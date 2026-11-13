; B3MAINC: the error handler, the prompt and the lines typed at it, tokenizing (CRUNCH), finding a line, and NEW
; and CLEAR with the routines that reset the program's state.
;
; A program is a list of lines from TXTTAB, in order of their numbers. Each line is its length in bytes (the whole
; line, this byte included), its number (low byte first), its tokens, and a zero; a length of zero ends the
; program. The byte before TXTTAB is a zero, which the statement fetcher reads as the end of a line before the first.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Errors
; ---------------------------------------------------------------------------------------------------------------------

;; Ends with OUT OF MEMORY.
;; See: <ERROR>
OMERR:
    ldx #ERROM

;; Reports error X: through ON ERR when the program has it in force, otherwise with a message, then goes back to
;; the prompt.
;;
;; It clears <CMDFLG>, sends output back to the OUTPUT# device (<FILNO> from <FILNO>+1, in case the error came during
;; PRINT#), keeps the number in <ERRNUM> (the ERR function) and frees the string temporaries.
;;
;; When a program is running (<CURLIN> is not direct), it copies <CURLIN> to <ERRLIN> (the ERRLIN function) and to
;; <OLDLIN>, and when bit 7 of <ERRFLG> is set (ON ERR) goes to <HNDLERR>. Otherwise, at <DNTTRAP>, it resets
;; output to the console, takes back all memory, turns the screen on, and prints `?`, the message and ` ERROR` with
;; a beep, and ` IN ` and the line when a program was running, then closes any EXEC file and goes to <READY>. The
;; stack pointer goes back to <REMSTK>, where the failing statement started.
;;
;; The number is the message's place in <ERRTAB>, from 1 (<ERRNF>). A SOS error with no number of BASIC's own comes
;; through <SERROR> as SOS CALL (<SSSSSS>), with SOS's code in <SOSLOC>. INPUT's errors 253 (extra ignored) and 254
;; (bad input) come here only when ON ERR can take them, and CONTROL-C's 255 goes to <HNDLERR> from <ISCNTC>.
;;
;; In 1.3, before a program has reached the prompt (<RNFLG> clear), it first prints the name of the program the
;; selector started.
;; In: X = the error number
;; See: <ERRFIN>, <HNDLERR>, <SERROR>
ERROR:
.if VERSION >= 130
    ; 1.3: restore SOS's prefix, and print the program's name when no program has reached the prompt yet.
    txa
    pha
    jsr SETSOS
    lda RNFLG
    bne ERRORR
    lda #<(PROGPATH+1)
    ldy #>(PROGPATH+1)
    ldx #ERRTABB
    jsr STROUTR
ERRORR:
    pla
    tax
.endif
    lda #0
    sta CMDFLG
    lda FILNO+1                             ; Output back to the OUTPUT# device
    sta FILNO
    stx ERRNUM

;; Frees each string temporary in use, and its string, for <ERROR>.
FREALL:
    lda LASTPT
    ldy LASTPT+1
    ldx #0
    jsr FRETNOW
    lda #<(TEMPST)
    cmp TEMPPT
    bcc FREALL
    ldx ERRNUM
    ldy CURLIN+1                            ; Direct: no ON ERR, and no line to keep
    iny
    beq DNTTRAP
    dey
    sty ERRLIN+1
    sty OLDLIN+1
    ldy CURLIN
    sty ERRLIN
    sty OLDLIN
    bit ERRFLG
    bpl DNTTRAP
    jmp HNDLERR                             ; ON ERR takes it

;; Prints error X's message for <ERROR> and goes back to the prompt.
;; In: X = the error number
DNTTRAP:
    lda #255                                ; Output to the console
    sta FILNO
    sta FILNO+1
    lda #0
    jsr EXPAND                              ; All the memory there is
    lda #15                                 ; Screen on
    jsr OUTDO
    jsr CRDO
    jsr OUTQST
    ldx REMSTK
    txs
    ldx ERRNUM
    lda #ERRTABB
    sta INDEXB
    lda #>(ERRTAB)
    sta INDEX+1
    lda #<(ERRTAB)
    sta INDEX
    ldy #0

;; Counts X down to the message in <ERRTAB>.
FINDHERR:
    dex
    beq GOTHER

