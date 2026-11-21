;; Reads a key through the input hook, KSWL, with a cursor shown.
;; Out: A = key with the high bit set
;; Original IIe: shows the cursor by flashing the character under it. Enhanced IIe: the internal
;; firmware (function $0B) shows the cursor for 40 or 80 columns.
RDKEY:
.if ENHANCED
    ldy #$0B                        ; $FD0C
    bne RDKEY_1                     ; $FD0E
    jmp RDKEYHOOK                   ; $FD10 not reached from here
.else
    ldy CH                          ; $FD0C
    lda (BASL),y                    ; $FD0E
    pha                             ; $FD10
    and #$3F                        ; $FD11
.endif

RDKEY_1:
.if ENHANCED
    jsr GOTOCX                      ; $FD13
    nop                             ; $FD16
    nop                             ; $FD17
.else
    ora #$40                        ; $FD13
    sta (BASL),y                    ; $FD15
    pla                             ; $FD17
.endif

RDKEYHOOK:
    jmp (KSWL)                      ; $FD18

;; The keyboard's input routine (KSWL's default): the internal firmware waits for a key, then clears
;; the strobe.
;;
;; The Apple II's Monitors wait here themselves, counting up RNDL/RNDH while they wait. When a key
;; comes, they put back the character that RDKEY replaced with the flashing cursor (A at the cursor,
;; CH in Y), then read the key and clear the strobe.
;; Out: A = key with the high bit set
KEYIN:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    ldy #$03                        ; $FD1B
.else
    ldy #$06                        ; $FD1B
.endif

KEYIN_1:
    jmp GOTOCX                      ; $FD1D
    .byte $EA                       ; $FD20

;; Reads a key, then lets the internal firmware handle it as an escape-mode key.
RDESC:
    jsr RDKEY                       ; $FD21
.if ENHANCED
    ldy #$01                        ; $FD24
    bne KEYIN_1                     ; $FD26

RDESC_1:
    lsr MSLOT                       ; $FD28
    jmp RDKEY                       ; $FD2B
    .byte $EA                       ; $FD2E
.else
    ldy #$07                        ; $FD24
    jmp GOTOCX                      ; $FD26

;; Original IIe: switches slot ROM back in and returns with the saved status (the internal firmware's
;; way back).
SLOTRTN:
    sta SETSLOTCXROM                ; $FD29

SLOTRTN_1:
    plp                             ; $FD2C
    rts                             ; $FD2D
    .byte $60                       ; $FD2E
.endif
.else
    inc RNDL                        ; $FD1B
    bne KEYIN2                      ; $FD1D
    inc RNDH                        ; $FD1F

KEYIN2:
    bit KBD                         ; $FD21
    bpl KEYIN                       ; $FD24
    sta (BASL),y                    ; $FD26
    lda KBD                         ; $FD28
    bit KBDSTRB                     ; $FD2B
    rts                             ; $FD2E
.endif

;; Escape mode: handles ESC commands until a non-command key, then reads the next character.
;;
;; The Apple II's Monitors read the key with RDKEY. The Apple II Monitor performs one command (ESC1)
;; and leaves escape mode.
ESC:
.if MONITOR = MONITOR_IIE
    jsr RDESC                       ; $FD2F
.else
    jsr RDKEY                       ; $FD2F
.endif
.if MONITOR = MONITOR_II
    jsr ESC1                        ; $FD32
.else
    jsr ESCNEW                      ; $FD32
.endif

;; Reads a character, handling ESC sequences (cursor movement) instead of returning them.
;; Out: A = character
RDCHAR:
.if ENHANCED
    jsr RDESC_1                     ; $FD35
.else
    jsr RDKEY                       ; $FD35
.endif
    cmp #KEY_ESC                    ; $FD38
    beq ESC                         ; $FD3A
    rts                             ; $FD3C
