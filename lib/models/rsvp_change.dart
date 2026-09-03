/// RSVP change model for the All Teed Up golf booking app.
///
/// Records a single player's RSVP status transition for a golf round,
/// used to populate the alerts feed and trigger notifications.
library;

import 'player.dart';

/// A recorded change in a player's RSVP status.
///
/// Created when the background calendar sync detects that an attendee's
/// status has changed (e.g. from [RsvpStatus.pending] to
/// [RsvpStatus.accepted]).
///
/// ```dart
/// final change = RsvpChange(
///   eventId: 'cal-abc-123',
///   playerName: 'John Smith',
///   playerEmail: 'john@example.com',
///   oldStatus: RsvpStatus.pending,
///   newStatus: RsvpStatus.accepted,
///   detectedAt: DateTime.now(),
/// );
/// ```
class RsvpChange {
  /// Creates an [RsvpChange].
  const RsvpChange({
    required this.eventId,
    required this.playerName,
    this.playerEmail,
    required this.oldStatus,
    required this.newStatus,
    required this.detectedAt,
    this.courseName,
    this.teeTime,
    this.isRead = false,
  });

  /// The calendar event ID this change belongs to.
  final String eventId;

  /// The player's display name.
  final String playerName;

  /// The player's email, if known.
  final String? playerEmail;

  /// The player's previous RSVP status.
  final RsvpStatus oldStatus;

  /// The player's new RSVP status.
  final RsvpStatus newStatus;

  /// When this change was detected by the sync engine.
  ///
  /// This is NOT the date of the round — it is when the app noticed. The
  /// alert list used to show this as the round's date, which read as
  /// "today" for every alert no matter when the golf actually is.
  final DateTime detectedAt;

  /// The course the round is at, for display in the alert.
  ///
  /// Null on alerts saved before this field existed; the UI falls back
  /// rather than showing an empty line.
  final String? courseName;

  /// When the round tees off — the date the user actually cares about when
  /// someone drops out.
  final DateTime? teeTime;

  /// Whether the user has seen/dismissed this alert.
  final bool isRead;

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  /// Whether this change represents a decline (someone dropped out).
  bool get isDecline => newStatus == RsvpStatus.declined;

  /// Whether this change represents a new acceptance.
  bool get isAcceptance => newStatus == RsvpStatus.accepted;

  /// A human-readable summary, e.g. "John Smith: pending -> accepted".
  String get summary => '$playerName: ${oldStatus.name} -> ${newStatus.name}';

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  /// Creates an [RsvpChange] from a JSON map.
  factory RsvpChange.fromJson(Map<String, dynamic> json) {
    return RsvpChange(
      eventId: json['eventId'] as String,
      playerName: json['playerName'] as String,
      playerEmail: json['playerEmail'] as String?,
      oldStatus: _parseRsvpStatus(json['oldStatus'] as String?),
      newStatus: _parseRsvpStatus(json['newStatus'] as String?),
      detectedAt: DateTime.parse(json['detectedAt'] as String),
      courseName: json['courseName'] as String?,
      teeTime: json['teeTime'] == null
          ? null
          : DateTime.tryParse(json['teeTime'] as String),
      isRead: json['isRead'] == true || json['isRead'] == 1,
    );
  }

  /// Parses a status string into an [RsvpStatus] enum value.
  ///
  /// Falls back to [RsvpStatus.pending] for `null` or unrecognised values.
  static RsvpStatus _parseRsvpStatus(String? status) {
    if (status == null) return RsvpStatus.pending;
    switch (status.toLowerCase().trim()) {
      case 'accepted':
        return RsvpStatus.accepted;
      case 'declined':
        return RsvpStatus.declined;
      case 'pending':
      default:
        return RsvpStatus.pending;
    }
  }

  /// Serialises this change to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'playerName': playerName,
      'playerEmail': playerEmail,
      'courseName': courseName,
      'teeTime': teeTime?.toIso8601String(),
      'oldStatus': oldStatus.name,
      'newStatus': newStatus.name,
      'detectedAt': detectedAt.toIso8601String(),
      'isRead': isRead,
    };
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  /// Returns a copy of this change with the given fields replaced.
  RsvpChange copyWith({
    String? eventId,
    String? playerName,
    String? playerEmail,
    RsvpStatus? oldStatus,
    RsvpStatus? newStatus,
    DateTime? detectedAt,
    String? courseName,
    DateTime? teeTime,
    bool? isRead,
  }) {
    return RsvpChange(
      eventId: eventId ?? this.eventId,
      playerName: playerName ?? this.playerName,
      playerEmail: playerEmail ?? this.playerEmail,
      oldStatus: oldStatus ?? this.oldStatus,
      newStatus: newStatus ?? this.newStatus,
      detectedAt: detectedAt ?? this.detectedAt,
      courseName: courseName ?? this.courseName,
      teeTime: teeTime ?? this.teeTime,
      isRead: isRead ?? this.isRead,
    );
  }

  // ---------------------------------------------------------------------------
  // Equality & toString
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RsvpChange &&
        other.eventId == eventId &&
        other.playerName == playerName &&
        other.oldStatus == oldStatus &&
        other.newStatus == newStatus &&
        other.detectedAt == detectedAt;
  }

  @override
  int get hashCode =>
      Object.hash(eventId, playerName, oldStatus, newStatus, detectedAt);

  @override
  String toString() => 'RsvpChange($summary at $detectedAt)';
}
