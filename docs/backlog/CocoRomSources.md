# Backlog: the Color Computer's ROM sources

Phase 7 of [the Color Computer](M6809-CoCo.md): native sources for Color, Extended, Disk and Super Extended BASIC
that assemble byte-identically to every ROM the machine runs, maintained by hand like `Level2.asm`. With them the
Color Computer runs and debugs with nothing external, as the Apple II family and the Model I do, and stepping from a
program into a ROM call goes into the ROM's source.

**Status:** the decisions were approved (2026-11-12). Stage 1, Color BASIC, was reviewed; stages 2 to 4, Extended and
Disk Extended Color BASIC and the CoCo 3, are built and await review; stage 5 is what remains.

## What there is to write

| ROM | Size | Versions | How they differ |
| --- | --- | --- | --- |
| Color BASIC | 8 KB at `$A000` | 1.0, 1.1, 1.2, 1.3 | Patches in place: 386 bytes from 1.0 to 1.1, 266 to 1.2, 11 to 1.3. |
| Extended Color BASIC | 8 KB at `$8000` | 1.0, 1.1 | 44 bytes. |
| Disk Extended Color BASIC | 8 KB at `$C000` | 1.0, 1.1 | 1.1 inserts code throughout (about 4.4 KB matches 1.0 in place), so addresses move. |
| CoCo 3 | 32 KB at `$8000` | one | Extended (85 bytes patched, as 2.0) and Color BASIC 1.2 (122 bytes), then the CoCo 3's own `$C000-$FDFF`: start-up, the GIME's set-up and Super Extended BASIC, about 16 KB. |

About 40 KB of distinct code and data. Level II's 12 KB is 10,000 lines of `Level2.asm`, so this is about 30,000
lines, the SDK's largest source after the IIe's.

## Proposed decisions

1. **Labels** come from Spectral Associates' *Unravelled* series (Color, Extended, Disk and Super Extended BASIC
   Unravelled), the names the CoCo community uses, with the ROM calls Radio Shack documents (`POLCAT`, `CHROUT`,
   `CSRDON`, `BLKIN`, `BLKOUT`, `JOYIN`) by those names. Where a book labels by address (`LA171`), the label is named
   after what it is or the routine it is in, as `Level2.asm` does. Comments are our own.
2. **One source per BASIC, every version.** `ColorBasic.asm` with `VERSION` 10-13 (12 by default),
   `ExtendedBasic.asm` with 10 or 11, `DiskBasic.asm` with 10 or 11, chosen by conditionals as `Level2.asm` chooses
   its revision. Disk BASIC's two versions share one source too: 1.1's inserted code is in conditionals, and the
   labels move with it.
3. **The CoCo 3 shares the sources.** `COCO3=1` applies the CoCo 3's patches to `ColorBasic.asm` and
   `ExtendedBasic.asm`, and `Coco3.asm` holds the rest; one build assembles the 32 KB image from the three. The ROM
   reads as what it is, the older BASICs patched, with the CoCo 3's additions on top.
4. **The machine builds its ROMs from the sources** when the launch names no dumps, so `romDirectory` and
   `RETROCORE_COCO_ROMS` become optional, and dumps still win when given.
5. **Where they live:** `src/Retrocore.Machines.Coco/Roms`, beside the machine as the Model I's are, copied beside
   the debug host as SDK modules.
6. **Review after Color BASIC**, before the rest, as the DOS sources were reviewed after DOS 3.3 1983.

## Stages

0. **References.** The four *Unravelled* books, offered as PDFs by
   [computerarcheology.com](https://www.computerarcheology.com/CoCo), into `C:\Users\jerem\Retrocore\docs\coco`,
   each shown with its site, file and checksum and approved first. The Technical Reference Manual, already there,
   names the documented ROM calls.
1. **Color BASIC.** `ColorBasic.asm` for 1.0-1.3. `CocoSdkModules` assembles it; `CocoRomSourceTests` pins each
   version by SHA-256 and compares it with the dumps when they are present. The debugger maps it as the Color BASIC
   area, so the sample's `JSR [CHROUT]` steps into the source. A CoCo with Color BASIC alone boots from it.
   **Review.**
2. **Extended Color BASIC** 1.0 and 1.1; the default CoCo 1 and 2 boot from the sources. Built: `ExtendedBasic.asm`,
   with Color BASIC's RAM, hardware, tokens and error codes moved into `ColorBasicEquates.asm` for both to include,
   Extended BASIC's own in `ExtendedBasicEquates.asm`, and the Color BASIC routines it calls in
   `ColorBasicEntries.asm`, each inheriting its documentation. Pinned by digest, mapped by the debugger, and stepped
   into by `tools/Test-CocoDap.mjs` through the console out hook.
3. **Disk Extended Color BASIC** 1.0 and 1.1; the disk controller's ROM comes from the source. Built:
   `DiskBasic.asm`, with its RAM, file layouts, controller registers, tokens and error codes in
   `DiskBasicEquates.asm`, and the Extended BASIC routines it calls in `ExtendedBasicEntries.asm`, as
   `ColorBasicEntries.asm` now lists Color BASIC's for both. A launch without dumps builds it for the disk
   controller; it is pinned by digest, mapped by the debugger in the cartridge area, and stepped into by
   `tools/Test-CocoDap.mjs` through the console out hook.
4. **The CoCo 3:** the `COCO3` patches and `Coco3.asm`, assembled into the 32 KB image and pinned. Built:
   `ExtendedBasic.asm` and `ColorBasic.asm` apply the CoCo 3's patches in place when `COCO3` is set, and `Coco3.asm`
   holds `$C000-$FFFF`: the start-up, which copies the ROM into RAM and patches the copy further from its table, and
   Super Extended Color BASIC, with its hardware and RAM in `Coco3Equates.asm` and the routines the patches call in it
   in `Coco3Entries.asm`. `CocoSdkModules.AssembleCoco3` builds the image; it is pinned by digest and compared with
   the dump when present, a launch without dumps runs it, the debugger maps the three sources over the CoCo 3's RAM
   copy, and `tools/Test-CocoDap.mjs` steps into it with no dumps.
5. **Nothing external.** Launches without dumps, `tools/Test-CocoDap.mjs` running with no ROMs and stepping into
   `ColorBasic.asm`, and [Coco.md](../Coco.md), the READMEs and the extension's options updated to match.

Each stage keeps the rules the SDK's sources follow: the native dialect; `;;` documentation for IntelliSense;
`SdkDocumentationIsClean` after editing comments; and headers that say only that a source is maintained by hand and
assembles byte-identically, without describing how it was produced or linking local copies.

## After this

A BASIC thread for Color BASIC, as Level II and AppleSoft have (statement breakpoints, stepping, variables), needs
the sources' names for the interpreter's loop and pointers, so it follows this work as its own plan.
