;; A fixed entry at the start of the $C800 ROM: jumps to $CA4A.
C8ENTRY:
    jmp PINIT1_0                    ; $C800

;; BASICINT: checks that the Monitor version byte reads $06; if not (language card RAM holding another
;; Monitor) copies the ROM Monitor into it with COPYROM and checks again, and hangs if it still differs.
BASICINIT:
    lda #$06                        ; $C803
    cmp VERSION                     ; $C805
    beq BINIT1                      ; $C808
    jsr COPYROM                     ; $C80A
    cmp VERSION                     ; $C80D
    beq BINIT1                      ; $C810
    sei                             ; $C812

HANG:
    jmp HANG                        ; $C813

;; Points CSW at $C307 and KSW at $C305, sets a 40-column window (top 20 if graphics are on), remembers CH in
;; $047B and clears every mode bit except bit 0.
BINIT1:
    lda #>BASICIN                   ; $C816 BASICIN and BASICOUT share page $C3
    sta CSWH                        ; $C818
    sta KSWH                        ; $C81A
    lda #<BASICIN                   ; $C81C
    sta KSWL                        ; $C81E
    lda #<BASICOUT                  ; $C820
    sta CSWL                        ; $C822
    lda #$00                        ; $C824
    sta WNDLFT                      ; $C826
    lda #$00                        ; $C828
    bit RDTEXT                      ; $C82A
    bmi BINIT1A                     ; $C82D
    lda #$14                        ; $C82F

BINIT1A:
    sta WNDTOP                      ; $C831
    lda #$18                        ; $C833
    sta WNDBTM                      ; $C835
    lda #$28                        ; $C837
    sta WNDWDTH                     ; $C839
    lda CH                          ; $C83B
    sta OLDCH                       ; $C83D
    lda #$01                        ; $C840
    and MODE80                      ; $C842
    sta MODE80                      ; $C845
    jmp BINIT2                      ; $C848
    .byte $00, $00                  ; $C84B
    jmp JPREAD                      ; $C84D not referenced in this ROM

;; When an 80-column card answers, doubles WNDWDTH and turns on 80STORE and 80VID. Always selects the
;; alternate character set, homes and clears the window, then continues as output of the character in A.
;; The label C8BASIC ($C866) is the shared input/output path: makes sure 80STORE is on and WNDWDTH even in
;; 80 columns, adopts CH as the cursor column if a program changed it, repeats the version check, and goes
;; to input or output by the saved carry.
BINIT2:
    jsr TESTCARD                    ; $C850
    bne CLEARIT                     ; $C853
    asl WNDWDTH                     ; $C855
    sta SET80STORE                  ; $C857
    sta SET80VID                    ; $C85A

CLEARIT:
    sta SETALTCHAR                  ; $C85D
    jsr X_FF                        ; $C860
    plp                             ; $C863
    clc                             ; $C864
    php                             ; $C865

C8BASIC:
    bit RD80VID                     ; $C866
    bpl C8B2                        ; $C869
    sta SET80STORE                  ; $C86B
    lda WNDWDTH                     ; $C86E
    and #$FE                        ; $C870
    sta WNDWDTH                     ; $C872

C8B2:
    lda CH                          ; $C874
    cmp OLDCH                       ; $C876
    beq C8B3                        ; $C879
    sta OURCH                       ; $C87B

C8B3:
    lda #$06                        ; $C87E
    cmp VERSION                     ; $C880
    beq C8B4                        ; $C883
    jsr COPYROM                     ; $C885
    cmp VERSION                     ; $C888
    beq C8B4                        ; $C88B
    jmp HANG                        ; $C88D

;; Pulls the entry P and goes to BINPUT when carry is set, output otherwise.
C8B4:
    plp                             ; $C890
    bcc BOUT                        ; $C891
    jmp BINPUT                      ; $C893

;; Output path: clears mode bit 6 (not in input).
BOUT:
    lda MODE80                      ; $C896
    and #$BF                        ; $C899
    sta MODE80                      ; $C89B
    jmp BPRINT                      ; $C89E

;; Outputs the character in $067B. A carriage return with Control-S waiting pauses until another key
;; (Control-C is left in the keyboard buffer). Control characters go to CTLCHAR, others to BPNCTL.
BPRINT:
    lda CHAR                        ; $C8A1
    cmp #KEY_CR                     ; $C8A4
    bne C8_NOWAIT                   ; $C8A6
    ldy KBD                         ; $C8A8
    bpl C8_NOWAIT                   ; $C8AB
    cpy #KEY_CTRL_S                 ; $C8AD
    bne C8_NOWAIT                   ; $C8AF
    bit KBDSTRB                     ; $C8B1

C8_KBDWAIT:
    ldy KBD                         ; $C8B4
    bpl C8_KBDWAIT                  ; $C8B7
    cpy #KEY_CTRL_C                 ; $C8B9
    beq C8_NOWAIT                   ; $C8BB
    bit KBDSTRB                     ; $C8BD

C8_NOWAIT:
    and #$7F                        ; $C8C0
    cmp #' ' & $7F                  ; $C8C2 below the space: a control character
    bcs BPNCTL                      ; $C8C4
    jsr CTLCHAR                     ; $C8C6
    jmp BIORET                      ; $C8C9

;; Displays $067B at the cursor (honoring inverse) and advances, wrapping with X_CR at the right edge.
;; BIORET ($C8E2) is the common exit: copies the cursor to CH (SETCH) and $05FB to CV, restores X and
;; Y and returns with A = $067B.
BPNCTL:
    ldy OURCH                       ; $C8CC
    lda CHAR                        ; $C8CF
    jsr STORCHAR                    ; $C8D2
    inc OURCH                       ; $C8D5
    lda OURCH                       ; $C8D8
    cmp WNDWDTH                     ; $C8DB
    bcc BIORET                      ; $C8DD
    jsr X_CR                        ; $C8DF

BIORET:
    lda OURCH                       ; $C8E2
    jsr SETCH                       ; $C8E5
    lda OURCV                       ; $C8E8
    sta CV                          ; $C8EB
    pla                             ; $C8ED
    tax                             ; $C8EE
    pla                             ; $C8EF
    tay                             ; $C8F0
    pla                             ; $C8F1
    lda CHAR                        ; $C8F2
    rts                             ; $C8F5

;; Input path: sets mode bit 6, puts back the character the Monitor's RDKEY changed at CH, then waits for a
;; key with the cursor shown by inverting the character at the 80-column cursor. ESC enters ESCAPING; other
;; keys go to NOESC.
BINPUT:
    lda MODE80                      ; $C8F6
    ora #$40                        ; $C8F9
    sta MODE80                      ; $C8FB
    lda CHAR                        ; $C8FE
    ldy CH                          ; $C901
    sta (BASL),y                    ; $C903

B_INPUT:
    jsr INVERT                      ; $C905
    jsr GETKEY80                    ; $C908
    sta CHAR                        ; $C90B
    jsr INVERT                      ; $C90E
    cmp #KEY_ESC                    ; $C911
    beq ESCAPING                    ; $C913
    jmp NOESC                       ; $C915

;; Escape mode: shows an inverse "+" cursor, reads a key, uppercases it and looks it up in ESCTAB. A match
;; performs ESCCHAR's control character; if that byte has bit 7 set, escape mode continues. Control-Q quits
;; the 80-column firmware and returns Control-X; R and T set and clear uppercase input (mode bit 7). Any
;; other key ends escape mode.
ESCAPING:
    jsr ESCON                       ; $C918
    jsr GETKEY80                    ; $C91B
    jsr ESCOFF                      ; $C91E
    and #$7F                        ; $C921
    cmp #'`' & $7F                  ; $C923 lowercase letters to uppercase
    bcc C8_ESC1                     ; $C925
    and #$DF                        ; $C927

C8_ESC1:
    ldy #ESCCHAR - ESCTAB           ; $C929 one past the last entry, so ESCCHAR's first byte is compared too

ESC2:
    cmp ESCTAB,y                    ; $C92B
    beq ESC3                        ; $C92E
    dey                             ; $C930
    bpl ESC2                        ; $C931
    bmi ESCSPEC                     ; $C933

ESC3:
    lda ESCCHAR,y                   ; $C935
    and #$7F                        ; $C938
    jsr CTLCHAR                     ; $C93A
    lda ESCCHAR,y                   ; $C93D
    bmi ESCAPING                    ; $C940
    jmp B_INPUT                     ; $C942

;; Escape mode, key not in the table: Control-Q runs QUIT and returns $98 (Control-X) as the key.
ESCSPEC:
    cmp #KEY_CTRL_Q & $7F           ; $C945
    bne ESCSPEC2                    ; $C947
    jsr QUIT                        ; $C949
    lda #KEY_CTRL_X                 ; $C94C
    sta CHAR                        ; $C94E
    jmp BIORET                      ; $C951

;; Escape R: sets mode bit 7 (lowercase input is converted to uppercase).
ESCSPEC2:
    cmp #'R' & $7F                  ; $C954
    bne ESCSPEC3                    ; $C956
    lda MODE80                      ; $C958
    ora #$80                        ; $C95B
    sta MODE80                      ; $C95D

ESCNONE:
    jmp B_INPUT                     ; $C960

;; Escape T: clears mode bit 7.
ESCSPEC3:
    cmp #'T' & $7F                  ; $C963
    bne ESCNONE                     ; $C965
    lda MODE80                      ; $C967
    and #$7F                        ; $C96A
    sta MODE80                      ; $C96C
    jmp B_INPUT                     ; $C96F

;; The escape-mode keys and the control character each performs. ESCTAB ($C972) holds the keys and
;; ESCCHAR ($C983) the control characters, both with bit 7 clear; ESC_STAY in ESCCHAR keeps escape mode on.
ESC_STAY = $80
.set ESCKEYS, 0

