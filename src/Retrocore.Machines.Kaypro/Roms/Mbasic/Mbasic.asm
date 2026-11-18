;; MBASIC 5.21 FOR CP/M ($0100-$5FFF)
;;
;; Microsoft's BASIC-80 interpreter, Rev. 5.21 (28 July 1981), as MBASIC.COM: a CP/M program that loads at $0100,
;; calls CP/M's BDOS for its files, and patches the BIOS's own console and printer entries into its calls as it
;; starts. This file assembles all of it from the modules below, in the order of their addresses.
;;
;; It follows Microsoft's design, which GW-BASIC's MIT-licensed source (https://github.com/microsoft/GW-BASIC)
;; keeps nearly routine for routine, and much of its code is the Z80 code of the TRS-80's Level II BASIC
;; (Level2.asm), Microsoft's BASIC of the same family:
;;
;; - A typed line is crunched into tokens, with its numbers in binary (CRUNCH). With a line number, it goes into
;;   the program, which starts at TXTTAB, its lines linked in order; without one, it runs at once.
;; - NEWSTT runs a statement at a time, GONE dispatching each through STMDSP and the evaluator (FRMEVL) the
;;   functions through FUNDSP. CHRGTR reads the text, skipping spaces.
;; - Numbers are integers, or single or double precision in Microsoft's binary format, in the floating
;;   accumulator (FAC) with their type in VALTYP. Simple variables follow the program at VARTAB, arrays at
;;   ARYTAB, and strings grow down from MEMSIZ to FRETOP.
;; - An error loads its code into E and jumps to ERROR, which prints its message from ERRTAB, or goes to the
;;   ON ERROR GOTO line.
;;
;; The modules:
;;
;; - Tables.asm ($0103-$0773): the USR conversions, STMDSP and FUNDSP, the reserved words, the operators'
;;   precedences and dispatch, and the error messages.
;; - Storage.asm ($0774-$0C4F): the interpreter's variables, part of the program's image, and its messages.
;; - Interpreter.asm ($0C50-$11BE): FNDFOR, errors, READY, MAIN, line links and search, and CRUNCH.
;; - Statements.asm ($11BF-$1693): FOR, NEWSTT, GONE and CHRGTR, then the control statements to IF.
;; - PrintInput.asm ($1694-$19F6): PRINT, LINE INPUT, INPUT and READ.
;; - Evaluator.asm ($19F7-$2083): the formula evaluator, the operators, user functions, INP, OUT, WAIT and WIDTH.
;; - List.asm ($2084-$2486): LIST, DELETE, PEEK and POKE, RENUM and OPTION BASE.
;; - Math1.asm, Math2.asm and Math3.asm ($2487-$397C): the math package, from addition to number input and
;;   output and the transcendental functions.
;; - Variables.asm ($397D-$3CD4): DIM and the variable and array search, PTRGET.
;; - Console.asm ($3CD5-$4309): EDIT, PRINT USING, console and printer output, and the memory checks.
;; - Misc.asm ($430A-$465B): NEW, CLEAR, RESTORE, STOP, END, CONT, SWAP, ERASE, NEXT and the helpers they share.
;; - Strings.asm ($465C-$4B0C): the string package.
;; - LineInput.asm ($4B0D-$4C57): the line editor that reads typed lines.
;; - Chain.asm ($4C58-$5160): WHILE, WEND, CALL, CHAIN, COMMON and WRITE, and the file-number routines.
;; - Disk1.asm and Disk2.asm ($5161-$5D6E): the file statements and functions, and the CP/M file layer under them.
;; - Init.asm ($5D6F-$5FFF): the start-up, which the file buffers and program overwrite once it has run.
;;
;; Equates.asm holds the CP/M names the modules share. Labels are Microsoft's names where GW-BASIC's source or
;; Level2.asm give them, and descriptive names in Microsoft's style elsewhere; statement and function handlers are
;; named for their keyword (ST_FOR, FN_LEFT), as in Level2.asm. The debugger looks up NEWSTT, GONE, READY, ERROR,
;; ST_RUN, ST_CONT, ST_STOP, ST_END and ENDCON, for MBASIC's BASIC thread.
;;
;; Maintained by hand. KayproTests check that it assembles to a program compatible byte for byte with MBASIC.COM.

.cpu Z80

.include "Equates.asm"

;; A reserved word in ALPTAB: its letters after the first, the last with bit 7 set, then its token. A token below
;; $80 is a function's, which CRUNCH stores after $FF.
.macro RESWORD rest, token
    .repeat .strlen(rest) - 1, index
    .byte .strat(rest, index)
    .endrepeat
    .byte .strat(rest, .strlen(rest) - 1) | $80, token
.endmacro

.org $0100
    JP INIT

; The modules, in the order of their addresses.
.include "Tables.asm"
.include "Storage.asm"
.include "Interpreter.asm"
.include "Statements.asm"
.include "PrintInput.asm"
.include "Evaluator.asm"
.include "List.asm"
.include "Math1.asm"
.include "Math2.asm"
.include "Math3.asm"
.include "Variables.asm"
.include "Console.asm"
.include "Misc.asm"
.include "Strings.asm"
.include "LineInput.asm"
.include "Chain.asm"
.include "Disk1.asm"
.include "Disk2.asm"
.include "Init.asm"

.assert * = $6000, "MBASIC.COM is $5F00 bytes, from $0100."
