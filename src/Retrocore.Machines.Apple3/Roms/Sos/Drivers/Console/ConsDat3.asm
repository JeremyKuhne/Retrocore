; ---------------------------------------------------------------------------------------------------------------------
; The console state table, which status and control code 1 read and write whole
; ---------------------------------------------------------------------------------------------------------------------

;; The console state table: the events, the console's modes and switches, the screen's state and its saved copy.
;; Status and control code 1 read and write it whole, <CONSTLEN> bytes; each part also has its own code.
;;
;; A flag here is on when bit 7 is set. For the editing switches, bit 6 says more: with <ECHO> it echoes control
;; characters too, and with <CHDELFLG> and <LNDELFLG> it erases the deleted characters from the screen.
;; See: <CSTAT01>, <CCNTL01>
CONSTTBL:
;; The any-key event: its priority, zero while it is not armed, its identifier, and its handler's address and bank.
;; The first key typed while no read is waiting queues it and disarms it; the type-ahead buffer is emptied, then the
;; key goes in.
;; See: <KIHCKEV>, <CSTAT08>, <CCNTL08>
ANYKYEVNT:
    .res $05
;; The attention event, in the same form, queued by the key in <ATTNCHAR>. It also ends a read in progress and
;; empties the type-ahead buffer.
;; See: <KIHCKEV>, <CSTAT06>, <CCNTL06>
ATTNEVNT:
    .res $05
ATTNCHAR:
    .byte $00                       ; the attention event's key
;; The modes and switches that control code 0 resets from <DFLTVAL>.
DFLTTBL:
KYBDMODE:
    .byte $00                       ; keyboard mode: reads return two bytes per key, unedited
NEWLINE:
    .byte $00                       ; a read ends at the new-line character
NEWLNCHR:
    .byte $00                       ; the new-line character
NOWAIT:
    .byte $00                       ; a read returns what is buffered rather than waiting for keys
ECHO:
    .byte $00                       ; reads show what is typed (bit 6: control characters too)
CHCPYFLG:
    .byte $00                       ; the right arrow copies the character under the cursor
CHCPYCHR = ASC_NAK                  ;; the key that copies a character from the screen: the right arrow
CHDELFLG:
    .byte $00                       ; Control-H deletes a character (bit 6: erasing it)
CHDELCHR = ASC_BS                   ;; the key that deletes a character: Control-H, the left arrow
LNDELFLG:
    .byte $00                       ; Control-X deletes the line (bit 6: erasing it)
LNDELCHR = ASC_CAN                  ;; the key that deletes the line: Control-X
ESCAPE:
    .byte $00                       ; Escape starts escape mode (bit 6: in escape mode)
;; The screen's state: the hardware and software modes, the cursor position, the viewport and the text colors.
;; <VERIFY> checks it and derives the driver's own copies.
;; See: <CF_SOH>, <CF_EOT>
SCRSTTBL:
HMODE:
    .byte $00                       ; bit 1 set for 80 columns, bit 0 for color; VERIFY adds bit 7 for 80 columns
SMODE:
    .byte $00                       ; inverse, cursor, scroll, return, line feed, advance: bits 5-0, see SMFLAGS
TPX:
    .byte $00                       ; the cursor's column in the viewport
TPY:
    .byte $00                       ; the cursor's line in the viewport
VPL:
    .byte $00                       ; the viewport's left column on the screen
VPR:
    .byte 79                        ; its right column
VPT:
    .byte $00                       ; its top line
VPB:
    .byte 23                        ; its bottom line
TCF:
    .byte $0F                       ; the text color, for 40 columns
TCB:
    .byte $00                       ; the background color, for 40 columns
SCRSTLEN = *-SCRSTTBL               ;; the screen state's length
DFLTLEN = *-DFLTTBL                 ;; the length of the part control code 0 resets
;; The screen state saved by control code $01 and brought back by $04.
SCRSTSAV:
    .res SCRSTLEN
CONSTLEN = *-CONSTTBL               ;; the console state table's length

;; The values control code 0 gives <DFLTTBL>: console mode; reads that do not end at a new-line character (Return,
;; when turned on) and that wait for keys; echo without control characters; character copy; character and line
;; delete, without erasing; escape mode; 80 columns with scrolling, wrapping and automatic advance but no cursor; the
;; whole screen as the viewport; and white text on black for 40 columns.
DFLTVAL:
    .byte FALSE
    .byte FALSE
    .byte ASC_CR
    .byte FALSE
    .byte TRUE
    .byte TRUE
    .byte TRUE
    .byte TRUE
    .byte TRUE
    .byte $02
    .byte $0D
    .byte 0
    .byte 0
    .byte 0
    .byte 79
    .byte 0
    .byte 23
    .byte $0F
    .byte $00

; ---------------------------------------------------------------------------------------------------------------------
; The driver's own variables
; ---------------------------------------------------------------------------------------------------------------------

KYBDBUFS = $1500                    ;; the type-ahead buffers: KABUF, then KBBUF
KABUF = KYBDBUFS                    ;; the buffered keys' characters
KBBUF = KYBDBUFS+BUFMAX             ;; the buffered keys' modifier bytes
;; The keyboard layout table, which SOS.DRIVER supplies. Its last 64 bytes turn the keyboard's character into a key
;; number, a multiple of 4; the entry at that number plus 1 for Shift and 2 for Control is the character typed. An
;; entry with bit 7 set is one that Alpha Lock replaces with the shifted entry.
;; See: <KIHXFORM>
XFORMTBL = $1700
KADATA:
    .byte $00                       ; the key being handled: its character
KBDATA:
    .byte $00                       ; and its modifier byte
