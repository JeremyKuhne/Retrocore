;; APPLE-1 BASIC ($E000-$EFFF)
;;
;; Steve Wozniak's BASIC for the Apple-1 (1976), sold on cassette and loaded into the 4K of RAM at $E000-$EFFF:
;; E000.EFFFR at the cassette interface's prompt loads it, E000R in the Monitor starts it with an empty program,
;; and E2B3R starts it again keeping the program. It works only with 16-bit integers, -32767 to 32767, and keeps a
;; program as tokens: a line is checked against the syntax table as it is typed and stored only if it is correct.
;; It is the first form of the Apple II's Integer BASIC, which kept its layout and code; Integer BASIC added
;; graphics, more statements and longer names, and moved what no longer fit to $F000 and above.
;;
;; Memory. The program lives at the top of memory and grows down: its lines lie from PP up to HIMEM, in order of
;; their numbers, and entering a line moves the lines below it down. The variables live at the bottom and grow up,
;; from LOMEM to PV. When the two would meet, the error is MEM FULL. The cold start puts LOMEM at $0800 and HIMEM at
;; $1000, for a 4K machine; HIMEM= and LOMEM= change them. Page zero from $48 up is BASIC's, and GOSUB and FOR keep
;; their stacks in page 1 below the 6502's stack (Equates.asm).
;;
;; Tokens. Each line is stored as a length byte (counting itself), the line number (low byte first), tokens, and
;; $01, the end-of-line token. A token is a byte below $80 that stands for a keyword or an operator. Bytes with bit 7
;; set are the rest of the line's text:
;;
;; - A numeric constant is its first digit, with bit 7 set ($B0-$B9), then its value, low byte first; the lister
;;   prints the value, so leading zeros are lost.
;; - A variable's name is its letter and optional digit with bit 7 set; a string variable's letter is followed by
;;   $40, the $ token.
;; - A string constant is the open-quote token $28, its characters with bit 7 set, and the close-quote token $29.
;; - The text of a remark follows REM ($5D) to the end of the line.
;;
;; The tokenizer (Tokenizer.asm) gives a word the token of the place in the syntax table where it matched, so the
;; same text can have several tokens: PRINT is $61 before a string, $62 before a number and $63 alone, and there
;; are a dozen commas. Each token has its own routine (VerbTables.asm), so the interpreter never has to work out
;; which meaning is meant.
;;
;; How a statement runs: the interpreter (Interpreter.asm) reads the tokens left to right, pushing each operand on
;; the noun stack and holding each token until the tokens after it with a higher priority have run; then it runs
;; the token's routine through the verb tables, and the routine takes its operands off the noun stack.
;;
;; The terminal. BASIC reads the keyboard and writes the display through the PIA itself (RDKEY, COUT), and edits a
;; typed line as the Monitor does: the back arrow (_) takes back a character, ESC cancels the line. A key typed
;; while a program runs stops it.
;;
;; Names follow the Apple II Integer BASIC source's, for the routines the two share (from Paul R. Santa-Maria's
;; annotated listing of Integer BASIC); the routines that are Apple-1 BASIC's own are named for what they do.
;;
;; Several versions of Apple-1 BASIC were passed around. This one writes the display at $D0F2; the copies most
;; replicas use write it at $D012, the same register, and are otherwise the same.
;;
;; Maintained by hand; it assembles byte-identically to that version at origin $E000.

.cpu Mos6502

; The Apple-1's keyboard sets bit 7, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

.include "Equates.asm"

.org $E000

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

.assert * = $F000, "The modules fill $E000-$EFFF exactly."
