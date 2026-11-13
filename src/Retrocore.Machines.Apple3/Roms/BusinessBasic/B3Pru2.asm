; B3PRU2: PRINT USING's second part: the scanner that takes each format character from the image, the tables of
; format characters, and the editor that writes a number into its field.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Format characters
; ---------------------------------------------------------------------------------------------------------------------

;; Takes the next format character from the image, with its repeat count, and returns its type from <STYPTBL>.
;;
;; A count may come before the character (`3#`), and a run of the same character adds to it (`3##` is 4). A quote
;; starts a literal and stops the scan at once. A comma before the character is skipped; at the end of the image GETDL
;; drops its caller's return address and returns to the caller's caller.
;; In: SPCNDX = the index of the last character of the image used, SPCPTR = the image, SPCLEN = its length
;; Out: A = the type, negative = set for a literal or string field, Y = the character's index in <DLMTBL>,
;;   DELIM = the character, REP = the count
;; Errors: illegal quantity for a count of 0 or over 255; a syntax error for a character that isn't a format
;;   character, or a run that takes the count past 255
;; See: <IMSYNCK>, <UGETCHR>
UGETDL:
    ldy #0
    sty DELIM
    sty REP
UCOMA:
    jsr UGETCHR
    bne UGOT1
    cmp #','
    beq UCOMA
    pla                                     ; the end of the image: return from the caller
    pla
    rts

;; Takes a digit of the count, or goes on to a format character.
;; In: A = the character, carry = clear for a digit
UGOT1:
    bcs UDLCHR
    ldx DELIM
    beq UG1STD                              ; nothing yet
    cpx #'9'                                ; only digits so far?
    bne UGVAL                               ; no: a digit after a format character ends it

;; Adds a digit to the count: REP times 10, plus the digit.
UG1STD:
    ldy REP
    cpy #26                                 ; would REP times 10 pass 255?
    bcc *+8                                 ; no: past the error exit

;; Frees the mask and ends the statement with an illegal quantity error.
;; See: <UFRESPC>, <FCERR>
UIQERR:
    jsr UFRESPC
    jmp FCERR
    ldx #'9'
    stx DELIM                               ; marks digits read
    tya
    asl
    asl
    asl
    adc REP
    adc REP                                 ; REP times 10
    sta REP
    ldy SPCNDX
    lda (SPCPTR),Y
    and #$0F                                ; the digit's value
    adc REP
    bcs UIQERR                              ; past 255
    sta REP

;; Takes the next character of the image.
UGNXTC:
    jsr UGETCHR
    beq UGEND                               ; the end of the field
    bne UGOT1

;; Backs up so the character that ended the field is read again by the next call.
UGVAL:
    dec SPCNDX

;; Looks the format character up in <DLMTBL>, in upper case, and returns its type.
UGEND:
    lda DELIM
    cmp #'Z'+1
    bcc *+4
    sbc #$20                                ; lower case to upper
    ldy #DLMCNT-1
UVALOOP:
    cmp a:DLMTBL,Y
    beq UGETND
    dey
    bpl UVALOOP

;; Frees the mask and ends the statement with a syntax error.
;; See: <UFRESPC>, <USNERR>
UGERRX:
    jsr UFRESPC
    jmp USNERR

;; Returns the type of the format character found at Y.
UGETND:
    lda a:STYPTBL,Y
    rts

;; Takes a format character: the first, the one after a count, or another of a run.
;; In: A = the character
UDLCHR:
    ldy DELIM
    beq U1STDL
    cpy #'9'                                ; after a count?
    bne UDLCK
    ldy REP
    beq UIQERR                              ; a count of 0
    bne USETDL

;; Takes the first format character, with a count of 1.
U1STDL:
    ldy #1
    sty REP

;; Records the format character; a quote ends the scan, as a literal follows it.
USETDL:
    sta DELIM
    cmp #'"'
    beq UGEND
    bne UGNXTC

