;; DOS 3.3 AND 3.2 COMMAND INTERPRETER: THE INPUT AND OUTPUT HOOKS (DOSHOOK)
;;
;; How DOS hears BASIC. Every character the Apple II prints goes through the Monitor's COUT, which jumps through
;; the output hook CSW ($36-$37, OUTSW here); every character it reads goes through RDKEY, which jumps through
;; the input hook KSW ($38-$39, INSW). DOS puts its own routines in both, CHROUT ($9EBD) and CHRIN ($9E81), and
;; keeps the real handlers (normally the screen and keyboard, or a card after PR# or IN#) in SVOUTS and SVINS.
;; MVCSW (BuildFileTables.asm) installs the hooks, and puts them back each time DOS exits, since BASIC and
;; PR#/IN# overwrite $36-$39 freely.
;;
;; How PRINT CHR$(4);"CATALOG" reaches a command handler:
;;
;; - PRINT sends Control-D ($84 with the high bit set, CCHAR), then C, A, T ... and a return, each through COUT
;;   and so to CHROUT. CHROUT saves the registers and stack pointer (SVREGS), hands $36-$39 back to the real
;;   handlers so anything DOS prints goes straight out, and jumps to the handler for the output state OSTATE.
;; - At the start of a line OSTATE is 0, so COS0 sees the Control-D, sets state 1 and starts filling the line
;;   buffer LBUFF ($0200). COS1 adds each later character; nothing is shown unless MON C is on.
;; - The return ends the line and COS1 jumps to SCNCMD (CommandScan.asm). It finds CATALOG in the name table
;;   CMDNTB, checks the operands against CMDSTB, collects options into CV, CD, CS and the rest, and CMDGO calls
;;   the handler through the address table CMDETB, here ECAT in MiscCommands.asm. Handlers call the file
;;   manager through DOSGO (DosGoer.asm).
;; - When the handler returns, CERTN and ORTN finish the "print": they put DOS's hooks back, restore the stack
;;   pointer and registers saved on entry, and return to whoever called COUT, as though the return had been
;;   printed.
;;
;; Commands typed at BASIC's prompt take another path. CHRIN sets OSTATE to 3 before it reads a key, so the
;; echo of that key, which BASIC's line input (the Monitor's GETLN) prints through COUT, goes to COS3. GETLN
;; keeps the line in $0200 too; when the return is echoed in direct mode, COS3 hands the line to SCNCMD as if it
;; had come after a Control-D. If it is a DOS command, CERTN empties the line so BASIC sees a blank one.
;;
;; The other states carry WRITE (output goes to a file: states 4 and 5) and READ (input comes from a file:
;; ISTATE, and state 6 to hide INPUT's prompt). An EXEC file (ESTATE) feeds CHRIN in place of the keyboard.
;; docs/Dos.md describes the whole interpreter. Runs at $9E81-$9FCC where DOS runs.

;; DOS's input hook: KSW points here, so the Monitor's RDKEY comes here for every character BASIC reads.
;;
;; While a file is being read (READ), the character comes from the file (ICFD). The first read after DOS
;; starts finishes starting it (INITC). Otherwise an EXEC file supplies the character (NXTEXC), or, when there
;; is none, the real input routine does. OSTATE is set to 3 so the echo of the character is checked for a
;; typed command.
;; In:    A = the screen character under the cursor, Y = the cursor column, BASL ($28) = the cursor's row, as
;;        RDKEY leaves them
;; Out:   A = the character read (through ORTN); from the real input routine, X as it returns it too
CHRIN:
    jsr SVREGS
    lda a:ISTATE
    beq CHIN1                       ; not reading a file and not just started: go read
    pha
    lda a:SVA
    sta ($28),y                     ; put back the character RDKEY replaced with a flashing cursor
    pla
    bmi CHIN0                       ; ISTATE negative: DOS has just started
    jmp ICFD                        ; ISTATE positive: READ is on; take the character from the file
CHIN0:
    jsr INITC                       ; finish starting DOS (DosInit.asm)
    ldy $24                         ; CH, the cursor column
    lda #$60                        ; a flashing space: the cursor again, since a key will be read after all
    sta ($28),y
CHIN1:
    lda a:ESTATE
    beq CHIN2
    jsr NXTEXC                      ; take the character from the EXEC file; returns here only at its end
CHIN2:
    lda #3
    sta a:OSTATE                    ; the echo of this character goes to COS3
    jsr LDREGS
    jsr GETIN
    sta a:SVA
    stx a:SVX
    jmp ORTN

;; Calls the real input routine, whose address SVREGS has put back in INSW.
GETIN:
    jmp (INSW)

;; DOS's output hook: CSW points here, so the Monitor's COUT comes here for every character printed.
;;
;; Saves the registers and goes to the handler for the current output state, COS0 to COS6, through OUTSVT
;; (DosInit.asm). The table holds each address less one, and pushing it and returning goes there: the 6502's
;; RTS adds one to the address it pulls.
;;
;; It returns to COUT's caller through ORTN, with the registers as the real output routine leaves them, or as on
;; entry if the character was not printed. The state handlers start with A = the character.
;; In:    A = the character
CHROUT:
    jsr SVREGS
    lda a:OSTATE
    asl a
    tax
    lda OUTSVT+1,x
    pha
    lda OUTSVT,x
    pha
    lda a:SVA
    rts

;; Saves the registers on entry to DOS and gives $36-$39 back to the real input and output routines.
;;
;; SVSTK gets the stack pointer as it was before the JSR here, so that ORTN can later return to the program
;; that called COUT or RDKEY whatever DOS has pushed in between. With the real routines back in OUTSW and INSW,
;; what DOS prints or reads while it works does not come back into DOS.
;; In:    A, X, Y = the caller's registers
;; Out:   SVA/SVX/SVY = A, X and Y, SVSTK = the stack pointer before the JSR here, OUTSW/INSW = SVOUTS/SVINS
;; Uses:  A, X
;; Entry: SVRGSA = saves all but A
SVREGS:
    sta a:SVA
SVRGSA:
    stx a:SVX
    sty a:SVY
    tsx
    inx
    inx                             ; drop this routine's own return address
    stx a:SVSTK
    ldx #3
SVRB:
    lda a:SVOUTS,x                  ; SVOUTS and SVINS lie in the same order as OUTSW and INSW
    sta OUTSW,x
    dex
    bpl SVRB
    rts

;; Output state 0: the first character of a line. A Control-D here starts a DOS command.
;;
;; While ISTATE is not 0 (normally because READ is on, and BASIC's INPUT is reading from the file), a "?", which
;; INPUT prints as its prompt, is hidden unless MON I is on (COS6), and the prompt character in PROMPT is printed
;; with the state left at 0.
;; In:    A = the character
COS0:
    ldx a:RSTATE
    beq COS00
    jmp COS7                        ; a RUN is waiting to be finished
COS00:
    ldx a:ISTATE
    beq COS01
    cmp #'?'+$80
    beq COS6
    cmp PROMPT                      ; PROMPT ($33): the character the Monitor's GETLN prints first
    beq COS2A
COS01:
    ldx #2
    stx a:OSTATE                    ; an ordinary line, unless ...
    cmp a:CCHAR
    bne COS2
    dex
    stx a:OSTATE                    ; ... it starts with Control-D: state 1
    dex
    stx a:LBUFD                     ; and the line buffer starts empty; the Control-D goes in first

;; Output state 1: collects a command line in LBUFF, and scans it at the return.
;; In:    A = the character
;; Entry: COS1A = stores at X rather than LBUFD (COS3's typed line)
COS1:
    ldx a:LBUFD
COS1A:
    sta LBUFF,x
    inx
    stx a:LBUFD
    cmp #$8D
    bne CMDRTN                      ; not yet the end: shown only under MON C
    jmp SCNCMD

;; Output state 2: the rest of an ordinary line. Prints it; the return goes back to state 0.
;; In:    A = the character
;; Entry: COS2A = goes back to state 0 and prints, whatever the character
COS2:
    cmp #$8D
    bne PRRTN
COS2A:
    ldx #0
    stx a:OSTATE
    jmp PRRTN

;; Output state 3: the echo of a character just read through CHRIN.
;;
;; Prints it, unless it came from an EXEC file, when only MON I shows it. At a return, if the line was typed in
;; direct mode or came from an EXEC file, it is a possible command: the line is already in LBUFF, where GETLN
;; keeps it, so COS1A adds the return and scans it. Lines a running program reads with INPUT are left alone.
;; In:    A = the character
COS3:
    ldx #0
    stx a:OSTATE
    cmp #$8D
    beq COS3A
COS3B:
    lda a:ESTATE
    beq PRRTN
    bne DRTNI
COS3A:
    pha
    sec                             ; from an EXEC file: as if in direct mode
    lda a:ESTATE
    bne COS3C
    jsr TSTRUN                      ; carry set in direct mode, clear while a program runs
COS3C:
    pla
    bcc COS3B
    ldx a:SVX                       ; GETLN's X: the length of the line
    jmp COS1A

;; Output state 4: WRITE is on and this is not the first character of a line. Writes the character to the file
;; (OCTD); shown only under MON O. A return moves to state 5.
;; In:    A = the character
COS4:
    cmp #$8D
    bne COS4A
    lda #5
    sta a:OSTATE
COS4A:
    jsr OCTD
    jmp DRTNO

;; Output state 5: WRITE is on and this is the first character of a line. A Control-D starts a command, as at
;; state 0; a line feed is written without leaving state 5; anything else is written in state 4.
;; In:    A = the character
COS5:
    cmp a:CCHAR
    beq COS0
    cmp #$8A
    beq COS4A
    ldx #4
    stx a:OSTATE
    bne COS4                        ; always

;; Output state 6: the echo of a character read from a file (ICFD sets this state), and COS0 sends INPUT's "?"
;; here while READ is on. Shown only under MON I; goes back to state 0.
COS6:
    lda #0
    sta a:OSTATE
    beq DRTNI                       ; always

;; Finishes a RUN under Applesoft. ERUN (LoadSave.asm) sets RSTATE, then loads the program, and an Applesoft load
;; ends by jumping into Applesoft through ASEQ instead of returning. So the RUN is finished here, when Applesoft
;; next prints at the start of a line: ERUN1 starts the program.
COS7:
    lda #0
    sta a:RSTATE
    jsr MVCSW
    jmp ERUN1

;; Where a command handler returns (through CMDGO): ends the command line and leaves DOS.
;;
;; A line BASIC printed after a Control-D is simply finished. A line typed at the prompt is replaced by an empty
;; one, a return at $0200 with X = 0, so that GETLN hands BASIC a blank line instead of the DOS command.
;; In:    SVA = the return that ended the line
CERTN:
    lda LBUFF
    cmp a:CCHAR
    beq CMDRTN
    lda #$8D
    sta LBUFF
    ldx #0
    stx a:SVX                       ; GETLN's line length on return
;; The ways out of DOS from an output state. Each prints the character in SVA only if its MON option is on
;; (MONMOD bit MC, MO or MI); PRRTN always prints it. All end at ORTN.
;; Entry: DRTNO = only under MON O (file output), DRTNI = only under MON I (file input), MODECK = with A = the
;;        bit, PRRTN = always
CMDRTN:
    lda #MC
    bne MODECK
DRTNO:
    lda #MO
    bne MODECK
DRTNI:
    lda #MI
MODECK:
    and a:MONMOD
    beq ORTN
PRRTN:
    jsr LDREGS
    jsr ORTN1                       ; the real output routine
    sta a:SVA                       ; return the registers as it leaves them
    sty a:SVY
    stx a:SVX
;; Leaves DOS: puts DOS's hooks back in $36-$39, resets the stack pointer to what it was on entry to CHRIN or
;; CHROUT, and returns to their caller with the saved registers.
;;
;; Any routine in DOS may jump here, however deep: the stack reset discards whatever is above the caller's
;; return address.
;; Out:   A, X, Y = SVA, SVX, SVY; carry set
ORTN:
    jsr MVCSW
    ldx a:SVSTK
    txs
;; Loads A, X and Y from SVA, SVX and SVY.
;; Out:   carry = set
LDREGS:
    lda a:SVA
    ldy a:SVY
    ldx a:SVX
    sec
    rts

;; Calls the real output routine, whose address SVREGS has put back in OUTSW.
ORTN1:
    jmp (OUTSW)

;; Prints a return through the real output routine.
;; Uses:  A
PRCRIF:
    lda #$8D
    jmp ORTN1
