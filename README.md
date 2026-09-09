# Port Bridge

English | [简体中文](README.zh-CN.md)

A lightweight desktop application for managing TCP port forwarding rules. Listen on a local address and port, forward connections to a target service, and monitor connections and traffic from one window.

Port Bridge uses Python's standard library, Tkinter, and asyncio. It runs on Windows, macOS, and Linux desktops without external forwarding utilities or per-rule system services. Running from source requires no pip packages; native bundles include Python and Tk.

## Features

- Add, edit, and delete multiple forwarding rules; start or stop them individually or together.
- View active and cumulative connections, sent / received traffic, errors, and activity logs.
- Save rules locally and optionally start them when the application opens.
- Native launchers, optional desktop login startup, and single-instance protection on Windows, macOS, and Linux.
- Switch between English and Simplified Chinese in **Settings → Language**. Changes apply immediately and persist across launches; active connections continue.
- Forward bidirectional TCP traffic, including TCP half-close, with IPv4 and IPv6 listening addresses.

## Installation

### Platform and architecture support

| Platform | x86_64 (Intel / AMD) | ARM64 (AArch64 / Apple Silicon) | Desktop integration |
| --- | --- | --- | --- |
| Windows 10/11 | Source and native `.exe` bundle | Source and native `.exe` bundle; use ARM64 Python with Tk | Start menu shortcut, Startup shortcut |
| macOS | Source and native `.app` bundle | Source and native `.app` bundle | `~/Applications` launcher, per-user LaunchAgent |
| Ubuntu / Debian / Linux Mint | Source, native bundle, `.deb` | Source, native bundle, `.deb` | Application menu and XDG autostart |
| Fedora, Arch / Manjaro, openSUSE | Source and native bundle with compatible system libraries | Source where the distribution supplies ARM64 Python/Tk; native bundle with compatible libraries | Application menu and XDG autostart |
| Raspberry Pi OS / other 32-bit ARM Linux | — | Use a 64-bit OS for ARM64; **ARMv7 / armhf uses source or the architecture-independent `.deb`** | Application menu and XDG autostart |

The primary native build targets are **x86_64** and **arm64**. ARMv7 is a distinct 32-bit architecture, not an alias for ARM64. Source code is architecture independent, but Python, Tcl/Tk, and native bundles must match the runtime architecture. Distribution availability varies; for example, official Arch Linux packages target x86_64, while ARM derivatives have their own repositories.

**Settings → Runtime platform** shows the OS (including the Linux distribution), Python version, and runtime architecture. You can also run `python app.py --platform-info`. An x86_64 Python running under emulation still reports an x86_64 runtime and produces an x86_64 bundle.

Source requirements: Python 3.10+ and Tkinter; use Python 3.11+ for native Windows ARM64 Tk support. A graphical desktop is required. Linux Tk uses an X11 display, including XWayland in Wayland sessions. macOS uses native Aqua Tk from a current python.org installer. The application does not require a particular Linux package manager at runtime.

The repository includes a six-target GitHub Actions matrix for Windows, macOS, and Ubuntu, each on x86_64 and ARM64. Local verification covers Windows x86_64 and Debian x86_64; macOS and ARM hardware validation must be completed by those CI runners. ARMv7 and other Linux distributions are source compatibility targets, not hardware-tested here.

### Run from source

Download or clone the repository, install a matching Python/Tk runtime, then open the project directory:

