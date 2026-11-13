; ---------------------------------------------------------------------------------------------------------------------
; The control request
; ---------------------------------------------------------------------------------------------------------------------

;; The control request: carries out the control code with the caller's list, through <CCNTLSW>, which each routine
;; enters with Y = 0 and A = the list's first byte.
;; In: SCCODE = the control code, SCLIST = the list
;; Errors: XNOTOPEN, XCTLCODE (through <SYSERR>)
CNSLCNTL:
    bit a:OPENFLG
    bpl @L010
    SWITCH SCCODE, 18, CCNTLSW, *
    bcs @L020
    ldy #$00
    lda (SCLIST),y
    rts
@L010:
    jmp CNOTOPEN
@L020:
    jmp CBADCTL

;; The control codes' routines, less one, for <SWITCH>: codes 0-18, of which 7 and 9 are errors.
CCNTLSW:
    .word CCNTL00-$01
    .word CCNTL01-$01
    .word CCNTL02-$01
    .word CCNTL03-$01
    .word CCNTL04-$01
    .word CCNTL05-$01
    .word CCNTL06-$01
    .word CBADCTL-$01
    .word CCNTL08-$01
    .word CBADCTL-$01
    .word CCNTL10-$01
    .word CCNTL11-$01
    .word CCNTL12-$01
    .word CCNTL13-$01
    .word CCNTL14-$01
    .word CCNTL15-$01
    .word LOADSET-$01
    .word LOAD8-$01
    .word CCNTL18-$01

;; Control 0: resets the console. The type-ahead buffer becomes its full size and empty; the events are disarmed; any
;; read, control code, suspend or flush ends; control characters are carried out again; <DFLTTBL> gets its defaults; and
;; the screen state is checked and saved, with the whole screen as the viewport. The keyboard interrupt stays masked or
;; unmasked as it was.
;; Uses: A, X, Y
CCNTL00:
    lda E_IER
    pha
    lda #<KYBDDSBL
    sta E_IER
    lda #<BUFMAX
    sta a:BUFSIZ
    lda #$00
    sta a:KEYCNT
    sta a:BUFHEAD
    sta a:BUFTAIL
    sta a:READING
    sta a:ANYKYEVNT
    sta a:ATTNEVNT
    sta a:CTLINDX
    sta a:DSPLYCTL
    sta SUSPFLSH
    jsr CURSOR
    ldx #<DFLTLEN
@L010:
    lda a:DFLTVAL-$01,x
    sta a:DFLTTBL-$01,x
    dex
    bne @L010
    jsr CF_SOH
    jsr CURSOR
    jsr ZPOUT
    pla
    and #<KYBDENBL
    ora #<BITON7
    sta E_IER
    rts

;; Control 1: sets the console state table from the list, whose first byte must be <CONSTLEN>, and puts the screen state
;; into effect.
;; Errors: XCTLPARM (through <SYSERR>)
CCNTL01:
    cmp #<CONSTLEN
    beq @L010
    lda #<XCTLPARM
    jsr SYSERR
@L010:
    jsr CURSOR
    ldy #<CONSTLEN
@L020:
    lda (SCLIST),y
    dey
    sta a:CONSTTBL,y
    bne @L020
    jsr VERIFY
    jsr CURSOR
    jsr ZPOUT
    rts

;; Control 2: sets the new-line flag from the list's first byte and the new-line character from its second.
CCNTL02:
    and #<BITON7
    sta a:NEWLINE
    iny
    lda (SCLIST),y
    sta a:NEWLNCHR
    rts

;; Control 3: sets the keyboard mode flag.
CCNTL03:
    and #<BITON7
    sta a:KYBDMODE
    rts

;; Control 4: sets the type-ahead buffer's size, 0 to <BUFMAX>, and empties it; 0 turns buffering off.
;; Errors: XCTLPARM (through <SYSERR>)
CCNTL04:
    cmp #<(BUFMAX+$01)
    bcc @L010
    lda #<XCTLPARM
    jsr SYSERR
@L010:
    ldx #<KYBDDSBL
    stx E_IER
    sty a:KEYCNT
    sty a:BUFHEAD
    sty a:BUFTAIL
    sta a:BUFSIZ
    ldx #<KYBDENBL
    stx E_IER
    rts

;; Control 5: empties the type-ahead buffer.
CCNTL05:
    lda E_IER
    pha
    lda #<KYBDDSBL
    sta E_IER
    sty a:KEYCNT
    sty a:BUFHEAD
    sty a:BUFTAIL
    pla
    and #<KYBDENBL
    ora #<BITON7
    sta E_IER
    rts

;; Control 6: sets the attention event and its key from the list's six bytes.
CCNTL06:
    php
    sei
    ldy #$05
@L010:
    lda (SCLIST),y
    sta a:ATTNEVNT,y
    dey
    bpl @L010
    plp
    rts

;; Control 8: sets the any-key event from the list's five bytes.
CCNTL08:
    php
    sei
    ldy #$04
@L010:
    lda (SCLIST),y
    sta a:ANYKYEVNT,y
    dey
    bpl @L010
    plp
    rts

;; Control 10: sets the no-wait flag.
CCNTL10:
    and #<BITON7
    sta a:NOWAIT
    rts

;; Control 11: sets the echo flags.
CCNTL11:
    and #<(BITON7+BITON6)
    sta a:ECHO
    rts

;; Control 12: sets the character copy flag.
CCNTL12:
    and #<BITON7
    sta a:CHCPYFLG
    rts

;; Control 13: sets the character delete flags.
CCNTL13:
    and #<(BITON7+BITON6)
    sta a:CHDELFLG
    rts

;; Control 14: sets the line delete flags.
CCNTL14:
    and #<(BITON7+BITON6)
    sta a:LNDELFLG
    rts

;; Control 15: sets the escape mode flag.
CCNTL15:
    and #<BITON7
    sta a:ESCAPE
    rts

;; Control 18: restores the viewport's contents from a list that status 18 filled. The list's hardware mode and viewport
;; size must match the screen's. An empty viewport's list does nothing, and nothing is restored while control characters
;; are being shown.
;; Errors: XCTLPARM (through <SYSERR>)
;; See: <CSTAT18>
CCNTL18:
    bit a:DSPLYCTL
    bmi @L020
    iny
    eor a:HMODE
    bmi @L010
    lda (SCLIST),y
    cmp a:VPHMAX
    bne @L010
    iny
    lda (SCLIST),y
    cmp a:VPVMAX
    bne @L030
    lda #$80
    jmp SCRNDUMP
@L010:
    lda (SCLIST),y
    iny
    ora (SCLIST),y
    bne @L030
@L020:
    rts
@L030:
    lda #<XCTLPARM
    jsr SYSERR
