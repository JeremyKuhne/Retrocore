; B3DIMNH: finding variables. DIM, PTRGET's search of the simple variable and array tables, which makes a variable
; it does not find, the tables of each type's size and type byte, the start of building an array (B3UDEFI finishes
; it), and helpers to push the FAC for FOR and to make the FAC a 16-bit integer.
;
; Variables live after the program: the array table from ARYTAB to VARTAB (also called SMVARS), then the simple
; variable table from VARTAB to STREND. Strings grow down from FRETOP to meet them. Every pointer into this space is
; three bytes: the low byte, a page kept in $02-$81, and the bank's X-byte ($80 + the bank) in the X-byte page. A page
; past $81 goes on at $02 in the next bank, so the space reads as one run of memory 32K per bank.
;
; A simple variable's entry is one length byte (the whole entry's), the name, a type byte and the value:
;
; > length | name (n bytes) | type | value
;
; An array's entry has a two-byte length (low byte first), then the name, the type, the count of dimensions, each
; dimension's size (high byte first, the last subscript's first), then the elements, the first subscript varying
; fastest:
;
; > length (2) | name (n bytes) | type | count | sizes (2 per dimension) | elements
;
; Names are kept in upper case without their type character; in the program a name, with its type character, may be
; up to 64 characters.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; DIM and the variable search
; ---------------------------------------------------------------------------------------------------------------------

;; DIM's loop: after each array, a comma brings the next one.
;; See: <DIM>
DIM3:
    jsr CHKCOM

;; The DIM statement: makes each array named, sized by its subscripts.
;;
;; DIMFLG, which <PTRGT1> takes from X, is the array name's first letter, so its bit 6 is set; the search tests that
;; bit to size a new array from the subscripts, to refuse an array that exists, and to stop before indexing it.
;; In: A = the character after DIM
;; See: <ISARY>, <NOTFF2>
DIM:
    tax                                     ; DIMFLG: the first letter, bit 6 set
    lda #0
    sta DORES                               ; arrays not found are made
    jsr PTRGT1
    jsr CHRGOT
    bne DIM3
    rts

;; Reads the variable name at TXTPTR and finds its value, making the variable when it does not exist.
;;
;; An array's subscripts are evaluated as formulas, which can call PTRGET again, so the array search keeps its state
;; on the stack. A simple variable or an array element not yet used is made, zeroed; an array not yet used is made
;; with 11 elements (0-10) in each dimension given.
;; In: TXTPTR = the variable's name
;; Out: VARPNT = the value's address (VARPNTB its bank), A = its low byte, Y = its page, TXTPTR = past the name and any
;;   subscripts, VALTYP = 0 for a number, $FF for a string or $40 for a long integer, INTFLG = $80 for an integer,
;;   ISARA = $80 for an array element, 0 for a simple variable
;; Errors: ERRSN = a bad name or one longer than 64 characters, ERRBS = the wrong count of subscripts or one past the
;;   array's size, ERRFC = a negative or too large subscript, ERRDD = DIM of an array that exists, ERROM = no room
;; See: <PTREVL>, <ISLETC>, <VALTAB>, <ISARY>
PTRGET:
    ldx #0                                  ; DORES: make arrays not found

;; Inherit: <PTRGET>
;; With X nonzero, an array not found is not made: VARPNT points to a zero (<ZERO>) instead, as the expression
;; evaluator wants.
;; In: X = nonzero not to make an array not found, TXTPTR = the variable's name
PTREVL:
    stx DORES
    ldx #$0                                 ; not in DIM

;; Inherit: <PTRGET>
;; Takes DIMFLG from X; <DIM> enters here.
;; In: X = DIMFLG, nonzero in DIM, TXTPTR = the variable's name
PTRGT1:
    stx DIMFLG

;; Inherit: <PTRGET>
;; Takes DIMFLG, DORES and SUBFLG as they are; FN's name and DEF's argument enter here with SUBFLG set.
;; In: SUBFLG = $80 for DEF's argument (no subscripts), bits 7 and 6 for an FN name, TXTPTR = the variable's name
;; See: <GETFN1>, <DEF>
PTRGT2:
    jsr CHRGOT
    jsr ISLETC
    bcs PTRGT3

;; Ends the statement with SYNTAX ERROR, for a variable name that is not one.
WRDERR:
    jmp SNERR

