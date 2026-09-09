import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import desktop
import platform_support as platforms
from scripts.build_native import validate_target

ROOT = Path(__file__).resolve().parents[1]


class PlatformTests(unittest.TestCase):
    def test_architecture_aliases_and_build_guard(self):
        for alias, expected in (("AMD64", "x86_64"), ("x64", "x86_64"), ("aarch64", "arm64"),
                                ("ARM64", "arm64"), ("armv7l", "armv7l"), ("armhf", "armv7l"),
                                ("i686", "x86")):
            self.assertEqual(platforms.normalize_arch(alias), expected)
        with patch("platform_support.system_name", return_value="windows"), \
                patch("platform_support.sysconfig.get_platform", return_value="win-amd64"), \
                patch("platform_support.platform.machine", return_value="ARM64"):
            self.assertEqual(platforms.runtime_arch(), "x86_64")
        with patch("platform_support.system_name", return_value="linux"), \
                patch("platform_support.platform.machine", return_value="aarch64"), \
                patch("platform_support.struct.calcsize", return_value=4):
            self.assertEqual(platforms.runtime_arch(), "armv7l")
        for system in ("windows", "macos", "linux"):
            for arch in ("x86_64", "arm64"):
                validate_target({"system": system, "architecture": arch}, arch)
                with self.assertRaisesRegex(ValueError, "Cannot build"):
                    validate_target({"system": system, "architecture": arch}, "arm64" if arch == "x86_64" else "x86_64")
        with self.assertRaises(ValueError):
            validate_target({"system": "linux", "architecture": "armv7l"}, None)

    def test_native_config_paths_override_and_legacy_preservation(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {}, clear=True):
            home = Path(temp)
            with patch("platform_support.Path.home", return_value=home):
                for system, expected in (("windows", home / "AppData/Roaming"),
                                         ("macos", home / "Library/Application Support"),
                                         ("linux", home / ".config")):
                    with patch("platform_support.system_name", return_value=system):
                        self.assertEqual(platforms.config_home(), expected)
                legacy = home / ".config/port-bridge"
                legacy.mkdir(parents=True)
                (legacy / "rules.json").write_text("{}")
                with patch("platform_support.system_name", return_value="macos"):
                    self.assertEqual(platforms.config_directory(), legacy)
                    native = platforms.config_home() / "port-bridge"
                    native.mkdir(parents=True)
                    self.assertEqual(platforms.config_directory(), legacy)
                    (native / "settings.json").write_text('{}')
                    self.assertEqual(platforms.config_directory(), native)
                    with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(home / "override")}):
                        self.assertEqual(platforms.config_directory(), home / "override/port-bridge")

    def test_frozen_launch_does_not_treat_executable_as_python(self):
        with patch.object(sys, "frozen", True, create=True), patch.object(sys, "executable", "bundle/PortBridge"):
            self.assertEqual(platforms.launch_command("ignored.py"), ["bundle/PortBridge"])

    def test_source_launcher_uses_pythonw_on_windows(self):
        with tempfile.TemporaryDirectory() as temp:
            executable = Path(temp) / "python.exe"
            windowed = Path(temp) / "pythonw.exe"
            windowed.touch()
            with patch("platform_support.system_name", return_value="windows"), \
                    patch.object(sys, "executable", str(executable)):
                self.assertEqual(platforms.gui_python(), str(windowed))


class DesktopTests(unittest.TestCase):
    def test_macos_login_plist_preserves_argument_boundaries(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "login.plist"
            command = ["/a path/python3", "/tmp/中文 ' $test/app.py"]
            with patch("desktop.system_name", return_value="macos"), \
                    patch("desktop.autostart_path", return_value=path), \
                    patch("desktop.launch_command", return_value=command):
                desktop.set_autostart(True)
                data = plistlib.loads(path.read_bytes())
                self.assertEqual(data["ProgramArguments"], command)
                self.assertTrue(data["RunAtLoad"])
                self.assertNotIn("KeepAlive", data)
                desktop.set_autostart(False)
                self.assertFalse(path.exists())

    def test_macos_app_bundle_and_linux_desktop_entry(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            command = ["/opt/python path/bin/python3", "/tmp/app ' $name.py"]
            with patch("desktop.Path.home", return_value=home), \
                    patch("desktop.launch_command", return_value=command), \
                    patch("desktop.system_name", return_value="macos"):
                bundle = desktop.install_launcher(command[1])
                info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
                self.assertEqual(info["CFBundleExecutable"], "port-bridge")
                import shlex
                shell = (bundle / "Contents/MacOS/port-bridge").read_text()
                self.assertEqual(shlex.split(shell.splitlines()[1])[1:], command)
            with patch("desktop.launch_command", return_value=command):
                entry = desktop.launcher()
                self.assertIn("Terminal=false", entry)
                self.assertIn("Name[zh_CN]=端口桥", entry)
                self.assertNotIn("Exec=python ", entry)

    def test_lock_excludes_another_process_and_releases(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "app.lock"
            lock = desktop.InstanceLock(path)
            self.assertTrue(lock.acquire())
            command = [sys.executable, "-c", "from desktop import InstanceLock; import sys; "
                       "lock = InstanceLock(sys.argv[1]); print(lock.acquire()); lock.close()", str(path)]
            try:
                child = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True)
                self.assertEqual(child.stdout.strip(), "False")
            finally:
                lock.close()
            child = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True)
            self.assertEqual(child.stdout.strip(), "True")

    @unittest.skipUnless(sys.platform == "win32", "Requires Windows COM")
    def test_windows_shortcut_round_trip(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "Port Bridge.lnk"
            command = [sys.executable, str(Path(temp) / "中文 ' $test" / "app.py")]
            desktop.write_shortcut(path, command)
            self.assertTrue(path.exists())
            # Avoid dependence on the PowerShell console's output encoding.
            script = "$s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:PB_TEST_SHORTCUT); " \
                     "[IO.File]::WriteAllText($env:PB_TEST_RESULT, $s.Arguments, [Text.Encoding]::UTF8)"
            output = Path(temp) / "arguments.txt"
            subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                           env=dict(os.environ, PB_TEST_SHORTCUT=str(path), PB_TEST_RESULT=str(output)),
                           creationflags=subprocess.CREATE_NO_WINDOW, check=True)
            self.assertEqual(output.read_text(encoding="utf-8-sig"), subprocess.list2cmdline(command[1:]))


if __name__ == "__main__":
    unittest.main()
