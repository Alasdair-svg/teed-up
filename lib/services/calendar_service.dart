/// Calendar service for the All Teed Up golf booking app.
///
/// Wraps the [device_calendar] package to create, find, update, and query
/// golf round calendar events. Supports all calendar providers (iCloud,
/// Google, Outlook, Exchange, CalDAV) through the unified native API.
///
/// All events created by All Teed Up use a ⛳ prefix in the title for
/// reliable identification when scanning upcoming events.
library;

import 'dart:io' show Platform;

import 'package:device_calendar/device_calendar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

import '../models/family_member.dart';
import '../models/golf_round.dart';
import '../models/player.dart';
import '../models/player_diff.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AttendeeStatus — normalised RSVP status across platforms
// ─────────────────────────────────────────────────────────────────────────────

/// Normalised attendee RSVP status that abstracts away platform differences
/// between [IosAttendanceStatus] and [AndroidAttendanceStatus].
enum AttendeeStatus {
  /// Attendee has accepted the invitation.
  accepted,

  /// Attendee has declined the invitation.
  declined,

  /// Attendee has tentatively accepted.
  tentative,

  /// Attendee has not yet responded.
  pending,

  /// Status is unknown or could not be determined.
  unknown,
}

// ─────────────────────────────────────────────────────────────────────────────
// CalendarService
// ─────────────────────────────────────────────────────────────────────────────

/// Service that manages device calendar operations for golf rounds.
///
/// Uses [DeviceCalendarPlugin] to interact with the native calendar store.
/// All methods are resilient — errors are caught, logged, and returned as
/// `null` / empty results rather than thrown.
///
/// Usage:
/// ```dart
/// final service = CalendarService();
/// final calendars = await service.getAvailableCalendars();
/// final eventId = await service.createGolfEvent(round, calendars.first.id!);
/// ```
class CalendarService {
  /// Creates a [CalendarService].
  ///
  /// Optionally accepts a [DeviceCalendarPlugin] for testing / DI.
  CalendarService({DeviceCalendarPlugin? plugin})
      : _plugin = plugin ?? DeviceCalendarPlugin();

  /// The underlying device calendar plugin instance.
  final DeviceCalendarPlugin _plugin;

  /// Number of times this service has touched the calendar permission API.
  ///
  /// Instrumentation, not decoration: a permission prompt appearing before
  /// onboarding explained why is caused by SOMETHING calling into the
  /// calendar API too early, and reading the code repeatedly failed to find
  /// which. A counter makes it testable.
  static int permissionChecks = 0;

  /// Prefix used in event titles to identify All Teed Up events.
  static const String eventPrefix = '⛳';

  /// Default golf round duration in minutes (4.5 hours = 270 minutes).
  static const int _roundDurationMinutes = 270;

  /// Store links for the growth-loop invite footer (see "The Growth Loop"
  /// design doc, Section 01). No link is ever placed inline in the invite
  /// title or as a tappable button — on-device testing confirmed neither
  /// custom URL schemes nor Android `intent://` links render as tappable
  /// in any calendar app's event view, so a plain `https://` line is the
  /// only reliably-tappable form available at all.
  ///
  /// Apple ID 6780447827, confirmed against App Store Connect. This was
  /// previously a literal `id0000000000` placeholder, so every invite the
  /// app has ever sent carried a link to a dead App Store page.
  static const String _appStoreUrl = 'https://apps.apple.com/app/id6780447827';
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.teedup.golf';

  // ─────────────────────────────────────────────────────────────────────────
  // Permissions
  // ─────────────────────────────────────────────────────────────────────────

  /// Ensures calendar permissions are granted.
  ///
  /// Returns `true` if permissions are available (or were just granted),
  /// `false` otherwise.
  /// Confirms an event actually exists in the calendar after writing it.
  ///
  /// Searches a window around the expected start rather than trusting the
  /// write's return value, because the plugin can report success for an
  /// event that never lands.
  Future<bool> verifyEventExists({
    required String calendarId,
    required String eventId,
    required TZDateTime around,
  }) async {
    try {
      final params = RetrieveEventsParams(
        startDate: around.subtract(const Duration(days: 1)),
        endDate: around.add(const Duration(days: 1)),
      );
      final res = await _plugin.retrieveEvents(calendarId, params);
      final found = res.data?.any((e) => e.eventId == eventId) ?? false;
      if (!found && res.errors.isNotEmpty) {
        debugPrint(
          '[CalendarService] verify read failed: '
          '${res.errors.map((e) => e.errorMessage).join(', ')}',
        );
      }
      return found;
    } catch (e) {
      debugPrint('[CalendarService] verifyEventExists threw: $e');
      // Unable to verify is not the same as verified-absent. Treat an
      // unreadable calendar as inconclusive rather than reporting a
      // failure for an event that may well be there.
      return true;
    }
  }

  /// A one-line, user-showable report of why the calendar list is empty.
  ///
  /// Four rounds of remote debugging failed because the app said only "no
  /// calendars found", which is a symptom shared by several very different
  /// causes: permission never granted, permission granted but the plugin
  /// gate disagreeing, or the OS genuinely returning nothing. This states
  /// which, so a screenshot is evidence rather than another guess.
  Future<String> diagnoseCalendarAccess() async {
    final parts = <String>[];
    try {
      final ph = await Permission.calendarFullAccess.status;
      parts.add('OS:${ph.name}');
    } catch (_) {
      parts.add('OS:err');
    }
    try {
      final has = await _plugin.hasPermissions();
      parts.add('gate:${has.data == true ? "y" : "n"}');
    } catch (_) {
      parts.add('gate:err');
    }
    // Report EVERY stage. The previous version reported only the raw count,
    // which said 21 while the screen showed none — proving the loss happened
    // somewhere downstream but not where. Each stage is measured separately
    // so the next screenshot names the exact step that drops them.
    try {
      final res = await _plugin.retrieveCalendars();
      final raw = res.data?.toList() ?? const <Calendar>[];
      parts.add('raw:${raw.length}');
      parts.add('withId:${raw.where((c) => c.id != null).length}');
      if (raw.isNotEmpty) {
        final f = raw.first;
        parts.add('id0:${f.id ?? "null"}');
        parts.add('nm0:${f.name ?? "null"}');
      }
      if (res.errors.isNotEmpty) {
        parts.add('e:${res.errors.first.errorMessage}');
      }
    } catch (e) {
      parts.add('raw:threw ${e.runtimeType}');
    }
    try {
      parts.add('svc:${(await getAvailableCalendars()).length}');
    } catch (e) {
      parts.add('svc:threw');
    }
    try {
      final g = await getAvailableCalendarsGrouped();
      parts.add('grp:${g.length}/${g.values.expand((v) => v).length}');
    } catch (e) {
      parts.add('grp:threw');
    }
    return parts.join('  ');
  }