;; Starts with a letter: notes where the name starts, in LOWDS and TMPPTR, and reads to its end.
PTRGT3:
    ldx #$0
    stx INTFLG                              ; a real unless the name says otherwise
    stx ISARA                               ; and a simple variable
    lda TXTPTR
    sta LOWDS
    sta TMPPTR
    lda TXTPTR+1
    sta LOWDS+1
    sta TMPPTR+1
    lda TXTPTRB
    sta LOWDSB
    sta TMPPTRB

;; Skips the name's letters, digits and periods.
EATEM:
    jsr CHRGET
    bcc EATEM                               ; a digit
    jsr ISLETC
    bcs EATEM
    cmp #'.'
    beq EATEM
    cmp #'!'                                ; the type character, if any: ! $ % or &
    beq GOTTYP
    cmp #'&'+1
    bcs REAL
    cmp #'$'
    bcc REAL

;; Turns the type character into an index in <VALTAB>, refusing one on an FN name, and steps past it.
GOTTYP:
    adc #$DF                                ; carry set: ! is 1, $ is 4, % is 5, & is 6
    tax
    bit SUBFLG
    bmi WRDERR                              ; FN names are real
    jsr CHRGET

;; Looks up the type's value size and type byte, and works out the name's length.
;;
;; A real's name has no type character, so its length gets 1 here to match the others: <FOUR6> is the name's length
;; plus 1 in every case. An FN name gets type $10 and a six-byte value.
REAL:
    ldy a:VALTAB,X
    sty VARNAM                              ; the value's size
    pha                                     ; the character after the name
    lda TXTPTR
    sec
    sbc LOWDS
    cmp #65
    bcs WRDERR                              ; longer than 64 characters
    ldy a:VALTB2,X
    bne NTREAL
    adc #$1                                 ; a real: carry is clear

;; Keeps the name's length plus 1 in <FOUR6>, and sets an FN name's type.
NTREAL:
    sta FOUR6
    pla
    bit SUBFLG
    bpl YSTORE
    bvc YSTORE
    ldy #6
    sty VARNAM                              ; an FN's value is six bytes
    ldy #$10                                ; and its type $10

;; Keeps the type byte in VALTYP, then goes to the array search for a name followed by `(`, unless SUBFLG is set.
YSTORE:
    sty VALTYP
    sec
    ora SUBFLG                              ; any SUBFLG bit makes it a simple variable
    sbc #'('
    bne SPLVAR

;; Goes to the array search.
GARRAY:
    jmp ISARY

;; Not followed by `(`: with SUBFLG bit 6 alone, still an array; otherwise a simple variable.
;;
;; Nothing in this BASIC sets bit 6 without bit 7, so the branch to <GARRAY> is never taken.
SPLVAR:
    bit SUBFLG
    bmi SIMVAR
    bvs GARRAY

;; Searches the simple variable table, from SMVARS to STREND, for the name and type; makes the variable at STREND if
;; it is not there.
;;
;; A `!` variable must be an array.
;; See: <ADDVAR>, <GONEXT>
SIMVAR:
    cpy #$C0                                ; the type of a ! name
    beq WRDERR
    ldy #$0
    sty SUBFLG                              ; subscripts allowed again
    lda SMVARS
    ldx SMVARS+1
    ldy SMVARSB
    sty SRCHPTB

;; Keeps the entry's page in SRCHPT and checks it against STREND, the table's end.
STXLOP:
    stx SRCHPT+1

;; Inherit: <STXLOP>
SRCHLP:
    sta SRCHPT
    cmp STREND
    bne PNTER3
    cpx STREND+1
    bne PNTER3
    ldy SRCHPTB
    cpy STRENDB
    beq ADDVAR                              ; the end: not found

;; Compares the name in the program with this entry's, upper-casing the program's letters.
;;
;; A character below `.` (the type character, `(` or a space) or above `z` (a token) ends the name.
PNTER3:
    ldy #0
    lda (SRCHPT),Y
    sta VARNAM+1                            ; the entry's length, for GONEXT

;; Inherit: <PNTER3>
COMPAR:
    lda (LOWDS),Y
    iny
    cmp #'.'
    bcc TYPCHK
    cmp #'A'+$20
    bcc NOT2BIG
    cmp #'Z'+1+$20
    bcs TYPCHK
    sbc #$1F                                ; carry clear: subtracts $20

