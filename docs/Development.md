# Development, testing and repository layout

How to build and test Retrocore from source, publish Native AOT hosts, configure optional external ROM dumps and
reference corpora, and navigate the repository's projects and SDK system sources.

## Building and testing

Prerequisites:

- the [.NET 11 SDK](https://dotnet.microsoft.com/download/dotnet/11.0) (pinned in [`global.json`](../global.json));
- [Node.js](https://nodejs.org) with npm, for the debug-adapter scripts and the VS Code extension.

[CI](../.github/workflows/ci.yml) runs the build, the .NET test suite, the multi-target sample builds, the debug-adapter
scripts that need nothing external, and the extension's grammar, language-server, and editor tests (in a downloaded
pinned VS Code) on every push to `main` and every pull request:

```powershell
dotnet build Retrocore.slnx -c Release
dotnet test Retrocore.slnx -c Release --no-build

# Assemble the IIe ca65 sample with the in-repo host (or run .\tools\Build-IIeSample.ps1 with cc65)
New-Item -ItemType Directory -Path artifacts\iie-sample -Force | Out-Null
dotnet artifacts\AnyCPU\Release\Retrocore.Debug\net11.0\Retrocore.Debug.dll --assemble sample\iie\main.s artifacts\iie-sample\main.bin --dialect ca65 --config sample\iie\link.cfg

# Build every target of the multi-machine adventure sample
dotnet artifacts\AnyCPU\Release\Retrocore.Debug\net11.0\Retrocore.Debug.dll build --all --project sample\adventure

# Debug-adapter integration scripts run in CI (need nothing external)
node tools/Test-Trs80Dap.mjs
node tools/Test-Trs80Model3Dap.mjs
node tools/Test-Apple1Dap.mjs
node tools/Test-Apple1BasicDap.mjs
node tools/Test-PetDap.mjs
node tools/Test-PetBasicDap.mjs
node tools/Test-IntegerBasicDap.mjs
node tools/Test-Breakpoints.mjs
node tools/Test-InterruptHitsDap.mjs
node tools/Test-Memory.mjs
node tools/Test-IIeDap.mjs
node tools/Test-IIPlusDap.mjs
node tools/Test-Apple3Dap.mjs
node tools/Test-BlockMediaDap.mjs
node tools/Test-SoftCardDap.mjs
node tools/Test-SoftCard3Dap.mjs
node tools/Test-BusinessBasicDap.mjs
node tools/Test-CocoDap.mjs
node tools/Test-BbcDap.mjs
node tools/Test-AltairDap.mjs
node tools/Test-Trs80Model100Dap.mjs
node tools/Test-AtariDap.mjs
node tools/Test-AdventureDap.mjs
node tools/Test-ProjectDap.mjs
node tools/Test-NewProjectDap.mjs
node tools/Test-OffMachine.mjs
node tools/Test-FreshClone.mjs

# Additional local debug-adapter scripts (need nothing external)
node tools/Test-CycleEvents.mjs
node tools/Test-RecoveryDap.mjs

# VS Code extension grammar, language-server, and full editor + debugger suites
npm --prefix extension ci
npm --prefix extension run compile
npm --prefix extension run test:grammar
npm --prefix extension run test:language
npm --prefix extension test
```

Additional debug-adapter scripts exercise optional external media when present, such as `node tools/Test-IIDap.mjs`
(`RETROCORE_II_ROMS` and `RETROCORE_IIPLUS_ROMS`), `node tools/Test-KayproDap.mjs` (boots CP/M and MBASIC when `RETROCORE_KAYPRO` is set),
`node tools/Test-ProDosBasicDap.mjs` (uses ProDOS 2.4.3 from `tools\Fetch-M1Dependencies.ps1`), and
`node tools/Test-PascalDap.mjs`.

For working on the VS Code extension itself, `tools\Install-Extension.ps1` packages and installs a VSIX, and
`tools\Start-SelfHost.ps1` launches the in-repo extension in an isolated VS Code profile
([extension README](../extension/README.md#installing-and-self-hosting)).

Test coverage spans:

- **CPUs** against reference suites: Tom Harte's SingleStepTests (per-cycle / per-T-state bus activity), Klaus
  Dormann's 6502 functional tests, ZEXALL (all 67 exerciser groups run in parallel as individual test cases; ZEXDOC
  optional), FUSE Z80 tests, Motorola 6809 tests, and Intel 8080/8085 exercisers;
- **Machines** against their ROMs, Apple2TS (for IIe ProDOS boot and double hi-res video), and MAME oracles (for the
  Model I, Model III, Apple III, Color Computer, PET and 4040/2040 drives, BBC Micro, Atari, and SoftCard);
- **SDK ROM, DOS, and SOS sources** pinned byte for byte by SHA-256 and compared against chip or disk dumps when
  present;
- **BASIC and Pascal** against lines tokenized by the real ROMs, programs on Apple's DOS 3.3 System Master, Business
  BASIC modules, and Apple Pascal code files;
- **Assembler front ends** differentially against `ca65`/`ld65`, Merlin 32, and original Microsoft 6502 BASIC builds.

[`tests/Retrocore.Aot.Tests`](../tests/Retrocore.Aot.Tests) verifies CPU, assembler, disassembler, and machine
execution under Native AOT, and [`tests/Retrocore.Perf`](../tests/Retrocore.Perf) holds BenchmarkDotNet benchmarks.

## Frameworks, Native AOT and PGO

Runtime libraries target `.NET 10` and `.NET 11`; applications, tools, and tests target `.NET 11` only. All projects
use C# 15, with the build-only Roslyn source generator kept on `.NET Standard 2.0`.

Release Native AOT publishing favors speed over size. Native x64 binaries require an `x86-64-v3` (AVX2-class) CPU;
ARM64 keeps its own instruction baseline. Set `IlcInstructionSet` explicitly when publishing for a different CPU
baseline. On Windows, Native AOT publish requires Visual Studio's C++ build tools and the Visual Studio Installer
folder on `PATH` for `vswhere`.

`Retrocore.Debug` uses no reflection and publishes ahead of time to a single native executable that starts in about a
quarter of the time:

```powershell
dotnet publish src\Retrocore.Debug -c Release -r win-x64 -p:RetrocoreAot=true -o artifacts\aot
$env:RETROCORE_DAP_HOST = "$PWD\artifacts\aot\Retrocore.Debug.exe"; node tools/Test-Trs80Dap.mjs
```

`Retrocore.Desktop` publishes ahead of time by default:

```powershell
dotnet publish src\Retrocore.Desktop -c Release -r win-x64 -o artifacts\desktop
```

The Windows x64 Desktop AOT publish consumes its checked-in instrumented Apple IIe profile
([`Apple2-win-x64-net11.mibc`](../src/Retrocore.Desktop/Profiles/Apple2-win-x64-net11.mibc)). Set
`-p:RetrocorePgoProfile=` to measure or publish without it, or set that property to an absolute `.mibc` path to use a
different profile. Other runtime identifiers do not implicitly consume this Windows profile. To refresh it after
changes to hot code (Windows, .NET 11, PowerShell 7, Git, and `dotnet-trace` required):

```powershell
.\tools\Build-PgoTool.ps1
.\tools\Update-DesktopPgoCorpus.ps1 -PgoTool .\artifacts\pgo-tool\bin\dotnet-pgo.exe -OutputDirectory .\artifacts\pgo-training-new
```

The converter is built from pinned official runtime sources. Training generates fresh SDK DOS disks for math/string,
graphics, and active stereo Mockingboard workloads, runs the JIT application with instrumented PGO, and validates
nonempty edge/block counts before replacing the profile. The adjacent JSON records provenance.
`tools\Update-DesktopPgo.ps1` can also train one custom disk independently. Recheck normal-speed behavior before
accepting a refreshed profile; training throughput alone is not the acceptance test.

## External files

Copyrighted ROM dumps, disk images, and third-party test corpora are never committed to this repository. Tests and
scripts look for them via environment variables or under `%USERPROFILE%\Retrocore`; any test missing an external input
reports **inconclusive** rather than failing.

This folder lives outside `AppData` on purpose: packaged Windows apps virtualize `%LOCALAPPDATA%` into a private
`AppData\Local\Packages\...\LocalCache` folder, so files written by shells they launch are invisible to Explorer, VS
Code, and normal terminals.

| Variable | Holds |
| --- | --- |
| `RETROCORE_CACHE` | Base folder for cached external files (default `%USERPROFILE%\Retrocore`, shown as `<cache>` below). |
| `RETROCORE_IIE_ROMS` | Apple IIe CD, EF, and video ROM dumps. Optional for debugging (which otherwise builds from the SDK); required by `AppleSharp` and the IIe chip/oracle tests; `extension`'s full `npm test` uses them when set and otherwise ROMs built from the SDK. |
| `RETROCORE_IIPLUS_ROMS`, `RETROCORE_II_ROMS` | Apple II Plus and Apple II 2716 chip dumps (defaults `<cache>\apple2-roms\APPLE II+` and `<cache>\apple2-roms\APPLE II`); optional for debugging. |
| `RETROCORE_DISKII_ROMS` | Disk II P5/P6 chip dumps under their `apple2.org.za` names (default `<cache>\disk2-roms`). |
| `RETROCORE_SUPERDRIVE_ROMS`, `RETROCORE_MOUSE_ROMS` | Apple II 3.5 Disk Controller EPROM and AppleMouse II EPROM dumps for source comparison tests (defaults `<cache>\superdrive-roms` and `<cache>\mouse-roms`). |
| `RETROCORE_SOFTCARD_DISKS`, `RETROCORE_SOFTCARD3` | SoftCard CP/M disks for the Apple II (default `<cache>\softcard-disks`), and SoftCard /// CP/M Master disk and `softcard3.rom` for the Apple III (default `<cache>\softcard3`). |
| `RETROCORE_APPLE1_ROMS` | Apple-1 Monitor, ACI, and BASIC dumps, `wozmon.bin`, `aci.bin`, and `basic.bin` (default `<cache>\apple1-roms` for the ROM source checks); optional for debugging. |
| `RETROCORE_APPLE3_ROMS` | MAME's `apple3` set unzipped (default `<cache>\apple3-roms\mame\apple3`); optional for debugging. |
| `RETROCORE_APPLE3_DISKS`, `RETROCORE_APPLE3_UTILITIES`, `RETROCORE_APPLE3_BUSINESS_BASIC` | SOS 1.3 disk images for the Apple III tests and `Test-Apple3Dap.mjs` (defaults `<cache>\apple3-disks`, `Apple3SOS1.3SysUtils.dsk`, and `Apple3BusBasic1.23.dsk`). |
| `RETROCORE_TRS80_ROMS` | TRS-80 ROM dumps under MAME's names (default `<cache>\trs80-roms\extract`); optional for every TRS-80 Model I/III/4/4P/II, whose ROMs the SDK's sources build. |
| `RETROCORE_TRS80_DOS` | A NEWDOS/80 JV1 disk image for `tools\Test-Trs80Dap.mjs` (default `<cache>\trs80-disks\NEWDOS_80sssd_jv1.DSK`). |
| `RETROCORE_TRS80M100_ROMS` | Model 100 and Tandy 102 ROMs (`m100rom.m12` and `m102rom.m12`, or `m100.bin` and `t102.bin`; default `<cache>\trs80m100-roms` for tests); required to run either until SDK sources are written. |
| `RETROCORE_COCO_ROMS` | Color Computer ROM dumps under MAME's names (default `<cache>\coco-roms\extract`); optional for debugging. |
| `RETROCORE_BBC_ROMS` | BBC Micro ROM dumps: MAME's `bbcb` set unzipped (default `<cache>\bbc-roms\extract\bbcb` for tests); optional for debugging. |
| `RETROCORE_PET_ROMS` | MAME's `pet2001`, `pet2001n`, `pet4016`, `pet4032b`, `c4040`, and `c2040` sets unzipped, each in its folder (default `<cache>\pet-roms\extract`); optional for PET machines themselves, while the 4040 and 2040 drives use `c4040` and `c2040`. |
| `RETROCORE_ATARI_ROMS` | MAME's `a800` set unzipped (default `<cache>\atari8-roms\extract\a800`), with the 810's firmware in an `atari810` folder beside it (a PAL launch takes the folder holding `a800` and `a800pal`); optional for debugging. |
| `RETROCORE_ALTAIR_BASIC`, `RETROCORE_ALTAIR_DISK` | SIMH Altair BASIC memory/tape images and 8-inch CP/M, Disk BASIC, and Altair DOS disks plus PROM dumps for Altair tests and `Test-AltairDap.mjs` (defaults `<cache>\altair-basic` and `<cache>\altair-disk`). |
| `RETROCORE_KAYPRO` | Kaypro II dumps and disks for tests and `tools\Test-KayproDap.mjs`: `81-149c.rom`, `81-146a.bin`, `cpm22-rom149.img` (CP/M 2.2), and `MBasic.img` (default `<cache>\kaypro`). |
| `RETROCORE_KAYPRO_ROMS` | Kaypro II chip dumps for debugging in place of the SDK's builds (MAME's `kayproii` names, or the names above); optional. |
| `RETROCORE_MAME` | `mame.exe` path for the Model I, Model III, Apple III, Color Computer, PET, 4040, 2040, BBC Micro, Atari, and SoftCard oracle tests (default `<cache>\mame\mame.exe`). |
| `RETROCORE_TEST_CACHE` | Processor test suites fetched by `tools\Fetch-ProcessorTests.ps1` (~3 GiB), `tools\Fetch-Z80Tests.ps1` (~1.4 GiB), `tools\Fetch-M6809Tests.ps1`, and `tools\Fetch-I8080Tests.ps1`, all requiring `gh` and `git` (default `<cache>\processor-tests`). |
| `RETROCORE_ZEXDOC` | Set to any value to run ZEXDOC in addition to ZEXALL. Skipped by default because ZEXALL runs the same instructions and checks all flags; ZEXDOC only isolates whether a ZEXALL failure is in undocumented flags. |
| `RETROCORE_CC65`, `RETROCORE_CA65_CORPUS`, `RETROCORE_CA65_ASMINC` | Directory containing `ca65` and `ld65`, optional `rom4x` ca65 source corpus, and `cc65`'s `asminc` header directory for the ca65 differential and SDK tests. |
| `RETROCORE_MERLIN32`, `RETROCORE_MERLIN_CORPUS` | Merlin 32 executable and approved source corpus for the Merlin differential tests. |
| `RETROCORE_VSCODE` | VS Code executable (`Code.exe` on Windows) for the extension's editor tests; unset, they download a pinned VS Code. |

`tools\Fetch-M1Dependencies.ps1` populates `<cache>\m1-dependencies` with `cc65` (compiled locally with Visual Studio's
C++ tools), ProDOS 2.4.3, Microsoft's 6502 BASIC source and `msbasic` reference binaries, and pinned Apple2TS sources.
`tools\Fetch-Trs80Font.ps1` fetches xtrs's font source to verify
[`CharacterGeneratorKit.asm`](../src/Retrocore.Machines.Trs80/Roms/CharacterGeneratorKit.asm).

## Projects

| Project | What it holds |
| --- | --- |
| [`Retrocore.Core`](../src/Retrocore.Core) | Shared instruction-set (`Isa`), CPU, bus, machine/device abstractions, and common chip models (6845 CRTC, 6560 VIC, 6821 PIA, 6522 VIA, 6532 RIOT, 6530 MIOT, 8155 PIO, 6850 ACIA, POKEY, SN76489, HD44102, uPD1990AC). |
| [`Retrocore.Cpu.I8080`](../src/Retrocore.Cpu.I8080) | State-exact Intel 8080 and 8085, with the 8085's interrupts, `RIM`/`SIM`, and undocumented instructions and flags ([instruction set](../src/Retrocore.Cpu.I8080/I8080Isa.txt)). |
| [`Retrocore.Cpu.M6502`](../src/Retrocore.Cpu.M6502) | Cycle-exact 6502 family: NMOS 6502, WDC 65C02, and Rockwell 65C02 ([opcode tables](../src/Retrocore.Cpu.M6502/OpcodeTables.txt)). |
| [`Retrocore.Cpu.M6809`](../src/Retrocore.Cpu.M6809) | Cycle-exact Motorola MC6809 with indexed postbytes, interrupts, and `SYNC`/`CWAI` ([instruction set](../src/Retrocore.Cpu.M6809/M6809Isa.txt)). |
| [`Retrocore.Cpu.Z80`](../src/Retrocore.Cpu.Z80) | T-state-exact Z80 with undocumented flags and MEMPTR ([instruction set](../src/Retrocore.Cpu.Z80/Z80Isa.txt)). |
| [`Retrocore.Assembler`](../src/Retrocore.Assembler) | Multi-dialect assembler (native, ca65, Merlin, MACRO-10), ld65-style linker, disassembler, flow analysis, and `;;` documentation parser. |
| [`Retrocore.Basic`](../src/Retrocore.Basic) | Apple, TRS-80, Color Computer, PET, BBC Micro, Atari, Model 100, and CP/M BASICs, plus shared Microsoft 6502 BASIC modules: tokenizers, listings, label-based source compilation, diagnostics, expression evaluation, renumbering, tokenized files, and tapes. |
| [`Retrocore.Pascal`](../src/Retrocore.Pascal) | Apple Pascal p-code, disassembler, decompiler, compiler-listing mapping, p-machine runtime state on the Apple II and Apple III, and SDK Pascal and interpreter sources ([`Sdk/`](../src/Retrocore.Pascal/Sdk)). |
| [`Retrocore.Media`](../src/Retrocore.Media) | Disk, tape, and block media: WOZ, DOS 3.3 and 3.2 (`.dsk`, `.do`, `.d13`), ProDOS block images, SOS and Apple Pascal volumes, sector floppies (DMK, IMD, raw images, JV1, JV3, JVC), Commodore D64/D67/G64/TAP, Acorn SSD/DSD/UEF, Atari ATR/XFD, and CAS/WAV tapes. |
| [`Retrocore.Input`](../src/Retrocore.Input) | SDL3 game controller discovery and polling, mapped to emulated joysticks and paddles. |
| [`Retrocore.Machines.Chips`](../src/Retrocore.Machines.Chips) | Western Digital FD1771 and FD179x floppy disk controllers and drives, and Z80 PIO, SIO, CTC, and DMA peripherals. |
| [`Retrocore.Machines.Apple1`](../src/Retrocore.Machines.Apple1) | Apple-1: 6821 PIA, video terminal, keyboard, Apple Cassette Interface, and SDK ROM sources. |
| [`Retrocore.Machines.Apple2`](../src/Retrocore.Machines.Apple2) | Apple II, II Plus, and IIe (original and enhanced), peripheral cards (Disk II, Mockingboard, Mouse, SmartPort/3.5, ProFile, Z80 SoftCard), and SDK ROM and DOS sources. |
| [`Retrocore.Machines.Apple3`](../src/Retrocore.Machines.Apple3) | Apple III: banked bus and extended addressing, video, keyboard, clock, serial, Disk III, ProFile, SoftCard III, and SDK boot ROM, SOS 1.3, and Business BASIC sources. |
| [`Retrocore.Machines.Trs80`](../src/Retrocore.Machines.Trs80) | TRS-80 Model I (with Expansion Interface and doublers), Model III/4/4P, Model II/12/16 (Z80 side), and SDK ROM sources. |
| [`Retrocore.Machines.Trs80Model100`](../src/Retrocore.Machines.Trs80Model100) | TRS-80 Model 100 and Tandy 102: 80C85 memory and ports, HD44102 LCD drivers, keyboard matrix, uPD1990AC clock, cassette, buzzer, and RAM-image file exchange. |
| [`Retrocore.Machines.Coco`](../src/Retrocore.Machines.Coco) | TRS-80 Color Computer 1, 2, and 3: SAM, VDG, GIME, PIAs, cassette, sound, cartridges, disk controller, and SDK ROM sources. |
| [`Retrocore.Machines.Acorn`](../src/Retrocore.Machines.Acorn) | BBC Micro Model B and Model A: paged ROMs, VIAs, video ULA and SAA5050, sound, serial ULA and cassette, Intel 8271, and SDK ROM sources. |
| [`Retrocore.Machines.Commodore`](../src/Retrocore.Machines.Commodore) | Commodore PET 2001 and 4032: PIAs and VIA, video, keyboards, sound, Datasettes, IEEE-488 bus with 4040/2040 dual drives, and SDK ROM sources. |
| [`Retrocore.Machines.Atari`](../src/Retrocore.Machines.Atari) | Atari 400 and 800: ANTIC, GTIA/CTIA, POKEY, PIA, cartridges, SIO bus with 410 recorder and hardware-level 810 drive, and SDK ROM sources. |
| [`Retrocore.Machines.Altair`](../src/Retrocore.Machines.Altair) | MITS Altair 8800: 88-2SIO/88-SIO serial cards, 88-ACR cassette, front panel, 88-DCDD 8-inch drives, and DBL/MBL boot PROM sources. |
| [`Retrocore.Machines.Kaypro`](../src/Retrocore.Machines.Kaypro) | Kaypro II: banked memory, Z80 PIO/SIO, serial keyboard, 80x24 video, FD1793 drives, and monitor, font, and MBASIC 5.21 SDK sources. |
| [`Retrocore.Debug`](../src/Retrocore.Debug) | Combined debug adapter (DAP), assembly/BASIC/Pascal language server, `retrocore build` / `new` / `init` project commands, and `--assemble` / `--basic` / `--dos` / `--pascal` / `--model100` / `--disassemble` CLI (packs as the `retrocore` .NET tool). |
| [`Retrocore.Desktop`](../src/Retrocore.Desktop) | Standalone Native AOT Avalonia + SDL3 desktop emulator for the full machine catalog, sharing the extension's Machine, Drives, and Display & Sound views. |
| [`AppleSharp`](../src/AppleSharp) | Minimal standalone SDL3 Native AOT desktop emulator for the Apple IIe (uses caller-supplied ROM dumps). |
| [`Retrocore.Generators`](../src/Retrocore.Generators) | Roslyn source generators that compile instruction-set descriptions and `.rom.asm` sources into C# tables. |
| [`tools/DosDisk`](../tools/DosDisk) | CLI tool that builds bootable DOS 3.3 and 3.2 disk images from the SDK's DOS sources and a folder of files ([Dos.md](Dos.md#building-disks)). |
| [`sdk/1`](../sdk/1/README.md) | Target headers (`<cpu.inc>`, `<machine.inc>`, `<environment.inc>`), `RC_*` defines, checked memory maps, and [`templates/`](../sdk/1/templates/README.md) for multi-target `retrocore.json` projects. |
| [`extension`](../extension) | VS Code extension: assembly, BASIC, and Pascal language features, debugging, live machine display, and Machine and Drives views. |

## SDK system and ROM sources

All system and ROM sources in the repository are maintained by hand. Automated tests pin every build by SHA-256 so CI
verifies byte identity on every change, and also compare byte for byte against chip or disk dumps when external files
are configured.

| Platform | Sources | Covers |
| --- | --- | --- |
| Apple-1 | [`WozMonitor.asm`](../src/Retrocore.Machines.Apple1/Roms/WozMonitor.asm), [`Aci.asm`](../src/Retrocore.Machines.Apple1/Roms/Aci.asm), [`CharacterGenerator.asm`](../src/Retrocore.Machines.Apple1/Roms/CharacterGenerator.asm), [`Basic/Basic.asm`](../src/Retrocore.Machines.Apple1/Roms/Basic/Basic.asm) | Woz Monitor (`$FF00`–`$FFFF`), Apple Cassette Interface PROM (`$C100`–`$C1FF`), Signetics 2513 character generator, and Apple-1 BASIC (`$E000`–`$EFFF`). |
| Apple II family | [`Monitor.asm`](../src/Retrocore.Machines.Apple2/Roms/System/Monitor.asm), [`Firmware.Original.asm`](../src/Retrocore.Machines.Apple2/Roms/System/Firmware.Original.asm), [`Firmware.Enhanced.asm`](../src/Retrocore.Machines.Apple2/Roms/System/Firmware.Enhanced.asm), [`CharacterGenerator.asm`](../src/Retrocore.Machines.Apple2/Roms/System/CharacterGenerator.asm), [`IIeEquates.asm`](../src/Retrocore.Machines.Apple2/Roms/System/IIeEquates.asm), [`MonitorEntries.asm`](../src/Retrocore.Machines.Apple2/Roms/System/MonitorEntries.asm) | Original, Autostart, and IIe Monitors (`$F800`–`$FFFF`), IIe `$C100`–`$CFFF` firmware, character/video ROMs (including MouseText), and shared equates/entry headers. |
| Apple II BASICs & utilities | [`AppleSoft.asm`](../src/Retrocore.Machines.Apple2/Roms/AppleSoft/AppleSoft.asm) / [`applesoft.mac`](../src/Retrocore.Machines.Apple2/Roms/AppleSoft/applesoft.mac), [`IntegerBasic.asm`](../src/Retrocore.Machines.Apple2/Roms/IntegerBasic/IntegerBasic.asm), [`ProgrammersAid.asm`](../src/Retrocore.Machines.Apple2/Roms/ProgrammersAid/ProgrammersAid.asm) | AppleSoft II (native modules sharing [`Microsoft6502Basic/`](../src/Retrocore.Basic/Roms/Microsoft6502Basic), plus the MACRO-10 overlay over `m6502.asm`), Integer BASIC (with floating-point, Mini-Assembler, and SWEET16), and Programmer's Aid #1. |
| Apple II storage & cards | [`Boot16.asm`](../src/Retrocore.Machines.Apple2/Roms/DiskII/Boot16.asm), [`Sequencer16.asm`](../src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer16.asm), [`Boot13.asm`](../src/Retrocore.Machines.Apple2/Roms/DiskII/Boot13.asm), [`Sequencer13.asm`](../src/Retrocore.Machines.Apple2/Roms/DiskII/Sequencer13.asm), [`Dos33.asm`](../src/Retrocore.Machines.Apple2/Roms/Dos/Dos33.asm), [`Dos32.asm`](../src/Retrocore.Machines.Apple2/Roms/Dos/Dos32.asm), [`Slot7.rom.asm`](../src/Retrocore.Machines.Apple2/Roms/Slot7.rom.asm), [`Disk35.rom.asm`](../src/Retrocore.Machines.Apple2/Roms/Disk35.rom.asm), [`Disk35Controller.asm`](../src/Retrocore.Machines.Apple2/Roms/Disk35/Disk35Controller.asm), [`ProFile.rom.asm`](../src/Retrocore.Machines.Apple2/Roms/ProFile.rom.asm), [`Mouse.rom.asm`](../src/Retrocore.Machines.Apple2/Roms/Mouse.rom.asm) | Disk II 16- and 13-sector boot ROMs and state sequencers ([DiskII.md](DiskII.md)), Apple DOS 3.3 and 3.2 ([Dos.md](Dos.md)), slot-7 ProDOS block ROM, Apple II 3.5 Disk Controller slot ROM and 341-0438-A EPROM, ProFile card ROM, and Mouse card ROM. |
| Apple III | [`BootRom.asm`](../src/Retrocore.Machines.Apple3/Roms/BootRom.asm), [`SosKernel.asm`](../src/Retrocore.Machines.Apple3/Roms/Sos/SosKernel.asm), [`SosBoot.asm`](../src/Retrocore.Machines.Apple3/Roms/Sos/SosBoot.asm), [`Sos/Drivers/`](../src/Retrocore.Machines.Apple3/Roms/Sos/Drivers), [`BusinessBasic.asm`](../src/Retrocore.Machines.Apple3/Roms/BusinessBasic/BusinessBasic.asm), [`SoftCard3Prom.asm`](../src/Retrocore.Machines.Apple3/Roms/SoftCard3Prom.asm) | Apple III `$F000`–`$FFFF` boot ROM, SOS 1.3 kernel, boot loader, and drivers ([Sos.md](Sos.md)), Business BASIC 1.23/1.3 ([BusinessBasic.md](BusinessBasic.md)), and SoftCard III PROM. |
| Apple Pascal | [`src/Retrocore.Pascal/Sdk/`](../src/Retrocore.Pascal/Sdk) | Apple Pascal p-machine interpreter, system, and 1.3 compiler SDK sources ([Pascal.md](Pascal.md)). |
| TRS-80 Models I, III, 4, and II | [`Level2.asm`](../src/Retrocore.Machines.Trs80/Roms/Level2.asm), [`Level1.asm`](../src/Retrocore.Machines.Trs80/Roms/Level1.asm), [`CharacterGenerator.asm`](../src/Retrocore.Machines.Trs80/Roms/CharacterGenerator.asm), [`CharacterGeneratorKit.asm`](../src/Retrocore.Machines.Trs80/Roms/CharacterGeneratorKit.asm), [`Model3.asm`](../src/Retrocore.Machines.Trs80/Roms/Model3.asm), [`Model4PBoot.asm`](../src/Retrocore.Machines.Trs80/Roms/Model4PBoot.asm), [`Model2Boot.asm`](../src/Retrocore.Machines.Trs80/Roms/Model2Boot.asm), [`Model3CharacterGenerator.asm`](../src/Retrocore.Machines.Trs80/Roms/Model3CharacterGenerator.asm), [`Model2CharacterGenerator.asm`](../src/Retrocore.Machines.Trs80/Roms/Model2CharacterGenerator.asm) | Model I Level II (1.2/1.3) and Level I BASIC and fonts (stock and lowercase kit), Model III/4 ROMs and Level I, Model 4P boot ROM, Model II boot ROMs (versions 1, 2, 3, and 5), and character generators. |
| TRS-80 Color Computer | [`ColorBasic.asm`](../src/Retrocore.Machines.Coco/Roms/ColorBasic.asm), [`ExtendedBasic.asm`](../src/Retrocore.Machines.Coco/Roms/ExtendedBasic.asm), [`DiskBasic.asm`](../src/Retrocore.Machines.Coco/Roms/DiskBasic.asm), [`Coco3.asm`](../src/Retrocore.Machines.Coco/Roms/Coco3.asm) | Color BASIC 1.0–1.3, Extended Color BASIC 1.0–1.1, Disk Extended Color BASIC 1.0–1.1, and the CoCo 3's Extended Color BASIC 2.0 / Super Extended BASIC ROM. |
| BBC Micro | [`Mos.asm`](../src/Retrocore.Machines.Acorn/Roms/Mos.asm), [`BbcBasic.asm`](../src/Retrocore.Machines.Acorn/Roms/BbcBasic.asm), [`Dnfs.asm`](../src/Retrocore.Machines.Acorn/Roms/Dnfs.asm), [`Saa5050.asm`](../src/Retrocore.Machines.Acorn/Roms/Saa5050.asm) | MOS 1.20, BBC BASIC II, DNFS 1.20 (Acorn DFS and Econet), and SAA5050 teletext character ROM. |
| Commodore PET | [`Basic1.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic/Basic1.asm), [`Basic2.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic/Basic2.asm), [`Basic4.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic/Basic4.asm), [`Editor1.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic1/Editor1.asm)–[`Kernal4.asm`](../src/Retrocore.Machines.Commodore/Roms/Basic4/Kernal4.asm), [`CharacterGenerator.asm`](../src/Retrocore.Machines.Commodore/Roms/CharacterGenerator.asm) | PET BASIC 1, 2, and 4 (sharing Microsoft 6502 BASIC modules with AppleSoft; MACRO-10 overlays remain selectable), screen editors, kernals, machine-language monitor, and 901447-08/-10 character ROMs (plus [`Vic20/`](../src/Retrocore.Machines.Commodore/Roms/Vic20) BASIC, Kernal, and character ROM sources). |
| Atari 400 and 800 | [`Os.asm`](../src/Retrocore.Machines.Atari/Roms/Os.asm), [`FloatingPoint.asm`](../src/Retrocore.Machines.Atari/Roms/FloatingPoint.asm), [`AtariBasic.asm`](../src/Retrocore.Machines.Atari/Roms/AtariBasic.asm), [`Atari810.asm`](../src/Retrocore.Machines.Atari/Roms/Atari810.asm), [`ExecutableLoader.rom.asm`](../src/Retrocore.Machines.Atari/Roms/ExecutableLoader.rom.asm) | Atari OS (rev. A, rev. B, and PAL), floating-point package, Atari BASIC (rev. A, B, and C), 810 disk drive firmware (rev. B and C), and `.xex` loader. |
| MITS Altair 8800 | [`Dbl.asm`](../src/Retrocore.Machines.Altair/Roms/Dbl.asm), [`Mbl.asm`](../src/Retrocore.Machines.Altair/Roms/Mbl.asm) | Disk Boot Loader (DBL) and Multi-Boot Loader (MBL) PROMs. |
| Kaypro II | [`Kaypro2.asm`](../src/Retrocore.Machines.Kaypro/Roms/Kaypro2.asm), [`Kaypro2CharacterGenerator.asm`](../src/Retrocore.Machines.Kaypro/Roms/Kaypro2CharacterGenerator.asm), [`Mbasic.asm`](../src/Retrocore.Machines.Kaypro/Roms/Mbasic/Mbasic.asm) | Monitor ROM 81-149C, character generator 81-146A, and CP/M MBASIC 5.21 (`MBASIC.COM`). |
