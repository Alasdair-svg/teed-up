// Friends & family are informational. They must never come back as players.
//
// Reported from the field: a scan of a 4-player booking produced a round
// with a fifth player whose name "had no resemblance" to anything in the
// screenshot. It was a family member — and it never came from the image.
//
// The app adds friends & family to the calendar event as OPTIONAL attendees
// (see _pushFamilyToCalendar, and the "ℹ️ … notified — information only"
// line it writes into the description). Players are Required. But when an
// event was read back, _eventToGolfRound walked every attendee and skipped
// only the organiser — so on the next import or reconciliation the family
// member was promoted to a player.
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/services/calendar_service.dart';

void main() {
  final svc = CalendarService();

  Attendee who(String name, String email, AttendeeRole role,
          {bool organiser = false}) =>
      Attendee(
        name: name,
        emailAddress: email,
        role: role,
        isOrganiser: organiser,
      );

  Event golfEvent(List<Attendee> attendees) => Event(
        'cal-1',
        eventId: 'EVT-1',
        title: '⛳ Emirates Golf Club | 07:20 | Four Players | All Teed Up',
        start: TZDateTime.from(DateTime(2026, 9, 27, 7, 20), local),
        end: TZDateTime.from(DateTime(2026, 9, 27, 11, 50), local),
        attendees: attendees,
      );

  test('an Optional family attendee is not a player', () {
    final round = svc.eventToRoundForTest(
      golfEvent([
        who('Alasdair Kilgour', 'alasdair@example.com', AttendeeRole.Required),
        who('Marc McStay', 'marc@example.com', AttendeeRole.Required),
        who('Hamish Clark', 'hamish@example.com', AttendeeRole.Required),
        who('Guy Parsonage', 'guy@example.com', AttendeeRole.Required),
        // Told about the round, not playing in it.
        who('Anchin Kilgour', 'anchind@gmail.com', AttendeeRole.Optional),
      ]),
      'cal-1',
    );

    expect(round, isNotNull);
    expect(round!.players.map((p) => p.name), isNot(contains('Anchin Kilgour')));
    expect(round.players, hasLength(4),
        reason: 'the booking had four players; the fifth was informational');
  });

  test('the organiser is still excluded', () {
    final round = svc.eventToRoundForTest(
      golfEvent([
        who('Alasdair Kilgour', 'me@example.com', AttendeeRole.Required,
            organiser: true),
        who('Marc McStay', 'marc@example.com', AttendeeRole.Required),
      ]),
      'cal-1',
    );
    expect(round!.players.map((p) => p.name), ['Marc McStay']);
  });

  test('a round of Required attendees is unaffected', () {
    final round = svc.eventToRoundForTest(
      golfEvent([
        who('Marc McStay', 'marc@example.com', AttendeeRole.Required),
        who('Hamish Clark', 'hamish@example.com', AttendeeRole.Required),
      ]),
      'cal-1',
    );
    expect(round!.players, hasLength(2));
  });
}
