# geo3d performance and equivalence tools

Scripts to measure what the V9968 command engine and the geo3d device cost on
the host, and to check that a change to them is invisible to the emulated
machine. They run headless (no window, no sound device) on Linux or WSL.

| Script | Purpose |
|---|---|
| `traces.sh <dir>` | Record the equivalence traces of every workload. |
| `traces.sh --compare <a> <b>` | Compare two trace sets (exit status 0 when identical). |
| `perf.sh <binary>...` | Host CPU used per emulated second, several interleaved runs. |
| `profile.sh [rom]` | Sampling profile by class and by function (no perf or gdb needed). |

Settings (binary under test, ROM directory, CPU to pin to) are environment
variables, listed at the top of `common.sh`. The V9968 machines and the system
ROMs are taken from `~/.openMSX/share`; a workload whose ROM is missing is
skipped.

## Checking a change

```sh
OPENMSX_BIN=/path/to/reference/openmsx tools/geo3d-perf/traces.sh /tmp/ref
make
tools/geo3d-perf/traces.sh /tmp/new
tools/geo3d-perf/traces.sh --compare /tmp/ref /tmp/new
```

Each workload is traced in two modes:

- `state`: every 13.7 ms of emulated time, a chained CRC of the VRAM, the
  visible memory, the CPU registers, the VDP registers and the palette.
- `probe`: a chained CRC of the emulated time of every VDP command start and
  end (the `commandExecuting` probe of every VDP in the machine).

Two runs of the same binary give identical files. A 2 % change of the geo3d
poll period (745 ns to 760 ns) changes every trace, the probe traces from
their first line.

The workloads cover the 98h profile (C-BIOS MSX2+ and a turboR), the 88h
cartridge profile next to a V9938, and BASIC drawing commands on the V9968
without the fast mode and on a plain V9938. A full run takes about 10 minutes.

Two more modes compare runs whose timing differs on purpose (`MODES=frames`
or `MODES=flips`, with `OPENMSX_SET="approx_cmd_timing on"` for one of the two
sets):

- `frames`: one line per frame period, the CRC of the VRAM page on display.
- `flips`: after every page flip (a change of VDP R#2), the CRC of the page
  now on display, numbered by flip instead of by time. Equal files mean the
  same sequence of pictures, whatever the timing.

Every run uses a private copy of `~/.openMSX/share/settings.xml`: openMSX
saves the settings on exit, and a test setting must not end up in that file.

## Measurements of 2026-10-10 (commit de29fb854, one core of an i7-1280P)

Host CPU per emulated second, no video: SPHERE7 6.8 %, the demo ROM 2.35 %.

Profile of SPHERE7: the V9968 side takes 77 % (VDPCmdEngine 51 %,
VDPAccessSlots 13 %, Graphic6Mode 6 %, VDPVRAM 4 %, VDP 3.5 %), geo3d 9 %,
the Z80 5 %, the scheduler 4 %. SPHERE7 issues about 67,000 VDP commands per
emulated second.

## Approximate command timing (prototype, setting `approx_cmd_timing`)

With `set approx_cmd_timing on`, the fast (HS) HMMV, HMMM, LINE and LRMM
commands are drawn in one go when they start, and CE stays set for an
estimated time: a cost per byte or pixel plus a cost per command, fitted on
the exact model (`ApproxCost` in `VDPCmdEngine.hh`). The other commands and
the V9938-speed mode keep the exact path. Off by default.

| | exact | approximate |
|---|---|---|
| SPHERE7, host CPU per emulated second | 6.77 % | 2.82 % |
| demo ROM | 2.41 % | 0.88 % |

Checked on 2026-10-10:

- setting off: the 13 traces are identical to the fork without the patch;
- setting on, command starts and ends in the same emulated time: demo ROM,
  shooter and the 88h profile equal, SPHERE7 +0.025 %, demo ROM on the
  turboR +0.013 %;
- setting on, sequence of pictures by page flip (`MODES=flips`), 150 s of
  SPHERE7 (8,707 flips), 345 s of the demo ROM (8,440) and 150 s of the demo
  ROM on the turboR (3,491): identical when the page is sampled 12 ms after
  the flip (`TRACE_FLIP_DELAY=0.012`). Sampled right at the flip, 1 to 7
  pictures differ in each: a command is still drawing in that page in the
  exact run, while the approximate run has drawn it at once. The approximate
  runs make one or two flips more in the same time (two of them at one demo
  transition);
- the shooter (3,431 flips): identical at the flip except flip 3; 12 ms
  later 29 differ, the game draws in the page on display.

Open: the cost table for LINE in SCREEN 7/8 is a guess (no workload uses
it), and LMMM is not covered (the 1 MB game uses it).

A trace mode that read the VRAM inside the `commandExecuting` probe callback
hung the exact path (the read re-enters the command engine while a command
is ending); it was replaced by `flips`.

## Exact optimizations that did not pay

Three changes that keep the traces identical were measured and gave no gain
outside the run-to-run noise, so they were not kept:

- the access slot calculation inlined in the command loops;
- `isHS()`, `isEVR()` and `isPlanar()` hoisted out of those loops;
- geo3d skipping the polls that fall before the engine's status change bound.

`set cmdtiming broken` does not change the cost either: the fast command path
still models every VRAM access (cache check and access slot).
