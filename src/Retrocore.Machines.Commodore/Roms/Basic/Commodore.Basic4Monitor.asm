; COMMODORE BASIC 4: MACHINE-LANGUAGE MONITOR

;; Emits the monitor shared by the original and revised BASIC 4 ROMs.
.macro COMMODORE_BASIC4_MONITOR
;; Enters the monitor after a CALL, identifying the entry as C.
CALLE:
    lda #'C'
    sta TMPC
    bne B3

;; Enters the monitor after BRK, saving the interrupted registers and corrected PC.
;;
;; The kernal's interrupt entry has stacked Y, X, A, status and the return address. The monitor
;; saves the IRQ vector and stack pointer and enables interrupts before displaying the registers.
BRKE:
    jsr CLRCH
    lda #'B'
    sta TMPC
    cld
    lsr a
    pla
    sta YR
    pla
    sta XR
    pla
    sta ACC
    pla
    sta FLGS
B3:
    pla
    adc #$FF
    sta PCL
    pla
    adc #$FF
    sta PCH
    lda CINV
    sta INVL
    lda CINV+1
    sta INVH
    tsx
    stx SP
    cli
B5:
    jsr CRLF
    ldx TMPC
    lda #'*'
    jsr WRTWO
    lda #'R'
    bne S0

;; Prompts for a monitor command, ignoring periods and spaces.
STRT:
    lda #$02
    sta TXTPTR
    lda #$00
    sta WRAP
    ldx #CR
    lda #'.'
    jsr WRTWO
ST1:
    jsr RDOC
    cmp #'.'
    beq ST1
    cmp #' '
    beq ST1
S0:
    ldx #(NCMDS-1)
S1:
    cmp CMDS,x
    bne S2
    stx SAVX
    lda ADRH,x
    pha
    lda ADRL,x
    pha
    rts
S2:
    dex
    bpl S1
    jmp (USRCMD)

;; Copies the current monitor address to the saved program counter.
PUTP:
    lda TMP0
    sta PCL
    lda TMP0+1
    sta PCH
    rts

;; Prints A bytes from the address in <TMP0>, advancing it; A=0 prints 256 bytes.
DM:
    sta TMPC
    ldy #$00
DM1:
    jsr SPACE
    lda (TMP0),y
    jsr WROB
    jsr INCTMP
    dec TMPC
    bne DM1
    rts

;; Reads a hexadecimal byte, writes it at <TMP0> if present, and verifies the write.
BYTE:
    jsr RDOB
    bcc BY3
    ldx #$00
    sta (TMP0,x)
    cmp (TMP0,x)
    beq BY3
    pla
    pla
    jmp ERROPR
BY3:
    jsr INCTMP
    dec TMPC
    rts

;; Selects the five saved status and register bytes for display or alteration.
;; Out: A = 5, TMP0 = address of <FLGS>
SETR:
    lda #<FLGS
    sta TMP0
    lda #>FLGS
    sta TMP0+1
    lda #$05
    rts

;; Prints two spaces.
SPAC2:
    jsr SPACE
;; Prints one space.
SPACE:
    lda #' '
    .byte $2C                   ; BIT absolute skips the following LDA immediate
;; Prints a carriage return.
CRLF:
    lda #CR
    jmp BSOUT

;; Advances <TMP0> and marks wraparound at $FFFF.
INCTMP:
    inc TMP0
    bne SETWR
    inc TMP0+1
    bne SETWR
    inc WRAP
SETWR:
    rts

;; Monitor command characters in dispatch order.
CMDS:
    .byte ':', ';', 'R', 'M', 'G', 'X', 'L', 'S'
;; High bytes of the monitor command return addresses.
ADRH:
    .byte >(ALTM-1), >(ALTR-1), >(DSPLYR-1), >(DSPLYM-1)
    .byte >(MGO-1), >(EXIT-1), >(LD-1), >(LD-1)
;; Low bytes of the monitor command return addresses.
ADRL:
    .byte <(ALTM-1), <(ALTR-1), <(DSPLYR-1), <(DSPLYM-1)
    .byte <(MGO-1), <(EXIT-1), <(LD-1), <(LD-1)
;; Monitor register-display heading.
REGK:
    .byte CR, "     PC  IRQ  SR AC XR YR SP"

;; Starts an editable monitor output line with the character in Y.
ALTRIT:
    tya
    pha
    jsr CRLF
    pla
    ldx #'.'
    jsr WRTWO
    jmp SPAC2

;; Displays the saved PC, IRQ vector and registers.
DSPLYR:
    ldx #$00
D2:
    lda REGK,x
    jsr BSOUT
    inx
    cpx #29
    bne D2
    ldy #';'
    jsr ALTRIT
    lda PCH
    jsr WROB
    lda PCL
    jsr WROB
    jsr SPACE
    lda INVH
    jsr WROB
    lda INVL
    jsr WROB
    jsr SETR
    jsr DM
    beq BEQS1

;; Displays eight-byte rows while their start addresses are in range, until STOP or address wrap.
DSPLYM:
    jsr RDOC
    jsr RDOA
    bcc ERRS1
    jsr T2T2
    jsr RDOC
    jsr RDOA
    bcc ERRS1
    jsr T2T2
DSP1:
    jsr STOP1
    beq BEQS1
    ldx WRAP
    bne BEQS1
    sec
    lda TMP2
    sbc TMP0
    lda TMP2+1
    sbc TMP0+1
    bcc BEQS1
    ldy #':'
    jsr ALTRIT
    jsr WROA
    lda #$08
    jsr DM
    beq DSP1
