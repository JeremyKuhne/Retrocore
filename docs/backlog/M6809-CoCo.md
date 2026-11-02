# Backlog: the 6809 and the TRS-80 Color Computer

Status: **not started**. The next CPU after the Z80, and the machine built around it, following the path the Z80
and the Model I took.

## Why the 6809

It is the third great 8-bit CPU, and the Color Computer is the TRS-80 line's continuation. Its instruction set
also tests the shared ISA model where the 6502 and Z80 did not:

- a prefix-paged opcode map ($10 and $11 pages);
- indexed addressing with a postbyte that encodes the register, the offset size, auto-increment and indirection;
- PSHS and PULS register lists;
- TFR and EXG register pairs;
- two stack pointers.

## The CPU

`Retrocore.Cpu.M6809`, like `Retrocore.Cpu.Z80`:

1. **The instruction set as data** (`M6809Isa.txt`). The prefix pages map onto the format's split opcodes. The
   indexed postbyte needs a new kind of operand field: a postbyte computed from the operand. That is the one
   extension the ISA format needs, and it serves the 6309 later too.
2. **The native syntax.**
   - `LDA [,X]`, `LDA 5,X`, `LDA ,X++`, `LEAX -2,U`;
   - immediate `#`;
   - direct-page versus extended chosen by value, or forced with `<` and `>` as Motorola does;
   - register lists for PSHS and PULS.
3. **A cycle-exact core.** E/Q clock cycles, including the dead cycles of indexed modes, and SYNC, CWAI, FIRQ,
   IRQ and NMI. It is verified against SingleStepTests' 6809 set and the 6809 functional test suites.
4. **The 6309** later, as a variant set, as the 65C02 is to the 6502.

## The machine: Color Computer 2

A CoCo 2 first: it is the simplest, and the most software runs on it.

- **The MC6883 SAM:** the memory map, the video address generator and the CPU rate (0.89 or 1.79 MHz).
- **The MC6847 VDG:** text, semigraphics and the graphics modes, with artifact colors on NTSC, rendered per
  scanline like the IIe's video.
- **Two MC6821 PIAs:** the keyboard matrix, joysticks, the cassette, the 6-bit DAC, the sound multiplexer, and
  the field-sync and line-sync interrupts.
- **Cartridges:** ROM packs, then the FD-502 disk controller (WD1793) with JVC and DSK images, sharing the
  Model I's floppy model.
- **ROMs:** Color BASIC and Extended Color BASIC, as dumps you supply. Then, as for the Model I, documented
  native sources that build byte-identical ROMs, maintained by hand. Disk BASIC follows with the disk controller.

The CoCo 3 (GIME, 128K/512K, 80 columns) and OS-9 come after the CoCo 2 runs its software.

## Tooling

The assembler, disassembler, debugger and extension need no new structure; a 6809 debug target adds:

- a call tracker for JSR, BSR, LBSR and the interrupts, which stack the whole register set, verified against
  the stack as the Z80's is;
- the register view, with both stacks, DP and CC's flags;
- `Keeps:` sections naming 6809 registers, and its flags by the shared words (`carry`, `half-carry`; the
  6809's E and F flags need words of their own), from `flag` lines in its instruction-set description.

[More dialects](Dialects.md) covers the Motorola, EDTASM+ and lwasm syntaxes.

## Testing

- The CPU against SingleStepTests at every cycle.
- The machine against MAME's `coco2` with the same keystroke oracle the Model I uses
  ([`Trs80Oracle.lua`](../../tools/Trs80Oracle.lua) generalized).
- The ROM sources pinned by digest.
- A DAP script like the Model I's.

Every download (ROM dumps, test suites, MAME's machine) is approved first, as before.
