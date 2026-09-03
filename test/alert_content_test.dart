// An alert has to say WHICH round, and WHEN the golf is.
//
// Reported from the field on build 65: declines arrived with "no content"
// and "dated today's date, not the date of the booking".
//
// Both came from the same place. RsvpChange carried only an eventId — no
// course, no tee time — so the alert row had nothing to print but the
// player's name, and the line labelled "Round details" printed detectedAt,
// which is when the app noticed, not when the round is. Every alert
// therefore read as today whatever day the golf was on.
//
// The monitor had the details all along: it passes eventTitle and eventDate
// to the push notification, and simply never put them on the alert.
import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/models/player.dart';
import 'package:all_teed_up/models/rsvp_change.dart';
import 'package:all_teed_up/services/rsvp_monitor.dart';

void main() {
  final teeOff = DateTime(2026, 9, 27, 7, 20);

  RsvpChange alert({String? course, DateTime? tee}) => RsvpChange(
        eventId: 'EVT-1',
        playerName: 'Marc McStay',
        oldStatus: RsvpStatus.confirmed,
        newStatus: RsvpStatus.declined,
        detectedAt: DateTime(2026, 9, 3, 12, 40), // "today"
        courseName: course,
        teeTime: tee,
      );

  group('alert carries the round', () {
    test('course and tee time are distinct from the detection time', () {
      final a = alert(course: 'Emirates Golf Club', tee: teeOff);
      expect(a.courseName, 'Emirates Golf Club');
      expect(a.teeTime, teeOff);
      expect(a.teeTime, isNot(a.detectedAt),
          reason: 'the round is on the 27th; the app noticed on the 3rd');
    });

    test('survives the save/load round trip', () {
      final restored = RsvpChange.fromJson(
          alert(course: 'Dubai Creek', tee: teeOff).toJson());
      expect(restored.courseName, 'Dubai Creek');
      expect(restored.teeTime, teeOff);
    });

    test('marking as read does not drop the round details', () {
      final read = alert(course: 'Dubai Creek', tee: teeOff).copyWith(isRead: true);
      expect(read.isRead, isTrue);
      expect(read.courseName, 'Dubai Creek');
      expect(read.teeTime, teeOff,
          reason: 'copyWith omitted these, so tapping an alert blanked it');
    });

    test('an alert stored before these fields existed still loads', () {
      final legacy = RsvpChange.fromJson({
        'eventId': 'EVT-OLD',
        'playerName': 'Guy Parsonage',
        'oldStatus': 'accepted',
        'newStatus': 'declined',
        'detectedAt': DateTime(2026, 9, 1).toIso8601String(),
      });
      expect(legacy.courseName, isNull);
      expect(legacy.teeTime, isNull,
          reason: 'the row hides the line rather than printing a wrong date');
    });
  });

  group('course name out of the event title', () {
    test('strips the marker and the trailing detail', () {
      expect(
        RsvpMonitor.courseFromEventTitle(
            '⛳ Emirates Golf Club | 07:20 | Alasdair, Marc | All Teed Up'),
        'Emirates Golf Club',
      );
    });

    test('handles a title with no marker or separators', () {
      expect(RsvpMonitor.courseFromEventTitle('Dubai Creek'), 'Dubai Creek');
    });

    test('never returns empty', () {
      expect(RsvpMonitor.courseFromEventTitle('⛳ '), 'Golf Round');
      expect(RsvpMonitor.courseFromEventTitle(''), 'Golf Round');
    });
  });
}
