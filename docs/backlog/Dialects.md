# Backlog: more assembler dialects

Status: **not started**. The assembler reads native, ca65, Merlin and MACRO-10 sources. Each front end turns
its dialect into the same statements, and the compiler, source maps and debugger then treat every dialect
alike. Adding a dialect means adding a front end. Neither the instruction-set descriptions nor the debugger
change.

## Z80 dialects

The native dialect writes Z80 memory operands in brackets (`LD A,[HL]`), so parentheses always group
expressions. The traditional Z80 assemblers use Zilog's parentheses, so their front ends must tell an operand
`(nn)` from an expression in parentheses by the instruction's forms.

| Dialect | Why | Notes |
| --- | --- | --- |
| **Zilog** (the manual's syntax) | The reference every other Z80 dialect starts from. | `LD A,(IX+5)`, `JP (HL)`, `EX AF,AF'`, `DEFB`/`DEFW`/`DEFS`/`DEFM`, `EQU`, `ORG`. In `LD A,(5)+1` the operand is memory only when the whole operand is one parenthesized expression; that is the one ambiguity, and it follows Zilog's reading. |
| **EDTASM** | Radio Shack's Editor/Assembler, the Model I's own; period listings and magazine programs use it. | Zilog mnemonics, line numbers, `DEFM 'text'`, `END start`, six-character labels. Reading line-numbered sources lets programs typed from listings assemble unchanged. |
| **zmac** | The cross assembler most TRS-80 sources on the net use today. | Zilog syntax plus macros (`MACRO`/`ENDM`), `IF`/`ELSE`/`ENDIF`, local labels, `.z80`, `.8080`, and its own pseudo-ops for TRS-80 file output (`/CMD`, CAS). Its test sources make a corpus to compare with, as ca65's and Merlin's do. |

Each front end gets a reference comparison like the ca65 and Merlin ones: an external assembler (zmac's
binary, or an EDTASM disk under emulation) builds a corpus, and the front end must match it byte for byte.
EDTASM can run on our own Model I, which makes the oracle part of the emulator.

Output formats come with them: `/CMD` load modules and SYSTEM-format CAS tapes. The debugger loads both, as it
loads cc65 `.dbg` files today, so an EDTASM or zmac program debugs from its listing.

## 6809 dialects

With the 6809 ([backlog](M6809-CoCo.md)) the native dialect gains its operand forms. The assemblers its sources
come in are:

| Dialect | Why |
| --- | --- |
| **Motorola** syntax, as in the MC6809 programming manual | The reference. `LDA ,X+`, `LEAX 5,Y`, `[,X]` for indirection, `FCB`/`FDB`/`FCC`/`RMB`. |
| **EDTASM+** | Radio Shack's Color Computer cartridge assembler, the CoCo's EDTASM. |
| **lwasm** (LWTOOLS) | The cross assembler current CoCo sources use, with macros, sections and OS-9 modules. |

The 6809 already uses brackets for indirection, which the native dialect's convention matches.

## 8080 and 8085 dialects

The native dialect already uses Intel's mnemonics and operands ([backlog](I8080.md)), so these front ends
change only the directives, numbers and labels around them:

| Dialect | Why |
| --- | --- |
| **Intel** (ASM80, and CP/M's ASM and MAC) | The reference, and the syntax period 8080 and CP/M sources are in: `1234H`, `17Q`, `$` for the current address, `EQU`/`SET`, `DB`/`DW`/`DS`, `ORG`, `END`, labels without colons; MAC adds macros. |
| **zmac** in `.8080` mode | The same cross assembler as the Z80's, already planned above. |

## What the native dialect keeps

The native dialect stays the one dialect that reads alike on every CPU. On the 6809 it keeps Motorola's operand
forms, whose brackets already mean indirection. `.byte` and `.word` define data, and the ca65 preprocessing and
scopes apply unchanged. The SDK's sources are written in it, and a source in another dialect can be exported as
native through the disassembler's exporter.
