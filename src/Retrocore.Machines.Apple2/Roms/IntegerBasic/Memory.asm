;; INTEGER BASIC: THE COLD START, CONTROL-C, HIMEM:, LOMEM:, LOAD, SAVE, POP AND TRACE ($F000-$F196)
;;
;; The cold start, which finds the top of RAM; the check for Control-C and TRACE before each line; HIMEM: and LOMEM:,
;; which move the ends of BASIC's memory; LOAD and SAVE, which move a program to and from the cassette through the
;; Monitor; and POP, TRACE and NOTRACE.
;;
;; A program on cassette is two records, each written by the Monitor's WRITE with its own header tone and checksum:
;; first the program's length (2 bytes, from ACC), then the program itself, which LOAD reads into the top of memory,
;; ending at HIMEM.
;;
;; Part of IntegerBasic.asm; it follows Statements.asm, at $F000.

;; The cold start: turns TRACE off, sets <LOMEM> to $0800, finds the top of RAM for <HIMEM>, and erases the program
;; (<NEW>).
;;
;; It tests each page from $0900 up by inverting its first byte and inverting it back; the first page where a byte
;; does not read back as written is past the end of RAM.
;; See: <BASIC>, <NEW>
COLD:
    ldy #$00                        ; $F000
    sty NOUNSTKC                    ; $F002 TRACE off
    sty LOMEM                       ; $F004
    sty HIMEM                       ; $F006
    lda #$08                        ; $F008
    sta LOMEM+1                     ; $F00A
    sta HIMEM+1                     ; $F00C
@Loop:
    inc HIMEM+1                     ; $F00E
    lda (HIMEM),y                   ; $F010
    eor #$FF                        ; $F012
    sta (HIMEM),y                   ; $F014
    cmp (HIMEM),y                   ; $F016
    bne COLD_1                      ; $F018
    eor #$FF                        ; $F01A
    sta (HIMEM),y                   ; $F01C
    cmp (HIMEM),y                   ; $F01E restore the byte and check it again
    beq @Loop                       ; $F020 RAM here: try the next page

COLD_1:
    jmp NEW                         ; $F022

;; Not Control-C: prints the line number in TRACE mode (<TRACELINE>).
CHKBREAK_1:
    jmp TRACELINE                   ; $F025

;; Checks for Control-C with the place to stop in X (low) and A (high), then runs from that token; nothing in the
;; ROM reaches it.
CHKBRKRUN:
    jsr CHKBREAKAT                  ; $F028
    jmp GETNEXTXA                   ; $F02B

;; Before each line: stops the program if Control-C was typed, otherwise prints the line number in TRACE mode.
;;
;; Stopping saves the token address (<PX>) in <NOUNSTKL> and the line address (<PR>) in <NOUNSTKH>, both of the
;; first two entries, for CON to continue from.
;; See: <CON>, <STOPPED_AT>, <TRACELINE>
;; Entry: CHKBREAKAT = with the token address already in X (low) and A (high)
CHKBREAK:
    ldx PX                          ; $F02E
    lda PX+1                        ; $F030

CHKBREAKAT:
    ldy KBD                         ; $F032
    cpy #ETX+$80                    ; $F035
    bne CHKBREAK_1                  ; $F037
    bit KBDSTRB                     ; $F039 take the key
    stx NOUNSTKL                    ; $F03C
    sta NOUNSTKL+1                  ; $F03E
    lda PR                          ; $F040
    sta NOUNSTKH                    ; $F042
    lda PR+1                        ; $F044
    sta NOUNSTKH+1                  ; $F046
    jmp STOPPED_AT                  ; $F048
    .byte $FF, $FF                  ; $F04B

