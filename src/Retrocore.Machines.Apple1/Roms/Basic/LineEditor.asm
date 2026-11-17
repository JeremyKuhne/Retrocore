;; APPLE-1 BASIC: THE COMMAND LOOP, PROGRAM EDITING AND OUTPUT ($E2B0-$E3EC)
;;
;; The cold and warm starts and the loop that reads each line typed at the > prompt, has it tokenized, and either
;; runs it at once or stores it in the program; DEL, which removes lines; the routines that print an error message
;; and return to the prompt; and COUT, which prints a character on the terminal.
;;
;; A typed line goes into IN ($0200) and its tokens after it in the same buffer. A line that starts with a number is
;; stored: its tokens already have the stored form, except that the constant marker of the line number becomes the
;; line's length. Storing a line first deletes any line with the same number, then moves the lines below the place
;; it goes down by its length and copies it into the gap. A number alone deletes the line.
;;
;; Part of Basic.asm; it follows Strings.asm, at $E2B0.

;; The cold start: sets up memory for a 4K machine and erases any program, then falls into the warm start.
;; See: <SETMEM4K>, <BASIC>
COLD:
    jsr SETMEM4K                    ; $E2B0

;; The warm start: prints a return, then reads and handles lines typed at the > prompt, forever.
;;
;; In AUTO mode the prompt is followed by the next line number, which the line typed starts with as if it had been
;; typed: <PRDEC> also puts the digits in <IN>.
;; See: <CMDLINE>, <COLD>
;; Entry: CMDPROMPT = without the return; the end of each line, and errors, come back here
WARM:
    jsr CROUT                       ; $E2B3

CMDPROMPT:
    lsr RUNFLAG                     ; $E2B6 not running a program
    lda #'>'                        ; $E2B8
    jsr COUT                        ; $E2BA
    ldy #$00                        ; $E2BD
    sty LEADZR                      ; $E2BF no blanks before the line number
    bit AUTOFLAG                    ; $E2C1
    bpl CMDLINE                     ; $E2C3 not AUTO
    ldx AUTOLN                      ; $E2C5
    lda AUTOLN+1                    ; $E2C7
    jsr PRDEC                       ; $E2C9
    lda #BLANK+$80                  ; $E2CC
    jsr COUT                        ; $E2CE

;; Reads a line and tokenizes it, then runs it or stores it.
;;
;; The tokenizer starts at the top of the syntax table, $EDFF, with <TXTNDX> before the line's first character and
;; <TOKNDX> at the end of its text, where the tokens will go. When it returns, <PX> is set to the first token.
CMDLINE:
    ldx #$FF                        ; $E2D1 a fresh 6502 stack
    txs                             ; $E2D3
    jsr GETLINE_NEXT                ; $E2D4 Y = the length of the line
    sty TOKNDX                      ; $E2D7
    txa                             ; $E2D9
    sta TXTNDX                      ; $E2DA X = $FF: before the first character
    ldx #$20                        ; $E2DC an empty syntax stack
    jsr STARTRULE                   ; $E2DE A = $FF: the rule at $EDFF, a whole line
    lda TXTNDX                      ; $E2E1 carry is set: PX = $0200 + TXTNDX + 1, the first token
    adc #$00                        ; $E2E3
    sta PX                          ; $E2E5
    lda #$00                        ; $E2E7
    tax                             ; $E2E9
    adc #$02                        ; $E2EA
    sta PX+1                        ; $E2EC
    lda (PX,x)                      ; $E2EE the first token
    and #$F0                        ; $E2F0
    cmp #'0'                        ; $E2F2 a constant: the line starts with its number
    beq STORELINE                   ; $E2F4
    jmp RUNLOOP                     ; $E2F6 no number: run the line now

;; Stores a numbered line in the program, replacing any line with the same number, or deletes the line if nothing
;; follows its number.
;; Errors: MEM FULL if the line would reach the variables
STORELINE:
    ldy #$02                        ; $E2F9

