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
| `disks` | Images for .D1, the built-in drive, then the external .D2-.D4: DOS-order (`.dsk`, `.do`), ProDOS-order (`.po`) or WOZ. Disks load write-protected; **Unlock** in the Drives view lets the machine write one, in memory, and **Save** saves it. |
| `romDirectory` | MAME's `apple3` set (`apple3.rom`, `341-0028-a.rom`), or `RETROCORE_APPLE3_ROMS`. Without it the ROM comes from the SDK. |
| `fastDisk` | Runs flat out while a drive's motor turns (on by default). |
| `sound` | `speaker` (the default) or `off`. |
| `screen` | The monitor: `color` (the default), or a monochrome `white`, `green` or `amber` one, which shows each pixel in the phosphor's color by its brightness. The display panel's **Screen** changes it. |
| `proFiles` | ProFile cards, each `{ "slot": 4, "image": "profile.po" }` with slot 1-4 and an optional image ([The ProFile](#the-profile)). |
| `softCard3` | Microsoft's SoftCard /// in this slot, 1-4, for CP/M ([The SoftCard ///](#the-softcard-)). |

With no disk, the boot ROM runs its diagnostics and shows RETRY. Press a key to try again once a disk is in.

## Apple II emulation

Apple's Apple II Emulation disk turns the machine into a 48K, 1 MHz Apple II Plus. Boot it, then, at its menu, put
an Apple II disk such as DOS 3.3 in the built-in drive (the **Drives** view's drive 1) and press RETURN.

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
- **Slots.** Four, for ProFile interface cards ([The ProFile](#the-profile)) and the SoftCard /// ([The SoftCard
  ///](#the-softcard-)).

## The ProFile

Apple's ProFile is a 5 MB hard disk, cabled to a ProFile interface card in one of the four slots. SOS reaches it through
the `.PROFILE` driver in `SOS.DRIVER`; the System Utilities disk's copy is configured for slot 4, so a card there (the
launch's `proFiles`, or **Add Card** in the Machine view) with an image in its ProFile works once SOS boots
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
writing buffers at every alignment. Under SOS itself, `Apple3SosTests` boots the System Utilities with a card in slot 4:
they format the ProFile as `/HARD`, copy `SOS.KERNEL` onto it, whose bytes match the floppy's, and list it, and a second
boot lists the volume again from the ProFile.

## The SoftCard ///

Microsoft's SoftCard /// (1982) puts a Z80 on a slot card so the Apple III runs CP/M. The Z80 has no memory of its
own: it borrows the Apple III's bus by DMA, and the 6502 stops while it runs. The launch's `softCard3` puts it in a slot,
1 to 4, as **Add Card** in the Machine view does, and its CP/M Master disk boots from `disks` to "Apple SoftCard /// CP/M
56K Version 2.20" and `A>`.

The card follows MAME's `softcard3`, which its authors describe as a best guess from the boot disk and checks on real
hardware, and the installation manual
([archive.org](https://archive.org/details/apple-iii-soft-card-iii-installation-and-operation-manual)):

| Part | What it does |
| --- | --- |
| Clock | Twice the slots' 1.02 MHz. The boot code puts the III in 1 MHz mode before switching, so an Apple cycle holds two Z80 T-states, now and then three. |
| Mapping PROM | 256 bytes: the Apple address is the Z80's low byte plus the PROM entry for its high byte, times 256. The DMA goes into the 6502's view, so it follows the bank and zero-page registers. Z80 `$0000` is Apple `$2000`, the I/O page is at Z80 `$A000` and zero page at `$F000`. The SDK's [`SoftCard3Prom.asm`](../src/Retrocore.Machines.Apple3/Roms/SoftCard3Prom.asm), byte-identical to MAME's `softcard3.rom`, is the card's PROM. |
| Registers | At `$C080 + slot * 16`. A read returns `$50`, which the boot code looks for. Writing `$01` arms a Z80 reset for the next switch; writing `$10` lets the card answer reads of `$FFFC` and `$FFFD`. |
| Switching | A 6502 read of `$FFFC` hands the bus to the Z80 and starts a supervision timer; a read of `$FFFD` stops the timer. The Z80 hands the bus back with `OUT ($00),A`. If the timer fires first, the card hands it back anyway, so the 6502 can serve SOS. MAME's period, 5 Hz, is marked as unchecked. |
| Boot | Its own boot blocks, not SOS's. They load at `$A000`, look for the card from slot 4 down, load the SOS drivers named in `DRIVER.SOS`, and run CP/M's console, printer and disk I/O through those drivers on the 6502. |

No source says whether the card lets the waiting 6502 make a refresh read in each Z80 opcode fetch, as the Apple II's
SoftCard does, so it makes none; the Apple III's own video refreshes its RAM. Interrupts are not modelled, as MAME has
none.

The Z80 debugs as its own thread, **SoftCard /// Z80**, beside the 6502's: source breakpoints, stepping by line, the
call stack and its registers. `z80:` names memory as the Z80 sees it, through the PROM, so `z80:$0100` is the Apple's
`$2100` in the bank switched in, and a data breakpoint there watches the Z80's own accesses. A `.cpu Z80` source loads
at `z80:$0100` and starts there with the Z80 holding the bus; the supervision timer does not run, so it keeps the bus
until its `OUT ($00),A`. An instruction breakpoint at `z80:0x0000` stops CP/M's boot at the Z80's first instruction.

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

## Against MAME and the manual

The machine was checked against MAME's `apple3` driver and Apple's Service Reference Manual (1982), and follows the
manual where they differ.

- **Power-on.** `Apple3OracleTests` matches MAME's instruction trace, registers included, from power-on to the
  boot ROM's first disk access, through every diagnostic, except for the screen-blank bit the ROM reads at `$F60F`
  and then masks off, which the test leaves out. What the hardware leaves to chance follows MAME so the two
  run in step: RAM powers on as `$FF`, the beam starts at line 192, and the test takes MAME's power-on X, S and P.
  The comparison stops at the drive check, where MAME's empty drive returns nothing and ours reads noise, as a real
  drive does, so ours reaches RETRY a little later. MAME's tracer is unsafe here: a debugger read of zero page
  latches an X-byte in its driver, so the oracle script (`tools\Apple3Oracle.lua`) traces registers only.
- **Timing.** A line is 65 states of 1 MHz, 25 of them horizontal blanking, one stretched by 2 dots: 912 dots (MAME
  uses 910). A frame is 262 lines, 70 of them vertical blanking. The 2 MHz clock is MAME's measured 1.905 MHz, a
  little above the manual's 1.8 MHz maximum.
- **Banks.** The memory board's decode equations (the 128K board's RAS and CAS PROMs) make bank number 7, 15 with
  512K, bank 0 with the system RAM, from the bank register or an X-byte; MAME gives that view to X-byte `$8F` only,
  and SOS's `CNVRT.ADR` relies on it. An extended access to the last bank wraps its partner to bank 0. What 128K
  does with values 3-6 depends on which RAS PROM pairs with which board, which the manual does not say; here they
  wrap to banks 0-2. The X-byte's bank is four bits, as in MAME, for 512K; Apple's board has three lines.
- **Video.** The RETRY screen matches MAME pixel for pixel, but for the cursor. The mode bits follow the manual's
  truth table, and so do three places MAME differs: page 2 of 280-dot color swaps dots and colors, and page 2 of 560
  dots and of 140 colors is at `$6000`/`$8000`. 80-column text is white, where MAME draws it green. Our own choices:
  140-dot color uses the graphics palette (MAME, the text palette), flashing toggles every 16 frames, smooth
  scrolling moves graphics only, as in MAME, and a frame keeps each line's switches but reads memory when drawn.
- **Disks.** The disk sequencer steps with the CPU, two clocks to a 1 MHz cycle and one to a 2 MHz cycle; SOS
  writes at 1 MHz, and drift between the two clocks lost bits. While writing, a cell is exactly 8 sequencer
  clocks, on the Apple II too.
- **Keyboard.** A typed capital or shifted symbol holds SHIFT, since SOS makes lowercase itself, and queued keys
  come 20 ms apart, since SOS takes keys by interrupt.
- **Apple II mode.** The environment is `$FC` there: 1 MHz, I/O, video, NMI, write protection, the primary stack
  and no ROM. The screen scrolls one line after CONTROL-RESET, as a II Plus's does.

Not checked: SOS and mode-test frames against MAME, frames in Apple II mode, the Emulation disk's configuration
menu (its slot 5 and 7 serial cards), the paddles in Apple II mode, breakpoints and disassembly qualified by bank, and the call stack
across bank switches. Host game controllers are not wired to the joysticks, the equates name the hardware but not
SOS's entry points, and beam breakpoints are not available on the Apple III.

## Testing

- `Apple3BusTests` and `Apple3VideoTests` need no files.
- `Apple3RomSourceTests` pins the boot ROM source by SHA-256.
- `Apple3MachineTests`, `Apple3SosTests` and `Apple3EmulationTests` need MAME's `apple3` set
  (`RETROCORE_APPLE3_ROMS`, by default `<cache>\apple3-roms\mame\apple3`) and Apple's disks
  (`RETROCORE_APPLE3_DISKS`); the emulation test also needs the DOS 3.3 System Master in `<cache>\iie-disks`.
- `Apple3OracleTests` runs MAME (`RETROCORE_MAME`). Every archived MAME set (to 0.279) has an older dump of the
  boot ROM (CRC `55e8eec9`), read from a running machine, so `$FFC0-$FFEF` holds RAM; the chip's contents (CRC
  `1af7ec42`) have the copyright string there, which the SDK's source builds.
- `Apple3ProFileTests` needs no files: it runs Apple's `.PROFILE` driver from the SDK on the SDK's boot ROM.
- `SoftCard3Tests` needs no files but for its CP/M boot, which needs the SoftCard /// CP/M Master disk
  (`RETROCORE_SOFTCARD3`, by default `<cache>\softcard3`), and its PROM check, which needs MAME's `softcard3.rom` in
  that folder's `extract`. `SoftCard3OracleTests` runs MAME.
- `node tools/Test-Apple3Dap.mjs` drives the debug host, and `node tools/Test-SoftCard3Dap.mjs` the SoftCard ///'s
  Z80 thread, booting CP/M too when the master disk is there.
