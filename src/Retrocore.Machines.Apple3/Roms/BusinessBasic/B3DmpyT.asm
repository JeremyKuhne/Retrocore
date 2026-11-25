; retrocore: style=strict
;; Business BASIC: `TEN`, `HEX$` and `SWAP`
;;
;; The `TEN` and `HEX$` functions, which turn hexadecimal text into a number and back, and the `SWAP` statement, which
;; exchanges two variables' values.
;;
;; Apple's listing calls this file B3DMPYT. Part of BusinessBasic.asm.

;; Hexadecimal digits, for `TEN` and `HEX$`.
.scope Hexadecimal

;; The digits `TEN` reads and `HEX$` writes: four, for 16 bits.
DIGITS = 4

;; From a letter to the same letter in upper case.
CASE_OFFSET = 'a' - 'A'

;; What a digit's value is past `9`'s when it is `A` to `F`: the characters between `9` and `A`.
LETTER_OFFSET = 'A' - '9' - 1

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; `TEN` and `HEX$`
; ---------------------------------------------------------------------------------------------------------------------

; `TEN`.
.scope Functions continued

;; The `TEN` function: the value of a string of hexadecimal digits, as a 16-bit signed integer.
;;
;; Only the string's last four characters count, right-aligned over zeros, so `TEN("12345")` is $2345 and `TEN("")`
;; is 0. Letters may be either case. The value is signed: `TEN("FFFF")` is -1.
;; In: FACMO = the string's temporary descriptor
;; Out: FAC = the value, VALTYP = 0
;; Errors: ERRFC = a character in the last four that is not a hexadecimal digit
;; See: <Functions::Hex>, <Hexadecimal::DigitValue>, <GIVAYF>
;; Also: DECER (BB13)
.proc Ten
    jsr LEN1                                ; Y = the length; VALTYP = 0
    lda #0
    sta FACMO
    sta FACLO
    ldx #Hexadecimal::DIGITS
    lda #'0'

;; Fills the four-character work area at <RES> with zeros.
;; Also: STARTAT0 (BB13)
FillZeros:
    sta RES-1,X
    dex
    bne FillZeros
    ldx #Hexadecimal::DIGITS

;; Copies up to four characters from the string's end into <RES>, right-aligned.
;; Also: PUTINUM (BB13)
CopyCharacters:
    tya
    beq Convert
    dey
    lda (INDEX1),Y
    sta RES-1,X
    dex
    bne CopyCharacters

;; Converts the four characters at <RES> into <FACMO> (the high byte) and <FACLO>, two digits a byte.
;; Also: GOTANUM (BB13)
Convert:
    ldy #Hexadecimal::DIGITS
    ldx #2

;; Converts two characters, low digit first, into one byte of the result.
;; Also: GETAHEX (BB13)
ConvertByte:
    lda RES-1,Y
    jsr Hexadecimal::DigitValue             ; the low digit
    ora FACMO-1,X
    sta FACMO-1,X
    lda RES-1,Y
    jsr Hexadecimal::DigitValue             ; the high digit
    asl
    asl
    asl
    asl
    ora FACMO-1,X
    sta FACMO-1,X
    dex
    bne ConvertByte
    lda FACMO
    ldy FACLO
    jsr GIVAYF
    jmp LEN0                                ; free the string
.endproc

.endscope

; A digit's value.
.scope Hexadecimal continued

;; Turns one hexadecimal character into its value, 0 to 15, stepping Y back first.
;; In: A = the character, Y = one past its index
;; Out: A = the value, Y = Y - 1
;; Errors: ERRFC = not a hexadecimal digit
;; Keeps: X
;; Also: DNNIB (BB13)
.proc DigitValue
    dey
    cmp #'Z'+1
    bcc *+4
    sbc #CASE_OFFSET                        ; lower case to upper
    sec
    sbc #'0'
    bcc IllegalQuantityError
    cmp #10
    bcc Done
    sbc #LETTER_OFFSET                      ; 'A' to 10
    cmp #$10
    bcs IllegalQuantityError
    cmp #10                                 ; between '9' and 'A'
    bcc IllegalQuantityError

;; Returns the digit's value.
;; Also: DECDN (BB13)
Done:
    rts
.endproc

.endscope

; `HEX$`.
.scope Functions continued

;; The `HEX$` function: a 16-bit number as four hexadecimal digits.
;;
;; A negative number gives its two's complement: `HEX$(-1)` is "FFFF".
;; In: FAC = the number, which must be below 65536 in size
;; Out: FAC = a temporary string of four digits, upper case
;; Errors: ERRFC = the number is too large
;; See: <Functions::Ten>, <Hexadecimal::Digit>, <GETADR>
;; Also: HEXS (BB13)
.proc Hex
    jsr GETADR                              ; the number into FACMO and FACLO
    lda #Hexadecimal::DIGITS
    jsr STRSPA
    ldy #Hexadecimal::DIGITS - 1            ; the last digit first
    ldx #2                                  ; FACLO first, then FACMO

;; Writes one byte of the number as two digits, right to left.
;; Also: MAKHEX (BB13)
WriteByte:
    lda FACMO-1,X
    pha
    and #$0F
    jsr Hexadecimal::Digit
    sta (DSCTMP+1),Y
    dey
    pla
    lsr
    lsr
    lsr
    lsr
    jsr Hexadecimal::Digit
    sta (DSCTMP+1),Y
    dey
    dex
    bne WriteByte
    jmp PUTNEW
.endproc

.endscope

; A value's digit, and the error.
.scope Hexadecimal continued

