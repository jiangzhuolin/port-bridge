import 'package:flutter/material.dart';

const ink = Color(0xFF172C3B);
const muted = Color(0xFF70828E);
const accent = Color(0xFF087F8C);
const canvas = Color(0xFFF3F6F8);
const border = Color(0xFFE2E9ED);

ThemeData bridgeTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: accent,
    primary: accent,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: canvas,
  fontFamilyFallback: const [
    'Inter',
    'Segoe UI',
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
  ],
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: ink,
      letterSpacing: -1,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodyMedium: TextStyle(fontSize: 14, color: ink),
    bodySmall: TextStyle(fontSize: 12, color: muted),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      side: const BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF7F9FA),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: border),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
  ),
  dividerColor: border,
);

String humanBytes(int bytes) {
  var value = bytes.toDouble();
  for (final unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB']) {
    if (value < 1024 || unit == 'TiB') {
      return '${unit == 'B' ? bytes : value.toStringAsFixed(1)} $unit';
    }
    value /= 1024;
  }
  return '$bytes B';
}
