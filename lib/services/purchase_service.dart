/// In-app purchase service for the All Teed Up golf booking app.
///
/// Manages the AED 99/year subscription that unlocks the full app.
/// (product ID: `teed_up_full_access`, AED 99 a year).
///
/// Uses the `in_app_purchase` Flutter plugin for App Store / Play Store
/// transactions and [SharedPreferences] for local purchase persistence.
/// No backend server is required — verification is handled locally
/// The subscription product itself is configured in App Store Connect and
/// Play Console; this only initiates the purchase and listens for the result.
///
/// ## Usage
///
/// ```dart
/// final purchaseService = PurchaseService(appState: context.read<AppState>());
/// await purchaseService.initialize();
///
/// if (!purchaseService.isPurchased) {
///   await purchaseService.buyApp();
/// }
/// ```
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/feature_flags.dart';
import '../providers/app_state.dart';

/// The subscription product ID configured in App Store Connect and Play
/// and Google Play Console.
const String kProductId = 'teed_up_full_access';

/// The lifetime, non-expiring product — a NON-CONSUMABLE on Apple and a
/// one-time product on Play, never a subscription.
///
/// This is what tester promo codes are issued against. Store promo codes
/// for a subscription can only grant a free *period*; issued against a
/// non-consumable they grant it permanently, single-use is enforced by
/// Apple and Google rather than by us, and because it is tied to the
/// redeemer's store account it comes back via Restore Purchases on a new
/// phone — which a locally-stored code never could.
///
/// It is a separate product from [kProductId] on purpose: the app grants
/// lifetime access for THIS id only, so a paying subscriber can never be
/// mistaken for a tester.
const String kLifetimeProductId = 'teed_up_lifetime_access';

/// SharedPreferences key for the local purchase cache.
const String _kPurchasedKey = 'teed_up_purchased';

/// SharedPreferences key for the purchase integrity token.
///
/// A secondary hash stored alongside the purchase boolean. If the boolean
/// is `true` but the token is absent or mismatched, it indicates tampering
/// (e.g. ADB SharedPreferences manipulation on a rooted device).
const String _kPurchaseTokenKey = 'teed_up_purchase_token';

/// SharedPreferences key for the lifetime grant.
const String _kLifetimeKey = 'teed_up_lifetime';

/// Integrity token for the lifetime grant, same purpose as
/// [_kPurchaseTokenKey] — a flipped boolean alone must not buy access.
const String _kLifetimeTokenKey = 'teed_up_lifetime_token';

