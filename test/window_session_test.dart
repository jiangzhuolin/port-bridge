import 'package:flutter_test/flutter_test.dart';
import 'package:port_bridge/application/bridge_controller.dart';
import 'package:port_bridge/application/window_session.dart';
import 'package:port_bridge/domain/window_preferences.dart';
import 'package:port_bridge/platform/window_actions.dart';

import 'widget_test.dart' show MemoryStore, FakeEngine, FakeDesktop;

class FakeWindow extends WindowActions {
  final calls = <String>[];
  bool trayAvailable = true, trayThrows = false;
  @override
  Future<void> initialize() async => calls.add('initialize');
  @override
  Future<bool> showTray(String language) async {
    calls.add('tray:$language');
    if (trayThrows) throw StateError('Tray initialization failed');
    return trayAvailable;
  }

  @override
  Future<void> removeTray() async => calls.add('removeTray');
  @override
  Future<void> show() async => calls.add('show');
  @override
  Future<void> hide() async => calls.add('hide');
  @override
  Future<void> minimize() async => calls.add('minimize');
  @override
  Future<void> destroy() async => calls.add('destroy');
  @override
  void detach() => calls.add('detach');
}

void main() {
  late BridgeController controller;
  late FakeWindow window;
  late WindowSession session;
  late int releases;
  setUp(() async {
    controller = BridgeController(
      store: MemoryStore(),
      engine: FakeEngine(),
      desktop: FakeDesktop(),
    );
    await controller.initialize();
    window = FakeWindow();
    releases = 0;
    session = WindowSession(
      controller,
      window,
      releaseLock: () async {
        releases++;
      },
    );
    await session.initialize();
    window.calls.clear();
  });
  tearDown(() async {
    await session.shutdown();
    controller.dispose();
  });

  for (final tray in [false, true]) {
    for (final action in CloseAction.values) {
      test('close $action with tray=$tray', () async {
        await controller.setWindowPreferences(
          WindowPreferences(minimizeToTray: tray, closeAction: action),
        );
        await session.closeWindow();
        if (action == CloseAction.exit) {
          expect(controller.closing, isTrue);
          expect(window.calls.last, 'destroy');
          expect(releases, 1);
        } else {
          expect(controller.closing, isFalse);
          expect(window.calls.last, tray ? 'hide' : 'minimize');
          expect(releases, 0);
        }
      });
    }
  }

  test(
    'native minimize, tray restore and explicit quit are serialized',
    () async {
      await controller.setWindowPreferences(
        const WindowPreferences(
          minimizeToTray: true,
          closeAction: CloseAction.minimize,
        ),
      );
      await session.minimize(alreadyMinimized: true);
      expect(window.calls.last, 'hide');
      expect(window.calls, isNot(contains('minimize')));
      expect(controller.closing, isFalse);
      await session.restore();
      expect(window.calls.last, 'show');
      await Future.wait([
        session.exit(),
        session.closeWindow(),
        session.exit(),
      ]);
      expect(releases, 1);
      expect(window.calls.where((call) => call == 'destroy'), hasLength(1));
      expect(
        window.calls.indexOf('removeTray'),
        lessThan(window.calls.indexOf('destroy')),
      );
    },
  );

  test(
    'unavailable or failed tray never hides the only accessible window',
    () async {
      window.trayAvailable = false;
      await controller.setWindowPreferences(
        const WindowPreferences(
          minimizeToTray: true,
          closeAction: CloseAction.minimize,
        ),
      );
      await session.closeWindow();
      expect(window.calls, isNot(contains('hide')));
      expect(window.calls.last, 'minimize');
      expect(controller.windowError, isNotNull);
      window.trayThrows = true;
      window.calls.clear();
      await session.minimize(alreadyMinimized: true);
      expect(window.calls, isNot(contains('hide')));
      expect(window.calls, isNot(contains('minimize')));
      expect(controller.closing, isFalse);
    },
  );

  test(
    'language updates tray menu and disabling tray restores hidden window',
    () async {
      await controller.setWindowPreferences(
        const WindowPreferences(minimizeToTray: true),
      );
      await session.minimize();
      await controller.setLanguage('zh_CN');
      await session.minimize();
      expect(window.calls, contains('tray:zh_CN'));
      window.calls.clear();
      await controller.setWindowPreferences(const WindowPreferences());
      await session.minimize(alreadyMinimized: true);
      expect(window.calls, ['show', 'removeTray']);
    },
  );
  test(
    'explicit settings exit works without a tray even when Close minimizes',
    () async {
      await controller.setWindowPreferences(
        const WindowPreferences(closeAction: CloseAction.minimize),
      );
      await session.closeWindow();
      expect(controller.closing, isFalse);
      await controller.requestExit!();
      expect(controller.closing, isTrue);
      expect(window.calls.last, 'destroy');
      expect(releases, 1);
    },
  );
}
