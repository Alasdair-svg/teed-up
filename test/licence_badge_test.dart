// The licence badge said "Free".
//
// That was accurate about `isPurchased` and wrong about the product: it told
// a tester the app IS free, when the truth was that the AED 99/year
// subscription does not exist in either store yet, so nobody could have
// bought one. Alongside it sat a "Restore purchases" button whose only
// possible outcome was "no purchase found".
//
// Apple requires a restore mechanism for a subscription app (Guideline
// 3.1.1), so the button ships — but only once there is something to restore.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:all_teed_up/config/feature_flags.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/screens/settings_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, {bool isPurchased = false}) async {
    final state = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LicenseAboutSection(isPurchased: isPurchased),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('during beta the badge says Beta, never Free', (tester) async {
    // Guard: this file describes the beta build. If enforcement is compiled
    // in, the expectations below are the wrong ones to assert.
    expect(kEnforceSubscription, isFalse,
        reason: 'built with ENFORCE_SUBSCRIPTION — run without it');

    await pump(tester);

    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Free'), findsNothing,
        reason: '"Free" tells a tester the app is free. It is not — the '
            'subscription simply does not exist yet.');
    expect(find.text('Purchased'), findsNothing);
  });

  testWidgets('no Restore purchases button while there is nothing to restore',
      (tester) async {
    await pump(tester);

    expect(find.text('Restore purchases'), findsNothing,
        reason: 'With no product in either store this button can only ever '
            'report "no purchase found".');
  });
}