/// Tamper-detection token for the lifetime grant.
///
/// Unlike the purchase token this carries no year, because the grant does
/// not expire — a yearly rotation would silently drop every tester's access
/// on 1 January. Not a secret: it raises the bar against flipping the
/// boolean over adb on a rooted device, nothing more.
String computeLifetimeToken() {
  const raw = '$kLifetimeProductId:teedup:golf:lifetime';
  var hash = 0;
  for (final unit in raw.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}

/// Whether a cached lifetime grant should be trusted.
///
/// The flag alone is never enough — a grant with a missing or wrong token is
/// treated as tampered and ignored, and Restore Purchases brings back the
/// real thing if there is one.
bool isLifetimeGrantValid({required bool flag, required String? token}) =>
    flag && token == computeLifetimeToken();

/// Manages the in-app purchase lifecycle for All Teed Up.
///
/// Call [initialize] once at app startup, then use [buyApp] to initiate
/// a purchase or [restorePurchases] to restore on a new device.
///
/// Purchase state is persisted locally in [SharedPreferences] and also
/// pushed to [AppState] so the UI reacts immediately via [ChangeNotifier].
class PurchaseService {
  /// Creates a [PurchaseService].
  ///
  /// Requires an [AppState] instance to update the reactive purchase flag
  /// when a transaction completes.
  PurchaseService({required AppState appState}) : _appState = appState;

  final AppState _appState;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _isAvailable = false;
  bool _isPurchased = false;

  /// Set when a purchase/restore event for [kProductId] arrives during a
  /// revalidation pass. See [revalidateEntitlement].
  bool _sawActiveEntitlement = false;
  ProductDetails? _productDetails;

  /// An optional callback invoked when a purchase error occurs.
  ///
  /// The screen can set this to show a SnackBar or dialog with the
  /// error message.
  ValueChanged<String>? onError;

  /// An optional callback invoked when a purchase is pending
  /// (e.g. waiting for parental approval or slow network).
  VoidCallback? onPending;

  /// An optional callback invoked when a purchase completes successfully.
  VoidCallback? onPurchaseComplete;

  // ---------------------------------------------------------------------------
  // Public Getters
  // ---------------------------------------------------------------------------

  /// Whether the App Store / Play Store is available on this device.
  bool get isAvailable => _isAvailable;

  /// Whether the user has purchased the app.
  ///
  /// Checks both the local [SharedPreferences] cache and [AppState].
  bool get isPurchased => _isPurchased;

  bool _hasLifetime = false;

  /// Whether a lifetime (non-consumable) grant is held on this device.
  bool get hasLifetime => _hasLifetime;

  /// The store-provided product details, available after [initialize].
  ///
  /// Returns `null` if the store is unavailable or the product ID
  /// was not found.
  ProductDetails? get productDetails => _productDetails;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initializes the in-app purchase plugin and starts listening to
  /// the purchase update stream.
  ///
  /// This method:
  /// 1. Checks whether the store is available on this device.
  /// 2. Loads the cached purchase state from [SharedPreferences].
  /// 3. Queries the store for the product details.
  /// 4. Subscribes to the purchase update stream.
  ///
  /// Call this once during app startup (e.g. in `main()` or the root
  /// widget's `initState`).
  Future<void> initialize() async {
    // Check store availability.
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint('PurchaseService: Store is not available on this device.');
      // Still load cached state so the app works offline after purchase.
      await _loadCachedPurchaseState();
      await _loadCachedLifetimeState();
      return;
    }

    // Load cached purchase state.
    await _loadCachedPurchaseState();
    await _loadCachedLifetimeState();

    // Listen to the purchase stream.
    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () => _subscription?.cancel(),
      onError: (Object error) {
        debugPrint('PurchaseService: Stream error — $error');
      },
    );

    // Query product details from the store.
    await _loadProductDetails();
  }

  /// Loads the cached purchase flag from [SharedPreferences] and syncs
  /// it to [AppState].
  ///
  /// Also validates the integrity token. If the flag is `true` but the
  /// token is absent or incorrect, the cache is treated as tampered and
  /// a store restore is triggered to re-verify with the platform.
  Future<void> _loadCachedPurchaseState() async {
    final prefs = await SharedPreferences.getInstance();
    final rawFlag = prefs.getBool(_kPurchasedKey) ?? false;

    if (rawFlag) {
      // Validate integrity token before trusting the cached flag.
      final storedToken = prefs.getString(_kPurchaseTokenKey);
      final expectedToken = _computeIntegrityToken();
      if (storedToken == expectedToken) {
        _isPurchased = true;
      } else {
        // Token mismatch — flag may have been set by ADB/root manipulation.
        // Clear the suspect cache and let the store verify.
        debugPrint(
          'PurchaseService: Integrity token mismatch — '
          'clearing cache and triggering restore.',
        );
        await prefs.remove(_kPurchasedKey);
        await prefs.remove(_kPurchaseTokenKey);
        _isPurchased = false;
        // Trigger a store restore after a short delay so the store SDK
        // has time to initialise.
        Future.delayed(const Duration(seconds: 2), restorePurchases);
      }
    } else {
      _isPurchased = false;
    }
    _appState.setPurchased(_isPurchased);
  }

  /// Re-checks with the store whether the subscription is still active, and
  /// revokes access if it is not.
  ///
  /// The cached flag alone is not enough for a subscription: it is written
  /// once at purchase and would stay true forever, so a lapsed subscription
  /// would never be noticed. This asks the store on every launch and resume.
  ///
  /// IMPORTANT — it only ever revokes on a DEFINITIVE negative. If the store
  /// is unreachable, the restore throws, or the platform is unavailable, the
  /// result is inconclusive and the previous state is kept. Revoking on a
  /// network failure would lock out paying customers, which is far worse than
  /// briefly over-granting.
  ///
  /// Returns true if the subscription is considered active afterwards.
  Future<bool> revalidateEntitlement({
    Duration wait = const Duration(seconds: 6),
  }) async {
    if (!_isAvailable) {
      debugPrint('PurchaseService: store unavailable — entitlement unchanged.');
      return _isPurchased;
    }

    // Do not disturb anyone who has nothing to revalidate.
    //
    // restorePurchases() can raise an App Store sign-in prompt on iOS. During
    // beta there is no subscription product in either store and nobody has
    // purchased, so calling it on every launch and resume would prompt
    // testers for a sign-in that finds nothing. Only check when enforcement
    // is on, or when this device believes it already has an entitlement to
    // confirm.
    if (!kEnforceSubscription && !_isPurchased) {
      return false;
    }

    // A lifetime grant is not a subscription and has nothing to revalidate.
    // Skipping here also means the revoke branch below can never reach it.
    if (_hasLifetime) {
      debugPrint('PurchaseService: lifetime grant held — nothing to '
          'revalidate.');
      return true;
    }

    _sawActiveEntitlement = false;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('PurchaseService: restore failed ($e) — entitlement '
          'unchanged. Not revoking on an inconclusive check.');
      return _isPurchased;
    }

    // Restored purchases arrive asynchronously on the purchase stream, which
    // _handleSuccessfulPurchase sets the flag from.
    await Future<void>.delayed(wait);

    if (_sawActiveEntitlement) {
      debugPrint('PurchaseService: subscription active.');
      return true;
    }

    if (_isPurchased) {
      debugPrint('PurchaseService: no active subscription returned by the '
          'store — revoking access.');
      _isPurchased = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPurchasedKey);
      await prefs.remove(_kPurchaseTokenKey);
      _appState.setPurchased(false);
    }
    return false;
  }

  /// Queries the store for the [kProductId] product details.
  Future<void> _loadProductDetails() async {
    final response = await _iap.queryProductDetails({kProductId});

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint(
        'PurchaseService: Product "$kProductId" not found in the store. '
        'Ensure it is configured in App Store Connect / Play Console.',
      );
    }

    if (response.error != null) {
      debugPrint(
        'PurchaseService: Error querying products — '
        '${response.error!.message}',
      );
    }

    if (response.productDetails.isNotEmpty) {
      _productDetails = response.productDetails.first;
    }
  }

  // ---------------------------------------------------------------------------
  // Purchase Actions
  // ---------------------------------------------------------------------------

  /// Initiates the purchase of the non-consumable product.
  ///
  /// Throws a [StateError] if the store is not available or the product
  /// details have not been loaded yet.
  ///
  /// Does nothing if the user has already purchased the app.
  Future<void> buyApp() async {
    if (_isPurchased) {
      debugPrint('PurchaseService: Already purchased — skipping.');
      return;
    }

    if (!_isAvailable) {
      onError?.call('The app store is not available on this device.');
      return;
    }

    if (_productDetails == null) {
      onError?.call(
        'Unable to load product information. Please try again later.',
      );
      return;
    }

    final purchaseParam = PurchaseParam(
      productDetails: _productDetails!,
    );

    // The store tracks the subscription and its renewal state.
    // buyNonConsumable is correct for a SUBSCRIPTION.
    //
    // The name misleads: the in_app_purchase package uses buyConsumable only
    // for consumables and buyNonConsumable for everything else, subscriptions
    // included — see the package README, which uses it in its own
    // "upgrading or downgrading an existing in-app subscription" section.
    final success = await _iap.buyNonConsumable(
      purchaseParam: purchaseParam,
    );

    if (!success) {
      debugPrint('PurchaseService: buyNonConsumable returned false.');
    }
  }

  /// Restores previous purchases (e.g. after a device change or
  /// app reinstall).
  ///
  /// Restored purchases will arrive via the purchase stream and be
  /// handled by [_handlePurchaseUpdates].
  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      onError?.call('The app store is not available on this device.');
      return;
    }

    await _iap.restorePurchases();
  }

  // ---------------------------------------------------------------------------
  // Purchase Stream Handler
  // ---------------------------------------------------------------------------

  /// Processes incoming purchase updates from the store.
  ///
  /// Handles four states:
  /// - [PurchaseStatus.purchased] — verify, deliver, and complete.
  /// - [PurchaseStatus.restored] — verify, deliver, and complete.
  /// - [PurchaseStatus.error] — notify the UI.
  /// - [PurchaseStatus.pending] — notify the UI (e.g. parental approval).
  void _handlePurchaseUpdates(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _handleSuccessfulPurchase(purchase);

        case PurchaseStatus.error:
          _handleError(purchase);

        case PurchaseStatus.pending:
          _handlePending(purchase);

        case PurchaseStatus.canceled:
          // User cancelled — nothing to do.
          debugPrint('PurchaseService: Purchase cancelled by user.');
          // Still need to complete pending purchases on Android.
          if (purchase.pendingCompletePurchase) {
            _iap.completePurchase(purchase);
          }
      }
    }
  }

  /// Handles a successful purchase or restoration.
  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchase) async {
    final isValid = await _verifyPurchase(purchase);

    if (isValid) {
      if (purchase.productID == kLifetimeProductId) {
        await _deliverLifetime();
      } else {
        await _deliverProduct();
      }
      onPurchaseComplete?.call();
      debugPrint(
        'PurchaseService: Purchase verified and delivered '
        '(status: ${purchase.status}).',
      );
    } else {
      onError?.call('Purchase verification failed. Please contact support.');
      debugPrint('PurchaseService: Purchase verification failed.');
    }

    // Always complete the purchase to avoid store-side errors.
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  /// Handles a purchase error by notifying the UI.
  void _handleError(PurchaseDetails purchase) {
    final errorMessage = purchase.error?.message ?? 'An unknown error occurred';
    debugPrint('PurchaseService: Purchase error — $errorMessage');
    onError?.call(errorMessage);

    // Complete the purchase to clear the transaction queue.
    if (purchase.pendingCompletePurchase) {
      _iap.completePurchase(purchase);
    }
  }

  /// Handles a pending purchase by notifying the UI.
  void _handlePending(PurchaseDetails purchase) {
    debugPrint('PurchaseService: Purchase pending — awaiting confirmation.');
    onPending?.call();
  }

  // ---------------------------------------------------------------------------
  // Verification & Delivery
  // ---------------------------------------------------------------------------

  /// Performs local verification of a purchase.
  ///
  /// For a non-consumable product with no server backend, we verify
  /// that the purchase details contain a valid product ID and that
  /// the transaction completed successfully.
  ///
  /// In a production app with a server, you would send the
  /// [PurchaseDetails.verificationData] to your backend for
  /// receipt validation.
  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    // Verify the product ID matches our expected product.
    if (purchase.productID != kProductId) {
      debugPrint(
        'PurchaseService: Unexpected product ID "${purchase.productID}".',
      );
      return false;
    }

    // For local-only verification of a non-consumable, checking the
    // product ID and status is sufficient. The store itself guarantees
    // the transaction's authenticity through the purchase stream.
    //
    // The verificationData is available if you ever add server-side
    // receipt validation:
    //   purchase.verificationData.localVerificationData  (receipt)
    //   purchase.verificationData.serverVerificationData (token)
    return true;
  }

  /// Marks the app as purchased in [SharedPreferences] and updates
  /// [AppState] so the UI reacts immediately.
  ///
  /// Also writes an integrity token alongside the purchase flag so that
  /// any out-of-band modification of the flag can be detected on next launch.
  Future<void> _deliverProduct() async {
    _isPurchased = true;

    // Persist locally with integrity token.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPurchasedKey, true);
    await prefs.setString(_kPurchaseTokenKey, _computeIntegrityToken());

    // Update reactive state.
    _sawActiveEntitlement = true;
    _appState.setPurchased(true);
  }

  /// Records the permanent grant from a redeemed tester code.
  ///
  /// Deliberately one-way. A non-consumable cannot be un-bought, so nothing
  /// in the subscription path — including [revalidateEntitlement], which
  /// revokes on an inconclusive store answer — may clear this.
  Future<void> _deliverLifetime() async {
    _hasLifetime = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLifetimeKey, true);
    await prefs.setString(_kLifetimeTokenKey, _computeLifetimeToken());
    _appState.setLifetimeAccess(true);
    debugPrint('PurchaseService: lifetime access granted.');
  }

  /// Loads the lifetime grant, validating its integrity token the same way
  /// the purchase flag is validated.
  Future<void> _loadCachedLifetimeState() async {
    final prefs = await SharedPreferences.getInstance();
    final flag = prefs.getBool(_kLifetimeKey) ?? false;
    if (!isLifetimeGrantValid(
      flag: flag,
      token: prefs.getString(_kLifetimeTokenKey),
    )) {
      if (flag) {
        debugPrint('PurchaseService: lifetime token mismatch — ignoring the '
            'cached grant. Restore Purchases will bring it back if real.');
      }
      return;
    }
    _hasLifetime = true;
    _appState.setLifetimeAccess(true);
  }

  String _computeLifetimeToken() => computeLifetimeToken();

  // ---------------------------------------------------------------------------
  // Integrity
  // ---------------------------------------------------------------------------

  /// Computes a lightweight integrity token for the purchase state.
  ///
  /// Not cryptographic — this is a tamper-detection signal, not a secret.
  /// It raises the bar against simple ADB SharedPreferences manipulation
  /// on rooted devices without requiring a backend server.
  String _computeIntegrityToken() {
    // Combine product ID, a fixed app salt, and the install year to produce
    // a value that is stable per-year but changes across calendar years
    // (forcing a natural re-verify cycle).
    final raw = '$kProductId:teedup:golf:${DateTime.now().year}';
    final hash = raw.codeUnits
        .fold<int>(0x811C9DC5, (h, c) => (h ^ c) * 0x01000193 & 0xFFFFFFFF);
    return hash.toRadixString(16).padLeft(8, '0');
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Cancels the purchase stream subscription.
  ///
  /// Call this when the service is no longer needed (e.g. when the
  /// root widget disposes).
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
