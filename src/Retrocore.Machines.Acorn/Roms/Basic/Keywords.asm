;; The paged ROM header, the language entry and start-up, the keyword table and the token routine tables
;; ($8000-$8450).
;;
;; - The header the MOS reads at &8000: the language entry, which starts BASIC, the ROM's type, title and copyright,
;;   and the address the ROM runs at when it is copied across the Tube.
;; - <BASIC_START>, which sets BASIC up once when the MOS selects it as the language.
;; - <KEYWORD_TABLE>: every keyword's text, its token and how the tokeniser treats what follows it. The tokeniser,
;;   <TOKENISE_LINE>, searches it to turn keywords into tokens, and <PRINT_CHARACTER_OR_TOKEN> to turn tokens back
;;   into keywords.
;; - <TOKEN_ROUTINES_LOW> and <TOKEN_ROUTINES_HIGH>: the address of the routine each token from &8E up runs, as a
;;   function or as a statement.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

LANGUAGE_START_UP = $01             ;; the code in A when the MOS enters a language to start it up
OSBYTE_READ_OSHWM = $83             ;; OSBYTE &83: reads OSHWM, the lowest address a language may use, into X and Y
OSBYTE_READ_HIMEM = $84             ;; OSBYTE &84: reads the bottom of screen memory, the highest a language may use

; The bits of a paged ROM's type byte that BASIC sets.
ROM_TYPE_LANGUAGE = %01000000       ;; the ROM has a language entry
ROM_TYPE_RELOCATION = %00100000     ;; the header gives the address the language runs at across the Tube

; The bits of a keyword's flags in <KEYWORD_TABLE>, which tell <TOKENISE_LINE> how to treat the text after it. The
; tokeniser keeps two states: whether it is at the start of a statement, where PTR, PAGE, TIME, LOMEM and HIMEM are
; statements, or in the middle of one; and whether numbers it meets are line numbers, which it packs after a
; <TOKEN_LINE_NUMBER>.
KEYWORD_CONDITIONAL = %00000001     ;; not a keyword when a letter, digit, _ or £ follows it, as in COUNTER or ENDING
KEYWORD_MID_STATEMENT = %00000010   ;; the tokeniser is in the middle of a statement after it; numbers are not lines
KEYWORD_START_STATEMENT = %00000100 ;; a new statement starts after it; numbers are not lines (unless bit 4 is set)
KEYWORD_SKIP_NAME = %00001000       ;; the name after it (of a PROC or FN) is copied without looking for keywords
KEYWORD_LINE_NUMBERS = %00010000    ;; numbers after it are line numbers, as after GOTO, THEN and LIST
KEYWORD_REST_OF_LINE = %00100000    ;; the rest of the line after it is text, not tokenised, as after REM and DATA
KEYWORD_PSEUDO_VARIABLE = %01000000 ;; at the start of a statement its token is &40 higher, the statement's token

