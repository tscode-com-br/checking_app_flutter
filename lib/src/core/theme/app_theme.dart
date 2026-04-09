import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color primary = Color(0xFF007AFF);
  static const Color background = Color(0xFFF9F9FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textMain = Color(0xFF1D1D1F);
  static const Color textSoft = Color(0xFF86868B);
  static const Color border = Color(0xFFE5E5E7);
  static const Color success = Color(0xFF1F7A3E);
  static const Color warning = Color(0xFFA15C00);
  static const Color error = Color(0xFFC62828);

  static ThemeData build() {
    const colorScheme = ColorScheme.light(
      primary: primary,
      surface: surface,
      onSurface: textMain,
      onPrimary: Colors.white,
      outline: border,
      error: error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: textMain,
          height: 1.05,
        ),
        bodyMedium: TextStyle(fontSize: 15, color: textSoft),
        titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSoft),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF2F2F7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black.withValues(alpha: 0.82),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}