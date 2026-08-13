/// Shared family-setup component (spec A4, restyled per spec C3).
///
/// Used both during onboarding ([OnboardingScreen]) and in [SettingsScreen].
/// Shows the current friends/family list with a dashed "+ Add family member"
/// button that opens a bottom-sheet modal contact picker (search + device-
/// contact matches + manual-email fallback), capped at
/// [FamilySetupSection.maxMembers].
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../services/contacts_service.dart';
import '../theme/app_theme.dart';

/// A list of [FamilyMember]s with a modal add-picker.
class FamilySetupSection extends StatelessWidget {
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

  void _openModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FamilyPickerModal(
        excludeNames: entries.map((e) => e.name).toList(),
        onAdd: onAdd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final atCap = entries.length >= maxMembers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Existing members ──────────────────────────────────────
        if (entries.isNotEmpty) ...[
          Text(
            '${entries.length} of $maxMembers added',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 10),
          ...entries.asMap().entries.map((e) => _FamilyMemberTile(
                member: e.value,
                onRemove: () => onRemove(e.key),
              )),
          const SizedBox(height: 12),
        ],

        // ── Add trigger (hidden at cap) ─────────────────────────────
        if (!atCap)
          InkWell(
            onTap: () => _openModal(context),
            borderRadius: AppRadius.cardBorder,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: AppRadius.cardBorder,
                border: Border.all(
                  color: AppColors.grey,
                  style: BorderStyle.solid,
                  width: 1.5,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text(
                    'Add family member',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
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

// =============================================================================
// Bottom-sheet modal contact picker — spec C3
// =============================================================================

class _FamilyPickerModal extends StatefulWidget {
  const _FamilyPickerModal({
    required this.excludeNames,
    required this.onAdd,
  });

  final List<String> excludeNames;
  final void Function(String name, String email) onAdd;

  @override
  State<_FamilyPickerModal> createState() => _FamilyPickerModalState();
}

class _FamilyPickerModalState extends State<_FamilyPickerModal> {
  final _searchController = TextEditingController();
  final _manualNameController = TextEditingController();
  final _manualEmailController = TextEditingController();

  Timer? _debounce;
  int _searchGeneration = 0;
  bool _loading = false;
  bool _searched = false;
  List<ContactSuggestion> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _manualNameController.dispose();
    _manualEmailController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = [];
        _loading = false;
        _searched = false;
      });
      return;
    }
    // ~400ms debounce (spec C3) with a skeleton-loading state so latency
    // reads as "searching", not "broken".
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(value.trim());
    });
  }

  Future<void> _runSearch(String query) async {
    final generation = ++_searchGeneration;
    try {
      final results = await ContactsService.instance.searchByName(
        query,
        exclude: widget.excludeNames,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results.take(6).toList();
        _loading = false;
        _searched = true;
      });
    } catch (e) {
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _results = [];
          _loading = false;
          _searched = true;
        });
      }
    }
  }

  void _addAndClose(String name, String email) {
    if (name.trim().isEmpty || email.trim().isEmpty) return;
    widget.onAdd(name.trim(), email.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final noMatches = _searched && !_loading && _results.isEmpty;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.paddingOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Add family member',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Search your contacts, or add someone manually.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search by name',
                hintText: 'Start typing a name…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: _onQueryChanged,
            ),
            const SizedBox(height: 12),

            // ── Skeleton loading ─────────────────────────────────────
            if (_loading)
              Column(
                children: List.generate(3, (_) => const _SkeletonRow()),
              ),

            // ── Match list (tap-to-add-immediately) ──────────────────
            if (!_loading && _results.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(
                  shrinkWrap: true,
                  children: _results
                      .where((s) => s.email != null && s.email!.isNotEmpty)
                      .map((s) => _MatchRow(
                            suggestion: s,
                            onAdd: () => _addAndClose(s.name, s.email!),
                          ))
                      .toList(),
                ),
              ),

            // ── No-match manual fallback ──────────────────────────────
            if (noMatches) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No matching contacts. Add them manually:',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                ),
              ),
              TextField(
                controller: _manualNameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _manualEmailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _addAndClose(
                    _manualNameController.text,
                    _manualEmailController.text,
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.greyLight,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.greyLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 160,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.greyLight,
                    borderRadius: BorderRadius.circular(4),
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

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.suggestion, required this.onAdd});
  final ContactSuggestion suggestion;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.primaryPale,
        child: Text(
          suggestion.name.isNotEmpty ? suggestion.name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
      title: Text(suggestion.name, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(
        suggestion.email ?? '',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Add'),
      ),
      onTap: onAdd,
    );
  }
}
