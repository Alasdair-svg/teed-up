// Rescanning an amended booking has to reach the calendar.
//
// It didn't. AppState.updateRound only touched the calendar when family
// members happened to be selected, so amending a booking updated the app's
// own list and stopped there: the arriving player was never invited, the
// departing player never got a cancellation, and the players who hadn't
// changed kept an event naming the old group. Rescanning is the documented
// way to amend a booking, and it silently did half the job.
//
// The guard has to stay narrow in the other direction too — RSVP cycling
// routes through updateRound, and rewriting the event there would notify
// four people every time the organiser tapped a name.
import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/models/golf_round.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/models/player_diff.dart';
import 'package:all_teed_up/providers/app_state.dart';

void main() {
  Player p(String name, {RsvpStatus status = RsvpStatus.pending}) =>
      Player(id: name, name: name, email: '$name@example.com', rsvpStatus: status);

  GolfRound round({
    List<Player>? players,
    DateTime? teeTime,
    String course = 'Emirates Golf Club',
    String? location,
  }) =>
      GolfRound(
        id: 'r1',
        courseName: course,
        date: DateTime(2026, 9, 12),
        teeTime: teeTime ?? DateTime(2026, 9, 12, 7, 30),
        players: players ?? [p('Marc'), p('Alasdair')],
        calendarEventId: 'evt1',
        isCreator: true,
        location: location,
      );

  bool decide(GolfRound? before, GolfRound after, {bool family = false}) =>
      AppState.shouldPushCalendarUpdate(
        previous: before,
        updated: after,
        diff: PlayerDiff.compare(
          oldPlayers: before?.players ?? after.players,
          newPlayers: after.players,
        ),
        notifyingFamily: family,
      );

  group('shouldPushCalendarUpdate', () {
    test('pushes when a player joins', () {
      expect(
        decide(round(), round(players: [p('Marc'), p('Alasdair'), p('Hamish')])),
        isTrue,
      );
    });

    test('pushes when a player leaves', () {
      expect(decide(round(), round(players: [p('Marc')])), isTrue);
    });

    test('pushes when a player is swapped', () {
      expect(
        decide(round(), round(players: [p('Marc'), p('Zach')])),
        isTrue,
      );
    });

    test('pushes when the tee time moves', () {
      expect(
        decide(round(), round(teeTime: DateTime(2026, 9, 12, 8, 10))),
        isTrue,
      );
    });

    test('pushes when the course or location changes', () {
      expect(decide(round(), round(course: 'Dubai Creek')), isTrue);
      expect(decide(round(), round(location: 'Al Sufouh Rd')), isTrue);
    });

    test('does NOT push for a local RSVP change alone', () {
      // The exact shape of AppState.updateRsvp: same roster, same schedule,
      // one status flipped.
      final before = round();
      final after = round(players: [
        p('Marc', status: RsvpStatus.declined),
        p('Alasdair'),
      ]);
      expect(decide(before, after), isFalse);
    });

    test('does NOT push when nothing changed at all', () {
      expect(decide(round(), round()), isFalse);
    });

    test('pushes when family members are being notified', () {
      expect(decide(round(), round(), family: true), isTrue);
    });

    test('does not push for an unknown prior round', () {
      expect(decide(null, round()), isFalse);
    });
  });
}
