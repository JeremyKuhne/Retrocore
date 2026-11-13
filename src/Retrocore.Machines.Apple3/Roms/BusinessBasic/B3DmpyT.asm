; B3DMPYT: the TEN and HEX$ functions, which turn hexadecimal text into a number and back, and the SWAP statement,
; which exchanges two variables' values.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; TEN and HEX$
; ---------------------------------------------------------------------------------------------------------------------

;; The TEN function: the value of a string of hexadecimal digits, as a 16-bit signed integer.
;;
;; Only the string's last four characters count, right-aligned over zeros, so TEN("12345") is $2345 and TEN("") is 0.
;; Letters may be either case. The value is signed: TEN("FFFF") is -1.
;; In: FACMO = the string's temporary descriptor
;; Out: FAC = the value, VALTYP = 0
;; Errors: ERRFC = a character in the last four that is not a hexadecimal digit
;; See: <HEXS>, <DNNIB>, <GIVAYF>
DECER:
    jsr LEN1                                ; Y = the length; VALTYP = 0
    lda #0
    sta FACMO
    sta FACLO
    ldx #4
    lda #$30                                ; '0'

;; Fills the four-character work area at <RES> with zeros.
STARTAT0:
    sta RES-1,X
    dex
    bne STARTAT0
    ldx #4

;; Copies up to four characters from the string's end into <RES>, right-aligned.
PUTINUM:
    tya
    beq GOTANUM
    dey
    lda (INDEX1),Y
    sta RES-1,X
    dex
    bne PUTINUM

;; Converts the four characters at <RES> into <FACMO> (the high byte) and <FACLO>, two digits a byte.
GOTANUM:
    ldy #4
    ldx #2

;; Converts two characters, low digit first, into one byte of the result.
GETAHEX:
    lda RES-1,Y
    jsr DNNIB                               ; the low digit
    ora FACMO-1,X
    sta FACMO-1,X
    lda RES-1,Y
    jsr DNNIB                               ; the high digit
    asl
    asl
    asl
    asl
    ora FACMO-1,X
    sta FACMO-1,X
    dex
    bne GETAHEX
    lda FACMO
    ldy FACLO
    jsr GIVAYF
    jmp LEN0                                ; free the string

;; Turns one hexadecimal character into its value, 0 to 15, stepping Y back first.
;; In: A = the character, Y = one past its index
;; Out: A = the value, Y = Y - 1
;; Errors: ERRFC = not a hexadecimal digit
DNNIB:
    dey
    cmp #'Z'+1
    bcc *+4
    sbc #$20                                ; lower case to upper
    sec
    sbc #'0'
    bcc QNERR
    cmp #10
    bcc DECDN
    sbc #7                                  ; 'A' to 10
    cmp #$10
    bcs QNERR
    cmp #10                                 ; between '9' and 'A'
    bcc QNERR

;; An RTS for <DNNIB>'s digits.
DECDN:
    rts

;; The HEX$ function: a 16-bit number as four hexadecimal digits.
;; In: FAC = the number, which must be below 65536 in size
;; Out: FAC = a temporary string of four digits, upper case
;; Errors: ERRFC = the number is too large
;; See: <DECER>, <DONIB>, <GETADR>
HEXS:
    jsr GETADR                              ; the number into FACMO and FACLO
    lda #4
    jsr STRSPA
    ldy #3                                  ; the last digit first
    ldx #2                                  ; FACLO first, then FACMO

;; Writes one byte of the number as two digits, right to left.
MAKHEX:
    lda FACMO-1,X
    pha
    and #$0F
    jsr DONIB
    sta (DSCTMP+1),Y
    dey
    pla
    lsr
    lsr
    lsr
    lsr
    jsr DONIB
    sta (DSCTMP+1),Y
    dey
    dex
    bne MAKHEX
    jmp PUTNEW

;; Turns a value from 0 to 15 into its hexadecimal digit.
;; In: A = the value
;; Out: A = the digit, `0` to `9` or `A` to `F`
DONIB:
    ora #$30
    cmp #$3A
    bcc GOTNIB
    adc #6                                  ; with the carry, 7: past the characters between '9' and 'A'

;; An RTS for <DONIB>'s decimal digits.
GOTNIB:
    rts

;; Ends the statement with an illegal quantity error.
QNERR:
    ldx #ERRFC
    jmp ERROR

; ---------------------------------------------------------------------------------------------------------------------
; SWAP
; ---------------------------------------------------------------------------------------------------------------------