;; Skips one message: its last character has bit 7 set.
CHECKHER:
    lda (INDEX),Y
    iny
    bne *+4
    inc INDEX+1                             ; The table never crosses into another bank
    cmp #$80
    bcc CHECKHER
    bcs FINDHERR

;; Prints the message, through its last character.
GOTHER:
    lda (INDEX),Y
    iny
    bne *+4
    inc INDEX+1
    pha
    jsr OUTDO
    pla
    cmp #$80
    bcc GOTHER
    lda #<(ERR)
    ldy #>(ERR)
    ldx #TEMPST
    stx TEMPPT
    ldx #ERRTABB

;; Prints a message, then ` IN ` and the line when a program was running, ends the line, closes any EXEC file and
;; goes to <READY>.
;;
;; BREAK and INPUT's EXTRA IGNORED come here with their own messages.
;; In: A = the message's low byte, Y = its high byte, X = its bank; the message ends with a zero
;; See: <ERROR>, <STOP2>
ERRFIN:
    jsr STROUTR
    ldy CURLIN+1
    iny                                     ; Direct?
    beq *+5
    jsr INPRT
    jsr CRDO
    ldx INFLNO                              ; An EXEC file?
    beq READY
    lda #SEEOF                              ; Close it, with an error EXCCLS accepts
    jsr EXCCLS

;; Goes back to the prompt after a program ends or stops, or after an error: writes out all files' buffers with
;; FLUSH (<RFLUSH>, whose reference number zero means every file), then falls into <MAIN>.
;;
;; The run-time version has no prompt: after an error it asks for the space bar, then, as when a program ends,
;; starts SOS again through <COLD1>.
;; See: <ERRFIN>, <MAIN>
READY:
.if VERSION >= 130
    jsr SETSOS                              ; 1.3: SOS's own prefix
.endif
.if RUNTIME
    lda ERRNUM                              ; Zero: the program ended
    beq READYGO
    lda #<(RTMSG)
    ldy #>(RTMSG)
    ldx #ERRTABB
    jsr STROUTR
READY1:
    jsr DOAGET
    lda KEYSAVE
    cmp #$20                                ; The space bar?
    bne READY1
READYGO:
    jmp COLD1
.else
    brk
    .byte SFLS
    .word RFLUSH
.endif

; ---------------------------------------------------------------------------------------------------------------------
; The prompt
; ---------------------------------------------------------------------------------------------------------------------

;; The prompt: reads a line, then runs it at once or, when it starts with a line number, puts it into the program.
;;
;; Each time round, it sets <CURLIN> direct and <RNFLG>, starts a new screen line unless the cursor is at the left
;; (from <VPOS>, which reads <CURX>), and turns the console's any-key event off for the prompt: it calls D_CONTROL
;; with priority zero in <KBDKEY>, then puts ON KBD's priority back in <KBDKEY> for CONT to turn it on again. It
;; clears <KEYSTROK> and reads the line with the prompt `)` through <INLINB>.
;;
;; A blank line is ignored. A direct line is tokenized in place by <CRUNCH> and run from <BUF> through <GONE>; after
;; its last statement the statement fetcher comes back through <READY>. A numbered line goes to <MAIN1>.
;; See: <READY>, <MAIN1>, <CRUNCH>
MAIN:
    lda #$FF                                ; Direct
    sta CURLIN+1
    lda #1
    sta RNFLG                               ; The prompt has been reached
.if VERSION >= 130
    jsr SETSOS                              ; 1.3: SOS's prefix, and the program's prefix
.endif
.if VERSION >= 130
    jsr SPROGPFX
.endif
    jsr VPOS
    lda a:CURX
    sta TRMPOS
    beq *+5                                 ; At the left already
    jsr CRDO
    lda a:KBDKEY
    pha
    lda #0
    sta a:KBDKEY
    brk                                     ; D_CONTROL: the any-key event off
    .byte SDCNT
    .word DKBD
    pla
    sta a:KBDKEY
    ldx #$29                                ; The prompt, `)`
    stx KEYSTROK                            ; which also clears bits 7 and 6: no key, no CONTROL-C
    jsr INLINB
    stx TXTPTR
    sty TXTPTR+1
    sta TXTPTRB
    jsr CHRGET
    tax                                     ; The line's end?
    beq MAIN
    ldx #255
    stx CURLIN+1
    bcc MAIN1                               ; A digit: a line number
    stx LOWTR+1                             ; Tells CRUNCH the line is direct
    jsr CRUNCH
    jmp GONE                                ; Run it

