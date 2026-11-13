; ---------------------------------------------------------------------------------------------------------------------
; The entry point
; ---------------------------------------------------------------------------------------------------------------------

;; The driver's entry point, for every request: sets up the driver's zero page and goes to the request's routine.
;;
;; It clears the extended-addressing bytes of the driver's zero page from <ZPDATA> on, so its pointers address the
;; current bank, and brings back <BASE1> and <BASE2> from <ZPSAVE>. A routine that moves them must call <ZPOUT>
;; before it returns.
;; In: REQCODE = the request, with its parameters after it
;; Errors: XREQCODE for a request the driver does not take, or the request's own (through <SYSERR>)
;; See: <CREQSW>
CNSLDH:
    ldx #<($FF-ZPDATA)
    ldy #$00
    tya
@L010:
    sta $1400+ZPDATA,x              ; the pointer's extended-addressing byte
    cpx #<ZPLENGTH
    bcs @L020
    lda a:ZPSAVE,x                  ; BASE1 and BASE2
    sta ZPDATA,x
    tya
@L020:
    dex
    bpl @L010
    SWITCH REQCODE, $08, CREQSW

;; Ends the request with the error for a request code the driver does not take.
;; Errors: XREQCODE (through <SYSERR>)
CBADREQ:
    lda #<XREQCODE
    jsr SYSERR

;; Ends the request with the error for a console that is not open.
;; Errors: XNOTOPEN (through <SYSERR>)
CNOTOPEN:
    lda #<XNOTOPEN
    jsr SYSERR

;; The request routines' addresses, less one, for <SWITCH>: read, write, status and control, two request codes that are
;; errors, then open, close and initialize.
CREQSW:
    .word CNSLREAD-$01
    .word CNSLWRIT-$01
    .word CNSLSTAT-$01
    .word CNSLCNTL-$01
    .word CBADREQ-$01
    .word CBADREQ-$01
    .word CNSLOPEN-$01
    .word CNSLCLOS-$01
    .word CNSLINIT-$01

; ---------------------------------------------------------------------------------------------------------------------
; The keyboard interrupt
; ---------------------------------------------------------------------------------------------------------------------

;; The keyboard's interrupt handler: reads the key, clears the interrupt and passes the key on.
;;
;; A special key goes to <KIHSPCL>. Return typed without Control is passed on as it is; any other key is translated by
;; <KIHXFORM>. The key then sets off any event waiting for it (<KIHCKEV>) and goes into the type-ahead buffer
;; (<KIHBFCH>).
;; Uses: A, X, Y
KYBDMIH:
    ldx #<KYBDCLR
    lda KAPORT
    bmi @L010
    stx E_IFR                       ; no key: only clear the interrupt
    rts
@L010:
    and #<BITOFF7
    sta a:KADATA
    lda KBPORT
    eor #$3C                        ; Control, Alpha Lock and the Apple keys read low; make them high
    sta a:KBDATA
    stx E_IFR
    stx KYBDSTRB
    bmi KIHSPCL                     ; a special key
    lda a:KADATA
    cmp #<ASC_CR
    bne KIHXFORM
    lda a:KBDATA
    and #<BITON2
    bne KIHXFORM
    jmp KIHA1KY

;; Handles a special key. With Control alone held, 5 to 9 are the console's own commands; any other special key is
;; passed on untranslated.
KIHSPCL:
    and #$36                        ; Shift, Control and the two Apple keys
    cmp #<BITON2
    beq @L050
@L010:
    jmp KIHA1KY
@L050:
    lda a:KADATA
    cmp #'5'                        ; Control-5: video off or on
    bcc @L010
    bne @L060
    lda SCRNMODE
    eor #<BITON7
    sta SCRNMODE
    rts
@L060:
    cmp #'6'                        ; Control-6: empty the type-ahead buffer
    bne @L070
    lda #$00
    sta a:KEYCNT
    sta a:BUFHEAD
    sta a:BUFTAIL
    rts
@L070:
    cmp #'7'                        ; Control-7: suspend output or resume it
    bne @L080
    lda SUSPFLSH
    eor #<BITON7
    sta SUSPFLSH
    rts
@L080:
    cmp #'8'                        ; Control-8: show control characters or carry them out
    bne @L090
    lda a:DSPLYCTL
    eor #<BITON7
    sta a:DSPLYCTL
    rts
@L090:
    cmp #'9'                        ; Control-9: throw output away or stop, and resume
    bne KIHA1KY
    lda SUSPFLSH
    and #<BITOFF7
    eor #<BITON6
    sta SUSPFLSH
    rts

;; Translates a key through the keyboard layout table, <XFORMTBL>, for Shift, Control and Alpha Lock.
KIHXFORM:
    lda a:KADATA
@L010:
    cmp #$7B
    bcc @L030
    cmp #$7E
    bcc @L020
    eor #$C0
    bne @L040
@L020:
    and #$5F
@L030:
    ora #$C0
@L040:
    tax
    lda a:KBDATA
    lsr a
    and #$03
    ora XFORMTBL,x                  ; the key number, plus Shift and Control
    tax
    lda XFORMTBL,x
    bpl @L050
    lda a:KBDATA
    and #<BITON3                    ; Alpha Lock down?
    beq @L050
    txa
    ora #<BITON0                    ; then take the shifted entry
    tax
@L050:
    lda XFORMTBL,x
    and #<BITOFF7
    sta a:KADATA

