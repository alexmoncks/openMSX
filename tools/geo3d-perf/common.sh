# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
#
# Shared settings for the geo3d measurement scripts. Override with the environment:
#   OPENMSX_BIN   binary under test (default: this tree's linux opt build)
#   GEO3D_ROMS    directory with GEO3D_98.ROM, SPHERE7_98.ROM, GEO3D_88_hardware_real.ROM
#                 and game/GEO3D_SHOOTER_98.ROM (a missing ROM skips its workload)
#   GEO3D_EXTRA_ROM  one more ASCII16 ROM for the 98h profile (optional)
#   BENCH_CPU     CPU to pin the emulator to (default 2)
# The V9968 machines and the system ROMs come from the user's ~/.openMSX/share.

TOOLS=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
REPO=$(readlink -f "$TOOLS/../..")
OPENMSX_BIN=${OPENMSX_BIN:-$REPO/derived/x86_64-linux-opt/bin/openmsx}
GEO3D_ROMS=${GEO3D_ROMS:-/mnt/c/Projects/mmsoft/openmsx-geo3d}
BENCH_CPU=${BENCH_CPU:-2}

# headless: no window, no sound device, system data from this tree
headless() {
	env OPENMSX_SYSTEM_DATA="$REPO/share" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$@"
}

M98=(-machine C-BIOS_V9968_JP -ext geo3d)
