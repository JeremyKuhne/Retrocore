;; DOS 3.3 RWTS: DELAYS, NIBBLE TABLES, PATCHES AND BUFFERS (MSWAITR)
;;
;; The page at $BA00 where DOS runs, and the two buffer pages after it. MSWAIT is the delay that times the head
;; and the motor, ONTABLE and OFFTABLE the head's step times, and NIBL and the DNIBL entries the translations
;; between six-bit values and nibbles that WRITE16 and READ16 use. NBUF1 and NBUF2 ($BB00-$BC55) hold a
;; sector's 342 six-bit values between the disk and the caller's buffer.
;;
;; DNIBL is indexed by the nibble itself, and only nibbles $96-$FF are valid, so its entries need only the last
;; $6A bytes of a page: the code and tables before them share the page. The space between holds three patches
;; added to DOS later: MOVEOF and FIXIT2, for the APPEND command, and OFF80, for the Apple IIe's 80-column
;; display. In this 1983 master FIXIT2 lives here; Apple's listing has a longer version in the boot loader's
;; page (see Dos33.asm). The timing rules for the tables and buffers are in RwtsEquates.asm and docs/DiskII.md
;; explains the nibbles.

; Three bytes of padding put MSWAIT at the start of a page, so that the branch in its timed loop never crosses a
; page boundary, which would add a cycle to every pass.
    LEFTOVER $00, $AA
    LEFTOVER $00, $A0
    LEFTOVER $00, $A0
;; Waits A times about 100 microseconds (256 times when A is 0), adding 1 to MONTIMEL/MONTIMEH for each.
;;
;; Each pass takes 101 cycles: the loop on X takes 84, and the count and the test the rest. RWTS counts the
;; motor's start-up time in MONTIMEL/MONTIMEH, so every wait during a seek counts toward it.
;; In:    A = the number of 100-microsecond waits (0 = 256)
;; Out:   A = 0, X = 0, carry set
;; Uses:  MONTIMEL, MONTIMEH
;; Keeps: Y
MSWAIT:
    ldx #$11
MSW1:
    dex
    bne MSW1                        ; 17 passes, 84 cycles
    inc MONTIMEL
    bne MSW2
    inc MONTIMEH
MSW2:
    sec
    sbc #$1
    bne MSWAIT
    rts
;; The end of the relocator's first range of code in RWTS, ASC1 to AEC1; the tables after it hold no addresses.
;;
;; ONTABLE: how long SEEK keeps the new phase on, together with the old one, in units of 100 microseconds,
;; indexed by the smaller of the half-tracks moved and those left to go (up to 11). The head starts and stops
;; slowly and moves fastest in between.
AEC1:
ONTABLE:
    .byte 1, $30, $28
    .byte $24, $20, $1E
    .byte $1D, $1C, $1C
    .byte $1C, $1C, $1C
;; How long SEEK waits after turning the old phase off, in units of 100 microseconds, indexed as ONTABLE.
OFFTABLE:
    .byte $70, $2C, $26
    .byte $22, $1F, $1E
    .byte $1D, $1C, $1C
    .byte $1C, $1C, $1C
;; The nibble that stands for each six-bit value, 0 to $3F: in order, the 64 bytes with the top bit set whose
;; bits 6-0 hold at least one pair of adjacent 1 bits and at most one pair of adjacent 0 bits. D5 and AA, which
;; mark the fields, fail the test, so data never contains them.
;;
;; WRITE16 reads it with `LDA NIBL,X`, counted at 4 cycles, so it must not cross a page boundary.
NIBL:
    .byte $96, $97, $9A
    .byte $9B, $9D, $9E
    .byte $9F, $A6, $A7
    .byte $AB, $AC, $AD
    .byte $AE, $AF, $B2
    .byte $B3, $B4, $B5
    .byte $B6, $B7, $B9
    .byte $BA, $BB, $BC
    .byte $BD, $BE, $BF
    .byte $CB, $CD, $CE
    .byte $CF, $D3, $D6
    .byte $D7, $D9, $DA
    .byte $DB, $DC, $DD
    .byte $DE, $DF, $E5
    .byte $E6, $E7, $E9
    .byte $EA, $EB, $EC
    .byte $ED, $EE, $EF
    .byte $F2, $F3, $F4
    .byte $F5, $F6, $F7
    .byte $F9, $FA, $FB
    .byte $FC, $FD, $FE
    .byte $FF
