/// Core application state for the Teed Up golf booking app.
///
/// Manages the in-memory list of upcoming rounds, RSVP alerts,
/// calendar selection, scan-in-progress state, and first-launch /
/// purchase status. Backed by SQLite for persistence (loaded on init).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/family_member.dart';
import '../models/golf_round.dart';
import '../models/player.dart';
import '../models/player_diff.dart';
import '../models/rsvp_change.dart';
import '../services/calendar_service.dart';

/// Central [ChangeNotifier] that holds the app's reactive state.
///
/// Provided at the root of the widget tree via [Provider] and consumed
/// by screens that need upcoming rounds, alerts, or global flags.
///
/// ```dart
/// final state = context.read<AppState>();
/// state.addRound(newRound);
/// ```
class AppState extends ChangeNotifier {
  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  int _currentTabIndex = 0;

  /// The currently selected bottom-navigation tab index.
  int get currentTabIndex => _currentTabIndex;

  /// Switches the active bottom-navigation tab.
  void setTab(int index) {
    if (_currentTabIndex == index) return;
    _currentTabIndex = index;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Upcoming Rounds
  // ---------------------------------------------------------------------------

  List<GolfRound> _upcomingRounds = [];

  /// All upcoming golf rounds, sorted by date (nearest first).
  List<GolfRound> get upcomingRounds => List.unmodifiable(_upcomingRounds);

  /// Replaces the entire rounds list (e.g. after initial DB load).
  void setRounds(List<GolfRound> rounds) {
    _upcomingRounds = List.of(rounds)
      ..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
  }

  /// Adds a single round and re-sorts.
  void addRound(GolfRound round) {
    _upcomingRounds.add(round);
    _upcomingRounds.sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
  }

  /// Replaces a round with the same [GolfRound.id].
  ///
  /// If no matching round is found, the [updated] round is appended.
  ///
  /// If [selectedFamily] is provided and non-empty, those members are
  /// patched onto the round's device calendar event as informational
  /// (Optional) attendees and the round is marked [GolfRound.familyNotified].
  Future<void> updateRound(
    GolfRound updated, {
    List<FamilyMember>? selectedFamily,
  }) async {
    final notify = selectedFamily != null && selectedFamily.isNotEmpty;
    var toSave = notify ? updated.copyWith(familyNotified: true) : updated;

    if (notify && _selectedCalendarId != null) {
      toSave = await _pushFamilyToCalendar(toSave, selectedFamily);
    }

    final index = _upcomingRounds.indexWhere((r) => r.id == toSave.id);
    if (index >= 0) {
      _upcomingRounds[index] = toSave;
    } else {
      _upcomingRounds.add(toSave);
    }
    _upcomingRounds.sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
  }

  /// Saves a brand-new [round] (from a fresh scan, spec A7/A9).
  ///
  /// If [selectedFamily] is provided and non-empty, the calendar event is
  /// created with those members as informational (Optional) attendees.
  Future<void> saveRound(
    GolfRound round, {
    List<FamilyMember>? selectedFamily,
  }) async {
    final notify = selectedFamily != null && selectedFamily.isNotEmpty;
    var toSave = notify ? round.copyWith(familyNotified: true) : round;

    if (_selectedCalendarId != null) {
      final eventId = await CalendarService().createGolfEvent(
        toSave,
        _selectedCalendarId!,
        notifyFamilyMembers: notify ? selectedFamily : null,
        reminderMinutes: enabledReminderMinutes,
      );
      if (eventId != null) {
        toSave = toSave.copyWith(calendarEventId: eventId);
      }
    }

    addRound(toSave);
  }

  /// Removes a round by its [id].
  void removeRound(String id) {
    _upcomingRounds.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// Returns the round matching [id], or `null` if not found.
  GolfRound? getRound(String id) {
    try {
      return _upcomingRounds.firstWhere((r) => r.id == id);
    } on StateError {
      return null;
    }
  }

  /// Finds an existing upcoming round matching [course]/[date]/[teeTime]
  /// (spec A7 — booking-match detection on rescan).
  ///
  /// Match is exact on course name (case-insensitive), calendar day, and
  /// tee-time hour/minute.
  GolfRound? findMatchingRound({
    required String course,
    required DateTime date,
    required DateTime teeTime,
  }) {
    final courseNorm = course.trim().toLowerCase();
    for (final r in _upcomingRounds) {
      final sameCourse = r.courseName.trim().toLowerCase() == courseNorm;
      final sameDay = r.date.year == date.year &&
          r.date.month == date.month &&
          r.date.day == date.day;
      final sameTime = r.teeTime.hour == teeTime.hour &&
          r.teeTime.minute == teeTime.minute;
      if (sameCourse && sameDay && sameTime) return r;
    }
    return null;
  }

  /// Updates a single player's RSVP status within a round (spec A10 —
  /// 4-state cycle: tbc → confirmed → pending → declined).
  ///
  /// Declining automatically raises an alert, mirroring the prototype's
  /// auto-alert-on-decline behaviour.
  Future<void> updatePlayerRsvp({
    required String roundId,
    required String playerId,
    required RsvpStatus newStatus,
  }) async {
    final round = getRound(roundId);
    if (round == null) return;

    Player? changedPlayer;
    final players = round.players.map((p) {
      if (p.id != playerId) return p;
      changedPlayer = p;
      return p.copyWith(rsvpStatus: newStatus);
    }).toList();
    if (changedPlayer == null) return;

    await updateRound(round.copyWith(players: players));

    if (newStatus == RsvpStatus.declined) {
      addAlert(RsvpChange(
        eventId: round.id,
        playerName: changedPlayer!.name,
        playerEmail: changedPlayer!.email,
        oldStatus: changedPlayer!.rsvpStatus,
        newStatus: newStatus,
        detectedAt: DateTime.now(),
      ));
    }
  }

  /// Informs friends & family about [roundId] (spec A10 — "Let friends and
  /// family know").
  ///
  /// Adds every configured [familyMembers] entry as an informational
  /// (Optional) calendar attendee on the round's event — creating the
  /// event first if it doesn't exist yet — then marks the round notified.
  /// No-ops if already notified.
  Future<void> notifyFamily({required String roundId}) async {
    final round = getRound(roundId);
    if (round == null || round.familyNotified) return;

    var toSave = round.copyWith(familyNotified: true);
    if (_familyMembers.isNotEmpty && _selectedCalendarId != null) {
      toSave = await _pushFamilyToCalendar(toSave, _familyMembers);
    }

    final index = _upcomingRounds.indexWhere((r) => r.id == toSave.id);
    if (index >= 0) {
      _upcomingRounds[index] = toSave;
    } else {
      _upcomingRounds.add(toSave);
    }
    notifyListeners();
  }

  /// Sends (creates or refreshes) the calendar invite for a round's
  /// players — the always-shown "Send invite" action. Does not touch
  /// family attendees.
  Future<void> sendCalendarInvite({required String roundId}) async {
    final round = getRound(roundId);
    if (round == null || _selectedCalendarId == null) return;

    final calendarService = CalendarService();
    if (round.calendarEventId != null) {
      final diff = PlayerDiff.compare(
        oldPlayers: round.players,
        newPlayers: round.players,
      );
      await calendarService.updateGolfEvent(
        round.calendarEventId!,
        round,
        diff,
        _selectedCalendarId!,
        reminderMinutes: enabledReminderMinutes,
      );
    } else {
      final eventId = await calendarService.createGolfEvent(
        round,
        _selectedCalendarId!,
        reminderMinutes: enabledReminderMinutes,
      );
      if (eventId != null) {
        await updateRound(round.copyWith(calendarEventId: eventId));
      }
    }
  }

  /// Creates or patches [round]'s calendar event so [members] are added as
  /// informational (Optional) attendees. Returns the round, updated with a
  /// [GolfRound.calendarEventId] if one was just created.
  Future<GolfRound> _pushFamilyToCalendar(
    GolfRound round,
    List<FamilyMember> members,
  ) async {
    final calendarService = CalendarService();
    if (round.calendarEventId != null) {
      final diff = PlayerDiff.compare(
        oldPlayers: round.players,
        newPlayers: round.players,
      );
      await calendarService.updateGolfEvent(
        round.calendarEventId!,
        round,
        diff,
        _selectedCalendarId!,
        notifyFamilyMembers: members,
        reminderMinutes: enabledReminderMinutes,
      );
      return round;
    }
    final eventId = await calendarService.createGolfEvent(
      round,
      _selectedCalendarId!,
      notifyFamilyMembers: members,
      reminderMinutes: enabledReminderMinutes,
    );
    return eventId != null ? round.copyWith(calendarEventId: eventId) : round;
  }

  // ---------------------------------------------------------------------------
  // Self identity (Creator/Recipient permission model)
  // ---------------------------------------------------------------------------

  Set<String> _ownAccountEmails = {};

  /// Loads this device's own calendar account emails, used to work out
  /// which player in a round is "you". Safe to call once at startup; the
  /// result is cached in memory for [selfPlayerIn]'s synchronous lookups.
  Future<void> loadOwnAccountEmails() async {
    _ownAccountEmails = await CalendarService().getOwnAccountEmails();
  }

  /// Returns whichever player in [round] matches one of this device's own
  /// calendar account emails, or `null` if none does.
  ///
  /// `null` is a normal, expected outcome — not every round will have a
  /// player whose email matches an account on this device (e.g. a Creator
  /// whose own name/email never appeared in the scanned booking text).
  /// Callers must treat a `null` result as "self-RSVP unavailable for this
  /// round", never as permission to fall back to editing someone else's.
  Player? selfPlayerIn(GolfRound round) {
    if (_ownAccountEmails.isEmpty) return null;
    for (final player in round.players) {
      final email = player.email?.trim().toLowerCase();
      if (email != null && _ownAccountEmails.contains(email)) return player;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // RSVP Alerts
  // ---------------------------------------------------------------------------

  List<RsvpChange> _alerts = [];

  /// All RSVP change alerts, newest first.
  List<RsvpChange> get alerts => List.unmodifiable(_alerts);

  /// The count of unread alerts (for badge display).
  int get unreadAlertCount => _alerts.where((a) => !a.isRead).length;

  /// Replaces the full alerts list (e.g. after DB load).
  void setAlerts(List<RsvpChange> alerts) {
    _alerts = List.of(alerts)
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    notifyListeners();
  }

  /// Adds a new alert and sorts newest-first.
  void addAlert(RsvpChange alert) {
    _alerts.insert(0, alert);
    notifyListeners();
  }

  /// Marks a single alert as read by matching its identity fields.
  void markAlertRead(RsvpChange alert) {
    final index = _alerts.indexWhere(
      (a) =>
          a.eventId == alert.eventId &&
          a.playerName == alert.playerName &&
          a.detectedAt == alert.detectedAt,
    );
    if (index >= 0) {
      _alerts[index] = _alerts[index].copyWith(isRead: true);
      notifyListeners();
    }
  }

  /// Marks all alerts as read.
  void markAllAlertsRead() {
    _alerts = _alerts.map((a) => a.copyWith(isRead: true)).toList();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Calendar Selection
  // ---------------------------------------------------------------------------

  String? _selectedCalendarId;

  /// The device calendar ID the user has chosen for golf events.
  ///
  /// `null` until the user selects one during onboarding or settings.
  String? get selectedCalendarId => _selectedCalendarId;

  /// Alias used by the settings screen.
  String? get defaultCalendarId => _selectedCalendarId;

  /// Sets the active calendar.
  void setSelectedCalendarId(String? id) {
    if (_selectedCalendarId == id) return;
    _selectedCalendarId = id;
    notifyListeners();
  }

  /// Alias used by the settings screen.
  void setDefaultCalendar(String? id) => setSelectedCalendarId(id);

  /// The calendar new golf events are written to (spec: multi-calendar
  /// account linking — this is the "Primary Calendar"). Alias for
  /// [selectedCalendarId] so existing create/update-event call sites don't
  /// need to change.
  String? get primaryCalendarId => _selectedCalendarId;

  /// Sets the primary calendar. Alias for [setSelectedCalendarId].
  void setPrimaryCalendarId(String? id) => setSelectedCalendarId(id);

  // ---------------------------------------------------------------------------
  // Linked Calendars (spec: multi-calendar account linking)
  // ---------------------------------------------------------------------------

  static const String _linkedCalendarIdsPrefsKey = 'teed_up_linked_calendar_ids';

  List<String> _linkedCalendarIds = [];

  /// Calendars enabled for event scanning / RSVP monitoring, in addition
  /// to [primaryCalendarId] (where new events are actually created).
  List<String> get linkedCalendarIds => List.unmodifiable(_linkedCalendarIds);

  /// Loads the persisted linked-calendars list from SharedPreferences.
  Future<void> loadLinkedCalendarIds() async {
    final prefs = await SharedPreferences.getInstance();
    _linkedCalendarIds = prefs.getStringList(_linkedCalendarIdsPrefsKey) ?? [];
    notifyListeners();
  }

  Future<void> _persistLinkedCalendarIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_linkedCalendarIdsPrefsKey, _linkedCalendarIds);
  }

  /// Toggles whether [calendarId] is linked for scanning/monitoring.
  void toggleLinkedCalendar(String calendarId) {
    if (_linkedCalendarIds.contains(calendarId)) {
      _linkedCalendarIds = List.of(_linkedCalendarIds)..remove(calendarId);
    } else {
      _linkedCalendarIds = List.of(_linkedCalendarIds)..add(calendarId);
    }
    notifyListeners();
    _persistLinkedCalendarIds();
  }

  /// All calendars that should be scanned/monitored: the linked list plus
  /// the primary calendar (always implicitly included, deduplicated).
  List<String> get calendarsToMonitor {
    final ids = {..._linkedCalendarIds};
    if (_selectedCalendarId != null) ids.add(_selectedCalendarId!);
    return ids.toList();
  }

  // ---------------------------------------------------------------------------
  // Decline Alerts Toggle
  // ---------------------------------------------------------------------------

  bool _declineAlertsEnabled = true;

  /// Whether decline alert notifications are enabled.
  bool get declineAlertsEnabled => _declineAlertsEnabled;

  /// Toggles decline alert notifications.
  void setDeclineAlerts(bool value) {
    if (_declineAlertsEnabled == value) return;
    _declineAlertsEnabled = value;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Pre-round Reminder Toggles (spec C5) — gate the 12h/1h calendar-invite
  // reminders built in CalendarService._buildEvent.
  // ---------------------------------------------------------------------------

  static const String _reminder12hPrefsKey = 'teed_up_reminder_12h';
  static const String _reminder1hPrefsKey = 'teed_up_reminder_1h';

  bool _reminder12hEnabled = true;
  bool _reminder1hEnabled = true;

  /// Whether a 12-hour-before reminder is added to the calendar invite.
  bool get reminder12hEnabled => _reminder12hEnabled;

  /// Whether a 1-hour-before reminder is added to the calendar invite.
  bool get reminder1hEnabled => _reminder1hEnabled;

  /// Loads persisted reminder toggle state.
  Future<void> loadReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _reminder12hEnabled = prefs.getBool(_reminder12hPrefsKey) ?? true;
    _reminder1hEnabled = prefs.getBool(_reminder1hPrefsKey) ?? true;
    notifyListeners();
  }

  /// Toggles the 12-hour-before reminder and persists it.
  Future<void> setReminder12h(bool value) async {
    if (_reminder12hEnabled == value) return;
    _reminder12hEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reminder12hPrefsKey, value);
  }

  /// Toggles the 1-hour-before reminder and persists it.
  Future<void> setReminder1h(bool value) async {
    if (_reminder1hEnabled == value) return;
    _reminder1hEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reminder1hPrefsKey, value);
  }

  /// Minutes-before reminder list built from the two toggles, passed straight
  /// through to [CalendarService].
  List<int> get enabledReminderMinutes => [
        if (_reminder1hEnabled) 60,
        if (_reminder12hEnabled) 720,
      ];

  // ---------------------------------------------------------------------------
  // Onboarding / Purchase Flags
  // ---------------------------------------------------------------------------

  bool _isOnboarded = false;

  /// Whether the user has completed the first-launch onboarding flow.
  bool get isOnboarded => _isOnboarded;

  /// Alias used by main.dart for routing.
  bool get onboardingComplete => _isOnboarded;

  /// Marks onboarding as complete.
  void completeOnboarding() {
    if (_isOnboarded) return;
    _isOnboarded = true;
    notifyListeners();
  }

  bool _isPurchased = false;

  /// Whether the user has purchased the app (AED 99 one-time).
  bool get isPurchased => _isPurchased;

  /// Records a successful purchase.
  void setPurchased(bool value) {
    if (_isPurchased == value) return;
    _isPurchased = value;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Scan-in-progress State
  // ---------------------------------------------------------------------------

  String? _scannedImagePath;
  String? _scannedCourseName;
  DateTime? _scannedDate;
  DateTime? _scannedTeeTime;
  String? _scannedBookingRef;
  List<Player> _scannedPlayers = [];

  /// Path to the captured/picked screenshot being processed.
  String? get scannedImagePath => _scannedImagePath;

  /// Course name extracted from OCR or edited by user.
  String? get scannedCourseName => _scannedCourseName;

  /// Date extracted from OCR or picked by user.
  DateTime? get scannedDate => _scannedDate;

  /// Tee time extracted from OCR or picked by user.
  DateTime? get scannedTeeTime => _scannedTeeTime;

  /// Booking reference extracted from OCR.
  String? get scannedBookingRef => _scannedBookingRef;

  /// Players extracted from OCR, possibly amended by user.
  List<Player> get scannedPlayers => List.unmodifiable(_scannedPlayers);

  /// Sets the scanned image path after capture/pick.
  void setScannedImage(String path) {
    _scannedImagePath = path;
    notifyListeners();
  }

  /// Updates one or more scan result fields.
  void updateScanResults({
    String? courseName,
    DateTime? date,
    DateTime? teeTime,
    String? bookingRef,
    List<Player>? players,
  }) {
    if (courseName != null) _scannedCourseName = courseName;
    if (date != null) _scannedDate = date;
    if (teeTime != null) _scannedTeeTime = teeTime;
    if (bookingRef != null) _scannedBookingRef = bookingRef;
    if (players != null) _scannedPlayers = List.of(players);
    notifyListeners();
  }

  /// Updates a specific player's email in the scanned list.
  void updateScannedPlayerEmail(String playerId, String email) {
    final index = _scannedPlayers.indexWhere((p) => p.id == playerId);
    if (index >= 0) {
      _scannedPlayers[index] = _scannedPlayers[index].copyWith(email: email);
      notifyListeners();
    }
  }

  /// Clears all scan-in-progress state after saving or cancelling.
  void clearScanState() {
    _scannedImagePath = null;
    _scannedCourseName = null;
    _scannedDate = null;
    _scannedTeeTime = null;
    _scannedBookingRef = null;
    _scannedPlayers = [];
    _existingBookingId = null;
    _addedPlayers = [];
    _removedPlayers = [];
    _unchangedPlayers = [];
    _notifyFamily = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Amendment / Diff State
  // ---------------------------------------------------------------------------

  String? _existingBookingId;
  List<Player> _addedPlayers = [];
  List<Player> _removedPlayers = [];
  List<Player> _unchangedPlayers = [];

  /// Whether the current scan is amending an existing booking.
  bool get isExistingBooking => _existingBookingId != null;

  /// Players added in the amendment.
  List<Player> get addedPlayers => List.unmodifiable(_addedPlayers);

  /// Players removed in the amendment.
  List<Player> get removedPlayers => List.unmodifiable(_removedPlayers);

  /// Players unchanged between scans.
  List<Player> get unchangedPlayers => List.unmodifiable(_unchangedPlayers);

  /// Sets the amendment diff data.
  void setAmendmentDiff({
    required String existingBookingId,
    required List<Player> added,
    required List<Player> removed,
    required List<Player> unchanged,
  }) {
    _existingBookingId = existingBookingId;
    _addedPlayers = List.of(added);
    _removedPlayers = List.of(removed);
    _unchangedPlayers = List.of(unchanged);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Family Notification
  // ---------------------------------------------------------------------------

  bool _notifyFamily = false;

  /// Sets whether to notify family for the current scan.
  void setNotifyFamily(bool value) {
    if (_notifyFamily == value) return;
    _notifyFamily = value;
    notifyListeners();
  }

  String? _familyContactName;
  String? _familyContactEmail;
  bool _familyAlwaysNotify = false;

  /// The configured family contact name.
  String? get familyContactName => _familyContactName;

  /// The configured family contact email.
  String? get familyContactEmail => _familyContactEmail;

  /// Whether family is always auto-added without asking.
  bool get familyAlwaysNotify => _familyAlwaysNotify;

  /// Whether a family contact has been configured.
  bool get hasFamilyContact =>
      _familyContactName != null &&
      _familyContactName!.isNotEmpty &&
      _familyContactEmail != null &&
      _familyContactEmail!.isNotEmpty;

  /// Loads family contact settings from SharedPreferences.
  Future<void> loadFamilySettings() async {
    final prefs = await SharedPreferences.getInstance();
    _familyContactName = prefs.getString('family_contact_name');
    _familyContactEmail = prefs.getString('family_contact_email');
    _familyAlwaysNotify = prefs.getBool('family_always_notify') ?? false;
    notifyListeners();
  }

  /// Saves the family contact details to SharedPreferences.
  Future<void> setFamilyContact(String name, String email) async {
    _familyContactName = name;
    _familyContactEmail = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('family_contact_name', name);
    await prefs.setString('family_contact_email', email);
    notifyListeners();
  }

  /// Clears the family contact from settings.
  Future<void> clearFamilyContact() async {
    _familyContactName = null;
    _familyContactEmail = null;
    _familyAlwaysNotify = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('family_contact_name');
    await prefs.remove('family_contact_email');
    await prefs.setBool('family_always_notify', false);
    notifyListeners();
  }

  /// Sets the "always notify family" toggle and persists it.
  Future<void> setFamilyAlwaysNotify(bool value) async {
    if (_familyAlwaysNotify == value) return;
    _familyAlwaysNotify = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('family_always_notify', value);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Friends & Family (spec A4/A9/A12 — up to 5 members, name + email)
  // ---------------------------------------------------------------------------

  static const int maxFamilyMembers = 5;
  static const String _familyMembersPrefsKey = 'teed_up_family_members';

  List<FamilyMember> _familyMembers = [];

  /// Friends/family kept informed about tee times (max [maxFamilyMembers]).
  List<FamilyMember> get familyMembers => List.unmodifiable(_familyMembers);

  /// Loads the persisted friends & family list from SharedPreferences.
  Future<void> loadFamilyMembers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_familyMembersPrefsKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _familyMembers = decoded
          .map((e) => FamilyMember.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('AppState: failed to load family members: $e');
    }
  }

  Future<void> _persistFamilyMembers() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_familyMembers.map((f) => f.toJson()).toList());
    await prefs.setString(_familyMembersPrefsKey, encoded);
  }

  /// Adds a friend/family member. No-ops once [maxFamilyMembers] is reached.
  void addFamilyMember({required String name, required String email}) {
    if (_familyMembers.length >= maxFamilyMembers) return;
    _familyMembers.add(FamilyMember(name: name, email: email));
    notifyListeners();
    _persistFamilyMembers();
  }

  /// Removes the friend/family member at [index].
  void removeFamilyMember(int index) {
    if (index < 0 || index >= _familyMembers.length) return;
    _familyMembers.removeAt(index);
    notifyListeners();
    _persistFamilyMembers();
  }

  // ---------------------------------------------------------------------------
  // Reset (for testing)
  // ---------------------------------------------------------------------------

  /// Resets all state to initial values. **For testing only.**
  @visibleForTesting
  void reset() {
    _currentTabIndex = 0;
    _upcomingRounds = [];
    _alerts = [];
    _familyMembers = [];
    _selectedCalendarId = null;
    _linkedCalendarIds = [];
    _declineAlertsEnabled = true;
    _isOnboarded = false;
    _isPurchased = false;
    _scannedImagePath = null;
    _scannedCourseName = null;
    _scannedDate = null;
    _scannedTeeTime = null;
    _scannedBookingRef = null;
    _scannedPlayers = [];
    _existingBookingId = null;
    _addedPlayers = [];
    _removedPlayers = [];
    _unchangedPlayers = [];
    _notifyFamily = false;
    notifyListeners();
  }
}
