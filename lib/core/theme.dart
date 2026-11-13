import 'package:flutter/material.dart';

/// CULINEX brand: premium minimalist black, white and gold.
class Brand {
  static const black = Color(0xFF111111);
  static const gold = Color(0xFFB8963E);
  static const goldSoft = Color(0xFFF4EBD3);
  static const white = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF7F6F3);
  static const grey = Color(0xFF6B6B6B);
  static const danger = Color(0xFFB3261E);
  static const ok = Color(0xFF1E6B52);
  static const tagline = 'Know Your Cost. Control Your Business.';
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.gold,
    brightness: Brightness.light,
  ).copyWith(
    primary: Brand.black,
    onPrimary: Brand.white,
    secondary: Brand.gold,
    onSecondary: Brand.black,
    surface: Brand.white,
    error: Brand.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.black,
      foregroundColor: Brand.white,
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.black,
        foregroundColor: Brand.gold,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Brand.white,
      indicatorColor: Brand.goldSoft,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.black,
      foregroundColor: Brand.gold,
    ),
  );
}
