// The tee time and the phone are in the same timezone. The booking says
// 06:30, the round should say 06:30, and the calendar should say 06:30.
// The correct amount of conversion is therefore ZERO.
//
// Both tee-time bugs were conversions the code had no business doing:
//   write (1.8.x): built the event from tz.local, which was UTC
//   read  (1.11.1+59): read .hour off a TZDateTime carrying GMT
//
// This asserts the property that actually matters — that a wall clock
// survives the trip to the calendar and back unchanged — and asserts it
// while tz.local is deliberately WRONG, because that is the condition under
// which both bugs occurred.
//
// Run across offsets with:
//   for z in UTC Europe/London Asia/Dubai America/New_York \
//            Asia/Kolkata Australia/Eucla Pacific/Chatham; do
//     TZ=$z flutter test test/tee_time_roundtrip_test.dart || echo "FAILED $z"
//   done
//
// Kolkata (+05:30), Eucla (+08:45) and Chatham (+12:45) are in the list on
// purpose: a conversion bug that happens to cancel out on whole-hour
// offsets will not survive a 45-minute one.

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:all_teed_up/services/calendar_service.dart';

/// Exactly what `_buildEvent` does on the way in.
DateTime writeToInstant(DateTime wallClock, tz.Location localTz) =>
    tz.TZDateTime.from(wallClock, localTz);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // The failing condition from the real bug: the zone database is loaded but
  // `local` was never pointed at the device zone, so it is UTC.
  setUp(() => tz.setLocalLocation(tz.UTC));

  group('a tee time survives the calendar round trip unchanged', () {
    final times = <List<int>>[
      [6, 30], // the real booking
      [0, 0], // midnight — rolls the date if anything shifts
      [23, 45], // late evening — rolls the date the other way
      [12, 0],
      [7, 15],
    ];

    for (final t in times) {
      test(
          '${t[0].toString().padLeft(2, '0')}:'
          '${t[1].toString().padLeft(2, '0')} on this machine', () {
        final wall = DateTime(2026, 8, 30, t[0], t[1]);

        final instant = writeToInstant(wall, tz.local);
        final back = CalendarService.localWallClock(instant);

        expect(back.hour, wall.hour, reason: 'hour drifted');
        expect(back.minute, wall.minute, reason: 'minute drifted');
        expect(back.day, wall.day, reason: 'date rolled');
        expect(back.month, wall.month);
        expect(back.year, wall.year);
      });
    }

    test('holds even when tz.local is a zone the device is not in', () {
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      final wall = DateTime(2026, 8, 30, 6, 30);

      final back =
          CalendarService.localWallClock(writeToInstant(wall, tz.local));

      expect(back.hour, 6);
      expect(back.minute, 30);
      expect(back.day, 30);
    });

    test('the stored instant is the one the device means by that wall clock',
        () {
      final wall = DateTime(2026, 8, 30, 6, 30);
      final instant = writeToInstant(wall, tz.local);

      // Independent oracle: the epoch the OS assigns to that local wall clock.
      expect(instant.millisecondsSinceEpoch, wall.millisecondsSinceEpoch);
    });
  });
}