XP = >(*)                           ;; this page's high byte
;; The six-bit value of each nibble, indexed by the nibble: DNIBL + $96 to DNIBL + $FF, the end of this page.
;;
;; DNIBL is the page's start ($BA00 where DOS runs). Because the page starts there, `EOR DNIBL,Y` with a nibble
;; in Y never crosses a page and always takes 4 cycles. DNIBL + 0 to + $95 is the code and tables above.
DNIBL = 256*XP
.if YEAR = 1983
;; The start of the relocator's range for the patch code, PSC1 to PEC1.
;;
;; MOVEOF clears EOFFLAG unless the command running is APPEND (CMDNO = $1C, APPEND's place in the command
;; table times 2). DOSGO (DosGoer.asm) calls it after EOFFIX has dealt with an end-of-file error from the file
;; manager, so the flag EOFFIX may have set reaches BUMPER only when APPEND is running.
;; In:    CMDNO = the command
;; Uses:  X, EOFFLAG
;; Keeps: A, Y
PSC1:
MOVEOF:
    ldx CMDNO
    cpx #$1C                        ; APPEND?
    beq GOON
    ldx #$00
    stx EOFFLAG
GOON:
    rts
;; Turns off the Apple IIe's 80-column display and its alternate character set, then resets the text screen
;; through the Monitor's INIT.
;;
;; RCPATCH (DosPatches.asm) calls it at the end of booting. $04FB is a byte of slot 3's screen holes, which the
;; IIe's 80-column firmware uses; writing $C00C selects the 40-column display and writing $C00E the primary
;; character set. INIT ($FB2F) sets text mode and the full-screen window, and returns to OFF80's caller. It also
;; uses what INIT uses.
;; Uses:  A
OFF80:
    lda #$FF
    sta $4FB
    sta $C00C
    sta $C00E
    jmp $FB2F
;; The end of APPEND, reached by a jump from BUMPER (BootLoader.asm): updates two of the file's position bytes
;; and leaves the file manager through GOODIO.
;;
;; It copies the byte at CCBRLN, which shares its bytes with CCBRRN, the record number BUMPER may have just
;; advanced, into the low bytes of DCBCSB and DCBCRR. GOODIO (FileLocateSector.asm) reloads the stack pointer
;; from ENTSTK before its RTS; saving S there first means the RTS returns as one from APPEND's EAPND would. It
;; also uses what GOODIO uses.
;; Uses:  A, X, DCBCSB, DCBCRR, ENTSTK
FIXIT2:
    lda CCBRLN
    sta DCBCSB
    sta DCBCRR
    tsx
    stx ENTSTK
    jmp GOODIO
; The end of the patch code for the relocator. Zeros fill the page up to DNIBL + $96, where the table starts.
PEC1:
PD1 = <(*)                          ;; where the patches end in this page
PD2 = $96-PD1                       ;; the bytes of padding up to DNIBL + $96
    .res PD2,0
.else
; The 1980 DOS has no patches here. The space up to DNIBL + $96 holds leftover bytes.
    .byte $B3, $B3, $A0, $E0, $B3, $C3, $C5, $B3, $A0, $E0, $B3, $C3, $C5, $B3, $A0, $E0
    .byte $B3, $B3, $C5, $AA, $A0, $82, $B3, $B3, $C5, $AA, $A0, $82, $C5, $B3, $B3, $AA
    .byte $88, $82, $C5, $B3, $B3, $AA, $88, $82, $C5, $C4, $B3, $B0, $88
.endif
    .assert <* = $96
; DNIBL + $96 to DNIBL + $FF. A byte that is not a valid nibble has its own value as its entry. READ16 does not
; test for those; a bad nibble shows up only through the checksum.
    .byte $00, $01, $98
    .byte $99, $02, $03
    .byte $9C, $04, $05
    .byte $06, $A0, $A1
    .byte $A2, $A3, $A4
    .byte $A5, $07, $08
    .byte $A8, $A9, $AA
    .byte $09, $0A, $0B
    .byte $0C, $0D, $B0
    .byte $B1, $0E, $0F
    .byte $10, $11, $12
    .byte $13, $B8, $14
    .byte $15, $16, $17
    .byte $18, $19, $1A
    .byte $C0, $C1, $C2
    .byte $C3, $C4, $C5
    .byte $C6, $C7, $C8
    .byte $C9, $CA, $1B
    .byte $CC, $1C, $1D
    .byte $1E, $D0, $D1
    .byte $D2, $1F, $D4
    .byte $D5, $20, $21
    .byte $D8, $22, $23
    .byte $24, $25, $26
    .byte $27, $28, $E0
    .byte $E1, $E2, $E3
    .byte $E4, $29, $2A
    .byte $2B, $E8, $2C
    .byte $2D, $2E, $2F
    .byte $30, $31, $32
    .byte $F0, $F1, $33
    .byte $34, $35, $36
    .byte $37, $38, $F8
    .byte $39, $3A, $3B
    .byte $3C, $3D, $3E
    .byte $3F
