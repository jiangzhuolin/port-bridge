import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:port_bridge/application/bridge_controller.dart';
import 'package:port_bridge/application/engine_client.dart';
import 'package:port_bridge/data/config_store.dart';
import 'package:port_bridge/domain/bridge_engine.dart';
import 'package:port_bridge/domain/rule.dart';
import 'package:port_bridge/domain/appearance.dart';
import 'package:port_bridge/domain/window_preferences.dart';
import 'package:port_bridge/platform/desktop_integration.dart';
import 'package:port_bridge/presentation/bridge_app.dart';

class MemoryStore extends ConfigStore {
  MemoryStore() : super(Directory('/test/config'));
  List<ForwardRule> rules = [];
  String language = 'en';
  Appearance appearance = const Appearance();
  WindowPreferences windowPreferences = const WindowPreferences();
  bool failSave = false;
  @override
  Future<List<ForwardRule>> loadRules() async => rules;
  @override
  Future<Map<String, dynamic>> loadSettings() async => {
    'language': language,
    'theme_mode': appearance.mode.name,
    'accent_color': appearance.accent.name,
    'minimize_to_tray': windowPreferences.minimizeToTray,
    'close_action': windowPreferences.closeAction.name,
    'close_action_confirmed': windowPreferences.closeActionConfirmed,
  };
  @override
  Future<void> saveRules(List<ForwardRule> value) async {
    if (failSave) throw const FileSystemException('Read only');
    rules = value;
  }

  @override
  Future<void> saveAppearance(Appearance value) async {
    if (failSave) throw const FileSystemException('Read only');
    appearance = value;
  }

