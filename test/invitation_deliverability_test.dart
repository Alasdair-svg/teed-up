// The app reads RSVPs from the calendar event's attendee records. It has no
// backend and no mail access, so it can only see a decline the calendar
// SERVER syncs back onto the event.
//
// A local, subscribed or birthday calendar has no server. It accepts
// attendees, sends no invitation, and can never report a response — while
// looking exactly like a working calendar. Reported in the field: a player
// declined twice, the owner's inbox-reading bot caught both, the app caught
// neither.

import 'package:device_calendar/device_calendar.dart' show Calendar;
import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/services/calendar_service.dart';

Calendar _cal({String? type, String? account, String name = 'Calendar'}) =>
    Calendar(id: 'c', name: name, accountType: type, accountName: account);

void main() {
  group('canDeliverInvitations', () {
    test('a Google account calendar can deliver', () {
      expect(
        CalendarService.canDeliverInvitations(
            _cal(type: 'com.google', account: 'alasdair@theartesiangroup.com')),
        isTrue,
      );
    });

    test('the phone\'s local calendar cannot', () {
      // This is the trap: it accepts attendees and reports nothing, forever.
      expect(
        CalendarService.canDeliverInvitations(
            _cal(type: 'Local', account: 'Default')),
        isFalse,
      );
    });

    test('subscribed and birthday calendars cannot', () {
      expect(
          CalendarService.canDeliverInvitations(
              _cal(type: 'Subscribed', account: 'Subscribed Calendars')),
          isFalse);
      expect(
          CalendarService.canDeliverInvitations(
              _cal(type: 'Birthdays', account: 'Other')),
          isFalse);
    });

    test('an account without an address cannot deliver', () {
      expect(
        CalendarService.canDeliverInvitations(
            _cal(type: 'com.example.sync', account: 'My Phone')),
        isFalse,
      );
    });

    test('null is not deliverable rather than throwing', () {
      expect(CalendarService.canDeliverInvitations(null), isFalse);
    });
  });
}
