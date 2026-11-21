;; Self-test (from RESETFW when BUTN1 is down; destroys memory). Shows graphics (TXTCLR), fills and
;; checks page zero with five patterns built from TESTPATTERNS (an error goes to TESTFAIL as RAM ZP), then
;; continues with RAMTEST.
;; $C603 is re-entered with the alternate zero page and aux RAM selected to test aux memory.
;; Uses: all
SELFTEST:
    sta TXTCLR                      ; $C600

SELFTEST_1:
    ldy #$04                        ; $C603 re-entered to test auxiliary memory
    ldx #$00                        ; $C605

SELFTEST_2:
    clc                             ; $C607
    adc TESTPATTERNS,y              ; $C608
    sta LOC0,x                      ; $C60B
    inx                             ; $C60D
    bne SELFTEST_2                  ; $C60E

SELFTEST_3:
    clc                             ; $C610
    adc TESTPATTERNS,y              ; $C611
    cmp LOC0,x                      ; $C614
    bne SELFTEST_5                  ; $C616
    inx                             ; $C618
    bne SELFTEST_3                  ; $C619
    ror a                           ; $C61B
    bit RDVBLBAR                    ; $C61C
    bpl SELFTEST_4                  ; $C61F
    eor #$A5                        ; $C621

SELFTEST_4:
    dey                             ; $C623
    bpl SELFTEST_2                  ; $C624
    bmi RAMTEST                     ; $C626

SELFTEST_5:
    eor LOC0,x                      ; $C628
    clc                             ; $C62A
    jmp TESTFAIL_1                  ; $C62B

;; The page the self-test's RAM test is filling or checking.
;;
;; <RAMTEST> counts it from $01 through $FF on each pass, filling the pages and then checking them. Pages
;; $C0-$CF, the I/O space, test language card bank 1 instead, through <TESTPTR>.
;; See: <TESTPTR>, <TESTCOUNT>, <RAMTEST>
TESTPAGE = $01

;; The self-test's pointer to the page it is testing, a page address with the low byte 0.
;;
;; <RAMTEST> sets its high byte from <TESTPAGE>, adding $10 for the pages $C0-$CF so that they reach bank 1 of
;; the language card at $D000-$DFFF, and fills or checks the page through it.
;; See: <TESTPAGE>, <RAMTEST>
TESTPTR = $02

;; The number of passes the self-test's RAM test has left after this one.
;;
;; <RAMTEST> sets it to 4 and makes five passes, each starting from a different pattern.
;; See: <TESTPAGE>, <RAMTEST>
TESTCOUNT = $04

;; Fills pages $01-$FF with patterns and verifies them, five passes ($04 counts). Pages $D0-$FF use
;; language card bank 2 RAM; pages $C0-$CF are redirected to bank 1 ($D0-$DF). A mismatch goes to
;; TESTFAIL. Then AUXRAMTEST: when aux memory answers and aux $0800 does not change along with $0C00
;; (more than 1K of aux memory), sets ALTZP and repeats the whole test there from $C603; otherwise the
;; MMU/IOU test at $C736 follows.
;; Uses: TESTPAGE, TESTPTR, TESTCOUNT, LCBANK2/LCBANK1
RAMTEST:
    stx TESTPAGE                    ; $C62E
    stx TESTPTR                     ; $C630
    stx TESTPTR+1                   ; $C632
    ldx #$04                        ; $C634
    stx TESTCOUNT                   ; $C636

RAMTEST_1:
    inc TESTPAGE                    ; $C638

RAMTEST_2:
    tay                             ; $C63A
    sta LCBANK2                     ; $C63B
    sta LCBANK2                     ; $C63E
    lda TESTPAGE                    ; $C641
    and #$F0                        ; $C643
    cmp #$C0                        ; $C645
    bne RAMTEST_3                   ; $C647
    lda LCBANK1                     ; $C649
    lda LCBANK1                     ; $C64C
    lda TESTPAGE                    ; $C64F
    adc #$0F                        ; $C651
    bne RAMTEST_4                   ; $C653

RAMTEST_3:
    lda TESTPAGE                    ; $C655

RAMTEST_4:
    sta TESTPTR+1                   ; $C657
    tya                             ; $C659
    ldy #$00                        ; $C65A

RAMTEST_5:
    clc                             ; $C65C
    adc TESTPATTERNS,x              ; $C65D
    sta (TESTPTR),y                 ; $C660
    dex                             ; $C662
    bpl RAMTEST_6                   ; $C663
    ldx #$04                        ; $C665

RAMTEST_6:
    iny                             ; $C667
    bne RAMTEST_5                   ; $C668
    inc TESTPAGE                    ; $C66A
    bne RAMTEST_2                   ; $C66C
    inc TESTPAGE                    ; $C66E

RAMTEST_7:
    tay                             ; $C670
    lda LCBANK2                     ; $C671
    lda LCBANK2                     ; $C674
    lda TESTPAGE                    ; $C677
    and #$F0                        ; $C679
    cmp #$C0                        ; $C67B
    bne RAMTEST_8                   ; $C67D
    lda LCBANK1                     ; $C67F
    lda TESTPAGE                    ; $C682
    adc #$0F                        ; $C684
    bne RAMTEST_9                   ; $C686

