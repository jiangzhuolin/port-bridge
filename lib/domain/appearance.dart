enum AppThemeMode { system, light, dark }

enum AppAccent { teal, blue, violet, amber }

class Appearance {
  const Appearance({
    this.mode = AppThemeMode.system,
    this.accent = AppAccent.teal,
  });
  final AppThemeMode mode;
  final AppAccent accent;

  factory Appearance.fromSettings(Map<String, dynamic> settings) => Appearance(
    mode:
        AppThemeMode.values
            .where((v) => v.name == settings['theme_mode'])
            .firstOrNull ??
        AppThemeMode.system,
    accent:
        AppAccent.values
            .where((v) => v.name == settings['accent_color'])
            .firstOrNull ??
        AppAccent.teal,
  );
}
