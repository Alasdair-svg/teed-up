// Renders the conflict alert at real device sizes.
//
// A dialog that lays out fine on a large phone and overflows on a small one
// is exactly the kind of defect that ships unnoticed — nothing crashes, it
// just looks broken on someone else's handset. `takeException` catches the
// RenderFlex overflow that Flutter reports in that case.

import 'package:device_calendar/device_calendar.dart'
    show Event, TZDateTime, local;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/widgets/calendar_conflict_dialog.dart';

Event _event(String title, DateTime start) {
  final e = Event('cal-1');
  e.title = title;
  e.start = TZDateTime.from(start, local);
  return e;
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  final base = DateTime(2026, 8, 30, 7, 40);

  Future<void> pumpAt(
      WidgetTester tester, Size size, List<Event> conflicts) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CalendarConflictDialog(conflicts: conflicts)),
    ));
    await tester.pump();
  }

  testWidgets('renders one conflict without overflow on a small phone',
      (tester) async {
    await pumpAt(tester, const Size(320, 568), [
      _event('⛳ Emirates Golf Club', base),
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('Potential calendar conflict'), findsOneWidget);
    expect(find.text('Add anyway'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('renders many conflicts without overflow on a small phone',
      (tester) async {
    await pumpAt(tester, const Size(320, 568), [
      for (var i = 0; i < 6; i++)
        _event('Existing booking number $i with a deliberately long title',
            base.add(Duration(minutes: i * 5))),
    ]);
    expect(tester.takeException(), isNull);
    // Caps the list and says how many were hidden rather than growing forever.
    expect(find.textContaining('more'), findsOneWidget);
  });

  testWidgets('renders on a large phone without overflow', (tester) async {
    await pumpAt(tester, const Size(430, 932), [
      _event('⛳ Emirates Golf Club', base),
      _event('Untitled', base.add(const Duration(minutes: 20))),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an event with no title still renders a label', (tester) async {
    final e = Event('cal-1')..start = TZDateTime.from(base, local);
    await pumpAt(tester, const Size(390, 844), [e]);
    expect(tester.takeException(), isNull);
    expect(find.text('Untitled event'), findsOneWidget);
  });
}
