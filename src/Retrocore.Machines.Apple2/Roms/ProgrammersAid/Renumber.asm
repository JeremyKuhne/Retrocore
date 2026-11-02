;; PROGRAMMER'S AID #1: RENUMBER AND APPEND ($D400-$D4D4)
;;
;; Steve Wozniak's renumbering of Integer BASIC programs (1978), and Append, which loads a program from tape in front
;; of the one in memory. Both are mostly SWEET16 (Sweet16.mac), with 6502 code where they print or call BASIC.
;;
;; Renumber works in two passes over the program, which lies from PP up to HIMEM. The first gives each line in the
;; range its new number, keeping the old numbers in a table between the variables (PV) and the program, and prints
;; each change as `old -> new`; MEM FULL if the table does not fit. The second rewrites every line number in the
;; program, and every number after GOTO, GOSUB, THEN, LIST and DEL, that is in the table. A line whose new number
;; would not keep the program in order stops it with RANGE ERR before anything changes.
;;
;; BASIC calls the front ends in RenumberCalls.asm, which read the new numbering from BASIC's variables START and
;; STEP, and the range from FROM and TO, and enter <Renumber::RENUM>. <Renumber::RENX> is the listing's own range entry.
;;
;; Names follow Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1). Part of ProgrammersAid.asm.

.scope Renumber

; The 6502 side: page zero, Integer BASIC and the Monitor.

;; SWEET16's R0, the accumulator, low byte: the old line number <PRDEC> prints.
R0L = $00

;; R0's high byte.
R0H = $01

;; The constant 1, as Apple's listing names it.
ONE = $01

;; SWEET16's R11, low byte: the new line number <PRDEC> prints.
R11L = $16

;; R11's high byte.
R11H = $17

;; Inherit: <IntegerBasic:HIMEM>
HIMEM = $4C

;; Inherit: <IntegerBasic:PP>
PPL = $CA

;; Inherit: <IntegerBasic:PV>
PVL = $CC

;; Inherit: <IntegerBasic:MEMFULL>
MEMFULL = $E36B

;; Inherit: <IntegerBasic:PRDEC>
PRDEC = $E51B

;; Integer BASIC's RANGE ERR.
RANGERR = $EE68

;; Inherit: <IntegerBasic:LOAD>
LOAD = $F0DF

;; Inherit: <IntegerBasic:SW16>
SW16 = $F689

;; Inherit: <Monitor:CROUT>
CROUT = $FD8E

;; Inherit: <Monitor:COUT>
COUT = $FDED

; The SWEET16 registers. Several names share a register; each pass gives it its own use.

ACC = $0                            ;; R0, the accumulator
NEWLOW = $1                         ;; R1: the first new line number (START)
NEWINCR = $2                        ;; R2: the step between new numbers (STEP)
LNLOW = $3                          ;; R3: the lowest line renumbered (FROM)
LNHI = $4                           ;; R4: the highest line renumbered (TO)
TBLSTRT = $5                        ;; R5: the start of the line number table
TBLNDX1 = $6                        ;; R6: pass 1's index into the table
TBLIM = $7                          ;; R7: the end of the room for the table
SCR8 = $8                           ;; R8: scratch
HMEM = $8                           ;; R8: HIMEM, the end of the program
SCR9 = $9                           ;; R9: scratch
PRGNDX = $9                         ;; R9: pass 1's index into the program
PRGNDX1 = $A                        ;; R10: pass 1's line being read
NEWLN = $B                          ;; R11: the next new line number
NEWLN1 = $C                         ;; R12: the last new line number given
TBLND = $6                          ;; R6: pass 2's end of the table
PRGNDX2 = $7                        ;; R7: pass 2's index into the program
CHR0 = $9                           ;; R9: the character "0"
CHRA = $A                           ;; R10: the character "A"
MODE = $C                           ;; R12: -1 while the number after a token is a line number
TBLNDX2 = $B                        ;; R11: pass 2's index into the table
OLDLN = $D                          ;; R13: the old line number being looked up
STRCON = $B                         ;; R11: the string constant token, $28
REM = $C                            ;; R12: the REM token, $5D
R13 = $D                            ;; R13, which compares leave their result in
THEN = $D                           ;; R13: the THEN token, $24
LIST = $D                           ;; R13: the LIST token, $74
DEL = $D                            ;; R13: the DEL token
SCRC = $C                           ;; R12: Append's scratch

