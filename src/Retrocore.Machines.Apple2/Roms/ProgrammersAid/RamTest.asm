;; PROGRAMMER'S AID #1: RAM TEST ($D5BC-$D6DC)
;;
;; Steve Wozniak's memory test (1977), run from the Monitor: D5BCG sets the Monitor's Ctrl-Y up (<RamTest::SETUP>), and
;; then `start.pages` Ctrl-Y tests the given number of pages from the start page, which the Monitor leaves in A1 and A2.
;; It fills the block with $00 and checks it, then with $FF, and then gallops: each cell in turn holds the inverse of
;; the data while every cell a power-of-2 distance from it is written and checked, which finds cells and address lines
;; that disturb one another. It beeps after a test that finds nothing.
;;
;; An error in the fill prints `address expected bad ERR`, then each failing chip as its row and column, `r-c`: the
;; row is D if the block starts below $5000 and E otherwise, the column the socket of the data bit that failed. An
;; error in the gallop prints the cell, the expected and bad data, the neighbor's address and the gallop data, then
;; ERR.
;;
;; Names follow Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1), which is of an earlier version: this one reports the failing chips
;; (<RamTest::ERRBITS>), and the original chip jumps to $02CB at $D670 where the listing prints a byte, which
;; RAMTESTFIX puts back. Part of ProgrammersAid.asm.

.scope RamTest

DATA = $00                          ;; the test data, $00 or $FF
NDATA = $01                         ;; its inverse
TESTD = $02                         ;; the gallop's data
R3L = $06                           ;; the address checked (2 bytes)
R3H = $07                           ;; its high byte
R4L = $08                           ;; the address written (2 bytes): the gallop's neighbor
R4H = $09                           ;; its high byte
R5L = $0A                           ;; the gallop's test cell (2 bytes)
R5H = $0B                           ;; its high byte
R6L = $0C                           ;; the gallop's bit mask (2 bytes), $0001 to 2^n
R6H = $0D                           ;; its high byte
BADBITS = $0E                       ;; the data bits that failed, which <ERRBITS> reports
YSAVE = $0F                         ;; where <ERRBITS> keeps Y

;; Inherit: <Monitor:YSAV>
YSAV = $34

;; Inherit: <Monitor:A1H>
A1H = $3D

;; Inherit: <Monitor:A2L>
A2L = $3E

;; Inherit: <Monitor:PRBYTE>
PRBYTE = $FDDA

;; Inherit: <Monitor:COUT>
COUT = $FDED

;; Inherit: <Monitor:PRERR>
PRERR = $FF2D

;; Inherit: <Monitor:BELL>
BELL = $FF3A

;; D5BCG: points the Monitor's Ctrl-Y command at <RAMTST>.
SETUP:
    lda #<RAMTST                    ; $D5BC
    ldy #>RAMTST                    ; $D5BE
    jmp SETCTLY                     ; $D5C0

;; The Ctrl-Y command: tests A2L pages from page A1H with $00, then $FF, and beeps.
RAMTST:
    lda #$00                        ; $D5C3
    jsr TEST                        ; $D5C5
    lda #$FF                        ; $D5C8
    jsr TEST                        ; $D5CA
    jmp BELL                        ; $D5CD

;; Tests the block with the data in A: fills it and checks it, then gallops.
;; In: A = the data, A1H = the first page, A2L = the number of pages
TEST:
    sta DATA                        ; $D5D0
    eor #$FF                        ; $D5D2
    sta NDATA                       ; $D5D4
    lda A1H                         ; $D5D6
    sta R3H                         ; $D5D8
    sta R4H                         ; $D5DA
    sta R5H                         ; $D5DC
    ldy #$00                        ; $D5DE
    sty R3L                         ; $D5E0
    sty R4L                         ; $D5E2
    sty R5L                         ; $D5E4
    ldx A2L                         ; $D5E6
    lda DATA                        ; $D5E8

TEST01:
    sta (R4L),y                     ; $D5EA fill the block
    iny                             ; $D5EC
    bne TEST01                      ; $D5ED
    inc R4H                         ; $D5EF
    dex                             ; $D5F1
    bne TEST01                      ; $D5F2
    ldx A2L                         ; $D5F4

TEST02:
    lda (R3L),y                     ; $D5F6 check it
    cmp DATA                        ; $D5F8
    beq TEST03                      ; $D5FA
    pha                             ; $D5FC
    lda R3H                         ; $D5FD
    jsr PRBYTE                      ; $D5FF
    tya                             ; $D602
    jsr PRBYSP                      ; $D603
    lda DATA                        ; $D606
    jsr PRBYSP                      ; $D608
    pla                             ; $D60B
    jsr ERRBITS                     ; $D60C

TEST03:
    iny                             ; $D60F
    bne TEST02                      ; $D610
    inc R3H                         ; $D612
    dex                             ; $D614
    bne TEST02                      ; $D615
    ldx A2L                         ; $D617

