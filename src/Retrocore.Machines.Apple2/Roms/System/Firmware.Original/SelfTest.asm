;; Checksum byte: the self-test expects the sum of $C100-$DFFF, excluding this byte, to equal it.
CHECKSUM:
    .byte $1B                       ; $C400

;; Built-in self-test, from B_RESETX with Solid-Apple held. Resets the stack, sends output to COUT1, homes the
;; screen, then checks the MMU status flags ($C011-$C018) against MMUFLAGS and toggles each MMU switch and
;; reads it back, then does the same for the IOU flags ($C01A-$C01F, IOUFLAGS) and switches. Any error prints
;; a header once and the failing flag number (FLAGERR) and the test hangs; otherwise ROM checksums follow.
;; Uses: $04..$0A, all
;;
;; Never returns.
SELFTEST:
    lda BUTN0                       ; $C401
    sta $05                         ; $C404 Open-Apple also held makes the RAM test click the speaker
    ldx #$FF                        ; $C406
    txs                             ; $C408
    lda #<COUT1                     ; $C409
    sta CSWL                        ; $C40B
    lda #>COUT1                     ; $C40D
    sta CSWH                        ; $C40F
    lda LCROM                       ; $C411
    jsr HOME                        ; $C414
    lda #$00                        ; $C417
    sta $09                         ; $C419
    sta $0A                         ; $C41B
    sta $08                         ; $C41D
    tax                             ; $C41F

SELFTEST_1:
    lda RDLCBNK2,x                  ; $C420
    eor MMUFLAGS,x                  ; $C423
    bpl SELFTEST_2                  ; $C426
    jsr FLAGERR                     ; $C428

SELFTEST_2:
    inx                             ; $C42B
    cpx #$08                        ; $C42C
    bne SELFTEST_1                  ; $C42E
    sta LCBANK1                     ; $C430
    bit RDLCBNK2                    ; $C433
    sta LCBANK2                     ; $C436
    bpl SELFTEST_3                  ; $C439
    jsr FLAGERR                     ; $C43B

SELFTEST_3:
    inx                             ; $C43E
    sta LCRAM2                      ; $C43F
    bit RDLCRAM                     ; $C442
    sta LCROM                       ; $C445
    bmi SELFTEST_4                  ; $C448
    jsr FLAGERR                     ; $C44A

SELFTEST_4:
    inx                             ; $C44D
    sta RDCARDRAM                   ; $C44E
    bit RDRAMRD                     ; $C451
    sta RDMAINRAM                   ; $C454
    bmi SELFTEST_5                  ; $C457
    jsr FLAGERR                     ; $C459

SELFTEST_5:
    inx                             ; $C45C
    sta WRCARDRAM                   ; $C45D
    bit RDRAMWRT                    ; $C460
    sta WRMAINRAM                   ; $C463
    bmi SELFTEST_6                  ; $C466
    jsr FLAGERR                     ; $C468

SELFTEST_6:
    inx                             ; $C46B
    sta SETALTZP                    ; $C46C
    bit RDALTZP                     ; $C46F
    sta SETSTDZP                    ; $C472
    bmi SELFTEST_7                  ; $C475
    jsr FLAGERR                     ; $C477

SELFTEST_7:
    inx                             ; $C47A
    sta SETSLOTC3ROM                ; $C47B
    bit RDC3ROM                     ; $C47E
    sta SETINTC3ROM                 ; $C481
    bmi SELFTEST_8                  ; $C484
    jsr FLAGERR                     ; $C486

SELFTEST_8:
    inx                             ; $C489
    sta SET80STORE                  ; $C48A
    bit RD80STORE                   ; $C48D
    sta KBD                         ; $C490
    bmi SELFTEST_9                  ; $C493
    jsr FLAGERR                     ; $C495

SELFTEST_9:
    jsr CROUT                       ; $C498
    ldx #$00                        ; $C49B
    lda #$FF                        ; $C49D
    sta $08                         ; $C49F

SELFTEST_10:
    lda RDTEXT,x                    ; $C4A1
    eor IOUFLAGS,x                  ; $C4A4
    bpl SELFTEST_11                 ; $C4A7
    jsr FLAGERR                     ; $C4A9

