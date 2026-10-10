#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
#
# Equivalence traces: does a change to the VDP command engine or to the geo3d
# device alter anything the emulated machine can observe?
#
#   traces.sh <outdir>            run every workload, write <outdir>/<name>.<mode>.txt
#   traces.sh --compare <a> <b>   compare two trace sets
#   ONLY="sphere7 demo" traces.sh <outdir>   run a subset
#
# Each workload runs twice (see trace.tcl): "state" samples a chained CRC of
# VRAM, memory, CPU and VDP registers every 13.7 ms of emulated time; "probe"
# chains the emulated time of every VDP command start and end. Take the
# reference set with the unmodified binary, the second set with OPENMSX_BIN
# pointing at the new one. Two runs of the same binary give identical files.
. "$(dirname "$(readlink -f "$0")")/common.sh"

if [ "$1" = "--compare" ]; then
	ok=0; bad=0
	for f in "$2"/*.txt; do
		n=$(basename "$f")
		if [ ! -f "$3/$n" ]; then echo "MISSING  $n"; bad=$((bad + 1)); continue; fi
		if cmp -s "$f" "$3/$n"; then
			ok=$((ok + 1))
		else
			bad=$((bad + 1))
			echo "DIFFERS  $n, first at line $(cmp "$f" "$3/$n" | awk '{print $NF}'):"
			diff "$f" "$3/$n" | head -3
		fi
	done
	echo "identical: $ok, different: $bad"
	[ $bad -eq 0 ]
	exit
fi

OUT=${1:?usage: traces.sh <outdir> | --compare <a> <b>}
mkdir -p "$OUT"
BASIC='10 SCREEN 5:R=RND(-1)\r20 FOR I=0 TO 60:LINE(RND(1)*255,RND(1)*211)-(RND(1)*255,RND(1)*211),I AND 15:NEXT\r30 LINE(20,20)-(200,150),5,BF:PAINT(5,5),3:COPY(0,0)-(100,100) TO (50,50):CIRCLE(128,100),60,7\r40 COPY(10,10)-(90,90) TO (120,60),0,XOR:GOTO 20\rRUN\r'

run() { # name seconds [VAR=value...] -- openmsx arguments
	local name=$1 end=$2; shift 2
	local envs=()
	while [ "$1" != "--" ]; do envs+=("$1"); shift; done
	shift
	if [ -n "$ONLY" ] && [[ " $ONLY " != *" $name "* ]]; then return; fi
	for a in "$@"; do
		if [[ "$a" == *.ROM ]] && [ ! -f "$a" ]; then echo "skip $name: no $a"; return; fi
	done
	for mode in ${MODES:-state probe}; do
		headless TRACE_OUT="$OUT/$name.$mode.txt" TRACE_MODE=$mode TRACE_END=$end "${envs[@]}" \
			"$OPENMSX_BIN" "$@" -script "$TOOLS/trace.tcl" > "$OUT/$name.$mode.log" 2>&1 &
	done
}

R=$GEO3D_ROMS
run sphere7 150 -- "${M98[@]}" -cart "$R/SPHERE7_98.ROM" -romtype ASCII16
run demo 345 TRACE_TYPE=1 -- "${M98[@]}" -cart "$R/GEO3D_98.ROM" -romtype ASCII16
[ -n "$GEO3D_EXTRA_ROM" ] && run extra 200 "TRACE_TYPE= " TRACE_TYPE_AT=30 -- "${M98[@]}" -cart "$GEO3D_EXTRA_ROM" -romtype ASCII16
wait
run shooter 120 "TRACE_TYPE= " TRACE_TYPE_AT=20 -- "${M98[@]}" -cart "$R/game/GEO3D_SHOOTER_98.ROM" -romtype ASCII16
run demo_turbor 150 TRACE_TYPE=1 TRACE_TYPE_AT=12 -- -machine Panasonic_FS-A1ST_V9968 -ext geo3d -cart "$R/GEO3D_98.ROM" -romtype ASCII16
run demo_88 150 TRACE_TYPE=1 TRACE_TYPE_AT=12 -- -machine Philips_NMS_8250 -ext HRA_V9968 -ext geo3d88 -cart "$R/GEO3D_88_hardware_real.ROM" -romtype ASCII16
wait
# BASIC drawing: the V9968 without geo3d and without the fast mode, and a plain V9938.
# The turboR boots Disk BASIC 2, which stores the host date in RAM: its state
# trace differs from run to run, so only the command timing is traced there.
MODES=probe run basic_turbor 120 "TRACE_TYPE=$BASIC" TRACE_TYPE_AT=25 -- -machine Panasonic_FS-A1ST_V9968
run basic_v9938 120 "TRACE_TYPE=$BASIC" TRACE_TYPE_AT=25 -- -machine Philips_NMS_8250
wait

for f in "$OUT"/*.txt; do printf '%-26s %s\n' "$(basename "$f")" "$(tail -1 "$f")"; done
grep -l -E 'Fatal error|No such probe|trace:' "$OUT"/*.log 2>/dev/null
exit 0
