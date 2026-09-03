import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:all_teed_up/services/calendar_service.dart';

// The tee time has gone wrong three times now, in three different ways.
//
//   Write path (1.7.x): the event was built from a bare wall clock with no
//   zone, so a 06:30 booking landed at the wrong instant.
//
//   Read path, first attempt (1.11.1+59): the event came back as a
//   TZDateTime in the event's own zone (GMT), and the code read .hour off
//   it — 02:30 for a 06:30 Dubai tee.
//
//   Read path, actual cause (1.11.1+60, covered here): the obvious fix,
//   `instant.toLocal()`, is a NO-OP. TZDateTime overrides toLocal to
//   convert to the timezone package's `tz.local`, not the OS zone. In any
//   isolate where TimezoneService.configure() has not run, tz.local is
//   still UTC and nothing moves. Measured on the Simulator:
//
//     ms=1788057000000  tzName=GMT  toLocal=02:30Z  dartNowOffsetMin=240
//
// The first version of this test asserted the result against
// `stored.toLocal()` — the very call that was broken — so it passed against
// a fix that did nothing. These assert against the epoch instead, which is
// an oracle independent of the implementation.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  // Reproduces the failing condition: the zone database is loaded but
  // tz.local was never pointed at the device zone.
  setUp(() => tz.setLocalLocation(tz.UTC));

  group('localWallClock', () {
    test('converts even when tz.local is UTC — the isolate case', () {
      // Exactly the event in the device calendar for the real Viya booking.
      final stored = tz.TZDateTime.utc(2026, 8, 30, 2, 30);
      expect(stored.millisecondsSinceEpoch, 1788057000000,
          reason: 'fixture drifted from the instant measured on the device');

      final wall = CalendarService.localWallClock(stored);

      // Independent oracle: what the OS says that instant is locally.
      final oracle =
          DateTime.fromMillisecondsSinceEpoch(stored.millisecondsSinceEpoch);
      expect(wall.hour, oracle.hour);
      expect(wall.minute, oracle.minute);
      expect(wall.day, oracle.day);
      expect(wall.month, oracle.month);

      // And the point of the whole exercise: on a UTC+4 machine this is
      // 06:30, and it must NOT be the 02:30 that toLocal() would have left.
      if (DateTime.now().timeZoneOffset == const Duration(hours: 4)) {
        expect(wall.hour, 6);
        expect(wall.minute, 30);
      }
    });

    test('is not fooled by a TZDateTime that merely claims a zone', () {
      // A TZDateTime carrying some zone that is not the device's — the
      // shape device_calendar hands back.
      final london = tz.getLocation('Europe/London');
      final stored = tz.TZDateTime(london, 2026, 8, 30, 2, 30);

      final wall = CalendarService.localWallClock(stored);
      final oracle =
          DateTime.fromMillisecondsSinceEpoch(stored.millisecondsSinceEpoch);

      expect(wall.hour, oracle.hour);
      expect(wall.day, oracle.day);
    });

    test('the date rolls with the time, not independently', () {
      // Late-evening local tee times cross the UTC date boundary. If the
      // date were taken from the raw fields and the time converted, the
      // round would land on the wrong day.
      final stored = tz.TZDateTime.utc(2026, 8, 30, 22, 30);
      final wall = CalendarService.localWallClock(stored);
      final oracle =
          DateTime.fromMillisecondsSinceEpoch(stored.millisecondsSinceEpoch);

      expect(wall.day, oracle.day);
      expect(wall.hour, oracle.hour);
    });

    test('drops sub-minute precision but keeps the minute', () {
      final stored = tz.TZDateTime.utc(2026, 8, 30, 2, 30, 45, 123);
      final wall = CalendarService.localWallClock(stored);
      expect(wall.second, 0);
      expect(wall.millisecond, 0);
      expect(
          wall.minute,
          DateTime.fromMillisecondsSinceEpoch(stored.millisecondsSinceEpoch)
              .minute);
    });
  });
}
