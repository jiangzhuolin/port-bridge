import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/config_store.dart';
import '../domain/rule.dart';
import '../platform/desktop_integration.dart';
import 'engine_client.dart';

class LogEntry {
  LogEntry(this.code, {this.name, this.detail = ''}) : time = DateTime.now();
  final DateTime time;
  final String code, detail;
  final String? name;
}

class BridgeController extends ChangeNotifier {
  BridgeController({
    required this.store,
    required this.engine,
    required this.desktop,
  });
  final ConfigStore store;
  final EngineClient engine;
  final DesktopIntegration desktop;
  List<ForwardRule> rules = [];
  final states = <String, String>{};
  final metrics = <String, Map<String, dynamic>>{};
  final logs = <LogEntry>[];
  String language = 'en';
  String? selectedId;
  Object? configError, settingsError;
  bool autostart = false,
      ready = false,
      saving = false,
      closing = false,
      engineFailed = false;
  StreamSubscription<dynamic>? _subscription;

  ForwardRule? get selected =>
      rules.where((r) => r.id == selectedId).firstOrNull;
  String state(String id) => states[id] ?? 'stopped';
  bool busy(String id) =>
      ['running', 'starting', 'stopping'].contains(state(id));
  int get running => rules.where((r) => state(r.id) == 'running').length;
  int total(String key) =>
      metrics.values.fold(0, (sum, item) => sum + (item[key] as int? ?? 0));

  Future<void> initialize() async {
    _subscription = engine.events.listen((event) {
      switch (event['type']) {
        case 'status':
          final id = event['id'] as String;
          states[id] = event['state'] as String;
          if (state(id) == 'stopped') metrics[id]?['connections'] = 0;
        case 'stats':
          final data = Map<String, dynamic>.from(event['data'] as Map);
          for (final item in data.entries) {
            metrics[item.key] = Map<String, dynamic>.from(item.value as Map);
          }
        case 'log':
          _log(
            event['code'] as String,
            name: event['name'] as String?,
            detail: event['detail'] as String? ?? '',
          );
        case 'fatal':
          engineFailed = true;
          for (final rule in rules) {
            states[rule.id] = 'failed';
            metrics[rule.id]?['connections'] = 0;
          }
          _log('engineStopped');
      }
      if (!closing) notifyListeners();
    });
    try {
      final settings = await store.loadSettings();
      language = settings['language'] == 'zh_CN' ? 'zh_CN' : 'en';
    } catch (error) {
      settingsError = error;
    }
    try {
      rules = await store.loadRules();
    } catch (error) {
      configError = error;
    }
    try {
      autostart = await desktop.isAutostartEnabled();
    } catch (error) {
      _log('autostartFailed', detail: error.toString());
    }
    ready = true;
    _log('readyLog');
    notifyListeners();
    if (configError == null) {
      for (final rule in rules.where((r) => r.autoStart)) {
        try {
          await start(rule);
        } catch (_) {
          /* Failure is reported by status and log. */
        }
      }
    }
  }

  void select(String id) {
    selectedId = id;
    notifyListeners();
  }

  void _log(String code, {String? name, String detail = ''}) {
    logs.add(LogEntry(code, name: name, detail: detail));
    if (logs.length > 500) logs.removeRange(0, logs.length - 500);
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  Future<void> saveRule(ForwardRule rule) async {
    if (configError != null) throw const BridgeException('configProtected');
    if (saving || busy(rule.id)) throw const BridgeException('stopBeforeEdit');
    rule.validate();
    saving = true;
    notifyListeners();
    try {
      final next = [...rules];
      final index = next.indexWhere((r) => r.id == rule.id);
      if (index < 0) {
        next.add(rule);
      } else {
        next[index] = rule;
      }
      await store.saveRules(next);
      rules = next;
      selectedId = rule.id;
      _log('ruleSaved', name: rule.name);
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> deleteRule(ForwardRule rule) async {
    if (configError != null) throw const BridgeException('configProtected');
    if (saving || busy(rule.id)) throw const BridgeException('stopBeforeEdit');
    saving = true;
    notifyListeners();
    try {
      final next = rules.where((r) => r.id != rule.id).toList();
      await store.saveRules(next);
      rules = next;
      states.remove(rule.id);
      metrics.remove(rule.id);
      if (selectedId == rule.id) selectedId = null;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> start(ForwardRule rule) async {
    if (closing ||
        saving ||
        engineFailed ||
        configError != null ||
        busy(rule.id)) {
      return;
    }
    states[rule.id] = 'starting';
    metrics.remove(rule.id);
    notifyListeners();
    try {
      await engine.start(rule);
    } catch (error) {
      states[rule.id] = 'failed';
      rethrow;
    } finally {
      if (!closing) notifyListeners();
    }
  }

  Future<void> stop(ForwardRule rule) async {
    if (closing || !busy(rule.id)) return;
    states[rule.id] = 'stopping';
    notifyListeners();
    await engine.stop(rule.id);
  }

  Future<void> startAll() async {
    for (final rule in rules) {
      try {
        await start(rule);
      } catch (_) {}
    }
  }

  Future<void> stopAll() async {
    for (final rule in rules) {
      await stop(rule);
    }
  }

  Future<void> setLanguage(String value) async {
    await store.saveLanguage(value);
    language = value;
    settingsError = null;
    notifyListeners();
  }

  Future<void> setAutostart(bool value) async {
    await desktop.setAutostart(value);
    autostart = value;
    notifyListeners();
  }

  Future<void> shutdown() async {
    if (closing) return;
    closing = true;
    try {
      await engine.close();
    } finally {
      await _subscription?.cancel();
    }
  }
}