SELFTEST_11:
    inx                             ; $C4AC
    cpx #$06                        ; $C4AD
    bne SELFTEST_10                 ; $C4AF
    sta SET80VID                    ; $C4B1
    bit RD80VID                     ; $C4B4
    sta CLR80VID                    ; $C4B7
    bmi SELFTEST_12                 ; $C4BA
    jsr FLAGERR                     ; $C4BC

SELFTEST_12:
    inx                             ; $C4BF
    sta SETALTCHAR                  ; $C4C0
    bit RDALTCHAR                   ; $C4C3
    sta CLRALTCHAR                  ; $C4C6
    bmi SELFTEST_13                 ; $C4C9
    jsr FLAGERR                     ; $C4CB

SELFTEST_13:
    inx                             ; $C4CE
    sta TXTCLR                      ; $C4CF
    bit RDTEXT                      ; $C4D2
    sta TXTSET                      ; $C4D5
    bpl SELFTEST_14                 ; $C4D8
    jsr FLAGERR                     ; $C4DA

SELFTEST_14:
    inx                             ; $C4DD
    sta HISCR                       ; $C4DE
    bit RDPAGE2                     ; $C4E1
    sta LOWSCR                      ; $C4E4
    bmi SELFTEST_15                 ; $C4E7
    jsr FLAGERR                     ; $C4E9

SELFTEST_15:
    inx                             ; $C4EC
    sta MIXSET                      ; $C4ED
    bit RDMIXED                     ; $C4F0
    sta MIXCLR                      ; $C4F3
    bmi SELFTEST_16                 ; $C4F6
    jsr FLAGERR                     ; $C4F8

SELFTEST_16:
    inx                             ; $C4FB
    sta HIRES                       ; $C4FC
    bit RDHIRES                     ; $C4FF
    sta LORES                       ; $C502
    bmi SELFTEST_17                 ; $C505
    jsr FLAGERR                     ; $C507

SELFTEST_17:
    lda $09                         ; $C50A
    ora $0A                         ; $C50C
    beq ROMSUM1                     ; $C50E

SELFTEST_18:
    jmp SELFTEST_18                 ; $C510

;; Reports a failed switch flag: prints "MMU FLAG E4:" (while $08 = 0) or "IOU FLAG E5:" once, then the flag
;; number in hex and a space.
;; In: X = flag number, $08 = 0 for MMU, nonzero for IOU.
;; Out: $09/$0A = set to mark the error
;; Keeps: X
FLAGERR:
    stx $04                         ; $C513
    lda $08                         ; $C515
    bne FLAGERR_1                   ; $C517
    lda $09                         ; $C519
    bne FLAGERR_2                   ; $C51B
    ldx #MSGMMU - TESTMSGS          ; $C51D
    jsr TESTMSG                     ; $C51F
    inc $09                         ; $C522
    bne FLAGERR_2                   ; $C524

FLAGERR_1:
    lda $0A                         ; $C526
    bne FLAGERR_2                   ; $C528
    ldx #MSGIOU - TESTMSGS          ; $C52A
    jsr TESTMSG                     ; $C52C
    inc $0A                         ; $C52F

FLAGERR_2:
    lda $04                         ; $C531
    jsr PRHEX                       ; $C533
    lda #' '                        ; $C536
    jsr COUT1                       ; $C538
    lda $04                         ; $C53B
    tax                             ; $C53D
    rts                             ; $C53E

;; First ROM checksum: adds $C100-$DFFF (skipping $C400) and compares with $C400. On a mismatch prints
;; "ROM:E8" and hangs.
;; Uses: LOC0/LOC1, A, X, Y.
ROMSUM1:
    lda #$C1                        ; $C53F
    sta LOC1                        ; $C541
    lda #$00                        ; $C543
    sta LOC0                        ; $C545
    tay                             ; $C547

ROMSUM1_1:
    clc                             ; $C548
    adc (LOC0),y                    ; $C549
    iny                             ; $C54B
    bne ROMSUM1_1                   ; $C54C
    inc LOC1                        ; $C54E
    ldx LOC1                        ; $C550
    cpx #$C4                        ; $C552
    bne ROMSUM1_2                   ; $C554
    iny                             ; $C556
    bne ROMSUM1_1                   ; $C557

