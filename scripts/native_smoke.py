"""Extract a locally built native archive and launch its isolated GUI smoke test."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from platform_support import VERSION, runtime_info

info = runtime_info()
name = f"port-bridge-{VERSION}-{info['system']}-{info['architecture']}"
suffix = ".tar.gz" if info["system"] == "linux" else ".zip"
with tempfile.TemporaryDirectory(prefix="port-bridge-native-test-") as temp:
    if info["system"] == "macos":
        subprocess.run(["ditto", "-x", "-k", str(ROOT / "dist" / (name + suffix)), temp], check=True)
    else:
        shutil.unpack_archive(ROOT / "dist" / (name + suffix), temp)
    entry = {"windows": "PortBridge/PortBridge.exe", "linux": "PortBridge/PortBridge",
             "macos": "PortBridge.app/Contents/MacOS/PortBridge"}[info["system"]]
    subprocess.run([str(Path(temp) / name / entry), "--smoke-test"], check=True, timeout=30)
print(f"Native GUI launch passed: {name}")
