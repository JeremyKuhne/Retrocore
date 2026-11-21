;; Clears mode bit 4 (leaving a quoted string).
B_CANLIT:
    lda MODE80                      ; $CA02
    and #$EF                        ; $CA05
    sta MODE80                      ; $CA07

B_FIXCHR:
    lda MODE80                      ; $CA0A
    and #$80                        ; $CA0D
    beq B_INRET                     ; $CA0F
    lda MODE80                      ; $CA11
    and #$10                        ; $CA14
    bne B_INRET                     ; $CA16
    lda CHAR                        ; $CA18
    cmp #'`'                        ; $CA1B above it: lowercase
    bcc B_INRET                     ; $CA1D
    and #$DF                        ; $CA1F
    sta CHAR                        ; $CA21

B_INRET:
    jmp BIORET                      ; $CA24

;; Reads the character before the cursor (moving left and back right).
;; Out:   $0478 = the character, zero = set if it is a quote ($A2), or if the cursor is at the top left
;; Keeps: Y
GETPRIOR:
    lda OURCV                       ; $CA27
    ora OURCH                       ; $CA2A
    beq GPX                         ; $CA2D
    tya                             ; $CA2F
    pha                             ; $CA30
    jsr X_BS                        ; $CA31
    ldy OURCH                       ; $CA34
    jsr PICK                        ; $CA37
    ora #$80                        ; $CA3A
    sta TEMP1                       ; $CA3C
    jsr X_FS                        ; $CA3F
    pla                             ; $CA42
    tay                             ; $CA43
    lda TEMP1                       ; $CA44
    cmp #'"'                        ; $CA47

GPX:
    rts                             ; $CA49

;; Sets the mode byte to $22 and continues as PINIT. Reached from the JMP at $C800.
PINIT1_0:
    lda #$22                        ; $CA4A
    jmp PINIT2                      ; $CA4C

;; Pascal init: sets the mode byte to $20 (or $22 from $CA4A), the full 80x24 window and inverse state.
;; With no 80-column card returns X = 9; otherwise turns on 80STORE, 80VID and the alternate character
;; set, homes and clears the screen, shows the cursor and returns X = 0.
PINIT:
    lda #$20                        ; $CA4F

PINIT2:
    sta MODE80                      ; $CA51
    jsr FULL80                      ; $CA54
    jsr PSETUP                      ; $CA57
    jsr TESTCARD                    ; $CA5A
    beq PIGOOD                      ; $CA5D
    ldx #$09                        ; $CA5F
    rts                             ; $CA61

;; Pascal init with a card present: switches 80 columns on and clears the screen.
PIGOOD:
    sta SET80STORE                  ; $CA62
    sta SET80VID                    ; $CA65
    sta SETALTCHAR                  ; $CA68
    jsr X_FF                        ; $CA6B
    jsr INVERT                      ; $CA6E
    ldx #$00                        ; $CA71
    rts                             ; $CA73

;; Pascal read: waits for a key and returns it with bit 7 clear.
;; Out: A = key (also in $067B); X = 0, or $C3 when mode bit 1 is set
C8_PREAD:
    jsr PSETUP                      ; $CA74
    jsr GETKEY80                    ; $CA77
    and #$7F                        ; $CA7A
    sta CHAR                        ; $CA7C
    ldx #$00                        ; $CA7F
    lda MODE80                      ; $CA81
    and #$02                        ; $CA84
    beq PREADRET2                   ; $CA86
    ldx #$C3                        ; $CA88

PREADRET2:
    lda CHAR                        ; $CA8A
    rts                             ; $CA8D

;; Pascal write: hides the cursor, handles the character, shows the cursor.
;; In: A = character.
;; Out: X = 0
;; $1E starts GOTOXY: the next two characters minus 32 are the column ($06FB) and row. Other control
;; characters go to CTLCHAR; printable ones are stored with bit 7 set and advance the cursor, which
;; stays on the last column when mode bit 0 is set, else wraps with a carriage return and line feed.
PWRITE:
    sta CHAR                        ; $CA8E
    jsr PSETUP                      ; $CA91
    jsr INVERT                      ; $CA94
    lda MODE80                      ; $CA97
    and #$08                        ; $CA9A
    beq PWRITE3                     ; $CA9C

PWRITE2:
    lda XCOORD                      ; $CA9E
    bpl GETY                        ; $CAA1
    lda CHAR                        ; $CAA3
    sec                             ; $CAA6
    sbc #$20                        ; $CAA7
    sta XCOORD                      ; $CAA9
    jmp PWRITERET                   ; $CAAC

