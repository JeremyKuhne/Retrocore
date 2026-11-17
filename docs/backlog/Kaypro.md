# Backlog: the Kaypro II

Status: **first pass done 2026-11-16.** The Kaypro II runs CP/M 2.2 and MBASIC from disk images, from the SDK's
sources of its monitor ROM and character generator, with the CPU and BASIC threads, Retrocore Memory's banks, the
display, drives, the extension's and Desktop's machine entries, and MBASIC as a BASIC dialect
([Kaypro.md](../Kaypro.md)).

## Done

- `Retrocore.Machines.Kaypro`: the machine, banked memory, the system PIO, the SIO's keyboard channel (the shared
  `Z80Sio` gained a receive buffer), the FD1793 with its HALT-gated NMI, and the display.
- Raw Kaypro disk images (`KayproFormat`), read and saved, beside IMD and DMK.
- `Kaypro2.asm` and `Kaypro2CharacterGenerator.asm`, byte-identical to 81-149C and 81-146A.
- `Mbasic.asm`, byte-identical to MBASIC.COM 5.21, with Microsoft's names for its tables, variables, statement and
  function handlers, error entries and interpreter core.
- The MBASIC dialect: CRUNCH, LIST, variables, loops, tokenized files; checked against MBASIC itself.
- `--disassemble` takes `--cpu Z80` (and any CPU the catalog knows) and the hints' `"vectors": false`.
- `tools/Test-KayproDap.mjs` and `KayproTests`, `MbasicOracleTests`.

## Next

- **Name the rest of MBASIC.** About 280 called routines and their labels are still `L_` and their address, and about
  80 variables `D_`. [GW-BASIC's source](https://github.com/microsoft/GW-BASIC) names nearly all of them;
  its routines can be matched to MBASIC's by their calls and by Level2.asm's math package, which MBASIC shares. Then
  `;;` documentation for each routine, as the other ROM sources have.
- **CP/M's sources.** The system tracks of the Kaypro's CP/M 2.2 disk: the boot record, CCP, BDOS and Kaypro's BIOS,
  byte-identical, so a CP/M program's calls step into CP/M's source as an Apple II program's step into DOS 3.3's.
  `CpmBdos` call names for the Z80 call stack, as `SosCalls` names SOS's.
- **CP/M disks as a file system.** List, extract and add files on Kaypro disks (`--cpm`, like `--dos`), and the
  Drives view's file listing.
- **MBASIC's double precision.** FIN's scaling of a double by powers of ten, to the bit, and FOUT for LIST.
- **The rest of the hardware.** The keyboard's bell as sound; the serial port and printer as devices that save what
  they get; SIO and PIO interrupts, if any software uses them; the 81-232 ROM and the Kaypro 4's double-sided
  drives.
- **Performance.** The Kaypro runs through the Z80 core's general path; measure it with the Desktop's PGO workloads
  once a Kaypro workload exists.
