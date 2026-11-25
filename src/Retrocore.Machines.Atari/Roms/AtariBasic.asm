;; ATARI BASIC ($A000-$BFFF), REV. A, REV. B AND REV. C
;;
;; The 8K cartridge in the 400's and 800's left slot, written by Shepardson Microsystems for Atari. A line typed at
;; the editor is checked against BASIC's grammar, the syntax tables, as it is tokenized, and stored in the statement
;; table by its number; RUN executes the tokens through the statement and operator execution tables. Numbers are the
;; floating point package's (FloatingPoint.asm), reached through FloatingPointEntries.asm, and every device is CIO's,
;; through OsEntries.asm. The ROM is in parts, each in its own file in AtariBasic, in the order they sit in the ROM
;; (the addresses are rev. C's):
;;
;; - Editor.asm ($A000-$A2E0): the cold and warm starts, NEW, the line editor and the syntax checker.
;; - Syntax.asm ($A2E1-$A879): the syntax tables' routines and the tables: the statement names, the grammar, and the
;;   operator and function names.
;; - Execution.asm ($A87A-$AB8F): the memory mover, the execution loop, finding lines, both execution tables and the
;;   expression evaluator.
;; - Expressions.asm ($AB90-$AF30): the argument stack, the precedence table, the operators, arrays and assignment.
;; - Functions.asm ($AF31-$B205): string comparison and the functions up to ^.
;; - Statements.asm ($B206-$B48E): DIM, COM, POKE, DEG, RAD, RESTORE, READ, INPUT and PRINT.
;; - List.asm ($B48F-$B6F8): PRINT's output, LPRINT, LIST, FOR, GOSUB and GOTO.
;; - Control.asm ($B6F9-$B909): NEXT, RUN, CLR, IF, END, STOP, CONT, TRAP, ON, POP and the run-time stack.
;; - Devices.asm ($B90A-$BCA7): the errors, the graphics and sound statements, ENTER, LOAD, SAVE, the cassette and the
;;   I/O statements.
;; - InputOutput.asm ($BCA8-$BFFF): the CIO helpers, READY, RETURN, line input, SIN, COS, ATN, SQR and the header.
;;
;; VERSION selects the build: VERSION_C (the default) for rev. C, the last; VERSION_B for rev. B, built into the
;; 600XL and 800XL; and VERSION_A for rev. A, the 400's and 800's first cartridge.
;;
;; Rev. B changed rev. A in these ways, among many smaller ones that save bytes:
;; - The grammar allows one unary operator before an operand, so NOT NOT A is an error, and a subscript's "(" must
;;   follow its name without a space; INPUT and READ need a variable.
;; - NOT binds more tightly than the comparisons, so NOT A=B is (NOT A)=B; rev. A's NOT was below them, as the
;;   reference manual says.
;; - Unary minus leaves 0 alone (rev. A made a negative zero, so SGN(-0) was -1).
;; - ^ makes an integer raised to a positive integer power an integer (rev. A's 2^3 is 7.99999991), gives X^0 = 1,
;;   and allows a negative number to the power 0.
;; - LOG and CLOG of 1 are 0, and tiny results are made 0.
;; - PRINT drops a number's tenth digit, and ends its line by the token after its last separator.
;; - The memory mover's removal works when its length is a whole number of pages, and ON ... GOSUB takes its entry
;;   back off the run-time stack when its list runs out; GET points INBUFF at its buffer.
;;
;; Rev. B brought two bugs that rev. C fixed: the memory mover's insertion, when its length is a whole number of pages,
;; copies the page past the data and leaves the lowest page where it was, damaging the program as it grows; and
;; LOAD sets each table 16 bytes further on, so a program grows by 16 bytes each time it is loaded. Rev. C also
;; zeroed seven leftover bytes before the header.
;;
;; Bugs every revision has: AND tests the two numbers' exponent bytes against each other, so 1 AND 0.01 is 0; STR$
;; and CHR$ build their results in one buffer, so STR$(1)=STR$(2) is true; SIN and COS keep too few digits of a large
;; argument's remainder; and SQR returns the guess before its last step.
;;
;; Maintained by hand; each build assembles byte-identically to its cartridge.

.cpu Mos6502

VERSION_A = 1                       ;; rev. A, the 400 and 800's cartridge (1979)
VERSION_B = 2                       ;; rev. B, built into the 600XL and 800XL
VERSION_C = 3                       ;; rev. C (1983), the last

.ifndef VERSION
VERSION = VERSION_C
.endif
.assert VERSION >= VERSION_A && VERSION <= VERSION_C, "VERSION is VERSION_A, VERSION_B or VERSION_C."

.include "OsEquates.asm"
.include "OsEntries.asm"
.include "FloatingPointEntries.asm"
.include "BasicEquates.asm"

.org $A000

.include "AtariBasic/Editor.asm"
.include "AtariBasic/Syntax.asm"
.include "AtariBasic/Execution.asm"
.include "AtariBasic/Expressions.asm"
.include "AtariBasic/Functions.asm"
.include "AtariBasic/Statements.asm"
.include "AtariBasic/List.asm"
.include "AtariBasic/Control.asm"
.include "AtariBasic/Devices.asm"
.include "AtariBasic/InputOutput.asm"
