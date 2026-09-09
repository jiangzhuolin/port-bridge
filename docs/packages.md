# Desktop packages

Version 0.2.2 uses native x86_64 and ARM64 builds. ARM64 is called `arm64` in
artifact filenames and DEB metadata, and `aarch64` in RPM metadata. The x86_64
DEB uses the standard `amd64` architecture name. These are not 32-bit ARM builds.

| Platform | x86_64 | ARM64 |
| --- | --- | --- |
| Linux | `.deb`, `.rpm`, `.tar.gz` | `.deb`, `.rpm`, `.tar.gz` |
| macOS | `.dmg`, `.tar.gz` | `.dmg`, `.tar.gz` |
| Windows | Portable directory | Portable directory |

Files follow `port-bridge-0.2.2-<platform>-<architecture>.<extension>`.
GitHub Actions uploads each platform/architecture separately as a build artifact.
Actions wraps downloads in ZIP files; the actual DEB, RPM, DMG and tar.gz files
are inside. Building packages does not automatically publish a GitHub Release.

## Linux

The native builds use Ubuntu 22.04. A graphical desktop with GTK 3, glibc and
compatible C++ runtime libraries is required. Package dependencies record the
system library versions actually required by the binaries; the package manager
will reject incompatible distributions. DEB targets Debian/Ubuntu-derived
distributions; RPM targets compatible Fedora/openSUSE-derived distributions.
Older distributions are not supported merely because they accept DEB or RPM.

Install with the package manager so runtime dependencies are resolved:

```sh
# Debian / Ubuntu (choose the file matching your CPU)
sudo apt install ./port-bridge-0.2.2-linux-x86_64.deb

# Fedora
sudo dnf install ./port-bridge-0.2.2-linux-x86_64.rpm

# openSUSE
sudo zypper install ./port-bridge-0.2.2-linux-x86_64.rpm
```

Launch from the application menu or run `port-bridge`. The complete application
is installed in `/opt/port-bridge`, with a command in `/usr/bin` and a desktop
entry and icon under `/usr/share`. Uninstall with `apt remove port-bridge`,
`dnf remove port-bridge` or `zypper remove port-bridge`. User configuration is
retained. Quit the running app before upgrading or uninstalling it.

For installation-free use, extract the entire `.tar.gz` and run `./port_bridge`
inside the extracted directory. No administrator access is needed, but system
runtime libraries must already be installed. Keep the adjacent `lib` and `data`
directories together. Tray support requires a StatusNotifier/AppIndicator host.

Build dependencies include Flutter, clang, CMake, Ninja, pkg-config, GTK 3 and
Ayatana AppIndicator development files, Python 3, `dpkg-dev`, `rpm` and
`desktop-file-utils`. On a matching Debian/Ubuntu host, run:

```sh
dart run tool/build.dart --target-arch x86_64
# On an ARM64 host:
dart run tool/build.dart --target-arch arm64
```

Packaging checks the architecture of all ELF binaries. DEB dependencies are
calculated with `dpkg-shlibdeps`; RPM keeps automatically generated system ABI
requirements while excluding private bundled libraries from exported capabilities.
Neither packaging path runs installation scripts or modifies user settings.

## macOS

Choose `x86_64` for Intel Macs and `arm64` for Apple Silicon. Open the `.dmg`
and drag **Port Bridge.app** to **Applications**, or extract the `.tar.gz` and
move the application to a stable location. Builds set the executable architecture
explicitly and verify it before packaging. A shared framework may include both
architecture slices, but the application executable matches the filename.

These packages are not Developer ID signed or notarized. macOS may block their
first launch; use Apple's **Privacy & Security → Open Anyway** only if you trust
the downloaded build. Do not disable Gatekeeper globally.

Build on the matching macOS architecture with Xcode, Flutter and CocoaPods, using
the same `dart run tool/build.dart --target-arch ...` command. Packaging generates
both tar.gz and DMG files and verifies the disk image with `hdiutil verify`.