;; Puts a numbered line into the program, replacing any line with its number, or deletes the line when nothing
;; follows the number.
;;
;; It reads the number into <LINNUM>, tokenizes the line, and forbids CONT (<OLDTXT>'s bank zero). <FNDLIN> finds
;; the line or where it goes. An old line is removed with <MVDWN>; a new one is made room for with <MVUP>, and its
;; length and number are put in the three bytes before <BUF> so the whole line copies from <BUF>-3. Both moves take
;; the variables and arrays along, so they keep their values. At the end, <STXTPT> and <FLOAD> reset the text
;; pointer, the ON ERR, ON KBD and ON EOF handlers, the DATA pointer and the stack, and it goes back to <MAIN>.
;; See: <MAIN>, <CRUNCH>, <FNDLIN>
MAIN1:
    jsr LINGET
    lda #0                                  ; Tells CRUNCH the line is in a program
    sta LOWTR+1
    sta OLDTXTB                             ; No CONT now
    jsr CRUNCH
    sty COUNT                               ; The stored line's length
    sty BUF-3
    jsr FNDLIN
    bcc NODEL                               ; No line to delete
    ldy #00                                 ; DELTA = minus the old line's length
    lda #$7F
    sta DELTA+1
    lda #$FF
    sta DELTAB
    eor (LOWTR),Y
    sta DELTA
    inc DELTA
    lda (LOWTR),Y                           ; The next line starts here
    clc
    adc LOWTR
    sta INDEX1
    lda LOWTR+1
    adc #0
    ldy LOWTRB
    jsr FIXADC
    sta INDEX1+1
    tya
    adc #0
    sta INDEX1B
    jsr MVDWN

;; Inserts the new line for <MAIN1>, unless it is empty.
NODEL:
    lda BUF                                 ; Nothing after the number?
    beq FINI
    lda #0                                  ; DELTA = the new line's length
    sta DELTA+1
    sta DELTAB
    lda COUNT
    sta DELTA
    jsr MVUP
    lda LINNUM
    ldy LINNUM+1
    sta BUF-2
    sty BUF-2+1
    ldy COUNT

;; Copies the line, from <BUF>-3, into the gap, last byte first.
STOLOP:
    lda BUF-4,Y
    dey
    sta (LOWTR),Y
    bne STOLOP

;; Resets the program's state after an edit, then goes back to the prompt.
FINI:
    jsr STXTPT
    jsr FLOAD
    jmp MAIN

;; Reads a line into <BUF> with no prompt, for INPUT.
;; Out: X = the low byte of <BUF>-1, Y = its high byte, A = 0 (its bank), BUF = the line, ending in a zero
;; See: <INLINB>
INLIN:
    ldx #0

;; Reads a line from the console, or from the EXEC file while one runs, into <BUF>, after printing the prompt.
;; In: X = the prompt character, or zero for none
;; Out: X = the low byte of <BUF>-1, Y = its high byte, A = 0 (its bank), BUF = the line, ending in a zero
;; See: <INPUTLIN>, <GDBUFS>
INLINB:
    jsr INPUTLIN

;; Ends the line in <BUF> with a zero and returns <BUF>-1 for <TXTPTR>.
;;
;; Lines read from a file with INPUT# end here too.
;; In: X = the line's length
;; Out: X = the low byte of <BUF>-1, Y = its high byte, A = 0 (its bank)
GDBUFS:
    lda #0
    sta BUF,X
    lda #0
    sta YSAVE
    ldx #<(BUF-1)
    ldy #>(BUF-1)
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Tokenizing
; ---------------------------------------------------------------------------------------------------------------------

;; Goes to <CRNCHED> at the line's end, for <CRUNCH>'s branch.
GCRNCHED:
    jmp CRNCHED

;; Tokenizes the line in <BUF> in place, from <TXTPTR> on, and points <TXTPTR> at <BUF>-1 to run it.
;;
;; Keywords from <RESLST> become one-byte tokens, $80 to <SCRATK>; those of the second list, from <RESL2>, become
;; two bytes, $FF and the token. A word is a keyword only with a separator (anything but a letter, digit or period)
;; before and after it, or when it ends in one, as `TAB(` does, so long variable names can hold keywords. Letters
;; may be in either case, and spaces inside a keyword are skipped. Spaces outside quotes are dropped, `?` becomes
;; PRINT and `!` becomes REM. Quoted text, and everything after REM, is copied as it is.
;;
;; <DORES> says when to copy: bit 7 set copies characters unchanged; a colon always turns tokenizing back on, and a
;; comma does when bit 6 is clear. DATA, IMAGE and CAT copy up to the colon. In a direct line (<LOWTR>+1 = $FF),
;; INVOKE and RENAME copy up to the colon, the other disk commands from LOAD to CATALOG up to the next comma or
;; colon, and OPEN tokenizes up to its first comma and copies after it, which bit 7 of <INTFLG> marks.
;;
;; The tokens go from <BUF> on, behind the characters still to read, with <BUFPTR> counting from 3. They end with
;; two zeros: the line's end, and a zero where a next line's length would be, which ends a direct line when it
;; runs. The three bytes before <BUF> are left for the line's length and number.
;; In: TXTPTR = the first character to tokenize, LOWTR+1 = $FF for a direct line, 0 for a numbered one
;; Out: Y = the line's length as stored in a program (its tokens and zero, and three bytes for its length and
;;   number), TXTPTR = BUF-1, TXTPTRB = 0
;; Uses: A, X, COUNT, FAC, TEMP, ENDCHR, DORES, INTFLG
;; See: <MAIN>, <MAIN1>, <CKSEP>
CRUNCH:
    lda TXTPTR
    sec
    sbc #<(BUF)
    tax                                     ; X = the input's index in BUF
    lda #3
    sta BUFPTR
    sta DORES                               ; Tokenizing on
    sta INTFLG
    sta BUF-1,X                             ; A separator before the first word

