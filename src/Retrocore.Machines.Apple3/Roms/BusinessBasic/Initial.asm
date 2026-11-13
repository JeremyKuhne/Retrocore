; INITIAL: BASIC's cold start, INIT, with the console's setup, then the memory routines the rest of BASIC shares:
; finding a FOR entry on the stack, moving blocks of memory up and down, and checking for room on the stack and
; below the strings.
;
; INIT runs once. Everything from INITAT to the end of INIT's own code is used only at start, so Apple's comments
; allowed it to be reused as buffer space later; everything from INITCNS on must stay.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; The cold start
; ---------------------------------------------------------------------------------------------------------------------

;; The model of <CHRGET> and the random number seed, which <INIT> copies to zero page; this copy never runs.
;;
;; CHSGET steps <TXTPTR> to the next character of the program and reads it, skipping spaces. Its operand is the
;; pointer itself, in zero page, so the Apple III's extended addressing reads it through its bank byte, <TXTPTRB>,
;; as it would a (zp),Y pointer; CHSGOT reads the same character again. The eight bytes after the code become
;; <RNDX>.
;; Out: A = the character, zero = set at the end of a statement (a zero or a colon),
;;   carry = clear for a digit, set for anything else
;; See: <CHRGET>, <CHRGOT>, <INIT>
INITAT:
CHSGET:
    inc TXTPTR
    bne CHSGOT
    inc TXTPTR+1
CHSGOT:
    lda 60000
    cmp #':'                                ; Most characters are at or above the colon
    bcs CHSRT
    cmp #' '
    beq CHSGET
    sec                                     ; Leaves carry clear for 0 to 9 only
    sbc #'0'
    sec
    sbc #$100-'0'
CHSRT:
    rts
    .byte 0, 0, 0, 0                        ; The random number seed, for RNDX; INIT replaces two bytes of it
    .byte $10, $D6, $3A, $F1

;; BASIC's cold start, where SOS starts the interpreter: sets up memory, zero page and the console, then runs the
;; program `HELLO` or, when there is none, waits at the prompt.
;;
;; In order, it:
;; - records the bank BASIC runs in, from the bank register, in <BASICBNK> and in the console events' <KBDBNK> and
;;   <DCNTBNK>;
;; - reserves bank 0's $2000-$21FF with REQUEST_SEG (<SEGTAB4>), as BASIC's bank-switched pointers can't reach it;
;; - pushes a zero, the byte at the bottom of the stack that stops <FNDFOR>;
;; - clears zero page from $01 up, and the bank bytes of its pointers at <SYSPAG>;
;; - asks SOS for the program's memory with <TRYSEG>, which sets <RAMLOC> to its start and <MEMSIZ> to its end;
;; - copies <CHSGET> and the seed to <CHRGET> and <RNDX>, with their bank bytes zero;
;; - clears <TRMPOS>, <TRFLAG> (trace off) and <INFLNO> (no EXEC file);
;; - sets <FRETOP>, the top of the strings, to <MEMSIZ>, and <TXTTAB>, the program's start, to <RAMLOC>;
;; - seeds two bytes of <RNDX> from timers;
;; - calls <P1INIT>, <INITCNS> (which opens the console and prints the sign-on) and <SCRTCH> (NEW, which leaves an
;;   empty program, no variables and the stack pointer at <STKEND>);
;; - points the <DISPATCH> jump at <SWCHGO>, for invokable modules;
;; - runs `HELLO` as the direct command `RUN HELLO`, through <RUN>, when GET_FILE_INFO finds it, and otherwise
;;   goes to <MAIN> without a message.
;;
;; 1.3 first takes a program name the program selector left in zero page and runs that program instead.
;; See: <P1INIT>, <INITCNS>, <SCRTCH>, <HELF>
INIT:
    lda $FFEF                               ; The bank register
    sta a:KBDBNK
    sta BASICBNK
    sta a:DCNTBNK
    brk                                     ; REQUEST_SEG bank 0's $2000-$21FF
    .byte MREQ
    .word SEGTAB4
    pha                                     ; The zero that stops FNDFOR