;; GOTOXY, second byte: sets the row from the character and the column from $06FB, clears mode bit 3.
GETY:
    lda CHAR                        ; $CAAF
    sec                             ; $CAB2
    sbc #$20                        ; $CAB3
    sta OURCV                       ; $CAB5
    jsr C8_BASCALC                  ; $CAB8
    lda XCOORD                      ; $CABB
    sta OURCH                       ; $CABE
    lda MODE80                      ; $CAC1
    and #$F7                        ; $CAC4
    sta MODE80                      ; $CAC6
    bne PWRITERET                   ; $CAC9

PWRITE3:
    lda CHAR                        ; $CACB
    cmp #KEY_GOTOXY & $7F           ; $CACE
    beq STARTXY                     ; $CAD0
    cmp #' ' & $7F                  ; $CAD2 below the space: a control character
    bcs PWRITE4                     ; $CAD4
    jsr CTLCHAR                     ; $CAD6
    jmp PWRITERET                   ; $CAD9

;; Control-^ ($1E): sets mode bit 3 and marks the column byte ($06FB = $FF) as not yet received.
;; PWRITE4 ($CAEB) displays a printable character and PWRITERET ($CB0F) is the common exit.
STARTXY:
    lda MODE80                      ; $CADC
    ora #$08                        ; $CADF
    sta MODE80                      ; $CAE1
    lda #$FF                        ; $CAE4
    sta XCOORD                      ; $CAE6
    bmi PWRITERET                   ; $CAE9

PWRITE4:
    ora #$80                        ; $CAEB
    ldy OURCH                       ; $CAED
    jsr STORCHAR                    ; $CAF0
    inc OURCH                       ; $CAF3
    lda OURCH                       ; $CAF6
    cmp WNDWDTH                     ; $CAF9
    bcc PWRITERET                   ; $CAFB
    lda MODE80                      ; $CAFD
    and #$01                        ; $CB00
    beq PWWRAP                      ; $CB02
    dec OURCH                       ; $CB04
    bne PWRITERET                   ; $CB07

PWWRAP:
    jsr X_CR                        ; $CB09
    jsr X_LF                        ; $CB0C

PWRITERET:
    jsr INVERT                      ; $CB0F
    ldx #$00                        ; $CB12
    rts                             ; $CB14

;; Waits for a key, stirring RNDL/RNDH, and clears the keyboard strobe.
;; Out: A = key (bit 7 set)
GETKEY80:
    inc RNDL                        ; $CB15
    bne GETK2                       ; $CB17
    inc RNDH                        ; $CB19

GETK2:
    lda KBD                         ; $CB1B
    bpl GETKEY80                    ; $CB1E
    sta KBDSTRB                     ; $CB20
    rts                             ; $CB23

;; Tests for an 80-column card: with interrupts off, turns 80STORE and PAGE2 on, writes $88 to $0400 in
;; auxiliary memory, reads it back and restores the byte, PAGE2 and 80STORE.
;; Out:   A = $88 if the card answered, zero = set if the card answered
;; Uses:  A, Y
TESTCARD:
    lda RDPAGE2                     ; $CB24
    asl a                           ; $CB27
    lda #$88                        ; $CB28
    bit RD80STORE                   ; $CB2A
    sta SET80STORE                  ; $CB2D
    php                             ; $CB30
    sei                             ; $CB31
    php                             ; $CB32
    sta HISCR                       ; $CB33
    ldy LINE1                       ; $CB36
    sta LINE1                       ; $CB39
    lda LINE1                       ; $CB3C
    sty LINE1                       ; $CB3F
    plp                             ; $CB42
    bcs STAY2                       ; $CB43
    sta LOWSCR                      ; $CB45

STAY2:
    bmi STAY80                      ; $CB48
    sta KBD                         ; $CB4A

STAY80:
    plp                             ; $CB4D

TESTFAIL:
    cmp #$88                        ; $CB4E
    rts                             ; $CB50

;; Computes BASL/BASH for a text row and saves them in $077B/$07FB. WNDLFT is added halved in 80 columns.
;; If mode bit 0 is set and bit 5 clear, calls the Monitor's $FC75 to let interrupts in.
;; In:    $05FB = the row
;; Entry: C8_BASCALC_1 = takes the row in A
;; Keeps: A
C8_BASCALC:
    clc                             ; $CB51
    bcc BSCLC1                      ; $CB52

C8_BASCALC_1:
    sec                             ; $CB54

BSCLC1:
    pha                             ; $CB55
    bcs BSCLC1A                     ; $CB56
    lda OURCV                       ; $CB58

