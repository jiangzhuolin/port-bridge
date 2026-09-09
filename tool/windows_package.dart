import 'dart:io';

Map<String, String> readCmakeCache(File file) => {
  for (final line in file.readAsLinesSync())
    if (RegExp(r'^[A-Za-z_][A-Za-z_0-9]*:[^=]+=').hasMatch(line))
      line.substring(0, line.indexOf(':')): line.substring(
        line.indexOf('=') + 1,
      ),
};

Future<void> includeWindowsRuntime(
  Directory bundle,
  Directory nativeBuild,
  String arch,
) async {
  final cpu = arch == 'x86_64' ? 'x64' : 'arm64';
  final cache = readCmakeCache(File('${nativeBuild.path}/CMakeCache.txt'));
  // The Flutter engine uses the VC runtime; ship its app-local redistributables.
  final roots = <Directory>[];
  final visualStudio = cache['CMAKE_GENERATOR_INSTANCE'];
  if (visualStudio != null && visualStudio.isNotEmpty) {
    roots.add(Directory('$visualStudio/VC/Redist/MSVC'));
  }
  final configured =
      Platform.environment['PORT_BRIDGE_VC_REDIST'] ??
      Platform.environment['VCToolsRedistDir'];
  if (configured != null) roots.add(Directory(configured));
  final compiler = cache['CMAKE_CXX_COMPILER'];
  if (compiler != null) {
    var parent = File(compiler).parent;
    for (var i = 0; i < 7; i++) {
      final redist = Directory('${parent.path}/Redist/MSVC');
      if (redist.existsSync()) roots.add(redist);
      parent = parent.parent;
    }
  }
  for (final name in [
    'msvcp140.dll',
    'vcruntime140.dll',
    if (cpu == 'x64') 'vcruntime140_1.dll',
  ]) {
    final destination = File('${bundle.path}/$name');
    if (destination.existsSync()) continue;
    File? source;
    for (final root in roots.where((directory) => directory.existsSync())) {
      for (final entry in root.listSync(recursive: true).whereType<File>()) {
        final path = entry.path.replaceAll('\\', '/').toLowerCase();
        if (path.endsWith('/$name') &&
            path.contains('/$cpu/') &&
            !path.contains('debug')) {
          source = entry;
        }
      }
    }
    if (source == null) {
      throw StateError(
        'Cannot locate $name for $cpu. Set PORT_BRIDGE_VC_REDIST to the Visual C++ redistributable directory.',
      );
    }
    await source.copy(destination.path);
  }
}
