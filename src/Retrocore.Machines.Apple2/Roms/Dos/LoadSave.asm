;; DOS 3.3 AND 3.2 COMMAND HANDLERS: LOAD, SAVE AND RUN (XLODSAV)
;;
;; The handlers that move programs between memory and disk, $A331-$A50D where DOS runs: BSAVE, BLOAD and BRUN
;; for binary files, and SAVE, LOAD, RUN and CHAIN for BASIC programs, with the entries DOS puts in BASIC's
;; RUN vector. CMDETB (DosInit.asm) lists them; OpenClose.asm has the OPEN and CLOSE code they share.
;;
;; Every file here holds a two-byte length, low byte first, then that many bytes of memory; a binary file has
;; its load address before the length. Each handler opens the file with the file type it expects and checks
;; it (SV1 or LD1), writes the two-byte values a byte at a time (file manager WRITE, subcode CRMNBT) or
;; reads them as a two-byte range (READ, subcode CRMNBL), then moves the block in one call and closes the file.
;;
;; Which BASIC is active decides where a program lives. ASIBSW is 0 for Integer BASIC, $40 for Applesoft at
;; $D000 (in ROM or a language card) and $80 for Applesoft loaded into lower RAM from the System Master's
;; APPLESOFT file. An Integer BASIC program sits just below HIMEM, from IBSOP ($CA) to IBHMEM ($4C), and grows
;; down towards LOMEM, IBLMEM ($4A). An Applesoft program grows up from ASSOP ($67, normally $0801) to ASEOP
;; ($AF), where its variables, ASEOP2 ($69), begin, below HIMEM, ASHM1 ($73). The BASIC entry points DOS uses
;; (RUN, CHAIN, ASEQ) are copied into DosInit.asm's vector from one of three images, one per BASIC. A program
;; of the other BASIC's type makes DOS switch BASICs first (LD1, then EAS or EINT in MiscCommands.asm).

;; BSAVE: writes CL bytes of memory from CA to a binary file named in FNAME1: the address, the length, then
;; the bytes; then verifies the file (DOS 3.2 only closes it).
;;
;; Both A and L must be given; otherwise CNF rejects the line as it does a command it does not know.
EBSV:
    lda #ADR+L
    and a:INOPTS
    cmp #ADR+L
    beq EBSV1
    jmp CNF
EBSV1:
    lda #4                          ; binary
    jsr SV1
    lda a:CA+1
    ldy a:CA
    jsr SV2
    lda a:CL+1
    ldy a:CL
    jsr SV2
    lda a:CA+1
    ldy a:CA
    jmp SV3

;; BLOAD: reads a binary file named in FNAME1 into memory at the address saved in it, or at CA when A is
;; given.
;;
;; It opens the file once to check that it is binary, then again through SV1.
;; Errors: FILE TYPE MISMATCH if the file is not binary
EBLD:
    jsr EOPN1
EBLD2:
    lda #$7F                        ; ignore the lock bit
    and a:CCBFUC
    cmp #4
    beq EBLD3
    jmp ETYP
EBLD3:
    lda #4
    jsr SV1
    jsr LD2                         ; the address saved in the file
    tax
    lda a:INOPTS
    and #ADR
    bne EBLD1
    stx a:CA
    sty a:CA+1
EBLD1:
    jsr LD2                         ; the length, left as the length to read
    ldx a:CA
    ldy a:CA+1
    jmp LD3

;; BRUN: BLOADs the file, then jumps to the address it was loaded at.
;;
;; MVCSW puts DOS's input and output hooks back, as DOS does whenever it leaves. The program is entered with a
;; JMP, so the return address on the stack is CMDGO's: a program that ends with an RTS finishes the command as
;; if BRUN itself had returned.
EBRUN:
    jsr EBLD
    jsr MVCSW
    jmp (CA)

;; SAVE: writes the BASIC program in memory to a file named in FNAME1: its length, then the program; then
;; verifies the file (DOS 3.2 only closes it).
;;
;; For Applesoft the file type is 2 and the program is ASSOP up to ASEOP. A program marked run-only (bit 7 of
;; $D6, ASRNX) is refused with PROGRAM TOO LARGE.
;; For Integer BASIC the type is 1 and the program is IBSOP up to HIMEM. INIT ends here too, to save the
;; greeting program on the disk it has just formatted.
;; Errors: PROGRAM TOO LARGE for a run-only Applesoft program; FILE TYPE MISMATCH if the file exists as
;;         another type
ESAVE:
    lda a:ASIBSW
    beq EIBSV
    lda ASRNX
    bpl EASAV
    jmp MFERR
