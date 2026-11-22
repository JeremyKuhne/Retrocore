; COMMODORE BASIC: ERRORS, COMMAND EDITING, TERMINAL INPUT AND TOKENIZATION
;
; Include after the selected workspace and emit these four macros in order at OMERR:
;              COMMODORE_ERROR_READY  COMMODORE_COMMAND_LOOP  COMMODORE_TERMINAL_INPUT  COMMODORE_TOKENIZE
; BASIC 1      1                      0, 0, 0, 0              1, 0                      0, 1
; BASIC 2      1                      1, 1, 1, 0              0, 0                      0, 0
; BASIC 4      0                      1, 1, 1, 1              0, 1                      1, 0
; Both revisions of BASIC 1 and BASIC 4 use their version's same settings. The next entry is FNDLIN.

.include "../../Microsoft6502Basic/MsBasic.CommandCore.asm"

;; Emits error reporting and the READY prompt.
;; Parameters: suppressOutput = 1 to clear the output-suppression flag
.macro COMMODORE_ERROR_READY suppressOutput
    .assert suppressOutput = 0 || suppressOutput = 1, "suppressOutput is 0 or 1."

;; Reports an OUT OF MEMORY error.
OMERR:
    ldx #<ERROM

;; Closes a selected channel and prints the selected error before returning to the command prompt.
;; In: X = offset of the message in <ERRTAB>
;; See: <CQCCHN>, <OUTDO>, <TYPERR>
ERROR:
.if suppressOutput
    lsr CNTWFL
.endif
    lda CHANNL
    beq ERRCRD
    jsr CQCCHN
    lda #$00
    sta CHANNL
ERRCRD:
    jsr CRDO
    jsr OUTQST
GETERR:
    lda ERRTAB,x
    pha
    and #$7F
    jsr OUTDO
    inx
    pla
    bpl GETERR
    BASIC_ERROR_FINISH

;; Prints the READY message before reading another command.
;; See: <MAIN>
READY:
.if suppressOutput
    lsr CNTWFL
.endif
    lda #<REDDY
    ldy #>REDDY
    jsr STROUT
.endmacro

;; Emits the command loop, program-line editing and link reconstruction.
;; Parameters: testCharacter = 1 to set zero from A after fetching the first character;
;;   resetBeforeInsert = 1 to clear variables and relink before inserting;
;;   linkReturns = 1 for <LNKPRG> to return rather than jump to <MAIN>;
;;   addHighToY = 1 for the BASIC 4 link high-byte addition
.macro COMMODORE_COMMAND_LOOP testCharacter, resetBeforeInsert, linkReturns, addHighToY
    .assert testCharacter = 0 || testCharacter = 1, "testCharacter is 0 or 1."
    .assert resetBeforeInsert = 0 || resetBeforeInsert = 1, "resetBeforeInsert is 0 or 1."
    .assert linkReturns = 0 || linkReturns = 1, "linkReturns is 0 or 1."
    .assert addHighToY = 0 || addHighToY = 1, "addHighToY is 0 or 1."
    .assert resetBeforeInsert = 0 || linkReturns = 1, "Relinking before insertion requires a returning LNKPRG."

;; Reads and executes a direct command, or inserts, replaces or deletes a numbered program line.
;; See: <INLIN>, <CRUNCH>, <FNDLIN>, <LNKPRG>
MAIN:
    jsr INLIN
    stx TXTPTR
    sty TXTPTR+1
    jsr CHRGET
.if testCharacter
    tax
.endif
    beq MAIN
    ldx #$FF
    stx CURLIN+1
    bcc MAIN1
    jsr CRUNCH
    jmp GONE

    BASIC_DELETE_OLD_LINE INDEX1
NODEL:
.if resetBeforeInsert
    jsr RUNC
    jsr LNKPRG
    lda BUF
    beq MAIN
    clc
.else
    lda BUF
    beq FINI
    lda MEMSIZ
    ldy MEMSIZ+1
    sta FRETOP
    sty FRETOP+1
.endif
    lda VARTAB
    sta HIGHTR
    adc COUNT
    sta HIGHDS
    ldy VARTAB+1
    sty HIGHTR+1
    bcc NODELC
    iny
NODELC:
    sty HIGHDS+1
    jsr BLTU
.if BUFPAG
    lda LINNUM
    ldy LINNUM+1
    sta BUF-2
    sty BUF-1
.endif
    lda STREND
    ldy STREND+1
    sta VARTAB
    sty VARTAB+1
    ldy COUNT
    dey
STOLOP:
    lda BUF-4,y
    sta (LOWTR),y
    dey
    bpl STOLOP

;; Clears execution state and relinks the program after an edit.
;; See: <RUNC>, <LNKPRG>
FINI:
    jsr RUNC
.if linkReturns
    jsr LNKPRG
    jmp MAIN
.endif

;; Rebuilds the linked program addresses by scanning each zero-terminated line.
;;
;; The earlier version enters <MAIN> at the end; later versions return to their caller.
;; In: TXTTAB = first line, with a zero high link byte marking the end of the program
LNKPRG:
    lda TXTTAB
    ldy TXTTAB+1
    sta INDEX
    sty INDEX+1
    clc
CHEAD:
    ldy #$01
    lda (INDEX),y
.if linkReturns
    beq LNKRTS
.else
    bne *+5
    jmp MAIN
.endif
    BASIC_LINK_LINE addHighToY
.if linkReturns
LNKRTS:
    rts
.endif
.endmacro

