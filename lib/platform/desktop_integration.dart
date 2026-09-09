import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

const appVersion = '0.2.2';
const appId = 'io.portbridge';

class PlatformPaths {
  PlatformPaths({
    String? system,
    Map<String, String>? environment,
    String? home,
  }) : system = system ?? Platform.operatingSystem,
       environment = environment ?? Platform.environment,
       home =
           home ??
           Platform.environment['HOME'] ??
           Platform.environment['USERPROFILE'] ??
           Directory.current.path;
  final String system, home;
  final Map<String, String> environment;
  String get configHome =>
      environment['XDG_CONFIG_HOME'] ??
      switch (system) {
        'windows' => environment['APPDATA'] ?? '$home/AppData/Roaming',
        'macos' => '$home/Library/Application Support',
        _ => '$home/.config',
      };
  Directory configDirectory() {
    final native = Directory('$configHome/port-bridge');
    final legacy = Directory('$home/.config/port-bridge');
    bool hasConfig(Directory dir) => [
      'rules.json',
      'settings.json',
    ].any((name) => File('${dir.path}/$name').existsSync());
    if (!environment.containsKey('XDG_CONFIG_HOME') &&
        ['windows', 'macos'].contains(system) &&
        !hasConfig(native) &&
        hasConfig(legacy)) {
      return legacy;
    }
    return native;
  }

  File get startupFile => File(switch (system) {
    'windows' =>
      '${environment['APPDATA'] ?? '$home/AppData/Roaming'}/Microsoft/Windows/Start Menu/Programs/Startup/Port Bridge.lnk',
    'macos' => '$home/Library/LaunchAgents/$appId.plist',
    _ => '$configHome/autostart/$appId.desktop',
  });
}

abstract class DesktopIntegration {
  String get runtimeLabel;
  Future<bool> isAutostartEnabled();
  Future<void> setAutostart(bool enabled);
}

class NativeDesktopIntegration implements DesktopIntegration {
  NativeDesktopIntegration({PlatformPaths? paths, String? executable})
    : paths = paths ?? PlatformPaths(),
      executable = executable ?? Platform.resolvedExecutable;
  final PlatformPaths paths;
  final String executable;
  static String get architecture {
    final abi = Abi.current().toString();
    if (abi.endsWith('arm64')) return 'arm64';
    if (abi.endsWith('x64')) return 'x86_64';
    return abi.split('_').last;
  }

  @override
  String get runtimeLabel => '${Platform.operatingSystem} · $architecture';
  @override
  Future<bool> isAutostartEnabled() => paths.startupFile.exists();

  @override
  Future<void> setAutostart(bool enabled) async {
    final file = paths.startupFile;
    if (!enabled) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    switch (paths.system) {
      case 'windows':
        final payloadDir = await Directory.systemTemp.createTemp(
          'port-bridge-shortcut-',
        );
        try {
          final payload = File('${payloadDir.path}/shortcut.json');
          await payload.writeAsString(
            jsonEncode({'path': file.absolute.path, 'target': executable}),
          );
          const script = r'''
$ErrorActionPreference = 'Stop'
$data = Get-Content -LiteralPath $env:PORT_BRIDGE_SHORTCUT_DATA -Raw -Encoding UTF8 | ConvertFrom-Json
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($data.path)
$shortcut.TargetPath = $data.target
$shortcut.Description = 'Port Bridge TCP forwarding'
$shortcut.Save()
''';
          final result = await Process.run(
            'powershell.exe',
            [
              '-NoProfile',
              '-NonInteractive',
              '-WindowStyle',
              'Hidden',
              '-Command',
              script,
            ],
            environment: {'PORT_BRIDGE_SHORTCUT_DATA': payload.path},
          );
          if (result.exitCode != 0) {
            throw FileSystemException(
              'Cannot create startup shortcut',
              result.stderr.toString(),
            );
          }
        } finally {
          await payloadDir.delete(recursive: true);
        }
      case 'macos':
        await file.writeAsString(launchAgent(executable), flush: true);
      case 'linux':
        await file.writeAsString(desktopEntry(executable), flush: true);
      default:
        throw UnsupportedError('Unsupported platform: ${paths.system}');
    }
  }

  static String desktopEntry(String executable) {
    if (executable.contains('\n') || executable.contains('\r')) {
      throw ArgumentError('Newlines in executable path');
    }
    var escaped = executable.replaceAll('%', '%%');
    for (final char in ['\\', '"', '`', r'$']) {
      escaped = escaped.replaceAll(char, '\\$char');
    }
    escaped = escaped.replaceAll('\\', '\\\\');
    return '[Desktop Entry]\nType=Application\nName=Port Bridge\nName[zh_CN]=端口桥\n'
        'Exec="$escaped"\nTerminal=false\nCategories=Network;\nStartupNotify=false\n';
  }

  static String launchAgent(String executable) {
    final escaped = executable
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0"><dict><key>Label</key><string>$appId</string>'
        '<key>ProgramArguments</key><array><string>$escaped</string></array>'
        '<key>RunAtLoad</key><true/><key>LimitLoadToSessionType</key><string>Aqua</string>'
        '<key>ProcessType</key><string>Interactive</string></dict></plist>\n';
  }
}

class InstanceLock {
  InstanceLock(this.file);
  final File file;
  RandomAccessFile? _handle;
  Future<bool> acquire() async {
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    if (await handle.length() == 0) {
      await handle.writeByte(0);
      await handle.flush();
    }
    try {
      await handle.lock(FileLock.exclusive, 0, 1);
      _handle = handle;
      return true;
    } on FileSystemException {
      await handle.close();
      return false;
    }
  }

  Future<void> close() async {
    await _handle?.unlock(0, 1);
    await _handle?.close();
    _handle = null;
  }
}