.if VERSION >= 130
    ; 1.3: when the program selector started BASIC, it left $EE in locations 0 and 1 and a pointer to the program's
    ; pathname in 2 and 3. Copy the pathname to PROGPATH and set SELECTOR.
    lda #SELFLG
    cmp 0
    bne NOTSEL
    cmp 1
    bne NOTSEL
    ldy #0
    lda (2),Y                               ; The pathname's length
    tay
    lda (2),Y
    sta PROGPATH,Y
    dey
    bpl *-6
    sty SELECTOR                            ; $FF: the selector started BASIC
.endif

;; Clears zero page and its bank bytes, then carries on with <INIT>.
NOTSEL:
    ldx #0
    txa
    inx
    sta 0,X                                 ; $01-$FF
    sta SYSPAG-1,X                          ; and their bank bytes
    inx
    bne *-6
    jsr TRYSEG                              ; The program's memory
    ldx #INIT-INITAT

;; Copies <CHSGET> and the seed to <CHRGET> and <RNDX>, last byte first, clearing their bank bytes.
MOVCHG:
    lda INITAT-1,X
    sta CHRGET-1,X
    lda #0
    sta SYSPAG+CHRGET-1,X
    dex
    bne MOVCHG
    stx TRMPOS
    stx TRFLAG                              ; Trace off
    stx INFLNO                              ; No EXEC file
    ldy MEMSIZ
    lda MEMSIZ+1                            ; The strings start at the top of memory
    ldx MEMSIZB
    sty FRETOP
    sta FRETOP+1
    stx FRETOPB
    ldx RAMLOC
    ldy RAMLOC+1                            ; The program starts at the bottom
    lda RAMLOCB
    stx TXTTAB
    sty TXTTAB+1
    sta TXTTABB
    lda $FFD9                               ; A timer's high byte
    and #$7F
    sta RNDX+4
    lda $FFE9                               ; Another timer's high byte
    sta RNDX+5
    jsr P1INIT
    jsr INITCNS
    jsr SCRTCH
.if VERSION >= 130
    jsr FILSOS                              ; 1.3: keep SOS's prefix in SOSPATH
.endif
    lda #<(SWCHGO)
    sta DISPATCH+1
    lda #>(SWCHGO)
    sta DISPATCH+2
.if VERSION >= 130
    ; 1.3: with the selector, run the program it named, or, with no name, carry on as without it. The run-time
    ; version reports FILE NOT FOUND for no name.
    lda SELECTOR
    beq BOOTRUN
    lda PROGPATH
    beq nopgm
    lda #<(PROGPATH)                        ; GET_FILE_INFO on PROGPATH
    sta a:HELF+1
    lda #>(PROGPATH)
    sta a:HELF+2
    brk
    .byte SGFI
    .word HELF
    beq SELLO
nopgm1:
    ldx #$FF                                ; Direct, then report the error
    stx CURLIN+1
    jmp SERROR
SELLO:
    sta LINNUM                              ; RUN the program, as BOOTRUN runs HELLO
    sta LINNUM+1
    sta TXTPTRB
    dec CURLIN+1
    lda #<(PROGPATH+1)
    sta TXTPTR
    lda #>(PROGPATH+1)
    sta TXTPTR+1
    jsr CHRGOT
    jmp RUN
.if RUNTIME
nopgm:
    lda #SEFNF
    bne nopgm1
.else
nopgm:
.endif
.endif

;; Runs `HELLO` if it is there; otherwise goes to the prompt, or, in the run-time version, reports the error.
;;
;; The run is the direct command `RUN HELLO`: <TXTPTR> points at <HELCN>, and <CURLIN> is direct ($FF in its high
;; byte, one less than the zero <SCRTCH> left).
BOOTRUN:
.if VERSION >= 130
    jsr COPYSOS                             ; 1.3: the program's prefix is SOS's
.endif
    brk                                     ; GET_FILE_INFO on HELLO
    .byte SGFI
    .word HELF
    beq *+9                                 ; Found: run it
.if RUNTIME
    ldx #$FF
    stx CURLIN+1
    jmp SERROR
.else
    ldx CURLIN+1                            ; Does nothing
    stx CURLIN+1
    jmp MAIN
.endif
    sta LINNUM                              ; A = 0: line 0
    sta LINNUM+1
    sta TXTPTRB
    dec CURLIN+1
    lda #<(HELCN)
    sta TXTPTR
    lda #>(HELCN)
    sta TXTPTR+1
    jsr CHRGOT                              ; Reads the H
    jmp RUN

