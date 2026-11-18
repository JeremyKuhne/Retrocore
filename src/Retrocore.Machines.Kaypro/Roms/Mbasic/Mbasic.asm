;; MBASIC 5.21 FOR CP/M ($0100-$5FFF)
;;
;; Microsoft's BASIC-80 interpreter, Rev. 5.21 (28 July 1981), as MBASIC.COM: a CP/M program that loads at $0100
;; and calls CP/M's BDOS at $0005 for its console, printer and files.
;;
;; It follows Microsoft's design, which GW-BASIC's MIT-licensed source (https://github.com/microsoft/GW-BASIC) keeps
;; nearly line for line. A line is crunched into tokens, with its numbers in binary; NEWSTT runs a statement at a time,
;; GONE dispatching each through STMDSP and functions through FUNDSP; errors load their code into E and jump to ERROR.
;; Numbers are integers, or single or double precision in Microsoft's binary format. The program starts at TXTTAB, its
;; simple variables at VARTAB and its arrays at ARYTAB, and strings grow down from MEMSIZ to FRETOP.
;;
;; Labels are Microsoft's names, as GW-BASIC's source gives them, for the routines and variables identified so far;
;; statement and function handlers are named for their keyword (ST_FOR, FN_LEFT), as in Level2.asm. Labels still
;; named L_ or D_ and their address are routines and variables not yet identified.
;;
;; Maintained by hand. KayproTests check that it assembles to a program compatible byte for byte with MBASIC.COM.

.cpu Z80

; Addresses outside the program that it refers to, not yet identified.
L_0000 = $0000
D_0001 = $0001
L_0005 = $0005
D_0006 = $0006
L_0008 = $0008
D_64CD = $64CD
L_7F1E = $7F1E
L_D1EB = $D1EB
L_E1C1 = $E1C1

;; A reserved word in ALPTAB: its letters after the first, the last with bit 7 set, then its token. A token below
;; $80 is a function's, which CRUNCH stores after $FF.
.macro RESWORD rest, token
    .repeat .strlen(rest) - 1, index
    .byte .strat(rest, index)
    .endrepeat
    .byte .strat(rest, .strlen(rest) - 1) | $80, token
.endmacro

.org $0100
    JP L_5D8C

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
.include "Chain.asm"
.include "Disk1.asm"
.include "Disk2.asm"
.include "Init.asm"

.assert * = $6000, "MBASIC.COM is $5F00 bytes, from $0100."
