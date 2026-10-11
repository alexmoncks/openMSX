#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
#
# cross-build.sh : build this tree for 64 bit ARM Linux (Raspberry Pi OS, which
# is Debian 13 "trixie"), on an x86 Linux or WSL host. Run as root.
#
# It keeps a Debian trixie amd64 chroot (CHROOT, about 2 GB) with Debian's
# arm64 cross compiler and the arm64 development libraries, so the binary
# links against exactly the libraries apt installs on the Pi. The host only
# needs debootstrap and debian-archive-keyring. The result is
# derived/aarch64-linux-opt/bin/openmsx; make-bundle.sh packs it.
#
#   JOBS=4 tools/geo3d-rpi/cross-build.sh
set -e
TOOLS=$(dirname "$(readlink -f "$0")")
REPO=$(readlink -f "$TOOLS/../..")
CHROOT=${CHROOT:-/home/alex/work/trixie}
JOBS=${JOBS:-4}

if [ ! -f "$CHROOT/etc/debian_version" ]; then
	command -v debootstrap > /dev/null || apt-get install -y --no-install-recommends debootstrap debian-archive-keyring
	debootstrap --variant=minbase --arch=amd64 trixie "$CHROOT" http://deb.debian.org/debian
fi
mkdir -p "$CHROOT/src" "$CHROOT/crossbin"
mountpoint -q "$CHROOT/proc" || mount -t proc proc "$CHROOT/proc"
mountpoint -q "$CHROOT/src" || mount --bind "$REPO" "$CHROOT/src"
# Never delete the chroot while the tree is mounted in it.
trap 'umount "$CHROOT/src" "$CHROOT/proc" 2>/dev/null || true' EXIT

if [ ! -x "$CHROOT/usr/bin/aarch64-linux-gnu-g++" ]; then
	chroot "$CHROOT" /bin/bash -e <<'EOF'
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture arm64
apt-get update -q
apt-get install -y -q --no-install-recommends \
	crossbuild-essential-arm64 make python3 pkgconf ca-certificates file qemu-user \
	libsdl2-dev:arm64 libsdl2-ttf-dev:arm64 libglew-dev:arm64 libgl-dev:arm64 tcl-dev:arm64 \
	libpng-dev:arm64 zlib1g-dev:arm64 libfreetype-dev:arm64 libogg-dev:arm64 libvorbis-dev:arm64 \
	libtheora-dev:arm64 libasound2-dev:arm64
EOF
fi

# The build calls plain "pkg-config": answer for arm64 (pkgconf picks the
# target from the name it is called by, so a symlink would not do).
printf '#!/bin/sh\nexec /usr/bin/aarch64-linux-gnu-pkg-config "$@"\n' > "$CHROOT/crossbin/pkg-config"
chmod +x "$CHROOT/crossbin/pkg-config"

# TCL_CONFIG: Debian keeps the arm64 tclConfig.sh in the multiarch directory.
chroot "$CHROOT" /usr/bin/env PATH=/crossbin:/usr/bin:/bin TCL_CONFIG=/usr/lib/aarch64-linux-gnu/tcl8.6 \
	make -C /src -j"$JOBS" OPENMSX_TARGET_CPU=aarch64 OPENMSX_TARGET_OS=linux \
	CXX=aarch64-linux-gnu-g++ OPENMSX_STRIP=false "$@"
ls -la "$REPO/derived/aarch64-linux-opt/bin/openmsx"
