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

/// Main home screen with bottom navigation, upcoming rounds list, and scan FAB.
///
/// Shows three tabs: Home (rounds list), Alerts (RSVP changes), Settings.
/// The Home tab displays upcoming round cards with player RSVP chips,
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
              SettingsScreen(),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(context, state),
          floatingActionButton: state.currentTabIndex == 0
              ? _ScanFab(onPressed: () => _openScanner(context))
              : null,
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
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: BottomNavigationBar(
          currentIndex: state.currentTabIndex,
          onTap: (i) => state.setTab(i),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.golf_course_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: _AlertsBadge(count: state.unreadAlertCount),
              label: 'Alerts',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
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

/// Badge overlay for the alerts tab icon.
class _AlertsBadge extends StatelessWidget {
  const _AlertsBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      backgroundColor: AppColors.error,
      child: const Icon(Icons.notifications_rounded),
    );
  }
}

/// Gradient FAB for scanning a booking.
class _ScanFab extends StatelessWidget {
  const _ScanFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        heroTag: 'scan_fab',
        child: const Icon(Icons.camera_alt_rounded, size: 28),
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
            // Branded golf ball on tee
            const GolfBallLogo(
              size: 160,
              animate: true,
              showTee: true,
              showGlow: true,
            ),
            const SizedBox(height: 32),

            Text(
              'No upcoming rounds',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            Text(
              'Scan your first booking confirmation to get started',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ScanScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('Scan Booking'),
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
    final (bgColor, fgColor) = switch (player.rsvpStatus) {
      RsvpStatus.accepted => (AppColors.successLight, AppColors.success),
      RsvpStatus.pending => (AppColors.warningLight, AppColors.warning),
      RsvpStatus.declined => (AppColors.errorLight, AppColors.error),
    };

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
            player.name,
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
