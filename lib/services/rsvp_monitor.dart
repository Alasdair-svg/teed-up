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
    unawaited(checkForChanges());
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

      // 1) Read the primary + linked calendar IDs to scan.
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

      // 5) Persist updated cache.
      await _saveCache(prefs, cache);

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
  Future<List<RsvpChange>> checkForChanges() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final calendarIds = _resolveCalendarIds(prefs);
      if (calendarIds.isEmpty) {
        debugPrint(
            '[RsvpMonitor] No calendar selected — skipping manual check');
        return [];
      }

      final events = await _fetchUpcomingEventsForCalendars(calendarIds);
      if (events.isEmpty) return [];

      final cache = _loadCache(prefs);
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
      final calendarIds = appState.calendarsToMonitor;
      if (calendarIds.isEmpty) return 0;

      final calendarRounds = await (debugRoundFetcher ??
          CalendarService().getUpcomingRoundsForCalendars)(calendarIds);

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

  /// Resolves every calendar ID that should be scanned: the primary
  /// calendar plus any linked calendars (spec: multi-calendar account
  /// linking), deduplicated. Returns an empty list if no primary calendar
  /// has ever been selected.
  static List<String> _resolveCalendarIds(SharedPreferences prefs) {
    final primary = prefs.getString(_calendarIdKey);
    if (primary == null || primary.isEmpty) return [];

    final linked = prefs.getStringList(_linkedCalendarIdsKey) ?? [];
    return {primary, ...linked}.toList();
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

  /// Converts an [Attendee]'s platform-specific status to a string.
  static String _attendeeStatusToString(Attendee attendee) {
    // Try iOS status first, then Android.
    final iosStatus = attendee.iosAttendeeDetails?.attendanceStatus;
    if (iosStatus != null) {
      switch (iosStatus) {
        case IosAttendanceStatus.Accepted:
          return 'accepted';
        case IosAttendanceStatus.Declined:
          return 'declined';
        case IosAttendanceStatus.Tentative:
          return 'tentative';
        case IosAttendanceStatus.Pending:
        default:
          return 'pending';
      }
    }

    final androidStatus = attendee.androidAttendeeDetails?.attendanceStatus;
    if (androidStatus != null) {
      switch (androidStatus) {
        case AndroidAttendanceStatus.Accepted:
          return 'accepted';
        case AndroidAttendanceStatus.Declined:
          return 'declined';
        case AndroidAttendanceStatus.Tentative:
          return 'tentative';
        case AndroidAttendanceStatus.Invited:
        default:
          return 'pending';
      }
    }

    return 'pending';
  }

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
