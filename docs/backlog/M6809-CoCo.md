# Backlog: the 6809 and the TRS-80 Color Computer

Status: **MC6809 core, undocumented behaviour, instruction set and native assembly done; Color Computer 2
next**. The next CPU after the Z80, and the machine built around it, following the path the Z80 and the Model I
took.

## Why the 6809

It is the third great 8-bit CPU, and the Color Computer is the TRS-80 line's continuation. Its instruction set
also tests the shared ISA model where the 6502 and Z80 did not:

- a prefix-paged opcode map ($10 and $11 pages);
- indexed addressing with a postbyte that encodes the register, the offset size, auto-increment and indirection;
- PSHS and PULS register lists;
- TFR and EXG register pairs;
- two stack pointers.

## The CPU (done)

[`Retrocore.Cpu.M6809`](../../src/Retrocore.Cpu.M6809), like `Retrocore.Cpu.Z80`:

1. **The instruction set as data** ([`M6809Isa.txt`](../../src/Retrocore.Cpu.M6809/M6809Isa.txt)). The `$10` and
   `$11` prefix pages and postbyte operand fields (`indexed`, `pair`, `sysmask`, `usermask`) drive the assembler,
   disassembler, flow analyzer and documentation checks. The shared code knows those fields only through
   `PostbyteCodec`; [`M6809PostbyteCodec`](../../src/Retrocore.Cpu.M6809/M6809PostbyteCodec.cs) supplies the
   MC6809's, one per instruction set, so the 6309 can bring its own (its `W` indexed modes and extra `TFR`
   registers).
2. **The native syntax.**
   - `LDA [,X]`, `LDA 5,X`, `LDA ,X++`, `LEAX -2,U`, `LEAY Table,PCR`, `JMP [$FFFE]`;
   - immediate `#`;
   - direct-page versus extended chosen by value, or forced with `<` and `>` as Motorola does;
   - indexed offsets sized by value, a zero offset as none (`0,X` is `,X`, as Motorola's assembler and lwasm
     encode it), or forced with `<<` (5-bit), `<` and `>`;
   - register pairs for `TFR` and `EXG`, and register lists for `PSHS`/`PULS`/`PSHU`/`PULU`.
3. **A cycle-exact state-machine core.** Allocation-free per-clock stepping and snapshots, including the internal
   cycles of indexed modes, `SYNC`, `CWAI`, `FIRQ`, `IRQ` and `NMI`, verified against the pinned MC6809
   functional, cycle-count and interrupt test suites ([`Fetch-M6809Tests.ps1`](../../tools/Fetch-M6809Tests.ps1))
   and focused per-cycle bus traces.
4. **The 6309** later, as a variant set, as the 65C02 is to the 6502.

## The CPU: undocumented behaviour (built 2026-11-12)

