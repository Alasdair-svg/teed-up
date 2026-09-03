// Rescanning an amended booking must keep the round attached to its
// calendar event.
//
// It didn't. The review screen rebuilt the round from the scan and never
// carried calendarEventId across, so the amendment orphaned the event: it
// was never updated and never deleted. Every player kept an invite naming
// the old group, the app showed the new line-up while the calendar showed
// the old one, and RsvpMonitor lost the only handle it had on the round —
// so declines on it could never be detected either.
//
// Reproduced end-to-end on the Simulator before this fix: after amending,
// the stored round came back with "calendarEventId": null and the event
// still listed the departed player.
import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/models/golf_round.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/screens/scan_screen.dart';

void main() {
  Player p(String n) => Player(id: n, name: n, email: null);
  final now = DateTime(2026, 9, 3, 8, 46);

  final existing = GolfRound(
    id: 'round_1',
    courseName: 'Emirates Golf Club',
    date: DateTime(2026, 9, 27),
    teeTime: DateTime(2026, 9, 27, 7, 20),
    players: [p('Alasdair Kilgour'), p('Guy Parsonage')],
    bookingRef: 'VG-884213',
    location: 'Emirates Hills',
    calendarEventId: 'EVT-123',
    isCreator: true,
    familyNotified: true,
  );

  GolfRound amend({
    GolfRound? matched,
    List<Player>? players,
    String? bookingRef = 'VG-884213',
  }) =>
      buildReviewedRound(
        matched: matched,
        courseName: 'Emirates Golf Club',
        date: DateTime(2026, 9, 27),
        teeTime: DateTime(2026, 9, 27, 7, 20),
        players: players ?? [p('Alasdair Kilgour'), p('Jack Kilgour')],
        bookingRef: bookingRef,
        notifyingFamily: false,
        now: now,
      );

  group('amending an existing round', () {
    test('keeps the calendar event id', () {
      expect(amend(matched: existing).calendarEventId, 'EVT-123');
    });

    test('keeps the round id, so it updates in place', () {
      expect(amend(matched: existing).id, 'round_1');
    });

    test('keeps ownership, location and family-notified state', () {
      final r = amend(matched: existing);
      expect(r.isCreator, isTrue);
      expect(r.location, 'Emirates Hills');
      expect(r.familyNotified, isTrue);
    });

    test('applies the new line-up', () {
      expect(
        amend(matched: existing).players.map((p) => p.name),
        ['Alasdair Kilgour', 'Jack Kilgour'],
      );
    });

    test('keeps the old booking ref when the rescan read none', () {
      expect(
          amend(matched: existing, bookingRef: null).bookingRef, 'VG-884213');
    });
  });

  group('a brand-new round', () {
    test('has no calendar event yet and a fresh id', () {
      final r = amend(matched: null);
      expect(r.calendarEventId, isNull);
      expect(r.id, 'round_${now.millisecondsSinceEpoch}');
      expect(r.isCreator, isTrue);
    });
  });
}
