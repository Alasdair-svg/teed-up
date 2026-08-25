/// Manual email assignment for a player whose address couldn't be resolved.
///
/// Automatic contact resolution will always miss sometimes — a name spelled
/// differently in the address book than on the booking, a contact that hasn't
/// synced yet, a person genuinely not in contacts at all. Before this existed
/// there was no recovery from that: a scanned player with no email rendered
/// with no address and no affordance, and the invite simply went out without
/// them, silently. This is the escape hatch — search contacts by any spelling,
/// or type an address directly.
library;

import 'package:flutter/material.dart';

import '../services/contacts_service.dart';
import '../theme/app_theme.dart';

/// Presents the email picker for [playerName]; resolves to the chosen address,
/// or null if dismissed.
Future<String?> showEmailPickerSheet(
  BuildContext context, {
  required String playerName,
  ContactsService? service,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => EmailPickerSheet(playerName: playerName, service: service),
  );
}

/// Search-contacts-or-type-an-address sheet. Exposed for testing.
class EmailPickerSheet extends StatefulWidget {
  /// Creates an [EmailPickerSheet] for [playerName].
  const EmailPickerSheet({
    super.key,
    required this.playerName,
    this.service,
  });

  /// The player needing an address — shown in the title and used as the
  /// initial search query, since the OCR'd name is the best first guess.
  final String playerName;

  /// Injectable for tests; defaults to the shared production instance.
  final ContactsService? service;

  @override
  State<EmailPickerSheet> createState() => _EmailPickerSheetState();
}

class _EmailPickerSheetState extends State<EmailPickerSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.playerName);
  ContactsService get _service => widget.service ?? ContactsService.instance;

  /// Flattened to one entry per address rather than one per contact: a
  /// contact with work and personal addresses shows both, so the user picks
  /// the exact address instead of trusting label priority to guess right.
  List<({String name, String email})> _results = const [];
  bool _searching = false;

  /// Guards against out-of-order responses: a slow search for an early,
  /// shorter query must not overwrite results for what's now in the field.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search(_ctrl.text);
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    final mine = ++_seq;
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    List<ContactSuggestion> found;
    try {
      found = await _service.searchByName(q);
    } catch (_) {
      found = const [];
    }
    if (!mounted || mine != _seq) return;

    final flat = <({String name, String email})>[];
    final seen = <String>{};
    for (final c in found) {
      // A contact with no address can't help here, so it isn't offered.
      final emails = c.allEmails.isNotEmpty
          ? c.allEmails
          : (c.email != null ? [c.email!] : const <String>[]);
      for (final e in emails) {
        if (seen.add('${c.name}|$e')) flat.add((name: c.name, email: e));
      }
    }
    setState(() {
      _results = flat.take(10).toList();
      _searching = false;
    });
  }

  /// Deliberately permissive. This only decides whether to offer the typed
  /// text as an address — over-strict validation here would block real,
  /// valid addresses for no benefit, and the calendar rejects genuine
  /// rubbish anyway.
  bool get _typedLooksLikeEmail {
    final v = _ctrl.text.trim();
    if (v.contains(RegExp(r'\s'))) return false;
    final at = v.indexOf('@');
    return at > 0 && v.indexOf('.', at) > at + 1 && !v.endsWith('.');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      // Lifts the sheet clear of the keyboard, which otherwise covers the
      // results the user is trying to read while typing.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
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
              child: Text(
                'Add an email for ${widget.playerName}',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                "We couldn't match this name to a contact. Try a different "
                'spelling, or type their address.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _ctrl,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  hintText: 'Name or email address',
                ),
                onChanged: (v) {
                  setState(() {}); // refresh the "use this address" row
                  _search(v);
                },
              ),
            ),
            const SizedBox(height: 8),
            if (_typedLooksLikeEmail)
              ListTile(
                leading: const Icon(Icons.alternate_email_rounded,
                    color: AppColors.primary),
                title: Text(_ctrl.text.trim()),
                subtitle: const Text('Use this address'),
                onTap: () => Navigator.of(context).pop(_ctrl.text.trim()),
              ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_results.isEmpty && !_typedLooksLikeEmail)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Text(
                  _ctrl.text.trim().length < 2
                      ? 'Type at least two characters to search.'
                      : 'No contacts matched. You can type an email address '
                          'instead.',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final r = _results[i];
                    return ListTile(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: Text(r.name),
                      subtitle: Text(r.email, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).pop(r.email),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
