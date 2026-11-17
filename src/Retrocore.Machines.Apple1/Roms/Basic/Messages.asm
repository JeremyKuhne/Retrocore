;; APPLE-1 BASIC: THE MESSAGES AND INPUT OF NUMBERS ($EB00-$EBFF)
;;
;; The error messages, which <ERRORMESS> prints by their offset in this page, and the routines of INPUT for numbers,
;; which also handle an error in the line typed.
;;
;; INPUT reads a line and runs the tokenizer on it with a rule of its own, at $EC61: a list of numbers, each with an
;; optional sign, separated by commas. The numbers' tokens go after the line's text in IN, as a program line's do,
;; and each variable of the INPUT statement takes the next one. A line that is not a list of numbers is an error,
;; which here asks for the line again: RETYPE LINE.
;;
;; Part of Basic.asm; it follows VerbTables.asm, at $EB00.

;; Places a message: its characters with bit 7 set, except the last one's, which ends the message for <ERRORMESS>.
;; Parameters: text = the message
.macro MSG text
    .repeat .strlen(text) - 1, I
    .byte .strat(text, I)
    .endrepeat
    .byte .strat(text, .strlen(text) - 1) & $7F
.endmacro

;; The error messages: each is its characters with bit 7 set on all but the last.
;;
;; The routines that report an error load Y with the low byte of a message's address, its offset in this page. An
;; error prints *** (<ErrMsg13>), the message and ERR (<ErrMsg14>): *** >32767 ERR for the first.
;; See: <ERRMESS>, <ERRORMESS>, <PRINTERR>
ErrMsg00:
    MSG ">32767"                    ; $EB00
    .assert <ErrMsg00 = 0, "The messages are found by their offset in the page."

;; TOO LONG: a line with too many tokens, or a syntax nested too deeply.
ErrMsg01:
    MSG "TOO LONG"                  ; $EB06

;; SYNTAX: a line that matches no rule of the syntax table.
ErrMsg02:
    MSG "SYNTAX"                    ; $EB0E

;; MEM FULL: the program and the variables would overlap.
ErrMsg03:
    MSG "MEM FULL"                  ; $EB14

;; TOO MANY PARENS, which no routine reports.
ErrMsg04:
    MSG "TOO MANY PARENS"           ; $EB1C

;; STRING: a substring position out of range.
ErrMsg05:
    MSG "STRING"                    ; $EB2B

;; NO END: the program ran past its last line.
ErrMsg06:
    MSG "NO END"                    ; $EB31

;; BAD BRANCH: GOTO or GOSUB to a line that does not exist.
ErrMsg07:
    MSG "BAD BRANCH"                ; $EB37

;; >8 GOSUBS: a GOSUB with the GOSUB stack full.
ErrMsg08:
    MSG ">8 GOSUBS"                 ; $EB41

;; BAD RETURN: RETURN with no GOSUB active.
ErrMsg09:
    MSG "BAD RETURN"                ; $EB4A

;; >8 FORS: a FOR with the FOR stack full.
ErrMsg10:
    MSG ">8 FORS"                   ; $EB54

;; BAD NEXT: NEXT for a variable no FOR loop has.
ErrMsg11:
    MSG "BAD NEXT"                  ; $EB5B

;; STOPPED AT, which <STOPPED_AT> prints before the line number.
ErrMsg12:
    MSG "STOPPED AT "               ; $EB63

;; The *** that starts every error.
ErrMsg13:
    MSG "*** "                      ; $EB6E

;; ERR and a return, which end every error; the return, bit 7 clear, ends the message.
ErrMsg14:
    .byte " ERR", CR                ; $EB72

;; >255: a value that must fit in a byte.
ErrMsg15:
    MSG ">255"                      ; $EB77

;; RANGE: a value outside what a statement allows, such as a screen position.
ErrMsg16:
    MSG "RANGE"                     ; $EB7B

;; DIM: DIM of a variable that is not the newest.
ErrMsg17:
    MSG "DIM"                       ; $EB80

;; STR OVFL: a string longer than its DIM.
ErrMsg18:
    MSG "STR OVFL"                  ; $EB83

;; A backslash and a return, which <GETLINE> prints when a typed line is cancelled.
ErrMsg19:
    .byte '\', CR                   ; $EB8B

;; RETYPE LINE and a return, then ?, for a line INPUT could not read.
;;
;; The return has bit 7 set, so the message runs on into <ErrMsg21>.
ErrMsg20:
    .byte "RETYPE LINE", CR | $80   ; $EB8D

