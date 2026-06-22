import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/app_state.dart';
import '../services/device_capability_service.dart';
import '../theme/app_theme.dart';
import '../widgets/golf_ball_logo.dart';
import 'home_screen.dart';

/// Onboarding screen shown on first launch.
///
/// Three-slide PageView introducing the app's core features:
/// 1. Snap Your Booking (camera)
/// 2. Invite Your Group (people)
/// 3. Stay in the Loop (notifications)
///
/// The final slide shows a "Get Started" button that requests
/// calendar, contacts, and camera permissions before navigating
/// to the home screen.
class OnboardingScreen extends StatefulWidget {
  /// Creates an [OnboardingScreen].
  const OnboardingScreen({super.key});

  /// Route name for navigation.
  static const String routeName = '/onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _slides = [
    _SlideData(
      icon: Icons.camera_alt_rounded,
      title: 'Snap Your Booking',
      description:
          'Take a photo of your golf booking confirmation and we\'ll '
          'extract all the details automatically using on-device OCR.',
    ),
    _SlideData(
      icon: Icons.people_rounded,
      title: 'Invite Your Group',
      description:
          'We\'ll match player names to your contacts and send calendar '
          'invites — iCloud, Google, Outlook, you name it.',
    ),
    _SlideData(
      icon: Icons.notifications_active_rounded,
      title: 'Stay in the Loop',
      description:
          'Get notified when players accept or decline. Amend bookings '
          'with a new scan — your group stays sorted.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleGetStarted() async {
    // 1. Request all required permissions.
    await [
      Permission.calendarWriteOnly,
      Permission.calendarFullAccess,
      Permission.contacts,
      Permission.camera,
    ].request();

    if (!mounted) return;

    // 2. Check device capabilities now that permissions have been granted.
    final capability = await DeviceCapabilityService.check();

    if (!mounted) return;

    // 3. If anything critical is missing, warn the user before proceeding.
    if (capability.hasIssues) {
      final shouldContinue = await _showIncompatibilitySheet(capability);
      if (!mounted) return;
      // If user chose to exit, close the app.
      if (!shouldContinue) {
        await SystemNavigator.pop();
        return;
      }
    }

    // 4. Mark onboarding complete and navigate to home.
    if (!mounted) return;
    context.read<AppState>().completeOnboarding();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  /// Shows a bottom sheet explaining which device capabilities are missing.
  ///
  /// Returns `true` if the user chose to continue anyway, `false` if they
  /// chose to exit the app.
  Future<bool> _showIncompatibilitySheet(
    DeviceCapabilityResult result,
  ) async {
    final shouldContinue = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _DeviceCompatibilitySheet(result: result),
    );
    return shouldContinue ?? false;
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: kTransitionDuration,
        curve: kTransitionCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.shortestSide >= 600;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Page View ────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) => _OnboardingSlide(
                  data: _slides[index],
                  slideIndex: index,
                  isTablet: isTablet,
                ),
              ),
            ),

            // ── Page Indicator ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => AnimatedContainer(
                    duration: kTransitionDuration,
                    curve: kTransitionCurve,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _currentPage ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _currentPage
                          ? AppColors.primary
                          : AppColors.grey,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom Button ────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: _currentPage == _slides.length - 1
                    ? _PrimaryGradientButton(
                        label: 'Get Started',
                        onPressed: _handleGetStarted,
                      )
                    : ElevatedButton(
                        onPressed: _nextPage,
                        child: const Text('Next'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Data model for an onboarding slide.
class _SlideData {
  const _SlideData({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

/// A single onboarding slide with icon, title, and description.
class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.data,
    required this.slideIndex,
    required this.isTablet,
  });

  final _SlideData data;
  final int slideIndex;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final iconSize = isTablet ? 120.0 : 88.0;
    final heroSize = isTablet ? 200.0 : 160.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 64 : 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // First slide: branded spinning golf ball on tee
          // Other slides: icon circle
          if (slideIndex == 0)
            GolfBallLogo(
              size: heroSize,
              animate: true,
              showTee: true,
              showGlow: true,
            )
          else
            Container(
              width: iconSize + 40,
              height: iconSize + 40,
              decoration: BoxDecoration(
                color: AppColors.primaryPale,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 40,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                data.icon,
                size: iconSize,
                color: AppColors.primary,
              ),
            ),
          SizedBox(height: isTablet ? 48 : 40),

          // Title
          Text(
            data.title,
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Description
          Text(
            data.description,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A button with the brand purple gradient background.
class _PrimaryGradientButton extends StatelessWidget {
  const _PrimaryGradientButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: AppRadius.buttonBorder,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Device Compatibility Bottom Sheet
// ---------------------------------------------------------------------------

/// Modal bottom sheet shown when [DeviceCapabilityService] detects that one
/// or more capabilities are unavailable on this device.
///
/// Displays a ✅/❌ list with plain-English explanations, then presents two
/// choices: exit the app, or continue anyway (for MDM/enterprise edge cases).
class _DeviceCompatibilitySheet extends StatelessWidget {
  const _DeviceCompatibilitySheet({required this.result});

  final DeviceCapabilityResult result;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device Compatibility Check',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Some features may not work on this device.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.grey,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // ── Capability rows ───────────────────────────────────────
          _CapabilityRow(
            label: 'Calendar',
            description:
                'Required to create tee time events and send invitations.',
            available: result.hasCalendar,
          ),
          const SizedBox(height: 12),
          _CapabilityRow(
            label: 'Contacts',
            description:
                'Used to match player names to email addresses automatically.',
            available: result.hasContacts,
          ),
          const SizedBox(height: 12),
          _CapabilityRow(
            label: 'Camera / Photo Library',
            description:
                'Required to photograph or import your booking confirmation.',
            available: result.hasCameraOrGallery,
          ),
          const SizedBox(height: 12),
          _CapabilityRow(
            label: 'Google Play Services',
            description:
                'Required to complete the one-time in-app purchase.',
            available: result.hasPlayServices,
          ),

          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // ── Warning text ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'All Teed Up requires all of the above to work correctly. '
              'If your device or organisation restricts these features, '
              'the app may not function as intended.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                    height: 1.5,
                  ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Actions ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonBorder,
                ),
              ),
              child: const Text(
                'Exit App',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.grey),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonBorder,
                ),
              ),
              child: Text(
                'Continue Anyway',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  color: AppColors.textBody,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single row in the compatibility check list.
class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.label,
    required this.description,
    required this.available,
  });

  final String label;
  final String description;
  final bool available;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status icon
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            available ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 20,
            color: available ? AppColors.primary : AppColors.error,
          ),
        ),
        const SizedBox(width: 12),
        // Label + description
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: available ? AppColors.textDark : AppColors.error,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.grey,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

