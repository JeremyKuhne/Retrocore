# The Commodore VIC-20

Retrocore's VIC-20 is [`Vic20Machine`](../src/Retrocore.Machines.Commodore/Vic20/Vic20Machine.cs): a cycle-exact NMOS
6502 with the VIC-20's memory map, the VIC (the 6560 on NTSC, the 6561 on PAL) for its screen, sound and paddles, two
6522 VIAs, the keyboard and joystick, the Datasette, cartridges and RAM in the expansion port, and the serial bus with
1540 and 1541 drives. Its BASIC, kernal and character ROM are SDK sources that assemble byte-identically to the chips,
so it needs no dumps.

This guide covers what it emulates, its ROMs and their sources, and how to debug on it.
[The plan](backlog/Commodore.md) has what is still to come, with the 64 and the 128.

## The machine

| Area | Addresses | Emulated |
| --- | --- | --- |
| RAM | `$0000-$03FF`, `$1000-$1FFF` | The built-in 5 KB. Unexpanded, BASIC's program starts at `$1001` and the screen is at `$1E00`. |
| 3K expansion | `$0400-$0FFF` | RAM1-RAM3, as the VIC-1210 adds; BASIC then starts at `$0401`. |
| Blocks 1-3 | `$2000-$7FFF` | 8K each, as the VIC-1110 and VIC-1111 add. With block 1, BASIC starts at `$1201` and the screen moves to `$1000`. |
| Character ROM | `$8000-$8FFF` | 901460-03: the upper-case and graphics set and the lower-case set, each followed by its reversed copy. |
| VIC | `$9000-$900F` | Repeated to `$90FF`. |
| VIAs | `$9110`, `$9120` | Address bit 4 selects VIA 1, bit 5 VIA 2. |
| Colour RAM | `$9400-$97FF` | 1K of four bits, one nybble for each character of the screen. |
| Block 5 | `$A000-$BFFF` | Where cartridges go; BASIC does not use it as RAM. |
| BASIC | `$C000-$E47B` | BASIC 2, 901486-01, which runs on into the kernal's chip. |
| Kernal | `$E47C-$FFFF` | 901486-06 (NTSC) or -07 (PAL): the screen editor and keyboard, the serial bus, RS-232, the tape, the files and channels, start-up and the jump table. |

What nothing answers reads as the byte the VIC fetched last, as on the real machine.

**CPU.** The 6502 runs at the VIC's dot clock divided by four: 1,022,727 Hz on NTSC (the 14.318 MHz crystal divided
by 14) and about 1,108,404 Hz on PAL (4.434 MHz divided by 4). The VIC fetches in the half of each cycle the 6502 does not
use, so it never stops the processor.

**Video.** The 6560 draws 65 cycles by 261 lines, the 6561 71 by 312, four dots each cycle. The text window is its
registers' size, 22 columns by 23 rows at power-on, of 8 × 8 or 8 × 16 characters, from the character ROM or RAM,
with multicolour and reversed characters, the border and background, and MAME's palettes. The window's columns are
taken at each line and its rows at each frame, as MAME takes them. [`Vic6560`](../src/Retrocore.Core/Machines/Chips/Vic6560.cs)'s
remarks list where it still differs from MAME.

**Sound.** Three square-wave voices and noise, with MAME's periods and noise generator, mixed in stereo.

**Interrupts.** VIA 2's interrupt is the IRQ, its timer 1 the 60 Hz jiffy clock and keyboard scan. VIA 1's is the
NMI, so RESTORE interrupts through its CA1, and RUN/STOP with RESTORE warm starts the kernal.

**Keyboard and joystick.** The 64-key matrix on VIA 2's ports, RESTORE on VIA 1's CA1, and the joystick on VIA 1's
port A and VIA 2's PB7. The paddles are the VIC's.

