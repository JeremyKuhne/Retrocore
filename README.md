# Retrocore

Retrocore emulates and debugs 8-bit computers in one .NET codebase: cycle-exact CPUs, the machines and
peripherals built around them, a multi-dialect assembler and disassembler, BASIC language and program tools, a
source-level debugger for assembly and BASIC, and a VS Code extension.

Every machine's ROMs are also maintained here as documented assembly sources that rebuild byte-identically to the
original chips. No external ROM dumps are needed to run or debug a machine, and you can step from your own code
straight into the ROM or DOS source.

| Machine | CPU | ROMs (SDK sources, or dumps you supply) | Media and peripherals |
| --- | --- | --- | --- |
| Apple-1 | MOS 6502 | Woz Monitor, Apple Cassette Interface PROM, Signetics 2513 character generator; Apple-1 BASIC, which loads into RAM | 4 or 8 KB RAM plus the `$E000` bank, 6821 PIA keyboard and 60-characters-a-second video terminal, Apple Cassette Interface (WAV tapes, play and record) |
| Apple II and II Plus | MOS 6502 | Integer BASIC (II), AppleSoft (II Plus), original or Autostart Monitor, character generator, Programmer's Aid #1 | Disk II 16- and 13-sector (WOZ, DSK, DO, PO, D13), fresh DOS 3.3 and 3.2 disks, slot-7 ProDOS block storage, slot-0 language or firmware card, speaker and slot-4 stereo Mockingboard, AppleMouse II-compatible mouse card, Apple II 3.5 Disk Controller-compatible SmartPort with two SuperDrives (400K/800K, 720K/1.44 MB), ProFile hard disk cards (PO, HDV), SDL3 game controllers |
| Apple IIe, original and enhanced | MOS 6502 / Rockwell 65C02 | Monitor, internal `$C100`–`$CFFF` firmware, AppleSoft, video ROM (with MouseText on enhanced) | Built-in language card and extended 80-column card (64 KB auxiliary RAM), plus the same Disk II, ProDOS block storage, audio, and controller support as the II |
| Apple III | Synertek 6502A | Boot ROM (diagnostics, monitor and SOS boot) | 128, 256 or 512 KB banked RAM with extended addressing, all native video modes with character RAM, built-in and three external drives (WOZ, DSK, DO, PO), speaker and 6-bit DAC, ProFile hard disk cards with pseudo-DMA (PO, HDV), SOS 1.3 |
| TRS-80 Model I, Level II and Level I | Z80 | Level II 1.2 and 1.3, Level I, MCM6670P character generator; plus the Radio Shack lowercase kit's font (from source; no chip dump is known) | CAS tapes (play and record), Expansion Interface (up to 48 KB RAM, 40 Hz clock, FD1771 with Percom/Radio Shack double-density doubler), JV1 and JV3 disks, lowercase modification |
| TRS-80 Color Computer 1, 2 and 3 | Motorola 6809E | Color BASIC 1.0-1.3, Extended Color BASIC 1.0 and 1.1, Disk Extended Color BASIC 1.0 and 1.1, and the CoCo 3's Extended Color BASIC 2.0 with Super Extended BASIC | SAM and MC6847/MC6847T1 VDG with artifact colors, the CoCo 3's GIME (MMU, 128 or 512 KB, palette, timer, 40/80 columns), CAS tapes, sound, joysticks, ROM packs, the disk controller cartridge with JVC disks |

The Disk II controller's boot and state-sequencer ROMs, Apple DOS 3.3 and 3.2, and the firmware of the emulated
slot-7 ProDOS block device, mouse card and ProFile card are documented SDK sources too. See the
[Apple-1](docs/Apple1.md), [Apple II family](docs/Apple2.md), [Apple III](docs/Apple3.md),
[TRS-80 Model I](docs/Trs80ModelI.md) and [Color Computer](docs/Coco.md) guides for hardware details and launch
options. On the Color Computer, Color, Extended and Disk BASIC and the CoCo 3's ROM are all SDK sources, so every
model runs with nothing external.

