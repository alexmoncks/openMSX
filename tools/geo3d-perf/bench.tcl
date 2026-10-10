# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
#
# openMSX speed probe (run by perf.sh and profile.sh). Each window prints the
# emulation speed and the host CPU seconds used per emulated second. Environment:
#   BENCH_THROTTLE  on|off   (default off)
#   BENCH_RENDERER  none|SDLGL-PP (default: leave as is)
#   BENCH_END       emulated seconds to run (default 240)
#   BENCH_WIN       window length in emulated seconds (default 10)
#   BENCH_KEYS      1 = press "1" at the language menu (default 1)
#   BENCH_SHOT      directory for screenshots at each window (optional)
proc benv {name def} {
	if {[info exists ::env($name)]} { return $::env($name) }
	return $def
}
# OPENMSX_SET="name value ..." sets openMSX settings first, e.g. "approx_cmd_timing on"
if {[info exists ::env(OPENMSX_SET)]} { foreach {k v} $::env(OPENMSX_SET) { set ::$k $v } }
set ::bench_end [benv BENCH_END 240]
set ::bench_win [benv BENCH_WIN 10]
set throttle [benv BENCH_THROTTLE off]
if {[info exists ::env(BENCH_RENDERER)]} { set renderer $::env(BENCH_RENDERER) }
if {[info exists ::env(BENCH_CMDTIMING)]} { set cmdtiming $::env(BENCH_CMDTIMING) }

proc bench_cpu {} {
	set f [open /proc/self/stat r]
	set s [read $f]
	close $f
	# skip past "pid (comm) " (comm may contain spaces)
	set s [string range $s [expr {[string last ")" $s] + 2}] end]
	set l [split $s " "]
	# utime, stime are fields 14 and 15 of the full line, 11 and 12 here
	return [expr {([lindex $l 11] + [lindex $l 12]) / 100.0}]
}

proc bench_tick {} {
	set t [machine_info time]
	set w [expr {[clock microseconds] / 1e6}]
	set c [bench_cpu]
	if {[info exists ::bt]} {
		set dt [expr {$t - $::bt}]
		set dw [expr {$w - $::bw}]
		set dc [expr {$c - $::bc}]
		puts stderr [format "BENCH t=%5.0f speed=%6.0f%% cpu_per_emusec=%6.2f%% (emu=%.2f wall=%.3f cpu=%.2f)" \
			$t [expr {100.0 * $dt / $dw}] [expr {100.0 * $dc / $dt}] $dt $dw $dc]
		if {[info exists ::env(BENCH_SHOT)]} {
			catch { screenshot -raw $::env(BENCH_SHOT)/t[format %04.0f $t].png }
		}
	}
	set ::bt $t
	set ::bw $w
	set ::bc $c
	if {$t >= $::bench_end} { exit }
	after time $::bench_win bench_tick
}

if {[benv BENCH_KEYS 1]} {
	foreach kt {6 9 12 15} { after time $kt { type "1" } }
}
after time 20 bench_tick
