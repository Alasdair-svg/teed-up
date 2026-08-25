/// Onboarding screen — shown on first launch.
///
/// ## Flow (5 pages, 3 user-facing "STEP N of 3" labels)
///
/// 1. **Welcome** — brand logo + headline copy, no step label
/// 2. **Permissions** — Camera, Calendar, Contacts (STEP 1 OF 3)
/// 3. **Calendar accounts** — link calendars + pick a primary (STEP 2 OF 3)
/// 4. **Family setup** — add up to 5 family/friends to notify (STEP 3 OF 3)
/// 5. **Done** — completion; navigates to [HomeScreen]
///
/// Regulars/players are no longer collected at onboarding — they come from OCR
/// each time a booking is scanned.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/family_member.dart';
import '../providers/app_state.dart';
import '../services/contacts_service.dart';
import '../services/device_capability_service.dart';
import '../services/rsvp_monitor.dart';
import '../theme/app_theme.dart';
import '../widgets/calendar_accounts_section.dart';
import '../widgets/family_setup_section.dart';
import '../widgets/golf_ball_logo.dart';
import 'home_screen.dart';

// =============================================================================
// Public screen
// =============================================================================

/// Onboarding screen shown once on first launch.
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

  // 0 = Welcome, 1 = Permissions, 2 = Calendar accounts, 3 = Family, 4 = Done
  static const int _totalPages = 5;

  // Family members being added during onboarding (shared with AppState on finish)
  final List<FamilyMember> _familyEntries = [];

  // True while permissions + device-capability checks are in flight, so the
  // "Grant Permissions" button can show a spinner instead of appearing to
  // sit on the same page twice.
  bool _requestingPermissions = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _next() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: kTransitionDuration,
        curve: kTransitionCurve,
      );
    }
  }

  void _back() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: kTransitionDuration,
        curve: kTransitionCurve,
      );
    }
  }

  Future<void> _handlePermissionsNext() async {
    setState(() => _requestingPermissions = true);
    try {
      await [
        Permission.calendarWriteOnly,
        Permission.calendarFullAccess,
        Permission.contacts,
        Permission.camera,
      ].request();

      // Warm the contacts cache in the background now that permission is
      // granted, so the Family setup step's first search isn't the one
      // paying the device-contacts fetch cost.
      ContactsService.prefetch();

      if (!mounted) return;

      final capability = await DeviceCapabilityService.check();
      if (!mounted) return;

      if (capability.hasIssues) {
        final ok = await _showIncompatibilitySheet(capability);
        if (!mounted) return;
        if (!ok) {
          await SystemNavigator.pop();
          return;
        }
      }

      _next();
    } finally {
      if (mounted) setState(() => _requestingPermissions = false);
    }
  }

  Future<void> _handleFinish() async {
    if (!mounted) return;
    // Persist family members into app state
    final appState = context.read<AppState>();
    for (final entry in _familyEntries) {
      appState.addFamilyMember(name: entry.name, email: entry.email);
    }
    appState.completeOnboarding();
    // Fire-and-forget — enriches self-identity resolution once calendar
    // permission has just been granted, but shouldn't add latency to
    // finishing onboarding (see the earlier fix for slow-feeling permission
    // steps). A missed result here just means selfPlayerIn returns null
    // until the next launch picks it up in main.dart.
    unawaited(appState.loadOwnAccountEmails());
    // Same reasoning — the first calendar scan for the growth loop's
    // auto-import shouldn't block finishing onboarding. If a round was
    // already sitting in the newly-linked calendar (someone invited this
    // user before they'd even installed the app), it appears on Home a
    // moment after landing there rather than holding up this transition.
    unawaited(RsvpMonitor.instance.reconcileWithCalendar(appState));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  Future<bool> _showIncompatibilitySheet(DeviceCapabilityResult result) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DeviceCompatibilitySheet(result: result),
    );
    return ok ?? false;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Back button (mid-flow steps only) ─────────────────────
            if (_currentPage >= 1 && _currentPage <= 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),

            // ── PageView ─────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _WelcomePage(isTablet: isTablet),
                  _PermissionsPage(isTablet: isTablet),
                  _CalendarAccountsPage(isTablet: isTablet),
                  _FamilySetupPage(
                    isTablet: isTablet,
                    entries: _familyEntries,
                    onAdd: (name, email) => setState(
                      () => _familyEntries.add(
                        FamilyMember(name: name, email: email),
                      ),
                    ),
                    onRemove: (i) => setState(() => _familyEntries.removeAt(i)),
                  ),
                  _DonePage(isTablet: isTablet),
                ],
              ),
            ),

            // ── Step indicator (hidden on Welcome and Done) ───────────
            if (_currentPage >= 1 && _currentPage <= 3)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'STEP $_currentPage OF 3',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

            // ── Page dots (Welcome + Done hidden) ─────────────────────
            if (_currentPage >= 1 && _currentPage <= 3)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final active = i == _currentPage - 1;
                    return AnimatedContainer(
                      duration: kTransitionDuration,
                      curve: kTransitionCurve,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : AppColors.grey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),

            // ── CTA button ───────────────────────────────────────────
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
                child: _buildCta(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCta() {
    switch (_currentPage) {
      case 0: // Welcome
        return _PrimaryGradientButton(
          label: 'Get Started',
          onPressed: _next,
        );
      case 1: // Permissions
        return _PrimaryGradientButton(
          label: 'Grant Permissions',
          onPressed: _handlePermissionsNext,
          loading: _requestingPermissions,
          loadingLabel: 'Setting up…',
        );
      case 2: // Calendar accounts
        return _PrimaryGradientButton(
          label: 'Continue',
          onPressed: _next,
        );
      case 3: // Family setup
        return _PrimaryGradientButton(
          label: _familyEntries.isEmpty ? 'Skip for now' : 'Continue',
          onPressed: _next,
        );
      case 4: // Done
        return _PrimaryGradientButton(
          label: "Let's go!",
          onPressed: _handleFinish,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// =============================================================================
// Pages
// =============================================================================

// ---------------------------------------------------------------------------
// Welcome
// ---------------------------------------------------------------------------

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.isTablet});
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final heroSize = isTablet ? 220.0 : 160.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 64 : 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GolfBallLogo(
            size: heroSize,
            animate: true,
            showTee: true,
            showGlow: true,
          ),
          SizedBox(height: isTablet ? 56 : 40),
          Text(
            'All Teed Up',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Snap your booking....Your group never misses a tee time',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'No accounts. No cloud. No Data Leaves Your Phone\u00a0—\u00a0Except A Calendar Invite.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.55,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Permissions
// ---------------------------------------------------------------------------

class _PermissionsPage extends StatelessWidget {
  const _PermissionsPage({required this.isTablet});
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 64 : 24,
        32,
        isTablet ? 64 : 24,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A few things we need',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'All Teed Up runs entirely on your device — no cloud, no accounts.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
          const SizedBox(height: 28),

          // Camera
          _PermissionCard(
            icon: Icons.camera_alt_rounded,
            title: 'Camera',
            description:
                'So you can snap your booking from the golf app and automatically create a calendar entry.',
          ),
          const SizedBox(height: 12),

          // Calendar
          _PermissionCard(
            icon: Icons.calendar_month_rounded,
            title: 'Calendar',
            description:
                'So you can pop your tee times straight on it\u00a0—\u00a0no double-booking the in-laws.',
          ),
          const SizedBox(height: 12),

          // Contacts
          _PermissionCard(
            icon: Icons.contacts_rounded,
            title: 'Contacts',
            description:
                'So you automatically send your playing partners a calendar invite\u00a0—\u00a0works across every contacts account on your phone. To get the most out of the app, you\u2019ll need your fellow players\u2019 email addresses\u00a0—\u00a0you can add them manually if they\u2019re not already in your contacts.',
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.grey),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryPale,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textBody,
                        height: 1.5,
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

// ---------------------------------------------------------------------------
// Calendar accounts (STEP 2 OF 3) — spec C2
//
// Lists calendars grouped by device account (Apple iCloud, Google, Outlook/
// Exchange, other CalDAV) with a link/unlink toggle for each, plus a "Set as
// primary" pill on linked, non-primary calendars. Backed directly by the
// AppState.primaryCalendarId / linkedCalendarIds already wired for scanning
// and RSVP monitoring — this screen just gives it a first-class UI.
// ---------------------------------------------------------------------------

class _CalendarAccountsPage extends StatelessWidget {
  const _CalendarAccountsPage({required this.isTablet});
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 64 : 24,
        32,
        isTablet ? 64 : 24,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where should tee times land?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Link the calendars you use, and pick one as primary — '
            'that’s where invites get written by default.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.55,
                ),
          ),
          const SizedBox(height: 24),
          const CalendarAccountsSection(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Family setup page (onboarding wrapper) — spec A4
//
// The shared FamilySetupSection widget (autocomplete, add/remove, 5-cap) now
// lives in lib/widgets/family_setup_section.dart so it's genuinely reusable
// from SettingsScreen too.
// ---------------------------------------------------------------------------

class _FamilySetupPage extends StatelessWidget {
  const _FamilySetupPage({
    required this.isTablet,
    required this.entries,
    required this.onAdd,
    required this.onRemove,
  });

  final bool isTablet;
  final List<FamilyMember> entries;
  final void Function(String name, String email) onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 64 : 24,
        32,
        isTablet ? 64 : 24,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep friends and family in the loop',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Got friends or family you\u2019d like to inform that you\u2019ll be playing? '
            'Add them here\u00a0—\u00a0they\u2019re not playing, they\u2019re just\u2026 informed.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.55,
                ),
          ),
          const SizedBox(height: 24),
          FamilySetupSection(
              entries: entries, onAdd: onAdd, onRemove: onRemove),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Done
// ---------------------------------------------------------------------------

class _DonePage extends StatelessWidget {
  const _DonePage({required this.isTablet});
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 64 : 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.deepPurple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.golf_course_rounded,
              size: 56,
              color: AppColors.white,
            ),
          ),
          SizedBox(height: isTablet ? 48 : 36),
          Text(
            'All Teed Up!',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: AppColors.primary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            'Scan your first booking and your group is sorted.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.55,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Shared UI helpers
// =============================================================================

/// A button with the brand gradient background.
class _PrimaryGradientButton extends StatelessWidget {
  const _PrimaryGradientButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel = 'Working…',
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;

  /// Shown beside the spinner while [loading]. A bare spinner with no words
  /// reads as a stuck button over a long wait — the permission sweep can
  /// take several seconds, and users reported the app looking frozen.
  final String loadingLabel;

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
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonBorder),
        ),
        child: loading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The app's own spinning ball, not a generic ring — the
                  // user asked for this specifically so a slow permission
                  // sweep reads as the app working rather than frozen.
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: GolfBallLogo(
                      size: 24,
                      animate: true,
                      showTee: false,
                      showGlow: false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    loadingLabel,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: AppColors.white,
                    ),
                  ),
                ],
              )
            : Text(
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

// =============================================================================
// Device Compatibility Bottom Sheet (unchanged from v1)
// =============================================================================

/// Modal bottom sheet shown when device capabilities are missing.
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Device Compatibility Check',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
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
          _CapRow(
              label: 'Camera / Photo Library',
              description:
                  'Required to photograph or import your booking confirmation.',
              available: result.hasCameraOrGallery),
          const SizedBox(height: 12),
          _CapRow(
              label: 'Calendar',
              description:
                  'Required to create tee time events and send invitations.',
              available: result.hasCalendar),
          const SizedBox(height: 12),
          _CapRow(
              label: 'Contacts',
              description:
                  'Used to match player names to email addresses automatically.',
              available: result.hasContacts),
          const SizedBox(height: 12),
          _CapRow(
              label: 'Google Play Services',
              description: 'Required to complete the one-time in-app purchase.',
              available: result.hasPlayServices),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),
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
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.buttonBorder),
              ),
              child: const Text('Exit App',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.white,
                  )),
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
                    borderRadius: AppRadius.buttonBorder),
              ),
              child: Text('Continue Anyway',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: AppColors.textBody,
                  )),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapRow extends StatelessWidget {
  const _CapRow({
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
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            available ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 20,
            color: available ? AppColors.primary : AppColors.error,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: available ? AppColors.textDark : AppColors.error,
                      )),
              const SizedBox(height: 2),
              Text(description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.grey,
                        height: 1.4,
                      )),
            ],
          ),
        ),
      ],
    );
  }
}
