import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'application/bridge_controller.dart';
import 'application/engine_client.dart';
import 'application/window_session.dart';
import 'data/config_store.dart';
import 'l10n/strings.dart';
import 'platform/desktop_integration.dart';
import 'platform/window_actions.dart';
import 'presentation/bridge_app.dart';
import 'presentation/theme.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final smoke = arguments.contains('--smoke-test');
  final temporary = smoke
      ? await Directory.systemTemp.createTemp('port-bridge-smoke-')
      : null;
  final directory = temporary ?? PlatformPaths().configDirectory();
  final store = ConfigStore(directory);
  var language = 'en';
  try {
    language = (await store.loadSettings())['language'] == 'zh_CN'
        ? 'zh_CN'
        : 'en';
  } catch (_) {}
  final strings = Strings(language);
  final lock = InstanceLock(File('${directory.path}/app.lock'));
  try {
    if (!await lock.acquire()) {
      _errorApp(strings('alreadyRunning'));
      return;
    }
    final engine = await IsolateEngineClient.create();
    final controller = BridgeController(
      store: store,
      engine: engine,
      desktop: NativeDesktopIntegration(),
    );
    await controller.initialize();
    final session = WindowSession(
      controller,
      NativeWindowActions(),
      releaseLock: lock.close,
    );
    try {
      await session.initialize();
    } catch (_) {
      await session.shutdown();
      rethrow;
    }
    runApp(
      BridgeApp(
        controller: controller,
        onShutdown: session.shutdown,
        // Windows Flutter consumes WM_CLOSE before native plugin delegates and
        // replays it after this response. Leave cleanup to WindowSession when
        // window_manager receives the replay, so minimize and quit both work.
        onExitRequested: Platform.isWindows
            ? () async => AppExitResponse.exit
            : null,
      ),
    );
    if (smoke) {
      Timer(const Duration(seconds: 2), () async {
        await session.shutdown();
        await temporary!.delete(recursive: true);
        exit(0);
      });
    }
  } catch (error) {
    await lock.close();
    _errorApp('${strings('startupFailed')}\n$error');
    if (smoke) exit(1);
  }
}

void _errorApp(String message) => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: bridgeTheme(),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: SelectableText(message),
        ),
      ),
    ),
  ),
);
