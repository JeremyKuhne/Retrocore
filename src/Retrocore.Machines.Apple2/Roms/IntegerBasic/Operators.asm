;; INTEGER BASIC: THE RULE INDEX, DSP, COMPARISONS, AND, OR AND THE LAST STATEMENTS ($F197-$F424)
;;
;; SYNTABLNDX, the tokenizer's index of where each syntax rule starts; the display of a variable marked with DSP when
;; a program assigns it; the comparisons less than, greater than, at most and at least, AND and OR; STEP, which finishes a FOR; DSP and NODSP;
;; CON, ASC(, PDL, ^, PR# and IN#; the line input of INPUT; and a few small routines the other modules share.
;;
;; Part of IntegerBasic.asm; it follows Memory.asm, at $F197.

;; Where each of the 32 syntax rules starts, as the tokenizer's <STARTRULE> takes it: the address less $EC01, halved.
;;
;; A rule therefore starts at an odd offset in its page; bit 7 selects the page at $ED00.
;; See: <SYNTABL>, <CALLRULE>
SYNTABLNDX:
    .byte (RULE00 - SYNTABL - 1) / 2 ; $F197 SNUMBER
    .byte (RULE01 - SYNTABL - 1) / 2 ; SUNUSED1
    .byte (RULE02 - SYNTABL - 1) / 2 ; SSTMT
    .byte (RULE03 - SYNTABL - 1) / 2 ; SDIMSTR
    .byte (RULE04 - SYNTABL - 1) / 2 ; STHEN
    .byte (RULE05 - SYNTABL - 1) / 2 ; SINVARS
    .byte (RULE06 - SYNTABL - 1) / 2 ; SSUBSTR
    .byte (RULE07 - SYNTABL - 1) / 2 ; SEXPR
    .byte (RULE08 - SYNTABL - 1) / 2 ; SSTRING
    .byte (RULE09 - SYNTABL - 1) / 2 ; SSTRVAR
    .byte (RULE0A - SYNTABL - 1) / 2 ; SSTRDEST
    .byte (RULE0B - SYNTABL - 1) / 2 ; SSTMT2
    .byte (RULE0C - SYNTABL - 1) / 2 ; SSTRCHR
    .byte (RULE0D - SYNTABL - 1) / 2 ; SDIMLIST
    .byte (RULE0E - SYNTABL - 1) / 2 ; SPRLIST
    .byte (RULE0F - SYNTABL - 1) / 2 ; SDIGIT
    .byte (RULE10 - SYNTABL - 1) / 2 ; SDIMNUM
    .byte (RULE11 - SYNTABL - 1) / 2 ; SRPAREN
    .byte (RULE12 - SYNTABL - 1) / 2 ; SINNUMS
    .byte (RULE13 - SYNTABL - 1) / 2 ; SSIGNED
    .byte (RULE14 - SYNTABL - 1) / 2 ; SFUNC
    .byte (RULE15 - SYNTABL - 1) / 2 ; SOPERAND
    .byte (RULE16 - SYNTABL - 1) / 2 ; SUNUSED2
    .byte (RULE17 - SYNTABL - 1) / 2 ; SNUMVAR
    .byte (RULE18 - SYNTABL - 1) / 2 ; SASSIGN
    .byte (RULE19 - SYNTABL - 1) / 2 ; SNAME
    .byte (RULE1A - SYNTABL - 1) / 2 ; SIMMED
    .byte (RULE1B - SYNTABL - 1) / 2 ; SSTMT3
    .byte (RULE1C - SYNTABL - 1) / 2 ; SNAMEEND
    .byte (RULE1D - SYNTABL - 1) / 2 ; SNAMECH
    .byte (RULE1E - SYNTABL - 1) / 2 ; SOPER
    .byte (RULE1F - SYNTABL - 1) / 2 ; SLINE

;; Prints the number in ACC and a blank: the value of a variable DSP shows.
;; See: <PRINTACC>
PRNUMBLANK:
    ldy #$00                        ; $F1B7
    jsr PRINTACC                    ; $F1B9
    lda #$A0                        ; $F1BC
    jmp COUT                        ; $F1BE
    .byte $00, $00, $00, $00, $00, $00, $00, $00 ; $F1C1 unused bytes

;; Prints the name of the variable at <AUX>, then =: finds the last variable that starts below AUX.
;;
;; A string's $40 prints as $.
;; In: AUX = the variable's value
;; Uses: A, Y, SRCH
PRVARNAME:
    ldy LOMEM                       ; $F1C9
    lda LOMEM+1                     ; $F1CB
@Loop1:
    pha                             ; $F1CD
    cpy AUX                         ; $F1CE
    sbc AUX+1                       ; $F1D0
    bcs PRSRCHNAME                  ; $F1D2
    pla                             ; $F1D4
    sty SRCH                        ; $F1D5
    sta SRCH+1                      ; $F1D7 SRCH = the variable to look at
    ldy #$FF                        ; $F1D9
@Loop2:
    iny                             ; $F1DB
    lda (SRCH),y                    ; $F1DC
    bmi @Loop2                      ; $F1DE
    cmp #$40                        ; $F1E0
    beq @Loop2                      ; $F1E2 skip the name
    iny                             ; $F1E4 the address of the next variable
    iny                             ; $F1E5
    lda (SRCH),y                    ; $F1E6
    pha                             ; $F1E8
    dey                             ; $F1E9
    lda (SRCH),y                    ; $F1EA
    tay                             ; $F1EC
    pla                             ; $F1ED
    bne @Loop1                      ; $F1EE

;; Prints the name of the variable at <SRCH>, up to its display flag.
PRSRCHNAME:
    pla                             ; $F1F0
    ldy #$00                        ; $F1F1

PRSRCHNAME_1:
    lda (SRCH),y                    ; $F1F3
    bmi PRSRCHNAME_2                ; $F1F5
    lsr a                           ; $F1F7
    beq PRSRCHNAME_3                ; $F1F8
    lda #'$'                        ; $F1FA

PRSRCHNAME_2:
    jsr COUT                        ; $F1FC
    iny                             ; $F1FF
    bne PRSRCHNAME_1                ; $F200

;; Prints the = after the name.
PRSRCHNAME_3:
    lda #'='                        ; $F202
    jmp COUT                        ; $F204

;; Stores the high byte of a numeric assignment and pops the variable; shows it if it is marked with DSP.
;; In: A = the value's high byte, AUX = the variable's value, Y = 1
;; See: <ASSIGN_NUM>, <TRYSHOWNUM>
LETNUMEND:
    sta (AUX),y                     ; $F207
    inx                             ; $F209
    lda NOUNSTKC-1,x                ; $F20A the display flag, which the lookup left in NOUNSTKC
    beq LETNUMEND_1                 ; $F20C
    jmp TRYSHOWNUM                  ; $F20E
    .byte $A0                       ; $F211 an unused byte

;; Shows a numeric variable after an assignment: # and the line number unless TRACE has printed it, then the name,
;; = and the value.
;; In: negative = set in TRACE mode
SHOWNUM:
    bmi SHOWNUM_1                   ; $F212
    lda PR                          ; $F214
    ldy PR+1                        ; $F216
    jsr PRLINENUM                   ; $F218

SHOWNUM_1:
    jsr PRVARNAME                   ; $F21B
    ldx XSAVE                       ; $F21E
    jmp PRNUMBLANK                  ; $F220

;; Pops a string assignment's variable, and shows it if it is marked with DSP.
;; See: <LET_STR>, <TRYSHOWSTR>
LETSTREND:
    inx                             ; $F223
    inx                             ; $F224
    lda NOUNSTKC-1,x                ; $F225
    beq GET16INC_1                  ; $F227
    jmp TRYSHOWSTR                  ; $F229

;; Shows a string variable after an assignment, as <SHOWNUM> shows a number.
SHOWSTR:
    bmi SHOWSTR_1                   ; $F22C
    lda PR                          ; $F22E
    ldy PR+1                        ; $F230
    jsr PRLINENUM                   ; $F232

SHOWSTR_1:
    jsr PRVARNAME                   ; $F235
    ldx XSAVE                       ; $F238
    jmp PRSTRAUX                    ; $F23A
    .byte $E8                       ; $F23D an unused byte

LETNUMEND_1:
    rts                             ; $F23E

;; Takes a number off the noun stack and adds 1.
;; Out: ACC = the number + 1
;; See: <GET16BIT>
GET16INC:
    jsr GET16BIT                    ; $F23F
    inc ACC                         ; $F242
    bne GET16INC_1                  ; $F244
    inc ACC+1                       ; $F246

GET16INC_1:
    rts                             ; $F248

;; < (token $1C): replaces two numbers with 1 if the lower is less than the top one, 0 if not: NOT >=.
;;
;; <NOT> always ends with Z clear, so the branch is always taken.
;; See: <GREATEQ>, <NOT>
LESS:
    jsr GREATEQ                     ; $F249
    bne JmpNOT                      ; $F24C

;; > (token $19): 1 if the lower number is greater than the top one: NOT <=.
GREATER:
    jsr LESSEQ                      ; $F24E
    bne JmpNOT                      ; $F251

;; <= (token $1A): 1 if the lower number is at most the top one: the difference, negated, is not negative.
LESSEQ:
    jsr SUBTRACT                    ; $F253
    jsr NEGATE                      ; $F256
    bvc GREATEQ_1                   ; $F259 always: an overflow is an error

;; >= (token $18): 1 if the lower number is at least the top one: the difference is not negative.
;;
;; The difference's sign (<SGN>) halved is 0 for 0 and 1, and $FF7F for -1; <NOT> turns that into 1, 1 and 0.
;; Errors: >32767 if the difference overflows
GREATEQ:
    jsr SUBTRACT                    ; $F25B

GREATEQ_1:
    jsr SGN                         ; $F25E
    lsr NOUNSTKL,x                  ; $F261

;; Replaces the top number with NOT of it.
JmpNOT:
    jmp NOT                         ; $F263

;; AND (token $1D): 1 if both numbers are not 0, else 0.
;;
;; It works as NOT (NOT a OR NOT b) on the 0 and 1 that <NOTBOTH> leaves.
;; See: <NOTBOTH>, <VOR>
VAND:
    jsr NOTBOTH                     ; $F266
    ora NOUNSTKL-1,x                ; $F269
    bpl VOR_1                       ; $F26B always: A is 0 or 1

;; OR (token $1E): 1 if either number is not 0, else 0: NOT (NOT a AND NOT b).
;; See: <NOTBOTH>, <VAND>
VOR:
    jsr NOTBOTH                     ; $F26D
    and NOUNSTKL-1,x                ; $F270

VOR_1:
    sta NOUNSTKL,x                  ; $F272
    bpl JmpNOT                      ; $F274
    jmp NOTBOTH                     ; $F276 unused: the branch before it is always taken

;; STEP (token $58): sets the step of the FOR loop being set up, and the place to loop back to again, after STEP.
;; In: X = the noun stack, its top entry the step
;; See: <TO>, <FOR>
STEP:
    jsr GET16BIT                    ; $F279
    ldy FORNDX                      ; $F27C
    lda ACC                         ; $F27E
    sta STK_60-1,y                  ; $F280
    lda ACC+1                       ; $F283
    jmp SETFORPLACE                 ; $F285

;; The rest of FOR: stores the variable's high byte, then removes any older FOR loop for the same variable,
;; moving the loops above it down.
;;
;; The move copies the <STK_A0> column twice and never <STK_B0>, so a loop that moves keeps the high byte of the
;; token address of the loop that was above it. The 1983 System Master's INTBASIC copies <STK_B0> instead, which
;; FORFIX builds.
;; See: <FOR>
FORDROPOLD:
    sta STK_50,y                    ; $F288
@Loop1:
    dey                             ; $F28B
    bmi @Return                     ; $F28C
    lda STK_40,y                    ; $F28E
    cmp NOUNSTKL,x                  ; $F291
    bne @Loop1                      ; $F293
    lda STK_50,y                    ; $F295
    cmp NOUNSTKH,x                  ; $F298
    bne @Loop1                      ; $F29A
    dec FORNDX                      ; $F29C one loop fewer
@Loop2:
    lda STK_40+1,y                  ; $F29E
    sta STK_40,y                    ; $F2A1
    lda STK_50+1,y                  ; $F2A4
    sta STK_50,y                    ; $F2A7
    lda STK_C0+1,y                  ; $F2AA
    sta STK_C0,y                    ; $F2AD
    lda STK_D0+1,y                  ; $F2B0
    sta STK_D0,y                    ; $F2B3
    lda STK_60+1,y                  ; $F2B6
    sta STK_60,y                    ; $F2B9
    lda STK_70+1,y                  ; $F2BC
    sta STK_70,y                    ; $F2BF
    lda STK_80+1,y                  ; $F2C2
    sta STK_80,y                    ; $F2C5
    lda STK_90+1,y                  ; $F2C8
    sta STK_90,y                    ; $F2CB
    lda STK_A0+1,y                  ; $F2CE
    sta STK_A0,y                    ; $F2D1
.if FORFIX
    lda STK_B0+1,y                  ; $F2D4
    sta STK_B0,y                    ; $F2D7
.else
    lda STK_A0+1,y                  ; $F2D4 STK_A0 again, where STK_B0 would be
    sta STK_A0,y                    ; $F2D7
.endif
    iny                             ; $F2DA
    cpy FORNDX                      ; $F2DB
    bcc @Loop2                      ; $F2DD
@Return:
    rts                             ; $F2DF

;; NODSP of a string (token $78): stops showing the variable when it is assigned.
;; In: X = the noun stack, its top entries the variable's range and address
;; See: <NODSP_NUM>, <DSP_STR>
NODSP_STR:
    inx                             ; $F2E0

;; NODSP of a number (token $79): clears the variable's display flag.
;; In: X = the noun stack, its top entry the variable's address
NODSP_NUM:
    lda #$00                        ; $F2E1

;; Sets the display flag of the variable on the noun stack to A, and pops it.
;;
;; The flag is the byte 3 before the value, after the name and before the next variable's address.
;; In: A = 0 or 1
SETDSPFLAG:
    pha                             ; $F2E3
    lda NOUNSTKL,x                  ; $F2E4
    sec                             ; $F2E6
    sbc #$03                        ; $F2E7
    sta ACC                         ; $F2E9
    lda NOUNSTKH,x                  ; $F2EB
    sbc #$00                        ; $F2ED
    sta ACC+1                       ; $F2EF
    pla                             ; $F2F1
    ldy #$00                        ; $F2F2
    sta (ACC),y                     ; $F2F4
    inx                             ; $F2F6
    rts                             ; $F2F7

;; A keyword matched (<GOTKEYWORD>): writes its token, or fails if it is a reserved word ($85 and up).
;;
;; Failing with Y = 2, at the bottom of the first page, makes the name rule (<SNAMECH>) try a digit and end the name.
;; In: A = the token
KEYMATCHED:
    cmp #$85                        ; $F2F8
    bcs KEYMATCHED_1                ; $F2FA
    jmp PUTTOKNEXT                  ; $F2FC

KEYMATCHED_1:
    ldy #$02                        ; $F2FF
    jmp ITEMFAILED                  ; $F301

;; DSP of a string (token $7B): shows the variable each time it is assigned.
;; In: X = the noun stack, its top entries the variable's range and address
;; See: <DSP_NUM>, <NODSP_STR>
DSP_STR:
    inx                             ; $F304

;; DSP of a number (token $7C): sets the variable's display flag.
;; In: X = the noun stack, its top entry the variable's address
DSP_NUM:
    lda #$01                        ; $F305
    bne SETDSPFLAG                  ; $F307 always
    .byte $E8                       ; $F309 an unused byte

;; CON (token $06): continues a program stopped by Control-C, from the token where it stopped.
;;
;; <CHKBREAK> saved the place in the noun stack's first entries.
;; See: <CHKBREAK>, <GETNEXT>
CON:
    lda NOUNSTKH                    ; $F30A
    sta PR                          ; $F30C
    lda NOUNSTKH+1                  ; $F30E
    sta PR+1                        ; $F310
    lda NOUNSTKL                    ; $F312
    ldy NOUNSTKL+1                  ; $F314
    jmp GETNEXT                     ; $F316

;; Sets a variable's display flag to 1, as DSP does; nothing in the ROM reaches it.
DSPFLAGON:
    lda #$01                        ; $F319
    bne SETDSPFLAG                  ; $F31B

;; ASC( (token $3C): replaces a string with its first character's code, bit 7 set as the Apple II keeps text: 193
;; for A.
;; In: X = the noun stack, its top entries the string's range and address
;; Errors: RANGE for an empty string
ASC:
    lda NOUNSTKL,x                  ; $F31D
    cmp NOUNSTKH,x                  ; $F31F
    bcc ASC_1                       ; $F321
    jmp RANGERR                     ; $F323

;; Reads the character and pushes it as a number.
ASC_1:
    tay                             ; $F326
    lda NOUNSTKL+1,x                ; $F327
    sta ACC                         ; $F329
    lda NOUNSTKH+1,x                ; $F32B
    sta ACC+1                       ; $F32D
    lda (ACC),y                     ; $F32F
    ldy #$00                        ; $F331
    inx                             ; $F333
    inx                             ; $F334
    jsr PUSHNOUN                    ; $F335
    jmp HIBYTEPAREN                 ; $F338

;; PDL (token $32): replaces a paddle's number, 0 to 3, with its position, 0 to 255.
;; In: X = the noun stack, its top entry the paddle
;; See: <PREAD>
PDL:
    jsr GETBYTE                     ; $F33B
    stx XSAVE                       ; $F33E
    and #$03                        ; $F340
    tax                             ; $F342
    jsr PREAD                       ; $F343
    ldx XSAVE                       ; $F346
    tya                             ; $F348
    ldy #$00                        ; $F349
    jsr PUSHNOUN                    ; $F34B
    sty NOUNSTKC,x                  ; $F34E
    rts                             ; $F350

;; Reads a line into <IN> from index X, after the prompt, and goes to the warm start if it holds a Control-C.
;;
;; INPUT of a string reads with it.
;; In: X = where the line starts in IN
;; Out: X = the index of the return that ends it
;; See: <NXTCHAR>, <INPUTSTR>
;; Entry: CHKCTRLC = checks the line already in IN up to index X
RDKEY:
    jsr NXTCHAR                     ; $F351

CHKCTRLC:
    txa                             ; $F354
    pha                             ; $F355

CHKCTRLC_1:
    lda IN,x                        ; $F356
    cmp #ETX+$80                    ; $F359
    bne CHKCTRLC_2                  ; $F35B
    jmp BASIC2                      ; $F35D Control-C: back to BASIC's prompt

CHKCTRLC_2:
    dex                             ; $F360
    bpl CHKCTRLC_1                  ; $F361
    pla                             ; $F363
    tax                             ; $F364
    rts                             ; $F365

;; Reads a line for INPUT of numbers, with the ? prompt, and checks it for Control-C.
;; Out: Y = the index of the underline that ends it
;; See: <GETQLINE>, <INPUTNUM>
INPUTNUMLN:
    jsr GETQLINE                    ; $F366
    tya                             ; $F369
    tax                             ; $F36A
    jsr CHKCTRLC                    ; $F36B
    txa                             ; $F36E
    tay                             ; $F36F
    rts                             ; $F370

;; ^ (token $20): replaces two numbers with the lower one raised to the power of the top one.
;;
;; The power is repeated multiplication, starting from 1. A negative exponent gives 0: it pushes 0, leaving both
;; operands below it on the noun stack.
;; In: X = the noun stack: the base, then the exponent on top
;; Out: X = the noun stack, its top entry the power
;; Errors: >32767
;; See: <MULT>
EXP:
    jsr GET16BIT                    ; $F371
    lda ACC+1                       ; $F374
    bpl EXP_2                       ; $F376
    tya                             ; $F378
    dex                             ; $F379
    jsr PUSHNOUN                    ; $F37A
    sty NOUNSTKC,x                  ; $F37D

EXP_1:
    rts                             ; $F37F

;; Multiplies 1 by the base as many times as the exponent says: <SRCH> counts, <SRCH2> holds the base.
EXP_2:
    sta SRCH+1                      ; $F380
    lda ACC                         ; $F382
    sta SRCH                        ; $F384
    jsr GET16BIT                    ; $F386
    lda ACC                         ; $F389
    sta SRCH2                       ; $F38B
    lda ACC+1                       ; $F38D
    sta SRCH2+1                     ; $F38F
    lda #$01                        ; $F391
    jsr PUSHNOUN                    ; $F393
    sty NOUNSTKC,x                  ; $F396
@Loop:
    lda SRCH                        ; $F398
    bne @NoDec                      ; $F39A
    dec SRCH+1                      ; $F39C
    bmi EXP_1                       ; $F39E
@NoDec:
    dec SRCH                        ; $F3A0
    lda SRCH2                       ; $F3A2
    ldy #$00                        ; $F3A4
    jsr PUSHNOUN                    ; $F3A6
    lda SRCH2+1                     ; $F3A9
    sta NOUNSTKC,x                  ; $F3AB
    jsr MULT                        ; $F3AD
    jmp @Loop                       ; $F3B0

;; Takes a byte from the noun stack, less 1: VTAB's line counted from 0.
;; Out: A = the byte - 1
GETBYTEDEC:
    jsr GETBYTE                     ; $F3B3
    clc                             ; $F3B6
    adc #$FF                        ; $F3B7

GETBYTEDEC_1:
    rts                             ; $F3B9

;; PRINT's comma at the end of the statement (token $4A): moves to the next tab stop, and the line owes no return.
COMMA_PREND:
    jsr NEXTTAB                     ; $F3BA
    lsr CRFLAG                      ; $F3BD
    rts                             ; $F3BF

;; Runs a line's tokens with the run flag and the stack pointer set from X; nothing in the ROM reaches it.
RUNTOKENS:
    stx RUNFLAG                     ; $F3C0
    txs                             ; $F3C2
    jsr CHKBREAK                    ; $F3C3
    jmp RUNLOOP                     ; $F3C6

;; PR# (token $7E): sends output to slot n's ROM, or to the screen for 0.
;; In: X = the noun stack, its top entry the slot
;; See: <OUTPORT>, <INSLOT>
PRSLOT:
    jsr GETBYTE                     ; $F3C9
    stx XSAVE                       ; $F3CC
    jsr OUTPORT                     ; $F3CE
    ldx XSAVE                       ; $F3D1
    rts                             ; $F3D3
    .byte $FE                       ; $F3D4 an unused byte

;; After a numeric assignment to a DSP variable: shows it, if a program is running.
;; See: <SHOWNUM>
TRYSHOWNUM:
    bit RUNFLAG                     ; $F3D5
    bpl GETBYTEDEC_1                ; $F3D7
    stx XSAVE                       ; $F3D9
    bit NOUNSTKC                    ; $F3DB
    jmp SHOWNUM                     ; $F3DD

;; After a string assignment to a DSP variable: shows it, if a program is running.
;; See: <SHOWSTR>
TRYSHOWSTR:
    bit RUNFLAG                     ; $F3E0
    bpl GETBYTEDEC_1                ; $F3E2
    stx XSAVE                       ; $F3E4
    bit NOUNSTKC                    ; $F3E6
    jmp SHOWSTR                     ; $F3E8

;; Reads the next byte of the line (<GETVERB>), with Y = 0.
GETVERB0:
    ldy #$00                        ; $F3EB
    jmp GETVERB                     ; $F3ED

;; Moves to the next line for TAB.
SETCURCOL_1:
    tay                             ; $F3F0
    jsr CROUT                       ; $F3F1

;; Sets the cursor's column to Y, moving down a line for each window's width it passes.
;; In: Y = the column, from 0
;; See: <TAB>, <NEXTTAB>
SETCURCOL:
    tya                             ; $F3F4
    sec                             ; $F3F5
    sbc WNDWDTH                     ; $F3F6
    bcs SETCURCOL_1                 ; $F3F8
    sty CH                          ; $F3FA
    rts                             ; $F3FC
    .byte $00, $00, $00, $FF, $FF, $FF, $FF ; $F3FD unused bytes

;; Stores Y as the high byte of the number just pushed, then ends like a left parenthesis (<LEFT_PAREN>).
HIBYTEPAREN:
    sty NOUNSTKC,x                  ; $F404
    jmp LEFT_PAREN                  ; $F406

;; Prints the string at <AUX>, up to the byte with bit 7 clear that ends it, and sets <CRFLAG>.
PRSTRAUX:
    ldy #$00                        ; $F409
    beq PRSTRAUX_2                  ; $F40B

PRSTRAUX_1:
    jsr COUT                        ; $F40D
    iny                             ; $F410

PRSTRAUX_2:
    lda (AUX),y                     ; $F411
    bmi PRSTRAUX_1                  ; $F413
    lda #$FF                        ; $F415
    sta CRFLAG                      ; $F417
    rts                             ; $F419

;; IN# (token $7F): takes input from slot n's ROM, or from the keyboard for 0.
;; In: X = the noun stack, its top entry the slot
;; See: <INPORT>, <PRSLOT>
INSLOT:
    jsr GETBYTE                     ; $F41A
    stx XSAVE                       ; $F41D
    jsr INPORT                      ; $F41F
    ldx XSAVE                       ; $F422
    rts                             ; $F424
