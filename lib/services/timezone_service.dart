/// Configures the `timezone` package to the device's actual zone.
///
/// Without this, `timezone`'s `local` is UTC. Every calendar event was built
/// with `TZDateTime(local, ..., hour, minute)`, so a 06:30 tee time was
/// written as 06:30 UTC and arrived in invites as 10:30 in Dubai (UTC+4) —
/// the app correctly read the booking, then wrote the wrong time.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Loads the zone database and points `local` at the device's zone.
///
/// Safe to call more than once. Never throws: a failure here must not stop
/// the app starting, and the fallback still beats UTC.
class TimezoneService {
  static bool _done = false;

  /// True once [configure] has pointed `local` at a real zone.
  static bool get isConfigured => _done;

  static Future<void> configure() async {
    if (_done) return;
    try {
      tzdata.initializeTimeZones();
    } catch (e) {
      debugPrint('[Timezone] failed to load the zone database: $e');
      return;
    }

    String? name;
    try {
      // v5 returns a TimezoneInfo; the IANA name is `identifier`.
      name = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (e) {
      debugPrint('[Timezone] device zone lookup failed: $e');
    }

    if (name != null && name.isNotEmpty) {
      try {
        tz.setLocalLocation(tz.getLocation(name));
        _done = true;
        debugPrint('[Timezone] local set to $name');
        return;
      } catch (e) {
        debugPrint('[Timezone] unknown zone "$name": $e');
      }
    }

    // Fallback: match the device's current UTC offset to any zone that
    // shares it. Not always the same city, but the wall-clock time it
    // produces is right, which is the part that matters for a tee time.
    final offset = DateTime.now().timeZoneOffset;
    try {
      final match = tz.timeZoneDatabase.locations.values.firstWhere(
        (l) => l.currentTimeZone.offset == offset.inMilliseconds,
      );
      tz.setLocalLocation(match);
      _done = true;
      debugPrint('[Timezone] fell back to ${match.name} for offset $offset');
    } catch (e) {
      debugPrint('[Timezone] no zone matched offset $offset — staying UTC: $e');
    }
  }
}
