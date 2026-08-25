import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db/database_helper.dart';
import 'models/golf_round.dart';
import 'models/player.dart';
import 'models/rsvp_change.dart';
import 'providers/app_state.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/scan_screen.dart';
import 'services/contacts_service.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';
import 'services/rsvp_monitor.dart';
import 'theme/app_theme.dart';

/// Root navigator key — lets the share-sheet listener (spec A6) push
/// [ScanScreen] from outside the widget tree (shares can arrive while the
/// app is backgrounded or cold-started).
final navigatorKey = GlobalKey<NavigatorState>();

/// SharedPreferences keys for persistence.
const String _kRoundsKey = 'teed_up_rounds';
const String _kOnboardedKey = 'teed_up_onboarded';
const String _kPurchasedKey = 'teed_up_purchased';
const String _kCalendarIdKey = 'teed_up_selected_calendar_id';
const String _kDeclineAlertsKey = 'teed_up_decline_alerts';

/// Entry point for the All Teed Up golf booking app.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch Flutter framework errors (rendering, layout) without crashing.
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[Flutter] Caught framework error: ${details.exception}');
    debugPrint('${details.stack}');
    // Don't rethrow — prevents OS-level crash dialogs.
  };

  // Force light mode, portrait-primary on phones
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Load persisted state before building the widget tree.
  final appState = AppState();
  await _loadPersistedState(appState);

  // Initialize services (non-blocking — errors are caught internally).
  await _initializeServices(appState);

  // Auto-save rounds whenever state changes.
  appState.addListener(() => _saveRounds(appState));

  runApp(TeedUpApp(appState: appState));

  _listenForSharedMedia();
}

/// Spec A6 — OS share-sheet integration. Routes an image shared from
/// Photos/WhatsApp/Telegram straight into [ScanScreen]'s review flow,
/// whether the app was already running, backgrounded, or cold-started.
void _listenForSharedMedia() {
  void openScanScreen(String path) {
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => ScanScreen(sharedImagePath: path),
      ),
    );
  }

  // App was launched fresh by a share action.
  ReceiveSharingIntent.instance.getInitialMedia().then((files) {
    if (files.isEmpty) return;
    openScanScreen(files.first.path);
    ReceiveSharingIntent.instance.reset();
  });

  // App was already running (foreground/background) when shared to.
  ReceiveSharingIntent.instance.getMediaStream().listen((files) {
    if (files.isEmpty) return;
    openScanScreen(files.first.path);
    ReceiveSharingIntent.instance.reset();
  });
}

/// Loads rounds, alerts, flags, and calendar selection from persistence.
Future<void> _loadPersistedState(AppState state) async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // -- Flags --
    final alreadyOnboarded = prefs.getBool(_kOnboardedKey) == true;
    if (alreadyOnboarded) {
      state.completeOnboarding();
    }
    if (prefs.getBool(_kPurchasedKey) == true) {
      state.setPurchased(true);
    }
    state.setSelectedCalendarId(prefs.getString(_kCalendarIdKey));
    state.setDeclineAlerts(prefs.getBool(_kDeclineAlertsKey) ?? true);
    await state.loadFamilyMembers();
    await state.loadFamilySettings();
    await state.loadLinkedCalendarIds();
    await state.loadReminderSettings();
    // Only for returning users — calendar permission has already been asked
    // (or declined) during onboarding by this point, so this can't surface
    // a surprise permission prompt before onboarding's own explained one.
    if (alreadyOnboarded) {
      await state.loadOwnAccountEmails();
    }

    // -- Rounds (JSON in SharedPreferences) --
    final roundsJson = prefs.getString(_kRoundsKey);
    if (roundsJson != null) {
      final List<dynamic> decoded = jsonDecode(roundsJson) as List<dynamic>;
      final rounds = decoded
          .map((r) => GolfRound.fromJson(r as Map<String, dynamic>))
          .toList();
      state.setRounds(rounds);
    }

    // -- Alerts (from SQLite) --
    final db = DatabaseHelper.instance;
    final alertRows = await db.queryAllAlerts();
    final alerts = alertRows.map((row) {
      return RsvpChange(
        eventId: row['event_id'] as String,
        playerName: row['player_name'] as String,
        playerEmail: row['player_email'] as String?,
        oldStatus: _parseStatus(row['old_status'] as String?),
        newStatus: _parseStatus(row['new_status'] as String?),
        detectedAt: DateTime.parse(row['detected_at'] as String),
        isRead: row['is_read'] == 1,
      );
    }).toList();
    state.setAlerts(alerts);
  } catch (e, st) {
    debugPrint('[main] Failed to load persisted state: $e\n$st');
  }
}

