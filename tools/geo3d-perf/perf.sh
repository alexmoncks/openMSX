#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
#
# perf.sh <binary>... : host CPU seconds used per emulated second (in % of one
# core), no video, no throttle. The binaries are interleaved over ROUNDS runs
# (default 5) and the minimum, median and maximum are printed: on a busy host
# single runs differ by 10 %, so compare the minimums.
. "$(dirname "$(readlink -f "$0")")/common.sh"
ROUNDS=${ROUNDS:-5}
res=$(mktemp)

one() { # binary label seconds rom
	local bin=$1 label=$2 end=$3 rom=$4
	[ -f "$rom" ] || return
	headless BENCH_RENDERER=none BENCH_END=$end BENCH_WIN=$((end - 20)) \
		taskset -c "$BENCH_CPU" "$bin" "${M98[@]}" -cart "$rom" -romtype ASCII16 -script "$TOOLS/bench.tcl" 2>&1 \
		| grep -a BENCH | awk -v l="$label" -v b="$(basename "$bin")" '{ v=$7; gsub("%","",v); print b, l, v }' >> "$res"
}

for round in $(seq "$ROUNDS"); do
	for bin in "${@:-$OPENMSX_BIN}"; do
		one "$bin" sphere7 140 "$GEO3D_ROMS/SPHERE7_98.ROM"
		one "$bin" demo 345 "$GEO3D_ROMS/GEO3D_98.ROM"
		[ -n "$GEO3D_EXTRA_ROM" ] && one "$bin" extra 200 "$GEO3D_EXTRA_ROM"
	done
done
sort -k2,2 -k1,1 -k3,3n "$res" | awk '
	function out() { printf "%-8s %-16s min %.2f  median %.2f  max %.2f  (%d runs)\n", w, b, v[1], v[int((n+1)/2)], v[n], n }
	{ if ($2 " " $1 != last) { if (last != "") out(); n=0; last=$2 " " $1; w=$2; b=$1 } v[++n]=$3 }
	END { if (last != "") out() }'
rm -f "$res"
