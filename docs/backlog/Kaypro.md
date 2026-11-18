# Backlog: the Kaypro II

Status: **first pass done 2026-11-16.** The Kaypro II runs CP/M 2.2 from disk images, from the SDK's sources of its
monitor ROM and character generator, with the CPU thread, Retrocore Memory's banks, the display, drives, and the
extension's and Desktop's machine entries ([Kaypro.md](../Kaypro.md)).

## Done

- `Retrocore.Machines.Kaypro`: the machine, banked memory, the system PIO, the SIO's keyboard channel (the shared
  `Z80Sio` gained a receive buffer), the FD1793 with its HALT-gated NMI, and the display.
- Raw Kaypro disk images (`KayproFormat`), read and saved, beside IMD and DMK.
- `Kaypro2.asm` and `Kaypro2CharacterGenerator.asm`, byte-identical to 81-149C and 81-146A.
- `tools/Test-KayproDap.mjs` and `KayproTests`.

## Next

- **CP/M's sources.** The system tracks of the Kaypro's CP/M 2.2 disk: the boot record, CCP, BDOS and Kaypro's BIOS,
  byte-identical, so a CP/M program's calls step into CP/M's source as an Apple II program's step into DOS 3.3's.
  `CpmBdos` call names for the Z80 call stack, as `SosCalls` names SOS's.
- **CP/M disks as a file system.** List, extract and add files on Kaypro disks (`--cpm`, like `--dos`), and the
  Drives view's file listing.
- **MBASIC.** BASIC-80 5.21 from its disk: its source, byte-identical to MBASIC.COM, and the dialect with a BASIC
  thread, as Level II has.
- **The rest of the hardware.** The keyboard's bell as sound; the serial port and printer as devices that save what
  they get; SIO and PIO interrupts, if any software uses them; the 81-232 ROM and the Kaypro 4's double-sided
  drives.
- **Performance.** The Kaypro runs through the Z80 core's general path; measure it with the Desktop's PGO workloads
  once a Kaypro workload exists.
