import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/strings.dart';

/// The window lifecycle uses this interface so decisions can be tested without
/// touching the user's real desktop or terminating the test process.
abstract class WindowActions {
  void Function()? onClose, onMinimize, onShow, onExit;
  Future<void> initialize();
  Future<bool> showTray(String language);
  Future<void> removeTray();
  Future<void> show();
  Future<void> hide();
  Future<void> minimize();
  Future<void> destroy();
  void detach();
}

class NativeWindowActions extends WindowActions
    with WindowListener, TrayListener {
  bool _trayCreated = false;

  @override
  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  @override
  Future<bool> showTray(String language) async {
    if (Platform.isLinux) {
      // AppIndicator can accept an icon even when no panel can display it.
      // Never hide the only usable window unless a tray host is present.
      try {
        final result = await Process.run('gdbus', [
          'call',
          '--session',
          '--dest',
          'org.freedesktop.DBus',
          '--object-path',
          '/org/freedesktop/DBus',
          '--method',
          'org.freedesktop.DBus.NameHasOwner',
          'org.kde.StatusNotifierWatcher',
        ]).timeout(const Duration(seconds: 2));
        if (result.exitCode != 0 ||
            !result.stdout.toString().contains('(true,)')) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    if (!_trayCreated) {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray.ico' : 'assets/tray.png',
      );
      _trayCreated = true;
    }
    final s = Strings(language);
    if (!Platform.isLinux) await trayManager.setToolTip(s('appName'));
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: s('showWindow'))..id = 41001,
          MenuItem.separator(),
          MenuItem(key: 'exit', label: s('exitApp'))..id = 41002,
        ],
      ),
    );
    return true;
  }

  @override
  Future<void> removeTray() async {
    if (_trayCreated) {
      await trayManager.destroy();
      _trayCreated = false;
    }
  }

  @override
  Future<void> show() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() => windowManager.hide();
  @override
  Future<void> minimize() => windowManager.minimize();
  @override
  Future<void> destroy() async {
    if (Platform.isWindows) {
      // WindowSession has already closed sockets, the tray and the file lock.
      // Posting WM_QUIT through window_manager can tear down Flutter while a
      // native callback is still on the stack. Finish the process after cleanup.
      exit(0);
    }
    await windowManager.destroy();
  }

  @override
  void detach() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
  }

  @override
  void onWindowClose() => onClose?.call();
  @override
  void onWindowMinimize() => onMinimize?.call();
  @override
  void onTrayIconMouseDown() => onShow?.call();
  @override
  void onTrayIconRightMouseDown() {
    // Linux opens the native indicator menu itself.
    if (!Platform.isLinux) trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') onShow?.call();
    if (menuItem.key == 'exit') onExit?.call();
  }
}
