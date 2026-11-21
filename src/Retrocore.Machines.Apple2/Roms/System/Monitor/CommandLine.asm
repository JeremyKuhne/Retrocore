;; The older reset sequence, without the IIe's power-up checks: normal video, text, the screen and
;; keyboard hooks, then the Monitor.
;;
;; It is the Apple II Monitor's reset handler (RESETVEC), named RESET in its listing.
OLDRST:
    jsr SETNORM                     ; $FF59
    jsr INIT                        ; $FF5C
    jsr SETVID                      ; $FF5F
    jsr SETKBD                      ; $FF62

;; Enters the Monitor with a beep.
MON:
    cld                             ; $FF65
    jsr BELL                        ; $FF66

;; Enters the Monitor: prompts with "*", reads a command line and performs its commands.
MONZ:
    lda #'*'                        ; $FF69
    sta PROMPT                      ; $FF6B
    jsr GETLNZ                      ; $FF6D
    jsr ZMODE                       ; $FF70

;; Monitor command line: reads the next number and command character, and performs the command.
NXTITM:
    jsr GETNUM                      ; $FF73
    sty YSAV                        ; $FF76
    ldy #SUBTBL-CHRTBL              ; $FF78

CHRSRCH:
    dey                             ; $FF7A
    bmi MON                         ; $FF7B
    cmp CHRTBL,y                    ; $FF7D
    bne CHRSRCH                     ; $FF80
    jsr TOSUB                       ; $FF82
    ldy YSAV                        ; $FF85
    jmp NXTITM                      ; $FF87

;; Shifts a hex digit into A2.
DIG:
    ldx #$03                        ; $FF8A
    asl a                           ; $FF8C
    asl a                           ; $FF8D
    asl a                           ; $FF8E
    asl a                           ; $FF8F

;; Shifts A2 left one bit, taking the bit from A.
NXTBIT:
    asl a                           ; $FF90
    rol A2L                         ; $FF91
    rol A2H                         ; $FF93
    dex                             ; $FF95
    bpl NXTBIT                      ; $FF96

;; Copies A2 to A1 and A3, unless a mode (".", ":", "+", "-") is pending.
NXTBAS:
    lda MODE                        ; $FF98
    bne NXTBS2                      ; $FF9A
    lda A2H,x                       ; $FF9C
    sta A1H,x                       ; $FF9E
    sta A3H,x                       ; $FFA0

;; Continues the copy in NXTBAS.
NXTBS2:
    inx                             ; $FFA2
    beq NXTBAS                      ; $FFA3
    bne NXTCHR                      ; $FFA5

;; Reads a hex number from IN at Y into A2.
;; Out: A = the next non-digit character (encoded for CHRTBL); Y after it
GETNUM:
    ldx #$00                        ; $FFA7
    stx A2L                         ; $FFA9
    stx A2H                         ; $FFAB

;; Reads the next character of a number.
NXTCHR:
.if ENHANCED
    jsr UPMON                       ; $FFAD
    nop                             ; $FFB0
.else
    lda IN,y                        ; $FFAD
    iny                             ; $FFB0
.endif
    eor #'0'                        ; $FFB1
    cmp #$0A                        ; $FFB3
    bcc DIG                         ; $FFB5
    adc #$88                        ; $FFB7
    cmp #$FA                        ; $FFB9
.if ENHANCED
    jmp RD3_1                       ; $FFBB
.else
    bcs DIG                         ; $FFBB
    rts                             ; $FFBD
.endif

;; Performs the Monitor command at CHRTBL,Y by pushing its handler's address minus one and
;; returning to it.
;; Out: A = MODE
TOSUB:
    lda #COMMAND_PAGE               ; $FFBE
    pha                             ; $FFC0
    lda SUBTBL,y                    ; $FFC1
    pha                             ; $FFC4
    lda MODE                        ; $FFC5

;; Clears MODE.
ZMODE:
    ldy #$00                        ; $FFC7
    sty MODE                        ; $FFC9
    rts                             ; $FFCB