ROMSUM1_2:
    cpx #$E0                        ; $C559
    beq ROMSUM1_3                   ; $C55B
    bne ROMSUM1_1                   ; $C55D

ROMSUM1_3:
    cmp CHECKSUM                    ; $C55F
    beq ROMSUM2                     ; $C562
    ldx #MSGROM1 - TESTMSGS         ; $C564
    jsr TESTMSG                     ; $C566

ROMSUM1_4:
    jmp ROMSUM1_4                   ; $C569

;; Second ROM checksum: adds $E000-$FFFF (skipping $F7FF) and compares with $F7FF. On a mismatch prints
;; "ROM:E10" and hangs.
ROMSUM2:
    ldy #$00                        ; $C56C
    tya                             ; $C56E

ROMSUM2_1:
    clc                             ; $C56F
    adc (LOC0),y                    ; $C570
    iny                             ; $C572
    beq ROMSUM2_2                   ; $C573
    cpy #$FF                        ; $C575
    bne ROMSUM2_1                   ; $C577
    ldx LOC1                        ; $C579
    cpx #$F7                        ; $C57B
    bne ROMSUM2_1                   ; $C57D
    iny                             ; $C57F

ROMSUM2_2:
    inc LOC1                        ; $C580
    bne ROMSUM2_1                   ; $C582
    cmp $F7FF                       ; $C584
    beq RAMTEST                     ; $C587
    ldx #MSGROM2 - TESTMSGS         ; $C589
    jsr TESTMSG                     ; $C58B

ROMSUM2_3:
    jmp ROMSUM2_3                   ; $C58E

;; RAM test, shown on the hi-res screen: fills $0006-$BFFF, $D000-$DFFF in both language card banks and
;; $E000-$FFFF with 0, then makes passes upward and downward that check each byte holds the expected value
;; and replace it with its complement. Clicks the speaker per page when $05 bit 7 is set.
;; Uses: LOC0/LOC1 (the pointer), $02 (the expected value), $03 (lower limit), $04 (read/write marker), X
RAMTEST:
    lda TXTCLR                      ; $C591
    lda HIRES                       ; $C594
    lda MIXCLR                      ; $C597
    lda LCBANK2                     ; $C59A
    lda LCBANK2                     ; $C59D
    lda #$01                        ; $C5A0
    sta $04                         ; $C5A2
    lda #$FF                        ; $C5A4
    sta $03                         ; $C5A6
    lda #$00                        ; $C5A8
    tax                             ; $C5AA
    sta LOC0                        ; $C5AB
    sta LOC1                        ; $C5AD
    ldy #$06                        ; $C5AF

RAMTEST_1:
    sta (LOC0),y                    ; $C5B1
    iny                             ; $C5B3
    bne RAMTEST_1                   ; $C5B4
    bit $05                         ; $C5B6
    bpl RAMTEST_2                   ; $C5B8
    sta SPKR                        ; $C5BA

RAMTEST_2:
    inc LOC1                        ; $C5BD
    beq RAMTEST_6                   ; $C5BF
    lda LOC1                        ; $C5C1
    cmp #$C0                        ; $C5C3
    bne RAMTEST_3                   ; $C5C5
    lda #$D0                        ; $C5C7
    sta LOC1                        ; $C5C9
    bmi RAMTEST_5                   ; $C5CB

RAMTEST_3:
    cmp #$E0                        ; $C5CD
    bne RAMTEST_5                   ; $C5CF
    bit RDLCBNK2                    ; $C5D1
    bpl RAMTEST_4                   ; $C5D4
    lda LCBANK1                     ; $C5D6
    lda LCBANK1                     ; $C5D9
    lda #$D0                        ; $C5DC
    sta LOC1                        ; $C5DE
    bmi RAMTEST_5                   ; $C5E0

RAMTEST_4:
    lda LCBANK2                     ; $C5E2
    lda LCBANK2                     ; $C5E5

RAMTEST_5:
    txa                             ; $C5E8
    beq RAMTEST_1                   ; $C5E9

RAMTEST_6:
    sta $02                         ; $C5EB
    eor #$FF                        ; $C5ED
    tax                             ; $C5EF

RAMTEST_7:
    lda #$00                        ; $C5F0
    sta LOC1                        ; $C5F2
    ldy #$06                        ; $C5F4

