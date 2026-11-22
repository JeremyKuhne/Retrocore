---
name: retrocore-native-assembly
description: Write, edit and review assembly in Retrocore's native dialect, for the 6502 family and the Z80, including the SDK's hand-maintained ROM sources (Monitor.asm, the IIe firmware, WozMonitor.asm, Apple-1 BASIC, Level2.asm, Level1.asm, Model3.asm, Model2Boot.asm, CharacterGenerator.asm). Use when creating or changing a .asm or .s file in native syntax, writing Z80 or 6502 examples, documenting routines with ;; comments, converting a disassembled or old-style source to the maintained style (structure, names, constants, links, historical names), or checking that a ROM source still assembles byte-identically.
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

Follow [the style guide](../../../docs/AssemblyStyle.md); it has the rules and complete examples. The ones
most often missed:

- **Structure:** each routine is a `.proc`, and a family that shares code or entries is a `.scope`. Labels go
  on their own line at column 0 with names for what happens there (`NextRow`, `NotFound`), never `ROUTINE_1` or
  an address (`L_F8C2`); drop a label nothing refers to.
- **Names:** PascalCase for routines, labels, variables, tables, macros and types; UPPER_SNAKE_CASE for constants,
  and for struct and union fields and enum members, which are offsets and values.
  Name things after what the code does. In the SDK's ROM sources, names follow the original documentation:
  Apple's for the IIe; the documented ROM calls and Microsoft's BASIC names for Level II; Li-Chen Wang's Tiny
  BASIC names for Level I; for the PET's editors and kernals, Commodore's names from its 1979 BASIC 4 kernal
  listing, where BASIC 4 has the same code, and Microsoft's for the jump table at `$FFC0`.
- **Historical names are never dropped.** A name from a manual or listing that a definition no longer has
  goes in its `;; Also:` section, with the documents' keys from [the bibliography](../../../docs/Bibliography.md):
  `;; Also: COUT (A2RM78)`. Old code keeps assembling and the editor offers the new name. Add a document to the
  bibliography before citing it.
- **Constants:** every value that means something gets one (unit numbers, offsets, masks, counts, control
  codes); 0 for clearing and 1 or 2 for stepping a pointer stay numbers.
- **Documentation:** a `;;` block **above** every definition (never a trailing `;;`, except on a type's member);
  it documents only the definition below it, so a group heading is a plain `;` comment. Routines get a summary, then `In:`, `Out:`
  and `Keeps:`; macros get `Parameters:`. [DocComments.md](../../../docs/DocComments.md) has the format.
- **`Keeps:`** lists only what the routine really preserves, from its code and everything it calls: the
  debugger checks it when the routine returns.
- **Registers and flags:** registers by the CPU's letters, flags by word (`carry`, `zero`, `negative`,
  `overflow`, `parity`, `half-carry`, `subtract`, `decimal`, `interrupt`): `;; Out: A = the key, carry = set
  for Return`. Never `C`, `Z` or `NZ` for a flag: on the Z80 `C` is the register. There is no `Flags:` section.
- **Links:** write `<Name>`, `<Scope::Name>` or `<text at Target>` for every documented definition a comment
  names. The names before `=` in `In:`/`Out:` entries are not links; an unresolved link is a lint error.
- **Data layouts** are `.struct`s, and each member is documented: a `;;` block above it when it has more to say
  than a few words or a historical name (`;; Also: IBCMD (DOS33)` reaches `Iob::COMMAND`), a trailing `;;`
  otherwise, or the type's `Members:` when all its members are plain; never two of these. A member's topic and
  the quick fix use its qualified name; an anonymous `.union`'s members are the enclosing type's.
- **Layout:** instructions four spaces in; each logical step a blank line and a short `;` heading at the code's
  indentation; comments indented like their code; macro bodies one level in; a type's members one level in, a
  nested type's one more.
- **Data:** tables through macros, with `.assert` where an entry's position matters; text as `.byte "TEXT"`;
  empty storage as `.res`.

## Converting a source to the style

