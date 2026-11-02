;; DOS 3.3 AND 3.2: THE MASTER'S RELOCATOR (RELOCTR)
;;
;; Only a System Master has this: the MASTER = 1 build puts it at $1B00-$1CFF, with DOS after it at
;; $1D00-$3FFF, $8000 below where DOS runs on a 48K machine. BOOT 2 loads all of that and jumps to DOSREL
;; here. The relocator finds how much memory the machine has, adjusts every address inside DOS for the place
;; DOS will run, the top of memory, and copies DOS there, so one master boots whatever the memory size.
;; Disks that INIT writes don't need it: they get the copy of DOS already running, which loads straight to its
;; place.
;;
;; The boot chain, with the master's addresses:
;;
;; - BOOT 0, the Disk II ROM, reads track 0 sector 0 to $0800 and runs it (docs/DiskII.md, Boot16.asm).
;;   DOS 3.2's ROM reads it to $0300 (Boot13.asm).
;; - BOOT 1, that sector (the TRK0LDR page of BootLoader.asm), reads the rest of track 0's first ten sectors
;;   to $3600-$3FFF and jumps to $3700. DOS 3.2's (BootLoader32.asm) reads all ten.
;; - BOOT 2 (DOSLODR) reads the rest of DOS, $1B00-$35FF, from tracks 0 to 2 and ends at DOSREL.
;; - This code moves DOS up and starts it at DBINIT, its cold start.
;;
;; DOS needs two kinds of fixing. Tables of addresses are listed in ADRTAB; ranges of code, whose three-byte
;; instructions may hold addresses, are listed in CDETAB. Only addresses inside DOS change. The relocator is
;; not itself moved, so its own addresses are those of the master image.

;; The first bytes of the master image: a jump to DOS's cold start where the image holds it. DOS's ASTART
;; names this address until the relocator changes it.
BEGIN:
    jmp DBINIT

;; Moves DOS to the top of memory and starts it there. BOOT 2 jumps here through DI3.
;;
;; First it finds the highest page of RAM: from $BF00 down, it tests each page's first byte by exclusive-oring
;; it with 0 to 255 in turn, comparing each result with what the same arithmetic gives on a copy of the byte.
;; Memory passes all 256; the byte ends where it began, since the 256 values exclusive-ored together give 0.
;; Where nothing answers, or a ROM does, a comparison fails and the page below is tried.
;; It doesn't return: it ends at DOS's cold start.
DOSREL:
DR0:

;; The relocator's copy of the byte under test while it looks for the top of RAM.
;;
;; <DOSREL> exclusive-ors the byte at the top of each page with each value from 0 to 255 in turn and does the
;; same to this copy; the page is RAM only if the two always agree. It shares $26 with RWTS's temporaries.
;; See: <DOSREL>, <ZPGWRK>
LOC1 = $26
    lda #$BF
    sta ZPGWRK+1
    ldx #0                          ; X stays 0: (ZPGWRK,x) is the byte at ZPGWRK
    stx ZPGWRK
DR0A:
    ldy #0
DR1B:
    lda (ZPGWRK,x)
    sta LOC1
DR1:
    tya
    eor LOC1
    sta LOC1
    tya
    eor (ZPGWRK,x)
    sta (ZPGWRK,x)
    cmp LOC1
    bne DR1A                        ; it didn't hold the value: not RAM
    iny
    bne DR1
    beq DR2                         ; always: all 256 passed, Y = 0
DR1A:
    dec ZPGWRK+1
    bne DR0A

; Some memory answers at two addresses 8K apart, so the page found may be the same RAM as the page 8K below it
; (bit 5 of the page number clear). The same test again, now writing below and reading at the page found: if
; every write shows up there, the two are one, and the top of memory is the lower page. Y is 0.
DR2:
    lda ZPGWRK+1
    and #$DF
    sta ZPGFCB+1
    stx ZPGFCB
    lda (ZPGFCB,x)
    pha                             ; the lower page's byte, to put back
    sta LOC1
DR2A:
    tya
    eor LOC1
    sta LOC1
    tya
    eor (ZPGWRK,x)
    sta (ZPGFCB,x)
    cmp LOC1
    bne DR2B                        ; separate memory
    iny
    bne DR2A
    ldy ZPGFCB+1                    ; one and the same: the byte is back as it was, by the same arithmetic
    pla
    jmp DR2C
DR2B:
    pla
    sta (ZPGFCB,x)
    ldy ZPGWRK+1

; Y is the top page of RAM. DOS ends just above it (NEPAGE), starts DOSLNG pages lower (NSPAGE), and moves by
; DELTA pages. With RAM to $3FFF DELTA is 0: DOS is already in place and starts where it is.
DR2C:
    iny
    sty a:NEPAGE
    sec
    tya
    sbc a:DOSLNG
    sta a:NSPAGE
    sec
    sbc a:RSPAGE
    beq BEGIN
    sta a:DELTA

