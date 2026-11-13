; INVOKE1: the INVOKE statement, which finds a segment for the modules and loads them; the SOS memory calls'
; parameter lists; and SCRUNCH and EXPAND, which give BASIC's free memory back to SOS and take it again.
;
; BASIC's program and data live in one segment, ID $11, that <TRYSEG> takes at start; invoked modules live in
; another, ID $12, in one bank. Addresses here are BASIC's form: an offset in a bank, its page from $02 to $81, with
; the bank byte beside it.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; INVOKE
; ---------------------------------------------------------------------------------------------------------------------

;; INVOKE: replaces the invoked modules with the ones the statement names, or with none.
;;
;; Gives all free memory back to SOS with <SCRUNCH> and releases the old modules' segment. Each file is then opened
;; once to add up its size, less its first block; a segment of that many pages and one more is found in one bank,
;; <DOINVO> loads the modules into it, and the pages they leave unused are given back from its base. <EXPAND> then
;; takes back as much memory as SOS gives.
;; In: TXTPTR = the file names, separated by commas, or the statement's end
;; See: <DOINVO>, <SEGTAB2>, <PERFIND>
INVOKE:
    lda #0                                  ; not RUN or CHAIN
    sta CMDFLG
.if VERSION >= 130
    jsr SETPROG                             ; 1.3: use the program's prefix
.endif
    lda #0
    jsr SCRUNCH                             ; all the free memory back to SOS
    lda a:SEGNUMB
    beq INVOK1                              ; nothing invoked yet
    brk
    .byte MRLS
    .word SEGTAB1

;; Loads the modules named, or with no name releases them all.
INVOK1:
    jsr CHRGOT
    bne INVOK3
    jmp INVEXP2

;; Adds up the files' sizes, in pages, in <BANKPNT> (pages) and BANKPNT+1 (bytes).
INVOK3:
    lda #0
    sta BANKPNT
    sta BANKPNT+1
    jsr SVTXT                               ; to read the names again

;; Opens the next file, adds its size less the first block, and closes it again.
;;
;; Opening it now, before the segment is found, lets SOS find room for the file's buffer.
INVOK4:
    lda #1                                  ; to read
    ldx #PCODTYP                            ; a code file
    jsr OPENIT
    lda FEOF                                ; the file's size, from OPENIT
    clc
    adc BANKPNT+1
    sta BANKPNT+1
    lda FEOF+1
    adc BANKPNT
    bcs INVERR1
    sec
    sbc #2                                  ; less the first block
    bcc INVERR1
    sta BANKPNT
    jsr CLSEND
    jsr CHRGOT
    beq *+8                                 ; the last name
    jsr CHKCOM
    jmp INVOK4
    ldx BANKPNT                             ; one more page, for the bytes past the last
    inx
    beq INVERR1
    stx a:PGCNT2
    ldx #0
    stx a:PGCNT2+1
    jsr RSTTXT
    brk
    .byte MFND                              ; a segment in one bank
    .word SEGTAB2
    bne INVERR1
    lda a:SEGNUM2
    sta a:SEGNUMB
    sta a:SEGNUM3
    lda a:BASPTR
    ora #$80                                ; the bank as an X-byte
    sta INVBNK
    tay
    lda a:BASPTR+1                          ; SOS's page, $20-$9F, less $20
    sec
    sbc #$20
    jsr FIXSBC
    sta INVTAB+1
    sty INVTABB
    sty PROCTABB
    lda a:LIMPTR
    ora #$80
    tay
    lda a:LIMPTR+1
    sec
    sbc #$20
    jsr FIXSBC
    cpy INVTABB
    beq *+5
    clc
    adc #MAXPG-MINPG                        ; in the next bank: count it from the base's
    sta PROCTAB+1
    lda #0
    sta PROCTAB
    sta INVTAB
    jsr DOINVO
    lda INVPNT                              ; the whole pages left below the records
    cmp INVTAB
    lda INVPNT+1
    sbc INVTAB+1
    and #$7F
    beq INVEXP1
    sta a:PGECNT                            ; give them back from the segment's base
    lda INVTAB+1
    clc
    adc a:PGECNT
    sta INVTAB+1
    lda #0
    sta a:PGECNT+1
    lda INVPNT
    sta INVTAB
    brk
    .byte MCHG
    .word SEGTAB3