;; Starts on the next input character, at the top of the keyword list.
CLOOP:
    ldy #0
    sty COUNT+1                             ; One-byte tokens first
    lda #$80
    sta COUNT                               ; The first token
    lda #<(RESLST)
    sta FAC
    lda #>(RESLST)
    sta FAC+1
    lda #RESLSTB
    sta FACB
    lda BUF,X
    beq GCRNCHED
    and #$7F
    cmp #$3A                                ; A colon?
    beq ONCRNC
    cmp #$2C                                ; A comma?
    bne CL1
    bit INTFLG
    bpl *+6
    ror DORES                               ; After OPEN: copy from here
    bmi CL1
    bit DORES                               ; Does a comma turn tokenizing on?
    bvs CL1

;; Turns tokenizing back on: A, a colon or comma, has bits 7 and 6 clear.
ONCRNC:
    sta DORES

;; Copies the character, drops a space, or looks for a keyword.
CL1:
    bit DORES
    bmi STUFIT                              ; Copying
    cmp #$21
    bcs *+5
    jmp NXCHR                               ; A space: drop it
    cmp #'!'
    bcc STUFIT
    bne SHORT1
    lda #REMTK
    bcs STUFIT

;; Turns `?` into PRINT and keeps other punctuation and digits.
SHORT1:
    cmp #'?'
    bcc STUFIT
    bne NPRNT
    lda #PRINTK
    bcs STUFIT

;; Goes to <NOMTCH> for the branches.
GNMTCH:
    jmp NOMTCH

;; Compares the input from X with the keyword at <FAC>.
NPRNT:
    stx TEMP                                ; Where the word starts

;; Starts the comparison again, with the next keyword.
NPR2:
    ldx TEMP

;; Compares the next input character, skipping spaces.
NPR3:
    lda BUF,X
    beq NSPC
    and #$7F
    cmp #$21
    bcs NSPC
    inx
    bne NPR3

;; Makes a lower-case letter upper case.
NSPC:
    cmp #'A'+$20
    bcc NSP2
    cmp #'Z'+$21
    bcs NSP2
    and #$DF