KEYCNT:
    .byte $00                       ; how many keys are in the type-ahead buffer
BUFSIZ:
    .byte $00                       ; the buffer's size; 0 turns buffering off
BUFHEAD:
    .byte $00                       ; where the oldest key is
BUFTAIL:
    .byte $00                       ; where the next key goes
OPENFLG:
    .byte $00                       ; the console is open
READING:
    .byte $00                       ; a read is waiting for keys; the attention key clears it
DSPLYCTL:
    .byte $00                       ; bit 7 set to show control characters rather than carry them out
;; The software mode's flags, one byte each with the flag in bit 7, which <VERIFY> sets from <SMODE>.
SMFLAGS:
SMINV:
    .byte $00                       ; inverse: $80 clears bit 7 of each character, which shows it inverse
SMCURSOR:
    .byte $00                       ; the cursor is shown
SMSCROLL:
    .byte $00                       ; a line feed at the bottom scrolls
SMAUTOCR:
    .byte $00                       ; the cursor wraps at the viewport's edges
SMAUTOLF:
    .byte $00                       ; a return also moves down a line
SMAUTOADV:
    .byte $00                       ; the cursor advances after each character
VPHMAX:
    .byte 79                        ; the viewport's last column, counting from 0
VPVMAX:
    .byte 23                        ; the viewport's last line
TCOLOR:
    .byte $F0                       ; the color byte for 40 columns: text color times 16, plus the background
CTLINDX:
    .byte $00                       ; how many bytes of a control code are in CTLBUFF
CTLBUFF:
    .res $08                        ; the control code being collected, then its parameters
CTLQUOTA:
    .byte $00                       ; how many bytes the control code takes
DNLDFLG:
    .byte $00                       ; downloading: bit 7 while active, bit 6 while more of a set is to come
DNLDCEL:
    .byte $00                       ; the download cell being loaded, 0-7
DNLDCHR:
    .byte $00                       ; the character code being loaded
DNLDIMG:
    .word $00                       ; the next character image of a whole set

; ---------------------------------------------------------------------------------------------------------------------
; Addresses for calls, and the interrupt resources the driver claims
; ---------------------------------------------------------------------------------------------------------------------

ANYKYPARM:
    .word ANYKYEVNT                 ; for QUEEVENT
ATTNPARM:
    .word ATTNEVNT                  ; for QUEEVENT
KYBDSADR:
    .word KYBDSTBL                  ; for ALLOCSIR and DEALCSIR
;; The keyboard's interrupt resource: SIR 2, handled by <KYBDMIH> in the driver's bank.
KYBDSTBL:
    .byte $02, $00
    .word KYBDMIH
KYBDBANK:
    .byte $00
KYBDSSIZ = *-KYBDSTBL               ;; the request's length
DNLDSADR:
    .word DNLDSTBL                  ; for ALLOCSIR and DEALCSIR
;; The resources a character download needs: SIR 5 and SIR 6, the two vertical-blanking edges, with SIR 6 handled by
;; <DNLDINT>, and SIR 16, character downloading.
DNLDSTBL:
    .byte $05, $00, $00, $00, $00
    .byte $06, $00
    .word DNLDINT
DNLDBANK:
    .byte $00
    .byte $10, $00, $00, $00, $00
DNLDSSIZ = *-DNLDSTBL               ;; the request's length
SYNCSADR:
    .word SYNCSTBL                  ; for ALLOCSIR and DEALCSIR
;; The resource control code $16 waits on: SIR 5, the rising edge of vertical blanking.
SYNCSTBL:
    .byte $05, $00, $00, $00, $00
SYNCSSIZ = *-SYNCSTBL               ;; the request's length

; ---------------------------------------------------------------------------------------------------------------------
; Tables
; ---------------------------------------------------------------------------------------------------------------------

;; The low byte of each screen line's address, for lines 0-23.
;; See: <BASH>, <TBASCAL>
BASL:
    .byte $00, $80, $00, $80
    .byte $00, $80, $00, $80
    .byte $28, $A8, $28, $A8
    .byte $28, $A8, $28, $A8
    .byte $50, $D0, $50, $D0
    .byte $50, $D0, $50, $D0
;; The high byte of each screen line's address in the first text page, $0400-$07FF; the same line's address in the
;; second page, $0800-$0BFF, has bits 2 and 3 flipped.
;; See: <BASL>
BASH:
    .byte $04, $04, $05, $05
    .byte $06, $06, $07, $07
    .byte $04, $04, $05, $05
    .byte $06, $06, $07, $07
    .byte $04, $04, $05, $05
    .byte $06, $06, $07, $07
;; The keys escape mode takes, in the order of the control codes they stand for in <ESCOP>.
ESCCMD:
    .byte 'B'                       ; the viewport's bottom right corner here
    .byte 'T'                       ; the viewport's top left corner here
    .byte 'V'                       ; the whole screen as the viewport
    .byte 'S'                       ; clear the viewport
    .byte 'P'                       ; clear to the end of the viewport
    .byte 'L'                       ; clear to the end of the line
    .byte 'H'                       ; the cursor to the top left
    .byte ASC_BS                    ; left
    .byte ASC_NAK                   ; right
    .byte ASC_VT                    ; up
    .byte ASC_LF                    ; down
ECMDCNT = *-ESCCMD                  ;; how many keys escape mode takes
;; The control code each key in <ESCCMD> writes.
ESCOP:
    .byte ASC_ETX
    .byte ASC_STX
    .byte ASC_SOH
    .byte ASC_FS
    .byte ASC_GS
    .byte ASC_US
    .byte ASC_FF
    .byte ASC_BS
    .byte ASC_HT
    .byte ASC_VT
    .byte ASC_LF
