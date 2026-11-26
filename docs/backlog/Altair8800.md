# Backlog: the MITS Altair 8800

Status: **phases 1-4 built (2026-11-20)**; [the guide](../Altair8800.md) covers them. Phase 5 is next.
The first machine for the 8080 ([CPU backlog](I8080.md)), and the one that started personal computing: an S-100 bus, a front panel of switches
and lights, and boards for serial terminals, cassette and 8-inch disks.

## Why the Altair

- It is the 8080's defining machine, and Altair BASIC was Microsoft's first product.
- It is small: a CPU board, RAM and a serial board make a working machine, so the 8080 gets a debug target early,
  and each further board adds software that runs.
- Its software is well preserved: Altair BASIC (4K, 8K, Extended, Disk), CP/M 2.2 and many disk images, all of it
  run on SIMH's `altairz80`, which makes a good oracle.

## The hardware

| Part | What it is | Ports and addresses |
| --- | --- | --- |
| CPU | 8080A at 2 MHz (500 ns states) | |
| Memory | S-100 RAM boards, 1 to 64 KB | |
| Front panel | 16 address/data switches, status and address/data lights; STOP, RUN, SINGLE STEP, EXAMINE (NEXT), DEPOSIT (NEXT), RESET; the high 8 switches read as sense switches | `IN $FF` |
| 88-2SIO | Two MC6850 ACIAs: serial terminals. Most later software (BASIC 4.x and later, CP/M) uses it | `$10`-`$11`, `$12`-`$13` |
| 88-SIO | The original single serial board, with active-low status | `$00`-`$01` |
| 88-ACR | Audio cassette, an 88-SIO with a modem; how BASIC was first loaded | `$06`-`$07` |
| 88-DCDD | 8-inch disk controller and drives (77 tracks, 32 sectors of 137 bytes) | `$08`-`$0A` |
| 88-DBL / MBL | The disk boot loader and multi-boot loader PROMs | `$FF00`, `$FE00` |

The ACIA joins the shared chips in `Retrocore.Core` (`Machines/Chips`), as the 6821 and 6522 did.

## Software

Every program the Altair ran is copyrighted, so, as for the other machines, it is supplied by the user:

- **Altair BASIC** 4K, 8K and Extended, as binary images or paper tapes, loaded over the serial port or into
  memory directly. Its documented sense-switch settings choose the terminal board.
- **CP/M 2.2 and Altair Disk BASIC** on 8-inch disk images in SIMH's format (77 tracks of 32 137-byte sectors,
  337,568 bytes).
- **The boot PROMs** (88-DBL, MBL) become documented SDK sources rebuilt byte-identically to dumps the user
  supplies, as the other machines' ROMs did. Until then the disk boots through a loader the debugger deposits,
  as an operator keyed one in through the front panel.

## The debug target

- Launch id `altair`, with options for RAM, boards (`2sio`, `sio`, `acr`, `dcdd`) and the sense switches.
- The terminal as the machine's screen: an 80-column teletype-style console on the 2SIO's first port.
- Assembling `source`, loading a `program` binary at an address, and mounting disk images, as the other machines
  do.
- A call tracker for `CALL`, the conditional calls, `RST` and interrupts, checked against the stack as the Z80's
  is; the register view with the flags by name; `Keeps:` sections naming 8080 registers.
- The front panel as a VS Code view: its lights follow the address and data buses while the machine runs, and its
  switches examine and deposit memory.

## Phases

1. **The machine.** `Retrocore.Machines.Altair`: the 8080, RAM, the 88-2SIO with the MC6850, sense switches, and a
   front panel model (examine, deposit, run, stop, single step) with no UI. Tests run small 8080 programs through
   the serial port.
2. **The debug target.** Launching `altair`, the terminal, the call tracker and register view, `source` and
   `program` launches, and a DAP test script like the other machines'.