STORELINE_1:
    lda (PX),y                      ; $E2FB ACC = the line number, from the constant after its marker
    sta ACC-1,y                     ; $E2FD
    dey                             ; $E300
    bne STORELINE_1                 ; $E301
    jsr DELLINE                     ; $E303 delete the old line; P1 = where the new one goes
    lda TOKNDX                      ; $E306 the line's length: its tokens, from the marker to the end
    sbc TXTNDX                      ; $E308
    cmp #$04                        ; $E30A only the number and the end of the line
    beq CMDPROMPT                   ; $E30C
    sta (PX),y                      ; $E30E the length replaces the marker: the stored form
    lda PP                          ; $E310 the new start of the program, P2 = PP - length
    sbc (PX),y                      ; $E312
    sta P2                          ; $E314
    lda PP+1                        ; $E316
    sbc #$00                        ; $E318
    sta P2+1                        ; $E31A
    lda P2                          ; $E31C it must stay above the variables
    cmp PV                          ; $E31E
    lda P2+1                        ; $E320
    sbc PV+1                        ; $E322
    bcc MEMFULL                     ; $E324

;; Moves each line below the insertion point down by the new line's length, from <PP> up to <P1>.
STORELINE_2:
    lda PP                          ; $E326
    sbc (PX),y                      ; $E328
    sta P3                          ; $E32A
    lda PP+1                        ; $E32C
    sbc #$00                        ; $E32E
    sta P3+1                        ; $E330
    lda (PP),y                      ; $E332
    sta (P3),y                      ; $E334
    inc PP                          ; $E336
    bne STORELINE_3                 ; $E338
    inc PP+1                        ; $E33A

STORELINE_3:
    lda P1                          ; $E33C
    cmp PP                          ; $E33E
    lda P1+1                        ; $E340
    sbc PP+1                        ; $E342
    bcs STORELINE_2                 ; $E344

;; Sets <PP> to the new start of the program, then copies the new line into the gap at <P3>.
STORELINE_4:
    lda P2,x                        ; $E346
    sta PP,x                        ; $E348
    dex                             ; $E34A
    bpl STORELINE_4                 ; $E34B
    lda (PX),y                      ; $E34D
    tay                             ; $E34F

STORELINE_5:
    dey                             ; $E350
    lda (PX),y                      ; $E351
    sta (P3),y                      ; $E353
    tya                             ; $E355
    bne STORELINE_5                 ; $E356
    bit AUTOFLAG                    ; $E358
    bpl STORELINE_6                 ; $E35A AUTO: the next line number
@Loop:
    lda AUTOLN+1,x                  ; $E35C
    adc AUTOINC+1,x                 ; $E35E
    sta AUTOLN+1,x                  ; $E360
    inx                             ; $E362
    beq @Loop                       ; $E363 X = $FF then 0: both bytes

;; Goes back to the prompt for the next line; the branch reaches CMDPROMPT through <LEAVELINE>.
STORELINE_6:
    bpl LEAVELINE                   ; $E365
    brk                             ; $E367 unused bytes
    .byte $00, $00, $00             ; $E368

;; The MEM FULL error.
MEMFULL:
    ldy #<ErrMsg03                  ; $E36B
    bne ERRMESS                     ; $E36D

;; The comma of DEL (token $0A): DEL m,n deletes the lines from where <DEL> left off through line n.
;;
;; <DEL> has removed line m, if it existed, and left the address of the line after it in <P1>.
;; In: X = the noun stack, its top entry the last line number
;; See: <DEL>, <FINDP3POP>
COMMA_DEL:
    jsr GET16BIT                    ; $E36F
    lda P1                          ; $E372
    sta P3                          ; $E374
    lda P1+1                        ; $E376
    sta P3+1                        ; $E378
    jsr FINDP3POP                   ; $E37A find line n, from P3; P3 = the line after it
    lda P1                          ; $E37D
    sta P2                          ; $E37F
    lda P1+1                        ; $E381
    sta P2+1                        ; $E383
    bne CLOSEGAP                    ; $E385 always: the program is not in page 0

;; DEL (token $09): deletes the line with the number on the noun stack, if there is one.
;; In: X = the noun stack, its top entry the line number
;; See: <COMMA_DEL>
DEL:
    jsr GET16BIT                    ; $E387

