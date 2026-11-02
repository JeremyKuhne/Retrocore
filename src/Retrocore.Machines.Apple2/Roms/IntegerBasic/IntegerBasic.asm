;; APPLE II INTEGER BASIC ($E000-$F7FF)
;;
;; Steve Wozniak's BASIC, in the Apple II's ROM from 1977, and in the language card or a firmware card of the
;; machines that followed. It works only with 16-bit integers, -32767 to 32767, and keeps a program as tokens:
;; a line is checked against the syntax tables as it is typed and stored only if it is correct. This file
;; assembles the 6 KB at $E000-$F7FF from the modules below, in address order; it matches Apple's three ROM chips
;; 341-0001 ($E000), 341-0002 ($E800) and 341-0003 ($F000) byte for byte.
;;
;; The chips hold more than BASIC. Integer BASIC fills $E000 to $F424; after it come Steve Wozniak and Roy Rankin's
;; floating-point routines ($F425, FloatingPoint.asm), the Mini-Assembler ($F500, entered at $F666;
;; MiniAssembler.asm) and SWEET16, a 16-bit interpreter ($F689, Sweet16.asm). BASIC uses none of them.
;;
;; Memory. The program lives at the top of memory and grows down: its lines lie from PP up to HIMEM, in order of
;; their numbers, and entering a line moves the lines below it down. The variables live at the bottom and grow up,
;; from LOMEM to PV. When the two would meet, the error is MEM FULL. The cold start puts LOMEM at $0800 and HIMEM at
;; the top of RAM. Page zero from $4A up is BASIC's, and GOSUB and FOR keep their stacks in page 1 below the 6502's
;; stack (Equates.asm).
;;
;; Tokens. Each line is stored as a length byte (counting itself), the line number (low byte first), tokens, and
;; $01, the end-of-line token. A token is a byte below $80 that stands for a keyword or an operator. Bytes with bit 7
;; set are the rest of the line's text:
;;
;; - A numeric constant is its first digit, with bit 7 set ($B0-$B9), then its value, low byte first; the lister
;;   prints the value, so leading zeros are lost.
;; - A variable's name is its characters with bit 7 set; a string variable's name is followed by $40, the $ token.
;; - A string constant is the open-quote token $28, its characters with bit 7 set, and the close-quote token $29.
;; - The text of a remark follows REM ($5D) to the end of the line.
;;
;; The tokenizer (Tokenizer.asm) gives a word the token of the place in the syntax tables where it matched, so the
;; same text can have several tokens: PRINT is $61 before a string, $62 before a number and $63 alone, and there
;; are a dozen commas. Each token has its own routine (VerbTables.asm), so the interpreter never has to work out
;; which meaning is meant. The C# class Retrocore.Basic.IntegerBasic lists a program from its tokens the way LIST
;; does.
;;
;; How a statement runs: the interpreter (Interpreter.asm) reads the tokens left to right, pushing each operand on
;; the noun stack and holding each token until the tokens after it with a higher priority have run; then it runs
;; the token's routine through the verb tables, and the routine takes its operands off the noun stack.
;;
;; Names follow Paul R. Santa-Maria's annotated listing of Integer BASIC, and Apple's listings in the Apple II
;; Reference Manual (1978, https://archive.org/details/Apple_II_Redbook) for the floating point, the
;; Mini-Assembler and SWEET16. Labels that are an address after L, or after T for a token's routine, are his names
;; for routines that had none. The routines Integer BASIC calls in the Monitor keep the Monitor's names.
;;
;; One predefined symbol chooses the build. FORFIX 0, the default, builds the ROMs. FORFIX 1 builds the Integer
;; BASIC in INTBASIC on the 1983 DOS 3.3 System Master (680-0210-A), which fixes FOR's removal of an older loop
;; for the same variable (<FORDROPOLD>): two bytes differ.
;;
;; Maintained by hand; it assembles byte-identically to the three ROMs at origin $E000.

.cpu Mos6502

.ifndef FORFIX
FORFIX = 0
.endif

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