**Tape.** The Datasette at the machine's clock: VIA 2's CA1 reads the tape, its PB3 writes, and VIA 1 senses the keys
and runs the motor. Tapes are TAP images (which save for the VIC-20, machine 1, at the video standard's clock), WAV
recordings, or a `.prg` made into the tape SAVE writes.

**Cartridges.** MAME's chip files, named for their address (`.a0`, `.20`, `.40`, `.60`, `.70`), a `.prg` at its
address, VICE `.crt` images, and plain images placed by their size. A chip smaller than its block repeats through it,
and a cartridge whose ROM at `$A004` reads `A0CBM` starts at power-on. Any RAM a cartridge brings is added.

**Drives.** 1541s and 1540s on the serial bus as devices 8 to 11, each with its own 6502, 2K of RAM, two VIAs and the
gate array that reads and writes GCR, running its own DOS from MAME's `c1541` or `c1540` set. Disks are D64 and G64
images, which save back. The reset line resets them with the computer.

## ROMs

| Source | Chip |
| --- | --- |
| [`Vic20/Basic.asm`](../src/Retrocore.Machines.Commodore/Roms/Vic20/Basic.asm) | BASIC 2, 901486-01, and BASIC's part of the kernal's chip, `$E000-$E47B`, over the shared Commodore and Microsoft modules the PET's BASICs use. |
| [`Vic20/Kernal.asm`](../src/Retrocore.Machines.Commodore/Roms/Vic20/Kernal.asm) | The kernal from `$E47C`: 901486-06, and with `PAL = 1` 901486-07. |
| [`Vic20/CharacterGenerator.asm`](../src/Retrocore.Machines.Commodore/Roms/Vic20/CharacterGenerator.asm) | 901460-03, over the PET's character source. |

`Vic20RomSourceTests` pins each build by digest and compares it with the dumps when they are present; their SHA-1s are
MAME's. [The conversion log](conversions/Vic20.md) and [the kernal's rename table](conversions/Vic20KernalRenames.md)
record how the sources were written. Dumps from `romDirectory` or `RETROCORE_VIC20_ROMS`, MAME's `vic20` and `vic20p`
chips, in the folder or its folder for the set, replace the sources' builds when given.

## Debugging

