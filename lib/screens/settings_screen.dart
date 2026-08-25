import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/contacts_service.dart';
import '../services/purchase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/calendar_accounts_section.dart';
import '../widgets/family_setup_section.dart';

/// Settings screen — 5 grouped cards (spec C5): Calendars & Accounts,
/// Notifications & Reminders, Friends & Family, Contacts & Privacy, and
/// App License & About.
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              _SettingsCard(
                emoji: '📅',
                title: 'Calendars & Accounts',
                child: const CalendarAccountsSection(),
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                emoji: '🔔',
                title: 'Notifications & Reminders',
                child: Column(
                  children: [
                    _ToggleRow(
                      title: 'Decline alerts',
                      subtitle: 'Notify when a player declines',
                      value: state.declineAlertsEnabled,
                      onChanged: state.setDeclineAlerts,
                    ),
                    const Divider(height: 20),
                    _ToggleRow(
                      title: '12 hours before',
                      subtitle: 'Reminder added to the calendar invite',
                      value: state.reminder12hEnabled,
                      onChanged: state.setReminder12h,
                    ),
                    const Divider(height: 20),
                    _ToggleRow(
                      title: '1 hour before',
                      subtitle: 'Reminder added to the calendar invite',
                      value: state.reminder1hEnabled,
                      onChanged: state.setReminder1h,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                emoji: '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}',
                title: 'Friends & Family',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FamilySetupSection(
                      entries: state.familyMembers,
                      onAdd: (name, email) =>
                          state.addFamilyMember(name: name, email: email),
                      onRemove: state.removeFamilyMember,
                    ),
                    if (state.familyMembers.isNotEmpty) ...[
                      const Divider(height: 28),
                      _ToggleRow(
                        title: 'Always notify all members',
                        subtitle: 'Auto-select on every scan',
                        value: state.familyAlwaysNotify,
                        onChanged: state.setFamilyAlwaysNotify,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                emoji: '\u{1F4C7}',
                title: 'Contacts & Privacy',
                child: _ContactsPrivacySection(),
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                emoji: '\u{1F4B3}',
                title: 'App License & About',
                child: _LicenseAboutSection(isPurchased: state.isPurchased),
              ),
              const SizedBox(height: 24),
              const _AppFooter(),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// Card shell
// =============================================================================

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.emoji,
    required this.title,
    required this.child,
  });

  final String emoji;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

// =============================================================================
// Contacts & Privacy card
// =============================================================================

class _ContactsPrivacySection extends StatefulWidget {
  @override
  State<_ContactsPrivacySection> createState() =>
      _ContactsPrivacySectionState();
}

class _ContactsPrivacySectionState extends State<_ContactsPrivacySection> {
  late Future<int> _cachedCount = _loadCount();

  Future<int> _loadCount() async {
    final cached = await ContactsService().getCachedEmails();
    return cached.length;
  }

  Future<void> _resync() async {
    await ContactsService().clearCache();
    setState(() => _cachedCount = _loadCount());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Contacts will be re-synced on your next scan.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<int>(
          future: _cachedCount,
          builder: (context, snapshot) {
            final count = snapshot.data;
            return Row(
              children: [
                const Icon(Icons.people_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    count == null
                        ? 'Loading cached contacts…'
                        : '$count contact${count == 1 ? '' : 's'} cached for matching',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _resync,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Re-sync contacts'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Contacts never leave your device — matching happens entirely '
          'on-device to find email addresses for your playing partners.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
                height: 1.5,
              ),
        ),
      ],
    );
  }
}

// =============================================================================
// App License & About card
// =============================================================================

class _LicenseAboutSection extends StatelessWidget {
  const _LicenseAboutSection({required this.isPurchased});
  final bool isPurchased;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isPurchased
                ? AppColors.success.withValues(alpha: 0.12)
                : AppColors.primaryPale,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            isPurchased ? 'Purchased' : 'Free',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: isPurchased ? AppColors.success : AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => _restorePurchase(context),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Restore purchases'),
          ),
        ),
        const SizedBox(height: 14),
        // Read from the actual bundle rather than a literal. This was
        // hardcoded to '1.1.0' and stayed there across every release, so the
        // About screen reported a version the user was not running — which
        // made it impossible for either side to tell which build a bug
        // report referred to.
        const _VersionRow(),
        // Both destinations below are live and verified. The earlier
        // versions of these rows pointed at teedup.golf/privacy and
        // support@teedup.golf, neither of which existed — a dead support
        // address is worse than none, because a user who writes to it
        // believes they have asked for help.
        _AboutRow(
          icon: Icons.shield_outlined,
          title: 'Privacy Policy',
          onTap: () => _launchUrl(_privacyUrl),
        ),
        _AboutRow(
          icon: Icons.help_outline_rounded,
          title: 'Help & Support',
          onTap: () => _launchUrl(_supportUrl),
        ),
        _AboutRow(
          icon: Icons.email_outlined,
          title: 'Email us',
          subtitle: _supportEmail,
          onTap: () => _launchUrl('mailto:$_supportEmail'),
        ),
      ],
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
}

/// Live support and privacy destinations. Verified reachable — see the
/// commit that introduced them. Keep these as the single source of truth;
/// the same URLs are filed in the iOS App Store Connect metadata.
const String _privacyUrl =
    'https://alasdair-svg.github.io/teed-up/privacy.html';
const String _supportUrl =
    'https://alasdair-svg.github.io/teed-up/support.html';
const String _supportEmail = 'allteedup.support@gmail.com';

Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  /// Tapping opens the destination. Rows without one are informational.
  final VoidCallback? onTap;

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: AppColors.textDark,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Wordmark footer at the bottom of the settings screen.
class _AppFooter extends StatelessWidget {
  const _AppFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 60),
          child: Divider(),
        ),
        const SizedBox(height: 16),
        const Text(
          'All Teed Up',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
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

/// Shows the running app version, read from the platform bundle.
class _VersionRow extends StatefulWidget {
  const _VersionRow();

  @override
  State<_VersionRow> createState() => _VersionRowState();
}

class _VersionRowState extends State<_VersionRow> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => _AboutRow(
        icon: Icons.info_outline_rounded,
        title: 'Version',
        subtitle: _version ?? '—',
      );
}