  @override
  Future<void> saveWindowPreferences(WindowPreferences value) async {
    if (failSave) throw const FileSystemException('Read only');
    windowPreferences = value;
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
    await tester.ensureVisible(find.text('完成'));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('toggle-$id')));
    await tester.pumpAndSettle();
    expect(controller.state(id), 'stopped');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'appearance changes live, follows system and preserves running rules',
    (tester) async {
      await controller.saveRule(
        const ForwardRule(
          id: 'theme-rule',
          name: 'Service',
          listenPort: 9000,
          targetHost: 'localhost',
          targetPort: 8080,
        ),
      );
      await controller.start(controller.rules.single);
      await open(tester);
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
      Color primary() =>
          Theme.of(tester.element(find.byType(Scaffold).first))
              .colorScheme
              .primary;
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      await tester.tap(find.byKey(const ValueKey('settingsButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('themeSelector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark').last);
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      expect(
        Theme.of(tester.element(find.byKey(const ValueKey('themeSelector'))))
            .brightness,
        Brightness.dark,
      );
      final oldPrimary = primary();
      await tester.ensureVisible(find.byKey(const ValueKey('accent-violet')));
      await tester.tap(find.byKey(const ValueKey('accent-violet')));
      await tester.pumpAndSettle();
      expect(primary(), isNot(oldPrimary));
      expect(store.appearance.mode, AppThemeMode.dark);
      expect(store.appearance.accent, AppAccent.violet);
      await controller.setAppearance(const Appearance());
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      expect(engine.starts, 1);
      expect(engine.stops, 0);
      expect(controller.state('theme-rule'), 'running');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed appearance save preserves active theme and reports error',
    (tester) async {
      store.failSave = true;
      await open(tester, const Size(800, 600));
      await tester.tap(find.byKey(const ValueKey('settingsButton')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('accent-blue')));
      await tester.tap(find.byKey(const ValueKey('accent-blue')));
      await tester.pumpAndSettle();
      expect(controller.appearance.accent, AppAccent.teal);
      expect(find.textContaining('Read only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('controller restores saved appearance on launch', () async {
    await store.saveAppearance(
      const Appearance(mode: AppThemeMode.dark, accent: AppAccent.violet),
    );
    final restored = BridgeController(
      store: store,
      engine: FakeEngine(),
      desktop: FakeDesktop(),
    );
    await restored.initialize();
    expect(restored.appearance.mode, AppThemeMode.dark);
    expect(restored.appearance.accent, AppAccent.violet);
    await restored.shutdown();
    restored.dispose();
  });

  testWidgets(
    'window behavior settings save, translate and preserve failed changes',
    (tester) async {
      await open(tester, const Size(800, 600));
      await tester.tap(find.byKey(const ValueKey('settingsButton')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('minimizeToTray')));
      await tester.tap(find.byKey(const ValueKey('minimizeToTray')));
      await tester.pumpAndSettle();
      expect(store.windowPreferences.minimizeToTray, isTrue);
      expect(store.windowPreferences.closeActionConfirmed, isFalse);
      await tester.ensureVisible(
        find.byKey(const ValueKey('closeActionSelector')),
      );
      await tester.tap(find.byKey(const ValueKey('closeActionSelector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Minimize').last);
      await tester.pumpAndSettle();
      expect(store.windowPreferences.closeAction, CloseAction.minimize);
      expect(store.windowPreferences.closeActionConfirmed, isTrue);
      store.failSave = true;
      await tester.tap(find.byKey(const ValueKey('closeActionSelector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exit application').last);
      await tester.pumpAndSettle();
      expect(controller.windowPreferences.closeAction, CloseAction.minimize);
      expect(find.textContaining('Read only'), findsOneWidget);
      await controller.setLanguage('zh_CN');
      await tester.pumpAndSettle();
      expect(find.text('最小化到托盘'), findsOneWidget);
      expect(find.text('最小化'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native close replay keeps engine alive until the window handler decides',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var shutdowns = 0;
      await tester.pumpWidget(
        BridgeApp(
          controller: controller,
          onShutdown: () async {
            shutdowns++;
          },
          onExitRequested: () async => AppExitResponse.exit,
        ),
      );
      await tester.pumpAndSettle();
      expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
      expect(controller.closing, isFalse);
      expect(shutdowns, 0);
    },
  );

  testWidgets(
    'settings provides explicit exit when close is configured to minimize',
    (tester) async {
      await controller.setWindowPreferences(
        const WindowPreferences(closeAction: CloseAction.minimize),
      );
      var exits = 0;
      controller.requestExit = () async {
        exits++;
      };
      await open(tester, const Size(800, 600));
      await tester.tap(find.byKey(const ValueKey('settingsButton')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('exitApplication')));
      await tester.tap(find.byKey(const ValueKey('exitApplication')));
      await tester.pumpAndSettle();
      expect(exits, 1);
      expect(tester.takeException(), isNull);
    },
  );

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

  for (final action in CloseAction.values) {
    testWidgets('first-close dialog remembers $action across restarts', (
      tester,
    ) async {
      await controller.setWindowPreferences(
        const WindowPreferences(minimizeToTray: true),
      );
      await open(tester, const Size(800, 600));
      final result = controller.confirmCloseAction!();
      await tester.pumpAndSettle();
      expect(find.text('What should the Close button do?'), findsOneWidget);
      await tester.tap(
        find.byKey(
          ValueKey(
            action == CloseAction.exit
                ? 'firstCloseExit'
                : 'firstCloseMinimize',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(await result, isTrue);
      expect(find.byKey(const ValueKey('firstCloseDialog')), findsNothing);
      expect(store.windowPreferences.closeAction, action);
      expect(store.windowPreferences.minimizeToTray, isTrue);
      final restored = BridgeController(
        store: store,
        engine: FakeEngine(),
        desktop: FakeDesktop(),
      );
      await tester.runAsync(() async {
        await restored.initialize();
        expect(restored.windowPreferences.closeActionConfirmed, isTrue);
        expect(restored.windowPreferences.closeAction, action);
        await restored.shutdown();
      });
      restored.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'first-close save failure keeps the Chinese dialog open and cancel changes nothing',
    (tester) async {
      await controller.setLanguage('zh_CN');
      store.failSave = true;
      await open(tester, const Size(800, 600));
      final result = controller.confirmCloseAction!();
      await tester.pumpAndSettle();
      expect(find.text('点击关闭按钮时要执行什么操作？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('firstCloseExit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Read only'), findsOneWidget);
      expect(controller.windowPreferences.closeActionConfirmed, isFalse);
      expect(find.byKey(const ValueKey('firstCloseDialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('firstCloseCancel')));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(controller.closing, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