;; Deletes the line numbered ACC if it exists, leaving <P1> at the line after it: where a line numbered ACC goes.
;;
;; <FINDLINE> leaves <P3> after the line when it exists, and equal to <P2> when it does not, so then nothing moves.
;; In: ACC = the line number
;; Out: P1 = the line after it
;; Uses: A, Y, P2, P3, PP
DELLINE:
    jsr FINDLINE                    ; $E38A
    lda P3                          ; $E38D
    sta P1                          ; $E38F
    lda P3+1                        ; $E391
    sta P1+1                        ; $E393

;; Moves the bytes from <PP> up to <P2> to end at <P3>, from the top down, removing what lay between <P2> and <P3>.
;; In: P2 = the end of what is kept, P3 = where it ends up
;; Out: PP = the new start of the program, Y = 0
;; Uses: A, P2, P3
CLOSEGAP:
    ldy #$00                        ; $E395

CLOSEGAP_1:
    lda PP                          ; $E397
    cmp P2                          ; $E399
    lda PP+1                        ; $E39B
    sbc P2+1                        ; $E39D
    bcs CLOSEGAP_4                  ; $E39F everything is moved
    lda P2                          ; $E3A1
    bne CLOSEGAP_2                  ; $E3A3
    dec P2+1                        ; $E3A5

CLOSEGAP_2:
    dec P2                          ; $E3A7
    lda P3                          ; $E3A9
    bne CLOSEGAP_3                  ; $E3AB
    dec P3+1                        ; $E3AD

CLOSEGAP_3:
    dec P3                          ; $E3AF
    lda (P2),y                      ; $E3B1
    sta (P3),y                      ; $E3B3
    bcc CLOSEGAP_1                  ; $E3B5

;; Sets <PP> to <P3>, the new start of the program.
CLOSEGAP_4:
    lda P3                          ; $E3B7
    sta PP                          ; $E3B9
    lda P3+1                        ; $E3BB
    sta PP+1                        ; $E3BD
    rts                             ; $E3BF

;; Prints the characters of a message until its last one.
;;
;; The messages (<ErrMsg00>) have bit 7 set on every character but the last.
ERRORMESS_1:
    jsr COUT                        ; $E3C0
    iny                             ; $E3C3

;; Prints the message at offset Y in the message table.
;; In: Y = the message's offset from <ErrMsg00>
;; Out: Y = the offset of its last character
;; Keeps: X
;; See: <ErrMsg00>, <PRINTERR>
ERRORMESS:
    lda ErrMsg00,y                  ; $E3C4
    bmi ERRORMESS_1                 ; $E3C7 the last character falls into COUT

;; Prints the character in A on the terminal, counting the columns in <CH>.
;;
;; A return sets <CH> back to the start of the line. The terminal takes a character only as its beam passes the
;; cursor, so COUT waits while <DSP> reads busy; output runs at about 60 characters a second. The terminal ignores
;; bit 7.
;; In: A = the character
;; Keeps: A, X, Y
;; Entry: CROUT = prints a return
;; See: <DSP>, <CH>
COUT:
    cmp #CR+$80                     ; $E3C9
    bne COUT_1                      ; $E3CB

CROUT:
    lda #$00                        ; $E3CD
    sta CH                          ; $E3CF
    lda #CR+$80                     ; $E3D1

COUT_1:
    inc CH                          ; $E3D3

COUT_WAIT:
    bit DSP                         ; $E3D5
    bmi COUT_WAIT                   ; $E3D8 the terminal is still taking the last character
    sta DSP                         ; $E3DA
    rts                             ; $E3DD

;; The TOO LONG error.
ErrTooLong:
    ldy #<ErrMsg01                  ; $E3DE

;; Reports an error: prints *** and the message at offset Y, then ERR, and leaves the statement.
;;
;; Typed lines go back to the prompt. In a running program <RUNERROR> decides: the error stops the program with the
;; line's number, unless INPUT is reading numbers, which asks for the line again.
;; In: Y = the message's offset from <ErrMsg00>
;; See: <PRINTERR>, <RUNERROR>
ERRMESS:
    jsr PRINTERR                    ; $E3E0
    bit RUNFLAG                     ; $E3E3

;; Leaves for the prompt, or for <RUNERROR> while a program runs (N set).
LEAVELINE:
    bmi LEAVELINE_1                 ; $E3E5
    jmp CMDPROMPT                   ; $E3E7

LEAVELINE_1:
    jmp RUNERROR                    ; $E3EA
