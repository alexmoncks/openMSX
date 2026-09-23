# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alex Moncks
# geo3d smoke test: openmsx -machine <V9968 machine> -ext geo3d -script tools/geo3d_smoke.tcl
# Expected: status idle 0, readback 2, busy 1 then 0, counters 0 0 1 0 0 0, R#36.. = 78 0 66 0 110 0 70 0 15 8 0
set renderer none
set throttle off
proc out {port val} { debug write ioports $port $val }
proc wr_words {idx words} {
  out 0x9D $idx
  foreach w $words { out 0x9F [expr {$w & 0xFF}]; out 0x9F [expr {($w >> 8) & 0xFF}] }
}
after time 3 {
  set f [open geo3d_smoke.txt w]
  puts $f "device: [machine_info device geo3d]"
  puts $f "status idle: [debug read ioports 0x9D]"
  # data path: NVERT = 2, NEDGE = 1, COLOR = 0x0F, read back through the window
  out 0x9D 0x42; out 0x9F 2; out 0x9F 1; out 0x9F 0x0F
  out 0x9D 0x42
  puts $f "readback 0x42: [debug read ioports 0x9F]"
  # one edge in SCREEN 5 terms: identity matrix, TZ = 256, F = 256, W = 256, H = 212
  wr_words 0x00 {16384 0 0 0 16384 0 0 0 16384 0 0 256 256 128 106 16 256 212}
  out 0x9D 0x40; out 0x9F 0; out 0x9F 0
  out 0x9D 0x50
  foreach w {-50 -30 0 60 40 0} { out 0x9F [expr {$w & 0xFF}]; out 0x9F [expr {($w >> 8) & 0xFF}] }
  out 0x9D 0x51; out 0x9F 0; out 0x9F 1
  out 0x9D 0x48; out 0x9F 0x01
  puts $f "status after RUN: [debug read ioports 0x9D]"
  close $f
  after time 1 {
    set f [open geo3d_smoke.txt a]
    puts $f "status 1 ms later: [debug read ioports 0x9D]"
    out 0x9D 0x4A
    set k {}
    foreach i {0x4A 0x4B 0x4C 0x4D 0x4E 0x4F} { out 0x9D $i; lappend k [debug read ioports 0x9F] }
    puts $f "counters (skip lo/hi, draw lo/hi, cull lo/hi): $k"
    set r {}
    foreach n {36 37 38 39 40 41 42 43 44 45 46} { lappend r [vdpreg $n] }
    puts $f "VDP R#36..R#46: $r"
    close $f
    exit
  }
}
