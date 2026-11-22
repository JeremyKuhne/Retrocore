; COMMODORE BASIC 1: SCREEN-EDITOR ROM PATCHES

;; Emits the BASIC 1 editor-ROM patches following its sign-on message.
.macro COMMODORE_BASIC1_EDITOR_PATCHES
;; Stops after a blank terminal INPUT without printing BREAK.
INPSTP:
    clc
    jmp STPEND

;; Checks whether a string variable is the clock string rather than an array element.
;; In: A/Y = variable name, FACLO = high byte of its value address
TISTR:
    bit FACLO
    bpl TISTR2
    cmp #'T'
    bne TISTR2
    jmp TISTR1
TISTR2:
    rts

;; Routes a numeric variable to the clock, status or ordinary variable handler.
;; In: A/Y = variable name, FACLO = high byte of its value address
TINUM:
    bit FACLO
    bmi TINUM2
    jmp GOMOVF
TINUM2:
    cmp #'T'
    beq TINUM3
    jmp QSTATV
TINUM3:
    jmp TINUM1

;; Stores the character fetched for GET and prepares to parse its buffer.
GETSTR:
    sta CHARAC
    inx
    jmp GETST1

;; Selects the DATA line for READ errors or a direct line for GET errors.
;; In: A = input type, negative = set for READ
;; Out: A/Y = DATA line for READ, Y = $FF for GET
GETDTL:
    bpl GETDT1
    lda DATLIN
    ldy DATLIN+1
    rts
GETDT1:
    ldy #$FF
    rts

;; Advances BASIC's terminal column only for screen output.
;; In: zero = set when the selected channel is the screen
INCTRM:
    bne INCTR2
INCTR1:
    inc TRMPOS
    bne INCTR2
    lda CQPNTR
    sta TRMPOS
    bne INCTR1
INCTR2:
    rts

;; Unwinds GET's return address and resumes input parsing with X as the text pointer.
GETST1:
    stx TXTPTR
    pla
    pla
    tya
    jmp RESETC
LASTWR:
.endmacro

;; Emits BASIC 1's array-descriptor step at the end of the editor ROM.
.macro COMMODORE_BASIC1_ARRAY_PATCH
    .assert * = $E7F3, "The BASIC 1 array patch must start at $E7F3."

;; Advances past an array header, retaining the original shift carry in the addition.
;; In: A = dimension count
;; Out: A = header size, Y = 0
ARYINC:
    asl a
    adc #$05
    ldy #$00
    rts
.endmacro
