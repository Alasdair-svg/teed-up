// Runs on a REAL Android handset, in a RELEASE build, in Firebase Test Lab.
//
// This exists because the two worst bugs this app has had were both invisible
// to every test that can run on a developer machine:
//
//   1. R8 obfuscated device_calendar's Gson-marshalled model field names, so
//      the calendar list came back empty — release builds only.
//   2. The tee time was written four hours out, because the event was built
//      from a wall clock without a timezone.
//
// Neither reproduces in debug, on a simulator, or in a widget test. This test
// drives the real plugin against the real CalendarProvider and reads the event
// back, so both classes of failure surface without anyone holding a phone.
//
// It deliberately does NOT touch the UI: the photo picker is system UI that
// integration_test cannot drive. Player parsing is covered by the host suite
// (booking_parser_viya_test.dart) and is shared Dart, so it cannot differ
// between platforms. What is Android-specific is exactly what is below.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:all_teed_up/models/golf_round.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/services/calendar_service.dart';
import 'package:all_teed_up/services/timezone_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late CalendarService service;

  setUpAll(() async {
    await TimezoneService.configure();
    await Permission.calendarFullAccess.request();
    service = CalendarService();
  });

  testWidgets('calendars survive R8 with their field names intact',
      (tester) async {
    final calendars = await service.getAvailableCalendars();

    // The R8 symptom was an EMPTY list, not an exception.
    expect(calendars, isNotEmpty,
        reason: 'No calendars came back. On a release build this is the '
            'signature of R8 stripping device_calendar model field names — '
            'check proguard-rules.pro before suspecting permissions.');

    // Gson populates these by name. If R8 renamed them they arrive null even
    // though the object itself exists, which is the failure that shipped.
    final writable = calendars.where((c) => c.isReadOnly != true).toList();
    expect(writable, isNotEmpty, reason: 'No writable calendar on the device.');
    for (final c in calendars) {
      expect(c.id, isNotNull, reason: 'Calendar.id was null — field renamed.');
      expect(c.name, isNotNull,
          reason: 'Calendar.name was null — field renamed.');
    }
  });

  testWidgets('a 06:30 tee time is written as 06:30, not shifted',
      (tester) async {
    final calendars = await service.getAvailableCalendars();
    final target = calendars.firstWhere((c) => c.isReadOnly != true);

    // The exact booking that was written four hours late on a real handset.
    final date = DateTime(2026, 8, 30);
    final round = GolfRound(
      id: 'itest_${DateTime.now().millisecondsSinceEpoch}',
      courseName: 'Integration Test Course',
      date: date,
      teeTime: DateTime(2026, 8, 30, 6, 30),
      players: const [
        Player(id: 'p1', name: 'Alasdair Kilgour'),
        Player(id: 'p2', name: 'Marc McStay'),
      ],
    );

    final eventId = await service.createGolfEvent(round, target.id!);
    expect(eventId, isNotNull,
        reason: 'createGolfEvent returned null — it read the event back and '
            'could not confirm it exists.');

    // Read it back off the device rather than trusting the write.
    // findExistingEvent takes the same strings the scan path produces.
    final readBack = await service.findExistingEvent(
      round.courseName,
      '2026-08-30',
      '06:30',
      target.id!,
    );
    expect(readBack, isNotNull,
        reason: 'Event was reported written but cannot be found.');

    expect(readBack!.teeTime.hour, 6,
        reason: 'Tee time hour shifted — the timezone regression is back. '
            'Expected 06:30 local, got '
            '${readBack.teeTime.hour}:${readBack.teeTime.minute}.');
    expect(readBack.teeTime.minute, 30);
    expect(readBack.date.day, 30);
    expect(readBack.date.month, 8);
  });
}
