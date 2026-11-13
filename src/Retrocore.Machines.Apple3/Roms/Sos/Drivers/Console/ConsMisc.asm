; ---------------------------------------------------------------------------------------------------------------------
; Open, close and initialize
; ---------------------------------------------------------------------------------------------------------------------

;; The open request: claims the keyboard interrupt, marks the console open and resets it (control 0), then sets up the
;; VIA's CA2 line for the keyboard and unmasks its interrupt.
;; Out: carry = clear
;; Errors: XNOTAVIL when the console is already open, XNORESRC (through <SYSERR>)
CNSLOPEN:
    bit a:OPENFLG
    bpl @L010
    lda #<XNOTAVIL
    jsr SYSERR
@L010:
    lda #<KYBDSSIZ
    ldx a:KYBDSADR
    ldy a:KYBDSADR+$01
    jsr ALLOCSIR
    bcs @L020
    lda #<TRUE
    sta a:OPENFLG
    jsr CCNTL00
    php
    sei
    lda E_PCR
    and #$F1
    ora #$02
    sta E_PCR
    plp
    lda #<KYBDCLR
    sta E_IFR
    bit KYBDSTRB
    lda #<KYBDENBL
    sta E_IER
    clc
    rts
@L020:
    lda #<XNORESRC
    jsr SYSERR

;; The close request: waits for a download in progress to finish, masks the keyboard interrupt and releases it.
;; Errors: XNOTOPEN (through <SYSERR>)
CNSLCLOS:
    asl a:OPENFLG
    bcs @L010
    jmp CNOTOPEN
@L010:
    bit a:DNLDFLG
    bmi @L010
    lda #<KYBDDSBL
    sta E_IER
    bit KYBDSTRB
    lda #<KYBDSSIZ
    ldx a:KYBDSADR
    ldy a:KYBDSADR+$01
    jsr DEALCSIR
    rts

;; The initialize request, made when SOS starts: marks the console closed, gives the interrupt resources the driver's
;; bank, and downloads the character set already at <TEXTCSA>.
;; Out: carry = clear
CNSLINIT:
    lda #<FALSE
    sta a:OPENFLG
    lda B_REG
    sta a:KYBDBANK
    sta a:DNLDBANK
    lda #<TEXTCSA
    sta SCLIST
    lda #>TEXTCSA
    sta SCLIST+$01
    lda #$00
    sta $1400+SCLIST+$01
    jsr LOADSET                     ; from TEXTCSA to itself, then download it
    clc
    rts