;; Counts another of the same format character, or ends the field at a different one.
UDLCK:
    cmp DELIM
    bne UGVAL
    cmp #'"'
    beq UGERRX
    inc REP
    bne UGNXTC
    beq UGERRX                              ; a run past 255

;; The format characters, in upper case; <STYPTBL> gives each one's type.
DLMTBL:
    .byte $41, $58, $22, $2B, $2D, $26, $24, $2E, $45, $43, $52, $2F, $23, $5A, $2A  ; A X " + - & $ . E C R / # Z *

;; Each format character's type, in <DLMTBL>'s order.
;;
;; The top two bits give the class: 01 a digit, 00 an editing character, 10 a literal, 11 a string. An editing
;; character's other bits say which it is: bit 5 a sign (with bit 0 set for `+`), bit 4 `$`, bit 3 `E`, bit 2 the
;; point and bit 1 `*`. A digit's low bits rank its kind: <ZTYP>, <DTYP>, then <CMATYP>.
STYPTBL:
DLMCNT = STYPTBL-DLMTBL                     ;; the number of format characters
    .byte $FF                               ; A: a string, from the left
    .byte $80                               ; X: a space
    .byte $80                               ; ": a literal, to the next quote
    .byte $21                               ; +: a sign, + or -
    .byte $20                               ; -: a sign, a space or -
    .byte CMATYP                            ; &: a digit, with commas
    .byte $10                               ; $
    .byte $04                               ; .: the point
    .byte $08                               ; E: the exponent
    .byte $FF                               ; C: a string, centered
    .byte $FF                               ; R: a string, to the right
    .byte $80                               ; /: a RETURN and a line feed
    .byte DTYP                              ; #: a digit, space filled
    .byte ZTYP                              ; Z: a digit, zero filled
    .byte $02                               ; *: asterisk fill

;; The fill character for the places before the point, by digit type less <ZTYP>: `0` for Z, a space for #, none
;; for the type between, and a space for &.
FILLTABL:
    .byte "0   "

;; The comma flag, by digit type less <ZTYP>: bit 7 set for &, which puts commas in.
CMATBL:
    .byte 0, 0, 0, $80

; ---------------------------------------------------------------------------------------------------------------------
; Numeric fields
; ---------------------------------------------------------------------------------------------------------------------

;; Unpacks the BCD mantissa in <FACT> into <BCDSTR>, one digit a byte from BCDSTR+2: 20 digits, then a 0.
;;
;; Leading zeros are dropped, each lowering the exponent in <ISARA> by one; ISARA holds the exponent doubled, with the
;; sign in bit 0.
;; Out: A = 0, zero = set, Y = 22
;; Uses: X, HALF
;; See: <LUNPACK>
UUNPACK:
    ldy #2
    ldx #$FF
    stx HALF                                ; the high digit first
    inx
UHLOOP:
    lda FACT,X
    bit HALF
    bpl UPUSELOW
    inc HALF                                ; the low digit next
    lsr
    lsr
    lsr
    lsr
    bpl UPUSEA
UPUSELOW:
    dec HALF                                ; the high digit of the next byte next
    inx
    and #$F
UPUSEA:
    cpy #3
    bcs UGTABYT                             ; past the first digit, zeros count
    cmp #0
    bne UGTABYT
    dec ISARA                               ; a leading zero: the exponent goes down one
    dec ISARA
    bne UHLOOP                              ; always
UGTABYT:
    sta BCDSTR,Y
    iny
    cpy #22
    bne UHLOOP
    lda #0
    sta BCDSTR,Y
    rts

