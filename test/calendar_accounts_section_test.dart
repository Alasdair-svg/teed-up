// The calendar chooser must always make the current choice, and how to
// change it, unmistakable.
//
// The previous UI grouped every device calendar under an account heading
// with per-row switches and a "Set as primary" pill. With many calendars
// under one "Other" heading, users tapped the HEADING — a plain label — and
// nothing happened. Reported three times as "you cannot select a calendar".

import 'package:device_calendar/device_calendar.dart' show Calendar;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/widgets/calendar_accounts_section.dart';

Calendar _cal(String id, String name, {bool readOnly = false}) =>
    Calendar(id: id, name: name, isReadOnly: readOnly);

void main() {
  Future<AppState> pump(
      WidgetTester tester, Map<String, List<Calendar>> grouped) async {
    final state = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CalendarAccountsSection(groupedOverride: grouped),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('auto-selects a writable calendar and names it on screen',
      (tester) async {
    final state = await pump(tester, {
      'Other': [_cal('r1', 'Holidays', readOnly: true), _cal('w1', 'Work')],
    });
    await tester.pumpAndSettle();
    expect(state.selectedCalendarId, 'w1',
        reason: 'must never leave the user with no write target');
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Tee times land in'), findsOneWidget);
  });

  testWidgets('offers Change, not a heading that does nothing', (tester) async {
    await pump(tester, {
      'Other': [_cal('w1', 'Work'), _cal('w2', 'Golf')],
    });
    await tester.pumpAndSettle();
    expect(find.text('Change'), findsOneWidget);
    // The old account heading is gone: it looked tappable and was not.
    expect(find.text('Other'), findsNothing);
  });

  testWidgets('still chooses a calendar when all report read-only',
      (tester) async {
    final state = await pump(tester, {
      'Other': [
        _cal('r1', 'Personal', readOnly: true),
        _cal('r2', 'Work', readOnly: true),
      ],
    });
    await tester.pumpAndSettle();
    // A device reporting zero writable calendars is not credible. Refusing
    // to choose left the user with no target AND an accusation about their
    // phone. Choose anyway; a real write failure reports itself honestly.
    expect(state.selectedCalendarId, 'r1');
    expect(find.textContaining('accept new events'), findsNothing);
  });

  _emptyStateTests();
}

// Regression: an empty first fetch must never be permanent.
//
// The list used to be held in a `late final` Future. If the first fetch ran
// before calendar permission existed — which it did, because PageView built
// the calendar step while the user was still on the Welcome screen — the
// empty result was cached for the widget's lifetime and the step read
// "No calendars found on this device" no matter what happened afterwards.
void _emptyStateTests() {
  testWidgets('an empty calendar list offers a retry, not a dead end',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: AppState(),
        child: const MaterialApp(
          home: Scaffold(
            body: CalendarAccountsSection(groupedOverride: {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining("Couldn't read your calendars"), findsOneWidget);
  });
}
