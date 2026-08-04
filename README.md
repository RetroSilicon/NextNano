# NextNano - ZX Spectrum Next implementation for the Tang Nano 20K FPGA board.

> **Status:** Early release — actively developed. Source code released.

📺 **[Watch The Saboteur! NEXT on NextNano in action on YouTube](https://www.youtube.com/watch?v=FlwklhXbSbg)**

![NextNano boot on Tang Nano 20K](screenshots/Boot.png)
![NextNano gameplay on Tang Nano 20K](screenshots/GamePlay.png)

## Hardware Requirements

-   **Tang Nano 20K** (Sipeed, Gowin GW2AR-18)
-   **USB-C Hub** — an active (powered) hub is recommended
-   **USB Keyboard** — wireless or wired
-   **microSD card** (FAT32, with NextZXOS contents — see below)
-   **HDMI display** and cable

### Optional:

-  **USB mouse** (emulated as Kempston Mouse)
-   **USB gamepad or joystick** (emulated as Kempston / Left port, 4 buttons)

## Preparing the SD Card

The SD card is **required** — NextNano boots into NextZXOS from the card.

1.  Format a microSD card as **FAT32**.
2.  Download the latest NextZXOS distribution from: **[https://www.specnext.com/latestdistro/](https://www.specnext.com/latestdistro/)**
3.  Extract the contents of the archive to the root of the SD card.
4.  Insert the card into the Tang Nano 20K's SD slot before powering on.

## Features

### Implemented

-   All ZX Spectrum Next features
-   Joystick (left port, Kempston)
-   Mouse (Kempston)
-   Keyboard
-   HDMI video and audio output - 50Hz and 60Hz supported

### Notes & Current Limitations

-   The system **boots at 28 MHz**. Switching to other frequency possible (F8).
-   **Networking is not yet implemented**. Network features will require an external BL616 (**M0S Dock**), because the BL616 built into the Tang Nano 20K has no antenna.

## Software Compatibility

All software tested so far runs flawlessly — including demoscene productions, games, BASIC programs, and utilities.


## Keyboard Mapping

| Spectrum Key   | USB Key             |
|----------------|---------------------|
| Symbol Shift   | Left Ctrl           |
| Edit           | Caps Shift + 1 or ~    |
| Break          | Caps Shift + Space  |
| Cursor keys    | Arrow keys          |

> Example: to type `LOAD ""` at the BASIC prompt, press `J`, then `Symbol Shift + P` twice.

## Function Keys

| Key  | Function                                            |
|------|-----------------------------------------------------|
| F1   | Hard reset                                          |
| F3   | Toggle 50 / 60 Hz video mode  |
| F4   | Soft reset                                          |
| F8   | Cycle CPU clock: 3.5 / 7 / 14 / 28 MHz              |
| F9   | NMI / Multiface                                     |
| F10  | DivMMC NMI                                          |


## Release v0.2 — Source Code Release

### Building from source 
To build the project, use Gowin EDA 1.9.12.03 and the provided tcl script, `nextNano.tcl`. The build has been tested only on Linux using `gw_sh`. From the source directory, run:

```
gw_sh nextNano.tcl
```

### Flashing the FPGA Bitstream

**macOS / Linux** — use [`openFPGALoader`](https://github.com/trabucayre/openFPGALoader):

```bash
openFPGALoader -f NextNano.fs
```

The `-f` flag writes the bitstream to the onboard flash so it persists across power cycles. Without `-f`, the bitstream is loaded into SRAM and will be lost on power-off.

**Windows** — use **Gowin Programmer**, included with the Gowin EDA toolchain. Select the Tang Nano 20K device, set the operation to _Embedded Flash Mode → Erase, Program_, choose `NextNano.fs`, and click _Program_.

### Flashing the FPGA Companion

To upload the FPGA Companion firmware, use the **Bouffalo Dev Cube** software (provided by BouffaloLab - https://dev.bouffalolab.com/download). Select the correct firmware file and load address for your setup:

| Target                        | Firmware File                          | Load Address |
|-------------------------------|----------------------------------------|--------------|
| Onboard BL616 (internal µC)   | `bl616_fpga_partner_nano20k.bin`       | `0x00000`    |
| Onboard BL616 (internal µC)   | `fpga_companion_TN20k_internal.bin`    | `0x40000`    |
| External M0S Dock             | `fpga_companion_bl616_m0s_dock.bin`    | `0x00000`    |


The onboard BL616 setup requires **both** files to be flashed at their respective load addresses.

----------

## Acknowledgments

NextNano stands on the shoulders of these projects:

-   **SpecNext Ltd. and the ZX Spectrum Next community**
-   **MiSTer FPGA** (https://github.com/MiSTer-devel/ZXNext_MISTer)
-   **MiSTle-Dev**(https://github.com/MiSTle-Dev/FPGA-Companion)

## Disclaimer

This project is not affiliated with, endorsed by, or associated with the official ZX Spectrum Next project or SpecNext Ltd.


