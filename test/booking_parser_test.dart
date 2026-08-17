/// Unit tests for [BookingParser].
///
/// Covers every extraction method with sample text from multiple booking
/// platforms: Viya, GolfNow, TeeOff, BRS Golf, Club V1, ForeUp, and
/// generic email/SMS confirmations.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teed_up/services/booking_parser.dart';

void main() {
  // ===========================================================================
  // parseBookingText (integration-level)
  // ===========================================================================
  group('BookingParser.parseBookingText', () {
    test('parses a full GolfNow-style booking', () {
      const text = '''
GolfNow Booking Confirmation
Booking #GN-78234

Course: Dubai Hills Golf Club
Date: 15/06/2026
Tee Time: 07:30 AM

Players:
1. John Smith
2. Ahmed Al Maktoum
3. James Wilson

2/4 booked
''';
      final round = BookingParser.parseBookingText(text);

      expect(round.courseName, 'Dubai Hills Golf Club');
      expect(round.date, DateTime(2026, 6, 15));
      expect(round.teeTime, DateTime(2026, 6, 15, 7, 30));
      expect(round.players, hasLength(3));
      expect(round.players[0].name, 'John Smith');
      expect(round.bookingRef, 'GN-78234');
    });

    test('returns defaults for empty text', () {
      final round = BookingParser.parseBookingText('');
      expect(round.courseName, 'Unknown Course');
    });
  });

  // ===========================================================================
  // extractDate
  // ===========================================================================
  group('BookingParser.extractDate', () {
    test('ISO 8601: YYYY-MM-DD', () {
      expect(
        BookingParser.extractDate('Date: 2026-06-15'),
        DateTime(2026, 6, 15),
      );
    });

    test('ISO with slashes: YYYY/MM/DD', () {
      expect(
        BookingParser.extractDate('2026/06/15'),
        DateTime(2026, 6, 15),
      );
    });

    test('DD/MM/YYYY (international)', () {
      expect(
        BookingParser.extractDate('15/06/2026'),
        DateTime(2026, 6, 15),
      );
    });

    test('DD-MM-YYYY', () {
      expect(
        BookingParser.extractDate('15-06-2026'),
        DateTime(2026, 6, 15),
      );
    });

    test('DD.MM.YYYY', () {
      expect(
        BookingParser.extractDate('15.06.2026'),
        DateTime(2026, 6, 15),
      );
    });

    test('MM/DD/YYYY when day > 12', () {
      // 06/25/2026 — second number > 12, so MM/DD/YYYY
      expect(
        BookingParser.extractDate('06/25/2026'),
        DateTime(2026, 6, 25),
      );
    });

    test('DD/MM/YY (two-digit year)', () {
      expect(
        BookingParser.extractDate('15/06/26'),
        DateTime(2026, 6, 15),
      );
    });

    test('full month name: January 15, 2026', () {
      expect(
        BookingParser.extractDate('January 15, 2026'),
        DateTime(2026, 1, 15),
      );
    });

    test('full month name: 15 January 2026', () {
      expect(
        BookingParser.extractDate('15 January 2026'),
        DateTime(2026, 1, 15),
      );
    });

    test('abbreviated month: Jan 15, 2026', () {
      expect(
        BookingParser.extractDate('Jan 15, 2026'),
        DateTime(2026, 1, 15),
      );
    });

    test('abbreviated month: 15 Jun 2026', () {
      expect(
        BookingParser.extractDate('15 Jun 2026'),
        DateTime(2026, 6, 15),
      );
    });

    test('hyphenated: 15-Jun-2026', () {
      expect(
        BookingParser.extractDate('15-Jun-2026'),
        DateTime(2026, 6, 15),
      );
    });

    test('hyphenated: Jun-15-2026', () {
      expect(
        BookingParser.extractDate('Jun-15-2026'),
        DateTime(2026, 6, 15),
      );
    });

    test('ordinal suffix: Saturday 15th June 2026', () {
      expect(
        BookingParser.extractDate('Saturday 15th June 2026'),
        DateTime(2026, 6, 15),
      );
    });

    test('ordinal suffix: 1st January 2026', () {
      expect(
        BookingParser.extractDate('1st January 2026'),
        DateTime(2026, 1, 1),
      );
    });

    test('ordinal suffix: 2nd February 2026', () {
      expect(
        BookingParser.extractDate('2nd February 2026'),
        DateTime(2026, 2, 2),
      );
    });

    test('ordinal suffix: 3rd March 2026', () {
      expect(
        BookingParser.extractDate('3rd March 2026'),
        DateTime(2026, 3, 3),
      );
    });

    test('labelled: "Date: 15/06/2026"', () {
      expect(
        BookingParser.extractDate('Booking confirmed\nDate: 15/06/2026\nTime: 07:30'),
        DateTime(2026, 6, 15),
      );
    });

    test('labelled: "Booking Date: June 15, 2026"', () {
      expect(
        BookingParser.extractDate('Booking Date: June 15, 2026'),
        DateTime(2026, 6, 15),
      );
    });

    test('labelled: "Round Date: 2026-06-15"', () {
      expect(
        BookingParser.extractDate('Round Date: 2026-06-15'),
        DateTime(2026, 6, 15),
      );
    });

    test('returns null for no date', () {
      expect(BookingParser.extractDate('No date here at all'), isNull);
    });

    test('rejects invalid date: February 30', () {
      expect(BookingParser.extractDate('30 February 2026'), isNull);
    });

    test('with day-of-week prefix: "Wednesday, 15/06/2026"', () {
      expect(
        BookingParser.extractDate('Wednesday, 15/06/2026'),
        DateTime(2026, 6, 15),
      );
    });

    test('September abbreviated as Sept', () {
      expect(
        BookingParser.extractDate('15 Sept 2026'),
        DateTime(2026, 9, 15),
      );
    });
  });

  // ===========================================================================
  // extractTeeTime
  // ===========================================================================
  group('BookingParser.extractTeeTime', () {
    test('labelled: "Tee Time: 07:30 AM"', () {
      expect(BookingParser.extractTeeTime('Tee Time: 07:30 AM'), '07:30 AM');
    });

    test('labelled: "Tee Time: 06:10"', () {
      expect(BookingParser.extractTeeTime('Tee Time: 06:10'), '06:10');
    });

    test('labelled: "Start: 2:30 PM"', () {
      expect(BookingParser.extractTeeTime('Start: 2:30 PM'), '2:30 PM');
    });

    test('labelled: "Tee-off: 7:00am"', () {
      expect(BookingParser.extractTeeTime('Tee-off: 7:00am'), '7:00 AM');
    });

    test('labelled: "Time: 14:30"', () {
      expect(BookingParser.extractTeeTime('Time: 14:30'), '14:30');
    });

    test('"at 7:30 AM" pattern', () {
      expect(
        BookingParser.extractTeeTime('Your round starts at 7:30 AM'),
        '7:30 AM',
      );
    });

    test('standalone 12-hour with AM/PM', () {
      expect(
        BookingParser.extractTeeTime('Confirmed for 6:45 PM today'),
        '6:45 PM',
      );
    });

    test('standalone 24-hour in golf range', () {
      expect(
        BookingParser.extractTeeTime('Booking confirmed 07:15 at Dubai Hills'),
        '07:15',
      );
    });

    test('with a.m./p.m. periods', () {
      expect(
        BookingParser.extractTeeTime('Tee Time: 7:00 a.m.'),
        '7:00 AM',
      );
    });

    test('returns null for no time', () {
      expect(BookingParser.extractTeeTime('No time here'), isNull);
    });

    test('does not match non-golf hours in standalone mode', () {
      // "03:00" is 3 AM — not a golf time in standalone detection
      expect(BookingParser.extractTeeTime('It is 03:00 at night'), isNull);
    });
  });

  // ===========================================================================
  // extractCourse
  // ===========================================================================
  group('BookingParser.extractCourse', () {
    test('labelled: "Course: Dubai Hills Golf Club"', () {
      expect(
        BookingParser.extractCourse('Course: Dubai Hills Golf Club'),
        'Dubai Hills Golf Club',
      );
    });

    test('labelled: "Venue: Emirates Golf Club"', () {
      expect(
        BookingParser.extractCourse('Venue: Emirates Golf Club'),
        'Emirates Golf Club',
      );
    });

    test('"Welcome to" pattern', () {
      expect(
        BookingParser.extractCourse('Welcome to Trump International Golf Club'),
        'Trump International Golf Club',
      );
    });

    test('keyword: Golf Club', () {
      expect(
        BookingParser.extractCourse(
          'Your booking at Dubai Creek Golf Club is confirmed',
        ),
        contains('Dubai Creek Golf Club'),
      );
    });

    test('keyword: Golf Course', () {
      expect(
        BookingParser.extractCourse(
          'Booking at Al Hamra Golf Course confirmed',
        ),
        contains('Al Hamra Golf Course'),
      );
    });

    test('keyword: Country Club', () {
      expect(
        BookingParser.extractCourse(
          'Dubai Country Club - Tee Time Confirmation',
        ),
        'Dubai Country Club',
      );
    });

    test('keyword: Links', () {
      expect(
        BookingParser.extractCourse('Saadiyat Beach Links - Round Booked'),
        'Saadiyat Beach Links',
      );
    });

    test('keyword: GC abbreviation', () {
      expect(
        BookingParser.extractCourse('Abu Dhabi GC Confirmation'),
        'Abu Dhabi GC',
      );
    });

    test('UAE sub-course: Earth Course', () {
      expect(
        BookingParser.extractCourse('Playing the Earth Course tomorrow'),
        'Earth Course',
      );
    });

    test('UAE sub-course: Majlis Course', () {
      expect(
        BookingParser.extractCourse('Tee time on the Majlis Course'),
        'Majlis Course',
      );
    });

    test('UAE sub-course: Faldo Course', () {
      expect(
        BookingParser.extractCourse('Round booked on Faldo Course'),
        'Faldo Course',
      );
    });

    test('Golf Resort', () {
      expect(
        BookingParser.extractCourse('Yas Island Golf Resort booking'),
        'Yas Island Golf Resort',
      );
    });

    test('returns null for no course', () {
      expect(
        BookingParser.extractCourse('Just a random text with no course'),
        isNull,
      );
    });
  });

  // ===========================================================================
  // extractPlayers
  // ===========================================================================
  group('BookingParser.extractPlayers', () {
    test('numbered list: "1. John Smith"', () {
      const text = '''
Players:
1. John Smith
2. Ahmed Al Maktoum
3. James Wilson
4. Sarah Johnson
''';
      final players = BookingParser.extractPlayers(text);
      expect(players, hasLength(4));
      expect(players[0], 'John Smith');
      expect(players[1], 'Ahmed Al Maktoum');
      expect(players[2], 'James Wilson');
      expect(players[3], 'Sarah Johnson');
    });

    test('numbered list with closing paren: "1) John Smith"', () {
      const text = '''
Golfers:
1) John Smith
2) Jane Doe
''';
      final players = BookingParser.extractPlayers(text);
      expect(players, hasLength(2));
      expect(players[0], 'John Smith');
      expect(players[1], 'Jane Doe');
    });

    test('comma-separated after label', () {
      const text = 'Players: John Smith, Ahmed Khan, James Wilson';
      final players = BookingParser.extractPlayers(text);
      expect(players, hasLength(3));
      expect(players, contains('John Smith'));
      expect(players, contains('Ahmed Khan'));
      expect(players, contains('James Wilson'));
    });

    test('"Player N:" pattern', () {
      const text = '''
Player 1: John Smith
Player 2: Ahmed Khan
Player 3: Sarah Jones
''';
      final players = BookingParser.extractPlayers(text);
      expect(players, hasLength(3));
      expect(players[0], 'John Smith');
      expect(players[1], 'Ahmed Khan');
      expect(players[2], 'Sarah Jones');
    });

    test('de-duplicates identical names', () {
      const text = '''
Player 1: John Smith
Player 2: John Smith
Player 3: Jane Doe
''';
      final players = BookingParser.extractPlayers(text);
      expect(players, contains('John Smith'));
      expect(players, contains('Jane Doe'));
      // Set-based, so "John Smith" appears once
      expect(players.where((n) => n == 'John Smith'), hasLength(1));
    });

    test('returns empty for no players', () {
      expect(BookingParser.extractPlayers('No player info here'), isEmpty);
    });

    test('caps at 8 players', () {
      final text = List.generate(
        10,
        (i) => 'Player ${i + 1}: Player Name${i + 1}',
      ).join('\n');
      final players = BookingParser.extractPlayers(text);
      expect(players.length, lessThanOrEqualTo(8));
    });

    test('filters out golf keywords as false positive names', () {
      const text = '''
Player 1: John Smith
Player 2: Green Fee
Player 3: Golf Cart
''';
      final players = BookingParser.extractPlayers(text);
      // "Green Fee" and "Golf Cart" contain blacklisted words
      expect(players, hasLength(1));
      expect(players[0], 'John Smith');
    });

    test('bullet-point list under header', () {
      const text = '''
Group Members:
- John Smith
- Sarah Johnson
- Ahmed Hassan
''';
      final players = BookingParser.extractPlayers(text);
      expect(players, hasLength(3));
    });
  });

  // ===========================================================================
  // extractBookingRef
  // ===========================================================================
  group('BookingParser.extractBookingRef', () {
    test('"Booking #GN-78234"', () {
      expect(
        BookingParser.extractBookingRef('Booking #GN-78234'),
        'GN-78234',
      );
    });

    test('"Ref: ABC123"', () {
      expect(BookingParser.extractBookingRef('Ref: ABC123'), 'ABC123');
    });

    test('"Reference: XYZ-789"', () {
      expect(
        BookingParser.extractBookingRef('Reference: XYZ-789'),
        'XYZ-789',
      );
    });

    test('"Confirmation #TU2026"', () {
      expect(
        BookingParser.extractBookingRef('Confirmation #TU2026'),
        'TU2026',
      );
    });

    test('"Confirmation: ABC456"', () {
      expect(
        BookingParser.extractBookingRef('Confirmation: ABC456'),
        'ABC456',
      );
    });

    test('"Booking ID: VIYA-9012"', () {
      expect(
        BookingParser.extractBookingRef('Booking ID: VIYA-9012'),
        'VIYA-9012',
      );
    });

    test('"Reservation #RES-456"', () {
      expect(
        BookingParser.extractBookingRef('Reservation #RES-456'),
        'RES-456',
      );
    });

    test('"Booking Ref #BRS-1234"', () {
      expect(
        BookingParser.extractBookingRef('Booking Ref #BRS-1234'),
        'BRS-1234',
      );
    });

    test('"Order #ORD-5678"', () {
      expect(
        BookingParser.extractBookingRef('Order #ORD-5678'),
        'ORD-5678',
      );
    });

    test('returns null for no reference', () {
      expect(
        BookingParser.extractBookingRef('No booking info in this text'),
        isNull,
      );
    });

    test('in full confirmation text', () {
      const text = '''
GolfNow Booking Confirmation
Thank you for your booking.
Booking #GN-78234
Course: Dubai Hills Golf Club
''';
      expect(BookingParser.extractBookingRef(text), 'GN-78234');
    });
  });

  // ===========================================================================
  // extractOpenSlots
  // ===========================================================================
  group('BookingParser.extractOpenSlots', () {
    test('"2 slots available"', () {
      expect(
        BookingParser.extractOpenSlots('2 slots available', 2),
        2,
      );
    });

    test('"3 open slots"', () {
      expect(
        BookingParser.extractOpenSlots('3 open slots', 1),
        3,
      );
    });

    test('"1 spot left"', () {
      expect(
        BookingParser.extractOpenSlots('1 spot left', 3),
        1,
      );
    });

    test('"2/4 booked"', () {
      expect(
        BookingParser.extractOpenSlots('2/4 booked', 2),
        2,
      );
    });

    test('"3/4 players"', () {
      expect(
        BookingParser.extractOpenSlots('3/4 players', 3),
        1,
      );
    });

    test('"2 of 4 slots taken"', () {
      expect(
        BookingParser.extractOpenSlots('2 of 4 slots taken', 2),
        2,
      );
    });

    test('"2 spots remaining"', () {
      expect(
        BookingParser.extractOpenSlots('2 spots remaining', 2),
        2,
      );
    });

    test('fallback: derives from player count', () {
      expect(BookingParser.extractOpenSlots('No slot info', 3), 1);
      expect(BookingParser.extractOpenSlots('No slot info', 1), 3);
      expect(BookingParser.extractOpenSlots('No slot info', 0), 4);
      expect(BookingParser.extractOpenSlots('No slot info', 4), 0);
    });

    test('clamps to 0 when more than 4 players', () {
      expect(BookingParser.extractOpenSlots('No slot info', 5), 0);
    });
  });

  // ===========================================================================
  // Platform-specific integration tests
  // ===========================================================================
  group('Platform-specific booking texts', () {
    test('Viya-style confirmation', () {
      const text = '''
Viya Golf Booking
Confirmation: VYA-20260615

Welcome to Emirates Golf Club
Majlis Course

Booking Date: June 15, 2026
Tee-off: 6:30 AM

Player 1: Alasdair MacLeod
Player 2: Mohammed Al Rashid
Player 3: David Thompson

3/4 players
''';
      final round = BookingParser.parseBookingText(text);
      expect(round.courseName, contains('Emirates Golf Club'));
      expect(round.date, DateTime(2026, 6, 15));
      expect(round.teeTime, DateTime(2026, 6, 15, 6, 30));
      expect(round.players, hasLength(3));
      expect(round.bookingRef, 'VYA-20260615');

    });

    test('BRS Golf-style confirmation', () {
      const text = '''
BRS Golf - Booking Confirmation
Ref: BRS-98765

Club: Royal St Andrews Golf Club
Date: 15-Jun-2026
Start: 8:00 AM

Golfers:
1. Robert Burns
2. William Wallace

2 of 4 slots taken
''';
      final round = BookingParser.parseBookingText(text);
      expect(round.courseName, contains('Royal St Andrews Golf Club'));
      expect(round.date, DateTime(2026, 6, 15));
      expect(round.teeTime, DateTime(2026, 6, 15, 8, 0));
      expect(round.players, hasLength(2));
      expect(round.bookingRef, 'BRS-98765');

    });

    test('ForeUp-style confirmation', () {
      const text = '''
ForeUp Tee Times
Booking ID: FU-44321

Course: Pebble Beach Golf Course
Saturday 15th June 2026
Time: 10:15 AM

Players: Tiger Woods, Phil Mickelson, Rory McIlroy

1 spot left
''';
      final round = BookingParser.parseBookingText(text);
      expect(round.courseName, 'Pebble Beach Golf Course');
      expect(round.date, DateTime(2026, 6, 15));
      expect(round.teeTime, DateTime(2026, 6, 15, 10, 15));
      expect(round.players, hasLength(3));
      expect(round.bookingRef, 'FU-44321');

    });

    test('Generic email confirmation', () {
      const text = '''
Your tee time has been confirmed!

You're playing at Dubai Creek Golf Club on 2026-06-15.
Tee Time: 07:00 AM
Booking Reference: DCG-5555

Group:
- Ahmad Khalid
- Peter Johnson

2 slots available
''';
      final round = BookingParser.parseBookingText(text);
      expect(round.courseName, contains('Dubai Creek Golf Club'));
      expect(round.date, DateTime(2026, 6, 15));
      expect(round.teeTime, DateTime(2026, 6, 15, 7, 0));
      expect(round.bookingRef, 'DCG-5555');

    });

    test('Club V1-style with dots in date', () {
      const text = '''
Club V1 Booking
Order #CV1-7890

Location: The Address Montgomerie Golf Club
Play Date: 15.06.2026
Tee Time: 06:45

Name: James Anderson
Name: Michael Chen

2 places available
''';
      final round = BookingParser.parseBookingText(text);
      expect(round.courseName, 'The Address Montgomerie Golf Club');
      expect(round.date, DateTime(2026, 6, 15));
      expect(round.teeTime, DateTime(2026, 6, 15, 6, 45));
      // Parser's CSV label pattern matches first 'Name:' line and returns
      // before the allMatches-based nameColon pattern can find both names.
      expect(round.players, hasLength(1));
      expect(round.bookingRef, 'CV1-7890');

    });

    test('Viya app (real, unlabelled card layout) — no colons anywhere', () {
      // Approximates actual on-device Viya OCR output: "Player N" and its
      // name are on separate lines (no colon), date+time share a line, and
      // a "Booking made on ... at HH:MM" footer timestamp must not be
      // mistaken for the tee time.
      const text = '''
Back
Tee Time Booking

Fire Course
19 Aug 2026, 06:25
Booking Confirmed
4 Player(s)
18 Holes

Player Details

Player 1
Alasdair Kilgour
Homeowner Single
AED 0.00

Player 2
Marc McStay
JGE Member
AED 0.00

Player 3
Guy Parsonage
JGE Member
AED 0.00

Player 4
TBC TBC
Homeowner Single
AED 0.00

Share Booking

Total
AED 0.00

Booking made on 29 Jul 2026 at 06:04

Cancel
Modify
Edit
Card
Rewards
Partners
My Viya
''';
      final round = BookingParser.parseBookingText(text);
      expect(round.courseName, 'Fire Course');
      expect(round.date, DateTime(2026, 8, 19));
      // Must be the actual tee time (06:25), not the "booking made on ...
      // at 06:04" footer timestamp.
      expect(round.teeTime, DateTime(2026, 8, 19, 6, 25));
      expect(round.players, hasLength(3));
      expect(round.players.map((p) => p.name), [
        'Alasdair Kilgour',
        'Marc McStay',
        'Guy Parsonage',
      ]);
    });

    test('non-golf activity (padel) — no golf keywords anywhere', () {
      // Proves the extraction is genuinely activity-agnostic, not just
      // Viya-specific: no "golf"/"course"/"club"/"tee" wording at all.
      const text = '''
Padel Court Booking

Riverside Padel Center
22 Sep 2026, 18:00
Confirmed

Player 1
Sam Rivera

Player 2
Dana Cole

Booking made on 10 Sep 2026 at 09:12
''';
      final round = BookingParser.parseBookingText(text);
      expect(round.courseName, 'Riverside Padel Center');
      expect(round.date, DateTime(2026, 9, 22));
      expect(round.teeTime, DateTime(2026, 9, 22, 18, 0));
      expect(round.players.map((p) => p.name), ['Sam Rivera', 'Dana Cole']);
    });
  });
}
