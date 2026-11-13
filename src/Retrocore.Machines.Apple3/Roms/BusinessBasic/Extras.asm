; EXTRAS: statements Business BASIC adds to Applesoft's: OUTREC, INDENT, HPOS and VPOS as statements, NORMAL,
; INVERSE, TRACE and NOTRACE, ON ERR and RESUME, ON KBD, ON EOF# and OFF, DELETE, TEXT and HOME, with the routines
; that test for two-byte tokens and that send a program to its ON KBD or ON EOF# handler.
;
; ON KBD and ON EOF# keep their handlers in EOFPTRS and EOFLINS, three bytes and two each, by number: 1 to 10 for
; the files #1 to #10, 11 for the keyboard. A handler is where its statement continues, as an offset from TXTTAB so
; it survives the program moving, and the line it is in. A zero first byte means no handler.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Screen and listing settings
; ---------------------------------------------------------------------------------------------------------------------

;; The `OUTREC = n` statement: sets <OUTREC>, LIST's right margin.
;; See: <CHKBYT>
SOUTREC:
    jsr CHKBYT
    stx OUTREC
    rts

;; The `INDENT = n` statement: sets <INDENT>, the spaces LIST indents each FOR loop by.
;; See: <CHKBYT>
SINDENT:
    jsr CHKBYT
    stx INDENT
    rts

;; Reads `=` and a number from 0 to 255.
;; Out: X = the number
;; Errors: SYNTAX without the `=`, ILLEGAL QUANTITY for a number out of range
CHKBYT:
    jsr CHKEQL
    jmp GETBYT

;; The `HPOS = n` statement: moves the cursor to column n, counting from 1, and records it in <TRMPOS>.
;; See: <HTABB>
HTAB:
    jsr HTABB
    sta TRMPOS                              ; The column, from 0
    rts

;; Ends with ILLEGAL QUANTITY, for TAB(0).
TOOBIG:
    jmp FCERR

;; Moves the cursor to the column after `=`, for <HTAB>.
;; Out: A = the column, counting from 0
;; See: <VTAB>
HTABB:
    lda #24                                 ; The console's code for a column
    .byte 44                                ; BIT abs, which skips VTAB's LDA

;; The `VPOS = n` statement: moves the cursor to line n, counting from 1.
;; See: <HTAB>
VTAB:
    lda #25                                 ; The console's code for a line
    pha
    jsr CHKEQL
    jsr GETBYT
    pla

;; Sends a console code and its argument, counting from 1, which the console counts from 0.
;; In: A = the code, X = the argument
;; Out: A = the argument as sent
;; See: <DOITOUT>
VWINDER:
    jsr PRNACHAR
    txa
    jmp DOITOUT

;; The NORMAL statement: sets normal video.
SETNORM:
    lda #17                                 ; The console's code for normal video
    .byte 44                                ; BIT abs, which skips INVERSE's LDA

;; The INVERSE statement: sets inverse video.
INVERSE:
    lda #18                                 ; The console's code for inverse video
    jmp PRNACHAR

;; The TRACE statement: sets bit 7 of <TRFLAG>, so the statement fetcher prints each line's number as it runs.
;;
;; With anything after TRACE it changes nothing, and the statement fetcher reports SYNTAX. Apple's comment had this
;; the wrong way round.
;; See: <TRACEOFF>
SETTRACE:
    sec
    .byte $90                               ; BCC, never taken after SEC, which skips NOTRACE's CLC

;; The NOTRACE statement: clears bit 7 of <TRFLAG>.
;; See: <SETTRACE>
TRACEOFF:
    clc
    bne RTSBCK                              ; Something follows: leave it for SYNTAX
    ror TRFLAG

;; Returns from <SETTRACE> and <TRACEOFF>.
RTSBCK:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; ON ERR and RESUME
; ---------------------------------------------------------------------------------------------------------------------

;; The `ON ERR statements` statement: makes the statements after ERR, to the end of the line, the program's error
;; handler, then skips them.
;;
;; It keeps where they start in <ERRTO> (the address of the ERR token, with its bank in <ERRTOB>) and the line's
;; number in <ERRTO>+3 and +4, and sets bit 7 of <ERRFLG>. OFF ERR clears the bit; RUN, NEW, LOAD and editing the
;; program clear <ERRFLG>.
;; Errors: ILLEGAL DIRECT outside a program
;; See: <HNDLERR>, <ERROR>, <OFF>
ONERR:
    jsr ERRDIR
    lda TXTPTR
    sta ERRTO
    lda TXTPTR+1
    sta ERRTO+1
    lda TXTPTRB
    sta ERRTOB
    lda ERRFLG
    ora #$80
    sta ERRFLG
    lda CURLIN                              ; The line, for the handler to run in
    sta ERRTO+3
    lda CURLIN+1
    sta ERRTO+4
    jsr REMN                                ; Skip the handler for now
    jmp ADDON