;; Writes a number into its field of the mask, as the image asks, and prints it.
;;
;; The number is in <BCDSTR>, one digit a byte, with its exponent doubled in <FACEXP> and its sign in bit 0. UNUMEDIT
;; makes FACEXP the power of ten of the first digit and adds the SCALE factor in <ISARA>; the result must lie between
;; -99 and 99. The number is rounded at the last place shown, and one too big for its field prints as a field of `!`.
;; A field with an exponent goes on to <UEEEDIT>.
;; In: MASKPT = the mask, MSKNDX = the index of its last byte, and the field as <IMSYNCK> left it: DIGB4DPT, DIGAFDPT,
;;   EMASK, FLTMSK, CMAFILL, TENZNDX, DPTNDX
;; Errors: illegal quantity for an exponent out of range
;; See: <UNUMVAR>, <USENDIT>
UNUMEDIT:
    inc MSKNDX                              ; now the field's length
    lda FACEXP
    cmp #$80                                ; carry = the exponent's sign
    ror
    ror                                     ; the mantissa's sign to bit 7
    sta FACSGN
    rol                                     ; the exponent, signed
    sec
    sbc #1                                  ; the power of the first digit
    clc
    adc ISARA                               ; plus the SCALE factor
    sta FACEXP
    cmp #MINSGN
    bcs UROKNOW
    cmp #MAXSGN+1
    bcc UROKNOW
    jsr UFRESPC
    jmp FCERR
MINSGN = $9D                                ;; the smallest exponent a field takes, -99
MAXSGN = $63                                ;; the largest exponent a field takes, 99

;; Fills in a fixed sign, then edits the field: with an exponent at <UEEEDIT>, otherwise here.
;;
;; With commas, the places before the point are cut to the digits they hold once the commas take their places.
UROKNOW:
    jsr USGNSCN
    ldy #0
    sty CMACTR
    sty DIGCTR
    lda #$08                                ; the E bit
    bit EMASK
    beq *+5
    jmp UEEEDIT
    bit CMAFILL
    bpl UNOCMAS                             ; no commas
    lda DIGB4DPT
    and #3
    cmp #1                                  ; carry = clear for a multiple of 4
    lda DIGB4DPT
    tax
    bcc UNOSBC1
    sbc #1
UNOSBC1:
    lsr
    lsr                                     ; the places the commas take
    sta DIGB4DPT
    txa
    sec
    sbc DIGB4DPT
    sta DIGB4DPT

;; Rounds the number at the last decimal place shown and checks the digits before the point fit.
UNOCMAS:
    lda #<(0-1)
    sec
    sbc DIGAFDPT                            ; the power of ten of the first place dropped
    tax
    jsr UROUNDI
    jsr UEXPLS1
    lda TENEXP
    bit FACEXP
    bmi UDOLEFT                             ; below 1: it fits
    cmp DIGB4DPT
    bcc UDOLEFT

;; Fills the field with `!`, for a number that doesn't fit, and prints it.
UTOOBIG:
    lda #'!'
    ldy MSKNDX
UEXLOOP:
    dey
    bmi UEXDONE
    sta (MASKPT),Y
    bne UEXLOOP                             ; always
UEXDONE:
    jmp USENDIT

;; Writes the digits before the point, right to left from the units place, with a comma every three digits when
;; asked; the units place shows 0 for a number below 1.
UDOLEFT:
    lda DIGB4DPT
    bne *+5
    jmp URIGHTS                             ; no places before the point
    ldx #$FF
    ldy TENZNDX
ULEFTLP:
    inx
    cpx DIGB4DPT
    bcs UDOFLTS                             ; every place is done
    jsr UGET10X
    bpl UDOADIG
    txa
    bne UDOISGN                             ; past the first digit
    lda #'0'                                ; the units place
UDOADIG:
    bit CMAFILL
    bpl USTALFT                             ; no commas
    pha
    lda CMACTR
    cmp #3
    bcc UINCMA
    lda #','
    sta (MASKPT),Y
    dey
    lda #0
    sta CMACTR
UINCMA:
    inc CMACTR
    pla
USTALFT:
    sta (MASKPT),Y
    dey
    bpl ULEFTLP

