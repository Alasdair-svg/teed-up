/// RSVP monitoring service for the Teed Up golf booking app.
///
/// Periodically checks calendar event attendee statuses in the background
/// (via [Workmanager]) and compares them against a local SQLite cache.
/// When a status change is detected — especially a decline — it records
/// an alert and fires a local notification.
///
/// ## Architecture
///
/// ```
/// ┌─────────────┐    every 30 min    ┌──────────────┐
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

import 'dart:convert';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workmanager/workmanager.dart';

import '../models/player.dart';
import '../models/rsvp_change.dart';
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
  static const int _intervalMinutes = 30;


  /// SharedPreferences key for the selected calendar ID.
  static const String _calendarIdKey = 'teed_up_selected_calendar_id';

  /// SharedPreferences key for the RSVP cache (JSON-encoded map).
  ///
  /// Structure: `{ eventId: { email: statusString, ... }, ... }`
  static const String _rsvpCacheKey = 'teed_up_rsvp_cache';

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Initialises Workmanager and registers the periodic RSVP check task.
  ///
  /// The task runs approximately every 30 minutes. On iOS, the actual
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
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
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

      // 1) Read the selected calendar ID.
      final calendarId = prefs.getString(_calendarIdKey);
      if (calendarId == null || calendarId.isEmpty) {
        debugPrint('[RsvpMonitor] No calendar selected — skipping check');
        return;
      }

      // 2) Fetch upcoming events from the device calendar.
      //
      // NOTE: CalendarService and DatabaseHelper are expected to be
      // implemented in sibling modules. When they are available, uncomment
      // the live integration below and remove the stub.
      //
      // In the background isolate we cannot use the main-isolate singletons,
      // so we create fresh instances that read directly from the device.
      final events = await _fetchUpcomingEvents(calendarId);
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

      final calendarId = prefs.getString(_calendarIdKey);
      if (calendarId == null || calendarId.isEmpty) {
        debugPrint('[RsvpMonitor] No calendar selected — skipping manual check');
        return [];
      }

      final events = await _fetchUpcomingEvents(calendarId);
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

          if (cachedStatusStr == null || currentStatusStr == cachedStatusStr) {
            continue;
          }

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
  static Future<List<Map<String, dynamic>>> _fetchUpcomingEvents(
    String calendarId,
  ) async {
    try {
      final plugin = DeviceCalendarPlugin();
      final now = DateTime.now();
      final end = now.add(const Duration(days: 30));

      final result = await plugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(
          startDate: TZDateTime.from(now, local),
          endDate: TZDateTime.from(end, local),
        ),
      );

      if (result.data == null) return [];

      return result.data!.map((event) {
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
      }).where((e) => (e['eventId'] as String).isNotEmpty).toList();
    } catch (e) {
      debugPrint('[RsvpMonitor] _fetchUpcomingEvents error: $e');
      return [];
    }
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
  static Future<void> _notifyDecline(
    RsvpChange change,
    String eventTitle,
    String eventDate,
  ) async {
    try {
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
