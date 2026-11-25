; retrocore: style=strict
;; Integer BASIC: the syntax table
;;
;; Integer BASIC's grammar, which the tokenizer (Tokenizer.asm) matches each typed line against, and from which the
;; keywords get their tokens. It fills the two pages at $EC00-$EDFF, and each rule is a list of alternatives, each a
;; list of items; the items are the ITEM_ codes below, and <RuleStarts> (Operators.asm) gives the address where each
;; of the 32 rules starts.
;;
;; The tokenizer reads a rule downward, from the higher address to the lower. This source lists the table in
;; address order, so a rule reads from the line where its label stands up toward the top of the file, and a keyword
;; is written in its usual spelling but stored backward: `Keyword "LIST"` places T, S, I, L at increasing addresses,
;; so the tokenizer meets L first. Each rule ends where its last alternative ends, and many rules end in the middle
;; of another rule's bytes, sharing that rule's later alternatives: the statements allowed in immediate mode
;; (<Syntax::RULE_IMMEDIATE_STATEMENT>) are the last alternatives of the statement rule
;; (<Syntax::RULE_STATEMENT>), for example.
;;
;; Tokens. A keyword's token is its place in the table: the number of keywords between it and the top of its page,
;; counting itself, plus the first byte of the page (<Syntax::FIRST_PAGE_TOKEN_BASE> at $EC00,
;; <Syntax::SECOND_PAGE_TOKEN_BASE> at $ED00). Each place where a word appears gives it a different token, which is
;; how the interpreter knows, for instance, which of the dozen commas it has: the comma between INPUT's variables is
;; $27, the comma of PLOT $68. The tokens of `THEN`, `TO`, `STEP`, `AND`, `OR`, `MOD` and `AT` at the bottom of the
;; first page are $85 and up: these words cannot be part of a variable's name, and matching one there ends the name.
;;
;; In the grammar of each rule, given with the rule's number below, a keyword is followed by its token in
;; parentheses, a rule is written as its RULE_ name in lower case without the prefix (expression is
;; <Syntax::RULE_EXPRESSION>), and LETTER, DIGIT, STRING_CHARACTER and REMARK_CHARACTER are the items of those
;; ITEM_ names; [ ] encloses what may be left out and { } what may repeat, zero or more times. Alternatives are
;; tried in order and the first that matches is kept: when an item after a rule's call fails, the tokenizer does not
;; go back into that rule for another alternative, but tries the caller's next one. The grammars leave out the
;; alternatives a rule reaches only by running on into another rule's bytes, where no text can match that an earlier
;; alternative did not.
;;
;; Part of IntegerBasic.asm; it follows Messages.asm, at $EC00.

;; Integer BASIC's grammar: the syntax table, its items and its rules.
.scope Syntax

; The items, as the tokenizer reads them (Tokenizer.asm).

;; An item that is a SYNTAX error: none of the alternatives before it matched.
;; Also: SYNERR (UNKN)
ITEM_SYNTAX_ERROR = $00

;; An item that copies one character of a string constant into the tokens, up to a quote or the line's end.
;; Also: STRCHAR (UNKN)
ITEM_STRING_CHARACTER = $01

;; An item that copies one character of a remark into the tokens, up to the line's end.
;; Also: REMCHAR (UNKN)
ITEM_REMARK_CHARACTER = $02

;; The end of the match: the tokenizer returns.
;; Also: ENDLINE (UNKN)
ITEM_LINE_MATCHED = $03

;; Repeats the two items before it (at the two higher addresses) while they match.
;;
;; When a repeated item fails, the item before it decides, as for any failure: a call with
;; <ITEM_CALL_THEN_OPTIONAL> there lets the rule match.
;; Also: AGAIN2 (UNKN)
ITEM_REPEAT_TWO = $7E

;; Repeats the item before it while it matches, as <ITEM_REPEAT_TWO> does.
;; Also: AGAIN (UNKN)
ITEM_REPEAT = $7F

;; Bit 7 of an item: a character, which the line's next character must be, after blanks.
ITEM_CHARACTER = $80

;; What a character item's low 6 bits hold its character less: they hold $A0 to $DF.
CHARACTER_OFFSET = $A0

;; Bit 6 of an item: the last item of its alternative.
;;
;; On a character, it also ends the keyword, and another alternative always follows.
;; Also: LAST (UNKN)
ITEM_LAST = $40

;; An item matching any letter, which is copied into the tokens: the character item of a blank.
;; Also: LETTER (UNKN)
ITEM_LETTER = ITEM_CHARACTER | (' ' - CHARACTER_OFFSET)

;; An item matching any digit, which is copied into the tokens: the character item of !.
;; Also: DIGIT (UNKN)
ITEM_DIGIT = ITEM_CHARACTER | ('!' - CHARACTER_OFFSET)

; The calls of a rule: one of these, ORed with the rule's number. The items $00 to $03 are not calls, so rules 0
; to 3 can be called only with the last three.

;; A call of a rule, an item that the next item follows.
;; Also: USE (UNKN)
ITEM_CALL = $00