The VIC-20 is in the Run and Debug dropdown, and **Retrocore: Start Machine…** starts it with a program, a BASIC
file, a cartridge, a disk (in a 1541 as device 8) or a tape. Launch configurations take `"machine": "vic20"`:

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "VIC-20: hello",
    "machine": "vic20",
    "ramExpansion": "8k",
    "source": "${workspaceFolder}/hello.asm",
    "stopOnEntry": true
}
```

The ROMs run for `bootSeconds` (three seconds by default when something loads) to `READY.` before the program loads,
at `$1400` by default, so the kernal's routines are ready for `JSR $FFD2`. A `.prg` file loads as the kernal's LOAD
does: one at BASIC's start on some VIC-20 (`$0401`, `$1001` or `$1201`) is a BASIC program, which moves to this
machine's start, is linked again there, has its pointers set and is started by RUN (`run` false leaves it); any other
is machine code, which starts at its first byte or `entryAddress`.

The options are:

- `video`: `ntsc` (the default) or `pal`;
- `ramExpansion`: `none` (the default), `3k`, `8k`, `16k`, `24k` or `32k` (the 3K and 24K);
- `cartridge`: a file, or a list of a cartridge's chip files;
- `sound`: `speaker` (the default) or `off`;
- `cassette`: a `.tap`, `.wav` or `.prg` tape, put in with PLAY down; and `fastCassette` (on by default), which runs as
  fast as it can while the tape moves;
- `diskUnits`: the device numbers of drives on the serial bus, 8 to 11, such as `[8]`; `diskModel`: `1541` (the
  default) or `1540`; `disks`: `.d64` or `.g64` images for device 8's drive, then the next (without `diskUnits`, as
  many drives as they need, from 8); and `driveRomDirectory`, the drives' ROMs;
- `sdkRoms`: the folder of the ROM sources, such as the repository's, so breakpoints set there bind;
- `screen`: `color` (the default), `white`, `green` or `amber`;
- `speed`: `1` (the default) runs at the machine's clock, `2`, `4` or `8` that many times as fast, and `"max"` as fast
  as possible.

The panel's key bar has **Run/Stop** (Esc), **Restore**, **Stop+Restore**, **Clr**, **Home**, **C= Shift**, **f1** to
**f8**, and **Reset** (Ctrl+F12 or Ctrl+Break). Home is HOME, the arrows the cursor keys, Backspace DEL and Insert INST;
in the Desktop, F1 to F8 are f1 to f8. The VIC-20 has no reset key; Reset pulls the expansion port's reset line,
resetting the 6502, the VIAs and the drives and keeping RAM, and **Machine reset** stops at the kernal's first
instruction after it, where a cartridge that signs itself starts. **BRK** stops at a BRK, which the kernal takes to its
warm start. The debug host's key codes for the keys that type nothing are 256 (RESTORE), 257 (RUN/STOP and RESTORE)
and 258 (SHIFT and the Commodore key), each held for a tenth of a second.

The Drives view shows the Datasette with its keys, and each drive; `retro/media` takes the same requests by `device`
`cassette` or `disk8` to `disk11`. In the Machine view, **Add Card…** on a free **Device 8** to **Device 11** row
connects a 1541 or a 1540 there.

BASIC and the kernal each debug against their source when the machine runs that source's build for its video
standard, dumps included. BASIC's source covers its end in the kernal's chip.

**BASIC programs.** VIC-20 BASIC programs have the BASIC thread, the program document and `basic` launches, as the
PET's do; the [extension's README](../extension/README.md#basic-programs) describes them. The dialect is `petbasic`
(files named `*.petbasic.bas`, or with `REM retrocore petbasic`), read and written on the machine with the VIC-20's
BASIC 2: the PET's BASIC 2 with its page-zero pointers three bytes higher, from `TXTTAB` at `$2B`, and its program
wherever the expansion puts it. The BASIC thread follows NEWSTT and GONE, with every page-zero address from the running
BASIC's assembly. An error's message comes from BASIC's table of addresses, entry X for error X, which the kernal's
errors 1 to 9 share.

## Testing

| Test | Checks |
| --- | --- |
| `Vic6560Tests` | The VIC's registers and what it reads, on blank ROMs: the light pen reads 0, the VIC sees colour RAM, and the window takes its rows each frame and its columns each line. |
| `Vic20MachineTests` | The machine on the dumps: `READY.` from power-on, the kernal's screen and colours, a typed program, `POKE 36869` choosing the character set, RUN/STOP and RESTORE, the joystick, and a voice's tone. |
| `Vic20OracleTests` (Conformance) | The ROMs against MAME's `vic20` and `vic20p` from power-on, instruction by instruction, booting BASIC and cartridges. |
| `Vic20TapeTests` | The Datasette through the kernal's own tape routines, and the TAP images it writes at its clocks. |
| `Vic20CartridgeTests` | The cartridge images, and a sample of MAME's `vic1001_cart` list starting on the RAM they were sold for. |
| `Vic20DiskTests` | A 1541 or 1540 on the serial bus through the kernal's and the drive's own DOS. |
| `Vic20DiskOracleTests` (Conformance) | The 1541's and 1540's DOS against MAME's `c1541` and `c1540`. |
| `Cbm1541GateArrayTests` | The 1541's gate array on its own, with no disk and no ROMs. |
| `Vic20RomSourceTests` | Every chip's source by digest and against the dumps, the kernal's citations, and the machine booting from the SDK's builds on both standards. `BuildLinkTests` checks each build's links. |
| `Vic20DebugTargetTests` | The debug target on the SDK's ROMs: its launch options, the keys that type nothing, its BASIC's pointers, its errors and screen, and the Machine view. |
| [`tools/Test-Vic20BasicDap.mjs`](../tools/Test-Vic20BasicDap.mjs) | A BASIC file on the BASIC thread on NTSC and PAL, unexpanded and with 3K and 8K: stopping on entry, stepping, a GOSUB's frame, variables and the FOR loop, the program as text, an error, Step Into on SYS, and one hit for each statement though an interrupt returns to GONE. |
| [`tools/Test-Vic20Dap.mjs`](../tools/Test-Vic20Dap.mjs) | The debugger end to end: BASIC from the sources, breakpoints in BASIC's and the kernal's sources with the call stack, the colour picture, the reset stop, RUN/STOP and RESTORE, a program recorded on tape and saved as TAP, loaded back, a `.prg` on two expansions and a source launched, each expansion's free bytes, and PAL. With the 1541's ROMs, a blank disk on device 8 formatted, a program saved, the disk saved as D64 and listed, and a second drive added and removed. |

The ROM-source, debug-target and DAP tests need nothing external. The tests on the dumps, the tape, cartridge and disk
tests and the comparisons with MAME are inconclusive without MAME 0.264's sets, from the
[MAME ROM sets on archive.org](https://archive.org/download/mame-0.264-roms-non-merged/): `vic20.zip`, `vic20p.zip`,
`c1540.zip` and `c1541.zip`, and its `vic1001_cart`, `vic1001_cass` and `vic1001_flop` software lists.
