; ---------------------------------------------------------------------------------------------------------------------
; The read request
; ---------------------------------------------------------------------------------------------------------------------

;; The read request: fills the caller's buffer with keys.
;;
;; In console mode the cursor shows while the read waits. With echo on, the keys typed are shown and the line can be
;; edited: <TSTESCAPE> handles escape mode, <TSTCHDEL> and <TSTLNDEL> the delete keys, and <TSTCHCPY> the copy key.
;; A read of one byte takes no delete keys. The read ends when the count is reached, after the new-line character when
;; that is on, or when no key comes.
;;
;; In keyboard mode each key fills two bytes, its character and its modifier byte, so the count is made even, and
;; nothing is echoed or edited.
;; In: BUFFPTR = the buffer, REQCNT = how many bytes, RTNCNT = where to put how many were read
;; Errors: XNOTOPEN (through <SYSERR>)
;; Uses: A, X, Y, COUNT, ONEBYTE
CNSLREAD:
    bit a:OPENFLG
    bmi @L010
    jmp CNOTOPEN
@L010:
    bit a:KYBDMODE
    bmi @L030
    lda a:SMCURSOR
    pha
    bmi @L020
    lda #<ASC_ENQ                   ; show the cursor
    jsr SCRNECHO
@L020:
    lda #<FALSE
    sta ONEBYTE
    lda REQCNT+$01
    bne @L040
    lda REQCNT
    cmp #$01
    bne @L040
    ror ONEBYTE                     ; carry is set: a one-byte read
    bmi @L040
@L030:
    lda REQCNT
    and #<BITOFF0                   ; keyboard mode: an even count
    sta REQCNT
@L040:
    lda a:ESCAPE
    and #<BITON7                    ; not in escape mode yet
    sta a:ESCAPE
    lda #$00
    sta COUNT
    sta COUNT+$01
    php
    sei
    sta SUSPFLSH                    ; end any suspend or flush of output
    lda #<KYBDDSBL
    sta E_IER
    lda #<TRUE
    sta a:READING
    plp

;; The read's loop: ends the read when the count is reached or no key comes, and takes the next key.
CNSLLOOP:
    lda COUNT
    cmp REQCNT
    lda COUNT+$01
    sbc REQCNT+$01
    bcc @L020
@L010:
    jmp CNSLEXIT
@L020:
    jsr GETKEY
    bcs @L010
    bit a:KYBDMODE
    bpl TSTESCAPE

;; Keyboard mode: stores the key's character and modifier byte.
KYBDRDY:
    pha
    ldy #$00
    sta (BUFFPTR),y
    iny
    txa
    sta (BUFFPTR),y
    lda #$02
    jmp BUMPCNT

; ---------------------------------------------------------------------------------------------------------------------
; Console mode: the keys that edit the line
; ---------------------------------------------------------------------------------------------------------------------

;; Escape mode, when echo and escape mode are on. Escape starts it; while it lasts, each key in <ESCCMD>, a letter in
;; either case, writes the control code <ESCOP> has for it, and any other key ends it and is dropped.
TSTESCAPE:
    bit a:ECHO
    bpl TSTCHDEL
    bit a:ESCAPE
    bpl TSTCHDEL
    bvc @L040                       ; not in escape mode
    ldy #<(ECMDCNT-$01)
    cmp #'a'
    bcc @L010
    cmp #'{'
    bcs @L010
    and #<BITOFF5                   ; a lowercase letter to a capital
@L010:
    cmp a:ESCCMD,y
    beq @L020
    dey
    bpl @L010
    asl a:ESCAPE
    bcs @L030                       ; always
@L020:
    lda a:ESCOP,y
    jsr SCRNECHO
@L030:
    jmp CNSLLOOP
@L040:
    cmp #<ASC_ESC
    bne TSTCHDEL
    ror a:ESCAPE
    bmi @L030

;; The character delete key, when it is on: takes back the last character read and backs up over it on the screen.
TSTCHDEL:
    bit ONEBYTE
    bmi TSTLNDEL
    bit a:CHDELFLG
    bpl TSTLNDEL
    cmp #<CHDELCHR
    bne TSTLNDEL
    lda COUNT
    ora COUNT+$01
    beq @L030
    lda COUNT
    bne @L010
    dec COUNT+$01
