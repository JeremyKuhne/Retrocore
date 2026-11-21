.if MONITOR = MONITOR_II

;; Apple II Monitor: multiplies two signed 16-bit numbers, AUXL/AUXH times ACL/ACH.
;;
;; Apple II Monitor only. It makes both numbers positive (<MD1>), which leaves the product's sign in
;; bit 0 of <SIGN> for the caller to apply, then multiplies them (<MUL>).
;; In: ACL/ACH = a number, AUXL/AUXH = the other, XTNDL/XTNDH = a number added to the product (usually 0)
;; Out: ACL/ACH = the product's low 16 bits, XTNDL/XTNDH = its high 16 bits,
;;   SIGN = bit 0 set for a negative product
;; Uses: A, X, Y
;; See: <DIVPM>
MULPM:
    jsr MD1                         ; $FB60

;; Apple II Monitor: multiplies two unsigned 16-bit numbers, AUXL/AUXH times ACL/ACH, and adds
;; XTNDL/XTNDH.
;;
;; Each of its 16 passes adds AUXL/AUXH to XTNDL/XTNDH when bit 0 of ACL is set, then shifts the 32 bits
;; of XTNDH, XTNDL, ACH and ACL right one, the add's carry coming in at the top.
;; In: ACL/ACH = a number, AUXL/AUXH = the other, XTNDL/XTNDH = a number added to the product (usually 0)
;; Out: ACL/ACH = the product's low 16 bits, XTNDL/XTNDH = its high 16 bits, X = $FF, Y = 0
;; Uses: A
MUL:
    ldy #$10                        ; $FB63 16 passes

MUL2:
    lda ACL                         ; $FB65
    lsr a                           ; $FB67
    bcc MUL4                        ; $FB68
    clc                             ; $FB6A
    ldx #$FE                        ; $FB6B X = $FE, $FF: the low byte, then the high byte

MUL3:
    lda XTNDL+2,x                   ; $FB6D
    adc AUXL+2,x                    ; $FB6F
    sta XTNDL+2,x                   ; $FB71
    inx                             ; $FB73
    bne MUL3                        ; $FB74

MUL4:
    ldx #$03                        ; $FB76

MUL5:
    ror ACL,x                       ; $FB78 XTNDH, XTNDL, ACH, ACL
    dex                             ; $FB7A
    bpl MUL5                        ; $FB7B
    dey                             ; $FB7D
    bne MUL2                        ; $FB7E
    rts                             ; $FB80

;; Apple II Monitor: divides two signed 16-bit numbers, ACL/ACH by AUXL/AUXH.
;;
;; Apple II Monitor only. It makes both numbers positive (<MD1>), which leaves the quotient's sign in
;; bit 0 of <SIGN> for the caller to apply, then divides them (<DIV>).
;; In: ACL/ACH = the dividend, AUXL/AUXH = the divisor, XTNDL/XTNDH = 0
;; Out: ACL/ACH = the quotient, XTNDL/XTNDH = the remainder, SIGN = bit 0 set for a negative quotient
;; Uses: A, X, Y
;; See: <MULPM>
DIVPM:
    jsr MD1                         ; $FB81

;; Apple II Monitor: divides the unsigned 32-bit number in XTNDL/XTNDH (high) and ACL/ACH (low) by
;; AUXL/AUXH.
;;
;; Each of its 16 passes shifts the 32 bits left one and, when the top half is at least AUXL/AUXH,
;; subtracts it there and sets the quotient bit at the bottom of ACL. The quotient fits in 16 bits when
;; XTNDL/XTNDH starts below AUXL/AUXH, as it does with XTNDL/XTNDH = 0.
;; In: ACL/ACH = the dividend's low half, XTNDL/XTNDH = its high half (usually 0), AUXL/AUXH = the divisor
;; Out: ACL/ACH = the quotient, XTNDL/XTNDH = the remainder, Y = 0
;; Uses: A, X
DIV:
    ldy #$10                        ; $FB84 16 passes

DIV2:
    asl ACL                         ; $FB86
    rol ACH                         ; $FB88
    rol XTNDL                       ; $FB8A
    rol XTNDH                       ; $FB8C
    sec                             ; $FB8E
    lda XTNDL                       ; $FB8F
    sbc AUXL                        ; $FB91
    tax                             ; $FB93
    lda XTNDH                       ; $FB94
    sbc AUXH                        ; $FB96
    bcc DIV3                        ; $FB98 too small: the quotient bit stays 0
    stx XTNDL                       ; $FB9A
    sta XTNDH                       ; $FB9C
    inc ACL                         ; $FB9E

DIV3:
    dey                             ; $FBA0
    bne DIV2                        ; $FBA1
    rts                             ; $FBA3

;; Apple II Monitor: makes AUXL/AUXH and ACL/ACH positive for <MULPM> and <DIVPM>, counting the
;; numbers it negates in <SIGN>.
;;
;; MD2 negates the 16-bit number at page zero X when it is negative, and MD3 negates it whatever its
;; sign; both need Y = 0. Bit 0 of SIGN ends set when exactly one number was negative.
;; Out: SIGN = the count of negated numbers, Y = 0
;; Uses: A, X
;; Entry: MD2 = with X the number's address, MD3 = with X the number's address and the carry set
MD1:
    ldy #$00                        ; $FBA4
    sty SIGN                        ; $FBA6
    ldx #AUXL                       ; $FBA8
    jsr MD2                         ; $FBAA
    ldx #ACL                        ; $FBAD