; ---------------------------------------------------------------------------------------------------------------------
; The console
; ---------------------------------------------------------------------------------------------------------------------

;; Opens .CONSOLE and sets it up: copies its reference number and device number into BASIC's console parameter
;; lists, resets it, turns on the CONTROL-C attention event, makes reads end at RETURN, and prints the sign-on.
;;
;; Invokable modules can call it through <JMPRTAB>.
;; Errors: a SOS error goes to <SERROR>
;; See: <OPNCNST>, <DGCN>, <DINIT>, <DCNTR>, <ISNLTB>, <SINIT>
INITCNS:
    brk
    .byte SOPN
    .word OPNCNST
    bne FUK2
    lda a:CONSRFN
    sta a:SCHRTB+1
    sta a:SLINTB+1
    sta a:SINIT+1
    sta a:ISNLTB+1
    sta a:RDCTC+1
    brk
    .byte SDGDN
    .word DGCN
    bne FUK2
    lda a:OTDN
    sta a:INDN
    sta a:INDN2
    sta a:INDN3
    sta a:INDN4
    sta a:INDN5
    sta a:INDN6
    brk                                     ; Control 0: reset
    .byte SDCNT
    .word DINIT
    bne FUK2
    brk                                     ; Control 6: the attention event
    .byte SDCNT
    .word DCNTR
    bne FUK2
    brk
    .byte SNWL
    .word ISNLTB
    bne FUK2
    brk
    .byte SWRT
    .word SINIT
    bne FUK2
    rts

;; Ends with the SOS error of one of <INITCNS>'s calls.
FUK2:
    jmp SERROR

;; The sign-on <INITCNS> writes: console codes that set the screen up, then BASIC's name, version and copyright.
;;
;; $10 2 sets text mode 2, 80 columns; $15 $D sets the console's options; 1 sets the viewport to the whole screen;
;; $1C clears it; 6 turns the cursor off; 7 beeps. After the text come three zeros, then RETURN and two line feeds.
;; See: <SINIT>
SICHRS:
    .byte $10, 2, $15, $D
    .byte 1
    .byte $1C
    .byte 6
    .byte 7
    .byte $0D
.if RUNTIME
    .byte "    "
.else
    .byte "       "
.endif
    .byte "Apple Business BASIC "
.if RUNTIME
    .byte "Run-Time "
.endif
.if VERSION = 123
    .byte "v1.23"
.else
    .byte "v1.3"
.endif
.if DEBUG
    .byte "D"                               ; The debugger's version
.endif
    .byte " - Copyright Apple Computer, 1980-83"
.if RUNTIME
.else
    .byte "       "
.endif
    .byte 0, 0, 0
    .byte $0D, $0A, $0A
SICLEN = *-SICHRS                           ;; the sign-on's length
    .byte $DA, $19, $83                     ; Three bytes nothing uses

; ---------------------------------------------------------------------------------------------------------------------
; Resetting BASIC's state
; ---------------------------------------------------------------------------------------------------------------------

;; Resets BASIC's state for a new program: no files, an empty program, nothing to report.
;;
;; It sets <CURLIN> direct (for any error message) and output to the console (<FILNO>), gives <OLDTXT> a bank of
;; $80, stores the JMP opcodes of <DISPATCH> and <JMPER>, clears <ERRFLG> (no ON ERR), <RNFLG> and the high byte of
;; <LASTPT>, sets up the string temporaries (<TEMPPT>, <FOUR6>), sets the defaults OUTREC = 80 and INDENT = 2, takes
;; all memory back with <EXPAND>, clears the ten file control blocks at <FCB>, and writes an empty program, three
;; zeros, at <TXTTAB>, with <ARYTAB> just after them.
;;
;; <INIT> calls it, and NEW through <SCRTCH>.
;; Uses: A, X, Y
;; See: <SCRTCH>
P1INIT:
    ldx #255
    stx CURLIN+1                            ; Direct
    stx FILNO                               ; Output to the console
    stx FILNO+1
    lda #$80
    sta OLDTXTB
    lda #$4C                                ; JMP, before the addresses in DISPATCH and JMPER
    sta DISPATCH
    sta JMPER
    ldx #0
    stx LASTPT+1
    stx ERRFLG
    lda #STRSIZ
    sta FOUR6
    ldx #TEMPST
    stx TEMPPT                              ; No string temporaries in use
    lda #80
    sta OUTREC                              ; LIST's right margin
    lda #2
    sta INDENT                              ; LIST's indent for each FOR
    lda #0
    jsr EXPAND                              ; All the memory there is
    ldy #0
    sty RNFLG
    tya
    sty ERRFLG
    dey
    sty FILNO                               ; Output to the console again
    sty FILNO+1
    ldy #FCBLEN*10                          ; The ten files' control blocks
    sta FCB-1,Y
    dey
    bne *-4
    sta (TXTTAB),Y                          ; The empty program
    iny
    sta (TXTTAB),Y
    iny
    sta (TXTTAB),Y
    lda TXTTAB
    clc
    adc #3
    sta ARYTAB
    lda TXTTAB+1
    adc #0
    ldy TXTTABB
    jsr FIXADC
    sta ARYTAB+1
    tya
    adc #0
    sta ARYTABB
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The stack
; ---------------------------------------------------------------------------------------------------------------------

