/// A friend or family member kept informed about upcoming rounds.
///
/// Unlike [Player], a [FamilyMember] never plays — they're added to the
/// device calendar event as an informational (optional) attendee only.
class FamilyMember {
  /// Creates a [FamilyMember] with a [name] and [email].
  const FamilyMember({required this.name, required this.email});

  /// Display name.
  final String name;

  /// Email address, used to add them as an optional calendar attendee.
  final String email;

  /// Creates a [FamilyMember] from a JSON map.
  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  /// Serialises this member to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'name': name, 'email': email};
}
