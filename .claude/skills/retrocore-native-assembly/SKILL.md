---
name: retrocore-native-assembly
description: Write, edit and review assembly in Retrocore's native dialect, for the 6502 family and the Z80, including the SDK's hand-maintained ROM sources (Monitor.asm, the IIe firmware, WozMonitor.asm, Level2.asm, Level1.asm, Model3.asm, Model2Boot.asm, CharacterGenerator.asm). Use when creating or changing a .asm or .s file in native syntax, writing Z80 or 6502 examples, documenting routines with ;; comments, or checking that a ROM source still assembles byte-identically.
license: MIT
compatibility: Requires the .NET SDK to assemble and test. The full reference is docs/NativeAssembly.md.
metadata:
   portability: repository
   applicability: retrocore
   risk: local-write
   maturity: canary
   requires: none
---

# Retrocore native assembly

The native dialect looks like other assemblers, and that is the trap: Zilog, ca65 and EDTASM habits produce
errors, or worse, sources that assemble to the wrong bytes. Read these rules before writing a line, use
[examples.md](examples.md) for idioms, and look anything else up in [the reference](../../../docs/NativeAssembly.md).

## Rules that differ from what you expect

1. **Z80 memory operands use brackets: `LD A,[HL]`, `LD [IX+5],A`, `JP [HL]`, `OUT [C],A`, `IN A,[$FF]`.**
   Parentheses always group an expression. `LD A,(HL)` is an error, and `LD A,(5)` loads the immediate 5.
2. **Labels need a colon** (`Loop:`). A word without one is read as an instruction. One label per line.
3. **Constants are `Name = value`** (or `Name: .equ value`). `Name .equ value` and `EQU` do not work; `.set` makes
   a reassignable variable.
4. **Data directives are `.byte`, `.word`, `.res`, `.dbyt`, `.dword`, `.asciiz`, `.hiascii`.** There is no `DB`,
   `DW`, `DEFB`, `DEFS` or `.db`. Strings go in `.byte "TEXT"`, never `'TEXT'`.
5. **Numbers are `$1F`, `0x1F`, `%1010` and `'A'`.** There are no `1FH`/`1010B` suffixes, `%` is never remainder
   (use `.mod`), and `*` is the current address (not `$`).
6. **Precedence is C's:** `|` is looser than `&`, which is looser than comparisons. Unary `<` and `>` bind to
   the next primary only, so `#<Table+1` is `(<Table)+1`. Write `#<(Table+1)`.
7. **Inequality is `!=`**; `<>` is an error. Use `.not` for logical NOT.
8. **A label on a preprocessing directive's line** (`Table: .repeat 4`) names where the directive appears,
   but not on a `.endmacro` or `.endrepeat` line, which is an error.
9. **Symbols and macro names are case-sensitive**; mnemonics, registers and directives are not.
10. **Conditionals and `.repeat` counts need values known at that point in the source**: constants and earlier
    variables, not labels or `*`.
11. **On the 6502, an address below $100 assembles as zero page** when it is known; `a:`, `!` or `.w` force
    absolute and `z:` forces zero page.
12. **`.cpu Name` picks the instruction set**: `Mos6502` (undocumented opcodes included), `Wdc65C02`,
    `Rockwell65C02`, `65SC02` or `Z80`.

## Writing a source

- Start with `.cpu`, then constants, then `.org` and the code. Document each routine with a `;;` block right
  above its label: a summary line, then compact sections such as `;; In: A = the character`, `;; Out:`,
  `;; Uses:` and `;; Keeps: X, Y`. The debugger checks `Keeps:` when the routine returns, so only list what
  the routine really preserves. [DocComments.md](../../../docs/DocComments.md) has the format.
- `;;` documents exactly one definition. A heading over a group of constants or a stretch of code is a plain `;`
  comment, with each constant documented by its own trailing `;;`. The lint fails a `;;` block above a definition
  that has a trailing `;;` of its own.
