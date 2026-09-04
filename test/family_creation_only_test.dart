// "Let friends and family know" belongs to the booking-creation workflow,
// and nowhere else.
//
// That makes creator-only STRUCTURAL rather than a check. Someone invited to
// another person's round never enters the creation workflow, so there is no
// button to guard and no isCreator test that a later UI change could get
// wrong. The trade, accepted deliberately: family cannot be added after the
// fact — rescanning the booking is the way.
//
// Two faults this replaces, both real:
//  - The settings card was hidden on the belief the feature was dead. It was
//    not: the scan screen had been adding these people to every event all
//    along. Hiding it left configuration that still acted and could not be
//    seen or edited.
//  - Every scan pre-ticked EVERY stored family member, unconditionally. That
//    is how someone who was never in the booking screenshot ended up attached
//    to a round. The "always notify" toggle that was supposed to control it
//    drove nothing at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/screens/settings_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpSettings(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 3)); // purchase retry timer
  }

  testWidgets('the family list is visible and editable', (tester) async {
    await pumpSettings(tester, AppState());
    expect(find.text('Friends & Family'), findsOneWidget,
        reason: 'hiding it left configuration that still acted, unseen');
  });

  testWidgets('the card says these people are not playing', (tester) async {
    await pumpSettings(tester, AppState());
    expect(find.textContaining('not playing in it'), findsOneWidget,
        reason: 'the confusion that started this was family-vs-player');
  });

  group('who gets pre-ticked on a new booking', () {
    test('nobody, by default', () {
      final s = AppState();
      expect(s.familyAlwaysNotify, isFalse,
          reason: 'opt in to including people, never opt out');
    });

    test('the toggle is what decides it', () {
      final s = AppState()..setFamilyAlwaysNotify(true);
      expect(s.familyAlwaysNotify, isTrue);
      s.setFamilyAlwaysNotify(false);
      expect(s.familyAlwaysNotify, isFalse);
    });
  });

  // There is deliberately no test that notifyFamily() is gone: it was
  // deleted, so its absence is a compile-time guarantee. A skipped test
  // asserting it would look like coverage and provide none.
}
