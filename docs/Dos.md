# Apple DOS 3.3 and 3.2

DOS 3.3 is the disk operating system Apple shipped for the Apple II from 1980 until ProDOS replaced it. It
lives on tracks 0 to 2 of every DOS 3.3 disk, and once booted it sits at the top of memory, between BASIC and
the Monitor, turning commands such as `CATALOG` and `LOAD HELLO` into reads and writes of the disk. This guide
explains how it starts, how it is put together and how it lays out a disk, and [DOS 3.2](#dos-32) covers the
earlier 13-sector release built from the same sources, for anyone reading or stepping through the SDK's sources
in [`Roms/Dos`](../src/Retrocore.Machines.Apple2/Roms/Dos). It assumes some
6502 assembly, and [DiskII.md](DiskII.md) for the hardware: nibbles, fields, and the controller's boot ROM.

## The sources

The source covers both DOS 3.3 releases on Apple's System Masters, chosen by `YEAR`: 1983 (the default), the
DOS on the 680-0210-A master, and 1980, the DOS on the 680-0051 masters. Its names and the order of its
modules are Apple's, from Apple's DOS 3.3 C source listing (July 1983); its comments are the SDK's own.
[`Dos33.asm`](../src/Retrocore.Machines.Apple2/Roms/Dos/Dos33.asm) includes the modules and builds
either of two images of each, chosen by `MASTER`:

| Build | Origin | What it is |
| --- | --- | --- |
| `MASTER = 1` (the default) | $1B00-$3FFF | The image on a System Master's tracks 0 to 2: the relocator at $1B00, then DOS assembled $8000 below where it runs. It is byte for byte that year's master's. |
| `MASTER = 0` | $9D00-$BFFF | DOS where it runs on a machine with 48K or more. The debugger maps the running DOS to this build's lines. |

`DosSourceTests` pins all four builds by SHA-256, so no disk is needed to check them. With the masters in
`iie-disks` under `RETROCORE_CACHE` (default `%USERPROFILE%\Retrocore\iie-disks`), it also compares each master
build with its disk byte for byte, and boots each master on a IIe built from the SDK to check that the DOS it
relocates debugs at the source's lines. The debugger maps both years' running builds.

Monitor and hardware addresses where DOS uses the SDK's shared names (`PROMPT`, `HOME`, `IORTS`) come from
[`IIeEquates.asm`](../src/Retrocore.Machines.Apple2/Roms/System/IIeEquates.asm) and
[`MonitorEntries.asm`](../src/Retrocore.Machines.Apple2/Roms/System/MonitorEntries.asm), included by
`Equates.asm`; addresses where DOS uses its own names (`OUTSW` for the output hook) live in `Equates.asm`.

The two years differ in Apple's 1982 "revision B" patches, which the 1980 DOS lacks. Apple's source already
has a switch for them, `DOS33B`: off, it builds the 1980 code exactly. The revision changes three things: how
APPEND finds the end of a file (`MOVEOF`, and `FIXIT2` at the end of the `EOFFIX` patch, which in the 1980
DOS returns straight to POSITION's call), a carry left set when the file manager computes a record's place in
a file (`LOCSEC`), and turning off the IIe's 80-column display after booting (`OFF80`). The 1983 DOS keeps the
extra code in a patch area after `MSWAIT`; the 1980 DOS has leftover bytes there instead.

Two details keep each image exact:

- **Leftover bytes.** Where DOS reserves storage, such as its VTOC and catalog buffers, a master holds whatever
  was in memory when it was written: parts of an old VTOC, catalog entries, the end of a previous program. The
  sources keep these bytes as data, marked "leftover", in place of the reserved space; where the two masters
  differ, small ones use the `LEFTOVER` macro (the 1983 byte, then the 1980 byte) and larger ones `.if`.
- **One patch differs from the listing.** The listing puts a patch, `FIXIT2`, in the boot loader's page; the
  680-0210-A master has a shorter version of it in the patch area after `MSWAIT` ($BA84). The sources follow
  the master.


## Where DOS runs

On a 48K or 64K Apple II, DOS occupies $9D00-$BFFF, and its file buffers sit just below it, so `HIMEM` is $9600
with the usual three buffers. Its modules, in memory order:

| Addresses | Part | Modules |
| --- | --- | --- |
| $9D00-$A883 | Command interpreter | `DosInit` (vectors, BASIC entry points, cold and warm start), `DosHook` (the input and output hooks), `CommandScan` (parsing a command line), `OpenClose`, `LoadSave`, `MiscCommands` (the commands), `DosGoer` (glue and error messages), `BuildFileTables` (the file buffers) |
| $A884-$AA4E | Command tables | `CommandTables`: command names, what each command accepts, options and error messages |
| $AA4F-$B5FD | File manager | `FileManagerEntry`, `FileOpenCloseReadWrite`, `FileDeleteCatalog`, `FileManagerIo`, `FileLocateNextByte`, `FileLocateSector`, `FileManagerData` |
| $B5FE-$B7FF | Boot loader | `BootLoader`: BOOT 1 (the boot sector) at $B600 and BOOT 2 at $B700, which loads the rest of DOS; also the code INIT uses to write DOS to a disk |
| $B800-$BFFF | RWTS | `RwtsEquates`, `PreNibble`, `WriteSector`, `PostNibbleRead`, `ReadAddressSeek`, `MsWait`, `WriteAddress`, `Rwts1`, `Rwts2`, `Formatter`, `DosPatches`: reading and writing sectors, seeking, and formatting |

DOS also puts a page of vectors at $03D0-$03FF, which programs use instead of DOS's own addresses, since those
move with the machine's memory:

| Address | Use |
| --- | --- |
| $03D0 | Warm start: reconnect DOS and return to BASIC, keeping the program |
| $03D3 | Cold start: reconnect DOS and restart BASIC |
| $03D6 | The file manager |
| $03D9 | RWTS |
| $03DC | Returns the file manager's parameter list's address in A and Y |
| $03E3 | Returns RWTS's parameter block (IOB) address in A and Y |
| $03EA | Reconnects DOS's input and output hooks |
| $03F2 | The reset vector, which DOS points at its own reset handler |

## How DOS starts

Booting is a chain of loaders, each loading the next:

1. **BOOT 0**, the Disk II's boot ROM, reads track 0 sector 0 into $0800 and runs it at $0801 with X = slot
   * 16 ([DiskII.md](DiskII.md) describes it).
2. **BOOT 1**, the boot sector, uses the ROM's own sector reader (at $Cn5C) to read track 0's sectors 9 down
   to 0 into ten pages that end at $3FFF on a master ($BFFF on a disk INIT wrote); the page to start from is a
   byte in the sector itself. Sector 0 is the boot sector, read again into its place in DOS, and the other
   nine hold BOOT 2 and RWTS. A table in the boot sector turns DOS's sector numbers into the ones written on
   the disk. Then it jumps to BOOT 2, at $3700 ($B700).
3. **BOOT 2** uses RWTS to read the rest of tracks 0 to 2 into memory below it, then jumps on: on a master, to
   the relocator; on a disk INIT wrote, to DOS's cold start.
4. **The relocator** (masters only) finds the top of RAM, moves DOS there and corrects every address in it,
   using tables of which ranges hold code and addresses. On a 48K or larger machine DOS ends at $BFFF.
5. **The cold start** connects DOS's hooks, sets up the file buffers, and runs the disk's HELLO program.

A master's image is the same DOS assembled at $1D00, and the relocator, at $1B00-$1CFF. Its sectors map to
memory like this:

| Sectors | Memory |
| --- | --- |
| Track 0, sectors 0-9 | $3600-$3FFF: the boot sector, then BOOT 2 and RWTS |
| Track 0 sector 10 to track 2 sector 4 | $1B00-$35FF: the relocator, then DOS from its start |
| The rest of track 2 | unused |

Sector 5 of track 0 is page $BB00, RWTS's 256-byte nibble buffer, written as zeros.

## How DOS sees commands

DOS has no command prompt of its own. It takes over the Monitor's character output and input hooks (`CSW`
and `KSW`, at $36 and $38), so every character BASIC prints or reads passes through it first. A command is a
line that starts with Control-D, printed by a program (`PRINT CHR$(4);"CATALOG"`), or a line typed at BASIC's
prompt that starts with a command name. `DosHook` follows the characters with a small state machine; when a
line is complete, `CommandScan` looks the command up in `CommandTables`, parses its file name and options,
and calls its handler, which calls the file manager.

The file manager takes requests in a parameter list (opcodes such as open, read, write, close, delete and
catalog), and calls RWTS with an I/O block (IOB) naming the slot, drive, track, sector, buffer and command.
Programs can use either layer through the vectors above.

## A DOS 3.3 disk

A disk has 35 tracks of 16 sectors, 256 bytes each: 140K. DOS numbers its sectors in an order that skips
around the track, so it can finish with one sector before the next passes under the head; disk images in DOS
order (`.dsk`, `.do`) store sectors in DOS's numbering.

| Where | What |
| --- | --- |
| Tracks 0-2 | DOS itself, as above |
| Track 17, sector 0 | The VTOC, "volume table of contents": the volume number, where the catalog starts, the disk's geometry, and a bit map of free sectors, four bytes per track |
| Track 17, sectors 15 down to 1 | The catalog: a chain of sectors, each with seven file entries |
| Everywhere else | Files |

A catalog entry gives a file's type (text, Integer BASIC, AppleSoft, binary, and a few rarer ones; the top bit
marks it locked), its name (30 characters), its length in sectors, and the track and sector of its
track/sector list. That list is a chain of sectors holding the track and sector of each of the file's data
sectors, 122 to a list sector.

