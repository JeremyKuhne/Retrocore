;; INTEGER BASIC: THE SYNTAX TABLE ($EC00-$EDFF)
;;
;; Integer BASIC's grammar, which the tokenizer (Tokenizer.asm) matches each typed line against, and from which
;; the keywords get their tokens. It fills two pages, and each rule is a list of alternatives, each a list of
;; items; the item encoding is explained in Tokenizer.asm and below. SYNTABLNDX (Operators.asm) gives the address
;; where each of the 32 rules starts.
;;
;; The tokenizer reads a rule downward, from the higher address to the lower. This source lists the table in
;; address order, so a rule reads from the line where its RULEnn equate stands up toward the top of the file, and a
;; keyword is written in its usual spelling but stored backward: KEY "LIST" places T, S, I, L at increasing
;; addresses, so the tokenizer meets L first. Each rule ends where its last alternative ends, and many rules end in
;; the middle of another rule's bytes, sharing that rule's later alternatives: the statements allowed in immediate
;; mode (rule SIMMED) are the last alternatives of the statement rule (SSTMT), for example.
;;
;; Tokens. A keyword's token is its place in the table: the number of keywords between it and the top of its page,
;; plus the first byte of the page ($50 here, 0 at $ED00). Each place where a word appears gives it a different
;; token, which is how the interpreter knows, for instance, which of the dozen commas it has: the comma between
;; INPUT's variables is $27, the comma of PLOT $68. The tokens of THEN, TO, STEP, AND, OR, MOD and AT at the
;; bottom of the first page are $85 and up: these words cannot be part of a variable's name, and matching one there
;; ends the name.
;;
;; In the grammar of each rule, given with the rule's number below, a keyword is followed by its token in
;; parentheses, and the other names are rules or the items LETTER, DIGIT, STRCHAR and REMCHAR; [ ] encloses what may
;; be left out and { } what may repeat, zero or more times. Alternatives are tried in order and the first
;; that matches is kept: when an item after a rule's call fails, the tokenizer does not go back into that rule for
;; another alternative, but tries the caller's next one. The grammars leave out the alternatives a rule reaches only
;; by running on into another rule's bytes, where no text can match that an earlier alternative did not.
;;
;; Part of IntegerBasic.asm; it follows Messages.asm, at $EC00.

; The item encoding, as the tokenizer reads it (Tokenizer.asm).
LAST = $40                          ;; bit 6 of an item: the last item of its alternative
LETTER = $80                        ;; an item matching any letter, which is copied into the tokens
DIGIT = $81                         ;; an item matching any digit, which is copied into the tokens
SYNERR = $00                        ;; an item that is a SYNTAX error: none of the alternatives before it matched
STRCHAR = $01                       ;; copies one character of a string constant, up to a quote or the line's end
REMCHAR = $02                       ;; copies one character of a remark, up to the line's end
ENDLINE = $03                       ;; the end of the match: the tokenizer returns
AGAIN = $7F                         ;; repeats the item before it while it matches
AGAIN2 = $7E                        ;; repeats the two items before it while they match
USE = $00                           ;; calls the rule in the low 5 bits
USEOPT = $20                        ;; calls a rule; if the item after it fails, the rule has matched without the rest
USEEND = $40                        ;; calls a rule as the last item of the rule's last alternative
USEALT = $60                        ;; calls a rule as the last item of an alternative that has more after it

;; Places a keyword or a punctuation character in the syntax table, stored backward.
;;
;; Each character is stored less $A0, with bit 7 set: the low 6 bits hold $A0-$DF. The last character is stored
;; first, at the lowest address.
;; Parameters: text = the keyword
.macro KEY text
    .repeat .strlen(text), I
    .byte (.strat(text, .strlen(text) - 1 - I) - $A0) | $80
    .endrepeat
.endmacro

;; Places a keyword, stored backward as <KEY> does, that is the last item of its alternative.
;;
;; Its last character, at the lowest address, has bit 6 set (<LAST>).
;; Parameters: text = the keyword
.macro KEYEND text
    .byte (.strat(text, .strlen(text) - 1) - $A0) | $C0
    .repeat .strlen(text) - 1, I
    .byte (.strat(text, .strlen(text) - 2 - I) - $A0) | $80
    .endrepeat