RAMTEST_8:
    lda TESTPAGE                    ; $C688

RAMTEST_9:
    sta TESTPTR+1                   ; $C68A
    tya                             ; $C68C
    ldy #$00                        ; $C68D

RAMTEST_10:
    clc                             ; $C68F
    adc TESTPATTERNS,x              ; $C690
    eor (TESTPTR),y                 ; $C693
    bne TESTFAIL                    ; $C695
    lda (TESTPTR),y                 ; $C697
    dex                             ; $C699
    bpl RAMTEST_11                  ; $C69A
    ldx #$04                        ; $C69C

RAMTEST_11:
    iny                             ; $C69E
    bne RAMTEST_10                  ; $C69F
    inc TESTPAGE                    ; $C6A1
    bne RAMTEST_7                   ; $C6A3
    ror a                           ; $C6A5
    bit RDVBLBAR                    ; $C6A6
    bpl RAMTEST_12                  ; $C6A9
    eor #$A5                        ; $C6AB

RAMTEST_12:
    dec TESTCOUNT                   ; $C6AD
    bpl RAMTEST_1                   ; $C6AF
    tax                             ; $C6B1
    jsr AUXRAMTEST                  ; $C6B2
    bne RAMTEST_13                  ; $C6B5
    asl $0C00                       ; $C6B7
    asl a                           ; $C6BA
    cmp $0C00                       ; $C6BB

RAMTEST_13:
    bne SWITCHTEST                  ; $C6BE
    cmp $0800                       ; $C6C0
    beq SWITCHTEST                  ; $C6C3
    txa                             ; $C6C5
    sta SETALTZP                    ; $C6C6
    jmp SELFTEST_1                  ; $C6C9

;; Self-test failure display (sec entry: RAM; $C6CD with carry clear: zero page). Resets several
;; switches to main memory and 40 columns, clears the text page, and shows "RAM" or "RAM ZP" (with
;; "*" when aux memory was selected) followed by the failing bits in X as 0/1, then hangs. With X = 0
;; it shows "MMU" (carry clear) or "IOU" (carry set) and hangs.
;; $C736 is the MMU/IOU soft switch test: sets each switch pair from TESTSWITCH1/TESTSWITCH2 by a rotating bit
;; and checks the status byte listed in TESTSTATUS; a mismatch shows MMU (first group) or IOU (second).
;; In: X = failing bits, carry, A
TESTFAIL:
    sec                             ; $C6CC

TESTFAIL_1:
    tax                             ; $C6CD
    lda RDRAMRD                     ; $C6CE
    clv                             ; $C6D1
    bpl TESTFAIL_2                  ; $C6D2
    bit TESTPATTERNS                ; $C6D4

TESTFAIL_2:
    lda #' '                        ; $C6D7
    ldy #$06                        ; $C6D9

TESTFAIL_3:
    sta $BFFE,y                     ; $C6DB stores to $C004/$C002/$C000 and $C00C/$C00A/$C008
    sta SETSLOTCXROM,y              ; $C6DE
    dey                             ; $C6E1
    dey                             ; $C6E2
    bne TESTFAIL_3                  ; $C6E3
    sta TXTSET                      ; $C6E5
    sta LOWSCR                      ; $C6E8

TESTFAIL_4:
    sta LINE1,y                     ; $C6EB
    sta $0500,y                     ; $C6EE
    sta $0600,y                     ; $C6F1
    sta $0700,y                     ; $C6F4
    iny                             ; $C6F7
    bne TESTFAIL_4                  ; $C6F8
    txa                             ; $C6FA
    beq TESTFAIL_9                  ; $C6FB
    ldy #$03                        ; $C6FD
    bcs TESTFAIL_5                  ; $C6FF
    ldy #$05                        ; $C701

TESTFAIL_5:
    lda #'*'                        ; $C703
    bvc TESTFAIL_6                  ; $C705
    sta $05B0                       ; $C707

TESTFAIL_6:
    lda RAMZPTEXT,y                 ; $C70A
    sta $05B1,y                     ; $C70D
    dey                             ; $C710
    bpl TESTFAIL_6                  ; $C711
    ldy #$10                        ; $C713

TESTFAIL_7:
    txa                             ; $C715
    lsr a                           ; $C716
    tax                             ; $C717
    lda #'0' >> 1                   ; $C718
    rol a                           ; $C71A "0" or "1"
    sta $05B6,y                     ; $C71B
    dey                             ; $C71E
    dey                             ; $C71F
    bne TESTFAIL_7                  ; $C720

TESTFAIL_8:
    beq TESTFAIL_8                  ; $C722

TESTFAIL_9:
    ldy #$02                        ; $C724

TESTFAIL_10:
    lda MMUTEXT,y                   ; $C726
    bcc TESTFAIL_11                 ; $C729
    lda IOUTEXT,y                   ; $C72B

TESTFAIL_11:
    sta $05B8,y                     ; $C72E
    dey                             ; $C731
    bpl TESTFAIL_10                 ; $C732

