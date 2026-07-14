import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Visuelle Richtung: frische Küche — Blattgrün + Tomatenrot auf mintigem Fond.
class AppTheme {
  static const Color seed = Color(0xFF1F6B4A);
  static const Color seedSoft = Color(0xFF3D8F6A);
  static const Color accent = Color(0xFFE4572E);
  static const Color accentSoft = Color(0xFFFFF0EB);
  static const Color mist = Color(0xFFEFF5F0);
  static const Color mistDeep = Color(0xFFE2EEE6);
  static const Color ink = Color(0xFF1A2E24);
  static const Color inkMuted = Color(0xFF4A5C52);
  static const Color cream = mist; // Alias für ältere Screens

  static ThemeData light() {
    final display = GoogleFonts.soraTextTheme();
    final body = GoogleFonts.nunitoSansTextTheme();

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: seed,
      secondary: accent,
      surface: Colors.white,
      onSurface: ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: mist,
      textTheme: body.copyWith(
        displaySmall: display.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.1,
          letterSpacing: -0.5,
        ),
        headlineMedium: display.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.15,
          letterSpacing: -0.4,
        ),
        headlineSmall: display.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.2,
        ),
        titleLarge: display.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: display.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: body.bodyLarge?.copyWith(color: ink, height: 1.45),
        bodyMedium: body.bodyMedium?.copyWith(color: inkMuted, height: 1.45),
        labelLarge: body.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: mist.withValues(alpha: 0.92),
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: display.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: ink,
          fontSize: 20,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 2,
        extendedTextStyle: body.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: seed.withValues(alpha: 0.1)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: seed.withValues(alpha: 0.18)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: seed.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: seed, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: body.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: seed,
          side: BorderSide(color: seed.withValues(alpha: 0.35)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: mistDeep,
        labelStyle: body.bodyMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Leichter Verlauf + Punkte für mehr Atmosphere auf der Fläche.
  static BoxDecoration pageBackdrop() {
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFF7FBF8),
          mist,
          Color(0xFFE8F2EB),
        ],
      ),
    );
  }
}

/// Dezente Punkt-Textur über dem Hintergrund.
class KitchenDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.seed.withValues(alpha: 0.045)
      ..style = PaintingStyle.fill;
    const step = 28.0;
    for (var y = 12.0; y < size.height; y += step) {
      for (var x = 12.0; x < size.width; x += step) {
        final offset = ((y / step).floor().isEven) ? 0.0 : step / 2;
        canvas.drawCircle(Offset(x + offset, y), 1.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
