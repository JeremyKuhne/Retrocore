; SYSERR, the error routines. SYSERR is how SOS code returns an error from a call; SYSDEATH stops the machine for an
; error SOS can't recover from, showing "SYSTEM FAILURE = $nn" at the bottom of the screen.
;
; Names follow Apple's SOS 1.3 listing.

ZZORG:
E_REG = $FFDF                       ;; the environment register
Z_REG = $FFD0                       ;; the zero-page register
B_REG = $FFEF                       ;; the bank register

; The offsets of SDEATH_REGS, where SYSDEATH saves the machine's state (SYSERR also keeps its dropped return address
; there).
S_SAVE = $09                        ;; the stack pointer
PCH_SAVE = $08                      ;; the return address, high byte
PCL_SAVE = $07                      ;; the return address, low byte: the last byte of the JSR
P_SAVE = $06                        ;; the status register
A_SAVE = $05                        ;; A, the error code
X_SAVE = $04                        ;; X
Y_SAVE = $03                        ;; Y
E_SAVE = $02                        ;; the environment register
Z_SAVE = $01                        ;; the zero-page register
B_SAVE = $00                        ;; the bank register

NMI_VECTOR = $FFFA                  ;; the 6502's NMI vector, in RAM
TXT_CLR = $C050                     ;; a display mode switch; clear with MIX_CLR and HIRES_CLR, it gives 40-column text
MIX_CLR = $C052                     ;; a display mode switch; MIX_CLR+1 sets it, which turns 40-column text into 80
HIRES_CLR = $C056                   ;; a display mode switch, cleared for text
PG2_CLR = $C054                     ;; selects display page 1
MSGBASE = $7E4                      ;; the message's place on the bottom line of text page 1
MSGBASE2 = $BE4                     ;; the same place in the second text page, which 80 columns also shows

;; The failure message, in plain ASCII, which the screen shows in inverse. The error code follows in hex.
MSG:
    .byte " SYSTEM FAILURE = $"

;; The length of <MSG>.
MSGLEN = * - MSG

;; Records an error code and returns from the routine that called SYSERR, with carry set for the error.
;;
;; SYSERR must be called with JSR. It drops its own return address, keeping it in SDEATH_REGS for debugging, so its
;; RTS returns to whoever called the routine that called SYSERR: an error ends that routine at once. An error code of
;; 0 returns with carry clear. X and Y are not changed.
;; In: A = the error code
;; Out: SERR = the error code, A = the same, carry = set unless it is 0
;; Uses: SDEATH_REGS+PCL_SAVE, SDEATH_REGS+PCH_SAVE
;; See: <SYSDEATH>
SYSERR:
    sta SERR
    pla
    sta SDEATH_REGS+PCL_SAVE
    pla
    sta SDEATH_REGS+PCH_SAVE
    sec
    lda SERR
    bne SERR_EXIT
    clc
SERR_EXIT:
    rts

;; Stops the machine for a fatal error, showing "SYSTEM FAILURE = $" and the error code, and never returns.
;;
;; SYSDEATH must be called with JSR. It saves the registers, the environment, zero-page and bank registers and the
;; return address in SDEATH_REGS, and copies the stack page to $1700, so the state can be examined afterwards. Then it
;; shuts down the Silentype printer port, sounds the bell, and switches to text page 1 with RAM at $F000 and the
;; Reset key unlocked: 40 columns, or 80 when the screen was showing 80-column text. It points the NMI vector at an
;; RTI so that NMIs are ignored, and loops until the user presses Control-RESET.
;; In: A = the error code
;; See: <SYSERR>, <SDEATH_REGS>
SYSDEATH:
    sta SDEATH_REGS+A_SAVE
    stx SDEATH_REGS+X_SAVE
    sty SDEATH_REGS+Y_SAVE
    php
    pla
    sta SDEATH_REGS+P_SAVE
    tsx
    stx SDEATH_REGS+S_SAVE
    lda E_REG
    sta SDEATH_REGS+E_SAVE
    lda Z_REG
    sta SDEATH_REGS+Z_SAVE
    lda B_REG
    sta SDEATH_REGS+B_SAVE
    pla
    sta SDEATH_REGS+PCL_SAVE
    pla
    sta SDEATH_REGS+PCH_SAVE
    sei
    cld
    ldx #0                          ; copy page 1, the stack, to $1700
SD005:
    lda $100,x
    sta $1700,x
    dex
    bne SD005
    lda a:$C059                     ; shut the Silentype port down
    lda a:$C0DD
    lda a:$C0DF
    lda a:$C05F
    lda a:$C05A
    lda a:$C040                     ; the bell
    lda #$74                        ; 2 MHz, I/O and screen on, primary stack, RAM at $F000 and writable
    sta E_REG
    lda TXT_CLR                     ; 40-column text, page 1
    lda MIX_CLR
    lda HIRES_CLR
    lda PG2_CLR
    lda #$02
    bit SCRNMODE
    bvs SD015                       ; graphics: keep 40 columns
    beq SD015                       ; 40-column text: keep it
    lda MIX_CLR+1                   ; 80-column text
    ldx #MSGLEN+1
    lda #$20                        ; an inverse space
SD010:
    sta MSGBASE2-1,x
    dex
    bpl SD010
SD015:
    ldx #0
SD020:
    lda MSG,x
    sta MSGBASE-1,x
    inx
    cpx #MSGLEN
    bne SD020
    lda SDEATH_REGS+A_SAVE          ; the error code as two hex digits
    clc
    lsr a
    lsr a
    lsr a
    lsr a
    jsr PRINT
    inx
    lda SDEATH_REGS+A_SAVE
    and #$0F
    jsr PRINT
    lda #<SD100
    sta NMI_VECTOR
    lda #>SD100
    sta NMI_VECTOR+1
    jmp *                           ; until Control-RESET

;; The NMI handler while the machine is stopped: it returns at once.
SD100:
    rti

;; Puts a hex digit on the screen after the failure message.
;; In: A = the digit (0-15), X = its column after MSGBASE-1
;; Uses: A
;; Keeps: X, Y
;; See: <SYSDEATH>
PRINT:
    cmp #$A
    bcs PRNT100
    adc #$30                        ; '0'-'9'
    bcc PRNT110                     ; always
PRNT100:
    adc #$36                        ; 'A'-'F', with the carry
PRNT110:
    sta MSGBASE-1,x
    rts
ZZEND:
ZZLEN = ZZEND-ZZORG
    .assert ZZLEN == LENSERR, "SOSORG gives the module another length"