.macro ESCKEY key, control, stay
    .ident(.sprintf("ESCKEY_%d", ESCKEYS)) = (key) & $7F
    .ident(.sprintf("ESCCHAR_%d", ESCKEYS)) = (control) & $7F | (stay)
    .set ESCKEYS, ESCKEYS + 1
.endmacro

    ESCKEY '@', KEY_FF, 0           ; home and clear the window
    ESCKEY 'A', KEY_FS, 0           ; right
    ESCKEY 'B', KEY_BS, 0           ; left
    ESCKEY 'C', KEY_LF, 0           ; down
    ESCKEY 'D', KEY_US, 0           ; up
    ESCKEY 'E', KEY_GS, 0           ; clear to the end of the line
    ESCKEY 'F', KEY_CTRL_K, 0       ; clear to the end of the window
    ESCKEY 'I', KEY_US, ESC_STAY    ; up
    ESCKEY 'J', KEY_BS, ESC_STAY    ; left
    ESCKEY 'K', KEY_FS, ESC_STAY    ; right
    ESCKEY 'M', KEY_LF, ESC_STAY    ; down
    ESCKEY '4', KEY_CTRL_Q, 0       ; 40 columns
    ESCKEY '8', KEY_CTRL_R, 0       ; 80 columns
    ESCKEY KEY_BS, KEY_BS, ESC_STAY ; the left arrow
    ESCKEY KEY_LF, KEY_LF, ESC_STAY ; the down arrow
    ESCKEY KEY_CTRL_K, KEY_US, ESC_STAY ; the up arrow
    ESCKEY KEY_RIGHT, KEY_FS, ESC_STAY ; the right arrow

ESCTAB:
.repeat ESCKEYS, index
    .byte .ident(.sprintf("ESCKEY_%d", index))
.endrepeat

ESCCHAR:
.repeat ESCKEYS, index
    .byte .ident(.sprintf("ESCCHAR_%d", index))
.endrepeat

;; Pascal status.
;; In:    A = the request
;; Out:   X = 0 for requests 0 and 1, 3 for any other,
;;          carry = set for request 0; for request 1, set if a key is waiting; clear for any other request
PSTATUS:
    tax                             ; $C994
    jsr PSETUP                      ; $C995
    txa                             ; $C998
    bne PSTATUS2                    ; $C999
    sec                             ; $C99B
    bcs PSTATUS4                    ; $C99C

PSTATUS2:
    cmp #$01                        ; $C99E
    beq PSTATUS3                    ; $C9A0
    ldx #$03                        ; $C9A2
    clc                             ; $C9A4
    rts                             ; $C9A5
    .byte $00, $00, $00, $00        ; $C9A6

;; A fixed entry: writes the current character ($067B) through JPWRITE.
C9ENTRY:
    lda CHAR                        ; $C9AA
    jmp JPWRITE                     ; $C9AD

;; Status request 1: carry = bit 7 of KBD.
PSTATUS3:
    lda KBD                         ; $C9B0
    asl a                           ; $C9B3

PSTATUS4:
    ldx #$00                        ; $C9B4
    rts                             ; $C9B6

;; Finishes an input key: right arrow (Control-U) picks up the character under the cursor instead. Tracks
;; quotes: a quote, or a backspace over one, toggles mode bit 4; inside quotes a quote, Control-X or return
;; clears it. With mode bit 7 set and outside quotes, lowercase is converted to uppercase. Returns the key.
NOESC:
    cmp #KEY_RIGHT                  ; $C9B7
    bne B_NOPICK                    ; $C9B9
    ldy OURCH                       ; $C9BB
    jsr PICK                        ; $C9BE
    ora #$80                        ; $C9C1
    sta CHAR                        ; $C9C3

B_NOPICK:
    lda MODE80                      ; $C9C6
    and #$10                        ; $C9C9
    bne B_CHKCAN                    ; $C9CB
    lda CHAR                        ; $C9CD
    cmp #'"'                        ; $C9D0
    beq B_FLIP                      ; $C9D2
    cmp #KEY_BS                     ; $C9D4
    bne B_FIXCHR                    ; $C9D6
    jsr GETPRIOR                    ; $C9D8
    bne B_FIXCHR                    ; $C9DB
    beq B_FLIP                      ; $C9DD

B_CHKCAN:
    lda CHAR                        ; $C9DF
    cmp #'"'                        ; $C9E2
    beq B_CANLIT                    ; $C9E4
    cmp #KEY_CTRL_X                 ; $C9E6
    beq B_CANLIT                    ; $C9E8
    cmp #KEY_CR                     ; $C9EA
    beq B_CANLIT                    ; $C9EC
    cmp #KEY_BS                     ; $C9EE
    bne B_FIXCHR                    ; $C9F0
    jsr GETPRIOR                    ; $C9F2
    bne B_FIXCHR                    ; $C9F5

B_FLIP:
    lda MODE80                      ; $C9F7
    eor #$10                        ; $C9FA
    sta MODE80                      ; $C9FC
    jmp B_FIXCHR                    ; $C9FF
