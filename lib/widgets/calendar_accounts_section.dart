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
import 'calendar_picker_sheet.dart';
import 'golf_ball_logo.dart';

/// Grouped, linkable list of device calendars bound to [AppState].
class CalendarAccountsSection extends StatefulWidget {
  /// Creates a [CalendarAccountsSection].
  const CalendarAccountsSection({super.key, this.groupedOverride});

  /// Injectable calendar list for tests. Production reads from the device.
  ///
  /// This widget previously called [CalendarService] directly with no seam,
  /// which is why a broken tap path could survive several rounds of fixes
  /// without a single test exercising it.
  final Map<String, List<Calendar>>? groupedOverride;

  @override
  State<CalendarAccountsSection> createState() =>
      _CalendarAccountsSectionState();
}

/// Long enough for the onboarding page transition to finish before the
/// calendar read begins.
const Duration _transitionSettleDelay = Duration(milliseconds: 450);

class _CalendarAccountsSectionState extends State<CalendarAccountsSection> {
  Future<Map<String, List<Calendar>>>? _grouped;

  /// Held null until the page transition has settled.
  ///
  /// Reading the device calendar list is slow — noticeably so with many
  /// calendars — and device_calendar does its work on the platform thread.
  /// Starting it while this page is sliding in stalled the PageView
  /// animation part-way, leaving both pages visible side by side: the
  /// "stuck screen" that was reported repeatedly. Deferring past the
  /// transition costs nothing perceptible and keeps the animation smooth.

  @override
  void initState() {
    super.initState();
    if (widget.groupedOverride != null) {
      _grouped = _load();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(_transitionSettleDelay);
      if (!mounted) return;
      setState(() {
        _grouped = _load();
      });
    });
  }

  /// Fetches the calendar list.
  ///
  /// Held in a mutable field, not `late final`, because an empty result must
  /// never be permanent. This previously cached the FIRST result forever —
  /// and if that first call happened before calendar permission was granted
  /// it returned nothing, so the screen said "No calendars found on this
  /// device" for the rest of the session no matter what the user did next.
  Future<Map<String, List<Calendar>>> _load() {
    final o = widget.groupedOverride;
    if (o != null) return Future.value(o);
    return CalendarService().getAvailableCalendarsGrouped();
  }

  /// Re-runs the fetch — used when the first attempt came back empty, which
  /// is the signature of it having run before permission existed.
  void _reload() {
    if (!mounted) return;
    setState(() {
      _grouped = _load();
    });
  }

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
      // Only ever auto-select a calendar that can actually receive an
      // event. Falling back to all.first meant a device whose calendars are
      // all read-only got a write target that could never work, and the
      // failure surfaced much later as an unexplained calendar error.
      // Leaving it unset instead lets the UI say plainly that nothing on
      // this phone accepts new events.
      // Prefer one the OS says is writable, but never refuse to choose:
      // device_calendar reported read-only for every calendar on a real
      // device, and bailing out left the user with no target at all.
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
          return _EmptyCalendars(onRetry: _reload);
        }
        return Consumer<AppState>(
          builder: (context, state, _) {
            _autoLinkIfNeeded(grouped, state);

            final all = grouped.values.expand((c) => c).toList();
            final selectable = all.where((c) => c.id != null).toList();
            final current = state.primaryCalendarId == null
                ? null
                : all.cast<Calendar?>().firstWhere(
                      (c) => c!.id == state.primaryCalendarId,
                      orElse: () => null,
                    );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ONE decision, stated plainly.
                //
                // This replaces a grouped list of every calendar on the
                // device with per-row switches, a "Set as primary" pill and
                // an account heading. With many calendars under a single
                // "Other" heading, that heading read as a collapsed
                // dropdown — users tapped IT rather than the rows beneath,
                // and it is a label, so nothing happened. Reported three
                // times as "you cannot select a calendar".
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius: AppRadius.cardBorder,
                    border: Border.all(
                      color:
                          current == null ? AppColors.warning : AppColors.grey,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        current == null
                            ? Icons.error_outline_rounded
                            : Icons.event_available_rounded,
                        size: 20,
                        color: current == null
                            ? AppColors.warning
                            : AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Tee times land in',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                letterSpacing: 0.6,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              current?.name?.trim().isNotEmpty == true
                                  ? current!.name!.trim()
                                  : (current != null
                                      ? 'Unnamed calendar'
                                      : 'No calendar chosen yet'),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: AppColors.textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        // Never disabled. A disabled button is
                        // indistinguishable from a broken one — this was
                        // reported repeatedly as "clicking does nothing".
                        onPressed: () async {
                          if (selectable.isEmpty) {
                            await CalendarService().ensureCalendarPermission();
                            _reload();
                            return;
                          }
                          final picked = await showCalendarPickerSheet(context);
                          if (picked != null) {
                            state.setPrimaryCalendarId(picked);
                          }
                        },
                        child: Text(current == null ? 'Choose' : 'Change'),
                      ),
                    ],
                  ),
                ),
                if (selectable.isEmpty) const _CalendarDiagnostics(),
              ],
            );
          },
        );
      },
    );
  }
}

/// Shown when the device returns no calendars at all.
///
/// Always offers a retry: the commonest cause is the list having been
/// fetched before calendar permission was granted, which is recoverable —
/// a dead-end message is not.
class _EmptyCalendars extends StatelessWidget {
  const _EmptyCalendars({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Couldn't read your calendars yet. If you've just granted "
            'calendar access, tap Retry.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onRetry, child: const Text('Retry')),
          ),
        ],
      ),
    );
  }
}

/// Reports exactly what the device said about calendar access.
///
/// "No calendars found" is a symptom shared by several unrelated causes, and
/// guessing between them from a screenshot cost days. This states the OS
/// permission status, the plugin's own gate, and the raw number of
/// calendars returned, so the next report is evidence.
class _CalendarDiagnostics extends StatefulWidget {
  const _CalendarDiagnostics();

  @override
  State<_CalendarDiagnostics> createState() => _CalendarDiagnosticsState();
}

class _CalendarDiagnosticsState extends State<_CalendarDiagnostics> {
  String? _report;

  @override
  void initState() {
    super.initState();
    CalendarService().diagnoseCalendarAccess().then((r) {
      if (mounted) setState(() => _report = r);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textMuted,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Couldn't read any calendars from this phone. Tap Choose to ask "
            'for calendar access again.',
            style: small,
          ),
          if (_report != null) ...[
            const SizedBox(height: 6),
            Text(
              _report!,
              style: small?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
