#!/usr/bin/env python3
"""Install a desktop launcher for the current user, without root."""
import os
from pathlib import Path
import shutil
import sys

from desktop import config_home, launcher


def main():
    if not sys.platform.startswith("linux"):
        raise SystemExit("This installer requires Linux.")
    try:
        import tkinter
    except ImportError:
        raise SystemExit("Install the GUI dependency first: sudo apt install python3-tk") from None
    data = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share")))
    destination = data / "port-bridge"
    destination.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).resolve().parent
    for name in ("app.py", "bridge.py", "desktop.py", "i18n.py", "settings.py", "install.py", "icon.svg", "README.md", "README.zh-CN.md"):
        if (source / name).resolve() != (destination / name).resolve():
            shutil.copyfile(source / name, destination / name)
    applications = data / "applications"
    applications.mkdir(parents=True, exist_ok=True)
    (applications / "io.portbridge.desktop").write_text(
        launcher(destination / "app.py", "io.portbridge"), encoding="utf-8")
    icons = data / "icons" / "hicolor" / "scalable" / "apps"
    icons.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(destination / "icon.svg", icons / "io.portbridge.svg")
    # Preserve an existing login preference when installing/moving the app.
    auto = config_home() / "autostart" / "io.portbridge.desktop"
    if auto.exists():
        auto.write_text(launcher(destination / "app.py", "io.portbridge"), encoding="utf-8")
    print(f"Installed to {destination}\nFind Port Bridge in your application menu.")


if __name__ == "__main__":
    main()
