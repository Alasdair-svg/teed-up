/// RSVP monitoring service for the All Teed Up golf booking app.
///
/// Periodically checks calendar event attendee statuses in the background
/// (via [Workmanager]) and compares them against a local SQLite cache.
/// When a status change is detected — especially a decline — it records
/// an alert and fires a local notification.
///
/// ## Architecture
///
/// ```
/// ┌─────────────┐    every 15 min    ┌──────────────┐
/// │  Workmanager │ ──────────────────►│ backgroundCb │
/// └─────────────┘                    └──────┬───────┘
///                                           │
///                    ┌──────────────────────┐│┌───────────────────┐
///                    │  CalendarService     │││  DatabaseHelper   │
///                    │  (live attendees)    │││  (rsvp_cache +    │
///                    └──────────────────────┘││   alerts table)   │
///                                           │└───────────────────┘
///                                           │
///                                    ┌──────▼──────────┐
///                                    │ NotificationSvc │
///                                    │ (decline alert) │
///                                    └─────────────────┘
/// ```
///
/// ## Usage
///
/// ```dart
/// final monitor = RsvpMonitor.instance;
/// await monitor.initialize();
///
/// // After creating a calendar event:
/// await monitor.registerEvent(eventId, {'john@x.com': 'pending'});
///
/// // Manual refresh (pull-to-refresh on alerts screen):
/// final changes = await monitor.checkForChanges();
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workmanager/workmanager.dart';

import '../models/golf_round.dart';
import '../models/player.dart';
import '../models/rsvp_change.dart';
import '../providers/app_state.dart';
import 'calendar_service.dart';
import 'notification_service.dart';

// =============================================================================
// Top-level callback (must be a top-level or static function for Workmanager)
// =============================================================================

/// Top-level dispatcher invoked by Workmanager on each background execution.
///
/// This function runs in its **own isolate** — it has no access to widget
/// state, Provider, or any in-memory singletons from the main isolate.
/// Everything it needs must be read from persistent storage.
@pragma('vm:entry-point')
void teedUpBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('[RsvpMonitor] Background task started: $taskName');

    try {
      if (taskName == RsvpMonitor.taskName) {
        await RsvpMonitor.backgroundCallback(taskName, inputData);
      }
      return true;
    } catch (e, stack) {
      debugPrint('[RsvpMonitor] Background task failed: $e');
      debugPrint('$stack');
      // Return true even on failure to prevent Workmanager from treating
      // this as a hard failure that might disable the task permanently.
      return true;
    }
  });
}

// =============================================================================
// RsvpMonitor
// =============================================================================

/// Signature of the calendar read [RsvpMonitor] depends on: every event in
/// one calendar between [start] and [end], in the map shape documented on
/// [RsvpMonitor.debugEventFetcher]'s production implementation.
typedef RsvpEventFetcher = Future<List<Map<String, dynamic>>> Function(
  String calendarId,
  DateTime start,
  DateTime end,
);

/// Monitors calendar event attendees for RSVP status changes.
///
/// Call [initialize] once at app start to register the periodic background
/// task. Use [registerEvent] after creating/updating calendar events to
/// snapshot the initial attendee state. Use [checkForChanges] for manual
/// pull-to-refresh.
class RsvpMonitor {
  /// Private constructor — use [instance].
  RsvpMonitor._();

  /// Singleton instance for use within the main isolate.
  static final RsvpMonitor instance = RsvpMonitor._();

  /// Unique task name registered with Workmanager.
  static const String taskName = 'com.teedup.rsvp_monitor';

  /// How often the background task runs (minutes).
  static const int _intervalMinutes = 15;

  /// How often the foreground timer polls (seconds).
  static const int _foregroundIntervalSeconds = 60;

  /// Foreground polling timer — active only when app is in foreground.
  Timer? _foregroundTimer;

  /// SharedPreferences key for the selected (primary) calendar ID.
  static const String _calendarIdKey = 'teed_up_selected_calendar_id';

  /// SharedPreferences key for additional linked calendar IDs (spec:
  /// multi-calendar account linking — same key `AppState` persists to).
  static const String _linkedCalendarIdsKey = 'teed_up_linked_calendar_ids';

  /// SharedPreferences key for the RSVP cache (JSON-encoded map).
  ///
  /// Structure: `{ eventId: { email: statusString, ... }, ... }`
  static const String _rsvpCacheKey = 'teed_up_rsvp_cache';

  /// SharedPreferences key for the last-seen timestamp of each cached
  /// event: `{ eventId: iso8601 }`. Drives [_pruneCache].
  static const String _rsvpCacheSeenKey = 'teed_up_rsvp_cache_seen';

  /// SharedPreferences key holding the persisted rounds list (same key
  /// `main.dart` writes). Read here — in the background isolate too — for
  /// the calendar id each round's event actually lives in.
  static const String _roundsKey = 'teed_up_rounds';

