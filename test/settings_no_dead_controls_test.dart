// Settings must not offer a control the build cannot honour.
//
// "Always notify all members" sat in the Friends & Family card and did
// nothing at all: familyAlwaysNotify was read nowhere but the row that drew
// it, and notifyFamily() returns immediately behind
// kEnableFamilyCalendarInvite, which is off in every shipped build. The
// label made it worse — nothing on screen said "members" meant family
// rather than playing partners, so it read as a control over who gets the
// invite. The whole card is hidden while the flag is off.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_teed_up/config/feature_flags.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/screens/settings_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the inert Friends & Family card is not shown', (tester) async {
    // Guard the guard: if the flag is ever switched on for a personal
    // build, this test is asserting nothing and should say so.
    expect(
      kEnableFamilyCalendarInvite,
      isFalse,
      reason: 'shipped builds leave family calendar invites off',
    );

    // Wide surface: widget tests have no real font metrics, so the card
    // header Row reports a false overflow at phone widths. Verified as a
    // test artifact, not a layout bug.
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    // pump past PurchaseService's one-shot 2s restore retry, which fires
    // in tests because no store is reachable. pumpAndSettle never returns
    // here, and leaving the timer pending fails the test on teardown.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Always notify all members'), findsNothing);
    expect(find.text('Friends & Family'), findsNothing);
  });
}
