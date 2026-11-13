# The Apple III

Retrocore emulates the Apple III of 1980: its banked memory and extended addressing, video modes, built-in and
external drives, keyboard and sound. It boots Apple's SOS 1.3 disks: the System Utilities, Business BASIC and the
rest. The boot ROM is assembled from the SDK's documented source, byte-identical to Apple's, so no dump is needed to
run or debug it.

## Starting one

Pick **Apple III** in the Run and Debug dropdown, or use **Retrocore: Start Machine**. A launch configuration
names it with `"machine": "apple3"`:

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "Apple III",
    "machine": "apple3",
    "disks": ["${workspaceFolder}/disks/SOS-Utilities.dsk"]
}
```

| Option | Meaning |
| --- | --- |
| `ramKilobytes` | 128, 256 (the default) or 512 (third-party upgrades). |
| `disks` | Images for .D1, the built-in drive, then the external .D2-.D4: DOS-order (`.dsk`, `.do`), ProDOS-order (`.po`) or WOZ. Disks load write-protected; **Unprotect** in the Retro Devices view lets the machine write one, in memory. |
| `romDirectory` | MAME's `apple3` set (`apple3.rom`, `341-0028-a.rom`), or `RETROCORE_APPLE3_ROMS`. Without it the ROM comes from the SDK. |
| `fastDisk` | Runs flat out while a drive's motor turns (on by default). |
| `sound` | `speaker` (the default) or `off`. |
| `screen` | The monitor: `color` (the default), or a monochrome `white`, `green` or `amber` one, which shows each pixel in the phosphor's color by its brightness. The display panel's **Screen** changes it. |
| `proFiles` | ProFile cards, each `{ "slot": 4, "image": "profile.po" }` with slot 1-4 and an optional image ([The ProFile](#the-profile)). |

With no disk, the boot ROM runs its diagnostics and shows RETRY. Press a key to try again once a disk is in.

## Apple II emulation

Apple's Apple II Emulation disk turns the machine into a 48K, 1 MHz Apple II Plus. Boot it, then, at its menu, put
an Apple II disk such as DOS 3.3 in the built-in drive (the **Retro Devices** view's drive 1) and press RETURN.

- The disk loads the II Plus's ROMs into write-protected RAM at `$D000-$FFFF`, then clears VIA 1 port A bit 6, the
  mode trap. That hides the VIAs, so nothing can change the environment register again: only turning the machine
  off leaves the mode. The Hardware view's environment register says "Apple II mode".
- CONTROL-RESET is an NMI there, which the emulation's ROM points at the Apple II's reset code, as RESET is on a
  II Plus.
- The machine is still an Apple III underneath: the debugger shows its banks and its registers, and the panel's
  keys and sound work as before.

## The hardware

- **Processor.** A 6502A at 2 MHz, which drops to 1 MHz while the beam draws a visible line with video on, or
  always when the environment register asks. The Service Reference Manual gives 1.4 MHz on average.
- **Memory.** 32K banks. The last is the system bank, at `$0000-$1FFF` and `$A000-$FFFF`; the bank register
  (`$FFEF`) picks the one at `$2000-$9FFF`. Bank number 7 (15 with 512K) is bank 0, with the system RAM, as the
  memory board decodes it.
- **Registers in the VIAs.** The environment register (`$FFDF`) sets the speed, I/O, video, reset, write protection,
  the stack and the ROM. The zero-page register (`$FFD0`) moves zero page, and the stack with it.
- **Extended addressing.** With zero page in `$18xx-$1Fxx`, `(zp),Y` and `(zp,X)` read an X-byte at the pointer XOR
  `$0C00`. With bit 7 set, it reaches bank N below `$8000` and N+1 above. SOS keeps its buffers in banks this way.
- **Video.**
  - 40-column text, black and white or in 16 colors.
  - 80-column text.
  - 280×192 black and white, or with a color byte per 7 dots.
  - 560×192 black and white, and 140×192 in 16 colors.
  - Smooth scrolling.
  - A 128-character set in RAM, loaded through the screen holes.
- **Disks.** The Disk II's logic, built in, with three external drives.
- **Other devices.** The keyboard with its Apple keys, the speaker and the 6-bit DAC, the clock and the serial port.
- **Slots.** Four, for ProFile interface cards ([The ProFile](#the-profile)).

## The ProFile

Apple's ProFile is a 5 MB hard disk, cabled to a ProFile interface card in one of the four slots. SOS reaches it through
the `.PROFILE` driver in `SOS.DRIVER`; the System Utilities disk's copy is configured for slot 4, so a card there (the
launch's `proFiles`, or **Add Card** in the Retro Devices view) with an image in its ProFile works once SOS boots
from the floppy. The boot ROM cannot boot from it. The image is a ProDOS-order (`.po` or `.hdv`) image of a SOS volume,
up to 65535 blocks, of which `.PROFILE` as Apple shipped it uses the first 9728; the machine can write to it, and
changes stay in memory.

The card follows Apple's driver ([Sos.md](Sos.md)):

- **Ports** at `$C080` plus 16 times the slot: `+0` writes a byte to the ProFile, `+1` reads one, `+2` is the status
  (bit 7 set while BSY is low, bit 6 a parity error, bit 0 no ProFile), and a write to `+3` clears the parity error.
- **Lines** are an addressable latch that any access to the card's `$Cn00` page sets: address bits 0, 1 and 3 pick
  the line (CMD, the direction, the interrupt enable, the port's read/write line and the ProFile's reset) and bit 2 is
  its level. So `$Cn04` raises CMD, `$Cn00` drops it, `$Cn0C` resets the ProFile.
- **Pseudo-DMA** moves whole pages. The driver points the zero-page register at the buffer and calls the boot ROM's
  chain of `SBC #$01`/`BEQ` at `$F800`. As the Service Reference Manual describes, each fetch from `$F800-$F8FF` lowers
  DMA OK, and the card moves one byte between the ProFile and RAM at the zero page's page and the fetch's low byte,
  while the CPU still reads the ROM. Every fetch counts, the dummy reads of the last, taken branch among them, which is
  why the driver enters the chain at even addresses and keeps bytes 0 and `$FE` of a short last page aside. The card
  that answers is the last one the CPU reached.
