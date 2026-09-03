// A detected decline has to reach the screen, not just the disk.
//
// checkForChanges is static and writes alerts straight to SharedPreferences
// so it can run in a background isolate. Nothing told the RUNNING app that a
// poll had found anything, so a decline spotted by the 60-second foreground
// poll sat in storage, invisible, until the next cold start.
//
// And it usually did not survive even that: the app saves its own alert list
// on every notifyListeners, and that save REPLACED the store — so the stale
// in-memory list overwrote the alert the poll had just written. Detected,
// persisted, then deleted, without ever being shown.
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
        oldStatus: RsvpStatus.accepted,
        newStatus: RsvpStatus.declined,
        detectedAt: DateTime(2026, 9, 3, 9),
      );

  group('a poll result reaches the app', () {
    test('new alerts are added and listeners told', () {
      final s = AppState();
      var notified = 0;
      s.addListener(() => notified++);

      expect(s.addAlerts([decline('Marc McStay')]), 1);
      expect(s.alerts, hasLength(1));
      expect(s.unreadAlertCount, 1);
      expect(notified, 1, reason: 'the badge must repaint');
    });

    test('the same decline seen by two polls is added once', () {
      final s = AppState()..addAlerts([decline('Marc McStay')]);
      expect(s.addAlerts([decline('Marc McStay')]), 0,
          reason: 'the 60s tick and the background pass both see it');
      expect(s.alerts, hasLength(1));
    });

    test('different people on one round are separate alerts', () {
      final s = AppState()
        ..addAlerts([decline('Marc McStay'), decline('Guy Parsonage')]);
      expect(s.alerts, hasLength(2));
    });

    test('nothing new does not churn listeners', () {
      final s = AppState()..addAlerts([decline('Marc McStay')]);
      var notified = 0;
      s.addListener(() => notified++);
      expect(s.addAlerts([decline('Marc McStay')]), 0);
      expect(notified, 0);
    });
  });

  group('saving never destroys a background-written alert', () {
    test('an alert only in the store survives a foreground save', () async {
      // What a background isolate does mid-session.
      await RsvpMonitor.saveAlerts([decline('Guy Parsonage', event: 'EVT-BG')]);

      // What the app does on its next notifyListeners, holding a list that
      // knows nothing about it.
      await RsvpMonitor.saveAlerts([decline('Marc McStay', event: 'EVT-FG')]);

      final stored = await RsvpMonitor.loadPersistedAlerts();
      expect(stored.map((a) => a.playerName),
          containsAll(['Marc McStay', 'Guy Parsonage']),
          reason: 'the blind replace deleted the background alert');
    });

    test('read state from memory wins for alerts both sides hold', () async {
      await RsvpMonitor.saveAlerts([decline('Marc McStay')]);
      await RsvpMonitor.saveAlerts([decline('Marc McStay').copyWith(isRead: true)]);
      final stored = await RsvpMonitor.loadPersistedAlerts();
      expect(stored, hasLength(1));
      expect(stored.single.isRead, isTrue,
          reason: 'a dismissed alert must not resurface unread');
    });
  });
}
