/// Inline calendar chooser, shown at the moment a calendar is actually needed.
///
/// Selecting a calendar used to be possible only in Settings. If nothing was
/// selected, sending an invite failed with an error telling the user to go
/// there — and reaching Settings from the scan review screen meant abandoning
/// the booking they had just scanned. So the only route to fixing the problem
/// destroyed the work that surfaced it. This sheet removes that trip
/// entirely: the choice is offered where the need arises.
library;

import 'package:device_calendar/device_calendar.dart' show Calendar;
import 'package:flutter/material.dart';

import '../services/calendar_service.dart';
import '../theme/app_theme.dart';

/// Shows the picker and resolves to the chosen calendar id, or null if
/// dismissed without choosing.
Future<String?> showCalendarPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const CalendarPickerSheet(),
  );
}

/// Lists the device's writable calendars for selection. Exposed for testing.
class CalendarPickerSheet extends StatefulWidget {
  /// Creates a [CalendarPickerSheet].
  const CalendarPickerSheet({super.key, this.calendarsOverride});

  /// Injectable for tests; production reads from the device.
  final List<Calendar>? calendarsOverride;

  @override
  State<CalendarPickerSheet> createState() => _CalendarPickerSheetState();
}

class _CalendarPickerSheetState extends State<CalendarPickerSheet> {
  List<Calendar>? _all;

  @override
  void initState() {
    super.initState();
    final o = widget.calendarsOverride;
    if (o != null) {
      _all = o;
    } else {
      CalendarService().getAvailableCalendars().then((c) {
        if (mounted) setState(() => _all = c);
      }).catchError((_) {
        if (mounted) setState(() => _all = const <Calendar>[]);
      });
    }
  }

  /// Every calendar with an id, most-likely-writable first.
  ///
  /// This used to hide anything device_calendar flagged read-only. On a real
  /// device that flag came back true for EVERY calendar, so the list was
  /// empty and the user was told their phone accepts no new events — which
  /// was false, and not a conclusion this app is entitled to draw. Show them
  /// all; if a write genuinely fails, report the real error rather than
  /// hiding the option in advance.
  List<Calendar> get _selectable {
    // Do NOT filter on a non-null id here. If the platform returns
    // calendars without ids, hiding them leaves a blank sheet and no clue;
    // showing them at least names what the phone reported.
    final all = (_all ?? const <Calendar>[]).toList();
    all.sort((a, b) => ((a.isReadOnly == true) ? 1 : 0)
        .compareTo((b.isReadOnly == true) ? 1 : 0));
    return all;
  }

  String _label(Calendar c) {
    final name = (c.name ?? '').trim();
    return name.isEmpty ? 'Unnamed calendar' : name;
  }

  String _detail(Calendar c) {
    final parts = <String>[
      if (c.accountName?.trim().isNotEmpty == true) c.accountName!.trim(),
      if (c.accountType?.trim().isNotEmpty == true) c.accountType!.trim(),
    ];
    // With many look-alike rows the user needs something to tell them apart,
    // even when the OS reports no account information at all.
    return parts.isEmpty ? 'Calendar ${c.id}' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final loading = _all == null;
    final selectable = _selectable;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('Where should tee times land?',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Pick the calendar to add this round to. You can change it later '
              'in Settings.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          else if (selectable.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Text(
                'No calendars found on this device.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: selectable.length,
                itemBuilder: (context, i) {
                  final c = selectable[i];
                  return ListTile(
                    leading: const Icon(Icons.calendar_today_outlined,
                        color: AppColors.primary),
                    title: Text(_label(c)),
                    subtitle: Text(_detail(c), overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context).pop(c.id),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
