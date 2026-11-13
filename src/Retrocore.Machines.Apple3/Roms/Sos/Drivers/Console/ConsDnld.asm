; ---------------------------------------------------------------------------------------------------------------------
; Downloading characters
; ---------------------------------------------------------------------------------------------------------------------

DIMGPTR = $00                       ;; LOADCHR's image pointer, at this offset from X
DCELPTR = $02                       ;; LOADCHR's cell pointer, at this offset from X

;; Loads one character into a download cell: its code and the eight rows of its image go into bytes of the text pages
;; that the screen does not show, where the hardware takes them while downloading.
;;
;; It indexes its zero-page pointers by X, so the driver and its interrupt handler can each give it their own.
;; In: DNLDCEL = the cell, 0-7, DNLDCHR = the character code, X = the zero-page offset of the image pointer, followed
;;   by two bytes LOADCHR uses for the cell pointer
;; Out: DIMGPTR,X = the image pointer, advanced by 8
;; Uses: A, Y
;; Keeps: X
LOADCHR:
    ldy #$00
@L010:
    lda a:DNLDCEL
    and #$03
    ora DCPTRL,y
    sta DCELPTR,x
    lda a:DNLDCEL
    lsr a
    lsr a
    cpy #$04
    rol a
    ora #$08                        ; the code's page, $08-$0B
    sta DCELPTR+$01,x
    lda a:DNLDCHR
    sta (DCELPTR,x)
    lda DCELPTR+$01,x
    eor #$0C                        ; the image's page, $04-$07
    sta DCELPTR+$01,x
    lda (DIMGPTR,x)
    sta (DCELPTR,x)
    inc DIMGPTR,x
    bne @L020
    inc DIMGPTR+$01,x
@L020:
    iny
    cpy #$08
    bcc @L010
    rts

;; The low bytes of the download cells' eight rows in the text pages, to which <LOADCHR> adds the cell number's low two
;; bits.
DCPTRL:
    .byte $78, $7C, $F8, $FC
    .byte $78, $7C, $F8, $FC

;; The vertical-blanking interrupt that ends a download cycle. While a whole set is loading it loads the next eight
;; characters and starts another cycle; once the set is done it turns downloading off and releases the resources.
;; In: X = the zero-page offset of four bytes <LOADCHR> may use
;; Uses: A, X, Y
;; See: <LOADSET>, <LOAD8>
DNLDINT:
    bit DNLDDSBL
    lda #<VBLDSBL
    sta E_IER
    bit a:DNLDFLG
    bvc @L030                       ; the set is done
    cli
    lda #$07
    sta a:DNLDCEL
    lda a:DNLDIMG
    sta DIMGPTR,x
    lda a:DNLDIMG+$01
    sta DIMGPTR+$01,x
@L010:
    jsr LOADCHR
    inc a:DNLDCHR
    bpl @L020
    asl a:DNLDFLG                   ; every character is loaded
@L020:
    dec a:DNLDCEL
    bpl @L010
    lda DIMGPTR,x
    sta a:DNLDIMG
    lda DIMGPTR+$01,x
    sta a:DNLDIMG+$01
    jmp DNLD_GO
@L030:
    asl a:DNLDFLG
    lda #<DNLDSSIZ
    ldx a:DNLDSADR
    ldy a:DNLDSADR+$01
    jsr DEALCSIR
    rts

;; Waits for a download in progress to finish, then claims the download's interrupt resources and sets the VIA's CB1 to
;; the falling edge of vertical blanking and CB2 to the rising edge, both masked.
;;
;; If the resources are in use it ends the request with an error, dropping its own return address.
;; Errors: XNORESRC (through <SYSERR>)
;; Uses: A, X, Y
GETSIRS:
    bit a:DNLDFLG
    bmi GETSIRS
    lda #<DNLDSSIZ
    ldx a:DNLDSADR
    ldy a:DNLDSADR+$01
    jsr ALLOCSIR
    bcs @L010
    php
    sei
    lda E_PCR
    and #$0F
    ora #$60
    sta E_PCR
    lda #<VBLDSBL
    sta E_IER
    plp
    rts
@L010:
    pla
    pla
    lda #<XNORESRC
    jsr SYSERR

;; Control 16: downloads a whole character set from the list's 1024 bytes. It copies the set to <TEXTCSA> and starts the
;; download, which <DNLDINT> carries on eight characters at a time.
;; In: SCLIST = the character set
;; Errors: XNORESRC (through <SYSERR>)
;; Uses: A, X, Y, WORK1
LOADSET:
    jsr GETSIRS
    lda #<TEXTCSA
    sta WORK1
    sta a:DNLDIMG
    lda #>TEXTCSA
    sta WORK1+$01
    sta a:DNLDIMG+$01
    lda #<ASC_NUL
    sta a:DNLDCHR
    ldx #$04
    ldy #$00
    lda SCLIST+$01
    cmp #$FB
    bcc @L010
    sbc #$80                        ; keep the four pages in one bank
    sta SCLIST+$01
    inc $1400+SCLIST+$01
@L010:
    lda (SCLIST),y
    sta (WORK1),y
    iny
    bne @L010
    inc SCLIST+$01
    inc WORK1+$01
    dex
    bne @L010
    lda #$C0                        ; active, with more to come
    sta a:DNLDFLG
    lda #<VBLENBL
    sta E_IER
    rts

;; Control 17: downloads up to eight characters. The list holds the count, then each character's code and eight bytes
;; of image; each image also goes into the copy of the set at <TEXTCSA>. The first character also fills the download
;; cells the others leave over.
;; In: A = the count, SCLIST = the list
;; Errors: XCTLPARM, XNORESRC (through <SYSERR>)
;; Uses: A, X, Y, COUNT, WORK1, WORK2
LOAD8:
    cmp #$01
    bcs @L010
    rts
@L010:
    cmp #$09
    bcc @L020
    lda #<XCTLPARM
    jsr SYSERR
@L020:
    sta COUNT
    jsr GETSIRS
    inc SCLIST
    bne @L030
    inc SCLIST+$01
@L030:
    lda #$08
    sta a:DNLDCEL
@L040:
    ldy #$00
    lda (SCLIST),y
    sta a:DNLDCHR
    inc SCLIST
    bne @L050
    inc SCLIST+$01
@L050:
    lda #$03
    sta WORK1+$01
    lda a:DNLDCHR
    asl a
    asl a
    rol WORK1+$01                   ; the image at TEXTCSA plus 8 times the code
    asl a
    rol WORK1+$01
    sta WORK1
    ldy #$07
@L060:
    lda (SCLIST),y
    sta (WORK1),y
    dey
    bpl @L060
    dec a:DNLDCEL
    ldx #<WORK1
    jsr LOADCHR
    lda a:DNLDCEL
    cmp COUNT
    bcs @L050                       ; fill the next cell with this character too
    lda #$08
    adc SCLIST
    sta SCLIST
    bcc @L070
    inc SCLIST+$01
@L070:
    dec COUNT
    bne @L040
    lda #$80                        ; active, with no more to come
    sta a:DNLDFLG

;; Starts a download cycle: turns downloading on, waits for a vertical-blanking edge when port B's blanking bit is set,
;; clears the flags, and unmasks the interrupt that <DNLDINT> handles.
;; Uses: A
DNLD_GO:
    bit DNLDENBL
    lda #<VBLCLR
    sta E_IFR
@L080:
    bit E_IORB
    bvc @L090
    bit E_IFR
    beq @L080
@L090:
    sta E_IFR
    lda #<VBLENBL
    sta E_IER
    rts