;; HIMEM: (token $10): moves the top of BASIC's memory, and the program with it.
;;
;; <AUX> is the distance from the old HIMEM down to the new one. When the new HIMEM is lower, the program moves
;; down, from its first byte up, and must stay above the variables. When it is higher, the program moves up, from its
;; last byte down (<SHIFTUPSTEP>). Whether the new HIMEM is RAM is not checked.
;; In: X = the noun stack, its top entry the new HIMEM
;; Errors: MEM FULL if the program would reach the variables
;; See: <HIMEM>, <VLOMEM>
VHIMEM:
    jsr GET16BIT                    ; $F04D
    stx XSAVE                       ; $F050
    ldx #$FE                        ; $F052 X = $FE, then $FF: the low bytes, then the high
    sec                             ; $F054
@Loop1:
    lda ACC+2,x                     ; $F055
    sta P2+2,x                      ; $F057
    lda HIMEM+2,x                   ; $F059
    sbc ACC+2,x                     ; $F05B
    sta AUX+2,x                     ; $F05D
    inx                             ; $F05F
    bne @Loop1                      ; $F060
    bcc SHIFTUPSTEP                 ; $F062 the new HIMEM is above the old: move the program up
    dex                             ; $F064 X = $FF, then 0
@Loop2:
    lda PP+1,x                      ; $F065
    sta P3+1,x                      ; $F067
    sbc AUX+1,x                     ; $F069
    sta P2+1,x                      ; $F06B
    inx                             ; $F06D
    beq @Loop2                      ; $F06E
    bcc JmpMEMFULL                  ; $F070 the new start must stay above the variables
    lda PV                          ; $F072
    cmp P2                          ; $F074
    lda PV+1                        ; $F076
    sbc P2+1                        ; $F078
    bcc VHIMEM_2                    ; $F07A

;; The MEM FULL error.
JmpMEMFULL:
    jmp MEMFULL                     ; $F07C

;; Moves the program down: copies from <P3>, the old start, to <P2>, the new one, up to the old HIMEM.
VHIMEM_1:
    lda (P3),y                      ; $F07F
    sta (P2),y                      ; $F081
    inc P2                          ; $F083
    bne @NoInc2                     ; $F085
    inc P2+1                        ; $F087
@NoInc2:
    inc P3                          ; $F089
    bne VHIMEM_2                    ; $F08B
    inc P3+1                        ; $F08D

;; Copies until <P3> reaches <HIMEM>.
VHIMEM_2:
    lda P3                          ; $F08F
    cmp HIMEM                       ; $F091
    lda P3+1                        ; $F093
    sbc HIMEM+1                     ; $F095
    bcc VHIMEM_1                    ; $F097

;; Sets <HIMEM> to where the program now ends, <P2>, and <PP> to its start, less the distance moved.
SETNEWHIMEM:
    ldx #$FE                        ; $F099
@Loop:
    lda P2+2,x                      ; $F09B
    sta HIMEM+2,x                   ; $F09D
    lda PP+2,x                      ; $F09F
    sbc AUX+2,x                     ; $F0A1
    sta PP+2,x                      ; $F0A3
    inx                             ; $F0A5
    bne @Loop                       ; $F0A6
    ldx XSAVE                       ; $F0A8
    rts                             ; $F0AA

;; Moves the program up: copies each byte from <HIMEM> to <ACC>, both stepping down, until HIMEM goes below <PP>.
;; Entry: SHIFTUPSTEP = steps first, from the ends
SHIFTPROGUP:
    lda (HIMEM),y                   ; $F0AB
    sta (ACC),y                     ; $F0AD

SHIFTUPSTEP:
    lda ACC                         ; $F0AF
    bne @NoInc                      ; $F0B1
    dec ACC+1                       ; $F0B3
@NoInc:
    dec ACC                         ; $F0B5
    lda HIMEM                       ; $F0B7
    bne SHIFTPROGUP_1               ; $F0B9
    dec HIMEM+1                     ; $F0BB