EASAV:
    lda #2                          ; Applesoft
    jsr SV1
    sec
    lda ASEOP
    sbc ASSOP
    tay
    lda ASEOP+1
    sbc ASSOP+1
    jsr SV2
    lda ASSOP+1
    ldy ASSOP
    jmp SV3
EIBSV:
    lda #1                          ; Integer BASIC
    jsr SV1
    sec
    lda IBHMEM
    sbc IBSOP
    tay
    lda IBHMEM+1
    sbc IBSOP+1
    jsr SV2
    lda IBSOP+1
    ldy IBSOP
    jmp SV3

;; Opens the file named in FNAME1 as file type A and checks that its type is A.
;;
;; A new file is created with type A, if the command allows creating one; an existing file must already
;; have it, the lock bit aside.
;; In:    A = file type: 0 text, 1 Integer BASIC, 2 Applesoft, 4 binary
;; Out:   ZPGWRK = the file's buffer
;; Errors: FILE TYPE MISMATCH, after closing the file
SV1:
SV1A:
    sta a:CCBFUC
    pha
    jsr EOPN1
    pla
    jmp TSTFUC

;; Writes a two-byte value to the open file, low byte first, and leaves it in CCBBLN, the length of the
;; range to write next.
;;
;; CCBBLN's high byte is parameter byte 7, the file type, no longer needed once the file is open; the
;; second write reads the high byte back from there.
;; In:    Y = low byte, A = high byte; the file open, its buffer in the parameter list
;; Out:   CCBREQ = CRQWR, ready for SV3
SV2:
    sty a:CCBBLN
    sty a:CCBDAT
    sta a:CCBBLN+1
    lda #CRQWR
    sta a:CCBREQ
    lda #CRMNBT
    sta a:CCBRQM
    jsr DOSGO
    lda a:CCBBLN+1
    sta a:CCBDAT
    jmp DOSGO

;; Writes the range of memory starting at A,Y to the open file, closes it and verifies it.
;;
;; The length is the one SV2 left in CCBBLN. VPATCH, in the boot loader's page, makes the call, then closes
;; the file and ends in VERIFY (EVAR). DOS 3.2 has no VPATCH: it stores the request and goes on into GODOS,
;; which makes the call and closes the file, without verifying it.
;; In:    Y = low byte, A = high byte of the address
SV3:
    sty a:CCBBBA
    sta a:CCBBBA+1
    lda #CRMNBL
.if DOS32
    sta a:CCBRQM
.else
    jmp VPATCH
.endif

;; Makes the file manager call already set up in the parameter list, then closes the file.
GODOS:
    jsr DOSGO
    jmp ECLOSE

;; Reports FILE TYPE MISMATCH for LOAD, RUN or CHAIN of a file that is not a BASIC program.
NBPER:
    jmp ERNU1

;; LOAD: closes every file except the EXEC file and reads the BASIC program named in FNAME1 into memory.
;;
;; A file of the other BASIC's type makes DOS switch BASICs and carry out the command again (LD1). Applesoft
;; programs are loaded at ASSOP and must end below HIMEM's page. Integer BASIC programs are loaded to end at
;; HIMEM and must start above LOMEM's page. Both checks compare high bytes only, so they can refuse a program
;; that would fit with less than a page to spare.
;;
;; An Applesoft load ends by jumping to ASEQ, Applesoft's own entry for fixing up a program just loaded, and
;; does not come back here. An Integer BASIC load returns.
;; Entry: ELOAD0 = without closing the other files (CHAIN)
;; Errors: FILE TYPE MISMATCH if the file is not a BASIC program; PROGRAM TOO LARGE if it does not fit
ELOAD:
    jsr CLALL
ELOAD0:
    jsr EOPN1
ELD1:
    lda #$23                        ; keep the type bits 1 (Integer), 2 (Applesoft) and $20
    and a:CCBFUC
    beq NBPER
ELD2:
    sta a:CCBFUC
    lda a:ASIBSW
    beq EIBL
; Applesoft: the program goes at ASSOP and ends at ASSOP plus its length.
    lda #2
    jsr LD1
    jsr LD2                         ; the length
    clc
    adc ASSOP
    tax
    tya
    adc ASSOP+1
    cmp ASHM1+1
    bcs MFULL
EASL1:
    sta ASEOP+1                     ; the program's end, where the variables start
    sta ASEOP2+1
    stx ASEOP
    stx ASEOP2
    ldx ASSOP
    ldy ASSOP+1
    jsr LD3
    jsr MVCSW
    jmp (ASEQ)
; Integer BASIC: the program ends at HIMEM and starts its length below it.
EIBL:
    lda #1
    jsr LD1
    jsr LD2
    sec
    lda IBHMEM
    sbc a:SVBL
    tax
    lda IBHMEM+1
    sbc a:SVBL+1
    bcc MFULL
    tay
    cpy IBLMEM+1
    bcc MFULL
    beq MFULL
    sty IBSOP+1
    stx IBSOP

