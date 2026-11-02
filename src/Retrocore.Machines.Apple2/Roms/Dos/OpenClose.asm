;; DOS 3.3 AND 3.2 COMMAND HANDLERS: OPEN, CLOSE AND FILE COMMANDS (XOPNCLS)
;;
;; The first of the three command handler modules, $A193-$A330 where DOS runs. It starts with the helpers the
;; command scanner (CommandScan.asm) uses to read the command line in LBUFF ($0200): the next character, the
;; next non-blank, and a decimal or $hex number. Then come the handlers for PR#, IN#, MON, NOMON, MAXFILES,
;; DELETE, LOCK, UNLOCK, VERIFY, RENAME, APPEND, OPEN and CLOSE, which CMDETB (DosInit.asm) lists, and the code
;; they and the other handlers share to open and close files.
;;
;; A handler finds the parsed command in DOS's variables: the file names in FNAME1 and FNAME2, the keywords
;; given as bits in INOPTS and their values in CV, CD, CS, CL, CR, CB and CA, the C, I and O of MON and NOMON in
;; IMBITS, and a number given after the command in CNUM. It acts on files by filling in CCB, the file manager's
;; parameter list (FileManagerData.asm; Beneath Apple DOS ch06 gives its layout), and calling DOSGO
;; (DosGoer.asm). DOSGO deals with errors itself: it frees the file's buffer, prints the message and leaves to
;; BASIC, so a handler only sees calls that worked.
;;
;; Each open file has a DOS buffer, one of MAXFILES chained in high memory (BuildFileTables.asm). $40-$41
;; (ZPGWRK) points at a buffer's 30-byte file name, which is followed by the addresses of its file manager
;; workarea, track/sector list buffer and data buffer, then the next buffer's name (0 on the last). A first
;; name byte of 0 marks the buffer free; copying a name in claims it. LoadSave.asm and MiscCommands.asm hold
;; the other handlers; docs/Dos.md describes the command interpreter as a whole.

;; Reads the next character of the command line and steps past it, unless it is the carriage return.
;; In:    LBUFD = index of the character in LBUFF
;; Out:   A = the character; Z set if it is a comma or the carriage return; LBUFD past it unless a return
;; Uses:  X
;; Keeps: Y
GNXTC:
    ldx a:LBUFD
    lda LBUFF,x
    cmp #$8D                        ; the line ends in a carriage return: stay on it
    beq GNXTCR
    inx
    stx a:LBUFD
    cmp #','+$80
GNXTCR:
    rts

;; Reads the next character of the command line that is not a space.
;; Out:   A = the character; Z set if it is a comma or the carriage return; LBUFD past it unless a return
;; Uses:  X
;; Keeps: Y
GNBC:
    jsr GNXTC
    beq GNXTCR
    cmp #$A0
    beq GNBC
    rts

;; Clears CCB, the file manager's parameter list, to zeros; CMDGO1 does it before every command.
;; Out:   A = 0, Y = 0
;; Keeps: X
CLRCCB:
    lda #0
    ldy #CCBLEN
CLC1:
    sta a:CCB-1,y
    dey
    bne CLC1
    rts

;; Converts the number at LBUFD in the command line, decimal or, after a "$", hexadecimal, to 16 bits.
;;
;; The number ends at a comma or the carriage return; spaces between digits are skipped. An empty number
;; gives 0. In decimal, a carry out of the final addition counts as too large, but bits lost from the
;; multiplications are not caught; in hex, digits beyond four simply push the first ones out.
;; In:    LBUFD = index of the first character
;; Out:   carry clear, CNUM and X = the low byte, A = the high byte; carry set if a character is not a digit
;; Uses:  A, X, Y, CNUM, LBUFD
GETNUM:
    lda #0
    sta CNUM
    sta CNUM+1
    jsr GNBC
    php                             ; keep GNBC's Z (comma or return) past the test for "$"
    cmp #$A4
    beq HEXNUM
    plp
    jmp GN2A
GN2:
    jsr GNBC
GN2A:
    bne GN3
    ldx CNUM
    lda CNUM+1
    clc
    rts
; A decimal digit: CNUM = CNUM * 10 + digit, made as CNUM * 2 + digit (kept in Y,X) plus CNUM * 8.
GN3:
    sec
    sbc #$B0
    bmi GN4
    cmp #10
    bcs GN4
    jsr GN5                         ; CNUM * 2
    adc CNUM
    tax
    lda #0
    adc CNUM+1
    tay
    jsr GN5
    jsr GN5                         ; CNUM * 8
    txa
    adc CNUM
    sta CNUM
    tya
    adc CNUM+1
    sta CNUM+1
    bcc GN2
GN4:
    sec
    rts

