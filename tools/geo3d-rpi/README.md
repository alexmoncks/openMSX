# openMSX (V9968 + geo3d) on a Raspberry Pi

A bundle for a Raspberry Pi 3B+ (or newer) running the stock Raspberry Pi OS
Lite, 64 bit (Debian 13 "trixie"): the fork built for aarch64, the C-BIOS
V9968 machine, the geo3d demo ROMs, an installer and a `geo3d` command that
starts openMSX on the text console, without X (SDL2 on KMS/DRM).

| File | Purpose |
|---|---|
| `cross-build.sh` | Build the tree for aarch64 in a Debian trixie chroot (run as root). |
| `make-bundle.sh <outdir>` | Pack `<outdir>/geo3d-rpi/`: the folder for the SD card. |
| `install.sh` | Runs on the Pi: apt packages, `/opt/openmsx-geo3d`, the `geo3d` command. |
| `geo3d` | Runs on the Pi: demos, any ROM, the speed measurement. |

## Build

```sh
sudo tools/geo3d-rpi/cross-build.sh
sudo HOME=/root tools/geo3d-rpi/make-bundle.sh /mnt/c/somewhere
```

`make-bundle.sh` takes the ROMs from `GEO3D_ROMS` and the C-BIOS V9968
machine from `~/.openMSX/share/machines`; `packages.txt` lists the Debian
packages that own the libraries the binary needs, plus Mesa and GBM/EGL.
No system ROMs are bundled, only C-BIOS.

## On the Pi

1. Write Raspberry Pi OS Lite (64 bit) to the card with Raspberry Pi Imager
   (set the user, and the Wi-Fi if there is no cable, in its settings).
2. Copy the `geo3d-rpi` folder to the card's boot partition (`bootfs`).
3. Boot, log in and run `sudo bash /boot/firmware/geo3d-rpi/install.sh`
   (it needs the network for apt). Log out and in again.
4. `geo3d bench`, then `geo3d demo`, `geo3d sphere`, `geo3d shooter`.

`geo3d bench` writes `geo3d-bench.txt`, and every run writes
`geo3d-last.log`; both are copied to `bootfs/geo3d-rpi`, where a PC can read
them. The `geo3d` command turns `approx_cmd_timing` on (`geo3d exact ...`
turns it off) and does not save settings.

## State on 2026-10-10

The aarch64 binary was run under qemu-user only: it boots the C-BIOS V9968
machine and runs SPHERE7 headless with both command timings. Nothing was
run on a real Pi yet, so the video path (SDL2 KMS/DRM, OpenGL 2.1 on the
VC4 Mesa driver, GLEW without GLX), the sound device and the speed are
untested.
