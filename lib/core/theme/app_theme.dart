import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Light Mode Colors (Orange & White Futuristic Minimalist)
  static const _primaryColor = Color(0xFFFF5C00);      // High energy futuristic orange
  static const _secondaryColor = Color(0xFFFF9E00);    // Warm glow amber orange
  static const _backgroundColor = Color(0xFFFAFAFA);   // Ultra clean warm white
  static const _surfaceColor = Color(0xFFFFFFFF);      // Pure white card surfaces
  static const _textPrimary = Color(0xFF111116);       // Deep obsidian text (high contrast)
  static const _textSecondary = Color(0xFF70727D);     // Warm mid-gray details

  // Dark Mode Colors (Obsidian Cyber & Neon Orange Accent)
  static const _darkPrimaryColor = Color(0xFFFF6B00);  // Hyper neon orange
  static const _darkSecondaryColor = Color(0xFFFFAC1C); // Cyber neon amber
  static const _darkBackgroundColor = Color(0xFF090A0F); // Pure cyber black-obsidian
  static const _darkSurfaceColor = Color(0xFF141622);    // Deep dark titanium-gray surface
  static const _darkTextPrimary = Color(0xFFFAFAFC);    // Crisp white text
  static const _darkTextSecondary = Color(0xFF90939F);  // Sleek space-gray details

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: _primaryColor,
        secondary: _secondaryColor,
        surface: _surfaceColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: _textPrimary,
      ),
      scaffoldBackgroundColor: _backgroundColor,
      dividerColor: const Color(0xFFEAEAEE),
      textTheme: GoogleFonts.outfitTextTheme().copyWith(
        headlineMedium: GoogleFonts.outfit(
          color: _textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
        ),
        titleLarge: GoogleFonts.outfit(
          color: _textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        bodyLarge: GoogleFonts.outfit(
          color: _textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: GoogleFonts.outfit(
          color: _textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: _textPrimary, size: 24),
        titleTextStyle: TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 22,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: _surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0xFFEDEDF2), width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: _primaryColor,
        unselectedItemColor: _textSecondary,
        elevation: 0,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: _darkPrimaryColor,
        secondary: _darkSecondaryColor,
        surface: _darkSurfaceColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: _darkTextPrimary,
      ),
      scaffoldBackgroundColor: _darkBackgroundColor,
      dividerColor: const Color(0xFF222431),
      textTheme: GoogleFonts.outfitTextTheme().copyWith(
        headlineMedium: GoogleFonts.outfit(
          color: _darkTextPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
        ),
        titleLarge: GoogleFonts.outfit(
          color: _darkTextPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        bodyLarge: GoogleFonts.outfit(
          color: _darkTextPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: GoogleFonts.outfit(
          color: _darkTextSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: _darkTextPrimary, size: 24),
        titleTextStyle: TextStyle(
          color: _darkTextPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 22,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: _darkSurfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0xFF222431), width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: _darkPrimaryColor,
        unselectedItemColor: _darkTextSecondary,
        elevation: 0,
      ),
    );
  }
}
