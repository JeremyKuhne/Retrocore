; B3PRU1: PRINT USING's first half: finding the image, the loop over the expressions, printing literals and strings,
; and the scanner that checks each spec and builds a number's edit mask.
;
; The image comes from a string literal, a string variable or an IMAGE statement, and is a list of specs separated by
; commas:
;
; - A literal: text in quotes, X for a space or / for a new line.
; - A string field: A to left-justify, C to center or R to right-justify, as wide as its count of letters.
; - A number field: digit positions, # (leading zeros as spaces), Z (leading zeros printed) or & (spaces, with
;   commas); ** for asterisk fill; $ or a floating $$; a sign, + or -, before or after the digits, or a floating ++
;   or --; a decimal point; and EEE or EEEE for an exponent.
;
; A count before a character repeats it, so 5# is #####. The scanner keeps its state in the FAC's bytes, which are
; free while it runs; the expression's value is kept as BCD digits in BCDSTR for the editor, UNUMEDIT, in B3Pru2.
;
; Names follow Apple's Business BASIC 1.3 listing.

DELIM = FAC+1                               ;; the spec character UGETDL found
REP = FAC+2                                 ;; its count: the repeat count, or the run of the same character
DIGB4DPT = FAC+24                           ;; the count of digit positions before the decimal point
DIGAFDPT = FAC+25                           ;; the count of digit positions after it
SAVLEN = FAC+6                              ;; the length of a literal, or of the string to print
SPECTYP = FAC+7                             ;; the spec's type: 0 a number, $FF a string, $80 a literal, 1 none
DIGCTR = FAC+8                              ;; the digit positions counted but not yet put in the mask
DIGEXP = FAC+9                              ;; the exponent of the digit the editor wants
USVSTRL = FAC+9                             ;; the string's length, kept while its spec is found
DPTNDX = FAC+10                             ;; the decimal point's index in the mask, $FF for none
NMASK = FAC+11                              ;; the digit class so far: <ZTYP>, <DTYP> or <CMATYP>, 0 for none
EXPADJ = FAC+11                             ;; the editor's adjustment to the exponent
EMASK = FAC+12                              ;; its parts: $80 digits, $20 a sign ($01 +), $10 $, $08 E, $04 a point
FLTMSK = FAC+13                             ;; the floating symbols: $10 **, $20 $, $40 a sign, $80 a $ after the sign
LITRLCH = FAC+14                            ;; the text X or / prints: a space, or a return and a line feed
SPCB4DIG = FAC+14                           ;; the editor's index of the place before the digits
MASKPT = FRESPC                             ;; the edit mask, <MSKLEN> bytes of string space from <GETSPA>
VSPEC = FAC+29                              ;; $FF once a spec has taken a value, so the image may start over
ENDFLG = VSPEC                              ;; how the statement ends: 0 with a new line, a semicolon without
MSKNDX = FAC+16                             ;; the index of the mask's last byte, $FF while it is empty
SPCPTR = FAC+17                             ;; the image's address
SPCPTRH = FAC+17+1                          ;; the image's address's high byte
SPCNDX = FAC+19                             ;; the index of the image's character last read
SPCLEN = FAC+20                             ;; the image's length, 1 to 255
TENZNDX = FAC+21                            ;; the mask index of the units digit, $FF for none
CMACTR = FAC+22                             ;; the editor's count of digits since a comma
HALF = FAC+22                               ;; which half of a BCD byte the unpacker takes next
CMAFILL = FAC+23                            ;; the character for leading zeros, with bit 7 set to put in commas
SPCPTRB = SPCPTR+SYSPAG                     ;; the image's bank byte

STRTYP = $FF                                ;; PTRGET's type for a string variable
ZTYP = $41                                  ;; Z's digit class: leading zeros printed
CMATYP = $44                                ;; &'s digit class: commas put in
DTYP = $42                                  ;; #'s digit class: leading zeros as spaces
MSKLEN = 32                                 ;; the edit mask's size

; ---------------------------------------------------------------------------------------------------------------------
; PRINT USING
; ---------------------------------------------------------------------------------------------------------------------

