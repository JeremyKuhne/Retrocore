; GETLN's echo of a character that is not a carriage return: prints it, handles backspace and
; Control-X (cancel), and beeps near the end of the 248-byte buffer.
.if ENHANCED

PICKFIX:
    ldy #$0F                        ; $FD3D
    jsr GOTOCX                      ; $FD3F
    ldy CH                          ; $FD42
    sta IN,x                        ; $FD44

NOTCR_1:
    jsr COUT                        ; $FD47
    nop                             ; $FD4A
.else

NOTCR:
    lda INVFLG                      ; $FD3D
    pha                             ; $FD3F
    lda #$FF                        ; $FD40
.endif
.if MONITOR = MONITOR_IIE
    nop                             ; $FD4B original $FD42
    nop                             ; $FD4C original $FD43
.else
    sta INVFLG                      ; $FD42 the Apple II's echo is always in normal video
.endif
    lda IN,x                        ; $FD4D original $FD44
.if .not ENHANCED

NOTCR_1:
    jsr COUT                        ; $FD47
    pla                             ; $FD4A
    sta INVFLG                      ; $FD4B
    lda IN,x                        ; $FD4D
.endif
    cmp #KEY_BS                     ; $FD50
    beq BCKSPC                      ; $FD52
    cmp #KEY_CTRL_X                 ; $FD54
    beq CANCEL                      ; $FD56
    cpx #$F8                        ; $FD58
    bcc NOTCR1                      ; $FD5A
    jsr BELL                        ; $FD5C

NOTCR1:
    inx                             ; $FD5F
    bne NXTCHAR                     ; $FD60

;; Cancels the input line: prints a backslash and starts again.
CANCEL:
    lda #'\'                        ; $FD62
    jsr COUT                        ; $FD64

;; GETLN after a carriage return.
GETLNZ:
    jsr CROUT                       ; $FD67

;; Reads a line of input into IN ($0200) after printing the prompt character in PROMPT.
;; Backspace deletes a character, Control-X cancels the line, and the right arrow (Control-U) copies
;; the character under the cursor.
;;
;; The Apple II's Monitors store lowercase letters as capitals, and echo the line in normal video
;; whatever INVFLG holds.
;; Out: X = length; the line ends with a carriage return at IN,X
GETLN:
    lda PROMPT                      ; $FD6A
    jsr COUT                        ; $FD6C

;; GETLN without printing the prompt.
GETLN_1:
    ldx #$01                        ; $FD6F

BCKSPC:
    txa                             ; $FD71
    beq GETLNZ                      ; $FD72
    dex                             ; $FD74

;; Reads the next character of an input line; Control-U takes the character under the cursor.
NXTCHAR:
    jsr RDCHAR                      ; $FD75
    cmp #KEY_RIGHT                  ; $FD78
.if ENHANCED
    bne ADDINP                      ; $FD7A
.else
    bne CAPTST                      ; $FD7A
.endif
    lda (BASL),y                    ; $FD7C
.if ENHANCED
    bit RD80VID                     ; $FD7E
    bmi PICKFIX                     ; $FD81
    nop                             ; $FD83
.else

CAPTST:
    cmp #'a' - 1                    ; $FD7E lowercase passes unchanged
    bcc ADDINP                      ; $FD80
.if MONITOR = MONITOR_IIE
    and #$FF                        ; $FD82
.else
    and #$DF                        ; $FD82 the Apple II's Monitors make it uppercase
.endif
.endif

;; Stores a character in the input line and handles it (NOTCR) unless it is a carriage return.
ADDINP:
    sta IN,x                        ; $FD84
    cmp #KEY_CR                     ; $FD87
.if ENHANCED
    bne NOTCR_1                     ; $FD89
.else
    bne NOTCR                       ; $FD89
.endif

;; Clears the rest of the line, then prints a carriage return.
CROUT1:
    jsr CLREOL                      ; $FD8B

;; Prints a carriage return.
CROUT:
    lda #KEY_CR                     ; $FD8E
    bne COUT                        ; $FD90

;; Prints a carriage return, then A1 as "AAAA-".
PRA1:
    ldy A1H                         ; $FD92
    ldx A1L                         ; $FD94

PRYX2:
    jsr CROUT                       ; $FD96
    jsr PRNTYX                      ; $FD99
    ldy #$00                        ; $FD9C
    lda #'-'                        ; $FD9E
    jmp COUT                        ; $FDA0