The core, the instruction-set description and the hover docs follow David Banks's
[Undocumented 6809 Behaviours](https://github.com/hoglet67/6809Decoder/wiki/Undocumented-6809-Behaviours) and David
Flamand's
[Comprehensive Document of 6809 Undocumented and Undefined Behavior](https://gitlab.com/dfffffff/6809_undoc/-/blob/main/6809_undocumented_behavior.pdf),
both from real chips, over MAME's `m6809` core where they differ (`X18`, `XADDU`, `DAA`'s V, halt and catch fire
taking interrupts, the store-immediate flags). [`M6809UndocumentedTests`](../../tests/Retrocore.Tests/M6809UndocumentedTests.cs)
pins each behaviour cycle by cycle, with MAME bug [06797](https://mametesters.org/view.php?id=6797) (`$10 $4F` is
`CLRA` on a real CoCo).

Decided 2026-11-12, and kept as is unless new evidence turns up:

- **Indexed mode `1RRI1010`** runs as `,R`. Flamand (page 6) describes an address formed from PC and a change to
  A in terms too ambiguous to build, and no known software uses it.
- **`$3E` (`XRES`)** leaves I and F alone, as the wiki states explicitly and MAME agrees; Flamand's table says it
  sets them.
- **`$10 $8D`** runs as `BSR`, as MAME does; Flamand found it unreliable on hardware, so no choice matches it.
- **Dummy reads.** Internal cycles stay bus-idle, where the chip reads PC or `$FFFF` as MAME models. Revisit with a
  MAME bus trace once the CoCo 2 runs, if I/O at those addresses turns out to matter.
- **`RESET` held for a single cycle** fetches a corrupted vector on hardware (Flamand, page 10); not modelled, as
  the machines hold RESET for many cycles and Flamand's account is incomplete.
- **Non-canonical indexed postbytes** (modes 7, 10 and 14, `$8F`, indirect `,R+` and `,-R`) execute but
  disassemble as bytes, which round-trip exactly; syntax waits for real code that uses them.

## The machines: Color Computer 1, 2 and 3

All three models are variants of one machine, as the Apple II family is: one project, one launch id, a model
setting. What they share and where they differ:

| | CoCo 1 (1980) | CoCo 2 (1983) | CoCo 3 (1986) |
| --- | --- | --- | --- |
| CPU | MC6809E, 0.89 MHz | MC6809E, 0.89 MHz | MC6809E (68B09E), 0.89 or 1.79 MHz |
| Memory map, clock | MC6883 SAM | MC6883 SAM (74LS785 on later boards) | GIME: MMU in 8 KB pages, 128 KB or 512 KB |
| Video | MC6847 VDG | MC6847, MC6847T1 with lowercase on the 2B | GIME: the VDG modes plus 40/80-column text and higher-resolution graphics, a 16-color palette, RGB or composite |
| RAM | 4, 16, 32 or 64 KB | 16 or 64 KB | 128 or 512 KB |
| ROM | Color BASIC 1.0-1.2, optional Extended 1.0-1.1 | Color BASIC 1.2-1.3 and Extended 1.1 | 32 KB: Color, Extended and Super Extended BASIC |
| Shared | Two MC6821 PIAs (keyboard matrix, joysticks, cassette, 6-bit DAC, sound multiplexer, sync interrupts), the cartridge port, the serial port | | Plus the GIME's own IRQ and FIRQ sources and timer |

MAME's drivers are the oracle: `coco` (1 and 2, with BASIC 1.0-1.2 as BIOS choices), `coco2b` and `coco3`.

### Decisions (agreed 2026-11-12)

- **Project and naming.** A new `Retrocore.Machines.Coco`, apart from the Model I's project: the CPU, memory map,
  video and storage share nothing with it but the floppy model. Launch id `coco` with `model: "coco1" | "coco2" |
  "coco3"`; the 2B (MC6847T1, BASIC 1.3) is an option of `coco2`, and RAM size an option of every model.
- **Shared chips.** The MC6821 PIA goes in `Retrocore.Core` (`Machines/Chips`), as the Apple III's 6522 did.
- **Order.** CoCo 1 and 2 first (they are one design), then the CoCo 3, then disks, so each step runs software.
- **Defaults.** CoCo 1: 16 KB, Color BASIC 1.2 with Extended 1.1. CoCo 2: 64 KB, BASIC 1.2 with Extended 1.1
  (the 2B option, 1.3). CoCo 3: 128 KB, NTSC.
- **ROMs** are dumps you supply, as for the IIe and Model I, until native sources exist.
- **Review.** All phases are built, then reviewed once.

### Phases

Phases 0-6 are built (2026-11-12) and await review: fixtures, the CoCo 1 and 2, the VDG, cassette, sound,
joysticks and cartridges, the CoCo 3's GIME, the disk controller with the 6809's HALT input, and the debugger and
extension. [Coco.md](../Coco.md) describes what they emulate. What is left:

7. **Native ROM sources** for Color, Extended, Disk and Super Extended BASIC, byte-identical and pinned by digest,
   maintained by hand: [CocoRomSources.md](CocoRomSources.md), a draft awaiting decisions. Until then the ROMs
   debug as disassembly and the machine needs the dumps.

Known gaps in what is built:

- **GIME video.** Palette changes mid-frame apply to the whole frame; the CoCo 3's composite artifact colors in
  two-color graphics are not drawn; the GIME timer and keyboard interrupt have no tests of their own.
- **Disks** are kept in memory: a changed disk is not written back to its file, as on the Model I.
- **Color BASIC** debugs at the 6809 level only; a BASIC thread like Level II's and AppleSoft's, and `basic`
  launches, would follow the ROM sources.
- **Cassette** reads and writes `.cas`; `.wav` is not read.

OS-9 and the 6309 come after.

## Tooling

The assembler, disassembler, debugger and extension need no new structure; a 6809 debug target adds:

- a call tracker for JSR, BSR, LBSR and the interrupts, which stack the whole register set, verified against
  the stack as the Z80's is;
- the register view, with both stacks, DP and CC's flags;
- `Keeps:` sections naming 6809 registers, and its flags by the shared words (`carry`, `half-carry`; the
  6809's E and F flags need words of their own), from `flag` lines in its instruction-set description.

[More dialects](Dialects.md) covers the Motorola, EDTASM+ and lwasm syntaxes.

## Testing

- The CPU against the pinned MC6809 functional, cycle-count and interrupt suites (`tools\Fetch-M6809Tests.ps1`)
  and Motorola Appendix F per-cycle bus traces.
- The machines against MAME's `coco`, `coco2b` and `coco3` with the same keystroke oracle the Model I uses
  ([`Trs80Oracle.lua`](../../tools/Trs80Oracle.lua) generalized).
- The ROM sources pinned by digest.
- A DAP script like the Model I's.

Every download (ROM dumps, test suites, MAME's machine) is approved first, as before.
