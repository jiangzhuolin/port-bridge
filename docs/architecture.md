# Architecture

Port Bridge 2 uses Flutter for every application screen and Dart for all application logic. There is no Python service, embedded interpreter, HTTP control server, or subprocess RPC protocol.

## Why Dart

The application needs TCP sockets, JSON files, process integration and a desktop UI. Dart provides these primitives without additional runtime dependencies. Keeping Python would retain proven code but also require shipping two runtimes, supervising a backend process and maintaining an IPC protocol for six platform/architecture combinations. Rust would be appropriate if profiling revealed substantial CPU work or a native networking requirement. Neither is necessary for the current forwarding workload.

## Boundaries

- `lib/presentation`: Flutter Material UI, rule editor and settings.
- `lib/application`: observable application state and a typed command facade for the worker isolate.
- `lib/domain`: validated rules and TCP resource ownership; independent of Flutter widgets.
- `lib/data`: versioned JSON loading and flushed temporary-file replacement.
- `lib/platform`: platform paths, per-user login startup and process locking.
- `lib/l10n`: English and Simplified Chinese catalogs, including semantic log messages.

The UI isolate sends rule/start/stop commands to a dedicated network isolate. Only status, logs and statistics return. TCP payloads remain in the network isolate. Commands are serialized, preventing start/stop races. Worker failures disable forwarding controls and fail pending requests.

Each listener owns its clients and pending connection attempts. Each relay has two independently bounded 64 KiB buffers. Partial socket writes pause reads and resume on write readiness. An EOF shuts down only the opposite send direction, allowing delayed responses after a client half-close. Stop closes the listener, active sockets and pending connect tasks. DNS resolution has a timeout; stopped relays cannot attach a socket after resolution completes. Each rule accepts at most 512 concurrent clients.

Rules retain the Python release's version-1 JSON schema. Settings retain `en` and `zh_CN`; changing the UI language does not restart listeners. Invalid configuration is reported and protected from UI edits, and malformed settings are never silently replaced. A file lock prevents multiple Dart application processes from sharing a configuration directory. Close the Python version before upgrading: its POSIX locking mechanism differs from Dart's.

## Desktop packaging

Flutter's standard Windows, macOS and Linux runners host the UI. Builds run on matching OS/CPU hosts, and artifact names include `x86_64` or `arm64`. `tool/build.dart` refuses a mismatched requested architecture. macOS builds may contain universal binaries produced by Xcode; the artifact suffix identifies the build/test host, not a promise that the other slice was tested.

Login startup uses Windows Startup shortcuts, a macOS LaunchAgent, or Linux XDG autostart entries. Install/extract to a stable directory before enabling it. Moving the application requires toggling login startup off and on. Exit terminates forwarding; minimize keeps it running.

Windows distribution is an installation-free directory containing `port_bridge.exe`, Flutter DLLs, assets and app-local Visual C++ redistributables. `tool/windows_package.dart` locates and includes the matching VC runtime; `tool/build.dart` copies the complete bundle and documentation into `dist/` without an archive. Keep all files together when moving or upgrading the application. The standard Flutter executable is the entry point for both direct launch and login startup.

For a standalone MSVC/Windows SDK environment without a registered Visual Studio installation, `tool/build_windows.ps1 -StandaloneToolchain` builds through Ninja Multi-Config. Run it with Flutter, CMake, Ninja, cl.exe and rc.exe on PATH and matching INCLUDE/LIB variables. Normal builds and CI continue to use Flutter's Visual Studio integration. Set `PORT_BRIDGE_VC_REDIST` when automatic redistributable discovery is unavailable.

Tests cover real sockets, half-close, concurrent binary payloads, bounded buffering, listener recovery, worker commands, legacy configuration, localization and UI workflows. Native builds on another operating system still require that system's compiler and runtime validation.
