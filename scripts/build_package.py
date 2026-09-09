"""Create a reproducible-layout Debian package tree and source zip."""
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT
STAGE = ROOT / "build" / "deb-stage"
DIST = ROOT / "dist"
DIST.mkdir(parents=True, exist_ok=True)


def write(relative, content):
    path = STAGE / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


for name in ("app.py", "bridge.py", "desktop.py", "i18n.py", "settings.py", "README.md", "README.zh-CN.md"):
    target = STAGE / "usr" / "share" / "port-bridge" / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE / name, target)
icon = STAGE / "usr/share/icons/hicolor/scalable/apps/io.portbridge.svg"
icon.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(SOURCE / "icon.svg", icon)
write("usr/bin/port-bridge", '#!/bin/sh\nexec /usr/bin/python3 /usr/share/port-bridge/app.py "$@"\n')
write("usr/share/applications/io.portbridge.desktop", """[Desktop Entry]
Type=Application
Name=Port Bridge
Name[zh_CN]=端口桥
Comment=Manage multiple TCP port forwarding rules
Exec=port-bridge
Icon=io.portbridge
Terminal=false
Categories=Network;
StartupNotify=false
""")
write("DEBIAN/control", """Package: port-bridge
Version: 1.0.0
Section: net
Priority: optional
Architecture: all
Maintainer: Port Bridge Authors <port-bridge@example.invalid>
Depends: python3 (>= 3.10), python3-tk
Recommends: fonts-noto-cjk
Description: Desktop GUI for multiple TCP port forwarding rules
 English and Chinese desktop application with per-rule start/stop,
 connection statistics, persistent configuration and desktop autostart.
""")
with zipfile.ZipFile(DIST / "port-bridge-1.0.0-source.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    paths = [SOURCE / name for name in (
        "app.py", "bridge.py", "desktop.py", "i18n.py", "settings.py", "install.py", "icon.svg", "README.md", "README.zh-CN.md", ".gitignore")]
    paths.extend((SOURCE / "tests").glob("*.py"))
    paths.extend((SOURCE / "scripts").glob("*.py"))
    paths.extend((SOURCE / "scripts").glob("*.sh"))
    for path in sorted(paths):
        archive.write(path, Path("port-bridge") / path.relative_to(SOURCE))
print("Package tree and source archive created")