;; A call of a rule after which the rest of the alternative is optional: if the item after it fails, the rule has
;; matched without the rest.
;; Also: USEOPT (UNKN)
ITEM_CALL_THEN_OPTIONAL = $20

;; A call of a rule as the last item of the rule's last alternative: if it fails, the rule fails.
;; Also: USEEND (UNKN)
ITEM_CALL_ENDING_RULE = ITEM_LAST

;; A call of a rule as the last item of an alternative that has another after it: bit 5, which before the last
;; item makes the rest optional, here says another alternative follows.
;; Also: USEALT (UNKN)
ITEM_CALL_ENDING_ALTERNATIVE = ITEM_LAST | ITEM_CALL_THEN_OPTIONAL

;; Places a keyword or a punctuation character in the syntax table, stored backward.
;;
;; Each character is stored less <Syntax::CHARACTER_OFFSET>, with bit 7 set (<Syntax::ITEM_CHARACTER>). The last
;; character is stored first, at the lowest address. Earlier versions of this source called it KEY.
;; Parameters:
;;   text = the keyword
.macro Keyword text
    .repeat .strlen(text), I
        .byte (.strat(text, .strlen(text) - 1 - I) - Syntax::CHARACTER_OFFSET) | Syntax::ITEM_CHARACTER
    .endrepeat
.endmacro

;; Places a keyword, stored backward as <Keyword> does, that is the last item of its alternative.
;;
;; Its last character, at the lowest address, has <Syntax::ITEM_LAST> set. Earlier versions of this source called
;; it KEYEND.
;; Parameters:
;;   text = the keyword
.macro KeywordEndingAlternative text
    .byte (.strat(text, .strlen(text) - 1) - Syntax::CHARACTER_OFFSET) | Syntax::ITEM_CHARACTER | Syntax::ITEM_LAST
    .repeat .strlen(text) - 1, I
        .byte (.strat(text, .strlen(text) - 2 - I) - Syntax::CHARACTER_OFFSET) | Syntax::ITEM_CHARACTER
    .endrepeat
.endmacro

;; Places a call of a rule (<Syntax::ITEM_CALL>), which the next item follows.
;; Parameters:
;;   rule = the RULE_ number, 4 or more
.macro CallRule rule
    .assert rule > Syntax::ITEM_LINE_MATCHED && rule <= Syntax::RULE_LINE, "A plain call is of rule 4 to 31."
    .byte Syntax::ITEM_CALL | rule
.endmacro

;; Places a call of a rule after which the rest of the alternative is optional (<Syntax::ITEM_CALL_THEN_OPTIONAL>).
;; Parameters:
;;   rule = the RULE_ number
.macro CallRuleThenOptional rule
    .byte Syntax::ITEM_CALL_THEN_OPTIONAL | rule
.endmacro

;; Places a call of a rule that ends the rule's last alternative (<Syntax::ITEM_CALL_ENDING_RULE>).
;; Parameters:
;;   rule = the RULE_ number
.macro CallRuleEndingRule rule
    .byte Syntax::ITEM_CALL_ENDING_RULE | rule
.endmacro

;; Places a call of a rule that ends an alternative another follows (<Syntax::ITEM_CALL_ENDING_ALTERNATIVE>).
;; Parameters:
;;   rule = the RULE_ number
.macro CallRuleEndingAlternative rule
    .byte Syntax::ITEM_CALL_ENDING_ALTERNATIVE | rule
.endmacro

; The rules, by number: an item's low 5 bits.

;; Rule 0: a numeric constant, one or more digits.
;;
;; When it returns, the tokenizer turns the digits it copied into the constant's form: the first digit, then the
;; value (<Tokenizer::RuleMatched>).
;; > digit { digit }
;; Also: SNUMBER (UNKN)
RULE_NUMBER = $00

;; Rule 1: no rule or routine calls it.
;; > number [dim_array]
;; Also: SUNUSED1 (UNKN)
RULE_NUMBER_THEN_ARRAY = $01

;; Rule 2: a statement in a numbered line: the statements only a program can use, then those of
;; <RULE_IMMEDIATE_STATEMENT>, whose bytes it shares.
;; > END ($51)
;; > INPUT ($52) string_destination { input_next }
;; > INPUT ($53) string { input_next }
;; > INPUT ($54) number_variable { input_next }
;; > FOR ($55) name = ($56) expression TO ($57) expression [STEP ($58) expression]
;; > NEXT ($59) name { , ($5A) name }
;; > RETURN ($5B)
;; > GOSUB ($5C) expression
;; > and the alternatives of immediate_statement
;; Also: SSTMT (UNKN)
RULE_STATEMENT = $02

