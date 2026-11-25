; retrocore: style=strict
;; Apple II Integer BASIC ($E000-$F7FF)
;;
;; Steve Wozniak's BASIC, in the Apple II's ROM from 1977, and in the language card or a firmware card of the
;; machines that followed. It works only with 16-bit integers, -32767 to 32767, and keeps a program as tokens: a line
;; is checked against the syntax table as it is typed and stored only if it is correct. This file assembles the 6 KB
;; at $E000-$F7FF from the modules below, in address order; it matches Apple's three ROM chips 341-0001 ($E000),
;; 341-0002 ($E800) and 341-0003 ($F000) byte for byte.
;;
;; The chips hold more than BASIC. Integer BASIC fills $E000 to $F424; after it come Steve Wozniak and Roy Rankin's
;; floating-point routines ($F425, FloatingPoint.asm), the Mini-Assembler ($F500, entered at $F666;
;; MiniAssembler.asm) and SWEET16, a 16-bit interpreter ($F689, Sweet16.asm). BASIC uses none of them.
;;
;; Memory. The program lives at the top of memory and grows down: its lines lie from <ProgramStart> up to
;; <HighMemory>, in order of their numbers, and entering a line moves the lines below it down. The variables live at
;; the bottom and grow up, from <LowMemory> to <VariablesEnd>. When the two would meet, the error is MEM FULL. The
;; cold start puts <LowMemory> at $0800 and <HighMemory> at the top of RAM. Page zero from $4A up is BASIC's, and
;; `GOSUB` and `FOR` keep their stacks in page 1 below the 6502's stack (Equates.asm).
;;
;; Tokens. Each line is stored as a length byte (counting itself), the line number (low byte first), tokens, and
;; <TOKEN_END_OF_LINE> (<ProgramLine>). A token is a byte below $80 that stands for a keyword or an operator. Bytes
;; with bit 7 set are the rest of the line's text:
;;
;; - A numeric constant is its first digit, with bit 7 set ($B0-$B9), then its value, low byte first; the lister
;;   prints the value, so leading zeros are lost.
;; - A variable's name is its characters with bit 7 set; a string variable's name is followed by <TOKEN_DOLLAR>.
;; - A string constant is <TOKEN_OPEN_QUOTE>, its characters with bit 7 set, and the close-quote token $29.
;; - The text of a remark follows <TOKEN_REM> to the end of the line.
;;
;; The tokenizer (Tokenizer.asm) gives a word the token of the place in the syntax table where it matched, so the
;; same text can have several tokens: `PRINT` is $61 before a string, $62 before a number and $63 alone, and there
;; are a dozen commas. Each token has its own routine (VerbTables.asm), so the interpreter never has to work out
;; which meaning is meant. The C# class Retrocore.Basic.IntegerBasic lists a program from its tokens the way `LIST`
;; does.
;;
;; How a statement runs: the interpreter (Interpreter.asm) reads the tokens left to right, pushing each operand on
;; the noun stack and holding each token until the tokens after it with a higher priority have run; then it runs
;; the token's routine through the verb tables, and the routine takes its operands off the noun stack. The token
;; routines are in the scopes <Statements>, <Functions> and <Operators>, named for their keywords and parts.
;;
;; Names. The routines and locations have names that say what they are; the names they had in earlier listings are
;; their historical names (`Also:`). Paul R. Santa-Maria's annotated listing named Integer BASIC's own (IBSM, as Andy
;; McFadden's port of it gives them), and Apple's listings in the 1978 Apple II Reference Manual named the floating
;; point, the Mini-Assembler and SWEET16 (A2RM78). The names this source used before its conversion that neither
;; gives are kept as UNKN. The routines and locations of the Monitor's that Integer BASIC uses have the Monitor's
;; names (Equates.asm and ../System/MonitorEntries.asm). docs/conversions/IntegerBasic.md records the decisions.
;;
;; One predefined symbol chooses the build. `FORFIX` 0, the default, builds the ROMs. `FORFIX` 1 builds the Integer
;; BASIC in INTBASIC on the 1983 DOS 3.3 System Master (680-0210-A), which fixes `FOR`'s removal of an older loop
;; for the same variable (<DropOlderForLoop>): two bytes differ.
;;
;; Maintained by hand; it assembles byte-identically to the three ROMs at origin $E000 (the digest tests in
;; Apple2SourceTests check both builds).

.cpu Mos6502

.ifndef FORFIX
FORFIX = 0
.endif

; Only the two builds the digest tests check (Apple2SourceTests).
.assert FORFIX = 0 || FORFIX = 1, "FORFIX is 0 for the ROMs or 1 for the 1983 System Master's INTBASIC."

; Apple II text has bit 7 set, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

.include "Equates.asm"
.include "../System/MonitorEntries.asm"


.org $E000

; Integer BASIC.
.include "Lister.asm"
.include "Strings.asm"
.include "LineEditor.asm"
.include "Tokenizer.asm"
.include "Program.asm"
.include "Interpreter.asm"
.include "Arithmetic.asm"
.include "ControlFlow.asm"
.include "VerbTables.asm"
.include "Messages.asm"
.include "SyntaxTable.asm"
.include "Statements.asm"
.include "Memory.asm"
.include "Operators.asm"

; The routines that share the chips.
.include "FloatingPoint.asm"
.include "MiniAssembler.asm"
.include "Sweet16.asm"

.assert * = $F800, "The modules fill $E000-$F7FF exactly."