RAMTEST_8:
    bit $05                         ; $C5F6
    bpl RAMTEST_9                   ; $C5F8
    sta SPKR                        ; $C5FA

RAMTEST_9:
    dec $04                         ; $C5FD
    lda (LOC0),y                    ; $C5FF
    cmp $02                         ; $C601
    beq RAMUP                       ; $C603
    jmp RAMFAIL                     ; $C605

;; RAM test, upward pass: writes the complement, verifies it and advances, switching language card banks at
;; $D000/$E000.
RAMUP:
    inc $04                         ; $C608
    txa                             ; $C60A
    sta (LOC0),y                    ; $C60B
    cmp (LOC0),y                    ; $C60D
    beq RAMUPNEXT                   ; $C60F
    jmp RAMFAIL                     ; $C611

;; RAM test, upward pass: next byte or page.
RAMUPNEXT:
    iny                             ; $C614
    bne RAMTEST_8                   ; $C615
    inc LOC1                        ; $C617
    beq RAMDOWN                     ; $C619
    lda LOC1                        ; $C61B
    cmp #$C0                        ; $C61D
    bne RAMUPNEXT_1                 ; $C61F
    lda #$D0                        ; $C621
    sta LOC1                        ; $C623
    bmi RAMTEST_8                   ; $C625

RAMUPNEXT_1:
    cmp #$E0                        ; $C627
    bne RAMTEST_8                   ; $C629
    bit RDLCBNK2                    ; $C62B
    bpl RAMUPNEXT_2                 ; $C62E
    lda LCBANK1                     ; $C630
    lda LCBANK1                     ; $C633
    lda #$D0                        ; $C636
    sta LOC1                        ; $C638
    bmi RAMTEST_8                   ; $C63A

RAMUPNEXT_2:
    lda LCBANK2                     ; $C63C
    lda LCBANK2                     ; $C63F
    jmp RAMTEST_8                   ; $C642

;; RAM test: start of the downward pass, with the expected value swapped for its complement.
RAMDOWN:
    sta $02                         ; $C645
    eor #$FF                        ; $C647
    tax                             ; $C649
    beq RAMTEST_7                   ; $C64A

RAMDOWN_1:
    lda #$FF                        ; $C64C
    sta LOC1                        ; $C64E
    tay                             ; $C650

RAMDOWN_2:
    bit $05                         ; $C651
    bpl RAMDOWN_3                   ; $C653
    sta SPKR                        ; $C655

RAMDOWN_3:
    dec $04                         ; $C658
    lda (LOC0),y                    ; $C65A
    cmp $02                         ; $C65C
    bne RAMFAIL                     ; $C65E
    inc $04                         ; $C660
    txa                             ; $C662
    sta (LOC0),y                    ; $C663
    cmp (LOC0),y                    ; $C665
    bne RAMFAIL                     ; $C667
    dey                             ; $C669
    cpy $03                         ; $C66A
    bne RAMDOWN_2                   ; $C66C
    dec LOC1                        ; $C66E
    lda LOC1                        ; $C670
    cmp #$FF                        ; $C672
    beq RAMDOWN_7                   ; $C674
    cmp #$CF                        ; $C676
    bne RAMDOWN_5                   ; $C678
    bit RDLCBNK2                    ; $C67A
    bpl RAMDOWN_4                   ; $C67D
    lda LCBANK1                     ; $C67F
    lda LCBANK1                     ; $C682
    lda #$DF                        ; $C685
    sta LOC1                        ; $C687
    bmi RAMDOWN_2                   ; $C689

RAMDOWN_4:
    lda LCBANK2                     ; $C68B
    lda LCBANK2                     ; $C68E
    lda #$BF                        ; $C691
    sta LOC1                        ; $C693
    bmi RAMDOWN_2                   ; $C695

RAMDOWN_5:
    cmp #$00                        ; $C697
    beq RAMDOWN_6                   ; $C699
    bne RAMDOWN_2                   ; $C69B

RAMDOWN_6:
    lda #$06                        ; $C69D
    sta $03                         ; $C69F
    bne RAMDOWN_2                   ; $C6A1

RAMDOWN_7:
    txa                             ; $C6A3
    beq TESTPASS                    ; $C6A4
    sta $02                         ; $C6A6
    sta $03                         ; $C6A8
    eor #$FF                        ; $C6AA
    tax                             ; $C6AC
    beq RAMDOWN_1                   ; $C6AD

