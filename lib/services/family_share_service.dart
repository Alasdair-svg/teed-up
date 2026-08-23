/// Friends & family notify — a message, not a meeting (Growth Loop 01c).
///
/// "Let friends and family know" never touches the device calendar. It
/// builds a short FYI text — course, date, tee time, whichever player this
/// device is (if resolvable) — and hands it to the native OS share sheet,
/// alongside a standalone `.ics` file the recipient can tap to add to
/// their own calendar if they want a reminder. Nobody receives a calendar
/// invite they didn't ask for; there's no shared object for another player
/// to ever see.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/golf_round.dart';
import '../models/player.dart';
import 'calendar_service.dart';

/// Builds and shares the friends & family FYI message for a round.
class FamilyShareService {
  /// Default golf round duration — mirrors [CalendarService]'s own event
  /// duration so the `.ics` file matches what's on the organizer's own
  /// calendar.
  static const int _roundDurationMinutes = 270;

  /// Shares an FYI about [round] via the native OS share sheet, with a
  /// standalone `.ics` file attached for an opt-in calendar reminder.
  ///
  /// [selfPlayer] is whichever player in [round] this device belongs to
  /// (see [AppState.selfPlayerIn]) — used to personalize the message with
  /// a name instead of a generic "I'm playing". `null` degrades to
  /// generic first-person phrasing rather than guessing.
  static Future<void> share(GolfRound round, {Player? selfPlayer}) async {
    final message = buildMessage(round, selfPlayer: selfPlayer);

    try {
      final icsFile = await _buildIcsFile(round);
      await Share.shareXFiles([XFile(icsFile.path)], text: message);
    } catch (e, st) {
      // The .ics attachment is a nice-to-have, not the point of the
      // share — if building or attaching it fails for any reason, still
      // get the message itself out rather than blocking the whole action.
      debugPrint('[FamilyShareService] .ics attach failed, sharing text only: $e\n$st');
      await Share.share(message);
    }
  }

  /// Builds the FYI message text. Public for testing/preview.
  static String buildMessage(GolfRound round, {Player? selfPlayer}) {
    final dateFormat = DateFormat('EEEE d MMMM');
    final subject = selfPlayer != null ? '${selfPlayer.name} is' : "I'm";

    return '⛳ $subject playing golf at ${round.courseName}\n'
        '${dateFormat.format(round.date)} · ${round.formattedTeeTime}\n'
        '\n'
        '${CalendarService.growthLoopFooter}';
  }

  /// Builds a standalone `.ics` file for [round] in the temp directory,
  /// for the recipient to optionally add to their own calendar. Never
  /// written to the device calendar itself.
  static Future<File> _buildIcsFile(GolfRound round) async {
    final start = DateTime(
      round.date.year,
      round.date.month,
      round.date.day,
      round.teeTime.hour,
      round.teeTime.minute,
    ).toUtc();
    final end = start.add(const Duration(minutes: _roundDurationMinutes));
    final stamp = DateTime.now().toUtc();

    final ics = 'BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'PRODID:-//All Teed Up//EN\r\n'
        'BEGIN:VEVENT\r\n'
        'UID:${round.id}@teedup.golf\r\n'
        'DTSTAMP:${_icsDateTime(stamp)}\r\n'
        'DTSTART:${_icsDateTime(start)}\r\n'
        'DTEND:${_icsDateTime(end)}\r\n'
        'SUMMARY:${_icsEscape('⛳ ${round.courseName}')}\r\n'
        'LOCATION:${_icsEscape(round.courseName)}\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/teed_up_round_${round.id}.ics');
    await file.writeAsString(ics);
    return file;
  }

  /// Formats a UTC [DateTime] as an RFC 5545 `DATE-TIME` value.
  static String _icsDateTime(DateTime utc) {
    String pad(int n, [int width = 2]) => n.toString().padLeft(width, '0');
    return '${pad(utc.year, 4)}${pad(utc.month)}${pad(utc.day)}'
        'T${pad(utc.hour)}${pad(utc.minute)}${pad(utc.second)}Z';
  }

  /// Escapes text per RFC 5545 §3.3.11 (commas, semicolons, backslashes,
  /// newlines).
  static String _icsEscape(String text) => text
      .replaceAll('\\', '\\\\')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;')
      .replaceAll('\n', '\\n');
}