;; Inherit: <PNTER3>
NOT2BIG:
    cmp (SRCHPT),Y
    beq COMPAR

;; At the name's end, or the first difference: the entry matches when its type byte is here and the name's length
;; agrees.
TYPCHK:
    lda VALTYP
    cmp (SRCHPT),Y
    bne GONEXT
    cpy FOUR6
    bne GONEXT
    tya                                     ; carry is set, adding one more

;; Points VARPNT at the value: the entry's address plus A plus carry, moving to the next bank past page $81.
;; In: A = the value's offset (less the carry), carry, SRCHPT = the entry, X = its page
FINUP:
    adc SRCHPT
    bcc CMPLTE
    inx
    cpx #MAXPG
    bcc *+7
    ldx #MINPG
    inc SRCHPTB

;; Inherit: <FINUP>
CMPLTE:
    stx VARPNT+1
    ldy VARPNT+1
    sta VARPNT
    ldx SRCHPTB
    stx VARPNTB

;; Turns an integer's type byte ($80) into INTFLG = $80 with VALTYP = 0, as the expression evaluator wants.
;; See: <DIMRTS1>
MYMYMY:
    ldx VALTYP
    cpx #$80
    bne PTRRTS
    stx INTFLG
    ldx #$0
    stx VALTYP

;; An RTS for <MYMYMY>'s branch.
PTRRTS:
    rts

;; Steps SRCHPT past this entry, by its length byte, and searches on.
GONEXT:
    clc
    lda VARNAM+1                            ; the entry's length
    adc SRCHPT
    bcc SRCHLP
    inx
    cpx #MAXPG
    bcc STXLOP
    ldx #MINPG
    inc SRCHPTB
    bcs STXLOP                              ; always

;; Tells whether a character is a letter, upper or lower case.
;; In: A = the character
;; Out: carry = set for a letter
;; Keeps: A, X, Y
ISLETC:
    cmp #'A'
    bcc ISLRTS
    sbc #'Z'+1                              ; the two subtractions take 256 in all, leaving A as it was
    sec
    sbc #$100-'Z'-1                         ; and carry set only for A-Z
    bcs ISLRTS
    cmp #'A'+$20
    bcc ISLRTS
    sbc #'Z'+$21                            ; the same for a-z
    sec
    sbc #$100-'Z'-$21

;; An RTS for <ISLETC>'s branches.
ISLRTS:
    rts

;; Makes a simple variable at STREND, the table's end: the length byte, the name in upper case, the type byte and a
;; zero value, then points VARPNT at the value.
;;
;; The simple variable table is last, so the entry only moves STREND up; <REASON> checks that it stays below the
;; strings.
;; In: SRCHPT = STREND, LOWDS = the name in the program, FOUR6 = the name's length plus 1, VARNAM = the value's size,
;;   VALTYP = the type byte
;; See: <SIMVAR>
ADDVAR:
    sec
    lda FOUR6
    sta VARNAM+1
    adc VARNAM                              ; the entry's length: the name's plus 2, and the value's
    ldy STREND+1
    ldx STRENDB
    pha
    adc STREND                              ; carry is clear
    bcc GOARND
    iny
    cpy #MAXPG                              ; past page $81:
    bcc GOARND
    ldy #MINPG                              ; on at page 2 of the next bank
    inx

;; Moves STREND past the new entry, if there is room, and writes the entry.
GOARND:
    jsr REASON
    sty STREND+1
    stx STRENDB
    sta STREND
    pla                                     ; the entry's length
    ldy #$0
    sta (SRCHPT),Y
    tay
    dey                                     ; the value's last byte
    ldx VARNAM                              ; the value's size
    lda #$0

;; Zeroes the value, from its last byte down, then writes the type byte.
TILOOP:
    sta (SRCHPT),Y
    dey
    dex
    bne TILOOP
    lda VALTYP
    sta (SRCHPT),Y

;; Copies the name from the program into the entry, from its last character down, upper-casing it.
TGHTLP:
    dey
    dey
    bmi ALDONE
    lda (LOWDS),Y
    cmp #'A'+$20
    bcc *+4
    sbc #$20
    iny
    sta (SRCHPT),Y
    bpl TGHTLP                              ; always

;; Points VARPNT at the new value, past the length byte, the name and the type byte.
ALDONE:
    ldx SRCHPT+1
    lda VARNAM+1                            ; the name's length plus 1
    sec                                     ; plus 1 more
    jmp FINUP

