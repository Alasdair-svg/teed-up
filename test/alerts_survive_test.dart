// A decline the user is never shown is the same as a decline never detected.
//
// This is the fourth decline bug in this app, and the one furthest downstream:
// detection worked, and the alert still never reached the user.
//
// Two alert stores existed and NEITHER was connected end to end.
//   - RsvpMonitor wrote every background-detected alert to SharedPreferences
//     (deliberately: a background isolate cannot reliably open SQLite).
//     loadPersistedAlerts() read that store and had no callers.
//   - main.dart loaded alerts from SQLite via queryAllAlerts(). Nothing has
//     ever called insertAlert(), so it always returned empty — and the
//     setAlerts([]) that followed WIPED whatever the running app had found.
//
// So: a decline found in the background was never shown; one found in the
// foreground survived only until the next cold start.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/models/rsvp_change.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/services/rsvp_monitor.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  RsvpChange decline(String who, {String event = 'EVT-1'}) => RsvpChange(
        eventId: event,
        playerName: who,
        playerEmail: '$who@example.com',
        oldStatus: RsvpStatus.confirmed,
        newStatus: RsvpStatus.declined,
        detectedAt: DateTime(2026, 9, 3, 9),
      );

  test('an alert saved by the app is read back after a cold start', () async {
    await RsvpMonitor.saveAlerts([decline('Marc McStay')]);
    // What main.dart does on launch.
    final restored = await RsvpMonitor.loadPersistedAlerts();
    expect(restored.map((a) => a.playerName), ['Marc McStay']);
    expect(restored.single.newStatus, RsvpStatus.declined);
  });

  test('read state survives a cold start', () async {
    await RsvpMonitor.saveAlerts([decline('Marc McStay').copyWith(isRead: true)]);
    final restored = await RsvpMonitor.loadPersistedAlerts();
    expect(restored.single.isRead, isTrue,
        reason: 'a dismissed alert must not come back unread every launch');
  });

  test('the same decline seen twice is stored once', () async {
    // The 60s foreground tick and the 15-minute background pass both see it.
    final a = decline('Marc McStay');
    expect(RsvpMonitor.alertKey(a), RsvpMonitor.alertKey(decline('Marc McStay')));
  });

  test('different players on one event are different alerts', () {
    expect(RsvpMonitor.alertKey(decline('Marc McStay')),
        isNot(RsvpMonitor.alertKey(decline('Hamish Clark'))));
  });

  test('the same player on different events are different alerts', () {
    expect(RsvpMonitor.alertKey(decline('Marc McStay', event: 'A')),
        isNot(RsvpMonitor.alertKey(decline('Marc McStay', event: 'B'))));
  });

  test('an empty store yields no alerts rather than throwing', () async {
    expect(await RsvpMonitor.loadPersistedAlerts(), isEmpty);
  });

  test('AppState surfaces a restored alert as unread', () async {
    await RsvpMonitor.saveAlerts([decline('Marc McStay')]);
    final state = AppState()..setAlerts(await RsvpMonitor.loadPersistedAlerts());
    expect(state.alerts, hasLength(1));
    expect(state.unreadAlertCount, 1,
        reason: 'the badge is the only thing that tells the user to look');
  });
}