;; Doubles CNUM.
;; Out:   carry = the bit shifted out of the top
;; Keeps: A, X, Y
GN5:
    asl CNUM
    rol CNUM+1
    rts

; A "$" came first: the digits that follow are hexadecimal, 0-9 and A-F.
HEXNUM:
    plp
HN0:
    jsr GNBC
    beq GN2A
    sec
    sbc #$B0
    bmi GN4
    cmp #10
    bcc HN1
    sbc #$7                         ; "A" ($C1) less $B0 and 7 is 10
    bmi GN4
    cmp #16
    bcs GN4
HN1:
    ldx #4
HN2:
    jsr GN5                         ; CNUM * 16
    dex
    bne HN2
    ora CNUM
    sta CNUM
    jmp HN0

;; PR#: sends output to the slot the scanner left in CNUM (0-7), through the Monitor's OUTPORT ($FE95).
;;
;; While DOS carries out a command, CSW and KSW hold the real output and input routines (SVREGS put them
;; back), so the Monitor changes the device DOS passes characters on to. When DOS leaves, MVCSW saves the new
;; routine and puts DOS's own hooks back in front of it.
EPR:
    lda CNUM
    jmp OUTPRT

;; IN#: takes input from the slot the scanner left in CNUM (0-7), through the Monitor's INPORT ($FE8B).
;;
;; As with PR#, the Monitor changes the routine that DOS's input hook passes on to.
EIN:
    lda CNUM
    jmp INPRT

;; MON: turns on the echo of commands (C), disk input (I) or disk output (O) given in IMBITS.
;; In:    IMBITS = MC ($40), MI ($20) and MO ($10) for the C, I and O given
EMON:
    lda a:MONMOD
    ora a:IMBITS
    sta a:MONMOD
    rts

;; NOMON: turns off the echoes given in IMBITS.
;;
;; With C, it first prints a carriage return: the command's own line was echoed while MON C was on, but its
;; return is echoed only on the way out (CERTN), which no longer happens once C is off.
;; In:    IMBITS = MC ($40), MI ($20) and MO ($10) for the C, I and O given
ENOMON:
    bit a:IMBITS                    ; V = bit 6, C
    bvc ENM1
    jsr PRCRIF
ENM1:
    lda #$70
    eor a:IMBITS                    ; the bits not given...
    and a:MONMOD                    ; ...are the ones kept
    sta a:MONMOD
    rts

;; MAXFILES: closes every file, the EXEC file too, and rebuilds the chain with CNUM (1-16) buffers.
;;
;; BLDFTB also moves BASIC's HIMEM to just below the new buffers; under Integer BASIC, whose program sits just
;; below HIMEM, that leaves no program.
EMAXF:
    lda #0
    sta a:ESTATE                    ; no EXEC, so that CLALL closes its file as well
    lda CNUM
    pha
    jsr CLALL
    pla
    sta a:CNFTBS
    jmp BLDFTB

;; DELETE: has the file manager delete the file named in FNAME1, then frees the buffer OPEN lent it.
;;
;; Like LOCK, UNLOCK, VERIFY and RENAME, DELETE goes through OPEN, which claims a buffer for the file manager
;; to work in. The file manager is not called to close it; the buffer is simply marked free again.
EDEL:
    lda #CRQDEL
    jsr OPEN
    jsr FILSRC                      ; find the buffer holding the name
    ldy #0
    tya
    sta (ZPGWRK),y                  ; and free it
    rts

;; LOCK: has the file manager lock the file named in FNAME1, then closes it.
ELOCK:
    lda #CRQLCK
    bne ELGO

;; UNLOCK: has the file manager unlock the file named in FNAME1, then closes it.
;;
;; ELGO, shared with LOCK and VERIFY, makes the call through OPEN with the opcode in A and then closes the
;; file, giving the buffer back.
EUNLK:
    lda #CRQUNL
ELGO:
    jsr OPEN
    jmp ECLOSE

;; VERIFY: has the file manager read every sector of the file named in FNAME1, then closes it.
;;
;; SAVE and BSAVE end here too (VPATCH), to check what they wrote; not in DOS 3.2, which has no VPATCH.
EVAR:
    lda #CRQVAR
    bne ELGO

;; RENAME: has the file manager rename the file named in FNAME1 to the name in FNAME2, then closes it.
;;
;; The new name's address goes in parameter bytes 2-3, which OPEN would otherwise fill with the record length,
;; so this enters at EO3, after that step.
EREN:
    lda FN2ADR
    sta a:CCBFN2
    lda FN2ADR+1
    sta a:CCBFN2+1
    lda #CRQRNM
    sta a:TEMP1A
    jsr EO3
    jmp ECLOSE

