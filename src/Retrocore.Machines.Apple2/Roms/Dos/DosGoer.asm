;; DOS 3.3 AND 3.2 COMMAND INTERPRETER: FILE MANAGER CALLS, ERRORS AND FILE BUFFERS (DOSGOER)
;;
;; The glue between the command handlers (OpenClose.asm, LoadSave.asm, MiscCommands.asm) and the file manager.
;; A handler fills in the file manager's parameter list, the CCB, and calls DOSGO, which calls the file manager
;; (DOSENT) and deals with its errors. ERROR prints any DOS error message and hands control back to BASIC.
;; The rest finds and fills the file buffers that BLDFTB (BuildFileTables.asm) chains below DOS: FILSRC looks
;; for the buffer of the file named in FNAME1, and OPNSUP, MVFN1 and MVBUFP copy a buffer's details into the
;; CCB. ZPGWRK ($40-$41) points at the buffer being worked on, at its header.
;;
;; Runs at $A6A8-$A7D3 where DOS runs.

;; Calls the file manager with the request in the CCB, and handles any error.
;;
;; END OF DATA (5) is not an error here: EOFFIX (BootLoader.asm) checks the file's FCB and comes back to DOSGO2A,
;; which returns as if a 0 byte had been read. Any other error frees the buffer of the file in FNAME1 and goes
;; to ERROR (CLOSFILE, BootLoader.asm).
;;
;; DOS 3.2 has neither patch: it frees the buffer of the file in FNAME1 on any error, so the file is closed.
;; END OF DATA is then not an error: DOSGO returns as if a 0 byte had been read. Any other error goes to ERROR.
;; In:    CCB = the request, filled in
;; Out:   CCB = updated by the file manager, CCBDAT = 0 at the end of the data
DOSGO:
    jsr DOSENT
    bcc DG3                         ; no error
.if DOS32
    jsr FILSRC
    bcs DG2                         ; no buffer
    lda #0
    tay
    sta (ZPGWRK),y                  ; a buffer whose name starts with 0 is free
DG2:
    lda a:CCBSTA
    cmp #5
    bne ERROR
.else
    lda a:CCBSTA
    cmp #5
    beq YESEOF
    jmp CLOSFILE
YESEOF:
    jmp EOFFIX
    nop                             ; not reached
.if DOS33B
; Revision B: MOVEOF (MsWait.asm) clears EOFFLAG unless the command is APPEND. Without it, three NOPs.
DOSGO2A:
    jsr MOVEOF
.else
    nop
DOSGO2A:
    nop
    nop
.endif
.endif
    ldx #0
    stx a:CCBDAT
DG3:
    rts

;; Reports an error: SYNTAX ERROR (11).
;;
;; It does not return.
ESYNTX:
    lda #CREFLK+1
    bne ERROR                       ; always
;; Reports an error: NO BUFFERS AVAILABLE (12).
;;
;; It does not return.
ENFA:
    lda #CREFLK+2
    bne ERROR                       ; always
;; Reports an error: PROGRAM TOO LARGE (14).
;;
;; It does not return.
MFERR:
    lda #CREFLK+4
    bne ERROR                       ; always
;; Reports an error: FILE TYPE MISMATCH (13).
;;
;; It does not return.
ETYP:
ERNU1:
    lda #CREFLK+3
;; Prints a DOS error message and returns to BASIC.
;;
;; Clears the input, output and RUN states. If Applesoft's ONERR GOTO is on, nothing is printed, so the
;; program's handler can deal with it; otherwise return, bell, return, the message and a return. Then, if a
;; program is running, goes to BASIC's error entry (the BREAK vector) with the error number in X; in direct mode,
;; to BASIC's command level (the CONT vector). The vectors are in DosInit.asm. It does not return to its caller.
;; In:    A = the error number, 1-15 (see EMDTB)
ERROR:
    sta a:SVA
    jsr CLRSTS1                     ; ISTATE, OSTATE and RSTATE = 0 (DosPatches.asm)
    lda a:ASIBSW
    beq ERNAS                       ; Integer BASIC
    lda ASONERR
    bmi ERRTN                       ; ONERR is on: no message
ERNAS:
    ldx #0
    jsr EMPR                        ; return, bell, return
    ldx a:SVA
    jsr EMPR
    jsr PRCRIF
ERRTN:
    jsr MVCSW
    jsr TSTRUN                      ; carry clear while a program runs
    ldx a:SVA
    lda #03
    bcs ERRTN1
    jmp (BREAK)
ERRTN1:
    jmp (CONT)

;; Prints error message X through the real output routine.
;; In:    X = the error number, or 0 for return, bell, return
;; Uses:  A, X, TEMP1A
;; Entry: EMPR1 = prints from offset X in EMSG
EMPR:
    lda a:EMDTB,x
    tax
EMPR1:
    stx a:TEMP1A
    lda a:EMSG,x
    pha
    ora #$80
    jsr ORTN1
    ldx a:TEMP1A
    inx
    pla
    bpl EMPR1                       ; the last character has its top bit set
    rts

