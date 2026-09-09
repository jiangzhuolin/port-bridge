#!/usr/bin/env python3
"""Package a native Flutter bundle as DEB and RPM on a Debian/Ubuntu host."""

import argparse
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import tempfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def elf_files(bundle, arch):
    binaries = []
    for path in bundle.rglob("*"):
        if not path.is_file():
            continue
        with path.open("rb") as stream:
            header = stream.read(20)
        if header[:4] != b"\x7fELF":
            continue
        machine = struct.unpack("<H", header[18:20])[0]
        if header[4:6] != b"\x02\x01" or machine != {"x86_64": 62, "arm64": 183}[arch]:
            raise ValueError(f"Wrong ELF architecture: {path}")
        binaries.append(path)
    if bundle / "port_bridge" not in binaries:
        raise ValueError("Missing native port_bridge executable")
    return binaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("version")
    parser.add_argument("arch", choices=["x86_64", "arm64"])
    args = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != {"x86_64": "x86_64", "arm64": "aarch64"}[args.arch]:
        parser.error("Build packages on the matching Linux architecture")
    if not re.fullmatch(r"0\.\d+\.\d+", args.version):
        parser.error("Expected a 0.x.x release version")
    bundle, output = args.bundle.resolve(), args.output.resolve()
    binaries = elf_files(bundle, args.arch)
    output.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="port-bridge-linux-package-") as temporary:
        work = Path(temporary)
        root = work / "root"
        install = root / "opt/port-bridge"
        shutil.copytree(bundle, install, symlinks=True)
        (install / "port-bridge.desktop").unlink(missing_ok=True)
        (root / "usr/bin").mkdir(parents=True)
        (root / "usr/bin/port-bridge").symlink_to("/opt/port-bridge/port_bridge")
        desktop = root / "usr/share/applications/port-bridge.desktop"
        desktop.parent.mkdir(parents=True)
        desktop.write_text("""[Desktop Entry]
Type=Application
Name=Port Bridge
Comment=Manage TCP port forwarding
Comment[zh_CN]=管理 TCP 端口转发
Exec=/opt/port-bridge/port_bridge
Icon=port-bridge
Terminal=false
Categories=Network;Utility;
StartupWMClass=io.portbridge
""", encoding="utf-8")
        icon = root / "usr/share/icons/hicolor/scalable/apps/port-bridge.svg"
        icon.parent.mkdir(parents=True)
        shutil.copy2(repo / "icon.svg", icon)
        license_path = root / "usr/share/licenses/port-bridge/LICENSE"
        license_path.parent.mkdir(parents=True)
        shutil.copy2(repo / "LICENSE", license_path)
        run("desktop-file-validate", str(desktop))

        # Resolve versioned system dependencies from every shipped ELF object.
        # Private Flutter/plugin libraries have no distro shlibs metadata.
        (work / "debian").mkdir()
        (work / "debian/control").write_text("Source: port-bridge\n\nPackage: port-bridge\nArchitecture: any\n")
        result = run("dpkg-shlibdeps", "--ignore-missing-info", "-O",
                     f"-l{bundle / 'lib'}", *(f"-e{p}" for p in binaries),
                     cwd=work, stdout=subprocess.PIPE)
        dependencies = next(line.split("=", 1)[1] for line in result.stdout.splitlines()
                            if line.startswith("shlibs:Depends="))
        deb_arch = {"x86_64": "amd64", "arm64": "arm64"}[args.arch]
        control = root / "DEBIAN/control"
        control.parent.mkdir()
        size = sum(p.stat().st_size for p in root.rglob("*") if p.is_file()) // 1024
        control.write_text(f"""Package: port-bridge
Version: {args.version}
Section: net
Priority: optional
Architecture: {deb_arch}
Maintainer: Port Bridge contributors <jiangzl975@gmail.com>
Homepage: https://github.com/jiangzhuolin/port-bridge
Installed-Size: {size}
Depends: {dependencies}, libglib2.0-bin, libegl1, libgles2
Description: Desktop TCP port forwarding manager
 Manage TCP forwarding rules with a multilingual Flutter desktop interface.
""")
        deb = output / f"port-bridge-{args.version}-linux-{args.arch}.deb"
        run("dpkg-deb", "--build", "--root-owner-group", str(root), str(deb))
        shutil.rmtree(control.parent)

        # Keep automatically detected system ABI requirements, but do not export
        # private bundled libraries as system-wide RPM capabilities.
        private = [re.escape(p.name) for p in binaries if p.parent == bundle / "lib"]
        private_pattern = "^(" + "|".join(private) + r")\(.*$"
        rpm_arch = {"x86_64": "x86_64", "arm64": "aarch64"}[args.arch]
        spec = work / "port-bridge.spec"
        spec.write_text(f"""%global debug_package %{{nil}}
%global __os_install_post %{{nil}}
%global __provides_exclude {private_pattern}
%global __requires_exclude {private_pattern}
Name: port-bridge
Version: {args.version}
Release: 1
Summary: Desktop TCP port forwarding manager
License: Apache-2.0
URL: https://github.com/jiangzhuolin/port-bridge
BuildArch: {rpm_arch}
Requires: /usr/bin/gdbus
Requires: libEGL.so.1()(64bit)
Requires: libGLESv2.so.2()(64bit)

%description
Manage TCP forwarding rules with a multilingual Flutter desktop interface.

%install
mkdir -p "%{{buildroot}}"
cp -a "{root}/." "%{{buildroot}}/"

%files
%defattr(-,root,root,-)
/opt/port-bridge
/usr/bin/port-bridge
/usr/share/applications/port-bridge.desktop
/usr/share/icons/hicolor/scalable/apps/port-bridge.svg
%license /usr/share/licenses/port-bridge/LICENSE
""")
        rpm_root = work / "rpmbuild"
        run("rpmbuild", "-bb", "--target", rpm_arch, "--define", f"_topdir {rpm_root}", str(spec))
        rpms = list((rpm_root / "RPMS").rglob("*.rpm"))
        if len(rpms) != 1:
            raise ValueError(f"Expected one RPM, got {rpms}")
        rpm = output / f"port-bridge-{args.version}-linux-{args.arch}.rpm"
        shutil.copy2(rpms[0], rpm)
        run("dpkg-deb", "--info", str(deb))
        run("rpm", "-qp", "--requires", str(rpm))
        print(f"Created {deb}\nCreated {rpm}")


if __name__ == "__main__":
    main()
