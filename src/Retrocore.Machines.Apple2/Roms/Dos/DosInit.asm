;; DOS 3.3 AND 3.2: COLD START AND INITIALISATION (DOSINIT)
;;
;; The first page of DOS, $9D00 where DOS runs. It opens with tables of addresses: those DOS keeps of its own
;; routines and buffers, the entry points of whichever BASIC is active, and the images to choose them from.
;; Then come DOS's entry points: DBINIT, the cold start, which BOOT 2 or the relocator reaches at the end of a
;; boot; DBRST, the warm start, which a reset or a CALL 976 reaches; and INITC, the rest of the setup, done
;; when BASIC first asks for a line. DBVECT is the page-3 jump table DOS installs at $3D0-$3FF.
;;
;; The relocator (Relocator.asm) adjusts the addresses here when a master moves DOS: the table from SAT1 to
;; EAT1, the entries of the BASIC vectors its ADRTAB lists, and the code from SC1 on. The boot chain and
;; docs/Dos.md say how DOS gets here.

; DOS starts on a page boundary.
.align 256

;; Addresses DOS keeps of its own routines and buffers, so code elsewhere, and programs, can find them
;; wherever DOS is. The relocator adjusts every word from SAT1 to EAT1.
;;
;; FTAB is the first file buffer's file-name field, 45 bytes below DOS: the file buffers are just below it.
START:
SAT1:
FTAB:
    .word *-45

;; DOS's input routine, which DOS puts in KSW.
CINA:
    .word CHRIN

;; DOS's output routine, which DOS puts in CSW.
COUTA:
    .word CHROUT

;; The file name buffer that commands fill.
FN1ADR:
    .word FNAME1

;; The second file name buffer, for RENAME's new name.
FN2ADR:
    .word FNAME2

;; The address of SVBL, a length LOAD keeps.
SVBLA:
    .word SVBL

;; DOS's first address, which INIT writes to the disk from. In the master image it names BEGIN, the relocator,
;; until the relocator points it at START.
ASTART:
    .word BEGIN

;; The file manager's parameter list.
CCBADR:
    .word CCB

;; The output routine for each state of DOS's output intercept, 0 to 6, each less one: CHROUT pushes the
;; address and returns to it, and RTS adds the one back.
OUTSVT:
    .word COS0-1
    .word COS1-1
    .word COS2-1
    .word COS3-1
    .word COS4-1
    .word COS5-1
    .word COS6-1

;; The routine for each command, in the order of the command names in CommandTables.asm, each less one for
;; the same RTS jump. A command's number, CMDNO, is its offset here: 0 for INIT, 6 for RUN.
CMDETB:
    .word EINIT-1
    .word ELOAD-1
    .word ESAVE-1
    .word ERUN-1
    .word ECHAIN-1
    .word EDEL-1
    .word ELOCK-1
    .word EUNLK-1
    .word ECLOSE-1
    .word EREAD-1
    .word EEXEC-1
    .word EWRITE-1
    .word EPOS-1
    .word EOPEN-1
    .word EAPND-1
    .word EREN-1
    .word ECAT-1
    .word EMON-1
    .word ENOMON-1
    .word EPR-1
    .word EIN-1
    .word EMAXF-1
    .word EAS-1
    .word EINT-1
    .word EBSV-1
    .word EBLD-1
    .word EBRUN-1
    .word EVAR-1

;; The entry points of the active BASIC, which DOS jumps through: CHAIN, RUN, BREAK (where DOS reports an
;; error), GO (cold start), CONT (warm start), and ASEQ (rebuild a loaded program's line links; Applesoft
;; only). DBINIT and INITC fill it from one of the three images below. Some entries are DOS's own routines, so
;; the relocator's ADRTAB lists them; the rest point into a BASIC and stay as they are.
EAT1:
IBASVT:
CHAIN:
    .word IBCHN
RUN:
    .word IBRUN
BREAK:
    .word IBBRK
GO:
    .word IBGO
CONT:
    .word IBCONT
