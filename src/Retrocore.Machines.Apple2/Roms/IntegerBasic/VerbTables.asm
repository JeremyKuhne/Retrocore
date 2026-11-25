; retrocore: style=strict ignore=unlinked-name:BASIC -- BASIC and its keywords in prose
;; Integer BASIC: the token priorities and the verb tables
;;
;; Three tables of 128 entries, one per token, at $E980-$EAFF: the priorities by which the interpreter
;; (Interpreter.asm) orders the tokens of a statement, and the low and high bytes of each token's routine. Each
;; entry gives its token and, in its comment, the text `LIST` shows for it; where the same text has several tokens, the
;; note in parentheses says which use the token is for.
;;
;; The tokenizer's syntax table (SyntaxTable.asm) fixes which token a word gets, so each token has exactly one
;; meaning and its own routine: PRINT before a string ($61) and PRINT before a number ($62) go to different routines,
;; and so do the dozen commas. A token that is never run has <Verbs::NO_ROUTINE>: the end of the line and REM end a
;; line before their routine would run, quotes and the $ after a string name are taken as part of their operand, and
;; a few tokens are not used.
;;
;; The routines are named by their current names where this file defines them and by their old names elsewhere
;; until the parts are integrated.
;;
;; Part of IntegerBasic.asm; it follows ControlFlow.asm, at $E980.

; Shared constants: to move to Equates.asm at integration.

;; The index of an empty syntax stack, where the tokenizer starts a line: the frames are pushed from here down.
SYNTAX_STACK_EMPTY = $20

;; The token the INPUT rule (<Syntax::InputLineStart>) writes at the end of a line of numbers, and INPUT puts at the
;; start of the input buffer to mark the line used up.
TOKEN_INPUT_END = $80

;; The token of a comma between INPUT's numbers.
TOKEN_INPUT_COMMA = $81

;; The token of a plus sign before one of INPUT's numbers.
TOKEN_INPUT_PLUS = $82

;; The token of a minus sign before one of INPUT's numbers, which <Statements::InputNumberComma> negates.
TOKEN_INPUT_MINUS = $83

;; The token priorities and the verb tables, which the interpreter (<DOTOKEN>) reads by token.
.scope Verbs

;; The value of a token's entry in both <RoutinesLow> and <RoutinesHigh> when it has no routine: each holds $FF.
NO_ROUTINE = $FFFF

;; One entry of <Verbs::Priorities>: a token's two priorities, 0 to 15, with their bits interleaved.
;;
;; The arriving priority goes in bits 0, 2, 4 and 6 and the waiting one in bits 1, 3, 5 and 7, each in the same
;; order, so masking with $55 or $AA and comparing compares the priorities.
;; Parameters:
;;   token = the token, which is the entry's index
;;   arriving = the priority the token has when it arrives
;;   waiting = the priority it has while it waits
.macro Priority token, arriving, waiting
    .assert * - Verbs::Priorities = token, "Priorities is in token order."
    .assert arriving >= 0 && arriving <= 15 && waiting >= 0 && waiting <= 15, "A priority is 0 to 15."
    ArrivingBits .set (arriving & 1) | (arriving & 2) << 1 | (arriving & 4) << 2 | (arriving & 8) << 3
    WaitingBits .set (waiting & 1) | (waiting & 2) << 1 | (waiting & 4) << 2 | (waiting & 8) << 3
    .byte ArrivingBits | WaitingBits << 1
.endmacro

;; One entry of <Verbs::RoutinesLow>: the low byte of a token's routine.
;; Parameters:
;;   token = the token, which is the entry's index
;;   routine = the routine, or <Verbs::NO_ROUTINE>
.macro RoutineLow token, routine
    .assert * - Verbs::RoutinesLow = token, "RoutinesLow is in token order."
    .byte <routine
.endmacro

;; One entry of <Verbs::RoutinesHigh>: the high byte of a token's routine.
;; Parameters:
;;   token = the token, which is the entry's index
;;   routine = the routine, or <Verbs::NO_ROUTINE>
.macro RoutineHigh token, routine
    .assert * - Verbs::RoutinesHigh = token, "RoutinesHigh is in token order."
    .byte >routine
.endmacro