;; PRINT USING: prints each expression through the next number or string spec of the image, with the literals
;; between.
;;
;; The image follows USING as a line number (of an IMAGE statement), a string literal or a string variable, then a
;; semicolon and the expressions, separated by commas or semicolons. When the image runs out of specs it starts over;
;; when the expressions run out, the literals up to the next number or string spec are printed, and a spec left over
;; is a type mismatch. A semicolon at the end leaves the line open.
;; In: TXTPTR = the end of USING
;; See: <IMSYNCK>, <UNUMEDIT>
PRUSING:
    jsr CHRGET
    bcc UIMAGE                              ; a line number
    cmp #'"'
    beq ULITRL
    jsr ISLETC                              ; a variable?
    bcc USNERR
    jsr PTRGET
    cpx #STRTYP
    bne USNERR
    sta INDEX
    sty INDEX+1
    lda VARPNTB
    sta INDEXB
    jsr NOTNOW                              ; the string itself
    sta SPCLEN
    stx SPCPTR
    sty SPCPTRH
    lda INDEXB
    sta SPCPTRB
    jmp UGOTSPT

;; Takes the image from a string literal, which may not be empty.
ULITRL:
    ldy #0
ULITS:
    jsr CHRGET
    beq USNERR                              ; no closing quote
    cpy #0
    bne ULITX
    ldx TXTPTR                              ; the first character: the image starts here
    stx SPCPTR
    ldx TXTPTR+1
    stx SPCPTR+1
    ldx TXTPTRB
    stx SPCPTRB
ULITX:
    cmp #'"'
    beq ULITE
    iny
    bne ULITS
ULITE:
    sty SPCLEN
    tya
    beq USNERR                              ; empty
    jsr CHRGET
    bne UGOTSPT

;; Ends the statement with a syntax error.
USNERR:
    jmp SNERR

;; Ends the statement with an undefined-statement error: the line is not an IMAGE statement, or the image is empty.
UIMERR:
    ldx #ERRUS
    jmp ERROR

;; Takes the image from the IMAGE statement at the line number in the program text, the rest of its line.
UIMAGE:
    jsr LINGET
    lda TXTPTR
    pha
    lda TXTPTR+1
    pha
    lda TXTPTRB
    pha
    jsr GOTOB                               ; find the line
    ldy #3
    jsr ADDON                               ; past its link and number
    jsr CHRGET
    tax
    cpx #IMAGETK
    bne UIMERR
    jsr CHRGET
    beq UIMERR
    lda TXTPTR
    sta SPCPTR
    lda TXTPTR+1
    sta SPCPTR+1
    lda TXTPTRB
    sta SPCPTRB
    jsr REMN                                ; the length to the line's end
    sty SPCLEN
    pla
    sta TXTPTRB
    pla
    sta TXTPTR+1
    pla
    sta TXTPTR

;; Starts on the expressions after the image's semicolon; an image that starts with a comma is a syntax error.
UGOTSPT:
    jsr CHRGOT
    cmp #';'
    bne USNERR
    ldx #$FF
    stx SPCNDX
    jsr UGETCH
    beq USNERR
    stx SPCNDX                              ; back before the first character
    inx
    stx VSPEC                               ; no spec has taken a value yet

;; Skips a comma or semicolon between the expressions.
USKPNXT:
    jsr CHRGET
    bne *+5                                 ; past the CHRGOT

;; Takes the next expression, or at the statement's end, or a semicolon, prints the image's last literals.
UNXTEXP:
    jsr CHRGOT
    bne UNXTEXC
    lda #0
    beq UTAILS
UNXTEXC:
    cmp #','
    beq USKPNXT
    cmp #';'
    bne UEVAL

