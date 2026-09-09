import 'dart:convert';
import 'dart:io';

import 'package:port_bridge/platform/desktop_integration.dart';

import 'windows_package.dart';

Future<void> copyDocs(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entry in source.list()) {
    final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (entry is File) {
      await entry.copy('${destination.path}/$name');
    } else if (entry is Directory) {
      await copyDocs(entry, Directory('${destination.path}/$name'));
    }
  }
}

Future<void> command(String executable, List<String> args) async {
  final process = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows && executable.endsWith('.bat'),
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, args, 'Command failed', code);
  }
}

/// Build on the target OS and CPU. Never label an emulated x64 build as ARM64.
Future<void> main(List<String> args) async {
  final os = Platform.operatingSystem;
  final arch = NativeDesktopIntegration.architecture;
  if (!['windows', 'macos', 'linux'].contains(os) ||
      !['x86_64', 'arm64'].contains(arch)) {
    throw UnsupportedError('Unsupported build host: $os/$arch');
  }
  final options = [...args];
  final skipBuild = options.remove('--skip-build');
  if (options.isNotEmpty &&
      (options.length != 2 ||
          options.first != '--target-arch' ||
          options.last != arch)) {
    throw ArgumentError(
      'Use --target-arch $arch on this host; cross-compilation is not configured.',
    );
  }
  final flutter = Platform.environment['FLUTTER_ROOT'];
  final executable = flutter == null
      ? (Platform.isWindows ? 'flutter.bat' : 'flutter')
      : '$flutter/bin/flutter${Platform.isWindows ? '.bat' : ''}';
  if (!skipBuild) await command(executable, ['build', os, '--release']);
  final cpu = arch == 'x86_64' ? 'x64' : 'arm64';
  final source = Directory(switch (os) {
    'windows' => 'build/windows/$cpu/runner/Release',
    'macos' => 'build/macos/Build/Products/Release',
    _ => 'build/linux/$cpu/release/bundle',
  });
  if (!await source.exists()) {
    throw FileSystemException('Missing build output', source.path);
  }
  if (os == 'windows') {
    await includeWindowsRuntime(source, Directory('build/windows/$cpu'), arch);
  }
  final name = 'port-bridge-$appVersion-$os-$arch';
  final dist = await Directory('dist').create(recursive: true);
  final stage = await Directory.systemTemp.createTemp('port-bridge-package-');
  try {
    final bundle = await Directory('${stage.path}/$name').create();
    if (os == 'macos') {
      final apps = source
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.endsWith('.app'))
          .toList();
      if (apps.length != 1) throw StateError('Expected exactly one macOS app');
      await command('ditto', [
        apps.single.path,
        '${bundle.path}/Port Bridge.app',
      ]);
    } else if (os == 'windows') {
      await copyDocs(source, bundle);
    } else {
      await command('cp', ['-a', '${source.path}/.', bundle.path]);
      await File('${bundle.path}/port-bridge.desktop').writeAsString(
        NativeDesktopIntegration.desktopEntry(
          '${bundle.path}/port_bridge',
        ).replaceFirst('Exec="${bundle.path}/port_bridge"', 'Exec=port_bridge'),
      );
    }
    for (final doc in ['README.md', 'README.zh-CN.md']) {
      await File(doc).copy('${bundle.path}/$doc');
    }
    await copyDocs(Directory('docs'), Directory('${bundle.path}/docs'));
    await File('${bundle.path}/build-info.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': appVersion,
        'platform': os,
        'architecture': arch,
        'dart': Platform.version.split(' ').first,
        'built_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (os == 'windows') {
      final destination = Directory('${dist.absolute.path}/$name');
      await copyDocs(bundle, destination);
      stdout.writeln('Created ${destination.path}/port_bridge.exe');
      return;
    }
    final archive = File('${dist.absolute.path}/$name.tar.gz');
    await command('tar', ['-czf', archive.path, '-C', stage.path, name]);
    stdout.writeln('Created ${archive.path}');
  } finally {
    await stage.delete(recursive: true);
  }
}