;; Runs the ON ERR handler: <ERROR> comes here when bit 7 of <ERRFLG> is set.
;;
;; It puts the stack pointer back to <REMSTK>, where the failing statement started, so FOR and GOSUB entries stay;
;; keeps <OLDTXT>, the failing statement's start, in <ERRPOS> and <ERRPOSB> for RESUME; then sets <TXTPTR> and
;; <CURLIN> from <ERRTO> and goes on at the statement after ON ERR, through <DIRCON>. <ERROR> has already set
;; <ERRNUM> and <ERRLIN>. The handler stays in force.
;; See: <ONERR>, <RESUME>
HNDLERR:
    ldx REMSTK
    txs
    lda OLDTXT
    sta ERRPOS
    lda OLDTXT+1
    sta ERRPOS+1
    lda OLDTXTB
    sta ERRPOSB
    lda ERRTO
    sta TXTPTR
    lda ERRTO+1
    sta TXTPTR+1
    lda ERRTOB
    sta TXTPTRB
    lda ERRTO+3
    sta CURLIN
    lda ERRTO+4
    sta CURLIN+1
    jmp DIRCON

;; The RESUME statement: runs the statement that failed again, from <ERRPOS> in line <ERRLIN>.
;;
;; When no error has been handled (<ERRPOSB> zero) it does nothing.
;; Errors: ILLEGAL DIRECT outside a program
;; See: <HNDLERR>
RESUME:
    jsr ERRDIR
    lda ERRPOSB
    beq RSM2
    sta TXTPTRB
    lda ERRLIN
    sta CURLIN
    lda ERRLIN+1
    sta CURLIN+1
    lda ERRPOS
    sta TXTPTR
    lda ERRPOS+1
    sta TXTPTR+1

;; Returns from <RESUME>, to the statement fetcher.
RSM2:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Two-byte tokens
; ---------------------------------------------------------------------------------------------------------------------

;; Tests whether the program has a two-byte token, $FF and A, at <TXTPTR>, and steps over the $FF if so.
;; In: A = the token's second byte
;; Out: zero = set when found, with TXTPTR at the second byte, A = the character at TXTPTR
;; Keeps: X, Y
;; See: <MSTESC>
TRYESC:
    sty YSAVE
    ldy #1
    cmp (TXTPTR),Y
    bne TRY2
    dey
    lda (TXTPTR),Y
    cmp #$FF
    bne TRY2
    jsr CHRGET                              ; Step over the $FF
    lda #$00                                ; Found

;; Reads the character at <TXTPTR> again, keeping the flags.
TRY2:
    php
    jsr CHRGOT
    ldy YSAVE
    plp
    rts

;; Requires the two-byte token $FF and A next, and steps past it.
;; In: A = the token's second byte
;; Errors: SYNTAX when it is not there
;; See: <TRYESC>, <SYNCHR>
MSTESC:
    pha
    lda #$FF
    jsr SYNCHR
    pla
    jmp SYNCHR

; ---------------------------------------------------------------------------------------------------------------------
; ON KBD, ON EOF# and OFF
; ---------------------------------------------------------------------------------------------------------------------

;; The `ON KBD statements` statement: makes the statements after KBD the handler for a key pressed while the
;; program runs, and turns the console's any-key event on.
;;
;; The handler is number 11 in <EOFPTRS>; <KEYHIT> calls it as a GOSUB.
;; Errors: ILLEGAL DIRECT outside a program
;; See: <ONEOF2>, <KEYHIT>, <OFFKBD>
ONKBD:
    jsr ERRDIR
    lda #1
    sta a:KBDKEY                            ; Priority 1
    brk                                     ; D_CONTROL: the any-key event on
    .byte SDCNT
    .word DKBD
    ldx #11
    bne ONEOF2

;; The `ON EOF#n statements` statement: makes the statements after the file number the handler for reaching the
;; end of file #n.
;;
;; <CHKEOF> goes to it as a GOTO.
;; Errors: ILLEGAL DIRECT outside a program
;; See: <ONEOF2>, <CHKEOF>, <OFFEOF>
ONEOF:
    jsr CHRGET
    jsr ERRDIR
    jsr GTFLNO
    inx                                     ; The file's number, from 1
    jsr DECTPT                              ; Back to the character before the statements