FORSIZ = $14                                ;; the bytes a FOR entry takes on the stack

;; Finds the FOR entry for the variable in <FORPNT> on the stack, or the topmost FOR entry when <FORPNT> is zero.
;;
;; It starts above its caller's and the statement fetcher's return addresses. A FOR entry starts with <FORTK>, then
;; the variable's type and its pointer; the search stops at the first entry that isn't a FOR (a GOSUB entry, or
;; the zero <INIT> pushed at the bottom). When <FORPNT> is zero, it takes the top entry's variable into <FORPNT>,
;; <TEMPFOR>, <INTFLG> and <ISARA>.
;; In: FORPNT = the variable's pointer, or zero, TEMPFOR = its type
;; Out: zero = set when found, X = the entry's offset from the stack's page, less 1 (its <FORTK> is at $0101,X)
;; Uses: A
;; See: <FORSIZ>
FNDFOR:
    tsx
    inx
    inx
    inx
    inx                                     ; Above the two return addresses

;; Checks the stack entry at X for <FNDFOR>.
FFLOOP:
    lda 257,X
    cmp #FORTK
    bne FFRTS                               ; Not a FOR: no more to look at
    lda FORPNT+1
    ora FORPNT
    bne CMPFOR
    lda 259,X                               ; No variable given: take this one's
    sta FORPNT
    lda 260,X
    sta FORPNT+1
    lda 258,X
    sta TEMPFOR
    sta INTFLG
    ror
    ror ISARA

;; Compares the entry's variable and type with <FORPNT> and <TEMPFOR>.
CMPFOR:
    lda FORPNT+1
    cmp 260,X
    bne ADDFRS
    lda FORPNT
    cmp 259,X
    bne ADDFRS
    lda TEMPFOR
    cmp 258,X
    beq FFRTS                               ; Found

;; Steps to the next entry down the stack.
ADDFRS:
    txa
    clc
    adc #FORSIZ
    tax
    bne FFLOOP

;; Returns from <FNDFOR>.
FFRTS:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Moving memory
;
; BASIC's pointers into its memory are three bytes: an address whose page stays in MINPG to MAXPG-1 ($02-$81), and
; a bank byte at SYSPAG beside it. FIXADC and FIXSBC keep the page in range as they add and subtract.
; ---------------------------------------------------------------------------------------------------------------------

;; Moves a block of memory up, after checking with <REASON> that its new top is below the strings, and makes that
;; top the new <STREND>.
;;
;; The block runs from <LOWTR> to just below <HIGHTR>, and moves to end just below <HIGHDS>. It moves from the top
;; down, so the two may overlap.
;; In: A = the new end of the variables' low byte, Y = its high byte, X = its bank, LOWTR = the block's start,
;;   HIGHTR = its end, HIGHDS = where its end goes
;; Out: HIGHDS = where the block now starts, LOWTR = unchanged, HIGHTR = within a page of LOWTR
;; Errors: OUT OF MEMORY, from <REASON>
;; Entry: BLTUC = moves without the check or setting STREND
;; See: <MVUP>, <MVDWN>
BLTU:
    jsr REASON
    sta STREND
    sty STREND+1
    stx STRENDB

