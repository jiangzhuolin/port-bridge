# Port Bridge

English | [简体中文](README.zh-CN.md)

A lightweight desktop application for managing TCP port forwarding rules. Listen on a local address and port, forward connections to a target service, and monitor connections and traffic from one window.

Port Bridge uses Python's standard library, Tkinter, and asyncio. It is designed for Linux desktops and requires no pip packages, external forwarding utilities, or per-rule system services.

## Features

- Add, edit, and delete multiple forwarding rules; start or stop them individually or together.
- View active and cumulative connections, sent / received traffic, errors, and activity logs.
- Save rules locally and optionally start them when the application opens.
- Optionally launch at Linux desktop login.
- Switch between English and Simplified Chinese in **Settings → Language**. Changes apply immediately and persist across launches; active connections continue.
- Forward bidirectional TCP traffic, including TCP half-close, with IPv4 and IPv6 listening addresses.

## Installation

Python 3.10+ and Tkinter are required. Linux packaging targets Ubuntu 22.04+ and Debian 12+ with a graphical desktop session. The application can also run on Windows with Tkinter installed; the installer, desktop autostart, and single-instance lock are Linux-specific.

### Run from source

Download or clone the repository and open its directory. On Ubuntu / Debian:

```bash
sudo apt install python3-tk
python3 app.py
```

On Windows, run `python app.py` using a Python installation with Tkinter support.

### Install for the current Linux user

After installing Tkinter, run this from the source directory:

```bash
python3 install.py
```

Then open **Port Bridge** from the application menu. The installer copies files into the current user's data directory and does not itself require root.

### Debian package

If you have downloaded or built the Debian package:

```bash
sudo apt install ./port-bridge_1.0.0_all.deb
```

The package declares Python and Tkinter dependencies. Open **Port Bridge** from the application menu or run `port-bridge`. Choose either the Debian package or the user installation to avoid duplicate launchers; both use the same configuration directory.

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

**Start this rule when the application opens** controls automatic activation on the next launch. **Start all** starts every rule regardless of that preference. **Open at Linux desktop login** launches the application after the current user logs into a graphical desktop session.

## Behavior and limitations

- TCP only. Port Bridge does not forward UDP, translate application protocols, or implement an HTTP / SOCKS server. It can relay TCP connections to an existing proxy, but does not support SOCKS5 UDP forwarding.
- No built-in authentication or encryption. Access and transport security depend on the network configuration and target service.
- Minimizing keeps forwarding active. Exiting stops listeners and closes existing connections. There is no tray mode or background system service.
- An unavailable target fails the current connection; the listener stays active and new clients can connect when the target recovers.
- Each rule accepts up to 512 concurrent connections. Each direction uses 64 KiB chunks with backpressure. Target connections have a 10-second connection timeout; established idle connections have no activity timeout.
- Sent / received traffic is measured from the forwarder's perspective. Counters reset when a rule starts. The most recent 500 log entries are kept in memory and are not written to disk.
- Port Bridge does not change client proxy settings, container networking, firewalls, or Docker daemon proxy settings.

## Configuration

The configuration base directory is `$XDG_CONFIG_HOME`, or `~/.config` when that variable is unset:

| File | Purpose |
| --- | --- |
| `port-bridge/rules.json` | Rules and per-rule startup preferences |
| `port-bridge/settings.json` | Application language (`en` or `zh_CN`) |
| `autostart/io.portbridge.desktop` | Optional Linux desktop login launcher |

Existing version-1 rule files remain supported. Language preferences are stored separately. An unreadable rule file is preserved and changes are disabled until it is repaired. An unreadable settings file falls back to English and is preserved; repair it and restart before saving preferences. An unknown language code falls back to English.

## Troubleshooting

- **Failed to start:** check the log for an occupied port, a listening IP that does not belong to the host, or insufficient permission to bind the port.
- **Running but connections fail:** check target reachability, the target service's listening address, and firewall rules.
- **Remote clients time out:** verify they use a reachable host address and that the listener and firewall allow access from their network.
- **Application already running on Linux:** find the existing window in the taskbar. One instance per user configuration directory is allowed.

## Development

Run core tests:

```bash
python3 -m unittest discover -s tests -v
```

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

Captures are saved to `build/gui-tests/`. With the Debian package installed, verify the system launcher with `xvfb-run -a python3 scripts/package_smoke.py`. The GUI test can also run on Windows with Pillow installed using `python scripts/gui_smoke.py`; Linux autostart checks are skipped there.

Translations are maintained in `i18n.py`. Runtime state codes are independent of the display language; new user-facing messages should use the translation helper and preserve placeholders in both languages.

Bug reports and pull requests are welcome. Include the operating system, Python version, reproduction steps, and relevant logs with sensitive data removed. Run relevant tests for code changes and check both languages for UI changes.

## Uninstall

First disable **Open at Linux desktop login** and exit. For a Debian installation:

```bash
sudo apt remove port-bridge
```

For a user installation, remove `~/.local/share/port-bridge`, `~/.local/share/applications/io.portbridge.desktop`, and `~/.local/share/icons/hicolor/scalable/apps/io.portbridge.svg`, or their equivalents under `$XDG_DATA_HOME`. Configuration is retained and can be removed separately from the configuration directory.
