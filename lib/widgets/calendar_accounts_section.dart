/// Shared calendar-accounts list (spec C2/C5).
///
/// Lists device calendars grouped by account (Apple iCloud, Google, Outlook/
/// Exchange, other CalDAV) with a link/unlink toggle for each, plus a
/// "Set as primary" pill for linked, non-primary calendars. Used by both the
/// onboarding Calendar Accounts step and the Settings "Calendars & Accounts"
/// card so the two never drift.
library;

import 'package:device_calendar/device_calendar.dart' show Calendar;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/calendar_service.dart';
import '../theme/app_theme.dart';

/// Grouped, linkable list of device calendars bound to [AppState].
class CalendarAccountsSection extends StatefulWidget {
  /// Creates a [CalendarAccountsSection].
  const CalendarAccountsSection({super.key});

  @override
  State<CalendarAccountsSection> createState() =>
      _CalendarAccountsSectionState();
}

class _CalendarAccountsSectionState extends State<CalendarAccountsSection> {
  late final Future<Map<String, List<Calendar>>> _grouped =
      CalendarService().getAvailableCalendarsGrouped();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<Calendar>>>(
      future: _grouped,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final grouped = snapshot.data ?? const {};
        if (grouped.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.offWhite,
              borderRadius: AppRadius.cardBorder,
              border: Border.all(color: AppColors.grey),
            ),
            child: Text(
              'No calendar accounts found on this device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
            ),
          );
        }
        return Consumer<AppState>(
          builder: (context, state, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in grouped.entries) ...[
                _CalendarAccountGroupLabel(accountKey: entry.key),
                const SizedBox(height: 8),
                for (final calendar in entry.value)
                  if (calendar.id != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CalendarAccountRow(
                        name: calendar.name ?? 'Unnamed Calendar',
                        isLinked: state.linkedCalendarIds.contains(calendar.id) ||
                            state.primaryCalendarId == calendar.id,
                        isPrimary: state.primaryCalendarId == calendar.id,
                        onToggleLink: () {
                          if (state.primaryCalendarId == calendar.id) {
                            state.setPrimaryCalendarId(null);
                          } else {
                            state.toggleLinkedCalendar(calendar.id!);
                          }
                        },
                        onSetPrimary: () {
                          state.setPrimaryCalendarId(calendar.id);
                        },
                      ),
                    ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CalendarAccountGroupLabel extends StatelessWidget {
  const _CalendarAccountGroupLabel({required this.accountKey});
  final String accountKey;

  IconData get _icon {
    final k = accountKey.toLowerCase();
    if (k.contains('icloud') || k.contains('apple')) {
      return Icons.cloud_outlined;
    }
    if (k.contains('google')) return Icons.mail_outline_rounded;
    if (k.contains('outlook') || k.contains('exchange')) {
      return Icons.business_center_outlined;
    }
    return Icons.calendar_today_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text(
          accountKey,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: AppColors.textMuted,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _CalendarAccountRow extends StatelessWidget {
  const _CalendarAccountRow({
    required this.name,
    required this.isLinked,
    required this.isPrimary,
    required this.onToggleLink,
    required this.onSetPrimary,
  });

  final String name;
  final bool isLinked;
  final bool isPrimary;
  final VoidCallback onToggleLink;
  final VoidCallback onSetPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(
          color: isPrimary ? AppColors.primary : AppColors.grey,
          width: isPrimary ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: AppColors.textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isLinked && !isPrimary)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: onSetPrimary,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPale,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    'Set as primary',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          if (isPrimary)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'Primary',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          Switch(
            value: isLinked,
            onChanged: (_) => onToggleLink(),
          ),
        ],
      ),
    );
  }
}
