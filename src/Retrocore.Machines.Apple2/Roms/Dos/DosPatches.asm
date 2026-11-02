;; DOS 3.3 AND 3.2: PATCHES AT THE TOP OF DOS (DOSPTCH)
;;
;; Fixes added after the rest of DOS was written, in its last bytes ($BFC8-$BFFF where DOS runs): the end of
;; the boot sequence, which resets the screen and the language card, and three short routines that existing
;; code was changed to call. ENDOFDOS, just after them, is where DOS ends: $C000 where it runs, $4000 in the
;; master image. More patches live in spare space in the boot loader's page (BootLoader.asm) and after MSWAIT
;; (MsWait.asm).
;;
;; SDP1 to EDP1 is one of the code ranges in the relocator's CDETAB, so the addresses in these instructions
;; move with DOS.
;;
;; DOS 3.2 has only the three routines, in $BFDC-$BFFF. They are inside ASC2 to AEC2, its relocator's last code
;; range, so there AEC2 is defined here and SDP1 and EDP1 are not.

;; The end of BOOT 2, reached from DOSINT once DOS is in memory: resets the hardware, then goes back to RCBACK.
;; It points output at the screen and, on a machine with a language card, writes zero to the card's RAM at
;; $E000 while leaving the ROM selected for reading. Without a card the write goes nowhere. Not in DOS 3.2.
.if DOS32 = 0
SDP1:
RCPATCH:
    jsr SETVID
    lda $C081                       ; two reads in a row: read the ROM, write the card's RAM
    lda $C081
    lda #0
    sta $E000                       ; the card's $E000 can't pass for a BASIC's first byte (see SWTST)
; Revision B (1982) also turns off the IIe's 80-column display; the original fills the space with zeros.
.if DOS33B
    jsr OFF80
    jmp RCBACK
.else
    jmp RCBACK
    .res 3,0
.endif
.endif

;; Clears TEMP1A and CB, the B parameter's value, while the command scanner resets a command's options.
;; In:    A = the value to store; its one caller passes 0
CLRBYTE:
    sta TEMP1A
    sta CB
    sta CB+1
    rts

;; Clears the input and output states, as CLRSTS does, and RSTATE too; DOS's error handler calls it.
;; Out:   Y = 0
CLRSTS1:
    jsr CLRSTS
    sty RSTATE
    rts

;; Reports DISK FULL (error 9), closing the open files first.
;;
;; It saves the current file's control block back to its buffer, returns to the stack level at which the file
;; manager was entered, closes the files, and records the stack level again, since CLALL used the file manager
;; itself. ERRORA then leaves the file manager with the error.
ERROR9X:
    jsr RTNFCB
    ldx ENTSTK
    txs
    jsr CLALL
    tsx
    stx ENTSTK
    lda #9
    jmp ERRORA

.if DOS32
;; The last byte of DOS: the end of the relocator's last code range, which leaves it out.
AEC2 = *-1
.else
;; The last byte of the patches: the end of the relocator's last code range.
EDP1 = *-1
.endif

;; The address just after DOS: $C000 where DOS runs.
ENDOFDOS:
