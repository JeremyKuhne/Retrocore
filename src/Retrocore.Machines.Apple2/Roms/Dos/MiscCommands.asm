;; DOS 3.3 AND 3.2 COMMAND HANDLERS: TEXT FILES, INIT, CATALOG AND BASIC (XMISCMD)
;;
;; The last command handler module, $A510-$A6A7 where DOS runs: the handlers for WRITE, READ, INIT, CATALOG,
;; FP, INT, EXEC and POSITION, which CMDETB (DosInit.asm) lists, and the code DOS's input and output hooks
;; (DosHook.asm) call to move the characters of a text file once READ, WRITE or EXEC has started.
;;
;; Text files work through BASIC's own PRINT and INPUT. READ and WRITE only open the file and set a state:
;; OSTATE, the state of the output hook, becomes 5, so that what the program prints next goes to the file
;; (OCTD); ISTATE becomes 1, so that the program's INPUT reads the file (ICFD). EXEC feeds a file to the input
;; hook in place of the keyboard (NXTEXC). The file stays open until CLOSE, the end of its data, or BASIC
;; going back to immediate mode (TSTRUN).
;;
;; FP and INT choose the BASIC. The Apple II has Integer BASIC or Applesoft in ROM at $D000-$FFFF, and a
;; language card in slot 0 can hold the other in RAM at the same addresses; SWTST finds the one wanted. Without
;; Applesoft in either, FP runs the System Master's APPLESOFT program, which loads Applesoft into lower RAM.
;; OpenClose.asm and LoadSave.asm hold the other handlers.

;; WRITE: positions the file named in FNAME1 (opening it if need be) and sends the program's output to it.
;;
;; Output state 5 marks the start of a line being written to the file (COS5 in DosHook.asm).
EWRITE:
    jsr RWPOSN
    lda #5
    sta a:OSTATE
    jmp CERTN

;; READ: positions the file named in FNAME1 (opening it if need be) and makes the program's input come from
;; it.
EREAD:
    jsr RWPOSN
    lda #1
    sta a:ISTATE
    jmp CERTN

;; Finds the file named in FNAME1, opening it as a text file if it is not open, and moves to the record CR
;; and byte CB when R or B is given.
;;
;; R and B are passed straight to the file manager's POSITION call, so they count from the start of the file:
;; records of the length given when the file was opened.
;; Out:   ZPGWRK = the file's buffer, whose work areas are in the parameter list
RWPOSN:
    jsr FILSRC
    bcc RWP1
    jsr EOPEN
    jmp RWP2
RWP1:
    jsr MVBUFP
RWP2:
    lda a:INOPTS
    and #R+B
    beq RWPR
    ldx #3
RWP2A:
    lda a:CR,x                      ; CR then CB, to parameter bytes 2-5: record and byte
    sta a:CCBRRN,x
    dex
    bpl RWP2A
RWP3:
    lda #CRQPOS
    sta a:CCBREQ
    jsr DOSGO
RWPR:
    rts

;; INIT: formats the disk, writes DOS onto it, then SAVEs the BASIC program in memory under the name in FNAME1
;; as the disk's greeting program.
;;
;; The volume number is V if given and not 0, otherwise 254. Parameter byte 1 (CCBBSA) gives the file manager
;; the first page of the DOS to copy: the high byte of BEGIN, $9D on a 48K machine.
EINIT:
    lda #V
    and a:INOPTS
    beq DFVOL
    lda a:CV
    bne EINITA
DFVOL:
    lda #$FE
    sta a:CV
EINITA:
    lda ASTART+1
    sta a:CCBBSA
    lda #CRQFMT
    jsr OPEN
    jmp ESAVE

;; CATALOG: has the file manager list the disk's files on the output device.
;;
;; CATALOG takes no file name, so the buffer OPEN lends to the file manager is never claimed. The volume the
;; file manager found is stored in CV.
ECAT:
    lda #CRQDIR
    jsr OPEN
    lda a:CCBVOL
    sta a:CV
    rts

