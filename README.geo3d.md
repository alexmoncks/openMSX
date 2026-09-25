# geo3d in openMSX (V9968 fork)

This branch (`geo3d`) is a fork of [buppu3/openMSX](https://github.com/buppu3/openMSX),
branch `v9968`, the openMSX fork that emulates HRA!'s V9968 VDP. It adds a
device for **geo3d**, a 3D coprocessor designed to run in the FPGA of the V9968
cartridge (a personal project, not part of the official V9968), so that its demo
ROM runs in an emulator.

geo3d itself, its RTL, its reference model and the demo ROM live in
[alexmoncks/V9968_Cartridge](https://github.com/alexmoncks/V9968_Cartridge/tree/geo3d-phase2/geo3d),
with a page of the demos in English, Portuguese and Spanish:
[geo3d/demos](https://github.com/alexmoncks/V9968_Cartridge/tree/geo3d-phase2/geo3d/demos).

## What is here

| Files | What |
|---|---|
| `src/video/Geo3DCore.hh/.cc` | geo3d itself: register window, vertex/edge/face/texture RAMs, transform, clipping, back-face culling, lighting, painter's sort, LINE and LRMM command lists. A 1:1 port of the Python reference model the RTL matches bit for bit, with no openMSX dependency. |
| `src/video/Geo3D.hh/.cc` | the openMSX device (`Geo3D`): two I/O ports, feeds the commands to the VDP |
| `share/extensions/geo3d.xml`, `geo3d88.xml` | the extensions: `-ext geo3d` (98h profile), `-ext geo3d88` (88h cartridge profile) |
| `src/video/VDP.hh/.cc` | a fix for the V9968 (see below) |
| `tools/geo3d_replay.cc` | runs a geo3d stimulus file through `Geo3DCore` and writes the command log, to diff against the reference model |
| `tools/geo3d_smoke.tcl` | a quick check of the device in a running machine |

## Using it

1. Build openMSX as usual (`./configure && make`).
2. Get the `C-BIOS_V9968_JP` machine from renatus-xxxx's
   [openmsx-v9968-windows-setup](https://github.com/renatus-xxxx/openmsx-v9968-windows-setup)
   (`config/machines/C-BIOS_V9968_JP.xml`) into `share/machines`.
3. Build `GEO3D_98.ROM` in V9968_Cartridge (`geo3d/rom/build_rom.py --base 0x98`)
   and run:

```
openmsx -machine C-BIOS_V9968_JP -ext geo3d -cart GEO3D_98.ROM -romtype ASCII16
```

For the ROM's music add `-ext scc`, or a MoonSound (`-ext moonsound`, which needs
its wave ROM) or `-ext OPL3Cartridge_Moonsound_compatible`.

## The device

- Ports: **9Dh** index write / status read, **9Fh** data, next to a V9968 on
  98h-9Ch (`-ext geo3d`). The register map is the one in the header of
  `geo3d/rtl/geo3d_engine.v`.
- Cartridge profile: `-ext HRA_V9968 -ext geo3d88` puts geo3d at **8Dh/8Fh**,
  next to the fork's V9968 cartridge at 88h-8Ch, on any machine (the order
  matters: geo3d88 looks up the VDP named `V9968`). Checked on an MSX1 and an
  MSX2+: geo3d answers and the V9968 reports ID 3 once R#21 bit 0 = 0. The
  picture of that second VDP has not been checked yet.
- `<vdp>` names the VDP device the commands go to (default `VDP`).
- Writing RUN computes the whole command list of the frame at once. The device
  then writes each command into the VDP command registers through
  `VDP::changeRegister` (the same path as a Z80 write), whenever the command
  engine is idle (CE = 0): LINE as R#36..R#46, LRMM as R#32..R#45, R#47..R#50
  (VX, VY) and R#46 last. While RUN is busy the device checks CE every 16 VDP
  clocks and on every status read. RUN busy (status bit 0) clears once the last
  command has finished, like the RTL's drain state, so a program that waits for
  it can flip pages right away.
- Savestates keep the whole geo3d state (checked: saved during the crawl,
  loaded back, the crawl and its music go on).

## The V9968 fix

In `v9968`, `version=V9968` means the new register layout (`V9968_NEW`). There,
`hasECOM()`, `hasEVR()` and `hasFID()` only held for `V9968_OLD`, so the S#1 ID
stayed 2, the command registers kept V9958 widths, R#47..R#58 did not reach the
command engine and VRAM stopped at 192 KB. This branch makes them hold for both
layouts (the `is*()` functions already switch on R#21 bit 0 for `V9968_NEW`) and
lets R#21 bit 0 = 0 also select the 256 KB VRAM mode, as `reg_vram256k_mode`
does in the FPGA (`vdp_cpu_interface.v`). The R#20 bits that switch these
features on `V9968_OLD` stay as they were. With it, renatus-xxxx's PROBE ROM
reports `VDP ID=3 / V9968 IDENTIFIED` on the `C-BIOS_V9968_JP` machine.

## Checks

- `tools/geo3d_replay` (build: `g++ -std=c++23 -O2 -Isrc/video
  tools/geo3d_replay.cc src/video/Geo3DCore.cc -o geo3d_replay`) reproduces,
  byte for byte, the command logs of the reference model for every test set of
  V9968_Cartridge: the random wireframe, solid and textured scenes, the three
  Z80 demo programs and the showcase scenes (hundreds of thousands of LINE and
  LRMM commands).
- `tools/geo3d_smoke.tcl`: loads the extension, checks the idle status and one
  RUN with a known LINE.
- The demo ROM runs through all its demos; its music chip detection finds the
  PSG, an SCC, an OPL3 and a MoonSound (OPL4) as expected.

## Limits

- geo3d here is not cycle exact: the geometry takes no emulated time, and each
  command is issued as soon as the VDP is idle. The fork's VDP timing is itself
  approximate (see `src/video/ToDo.txt`).
- The demo ROM for real hardware (88h) has not been run on the cartridge profile yet.

## Building for Windows

A static Windows build cross-compiles from Linux or WSL with MinGW-w64 (posix
threads):

```
make staticbindist OPENMSX_TARGET_OS=mingw-w64 OPENMSX_TARGET_CPU=x86_64
```

With GCC 15 as the host compiler, the `pkg-config` that the 3rd-party build
compiles needs `-std=gnu17` added to its `CFLAGS` in `build/3rdparty.mk` (its
bundled glib does not build as C23).

## License

openMSX is GPL-2.0. The new geo3d files carry `SPDX-License-Identifier: MIT`
(compatible with the GPL), copyright Alex Moncks.
