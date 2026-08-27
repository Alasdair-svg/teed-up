// Onboarding must actually advance when the user taps through it.
//
// Regression test for a bug reported four times as the app "sticking half
// way between the front page and the grant permissions page". Tapping Get
// Started updated the button and the step indicator but left the Welcome
// page on screen: widgets inserted conditionally above the PageView shifted
// its slot in the Column, so reconciliation rebuilt the PageView and reset
// its scroll position to page 0 while _currentPage stayed 1.
//
// It also explains the second complaint — that OS permission dialogs
// appeared BEFORE the screen explaining why they were needed. With the page
// stuck, the user's next tap was "Grant Permissions", which requests
// permissions and only then advances the page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/screens/onboarding_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpFrames(WidgetTester t, [int n = 20]) async {
    // pump(), never pumpAndSettle(): the golf ball spins forever, so the
    // tree never settles and pumpAndSettle would time out.
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Get Started shows the Permissions page, not just its button',
      (t) async {
    t.view.physicalSize = const Size(402, 874);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: AppState(),
      child: const MaterialApp(home: OnboardingScreen()),
    ));
    await t.pump(const Duration(milliseconds: 50));

    expect(find.text('Get Started'), findsOneWidget);
    await t.tap(find.text('Get Started'));
    await pumpFrames(t);

    // The page content is what matters. Asserting only on the button would
    // have passed throughout the entire bug.
    expect(find.text('A few things needed to get going:'), findsOneWidget);
    expect(find.text('Grant Permissions'), findsOneWidget);
  });

  testWidgets('advances past Permissions even when a platform call fails',
      (t) async {
    // The 1.6.0 regression: an await was added between the permission
    // request and _next(), inside a try/finally with NO catch. On a device
    // where that call threw, _next() never ran and onboarding stopped dead
    // with no error — reported as the screen freezing again.
    //
    // In the test environment every plugin channel is absent, so these calls
    // fail exactly as they would on a hostile device. Reaching the calendar
    // step therefore proves navigation cannot be blocked by a failing
    // permission call.
    t.view.physicalSize = const Size(402, 874);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: AppState(),
      child: const MaterialApp(home: OnboardingScreen()),
    ));
    await t.pump(const Duration(milliseconds: 50));

    await t.tap(find.text('Get Started'));
    await pumpFrames(t);
    expect(find.text('A few things needed to get going:'), findsOneWidget);

    await t.tap(find.text('Grant Permissions'));
    // Advance past the permission timeout. In the test environment the
    // plugin channel is absent and the request Future NEVER completes and
    // never throws — the same shape as the real-device hang — so only the
    // timeout can free the flow.
    await t.pump(kPermissionRequestTimeout + const Duration(seconds: 1));
    await t.pump(kCapabilityTimeout + const Duration(seconds: 1));
    await pumpFrames(t, 40);

    expect(find.text('Where should tee times land?'), findsOneWidget,
        reason: 'a failing permission call must never trap the user');
  });
}
