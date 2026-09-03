// An acceptance on the calendar has to show as accepted in the app.
//
// Reported from the field: "when the calendar invites are being accepted and
// showing as such on the calendar they still say pending in the app".
//
// The ONLY place a player's rsvpStatus was ever written was AppState.updateRsvp
// — the user tapping a name by hand. So a player could accept, the acceptance
// could sync to the calendar, RsvpMonitor could read it and raise an alert
// about it, and the round detail screen would still say Pending forever.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_teed_up/models/golf_round.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/providers/app_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Player p(String name, {String? email, RsvpStatus status = RsvpStatus.pending}) =>
      Player(id: name, name: name, email: email, rsvpStatus: status);

  GolfRound roundWith(List<Player> players) => GolfRound(
        id: 'r1',
        courseName: 'Emirates Golf Club',
        date: DateTime(2026, 9, 27),
        teeTime: DateTime(2026, 9, 27, 7, 20),
        players: players,
        calendarEventId: 'EVT-1',
        isCreator: true,
      );

  AppState stateWith(List<Player> players) =>
      AppState()..addRound(roundWith(players));

  test('an acceptance on the calendar reaches the round', () {
    final s = stateWith([p('Marc McStay', email: 'marc@example.com')]);
    expect(s.getRound('r1')!.players.first.rsvpStatus, RsvpStatus.pending);

    final changed = s.applyCalendarStatuses('r1', [
      p('Marc McStay', email: 'marc@example.com', status: RsvpStatus.accepted),
    ]);

    expect(changed, isTrue);
    expect(s.getRound('r1')!.players.first.rsvpStatus, RsvpStatus.accepted);
  });

  test('a decline reaches the round too', () {
    final s = stateWith([
      p('Guy Parsonage', email: 'guy@example.com', status: RsvpStatus.accepted),
    ]);
    s.applyCalendarStatuses('r1', [
      p('Guy Parsonage', email: 'guy@example.com', status: RsvpStatus.declined),
    ]);
    expect(s.getRound('r1')!.players.first.rsvpStatus, RsvpStatus.declined);
  });

  test('matches by email even when the display name differs', () {
    // A calendar attendee's name is whatever their account says, not what
    // the booking screenshot called them.
    final s = stateWith([p('Marc McStay', email: 'marc@example.com')]);
    s.applyCalendarStatuses('r1', [
      p('M. McStay', email: 'MARC@example.com', status: RsvpStatus.accepted),
    ]);
    expect(s.getRound('r1')!.players.first.rsvpStatus, RsvpStatus.accepted);
  });

  test('falls back to name for a player with no email', () {
    final s = stateWith([p('Hamish Clark')]);
    s.applyCalendarStatuses('r1', [
      p('hamish clark', status: RsvpStatus.accepted),
    ]);
    expect(s.getRound('r1')!.players.first.rsvpStatus, RsvpStatus.accepted);
  });

  test('an attendee missing from a read never resets a known status', () {
    // A sync blip must not silently un-accept someone.
    final s = stateWith([
      p('Marc McStay', email: 'marc@example.com', status: RsvpStatus.accepted),
    ]);
    final changed = s.applyCalendarStatuses('r1', const []);
    expect(changed, isFalse);
    expect(s.getRound('r1')!.players.first.rsvpStatus, RsvpStatus.accepted);
  });

  test('no change reports false, so polls do not churn the UI', () {
    final s = stateWith([
      p('Marc McStay', email: 'marc@example.com', status: RsvpStatus.accepted),
    ]);
    expect(
      s.applyCalendarStatuses('r1', [
        p('Marc McStay', email: 'marc@example.com', status: RsvpStatus.accepted),
      ]),
      isFalse,
    );
  });

  test('an unknown round is ignored rather than throwing', () {
    expect(stateWith([p('Marc')]).applyCalendarStatuses('nope', []), isFalse);
  });
}
