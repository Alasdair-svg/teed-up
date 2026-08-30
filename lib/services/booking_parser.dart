/// Booking text parser for the All Teed Up golf booking app.
///
/// Extracts structured golf round data from raw OCR text using a
/// priority-ordered set of regex patterns. Each extraction method tries
/// multiple patterns — from most-specific to most-generic — and returns
/// the first successful match.
///
/// Supports booking confirmations from worldwide platforms including
/// Viya, GolfNow, TeeOff, BRS Golf, Club V1, ForeUp, and generic
/// email / SMS confirmations.
library;

import '../models/golf_round.dart';
import '../models/player.dart';

/// Static utility class that parses raw OCR text into [GolfRound] fields.
///
/// Each method is independent and returns `null` (or an empty list / zero)
/// when no match is found, allowing the UI to prompt for manual input on
/// missing fields.
///
/// ```dart
/// final round = BookingParser.parseBookingText(rawOcrText);
/// ```
class BookingParser {
  // Private constructor — all methods are static.
  BookingParser._();

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  /// Standard group size in golf.
  static const int _defaultGroupSize = 4;

  /// Month name → number lookup (case-insensitive keys stored lowercase).
  static const Map<String, int> _monthMap = {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  /// Day-of-week names stripped from input before parsing.
  static final RegExp _dayOfWeekPrefix = RegExp(
    r'(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|'
    r'mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)'
    r'[,.]?\s*',
    caseSensitive: false,
  );

  /// Ordinal suffixes stripped from day numbers (e.g. "15th" → "15").
  static final RegExp _ordinalSuffix = RegExp(r'(\d+)(?:st|nd|rd|th)\b');

  // ---------------------------------------------------------------------------
  // Main entry point
  // ---------------------------------------------------------------------------

  /// Parses [rawText] into a [GolfRound] with best-effort field extraction.
  ///
  /// Fields that cannot be determined are set to safe defaults:
  /// - [GolfRound.courseName] defaults to `'Unknown Course'`.
  /// - [GolfRound.date] defaults to [DateTime.now].
  /// - [GolfRound.teeTime] defaults to the round date at midnight.
  /// - [GolfRound.id] is set to `'pending_<timestamp>'` (assigned after calendar sync).
  static GolfRound parseBookingText(String rawText) {
    final players = extractPlayers(rawText);
    final date = extractDate(rawText) ?? DateTime.now();
    final teeTimeStr = extractTeeTime(rawText);
    final course = extractCourse(rawText);
    final bookingRef = extractBookingRef(rawText);

    // Parse tee time string into a DateTime anchored to the round date.
    final teeTime = _parseTeeTimeString(teeTimeStr, date);

    return GolfRound(
      id: 'pending_${DateTime.now().millisecondsSinceEpoch}',
      courseName: course ?? 'Unknown Course',
      date: date,
      teeTime: teeTime,
      players: players
          .map((name) => Player(
                id: 'player_${name.hashCode}',
                name: name,
              ))
          .toList(),
      location: extractLocation(rawText),
      bookingRef: bookingRef,
    );
  }

  /// Parses a tee time string (e.g. "6:10 AM", "14:30", "TBC") into
  /// a [DateTime] anchored to [roundDate].
  ///
  /// Returns [roundDate] with hour/minute set if parsing succeeds,
  /// or [roundDate] unchanged if the string is null or unrecognisable.
  static DateTime _parseTeeTimeString(String? teeTimeStr, DateTime roundDate) {
    if (teeTimeStr == null || teeTimeStr.toUpperCase() == 'TBC') {
      return roundDate;
    }

    // Try to parse "HH:MM AM/PM" or "HH:MM" (24-hour).
    final match = RegExp(
      r'(\d{1,2}):(\d{2})\s*(am|pm|AM|PM)?',
    ).firstMatch(teeTimeStr);

    if (match == null) return roundDate;

    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final meridiem = match.group(3)?.toUpperCase();

    if (meridiem == 'PM' && hour < 12) hour += 12;
    if (meridiem == 'AM' && hour == 12) hour = 0;

    return DateTime(
        roundDate.year, roundDate.month, roundDate.day, hour, minute);
  }

  // ---------------------------------------------------------------------------
  // Date extraction
  // ---------------------------------------------------------------------------

  /// Extracts a date from [text] trying 20+ international formats.
  ///
  /// Returns `null` when no recognisable date pattern is found.
  ///
  /// Supported formats (non-exhaustive):
  /// - `DD/MM/YYYY`, `MM/DD/YYYY`, `YYYY-MM-DD`
  /// - `DD-MM-YYYY`, `DD.MM.YYYY`
  /// - `January 15, 2026`, `15 January 2026`, `Jan 15, 2026`
  /// - `Saturday 15th June 2026`, `15th Jun 2026`
  /// - `15-Jun-2026`, `Jun-15-2026`
  /// - `Date: 15/06/2026` (labelled variants)
  static DateTime? extractDate(String text) {
    // Normalise: remove day-of-week prefixes, ordinal suffixes, extra spaces.
    var cleaned = text.replaceAll(_dayOfWeekPrefix, '');
    cleaned = cleaned.replaceAllMapped(
      _ordinalSuffix,
      (m) => m.group(1)!,
    );

    // --- Labelled date (highest priority) ---
    // "Date: 15/06/2026" or "Date: June 15, 2026"
    final labelledMatch = RegExp(
      r'(?:date|booking\s*date|round\s*date|play\s*date)\s*[:]\s*(.+)',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (labelledMatch != null) {
      final sub = labelledMatch.group(1)!.trim();
      final parsed = _tryAllDateFormats(sub);
      if (parsed != null) return parsed;
    }

    // --- Try all formats on the full text ---
    return _tryAllDateFormats(cleaned);
  }

  /// Tries every date regex pattern against [text] and returns the first hit.
  static DateTime? _tryAllDateFormats(String text) {
    // 1) ISO 8601: YYYY-MM-DD
    final iso = RegExp(r'\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b');
    final isoMatch = iso.firstMatch(text);
    if (isoMatch != null) {
      final dt = _buildDate(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
      if (dt != null) return dt;
    }

    // 2) DD/MM/YYYY or DD-MM-YYYY or DD.MM.YYYY (most common outside US)
    final dmy = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})\b');
    final dmyMatch = dmy.firstMatch(text);
    if (dmyMatch != null) {
      final a = int.parse(dmyMatch.group(1)!);
      final b = int.parse(dmyMatch.group(2)!);
      final year = int.parse(dmyMatch.group(3)!);
      // Heuristic: if first number > 12 it's definitely the day (DD/MM/YYYY).
      // If second number > 12 it's MM/DD/YYYY. Otherwise assume DD/MM/YYYY.
      if (a > 12) {
        return _buildDate(year, b, a); // DD/MM/YYYY
      } else if (b > 12) {
        return _buildDate(year, a, b); // MM/DD/YYYY
      } else {
        return _buildDate(year, b, a); // Default DD/MM/YYYY (international)
      }
    }

    // 3) DD/MM/YY (two-digit year)
    final dmyShort = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2})\b');
    final dmyShortMatch = dmyShort.firstMatch(text);
    if (dmyShortMatch != null) {
      final a = int.parse(dmyShortMatch.group(1)!);
      final b = int.parse(dmyShortMatch.group(2)!);
      final shortYear = int.parse(dmyShortMatch.group(3)!);
      final year = shortYear + (shortYear < 50 ? 2000 : 1900);
      if (a > 12) {
        return _buildDate(year, b, a);
      } else if (b > 12) {
        return _buildDate(year, a, b);
      } else {
        return _buildDate(year, b, a);
      }
    }

