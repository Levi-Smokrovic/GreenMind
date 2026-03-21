import 'package:flutter/material.dart';

const _green = Color(0xFF16A34A);

final greenMindTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _green,
    brightness: Brightness.light,
  ),
  scaffoldBackgroundColor: const Color(0xFFF9FAFB),
  appBarTheme: const AppBarTheme(
    backgroundColor: _green,
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: true,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _green,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
);
