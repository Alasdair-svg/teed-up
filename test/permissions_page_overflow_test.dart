import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/screens/onboarding_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('permissions page does not overflow on a small phone', (t) async {
    // 320x568 is the smallest phone worth supporting. The page scrolls, but an
    // overflow means content is clipped rather than reachable.
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: AppState(),
      child: const MaterialApp(home: OnboardingScreen()),
    ));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('Get Started'));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Notification access:'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