- **The ProFile** (`ProFileDrive`, shared with the [Apple II's card](Apple2.md#slots-and-cards)) plays the Z8
  controller's side of the CMD-BSY handshakes: response 1 for a command, 2 when a read's status and block are ready,
  3 or 4 for a write's data and 6 to write it. It answers at once, keeps no tags, and gives its identification
  block at `$FFFFFF`. The card's interrupt is not raised; the driver turns it off.

`Apple3ProFileTests` runs Apple's `.PROFILE` 1.30, assembled from the SDK's source, against the card, reading and
writing buffers at every alignment.

Phase by phase, how this was built and checked against MAME and the manual is in the
[backlog plan](backlog/Apple3.md).

## Debugging

The Apple III debugs as the Apple II does: source breakpoints, the call stack, stepping and memory views. The boot ROM's
source, [`BootRom.asm`](../src/Retrocore.Machines.Apple3/Roms/BootRom.asm), is a ROM module, so a breakpoint in it stops
there. Its hardware names are in [`Apple3Equates.asm`](../src/Retrocore.Machines.Apple3/Roms/Apple3Equates.asm).

Memory references can name a bank:

- `system:$A000` reads the system bank, and `bank2:$2000` bank 2, whichever is switched in;
- `rom:$F000` reads the boot ROM, even when RAM is mapped over it;
- `x81:$3000` reads through X-byte `$81`, as SOS writes an extended address.

A breakpoint on `bank2:$2000` stops only while bank 2 is switched in. **Retrocore: Open Memory** lists the banks.

A program calls SOS with `BRK`, a call number and its parameters' address:

- A function breakpoint such as `sos OPEN`, or `sos` for every call, stops before the call. With a log message
  such as `{sos} from {PC}` it traces calls instead, writing lines such as `OPEN ".CONSOLE" from $866D`.
- **BRK instructions** (on by default) stops only at a `BRK` that is not a call, such as `BRK $00` from running
  into empty memory, and at SOS's debug call, `BRK $FE`.

[Breakpoints.md](Breakpoints.md#sos-call-breakpoints) has the details.

Apple III Pascal's programs debug on a Pascal thread, by source line through the compiler's listing: see
[Pascal.md](Pascal.md).

SOS itself debugs at its source: the SDK has SOS 1.3's kernel, its bootstrap loader and Apple's drivers, each
byte-identical to Apple's disks, and the debugger maps the drivers as SOS loads them. [Sos.md](Sos.md) covers them.

The SDK also has the source of Business BASIC 1.23's interpreter, byte-identical to its disk's `SOS.INTERP`, and it
debugs at that source where SOS loads it. Programs in Business BASIC debug on a BASIC thread, statement by statement.
[BusinessBasic.md](BusinessBasic.md) covers both.

The display panel shows the screen, with **Fast disk**, **Sound** and its volume, and buttons for Ctrl, CONTROL-C,
CONTROL-RESET, Esc and the Apple keys. Left Alt is Open Apple, right Alt Solid Apple, and Ctrl+F12 CONTROL-RESET.

## Testing

- `Apple3BusTests` and `Apple3VideoTests` need no files.
- `Apple3RomSourceTests` pins the boot ROM source by SHA-256.
- `Apple3MachineTests`, `Apple3SosTests` and `Apple3EmulationTests` need MAME's `apple3` set
  (`RETROCORE_APPLE3_ROMS`, by default `<cache>\apple3-roms\mame\apple3`) and Apple's disks
  (`RETROCORE_APPLE3_DISKS`); the emulation test also needs the DOS 3.3 System Master in `<cache>\iie-disks`.
- `Apple3OracleTests` runs MAME (`RETROCORE_MAME`).
- `Apple3ProFileTests` needs no files: it runs Apple's `.PROFILE` driver from the SDK on the SDK's boot ROM.
- `node tools/Test-Apple3Dap.mjs` drives the debug host.