;; Puts a minus sign before a negative number whose image has no sign, in a spare digit place; with no place for it
;; the number doesn't fit.
UDOISGN:
    lda #$20                                ; the sign bit
    bit EMASK
    bne UDOFLTS                             ; the image has a sign
    bit FACSGN
    bpl UDOFLTS
    tya
    bmi UTOOBIG
    lda (MASKPT),Y
    bne UTOOBIG                             ; not a digit place
    lda #'-'
    sta (MASKPT),Y
    dey

;; Writes the floating `$` and sign before the digits, right to left in the order the image gave them, from the bits
;; of <FLTMSK>: bit 7 `$` after the sign, bit 6 the sign, bit 5 `$` before it.
UDOFLTS:
    lda FLTMSK
    and #$E0
    beq UDOFILL
    asl
    bcc UNODL1
    tax
    lda #'$'
    sta (MASKPT),Y
    dey
    txa
UNODL1:
    asl
    bcc UNOSIGN
    tax
    lda EMASK
    lsr                                     ; carry = set for +
    lda #'-'
    bit FACSGN
    bmi USTORMI
    bcc USKPSI                              ; positive, and no + asked for
    lda #'+'
USTORMI:
    sta (MASKPT),Y
    dey
USKPSI:
    txa
UNOSIGN:
    asl
    bcc UDOFILL
    lda #'$'
    sta (MASKPT),Y
    dey

;; Fills the digit places left before the number with the fill character: a space, `0` or `*`.
UDOFILL:
    tya
    bmi URIGHTS
    lda CMAFILL
    and #$7F                                ; without the comma flag
    tax
UFILLP:
    lda (MASKPT),Y
    bne URIGHTS                             ; not a digit place
    txa
    sta (MASKPT),Y
    dey
    bpl UFILLP

;; Writes the digits after the point: the number's own places, or with an exponent its next digits.
URIGHTS:
    lda DIGAFDPT
    beq UDOEXP
    ldy DPTNDX
    iny
    ldx #0
    txa
    sec
    sbc DIGAFDPT
    sta DIGAFDPT                            ; the power of ten of the last place
URITLOP:
    dex
    cpx DIGAFDPT
    bcc UDOEXP
    lda #8
    bit EMASK
    bne UEXPTYP
    jsr UGET10X
    bpl UDIGRIT
    lda #'0'
    bpl UDIGRIT
UEXPTYP:
    jsr UGETNSD
UDIGRIT:
    sta (MASKPT),Y
    iny
    jmp URITLOP

;; Writes the exponent at the image's first E: an upper-case E, the exponent's sign, and two digits, or one when the
;; image has only three Es; an exponent that needs two digits there doesn't fit.
UDOEXP:
    lda #8
    bit EMASK
    beq USENDIT
    ldy #0
UDOEXP1:
    lda (MASKPT),Y
    and #$DF                                ; upper case
    iny
    cmp #'E'
    bne UDOEXP1
    dey
    sta (MASKPT),Y
    iny
    lda #'+'
    bit FACEXP
    bpl *+4
    lda #'-'
    sta (MASKPT),Y
    iny
    lda TENEXP
    ldx #0
    sec
USBCLP:
    sbc #10
    bcc UGOTHI
    inx                                     ; the tens
    bne USBCLP
UGOTHI:
    adc #10                                 ; the units
    iny
    cpy MSKNDX                              ; room for two digits?
    dey
    bcc UDO1STD
    cpx #0
    beq UDO2NDD
    jmp UTOOBIG
UDO1STD:
    pha
    txa
    ora #$30
    sta (MASKPT),Y
    iny
    pla
UDO2NDD:
    ora #$30
    sta (MASKPT),Y

;; Prints the field: the mask, <MSKNDX> characters, as a string.
;; See: <STRPR3>
USENDIT:
    lda #0
    sta VALTYP
    lda MASKPT
    sta INDEX
    lda MASKPT+1
    sta INDEX+1
    lda FRESPCB                             ; the mask's bank
    sta INDEXB
    ldx MSKNDX
    jmp STRPR3

