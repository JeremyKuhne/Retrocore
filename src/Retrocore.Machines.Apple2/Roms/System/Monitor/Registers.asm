;; Prints a carriage return, then the registers saved by SAVE as "A=xx X=xx Y=xx P=xx S=xx".
;;
;; In the Apple II Monitor, <RTNJMP> falls into it at the end of <STEP>.
REGDSP:
    jsr CROUT                       ; $FAD7

RGDSP1:
    lda #<A5H                       ; $FADA
    sta A3L                         ; $FADC
    lda #>A5H                       ; $FADE
    sta A3H                         ; $FAE0
    ldx #$FB                        ; $FAE2 X runs $FB-$FF over the five registers

RDSP1:
    lda #' '                        ; $FAE4
    jsr COUT                        ; $FAE6
    lda RTBL-$FB,x                  ; $FAE9
    jsr COUT                        ; $FAEC
    lda #'='                        ; $FAEF
    jsr COUT                        ; $FAF1
    lda A5H+5,x                     ; $FAF4 wraps in page zero: A5H, XREG, YREG, STATUS, SPNT
    jsr PRBYTE                      ; $FAF6
    inx                             ; $FAF9
    bmi RDSP1                       ; $FAFA
    rts                             ; $FAFC
.if MONITOR = MONITOR_II

;; Apple II Monitor: the end of a taken branch run by <STEP>: moves PCL/PCH to the branch's target.
;;
;; The copied branch lands on the jump to here in <XQT> when it is taken. The target is PCL/PCH plus
;; the real displacement plus 2, the branch's length.
BRANCH:
    clc                             ; $FAFD
    ldy #$01                        ; $FAFE
    lda (PCL),y                     ; $FB00 the displacement
    jsr PCADJ3                      ; $FB02
    sta PCL                         ; $FB05
    tya                             ; $FB07
    sec                             ; $FB08 PCINC3 adds LENGTH + 1
    bcs PCINC2                      ; $FB09

;; Apple II Monitor: the end of an instruction run by <STEP> that did not branch: saves the registers
;; and moves PCL/PCH past the instruction (<PCINC3>).
NBRNCH:
    jsr SAVE                        ; $FB0B
    sec                             ; $FB0E
    bcs PCINC3                      ; $FB0F

;; Apple II Monitor: what <STEP> puts after the instruction it copies to <XQT>: two NOPs, then a jump
;; to <NBRNCH> for an instruction that falls through and one to <BRANCH> for a taken branch.
;;
;; The instruction overwrites as many of the NOPs as it has operand bytes.
INITBL:
    nop                             ; $FB11
    nop                             ; $FB12
    jmp NBRNCH                      ; $FB13
    jmp BRANCH                      ; $FB16
.else

;; Power-up defaults for $03F0-$03F4: BRKV = OLDBRK, SOFTEV = BASIC ($E000), PWREDUP = $45.
PWRCON:
    .word OLDBRK                    ; $FAFD BRKV
    .word BASIC                     ; $FAFF SOFTEV
    .byte >BASIC ^ $A5              ; $FB01 PWREDUP

;; The disk controller signature PWRUP compares at $Cn01, $Cn03, $Cn05 (and $Cn07 on the original IIe):
;; every other byte. The $FF bytes between are never compared.
;;
;; The Autostart Monitor compares four bytes, as the original IIe does.
DISKID:
    .byte $20, $FF, $00, $FF, $03, $FF, $3C ; $FB02

;; The original IIe's title, "Apple ][", copied by APPLEII.
;;
;; The Autostart Monitor's is in capitals, "APPLE ][".
TITLE:
.if MONITOR = MONITOR_IIE
    .byte "Apple ]["                ; $FB09
.else
    .byte "APPLE ]["                ; $FB09
.endif

;; ESCNOW's translation of the escape-mode keys I, J, K and M to the cursor commands D (up), B (left),
;; A (right) and C (down). L and the bytes after it are not used.
XLTBL:
    .byte "DBA", $FF, "C", $FF, $FF, $FF ; $FB11
.endif

;; Register names for REGDSP: "AXYPS", in reverse order of display.
;;
;; Apple's listing of the Apple II Monitor gives the table no name.
RTBL:
    .byte "AXYPS"                   ; $FB19

;; Reads a game paddle.
;; In: X = paddle (0-3)
;; Out: Y = position (0-255, the time the paddle's timer ran).
;; Uses: A
PREAD:
    lda PTRIG                       ; $FB1E
    ldy #$00                        ; $FB21
    nop                             ; $FB23
    nop                             ; $FB24

PREAD2:
    lda PADDL0,x                    ; $FB25
    bpl RTS2D                       ; $FB28
    iny                             ; $FB2A
    bne PREAD2                      ; $FB2B
    dey                             ; $FB2D

RTS2D:
    rts                             ; $FB2E
