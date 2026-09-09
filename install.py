#!/usr/bin/env python3
"""Install the source application and a native launcher for the current user."""
from pathlib import Path
import shutil

from desktop import autostart_path, install_launcher, set_autostart
from platform_support import APP_ID, data_home, runtime_info, system_name, tk_install_hint

SOURCE_FILES = ("app.py", "bridge.py", "desktop.py", "platform_support.py", "i18n.py", "settings.py",
                "install.py", "icon.svg", "README.md", "README.zh-CN.md")


def main():
    if system_name() not in ("windows", "macos", "linux"):
        raise SystemExit(f"Unsupported operating system: {system_name()}")
    try:
        import tkinter
    except ImportError:
        raise SystemExit(tk_install_hint()) from None
    destination = data_home() / "port-bridge"
    destination.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).resolve().parent
    for name in SOURCE_FILES:
        if (source / name).resolve() != (destination / name).resolve():
            shutil.copyfile(source / name, destination / name)
    entry = install_launcher(destination / "app.py")
    if system_name() == "linux":
        icons = data_home() / "icons/hicolor/scalable/apps"
        icons.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(destination / "icon.svg", icons / f"{APP_ID}.svg")
    if autostart_path().exists():
        set_autostart(True, destination / "app.py")
    info = runtime_info()
    print(f"Installed for {info['system']} / {info['architecture']}: {destination}\nLauncher: {entry}")


if __name__ == "__main__":
    main()
