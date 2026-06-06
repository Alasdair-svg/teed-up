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
    this.bookingRef,
    this.calendarEventId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Unique identifier.
  final String id;

  /// Name of the golf course.
  final String courseName;

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

  /// When this round was created in the app.
  final DateTime createdAt;

  /// Timeline of events for this round.
  final List<RoundEvent> timeline = [];

  /// Whether the round is in the future.
  bool get isUpcoming => date.isAfter(DateTime.now());

  /// Formatted tee time string (HH:mm).
  String get formattedTeeTime =>
      '${teeTime.hour.toString().padLeft(2, '0')}:${teeTime.minute.toString().padLeft(2, '0')}';

  /// Creates a copy with the given fields replaced.
  GolfRound copyWith({
    String? id,
    String? courseName,
    DateTime? date,
    DateTime? teeTime,
    List<Player>? players,
    String? bookingRef,
    String? calendarEventId,
    DateTime? createdAt,
  }) {
    return GolfRound(
      id: id ?? this.id,
      courseName: courseName ?? this.courseName,
      date: date ?? this.date,
      teeTime: teeTime ?? this.teeTime,
      players: players ?? this.players,
      bookingRef: bookingRef ?? this.bookingRef,
      calendarEventId: calendarEventId ?? this.calendarEventId,
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
