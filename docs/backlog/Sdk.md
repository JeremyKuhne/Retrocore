# Backlog: the Retrocore SDK for writing retro software

A project written for one CPU family that builds for, and debugs on, every machine of that family that Retrocore
emulates. Retrocore gives each target its headers and defines, places the program in that target's free memory, and
F5 in VS Code debugs whichever target is active. A repository that develops with Retrocore is set up, built and run in
CI the same way every time.

The first project built this way is an assembly-language interpreter for Scott Adams adventures, with Pirate Adventure
as its game. It builds for the Apple-1, the Apple II, the Apple III, the Commodore PET and the BBC Micro.

**Status:** proposed 2026-11-16 and revised the same day after walking through its open questions. Revised again
2026-11-25 against main, once the PET and BBC Micro had landed. Nothing here is built. The
[decisions](#decisions-agreed-2026-11-16) were agreed on 2026-11-16, with [corrections](#revised-2026-11-25) on
2026-11-25.

**What it builds on:** the [Commodore PET](../Pet.md) and the [BBC Micro](../BbcMicro.md) are Retrocore machines now,
and every ROM they run is an SDK source, except the PET's 4040 and 2040 disk drives, whose ROMs must be dumps. Phases
1 to 3 can start on main as it is. The starting environments need the [media writers](#media-writers) first.

- [What there is](#what-there-is)
- [Setting up a repository](#setting-up-a-repository)
- [The project](#the-project)
- [Targets](#targets)
- [Headers and defines](#headers-and-defines)
- [Memory maps](#memory-maps)
- [Building](#building)
- [Debugging in VS Code](#debugging-in-vs-code)
- [The first sample: a Scott Adams interpreter](#the-first-sample-a-scott-adams-interpreter)
- [Dialects](#dialects)
- [Languages](#languages)
- [Versions of the SDK](#versions-of-the-sdk)
- [Tests](#tests)
- [Phases](#phases)
- [Decisions](#decisions-agreed-2026-11-16)
- [Open questions](#open-questions)

## What there is

| Piece | What it does today |
| --- | --- |
| [`.include <file>`](../NativeAssembly.md#includes) | Looks only in the host's SDK paths; `.include "file"` looks beside the source, then in the include paths. |
| [Predefined symbols](../NativeAssembly.md#symbols) | A host sets constants before the source runs; the SDK's ROM sources already pick variants with `.ifndef ENHANCED`. |
| [`AssemblyProject`](../../src/Retrocore.Assembler/Assembler/AssemblyProject.cs) and ld65-style linker configurations | Several sources, sections placed by memory region, BSS. |
| A launch's `source`, `dialect`, `linkerConfiguration`, `loadAddress` | Assembles one source in the debug host for one `machine` and debugs it from its source map. |
| [`AssembleCommand`](../../src/Retrocore.Debug/AssembleCommand.cs) | `Retrocore.Debug --assemble` writes a binary and a cc65 `.dbg` outside a debug session, with `--dialect`, `--cpu`, `--origin`, `--config` and `--define NAME=value`. It knows no machine or target. |
| `.cpu` and ca65's `.setcpu` | A 65C02-only opcode under `.cpu Mos6502` is an error. A source's own `.cpu` replaces the launch's CPU without a check. |
| The linker | ld65's `MEMORY`, `SEGMENTS`, `SYMBOLS` and `FEATURES`, with `define` and `fill`. A segment that overflows its region and sections that overlap are errors. Nothing knows a machine's reserved areas. |
| `.incbin` | Inserts a file's bytes, from a resolver that reads binary files. |
| The SDK's ROM sources | Every ROM of every machine except the PET's disk drives: the Apple-1's, the Apple II's and IIe's, the Apple III's boot ROM and SOS 1.3, the PET's BASIC, editor and Kernal, the BBC Micro's MOS, BASIC II and DNFS, the TRS-80s', the Color Computer's, the Atari's, all with labels and `;;` contracts in the [maintained style](../AssemblyStyle.md). |
| Entries and equates files | Already most of a header: [`MonitorEntries.asm`](../../src/Retrocore.Machines.Apple2/Roms/System/MonitorEntries.asm), [`IIeEquates.asm`](../../src/Retrocore.Machines.Apple2/Roms/System/IIeEquates.asm), [`FirmwareEquates.asm`](../../src/Retrocore.Machines.Apple2/Roms/System/FirmwareEquates.asm), [`Apple3Equates.asm`](../../src/Retrocore.Machines.Apple3/Roms/Apple3Equates.asm), [`BfmEquates.asm`](../../src/Retrocore.Machines.Apple3/Roms/Sos/Kernel/BfmEquates.asm), [`PetEquates.asm`](../../src/Retrocore.Machines.Commodore/Roms/PetEquates.asm), [`MosEntries.asm`](../../src/Retrocore.Machines.Acorn/Roms/MosEntries.asm) and [`MosEquates.asm`](../../src/Retrocore.Machines.Acorn/Roms/MosEquates.asm). An entries file's names inherit the ROM's documentation and repeat its `Also:` names ([ConvertingSources.md](../ConvertingSources.md)). They ship in the host's `Sdk/` folder. |
| Historical and deprecated names | `;; Also:` lets an old name assemble as an alias of the new one, and a `Deprecated:` section makes the editor warn at each use. The command-line build prints no deprecation warnings. |
| [`SdkModules`](../../src/Retrocore.Debug/SdkModules.cs) and the other SDK module classes | Assemble those sources in the debug host and map them onto whatever ROM is running. |
| [`SdkIndex`](../../src/Retrocore.Debug/Language/SdkIndex.cs) | The language server's analysis of every SDK source, behind hover, completion and go to definition. It is global: one `Sdk/` root, with no per-target view. |
| A launch's `dos: "3.3"` | On the Apple II, builds DOS 3.3 from its SDK source and puts the program on a fresh disk as a B file with a `HELLO` that BRUNs it ([`Apple2DebugTarget.cs`](../../src/Retrocore.Debug/Apple2DebugTarget.cs)). |
| Media writers | [`DosDisk.Create`](../../src/Retrocore.Media/Apple/DosDisk.cs) with any list of files; [`SosVolumeBuilder`](../../src/Retrocore.Media/Apple/SosVolumeBuilder.cs) for SOS volumes and their files; [`Apple1Tape`](../../src/Retrocore.Machines.Apple1/Apple1Tape.cs) to ACI WAV; [`WozMonitorHex`](../../src/Retrocore.Machines.Apple1/WozMonitorHex.cs) for the Woz Monitor's typed-in hex; [`CommodoreTapeBuilder`](../../src/Retrocore.Media/Commodore/CommodoreTapeBuilder.cs) and `TapFormat` for PET tapes; [`AcornDfsDisk`](../../src/Retrocore.Media/Acorn/AcornDfsDisk.cs) for DFS `.ssd` disks, their files, title, boot option and `!BOOT`; [`AcornTapeBuilder.BuildUef`](../../src/Retrocore.Media/Acorn/AcornTapeBuilder.cs) for UEF tapes of files. |

What is missing:

- a project that names its targets, and a build of it that runs outside the editor;
- a published `retrocore` .NET tool: the debug host packs as one, but no preview build ships it;
- per-target SDK roots: every host searches the one `Sdk/` folder;
- headers that describe each target to the program, and `RC_` defines;
- user-set symbols outside `--assemble`: the debug launch and the language server pass none;
- a check that a source's `.cpu` stays within its target's CPU, and a language server that knows the target's CPU
  (it starts every file at the 6502);
- memory maps of each machine's reserved areas;
- a way to choose the target in VS Code: there is no status-bar item, F5 with no launch.json opens VS Code's own
  debugger picker, and the language server has no channel for a target's settings;
- the [media writers](#media-writers) four of the five starting targets need;
- a documented way to start a repository.

Each launch configuration is written by hand today, one machine at a time, or saved from Start Machine.

## Setting up a repository

The workflow a developer follows, and the one this plan's sample is built with:

1. **Create it.** Run *Retrocore: New Project* in VS Code, or:

   ```text
   dotnet new tool-manifest
   dotnet tool install retrocore
   dotnet retrocore new 6502 adventure --machines apple1,apple2,apple3,pet,bbc
   ```

   Both use the same templates. You pick a CPU family and tick its machines, and each machine becomes a target with
   its usual environment ([targets](#targets)). `retrocore init` adds a project to an existing repository instead.

2. **What it writes:**

   ```text
   adventure/
     retrocore.json                 the project, its targets and steps
     src/main.s                     a hello world that builds for every target
     src/platform/<family>/         each family's console layer, started for you
     .config/dotnet-tools.json      retrocore, pinned
     .vscode/extensions.json        recommends the Retrocore extension
     .gitignore                     artifacts/ and obj/
     .github/workflows/build.yml    restores the tool and builds every target
     README.md                      how to build, debug and add a target
   ```

3. **Build.** `dotnet retrocore build --all` builds every target into `artifacts/<target>/`, and
   `--target apple2-dos` builds just one.

4. **Debug.** Open the folder in VS Code and pick the target in the status bar (`adventure · apple2-dos ▾`). F5
   builds it, starts its machine and stops at the entry point. No launch.json is needed.

5. **CI.** The generated workflow sets up .NET, runs `dotnet tool restore`, and runs `dotnet retrocore build --all`,
   keeping each target's disk or tape image as a build artifact. Running the tests under emulation (`retrocore test`)
   comes later.

**Delivery.** `retrocore` is a .NET tool carrying the SDK majors it supports. A repository pins its version in
`.config/dotnet-tools.json`, so everyone, CI included, builds with the same tool and headers. The VS Code extension
uses the repository's pinned tool when there is one and its own bundled copy otherwise, and it says so when the two
differ. Retrocore is not published yet, so the tool and the extension need preview builds first. Until then the
workflow runs from a local build of this repository.

## The project

A repository has one `retrocore.json` at its root. It is either a single project, or it lists the folders of its
projects, each with its own `retrocore.json`. VS Code finds the root by this file, and the active target is chosen per
project. The language server, the debug host and `retrocore build` all read it, and its JSON schema gives completion
and validation in VS Code.

```jsonc
// retrocore.json at the root of a repository with several projects
{ "projects": ["interpreter", "tools/editor"] }
```

```jsonc
// a project
{
  "sdk": "1",
  "name": "adventure",
  "cpu": "6502",
  "sources": ["src/core/*.s"],
  "steps": [
    { "tool": "tools/packer.cs", "args": ["pack", "${in}", "${out}"], "in": "games/pirate.dat", "out": "${obj}/pirate.bin" }
  ],
  "targets": {
    "apple1-wozmon": { "machine": "apple1", "environment": "wozmon", "options": { "ramKilobytes": 32 },
                       "defines": { "GAME_LINKED": 1 } },
    "apple2-dos":    { "machine": "apple2-iiplus", "environment": "dos33" },
    "apple3-sos":    { "machine": "apple3", "environment": "sos" },
    "pet-basic":     { "machine": "pet4032", "environment": "basic", "defines": { "GAME_LINKED": 1 } },
    "bbc-dfs":       { "machine": "bbcb", "environment": "dfs" }
  }
}
```

| Field | Meaning |
| --- | --- |
| `projects` | In a root file only: the folders of the repository's projects. |
| `sdk` | The SDK's major version the project is written against ([versions](#versions-of-the-sdk)). |
| `cpu` | The baseline the code must keep to. A target can raise it (`65c02` on an enhanced IIe), never lower it. |
| `sources` | Files or globs. An entry can be an object with `path`, `dialect` and, later, `kind` ([languages](#languages)). |
| `steps` | Host-side build steps that run before assembly ([building](#building)). |
| `defines` | Project-wide symbols, added to the SDK's own. |
| `targets` | Named targets: `machine` (as Start Machine lists it), `environment`, and optionally `cpu`, `options` (the machine's launch options), `cards`, `defines`, `sources` added for this target only, `linkerConfiguration`, `memoryMap` overrides, `files` (data files put beside the program on its disk), `bootImage`, `image`, and `machineFile` once [machine files](MachineFiles.md) exist. |
| `entry` | The entry point's label; defaults to the first byte the project's own sources emit, after the platform folders' code. |

A target's `machine` is a machine as the extension's catalog names it ([`machines.ts`](../../extension/src/machines.ts)),
the same names Start Machine and favorites use: `apple1`, `apple2-iiplus`, `apple3`, `pet2001-basic2`, `pet4032`,
`bbcb` and the rest. The build maps it to the launch's `machine` and `model`, as `startFlow.ts` does today.

**Sources for each target.** Besides `sources`, every target gets its family's folder `src/platform/<family>/`,
then its model's folder `src/platform/<model>/`, then its environment's folder `src/platform/<environment>/`. A later
folder's file replaces an earlier one's of the same name, so `platform/apple2-iie/console.s` replaces
`platform/apple2/console.s` on IIe targets, and `platform/dos33/` can add the code that loads a game's data from the
disk. The platform folders assemble
first, then `sources`, then a target's own `sources`: the shared code builds on the platform, whose constants (a
screen's width for a `.res`) and zero-page locations must be known before it. Most projects need no per-target
lists.

Build output goes to `artifacts/<target>/` and intermediate files to `obj/<target>/` (`${obj}`), unless `output` says
otherwise.

## Targets

A target is a **machine × environment**. The machine decides the hardware and its ROMs. The environment decides how
the program is loaded and started, the file it is built as, which memory it may use, and which system calls it may
make.

| Environment | Machines | System calls | Built as |
| --- | --- | --- | --- |
| `bare` | all | the ROM's routines only | a raw binary, loaded straight into RAM |
| `wozmon` | the Apple-1 | the Woz Monitor | Woz Monitor hex text to type in, and an ACI tape (WAV) |
| `dos33` | the Apple II, II Plus and IIe | DOS 3.3's file manager and RWTS, and the Monitor | a B file on a DOS 3.3 disk whose `HELLO` BRUNs it |
| `prodos` | the Apple II Plus with 64K, and the IIe | the ProDOS MLI | a SYS file at `$2000`, or a BIN file with its aux type |
| `sos` | the Apple III | SOS calls (`BRK`, a call number, its parameters) | a `SOS.INTERP` on a boot disk with the SDK's SOS 1.3 kernel and drivers |
| `basic` | the PET | the Kernal and BASIC | a PRG with a BASIC `SYS` line, on a TAP tape; also on a 4040 disk when the drive's ROM dumps are found |
| `dfs` | the BBC Micro | the MOS (`OSWRCH`, `OSRDCH`, `OSFILE`, …) | a `*RUN` file on a DFS disk (`.ssd`) whose `!BOOT` runs it, and a UEF tape of the same files |
| `cpm` | the Apple II and IIe with a SoftCard, the Model 4, the Altair, the Kaypro II | the BDOS at `$0005` | a `.COM` file at `$0100` |
| `level2` | the Model I and III | Level II's routines | a SYSTEM tape (CAS) |
| `trsdos` | the Model I, III and 4 | TRSDOS, LDOS and LS-DOS SVCs | a `/CMD` load module |
| `colorbasic`, `diskbasic` | the Color Computer 1, 2 and 3 | Color BASIC's and Disk BASIC's routines | a DECB `.BIN` for `LOADM`, on a CAS tape or a JVC disk |

The first five starting targets use `wozmon`, `dos33`, `sos`, `basic` and `dfs`. The rest follow.

**CPU compatibility** follows supersets. A `6502` project can target 65C02 machines, and an `8080` project can target
the Altair and Z80 machines (the Model 4, the Kaypro II, or a SoftCard under CP/M). A `z80` or `65c02` project cannot
target a machine whose CPU lacks its instructions. Each build starts at the target's CPU, as a launch does today. The
assembler already rejects a 65C02 opcode under `.cpu Mos6502`. What is new is that a `.cpu` in the source naming a CPU
the target lacks is an error naming the target, where today it silently replaces the launch's CPU.

**Boot media.** An environment whose system is an SDK source boots with nothing external: DOS 3.3, SOS, DFS, and
the ROM environments. The SDK lists the known images of every other environment (title, version, SHA-256), such as
ProDOS, CP/M and TRSDOS, and the dumps a device needs, such as the PET's 4040 ROMs. A PET target therefore builds
its tape by default, which runs from SDK sources alone, and adds a disk only when the 4040's dumps are found. The build and F5 look for them by hash
in the user's [libraries](MachineFiles.md#libraries) and `RETROCORE_CACHE`. A target can name one with `bootImage`.
When none is found, the error names the image, says where to put it, and offers a Fetch command where a legal source
exists, as `Fetch-M1Dependencies.ps1` does for ProDOS 2.4.3.

## Headers and defines

Each build adds its target's folder of headers to the SDK paths, before the shared `Sdk/` root the hosts search today,
so the same includes resolve to that target's files:

```asm
.include <cpu.inc>          ; the CPU family's macros
.include <machine.inc>      ; the machine's hardware and ROM entry points
.include <environment.inc>  ; the environment's calls and conventions
```

Each header includes its family's common header first (the IIe's includes the Apple II's), so a name means the same
thing on every machine that has it.

**What comes from where.**

- **ROM entry points come from the entries files the SDK already has.** At first a machine's header includes them:
  `MonitorEntries.asm` and `IIeEquates.asm` on the Apple II, `MosEntries.asm` and `MosEquates.asm` on the BBC Micro,
  `PetEquates.asm` on the PET, `Apple3Equates.asm` on the Apple III. Their names inherit the ROMs'
  documentation, so hover in a project shows the Monitor's own documentation of `COUT`, and their `Also:` names
  keep the period names working.
- **Generated headers come later**, where a machine has no entries file or its file covers too little. They reuse
  the source generator's walk of a ROM's exports and their documentation
  ([`RomAssemblyGenerator`](../../src/Retrocore.Generators/RomAssemblyGenerator.cs), `ExportDocumentation`) to emit
  native `.inc` text instead of C#. Either way the names cannot drift from the ROMs, because they come from the same
  sources.
- **A header includes only what a program may use.** An entries file can name workspace a ROM keeps to itself. The
  header leaves that out, or marks it, rather than including the ROM's whole equates.
- **Hardware equates are written by hand** where no equates file has them, such as the PET's VIA. Tests check them
  against the emulator's device maps.
- **Environment headers are written by hand**: the SOS call macro and its parameter lists (from `BfmEquates.asm` and
  the SOS sources), the MLI call macro, the BDOS function numbers, the DOS 3.3 vectors at `$03D0`.
- **The headers follow the [style guide](../AssemblyStyle.md)** and its strict lint, as every SDK source does, and
  `SdkDocumentationTests` covers them as it covers the rest.

**Defines.** Every build predefines these, so `.if` and `.ifdef` can choose code by target:

| Symbol | Example | Value |
| --- | --- | --- |
| `RC_SDK` | `RC_SDK = 1` | the SDK's major version |
| `RC_CPU_<cpu>` | `RC_CPU_65C02` | 1 for the target's CPU and every CPU it is a superset of |
| `RC_MACHINE_<family>` | `RC_MACHINE_APPLE2` | 1 for the machine's family |
| `RC_MODEL_<machine>` | `RC_MODEL_APPLE2_IIE_ENHANCED` | 1 for the exact machine, by its catalog id |
| `RC_ENV_<environment>` | `RC_ENV_SOS` | 1 for the environment |
| `RC_RAM_KB` | `RC_RAM_KB = 32` | the target's RAM |
| `RC_SCREEN_COLUMNS`, `RC_SCREEN_ROWS` | `RC_SCREEN_COLUMNS = 40` | the text screen the environment starts in |
| `RC_TARGET` | `.define RC_TARGET "apple2-dos"` | the target's name, as a textual definition |

Names a program defines itself may not start with `RC_`; the build reports any that do. [sdk/1/README.md](../../sdk/1/README.md)
has the headers and defines as built, and where a target's includes are found.

The `RC_` defines are build switches, so they follow
[Builds and their switches](../ConvertingSources.md#builds-and-their-switches): a header that depends on one asserts
the values it accepts, so a build for a target it does not support fails at once. `Also:` does not reach `.ifdef` and
`.ifndef`, so a renamed define keeps an `.assert .not .defined(...)` that names its new name.

Every host gets the same symbols. The build passes them as `PredefinedSymbols`, which today only `--assemble`'s
`--define` and the SDK's own ROM builds set. The `project` launch builds through the same code, and the language
server gets the active target's symbols with its SDK paths and CPU. The `rc_` namespace is
also kept for the portable macros that come [later](#phases). The adventure's console layer is where they will be
proven first.

## Memory maps

Each machine × environment ships a memory map with RAM size variants: the free RAM regions, the zero-page bytes a
program may use, and the reserved areas with the reason for each. (The design; the bare maps as built follow it.)

```jsonc
// sdk/1/environments/dos33/apple2-48k.map.json
{
  "free":     [{ "start": "$0800", "end": "$95FF" }],
  "zeroPage": ["$06-$09", "$EB-$EF", "$FA-$FD"],
  "reserved": [
    { "start": "$0400", "end": "$07FF", "why": "text and lo-res page 1" },
    { "start": "$9600", "end": "$BFFF", "why": "DOS 3.3 and its buffers" }
  ]
}
```

- **With no linker configuration**, the build makes one from the map. `CODE`, `DATA` and `BSS` go in free RAM from the
  environment's load address, and `ZEROPAGE` goes in the free zero-page bytes.
- **With a linker configuration**, the build checks every section against the map. A section that overlaps a reserved
  area is an error, unless the target's `memoryMap` override frees that area. A game that uses hi-res page 1 frees it
  this way.
- The error names the section, the area and the target: *section CODE ($9000-$9800) overlaps DOS 3.3 and its
  buffers ($9600-$BFFF) on target apple2-dos*.
- **When a build doesn't fit**, the error gives each section's size and the free space left, so the Apple-1 target
  shows how far over it is.
- **At run time**, a later phase lets the debugger warn on writes into reserved areas, as the `;; Keeps:` contracts
  warn today.

**The Apple-1's expansion RAM.** Retrocore's Apple-1 takes `ramKilobytes` 16 and 32 as well as 4 and 8, for the
expansion RAM period owners added and modern replicas ship with: RAM contiguous from `$0000`, with the 4K bank at
`$E000` where it was ([Apple1.md](../Apple1.md#the-machine)). The adventure's Apple-1 target asks for 32K.

The linker already reports a segment that overflows its region and sections that overlap. A memory map adds what
the linker cannot know, the machine's reserved areas, and turns those errors into messages that name the target.

**As built (phase 3).** The `bare` maps for the five machines are in `sdk/1/environments/bare/`, one file per RAM size,
and [sdk/1/README.md](../../sdk/1/README.md#memory-maps) is their contract. A map also gives `load`, the address a
program loads at, which is the launch's own at a machine's default RAM. The zero page is given only as the bytes a
program may use, and every other address is free or reserved. The made configuration's RAM region runs to `$FFFF`, so
the map's check, not the linker, reports a program that is too big, with how far over it is. The adventure gives no
linker configuration: its five machines link by their maps. The run-time warning is still for later.

## Building

`retrocore build [--target <name>|--all]` reads `retrocore.json`, runs its steps, assembles each target, and writes
its output. It is the .NET tool's command, grown from the debug host's `--assemble`, which already takes a dialect, a
CPU, an origin, a linker configuration and defines. The debugger builds through the same code, so CI and F5 always
produce the same bytes. The command also prints the deprecation warnings that only the editor shows today.

The debug host packs as the tool (`dotnet pack src/Retrocore.Debug`, package `retrocore`, command `retrocore`), which
CI installs from its own package folder and builds and debugs the project sample with. Its `Sdk/` and `Schemas/`
folders go in the package, as they go beside the host. The host is already AOT-compatible, but a tool runs on the .NET
runtime the C# steps need anyway.

**Steps.** A step runs a host-side tool before assembly, with declared inputs and outputs. The build skips it when the
hashes of its inputs and its tool are unchanged. As built: a step gives `tool` (a `.cs` file-based app, run as
`dotnet run <file> -- <args>`, or a `.csproj`, run with `--project`), `in` and `out` (a path or a list), and `args`.
Paths start from the project's folder, `${obj}` in an input, output or argument is its `obj/`, and an argument that is exactly `${in}` or `${out}` stands for every input or
output; without `args` the tool gets the inputs, then the outputs. The tool starts in the project's folder. Its
record in `obj/steps/` holds the SHA-256 of what it read (the tool, the files its `#:include` and `#:project`
directives bring in, or a project's folder, and the inputs) and of what it wrote, so a changed output runs it again
too. A failing tool fails the build with what it printed. Either kind of tool needs only the .NET SDK, which the tool
already needs. A tool can reference
`Retrocore.Sdk.Tools`, which carries the media layer for disk and tape images and the assembler's symbols. A step's
output is used by `.incbin` or by a target's `files`.

```text
artifacts/apple2-dos/
  ADVENTURE         the B file
  PIRATE.DAT        the packed game, from the target's files
  adventure.dbg     the source map
  adventure.map     where each section and symbol landed
  adventure.dsk     a DOS 3.3 disk: HELLO, ADVENTURE, PIRATE.DAT
```

**Images.** Disk and tape targets build their image by default, through the [media layer](MediaPersistence.md). A target
can set `"image": false`, or give a template disk to start from.

### Media writers

What each starting environment's image needs, and what is there:

| Environment | Image | There | To add |
| --- | --- | --- | --- |
| `wozmon` | ACI tape (WAV) and hex text | `Apple1Tape.FromData` and `ToWave`; `WozMonitorHex.ToText` for the hex text (`0300: A9 C1 …` lines, then `0300R`) | |
| `dos33` | DOS 3.3 disk | `DosDisk.Create` takes any files, and the launch's `dos: "3.3"` builds the disk with `HELLO` and a B file | more files than `HELLO` and the program, such as `PIRATE.DAT`. The launch's disk is documented for the IIe, so a test should show it boots a II Plus. |
| `sos` | SOS boot disk | `Apple3SdkModules.BuildSosBootDisk`, in the debug host, where the build runs, builds a bootable disk from the SDK's sources around a program at a fixed address: the boot block, SOS.KERNEL, SOS.DRIVER (`SosDriverFile.Write`, the console by default) and the program as SOS.INTERP (`SosInterpreterFile.Write`). `SosVolumeBuilder` adds the other files. A test boots it under emulation | |
| `basic` | PET TAP tape, and a 4040 disk with dumps | [`PetSysProgram`](../../src/Retrocore.Media/Commodore/PetSysProgram.cs) builds the PRG with its `SYS` line and its TAP tape (through `CommodoreTapeBuilder.FromPrg` and `TapFormat.Write`); [`CbmDosDisk`](../../src/Retrocore.Media/Commodore/CbmDosDisk.cs) formats a DOS 2 disk and adds PRG and SEQ files; a `.prg` already loads and RUNs from a launch | |
| `dfs` | DFS `.ssd` | `AcornDfsDisk` writes the files with their load and exec addresses, the title, `!BOOT` and the `*OPT 4` boot option, and boots under DNFS; `AcornTapeBuilder.BuildUef` writes the tape | nothing |

Each writer reads back through the existing readers in its tests, and boots under emulation.

**How F5 loads the program:**

- `bare`: loads the binary into RAM and starts it at its entry point, as today.
- `wozmon`: loads the binary as if its hex had been typed in, and starts it at its entry point as `R` would.
- A disk or tape target: boots its image and lets the environment start the program, as a user would.
- `"image": false`: boots the environment to its ready point, then loads the file as that environment's loader would
  and starts it the way the environment starts programs.

**As built (phase 4).** The environments are classes of the host's build (`TargetEnvironment`), each writing its file
and image beside the binary and saying which of `files`, `image` and `bootImage` it takes; a target that gives one its
environment does not take fails naming it. [sdk/1/README.md](../../sdk/1/README.md#environments) is the contract.
`wozmon` writes `<name>.hex` and the ACI tape `<name>.wav` (`"image": false` leaves the tape out), and its maps are the
bare Apple-1's. The adventure's `apple1-wozmon` target plays Pirate Adventure's win under the debugger, and the test
checks that its hex stores the bytes the launch loaded. `dos33` writes `<name>.dsk`: DOS 3.3 from the SDK's sources,
`HELLO` (AppleSoft, or Integer BASIC on the II), the program as a B file, and the target's `files` as B files; a launch
boots it in slot 6, after the saved machine's and the journal's media, and runs to the program's entry. It boots the II
Plus, the enhanced IIe, and the II with the Autostart ROM. The adventure's `apple2-dos` target loads `PIRATE.DAT` from
its disk with `BLOAD`, printed through `COUT`, and plays both of Pirate Adventure's transcripts. `dfs` writes
`<name>.ssd`, the program as a `*RUN` file with the target's `files` and a `!BOOT` that runs it, and a UEF tape of
the same files; a launch fits the disk interface, puts the disk in drive 0 and boots it holding SHIFT, on the model B
and on a model A. The adventure's `bbc-dfs` target loads `$.PIRATE` with OSFILE and plays both transcripts. `basic`
writes `<name>.prg` (its `SYS` line, then the program from `$0410`), its TAP tape and a 4040 disk; a launch puts the
tape in with PLAY down, types `LOAD` and then `RUN`, on BASIC 4, 2 and 1. A target whose image boots the disk (BASIC 2
and 4: BASIC 1's IEEE-488 bug stops disk drives) needs the
4040's ROMs, which the launch finds by hash: the SDK's first [boot media](../../sdk/1/README.md#environments) lookup,
by the SHA-1s MAME publishes (the plan said SHA-256; MAME's sets give SHA-1), in `bootImage`, the launch's
`romDirectory`, `RETROCORE_PET_ROMS` and `RETROCORE_CACHE`. The disk is written even without them, as the writer is the host's. The adventure's `pet-basic`
target plays both Pirate transcripts from its tape; `pet-disk` plays from the disk with the dumps, and the DAP test
reports it skipped without them. A target's `bootImage` names the folder its boot media is looked for in
first, by hash, as the `basic` environment's 4040 disk, above, uses it.

## Debugging in VS Code

- **The active target** shows in the status bar (`adventure · apple2-dos ▾`) and in the Retrocore view. It is the
  extension's first status-bar item. Clicking it lists the project's targets, grouped by project when a repository
  has several, with the same quick picks Start Machine uses. The choice is kept in workspace state, and
  `retrocore.activeTarget` returns it for launch configurations.
- **F5 with no launch.json** in a folder with a `retrocore.json` builds the active target and starts its machine.
  A `resolveDebugConfiguration` (`extension/src/activeTarget.ts`) takes the empty configuration F5 sends without a
  launch.json and makes it a `project` launch of the active target, and `workspaceContains` activation events (a
  `retrocore.json` at the root or below) start the extension for it. VS Code gives that configuration to the
  debugger the editor's language picks, so F5 does this from a Retrocore source. The launch resolves the target's
  machine through the catalog, so it gets a saved machine and recovery journal of its own, as any other launch does.
- **The project file has a schema**, contributed through `jsonValidation`, and the extension watches it.
- **One launch configuration** covers every target when you want one:

  ```jsonc
  {
    "type": "retrocore",
    "request": "launch",
    "name": "Debug project",
    "project": "${workspaceFolder}",
    "target": "${command:retrocore.activeTarget}"
  }
  ```

  `project` replaces `source`, `program` and `debugFile`. The target supplies `machine`, its options and its cards.
  Breakpoints, `stopOnEntry` and `checkContracts` stay launch options.
- **Stopping on entry** stops at the program's entry point, not at the boot, even when F5 boots a disk.
- **The language server follows the active target.** It uses that target's SDK paths, defines, CPU and platform
  folders for completion, hover and diagnostics. Changing the target re-checks the open files. Today the server's only
  inputs are `--sdk-roms`, `.cfg` files and the lint words. The extension sends the active target in a
  `retrocore/activeTarget` notification, `{ "project": "<retrocore.json path>", "target": "<name>" }` (both null
  without one), at the server's start and whenever the active target or what its file gives it changes. Every change
  to a `retrocore.json` also reaches the server as a watched-file event. The server's side, in phase 2, loads the target's
  settings from the file itself, and without a target uses each source's first target that assembles it.
- **Inactive `.if` blocks are dimmed** with the `Unnecessary` diagnostic tag the server already uses for an unused
  `.using`.
- **A build error** fails the launch, and its diagnostics name the target.

## The first sample: a Scott Adams interpreter

The sample is the first real project the SDK is built against. Each phase is done when the sample builds and runs on
more targets.

**What it is.** An interpreter for Scott Adams adventures, written in native 6502 assembly. It plays games in the
ScottFree `.dat` format, the text form the classic games are distributed in. Pirate Adventure is the included game,
along with a small test adventure of our own. The interpreter is our own code; the game is Scott and Alexis Adams'.

**Layout.**

```text
sample/adventure/
  retrocore.json
  src/core/            the engine: the parser, word lookup, conditions and actions, the light timer, inventory
  src/platform/
    apple1/            console.s: the Woz Monitor's ECHO and the keyboard PIA
    apple2/            console.s: COUT and GETLN; load.s: DOS 3.3's file manager
    apple3/            console.s and load.s: SOS's console driver and file calls
    pet/               console.s: the Kernal's CHROUT and GETIN; load.s: LOAD, for a disk
    bbc/               console.s and load.s: OSWRCH, OSRDCH and OSFILE
  tools/packer.cs      .dat → packed binary
  games/pirate.dat     Pirate Adventure
  games/README.md      where the game comes from and where it is normally hosted
  games/test.dat       a three-room test adventure of our own, MIT
```

**The packer** reads the `.dat` and writes a compact binary: tokenized words, packed condition and action tables, and
messages compressed with a common-substring dictionary. Its format is the interpreter's own, documented in the sample.
The packer also holds a C# reference engine for the same format, which the [tests](#tests) play transcripts against.

**Linked or loaded.**

- **The tape targets** link the packed game into the program (`GAME_LINKED`, `.incbin "${obj}/pirate.bin"`): the
  Apple-1 in its 32K, and the PET 4032 in its 32K, since its tape is the image that needs no dumps.
- **The disk targets** put `PIRATE.DAT` beside the interpreter (the target's `files`) and load it at start, so another
  game runs without rebuilding.

**Wrapping** follows `RC_SCREEN_COLUMNS`: 40 on the Apple-1, the Apple II, the PET 4032 and the BBC Micro's MODE 7,
and 80 on the Apple III's SOS console.

**Style.** The sample is a repository source like any other, so it follows the [style guide](../AssemblyStyle.md)
(`style=strict`), and its folder goes in `SdkDocumentationTests`' list of samples and their machines.

**Pirate Adventure** is checked in as `games/pirate.dat`. `games/README.md` names the site where Scott Adams' classic
adventures are normally hosted and the terms given there. Recording the exact page and terms is part of adding the
file.

**Where it lives.** The sample starts in this repository, in `sample/adventure/`, so it can change with the SDK. Once
the tool has its first preview build, it moves to a repository of its own, made with `retrocore new` and keeping its
history, and its CI builds it with the published tool. This repository's tests then build it at a pinned commit.

## Dialects

The SDK's headers are written once, in native. A ca65 or Merlin source includes them (`.include <machine.inc>`,
or Merlin's `PUT`), and the assembler reads the header as native whatever the including file's dialect, because SDK
includes default to `dialect=native`. Constants and labels work in every dialect. A macro works where the including
dialect can call native macros. Where it cannot, the header also gives the call as a constant: `MLI` and the call
numbers, besides the `rc_mli` macro.

## Languages

The first version builds assembly only. Source entries take a `kind` from the start (`asm` by default), so a later
version can add `basic`. That version would build a BASIC program that BLOADs the routines the same project
assembles, a common pattern of the time, with the BASIC file as the `entry`:

```jsonc
"sources": [
  { "path": "src/*.s" },
  { "path": "menu.applesoft.bas", "kind": "basic" }
],
"entry": "menu.applesoft.bas"
```

Apple Pascal comes after BASIC, with its own [plan](ApplePascal.md).

## Versions of the SDK

- **A project pins a major version** with `"sdk": "1"`. Its files live under `sdk/1/` in the tool and beside the
  debug host. The tool's own version is pinned in `.config/dotnet-tools.json`.
- **Within a major version the SDK only adds**: new names, new targets, more free memory in a map only when it is
  shown to be safe.
- **A removal or rename waits for the next major.** That major keeps the old name with the mechanisms the SDK's
  sources already use: `;; Also:` makes the old name assemble as an alias, and a `Deprecated:` section makes each use
  a warning. Moving up is therefore a warning rather than a broken build. The editor warns today, and
  `retrocore build` must warn too. A renamed `RC_` define is the exception: `Also:` does not reach `.ifdef`, so it
  gets the build switches' `.assert`.
- **The tool and the extension ship the current and previous majors.** A project on the previous one builds, with a
  warning that names the next.
- A bug fix that changes a header's value, such as a wrong soft-switch address, goes into the current major and is
  listed in the SDK's change log.

## Tests

| What | How |
| --- | --- |
| The manifest | Schema tests: every field, root files with projects, bad targets, CPU lowering, unknown machines and environments. |
| Repository setup | `retrocore new` with every template and machine set builds at once, and its generated CI workflow passes. |
| Platform folders | A model's file replaces its family's; a target's own sources add after both. |
| Steps | A step reruns only when its inputs or tool change, and its output feeds `.incbin` and `files`. |
| Generated headers | Regenerating them changes nothing (checked by digest), and every entry point matches its ROM source's address. |
| Hardware equates | Each one matches the emulator's device map for its machine. |
| CPU checks | A 65C02 opcode fails the 6502 targets and builds for the enhanced IIe; a Z80 opcode fails an 8080 project. |
| Memory maps | A section in a reserved area fails with the target's name; a `memoryMap` override frees it; the generated linker configuration places a sample in free RAM on every target. |
| Boot media | A missing image fails with its name and hash; a library image with the right hash is found; a PET target without the 4040's dumps builds its tape and no disk. |
| Media writers | Each writer's image reads back through the existing readers (`DosDisk`, `SosVolume`, the D64 and DFS readers, `TapFormat`, `UefFormat`) and boots under emulation: the DOS 3.3 disk on a II Plus as well as a IIe, the SOS disk with SOS 1.3 built from source, the DFS disk with `!BOOT`. |
| The Apple-1's RAM | 16K and 32K boot the Woz Monitor and run a program above `$1FFF`; other sizes are still rejected. |
| Dialects | ca65 and Merlin samples include the native headers and build byte-identically to their native twin. |
| The adventure | It builds for all five targets. A scripted walkthrough of the test adventure, and an opening of Pirate Adventure, run on each target under the debug adapter, in the style of the `tools/Test-*Dap.mjs` scripts, and each transcript must match the packer's reference engine. As built in phase 3: Pirate Adventure's win, from start to finish, and its death play on the bare Apple-1, PET, Apple II and BBC Micro, and the test game's three transcripts on a second Apple II target; the Apple III builds but is not played until it has a character set. |
| VS Code | The active target picker, F5 without a launch.json, the `project` launch, and the language server switching targets. |
| Versions | A project on the previous major builds with its deprecation warnings; a removed name fails on the current major. |

## Phases

Each phase ends with the adventure doing more. Phases 1 to 3 need nothing main lacks beyond what they build. Phase 4's
media writers can go alongside them, each in its own change.

1. **The project, the build and the active target.** `retrocore.json` (with root files listing projects) and its
   schema, platform folders, `retrocore build` grown from `--assemble` and packed as a .NET tool (run locally until
   it has a preview build), the `project` launch, the status-bar target, F5 without a launch.json, the language
   server's target notification, and `sdk/1/`. Done when the adventure's engine plays the test adventure on a `bare`
   Apple II target from the picker.
2. **Headers, defines and CPU checks.** `<machine.inc>` for the Apple-1, the Apple II family, the Apple III, the PET
   and the BBC Micro over their entries and equates files, with hand-written equates where those lack them. Also the
   `RC_` defines and their asserts, symbols in every host, the target CPU check, and dimming inactive blocks. Done
   when the engine's core builds unchanged for all five machines as `bare` targets with a platform folder each.
3. **Steps and memory maps.** C# tool steps with caching, the packer, memory maps for the five starting environments,
   the generated linker configuration, the reserved-area errors, and the Apple-1's expansion RAM. Done when Pirate
   Adventure, linked in, plays on the Apple-1 with 32K and on a bare PET 4032.
4. **The media writers and the starting environments.** First the [media writers](#media-writers): Woz Monitor hex,
   more files on the DOS 3.3 disk, the PET's `SYS` stub, the DFS catalogue with `!BOOT`, and the SOS boot disk
   (boot blocks, `SOS.DRIVER`, the `SOS.INTERP` header), the largest of them. The CBM DOS writer is needed only for the
   PET's optional disk and can follow. Then `wozmon`, `dos33`, `sos`, `basic` and `dfs`, each with its header, its
   file format, its image and how F5 loads it, and boot media lookup by hash. Done when Pirate Adventure plays on all
   five targets from their disks and tapes, loading `PIRATE.DAT` where there is a disk.
5. **The repository workflow.** `retrocore new` and `retrocore init` with their templates, *Retrocore: New Project*,
   the generated CI workflow, and preview builds of the tool and the extension. Then the sample moves to its own
   repository. Done when a fresh clone builds every target with `dotnet tool restore` and `dotnet retrocore build --all`
   on Windows, macOS and Linux.
6. **Deprecation.** Deprecation warnings from `retrocore build`, and the previous-major support, needed before the
   SDK's first breaking change.
7. **More environments.** `prodos`, `cpm`, `level2`, `trsdos`, `colorbasic` and `diskbasic`, and SOS interpreters that
   relocate.
8. **Portable macros.** A small `rc_` set (`rc_putchar`, `rc_getkey`, `rc_getline`, `rc_cls`, `rc_exit`) for every
   target, grown out of the adventure's console layer.
9. **BASIC sources**, which load routines the same project assembles.
10. **Run-time memory guard and `retrocore test`.** The debugger warns on writes into reserved areas, and CI can run a
    project's scripted transcripts under emulation.

## Decisions (agreed 2026-11-16)

- **A target is a machine × environment.** `<machine.inc>` describes the hardware and `<environment.inc>` the system
  calls, so a CP/M program can target several machines.
- **Headers and defines first.** Entry points are generated from the SDK's ROM sources. The `rc_` namespace is
  kept for a thin portable macro set later, and a full runtime library is out of scope.
- **The project is a JSON manifest**, `retrocore.json` with a schema, read by the language server, the debug host and
  `retrocore build`.
- **Each environment's own file** is the build output: a B file, a SYS file, a `.COM`, a `/CMD`, a DECB `.BIN` or Woz
  Monitor hex. A bootable image can be built for each target.
- **Headers are native only.** Sources in any dialect include them.
- **Assembly in the first version.** Sources take a `kind` so BASIC can follow, with Pascal after it.
- **Each target ships a memory map** of free RAM, usable zero-page bytes and reserved areas. The linker checks
  against it, and a target can override it.
- **A project pins the SDK's major version.** Within a major the SDK only adds. Renames keep a deprecated alias for one
  major, and the tool and the extension ship the current and previous majors.
- **The active target is chosen in the status bar.** One generic `project` launch configuration, or none at all,
  debugs it with F5.

From walking through the open questions:

- **Boot media that is not an SDK source is found by hash** in the user's libraries and `RETROCORE_CACHE`. If it is
  missing, the error names it and offers a Fetch command where a legal source exists. A target can name one with
  `bootImage`.
- **One `retrocore.json` at a repository's root**, which is a project or lists its projects' folders.
- **Repositories are created by *Retrocore: New Project* and `retrocore new`** from the same templates. The scaffold
  includes the pinned tool, the extension recommendation, `.gitignore`, a CI workflow and a README.
- **Targets add sources, and platform folders are picked up by family and model**, a model's file replacing its
  family's.
- **The Apple III starts with SOS**: a `SOS.INTERP` at a fixed address on a boot disk built from the SDK's SOS 1.3
  sources, with relocation later.
- **The PET and BBC Micro are added before this plan begins**, in plans of their own. (Both have since landed.)
- **The starting targets use each machine's usual way**: `wozmon` hex and tape on the Apple-1, a DOS 3.3 disk on the
  Apple II, a SOS disk on the Apple III, a PRG with a `SYS` line on the PET, and a DFS disk with `!BOOT` on the BBC
  Micro.
- **The first sample is a Scott Adams interpreter in 6502 assembly**, playing Pirate Adventure on the Apple-1, the
  Apple II, the Apple III, the PET and the BBC Micro.
- **Game data is packed at build time.** The Apple-1 links it in, and disk targets load it as a file.
- **The Apple-1 gains expansion RAM** (16K and 32K), and the adventure's Apple-1 target uses 32K.
- **Pirate Adventure's `.dat` is checked in**, with a README naming the site where the games are normally hosted.
- **The sample starts in `sample/adventure/`** and moves to its own repository once the tool has a preview build.
- **Build steps are C# file-based apps** (or small projects), cached by the hashes of their inputs.
- **`retrocore` is a .NET tool pinned in each repository's `.config/dotnet-tools.json`.** The extension uses the
  pinned tool when there is one.

### Revised 2026-11-25

Checked against main once the PET and BBC Micro had landed:

- **Targets name machines by the extension's catalog**: `pet4032` and `bbcb` for the adventure, not placeholders.
- **The first headers include the SDK's entries and equates files**, including the PET's and BBC's, which are SDK
  sources. Generating headers comes later, from the source generator's export walk.
- **Deprecated names use `Also:` and `Deprecated:`**, which exist, not a new directive. `retrocore build` prints
  their warnings.
- **The `RC_` defines are build switches** and follow the style guide's asserts.
- **A PET target builds a tape by default**, which needs no dumps. A 4040 disk is added when the drive's dumps are
  found. The PET links the game in, like the Apple-1.
- **The media writers are their own work** ahead of the starting environments: Woz Monitor hex, more DOS 3.3 files,
  the PET's `SYS` stub, the DFS catalogue, the SOS boot disk, and later CBM DOS.
- **The Apple II target reuses the launch's `dos: "3.3"` disk**, extended to more files.
- **The SOS boot disk's `SOS.DRIVER` carries the console alone by default**, from the SDK's source. The built-in
  disk's driver, `.D1` to `.D4`, is part of SOS.KERNEL, so the disk needs no entry. `SosDriverFile.Write` writes any
  drivers it is given: it rewrites Apple's own files byte for byte, and the SDK builds every Apple driver it has a
  source for (console, RS-232, printer, graphics, audio, Silentype, ProFile, formatter and RAM disk). A target can
  add those by name. The drivers are relocated, because `SOS.DRIVER` has no fixed-address form: SOS's loader puts
  each driver wherever it finds room below the interpreter and adds that address to the words its relocation table
  lists. The build finds those words by assembling each driver at two origins. The header's character set and
  keyboard layout come from a new SDK source, `Sos/SosDriverHeader.asm`: Apple's STANDARD set and SHOLES layout.

## Open questions

- **The packed format's budget.** How small Pirate Adventure packs, and so whether the Apple-1 could fit in 16K.
  Measured in phase 3: it packs to 5,894 bytes, and the Apple-1's whole program, the game linked in, is 10,141 bytes
  from `$0300` with about 0.5K of engine state after it, so it would fit in 16K. The target keeps 32K.
- **Saving the game.** A save to disk on the disk targets, and to tape or nothing on the Apple-1. Is this in the first
  sample, or after it?
- **Where the extension and tool disagree.** Should the extension refuse to build when the repository pins a tool it
  cannot run, or fall back to its own copy with a warning?
