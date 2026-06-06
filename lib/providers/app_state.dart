/// Core application state for the Teed Up golf booking app.
///
/// Manages the in-memory list of upcoming rounds, RSVP alerts,
/// calendar selection, scan-in-progress state, and first-launch /
/// purchase status. Backed by SQLite for persistence (loaded on init).
library;

import 'package:flutter/foundation.dart';

import '../models/golf_round.dart';
import '../models/player.dart';
import '../models/rsvp_change.dart';

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
  void updateRound(GolfRound updated) {
    final index = _upcomingRounds.indexWhere((r) => r.id == updated.id);
    if (index >= 0) {
      _upcomingRounds[index] = updated;
    } else {
      _upcomingRounds.add(updated);
    }
    _upcomingRounds.sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
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
  // Reset (for testing)
  // ---------------------------------------------------------------------------

  /// Resets all state to initial values. **For testing only.**
  @visibleForTesting
  void reset() {
    _currentTabIndex = 0;
    _upcomingRounds = [];
    _alerts = [];
    _selectedCalendarId = null;
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
    notifyListeners();
  }
}
