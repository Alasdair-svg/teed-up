// Settings must not offer a control the app cannot honour — and must not
// hide one it IS acting on.
//
// This file previously asserted the opposite: that the Friends & Family card
// was hidden. That was written on the belief the feature was dead, because
// notifyFamily() sat behind a build flag that ships off.
//
// The belief was wrong. Only the round-detail button was flagged. The scan
// screen had been adding family members to every event created, unflagged,
// all along — and pre-ticking every one of them automatically. So hiding the
// card removed the user's ability to see or edit a list the app was still
// acting on, which is worse than the dead control it was meant to remove.
//
// The card is back, the list is visible, and nobody is pre-ticked unless the
// user asks. The inversion is kept here rather than deleted, because "we
// hid it, then found it was live" is the useful part.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/screens/settings_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a list the app acts on is visible to the user', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 3)); // purchase retry timer

    expect(find.text('Friends & Family'), findsOneWidget);
  });

  test('the pre-tick control now drives something', () {
    // "Always notify all members" was read by nothing but the row that drew
    // it, while every scan pre-ticked everyone regardless. It is now the
    // switch that decides, and it defaults to off.
    final state = AppState();
    expect(state.familyAlwaysNotify, isFalse);
    state.setFamilyAlwaysNotify(true);
    expect(state.familyAlwaysNotify, isTrue);
  });
}
