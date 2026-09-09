"""Build on the target OS with a Python interpreter of the target architecture."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from platform_support import APP_ID, VERSION, runtime_info


def validate_target(info, requested):
    if info["system"] not in ("windows", "macos", "linux"):
        raise ValueError(f"Unsupported OS: {info['system']}")
    if info["architecture"] not in ("x86_64", "arm64"):
        raise ValueError("Native bundles target x86_64 or arm64. Use the source distribution for 32-bit ARM.")
    if requested and requested != info["architecture"]:
        raise ValueError(f"Cannot build {requested} with a {info['architecture']} interpreter. "
                         "Run on the target architecture with matching Python; this is not a cross-compiler.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-arch", choices=("x86_64", "arm64"))
    args = parser.parse_args()
    info = runtime_info()
    try:
        validate_target(info, args.target_arch)
    except ValueError as exc:
        parser.error(str(exc))
    try:
        import tkinter
        import PyInstaller
    except ImportError as exc:
        parser.error(f"{exc}. Install Tkinter and requirements-build.txt first.")
    if info["system"] == "linux":
        missing = [tool for tool in ("ldd", "objdump", "objcopy") if not shutil.which(tool)]
        if missing:
            parser.error(f"Missing Linux build tools: {', '.join(missing)}. Install binutils and libc tools.")
    info.update(version=VERSION, tkinter=tkinter.TkVersion, pyinstaller=PyInstaller.__version__)
    dist = ROOT / "dist"
    work = ROOT / "build/native"
    dist.mkdir(exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    name = f"port-bridge-{VERSION}-{info['system']}-{info['architecture']}"
    # Isolated builds prevent stale artifacts from another architecture entering the archive.
    with tempfile.TemporaryDirectory(prefix=name + "-", dir=work) as temp:
        temp = Path(temp)
        command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir",
                   "--windowed", "--name", "PortBridge", "--distpath", str(temp / "dist"),
                   "--workpath", str(temp / "work"), "--specpath", str(temp),
                   "--paths", str(ROOT)]
        if info["system"] == "macos":
            command += ["--target-architecture", info["architecture"], "--osx-bundle-identifier", APP_ID]
        command.append(str(ROOT / "app.py"))
        subprocess.run(command, cwd=ROOT, check=True)
        stage = temp / name
        stage.mkdir()
        bundle_name = "PortBridge.app" if info["system"] == "macos" else "PortBridge"
        shutil.copytree(temp / "dist" / bundle_name, stage / bundle_name, symlinks=True)
        for filename in ("README.md", "README.zh-CN.md"):
            shutil.copyfile(ROOT / filename, stage / filename)
        (stage / "build-info.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
        if info["system"] == "macos":
            # ditto preserves app-bundle symlinks and executable permissions in a Finder-compatible zip.
            output = dist / f"{name}.zip"
            output.unlink(missing_ok=True)
            subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(stage), str(output)], check=True)
        else:
            kind = "zip" if info["system"] == "windows" else "gztar"
            output = shutil.make_archive(str(dist / name), kind, root_dir=temp, base_dir=name)
        print(f"Created {output}")


if __name__ == "__main__":
    main()
