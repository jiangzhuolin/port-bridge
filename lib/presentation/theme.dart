import 'package:flutter/material.dart';

import '../domain/appearance.dart';

Color accentSeed(AppAccent accent) => switch (accent) {
  AppAccent.teal => const Color(0xFF087F8C),
  AppAccent.blue => const Color(0xFF2563EB),
  AppAccent.violet => const Color(0xFF7C3AED),
  AppAccent.amber => const Color(0xFFAF6500),
};

ThemeData bridgeTheme({
  Brightness brightness = Brightness.light,
  AppAccent accent = AppAccent.teal,
}) {
  final colors = ColorScheme.fromSeed(
    seedColor: accentSeed(accent),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surfaceContainerLow,
    fontFamilyFallback: const [
      'Inter',
      'Segoe UI',
      'PingFang SC',
      'Microsoft YaHei',
      'Noto Sans CJK SC',
    ],
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
        letterSpacing: -1,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      bodyMedium: TextStyle(fontSize: 14, color: colors.onSurface),
      bodySmall: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
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
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    ),
    dividerColor: colors.outlineVariant,
  );
}

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