    // 4) "15 January 2026" / "15 Jan 2026"
    final dayMonthYear = RegExp(
      r'\b(\d{1,2})\s+'
      r'(january|february|march|april|may|june|july|august|september|october|november|december|'
      r'jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)'
      r'[\s,]+(\d{4})\b',
      caseSensitive: false,
    );
    final dmyWordMatch = dayMonthYear.firstMatch(text);
    if (dmyWordMatch != null) {
      final day = int.parse(dmyWordMatch.group(1)!);
      final month = _monthMap[dmyWordMatch.group(2)!.toLowerCase()];
      final year = int.parse(dmyWordMatch.group(3)!);
      if (month != null) return _buildDate(year, month, day);
    }

    // 5) "January 15, 2026" / "Jan 15 2026"
    final monthDayYear = RegExp(
      r'\b(january|february|march|april|may|june|july|august|september|october|november|december|'
      r'jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)'
      r'[\s]+(\d{1,2})[,\s]+(\d{4})\b',
      caseSensitive: false,
    );
    final mdyWordMatch = monthDayYear.firstMatch(text);
    if (mdyWordMatch != null) {
      final month = _monthMap[mdyWordMatch.group(1)!.toLowerCase()];
      final day = int.parse(mdyWordMatch.group(2)!);
      final year = int.parse(mdyWordMatch.group(3)!);
      if (month != null) return _buildDate(year, month, day);
    }

    // 6) "15-Jun-2026" or "15/Jun/2026"
    final dayMonSepYear = RegExp(
      r'\b(\d{1,2})[/\-]'
      r'(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)'
      r'[/\-](\d{4})\b',
      caseSensitive: false,
    );
    final dmsyMatch = dayMonSepYear.firstMatch(text);
    if (dmsyMatch != null) {
      final day = int.parse(dmsyMatch.group(1)!);
      final month = _monthMap[dmsyMatch.group(2)!.toLowerCase()];
      final year = int.parse(dmsyMatch.group(3)!);
      if (month != null) return _buildDate(year, month, day);
    }