TEST04:
    lda NDATA                       ; $D619 the test cell gets the inverse
    sta (R5L),y                     ; $D61B
    sty R6H                         ; $D61D
    sty R6L                         ; $D61F
    inc R6L                         ; $D621

TEST05:
    lda NDATA                       ; $D623
    jsr TEST6                       ; $D625
    lda DATA                        ; $D628
    jsr TEST6                       ; $D62A
    asl R6L                         ; $D62D the next neighbor, twice as far
    rol R6H                         ; $D62F
    lda R6H                         ; $D631
    cmp A2L                         ; $D633
    bcc TEST05                      ; $D635
    lda DATA                        ; $D637
    sta (R5L),y                     ; $D639
    inc R5L                         ; $D63B
    bne TEST04                      ; $D63D
    inc R5H                         ; $D63F
    dex                             ; $D641
    bne TEST04                      ; $D642

RTS1:
    rts                             ; $D644

;; Writes the gallop data to the test cell's neighbor, and checks that the test cell kept its data.
;; In: A = the gallop data, R5L = the test cell, R6L = the bit that makes the neighbor
TEST6:
    sta TESTD                       ; $D645
    lda R5L                         ; $D647
    eor R6L                         ; $D649
    sta R4L                         ; $D64B
    lda R5H                         ; $D64D
    eor R6H                         ; $D64F
    sta R4H                         ; $D651
    lda TESTD                       ; $D653
    sta (R4L),y                     ; $D655
    lda (R5L),y                     ; $D657
    cmp NDATA                       ; $D659
    beq RTS1                        ; $D65B
    pha                             ; $D65D the test cell changed
    lda R5H                         ; $D65E
    jsr PRBYTE                      ; $D660
    lda R5L                         ; $D663
    jsr PRBYSP                      ; $D665
    lda NDATA                       ; $D668
    sta (R5L),y                     ; $D66A
    jsr PRBYSP                      ; $D66C
    pla                             ; $D66F
.if RAMTESTFIX
    jsr PRBYSP                      ; $D670 the bad data
.else
    jmp $02CB                       ; $D670
.endif
    lda R4H                         ; $D673
    jsr PRBYTE                      ; $D675
    lda R4L                         ; $D678
    jsr PRBYSP                      ; $D67A
    lda TESTD                       ; $D67D

;; Prints a byte and a space, then ERR, beeping, and a return.
;; In: A = the byte
PRBYCR:
    jsr PRBYSP                      ; $D67F
    jsr PRERR                       ; $D682

PRBYCR_1:
    lda #$8D                        ; $D685
    jmp COUT                        ; $D687

;; Prints a byte in hex and a space.
;; In: A = the byte
;; Uses: A
PRBYSP:
    jsr PRBYTE                      ; $D68A
    lda #$A0                        ; $D68D
    jmp COUT                        ; $D68F

;; Prints the bad data, ERR, and then each failing chip as ` r-c`: its row, D if the block starts below $5000 and E
;; otherwise, and the socket of the data bit that differs, then a return.
;; In: A = the bad data, DATA = the data expected
;; Keeps: Y
ERRBITS:
    sty YSAVE                       ; $D692
    sta BADBITS                     ; $D694
    jsr PRBYSP                      ; $D696
    jsr PRERR                       ; $D699
    lda DATA                        ; $D69C
    eor BADBITS                     ; $D69E
    sta BADBITS                     ; $D6A0
    ldy #$07                        ; $D6A2

ERRBITS_1:
    lsr BADBITS                     ; $D6A4
    bcc ERRBITS_3                   ; $D6A6
    lda #$A0                        ; $D6A8 " "
    jsr COUT                        ; $D6AA
    lda A1H                         ; $D6AD
    cmp #$50                        ; $D6AF
    lda #$C4                        ; $D6B1 "D", or "E" from $5000
    adc #$00                        ; $D6B3
    jsr COUT                        ; $D6B5
    lda #$AD                        ; $D6B8 "-"
    jsr COUT                        ; $D6BA
    tya                             ; $D6BD
    bne ERRBITS_2                   ; $D6BE
    lda #$B1                        ; $D6C0 bit 7's socket is 10
    jsr COUT                        ; $D6C2

ERRBITS_2:
    lda SOCKETS,y                   ; $D6C5
    jsr COUT                        ; $D6C8

ERRBITS_3:
    dey                             ; $D6CB
    bpl ERRBITS_1                   ; $D6CC
    ldy YSAVE                       ; $D6CE
    jmp PRBYCR_1                    ; $D6D0

;; The last digit of each data bit's socket, from bit 7 (10, printed with its 1) to bit 0 (3); the last two are never
;; read.
SOCKETS:
    .byte "0987654321"              ; $D6D3

.endscope
