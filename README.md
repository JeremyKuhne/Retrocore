# Retrocore

Retrocore emulates and debugs 8-bit computers in one .NET codebase: cycle-exact CPUs, the machines and
peripherals built around them, a multi-dialect assembler and disassembler, BASIC language and program tools, a
source-level debugger for assembly and BASIC, and a VS Code extension.

Every ROM the machines run but the TRS-80 Model 100's is also maintained here as documented assembly sources that
rebuild byte-identically to the original chips wherever a good dump of the chip is known. No external ROM dumps are
needed to run or debug the other machines, and you can step from your own code straight into the ROM or DOS source.
The Model 100 runs the ROM you supply until its source is written.

| Machine | CPU | ROMs (SDK sources, or dumps you supply) | Media and peripherals |
| --- | --- | --- | --- |
| Apple-1 | MOS 6502 | Woz Monitor, Apple Cassette Interface PROM, Signetics 2513 character generator; Apple-1 BASIC, which loads into RAM | 4 or 8 KB RAM, or 16 or 32 KB of expansion RAM, plus the `$E000` bank, 6821 PIA keyboard and 60-characters-a-second video terminal, Apple Cassette Interface (WAV tapes, play and record) |
| Apple II and II Plus | MOS 6502 | Integer BASIC (II), AppleSoft (II Plus), original or Autostart Monitor, character generator, Programmer's Aid #1 | Disk II 16- and 13-sector (WOZ, DSK, DO, PO, D13), fresh DOS 3.3 and 3.2 disks, slot-7 ProDOS block storage, slot-0 language or firmware card, speaker and slot-4 stereo Mockingboard, AppleMouse II-compatible mouse card, Apple II 3.5 Disk Controller-compatible SmartPort with two SuperDrives (400K/800K, 720K/1.44 MB), ProFile hard disk cards (PO, HDV), SDL3 game controllers |
| Apple IIe, original and enhanced | MOS 6502 / Rockwell 65C02 | Monitor, internal `$C100`–`$CFFF` firmware, AppleSoft, video ROM (with MouseText on enhanced) | Built-in language card and extended 80-column card (64 KB auxiliary RAM), plus the same Disk II, ProDOS block storage, audio, and controller support as the II |
| Apple III | Synertek 6502A | Boot ROM (diagnostics, monitor and SOS boot) | 128, 256 or 512 KB banked RAM with extended addressing, all native video modes with character RAM, built-in and three external drives (WOZ, DSK, DO, PO), speaker and 6-bit DAC, ProFile hard disk cards with pseudo-DMA (PO, HDV), SOS 1.3 |
| TRS-80 Model I, Level II and Level I | Z80 | Level II 1.2 and 1.3, Level I, MCM6670P character generator; plus the Radio Shack lowercase kit's font (from source; no chip dump is known) | CAS tapes (play and record), Expansion Interface (up to 48 KB RAM, 40 Hz clock, FD1771 with Percom/Radio Shack double-density doubler), JV1 and JV3 disks, lowercase modification |
| TRS-80 Model III, 4 and 4P | Z80 | The Model III's ROM (ROM C revisions B and C) and its Level I ROM, the Model 4's, the 4P's boot ROM, and their character generators | 16-128 KB with the Model 4's memory maps and banking, 64x16 and 80x24 video, FD1793 with wait states and NMIs, JV1, JV3, DMK and IMD disks, CAS tapes at 500 and 1500 baud; boots TRSDOS, LDOS and LS-DOS |
| TRS-80 Model II, 12 and 16 (Z80 side) | Z80 | Versions 1, 2, 3 and 5 of the boot ROM (five ROMs, as version 3 has two; version 4 has no known good dump) and the character generator | 32-512 KB banked RAM, MC6845 80x24 video, Z80 CTC, PIO, SIO and DMA with mode 2 interrupts, FD1791 with 8-inch IMD, DMK and JV3 disks |
| TRS-80 Color Computer 1, 2 and 3 | Motorola 6809E | Color BASIC 1.0-1.3, Extended Color BASIC 1.0 and 1.1, Disk Extended Color BASIC 1.0 and 1.1, and the CoCo 3's Extended Color BASIC 2.0 with Super Extended BASIC | SAM and MC6847/MC6847T1 VDG with artifact colors, the CoCo 3's GIME (MMU, 128 or 512 KB, palette, timer, 40/80 columns), CAS tapes, sound, joysticks, ROM packs, the disk controller cartridge with JVC disks |
| BBC Micro Model B and Model A | MOS 6502 at 2 MHz | MOS 1.20, BBC BASIC II, DNFS 1.20 and the SAA5050's characters | 6845 and video ULA in modes 0-6, SAA5050 teletext in mode 7, SN76489 sound, UEF tapes (play and record) and `.inf` files, the Intel 8271 with SSD and DSD disks, the analogue port |
| Commodore PET 2001 and 4032 | MOS 6502 | BASIC 1 and 4 (original and revised) and BASIC 2, their screen editors (BASIC 4's for the graphics and business keyboards) and kernals, with the machine-language monitor, and the 901447-08 and -10 character ROMs | 4-32 KB RAM, two 6520 PIAs and a 6522 VIA, 40x25 video with the 2001's timing and snow, the chiclet, graphics and business keyboards, CB2 sound, two Datasettes (TAP, WAV and PRG tapes, play and record), the IEEE-488 bus with 4040 and 2040 dual drives as devices 8-15 (D64, D67 and G64 disks, which save) |
| Atari 400 and 800 | MOS 6502 | OS rev. A and B and the PAL OS, the floating point package, Atari BASIC rev. A, B and C, and the 810's firmware | ANTIC and GTIA (or CTIA) with every display mode, players and missiles, POKEY's sound, keyboard and timers, joysticks, 8-48 KB, both cartridge slots with bank-switched cartridges, the 410 recorder (CAS), 810 disk drives at the hardware level (ATR, XFD), and `.xex` files |
| TRS-80 Model 100 and Tandy 102 | OKI 80C85 | None of their own; your ROM runs | 8-32 KB RAM kept between sessions in a RAM image, the 240x64 LCD's ten HD44102 drivers, the keyboard matrix, the uPD1990AC clock on RST 7.5, the 81C55, the option ROM socket and the power-off bit; boots the menu and runs BASIC from your ROM |
| MITS Altair 8800 | Intel 8080 | None of its own; DBL and MBL PROMs from SDK sources | 1-64 KB RAM, the 88-2SIO's MC6850 ACIAs or the 88-SIO with an 80x24 ADM-3A-style terminal, the 88-ACR cassette, sense switches, the front panel's EXAMINE and DEPOSIT, the 88-DCDD with 8-inch drives and the DBL and MBL boot PROMs; runs Altair BASIC and CP/M 2.2 from your images |
| Kaypro II | Z80 | Monitor ROM 81-149C and its character generator; MBASIC 5.21 too, which loads from disk | 64 KB RAM under the banked ROM and 4 KB of video RAM, 80x24 text, serial keyboard, FD1793 with two drives (raw IMG, IMD and DMK disks), Z80 SIO and PIOs; runs CP/M 2.2 and MBASIC from your disks |

The Disk II controller's boot and state-sequencer ROMs, Apple DOS 3.3 and 3.2, and the firmware of the emulated
slot-7 ProDOS block device, mouse card and ProFile card are documented SDK sources too. See the
[Apple-1](docs/Apple1.md), [Apple II family](docs/Apple2.md), [Apple III](docs/Apple3.md),
[TRS-80 Model I](docs/Trs80ModelI.md), [Model III, 4 and II](docs/Trs80Model3And2.md), [Model 100](docs/Trs80Model100.md),
[Color Computer](docs/Coco.md), [PET](docs/Pet.md), [BBC Micro](docs/BbcMicro.md), [Atari 400 and 800](docs/Atari800.md), [Altair 8800](docs/Altair8800.md) and [Kaypro II](docs/Kaypro.md) guides for hardware details and launch options. On the Color Computer, Color, Extended and Disk BASIC and the CoCo 3's ROM are all SDK sources, so every
model runs with nothing external, and so are all of the PET's ROMs, the BBC Micro's MOS, BASIC, DFS and character ROM, and the Atari's OS,
floating point package, Atari BASIC and 810 firmware.

> **Not published yet.** Retrocore has no public release on the VS Code Marketplace, Open VSX, or NuGet. To use
> the VS Code extension, build and install the VSIX from this repository as shown below.

## Installing the VS Code extension

Prerequisites:

- the [.NET 11 SDK](https://dotnet.microsoft.com/download/dotnet/11.0);
- [Node.js](https://nodejs.org) with npm, to compile and package the extension;
- [VS Code](https://code.visualstudio.com) 1.140 or later, with its `code` command on `PATH`;
- PowerShell 7 (the install script is tested on Windows only).

From the repository root:

```powershell
.\tools\Install-Extension.ps1
```

The script:

1. runs `npm ci` in `extension` (when `node_modules` is not present yet) and compiles the extension;
2. publishes `Retrocore.Debug`—the combined debug adapter, language server, and CLI host—into the package;
3. writes `artifacts\vsix\retrocore-<version>.vsix` and installs it in VS Code.

Reload your VS Code windows afterwards. Run the script again whenever you want to update the installed copy.

To build only the VSIX (for example, to install on another machine):

```powershell
.\tools\Install-Extension.ps1 -PackageOnly
```

Copy the `.vsix` file over and install it with **Extensions: Install from VSIX...** in the Command Palette, or
run `code --install-extension retrocore-<version>.vsix`. The packaged host is framework-dependent, so that
machine needs the [.NET 11 runtime](https://dotnet.microsoft.com/download/dotnet/11.0), but it does not need the
.NET SDK, Node.js, or any ROM dumps. To run the in-repo extension directly in a separate development
window while working on it, see [Installing and self-hosting](extension/README.md#installing-and-self-hosting).

Runtime libraries target .NET 10 and .NET 11; applications, tools, and tests target .NET 11 only. All projects
use C# 15, with the build-only Roslyn generator kept on .NET Standard 2.0. Release Native AOT publishing favors
speed over size. Native x64 binaries require an x86-64-v3 (AVX2-class) CPU; ARM64 keeps its own instruction
baseline. Set `IlcInstructionSet` explicitly when publishing for a different CPU baseline.

The Windows x64 Desktop AOT publish also uses its checked-in instrumented Apple IIe profile. Set
`-p:RetrocorePgoProfile=` to measure without it, or set that property to an absolute `.mibc` path to use a
different profile. Other runtime identifiers do not implicitly consume this Windows profile. To refresh it
after changes to hot code (Windows, .NET 11, PowerShell 7, Git, and `dotnet-trace` required):

```powershell
.\tools\Build-PgoTool.ps1
.\tools\Update-DesktopPgoCorpus.ps1 -PgoTool .\artifacts\pgo-tool\bin\dotnet-pgo.exe -OutputDirectory .\artifacts\pgo-training-new
```

The converter is built from pinned official runtime sources. Training generates fresh SDK DOS disks for
math/string, graphics, and active stereo Mockingboard workloads, runs the JIT application with instrumented
PGO, and validates nonempty edge/block counts before replacing the profile. The adjacent JSON records
provenance. `Update-DesktopPgo.ps1` can also train one custom disk independently. Recheck normal-speed behavior
before accepting a refreshed profile; training throughput alone is not the acceptance test.

## Assembly language

The assembler reads four dialects:

- **native**: Retrocore's own syntax for every supported CPU, specified in
  [the native assembly reference](docs/NativeAssembly.md);
- **ca65**, including macros, `.struct`/`.enum`/`.define`, and single-object `ld65`-style linking
  ([details](extension/README.md#ca65-and-single-object-ld65-support));
- **Merlin** 8/Pro and Merlin 32 ([details](extension/README.md#merlin-8pro-source));
- **MACRO-10**, covering the PDP-10 macro subset used by Microsoft's 6502 BASIC source, plus SHA-256-pinned
  source overlays such as AppleSoft's
  [`applesoft.mac`](src/Retrocore.Machines.Apple2/Roms/AppleSoft/applesoft.mac)
  ([details](extension/README.md#macro-10-source-microsoft-basic)).

`;;` comments document routines, constants, structures, and tables in any dialect. The language server renders
them in hovers and completions and checks their links and register lists; the debugger shows routine parameters in
the Variables view and verifies `Keeps:` and `Uses:` contracts when calls return; and the source generator copies
summaries into generated C# XML documentation ([DocComments.md](docs/DocComments.md)). A definition's `Also:`
section keeps the names manuals and listings gave it, so code written with them still assembles and the editor
offers the current name. Sources maintained by hand follow [the assembly style guide](docs/AssemblyStyle.md),
which the SDK's ROM sources are being converted to, for developers new to the old machines, with the old names
kept as a bridge to the original documents; the SDK's Pascal sources follow
[the Pascal style guide](docs/PascalStyle.md) in the same spirit. [ConvertingSources.md](docs/ConvertingSources.md)
is why and how, and
[the conversion logs](docs/conversions/README.md) record what was decided for each source converted.

In VS Code, assembly files get syntax highlighting, live diagnostics as you type, go to definition, find all
references, hovers (instruction summaries, flags, addressing modes, cycle counts, and emitted bytes),
completions, document outlines, and workspace symbol search across your code and the SDK ROMs
([Language features](extension/README.md#language-features)).

## BASIC

Retrocore supports **AppleSoft BASIC**, **Integer BASIC**, and **TRS-80 Level II and Level I BASIC**. **MBASIC**
(Microsoft BASIC-80 5.21, the Kaypro II's CP/M BASIC) has `.mbasic.bas` source files with the same editing support:

- **Source files with optional labels.** `.applesoft.bas`, `.integer.bas`, `.level2.bas`, `.level1.bas`, `.mbasic.bas`, and `.bas` files can
  omit line numbers, indent freely, and jump to `label:` or `@label` targets. They get dialect-accurate
  highlighting (finding reserved words inside identifiers where the ROMs do), diagnostics, keyword and variable
  hovers, go to definition, find all references, completions, outlines, and line renumbering.
- **Tokenized files and tapes.** **Retrocore: Open as BASIC Listing** opens tokenized programs (including
  CiderPress2 `#fc` and `#fa` files) and Model I `.cas` tapes as text and writes them back on save.
- **Live machine editing.** While a machine is running, **Retrocore: Open BASIC Program** edits the program
  currently in RAM as text, tracks `LOAD`, `CLOAD`, or lines typed on the emulated screen, and tokenizes changes
  back into memory on save ([BASIC programs](extension/README.md#basic-programs)).

## Debugging

Every machine appears in VS Code's **Run and Debug** dropdown, and **Retrocore: Start Machine…** starts one bare
or with an assembly source, binary, BASIC file, disk image, or tape—with no `launch.json` required
([Starting a machine](extension/README.md#starting-a-machine)). In `launch.json`, a configuration names a machine
(such as `"apple2"`, `"trs80-model1"`, `"trs80-model3"` or `"trs80-model2"`) and can boot the machine on its own, assemble `source` (directly into RAM or
onto a fresh bootable DOS 3.3 or 3.2 disk), load a `program` binary (with optional cc65 `.dbg` or VICE labels),
run a `basic` file, or mount media.

The debugger supports:

- **Breakpoints:** source, function, instruction, data (memory or Z80 I/O port reads/writes, or BASIC variable
  changes), Apple II video-beam scanline positions, and exception stops (reset, `BRK`, broken `Keeps:`
  contracts, and BASIC start/errors/end), with conditions, hit-count conditions, log messages, and live hit
  counts ([Breakpoints.md](docs/Breakpoints.md));
- **CPU and macro stepping:** source-level and instruction-level stepping (in the Disassembly view), inline macro
  frames that step into, over, and out of nested expansions, call stacks, and registers;
- **Statement-level BASIC debugging:** a **BASIC** thread alongside the CPU thread for AppleSoft, Integer BASIC,
  and Level II BASIC, with `GOSUB` call stacks, Variables/Arrays/Loops inspection and editing, BASIC expression
  watches, Jump to Cursor, and Step Into from `CALL`, `USR`, or `&` straight into machine code;
- **Apple Pascal debugging:** a **Pascal** thread for Apple Pascal on the Apple II and Apple III Pascal, with the
  p-machine's procedures as its call stack, breakpoints and steps by source line through the compiler's listing,
  named variables, and `pascal` breakpoints on p-code, and a decompiler that turns a code file back into Pascal that
  Apple's Compiler compiles to the same p-code ([Pascal.md](docs/Pascal.md));
- **Live memory views:** side-effect-free inspection and editing in Retrocore Memory, with go to, find and an
  inspector, RAM search, snapshots and frozen bytes, kept current while the machine runs, with Apple II language-card banks, firmware/slot ROMs, and IIe auxiliary
  RAM addressable directly regardless of active soft switches ([Memory.md](docs/Memory.md));
- **Cycle counts and contracts:** each source line's CPU cycles, each call's total cycles (`JSR`, `CALL`, `RST`),
  and runtime checks of documented `;; Keeps:` contracts;
- **Display and hardware controls:** a live display panel with paused video-beam overlay, 1x–8x and unthrottled
  (`Max`) speed, automatic fast disk and fast tape while drive motors run, speaker and stereo Mockingboard audio,
  and the **Retrocore** activity bar's Machine and Drives views for hot-plugging Apple II slot cards and managing disks and tapes
  ([Devices.md](docs/Devices.md)).

Your program and the SDK's ROM and DOS sources debug together in the same session. Each source module is bound to
its memory bank and active only while memory still holds the bytes it assembled to, so banked RAM or overwritten
code never shows stale source lines. The [extension README](extension/README.md) covers all launch options; the
[Apple II](docs/Apple2.md), [Model I](docs/Trs80ModelI.md), [Color Computer](docs/Coco.md),
[BBC Micro](docs/BbcMicro.md) and [Atari](docs/Atari800.md) guides cover each machine.

## SDK ROM sources

| Source | Covers |
| --- | --- |
| [`Monitor.asm`](src/Retrocore.Machines.Apple2/Roms/System/Monitor.asm) | The Apple II Monitor, `$F800`–`$FFFF`: the II's original Monitor, the II and II Plus's Autostart Monitor, and both IIe models' Monitors. |
| [`Firmware.Original.asm`](src/Retrocore.Machines.Apple2/Roms/System/Firmware.Original.asm), [`Firmware.Enhanced.asm`](src/Retrocore.Machines.Apple2/Roms/System/Firmware.Enhanced.asm) | The IIe's internal `$C100`–`$CFFF` firmware, sharing [`FirmwareEquates.asm`](src/Retrocore.Machines.Apple2/Roms/System/FirmwareEquates.asm). |
| [`IIeEquates.asm`](src/Retrocore.Machines.Apple2/Roms/System/IIeEquates.asm), [`MonitorEntries.asm`](src/Retrocore.Machines.Apple2/Roms/System/MonitorEntries.asm) | Shared IIe page-zero locations, soft switches, and key codes (`IIeEquates.asm`, included by the Monitor too) and Monitor entry points (`MonitorEntries.asm`), included by the firmware, Disk II boot ROMs, and DOS. |
| [`Boot16.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Boot16.asm), [`Sequencer16.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer16.asm), [`Boot13.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Boot13.asm), [`Sequencer13.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer13.asm) | The Disk II controller's 16- and 13-sector boot ROMs and logic state sequencers, sharing [`Boot.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Boot.asm) and [`Sequencer.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer.asm); see [DiskII.md](docs/DiskII.md). |
| [`AppleSoft.asm`](src/Retrocore.Machines.Apple2/Roms/AppleSoft/AppleSoft.asm), [`applesoft.mac`](src/Retrocore.Machines.Apple2/Roms/AppleSoft/applesoft.mac) | AppleSoft II for the II Plus and IIe, as native source or a MACRO-10 overlay over Microsoft's [`m6502.asm`](src/Retrocore.Basic/Roms/Microsoft6502Basic/m6502.asm). |
| [`IntegerBasic.asm`](src/Retrocore.Machines.Apple2/Roms/IntegerBasic/IntegerBasic.asm) | The Apple II's Integer BASIC ROM, `$E000`–`$F7FF`, including its floating-point package, Mini-Assembler, and SWEET16. |
| [`ProgrammersAid.asm`](src/Retrocore.Machines.Apple2/Roms/ProgrammersAid/ProgrammersAid.asm) | Programmer's Aid #1, the II's `$D000`–`$D7FF` ROM of Integer BASIC utilities. |
| [`CharacterGenerator.asm`](src/Retrocore.Machines.Apple2/Roms/System/CharacterGenerator.asm) | The IIe's video ROM (both models, including MouseText) and the II and II Plus's character generator. |
| [`Dos33.asm`](src/Retrocore.Machines.Apple2/Roms/Dos/Dos33.asm), [`Dos32.asm`](src/Retrocore.Machines.Apple2/Roms/Dos/Dos32.asm) | Apple DOS 3.3 (1983 and 1980) and DOS 3.2: both the System Masters' tracks 0–2 and DOS relocated at `$9D00`; see [Dos.md](docs/Dos.md). |
| [`Slot7.rom.asm`](src/Retrocore.Machines.Apple2/Roms/Slot7.rom.asm) | The emulated slot-7 ProDOS block device's 256-byte boot and driver ROM, `$C700`–`$C7FF`. |
| [`Disk35.rom.asm`](src/Retrocore.Machines.Apple2/Roms/Disk35.rom.asm) | The emulated 3.5 disk controller's 256-byte slot ROM: Apple's card's identification and entry points, handing each SmartPort and ProDOS call to the emulator. |
| [`Disk35Controller.asm`](src/Retrocore.Machines.Apple2/Roms/Disk35/Disk35Controller.asm) | Apple's Apple II 3.5 Disk Controller Card EPROM (341-0438-A): the host's slot page and SmartPort code, the diagnostics, and the card's own 65C02 firmware that drives the SWIM. |
| [`ProFile.rom.asm`](src/Retrocore.Machines.Apple2/Roms/ProFile.rom.asm) | The emulated Apple II ProFile card's 256-byte ProDOS boot and driver ROM, which drives the ProFile's handshakes; works in any slot. |
| [`BootRom.asm`](src/Retrocore.Machines.Apple3/Roms/BootRom.asm), [`Apple3Equates.asm`](src/Retrocore.Machines.Apple3/Roms/Apple3Equates.asm) | The Apple III's boot ROM, `$F000`–`$FFFF`: disk routines, diagnostics and monitor, with its hardware names. |
| [`WozMonitor.asm`](src/Retrocore.Machines.Apple1/Roms/WozMonitor.asm) | The Apple-1 Monitor, `$FF00`–`$FFFF`. |
| [`Aci.asm`](src/Retrocore.Machines.Apple1/Roms/Aci.asm) | The Apple Cassette Interface's PROM, `$C100`–`$C1FF`. |
| [`CharacterGenerator.asm`](src/Retrocore.Machines.Apple1/Roms/CharacterGenerator.asm) | The Apple-1 terminal's Signetics 2513 (no chip dump is published; its glyphs match the original Apple II's). |
| [`Basic/Basic.asm`](src/Retrocore.Machines.Apple1/Roms/Basic/Basic.asm) | Apple-1 BASIC, `$E000`–`$EFFF`, which loads from tape into the `$E000` bank. |
| [`Level2.asm`](src/Retrocore.Machines.Trs80/Roms/Level2.asm) | TRS-80 Model I Level II BASIC, revisions 1.2 and 1.3. |
| [`Level1.asm`](src/Retrocore.Machines.Trs80/Roms/Level1.asm) | TRS-80 Level I BASIC: the Model I's, and with `MODEL = 3` the Model III's. |
| [`CharacterGenerator.asm`](src/Retrocore.Machines.Trs80/Roms/CharacterGenerator.asm) | The Model I's stock MCM6670P character generator. |
| [`CharacterGeneratorKit.asm`](src/Retrocore.Machines.Trs80/Roms/CharacterGeneratorKit.asm) | The Radio Shack lowercase kit's character generator, following xtrs's reconstruction (no chip dump is known). |
| [`Model3.asm`](src/Retrocore.Machines.Trs80/Roms/Model3.asm), [`Model3Equates.asm`](src/Retrocore.Machines.Trs80/Roms/Model3Equates.asm) | The TRS-80 Model III's 14K ROM (both revisions of ROM C) and the Model 4's, including `Level2.asm` for the BASIC they share with the Model I. |
| [`Model4PBoot.asm`](src/Retrocore.Machines.Trs80/Roms/Model4PBoot.asm) | The Model 4P's boot ROM. |
| [`Model2Boot.asm`](src/Retrocore.Machines.Trs80/Roms/Model2Boot.asm) | The Model II's boot ROMs: versions 1, 2, 3 and 5, five ROMs, as version 3 has two. |
| [`Model3CharacterGenerator.asm`](src/Retrocore.Machines.Trs80/Roms/Model3CharacterGenerator.asm), [`Model2CharacterGenerator.asm`](src/Retrocore.Machines.Trs80/Roms/Model2CharacterGenerator.asm) | The Model III's and 4's, the 4P's, and the Model II's character generators. |
| [`ColorBasic.asm`](src/Retrocore.Machines.Coco/Roms/ColorBasic.asm) | TRS-80 Color Computer Color BASIC, versions 1.0 to 1.3. |
| [`ExtendedBasic.asm`](src/Retrocore.Machines.Coco/Roms/ExtendedBasic.asm) | TRS-80 Color Computer Extended Color BASIC, versions 1.0 and 1.1. |
| [`DiskBasic.asm`](src/Retrocore.Machines.Coco/Roms/DiskBasic.asm) | TRS-80 Color Computer Disk Extended Color BASIC, versions 1.0 and 1.1. |
| [`Mos.asm`](src/Retrocore.Machines.Acorn/Roms/Mos.asm) | The BBC Micro's MOS 1.20. |
| [`BbcBasic.asm`](src/Retrocore.Machines.Acorn/Roms/BbcBasic.asm) | BBC BASIC II. |
| [`Dnfs.asm`](src/Retrocore.Machines.Acorn/Roms/Dnfs.asm) | DNFS 1.20: the Acorn DFS and the Econet filing system. |
| [`Saa5050.asm`](src/Retrocore.Machines.Acorn/Roms/Saa5050.asm) | The SAA5050 teletext character generator's 96 characters. |
| [`Basic1.asm`](src/Retrocore.Machines.Commodore/Roms/Basic/Basic1.asm), [`Basic2.asm`](src/Retrocore.Machines.Commodore/Roms/Basic/Basic2.asm), [`Basic4.asm`](src/Retrocore.Machines.Commodore/Roms/Basic/Basic4.asm) | Commodore PET BASIC 1 (both first chips), BASIC 2 and BASIC 4 (both `$B000` chips, with the monitor and disk commands), sharing native Microsoft BASIC modules with AppleSoft. MACRO-10 overlays remain selectable. |
| [`Editor1.asm`](src/Retrocore.Machines.Commodore/Roms/Basic1/Editor1.asm), [`Kernal1.asm`](src/Retrocore.Machines.Commodore/Roms/Basic1/Kernal1.asm), [`Editor2.asm`](src/Retrocore.Machines.Commodore/Roms/Basic2/Editor2.asm), [`Kernal2.asm`](src/Retrocore.Machines.Commodore/Roms/Basic2/Kernal2.asm), [`Editor4.asm`](src/Retrocore.Machines.Commodore/Roms/Basic4/Editor4.asm), [`Kernal4.asm`](src/Retrocore.Machines.Commodore/Roms/Basic4/Kernal4.asm) | The PET's screen editors and kernals for BASIC 1, 2 and 4, with BASIC 2's machine-language monitor; BASIC 4's editor builds the graphics or the business keyboard's. |
| [`CharacterGenerator.asm`](src/Retrocore.Machines.Commodore/Roms/CharacterGenerator.asm) | The PET's character ROMs, the 2001's 901447-08 and the 2001-N's 901447-10. |
| [`Kaypro2.asm`](src/Retrocore.Machines.Kaypro/Roms/Kaypro2.asm), [`Kaypro2CharacterGenerator.asm`](src/Retrocore.Machines.Kaypro/Roms/Kaypro2CharacterGenerator.asm) | The Kaypro II's 81-149C monitor ROM and 81-146A character generator. |
| [`Mbasic/`](src/Retrocore.Machines.Kaypro/Roms/Mbasic/Mbasic.asm) | MBASIC 5.21 for CP/M, `$0100`-`$5FFF`, byte-identical to MBASIC.COM, in 19 modules following GW-BASIC's, with Microsoft's names and every routine documented. |
| [`Os.asm`](src/Retrocore.Machines.Atari/Roms/Os.asm) | The Atari 400's and 800's OS and character set, rev. A, rev. B and the PAL OS. |
| [`FloatingPoint.asm`](src/Retrocore.Machines.Atari/Roms/FloatingPoint.asm) | The Atari floating point package. |
| [`AtariBasic.asm`](src/Retrocore.Machines.Atari/Roms/AtariBasic.asm) | Atari BASIC, rev. A, B and C. |
| [`Atari810.asm`](src/Retrocore.Machines.Atari/Roms/Atari810.asm) | The Atari 810 disk drive's firmware, revisions B and C. |

All ROM sources are maintained by hand. Automated tests pin every build by SHA-256—so no ROM dumps are needed to
verify them—and also compare against your chip dumps byte for byte when dumps are present.

## Projects

| Project | What it holds |
| --- | --- |
| [`Retrocore.Core`](src/Retrocore.Core) | Shared instruction-set (`Isa`), CPU, bus, and machine/device abstractions. |
| [`Retrocore.Cpu.I8080`](src/Retrocore.Cpu.I8080) | State-exact Intel 8080 and 8085, with the 8085's interrupts, `RIM`/`SIM` and undocumented instructions and flags, and their [instruction set](src/Retrocore.Cpu.I8080/I8080Isa.txt). |
| [`Retrocore.Cpu.M6502`](src/Retrocore.Cpu.M6502) | Cycle-exact 6502 family: NMOS 6502, WDC 65C02, and Rockwell 65C02, with their [opcode tables](src/Retrocore.Cpu.M6502/OpcodeTables.txt). |
| [`Retrocore.Cpu.M6809`](src/Retrocore.Cpu.M6809) | Cycle-exact Motorola MC6809 with indexed postbytes, interrupts, `SYNC`/`CWAI`, and its [instruction set](src/Retrocore.Cpu.M6809/M6809Isa.txt). |
| [`Retrocore.Cpu.Z80`](src/Retrocore.Cpu.Z80) | T-state-exact Z80 with undocumented flags and MEMPTR, and its [instruction set](src/Retrocore.Cpu.Z80/Z80Isa.txt). |
| [`Retrocore.Assembler`](src/Retrocore.Assembler) | Multi-dialect assembler (native, ca65, Merlin, MACRO-10), disassembler, flow analysis, and `;;` documentation parser. |
| [`Retrocore.Basic`](src/Retrocore.Basic) | The Apple, TRS-80, Color Computer, PET, BBC Micro, Atari and CP/M BASICs, Level I among them: tokenizers, listings, label-based source compilation, diagnostics, expression evaluation, renumbering, tokenized files, and Model I tapes. |
| [`Retrocore.Media`](src/Retrocore.Media) | Disk, tape, and block media: WOZ, DOS 3.3 and 3.2 (`.dsk`, `.do`, `.d13`), ProDOS block images, SOS and Apple Pascal volumes and code files, sector floppies (DMK, IMD and raw Kaypro images in `Floppy`; JV1, JV3 and JVC), and CAS tapes. |
| [`Retrocore.Pascal`](src/Retrocore.Pascal) | Apple Pascal's p-code and its disassembler, and the p-machine's state as its interpreters keep it on the Apple II and Apple III. |
| [`Retrocore.Input`](src/Retrocore.Input) | SDL3 game controller discovery and polling, mapped to emulated joysticks and paddles. |
| [`Retrocore.Machines.Apple1`](src/Retrocore.Machines.Apple1) | The Apple-1: its 6821 PIA, video terminal, keyboard, Apple Cassette Interface, and SDK ROM sources. |
| [`Retrocore.Machines.Apple2`](src/Retrocore.Machines.Apple2) | The Apple II, II Plus, and IIe (original and enhanced), peripheral cards, and SDK ROM sources. |
| [`Retrocore.Machines.Apple3`](src/Retrocore.Machines.Apple3) | The Apple III: banked bus and extended addressing, video, keyboard, clock, serial port, drives, and its SDK ROM source. |
| [`Retrocore.Machines.Chips`](src/Retrocore.Machines.Chips) | Chips more than one machine uses: the Western Digital FD1771 and FD179x floppy disk controller and its drives, and the Z80 PIO, SIO, CTC and DMA. |
| [`Retrocore.Machines.Trs80`](src/Retrocore.Machines.Trs80) | The TRS-80 Model I, Expansion Interface with its drive select and doublers, cassette, and SDK ROM sources; the Model III, 4 and 4P; and the Model II family. |
| [`Retrocore.Machines.Trs80Model100`](src/Retrocore.Machines.Trs80Model100) | The TRS-80 Model 100 and Tandy 102: the 80C85's memory and ports, the LCD, keyboard and clock, and power. |
| [`Retrocore.Machines.Kaypro`](src/Retrocore.Machines.Kaypro) | The Kaypro II: banked memory, the system PIO, serial keyboard, display and disks, and its SDK sources, MBASIC's included. |
| [`Retrocore.Machines.Coco`](src/Retrocore.Machines.Coco) | The TRS-80 Color Computer 1, 2 and 3: SAM, VDG, GIME, PIAs, cassette, sound, cartridges, and the disk controller. |
| [`Retrocore.Machines.Acorn`](src/Retrocore.Machines.Acorn) | The BBC Micro Model B and A: the paged ROMs, both VIAs, the video ULA and SAA5050, keyboard, sound, the serial ULA and cassette, the 8271, and SDK ROM sources. |
| [`Retrocore.Machines.Commodore`](src/Retrocore.Machines.Commodore) | The Commodore PET 2001 and 4032: its PIAs and VIA, video, keyboard, sound, Datasettes, the IEEE-488 bus and the 4040 and 2040 disk drives, and SDK ROM sources. |
| [`Retrocore.Machines.Atari`](src/Retrocore.Machines.Atari) | The Atari 400 and 800: ANTIC, GTIA, POKEY, the PIA, cartridges, the serial bus with the 410 and the 810, and SDK ROM sources. |
| [`Retrocore.Debug`](src/Retrocore.Debug) | The debug adapter (DAP), assembly and BASIC language server, and `--assemble` / `--basic` / `--dos` / `--pascal` / `--disassemble` CLI, in one host. |
| [`Retrocore.Generators`](src/Retrocore.Generators) | Roslyn source generators that compile instruction-set descriptions and ROM sources into tables. |
| [`AppleSharp`](src/AppleSharp) | Standalone SDL3 Native AOT desktop emulator for the Apple IIe (uses caller-supplied ROM dumps). |
| [`tools/DosDisk`](tools/DosDisk) | CLI tool that builds bootable DOS 3.3 and 3.2 disk images from the SDK's DOS sources and a folder of files ([Dos.md](docs/Dos.md#building-disks)). |
| [`extension`](extension) | The VS Code extension: assembly and BASIC language features, debugging, live machine display, and the Retrocore activity bar's Machine and Drives views. |

## External files

Copyrighted ROM dumps, disk images, and third-party test corpora are never committed to this repository. Tests
and scripts look for them via environment variables or under `%USERPROFILE%\Retrocore`; any test missing an
external input reports **inconclusive** rather than failing.

This folder lives outside AppData on purpose: packaged Windows apps (such as the Claude desktop app) virtualize
`%LOCALAPPDATA%` into a private `AppData\Local\Packages\...\LocalCache` folder, so files written by shells they
launch are invisible to Explorer, VS Code, and normal terminals.

| Variable | Holds |
| --- | --- |
| `RETROCORE_CACHE` | Base folder for cached external files (default `%USERPROFILE%\Retrocore`, shown as `<cache>` below). |
| `RETROCORE_IIE_ROMS` | Apple IIe CD, EF, and video ROM dumps. Optional for debugging (which otherwise builds from the SDK); required by `AppleSharp` and the IIe chip/oracle tests; `extension`'s full `npm test` uses them when set and otherwise ROMs built from the SDK. |
| `RETROCORE_IIPLUS_ROMS`, `RETROCORE_II_ROMS` | Apple II Plus and Apple II 2716 chip dumps (defaults `<cache>\apple2-roms\APPLE II+` and `<cache>\apple2-roms\APPLE II`); optional for debugging. |
| `RETROCORE_DISKII_ROMS` | Disk II P5/P6 chip dumps under their `apple2.org.za` names (default `<cache>\disk2-roms`). |
| `RETROCORE_APPLE1_ROMS` | Apple-1 Monitor, ACI and BASIC dumps, `wozmon.bin`, `aci.bin` and `basic.bin` (default `<cache>\apple1-roms` for the ROM source checks); optional for debugging. |
| `RETROCORE_TRS80M100_ROMS` | The Model 100's and Tandy 102's ROMs (`m100rom.m12` and `m102rom.m12`, or `m100.bin` and `t102.bin`; default `<cache>\trs80m100-roms` for the tests); the debugger needs it, `romDirectory` or `rom` to run either, as Retrocore has no source for the ROMs yet. |
| `RETROCORE_TRS80_ROMS` | TRS-80 ROM dumps under MAME's names (default `<cache>\trs80-roms\extract`); optional for every TRS-80, whose ROMs the SDK's sources build. |
| `RETROCORE_APPLE3_ROMS` | MAME's `apple3` set unzipped (default `<cache>\apple3-roms\mame\apple3`); optional for debugging. |
| `RETROCORE_APPLE3_DISKS` | SOS 1.3 disk images for the Apple III tests (default `<cache>\apple3-disks`). |
| `RETROCORE_COCO_ROMS` | Color Computer ROM dumps under MAME's names (default `<cache>\coco-roms\extract`); optional for debugging (without them, every model's ROMs are built from the SDK's sources). |
| `RETROCORE_BBC_ROMS` | BBC Micro ROM dumps: MAME's `bbcb` set unzipped (default `<cache>\bbc-roms\extract\bbcb` for the tests); optional for debugging, which builds the ROMs from the SDK's sources. |
| `RETROCORE_PET_ROMS` | MAME's `pet2001`, `pet2001n`, `pet4016`, `pet4032b`, `c4040` and `c2040` sets unzipped, each in its folder (default `<cache>\pet-roms\extract`); optional for debugging (without them, every model's ROMs are built from the SDK's sources), but the 4040 and 2040 drives need their `c4040` and `c2040` sets. |
| `RETROCORE_ATARI_ROMS` | MAME's `a800` set unzipped (default `<cache>\atari8-roms\extract\a800`), with the 810's firmware in an `atari810` folder beside it (a PAL launch takes the folder holding `a800` and `a800pal`); optional for debugging (without them, the ROMs are built from the SDK's sources). |
| `RETROCORE_MAME` | `mame.exe` path for the Model I, Apple III, Color Computer, PET, 4040, 2040, BBC Micro and Atari oracle tests (default `<cache>\mame\mame.exe`). |
| `RETROCORE_TRS80_DOS` | A NEWDOS/80 JV1 disk image for `tools\Test-Trs80Dap.mjs` (default `<cache>\trs80-disks\NEWDOS_80sssd_jv1.DSK`). |
| `RETROCORE_KAYPRO` | Kaypro II dumps and disks for the tests and `tools\Test-KayproDap.mjs`: `81-149c.rom`, `81-146a.bin`, `cpm22-rom149.img` (CP/M 2.2) and `MBasic.img` (default `<cache>\kaypro`). |
| `RETROCORE_KAYPRO_ROMS` | Kaypro II chip dumps for debugging in place of the SDK's builds (MAME's `kayproii` names, or the names above); optional. |
| `RETROCORE_TEST_CACHE` | Processor test suites fetched by `tools\Fetch-ProcessorTests.ps1` (~3 GiB), `tools\Fetch-Z80Tests.ps1` (~1.4 GiB), `tools\Fetch-M6809Tests.ps1`, and `tools\Fetch-I8080Tests.ps1`, all requiring `gh` and `git` (default `<cache>\processor-tests`). |
| `RETROCORE_ZEXDOC` | Set to any value to run ZEXDOC in addition to ZEXALL. Skipped by default because ZEXALL runs the same instructions and checks all flags; ZEXDOC only isolates whether a ZEXALL failure is in undocumented flags. |
| `RETROCORE_CC65`, `RETROCORE_CA65_CORPUS`, `RETROCORE_CA65_ASMINC` | Directory containing `ca65` and `ld65`, optional `rom4x` ca65 source corpus, and `cc65`'s `asminc` header directory for the ca65 differential and SDK tests. |
| `RETROCORE_MERLIN32`, `RETROCORE_MERLIN_CORPUS` | Merlin 32 executable and approved source corpus for the Merlin differential tests. |
| `RETROCORE_VSCODE` | VS Code executable (`Code.exe` on Windows) for the extension's editor tests; unset, they download a pinned VS Code. |

`tools\Fetch-M1Dependencies.ps1` populates `<cache>\m1-dependencies` with `cc65` (compiled locally with Visual
Studio's C++ tools), ProDOS 2.4.3, Microsoft's 6502 BASIC source and `msbasic` reference binaries, and pinned
Apple2TS sources. `tools\Fetch-Trs80Font.ps1` fetches xtrs's font source to verify
[`CharacterGeneratorKit.asm`](src/Retrocore.Machines.Trs80/Roms/CharacterGeneratorKit.asm).

## Building and testing

With the `.NET 10 SDK` and Node.js in place, these build and test the repository.
[CI](.github/workflows/ci.yml) runs the ones that need nothing external, and the extension's editor tests in the
VS Code they download, on every push to `main` and every pull request:

```powershell
dotnet build Retrocore.slnx -c Release
dotnet test Retrocore.slnx -c Release --no-build

node tools/Test-Trs80Dap.mjs          # needs nothing external
node tools/Test-Trs80Model3Dap.mjs    # needs nothing external; it writes stand-in ROMs
node tools/Test-KayproDap.mjs         # needs nothing external; boots CP/M and MBASIC with RETROCORE_KAYPRO's disks
node tools/Test-Apple1Dap.mjs         # needs nothing external
node tools/Test-Apple1BasicDap.mjs    # needs nothing external
node tools/Test-CocoDap.mjs           # needs nothing external; uses the dumps in RETROCORE_COCO_ROMS when set
node tools/Test-BbcDap.mjs            # needs nothing external; uses the dumps in RETROCORE_BBC_ROMS when set
node tools/Test-PetDap.mjs            # needs nothing external
node tools/Test-PetBasicDap.mjs       # needs nothing external
node tools/Test-AtariDap.mjs          # needs nothing external
node tools/Test-IntegerBasicDap.mjs   # needs nothing external
node tools/Test-Breakpoints.mjs       # needs nothing external
node tools/Test-Memory.mjs            # needs nothing external; also checks IIe banks when RETROCORE_IIE_ROMS is set
node tools/Test-CycleEvents.mjs       # needs nothing external; checks cycle snapshots and compatibility
node tools/Test-OffMachine.mjs        # needs nothing external

.\tools\Build-IIeSample.ps1           # needs cc65 from Fetch-M1Dependencies.ps1 (or assemble with Retrocore.Debug --assemble)
node tools/Test-IIeDap.mjs            # SDK-built ROMs, or the dumps in RETROCORE_IIE_ROMS
node tools/Test-ProDosBasicDap.mjs    # needs the ProDOS 2.4.3 image from Fetch-M1Dependencies.ps1

npm --prefix extension ci
npm --prefix extension run compile
npm --prefix extension run test:grammar   # needs nothing external
npm --prefix extension run test:language  # needs the Release build; downloads a pinned VS Code
npm --prefix extension test               # full editor + debugger suite: needs the Release build and iie-sample; downloads a pinned VS Code
```

Without `cc65`, you can also build `artifacts\iie-sample\main.bin` and `main.dbg` with `Retrocore.Debug` itself:

```powershell
New-Item -ItemType Directory -Path artifacts\iie-sample -Force | Out-Null
dotnet run --project src\Retrocore.Debug -c Release --no-build -- --assemble sample\iie\main.s artifacts\iie-sample\main.bin --dialect ca65 --config sample\iie\link.cfg
```

`node tools/Test-IIPlusDap.mjs` and `node tools/Test-IIDap.mjs` run additional DAP checks against Apple II Plus
and Apple II chip dumps when `RETROCORE_IIPLUS_ROMS` and `RETROCORE_II_ROMS` are present.

`Retrocore.Debug` uses no reflection, so it also compiles ahead of time to a single native executable that starts
in about a quarter of the time:

```powershell
dotnet publish src\Retrocore.Debug -c Release -r win-x64 -p:RetrocoreAot=true -o artifacts\aot
$env:RETROCORE_DAP_HOST = "$PWD\artifacts\aot\Retrocore.Debug.exe"; node tools/Test-Trs80Dap.mjs
```

Native AOT publish on Windows requires Visual Studio's C++ build tools and the Visual Studio Installer folder on
`PATH` for `vswhere`. Setting `RETROCORE_DAP_HOST` runs the DAP scripts against that binary instead of the
Release build.

For working on the VS Code extension itself, `tools\Install-Extension.ps1` packages and installs it
([Installing the VS Code extension](#installing-the-vs-code-extension)), and `tools\Start-SelfHost.ps1` launches
the in-repo extension in an isolated VS Code profile
([extension README](extension/README.md#installing-and-self-hosting)).

Test coverage spans:

- **CPUs** against reference suites: Tom Harte's SingleStepTests (per-cycle/T-state), Klaus Dormann's 6502
  functional tests, ZEXALL (all 67 exerciser groups run in parallel as individual test cases; ZEXDOC optional),
  and the FUSE Z80 tests;
- **Machines** against their ROMs, Apple2TS (for IIe ProDOS boot and double hi-res video), and MAME (for the
  Model I and the Color Computer, down to a Disk BASIC disk image);
- **SDK ROM and DOS sources** pinned byte for byte by SHA-256 and compared against chip dumps;
- **BASIC dialects** against lines tokenized by the real ROMs and programs on Apple's DOS 3.3 System Master;
- **Assembler front ends** differentially against `ca65`/`ld65`, Merlin 32, and original Microsoft 6502 BASIC
  builds.

[`tests/Retrocore.Aot.Tests`](tests/Retrocore.Aot.Tests) verifies CPU, assembler, disassembler, and machine
execution under Native AOT, and [`tests/Retrocore.Perf`](tests/Retrocore.Perf) holds BenchmarkDotNet benchmarks.

## Plans

Design notes for upcoming work live in [`docs/backlog`](docs/backlog):

- [debugging BASIC programs](docs/backlog/BasicDebugging.md): disk-image import/export;
- [choosing and starting a machine, next round](docs/backlog/MachineLaunch.md);
- [CPU core and machine loop speed](docs/backlog/CoreOptimization.md), including what .NET 11 might offer;
- [the language server's SDK index speed](docs/backlog/SdkIndexOptimization.md), with every change measured;
- [exporting HTML documentation from `;;` comments](docs/backlog/DocExport.md);
- [documented struct, union and enum members](docs/backlog/MemberDocumentation.md), with historical names;
- [`.using`, names from another scope without qualifying them](docs/backlog/Using.md);
- [lint exclusions](docs/backlog/LintExclusions.md): rule IDs, and ignoring a rule for a line, a comment or a file;
- [the media library and explorers](docs/backlog/Media.md);
- [saving media back to images](docs/backlog/MediaPersistence.md): changed disks and tapes on every machine;
- [machine files, data folders and libraries](docs/backlog/MachineFiles.md), shared by VS Code and the standalone emulator;
- [the Retrocore SDK](docs/backlog/Sdk.md): projects for a CPU family that build for and debug on each of its machines,
  starting with a Scott Adams adventure interpreter;
- [Retrocore Desktop](docs/backlog/Desktop.md), the standalone emulator, with the extension's views in an Avalonia window;
- [Apple Pascal](docs/backlog/ApplePascal.md) on the Apple II and Apple III;
- [more assembler dialects (Zilog, EDTASM, zmac, 6809)](docs/backlog/Dialects.md);
- [the Motorola 6809 and the TRS-80 Color Computer](docs/backlog/M6809-CoCo.md), and
  [its ROM sources](docs/backlog/CocoRomSources.md);
- [the Apple III's open checks and later work](docs/backlog/Apple3.md);
- [the Intel 8080 and 8085](docs/backlog/I8080.md), and [the Altair 8800](docs/backlog/Altair8800.md): CP/M's sources and its front panel view;
- [the TRS-80 Model 100](docs/backlog/Trs80Model100.md): its files, cassette, serial port and disk drive, its ROM as an SDK source, and its relatives;
- [the 3.5 disk controller at the hardware level](docs/backlog/Disk35Hardware.md), running Apple's EPROM on an emulated 65C02 and SWIM;
- [SOS sources: the Apple III's kernel and drivers](docs/backlog/SosSources.md);
- [Business BASIC's other versions, modules and DEF FN view](docs/backlog/BusinessBasic.md);
- [the Z80 SoftCards](docs/backlog/SoftCard.md): interrupts, the Premium SoftCard IIe and CP/M 3, CP/M sources, if wanted;
- [the Commodore PET](docs/backlog/Pet.md): the 8032's 80 columns and CRTC, if wanted;
- [the Kaypro II](docs/backlog/Kaypro.md): CP/M's sources and its disks as a file system;
- [the BBC Micro's later models and expansions](docs/backlog/BbcMicro.md);
- [the Atari 400 and 800](docs/backlog/Atari800.md);
- [aligning the conversion of the SDK's sources](docs/backlog/ConversionAlignment.md) with the shared BASIC modules.

## License

MIT; see [LICENSE](LICENSE). Microsoft's `m6502.asm` carries its own MIT license in
[`src/Retrocore.Basic/Roms/Microsoft6502Basic/LICENSE`](src/Retrocore.Basic/Roms/Microsoft6502Basic/LICENSE).
MBASIC's source ([`Mbasic/`](src/Retrocore.Machines.Kaypro/Roms/Mbasic/Mbasic.asm)) takes Microsoft's names for its routines and variables
from [GW-BASIC's source](https://github.com/microsoft/GW-BASIC), also MIT-licensed.
The Model I lowercase kit's font follows [xtrs](https://github.com/TimothyPMann/xtrs), whose notice is kept in
[`CharacterGeneratorKit.asm`](src/Retrocore.Machines.Trs80/Roms/CharacterGeneratorKit.asm). Additional
third-party notices for bundled extension and desktop assets are in
[`extension/ThirdPartyNotices.txt`](extension/ThirdPartyNotices.txt) and
[`src/AppleSharp/ThirdPartyNotices.txt`](src/AppleSharp/ThirdPartyNotices.txt). ROM dumps belong to their
respective copyright holders and are not distributed here.
