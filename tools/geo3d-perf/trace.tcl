# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
#
# Equivalence trace for the VDP command engine (run by traces.sh). Environment:
#   TRACE_OUT   output file
#   TRACE_MODE  state | probe
#   TRACE_END   emulated seconds to run
#   TRACE_DT    state mode: sampling period in emulated seconds (default 0.0137)
#   TRACE_TYPE  optional text to type, TRACE_TYPE_AT emulated second (default 6)
# state: every TRACE_DT a chained CRC of VRAM, visible memory, CPU and VDP registers.
# probe: a chained CRC of the emulated time of every command start and end.
proc tenv {name def} {
	if {[info exists ::env($name)]} { return $::env($name) }
	return $def
}
set throttle off
set renderer none
# the clock chip follows emulated time, or two runs of a machine that reads it differ
if {[catch { set rtcmode EmuTime } err]} { puts stderr "trace: rtcmode not set ($err)" }
set ::t_out [open [tenv TRACE_OUT /tmp/trace.txt] w]
set ::t_end [tenv TRACE_END 60]
set ::t_dt [tenv TRACE_DT 0.0137]
set ::t_crc 0
set ::t_n 0
set ::t_blocks {}
foreach d {VRAM memory {CPU regs} {VDP regs} {VDP palette}} {
	if {![catch {debug size $d} sz]} { lappend ::t_blocks $d $sz }
}

proc t_state {} {
	foreach {d sz} $::t_blocks {
		set ::t_crc [zlib crc32 [debug read_block $d 0 $sz] $::t_crc]
	}
	incr ::t_n
	if {$::t_n % 50 == 0} {
		puts $::t_out [format "%d %.4f %08x" $::t_n [machine_info time] $::t_crc]
	}
	if {[machine_info time] >= $::t_end} { t_finish }
	after time $::t_dt t_state
}

proc t_probe {} {
	set ::t_crc [zlib crc32 [machine_info time] $::t_crc]
	incr ::t_n
	if {$::t_n % 500 == 0} {
		puts $::t_out [format "%d %s %08x" $::t_n [machine_info time] $::t_crc]
	}
}

proc t_finish {} {
	puts $::t_out [format "END %d %s %08x" $::t_n [machine_info time] $::t_crc]
	close $::t_out
	exit
}

if {[info exists ::env(TRACE_TYPE)]} {
	after time [tenv TRACE_TYPE_AT 6] { type [subst -nocommands -novariables $::env(TRACE_TYPE)] }
}
if {[tenv TRACE_MODE state] eq "probe"} {
	after time $::t_end t_finish
	# every VDP in the machine (the 88h profile has two)
	foreach p [debug probe list] {
		if {[string match *commandExecuting $p]} { debug probe set_bp $p {} t_probe }
	}
} else {
	after time $::t_dt t_state
}