3. **BASIC.** Altair BASIC 4K and 8K from user-supplied images, over the 2SIO; the 88-SIO and 88-ACR for the
   versions that need them, with tape images. *Built:* the 88-SIO and the 88-ACR with a cassette recorder for
   byte-stream `.tap` tapes, and caps lock. Tests run 4K BASIC 3.2 and 4.0, 8K BASIC 4.0 and Extended BASIC 4.0
   against SIMH, and load MITS's own tapes through the front panel's bootstrap.
4. **Disks.** The 88-DCDD and its drives, SIMH disk images, the boot loaders as SDK sources, and CP/M 2.2.
   *Built:* the 88-DCDD with up to 16 FD-400 drives turning in real time, SIMH `.dsk` images that save back byte for
   byte, DBL 4.1 and MBL as PROMs from SDK sources, and launches with `disks` that boot through DBL. Tests boot
   CP/M 2.2b, Burcon CP/M, Disk BASIC 5.0 and Altair DOS, and write files under CP/M.
5. **The front panel view** in the extension.

## Testing

- The machine against SIMH's `altairz80` with the same keystroke-oracle approach the Model I and CoCo use.
- The ACIA against the MC6850 data sheet's status and interrupt behaviour.
- The boot PROMs pinned by digest. *Done:* `AltairDiskTests` check that DBL's and MBL's sources assemble to the
  PROMs' digests, and, with the dumps, byte for byte.
- A DAP script like the Model I's.

Every download (SIMH, software images, ROM dumps) is approved first, as before.

## Decisions (agreed 2026-11-13)

- **Project and launch id.** A new `Retrocore.Machines.Altair`, launch id `altair`.
- **Defaults.** 64 KB RAM, the 88-2SIO on `$10`, sense switches set for a 2SIO terminal. The MC6850 ACIA joins
  the shared chips in `Retrocore.Core`.
- **This round: phases 1 and 2**, so the 8080 runs and debugs in a machine. BASIC, disks and the front panel view
  stay in the backlog.
- **Oracle.** SIMH's `altairz80`, built locally outside the repository.
- **Software** is supplied by the user; the boot PROMs become SDK sources once dumps are available.

## Decisions for phase 3 (agreed 2026-11-13)

- **Images and tapes.** BASIC loads from memory images; the 88-SIO and the 88-ACR's cassette come with it, for the
  versions and tapes that need them.
