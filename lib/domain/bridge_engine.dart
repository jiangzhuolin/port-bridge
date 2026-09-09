import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'rule.dart';

typedef EngineEvent = Map<String, dynamic>;

/// Owns TCP resources on one isolate. Each direction buffers at most 64 KiB.
class BridgeEngine {
  BridgeEngine({
    required this.emit,
    this.connectTimeout = const Duration(seconds: 10),
    this.maxConnections = 512,
  });
  final void Function(EngineEvent) emit;
  final Duration connectTimeout;
  final int maxConnections;
  final Map<String, _Listener> _listeners = {};

  void _status(String id, String state) =>
      emit({'type': 'status', 'id': id, 'state': state});
  void _log(ForwardRule rule, String code, [String detail = '']) =>
      emit({'type': 'log', 'name': rule.name, 'code': code, 'detail': detail});

  Future<void> start(ForwardRule rule) async {
    rule.validate();
    if (_listeners.containsKey(rule.id)) return;
    try {
      final server = await RawServerSocket.bind(
        rule.listenHost,
        rule.listenPort,
        v6Only: rule.listenHost.contains(':'),
        shared: false,
      );
      final state = _Listener(rule, server);
      _listeners[rule.id] = state;
      state.subscription = server.listen(
        (client) {
          if (state.stopping || state.connections.length >= maxConnections) {
            client.close();
            return;
          }
          client.readEventsEnabled = false;
          client.writeEventsEnabled = false;
          final relay = _Relay(client, state, () {});
          relay.onDone = () => state.connections.remove(relay);
          state.connections.add(relay);
          state.total++;
          unawaited(_connect(state, relay));
        },
        onError: (Object error) {
          _log(rule, 'listenerFailed', error.toString());
          unawaited(stop(rule.id).then((_) => _status(rule.id, 'failed')));
        },
      );
      _status(rule.id, 'running');
      _log(
        rule,
        'listening',
        '${rule.listenEndpoint} → ${rule.targetEndpoint}',
      );
    } catch (error) {
      _status(rule.id, 'failed');
      _log(rule, 'listenFailed', error.toString());
      rethrow;
    }
  }

  Future<void> _connect(_Listener state, _Relay relay) async {
    try {
      final addresses = await InternetAddress.lookup(state.rule.targetHost)
          .timeout(connectTimeout);
      // Resolve once and connect only to the checked addresses to avoid DNS rebinding loops.
      if (state.rule.listenPort == state.rule.targetPort) {
        final local = InternetAddress(state.rule.listenHost);
        final wildcard = local.address == '0.0.0.0' || local.address == '::';
        final localAddresses = <String>{
          InternetAddress.loopbackIPv4.address,
          InternetAddress.loopbackIPv6.address,
        };
        if (wildcard) {
          for (final interface in await NetworkInterface.list(
            includeLoopback: true,
          )) {
            localAddresses.addAll(interface.addresses.map((a) => a.address));
          }
        } else {
          localAddresses.add(local.address);
        }
        if (addresses.any((a) => localAddresses.contains(a.address))) {
          throw const BridgeException('forwardingLoop');
        }
      }
      Object? lastError;
      final deadline = DateTime.now().add(connectTimeout);
      for (final address in addresses) {
        if (relay.closed || state.stopping) return;
        final remaining = deadline.difference(DateTime.now());
        if (remaining.isNegative) {
          throw TimeoutException('Target connection timed out');
        }
        try {
          final attempt = await RawSocket.startConnect(
            address,
            state.rule.targetPort,
          );
          relay.attempt = attempt;
          if (relay.closed || state.stopping) {
            attempt.cancel();
            try {
              await (await attempt.socket).close();
            } catch (_) {
              /* Cancelled connection. */
            }
            return;
          }
          final upstream = await attempt.socket.timeout(
            remaining,
            onTimeout: () {
              attempt.cancel();
              throw TimeoutException('Target connection timed out');
            },
          );
          relay.attempt = null;
          if (relay.closed || state.stopping) {
            await upstream.close();
            return;
          }
          relay.attach(upstream, (error) => _connectionError(state, error));
          return;
        } catch (error) {
          lastError = error;
          relay.attempt = null;
        }
      }
      throw lastError ?? const BridgeException('targetUnavailable');
    } catch (error) {
      if (!relay.closed && !state.stopping) _connectionError(state, error);
      relay.close();
    }
  }

