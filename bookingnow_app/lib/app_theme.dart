import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tema de BookingNow — paleta "teal y ámbar".
///
/// Primario teal (confianza, válido para cualquier sector), acento ámbar
/// (energía: avisos, pendientes, destacados), tinta azul noche para textos y
/// fondos oscuros, superficies tintadas en lugar de blanco plano.
class AppTheme {
  // Marca
  static const primary = Color(0xFF0D9488); // teal 600
  static const primaryDark = Color(0xFF0F766E); // teal 700
  static const primaryDeep = Color(0xFF134E4A); // teal 900
  static const primaryLight = Color(0xFF5EEAD4); // teal 300
  static const accent = Color(0xFFF59E0B); // ámbar 500
  static const accentDark = Color(0xFFB45309); // ámbar 700
  static const ink = Color(0xFF111318); // grafito
  static const inkSoft = Color(0xFF3A3F47);

  // Estados
  static const success = Color(0xFF10B981);
  static const warning = accent;
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF0EA5E9);

  // Superficies
  static const surfaceLight = Color(0xFFFAFAF7); // blanco cálido (hueso)
  static const cardLight = Colors.white;
  static const surfaceDark = Color(0xFF121417); // grafito neutro
  static const cardDark = Color(0xFF1C1F24);
  static const chipLight = Color(0xFFEFEEE9);
  static const chipDark = Color(0xFF262A30);

  /// Degradado de marca para cabeceras, splash y tarjetas destacadas.
  static const brandGradient = LinearGradient(
    colors: [primary, primaryDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Degradado "hero" más luminoso (portadas sin imagen).
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF14B8A6), primaryDark, primaryDeep],
    stops: [0, 0.55, 1],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Degradado ámbar para destacados (promos, bonos).
  static const accentGradient = LinearGradient(
    colors: [Color(0xFFFBBF24), accentDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Sombra suave y teñida para tarjetas elevadas.
  static List<BoxShadow> softShadow(Brightness b) => [
        BoxShadow(
          color: (b == Brightness.dark ? Colors.black : primaryDeep)
              .withValues(alpha: b == Brightness.dark ? 0.35 : 0.08),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: b,
      primary: isDark ? const Color(0xFF2DD4BF) : primary,
      onPrimary: isDark ? const Color(0xFF0B1F1D) : Colors.white,
      secondary: accent,
      onSecondary: ink,
      tertiary: info,
      error: danger,
      surface: isDark ? cardDark : cardLight,
      onSurface: isDark ? const Color(0xFFF3F4F6) : ink,
      surfaceContainerHighest: isDark ? chipDark : chipLight,
      outline: isDark ? const Color(0xFF8A8F98) : const Color(0xFF6B7280),
      outlineVariant: isDark ? const Color(0xFF2A2E35) : const Color(0xFFE8E7E1),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? surfaceDark : surfaceLight,
    );

    // Titulares con Plus Jakarta Sans (más carácter), cuerpo con Inter.
    final body = GoogleFonts.interTextTheme(base.textTheme);
    final display = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);
    final text = body.copyWith(
      displayLarge: display.displayLarge?.copyWith(fontWeight: FontWeight.w800),
      displayMedium: display.displayMedium?.copyWith(fontWeight: FontWeight.w800),
      displaySmall: display.displaySmall?.copyWith(fontWeight: FontWeight.w800),
      headlineLarge: display.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineMedium: display.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: display.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleLarge: display.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: display.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: display.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    final radius12 = BorderRadius.circular(12);
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? surfaceDark : surfaceLight,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      // Tarjetas que "flotan": sin borde, sombra suave y teñida (opción 1).
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 3,
        shadowColor: ink.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isDark ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.primary, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          textStyle: text.titleSmall,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 1.5),
          textStyle: text.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const StadiumBorder(),
        elevation: 4,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
        backgroundColor: isDark ? chipDark : chipLight,
        selectedColor: scheme.primary.withValues(alpha: 0.18),
        labelStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
        elevation: 3,
        shadowColor: ink.withValues(alpha: 0.25),
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.outline,
        indicatorColor: scheme.primary,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.7), space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: scheme.surface,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        showDragHandle: true,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
    );
  }
}

/// Colores de estado de reserva, comunes a toda la app.
Color bookingStatusColor(String status) {
  switch (status) {
    case 'pending':
      return AppTheme.accent;
    case 'confirmed':
      return AppTheme.primary;
    case 'checked_in':
      return AppTheme.info;
    case 'completed':
      return AppTheme.success;
    case 'cancelled':
      return const Color(0xFF94A3B8);
    case 'no_show':
      return AppTheme.danger;
    default:
      return const Color(0xFF94A3B8);
  }
}
