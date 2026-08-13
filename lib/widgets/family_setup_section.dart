/// Shared family-setup component (spec A4).
///
/// Used both during onboarding ([OnboardingScreen]) and in [SettingsScreen].
/// Lets the user add up to [FamilySetupSection.maxMembers] friends/family
/// (name + email) who get informed about tee times, with device-contact
/// autocomplete as they type a name.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../services/contacts_service.dart';
import '../theme/app_theme.dart';

/// A list of [FamilyMember]s with an inline add form and autocomplete.
class FamilySetupSection extends StatefulWidget {
  /// Creates a [FamilySetupSection].
  const FamilySetupSection({
    super.key,
    required this.entries,
    required this.onAdd,
    required this.onRemove,
  });

  /// The current family members to display.
  final List<FamilyMember> entries;

  /// Called with the trimmed name/email when the user adds a member.
  final void Function(String name, String email) onAdd;

  /// Called with the index to remove.
  final void Function(int index) onRemove;

  /// Maximum number of family members allowed.
  static const int maxMembers = 5;

  @override
  State<FamilySetupSection> createState() => _FamilySetupSectionState();
}

class _FamilySetupSectionState extends State<FamilySetupSection> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameFocus = FocusNode();
  List<ContactSuggestion> _suggestions = [];

  Timer? _debounce;
  // Bumped on every keystroke so a slow, stale search response can't
  // overwrite a newer one (results arriving out of order).
  int _searchGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    _debounce?.cancel();
    if (value.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    // Debounce (300ms) so device-contact queries only fire once the user
    // pauses typing, rather than on every keystroke.
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String value) async {
    final generation = ++_searchGeneration;
    try {
      final results = await ContactsService.instance.searchByName(
        value,
        exclude: widget.entries.map((e) => e.name).toList(),
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _suggestions = results.take(4).toList());
    } catch (e) {
      // Contacts permission can be denied/restricted mid-session (device
      // policy, user revokes it in Settings) — fail quietly rather than
      // freezing the field or throwing past the widget tree.
      if (mounted && generation == _searchGeneration) {
        setState(() => _suggestions = []);
      }
    }
  }

  void _selectSuggestion(ContactSuggestion s) {
    _nameController.text = s.name;
    _emailController.text = s.email ?? '';
    setState(() => _suggestions = []);
  }

  void _addEntry() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || email.isEmpty || !email.contains('@')) return;
    if (widget.entries.length >= FamilySetupSection.maxMembers) return;
    widget.onAdd(name, email);
    _nameController.clear();
    _emailController.clear();
    setState(() => _suggestions = []);
  }

  @override
  Widget build(BuildContext context) {
    final atCap = widget.entries.length >= FamilySetupSection.maxMembers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Existing members ──────────────────────────────────────
        if (widget.entries.isNotEmpty) ...[
          Text(
            '${widget.entries.length} of ${FamilySetupSection.maxMembers} added',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 10),
          ...widget.entries.asMap().entries.map((e) => _FamilyMemberTile(
                member: e.value,
                onRemove: () => widget.onRemove(e.key),
              )),
          const SizedBox(height: 16),
        ],

        // ── Add form (hidden at cap) ───────────────────────────────
        if (!atCap) ...[
          // Name field with autocomplete
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Start typing a name…',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: _onNameChanged,
          ),

          // Suggestion dropdown
          if (_suggestions.isNotEmpty)
            Material(
              elevation: 4,
              borderRadius: AppRadius.cardBorder,
              child: Column(
                children: _suggestions.map((s) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primaryPale,
                    child: Text(
                      s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  title: Text(s.name,
                      style: Theme.of(context).textTheme.bodyMedium),
                  subtitle: s.email != null
                      ? Text(s.email!,
                          style: Theme.of(context).textTheme.bodySmall)
                      : null,
                  onTap: () => _selectSuggestion(s),
                )).toList(),
              ),
            ),

          const SizedBox(height: 10),

          // Email field
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'Their email address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
          ),

          const SizedBox(height: 12),

          // Add button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _addEntry,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryPale,
              borderRadius: AppRadius.cardBorder,
            ),
            child: Text(
              'You\'ve reached the 5 family member limit.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

class _FamilyMemberTile extends StatelessWidget {
  const _FamilyMemberTile({required this.member, required this.onRemove});
  final FamilyMember member;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.grey),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryPale,
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                Text(member.email,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textMuted,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
