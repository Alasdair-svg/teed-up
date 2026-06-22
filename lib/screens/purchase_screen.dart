/// Premium purchase / paywall screen for the Teed Up golf booking app.
///
/// Displays the feature list, pricing (AED 99 one-time), and purchase
/// / restore buttons using TAG branding. Shown before the user can
/// access the full app.
///
/// ## Navigation
///
/// Push this screen when `AppState.isPurchased` is `false`:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => const PurchaseScreen(),
/// ));
/// ```
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/purchase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/golf_ball_logo.dart';

/// The paywall screen presented to unpaid users.
///
/// Shows the app's key features, a one-time price tag, and buttons to
/// purchase or restore a previous purchase. Fully TAG-branded with
/// white background, purple accents, and Outfit / Inter typography.
class PurchaseScreen extends StatefulWidget {
  /// Creates a [PurchaseScreen].
  const PurchaseScreen({super.key});

  /// Route name for named navigation.
  static const String routeName = '/purchase';

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final PurchaseService _purchaseService;
  bool _isLoading = false;
  bool _isRestoring = false;

  late final AnimationController _shimmerController;
  late final Animation<double> _shimmerAnimation;

  /// Features displayed in the paywall list.
  static const _features = [
    _Feature(
      icon: Icons.camera_alt_rounded,
      title: 'Scan Booking Confirmations',
      subtitle: 'On-device OCR — no cloud, no data leaves your phone',
    ),
    _Feature(
      icon: Icons.calendar_month_rounded,
      title: 'Instant Calendar Sync',
      subtitle: 'iCloud, Google, Outlook, Exchange — all supported',
    ),
    _Feature(
      icon: Icons.people_rounded,
      title: 'Smart Contact Matching',
      subtitle: 'Auto-match player names to your address book',
    ),
    _Feature(
      icon: Icons.notifications_active_rounded,
      title: 'Decline & RSVP Alerts',
      subtitle: 'Know immediately when someone drops out',
    ),
    _Feature(
      icon: Icons.refresh_rounded,
      title: 'Booking Amendments',
      subtitle: 'Re-scan to update — added and removed players tracked',
    ),
    _Feature(
      icon: Icons.lock_rounded,
      title: '100% Private & Offline',
      subtitle: 'Zero backend — everything runs on your device',
    ),
  ];

  @override
  void initState() {
    super.initState();

    // Register as a lifecycle observer for iOS background overlay.
    WidgetsBinding.instance.addObserver(this);

    // TODO: Re-add Android FLAG_SECURE screenshot blocking when a
    // maintained window-manager package is added to pubspec.yaml.
    // Previous implementation used flutter_windowmanager which was
    // never added as a dependency.

    // Subtle button shimmer animation.
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _shimmerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _initPurchaseService();
  }

  Future<void> _initPurchaseService() async {
    final appState = context.read<AppState>();
    _purchaseService = PurchaseService(appState: appState);

    // Wire up callbacks.
    _purchaseService
      ..onError = _handleError
      ..onPending = _handlePending
      ..onPurchaseComplete = _handlePurchaseComplete;

    await _purchaseService.initialize();

    // If already purchased (from cache), pop immediately.
    if (_purchaseService.isPurchased && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer.
    WidgetsBinding.instance.removeObserver(this);

    // (Android FLAG_SECURE cleanup — see TODO in initState.)

    _shimmerController.dispose();
    _purchaseService.dispose();
    super.dispose();
  }

  /// iOS: overlay a solid cover when the app moves to background to prevent
  /// the paywall appearing in the app switcher screenshot.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isIOS) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _showIosBackgroundOverlay();
    } else if (state == AppLifecycleState.resumed) {
      _removeIosBackgroundOverlay();
    }
  }

  OverlayEntry? _iosOverlay;

  void _showIosBackgroundOverlay() {
    if (_iosOverlay != null) return;
    _iosOverlay = OverlayEntry(
      builder: (_) => const ColoredBox(
        color: AppColors.white,
        child: SizedBox.expand(),
      ),
    );
    Overlay.of(context).insert(_iosOverlay!);
  }

  void _removeIosBackgroundOverlay() {
    _iosOverlay?.remove();
    _iosOverlay = null;
  }

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  void _handleError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isRestoring = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handlePending() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Purchase pending — waiting for confirmation.',
        ),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handlePurchaseComplete() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isRestoring = false;
    });
    // Pop back — the app will now show full content.
    Navigator.of(context).pop(true);
  }

  Future<void> _handleBuy() async {
    setState(() => _isLoading = true);
    await _purchaseService.buyApp();
    // Loading state will be cleared by onPurchaseComplete or onError.
  }

  Future<void> _handleRestore() async {
    setState(() => _isRestoring = true);
    await _purchaseService.restorePurchases();

    // Give the restore a moment to process, then check.
    await Future<void>.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    if (!_purchaseService.isPurchased) {
      setState(() => _isRestoring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No previous purchase found.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final isTablet = size.shortestSide >= 600;
    final horizontalPadding = isTablet ? 64.0 : 24.0;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Scrollable Content ──────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: isTablet ? 48 : 32),

                    // Branded golf ball logo
                    const GolfBallLogo(
                      size: 100,
                      animate: false,
                      showTee: true,
                      showGlow: true,
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      'All Teed Up',
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                color: AppColors.primary,
                              ),
                    ),
                    const SizedBox(height: 4),

                    // Tagline
                    Text(
                      'It\'s In The Calendar',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textMuted,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Feature list
                    ..._features.map(
                      (f) => _FeatureTile(feature: f),
                    ),
                    const SizedBox(height: 24),

                    // Price badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.palePurple,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'AED 99 — One Time. No Subscription. Ever.',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: AppColors.primary,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Less than the cost of a single round',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.softPurple,
                                      fontStyle: FontStyle.italic,
                                    ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ── Bottom CTA (fixed) ─────────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                bottomPadding + 16,
              ),
              decoration: BoxDecoration(
                color: AppColors.white,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textDark.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Purchase button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: AnimatedBuilder(
                      animation: _shimmerAnimation,
                      builder: (context, child) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                Color.lerp(
                                  AppColors.primary,
                                  AppColors.softPurple,
                                  _shimmerAnimation.value * 0.4,
                                )!,
                                AppColors.deepPurple,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: AppRadius.buttonBorder,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.primary.withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleBuy,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.buttonBorder,
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.lock_open_rounded,
                                    color: AppColors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Unlock All Teed Up',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 17,
                                      color: AppColors.white,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Restore button
                  SizedBox(
                    height: 44,
                    child: TextButton(
                      onPressed: _isRestoring ? null : _handleRestore,
                      child: _isRestoring
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Restoring…',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Restore Purchase',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                color: AppColors.textMuted,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Supporting Widgets
// =============================================================================

/// Data model for a feature in the paywall list.
class _Feature {
  const _Feature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

/// A single feature row with a purple checkmark, title, and subtitle.
class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.feature});

  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkmark circle
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.palePurple,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),

          // Text content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  feature.subtitle,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
