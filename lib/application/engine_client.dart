import 'dart:async';
import 'dart:isolate';

import '../domain/bridge_engine.dart';
import '../domain/rule.dart';

abstract class EngineClient {
  Stream<EngineEvent> get events;
  Future<void> start(ForwardRule rule);
  Future<void> stop(String id);
  Future<void> close();
}

/// Commands and small statistics cross isolates; TCP buffers never enter the UI isolate.
class IsolateEngineClient implements EngineClient {
  final _events = StreamController<EngineEvent>.broadcast();
  final _pending = <int, Completer<void>>{};
  final _ready = Completer<SendPort>();
  final _receive = ReceivePort();
  Isolate? _isolate;
  int _nextId = 0;
  bool _closed = false;
  bool _failed = false;

  static Future<IsolateEngineClient> create() async {
    final client = IsolateEngineClient();
    client._receive.listen(client._onMessage);
    client._isolate = await Isolate.spawn(
      _worker,
      client._receive.sendPort,
      onError: client._receive.sendPort,
      onExit: client._receive.sendPort,
      errorsAreFatal: true,
    );
    await client._ready.future;
    return client;
  }

  void _onMessage(dynamic message) {
    if (message is SendPort) {
      _ready.complete(message);
      return;
    }
    if (message is Map) {
      final event = Map<String, dynamic>.from(message);
      if (event['type'] == 'reply') {
        final request = _pending.remove(event['request']);
        if (event['error'] != null) {
          request?.completeError(
            BridgeException(
              event['code'] as String? ?? 'operationFailed',
              event['error'] as String,
            ),
          );
        } else {
          request?.complete();
        }
      } else if (!_closed) {
        _events.add(event);
      }
      return;
    }
    if (!_closed && !_failed) {
      _failed = true;
      const error = BridgeException('engineStopped');
      if (!_ready.isCompleted) _ready.completeError(error);
      for (final request in _pending.values) {
        request.completeError(error);
      }
      _pending.clear();
      _events.add({'type': 'fatal', 'code': 'engineStopped'});
    }
  }

  @override
  Stream<EngineEvent> get events => _events.stream;
  Future<void> _send(String action, [Object? data]) async {
    if (_closed || _failed) throw const BridgeException('engineStopped');
    final port = await _ready.future;
    final id = _nextId++;
    final request = Completer<void>();
    _pending[id] = request;
    port.send({'request': id, 'action': action, 'data': data});
    return request.future;
  }

  @override
  Future<void> start(ForwardRule rule) => _send('start', rule.toJson());
  @override
  Future<void> stop(String id) => _send('stop', id);
  @override
  Future<void> close() async {
    if (_closed) return;
    try {
      if (!_failed) await _send('close').timeout(const Duration(seconds: 5));
    } finally {
      _closed = true;
      _isolate?.kill(priority: Isolate.immediate);
      for (final request in _pending.values) {
        request.completeError(const BridgeException('engineStopped'));
      }
      _pending.clear();
      _receive.close();
      await _events.close();
    }
  }
}

void _worker(SendPort output) {
  final input = ReceivePort();
  final engine = BridgeEngine(emit: output.send);
  final timer = Timer.periodic(
    const Duration(milliseconds: 500),
    (_) => output.send({'type': 'stats', 'data': engine.snapshot()}),
  );
  output.send(input.sendPort);
  Future<void> queue = Future.value();
  input.listen((dynamic raw) {
    final command = Map<String, dynamic>.from(raw as Map);
    queue = queue.then((_) async {
      try {
        switch (command['action']) {
          case 'start':
            await engine.start(
              ForwardRule.fromJson(
                Map<String, dynamic>.from(command['data'] as Map),
              ),
            );
          case 'stop':
            await engine.stop(command['data'] as String);
          case 'close':
            await engine.stopAll();
            timer.cancel();
            input.close();
        }
        output.send({'type': 'reply', 'request': command['request']});
      } catch (error) {
        output.send({
          'type': 'reply',
          'request': command['request'],
          'code': error is BridgeException ? error.code : 'operationFailed',
          'error': error is BridgeException ? error.detail : error.toString(),
        });
      }
    });
  });
}
