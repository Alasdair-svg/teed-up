/// Contact resolution service for the All Teed Up golf booking app.
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

/// Normalises a name for comparison: lowercase, accents folded, punctuation
/// (hyphens, apostrophes, dots) reduced to spaces, whitespace collapsed.
///
/// Needed because OCR and the address book routinely disagree on
/// punctuation — "Sidi-Mohammed Saaf" against a contact saved as
/// "Sidi Mohammed Saaf" — and a raw substring test treats that as a
/// different person.
String normalizeName(String v) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final buf = StringBuffer();
  for (final ch in v.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Whether [query] and [candidate] plausibly name the same person.
///
/// The previous rule required EVERY token of the scanned name to appear as a
/// literal substring of the contact's display name. That rejected the two
/// commonest real-world cases: a shortened first name ("Zach Drury" in
/// contacts vs "Zachary Drury" on the booking) and punctuation differences
/// in compound names. Both looked to the user like the app simply failing to
/// find a contact that was plainly there.
///
/// The surname must match exactly. The forename may match exactly, be a
/// prefix of the other (Zach/Zachary, Nick/Nicholas), or share an initial.
bool namesMatch(String query, String candidate) {
  final q = normalizeName(query).split(' ').where((e) => e.isNotEmpty).toList();
  final c =
      normalizeName(candidate).split(' ').where((e) => e.isNotEmpty).toList();
  if (q.isEmpty || c.isEmpty) return false;

  if (q.last != c.last) return false;
  if (q.length == 1 || c.length == 1) return true;

  final qf = q.first;
  final cf = c.first;
  if (qf == cf) return true;
  if (qf.startsWith(cf) || cf.startsWith(qf)) return true;
  return qf[0] == cf[0];
}

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

  /// In-memory cache of the device contact list — **names only**, no
  /// properties (emails/phones/etc). `FlutterContacts.getContacts(
  /// withProperties: true)` fetches every property for every contact and can
  /// take many seconds on a real address book; fetching without properties
  /// is a much cheaper single query and is fast even with thousands of
  /// contacts. Emails are hydrated afterwards, only for the handful of
  /// contacts that actually match a query — see [_hydrateEmails].
  static List<Contact>? _deviceContactsLightCache;
  static DateTime? _deviceContactsCachedAt;
  static Future<List<Contact>>? _prefetchInFlight;

  /// How long the light contacts cache stays valid.
  ///
  /// It previously had no expiry at all and [invalidateContactsCache] was
  /// never called from anywhere, so the list was fetched once per app
  /// process and then frozen. Anyone added, edited, or synced after that
  /// first fetch stayed invisible until the app was force-quit — which
  /// looks exactly like "it can't find this one contact" while every other
  /// name resolves fine.
  static const Duration _cacheTtl = Duration(minutes: 15);

  Future<List<Contact>> _getDeviceContactsLight() async {
    final cached = _deviceContactsLightCache;
    final cachedAt = _deviceContactsCachedAt;
    final stale =
        cachedAt == null || DateTime.now().difference(cachedAt) >= _cacheTtl;

    // Stale-while-revalidate. A plain TTL made every search after the
    // expiry pay a full address-book fetch on the UI path, which turned a
    // previously instant contact search into a visible wait — a worse bug
    // than the staleness it was added to fix. Now a cached list is ALWAYS
    // returned immediately, and a stale one additionally kicks off a
    // background refresh whose result lands in time for the next search.
    if (cached != null) {
      if (stale) _refreshInBackground();
      return cached;
    }
    // Coalesce concurrent callers onto the same in-flight fetch instead of
    // each kicking off a separate platform-channel call.
    final future = _prefetchInFlight ??= FlutterContacts.getContacts(
      withProperties: false,
      withPhoto: false,
      withThumbnail: false,
    );
    try {
      final contacts = await future;
      _deviceContactsLightCache = contacts;
      _deviceContactsCachedAt = DateTime.now();
      return contacts;
    } finally {
      _prefetchInFlight = null;
    }
  }

  /// Re-fetches the contact list without blocking the caller.
  void _refreshInBackground() {
    if (_prefetchInFlight != null) return; // already refreshing
    final future = _prefetchInFlight = FlutterContacts.getContacts(
      withProperties: false,
      withPhoto: false,
      withThumbnail: false,
    );
    future.then((contacts) {
      _deviceContactsLightCache = contacts;
      _deviceContactsCachedAt = DateTime.now();
    }).catchError((_) {
      // Keep serving the previous list; a later search retries.
    }).whenComplete(() => _prefetchInFlight = null);
  }

  /// Warms the light contacts cache in the background. Call this as soon as
  /// contacts permission is granted (onboarding) or at app start if
  /// permission was already granted in a prior session, so the first real
  /// search doesn't pay the fetch cost while the user is waiting on it.
  static void prefetch() {
    // Fire-and-forget — errors are swallowed, a real search will just
    // fetch (and cache) normally if this fails.
    instance._getDeviceContactsLight().catchError((_) => <Contact>[]);
  }

  /// Clears the in-memory device-contacts cache, forcing the next query to
  /// re-fetch. Call after permission is newly granted, or if a caller needs
  /// to observe a contact added/edited since the cache was populated.
  static void invalidateContactsCache() {
    _deviceContactsLightCache = null;
    _deviceContactsCachedAt = null;
  }

  /// Hydrates full properties (email, etc.) for a short list of contact
  /// [stubs] in parallel — cheap because it's bounded to just the matches
  /// actually being shown/used, not the whole address book.
  Future<List<Contact>> _hydrateEmails(List<Contact> stubs) async {
    final hydrated = await Future.wait(stubs.map(
      (c) => FlutterContacts.getContact(
        c.id,
        withProperties: true,
        withPhoto: false,
        withThumbnail: false,
      ),
    ));
    return hydrated.whereType<Contact>().toList();
  }

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

  /// Like [resolvePlayerEmails], but returns EVERY candidate address per
  /// name rather than only the top-priority one.
  ///
  /// Needed because a contact with both a work and a personal address had
  /// one silently chosen, so an invite could be sent to an address the
  /// person doesn't read with no sign a choice had been made. The scan
  /// review screen uses this to offer the alternatives.
  ///
  /// Names with no match are omitted. Order is best-first, matching
  /// [orderedEmails].
  Future<Map<String, List<String>>> resolvePlayerEmailOptions(
    List<String> playerNames,
  ) async {
    final out = <String, List<String>>{};
    for (final name in playerNames) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      try {
        final matches = await searchByName(trimmed);
        if (matches.isEmpty) continue;
        // Prefer an exact display-name match; otherwise the first hit.
        final exact = matches.firstWhere(
          (m) => m.name.trim().toLowerCase() == trimmed.toLowerCase(),
          orElse: () => matches.first,
        );
        if (exact.allEmails.isNotEmpty) out[name] = exact.allEmails;
      } catch (e) {
        debugPrint('ContactsService: email options for "$name" failed: $e');
      }
    }
    return out;
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
      final light = await _getDeviceContactsLight();

      final nameMatches = light
          .where((c) => c.displayName.toLowerCase().contains(q))
          .where(
              (c) => !excludeSet.contains(c.displayName.trim().toLowerCase()))
          .take(10) // over-fetch a little — some matches may lack an email
          .toList();
      if (nameMatches.isEmpty) return [];

      final hydrated = await _hydrateEmails(nameMatches);

      return hydrated
          .map((c) => ContactSuggestion(
                name: c.displayName,
                email: _pickBestEmail(c),
                allEmails: orderedEmails(c),
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
  /// Matches against the cheap, properties-free contact list first, then
  /// hydrates email data only for the shortlisted matches — not the whole
  /// address book.
  ///
  /// When [refineName] is provided the result list is further filtered to
  /// contacts whose display name contains **all** parts of [refineName],
  /// preventing false positives from broad single-word queries.
  Future<String?> _findEmailByQuery(
    String query, {
    String? refineName,
  }) async {
    try {
      final light = await _getDeviceContactsLight();

      // Filter contacts matching the query.
      final target = refineName ?? query;
      final nameMatches = light.where((c) {
        // Real name comparison first — tolerates shortened forenames and
        // punctuation differences that a substring test rejects outright.
        if (namesMatch(target, c.displayName)) return true;
        // Then the looser substring test, which still catches partial
        // queries like a bare surname.
        return normalizeName(c.displayName).contains(normalizeName(query));
      }).toList();

      // Best matches first so the hydrate cap can't discard the right person.
      nameMatches.sort((a, b) {
        int rank(Contact c) {
          if (normalizeName(c.displayName) == normalizeName(target)) return 0;
          if (namesMatch(target, c.displayName)) return 1;
          return 2;
        }

        return rank(a).compareTo(rank(b));
      });

      if (nameMatches.isEmpty) return null;

      // Prefer an exact full-name match if present, otherwise hydrate just
      // the first handful of candidates (bounded — a common first/last name
      // query shouldn't hydrate hundreds of contacts).
      // Collapse runs of whitespace before comparing — a contact saved as
      // "Guy  Parsonage" (double space) or with stray padding would
      // otherwise miss the exact-match path and fall back to fuzzier
      // matching for no good reason.
      final exactStub = nameMatches.cast<Contact?>().firstWhere(
            (c) => normalizeName(c!.displayName) == normalizeName(target),
            orElse: () => null,
          );

      final toHydrate =
          exactStub != null ? [exactStub] : nameMatches.take(8).toList();
      final hydrated = await _hydrateEmails(toHydrate);
      if (hydrated.isEmpty) return null;

      // Return the first candidate that ACTUALLY HAS an email. This used to
      // be `_pickBestEmail(hydrated.first)`, which gave up if the single
      // first candidate happened to have no address — even though a later
      // one did. A contact whose name collides with an email-less entry
      // (a phone-only contact, a company record) was therefore
      // unresolvable, which is a silent and very confusing failure.
      for (final c in hydrated) {
        final email = _pickBestEmail(c);
        if (email != null) return email;
      }
      return null;
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
    final ordered = orderedEmails(contact);
    return ordered.isEmpty ? null : ordered.first;
  }

  /// Every address on [contact], best-first (work > home > iCloud > other >
  /// unlabelled), de-duplicated.
  ///
  /// [_pickBestEmail] returns only the first of these. That's a reasonable
  /// default but a poor final answer: a contact with both a work and a
  /// personal address gets one picked silently, so an invite can go to an
  /// address the person never reads with no indication a choice was made.
  /// Surfacing the full list lets the UI ask.
  List<String> orderedEmails(Contact contact) {
    final emails = contact.emails;
    if (emails.isEmpty) return const [];

    // Priority: work > home > iCloud > other > unlabelled.
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

    final out = <String>[];
    for (final e in sorted) {
      final addr = e.address.trim();
      if (addr.isEmpty) continue;
      if (out.any((x) => x.toLowerCase() == addr.toLowerCase())) continue;
      out.add(addr);
    }
    return out;
  }
}

/// A device-contact match surfaced by [ContactsService.searchByName].
class ContactSuggestion {
  /// Creates a [ContactSuggestion] with a [name] and optional [email].
  const ContactSuggestion({
    required this.name,
    this.email,
    this.allEmails = const [],
  });

  /// Display name from the device contact.
  final String name;

  /// Best email address for this contact, if any.
  final String? email;

  /// Every email on the contact, best-first.
  ///
  /// A contact with a work AND a personal address used to have one silently
  /// chosen by label priority, with no way for the user to say which one the
  /// invite should go to — so invites could be sent to an address the person
  /// doesn't read. Callers should offer a choice whenever this has more than
  /// one entry.
  final List<String> allEmails;

  /// Whether this contact has more than one address to choose between.
  bool get hasMultipleEmails => allEmails.length > 1;
}
