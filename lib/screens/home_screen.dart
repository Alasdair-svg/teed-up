import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'alerts_screen.dart';
import 'round_detail_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

/// Main home screen — matches the Claude design system exactly.
///
/// Layout:
/// - Custom header (title + subtitle + profile icon)
/// - Scrollable rounds list (or empty state)
/// - Pinned "+ Scan a booking" button
/// - Bottom nav with 4 items (scan is the elevated centre circle)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  static const String routeName = '/home';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: AppColors.offWhite,
          body: IndexedStack(
            index: state.currentTabIndex,
            children: const [
              _HomeTab(),
              AlertsScreen(),
              SizedBox.shrink(),
              SettingsScreen(),
            ],
          ),
          bottomNavigationBar: _BottomNav(state: state),
        );
      },
    );
  }
}

// =============================================================================
// Bottom Navigation
// =============================================================================

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border(
          top: BorderSide(color: AppColors.grey, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.grid_view_rounded,
                label: 'Home',
                selected: state.currentTabIndex == 0,
                onTap: () => state.setTab(0),
              ),
              _NavItemWithBadge(
                icon: Icons.circle_outlined,
                label: 'Alerts',
                selected: state.currentTabIndex == 1,
                badge: state.unreadAlertCount,
                onTap: () => state.setTab(1),
              ),
              // Centre scan button
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ScanScreen(),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.crop_square_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              _NavItem(
                icon: Icons.circle_outlined,
                label: 'Settings',
                selected: state.currentTabIndex == 3,
                onTap: () => state.setTab(3),
              ),
              // placeholder to balance layout
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemWithBadge extends StatelessWidget {
  const _NavItemWithBadge({
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text(
                badge > 99 ? '99+' : badge.toString(),
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
              ),
              backgroundColor: AppColors.error,
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Home Tab
// =============================================================================

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;

    return Consumer<AppState>(
      builder: (context, state, _) {
        final rounds = state.upcomingRounds;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(24, topPad + 20, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'All Teed Up',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w700,
                                fontSize: 26,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rounds.isEmpty
                              ? 'Snap your first booking below'
                              : 'Your upcoming rounds',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  // Profile / settings circle
                  GestureDetector(
                    onTap: () => state.setTab(3),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Rounds list ────────────────────────────────────────────────
            Expanded(
              child: rounds.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: rounds.length,
                      itemBuilder: (context, i) =>
                          _RoundCard(round: rounds[i]),
                    ),
            ),

            // ── Pinned scan button ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ScanScreen(),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '+ Scan a booking',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// Empty State
// =============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryPale,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.golf_course_rounded,
                size: 38,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No rounds yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Tap "+ Scan a booking" below to snap your first golf booking. Your group is sorted in seconds.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textMuted, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Round Card — matches Claude design exactly
// =============================================================================

class _RoundCard extends StatelessWidget {
  const _RoundCard({required this.round});
  final GolfRound round;

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final roundDay = DateTime(date.year, date.month, date.day);
    final diff = roundDay.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';

    // "Sat, 2 Aug"
    return DateFormat('EEE, d MMM').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RoundDetailScreen(roundId: round.id),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.grey),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Course name + date pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Hero(
                    tag: 'round_hero_${round.id}',
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        round.courseName,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Date pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPale,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _formatDate(round.date),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Tee time
            Text(
              '${round.formattedTeeTime} tee time',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),

            const SizedBox(height: 14),

            // Player avatar circles
            Row(
              children: round.players
                  .take(5)
                  .map((p) => _PlayerAvatar(player: p))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Player Avatar — purple circle with initials
// =============================================================================

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.player});
  final Player player;

  String get _initials {
    final name = player.name.trim();
    if (player.rsvpStatus == RsvpStatus.tbc ||
        name.isEmpty ||
        name.toLowerCase() == 'tbc') {
      return '?';
    }
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Color get _bgColor {
    return switch (player.rsvpStatus) {
      RsvpStatus.confirmed  => AppColors.primary,
      RsvpStatus.accepted   => AppColors.primary,
      RsvpStatus.declined   => AppColors.error,
      RsvpStatus.pending    => AppColors.primary,
      RsvpStatus.tbc        => AppColors.textMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: _bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _initials,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
