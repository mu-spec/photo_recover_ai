import 'package:flutter/material.dart';

class AppTheme {
  // Dark mode flag - set from main.dart when theme changes
  static bool _isDark = false;
  static set isDarkMode(bool value) => _isDark = value;
  static bool get isDarkMode => _isDark;

  // Brand colors (always constant)
  static const Color primaryColor = Color(0xFF6C63FF);
  static const Color primaryDark = Color(0xFF5A52E0);
  static const Color primaryLight = Color(0xFF8B83FF);
  static const Color accentColor = Color(0xFF00D9A6);
  static const Color warningColor = Color(0xFFFF6B6B);
  static const Color successColor = Color(0xFF10B981);
  static const Color cardShadow = Color(0x0A000000);

  // Light theme colors
  static const Color lightBackgroundColor = Color(0xFFF8F9FE);
  static const Color lightSurfaceColor = Colors.white;
  static const Color lightTextPrimary = Color(0xFF1A1A2E);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightTextLight = Color(0xFF9CA3AF);
  static const Color lightDividerColor = Color(0xFFF0F0F5);

  // Dark theme colors
  static const Color darkBackgroundColor = Color(0xFF0F172A);
  static const Color darkSurfaceColor = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextLight = Color(0xFF64748B);
  static const Color darkDividerColor = Color(0xFF334155);

  // Dynamic theme colors (automatically switch based on dark mode)
  static Color get backgroundColor => _isDark ? darkBackgroundColor : lightBackgroundColor;
  static Color get surfaceColor => _isDark ? darkSurfaceColor : lightSurfaceColor;
  static Color get textPrimary => _isDark ? darkTextPrimary : lightTextPrimary;
  static Color get textSecondary => _isDark ? darkTextSecondary : lightTextSecondary;
  static Color get textLight => _isDark ? darkTextLight : lightTextLight;
  static Color get dividerColor => _isDark ? darkDividerColor : lightDividerColor;

  /// Get theme-aware colors based on current BuildContext
  static Color getPrimaryTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextPrimary
        : lightTextPrimary;
  }

  static Color getSecondaryTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextSecondary
        : lightTextSecondary;
  }

  static Color getLightTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextLight
        : lightTextLight;
  }

  static Color getBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkBackgroundColor
        : lightBackgroundColor;
  }

  static Color getSurfaceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurfaceColor
        : lightSurfaceColor;
  }

  static Color getDividerColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkDividerColor
        : lightDividerColor;
  }

  /// Get the current theme-aware text primary color.
  /// Use this in widgets that need to adapt to dark mode.
  static Color textColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextPrimary
        : lightTextPrimary;
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: accentColor,
        surface: lightSurfaceColor,
        error: warningColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextPrimary,
      ),
      scaffoldBackgroundColor: lightBackgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: lightTextPrimary),
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: lightSurfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        shadowColor: cardShadow,
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor, width: 2),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightBackgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: lightDividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightBackgroundColor,
        selectedColor: primaryColor.withOpacity(0.1),
        secondarySelectedColor: primaryColor,
        labelStyle: const TextStyle(color: lightTextPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightSurfaceColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: lightTextLight,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: lightDividerColor,
      ),
      dividerTheme: const DividerThemeData(
        color: lightDividerColor,
        thickness: 1,
        space: 0,
      ),
    );
  }
}