TESTFAIL_12:
    bmi TESTFAIL_12                 ; $C734

SWITCHTEST:
    ldy #$01                        ; $C736 MMU/IOU soft switch test

SWITCHTEST_1:
    lda #$7F                        ; $C738

SWITCHTEST_2:
    ror a                           ; $C73A
    ldx TESTSWITCH1,y               ; $C73B
    beq SWITCHTEST_5                ; $C73E
    bcc SWITCHTEST_3                ; $C740
    ldx TESTSWITCH2,y               ; $C742

SWITCHTEST_3:
    sta $BFFF,x                     ; $C745
    iny                             ; $C748
    bne SWITCHTEST_2                ; $C749

SWITCHTEST_4:
    ldx SPKR                        ; $C74B
    rol a                           ; $C74E

SWITCHTEST_5:
    dey                             ; $C74F
    ldx TESTSTATUS,y                ; $C750
    beq SWITCHTEST_7                ; $C753
    bmi SWITCHTEST_4                ; $C755
    rol a                           ; $C757
    bcc SWITCHTEST_6                ; $C758
    asl KBD,x                       ; $C75A
    bcc SWITCHTEST_8                ; $C75D
    bcs SWITCHTEST_5                ; $C75F

SWITCHTEST_6:
    asl KBD,x                       ; $C761
    bcs SWITCHTEST_8                ; $C764
    bcc SWITCHTEST_5                ; $C766

SWITCHTEST_7:
    rol a                           ; $C768
    iny                             ; $C769
    sec                             ; $C76A
    sbc #$01                        ; $C76B
    bcs SWITCHTEST_2                ; $C76D
    dey                             ; $C76F
    bne TESTPASS                    ; $C770
    ldy #$09                        ; $C772
    bne SWITCHTEST_1                ; $C774

SWITCHTEST_8:
    ldx #$00                        ; $C776
    cpy #$0A                        ; $C778
    jmp TESTFAIL_2                  ; $C77A

;; Repeats the soft switch test while lsr $80 leaves a nonzero value, then clears the screen and loops:
;; with both apple keys down it reruns SELFTEST, otherwise it shows "System OK" (SYSTEMOK).
TESTPASS:
    lsr $80                         ; $C77D
    bne SWITCHTEST                  ; $C77F
    lda #' '                        ; $C781
    ldy #$00                        ; $C783

TESTPASS_1:
    sta LINE1,y                     ; $C785
    sta $0500,y                     ; $C788
    sta $0600,y                     ; $C78B
    sta $0700,y                     ; $C78E
    iny                             ; $C791
    bne TESTPASS_1                  ; $C792

TESTPASS_2:
    lda BUTN0                       ; $C794
    and BUTN1                       ; $C797
    asl a                           ; $C79A
    inc $FF                         ; $C79B
    lda $FF                         ; $C79D
    bcc SYSTEMOK                    ; $C79F
    jmp SELFTEST                    ; $C7A1

;; Shows SYSOKTEXT ("System OK") on the text page and returns to TESTPASS's key loop.
SYSTEMOK:
    lda TXTSET                      ; $C7A4
    ldy #$08                        ; $C7A7

SYSTEMOK_1:
    lda SYSOKTEXT,y                 ; $C7A9
    sta $05B8,y                     ; $C7AC
    dey                             ; $C7AF
    bpl SYSTEMOK_1                  ; $C7B0
    bmi TESTPASS_2                  ; $C7B2

;; Five pattern increments for the RAM tests; also read by a bit instruction to set V.
TESTPATTERNS:
    .byte $53, $43, $2B, $29, $07   ; $C7B4

;; Self-test soft switches ($BFFF + entry), one side of each pair; 0 ends a group.
TESTSWITCH1:
    .byte $00, $89, $31, $03, $05, $09, $0B, $01 ; $C7B9
    .byte $00, $83, $51, $53, $55, $57, $0F, $0D ; $C7C1

;; Self-test soft switches, the other side of each pair in TESTSWITCH1.
TESTSWITCH2:
    .byte $00, $81, $31, $04, $06, $0A, $0C, $02 ; $C7C9
    .byte $00, $84, $52, $54, $56, $58, $10, $0E ; $C7D1

;; Self-test status reads ($C000 + entry) matching TESTSWITCH1/TESTSWITCH2; $FF reads SPKR instead.
TESTSTATUS:
    .byte $00, $11, $FF, $13, $14, $16, $17, $18 ; $C7D9
    .byte $00, $12, $1A, $1B, $1C, $1D, $1E, $1F ; $C7E1
    .byte $00                       ; $C7E9

;; "RAM ZP", shown by TESTFAIL.
RAMZPTEXT:
    .byte "RAM ZP"                  ; $C7EA

;; "MMU", shown by TESTFAIL.
MMUTEXT:
    .byte "MMU"                     ; $C7F0

;; "IOU", shown by TESTFAIL.
IOUTEXT:
    .byte "IOU"                     ; $C7F3

;; "System OK", shown when the self-test passes.
SYSOKTEXT:
    .byte "System OK"               ; $C7F6
    .byte $00                       ; $C7FF