;; Moves the block for <BLTU>: whole pages while a page or more is left, then the rest. Invokable modules can call
;; it through <JMPRTAB>.
BLTUC:
    ldy HIGHTR                              ; How much is left to move
    cpy LOWTR
    lda HIGHTR+1
    sbc LOWTR+1
    ldy HIGHTRB
    ldx LOWTRB
    jsr FIXAYX
    cpy #0
    bne MV256
    cmp #1
    bcc MVEND                               ; Less than a page

;; Moves the top page of what is left down from <HIGHTR> to <HIGHDS>, lowering both by a page.
MV256:
    ldx #HIGHDS
    jsr SUB256
    ldx #HIGHTR
    jsr SUB256
    ldy #$FF

;; Copies a page, from the top down.
BLK2:
    lda (HIGHTR),Y
    sta (HIGHDS),Y
    dey
    bne BLK2
    lda (HIGHTR),Y                          ; And its first byte
    sta (HIGHDS),Y
    jmp BLTUC

;; Moves the last part of a page, from <LOWTR>, lowering <HIGHDS> to its start.
MVEND:
    lda HIGHTR
    sec
    sbc LOWTR
    beq MVDONE                              ; Nothing left
    pha                                     ; The bytes left
    ldy HIGHDSB
    sta HIGHDSB                             ; Briefly holds the count
    lda HIGHDS
    sec
    sbc HIGHDSB
    sta HIGHDS
    lda HIGHDS+1
    sbc #0
    cpy #$80                                ; A bank-switched pointer?
    bcc *+5
    jsr FIXSB2                              ; Keep its page in range
    sta HIGHDS+1
    sty HIGHDSB
    pla
    tay
    dey
    lda (LOWTR),Y
    sta (HIGHDS),Y
    dey
    cpy #$FF
    bne *-7

;; Returns from <BLTUC>.
MVDONE:
    rts

;; Lowers the three-byte pointer at X by a page, keeping its page in range.
;; In: X = the pointer's zero-page address
;; Uses: A, Y
SUB256:
    lda 1,X
    ldy SYSPAG,X                            ; The bank byte
    sec
    sbc #1
    jsr FIXSBC
    sta 1,X
    tya                                     ; There's no STY abs,X
    sta SYSPAG,X
    rts

;; Moves the memory from <INDEX1> up to <STREND> down to <LOWTR>, then adds <DELTA> to <VARTAB>, <ARYTAB> and
;; <STREND>.
;;
;; The caller sets <DELTA> (and <DELTAB>) to the distance, negative, in BASIC's three-byte form. The move goes from
;; the bottom up, so the two may overlap. Apple's comment said it adjusts every table pointer and buffer; it adjusts
;; just these three.
;; In: INDEX1 = the first byte to move, LOWTR = where it goes, DELTA = LOWTR less INDEX1
;; Out: LOWTR = unchanged
;; Uses: A, X, Y, INDEX1
;; <MVDWN2> adds <DELTA> to the pointers alone, from X = 5 (all three) or 3 (<ARYTAB> and <VARTAB>).
;; See: <MVUP>, <BLTU>, <MVDWN2>
MVDWN:
    lda LOWTR
    pha
    lda LOWTR+1
    pha
    lda LOWTRB
    pha
    ldy #0

;; Stops <MVDWN>'s loop when <INDEX1> reaches <STREND>.
MVDWN0:
    lda INDEX1
    cmp STREND
    bne MVDWN1
    lda INDEX1+1
    cmp STREND+1
    bne MVDWN1
    lda INDEX1B
    cmp STRENDB
    beq MVDWN3

;; Moves a byte and steps both pointers, keeping their pages in range.
MVDWN1:
    lda (INDEX),Y
    sta (LOWTR),Y
    inc INDEX1
    bne MVDWN4
    ldx INDEX1+1
    inx
    cpx #MAXPG
    bcc *+7
    ldx #MINPG                              ; Into the next bank
    inc INDEX1B
    stx INDEX1+1

;; Steps <LOWTR> for <MVDWN>.
MVDWN4:
    inc LOWTR
    bne MVDWN0
    ldx LOWTR+1
    inx
    cpx #MAXPG
    bcc *+7
    ldx #MINPG
    inc LOWTRB
    stx LOWTR+1
    bne MVDWN0                              ; Always

;; Gets <LOWTR> back, then adjusts the pointers.
MVDWN3:
    pla
    sta LOWTRB
    pla
    sta LOWTR+1
    pla
    sta LOWTR
    ldx #5                                  ; STREND, ARYTAB, VARTAB

