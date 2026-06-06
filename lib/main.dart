import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';

/// Entry point for the Teed Up golf booking app.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force light mode, portrait-primary on phones
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const TeedUpApp());
}

/// Root widget for the Teed Up application.
///
/// Provides [AppState] via [ChangeNotifierProvider] and applies the
/// TAG-branded light theme throughout the widget tree.
class TeedUpApp extends StatelessWidget {
  /// Creates the [TeedUpApp].
  const TeedUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'Teed Up',
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
