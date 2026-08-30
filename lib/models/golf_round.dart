import 'player.dart';

/// Represents a golf round/booking.
class GolfRound {
  /// Creates a [GolfRound] with all booking details.
  GolfRound({
    required this.id,
    required this.courseName,
    required this.date,
    required this.teeTime,
    required this.players,
    this.location,
    this.bookingRef,
    this.calendarEventId,
    this.familyNotified = false,
    this.isCreator = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Unique identifier.
  final String id;

  /// Name of the golf course.
  final String courseName;

  /// Where the course is — an address or city, when the booking states one.
  ///
  /// Distinct from [courseName]. The calendar event's location field used to
  /// repeat the course name, which tells a maps app nothing. Null when the
  /// booking gives no address; a wrong address is worse than none.
  final String? location;

  /// Date of the round.
  final DateTime date;

  /// Tee time (stored as TimeOfDay-equivalent hours/minutes in DateTime).
  final DateTime teeTime;

  /// Players in this round.
  final List<Player> players;

  /// Booking reference from the confirmation.
  final String? bookingRef;

  /// Linked device calendar event ID (if created).
  final String? calendarEventId;

  /// Whether friends & family have been informed about this round.
  final bool familyNotified;

  /// Whether this device created/organized the round (scanned the booking),
  /// as opposed to being auto-imported from a calendar invite someone else
  /// sent. Gates every write action except cycling your own RSVP — see the
  /// Creator/Recipient permission model.
  ///
  /// Defaults to `true`: every round built via the existing scan flow is
  /// self-created. Only the calendar auto-import path constructs a round
  /// with this `false`.
  final bool isCreator;

  /// When this round was created in the app.
  final DateTime createdAt;

  /// Timeline of events for this round.
  final List<RoundEvent> timeline = [];

  /// Whether the round is in the future.
  bool get isUpcoming => date.isAfter(DateTime.now());

  /// Formatted tee time string (HH:mm).
  String get formattedTeeTime =>
      '${teeTime.hour.toString().padLeft(2, '0')}:${teeTime.minute.toString().padLeft(2, '0')}';

  /// Creates a [GolfRound] from a JSON map.
  factory GolfRound.fromJson(Map<String, dynamic> json) {
    return GolfRound(
      id: json['id'] as String,
      courseName: json['courseName'] as String,
      date: DateTime.parse(json['date'] as String),
      teeTime: DateTime.parse(json['teeTime'] as String),
      players: (json['players'] as List<dynamic>)
          .map((p) => Player.fromJson(p as Map<String, dynamic>))
          .toList(),
      location: json['location'] as String?,
      bookingRef: json['bookingRef'] as String?,
      calendarEventId: json['calendarEventId'] as String?,
      familyNotified: json['familyNotified'] == true,
      // Absent on any round persisted before this field existed — those are
      // all self-created rounds from the pre-auto-import app, so default
      // true rather than reading a missing key as false.
      isCreator: json['isCreator'] == null ? true : json['isCreator'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  /// Serialises this round to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'courseName': courseName,
        'date': date.toIso8601String(),
        'teeTime': teeTime.toIso8601String(),
        'players': players.map((p) => p.toJson()).toList(),
        'location': location,
        'bookingRef': bookingRef,
        'calendarEventId': calendarEventId,
        'familyNotified': familyNotified,
        'isCreator': isCreator,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Creates a copy with the given fields replaced.
  GolfRound copyWith({
    String? id,
    String? courseName,
    DateTime? date,
    DateTime? teeTime,
    List<Player>? players,
    String? location,
    String? bookingRef,
    String? calendarEventId,
    bool? familyNotified,
    bool? isCreator,
    DateTime? createdAt,
  }) {
    return GolfRound(
      id: id ?? this.id,
      courseName: courseName ?? this.courseName,
      date: date ?? this.date,
      teeTime: teeTime ?? this.teeTime,
      players: players ?? this.players,
      location: location ?? this.location,
      bookingRef: bookingRef ?? this.bookingRef,
      calendarEventId: calendarEventId ?? this.calendarEventId,
      familyNotified: familyNotified ?? this.familyNotified,
      isCreator: isCreator ?? this.isCreator,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// An event in the round's timeline.
class RoundEvent {
  /// Creates a [RoundEvent].
  const RoundEvent({
    required this.type,
    required this.timestamp,
    this.playerName,
    this.description,
  });

  /// The type of event.
  final RoundEventType type;

  /// When the event occurred.
  final DateTime timestamp;

  /// Associated player name (for RSVP events).
  final String? playerName;

  /// Human-readable description.
  final String? description;
}

/// Types of events in a round's timeline.
enum RoundEventType {
  /// Round was first created.
  created,

  /// Calendar invites were sent.
  invitesSent,

  /// A player accepted.
  playerAccepted,

  /// A player declined.
  playerDeclined,

  /// The booking was amended.
  amended,

  /// The round was cancelled.
  cancelled,
}