/// Saves the current rounds list to SharedPreferences as JSON.
Future<void> _saveRounds(AppState state) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final roundsJson = jsonEncode(
      state.upcomingRounds.map((r) => r.toJson()).toList(),
    );
    await prefs.setString(_kRoundsKey, roundsJson);

    // Also persist flags.
    await prefs.setBool(_kOnboardedKey, state.onboardingComplete);
    await prefs.setBool(_kPurchasedKey, state.isPurchased);
    if (state.selectedCalendarId != null) {
      await prefs.setString(_kCalendarIdKey, state.selectedCalendarId!);
    }
    await prefs.setBool(_kDeclineAlertsKey, state.declineAlertsEnabled);
  } catch (e) {
    debugPrint('[main] Failed to save rounds: $e');
  }
}

/// Initializes non-critical services. Errors are fully caught so they can
/// never crash the app. Each service is optional — the app works without them.
Future<void> _initializeServices(AppState appState) async {
  // Warm the contacts cache for returning users only — i.e. users who have
  // already been through onboarding's Permissions step at least once, so
  // contacts authorization is already decided one way or another. On a
  // fresh install (onboarding not yet complete), iOS's contacts API
  // auto-prompts for permission the moment it's touched at all, even just
  // to enumerate — calling this unconditionally at startup was firing that
  // native permission dialog before the user ever saw the in-app Welcome
  // screen or the Permissions step's rationale.
  if (appState.onboardingComplete) {
    ContactsService.prefetch();
  }

  // Notification service.
  try {
    await NotificationService.instance.initialize();
  } catch (e, st) {
    debugPrint('[main] NotificationService init failed: $e\n$st');
  }

  // RSVP background monitor.
  try {
    await RsvpMonitor.instance.initialize();
  } catch (e, st) {
    debugPrint('[main] RsvpMonitor init failed: $e\n$st');
  }

  // In-app purchase service — may fail if Play Store is not configured yet.
  try {
    final purchaseService = PurchaseService(appState: appState);
    await purchaseService.initialize();
  } catch (e, st) {
    debugPrint('[main] PurchaseService init failed: $e\n$st');
    // App works fine without IAP — just mark as unpurchased for now.
  }
}

/// Parses a status string into an [RsvpStatus].
RsvpStatus _parseStatus(String? status) {
  switch (status?.toLowerCase()) {
    case 'accepted':
      return RsvpStatus.accepted;
    case 'declined':
      return RsvpStatus.declined;
    default:
      return RsvpStatus.pending;
  }
}

/// Root widget for the All Teed Up application.
///
/// Provides [AppState] via [ChangeNotifierProvider] and applies the
/// Light theme throughout the widget tree. Also owns the
/// app-lifecycle observer that drives [RsvpMonitor]'s foreground polling
/// and calendar auto-import reconciliation (growth loop) — see
/// [_TeedUpAppState.didChangeAppLifecycleState].
class TeedUpApp extends StatefulWidget {
  /// Creates the [TeedUpApp].
  const TeedUpApp({super.key, required this.appState});

  /// Pre-loaded application state.
  final AppState appState;

  @override
  State<TeedUpApp> createState() => _TeedUpAppState();
}

class _TeedUpAppState extends State<TeedUpApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Cold-start reconciliation for returning users only — a fresh install
    // hasn't been through onboarding's calendar-permission step yet, so
    // there's nothing to scan. Onboarding fires its own reconciliation
    // pass once permission is actually granted (see onboarding_screen.dart).
    if (widget.appState.onboardingComplete) {
      RsvpMonitor.instance.startForegroundPolling();
      unawaited(
        RsvpMonitor.instance.reconcileWithCalendar(widget.appState),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!widget.appState.onboardingComplete) return;
      RsvpMonitor.instance.startForegroundPolling();
      unawaited(
        RsvpMonitor.instance.reconcileWithCalendar(widget.appState),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      RsvpMonitor.instance.stopForegroundPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RsvpMonitor.instance.stopForegroundPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.appState,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'All Teed Up',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),

            // Route to onboarding or home based on completion state
            home: state.onboardingComplete
                ? const HomeScreen()
                : const OnboardingScreen(),
          );
        },
      ),
    );
  }
}
