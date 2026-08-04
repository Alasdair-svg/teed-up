// Basic smoke test for the Teed Up app.

import 'package:flutter_test/flutter_test.dart';

import 'package:teed_up/main.dart';
import 'package:teed_up/providers/app_state.dart';

void main() {
  testWidgets('App shows onboarding welcome screen on first launch',
      (WidgetTester tester) async {
    final appState = AppState();
    await tester.pumpWidget(TeedUpApp(appState: appState));
    // Avoid pumpAndSettle: the welcome screen's golf-ball logo animates
    // continuously (AnimationController.repeat()), so it never "settles".
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('All Teed Up'), findsWidgets);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
