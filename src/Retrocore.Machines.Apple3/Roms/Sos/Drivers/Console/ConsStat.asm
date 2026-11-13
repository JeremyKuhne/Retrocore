; ---------------------------------------------------------------------------------------------------------------------
; The status request
; ---------------------------------------------------------------------------------------------------------------------

;; The status request: returns what the status code asks for in the caller's list, through <CSTATSW>, which each
;; routine enters with Y = 0.
;; In: SCCODE = the status code, SCLIST = the list
;; Errors: XNOTOPEN, XCTLCODE (through <SYSERR>)
CNSLSTAT:
    bit a:OPENFLG
    bmi @L010
    jmp CNOTOPEN
@L010:
    SWITCH SCCODE, 18, CSTATSW, *
    bcs CBADCTL
    ldy #$00
    rts

;; Ends the request with the error for a status or control code the driver does not take.
;; Errors: XCTLCODE (through <SYSERR>)
CBADCTL:
    lda #<XCTLCODE
    jsr SYSERR

;; The status codes' routines, less one, for <SWITCH>: codes 0-18, of which 7 is an error.
CSTATSW:
    .word CSTAT00-$01
    .word CSTAT01-$01
    .word CSTAT02-$01
    .word CSTAT03-$01
    .word CSTAT04-$01
    .word CSTAT05-$01
    .word CSTAT06-$01
    .word CBADCTL-$01
    .word CSTAT08-$01
    .word CSTAT09-$01
    .word CSTAT10-$01
    .word CSTAT11-$01
    .word CSTAT12-$01
    .word CSTAT13-$01
    .word CSTAT14-$01
    .word CSTAT15-$01
    .word CSTAT16-$01
    .word CSTAT17-$01
    .word CSTAT18-$01

;; Status 0: nothing.
CSTAT00:
    rts

;; Status 1: the console state table, <CONSTTBL>. The list's first byte gives its room, which must be at least
;; <CONSTLEN>; the table's length goes there and the table after it.
;; Errors: XCTLPARM (through <SYSERR>)
CSTAT01:
    lda (SCLIST),y
    cmp #<CONSTLEN
    bcs @L010
    lda #<XCTLPARM
    jsr SYSERR
@L010:
    lda #<CONSTLEN
    sta (SCLIST),y
    tay
@L020:
    lda a:CONSTTBL-$01,y
    sta (SCLIST),y
    dey
    bne @L020
    rts

;; Status 2: the new-line flag, then the new-line character.
CSTAT02:
    lda a:NEWLINE
    sta (SCLIST),y
    iny
    lda a:NEWLNCHR
    sta (SCLIST),y
    rts

;; Status 3: the keyboard mode flag.
CSTAT03:
    lda a:KYBDMODE
    sta (SCLIST),y
    rts

;; Status 4: the type-ahead buffer's size.
CSTAT04:
    lda a:BUFSIZ
    sta (SCLIST),y
    rts

;; Status 5: how many keys are in the type-ahead buffer.
CSTAT05:
    lda a:KEYCNT
    sta (SCLIST),y
    rts

;; Status 6: the attention event, then its key.
CSTAT06:
    ldy #$05
@L010:
    lda a:ATTNEVNT,y
    sta (SCLIST),y
    dey
    bpl @L010
    rts

;; Status 8: the any-key event.
CSTAT08:
    ldy #$04
@L010:
    lda a:ANYKYEVNT,y
    sta (SCLIST),y
    dey
    bpl @L010
    rts

;; Status 9: the character under the cursor in bits 6-0, with bit 7 set when it is shown inverse, not counting the
;; cursor.
CSTAT09:
    jsr SCRNPICK
    eor #<BITON7
    eor a:SMCURSOR
    ldy #$00
    sta (SCLIST),y
    rts

;; Status 10: the no-wait flag.
CSTAT10:
    lda a:NOWAIT
    sta (SCLIST),y
    rts

;; Status 11: the echo flags.
CSTAT11:
    lda a:ECHO
    sta (SCLIST),y
    rts

;; Status 12: the character copy flag.
CSTAT12:
    lda a:CHCPYFLG
    sta (SCLIST),y
    rts

;; Status 13: the character delete flags.
CSTAT13:
    lda a:CHDELFLG
    sta (SCLIST),y
    rts

;; Status 14: the line delete flags.
CSTAT14:
    lda a:LNDELFLG
    sta (SCLIST),y
    rts

;; Status 15: the escape mode flag.
CSTAT15:
    lda a:ESCAPE
    sta (SCLIST),y
    rts

;; Status 16: the cursor's column, then its line.
CSTAT16:
    lda a:TPX
    sta (SCLIST),y
    iny
    lda a:TPY
    sta (SCLIST),y
    rts

;; Status 17: the character under the cursor, with bit 7 set for a control character, as the copy key reads it.
CSTAT17:
    jsr SCRNPICK
    asl a
    cmp #$40
    ror a
    eor #<BITON7
    ldy #$00
    sta (SCLIST),y
    rts

;; Status 18: the viewport's contents. The list gets the hardware mode, the viewport's last column and last line, then
;; the contents (<SCRNDUMP>). While control characters are being shown, it gets an empty viewport: two zeros and no
;; contents.
;; See: <CCNTL18>
CSTAT18:
    lda a:HMODE
    sta (SCLIST),y
    iny
    lda a:VPHMAX
    sta (SCLIST),y
    iny
    lda a:VPVMAX
    sta (SCLIST),y
    lda #$00
    bit a:DSPLYCTL
    bmi @L010
    jmp SCRNDUMP
@L010:
    sta (SCLIST),y
    dey
    sta (SCLIST),y
    rts