;; ?: INPUT's prompt for numbers.
ErrMsg21:
    .byte '?' & $7F                 ; $EB99

;; An error in a running program: stops it at the line, or, while INPUT tokenizes a typed line, asks for the line
;; again.
;;
;; <RUNFLAG> is $FF while a program runs and $FE while INPUT tokenizes, so bit 0 tells the two apart.
;; See: <ERRMESS>, <INPUTNUM>
RUNERROR:
    lsr RUNFLAG                     ; $EB9A
    bcc RUNERROR_1                  ; $EB9C
    jmp STOPPED_AT                  ; $EB9E

;; Puts back the noun stack and the 6502's stack INPUT had, prints RETYPE LINE and ?, and reads the line again.
RUNERROR_1:
    ldx ACC+1                       ; $EBA1
    txs                             ; $EBA3
    ldx ACC                         ; $EBA4
    ldy #<ErrMsg20                  ; $EBA6
    bne READNUMLINE                 ; $EBA8 always

;; INPUT of numbers without a prompt (token $54): prints ? and reads a line, then tokenizes it as a list of numbers.
;;
;; It comes back here, for a new line, when the variables outnumber the numbers typed.
;; In: X = the noun stack, its top entry the first variable
;; See: <COMMA_INPUT>, <GETLINE>
;; Entry: READNUMLINE = prints the message at offset Y instead of ?
INPUTNUM:
    ldy #<ErrMsg21                  ; $EBAA

READNUMLINE:
    jsr ERRORMESS                   ; $EBAC
    stx ACC                         ; $EBAF keep the noun stack and the 6502's stack, for RETYPE LINE
    tsx                             ; $EBB1
    stx ACC+1                       ; $EBB2
    ldy #$FE                        ; $EBB4
    sty RUNFLAG                     ; $EBB6 RUNFLAG = $FE: tokenizing for INPUT
    iny                             ; $EBB8
    sty TXTNDX                      ; $EBB9 $FF: before the line
    jsr GETLINE                     ; $EBBB read the line; Y = its end
    sty TOKNDX                      ; $EBBE the tokens go after it
    ldx #$20                        ; $EBC0 a new syntax stack
    lda #(SYNINPUT - SYNTABL - 1) / 2 ; $EBC2 the rule at $EC61: a list of numbers
    jsr STARTRULE                   ; $EBC4
    inc RUNFLAG                     ; $EBC7 RUNFLAG = $FF again
    ldx ACC                         ; $EBC9

;; Assigns the next number of the typed line to the variable (token $27, the comma between INPUT's variables, and
;; after <INPUTNUM>).
;;
;; <TXTNDX> keeps the place in the line's tokens. The INPUT rule writes $74 at the end of the line, $75 for a comma,
;; $76 and $77 for + and -, and each number as its marker digit and value; a - before the number negates it.
;; In: X = the noun stack, its top entry the variable
;; See: <ASSIGN_NUM>
COMMA_INPUT:
    ldy TXTNDX                      ; $EBCB
    asl a                           ; $EBCD

;; Steps over the tokens before the next number, keeping the last one in ACC, exclusive-ORed with $B0.
COMMA_INPUT_1:
    sta ACC                         ; $EBCE
    iny                             ; $EBD0
    lda IN,y                        ; $EBD1
    cmp #$74                        ; $EBD4
    beq INPUTNUM                    ; $EBD6 the end of the line: read another
    eor #'0'                        ; $EBD8 a digit marker gives 0-9
    cmp #10                         ; $EBDA
    bcs COMMA_INPUT_1               ; $EBDC
    iny                             ; $EBDE Y = the number's high byte
    iny                             ; $EBDF
    sty TXTNDX                      ; $EBE0
    lda IN,y                        ; $EBE2
    pha                             ; $EBE5
    lda IN-1,y                      ; $EBE6 the low byte
    ldy #$00                        ; $EBE9 push it as a number
    jsr PUSHNOUN                    ; $EBEB
    pla                             ; $EBEE
    sta NOUNSTKC,x                  ; $EBEF
    lda ACC                         ; $EBF1
    cmp #$C7                        ; $EBF3 $77, the - token, exclusive-ORed with $B0
    bne COMMA_INPUT_2               ; $EBF5
    jsr NEGATE                      ; $EBF7

;; Stores the number in the variable.
COMMA_INPUT_2:
    jmp ASSIGN_NUM                  ; $EBFA
    .byte $FF, $FF, $FF             ; $EBFD .align $0100 (3 bytes) unused bytes, to the end of the page
