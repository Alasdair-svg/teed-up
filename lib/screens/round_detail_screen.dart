import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'scan_screen.dart';

/// Detailed view of a single golf round.
///
/// Shows a hero header with course name and date, the player list with
/// RSVP status icons, an event timeline, and action buttons for amending
/// or cancelling the round.
class RoundDetailScreen extends StatelessWidget {
  /// Creates a [RoundDetailScreen] for the round with [roundId].
  const RoundDetailScreen({super.key, required this.roundId});

  /// The ID of the round to display.
  final String roundId;

  /// Route name for navigation.
  static const String routeName = '/round-detail';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final round = state.getRound(roundId);

        if (round == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text('Round not found'),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.white,
          body: CustomScrollView(
            slivers: [
              // ── Hero Header ──────────────────────────────────
              _HeroHeader(round: round),

              // ── Content ──────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Booking reference
                    if (round.bookingRef != null &&
                        round.bookingRef!.isNotEmpty) ...[
                      _InfoRow(
                        icon: Icons.confirmation_number_rounded,
                        label: 'Booking Ref',
                        value: round.bookingRef!,
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Players section
                    _SectionTitle(title: 'Players'),
                    const SizedBox(height: 12),
                    ...round.players.map((p) => _PlayerTile(player: p)),
                    const SizedBox(height: 28),

                    // Timeline section
                    _SectionTitle(title: 'Timeline'),
                    const SizedBox(height: 12),
                    _EventTimeline(round: round),
                    const SizedBox(height: 32),

                    // Action buttons
                    _ActionButtons(round: round),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Sliver app bar with hero-animated course name and date.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.round});

  final GolfRound round;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE, d MMMM yyyy');

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.textDark,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryPale,
                AppColors.white,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Course name with hero animation
                  Hero(
                    tag: 'round_hero_${round.id}',
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        round.courseName,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w700,
                          fontSize: 26,
                          color: AppColors.textDark,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Date and tee time
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: AppColors.primarySoft,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dateFormat.format(round.date),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppColors.textBody,
                        ),
                      ),
                      const SizedBox(width: 20),
                      const Icon(
                        Icons.access_time_rounded,
                        size: 16,
                        color: AppColors.primarySoft,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        round.formattedTeeTime,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled info row with icon.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.greyLight,
        borderRadius: AppRadius.cardBorder,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title with Outfit semi-bold.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

/// A single player tile with RSVP status icon and colour.
class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final (statusIcon, statusColor, statusLabel) = switch (player.rsvpStatus) {
      RsvpStatus.accepted => (
          Icons.check_circle_rounded,
          AppColors.success,
          'Accepted'
        ),
      RsvpStatus.pending => (
          Icons.schedule_rounded,
          AppColors.warning,
          'Pending'
        ),
      RsvpStatus.declined => (
          Icons.cancel_rounded,
          AppColors.error,
          'Declined'
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.cardBorder,
          border: Border.all(color: AppColors.grey),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: statusColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name and email
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
                  ),
                  if (player.email != null && player.email!.isNotEmpty)
                    Text(
                      player.email!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: statusColor,
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

/// Vertical event timeline for the round.
class _EventTimeline extends StatelessWidget {
  const _EventTimeline({required this.round});

  final GolfRound round;

  @override
  Widget build(BuildContext context) {
    // Build a default timeline if no events exist yet
    final events = round.timeline.isNotEmpty
        ? round.timeline
        : [
            RoundEvent(
              type: RoundEventType.created,
              timestamp: round.createdAt,
              description: 'Round created',
            ),
          ];

    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          _TimelineEntry(
            event: events[i],
            isLast: i == events.length - 1,
          ),
      ],
    );
  }
}

/// A single entry in the event timeline.
class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.event,
    required this.isLast,
  });

  final RoundEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('d MMM, HH:mm');

    final (icon, color) = switch (event.type) {
      RoundEventType.created => (Icons.add_circle_rounded, AppColors.primary),
      RoundEventType.invitesSent => (Icons.send_rounded, AppColors.primarySoft),
      RoundEventType.playerAccepted => (
          Icons.check_circle_rounded,
          AppColors.success
        ),
      RoundEventType.playerDeclined => (
          Icons.cancel_rounded,
          AppColors.error
        ),
      RoundEventType.amended => (
          Icons.edit_rounded,
          AppColors.warning
        ),
      RoundEventType.cancelled => (
          Icons.block_rounded,
          AppColors.error
        ),
    };

    final description = event.description ??
        switch (event.type) {
          RoundEventType.created => 'Round created',
          RoundEventType.invitesSent => 'Calendar invites sent',
          RoundEventType.playerAccepted => '${event.playerName} accepted',
          RoundEventType.playerDeclined => '${event.playerName} declined',
          RoundEventType.amended => 'Booking amended',
          RoundEventType.cancelled => 'Round cancelled',
        };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppColors.grey,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeFormat.format(event.timestamp),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Action buttons at the bottom of the round detail.
class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.round});

  final GolfRound round;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Amend Booking
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
              );
            },
            icon: const Icon(Icons.camera_alt_rounded, size: 20),
            label: const Text('Amend Booking'),
          ),
        ),
        const SizedBox(height: 12),

        // Cancel Round
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () => _confirmCancel(context),
            icon: const Icon(Icons.cancel_rounded, size: 20),
            label: const Text('Cancel Round'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmCancel(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Round?'),
        content: Text(
          'Are you sure you want to cancel the round at ${round.courseName}? '
          'This will remove the calendar event for all players.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () {
              context.read<AppState>().removeRound(round.id);
              Navigator.of(ctx).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back to home
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel Round'),
          ),
        ],
      ),
    );
  }
}
