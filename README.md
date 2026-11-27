# Retrocore

Retrocore brings a modern software engineering experience to classic 8-bit computers. In one .NET codebase, it unites
cycle-exact CPUs and machines, rich language tooling for assembly, BASIC, and Apple Pascal, a whole-machine
source-level debugger, a portable multi-target SDK, and two ways to run machines: inside VS Code or in the standalone
Retrocore Desktop app.

> **Active development — not published yet.** Retrocore has no public release on the VS Code Marketplace, Open VSX, or
> NuGet yet; build and run it from this repository as shown below. Everything in the repository is being brought to the
> same **all-source standard**: documented, readable system source maintained in-repo, verified byte-for-byte against
> the original binaries, with full editor and debugger support across every platform. Parts still in flight will be
> brought all the way there.

## Design

Most 8-bit workflows stitch together separate pieces—an emulator, an external cross-assembler, disk utilities, and a
hex monitor where symbols and source disappear at the first system call. Retrocore is designed around four ideas that
work together because the emulator, compilers, language server, debugger, and system sources live in one stack.

### All-source machines

System firmware, BASIC interpreters, character generators, controller PROMs, and disk operating systems—including
Apple DOS 3.2 and 3.3, Apple III SOS 1.3 and Business BASIC, Acorn DNFS, and Atari 810 drive firmware—are maintained
in-repo as assembly sources pinned byte-for-byte by SHA-256. Nothing on the machine is a black box when debugging: when
execution enters `$FDED`, `$03D6`, a BASIC runtime routine, or a device driver, you step straight into documented ROM
or OS source with routine names, scopes, hovers, call stacks, and runtime-checked `;; Keeps:` contracts—whether mapped
onto your own ROM images or running directly from the included sources. Being able to build and boot the machines from
those sources is a natural bonus where their sources are already in place.

### Readable system code that keeps its history

System sources are written and converted for developers who know modern tools and are meeting an old platform for the
first time ([ConvertingSources.md](docs/ConvertingSources.md)). Routines, structures, and hardware locations use clear,
full-word names (`CharacterOut`, `CallFileManager`), `.proc` and `.scope` boundaries, and `;;` doc comments that
explain the machine as well as the instructions. Every name that original manuals and listings used stays attached in
an `;; Also:` section with bibliography citations—so 1970s listings and existing code still assemble, hover and go to
definition resolve under either name, and disassembled legacy binaries read in plain terms instead of raw hex.

### Modern language intelligence across Assembly, BASIC, and Pascal

One reflection-free language server and compiler host ([`Retrocore.Debug`](src/Retrocore.Debug)) powers editing and
building across languages:

- **Assembly:** four dialects—Retrocore's [native syntax](docs/NativeAssembly.md) across every supported CPU, `ca65`
  (with macros, `.struct`/`.enum`, and single-object `ld65`-style linking), Merlin 8/Pro and Merlin 32, and `MACRO-10`
  (including SHA-256-pinned overlays over Microsoft's 6502 BASIC source)—with live diagnostics, hovers showing flags,
  addressing modes, cycle counts, emitted bytes, and `;;` docs ([DocComments.md](docs/DocComments.md)), go to
  definition, find all references, and symbol search across your code and the SDK's ROMs.
- **BASIC:** write source without line numbers using indentation and `label:` or `@label` targets, open tokenized files
  and tapes directly as text, or edit the program currently in an emulated machine's RAM and tokenize changes back on
  save—with dialect-accurate highlighting, diagnostics, hovers, completions, and renumbering.
- **Apple Pascal:** run UCSD Apple Pascal on the Apple II and Apple III, inspect p-code, and decompile code files back
  into readable Pascal that Apple's Compiler compiles to the same p-code ([Pascal.md](docs/Pascal.md),
  [PascalStyle.md](docs/PascalStyle.md)).

### Whole-machine debugging and a portable SDK

- **Debugging across layers:** CPU, **BASIC**, and **Pascal** threads appear side by side in the same session. Step
  from BASIC `CALL` or `USR` straight into machine code, step into and out of inline macro expansions, and step across
  your code and the SDK's ROM and OS sources. Set source, data, Z80 I/O port, BASIC-variable, or scanline-beam
  breakpoints ([Breakpoints.md](docs/Breakpoints.md)); inspect per-line and per-call cycle counts; verify documented
  `;; Keeps:` register-preservation contracts at runtime; and inspect, search, or freeze banked RAM and ROM without
  triggering soft-switch side effects ([Memory.md](docs/Memory.md)). Source modules bind to memory banks and stay
  active only while memory matches their assembled bytes, so banked RAM or overwritten code never shows stale lines.
- **Multi-target SDK (`retrocore.json`):** write assembly once for a CPU family using [`sdk/1`](sdk/1/README.md)
  headers (`<cpu.inc>`, `<machine.inc>`, `<environment.inc>`), target defines, and checked per-machine memory maps.
  `retrocore build` verifies that sections stay out of reserved memory and emits bootable disks, tapes, or binaries for
  each target machine—demonstrated in [`sample/adventure`](sample/adventure/README.md), a Scott Adams interpreter
  building from one 6502 core across the Apple-1, Apple II, Apple III, PET, and BBC Micro.