- **Where the images came from.** The user pointed at
  [option8/Altair-BASIC](https://github.com/option8/Altair-BASIC) (4K BASIC 3.2's annotated listing) and asked for
  binary images. The tests use SIMH's `altsw.zip` from schorn.ch (4K BASIC 3.2 and 4.0, 8K BASIC 4.0 and Extended
  BASIC 4.0), and MITS's tapes from altairclone.com's "MITS Tapes" CP/M disk, which add 8K BASIC 3.2 and Extended
  BASIC 4.1. [avwohl/mbasic2025](https://github.com/avwohl/mbasic2025) has the same 4.0 images. option8's 3.2 image,
  a reassembly, differs from SIMH's in one byte, a self-modified port number BASIC sets before it is used. The
  images and tapes stay in the external test data's `altair-basic` folder, never in the repository, and the tests
  pin them by digest.
- **The terminal's board.** The terminal is on the 88-2SIO or the 88-SIO (the `console` option); the BASICs pick
  their terminal by the sense switches, as MITS documented.
- **The cassette.** The 88-ACR has no motor control, so a tape plays from the moment it goes in, a byte each
  300-baud character time; recordings save on eject, as the Apple-1's do.

## Decisions for phase 4 (agreed 2026-11-20)

- **Scope.** The 88-DCDD and 8-inch drives, the boot PROMs as SDK sources, and CP/M 2.2 booting and running.
  CP/M's own sources wait.
- **Timing.** The disk turns in real time, with the sector, byte, step and settle times Mike Douglas's FDC+
  firmware (1.8, `altair-8in.s`) gives the 88-DCDD. The Disk IO Timing paper agrees on the byte timing that MITS's
  read loops rely on; the 88-DCDD manual and the "New Controller Timing (1978)" notes are scans, and were not
  checked line by line. Software that polls the controller sees what it would on the
  board, such as DBL's two-bytes-a-pass loop.
- **PROMs.** DBL 4.1 follows Martin Eberhard's disassembly and MBL Geoff Harrison's; both assemble to the dumps
  deramp.com has as HEX files. HDBL, MDBL and DBL 3.3, which the user also approved downloading, are not built.
- **Software.** CP/M 2.2b, Burcon CP/M, Disk BASIC and Altair DOS images come from deramp.com and stay in the
  external test data's `altair-disk` folder, with the PROM dumps.
- **Launching.** A launch with `disks` fits the controller and DBL and starts at `$FF00`; the debug target has four
  drives.

## Still open

- **CP/M's sources**, the BIOS and boot sector, as SDK sources or documented disassemblies.
- **The 88-MDS Minidisk** (5.25-inch, 16 sectors of 137 bytes on 35 tracks), and HDBL, MDBL and DBL 3.3.
- **Sector interrupts.** The controller's interrupt at each sector's start is not modeled, as nothing here uses it.
- **DBL's loader** runs from RAM at `$2C00`, which the PROM's source map does not cover, so stepping it shows
  disassembly.
- **Index sync.** The FDC+ waits for the index pulse after a drive is selected before it shows sectors; here the
  sector position shows once the head is settled. Whether MITS's board waits too needs the manual.
- **A drive picture.** Retro Devices shows the drives as text; there is no 8-inch drive image.
- **The other disk images.** Disk BASIC 4.0, 4.1, 300-5-C and 300-5-F, Altair DOS 1.0 with Fortran, the 24K CP/M
  2.2b and Burcon's 48K CP/M were downloaded with the rest (approved 2026-11-20) but have not been booted. Disk
  BASIC 5.0 and Altair DOS are checked only as far as `MEMORY SIZE?`.
- **SIMH for the disks.** CP/M, Disk BASIC and Altair DOS boot on SIMH's `altairz80` too, but that was checked by
  hand; no test compares a disk session with SIMH, as the BASIC tests do.
- **Loading a tape with MBL.** `proms` fits MBL, but a launch starts at its program, at DBL's `$FF00` or at `$0000`; to
  load a tape, the program counter is set to `$FE00` in the debugger. A launch option to start at MBL would do it.
- **DBL and MBL in the maintained style.** Both sources were written before the conversion rules in
  [ConvertingSources.md](../ConvertingSources.md) and don't opt in to the strict style check; converting them would
  give them full names with the listings' names kept as historical names, as the Apple II sources have.
- **Trim erase and the head.** The FDC+ holds off a head unload until a write's trim erase ends; here the head
  unloads at once. Nothing here can tell the difference.
- **A missing PROM source.** A launch whose `sdkRoms` folder lacks the source of a PROM it fits, `Dbl.asm` or
  `Mbl.asm`, fails with a file-not-found error, while the source map skips a missing file. Whether a launch should
  fall back to the SDK's copy is open.
- **The 1975 source listing** on gatesnotes.com, which the user named: its host is allowed now, but its CDN answers
  automated downloads with "Access Denied", so it needs downloading by hand.
- **The 88-SIO's status bits** other than 0, 4 and 7 read 0 here; the board's manual would settle them.
- **The CP/M disk format**, for CP/M's sources. Reading the MITS Tapes disk worked out the layout CP/M uses on Altair
  8-inch disks in SIMH's 137-byte-sector images. Two system tracks, then 2 KB blocks, 16 records to a block, two
  blocks a track. Tracks 0-5 have the 128 data bytes at offset 3 of each sector, tracks 6-76 at offset 7. A track's
  logical record r is in the sector numbered h, where k = r mod 16 and h = 8(k mod 4) + 2(k div 4), plus 1 for r of 16
  or more. On tracks 0-5 that sector is image sector h; from track 6 it is image sector 17h mod 32, as the sector
  headers' numbers show. Every record of the twelve tapes on that disk passes its checksum this way, and Extended
  BASIC 4.0's tape rebuilds SIMH's `exbas.bin` byte for byte.
