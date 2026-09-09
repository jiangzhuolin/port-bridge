import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:port_bridge/application/bridge_controller.dart';
import 'package:port_bridge/application/engine_client.dart';
import 'package:port_bridge/data/config_store.dart';
import 'package:port_bridge/domain/bridge_engine.dart';
import 'package:port_bridge/domain/rule.dart';
import 'package:port_bridge/platform/desktop_integration.dart';
import 'package:port_bridge/presentation/bridge_app.dart';

class MemoryStore extends ConfigStore {
  MemoryStore() : super(Directory('/test/config'));
  List<ForwardRule> rules = [];
  String language = 'en';
  bool failSave = false;
  @override
  Future<List<ForwardRule>> loadRules() async => rules;
  @override
  Future<Map<String, dynamic>> loadSettings() async => {'language': language};
  @override
  Future<void> saveRules(List<ForwardRule> value) async {
    if (failSave) throw const FileSystemException('Read only');
    rules = value;
  }

  @override
  Future<void> saveLanguage(String value) async {
    language = value;
  }
}

class FakeEngine implements EngineClient {
  final output = StreamController<EngineEvent>.broadcast(sync: true);
  int starts = 0, stops = 0;
  @override
  Stream<EngineEvent> get events => output.stream;
  @override
  Future<void> start(ForwardRule rule) async {
    starts++;
    output.add({'type': 'status', 'id': rule.id, 'state': 'running'});
  }

  @override
  Future<void> stop(String id) async {
    stops++;
    output.add({'type': 'status', 'id': id, 'state': 'stopped'});
  }

  @override
  Future<void> close() => output.close();
}

class FakeDesktop implements DesktopIntegration {
  bool enabled = false;
  @override
  String get runtimeLabel => 'linux · x86_64';
  @override
  Future<bool> isAutostartEnabled() async => enabled;
  @override
  Future<void> setAutostart(bool value) async {
    enabled = value;
  }
}

void main() {
  late MemoryStore store;
  late FakeEngine engine;
  late BridgeController controller;
  setUp(() async {
    store = MemoryStore();
    engine = FakeEngine();
    controller = BridgeController(
      store: store,
      engine: engine,
      desktop: FakeDesktop(),
    );
    await controller.initialize();
  });
  tearDown(() async {
    await controller.shutdown();
    controller.dispose();
  });

  Future<void> open(
    WidgetTester tester, [
    Size size = const Size(1360, 900),
  ]) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(BridgeApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets('create, start, change language live, persist and stop', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Make the connection.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('addRule')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ruleName')), 'Local API');
    await tester.enterText(
      find.byKey(const ValueKey('targetHost')),
      'localhost',
    );
    await tester.tap(find.byKey(const ValueKey('saveRule')));
    await tester.pumpAndSettle();
    expect(store.rules.single.name, 'Local API');
    final id = store.rules.single.id;
    await tester.tap(find.byKey(ValueKey('toggle-$id')));
    await tester.pumpAndSettle();
    expect(controller.state(id), 'running');
    await tester.tap(find.byKey(const ValueKey('settingsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
    expect(store.language, 'zh_CN');
    expect(engine.starts, 1);
    expect(engine.stops, 0);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('toggle-$id')));
    await tester.pumpAndSettle();
    expect(controller.state(id), 'stopped');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save keeps dialog and in-memory rules unchanged', (
    tester,
  ) async {
    store.failSave = true;
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('addRule')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ruleName')), 'Service');
    await tester.enterText(
      find.byKey(const ValueKey('targetHost')),
      'localhost',
    );
    await tester.tap(find.byKey(const ValueKey('saveRule')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ruleError')), findsOneWidget);
    expect(controller.rules, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact desktop has usable settings and no overflow', (
    tester,
  ) async {
    await open(tester, const Size(800, 600));
    await tester.tap(find.byKey(const ValueKey('settingsButton')));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
