# The TRS-80 Color Computer

Retrocore's Color Computer is [`CocoMachine`](../src/Retrocore.Machines.Coco/CocoMachine.cs): a cycle-exact
6809E with the CoCo 1, 2 or 3's memory map, video, keyboard, joysticks, cassette, sound and cartridge port, and
optionally the disk controller cartridge. The three models are variants of one machine, chosen by
[`CocoConfiguration`](../src/Retrocore.Machines.Coco/CocoConfiguration.cs)'s `Model`. This guide covers what it
emulates, its ROMs, and how to debug on it.

## The machine

### The CoCo 1 and 2

| Area | Addresses | Emulated |
| --- | --- | --- |
| RAM | `$0000-$7FFF` | 4, 16, 32 or 64 KB through the SAM; 64 KB machines page the upper 32 KB in with P1, or map it all with map type 1. |
| Extended Color BASIC | `$8000-$9FFF` | 1.0 or 1.1, or nothing. |
| Color BASIC | `$A000-$BFFF` | 1.0 to 1.3. |
| Cartridge | `$C000-$FEFF` | A ROM pack of up to 16 KB, or Disk Extended Color BASIC. |
| PIA 0 | `$FF00-$FF1F` | Keyboard rows and columns, the joystick comparator, HS and FS, and IRQ. |
| PIA 1 | `$FF20-$FF3F` | The 6-bit DAC, cassette in and motor, single-bit sound, RAM size strap, VDG mode, the cartridge's CART line, and FIRQ. |
| Disk controller | `$FF40-$FF5F` | The drive control register and the WD1793. |
| SAM | `$FFC0-$FFDF` | Video mode and offset, page, rate (0.89 or 1.79 MHz), memory size and map type. |
| Vectors | `$FFE0-$FFFF` | Color BASIC's last 32 bytes. |

**CPU.** The 6809E runs at 0.894886 MHz, a sixteenth of the 14.31818 MHz crystal, or twice that in the SAM's
fast rates. It passes the SingleStepTests at every cycle, with the undocumented opcodes, postbytes and transfers
the [6809 references](backlog/M6809-CoCo.md) describe.