;; FP: makes Applesoft the active BASIC and starts DOS and Applesoft afresh, losing the program in memory.
;;
;; If Applesoft is in ROM or the language card, DBINIT (DosInit.asm) starts DOS with it. If not, Integer BASIC
;; becomes the active BASIC and DOS RUNs the program named APPLESOFT, with ISTATE = $C0. That program loads
;; Applesoft into RAM and starts it. ISTATE $C0 then tells DOS's input hook, at Applesoft's first input, to
;; finish starting DOS for RAM Applesoft (INITC in DosInit.asm). With ISTATE $C0, a disk without APPLESOFT
;; gives LANGUAGE NOT AVAILABLE rather than FILE NOT FOUND (FOPEN in FileOpenCloseReadWrite.asm).
;;
;; LD1 (LoadSave.asm) comes here to switch to Applesoft for a program of that type.
EAS:
    lda #ATSTV
    jsr SWTST
    beq GOINIT
    lda #0
    sta a:ASIBSW                    ; Integer BASIC runs the APPLESOFT program
EAS0:
    ldy #30
    jsr CLRFNA                      ; blank FNAME1
    ldx #FASBL
EAS1:
    lda a:FASB-1,x                  ; "APPLESOFT"
    sta a:FNAME1-1,x
    dex
    bne EAS1
EAS2:
    lda #$C0
    sta a:ISTATE
    jmp ERUN

;; INT: makes Integer BASIC the active BASIC and starts DOS and Integer BASIC afresh, losing the program in
;; memory.
;;
;; LD1 (LoadSave.asm) comes here to switch to Integer BASIC for a program of that type.
;; Errors: LANGUAGE NOT AVAILABLE if Integer BASIC is in neither the ROM nor the language card
;; Entry: GOINIT = starts DOS with whichever BASIC $E000 now shows
EINT:
    lda #ITSTV
    jsr SWTST
    beq GOINT
    lda #1
    jmp ERROR
GOINT:
    lda #0
    sta a:RSTATE
GOINIT:
    jmp DBINIT

;; Looks for the BASIC whose first byte is A at $E000, switching the language card to it if need be.
;;
;; Applesoft starts with a JMP ($4C, ATSTV), Integer BASIC with a JSR ($20, ITSTV). The test is made with
;; memory as it is, then with the language card's RAM read ($C080, bank 2), then with the ROM read ($C081).
;; The language card switches respond to any access, so a write selects them as a read would. Without a
;; language card the switches do nothing and the test fails the same way three times.
;; In:    A = $4C for Applesoft, $20 for Integer BASIC
;; Out:   zero = set if found, with the memory it was found in selected
;; Keeps: A, X, Y
SWTST:
    cmp AITSTL
    beq SWTR
    sta $C080
    cmp AITSTL
    beq SWTR
    sta $C081
    cmp AITSTL
SWTR:
    rts

;; EXEC: opens the text file named in FNAME1 and takes the input of BASIC and DOS from it, line by line,
;; in place of the keyboard, skipping the first R lines when R is given.
;;
;; EFTABA keeps the file's buffer, and ESTATE, nonzero while EXEC runs, takes the first character of the name.
EEXEC:
    jsr EOPEN
    lda a:CFTABA
    sta a:EFTABA
    lda a:CFTABA+1
    sta a:EFTABA+1
    lda a:FNAME1
    sta a:ESTATE
    bne EXP2                        ; always: a name was given

;; POSITION: moves forward R lines from where the file named in FNAME1 is, opening it as a text file if it is
;; not open.
;;
;; Unlike R in READ and WRITE, this R counts lines, ends of line ($8D) read one byte at a time from the current
;; position; the file manager's POSITION call is not used.
;; Errors: END OF DATA if the file ends first
EPOS:
    jsr FILSRC
    bcc EXP1
    jsr EOPEN
    jmp EXP2
EXP1:
    jsr MVBUFP
EXP2:
    lda a:INOPTS
    and #R
    beq EX2
EX0:
    lda a:CR                        ; count CR down to 0, a line at a time
    bne EX1A
    ldx a:CR+1
    beq EX2
    dec a:CR+1
EX1A:
    dec a:CR
EX1:
    jsr RBYTE
    beq ICFD4
    cmp #$8D
    bne EX1
    beq EX0
EX2:
    rts

