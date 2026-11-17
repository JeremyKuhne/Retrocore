;; APPLE-1 BASIC: TOKEN PRIORITIES AND THE VERB DISPATCH TABLES ($E998-$EAFF)
;;
;; Three tables of 120 entries, one per token: the priorities by which the interpreter (Interpreter.asm) orders
;; the tokens of a statement, and the low and high bytes of each token's routine. Each entry is listed with its
;; token and the text LIST shows for it; where the same text has several tokens, the note in parentheses says
;; which use the token is for.
;;
;; The tokenizer's syntax tables fix which token a word gets, so each token has exactly one meaning and its own
;; routine: PRINT before a string ($61) and PRINT before a number ($62) go to different routines, and so do the
;; dozen commas. An entry of $FF marks a token that is never run: the end of the line and REM end a line before
;; their routine would run, quotes and the $ after a string name are taken as part of their operand, and a few
;; tokens are not used.
;;
;; Part of Basic.asm; it follows ControlFlow.asm, at $E998.

;; The priority of each token: two 4-bit priorities with their bits interleaved.
;;
;; Bits 0, 2, 4 and 6 hold the priority on arrival, bits 1, 3, 5 and 7 the priority while waiting (<DOTOKEN>); the
;; two numbers after each token's text are these, decoded. A waiting token runs when a token arrives whose arriving
;; priority is no higher than its own waiting priority. So * (8) waits on + (7), operators run left to right among
;; equals, a left parenthesis (15 arriving, 0 waiting) holds everything until the right parenthesis comes, and a
;; statement's keyword (1 and 1) runs at the end of its statement. The end of the line and REM, at 0, make
;; everything run.
;; See: <DOTOKEN>, <VERBADRL>
TABLE1:
    .byte $00                       ; $00 (begins the line)       0  0
    .byte $00                       ; $01 _ (end of line)         0  0
    .byte $00                       ; $02 _ (empty line)          0  0
    .byte $AB                       ; $03 :                       1 15
    .byte $03                       ; $04 LIST                    1  1
    .byte $03                       ; $05 , (LIST)                1  1
    .byte $03                       ; $06 LIST                    1  1
    .byte $03                       ; $07 RUN                     1  1
    .byte $03                       ; $08 RUN                     1  1
    .byte $03                       ; $09 DEL                     1  1
    .byte $03                       ; $0A , (DEL)                 1  1
    .byte $03                       ; $0B SCR                     1  1
    .byte $03                       ; $0C CLR                     1  1
    .byte $03                       ; $0D AUTO                    1  1
    .byte $03                       ; $0E , (AUTO)                1  1
    .byte $03                       ; $0F OFF                     1  1
    .byte $03                       ; $10 HIMEM=                  1  1
    .byte $03                       ; $11 LOMEM=                  1  1
    .byte $3F                       ; $12 +                       7  7
    .byte $3F                       ; $13 -                       7  7
    .byte $C0                       ; $14 *                       8  8
    .byte $C0                       ; $15 /                       8  8
    .byte $3C                       ; $16 =                       6  6
    .byte $3C                       ; $17 #                       6  6
    .byte $3C                       ; $18 >=                      6  6
    .byte $3C                       ; $19 >                       6  6
    .byte $3C                       ; $1A <=                      6  6
    .byte $3C                       ; $1B <>                      6  6
    .byte $3C                       ; $1C <                       6  6
    .byte $30                       ; $1D AND                     4  4
    .byte $0F                       ; $1E OR                      3  3
    .byte $C0                       ; $1F MOD                     8  8
    .byte $CC                       ; $20 ^                      10 10
    .byte $FF                       ; $21 + (unused)             15 15
    .byte $55                       ; $22 ( (DIM string)         15  0
    .byte $00                       ; $23 , (substring)           0  0
    .byte $AB                       ; $24 THEN (line number)      1 15
    .byte $AB                       ; $25 THEN (statement)        1 15
    .byte $03                       ; $26 , (INPUT string)        1  1
    .byte $03                       ; $27 , (INPUT number)        1  1
    .byte $FF                       ; $28 " (open)               15 15
    .byte $FF                       ; $29 " (close)              15 15
    .byte $55                       ; $2A ( (substring)          15  0
    .byte $FF                       ; $2B ! (unused)             15 15
    .byte $FF                       ; $2C ! (unused)             15 15
    .byte $55                       ; $2D ( (array)              15  0
    .byte $CF                       ; $2E PEEK                   11 11
    .byte $CF                       ; $2F RND                    11 11
    .byte $CF                       ; $30 SGN                    11 11
    .byte $CF                       ; $31 ABS                    11 11
    .byte $CF                       ; $32 USR                    11 11
    .byte $FF                       ; $33 RNDX                   15 15
    .byte $55                       ; $34 ( (DIM number)         15  0
    .byte $C3                       ; $35 + (unary)               9  9
    .byte $C3                       ; $36 - (unary)               9  9
    .byte $C3                       ; $37 NOT                     9  9
    .byte $55                       ; $38 ( (expression)         15  0
    .byte $F0                       ; $39 = (strings)            12 12
    .byte $F0                       ; $3A # (strings)            12 12
    .byte $CF                       ; $3B LEN(                   11 11
    .byte $56                       ; $3C COLOR                  14  1
    .byte $56                       ; $3D HIMEM                  14  1
    .byte $56                       ; $3E LOMEM                  14  1
    .byte $55                       ; $3F ( (function)           15  0
    .byte $FF                       ; $40  $ (string name)       15 15
    .byte $FF                       ; $41 $ (unused)             15 15
    .byte $55                       ; $42 ( (string store)       15  0
    .byte $03                       ; $43 , (DIM string)          1  1
    .byte $03                       ; $44 , (DIM number)          1  1
    .byte $03                       ; $45 ; (string)              1  1
    .byte $03                       ; $46 ; (number)              1  1
    .byte $03                       ; $47 ; (end)                 1  1
    .byte $03                       ; $48 , (string)              1  1
    .byte $03                       ; $49 , (number)              1  1
    .byte $FF                       ; $4A ! (unused)             15 15
    .byte $FF                       ; $4B ? (unused)             15 15
    .byte $FF                       ; $4C ? (unused)             15 15
    .byte $03                       ; $4D CALL                    1  1
    .byte $03                       ; $4E DIM (string)            1  1
    .byte $03                       ; $4F DIM (number)            1  1
    .byte $03                       ; $50 TAB                     1  1
    .byte $03                       ; $51 END                     1  1
    .byte $03                       ; $52 INPUT (string)          1  1
    .byte $03                       ; $53 INPUT (prompt)          1  1
    .byte $03                       ; $54 INPUT (number)          1  1
    .byte $03                       ; $55 FOR                     1  1
    .byte $03                       ; $56 = (FOR)                 1  1
    .byte $03                       ; $57 TO                      1  1
    .byte $03                       ; $58 STEP                    1  1
    .byte $03                       ; $59 NEXT                    1  1
    .byte $03                       ; $5A , (NEXT)                1  1
    .byte $03                       ; $5B RETURN                  1  1
    .byte $03                       ; $5C GOSUB                   1  1
    .byte $00                       ; $5D REM                     0  0
    .byte $AB                       ; $5E LET                     1 15
    .byte $03                       ; $5F GOTO                    1  1
    .byte $57                       ; $60 IF                     15  1
    .byte $03                       ; $61 PRINT (string)          1  1
    .byte $03                       ; $62 PRINT (number)          1  1
    .byte $03                       ; $63 PRINT (alone)           1  1
    .byte $03                       ; $64 POKE                    1  1
    .byte $07                       ; $65 , (POKE)                3  1
    .byte $03                       ; $66 COLOR=                  1  1
    .byte $03                       ; $67 PLOT                    1  1
    .byte $03                       ; $68 , (PLOT)                1  1
    .byte $03                       ; $69 HLIN                    1  1
    .byte $03                       ; $6A , (HLIN)                1  1
    .byte $03                       ; $6B AT (HLIN)               1  1
    .byte $03                       ; $6C _ (old INPUT rule)      1  1
    .byte $03                       ; $6D , (old INPUT rule)      1  1
    .byte $03                       ; $6E + (old INPUT rule)      1  1
    .byte $03                       ; $6F - (old INPUT rule)      1  1
    .byte $03                       ; $70 = (string)              1  1
    .byte $03                       ; $71 = (number)              1  1
    .byte $AA                       ; $72 )                       0 15
    .byte $FF                       ; $73 ) (unused)             15 15
    .byte $FF                       ; $74 _ (end of INPUT's numbers) 15 15
    .byte $FF                       ; $75 , (INPUT's numbers)    15 15
    .byte $FF                       ; $76 + (INPUT's numbers)    15 15
    .byte $FF                       ; $77 - (INPUT's numbers)    15 15
;; The low bytes of the routine for each token, which the interpreter jumps to through <ACC> (<DOTOKEN_2>).
;; See: <VERBADRH>, <TABLE1>
VERBADRL:
    .byte <BEGIN_LINE             ; $00 (begins the line)
    .byte $FF                       ; $01 _ (end of line): no routine
    .byte $FF                       ; $02 _ (empty line): no routine
    .byte <COLON                  ; $03 :
    .byte <LISTNUM                ; $04 LIST
    .byte <COMMA_LIST             ; $05 , (LIST)
    .byte <LIST                   ; $06 LIST
    .byte <RUNNUM                 ; $07 RUN
    .byte <RUN                    ; $08 RUN
    .byte <DEL                    ; $09 DEL
    .byte <COMMA_DEL              ; $0A , (DEL)
    .byte <NEW                    ; $0B SCR
    .byte <CLR                    ; $0C CLR
    .byte <AUTO                   ; $0D AUTO
    .byte <COMMA_AUTO             ; $0E , (AUTO)
    .byte <(SETHIMEMPP+1)         ; $0F OFF: an address inside other code
    .byte <VHIMEM                 ; $10 HIMEM=
    .byte <VLOMEM                 ; $11 LOMEM=
    .byte <PLUS                   ; $12 +
    .byte <SUBTRACT               ; $13 -
    .byte <MULT                   ; $14 *
    .byte <DIVIDE                 ; $15 /
    .byte <EQUAL_NUM              ; $16 =
    .byte <NOTEQUAL_NUM           ; $17 #
    .byte <GREATEQ                ; $18 >=
    .byte <GREATER                ; $19 >
    .byte <LESSEQ                 ; $1A <=
    .byte <NOTEQUAL_NUM           ; $1B <>
    .byte <LESS                   ; $1C <
    .byte <VAND                   ; $1D AND
    .byte <VOR                    ; $1E OR
    .byte <MOD                    ; $1F MOD
    .byte $00                       ; $20 ^: no routine
    .byte $FF                       ; $21 + (unused): no routine
    .byte <LEFT_PAREN             ; $22 ( (DIM string)
    .byte <COMMA_SUBSTR           ; $23 , (substring)
    .byte <GOTO                   ; $24 THEN (line number)
    .byte <LET                    ; $25 THEN (statement)
    .byte <INPUT_STRVAR           ; $26 , (INPUT string)
    .byte <COMMA_INPUT            ; $27 , (INPUT number)
    .byte $FF                       ; $28 " (open): no routine
    .byte $FF                       ; $29 " (close): no routine
    .byte <PAREN_SUBSTR           ; $2A ( (substring)
    .byte $FF                       ; $2B ! (unused): no routine
    .byte $FF                       ; $2C ! (unused): no routine
    .byte <PAREN_ARRAY            ; $2D ( (array)
    .byte <PEEK                   ; $2E PEEK
    .byte <RND                    ; $2F RND
    .byte <SGN                    ; $30 SGN
    .byte <ABS                    ; $31 ABS
    .byte $00                       ; $32 USR: no routine
    .byte $FF                       ; $33 RNDX: no routine
    .byte <LEFT_PAREN             ; $34 ( (DIM number)
    .byte <POSITIVE               ; $35 + (unary)
    .byte <NEGATE                 ; $36 - (unary)
    .byte <NOT                    ; $37 NOT
    .byte <LEFT_PAREN             ; $38 ( (expression)
    .byte <EQ_STR                 ; $39 = (strings)
    .byte <NE_STR                 ; $3A # (strings)
    .byte <LEN                    ; $3B LEN(
    .byte <MOVEPROG_6             ; $3C COLOR: an address inside other code
    .byte <MOVEPROG_2             ; $3D HIMEM: an address inside other code
    .byte <MOVEPROG_4             ; $3E LOMEM: an address inside other code
    .byte <LEFT_PAREN             ; $3F ( (function)
    .byte $FF                       ; $40  $ (string name): no routine
    .byte $FF                       ; $41 $ (unused): no routine
    .byte <PAREN_STRDEST          ; $42 ( (string store)
    .byte <DIMSTR                 ; $43 , (DIM string)
    .byte <DIMNUM                 ; $44 , (DIM number)
    .byte <PRINTSTR               ; $45 ; (string)
    .byte <PRINTNUM               ; $46 ; (number)
    .byte <SEMI_END               ; $47 ; (end)
    .byte <COMMA_PRSTR            ; $48 , (string)
    .byte <COMMA_PRNUM            ; $49 , (number)
    .byte $FF                       ; $4A ! (unused): no routine
    .byte $FF                       ; $4B ? (unused): no routine
    .byte $FF                       ; $4C ? (unused): no routine
    .byte <CALL                   ; $4D CALL
    .byte <DIMSTR                 ; $4E DIM (string)
    .byte <DIMNUM                 ; $4F DIM (number)
    .byte <TAB                    ; $50 TAB
    .byte <END                    ; $51 END
    .byte <INPUT_STRVAR           ; $52 INPUT (string)
    .byte <INPUT_PROMPT           ; $53 INPUT (prompt)
    .byte <INPUTNUM               ; $54 INPUT (number)
    .byte <FOR                    ; $55 FOR
    .byte <ASSIGN_NUM             ; $56 = (FOR)
    .byte <TO                     ; $57 TO
    .byte <STEP                   ; $58 STEP
    .byte <NEXT                   ; $59 NEXT
    .byte <NEXT                   ; $5A , (NEXT)
    .byte <RETURN                 ; $5B RETURN
    .byte <GOSUB                  ; $5C GOSUB
    .byte $FF                       ; $5D REM: no routine
    .byte <LET                    ; $5E LET
    .byte <GOTO                   ; $5F GOTO
    .byte <IF                     ; $60 IF
    .byte <PRINTSTR               ; $61 PRINT (string)
    .byte <PRINTNUM               ; $62 PRINT (number)
    .byte <PRINT_CR               ; $63 PRINT (alone)
    .byte <POKE                   ; $64 POKE
    .byte <COMMA_POKE             ; $65 , (POKE)
    .byte <COLOR_EQ               ; $66 COLOR=
    .byte <POKE                   ; $67 PLOT
    .byte <COMMA_PLOT             ; $68 , (PLOT)
    .byte <POKE                   ; $69 HLIN
    .byte <MOVEPROG               ; $6A , (HLIN): an address inside other code
    .byte <(MOVEPROG_2+2)         ; $6B AT (HLIN): an address inside other code
    .byte <POKE                   ; $6C _ (old INPUT rule)
    .byte <MOVEPROG_5             ; $6D , (old INPUT rule): no line makes it
    .byte <(MOVEPROG_6+4)         ; $6E + (old INPUT rule): no line makes it
    .byte <(SETHIMEMPP_1+1)       ; $6F - (old INPUT rule): no line makes it
    .byte <LET_STR                ; $70 = (string)
    .byte <ASSIGN_NUM             ; $71 = (number)
    .byte <RIGHT_PAREN            ; $72 )
    .byte $FF                       ; $73 ) (unused): no routine
    .byte $FF                       ; $74 _ (end of INPUT's numbers): no routine
    .byte $FF                       ; $75 , (INPUT's numbers): no routine
    .byte $FF                       ; $76 + (INPUT's numbers): no routine
    .byte $FF                       ; $77 - (INPUT's numbers): no routine
;; The high bytes of the routine for each token.
;; See: <VERBADRL>
VERBADRH:
    .byte >BEGIN_LINE             ; $00 (begins the line)
    .byte $FF                       ; $01 _ (end of line): no routine
    .byte $FF                       ; $02 _ (empty line): no routine
    .byte >COLON                  ; $03 :
    .byte >LISTNUM                ; $04 LIST
    .byte >COMMA_LIST             ; $05 , (LIST)
    .byte >LIST                   ; $06 LIST
    .byte >RUNNUM                 ; $07 RUN
    .byte >RUN                    ; $08 RUN
    .byte >DEL                    ; $09 DEL
    .byte >COMMA_DEL              ; $0A , (DEL)
    .byte >NEW                    ; $0B SCR
    .byte >CLR                    ; $0C CLR
    .byte >AUTO                   ; $0D AUTO
    .byte >COMMA_AUTO             ; $0E , (AUTO)
    .byte >(SETHIMEMPP+1)         ; $0F OFF: an address inside other code
    .byte >VHIMEM                 ; $10 HIMEM=
    .byte >VLOMEM                 ; $11 LOMEM=
    .byte >PLUS                   ; $12 +
    .byte >SUBTRACT               ; $13 -
    .byte >MULT                   ; $14 *
    .byte >DIVIDE                 ; $15 /
    .byte >EQUAL_NUM              ; $16 =
    .byte >NOTEQUAL_NUM           ; $17 #
    .byte >GREATEQ                ; $18 >=
    .byte >GREATER                ; $19 >
    .byte >LESSEQ                 ; $1A <=
    .byte >NOTEQUAL_NUM           ; $1B <>
    .byte >LESS                   ; $1C <
    .byte >VAND                   ; $1D AND
    .byte >VOR                    ; $1E OR
    .byte >MOD                    ; $1F MOD
    .byte $00                       ; $20 ^: no routine
    .byte $FF                       ; $21 + (unused): no routine
    .byte >LEFT_PAREN             ; $22 ( (DIM string)
    .byte >COMMA_SUBSTR           ; $23 , (substring)
    .byte >GOTO                   ; $24 THEN (line number)
    .byte >LET                    ; $25 THEN (statement)
    .byte >INPUT_STRVAR           ; $26 , (INPUT string)
    .byte >COMMA_INPUT            ; $27 , (INPUT number)
    .byte $FF                       ; $28 " (open): no routine
    .byte $FF                       ; $29 " (close): no routine
    .byte >PAREN_SUBSTR           ; $2A ( (substring)
    .byte $FF                       ; $2B ! (unused): no routine
    .byte $FF                       ; $2C ! (unused): no routine
    .byte >PAREN_ARRAY            ; $2D ( (array)
    .byte >PEEK                   ; $2E PEEK
    .byte >RND                    ; $2F RND
    .byte >SGN                    ; $30 SGN
    .byte >ABS                    ; $31 ABS
    .byte $00                       ; $32 USR: no routine
    .byte $FF                       ; $33 RNDX: no routine
    .byte >LEFT_PAREN             ; $34 ( (DIM number)
    .byte >POSITIVE               ; $35 + (unary)
    .byte >NEGATE                 ; $36 - (unary)
    .byte >NOT                    ; $37 NOT
    .byte >LEFT_PAREN             ; $38 ( (expression)
    .byte >EQ_STR                 ; $39 = (strings)
    .byte >NE_STR                 ; $3A # (strings)
    .byte >LEN                    ; $3B LEN(
    .byte >MOVEPROG_6             ; $3C COLOR: an address inside other code
    .byte >MOVEPROG_2             ; $3D HIMEM: an address inside other code
    .byte >MOVEPROG_4             ; $3E LOMEM: an address inside other code
    .byte >LEFT_PAREN             ; $3F ( (function)
    .byte $FF                       ; $40  $ (string name): no routine
    .byte $FF                       ; $41 $ (unused): no routine
    .byte >PAREN_STRDEST          ; $42 ( (string store)
    .byte >DIMSTR                 ; $43 , (DIM string)
    .byte >DIMNUM                 ; $44 , (DIM number)
    .byte >PRINTSTR               ; $45 ; (string)
    .byte >PRINTNUM               ; $46 ; (number)
    .byte >SEMI_END               ; $47 ; (end)
    .byte >COMMA_PRSTR            ; $48 , (string)
    .byte >COMMA_PRNUM            ; $49 , (number)
    .byte $FF                       ; $4A ! (unused): no routine
    .byte $FF                       ; $4B ? (unused): no routine
    .byte $FF                       ; $4C ? (unused): no routine
    .byte >CALL                   ; $4D CALL
    .byte >DIMSTR                 ; $4E DIM (string)
    .byte >DIMNUM                 ; $4F DIM (number)
    .byte >TAB                    ; $50 TAB
    .byte >END                    ; $51 END
    .byte >INPUT_STRVAR           ; $52 INPUT (string)
    .byte >INPUT_PROMPT           ; $53 INPUT (prompt)
    .byte >INPUTNUM               ; $54 INPUT (number)
    .byte >FOR                    ; $55 FOR
    .byte >ASSIGN_NUM             ; $56 = (FOR)
    .byte >TO                     ; $57 TO
    .byte >STEP                   ; $58 STEP
    .byte >NEXT                   ; $59 NEXT
    .byte >NEXT                   ; $5A , (NEXT)
    .byte >RETURN                 ; $5B RETURN
    .byte >GOSUB                  ; $5C GOSUB
    .byte $FF                       ; $5D REM: no routine
    .byte >LET                    ; $5E LET
    .byte >GOTO                   ; $5F GOTO
    .byte >IF                     ; $60 IF
    .byte >PRINTSTR               ; $61 PRINT (string)
    .byte >PRINTNUM               ; $62 PRINT (number)
    .byte >PRINT_CR               ; $63 PRINT (alone)
    .byte >POKE                   ; $64 POKE
    .byte >COMMA_POKE             ; $65 , (POKE)
    .byte >COLOR_EQ               ; $66 COLOR=
    .byte >POKE                   ; $67 PLOT
    .byte >COMMA_PLOT             ; $68 , (PLOT)
    .byte >POKE                   ; $69 HLIN
    .byte >MOVEPROG               ; $6A , (HLIN): an address inside other code
    .byte >(MOVEPROG_2+2)         ; $6B AT (HLIN): an address inside other code
    .byte >POKE                   ; $6C _ (old INPUT rule)
    .byte >MOVEPROG_5             ; $6D , (old INPUT rule): no line makes it
    .byte >(MOVEPROG_6+4)         ; $6E + (old INPUT rule): no line makes it
    .byte >(SETHIMEMPP_1+1)       ; $6F - (old INPUT rule): no line makes it
    .byte >LET_STR                ; $70 = (string)
    .byte >ASSIGN_NUM             ; $71 = (number)
    .byte >RIGHT_PAREN            ; $72 )
    .byte $FF                       ; $73 ) (unused): no routine
    .byte $FF                       ; $74 _ (end of INPUT's numbers): no routine
    .byte $FF                       ; $75 , (INPUT's numbers): no routine
    .byte $FF                       ; $76 + (INPUT's numbers): no routine
    .byte $FF                       ; $77 - (INPUT's numbers): no routine
