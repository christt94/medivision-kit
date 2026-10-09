import 'package:flutter/material.dart';

class AppTheme {
  static const _primary = Color(0xFF01696F);
  static const _primaryDark = Color(0xFF4F98A3);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _primary, brightness: Brightness.light),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _primaryDark, brightness: Brightness.dark),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
  );
}
