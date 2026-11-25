# Conversion logs

What was decided for each source converted to the maintained style, and why: the precedents later conversions
follow. The method and the general rules are in [ConvertingSources.md](../ConvertingSources.md); the style itself
in [AssemblyStyle.md](../AssemblyStyle.md).

| Source | Status | Log |
| --- | --- | --- |
| The Apple II Monitor (`Roms/System/Monitor.asm` and `Monitor/`) | Converted | [Monitor.md](Monitor.md) |
| The IIe's shared equates (`Roms/System/IIeEquates.asm`) | Converted | [IIeEquates.md](IIeEquates.md) |
| The IIe internal firmware (`Roms/System/Firmware.*`) | Converted | [Firmware.md](Firmware.md) |
| Microsoft 6502 BASIC (`src/Retrocore.Basic/Roms/Microsoft6502Basic/MsBasic.*`, with AppleSoft's `src/Retrocore.Machines.Apple2/Roms/AppleSoft` and PET BASIC's `src/Retrocore.Machines.Commodore/Roms/Basic`) | In progress | [Basic.md](Basic.md) |
| DOS 3.3 and 3.2 (`Roms/Dos/`), with Boot13 and MasterCreate | Converted | [Dos.md](Dos.md) |
| The Disk II boot ROMs and sequencers (`Roms/DiskII/`), with the language card finder | Converted | [DiskII.md](DiskII.md) |
| The Apple II character generators (`Roms/System/CharacterGenerator.asm`) | Converted | [CharacterGenerator.md](CharacterGenerator.md) |
| The mouse card's firmware (`Roms/Mouse.rom.asm` and Apple's `Roms/Mouse/MouseInterface.asm`) | Converted | [Mouse.md](Mouse.md) |
| Integer BASIC, with the floating point, the Mini-Assembler and SWEET16 (`Roms/IntegerBasic/`) | Converted | [IntegerBasic.md](IntegerBasic.md) |

Each decision has an ID, which commit messages and comments may cite.
