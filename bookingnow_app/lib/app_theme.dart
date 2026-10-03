import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tema de BookingNow: limpio, claro por defecto (negocios de cualquier
/// sector), con modo oscuro. Color primario índigo + acento verde menta.
class AppTheme {
  static const primary = Color(0xFF4F46E5);
  static const primaryDark = Color(0xFF3730A3);
  static const accent = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const ink = Color(0xFF0F172A);
  static const surfaceLight = Color(0xFFF8FAFC);
  static const surfaceDark = Color(0xFF0F172A);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: b,
      primary: isDark ? const Color(0xFF818CF8) : primary,
      secondary: accent,
      error: danger,
      surface: isDark ? const Color(0xFF1E293B) : Colors.white,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? surfaceDark : surfaceLight,
    );
    final text = GoogleFonts.interTextTheme(base.textTheme);
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? surfaceDark : surfaceLight,
        foregroundColor: isDark ? Colors.white : ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : ink,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStatePropertyAll(
            text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
      ),
      dividerTheme: DividerThemeData(
          color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

/// Colores de estado de reserva, comunes a toda la app.
Color bookingStatusColor(String status) {
  switch (status) {
    case 'pending':
      return AppTheme.warning;
    case 'confirmed':
      return AppTheme.primary;
    case 'checked_in':
      return const Color(0xFF0EA5E9);
    case 'completed':
      return AppTheme.accent;
    case 'cancelled':
      return Colors.grey;
    case 'no_show':
      return AppTheme.danger;
    default:
      return Colors.grey;
  }
}