;; Sets bit 7 of the key's character when Open Apple is held.
KIHA1KY:
    lda a:KBDATA
    and #<BITON4
    beq KIHCKEV
    lda a:KADATA
    ora #<BITON7
    sta a:KADATA

;; Queues the event a key sets off: the any-key event, when no read is waiting, or else the attention event, when the
;; key is the attention key. Either one empties the type-ahead buffer and ends any suspend or flush of output; the
;; attention event also ends a read in progress.
;; See: <ANYKYEVNT>, <ATTNEVNT>
KIHCKEV:
    bit a:READING
    bmi @L010
    lda a:ANYKYEVNT
    beq @L010
    ldx a:ANYKYPARM
    ldy a:ANYKYPARM+$01
    jsr QUEEVENT
    lda #<FALSE
    sta a:ANYKYEVNT
    beq @L020
@L010:
    lda a:ATTNEVNT
    beq KIHBFCH
    lda a:KADATA
    cmp a:ATTNCHAR
    bne KIHBFCH
    ldx a:ATTNPARM
    ldy a:ATTNPARM+$01
    jsr QUEEVENT
    lda #<FALSE
    sta a:ATTNEVNT
@L020:
    sta a:READING
    sta a:KEYCNT
    sta a:BUFHEAD
    sta a:BUFTAIL
    sta SUSPFLSH

;; Puts the key in the type-ahead buffer. When the buffer is full the key is dropped and the bell sounds; with buffering
;; off, a buffer size of 0, it is dropped silently.
KIHBFCH:
    ldx a:BUFSIZ
    beq @L030
    dex
    cpx a:KEYCNT
    bcs @L010
    bit BELL
    bcc @L030                       ; always
@L010:
    inc a:KEYCNT
    ldx a:BUFTAIL
    lda a:KADATA
    sta KABUF,x
    lda a:KBDATA
    sta KBBUF,x
    inx
    cpx a:BUFSIZ
    bcc @L020
    ldx #$00
@L020:
    stx a:BUFTAIL
@L030:
    rts

;; Takes the next key from the type-ahead buffer, waiting for one unless no-wait is on.
;;
;; Before it waits it turns the video on, and it shrinks the buffer to one key and unmasks the keyboard interrupt. In
;; escape mode it shows a plus sign at the cursor while it waits.
;; In: E_IER = the keyboard interrupt masked, interrupt = clear
;; Out: carry = clear for a key and set for none (no-wait found the buffer empty, or the attention key ended the read),
;;   A = the key's character, X = its modifier byte
;; Uses: Y
GETKEY:
    lda a:KEYCNT
    bne @L030
    php
    sei
    lda SCRNMODE
    ora #<BITON7
    sta SCRNMODE
    lda E_REG
    ora #<BITON5                    ; the video on
    sta E_REG
    plp
    bit a:NOWAIT
    bpl @L010
    asl a:READING                   ; carry set: no key
    rts
@L010:
    ldx a:BUFSIZ
    lda #$01
    sta a:BUFSIZ
    lda #<KYBDENBL
    sta E_IER
    bit a:ESCAPE
    bvc @L020
    clc
    lda a:TPX
    ldy a:HMODE
    bpl @L015
    lsr a
    bcc @L015
    tay
    lda (BASE2),y
    pha
    and #<BITON7
    ora #$2B                        ; a '+', normal or inverse as the character was
    sta (BASE2),y
    bcs @L020
@L015:
    tay
    lda (BASE1),y
    pha
    and #<BITON7
    ora #$2B
    sta (BASE1),y
@L020:
    lda a:KEYCNT
    beq @L020
    bvc @L026
    pla
    bcc @L024
    sta (BASE2),y
    bcs @L026
@L024:
    sta (BASE1),y
@L026:
    lda #<KYBDDSBL
    sta E_IER
    stx a:BUFSIZ
    sec
    bit a:READING
    bpl @L060                       ; the attention key ended the read
@L030:
    ldy a:BUFHEAD
    dec a:KEYCNT
    bne @L040
    lda #$00
    sta a:BUFHEAD
    sta a:BUFTAIL
    beq @L050
@L040:
    inc a:BUFHEAD
    lda a:BUFHEAD
    cmp a:BUFSIZ
    bcc @L050
    lda #$00
    sta a:BUFHEAD
@L050:
    lda KABUF,y
    ldx KBBUF,y
    clc
@L060:
    rts

;; Writes a character or control code to the screen when echo is on, taking the cursor off while it does.
;; In: A = the character
;; Uses: A, X, Y
SCRNECHO:
    bit a:ECHO
    bpl @L010
    pha
    jsr CURSOR
    pla
    jsr PRINT
    jsr CURSOR
@L010:
    rts

;; Backs the screen's cursor up over a deleted input character, when echo is on and the character is not a control
;; character, and erases it when asked.
;; In: BUFFPTR = the deleted character, overflow = set to erase it
;; Uses: A, X, Y
BACKSP:
    lda a:ECHO
    bpl @L020
    ldy #$00
    lda (BUFFPTR),y
    cmp #<ASC_SP
    bcc @L020
    php
    jsr CURSOR
    lda #<ASC_BS
    jsr PRINT
    plp
    bvc @L010
    lda #<ASC_SP
    jsr PRINT
    lda #<ASC_BS
    jsr PRINT
@L010:
    jsr CURSOR
@L020:
    rts
