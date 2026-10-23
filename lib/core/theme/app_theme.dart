import 'package:flutter/material.dart';

/// Blue-and-white logistics palette.
class AppColors {
  const AppColors._();

  static const primary = Color(0xFF1565C0);
  static const primaryDark = Color(0xFF0D47A1);
  static const primaryLight = Color(0xFFE3F0FF);
  static const surface = Colors.white;
  static const background = Color(0xFFF5F8FC);
  static const textPrimary = Color(0xFF1B2430);
  static const textSecondary = Color(0xFF5B6675);
  static const border = Color(0xFFDDE3EC);

  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFB26A00);
  static const danger = Color(0xFFC62828);
  static const info = Color(0xFF0277BD);
  static const neutral = Color(0xFF607D8B);

  // Dashboard palette: one colour per operation, so each stage is recognisable at a glance.
  static const indigo = Color(0xFF3949AB);
  static const purple = Color(0xFF8E24AA);
  static const teal = Color(0xFF00897B);
  static const orange = Color(0xFFF57C00);
  static const amber = Color(0xFFFFA000);
  static const cyan = Color(0xFF0288D1);
  static const pink = Color(0xFFD81B60);
  static const green = Color(0xFF2E7D32);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.danger,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: base.textTheme.apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          // From the theme's text style so the button keeps the app font family.
          textStyle: base.textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryLight,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }
}
