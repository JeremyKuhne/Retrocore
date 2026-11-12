---
name: retrocore-disassembly
description: Turn an Apple II program into annotated native assembly source that assembles back to the same bytes, naming what it uses of the Monitor, firmware, BASIC and DOS by the SDK sources' names. Use when asked to disassemble, decompile, reverse engineer, list or annotate a binary file, a program on a DOS 3.3 or 3.2 disk image (such as one on a System Master), or a memory image, or to list or extract the files on an Apple II disk image.
license: MIT
compatibility: Requires the .NET SDK. The commands are in Retrocore.Debug; docs/NativeAssembly.md is the syntax reference.
metadata:
   portability: repository
   applicability: retrocore
   risk: local-write
   maturity: canary
   requires: retrocore-native-assembly
---

# Disassembling Apple II programs

Don't write scripts to read disks, decode sectors or disassemble. The debug host has commands for all three, and
they already know the machine's names. Your work is the part they can't do: deciding what each piece of code is
for, and saying so in names and `;;` documentation.

## The commands

Build once, then run the host:

```powershell
dotnet build src/Retrocore.Debug -c Release
$host = "artifacts/AnyCPU/Release/Retrocore.Debug/net10.0/Retrocore.Debug.dll"
```

| Step | Command |
| --- | --- |
| List a disk's files | `dotnet $host --dos catalog disk.dsk` (add `--json` to parse it) |
| Copy a file out | `dotnet $host --dos extract disk.dsk "NAME" out.bin` |
| Disassemble a file on a disk | `dotnet $host --disassemble --disk disk.dsk --file "NAME" out.asm` |
| Disassemble a plain binary | `dotnet $host --disassemble in.bin out.asm --origin $0800` |
| List a BASIC program as text | `--dos extract` it, then `dotnet $host --basic list out.bin --dialect applesoft` (or `integer`) |

- **Disk images:** the commands read `.dsk`, `.do`, `.po` (ProDOS sector order) and `.d13` (13 sectors) images, but not
  `.woz`.
- **Names:** `--machine ii|iiplus|iie|iie-enhanced` (default `iiplus`) and `--dos 3.3|3.3-1980|3.2|none` (default
  `3.3`) choose whose names the output uses. Match the disk: a 1980 System Master's program runs under the 1980 DOS.
- **What the command does:** it follows the code from the first byte, names the addresses it uses from the SDK
  sources, and writes native source. It then assembles that source and reports:
  - whether the bytes match, with exit code 0 when they do;
  - the ranges it left as `.byte`, because no code it followed reached them.

## The loop

1. Catalog the disk, and disassemble the file with the right `--machine` and `--dos`.
2. Read the "Bytes left as .byte" report against the source. Each range is one of:
   - **Data** (text, tables, buffers): leave it as data. Optionally mark it in the hints, so code following never
     wanders into it.
   - **Code reached in a way flow analysis can't follow:** a jump table, a pushed address and `RTS`, a routine called
     only from outside, or code after a `JSR` that never returns or takes inline bytes. Add an entry point,
     `noReturn` or `inline` hint.
3. Write a hints file (see below), give it with `--hints`, and rerun until every range is explained.
4. Name things in the hints as you work out what they do. A name inside the program becomes a label, and one
   outside becomes an equate.

The hints file is JSON. Each address is a string such as `"$0812"`, or a number:

```json
{
  "entries": ["$0A10"],
  "data": [{ "start": "$09E2", "end": "$0EFE" }],
  "names": { "$0812": "ReadImage", "$F0": "Pointer", "$03D9": "DOS_RWTS" },
  "comments": { "$0812": "Reads the master image." },
  "noReturn": ["$0900"],
  "inline": { "$0950": 2, "$0960": "zero" }
}
```

The output is a correct starting point, not a finished source. The generated labels are only addresses (`L_0905`,
`D_0E50`), data is hex bytes, and the mnemonics are uppercase.

## Finishing the source

Edit the output by hand into a source someone can maintain. Follow the retrocore-native-assembly skill throughout:
its syntax rules, `;;` documentation and naming. Then:

- **Labels:** rename every generated one after what the code does. A routine's inner labels are `ROUTINE_Name`, and
  no name may be only an address.
- **Equates:** `.include` the SDK's equates instead of repeating their values, for example
  `../Roms/Dos/Equates.asm` and `../Roms/System/FirmwareEquates.asm`. Define only what they lack. DOS's page-3
  entries (`$03D0`-`$03FF`), for one, are set up as DOS runs, so no source names them.
- **Data:** write text as `.byte "TEXT", $0D`. Name the constants a table or message number stands for.
- **Mnemonics:** use lowercase, as the SDK sources do.
- **Documentation:** give each routine a `;;` block with `In:`, `Out:` and `Keeps:`. After editing comments,
  check them as the native-assembly skill says.
- **Placement:** put a program from a System Master in `src/Retrocore.Machines.Apple2/Software/`. Add a test that
  assembles it and pins its SHA-256, as `SystemMasterBasicTests.MasterCreateSourceMatchesThe1980Master` does for
  `MasterCreate.asm`.
- **Wording:** in the source and docs, say it assembles byte-identically to the original. Don't say it was
  disassembled or generated.

## Pitfalls

- **Page-zero names:** only the Monitor's and the hardware's names are used there. Programs reuse BASIC's and
  DOS's page-zero storage for their own purposes, so name those locations after what this program keeps in them.
- **Machine and DOS:** the wrong `--machine` or `--dos` names addresses by another version's layout. Check that a
  named DOS address really is that routine for the disk's DOS.
- **Wrong entry points:** an entry point in the middle of an instruction or in data makes nonsense. If the source
  stops assembling to the same bytes, the last hint you added is the first suspect.
- **Machine code inside a BASIC program:** a BASIC program that holds machine code among its lines, as
  APPLEVISION does, is not a binary file. Copy it out with `--dos extract`, find the code's address, and disassemble
  that part with `--origin`.
