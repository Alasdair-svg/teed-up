// The RSVP baseline cache must not grow forever.
//
// The cache is a single JSON blob in SharedPreferences, decoded and
// re-encoded on every poll — and the foreground poll runs every 60
// seconds. Nothing ever removed an entry, so every event the monitor had
// ever seen stayed in it for the life of the install, making each of those
// 60-second ticks fractionally more expensive than the last.
//
// Pruning has to be careful in one specific way: a poll that returns no
// events is NOT evidence that the events are gone. Permission can be
// revoked, an account can be offline, a provider can hiccup. Deleting
// baselines on that basis would recreate the very first decline bug — the
// baseline that was never seeded — from inside the fix for a memory leak.
// So entries expire on age since last seen, not on absence from one poll.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_teed_up/services/rsvp_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final teeTime = now.add(const Duration(days: 1));

  Map<String, dynamic> liveEvent = {
    'eventId': 'EVT-LIVE',
    'title': '⛳ Emirates Golf Club | 07:30 | Guy Parsonage',
    'date': teeTime.toIso8601String().split('T').first,
    'start': teeTime,
    'attendees': {'guy@example.com': 'accepted'},
    'attendeeNames': {'guy@example.com': 'Guy Parsonage'},
  };

  void serveCalendar(List<Map<String, dynamic>> events) {
    RsvpMonitor.debugEventFetcher = (calendarId, start, end) async {
      return events.where((e) {
        final s = e['start'] as DateTime;
        return !s.isBefore(start) && !s.isAfter(end);
      }).toList();
    };
  }

  /// A cache holding one live event plus [staleCount] ancient ones, with
  /// last-seen stamps putting the ancient ones well outside any window the
  /// monitor polls.
  void primeCache({required int staleCount, required Duration staleAge}) {
    final cache = <String, dynamic>{
      'EVT-LIVE': {'guy@example.com': 'accepted'},
      for (var i = 0; i < staleCount; i++)
        'EVT-OLD-$i': {'someone$i@example.com': 'accepted'},
    };
    final seen = <String, dynamic>{
      'EVT-LIVE': now.toIso8601String(),
      for (var i = 0; i < staleCount; i++)
        'EVT-OLD-$i': now.subtract(staleAge).toIso8601String(),
    };

    SharedPreferences.setMockInitialValues({
      'teed_up_selected_calendar_id': 'cal-primary',
      'teed_up_rsvp_cache': jsonEncode(cache),
      'teed_up_rsvp_cache_seen': jsonEncode(seen),
    });
  }

  Future<Map<String, dynamic>> readCache() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonDecode(prefs.getString('teed_up_rsvp_cache')!)
        as Map<String, dynamic>;
  }

  tearDown(() => RsvpMonitor.debugEventFetcher = null);

  test('entries for events long out of the poll window are dropped',
      () async {
    primeCache(staleCount: 200, staleAge: const Duration(days: 200));
    serveCalendar([liveEvent]);

    await RsvpMonitor.instance.checkForChanges();

    final cache = await readCache();
    expect(cache.keys, ['EVT-LIVE']);
  });

  test('the live event keeps its baseline — pruning must not cause bug (a)',
      () async {
    primeCache(staleCount: 5, staleAge: const Duration(days: 200));
    serveCalendar([liveEvent]);

    await RsvpMonitor.instance.checkForChanges();

    final cache = await readCache();
    expect(cache['EVT-LIVE'], {'guy@example.com': 'accepted'});
  });

  test('an entry merely absent from one poll is kept', () async {
    primeCache(staleCount: 0, staleAge: Duration.zero);
    // Calendar read comes back empty — permission blip, account offline.
    serveCalendar(const []);

    await RsvpMonitor.instance.checkForChanges();

    final cache = await readCache();
    expect(
      cache.containsKey('EVT-LIVE'),
      isTrue,
      reason: 'a failed read must never wipe the baselines a decline is '
          'detected against',
    );
  });

  test('an entry with no last-seen stamp gets one instead of being deleted',
      () async {
    // The state of every install the moment this ships: a populated cache
    // and no bookkeeping alongside it.
    SharedPreferences.setMockInitialValues({
      'teed_up_selected_calendar_id': 'cal-primary',
      'teed_up_rsvp_cache': jsonEncode({
        'EVT-LEGACY': {'guy@example.com': 'accepted'},
      }),
    });
    serveCalendar(const []);

    await RsvpMonitor.instance.checkForChanges();

    final cache = await readCache();
    expect(cache.containsKey('EVT-LEGACY'), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('teed_up_rsvp_cache_seen'), contains('EVT-LEGACY'));
  });

  test('control — a decline is still detected while pruning runs', () async {
    primeCache(staleCount: 50, staleAge: const Duration(days: 200));
    serveCalendar([
      {...liveEvent, 'attendees': {'guy@example.com': 'declined'}},
    ]);

    final changes = await RsvpMonitor.instance.checkForChanges();

    expect(changes.single.isDecline, isTrue);
  });
}
