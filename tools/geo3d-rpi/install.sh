#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
#
# Installs the openMSX fork (V9968 + geo3d) on Raspberry Pi OS Lite, 64 bit
# (Debian 13 "trixie"). Run on the Pi, with a network connection:
#
#   sudo bash /boot/firmware/geo3d-rpi/install.sh
#
# It installs the runtime libraries with apt, unpacks the bundle that sits
# next to this script into /opt/openmsx-geo3d and adds the "geo3d" command.
set -e
HERE=$(dirname "$(readlink -f "$0")")
BUNDLE=$HERE/openmsx-geo3d-rpi.tar.gz
LOG=$HERE/install.log
exec > >(tee "$LOG") 2>&1

[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
[ -f "$BUNDLE" ] || { echo "Missing $BUNDLE"; exit 1; }
echo "== $(date)"
echo "board: $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)"
. /etc/os-release; echo "system: $PRETTY_NAME, $(uname -m)"
[ "$(uname -m)" = aarch64 ] || { echo "This build needs the 64 bit system (aarch64)."; exit 1; }
[ "$VERSION_CODENAME" = trixie ] || echo "WARNING: built for Debian 13 (trixie); this is $VERSION_CODENAME, libraries may not match."

echo "== runtime libraries"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
# shellcheck disable=SC2046
apt-get install -y -q --no-install-recommends $(cat "$HERE/packages.txt")

echo "== files"
rm -rf /opt/openmsx-geo3d
mkdir -p /opt
tar -xzf "$BUNDLE" -C /opt
chmod +x /opt/openmsx-geo3d/bin/openmsx /opt/openmsx-geo3d/geo3d
ln -sf /opt/openmsx-geo3d/geo3d /usr/local/bin/geo3d

# the user who called sudo needs the screen, the GPU, the keyboard and the sound
U=${SUDO_USER:-$(logname 2>/dev/null || true)}
if [ -n "$U" ] && [ "$U" != root ]; then
	for g in video render input audio; do
		getent group $g > /dev/null && usermod -aG $g "$U"
	done
	echo "user $U: $(id -nG "$U")"
fi

echo "== check"
missing=$(ldd /opt/openmsx-geo3d/bin/openmsx | grep 'not found' || true)
if [ -n "$missing" ]; then
	echo "MISSING LIBRARIES:"; echo "$missing"; exit 1
fi
OPENMSX_SYSTEM_DATA=/opt/openmsx-geo3d/share /opt/openmsx-geo3d/bin/openmsx -v | head -2
echo
echo "Installed. Log out and in again (new groups), then:"
echo "  geo3d bench     speed measurement, about 10 minutes"
echo "  geo3d demo      the geo3d demo ROM (also: sphere, shooter)"