;; Writes a number into a field with an exponent: `.DDDE+EE` with no places before the point, `D.DDDE+EE` with one,
;; or engineering notation with three (<UENGNOT>).
;;
;; The number is rounded to the places shown. With one place before the point, its digit goes after a fixed sign at
;; the field's start.
;; See: <UNUMEDIT>
UEEEDIT:
    lda DIGB4DPT
    clc
    adc DIGAFDPT
    tax                                     ; the index of the first place dropped
    jsr UROUNDA
    jsr UEXPLS1
    ldx DIGB4DPT
    beq UDOSCI0
    dex
    bne UENGNOT
    ldy #0
    lda (MASKPT),Y
    beq UDOSCI1
    iny                                     ; after the sign

;; Writes <DIGB4DPT> digits, then those after the point.
;; In: Y = the first digit's place
UDOSCI1:
    lda DIGB4DPT
    beq UDOSCI2
    jsr UGETNSD
    sta (MASKPT),Y
    dec DIGB4DPT
    iny
    bne UDOSCI1

;; With no places before the point, the exponent is one higher.
UDOSCI0:
    sec
    jsr UEXPLS1
UDOSCI2:
    jmp URIGHTS

;; Engineering notation: lowers the exponent to a multiple of three, which leaves one to three digits before the
;; point, and puts the floating sign and the fill character in the places left before them.
;;
;; Only one place gets the fill character: the fill loop doesn't step Y, so after filling a place it finds it filled
;; and stops, and any place further left keeps its 0.
UENGNOT:
    lda FACEXP
UMOD3LP:
    bpl UCHKMD3
    clc
    adc #3
    bmi UMOD3LP
UCHKMD3:
    cmp #3
    bcc UGOTMOD
    sbc #3
    bne UMOD3LP
UGOTMOD:
    bit FACEXP                              ; the flags aren't used
    sta DIGB4DPT
    sta EXPADJ
    lda FACEXP
    sec
    sbc EXPADJ
    sta FACEXP
    jsr UABSEXP
    lda #2
    sec
    sbc DIGB4DPT                            ; the places before the digits: 2, 1 or 0
    sta SPCB4DIG
    inc DIGB4DPT                            ; the digits: 1, 2 or 3
    ldy SPCB4DIG
    lda FLTMSK
    beq UDOEFIL
    inc SPCB4DIG                            ; a floating sign takes the place before the digits
    lda EMASK
    lsr                                     ; carry = set for +
    lda #'-'
    bit FACSGN
    bmi USTORM
    bcc UDOEFIL
    lda #'+'
USTORM:
    sta (MASKPT),Y
UDOEFIL:
    dey
    bmi UDODIGS
    lda CMAFILL
    and #$7F
    tax
UDOEFLL:
    lda (MASKPT),Y
    bne UDODIGS
    txa
    sta (MASKPT),Y
    bne UDOEFLL                             ; and the place now reads filled

;; Writes the digits from the place in <SPCB4DIG>.
UDODIGS:
    ldy SPCB4DIG
    jmp UDOSCI1

; ---------------------------------------------------------------------------------------------------------------------
; Digits, signs and rounding
; ---------------------------------------------------------------------------------------------------------------------

;; Returns the number's digit for a power of ten, in ASCII.
;;
;; Indexes up to 21 are read, two past the 20 digits <UUNPACK> unpacks, so the furthest places come from <BCDSTR>'s
;; end mark and the byte after it.
;; In: X = the power of ten
;; Out: A = the digit, `0` past the digits, negative = set (and A no digit) when the power is above the first digit
;; Uses: DIGEXP
;; Keeps: X, Y
;; Entry: UGETITA = takes the digit's index from the first in A
;; See: <UCVTX>, <UGETNSD>
UGET10X:
    jsr UCVTX
    bmi UNODIGT
UGETITA:
    cmp #22
    bcc UUSEIT
    lda #'0'