;; Reads the range of memory starting at X,Y from the open file, then closes it.
;;
;; The length and the read-a-range request are the ones LD2 left in the parameter list.
;; In:    X = low byte, Y = high byte of the address
LD3:
    stx a:CCBBBA
    sty a:CCBBBA+1
    jmp GODOS

;; Reads the next two bytes of the open file into SVBL and leaves them in CCBBLN, as the length of the range
;; to read next.
;;
;; The value is an address for a binary file's first two bytes, a length otherwise; it goes in CCBBLN either
;; way, and BLOAD's second call replaces the address with the length.
;; Out:   A = low byte, Y = high byte; CCBREQ = CRQRD and CCBRQM = CRMNBL, ready for LD3
LD2:
    lda SVBLA
    sta a:CCBBBA
    lda SVBLA+1
    sta a:CCBBBA+1
    lda #0
    sta a:CCBBLN+1
    lda #2
    sta a:CCBBLN
    lda #CRQRD
    sta a:CCBREQ
    lda #CRMNBL
    sta a:CCBRQM
    jsr DOSGO
    lda a:SVBL+1
    sta a:CCBBLN+1
    tay
    lda a:SVBL
    sta a:CCBBLN
    rts

;; Closes the file and reports PROGRAM TOO LARGE.
MFULL:
    jsr ECLOSE
    jmp MFERR

;; Returns if the open file is a program for the active BASIC; otherwise switches to the other BASIC and
;; has the command carried out again.
;;
;; The command goes in SVCMD. Once the new BASIC has started and asks for its first input, DOS's input hook
;; finishes starting DOS (INITC in DosInit.asm), sees SVCMD and runs the command again. For Applesoft the file
;; name is copied to FNAME2 as well: if Applesoft has to be loaded into RAM, loading the APPLESOFT file
;; replaces FNAME1, and INITC copies the name back.
;; In:    A = the type of the active BASIC: 1 Integer BASIC, 2 Applesoft; CCBFUC = the file's type
LD1:
    cmp a:CCBFUC
    beq LD1C
    ldx a:CMDNO
    stx a:SVCMD
    lsr a
    beq LD1A                        ; Integer BASIC is active: the file wants Applesoft
    jmp EINT
LD1A:
    ldx #29
LD1B:
    lda a:FNAME1,x
    sta a:FNAME2,x
    dex
    bpl LD1B
    jmp EAS
LD1C:
    rts

;; RUN: LOADs the program named in FNAME1 and runs it in the active BASIC.
;;
;; Under Applesoft the load does not come back (it ends in ASEQ), so RSTATE is set first: when Applesoft
;; next prints, DOS's output hook sees RSTATE and carries on at ERUN1 (COS7 in DosHook.asm).
;; Entry: ERUN1 = after the load, where COS7 picks up an Applesoft RUN
ERUN:
    lda a:ASIBSW
    beq ERUN0
    sta a:RSTATE
ERUN0:
    jsr ELOAD
ERUN1:
    jsr PRCRIF
    jsr MVCSW
    jmp (RUN)

;; Integer BASIC's RUN entry as DOS sets it: clears the variables, then runs the program from its CHAIN
;; entry, which keeps them.
;;
;; Setting IBSOV ($CC), Integer BASIC's variable pointer, back to LOMEM leaves no variables.
IBRUN:
    lda IBLMEM
    sta IBSOV
    lda IBLMEM+1
    sta IBSOV+1
    jmp (CHAIN)

;; CHAIN: loads the program named in FNAME1 without closing open files, and runs it keeping the variables.
;;
;; CHAIN is an Integer BASIC command: the CHAIN vector goes to Integer BASIC's own entry ($E836), which runs a
;; program without clearing its variables. In Applesoft's vector images CHAIN is the same as RUN.
ECHAIN:
    jsr ELOAD0
    jsr PRCRIF
    jsr MVCSW
    jmp (CHAIN)

;; Applesoft's RUN (and CHAIN) entry as DOS sets it, for Applesoft in ROM.
;;
;; It clears the program's variables ($D665), sets PROMPT and ASONERR ($D8) to the A that call leaves, 0, so
;; that ONERR is off and TSTRUN sees a running program, and starts the program running ($D7D2).
ASRUN1:
    jsr $D665
    sta PROMPT
    sta ASONERR
    jmp $D7D2

;; Applesoft's RUN (and CHAIN) entry as DOS sets it, for Applesoft in RAM: as ASRUN1, at RAM Applesoft's
;; addresses.
ASRUN2:
    jsr $E65
    sta PROMPT
    sta ASONERR
    jmp $FD4