| System | Install Python / Tkinter |
| --- | --- |
| Windows | Use the x86_64 or ARM64 installer from [python.org](https://www.python.org/downloads/windows/) with Tcl/Tk enabled |
| macOS | Use the universal2 installer from [python.org](https://www.python.org/downloads/macos/); run its native interpreter for your CPU |
| Ubuntu / Debian / Linux Mint | `sudo apt install python3 python3-tk` |
| Fedora | `sudo dnf install python3 python3-tkinter` |
| Arch / Manjaro | `sudo pacman -S python tk` |
| openSUSE | `zypper search -s 'python3*-tk'`, then install the Tk package matching your interpreter, for example `python313-tk` for Python 3.13 |

```bash
python3 -m tkinter
python3 app.py
```

On Windows, use `python` in place of `python3`. The first command opens a small Tk test window; close it before starting Port Bridge. Tkinter is an OS/Python component, not a package installed with pip.

### Install for the current user

After installing Python/Tk, run `python3 install.py` (`python install.py` on Windows). No administrator privileges are needed. The installer creates a Windows Start menu shortcut, a macOS `~/Applications/Port Bridge.app` launcher, or a Linux application-menu entry. Source installations retain a dependency on the Python interpreter used during installation; rerun the installer if it moves.

### Native bundles

Build locally using the instructions below, or download an artifact from a successful GitHub Actions run. Choose the archive matching both the OS and architecture:

```text
port-bridge-1.0.0-windows-x86_64.zip
port-bridge-1.0.0-windows-arm64.zip
port-bridge-1.0.0-macos-x86_64.zip
port-bridge-1.0.0-macos-arm64.zip
port-bridge-1.0.0-linux-x86_64.tar.gz
port-bridge-1.0.0-linux-arm64.tar.gz
```

Extract the complete archive. On Windows open `PortBridge/PortBridge.exe`; on macOS open `PortBridge.app` (it can be moved into Applications); on Linux run `PortBridge/PortBridge`. Keep each bundle's supporting files together. Enable login startup only after placing the bundle in its permanent location; toggle the preference off and on after moving it.

Native Linux bundles depend on compatible system libraries, including glibc and a graphical desktop. CI builds on Ubuntu 22.04; this does not make the bundle universal across every Linux release or musl-based distribution. Use source installation or build on the target distribution when compatibility differs. macOS CI builds on macOS 15 and does not establish support for older releases; build from source on the required OS. CI artifacts do not include a publisher signature or Apple notarization.

### Debian package

If you have downloaded or built the Debian package:

```bash
sudo apt install ./port-bridge_1.0.0_all.deb
```

The package declares Python and Tkinter dependencies. Open **Port Bridge** from the application menu or run `port-bridge`. The `.deb` contains pure Python and declares `Architecture: all`: it uses the distribution's native Python/Tk on amd64, arm64, or armhf rather than embedding architecture-specific executables. Choose either the Debian package or the user installation to avoid duplicate launchers; both use the same configuration directory.

## Usage

```text
TCP client → Host running Port Bridge:listen_port → Target host:target_port
```

1. Click **Add rule** and enter a name, listening address and port, and target address and port.
2. Click **Save rule**, select the rule, and click **Start selected**.
3. Connect your client to the listening address and port. Watch the table and log for traffic and errors.
4. Stop a rule before editing it. Use **Start all** or **Stop all** to control all rules.

For example, to reach a service on another machine's port `8080` through local port `9000`:

| Field | Example |
| --- | --- |
| Rule name | Development service |
| Listen address | `127.0.0.1` |
| Listen port | `9000` |
| Target IP / hostname | `192.0.2.10` |
| Target port | `8080` |

`192.0.2.10` is a documentation example; replace it with a service address reachable from the machine running Port Bridge. Enter the target host without a URL scheme, port, or IPv6 brackets. Port Bridge connects to the target when a client connects, so **Running** means the listening socket is ready; it does not confirm target reachability.

Use `127.0.0.1` for clients on the same machine. To accept clients from other machines, virtual machines, or containers, choose an appropriate host interface address or `0.0.0.0` for all IPv4 interfaces, and configure firewall access for the intended clients. Clients must use a reachable address of the host running Port Bridge; `0.0.0.0` is a listening address. An IPv6 listener can use `::` or a specific IPv6 interface address.

Typical uses include forwarding to a development server, accessing a reachable TCP service through a different local port, or connecting a container or virtual machine to a service through its host. Routing, target access, and firewall permissions must allow the connection.

## Language and preferences

The application defaults to English. Open **Settings → Language**, choose **English** or **简体中文**, and click **Apply**. Labels, statuses, validation messages, and application log messages update immediately. Rule names and addresses remain as entered; operating-system error details use the language supplied by the system.

**Start this rule when the application opens** controls automatic activation on the next launch. **Start all** starts every rule regardless of that preference. **Open at desktop login** launches the application after the current user logs into a graphical desktop session, using the Windows Startup folder, a macOS LaunchAgent, or Linux XDG autostart. It does not start a system service before login.

## Behavior and limitations

- TCP only. Port Bridge does not forward UDP, translate application protocols, or implement an HTTP / SOCKS server. It can relay TCP connections to an existing proxy, but does not support SOCKS5 UDP forwarding.
- No built-in authentication or encryption. Access and transport security depend on the network configuration and target service.
- Minimizing keeps forwarding active. Exiting stops listeners and closes existing connections. There is no tray mode or background system service.
- An unavailable target fails the current connection; the listener stays active and new clients can connect when the target recovers.
- Each rule accepts up to 512 concurrent connections. Each direction uses 64 KiB chunks with backpressure. Target connections have a 10-second connection timeout; established idle connections have no activity timeout.
- Sent / received traffic is measured from the forwarder's perspective. Counters reset when a rule starts. The most recent 500 log entries are kept in memory and are not written to disk.
- Port Bridge does not change client proxy settings, container networking, firewalls, or Docker daemon proxy settings.

## Configuration

Rules and settings are stored per user:

| System | Configuration directory | Source installation directory | Login startup entry |
| --- | --- | --- | --- |
| Windows | `%APPDATA%/port-bridge` | `%LOCALAPPDATA%/port-bridge` | `%APPDATA%/Microsoft/Windows/Start Menu/Programs/Startup/Port Bridge.lnk` |
| macOS | `~/Library/Application Support/port-bridge` | `~/Library/Application Support/port-bridge` | `~/Library/LaunchAgents/io.portbridge.plist` |
| Linux | `~/.config/port-bridge` | `~/.local/share/port-bridge` | `~/.config/autostart/io.portbridge.desktop` |

`rules.json` contains rules and their startup preferences; `settings.json` contains the language (`en` or `zh_CN`). `app.lock` protects the active instance. Explicit `XDG_CONFIG_HOME` and `XDG_DATA_HOME` overrides remain supported; on Windows/macOS they do not relocate the OS-native startup folder. Existing Windows/macOS configurations under `~/.config/port-bridge` continue to be used if the native directory contains no rules or settings yet.

Existing version-1 rule files remain supported. Language preferences are stored separately. An unreadable rule file is preserved and changes are disabled until it is repaired. An unreadable settings file falls back to English and is preserved; repair it and restart before saving preferences. An unknown language code falls back to English.

## Troubleshooting

- **Failed to start:** check the log for an occupied port, a listening IP that does not belong to the host, or insufficient permission to bind the port.
- **Running but connections fail:** check target reachability, the target service's listening address, and firewall rules.
- **Remote clients time out:** verify they use a reachable host address and that the listener and firewall allow access from their network.
- **Application already running:** find the existing window in the taskbar or Dock. One instance per user configuration directory is allowed.

## Development

Run core tests:

```bash
python3 -m unittest discover -s tests -v
```

Build a native bundle **on the target OS with a matching-architecture Python interpreter**:

Linux builds require `binutils` and libc tools (`ldd`), plus venv support. On Ubuntu / Debian, install `python3-venv binutils` with apt before the commands below. A system Python also needs its shared library (for example, `libpython3.13` for Python 3.13). Other distributions provide equivalent build packages.

```bash
python3 -m venv .venv
# Linux/macOS: source .venv/bin/activate
# Windows PowerShell: .venv\Scripts\Activate.ps1
python -m pip install -r requirements-build.txt
python scripts/build_native.py --target-arch x86_64
# On ARM64 with ARM64 Python: use --target-arch arm64
python scripts/native_smoke.py
```

On headless Linux, run the last command under `xvfb-run -a`. `--target-arch` validates the interpreter architecture; it does not cross-compile. Bundles include `build-info.json` with OS, runtime architecture, Python, Tk, PyInstaller, and (on Linux) libc details. Workflow artifacts are produced only after tests pass; the workflow does not publish GitHub Releases.

Build the source archive and Debian package (the second command requires Linux and `dpkg-deb`):

```bash
python3 scripts/build_package.py
bash scripts/build_deb.sh
```

Outputs go to `dist/`; intermediate files go to `build/`. Both are excluded from Git. Packages include both README versions and the language resources.

For GUI integration tests and window captures on Ubuntu / Debian:

```bash
sudo apt install python3-tk xvfb xauth python3-pil fonts-noto-cjk
xvfb-run -a -s "-screen 0 1400x1000x24" python3 scripts/gui_smoke.py
```

Captures are saved to `build/gui-tests/`. With the Debian package installed, verify the system launcher with `xvfb-run -a python3 scripts/package_smoke.py`. The GUI test also runs on Windows and macOS using `python scripts/gui_smoke.py`, including native autostart checks in an isolated temporary location. Set `PORT_BRIDGE_SKIP_CAPTURES=1` to run without screenshots or Pillow (useful on macOS CI without screen-recording permission).

Translations are maintained in `i18n.py`. Runtime state codes are independent of the display language; new user-facing messages should use the translation helper and preserve placeholders in both languages.

Bug reports and pull requests are welcome. Include the operating system, Python version, reproduction steps, and relevant logs with sensitive data removed. Run relevant tests for code changes and check both languages for UI changes.

## Uninstall

First disable **Open at desktop login** and exit. For a Debian installation:

```bash
sudo apt remove port-bridge
```

For a user installation, remove `~/.local/share/port-bridge`, `~/.local/share/applications/io.portbridge.desktop`, and `~/.local/share/icons/hicolor/scalable/apps/io.portbridge.svg`, or their equivalents under `$XDG_DATA_HOME`. Configuration is retained and can be removed separately from the configuration directory.

On Windows, remove the source installation directory and the Start menu `Port Bridge.lnk`. On macOS, remove `~/Applications/Port Bridge.app` and the source installation directory. For native bundles, remove the extracted folder or `.app`. Rules and preferences remain in the configuration directory unless removed separately.

Platform references: [Python / Tkinter](https://docs.python.org/3/library/tkinter.html), [Windows ARM64 Tk support](https://github.com/python/cpython/issues/90725), [PyInstaller platform requirements](https://pyinstaller.org/en/stable/requirements.html), [GitHub runner architectures](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