;; Turns a value from 0 to 15 into its hexadecimal digit.
;; In: A = the value
;; Out: A = the digit, `0` to `9` or `A` to `F`
;; Keeps: X, Y
;; Also: DONIB (BB13)
.proc Digit
    ora #'0'
    cmp #'9'+1
    bcc Done
    adc #LETTER_OFFSET - 1                  ; with the carry, LETTER_OFFSET: past the characters between '9' and 'A'

;; Returns the digit.
;; Also: GOTNIB (BB13)
Done:
    rts
.endproc

;; Ends the statement with an illegal quantity error.
;; Also: QNERR (BB13)
.proc IllegalQuantityError
    ldx #ERRFC
    jmp ERROR
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; `SWAP`
; ---------------------------------------------------------------------------------------------------------------------

; `SWAP`.
.scope Statements continued

;; The `SWAP` statement: exchanges the values of two variables of the same type, simple or array elements.
;;
;; The two values' bytes are exchanged in place. For strings, that exchanges their descriptors, and then the info bytes
;; after each string's text, which point back at its descriptor, must follow: when both strings have text, their info
;; bytes are exchanged too; when only one has, its back pointer is rebuilt by <FIXBAK>. Nothing in string space moves,
;; so `SWAP` needs no room for a copy. After two strings with text, <VALTYP> is left at <INFOSIZ> - 1 rather than $FF.
;; In: TXTPTR = past the `SWAP` token
;; Out: TXTPTR = the statement's end
;; Errors: ERRTM = the variables' types differ
;; Entry:
;;   ToTypeMismatch = ends the statement with a type mismatch error; `IF` jumps here for a string condition
;; See: <PTRGET>, <FIXBAK>
;; Also: SWAP (BB13)
.proc Swap
    jsr PTRGET                              ; the first variable
    pha                                     ; its address and bank
    tya
    pha
    lda VARPNTB
    pha
    lda ISARA                               ; array or simple
    pha
    txa                                     ; its VALTYP, as PTRGET leaves X
    pha
    lda INTFLG
    pha
    jsr CHKCOM
    jsr PTRGET                              ; the second variable
    pla
    cmp INTFLG
    beq SameType

;; Ends the statement with a type mismatch error (<CHKERR>).
;; Also: MISERR (BB13)
ToTypeMismatch:
    jmp CHKERR

;; Checks the value types match, then takes the first variable's address back into <INDEX1>.
;; Also: SWAP1 (BB13)
SameType:
    pla
    cmp VALTYP
    bne ToTypeMismatch
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
;; Also: TRNSFR (BB13)
Exchange:
    lda (INDEX1),Y
    tax
    lda (VARPNT),Y
    sta (INDEX1),Y
    txa
    sta (VARPNT),Y
    dey
    bpl Exchange
    ldx VALTYP                              ; $FF for a string
    inx
    bne Done
    iny                                     ; Y = 0: the strings' lengths
    lda (INDEX),Y
    bne FirstHasText
    lda (VARPNT),Y
    beq Done                                ; both empty: nothing points back
    lda VARPNT                              ; only VARPNT's string has text: keep its descriptor
    pha
    lda VARPNT+1
    pha
    lda VARPNTB
    pha
    lda ISARA                               ; and its array flag
    pha
    jsr Strings::SwapPointers               ; then put it in INDEX
    jmp RebuildBackPointer

;; The first descriptor's string has text: exchanges info bytes if the second's has too, or else rebuilds the first's
;; back pointer.
;; Also: ONEISGD (BB13)
FirstHasText:
    lda (VARPNT),Y
    bne BothHaveText
    lda INDEX                               ; only INDEX's string has text: keep its descriptor
    pha
    lda INDEX+1
    pha
    lda INDEXB
    pha
    lda TEMP                                ; and its array flag
    pha

;; Points the string in <INDEX>'s descriptor back at that descriptor, from the descriptor address and array flag on
;; the stack (<FIXBAK>).
;; Also: MAKNUL (BB13)
RebuildBackPointer:
    jsr Strings::PointAtInfoBytes           ; INDEX to the string's info bytes
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
;; Also: OLDSWAP (BB13)
BothHaveText:
    jsr Strings::PointAtInfoBytes           ; INDEX to the first string's info bytes
    jsr Strings::SwapPointers               ; and over to VARPNT
    jsr Strings::PointAtInfoBytes           ; INDEX to the second string's
    ldy #INFOSIZ-1
    sty VALTYP                              ; anything but $FF, so Exchange stops after these
    bne Exchange                            ; always

;; Returns.
;; Also: SWPRTS (BB13)
Done:
    rts
.endproc

.endscope

; `SWAP`'s pointer helpers.
.scope Strings continued

;; Exchanges the pointers <INDEX> and <VARPNT>, banks included, for `SWAP`.
;; Uses: A, X, Y
;; Also: TRNS (BB13)
.proc SwapPointers
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
.endproc

;; Points <INDEX> past a string's text, at its info bytes, from the descriptor it points to.
;; In: INDEX = the descriptor
;; Out: INDEX, INDEXB = the info bytes
;; See: <NOTNOW>
;; Also: INCNDX (BB13)
.proc PointAtInfoBytes
    jsr NOTNOW                              ; INDEX to the text; A = the length
    clc
    adc INDEX
    sta INDEX
    bcc Done
    inc INDEX+1
    lda INDEX+1
    cmp #MAXPG                              ; past the bank's window: on to the next bank
    bcc Done
    sbc #MAXPG-MINPG
    inc INDEXB
    sta INDEX+1

;; Returns.
;; Also: INCNDRTS (BB13)
Done:
    rts
.endproc

.endscope