;; Fills in the CCB for opening a file: volume, drive and slot from the command's options, the address of
;; FNAME1, and notes the buffer in CFTABA.
;; In:    ZPGWRK = the file's buffer
;; Uses:  A
OPNSUP:
    lda a:CV
    sta a:CCBVOL
    lda a:CD
    sta a:CCBDRV
    lda a:CS
    sta a:CCBSLT
    lda FN1ADR
    sta a:CCBFN1
    lda FN1ADR+1
    sta a:CCBFN1+1
    lda ZPGWRK
    sta a:CFTABA
    lda ZPGWRK+1
    sta a:CFTABA+1
    rts

;; Copies FNAME1 into a buffer's name field, which marks the buffer as in use by that file.
;; In:    ZPGWRK = the buffer
;; Out:   Y = $FF
;; Uses:  A
MVFN1:
    ldy #29
MVFN1A:
    lda a:FNAME1,y
    sta (ZPGWRK),y
    dey
    bpl MVFN1A
    rts

;; Copies a buffer's four pointers, header bytes 30-37, into the CCB (CCBFCB on): its work area, track/sector
;; list buffer, data buffer and the link to the next buffer.
;; In:    ZPGWRK = the buffer
;; Out:   Y = 38
;; Uses:  A
MVBUFP:
    ldy #30
MVBP1:
    lda (ZPGWRK),y
    sta a:CCBFCB-30,y
    iny
    cpy #38
    bne MVBP1
    rts

;; Clears the input and output states: no READ, no WRITE, and the next character printed starts a line.
;; Out:   Y = 0
CLRSTS:
    ldy #0
    sty a:ISTATE
    sty a:OSTATE
    rts

;; Looks for the buffer of the file named in FNAME1, noting a free one on the way.
;; Out:   ZPGWRK = the file's buffer if it is open, CNUM = in either case the last free buffer passed (the
;;          lowest), or CNUM+1 = 0 if none, carry = clear if the file is open, set if not
;; Uses:  A, X, Y
FILSRC:
    lda #0
    sta CNUM+1
    jsr TSINIT
    jmp FLS1A
FLS1:
    jsr TSNXT
    beq FLS4                        ; the end of the chain
FLS1A:
    jsr TSTOPN
    bne FLS2                        ; in use: compare the name
    lda ZPGWRK
    sta CNUM
    lda ZPGWRK+1
    sta CNUM+1
    bne FLS1                        ; always: a buffer is never in page 0
FLS2:
    ldy #29
FLS3:
    lda (ZPGWRK),y
    cmp a:FNAME1,y
    bne FLS1
    dey
    bpl FLS3
    clc
    rts
FLS4:
    sec
    rts

;; Points ZPGWRK at the first file buffer.
;; Out:   ZPGWRK = the first buffer; A = X = its high byte; Z clear
;; Entry: TSNXT = points ZPGWRK at the next buffer: Z set at the end of the chain, Z clear and A = X = the
;;        next buffer's high byte otherwise (uses Y)
TSINIT:
    lda FTAB
    ldx FTAB+1
    bne TSST                        ; always
TSNXT:
    ldy #37
    lda (ZPGWRK),y                  ; the link's high byte
    beq TSR                         ; 0: no next buffer
    tax
    dey
    lda (ZPGWRK),y
TSST:
    stx ZPGWRK+1
    sta ZPGWRK
    txa                             ; Z clear
TSR:
    rts

;; Tests whether a buffer is in use.
;; In:    ZPGWRK = the buffer
;; Out:   A = the first byte of its file name; Z set if the buffer is free; Y = 0
TSTOPN:
    ldy #0
    lda (ZPGWRK),y
    rts

;; Tests whether a buffer is the one the EXEC file is using.
;;
;; The "no" answers that fall through to TXC1 get Z from DEX, so they are right only when X is not 1 on entry.
;; CLALL and ECLOSE call it straight after FILSRC, TSINIT or TSNXT, which leave X = a buffer's high byte.
;; In:    ZPGWRK = the buffer, X = anything but 1
;; Out:   zero = set if an EXEC file is open in this buffer
;; Uses:  A, X
TSTEXC:
    lda a:ESTATE
    beq TXC1                        ; no EXEC file
    lda a:EFTABA
    cmp ZPGWRK
    bne TXC2                        ; Z clear: another buffer
    lda a:EFTABA+1
    cmp ZPGWRK+1
    beq TXC2                        ; Z set: this one
TXC1:
    dex
TXC2:
    rts

;; Checks that the file just opened is of the type the command wants. The lock bit (bit 7) is ignored. On a
;; mismatch the file is closed and the error is FILE TYPE MISMATCH.
;;
;; It returns only if the types match.
;; In:    A = the type wanted; CCBFUC = the file's type, from the file manager
TSTFUC:
    eor a:CCBFUC
    beq TFUCR
    and #$7F
    beq TFUCR
    jsr ECLOSE
    jmp ERNU1
TFUCR:
    rts