; Two fixes before the general ones. ASTART, which INIT uses as the first page of DOS to write to a disk,
; names BEGIN, the relocator; it is pointed at START instead. And DI3, the JMP at the end of BOOT 2, is
; pointed at DBINIT, so a disk INIT writes from the moved DOS boots straight into DOS. Both are in ranges the
; next two passes adjust.
    lda a:RSPAGE
    sta a:ASTART+1
    lda #>(DBINIT)
    sta a:DI3+2
    lda #<(DBINIT)
    sta a:DI3+1

; Adjusts the address tables. Each ADRTAB entry is a range of two-byte addresses, start to end (the end not
; included); DELTA is added to each one's high byte. Y and ZPGWRK + 1 are the pointer, ZPGWRK staying 0.
    ldx #0
    stx ZPGWRK
DR3:
    lda a:ADRTAB+1,x
    tay
    lda a:ADRTAB+2,x
    sta ZPGWRK+1
    jmp DR5                         ; step to the first address's high byte
DR4:
    clc
    lda (ZPGWRK),y
    adc a:DELTA
    sta (ZPGWRK),y
    iny
    bne DR5
    inc ZPGWRK+1
DR5:
    iny
    bne DR6
    inc ZPGWRK+1
DR6:
    lda ZPGWRK+1
    cmp a:ADRTAB+4,x
    bcc DR4
    tya
    cmp a:ADRTAB+3,x
    bcc DR4
    txa
    clc
    adc #4
    tax
    cpx a:ADRTAB
    bcc DR3

; Adjusts the code. Each CDETAB entry is a range of instructions, walked one at a time with the Monitor's
; INSDS2, which gives each opcode's length. In a three-byte instruction whose operand's high byte is a page of
; DOS (RSPAGE to REPAGE), DELTA is added to it. The ranges must hold only code, or the walk falls out of step.
    ldx #0
DR7:
    stx a:TEMP1                     ; INSDS2 changes X
    lda a:CDETAB+1,x
    sta ZPGWRK
    lda a:CDETAB+2,x
    sta ZPGWRK+1
DR8:
    ldx #0
    lda (ZPGWRK,x)
    jsr INSDS2
    ldy LENGTH
    cpy #2
    bne DR9                         ; not three bytes long
    lda (ZPGWRK),y
    cmp a:RSPAGE
    bcc DR9
    cmp a:REPAGE
    bcs DR9
    adc a:DELTA                     ; the carry is clear: the BCS wasn't taken
    sta (ZPGWRK),y
DR9:
    sec                             ; past the instruction: LENGTH + 1 bytes
    lda LENGTH
    adc ZPGWRK
    sta ZPGWRK
    lda #0
    adc ZPGWRK+1
    sta ZPGWRK+1
    ldx a:TEMP1
    cmp a:CDETAB+4,x
    bcc DR8
    lda ZPGWRK
    cmp a:CDETAB+3,x
    bcc DR8
    txa
    clc
    adc #4
    tax
    cpx a:CDETAB
    bcc DR7