.endmacro

; The rules, by number: an item's low 5 bits. Rules 0 to 3 can only be called with USEOPT, USEEND or USEALT, as
; their CALL bytes are other items.
;; Rule 0: a numeric constant, one or more digits.
;;
;; When it returns, the tokenizer turns the digits it copied into the constant's form: the first digit, then the
;; value (<RULEMATCHED>).
;; > SDIGIT { SDIGIT }
SNUMBER = $00

;; Rule 1: no rule or routine calls it.
;; > SNUMBER [SDIMNUM]
SUNUSED1 = $01

;; Rule 2: a statement in a numbered line: the statements only a program can use, then those of <SIMMED>, whose
;; bytes it shares.
;; > END ($51)
;; > INPUT ($52) SSTRDEST { SINVARS }
;; > INPUT ($53) SSTRING { SINVARS }
;; > INPUT ($54) SNUMVAR { SINVARS }
;; > FOR ($55) SNAME = ($56) SEXPR TO ($57) SEXPR [STEP ($58) SEXPR]
;; > NEXT ($59) SNAME { , ($5A) SNAME }
;; > RETURN ($5B)
;; > GOSUB ($5C) SEXPR
;; > and the alternatives of SIMMED
SSTMT = $02

;; Rule 3: a string variable with its size, in DIM.
;; > SSTRVAR ( ($22) SEXPR SRPAREN
SDIMSTR = $03

;; Rule 4: what follows IF's condition: THEN and a line number, or THEN and a statement.
;; > THEN ($24) SNUMBER
;; > THEN ($25) SSTMT
STHEN = $04

;; Rule 5: a further variable of INPUT.
;; > , ($26) SSTRDEST
;; > , ($27) SNUMVAR
SINVARS = $05

;; Rule 6: a substring's positions.
;; > SEXPR [, ($23) SEXPR]
SSUBSTR = $06

;; Rule 7: a numeric expression: operands with operators between them.
;; > SOPERAND { SOPER SOPERAND }
SEXPR = $07

;; Rule 8: a string: a constant, or a variable with an optional substring.
;; > " ($28) SSTRCHR " ($29)
;; > SSTRVAR [( ($2A) SSUBSTR SRPAREN]
SSTRING = $08

;; Rule 9: a string variable's name, which ends in $ (token $40).
;; > SNAME $ ($40)
SSTRVAR = $09

;; Rule 10: a string variable to store into, with an optional position.
;; > SSTRVAR [( ($42) SEXPR SRPAREN]
SSTRDEST = $0A

;; Rule 11: TEXT, GR, CALL, DIM and TAB.
;; > TEXT ($4B)
;; > GR ($4C)
;; > CALL ($4D) SEXPR
;; > DIM ($4E) SDIMSTR { SDIMLIST }
;; > DIM ($4F) SDIMNUM { SDIMLIST }
;; > TAB ($50) SEXPR
SSTMT2 = $0B

;; Rule 12: the characters of a string constant, up to the closing quote.
;; > { STRCHAR }
SSTRCHR = $0C

;; Rule 13: a further variable of DIM.
;; > , ($43) SDIMSTR
;; > , ($44) SDIMNUM
SDIMLIST = $0D

;; Rule 14: what follows the first value of PRINT: a semicolon or a comma, then a string, a number or nothing.
;; > ; ($45) SSTRING
;; > ; ($46) SEXPR
;; > ; ($47)
;; > , ($48) SSTRING
;; > , ($49) SEXPR
;; > , ($4A)
SPRLIST = $0E

;; Rule 15: one digit.
;; > DIGIT
SDIGIT = $0F

;; Rule 16: a numeric array with its size, in DIM.
;; > SNAME ( ($34) SEXPR SRPAREN
SDIMNUM = $10

;; Rule 17: a right parenthesis.
;; > ) ($72)
SRPAREN = $11

;; Rule 18: the numbers of a line typed for INPUT, separated by commas; <SYNINPUT> calls it.
;; > SSIGNED { , ($81) SSIGNED }
SINNUMS = $12

;; Rule 19: a number with an optional sign.
;; > + ($82) SNUMBER
;; > - ($83) SNUMBER
;; > SNUMBER
SSIGNED = $13

;; Rule 20: the names of the functions that take a number in parentheses.
;;
;; RNDX has a token, $33, but no routine; RND, before it, matches its first three letters first.
;; > PEEK ($2E)
;; > RND ($2F)
;; > SGN ($30)
;; > ABS ($31)
;; > PDL ($32)
SFUNC = $14

;; Rule 21: an operand of a numeric expression.
;; > + ($35) SOPERAND
;; > - ($36) SOPERAND
;; > NOT ($37) SOPERAND
;; > SNUMBER
;; > ( ($38) SEXPR SRPAREN
;; > SSTRING = ($39) SSTRING
;; > SSTRING # ($3A) SSTRING
;; > LEN( ($3B) SSTRING SRPAREN
;; > ASC( ($3C) SSTRING SRPAREN
;; > SCRN( ($3D) SEXPR , ($3E) SEXPR SRPAREN
;; > SFUNC ( ($3F) SEXPR SRPAREN
;; > SNUMVAR
SOPERAND = $15

;; Rule 22: <SOPERAND> without the signs and NOT; no rule or routine calls it.
SUNUSED2 = $16

;; Rule 23: a numeric variable, or an element of an array.
;; > SNAME [( ($2D) SEXPR SRPAREN]
SNUMVAR = $17

;; Rule 24: an assignment, with or without LET.
;; > SSTRDEST = ($70) SSTRING
;; > SNUMVAR = ($71) SEXPR
SASSIGN = $18

;; Rule 25: a variable's name: a letter, then the rest of the name (<SNAMEEND>).
;; > LETTER SNAMEEND
SNAME = $19

;; Rule 26: a statement allowed in a line without a number, and the rest of the statements of <SSTMT>.
;; > REM ($5D) { REMCHAR }
;; > SSTMT2
;; > LET ($5E) SASSIGN
;; > GOTO ($5F) SEXPR
;; > IF ($60) SEXPR STHEN
;; > PRINT ($61) SSTRING { SPRLIST }
;; > PRINT ($62) SEXPR { SPRLIST }
;; > PRINT ($63)
;; > POKE ($64) SEXPR , ($65) SEXPR
;; > COLOR= ($66) SEXPR
;; > PLOT ($67) SEXPR , ($68) SEXPR
;; > HLIN ($69) SEXPR , ($6A) SEXPR AT ($6B) SEXPR
;; > VLIN ($6C) SEXPR , ($6D) SEXPR AT ($6E) SEXPR
;; > VTAB ($6F) SEXPR
;; > SSTMT3
;; > SASSIGN
SIMMED = $1A

;; Rule 27: LIST, POP, NODSP, NOTRACE, DSP, TRACE, PR# and IN#.
;; > LIST ($74) SNUMBER [, ($75) SNUMBER]
;; > LIST ($76)
;; > POP ($77)
;; > NODSP ($78) SSTRVAR
;; > NODSP ($79) SNAME
;; > NOTRACE ($7A)
;; > DSP ($7B) SSTRVAR
;; > DSP ($7C) SNAME
;; > TRACE ($7D)
;; > PR# ($7E) SEXPR
;; > IN# ($7F) SEXPR
SSTMT3 = $1B

;; Rule 28: the rest of a variable's name: letters and digits, up to a reserved word.
;;
;; The byte above where it starts is <USEOPT>, so when its first item fails it matches nothing: a name can be one
;; letter.
;; > { SNAMECH }
SNAMEEND = $1C

;; Rule 29: a character of a name after the first: a letter or a digit, unless a reserved word starts there.
;;
;; A reserved word matches with a token of $85 or above, which the tokenizer treats as a failure (<KEYMATCHED>).
;; > THEN ($85) | TO ($86) | STEP ($87) | AND ($88) | OR ($89) | MOD ($8A) | AT ($8B), which fail
;; > LETTER
;; > SDIGIT
SNAMECH = $1D

;; Rule 30: an operator between two operands.
;; > + ($12) | - ($13) | * ($14) | / ($15)
;; > = ($16) | # ($17) | >= ($18) | > ($19) | <= ($1A) | <> ($1B) | < ($1C)
;; > AND ($1D) | OR ($1E) | MOD ($1F) | ^ ($20)
SOPER = $1E

;; Rule 31: a whole line: a numbered line of statements, a statement of <SIMMED>, or a command.
;; > SNUMBER SSTMT { : ($03) SSTMT }
;; > SIMMED
;; > LOAD ($04) | SAVE ($05) | CON ($06)
;; > RUN ($07) SNUMBER
;; > RUN ($08)
;; > DEL ($09) SNUMBER [, ($0A) SNUMBER]
;; > NEW ($0B) | CLR ($0C)
;; > AUTO ($0D) SNUMBER [, ($0E) SNUMBER]
;; > MAN ($0F)
;; > HIMEM: ($10) SEXPR
;; > LOMEM: ($11) SEXPR
SLINE = $1F

;; The syntax table's first page: rules for statements, names and INPUT's numbers, and the reserved words.
;;
;; Its first byte, $50, is the number its tokens count from, so its keywords have the tokens $51 (END, at the top)
;; to $8B. <SYNLINE> and <SYNINPUT> are where the tokenizer starts, and RULEnn where each rule starts.
;; See: <SYNTABL2>, <SYNTABLNDX>, <STARTRULE>
SYNTABL:
    .byte $50                       ; $EC00 the count the tokens of this page start from
RULE01 = *                          ;; where rule <SUNUSED1> starts
    .byte USEOPT | SNUMBER          ; $EC01
    .byte USEEND | SDIGIT           ; $EC02
    .byte LETTER | LAST             ; $EC03
    KEYEND "AT"                     ; $EC04 token $8B, a reserved word
    KEYEND "MOD"                    ; $EC06 token $8A, a reserved word
    KEYEND "OR"                     ; $EC09 token $89, a reserved word
    KEYEND "AND"                    ; $EC0B token $88, a reserved word
    KEYEND "STEP"                   ; $EC0E token $87, a reserved word
    KEYEND "TO"                     ; $EC12 token $86, a reserved word
RULE1D = * + 3                      ;; where rule <SNAMECH> starts
    KEYEND "THEN"                   ; $EC14 token $85, a reserved word
    .byte USEEND | SNAMEEND         ; $EC18
RULE19 = *                          ;; where rule <SNAME> starts
    .byte LETTER                    ; $EC19
    .byte SYNERR                    ; $EC1A
    .byte USEEND | SNUMBER          ; $EC1B
    .byte USEALT | SNUMBER          ; $EC1C
    KEY "-"                         ; $EC1D token $83
    .byte USEALT | SNUMBER          ; $EC1E
RULE13 = *                          ;; where rule <SSIGNED> starts
    KEY "+"                         ; $EC1F token $82
    .byte AGAIN                     ; $EC20
RULE1C = *                          ;; where rule <SNAMEEND> starts
    .byte USE | SNAMECH             ; $EC21
    .byte USEOPT | SNUMBER          ; $EC22
    .byte AGAIN2                    ; $EC23
    KEY ","                         ; $EC24 token $81
RULE12 = *                          ;; where rule <SINNUMS> starts
    .byte USEOPT | SSIGNED          ; $EC25
    .byte SYNERR                    ; $EC26
    .byte SYNERR                    ; $EC27
    .byte USEALT | SNUMBER          ; $EC28
    .byte ENDLINE                   ; $EC29
    KEY "_"                         ; $EC2A token $80
SYNINPUT = *                        ;; where it starts on a line INPUT reads
    .byte USE | SINNUMS             ; $EC2B
    .byte USEEND | SEXPR            ; $EC2C
    KEY "IN#"                       ; $EC2D token $7F
    .byte USEALT | SEXPR            ; $EC30
    KEY "PR#"                       ; $EC31 token $7E
    KEYEND "TRACE"                  ; $EC34 token $7D
    .byte USEALT | SNAME            ; $EC39
    KEY "DSP"                       ; $EC3A token $7C
    .byte USEALT | SSTRVAR          ; $EC3D
    KEY "DSP"                       ; $EC3E token $7B
    KEYEND "NOTRACE"                ; $EC41 token $7A
    .byte USEALT | SNAME            ; $EC48
    KEY "NODSP"                     ; $EC49 token $79
    .byte USEALT | SSTRVAR          ; $EC4E
    KEY "NODSP"                     ; $EC4F token $78
    KEYEND "POP"                    ; $EC54 token $77
    KEYEND "LIST"                   ; $EC57 token $76
    .byte USEALT | SNUMBER          ; $EC5B
    KEY ","                         ; $EC5C token $75
    .byte USEOPT | SNUMBER          ; $EC5D
RULE1B = * + 3                      ;; where rule <SSTMT3> starts
    KEY "LIST"                      ; $EC5E token $74
    .byte SYNERR                    ; $EC62
    .byte USEEND | SNUMBER          ; $EC63
    KEY ")"                         ; $EC64 token $73
RULE11 = *                          ;; where rule <SRPAREN> starts
    KEYEND ")"                      ; $EC65 token $72
    .byte USEEND | SEXPR            ; $EC66
    KEY "="                         ; $EC67 token $71
    .byte USE | SNUMVAR             ; $EC68
    .byte USEALT | SSTRING          ; $EC69
    KEY "="                         ; $EC6A token $70
RULE18 = *                          ;; where rule <SASSIGN> starts
    .byte USE | SSTRDEST            ; $EC6B
    .byte USEEND | SASSIGN          ; $EC6C
    .byte USEALT | SSTMT3           ; $EC6D
    .byte USEALT | SEXPR            ; $EC6E
    KEY "VTAB"                      ; $EC6F token $6F
    .byte USEALT | SEXPR            ; $EC73
    KEY "AT"                        ; $EC74 token $6E
    .byte USE | SEXPR               ; $EC76
    KEY ","                         ; $EC77 token $6D
    .byte USE | SEXPR               ; $EC78
    KEY "VLIN"                      ; $EC79 token $6C
    .byte USEALT | SEXPR            ; $EC7D
    KEY "AT"                        ; $EC7E token $6B
    .byte USE | SEXPR               ; $EC80
    KEY ","                         ; $EC81 token $6A
    .byte USE | SEXPR               ; $EC82
    KEY "HLIN"                      ; $EC83 token $69
    .byte USEALT | SEXPR            ; $EC87
    KEY ","                         ; $EC88 token $68
    .byte USE | SEXPR               ; $EC89
    KEY "PLOT"                      ; $EC8A token $67
    .byte USEALT | SEXPR            ; $EC8E
    KEY "COLOR="                    ; $EC8F token $66
    .byte USEALT | SEXPR            ; $EC95
    KEY ","                         ; $EC96 token $65
    .byte USE | SEXPR               ; $EC97
    KEY "POKE"                      ; $EC98 token $64
    KEYEND "PRINT"                  ; $EC9C token $63
    .byte AGAIN                     ; $ECA1
    .byte USE | SPRLIST             ; $ECA2
    .byte USEOPT | SEXPR            ; $ECA3
    KEY "PRINT"                     ; $ECA4 token $62
    .byte AGAIN                     ; $ECA9
    .byte USE | SPRLIST             ; $ECAA
    .byte USEOPT | SSTRING          ; $ECAB
    KEY "PRINT"                     ; $ECAC token $61
    .byte USEALT | STHEN            ; $ECB1
    .byte USE | SEXPR               ; $ECB2
    KEY "IF"                        ; $ECB3 token $60
    .byte USEALT | SEXPR            ; $ECB5
    KEY "GOTO"                      ; $ECB6 token $5F
    .byte USEALT | SASSIGN          ; $ECBA
    KEY "LET"                       ; $ECBB token $5E
    .byte USEALT | SSTMT2           ; $ECBE
    .byte AGAIN                     ; $ECBF
    .byte REMCHAR                   ; $ECC0
RULE1A = * + 2                      ;; where rule <SIMMED> starts
    KEY "REM"                       ; $ECC1 token $5D
    .byte USEALT | SEXPR            ; $ECC4
    KEY "GOSUB"                     ; $ECC5 token $5C
    KEYEND "RETURN"                 ; $ECCA token $5B
    .byte AGAIN2                    ; $ECD0
    KEY ","                         ; $ECD1 token $5A
    .byte USEOPT | SNAME            ; $ECD2
    KEY "NEXT"                      ; $ECD3 token $59
    .byte USEALT | SEXPR            ; $ECD7
    KEY "STEP"                      ; $ECD8 token $58
    .byte USEOPT | SEXPR            ; $ECDC
    KEY "TO"                        ; $ECDD token $57
    .byte USE | SEXPR               ; $ECDF
    KEY "="                         ; $ECE0 token $56
    .byte USE | SNAME               ; $ECE1
    KEY "FOR"                       ; $ECE2 token $55
    .byte AGAIN                     ; $ECE5
    .byte USE | SINVARS             ; $ECE6
    .byte USEOPT | SNUMVAR          ; $ECE7
    KEY "INPUT"                     ; $ECE8 token $54
    .byte AGAIN                     ; $ECED
    .byte USE | SINVARS             ; $ECEE
    .byte USEOPT | SSTRING          ; $ECEF
    KEY "INPUT"                     ; $ECF0 token $53
    .byte AGAIN                     ; $ECF5
    .byte USE | SINVARS             ; $ECF6
    .byte USEOPT | SSTRDEST         ; $ECF7
    KEY "INPUT"                     ; $ECF8 token $52
RULE02 = * + 2                      ;; where rule <SSTMT> starts
    KEYEND "END"                    ; $ECFD token $51

;; The syntax table's second page: rules for expressions, strings, PRINT, DIM and the commands, and the operators.
;;
;; Its first byte, 0, is the number its tokens count from, so its keywords have the tokens $01 to $50. The top of the
;; page is where the tokenizer starts on a typed line (<SYNLINE>): the rule for a line, then the underline that ends
;; it (token $01), then <ENDLINE>; a line with nothing on it matches the underline at $EDFB instead (token $02).
;; See: <SYNTABL>, <SYNLINE>
SYNTABL2:
    .byte $00                       ; $ED00 the count the tokens of this page start from
    .byte USEEND | SEXPR            ; $ED01
    KEY "TAB"                       ; $ED02 token $50
    .byte AGAIN                     ; $ED05
    .byte USE | SDIMLIST            ; $ED06
    .byte USEOPT | SDIMNUM          ; $ED07
    KEY "DIM"                       ; $ED08 token $4F
    .byte AGAIN                     ; $ED0B
    .byte USE | SDIMLIST            ; $ED0C
    .byte USEOPT | SDIMSTR          ; $ED0D
    KEY "DIM"                       ; $ED0E token $4E
    .byte USEALT | SEXPR            ; $ED11
    KEY "CALL"                      ; $ED12 token $4D
    KEYEND "GR"                     ; $ED16 token $4C
RULE0B = * + 3                      ;; where rule <SSTMT2> starts
    KEYEND "TEXT"                   ; $ED18 token $4B
    .byte SYNERR                    ; $ED1C
    .byte USEEND | SDIMLIST         ; $ED1D
    KEYEND ","                      ; $ED1E token $4A
    .byte USEALT | SEXPR            ; $ED1F
    KEY ","                         ; $ED20 token $49
    .byte USEALT | SSTRING          ; $ED21
    KEY ","                         ; $ED22 token $48
    KEYEND ";"                      ; $ED23 token $47
    .byte USEALT | SEXPR            ; $ED24
    KEY ";"                         ; $ED25 token $46
    .byte USEALT | SSTRING          ; $ED26
RULE0E = *                          ;; where rule <SPRLIST> starts
    KEY ";"                         ; $ED27 token $45
    .byte USEEND | SDIMNUM          ; $ED28
    KEY ","                         ; $ED29 token $44
    .byte USEALT | SDIMSTR          ; $ED2A
RULE0D = *                          ;; where rule <SDIMLIST> starts
    KEY ","                         ; $ED2B token $43
    .byte AGAIN                     ; $ED2C
RULE0C = *                          ;; where rule <SSTRCHR> starts
    .byte STRCHAR                   ; $ED2D
    .byte USEEND | SRPAREN          ; $ED2E
    .byte USE | SEXPR               ; $ED2F
    KEY "("                         ; $ED30 token $42
RULE0A = *                          ;; where rule <SSTRDEST> starts
    .byte USEOPT | SSTRVAR          ; $ED31
    KEY "$"                         ; $ED32 token $41
    .byte LETTER                    ; $ED33
    KEYEND "$"                      ; $ED34 token $40
RULE09 = *                          ;; where rule <SSTRVAR> starts
    .byte USE | SNAME               ; $ED35
    .byte USEEND | SNUMVAR          ; $ED36
    .byte USEALT | SRPAREN          ; $ED37
    .byte USE | SEXPR               ; $ED38
    KEY "("                         ; $ED39 token $3F
    .byte USE | SFUNC               ; $ED3A
    .byte USEALT | SRPAREN          ; $ED3B
    .byte USE | SEXPR               ; $ED3C
    KEY ","                         ; $ED3D token $3E
    .byte USE | SEXPR               ; $ED3E
    KEY "SCRN("                     ; $ED3F token $3D
    .byte USEALT | SRPAREN          ; $ED44
    .byte USE | SSTRING             ; $ED45
    KEY "ASC("                      ; $ED46 token $3C
    .byte USEALT | SRPAREN          ; $ED4A
    .byte USE | SSTRING             ; $ED4B
    KEY "LEN("                      ; $ED4C token $3B
    .byte USEALT | SSTRING          ; $ED50
    KEY "#"                         ; $ED51 token $3A
    .byte USE | SSTRING             ; $ED52
    .byte USEALT | SSTRING          ; $ED53
    KEY "="                         ; $ED54 token $39
    .byte USE | SSTRING             ; $ED55
    .byte USEALT | SRPAREN          ; $ED56
    .byte USE | SEXPR               ; $ED57
    KEY "("                         ; $ED58 token $38
RULE16 = *                          ;; where rule <SUNUSED2> starts
    .byte USEALT | SNUMBER          ; $ED59
    .byte USEALT | SOPERAND         ; $ED5A
    KEY "NOT"                       ; $ED5B token $37
    .byte USEALT | SOPERAND         ; $ED5E
    KEY "-"                         ; $ED5F token $36
    .byte USEALT | SOPERAND         ; $ED60
RULE15 = *                          ;; where rule <SOPERAND> starts
    KEY "+"                         ; $ED61 token $35
    .byte USEEND | SRPAREN          ; $ED62
    .byte USE | SEXPR               ; $ED63
    KEY "("                         ; $ED64 token $34
RULE10 = *                          ;; where rule <SDIMNUM> starts
    .byte USE | SNAME               ; $ED65
    KEY "RNDX"                      ; $ED66 token $33
    KEYEND "PDL"                    ; $ED6A token $32
    KEYEND "ABS"                    ; $ED6D token $31
    KEYEND "SGN"                    ; $ED70 token $30
    KEYEND "RND"                    ; $ED73 token $2F
RULE14 = * + 3                      ;; where rule <SFUNC> starts
    KEYEND "PEEK"                   ; $ED76 token $2E
    .byte USEEND | SRPAREN          ; $ED7A
    .byte USE | SEXPR               ; $ED7B
    KEY "("                         ; $ED7C token $2D
RULE17 = *                          ;; where rule <SNUMVAR> starts
    .byte USEOPT | SNAME            ; $ED7D
    .byte DIGIT                     ; $ED7E
RULE0F = *                          ;; where rule <SDIGIT> starts
    .byte DIGIT | LAST              ; $ED7F
    .byte USEEND | SDIGIT           ; $ED80
    .byte AGAIN                     ; $ED81
    .byte USE | SDIGIT              ; $ED82
RULE00 = *                          ;; where rule <SNUMBER> starts
    .byte USEOPT | SDIGIT           ; $ED83
    .byte SYNERR                    ; $ED84
    .byte USEEND | SRPAREN          ; $ED85
    .byte USE | SSUBSTR             ; $ED86
    KEY "("                         ; $ED87 token $2A
    .byte USEOPT | SSTRVAR          ; $ED88
    .byte $C2                       ; $ED89 " (last), token $29
    .byte USE | SSTRCHR             ; $ED8A
RULE08 = *                          ;; where rule <SSTRING> starts
    .byte $82                       ; $ED8B ", token $28
    .byte USEEND | SNUMVAR          ; $ED8C
    KEY ","                         ; $ED8D token $27
    .byte USEALT | SSTRDEST         ; $ED8E
RULE05 = *                          ;; where rule <SINVARS> starts
    KEY ","                         ; $ED8F token $26
    .byte USEEND | SSTMT            ; $ED90
    KEY "THEN"                      ; $ED91 token $25
    .byte USEALT | SNUMBER          ; $ED95
RULE04 = * + 3                      ;; where rule <STHEN> starts
    KEY "THEN"                      ; $ED96 token $24
    .byte USEEND | SDIGIT           ; $ED9A
    .byte AGAIN2                    ; $ED9B
    .byte USE | SOPER               ; $ED9C
RULE07 = *                          ;; where rule <SEXPR> starts
    .byte USEOPT | SOPERAND         ; $ED9D
    KEY ","                         ; $ED9E token $23
RULE06 = *                          ;; where rule <SSUBSTR> starts
    .byte USEOPT | SEXPR            ; $ED9F
    .byte USEEND | SRPAREN          ; $EDA0
    .byte USE | SEXPR               ; $EDA1
    KEY "("                         ; $EDA2 token $22
RULE03 = *                          ;; where rule <SDIMSTR> starts
    .byte USE | SSTRVAR             ; $EDA3
    KEY "+"                         ; $EDA4 token $21
    KEYEND "^"                      ; $EDA5 token $20
    KEYEND "MOD"                    ; $EDA6 token $1F
    KEYEND "OR"                     ; $EDA9 token $1E
    KEYEND "AND"                    ; $EDAB token $1D
    KEYEND "<"                      ; $EDAE token $1C
    KEYEND "<>"                     ; $EDAF token $1B
    KEYEND "<="                     ; $EDB1 token $1A
    KEYEND ">"                      ; $EDB3 token $19
    KEYEND ">="                     ; $EDB4 token $18
    KEYEND "#"                      ; $EDB6 token $17
    KEYEND "="                      ; $EDB7 token $16
    KEYEND "/"                      ; $EDB8 token $15
    KEYEND "*"                      ; $EDB9 token $14
    KEYEND "-"                      ; $EDBA token $13
RULE1E = *                          ;; where rule <SOPER> starts
    KEYEND "+"                      ; $EDBB token $12
    .byte SYNERR                    ; $EDBC
    .byte USEEND | SEXPR            ; $EDBD
    KEY "LOMEM:"                    ; $EDBE token $11
    .byte USEALT | SEXPR            ; $EDC4
    KEY "HIMEM:"                    ; $EDC5 token $10
    KEYEND "MAN"                    ; $EDCB token $0F
    .byte USEALT | SNUMBER          ; $EDCE
    KEY ","                         ; $EDCF token $0E
    .byte USEOPT | SNUMBER          ; $EDD0
    KEY "AUTO"                      ; $EDD1 token $0D
    KEYEND "CLR"                    ; $EDD5 token $0C
    KEYEND "NEW"                    ; $EDD8 token $0B
    .byte USEALT | SNUMBER          ; $EDDB
    KEY ","                         ; $EDDC token $0A
    .byte USEOPT | SNUMBER          ; $EDDD
    KEY "DEL"                       ; $EDDE token $09
    KEYEND "RUN"                    ; $EDE1 token $08
    .byte USEALT | SNUMBER          ; $EDE4
    KEY "RUN"                       ; $EDE5 token $07
    KEYEND "CON"                    ; $EDE8 token $06
    KEYEND "SAVE"                   ; $EDEB token $05
    KEYEND "LOAD"                   ; $EDEF token $04
    .byte USEALT | SIMMED           ; $EDF3
    .byte AGAIN2                    ; $EDF4
    KEY ":"                         ; $EDF5 token $03
    .byte USEOPT | SSTMT            ; $EDF6
RULE1F = *                          ;; where rule <SLINE> starts
    .byte USEOPT | SNUMBER          ; $EDF7
    .byte SYNERR                    ; $EDF8
    .byte USEALT | SNUMBER          ; $EDF9
    .byte ENDLINE                   ; $EDFA
    KEY "_"                         ; $EDFB token $02
    .byte USEALT | SNUMBER          ; $EDFC
    .byte ENDLINE                   ; $EDFD
    KEY "_"                         ; $EDFE token $01
SYNLINE = *                         ;; where the tokenizer starts on a typed line
    .byte USE | SLINE               ; $EDFF
    .assert * = $EE00, "The syntax table fills two pages."