  void _connectionError(_Listener state, Object error) {
    state.errors++;
    final now = DateTime.now();
    if (now.difference(state.lastError).inMilliseconds >= 1000) {
      state.lastError = now;
      _log(
        state.rule,
        error is BridgeException ? error.code : 'connectionFailed',
        error is BridgeException ? error.detail : error.toString(),
      );
    }
  }

  Future<void> stop(String id) async {
    final state = _listeners.remove(id);
    if (state != null) {
      state.stopping = true;
      for (final relay in state.connections.toList()) {
        relay.close();
      }
      await state.server.close();
      await state.subscription?.cancel();
      _log(state.rule, 'stoppedLog');
    }
    _status(id, 'stopped');
  }

  Future<void> stopAll() async {
    for (final id in _listeners.keys.toList()) {
      await stop(id);
    }
  }

  Map<String, dynamic> snapshot() => _listeners.map(
    (id, state) => MapEntry(id, {
      'connections': state.connections.length,
      'up': state.up,
      'down': state.down,
      'total': state.total,
      'errors': state.errors,
      'buffered': state.connections.fold<int>(
        0,
        (sum, relay) => sum + relay.buffered,
      ),
    }),
  );
}

class _Listener {
  _Listener(this.rule, this.server);
  final ForwardRule rule;
  final RawServerSocket server;
  StreamSubscription<RawSocket>? subscription;
  final Set<_Relay> connections = {};
  bool stopping = false;
  int up = 0, down = 0, total = 0, errors = 0;
  DateTime lastError = DateTime.fromMillisecondsSinceEpoch(0);
}

class _Relay {
  _Relay(this.client, this.state, this.onDone);
  final RawSocket client;
  final _Listener state;
  void Function() onDone;
  ConnectionTask<RawSocket>? attempt;
  RawSocket? target;
  StreamSubscription<RawSocketEvent>? clientEvents, targetEvents;
  _Direction? up, down;
  bool closed = false;
  int get buffered => (up?.buffered ?? 0) + (down?.buffered ?? 0);

  void attach(RawSocket socket, void Function(Object) onError) {
    target = socket;
    socket.readEventsEnabled = false;
    socket.writeEventsEnabled = false;
    up = _Direction(client, socket, (count) => state.up += count);
    down = _Direction(socket, client, (count) => state.down += count);
    void handle(RawSocketEvent event, _Direction read, _Direction write) {
      if (closed) return;
      try {
        if (event == RawSocketEvent.read) read.read();
        if (event == RawSocketEvent.write) write.drain();
        if (event == RawSocketEvent.readClosed) read.finish();
        if (event == RawSocketEvent.closed && !read.eof) read.finish();
        if (up!.finished && down!.finished) close();
      } catch (error) {
        onError(error);
        close();
      }
    }

    void fail(Object error) {
      if (!closed) {
        onError(error);
        close();
      }
    }

    clientEvents = client.listen(
      (event) => handle(event, up!, down!),
      onError: fail,
    );
    targetEvents = socket.listen(
      (event) => handle(event, down!, up!),
      onError: fail,
    );
    client.readEventsEnabled = true;
    socket.readEventsEnabled = true;
  }

  void close() {
    if (closed) return;
    closed = true;
    attempt?.cancel();
    client.close();
    target?.close();
    unawaited(clientEvents?.cancel());
    unawaited(targetEvents?.cancel());
    onDone();
  }
}

class _Direction {
  _Direction(this.source, this.destination, this.count);
  final RawSocket source, destination;
  final void Function(int) count;
  Uint8List? pending;
  int offset = 0;
  bool eof = false, finished = false;
  int get buffered => pending == null ? 0 : pending!.length - offset;

  void read() {
    if (pending != null || eof) return;
    pending = source.read(64 * 1024);
    offset = 0;
    drain();
  }

  void drain() {
    if (pending != null) {
      final written = destination.write(
        pending!,
        offset,
        pending!.length - offset,
      );
      count(written);
      offset += written;
      if (offset < pending!.length) {
        source.readEventsEnabled = false;
        destination.writeEventsEnabled = true;
        return;
      }
      pending = null;
    }
    destination.writeEventsEnabled = false;
    if (eof) {
      if (!finished) {
        finished = true;
        destination.shutdown(SocketDirection.send);
      }
    } else {
      source.readEventsEnabled = true;
    }
  }

  void finish() {
    eof = true;
    drain();
  }
}
