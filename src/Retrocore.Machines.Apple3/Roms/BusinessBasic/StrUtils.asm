; STRUTILS: string space. GETSPA to make room for a string, the garbage collector that packs the strings together,
; CONCAT, and the routines that free a temporary string and find a string from its descriptor.
;
; Strings live between FRETOP and HIMEM, growing down from HIMEM. Each string has three information bytes just above
; its characters: a type (0 for free space, TEMPTYP for a temporary, SIMTYP for a simple variable's, ARYTYP for an
; array element's), then for a string in use where its descriptor is, relative to VARTAB or ARYTAB; free space holds
; 0 and its length instead. A descriptor is three bytes: the string's length, then the string's distance below
; HIMEM, low byte first, so that strings can move without their descriptors pointing into another bank.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Getting space
; ---------------------------------------------------------------------------------------------------------------------

;; Takes room for a string of A characters, and its information bytes, from the bottom of string space.
;;
;; When the room would reach <STREND>, or the strings would take more than 64K below <HIMEM>, the garbage collector
;; packs them and <GETSPA> tries again; when that is not enough, it asks SOS for more memory with <EXPAND> before
;; collecting again, until <EXPAND> ends the statement with OUT OF MEMORY. An empty string takes no room, and returns at
;; once.
;; In: A = the length
;; Out: X, Y = the room's address, FRESPC, FRESPC+1, FRESPCB = the room, HIGHDS = its information bytes,
;;   A = the length
;; See: <GARBA2>, <STRINI>
GETSPA:
    lsr GARBFL                              ; not collected yet
    and #$FF
    beq STRRT2                              ; nothing to take for an empty string
    pha

;; Tries again to take the room for the length on the stack.
TRYAG0:
    lda FRETOP
    ldy FRETOP+1
    ldx FRETOPB
    sec
    sbc #INFOSIZ
    bcs TRYAG1
    jsr FIXXY

;; Keeps the information bytes' address and takes the characters' room below them.
TRYAG1:
    sty HIGHDS+1
    stx HIGHDSB
    sta HIGHDS
    pla
    pha
    eor #255                                ; HIGHDS less the length
    sec
    adc HIGHDS
    bcs TRYAG4
    jsr FIXXY

;; Collects garbage when the room would reach STREND.
TRYAG4:
    cpx STRENDB
    bcc GARBAG
    bne TRYAG5
    cpy STREND+1
    bcc GARBAG
    bne TRYAG5
    cmp STREND
    bcc GARBAG

;; Takes the room, unless string space would grow past 64K below <HIMEM>, two banks.
TRYAG5:
    sta FRESPC
    sty FRESPC+1
    stx FRESPCB
    pha
    clc
    sbc HIMEM
    tya
    sbc HIMEM+1
    txa
    sbc HIMEMB
    clc
    adc #2
    pla
    bcc GARBAG
    stx FRETOPB
    sta FRETOP
    sty FRETOP+1
    ldx FRESPC
    ldy FRESPC+1
    pla

;; An RTS for <GETSPA>.
STRRT2:
    rts

;; Packs the strings and tries again; the second time round, first asks SOS for more memory.
;;
;; The LDX of OUT OF MEMORY is never used: <EXPAND> reports the error itself.
GARBAG:
    ldx #ERROM
    bit GARBFL                              ; collected already?
    bpl GARBA1
    lda #4
    jsr EXPAND

;; Packs the strings, then tries <GETSPA> again.
GARBA1:
    jsr GARBA2
    lda #$80
    sta GARBFL
    bne TRYAG0                              ; always

; ---------------------------------------------------------------------------------------------------------------------
; The garbage collector
; ---------------------------------------------------------------------------------------------------------------------

;; Packs the strings in use up against <HIMEM>, so that the free space is all below them, and sets <FRETOP> to the
;; lowest string.
;;
;; It walks string space down from HIMEM, a string at a time by its information bytes. Each run of strings in use
;; moves up with <BLTUC> over the free space found above it; <GRBPNT> counts the free bytes so far, and each string's
;; descriptor has its distance below HIMEM reduced by that count.
;; Uses: A, X, Y, TEMP, CNTDIGS, INPFLG, GRBPNT, HEADER, DECCNT, ANYNUM, HIGHDS, HIGHTR, LOWTR
;; See: <GETSPA>, <GFINDTEMP>
GARBA2:
    lda #0
    sta TEMP
    sta CNTDIGS
    sta INPFLG                              ; whether the last string was in use
    sta GRBPNT                              ; the free bytes found so far
    sta GRBPNT+1
    lda HIMEM
    ldx HIMEMB
    ldy HIMEM+1
    sta HIGHDS                              ; where the next string in use goes
    stx HIGHDSB
    sty HIGHDS+1
    jmp GSUBIN3                             ; always

;; Takes the string whose information bytes <DECCNT> points to: one in use has its descriptor adjusted, a free one adds
;; its length to GRBPNT.
GMOVPTR:
    ldy #0
    lda (DECCNT),Y                          ; the type
    sta TEMP
    iny
    lda (DECCNT),Y
    sta HEADER                              ; where the descriptor is
    iny
    lda (DECCNT),Y
    sta HEADER+1
    sta ANYNUM                              ; the length, for free space
    lda TEMP
    beq SUBYSAV                             ; free
    eor INPFLG
    and #01
    sta CNTDIGS                             ; set when free space ends here
    lda #1
    sta INPFLG
    lda TEMP
    cmp #TEMPTYP
    bne *+5
    jmp GFINDTEMP                           ; a temporary
    cmp #ARYTYP
    bcc GRELSIM                             ; a simple variable's
    lda ARYTAB+1                            ; an array element's
    pha
    lda ARYTABB
    pha
    lda ARYTAB
    bcs GARBREL                             ; always

;; Finds a simple variable's descriptor from VARTAB.
GRELSIM:
    lda VARTAB+1
    pha
    lda VARTABB
    pha
    lda VARTAB

;; Works out the descriptor's address from the base, <VARTAB> or <ARYTAB>, and the relative address in HEADER.
GARBREL:
    sec
    sbc HEADER
    sta HEADER
    pla
    tay
    pla
    ldx HEADER+1
    jsr FIXYAX
    sta HEADER+1
    tya
    sbc #$FE
    sta HEADERB
    ldy #0
    lda (HEADER),Y                          ; the string's length
    sta ANYNUM

;; Moves the string's descriptor up by <GRBPNT> bytes, closer to HIMEM.
GRBCMP2:
    ldy #1
    sec
    lda (HEADER),Y
    sbc GRBPNT
    sta (HEADER),Y
    iny
    lda (HEADER),Y
    sbc GRBPNT+1
    sta (HEADER),Y
    bcs SUBYS2                              ; always

;; Adds a free string and its information bytes to GRBPNT.
SUBYSAV:
    lda GRBPNT
    ldy GRBPNT+1
    clc
    adc ANYNUM
    bcc *+3
    iny
    clc
    adc #INFOSIZ
    bcc *+3
    iny
    sta GRBPNT
    sty GRBPNT+1
    lda INPFLG
    ora TEMP
    sta CNTDIGS                             ; set when strings in use end here
    lda #0
    sta INPFLG

;; Steps <DECCNT> down past the string's characters.
SUBYS2:
    lda DECCNT
    ldy DECCNT+1
    ldx DECCNTB
    sec
    sbc ANYNUM
    bcs GSUBINF
    jsr FIXXY
    stx DECCNTB
    sty DECCNT+1

;; Where free space and strings in use meet, marks the top of the run of strings to move, or moves the run.
GSUBINF:
    pha
    lda CNTDIGS
    beq GSUBIN2                             ; no change here
    lda TEMP
    beq GSUBIN1                             ; free space starts here
    lda FRESPC                              ; strings in use start here: the run's top
    sta HIGHTR
    lda FRESPCB
    sta HIGHTRB
    lda FRESPC+1
    sta HIGHTR+1
    jmp GSUBIN2                             ; always

;; Moves the run of strings in use, from <LOWTR> up to <HIGHTR>, to just under HIGHDS.
GSUBIN1:
    lda FRESPC
    sta LOWTR
    lda FRESPCB
    sta LOWTRB
    lda FRESPC+1
    sta LOWTR+1
    txa
    pha
    tya
    pha
    jsr BLTUC
    pla
    tay
    pla
    tax

;; Goes on to the next string down.
GSUBIN2:
    pla

;; Goes on to the string below A, Y and bank X, or ends at <FRETOP>, moving the last run of strings in use.
GSUBIN3:
    sta FRESPC
    sty FRESPC+1
    stx FRESPCB
    cpx FRETOPB
    bne GMOVCHK
    cpy FRETOP+1
    bne GMOVCHK
    cmp FRETOP
    bne GMOVCHK
    lda TEMP                                ; free space at the bottom?
    beq GRBDON
    lda FRETOP
    sta LOWTR
    stx LOWTRB
    sty LOWTR+1
    jmp GRBLTUC

;; Points <DECCNT> at the next string's information bytes.
GMOVCHK:
    sec
    sbc #INFOSIZ
    bcs GSUBIN4
    jsr FIXXY

;; Sets <DECCNT> and takes the next string.
GSUBIN4:
    stx DECCNTB
    sty DECCNT+1
    sta DECCNT
    jmp GMOVPTR

;; Moves the last run of strings in use up.
GRBLTUC:
    jsr BLTUC

;; Sets <FRETOP> to the lowest string, and ends the collection.
GRBDON:
    lda HIGHDS
    sta FRETOP
    lda HIGHDS+1
    sta FRETOP+1
    lda HIGHDSB
    sta FRETOPB
    rts

;; Finds the temporary descriptor in <TEMPST> that points to this string, and adjusts it; a temporary string that none
;; points to ends the statement with a VARIABLE error.
GFINDTEMP:
    lda #0
    sta HEADERB
    lda #<(TEMPST)
    ldx #>(TEMPST)
    sta HEADER
    stx HEADER+1

;; Tries the temporary descriptor at <HEADER>: is its string's end this string's information bytes?
GARBTEMP:
    cmp TEMPPT                              ; past the last temporary?
    beq NOTEMP
    ldy #0
    lda (HEADER),Y                          ; the length
    beq DVARTS                              ; empty
    sta ANYNUM
    iny
    iny
    lda (HEADER),Y                          ; the distance below HIMEM: the high byte
    tax
    dey
    lda HIMEM
    sec
    sbc (HEADER),Y                          ; and the low
    sta LOWTR
    lda HIMEM+1
    ldy HIMEMB
    jsr FIXYAX
    sta LOWTR+1
    sty LOWTRB
    lda LOWTR
    clc
    adc ANYNUM                              ; the string's end
    sta LOWTR
    ldy LOWTR+1
    ldx LOWTRB
    bcc *+6
    iny
    jsr FIXYX
    cpx DECCNTB
    bne DVARTS
    cpy DECCNT+1
    bne DVARTS
    cmp DECCNT
    bne DVARTS
    jmp GRBCMP2                             ; this one

;; Steps to the next temporary descriptor.
DVARTS:
    lda #STRSIZ
    clc
    adc HEADER
    sta HEADER
    jmp GARBTEMP

;; Ends the statement with a VARIABLE error: a temporary string that no temporary descriptor points to.
NOTEMP:
    ldx #ERRVA
    jmp ERROR

; ---------------------------------------------------------------------------------------------------------------------
; Concatenation
; ---------------------------------------------------------------------------------------------------------------------

;; Concatenates two strings into a new temporary string, freeing their temporaries.
;; In: ARGMO, ARGMO+1, ARGMOB = the left string's descriptor, FACMO, FACMO+1, FACMOB = the right string's
;; Out: FACMO, FACMO+1 = the new temporary descriptor
;; See: <STRINI>, <MOVINS>, <PUTNEW>
CONCAT:
    ldy #0
    lda (FACMO),Y
    clc
    adc (ARGMO),Y                           ; the two lengths
    bcc SIZEOK
    jsr CAT11
    ldx #ERRLS
    jmp ERROR

;; Takes room for the joined string, and copies the left string into it.
SIZEOK:
    jsr STRINI
    ldx ARGMO
    ldy ARGMO+1
    stx STRNG1
    sty STRNG1+1
    ldx ARGMOB
    stx STRNG1B
    jsr MOVINS
    clc
    adc FRESPC                              ; past the left string
    sta FRESPC
    bcc CAT10
    inc FRESPC+1
    lda FRESPC+1
    cmp #MAXPG
    bcc CAT10
    sbc #MAXPG-MINPG
    inc FRESPCB
    sta FRESPC+1

;; Copies the right string after it, frees both temporaries and makes the result's.
CAT10:
    ldx FACMO
    ldy FACMO+1
    stx STRNG1
    sty STRNG1+1
    ldx FACMOB
    stx STRNG1B
    jsr MOVINS
    jsr CAT11
    jmp PUTNEW

;; Frees the <FAC>'s and <ARG>'s strings, if they are the last temporaries.
;; See: <FRECNOW>, <FRETNOW>
CAT11:
    jsr FRECNOW
    lda ARGMO
    ldy ARGMO+1
    ldx ARGMOB
    jmp FRETNOW

; ---------------------------------------------------------------------------------------------------------------------
; Finding and freeing strings
; ---------------------------------------------------------------------------------------------------------------------

;; Turns <INDEX> from a distance below <HIMEM> into an address, or back: it is HIMEM less INDEX either way.
;; In: INDEX, INDEX+1, INDEXB = the address or the distance
;; Out: INDEX, INDEX+1, INDEXB = the other
;; Uses: YSAVE
;; Keeps: A, X, Y
MAKREL:
    pha
    lda HIMEM
    sec
    sbc INDEX
    sta INDEX
    lda HIMEM+1
    sty YSAVE
    ldy HIMEMB
    sbc INDEX+1
    jsr FIXSBC
    sta INDEX+1
    tya
    sbc INDEXB
    sta INDEXB
    ldy YSAVE
    pla
    rts

;; Copies the string whose descriptor <STRNG1> points to into the room at FRESPC.
;; In: STRNG1, STRNG1+1, STRNG1B = the descriptor's address
;; Out: A = the length
;; See: <MOVDO>
MOVINS:
    ldy #0
    lda (STRNG1),Y                          ; the length
    pha
    iny
    lda (STRNG1),Y
    tax
    iny
    lda (STRNG1),Y
    ldy #0
    jsr FIXYA
    sty INDEXB
    stx INDEX
    sta INDEX+1
    jsr MAKREL                              ; the string's address
    pla

;; Copies A bytes from <INDEX> to <FRESPC>, last byte first.
;; In: A = the count, INDEX = the source
;; Out: A = the count, Y = 0
MOVDO:
    tay
    beq MVSTRT
    pha

;; Copies one byte, for <MOVDO>.
MOVLP:
    dey
    lda (INDEX),Y
    sta (FRESPC),Y
    tya
    bne MOVLP
    pla

;; An RTS for <MOVDO>.
MVSTRT:
    rts

;; Frees the temporary descriptor of the <FAC>'s string, if it is the last temporary, and finds the string, returning
;; as <FRETMP> does.
;; See: <FRETMP>
FREFAC:
    lda FACMO
    ldx FACMOB
    ldy FACMO+1

;; Frees a temporary descriptor, if it is the last one made, and finds its string.
;;
;; The string's own space is freed only by <FRENOW>, when the zero flag says the descriptor was freed.
;; In: A, Y = the descriptor's address, X = its bank
;; Out: A = the length, X, Y = the string's address, INDEX, INDEX+1, INDEXB = the string,
;;   zero = set when the descriptor was the last temporary and is now free
;; See: <FRETMS>, <NOTNOW>
FRETMP:
    sta INDEX
    stx INDEXB
    sty INDEX+1
    jsr FRETMS

;; Finds the string whose descriptor <INDEX> points to.
;; In: INDEX, INDEX+1, INDEXB = the descriptor's address
;; Out: A = the length, X, Y = the string's address, INDEX, INDEX+1, INDEXB = the string
NOTNOW:
    php                                     ; FRETMS's zero flag, for the caller
    ldy #0
    lda (INDEX),Y                           ; the length
    pha
    iny
    lda (INDEX),Y
    tax
    iny
    lda (INDEX),Y
    ldy #0
    jsr FIXYA
    sty INDEXB
    sta INDEX+1
    stx INDEX
    jsr MAKREL
    ldx INDEX
    ldy INDEX+1
    pla
    plp
    rts

;; Finds the <FAC>'s string again and frees its space when the zero flag says to.
;; In: zero = set to free it
;; See: <FRENOW>
FREFC1:
    php
    jsr FREFAC
    plp

;; Frees a string's space, when the zero flag says its temporary descriptor was freed.
;; In: zero = set to free it, A = the length, INDEX = the string
;; See: <FRESPA>
FRENOW:
    bne FRERTS

;; Marks a string's space free, unless the string is empty.
;; In: A = the length, INDEX = the string
;; See: <TSTFRE>
FRESPA:
    cmp #0
    beq FRERTS
    jmp TSTFRE

;; Frees the temporary descriptor at A, Y, if it is the last one made.
;; In: A, Y = the descriptor's address
;; Out: zero = set when it was freed
FRETMS:
    pha
    lda #<(TEMPST)
    cmp TEMPPT                              ; any temporaries?
    pla
    bcc *+5
    lda #$FF                                ; none: zero clear
    rts
    cpy LASTPT+1                            ; the last one?
    bne FRERTS
    cmp LASTPT
    bne FRERTS
    sta TEMPPT
    sbc #STRSIZ
    sta LASTPT
    ldy #0                                  ; zero set: freed

;; An RTS for the routines that free strings.
FRERTS:
    rts

;; Finds the <FAC>'s string from its descriptor, without freeing anything, returning as <NOTNOW> does.
NOTFAC:
    lda FACMO
    ldy FACMO+1
    ldx FACMOB

;; Finds the string whose descriptor is at A, Y and bank X, without freeing anything, returning as <NOTNOW> does.
NOTNW2:
    sta INDEX
    sty INDEX+1
    stx INDEXB
    jmp NOTNOW
