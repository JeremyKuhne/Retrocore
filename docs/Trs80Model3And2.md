# The TRS-80 Model III, 4 and 4P, and the Model II, 12 and 16

Retrocore runs the TRS-80's other Z80 machines beside the [Model I](Trs80ModelI.md):

- [`Trs80Model3Machine`](../src/Retrocore.Machines.Trs80/Trs80Model3Machine.cs): the **Model III**, the **Model 4**
  and the **Model 4P**, which share the Model III's ports, keyboard and disk controller;
- [`Trs80Model2Machine`](../src/Retrocore.Machines.Trs80/Trs80Model2Machine.cs): the **Model II** and **Model 12**,
  and the Z80 side of the **Model 16, 16B and Tandy 6000**.

The SDK has no sources for these machines' ROMs yet, so they need dumps of them (see [ROMs](#roms)). The hardware is
tested with ROMs the tests assemble, and no real ROM, DOS or program has been run on these machines yet; see
[What is not done yet](#what-is-not-done-yet).

## The Model III, 4 and 4P

| Area | Model III | Model 4 |
| --- | --- | --- |
| CPU | Z80 at 2.03 MHz | 2.03 MHz, or 4.06 MHz with port `$EC` bit 6 |
| ROM | 14K at `$0000`-`$37FF` | The same, in maps 0 and 1. The 4P's is a 4K boot ROM that port `$9C` bit 0 switches out. |
| RAM | 16, 32 or 48K from `$4000` | 64 or 128K; with 128K, port `$84` swaps a 32K half of the second 64K into either half of the address space. |
| Keyboard | `$3800`-`$3BFF`, the Model I's matrix plus the right SHIFT | Plus CTRL, CAPS and F1-F3; at `$F400` in map 2. |
| Video | 1K at `$3C00`: 64x16 (or 32x16) characters of 8x12 | 2K: 64x16 through a 1K page (port `$84` bit 7), or 80x24 (or 40x24) of 8x10 from the 6845's start address; all 2K at `$F800` in map 2. |

The Model 4's memory maps (port `$84` bits 0-1) are 0, the Model III's; 1, which writes RAM under the ROM; 2, RAM to
`$F3FF` with the keyboard at `$F400` and video at `$F800`; and 3, all RAM.

The ports are:

| Port | Read | Write |
| --- | --- | --- |
| `$E0`-`$E3` | Interrupt status, active low: bit 2 the 30 Hz clock | Interrupt mask |
| `$E4`-`$E7` | NMI status, active low: bit 7 the controller's INTRQ, 6 the motor timeout, 5 the reset button | NMI mask: bit 7 INTRQ, bit 6 the motor timeout |
| `$E8`-`$EB` | The RS-232 UART, with nothing connected | |
| `$EC`-`$EF` | Acknowledges the clock | Bit 1 cassette motor, 2 wide characters, 3 alternate characters, 6 the Model 4's 4 MHz |
| `$F0`-`$F3` | The FD1793 | The FD1793 |
| `$F4`-`$F7` | | Drive select: bits 0-3 the drive, 4 the side, 6 wait, 7 double density |
| `$F8`-`$FB` | Printer status | Printer |
| `$FC`-`$FF` | Cassette: bit 7 the 500 baud latch | Cassette output |
| `$84`-`$87` | | Model 4: the memory map, 80x24, inverse video, paging and the video page |
| `$88`-`$89` | | Model 4: the 6845 (only the start address changes the picture) |
| `$90`-`$93` | | Model 4: the speaker |
| `$9C`-`$9F` | | Model 4P: the boot ROM |

**Interrupts.** The real-time clock interrupts 30 times a second where `$E0` enables it, and reading `$EC` acknowledges
it. The disk controller's INTRQ and the drives' motor timeout raise an NMI where `$E4` enables them. The reset button
raises the NMI whatever the mask, with `$E4` bit 5 showing why.

**Disks.** The FD1793 is the Model I's controller in WD179x mode: both densities, 179x step rates and record types. A
drive select with bit 6 set holds the Z80 in WAIT until the controller asks for data or finishes, as Model III DOSes
use for double density. Selecting a drive runs the motors for 3 seconds. Four drives take JV1, JV3, DMK or IMD images
(see [Disk images](#disk-images)).

**Cassette.** 500 baud tapes play and record from CAS images through port `$FF`, with the motor on port `$EC` bit 1.
The Model 4P has no cassette port.

## The Model II, 12 and 16

| Area | Addresses or ports | Emulated |
| --- | --- | --- |
| Boot ROM | `$0000`-`$07FF` | 2K, over RAM until port `$F9` bit 0 is cleared. |
| RAM | `$0000`-`$7FFF`, and a bank at `$8000` | 32 to 512K in 32K banks: the first always low, and port `$FF` bits 0-3 choose the bank above (0 is none). |
| Video | `$F800`-`$FFFF` | 2K of video RAM, while port `$FF` bit 7 maps it; an MC6845 at `$FC`-`$FD` shows 80x24 (or 40x24 with bit 4), with bit 7 of a code inverse and the 6845's cursor. Bit 6 blanks it. |
| Keyboard | `$FC` | The keyboard's codes, latched; the latch raises the CTC's channel 3 trigger. |
| Clock | `$FE` | Each vertical sync toggles it; with `$FF` bit 5 it raises an NMI 30 times a second, which reading `$FE` acknowledges. |
| PIO | `$E0`-`$E3` | Port A reads the disk controller's INTRQ and a two-sided disk; port B is the printer. |
| FD1791 | `$E4`-`$E7`, drive select `$EF` | 8-inch drives at 360 rpm, both densities. Drive select: bits 0-3 the drive (active low), bit 6 clear side 1, bit 7 double density. |
| CTC | `$F0`-`$F3` | Four counter/timer channels in timer and counter modes. |
| SIO | `$F4`-`$F7` | Two serial channels with nothing connected. |
| DMA | `$F8` | A Z80 DMA, ready on the disk controller's DRQ: memory and I/O ports, byte, continuous and burst modes, end-of-block interrupts and auto restart. |

The peripherals interrupt in mode 2 through the Z80 daisy chain, from the CTC through the SIO and DMA to the PIO: the
requesting device puts its vector on the bus, and holds off the devices after it until its routine returns with
`RETI`, which the machine sees in the opcodes the Z80 fetches.

The keyboard sends ASCII, with CTRL giving `$01`-`$1A`, BREAK `$03`, ESC `$1B`, the arrows `$1C`-`$1F` (left, right,
up, down), HOLD `$00`, and F1 and F2 `$01` and `$02`. These follow the Model II's documentation as remembered rather
than its keyboard's ROM, so they need checking against a real ROM.

The Model 16, 16B and Tandy 6000 add a 68000 board, which is not emulated: they run what a Model II or 12 runs, such as
TRSDOS-II, and not TRS-XENIX.

## Disk images

The new machines, and now the Model I too, read four formats, by extension or, for `.dsk`, by contents:

| Format | Notes |
| --- | --- |
| JV1 | Single-density 10-sector tracks, as the Model I's DOSes use. |
| JV3 | Sector tables with density, side and record type per sector. |
| DMK | Raw tracks with their ID marks' offsets, single and double density. |
| IMD | ImageDisk, the usual format for Model II disks: FM and MFM, compressed, deleted and bad sectors. |

Writing changed disks back to their image files is not emulated yet, as on the Model I.

## ROMs

The ROMs are dumps under MAME's names, in `romDirectory` (or `RETROCORE_TRS80_ROMS`), or its `trs80m3`, `trs80m4`,
`trs80m4p`, `trs80m2` or `trs80m16` folder:

| Machine | System ROM | Character generator |
| --- | --- | --- |
| Model III | `8041364.u104`, `8040332.u105` and `8040316c.u106` (or `8040316b.u106`), or one 14K `trs80m3.rom` | `8044316a.u36` |
| Model 4 | `trs80m4.rom`, or the Model III's | `8044316a.u36` |
| Model 4P | `8075332.u69` | `8049007.u103` |
| Model II, 12, 16 | The newest of `u54.u11`, `cpu_fc86.u11`, `cpu_2119.u11`, `cpu_11be.u11`, `8047316.u11` and `8043216.u11`, or the one `bootRom` names | `8043316.u9` |

A launch without them fails and names the file it is missing.

## Debugging

The machines are in the Run and Debug dropdown and **Retrocore: Start Machine…**. Launch configurations name
`"machine": "trs80-model3"` with `"model"` `3`, `4` or `4p` (`"trs80-model4"` is the Model 4), or
`"machine": "trs80-model2"` with `"model"` `2`, `12` or `16`:

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "Model 4: TRSDOS 6",
    "machine": "trs80-model3",
    "model": "4",
    "romDirectory": "${env:RETROCORE_TRS80_ROMS}",
    "disks": ["${workspaceFolder}/disks/trsdos6.dsk"]
}
```

The options are `romDirectory`, `ramKilobytes`, `disks`, `diskController` (the Model III family's; on when disks are
given), `cassette` and `fastCassette` (Model III and 4), `fastDisk` (Model II: flat out while the controller works),
`bootRom` (Model II), `bootSeconds`, `screen` and `speed`. A `source` or `program` loads at `$7000`.

The display panel types the Model I's keys on the Model III family (Esc is BREAK, Home is CLEAR), and ASCII on the
Model II (Esc is BREAK, the arrows `$1C`-`$1F`), with buttons for BREAK, HOLD, F1 and F2. **Machine reset** stops at
`$0066` on the Model III family, whose reset button raises the NMI, and at `$0000` on the Model II, whose reset switch
resets the Z80. The Retro Devices view shows the cassette and drives.

Debugging is at the Z80 level: the call stack, registers, ports, memory and breakpoints work as on the Model I, but
with no ROM sources there is no source to step into, and no BASIC thread for the Model III's BASIC.

## Testing

| Test | Checks |
| --- | --- |
| `Trs80Model3Tests` | The Model III's map, clock interrupt, keyboard and NMI; the Model 4's maps, paging, speed and 80x24; the 4P's boot ROM; the FD1793 with wait and NMI; the cassette motor. |
| `Trs80Model2Tests` | Banked RAM; the CTC's mode 2 keyboard interrupt with `RETI`; the clock NMI; the 6845; the DMA reading a sector; IMD and DMK images. |
| [`tools/Test-Trs80Model3Dap.mjs`](../tools/Test-Trs80Model3Dap.mjs) | Each machine launching from stand-in dumps it writes, the missing-dump error, threads, hardware rows, and the Model II's reset stop. |

## What is not done yet

- **ROM sources.** These machines need dumps; the Model III ROM (largely Level II), the 4P's boot ROM and the Model
  II's boot ROM could become SDK sources as the Model I's did ([the backlog](backlog/Trs80Model3AndModel2.md)).
- **Real software.** No real ROM, TRSDOS, LDOS, NEWDOS or TRSDOS-II has been run; the hardware follows the technical
  references and MAME's drivers, and needs checking against them.
- **1500 baud cassettes** on the Model III and 4, which interrupt on the tape's edges.
- **The RS-232 ports**, the Model 4's sound beyond the speaker bit, its hi-res graphics board and hard disks, and the
  Model II's hard disks and serial devices.
- **The Model 16's 68000.**
- **Writing disk images back**, as on the Model I.