Read [ConvertingSources.md](../../../docs/ConvertingSources.md) first: who the sources are for (developers new to
the old machines, with the old names kept as a bridge), the method (inventory, citations, a rename table the owner
reviews, conversion, verification) and the rules learned so far. The [conversion logs](../../../docs/conversions/README.md)
are the precedents: follow a settled rule rather than deciding it again.

For a disassembly, an old-style SDK source, or anything maintained by hand that does not follow the guide yet:

1. **Propose the names first.** For each file, list old name, new name and why, and get them reviewed before
   converting. Keep every documented old name for its definition's `Also:` section.
2. **Convert a routine or two at a time**, then assemble and compare. The bytes never change; a source that
   stops matching is fixed before going on.
3. **Work out each fact from the code:** what a value means before naming it, what a routine keeps by reading
   it and everything it calls, what a comment claims. A doubt stays in the comment, saying what is uncertain
   and why.
4. **Put `; retrocore: style=strict` on the first line** of each converted file, so the lint checks the
   style, and **run the lint** (`SdkDocumentationTests`, or the editor) before finishing. Fix every problem.
5. **Splitting the work** across several people or agents: give each its own files and copy of the source,
   and have each record the names it changes that other files use (`{"Old": "New::Name"}`). Apply each one's
   renames only to the others' files, never back to its own, then assemble and lint the whole.

## Editing the SDK's ROM sources

The sources in `src/Retrocore.Machines.Apple2/Roms`, `src/Retrocore.Machines.Apple1/Roms`,
`src/Retrocore.Machines.Trs80/Roms` and `src/Retrocore.Machines.Kaypro/Roms` (MBASIC.COM's too) must assemble
byte-identically to the ROMs, for every variant: `ENHANCED` for the IIe; `REVISION` 12 or 13 for Level II; `MODEL` 1
or 3 for `Level1.asm`; `MODEL` and `ROMC` for `Model3.asm`; `VERSION` and `FILL_11BE` for `Model2Boot.asm`;
`MODEL4P` for `Model3CharacterGenerator.asm`. They are maintained by hand: change names, comments and structure only
in ways that keep the bytes.

- **Renaming:** rename a label everywhere it is used, including other variants' `.if` blocks and the sources
  that include the file. A documented name that changes goes in the definition's `Also:` section.
- **Rewriting data as macros:** check that the macro emits exactly the bytes it replaces.
- **Verifying:** run the digest tests, which need no ROMs:

  ```powershell
  dotnet test tests/Retrocore.Tests -c Release --filter "FullyQualifiedName~SdkDocumentationTests|FullyQualifiedName~SystemSourceTests|FullyQualifiedName~Trs80RomSourceTests|FullyQualifiedName~Apple1RomTests|FullyQualifiedName~AppleSoftTests|FullyQualifiedName~KayproTests"
  ```

  With the dumps present (`RETROCORE_IIE_ROMS`, `RETROCORE_TRS80_ROMS`), the same tests name the first byte
  that differs.

Byte identity proves the assembled program has not changed; it does not prove that a new comment or contract is
semantically correct. For `In:`, `Out:`, `Uses:` and `Keeps:`, trace every relevant exit path, including errors,
timeouts, and conditional branches. Where a claim is consumed by the debugger or changes routine behavior, add a
focused runtime or contract test with distinct register/flag values. Check hardware/model-specific conditional
branches independently. Use [retrocore-conformance](../retrocore-conformance/SKILL.md) for oracle selection and
evidence limits, and report any path that could not be exercised.

## Checking a source

Assemble a file without a test:

```powershell
dotnet build src/Retrocore.Debug -c Release
dotnet artifacts/AnyCPU/Release/Retrocore.Debug/net11.0/Retrocore.Debug.dll --assemble program.asm program.bin --cpu Z80 --origin $7000
```

It writes the binary and a `.dbg` file, or prints each error with its file and line. In VS Code, a
`retrocore-asm` document shows errors as you type.

When you add an example to `docs/NativeAssembly.md`, `docs/AssemblyStyle.md` or this skill's files, put it in
an `asm` fence: `NativeAssemblyDocsTests` assembles every one of them, and lints those of the style guide and
this skill. Use a `text` fence for one that is meant to fail or that
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
