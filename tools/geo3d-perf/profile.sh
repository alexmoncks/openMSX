#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
#
# profile.sh [rom] : sampling profile by class and by function, without perf
# or gdb. Needs a binary with symbols: build with `make OPENMSX_STRIP=false`.
# The sampler is preloaded and records the program counter every 1 ms of CPU.
. "$(dirname "$(readlink -f "$0")")/common.sh"
ROM=${1:-$GEO3D_ROMS/SPHERE7_98.ROM}
tmp=$(mktemp -d)
gcc -O2 -shared -fPIC -o "$tmp/sampler.so" "$TOOLS/sampler.c" || exit 1
headless BENCH_RENDERER=none BENCH_END=${BENCH_END:-320} BENCH_WIN=100 \
	PROF_OUT="$tmp/samples.txt" LD_PRELOAD="$tmp/sampler.so" \
	taskset -c "$BENCH_CPU" "$OPENMSX_BIN" "${M98[@]}" -cart "$ROM" -romtype ASCII16 -script "$TOOLS/bench.tcl" 2>&1 \
	| grep -a BENCH
python3 "$TOOLS/symbolize.py" "$tmp/samples.txt" "$OPENMSX_BIN" "${TOP:-25}"
rm -rf "$tmp"
