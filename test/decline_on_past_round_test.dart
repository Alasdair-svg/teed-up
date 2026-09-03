// A decline must be detected on a round that has just been played.
//
// Third report of decline detection failing in the field. The first two
// causes were a baseline that was never seeded (build 63) and an amended
// booking orphaning its calendar event (build 64). This is the third: the
// monitor only ever read calendar events from "now" forward, so a round
// dropped out of monitoring the moment its tee time passed.
//
// That is exactly when people drop out. A decline arriving on the morning
// of a round — or after the group has teed off — landed on an event the
// monitor had already stopped reading, so it could never be seen. Nor
// could a decline on any round created by an older build, whose first
// observation only happens the next time the event is read at all.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/services/rsvp_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();

  /// One golf event, in the map shape the monitor reads.
  Map<String, dynamic> event(
    String id,
    DateTime start,
    Map<String, String> attendees,
  ) =>
      {
        'eventId': id,
        'title': 'Golf at Emirates Golf Club',
        'date': start.toIso8601String().split('T').first,
        'start': start,
        'attendees': attendees,
        'attendeeNames': {'guy@example.com': 'Guy Parsonage'},
      };

  /// A stand-in for the device calendar that honours the poll window the
  /// monitor asks for — which is the whole point: an event outside that
  /// window is invisible to the monitor on a real device too.
  void serveCalendar(List<Map<String, dynamic>> events) {
    RsvpMonitor.debugEventFetcher = (calendarId, start, end) async {
      return events.where((e) {
        final s = e['start'] as DateTime;
        return !s.isBefore(start) && !s.isAfter(end);
      }).toList();
    };
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'teed_up_selected_calendar_id': 'cal-primary',
      // Guy had accepted. The baseline exists — this is not the build-63 bug.
      'teed_up_rsvp_cache': jsonEncode({
        'EVT-1': {'guy@example.com': 'accepted'},
      }),
    });
  });

  tearDown(() => RsvpMonitor.debugEventFetcher = null);

  group('the poll window', () {
    test('reaches back far enough to cover a round played last week', () {
      final window = RsvpMonitor.pollWindow(now);
      expect(
        window.start.isBefore(now.subtract(const Duration(days: 7))),
        isTrue,
        reason: 'a round played last week must still be polled',
      );
      expect(window.end.isAfter(now.add(const Duration(days: 29))), isTrue);
    });
  });

  group('detecting a decline', () {
    test('on a round that teed off four hours ago', () async {
      serveCalendar([
        event(
          'EVT-1',
          now.subtract(const Duration(hours: 4)),
          {'guy@example.com': 'declined'},
        ),
      ]);

      final changes = await RsvpMonitor.instance.checkForChanges();

      expect(changes.length, 1);
      expect(changes.single.newStatus, RsvpStatus.declined);
      expect(changes.single.playerEmail, 'guy@example.com');
    });

    test('on a round played four days ago — a late decline is still news',
        () async {
      serveCalendar([
        event(
          'EVT-1',
          now.subtract(const Duration(days: 4)),
          {'guy@example.com': 'declined'},
        ),
      ]);

      final changes = await RsvpMonitor.instance.checkForChanges();

      expect(changes.length, 1);
      expect(changes.single.isDecline, isTrue);
    });

    test('on a round still to come — the case that already worked', () async {
      serveCalendar([
        event(
          'EVT-1',
          now.add(const Duration(days: 3)),
          {'guy@example.com': 'declined'},
        ),
      ]);

      final changes = await RsvpMonitor.instance.checkForChanges();

      expect(changes.length, 1);
      expect(changes.single.isDecline, isTrue);
    });

    test('an ancient round is not polled forever', () async {
      serveCalendar([
        event(
          'EVT-1',
          now.subtract(const Duration(days: 90)),
          {'guy@example.com': 'declined'},
        ),
      ]);

      expect(await RsvpMonitor.instance.checkForChanges(), isEmpty);
    });
  });

  group('when the app comes to the foreground', () {
    test('it polls immediately, not a minute later', () async {
      serveCalendar([
        event(
          'EVT-1',
          now.subtract(const Duration(hours: 2)),
          {'guy@example.com': 'declined'},
        ),
      ]);

      RsvpMonitor.instance.startForegroundPolling();
      addTearDown(RsvpMonitor.instance.stopForegroundPolling);

      // No timer advanced: the first poll must have run on start. A user
      // opening the app to check on a round should not wait 60 seconds for
      // the decline that made them open it.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final alerts = await RsvpMonitor.loadPersistedAlerts();
      expect(alerts.where((a) => a.isDecline), isNotEmpty);
    });
  });
}