SHIFTPROGUP_1:
    dec HIMEM                       ; $F0BD
    cmp PP                          ; $F0BF
    lda HIMEM+1                     ; $F0C1
    sbc PP+1                        ; $F0C3
    bcc SHIFTPROGUP                 ; $F0C5
    bcs SETNEWHIMEM                 ; $F0C7

;; LOMEM: (token $11): moves the bottom of the variables, and discards them (<CLR>).
;;
;; The new LOMEM must be below the program. The low byte is compared with $CA, the address of PP, rather than with
;; PP's low byte, so only the high bytes count reliably.
;; In: X = the noun stack, its top entry the new LOMEM
;; Errors: MEM FULL if it is not below the program
;; See: <LOMEM>, <VHIMEM>
VLOMEM:
    jsr GET16BIT                    ; $F0C9
    ldy ACC                         ; $F0CC
    cpy #PP                         ; $F0CE immediate: the constant $CA, not the contents of PP
    lda ACC+1                       ; $F0D0
    sbc PP+1                        ; $F0D2

;; A MEM FULL error if the carry is set.
BcsJmpMEMFULL:
    bcs JmpMEMFULL                  ; $F0D4
    sty LOMEM                       ; $F0D6
    lda ACC+1                       ; $F0D8
    sta LOMEM+1                     ; $F0DA
    jmp CLR                         ; $F0DC

;; LOAD (token $04): reads a program from the cassette into the top of memory, below HIMEM.
;;
;; The first record is the program's length. If it would not fit above the variables it is a MEM FULL error; if it
;; is 0 LOAD only beeps. Otherwise <PP> moves down to make room and the second record is read into the program's
;; place. The variables are kept.
;; Errors: MEM FULL
;; See: <VSAVE>, <SETHDR>, <SETPRG>, <READ>
LOAD:
    stx XSAVE                       ; $F0DF
    jsr SETHDR                      ; $F0E1
    jsr READ                        ; $F0E4 the length, into ACC
    ldx #$FF                        ; $F0E7
    sec                             ; $F0E9
@Loop:
    lda HIMEM+1,x                   ; $F0EA
    sbc ACC+1,x                     ; $F0EC
    sta AUX+1,x                     ; $F0EE
    inx                             ; $F0F0
    beq @Loop                       ; $F0F1
    bcc JmpMEMFULL                  ; $F0F3 longer than memory
    lda PV                          ; $F0F5
    cmp AUX                         ; $F0F7
    lda PV+1                        ; $F0F9
    sbc AUX+1                       ; $F0FB
    bcs BcsJmpMEMFULL               ; $F0FD it would reach the variables
    lda ACC                         ; $F0FF
    bne LOAD_1                      ; $F101
    lda ACC+1                       ; $F103
    beq LOAD_3                      ; $F105

;; Reads the program into its place, from the new <PP> to <HIMEM>.
LOAD_1:
    lda AUX                         ; $F107
    sta PP                          ; $F109
    lda AUX+1                       ; $F10B
    sta PP+1                        ; $F10D
    jsr SETPRG                      ; $F10F
    jsr READ                        ; $F112

;; Restores X and returns.
LOAD_2:
    ldx XSAVE                       ; $F115
    rts                             ; $F117

;; A length of 0: beeps instead of loading.
LOAD_3:
    jsr BELL                        ; $F118
    jmp LOAD_2                      ; $F11B

;; Points the cassette routines at <ACC>: <A1L> = $00CE and <A2L> = $00CF, the program's length.
;; Uses: Y
;; Keeps: A, X
SETHDR:
    ldy #$CE                        ; $F11E
    sty A1L                         ; $F120
    iny                             ; $F122
    sty A2L                         ; $F123
    ldy #$00                        ; $F125
    sty A1H                         ; $F127
    sty A2H                         ; $F129
    rts                             ; $F12B