;; Compares the character with the keyword's.
NSP2:
    eor (FAC),Y
    iny
    inx
    asl                                     ; The low seven bits must match
    bne GNMTCH
    bcc NPR3                                ; Bit 7 clear: not the keyword's last character
    lda BUF,X                               ; The whole keyword matches: is a separator after it?
    and #$7F
    jsr CKSEP
    bcc YMTCH
    dey                                     ; Or does the keyword end in one, as DEC( does?
    lda (FAC),Y
    and #$7F
    jsr CKSEP
    bcc YMTCH
    lda COUNT                               ; Or is it EXFN. or EXFN%., or FN?
    cmp #EXFNSTK-1
    beq YMTCH
    cmp #EXFNSTK
    beq YMTCH
    cmp #FNTK
    bne GNMTCH
    bit COUNT+1                             ; FN is in the second list
    bpl GNMTCH

;; Takes the keyword when a separator comes before it too.
YMTCH:
    txa
    pha
    ldx TEMP
    lda BUF-1,X
    jsr CKSEP
    pla
    tax
    bcs GNMTCH
    dex                                     ; Back to the keyword's last character
    lda COUNT+1
    bmi STUFIT                              ; Two bytes: $FF first
    lda COUNT

;; Stores A in the tokens, with the token after $FF for a two-byte token.
STUFIT:
    ldy BUFPTR
    sta BUF-3,Y
    iny
    cmp #$FF
    bne NESC
    lda COUNT
    sta BUF-3,Y
    iny
    lda #0                                  ; Matches none of the tests below

;; Keeps the output index.
NESC:
    sty BUFPTR

;; Steps to the next input character, after checking whether the token just stored turns tokenizing off.
NXCHR:
    inx
    cmp #REMTK
    beq REMIT
    cmp #DATATK
    beq ITDIR15
    cmp #$22                                ; A quote
    beq DOQUOT
    cmp #IMAGETK+2
    bcs GCLOOP
    ldy LOWTR+1                             ; A direct line?
    iny
    beq ITDIR
    cmp #DSKCOMS+1                          ; In a program, only IMAGE and CAT go on
    bcc GCLOOP

;; Checks OPEN, INVOKE and the disk commands, and IMAGE and CAT.
ITDIR:
    cmp #OPENTK
    bne ITDIR1
    ror INTFLG                              ; Copy after OPEN's first comma
    bmi GCLOOP                              ; Always

;; Checks INVOKE and the disk commands.
ITDIR1:
    cmp #INVOKTK
    beq ITDIR15
    cmp #LDTKN
    bcc GCLOOP
    cmp #RENMTK
    bne ITDIR2

;; Copies up to the colon: bits 7 and 6 of <DORES> set.
ITDIR15:
    sec
    .byte 44                                ; BIT abs, which skips the CMP

;; Copies up to the next comma or colon after a disk command (bit 6 clear), or up to the colon after IMAGE and
;; CAT (bit 6 set).
ITDIR2:
    cmp #DSKCOMS+1
    ror DORES
    sec
    ror DORES

;; Goes back to <CLOOP>.
GCLOOP:
    jmp CLOOP

;; Copies the rest of the line after REM.
REMIT:
    lda #0                                  ; Only the line's end ends it

;; Copies characters unchanged up to the one in A, or the line's end.
;; In: A = the character that ends the copy
DOQUOT:
    dex
    sta ENDCHR
    ldy BUFPTR
    dey

;; Copies a character for <DOQUOT>.
DOQ2:
    iny
    inx
    lda BUF,X
    sta BUF-3,Y
    sty BUFPTR
    beq CRNCHED
    cmp ENDCHR
    bne DOQ2
    iny
    sty BUFPTR
    inx
    jmp GCLOOP

;; Steps to the next keyword in the list, or stores the character as it is when there are no more.
NOMTCH:
    dey
    beq FNDNXT
    dey

;; Skips the rest of this keyword, then adds its length to <FAC>.
FNDNXT:
    iny
    lda (FAC),Y
    bpl FNDNXT                              ; A keyword ends with bit 7 set
    sec
    tya
    adc FAC
    sta FAC
    bcc *+4
    inc FAC+1                               ; The list never crosses into another bank
    ldy #0
    ldx COUNT
    inx
    cpx #SCRATK+1                           ; Past the statements?
    bne FND2
    ldx #$FF                                ; The second list: two-byte tokens from $80
    stx COUNT+1
    ldx #$80

;; Keeps the token number and checks for the list's end.
FND2:
    stx COUNT
    lda (FAC),Y
    bne GNPR2
    ldx TEMP                                ; No keyword: store the character
    lda BUF,X
    and #$7F
    jmp STUFIT

;; Ends the tokens with two zeros and points <TXTPTR> at <BUF>-1.
CRNCHED:
    ldy BUFPTR
    sta BUF-3,Y
    sta BUF-2,Y                             ; A zero length after the line: a direct line ends there
    lda #0
    sta TXTPTRB
    lda #>(BUF-1)
    sta TXTPTR+1
    lda #<(BUF-1)
    sta TXTPTR
    iny
    rts

;; Goes to <NPR2> for the branch.
GNPR2:
    jmp NPR2

;; Tells whether a character separates words: anything but a letter, a digit or a period does.
;; In: A = the character
;; Out: carry = clear for a separator
;; See: <ISLETC>
CKSEP:
    jsr ISLETC
    bcs CKRTS
    cmp #'9'+1
    bcs CKRT1
    cmp #'0'
    bcs CKRTS
    cmp #'.'
    beq CKRTS

;; Returns with carry clear: a separator.
CKRT1:
    clc

;; Returns from <CKSEP>.
CKRTS:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Finding a line
; ---------------------------------------------------------------------------------------------------------------------

;; Finds the line numbered <LINNUM>, or where it would go.
;;
;; It searches from <TXTTAB>; FNDLNC0 searches from the line at Y, X and A (bank, page, low byte), as GOTO does
;; when the line is after the current one. Invokable modules can call both through <JMPRTAB>.
;; In: LINNUM = the line's number
;; Out: carry = set when found, LOWTR = the line's length byte, or the first line with a higher number, or the
;;   program's end
;; Uses: A, X, Y
;; Entry: FNDLNC0 = searches from the line at Y, X and A, FNDLNC1 = from the bank in <LOWTRB> and the page in X,
;;   FNDLNC = from the bank and page in LOWTR
FNDLIN:
    lda TXTTAB
    ldx TXTTAB+1
    ldy TXTTABB
FNDLNC0:
    sty LOWTRB
FNDLNC1:
    stx LOWTR+1
FNDLNC:
    sta LOWTR
    ldy #0
    lda (LOWTR),Y                           ; The line's length
    beq FLINRT                              ; Zero: the program's end
    ldy #2
    tax
    lda LINNUM+1
    cmp (LOWTR),Y
    bcc FLNRTS                              ; Past it: not there
    bne AFFRTS
    lda LINNUM
    dey
    cmp (LOWTR),Y
    bcc FLNRTS                              ; Past it: not there
    beq FLNRTS                              ; Found, with carry set

;; Steps <LOWTR> to the next line, by this one's length in X.
AFFRTS:
    txa
    clc
    adc LOWTR
    bcc FNDLNC
    ldx LOWTR+1
    inx
    cpx #MAXPG
    bcc FNDLNC1
    pha                                     ; Into the next bank
    txa
    sbc #MAXPG-MINPG
    tax
    pla
    inc LOWTRB
    bne FNDLNC1                             ; Always
    bcs FNDLNC                              ; Never reached

;; Returns from <FNDLIN> with carry clear: not found.
FLINRT:
    clc

;; Returns from <FNDLIN>.
FLNRTS:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; NEW, CLEAR and resetting
; ---------------------------------------------------------------------------------------------------------------------

;; The NEW statement: deletes the program and its variables, closing all files.
;;
;; With anything after NEW it returns at once, and the statement fetcher reports SYNTAX.
;; See: <SCRTCH>
SCRATH:
    bne FLNRTS

;; Deletes the program and its variables: closes all files, resets BASIC's state with <P1INIT>, then clears
;; everything as <RUNC> does. <INIT> calls it.
;; See: <P1INIT>, <RUNC>
SCRTCH:
    jsr CLSALL
    jsr P1INIT

;; Gets ready to run the program from its start, for RUN: points <TXTPTR> before the first line, marks <CURLIN> as
;; not direct so the statement fetcher goes on to the first line, and clears as CLEAR does.
;; See: <STXTPT>, <CLEARC>
RUNC:
    jsr STXTPT
    lda #0                                  ; Sets zero for CLEAR's test
    sta CURLIN+1

;; The CLEAR statement: closes all files and clears the variables, the strings and the stack.
;;
;; With anything after CLEAR it returns at once, and the statement fetcher reports SYNTAX.
;; See: <CLEARC>
CLEAR:
    bne STKRTS

;; Closes all files, then clears as <CLEARL> does.
;; See: <CLEARL>
CLEARC:
    jsr CLSALL

;; Clears the variables, arrays and strings, ERR, ERRLIN, KBD and EOF, then resets as <FLOAD> does.
;;
;; The strings start again at <MEMSIZ>, and the simple variables and the end of the variables (<VARTAB> and
;; <STREND>) go back to <ARYTAB>, the program's end. LOAD calls it without closing files.
;; See: <FLOAD>
CLEARL:
    lda MEMSIZ
    ldx MEMSIZB
    ldy MEMSIZ+1                            ; No strings
    sta FRETOP
    sty FRETOP+1
    stx FRETOPB
    lda ARYTAB
    ldy ARYTAB+1                            ; No variables or arrays
    ldx ARYTABB
    sta VARTAB
    sty VARTAB+1
    stx VARTABB
    sta STREND
    sty STREND+1
    stx STRENDB
    lda #0
    sta KEYSAVE                             ; KBD
    sta ERRNUM                              ; ERR
    sta ERRLIN                              ; ERRLIN
    sta ERRLIN+1
    sta EOFSV                               ; EOF

;; Takes back all memory with <EXPAND>, points DATA at the program's start with <RESTOR>, and resets the stack
;; with <STKINI>.
;; See: <STKINI>
FLOAD:
    lda #0
    jsr EXPAND
    jsr RESTOR

;; Empties the stack, keeping only the caller's return address, and resets the formula evaluator's stacks.
;;
;; The stack pointer goes to <STKEND> and into <REMSTK>; GOSUB and FOR entries are gone. The byte above, the zero
;; <INIT> pushed, stays at the bottom for <FNDFOR>. Apple's comment said it also frees the string temporaries and
;; forbids CONT; the code does neither.
;; Uses: A, X, Y
STKINI:
    pla                                     ; The return address
    tay
    pla
    ldx #STKEND
    stx REMSTK
    txs
    pha
    tya
    pha
    lda #2
    sta VRBPT                               ; Past the end-of-line entry
    lda #0
    sta VRBSTK+1                            ; The end-of-line precedence
    sta NOUNPT
    sta SUBFLG                              ; Subscripts allowed

;; Returns from <STKINI>, and from CLEAR when something follows it.
STKRTS:
    rts

;; Points <TXTPTR> at the byte before the program, writing the zero there, then turns off the program's handlers
;; as <CLEARONS> does.
;; See: <CLEARONS>
STXTPT:
    sec
    lda TXTTAB
    sbc #1
    sta TXTPTR
    lda TXTTAB+1
    sbc #0
    ldy TXTTABB
    jsr FIXSBC
    sta TXTPTR+1
    tya
    sbc #0
    sta TXTPTRB
    ldy #0
    tya
    sta (TXTPTR),Y                          ; The zero before the first line

;; Turns off ON KBD, ON EOF and ON ERR, clears any key waiting in <KEYSTROK>, and leaves nothing for RESUME.
;;
;; It turns off the console's any-key event with <OFFKBD>, clears every handler in <EOFPTRS>, and clears
;; <ERRFLG> and <ERRPOSB>. LOAD calls it too.
;; Out: A = 0, Y = 0
;; Uses: X
CLEARONS:
    jsr OFFKBD
    ldy #EOFSIZ
    lda #0
    sta KEYSTROK

;; Clears <EOFPTRS>, from the top.
CLEOFS:
    sta EOFPTRS-1,Y
    dey
    bne CLEOFS
    sty ERRFLG                              ; No ON ERR
    sty ERRPOSB                             ; No error to RESUME
    rts