MD2:
    lda LOC1,x                      ; $FBAF the high byte
    bpl MDRTS                       ; $FBB1
    sec                             ; $FBB3 the byte the IIe's VERSION reads here, $38

MD3:
    tya                             ; $FBB4 0 minus the number
    sbc LOC0,x                      ; $FBB5
    sta LOC0,x                      ; $FBB7
    tya                             ; $FBB9
    sbc LOC1,x                      ; $FBBA
    sta LOC1,x                      ; $FBBC
    inc SIGN                        ; $FBBE

MDRTS:
    rts                             ; $FBC0
.else

;; Clears the screen and shows the model's title at the top center: "Apple ][" on the original IIe,
;; "Apple //e" on the Enhanced IIe.
;;
;; The Autostart Monitor's PWRUP shows "APPLE ][" this way. The Apple II Monitor has no title.
APPLEII:
    jsr HOME                        ; $FB60
.if ENHANCED
    ldy #$09                        ; $FB63
.else
    ldy #$08                        ; $FB63
.endif

STITLE:
.if ENHANCED
    lda TITLE2E-1,y                 ; $FB65
.else
    lda TITLE-1,y                   ; $FB65
.endif
    sta $040E,y                     ; $FB68
    dey                             ; $FB6B
    bne STITLE                      ; $FB6C
    rts                             ; $FB6E

;; Makes the reset vector valid: PWREDUP = SOFTEV's high byte EOR $A5. Call after changing SOFTEV.
SETPWRC:
    lda SOFTEV+1                    ; $FB6F
    eor #$A5                        ; $FB72
    sta PWREDUP                     ; $FB74
    rts                             ; $FB77

;; Screen output with pause: when A is a carriage return and the user has typed Control-S, waits
;; for another key before printing (KBDWAIT). Then prints A (VIDOUT).
;; In: A = character
VIDWAIT:
    cmp #KEY_CR                     ; $FB78
    bne NOWAIT                      ; $FB7A
    ldy KBD                         ; $FB7C
    bpl NOWAIT                      ; $FB7F
    cpy #KEY_CTRL_S                 ; $FB81
    bne NOWAIT                      ; $FB83
    bit KBDSTRB                     ; $FB85

;; Waits for a key and clears the strobe, except for Control-C, which stays in the keyboard latch
;; for the program to see. Then prints A (VIDOUT).
KBDWAIT:
    ldy KBD                         ; $FB88
    bpl KBDWAIT                     ; $FB8B
    cpy #KEY_CTRL_C                 ; $FB8D
    beq NOWAIT                      ; $FB8F
    bit KBDSTRB                     ; $FB91

NOWAIT:
    jmp VIDOUT                      ; $FB94

;; Escape-mode cursor command: handles the character in A as an ESC command (ESC1) with carry set.
ESCOLD:
    sec                             ; $FB97
    jmp ESC1                        ; $FB98

;; Escape mode: shows the escape cursor, reads a key and handles cursor-moving keys until another
;; key ends escape mode.
;;
;; The Autostart Monitor reads the next key with RDKEY, without an escape cursor of its own. The Apple
;; II Monitor has no escape keys I, J, K and M: its <ESC> hands every key to ESC1.
ESCNOW:
    tay                             ; $FB9B
    lda XLTBL-'I',y                 ; $FB9C
    jsr ESCOLD                      ; $FB9F
.if MONITOR = MONITOR_IIE
    jsr RDESC                       ; $FBA2
.else
    jsr RDKEY                       ; $FBA2
.endif

ESCNEW:
    cmp #'N'                        ; $FBA5
    bcs ESCOLD                      ; $FBA7
    cmp #'I'                        ; $FBA9
    bcc ESCOLD                      ; $FBAB
    cmp #'L'                        ; $FBAD
    beq ESCOLD                      ; $FBAF
    bne ESCNOW                      ; $FBB1

;; The model identification byte: $06 means an Apple IIe (with $FBC0, below).
;;
;; Programs read the same address on the Apple II: the Autostart Monitor has $EA here, followed by
;; unused $EA bytes up to $FBC0, and the Apple II Monitor $38, a SEC in its MD2.
VERSION:
.if MONITOR = MONITOR_AUTOSTART
    .byte $EA                       ; $FBB3
    .res 13, $EA                    ; $FBB4 unused
.else
    .byte $06                       ; $FBB3

;; Calls the internal firmware: saves whether slot ROM or internal ROM was selected at $C100-$CFFF,
;; switches internal ROM in and jumps to the firmware's dispatcher at $C100, which performs the
;; function in Y and switches back.
;; In: Y = function number; other registers as the function needs
;; The original IIe also saves the interrupt state and disables interrupts first.
GOTOCX:
.if .not ENHANCED
    php                             ; $FBB4
    sei                             ; $FBB5
.endif
    bit RDCXROM                     ; $FBB4 original $FBB6
    php                             ; $FBB7 original $FBB9
    sta SETINTCXROM                 ; $FBB8 original $FBBA
.if ENHANCED
    jmp $C100                       ; $FBBB
    .byte $00, $00, $E0             ; $FBBE $FBC0 = $E0 identifies the Enhanced IIe
.else
    jmp B_FUNC                      ; $FBBD
    .byte $EA                       ; $FBC0 identifies the original IIe ($EA)
.endif
.endif
.endif
