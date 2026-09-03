// A round that lost its calendar link must be re-attached, not duplicated.
//
// Builds before 1.11.3+64 dropped GolfRound.calendarEventId whenever a
// booking was amended (see amend_preserves_event_link_test.dart). Those
// rounds are still on people's devices. Two things follow: RsvpMonitor has
// no handle on them, so a decline can never be detected; and their calendar
// event looks brand new to the reconciliation pass, so the growth-loop
// import would add a SECOND copy of a round the user already has.
//
// Reconciliation is the only place that sees both sides, so it is where the
// repair belongs.
import 'package:flutter_test/flutter_test.dart';

import 'package:all_teed_up/models/golf_round.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/services/rsvp_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Player p(String n) => Player(id: n, name: n, email: '$n@example.com');

  final teeTime = DateTime.now().add(const Duration(days: 5));
  final day = DateTime(teeTime.year, teeTime.month, teeTime.day);

  GolfRound round({required String id, String? eventId}) => GolfRound(
        id: id,
        courseName: 'Emirates Golf Club',
        date: day,
        teeTime: teeTime,
        players: [p('guy')],
        calendarEventId: eventId,
      );

  tearDown(() => RsvpMonitor.debugRoundFetcher = null);

  test(
      'an orphaned round adopts its calendar event instead of being '
      'imported a second time', () async {
    // Stored on the device with no calendar link — orphaned by the amend
    // bug fixed in build 64.
    final state = AppState()
      ..setSelectedCalendarId('cal-primary')
      ..setRounds([round(id: 'local_1')]);

    // The same booking, still in the calendar, event id intact.
    RsvpMonitor.debugRoundFetcher =
        (ids) async => [round(id: 'EVT-9', eventId: 'EVT-9')];

    await RsvpMonitor.instance.reconcileWithCalendar(state);

    expect(state.allRounds.length, 1, reason: 'no duplicate round');
    expect(state.allRounds.single.id, 'local_1');
    expect(state.allRounds.single.calendarEventId, 'EVT-9',
        reason: 'the monitor needs a handle on the event');
  });

  test('a genuinely new calendar event is still imported', () async {
    final state = AppState()
      ..setSelectedCalendarId('cal-primary')
      ..setRounds([]);

    RsvpMonitor.debugRoundFetcher =
        (ids) async => [round(id: 'EVT-9', eventId: 'EVT-9')];

    expect(await RsvpMonitor.instance.reconcileWithCalendar(state), 1);
    expect(state.allRounds.single.calendarEventId, 'EVT-9');
  });

  test('a round that already has a different event id is left alone', () async {
    final state = AppState()
      ..setSelectedCalendarId('cal-primary')
      ..setRounds([round(id: 'local_1', eventId: 'EVT-OLD')]);

    RsvpMonitor.debugRoundFetcher =
        (ids) async => [round(id: 'EVT-9', eventId: 'EVT-9')];

    await RsvpMonitor.instance.reconcileWithCalendar(state);

    expect(
      state.allRounds.map((r) => r.calendarEventId),
      ['EVT-OLD', 'EVT-9'],
      reason: 'two distinct events, two rounds — not a relink',
    );
  });
}