- Name registers by the CPU's letters and flags by word on every CPU, in `In:` and `Out:` (there is no
  `Flags:` section): `;; Out: A = the key, carry = set for Return`, `zero = found`. Never `C`, `Z` or `NZ` for
  a flag: on the Z80 `C` is the register. The words are `carry`, `zero`, `negative`, `overflow`, `parity`,
  `half-carry`, `subtract`, `decimal` and `interrupt`, as the routine's CPU has them.
- Prefer named constants, macros for repeated table shapes, and `.assert` for layout assumptions (a table
  fitting a page, a routine landing at a documented address) over comments that state them.
- Name things after what the code does. In the SDK's ROM sources, names follow the original documentation:
  - Apple's for the IIe;
  - the documented ROM calls and Microsoft's BASIC names for Level II;
  - Li-Chen Wang's Tiny BASIC names for Level I.

  Labels inside a routine are named after it (`ROUTINE_1`). Never use a name that is only an address (`SUB_F8C2`,
  `LE5D1`, `unref_e5cc`): find out what the code does and name it, and drop a label that nothing refers to.

## Editing the SDK's ROM sources

The sources in `src/Retrocore.Machines.Apple2/Roms`, `src/Retrocore.Machines.Apple1/Roms` and
`src/Retrocore.Machines.Trs80/Roms` must assemble byte-identically to the ROMs, for every variant: `ENHANCED` for the
IIe; `REVISION` 12 or 13 for Level II; `MODEL` and `ROMC` for `Model3.asm`; `VERSION` and `FILL_11BE` for
`Model2Boot.asm`; `MODEL4P` for `Model3CharacterGenerator.asm`. They are maintained by hand: change names, comments and
structure only in ways that keep the bytes.

- **Renaming:** rename a label everywhere it is used, including other variants' `.if` blocks.
- **Rewriting data as macros:** check that the macro emits exactly the bytes it replaces.
- **Verifying:** run the digest tests, which need no ROMs:

  ```powershell
  dotnet test tests/Retrocore.Tests -c Release --filter "FullyQualifiedName~SdkDocumentationTests|FullyQualifiedName~SystemSourceTests|FullyQualifiedName~Trs80RomSourceTests|FullyQualifiedName~Apple1RomTests|FullyQualifiedName~AppleSoftTests"
  ```

  With the dumps present (`RETROCORE_IIE_ROMS`, `RETROCORE_TRS80_ROMS`), the same tests name the first byte
  that differs.

## Checking a source

Assemble a file without a test:

```powershell
dotnet build src/Retrocore.Debug -c Release
dotnet artifacts/AnyCPU/Release/Retrocore.Debug/net10.0/Retrocore.Debug.dll --assemble program.asm program.bin --cpu Z80 --origin $7000
```

It writes the binary and a `.dbg` file, or prints each error with its file and line. In VS Code, a
`retrocore-asm` document shows errors as you type.

When you add an example to `docs/NativeAssembly.md` or to this skill's files, put it in an `asm` fence:
`NativeAssemblyDocsTests` assembles every one of them. Use a `text` fence for one that is meant to fail or that
needs files.

## Common errors

| Message | Usual cause |
| --- | --- |
| `Unresolved expression '(HL)'` | Zilog parentheses on the Z80; write `[HL]`. |
| `Unknown instruction or unsupported addressing mode: X ...` | A label without its colon, a form the CPU lacks (`lda zp,y`), or a missing `.cpu`. |
| `Operand is outside the byte range; use < or > for extraction.` | A 16-bit value in a byte; take `<` or `>` of it, in parentheses if it is a sum. |
| `Missing expression operand.` | `Name .equ value`, a `.paramcount` outside a macro, or an empty operand. |
| `Conditional requires a constant known at this point in source order.` | A label or later symbol in `.if` or a `.repeat` count. |
| `Use != for inequality ...` | `<>` from another assembler. |
| `A character literal holds one character ...` | `'TEXT'` where a string needs `"TEXT"`. |
| `Displacement is outside the signed 8-bit range.` | An `[IX+d]` displacement beyond -128 to 127. |
| `Restart address must be $00, $08, ...` | `RST 7` instead of `RST $38`. |
