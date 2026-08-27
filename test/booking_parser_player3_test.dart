// Reproduces a real failure: a 4-player Viya booking shared into the app
// yielded only 3 players — Michael Murphy, player 3, was always the one
// lost. The identical screenshot picked from the gallery gave all 4.
//
// The difference is ML Kit block ordering. Each row has the name on the left
// and "AED 0.00" on the right; which one is emitted first is not stable.

import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/services/booking_parser.dart';

/// Name first, price after — the ordering that worked.
const _nameFirst = '''
Tee Time Booking
Earth Course
30 Aug 2026, 06:30
Booking Confirmed
4 Player(s)
18 Holes
Player Details
Player 1
Alasdair Kilgour
AED 0.00
Homeowner Single
Player 2
Marc McStay
AED 0.00
JGE Member
Player 3
Michael Murphy
AED 0.00
JGE Member
Player 4
Guy Parsonage
AED 0.00
JGE Member
''';

/// The price emitted BEFORE the name on one row — the ordering that lost a
/// player.
const _priceBeforeName = '''
Tee Time Booking
Earth Course
30 Aug 2026, 06:30
Booking Confirmed
4 Player(s)
18 Holes
Player Details
Player 1
Alasdair Kilgour
AED 0.00
Homeowner Single
Player 2
Marc McStay
AED 0.00
JGE Member
Player 3
AED 0.00
Michael Murphy
JGE Member
Player 4
Guy Parsonage
AED 0.00
JGE Member
''';

void main() {
  test('name-first ordering finds all four', () {
    final players = BookingParser.extractPlayers(_nameFirst);
    expect(players, contains('Michael Murphy'));
    expect(players.length, 4);
  });

  test('a price line before the name must not lose that player', () {
    final players = BookingParser.extractPlayers(_priceBeforeName);
    expect(players, contains('Michael Murphy'),
        reason: 'player 3 was dropped because the scan stopped at the first '
            'non-blank line after the "Player 3" marker');
    expect(players.length, 4);
  });
}
