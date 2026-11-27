; retrocore: style=strict
; Apple Business BASIC: the SOS.INTERP file of Apple's Business BASIC 1.23 disk.
;
; The file starts with SOS's interpreter header, loads at LoadAddress and starts at ColdStart. Its files follow
; Apple's Business BASIC 1.3 source, in Apple's order and with Apple's file names. Every name is the SDK's, and the
; name Apple's listing gives each definition is kept in its `Also:` section with the key BB13 (docs/Bibliography.md),
; so a name from the listing still assembles, links and resolves in the debugger. docs/conversions/BusinessBasic.md
; logs the conversion and has the rename table.
;
; VERSION picks the release:
;
; - 123 (the default) builds 1.23 byte for byte. It lacks 1.3's program selector support: the StartedBySelector,
;   ProgramPath and SosPrefix buffers, the prefix routines (ProgramPrefix), `PROGPREFIX$` and the calls to them.
;   Storage the source reserves holds whatever was in memory when Apple built the file, and the file runs 21 bytes past
;   the length its header gives.
; - 130 builds the 1.3 listing as printed. No 1.3 binary is known, so this build is unchecked.
;
; With VERSION = 130, DEBUG = 1 and RUNTIME = 1 build Apple's debugger and run-time variants of the listing (its
; BASIC.D and BASIC.RT); neither was checked either. The digest tests in BusinessBasicSourceTests pin all four builds.

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

; Only the four builds the digest tests check (BusinessBasicSourceTests): 1.23, and 1.3 with its debugger and run-time
; variants.
.assert VERSION = 123 || VERSION = 130, "VERSION is 123 for Business BASIC 1.23 or 130 for the 1.3 listing."
.assert DEBUG = 0 || DEBUG = 1, "DEBUG is 1 for Apple's debugger build or 0."
.assert RUNTIME = 0 || RUNTIME = 1, "RUNTIME is 1 for Apple's run-time build or 0."
.assert DEBUG + RUNTIME <= 1, "DEBUG and RUNTIME are separate builds: set one at most."
.assert DEBUG + RUNTIME = 0 || VERSION = 130, "The debugger and run-time builds are of the 1.3 listing: VERSION = 130."

;; Places text with bit 7 set on its last character, as EDASM's DCI directive does: how BASIC's keyword and message
;; tables mark where each entry ends.
;; Parameters:
;;   text = the text
.macro TextEndingHigh text
    .repeat .strlen(text) - 1, index
        .byte .strat(text, index)
    .endrepeat
    .byte .strat(text, .strlen(text) - 1) | $80
.endmacro

    .include "B3Invok.asm"                  ; SOS call numbers and errors, file types, file control blocks
    .include "ZpgEqus.asm"                  ; Zero page, X-bytes, page $1E, the header, buffers, dispatch tables
    .include "B3Resvb.asm"                  ; Keywords and tokens, operators, error messages
    .include "Initial.asm"                  ; The cold start and the memory moves
    .include "B3MainC.asm"                  ; Errors, the prompt, tokenizing, finding lines, NEW and CLEAR
    .include "Extras.asm"                   ; Business BASIC's added statements, ON ERR, ON KBD, ON EOF#
    .include "SosStuf.asm"                  ; SOS call parameter lists, the console, keys, CONTROL-C
    .include "B3ListD.asm"                  ; LIST, FOR, the statement loop, RUN, CONT
    .include "B3GotoE.asm"                  ; GOTO, GOSUB, RETURN, ON, LET, PRINT and its output
    .include "B3InpuF.asm"                  ; INPUT, GET, READ, NEXT, the expression evaluator's first half
    .include "B3EvalG.asm"                  ; The expression evaluator's second half: operands and operators
    .include "StrUtils.asm"                 ; String space and the garbage collector
    .include "B3MathK.asm"                  ; Floating-point addition, subtraction, normalizing
    .include "B3MathL.asm"                  ; LOG, multiplication, division, moves, comparison
    .include "B3FinpM.asm"                  ; INT, reading a number and formatting one
    .include "B3Expon.asm"                  ; EXP, RND, COS, SIN, TAN, ATN
    .include "B3FreeR.asm"                  ; Freeing strings, pointer arithmetic, IF, WINDOW
    .include "LongInt.asm"                  ; Long integers and the CONV functions
    .include "B3DmpyT.asm"                  ; TEN, HEX$ and SWAP
    .include "B3DimnH.asm"                  ; DIM and the variable search
    .include "B3UdefI.asm"                  ; Arrays' elements, FRE, POS, VPOS, DEF and FN
    .include "StrngStuf.asm"                ; String functions, PREFIX$, TIME$, DATE$
    .include "Invoke.asm"                   ; Loading invokable modules, PERFORM, EXFN
    .include "Invoke1.asm"                  ; The INVOKE statement, shrinking and growing segments
    .include "B3Pru1.asm"                   ; PRINT USING, first part
    .include "B3Pru2.asm"                   ; PRINT USING, second part
    .include "DiskStuf1.asm"                ; Console line input, TYP, REC, CLOSE, PDL, BUTTON
    .include "DiskStuf2.asm"                ; OPEN and the open the file commands share
    .include "DisCmds.asm"                  ; READ#, WRITE#, CHAIN, OUTPUT#, EXEC
    .include "FileStuf.asm"                 ; CREATE, SAVE, LOAD, RENAME, LOCK, UNLOCK, DELETE
    .include "Catalog.asm"                  ; CATALOG, and the table of routines for modules
    .include "BasicEnd.asm"                 ; Calls between BASIC and modules, and the end