;; Lays out an entry of <KEYWORD_TABLE>: the keyword's text, its token and its flags.
;;
;; The token ends the text, because its bit 7 is set and no character of a keyword has it.
;; Parameters:
;;   text = the keyword, in capitals, with the $ or ( that is part of it
;;   token = its token, a TOKEN_ constant
;;   flags = how the tokeniser treats what follows it: KEYWORD_ bits, or 0
.macro KEYWORD text, token, flags
    .byte text, token, flags
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; The paged ROM header
; ---------------------------------------------------------------------------------------------------------------------

;; The language entry: starts BASIC when the MOS selects it as the current language.
;;
;; The MOS enters a language here with a JMP and a code in A; <LANGUAGE_START_UP>, the only code a BBC Micro sends,
;; starts BASIC at <BASIC_START>, and any other code returns. The paged ROM header gives a service entry at &8003,
;; but BASIC has none: its type byte's bit 7 is clear, so the MOS never calls it, and &8003 is the middle of the BEQ.
;; In: A = the reason for the call
;; See: <BASIC_START>, <LANGUAGE_ENTRY>
BASIC_ENTRY:
    cmp #LANGUAGE_START_UP
    beq BASIC_START                 ; &8003, the service entry's place, is this instruction's offset
    rts
    .byte $EA                       ; padding, a NOP, up to the type byte
    .assert BASIC_ENTRY = LANGUAGE_ENTRY, "The language entry is at &8000."

;; The ROM type, &60: a language with a Tube relocation address, and no service entry.
;;
;; Bit 7 is clear because BASIC has no service entry; the MOS takes a ROM without one to be BASIC.
;; See: <ROM_TYPE>
BASIC_ROM_TYPE:
    .byte ROM_TYPE_LANGUAGE | ROM_TYPE_RELOCATION
    .assert BASIC_ROM_TYPE = ROM_TYPE, "The ROM type is at &8006."

;; The offset from &8000 of <BASIC_COPYRIGHT>, the zero before "(C)" that the MOS checks to recognise a paged ROM.
;; See: <COPYRIGHT_OFFSET>
BASIC_COPYRIGHT_OFFSET:
    .byte BASIC_COPYRIGHT - BASIC_ENTRY
    .assert BASIC_COPYRIGHT_OFFSET = COPYRIGHT_OFFSET, "The copyright offset is at &8007."

;; The binary version number: 1 for BASIC II (BASIC I has 0). The MOS ignores it.
BASIC_VERSION:
    .byte 1

;; The ROM's title, "BASIC", which the MOS prints when it selects the language; the zero at the start of
;; <BASIC_COPYRIGHT> ends it.
;; See: <ROM_TITLE>
BASIC_TITLE:
    .byte "BASIC"
    .assert BASIC_TITLE = ROM_TITLE, "The title is at &8009."

;; The copyright string: a zero, "(C)1982 Acorn", a line feed and a carriage return, and a zero to end it.
;;
;; The MOS finds it from <BASIC_COPYRIGHT_OFFSET> and checks its zero and "(C)" to recognise the ROM.
BASIC_COPYRIGHT:
    .byte 0, "(C)1982 Acorn", $0A, $0D, 0

;; The second processor relocation address, four bytes after the copyright string's zero: &00008000.
;;
;; <ROM_TYPE_RELOCATION> says it is there. When a second processor is fitted, the MOS copies the language across the
;; Tube to this address; BASIC runs at &8000 there too, so it needs no relocating.
BASIC_RELOCATION_ADDRESS:
    .dword LANGUAGE_ENTRY

; ---------------------------------------------------------------------------------------------------------------------
; Start-up
; ---------------------------------------------------------------------------------------------------------------------

;; Sets BASIC up when the MOS starts it as the language, then starts it with no program, as NEW.
;;
;; It runs once each time BASIC is entered, after any BREAK as well as at power on: HIMEM is set to the bottom of
;; screen memory and PAGE to OSHWM, LISTO to 0, WIDTH to &FF (no wrapping) and @% to &0000090A, PRINT's general
;; format with nine digits in a field of ten. RND's seed survives a BREAK; only if it is all zero, which would never
;; change, is it seeded with the letters "ARW". BRKV is pointed at <BRK_HANDLER>, so that errors come to BASIC.
;; Out: HIMEM, PAGE_HIGH, LISTO, WIDTH, AT_PERCENT..AT_PERCENT+3, RANDOM, BRKV
;; See: <COLD_START>
BASIC_START:
    lda #OSBYTE_READ_HIMEM
    jsr OSBYTE
    stx HIMEM
    sty HIMEM+1
    lda #OSBYTE_READ_OSHWM
    jsr OSBYTE
    sty PAGE_HIGH                   ; OSHWM's low byte is zero
    ldx #$00
    stx LISTO
    stx AT_PERCENT+2                ; @%'s format: 0, general
    stx AT_PERCENT+3                ; @%'s top byte, which STR$ also reads
    dex
    stx WIDTH
    ldx #10
    stx AT_PERCENT                  ; @%'s field width
    dex
    stx AT_PERCENT+1                ; @%'s number of digits
    lda #$01                        ; the seed's top bit, bit 0 of RANDOM+4
    and RANDOM+4
    ora RANDOM
    ora RANDOM+1
    ora RANDOM+2
    ora RANDOM+3
    bne BASIC_START_SEEDED
    lda #'A'
    sta RANDOM
    lda #'R'
    sta RANDOM+1
    lda #'W'
    sta RANDOM+2
BASIC_START_SEEDED:
    lda #<BRK_HANDLER
    sta BRKV
    lda #>BRK_HANDLER
    sta BRKV+1
    cli
    jmp COLD_START

; ---------------------------------------------------------------------------------------------------------------------
; The keywords
; ---------------------------------------------------------------------------------------------------------------------

;; The keyword table: each keyword's text, its token and the flags that tell the tokeniser how to treat what follows.
;;
;; Each entry is a <KEYWORD>. The text ends at the token, which has bit 7 set, and the flags follow it.
;;
;; <TOKENISE_LINE> compares the text with each entry in turn, giving up when the entries' first letter passes the
;; text's or after WIDTH's entry, so the order matters:
;; - A keyword matches when its whole text does, so a longer keyword comes before one it starts with: ENDPROC before
;;   END, GET$ before GET, INKEY$ before INKEY.
;; - An abbreviation, some letters and a full stop, matches the first keyword in the table that starts with them, so
;;   the most used comes first: P. is PRINT, not PAGE.
;; - The five entries after WIDTH, the tokens PTR, PAGE, TIME, LOMEM and HIMEM have at the start of a statement, are
;;   never searched: the tokeniser makes those tokens from the functions' with <KEYWORD_PSEUDO_VARIABLE>. They are
;;   there for <PRINT_CHARACTER_OR_TOKEN>, which lists a token by searching the whole table for it.
;;
;; The tokens &8D (a line number) and &CE (unused) have no entry.
;; See: <TOKENISE_LINE>, <PRINT_CHARACTER_OR_TOKEN>
KEYWORD_TABLE:
    KEYWORD "AND", TOKEN_AND, 0
    KEYWORD "ABS", TOKEN_ABS, 0
    KEYWORD "ACS", TOKEN_ACS, 0
    KEYWORD "ADVAL", TOKEN_ADVAL, 0
    KEYWORD "ASC", TOKEN_ASC, 0
    KEYWORD "ASN", TOKEN_ASN, 0
    KEYWORD "ATN", TOKEN_ATN, 0
    KEYWORD "AUTO", TOKEN_AUTO, KEYWORD_LINE_NUMBERS
    KEYWORD "BGET", TOKEN_BGET, KEYWORD_CONDITIONAL
    KEYWORD "BPUT", TOKEN_BPUT, KEYWORD_CONDITIONAL | KEYWORD_MID_STATEMENT
    KEYWORD "COLOUR", TOKEN_COLOUR, KEYWORD_MID_STATEMENT
    KEYWORD "CALL", TOKEN_CALL, KEYWORD_MID_STATEMENT
    KEYWORD "CHAIN", TOKEN_CHAIN, KEYWORD_MID_STATEMENT
    KEYWORD "CHR$", TOKEN_CHR_STR, 0
    KEYWORD "CLEAR", TOKEN_CLEAR, KEYWORD_CONDITIONAL
    KEYWORD "CLOSE", TOKEN_CLOSE, KEYWORD_CONDITIONAL | KEYWORD_MID_STATEMENT
    KEYWORD "CLG", TOKEN_CLG, KEYWORD_CONDITIONAL
    KEYWORD "CLS", TOKEN_CLS, KEYWORD_CONDITIONAL
    KEYWORD "COS", TOKEN_COS, 0
    KEYWORD "COUNT", TOKEN_COUNT, KEYWORD_CONDITIONAL
    KEYWORD "DATA", TOKEN_DATA, KEYWORD_REST_OF_LINE
    KEYWORD "DEG", TOKEN_DEG, 0
    KEYWORD "DEF", TOKEN_DEF, 0
    KEYWORD "DELETE", TOKEN_DELETE, KEYWORD_LINE_NUMBERS
    KEYWORD "DIV", TOKEN_DIV, 0
    KEYWORD "DIM", TOKEN_DIM, KEYWORD_MID_STATEMENT
    KEYWORD "DRAW", TOKEN_DRAW, KEYWORD_MID_STATEMENT
    KEYWORD "ENDPROC", TOKEN_ENDPROC, KEYWORD_CONDITIONAL
    KEYWORD "END", TOKEN_END, KEYWORD_CONDITIONAL
    KEYWORD "ENVELOPE", TOKEN_ENVELOPE, KEYWORD_MID_STATEMENT
    KEYWORD "ELSE", TOKEN_ELSE, KEYWORD_START_STATEMENT | KEYWORD_LINE_NUMBERS
    KEYWORD "EVAL", TOKEN_EVAL, 0
    KEYWORD "ERL", TOKEN_ERL, KEYWORD_CONDITIONAL
    KEYWORD "ERROR", TOKEN_ERROR, KEYWORD_START_STATEMENT
    KEYWORD "EOF", TOKEN_EOF, KEYWORD_CONDITIONAL
    KEYWORD "EOR", TOKEN_EOR, 0
    KEYWORD "ERR", TOKEN_ERR, KEYWORD_CONDITIONAL
    KEYWORD "EXP", TOKEN_EXP, 0
    KEYWORD "EXT", TOKEN_EXT, KEYWORD_CONDITIONAL
    KEYWORD "FOR", TOKEN_FOR, KEYWORD_MID_STATEMENT
    KEYWORD "FALSE", TOKEN_FALSE, KEYWORD_CONDITIONAL
    KEYWORD "FN", TOKEN_FN, KEYWORD_SKIP_NAME
    KEYWORD "GOTO", TOKEN_GOTO, KEYWORD_MID_STATEMENT | KEYWORD_LINE_NUMBERS
    KEYWORD "GET$", TOKEN_GET_STR, 0
    KEYWORD "GET", TOKEN_GET, 0
    KEYWORD "GOSUB", TOKEN_GOSUB, KEYWORD_MID_STATEMENT | KEYWORD_LINE_NUMBERS
    KEYWORD "GCOL", TOKEN_GCOL, KEYWORD_MID_STATEMENT
    KEYWORD "HIMEM", TOKEN_HIMEM, KEYWORD_CONDITIONAL | KEYWORD_MID_STATEMENT | KEYWORD_PSEUDO_VARIABLE
    KEYWORD "INPUT", TOKEN_INPUT, KEYWORD_MID_STATEMENT
    KEYWORD "IF", TOKEN_IF, KEYWORD_MID_STATEMENT
    KEYWORD "INKEY$", TOKEN_INKEY_STR, 0
    KEYWORD "INKEY", TOKEN_INKEY, 0
    KEYWORD "INT", TOKEN_INT, 0
    KEYWORD "INSTR(", TOKEN_INSTR, 0
    KEYWORD "LIST", TOKEN_LIST, KEYWORD_LINE_NUMBERS
    KEYWORD "LINE", TOKEN_LINE, 0
    KEYWORD "LOAD", TOKEN_LOAD, KEYWORD_MID_STATEMENT
    KEYWORD "LOMEM", TOKEN_LOMEM, KEYWORD_CONDITIONAL | KEYWORD_MID_STATEMENT | KEYWORD_PSEUDO_VARIABLE
    KEYWORD "LOCAL", TOKEN_LOCAL, KEYWORD_MID_STATEMENT
    KEYWORD "LEFT$(", TOKEN_LEFT_STR, 0
    KEYWORD "LEN", TOKEN_LEN, 0
    KEYWORD "LET", TOKEN_LET, KEYWORD_START_STATEMENT
    KEYWORD "LOG", TOKEN_LOG, 0
    KEYWORD "LN", TOKEN_LN, 0
    KEYWORD "MID$(", TOKEN_MID_STR, 0
    KEYWORD "MODE", TOKEN_MODE, KEYWORD_MID_STATEMENT
    KEYWORD "MOD", TOKEN_MOD, 0
    KEYWORD "MOVE", TOKEN_MOVE, KEYWORD_MID_STATEMENT
    KEYWORD "NEXT", TOKEN_NEXT, KEYWORD_MID_STATEMENT
    KEYWORD "NEW", TOKEN_NEW, KEYWORD_CONDITIONAL
    KEYWORD "NOT", TOKEN_NOT, 0
    KEYWORD "OLD", TOKEN_OLD, KEYWORD_CONDITIONAL
    KEYWORD "ON", TOKEN_ON, KEYWORD_MID_STATEMENT
    KEYWORD "OFF", TOKEN_OFF, 0
    KEYWORD "OR", TOKEN_OR, 0
    KEYWORD "OPENIN", TOKEN_OPENIN, 0
    KEYWORD "OPENOUT", TOKEN_OPENOUT, 0
    KEYWORD "OPENUP", TOKEN_OPENUP, 0
    KEYWORD "OSCLI", TOKEN_OSCLI, KEYWORD_MID_STATEMENT
    KEYWORD "PRINT", TOKEN_PRINT, KEYWORD_MID_STATEMENT
    KEYWORD "PAGE", TOKEN_PAGE, KEYWORD_CONDITIONAL | KEYWORD_MID_STATEMENT | KEYWORD_PSEUDO_VARIABLE
    KEYWORD "PTR", TOKEN_PTR, KEYWORD_CONDITIONAL | KEYWORD_MID_STATEMENT | KEYWORD_PSEUDO_VARIABLE
    KEYWORD "PI", TOKEN_PI, KEYWORD_CONDITIONAL
    KEYWORD "PLOT", TOKEN_PLOT, KEYWORD_MID_STATEMENT
    KEYWORD "POINT(", TOKEN_POINT, 0
    KEYWORD "PROC", TOKEN_PROC, KEYWORD_MID_STATEMENT | KEYWORD_SKIP_NAME
    KEYWORD "POS", TOKEN_POS, KEYWORD_CONDITIONAL
    KEYWORD "RETURN", TOKEN_RETURN, KEYWORD_CONDITIONAL
    KEYWORD "REPEAT", TOKEN_REPEAT, 0
    KEYWORD "REPORT", TOKEN_REPORT, KEYWORD_CONDITIONAL
    KEYWORD "READ", TOKEN_READ, KEYWORD_MID_STATEMENT
    KEYWORD "REM", TOKEN_REM, KEYWORD_REST_OF_LINE
    KEYWORD "RUN", TOKEN_RUN, KEYWORD_CONDITIONAL
    KEYWORD "RAD", TOKEN_RAD, 0
    KEYWORD "RESTORE", TOKEN_RESTORE, KEYWORD_MID_STATEMENT | KEYWORD_LINE_NUMBERS
    KEYWORD "RIGHT$(", TOKEN_RIGHT_STR, 0
    KEYWORD "RND", TOKEN_RND, KEYWORD_CONDITIONAL
    KEYWORD "RENUMBER", TOKEN_RENUMBER, KEYWORD_LINE_NUMBERS
    KEYWORD "STEP", TOKEN_STEP, 0
    KEYWORD "SAVE", TOKEN_SAVE, KEYWORD_MID_STATEMENT
    KEYWORD "SGN", TOKEN_SGN, 0
    KEYWORD "SIN", TOKEN_SIN, 0
    KEYWORD "SQR", TOKEN_SQR, 0
    KEYWORD "SPC", TOKEN_SPC, 0
    KEYWORD "STR$", TOKEN_STR_STR, 0
    KEYWORD "STRING$(", TOKEN_STRING_STR, 0
    KEYWORD "SOUND", TOKEN_SOUND, KEYWORD_MID_STATEMENT
    KEYWORD "STOP", TOKEN_STOP, KEYWORD_CONDITIONAL
    KEYWORD "TAN", TOKEN_TAN, 0
    KEYWORD "THEN", TOKEN_THEN, KEYWORD_START_STATEMENT | KEYWORD_LINE_NUMBERS
    KEYWORD "TO", TOKEN_TO, 0
    KEYWORD "TAB(", TOKEN_TAB, 0
    KEYWORD "TRACE", TOKEN_TRACE, KEYWORD_MID_STATEMENT | KEYWORD_LINE_NUMBERS
    KEYWORD "TIME", TOKEN_TIME, KEYWORD_CONDITIONAL | KEYWORD_MID_STATEMENT | KEYWORD_PSEUDO_VARIABLE
    KEYWORD "TRUE", TOKEN_TRUE, KEYWORD_CONDITIONAL
    KEYWORD "UNTIL", TOKEN_UNTIL, KEYWORD_MID_STATEMENT
    KEYWORD "USR", TOKEN_USR, 0
    KEYWORD "VDU", TOKEN_VDU, KEYWORD_MID_STATEMENT
    KEYWORD "VAL", TOKEN_VAL, 0
    KEYWORD "VPOS", TOKEN_VPOS, KEYWORD_CONDITIONAL
    KEYWORD "WIDTH", TOKEN_WIDTH, KEYWORD_MID_STATEMENT
    KEYWORD "PAGE", TOKEN_PAGE_STATEMENT, 0
    KEYWORD "PTR", TOKEN_PTR_STATEMENT, 0
    KEYWORD "TIME", TOKEN_TIME_STATEMENT, 0
    KEYWORD "LOMEM", TOKEN_LOMEM_STATEMENT, 0
    KEYWORD "HIMEM", TOKEN_HIMEM_STATEMENT, 0

; ---------------------------------------------------------------------------------------------------------------------
; The routines the tokens run
; ---------------------------------------------------------------------------------------------------------------------

;; The low bytes of the routines the tokens &8E-&FF run, one for each token, from OPENIN's.
;;
;; The functions, &8E-&C5, run from <EVALUATE_FACTOR>, the statements, &CF-&FF, from the statement loop at
;; <EXECUTE_STATEMENT>, and the commands, &C6-&CD, only at the start of a line typed in immediate mode, from
;; <EXECUTE_LINE_RUN>. All three jump through <DISPATCH_TOKEN>, which indexes the tables with the token itself, through
;; <ROUTINE_LOW_BY_TOKEN> and <ROUTINE_HIGH_BY_TOKEN>, the tables' addresses less &8E. A function returns its value in
;; the accumulators, with its type in A; a statement goes back to the loop through <CONTINUE_EXECUTION>.
;;
;; Some tokens share a routine: DATA, DEF and REM run <SKIP_LINE>, since none does anything when it is reached, and
;; &CE, which no keyword has, runs <SYNTAX_ERROR>. TO, which is not a function, runs <TOP_FUNCTION>, which reads TO
;; followed by P as TOP.
;; See: <TOKEN_ROUTINES_HIGH>
TOKEN_ROUTINES_LOW:
    .byte <(OPENIN_FUNCTION)
    .byte <(PTR_FUNCTION)
    .byte <(PAGE_FUNCTION)
    .byte <(TIME_FUNCTION)
    .byte <(LOMEM_FUNCTION)
    .byte <(HIMEM_FUNCTION)
    .byte <(ABS_FUNCTION)
    .byte <(ACS_FUNCTION)
    .byte <(ADVAL_FUNCTION)
    .byte <(ASC_FUNCTION)
    .byte <(ASN_FUNCTION)
    .byte <(ATN_FUNCTION)
    .byte <(BGET_FUNCTION)
    .byte <(COS_FUNCTION)
    .byte <(COUNT_FUNCTION)
    .byte <(DEG_FUNCTION)
    .byte <(ERL_FUNCTION)
    .byte <(ERR_FUNCTION)
    .byte <(EVAL_FUNCTION)
    .byte <(EXP_FUNCTION)
    .byte <(EXT_FUNCTION)
    .byte <(FALSE_FUNCTION)
    .byte <(FN_FUNCTION)
    .byte <(GET_FUNCTION)
    .byte <(INKEY_FUNCTION)
    .byte <(INSTR_FUNCTION)
    .byte <(INT_FUNCTION)
    .byte <(LEN_FUNCTION)
    .byte <(LN_FUNCTION)
    .byte <(LOG_FUNCTION)
    .byte <(NOT_FUNCTION)
    .byte <(OPENUP_FUNCTION)
    .byte <(OPENOUT_FUNCTION)
    .byte <(PI_FUNCTION)
    .byte <(POINT_FUNCTION)
    .byte <(POS_FUNCTION)
    .byte <(RAD_FUNCTION)
    .byte <(RND_FUNCTION)
    .byte <(SGN_FUNCTION)
    .byte <(SIN_FUNCTION)
    .byte <(SQR_FUNCTION)
    .byte <(TAN_FUNCTION)
    .byte <(TOP_FUNCTION)                      ; &B8, TO as a function: TOP, which is TO followed by P
    .byte <(TRUE_FUNCTION)
    .byte <(USR_FUNCTION)
    .byte <(VAL_FUNCTION)
    .byte <(VPOS_FUNCTION)
    .byte <(CHR_STR_FUNCTION)
    .byte <(GET_STR_FUNCTION)
    .byte <(INKEY_STR_FUNCTION)
    .byte <(LEFT_STR_FUNCTION)
    .byte <(MID_STR_FUNCTION)
    .byte <(RIGHT_STR_FUNCTION)
    .byte <(STR_STR_FUNCTION)
    .byte <(STRING_STR_FUNCTION)
    .byte <(EOF_FUNCTION)
    .byte <(AUTO_COMMAND)
    .byte <(DELETE_COMMAND)
    .byte <(LOAD_COMMAND)
    .byte <(LIST_COMMAND)
    .byte <(NEW_COMMAND)
    .byte <(OLD_COMMAND)
    .byte <(RENUMBER_COMMAND)
    .byte <(SAVE_COMMAND)
    .byte <(SYNTAX_ERROR)               ; &CE, no keyword has token &CE
    .byte <(PTR_STATEMENT)
    .byte <(PAGE_STATEMENT)
    .byte <(TIME_STATEMENT)
    .byte <(LOMEM_STATEMENT)
    .byte <(HIMEM_STATEMENT)
    .byte <(SOUND_STATEMENT)
    .byte <(BPUT_STATEMENT)
    .byte <(CALL_STATEMENT)
    .byte <(CHAIN_STATEMENT)
    .byte <(CLEAR_STATEMENT)
    .byte <(CLOSE_STATEMENT)
    .byte <(CLG_STATEMENT)
    .byte <(CLS_STATEMENT)
    .byte <(SKIP_LINE)                  ; &DC, DATA: skipped when run
    .byte <(SKIP_LINE)                  ; &DD, DEF: skipped when run
    .byte <(DIM_STATEMENT)
    .byte <(DRAW_STATEMENT)
    .byte <(END_STATEMENT)
    .byte <(ENDPROC_STATEMENT)
    .byte <(ENVELOPE_STATEMENT)
    .byte <(FOR_STATEMENT)
    .byte <(GOSUB_STATEMENT)
    .byte <(GOTO_STATEMENT)
    .byte <(GCOL_STATEMENT)
    .byte <(IF_STATEMENT)
    .byte <(INPUT_STATEMENT)
    .byte <(LET_STATEMENT)
    .byte <(LOCAL_STATEMENT)
    .byte <(MODE_STATEMENT)
    .byte <(MOVE_STATEMENT)
    .byte <(NEXT_STATEMENT)
    .byte <(ON_STATEMENT)
    .byte <(VDU_STATEMENT)
    .byte <(PLOT_STATEMENT)
    .byte <(PRINT_STATEMENT)
    .byte <(PROC_STATEMENT)
    .byte <(READ_STATEMENT)
    .byte <(SKIP_LINE)                  ; &F4, REM: skipped when run
    .byte <(REPEAT_STATEMENT)
    .byte <(REPORT_STATEMENT)
    .byte <(RESTORE_STATEMENT)
    .byte <(RETURN_STATEMENT)
    .byte <(RUN_STATEMENT)
    .byte <(STOP_STATEMENT)
    .byte <(COLOUR_STATEMENT)
    .byte <(TRACE_STATEMENT)
    .byte <(UNTIL_STATEMENT)
    .byte <(WIDTH_STATEMENT)
    .byte <(OSCLI_STATEMENT)

;; The high bytes of the routines the tokens &8E-&FF run, laid out as <TOKEN_ROUTINES_LOW>.
;; See: <TOKEN_ROUTINES_LOW>
TOKEN_ROUTINES_HIGH:
    .byte >(OPENIN_FUNCTION)
    .byte >(PTR_FUNCTION)
    .byte >(PAGE_FUNCTION)
    .byte >(TIME_FUNCTION)
    .byte >(LOMEM_FUNCTION)
    .byte >(HIMEM_FUNCTION)
    .byte >(ABS_FUNCTION)
    .byte >(ACS_FUNCTION)
    .byte >(ADVAL_FUNCTION)
    .byte >(ASC_FUNCTION)
    .byte >(ASN_FUNCTION)
    .byte >(ATN_FUNCTION)
    .byte >(BGET_FUNCTION)
    .byte >(COS_FUNCTION)
    .byte >(COUNT_FUNCTION)
    .byte >(DEG_FUNCTION)
    .byte >(ERL_FUNCTION)
    .byte >(ERR_FUNCTION)
    .byte >(EVAL_FUNCTION)
    .byte >(EXP_FUNCTION)
    .byte >(EXT_FUNCTION)
    .byte >(FALSE_FUNCTION)
    .byte >(FN_FUNCTION)
    .byte >(GET_FUNCTION)
    .byte >(INKEY_FUNCTION)
    .byte >(INSTR_FUNCTION)
    .byte >(INT_FUNCTION)
    .byte >(LEN_FUNCTION)
    .byte >(LN_FUNCTION)
    .byte >(LOG_FUNCTION)
    .byte >(NOT_FUNCTION)
    .byte >(OPENUP_FUNCTION)
    .byte >(OPENOUT_FUNCTION)
    .byte >(PI_FUNCTION)
    .byte >(POINT_FUNCTION)
    .byte >(POS_FUNCTION)
    .byte >(RAD_FUNCTION)
    .byte >(RND_FUNCTION)
    .byte >(SGN_FUNCTION)
    .byte >(SIN_FUNCTION)
    .byte >(SQR_FUNCTION)
    .byte >(TAN_FUNCTION)
    .byte >(TOP_FUNCTION)                      ; &B8, TO as a function: TOP, which is TO followed by P
    .byte >(TRUE_FUNCTION)
    .byte >(USR_FUNCTION)
    .byte >(VAL_FUNCTION)
    .byte >(VPOS_FUNCTION)
    .byte >(CHR_STR_FUNCTION)
    .byte >(GET_STR_FUNCTION)
    .byte >(INKEY_STR_FUNCTION)
    .byte >(LEFT_STR_FUNCTION)
    .byte >(MID_STR_FUNCTION)
    .byte >(RIGHT_STR_FUNCTION)
    .byte >(STR_STR_FUNCTION)
    .byte >(STRING_STR_FUNCTION)
    .byte >(EOF_FUNCTION)
    .byte >(AUTO_COMMAND)
    .byte >(DELETE_COMMAND)
    .byte >(LOAD_COMMAND)
    .byte >(LIST_COMMAND)
    .byte >(NEW_COMMAND)
    .byte >(OLD_COMMAND)
    .byte >(RENUMBER_COMMAND)
    .byte >(SAVE_COMMAND)
    .byte >(SYNTAX_ERROR)               ; &CE, no keyword has token &CE
    .byte >(PTR_STATEMENT)
    .byte >(PAGE_STATEMENT)
    .byte >(TIME_STATEMENT)
    .byte >(LOMEM_STATEMENT)
    .byte >(HIMEM_STATEMENT)
    .byte >(SOUND_STATEMENT)
    .byte >(BPUT_STATEMENT)
    .byte >(CALL_STATEMENT)
    .byte >(CHAIN_STATEMENT)
    .byte >(CLEAR_STATEMENT)
    .byte >(CLOSE_STATEMENT)
    .byte >(CLG_STATEMENT)
    .byte >(CLS_STATEMENT)
    .byte >(SKIP_LINE)                  ; &DC, DATA: skipped when run
    .byte >(SKIP_LINE)                  ; &DD, DEF: skipped when run
    .byte >(DIM_STATEMENT)
    .byte >(DRAW_STATEMENT)
    .byte >(END_STATEMENT)
    .byte >(ENDPROC_STATEMENT)
    .byte >(ENVELOPE_STATEMENT)
    .byte >(FOR_STATEMENT)
    .byte >(GOSUB_STATEMENT)
    .byte >(GOTO_STATEMENT)
    .byte >(GCOL_STATEMENT)
    .byte >(IF_STATEMENT)
    .byte >(INPUT_STATEMENT)
    .byte >(LET_STATEMENT)
    .byte >(LOCAL_STATEMENT)
    .byte >(MODE_STATEMENT)
    .byte >(MOVE_STATEMENT)
    .byte >(NEXT_STATEMENT)
    .byte >(ON_STATEMENT)
    .byte >(VDU_STATEMENT)
    .byte >(PLOT_STATEMENT)
    .byte >(PRINT_STATEMENT)
    .byte >(PROC_STATEMENT)
    .byte >(READ_STATEMENT)
    .byte >(SKIP_LINE)                  ; &F4, REM: skipped when run
    .byte >(REPEAT_STATEMENT)
    .byte >(REPORT_STATEMENT)
    .byte >(RESTORE_STATEMENT)
    .byte >(RETURN_STATEMENT)
    .byte >(RUN_STATEMENT)
    .byte >(STOP_STATEMENT)
    .byte >(COLOUR_STATEMENT)
    .byte >(TRACE_STATEMENT)
    .byte >(UNTIL_STATEMENT)
    .byte >(WIDTH_STATEMENT)
    .byte >(OSCLI_STATEMENT)
    .assert TOKEN_ROUTINES_HIGH - TOKEN_ROUTINES_LOW = $100 - TOKEN_OPENIN, "Each token from &8E has a low byte."
    .assert * - TOKEN_ROUTINES_HIGH = $100 - TOKEN_OPENIN, "Each token from &8E has a high byte."

ROUTINE_LOW_BY_TOKEN = TOKEN_ROUTINES_LOW - TOKEN_OPENIN    ;; <TOKEN_ROUTINES_LOW>, indexed by the token itself
ROUTINE_HIGH_BY_TOKEN = TOKEN_ROUTINES_HIGH - TOKEN_OPENIN  ;; <TOKEN_ROUTINES_HIGH>, indexed by the token itself
