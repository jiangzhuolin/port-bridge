import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:port_bridge/data/config_store.dart';
import 'package:port_bridge/domain/rule.dart';
import 'package:port_bridge/l10n/strings.dart';
import 'package:port_bridge/platform/desktop_integration.dart';

void main() {
  late Directory temp;
  late ConfigStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('port-bridge-test-');
    store = ConfigStore(temp);
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  test(
    'reads Python version 1 format and replaces files without losing settings',
    () async {
      await store.rulesFile.writeAsString(
        jsonEncode({
          'version': 1,
          'rules': [
            {
              'id': 'legacy',
              'name': 'Service',
              'listen_host': '0.0.0.0',
              'listen_port': 9000,
              'target_host': 'example.com',
              'target_port': 443,
              'auto_start': true,
            },
          ],
        }),
      );
      final rules = await store.loadRules();
      expect(rules.single.autoStart, isTrue);
      await store.saveRules(rules);
      expect((await store.loadRules()).single.toJson(), rules.single.toJson());
      await store.settingsFile.writeAsString(
        '{"language":"en","future_option":42}',
      );
      await store.saveLanguage('zh_CN');
      expect(await store.loadSettings(), {
        'language': 'zh_CN',
        'future_option': 42,
      });
      expect(temp.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    },
  );
  test('corrupt settings are preserved', () async {
    await store.settingsFile.writeAsString('{broken');
    await expectLater(store.saveLanguage('zh_CN'), throwsFormatException);
    expect(await store.settingsFile.readAsString(), '{broken');
  });
  test('rejects duplicate IDs and invalid schema', () async {
    const r = ForwardRule(
      id: 'same',
      name: 'Service',
      listenPort: 9000,
      targetHost: 'example.com',
      targetPort: 443,
    );
    await expectLater(store.saveRules([r, r]), throwsA(isA<BridgeException>()));
    await store.rulesFile.writeAsString('{"version":2,"rules":[]}');
    await expectLater(store.loadRules(), throwsA(isA<BridgeException>()));
  });
  test('locale catalogs have complete parity', () {
    expect(Strings.zh.keys.toSet(), Strings.en.keys.toSet());
  });
  test('platform directories preserve legacy configurations', () async {
    final legacy = Directory('${temp.path}/.config/port-bridge');
    await legacy.create(recursive: true);
    await File('${legacy.path}/rules.json').writeAsString('{}');
    final paths = PlatformPaths(
      system: 'windows',
      home: temp.path,
      environment: {},
    );
    expect(paths.configDirectory().path, legacy.path);
    final overridden = PlatformPaths(
      system: 'linux',
      home: temp.path,
      environment: {'XDG_CONFIG_HOME': '${temp.path}/custom'},
    );
    expect(
      overridden.configDirectory().path,
      '${temp.path}/custom/port-bridge',
    );
  });
  test('startup entries escape paths and toggle only their own file', () async {
    expect(
      NativeDesktopIntegration.launchAgent('/Apps/A&B <test>'),
      contains('A&amp;B &lt;test&gt;'),
    );
    expect(
      NativeDesktopIntegration.desktopEntry('/apps/50% service'),
      contains('50%% service'),
    );
    final paths = PlatformPaths(
      system: 'linux',
      home: temp.path,
      environment: {},
    );
    final desktop = NativeDesktopIntegration(
      paths: paths,
      executable: '/apps/Port Bridge/port_bridge',
    );
    await desktop.setAutostart(true);
    expect(await desktop.isAutostartEnabled(), isTrue);
    expect(
      await paths.startupFile.readAsString(),
      contains('Exec="/apps/Port Bridge/port_bridge"'),
    );
    await desktop.setAutostart(false);
    expect(await desktop.isAutostartEnabled(), isFalse);
  });
}