;; Rule 3: a string variable with its size, in DIM.
;; > string_variable ( ($22) expression right_parenthesis
;; Also: SDIMSTR (UNKN)
RULE_DIM_STRING = $03

;; Rule 4: what follows IF's condition: THEN and a line number, or THEN and a statement.
;; > THEN ($24) number
;; > THEN ($25) statement
;; Also: STHEN (UNKN)
RULE_THEN = $04

;; Rule 5: a further variable of INPUT.
;; > , ($26) string_destination
;; > , ($27) number_variable
;; Also: SINVARS (UNKN)
RULE_INPUT_NEXT = $05

;; Rule 6: a substring's positions.
;; > expression [, ($23) expression]
;; Also: SSUBSTR (UNKN)
RULE_SUBSTRING = $06

;; Rule 7: a numeric expression: operands with operators between them.
;; > operand { operator operand }
;; Also: SEXPR (UNKN)
RULE_EXPRESSION = $07

;; Rule 8: a string: a constant, or a variable with an optional substring.
;; > " ($28) string_characters " ($29)
;; > string_variable [( ($2A) substring right_parenthesis]
;; Also: SSTRING (UNKN)
RULE_STRING = $08

;; Rule 9: a string variable's name, which ends in $ (token $40).
;; > name $ ($40)
;; Also: SSTRVAR (UNKN)
RULE_STRING_VARIABLE = $09

;; Rule 10: a string variable to store into, with an optional position.
;; > string_variable [( ($42) expression right_parenthesis]
;; Also: SSTRDEST (UNKN)
RULE_STRING_DESTINATION = $0A

;; Rule 11: TEXT, GR, CALL, DIM and TAB.
;; > TEXT ($4B)
;; > GR ($4C)
;; > CALL ($4D) expression
;; > DIM ($4E) dim_string { dim_next }
;; > DIM ($4F) dim_array { dim_next }
;; > TAB ($50) expression
;; Also: SSTMT2 (UNKN)
RULE_STATEMENTS_TEXT_TO_TAB = $0B

;; Rule 12: the characters of a string constant, up to the closing quote.
;; > { STRING_CHARACTER }
;; Also: SSTRCHR (UNKN)
RULE_STRING_CHARACTERS = $0C

;; Rule 13: a further variable of DIM.
;; > , ($43) dim_string
;; > , ($44) dim_array
;; Also: SDIMLIST (UNKN)
RULE_DIM_NEXT = $0D

;; Rule 14: what follows the first value of PRINT: a semicolon or a comma, then a string, a number or nothing.
;; > ; ($45) string
;; > ; ($46) expression
;; > ; ($47)
;; > , ($48) string
;; > , ($49) expression
;; > , ($4A)
;; Also: SPRLIST (UNKN)
RULE_PRINT_NEXT = $0E

;; Rule 15: one digit.
;; > DIGIT
;; Also: SDIGIT (UNKN)
RULE_DIGIT = $0F

;; Rule 16: a numeric array with its size, in DIM.
;; > name ( ($34) expression right_parenthesis
;; Also: SDIMNUM (UNKN)
RULE_DIM_ARRAY = $10

;; Rule 17: a right parenthesis.
;; > ) ($72)
;; Also: SRPAREN (UNKN)
RULE_RIGHT_PARENTHESIS = $11

;; Rule 18: the numbers of a line typed for INPUT, separated by commas; <InputLineStart> calls it.
;; > signed_number { , ($81) signed_number }
;; Also: SINNUMS (UNKN)
RULE_INPUT_NUMBERS = $12

;; Rule 19: a number with an optional sign.
;; > + ($82) number
;; > - ($83) number
;; > number
;; Also: SSIGNED (UNKN)
RULE_SIGNED_NUMBER = $13

;; Rule 20: the names of the functions that take a number in parentheses.
;;
;; RNDX has a token, $33, but no routine; RND, before it, matches its first three letters first.
;; > PEEK ($2E)
;; > RND ($2F)
;; > SGN ($30)
;; > ABS ($31)
;; > PDL ($32)
;; Also: SFUNC (UNKN)
RULE_FUNCTION_NAME = $14

;; Rule 21: an operand of a numeric expression.
;; > + ($35) operand
;; > - ($36) operand
;; > NOT ($37) operand
;; > number
;; > ( ($38) expression right_parenthesis
;; > string = ($39) string
;; > string # ($3A) string
;; > LEN( ($3B) string right_parenthesis
;; > ASC( ($3C) string right_parenthesis
;; > SCRN( ($3D) expression , ($3E) expression right_parenthesis
;; > function_name ( ($3F) expression right_parenthesis
;; > number_variable
;; Also: SOPERAND (UNKN)
RULE_OPERAND = $15

;; Rule 22: <RULE_OPERAND> without the signs and NOT; no rule or routine calls it.
;; Also: SUNUSED2 (UNKN)
RULE_UNSIGNED_OPERAND = $16

;; Rule 23: a numeric variable, or an element of an array.
;; > name [( ($2D) expression right_parenthesis]
;; Also: SNUMVAR (UNKN)
RULE_NUMBER_VARIABLE = $17

;; Rule 24: an assignment, with or without LET.
;; > string_destination = ($70) string
;; > number_variable = ($71) expression
;; Also: SASSIGN (UNKN)
RULE_ASSIGNMENT = $18

;; Rule 25: a variable's name: a letter, then the rest of the name (<RULE_NAME_REST>).
;; > LETTER name_rest
;; Also: SNAME (UNKN)
RULE_NAME = $19

;; Rule 26: a statement allowed in a line without a number, and the rest of the statements of <RULE_STATEMENT>.
;; > REM ($5D) { REMARK_CHARACTER }
;; > statements_text_to_tab
;; > LET ($5E) assignment
;; > GOTO ($5F) expression
;; > IF ($60) expression then
;; > PRINT ($61) string { print_next }
;; > PRINT ($62) expression { print_next }
;; > PRINT ($63)
;; > POKE ($64) expression , ($65) expression
;; > COLOR= ($66) expression
;; > PLOT ($67) expression , ($68) expression
;; > HLIN ($69) expression , ($6A) expression AT ($6B) expression
;; > VLIN ($6C) expression , ($6D) expression AT ($6E) expression
;; > VTAB ($6F) expression
;; > statements_list_to_in
;; > assignment
;; Also: SIMMED (UNKN)
RULE_IMMEDIATE_STATEMENT = $1A

;; Rule 27: LIST, POP, NODSP, NOTRACE, DSP, TRACE, PR# and IN#.
;; > LIST ($74) number [, ($75) number]
;; > LIST ($76)
;; > POP ($77)
;; > NODSP ($78) string_variable
;; > NODSP ($79) name
;; > NOTRACE ($7A)
;; > DSP ($7B) string_variable
;; > DSP ($7C) name
;; > TRACE ($7D)
;; > PR# ($7E) expression
;; > IN# ($7F) expression
;; Also: SSTMT3 (UNKN)
RULE_STATEMENTS_LIST_TO_IN = $1B

;; Rule 28: the rest of a variable's name: letters and digits, up to a reserved word.
;;
;; The byte above where it starts is an <ITEM_CALL_THEN_OPTIONAL> call, so when its first item fails it matches
;; nothing: a name can be one letter.
;; > { name_character }
;; Also: SNAMEEND (UNKN)
RULE_NAME_REST = $1C

;; Rule 29: a character of a name after the first: a letter or a digit, unless a reserved word starts there.
;;
;; A reserved word matches with a token of $85 or above, which the tokenizer treats as a failure (<WriteKeywordToken>).
;; > THEN ($85) | TO ($86) | STEP ($87) | AND ($88) | OR ($89) | MOD ($8A) | AT ($8B), which fail
;; > LETTER
;; > digit
;; Also: SNAMECH (UNKN)
RULE_NAME_CHARACTER = $1D

;; Rule 30: an operator between two operands.
;; > + ($12) | - ($13) | * ($14) | / ($15)
;; > = ($16) | # ($17) | >= ($18) | > ($19) | <= ($1A) | <> ($1B) | < ($1C)
;; > AND ($1D) | OR ($1E) | MOD ($1F) | ^ ($20)
;; Also: SOPER (UNKN)
RULE_OPERATOR = $1E

;; Rule 31: a whole line: a numbered line of statements, a statement of <RULE_IMMEDIATE_STATEMENT>, or a command.
;; > number statement { : ($03) statement }
;; > immediate_statement
;; > LOAD ($04) | SAVE ($05) | CON ($06)
;; > RUN ($07) number
;; > RUN ($08)
;; > DEL ($09) number [, ($0A) number]
;; > NEW ($0B) | CLR ($0C)
;; > AUTO ($0D) number [, ($0E) number]
;; > MAN ($0F)
;; > HIMEM: ($10) expression
;; > LOMEM: ($11) expression
;; Also: SLINE (UNKN)
RULE_LINE = $1F

; The two pages' first bytes, which the tokens of their keywords count from.

;; The first byte of the first page: its keywords have the tokens $51 (END, at the top) to $8B.
;;
;; Rule 1, which starts at the next byte, reads it as its second item: a call of <RULE_DIM_ARRAY> ending the rule.
FIRST_PAGE_TOKEN_BASE = $50
.assert FIRST_PAGE_TOKEN_BASE = ITEM_CALL_ENDING_RULE | RULE_DIM_ARRAY, "Rule 1 reads the token base as an item."

;; The first byte of the second page: its keywords have the tokens $01 to $50.
SECOND_PAGE_TOKEN_BASE = $00

;; The syntax table's first page: rules for statements, names and INPUT's numbers, and the reserved words.
;;
;; Its first byte is <FIRST_PAGE_TOKEN_BASE>. <LineStart> and <InputLineStart> are where the tokenizer starts, and
;; the labels ending in Rule where each rule starts. The tokenizer finds the page as <Table>'s high byte halved
;; (<Tokenizer::StartRule>), so the table starts an even page.
;; See: <SecondPage>, <RuleStarts>, <Tokenizer::StartRule>
;; Also: SYNTABL (IBSM)
Table:
    .assert <Table = 0 && (>Table & 1) = 0, "The syntax table starts an even page."
    .byte FIRST_PAGE_TOKEN_BASE

;; Where <RULE_NUMBER_THEN_ARRAY> starts.
;; Also: RULE01 (UNKN)
NumberThenArrayRule:
    CallRuleThenOptional RULE_NUMBER
    CallRuleEndingRule RULE_DIGIT
    .byte ITEM_LETTER | ITEM_LAST
    KeywordEndingAlternative "AT"           ; token $8B, a reserved word
    KeywordEndingAlternative "MOD"          ; token $8A, a reserved word
    KeywordEndingAlternative "OR"           ; token $89, a reserved word
    KeywordEndingAlternative "AND"          ; token $88, a reserved word
    KeywordEndingAlternative "STEP"         ; token $87, a reserved word
    KeywordEndingAlternative "TO"           ; token $86, a reserved word

;; Where <RULE_NAME_CHARACTER> starts: the first character of the keyword below, its highest byte.
;; Also: RULE1D (UNKN)
NameCharacterRule = * + .strlen("THEN") - 1
    KeywordEndingAlternative "THEN"         ; token $85, a reserved word
    CallRuleEndingRule RULE_NAME_REST

;; Where <RULE_NAME> starts.
;; Also: RULE19 (UNKN)
NameRule:
    .byte ITEM_LETTER
    .byte ITEM_SYNTAX_ERROR
    CallRuleEndingRule RULE_NUMBER
    CallRuleEndingAlternative RULE_NUMBER
    Keyword "-"                             ; token $83
    CallRuleEndingAlternative RULE_NUMBER

;; Where <RULE_SIGNED_NUMBER> starts.
;; Also: RULE13 (UNKN)
SignedNumberRule:
    Keyword "+"                             ; token $82
    .byte ITEM_REPEAT

;; Where <RULE_NAME_REST> starts.
;; Also: RULE1C (UNKN)
NameRestRule:
    CallRule RULE_NAME_CHARACTER
    CallRuleThenOptional RULE_NUMBER        ; only read as the item before NAME_REST's: its first item is optional
    .byte ITEM_REPEAT_TWO
    Keyword ","                             ; token $81

;; Where <RULE_INPUT_NUMBERS> starts.
;; Also: RULE12 (UNKN)
InputNumbersRule:
    CallRuleThenOptional RULE_SIGNED_NUMBER
    .byte ITEM_SYNTAX_ERROR
    .byte ITEM_SYNTAX_ERROR
    CallRuleEndingAlternative RULE_NUMBER
    .byte ITEM_LINE_MATCHED
    Keyword "_"                             ; token $80

;; Where the tokenizer starts on a line INPUT reads (<Statements::InputNumber>): the numbers, then
;; the underline that ends the line (token $80) and <ITEM_LINE_MATCHED>.
;; Also: SYNINPUT (UNKN)
InputLineStart:
    CallRule RULE_INPUT_NUMBERS
    CallRuleEndingRule RULE_EXPRESSION
    Keyword "IN#"                           ; token $7F
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword "PR#"                           ; token $7E
    KeywordEndingAlternative "TRACE"        ; token $7D
    CallRuleEndingAlternative RULE_NAME
    Keyword "DSP"                           ; token $7C
    CallRuleEndingAlternative RULE_STRING_VARIABLE
    Keyword "DSP"                           ; token $7B
    KeywordEndingAlternative "NOTRACE"      ; token $7A
    CallRuleEndingAlternative RULE_NAME
    Keyword "NODSP"                         ; token $79
    CallRuleEndingAlternative RULE_STRING_VARIABLE
    Keyword "NODSP"                         ; token $78
    KeywordEndingAlternative "POP"          ; token $77
    KeywordEndingAlternative "LIST"         ; token $76
    CallRuleEndingAlternative RULE_NUMBER
    Keyword ","                             ; token $75
    CallRuleThenOptional RULE_NUMBER

;; Where <RULE_STATEMENTS_LIST_TO_IN> starts: the first character of the keyword below, its highest byte.
;; Also: RULE1B (UNKN)
StatementsListToInRule = * + .strlen("LIST") - 1
    Keyword "LIST"                          ; token $74
    .byte ITEM_SYNTAX_ERROR
    CallRuleEndingRule RULE_NUMBER
    Keyword ")"                             ; token $73

;; Where <RULE_RIGHT_PARENTHESIS> starts.
;; Also: RULE11 (UNKN)
RightParenthesisRule:
    KeywordEndingAlternative ")"            ; token $72
    CallRuleEndingRule RULE_EXPRESSION
    Keyword "="                             ; token $71
    CallRule RULE_NUMBER_VARIABLE
    CallRuleEndingAlternative RULE_STRING
    Keyword "="                             ; token $70

;; Where <RULE_ASSIGNMENT> starts.
;; Also: RULE18 (UNKN)
AssignmentRule:
    CallRule RULE_STRING_DESTINATION
    CallRuleEndingRule RULE_ASSIGNMENT
    CallRuleEndingAlternative RULE_STATEMENTS_LIST_TO_IN
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword "VTAB"                          ; token $6F
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword "AT"                            ; token $6E
    CallRule RULE_EXPRESSION
    Keyword ","                             ; token $6D
    CallRule RULE_EXPRESSION
    Keyword "VLIN"                          ; token $6C
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword "AT"                            ; token $6B
    CallRule RULE_EXPRESSION
    Keyword ","                             ; token $6A
    CallRule RULE_EXPRESSION
    Keyword "HLIN"                          ; token $69
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword ","                             ; token $68
    CallRule RULE_EXPRESSION
    Keyword "PLOT"                          ; token $67
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword "COLOR="                        ; token $66
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword ","                             ; token $65
    CallRule RULE_EXPRESSION
    Keyword "POKE"                          ; token $64
    KeywordEndingAlternative "PRINT"        ; token $63
    .byte ITEM_REPEAT
    CallRule RULE_PRINT_NEXT
    CallRuleThenOptional RULE_EXPRESSION
    Keyword "PRINT"                         ; token $62
    .byte ITEM_REPEAT
    CallRule RULE_PRINT_NEXT
    CallRuleThenOptional RULE_STRING
    Keyword "PRINT"                         ; token $61
    CallRuleEndingAlternative RULE_THEN
    CallRule RULE_EXPRESSION
    Keyword "IF"                            ; token $60
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword "GOTO"                          ; token $5F
    CallRuleEndingAlternative RULE_ASSIGNMENT
    Keyword "LET"                           ; token $5E
    CallRuleEndingAlternative RULE_STATEMENTS_TEXT_TO_TAB
    .byte ITEM_REPEAT
    .byte ITEM_REMARK_CHARACTER

;; Where <RULE_IMMEDIATE_STATEMENT> starts: the first character of the keyword below, its highest byte.
;; Also: RULE1A (UNKN)
ImmediateStatementRule = * + .strlen("REM") - 1
    Keyword "REM"                           ; token $5D
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword "GOSUB"                         ; token $5C
    KeywordEndingAlternative "RETURN"       ; token $5B
    .byte ITEM_REPEAT_TWO
    Keyword ","                             ; token $5A
    CallRuleThenOptional RULE_NAME
    Keyword "NEXT"                          ; token $59
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword "STEP"                          ; token $58
    CallRuleThenOptional RULE_EXPRESSION
    Keyword "TO"                            ; token $57
    CallRule RULE_EXPRESSION
    Keyword "="                             ; token $56
    CallRule RULE_NAME
    Keyword "FOR"                           ; token $55
    .byte ITEM_REPEAT
    CallRule RULE_INPUT_NEXT
    CallRuleThenOptional RULE_NUMBER_VARIABLE
    Keyword "INPUT"                         ; token $54
    .byte ITEM_REPEAT
    CallRule RULE_INPUT_NEXT
    CallRuleThenOptional RULE_STRING
    Keyword "INPUT"                         ; token $53
    .byte ITEM_REPEAT
    CallRule RULE_INPUT_NEXT
    CallRuleThenOptional RULE_STRING_DESTINATION
    Keyword "INPUT"                         ; token $52

;; Where <RULE_STATEMENT> starts: the first character of the keyword below, its highest byte.
;; Also: RULE02 (UNKN)
StatementRule = * + .strlen("END") - 1
    KeywordEndingAlternative "END"          ; token $51

;; The syntax table's second page: rules for expressions, strings, PRINT, DIM and the commands, and the operators.
;;
;; Its first byte is <SECOND_PAGE_TOKEN_BASE>. The top of the page is where the tokenizer starts on a typed line
;; (<LineStart>): the rule for a line, then the underline that ends it (token $01), then <ITEM_LINE_MATCHED>; a line
;; with nothing on it matches the underline below them instead (token $02).
;; See: <Table>, <LineStart>
;; Also: SYNTABL2 (IBSM)
SecondPage:
    .byte SECOND_PAGE_TOKEN_BASE
    CallRuleEndingRule RULE_EXPRESSION
    Keyword "TAB"                           ; token $50
    .byte ITEM_REPEAT
    CallRule RULE_DIM_NEXT
    CallRuleThenOptional RULE_DIM_ARRAY
    Keyword "DIM"                           ; token $4F
    .byte ITEM_REPEAT
    CallRule RULE_DIM_NEXT
    CallRuleThenOptional RULE_DIM_STRING
    Keyword "DIM"                           ; token $4E
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword "CALL"                          ; token $4D
    KeywordEndingAlternative "GR"           ; token $4C

;; Where <RULE_STATEMENTS_TEXT_TO_TAB> starts: the first character of the keyword below, its highest byte.
;; Also: RULE0B (UNKN)
StatementsTextToTabRule = * + .strlen("TEXT") - 1
    KeywordEndingAlternative "TEXT"         ; token $4B
    .byte ITEM_SYNTAX_ERROR
    CallRuleEndingRule RULE_DIM_NEXT
    KeywordEndingAlternative ","            ; token $4A
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword ","                             ; token $49
    CallRuleEndingAlternative RULE_STRING
    Keyword ","                             ; token $48
    KeywordEndingAlternative ";"            ; token $47
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword ";"                             ; token $46
    CallRuleEndingAlternative RULE_STRING

;; Where <RULE_PRINT_NEXT> starts.
;; Also: RULE0E (UNKN)
PrintNextRule:
    Keyword ";"                             ; token $45
    CallRuleEndingRule RULE_DIM_ARRAY
    Keyword ","                             ; token $44
    CallRuleEndingAlternative RULE_DIM_STRING

;; Where <RULE_DIM_NEXT> starts.
;; Also: RULE0D (UNKN)
DimNextRule:
    Keyword ","                             ; token $43
    .byte ITEM_REPEAT

;; Where <RULE_STRING_CHARACTERS> starts.
;; Also: RULE0C (UNKN)
StringCharactersRule:
    .byte ITEM_STRING_CHARACTER
    CallRuleEndingRule RULE_RIGHT_PARENTHESIS
    CallRule RULE_EXPRESSION
    Keyword "("                             ; token $42

;; Where <RULE_STRING_DESTINATION> starts.
;; Also: RULE0A (UNKN)
StringDestinationRule:
    CallRuleThenOptional RULE_STRING_VARIABLE
    Keyword "$"                             ; token $41
    .byte ITEM_LETTER
    KeywordEndingAlternative "$"            ; token $40

;; Where <RULE_STRING_VARIABLE> starts.
;; Also: RULE09 (UNKN)
StringVariableRule:
    CallRule RULE_NAME
    CallRuleEndingRule RULE_NUMBER_VARIABLE
    CallRuleEndingAlternative RULE_RIGHT_PARENTHESIS
    CallRule RULE_EXPRESSION
    Keyword "("                             ; token $3F
    CallRule RULE_FUNCTION_NAME
    CallRuleEndingAlternative RULE_RIGHT_PARENTHESIS
    CallRule RULE_EXPRESSION
    Keyword ","                             ; token $3E
    CallRule RULE_EXPRESSION
    Keyword "SCRN("                         ; token $3D
    CallRuleEndingAlternative RULE_RIGHT_PARENTHESIS
    CallRule RULE_STRING
    Keyword "ASC("                          ; token $3C
    CallRuleEndingAlternative RULE_RIGHT_PARENTHESIS
    CallRule RULE_STRING
    Keyword "LEN("                          ; token $3B
    CallRuleEndingAlternative RULE_STRING
    Keyword "#"                             ; token $3A
    CallRule RULE_STRING
    CallRuleEndingAlternative RULE_STRING
    Keyword "="                             ; token $39
    CallRule RULE_STRING
    CallRuleEndingAlternative RULE_RIGHT_PARENTHESIS
    CallRule RULE_EXPRESSION
    Keyword "("                             ; token $38

;; Where <RULE_UNSIGNED_OPERAND> starts.
;; Also: RULE16 (UNKN)
UnsignedOperandRule:
    CallRuleEndingAlternative RULE_NUMBER
    CallRuleEndingAlternative RULE_OPERAND
    Keyword "NOT"                           ; token $37
    CallRuleEndingAlternative RULE_OPERAND
    Keyword "-"                             ; token $36
    CallRuleEndingAlternative RULE_OPERAND

;; Where <RULE_OPERAND> starts.
;; Also: RULE15 (UNKN)
OperandRule:
    Keyword "+"                             ; token $35
    CallRuleEndingRule RULE_RIGHT_PARENTHESIS
    CallRule RULE_EXPRESSION
    Keyword "("                             ; token $34

;; Where <RULE_DIM_ARRAY> starts.
;; Also: RULE10 (UNKN)
DimArrayRule:
    CallRule RULE_NAME
    Keyword "RNDX"                          ; token $33
    KeywordEndingAlternative "PDL"          ; token $32
    KeywordEndingAlternative "ABS"          ; token $31
    KeywordEndingAlternative "SGN"          ; token $30
    KeywordEndingAlternative "RND"          ; token $2F

;; Where <RULE_FUNCTION_NAME> starts: the first character of the keyword below, its highest byte.
;; Also: RULE14 (UNKN)
FunctionNameRule = * + .strlen("PEEK") - 1
    KeywordEndingAlternative "PEEK"         ; token $2E
    CallRuleEndingRule RULE_RIGHT_PARENTHESIS
    CallRule RULE_EXPRESSION
    Keyword "("                             ; token $2D

;; Where <RULE_NUMBER_VARIABLE> starts.
;; Also: RULE17 (UNKN)
NumberVariableRule:
    CallRuleThenOptional RULE_NAME
    .byte ITEM_DIGIT

;; Where <RULE_DIGIT> starts.
;; Also: RULE0F (UNKN)
DigitRule:
    .byte ITEM_DIGIT | ITEM_LAST
    CallRuleEndingRule RULE_DIGIT
    .byte ITEM_REPEAT
    CallRule RULE_DIGIT

;; Where <RULE_NUMBER> starts.
;; Also: RULE00 (UNKN)
NumberRule:
    CallRuleThenOptional RULE_DIGIT
    .byte ITEM_SYNTAX_ERROR
    CallRuleEndingRule RULE_RIGHT_PARENTHESIS
    CallRule RULE_SUBSTRING
    Keyword "("                             ; token $2A
    CallRuleThenOptional RULE_STRING_VARIABLE
    .byte ('"' - Syntax::CHARACTER_OFFSET) | Syntax::ITEM_CHARACTER | Syntax::ITEM_LAST; ", closing, token $29
    CallRule RULE_STRING_CHARACTERS

;; Where <RULE_STRING> starts.
;; Also: RULE08 (UNKN)
StringRule:
    .byte ('"' - CHARACTER_OFFSET) | ITEM_CHARACTER         ; ", opening, token $28
    CallRuleEndingRule RULE_NUMBER_VARIABLE
    Keyword ","                             ; token $27
    CallRuleEndingAlternative RULE_STRING_DESTINATION

;; Where <RULE_INPUT_NEXT> starts.
;; Also: RULE05 (UNKN)
InputNextRule:
    Keyword ","                             ; token $26
    CallRuleEndingRule RULE_STATEMENT
    Keyword "THEN"                          ; token $25
    CallRuleEndingAlternative RULE_NUMBER

;; Where <RULE_THEN> starts: the first character of the keyword below, its highest byte.
;; Also: RULE04 (UNKN)
ThenRule = * + .strlen("THEN") - 1
    Keyword "THEN"                          ; token $24
    CallRuleEndingRule RULE_DIGIT
    .byte ITEM_REPEAT_TWO
    CallRule RULE_OPERATOR

;; Where <RULE_EXPRESSION> starts.
;; Also: RULE07 (UNKN)
ExpressionRule:
    CallRuleThenOptional RULE_OPERAND
    Keyword ","                             ; token $23

;; Where <RULE_SUBSTRING> starts.
;; Also: RULE06 (UNKN)
SubstringRule:
    CallRuleThenOptional RULE_EXPRESSION
    CallRuleEndingRule RULE_RIGHT_PARENTHESIS
    CallRule RULE_EXPRESSION
    Keyword "("                             ; token $22

;; Where <RULE_DIM_STRING> starts.
;; Also: RULE03 (UNKN)
DimStringRule:
    CallRule RULE_STRING_VARIABLE
    Keyword "+"                             ; token $21
    KeywordEndingAlternative "^"            ; token $20
    KeywordEndingAlternative "MOD"          ; token $1F
    KeywordEndingAlternative "OR"           ; token $1E
    KeywordEndingAlternative "AND"          ; token $1D
    KeywordEndingAlternative "<"            ; token $1C
    KeywordEndingAlternative "<>"           ; token $1B
    KeywordEndingAlternative "<="           ; token $1A
    KeywordEndingAlternative ">"            ; token $19
    KeywordEndingAlternative ">="           ; token $18
    KeywordEndingAlternative "#"            ; token $17
    KeywordEndingAlternative "="            ; token $16
    KeywordEndingAlternative "/"            ; token $15
    KeywordEndingAlternative "*"            ; token $14
    KeywordEndingAlternative "-"            ; token $13

;; Where <RULE_OPERATOR> starts.
;; Also: RULE1E (UNKN)
OperatorRule:
    KeywordEndingAlternative "+"            ; token $12
    .byte ITEM_SYNTAX_ERROR
    CallRuleEndingRule RULE_EXPRESSION
    Keyword "LOMEM:"                        ; token $11
    CallRuleEndingAlternative RULE_EXPRESSION
    Keyword "HIMEM:"                        ; token $10
    KeywordEndingAlternative "MAN"          ; token $0F
    CallRuleEndingAlternative RULE_NUMBER
    Keyword ","                             ; token $0E
    CallRuleThenOptional RULE_NUMBER
    Keyword "AUTO"                          ; token $0D
    KeywordEndingAlternative "CLR"          ; token $0C
    KeywordEndingAlternative "NEW"          ; token $0B
    CallRuleEndingAlternative RULE_NUMBER
    Keyword ","                             ; token $0A
    CallRuleThenOptional RULE_NUMBER
    Keyword "DEL"                           ; token $09
    KeywordEndingAlternative "RUN"          ; token $08
    CallRuleEndingAlternative RULE_NUMBER
    Keyword "RUN"                           ; token $07
    KeywordEndingAlternative "CON"          ; token $06
    KeywordEndingAlternative "SAVE"         ; token $05
    KeywordEndingAlternative "LOAD"         ; token $04
    CallRuleEndingAlternative RULE_IMMEDIATE_STATEMENT
    .byte ITEM_REPEAT_TWO
    Keyword ":"                             ; token $03
    CallRuleThenOptional RULE_STATEMENT

;; Where <RULE_LINE> starts.
;; Also: RULE1F (UNKN)
LineRule:
    CallRuleThenOptional RULE_NUMBER
    .byte ITEM_SYNTAX_ERROR
    CallRuleEndingAlternative RULE_NUMBER
    .byte ITEM_LINE_MATCHED
    Keyword "_"                             ; token $02
    CallRuleEndingAlternative RULE_NUMBER
    .byte ITEM_LINE_MATCHED
    Keyword "_"                             ; token $01

;; Where the tokenizer starts on a typed line (<WarmStart::ReadCommand>): a call of <RULE_LINE>, the top of the table.
;; Also: SYNLINE (UNKN)
LineStart:
    CallRule RULE_LINE
    .assert * = Table + $200, "The syntax table fills two pages."

.endscope