ASEQ:
    LEFTOVER $00, $F2, $00
    LEFTOVER $00, $D4, $00

;; The vector for Integer BASIC. It is two bytes shorter than the others: Integer BASIC leaves ASEQ alone.
IBVT:
    .word IBCHN
    .word IBRUN
    .word IBBRK
    .word IBGO
    .word IBCONT
IBVTL = *-IBVT                      ;; its length in bytes

;; The vector for Applesoft in ROM.
AS1VT:
    .word ASRUN1
    .word ASRUN1
    .word ASBRK1
    .word IBGO
    .word ASCNTU1
    .word ASRSEQ1
AS1VTL = *-AS1VT                    ;; its length in bytes

;; The vector for Applesoft loaded into RAM. Its cold start is DOS's own.
AS2VT:
    .word ASRUN2
    .word ASRUN2
    .word ASBRK2
    .word DBINIT
    .word ASCNTU2
    .word ASRSEQ2
AS2VTL = *-AS2VT                    ;; its length in bytes

;; DBINIT, DOS's cold start ($9D84, CALL 40324 or 3D3G), where every boot ends. SC1 marks the start of the
;; relocator's first code range.
;;
;; It takes the slot and drive in the IOB (after a boot, those it booted from) as the defaults for commands,
;; and sees which BASIC is in ROM from the byte at $E000. ASIBSW records the BASIC: 0 for Integer BASIC, $40
;; for Applesoft in ROM ($80, Applesoft in RAM, is set later by INITC). It then hooks DOS into input and output
;; and cold starts BASIC. When BASIC first asks for a line, DOS's input routine finishes the job (INITC).
;; It doesn't return: it ends in BASIC.
SC1:
DBINIT:
    lda a:IBSLOT
    lsr a
    lsr a
    lsr a
    lsr a
    sta a:CS
    lda a:IBDRVN
    sta a:CD
    lda AITSTL
    eor #ITSTV
    bne IAS1                        ; not Integer BASIC: Applesoft
    sta a:ASIBSW                    ; A = 0
    ldx #IBVTL
IIB1:
    lda IBVT-1,x
    sta IBASVT-1,x
    dex
    bne IIB1
    jmp INITAA
IAS1:
    lda #$40
    sta a:ASIBSW
    ldx #AS1VTL
IAS1A:
    lda AS1VT-1,x
    sta IBASVT-1,x
    dex
    bne IAS1A
INITAA:
    sec                             ; carry set: a cold start
    bcs INITA