;; Renumbers the lines from <LNLOW> to <LNHI>, having set the range to every line: the listing's range entry.
;; In: NEWLOW = the first new number, NEWINCR = the step
RENX:
    jsr SW16                        ; $D400
    SUB ACC                         ; $D403
    ST LNLOW                        ; $D404
    ST LNHI                         ; $D405
    DCR LNHI                        ; $D406
    RTN                             ; $D407

;; Renumbers the program's lines from <LNLOW> to <LNHI>, starting at <NEWLOW> and stepping by <NEWINCR>, printing
;; each change; RANGE ERR if the new numbers would put the lines out of order, MEM FULL if the table does not fit.
;; In: NEWLOW = the first new number, NEWINCR = the step, LNLOW/LNHI = the lines renumbered
RENUM:
    jsr SW16                        ; $D408
    SET HMEM, HIMEM                 ; $D40B
    LDD [HMEM]                      ; $D40E
    ST HMEM                         ; $D40F

RNUM3:
    SET SCR9, PVL+2                 ; $D410
    POPD [SCR9]                     ; $D413 the table starts at PV
    ST TBLSTRT                      ; $D414
    ST TBLNDX1                      ; $D415
    LD NEWLOW                       ; $D416
    ST NEWLN                        ; $D417
    ST NEWLN1                       ; $D418
    POPD [SCR9]                     ; $D419 and can grow up to PP
    ST TBLIM                        ; $D41A
    ST PRGNDX                       ; $D41B

; Pass 1: each line in the range gets the next new number, and its old number goes in the table.
PASS1:
    LD PRGNDX                       ; $D41C
    CPR HMEM                        ; $D41D
    BC PASS2                        ; $D41E past the last line
    ST PRGNDX1                      ; $D420
    LD TBLNDX1                      ; $D421
    INR ACC                         ; $D422
    CPR TBLIM                       ; $D423
    BC MERR                         ; $D424 no room for two more bytes
    LD [PRGNDX1]                    ; $D426 the line's length
    ADD PRGNDX                      ; $D427
    ST PRGNDX                       ; $D428
    LDD [PRGNDX1]                   ; $D429 its number
    CPR LNLOW                       ; $D42A
    BNC P1B                         ; $D42B below the range
    CPR LNHI                        ; $D42D
    BNC P1A                         ; $D42E
    BNZ P1C                         ; $D430 above the range

P1A:
    STD [TBLNDX1]                   ; $D432
    RTN                             ; $D433
    lda R0H                         ; $D434 print "old->new"
    ldx R0L                         ; $D436
    jsr PRDEC                       ; $D438
    lda #$AD                        ; $D43B "-"
    jsr COUT                        ; $D43D
    lda #$BE                        ; $D440 ">"
    jsr COUT                        ; $D442
    lda R11H                        ; $D445
    ldx R11L                        ; $D447
    jsr PRDEC                       ; $D449
    jsr CROUT                       ; $D44C
    jsr SW16+3                      ; $D44F back to SWEET16, its registers kept
    LD NEWLN                        ; $D452
    ST NEWLN1                       ; $D453
    ADD NEWINCR                     ; $D454
    ST NEWLN                        ; $D455
    .byte $0D                       ; $D456 a SWEET16 no-op that skips the next instruction

P1B:
    CPR NEWLOW                      ; $D457
    BNC PASS1                       ; $D458

RERR:
    RTN                             ; $D45A
    jmp RANGERR                     ; $D45B

MERR:
    RTN                             ; $D45E
    jmp MEMFULL                     ; $D45F

P1C:
    INR NEWLN1                      ; $D462
    CPR NEWLN1                      ; $D463
    BNC RERR                        ; $D464

; Pass 2: every line number in the program, and every number after a token that takes one, that is in the table
; becomes its new number.
PASS2:
    SET CHR0, $00B0                 ; $D466
    SET CHRA, $00C0                 ; $D469

