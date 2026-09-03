// A round whose tee time has passed must not be listed under
// "Your upcoming rounds".
//
// Reported from the field and reproduced on the Simulator on 3 Sep 2026:
// a round dated 30 Aug 2026 was still on the home screen under "Your
// upcoming rounds". AppState.upcomingRounds was never a filtered view —
// it was simply every round the app had ever stored, and the home screen
// rendered all of it.
//
// The rounds are not deleted: a played round moves to a "Past rounds"
// section and stays in storage. A round the user can no longer see is
// lost to them, which is worse than one listed in the wrong place.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:all_teed_up/models/golf_round.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/screens/home_screen.dart';

void main() {
  Player p(String n) => Player(id: n, name: n, email: null);

  GolfRound roundAt(String id, DateTime teeTime) => GolfRound(
        id: id,
        courseName: 'Emirates Golf Club',
        date: DateTime(teeTime.year, teeTime.month, teeTime.day),
        teeTime: teeTime,
        players: [p('Alasdair Kilgour')],
        calendarEventId: 'EVT-$id',
      );

  final now = DateTime.now();
  // The exact round from the bug report: four days ago.
  final lastWeek = roundAt('past', now.subtract(const Duration(days: 4)));
  final nextWeek = roundAt('future', now.add(const Duration(days: 7)));

  group('upcoming vs past', () {
    test('a round four days ago is not an upcoming round', () {
      final state = AppState()..setRounds([lastWeek, nextWeek]);
      expect(state.upcomingRounds.map((r) => r.id), ['future']);
    });

    test('a round that teed off two hours ago is still upcoming — '
        'people are on the course, and late declines still matter', () {
      final teeingOff = roundAt('today', now.subtract(const Duration(hours: 2)));
      final state = AppState()..setRounds([teeingOff]);
      expect(state.upcomingRounds.map((r) => r.id), ['today']);
    });
  });

  group('the home screen', () {
    testWidgets('lists a played round under "Past rounds", not under '
        '"Your upcoming rounds"', (tester) async {
      final state = AppState()..setRounds([lastWeek, nextWeek]);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Your upcoming rounds'), findsOneWidget);
      expect(find.text('Past rounds'), findsOneWidget);

      // Both rounds are visible; the played one sits below the heading.
      final heading = tester.getTopLeft(find.text('Past rounds')).dy;
      final cards = find.text('Emirates Golf Club');
      expect(cards, findsNWidgets(2));
      expect(tester.getTopLeft(cards.at(0)).dy, lessThan(heading));
      expect(tester.getTopLeft(cards.at(1)).dy, greaterThan(heading));

      // The settings tab, built offstage by the IndexedStack, leaves a
      // short-lived timer behind; drain it so the binding's teardown check
      // doesn't fail the test on something unrelated to the rounds list.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a played round is still stored, not deleted', (tester) async {
      final state = AppState()..setRounds([lastWeek, nextWeek]);
      expect(state.allRounds.map((r) => r.id), ['past', 'future']);
      expect(state.pastRounds.map((r) => r.id), ['past']);
    });
  });
}
