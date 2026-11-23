;; MICROSOFT 6502 BASIC: STRING FUNCTIONS AND BYTE CONVERSION
;;
;; These entries use the platform's string allocator and temporary-descriptor release routines.
;; The switches separately select argument checking, the slice preamble's return sequence, the shared
;; LEN/ASC jump, and the instruction used to put a zero terminator after a VAL argument.

;; Emits CHR$, slicing, LEN, ASC, byte conversion and VAL through <VALRTS>.
;; Parameters: rejectZeroSlices = 1 to reject zero LEFT$/RIGHT$ counts in <PREAM>, 0 to reject only MID$ start zero,
;;   indirectReturn = 1 to return from <PREAM> through the writable jump operand, 0 to restore the stack return,
;;   sharedLenJump = 1 for <ASC> to use LENFLT, 0 for <ASC> to jump directly to <SNGFLT>,
;;   zeroTermViaY = 1 to use TYA for <VAL>'s terminator, 0 to load zero immediately
.macro STRING_FUNCTIONS rejectZeroSlices, indirectReturn, sharedLenJump, zeroTermViaY
    .assert rejectZeroSlices = 0 || rejectZeroSlices = 1, "rejectZeroSlices must be 0 or 1."
    .assert indirectReturn = 0 || indirectReturn = 1, "indirectReturn must be 0 or 1."
    .assert sharedLenJump = 0 || sharedLenJump = 1, "sharedLenJump must be 0 or 1."
    .assert zeroTermViaY = 0 || zeroTermViaY = 1, "zeroTermViaY must be 0 or 1."

;; Returns CHR$(n), a one-byte string containing the value of n.
;;
;; In PET BASIC 4, Commodore's 1979 source calls it `CHRD` (code16). In PET BASIC 1 and 2, the
;; Hoffmann-Vetter reconstructions call it `CHRD` (code16).
;;
;; Errors: ILLEGAL QUANTITY if the argument cannot be converted to a byte
CHR:
    jsr CONINT
    txa
    pha
    lda #$01
    jsr STRSPA
    pla
    ldy #$00
    sta (DSCTMP+1),y
    pla
    pla

RLZRET:
    jmp PUTNEW

;; Returns the leftmost requested characters, or the whole string if the count exceeds its length.
;;
;; In PET BASIC 4, Commodore's 1979 source calls it `LEFTD` (code16). In PET BASIC 1 and 2, the
;; Hoffmann-Vetter reconstructions call it `LEFTD` (code16).
;;
;; Errors: ILLEGAL QUANTITY for a zero count when rejectZeroSlices is selected
LEFT:
    jsr PREAM
    cmp (DSCPNT),y
    tya

RLEFT:
    bcc RLEFT1
    lda (DSCPNT),y
    tax
    tya

RLEFT1:
    pha

RLEFT2:
    txa

RLEFT3:
    pha
    jsr STRSPA
    lda DSCPNT
    ldy DSCPNT+1
    jsr FRETMP
    pla
    tay
    pla
    clc
    adc INDEX
    sta INDEX
    bcc PULMOR
    inc INDEX+1

PULMOR:
    tya
    jsr MOVDO
    jmp PUTNEW

;; Returns the rightmost requested characters, or the whole string if the count exceeds its length.
;;
;; In PET BASIC 4, Commodore's 1979 source calls it `RIGHTD` (code16). In PET BASIC 1 and 2, the
;; Hoffmann-Vetter reconstructions call it `RIGHTD` (code16).
;;
;; Errors: ILLEGAL QUANTITY for a zero count when rejectZeroSlices is selected
RIGHT:
    jsr PREAM
    clc
    sbc (DSCPNT),y
    eor #$FF
    jmp RLEFT

;; Returns MID$(string, start [, length]), with a one-based start and an optional length.
;;
;; A start beyond the end produces an empty string; a length extending past the end is shortened.
;;
;; In PET BASIC 4, Commodore's 1979 source calls it `MIDD` (code16). In PET BASIC 1 and 2, the
;; Hoffmann-Vetter reconstructions call it `MIDD` (code16).
;;
;; Errors: ILLEGAL QUANTITY for a zero start
MID:
    lda #$FF
    sta FACLO
    jsr CHRGOT
    cmp #$29
    beq MID2
    jsr CHKCOM
    jsr GETBYT

