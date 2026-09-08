#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stage=$(mktemp -d /tmp/port-bridge-build.XXXXXX)
cp -R "$root/build/deb-stage/." "$stage/"
find "$stage" -type d -exec chmod 755 {} +
find "$stage" -type f -exec chmod 644 {} +
chmod 755 "$stage/usr/bin/port-bridge"
dpkg-deb --root-owner-group --build "$stage" "$root/dist/port-bridge_1.0.0_all.deb"
dpkg-deb --info "$root/dist/port-bridge_1.0.0_all.deb"