;; Takes back all the memory SOS gives, and ends the statement.
INVEXP1:
    lda #0
    jmp EXPAND

;; Marks nothing invoked, then takes the memory back.
INVEXP2:
    lda #0
    sta a:SEGNUMB
    beq INVEXP1                             ; always

; ---------------------------------------------------------------------------------------------------------------------
; BASIC's own segment
; ---------------------------------------------------------------------------------------------------------------------

;; Finds the largest free segment for BASIC's program and data, anywhere in memory, and sets <RAMLOC> and <MEMSIZ>
;; from it.
;;
;; The first FIND_SEG asks for $FFFF pages, which fails, and SOS leaves the most it can give in the count; the second
;; asks for that.
;; Out: RAMLOC = the segment's start plus 1, MEMSIZ = its end
;; See: <SEGTAB7>, <INIT>
TRYSEG:
    brk
    .byte MFND
    .word SEGTAB7
    bne TRYSEG
    lda a:SEGNUM7
    sta a:SEGNUM5
    sta a:SEGNUM6                           ; for SCRUNCH and EXPAND
    ldy #0
    sty MEMSIZ
    iny
    sty RAMLOC
    lda a:BASBNK
    ora #$80
    tay
    lda a:BASBNK+1
    sec
    sbc #$20
    jsr FIXSB2                              ; into BASIC's range, $02-$81
    sta RAMLOC+1
    sty RAMLOCB
    lda a:LIMBNK
    ora #$80
    tay
    lda a:LIMBNK+1
    sec
    sbc #$1F                                ; the page after the limit
    jsr FIXSB2
    sta MEMSIZ+1
    sty MEMSIZB
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The SOS memory calls' parameter lists
; ---------------------------------------------------------------------------------------------------------------------

;; RELEASE_SEG's parameter list for the invoked modules' segment.
;; See: <INVOKE>
SEGTAB1:
    .byte 1

;; The invoked modules' segment number, 0 when nothing is invoked.
SEGNUMB:
    .byte 0

;; FIND_SEG's parameter list for the invoked modules: search mode 0 (within one bank), segment ID $12 and <PGCNT2>
;; pages; SOS returns the base, the limit and the segment number.
SEGTAB2:
    .byte 6
    .byte 0
    .byte $12

;; The pages the invoked modules need.
PGCNT2:
    .word 1

;; The modules' segment's base: its bank, then its page.
BASPTR:
    .word 0

;; The modules' segment's limit: its bank, then its page.
LIMPTR:
    .word 0

;; The modules' segment number, from FIND_SEG.
SEGNUM2:
    .byte 0

;; CHANGE_SEG's parameter list that gives the modules' unused pages back from the segment's base (mode 0).
SEGTAB3:
    .byte 3

;; The modules' segment number, for <SEGTAB3>.
SEGNUM3:
    .byte 0
    .byte 0                                 ; mode 0: move the base up

;; The pages <SEGTAB3> gives back.
PGECNT:
    .word 0

;; REQUEST_SEG's parameter list that reserves bank 0's $2000-$21FF (segment ID $13), which BASIC's bank-switched
;; pointers can't reach.
;; See: <INIT>
SEGTAB4:
    .byte 4
    .byte 0                                 ; the base: bank 0, page $20
    .byte $20
    .byte 0                                 ; the limit: bank 0, page $21
    .byte $21
    .byte $13

;; The reserved segment's number.
SEGNUM4:
    .byte 0

