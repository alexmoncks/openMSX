#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
#
# make-bundle.sh <outdir> : assemble the Raspberry Pi bundle from the aarch64
# build of this tree (derived/aarch64-linux-opt, see README.md).
#
#   GEO3D_ROMS     directory with GEO3D_98.ROM, SPHERE7_98.ROM, game/GEO3D_SHOOTER_98.ROM
#   EXTRA_MACHINES directory with more machine XMLs (C-BIOS_V9968_JP.xml lives
#                  in ~/.openMSX/share/machines, not in this tree)
#   CHROOT         the Debian trixie cross chroot, used to name the runtime packages
#
#   OFFLINE=1      also fill <outdir>/geo3d-rpi/debs for a Pi without network
#
# Writes <outdir>/geo3d-rpi/{install.sh,packages.txt,openmsx-geo3d-rpi.tar.gz}:
# that folder goes on the boot partition of the SD card.
set -e
TOOLS=$(dirname "$(readlink -f "$0")")
REPO=$(readlink -f "$TOOLS/../..")
OUT=${1:?usage: make-bundle.sh <outdir>}
GEO3D_ROMS=${GEO3D_ROMS:-/mnt/c/Projects/mmsoft/openmsx-geo3d}
EXTRA_MACHINES=${EXTRA_MACHINES:-$HOME/.openMSX/share/machines}
CHROOT=${CHROOT:-/home/alex/work/trixie}
BIN=$REPO/derived/aarch64-linux-opt/bin/openmsx
[ -f "$BIN" ] || { echo "no $BIN: build for aarch64 first"; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=$W/openmsx-geo3d
mkdir -p "$D/bin" "$D/roms" "$D/tools"
# strip and inspect the binary with the cross tools, inside the chroot
T=$(mktemp -d -p "$CHROOT/tmp")
cp "$BIN" "$T/openmsx"
chroot "$CHROOT" aarch64-linux-gnu-strip "${T#"$CHROOT"}/openmsx"
cp "$T/openmsx" "$D/bin/openmsx"
NEEDED=$(chroot "$CHROOT" aarch64-linux-gnu-readelf -d "${T#"$CHROOT"}/openmsx" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
rm -rf "$T"
cp -r "$REPO/share" "$D/share"
rm -rf "$D/share/systemroms"
# what "make install" does: the C-BIOS machines and ROMs (free) go with the machines
cp "$REPO"/Contrib/cbios/*.xml "$REPO"/Contrib/cbios/*.rom "$D/share/machines/"
for m in C-BIOS_V9968_JP.xml; do
	[ -f "$EXTRA_MACHINES/$m" ] && cp "$EXTRA_MACHINES/$m" "$D/share/machines/"
done
for r in GEO3D_98.ROM SPHERE7_98.ROM game/GEO3D_SHOOTER_98.ROM; do
	[ -f "$GEO3D_ROMS/$r" ] && cp "$GEO3D_ROMS/$r" "$D/roms/"
done
cp "$TOOLS/../geo3d-perf/bench.tcl" "$D/tools/"
cp "$TOOLS/geo3d" "$D/geo3d"
chmod +x "$D/geo3d" "$D/bin/openmsx"
git -C "$REPO" log -1 --format='openMSX fork %h (%s), bundled %ad' --date=short > "$D/VERSION" 2>/dev/null || true

# Runtime packages: the owner of every library the binary needs, plus what SDL2
# loads by name for KMS/DRM (GBM, EGL, the Mesa drivers).
mkdir -p "$OUT/geo3d-rpi"
{
	for so in $NEEDED; do
		chroot "$CHROOT" dpkg -S "/usr/lib/aarch64-linux-gnu/$so" 2>/dev/null | cut -d: -f1
	done
	printf '%s\n' libgl1-mesa-dri libegl1 libgbm1 libgles2 libdrm2 libasound2-plugins alsa-utils
} | sort -u > "$OUT/geo3d-rpi/packages.txt"

tar -czf "$OUT/geo3d-rpi/openmsx-geo3d-rpi.tar.gz" -C "$W" openmsx-geo3d

# OFFLINE=1: also download every runtime package with its whole dependency
# closure (resolved against an empty system, about 100 MB), for a Pi without
# network. install.sh then installs the ones the Pi does not have.
if [ -n "$OFFLINE" ]; then
	cp "$OUT/geo3d-rpi/packages.txt" "$CHROOT/root/packages.txt"
	chroot "$CHROOT" /bin/bash -e <<'EOF'
rm -rf /root/debs /root/empty; mkdir -p /root/debs/partial /root/empty
: > /root/empty/status
apt-get update -q > /dev/null
apt-get install -y -q --download-only --no-install-recommends \
	-o APT::Architecture=arm64 -o APT::Architectures::=arm64 \
	-o Dir::State::status=/root/empty/status -o Dir::Cache::archives=/root/debs \
	$(cat /root/packages.txt) > /dev/null
EOF
	rm -rf "$OUT/geo3d-rpi/debs"; mkdir -p "$OUT/geo3d-rpi/debs"
	cp "$CHROOT"/root/debs/*.deb "$OUT/geo3d-rpi/debs/"
	echo "offline packages: $(ls "$OUT/geo3d-rpi/debs" | wc -l)"
fi
cp "$TOOLS/install.sh" "$OUT/geo3d-rpi/"
ls -la "$OUT/geo3d-rpi"
echo "packages: $(tr '\n' ' ' < "$OUT/geo3d-rpi/packages.txt")"
cat "$D/VERSION" 2>/dev/null
