// A redeemed tester code must outlive everything a subscription does.
//
// Testers are promised free access for life. The mechanism is a store promo
// code issued against a NON-CONSUMABLE (kLifetimeProductId), not against the
// subscription — codes on a subscription only ever buy a free period, and a
// locally-stored code would not survive a new phone. A non-consumable is
// tied to the redeemer's store account, so Restore Purchases brings it back.
//
// The risk this file guards: the subscription path revoking access that was
// never a subscription. revalidateEntitlement() revokes on an inconclusive
// store answer, and that must never reach a lifetime grant.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_teed_up/providers/app_state.dart';
import 'package:all_teed_up/services/purchase_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('entitlement gate', () {
    test('a lifetime grant alone opens full access', () {
      final s = AppState();
      expect(s.hasFullAccess, isFalse);
      s.setLifetimeAccess(true);
      expect(s.hasFullAccess, isTrue);
      expect(s.isPurchased, isFalse,
          reason: 'a tester has not subscribed, and must not appear to have');
    });

    test('a subscription alone opens full access', () {
      final s = AppState()..setPurchased(true);
      expect(s.hasFullAccess, isTrue);
    });

    test('a lapsing subscription does not disturb the lifetime grant', () {
      final s = AppState()
        ..setLifetimeAccess(true)
        ..setPurchased(true);
      s.setPurchased(false); // what revalidateEntitlement does on revoke
      expect(s.hasLifetimeAccess, isTrue);
      expect(s.hasFullAccess, isTrue,
          reason: 'the tester was promised life, not a year');
    });

    test('notifies listeners so the badge repaints on redemption', () {
      final s = AppState();
      var notified = 0;
      s.addListener(() => notified++);
      s.setLifetimeAccess(true);
      expect(notified, 1);
      s.setLifetimeAccess(true); // no-op
      expect(notified, 1);
    });
  });

  group('product identity', () {
    test('lifetime is a different product from the subscription', () {
      // The app grants lifetime for this id ONLY. Sharing one id would hand
      // every paying subscriber a permanent free entitlement.
      expect(kLifetimeProductId, isNot(kProductId));
    });
  });

  group('tamper resistance', () {
    test('a hand-set flag with no token is rejected', () {
      // What flipping the boolean over adb on a rooted device looks like.
      expect(isLifetimeGrantValid(flag: true, token: null), isFalse);
    });

    test('a flag with the wrong token is rejected', () {
      expect(isLifetimeGrantValid(flag: true, token: 'deadbeef'), isFalse);
    });

    test('a genuine grant is accepted', () {
      expect(
        isLifetimeGrantValid(flag: true, token: computeLifetimeToken()),
        isTrue,
      );
    });

    test('no token rotation — the grant must not lapse on 1 January', () {
      // The purchase token deliberately embeds the year to force an annual
      // re-verify. A lifetime grant must not, or every tester silently loses
      // access at new year with no way to notice.
      expect(computeLifetimeToken(), isNot(contains(DateTime.now().year.toString())));
      expect(computeLifetimeToken(), computeLifetimeToken());
    });
  });
}