;; Ends the statement: prints the literals left before the next number or string spec, then a new line unless a
;; semicolon ended it. A number or string spec found there, with no value for it, is a type mismatch.
;; In: A = 0 at the statement's end, or a semicolon
UTAILS:
    sta ENDFLG
    tax
    beq *+5
    jsr CHRGET                              ; nothing may follow the semicolon
    beq *+5
    jmp USNERR
    lda #MSKLEN
    jsr GETSPA                              ; the mask, for the scan
    jsr UDOLITS
    jsr UFRESPC
    dec SPECTYP                             ; 1, the image's end, is the only good result
    beq *+5
    jmp UTMERR
    lda ENDFLG
    bne *+5
    jmp CRDO
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Each expression
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates the next expression, or SCALE(n, expression), and makes it ready to print: a number as BCD digits in
;; <BCDSTR>, a string as its pointer and length.
;;
;; The image's place is kept on the stack meanwhile, as the evaluator uses the FAC's bytes. SCALE's n, a signed byte,
;; goes to the editor in <ISARA>; it is 0 otherwise.
UEVAL:
    lda SPCNDX
    pha
    lda SPCLEN
    pha
    lda SPCPTR
    pha
    lda SPCPTRH
    pha
    lda VSPEC
    pha
    lda #0                                  ; no scale
    pha
    jsr CHRGOT
    cmp #SCALETK
    bne UNOSCALE
    jsr CHRGET
    jsr GETABYT
    pla                                     ; the scale in place of the 0
    txa
    pha
    jsr CHKCOM
    lda #$20
    sta VALTYP                              ; any type: GETABYT set it
    jsr FRMEVL
    jsr CHKCLS
    beq UGOTNUM                             ; then the end, a comma or a semicolon
    cmp #','
    beq UGOTNUM
    cmp #';'
    beq UGOTNUM
    jmp SNERR

;; Evaluates an expression of any type.
UNOSCALE:
    lda #$20
    sta VALTYP
    jsr FRMEVL

;; Makes the value ready by its type: a string's pointer to <INDEX> and its length to <USVSTRL>, a long integer's
;; digits by <LUNPACK>, or a real's by <UNTYPE>.
UGOTNUM:
    bit VALTYP
    bpl UNTYPE
    jsr NOTFAC                              ; a string
    sta USVSTRL
    jmp USTKSAV

;; Unpacks a long integer's digits into <BCDSTR>, its exponent to <FACEXP>.
UDTYPE:
    jsr LUNPACK
    lda ISARA
    sta FACEXP
    jmp USTKSAV

;; Turns a real into BCD digits in <BCDSTR>, from index 2, through FOUT's text; its exponent less 1, times 2, plus 1
;; when negative, goes to <FACEXP>.
UNTYPE:
    bvs UDTYPE                              ; a long integer
    lda FACSGN
    pha
    jsr FOUT
    pla
    cmp #$80                                ; carry = the sign
    php
    lda ISARA                               ; FOUT's exponent
    sec
    sbc #1
    plp
    rol
    sta FACEXP
    ldy #2
    ldx #0

;; Copies FOUT's digits, skipping the point, a minus and leading zeros, up to the first other character.
STRBCD0:
    lda FBUFFR,X
    cmp #'.'
    beq STRBCD1
    cmp #'-'
    beq STRBCD1
    cmp #':'
    bcs STRBCD2
    sbc #'0'-1
    bcc STRBCD2
    bne *+6
    cpy #2                                  ; a zero before any other digit
    beq STRBCD1
    sta BCDSTR,Y
    iny
STRBCD1:
    inx
    bne STRBCD0                             ; always
STRBCD2:
    lda #0                                  ; zeros to index 21
STRBCD3:
    sta BCDSTR,Y
    iny
    cpy #22
    bne STRBCD3

;; Takes the image's place and the scale back off the stack, then finds the value's spec.
USTKSAV:
    pla
    sta ISARA
    pla
    sta VSPEC
    pla
    sta SPCPTRH
    pla
    sta SPCPTR
    pla
    sta SPCLEN
    pla
    sta SPCNDX
    lda #MSKLEN
    jsr GETSPA

;; Prints the literals up to the next number or string spec; at the image's end starts over from its first spec,
;; unless no spec in it takes a value, which is a type mismatch.
UNXTSPC:
    jsr UDOLITS
    ldx SPECTYP
    beq UVSPEC                              ; a number
    bmi UVSPEC                              ; a string
    lda VSPEC
    beq UTMERR2
    sta SPCNDX                              ; $FF: start over
    bne UNXTSPC                             ; always

