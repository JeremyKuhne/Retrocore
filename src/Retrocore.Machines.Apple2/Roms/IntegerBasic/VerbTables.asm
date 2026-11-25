; retrocore: style=strict
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
;; Part of IntegerBasic.asm; it follows ControlFlow.asm, at $E980.

;; The token priorities and the verb tables, which the interpreter (<Interpreter::RunLine::Arrive>) reads by token.
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
;; (<Interpreter::RunLine::Arrive>). So * (8) runs before a + (7) that comes after it, operators run left to right among
;; equals, a left parenthesis (15 arriving, 0 waiting) holds everything until the right parenthesis comes, and a
;; statement's keyword (1 and 1) runs at the end of its statement. The end of the line and REM, at 0, make everything
;; run.
;;
;; Most second parts of a statement arrive at 1 and so make the keyword before them run first: PLOT's keyword
;; takes the column (<Statements::FirstValue>) before PLOT's comma runs. `POKE`'s comma arrives at 3 and waits above
;; `POKE` instead, so the comma takes the second value, the byte, and `POKE` runs last with the address. A unary sign or
;; `NOT` (10 arriving, 9 waiting) runs before a ^ that follows it, so -2^2 is 4.
;; See: <Interpreter::RunLine::Arrive>, <RoutinesLow>
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
;; (<Interpreter::RunLine::RunWaiting>).
;;
;; TEXT and GR are the Monitor's own routines, <SetText> and <SetGraphics>. Several tokens share a routine: every
;; left parenthesis but a substring's, an array's and a string store's is <Operators::LeftParenthesis>, and # and <> are
;; both <Operators::NotEqual>.
;; See: <RoutinesHigh>, <Priorities>
;; Also: VERBADRL (IBSM)
RoutinesLow:
    RoutineLow $00, Statements::BeginLine                      ; (begins the line)
    RoutineLow $01, NO_ROUTINE                      ; _ (end of line)
    RoutineLow $02, NO_ROUTINE                      ; _ (empty line)
    RoutineLow $03, Statements::Colon                           ; :
    RoutineLow $04, Statements::Load                            ; LOAD
    RoutineLow $05, Statements::Save                           ; SAVE
    RoutineLow $06, Statements::Con                             ; CON
    RoutineLow $07, Statements::RunLine                          ; RUN n
    RoutineLow $08, Statements::Run                             ; RUN
    RoutineLow $09, Statements::Del                             ; DEL
    RoutineLow $0A, Statements::DelComma                       ; DEL's ,
    RoutineLow $0B, Statements::New                             ; NEW
    RoutineLow $0C, Statements::Clr                             ; CLR
    RoutineLow $0D, Statements::Auto                            ; AUTO
    RoutineLow $0E, Statements::AutoComma                      ; AUTO's ,
    RoutineLow $0F, Statements::Man                             ; MAN
    RoutineLow $10, Statements::HiMem                          ; HIMEM:
    RoutineLow $11, Statements::LoMem                          ; LOMEM:
    RoutineLow $12, Operators::Add                            ; +
    RoutineLow $13, Operators::Subtract                        ; -
    RoutineLow $14, Operators::Multiply                            ; *
    RoutineLow $15, Operators::Divide                          ; /
    RoutineLow $16, Operators::Equal                       ; =
    RoutineLow $17, Operators::NotEqual                    ; #
    RoutineLow $18, Operators::GreaterOrEqual                         ; >=
    RoutineLow $19, Operators::Greater                         ; >
    RoutineLow $1A, Operators::LessOrEqual                          ; <=
    RoutineLow $1B, Operators::NotEqual                    ; <>
    RoutineLow $1C, Operators::Less                            ; <
    RoutineLow $1D, Operators::And                            ; AND
    RoutineLow $1E, Operators::Or                             ; OR
    RoutineLow $1F, Operators::Mod                             ; MOD
    RoutineLow $20, Operators::Power                             ; ^
    RoutineLow $21, NO_ROUTINE                      ; +
    RoutineLow $22, Operators::LeftParenthesis                      ; ( (DIM string)
    RoutineLow $23, Operators::SubstringComma                    ; , (substring)
    RoutineLow $24, Statements::GoTo                            ; THEN (line number)
    RoutineLow $25, Statements::Let                             ; THEN (statement)
    RoutineLow $26, Statements::InputString                    ; , (INPUT string)
    RoutineLow $27, Statements::InputNumberComma    ; , (INPUT number)
    RoutineLow $28, NO_ROUTINE                      ; " (open)
    RoutineLow $29, NO_ROUTINE                      ; " (close)
    RoutineLow $2A, Operators::Substring                    ; ( (substring)
    RoutineLow $2B, NO_ROUTINE                      ; !
    RoutineLow $2C, NO_ROUTINE                      ; !
    RoutineLow $2D, Operators::ArrayElement                     ; ( (array)
    RoutineLow $2E, Functions::Peek                            ; PEEK
    RoutineLow $2F, Functions::Rnd                             ; RND
    RoutineLow $30, Functions::Sgn                             ; SGN
    RoutineLow $31, Functions::Abs                             ; ABS
    RoutineLow $32, Functions::Pdl                             ; PDL
    RoutineLow $33, NO_ROUTINE                      ; RNDX
    RoutineLow $34, Operators::LeftParenthesis                      ; ( (DIM number)
    RoutineLow $35, Operators::Plus                        ; + (unary)
    RoutineLow $36, Operators::Negate                          ; - (unary)
    RoutineLow $37, Operators::Not                             ; NOT
    RoutineLow $38, Operators::LeftParenthesis                      ; ( (expression)
    RoutineLow $39, Operators::StringEqual                          ; = (strings)
    RoutineLow $3A, Operators::StringNotEqual                          ; # (strings)
    RoutineLow $3B, Functions::Len                             ; LEN(
    RoutineLow $3C, Functions::Asc                             ; ASC(
    RoutineLow $3D, Functions::Scrn                            ; SCRN(
    RoutineLow $3E, Functions::ScrnComma                      ; , (SCRN)
    RoutineLow $3F, Operators::LeftParenthesis                      ; ( (function)
    RoutineLow $40, NO_ROUTINE                      ; $ (string name)
    RoutineLow $41, NO_ROUTINE                      ; $
    RoutineLow $42, Operators::StringDestination                   ; ( (string store)
    RoutineLow $43, Statements::DimString                          ; , (DIM string)
    RoutineLow $44, Statements::DimNumber                          ; , (DIM number)
    RoutineLow $45, Statements::PrintString                        ; ; (string)
    RoutineLow $46, Statements::PrintNumber                        ; ; (number)
    RoutineLow $47, Statements::PrintSemicolonEnd                        ; ; (end)
    RoutineLow $48, Statements::PrintStringComma                     ; , (string)
    RoutineLow $49, Statements::PrintNumberComma                     ; , (number)
    RoutineLow $4A, Statements::PrintCommaEnd                     ; , (end)
    RoutineLow $4B, SetText                         ; TEXT
    RoutineLow $4C, SetGraphics                     ; GR
    RoutineLow $4D, Statements::Call                            ; CALL
    RoutineLow $4E, Statements::DimString                          ; DIM (string)
    RoutineLow $4F, Statements::DimNumber                          ; DIM (number)
    RoutineLow $50, Statements::Tab                             ; TAB
    RoutineLow $51, Statements::End                             ; END
    RoutineLow $52, Statements::InputString                    ; INPUT (string)
    RoutineLow $53, Statements::InputPrompt                    ; INPUT (prompt)
    RoutineLow $54, Statements::InputNumber         ; INPUT (number)
    RoutineLow $55, Statements::For                             ; FOR
    RoutineLow $56, Statements::AssignNumber                      ; = (FOR)
    RoutineLow $57, Statements::To                              ; TO
    RoutineLow $58, Statements::Step                            ; STEP
    RoutineLow $59, NEXT                            ; NEXT
    RoutineLow $5A, NEXT                            ; NEXT's ,
    RoutineLow $5B, Statements::Return                          ; RETURN
    RoutineLow $5C, Statements::GoSub                           ; GOSUB
    RoutineLow $5D, NO_ROUTINE                      ; REM
    RoutineLow $5E, Statements::Let                             ; LET
    RoutineLow $5F, Statements::GoTo                            ; GOTO
    RoutineLow $60, Statements::If                              ; IF
    RoutineLow $61, Statements::PrintString                        ; PRINT (string)
    RoutineLow $62, Statements::PrintNumber                        ; PRINT (number)
    RoutineLow $63, Statements::Print                        ; PRINT
    RoutineLow $64, Statements::Poke                            ; POKE
    RoutineLow $65, Statements::FirstValue                       ; POKE's ,
    RoutineLow $66, Statements::Color                        ; COLOR=
    RoutineLow $67, Statements::FirstValue                       ; PLOT
    RoutineLow $68, Statements::PlotComma                      ; PLOT's ,
    RoutineLow $69, Statements::FirstValue                       ; HLIN
    RoutineLow $6A, Statements::HLinComma                      ; HLIN's ,
    RoutineLow $6B, Statements::HLinAt                         ; AT (HLIN)
    RoutineLow $6C, Statements::FirstValue                       ; VLIN
    RoutineLow $6D, Statements::VLinComma                      ; VLIN's ,
    RoutineLow $6E, Statements::VLinAt                         ; AT (VLIN)
    RoutineLow $6F, Statements::VTab                           ; VTAB
    RoutineLow $70, Statements::LetString                         ; = (string)
    RoutineLow $71, Statements::AssignNumber                      ; = (number)
    RoutineLow $72, Operators::RightParenthesis                     ; )
    RoutineLow $73, NO_ROUTINE                      ; )
    RoutineLow $74, Statements::ListLine                         ; LIST n
    RoutineLow $75, Statements::ListComma                      ; LIST's ,
    RoutineLow $76, Statements::List                            ; LIST
    RoutineLow $77, Statements::Pop                             ; POP
    RoutineLow $78, Statements::NoDspString                       ; NODSP (string)
    RoutineLow $79, Statements::NoDspNumber                       ; NODSP (number)
    RoutineLow $7A, Statements::NoTrace                         ; NOTRACE
    RoutineLow $7B, Statements::DspString                         ; DSP (string)
    RoutineLow $7C, Statements::DspNumber                         ; DSP (number)
    RoutineLow $7D, Statements::Trace                           ; TRACE
    RoutineLow $7E, Statements::PrNumber                          ; PR#
    RoutineLow $7F, Statements::InNumber                          ; IN#

;; The high bytes of each token's routine, as <RoutinesLow>.
;; Also: VERBADRH (IBSM)
RoutinesHigh:
    RoutineHigh $00, Statements::BeginLine                     ; (begins the line)
    RoutineHigh $01, NO_ROUTINE                     ; _ (end of line)
    RoutineHigh $02, NO_ROUTINE                     ; _ (empty line)
    RoutineHigh $03, Statements::Colon                          ; :
    RoutineHigh $04, Statements::Load                           ; LOAD
    RoutineHigh $05, Statements::Save                          ; SAVE
    RoutineHigh $06, Statements::Con                            ; CON
    RoutineHigh $07, Statements::RunLine                         ; RUN n
    RoutineHigh $08, Statements::Run                            ; RUN
    RoutineHigh $09, Statements::Del                            ; DEL
    RoutineHigh $0A, Statements::DelComma                      ; DEL's ,
    RoutineHigh $0B, Statements::New                            ; NEW
    RoutineHigh $0C, Statements::Clr                            ; CLR
    RoutineHigh $0D, Statements::Auto                           ; AUTO
    RoutineHigh $0E, Statements::AutoComma                     ; AUTO's ,
    RoutineHigh $0F, Statements::Man                            ; MAN
    RoutineHigh $10, Statements::HiMem                         ; HIMEM:
    RoutineHigh $11, Statements::LoMem                         ; LOMEM:
    RoutineHigh $12, Operators::Add                           ; +
    RoutineHigh $13, Operators::Subtract                       ; -
    RoutineHigh $14, Operators::Multiply                           ; *
    RoutineHigh $15, Operators::Divide                         ; /
    RoutineHigh $16, Operators::Equal                      ; =
    RoutineHigh $17, Operators::NotEqual                   ; #
    RoutineHigh $18, Operators::GreaterOrEqual                        ; >=
    RoutineHigh $19, Operators::Greater                        ; >
    RoutineHigh $1A, Operators::LessOrEqual                         ; <=
    RoutineHigh $1B, Operators::NotEqual                   ; <>
    RoutineHigh $1C, Operators::Less                           ; <
    RoutineHigh $1D, Operators::And                           ; AND
    RoutineHigh $1E, Operators::Or                            ; OR
    RoutineHigh $1F, Operators::Mod                            ; MOD
    RoutineHigh $20, Operators::Power                            ; ^
    RoutineHigh $21, NO_ROUTINE                     ; +
    RoutineHigh $22, Operators::LeftParenthesis                     ; ( (DIM string)
    RoutineHigh $23, Operators::SubstringComma                   ; , (substring)
    RoutineHigh $24, Statements::GoTo                           ; THEN (line number)
    RoutineHigh $25, Statements::Let                            ; THEN (statement)
    RoutineHigh $26, Statements::InputString                   ; , (INPUT string)
    RoutineHigh $27, Statements::InputNumberComma   ; , (INPUT number)
    RoutineHigh $28, NO_ROUTINE                     ; " (open)
    RoutineHigh $29, NO_ROUTINE                     ; " (close)
    RoutineHigh $2A, Operators::Substring                   ; ( (substring)
    RoutineHigh $2B, NO_ROUTINE                     ; !
    RoutineHigh $2C, NO_ROUTINE                     ; !
    RoutineHigh $2D, Operators::ArrayElement                    ; ( (array)
    RoutineHigh $2E, Functions::Peek                           ; PEEK
    RoutineHigh $2F, Functions::Rnd                            ; RND
    RoutineHigh $30, Functions::Sgn                            ; SGN
    RoutineHigh $31, Functions::Abs                            ; ABS
    RoutineHigh $32, Functions::Pdl                            ; PDL
    RoutineHigh $33, NO_ROUTINE                     ; RNDX
    RoutineHigh $34, Operators::LeftParenthesis                     ; ( (DIM number)
    RoutineHigh $35, Operators::Plus                       ; + (unary)
    RoutineHigh $36, Operators::Negate                         ; - (unary)
    RoutineHigh $37, Operators::Not                            ; NOT
    RoutineHigh $38, Operators::LeftParenthesis                     ; ( (expression)
    RoutineHigh $39, Operators::StringEqual                         ; = (strings)
    RoutineHigh $3A, Operators::StringNotEqual                         ; # (strings)
    RoutineHigh $3B, Functions::Len                            ; LEN(
    RoutineHigh $3C, Functions::Asc                            ; ASC(
    RoutineHigh $3D, Functions::Scrn                           ; SCRN(
    RoutineHigh $3E, Functions::ScrnComma                     ; , (SCRN)
    RoutineHigh $3F, Operators::LeftParenthesis                     ; ( (function)
    RoutineHigh $40, NO_ROUTINE                     ; $ (string name)
    RoutineHigh $41, NO_ROUTINE                     ; $
    RoutineHigh $42, Operators::StringDestination                  ; ( (string store)
    RoutineHigh $43, Statements::DimString                         ; , (DIM string)
    RoutineHigh $44, Statements::DimNumber                         ; , (DIM number)
    RoutineHigh $45, Statements::PrintString                       ; ; (string)
    RoutineHigh $46, Statements::PrintNumber                       ; ; (number)
    RoutineHigh $47, Statements::PrintSemicolonEnd                       ; ; (end)
    RoutineHigh $48, Statements::PrintStringComma                    ; , (string)
    RoutineHigh $49, Statements::PrintNumberComma                    ; , (number)
    RoutineHigh $4A, Statements::PrintCommaEnd                    ; , (end)
    RoutineHigh $4B, SetText                        ; TEXT
    RoutineHigh $4C, SetGraphics                    ; GR
    RoutineHigh $4D, Statements::Call                           ; CALL
    RoutineHigh $4E, Statements::DimString                         ; DIM (string)
    RoutineHigh $4F, Statements::DimNumber                         ; DIM (number)
    RoutineHigh $50, Statements::Tab                            ; TAB
    RoutineHigh $51, Statements::End                            ; END
    RoutineHigh $52, Statements::InputString                   ; INPUT (string)
    RoutineHigh $53, Statements::InputPrompt                   ; INPUT (prompt)
    RoutineHigh $54, Statements::InputNumber        ; INPUT (number)
    RoutineHigh $55, Statements::For                            ; FOR
    RoutineHigh $56, Statements::AssignNumber                     ; = (FOR)
    RoutineHigh $57, Statements::To                             ; TO
    RoutineHigh $58, Statements::Step                           ; STEP
    RoutineHigh $59, NEXT                           ; NEXT
    RoutineHigh $5A, NEXT                           ; NEXT's ,
    RoutineHigh $5B, Statements::Return                         ; RETURN
    RoutineHigh $5C, Statements::GoSub                          ; GOSUB
    RoutineHigh $5D, NO_ROUTINE                     ; REM
    RoutineHigh $5E, Statements::Let                            ; LET
    RoutineHigh $5F, Statements::GoTo                           ; GOTO
    RoutineHigh $60, Statements::If                             ; IF
    RoutineHigh $61, Statements::PrintString                       ; PRINT (string)
    RoutineHigh $62, Statements::PrintNumber                       ; PRINT (number)
    RoutineHigh $63, Statements::Print                       ; PRINT
    RoutineHigh $64, Statements::Poke                           ; POKE
    RoutineHigh $65, Statements::FirstValue                      ; POKE's ,
    RoutineHigh $66, Statements::Color                       ; COLOR=
    RoutineHigh $67, Statements::FirstValue                      ; PLOT
    RoutineHigh $68, Statements::PlotComma                     ; PLOT's ,
    RoutineHigh $69, Statements::FirstValue                      ; HLIN
    RoutineHigh $6A, Statements::HLinComma                     ; HLIN's ,
    RoutineHigh $6B, Statements::HLinAt                        ; AT (HLIN)
    RoutineHigh $6C, Statements::FirstValue                      ; VLIN
    RoutineHigh $6D, Statements::VLinComma                     ; VLIN's ,
    RoutineHigh $6E, Statements::VLinAt                        ; AT (VLIN)
    RoutineHigh $6F, Statements::VTab                          ; VTAB
    RoutineHigh $70, Statements::LetString                        ; = (string)
    RoutineHigh $71, Statements::AssignNumber                     ; = (number)
    RoutineHigh $72, Operators::RightParenthesis                    ; )
    RoutineHigh $73, NO_ROUTINE                     ; )
    RoutineHigh $74, Statements::ListLine                        ; LIST n
    RoutineHigh $75, Statements::ListComma                     ; LIST's ,
    RoutineHigh $76, Statements::List                           ; LIST
    RoutineHigh $77, Statements::Pop                            ; POP
    RoutineHigh $78, Statements::NoDspString                      ; NODSP (string)
    RoutineHigh $79, Statements::NoDspNumber                      ; NODSP (number)
    RoutineHigh $7A, Statements::NoTrace                        ; NOTRACE
    RoutineHigh $7B, Statements::DspString                        ; DSP (string)
    RoutineHigh $7C, Statements::DspNumber                        ; DSP (number)
    RoutineHigh $7D, Statements::Trace                          ; TRACE
    RoutineHigh $7E, Statements::PrNumber                         ; PR#
    RoutineHigh $7F, Statements::InNumber                         ; IN#

.endscope