## Two Ways to Run: VS Code and Retrocore Desktop

Both hosts run the same cycle-exact machines, slot/hardware configurations, display and audio controls, automatic fast
disk and fast tape, and non-destructive mounted media—disk and tape images keep changes in memory until you choose to
save, with crash-recovery journaling in the VS Code debug host ([Devices.md](docs/Devices.md)).

Both require the [.NET 11 SDK](https://dotnet.microsoft.com/download/dotnet/11.0) to build from this repository.

### VS Code extension

Provides the full editing, building, and debugging experience alongside a live display panel and the **Retrocore**
activity bar's Machine and Drives views. Pick any machine in **Run and Debug** and press F5, or run
**Retrocore: Start Machine…** to boot bare or launch an assembly source, BASIC file, binary, disk image, or tape with
no `launch.json` required ([extension README](extension/README.md)).

With [Node.js](https://nodejs.org) (npm), [VS Code](https://code.visualstudio.com) 1.140+ (`code` on `PATH`), and
PowerShell 7 on Windows, build and install the extension from the repository root:

```powershell
.\tools\Install-Extension.ps1
```

Reload VS Code afterwards; pass `-PackageOnly` to build `artifacts\vsix\retrocore-<version>.vsix` without installing
(installing that VSIX on another machine needs only the .NET 11 runtime, not the .NET SDK or Node.js). To run
the extension directly from source in an isolated development profile, see
[Installing and self-hosting](extension/README.md#installing-and-self-hosting).

### Retrocore Desktop

[`Retrocore.Desktop`](src/Retrocore.Desktop) runs the full machine catalog in a standalone Avalonia and SDL3 window
outside VS Code, with the same collapsible Machine, Drives, and Display & Sound views over the emulated screen:

```powershell
dotnet run --project src\Retrocore.Desktop -c Release
```

It also publishes ahead of time to a standalone native executable (see [Development.md](docs/Development.md) for Native
AOT prerequisites and profile details):

```powershell
dotnet publish src\Retrocore.Desktop -c Release -r win-x64 -o artifacts\desktop
```

### CLI and multi-target builds

[`Retrocore.Debug`](src/Retrocore.Debug) also runs from the command line (and packs as the `retrocore` .NET tool) to
build `retrocore.json` projects, assemble or disassemble files, work with BASIC files and tapes, and build DOS or
Pascal disks:

```powershell
dotnet build Retrocore.slnx -c Release
dotnet artifacts\AnyCPU\Release\Retrocore.Debug\net11.0\Retrocore.Debug.dll build --all --project sample\adventure
```

## Supported Machines

Hardware details, system sources, media formats, and launch options are covered in each platform's guide:

- **MOS 6502 / 65C02:** [Apple-1](docs/Apple1.md) · [Apple II, II Plus, and IIe (original and enhanced)](docs/Apple2.md) ·
  [Apple III](docs/Apple3.md) ([SOS](docs/Sos.md), [Business BASIC](docs/BusinessBasic.md)) ·
  [Commodore PET 2001 and 4032](docs/Pet.md) · [BBC Micro Model B and Model A](docs/BbcMicro.md) ·
  [Atari 400 and 800](docs/Atari800.md)
- **Zilog Z80:** [TRS-80 Model I](docs/Trs80ModelI.md) ·
  [TRS-80 Model III, 4, and 4P, and Model II, 12, and 16 (Z80 side)](docs/Trs80Model3And2.md) ·
  [Kaypro II](docs/Kaypro.md) · Z80 SoftCards for the [Apple II](docs/Apple2.md) and [Apple III](docs/Apple3.md)
- **Motorola 6809E:** [TRS-80 Color Computer 1, 2, and 3](docs/Coco.md)
- **Intel 8080 / OKI 80C85:** [MITS Altair 8800](docs/Altair8800.md) ·
  [TRS-80 Model 100 and Tandy 102](docs/Trs80Model100.md)

## Documentation

- **Editor, debugger, and SDK:** [VS Code extension guide](extension/README.md) ·
  [SDK headers, memory maps, and environments](sdk/1/README.md) · [Native assembly](docs/NativeAssembly.md) ·
  [Doc comments (`;;`)](docs/DocComments.md) · [Breakpoints](docs/Breakpoints.md) · [Memory views](docs/Memory.md) ·
  [Devices and media](docs/Devices.md) · [Apple DOS](docs/Dos.md) · [Disk II](docs/DiskII.md) ·
  [Apple Pascal](docs/Pascal.md)
- **Source conversion and style:** [Converting sources](docs/ConvertingSources.md) ·
  [Assembly style guide](docs/AssemblyStyle.md) · [Pascal style guide](docs/PascalStyle.md) ·
  [Conversion logs](docs/conversions/README.md) · [Bibliography](docs/Bibliography.md)
- **Contributing and roadmap:** [Development, testing, and repository layout](docs/Development.md) (build and test
  commands, Native AOT and PGO, `RETROCORE_*` external fixtures, solution projects, and the SDK ROM source index) ·
  [`docs/backlog`](docs/backlog) for active design notes

## License

MIT; see [LICENSE](LICENSE) and [THIRD-PARTY-NOTICES](THIRD-PARTY-NOTICES).
