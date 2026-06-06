import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';

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
      backgroundColor: AppColors.white,
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
                title: 'Default Calendar',
                subtitle: state.defaultCalendarId ?? 'Not set',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
                onTap: () => _showCalendarPicker(context, state),
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

  void _showCalendarPicker(BuildContext context, AppState state) {
    // TODO: Integrate with device_calendar to list real calendars
    // For now, show a placeholder dialog
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Calendar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CalendarOption(
              name: 'iCloud Calendar',
              color: AppColors.primary,
              isSelected: state.defaultCalendarId == 'icloud',
              onTap: () {
                state.setDefaultCalendar('icloud');
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 8),
            _CalendarOption(
              name: 'Google Calendar',
              color: Colors.blue,
              isSelected: state.defaultCalendarId == 'google',
              onTap: () {
                state.setDefaultCalendar('google');
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 8),
            _CalendarOption(
              name: 'Outlook Calendar',
              color: Colors.teal,
              isSelected: state.defaultCalendarId == 'outlook',
              onTap: () {
                state.setDefaultCalendar('outlook');
                Navigator.of(ctx).pop();
              },
            ),
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

  void _showCachedContacts(BuildContext context) {
    // TODO: Integrate with flutter_contacts and local cache
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cached Contacts'),
        content: const Text(
          'No cached contacts yet. Contacts will be cached '
          'after your first scan.',
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
            onPressed: () {
              // TODO: Clear actual contact cache from SQLite
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

  void _restorePurchase(BuildContext context) {
    // TODO: Integrate with in_app_purchase
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checking for existing purchases…'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
          'Teed Up',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'by The Artesian Group®',
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
          '"Snap your booking. Your group is sorted."',
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
