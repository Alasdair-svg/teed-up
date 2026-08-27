// The last chance to catch a wrong tee time before it reaches everyone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/models/models.dart';
import 'package:all_teed_up/widgets/invite_review_sheet.dart';

GolfRound _round({List<Player>? players}) {
  final t = DateTime(2026, 9, 3, 6, 30);
  return GolfRound(
    id: 'r1',
    courseName: 'Emirates Golf Club',
    date: t,
    teeTime: t,
    players: players ??
        [
          Player(id: '1', name: 'Guy Parsonage', email: 'guy@example.com'),
          Player(id: '2', name: 'Zachary Drury', email: 'zach@example.com'),
        ],
  );
}

void main() {
  Future<InviteReviewChoice?> open(WidgetTester t, GolfRound r) async {
    InviteReviewChoice? choice;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async =>
                choice = await showInviteReviewSheet(ctx, round: r),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return choice;
  }

  testWidgets('shows the tee time prominently — the detail that goes wrong',
      (t) async {
    await open(t, _round());
    expect(find.text('Want to change anything?'), findsOneWidget);
    expect(find.textContaining('06:30'), findsOneWidget);
    expect(find.textContaining('Thursday 3 September'), findsOneWidget);
  });

  testWidgets('warns when a player has no email', (t) async {
    await open(
      t,
      _round(players: [
        Player(id: '1', name: 'Guy Parsonage', email: 'guy@example.com'),
        Player(id: '2', name: 'No Email Guy'),
      ]),
    );
    expect(find.textContaining("won't receive this"), findsOneWidget);
  });

  testWidgets('Send returns send; Change returns edit', (t) async {
    await open(t, _round());
    await t.tap(find.text('Send invite'));
    await t.pumpAndSettle();

    await open(t, _round());
    await t.tap(find.text('Change something'));
    await t.pumpAndSettle();
    expect(find.text('Want to change anything?'), findsNothing);
  });
}