MID2:
    jsr PREAM
.if .not rejectZeroSlices
.if indirectReturn
    txa
.endif
    beq GOFUC
.endif
    dex
    txa
    pha
    clc
    ldx #$00
    sbc (DSCPNT),y
    bcs RLEFT2
    eor #$FF
    cmp FACLO
    bcc RLEFT3
    lda FACLO
    bcs RLEFT3

;; Checks the closing parenthesis and retrieves the stacked string descriptor and byte argument.
;;
;; The dispatcher's return address is discarded. The indirect return increments only the saved low byte,
;; so its continuation wraps within the same page when that byte was $FF. The stack return carries normally.
;; The stack holds the preamble return, dispatcher return, byte argument, and descriptor low and high bytes.
;; The stack return sets zero from the argument; the indirect return sets it from the incremented return byte.
;; Out: A = byte argument, X = byte argument, Y = 0, DSCPNT = descriptor address
;; Errors: ILLEGAL QUANTITY for a zero byte argument when rejectZeroSlices is selected
PREAM:
    jsr CHKCLS
    pla
.if indirectReturn
    sta JMPER+1
    pla
    sta JMPER+2
.else
    tay
    pla
    sta JMPER+1
.endif
    pla
    pla
    pla
    tax
    pla
    sta DSCPNT
    pla
    sta DSCPNT+1
.if .not indirectReturn
    lda JMPER+1
    pha
    tya
    pha
.endif
    ldy #$00
    txa
.if rejectZeroSlices
    beq GOFUC
.endif
.if indirectReturn
    inc JMPER+1
    jmp (JMPER+1)
.else
    rts
.endif

;; Returns the length of a string in <FAC>.
LEN:
    jsr LEN1
.if sharedLenJump
LENFLT:
.endif
    jmp SNGFLT

;; Checks and releases a string, returning its length and character address for string functions.
;; Out: A = length, Y = length, INDEX = character address, VALTYP = numeric
LEN1:
    jsr FRESTR
    ldx #$00
    stx VALTYP
    tay
    rts

;; Returns the first character's byte value in <FAC>.
;; Errors: ILLEGAL QUANTITY for an empty string
ASC:
    jsr LEN1
    beq GOFUC
    ldy #$00
    lda (INDEX),y
    tay
.if sharedLenJump
    jmp LENFLT
.else
    jmp SNGFLT
.endif

GOFUC:
    jmp FCERR

;; Advances past the current character and reads a byte-valued numeric expression.
GTBYTC:
    jsr CHRGET

;; Reads a byte-valued numeric expression.
;; Out: X = value, TXTPTR = terminating character
GETBYT:
    jsr FRMNUM

;; Converts <FAC> to a nonnegative byte and refreshes the current text character.
;; Out: X = value
;; Errors: ILLEGAL QUANTITY if the value is outside the byte range
CONINT:
    jsr POSINT
    ldx FACMO
    bne GOFUC
    ldx FACLO

CHRGO2:
    jmp CHRGOT

;; Converts the numeric prefix of a string to <FAC>; an empty string yields zero.
;;
;; The byte immediately after the counted characters must be writable. It is saved and replaced with zero for
;; <FIN>; on success, that byte and the caller's <TXTPTR> are restored. An error from <FIN> bypasses restoration.
VAL:
    jsr LEN1
    bne *+5
    jmp ZEROFC
    ldx TXTPTR
    ldy TXTPTR+1
    stx STRNG2
    sty STRNG2+1
    ldx INDEX
    stx TXTPTR
    clc
    adc INDEX
    sta INDEX2
    ldx INDEX+1
    stx TXTPTR+1
    bcc VAL2
    inx

VAL2:
    stx INDEX2+1
    ldy #$00
    lda (INDEX2),y
    pha
.if zeroTermViaY
    tya
.else
    lda #$00
.endif
    sta (INDEX2),y
    jsr CHRGOT
    jsr FIN
    pla
    ldy #$00
    sta (INDEX2),y

;; Restores the text pointer saved in <STRNG2>.
ST2TXT:
    ldx STRNG2
    ldy STRNG2+1
    stx TXTPTR
    sty TXTPTR+1

VALRTS:
    rts
.endmacro