BSCLC1A:
    pha                             ; $CB5B
    lsr a                           ; $CB5C
    and #$03                        ; $CB5D
    ora #$04                        ; $CB5F
    sta BASH                        ; $CB61
    sta OLDBASH                     ; $CB63
    pla                             ; $CB66
    and #$18                        ; $CB67
    bcc BSCLC2                      ; $CB69
    adc #$7F                        ; $CB6B

BSCLC2:
    sta BASL                        ; $CB6D
    asl a                           ; $CB6F
    asl a                           ; $CB70
    ora BASL                        ; $CB71
    sta BASL                        ; $CB73
    lda WNDLFT                      ; $CB75
    php                             ; $CB77
    bit RD80VID                     ; $CB78
    bpl BASCLC3                     ; $CB7B
    lsr a                           ; $CB7D

BASCLC3:
    plp                             ; $CB7E
    adc BASL                        ; $CB7F
    sta BASL                        ; $CB81
    sta OLDBASL                     ; $CB83
    lda MODE80                      ; $CB86
    and #$01                        ; $CB89
    beq BASCLCX                     ; $CB8B
    lda MODE80                      ; $CB8D
    and #$20                        ; $CB90
    bne BASCLCX                     ; $CB92
    jsr VIDSYNC                     ; $CB94

BASCLCX:
    pla                             ; $CB97
    rts                             ; $CB98

;; Performs a control character at the 80-column cursor.
;; In: A = character ($00-$1F).
;; Out:   carry = clear if handled, set if not
;; Keeps: A, Y
;; Uses: $0478
CTLCHAR:
    sta TEMP1                       ; $CB99
    pha                             ; $CB9C
    tya                             ; $CB9D
    pha                             ; $CB9E
    ldy TEMP1                       ; $CB9F
    cpy #KEY_BELL & $7F             ; $CBA2 Control-G, the first in CTLADL and CTLADH
    bcc CTLCHARX                    ; $CBA4
    lda CTLADH-7,y                  ; $CBA6 Y = 7-$1F: Control-G to Control-_
    bne CTLGO                       ; $CBA9

CTLCHARX:
    sec                             ; $CBAB
    bcs CTLRET                      ; $CBAC

CTLGO:
    jsr CTLXFER                     ; $CBAE
    clc                             ; $CBB1

CTLRET:
    pla                             ; $CBB2
    tay                             ; $CBB3
    pla                             ; $CBB4
    rts                             ; $CBB5

;; Jumps (by RTS) to the handler for control character Y: the caller has pushed the high byte from
;; CTLADH, this pushes the low byte from CTLADL.
CTLXFER:
    pha                             ; $CBB6
    lda CTLADL-7,y                  ; $CBB7 Y = 7-$1F
    pha                             ; $CBBA
    rts                             ; $CBBB

;; Control-G: rings the bell. Pauses, then toggles the speaker 192 times.
X_BELL:
    lda #$40                        ; $CBBC
    jsr C8_WAIT                     ; $CBBE
    ldy #$C0                        ; $CBC1

C8_BELL2:
    lda #$0C                        ; $CBC3
    jsr C8_WAIT                     ; $CBC5
    lda SPKR                        ; $CBC8
    dey                             ; $CBCB
    bne C8_BELL2                    ; $CBCC
    rts                             ; $CBCE

;; A delay, a copy of the Monitor's WAIT.
;; In: A = count
C8_WAIT:
    sec                             ; $CBCF

C8_WAIT2:
    pha                             ; $CBD0

C8_WAIT3:
    sbc #$01                        ; $CBD1
    bne C8_WAIT3                    ; $CBD3
    pla                             ; $CBD5
    sbc #$01                        ; $CBD6
    bne C8_WAIT2                    ; $CBD8
    rts                             ; $CBDA

;; Moves the cursor left; from column 0 goes to the end of the previous line (X_US).
X_BS:
    dec OURCH                       ; $CBDB
    bpl BSDONE                      ; $CBDE
    lda WNDWDTH                     ; $CBE0

BS40:
    sta OURCH                       ; $CBE2
    dec OURCH                       ; $CBE5
    jsr X_US                        ; $CBE8

BSDONE:
    rts                             ; $CBEB

;; Carriage return: in BASIC input (mode bit 6, not Pascal) clears to the end of the line first. Sets the
;; column to 0 and, outside Pascal mode, does a line feed.
X_CR:
    lda MODE80                      ; $CBEC
    and #$20                        ; $CBEF
    bne X_CRPAS                     ; $CBF1
    lda MODE80                      ; $CBF3
    and #$40                        ; $CBF6
    beq X_CRPAS                     ; $CBF8
    jsr X_GS                        ; $CBFA