;; RAM test failure: switches language card ROM back in, resets the text screen and prints "RAM:",
;; then works out which bits failed (RAMBITS). $04 tells whether the bad byte was found on the read (0)
;; or on the write-back check (1).
RAMFAIL:
    lda LCROM                       ; $C6AF
    jsr TESTSCRN                    ; $C6B2
    lda TXTSET                      ; $C6B5
    ldx #MSGRAM - TESTMSGS          ; $C6B8
    jsr TESTMSG                     ; $C6BA
    lda $04                         ; $C6BD
    beq RAMBITS                     ; $C6BF
    lda $02                         ; $C6C1
    eor #$FF                        ; $C6C3
    eor (LOC0),y                    ; $C6C5
    sta $06                         ; $C6C7
    jmp RAMBITS_1                   ; $C6C9

;; RAM test failure, part two: XORs the expected value with the byte read to find the bad bits ($06), then
;; prints a chip location ("F13" for bit 7 down to "F6" for bit 0) for each, and hangs.
RAMBITS:
    lda $02                         ; $C6CC
    eor (LOC0),y                    ; $C6CE
    sta $06                         ; $C6D0

RAMBITS_1:
    lda $06                         ; $C6D2
    asl a                           ; $C6D4
    bcc RAMBITS_2                   ; $C6D5
    ldx #MSGF13 - TESTMSGS          ; $C6D7
    jsr TESTMSG                     ; $C6D9

RAMBITS_2:
    asl a                           ; $C6DC
    bcc RAMBITS_3                   ; $C6DD
    ldx #MSGF12 - TESTMSGS          ; $C6DF
    jsr TESTMSG                     ; $C6E1

RAMBITS_3:
    asl a                           ; $C6E4
    bcc RAMBITS_4                   ; $C6E5
    ldx #MSGF11 - TESTMSGS          ; $C6E7
    jsr TESTMSG                     ; $C6E9

RAMBITS_4:
    asl a                           ; $C6EC
    bcc RAMBITS_5                   ; $C6ED
    ldx #MSGF10 - TESTMSGS          ; $C6EF
    jsr TESTMSG                     ; $C6F1

RAMBITS_5:
    asl a                           ; $C6F4
    bcc RAMBITS_6                   ; $C6F5
    ldx #MSGF9 - TESTMSGS           ; $C6F7
    jsr TESTMSG                     ; $C6F9

RAMBITS_6:
    asl a                           ; $C6FC
    bcc RAMBITS_7                   ; $C6FD
    ldx #MSGF8 - TESTMSGS           ; $C6FF
    jsr TESTMSG                     ; $C701

RAMBITS_7:
    asl a                           ; $C704
    bcc RAMBITS_8                   ; $C705
    ldx #MSGF7 - TESTMSGS           ; $C707
    jsr TESTMSG                     ; $C709

RAMBITS_8:
    asl a                           ; $C70C
    bcc RAMBITS_9                   ; $C70D
    ldx #MSGF6 - TESTMSGS           ; $C70F
    jsr TESTMSG                     ; $C711

RAMBITS_9:
    jmp RAMBITS_9                   ; $C714

;; All tests passed: restores the text screen. If both Apple keys are still held, runs TESTLOOP; otherwise
;; prints "KERNEL OK" and hangs.
TESTPASS:
    lda LCROM                       ; $C717
    jsr TESTSCRN                    ; $C71A
    lda TXTSET                      ; $C71D
    lda BUTN0                       ; $C720
    and BUTN1                       ; $C723
    bmi TESTLOOP                    ; $C726
    ldx #MSGOK - TESTMSGS           ; $C728
    jsr TESTMSG                     ; $C72A

TESTPASS_1:
    jmp TESTPASS_1                  ; $C72D

;; Copies the 53-byte program at LOOPCODE to $0100 and runs it.
TESTLOOP:
    ldx #$00                        ; $C730

TESTLOOP_1:
    lda LOOPCODE,x                  ; $C732
    sta $0100,x                     ; $C735
    inx                             ; $C738
    cpx #LOOPCODEEND - LOOPCODE     ; $C739
    bne TESTLOOP_1                  ; $C73B
    jmp $0100                       ; $C73D