## DOS 3.2

[`Dos32.asm`](../src/Retrocore.Machines.Apple2/Roms/Dos/Dos32.asm) builds DOS 3.2, the 13-sector DOS on its
System Master, from the same folder as DOS 3.3. There is no Apple listing of it: where its code is the same
routine as DOS 3.3's it has DOS 3.3's names, and the routines only 3.2 has (its 5-and-3 RWTS, its boot) have
names in the same style. It builds the same two images, `MASTER = 1`
byte for byte the master's tracks 0 to 2 and `MASTER = 0` DOS where it runs, both pinned by digest; the
debugger maps the running build.

The two versions share one copy of the relocator, the command interpreter, the file manager and RWTS's
equates and patches: each root sets `DOS32`, and the few places they differ are `.if DOS32` blocks.
`LEFTOVER` takes three bytes, one for each master (1983, 1980, then DOS 3.2). The boot loader and RWTS are
too different to share, so DOS 3.2 has its own, in the modules whose names end in `32` (`BootLoader32.asm`,
`Rwts32.asm` and so on).

The command interpreter and file manager are the 1980 DOS 3.3's, at the same addresses, apart from the disk's
geometry (13 sectors, the catalog in sectors 12 to 1) and three places DOS 3.3 later changed: the end of APPEND,
SAVE and BSAVE without DOS 3.3's verify, and DOSGO's handling of END OF DATA, which DOS 3.3's `EOFFIX` patch
changes. The rest differs:

- **Booting.** The 13-sector boot ROM decodes the boot sector only partly, in the order the nibbles arrive, so
  the code at $0300 is the sector's bytes rearranged: byte 5i + q, of 256, runs at $0300 + 51q + 50 - i. The
  source writes BOOT 1 as it runs, in a `.dum` at $0300, through macros that record each byte, and emits the
  sector in DOS's order. BOOT 1 reads track 0's sectors 0 to 9 with the ROM's reader and decodes them itself;
  BOOT 2 then reads the rest forwards from sector 10. A master's relocator is the same as DOS 3.3's.
- **Sectors on the disk.** DOS 3.2 has no interleave of its own: the numbers are those written on the disk,
  and INIT lays sectors down around the track in the order 0, 10, 7, 4, 1, 11, 8, 5, 2, 12, 9, 6, 3. A master's
  tracks hold the boot sector, BOOT 2 and RWTS in track 0 sectors 0-9 (at $3600-$3FFF), the relocator in
  sectors 10-11, and DOS from sector 12 to track 2 sector 10; a disk INIT writes starts DOS at sector 10.
- **RWTS** is an earlier form of DOS 3.3's: 5-and-3 nibbles, nine-bit sync bytes, a single recalibration, and
  a formatter that writes only address fields and leaves the first write of each sector to make its data field.