P2A:
    LD PRGNDX2                      ; $D46C
    CPR HMEM                        ; $D46D
    BC DONE                         ; $D46E
    INR PRGNDX2                     ; $D470 past the length byte
    LDD [PRGNDX2]                   ; $D471 the line's number

UPDATE:
    ST OLDLN                        ; $D472
    LD TBLSTRT                      ; $D473
    ST TBLNDX2                      ; $D474
    LD NEWLOW                       ; $D475
    .byte $1C                       ; $D476 SET R12, which skips the next two bytes

UD2:
    LD NEWLN1                       ; $D477
    ADD NEWINCR                     ; $D478
    ST NEWLN1                       ; $D479
    LD TBLNDX2                      ; $D47A
    SUB TBLND                       ; $D47B
    BC UD3                          ; $D47C not in the table
    LDD [TBLNDX2]                   ; $D47E
    SUB OLDLN                       ; $D47F
    BNZ UD2                         ; $D480
    POPD [PRGNDX2]                  ; $D482
    LD NEWLN1                       ; $D483
    STD [PRGNDX2]                   ; $D484

UD3:
    SET STRCON, $0028               ; $D485
    .byte $1C                       ; $D488 SET R12, which skips the next two instructions

GOTCON:
    LDD [PRGNDX2]                   ; $D489 a number's value
    DCR MODE                        ; $D48A
    BM1 UPDATE                      ; $D48B a line number to update

ITEM:
    LD [PRGNDX2]                    ; $D48D the next token
    CPR CHR0                        ; $D48E
    BNC CHKTOK                      ; $D48F
    CPR CHRA                        ; $D491
    BNC GOTCON                      ; $D492 a number

SKPASC:
    DCR PRGNDX2                     ; $D494
    LDD [PRGNDX2]                   ; $D495
    BM SKPASC                       ; $D496 skip a name, a string or a remark
    DCR PRGNDX2                     ; $D498
    LD [PRGNDX2]                    ; $D499

CHKTOK:
    CPR STRCON                      ; $D49A
    BZ SKPASC                       ; $D49B
    SET REM, $005D                  ; $D49D
    CPR REM                         ; $D4A0
    BZ SKPASC                       ; $D4A1
    BM1 CONTST                      ; $D4A3 GOSUB
    DCR R13                         ; $D4A5
    DCR R13                         ; $D4A6
    BZ CONTST                       ; $D4A7 GOTO
    SET THEN, $0024                 ; $D4A9
    CPR THEN                        ; $D4AC
    BZ CONTST                       ; $D4AD
    DCR ACC                         ; $D4AF
    BZ P2A                          ; $D4B0 the end of the line
    SET LIST, $0074                 ; $D4B2
    SUB LIST                        ; $D4B5
    BNM1 CONTS2                     ; $D4B6 LIST or its comma, $74 or $75

CONTST:
    SUB ACC                         ; $D4B8

CONTS2:
    ST MODE                         ; $D4B9
    BR ITEM                         ; $D4BA

;; APPEND (CALL -11076): loads a program from tape in front of the one in memory, whose lines must all be numbered
;; higher. After MEM FULL, CALL -11059 (<APPEND_1>) brings the program in memory back.
APPEND:
    jsr SW16                        ; $D4BC
    SET SCRC, HIMEM+2               ; $D4BF
    POPD [SCRC]                     ; $D4C2 keep HIMEM
    ST HMEM                         ; $D4C3
    SET SCR9, PPL                   ; $D4C4
    LDD [SCR9]                      ; $D4C7
    STD [SCRC]                      ; $D4C8 HIMEM = PP, which keeps the program in memory
    RTN                             ; $D4C9
    jsr LOAD                        ; $D4CA

;; After a tape load, or CALL -11059 after MEM FULL: puts back the HIMEM <APPEND> kept, so both programs show.
APPEND_1:
    jsr SW16                        ; $D4CD
    POPD [SCRC]                     ; $D4D0
    LD HMEM                         ; $D4D1
    STD [SCRC]                      ; $D4D2

DONE:
    RTN                             ; $D4D3
    rts                             ; $D4D4

.endscope