;; Prints the zero-terminated message at TESTMSGS+X through COUT1.
;; In: X = offset of the message
;; Keeps: A (via $07)
;; Out: X = the offset of the terminator
TESTMSG:
    sta $07                         ; $C740

TESTMSG_1:
    lda TESTMSGS,x                  ; $C742
    beq TESTMSG_2                   ; $C745
    jsr COUT1                       ; $C747
    inx                             ; $C74A
    bne TESTMSG_1                   ; $C74B

TESTMSG_2:
    lda $07                         ; $C74D
    rts                             ; $C74F

;; Self-test messages for TESTMSG, each ended by $00 and found by its offset from TESTMSGS. The RAM chip
;; locations run from F13 (bit 7) down to F6 (bit 0).
TESTMSGS:
MSGROM1:
    .byte "ROM:E8", KEY_CR, 0       ; $C750
MSGROM2:
    .byte "ROM:E10", KEY_CR, 0      ; $C758
MSGRAM:
    .byte "RAM:", 0                 ; $C761
MSGOK:
    .byte "KERNEL OK", 0            ; $C766
MSGF13:
    .byte "F13 ", 0                 ; $C770
MSGF12:
    .byte "F12 ", 0                 ; $C775
MSGF11:
    .byte "F11 ", 0                 ; $C77A
MSGF10:
    .byte "F10 ", 0                 ; $C77F
MSGF9:
    .byte "F9 ", 0                  ; $C784
MSGF8:
    .byte "F8 ", 0                  ; $C788
MSGF7:
    .byte "F7 ", 0                  ; $C78C
MSGF6:
    .byte "F6 ", 0                  ; $C790
MSGMMU:
    .byte "MMU FLAG E4:", 0         ; $C794
MSGIOU:
    .byte "IOU FLAG E5:", 0         ; $C7A1

;; Code copied to $0100 by TESTLOOP and run there: selects slot ROMs, reads and rewrites every byte from
;; $C090 to $CFFF, reads $C079 down to $C001, switches internal ROM and text back in and restarts SELFTEST
;; at $C401. It is assembled here; it has only relative branches and no absolute references to itself,
;; so it runs the same at $0100.
LOOPCODE:
    sta SETSLOTCXROM                ; $C7AE
    sta CLRROM                      ; $C7B1
    ldy #$00                        ; $C7B4
    lda #$C0                        ; $C7B6
    sta LOC1                        ; $C7B8
    lda #$00                        ; $C7BA
    sta LOC0                        ; $C7BC
    ldy #$90                        ; $C7BE

LOOPCODE_1:
    lda (LOC0),y                    ; $C7C0
    sta (LOC0),y                    ; $C7C2
    iny                             ; $C7C4
    bne LOOPCODE_1                  ; $C7C5
    inc LOC1                        ; $C7C7
    lda LOC1                        ; $C7C9
    cmp #$D0                        ; $C7CB
    bne LOOPCODE_1                  ; $C7CD
    lda #$C0                        ; $C7CF
    sta LOC1                        ; $C7D1
    ldy #$79                        ; $C7D3

LOOPCODE_2:
    lda (LOC0),y                    ; $C7D5
    dey                             ; $C7D7
    bne LOOPCODE_2                  ; $C7D8
    sta SETINTCXROM                 ; $C7DA
    sta TXTSET                      ; $C7DD
    jmp SELFTEST                    ; $C7E0
LOOPCODEEND:

;; Resets the text screen for the self-test: INIT, normal video (INVFLG = $FF) and HOME.
TESTSCRN:
    jsr INIT                        ; $C7E3
    lda #$FF                        ; $C7E6
    sta INVFLG                      ; $C7E8
    jsr HOME                        ; $C7EA
    rts                             ; $C7ED

;; Expected MMU flag states for $C011-$C018 (bit 7): bank 2 and internal $CX ROM on, the rest off.
MMUFLAGS:
    .byte $80, $00, $00, $00, $80, $00, $00, $00 ; $C7EE

;; Expected IOU flag states for $C01A-$C01F (bit 7): text on, the rest off.
IOUFLAGS:
    .byte $80, $00, $00, $00, $00, $00 ; $C7F6
    .byte $00, $00, $00, $00        ; $C7FC