;; The sector's 256 six-bit high parts, NBUF1 + n for byte n ($BB00 where DOS runs).
;;
;; It must start a page: READ16 and WRITE16 index it with Y from 0 to $FF and count each access at 4 cycles.
NBUF1:
.if YEAR = 1983
    .res 256,0
.else
    ; leftover: what the 1980 master holds here
    .byte $00, $38, $11, $0A, $08, $20, $20, $0E, $18, $06, $02, $31, $02, $09, $08, $27
    .byte $22, $00, $12, $0A, $0A, $04, $00, $00, $03, $2A, $00, $04, $00, $00, $22, $08
    .byte $10, $28, $12, $02, $00, $02, $08, $11, $0A, $08, $02, $28, $11, $01, $39, $22
    .byte $31, $01, $05, $18, $20, $28, $02, $10, $06, $02, $09, $02, $05, $2C, $10, $00
    .byte $08, $2E, $00, $05, $02, $28, $18, $02, $30, $23, $02, $20, $32, $04, $11, $02
    .byte $14, $02, $08, $09, $12, $20, $0E, $2F, $23, $30, $2F, $23, $30, $0C, $17, $2A
    .byte $3F, $27, $23, $30, $37, $23, $30, $12, $1A, $08, $30, $0F, $08, $30, $0F, $27
    .byte $23, $30, $37, $23, $30, $3A, $22, $34, $3C, $2A, $35, $08, $35, $0F, $2A, $2A
    .byte $08, $35, $0F, $2A, $25, $08, $35, $0F, $29, $10, $08, $31, $0F, $29, $11, $08
    .byte $31, $0F, $29, $0F, $08, $31, $0F, $29, $10, $11, $11, $11, $0F, $12, $12, $01
    .byte $0F, $27, $23, $30, $2F, $23, $30, $1A, $02, $2A, $08, $35, $0F, $2A, $37, $08
    .byte $35, $0F, $2A, $2A, $08, $35, $0F, $2A, $3A, $08, $35, $0F, $06, $2F, $23, $30
    .byte $2F, $23, $30, $18, $12, $12, $01, $0F, $27, $23, $30, $37, $23, $30, $1A, $3A
    .byte $3A, $3A, $02, $2A, $3A, $3A, $12, $1A, $27, $23, $30, $37, $23, $30, $18, $22
    .byte $29, $3A, $24, $28, $25, $22, $25, $3A, $24, $28, $25, $22, $25, $24, $24, $32
    .byte $25, $34, $25, $24, $24, $32, $25, $34, $25, $24, $28, $32, $28, $29, $21, $29
.endif
;; The sector's 86 six-bit values of low bit pairs, three bytes' pairs to a value ($BC00 where DOS runs).
;;
;; It must start a page: WRITE16 reads it as NBUF2 - 1 + Y, with Y from $56 down to 1, and counts on that always
;; crossing into NBUF2's page, a 5-cycle access.
NBUF2:
.if YEAR = 1983
    .res 86,0
.else
    ; leftover: what the 1980 master holds here
    .byte $00, $E1, $45, $28, $21, $82, $80, $38, $62, $19, $0B, $C5, $0B, $24, $21, $9C
    .byte $88, $00, $48, $28, $2B, $10, $00, $03, $0C, $A9, $01, $10, $01, $00, $88, $22
    .byte $40, $A0, $48, $09, $01, $08, $21, $44, $29, $22, $08, $A0, $45, $06, $E4, $8A
    .byte $C4, $06, $16, $60, $80, $A0, $09, $40, $18, $0A, $24, $0A, $16, $B0, $43, $00
    .byte $20, $BB, $00, $14, $08, $A0, $60, $0A, $C0, $8F, $0A, $83, $CA, $11, $44, $08
    .byte $51, $0A, $20, $26, $4A, $80
.endif
