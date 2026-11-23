;; Applesoft cold start ($F10B-$F1D4).
;;
;; The <CharacterReaderTemplate> template initializes the page-zero character reader and random seed; <INIT> installs the
;; interpreter vectors, discovers available memory and enters <MAIN>. <CharacterReaderTemplate> immediately follows
;; <Float::ArctangentPolynomial> in MsBasic.Transcendental.asm. AppleSoft.AppleCommands.asm follows this module.

;; Group: Cold start

    CharacterReader $58

;; Cold-starts Applesoft, initializes its workspace and enters <MAIN>.
;;
;; It installs the restart and USR vectors, copies <CharacterReaderTemplate> and four bytes of the initial random value to page
;; zero, probes RAM by complementing and restoring a byte on each page, rounds the upper limit down to a 4 KB
;; boundary, initializes the program at $0800 and resets the interpreter. The probe stops at the first location
;; that fails either test.
INIT:
    ldx #$FF
    stx CURLIN+1
    ldx #$FB
    txs
    lda #<INIT
    ldy #>INIT
    sta START+1
    sty START+2
    sta RDYJSR+1
    sty RDYJSR+2
    jsr NRMSTM
    lda #$4C
    sta START
    sta RDYJSR
    sta JMPER
    sta USRPOK
    lda #<FCERR
    ldy #>FCERR
    sta USRPOK+1
    sty USRPOK+2
    ldx #$1C

MOVCHG:
    lda INITAT-1,x
    sta CHRGET-1,x
    stx SPEEDZ
    dex
    bne MOVCHG
    stx TRCFLG
    txa
    sta BITS
    sta LASTPT+1
    pha
    lda #3
    sta FOUR6
    jsr CRDO
    lda #1
    sta BUF-3
    sta BUF-4
    ldx #TEMPST
    stx TEMPPT
    lda #0
    ldy #8
    sta LINNUM
    sty LINNUM+1
    ldy #0

LOOPMM:
    inc LINNUM+1
    lda (LINNUM),y
    eor #$FF
    sta (LINNUM),y
    cmp (LINNUM),y
    bne USEDEC
    eor #$FF
    sta (LINNUM),y
    cmp (LINNUM),y
    beq LOOPMM

USEDEC:
    ldy LINNUM
    lda LINNUM+1
    and #$F0
    sty MEMSIZ
    sta MEMSIZ+1
    sty FRETOP
    sta FRETOP+1
    ldx #0
    ldy #8
    stx TXTTAB
    sty TXTTAB+1
    ldy #0
    sty LOCK
    tya
    sta (TXTTAB),y
    inc TXTTAB
    bne QROOM
    inc TXTTAB+1

QROOM:
    lda TXTTAB
    ldy TXTTAB+1
    jsr REASON
    jsr SCRTCH
    lda #<STROUT
    ldy #>STROUT
    sta RDYJSR+1
    sty RDYJSR+2
    lda #<MAIN
    ldy #>MAIN
    sta START+1
    sty START+2
    jmp (START+1)