;; The Monitor's commands: each key and the routine that performs it.
;; CHRTBL holds the keys as GETNUM returns them, (key EOR $B0) + $89, and SUBTBL the low byte of
;; each handler's address minus one; TOSUB pushes the page, COMMAND_PAGE, and returns to it. NXTITM
;; searches from the end, so a later entry for the same key wins.
COMMAND_PAGE = $FE
.set COMMANDS, 0

.macro COMMAND key, handler
    .ident(.sprintf("COMMAND_KEY_%d", COMMANDS)) = (((key) ^ $B0) + $89) & $FF
    .ident(.sprintf("COMMAND_SUB_%d", COMMANDS)) = <(handler - 1)
    .assert >(handler - 1) = COMMAND_PAGE, "A Monitor command handler must follow the first byte of page $FE."
    .set COMMANDS, COMMANDS + 1
.endmacro

    COMMAND KEY_CTRL_C, BASCONT     ; continue BASIC
    COMMAND KEY_CTRL_Y, USR         ; the user's routine
    COMMAND KEY_CTRL_E, REGZ        ; show the registers
.if ENHANCED
    COMMAND '!', MINIASM            ; the mini-assembler
.elseif MONITOR = MONITOR_II
    COMMAND 'T', TRACE              ; trace
.else
    COMMAND KEY_CTRL_Y, TRACE       ; left from the T command; the later Control-Y entries win
.endif
    COMMAND 'V', VFY                ; verify
    COMMAND KEY_CTRL_K, INPRT       ; IN#
.if ENHANCED
    COMMAND 'S', MEMFIND            ; search
.elseif MONITOR = MONITOR_II
    COMMAND 'S', STEPZ              ; step
.elseif MONITOR = MONITOR_AUTOSTART
    COMMAND KEY_CTRL_Y, STEPZ + 1   ; left from the S command; this one wins, and runs into USR
.else
    COMMAND KEY_CTRL_Y, SLOTRTS     ; left from the S command; this one wins
.endif
    COMMAND KEY_CTRL_P, OUTPRT      ; PR#
    COMMAND KEY_CTRL_B, XBASIC      ; start BASIC
    COMMAND '-', SETMODE            ; subtract
    COMMAND '+', SETMODE            ; add
    COMMAND 'M', MOVE               ; move
    COMMAND '<', LT                 ; destination
    COMMAND 'N', SETNORM            ; normal text
    COMMAND 'I', SETINV             ; inverse text
    COMMAND 'L', LIST               ; list (disassemble)
    COMMAND 'W', WRITE              ; write to cassette
    COMMAND 'G', GO                 ; go
    COMMAND 'R', READ               ; read from cassette
    COMMAND ':', SETMODE            ; store
    COMMAND '.', SETMODE            ; range
    COMMAND KEY_CR, CRMON           ; end of the line
    COMMAND ' ', BLANK              ; separator

CHRTBL:
.repeat COMMANDS, index
    .byte .ident(.sprintf("COMMAND_KEY_%d", index))
.endrepeat

SUBTBL:
.repeat COMMANDS, index
    .byte .ident(.sprintf("COMMAND_SUB_%d", index))
.endrepeat

;; The 6502's NMI vector: $03FB.
NMIVEC:
    .word NMI                       ; $FFFA

;; The 6502's reset vector: RESET.
;;
;; The Apple II Monitor's points at OLDRST, which its listing calls RESET.
RESETVEC:
.if MONITOR = MONITOR_II
    .word OLDRST                    ; $FFFC
.else
    .word RESET                     ; $FFFC
.endif

;; The 6502's IRQ and BRK vector: IRQ on the original IIe, the internal firmware at $C3FA on the
;; Enhanced IIe.
IRQVEC:
.if ENHANCED
    .word IRQHANDLER                ; $FFFE
.else
    .word IRQ                       ; $FFFE
.endif