;; DOS's warm start ($9DBF, CALL 976 or 3D0G), where a reset goes once DOS has set the reset vector.
;;
;; It selects again the BASIC in ROM that ASIBSW records (SWTST switches the language card, or Apple's
;; firmware card, until $E000 holds that BASIC's first byte), hooks DOS back into input and output and warm
;; starts BASIC, keeping the program.
;; It doesn't return: it ends in BASIC.
;; Entry: INITA = with the carry set for a cold start, clear for a warm one
DBRST:
    lda a:ASIBSW
    bne INITA1
    lda #ITSTV                      ; Integer BASIC
    bne INITA2
INITA1:
    asl a
    bpl INITA3                      ; $80, Applesoft in RAM: no ROM to select
    lda #ATSTV
INITA2:
    jsr SWTST
INITA3:
    clc                             ; carry clear: a warm start
INITA:
    php
    jsr MVCSW
    lda #0
    sta a:MONMOD                    ; MON's echoes off
    sta a:OSTATE
    plp
    ror a                           ; the carry to bit 7: ISTATE = $80 after a cold start, else 0
    sta a:ISTATE
    bmi INITB
    jmp (CONT)
INITB:
    jmp (GO)

;; Finishes DOS's setup when BASIC first asks for a line after a cold start; DOS's input routine calls it
;; while ISTATE has bit 7 set.
;;
;; ISTATE $C0 means FP, finding no Applesoft in ROM, has run the program that loads it into RAM: DOS then uses
;; that Applesoft's vector and copies the second file name buffer over the first. Then, every time, it sets
;; MAXFILES to its default, builds the file buffers below HIMEM, keeps an EXEC file going, and clears the
;; input and output states.
;;
;; After a boot CMDNO is 0, INIT's number, as it was when the disk's copy of DOS was written. DOS then installs
;; its page-3 jump table, points the reset vector at DBRST, and runs the disk's greeting program, whose name
;; INIT left in FNAME1. Otherwise it carries out any command that was waiting (SVCMD).
;; In:    A = ISTATE
INITC:
    asl a
    bpl INITD                       ; $80: ROM BASIC
    sta a:ASIBSW                    ; $C0 becomes $80
    ldx #AS2VTL
IAS2A:
    lda AS2VT-1,x
    sta IBASVT-1,x
    dex
    bne IAS2A
    ldx #29
IAS2B:
    lda a:FNAME2,x
    sta a:FNAME1,x
    dex
    bpl IAS2B
INITD:
    lda a:DFNFTS
    sta a:CNFTBS
    jsr BLDFTB

; BLDFTB marked every buffer free by clearing the first byte of its file name. ESTATE, when an EXEC file is
; open, is the first character of that file's name: it goes back in the EXEC file's buffer.
    lda a:ESTATE
    beq INITZ
    pha
    jsr MVEFTA
    pla
    ldy #0
    sta (ZPGWRK),y
INITZ:
    jsr CLRSTS
    lda a:CMDNO
    bne INITF                       ; not just booted

; Just booted: copies DBVECT to $3D0-$3FF and makes a reset go to DBRST. The Autostart Monitor follows
; ZRSET only while PWCNST holds ZRSET's high byte exclusive-ored with $A5.
    ldx #IFBL
INITE:
    lda a:DBVECT,x
    sta $3D0,x
    dex
    bpl INITE
    lda a:DBVECT+2
    sta ZRSET+1
    eor #$A5
    sta PWCNST
    lda a:DBVECT+1
    sta ZRSET
    lda #6                          ; RUN
    bne INITF1
INITF:
    lda a:SVCMD
    beq INITG
INITF1:
    sta a:CMDNO
    jmp CMDGO1
INITG:
    rts

;; DBVECT, the image of DOS's page-3 jump table, which INITC copies to $3D0-$3FF; programs reach DOS through it
;; wherever DOS is in memory. Its entries, by address in page 3:
;;
;; $3D0 = DOS's warm start; $3D3 = its cold start; $3D6 = the file manager; $3D9 = RWTS, through DISKIO;
;; $3DC = loads the file manager's parameter list address into Y (low) and A (high); $3E3 = the same for
;; RWTS's IOB; $3EA = hooks DOS back into input and output (MVCSW).
;;
;; From $3EF on, the table fills the Monitor's vectors; there, what counts is the address in each JMP: $3F0 =
;; BRK (MONBRK), $3F2 = reset (INITC then points it at DBRST and sets $3F4), $3F5 = Applesoft's &, $3F8 =
;; the Monitor's Ctrl-Y, $3FB = NMI, $3FE = IRQ (a bare address). They are written as JMPs so the relocator,
;; which walks this as code, stays in step; the last word's low byte, $65, reads as a two-byte instruction.
IFB:
DBVECT:
    jmp DBRST
    jmp DBINIT
    jmp USERENT
    jmp DISKIO

;; Returns the address of the file manager's parameter list, the $3DC entry.
;; Out:   A = its high byte, Y = its low byte
CCBLDR:
    lda CCBADR+1
    ldy CCBADR
    rts

;; Returns the address of RWTS's IOB, the $3E3 entry.
;; Out:   A = its high byte, Y = its low byte
IOBLDR:
    lda a:AIOB+1
    ldy a:AIOB
    rts
    jmp MVCSW
    nop
    nop
    jmp MONBRK
    jmp MONRST
    jmp IORTS
    jmp MONRST
    jmp MONRST
    .word MONRST
IFBL = *-IFB-1                      ;; the table's length less one: the last index to copy