  /// SharedPreferences key for calendars found by the ⛳ discovery sweep.
  ///
  /// Cached so the 60-second foreground tick can include them without
  /// re-running the sweep. See [discoverGolfCalendars].
  static const String _discoveredCalendarIdsKey =
      'teed_up_discovered_calendar_ids';

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Initialises Workmanager and registers the periodic RSVP check task.
  ///
  /// The task runs approximately every 15 minutes. On iOS, the actual
  /// interval is determined by the OS (BGTaskScheduler) and may be longer.
  ///
  /// Safe to call multiple times — Workmanager deduplicates by [taskName].
  Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        teedUpBackgroundDispatcher,
      );

      await Workmanager().registerPeriodicTask(
        taskName,
        taskName,
        frequency: const Duration(minutes: _intervalMinutes),
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 5),
      );

      debugPrint(
        '[RsvpMonitor] Periodic task registered '
        '(every $_intervalMinutes min)',
      );
    } catch (e, stack) {
      debugPrint('[RsvpMonitor] Initialisation failed: $e');
      debugPrint('$stack');
    }
  }

  // ---------------------------------------------------------------------------
  // Foreground polling (app lifecycle-aware)
  // ---------------------------------------------------------------------------

  /// Starts the foreground polling timer.
  ///
  /// Should be called when the app transitions to the foreground
  /// (e.g. from [AppLifecycleListener.onResume] or [didChangeAppLifecycleState]).
  /// Polls every 60 seconds for near-real-time RSVP updates while the user
  /// is actively using the app.
  ///
  /// Safe to call multiple times — restarts the timer if already running.
  void startForegroundPolling() {
    stopForegroundPolling();
    debugPrint(
      '[RsvpMonitor] Foreground polling started '
      '(every ${_foregroundIntervalSeconds}s)',
    );
    _foregroundTimer = Timer.periodic(
      const Duration(seconds: _foregroundIntervalSeconds),
      (_) async {
        debugPrint('[RsvpMonitor] Foreground poll tick');
        await checkForChanges();
      },
    );

    // Poll once NOW, not only after the first 60-second tick. This is
    // called on cold start and on every resume — the two moments a user is
    // most likely to be opening the app *because* something changed. A
    // decline that arrived overnight should be on screen when they look,
    // not a minute after they look.
    //
    // This one poll carries the full ⛳ discovery sweep across every
    // calendar on the device; the recurring tick above does not. Cold
    // start and resume are once-per-session events where a few extra
    // calendar reads are affordable and the user is waiting for fresh
    // information anyway. Doing the same work 60 times an hour on a phone
    // with a dozen subscribed calendars is not.
    unawaited(checkForChanges(discoverAllCalendars: true));
  }

  /// Stops the foreground polling timer.
  ///
  /// Should be called when the app transitions to the background
  /// (e.g. from [AppLifecycleListener.onPause]). The Workmanager periodic
  /// task continues to run in the background at the 15-minute interval.
  void stopForegroundPolling() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
    debugPrint('[RsvpMonitor] Foreground polling stopped');
  }

  /// Whether the foreground polling timer is currently active.
  bool get isForegroundPollingActive => _foregroundTimer?.isActive ?? false;

  // ---------------------------------------------------------------------------
  // Background callback (runs in background isolate)
  // ---------------------------------------------------------------------------

  /// The core background logic invoked by Workmanager.
  ///
  /// 1. Reads the selected calendar ID from SharedPreferences.
  /// 2. Fetches upcoming golf rounds from the device calendar (next 30 days).
  /// 3. For each round, compares current attendee RSVP statuses against
  ///    the cached values in SharedPreferences.
  /// 4. For any status changes:
  ///    - If the new status is `declined`, fires a local notification.
  ///    - Records the change in the alerts cache.
  ///    - Updates the RSVP cache with the new status.
  ///
  /// This method is **static** because it runs in a background isolate with
  /// no access to instance state. All data is read from persistent storage.
  static Future<void> backgroundCallback(
    String taskId,
    Map<String, dynamic>? inputData,
  ) async {
    debugPrint('[RsvpMonitor] Executing background check...');

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1) Full ⛳ discovery sweep, then resolve every calendar to poll.
      //
      // The background task runs every 15 minutes, not every 60 seconds,
      // so it can afford the all-calendar sweep — and it is the only path
      // that runs while the app is closed, which is when most RSVPs
      // actually arrive.
      await discoverGolfCalendars(prefs);
      final calendarIds = _resolveCalendarIds(prefs);
      if (calendarIds.isEmpty) {
        debugPrint('[RsvpMonitor] No calendar selected — skipping check');
        return;
      }

      // 2) Fetch upcoming events from the device calendar(s).
      //
      // NOTE: CalendarService and DatabaseHelper are expected to be
      // implemented in sibling modules. When they are available, uncomment
      // the live integration below and remove the stub.
      //
      // In the background isolate we cannot use the main-isolate singletons,
      // so we create fresh instances that read directly from the device.
      final events = await _fetchUpcomingEventsForCalendars(calendarIds);
      if (events.isEmpty) {
        debugPrint('[RsvpMonitor] No upcoming events found');
        return;
      }

      // 3) Load the cached RSVP states.
      final cache = _loadCache(prefs);

      // 4) Compare and detect changes.
      final changes = <RsvpChange>[];

      for (final event in events) {
        final eventId = event['eventId'] as String;
        final eventTitle = event['title'] as String? ?? 'Golf Round';
        final eventDate = event['date'] as String? ?? '';
        final attendees =
            (event['attendees'] as Map<String, String>?) ?? <String, String>{};

        final cachedStatuses = cache[eventId] as Map<String, dynamic>? ?? {};

        for (final entry in attendees.entries) {
          final email = entry.key;
          final currentStatusStr = entry.value;
          final cachedStatusStr = cachedStatuses[email] as String?;

          // Skip if we've never cached this attendee (first time seeing them
          // is handled by registerEvent, not the background check).
          if (cachedStatusStr == null) continue;

          // Skip if status hasn't changed.
          if (currentStatusStr == cachedStatusStr) continue;

          final oldStatus = _parseStatus(cachedStatusStr);
          final newStatus = _parseStatus(currentStatusStr);

          final change = RsvpChange(
            eventId: eventId,
            playerName: event['attendeeNames']?[email] as String? ?? email,
            playerEmail: email,
            oldStatus: oldStatus,
            newStatus: newStatus,
            detectedAt: DateTime.now(),
          );

          changes.add(change);

          // Update the cache immediately.
          if (cache[eventId] == null) {
            cache[eventId] = <String, String>{};
          }
          (cache[eventId] as Map<String, dynamic>)[email] = currentStatusStr;

          debugPrint(
            '[RsvpMonitor] Status change: ${change.summary}',
          );

          // Fire notification for declines.
          if (change.isDecline) {
            await _notifyDecline(change, eventTitle, eventDate);
          }
        }
      }

      // 5) Persist updated cache, then drop entries for events that have
      // long since left the poll window.
      await _saveCache(prefs, cache);
      await _pruneCache(
        prefs,
        cache,
        events.map((e) => e['eventId'] as String),
      );

      // 6) Persist alerts.
      if (changes.isNotEmpty) {
        await _persistAlerts(prefs, changes);
      }

      debugPrint(
        '[RsvpMonitor] Background check complete. '
        '${changes.length} change(s) detected.',
      );
    } catch (e, stack) {
      debugPrint('[RsvpMonitor] Background callback error: $e');
      debugPrint('$stack');
      // Swallow — background tasks must not crash.
    }
  }

  // ---------------------------------------------------------------------------
  // Event registration
  // ---------------------------------------------------------------------------

  /// Caches the initial RSVP state for a newly created or updated event.
  ///
  /// Call this right after creating a calendar event so the background
  /// monitor has a baseline to compare against.
  ///
  /// [eventId] — The calendar event ID.
  /// [attendeeStatus] — A map of `{email: statusString}`.
  ///
  /// ```dart
  /// await monitor.registerEvent(
  ///   'cal-abc-123',
  ///   {'john@x.com': 'pending', 'jane@x.com': 'accepted'},
  /// );
  /// ```
  Future<void> registerEvent(
    String eventId,
    Map<String, String> attendeeStatus,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache = _loadCache(prefs);

      cache[eventId] = Map<String, String>.from(attendeeStatus);

      await _saveCache(prefs, cache);

      debugPrint(
        '[RsvpMonitor] Registered event $eventId with '
        '${attendeeStatus.length} attendee(s)',
      );
    } catch (e, stack) {
      debugPrint('[RsvpMonitor] registerEvent failed: $e');
      debugPrint('$stack');
    }
  }

  // ---------------------------------------------------------------------------
  // Manual check (pull-to-refresh)
  // ---------------------------------------------------------------------------

  /// Manually checks for RSVP changes — same logic as the background task
  /// but returns the changes directly for immediate UI update.
  ///
  /// Returns an empty list if no changes are detected or if the check fails.
  /// Set [discoverAllCalendars] to run the ⛳ sweep over every calendar on
  /// the device first. That costs one calendar read per calendar, so it is
  /// reserved for cold start, resume, and the background task — never the
  /// 60-second tick. See [discoverGolfCalendars].
  Future<List<RsvpChange>> checkForChanges({
    bool discoverAllCalendars = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (discoverAllCalendars) {
        await discoverGolfCalendars(prefs);
      }

      final calendarIds = _resolveCalendarIds(prefs);
      if (calendarIds.isEmpty) {
        debugPrint(
            '[RsvpMonitor] No calendar selected — skipping manual check');
        return [];
      }

      final events = await _fetchUpcomingEventsForCalendars(calendarIds);
      final cache = _loadCache(prefs);

      if (events.isEmpty) {
        // Nothing to compare, but housekeeping still runs: an install that
        // never reads a calendar again should not keep a cache growing
        // from a previous life. Pruning is by age, so an empty read costs
        // no live baseline (see [_pruneCache]).
        await _pruneCache(prefs, cache, const []);
        return [];
      }

      final changes = <RsvpChange>[];

      for (final event in events) {
        final eventId = event['eventId'] as String;
        final eventTitle = event['title'] as String? ?? 'Golf Round';
        final eventDate = event['date'] as String? ?? '';
        final attendees =
            (event['attendees'] as Map<String, String>?) ?? <String, String>{};

        final cachedStatuses = cache[eventId] as Map<String, dynamic>? ?? {};

        for (final entry in attendees.entries) {
          final email = entry.key;
          final currentStatusStr = entry.value;
          final cachedStatusStr = cachedStatuses[email] as String?;

          // No baseline yet — the event predates the seeding fix, or was
          // written by a version that never called registerEvent (which was
          // every version until 1.11.1+63). Record what we see now so the
          // NEXT change is detectable, instead of skipping this attendee
          // forever.
          if (cachedStatusStr == null) {
            cache[eventId] ??= <String, String>{};
            (cache[eventId] as Map<String, dynamic>)[email] = currentStatusStr;

            // One exception to staying quiet on a first observation: an
            // attendee already showing as declined is news the user has
            // never been given, because the old code could not give it.
            // Surfacing it once is right; staying silent repeats the
            // original failure.
            if (_parseStatus(currentStatusStr) == RsvpStatus.declined) {
              final change = RsvpChange(
                eventId: eventId,
                playerName: event['attendeeNames']?[email] as String? ?? email,
                playerEmail: email,
                oldStatus: RsvpStatus.pending,
                newStatus: RsvpStatus.declined,
                detectedAt: DateTime.now(),
              );
              changes.add(change);
              await _notifyDecline(change, eventTitle, eventDate);
            }
            continue;
          }

          if (currentStatusStr == cachedStatusStr) continue;

          final oldStatus = _parseStatus(cachedStatusStr);
          final newStatus = _parseStatus(currentStatusStr);

          final change = RsvpChange(
            eventId: eventId,
            playerName: event['attendeeNames']?[email] as String? ?? email,
            playerEmail: email,
            oldStatus: oldStatus,
            newStatus: newStatus,
            detectedAt: DateTime.now(),
          );

          changes.add(change);

          if (cache[eventId] == null) {
            cache[eventId] = <String, String>{};
          }
          (cache[eventId] as Map<String, dynamic>)[email] = currentStatusStr;

          if (change.isDecline) {
            await _notifyDecline(change, eventTitle, eventDate);
          }
        }
      }

      await _saveCache(prefs, cache);
      await _pruneCache(
        prefs,
        cache,
        events.map((e) => e['eventId'] as String),
      );

      if (changes.isNotEmpty) {
        await _persistAlerts(prefs, changes);
      }

      debugPrint(
        '[RsvpMonitor] Manual check complete. '
        '${changes.length} change(s) detected.',
      );

      return changes;
    } catch (e, stack) {
      debugPrint('[RsvpMonitor] Manual check failed: $e');
      debugPrint('$stack');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-import reconciliation (growth loop — spec Growth Loop 01a)
  // ---------------------------------------------------------------------------

  /// Reconciles the device calendar against [appState]'s known rounds: any
  /// ⛳-prefixed calendar event not already tracked there (by
  /// [GolfRound.calendarEventId]) is imported as a Recipient round —
  /// [GolfRound.isCreator] `false`, since it wasn't created via this
  /// device's own scan flow.
  ///
  /// This is the whole growth-loop mechanism: a round someone else created
  /// and invited this device to just appears next time the app looks at
  /// the calendar. No link, deep link, or hosted page involved — the
  /// calendar itself is the data channel.
  ///
  /// Runs in the **main isolate only** (it needs the live [AppState], so
  /// it's called from app startup, right after onboarding, and on every
  /// app-resume — never from the Workmanager background callback, which
  /// only has isolate-safe persistent storage to work with).
  ///
  /// Safe to call repeatedly — already-known events are skipped by id.
  /// Returns the number of newly-imported rounds.
  Future<int> reconcileWithCalendar(AppState appState) async {
    try {
      // The same union the monitor polls — including calendars found by
      // the ⛳ sweep — so a round living outside the primary/linked set is
      // imported and relinked, not just polled. Falls back to the live
      // AppState set alone if persistence is unreadable: a reconciliation
      // over fewer calendars beats none.
      final calendarIds = <String>{...appState.calendarsToMonitor};
      try {
        final prefs = await SharedPreferences.getInstance();
        calendarIds.addAll(_resolveCalendarIds(prefs));
      } catch (e) {
        debugPrint('[RsvpMonitor] Could not widen reconcile calendars: $e');
      }
      if (calendarIds.isEmpty) return 0;

      final calendarRounds = await (debugRoundFetcher ??
          CalendarService().getUpcomingRoundsForCalendars)(
        calendarIds.toList(),
      );

      final knownEventIds = appState.allRounds
          .map((r) => r.calendarEventId)
          .whereType<String>()
          .toSet();

      var imported = 0;
      var repaired = 0;
      var relinked = 0;
      for (final round in calendarRounds) {
        final eventId = round.calendarEventId;
        if (eventId == null) continue;

        // Already known: repair ownership rather than skipping outright.
        // Every round stored before the per-event check was written as
        // isCreator:false, and findMatchingRound skips non-creator rounds —
        // so an amended booking rescanned against one of them was treated as
        // brand new. Existing installs need correcting, not just new
        // imports.
        if (knownEventIds.contains(eventId)) {
          final existing =
              appState.allRounds.where((r) => r.calendarEventId == eventId);
          if (existing.isNotEmpty &&
              appState.repairIsCreator(existing.first.id, round.isCreator)) {
            repaired++;
          }
          // Backfill the calendar id on rounds stored before the field
          // existed. Without this a pre-existing round stays dependent on
          // its calendar happening to be the primary or a linked one —
          // which is the gap this whole change is about.
          if (existing.isNotEmpty &&
              existing.first.calendarId == null &&
              round.calendarId != null) {
            appState.linkCalendarEvent(
              existing.first.id,
              eventId,
              calendarId: round.calendarId,
            );
          }
          continue;
        }

        // Not known by event id — but it may still be a round we already
        // have, which lost its calendar link. Builds before 1.11.3+64
        // dropped calendarEventId when a booking was amended, orphaning
        // the event: the monitor had no handle on the round, so declines
        // on it were undetectable, and importing the event here would have
        // added a second copy of a round the user already has. Re-attach
        // instead of importing.
        final orphan = appState.findUnlinkedRound(
          course: round.courseName,
          date: round.date,
          teeTime: round.teeTime,
        );
        if (orphan != null) {
          appState.linkCalendarEvent(
            orphan.id,
            eventId,
            isCreator: round.isCreator,
            calendarId: round.calendarId,
          );
          relinked++;
          continue;
        }

        // Was `copyWith(isCreator: false)` — which made EVERY discovered
        // event somebody else's, so your own rounds came back read-only
        // after a reinstall. CalendarService now decides per event.
        appState.addRound(round);
        imported++;
      }

      if (imported > 0 || repaired > 0 || relinked > 0) {
        debugPrint(
          '[RsvpMonitor] Reconciliation imported $imported round(s), '
          'repaired ownership on $repaired, relinked $relinked orphan(s)',
        );
      }
      return imported;
    } catch (e, st) {
      debugPrint('[RsvpMonitor] reconcileWithCalendar error: $e\n$st');
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Cancel monitoring
  // ---------------------------------------------------------------------------

  /// Cancels all background RSVP monitoring tasks.
  ///
  /// Call this when the user disables decline alerts in settings, or when
  /// cleaning up resources.
  Future<void> cancelMonitoring() async {
    try {
      await Workmanager().cancelByUniqueName(taskName);
      debugPrint('[RsvpMonitor] Monitoring cancelled');
    } catch (e, stack) {
      debugPrint('[RsvpMonitor] Cancel failed: $e');
      debugPrint('$stack');
    }
  }

  // ---------------------------------------------------------------------------
  // Cache helpers (SharedPreferences-backed — works in background isolates)
  // ---------------------------------------------------------------------------

  /// Loads the RSVP cache from SharedPreferences.
  ///
  /// Returns a mutable map: `{ eventId: { email: statusString } }`.
  static Map<String, dynamic> _loadCache(SharedPreferences prefs) {
    final raw = prefs.getString(_rsvpCacheKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[RsvpMonitor] Cache decode failed: $e');
      return {};
    }
  }

  /// Saves the RSVP cache to SharedPreferences.
  static Future<void> _saveCache(
    SharedPreferences prefs,
    Map<String, dynamic> cache,
  ) async {
    await prefs.setString(_rsvpCacheKey, jsonEncode(cache));
  }

  /// How long a cache entry survives after the last poll that saw its
  /// event.
  ///
  /// Comfortably wider than [pollWindow] itself (14 days back + 30 days
  /// ahead): an entry is only dropped once its event has been out of sight
  /// for longer than the window could possibly explain.
  static const int _cacheRetentionDays = 45;

  /// Drops RSVP baselines for events that have long since left the poll
  /// window, and the last-seen records that go with them.
  ///
  /// The cache was never pruned at all: every event ever polled kept an
  /// entry in SharedPreferences forever, so the JSON blob the monitor
  /// decodes and re-encodes on *every* 60-second tick grew without bound
  /// for the life of the install.
  ///
  /// Pruning is by "not seen for [_cacheRetentionDays]", not by "not in
  /// this poll's results". The naive version is actively dangerous: one
  /// failed calendar read — permission revoked, a provider hiccup, an
  /// account temporarily offline — returns zero events, which would wipe
  /// every baseline in the cache. The next successful poll would then see
  /// every attendee for the first time again. That is bug (a), the
  /// un-seeded baseline, recreated by the fix for a memory leak.
  ///
  /// [observedEventIds] are the events this poll actually read.
  static Future<void> _pruneCache(
    SharedPreferences prefs,
    Map<String, dynamic> cache,
    Iterable<String> observedEventIds,
  ) async {
    try {
      final now = DateTime.now();
      final seen = <String, DateTime>{};

      final raw = prefs.getString(_rsvpCacheSeenKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final at = DateTime.tryParse(value as String? ?? '');
            if (at != null) seen['$key'] = at;
          });
        }
      }

      for (final id in observedEventIds) {
        seen[id] = now;
      }

      // Entries written before this bookkeeping existed have no last-seen
      // stamp. Stamping them now gives them a full retention period rather
      // than deleting a baseline the moment the app updates.
      for (final id in cache.keys) {
        seen.putIfAbsent(id, () => now);
      }

      final cutoff = now.subtract(const Duration(days: _cacheRetentionDays));
      final stale = seen.entries
          .where((e) => e.value.isBefore(cutoff))
          .map((e) => e.key)
          .toList();

      for (final id in stale) {
        cache.remove(id);
        seen.remove(id);
      }

      // A last-seen stamp for an event with no cache entry is dead weight.
      seen.removeWhere((id, _) => !cache.containsKey(id));

      if (stale.isNotEmpty) {
        await _saveCache(prefs, cache);
        debugPrint(
          '[RsvpMonitor] Pruned ${stale.length} stale RSVP cache entr'
          '${stale.length == 1 ? 'y' : 'ies'}',
        );
      }

      await prefs.setString(
        _rsvpCacheSeenKey,
        jsonEncode(seen.map((k, v) => MapEntry(k, v.toIso8601String()))),
      );
    } catch (e) {
      // Pruning is housekeeping. It must never cost us a poll.
      debugPrint('[RsvpMonitor] Cache prune failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Alert persistence (SharedPreferences — no SQLite in background isolate)
  // ---------------------------------------------------------------------------

  /// SharedPreferences key for the persisted alerts list.
  static const String _alertsKey = 'teed_up_alerts';

  /// Appends new [changes] to the persisted alerts list.
  ///
  /// Alerts are stored as a JSON array in SharedPreferences. This works
  /// reliably in background isolates where opening a fresh SQLite database
  /// connection can be problematic.
  ///
  /// The list is capped at 200 entries to prevent unbounded growth.
  static Future<void> _persistAlerts(
    SharedPreferences prefs,
    List<RsvpChange> changes,
  ) async {
    try {
      final raw = prefs.getString(_alertsKey);
      final existing = <Map<String, dynamic>>[];

      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        existing.addAll(decoded.cast<Map<String, dynamic>>());
      }

      for (final change in changes) {
        existing.add(change.toJson());
      }

      // Cap at 200 most recent.
      const maxAlerts = 200;
      final trimmed = existing.length > maxAlerts
          ? existing.sublist(existing.length - maxAlerts)
          : existing;

      await prefs.setString(_alertsKey, jsonEncode(trimmed));

      debugPrint(
        '[RsvpMonitor] Persisted ${changes.length} alert(s) '
        '(total: ${trimmed.length})',
      );
    } catch (e) {
      debugPrint('[RsvpMonitor] Alert persistence failed: $e');
    }
  }

  /// Loads all persisted alerts from SharedPreferences.
  ///
  /// Returns an empty list on failure.
  static Future<List<RsvpChange>> loadPersistedAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_alertsKey);
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((json) => RsvpChange.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[RsvpMonitor] Failed to load persisted alerts: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Calendar integration (stub — wire up when CalendarService is built)
  // ---------------------------------------------------------------------------

  /// Fetches upcoming events from the device calendar.
  ///
  /// Returns a list of event maps with the structure:
  /// ```json
  /// {
  ///   "eventId": "...",
  ///   "title": "Golf at Dubai Hills",
  ///   "date": "2026-06-15",
  ///   "attendees": { "john@x.com": "accepted", "jane@x.com": "declined" },
  ///   "attendeeNames": { "john@x.com": "John Smith", "jane@x.com": "Jane Doe" }
  /// }
  /// ```
  static Future<List<Map<String, dynamic>>> _fetchEventsFromDevice(
    String calendarId,
    DateTime start,
    DateTime end,
  ) async {
    try {
      final plugin = DeviceCalendarPlugin();

      final result = await plugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(
          startDate: TZDateTime.from(start, local),
          endDate: TZDateTime.from(end, local),
        ),
      );

      if (result.data == null) return [];

      return result.data!
          .map((event) {
            final attendees = <String, String>{};
            final attendeeNames = <String, String>{};

            for (final a in event.attendees ?? <Attendee?>[]) {
              if (a == null) continue;
              final email = a.emailAddress ?? '';
              if (email.isEmpty) continue;
              attendees[email] = _attendeeStatusToString(a);
              attendeeNames[email] = a.name ?? email;
            }

            return {
              'eventId': event.eventId ?? '',
              'title': event.title ?? '',
              'date': event.start?.toIso8601String().split('T').first ?? '',
              'attendees': attendees,
              'attendeeNames': attendeeNames,
            };
          })
          .where((e) => (e['eventId'] as String).isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[RsvpMonitor] _fetchEventsFromDevice error: $e');
      return [];
    }
  }

  /// Resolves every calendar ID that should be polled on a routine tick.
  ///
  /// The union of four sources, any one of which is sufficient to bring a
  /// round under monitoring:
  ///
  ///   1. the primary (selected) calendar;
  ///   2. calendars the user explicitly linked;
  ///   3. **the calendar each stored round's event actually lives in**
  ///      ([GolfRound.calendarId]);
  ///   4. calendars the ⛳ discovery sweep has found events in
  ///      ([discoverGolfCalendars]).
  ///
  /// (1) and (2) alone were the whole monitored set, and that was the third
  /// hiding place for an undetected decline. On the reporting device the
  /// linked calendars were Birthdays and UAE Holidays — neither can carry
  /// an invitation — so effectively only the primary calendar was read. An
  /// event anywhere else was invisible forever.
  ///
  /// Note the missing early return: this used to yield an empty list, and
  /// therefore poll nothing at all, whenever no primary calendar had been
  /// selected — even with rounds on disk naming exactly which calendar to
  /// look in.
  static List<String> _resolveCalendarIds(SharedPreferences prefs) {
    final ids = <String>{};

    final primary = prefs.getString(_calendarIdKey);
    if (primary != null && primary.isNotEmpty) ids.add(primary);

    ids.addAll(prefs.getStringList(_linkedCalendarIdsKey) ?? const []);
    ids.addAll(storedRoundCalendarIds(prefs));
    ids.addAll(prefs.getStringList(_discoveredCalendarIdsKey) ?? const []);

    ids.removeWhere((id) => id.isEmpty);
    return ids.toList();
  }

  /// Every distinct [GolfRound.calendarId] on the persisted rounds.
  ///
  /// Deliberately hand-rolled rather than routed through
  /// [GolfRound.fromJson]: this runs in the background isolate, one round
  /// written by a future (or past) schema must not take the whole poll
  /// down with it, and the only field needed is one string.
  @visibleForTesting
  static Set<String> storedRoundCalendarIds(SharedPreferences prefs) {
    final raw = prefs.getString(_roundsKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};

      final ids = <String>{};
      for (final entry in decoded) {
        if (entry is! Map) continue;
        // Rounds stored before this field existed simply have no value —
        // that is the expected migration state, not an error. The ⛳ sweep
        // is what finds those.
        final id = entry['calendarId'];
        if (id is String && id.isNotEmpty) ids.add(id);
      }
      return ids;
    } catch (e) {
      debugPrint('[RsvpMonitor] Could not read stored round calendars: $e');
      return {};
    }
  }

  /// Test seam for the device calendar list. Null in production.
  @visibleForTesting
  static Future<List<String>> Function()? debugCalendarLister;

  /// Every calendar id on the device.
  static Future<List<String>> _listAllCalendarIds() async {
    try {
      final result = await DeviceCalendarPlugin().retrieveCalendars();
      return (result.data ?? [])
          .map((c) => c.id)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[RsvpMonitor] Could not list calendars: $e');
      return [];
    }
  }

  /// Scans **every** calendar on the device for ⛳-prefixed events inside
  /// [pollWindow] and caches the ids of those that have any.
  ///
  /// The second, independent discovery path. A calendar id recorded on a
  /// round is the precise route; this is the one that still works when no
  /// id was ever recorded — a round imported by an old build, a calendar
  /// the user has since switched away from, an event created on another
  /// device and synced in. Either path alone is enough to bring a round
  /// under monitoring, which is the point: they fail in different ways.
  ///
  /// **Cost.** This reads N calendars instead of the two or three the
  /// routine poll reads, so it is deliberately NOT run on the 60-second
  /// foreground tick. It runs on cold start, on app resume, and in the
  /// 15-minute background task; the tick then polls the cached result via
  /// [_resolveCalendarIds] for free.
  ///
  /// Returns the discovered ids (already-known calendars excluded — they
  /// are polled regardless).
  static Future<List<String>> discoverGolfCalendars(
    SharedPreferences prefs,
  ) async {
    try {
      final all = await (debugCalendarLister ?? _listAllCalendarIds)();
      if (all.isEmpty) return [];

      final known = <String>{
        prefs.getString(_calendarIdKey) ?? '',
        ...prefs.getStringList(_linkedCalendarIdsKey) ?? const [],
        ...storedRoundCalendarIds(prefs),
      }..removeWhere((id) => id.isEmpty);

      final window = pollWindow(DateTime.now());
      final fetch = debugEventFetcher ?? _fetchEventsFromDevice;

      final found = <String>[];
      for (final calendarId in all) {
        if (known.contains(calendarId)) continue;
        final events = await fetch(calendarId, window.start, window.end);
        final carriesGolf = events.any(
          (e) => (e['title'] as String? ?? '').contains(
            CalendarService.eventPrefix,
          ),
        );
        if (carriesGolf) found.add(calendarId);
      }

      await prefs.setStringList(_discoveredCalendarIdsKey, found);
      if (found.isNotEmpty) {
        debugPrint(
          '[RsvpMonitor] ⛳ sweep found ${found.length} unlisted '
          'calendar(s) carrying golf events: ${found.join(', ')}',
        );
      }
      return found;
    } catch (e, st) {
      debugPrint('[RsvpMonitor] discoverGolfCalendars error: $e\n$st');
      return [];
    }
  }

  /// How far ahead the monitor polls for events to watch.
  static const int _lookAheadDays = 30;

  /// How far BACK the monitor polls.
  ///
  /// This was 0 — the window started at "now", so a round was dropped from
  /// monitoring the instant its tee time passed. That is precisely when
  /// people drop out: a decline that arrives on the morning of a round, or
  /// after the group has teed off, could never be seen, because the event
  /// carrying it was no longer being read. It also meant a played round's
  /// calendar event vanished from every reconciliation pass, so ownership
  /// on it could never be repaired.
  static const int _lookBackDays = 14;

  /// The calendar window the monitor reads on each poll.
  @visibleForTesting
  static ({DateTime start, DateTime end}) pollWindow(DateTime now) => (
        start: now.subtract(const Duration(days: _lookBackDays)),
        end: now.add(const Duration(days: _lookAheadDays)),
      );

  /// Test seam: replaces the device-calendar read. Null in production.
  @visibleForTesting
  static RsvpEventFetcher? debugEventFetcher;

  /// Test seam for [reconcileWithCalendar]'s calendar read. Null in
  /// production, where it reads [CalendarService].
  @visibleForTesting
  static Future<List<GolfRound>> Function(List<String>)? debugRoundFetcher;

  /// Reads every event in [pollWindow] across every calendar in
  /// [calendarIds] (spec: multi-calendar account linking), de-duplicated
  /// by event id.
  static Future<List<Map<String, dynamic>>> _fetchUpcomingEventsForCalendars(
    List<String> calendarIds,
  ) async {
    final window = pollWindow(DateTime.now());
    final fetch = debugEventFetcher ?? _fetchEventsFromDevice;

    final seen = <String>{};
    final events = <Map<String, dynamic>>[];

    for (final calendarId in calendarIds) {
      final calendarEvents = await fetch(calendarId, window.start, window.end);
      for (final event in calendarEvents) {
        if (seen.add(event['eventId'] as String)) events.add(event);
      }
    }

    return events;
  }

  /// Converts an [Attendee]'s status to the cache string.
  ///
  /// Delegates to [CalendarService.attendeeStatusString] — the single
  /// implementation. This file used to carry its own copy with a DIFFERENT
  /// mapping (`tentative` collapsed to `pending`, and a `pending` fallback
  /// where CalendarService returned `unknown`), which is a latent decline
  /// bug of exactly the kind this app has now shipped three times: the
  /// baseline in the cache is written by CalendarService and every
  /// subsequent poll is read by this class. Two mappings that disagree
  /// about a status make the comparison between them meaningless.
  static String _attendeeStatusToString(Attendee attendee) =>
      CalendarService.attendeeStatusString(attendee);

  /// Test seam over [_attendeeStatusToString], so a test can assert that
  /// this class and [CalendarService] still agree. Re-introducing a second
  /// mapping here is meant to fail loudly.
  @visibleForTesting
  static String attendeeStatusStringForTest(Attendee attendee) =>
      _attendeeStatusToString(attendee);

  // ---------------------------------------------------------------------------
  // Status helpers
  // ---------------------------------------------------------------------------

  /// Parses a status string into an [RsvpStatus] enum value.
  ///
  /// Falls back to [RsvpStatus.pending] for unrecognised values.
  static RsvpStatus _parseStatus(String? status) {
    if (status == null) return RsvpStatus.pending;

    switch (status.toLowerCase().trim()) {
      case 'accepted':
      case 'confirmed':
      case 'tentativelyaccepted':
        return RsvpStatus.accepted;
      case 'declined':
      case 'rejected':
        return RsvpStatus.declined;
      case 'pending':
      case 'none':
      case 'invited':
      case 'tentative':
      // Read but unreadable — the attendee carries no platform status
      // details at all. Not attending, not declined.
      case 'unknown':
      default:
        return RsvpStatus.pending;
    }
  }

  // ---------------------------------------------------------------------------
  // Notification helper
  // ---------------------------------------------------------------------------

  /// Fires a decline notification via [NotificationService].
  ///
  /// This initialises a fresh NotificationService instance because in
  /// background isolates the main-isolate singleton may not be available.
  ///
  /// No-ops if the user has turned off decline alerts in Settings — read
  /// directly from SharedPreferences (same key `main.dart` persists) since
  /// background isolates can't share the live `AppState` instance.
  static Future<void> _notifyDecline(
    RsvpChange change,
    String eventTitle,
    String eventDate,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alertsEnabled = prefs.getBool('teed_up_decline_alerts') ?? true;
      if (!alertsEnabled) {
        debugPrint(
            '[RsvpMonitor] Decline alerts disabled — skipping notification.');
        return;
      }

      final notificationService = NotificationService.instance;
      await notificationService.initialize();
      await notificationService.showDeclineNotification(
        change,
        courseName: eventTitle,
        date: eventDate,
      );
    } catch (e) {
      debugPrint('[RsvpMonitor] Decline notification failed: $e');
    }
  }
}
