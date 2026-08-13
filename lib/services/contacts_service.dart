/// Contact resolution service for the Teed Up golf booking app.
///
/// Resolves player names to email addresses using a three-tier strategy:
/// 1. **Local cache** — manual corrections always win.
/// 2. **Device contacts** — searched via [flutter_contacts].
/// 3. **Multi-strategy search** — full name → last name → first name.
///
/// Successful resolutions are cached in SQLite so subsequent look-ups
/// are instantaneous and work offline.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../db/database_helper.dart';

/// Resolves player names to email addresses from device contacts,
/// with a SQLite-backed cache and manual-correction support.
///
/// ```dart
/// final service = ContactsService();
/// final emails = await service.resolvePlayerEmails(['John Smith', 'Jane Doe']);
/// ```
class ContactsService {
  /// Creates a [ContactsService] backed by the given [DatabaseHelper].
  ///
  /// Falls back to [DatabaseHelper.instance] when no helper is supplied,
  /// which is the normal production path.
  ContactsService({DatabaseHelper? dbHelper})
      : _db = dbHelper ?? DatabaseHelper.instance;

  /// Shared production instance, for call sites that don't need DI.
  static final ContactsService instance = ContactsService();

  final DatabaseHelper _db;

  /// In-memory cache of the device contact list, keyed by app session.
  ///
  /// `FlutterContacts.getContacts(withProperties: true)` re-reads and
  /// re-parses every contact's full property set on each call — on a real
  /// device this can take multiple seconds. Every search/resolution call
  /// was hitting that cost on every keystroke-debounced query, which read
  /// to the user as the app freezing. Fetched once per session and reused;
  /// call [_invalidateContactsCache] if a caller needs a fresh read (e.g.
  /// after the user grants contacts permission for the first time).
  static List<Contact>? _deviceContactsCache;

