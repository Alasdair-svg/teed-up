// Nothing may touch the calendar permission API until the user has seen the
// Permissions step and tapped its button.
//
// The user reported four times that the OS permission dialogs appear BEFORE
// the screen explaining why they are needed. Reading the code did not find
// the cause. This asserts the invariant directly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/services/calendar_service.dart';
import 'package:all_teed_up/screens/onboarding_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CalendarService.permissionChecks = 0;
  });

  testWidgets('no calendar permission touched on Welcome, or after Get Started',
      (tester) async {
    // A tall surface: the onboarding column overflows on short ones, which
    // is a separate bug and would drown this assertion in noise.
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: AppState(),
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    // pump(), never pumpAndSettle(): the golf ball spins forever, so the
    // tree never settles and pumpAndSettle would simply time out.
    await tester.pump(const Duration(milliseconds: 100));

    expect(CalendarService.permissionChecks, 0,
        reason: 'Welcome must not touch the calendar API');

    await tester.tap(find.text('Get Started'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(CalendarService.permissionChecks, 0,
        reason: 'the Permissions EXPLANATION step must not request anything; '
            'the user has not tapped Grant Permissions yet');
    expect(find.text('Grant Permissions'), findsOneWidget);
  });
}