;; Writes the character the program printed to the open file: the output hook's handling of a WRITE.
;;
;; If BASIC is no longer running a program, the WRITE has ended: the file is closed, the input and output
;; states are cleared, and the character is dropped.
;; In:    SVA = the character; ZPGWRK = the file's buffer, its work areas in the parameter list
OCTD:
    jsr TSTRUN
    bcs ICFDB
    lda a:SVA
    sta a:CCBDAT
    lda #CRQWR
    sta a:CCBREQ
    lda #CRMNBT
    sta a:CCBRQM
    jmp DOSGO

;; Gives BASIC the next character of the open file as if it had been typed: the input hook's handling of a
;; READ. It leaves DOS through ORTN with the character in A.
;;
;; Output state 6 makes the output hook swallow the echo BASIC prints of the character (COS6). If BASIC is
;; not running a program, the READ has ended as in OCTD. At the end of the data the file is closed and END
;; OF DATA reported, except for EXEC, where the end of the file just ends the EXEC.
;;
;; A lowercase character ($E0 and up) is passed with bit 7 off, which the Monitor's GETLN on the II and II Plus
;; would otherwise turn into a capital. On the next call, ICFD sets bit 7 again on the previous character in
;; the input line LBUFF, using SVX, GETLN's index into it.
;; In:    ZPGWRK = the file's buffer, its work areas in the parameter list
;; Entry: ICFD3 = with A = the output state to set (3 for EXEC)
;; Errors: END OF DATA at the end of the file, outside EXEC
ICFD:
    jsr TSTRUN
    bcs ICFDB
    lda #6
ICFD3:
    sta a:OSTATE
    jsr RBYTE
    bne ICFD1
ICFD2:
    jsr CLOSE
    lda #3
    cmp a:OSTATE
    beq EX2                         ; EXEC: return to the input hook, which reads the keyboard
ICFD4:
    lda #CREEOF
    jmp ERROR
ICFD1:
    cmp #$E0
    bcc ICFNLC
    and #$7F
ICFNLC:
    sta a:SVA
    ldx a:SVX
    beq ICFD0                       ; nothing in the line yet
    dex
    lda LBUFF,x
    ora #$80
    sta LBUFF,x
ICFD0:
    jmp ORTN

;; Tells whether BASIC is running a program or is in immediate mode.
;;
;; Applesoft is taken to be running unless the high byte of its current line number ($76) is $FF, as it is in
;; immediate mode, or the prompt (PROMPT, $33) is "]". Integer BASIC is running when bit 7 of $D9 is set.
;; Out:   carry = clear if a program is running, set if not
;; Uses:  X
;; Keeps: A, Y
TSTRUN:
    pha
    lda a:ASIBSW
    beq TR1
    ldx $76
    inx
    beq NOTRUN
    ldx PROMPT
    cpx #']'+$80
    beq NOTRUN
TR0:
    pla
    clc
    rts
TR1:
    lda $D9
    bmi TR0
NOTRUN:
    pla
    sec
    rts

;; Ends a READ or WRITE that BASIC has left: closes the file, clears the input and output states and leaves
;; DOS through ORTN.
ICFDB:
    jsr CLOSE
    jsr CLRSTS
    jmp ORTN

;; Gives BASIC the next character of the EXEC file in place of a key: the input hook calls it while ESTATE is
;; set. It leaves DOS through ORTN with the character, and returns only at the end of the file.
;;
;; Output state 3 makes the output hook treat what BASIC prints next as the echo of an EXEC character (COS3).
NXTEXC:
    jsr MVEFTA
    jsr MVBUFP
    lda #3
    bne ICFD3

;; Reads the next byte of the open file.
;; In:    CCBFCB/CCBDBP/CCBSBP = the file's work areas, in the parameter list
;; Out:   A = the byte, zero = set if it is 0, which a text file ends with and DOSGO gives at the end of the data
RBYTE:
    lda #CRQRD
    sta a:CCBREQ
    lda #CRMNBT
    sta a:CCBRQM
    jsr DOSGO
    lda a:CCBDAT
    rts

;; Points ZPGWRK at the EXEC file's buffer.
;; Keeps: X, Y
MVEFTA:
    lda a:EFTABA+1
    sta ZPGWRK+1
    lda a:EFTABA
    sta ZPGWRK
    rts