;; CHANGE_SEG's parameter list that gives pages back from the top of BASIC's segment (mode 3), for <SCRUNCH>.
SEGTAB5:
    .byte 3

;; BASIC's segment number, set by <TRYSEG>.
SEGNUM5:
    .byte $11
    .byte 3                                 ; mode 3: move the limit down

;; The pages <SCRUNCH> gives back.
SEGSIZ5:
    .word 0

;; CHANGE_SEG's parameter list that adds pages to the top of BASIC's segment (mode 2), for <EXPAND>.
SEGTAB6:
    .byte 3

;; BASIC's segment number, set by <TRYSEG>.
SEGNUM6:
    .byte $11
    .byte 2                                 ; mode 2: move the limit up

;; The pages <EXPAND> asks for; when SOS can't give them, it leaves the most it can here.
SEGSIZ6:
    .word 0

;; FIND_SEG's parameter list for BASIC's program and data: search mode 2 (across banks), segment ID $11 and $FFFF
;; pages, which fails and leaves the largest count SOS can give.
;; See: <TRYSEG>
SEGTAB7:
    .byte 6
    .byte 2
    .byte $11
    .byte $FF
    .byte $FF

;; BASIC's segment's base: its bank, then its page.
BASBNK:
    .word 0

;; BASIC's segment's limit: its bank, then its page.
LIMBNK:
    .word 0

;; BASIC's segment number, from FIND_SEG.
SEGNUM7:
    .byte 0

;; GET_PREFIX's parameter list, into <CATBUF>+1, for PREFIX$ and 1.3's prefix handling.
;; See: <PREFIXS>
PREFTAB:
    .byte 2
    .word CATBUF+1
    .byte <(BUF-CATBUF-4)

;; GET_TIME's parameter list, into <CATBUF>+2, for DATE$ and TIME$.
;; See: <DATES>, <TIMES>
DATETAB:
    .byte 1
    .word CATBUF+2

;; SET_PREFIX's parameter list, from the pathname in <NAMBUF>, for PREFIX$ =.
;; See: <PREFIXSET>
PREFTB2:
    .byte 1
    .word NAMBUF

;; GET_PREFIX's parameter list, into <NAMBUF>, up to 128 bytes, for CATALOG.
;; See: <CATALOG>
PREFTB3:
    .byte 2
    .word NAMBUF
    .byte 128

; ---------------------------------------------------------------------------------------------------------------------
; Giving memory back to SOS and taking it again
; ---------------------------------------------------------------------------------------------------------------------

;; Gives free memory back to SOS: moves the strings and buffers, from <FRETOP> to <HIMEM>, down by A pages, or by all
;; the free space when A is 0, and shrinks BASIC's segment by as much.
;;
;; The strings' garbage is collected first, so the free space runs from <STREND> to FRETOP. DELTA is zero, so the
;; move adjusts no pointers. With no free page it is an out-of-memory error, and a CHANGE_SEG that fails ends the
;; statement with SOS's error.
;; In: A = the pages, 0 for all the free space; more than there are gives all of it
;; See: <EXPAND>, <SEGTAB5>
SCRUNCH:
    pha
    jsr GARBA2
    pla
    tax
    lda FRETOP                              ; the free space, in pages and banks
    cmp STREND
    lda FRETOP+1
    sbc STREND+1
    sta INDEX2
    lda FRETOPB
    sbc STRENDB
    sta INDEX2+1
    asl INDEX2                              ; banks are 128 pages: make it a count of pages
    lsr INDEX2+1
    ror INDEX2
    txa
    beq SCRUN1                              ; all of it
    ldx INDEX2+1
    bne SCRUN0                              ; 256 pages or more: A is fewer
    cmp INDEX2
    bcs SCRUN1                              ; A is more: all of it
SCRUN0:
    sta INDEX2
    lda #0
    sta INDEX2+1