**Video.** The MC6847 VDG, or the MC6847T1 with true lowercase (the CoCo 2B's chip, `LowercaseVdg`), draws text,
semigraphics 4 and 6, and the eight graphics modes, line by line as the beam reaches them. Two-color 256-dot
graphics show composite artifact colors, blue-red by default. The frame is 320x240, the 256x192 picture in its
border.

**Sound.** The DAC, the cassette and the single-bit output, through the analog multiplexer as PIA 0's CA2 and
CB2 select, while PIA 1's CB2 enables sound.

**Cassette.** `.cas` tapes play and record at 1500 baud. A recording is cut into blocks at each leader so that it
reads back as the tape it would have made.

**Cartridges.** A ROM pack starts itself through CART, as games do, unless `autostart` is false.

### The CoCo 3

The GIME replaces the SAM and VDG. Its MMU maps 128 or 512 KB in 8 KB blocks, with two task registers, and the
32 KB ROM holds Color BASIC, Extended Color BASIC 2.0 and the CoCo 3's additions. The GIME's registers at
`$FF90-$FFBF` set the MMU, ROM map, constant RAM page, palette, timer and its IRQ and FIRQ sources (timer,
borders, keyboard and cartridge). Its video draws the CoCo 1 and 2's modes in compatible mode, and 32, 40 and
80-column text with attributes and 16-color graphics up to 640 dots in its own, on a composite monitor or the
CM-8 RGB monitor (`RgbMonitor`).

### The disk controller

The disk controller cartridge (`CocoDiskController`) holds Disk Extended Color BASIC 1.0 or 1.1 in its ROM, a
WD1793 and four drives. `$FF40` selects the drive, side, motor and density, and lets the WD1793's INTRQ drive
NMI and its DRQ release HALT, which Disk BASIC uses to move each sector's bytes. Disks are JVC images (`.dsk`):
35 tracks of 18 256-byte sectors, with an optional header for other geometries. The WD1793 is the Model I's
controller, shared with the TRS-80's code.

## ROMs

Every ROM the machines run is an SDK source, maintained by hand and byte-identical to the ROM: Color BASIC 1.0 to 1.3,
Extended Color BASIC 1.0 and 1.1, Disk Extended Color BASIC 1.0 and 1.1, and the CoCo 3's 32 KB ROM,
[`ColorBasic.asm`](../src/Retrocore.Machines.Coco/Roms/ColorBasic.asm),
[`ExtendedBasic.asm`](../src/Retrocore.Machines.Coco/Roms/ExtendedBasic.asm),
[`DiskBasic.asm`](../src/Retrocore.Machines.Coco/Roms/DiskBasic.asm) and
[`Coco3.asm`](../src/Retrocore.Machines.Coco/Roms/Coco3.asm). They share the RAM, hardware, token and error names in
`ColorBasicEquates.asm`, `ExtendedBasicEquates.asm`, `DiskBasicEquates.asm` and `Coco3Equates.asm`, and each names
the routines it calls in the others through `ColorBasicEntries.asm`, `ExtendedBasicEntries.asm` and
`Coco3Entries.asm`.

The CoCo 3's ROM is Extended Color BASIC 1.1 and Color BASIC 1.2 with the CoCo 3's patches, which the two sources
apply when `COCO3` is set, with `Coco3.asm` on top: the start-up and Super Extended Color BASIC at `$C000-$FDFF`. The
patches in place give Extended BASIC 2.0's sign-on, send RESET to the start-up, replace the CoCo 2's RAM test and
memory size setting, which the GIME's MMU makes unneeded, drop the quick keyboard check, and point the interrupt
vectors at the GIME's constant page. The
start-up copies the ROM into RAM and patches the copy further, from the table in `Coco3.asm`, so that crunching,
listing, the command loop, errors, BREAK and the screen's output reach Super Extended BASIC; BASIC then runs in
RAM. The debugger follows: on a CoCo 3 the three sources apply wherever their bytes are, and the patched places show
the patches' source.

Nothing external is needed: without dumps, every model's ROMs are built from the sources, disk controller included,
and debugging steps into them wherever the BASICs run. Dumps can still take their place, from a directory of dumps
under MAME's names: `romDirectory`, or `RETROCORE_COCO_ROMS`, in the directory itself or its `coco`, `coco2b`, `coco3`
and `coco_fdc` folders. A blank `romDirectory`, as `${env:RETROCORE_COCO_ROMS}` gives when the variable is not set,
names no dumps.

| Model | Files |
| --- | --- |
| CoCo 1 and 2 | `bas10.rom` to `bas13.rom`, `extbas10.rom` and `extbas11.rom` |
| CoCo 3 | `coco3.rom` |
| Disk controller | `disk10.rom` and `disk11.rom` |

## Debugging

The three models are in the Run and Debug dropdown, and **Retrocore: Start Machine…** starts them with a program,
a tape or a disk. Launch configurations take `"machine": "coco"` and a `model`:

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "Color Computer: 6809 sample",
    "machine": "coco",
    "model": "coco2",
    "source": "${workspaceFolder}/sample/coco/hello.asm",
    "stopOnEntry": true
}
```

BASIC runs for `bootSeconds` (two seconds by default) before the program loads at `$3000`, so the screen and
Color BASIC's RAM hooks are in place for [the sample](../sample/coco/hello.asm)'s `JSR [CHROUT]`.

The options are:

- `model`: `coco1`, `coco2` (the default) or `coco3`;
- `ramKilobytes`: 4, 16, 32 or 64 on a CoCo 1 or 2 (16 on a CoCo 1 and 64 on a CoCo 2 by default), 128 (the
  default) or 512 on a CoCo 3;
- `colorBasic` (`1.0` to `1.3`, `1.2` by default) and `extendedBasic` (`1.0`, `1.1` or `none`) on a CoCo 1 or 2;
  without dumps, both are built from the sources;
- `sdkRoms`: the folder of the ROM sources, such as the repository's, so breakpoints set there bind;
- `lowercase`: the MC6847T1 VDG on a CoCo 1 or 2;
- `artifacts`: `blue-red` (the default), `red-blue` or `none`;
- `monitor`: `composite` (the default) or `rgb` on a CoCo 3;
- `cartridge` and `autostart`: a ROM pack image, which takes the slot from the disk controller;
- `diskController` (on by default when disks are given), `diskBasic` (`1.0` or `1.1`, `1.1` by default; without
  dumps, built from the source) and `disks`, JVC images for drives 0-3;
- `cassette` and `fastCassette` (on by default);
- `sound`: `speaker` (the default) or `off`;
- `speed`: `1` (the default) runs at 0.895 MHz, `2`, `4` or `8` that many times as fast, and `"max"` as fast as
  possible.

The panel's key bar has **Break** (Esc), **Clear** (Home) and **Reset** (Ctrl+F12 or Ctrl+Break), which restarts
the 6809 through its reset vector; Color BASIC starts again with the program kept. **Machine reset** stops at the
first instruction after it. The Retro Devices view shows the cassette and the drives, and inserts, records and
ejects media, as on the Model I; `retro/media` takes the same requests.

**What the debugger knows about the 6809.**

- The call stack follows `JSR`, `BSR`, `LBSR`, the three `SWI`s and interrupts on the S stack, checking each
  frame's return address, so a routine that drops its return address ends its frame.
- The Variables view lists A, B, D, X, Y, U, S, DP, CC and PC, and the **Direct page** memory scope.
- Step over steps over calls, including `JSR` indexed, and step out stops when the stack returns to the caller.
- While the disk controller holds HALT, or the 6809 waits in `SYNC` or `CWAI`, it is between instructions;
  breakpoints are checked when it goes on.

Color BASIC programs debug at the 6809 level; the BASIC thread, the Level II and AppleSoft dialects have, is not
yet there for Color BASIC.

## Testing

| Test | Checks |
| --- | --- |
| `CocoMachineTests` | Each Color BASIC and Extended Color BASIC pairing boots, runs typed lines and counts TIMER; the CoCo 3 boots and changes width. |
| `CocoVideoTests`, `Coco3VideoTests` | The VDG's and GIME's modes, pixel by pixel. |
| `CocoPeripheralTests` | A cassette round trip, joysticks, sound and a ROM pack. |
| `CocoDiskTests` | DSKINI, SAVE, DIR and LOAD on a CoCo 2 and 3, and JVC images. |
| `CocoRomSourceTests` | The Color, Extended and Disk BASIC sources and the CoCo 3's ROM, by digest for each version and against the dumps, and machines booting from them, saving and loading a program on disk, and the CoCo 3 drawing on its hi-res screen. |
| `CocoOracleTests` (Conformance) | The same keystrokes on our machine and on MAME, through [`tools/Trs80Oracle.lua`](../tools/Trs80Oracle.lua): screens and programs on the CoCo 2, 2B and 3, and a Disk BASIC SAVE's disk image byte for byte. |
| [`tools/Test-CocoDap.mjs`](../tools/Test-CocoDap.mjs) | The debugger end to end: stepping from the sample into `ColorBasic.asm` and through the console out hook into `ExtendedBasic.asm`, or with a disk into `DiskBasic.asm`, and on a CoCo 3 into its `ColorBasic.asm` and on into a patch in `Coco3.asm`, which then switches to 80 columns; then Disk BASIC saving and listing a program, a breakpoint in the sample with its call stack and step out, and the CoCo 3 at 80 columns, on the dumps when they are there and otherwise on the sources. |

The machine, disk, video and peripheral tests and the DAP script run on the dumps when they are there and otherwise
on the ROMs built from the sources, so they need nothing external. Only the comparisons with the dumps and with MAME
are inconclusive without them.

The [MAME 0.264 ROM sets on archive.org](https://archive.org/download/mame-0.264-roms-non-merged/) hold the
dumps under these names, in `coco.zip`, `coco2b.zip`, `coco3.zip` and `coco_fdc.zip`; MAME 0.289 is the oracle.
