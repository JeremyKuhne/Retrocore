# Backlog: SOS sources

Status: **asked for 2026-11-12** ("Plan SOS sources, including all drivers, then implement"). All stages built
2026-11-12, awaiting review. [Sos.md](../Sos.md) is the user guide.

## Built

- **Stage 0:** `SosVolume`, `SosFileEntry`, `SosDriverFile` and `SosDriver` in `Retrocore.Media`; `SosVolumeTests`.
- **Stage 1:** `Sos/SosKernel.asm`, `SosOrg.asm` and 40 files in `Sos/Kernel`, byte-identical to SOS 1.3's
  `SOS.KERNEL`, documented in our own words; `SosSourceTests`. Where Apple's text listing is damaged, the source
  follows the shipped bytes: runs of spaces in strings had collapsed (the DIB names, messages, the date template),
  two chains between the loader's files were missing, a garbled `SOSQUIT` line is not in 1.3, and 1.3's version
  text reads `01-NOV-82`. Apple's assembler used absolute addressing for symbols other modules define and for the
  BFM's storage map; those operands carry `a:`. Reserved storage holds whatever was in memory when Apple built the
  file, spelled out as bytes.
- **Stage 2:** the debugger maps the kernel wherever its bytes are; `Test-Apple3Dap.mjs` stops in `ScMgr.asm`.
- **Stages 3 and 4:** all eight drivers, byte-identical in code, relocation table and comment, in
  `SosDriverSourceTests`. `.CONSOLE` builds 1.31 and, with `RELEASE_130`, 1.30 (they differ in how `VERIFY` sets
  the screen switches). `.PRINTER` is the serial printer driver 1.10, the version Apple's 1.30 listing revised.
  `.PROFILE`'s DIB has the slot SCP set. `.GRAFIX`, `.AUDIO` and `.SILENTYPE` have no listing; their names are ours.
  The parallel printer driver's listing has no binary on our disks to check it against, so it is not built.
- **Third-party code, at the user's request:** `.RAM`, D A DataSystems' RAM disk for Titan's III+IIe card from the
  Utilities disk (its AutoFormat routine is never called); Titan's own `.RAM` 1.00 by Harmony Systems
  (`Drivers/TitanRam`), from `RAMDISK.DRIVER` on Titan's startup disk, a Pascal code file that `SosDriverCodeFile`
  reads; and On Three's boot loader 2.2 (`ON_THREE`). Titan's driver moves only one page per block in multi-block
  requests, documented as found.
- **Searched for and not found online:** a disk with Apple's parallel printer driver (the Washington Apple Pi
  library lists it on its System Utilities Data side, but apple3.org's and Asimov's copy of that disk is another
  revision, without it), a RAM disk driver from Apple (the 1988 Apple III drivers list has none), and On Three's
  512K RAM disk driver 0.2.0.
- **Stage 5:** `SosDriverModules` reads the device manager's table, whose entries point at each DIB's name, and
  maps each driver's source where SOS put it; source breakpoints bind again when a driver appears.
  `Test-Apple3Dap.mjs` binds one in `.FMTD1` at the Utilities' menu.
- **Stage 6:** `Sos/SosBoot.asm`, Apple's loader 1.1 (Business BASIC 1.23's block 0) and the System Demo's copy
  (`SYSTEM_DEMO`). The SOS 1.3 Utilities disk's block 0 is On Three's 1985 revision, which is not built. The
  debugger maps the loader at `$A000`.

Found along the way:

- **An assembler fix:** padding with `.res` or `.org` to an address the counter is past only until forward
  references shrink to zero page (as before SYSGLOB, after the loader) failed on the first pass. Such a count now
  counts as zero until the layout is stable, and is reported only if it is still behind then (`AssemblerSpanTests`).
- **Apple's code, documented as found:** the loader's `NEXT_DIB` can leave overflow as it was; CLOSE(0) and
  FLUSH(0) can lose an error; `.GRAFIX`'s `D_READ` never sets the count read; `.SILENTYPE`'s argument table is one
  entry short, its last flag coming from the next routine's first byte.

SOS is the Apple III's operating system. The goal is SDK sources for it, as the Apple II has for DOS: the SOS 1.3
kernel and every Apple driver on Apple's disks, each assembling byte-identically to what is on those disks. The
debugger then shows source for SOS and its drivers wherever they run, the way it does for the boot ROM.

## What there is

**On Apple's disks** (`%USERPROFILE%\Retrocore\apple3-disks`):

| File | Disks | What it is |
| --- | --- | --- |
| `SOS.KERNEL`, 22,016 bytes | Business BASIC 1.23, System Utilities | SOS 1.3. The two disks' copies are identical. |
| `SOS.KERNEL` | System Demo | SOS 1.1. Not a goal; see Later. |
| `SOS.DRIVER` | each disk | The drivers that disk was configured with, each relocatable, with its relocation table. |

The drivers in those `SOS.DRIVER` files:

| Driver | Code bytes | Disks | Apple's source |
| --- | --- | --- | --- |
| `.CONSOLE` | 4,007 and 4,003 | Business BASIC; Utilities | Console Driver 1.31 |
| `.GRAFIX` | 4,513 | Business BASIC | none |
| `.SILENTYPE` | 3,756 | Business BASIC, Demo | none |
| `.PROFILE` | 1,981 | Utilities | ProFile Driver |
| `.RS232` | 1,887 | Business BASIC | RS-232 Driver 1.30 |
| `.FMTD1` | 1,127 | Utilities | Disk /// Formatter Driver |
| `.PRINTER` | 746 | Business BASIC, Demo | Parallel 1.31 or Serial 1.30 Printer Driver, to be matched |
| `.AUDIO` | 552 | Business BASIC, Demo | none |