    // 7) "Jun-15-2026" or "Jun/15/2026"
    final monDayYear = RegExp(
      r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)'
      r'[/\-](\d{1,2})[/\-](\d{4})\b',
      caseSensitive: false,
    );
    final mdySepMatch = monDayYear.firstMatch(text);
    if (mdySepMatch != null) {
      final month = _monthMap[mdySepMatch.group(1)!.toLowerCase()];
      final day = int.parse(mdySepMatch.group(2)!);
      final year = int.parse(mdySepMatch.group(3)!);
      if (month != null) return _buildDate(year, month, day);
    }

    // 8) "January 15" / "Jun 15" (no year — assume current or next occurrence)
    final monthDay = RegExp(
      r'\b(january|february|march|april|may|june|july|august|september|october|november|december|'
      r'jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)'
      r'[\s]+(\d{1,2})\b',
      caseSensitive: false,
    );
    final mdNoYearMatch = monthDay.firstMatch(text);
    if (mdNoYearMatch != null) {
      final month = _monthMap[mdNoYearMatch.group(1)!.toLowerCase()];
      final day = int.parse(mdNoYearMatch.group(2)!);
      if (month != null) {
        final now = DateTime.now();
        var year = now.year;
        final candidate = _buildDate(year, month, day);
        if (candidate != null && candidate.isBefore(now)) {
          return _buildDate(year + 1, month, day);
        }
        return candidate;
      }
    }

    // 9) "15 January" / "15 Jun" (no year)
    final dayMonth = RegExp(
      r'\b(\d{1,2})\s+'
      r'(january|february|march|april|may|june|july|august|september|october|november|december|'
      r'jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b',
      caseSensitive: false,
    );
    final dmNoYearMatch = dayMonth.firstMatch(text);
    if (dmNoYearMatch != null) {
      final day = int.parse(dmNoYearMatch.group(1)!);
      final month = _monthMap[dmNoYearMatch.group(2)!.toLowerCase()];
      if (month != null) {
        final now = DateTime.now();
        var year = now.year;
        final candidate = _buildDate(year, month, day);
        if (candidate != null && candidate.isBefore(now)) {
          return _buildDate(year + 1, month, day);
        }
        return candidate;
      }
    }

    return null;
  }

  /// Safely builds a [DateTime], returning `null` for invalid combinations.
  static DateTime? _buildDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (year < 1900 || year > 2100) return null;
    try {
      final dt = DateTime(year, month, day);
      // DateTime auto-adjusts overflows (e.g. Feb 30 → Mar 2).
      // Reject if day doesn't match what we asked for.
      if (dt.month != month || dt.day != day) return null;
      return dt;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Tee time extraction
  // ---------------------------------------------------------------------------

  /// Matches "made on"/"booked on"/etc footer timestamps (e.g. "Booking made
  /// on 29 Jul 2026 at 06:04") — a near-universal receipt footer across many
  /// booking/order formats that must never be mistaken for the actual
  /// event's date/time.
  static final RegExp _metadataFooterPrefix = RegExp(
    r'\b(?:made|booked|created|placed|purchased|ordered|generated)\s+on\b',
    caseSensitive: false,
  );

  /// Extracts a tee time from [text].
  ///
  /// Returns a normalised time string (e.g. `"6:10 AM"`, `"14:30"`) or `null`.
  ///
  /// Recognised patterns:
  /// - `Tee Time: 06:10`, `Start: 2:30 PM`
  /// - `Time: 14:30`, `Tee-off: 7:00am`
  /// - A time on the same line as a recognisable date (e.g.
  ///   `"19 Aug 2026, 06:25"`) — common in card/list-style booking UIs that
  ///   don't label fields at all.
  /// - Standalone `HH:MM AM/PM` or 24-hour `HH:MM`
  static String? extractTeeTime(String text) {
    // --- Time on the same line as a date (highest priority) ---
    // Checked first so it can't be shadowed by an unrelated "made on ... at
    // HH:MM" footer timestamp appearing later in the text. Skips lines that
    // are themselves that kind of footer.
    for (final line in text.split('\n')) {
      if (_metadataFooterPrefix.hasMatch(line)) continue;
      if (extractDate(line) == null) continue;
      final onDateLine = RegExp(
        r'(\d{1,2}:\d{2})\s*(am|pm|AM|PM|a\.m\.|p\.m\.)?',
      ).firstMatch(line);
      if (onDateLine != null) {
        return _formatTime(onDateLine.group(1)!, onDateLine.group(2));
      }
    }

    // --- Labelled patterns ---
    final labelled = RegExp(
      r'(?:tee\s*time|tee[\s\-]*off|start\s*time|time|starts?)\s*[:]\s*'
      r'(\d{1,2}:\d{2})\s*(am|pm|AM|PM|a\.m\.|p\.m\.)?',
      caseSensitive: false,
    );
    final labelledMatch = labelled.firstMatch(text);
    if (labelledMatch != null) {
      return _formatTime(labelledMatch.group(1)!, labelledMatch.group(2));
    }

    // --- "at HH:MM AM/PM" (skipping "made/booked/created on ... at" footers) ---
    final atTime = RegExp(
      r'\bat\s+(\d{1,2}:\d{2})\s*(am|pm|AM|PM|a\.m\.|p\.m\.)?',
      caseSensitive: false,
    );
    for (final atMatch in atTime.allMatches(text)) {
      final lineStart = text.lastIndexOf('\n', atMatch.start) + 1;
      final lineEnd = text.indexOf('\n', atMatch.end);
      final line = text.substring(
        lineStart,
        lineEnd == -1 ? text.length : lineEnd,
      );
      if (_metadataFooterPrefix.hasMatch(line)) continue;
      return _formatTime(atMatch.group(1)!, atMatch.group(2));
    }

    // --- "HH:MM AM/PM" with mandatory meridiem ---
    final withMeridiem = RegExp(
      r'\b(\d{1,2}:\d{2})\s*(am|pm|AM|PM|a\.m\.|p\.m\.)\b',
    );
    final meridiemMatch = withMeridiem.firstMatch(text);
    if (meridiemMatch != null) {
      return _formatTime(meridiemMatch.group(1)!, meridiemMatch.group(2));
    }

    // --- Standalone HH:MM (24-hour, only valid golf hours 05:00–20:59) ---
    final standalone = RegExp(r'\b((?:0[5-9]|1[0-9]|20):\d{2})\b');
    final standaloneMatch = standalone.firstMatch(text);
    if (standaloneMatch != null) {
      return standaloneMatch.group(1);
    }

    return null;
  }

  /// Formats a raw time string with an optional [meridiem] into a
  /// consistent display format.
  static String _formatTime(String raw, String? meridiem) {
    if (meridiem == null || meridiem.isEmpty) return raw;
    final m = meridiem.replaceAll('.', '').toUpperCase().trim();
    return '$raw $m';
  }

  // ---------------------------------------------------------------------------
  // Course name extraction
  // ---------------------------------------------------------------------------

  /// Extracts a golf course name from [text].
  ///
  /// Looks for keywords like "Golf Club", "Golf Course", "Country Club",
  /// "Links", "GC", and UAE-specific course names ("Earth Course",
  /// "Majlis Course", "Fire Course", "Faldo Course").
  ///
  /// Returns the full matched course name or `null`.
  static String? extractCourse(String text) {
    // --- Labelled: "Course: Dubai Hills Golf Club" ---
    final labelled = RegExp(
      r'(?:course|club|venue|location|facility)\s*[:]\s*(.+)',
      caseSensitive: false,
    );
    final labelledMatch = labelled.firstMatch(text);
    if (labelledMatch != null) {
      final name = _cleanCourseName(labelledMatch.group(1)!);
      if (name.isNotEmpty) return name;
    }

    // --- "Welcome to [Course Name]" ---
    final welcome = RegExp(
      r'welcome\s+to\s+(.+?)(?:\n|$)',
      caseSensitive: false,
    );
    final welcomeMatch = welcome.firstMatch(text);
    if (welcomeMatch != null) {
      final name = _cleanCourseName(welcomeMatch.group(1)!);
      if (name.isNotEmpty) return name;
    }

    // --- Known keyword patterns ---
    // Capture word(s) before + the keyword + optional word(s) after.
    final keywords = [
      // Full names with suffixes
      r"[\w\s'-]+?\s+Golf\s+(?:Club|Course|Resort|Academy|Centre|Center)",
      r"[\w\s'-]+?\s+Country\s+Club",
      r"[\w\s'-]+?\s+Golf\s+&\s+Country\s+Club",
      r"[\w\s'-]+?\s+Links",
      r"[\w\s'-]+?\s+GC\b",
      // UAE-specific course names (sub-courses within a club)
      r"(?:Earth|Majlis|Faldo|Fire|Water|Wind|Championship|Academy)\s+Course",
    ];

    for (final pattern in keywords) {
      final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
      if (match != null) {
        final name = _cleanCourseName(match.group(0)!);
        if (name.isNotEmpty) return name;
      }
    }

    // --- Last resort: first heading-like line, for venues/activities that
    // don't use "Golf"/"Club"/"Course" wording at all (e.g. a padel or
    // tennis booking) — not just golf-specific formats. ---
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(r'\d').hasMatch(trimmed))
        continue; // dates/times/prices/counts
      final words = trimmed.split(RegExp(r'\s+'));
      if (words.length < 2 || words.length > 6) continue;
      if (!words.every((w) => RegExp(r'^[A-Z]').hasMatch(w))) continue;
      if (_looksLikeScreenChrome(trimmed)) continue;
      final name = _cleanCourseName(trimmed);
      if (name.isNotEmpty) return name;
    }

    return null;
  }

  /// Whether [line] reads as a screen title / status / nav chrome rather
  /// than a venue name — matched by *containing* any of these marker words
  /// (not an exact-phrase list) so it generalises across apps regardless of
  /// exact wording ("Padel Court Booking", "Tee Time Booking", "Order
  /// Confirmation Details" all get caught the same way).
  static bool _looksLikeScreenChrome(String line) {
    const markers = {
      'booking',
      'confirmation',
      'confirmed',
      'receipt',
      'summary',
      'details',
      'reservation',
      'welcome',
      'thank',
      'share',
      'back',
      'home',
      'total',
      'checkout',
      'itinerary',
    };
    final words = line.toLowerCase().split(RegExp(r'\s+'));
    return words.any(markers.contains);
  }

  /// Trims and cleans a raw course name string.
  static String _cleanCourseName(String raw) {
    return raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r"[^\w\s\&\'-]"), '')
        .trim();
  }

  // ---------------------------------------------------------------------------
  // Player extraction
  // ---------------------------------------------------------------------------

  /// Extracts player names from [text].
  ///
  /// Tries (in order):
  /// 1. "Player N" pattern — same-line "Player N: Name" / "Player N Name",
  ///    or "Player N" alone on its line with the name on the following
  ///    non-blank line (common in card/list-UI layouts with no colon
  ///    separator at all, e.g. Viya's actual app format).
  /// 2. Lines under a "Players" / "Golfers" / "Group" heading.
  /// 3. Comma-separated names after a label (e.g. "Players: A, B, C").
  /// 4. Numbered list items (e.g. "1. John Smith").
  /// 5. "Name:" / "Golfer:" pattern used by some platforms.
  /// 6. Last resort: any line elsewhere that looks like a real person's
  ///    name, for formats none of the above recognise at all.
  ///
  /// Placeholder names ("TBC", "TBC TBC") are treated as unfilled slots,
  /// not players — [ScanService] pads the remainder with TBC players based
  /// on [extractOpenSlots].
  ///
  /// Results are de-duplicated and capped at 8 (two groups max).
  /// Row content that is never a player's name.
  ///
  /// A booking row carries a price and a membership tier alongside the name.
  /// Without this, "AED 0.00" was accepted AS a name — it survived
  /// _cleanPlayerName as "AED 000" and passed _isValidName — so a player was
  /// not merely dropped but replaced by a price in the review list.
  static bool _isNonNameRowNoise(String candidate) {
    final v = candidate.trim();
    if (v.isEmpty) return true;

    // Any currency code or amount.
    if (RegExp(
      r'^(?:aed|usd|gbp|eur|sar|qar|omr|bhd|kwd|inr|rs|\$|£|€)\b',
      caseSensitive: false,
    ).hasMatch(v)) {
      return true;
    }
    // Digits with no letters at all — amounts, totals, counts.
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return true;
    // A trailing bare number is what "AED 0.00" degrades into once the
    // currency symbol and punctuation are stripped.
    if (RegExp(r'^[A-Za-z]{2,4}\s*\d[\d.,]*$').hasMatch(v)) return true;

    // Membership tiers and row labels seen on real bookings.
    const labels = {
      'member',
      'members',
      'guest',
      'guests',
      'visitor',
      'visitors',
      'homeowner single',
      'homeowner',
      'single',
      'jge member',
      'holes',
      'total',
      'booking confirmed',
      'player details',
      'confirmed',
      'paid',
      'unpaid',
      'free',
    };
    final lower = v.toLowerCase();
    if (labels.contains(lower)) return true;
    // "<something> Member" / "<something> Guest" tier lines.
    if (RegExp(r'\b(member|guest|visitor)$', caseSensitive: false)
        .hasMatch(lower)) {
      return true;
    }
    return false;
  }

  static List<String> extractPlayers(String text) {
    final Set<String> found = {};

    // --- 1) "Player N" — same line, or name on the next non-blank line ---
    final lines = text.split('\n');
    // A bare "Player" with no digit counts as a marker too. On a real Viya
    // booking ML Kit emitted the first row's label as "Player" on its own —
    // the "1" was never recognised — so a numbered-only pattern matched
    // players 2, 3 and 4, returned early, and lost player 1 altogether.
    final playerLine =
        RegExp(r'^\s*player\s*\d*\s*[:.]?\s*(.*)$', caseSensitive: false);
    for (var i = 0; i < lines.length; i++) {
      final m = playerLine.firstMatch(lines[i]);
      if (m == null) continue;

      final sameLine = _cleanPlayerName(m.group(1) ?? '');
      if (sameLine.isNotEmpty) {
        if (_isValidName(sameLine) && !_isTbcPlaceholder(sameLine)) {
          found.add(sameLine);
        }
        continue;
      }

      // "Player N" alone on its line — the name is on a following line.
      //
      // Keep looking until a NAME is found, rather than giving up on the
      // first non-blank line. Each row in a booking carries a price and a
      // membership label as well as a name, and the order they arrive in is
      // decided by the OCR engine's block ordering, not the layout. On a
      // real 4-player booking the price for player 3 was emitted before the
      // name, so the old code took "AED 0.00", failed to recognise it, and
      // broke out — losing Michael Murphy entirely while the same
      // screenshot picked from the gallery found all four.
      for (var j = i + 1; j < lines.length && j < i + 5; j++) {
        final candidate = _cleanPlayerName(lines[j]);
        if (candidate.isEmpty) continue;
        // Stop if the next player's marker is reached: the name for this one
        // is genuinely absent rather than further down.
        if (playerLine.hasMatch(lines[j])) break;
        if (_isNonNameRowNoise(candidate)) continue;
        if (_isValidName(candidate) && !_isTbcPlaceholder(candidate)) {
          found.add(candidate);
          break;
        }
      }
    }
    if (found.isNotEmpty) {
      // A booking that states its own group size ("4 Player(s)") is the
      // authority on how many names should have been found. When the marker
      // pass comes up short, sweep the text for names it could not reach
      // rather than returning a group that is silently a player light.
      final declared = extractDeclaredPlayerCount(text);
      if (declared != null && found.length < declared) {
        for (final line in lines) {
          if (found.length >= declared) break;
          final candidate = _cleanPlayerName(line);
          if (candidate.isEmpty || candidate != line.trim()) continue;
          if (_isNonNameRowNoise(candidate)) continue;
          if (_isValidName(candidate) && !_isTbcPlaceholder(candidate)) {
            found.add(candidate);
          }
        }
      }
      return found.take(8).toList();
    }

    // --- 2) Lines under a header: "Players:", "Golfers:", "Group:" ---
    final headerPattern = RegExp(
      r'(?:players?|golfers?|group\s*members?|attendees?|participants?)\s*[:]\s*\n((?:.+\n?)+)',
      caseSensitive: false,
    );
    final headerMatch = headerPattern.firstMatch(text);
    if (headerMatch != null) {
      final block = headerMatch.group(1)!;
      for (final line in block.split('\n')) {
        // Strip leading numbers, bullets, dashes.
        final cleaned = line
            .replaceAll(RegExp(r'^\s*[\d]+[.)]\s*'), '')
            .replaceAll(RegExp(r'^\s*[-•*]\s*'), '')
            .trim();
        if (_isValidName(cleaned)) found.add(cleaned);
        // Stop at blank line or a new section header.
        if (line.trim().isEmpty ||
            RegExp(r'^[A-Z][a-z]+:').hasMatch(line.trim())) {
          break;
        }
      }
      if (found.isNotEmpty) return found.take(8).toList();
    }

    // --- 3) Comma-separated after label ---
    final csvLabel = RegExp(
      r'(?:players?|golfers?|group|names?)\s*[:]\s*(.+)',
      caseSensitive: false,
    );
    final csvMatch = csvLabel.firstMatch(text);
    if (csvMatch != null) {
      final names = csvMatch.group(1)!.split(RegExp(r'[,;&]+'));
      for (final raw in names) {
        final name = _cleanPlayerName(raw);
        if (_isValidName(name)) found.add(name);
      }
      if (found.isNotEmpty) return found.take(8).toList();
    }

    // --- 4) Numbered list anywhere: "1. John Smith", "2) Jane Doe" ---
    final numbered = RegExp(
      r'^\s*\d+[.)]\s+([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)+)',
      multiLine: true,
    );
    for (final m in numbered.allMatches(text)) {
      final name = _cleanPlayerName(m.group(1)!);
      if (_isValidName(name)) found.add(name);
    }
    if (found.isNotEmpty) return found.take(8).toList();

    // --- 5) "Name:" / "Name -" pattern used by some platforms ---
    final nameColon = RegExp(
      r'(?:name|golfer|player)\s*[:]\s*(.+)',
      caseSensitive: false,
    );
    for (final m in nameColon.allMatches(text)) {
      final name = _cleanPlayerName(m.group(1)!);
      if (_isValidName(name) && !_isTbcPlaceholder(name)) found.add(name);
    }
    if (found.isNotEmpty) return found.take(8).toList();

    // --- 6) Last resort: any line that looks like a real person's name,
    // for layouts none of the labelled/structured strategies above
    // recognise at all. Deliberately conservative — [_isValidName] already
    // filters length/word-count/blacklist, and a full-line match (not just
    // a substring) avoids grabbing partial phrases out of longer sentences.
    for (final line in lines) {
      final candidate = _cleanPlayerName(line);
      if (candidate.isEmpty || candidate != line.trim()) continue;
      if (_isNonNameRowNoise(candidate)) continue;
      if (_isValidName(candidate) && !_isTbcPlaceholder(candidate)) {
        found.add(candidate);
      }
    }

    return found.take(8).toList();
  }

  /// The group size the booking states for itself — "4 Player(s)",
  /// "3 golfers". Returns `null` when the text makes no such claim, in
  /// which case callers must not assume a size.
  static int? extractDeclaredPlayerCount(String text) {
    final m = RegExp(
      r'\b(\d+)\s*(?:player|golfer)\(?s?\)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    final n = int.parse(m.group(1)!);
    return (n >= 1 && n <= 8) ? n : null;
  }

  /// Cleans a raw player name string.
  static String _cleanPlayerName(String raw) {
    return raw
        .replaceAll(RegExp(r"[^\w\s\'-]"), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Whether [name] is a "to be confirmed" placeholder (e.g. "TBC", "TBC
  /// TBC") rather than a real player — these should become an open/TBC
  /// slot (see [extractOpenSlots]), not a named player.
  static bool _isTbcPlaceholder(String name) {
    final compact = name.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    return compact == 'TBC' || compact == 'TBC TBC';
  }

  /// Heuristic: a "valid" player name has 2–5 words, each starting
  /// with an uppercase letter, total length 3–60 characters, and doesn't
  /// contain non-name keywords generic across booking/reservation apps
  /// (golf-specific, UI chrome, or otherwise).
  static bool _isValidName(String name) {
    if (name.length < 3 || name.length > 60) return false;

    final words = name.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length < 2 || words.length > 5) return false;

    // Reject common false positives from booking text.
    final blacklist = {
      // Golf-specific.
      'golf', 'club', 'course', 'tee', 'holes', 'round', 'buggy', 'cart',
      'caddy', 'green', 'fee',
      // Generic booking/receipt vocabulary.
      'booking', 'confirmation', 'reference', 'time', 'date', 'player',
      'players', 'slot', 'group', 'total', 'amount', 'payment', 'receipt',
      'invoice', 'rate', 'price', 'open', 'available', 'booked', 'reserved',
      'unknown', 'details', 'summary', 'order', 'reservation', 'venue',
      'location', 'member', 'members', 'single', 'homeowner', 'guest',
      // Generic app chrome (nav bars, buttons, headers).
      'back', 'home', 'share', 'cancel', 'modify', 'edit', 'rewards',
      'partners', 'card', 'confirmed', 'pending', 'welcome', 'my',
    };
    for (final word in words) {
      if (blacklist.contains(word.toLowerCase())) return false;
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // Location extraction
  // ---------------------------------------------------------------------------

  /// The venue's location — an address, city or resort — as distinct from the
  /// course name.
  ///
  /// A tee time is useless if you cannot find the course, and until now the
  /// calendar event's location field was just the course name repeated, which
  /// tells a maps app nothing it did not already have.
  ///
  /// Returns `null` rather than a guess. A wrong address is worse than none:
  /// it sends someone to the wrong place with confidence.
  static String? extractLocation(String text) {
    // --- 1) Explicitly labelled ---
    final labelled = RegExp(
      r'(?:address|location|venue\s*address|where)\s*[:]\s*(.+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (labelled != null) {
      final v = _cleanLocation(labelled.group(1)!);
      if (v != null) return v;
    }

    // --- 2) A line carrying a recognised thoroughfare word. ---
    //
    // Deliberately NOT "a line starting with a number", which was the first
    // attempt: that shape also matches "30 Aug 2026, 06:30" and
    // "4 Player(s)", both of which it duly returned as addresses. A street
    // word or a postcode is required. Missing a real address is a small
    // loss; writing "4 Player(s)" into the calendar's location field is a
    // visible defect.
    final street = RegExp(
      r'^\s*(.{4,80}\b(?:street|st\.?|road|rd\.?|avenue|ave\.?|drive|dr\.?|'
      r'lane|ln\.?|boulevard|blvd\.?|way|parkway|highway|hwy\.?)\b.{0,40})$',
      caseSensitive: false,
      multiLine: true,
    );
    for (final m in street.allMatches(text)) {
      final v = _cleanLocation(m.group(1) ?? '');
      if (v != null) return v;
    }

    // --- 3) A postcode-bearing line, which is an address even when the
    // street word is missing. Covers UK, US ZIP and generic alphanumerics. ---
    final postcode = RegExp(
      r'^(.{4,90}?\b(?:[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}|\d{5}(?:-\d{4})?)\b.{0,30})$',
      multiLine: true,
    );
    for (final m in postcode.allMatches(text)) {
      final v = _cleanLocation(m.group(1)!);
      if (v != null) return v;
    }

    return null;
  }

  /// Trims a candidate location and rejects the ones that are really
  /// something else — a price, a booking reference, a date, or the course
  /// name on its own.
  static String? _cleanLocation(String raw) {
    var v = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    v = v.replaceAll(RegExp(r'^[\-–—:,\s]+|[\-–—:,\s]+$'), '');
    if (v.length < 5 || v.length > 120) return null;

    // Must contain letters — a bare number is a reference, not a place.
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return null;

    // Currency, times and booking refs masquerading as addresses.
    if (RegExp(r'^(?:aed|usd|gbp|eur|sar|\$|£|€)\b', caseSensitive: false)
        .hasMatch(v)) {
      return null;
    }
    if (RegExp(r'^\d{1,2}[:.]\d{2}').hasMatch(v)) return null;

    // Dates read as street addresses: "30 Aug 2026, 06:30" begins with a
    // number followed by words, which is exactly the shape of "12 Oak
    // Avenue". Caught by a test rather than by a tester, but it would have
    // written the booking date into the calendar's location field.
    const months = r'jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec';
    if (RegExp('\\b(?:$months)', caseSensitive: false).hasMatch(v) &&
        RegExp(r'\b\d{4}\b').hasMatch(v)) {
      return null;
    }
    if (RegExp(r'^\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}').hasMatch(v)) {
      return null;
    }
    // Any candidate that still carries a clock time is a schedule line.
    if (RegExp(r'\d{1,2}[:.]\d{2}\s*(?:am|pm)?\s*$', caseSensitive: false)
        .hasMatch(v)) {
      return null;
    }
    if (RegExp(
            r'\b(?:booking|ref|reference|confirmation|player|players|golfer|'
            r'golfers|hole|holes|slot|slots|guest|member)\b',
            caseSensitive: false)
        .hasMatch(v)) {
      return null;
    }
    return v;
  }

  // ---------------------------------------------------------------------------
  // Booking reference extraction
  // ---------------------------------------------------------------------------

  /// Extracts a booking reference / confirmation number from [text].
  ///
  /// Recognised patterns:
  /// - `Ref: ABC123`, `Ref #ABC123`, `Reference: ABC-123`
  /// - `Booking #12345`, `Booking ID: XYZ789`
  /// - `Confirmation: XYZ`, `Confirmation #ABC`
  /// - `Reservation #12345`, `Reservation ID: ABC`
  /// - `Order #12345`
  static String? extractBookingRef(String text) {
    final patterns = [
      // Explicit labelled references.
      RegExp(
        r'(?:booking\s*(?:ref(?:erence)?|id|no|number|#)|'
        r'ref(?:erence)?\s*(?:no|number|#|:)|'
        r'confirmation\s*(?:no|number|#|code|:)|'
        r'reservation\s*(?:no|number|#|id|:)|'
        r'order\s*(?:no|number|#|:))'
        r'\s*[:#]?\s*([A-Za-z0-9][\w\-]{2,20})',
        caseSensitive: false,
      ),
      // Short-form: "Ref: ABC123" or "Ref #ABC123"
      RegExp(
        r'\bref\s*[:#]\s*([A-Za-z0-9][\w\-]{2,20})',
        caseSensitive: false,
      ),
      // "Confirmation ABC123"
      RegExp(
        r'\bconfirmation\s+([A-Za-z0-9][\w\-]{3,20})',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(1)!.trim();
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Open slots extraction
  // ---------------------------------------------------------------------------

  /// Extracts the number of open (unfilled) slots from [text].
  ///
  /// If no explicit slot information is found, calculates as
  /// `4 - playerCount` (clamped to 0–4).
  ///
  /// Recognised patterns:
  /// - `2 slots available`, `3 open slots`, `1 spot left`
  /// - `2/4 booked`, `3/4 players`, `1/4 filled`
  /// - `X of 4 slots taken`
  static int extractOpenSlots(String text, int playerCount) {
    // --- "N slots available / open" ---
    final slotsAvailable = RegExp(
      r'(\d+)\s+(?:slots?|spots?|places?|spaces?)\s+'
      r'(?:available|open|remaining|left|free)',
      caseSensitive: false,
    );
    final saMatch = slotsAvailable.firstMatch(text);
    if (saMatch != null) {
      return int.parse(saMatch.group(1)!).clamp(0, _defaultGroupSize);
    }

    // --- "N open slots" ---
    final openSlots = RegExp(
      r'(\d+)\s+open\s+(?:slots?|spots?|places?)',
      caseSensitive: false,
    );
    final osMatch = openSlots.firstMatch(text);
    if (osMatch != null) {
      return int.parse(osMatch.group(1)!).clamp(0, _defaultGroupSize);
    }

    // --- "X/4 booked" or "X/4 players" ---
    final xOfN = RegExp(
      r'(\d+)\s*/\s*(\d+)\s*(?:booked|filled|confirmed|players?|slots?)',
      caseSensitive: false,
    );
    final xnMatch = xOfN.firstMatch(text);
    if (xnMatch != null) {
      final booked = int.parse(xnMatch.group(1)!);
      final total = int.parse(xnMatch.group(2)!);
      return (total - booked).clamp(0, total);
    }

    // --- "X of N slots taken/filled" ---
    final xOfNWord = RegExp(
      r'(\d+)\s+of\s+(\d+)\s+(?:slots?|spots?|places?)\s+'
      r'(?:taken|filled|booked|confirmed)',
      caseSensitive: false,
    );
    final xnwMatch = xOfNWord.firstMatch(text);
    if (xnwMatch != null) {
      final booked = int.parse(xnwMatch.group(1)!);
      final total = int.parse(xnwMatch.group(2)!);
      return (total - booked).clamp(0, total);
    }

    // --- "N spots/slots left" ---
    final spotsLeft = RegExp(
      r'(\d+)\s+(?:slots?|spots?|places?)\s+left',
      caseSensitive: false,
    );
    final slMatch = spotsLeft.firstMatch(text);
    if (slMatch != null) {
      return int.parse(slMatch.group(1)!).clamp(0, _defaultGroupSize);
    }

    // --- Fallback: derive from player count ---
    return (_defaultGroupSize - playerCount).clamp(0, _defaultGroupSize);
  }
}
