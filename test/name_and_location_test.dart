// Two capabilities that were asked for and had never been built:
// splitting a player's name into forename and surname, and extracting the
// venue's LOCATION as distinct from the course name.
//
// Before this, Player held a single `name` string and the calendar event's
// location field was the course name repeated — which tells a maps app
// nothing it did not already have.
//
// HONESTY NOTE ON FIXTURES: only the Viya block in
// booking_parser_viya_test.dart is a real OCR sample. The location fixtures
// below are SYNTHETIC — written to cover address shapes the parser claims to
// handle. They prove the code does what it says on those shapes. They do NOT
// prove real-world coverage of any booking system, and must not be cited as
// if they did.

import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/services/booking_parser.dart';

Player p(String name) => Player(id: 'x', name: name);

void main() {
  group('forename and surname', () {
    test('an ordinary two-part name', () {
      expect(p('Alasdair Kilgour').firstName, 'Alasdair');
      expect(p('Alasdair Kilgour').lastName, 'Kilgour');
    });

    test('a middle name or initial does not become the surname', () {
      expect(p('Marc J McStay').firstName, 'Marc');
      expect(p('Marc J McStay').lastName, 'McStay');
      expect(p('Guy Robert Parsonage').lastName, 'Parsonage');
    });

    test('surname-first, as tee sheets sorted by surname write it', () {
      expect(p('McStay, Marc').firstName, 'Marc');
      expect(p('McStay, Marc').lastName, 'McStay');
      expect(p('Kilgour, Alasdair J').firstName, 'Alasdair');
      expect(p('Kilgour, Alasdair J').lastName, 'Kilgour');
    });

    test('particles stay attached to the surname', () {
      // A naive last-word split truncates these to "Berg" and "Silva".
      expect(p('Johan van der Berg').lastName, 'van der Berg');
      expect(p('Ana de Silva').lastName, 'de Silva');
      expect(p('Ahmed bin Rashid').lastName, 'bin Rashid');
    });

    test('a single word is treated as a forename, not a surname', () {
      expect(p('Alasdair').firstName, 'Alasdair');
      expect(p('Alasdair').lastName, isNull);
    });

    test('placeholders do not produce a name', () {
      expect(p('Player TBC').firstName, '');
      expect(p('Player TBC').lastName, isNull);
      expect(p('TBC').firstName, '');
    });

    test('stray whitespace and trailing commas are tolerated', () {
      expect(p('  Marc   McStay  ').firstName, 'Marc');
      expect(p('  Marc   McStay  ').lastName, 'McStay');
      expect(p('Guy Parsonage,').lastName, 'Parsonage');
    });
  });

  group('location extraction (synthetic fixtures)', () {
    test('an explicitly labelled address', () {
      expect(
        BookingParser.extractLocation(
            'Tee Time Confirmed\nAddress: Emirates Hills, Dubai, UAE\n06:30'),
        'Emirates Hills, Dubai, UAE',
      );
    });

    test('a street address on its own line', () {
      expect(
        BookingParser.extractLocation(
            'Sunningdale Golf Club\nRidgemount Road, Sunningdale\n07:10'),
        contains('Ridgemount Road'),
      );
    });

    test('a UK postcode line without a street word', () {
      expect(
        BookingParser.extractLocation(
            'The Belfry\nWishaw, Sutton Coldfield B76 9PR\nTee time 08:00'),
        contains('B76 9PR'),
      );
    });

    test('a US ZIP line', () {
      expect(
        BookingParser.extractLocation(
            'Pebble Beach\n1700 17 Mile Drive, Pebble Beach, CA 93953'),
        contains('93953'),
      );
    });

    test('returns null rather than guessing when there is no address', () {
      // The real Viya booking carries no address at all. A wrong location is
      // worse than none — it sends someone to the wrong place confidently.
      expect(
        BookingParser.extractLocation(
            'Tee Time Booking\nEarth Course\n30 Aug 2026, 06:30\n'
            'Player 2\nMarc McStay\nJGE Member\n4 Player(s)\nAED 0.00'),
        isNull,
      );
    });

    test('a price, a time or a booking reference is never a location', () {
      expect(BookingParser.extractLocation('Address: AED 250.00'), isNull);
      expect(BookingParser.extractLocation('Address: 06:30'), isNull);
      expect(
          BookingParser.extractLocation('Address: Booking Ref 88213'), isNull);
    });
  });
}
