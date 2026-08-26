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
import 'golf_ball_logo.dart';

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
  bool _autoLinkAttempted = false;

  /// Defaults every discovered calendar to linked (opt-out, not opt-in) the
  /// first time this screen sees them with nothing configured yet — a fresh
  /// install previously started with everything toggled OFF, so unless the
  /// user noticed and manually flipped every switch, nothing ever actually
  /// synced. Runs once; never overrides a choice the user already made.
  void _autoLinkIfNeeded(Map<String, List<Calendar>> grouped, AppState state) {
    if (_autoLinkAttempted) return;
    // Only a set PRIMARY means there is somewhere to write. Bailing out
    // because linked calendars exist left anyone with links but no primary
    // permanently stuck: auto-selection never ran, and every write failed
    // with "no calendar selected".
    if (state.primaryCalendarId != null) {
      _autoLinkAttempted = true;
      return;
    }
    final all =
        grouped.values.expand((c) => c).where((c) => c.id != null).toList();
    if (all.isEmpty) return;
    _autoLinkAttempted = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final writable = all.where((c) => c.isReadOnly != true).toList();
      final primary = writable.isNotEmpty ? writable.first : all.first;
      state.setPrimaryCalendarId(primary.id);
      for (final c in all) {
        if (c.id != primary.id) state.toggleLinkedCalendar(c.id!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<Calendar>>>(
      future: _grouped,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Enumerating every calendar on the device takes a noticeable
          // moment on a phone with many accounts, and this lands straight
          // after the permission step — so the app appeared to freeze
          // between screens. Say what is happening, with the app's own ball.
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: GolfBallLogo(
                      size: 44,
                      animate: true,
                      showTee: false,
                      showGlow: false,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Finding your calendars…',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
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
          builder: (context, state, _) {
            _autoLinkIfNeeded(grouped, state);
            // "Other" only means the device didn't report an accountName
            // for a calendar — NOT that no accounts exist. An earlier
            // version asserted the latter ("no linked account… add one in
            // Settings"), which is a diagnosis this code cannot actually
            // make: users with several Google accounts signed in still hit
            // this path, and were told to go add an account they already
            // had. Say what was found and let the user judge.
            final unnamedOnly =
                grouped.length == 1 && grouped.containsKey('Other');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    unnamedOnly
                        ? 'Tap a calendar to choose where tee times land. Your '
                            'phone didn\'t say which account each one belongs '
                            'to, so they\'re listed together — the ones that '
                            'accept new events are first.'
                        : 'Tap a calendar to choose where tee times land.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
                ),
                for (final entry in grouped.entries) ...[
                  _CalendarAccountGroupLabel(accountKey: entry.key),
                  const SizedBox(height: 8),
                  // Writable first. With 21 look-alike calendars, the ones
                  // that can actually receive a tee time should not be buried
                  // among holiday and birthday calendars.
                  for (final calendar in ([...entry.value]..sort((a, b) =>
                      ((a.isReadOnly == true) ? 1 : 0)
                          .compareTo((b.isReadOnly == true) ? 1 : 0))))
                    if (calendar.id != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CalendarAccountRow(
                          name: calendar.name ?? 'Unnamed Calendar',
                          // Surface what the OS actually reported. Without
                          // this the list can show several indistinguishable
                          // rows (or one confusingly labelled "Other") with
                          // no way for the user — or a bug report — to tell
                          // which underlying account each row really is.
                          detail: [
                            if (calendar.accountName?.trim().isNotEmpty == true)
                              calendar.accountName!.trim(),
                            if (calendar.accountType?.trim().isNotEmpty == true)
                              calendar.accountType!.trim(),
                            if (calendar.isReadOnly == true)
                              'read-only — can\'t receive tee times',
                          ].join(' · '),
                          fallbackDetail: 'Calendar ${calendar.id}',
                          isReadOnly: calendar.isReadOnly == true,
                          isLinked:
                              state.linkedCalendarIds.contains(calendar.id) ||
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
            );
          },
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
    this.detail = '',
    this.fallbackDetail = '',
    this.isReadOnly = false,
    required this.isLinked,
    required this.isPrimary,
    required this.onToggleLink,
    required this.onSetPrimary,
  });

  final String name;

  /// Raw account info as reported by the OS (account name, type, read-only).
  final String detail;

  /// Shown when the OS reported no account info at all, so that a list of
  /// otherwise identical rows still has something to distinguish them.
  final String fallbackDetail;

  /// A read-only calendar cannot receive tee times — worth showing, since
  /// selecting one would fail at write time with no obvious reason.
  final bool isReadOnly;

  final bool isLinked;
  final bool isPrimary;
  final VoidCallback onToggleLink;
  final VoidCallback onSetPrimary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // The row itself selects. The instruction on screen says to pick a
      // calendar, but the only working target used to be the Switch on the
      // right — tapping the name, or the "Other" group heading above it,
      // did nothing and read as a frozen screen.
      // Always tappable. A read-only row that simply ignores taps is
      // indistinguishable from a frozen screen — and on Android most Google
      // sub-calendars (holidays, birthdays, subscribed) report read-only, so
      // that could silently disable the entire list.
      onTap: onSetPrimary,
      borderRadius: AppRadius.cardBorder,
      child: Container(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (detail.isNotEmpty || fallbackDetail.isNotEmpty)
                    Text(
                      detail.isNotEmpty ? detail : fallbackDetail,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color:
                            isReadOnly ? AppColors.error : AppColors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
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
              onChanged: isReadOnly ? null : (_) => onToggleLink(),
            ),
          ],
        ),
      ),
    );
  }
}
