; Apple Business BASIC: the SOS.INTERP file of Apple's Business BASIC 1.23 disk.
;
; The file starts with SOS's interpreter header, loads at B3PRT1 and starts at INIT. Its files follow Apple's
; Business BASIC 1.3 source, with Apple's names; VERSION picks the release:
;
; - 123 (the default) builds 1.23 byte for byte. It lacks 1.3's program selector support: the SELECTOR, PROGPATH
;   and SOSPATH buffers, the prefix routines, PROGPREFIX$ and the calls to them. Storage the source reserves holds
;   whatever was in memory when Apple built the file, and the file runs 21 bytes past the length its header gives.
; - 130 builds the 1.3 listing as printed. No 1.3 binary is known, so this build is unchecked.
;
; DEBUG and RUNTIME build Apple's debugger and run-time variants of the listing; neither was checked either.

    .cpu Mos6502

.ifndef VERSION
VERSION = 123
.endif
.ifndef DEBUG
DEBUG = 0
.endif
.ifndef RUNTIME
RUNTIME = 0
.endif

.macro DCI text
    .repeat .strlen(text) - 1, index
    .byte .strat(text, index)
    .endrepeat
    .byte .strat(text, .strlen(text) - 1) | $80
.endmacro

    .include "B3Invok.asm"                  ; SOS call numbers and errors, file types, file control blocks
    .include "ZpgEqus.asm"                  ; Zero page, X-bytes, page $1E, the header, buffers, dispatch tables
    .include "B3Resvb.asm"                  ; Keywords and tokens, operators, error messages
    .include "Initial.asm"                  ; The cold start, INIT, and the memory moves
    .include "B3MainC.asm"                  ; Errors, the prompt, CRUNCH, finding lines, NEW and CLEAR
    .include "Extras.asm"                   ; Business BASIC's added statements, ON ERR, ON KBD, ON EOF#
    .include "SosStuf.asm"                  ; SOS call parameter lists, the console, keys, CONTROL-C
    .include "B3ListD.asm"                  ; LIST, FOR, the statement loop NEWSTT, RUN, CONT
    .include "B3GotoE.asm"                  ; GOTO, GOSUB, RETURN, ON, LET, PRINT and its output
    .include "B3InpuF.asm"                  ; INPUT, GET, READ, NEXT, the formula evaluator's first half
    .include "B3EvalG.asm"                  ; The formula evaluator's second half, EVAL
    .include "StrUtils.asm"                 ; String space and the garbage collector
    .include "B3MathK.asm"                  ; Floating-point addition, subtraction, normalizing
    .include "B3MathL.asm"                  ; LOG, multiplication, division, moves, comparison
    .include "B3FinpM.asm"                  ; INT, FIN to read a number, FOUT to print one
    .include "B3Expon.asm"                  ; EXP, RND, COS, SIN, TAN, ATN
    .include "B3FreeR.asm"                  ; Freeing strings, pointer arithmetic, IF, WINDOW
    .include "LongInt.asm"                  ; Long integers and the CONV functions
    .include "B3DmpyT.asm"                  ; TEN, HEX$ and SWAP
    .include "B3DimnH.asm"                  ; DIM and the variable search, PTRGET
    .include "B3UdefI.asm"                  ; Arrays' elements, FRE, POS, VPOS, DEF and FN
    .include "StrngStuf.asm"                ; String functions, PREFIX$, TIME$, DATE$
    .include "Invoke.asm"                   ; Loading invokable modules, PERFORM, EXFN
    .include "Invoke1.asm"                  ; The INVOKE statement, SCRUNCH and EXPAND
    .include "B3Pru1.asm"                   ; PRINT USING, first part
    .include "B3Pru2.asm"                   ; PRINT USING, second part
    .include "DiskStuf1.asm"                ; Console line input, TYP, REC, CLOSE, PDL, BUTTON
    .include "DiskStuf2.asm"                ; OPEN and the open the file commands share
    .include "DisCmds.asm"                  ; READ#, WRITE#, CHAIN, OUTPUT#, EXEC
    .include "FileStuf.asm"                 ; CREATE, SAVE, LOAD, RENAME, LOCK, UNLOCK, DELETE
    .include "Catalog.asm"                  ; CATALOG, and the table of routines for modules
    .include "BasicEnd.asm"                 ; Calls between BASIC and modules, and the end