;; Points the cassette routines at the program: <A1L> = <PP> and <A2L> = <HIMEM> - 1.
;; In: X = 1
;; Out: X = $FF
;; Uses: A, Y
SETPRG:
    lda PP,x                        ; $F12C
    sta A1L,x                       ; $F12E
    ldy HIMEM,x                     ; $F130
    sty A2L,x                       ; $F132
    dex                             ; $F134
    bpl SETPRG                      ; $F135
    lda A2L                         ; $F137
    bne SETPRG_1                    ; $F139
    dec A2H                         ; $F13B

SETPRG_1:
    dec A2L                         ; $F13D
    rts                             ; $F13F

;; Saves X in <XSAVE>, then falls into SAVE; nothing in the ROM reaches it.
SAVEKEEPX:
    stx XSAVE                       ; $F140

;; SAVE (token $05): writes the program to the cassette: its length, then its bytes.
;;
;; The program's record gets a shorter header tone than the length's: $1A against the Monitor's usual $40. SAVE
;; ends by loading X from <XSAVE>, which only the unused entry before it sets.
;; See: <LOAD>, <WRITE>, <WRITE0>
VSAVE:
    sec                             ; $F142
    ldx #$FF                        ; $F143 X = $FF, then 0: ACC = HIMEM - PP
@Loop:
    lda HIMEM+1,x                   ; $F145
    sbc PP+1,x                      ; $F147
    sta ACC+1,x                     ; $F149
    inx                             ; $F14B
    beq @Loop                       ; $F14C
    jsr SETHDR                      ; $F14E
    jsr WRITE                       ; $F151
    ldx #$01                        ; $F154
    jsr SETPRG                      ; $F156
    lda #$1A                        ; $F159 a shorter header tone
    jsr WRITE0                      ; $F15B
    ldx XSAVE                       ; $F15E
    rts                             ; $F160

;; Prints the message at offset Y, then sounds the bell.
;; In: Y = the message's offset from <ErrMsg00>
PRTERR:
    jsr ERRORMESS                   ; $F161
    jmp BELL                        ; $F164

;; POP (token $77): forgets the last GOSUB, so its RETURN will not come back to it.
;;
;; With no GOSUB active it goes to RETURN, for the BAD RETURN error.
;; Errors: BAD RETURN
;; See: <GOSUB>, <RETURN>
POP:
    lda GOSUBNDX                    ; $F167
    bne POP_1                       ; $F169
    jmp RETURN                      ; $F16B

;; Drops the GOSUB.
POP_1:
    dec GOSUBNDX                    ; $F16E
    rts                             ; $F170

;; TRACE (token $7D): turns TRACE mode on: the run loop prints each line's number as it runs it.
;; See: <NOTRACE>, <TRACELINE>, <NOUNSTKC>
TRACE:
    lda #$FF                        ; $F171
    sta NOUNSTKC                    ; $F173
    rts                             ; $F175

;; NOTRACE (token $7A): turns TRACE mode off.
NOTRACE:
    lsr NOUNSTKC                    ; $F176
    rts                             ; $F178

;; In TRACE mode, prints # and the number of the line at <PR>, then a blank.
;; Entry: PRLINENUM = prints them whatever the mode
;; Uses: A, X, Y
TRACELINE:
    bit NOUNSTKC                    ; $F179
    bpl TRACELINE_1                 ; $F17B

PRLINENUM:
    lda #'#'                        ; $F17D
    jsr COUT                        ; $F17F
    ldy #$01                        ; $F182
    lda (PR),y                      ; $F184
    tax                             ; $F186
    iny                             ; $F187
    lda (PR),y                      ; $F188
    jsr PRDEC                       ; $F18A
    lda #BLANK+$80                  ; $F18D
    jmp COUT                        ; $F18F

;; Loads the address of the line running, PR, into A (low) and Y (high); nothing in the ROM reaches it.
GETLINEADR:
    lda PR                          ; $F192
    ldy PR+1                        ; $F194

TRACELINE_1:
    rts                             ; $F196