;; The priorities of each token: the first number after the token is its priority on arrival, the second its
;; priority while it waits.
;;
;; A waiting token runs when a token arrives whose arriving priority is no higher than its own waiting priority
;; (<DOTOKEN>). So * (8) runs before a + (7) that comes after it, operators run left to right among equals, a left
;; parenthesis (15 arriving, 0 waiting) holds everything until the right parenthesis comes, and a statement's
;; keyword (1 and 1) runs at the end of its statement. The end of the line and REM, at 0, make everything run.
;;
;; Most second parts of a statement arrive at 1 and so make the keyword before them run first: PLOT's keyword
;; takes the column (<GETVAL255>) before PLOT's comma runs. `POKE`'s comma arrives at 3 and waits above `POKE`
;; instead, so the comma takes the second value, the byte, and `POKE` runs last with the address. A unary sign or
;; `NOT` (10 arriving, 9 waiting) runs before a ^ that follows it, so -2^2 is 4.
;; See: <DOTOKEN>, <RoutinesLow>
;; Also: TABLE1 (IBSM)
Priorities:
    Priority $00, 0, 0                  ; (begins the line)
    Priority $01, 0, 0                  ; _ (end of line)
    Priority $02, 0, 0                  ; _ (empty line)
    Priority $03, 1, 15                 ; :
    Priority $04, 1, 1                  ; LOAD
    Priority $05, 1, 1                  ; SAVE
    Priority $06, 1, 1                  ; CON
    Priority $07, 1, 1                  ; RUN n
    Priority $08, 1, 1                  ; RUN
    Priority $09, 1, 1                  ; DEL
    Priority $0A, 1, 1                  ; DEL's ,
    Priority $0B, 1, 1                  ; NEW
    Priority $0C, 1, 1                  ; CLR
    Priority $0D, 1, 1                  ; AUTO
    Priority $0E, 1, 1                  ; AUTO's ,
    Priority $0F, 1, 1                  ; MAN
    Priority $10, 1, 1                  ; HIMEM:
    Priority $11, 1, 1                  ; LOMEM:
    Priority $12, 7, 7                  ; +
    Priority $13, 7, 7                  ; -
    Priority $14, 8, 8                  ; *
    Priority $15, 8, 8                  ; /
    Priority $16, 6, 6                  ; =
    Priority $17, 6, 6                  ; #
    Priority $18, 6, 6                  ; >=
    Priority $19, 6, 6                  ; >
    Priority $1A, 6, 6                  ; <=
    Priority $1B, 6, 6                  ; <>
    Priority $1C, 6, 6                  ; <
    Priority $1D, 4, 4                  ; AND
    Priority $1E, 3, 3                  ; OR
    Priority $1F, 8, 8                  ; MOD
    Priority $20, 9, 9                  ; ^
    Priority $21, 15, 15                ; +
    Priority $22, 15, 0                 ; ( (DIM string)
    Priority $23, 0, 0                  ; , (substring)
    Priority $24, 1, 15                 ; THEN (line number)
    Priority $25, 1, 15                 ; THEN (statement)
    Priority $26, 1, 1                  ; , (INPUT string)
    Priority $27, 1, 1                  ; , (INPUT number)
    Priority $28, 15, 15                ; " (open)
    Priority $29, 15, 15                ; " (close)
    Priority $2A, 15, 0                 ; ( (substring)
    Priority $2B, 15, 15                ; !
    Priority $2C, 15, 15                ; !
    Priority $2D, 15, 0                 ; ( (array)
    Priority $2E, 11, 11                ; PEEK
    Priority $2F, 11, 11                ; RND
    Priority $30, 11, 11                ; SGN
    Priority $31, 11, 11                ; ABS
    Priority $32, 11, 11                ; PDL
    Priority $33, 15, 15                ; RNDX
    Priority $34, 15, 0                 ; ( (DIM number)
    Priority $35, 10, 9                 ; + (unary)
    Priority $36, 10, 9                 ; - (unary)
    Priority $37, 10, 9                 ; NOT
    Priority $38, 15, 0                 ; ( (expression)
    Priority $39, 12, 12                ; = (strings)
    Priority $3A, 12, 12                ; # (strings)
    Priority $3B, 11, 11                ; LEN(
    Priority $3C, 11, 11                ; ASC(
    Priority $3D, 15, 0                 ; SCRN(
    Priority $3E, 1, 0                  ; , (SCRN)
    Priority $3F, 15, 0                 ; ( (function)
    Priority $40, 15, 15                ; $ (string name)
    Priority $41, 15, 15                ; $
    Priority $42, 15, 0                 ; ( (string store)
    Priority $43, 1, 1                  ; , (DIM string)
    Priority $44, 1, 1                  ; , (DIM number)
    Priority $45, 1, 1                  ; ; (string)
    Priority $46, 1, 1                  ; ; (number)
    Priority $47, 1, 1                  ; ; (end)
    Priority $48, 1, 1                  ; , (string)
    Priority $49, 1, 1                  ; , (number)
    Priority $4A, 1, 1                  ; , (end)
    Priority $4B, 1, 1                  ; TEXT
    Priority $4C, 1, 1                  ; GR
    Priority $4D, 1, 1                  ; CALL
    Priority $4E, 1, 1                  ; DIM (string)
    Priority $4F, 1, 1                  ; DIM (number)
    Priority $50, 1, 1                  ; TAB
    Priority $51, 1, 1                  ; END
    Priority $52, 1, 1                  ; INPUT (string)
    Priority $53, 1, 1                  ; INPUT (prompt)
    Priority $54, 1, 1                  ; INPUT (number)
    Priority $55, 1, 1                  ; FOR
    Priority $56, 1, 1                  ; = (FOR)
    Priority $57, 1, 1                  ; TO
    Priority $58, 1, 1                  ; STEP
    Priority $59, 1, 1                  ; NEXT
    Priority $5A, 1, 1                  ; NEXT's ,
    Priority $5B, 1, 1                  ; RETURN
    Priority $5C, 1, 1                  ; GOSUB
    Priority $5D, 0, 0                  ; REM
    Priority $5E, 1, 15                 ; LET
    Priority $5F, 1, 1                  ; GOTO
    Priority $60, 15, 1                 ; IF
    Priority $61, 1, 1                  ; PRINT (string)
    Priority $62, 1, 1                  ; PRINT (number)
    Priority $63, 1, 1                  ; PRINT
    Priority $64, 1, 1                  ; POKE
    Priority $65, 3, 1                  ; POKE's ,
    Priority $66, 1, 1                  ; COLOR=
    Priority $67, 1, 1                  ; PLOT
    Priority $68, 1, 1                  ; PLOT's ,
    Priority $69, 1, 1                  ; HLIN
    Priority $6A, 1, 1                  ; HLIN's ,
    Priority $6B, 1, 1                  ; AT (HLIN)
    Priority $6C, 1, 1                  ; VLIN
    Priority $6D, 1, 1                  ; VLIN's ,
    Priority $6E, 1, 1                  ; AT (VLIN)
    Priority $6F, 1, 1                  ; VTAB
    Priority $70, 1, 1                  ; = (string)
    Priority $71, 1, 1                  ; = (number)
    Priority $72, 0, 15                 ; )
    Priority $73, 15, 15                ; )
    Priority $74, 1, 1                  ; LIST n
    Priority $75, 1, 1                  ; LIST's ,
    Priority $76, 1, 1                  ; LIST
    Priority $77, 1, 1                  ; POP
    Priority $78, 1, 1                  ; NODSP (string)
    Priority $79, 1, 1                  ; NODSP (number)
    Priority $7A, 1, 1                  ; NOTRACE
    Priority $7B, 1, 1                  ; DSP (string)
    Priority $7C, 1, 1                  ; DSP (number)
    Priority $7D, 1, 1                  ; TRACE
    Priority $7E, 1, 1                  ; PR#
    Priority $7F, 1, 1                  ; IN#

;; The low bytes of each token's routine, which the interpreter puts in <Accumulator> and calls through it
;; (<DOTOKEN_2>).
;;
;; TEXT and GR are the Monitor's own routines, <SetText> and <SetGraphics>. Several tokens share a routine: every
;; left parenthesis but a substring's, an array's and a string store's is <LEFT_PAREN>, and # and <> are both
;; <NOTEQUAL_NUM>.
;; See: <RoutinesHigh>, <Priorities>
;; Also: VERBADRL (IBSM)
RoutinesLow:
    RoutineLow $00, BEGIN_LINE                      ; (begins the line)
    RoutineLow $01, NO_ROUTINE                      ; _ (end of line)
    RoutineLow $02, NO_ROUTINE                      ; _ (empty line)
    RoutineLow $03, COLON                           ; :
    RoutineLow $04, LOAD                            ; LOAD
    RoutineLow $05, VSAVE                           ; SAVE
    RoutineLow $06, CON                             ; CON
    RoutineLow $07, RUNNUM                          ; RUN n
    RoutineLow $08, RUN                             ; RUN
    RoutineLow $09, DEL                             ; DEL
    RoutineLow $0A, COMMA_DEL                       ; DEL's ,
    RoutineLow $0B, NEW                             ; NEW
    RoutineLow $0C, CLR                             ; CLR
    RoutineLow $0D, AUTO                            ; AUTO
    RoutineLow $0E, COMMA_AUTO                      ; AUTO's ,
    RoutineLow $0F, MAN                             ; MAN
    RoutineLow $10, VHIMEM                          ; HIMEM:
    RoutineLow $11, VLOMEM                          ; LOMEM:
    RoutineLow $12, PLUS                            ; +
    RoutineLow $13, SUBTRACT                        ; -
    RoutineLow $14, MULT                            ; *
    RoutineLow $15, DIVIDE                          ; /
    RoutineLow $16, EQUAL_NUM                       ; =
    RoutineLow $17, NOTEQUAL_NUM                    ; #
    RoutineLow $18, GREATEQ                         ; >=
    RoutineLow $19, GREATER                         ; >
    RoutineLow $1A, LESSEQ                          ; <=
    RoutineLow $1B, NOTEQUAL_NUM                    ; <>
    RoutineLow $1C, LESS                            ; <
    RoutineLow $1D, VAND                            ; AND
    RoutineLow $1E, VOR                             ; OR
    RoutineLow $1F, MOD                             ; MOD
    RoutineLow $20, EXP                             ; ^
    RoutineLow $21, NO_ROUTINE                      ; +
    RoutineLow $22, LEFT_PAREN                      ; ( (DIM string)
    RoutineLow $23, COMMA_SUBSTR                    ; , (substring)
    RoutineLow $24, GOTO                            ; THEN (line number)
    RoutineLow $25, LET                             ; THEN (statement)
    RoutineLow $26, INPUT_STRVAR                    ; , (INPUT string)
    RoutineLow $27, Statements::InputNumberComma    ; , (INPUT number)
    RoutineLow $28, NO_ROUTINE                      ; " (open)
    RoutineLow $29, NO_ROUTINE                      ; " (close)
    RoutineLow $2A, PAREN_SUBSTR                    ; ( (substring)
    RoutineLow $2B, NO_ROUTINE                      ; !
    RoutineLow $2C, NO_ROUTINE                      ; !
    RoutineLow $2D, PAREN_ARRAY                     ; ( (array)
    RoutineLow $2E, PEEK                            ; PEEK
    RoutineLow $2F, RND                             ; RND
    RoutineLow $30, SGN                             ; SGN
    RoutineLow $31, ABS                             ; ABS
    RoutineLow $32, PDL                             ; PDL
    RoutineLow $33, NO_ROUTINE                      ; RNDX
    RoutineLow $34, LEFT_PAREN                      ; ( (DIM number)
    RoutineLow $35, POSITIVE                        ; + (unary)
    RoutineLow $36, NEGATE                          ; - (unary)
    RoutineLow $37, NOT                             ; NOT
    RoutineLow $38, LEFT_PAREN                      ; ( (expression)
    RoutineLow $39, EQ_STR                          ; = (strings)
    RoutineLow $3A, NE_STR                          ; # (strings)
    RoutineLow $3B, LEN                             ; LEN(
    RoutineLow $3C, ASC                             ; ASC(
    RoutineLow $3D, SCRN                            ; SCRN(
    RoutineLow $3E, COMMA_SCRN                      ; , (SCRN)
    RoutineLow $3F, LEFT_PAREN                      ; ( (function)
    RoutineLow $40, NO_ROUTINE                      ; $ (string name)
    RoutineLow $41, NO_ROUTINE                      ; $
    RoutineLow $42, PAREN_STRDEST                   ; ( (string store)
    RoutineLow $43, DIMSTR                          ; , (DIM string)
    RoutineLow $44, DIMNUM                          ; , (DIM number)
    RoutineLow $45, PRINTSTR                        ; ; (string)
    RoutineLow $46, PRINTNUM                        ; ; (number)
    RoutineLow $47, SEMI_END                        ; ; (end)
    RoutineLow $48, COMMA_PRSTR                     ; , (string)
    RoutineLow $49, COMMA_PRNUM                     ; , (number)
    RoutineLow $4A, COMMA_PREND                     ; , (end)
    RoutineLow $4B, SetText                         ; TEXT
    RoutineLow $4C, SetGraphics                     ; GR
    RoutineLow $4D, CALL                            ; CALL
    RoutineLow $4E, DIMSTR                          ; DIM (string)
    RoutineLow $4F, DIMNUM                          ; DIM (number)
    RoutineLow $50, TAB                             ; TAB
    RoutineLow $51, END                             ; END
    RoutineLow $52, INPUT_STRVAR                    ; INPUT (string)
    RoutineLow $53, INPUT_PROMPT                    ; INPUT (prompt)
    RoutineLow $54, Statements::InputNumber         ; INPUT (number)
    RoutineLow $55, FOR                             ; FOR
    RoutineLow $56, ASSIGN_NUM                      ; = (FOR)
    RoutineLow $57, TO                              ; TO
    RoutineLow $58, STEP                            ; STEP
    RoutineLow $59, NEXT                            ; NEXT
    RoutineLow $5A, NEXT                            ; NEXT's ,
    RoutineLow $5B, RETURN                          ; RETURN
    RoutineLow $5C, GOSUB                           ; GOSUB
    RoutineLow $5D, NO_ROUTINE                      ; REM
    RoutineLow $5E, LET                             ; LET
    RoutineLow $5F, GOTO                            ; GOTO
    RoutineLow $60, IF                              ; IF
    RoutineLow $61, PRINTSTR                        ; PRINT (string)
    RoutineLow $62, PRINTNUM                        ; PRINT (number)
    RoutineLow $63, PRINT_CR                        ; PRINT
    RoutineLow $64, POKE                            ; POKE
    RoutineLow $65, GETVAL255                       ; POKE's ,
    RoutineLow $66, COLOR_EQ                        ; COLOR=
    RoutineLow $67, GETVAL255                       ; PLOT
    RoutineLow $68, COMMA_PLOT                      ; PLOT's ,
    RoutineLow $69, GETVAL255                       ; HLIN
    RoutineLow $6A, COMMA_HLIN                      ; HLIN's ,
    RoutineLow $6B, AT_HLIN                         ; AT (HLIN)
    RoutineLow $6C, GETVAL255                       ; VLIN
    RoutineLow $6D, COMMA_VLIN                      ; VLIN's ,
    RoutineLow $6E, AT_VLIN                         ; AT (VLIN)
    RoutineLow $6F, IVTAB                           ; VTAB
    RoutineLow $70, LET_STR                         ; = (string)
    RoutineLow $71, ASSIGN_NUM                      ; = (number)
    RoutineLow $72, RIGHT_PAREN                     ; )
    RoutineLow $73, NO_ROUTINE                      ; )
    RoutineLow $74, LISTNUM                         ; LIST n
    RoutineLow $75, COMMA_LIST                      ; LIST's ,
    RoutineLow $76, LIST                            ; LIST
    RoutineLow $77, POP                             ; POP
    RoutineLow $78, NODSP_STR                       ; NODSP (string)
    RoutineLow $79, NODSP_NUM                       ; NODSP (number)
    RoutineLow $7A, NOTRACE                         ; NOTRACE
    RoutineLow $7B, DSP_STR                         ; DSP (string)
    RoutineLow $7C, DSP_NUM                         ; DSP (number)
    RoutineLow $7D, TRACE                           ; TRACE
    RoutineLow $7E, PRSLOT                          ; PR#
    RoutineLow $7F, INSLOT                          ; IN#

;; The high bytes of each token's routine, as <RoutinesLow>.
;; Also: VERBADRH (IBSM)
RoutinesHigh:
    RoutineHigh $00, BEGIN_LINE                     ; (begins the line)
    RoutineHigh $01, NO_ROUTINE                     ; _ (end of line)
    RoutineHigh $02, NO_ROUTINE                     ; _ (empty line)
    RoutineHigh $03, COLON                          ; :
    RoutineHigh $04, LOAD                           ; LOAD
    RoutineHigh $05, VSAVE                          ; SAVE
    RoutineHigh $06, CON                            ; CON
    RoutineHigh $07, RUNNUM                         ; RUN n
    RoutineHigh $08, RUN                            ; RUN
    RoutineHigh $09, DEL                            ; DEL
    RoutineHigh $0A, COMMA_DEL                      ; DEL's ,
    RoutineHigh $0B, NEW                            ; NEW
    RoutineHigh $0C, CLR                            ; CLR
    RoutineHigh $0D, AUTO                           ; AUTO
    RoutineHigh $0E, COMMA_AUTO                     ; AUTO's ,
    RoutineHigh $0F, MAN                            ; MAN
    RoutineHigh $10, VHIMEM                         ; HIMEM:
    RoutineHigh $11, VLOMEM                         ; LOMEM:
    RoutineHigh $12, PLUS                           ; +
    RoutineHigh $13, SUBTRACT                       ; -
    RoutineHigh $14, MULT                           ; *
    RoutineHigh $15, DIVIDE                         ; /
    RoutineHigh $16, EQUAL_NUM                      ; =
    RoutineHigh $17, NOTEQUAL_NUM                   ; #
    RoutineHigh $18, GREATEQ                        ; >=
    RoutineHigh $19, GREATER                        ; >
    RoutineHigh $1A, LESSEQ                         ; <=
    RoutineHigh $1B, NOTEQUAL_NUM                   ; <>
    RoutineHigh $1C, LESS                           ; <
    RoutineHigh $1D, VAND                           ; AND
    RoutineHigh $1E, VOR                            ; OR
    RoutineHigh $1F, MOD                            ; MOD
    RoutineHigh $20, EXP                            ; ^
    RoutineHigh $21, NO_ROUTINE                     ; +
    RoutineHigh $22, LEFT_PAREN                     ; ( (DIM string)
    RoutineHigh $23, COMMA_SUBSTR                   ; , (substring)
    RoutineHigh $24, GOTO                           ; THEN (line number)
    RoutineHigh $25, LET                            ; THEN (statement)
    RoutineHigh $26, INPUT_STRVAR                   ; , (INPUT string)
    RoutineHigh $27, Statements::InputNumberComma   ; , (INPUT number)
    RoutineHigh $28, NO_ROUTINE                     ; " (open)
    RoutineHigh $29, NO_ROUTINE                     ; " (close)
    RoutineHigh $2A, PAREN_SUBSTR                   ; ( (substring)
    RoutineHigh $2B, NO_ROUTINE                     ; !
    RoutineHigh $2C, NO_ROUTINE                     ; !
    RoutineHigh $2D, PAREN_ARRAY                    ; ( (array)
    RoutineHigh $2E, PEEK                           ; PEEK
    RoutineHigh $2F, RND                            ; RND
    RoutineHigh $30, SGN                            ; SGN
    RoutineHigh $31, ABS                            ; ABS
    RoutineHigh $32, PDL                            ; PDL
    RoutineHigh $33, NO_ROUTINE                     ; RNDX
    RoutineHigh $34, LEFT_PAREN                     ; ( (DIM number)
    RoutineHigh $35, POSITIVE                       ; + (unary)
    RoutineHigh $36, NEGATE                         ; - (unary)
    RoutineHigh $37, NOT                            ; NOT
    RoutineHigh $38, LEFT_PAREN                     ; ( (expression)
    RoutineHigh $39, EQ_STR                         ; = (strings)
    RoutineHigh $3A, NE_STR                         ; # (strings)
    RoutineHigh $3B, LEN                            ; LEN(
    RoutineHigh $3C, ASC                            ; ASC(
    RoutineHigh $3D, SCRN                           ; SCRN(
    RoutineHigh $3E, COMMA_SCRN                     ; , (SCRN)
    RoutineHigh $3F, LEFT_PAREN                     ; ( (function)
    RoutineHigh $40, NO_ROUTINE                     ; $ (string name)
    RoutineHigh $41, NO_ROUTINE                     ; $
    RoutineHigh $42, PAREN_STRDEST                  ; ( (string store)
    RoutineHigh $43, DIMSTR                         ; , (DIM string)
    RoutineHigh $44, DIMNUM                         ; , (DIM number)
    RoutineHigh $45, PRINTSTR                       ; ; (string)
    RoutineHigh $46, PRINTNUM                       ; ; (number)
    RoutineHigh $47, SEMI_END                       ; ; (end)
    RoutineHigh $48, COMMA_PRSTR                    ; , (string)
    RoutineHigh $49, COMMA_PRNUM                    ; , (number)
    RoutineHigh $4A, COMMA_PREND                    ; , (end)
    RoutineHigh $4B, SetText                        ; TEXT
    RoutineHigh $4C, SetGraphics                    ; GR
    RoutineHigh $4D, CALL                           ; CALL
    RoutineHigh $4E, DIMSTR                         ; DIM (string)
    RoutineHigh $4F, DIMNUM                         ; DIM (number)
    RoutineHigh $50, TAB                            ; TAB
    RoutineHigh $51, END                            ; END
    RoutineHigh $52, INPUT_STRVAR                   ; INPUT (string)
    RoutineHigh $53, INPUT_PROMPT                   ; INPUT (prompt)
    RoutineHigh $54, Statements::InputNumber        ; INPUT (number)
    RoutineHigh $55, FOR                            ; FOR
    RoutineHigh $56, ASSIGN_NUM                     ; = (FOR)
    RoutineHigh $57, TO                             ; TO
    RoutineHigh $58, STEP                           ; STEP
    RoutineHigh $59, NEXT                           ; NEXT
    RoutineHigh $5A, NEXT                           ; NEXT's ,
    RoutineHigh $5B, RETURN                         ; RETURN
    RoutineHigh $5C, GOSUB                          ; GOSUB
    RoutineHigh $5D, NO_ROUTINE                     ; REM
    RoutineHigh $5E, LET                            ; LET
    RoutineHigh $5F, GOTO                           ; GOTO
    RoutineHigh $60, IF                             ; IF
    RoutineHigh $61, PRINTSTR                       ; PRINT (string)
    RoutineHigh $62, PRINTNUM                       ; PRINT (number)
    RoutineHigh $63, PRINT_CR                       ; PRINT
    RoutineHigh $64, POKE                           ; POKE
    RoutineHigh $65, GETVAL255                      ; POKE's ,
    RoutineHigh $66, COLOR_EQ                       ; COLOR=
    RoutineHigh $67, GETVAL255                      ; PLOT
    RoutineHigh $68, COMMA_PLOT                     ; PLOT's ,
    RoutineHigh $69, GETVAL255                      ; HLIN
    RoutineHigh $6A, COMMA_HLIN                     ; HLIN's ,
    RoutineHigh $6B, AT_HLIN                        ; AT (HLIN)
    RoutineHigh $6C, GETVAL255                      ; VLIN
    RoutineHigh $6D, COMMA_VLIN                     ; VLIN's ,
    RoutineHigh $6E, AT_VLIN                        ; AT (VLIN)
    RoutineHigh $6F, IVTAB                          ; VTAB
    RoutineHigh $70, LET_STR                        ; = (string)
    RoutineHigh $71, ASSIGN_NUM                     ; = (number)
    RoutineHigh $72, RIGHT_PAREN                    ; )
    RoutineHigh $73, NO_ROUTINE                     ; )
    RoutineHigh $74, LISTNUM                        ; LIST n
    RoutineHigh $75, COMMA_LIST                     ; LIST's ,
    RoutineHigh $76, LIST                           ; LIST
    RoutineHigh $77, POP                            ; POP
    RoutineHigh $78, NODSP_STR                      ; NODSP (string)
    RoutineHigh $79, NODSP_NUM                      ; NODSP (number)
    RoutineHigh $7A, NOTRACE                        ; NOTRACE
    RoutineHigh $7B, DSP_STR                        ; DSP (string)
    RoutineHigh $7C, DSP_NUM                        ; DSP (number)
    RoutineHigh $7D, TRACE                          ; TRACE
    RoutineHigh $7E, PRSLOT                         ; PR#
    RoutineHigh $7F, INSLOT                         ; IN#

.endscope
