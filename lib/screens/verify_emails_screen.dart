import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/calendar_service.dart';
import '../services/rsvp_monitor.dart';
import '../theme/app_theme.dart';

/// Email verification screen — CRITICAL UX gate before sending invitations.
///
/// Displays each player with their resolved (or unresolved) email address,
/// the contact source, and an editable email field. Blocks progression
/// until all players have valid email addresses.
///
/// For amended bookings, newly added players show a "NEW" badge.
class VerifyEmailsScreen extends StatefulWidget {
  /// Creates a [VerifyEmailsScreen].
  const VerifyEmailsScreen({super.key});

  /// Route name for navigation.
  static const String routeName = '/verify-emails';

  @override
  State<VerifyEmailsScreen> createState() => _VerifyEmailsScreenState();
}

class _VerifyEmailsScreenState extends State<VerifyEmailsScreen> {
  late List<TextEditingController> _emailControllers;

  @override
  void initState() {
    super.initState();
    final players = context.read<AppState>().scannedPlayers;
    _emailControllers = players
        .map((p) => TextEditingController(text: p.email ?? ''))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _emailControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool _allEmailsValid(List<Player> players) {
    for (var i = 0; i < players.length; i++) {
      final email = _emailControllers[i].text.trim();
      if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
        return false;
      }
    }
    return true;
  }

  Future<void> _sendInvitations() async {
    final state = context.read<AppState>();
    final players = state.scannedPlayers;

    // Update all player emails from controllers
    for (var i = 0; i < players.length; i++) {
      state.updateScannedPlayerEmail(
        players[i].id,
        _emailControllers[i].text.trim(),
      );
    }

    // Build the round object.
    var round = GolfRound(
      id: 'round_${DateTime.now().millisecondsSinceEpoch}',
      courseName: state.scannedCourseName ?? 'Unknown Course',
      date: state.scannedDate ?? DateTime.now(),
      teeTime: state.scannedTeeTime ?? DateTime.now(),
      players: state.scannedPlayers,
      bookingRef: state.scannedBookingRef,
    );

    // Create calendar event with attendees on the device.
    final calendarId = state.selectedCalendarId;
    if (calendarId != null && calendarId.isNotEmpty) {
      try {
        final calendarService = CalendarService();
        final eventId = await calendarService.createGolfEvent(
          round,
          calendarId,
        );

        if (eventId != null) {
          round = round.copyWith(calendarEventId: eventId);

          // Register with RSVP monitor for background polling.
          final attendeeStatus = <String, String>{};
          for (final player in round.players) {
            if (player.hasValidEmail) {
              attendeeStatus[player.email!] = 'pending';
            }
          }
          await RsvpMonitor.instance.registerEvent(eventId, attendeeStatus);
        }
      } catch (e) {
        debugPrint('Calendar event creation failed: $e');
        // Non-fatal — round is still saved locally.
      }
    }

    state.addRound(round);
    state.clearScanState();
    state.setTab(0);

    if (!mounted) return;

    // Pop all the way back to home
    Navigator.of(context).popUntil((route) => route.isFirst);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invitations sent! 🎉'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Verify Emails'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          final players = state.scannedPlayers;

          return Column(
            children: [
              // ── Warning Header ───────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                decoration: const BoxDecoration(
                  color: AppColors.primaryPale,
                  border: Border(
                    bottom: BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                child: const Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _HeaderDash(),
                        SizedBox(width: 12),
                        Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.primary,
                          size: 28,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'REVIEW REQUIRED',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: AppColors.primary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(width: 12),
                        _HeaderDash(),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Verify each player\'s email before sending calendar invitations.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: AppColors.textBody,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // ── Player Cards ─────────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return _PlayerEmailCard(
                      player: player,
                      controller: _emailControllers[index],
                      onChanged: (email) {
                        setState(() {}); // Rebuild to update button state
                        state.updateScannedPlayerEmail(player.id, email);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomSheet: _buildBottomActions(context),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    final players = context.watch<AppState>().scannedPlayers;
    final allValid = _allEmailsValid(players);

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cancel text button
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 8),

          // Send invitations button
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: allValid ? _sendInvitations : null,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send Invitations'),
              style: ElevatedButton.styleFrom(
                backgroundColor: allValid ? AppColors.primary : AppColors.grey,
                foregroundColor:
                    allValid ? AppColors.white : AppColors.textMuted,
                disabledBackgroundColor: AppColors.grey,
                disabledForegroundColor: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decorative dash line for the review header.
class _HeaderDash extends StatelessWidget {
  const _HeaderDash();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 3,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Card for a single player's email verification.
class _PlayerEmailCard extends StatelessWidget {
  const _PlayerEmailCard({
    required this.player,
    required this.controller,
    required this.onChanged,
  });

  final Player player;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasValidEmail = controller.text.trim().isNotEmpty &&
        controller.text.contains('@') &&
        controller.text.contains('.');
    final isUnresolved = controller.text.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.cardBorder,
          border: Border.all(
            color: isUnresolved ? AppColors.error : AppColors.grey,
            width: isUnresolved ? 2 : 1,
          ),
          boxShadow: cardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Player name row
              Row(
                children: [
                  // Avatar circle
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryPale,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        player.name.isNotEmpty
                            ? player.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name
                  Expanded(
                    child: Text(
                      player.name,
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),

                  // NEW badge for amended bookings
                  if (player.isNewlyAdded) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                          color: AppColors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // Email field
              TextField(
                controller: controller,
                onChanged: onChanged,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: isUnresolved ? 'Add email address' : null,
                  prefixIcon: Icon(
                    hasValidEmail
                        ? Icons.check_circle_rounded
                        : Icons.email_rounded,
                    color: hasValidEmail ? AppColors.success : null,
                    size: 20,
                  ),
                  suffixIcon: isUnresolved
                      ? const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                          size: 20,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),

              // Contact source badge
              _ContactSourceBadge(source: player.contactSource),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small chip showing where the contact data was sourced from.
class _ContactSourceBadge extends StatelessWidget {
  const _ContactSourceBadge({required this.source});

  final ContactSource source;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (source) {
      ContactSource.iCloud => ('iCloud', Icons.cloud_rounded),
      ContactSource.google => ('Google', Icons.g_mobiledata_rounded),
      ContactSource.outlook => ('Outlook', Icons.mail_rounded),
      ContactSource.manual => ('Manual', Icons.edit_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.greyLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
