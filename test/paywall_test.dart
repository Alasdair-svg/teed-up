// The purchase screen has to say what it charges, and must not offer to sell
// to someone who already has access.
//
// Apple Guideline 3.1.2 requires price, billing period and renewal terms to
// be legible at the point of purchase. It is also the honest thing: an annual
// AED 99 charge that arrives unannounced is the top cause of refund requests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_teed_up/config/feature_flags.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/screens/settings_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester,
      {required bool purchased, required bool lifetime}) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LicenseAboutSection(
              isPurchased: purchased,
              hasLifetimeAccess: lifetime,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the badge tells each kind of user what they hold',
      (tester) async {
    await pump(tester, purchased: false, lifetime: true);
    expect(find.text('Lifetime'), findsOneWidget,
        reason: 'a tester who redeemed a code must see it landed');

    await pump(tester, purchased: false, lifetime: false);
    expect(find.text(kEnforceSubscription ? 'Not subscribed' : 'Beta'),
        findsOneWidget);
  });

  testWidgets('nothing is sold to someone who already has access',
      (tester) async {
    // The exact button label, not a substring: the badge itself reads
    // "Subscribed", which contains "Subscribe" and made an earlier version of
    // this test fail against correct code.
    const buyLabel = 'Subscribe — AED 99/year';

    await pump(tester, purchased: true, lifetime: false);
    expect(find.text(buyLabel), findsNothing,
        reason: 'a subscriber shown a Subscribe button assumes payment failed');

    await pump(tester, purchased: false, lifetime: true);
    expect(find.text(buyLabel), findsNothing,
        reason: 'a lifetime tester shown one assumes their code did not take');
  });

  testWidgets('when enforcement is on, terms are stated before purchase',
      (tester) async {
    if (!kEnforceSubscription) return; // gated build; asserted below instead
    await pump(tester, purchased: false, lifetime: false);
    expect(find.text('Subscribe — AED 99/year'), findsOneWidget);
    expect(find.text('AED 99 per year'), findsOneWidget);
    expect(find.textContaining('Renews automatically'), findsOneWidget);
    expect(find.textContaining('Cancel any time'), findsOneWidget);
    expect(find.textContaining('Redeem a code'), findsOneWidget);
    expect(find.textContaining('Restore purchases'), findsOneWidget);
  });

  testWidgets('the beta build sells nothing at all', (tester) async {
    if (kEnforceSubscription) return;
    await pump(tester, purchased: false, lifetime: false);
    expect(find.text('Subscribe — AED 99/year'), findsNothing,
        reason: 'testers have no codes yet; selling to them would be a trap');
    expect(find.textContaining('Restore purchases'), findsNothing,
        reason: 'a button whose only outcome is "no purchase found" is noise');
  });
}
