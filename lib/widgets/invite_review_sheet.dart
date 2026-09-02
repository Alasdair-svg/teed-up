/// Last look at a round before its invite goes out.
///
/// Exists because an invite is not undoable in any way the app controls:
/// once it is written, everyone on it has been notified. A tee time that
/// went out at the wrong hour could only be discovered by the recipients.
/// This puts the details in front of the user, with a way back to change
/// them, before anything is sent.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'package:device_calendar/device_calendar.dart' show Calendar;
import '../services/calendar_service.dart';

/// What the user chose to do from the review sheet.
enum InviteReviewChoice {
  /// Send the invite as shown.
  send,

  /// Go back and edit the round first.
  edit,
}

/// Shows the review sheet; resolves to null if dismissed without choosing.
Future<InviteReviewChoice?> showInviteReviewSheet(
  BuildContext context, {
  required GolfRound round,
  Calendar? targetCalendar,
}) {
  return showModalBottomSheet<InviteReviewChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        InviteReviewSheet(round: round, targetCalendar: targetCalendar),
  );
}

/// Read-only summary of exactly what the invite will contain.
class InviteReviewSheet extends StatelessWidget {
  /// Creates an [InviteReviewSheet] for [round].
  const InviteReviewSheet({
    super.key,
    required this.round,
    this.targetCalendar,
  });

  /// The round about to be sent.
  final GolfRound round;

  /// The calendar the event will be written to, when known.
  ///
  /// Used only to warn when that calendar cannot deliver invitations — see
  /// [CalendarService.canDeliverInvitations].
  final Calendar? targetCalendar;

  DateTime get _start => DateTime(
        round.date.year,
        round.date.month,
        round.date.day,
        round.teeTime.hour,
        round.teeTime.minute,
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final withEmail = round.players.where((p) => p.email != null).length;
    final missing = round.players.length - withEmail;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Want to change anything?',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Once this goes out, everyone on it is notified. Check the time '
              'especially.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),

            // Time first and largest: it is the detail that has actually
            // gone out wrong, and the one nobody thinks to check.
            _Row(
              icon: Icons.schedule_rounded,
              label: 'Tee time',
              value: DateFormat('EEEE d MMMM  ·  HH:mm').format(_start),
              emphasise: true,
            ),
            _Row(
              icon: Icons.golf_course_rounded,
              label: 'Course',
              value: round.courseName,
            ),
            _Row(
              icon: Icons.group_rounded,
              label: 'Players',
              value: round.players.map((p) => p.name).join(', '),
            ),
            if (missing > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 15, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$missing player${missing == 1 ? '' : 's'} without an '
                        'email won\'t receive this.',
                        style:
                            text.bodySmall?.copyWith(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            // A local or subscribed calendar accepts attendees, sends
            // nothing, and can never report an RSVP — while looking exactly
            // like a working calendar. Reported in the field: a player
            // declined twice and the app saw neither decline. Warning here
            // is the only place it can be caught before it matters.
            if (targetCalendar != null &&
                !CalendarService.canDeliverInvitations(targetCalendar))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 15, color: AppColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This calendar can\'t send invitations, so nobody '
                        'will receive one and replies won\'t show up here. '
                        'Pick a Google or work calendar in Settings.',
                        style: text.bodySmall?.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(InviteReviewChoice.edit),
                    child: const Text('Change something'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: AppRadius.buttonBorder,
                    ),
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(InviteReviewChoice.send),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.buttonBorder,
                        ),
                      ),
                      child: const Text(
                        'Send invite',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18,
              color: emphasise ? AppColors.primary : AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    letterSpacing: 0.6,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
                    fontSize: emphasise ? 17 : 14,
                    color: AppColors.textDark,
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