## Building disks

`DosDisk` in `Retrocore.Media` builds DOS disk images: `Dos33Tracks` and `Dos32Tracks` place a DOS memory image on
tracks 0 to 2 as INIT or a System Master does, and `Create` adds an initialized VTOC and catalog on track 17 and the
files, each with its track/sector list. `DosFile` makes files as DOS stores them: binary (address and length first),
AppleSoft and Integer BASIC (length first) and text. A 16-sector image comes out in DOS order (`.dsk`, `.do`),
which `SectorDiskConverter.Convert` turns into a disk; a 13-sector one in sector order (`.d13`), which
`SectorDiskConverter.ConvertThirteenSector` turns into 5-and-3 nibbles. `DosDiskTests` boots disks built both
ways, for both years, and runs a HELLO that BRUNs a binary.

Two front ends use it:

- **`tools/DosDisk`**, a command-line tool, assembles DOS from the sources beside it and writes a `.dsk`, `.do`
  or `.woz` image. Files come from a folder: `NAME.bas` is an AppleSoft listing it tokenizes, `NAME.txt` a text
  file, and `NAME#TTAAAA` a file named in CiderPress II's style, with its ProDOS type and auxiliary type (04
  text, FA Integer BASIC, FC AppleSoft, 06 binary at address AAAA). `--run NAME` writes a HELLO that runs it;
  `--master` writes the master's relocatable DOS; `--year 1980` the 1980 DOS.

  ```text
  dotnet run --project tools/DosDisk -- -o game.dsk -f game-files --run GAME
  ```

  `--dos 3.2` builds a DOS 3.2 disk instead, written as `.d13` or `.woz`.

- **The debugger's `dos` launch option** (`3.3` or `3.2`) builds a disk holding the launch's program and a HELLO that BRUNs it,
  and boots it, so the program runs, and debugs, under DOS.

## Oddities in the code

Documenting the source turned up a few things DOS does that its manuals don't say. Each is described where it
happens in the source:

- **Block writes write one byte more than asked.** The file manager writes a byte before it counts one off
  (`WNXBLK`, `DTBLN`), so a block write of n bytes writes n + 1, while a block read reads n. SAVE and BSAVE
  pass the full length, so every binary and BASIC file holds one byte more than its recorded length.
- **CATALOG shows sizes modulo 256.** `PRNUM` prints only the low byte of the sector count, so a file of 300
  sectors shows as 044.
- **INIT keeps part of the last VTOC.** `FFMT` rebuilds only the free-sector map, so a new disk's other VTOC
  fields come from the last VTOC DOS read, or from DOS's built-in copy if it read none.
- **Track 0 is never freed.** `FRESEC` and DELETE skip it; DOS keeps tracks 0 to 2 for itself anyway.
- **INIT doesn't check writing DOS.** `BOOTIO` returns the status of its last sector only, and the caller
  ignores even that, so a disk error while INIT writes tracks 0 to 2 goes unreported.
- **RWTS leaves a stray return code.** On success `ALLDONE` stores whatever is in A as the IOB's return code;
  only the carry says whether the call worked, which is what the file manager checks.
- **The relocator's walk depends on data's values.** The relocator steps through DOS's code instruction by
  instruction to find addresses, and a few data bytes lie inside those ranges. They happen to decode as
  instructions of the right lengths, so the walk stays in step.

## References

- Apple, *DOS 3.3 C source listing* (1983): the names and module structure;
  [PDF](https://elite.bbcelite.com/pdfs/apple2_SRC_DOS33C_1983.pdf).
- Don Worth and Pieter Lechner, *Beneath Apple DOS* (Quality Software, 1981): chapter 3 for the disk format,
  4 for the VTOC, catalog and track/sector lists, 6 for using RWTS and the file manager, and 8 for a map of
  DOS by address; [scan](https://archive.org/details/Beneath_Apple_DOS),
  [text](https://github.com/iKarith/beneath-apple-dos).