;; Emits the terminal-line reader and, where present, its character-input wrapper.
;; Parameters: earlyDelete = 1 to retain the early line-editing entries;
;;   checkedInput = 1 to reject a full buffer and call the kernal directly
.macro COMMODORE_TERMINAL_INPUT earlyDelete, checkedInput
    .assert earlyDelete = 0 || earlyDelete = 1, "earlyDelete is 0 or 1."
    .assert checkedInput = 0 || checkedInput = 1, "checkedInput is 0 or 1."
    .assert earlyDelete = 0 || checkedInput = 0, "The early editor uses the character-input wrapper."

.if earlyDelete
;; Backs up the input index, restarting the line if it moves before the buffer.
LINLIN:
    dex
    bpl INLINC

;; Restarts terminal input after printing a newline.
INLINN:
    jsr CRDO
.endif

;; Reads a carriage-return-terminated line into <BUF>.
;;
;; The checked reader reports STRING TOO LONG when it fills the buffer. The earlier readers rely on
;; the editor's limit and continue until carriage return or an eight-bit index wrap.
;; Out: X/Y = address before <BUF> after <FININL>
;; Errors: STRING TOO LONG for a full buffer when checked input is selected
INLIN:
    ldx #$00
INLINC:
.if checkedInput
    jsr CQINCH
.else
    jsr INCHR
.endif
    cmp #$0D
    beq FININ1
.if .not checkedInput
GOODCH:
.endif
    sta BUF,x
    inx
.if checkedInput
    cpx #BUFLEN
    bne INLINC
    ldx #<ERRLS
    jmp ERROR
.else
    bne INLINC
.endif
FININ1:
    jmp FININL

.if .not checkedInput
;; Reads a character and toggles output suppression on terminal Control-O.
;;
;; Control-O on a selected nonterminal channel is returned without changing the flag.
;; Out: A = input character
;; See: <CQINCH>
INCHR:
    jsr CQINCH
    ldy CHANNL
    bne INCRTS
    cmp #CONTW
    bne INCRTS
    pha
    lda CNTWFL
    eor #$FF
    sta CNTWFL
    pla
INCRTS:
    rts
.endif
.endmacro

;; Emits the PET reserved-word tokenizer.
;; Parameters: indirectTable = 1 to walk a table longer than 256 bytes through <INDEX1>;
;;   skipKeywordSpaces = 1 to ignore spaces while matching reserved words
.macro COMMODORE_TOKENIZE indirectTable, skipKeywordSpaces
    .assert indirectTable = 0 || indirectTable = 1, "indirectTable is 0 or 1."
    .assert skipKeywordSpaces = 0 || skipKeywordSpaces = 1, "skipKeywordSpaces is 0 or 1."
    .assert indirectTable = 0 || skipKeywordSpaces = 0, "The indirect table walker does not skip keyword spaces."
.if indirectTable
    .assert <RESLST != 0, "The indirect table setup branches on the nonzero low byte of RESLST."
.endif

;; Replaces reserved words in the input buffer with tokens from <RESLST>.
;;
;; Spaces are retained. Quoted strings, DATA fields and REM text are copied without tokenization; a colon
;; ends a DATA field and ? abbreviates PRINT. High-bit characters other than PI are discarded outside
;; quoted strings and REM text, including in an unquoted DATA field. The early walker ignores spaces within a word.
;; In: TXTPTR = address of the first input character
;; Out: TXTPTR = address before <BUF>, Y = encoded line length including the link and line-number header
;; See: <LIST>
CRUNCH:
    ldx TXTPTR
    ldy #$04
    sty DORES
KLOOP:
    lda BUFOFS,x
    bpl CMPSPC
    cmp #PI
    beq STUFFH
    inx
    bne KLOOP
CMPSPC:
    cmp #' '
    beq STUFFH
    sta ENDCHR
    cmp #'"'
    beq STRNG
    bit DORES
    bvs STUFFH
    cmp #'?'
    bne KLOOP1
    lda #<PRINTK
    bne STUFFH
KLOOP1:
    cmp #'0'
    bcc MUSTCR
    cmp #$3C
    bcc STUFFH
MUSTCR:
    sty BUFPTR
    ldy #$00
    sty COUNT
.if indirectTable
    stx TXTPTR
    lda #>RESLST
    sta INDEX1+1
    lda #<RESLST
    sta INDEX1
    bne RESCON
RESER:
    inx
    inc INDEX1
    bne RESCON
    inc INDEX1+1
.else
    dey
    stx TXTPTR
    dex
RESER:
    iny
RESPUL:
    inx
.endif
RESCON:
    lda BUFOFS,x
.if skipKeywordSpaces
    cmp #' '
    beq RESPUL
.endif
    sec
.if indirectTable
    sbc (INDEX1),y
.else
    sbc RESLST,y
.endif
    beq RESER
    cmp #$80
    bne NTHIS
    ora COUNT

    BASIC_TOKEN_STORE BUFOFS, 0
NTHIS:
    ldx TXTPTR
    inc COUNT
NTHIS1:
.if indirectTable
    lda (INDEX1),y
    php
    inc INDEX1
    bne NTHIS2
    inc INDEX1+1
NTHIS2:
    plp
.else
    iny
    lda RESLST-1,y
.endif
    bpl NTHIS1
.if indirectTable
    lda (INDEX1),y
.else
    lda RESLST,y
.endif
    bne RESCON
    lda BUFOFS,x
    bpl GETBPT
CRDONE:
    sta BUF-3,y
.if BUFPAG
    dec TXTPTR+1
.endif
    lda #<(BUF-1)
    sta TXTPTR
LISTRT:
    rts
.endmacro