;; Checks the value's type against the spec's, then prints it.
UVSPEC:
    lda #$FF
    sta VSPEC
    sec
    lda VALTYP
    tax
    sbc SPECTYP
    lsr                                     ; carry = set when only one is a string
    bcc *+8

;; Frees the mask, then ends the statement with a type mismatch.
UTMERR2:
    jsr UFRESPC

;; Ends the statement with a type mismatch.
UTMERR:
    jmp TMERR
    txa
    bpl *+5
    jmp USTRVAR
    jmp UNUMVAR

;; Clears the mask, scans the next spec, and prints it when it is a literal, until a number or string spec or the
;; image's end.
;; Out: SPECTYP = 0 for a number spec, $FF for a string spec, 1 at the image's end
;; See: <IMSYNCK>
UDOLITS:
    ldy #MSKLEN-1
    lda #0
UBLKMSK:
    sta (MASKPT),Y
    dey
    bpl UBLKMSK
    jsr IMSYNCK
    bit SPECTYP
    bmi ULITOUT

;; Returns from <UDOLITS>.
UDOXIT:
    rts

;; Prints a literal, unless the spec was a string's.
ULITOUT:
    bvs UDOXIT                              ; a string

;; Prints the literal at <LOWTR>, <SAVLEN> bytes, <REP> times, then goes on to the next spec.
;;
;; An empty literal, "", has a length of 0, and prints 256 bytes.
UREPEAT:
    ldy #0
    ldx SAVLEN
UOUTLP:
    lda (LOWTR),Y
    jsr OUTDO
    iny
    dex
    bne UOUTLP
    dec REP
    bne UREPEAT
    beq UDOLITS

;; Prints a string through its spec, cut to the field's width or padded with spaces: A puts the spaces after it, C
;; half before, and R all before.
USTRVAR:
    lda USVSTRL
    sta SAVLEN
    lda REP                                 ; the width less the length
    sec
    sbc SAVLEN
    beq UEXACT
    bcs USFITS
    ldx REP                                 ; too long: cut it
    stx SAVLEN
    jmp UEXACT

;; Prints the spaces before a string shorter than its field.
;; In: A = the spaces to spare
USFITS:
    ldy DELIM
    cpy #'A'
    beq UEXACT
    cpy #'A'+$20
    beq UEXACT
    cpy #'C'
    beq *+6
    cpy #'C'+$20
    bne UEATME
    ldx SAVLEN
    beq UEATME
    lsr                                     ; centered: half before
UEATME:
    tax
    inx
ULSPCS:
    dex
    beq UEXACT
    jsr OUTSPC
    dec REP
    bne ULSPCS

;; Prints the string's <SAVLEN> characters, then spaces to the field's end.
UEXACT:
    ldy #0
    ldx SAVLEN
    beq UNULL
UEXACT2:
    lda (INDEX),Y
    jsr OUTDO
    iny
    dec REP
    dex
    bne UEXACT2

;; Prints spaces to the field's end.
UNULL:
    ldx REP
UFILL3:
    beq UFRESTR
    jsr OUTSPC
    dex
    jmp UFILL3

;; Prints a number through its mask, then takes the next expression.
;; See: <UNUMEDIT>
UNUMVAR:
    jsr UNUMEDIT

;; Frees the mask and takes the next expression.
UFREMSK:
    jsr UFRESPC
    jmp UNXTEXP

;; Frees the string, if it was a temporary one, and the mask, then takes the next expression.
UFRESTR:
    jsr FRECNOW
    jmp UFREMSK

; ---------------------------------------------------------------------------------------------------------------------
; Reading the image
; ---------------------------------------------------------------------------------------------------------------------

;; Frees the mask's <MSKLEN> bytes of string space.
;; See: <FRESPA>
UFRESPC:
    lda #MSKLEN
    ldy FRESPC+1
    ldx FRESPC
    stx INDEX
    sty INDEX+1
    ldx FRESPCB
    stx INDEXB
    jmp FRESPA

; UREGET drops UGETCHR's saved status and reads on past a space.
UREGET:
    pla

;; Reads the image's next character other than a space, and classifies it as <IGOTCH> does.
;; See: <UGETCH>
UGETCHR:
    jsr UGETCH
    php
    cmp #' '
    beq UREGET
    plp
    rts

