/// Named route configuration for the Teed Up golf booking app.
///
/// Centralises all route names and provides the [onGenerateRoute] callback
/// for [MaterialApp]. Routes now point to the real screen widgets.
library;

import 'package:flutter/material.dart';

import '../screens/alerts_screen.dart';
import '../screens/home_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/purchase_screen.dart';
import '../screens/round_detail_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/verify_emails_screen.dart';

/// All named route paths used in the app.
///
/// Usage:
/// ```dart
/// Navigator.pushNamed(context, AppRoutes.scan);
/// ```
abstract final class AppRoutes {
  /// Home / dashboard — upcoming rounds list.
  static const String home = '/';

  /// OCR camera scan screen.
  static const String scan = '/scan';

  /// Email verification / contact matching screen.
  static const String verifyEmails = '/verify-emails';

  /// Individual round detail screen.
  ///
  /// Expects a route argument of type `String` for the round's ID.
  static const String roundDetail = '/round';

  /// RSVP alerts feed.
  static const String alerts = '/alerts';

  /// App settings.
  static const String settings = '/settings';

  /// First-launch onboarding flow.
  static const String onboarding = '/onboarding';

  /// Premium purchase / paywall screen.
  static const String purchase = '/purchase';
}

/// Generates [Route] objects for the named routes defined in [AppRoutes].
///
/// Pass this to [MaterialApp.onGenerateRoute]:
/// ```dart
/// MaterialApp(
///   onGenerateRoute: AppRouter.onGenerateRoute,
/// )
/// ```
abstract final class AppRouter {
  /// Route factory for [MaterialApp.onGenerateRoute].
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    // Extract the base path (strip any trailing slash).
    final path = settings.name?.replaceAll(RegExp(r'/$'), '') ?? '/';

    switch (path) {
      case AppRoutes.home:
        return _buildRoute(
          settings: settings,
          builder: (_) => const HomeScreen(),
        );

      case AppRoutes.scan:
        return _buildRoute(
          settings: settings,
          builder: (_) => const ScanScreen(),
        );

      case AppRoutes.verifyEmails:
        return _buildRoute(
          settings: settings,
          builder: (_) => const VerifyEmailsScreen(),
        );

      case AppRoutes.alerts:
        return _buildRoute(
          settings: settings,
          builder: (_) => const AlertsScreen(),
        );

      case AppRoutes.settings:
        return _buildRoute(
          settings: settings,
          builder: (_) => const SettingsScreen(),
        );

      case AppRoutes.onboarding:
        return _buildRoute(
          settings: settings,
          builder: (_) => const OnboardingScreen(),
        );

      case AppRoutes.purchase:
        return _buildRoute(
          settings: settings,
          builder: (_) => const PurchaseScreen(),
        );

      default:
        // Handle parameterised routes like /round/:id
        if (path.startsWith('${AppRoutes.roundDetail}/')) {
          final roundId = path.substring('${AppRoutes.roundDetail}/'.length);
          return _buildRoute(
            settings: settings,
            builder: (_) => RoundDetailScreen(roundId: roundId),
          );
        }

        // Also handle /round with argument passed via settings.arguments
        if (path == AppRoutes.roundDetail) {
          final roundId = settings.arguments as String? ?? '';
          return _buildRoute(
            settings: settings,
            builder: (_) => RoundDetailScreen(roundId: roundId),
          );
        }

        // 404 fallback
        return _buildRoute(
          settings: settings,
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Not Found')),
            body: const Center(
              child: Text('Page not found'),
            ),
          ),
        );
    }
  }

  /// Wraps a builder in a [MaterialPageRoute] with the provided settings.
  static MaterialPageRoute<T> _buildRoute<T>({
    required RouteSettings settings,
    required WidgetBuilder builder,
  }) {
    return MaterialPageRoute<T>(
      settings: settings,
      builder: builder,
    );
  }
}
