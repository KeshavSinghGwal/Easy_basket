import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color primaryYellow = Color(0xFFFFC107);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color grey = Color(0xFF757575);
  static const Color lightGrey = Color(0xFFF5F5F5);
  static const Color darkGrey = Color(0xFF424242);

  // 3D Soft Shadow — gives depth/elevation feel to cards
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 16,
      spreadRadius: 0,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.02),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  // Deeper shadow for elevated cards (banners, CTAs)
  static List<BoxShadow> get deepShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.1),
      blurRadius: 20,
      spreadRadius: 0,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  // Green glow shadow for green buttons/cards
  static List<BoxShadow> get greenGlow => [
    BoxShadow(
      color: primaryGreen.withValues(alpha: 0.25),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  // Standard card decoration with 3D feel
  static BoxDecoration softCard({Color? color, double radius = 16}) => BoxDecoration(
    color: color ?? Colors.white,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: softShadow,
  );

  // Gradient for primary buttons
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF0A5C18), Color(0xFF1B8A2E), Color(0xFF0A5C18)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    stops: [0.0, 0.5, 1.0],
  );

  static BoxDecoration get gradientButtonDecoration => BoxDecoration(
    gradient: primaryGradient,
    borderRadius: BorderRadius.circular(12),
  );

  /// Wraps any child (usually ElevatedButton) with the brand gradient
  static Widget gradientButton({
    required VoidCallback? onPressed,
    required Widget child,
    double? width,
    double height = 48,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 24),
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: onPressed != null ? primaryGradient : null,
        color: onPressed == null ? grey.withValues(alpha: 0.3) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: padding,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  /// Theme for a given language.
  ///
  /// Poppins ships Latin AND Devanagari, so English and Hindi both render
  /// correctly on it. It has NO Gurmukhi coverage, so Punjabi falls back to
  /// Noto Sans Gurmukhi — without this every Punjabi screen renders as tofu
  /// boxes no matter how good the translations are.
  static ThemeData themeFor(String languageCode) {
    return languageCode == 'pa' ? _buildTheme(gurmukhi: true) : lightTheme;
  }

  static ThemeData get lightTheme => _buildTheme(gurmukhi: false);

  static ThemeData _buildTheme({required bool gurmukhi}) {
    final baseTextTheme = gurmukhi
        ? GoogleFonts.notoSansGurmukhiTextTheme()
        : GoogleFonts.poppinsTextTheme();

    TextStyle headingFont({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
    }) {
      return gurmukhi
          ? GoogleFonts.notoSansGurmukhi(
              color: color, fontSize: fontSize, fontWeight: fontWeight)
          : GoogleFonts.poppins(
              color: color, fontSize: fontSize, fontWeight: fontWeight);
    }

    return ThemeData(
      useMaterial3: true,
      fontFamily: gurmukhi
          ? GoogleFonts.notoSansGurmukhi().fontFamily
          : GoogleFonts.poppins().fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        secondary: primaryYellow,
      ),
      scaffoldBackgroundColor: white,
      appBarTheme: AppBarTheme(
        backgroundColor: white,
        elevation: 0,
        iconTheme: const IconThemeData(color: black),
        titleTextStyle: headingFont(
          color: black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: black,
        ),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: black,
        ),
        displaySmall: baseTextTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: black,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: black,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: black,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: black,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: grey,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: headingFont(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightGrey,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
