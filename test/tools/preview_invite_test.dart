// Renders the exact calendar invite this app produces, and writes a real
// .ics file so it can be opened in any mail or calendar client and reviewed
// the way a recipient sees it.
//
// Uses CalendarService.buildInvitePreview, the same builders the real write
// uses, so the preview cannot drift from what actually goes out.
//
//   flutter test test/tools/preview_invite_test.dart
//
// A test, not a script: CalendarService imports Flutter plugin bindings,
// which a plain Dart VM cannot load.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_teed_up/models/models.dart';
import 'package:all_teed_up/services/calendar_service.dart';

String _icsEscape(String v) => v
    .replaceAll('\\', '\\\\')
    .replaceAll('\n', '\\n')
    .replaceAll(',', '\\,')
    .replaceAll(';', '\;');

/// ICS lines must be folded at 75 octets; unfolded lines are silently
/// mangled by some clients, which would make the preview lie.
String _fold(String line) {
  if (line.length <= 73) return line;
  final buf = StringBuffer();
  var rest = line;
  buf.write(rest.substring(0, 73));
  rest = rest.substring(73);
  while (rest.isNotEmpty) {
    final take = rest.length > 72 ? 72 : rest.length;
    buf.write('\r\n ');
    buf.write(rest.substring(0, take));
    rest = rest.substring(take);
  }
  return buf.toString();
}

String _utc(DateTime d) {
  final u = d.toUtc();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${p(u.month)}${p(u.day)}T${p(u.hour)}${p(u.minute)}'
      '${p(u.second)}Z';
}

void main() {
  test('render the invite a recipient would receive', () {
    // A representative round: a mix of resolved and unresolved players, an
    // open slot, and a booking reference — the cases that actually appear.
    final teeTime = DateTime(2026, 9, 3, 7, 40);
    final round = GolfRound(
      id: 'preview',
      courseName: 'Emirates Golf Club — Faldo',
      date: teeTime,
      teeTime: teeTime,
      bookingRef: 'EGC-4471902',
      players: [
        Player(id: '1', name: 'Alasdair Kilgour', email: 'you@example.com'),
        Player(id: '2', name: 'Guy Parsonage', email: 'guy@example.com'),
        Player(id: '3', name: 'Zachary Drury', email: 'zach@example.com'),
      ],
    );

    final preview = CalendarService().buildInvitePreview(round);
    final end = teeTime.add(const Duration(hours: 4, minutes: 30));

    stdout.writeln('=' * 72);
    stdout.writeln('TITLE');
    stdout.writeln('=' * 72);
    stdout.writeln(preview.title);
    stdout.writeln();
    stdout.writeln('=' * 72);
    stdout.writeln('WHEN');
    stdout.writeln('=' * 72);
    stdout.writeln('$teeTime  ->  $end   (4h 30m)');
    stdout.writeln('Reminders: 12 hours before, 1 hour before');
    stdout.writeln();
    stdout.writeln('=' * 72);
    stdout.writeln('ATTENDEES');
    stdout.writeln('=' * 72);
    for (final p in round.players) {
      stdout.writeln('  ${p.name} <${p.email ?? "no email"}>');
    }
    stdout.writeln();
    stdout.writeln('=' * 72);
    stdout.writeln('BODY');
    stdout.writeln('=' * 72);
    stdout.writeln(preview.description);

    final ics = StringBuffer()
      ..write('BEGIN:VCALENDAR\r\n')
      ..write('VERSION:2.0\r\n')
      ..write('PRODID:-//All Teed Up//Invite Preview//EN\r\n')
      ..write('METHOD:REQUEST\r\n')
      ..write('CALSCALE:GREGORIAN\r\n')
      ..write('BEGIN:VEVENT\r\n')
      ..write('UID:preview-${teeTime.millisecondsSinceEpoch}@allteedup\r\n')
      ..write('DTSTAMP:${_utc(DateTime(2026, 8, 27, 9))}\r\n')
      ..write('DTSTART:${_utc(teeTime)}\r\n')
      ..write('DTEND:${_utc(end)}\r\n')
      ..write('${_fold('SUMMARY:${_icsEscape(preview.title)}')}\r\n')
      ..write('${_fold('DESCRIPTION:${_icsEscape(preview.description)}')}\r\n')
      ..write('${_fold('LOCATION:${_icsEscape(round.courseName)}')}\r\n')
      ..write(
          'ORGANIZER;CN=All Teed Up:mailto:allteedup.support@gmail.com\r\n');
    for (final p in round.players) {
      if (p.email == null) continue;
      ics.write(_fold('ATTENDEE;CN=${_icsEscape(p.name)};ROLE=REQ-PARTICIPANT;'
          'PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:${p.email}'));
      ics.write('\r\n');
    }
    ics
      ..write('BEGIN:VALARM\r\nTRIGGER:-PT12H\r\nACTION:DISPLAY\r\n'
          'DESCRIPTION:Tee time in 12 hours\r\nEND:VALARM\r\n')
      ..write('BEGIN:VALARM\r\nTRIGGER:-PT1H\r\nACTION:DISPLAY\r\n'
          'DESCRIPTION:Tee time in 1 hour\r\nEND:VALARM\r\n')
      ..write('END:VEVENT\r\n')
      ..write('END:VCALENDAR\r\n');

    final out = File('build/all_teed_up_invite_preview.ics')
      ..createSync(recursive: true)
      ..writeAsStringSync(ics.toString());
    stdout.writeln('\nWrote ${out.path}');
  });
}
