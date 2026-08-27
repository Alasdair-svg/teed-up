// A tee time must reach the calendar at the time the booking said.
//
// The app read a 06:30 booking correctly and then wrote an invite for
// 10:30 — a four-hour shift, exactly Dubai's UTC+4 offset. Cause:
// initializeTimeZones() and setLocalLocation() were never called, so the
// timezone package's `local` was UTC. TZDateTime(local, ..., 6, 30) built
// 06:30 UTC, which is 10:30 in Dubai.

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('an uninitialised local zone is UTC — the bug', () {
    // Documents the failure: with `local` left at UTC, a 06:30 wall-clock
    // tee time is 06:30Z, which Dubai displays as 10:30.
    final utc = tz.getLocation('UTC');
    final built = tz.TZDateTime(utc, 2026, 9, 3, 6, 30);
    final asSeenInDubai =
        tz.TZDateTime.from(built, tz.getLocation('Asia/Dubai'));
    expect(asSeenInDubai.hour, 10);
  });

  test('with the device zone set, 06:30 stays 06:30', () {
    tz.setLocalLocation(tz.getLocation('Asia/Dubai'));
    final built = tz.TZDateTime(tz.local, 2026, 9, 3, 6, 30);

    expect(built.hour, 6);
    expect(built.minute, 30);
    // And it is genuinely 02:30Z — i.e. it carries the right instant, not
    // just the right wall-clock digits.
    expect(built.toUtc().hour, 2);
  });

  test('a zone with a half-hour offset also survives', () {
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    final built = tz.TZDateTime(tz.local, 2026, 9, 3, 6, 30);
    expect(built.hour, 6);
    expect(built.minute, 30);
    expect(built.toUtc().hour, 1);
    expect(built.toUtc().minute, 0);
  });
}