  /// Public wrapper so onboarding can prime the plugin's own permission
  /// gate at the point the user has just agreed, rather than lazily on the
  /// first read — which is too late if the read is what populates the UI.
  Future<bool> ensureCalendarPermission() => _ensurePermissions();

  Future<bool> _ensurePermissions() async {
    try {
      permissionChecks++;
      var permResult = await _plugin.hasPermissions();
      if (permResult.data == true) return true;

      permResult = await _plugin.requestPermissions();
      return permResult.data == true;
    } catch (e, st) {
      debugPrint('[CalendarService] Permission check failed: $e\n$st');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Calendar retrieval
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns all calendars available on the device.
  ///
  /// This includes iCloud, Google, Outlook, Exchange, and any other
  /// CalDAV/ActiveSync accounts configured on the device.
  ///
  /// Returns an empty list if permissions are denied or an error occurs.
  Future<List<Calendar>> getAvailableCalendars() async {
    try {
      // The permission check is advisory here, NOT a gate.
      //
      // Bailing out on it returned an empty list while a direct
      // retrieveCalendars() on the same device returned 21 — the on-screen
      // diagnostic showed `plugin: granted · returned: 21` moments after
      // this had produced nothing. The read itself is the authority on
      // whether the calendars are reachable, so ask for permission if it
      // looks missing, then read regardless of what the gate claims.
      await _ensurePermissions();

      var result = await _plugin.retrieveCalendars();

      // Retry once on an empty result. Permission is granted moments
      // earlier in onboarding, and on Android the calendar provider is not
      // reliably ready the instant the grant returns — the first read comes
      // back empty and a read a moment later returns everything. Without
      // this the user is told they have no calendars and has no way back.
      if ((result.data?.isEmpty ?? true)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        result = await _plugin.retrieveCalendars();
      }

      // Use the data whenever there IS data, regardless of isSuccess.
      //
      // This previously required `result.isSuccess && result.data != null`
      // and returned an empty list otherwise. On a real device the plugin
      // returned 21 calendars TOGETHER WITH a non-success flag — so every
      // one of them was discarded here, and the app reported "No calendars
      // found on this device" on a phone full of them. The on-screen
      // diagnostic proved it: `OS: granted · plugin: granted · returned:
      // 21`, because the diagnostic read result.data directly and this did
      // not.
      //
      // A non-fatal error alongside good data is common in device_calendar
      // (one unreadable account among several). Log it and keep the data;
      // discarding everything because part of the read complained is worse
      // than surfacing what the OS did hand us.
      if (result.errors.isNotEmpty) {
        debugPrint(
          '[CalendarService] retrieveCalendars reported '
          '${result.errors.length} error(s), continuing with '
          '${result.data?.length ?? 0} calendar(s): '
          '${result.errors.map((e) => e.errorMessage).join(', ')}',
        );
      }

      final data = result.data;
      if (data != null && data.isNotEmpty) return data.toList();

      debugPrint(
        '[CalendarService] No calendars returned. isSuccess='
        '${result.isSuccess} errors='
        '${result.errors.map((e) => e.errorMessage).join(', ')}',
      );
      return [];
    } catch (e, st) {
      debugPrint('[CalendarService] getAvailableCalendars error: $e\n$st');
      return [];
    }
  }

  /// Returns [getAvailableCalendars] grouped by account (spec: multi-calendar
  /// account linking) — e.g. all calendars under a single Google or iCloud
  /// account grouped together, keyed by `"{accountName} ({accountType})"`.
  ///
  /// Calendars with no account info are grouped under `"Other"`.
  Future<Map<String, List<Calendar>>> getAvailableCalendarsGrouped() async {
    final calendars = await getAvailableCalendars();
    final grouped = <String, List<Calendar>>{};

    // TODO(diagnostic): remove once we've confirmed what device_calendar
    // actually reports for accountName/accountType on real multi-account
    // Android devices — reported grouping everything under "Other" even
    // with multiple Google accounts present, which the plugin's fields
    // shouldn't cause. Check via `adb logcat | grep CalendarService`.
    for (final calendar in calendars) {
      debugPrint(
        '[CalendarService] raw calendar: id=${calendar.id} '
        'name=${calendar.name} accountName=${calendar.accountName} '
        'accountType=${calendar.accountType} '
        'isReadOnly=${calendar.isReadOnly} isDefault=${calendar.isDefault}',
      );
    }

    for (final calendar in calendars) {
      final name = calendar.accountName?.trim();
      final type = calendar.accountType?.trim();
      final key = (name == null || name.isEmpty)
          ? 'Other'
          : (type == null || type.isEmpty ? name : '$name ($type)');
      grouped.putIfAbsent(key, () => []).add(calendar);
    }

    return grouped;
  }

  /// Returns the set of email addresses this device's own calendar accounts
  /// are signed in under (lowercased), derived from each [Calendar]'s
  /// `accountName` — for Google and Exchange accounts this is the login
  /// email directly; other providers may not populate it usefully.
  ///
  /// Used to work out which player in a round's roster is "you" (Creator/
  /// Recipient self-identity) by matching against [Player.email]. Returns
  /// an empty set on permission failure or if no account looks like an
  /// email — callers should treat that as "can't determine self," not an
  /// error, and degrade gracefully rather than block on it.
  ///
  /// Known caveat: `accountName` has been observed not reporting reliably
  /// on some real multi-Google-account Android devices (see the diagnostic
  /// logging in [getAvailableCalendarsGrouped]) — this method inherits that
  /// same data-reliability risk.
  Future<Set<String>> getOwnAccountEmails() async {
    final calendars = await getAvailableCalendars();
    final emails = <String>{};
    for (final calendar in calendars) {
      final name = calendar.accountName?.trim().toLowerCase();
      if (name != null && name.contains('@')) emails.add(name);
    }
    return emails;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Create event
  // ─────────────────────────────────────────────────────────────────────────

  /// Creates a calendar event for the given [round] in the specified calendar.
  ///
  /// The event includes:
  /// - **Title**: `⛳ {course} | {teeTime} | {player1}, {player2}, ...`
  /// - **Duration**: 5 hours from tee time
  /// - **Location**: course name
  /// - **Description**: players list, booking ref, open slots info
  /// - **Attendees**: players with valid emails added as Required attendees
  ///
  /// If [notifyFamilyMembers] is non-empty, each member is added as an
  /// [AttendeeRole.Optional] attendee so they receive the calendar invite
  /// as information only (they're never marked as a player).
  ///
  /// [notifyFamily]/[familyName]/[familyEmail] are a legacy single-contact
  /// form retained for older call sites — merged into [notifyFamilyMembers].
  ///
  /// Returns the created event's ID, or `null` on failure.
  Future<String?> createGolfEvent(
    GolfRound round,
    String calendarId, {
    List<FamilyMember>? notifyFamilyMembers,
    bool notifyFamily = false,
    String? familyName,
    String? familyEmail,
    List<int>? reminderMinutes,
  }) async {
    try {
      if (!await _ensurePermissions()) return null;

      final mergedFamily = <FamilyMember>[
        ...?notifyFamilyMembers,
        if (notifyFamily && familyEmail != null && familyEmail.isNotEmpty)
          FamilyMember(name: familyName ?? familyEmail, email: familyEmail),
      ];

      final event = _buildEvent(
        round,
        calendarId,
        notifyFamilyMembers: mergedFamily.isEmpty ? null : mergedFamily,
        reminderMinutes: reminderMinutes,
      );
      final result = await _plugin.createOrUpdateEvent(event);

      if (result?.isSuccess == true && result?.data != null) {
        final eventId = result!.data!;

        // Read it back before calling this a success.
        //
        // The plugin reporting success is not evidence the event exists.
        // A user was shown a green "invite sent" for an event that was not
        // in their calendar, and only discovered it by checking manually —
        // which is worse than an error, because it removes any reason to
        // trust the message. Confirm the event is really there, and say so
        // only then.
        final confirmed = await verifyEventExists(
          calendarId: calendarId,
          eventId: eventId,
          around: event.start ?? TZDateTime.now(local),
        );
        if (!confirmed) {
          debugPrint(
            '[CalendarService] Plugin reported success for $eventId but the '
            'event could not be read back from calendar $calendarId',
          );
          return null;
        }

        debugPrint(
          '[CalendarService] Created and verified event $eventId '
          'for "${round.courseName}" at ${event.start}',
        );
        return eventId;
      }

      debugPrint(
        '[CalendarService] Failed to create event: '
        '${result?.errors.map((e) => e.errorMessage).join(', ')}',
      );
      return null;
    } catch (e, st) {
      debugPrint('[CalendarService] createGolfEvent error: $e\n$st');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Delete event
  // ─────────────────────────────────────────────────────────────────────────

  /// Deletes the calendar event [eventId] from [calendarId].
  ///
  /// This is what actually cancels a round for every player — the
  /// calendar provider sends each attendee a cancellation notice. Returns
  /// `true` on success. Like every other method here, failures are caught
  /// and logged rather than thrown — callers should still remove the round
  /// from local state even if this returns `false`, since a dangling
  /// calendar event with no matching app round is a lesser problem than a
  /// round the app can't get rid of at all.
  Future<bool> deleteEvent(String calendarId, String eventId) async {
    try {
      if (!await _ensurePermissions()) return false;

      final result = await _plugin.deleteEvent(calendarId, eventId);
      if (result.isSuccess && result.data == true) {
        debugPrint('[CalendarService] Deleted event "$eventId"');
        return true;
      }

      debugPrint(
        '[CalendarService] Failed to delete event "$eventId": '
        '${result.errors.map((e) => e.errorMessage).join(', ')}',
      );
      return false;
    } catch (e, st) {
      debugPrint('[CalendarService] deleteEvent error: $e\n$st');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Find existing event
  // ─────────────────────────────────────────────────────────────────────────

  /// Searches for an existing All Teed Up event matching the given parameters.
  ///
  /// Looks in the specified calendar for events in the next 90 days whose
  /// title contains the ⛳ prefix and the [course] name, and whose start
  /// time matches the parsed [date] and [teeTime].
  ///
  /// Returns the matched [GolfRound], or `null` if no match is found.
  Future<GolfRound?> findExistingEvent(
    String course,
    String date,
    String teeTime,
    String calendarId,
  ) async {
    try {
      if (!await _ensurePermissions()) return null;

      // Parse the date and tee time into a DateTime for comparison.
      final targetStart = _parseDateTime(date, teeTime);
      if (targetStart == null) {
        debugPrint(
          '[CalendarService] Could not parse date="$date" '
          'teeTime="$teeTime"',
        );
        return null;
      }

      // Search a window around the target date (±1 day for safety).
      final searchStart = targetStart.subtract(const Duration(days: 1));
      final searchEnd = targetStart.add(const Duration(days: 2));

      final events = await _retrieveEvents(
        calendarId,
        searchStart,
        searchEnd,
      );

      final courseNorm = course.trim().toLowerCase();

      for (final event in events) {
        final title = event.title ?? '';

        // Must be a All Teed Up event.
        if (!title.contains(eventPrefix)) continue;

        // Must contain the course name.
        if (!title.toLowerCase().contains(courseNorm)) continue;

        // Start time must match (within 1 minute tolerance).
        if (event.start == null) continue;
        final eventStart = event.start!;
        final diff = eventStart.difference(targetStart).abs();
        if (diff > const Duration(minutes: 1)) continue;

        // Match found — parse into GolfRound.
        return _eventToGolfRound(event);
      }

      return null;
    } catch (e, st) {
      debugPrint('[CalendarService] findExistingEvent error: $e\n$st');
      return null;
    }
  }

  /// Like [findExistingEvent], but searches every calendar in [calendarIds]
  /// (spec: multi-calendar account linking) and returns the first match.
  Future<GolfRound?> findExistingEventAcrossCalendars(
    String course,
    String date,
    String teeTime,
    List<String> calendarIds,
  ) async {
    for (final calendarId in calendarIds) {
      final match = await findExistingEvent(course, date, teeTime, calendarId);
      if (match != null) return match;
    }
    return null;
  }

  /// Finds ANY existing calendar event overlapping [start], regardless of who
  /// created it, across every calendar in [calendarIds].
  ///
  /// [findExistingEvent] deliberately requires the ⛳ prefix because it's for
  /// re-finding *this app's own* events. That makes it useless for duplicate
  /// detection: a round already in the calendar from another source — a
  /// CoPilot bot, a club's own invite, a manually-added entry — has no ⛳ and
  /// was therefore invisible, so the app would happily create a second event
  /// for a tee time already in the calendar. This matches on time overlap
  /// instead, which is the thing that actually makes two entries duplicates.
  ///
  /// [window] is the tolerance either side of the tee time; club confirmations
  /// and manual entries often differ by a few minutes for the same booking.
  /// Finds events near [start] that may duplicate a round being added.
  ///
  /// Pass an EMPTY [calendarIds] to search every calendar on the device,
  /// which is almost always what you want: "is this already in my calendar?"
  /// is a question about the whole calendar, not just the calendars the app
  /// happens to write to. Restricting the search to linked calendars meant
  /// that a user who had selected none — which was easy, since the picker
  /// row was not tappable — had duplicate detection silently disabled, and
  /// an entry created by another tool in an unlinked calendar was invisible
  /// to the check by construction.
  Future<List<Event>> findConflictingEvents({
    required DateTime start,
    required List<String> calendarIds,
    Duration window = const Duration(minutes: 90),
  }) async {
    if (calendarIds.isEmpty) {
      final all = await getAvailableCalendars();
      calendarIds = all.map((c) => c.id).whereType<String>().toList();
    }
    final conflicts = <Event>[];
    final seen = <String>{};
    try {
      if (!await _ensurePermissions()) return conflicts;
      for (final calendarId in calendarIds) {
        final events = await _retrieveEvents(
          calendarId,
          start.subtract(window),
          start.add(window),
        );
        for (final e in events) {
          final s = e.start;
          if (s == null) continue;
          if (e.allDay == true) continue; // all-day entries aren't tee times
          if (s.difference(start).abs() > window) continue;
          final id = e.eventId;
          if (id != null && !seen.add(id)) continue;
          conflicts.add(e);
        }
      }
    } catch (e, st) {
      debugPrint('[CalendarService] findConflictingEvents error: $e\n$st');
    }
    conflicts.sort((a, b) => (a.start?.difference(start).abs() ?? Duration.zero)
        .compareTo(b.start?.difference(start).abs() ?? Duration.zero));
    return conflicts;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Update event (CRITICAL — preserves RSVP statuses)
  // ─────────────────────────────────────────────────────────────────────────

  /// Updates an existing calendar event with new player information.
  ///
  /// **Critical RSVP-preserving logic:**
  /// 1. Fetches the existing event to read current attendee statuses.
  /// 2. For **unchanged** players: preserves their existing
  ///    `responseStatus` so they are NOT re-invited.
  /// 3. For **added** players: creates new attendees (they receive fresh
  ///    calendar invitations).
  /// 4. For **removed** players: removes them from the attendee list
  ///    (they receive cancellation notices from the calendar provider).
  /// 5. Updates the event title with the new player list.
  /// 6. Updates the description.
  /// Returns `true` only if the event was actually written. Callers must
  /// surface a failure to the user rather than assuming success — an
  /// earlier version returned void and swallowed every error, so the UI
  /// reported "Calendar invite sent" even when nothing was sent.
  Future<bool> updateGolfEvent(
    String eventId,
    GolfRound round,
    PlayerDiff diff,
    String calendarId, {
    List<FamilyMember>? notifyFamilyMembers,
    List<int>? reminderMinutes,
  }) async {
    try {
      if (!await _ensurePermissions()) return false;

      // 1. Fetch the existing event to get current attendees + statuses.
      final existingEvents = await _retrieveEvents(
        calendarId,
        round.date.subtract(const Duration(days: 1)),
        round.date.add(const Duration(days: 2)),
      );

      Event? existingEvent;
      for (final e in existingEvents) {
        if (e.eventId == eventId) {
          existingEvent = e;
          break;
        }
      }

      if (existingEvent == null) {
        debugPrint(
          '[CalendarService] Could not find event "$eventId" to update',
        );
        return false;
      }

      // 2. Build a map of existing attendee email → Attendee for
      //    preserving RSVP status.
      final existingAttendeeMap = <String, Attendee>{};
      for (final attendee in existingEvent.attendees ?? <Attendee?>[]) {
        if (attendee?.emailAddress != null) {
          existingAttendeeMap[attendee!.emailAddress!.toLowerCase()] = attendee;
        }
      }

      // 3. Build the new attendee list.
      final newAttendees = <Attendee>[];

      // Unchanged players — preserve their existing attendee object
      // (keeps RSVP status intact).
      for (final player in diff.unchanged) {
        if (!player.hasValidEmail) continue;
        final emailKey = player.email!.toLowerCase();

        if (existingAttendeeMap.containsKey(emailKey)) {
          // Re-use the existing attendee to preserve responseStatus.
          newAttendees.add(existingAttendeeMap[emailKey]!);
        } else {
          // Email wasn't in the old event (edge case) — add as new.
          newAttendees.add(_playerToAttendee(player));
        }
      }

      // Added players — create fresh attendees (they get invitations).
      for (final player in diff.added) {
        if (!player.hasValidEmail) continue;
        newAttendees.add(_playerToAttendee(player));
      }

      // Removed players are simply omitted from the list — the
      // calendar provider handles sending cancellation notices.

      // Preserve existing family (Optional) attendees if present.
      final existingFamilyAttendees = (existingEvent.attendees ?? <Attendee?>[])
          .where((a) => a != null && a.role == AttendeeRole.Optional)
          .whereType<Attendee>();
      for (final familyAttendee in existingFamilyAttendees) {
        // Only re-add if not already in the new list.
        final alreadyPresent = newAttendees.any(
          (a) =>
              a.emailAddress?.toLowerCase() ==
              familyAttendee.emailAddress?.toLowerCase(),
        );
        if (!alreadyPresent) {
          newAttendees.add(familyAttendee);
        }
      }

      // Add any newly-selected family members not already on the event.
      String? familyNoteLine;
      if (notifyFamilyMembers != null && notifyFamilyMembers.isNotEmpty) {
        for (final member in notifyFamilyMembers) {
          final emailKey = member.email.toLowerCase();
          final alreadyPresent = newAttendees.any(
            (a) => a.emailAddress?.toLowerCase() == emailKey,
          );
          if (!alreadyPresent) {
            newAttendees.add(Attendee(
              name: member.name,
              emailAddress: member.email,
              role: AttendeeRole.Optional,
              isOrganiser: false,
            ));
          }
        }
        final names = notifyFamilyMembers.map((m) => m.name).join(', ');
        familyNoteLine = 'ℹ️ $names notified — information only';
      }

      // 4. Update the event fields.
      existingEvent.title = _buildSummary(round);
      existingEvent.description =
          _buildDescription(round, familyNoteLine: familyNoteLine);
      existingEvent.attendees = newAttendees;
      existingEvent.location = round.courseName;
      if (reminderMinutes != null) {
        existingEvent.reminders = [
          for (final minutes in reminderMinutes) Reminder(minutes: minutes),
        ];
      }

      // 5. Persist the update.
      final result = await _plugin.createOrUpdateEvent(existingEvent);

      if (result?.isSuccess == true) {
        // Same rule as create: confirm before claiming success.
        final confirmed = await verifyEventExists(
          calendarId: calendarId,
          eventId: eventId,
          around: existingEvent.start ?? TZDateTime.now(local),
        );
        if (!confirmed) {
          debugPrint(
            '[CalendarService] Plugin reported success updating $eventId but '
            'it could not be read back',
          );
          return false;
        }
        debugPrint(
          '[CalendarService] Updated event "$eventId" — '
          'added: ${diff.added.length}, '
          'removed: ${diff.removed.length}, '
          'unchanged: ${diff.unchanged.length}',
        );
        return true;
      }
      debugPrint(
        '[CalendarService] Failed to update event: '
        '${result?.errors.map((e) => e.errorMessage).join(', ')}',
      );
      return false;
    } catch (e, st) {
      debugPrint('[CalendarService] updateGolfEvent error: $e\n$st');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Get upcoming rounds
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches all All Teed Up golf events from the next [days] days.
  ///
  /// Scans the specified calendar for events with ⛳ in the title and
  /// parses each into a [GolfRound] with attendee RSVP status.
  ///
  /// Returns an empty list if permissions are denied or an error occurs.
  Future<List<GolfRound>> getUpcomingRounds(
    String calendarId, {
    int days = 60,
  }) async {
    try {
      if (!await _ensurePermissions()) return [];

      final now = DateTime.now();
      final end = now.add(Duration(days: days));

      final events = await _retrieveEvents(calendarId, now, end);
      final rounds = <GolfRound>[];

      for (final event in events) {
        final title = event.title ?? '';
        if (!title.contains(eventPrefix)) continue;

        final round = _eventToGolfRound(event);
        if (round != null) {
          rounds.add(round);
        }
      }

      // Sort by date ascending.
      rounds.sort((a, b) => a.date.compareTo(b.date));

      return rounds;
    } catch (e, st) {
      debugPrint('[CalendarService] getUpcomingRounds error: $e\n$st');
      return [];
    }
  }

  /// Like [getUpcomingRounds], but aggregates across every calendar in
  /// [calendarIds] (spec: multi-calendar account linking), de-duplicated
  /// by event id and sorted by date ascending.
  Future<List<GolfRound>> getUpcomingRoundsForCalendars(
    List<String> calendarIds, {
    int days = 60,
  }) async {
    final seen = <String>{};
    final rounds = <GolfRound>[];

    for (final calendarId in calendarIds) {
      final calendarRounds = await getUpcomingRounds(calendarId, days: days);
      for (final round in calendarRounds) {
        if (seen.add(round.id)) rounds.add(round);
      }
    }

    rounds.sort((a, b) => a.date.compareTo(b.date));
    return rounds;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Attendee status
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a map of email → [AttendeeStatus] for the given event.
  ///
  /// Reads the platform-specific attendance details and normalises them
  /// into the app's [AttendeeStatus] enum.
  Future<Map<String, AttendeeStatus>> getAttendeeStatus(
    String eventId,
    String calendarId,
  ) async {
    try {
      if (!await _ensurePermissions()) return {};

      // Retrieve events in a wide window to find the specific event.
      final now = DateTime.now();
      final events = await _retrieveEvents(
        calendarId,
        now.subtract(const Duration(days: 30)),
        now.add(const Duration(days: 365)),
      );

      for (final event in events) {
        if (event.eventId != eventId) continue;

        final statusMap = <String, AttendeeStatus>{};
        for (final attendee in event.attendees ?? <Attendee?>[]) {
          if (attendee?.emailAddress == null) continue;
          statusMap[attendee!.emailAddress!.toLowerCase()] =
              _normaliseAttendanceStatus(attendee);
        }
        return statusMap;
      }

      debugPrint('[CalendarService] Event "$eventId" not found');
      return {};
    } catch (e, st) {
      debugPrint('[CalendarService] getAttendeeStatus error: $e\n$st');
      return {};
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Player diff from summary
  // ─────────────────────────────────────────────────────────────────────────

  /// Computes the difference between player names in an old event summary
  /// and a new list of [Player]s.
  ///
  /// Parses player names from the pipe-delimited summary format:
  /// `⛳ Course Name | 07:30 | Player 1, Player 2, Player 3`
  ///
  /// Returns a [PlayerDiff] with added, removed, and unchanged players.
  PlayerDiff diffPlayers(String oldSummary, List<Player> newPlayers) {
    final oldPlayerNames = _extractPlayerNamesFromSummary(oldSummary);

    // Create placeholder Player objects from old names for comparison.
    final oldPlayers = oldPlayerNames
        .map(
          (name) => Player(
            id: name.toLowerCase().replaceAll(' ', '_'),
            name: name,
          ),
        )
        .toList();

    return PlayerDiff.compare(
      oldPlayers: oldPlayers,
      newPlayers: newPlayers,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private helpers
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Event building ─────────────────────────────────────────────────────

  /// Builds a [device_calendar.Event] from a [GolfRound].
  ///
  /// Optionally adds each of [notifyFamilyMembers] as an
  /// [AttendeeRole.Optional] attendee.
  Event _buildEvent(
    GolfRound round,
    String calendarId, {
    List<FamilyMember>? notifyFamilyMembers,
    List<int>? reminderMinutes,
  }) {
    final localTz = local;

    // Build the instant with Dart's DateTime FIRST, then convert.
    //
    // TZDateTime(localTz, y, m, d, hh, mm) treats those components as
    // wall-clock time IN localTz — so if the timezone package's `local` is
    // wrong, the instant is wrong. That is how a 06:30 tee time went out as
    // 10:30: `local` was UTC, so 06:30 became 06:30Z, which is 10:30 in
    // Dubai.
    //
    // DateTime(y, m, d, hh, mm) is interpreted in the DEVICE's zone by the
    // Dart runtime itself, with no dependency on the timezone database.
    // Converting that instant into localTz therefore yields the correct
    // moment even when localTz is UTC: only the label changes, and the
    // epoch milliseconds — which is what the platform actually stores — are
    // right either way.
    final wallClock = DateTime(
      round.date.year,
      round.date.month,
      round.date.day,
      round.teeTime.hour,
      round.teeTime.minute,
    );
    final startDt = TZDateTime.from(wallClock, localTz);

    final endDt = startDt.add(const Duration(minutes: _roundDurationMinutes));

    // Build attendee list from players with valid emails.
    final attendees = <Attendee>[
      for (final player in round.players)
        if (player.hasValidEmail) _playerToAttendee(player),
    ];

    // Add family members as Optional attendees if requested.
    if (notifyFamilyMembers != null) {
      for (final member in notifyFamilyMembers) {
        attendees.add(Attendee(
          name: member.name,
          emailAddress: member.email,
          role: AttendeeRole.Optional,
          isOrganiser: false,
        ));
      }
    }

    // Build description, prepending family notification line if applicable.
    String? familyNoteLine;
    if (notifyFamilyMembers != null && notifyFamilyMembers.isNotEmpty) {
      final names = notifyFamilyMembers.map((m) => m.name).join(', ');
      familyNoteLine = 'ℹ️ $names notified — information only';
    }

    return Event(
      calendarId,
      title: _buildSummary(round),
      start: startDt,
      end: endDt,
      location: round.courseName,
      description: _buildDescription(round, familyNoteLine: familyNoteLine),
      attendees: attendees.isNotEmpty ? attendees : null,
      availability: Availability.Busy,
      // Defaults to both 1h and 12h before (spec A13) when the caller
      // doesn't specify — callers gate this via AppState.enabledReminderMinutes
      // (spec C5's Notifications & Reminders toggles).
      reminders: [
        for (final minutes in reminderMinutes ?? const [60, 720])
          Reminder(minutes: minutes),
      ],
    );
  }

  /// Builds the event title/summary in the standard format.
  ///
  /// Format: `⛳ Course Name | 07:30 | Player 1, Player 2 | All Teed Up`
  ///
  /// The trailing brand segment (Growth Loop Section 01) is a free
  /// impression in every notification banner and month view a recipient
  /// sees, tapped or not — it costs nothing to keep on every event this
  /// app creates. It's its own pipe segment rather than appended after the
  /// player list so [_eventToGolfRound]'s comma-split player parsing (used
  /// when an event has no attendees to read RSVP status from) can't pick
  /// up "All Teed Up" as a fourth player name.
  /// Exactly what this app writes as the event title and body, without
  /// touching the device calendar.
  ///
  /// Exposed so the invite can be reviewed — on-device and offline — before
  /// anyone sends one. Uses the same builders as the real write, so a
  /// preview cannot drift from what actually goes out.
  ({String title, String description}) buildInvitePreview(
    GolfRound round, {
    String? familyNoteLine,
  }) =>
      (
        title: _buildSummary(round),
        description: _buildDescription(round, familyNoteLine: familyNoteLine),
      );

  String _buildSummary(GolfRound round) {
    final playerNames = round.players.map((p) => p.name).join(', ');
    return '$eventPrefix ${round.courseName} '
        '| ${round.formattedTeeTime} '
        '| $playerNames '
        '| All Teed Up';
  }

  /// Builds the event description with booking details (spec A13).
  ///
  /// Sections:
  /// - 🏌️ Players list with email addresses
  /// - 🟢 Open slots (omitted when zero)
  /// - ⏱️ Duration
  /// - "Created by All Teed Up"
  ///
  /// If [familyNoteLine] is provided, it is prepended to the description.
  String _buildDescription(GolfRound round, {String? familyNoteLine}) {
    final buffer = StringBuffer();

    // Prepend family notification line if provided.
    if (familyNoteLine != null) {
      buffer.writeln(familyNoteLine);
      buffer.writeln();
    }

    // 🏌️ Players
    buffer.writeln('🏌️ Players');
    for (var i = 0; i < round.players.length; i++) {
      final p = round.players[i];
      final isTbc =
          p.rsvpStatus.name == 'tbc' || p.name.toLowerCase().contains('tbc');
      if (isTbc) {
        buffer.writeln('  ${i + 1}. Player TBC');
      } else {
        final emailSuffix = p.email != null ? ' <${p.email}>' : '';
        buffer.writeln('  ${i + 1}. ${p.name}$emailSuffix');
      }
    }

    // 🟢 Open slots (drop line if zero)
    const totalSlots = 4;
    final openSlots = totalSlots - round.players.length;
    if (openSlots > 0) {
      buffer.writeln();
      buffer.writeln('🟢 $openSlots open slot${openSlots > 1 ? 's' : ''}');
    }

    // ⏱️ Duration
    buffer.writeln();
    buffer.writeln('⏱️ Duration: 4h 30m');

    // Booking reference (if present)
    if (round.bookingRef != null && round.bookingRef!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Booking Ref: ${round.bookingRef}');
    }

    buffer.writeln();
    buffer.write(_growthLoopFooter);

    return buffer.toString();
  }

  /// The growth-loop signature (Growth Loop Section 01) appended to every
  /// invite — no data, no deep link, nothing to tap for someone who
  /// already has the app (it finds the round on its own via
  /// [RsvpMonitor]'s reconciliation pass, not a link). A plain
  /// `https://` line is the only link form confirmed to render as
  /// tappable in a calendar event view at all, so that's what the
  /// "new here" store links use.
  static const String _growthLoopFooter = '──────────\n'
      '📲 Already have All Teed Up?\n'
      "Open it — this round's waiting for you.\n"
      '\n'
      'New here? Never miss a tee time again.\n'
      'All Teed Up — AED 99.\n'
      '🍎 iPhone → $_appStoreUrl\n'
      '🤖 Android → $_playStoreUrl';

  /// Converts a [Player] to a device_calendar [Attendee].
  Attendee _playerToAttendee(Player player) {
    return Attendee(
      name: player.name,
      emailAddress: player.email,
      role: AttendeeRole.Required,
      isOrganiser: false,
    );
  }

  // ── Event retrieval ────────────────────────────────────────────────────

  /// Retrieves events from the specified calendar within the date range.
  Future<List<Event>> _retrieveEvents(
    String calendarId,
    DateTime start,
    DateTime end,
  ) async {
    final localTz = local;
    final startTz = TZDateTime.from(start, localTz);
    final endTz = TZDateTime.from(end, localTz);

    final params = RetrieveEventsParams(startDate: startTz, endDate: endTz);
    final result = await _plugin.retrieveEvents(calendarId, params);

    // Same read-shaped rule as retrieveCalendars: keep the data whenever
    // there is data. Gating on isSuccess here would silently return no
    // events when the plugin reports a non-fatal error alongside a good
    // result — which would disable duplicate detection without a word.
    final data = result.data;
    if (data != null && data.isNotEmpty) {
      if (result.errors.isNotEmpty) {
        debugPrint(
          '[CalendarService] retrieveEvents reported errors but returned '
          '${data.length} event(s): '
          '${result.errors.map((e) => e.errorMessage).join(', ')}',
        );
      }
      return data.toList();
    }

    debugPrint(
      '[CalendarService] Failed to retrieve events: '
      '${result.errors.map((e) => e.errorMessage).join(', ')}',
    );
    return [];
  }

  // ── Event parsing ──────────────────────────────────────────────────────

  /// Converts a device_calendar [Event] back into a [GolfRound].
  ///
  /// Returns `null` if the event cannot be parsed.
  GolfRound? _eventToGolfRound(Event event) {
    try {
      final title = event.title ?? '';
      final start = event.start;
      if (start == null) return null;

      // Parse course name and players from the title.
      // Format: ⛳ Course Name | HH:mm | Player1, Player2
      final parts = title.split('|').map((s) => s.trim()).toList();

      // Course name — strip the ⛳ prefix.
      final courseName = parts.isNotEmpty
          ? parts[0].replaceFirst(eventPrefix, '').trim()
          : 'Unknown Course';

      // Players — from title and/or attendees.
      final players = <Player>[];

      // Prefer attendees (they have RSVP status).
      if (event.attendees != null && event.attendees!.isNotEmpty) {
        for (final attendee in event.attendees!) {
          if (attendee == null) continue;
          if (attendee.isOrganiser) continue; // Skip the organiser.

          players.add(Player(
            id: (attendee.emailAddress ?? attendee.name ?? 'unknown')
                .toLowerCase()
                .replaceAll(' ', '_'),
            name: attendee.name ?? attendee.emailAddress ?? 'Unknown',
            email: attendee.emailAddress,
            rsvpStatus: _attendeeStatusToRsvp(
              _normaliseAttendanceStatus(attendee),
            ),
          ));
        }
      }

      // If no attendees, fall back to parsing names from the title.
      if (players.isEmpty && parts.length >= 3) {
        final names = parts[2].split(',').map((s) => s.trim()).toList();
        for (final name in names) {
          if (name.isEmpty) continue;
          players.add(Player(
            id: name.toLowerCase().replaceAll(' ', '_'),
            name: name,
          ));
        }
      }

      // Extract booking ref from description.
      String? bookingRef;
      final desc = event.description ?? '';
      final refMatch = RegExp(
        r'Booking\s+Ref:\s*(.+)',
        caseSensitive: false,
      ).firstMatch(desc);
      if (refMatch != null) {
        bookingRef = refMatch.group(1)?.trim();
      }

      return GolfRound(
        id: event.eventId ?? 'unknown',
        courseName: courseName,
        date: DateTime(start.year, start.month, start.day),
        teeTime: DateTime(
          start.year,
          start.month,
          start.day,
          start.hour,
          start.minute,
        ),
        players: players,
        bookingRef: bookingRef,
        calendarEventId: event.eventId,
      );
    } catch (e, st) {
      debugPrint('[CalendarService] _eventToGolfRound error: $e\n$st');
      return null;
    }
  }

  /// Extracts player names from a All Teed Up event summary string.
  ///
  /// Given `⛳ Course | 07:30 | Alice, Bob, Charlie`, returns
  /// `['Alice', 'Bob', 'Charlie']`.
  List<String> _extractPlayerNamesFromSummary(String summary) {
    final parts = summary.split('|').map((s) => s.trim()).toList();
    if (parts.length < 3) return [];

    return parts[2]
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ── Status normalisation ───────────────────────────────────────────────

  /// Normalises platform-specific attendance status into [AttendeeStatus].
  ///
  /// On iOS, reads [IosAttendeeDetails.attendanceStatus].
  /// On Android, reads [AndroidAttendeeDetails.attendanceStatus].
  AttendeeStatus _normaliseAttendanceStatus(Attendee attendee) {
    if (Platform.isIOS) {
      final iosStatus = attendee.iosAttendeeDetails?.attendanceStatus;
      if (iosStatus == null) return AttendeeStatus.unknown;

      switch (iosStatus) {
        case IosAttendanceStatus.Accepted:
          return AttendeeStatus.accepted;
        case IosAttendanceStatus.Declined:
          return AttendeeStatus.declined;
        case IosAttendanceStatus.Tentative:
          return AttendeeStatus.tentative;
        case IosAttendanceStatus.Pending:
          return AttendeeStatus.pending;
        default:
          return AttendeeStatus.unknown;
      }
    } else if (Platform.isAndroid) {
      final androidStatus = attendee.androidAttendeeDetails?.attendanceStatus;
      if (androidStatus == null) return AttendeeStatus.unknown;

      switch (androidStatus) {
        case AndroidAttendanceStatus.Accepted:
          return AttendeeStatus.accepted;
        case AndroidAttendanceStatus.Declined:
          return AttendeeStatus.declined;
        case AndroidAttendanceStatus.Tentative:
          return AttendeeStatus.tentative;
        case AndroidAttendanceStatus.Invited:
          return AttendeeStatus.pending;
        default:
          return AttendeeStatus.unknown;
      }
    }

    return AttendeeStatus.unknown;
  }

  /// Maps [AttendeeStatus] to the app's [RsvpStatus].
  RsvpStatus _attendeeStatusToRsvp(AttendeeStatus status) {
    switch (status) {
      case AttendeeStatus.accepted:
        return RsvpStatus.accepted;
      case AttendeeStatus.declined:
        return RsvpStatus.declined;
      case AttendeeStatus.tentative:
      case AttendeeStatus.pending:
      case AttendeeStatus.unknown:
        return RsvpStatus.pending;
    }
  }

  // ── Date/time parsing ──────────────────────────────────────────────────

  /// Parses separate date and time strings into a single [DateTime].
  ///
  /// Supports common formats:
  /// - Date: `YYYY-MM-DD`, `DD/MM/YYYY`, `DD-MM-YYYY`
  /// - Time: `HH:mm`, `H:mm AM/PM`, `HH:mm AM/PM`
  ///
  /// Returns `null` if parsing fails.
  DateTime? _parseDateTime(String dateStr, String timeStr) {
    try {
      // Try ISO date first.
      DateTime? date;

      // YYYY-MM-DD
      final isoMatch =
          RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(dateStr.trim());
      if (isoMatch != null) {
        date = DateTime(
          int.parse(isoMatch.group(1)!),
          int.parse(isoMatch.group(2)!),
          int.parse(isoMatch.group(3)!),
        );
      }

      // DD/MM/YYYY or DD-MM-YYYY
      if (date == null) {
        final dmyMatch = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$')
            .firstMatch(dateStr.trim());
        if (dmyMatch != null) {
          final a = int.parse(dmyMatch.group(1)!);
          final b = int.parse(dmyMatch.group(2)!);
          final year = int.parse(dmyMatch.group(3)!);
          // Assume DD/MM/YYYY (international).
          date = DateTime(year, b, a);
        }
      }

      // Fallback: try DateTime.parse.
      date ??= DateTime.tryParse(dateStr.trim());

      if (date == null) return null;

      // Parse the time.
      final timeParts = _parseTimeString(timeStr);
      if (timeParts == null) return null;

      return DateTime(
        date.year,
        date.month,
        date.day,
        timeParts.$1,
        timeParts.$2,
      );
    } catch (e) {
      debugPrint(
        '[CalendarService] _parseDateTime error for '
        '"$dateStr" / "$timeStr": $e',
      );
      return null;
    }
  }

  /// Parses a time string into (hour, minute) in 24-hour format.
  ///
  /// Supports: `HH:mm`, `H:mm AM/PM`, `HH:mm AM/PM`.
  (int, int)? _parseTimeString(String timeStr) {
    final cleaned = timeStr.trim().toUpperCase();

    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM|A\.M\.|P\.M\.)?$',
    ).firstMatch(cleaned);
    if (match == null) return null;

    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final meridiem = match.group(3)?.replaceAll('.', '');

    if (meridiem == 'PM' && hour < 12) {
      hour += 12;
    } else if (meridiem == 'AM' && hour == 12) {
      hour = 0;
    }

    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return (hour, minute);
  }
}
