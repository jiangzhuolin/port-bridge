"""Per-user desktop launchers, login startup, and single-instance locking."""
import errno
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile

from i18n import LocalizedError
from platform_support import (APP_ID, config_home, data_home, launch_command,
                              system_name, VERSION)


def desktop_quote(value):
    value = str(value).replace("%", "%%")
    for char in ("\\", '"', "`", "$"):
        value = value.replace(char, "\\" + char)
    value = value.replace("\\", "\\\\")
    if "\n" in value or "\r" in value:
        raise LocalizedError("Application paths cannot contain newlines")
    return '"' + value + '"'


def launcher(app_path=None, icon="network-wired"):
    command = " ".join(desktop_quote(arg) for arg in launch_command(app_path))
    return ("[Desktop Entry]\nType=Application\nName=Port Bridge\nName[zh_CN]=端口桥\n"
            "Comment=Manage multiple TCP port forwarding rules\n"
            f"Exec={command}\nIcon={icon}\nTerminal=false\nCategories=Network;\nStartupNotify=false\n")


def windows_programs():
    roaming = Path(os.environ.get("APPDATA", str(Path.home() / "AppData/Roaming")))
    return roaming / "Microsoft/Windows/Start Menu/Programs"


def autostart_path():
    if system_name() == "windows":
        return windows_programs() / "Startup/Port Bridge.lnk"
    if system_name() == "macos":
        return Path.home() / f"Library/LaunchAgents/{APP_ID}.plist"
    return config_home() / "autostart" / f"{APP_ID}.desktop"


def write_shortcut(path, command):
    """Use a temporary JSON payload so paths never become PowerShell source code."""
    import json
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"path": str(path), "target": command[0],
               "arguments": subprocess.list2cmdline(command[1:]),
               "working": str(Path(command[-1]).parent)}
    fd, name = tempfile.mkstemp(suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)
        env = dict(os.environ, PORT_BRIDGE_SHORTCUT_DATA=name)
        script = """$ErrorActionPreference = 'Stop'
$data = Get-Content -LiteralPath $env:PORT_BRIDGE_SHORTCUT_DATA -Raw -Encoding UTF8 | ConvertFrom-Json
$shellObject = New-Object -ComObject WScript.Shell
$shortcut = $shellObject.CreateShortcut($data.path)
$shortcut.TargetPath = $data.target
$shortcut.Arguments = $data.arguments
$shortcut.WorkingDirectory = $data.working
$shortcut.Description = 'Port Bridge TCP forwarding'
$shortcut.Save()
"""
        subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                       env=env, check=True, capture_output=True,
                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    finally:
        Path(name).unlink(missing_ok=True)


def set_autostart(enabled, app_path=None):
    path = autostart_path()
    if not enabled:
        path.unlink(missing_ok=True)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if system_name() == "windows":
        write_shortcut(path, launch_command(app_path))
    elif system_name() == "macos":
        # No bootstrap: RunAtLoad applies at the next login, without starting a duplicate now.
        data = {"Label": APP_ID, "ProgramArguments": launch_command(app_path),
                "RunAtLoad": True, "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive"}
        path.write_bytes(plistlib.dumps(data))
        path.chmod(0o600)
    elif system_name() == "linux":
        path.write_text(launcher(app_path), encoding="utf-8")
    else:
        raise LocalizedError("Unsupported operating system: {system}", system=system_name())


def install_launcher(app_path):
    """Install a source-based entry point. Native bundles can be opened directly."""
    if system_name() == "windows":
        path = windows_programs() / "Port Bridge.lnk"
        write_shortcut(path, launch_command(app_path))
    elif system_name() == "macos":
        path = Path.home() / "Applications/Port Bridge.app"
        contents = path / "Contents"
        executable = contents / "MacOS/port-bridge"
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_text("#!/bin/sh\nexec " + shlex.join(launch_command(app_path)) + '\n', encoding="utf-8")
        executable.chmod(0o755)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleName": "Port Bridge", "CFBundleDisplayName": "Port Bridge",
            "CFBundleIdentifier": APP_ID, "CFBundleExecutable": "port-bridge",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": VERSION,
            "NSHighResolutionCapable": True,
        }))
    elif system_name() == "linux":
        path = data_home() / "applications" / f"{APP_ID}.desktop"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(launcher(app_path, APP_ID), encoding="utf-8")
    else:
        raise LocalizedError("Unsupported operating system: {system}", system=system_name())
    return path


class InstanceLock:
    """Lock one byte on Windows, flock on Unix; never unlink an active lock file."""
    def __init__(self, path):
        self.path = Path(path)
        self.handle = None

    def acquire(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        handle = self.path.open("a+b")
        if self.path.stat().st_size == 0:
            handle.write(b"\0")
            handle.flush()
        handle.seek(0)
        try:
            if system_name() == "windows":
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            handle.close()
            if exc.errno in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
                return False
            raise
        self.handle = handle
        return True

    def close(self):
        if self.handle:
            if system_name() == "windows":
                import msvcrt
                self.handle.seek(0)
                msvcrt.locking(self.handle.fileno(), msvcrt.LK_UNLCK, 1)
            self.handle.close()
            self.handle = None
