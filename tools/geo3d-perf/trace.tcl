# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
#
# Equivalence trace for the VDP command engine (run by traces.sh). Environment:
#   TRACE_OUT   output file
#   TRACE_MODE  state | probe | frames | flips
#   TRACE_END   emulated seconds to run
#   TRACE_DT    state mode: sampling period in emulated seconds (default 0.0137)
#   TRACE_TYPE  optional text to type, TRACE_TYPE_AT emulated second (default 6)
# state: every TRACE_DT a chained CRC of VRAM, visible memory, CPU and VDP registers.
# probe: a chained CRC of the emulated time of every command start and end.
# flips:  after every page flip (a change of VDP R#2, looked for every 2 ms),
#         the CRC of the VRAM page now on display, numbered by flip instead of
#         by time: equal lines in two runs mean the same sequence of pictures,
#         whatever the timing.
# frames: every TRACE_FDT (one NTSC frame), the CRC of the VRAM page on display (to compare pictures
#         between runs whose timing differs, e.g. approx_cmd_timing on and off).
proc tenv {name def} {
	if {[info exists ::env($name)]} { return $::env($name) }
	return $def
}
# OPENMSX_SET="name value ..." sets openMSX settings first, e.g. "approx_cmd_timing on"
if {[info exists ::env(OPENMSX_SET)]} { foreach {k v} $::env(OPENMSX_SET) { set ::$k $v } }
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

# One line per frame period: the CRC of the VRAM page on display (bitmap modes
# of the internal VDP). Not chained, so two traces can be compared line by
# line. Sampled on a timer: 'after frame' does not fire without a renderer.
proc t_frame {} {
	set r0 [debug read "VDP regs" 0]
	set page [expr {([debug read "VDP regs" 2] >> 5) & 3}]
	switch [expr {$r0 & 0x0E}] {
		6 - 8   { set size 0x8000 }
		10 - 14 { set size 0x10000 }
		default { set size 0 }
	}
	incr ::t_n
	if {$size && ($page + 1) * $size <= [debug size VRAM]} {
		puts $::t_out [format "%d %08x" $::t_n [zlib crc32 [debug read_block VRAM [expr {$page * $size}] $size]]]
	} else {
		puts $::t_out "$::t_n -"
	}
	if {[machine_info time] >= $::t_end} { t_finish }
	after time $::t_fdt t_frame
}

proc t_page_crc {} {
	set page [expr {([debug read "VDP regs" 2] >> 5) & 3}]
	switch [expr {[debug read "VDP regs" 0] & 0x0E}] {
		6 - 8   { set size 0x8000 }
		10 - 14 { set size 0x10000 }
		default { return - }
	}
	if {($page + 1) * $size > [debug size VRAM]} { return - }
	return [format %08x [zlib crc32 [debug read_block VRAM [expr {$page * $size}] $size]]]
}

proc t_flip_sample {n} {
	puts $::t_out "$n [t_page_crc]"
}

proc t_flips {} {
	set r2 [debug read "VDP regs" 2]
	if {$r2 != $::t_r2} {
		set ::t_r2 $r2
		incr ::t_n
		# TRACE_FLIP_DELAY (seconds) samples later in the frame: a command
		# still drawing in the page at the flip has finished by then
		after time [tenv TRACE_FLIP_DELAY 0] [list t_flip_sample $::t_n]
	}
	if {[machine_info time] >= $::t_end} { t_finish }
	after time 0.002 t_flips
}

proc t_finish {} {
	puts $::t_out [format "END %d %s %08x" $::t_n [machine_info time] $::t_crc]
	close $::t_out
	exit
}

if {[info exists ::env(TRACE_TYPE)]} {
	after time [tenv TRACE_TYPE_AT 6] { type [subst -nocommands -novariables $::env(TRACE_TYPE)] }
}
if {[tenv TRACE_MODE state] eq "frames"} {
	set ::t_fdt [tenv TRACE_FDT 0.0166886]
	after time $::t_fdt t_frame
} elseif {[tenv TRACE_MODE state] eq "flips"} {
	set ::t_r2 [debug read "VDP regs" 2]
	after time 0.002 t_flips
} elseif {[tenv TRACE_MODE state] eq "probe"} {
	after time $::t_end t_finish
	# every VDP in the machine (the 88h profile has two)
	foreach p [debug probe list] {
		if {[string match *commandExecuting $p]} { debug probe set_bp $p {} t_probe }
	}
} else {
	after time $::t_dt t_state
}
