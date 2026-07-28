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
///
/// Shows four tabs: Home (rounds list), Alerts (RSVP changes), Scan (elevated),
/// Settings. The Home tab displays upcoming round cards with player RSVP chips,
/// or an empty state prompting the user to scan their first booking.
class HomeScreen extends StatelessWidget {
  /// Creates a [HomeScreen].
  const HomeScreen({super.key});

  /// Route name for navigation.
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
              SizedBox.shrink(), // Scan is always a push, not a tab page
              SettingsScreen(),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(context, state),
        );
      },
    );
  }

  Widget _buildBottomNav(BuildContext context, AppState state) {
    // 4 tabs — Scan (index 2) is the elevated centre action.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Home
              _NavItem(
                icon: Icons.golf_course_rounded,
                label: 'Home',
                selected: state.currentTabIndex == 0,
                onTap: () => state.setTab(0),
              ),
              // Alerts
              _NavItem(
                icon: Icons.notifications_rounded,
                label: 'Alerts',
                selected: state.currentTabIndex == 1,
                badge: state.unreadAlertCount,
                onTap: () => state.setTab(1),
              ),
              // Scan — elevated centre button
              _ScanNavItem(onTap: () => _openScanner(context)),
              // Settings
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

/// Individual nav tab item.
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

/// Elevated scan button in the centre of the bottom nav bar.
class _ScanNavItem extends StatelessWidget {
  const _ScanNavItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.document_scanner_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}


/// The Home tab body showing upcoming rounds or empty state.
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Teed Up'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () =>
                context.read<AppState>().setTab(2), // Switch to settings tab
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          final rounds = state.upcomingRounds;

          if (rounds.isEmpty) {
            return const _EmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
            itemCount: rounds.length,
            itemBuilder: (context, index) => _RoundCard(round: rounds[index]),
          );
        },
      ),
    );
  }
}

/// Empty state shown when there are no upcoming rounds.
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
            const GolfBallLogo(
              size: 160,
              animate: true,
              showTee: true,
              showGlow: true,
            ),
            const SizedBox(height: 32),
            Text(
              'No rounds yet',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Fore-tunately, that’s easy to fix\u00a0\u2014 scan your first booking below.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textMuted,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Scan a booking'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card displaying a single upcoming round with player RSVP chips.
///
/// Tapping the card navigates to [RoundDetailScreen] with a hero animation
/// on the course name.
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
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Course name with hero animation
                Hero(
                  tag: 'round_hero_${round.id}',
                  child: Material(
                    color: Colors.transparent,
                    child: Text(
                      round.courseName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Date and tee time
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      dateFormat.format(round.date),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      round.formattedTeeTime,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Player RSVP chips
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

/// A chip showing a player's name coloured by RSVP status.
class _PlayerChip extends StatelessWidget {
  const _PlayerChip({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final (bgColor, fgColor, label) = switch (player.rsvpStatus) {
      RsvpStatus.confirmed  => (AppColors.successLight, AppColors.success,  player.name),
      RsvpStatus.pending => (AppColors.warningLight, AppColors.warning,   player.name),
      RsvpStatus.declined => (AppColors.errorLight,  AppColors.error,     player.name),
      RsvpStatus.accepted => (AppColors.successLight, AppColors.success,   player.name), // legacy
    };

    final isTbc = player.name.trim().isEmpty || player.name.trim().toLowerCase() == 'tbc';
    final displayName = isTbc ? '?' : label;

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
            width: 8,
            height: 8,
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