;; Moves <SPCNDX> to the image's next character, and classifies it as <IGOTCH> does.
UGETCH:
    inc SPCNDX

;; Classifies the image's character at <SPCNDX>.
;;
;; An index of $FF, past a 255-character image, reads as the end, and stays there.
;; Out: A = the character (0 at the end), zero = set at the end or a comma, carry = clear for a digit,
;;   overflow = set for an upper-case letter
IGOTCH:
    ldy SPCNDX
    lda #0
    cpy #$FF
    bne UGETCKL
    dec SPCNDX
    bne UGETNE
UGETCKL:
    cpy SPCLEN
    bcs UGETNE                              ; the end
    lda (SPCPTR),Y
    cmp #','
    beq UGETEND
    cmp #'A'
    bcc UGETCKD
    cmp #'Z'+1
    bcc UGETVS
UGETCKD:
    cmp #':'
    bcs UGETNE
    sec                                     ; carry = clear for a digit, and A as it was
    sbc #'0'
    sec
    sbc #$D0
UGETNE:
    tay                                     ; zero = set for 0, the end
UGETEND:
    clv
    rts

;; Returns an upper-case letter with overflow set and carry set.
UGETVS:
    bit *+4                                 ; the $40 in the next instruction sets overflow
    cmp #$40
    rts

;; Adds A to the mask.
;;
;; A mask longer than <MSKLEN> bytes is a syntax error.
UATOMSK:
    ldy MSKNDX
    iny
    cpy #MSKLEN
    bcs USYERR
    sta (MASKPT),Y
    sty MSKNDX
    rts

;; Ends the statement with a syntax error.
USYERR:
    jmp USNERR

;; Puts the digit positions counted in <DIGCTR> into the mask as zeros, and adds them to <DIGB4DPT> or <DIGAFDPT>.
;;
;; Before the decimal point, the last one's index is the units digit's, in <TENZNDX>. It is a syntax error for Z
;; digits before the point in a field with a floating symbol, or for & digits fewer than 5.
;; Out: A = as it was, Y = 2, NMASK = 0
UDOMASK:
    pha
    ldy DIGCTR
    beq UDONT
    ldx #1                                  ; after the point
    lda #4
    bit EMASK
    php                                     ; zero = set before the point
    bne UAFDPT
    lda NMASK
    cmp #ZTYP
    bne UNOTZ
    lda FLTMSK
    bne USYERR
UNOTZ:
    dex                                     ; before the point
UAFDPT:
    tya
    sta DIGB4DPT,X
    ldx NMASK
    beq USYERR
    cpx #CMATYP
    bne UANYSIZ
    cmp #5                                  ; room for #,###
    bcc USYERR
UANYSIZ:
    lda #0
UDOMSKL:
    jsr UATOMSK
    dec DIGCTR
    bne UDOMSKL
    plp
    bne UDONT
    sty TENZNDX
UDONT:
    ldy #2
    lda #0
    sta NMASK
    pla
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The spec scanner
; ---------------------------------------------------------------------------------------------------------------------

;; Scans the image's next spec, checking its syntax, and builds a number spec's edit mask at <MASKPT>, or points
;; <LOWTR> and <SAVLEN> at a literal's text.
;;
;; A number spec's parts may come in this order: **, $ or a sign (a fixed $ or sign goes into the mask, a floating
;; one only reserves its place), $ again, the digits and decimal point, a trailing sign, then the exponent's E's. A
;; spec must end at a comma or the image's end; anything else is a syntax error.
;; Out: SPECTYP = 0 for a number, $FF for a string, $80 for a literal, 1 at the image's end, REP = its count,
;;   DELIM = its character
;; See: <UGETDL>, <UDOLITS>
IMSYNCK:
    ldy #1
    sty SPECTYP                             ; none, until one is found
    dey
    sty CMAFILL
    sty DIGB4DPT
    sty DIGAFDPT
    sty FLTMSK
    sty DIGCTR
    sty EMASK
    sty NMASK
    dey
    sty DPTNDX
    sty TENZNDX
    sty MSKNDX
    jsr UGETDL
    bpl UNUMTYP                             ; a number spec's character
    sta SPECTYP
    bit SPECTYP
    bvs UCHEKCM                             ; a string: done
    lda DELIM
    cmp #'/'
    beq UCRLIT
    cmp #'X'
    beq USPLIT
    cmp #'X'+$20
    beq USPLIT
    lda SPCNDX                              ; a quoted literal: it starts after the quote
    sec
    adc SPCPTR
    ldy SPCPTR+1
    ldx SPCPTRB
    bcc *+6
    iny
    jsr FIXYX
    sta LOWTR
    sty LOWTR+1
    stx LOWTRB
    ldx #<(0-1)

