# Native assembly language reference

The native dialect is Retrocore's own assembly language. It reads the same on every CPU: 6502-family sources and
Z80 sources share their directives, expressions, preprocessing and scopes, and differ only in their
instructions. The SDK's ROM sources are written in it.

Native borrows ca65's preprocessing (macros, `.define`, `.struct`, `.charmap` and its functions) but has its own
expression syntax, and it writes Z80 memory operands in brackets so that parentheses always group.

Every example in an `asm` block on this page assembles; [`NativeAssemblyDocsTests`](../tests/Retrocore.Tests/NativeAssemblyDocsTests.cs)
checks them.

- [Selecting the dialect](#selecting-the-dialect)
- [Lines, labels and comments](#lines-labels-and-comments)
- [Expressions](#expressions)
- [Symbols](#symbols)
- [Data](#data)
- [Layout and sections](#layout-and-sections)
- [CPUs and instructions](#cpus-and-instructions)
- [6502 operands](#6502-operands)
- [Z80 operands](#z80-operands)
- [6809 operands](#6809-operands)
- [Macros](#macros)
- [Conditionals](#conditionals)
- [Repeats](#repeats)
- [Textual definitions](#textual-definitions)
- [Structures and enumerations](#structures-and-enumerations)
- [Character maps](#character-maps)
- [Functions](#functions)
- [Includes](#includes)
- [Exports, assertions and messages](#exports-assertions-and-messages)
- [Documentation comments](#documentation-comments)
- [Hosting the assembler](#hosting-the-assembler)
- [Limits](#limits)
- [Directive index](#directive-index)

## Selecting the dialect

Native is the default. A file's first line can name its dialect explicitly:

```asm
; retrocore: dialect=native
```

The other values are `ca65`, `merlin` and `macro10`. An `.include` can also name the dialect of the file it
includes (see [Includes](#includes)). In VS Code, a file whose language is `retrocore-asm` is native unless its
first line says otherwise.

## Lines, labels and comments

A line holds at most one statement: an optional label, then an instruction, a directive or a macro call, then
its operand. There is no statement separator and no line continuation. Indentation does not matter.

```asm
Start:  lda #1          ; a label, an instruction and its operand
        sta $0200
Done:                   ; a label on its own line
```

**Labels** end with a colon, wherever they start; a word without a colon is read as an instruction. A line
holds one label. A label names the address of the statement after it on the line, or of the next statement.
A label on a preprocessing directive's line, such as `Table: .repeat 4`, names the address where the
directive appears. As in ca65, it is defined only when the code just before the directive is assembled, so a
label on `.else` or `.endif` belongs to the block that line closes. A label cannot be on a `.endmacro` or `.endrepeat` line, which ends
every expansion of its body.

**Comments** start with `;` and run to the end of the line, except inside a string or character. `;;` starts a
[documentation comment](#documentation-comments), which the assembler treats as an ordinary comment.

**Identifiers** start with an ASCII letter, `_` or `@`, and continue with letters, digits and `_`. Characters
after the first may be any Unicode letter or digit. `.` is never part of a name. An identifier starting with `@`
is a [cheap local](#cheap-local-labels).

**Case.** Mnemonics, directives, register names and `.cpu` names ignore case. Symbols, scopes, macros and
`.define` names do not: `Label` and `label` are different symbols.

## Expressions

Expressions are evaluated in 64-bit signed integers, and overflow is an error.

### Literals

| Form | Example | Notes |
| --- | --- | --- |
| Decimal | `42` | |
| Hexadecimal | `$1F`, `0x1F` | |
| Binary | `%1010` | `%` is never the remainder operator; use `.mod`. |
| Character | `'A'` | One character, no escapes; its code goes through the [character map](#character-maps). `'AB'` is an error: strings use double quotes. |
| String | `"text"` | Only as a whole operand of `.byte`, `.hiascii`, `.asciiz` or a function; no escapes and no embedded `"`. |
| Current address | `*` | The address of the current instruction, or of the current element in a data list. |

### Operators

From tightest to loosest; binary operators associate to the left.

| Operators | Meaning |
| --- | --- |
| `-` `+` `~` `<` `>` `.not` (unary) | Negate, plus, bitwise NOT, low byte, high byte, logical NOT. They apply to the next primary: `<Label+1` is `(<Label)+1`, so write `<(Label+1)`. |
| `.lobyte(e)` `.hibyte(e)` `.bankbyte(e)` | Bits 0-7, 8-15 and 16-23. The parentheses are required. |
| `*` `/` `.mod` | Multiply, divide (truncating), remainder (with the dividend's sign). |
| `+` `-` | Add, subtract. |
| `<<` `>>` | Shift; the count is 0-63. |
| `&` | Bitwise AND. |
| `^` | Bitwise XOR. |
| `\|` | Bitwise OR. |
| `=` `==` `!=` `<` `>` `<=` `>=` | Comparisons, giving 1 or 0. `=` and `==` both test equality. |
| `&&` `.and` | Logical AND, giving 1 or 0. |
| `.xor` | Logical exclusive OR. |
| `\|\|` `.or` | Logical OR. |

Both operands of a logical operator are evaluated: `0 && (1/0)` is a division by zero.

Native's precedence is C's, which is not ca65's: in ca65, `&` binds like `*` and `|` like `+`. Write
parentheses when a source must read the same in both.

```asm
Mask = %1010 | $F0 & ~$0F         ; | is looser than &: %1010 | ($F0 & $F0) = $FA
Low = <$1234                      ; $34
High = >$1234                     ; $12
Bank = .bankbyte($123456)         ; $12
Ok = (Low = $34) && (High = $12)  ; 1
Left = -7 .mod 3                  ; -1
```

Not part of the dialect: `<>` for inequality, which is an error (use `!=`), unary `!` (use `.not`), and `%`
as remainder.

## Symbols

### Constants, variables and labels

| Form | Defines |
| --- | --- |
| `Name = expr` or `Name: .equ expr` | A constant. It may use labels and later symbols, and is fixed once defined. |
| `Name .set expr`, `Name: .set expr` or `.set Name, expr` | A variable. Each assignment is a new value; a use sees the latest assignment before it in the source. |
| `Name:` | A label: the address of what follows. |

Constants, variables and labels share one namespace per scope, and defining a name twice is an error. Forward
references are allowed anywhere the value is needed only at the end: the assembler lays the program out again
until every address settles. A few places need a value already known at that point in the source: conditionals,
repeat counts, `.incbin` offsets, `.charmap`, structure counts and numeric function arguments.

```asm
Count .set 1
Count .set Count + 1     ; 2
Size = End - Start       ; a forward reference
Start:  .byte Count
End:
```

A host can predefine symbols, which then behave like constants at the top of the source. The SDK's sources
use this for variants:

```asm
.ifndef ENHANCED
ENHANCED = 1             ; the default when the host does not set it
.endif
```

### Scopes

`.scope Name` ... `.endscope` opens a namespace, and `.scope` without a name opens an anonymous one.
`.proc Name` ... `.endproc` does the same and also defines `Name` as the address of its first statement.
`A::B` names `B` in scope `A`, and `::Name` starts at the outermost scope.

```asm
.proc Clear
        ldx #0
Loop:   sta $0400,x      ; Clear::Loop
        inx
        bne Loop
        rts
.endproc

        jsr Clear
        jmp Clear::Loop
```

The rules follow ca65:

- A plain name resolves to the innermost enclosing scope that defines it, even later in the source.
- In `A::B`, `A` is a scope already opened at that point, or else a later one.
- Symbols and scopes are separate: `Value = 1` and `.scope Value` can coexist.

A `.scope` or `.proc` line cannot carry a label.

### Cheap local labels

A name starting with `@` belongs to the stretch of source since the last ordinary symbol was defined, so the
same `@name` can be reused after each routine's label. It cannot be qualified with `::`.

```asm
First:  ldx #3
@loop:  dex
        bne @loop
Second: ldy #3
@loop:  dey
        bne @loop
```

### Anonymous labels

A `:` alone defines an anonymous label. `:+` refers to the next one, `:++` to the one after, and `:-`/`:--` to
those before.

```asm
:       dex
        bne :-
        beq :+
        nop
:       rts
```

### Names shaped like registers

A word in a register's place in an operand is the register, even when a symbol has that name: with `X = $12`,
`lda X,x` loads from `$12` indexed by X.

## Data

| Directive | Emits |
| --- | --- |
| `.byte e, "text", ...` | One byte per expression (0-255) or per string character (ASCII). `.byt` is a synonym. |
| `.hiascii e, "text", ...` | As `.byte`, with bit 7 set in every byte, as Apple II text uses. |
| `.asciiz "text", ...` | Each string's characters, then a zero byte. |
| `.word e, ...` | 16-bit little-endian values, 0-$FFFF. |
| `.dbyt e, ...` | 16-bit big-endian values. |
| `.faraddr e, ...` | 24-bit little-endian values. |
| `.dword e, ...` | 32-bit little-endian values; negative values are stored in two's complement. |
| `.lobytes e, ...` / `.hibytes e, ...` | The low or high byte of each value. |
| `.res count[, fill]` | `count` bytes of `fill` (default 0). |

A byte value outside 0-255 is an error that suggests `<` or `>`; negative values are not wrapped.

```asm
Table:  .byte 1, 2, "AB", $0D
        .hiascii "OK"
        .asciiz "DONE"
        .word Table, $1234
        .dbyt $1234          ; $12 $34
        .faraddr $123456
        .dword -1
        .lobytes Table, $1234
        .res 4, $FF
```

## Layout and sections

| Directive | Does |
| --- | --- |
| `.org address` | Moves forward to an address, filling the gap. It cannot move backward. |
| `.align size[, fill]` | Pads to a multiple of `size`, a power of two up to 64K. |
| `.logicalorg [address]` | Assembles following code for another address without moving in the output, as for code copied elsewhere before it runs; an empty operand returns to the output's own addresses. |
| `.dum address` ... `.dend` | Lays out labels from `address` without emitting bytes, for storage maps. |
| `.checksum` | Emits the XOR of every byte before it in the current section. |
| `.section Name, origin, size[, fill[, trim]]` | Starts a separate output section, with its own address space and capacity. A nonzero `trim` drops its unused tail. `.section Name` returns to a defined section, and `.section .text` to the default one. |

The default section starts at the host's origin and has its image size; its unused space is zero. A section
defines `__Name_SIZE__` (the bytes it uses), `__Name_LOAD__` and `__Name_RUN__`. Addresses are 16-bit.

A label on an `.org` or `.align` line names the address before the padding; put it on the next line to name the
address after.

```asm
        .org $1000
Code:   nop
        .align 16, $EA
Copied:
        .logicalorg $0300
Relocated:              ; $0300, though it follows $1010 in the output
        jmp Relocated
        .logicalorg
        .dum $80
Pointer: .res 2
Count:  .res 1
        .dend
        .checksum
        .section Vectors, $FFFA, 6
        .word Code, Code, Code
```

When the host supplies an ld65-style linker configuration, `.section Name` selects one of its segments instead,
and code before any `.section` goes to `CODE`.

## CPUs and instructions

`.cpu Name` selects the instruction set for the instructions that follow. The first `.cpu` in a source also
applies to any instructions before it; without one, the host's CPU applies.

| Name | Instructions |
| --- | --- |
| `Mos6502` | The NMOS 6502, with its undocumented opcodes (`LAX`, `SAX`, `DCP`, `ISC`, `SLO`, `RLA`, `SRE`, `RRA`, `ANC`, `ALR`, `ARR`, `AXS`, `XAA`, `LAS`, `TAS`, `AHX`, `SHX`, `SHY`, `JAM` and the extra `NOP`s). |
| `Wdc65C02` | The WDC 65C02, with `BRA`, `PHX`/`PHY`/`PLX`/`PLY`, `STZ`, `TRB`, `TSB`, `WAI`, `STP`, and the bit instructions `BBR0`-`BBR7`, `BBS0`-`BBS7`, `RMB0`-`RMB7`, `SMB0`-`SMB7`. |
| `Rockwell65C02` | The Rockwell 65C02: the WDC set without `WAI` and `STP`. |
| `65SC02` | The 65SC02: the WDC set without `WAI`, `STP` and the bit instructions. |
| `Z80` | The Z80, documented and undocumented instructions alike. |
| `M6809` | The Motorola MC6809, with page-`$10` and page-`$11` instructions, indexed postbytes, register pairs and stack register lists. |

An instruction is a mnemonic and its operand. Where one instruction has several encodings, such as the Z80's
duplicate `NEG`s, the documented one is used.

```asm
.cpu Wdc65C02
        stz $10
        bbr0 $10, Next
Next:   bra Next
.cpu Z80
        ld a,1
```

## 6502 operands

| Operand | Addressing |
| --- | --- |
| (none) or `A` | Implied, or the accumulator: `asl` and `asl a` are the same. |
| `#e` | Immediate. |
| `e` | Zero page or absolute, or a branch target. |
| `e,x` / `e,y` | Indexed. |
| `(e,x)` | Indexed indirect (and the 65C02's `jmp (a,x)`). |
| `(e),y` | Indirect indexed. |
| `(e)` | Indirect (`jmp`, and the 65C02's zero-page indirect). The whole operand must be one parenthesized group: `(1)+(2)` is an absolute address. |
| `zp, target` | The 65C02's `BBRn` and `BBSn`. |

**Zero page or absolute.** An address that is known and below $100 assembles as zero page; one not yet known
assembles as absolute until it is. `$0010` is still zero page, since only the value decides. To choose:

- `a:e`, `!e` or a `.w` mnemonic suffix forces absolute;
- `z:e` forces zero page.

```asm
        lda #<Message
        lda $10           ; zero page
        lda a:$10         ; absolute
        lda.w $10         ; absolute
        lda !$10          ; absolute
        ldx z:$10,y       ; zero page, Y
        lda ($20),y
        jmp ($FFFC)
Message: .byte 0
```

A branch target must be within -128 to +127 bytes.

## Z80 operands

Mnemonics, registers and operand order are Zilog's. Memory and port operands are written in **brackets**, and
parentheses always group an expression:

| Operand | Means |
| --- | --- |
| `A` `B` `C` `D` `E` `H` `L` `I` `R`, `AF` `BC` `DE` `HL` `SP` `IX` `IY`, `AF'` | Registers. The undocumented halves `IXH`, `IXL`, `IYH`, `IYL` work too. |
| `[HL]` `[BC]` `[DE]` `[SP]` | Memory at a register. |
| `[IX+d]` `[IX-d]` `[IX]` | Memory at IX or IY plus a signed 8-bit displacement, which may be any expression; `[IX]` is `[IX+0]`. |
| `[nn]` | Memory at an address. |
| `[n]` and `[C]` | I/O ports, in `IN` and `OUT`. |
| `NZ` `Z` `NC` `C` `PO` `PE` `P` `M` | Conditions; `JR` takes only the first four. |
| `n`, `nn` | Immediate values: `LD A,(2+3)*2` loads 10. |

`RST` takes the restart address ($00, $08, ... $38), and `IM` takes 0, 1 or 2. `BIT`, `SET` and `RES` take a bit
number 0-7, which may be an expression. `JR` and `DJNZ` targets must be within -128 to +127 bytes.

```asm
.cpu Z80
Offset = 5
Start:  ld a,[hl]
        ld [ix+Offset],a
        ld b,[iy-1]
        ld hl,[Data]
        ld [Data],hl
        ld a,(2+3)*2
        in a,[$FF]
        out [c],a
        ex af,af'
        bit 7,[hl]
        set 0,[ix+2]
        jr nz,Start
        djnz Start
        jp [hl]
        call nz,Start
        rst $38
        im 1
        ld ixh,5
Data:   .word 0
```

### From Zilog syntax

| Zilog | Native |
| --- | --- |
| `LD A,(HL)`, `LD A,(1234H)`, `OUT (C),A` | `LD A,[HL]`, `LD A,[$1234]`, `OUT [C],A` |
| `JP (HL)` | `JP [HL]` |
| `1234H`, `1010B` | `$1234`, `%1010` |
| `$` (current address) | `*` |
| `LABEL EQU 5` | `LABEL = 5` |
| `DEFB`, `DEFW`, `DEFS`, `DEFM` | `.byte`, `.word`, `.res`, `.byte "text"` |
| `ORG` | `.org` |
| Labels without colons | Labels with colons |

A Zilog `(HL)` in native source is an expression in parentheses, so it reports "Unresolved expression '(HL)'".
`[HL+5]` is memory at the address `HL+5`, which needs a symbol named `HL`; only IX and IY take displacements.

## 6809 operands

Mnemonics, registers and width prefixes (`<` and `>`) follow Motorola; indirection uses **brackets** (`[...]`) so
parentheses always group an expression:

| Operand | Addressing |
| --- | --- |
| (none) | Inherent (`NOP`, `ASLA`/`LSLA`, `RTS`, `RTI`, `MUL`, `DAA`, `SEX`, `ABX`, `SYNC`, `SWI`/`SWI2`/`SWI3`). |
| `#e` | 8-bit or 16-bit immediate (`LDA #$A5`, `LDD #$1234`). |
| `e`, `<e`, `>e` | Direct page (`$00`–`$FF` when unforced, or forced with `<`) or extended (`>`), or a relative branch target. |
| `,R`, `e,R`, `<e,R`, `<<e,R`, `>e,R` | Indexed by `X`, `Y`, `U` or `S`: no offset, or 5-bit (`<<`), 8-bit (`<`) or 16-bit (`>`). |
| `A,R` `B,R` `D,R` | Accumulator-offset indexed. |
| `,R+` `,R++` `,-R` `,--R` | Auto-increment and auto-decrement indexed. |
| `target,PCR` / `>target,PCR` | PC-relative indexed (8-bit or 16-bit displacement). |
| `[,R]` `[e,R]` `[A,R]` `[,R++]` `[target,PCR]` `[nn]` | Indirect indexed and extended indirect (`[nn]`); `,R+` and `,-R` have no indirect form. |
| `R1,R2` | `TFR` and `EXG` register pairs (`D`, `X`, `Y`, `U`, `S`, `PC` or `A`, `B`, `CC`, `DP`). |
| `CC,A,B,DP,X,Y,U,PC` (or `#mask`) | `PSHS`/`PULS` (`U` allowed) and `PSHU`/`PULU` (`S` allowed); `D` stands for `A,B`. |

`LSL`, `LSLA`, `LSLB`, `BHS`, `BLO`, `LBHS` and `LBLO` are accepted as synonyms for `ASL` and `BCC`/`BCS`.

```asm
.cpu M6809
        .org $1000
Entry:  lds #$2000
        lda <$10
        lda >$0010
        lda [,x]
        lda 5,x
        lda ,x++
        leax -2,u
        leay Table,pcr
        pshs d,x,y,pc
        tfr d,u
        lbne Done
Done:   puls d,x,y,pc
Table:  .dbyt $1234
```

## Macros

```asm
.macro Store value, address
        lda #value
        sta address
.endmacro

        Store 1, $0200
        Store <(Table+1), $0201
Table:  .byte 0
```

`.macro Name p1, p2` begins a macro, and `.endmacro` ends it. A macro must be defined before it is used.

- **Calls.** A macro is called by writing its name where an instruction goes. Its name matches exactly,
  including case, and a macro takes the place of an instruction with the same spelling. A label on the call
  line names the address of the expansion.
- **Arguments** are separated by commas outside parentheses and strings. Missing arguments are empty, and
  parentheses written in a call stay part of its argument. A parameter is replaced wherever its whole name
  appears in the body, outside strings and comments, including as one part of a `::` name.
- **`.paramcount`** is the number of arguments given.
- **`.local` names, ...** gives each invocation its own copy of those labels.
- **`.exitmacro`** ends the expansion early.
- **Recursion** is allowed, up to the depth limit.

```asm
.macro Delay count
        .local again
        ldx #count
again:  dex
        bne again
.endmacro

        Delay 5
        Delay 10
```

## Conditionals

| Directive | Takes the block when |
| --- | --- |
| `.if e` / `.elseif e` / `.else` / `.endif` | `e` is nonzero. |
| `.ifdef Name` / `.ifndef Name` | A symbol or macro of that name was defined earlier (or was not). |
| `.ifblank text` / `.ifnblank text` | The text is empty (or is not), as for a macro argument. |
| `.ifconst e` / `.ifnconst e` | `e` is a constant known at that point (or is not). |
| `.ifp02`, `.ifpsc02`, `.ifpc02`, `.ifpwc02` | The CPU is `Mos6502`, `65SC02`, `Rockwell65C02` or `Wdc65C02`. |

The CPU tests follow the latest `.cpu` before them, or the host's CPU before the first `.cpu`. On the Z80
none of them is true.

A condition's value must be known at that point in the source: constants and variables count, labels and `*`
do not. Inactive blocks are skipped without being read, and every file closes the conditionals it opens.

```asm
Model = 2
.if Model = 1
        nop
.elseif Model = 2
        brk
.else
        rts
.endif
```

## Repeats

`.repeat count[, counter]` ... `.endrepeat` repeats its block. The count must be known at that point, and the
counter, from 0, is substituted as a number in the block's own lines.

```asm
Squares:
.repeat 8, I
        .byte I * I
.endrepeat
```

## Textual definitions

`.define Name text` replaces the word `Name` with `text` on later lines, outside strings and comments, and
`.undefine Name` removes it. A definition can take parameters. The call does not use parentheses (they would
become part of the argument), and braces group an argument that contains commas.

```asm
.define WIDTH 40
.define AT(row, column) (row) * WIDTH + (column)
Cell = AT 2, 5          ; 85
.undefine WIDTH
```

## Structures and enumerations

`.struct Name` ... `.endstruct` defines field offsets as constants `Name::field`, and `.sizeof(Name)` gives its
size. Fields are `.byte`, `.res n`, `.word`, `.addr`, `.dbyt`, `.faraddr`, `.dword`, or `.tag Type` for a nested
structure, each with an optional count. `.union` overlays its fields at offset 0. `.tag Type[, count]` outside
a structure reserves room for one or more.

`.enum Name` ... `.endenum` defines `Name::MEMBER` constants, counting from 0 or from a member's `= value`.

```asm
.struct Point
        column .word
        row .word
.endstruct

.enum Color
        BLACK
        WHITE
        RED = 4
        GREEN
.endenum

Origin: .tag Point
Size = .sizeof(Point)          ; 4
        .byte Point::row, Color::GREEN   ; 2, 5
```

## Character maps

`.charmap from, to` maps a character code to a byte for every later string and character literal. The Apple
II's text has bit 7 set, so the Apple II sources map every character once:

```asm
.repeat 128, character
.charmap character, character | $80
.endrepeat
        .byte "HI"              ; $C8 $C9
        lda #'A'                ; $C1
```

`.hiascii` sets bit 7 itself and does not go through the map.

## Functions

These are expanded before a line is assembled; their numeric arguments must be known at that point. Names ignore
case.

| Function | Gives |
| --- | --- |
| `.defined(name)`, `.def(name)` | 1 when a symbol was defined earlier. |
| `.definedmacro(name)` | 1 when a macro is defined. |
| `.const(e)` | 1 when `e` is a constant known now. |
| `.sizeof(name)` | The size of a structure, a field, a `.tag`ged label, a `.proc` or `.scope`, or a labeled statement. |
| `.strlen("s")`, `.strat("s", i)` | A string's length, and its character code at an index (through the map). |
| `.concat("a", "b", ...)`, `.string(name)` | Joined strings, and a name's spelling as a string. |
| `.sprintf("format", ...)` | A string formatted with `%d %i %u %x %X %o %c %s %%`, flags, width and precision. |
| `.ident("name")` | The identifier the string spells, so a name can be computed: `.ident(.sprintf("ENTRY_%d", 3)) = 1`. |
| `.min(a, b)`, `.max(a, b)` | The smaller or larger value. |
| `.loword(e)`, `.hiword(e)` | Bits 0-15 and 16-31. |
| `.blank(tokens)`, `.tcount(tokens)` | Whether a token list is empty, and how many tokens it has. |
| `.match(a, b)`, `.xmatch(a, b)` | Whether two token lists have the same kinds of tokens, or the same tokens. |
| `.left(n, tokens)`, `.right(n, tokens)`, `.mid(start, n, tokens)` | Part of a token list. |

```asm
.macro NAMED number, value
.ident(.sprintf("ENTRY_%d", number)) = value
.endmacro
        NAMED 1, $10
        NAMED 2, $20
Length = .strlen("HELLO")       ; 5
First = .strat("HELLO", 0)      ; 'H'
Larger = .max(3, 7)             ; 7
```

`.lobyte`, `.hibyte` and `.bankbyte` are part of [expressions](#operators) rather than functions, so they
also work with values not yet known.

## Includes

`.include "file"` reads another source at that point. A quoted path is looked for beside the including file,
then in the host's include paths. `.include <file>` looks only in the host's SDK paths. A suffix
`dialect=native|ca65|merlin|macro10` names the included file's dialect. Includes nest up to the depth limit and
cannot form a cycle.

`.incbin "file"[, start[, size]]` inserts a file's bytes.

```text
.include "hardware.inc"
.include "routines.s" dialect=ca65
.incbin "font.bin", 0, 1024
```

## Exports, assertions and messages

| Directive | Does |
| --- | --- |
| `.export Name, ...` | Publishes symbols to the host, such as a ROM's entry points to generated C#; an export that never gets defined is an error. |
| `.global Name, ...` | Like `.export`, but an undefined name is ignored. |
| `.assert e[, "message"]` | Fails when `e` is zero once every address is known. |
| `.error "message"`, `.fatal "message"` | Fails with the message. |
| `.out`, `.warning` | Accepted and ignored. |

```asm
Size = End - Start
Start:  .res 16
End:
        .assert Size = 16, "The buffer is 16 bytes."
        .assert * = $10
        .export Start
```

## Documentation comments

`;;` comments document routines, tables, constants, macros and scopes for hover, completion and the debugger,
in a compact form:

```asm
;; Prints the character in A.
;; In: A = the character
;; Keeps: X, Y
COUT:   rts
```

[Documentation comments](DocComments.md) specifies the format: topics, sections such as `In:`, `Out:`,
`Uses:` and `Keeps:`, links, and inheritance.

## Hosting the assembler

A host runs the assembler through [`AssemblyOptions`](../src/Retrocore.Assembler/Assembler/AssemblyOptions.cs):

- the CPU, origin and image size;
- a `SourceResolver` for includes. `FileAssemblySourceResolver` reads files (and binary files for `.incbin`),
  and the assembler never reads a file on its own;
- `IncludePaths` and `SdkPaths`;
- `PredefinedSymbols`;
- the dialect;
- an ld65-style `LinkerConfiguration`;
- the limits below.

`WidthPolicy` chooses whether zero-page addressing may shrink instructions in later layout passes (`Shrink`, the
default) or keeps each instruction's first-pass width (`SourceOrder`). Several root sources can share one
preprocessing environment through the overloads that take a list of sources.

A source map ties each statement to its source line: its logical address, its offset in its section, and its
section. A macro or include line keeps the chain of lines it was expanded from. Diagnostics give the innermost
line and list the chain.

The source generator assembles `.rom` sources at build time. It resolves includes only from the project's
`AdditionalFiles`, with `RetrocoreIncludePaths` and `RetrocoreSdkPaths` naming the search directories and
`RetrocoreDialect` an included file's dialect. Its resolver reads text only, so `.incbin` is unavailable
there:

```xml
<AdditionalFiles Include="sdk\api.inc" RetrocoreDialect="native" />
```

Model projects ([`AssemblyProject`](../src/Retrocore.Assembler/Assembler/AssemblyProject.cs)) can also declare
sections that a source cannot. These are sections placed automatically, aligned, run at another address, or
holding no output (BSS).

The disassembler writes native syntax, and its export reassembles to the same bytes. Undocumented aliases that
the assembler would encode differently export as `.byte`.

## Limits

| Limit | Default |
| --- | --- |
| Include depth | 32 |
| Macro and function nesting | 64 |
| Repeat count | 1,000,000 |
| Lines after expansion | 1,000,000 |
| Layout passes | 32 |

## Directive index

| Directive | Section |
| --- | --- |
| `.align` | [Layout](#layout-and-sections) |
| `.asciiz` | [Data](#data) |
| `.assert` | [Exports, assertions](#exports-assertions-and-messages) |
| `.byte`, `.byt` | [Data](#data) |
| `.charmap` | [Character maps](#character-maps) |
| `.checksum` | [Layout](#layout-and-sections) |
| `.cpu` | [CPUs](#cpus-and-instructions) |
| `.dbyt` | [Data](#data) |
| `.define`, `.undefine` | [Textual definitions](#textual-definitions) |
| `.dum`, `.dend` | [Layout](#layout-and-sections) |
| `.dword` | [Data](#data) |
| `.enum`, `.endenum` | [Structures](#structures-and-enumerations) |
| `.equ` | [Symbols](#constants-variables-and-labels) |
| `.error`, `.fatal`, `.out`, `.warning` | [Messages](#exports-assertions-and-messages) |
| `.exitmacro` | [Macros](#macros) |
| `.export`, `.global` | [Exports](#exports-assertions-and-messages) |
| `.faraddr` | [Data](#data) |
| `.hiascii` | [Data](#data) |
| `.hibytes`, `.lobytes` | [Data](#data) |
| `.if`, `.elseif`, `.else`, `.endif` | [Conditionals](#conditionals) |
| `.ifblank`, `.ifnblank` | [Conditionals](#conditionals) |
| `.ifconst`, `.ifnconst` | [Conditionals](#conditionals) |
| `.ifp02`, `.ifpsc02`, `.ifpc02`, `.ifpwc02` | [Conditionals](#conditionals) |
| `.ifdef`, `.ifndef` | [Conditionals](#conditionals) |
| `.include`, `.incbin` | [Includes](#includes) |
| `.local` | [Macros](#macros) |
| `.logicalorg` | [Layout](#layout-and-sections) |
| `.macro`, `.endmacro` | [Macros](#macros) |
| `.org` | [Layout](#layout-and-sections) |
| `.proc`, `.endproc` | [Scopes](#scopes) |
| `.repeat`, `.endrepeat` | [Repeats](#repeats) |
| `.res` | [Data](#data) |
| `.scope`, `.endscope` | [Scopes](#scopes) |
| `.section` | [Layout](#layout-and-sections) |
| `.set` | [Symbols](#constants-variables-and-labels) |
| `.struct`, `.endstruct`, `.union`, `.endunion`, `.tag` | [Structures](#structures-and-enumerations) |
| `.word` | [Data](#data) |

ca65's `.debuginfo`, `.list`, `.smart` and `.feature ubiquitous_idents` are accepted and ignored, so shared
sources assemble.