;; Moves the strings and buffers down by <INDEX2> pages and gives the pages to SOS.
SCRUN1:
    lda INDEX2
    ora INDEX2+1
    bne *+5
    jmp OMERR                               ; no free page
    lda INDEX2
    asl                                     ; HEADER = the count as pages and banks
    tax
    lda INDEX2+1
    rol
    sta HEADER+1
    txa
    lsr
    sta HEADER
    lda FRETOP
    sta INDEX1
    sta LOWTR
    lda FRETOP+1
    sta INDEX1+1
    ldy FRETOPB
    sty INDEX1B
    sec
    sbc HEADER
    jsr FIXSBC
    sta LOWTR+1                             ; LOWTR = where the strings go
    tya
    sbc HEADER+1
    sta LOWTRB
    lda STREND
    pha
    lda STREND+1
    pha
    lda STRENDB
    pha
    lda HIMEM                               ; MVDWN moves up to STREND: here, HIMEM
    sta STREND
    lda HIMEM+1
    sta STREND+1
    lda HIMEMB
    sta STRENDB
    lda #0
    sta DELTA
    sta DELTA+1
    sta DELTAB
    jsr MVDWN
    pla
    sta STRENDB
    pla
    sta STREND+1
    pla
    sta STREND
    lda LOWTR
    sta FRETOP
    lda LOWTR+1
    sta FRETOP+1
    lda LOWTRB
    sta FRETOPB
    lda HIMEM+1
    ldy HIMEMB
    sec
    sbc HEADER
    jsr FIXSBC
    sta HIMEM+1
    tya
    sbc HEADER+1
    sta HIMEMB
    lda INDEX2
    sta SEGSIZ5
    lda INDEX2+1
    sta SEGSIZ5+1
    brk
    .byte MCHG
    .word SEGTAB5
    beq *+5
    jmp SERROR
    rts

;; Takes memory back from SOS: grows BASIC's segment by A pages, or by as many as SOS gives when A is 0, and moves the
;; strings and buffers up to the new top.
;;
;; When SOS can't give the pages asked for, the call is made again for the count SOS leaves in <SEGSIZ6>, until it
;; works. When SOS gives none, it is an out-of-memory error if A was not 0.
;; In: A = the pages, 0 for as many as SOS gives
;; See: <SCRUNCH>, <SEGTAB6>
EXPAND:
    ldy #0
    tax
    bne EXPAN0
    ldy #15                                 ; A is 0: ask for $FFF pages
    lda #255
EXPAN0:
    sta SEGSIZ6
    sty SEGSIZ6+1

;; Grows BASIC's segment by <SEGSIZ6> pages, trying again with SOS's count until it works.
EXPAN1:
    brk
    .byte MCHG
    .word SEGTAB6
    bne EXPAN1
    lda SEGSIZ6
    ora SEGSIZ6+1
    bne EXPAN2
    tya                                     ; none: Y is nonzero when A was 0
    bne *+5
    jmp OMERR
    rts

;; Moves the strings and buffers up by the pages SOS gave, to the new <HIMEM>.
EXPAN2:
    lda HIMEM
    sta HIGHTR
    sta HIGHDS
    clc
    lda HIMEM+1
    sta HIGHTR+1
    ldy HIMEMB
    sty HIGHTRB
    adc SEGSIZ6
    jsr FIXADC
    sta HIMEM+1
    sta HIGHDS+1
    tya
    adc SEGSIZ6+1
    adc SEGSIZ6+1                           ; twice: each 256 pages is two banks
    sta HIMEMB
    sta HIGHDSB
    lda FRETOP
    sta LOWTR
    lda FRETOP+1
    sta LOWTR+1
    lda FRETOPB
    sta LOWTRB
    jsr BLTUC
    lda HIGHDS
    sta FRETOP
    lda HIGHDS+1
    sta FRETOP+1
    lda HIGHDSB
    sta FRETOPB
    rts