;; Each type's value size in bytes, by the index the type character gives: a real (no character) 4, `!` 1, `"` none,
;; `#` 10, `$` 3 (a string's descriptor), `%` 2, `&` 8.
;;
;; `"` and `#` never get here: only `!` and `$` to `&` are taken as type characters. A real is four bytes: the
;; exponent, then the mantissa's top three bytes, the sign in bit 7 of the first. An integer is two bytes, high byte
;; first; a long integer eight, two's complement, high byte first.
;; See: <VALTB2>, <REAL>
VALTAB:
    .byte 4, 1, 0, 10                       ; real, !, unused, #
    .byte 3, 2, 8                           ; $, %, &

;; Each type's type byte, in <VALTAB>'s order: a real 0, `!` $C0, `#` $40, `$` $FF, `%` $80, `&` $40.
;;
;; An FN gets $10 instead, in <NTREAL>.
VALTB2:
    .byte 0, 192, 0, 64
    .byte 255, 128, 64

; ---------------------------------------------------------------------------------------------------------------------
; Helpers for FOR and for subscripts
; ---------------------------------------------------------------------------------------------------------------------

;; Pushes A, then the rounded FAC, under the caller's return: FOR keeps its STEP this way.
;; In: A = the byte to push first (the step's sign)
;; See: <FORPSH>
PUSHF:
    tay
    pla                                     ; the return address, into INDEX1
    sta INDEX1
    pla
    sta INDEX1+1
    inc INDEX1
    bne *+4
    inc INDEX1+1
    tya
    pha

;; Pushes the rounded FAC, five bytes with the exponent on top, then jumps to INDEX1.
;; In: INDEX1 = where to go on
FORPSH:
    jsr ROUND
    lda FACLO
    pha
    lda FACMO
    pha
    lda FACMOH
    pha
    lda FACHO
    pha
    lda FACEXP
    pha
    jmp (INDEX1)

;; Points ARYPNT at an array's elements: past the entry's head and two bytes for each of COUNT dimensions.
;; In: LOWTR = the array's entry, VARNAM+1 = the name's length plus 3, COUNT = the count of dimensions
;; Out: ARYPNT = the elements' address, with its bank in ARYPNTB, carry = clear
;; See: <FMPTR1>, <FMPTR2>
FMAPTR:
    lda COUNT
    asl

;; Points ARYPNT A bytes past an array's sizes, which start one past the count of dimensions.
;; In: A = the offset, LOWTR = the array's entry, VARNAM+1 = the name's length plus 3
FMPTR1:
    sec

;; Points ARYPNT A bytes plus carry past an array's count of dimensions.
;; In: A = the offset, carry, LOWTR = the array's entry, VARNAM+1 = the name's length plus 3
FMPTR2:
    adc VARNAM+1
    adc LOWTR
    ldy LOWTR+1
    ldx LOWTRB
    bcc JSRGM
    iny
    cpy #MAXPG
    bcc JSRGM
    ldy #MINPG
    inx

;; Inherit: <FMPTR2>
JSRGM:
    sta ARYPNT
    sty ARYPNT+1
    stx ARYPNTB
    rts

;; -32768 as a real, for <AYINT>'s check.
N32768:
    .byte 144, 128, 0, 0
    .byte 0

;; Evaluates a subscript: the formula after the current character, as an integer 0-32767.
;;
;; The formula can name another array, so the name's address in TMPPTR and DORES are kept on the stack meanwhile.
;; Out: INDICE = the subscript's high byte (INDICE is FACMO), FACLO = its low byte
;; Errors: ERRFC = a negative or too large value
;; See: <POSINT>
INTIDX:
    jsr CHRGET
    lda TMPPTR
    pha
    lda TMPPTR+1
    pha
    lda TMPPTRB
    pha
    lda DORES
    pha
    jsr FRMNUM
    pla
    sta DORES
    pla
    sta TMPPTRB
    pla
    sta TMPPTR+1
    pla
    sta TMPPTR

;; Makes the FAC a 16-bit integer, refusing a negative number.
;; Out: FACMO = the high byte, FACLO = the low byte
;; Errors: ERRFC = a negative number or one past 32767
;; See: <AYINT>
POSINT:
    lda FACSGN
    bmi NONONO                              ; negative: zero is clear, so an error

;; Makes the FAC a signed 16-bit integer, -32768 to 32767, rounding it by adding one half first.
;; Out: FACMO = the high byte, FACLO = the low byte
;; Errors: ERRFC = a number out of range
;; See: <POSINT>, <N32768>
AYINT:
    lda FACEXP
    cmp #144                                ; below 32768 in size?
    bcc QINTGO
    lda #<(N32768)
    ldx #0
    ldy #>(N32768)
    jsr FCOMP                               ; or exactly -32768?

;; Goes on when zero is set; otherwise an ILLEGAL QUANTITY error.
NONONO:
    beq QINTGO
    jmp FCERR

;; Adds one half and makes the FAC an integer.
QINTGO:
    jsr FADDH
    jmp QINT

; ---------------------------------------------------------------------------------------------------------------------
; Arrays
; ---------------------------------------------------------------------------------------------------------------------

;; Finds an array, or makes it, and points VARPNT at the element the subscripts name.
;;
;; The subscripts are evaluated first and kept on the stack, two bytes each with the low byte on top and the last
;; subscript nearest the top, under the type byte and DIMFLG. In DIM the array must not exist, and is only made.
;; In: Y = the type byte, FOUR6 = the name's length plus 1, TMPPTR = the name in the program
;; See: <INTIDX>, <STRTSRCH>, <NOTFFD>, <GETDEF>
ISARY:
    lda FOUR6
    clc
    adc #$2
    sta VARNAM+1                            ; the name's length plus 3: the length bytes and the type
    lda SUBFLG
    bne STRTSRCH                            ; no subscripts to read
    lda DIMFLG
    ora INTFLG
    pha
    tya
    pha                                     ; the type byte
    ldy #0                                  ; no subscripts yet

;; Evaluates each subscript and slips it on the stack under the type byte and DIMFLG.
INDLOP:
    tya
    pha
    lda VARNAM+1
    pha
    lda VARNAM
    pha
    jsr INTIDX
    pla
    sta VARNAM
    pla
    sta VARNAM+1
    pla
    tay
    tsx
    lda 258,X
    pha                                     ; DIMFLG and the type, pushed again
    lda 257,X
    pha
    lda INDICE                              ; and the subscript in their old place
    sta 258,X
    lda INDICE+1
    sta 257,X
    iny
    jsr CHRGOT
    cmp #44                                 ; a comma: another subscript
    beq INDLOP
    sty COUNT                               ; the count of subscripts
    jsr CHKCLS
    pla
    sta VALTYP
    pla
    sta INTFLG
    and #127
    sta DIMFLG

;; Searches the array table, from ARYTAB to VARTAB, for the name and type.
STRTSRCH:
    lda ARYTAB+1
    ldx ARYTAB
    ldy ARYTABB

;; Points LOWTR at the next entry, and ends the search at VARTAB.
;; In: X = the entry's low byte, A = its page, Y = its bank
LOPFDA:
    sta LOWTR+1
    stx LOWTR
    sty LOWTRB
    cpy VARTABB
    bne LOPFDV
    cmp VARTAB+1
    bne LOPFDV
    cpx VARTAB
    beq NOTFFD                              ; the end: not found

;; Compares the name in the program with this entry's, upper-casing the program's letters.
;;
;; Unlike the simple variable search, any character below `a` is compared, so a type character or `(` is what ends a
;; match.
LOPFDV:
    ldy #$1

;; Inherit: <LOPFDV>
NMLOOP:
    dey
    lda (TMPPTR),Y
    iny
    iny                                     ; the entry's name starts at offset 2
    cmp #'A'+$20
    bcc NOT2SML
    cmp #'Z'+$21
    bcs CHKTYP
    sbc #$1F                                ; carry clear: subtracts $20

;; Inherit: <LOPFDV>
NOT2SML:
    cmp (LOWTR),Y
    beq NMLOOP

;; The entry matches when its type byte is here and the name's length agrees.
CHKTYP:
    lda VALTYP
    cmp (LOWTR),Y
    bne NOGOT
    iny
    cpy VARNAM+1
    beq GOTARY

;; Steps LOWTR past this entry, by its two-byte length, and searches on.
NOGOT:
    ldy #$0
    lda (LOWTR),Y
    clc
    adc LOWTR
    tax
    iny
    lda (LOWTR),Y
    adc LOWTR+1
    ldy LOWTRB
    jsr FIXADC
    jmp LOPFDA                              ; always

;; Ends the statement with BAD SUBSCRIPT.
BSERR:
    ldx #ERRBS
    .byte 44                                ; BIT abs, which skips FCERR's LDX

;; Ends the statement with ILLEGAL QUANTITY.
FCERR:
    ldx #ERRFC

;; Ends the statement with the error in X.
ERRGO3:
    jmp ERROR

;; Found the array: in DIM, a REDIM'D ARRAY error; otherwise checks the count of subscripts and finds the element.
;;
;; With SUBFLG set it returns with carry set and LOWTR at the entry, for a statement that names a whole array; nothing
;; in this BASIC sets it here.
GOTARY:
    ldx #ERRDD
    lda DIMFLG
    bne ERRGO3
    lda SUBFLG
    beq GOGETM
    sec
    rts

;; Checks that the array has as many dimensions as there are subscripts (BAD SUBSCRIPT otherwise), then finds the
;; element.
;; See: <GETDEF>
GOGETM:
    clc
    lda #$0
    jsr FMPTR2                              ; ARYPNT: the count of dimensions
    lda COUNT
    ldy #0
    cmp (ARYPNT),Y
    bne BSERR
    jmp GETDEF

;; Not found. From an expression (DORES set), the array is not made: the subscripts are dropped and VARPNT points to
;; <ZERO>, so the element reads as zero or an empty string.
;; See: <NOTFF2>
NOTFFD:
    lda DORES
    beq NOTFF2
    lda #<(ZERO)
    ldy #>(ZERO)
    sta VARPNT
    sty VARPNT+1

;; Drops a subscript from the stack.
NOTFONE:
    pla
    pla
    dec COUNT
    bne NOTFONE
    lda #0                                  ; ZERO's bank
    jmp DIMRTS2

;; Makes the array at VARTAB, the array table's end, moving the simple variable table up to make room.
;;
;; Each dimension's size is its subscript plus 1 in DIM, or 11 otherwise; the size of the whole entry is the element
;; size times every dimension's size, plus the head: the length, the name, the type, the count and the sizes. More
;; than 64K is OUT OF MEMORY. The sizes stay on the stack; B3UDEFI writes the entry.
;; In: LOWTR = VARTAB, COUNT = the count of subscripts, on the stack
;; Errors: ERROM = 64K or more, or no room
;; See: <UMULT>, <BLTU>
NOTFF2:
    lda COUNT
    sta INDEX+1                             ; the dimensions left
    ldy #$0
    sty CURTOL+1
    ldy VARNAM
    sty CURTOL                              ; the element's size
    tsx                                     ; reads the subscripts in place

;; Multiplies CURTOL by each dimension's size.
SIZLOP:
    lda #$0
    ldy #$A                                 ; not DIM: 10, the highest subscript
    bit DIMFLG
    bvc NOTDIM
    inx
    lda $100,X                              ; DIM: the subscript's low byte
    inx
    tay
    lda $100,X                              ; and high byte

;; Inherit: <SIZLOP>
NOTDIM:
    stx INDEX
    tax
    iny                                     ; the size is one more than the highest subscript
    bne NOVFLW
    inx

;; Inherit: <SIZLOP>
NOVFLW:
    jsr UMULT
    stx CURTOL
    sty CURTOL+1
    ldx INDEX
    dec INDEX+1
    bne SIZLOP
    lda COUNT
    asl
    sec                                     ; the count byte
    adc VARNAM+1                            ; the name, its length bytes and type
    adc CURTOL                              ; the elements
    sta CURTOL
    bcc GOODIE
    iny
    bne ALGOOD
    jmp OMERR                               ; 64K or more

;; Inherit: <NOTFF2>
ALGOOD:
    clc
    sty CURTOL+1

;; Moves the simple variable table, from VARTAB to STREND, up by the entry's size, which moves STREND.
GOODIE:
    lda STREND
    sta HIGHTR
    adc CURTOL
    sta HIGHDS
    lda STREND+1
    sta HIGHTR+1
    adc CURTOL+1
    ldy STRENDB
    sty HIGHTRB
    jsr FIXADC
    sta HIGHDS+1
    tya
    sta HIGHDSB
    tax
    lda HIGHDS
    ldy HIGHDS+1
    jsr BLTU                                ; the code goes on in B3UDEFI
