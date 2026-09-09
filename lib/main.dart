import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'application/bridge_controller.dart';
import 'application/engine_client.dart';
import 'data/config_store.dart';
import 'l10n/strings.dart';
import 'platform/desktop_integration.dart';
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
    runApp(BridgeApp(controller: controller, onShutdown: lock.close));
    if (smoke) {
      Timer(const Duration(seconds: 2), () async {
        await controller.shutdown();
        await lock.close();
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
