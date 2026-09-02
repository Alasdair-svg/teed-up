import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/models/player_diff.dart';
import 'package:all_teed_up/services/calendar_service.dart';

/// The note an unchanged player reads at the top of an amended event.
///
/// Its whole purpose is to tell someone who did not change anything why
/// the event just reappeared in their calendar, so the wording matters as
/// much as the trigger. See [CalendarService.buildChangeNote].
void main() {
  Player p(String name) => Player(id: name, name: name, email: null);
  final on2Sep = DateTime(2026, 9, 2);

  PlayerDiff diff({
    List<Player> added = const [],
    List<Player> removed = const [],
    List<Player> unchanged = const [],
  }) =>
      PlayerDiff(added: added, removed: removed, unchanged: unchanged);

  group('buildChangeNote', () {
    test('is null when the group is unchanged', () {
      expect(
        CalendarService.buildChangeNote(
          diff(unchanged: [p('Marc McStay'), p('Alasdair Kilgour')]),
          now: on2Sep,
        ),
        isNull,
      );
    });

    test('names a single arrival', () {
      expect(
        CalendarService.buildChangeNote(
          diff(added: [p('Hamish Clark')], unchanged: [p('Marc McStay')]),
          now: on2Sep,
        ),
        '🔄 Updated 2 Sep — Hamish Clark is now playing',
      );
    });

    test('names a single departure', () {
      expect(
        CalendarService.buildChangeNote(
          diff(removed: [p('Rich Smith')], unchanged: [p('Marc McStay')]),
          now: on2Sep,
        ),
        '🔄 Updated 2 Sep — Rich Smith is no longer playing',
      );
    });

    test('reports a swap as one sentence, arrival first', () {
      expect(
        CalendarService.buildChangeNote(
          diff(
            added: [p('Zach Brown')],
            removed: [p('Rich Smith')],
            unchanged: [p('Marc McStay'), p('Alasdair Kilgour')],
          ),
          now: on2Sep,
        ),
        '🔄 Updated 2 Sep — Zach Brown is now playing; '
        'Rich Smith is no longer playing',
      );
    });

    test('uses plural verbs and an Oxford-free list for several names', () {
      expect(
        CalendarService.buildChangeNote(
          diff(added: [p('Anchin Kilgour'), p('Jack Kilgour')]),
          now: on2Sep,
        ),
        '🔄 Updated 2 Sep — Anchin Kilgour and Jack Kilgour are now playing',
      );
      expect(
        CalendarService.buildChangeNote(
          diff(added: [p('A One'), p('B Two'), p('C Three')]),
          now: on2Sep,
        ),
        '🔄 Updated 2 Sep — A One, B Two and C Three are now playing',
      );
    });

    test('formats the month as a short name, not a number', () {
      final note = CalendarService.buildChangeNote(
        diff(added: [p('Hamish Clark')]),
        now: DateTime(2026, 12, 25),
      );
      expect(note, contains('25 Dec'));
    });
  });
}
