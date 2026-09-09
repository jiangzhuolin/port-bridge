import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:port_bridge/data/config_store.dart';
import 'package:port_bridge/domain/rule.dart';
import 'package:port_bridge/platform/desktop_integration.dart';

/// Exercise a compiled desktop app with isolated configuration and real TCP.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Pass the compiled executable path');
  }
  final executable = File(args.single).absolute.path;
  final temp = await Directory.systemTemp.createTemp(
    'port-bridge-desktop-test-',
  );
  final store = ConfigStore(Directory('${temp.path}/port-bridge'));
  final echo = await ServerSocket.bind('127.0.0.1', 0);
  final reservation = await ServerSocket.bind('127.0.0.1', 0);
  final port = reservation.port;
  await reservation.close();
  final peers = <Socket>[];
  final subscription = echo.listen((socket) {
    peers.add(socket);
    socket.listen(socket.add, onDone: socket.close);
  });
  Process? app;
  Socket? client;
  final lock = InstanceLock(File('${store.directory.path}/app.lock'));
  try {
    await store.saveRules([
      ForwardRule(
        id: 'smoke',
        name: 'Native TCP test',
        listenHost: '127.0.0.1',
        listenPort: port,
        targetHost: '127.0.0.1',
        targetPort: echo.port,
        autoStart: true,
      ),
    ]);
    await store.saveLanguage('zh_CN');
    app = await Process.start(
      executable,
      [],
      environment: {'XDG_CONFIG_HOME': temp.path},
    );
    unawaited(stdout.addStream(app.stdout));
    unawaited(stderr.addStream(app.stderr));
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (client == null) {
      try {
        client = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 200),
        );
      } on SocketException {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    if (await lock.acquire()) {
      throw StateError('Application did not hold the configuration lock');
    }
    final payload = Uint8List.fromList(
      List.generate(65536, (index) => index % 251),
    );
    final response = client.fold<List<int>>(
      [],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    client.add(payload);
    await client.close();
    final received = await response.timeout(const Duration(seconds: 10));
    if (received.length != payload.length ||
        List.generate(
          payload.length,
          (i) => received[i] == payload[i],
        ).contains(false)) {
      throw StateError('Native application altered the TCP payload');
    }
    if ((await store.loadSettings())['language'] != 'zh_CN') {
      throw StateError('Native application changed the saved language');
    }
  } finally {
    client?.destroy();
    app?.kill();
    await app?.exitCode.timeout(const Duration(seconds: 10));
    await lock.close();
    for (final peer in peers) {
      peer.destroy();
    }
    await subscription.cancel();
    await echo.close();
    await temp.delete(recursive: true);
  }
  // A clean, application-driven shutdown must also complete successfully.
  final smoke = await Process.start(executable, ['--smoke-test']);
  unawaited(stdout.addStream(smoke.stdout));
  unawaited(stderr.addStream(smoke.stderr));
  final code = await smoke.exitCode.timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      smoke.kill();
      throw TimeoutException('Application shutdown timed out');
    },
  );
  if (code != 0) throw StateError('Application smoke test exited with $code');
  stdout.writeln(
    'Native startup, TCP payload, half-close, config lock and shutdown passed.',
  );
}
