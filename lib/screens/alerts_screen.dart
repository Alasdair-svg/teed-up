import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'round_detail_screen.dart';

/// Alerts screen showing RSVP change notifications.
///
/// Displays a chronological list of RSVP changes (accepted/declined)
/// with unread cards accented with a purple left border.
/// Tapping a card navigates to the round detail.
class AlertsScreen extends StatelessWidget {
  /// Creates an [AlertsScreen].
  const AlertsScreen({super.key});

  /// Route name for navigation.
  static const String routeName = '/alerts';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Alerts'),
        automaticallyImplyLeading: false,
        actions: [
          Consumer<AppState>(
            builder: (context, state, _) {
              if (state.unreadAlertCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => state.markAllAlertsRead(),
                child: const Text('Mark all as read'),
              );
            },
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          final alerts = state.alerts;

          if (alerts.isEmpty) {
            return const _EmptyAlerts();
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            itemCount: alerts.length,
            itemBuilder: (context, index) => _AlertCard(
              alert: alerts[index],
              onTap: () {
                state.markAlertRead(alerts[index]);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        RoundDetailScreen(roundId: alerts[index].eventId),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Empty state for the alerts tab.
class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                color: AppColors.primaryPale,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 56,
                color: AppColors.primarySoft,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No alerts yet',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'When players respond to your invitations, '
              'you\'ll see their updates here.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single RSVP change notification card.
class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.onTap,
  });

  final RsvpChange alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (actionColor, actionLabel, actionIcon) = switch (alert.newStatus) {
      RsvpStatus.confirmed => (
          AppColors.success,
          'confirmed',
          Icons.check_circle_rounded
        ),
      RsvpStatus.accepted => (
          AppColors.success,
          'confirmed',
          Icons.check_circle_rounded
        ), // legacy
      RsvpStatus.pending => (
          AppColors.warning,
          'is pending',
          Icons.schedule_rounded
        ),
      RsvpStatus.declined => (
          AppColors.error,
          'declined',
          Icons.cancel_rounded
        ),
      RsvpStatus.tbc => (
          AppColors.textMuted,
          'is TBC',
          Icons.help_outline_rounded
        ),
    };
    final dateFormat = DateFormat('d MMM');
    final timeAgo = _formatTimeAgo(alert.detectedAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.cardBorder,
            boxShadow: cardShadow,
            border: !alert.isRead
                ? const Border(
                    left: BorderSide(color: AppColors.primary, width: 4),
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(actionIcon, size: 20, color: actionColor),
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Player action
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: AppColors.textDark,
                          ),
                          children: [
                            TextSpan(
                              text: alert.playerName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            TextSpan(text: ' $actionLabel'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Round details
                      Text(
                        '${dateFormat.format(alert.detectedAt)}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                // Time ago
                Text(
                  timeAgo,
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
      ),
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(timestamp);
  }
}
