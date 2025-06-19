import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final Color primaryGreen = Color(0xFF65B292); // #65b292
final Color lightBackground = Color(0xFFFAFAFA);

final ThemeData appTheme = ThemeData(
  brightness: Brightness.light,
  primaryColor: primaryGreen,
  colorScheme: ColorScheme.fromSeed(
    seedColor: primaryGreen,
    primary: primaryGreen,
    secondary: primaryGreen,
    surface: Colors.white,
    onPrimary: Colors.white,
    onSurface: Color(0xFF222222),
  ),
  scaffoldBackgroundColor: Colors.white,
  appBarTheme: AppBarTheme(
    backgroundColor: primaryGreen,
    foregroundColor: Colors.white,
    elevation: 1,
    titleTextStyle: GoogleFonts.baloo2(
      fontWeight: FontWeight.w800,
      fontSize: 22,
      color: Colors.white,
      letterSpacing: 1,
    ),
  ),
  textTheme: GoogleFonts.baloo2TextTheme().copyWith(
    bodyLarge: GoogleFonts.baloo2(color: Color(0xFF222222)),
    bodyMedium: GoogleFonts.baloo2(color: Color(0xFF222222)),
    headlineMedium: GoogleFonts.baloo2(
      color: primaryGreen,
      fontWeight: FontWeight.bold,
      fontSize: 24,
    ),
    titleLarge: GoogleFonts.baloo2(
      color: primaryGreen,
      fontWeight: FontWeight.bold,
      fontSize: 20,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primaryGreen,
      foregroundColor: Colors.white,
      textStyle: GoogleFonts.baloo2(fontWeight: FontWeight.w600),
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 32),
      shape: StadiumBorder(),
      elevation: 2,
      shadowColor: Colors.black12,
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: primaryGreen,
      textStyle: GoogleFonts.baloo2(decoration: TextDecoration.underline),
    ),
  ),
  cardTheme: CardThemeData(
    color: lightBackground,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    ),
    elevation: 3,
    margin: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    shadowColor: Colors.black.withOpacity(0.08),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: primaryGreen, width: 2),
    ),
    labelStyle: GoogleFonts.baloo2(color: primaryGreen),
    floatingLabelStyle: GoogleFonts.baloo2(color: primaryGreen),
  ),
);
