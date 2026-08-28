import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/services/booking_parser.dart';

/// The exact text ML Kit produced from Alasdair's real Viya booking
/// screenshot (Earth Course, 30 Aug 2026), read block-by-block off the
/// "What the scan read" diagnostic in the iOS Simulator on 28 Aug 2026.
///
/// The first row's label came back as a bare "Player" — the digit was never
/// recognised — while rows 2, 3 and 4 kept theirs. That asymmetry is the
/// whole point of this fixture: do not "tidy" it.
const _viyaOcr = '''
<Back
Tee Time Booking
Earth Course
30 Aug 2026, 06:30
Booking Confirmed
Player Details
Player
Alasdair Kilgour
Homeowner Single
Player 2
Marc McStay
JGE Member
Player 3
Michael Murphy
JGE Member
Player 4
Guy Parsonage
JGE Member
Share Booking
4 Player(s)
18 Holes
AED 0.00
AED 0.00
AED 0.00
''';

void main() {
  group('Viya booking — real OCR', () {
    test('finds all four players including the bare "Player" marker', () {
      final players = BookingParser.extractPlayers(_viyaOcr);
      expect(players, [
        'Alasdair Kilgour',
        'Marc McStay',
        'Michael Murphy',
        'Guy Parsonage',
      ]);
    });

    test('never mistakes a price row for a name', () {
      expect(BookingParser.extractPlayers(_viyaOcr),
          isNot(contains(anyOf('AED 000', 'AED 0.00'))));
    });

    test('reads the booking\'s own declared group size', () {
      expect(BookingParser.extractDeclaredPlayerCount(_viyaOcr), 4);
      expect(BookingParser.extractDeclaredPlayerCount('no count here'), isNull);
    });

    test('course, date and tee time are unchanged by the fix', () {
      expect(BookingParser.extractCourse(_viyaOcr), 'Earth Course');
      final d = BookingParser.extractDate(_viyaOcr);
      expect(d, isNotNull);
      expect([d!.year, d.month, d.day], [2026, 8, 30]);
      expect(BookingParser.extractTeeTime(_viyaOcr), contains('06:30'));
    });
  });
}
