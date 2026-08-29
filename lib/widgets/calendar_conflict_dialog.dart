/// Branded "potential calendar conflict" alert.
///
/// Shown when a tee time about to be saved overlaps something already in the
/// user's calendar — from any source, not just this app. Deliberately a
/// warning rather than an error: overlapping entries are often legitimate
/// (a club's own invite alongside your booking), so the user decides. This
/// never silently duplicates and never silently merges.
///
/// Lives in its own file rather than inside the scan screen so it can be
/// widget-tested for overflow at real device sizes — a dialog that renders
/// fine on a large phone and overflows on a small one is exactly the kind of
/// defect that otherwise ships unnoticed.
library;

import 'package:device_calendar/device_calendar.dart' show Event;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../services/calendar_service.dart';

/// Shows the conflict alert. Resolves true if the user chose "Add anyway".
Future<bool?> showCalendarConflictDialog(
  BuildContext context,
  List<Event> conflicts,
) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => CalendarConflictDialog(conflicts: conflicts),
  );
}

/// The alert itself, separated so tests can pump it directly.
class CalendarConflictDialog extends StatelessWidget {
  /// Creates a [CalendarConflictDialog] for [conflicts].
  const CalendarConflictDialog({super.key, required this.conflicts});

  /// Existing calendar entries overlapping the tee time, nearest first.
  final List<Event> conflicts;

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final text = Theme.of(ctx).textTheme;
    final fmt = DateFormat('EEE d MMM · HH:mm');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBorder),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppRadius.card),
                topRight: Radius.circular(AppRadius.card),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.event_repeat_rounded,
                      size: 20, color: AppColors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Potential calendar conflict',
                        style: text.titleMedium?.copyWith(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        conflicts.length == 1
                            ? 'Something else is already booked around '
                                'this tee time.'
                            : '${conflicts.length} other entries are '
                                'already around this tee time.',
                        style:
                            text.bodySmall?.copyWith(color: AppColors.textBody),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Conflicting entries ───────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in conflicts.take(4))
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.offWhite,
                        borderRadius: AppRadius.buttonBorder,
                        border: Border.all(color: AppColors.grey),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 15, color: AppColors.textMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.title?.trim().isNotEmpty == true
                                      ? e.title!.trim()
                                      : 'Untitled event',
                                  style: text.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (e.start != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    // Via localWallClock: e.start is a
                                    // plugin TZDateTime in the event's own
                                    // zone, so formatting it directly shows
                                    // the wrong hour.
                                    fmt.format(
                                      CalendarService.localWallClock(e.start!),
                                    ),
                                    style: text.bodySmall
                                        ?.copyWith(color: AppColors.textMuted),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (conflicts.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '+ ${conflicts.length - 4} more',
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  Text(
                    'Adding this round creates a separate entry — it '
                    'won’t replace what’s already there.',
                    style: text.bodySmall?.copyWith(color: AppColors.textBody),
                  ),
                ],
              ),
            ),
          ),

          // ── Actions ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: AppRadius.buttonBorder,
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.buttonBorder),
                      ),
                      child: const Text('Add anyway'),
                    ),
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
