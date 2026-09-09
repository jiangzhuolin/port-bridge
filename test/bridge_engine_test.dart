import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:port_bridge/domain/bridge_engine.dart';
import 'package:port_bridge/domain/rule.dart';
import 'package:port_bridge/application/engine_client.dart';

Future<int> freePort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}

ForwardRule rule(int port, int target, {String id = 'test'}) => ForwardRule(
  id: id,
  name: 'Test',
  listenHost: '127.0.0.1',
  listenPort: port,
  targetHost: '127.0.0.1',
  targetPort: target,
);
Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late BridgeEngine engine;
  late ServerSocket target;
  final sockets = <Socket>[];
  setUp(() async {
    engine = BridgeEngine(emit: (_) {});
    target = await ServerSocket.bind('127.0.0.1', 0);
  });
  tearDown(() async {
    await engine.stopAll();
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await target.close();
  });

  test(
    'concurrent binary transfers preserve all bytes and statistics',
    () async {
      target.listen((socket) {
        sockets.add(socket);
        socket.listen(socket.add, onDone: socket.close);
      });
      final port = await freePort();
      await engine.start(rule(port, target.port));
      final payload = Uint8List.fromList(
        List.generate(1024 * 1024, (i) => i % 251),
      );
      await Future.wait(
        List.generate(4, (_) async {
          final client = await Socket.connect('127.0.0.1', port);
          sockets.add(client);
          final received = BytesBuilder();
          final done = Completer<void>();
          client.listen((data) {
            received.add(data);
            if (received.length == payload.length && !done.isCompleted) {
              done.complete();
            }
          }, onError: done.completeError);
          client.add(payload);
          await client.flush();
          await done.future.timeout(const Duration(seconds: 10));
          expect(received.takeBytes(), payload);
          client.destroy();
        }),
      );
      expect(engine.snapshot()['test']['up'], payload.length * 4);
      expect(engine.snapshot()['test']['down'], payload.length * 4);
      await eventually(() => engine.snapshot()['test']['connections'] == 0);
    },
  );

  test(
    'client half-close still receives a delayed complete response',
    () async {
      target.listen((socket) {
        sockets.add(socket);
        final received = BytesBuilder();
        socket.listen(
          received.add,
          onDone: () async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            socket.add(received.takeBytes().reversed.toList());
            await socket.close();
          },
        );
      });
      final port = await freePort();
      await engine.start(rule(port, target.port));
      final client = await Socket.connect('127.0.0.1', port);
      sockets.add(client);
      final response = client.fold<List<int>>(
        [],
        (all, data) => all..addAll(data),
      );
      client.add([0, 1, 128, 255]);
      await client.close();
      expect(await response.timeout(const Duration(seconds: 5)), [
        255,
        128,
        1,
        0,
      ]);
      await eventually(() => engine.snapshot()['test']['connections'] == 0);
    },
  );

  test(
    'slow receiver applies bounded buffering and stop releases the port',
    () async {
      final accepted = Completer<Socket>();
      target.listen((socket) {
        sockets.add(socket);
        accepted.complete(socket);
      });
      final port = await freePort();
      await engine.start(rule(port, target.port));
      final client = await Socket.connect('127.0.0.1', port);
      sockets.add(client);
      final upstream = await accepted.future;
      client.add(Uint8List(16 * 1024 * 1024));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        engine.snapshot()['test']['buffered'],
        lessThanOrEqualTo(128 * 1024),
      );
      final received = upstream.fold<int>(0, (sum, data) => sum + data.length);
      await client.close();
      expect(
        await received.timeout(const Duration(seconds: 15)),
        16 * 1024 * 1024,
      );
      await upstream.close();
      await engine.stop('test');
      final reused = await ServerSocket.bind('127.0.0.1', port);
      await reused.close();
    },
  );

  test('bind failure is recoverable and stop closes active clients', () async {
    final port = await freePort();
    final occupied = await ServerSocket.bind('127.0.0.1', port);
    await expectLater(
      engine.start(rule(port, target.port)),
      throwsA(isA<SocketException>()),
    );
    await occupied.close();
    target.listen((socket) {
      sockets.add(socket);
      socket.listen((_) {});
    });
    await engine.start(rule(port, target.port));
    final client = await Socket.connect('127.0.0.1', port);
    sockets.add(client);
    final done = client.drain<void>();
    await eventually(() => engine.snapshot()['test']['connections'] == 1);
    await engine.stop('test');
    await done.timeout(const Duration(seconds: 5));
    expect(engine.snapshot(), isEmpty);
  });

  test(
    'connection limit rejects excess clients without disrupting the first',
    () async {
      engine = BridgeEngine(emit: (_) {}, maxConnections: 1);
      target.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {});
      });
      final port = await freePort();
      await engine.start(rule(port, target.port));
      final first = await Socket.connect('127.0.0.1', port);
      sockets.add(first);
      await eventually(() => engine.snapshot()['test']['connections'] == 1);
      final second = await Socket.connect('127.0.0.1', port);
      sockets.add(second);
      await second.drain<void>().timeout(const Duration(seconds: 5));
      expect(engine.snapshot()['test']['connections'], 1);
      expect(engine.snapshot()['test']['total'], 1);
    },
  );

  test('IPv6 listener forwards to an IPv4 target', () async {
    final reservation = await ServerSocket.bind('::1', 0, v6Only: true);
    final port = reservation.port;
    await reservation.close();
    target.listen((socket) {
      sockets.add(socket);
      socket.listen(socket.add, onDone: socket.close);
    });
    await engine.start(
      ForwardRule(
        id: 'ipv6',
        name: 'IPv6',
        listenHost: '::1',
        listenPort: port,
        targetHost: '127.0.0.1',
        targetPort: target.port,
      ),
    );
    final client = await Socket.connect('::1', port);
    sockets.add(client);
    final response = client.fold<List<int>>(
      [],
      (all, data) => all..addAll(data),
    );
    client.add([1, 128, 255]);
    await client.close();
    expect(await response.timeout(const Duration(seconds: 5)), [1, 128, 255]);
  });

  test('rejects direct self-forwarding', () async {
    final port = await freePort();
    await expectLater(
      engine.start(rule(port, port)),
      throwsA(isA<BridgeException>()),
    );
  });

  test('isolate command failures do not kill subsequent commands', () async {
    final worker = await IsolateEngineClient.create();
    final subscription = worker.events.listen((_) {});
    try {
      await expectLater(
        worker.start(rule(target.port, target.port)),
        throwsA(
          isA<BridgeException>()
              .having((error) => error.code, 'code', 'forwardingLoop')
              .having((error) => error.detail, 'detail', isEmpty),
        ),
      );
      await expectLater(
        worker.start(rule(target.port, target.port + 1)),
        throwsA(isA<BridgeException>()),
      );
      await worker.start(rule(await freePort(), target.port));
      await worker.stop('test');
    } finally {
      await worker.close();
      await subscription.cancel();
    }
    await expectLater(worker.stop('test'), throwsA(isA<BridgeException>()));
  });
}
