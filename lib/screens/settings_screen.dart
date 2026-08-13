import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_state.dart';
import '../services/calendar_service.dart';
import '../services/contacts_service.dart';
import '../services/purchase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/family_setup_section.dart';

/// Settings screen with grouped sections for calendar, notifications,
/// contacts, purchase, and about information.
///
/// Features TAG branding footer "Teed Up by The Artesian Group®".
class SettingsScreen extends StatelessWidget {
  /// Creates a [SettingsScreen].
  const SettingsScreen({super.key});

  /// Route name for navigation.
  static const String routeName = '/settings';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
            children: [
              // ── CALENDAR ─────────────────────────────────────
              const _SectionLabel(label: 'CALENDAR'),
              _SettingsTile(
                icon: Icons.calendar_month_rounded,
                title: 'Primary Calendar',
                subtitle: state.primaryCalendarId ?? 'Not set',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
                onTap: () => _showCalendarPicker(context, state),
              ),
              _SettingsTile(
                icon: Icons.link_rounded,
                title: 'Linked Calendars',
                subtitle: state.linkedCalendarIds.isEmpty
                    ? 'None — scanning primary calendar only'
                    : '${state.linkedCalendarIds.length} linked for scanning & alerts',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
                onTap: () => _showLinkedCalendarsPicker(context, state),
              ),
              const _SettingsDivider(),

              // ── NOTIFICATIONS ────────────────────────────────
              const _SectionLabel(label: 'NOTIFICATIONS'),
              _SettingsTile(
                icon: Icons.notifications_rounded,
                title: 'Decline Alerts',
                subtitle: 'Notify when a player declines',
                trailing: Switch(
                  value: state.declineAlertsEnabled,
                  onChanged: (v) => state.setDeclineAlerts(v),
                ),
              ),
              const _SettingsDivider(),

              // ── CONTACTS ─────────────────────────────────────
              const _SectionLabel(label: 'CONTACTS'),
              _SettingsTile(
                icon: Icons.people_rounded,
                title: 'View Cached Contacts',
                subtitle: 'See synced contacts used for matching',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
                onTap: () => _showCachedContacts(context),
              ),
              _SettingsTile(
                icon: Icons.delete_outline_rounded,
                title: 'Clear Contact Cache',
                subtitle: 'Remove all cached contact data',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
                onTap: () => _confirmClearCache(context),
              ),
              const _SettingsDivider(),

              // ── FRIENDS & FAMILY (A12 — up to 5 members) ─────
              const _SectionLabel(label: '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}  FRIENDS & FAMILY'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FamilySetupSection(
                  entries: state.familyMembers,
                  onAdd: (name, email) =>
                      state.addFamilyMember(name: name, email: email),
                  onRemove: state.removeFamilyMember,
                ),
              ),
              if (state.familyMembers.isNotEmpty)
                _SettingsTile(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Always notify all members',
                  subtitle: 'Auto-select on every scan',
                  trailing: Switch(
                    value: state.familyAlwaysNotify,
                    onChanged: (v) => state.setFamilyAlwaysNotify(v),
                  ),
                ),
              const _SettingsDivider(),

              // ── PURCHASE ─────────────────────────────────────
              const _SectionLabel(label: 'PURCHASE'),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _restorePurchase(context),
                    icon: const Icon(Icons.restore_rounded, size: 20),
                    label: const Text('Restore Purchase'),
                  ),
                ),
              ),
              const _SettingsDivider(),

              // ── ABOUT ────────────────────────────────────────
              const _SectionLabel(label: 'ABOUT'),
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'Version',
                subtitle: '1.0.0 (1)',
              ),
              _SettingsTile(
                icon: Icons.shield_outlined,
                title: 'Privacy Policy',
                trailing: const Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                onTap: () => _launchUrl('https://teedup.golf/privacy'),
              ),
              _SettingsTile(
                icon: Icons.email_outlined,
                title: 'Support',
                subtitle: 'support@teedup.golf',
                onTap: () => _launchUrl('mailto:support@teedup.golf'),
              ),

              // ── TAG Footer ───────────────────────────────────
              const SizedBox(height: 40),
              const _TagFooter(),
            ],
          );
        },
      ),
    );
  }

  void _showCalendarPicker(BuildContext context, AppState state) async {
    // Fetch real writable calendars from the device.
    final calendarService = CalendarService();
    final calendars = await calendarService.getAvailableCalendars();

    // Filter to writable calendars only.
    final writable = calendars
        .where((c) => !c.isReadOnly! && c.id != null)
        .toList();

    if (!context.mounted) return;

    if (writable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No writable calendars found on this device.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Calendar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < writable.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _CalendarOption(
                name: writable[i].name ?? 'Unnamed Calendar',
                color: Color(writable[i].color ?? 0xFF1976D2),
                isSelected: state.defaultCalendarId == writable[i].id,
                onTap: () {
                  state.setDefaultCalendar(writable[i].id);
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Multi-select picker for calendars to scan for RSVP changes / decline
  /// alerts, in addition to the Primary Calendar (spec: multi-calendar
  /// account linking). Grouped by account (Google/iCloud/Outlook/etc.).
  void _showLinkedCalendarsPicker(BuildContext context, AppState state) async {
    final calendarService = CalendarService();
    final grouped = await calendarService.getAvailableCalendarsGrouped();

    if (!context.mounted) return;

    if (grouped.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No calendars found on this device.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Linked Calendars'),
        content: SizedBox(
          width: double.maxFinite,
          child: Consumer<AppState>(
            builder: (context, liveState, _) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in grouped.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: AppColors.textMuted,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    for (final calendar in entry.value)
                      if (calendar.id != null)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(calendar.name ?? 'Unnamed Calendar'),
                          value: liveState.linkedCalendarIds.contains(calendar.id) ||
                              liveState.primaryCalendarId == calendar.id,
                          // The primary calendar is always implicitly
                          // monitored (see AppState.calendarsToMonitor) —
                          // show it checked and non-interactive here.
                          onChanged: liveState.primaryCalendarId == calendar.id
                              ? null
                              : (_) => liveState.toggleLinkedCalendar(calendar.id!),
                        ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showCachedContacts(BuildContext context) async {
    final contactsService = ContactsService();
    final cached = await contactsService.getCachedEmails();

    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cached Contacts'),
        content: cached.isEmpty
            ? const Text(
                'No cached contacts yet. Contacts will be cached '
                'after your first scan.',
              )
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: cached.length,
                  itemBuilder: (_, i) {
                    final name = cached.keys.elementAt(i);
                    final email = cached[name]!;
                    return ListTile(
                      dense: true,
                      title: Text(name),
                      subtitle: Text(email),
                      leading: const Icon(Icons.person_rounded, size: 20),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _confirmClearCache(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Contact Cache?'),
        content: const Text(
          'This will remove all cached contact data. '
          'Contacts will be re-synced on your next scan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await ContactsService().clearCache();
              if (!context.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Contact cache cleared'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _restorePurchase(BuildContext context) async {
    final state = context.read<AppState>();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checking for existing purchases…'),
        backgroundColor: AppColors.primary,
      ),
    );

    try {
      final purchaseService = PurchaseService(appState: state);
      await purchaseService.initialize();
      await purchaseService.restorePurchases();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _confirmClearFamily(BuildContext context, AppState state) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Family Contact?'),
        content: const Text(
          'This will remove the configured family contact. '
          'They will no longer receive calendar invites.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await state.clearFamilyContact();
              if (!context.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Family contact cleared'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

/// Section label in uppercase muted text.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: AppColors.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// A single settings row with icon, title, subtitle, and trailing widget.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primaryPale,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
          fontSize: 15,
          color: AppColors.textDark,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }
}

/// Thin divider between settings sections.
class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Divider(height: 1),
    );
  }
}

/// Calendar option row in the picker dialog.
class _CalendarOption extends StatelessWidget {
  const _CalendarOption({
    required this.name,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryPale : AppColors.greyLight,
          borderRadius: AppRadius.buttonBorder,
          border: isSelected
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 14,
                  color: AppColors.textDark,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_rounded, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

/// TAG branded footer at the bottom of the settings screen.
class _TagFooter extends StatelessWidget {
  const _TagFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Divider
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 60),
          child: Divider(),
        ),
        const SizedBox(height: 16),

        // TAG wordmark
        const Text(
          'All Teed Up',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'by TAG',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
            fontSize: 13,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),

        // Tagline
        Text(
          '"It\'s In The Calendar"',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: AppColors.textMuted.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
