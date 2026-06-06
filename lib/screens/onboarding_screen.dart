import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';
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
    // Request all required permissions
    await [
      Permission.calendar,
      Permission.contacts,
      Permission.camera,
    ].request();

    if (!mounted) return;

    // Mark onboarding complete
    context.read<AppState>().completeOnboarding();

    // Navigate to home
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
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
  const _OnboardingSlide({required this.data, required this.isTablet});

  final _SlideData data;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final iconSize = isTablet ? 120.0 : 88.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 64 : 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon circle
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