;; APPEND: opens a text file and reads it to its end, so that the next WRITE adds to it.
;;
;; A text file ends at its first zero byte, and DOSGO also hands back a zero when the file manager reports the
;; end of the data. BUMPER, a patch in the boot loader's page (BootLoader.asm), then steps the record number
;; on when the end flag EOFFLAG is set and finishes the call. DOS 3.2 ends instead with the file manager's
;; POSITION call that the READ and WRITE commands make (RWP3, MiscCommands.asm), with the parameter list as the
;; reads left it, so the record number is not corrected.
EAPND:
    jsr EOPEN
AP1:
    jsr RBYTE
    bne AP1
.if DOS32
    jmp RWP3
.else
    jmp BUMPER
.endif

;; OPEN: opens the file named in FNAME1 as a text file, creating it if it is missing.
;;
;; Zero, the text type, goes in the file type, and SV1 opens the file and checks that its type matches,
;; giving FILE TYPE MISMATCH if not. The L keyword gives the record length, 1 by default.
EOPEN:
    lda #0
    jmp SV1

;; Opens the file named in FNAME1 through the file manager's OPEN call.
;;
;; Whether a missing file is created depends on the command: the file manager checks CREFLG in the command's
;; CMDSTB entry (CommandTables.asm).
EOPN1:
    lda #CRQOPN

;; Makes file manager call A for the file named in FNAME1 in a free DOS buffer: the common code of the
;; handlers that work on a named file, and of CATALOG and INIT.
;;
;; It closes the file first if it is open, claims a free buffer by copying the name into it, fills in the
;; parameter list (record length, then volume, drive, slot and name address in OPNSUP) and calls the file
;; manager. The buffer stays claimed; CLOSE gives it back. A command without a file name has a 0 for the
;; first character of FNAME1, so the buffer is lent to the call without being claimed.
;; In:    A = file manager opcode (CRQOPN, CRQDEL, ...); FNAME1, CV, CD, CS and CL as the scanner left them
;; Out:   ZPGWRK = the buffer; CFTABA = the same
;; Errors: NO BUFFERS AVAILABLE when every buffer is in use; any file manager error, through DOSGO
;; Entry: EO3 = with the opcode already in TEMP1A and parameter bytes 2-3 already set (RENAME)
OPEN:
    sta a:TEMP1A
    lda a:CL
    bne EO1
    lda a:CL+1
    bne EO1
    lda #1                          ; no L given: records of one byte
    sta a:CL
EO1:
    lda a:CL
    sta a:CCBRLN
    lda a:CL+1
    sta a:CCBRLN+1
EO3:
    jsr ECLOSE                      ; also leaves CNUM = a free buffer, from FILSRC
EO4:
    lda CNUM+1
    bne EO5
    jmp ENFA
EO5:
    sta ZPGWRK+1
    lda CNUM
    sta ZPGWRK
EO6:
    jsr MVFN1                       ; the name claims the buffer
    jsr MVBUFP                      ; its three work areas go in the parameter list
    jsr OPNSUP
    lda a:TEMP1A
    sta a:CCBREQ
    jmp DOSGO

;; CLOSE: closes the file named in FNAME1 or, with no name, every file except the EXEC file.
;;
;; The search starts over after each close, so it closes every buffer that holds the name. When none is left,
;; FILSRC has also left the address of a free buffer, if any, in CNUM, which OPEN relies on.
;; Out:   CNUM = a free buffer (high byte 0 if none), when a name was given
ECLOSE:
    lda a:FNAME1
    cmp #$A0
    beq CLALL
    jsr FILSRC
    bcs CL2
    jsr CLOSE
    jmp ECLOSE

;; Closes the file whose buffer ZPGWRK points at and frees the buffer.
;;
;; If the buffer is the EXEC file's, EXEC stops. The name is cleared before the call, so the buffer is free
;; even if the file manager fails.
;; In:    ZPGWRK = the buffer
CLOSE:
    jsr TSTEXC                      ; Z set if this is EXEC's buffer
    bne CLX
    lda #0
    sta a:ESTATE
CLX:
    ldy #0
    tya
    sta (ZPGWRK),y
    jsr MVBUFP
    lda #CRQCLS
    sta a:CCBREQ
    jmp DOSGO

;; Closes every open file except the EXEC file, so that a program EXEC runs can use LOAD, RUN and the rest.
;;
;; After each close it starts again from the first buffer.
CLALL:
    jsr TSINIT
    bne CL1
CL0:
    jsr TSNXT
    beq CL2
CL1:
    jsr TSTEXC
    beq CL0                         ; leave the EXEC file open
    jsr TSTOPN
    beq CL0                         ; a free buffer
    jsr CLOSE
    jmp CLALL
CL2:
    rts