;; The SWAP statement: exchanges the values of two variables of the same type, simple or array elements.
;;
;; The two values' bytes are exchanged in place. For strings, that exchanges their descriptors, and then the info bytes
;; after each string's text, which point back at its descriptor, must follow: when both strings have text, their info
;; bytes are exchanged too; when only one has, its back pointer is rebuilt by <FIXBAK>. Nothing in string space moves,
;; so SWAP needs no room for a copy.
;; In: TXTPTR = past the SWAP token
;; Out: TXTPTR = the statement's end
;; Errors: ERRTM = the variables' types differ
;; See: <PTRGET>, <FIXBAK>
SWAP:
    jsr PTRGET                              ; the first variable
    pha                                     ; its address and bank
    tya
    pha
    lda VARPNTB
    pha
    lda ISARA                               ; array or simple
    pha
    txa                                     ; its VALTYP
    pha
    lda INTFLG
    pha
    jsr CHKCOM
    jsr PTRGET                              ; the second variable
    pla
    cmp INTFLG
    beq SWAP1

;; Ends the statement with a type mismatch error.
MISERR:
    jmp CHKERR

;; Checks the value types match, then takes the first variable's address back into <INDEX1>.
SWAP1:
    pla
    cmp VALTYP
    bne MISERR
    pla
    sta TEMP                                ; the first variable's array flag
    pla
    sta INDEXB
    pla
    sta INDEX1+1
    pla
    sta INDEX1
    ldy VARNAM                              ; PTRGET leaves the value's size here
    dey

;; Exchanges Y + 1 bytes between (<INDEX1>) and (<VARPNT>).
TRNSFR:
    lda (INDEX1),Y
    tax
    lda (VARPNT),Y
    sta (INDEX1),Y
    txa
    sta (VARPNT),Y
    dey
    bpl TRNSFR
    ldx VALTYP                              ; $FF for a string
    inx
    bne SWPRTS
    iny                                     ; Y = 0: the strings' lengths
    lda (INDEX),Y
    bne ONEISGD
    lda (VARPNT),Y
    beq SWPRTS                              ; both empty: nothing points back
    lda VARPNT                              ; only VARPNT's string has text: keep its descriptor
    pha
    lda VARPNT+1
    pha
    lda VARPNTB
    pha
    lda ISARA                               ; and its array flag
    pha
    jsr TRNS                                ; then put it in INDEX
    jmp MAKNUL

;; The first descriptor's string has text: exchanges info bytes if the second's has too, or else rebuilds the first's
;; back pointer.
ONEISGD:
    lda (VARPNT),Y
    bne OLDSWAP
    lda INDEX                               ; only INDEX's string has text: keep its descriptor
    pha
    lda INDEX+1
    pha
    lda INDEXB
    pha
    lda TEMP                                ; and its array flag
    pha

;; Points the string in <INDEX>'s descriptor back at that descriptor, from the descriptor address and array flag on
;; the stack.
;; See: <FIXBAK>
MAKNUL:
    jsr INCNDX                              ; INDEX to the string's info bytes
    lda INDEX
    sta HIGHDS                              ; where FIXBAK writes them
    lda INDEX+1
    sta HIGHDS+1
    lda INDEXB
    sta HIGHDSB
    pla
    sta ISARA
    pla
    sta FORPNTB
    pla
    sta FORPNT+1                            ; the descriptor
    pla
    sta FORPNT
    jmp FIXBAK

;; Both strings have text: exchanges their three info bytes, so each points back at its new descriptor.
OLDSWAP:
    jsr INCNDX                              ; INDEX to the first string's info bytes
    jsr TRNS                                ; and over to VARPNT
    jsr INCNDX                              ; INDEX to the second string's
    ldy #INFOSIZ-1
    sty VALTYP                              ; anything but $FF, so TRNSFR stops after these
    bne TRNSFR                              ; always

;; An RTS for <SWAP>.
SWPRTS:
    rts

;; Exchanges the pointers <INDEX> and <VARPNT>, banks included.
;; Uses: A, X, Y
TRNS:
    ldx #1
    lda INDEX,X
    ldy VARPNT,X
    sty INDEX,X
    sta VARPNT,X
    dex
    bpl *-9
    lda INDEXB
    ldy VARPNTB
    sty INDEXB
    sta VARPNTB
    rts

;; Points <INDEX> past a string's text, at its info bytes, from the descriptor it points to.
;; In: INDEX = the descriptor
;; Out: INDEX, INDEXB = the info bytes
;; See: <NOTNOW>
INCNDX:
    jsr NOTNOW                              ; INDEX to the text; A = the length
    clc
    adc INDEX
    sta INDEX
    bcc INCNDRTS
    inc INDEX+1
    lda INDEX+1
    cmp #MAXPG                              ; past the bank's window: on to the next bank
    bcc INCNDRTS
    sbc #MAXPG-MINPG
    inc INDEXB
    sta INDEX+1

;; An RTS for <INCNDX>.
INCNDRTS:
    rts
