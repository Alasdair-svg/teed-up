/// RSVP status for a player in a round.
///
/// 4-state cycle (spec A10): [tbc] → [confirmed] → [pending] → [declined] → [tbc]
enum RsvpStatus {
  /// Player has confirmed / accepted the invitation.
  confirmed,

  /// Player has not yet responded.
  pending,

  /// Player has declined the invitation.
  declined,

  // Backwards-compat alias — JSON from older builds may have stored "accepted".
  // Do not use in new code; use [confirmed] instead.
  // ignore: constant_identifier_names
  accepted,

  /// Slot not yet assigned to a named player (booking said more players
  /// than were identified by OCR).
  tbc,
}

/// Source of the player's contact information.
enum ContactSource {
  /// Synced from iCloud contacts.
  iCloud,

  /// Synced from Google contacts.
  google,

  /// Synced from Outlook/Exchange contacts.
  outlook,

  /// Entered manually by the user.
  manual,
}

/// A player participating in a golf round.
class Player {
  /// Creates a [Player] with the given details.
  const Player({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.rsvpStatus = RsvpStatus.pending,
    this.contactSource = ContactSource.manual,
    this.isNewlyAdded = false,
  });

  /// Unique identifier for this player.
  final String id;

  /// Display name.
  final String name;

  /// Email address (may be null if unresolved).
  final String? email;

  /// Phone number (optional).
  final String? phone;

  /// Current RSVP status.
  final RsvpStatus rsvpStatus;

  /// Where the contact info was sourced from.
  final ContactSource contactSource;

  /// Whether this player was newly added in an amendment.
  final bool isNewlyAdded;

  /// Whether this player has a valid email set.
  bool get hasValidEmail =>
      email != null && email!.isNotEmpty && email!.contains('@');

  /// The player's forename.
  ///
  /// Bookings write names in more than one order — "Marc McStay" on a Viya
  /// confirmation, "McStay, Marc" on tee sheets that sort by surname — so
  /// this is derived rather than assumed to be the first word.
  ///
  /// Returns the whole name when it is a single word, because a lone word is
  /// far more often a forename than a surname.
  String get firstName {
    final n = _cleanName;
    if (n.isEmpty) return '';

    final comma = n.indexOf(',');
    if (comma > 0) {
      // "McStay, Marc" and "McStay, Marc J" -> Marc
      final after = n.substring(comma + 1).trim();
      if (after.isNotEmpty) return after.split(RegExp(r'\s+')).first;
    }

    return n.split(RegExp(r'\s+')).first;
  }

  /// The player's surname, or `null` when the name is a single word.
  ///
  /// Takes the LAST word rather than the second, so middle names and
  /// initials ("Marc J McStay") do not become the surname. Keeps common
  /// multi-word particles attached ("van der Berg", "de Silva", "Mc Kenzie"),
  /// which a naive last-word split would truncate to "Berg".
  String? get lastName {
    final n = _cleanName;
    if (n.isEmpty) return null;

    final comma = n.indexOf(',');
    if (comma > 0) {
      final before = n.substring(0, comma).trim();
      if (before.isNotEmpty) return before;
    }

    final parts = n.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.length < 2) return null;

    const particles = {
      'van', 'von', 'de', 'del', 'della', 'di', 'da', 'du', 'der', 'den',
      'la', 'le', 'mac', 'mc', "o'", 'st', 'ter', 'ten', 'bin', 'ibn', 'al',
    };

    var start = parts.length - 1;
    while (start > 1 &&
        particles.contains(parts[start - 1].toLowerCase().replaceAll('.', ''))) {
      start--;
    }
    return parts.sublist(start).join(' ');
  }

  /// Name with placeholder rows and stray punctuation removed, so the
  /// forename/surname split never operates on "Player TBC" or a trailing
  /// comma.
  String get _cleanName {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return '';
    final upper = n.toUpperCase();
    if (upper == 'TBC' || upper == 'TBC TBC' || upper == 'PLAYER TBC') {
      return '';
    }
    return n.replaceAll(RegExp(r'[,\s]+$'), '');
  }

  /// Creates a [Player] from a JSON map.
  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      rsvpStatus: _parseRsvpStatus(json['rsvpStatus'] as String?),
      contactSource: ContactSource.values.firstWhere(
        (e) => e.name == json['contactSource'],
        orElse: () => ContactSource.manual,
      ),
      isNewlyAdded: json['isNewlyAdded'] == true,
    );
  }

  /// Serialises this player to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'rsvpStatus': rsvpStatus.name,
        'contactSource': contactSource.name,
        'isNewlyAdded': isNewlyAdded,
      };

  /// Creates a copy with the given fields replaced.
  Player copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    RsvpStatus? rsvpStatus,
    ContactSource? contactSource,
    bool? isNewlyAdded,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      rsvpStatus: rsvpStatus ?? this.rsvpStatus,
      contactSource: contactSource ?? this.contactSource,
      isNewlyAdded: isNewlyAdded ?? this.isNewlyAdded,
    );
  }
}

/// Parses an RSVP status string with backwards compatibility.
///
/// Maps the legacy `"accepted"` value to [RsvpStatus.confirmed].
RsvpStatus _parseRsvpStatus(String? value) {
  switch (value) {
    case 'confirmed':
    case 'accepted': // legacy
      return RsvpStatus.confirmed;
    case 'declined':
      return RsvpStatus.declined;
    case 'tbc':
      return RsvpStatus.tbc;
    case 'pending':
    default:
      return RsvpStatus.pending;
  }
}
