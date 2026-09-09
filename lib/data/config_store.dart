import 'dart:convert';
import 'dart:io';

import '../domain/rule.dart';
import '../domain/appearance.dart';
import '../domain/window_preferences.dart';

class ConfigStore {
  ConfigStore(this.directory);
  final Directory directory;
  File get rulesFile => File('${directory.path}/rules.json');
  File get settingsFile => File('${directory.path}/settings.json');

  Future<List<ForwardRule>> loadRules() async {
    if (!await rulesFile.exists()) return [];
    final data = jsonDecode(await rulesFile.readAsString());
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['rules'] is! List) {
      throw const BridgeException('invalidConfig');
    }
    final rules = (data['rules'] as List).map((item) {
      if (item is! Map<String, dynamic>) {
        throw const BridgeException('invalidConfig');
      }
      return ForwardRule.fromJson(item);
    }).toList();
    if (rules.map((r) => r.id).toSet().length != rules.length) {
      throw const BridgeException('duplicateIds');
    }
    return rules;
  }

  Future<Map<String, dynamic>> loadSettings() async {
    if (!await settingsFile.exists()) return {};
    final data = jsonDecode(await settingsFile.readAsString());
    if (data is! Map<String, dynamic>) {
      throw const BridgeException('invalidSettings');
    }
    return data;
  }

  Future<void> saveRules(List<ForwardRule> rules) async {
    for (final rule in rules) {
      rule.validate();
    }
    if (rules.map((r) => r.id).toSet().length != rules.length) {
      throw const BridgeException('duplicateIds');
    }
    await _write(rulesFile, {
      'version': 1,
      'rules': rules.map((r) => r.toJson()).toList(),
    });
  }

  Future<void> saveLanguage(String language) async {
    if (!['en', 'zh_CN'].contains(language)) {
      throw const BridgeException('invalidLanguage');
    }
    final settings = await loadSettings();
    settings['language'] = language;
    await _write(settingsFile, settings);
  }

  Future<void> saveAppearance(Appearance appearance) async {
    final settings = await loadSettings();
    settings['theme_mode'] = appearance.mode.name;
    settings['accent_color'] = appearance.accent.name;
    await _write(settingsFile, settings);
  }

  Future<void> saveWindowPreferences(WindowPreferences preferences) async {
    final settings = await loadSettings();
    settings['minimize_to_tray'] = preferences.minimizeToTray;
    settings['close_action'] = preferences.closeAction.name;
    settings['close_action_confirmed'] = preferences.closeActionConfirmed;
    await _write(settingsFile, settings);
  }

  Future<void> _write(File destination, Object value) async {
    await directory.create(recursive: true);
    final temp = File('${destination.path}.${ForwardRule.newId()}.tmp');
    try {
      await temp.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(value)}\n',
        flush: true,
      );
      await temp.rename(destination.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