  Future<List<Contact>> _getDeviceContacts() async {
    final cached = _deviceContactsCache;
    if (cached != null) return cached;
    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );
    _deviceContactsCache = contacts;
    return contacts;
  }

  /// Clears the in-memory device-contacts cache, forcing the next query to
  /// re-fetch. Call after permission is newly granted, or if a caller needs
  /// to observe a contact added/edited since the cache was populated.
  static void invalidateContactsCache() => _deviceContactsCache = null;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Resolves a list of [playerNames] to email addresses.
  ///
  /// For each name the resolution order is:
  /// 1. Check the local SQLite cache (manual corrections take priority).
  /// 2. If not cached, search device contacts via [FlutterContacts].
  /// 3. Cache any newly resolved emails for future look-ups.
  ///
  /// Returns a `Map<name, email>` containing only the names for which
  /// an email could be found. Names with no match are omitted.
  Future<Map<String, String>> resolvePlayerEmails(
    List<String> playerNames,
  ) async {
    final results = <String, String>{};

    for (final name in playerNames) {
      if (name.trim().isEmpty) continue;

      try {
        // ── 1. Check cache (manual corrections surface first) ──
        final cached = await _db.queryContactCacheByName(name);
        if (cached.isNotEmpty) {
          results[name] = cached.first['email'] as String;
          continue;
        }

        // ── 2. Search device contacts ──
        final email = await _searchDeviceContacts(name);
        if (email != null) {
          await cacheContactResolution(name, email, 'device_contacts');
          results[name] = email;
        }
      } catch (e, st) {
        debugPrint('ContactsService: failed to resolve "$name": $e\n$st');
        // Swallow per-name errors so other names can still resolve.
      }
    }

    return results;
  }

  /// Returns device-contact suggestions whose display name contains [query]
  /// (case-insensitive substring match), for the family-setup autocomplete
  /// (spec A4). Names in [exclude] (already-added family members) are
  /// filtered out. Callers should cap the result count themselves
  /// (e.g. `.take(4)`).
  Future<List<ContactSuggestion>> searchByName(
    String query, {
    List<String> exclude = const [],
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    try {
      if (!await FlutterContacts.requestPermission(readonly: true)) {
        debugPrint('ContactsService: contacts permission denied');
        return [];
      }

      final excludeSet = exclude.map((e) => e.trim().toLowerCase()).toSet();
      final contacts = await _getDeviceContacts();

      return contacts
          .where((c) => c.displayName.toLowerCase().contains(q))
          .where((c) => !excludeSet.contains(c.displayName.trim().toLowerCase()))
          .map((c) => ContactSuggestion(
                name: c.displayName,
                email: _pickBestEmail(c),
              ))
          .toList();
    } catch (e, st) {
      debugPrint('ContactsService: searchByName "$query" failed: $e\n$st');
      return [];
    }
  }

  /// Saves a manual correction for [name] → [email].
  ///
  /// Manual corrections are stored with `is_manual = 1` and are **never**
  /// overwritten by automatic resolution. Calling this again for the same
  /// name updates the existing manual entry.
  Future<void> saveManualCorrection(String name, String email) async {
    final existing = await _db.queryContactCacheByName(name);

    // If a manual entry already exists, update it in place.
    final manualRow = existing.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r!['is_manual'] == 1,
          orElse: () => null,
        );

    if (manualRow != null) {
      await _db.updateContactCache(manualRow['id'] as int, {
        'email': email,
        'source': 'manual_correction',
        'is_manual': 1,
      });
    } else {
      await _db.insertContactCache({
        'name': name,
        'email': email,
        'source': 'manual_correction',
        'is_manual': 1,
      });
    }
  }

  /// Caches an auto-resolved [email] for [name] with the given [source].
  ///
  /// If a manual correction already exists for [name], this call is a
  /// no-op — manual entries are sacrosanct. Otherwise any previous auto
  /// entry is replaced to keep the cache fresh.
  Future<void> cacheContactResolution(
    String name,
    String email,
    String source,
  ) async {
    // Never overwrite a manual correction.
    if (await _db.hasManualCorrection(name)) return;

    // Remove stale auto entries, then insert the fresh one.
    await _db.deleteAutoEntriesForName(name);
    await _db.insertContactCache({
      'name': name,
      'email': email,
      'source': source,
      'is_manual': 0,
    });
  }

  /// Returns all cached name → email mappings.
  ///
  /// If multiple entries exist for the same name (shouldn't normally
  /// happen), manual corrections take precedence.
  Future<Map<String, String>> getCachedEmails() async {
    final rows = await _db.queryAllContactCache();
    final results = <String, String>{};

    for (final row in rows) {
      final name = row['name'] as String;
      // Only overwrite if this row is manual and the existing one isn't,
      // or if the name hasn't been seen yet.
      if (!results.containsKey(name) || row['is_manual'] == 1) {
        results[name] = row['email'] as String;
      }
    }

    return results;
  }

  /// Clears all **non-manual** cache entries.
  ///
  /// Manual corrections are preserved so the user never loses their
  /// hand-entered mappings.
  Future<void> clearCache() async {
    await _db.clearAutoCache();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Searches device contacts for [name] using a multi-strategy approach:
  /// full name → last name → first name.
  ///
  /// Returns the best matching email or `null` if nothing was found.
  Future<String?> _searchDeviceContacts(String name) async {
    // Bail out early if we don't have contacts permission.
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      debugPrint('ContactsService: contacts permission denied');
      return null;
    }

    final nameParts = name.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.last : null;

    // Strategy 1 — search by full name.
    var email = await _findEmailByQuery(name);
    if (email != null) return email;

    // Strategy 2 — search by last name only (catches "Smith, John" entries).
    if (lastName != null && lastName != firstName) {
      email = await _findEmailByQuery(lastName, refineName: name);
      if (email != null) return email;
    }

    // Strategy 3 — search by first name only (broadest match).
    email = await _findEmailByQuery(firstName, refineName: name);
    return email;
  }

  /// Queries device contacts for [query] and returns the best email.
  ///
  /// When [refineName] is provided the result list is further filtered to
  /// contacts whose display name contains **all** parts of [refineName],
  /// preventing false positives from broad single-word queries.
  Future<String?> _findEmailByQuery(
    String query, {
    String? refineName,
  }) async {
    try {
      final contacts = await _getDeviceContacts();

      // Filter contacts matching the query.
      final matches = contacts.where((c) {
        final displayName = c.displayName.toLowerCase();
        final q = query.toLowerCase();

        // Basic substring match first.
        if (!displayName.contains(q)) return false;

        // If we have a refinement name, ensure ALL parts appear.
        if (refineName != null) {
          final parts =
              refineName.toLowerCase().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
          return parts.every((p) => displayName.contains(p));
        }

        return true;
      }).toList();

      if (matches.isEmpty) return null;

      // Prefer exact full-name matches over partial ones.
      final exactMatch = matches.cast<Contact?>().firstWhere(
            (c) => c!.displayName.toLowerCase() == (refineName ?? query).toLowerCase(),
            orElse: () => null,
          );

      final bestMatch = exactMatch ?? matches.first;
      return _pickBestEmail(bestMatch);
    } catch (e, st) {
      debugPrint('ContactsService: contact query "$query" failed: $e\n$st');
      return null;
    }
  }

  /// Picks the best email from a [contact].
  ///
  /// Prefers emails labelled as *work* or *home* over unlabelled ones.
  /// When the contact has only one email, that one wins regardless of label.
  String? _pickBestEmail(Contact contact) {
    final emails = contact.emails;
    if (emails.isEmpty) return null;
    if (emails.length == 1) return emails.first.address;

    // Priority: work > home > other > unlabelled.
    const labelPriority = {
      EmailLabel.work: 0,
      EmailLabel.home: 1,
      EmailLabel.iCloud: 2,
      EmailLabel.other: 3,
    };

    final sorted = List<Email>.from(emails)
      ..sort((a, b) {
        final pa = labelPriority[a.label] ?? 99;
        final pb = labelPriority[b.label] ?? 99;
        return pa.compareTo(pb);
      });

    return sorted.first.address;
  }
}

/// A device-contact match surfaced by [ContactsService.searchByName].
class ContactSuggestion {
  /// Creates a [ContactSuggestion] with a [name] and optional [email].
  const ContactSuggestion({required this.name, this.email});

  /// Display name from the device contact.
  final String name;

  /// Best email address for this contact, if any.
  final String? email;
}
