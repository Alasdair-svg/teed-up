// A round you organised must stay yours after a reinstall.
//
// The growth loop imports any ⛳ event it finds in the calendar. It used to
// mark every one of them isCreator:false — correct for a round a friend
// invited you to, and wrong for your own rounds once the app has forgotten
// it created them. The symptom is silent and permanent: Send invite, amend
// and RSVP cycling all disappear, and nothing explains why.
//
// Found on the Simulator by reinstalling to test something else, then
// noticing the round I had created an hour earlier had come back read-only.

import 'package:device_calendar/device_calendar.dart' show Attendee, Event;
import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/services/calendar_service.dart';

Attendee _att(String email, {bool organiser = false}) => Attendee(
      name: email.split('@').first,
      emailAddress: email,
      isOrganiser: organiser,
    );

void main() {
  group('own-event detection', () {
    test('an event with no attendees is mine', () {
      // The common case: a booking whose players had no resolved emails, so
      // the app wrote the event with nobody attached. An invitation always
      // carries attendees, so this cannot be one.
      final e = Event('cal', eventId: 'e1', title: '⛳ Earth Course');
      expect(CalendarService().isOwnEventForTest(e), isTrue);
    });

    test('attendees but no recorded organiser is mine', () {
      final e = Event('cal', eventId: 'e2', title: '⛳ Earth Course')
        ..attendees = [_att('marc@example.com')];
      expect(CalendarService().isOwnEventForTest(e), isTrue);
    });

    test('an organiser matching one of my calendar accounts is mine', () {
      final e = Event('cal', eventId: 'e3', title: '⛳ Earth Course')
        ..attendees = [
          _att('alasdair@theartesiangroup.com', organiser: true),
          _att('marc@example.com'),
        ];
      final svc = CalendarService()
        ..setOwnEmailsForTest({'alasdair@theartesiangroup.com'});
      expect(svc.isOwnEventForTest(e), isTrue);
    });

    test('an organiser who is someone else is NOT mine', () {
      // The growth loop's real purpose: a round a friend invited me to.
      final e = Event('cal', eventId: 'e4', title: '⛳ Earth Course')
        ..attendees = [
          _att('someone.else@example.com', organiser: true),
          _att('alasdair@theartesiangroup.com'),
        ];
      final svc = CalendarService()
        ..setOwnEmailsForTest({'alasdair@theartesiangroup.com'});
      expect(svc.isOwnEventForTest(e), isFalse);
    });

    test('organiser matching is case- and whitespace-insensitive', () {
      final e = Event('cal', eventId: 'e5', title: '⛳ Earth Course')
        ..attendees = [_att('  Alasdair@TheArtesianGroup.com  ', organiser: true)];
      final svc = CalendarService()
        ..setOwnEmailsForTest({'alasdair@theartesiangroup.com'});
      expect(svc.isOwnEventForTest(e), isTrue);
    });
  });
}