UNODIGT:
    rts
UUSEIT:
    tax
    lda BCDSTR+2,X
    ora #$30
    ldx DIGEXP
    and #$7F                                ; negative = clear
    rts

;; Returns the number's next digit, counting from the first with <DIGCTR>, in ASCII.
;; Out: A = the digit, or `0` past the digits
;; Uses: DIGCTR, DIGEXP
;; Keeps: X, Y
;; See: <UGET10X>
UGETNSD:
    stx DIGEXP
    lda DIGCTR
    inc DIGCTR
    jmp UGETITA

;; Fills in the image's fixed sign by the number's: a `+` becomes `+` or `-`, a `-` becomes a space or `-`.
;; In: FACSGN = bit 7 set for a negative number, EMASK = bit 5 set for a fixed sign, MSKNDX = the field's length,
;;   MASKPT = the mask
;; Uses: A, Y
USGNSCN:
    lda #$20
    bit EMASK
    beq USGNRTS                             ; no fixed sign
    ldy #$FF
USIGNLP:
    iny
    cpy MSKNDX
    beq USGNRTS
    lda (MASKPT),Y
    cmp #'-'
    beq UDOMSIN
    cmp #'+'
    bne USIGNLP
    lda #'+'
    bne USTASIN
UDOMSIN:
    lda #' '
USTASIN:
    bit FACSGN
    bpl *+4
    lda #'-'
    sta (MASKPT),Y
USGNRTS:
    rts

;; Adds one to the exponent in <FACEXP> when carry is set, then puts its size in <TENEXP>.
;; In: carry = set to add one
;; Out: TENEXP = the exponent without its sign
;; Uses: A, REP
;; Keeps: X, Y
;; Entry: UABSEXP = only sets TENEXP
UEXPLS1:
    lda #1
    bcc UABSEXP
    sta REP
    lda FACEXP
    clc
    adc REP
    sta FACEXP
UABSEXP:
    lda FACEXP
    bpl USTATEN
    eor #$FF
    clc
    adc #1
USTATEN:
    sta TENEXP
    rts

;; Turns a power of ten into its digit's index in <BCDSTR>, counting from BCDSTR+2.
;; In: X = the power of ten
;; Out: A = the index, negative = set when the power is above the first digit, DIGEXP = X
;; Keeps: X, Y
UCVTX:
    stx DIGEXP
    lda FACEXP
    sec
    sbc DIGEXP
    rts

;; Rounds the number at a power of ten: if that place's digit is 5 or more, it becomes 0 and one is carried into the
;; places before it.
;;
;; When every place before it is 9, the number becomes 1 followed by zeros and the exponent must go up one.
;; In: X = the power of ten of the first place dropped
;; Out: carry = set when the exponent must go up one
;; Uses: A, X, DIGEXP
;; Entry: UROUNDA = takes the place's index in X
;; See: <UEXPLS1>
UROUNDI:
    jsr UCVTX
    bmi UROUNDX                             ; above the first digit
    cmp #22
    bcs UROUNDX                             ; past the digits
    tax
UROUNDA:
    lda BCDSTR+2,X
    cmp #$05
    bcc UROUNDX+1                           ; below 5: carry clear, to the RTS
    lda #9                                  ; 9 plus the carry makes this place 0
    bcs UROUNDB
UROUNDL:
    dex
    bmi UROUNDO                             ; carried out of the first digit
    lda BCDSTR+2,X
UROUNDB:
    sed
    adc #0                                  ; plus the carry, in decimal
    cld
    cmp #$10                                ; carry = set for a carry on
    and #$0F
    sta BCDSTR+2,X
    bcs UROUNDL

;; Returns with carry clear: the exponent stands.
UROUNDX:
    clc
    rts

;; Makes the number 1 after a carry out of its first digit, the other places now 0, and returns with carry set.
UROUNDO:
    lda #1
    sta BCDSTR+2
    rts