BEQS1:
    jmp STRT
ERRS1:
    jmp ERROPR

;; Alters the saved PC, IRQ vector and register bytes.
ALTR:
    jsr RDOB
    jsr RDOA
    bcc AL2
    jsr PUTP
AL2:
    jsr BASIN
    jsr RDOA
    bcc AL3
    lda TMP0
    sta INVL
    lda TMP0+1
    sta INVH
AL3:
    jsr SETR
    bne A4

;; Alters up to eight bytes at a supplied memory address.
ALTM:
    jsr RDOB
    jsr RDOA
    bcc ERRS1
    lda #$08
A4:
    sta TMPC
A5:
    jsr RDOC
    jsr BYTE
    bne A5
A9:
    beq BEQS1

;; Restores the saved state and resumes execution, optionally at a supplied address.
MGO:
    jsr BASIN
    cmp #CR
    beq G1
    cmp #' '
    bne ERRS1
    jsr RDOA
    bcc G1
    jsr PUTP
G1:
    ldx SP
    txs
    sei
    lda INVH
    sta CINV+1
    lda INVL
    sta CINV
    lda PCH
    pha
    lda PCL
    pha
    lda FLGS
    pha
    lda ACC
    ldx XR
    ldy YR
    rti

;; Restores the saved stack pointer and returns to BASIC's warm start.
EXIT:
    ldx SP
    txs
    jmp READY
ERRL:
    jmp ERROPR

;; Parses and performs the monitor LOAD or SAVE command.
LD:
    ldy #$01
    sty FA
    dey
    sty FNLEN
    sty SATUS
    sty VERCK
    lda #>SAVNAM
    sta FNADR+1
    lda #<SAVNAM
    sta FNADR
L1:
    jsr BASIN
    cmp #' '
    beq L1
    cmp #CR
    beq L5
    cmp #'"'
L2:
    bne ERRL
L3:
    jsr BASIN
    cmp #'"'
    beq L8
    cmp #CR
    beq L5
    sta (FNADR),y
    inc FNLEN
    iny
    cpy #16
L4:
    beq ERRL
    bne L3
L5:
    lda SAVX
    cmp #6
L6:
    bne L2
    jsr LD15
    jsr TWAIT
    lda SATUS
    and #SPERR
L7:
    bne L6
    jmp STRT
L8:
    jsr BASIN
    cmp #CR
    beq L5
    cmp #','
L9:
    bne L7
    jsr RDOB
    and #$0F
L10:
    beq L4
    cmp #3
L11:
    beq L10
    sta FA
    jsr BASIN
    cmp #CR
    beq L5
    cmp #','
L12:
    bne L9
    jsr RDOA
    jsr T2T2
    jsr BASIN
    cmp #','
L13:
    bne L12
    jsr RDOA
    lda TMP0
    sta EAL
    lda TMP0+1
    sta EAH
    jsr T2T2
L20:
    jsr BASIN
    cmp #' '
    beq L20
    cmp #CR
L14:
    bne L13
    lda SAVX
    cmp #7
    bne L14
    jsr SV5
    jmp STRT

;; Prints the two-byte monitor address in <TMP0> in hexadecimal.
WROA:
    ldx #$01
WROA1:
    lda TMP0-1,x
    pha
    lda TMP0,x
    jsr WROB
    pla
;; Prints A as two hexadecimal digits.
WROB:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr ASCII
    tax
    pla
    and #$0F
    jsr ASCII
;; Prints the characters in X and A, in that order.
WRTWO:
    pha
    txa
    jsr BSOUT
    pla
    jmp BSOUT

;; Converts a hexadecimal nibble in A to its printable character.
ASCII:
    clc
    adc #$F6
    bcc ASC1
    adc #$06
ASC1:
    adc #$3A
    rts

;; Exchanges the two monitor address words <TMP0> and <TMP2>.
T2T2:
    ldx #$02
T2T21:
    lda TMP0-1,x
    pha
    lda TMP2-1,x
    sta TMP0-1,x
    pla
    sta TMP2-1,x
    dex
    bne T2T21
    rts

;; Reads two hexadecimal bytes into <TMP0>, returning the second byte's carry.
RDOA:
    jsr RDOB
    bcc RDOA2
    sta TMP0+1
RDOA2:
    jsr RDOB
    bcc RDEXIT
    sta TMP0
RDEXIT:
    rts

;; Reads a hexadecimal byte, returning carry clear for a blank field.
RDOB:
    lda #$00
    sta BAD
    jsr RDOC
RDOB1:
    cmp #' '
    bne RDOB2
    jsr RDOC
    cmp #' '
    bne RDOB3
    clc
    rts
RDOB2:
    jsr HEXIT
    asl a
    asl a
    asl a
    asl a
    sta BAD
    jsr RDOC
RDOB3:
    jsr HEXIT
    ora BAD
    sec
    rts

;; Converts a monitor hexadecimal character to a nibble.
HEXIT:
    cmp #$3A
    php
    and #$0F
    plp
    bcc HEX09
    adc #$08
HEX09:
    rts

;; Reads a monitor character, abandoning the current command on carriage return.
RDOC:
    jsr BASIN
    cmp #CR
    bne HEX09
    pla
    pla
    jmp STRT

;; Prints the monitor error prompt and restarts the command loop.
ERROPR:
    lda #'?'
    jsr BSOUT
    jmp STRT
.endmacro