; Copies DOS, now fixed, to its new place, a page at a time from the top page down: DPGCNT pages, from the
; page holding ENDOFDOS - $80 (DOS's last) to the page below NEPAGE. The new place is higher, so working down
; never overwrites a page before it is copied.
    lda #>(ENDOFDOS-$80)
    sta ZPGWRK+1
    ldy a:NEPAGE
    dey
    sty ZPGFCB+1
    lda #0
    sta ZPGWRK
    sta ZPGFCB
    tay
DR10:
    lda (ZPGWRK),y
    sta (ZPGFCB),y
    iny
    bne DR10
    dec a:DPGCNT
    beq DR11
    dec ZPGWRK+1
    dec ZPGFCB+1
    bne DR10

; Starts DOS. DBVECT + 3 is a JMP DBINIT in the old copy of DOS, still in memory; its address was adjusted
; with the rest, so it goes to the cold start in the new copy.
DR11:
    jmp DBVECT+3

;; The address tables to adjust: a count of bytes used (four per entry), then the entries, each the start and
;; the end (not included) of a run of two-byte addresses. Only the high bytes change. The tables of DosInit.asm
;; between EAT1 and SC1 hold addresses outside DOS too, so only the entries that point into DOS are listed.
ADRTAB:
    .byte 9*4
    .word SAT1                      ; DosInit's table of DOS addresses, START to the command handlers
    .word EAT1
    .word RUN                       ; the RUN entry of the active BASIC's vector
    .word RUN+2
    .word IBVT+2                    ; RUN in Integer BASIC's
    .word IBVT+4
    .word AS1VT                     ; CHAIN and RUN in ROM Applesoft's
    .word AS1VT+4
    .word AS2VT                     ; CHAIN and RUN in RAM Applesoft's
    .word AS2VT+4
    .word AS2VT+6                   ; its cold start, DBINIT
    .word AS2VT+8
    .word SAT2                      ; the file manager's tables
    .word EAT2
    .word BAIOB                     ; BOOT 2's pointers to the IOB and the boot page
    .word ADOSLD+2
    .word IBDCTP                    ; the IOB's pointer to the DCT
    .word IBDCTP+2
    .byte 0, 0, 0, 0                ; room for three more entries
    .byte 0, 0, 0, 0
    .byte 0, 0, 0, 0

;; The code ranges to adjust: a count of bytes used (four per entry), then the entries, each the start and end
;; of a run of instructions. DOS 3.2's RWTS is laid out differently, and it has no patch area: its table has
;; six entries and room for one more.
CDETAB:
.if DOS32
    .byte 6*4
    .word SC1                       ; the command interpreter, from DBINIT
    .word EC1
    .word SC2                       ; the file manager
    .word EC2
    .word SC3                       ; BOOT 2 and its helpers
    .word EC3
    .word SC4                       ; an empty range, just before the boot page
    .word EC4
    .word ASC1                      ; RWTS's low-level routines
    .word AEC1
    .word ASC2                      ; RWTS, the formatter and the patches at the top of DOS
    .word AEC2
    .byte 0, 0, 0, 0                ; room for one more entry
.else
.if DOS33B
    .byte 8*4
.else
    .byte 7*4                       ; no patch area in 1980
.endif
    .word SC1                       ; the command interpreter, from DBINIT
    .word EC1
    .word SC2                       ; the file manager
    .word EC2
    .word SC3                       ; the patches and BOOT 2 in the boot loader's pages
    .word EC3
    .word SWADR1                    ; RWTS, in pieces between its tables
    .word EWADR1
    .word ASC1
    .word AEC1
.if DOS33B
    .word PSC1                      ; the 1983 patch area after MSWAIT
    .word PEC1
.endif
    .word ASC2
    .word AEC2
    .word SDP1                      ; the patches at the top of DOS
    .word EDP1
.endif

;; DOS's first page in the master image.
RSPAGE:
    .byte >(START)
;; The page just after DOS in the master image.
REPAGE:
    .byte >(ENDOFDOS)
;; DOS's first page once moved.
NSPAGE:
    LEFTOVER $00, $1D, $00
;; The page just after DOS once moved.
NEPAGE:
    LEFTOVER $00, $40, $00
;; DOS's length in pages.
DOSLNG:
    .byte >(ENDOFDOS-START)
;; How many pages DOS moves up.
DELTA:
    .byte 0
;; Pages left to copy.
DPGCNT:
    .byte >(ENDOFDOS-START)
.if DOS32 = 0 && YEAR = 1983
    ; leftover: the rest of the page holds whatever was in memory when the master was written
    .byte $FC, $FD, $FD, $FD, $FC, $FD, $FC, $FC, $FC, $FE, $FE, $FC, $FE, $FC, $FC, $FD
    .byte $FE, $FC, $FF, $FC, $FD, $FC, $FC, $FC, $FF, $FC, $FF, $FC, $FE, $FF, $FF, $FF
    .byte $FF, $FD, $FE, $FC, $FD, $FC, $FC, $FC, $FC, $FD, $FC, $FE, $FE, $FE, $FC, $FD
    .byte $FF, $FC, $FC, $FC, $FE, $FC, $FD, $FC, $FC, $FC, $FE, $FC, $FD, $FC, $FC, $FC
    .byte $FD, $FC, $FD, $FD, $FC, $FC, $FC, $FD, $FD, $FC, $FE, $FC, $FC, $FE, $FC, $FC
    .byte $FD, $FD, $FC, $FF, $FE, $FC, $FF, $FC, $FC, $FD, $FC, $FD, $FE, $FC, $FC, $FD
    .byte $FC, $FF, $FC, $FE, $FF, $FF, $FF, $FD, $FC, $FE, $FE, $FC, $FC, $FE, $FC, $FC
    .byte $FE, $FC, $FE, $FC, $FE, $FE, $FC, $FE, $FE, $FC, $FC, $FE, $FC, $FD, $FD
.else
    ; leftover: the 1980 master's rest of the page, which the DOS 3.2 master has too
    .byte $A5, $74, $86, $6F, $85, $70, $A0, $00, $84, $8B, $A5, $6D, $A6, $6E, $85, $9B
    .byte $86, $9C, $A9, $55, $A2, $00, $85, $5E, $86, $5F, $C5, $52, $F0, $05, $20, $1A
    .byte $1D, $F0, $F7, $A9, $07, $85, $8F, $A5, $69, $A6, $6A, $85, $5E, $86, $5F, $E4
    .byte $6C, $D0, $04, $C5, $6B, $F0, $05, $20, $10, $1D, $F0, $F3, $85, $94, $86, $95
    .byte $A9, $03, $85, $8F, $A5, $94, $A6, $95, $E4, $6E, $D0, $07, $C5, $6D, $D0, $03
    .byte $4C, $59, $1D, $85, $5E, $86, $00, $A0, $00, $B1, $5E, $AA, $C8, $B1, $5E, $08
    .byte $C8, $B1, $5E, $65, $94, $85, $94, $C8, $B1, $5E, $65, $95, $85, $95, $28, $10
    .byte $D3, $8A, $30, $D0, $A6, $1C, $A6, $1B, $A6, $1A, $80, $1A, $65, $5E, $85, $5E
    .byte $90, $02, $E6
.endif
    .assert <* = 0
