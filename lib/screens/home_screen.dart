import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/golf_ball_logo.dart';
import 'alerts_screen.dart';
import 'round_detail_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

/// Main home screen with bottom navigation, upcoming rounds list, and scan CTA.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  static const String routeName = '/home';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          body: IndexedStack(
            index: state.currentTabIndex,
            children: const [
              _HomeTab(),
              AlertsScreen(),
              SizedBox.shrink(),
              SettingsScreen(),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(context, state),
        );
      },
    );
  }

  Widget _buildBottomNav(BuildContext context, AppState state) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.golf_course_rounded,
                label: 'Rounds',
                selected: state.currentTabIndex == 0,
                onTap: () => state.setTab(0),
              ),
              _NavItem(
                icon: Icons.notifications_rounded,
                label: 'Alerts',
                selected: state.currentTabIndex == 1,
                badge: state.unreadAlertCount,
                onTap: () => state.setTab(1),
              ),
              _ScanNavItem(onTap: () => _openScanner(context)),
              _NavItem(
                icon: Icons.settings_rounded,
                label: 'Settings',
                selected: state.currentTabIndex == 3,
                onTap: () => state.setTab(3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openScanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text(
                  badge > 99 ? '99+' : badge.toString(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                ),
                backgroundColor: AppColors.error,
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 11,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanNavItem extends StatelessWidget {
  const _ScanNavItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.document_scanner_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

// =============================================================================
// Home Tab — Hero Header + Rounds List
// =============================================================================

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final rounds = state.upcomingRounds;

        return CustomScrollView(
          slivers: [
            // ── Hero header ──────────────────────────────────────────────────
            _HeroHeader(hasRounds: rounds.isNotEmpty),

            // ── Content ──────────────────────────────────────────────────────
            if (rounds.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Text(
                        'Upcoming Rounds',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPale,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${rounds.length}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _RoundCard(round: rounds[index]),
                    childCount: rounds.length,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// =============================================================================
// Hero Header
// =============================================================================

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.hasRounds});
  final bool hasRounds;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.deepPurple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Subtle pattern overlay
            Positioned.fill(
              child: CustomPaint(
                painter: _GolfDimplePainter(),
              ),
            ),

            Padding(
              padding: EdgeInsets.fromLTRB(24, topPadding + 20, 24, 28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Text block
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Eyebrow label
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '⛳ GOLF BOOKING',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              color: Colors.white,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // App name
                        const Text(
                          'All Teed Up',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 30,
                            color: Colors.white,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Tagline
                        Text(
                          hasRounds
                              ? 'Your group is sorted.'
                              : 'Snap your booking.\nYour group is sorted.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.45,
                          ),
                        ),

                        if (!hasRounds) ...[
                          const SizedBox(height: 20),
                          // Scan CTA
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ScanScreen(),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.document_scanner_rounded,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Scan a booking',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Golf ball logo
                  const GolfBallLogo(
                    size: 90,
                    animate: true,
                    showTee: false,
                    showGlow: true,
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

/// Subtle dimple dot pattern — gives the header a golf ball texture feel.
class _GolfDimplePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    const radius = 3.5;

    for (double y = 0; y < size.height + spacing; y += spacing) {
      for (double x = 0; x < size.width + spacing; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GolfDimplePainter oldDelegate) => false;
}

// =============================================================================
// Empty State
// =============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration container
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.primaryPale,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.golf_course_rounded,
              size: 52,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'No rounds yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Tap the scan button below to snap your first golf booking — your group will be sorted in seconds.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.55,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // How it works mini-steps
          _HowItWorksRow(
            steps: const [
              _Step(icon: Icons.camera_alt_rounded, label: 'Snap booking'),
              _Step(icon: Icons.auto_fix_high_rounded, label: 'Auto-read'),
              _Step(icon: Icons.calendar_today_rounded, label: 'Calendar invite'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step {
  const _Step({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _HowItWorksRow extends StatelessWidget {
  const _HowItWorksRow({required this.steps});
  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          _StepBubble(step: steps[i]),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepBubble extends StatelessWidget {
  const _StepBubble({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryPale,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(step.icon, size: 22, color: AppColors.primary),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
            fontSize: 11,
            color: AppColors.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// =============================================================================
// Round Card
// =============================================================================

class _RoundCard extends StatelessWidget {
  const _RoundCard({required this.round});
  final GolfRound round;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, d MMM yyyy');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTap: () => _openDetail(context),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.cardBorder,
            boxShadow: cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coloured top stripe
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.card),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Course name
                    Hero(
                      tag: 'round_hero_${round.id}',
                      child: Material(
                        color: Colors.transparent,
                        child: Text(
                          round.courseName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Date + time row
                    Row(
                      children: [
                        _InfoChip(
                          icon: Icons.calendar_today_rounded,
                          label: dateFormat.format(round.date),
                        ),
                        const SizedBox(width: 10),
                        _InfoChip(
                          icon: Icons.access_time_rounded,
                          label: round.formattedTeeTime,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Player chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: round.players
                          .map((player) => _PlayerChip(player: player))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoundDetailScreen(roundId: round.id),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.greyLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: AppColors.textBody,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    final (bgColor, fgColor) = switch (player.rsvpStatus) {
      RsvpStatus.confirmed  => (AppColors.successLight, AppColors.success),
      RsvpStatus.pending    => (AppColors.warningLight, AppColors.warning),
      RsvpStatus.declined   => (AppColors.errorLight,   AppColors.error),
      RsvpStatus.accepted   => (AppColors.successLight, AppColors.success),
    };

    final isTbc = player.name.trim().isEmpty ||
        player.name.trim().toLowerCase() == 'tbc';
    final displayName = isTbc ? 'TBC' : player.name;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: fgColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            displayName,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}
