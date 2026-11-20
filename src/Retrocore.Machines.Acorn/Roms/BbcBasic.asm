;; BBC BASIC II ($8000-$BFFF)
;;
;; BBC BASIC, version 2: the Model B's language ROM from 1982, 16K at &8000-&BFFF in a paged ROM socket. It is an
;; interpreter that keeps a program as tokens, with integer, real and string variables, procedures and functions,
;; and a 6502 assembler built in. The MOS enters it at &8000 as the current language; from then on it reads lines,
;; tokenises them, stores numbered lines in the program and runs the others at once. The ROM is in parts, each in its
;; own file in Basic, in the order they sit in the ROM:
;;
;; - Keywords.asm ($8000-$8450): the paged ROM header, the language entry and start-up, the keyword table and the
;;   table of the routines each token runs.
;; - Assembler.asm ($8451-$8820): the assembler's mnemonic and opcode tables and the assembler.
;; - Interpreter.asm ($8821-$8BE3): the tokeniser, reading the text, the start-up and immediate mode, and the loop
;;   that runs statements.
;; - Statements.asm ($8BE4-$8F30): LET and assignment, PRINT, CLG, CLS and CALL.
;; - Commands.asm ($8F31-$945A): DELETE, RENUMBER, AUTO, DIM, the pseudo-variables, PROC, LOCAL, ENDPROC and the
;;   graphics and sound statements.
;; - Variables.asm ($945B-$97DC): the variable lists, finding and making variables, FNs and PROCs.
;; - Lines.asm ($97DD-$9B1C): line numbers, the end of a statement, IF, printing line numbers, finding lines and
;;   integer division.
;; - Expressions.asm ($9B1D-$A07A): the expression evaluator, the operators and converting numbers to strings.
;; - FloatingPoint.asm ($A07B-$A6A4): the floating point accumulators and arithmetic.
;; - Maths.asm ($A6A5-$AB32): the mathematical functions and their constants.
;; - Functions.asm ($AB33-$B111): the other functions and the string functions.
;; - Procedures.asm ($B112-$B4B3): calling FNs and PROCs, their parameters, errors and the BRK handler, SOUND,
;;   ENVELOPE and WIDTH.
;; - List.asm ($B4B4-$B694): assigning numbers, printing characters and tokens, LISTO and LIST.
;; - Loops.asm ($B695-$BBE3): NEXT, FOR, GOSUB, RETURN, GOTO, ON, INPUT, RESTORE, READ and UNTIL.
;; - System.asm ($BBE4-$BFFF): REPEAT, reading lines, editing the program, RUN, BASIC's stack, loading and saving,
;;   the file statements and REPORT.
;;
;; Acorn published no names for BASIC's routines or workspace. The keywords name the routines that run them, and the
;; others are named after what they do, in the terms of the BASIC ROM User Guide (BasicEquates.asm).
;;
;; Maintained by hand. BbcBasicSourceTests check that it assembles byte-identically to BASIC II.

.cpu Mos6502

.include "MosEquates.asm"
.include "MosEntries.asm"
.include "BasicEquates.asm"

.org $8000

.include "Basic/Keywords.asm"
.include "Basic/Assembler.asm"
.include "Basic/Interpreter.asm"
.include "Basic/Statements.asm"
.include "Basic/Commands.asm"
.include "Basic/Variables.asm"
.include "Basic/Lines.asm"
.include "Basic/Expressions.asm"
.include "Basic/FloatingPoint.asm"
.include "Basic/Maths.asm"
.include "Basic/Functions.asm"
.include "Basic/Procedures.asm"
.include "Basic/List.asm"
.include "Basic/Loops.asm"
.include "Basic/System.asm"
