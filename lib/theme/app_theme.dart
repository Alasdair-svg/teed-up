/// TAG-branded theme for the Teed Up golf booking app.
///
/// Implements The Artesian Group design tokens as a complete Flutter
/// [ThemeData]. **Light theme only** — no dark mode.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// Design Tokens
// =============================================================================

/// The Artesian Group brand colours.
abstract final class AppColors {
  /// Primary brand purple — #7B2D8E.
  static const Color primary = Color(0xFF7B2D8E);

  /// Deep purple (hover / pressed) — #5C1D6E.
  static const Color deepPurple = Color(0xFF5C1D6E);

  /// Soft purple (accent highlights) — #9B4DB8.
  static const Color softPurple = Color(0xFF9B4DB8);

  /// Pale purple (background tint) — #F3EAF6.
  static const Color palePurple = Color(0xFFF3EAF6);

  /// Dark text for headlines — #1E1E2E.
  static const Color textDark = Color(0xFF1E1E2E);

  /// Body text — #4A4A5E.
  static const Color textBody = Color(0xFF4A4A5E);

  /// Muted text — #8888A0.
  static const Color textMuted = Color(0xFF8888A0);

  /// Primary background — white.
  static const Color white = Color(0xFFFFFFFF);

  /// Input / off-white backgrounds — #FAFAFE.
  static const Color offWhite = Color(0xFFFAFAFE);

  /// Borders and dividers — #E8E8EE.
  static const Color grey = Color(0xFFE8E8EE);

  /// Section backgrounds — #F4F4F8.
  static const Color greyLight = Color(0xFFF4F4F8);

  /// Error / destructive actions.
  static const Color error = Color(0xFFD32F2F);

  /// Light error background.
  static const Color errorLight = Color(0xFFFDE8E8);

  /// Success / confirmed actions.
  static const Color success = Color(0xFF2E7D32);

  /// Light success background.
  static const Color successLight = Color(0xFFE8F5E9);

  /// Warning / pending actions.
  static const Color warning = Color(0xFFED6C02);

  /// Light warning background.
  static const Color warningLight = Color(0xFFFFF4E5);

  /// Alias for [palePurple] — used by screens as a tint background.
  static const Color primaryPale = palePurple;

  /// Alias for [softPurple] — used by screens as an accent colour.
  static const Color primarySoft = softPurple;

  /// Primary brand gradient.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, deepPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Standard border radii.
abstract final class AppRadius {
  /// Card radius (12 px).
  static const double card = 12.0;

  /// Button / input radius (8 px).
  static const double button = 8.0;

  /// Pre-built card [BorderRadius] for use in [BoxDecoration].
  static final BorderRadius cardBorder = BorderRadius.circular(card);

  /// Pre-built button / input [BorderRadius] for use in [BoxDecoration].
  static final BorderRadius buttonBorder = BorderRadius.circular(button);
}

/// Standard box shadow matching the TAG spec.
final List<BoxShadow> appCardShadow = [
  BoxShadow(
    color: AppColors.primary.withValues(alpha: 0.12),
    blurRadius: 24,
    offset: const Offset(0, 4),
  ),
];

/// Alias used by screen widgets.
final List<BoxShadow> cardShadow = appCardShadow;

/// Global transition duration (matches [AppMotion.duration]).
const Duration kTransitionDuration = Duration(milliseconds: 300);

/// Global transition curve (matches [AppMotion.curve]).
const Curve kTransitionCurve = Cubic(0.4, 0, 0.2, 1);

/// Top-level convenience function used by `main.dart`.
ThemeData buildAppTheme() => AppTheme.light;

/// Standard animation curve / duration.
abstract final class AppMotion {
  /// Default animation duration (300 ms).
  static const Duration duration = Duration(milliseconds: 300);

  /// Default animation curve.
  static const Curve curve = Cubic(0.4, 0, 0.2, 1);
}

// =============================================================================
// Theme Builder
// =============================================================================

/// Builds the app-wide [ThemeData] using TAG brand tokens.
///
/// Usage in `MaterialApp`:
/// ```dart
/// MaterialApp(
///   theme: AppTheme.light,
///   ...
/// )
/// ```
abstract final class AppTheme {
  /// The one-and-only light theme.
  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      secondary: AppColors.deepPurple,
      onSecondary: AppColors.white,
      tertiary: AppColors.softPurple,
      surface: AppColors.white,
      onSurface: AppColors.textDark,
      error: AppColors.error,
      onError: AppColors.white,
      outline: AppColors.grey,
      surfaceContainerHighest: AppColors.greyLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.white,

      // --- Typography ---
      textTheme: _textTheme,
      fontFamily: 'Inter',

      // --- AppBar ---
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: AppColors.textDark,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: AppColors.textDark),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
          statusBarColor: Colors.transparent,
        ),
      ),

      // --- Cards ---
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        shadowColor: AppColors.primary.withValues(alpha: 0.12),
        margin: EdgeInsets.zero,
      ),

      // --- Elevated Buttons ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // --- Outlined Buttons ---
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),

      // --- Text Buttons ---
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),

      // --- Input Fields ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.offWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.grey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: AppColors.textMuted,
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: AppColors.textBody,
        ),
      ),

      // --- Dividers ---
      dividerTheme: const DividerThemeData(
        color: AppColors.grey,
        thickness: 1,
        space: 1,
      ),

      // --- Bottom Navigation ---
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w400,
          fontSize: 12,
        ),
      ),

      // --- Floating Action Button ---
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),

      // --- Snackbar ---
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textDark,
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: AppColors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // --- Chips ---
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.palePurple,
        selectedColor: AppColors.primary,
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: AppColors.textBody,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: AppColors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        side: BorderSide.none,
      ),

      // --- Dialog ---
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: AppColors.textDark,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: AppColors.textBody,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Text Theme
  // ---------------------------------------------------------------------------

  static const TextTheme _textTheme = TextTheme(
    // --- Outfit headlines ---
    displayLarge: TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w700,
      fontSize: 32,
      letterSpacing: -0.5,
      color: AppColors.textDark,
    ),
    displayMedium: TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w700,
      fontSize: 28,
      letterSpacing: -0.4,
      color: AppColors.textDark,
    ),
    displaySmall: TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w700,
      fontSize: 24,
      letterSpacing: -0.3,
      color: AppColors.textDark,
    ),
    headlineLarge: TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w700,
      fontSize: 22,
      letterSpacing: -0.3,
      color: AppColors.textDark,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w600,
      fontSize: 20,
      letterSpacing: -0.2,
      color: AppColors.textDark,
    ),
    headlineSmall: TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w600,
      fontSize: 18,
      letterSpacing: -0.1,
      color: AppColors.textDark,
    ),

    // --- Outfit titles ---
    titleLarge: TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w600,
      fontSize: 16,
      color: AppColors.textDark,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w600,
      fontSize: 14,
      color: AppColors.textDark,
    ),
    titleSmall: TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w600,
      fontSize: 12,
      color: AppColors.textDark,
    ),

    // --- Inter body ---
    bodyLarge: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w400,
      fontSize: 16,
      color: AppColors.textBody,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w400,
      fontSize: 14,
      color: AppColors.textBody,
    ),
    bodySmall: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w400,
      fontSize: 12,
      color: AppColors.textMuted,
    ),

    // --- Inter labels ---
    labelLarge: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w500,
      fontSize: 14,
      color: AppColors.textBody,
    ),
    labelMedium: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w500,
      fontSize: 12,
      color: AppColors.textBody,
    ),
    labelSmall: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w500,
      fontSize: 10,
      color: AppColors.textMuted,
    ),
  );
}
