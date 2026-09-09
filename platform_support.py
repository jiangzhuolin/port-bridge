"""OS integration paths and the architecture of the running Python process."""
import os
from pathlib import Path
import platform
import struct
import sys
import sysconfig

VERSION = "1.0.0"
APP_ID = "io.portbridge"


def system_name():
    if sys.platform == "win32":
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    if sys.platform.startswith("linux"):
        return "linux"
    return sys.platform


def normalize_arch(machine):
    value = machine.lower().replace("-", "_")
    if value in ("amd64", "x64", "x86_64"):
        return "x86_64"
    if value in ("arm64", "aarch64"):
        return "arm64"
    if value in ("arm", "armhf", "armv7", "armv7l", "armv8l"):
        return "armv7l"
    if value in ("i386", "i486", "i586", "i686", "x86", "win32"):
        return "x86"
    return value


def runtime_arch():
    # On Windows, machine() can describe the host rather than an emulated interpreter.
    if system_name() == "windows":
        target = sysconfig.get_platform().lower()
        if target.startswith("win"):
            return normalize_arch(target.removeprefix("win-"))
    arch = normalize_arch(platform.machine())
    if struct.calcsize("P") == 4:
        return {"x86_64": "x86", "arm64": "armv7l"}.get(arch, arch)
    return arch


def runtime_info():
    info = {"system": system_name(), "architecture": runtime_arch(),
            "python": platform.python_version(), "bits": struct.calcsize("P") * 8,
            "os_release": platform.release()}
    if info["system"] == "linux":
        try:
            info["distribution"] = platform.freedesktop_os_release().get("PRETTY_NAME", "Linux")
        except OSError:
            info["distribution"] = "Linux"
        info["libc"] = " ".join(platform.libc_ver())
    return info


def config_home():
    # Retain the previous explicit XDG override on every platform.
    if os.environ.get("XDG_CONFIG_HOME"):
        return Path(os.environ["XDG_CONFIG_HOME"])
    if system_name() == "windows":
        return Path(os.environ.get("APPDATA", str(Path.home() / "AppData/Roaming")))
    if system_name() == "macos":
        return Path.home() / "Library/Application Support"
    return Path.home() / ".config"


def config_directory():
    native = config_home() / "port-bridge"
    legacy = Path.home() / ".config/port-bridge"
    # Keep existing Windows/macOS installations on their old directory without copying data.
    names = ("rules.json", "settings.json")
    if (not os.environ.get("XDG_CONFIG_HOME") and system_name() in ("windows", "macos")
            and not any((native / name).exists() for name in names)
            and any((legacy / name).exists() for name in names)):
        return legacy
    return native


def data_home():
    if os.environ.get("XDG_DATA_HOME"):
        return Path(os.environ["XDG_DATA_HOME"])
    if system_name() == "windows":
        return Path(os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData/Local")))
    if system_name() == "macos":
        return Path.home() / "Library/Application Support"
    return Path.home() / ".local/share"


def gui_python():
    executable = Path(sys.executable)
    if system_name() == "windows" and not getattr(sys, "frozen", False):
        windowed = executable.with_name("pythonw.exe")
        if windowed.exists():
            return str(windowed)
    return str(executable)


def launch_command(app_path=None):
    if getattr(sys, "frozen", False):
        return [sys.executable]
    return [gui_python(), str(Path(app_path or Path(__file__).with_name("app.py")).resolve())]


def tk_install_hint():
    return ("Install Python with Tcl/Tk support, then check with: python -m tkinter\n"
            "Windows/macOS: use a matching-architecture Python installer from python.org.\n"
            "Ubuntu/Debian: sudo apt install python3-tk\n"
            "Fedora: sudo dnf install python3-tkinter\n"
            "Arch/Manjaro: sudo pacman -S python tk\n"
            "openSUSE: install the python3*-tk package matching your Python version.")
