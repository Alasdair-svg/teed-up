// Both real parser failures were STRUCTURAL, not vocabulary:
//   player 3 lost - the parser broke on the first non-blank line after a
//                   marker, and ML Kit had put the price there
//   player 1 lost - the marker regex required a digit, and ML Kit had
//                   dropped the "1"
//
// Neither would have been caught by testing more booking formats. Both are
// deformations of ONE format. So this takes the real Viya OCR sample and
// deforms it the ways OCR actually deforms things, and asserts the parser
// still finds all four players.
//
// The base fixture is the genuine sample read off the diagnostic panel on
// the iOS Simulator, 28 Aug 2026. The deformations are synthetic, but each
// one mimics a failure mode observed in real ML Kit output rather than an
// invented one.

import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/services/booking_parser.dart';

const _base = '''
<Back
Tee Time Booking
Earth Course
30 Aug 2026, 06:30
Booking Confirmed
Player Details
Player 1
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
''';

const _four = [
  'Alasdair Kilgour',
  'Marc McStay',
  'Michael Murphy',
  'Guy Parsonage',
];

void main() {
  group('the real sample, deformed the way OCR deforms things', () {
    test('undeformed - the control', () {
      expect(BookingParser.extractPlayers(_base), _four);
    });

    test('a price row lands between the marker and the name', () {
      // Exactly what lost Michael Murphy: ML Kit returns spatial blocks, and
      // the row's price was emitted before its name.
      final t = _base.replaceAll(
          'Player 3\nMichael Murphy', 'Player 3\nAED 0.00\nMichael Murphy');
      expect(BookingParser.extractPlayers(t), containsAll(_four));
    });

    test('a membership tier lands between the marker and the name', () {
      final t = _base.replaceAll(
          'Player 2\nMarc McStay', 'Player 2\nJGE Member\nMarc McStay');
      expect(BookingParser.extractPlayers(t), containsAll(_four));
    });

    test('a marker loses its digit', () {
      // Exactly what lost Alasdair Kilgour.
      expect(BookingParser.extractPlayers(_base.replaceAll('Player 1', 'Player')),
          containsAll(_four));
    });

    test('every marker loses its digit', () {
      var t = _base;
      for (var i = 1; i <= 4; i++) {
        t = t.replaceAll('Player $i', 'Player');
      }
      expect(BookingParser.extractPlayers(t), containsAll(_four));
    });

    test('markers are lowercased', () {
      expect(
          BookingParser.extractPlayers(_base.replaceAll('Player ', 'player ')),
          containsAll(_four));
    });

    test('a marker and its name are merged onto one line', () {
      final t = _base.replaceAll(
          'Player 4\nGuy Parsonage', 'Player 4 Guy Parsonage');
      expect(BookingParser.extractPlayers(t), containsAll(_four));
    });

    test('blank lines appear between rows', () {
      expect(BookingParser.extractPlayers(_base.replaceAll('\n', '\n\n')),
          containsAll(_four));
    });

    test('trailing spaces on every line', () {
      final t = _base.split('\n').map((l) => '$l  ').join('\n');
      expect(BookingParser.extractPlayers(t), containsAll(_four));
    });

    test('the whole block arrives in reverse order', () {
      // The pathological case for anything that assumes reading order.
      final t = _base.split('\n').reversed.join('\n');
      final found = BookingParser.extractPlayers(t);
      expect(found.length, greaterThanOrEqualTo(3),
          reason: 'reversed blocks should still yield most players, '
              'got: $found');
    });
  });

  group('label vocabulary found by researching other booking systems', () {
    test('label-first player count, as CPS Golf writes it', () {
      expect(BookingParser.extractDeclaredPlayerCount('Number of players: 3'),
          3);
      expect(BookingParser.extractDeclaredPlayerCount('Players: 2'), 2);
    });

    test('count-first player count, as Viya writes it', () {
      expect(BookingParser.extractDeclaredPlayerCount('4 Player(s)'), 4);
      expect(BookingParser.extractDeclaredPlayerCount('3 golfers'), 3);
    });

    test('Confirmation ID, as TeeOff and GolfNow write it', () {
      expect(BookingParser.extractBookingRef('Confirmation ID: A7X92B'),
          'A7X92B');
    });

    test('Tee Time Identification number, as foreUP writes it', () {
      expect(BookingParser.extractBookingRef('Tee Time ID 558213'), '558213');
    });
  });
}
