import 'package:flutter/material.dart';

/// Same palette as the web application (frontend/src/theme/_tokens.scss): crimson brand,
/// indigo accent, cool grey page, one colour per status tone.
class AppColors {
  const AppColors._();

  static const primary = Color(0xFFD61F45); // --brand-600
  static const primaryDark = Color(0xFFB3123A); // --brand-700
  static const primaryLight = Color(0xFFFFF1F4); // --brand-50
  static const surface = Colors.white;
  static const background = Color(0xFFEDEFF3); // --page-bg
  static const textPrimary = Color(0xFF1E2140); // --content-fg
  static const textSecondary = Color(0xFF5D6285); // --content-muted
  static const border = Color(0xFFE0E3EC); // --surface-border

  /// Input and inset fill (--surface-muted), so fields read as wells.
  static const field = Color(0xFFEEF0F5);
  static const shadow = Color(0x140F172A);

  static const success = Color(0xFF16A34A);
  // The web's #F59E0B is too light for text on white; this is the web charts' amber.
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF4338CA); // --accent / --info
  static const neutral = Color(0xFF64748B);

  // Per-operation colours, taken from the web's tones so a stage looks the same on both.
  static const indigo = Color(0xFF4338CA); // info / accent
  static const purple = Color(0xFFB3123A); // brand strong
  static const teal = Color(0xFF0D9488);
  static const orange = Color(0xFFD97706); // warning
  static const amber = Color(0xFFF59E0B);
  static const cyan = Color(0xFF2563EB); // web chart blue
  static const pink = Color(0xFFE23459); // brand-500
  static const green = Color(0xFF16A34A); // success

  // Side menu: floating crimson panel. Labels are full white because 88% white fails
  // AA on the light top of the gradient; pressed/hover darkens for the same reason.
  static const sidebarText = Colors.white;
  static const sidebarPillBg = Colors.white;
  static const sidebarPillFg = Color(0xFFB3123A);
  static const sidebarPressed = Color(0x24000000); // black 14%
  static const sidebarInset = Color(0x24000000);
  static const sidebarPillShadow = Color(0x2E000000); // black 18%
  static const sidebarShadow = Color(0x1F4338CA); // indigo 12%
  static const focusRing = Color(0xFF4338CA);
  static const glass = Color(0xB8FFFFFF); // white 72%
  static const scrim = Color(0x73141428); // rgb(20 20 40 / 45%)
  static const sidebarGradient = LinearGradient(
    // 170deg: top to bottom, leaning slightly left to right.
    begin: Alignment(-0.18, -1),
    end: Alignment(0.18, 1),
    colors: [Color(0xFFE02550), Color(0xFFB3123A), Color(0xFF7A0E33)],
    stops: [0, 0.55, 1],
  );
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.info,
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
        elevation: 2,
        shadowColor: AppColors.shadow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.field,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
        prefixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide.none,
        backgroundColor: AppColors.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.field,
          selectedBackgroundColor: AppColors.primary,
          selectedForegroundColor: Colors.white,
          side: BorderSide.none,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.primary, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: base.textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.textSecondary),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          // From the theme's text style so the button keeps the app font family.
          textStyle: base.textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.14),
        elevation: 8,
        shadowColor: AppColors.shadow,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