;; Adds <DELTA> to the pointer at <VARTAB>-1+X, then to those below it.
MVDWN2:
    clc
    lda VARTAB-1,X
    adc DELTA
    sta VARTAB-1,X
    lda VARTAB,X
    adc DELTA+1
    ldy VARTABB-1,X
    jsr FIXADC
    sta VARTAB,X
    tya
    adc DELTAB
    sta VARTABB-1,X
    dex
    dex
    bpl MVDWN2
    rts

;; Moves the memory from <LOWTR> up to <STREND> up by <DELTA>, opening a gap at <LOWTR>, and adds <DELTA> to
;; <STREND>, <ARYTAB> and <VARTAB>.
;; In: LOWTR = the first byte to move, DELTA = the distance, positive
;; Out: LOWTR = unchanged
;; Errors: OUT OF MEMORY when the new top would reach the strings
;; See: <BLTU>, <MVDWN>
MVUP:
    lda STREND+1
    sta HIGHTR+1
    lda STRENDB
    sta HIGHTRB
    lda STREND
    sta HIGHTR                              ; The top of what moves
    clc
    adc DELTA                               ; and where it goes
    sta HIGHDS
    lda STREND+1
    adc DELTA+1
    ldy STRENDB
    jsr FIXADC
    sta HIGHDS+1
    tya
    adc DELTAB
    sta HIGHDSB
    tax
    ldy HIGHDS+1
    lda HIGHDS
    jsr BLTU
    ldx #3                                  ; BLTU set STREND: just ARYTAB and VARTAB
    jmp MVDWN2

; ---------------------------------------------------------------------------------------------------------------------
; Checking for room
; ---------------------------------------------------------------------------------------------------------------------

;; Checks that the stack has room for A more two-byte entries, beyond the levels every routine may use.
;;
;; Routines that push without limit, such as the formula evaluator, call it, and so do FOR and GOSUB, which leave
;; entries on the stack. The stack pointer must stay at or above 2A + 54 (2 * <NUMLEV> + 16 more).
;; In: A = the number of two-byte entries
;; Errors: STACK OVERFLOW
;; Uses: A, X, INDEX
GETSTK:
    asl
    adc #NUMLEV*2+3+13
    bcs OSERR
    sta INDEX
    tsx
    cpx INDEX
    bcc OSERR
    rts

;; Checks that an address is below <FRETOP>, the bottom of the strings, collecting the strings' garbage once if it
;; is not.
;;
;; Around the collection it keeps <HIGHDS> through <LOWTR> and their banks, which a block move may be using.
;; In: A = the address's low byte, Y = its high byte, X = its bank
;; Keeps: A, X, Y
;; Errors: OUT OF MEMORY when the address is still too high
;; See: <GARBA2>, <BLTU>
REASON:
    cpx FRETOPB
    bcc REARTS
    bne TRYMOR
    cpy FRETOP+1
    bcc REARTS
    bne TRYMOR
    cmp FRETOP
    bcc REARTS

;; Collects the strings' garbage for <REASON> and checks again.
TRYMOR:
    pha
    txa
    pha
    ldx #10+1
    tya

;; Pushes Y, then <HIGHDS> through <LOWTR>+1, eleven bytes.
REASAV:
    pha
    lda HIGHDS-1,X
    dex
    bpl REASAV
    lda LOWDSB
    pha
    lda LOWTRB
    pha
    lda HIGHDSB
    pha
    lda HIGHTRB
    pha
    jsr GARBA2
    pla
    sta HIGHTRB
    pla
    sta HIGHDSB
    pla
    sta LOWTRB
    pla
    sta LOWDSB
    ldx #$F5                                ; -11; the index wraps within zero page

;; Pulls <HIGHDS> through <LOWTR>+1 back for <REASON>.
REASTO:
    pla
    sta HIGHDS+10+1,X
    inx
    bmi REASTO
    pla
    tay
    pla
    tax
    pla
    cpx FRETOPB
    bcc REARTS
    bne OMERR
    cpy FRETOP+1
    bcc REARTS
    bne OMERR
    cmp FRETOP
    bcs OMERR

;; Returns from <REASON>.
REARTS:
    rts

;; Ends with STACK OVERFLOW.
;; See: <GETSTK>, <ERROR>
OSERR:
    ldx #ERRSK
    bne ERROR
