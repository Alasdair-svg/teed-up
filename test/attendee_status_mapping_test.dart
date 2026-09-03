// CalendarService and RsvpMonitor must read an attendee's RSVP the same way.
//
// They did not. Two separate `_attendeeStatusToString` implementations
// existed with different mappings, and they sit on opposite ends of the
// same comparison: CalendarService writes the baseline into the RSVP cache
// (_seedRsvpBaseline), RsvpMonitor reads the live status on every poll and
// compares it against that baseline. If the two disagree about what a
// given attendee's status *is*, the comparison is meaningless — either a
// change is invented where nothing happened, or a real decline reads as
// "no change" and is never reported.
//
// Two concrete divergences:
//
//   * CalendarService gated on `Platform.isIOS` / `Platform.isAndroid` and
//     returned `unknown` otherwise. Whenever that gate is wrong, a plainly
//     readable *declined* attendee comes back as unknown. The monitor did
//     not gate; it read whichever details field was populated.
//   * The monitor collapsed `tentative` into `pending`; CalendarService
//     kept it distinct — so the same attendee was cached as two different
//     strings depending on which code path wrote the entry.
//
// There is now one implementation, in CalendarService, and this test holds
// the two classes to it.
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:all_teed_up/services/calendar_service.dart';
import 'package:all_teed_up/services/rsvp_monitor.dart';

void main() {
  Attendee android(AndroidAttendanceStatus status) => Attendee(
        name: 'Guy Parsonage',
        emailAddress: 'guy@example.com',
        androidAttendeeDetails:
            AndroidAttendeeDetails(attendanceStatus: status),
      );

  Attendee ios(IosAttendanceStatus status) => Attendee(
        name: 'Guy Parsonage',
        emailAddress: 'guy@example.com',
        iosAttendeeDetails: IosAttendeeDetails(attendanceStatus: status),
      );

  group('a decline is read as a decline', () {
    test('from Android attendance details', () {
      expect(
        CalendarService.attendeeStatusOf(
          android(AndroidAttendanceStatus.Declined),
        ),
        AttendeeStatus.declined,
      );
    });

    test('from iOS attendance details', () {
      expect(
        CalendarService.attendeeStatusOf(ios(IosAttendanceStatus.Declined)),
        AttendeeStatus.declined,
      );
    });

    test('whichever details field the platform populated — no Platform gate',
        () {
      // The details field that is present already says which platform we
      // are on. Gating on dart:io's Platform in addition can only ever
      // disagree with it, and disagreeing means losing a decline.
      for (final attendee in [
        android(AndroidAttendanceStatus.Declined),
        ios(IosAttendanceStatus.Declined),
      ]) {
        expect(CalendarService.attendeeStatusOf(attendee),
            AttendeeStatus.declined);
      }
    });
  });

  group('the two classes agree on every status', () {
    final attendees = <String, Attendee>{
      'android accepted': android(AndroidAttendanceStatus.Accepted),
      'android declined': android(AndroidAttendanceStatus.Declined),
      'android tentative': android(AndroidAttendanceStatus.Tentative),
      'android invited': android(AndroidAttendanceStatus.Invited),
      'ios accepted': ios(IosAttendanceStatus.Accepted),
      'ios declined': ios(IosAttendanceStatus.Declined),
      'ios tentative': ios(IosAttendanceStatus.Tentative),
      'ios pending': ios(IosAttendanceStatus.Pending),
      'no details at all': Attendee(emailAddress: 'guy@example.com'),
    };

    attendees.forEach((label, attendee) {
      test('$label reads identically on both sides of the cache', () {
        expect(
          RsvpMonitor.attendeeStatusStringForTest(attendee),
          CalendarService.attendeeStatusString(attendee),
          reason: 'the baseline is written by CalendarService and compared '
              'by RsvpMonitor — a divergence here hides declines',
        );
      });
    });
  });

  group('tentative stays distinct from pending', () {
    test('in the cached string', () {
      expect(
        CalendarService.attendeeStatusString(
          android(AndroidAttendanceStatus.Tentative),
        ),
        'tentative',
      );
      expect(
        CalendarService.attendeeStatusString(
          android(AndroidAttendanceStatus.Invited),
        ),
        isNot('tentative'),
      );
    });
  });

  test('an accepted attendee is accepted', () {
    // Not a control: under the old Platform gate this failed too, because
    // on any host that is neither iOS nor Android — every unit test run —
    // CalendarService returned unknown for *every* attendee. That is the
    // measure of how wide the gate's blast radius was.
    expect(
      CalendarService.attendeeStatusOf(
        android(AndroidAttendanceStatus.Accepted),
      ),
      AttendeeStatus.accepted,
    );
  });

  group('control case — this held before the convergence too', () {
    test('an attendee with no platform details is unknown, not declined',
        () {
      expect(
        CalendarService.attendeeStatusOf(Attendee(emailAddress: 'x@y.com')),
        AttendeeStatus.unknown,
      );
    });
  });
}
