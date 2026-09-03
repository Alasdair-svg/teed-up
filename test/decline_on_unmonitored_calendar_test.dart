// A decline must be detected on a round whose calendar the app was never
// told to watch.
//
// Fourth hiding place for an undetected decline. The monitor polled the
// union of {primary calendar} ∪ {linked calendars} and nothing else. On
// the reporting device the linked calendars were Birthdays and UAE
// Holidays — neither can carry an invitation — so in practice a single
// calendar was monitored. A round whose event lived anywhere else (a
// second account's default calendar, or the calendar selected before the
// user switched) was invisible forever, and a decline on it could never
// be seen.
//
// Two independent discovery paths now bring a round under monitoring, and
// EITHER one alone is sufficient:
//
//   1. the calendar id recorded on the round itself (GolfRound.calendarId);
//   2. a sweep of every calendar on the device for ⛳-prefixed events.
//
// They are tested separately, and each with the other's signal removed, so
// neither can pass on the other's coat-tails.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_teed_up/models/golf_round.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/services/rsvp_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final teeTime = now.add(const Duration(days: 2));

  /// One golf event as the monitor reads it, tagged with the calendar it
  /// lives in so the fake device can serve it from there and nowhere else.
  Map<String, dynamic> event({
    required String id,
    required String calendarId,
    required String title,
    required Map<String, String> attendees,
  }) =>
      {
        'eventId': id,
        'calendarId': calendarId,
        'title': title,
        'date': teeTime.toIso8601String().split('T').first,
        'start': teeTime,
        'attendees': attendees,
        'attendeeNames': {'guy@example.com': 'Guy Parsonage'},
      };

  /// A device with several calendars. Reads are served per calendar id —
  /// a calendar the monitor never asks about is a calendar it cannot see,
  /// which is exactly the real constraint.
  void serveDevice(List<Map<String, dynamic>> events) {
    RsvpMonitor.debugEventFetcher = (calendarId, start, end) async {
      return events.where((e) {
        if (e['calendarId'] != calendarId) return false;
        final s = e['start'] as DateTime;
        return !s.isBefore(start) && !s.isAfter(end);
      }).toList();
    };
    RsvpMonitor.debugCalendarLister = () async => const [
          'cal-primary',
          'cal-birthdays',
          'cal-uae-holidays',
          'cal-work',
        ];
  }

  /// The stored rounds list, in the shape `main.dart` persists.
  String roundsJson(List<GolfRound> rounds) =>
      jsonEncode(rounds.map((r) => r.toJson()).toList());

  GolfRound round({String? calendarId, String? eventId}) => GolfRound(
        id: 'round-1',
        courseName: 'Emirates Golf Club',
        date: DateTime(teeTime.year, teeTime.month, teeTime.day),
        teeTime: teeTime,
        players: const [Player(id: 'guy', name: 'Guy Parsonage')],
        calendarEventId: eventId,
        calendarId: calendarId,
      );

  /// Guy had accepted — the baseline exists, so this is not the
  /// never-seeded-baseline bug, nor the poll-window bug.
  void primePrefs({required String rounds}) {
    SharedPreferences.setMockInitialValues({
      'teed_up_selected_calendar_id': 'cal-primary',
      // Neither of these can carry an invitation. This is the user's real
      // configuration, and the reason the old union monitored one calendar.
      'teed_up_linked_calendar_ids': ['cal-birthdays', 'cal-uae-holidays'],
      'teed_up_rounds': rounds,
      'teed_up_rsvp_cache': jsonEncode({
        'EVT-WORK': {'guy@example.com': 'accepted'},
      }),
    });
  }

  tearDown(() {
    RsvpMonitor.debugEventFetcher = null;
    RsvpMonitor.debugCalendarLister = null;
  });

  group('path 1 — the calendar id recorded on the round', () {
    setUp(() {
      primePrefs(
        rounds: roundsJson([
          round(calendarId: 'cal-work', eventId: 'EVT-WORK'),
        ]),
      );
    });

    test('finds a decline in a calendar that is neither primary nor linked',
        () async {
      serveDevice([
        event(
          id: 'EVT-WORK',
          calendarId: 'cal-work',
          // No ⛳ in the title: the sweep cannot help here, so only the
          // recorded calendar id can find this round.
          title: 'Golf at Emirates Golf Club',
          attendees: {'guy@example.com': 'declined'},
        ),
      ]);

      final changes = await RsvpMonitor.instance.checkForChanges();

      expect(changes.length, 1);
      expect(changes.single.isDecline, isTrue);
      expect(changes.single.playerEmail, 'guy@example.com');
    });

    test('the recorded calendar is polled on the plain 60s tick, with no '
        'discovery sweep', () async {
      var calendarsListed = 0;
      serveDevice([
        event(
          id: 'EVT-WORK',
          calendarId: 'cal-work',
          title: 'Golf at Emirates Golf Club',
          attendees: {'guy@example.com': 'declined'},
        ),
      ]);
      final lister = RsvpMonitor.debugCalendarLister!;
      RsvpMonitor.debugCalendarLister = () {
        calendarsListed++;
        return lister();
      };

      final changes = await RsvpMonitor.instance.checkForChanges();

      expect(changes.single.isDecline, isTrue);
      expect(
        calendarsListed,
        0,
        reason: 'the cheap tick must not enumerate every calendar',
      );
    });

    test('storedRoundCalendarIds survives a round with no calendarId — the '
        'migration case', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'teed_up_rounds',
        roundsJson([
          round(calendarId: null, eventId: 'EVT-WORK'),
          round(calendarId: 'cal-work', eventId: 'EVT-WORK'),
        ]),
      );

      expect(RsvpMonitor.storedRoundCalendarIds(prefs), {'cal-work'});
    });

    test('storedRoundCalendarIds does not throw on unreadable storage',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('teed_up_rounds', 'not json at all');

      expect(RsvpMonitor.storedRoundCalendarIds(prefs), isEmpty);
    });
  });

  group('path 2 — the ⛳ discovery sweep', () {
    setUp(() {
      // A round with NO calendar id: stored by a build before the field
      // existed. Path 1 has nothing to work with.
      primePrefs(
        rounds: roundsJson([round(calendarId: null, eventId: 'EVT-WORK')]),
      );
    });

    test('finds a decline on a ⛳ event in a calendar nothing points to',
        () async {
      serveDevice([
        event(
          id: 'EVT-WORK',
          calendarId: 'cal-work',
          title: '⛳ Emirates Golf Club | 07:30 | Guy Parsonage',
          attendees: {'guy@example.com': 'declined'},
        ),
      ]);

      final changes =
          await RsvpMonitor.instance.checkForChanges(discoverAllCalendars: true);

      expect(changes.length, 1);
      expect(changes.single.isDecline, isTrue);
    });

    test('the swept calendar is remembered, so the next cheap tick keeps '
        'polling it', () async {
      serveDevice([
        event(
          id: 'EVT-WORK',
          calendarId: 'cal-work',
          title: '⛳ Emirates Golf Club | 07:30 | Guy Parsonage',
          attendees: {'guy@example.com': 'accepted'},
        ),
      ]);

      await RsvpMonitor.instance.checkForChanges(discoverAllCalendars: true);

      // Now the decline lands, and only a plain tick runs.
      serveDevice([
        event(
          id: 'EVT-WORK',
          calendarId: 'cal-work',
          title: '⛳ Emirates Golf Club | 07:30 | Guy Parsonage',
          attendees: {'guy@example.com': 'declined'},
        ),
      ]);

      final changes = await RsvpMonitor.instance.checkForChanges();

      expect(changes.length, 1);
      expect(changes.single.isDecline, isTrue);
    });

    test('a calendar with no ⛳ events is not adopted', () async {
      serveDevice([
        event(
          id: 'EVT-BIRTHDAY',
          calendarId: 'cal-work',
          title: "Someone's birthday",
          attendees: {'guy@example.com': 'declined'},
        ),
      ]);

      await RsvpMonitor.instance.checkForChanges(discoverAllCalendars: true);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('teed_up_discovered_calendar_ids'),
        isEmpty,
        reason: 'sweeping must not drag every subscribed calendar into the '
            'polled set',
      );
    });
  });

  group('control cases — these passed before the fix too', () {
    setUp(() {
      primePrefs(rounds: roundsJson([round(calendarId: 'cal-primary')]));
    });

    test('a decline in the primary calendar is still detected', () async {
      SharedPreferences.setMockInitialValues({
        'teed_up_selected_calendar_id': 'cal-primary',
        'teed_up_rsvp_cache': jsonEncode({
          'EVT-PRIMARY': {'guy@example.com': 'accepted'},
        }),
      });
      serveDevice([
        event(
          id: 'EVT-PRIMARY',
          calendarId: 'cal-primary',
          title: '⛳ Emirates Golf Club | 07:30 | Guy Parsonage',
          attendees: {'guy@example.com': 'declined'},
        ),
      ]);

      final changes = await RsvpMonitor.instance.checkForChanges();

      expect(changes.single.isDecline, isTrue);
    });

    test('an unchanged acceptance raises nothing', () async {
      serveDevice([
        event(
          id: 'EVT-WORK',
          calendarId: 'cal-primary',
          title: '⛳ Emirates Golf Club | 07:30 | Guy Parsonage',
          attendees: {'guy@example.com': 'accepted'},
        ),
      ]);

      expect(
        await RsvpMonitor.instance.checkForChanges(discoverAllCalendars: true),
        isEmpty,
      );
    });
  });
}