;; Records handler X: where the statements start, relative to <TXTTAB>, in <EOFPTRS>, and the line in <EOFLINS>;
;; then skips the statements.
;; In: X = the handler's number, 1 to 11
ONEOF2:
    txa
    sta YSAVE
    asl                                     ; Three bytes each
    adc YSAVE
    tax
    jsr RELTXT
    lda TXTPTR
    sta EOFPTRS-2,X
    lda TXTPTR+1
    sta EOFPTRS-1,X
    lda TXTPTRB
    sta EOFPTRS-3,X
    jsr RELTXT                              ; Back to an address
    lda CURLIN
    sta EOFLINS-3,X
    lda CURLIN+1
    sta EOFLINS-2,X
    jsr REMN                                ; Skip the handler for now
    jmp ADDON

;; Turns <TXTPTR> into an offset from <TXTTAB>, or such an offset back into an address.
;;
;; It replaces <TXTPTR> with <TXTTAB> less <TXTPTR>, which undoes itself when done twice.
;; Uses: A, Y
RELTXT:
    sec
    lda TXTTAB
    sbc TXTPTR
    sta TXTPTR
    lda TXTTAB+1
    sbc TXTPTR+1
    ldy TXTTABB
    jsr FIXSBC
    sta TXTPTR+1
    tya
    sbc TXTPTRB
    sta TXTPTRB
    rts

;; The OFF statement: `OFF KBD`, `OFF EOF#n` or `OFF ERR` turns that handler off.
;;
;; Any other word after OFF is ignored here, and left for the statement fetcher.
;; In: A = the token after OFF
;; See: <OFFKBD>, <OFFEOF>
OFF:
    pha
    jsr CHRGET
    pla
    cmp #KBDTK
    beq OFFKBD
    cmp #EOFTK
    beq OFFEOF
    cmp #ERRTK
    bne RTS999
    lda ERRFLG                              ; OFF ERR
    and #$7F
    sta ERRFLG

;; Returns from <OFF>.
RTS999:
    rts

;; Turns ON KBD off: turns the console's any-key event off and clears handler 11.
;; See: <ONKBD>
OFFKBD:
    lda #0
    sta a:KBDKEY
    brk                                     ; D_CONTROL: the any-key event off
    .byte SDCNT
    .word DKBD
    ldx #11
    bne OFFEOF2

;; Turns ON EOF#n off.
;; See: <ONEOF>
OFFEOF:
    jsr GTFLNO
    inx

;; Clears handler X in <EOFPTRS>.
;; In: X = the handler's number, 1 to 11
OFFEOF2:
    txa
    sta YSAVE
    asl
    adc YSAVE
    tax
    lda #0
    sta EOFPTRS-2,X
    sta EOFPTRS-1,X
    sta EOFPTRS-3,X
    rts

;; Goes to the ON EOF# handler of the file in <SVFLNO>, which reached its end, or ends with OUT OF DATA when it has
;; none.
;;
;; It keeps the file's number, from 1, in <EOFSV> for the EOF function, puts the stack pointer back to <REMSTK>, sends
;; output back to the OUTPUT# device, and goes on at the handler's statements in its line, through <GONE>.
;; In: SVFLNO = the file's number, from 0
;; See: <ONEOF>, <DSKEOF>
CHKEOF:
    inc SVFLNO
    lda SVFLNO
    sta EOFSV
    asl
    adc SVFLNO
    ldx REMSTK                              ; The stack as the statement started
    txs
    tax

;; Goes to handler X/3 in <EOFPTRS>, or ends with OUT OF DATA when there is none.
;; In: X = three times the handler's number
CKEOF2:
    lda FILNO+1
    sta FILNO
    lda EOFPTRS-3,X
    beq GIVOD                               ; No handler
    sta TXTPTRB
    lda EOFPTRS-2,X
    sta TXTPTR
    lda EOFPTRS-1,X
    sta TXTPTR+1
    lda EOFLINS-3,X
    sta CURLIN
    lda EOFLINS-2,X
    sta CURLIN+1
    jsr RELTXT                              ; Back to an address
    jmp GONE

;; Ends with OUT OF DATA.
GIVOD:
    ldx #ERROD
    jmp ERROR