;; Counts the literal's characters up to its closing quote; with none, it is a syntax error.
UQSCAN:
    inx
    jsr UGETCH
    cmp #0
    beq USNERRL
    cmp #'"'
    bne UQSCAN
    stx SAVLEN
    jsr UGETCHR

;; Returns when the spec ends at a comma or the image's end, or ends the statement with a syntax error.
UCHEKCM:
    jsr IGOTCH
    bne *+3
    rts

;; Ends the statement with a syntax error.
USNERRL:
    jmp USNERR

;; Makes / a literal of a return and a line feed.
UCRLIT:
    lda #$0A
    sta LITRLCH+1
    ldy #2
    lda #$0D
    bne *+6

;; Makes X a literal of a space.
USPLIT:
    lda #' '
    ldy #1
    sta LITRLCH
    ldx #>(LITRLCH)
    lda #LITRLCH
    sta LOWTR
    stx LOWTR+1
    sty LOWTRB                              ; 1 or 2: no bank, as for the zero page
    sty SAVLEN
    bne UCHEKCM

;; Starts a number spec: takes **, which must be exactly two, for asterisk fill.
;; In: A = the spec character's type
UNUMTYP:
    ldy #2
    cmp #$02                                ; *
    bne UDOLLR
    cpy REP
    bne UNSERR
    lda #$10
    sta FLTMSK
    lda DELIM
    sta CMAFILL
    jsr UENDERR
    jmp UDOLLR

;; Takes a $, or returns when A is not one: $$ floats; one $ floats after ** or a floating sign, and otherwise goes
;; into the mask. A second $ in the spec, or $$ after another floating symbol, is a syntax error.
;; In: A = the spec character's type, Y = 2
UDOLAR:
    cmp #$10
    beq *+3
    rts
    bit EMASK
    bne UNSERR
    ora EMASK
    sta EMASK
    cpy REP
    bne UCK1DL
    lda FLTMSK
    bne UNSERR
    beq UDLFLT
UCK1DL:
    dey
    cpy REP
    bne UNSERR
    lda FLTMSK
    beq USTDLR

;; Marks a floating $, after a floating sign or not, and reserves its place in the mask.
UDLFLT:
    cmp #$40                                ; after a floating sign?
    lda #$20
    bcc *+4
    asl
    asl
    ora FLTMSK
    sta FLTMSK
    inc MSKNDX
    jmp UXDLR

;; Puts a fixed $ into the mask.
USTDLR:
    lda DELIM
    jsr UATOMSK
UXDLR:
    jmp UENDERR

;; Takes a $ and then a leading sign: ++ or -- floats; one sign floats after another floating symbol, and otherwise
;; goes into the mask.
UDOLLR:
    jsr UDOLAR
    bit UDOLLR                              ; its JSR's $20: a sign?
    beq UTRYDL2
    ora EMASK
    sta EMASK
    cpy REP
    bne UCK1SIN
    lda FLTMSK
    bne UNSERR
    beq UFLTSIN
UCK1SIN:
    dey
    cpy REP
    bne UNSERR
    lda FLTMSK
    beq USETSIN

;; Marks a floating sign and reserves its place in the mask.
UFLTSIN:
    lda #$40
    ora FLTMSK
    sta FLTMSK
    inc MSKNDX
    jmp UXSIN

;; Ends the statement with a syntax error.
UNSERR:
    jmp USNERR

;; Puts a fixed leading sign into the mask.
USETSIN:
    lda DELIM
    jsr UATOMSK
UXSIN:
    jsr UENDERR

;; Takes a $ after the sign.
UTRYDL2:
    jsr UDOLAR

