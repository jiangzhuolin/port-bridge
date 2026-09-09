import 'dart:async';

import '../domain/rule.dart';
import '../domain/window_preferences.dart';
import '../platform/window_actions.dart';
import 'bridge_controller.dart';

class WindowSession {
  WindowSession(this.controller, this.window, {required this.releaseLock});
  final BridgeController controller;
  final WindowActions window;
  final Future<void> Function() releaseLock;
  Future<void> _pending = Future.value();
  Future<void>? _shutdown;
  bool _hidden = false, _disposed = false;
  String? _trayPreferences;

  Future<void> initialize() async {
    controller.requestExit = exit;
    window.onClose = () => unawaited(closeWindow());
    window.onMinimize = () => unawaited(minimize(alreadyMinimized: true));
    window.onShow = () => unawaited(restore());
    window.onExit = () => unawaited(exit());
    await window.initialize();
    controller.addListener(_preferencesChanged);
    _preferencesChanged();
    await _pending;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    _pending = _pending.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (error) {
        controller.reportWindowError(error);
      }
    });
    return _pending;
  }

  void _preferencesChanged() {
    final key =
        '${controller.windowPreferences.minimizeToTray}/${controller.language}';
    if (_trayPreferences == key) return;
    _trayPreferences = key;
    unawaited(
      _enqueue(() async {
        if (controller.windowPreferences.minimizeToTray) {
          await _ensureTray();
        } else {
          if (_hidden) await _restore();
          await window.removeTray();
          controller.reportWindowError(null);
        }
      }),
    );
  }

  Future<bool> _ensureTray() async {
    try {
      if (await window.showTray(controller.language)) {
        controller.reportWindowError(null);
        return true;
      }
      controller.reportWindowError(const BridgeException('trayUnavailable'));
    } catch (error) {
      controller.reportWindowError(
        BridgeException('trayUnavailable', error.toString()),
      );
    }
    return false;
  }

  Future<void> minimize({bool alreadyMinimized = false}) =>
      _enqueue(() => _minimize(alreadyMinimized: alreadyMinimized));

  Future<void> _minimize({bool alreadyMinimized = false}) async {
    if (_hidden) return;
    if (controller.windowPreferences.minimizeToTray && await _ensureTray()) {
      await window.hide();
      _hidden = true;
    } else if (!alreadyMinimized) {
      await window.minimize();
    }
  }

  Future<void> restore() => _enqueue(_restore);
  Future<void> _restore() async {
    await window.show();
    _hidden = false;
  }

  Future<void> closeWindow() => _enqueue(() async {
    if (controller.windowPreferences.closeAction == CloseAction.minimize) {
      await _minimize();
    } else {
      await _exit();
    }
  });

  /// Explicit tray Quit and operating-system Quit always terminate forwarding.
  Future<void> exit() => _enqueue(_exit);
  Future<void> _exit() async {
    await shutdown();
    await window.destroy();
  }

  Future<void> shutdown() => _shutdown ??= _cleanup();
  Future<void> _cleanup() async {
    _disposed = true;
    controller.requestExit = null;
    controller.removeListener(_preferencesChanged);
    window.detach();
    try {
      await controller.shutdown();
    } finally {
      try {
        await window.removeTray();
      } finally {
        await releaseLock();
      }
    }
  }
}
