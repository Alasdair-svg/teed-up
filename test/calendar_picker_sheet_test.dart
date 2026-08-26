// The picker is the only route to choosing a calendar that doesn't require
// abandoning a scanned booking, so its failure modes matter.
//
// It originally hid anything device_calendar flagged read-only. On the
// user's real phone that flag came back true for EVERY calendar, so the
// sheet was empty and the app told them their phone accepts no new events —
// which was false, and not a conclusion this app is entitled to draw.

import 'package:device_calendar/device_calendar.dart' show Calendar;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/widgets/calendar_picker_sheet.dart';

Calendar _cal(String id, String name,
    {bool readOnly = false, String? account}) {
  final c = Calendar(id: id, name: name, isReadOnly: readOnly);
  c.accountName = account;
  return c;
}

void main() {
  Future<void> pump(WidgetTester tester, List<Calendar> cals,
      {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CalendarPickerSheet(calendarsOverride: cals)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every calendar, likely-writable first', (tester) async {
    await pump(tester, [
      _cal('2', 'Holidays in UAE', readOnly: true),
      _cal('1', 'Work', account: 'me@work.com'),
      _cal('3', 'Birthdays', readOnly: true),
    ]);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Holidays in UAE'), findsOneWidget);
    expect(find.text('Birthdays'), findsOneWidget);
  });

  testWidgets('an all-read-only device still gets a usable list',
      (tester) async {
    await pump(tester, [
      _cal('1', 'Personal', readOnly: true),
      _cal('2', 'Work', readOnly: true),
    ]);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('never claims the phone accepts no events', (tester) async {
    await pump(tester, [_cal('1', 'Personal', readOnly: true)]);
    expect(find.textContaining('accept new events'), findsNothing);
  });

  testWidgets('many look-alike calendars render without overflow',
      (tester) async {
    await pump(
      tester,
      [for (var i = 0; i < 21; i++) _cal('id$i', 'Calendar')],
      size: const Size(320, 568),
    );
    expect(tester.takeException(), isNull);
    // Falls back to the id so otherwise identical rows can be told apart.
    // Only the first rows are checked: the list is lazy.
    expect(find.text('Calendar id0'), findsOneWidget);
  });

  testWidgets('choosing a calendar returns its id', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              picked = await showModalBottomSheet<String>(
                context: ctx,
                builder: (_) => CalendarPickerSheet(
                  calendarsOverride: [_cal('cal-9', 'Golf')],
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Golf'));
    await tester.pumpAndSettle();
    expect(picked, 'cal-9');
  });
}