@L010:
    dec COUNT
    lda BUFFPTR
    bne @L020
    dec BUFFPTR+$01
@L020:
    dec BUFFPTR
    jsr BACKSP
@L030:
    jmp CNSLLOOP

;; The line delete key, when it is on: takes back everything read. With echo, it backs up over each character when it
;; erases, or else writes a backslash and starts a new line.
TSTLNDEL:
    bit ONEBYTE
    bmi TSTCHCPY
    bit a:LNDELFLG
    bpl TSTCHCPY
    cmp #<LNDELCHR
    bne TSTCHCPY
    lda a:ECHO
    bpl @L050
    bvc @L040                       ; not erasing
@L010:
    lda COUNT
    ora COUNT+$01
    beq @L060
    lda COUNT
    bne @L020
    dec COUNT+$01
@L020:
    dec COUNT
    lda BUFFPTR
    bne @L030
    dec BUFFPTR+$01
@L030:
    dec BUFFPTR
    bit a:LNDELFLG
    jsr BACKSP
    jmp @L010
@L040:
    lda #'\'
    jsr SCRNECHO
    lda #<ASC_CR
    jsr SCRNECHO
    lda #<ASC_LF
    jsr SCRNECHO
@L050:
    sec
    lda BUFFPTR
    sbc COUNT
    sta BUFFPTR
    lda BUFFPTR+$01
    sbc COUNT+$01
    sta BUFFPTR+$01
    lda #$00
    sta COUNT
    sta COUNT+$01
@L060:
    jmp CNSLLOOP

;; The copy key, when echo and copy are on: reads the character under the cursor in its place, with bit 7 set for a
;; control character.
TSTCHCPY:
    bit a:ECHO
    bpl CNSLRDY
    bit a:CHCPYFLG
    bpl CNSLRDY
    cmp #<CHCPYCHR
    bne CNSLRDY
    jsr SCRNPICK
    asl a
    cmp #$40                        ; carry set for a character from a space on
    ror a
    eor #<BITON7

; ---------------------------------------------------------------------------------------------------------------------
; Storing what was read
; ---------------------------------------------------------------------------------------------------------------------

;; Stores a character and echoes it, when echo is on; control characters are echoed only when bit 6 of <ECHO> says so.
CNSLRDY:
    pha
    ldy #$00
    sta (BUFFPTR),y
    bit a:ECHO
    bpl @L020
    bvs @L010
    cmp #$20
    bcc @L020
@L010:
    jsr SCRNECHO
@L020:
    lda #$01

;; Counts the bytes just stored and moves the buffer pointer past them. When the pointer reaches page $FF it moves back
;; to $7F and on to the next bank, as extended addressing requires. The character read is on the stack.
;; In: A = how many bytes
BUMPCNT:
    pha
    clc
    adc COUNT
    sta COUNT
    bcc @L010
    inc COUNT+$01
@L010:
    pla
    clc
    adc BUFFPTR
    sta BUFFPTR
    bcc TSTNEWLN
    inc BUFFPTR+$01
    lda BUFFPTR+$01
    cmp #$FF
    bcc TSTNEWLN
    sbc #$80
    sta BUFFPTR+$01
    inc $1400+BUFFPTR+$01

;; Ends the read after the new-line character, when that is on, or goes back for the next key. The character read is
;; on the stack.
TSTNEWLN:
    pla
    bit a:NEWLINE
    bpl @L010
    cmp a:NEWLNCHR
    beq CNSLEXIT
@L010:
    jmp CNSLLOOP

;; Ends the read: unmasks the keyboard and returns the count. In console mode it also hides the cursor again if the
;; read showed it, and saves the zero page.
CNSLEXIT:
    asl a:READING                   ; no read in progress
    lda #<KYBDENBL
    sta E_IER
    ldy #$00
    lda COUNT
    sta (RTNCNT),y
    iny
    lda COUNT+$01
    sta (RTNCNT),y
    bit a:KYBDMODE
    bmi @L020
    pla                             ; the cursor's state before the read
    bmi @L010
    lda #<ASC_ACK                   ; hide the cursor again
    jsr SCRNECHO
@L010:
    jsr ZPOUT
@L020:
    rts