The two `.CONSOLE` builds differ by 4 bytes, likely their configuration. The Utilities disk's `.RAM` is not
Apple's ("Enhanced RamDisk ... for 3+2E"), so it is out of scope. The Demo's `.CONSOLE`, `.GRAFIX` and `.RS232`
are older builds; see Later.

**Listings** (`%USERPROFILE%\Retrocore\docs\apple3`, hashes in its `README.txt`):

- `SOS13Src.txt`: the SOS 1.3 kernel: the loader, INIT, SYSGLOB, the block file manager, OPRMSG, IPL, UMGR, the
  Disk III driver (`.D1`-`.D4`), SYSERR, DEVMGR, SCMGR, FMGR, CFMGR, BUFMGR and MEMMGR. `SOSORG` gives each
  module's origin and load address.
- David T. Craig's listings of Apple's 1983 driver sources: console, formatter, ProFile, RS-232, and parallel and
  serial printer.
- The Service Reference Manual has the SOS bootstrap loader (blocks 0 and 1 of a SOS disk).

## Rules

As for the boot ROM and DOS:

- **Labels:** Apple's, from the listings. For the three drivers with no listing, we name things after what they
  do, using the SOS Device Driver Writer's Guide's names for the standard parts (DIBs, requests, `D_READ` and
  so on).
- **Comments:** our own, never Apple's. Each routine gets a `;;` block (summary, `In:`, `Out:`, `Keeps:` only
  where true).
- **Bytes:** every source assembles byte-identically to the disk's file. Where a listing differs from the
  shipped bytes, the bytes win and the source's header says where they differ.
- **Maintenance:** sources are hand-maintained once written.
- **Docs:** no local links ([archive.org](https://archive.org) or the original site), and docs say only that the
  sources are byte-identical, never how they were made.

## Layout

In the Apple III project, beside the boot ROM, shipped with the SDK's ROM sources:

```text
Roms/Sos/
  SosKernel.asm      the root: the SOS.KERNEL file, module by module at its load address
  SosEquates.asm     EQUATES and SYSGLOB's names, shared by the kernel's modules
  Kernel/*.asm       one file per Apple module (SosLoader, Init, SysGlob, BfmInit2, Bfm..., OprMsg, Ipl, UMgr,
                     Disk3, SysErr, DevMgr, ScMgr, FMgr, CfMgr, BufMgr, MemMgr)
  Drivers/*.asm      one file per driver, assembled at origin 0 as SOS.DRIVER stores it
  SosDriver.asm      shared driver definitions: the DIB, request codes, SOS calls drivers use
```

- **Kernel:** each module is a `.scope`, so names private to a module stay private, as Apple's separate assemblies
  were. Entry points other modules use are defined at the outer level. `.logicalorg` assembles each module for
  its run address at its place in the file.
- **Drivers:** a driver's source builds its code, which starts with its first DIB. The relocation table is
  derived by assembling at two origins and comparing, and must equal the one in `SOS.DRIVER`.

## Stages

Each stage ends with its tests passing.

### 0. Fixtures and reading SOS disks

- The six driver listings: downloaded with approval 2026-11-12, text extracted.
- A read-only SOS (ProDOS-format) volume reader in `Retrocore.Media`: the directory and its files, from a
  `.dsk` or `.po`. The tests use it to take `SOS.KERNEL` and `SOS.DRIVER` from Apple's disks, and it splits a
  driver file into its drivers (comment, code, relocation table).

### 1. The kernel

- `SosKernel.asm` and its modules, byte-identical to SOS 1.3's `SOS.KERNEL`.
- **Tests:**
  - a SHA-256 digest, with no files needed;
  - with the disks, a compare against the file that names the first byte that differs.
- Documentation lint (`SdkDocumentationTests`) covers the sources.

### 2. The kernel in the debugger

- SOS's modules map as source wherever memory holds their bytes. Most of the kernel sits in the system bank
  at fixed addresses; the loader and INIT map only while they are there.
- The `sos` breakpoints' calls name SCMGR's handler, and SOS's equates are available to watch expressions.
- `Test-Apple3Dap.mjs`: a breakpoint in the kernel's source stops during the Utilities' boot.

### 3. The drivers with Apple's listings

- `.CONSOLE` (both builds, by a configuration symbol), `.PROFILE`, `.FMTD1`, `.RS232` and `.PRINTER`.
- Each driver's code and relocation table must match its `SOS.DRIVER`.

### 4. The other drivers

- `.GRAFIX`, `.AUDIO` and `.SILENTYPE`, written from their bytes and the Driver Writer's Guide. Same tests as
  stage 3.

### 5. Drivers in the debugger

- SOS relocates each driver as it loads it, to a bank and address it chooses.
- After boot, the debug target reads SOS's device table, assembles each driver's source for the address its first
  DIB landed at, and maps it in that bank. Source lines apply only where the bytes match, as everywhere else.
- A breakpoint in `.CONSOLE`'s source stops when the Utilities read a key.

### 6. The bootstrap loader

- Blocks 0 and 1 of a SOS disk, from the Service Reference Manual's listing, byte-identical to Apple's disks.
- The debugger maps it at `$A000`, where the boot ROM loads it.

## Docs

`docs/Sos.md`: what SOS is, how the sources are laid out, how to build and debug them. `docs/Apple3.md` links to
it.

## Later

- SOS 1.1 and 1.2 kernels, and the older drivers on the Demo disk, as conditional builds.
- Building a `SOS.DRIVER` file from chosen drivers, as the System Configuration Program does.
- Business BASIC 1.3's source, which apple3.org also has (and which [Business BASIC debugging](Apple3.md#later)
  would use).
