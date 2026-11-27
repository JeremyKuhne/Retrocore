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
| The ProFile card's and the slot 7 block device's firmware (`Roms/ProFile.rom.asm`, `Roms/Slot7.rom.asm`) | Converted | [BlockDeviceFirmware.md](BlockDeviceFirmware.md) |
| The Disk II boot ROMs and sequencers (`Roms/DiskII/`), with the language card finder | Converted | [DiskII.md](DiskII.md) |
| The Apple II character generators (`Roms/System/CharacterGenerator.asm`) | Converted | [CharacterGenerator.md](CharacterGenerator.md) |
| The mouse card's firmware (`Roms/Mouse.rom.asm` and Apple's `Roms/Mouse/MouseInterface.asm`) | Converted | [Mouse.md](Mouse.md) |
| Integer BASIC, with the floating point, the Mini-Assembler and SWEET16 (`Roms/IntegerBasic/`) | Converted | [IntegerBasic.md](IntegerBasic.md) |
| Programmer's Aid #1 (`Roms/ProgrammersAid/`) | Converted | [ProgrammersAid.md](ProgrammersAid.md) |
| The 3.5 disk controller (`Roms/Disk35/`, Apple's EPROM, and the emulator's `Roms/Disk35.rom.asm`) | Converted | [Disk35.md](Disk35.md) |
| Apple III Business BASIC (`src/Retrocore.Machines.Apple3/Roms/BusinessBasic/`), as its own source (the shared Microsoft modules not used yet) | Converted | [BusinessBasic.md](BusinessBasic.md) |
| MBASIC 5.21 for CP/M (`src/Retrocore.Machines.Kaypro/Roms/Mbasic/`), with Microsoft's names and where each came from | Named, not converted | [Mbasic.md](Mbasic.md) |
| Apple Pascal 1.1's interpreter, SYSTEM.APPLE (`src/Retrocore.Pascal/Sdk/Interpreter/1.1/`) | Converted | [PascalInterpreter.md](PascalInterpreter.md), [renames](PascalInterpreterRenames.md) |
| Apple Pascal 1.3's Compiler, SYSTEM.COMPILER (`src/Retrocore.Pascal/Sdk/Compiler/apple2-1.3/`) | Converted | [PascalCompiler13.md](PascalCompiler13.md), [renames](PascalCompiler13Renames.md) |

Each decision has an ID, which commit messages and comments may cite.