;; Calls the ON KBD handler as a GOSUB: the statement fetcher comes here when bit 7 of <KEYSTROK> says the
;; any-key event saw a key.
;;
;; It clears the bit and pushes a GOSUB entry, so RETURN goes back to the statement that was next.
;; See: <ONKBD>, <KBDEVNT>, <DIRCON>
KEYHIT:
    lda KEYSTROK
    and #$7F
    sta KEYSTROK
    jsr PSHTXT4
    ldx #EOFSIZ                             ; Handler 11
    bne CKEOF2                              ; Always

; ---------------------------------------------------------------------------------------------------------------------
; DELETE
; ---------------------------------------------------------------------------------------------------------------------

;; Ends with SYNTAX, for <DELETE>.
BLOWDEL:
    jmp SNERR

;; The `DELETE first[,last]` statement: deletes a line, or the lines from first to last, from the program.
;;
;; A comma, `-` or TO may separate the numbers. Run from a program, it may delete only lines after the one it is in.
;; The program's end, the variables and the arrays move down with <MVDWN>, so the variables keep their values;
;; <FLOAD> then resets the DATA pointer and the stack. When the range holds no lines it does nothing.
;; Errors: SYNTAX without a line number, RANGE for a line at or before the current one
;; See: <FNDLIN>, <MVDWN>
DELETE:
    bcs BLOWDEL                             ; Not a digit
    jsr LINGET
    jsr FNDLIN                              ; The first line to delete
    ldx CURLIN+1
    inx
    beq RNGOK                               ; Direct: any line
    lda CURLIN
    cmp LINNUM
    lda CURLIN+1
    sbc LINNUM+1
    bcc RNGOK

;; Ends with RANGE.
RNGERR:
    ldx #ERRNG
    jmp ERROR

;; Reads the range's end for <DELETE> and deletes the lines.
RNGOK:
    lda LOWTR
    pha
    lda LOWTR+1
    pha
    lda LOWTRB
    pha
    jsr CHRGOT
    beq JSONEL                              ; One line
    cmp #','
    beq DELOK
    cmp #'-'
    beq DELOK
    lda #TOTK
    jsr TRYESC
    bne BLOWDEL

;; Reads the last line's number.
DELOK:
    jsr CHRGET
    bcs BLOWDEL                             ; Not a digit
    jsr LINGET

;; Finds the first line after the range, and moves what follows it down to the range's start.
JSONEL:
    inc LINNUM
    bne *+4
    inc LINNUM+1
    jsr FNDLIN
    lda LOWTR
    sta INDEX1                              ; Move from here
    lda LOWTR+1
    sta INDEX1+1
    lda LOWTRB
    sta INDEX1B
    pla
    sta LOWTRB
    pla
    sta LOWTR+1
    pla
    sec                                     ; DELTA = the range's start less its end
    sta LOWTR
    sbc INDEX1
    sta DELTA
    lda LOWTR+1
    sbc INDEX1+1
    ldy LOWTRB
    jsr FIXSBC
    sta DELTA+1
    tax
    bpl *+3                                 ; $80 or more: the range holds nothing
    rts
    tya
    sbc INDEX1B
    sta DELTAB
    jsr MVDWN
    jmp FLOAD

; ---------------------------------------------------------------------------------------------------------------------
; TEXT and HOME
; ---------------------------------------------------------------------------------------------------------------------

;; The TEXT statement: puts the console back in its text mode, with the whole screen, normal video and the screen
;; on, by writing <TXTCHRS>.
;;
;; With anything after TEXT it returns at once, and the statement fetcher reports SYNTAX.
MSETTXT:
    bne TXTRTS
    ldx #0

;; Writes <TXTCHRS> to the console, up to its zero.
TXTOUT:
    lda a:TXTCHRS,X
    beq TXTRTS
    jsr PRNACHAR
    inx
    bne TXTOUT

;; Returns from <MSETTXT> and <HOME>.
TXTRTS:
    rts

;; The HOME statement: clears the viewport and puts the cursor at its top left.
;;
;; With anything after HOME it returns at once, and the statement fetcher reports SYNTAX.
HOME:
    bne TXTRTS
    lda #$1C                                ; The console's code to clear the viewport
    jmp PRNACHAR

;; The console codes TEXT writes, ending in a zero.
;; See: <MSETTXT>
TXTCHRS:
    .byte $10, 2, 6                         ; Text mode 2, cursor off
    .byte $15, $D                           ; The console's options, $D
    .byte $11, 1                            ; Normal video; the viewport is the whole screen
    .byte $F, $0D, 0                        ; Screen on, RETURN, the end
