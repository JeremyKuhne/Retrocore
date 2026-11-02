;; DOS 3.3 AND 3.2 COMMAND INTERPRETER: SCAN A COMMAND LINE (CMDSCAN)
;;
;; Parses the line in LBUFF ($0200) that the output hook (DosHook.asm) has collected, either after a Control-D
;; or typed at BASIC's prompt, and calls the command's handler. In order:
;;
;; - SCNCMD looks the command's name up in CMDNTB (CommandTables.asm). Blanks are skipped, so "CAT ALOG"
;;   matches too. The command's number, doubled, ends up in CMDNO.
;; - SYNTAX checks the command's entry in CMDSTB: whether it may be used in direct mode, and whether it takes
;;   one or two file names (into FNAME1 and FNAME2, 30 characters each, padded with blanks) or a number (the
;;   slot of PR# and IN#, the count of MAXFILES).
;; - SOPTS reads the keyword options that follow, ",V254", ",D2", ",S6", ",A$2000" and the rest, into CUROPT
;;   (CV, CD, CS, CL, CR, CB, CA), checking each against its range in OPTAB3 and the set the command allows.
;; - CMDGO calls the handler through CMDETB (DosInit.asm).
;;
;; A line that is not a DOS command is passed on to BASIC if it was typed, and is a SYNTAX ERROR if it came
;; after a Control-D. So are a few half-commands BASIC has its own meaning for: LOAD, SAVE and RUN with no file
;; name (cassette LOAD and SAVE, BASIC's RUN), and names that do not start with a letter (RUN 100).
;;
;; Runs at $9FCD-$A192 where DOS runs. The character routines it uses, GNBC, GNXTC and GETNUM, are in
;; OpenClose.asm.

;; Scans the command line in LBUFF and, if it is a DOS command, carries it out.
;;
;; Each entry of CMDNTB is compared with the line in turn. The status pushed by PHP holds the result so far in
;; its Z flag: set (from LDX #0) at the start of an entry, replaced by a copy with Z clear at the first
;; character that differs. In each comparison, the EOR leaves the table character's top bit, which marks the
;; last character of a name, in bit 7, and ASL moves it into the carry while the rest says whether the
;; characters match.
;;
;; It does not return: it leaves through CMDGO and CERTN, an error (ERROR), or PRRTN for a line that is not a
;; command.
;; In:    LBUFF = the line, ending in a return; it may start with Control-D (CCHAR)
SCNCMD:
.if ULC
    ; The lowercase build: UPRCASE (BootLoader.asm) raises letters outside quotes to capitals and returns with
    ; Y = CMDNO = $FF.
    ldx #0
    jsr UPRCASE
.else
    ldy #$FF
    sty a:CMDNO                     ; incremented to 0 for the first command
.endif
    iny                             ; Y = 0, the index into CMDNTB
    sty a:SVCMD                     ; no command saved for INITC to resume
SC0:
    inc a:CMDNO
    ldx #0                          ; sets Z: matches so far
    php
    lda LBUFF,x
    cmp a:CCHAR
    bne SC0A
    inx                             ; skip the Control-D
SC0A:
    stx a:LBUFD
SC1X:
    jsr GNBC
    and #$7F
    eor a:CMDNTB,y
    iny
    asl a                           ; carry = last character of the name; A = 0 if the characters match
    beq SC1A
    pla
    php                             ; a mismatch: replace the saved status with this one, Z clear
SC1A:
    bcc SC1X
    plp
    beq SYNTAX                      ; every character matched
    lda a:CMDNTB,y
    bne SC0                         ; try the next name; a 0 ends the table
;; Command not found. A typed line goes to BASIC; a Control-D line is a syntax error, except a Control-D alone,
;; which does nothing.
CNF:
    lda LBUFF
    cmp a:CCHAR
    beq CNF1
    jmp PRRTN                       ; typed: print the return and let BASIC have the line
CNF1:
    lda LBUFF+1
    cmp #$8D
    bne CSERR
    jsr CLRSTS
    jmp CMDRTN
CSERR:
    jmp ESYNTX

;; Checks and collects the operands of the command found: the file names or the number.
;;
;; The status pushed after CLRFNS and before the second name records which name is being read: Z set for the
;; first (Y = 0 then), Z clear for the second (Y = 30).
;; In:    CMDNO = the command's number; LBUFD = the index just past its name
SYNTAX:
    asl a:CMDNO                     ; CMDNO * 2 indexes CMDSTB and CMDETB, two bytes an entry
    ldy a:CMDNO
    jsr TSTRUN                      ; carry clear while a program is running
    bcc SYN1
    lda #RNONLY
    and a:CMDSTB,y
    beq SYN1
    lda #$F                         ; a program-only command typed in direct mode: NOT DIRECT COMMAND
    jmp ERROR
SYN1:
    cpy #6                          ; RUN (command 3)
    bne SYN1A
    sty PROMPT                      ; make the prompt not "]", so that TSTRUN sees the program as running
SYN1A:
    lda #FN1
    and a:CMDSTB,y
    beq SN10                        ; no file name: maybe a number
    jsr CLRFNS
    php                             ; Z set: reading the first name
SN2:
    jsr GNBC
    beq SN6                         ; a comma or the return: no name
    asl a                           ; carry = bit 7, N = bit 6 of the character
    bcc SN2A
    bmi SN2A                        ; $C0-$FF: a letter, or one of @[\]^_
    jmp CNF                         ; anything else ($80-$BF: a digit, punctuation) can't start a name
SN2A:
    ror a
    jmp SN4
SN3:
    jsr GNXTC                       ; inside the name, blanks count
    beq SN6
SN4:
    sta a:FNAME1,y
    iny
    cpy #60
    bcc SN3
SN5:
    jsr GNXTC                       ; at the limit: skip the rest of the name
    bne SN5
SN6:
    plp
    bne SN7                         ; that was the second name
    ldy a:CMDNO
    lda #FN2
    and a:CMDSTB,y
    beq SN8
    ldy #30                         ; the second name goes to FNAME2
    php                             ; Z clear: reading the second name
    bne SN2                         ; always
SN7:
    lda a:FNAME2
    cmp #$A0
    beq SERR1                       ; the second name is missing
SN8:
    lda a:FNAME1
    cmp #$A0
    bne SOPTS
    ; No file name. Commands with NPE do without one; those with NPB go to BASIC; the rest are errors.
    ldy a:CMDNO
    lda #NPB+NPE
    and a:CMDSTB,y
    beq SERR1
    bpl SOPTS                       ; NPE ($40) without NPB ($80)
SERR1:
    jmp CNF

;; Fills both file names, FNAME1 and FNAME2, with blanks.
;; Out:   Y = 0, Z set
;; Uses:  A
;; Entry: CLRFNA = fills the Y bytes from FNAME1 with blanks
CLRFNS:
    ldy #60
CLRFNA:
    lda #$A0
SN1:
    sta a:FNAME1-1,y
    dey
    bne SN1
    rts

;; The command takes no file name. Reads its number if it takes one: a slot 0-7 (NUM1: PR#, IN#) or a count
;; 1-16 (NUM2: MAXFILES), left in CNUM.
;; In:    A = 0, Y = CMDNO
SN10:
    sta a:FNAME1                    ; A = 0: the first name's first character becomes 0
    lda #NUM1+NUM2
    and a:CMDSTB,y
    beq SOPTS
    jsr GETNUM                      ; X = low byte, A = high byte; carry set if not a number
    bcs SERR2
    tay
    bne SERR3                       ; 256 or more
    cpx #17
    bcs SERR3                       ; more than 16
    ldy a:CMDNO
    lda #NUM1
    and a:CMDSTB,y
    beq SN11
    cpx #8
    bcs SERR1                       ; a slot of 8 or more: not a DOS command
    bcc SOPTS                       ; always
SN11:
    txa
    bne SOPTS                       ; MAXFILES 0 is a range error
SERR3:
    lda #2                          ; RANGE ERROR
    jmp ERROR
SERR2:
    jmp ESYNTX

;; Reads the keyword options after the operands, each a letter from OPTAB1, and checks them.
;;
;; V, D, S, L, R, B and A take a number, decimal or hex after "$", which is checked against the option's range
;; in OPTAB3 and stored in CUROPT. C, I and O (for MON and NOMON) take none and set bits in IMBITS. INOPTS gets
;; a bit for each option given (OPTAB2), and at the end any option the command does not allow (the second byte
;; of its CMDSTB entry) is an error.
;;
;; The code has room for two passes, the first checking without storing: TEMP1A not 0 would mean the first
;; pass, holding the index to start the second from. But TEMP1A is set to 0 here, so there is one pass, and
;; each value is stored as soon as it is checked.
;;
;; It does not return: it goes on to CMDGO, or to an error.
;; In:    LBUFD = the index of the first character after the operands
SOPTS:
    lda #0
    sta a:INOPTS
    sta a:IMBITS
    sta a:CV                        ; volume 0: any volume
    sta a:CL
    sta a:CL+1
    jsr CLRBYTE                     ; TEMP1A = 0 and CB = 0 (DosPatches.asm)
    lda a:LBUFD                     ; not used: TEMP1A stays 0
SP1:
    jsr GNBC
    bne SP2                         ; an option letter
    cmp #$8D
    bne SP1                         ; a comma: go on
    ; The end of the line. INOPTS OR allowed, EOR allowed, leaves the options given but not allowed.
    ldx a:CMDNO
    lda a:INOPTS
    ora a:CMDSTB+1,x
    eor a:CMDSTB+1,x
    bne SERR1
    ldx a:TEMP1A
    beq CMDGO                       ; the (only) pass is done
    sta a:TEMP1A
    stx a:LBUFD
    bne SP1
SP2:
    ldx #OPT1L
SP3:
    cmp a:OPTAB1-1,x
    beq SP4
    dex
    bne SP3
SERR2A:
    beq SERR2                       ; not an option letter
SP4:
    lda a:OPTAB2-1,x
    bmi SP8                         ; C, I or O
    ora a:INOPTS
    sta a:INOPTS
    dex
    stx a:TEMP2A                    ; the option's number, 0 for V to 6 for A
    jsr GETNUM
    bcs SERR2
    ; Compare CNUM with the option's lowest and highest values in OPTAB3, four bytes from TEMP2A * 4.
    lda a:TEMP2A
    asl a
    asl a
    tay
    lda CNUM+1
    bne SP5                         ; 256 or more: above every lowest value
    lda CNUM
    cmp a:OPTAB3,y
    bcc SERR3
    lda CNUM+1
SP5:
    cmp a:OPTAB3+3,y
    bcc SP6
SERR3A:
    bne SERR3
    lda CNUM
    cmp a:OPTAB3+2,y
    bcc SP6
    bne SERR3A
SP6:
    lda a:TEMP1A
    bne SP1                         ; first pass: don't store (never taken)
    tya
    lsr a
    tay                             ; the option's number * 2 indexes CUROPT
    lda CNUM+1
    sta a:CUROPT+1,y
    lda CNUM
    sta a:CUROPT,y
SP7:
    jmp SP1
SP8:
    pha
    lda #CIO
    ora a:INOPTS
    sta a:INOPTS
    pla
    and #$7F
    ora a:IMBITS                    ; MC, MI or MO
    sta a:IMBITS
    bne SP7                         ; always
    beq SERR2A

;; Carries out the command, then leaves DOS through CERTN (DosHook.asm).
CMDGO:
    jsr CMDGO1
    jmp CERTN

;; Calls the handler for the command in CMDNO, after clearing the input and output states and the file
;; manager's parameter list (the CCB).
;;
;; The handler's address less one is pushed from CMDETB, and RTS goes to it; its own RTS returns to this
;; routine's caller. INITC (DosInit.asm) also jumps here, to run the greeting program after a boot or to resume
;; the command saved in SVCMD.
;; In:    CMDNO = the command's number * 2; the options in CUROPT, INOPTS and IMBITS
;; Entry: ECMD = calls the handler without clearing anything
CMDGO1:
    jsr CLRSTS
    jsr CLRCCB
ECMD:
    lda a:CMDNO
    tax
    lda CMDETB+1,x
    pha
    lda CMDETB,x
    pha
    rts
