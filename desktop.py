"""Freedesktop launchers; no systemd service is installed."""
import os
from pathlib import Path
import sys

from i18n import LocalizedError


def config_home():
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))


def desktop_quote(value):
    # Exec quoting is processed first as a desktop string, then as command args.
    value = str(value).replace("%", "%%")
    for char in ("\\", '"', "`", "$"):
        value = value.replace(char, "\\" + char)
    value = value.replace("\\", "\\\\")
    if "\n" in value or "\r" in value:
        raise LocalizedError("Application paths cannot contain newlines")
    return '"' + value + '"'


def launcher(app_path, icon="network-wired"):
    return ("[Desktop Entry]\nType=Application\nName=Port Bridge\nName[zh_CN]=端口桥\n"
            "Comment=Manage multiple TCP port forwarding rules\n"
            f"Exec={desktop_quote(sys.executable)} {desktop_quote(app_path)}\n"
            f"Icon={icon}\nTerminal=false\nCategories=Network;\n"
            "StartupNotify=false\n")


def autostart_path():
    return config_home() / "autostart" / "io.portbridge.desktop"


def set_autostart(enabled, app_path):
    path = autostart_path()
    if enabled:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(launcher(app_path), encoding="utf-8")
    else:
        path.unlink(missing_ok=True)
