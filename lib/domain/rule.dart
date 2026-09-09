import 'dart:io';
import 'dart:math';

class BridgeException implements Exception {
  const BridgeException(this.code, [this.detail = '']);
  final String code;
  final String detail;
  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';
}

class ForwardRule {
  const ForwardRule({
    required this.id,
    required this.name,
    this.listenHost = '0.0.0.0',
    this.listenPort = 10808,
    this.targetHost = '',
    this.targetPort = 10808,
    this.autoStart = false,
  });

  final String id, name, listenHost, targetHost;
  final int listenPort, targetPort;
  final bool autoStart;

  static String newId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String get listenEndpoint => endpoint(listenHost, listenPort);
  String get targetEndpoint => endpoint(targetHost, targetPort);
  static String endpoint(String host, int port) =>
      host.contains(':') ? '[$host]:$port' : '$host:$port';

  ForwardRule validate() {
    if (id.isEmpty) throw const BridgeException('invalidId');
    if (name.trim().isEmpty) throw const BridgeException('nameRequired');
    final local = InternetAddress.tryParse(listenHost);
    if (local == null) throw const BridgeException('invalidListen');
    if (targetHost.isEmpty ||
        RegExp(r'[\s/\[\]]').hasMatch(targetHost) ||
        (targetHost.contains(':') &&
            InternetAddress.tryParse(targetHost) == null)) {
      throw const BridgeException('invalidTarget');
    }
    if (listenPort < 1 ||
        listenPort > 65535 ||
        targetPort < 1 ||
        targetPort > 65535) {
      throw const BridgeException('invalidPort');
    }
    if (listenPort == targetPort) {
      final target = InternetAddress.tryParse(targetHost);
      final wildcard = local.address == '0.0.0.0' || local.address == '::';
      if (target?.address == local.address ||
          (wildcard && target?.isLoopback == true) ||
          (targetHost.toLowerCase() == 'localhost' &&
              (local.isLoopback || wildcard))) {
        throw const BridgeException('forwardingLoop');
      }
    }
    return this;
  }

  factory ForwardRule.fromJson(Map<String, dynamic> json) {
    try {
      return ForwardRule(
        id: json['id'] as String,
        name: json['name'] as String,
        listenHost: (json['listen_host'] ?? '0.0.0.0') as String,
        listenPort: (json['listen_port'] ?? 10808) as int,
        targetHost: (json['target_host'] ?? '') as String,
        targetPort: (json['target_port'] ?? 10808) as int,
        autoStart: (json['auto_start'] ?? false) as bool,
      ).validate();
    } on TypeError {
      throw const BridgeException('invalidConfig');
    }
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'listen_host': listenHost,
    'listen_port': listenPort,
    'target_host': targetHost,
    'target_port': targetPort,
    'auto_start': autoStart,
  };
}