;; Takes a run of digit positions, counting them in <DIGCTR> and noting the field's digit class and fill.
;;
;; The class is the highest of the digits' so far; after the decimal point it is Z's, as every digit there prints.
;; A string or literal character among them is a syntax error.
;; In: A = the spec character's type
UTRYDIG:
    cmp #ZTYP
    bcc UBLDMK                              ; not a digit
    tax
    bmi UNSERR
    lda #$80
    ora EMASK
    sta EMASK
    lda REP
    clc
    adc DIGCTR
    sta DIGCTR
    cpx NMASK
    bcs *+4
    ldx NMASK
    lda #$04
    bit EMASK
    beq UB4DPT
    ldx #ZTYP                               ; after the point
    bne UXNMASK

;; Sets the fill for leading zeros from the class, or keeps **'s asterisk, with the comma bit for &.
UB4DPT:
    lda CMAFILL
    and #$7F
    cmp #'*'
    beq USETCMA
    lda a:FILLTABL-ZTYP,X
USETCMA:
    ora a:CMATBL-ZTYP,X
    sta CMAFILL
UXNMASK:
    stx NMASK

;; Reads the spec's next character, or finishes the spec at its end.
UXMORE:
    jsr UCKDEND
    jmp UTRYDIG

;; Puts the digits counted into the mask, then takes a decimal point, which must be single and the spec's only one.
UBLDMK:
    jsr UDOMASK
    cmp #$04                                ; .
    bne USGNCK
    bit EMASK
    bne UNSERR
    dey
    cpy REP
    bne UNSERR
    ora EMASK
    sta EMASK
    lda DELIM
    jsr UATOMSK
    lda MSKNDX
    sta DPTNDX
    jmp UXMORE

;; Takes a trailing sign, which must be single and the spec's only one.
USGNCK:
    bit UDOLLR                              ; its JSR's $20: a sign?
    beq UCKEXP
    dey
    cpy REP
    bne USTERR
    bit EMASK
    bne USTERR
    ora EMASK
    sta EMASK
    lda DELIM
    jsr UATOMSK
    jsr UCKDEND

;; Takes the exponent, EEE or EEEE, which must end the spec; anything else is a syntax error.
;;
;; With an exponent, no floating symbol may come with 0 or 1 digit before the point, only a floating sign with 3, and
;; any other count is a syntax error.
UCKEXP:
    cmp #$08                                ; E
    bne USTERR
    iny
    cpy REP
    beq UEEE
    iny
    cpy REP
    bne USTERR
UEEE:
    ora EMASK
    sta EMASK
    lda DELIM
UEEELP:
    jsr UATOMSK
    dec REP
    bne UEEELP
    lda #$F0                                ; no floating symbol
    ldx DIGB4DPT
    beq UENOFLT
    dex
    beq UENOFLT
    cpx #2
    bne USTERR
    lda #$B0                                ; only a floating sign
UENOFLT:
    and FLTMSK
    bne USTERR
    jsr UCHEKCM
    jsr UDIGEND                             ; which does not return

;; Reads the spec's next character, which must be there.
;; Out: A = its type, Y = 2
UENDERR:
    jsr IGOTCH
    beq USTERR
    bne UNXTGET

;; Reads the spec's next character, or at its end finishes the spec with <UDIGEND>.
;; Out: A = its type, Y = 2
UCKDEND:
    jsr IGOTCH
    beq UDIGEND
UNXTGET:
    jsr UGETDL
    ldy #2
    rts

;; Finishes a number spec: puts the last digits into the mask, and returns to <IMSYNCK>'s caller with SPECTYP 0.
;;
;; A spec with no digits, or with a floating symbol and no digit before the point, is a syntax error.
UDIGEND:
    lda EMASK
    bpl USTERR
    jsr UDOMASK
    lda FLTMSK
    beq UCKXIT
    lda DIGB4DPT
    beq USTERR

;; Marks the spec a number's and returns past the caller.
UCKXIT:
    lda #0
    sta SPECTYP
    pla
    pla
    rts

;; Frees the mask, then ends the statement with a syntax error.
USTERR:
    jsr UFRESPC
    jmp USNERR