> **Not published yet.** Retrocore has no public release on the VS Code Marketplace, Open VSX, or NuGet. To use
> the VS Code extension, build and install the VSIX from this repository as shown below.

## Installing the VS Code extension

Prerequisites:

- the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0);
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
machine needs the [.NET 10 runtime](https://dotnet.microsoft.com/download/dotnet/10.0), but it does not need the
.NET SDK, Node.js, or any ROM dumps. To run the in-repo extension directly in a separate development
window while working on it, see [Installing and self-hosting](extension/README.md#installing-and-self-hosting).

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
summaries into generated C# XML documentation ([DocComments.md](docs/DocComments.md)).

In VS Code, assembly files get syntax highlighting, live diagnostics as you type, go to definition, find all
references, hovers (instruction summaries, flags, addressing modes, cycle counts, and emitted bytes),
completions, document outlines, and workspace symbol search across your code and the SDK ROMs
([Language features](extension/README.md#language-features)).

## BASIC

Retrocore supports **AppleSoft BASIC**, **Integer BASIC**, and **TRS-80 Level II BASIC** (Level I BASIC is
[planned](docs/backlog/BasicDebugging.md)):

- **Source files with optional labels.** `.applesoft.bas`, `.integer.bas`, `.level2.bas`, and `.bas` files can
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
(`"apple2"` or `"trs80-model1"`) and can boot the machine on its own, assemble `source` (directly into RAM or
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
  named variables, and `pascal` breakpoints on p-code ([Pascal.md](docs/Pascal.md));
- **Live memory views:** side-effect-free inspection and editing in Microsoft's Hex Editor or Memory Inspector,
  kept current while the machine runs, with Apple II language-card banks, firmware/slot ROMs, and IIe auxiliary
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
[Apple II](docs/Apple2.md), [Model I](docs/Trs80ModelI.md) and [Color Computer](docs/Coco.md) guides cover each
machine.

## SDK ROM sources

| Source | Covers |
| --- | --- |
| [`Monitor.asm`](src/Retrocore.Machines.Apple2/Roms/System/Monitor.asm) | The Apple II Monitor, `$F800`–`$FFFF`: the II's original Monitor, the II and II Plus's Autostart Monitor, and both IIe models' Monitors. |
| [`Firmware.Original.asm`](src/Retrocore.Machines.Apple2/Roms/System/Firmware.Original.asm), [`Firmware.Enhanced.asm`](src/Retrocore.Machines.Apple2/Roms/System/Firmware.Enhanced.asm) | The IIe's internal `$C100`–`$CFFF` firmware, sharing [`FirmwareEquates.asm`](src/Retrocore.Machines.Apple2/Roms/System/FirmwareEquates.asm). |
| [`IIeEquates.asm`](src/Retrocore.Machines.Apple2/Roms/System/IIeEquates.asm), [`MonitorEntries.asm`](src/Retrocore.Machines.Apple2/Roms/System/MonitorEntries.asm) | Shared IIe page-zero locations, soft switches, and key codes (`IIeEquates.asm`, included by the Monitor too) and Monitor entry points (`MonitorEntries.asm`), included by the firmware, Disk II boot ROMs, and DOS. |
| [`Boot16.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Boot16.asm), [`Sequencer16.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer16.asm), [`Boot13.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Boot13.asm), [`Sequencer13.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer13.asm) | The Disk II controller's 16- and 13-sector boot ROMs and logic state sequencers, sharing [`Boot.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Boot.asm) and [`Sequencer.asm`](src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer.asm); see [DiskII.md](docs/DiskII.md). |
| [`applesoft.mac`](src/Retrocore.Machines.Apple2/Roms/AppleSoft/applesoft.mac) | AppleSoft II for the II Plus and IIe, as a MACRO-10 overlay over Microsoft's [`m6502.asm`](src/Retrocore.Machines.Apple2/Roms/AppleSoft/m6502.asm). |
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
| [`Level1.asm`](src/Retrocore.Machines.Trs80/Roms/Level1.asm) | TRS-80 Model I Level I BASIC. |
| [`CharacterGenerator.asm`](src/Retrocore.Machines.Trs80/Roms/CharacterGenerator.asm) | The Model I's stock MCM6670P character generator. |
| [`CharacterGeneratorKit.asm`](src/Retrocore.Machines.Trs80/Roms/CharacterGeneratorKit.asm) | The Radio Shack lowercase kit's character generator, following xtrs's reconstruction (no chip dump is known). |
| [`ColorBasic.asm`](src/Retrocore.Machines.Coco/Roms/ColorBasic.asm) | TRS-80 Color Computer Color BASIC, versions 1.0 to 1.3. |
| [`ExtendedBasic.asm`](src/Retrocore.Machines.Coco/Roms/ExtendedBasic.asm) | TRS-80 Color Computer Extended Color BASIC, versions 1.0 and 1.1. |
| [`DiskBasic.asm`](src/Retrocore.Machines.Coco/Roms/DiskBasic.asm) | TRS-80 Color Computer Disk Extended Color BASIC, versions 1.0 and 1.1. |

All ROM sources are maintained by hand. Automated tests pin every build by SHA-256—so no ROM dumps are needed to
verify them—and also compare against your chip dumps byte for byte when dumps are present.

## Projects

| Project | What it holds |
| --- | --- |
| [`Retrocore.Core`](src/Retrocore.Core) | Shared instruction-set (`Isa`), CPU, bus, and machine/device abstractions. |
| [`Retrocore.Cpu.M6502`](src/Retrocore.Cpu.M6502) | Cycle-exact 6502 family: NMOS 6502, WDC 65C02, and Rockwell 65C02, with their [opcode tables](src/Retrocore.Cpu.M6502/OpcodeTables.txt). |
| [`Retrocore.Cpu.M6809`](src/Retrocore.Cpu.M6809) | Cycle-exact Motorola MC6809 with indexed postbytes, interrupts, `SYNC`/`CWAI`, and its [instruction set](src/Retrocore.Cpu.M6809/M6809Isa.txt). |
| [`Retrocore.Cpu.Z80`](src/Retrocore.Cpu.Z80) | T-state-exact Z80 with undocumented flags and MEMPTR, and its [instruction set](src/Retrocore.Cpu.Z80/Z80Isa.txt). |
| [`Retrocore.Assembler`](src/Retrocore.Assembler) | Multi-dialect assembler (native, ca65, Merlin, MACRO-10), disassembler, flow analysis, and `;;` documentation parser. |
| [`Retrocore.Basic`](src/Retrocore.Basic) | AppleSoft, Integer BASIC, and Level II BASIC: tokenizers, listings, label-based source compilation, diagnostics, expression evaluation, renumbering, tokenized files, and Model I tapes. |
| [`Retrocore.Media`](src/Retrocore.Media) | Disk, tape, and block media: WOZ, DOS 3.3 and 3.2 (`.dsk`, `.do`, `.d13`), ProDOS block images, SOS and Apple Pascal volumes and code files, JV1, JV3 and JVC floppies, and CAS tapes. |
| [`Retrocore.Pascal`](src/Retrocore.Pascal) | Apple Pascal's p-code and its disassembler, and the p-machine's state as its interpreters keep it on the Apple II and Apple III. |
| [`Retrocore.Input`](src/Retrocore.Input) | SDL3 game controller discovery and polling, mapped to emulated joysticks and paddles. |
| [`Retrocore.Machines.Apple1`](src/Retrocore.Machines.Apple1) | The Apple-1: its 6821 PIA, video terminal, keyboard, Apple Cassette Interface, and SDK ROM sources. |
| [`Retrocore.Machines.Apple2`](src/Retrocore.Machines.Apple2) | The Apple II, II Plus, and IIe (original and enhanced), peripheral cards, and SDK ROM sources. |
| [`Retrocore.Machines.Apple3`](src/Retrocore.Machines.Apple3) | The Apple III: banked bus and extended addressing, video, keyboard, clock, serial port, drives, and its SDK ROM source. |
| [`Retrocore.Machines.Trs80`](src/Retrocore.Machines.Trs80) | The TRS-80 Model I, Expansion Interface, floppy/doubler hardware, cassette, and SDK ROM sources. |
| [`Retrocore.Machines.Coco`](src/Retrocore.Machines.Coco) | The TRS-80 Color Computer 1, 2 and 3: SAM, VDG, GIME, PIAs, cassette, sound, cartridges, and the disk controller. |
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
| `RETROCORE_IIE_ROMS` | Apple IIe CD, EF, and video ROM dumps. Optional for debugging (which otherwise builds from the SDK); required by `AppleSharp`, the IIe chip/oracle tests, and `extension`'s full `npm test`. |
| `RETROCORE_IIPLUS_ROMS`, `RETROCORE_II_ROMS` | Apple II Plus and Apple II 2716 chip dumps (defaults `<cache>\apple2-roms\APPLE II+` and `<cache>\apple2-roms\APPLE II`); optional for debugging. |
| `RETROCORE_DISKII_ROMS` | Disk II P5/P6 chip dumps under their `apple2.org.za` names (default `<cache>\disk2-roms`). |
| `RETROCORE_APPLE1_ROMS` | Apple-1 Monitor, ACI and BASIC dumps, `wozmon.bin`, `aci.bin` and `basic.bin` (default `<cache>\apple1-roms` for the ROM source checks); optional for debugging. |
| `RETROCORE_TRS80_ROMS` | Model I ROM dumps under MAME's names (default `<cache>\trs80-roms\extract`); optional for debugging. |
| `RETROCORE_APPLE3_ROMS` | MAME's `apple3` set unzipped (default `<cache>\apple3-roms\mame\apple3`); optional for debugging. |
| `RETROCORE_APPLE3_DISKS` | SOS 1.3 disk images for the Apple III tests (default `<cache>\apple3-disks`). |
| `RETROCORE_COCO_ROMS` | Color Computer ROM dumps under MAME's names (default `<cache>\coco-roms\extract`); optional for debugging (without them, every model's ROMs are built from the SDK's sources). |
| `RETROCORE_MAME` | `mame.exe` path for the Model I, Apple III and Color Computer oracle tests (default `<cache>\mame\mame.exe`). |
| `RETROCORE_TRS80_DOS` | A NEWDOS/80 JV1 disk image for `tools\Test-Trs80Dap.mjs` (default `<cache>\trs80-disks\NEWDOS_80sssd_jv1.DSK`). |
| `RETROCORE_TEST_CACHE` | Processor test suites fetched by `tools\Fetch-ProcessorTests.ps1` (~3 GiB), `tools\Fetch-Z80Tests.ps1` (~1.4 GiB), and `tools\Fetch-M6809Tests.ps1`, all requiring `gh` and `git` (default `<cache>\processor-tests`). |
| `RETROCORE_ZEXDOC` | Set to any value to run ZEXDOC in addition to ZEXALL. Skipped by default because ZEXALL runs the same instructions and checks all flags; ZEXDOC only isolates whether a ZEXALL failure is in undocumented flags. |
| `RETROCORE_CC65`, `RETROCORE_CA65_CORPUS`, `RETROCORE_CA65_ASMINC` | Directory containing `ca65` and `ld65`, optional `rom4x` ca65 source corpus, and `cc65`'s `asminc` header directory for the ca65 differential and SDK tests. |
| `RETROCORE_MERLIN32`, `RETROCORE_MERLIN_CORPUS` | Merlin 32 executable and approved source corpus for the Merlin differential tests. |
| `RETROCORE_VSCODE` | VS Code executable (`Code.exe`) override for the extension's editor tests. |

`tools\Fetch-M1Dependencies.ps1` populates `<cache>\m1-dependencies` with `cc65` (compiled locally with Visual
Studio's C++ tools), ProDOS 2.4.3, Microsoft's 6502 BASIC source and `msbasic` reference binaries, and pinned
Apple2TS sources. `tools\Fetch-Trs80Font.ps1` fetches xtrs's font source to verify
[`CharacterGeneratorKit.asm`](src/Retrocore.Machines.Trs80/Roms/CharacterGeneratorKit.asm).

## Building and testing

With the `.NET 10 SDK` and Node.js in place, these build and test the repository.
[CI](.github/workflows/ci.yml) runs the ones that need nothing external on every push to `main` and every pull
request:

```powershell
dotnet build Retrocore.slnx -c Release
dotnet test Retrocore.slnx -c Release --no-build

node tools/Test-Trs80Dap.mjs          # needs nothing external
node tools/Test-Apple1Dap.mjs         # needs nothing external
node tools/Test-Apple1BasicDap.mjs    # needs nothing external
node tools/Test-CocoDap.mjs           # needs nothing external; uses the dumps in RETROCORE_COCO_ROMS when set
node tools/Test-IntegerBasicDap.mjs   # needs nothing external
node tools/Test-Breakpoints.mjs       # needs nothing external
node tools/Test-Memory.mjs            # needs nothing external; also checks IIe banks when RETROCORE_IIE_ROMS is set

.\tools\Build-IIeSample.ps1           # needs cc65 from Fetch-M1Dependencies.ps1 (or assemble with Retrocore.Debug --assemble)
node tools/Test-IIeDap.mjs            # SDK-built ROMs, or the dumps in RETROCORE_IIE_ROMS
node tools/Test-ProDosBasicDap.mjs    # needs the ProDOS 2.4.3 image from Fetch-M1Dependencies.ps1

npm --prefix extension ci
npm --prefix extension run compile
npm --prefix extension run test:grammar   # needs nothing external
npm --prefix extension run test:language  # needs VS Code
npm --prefix extension test               # full editor + debugger suite: needs VS Code, RETROCORE_IIE_ROMS, and iie-sample
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

- [debugging BASIC programs](docs/backlog/BasicDebugging.md): Level I BASIC and disk-image import/export;
- [choosing and starting a machine, next round](docs/backlog/MachineLaunch.md);
- [CPU core and machine loop speed](docs/backlog/CoreOptimization.md), including what .NET 11 might offer;
- [exporting HTML documentation from `;;` comments](docs/backlog/DocExport.md);
- [the media library and explorers](docs/backlog/Media.md);
- [Apple Pascal](docs/backlog/ApplePascal.md) on the Apple II and Apple III;
- [more assembler dialects (Zilog, EDTASM, zmac, 6809)](docs/backlog/Dialects.md);
- [the Motorola 6809 and the TRS-80 Color Computer](docs/backlog/M6809-CoCo.md), and
  [its ROM sources](docs/backlog/CocoRomSources.md);
- [the Apple III](docs/backlog/Apple3.md);
- [the 3.5 disk controller at the hardware level](docs/backlog/Disk35Hardware.md), running Apple's EPROM on an emulated 65C02 and SWIM;
- [SOS sources: the Apple III's kernel and drivers](docs/backlog/SosSources.md);
- [debugging Business BASIC](docs/backlog/BusinessBasic.md).

## License

MIT; see [LICENSE](LICENSE). Microsoft's `m6502.asm` carries its own MIT license in
[`src/Retrocore.Machines.Apple2/Roms/AppleSoft/LICENSE`](src/Retrocore.Machines.Apple2/Roms/AppleSoft/LICENSE).
The Model I lowercase kit's font follows [xtrs](https://github.com/TimothyPMann/xtrs), whose notice is kept in
[`CharacterGeneratorKit.asm`](src/Retrocore.Machines.Trs80/Roms/CharacterGeneratorKit.asm). Additional
third-party notices for bundled extension and desktop assets are in
[`extension/ThirdPartyNotices.txt`](extension/ThirdPartyNotices.txt) and
[`src/AppleSharp/ThirdPartyNotices.txt`](src/AppleSharp/ThirdPartyNotices.txt). ROM dumps belong to their
respective copyright holders and are not distributed here.
