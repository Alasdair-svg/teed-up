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
