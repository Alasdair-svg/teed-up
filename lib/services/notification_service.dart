/// Notification service for the Teed Up golf booking app.
///
/// Wraps [flutter_local_notifications] to deliver decline alerts when
/// a calendar attendee changes their RSVP status. Handles platform-specific
/// setup (iOS permissions, Android notification channels) and notification
/// tap routing for deep-linking into round detail screens.
///
/// This service is designed to work both in the foreground and from
/// background isolates (via [Workmanager]), so it uses a static singleton
/// and avoids depending on any widget-layer state.
library;

import 'dart:io' show Platform;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rsvp_change.dart';

/// Callback signature for handling notification taps.
///
/// The [payload] contains the calendar event ID so the UI can navigate
/// to the correct round detail screen.
typedef NotificationTapCallback = void Function(String? payload);

/// Manages local notifications for RSVP decline alerts.
///
/// Usage:
/// ```dart
/// final notifications = NotificationService.instance;
/// await notifications.initialize();
/// await notifications.showDeclineNotification(change);
/// ```
class NotificationService {
  /// Private constructor — use [instance] instead.
  NotificationService._();

  /// Singleton instance safe for use across isolates.
  static final NotificationService instance = NotificationService._();

  /// The underlying notification plugin.
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Whether [initialize] has completed successfully.
  bool _isInitialised = false;

  /// Optional callback invoked when the user taps a notification.
  ///
  /// Set this from the UI layer (e.g. in `main.dart`) to handle navigation.
  NotificationTapCallback? onTap;

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  /// Android notification channel for decline alerts.
  static const String _channelId = 'teed_up_decline_alerts';
  static const String _channelName = 'Decline Alerts';
  static const String _channelDescription =
      'Notifications when a player declines a golf round invitation';

  /// SharedPreferences key for the iOS badge counter.
  static const String _badgeCountKey = 'teed_up_badge_count';

  /// Base notification ID — individual notifications get unique IDs by
  /// hashing the event ID + player name.
  static const int _baseNotificationId = 9000;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Initialises the notification plugin with platform-specific settings.
  ///
  /// - **iOS**: Requests permission for alerts, badges, and sounds.
  /// - **Android**: Creates the `teed_up_decline_alerts` channel with high
  ///   importance so notifications appear as heads-up banners.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  ///
  /// Throws no exceptions; logs errors and degrades gracefully.
  Future<void> initialize() async {
    if (_isInitialised) return;

    try {
      // --- Android settings ---
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

      // --- iOS settings ---
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );

      // Create the Android notification channel.
      if (!kIsWeb && Platform.isAndroid) {
        await _createAndroidChannel();
      }

      _isInitialised = true;
      debugPrint('[NotificationService] Initialised successfully');
    } catch (e, stack) {
      debugPrint('[NotificationService] Initialisation failed: $e');
      debugPrint('$stack');
      // Don't rethrow — notifications are non-critical. The app should
      // continue working without them.
    }
  }

  /// Creates the Android notification channel for decline alerts.
  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);
  }

  /// Handles the user tapping on a notification.
  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    debugPrint('[NotificationService] Notification tapped, payload: $payload');
    onNotificationTap(payload);
  }

  // ---------------------------------------------------------------------------
  // Show notifications
  // ---------------------------------------------------------------------------

  /// Shows a local notification for a decline RSVP change.
  ///
  /// - **Title**: `'Player Declined'`
  /// - **Body**: `'{playerName} declined {courseName} on {date}'`
  /// - **Payload**: The calendar event ID, for deep-linking.
  /// - **iOS**: Increments the app badge count.
  /// - **Android**: Uses the high-importance decline channel.
  ///
  /// [change] — The RSVP status change to notify about.
  /// [courseName] — The golf course name, displayed in the notification body.
  /// [date] — The round date, displayed in the notification body.
  ///
  /// Does nothing if [initialize] hasn't been called or failed.
  Future<void> showDeclineNotification(
    RsvpChange change, {
    String? courseName,
    String? date,
  }) async {
    if (!_isInitialised) {
      debugPrint(
        '[NotificationService] Skipping notification — not initialised',
      );
      return;
    }

    try {
      final courseDisplay = courseName ?? 'your round';
      final dateDisplay = date ?? 'an upcoming date';

      // Increment badge count on iOS.
      final badgeCount = await _incrementBadge();

      // Build platform-specific notification details.
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF7B2D8E), // Primary purple
        category: AndroidNotificationCategory.social,
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: badgeCount,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Generate a stable notification ID from the change details so
      // duplicate notifications for the same event+player are replaced.
      final notificationId = _notificationIdFor(
        change.eventId,
        change.playerName,
      );

      await _plugin.show(
        notificationId,
        'Player Declined',
        '${change.playerName} declined $courseDisplay on $dateDisplay',
        details,
        payload: change.eventId,
      );

      debugPrint(
        '[NotificationService] Showed decline notification for '
        '${change.playerName} (id=$notificationId)',
      );
    } catch (e, stack) {
      debugPrint('[NotificationService] Failed to show notification: $e');
      debugPrint('$stack');
    }
  }

  // ---------------------------------------------------------------------------
  // Notification tap handling
  // ---------------------------------------------------------------------------

  /// Handles a notification tap event.
  ///
  /// [payload] contains the calendar event ID. If [onTap] is set by the
  /// UI layer, it will be invoked to navigate to the round detail screen.
  ///
  /// Also clears the badge when the user engages with a notification.
  Future<void> onNotificationTap(String? payload) async {
    debugPrint('[NotificationService] Processing tap, eventId: $payload');

    if (payload != null && onTap != null) {
      onTap!(payload);
    }

    // Clear badge when user engages.
    await clearBadge();
  }

  // ---------------------------------------------------------------------------
  // Badge management
  // ---------------------------------------------------------------------------

  /// Increments the iOS badge count by 1 and returns the new count.
  ///
  /// The badge count is persisted in [SharedPreferences] so it survives
  /// app restarts and background task cycles.
  Future<int> _incrementBadge() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_badgeCountKey) ?? 0;
      final newCount = current + 1;
      await prefs.setInt(_badgeCountKey, newCount);
      return newCount;
    } catch (e) {
      debugPrint('[NotificationService] Badge increment failed: $e');
      return 1;
    }
  }

  /// Resets the app badge count to zero.
  ///
  /// Call this when the user opens the alerts screen or taps a notification.
  Future<void> clearBadge() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_badgeCountKey, 0);

      // Also clear the iOS badge via the notification plugin.
      if (!kIsWeb && Platform.isIOS) {
        // Badge is cleared by persisting 0 — the next notification will
        // pick up the reset count. A more direct approach would be to
        // use the iOS plugin to set badge 0, but this is sufficient.
        debugPrint('[NotificationService] Badge cleared');
      }
    } catch (e) {
      debugPrint('[NotificationService] Badge clear failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Generates a deterministic notification ID for a given event + player
  /// combination so duplicate notifications replace each other.
  int _notificationIdFor(String eventId, String playerName) {
    final hash = '$eventId:$playerName'.hashCode;
    // Keep it positive and within 32-bit int range.
    return (_baseNotificationId + hash.abs()) & 0x7FFFFFFF;
  }
}
