; retrocore: style=strict
;; Programmer's Aid #1: Renumber and Append ($D400-$D4D4)
;;
;; Steve Wozniak's renumbering of Integer BASIC programs (1978), and Append, which loads a program from tape in front
;; of the one in memory. Both are mostly SWEET16 (Sweet16.mac), with 6502 code where they print or call BASIC.
;;
;; Renumber works in two passes over the program, which lies from <PP> up to <HIMEM>. The first gives each line in the
;; range its new number, keeping the old numbers in a table between the variables (<PV>) and the program, and prints
;; each change as `old->new`; MEM FULL if the table does not fit. The second rewrites every line number in the program,
;; and every number after GOTO, GOSUB, THEN and LIST, that is in the table; DEL's numbers are left as they are. A line
;; whose new number would not keep the program in order stops it with RANGE ERR before anything changes.
;;
;; BASIC calls the entries in RenumberCalls.asm, which read the new numbering from BASIC's variables `START` and `STEP`,
;; and the range from `FROM` and `TO`, and enter <Renumber::RenumberRange>. <Renumber::RenumberAll> is the listing's own
;; entry for every line.
;;
;; The listing's names are those of Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1). Its equates also name three values the code never uses, left out
;; here: ONE ($01), SCR8 (R8, as scratch) and DEL (R13, for DEL's token, which the code never checks). Its ACC (R0)
;; and MODE (R12) are given in prose, as here they would clash with the Monitor's names, and so is DONE, Music's name
;; too. Part of ProgrammersAid.asm.

.scope Renumber

; The SWEET16 registers. Several names share a register; each pass gives it its own use.

;; R0, the accumulator. Apple's listing calls it ACC.
ACCUMULATOR = $0

;; R1: the first new line number (`START`).
;; Also: NEWLOW (PA1)
FIRST_NUMBER = $1

;; R2: the step between new numbers (`STEP`).
;; Also: NEWINCR (PA1)
STEP = $2

;; R3: the lowest line renumbered (`FROM`).
;; Also: LNLOW (PA1)
LOWEST_LINE = $3

;; R4: the highest line renumbered (`TO`).
;; Also: LNHI (PA1)
HIGHEST_LINE = $4

;; R5: the start of the line number table.
;; Also: TBLSTRT (PA1)
TABLE_START = $5

;; R6: pass 1's index into the table, where the next old number goes.
;; Also: TBLNDX1 (PA1)
PASS1_TABLE_INDEX = $6

;; R6: pass 2's end of the table, where pass 1 left its index.
;; Also: TBLND (PA1)
TABLE_END = $6

;; R7: the end of the room for the table, <PP>.
;; Also: TBLIM (PA1)
TABLE_LIMIT = $7

;; R7: pass 2's index into the program.
;; Also: PRGNDX2 (PA1)
PASS2_PROGRAM_INDEX = $7

;; R8: <HIMEM>, the end of the program.
;; Also: HMEM (PA1)
PROGRAM_END = $8

;; R9: a pointer into page zero, to read BASIC's pointers.
;; Also: SCR9 (PA1)
POINTER = $9

;; R9: pass 1's index into the program: the next line.
;; Also: PRGNDX (PA1)
PASS1_PROGRAM_INDEX = $9

;; R9: the character "0", the first of a number's.
;; Also: CHR0 (PA1)
DIGIT_ZERO = $9

;; R10: pass 1's line being read.
;; Also: PRGNDX1 (PA1)
PASS1_LINE = $A

;; R10: the code before "A", $C0, which a number's first character, a digit, is below and a name's letters are not.
;; Apple's listing calls it ASCII "A".
;; Also: CHRA (PA1)
LETTER_A = $A

;; R11: the next new line number.
;; Also: NEWLN (PA1)
NEXT_NUMBER = $B

;; R11: pass 2's index into the table.
;; Also: TBLNDX2 (PA1)
PASS2_TABLE_INDEX = $B

;; R11: the string constant token, <TOKEN_STRING>.
;; Also: STRCON (PA1)
STRING_TOKEN = $B

;; R12: the last new line number given.
;; Also: NEWLN1 (PA1)
LAST_NUMBER = $C

;; R12: 0 after a token whose number is a line number, which the number's DCR makes -1. Apple's listing calls it MODE.
LINE_NUMBER_MODE = $C

;; R12: the REM token, <TOKEN_REM>.
;; Also: REM (PA1)
REM_TOKEN = $C

;; R12: <Append>'s pointer into page zero, at <HIMEM>.
;; Also: SCRC (PA1)
APPEND_POINTER = $C

;; R13, which a compare leaves its result in.
;; Also: R13 (PA1)
COMPARE_RESULT = $D

;; R13: the old line number being looked up in the table.
;; Also: OLDLN (PA1)
LOOKUP_NUMBER = $D

;; R13: the THEN token, <TOKEN_THEN>.
;; Also: THEN (PA1)
THEN_TOKEN = $D

;; R13: the LIST token, <TOKEN_LIST>.
;; Also: LIST (PA1)
LIST_TOKEN = $D

; Integer BASIC's tokens and characters, as the program holds them.

;; The token that opens a string constant.
TOKEN_STRING = $28

;; REM's token, whose text runs to the end of the line.
TOKEN_REM = $5D

;; THEN's token before a line number.
TOKEN_THEN = $24

;; LIST's token; the comma after its first number, $75, follows it.
TOKEN_LIST = $74

;; GOSUB's token.
TOKEN_GOSUB = $5C

;; GOTO's token.
TOKEN_GOTO = $5F

; The 6502's view of the registers it prints.

;; R0's bytes, which hold the old line number when pass 1 prints it.
;; Also: R0L (PA1)
OldNumber = Sweet16Registers + ACCUMULATOR * SWEET16_REGISTER_SIZE

;; The high byte of <OldNumber>.
;; Also: R0H (PA1)
OldNumberHigh = OldNumber + 1

;; R11's bytes, the new line number pass 1 prints.
;; Also: R11L (PA1)
NewNumber = Sweet16Registers + NEXT_NUMBER * SWEET16_REGISTER_SIZE

;; The high byte of <NewNumber>.
;; Also: R11H (PA1)
NewNumberHigh = NewNumber + 1

;; Renumbers every line: sets the range to lines 0 to 65535, then falls into <RenumberRange>.
;; In: FIRST_NUMBER = the first new number, STEP = the step, in SWEET16's registers
;; Also: RENX (PA1)
.proc RenumberAll
.assert * = $D400, "Renumber::RenumberAll must stay at $D400."
    jsr SW16
    SUB ACCUMULATOR
    ST LOWEST_LINE
    ST HIGHEST_LINE
    DCR HIGHEST_LINE
    RTN
    ; Falls into RenumberRange.
.endproc

;; Renumbers the program's lines from <LOWEST_LINE> to <HIGHEST_LINE>, starting at <FIRST_NUMBER> and stepping by
;; <STEP>, printing each change; RANGE ERR if the new numbers would put the lines out of order, MEM FULL if the table
;; does not fit.
;;
;; The table of old numbers, a word per line renumbered, grows up from <PV>, the end of the variables, toward <PP>.
;; In: FIRST_NUMBER = the first new number, STEP = the step, LOWEST_LINE = the lowest line renumbered,
;;   HIGHEST_LINE = the highest, all in SWEET16's registers
;; Also: RENUM (PA1)
.proc RenumberRange
.assert * = $D408, "Renumber::RenumberRange must stay at $D408."
    jsr SW16
    SET PROGRAM_END, HIMEM
    LDD [PROGRAM_END]
    ST PROGRAM_END

;; Finds the room for the table: from <PV> up to <PP>.
;; Also: RNUM3 (PA1)
FindTable:
    SET POINTER, PV + 2
    ; The table starts at PV.
    POPD [POINTER]
    ST TABLE_START
    ST PASS1_TABLE_INDEX
    LD FIRST_NUMBER
    ST NEXT_NUMBER
    ST LAST_NUMBER
    ; And can grow up to PP, where the program starts.
    POPD [POINTER]
    ST TABLE_LIMIT
    ST PASS1_PROGRAM_INDEX

;; Pass 1: each line in the range gets the next new number, and its old number goes in the table.
;; Also: PASS1 (PA1)
Pass1:
    LD PASS1_PROGRAM_INDEX
    CPR PROGRAM_END
    ; Past the last line.
    BC Pass2
    ST PASS1_LINE
    LD PASS1_TABLE_INDEX
    INR ACCUMULATOR
    CPR TABLE_LIMIT
    ; No room for two more bytes.
    BC MemoryFull
    ; The line's length, to the next line.
    LD [PASS1_LINE]
    ADD PASS1_PROGRAM_INDEX
    ST PASS1_PROGRAM_INDEX
    ; Its number.
    LDD [PASS1_LINE]
    CPR LOWEST_LINE
    ; Below the range.
    BNC BelowRange
    CPR HIGHEST_LINE
    BNC InRange
    ; Above the range.
    BNZ AboveRange

;; Puts the old number in the table, and prints `old->new`.
;; Also: P1A (PA1)
InRange:
    STD [PASS1_TABLE_INDEX]
    RTN
    lda OldNumberHigh
    ldx OldNumber
    jsr PRDEC
    lda #'-'
    jsr CharacterOut
    lda #'>'
    jsr CharacterOut
    lda NewNumberHigh
    ldx NewNumber
    jsr PRDEC
    jsr PrintReturn

    ; Back to SWEET16, past SW16's save of the 6502's registers, so the ones it saved for the caller stay.
    jsr SW16 + 3
    LD NEXT_NUMBER
    ST LAST_NUMBER
    ADD STEP
    ST NEXT_NUMBER
    ; Skips the compare below, so BNC tests the add: a new number past 65535 is RANGE ERR.
    NUL

;; A line below the range: its number must be below the first new number, which the lines in the range start at.
;; Also: P1B (PA1)
BelowRange:
    CPR FIRST_NUMBER
    BNC Pass1

;; Also: RERR (PA1)
RangeError:
    RTN
    jmp RANGERR

;; Also: MERR (PA1)
MemoryFull:
    RTN
    jmp MEMFULL

;; A line above the range: its number must be above the last new number given. Pass 1 ends here, as the lines after
;; it are above the range too.
;; Also: P1C (PA1)
AboveRange:
    INR LAST_NUMBER
    CPR LAST_NUMBER
    BNC RangeError

;; Pass 2: every line number in the program, and every number after a token that takes one, that is in the table
;; becomes its new number.
;; Also: PASS2 (PA1)
Pass2:
    SET DIGIT_ZERO, '0'
    SET LETTER_A, 'A' - 1

;; Takes the next line: updates its number, then its tokens.
;; Also: P2A (PA1)
NextLine:
    LD PASS2_PROGRAM_INDEX
    CPR PROGRAM_END
    BC Append::Done
    ; Past the length byte, to the line's number.
    INR PASS2_PROGRAM_INDEX
    LDD [PASS2_PROGRAM_INDEX]

;; Looks the number in R0 up in the table, and writes its new number over it when it is there.
;; Also: UPDATE (PA1)
Update:
    ST LOOKUP_NUMBER
    LD TABLE_START
    ST PASS2_TABLE_INDEX
    LD FIRST_NUMBER
    ; Skips the next two instructions, so the first new number is the first number's.
    SetSkippingTwo LAST_NUMBER

;; Also: UD2 (PA1)
NextTableEntry:
    LD LAST_NUMBER
    ADD STEP
    ST LAST_NUMBER
    LD PASS2_TABLE_INDEX
    SUB TABLE_END
    ; Not in the table.
    BC AfterNumber
    LDD [PASS2_TABLE_INDEX]
    SUB LOOKUP_NUMBER
    BNZ NextTableEntry
    POPD [PASS2_PROGRAM_INDEX]
    LD LAST_NUMBER
    STD [PASS2_PROGRAM_INDEX]

;; Also: UD3 (PA1)
AfterNumber:
    SET STRING_TOKEN, TOKEN_STRING
    ; Skips the next two instructions.
    SetSkippingTwo LINE_NUMBER_MODE

;; A number constant: its value, a line number to update when the token before it takes one.
;; Also: GOTCON (PA1)
GotNumber:
    LDD [PASS2_PROGRAM_INDEX]
    DCR LINE_NUMBER_MODE
    BM1 Update

;; Takes the next token.
;; Also: ITEM (PA1)
NextToken:
    LD [PASS2_PROGRAM_INDEX]
    CPR DIGIT_ZERO
    BNC CheckToken
    CPR LETTER_A
    ; A number.
    BNC GotNumber

;; Skips a name, a string or a remark: the bytes with bit 7 set.
;; Also: SKPASC (PA1)
SkipText:
    DCR PASS2_PROGRAM_INDEX
    LDD [PASS2_PROGRAM_INDEX]
    BM SkipText
    DCR PASS2_PROGRAM_INDEX
    LD [PASS2_PROGRAM_INDEX]

;; Checks a token: a string or a remark is skipped, and GOSUB, GOTO, THEN and LIST make the number after them a line
;; number.
;; Also: CHKTOK (PA1)
CheckToken:
    CPR STRING_TOKEN
    BZ SkipText
    SET REM_TOKEN, TOKEN_REM
    CPR REM_TOKEN
    BZ SkipText
    ; GOSUB: the compare with REM's token left -1.
    .assert TOKEN_GOSUB = TOKEN_REM - 1, "GOSUB's token must be one below REM's."
    BM1 LineNumberNext
    ; GOTO: two above GOSUB.
    .assert TOKEN_GOTO = TOKEN_GOSUB + 3, "GOTO's token must be three above GOSUB's."
    DCR COMPARE_RESULT
    DCR COMPARE_RESULT
    BZ LineNumberNext
    SET THEN_TOKEN, TOKEN_THEN
    CPR THEN_TOKEN
    BZ LineNumberNext
    ; The end of the line, token $01.
    DCR ACCUMULATOR
    BZ NextLine
    SET LIST_TOKEN, TOKEN_LIST
    SUB LIST_TOKEN
    ; R0 is now -1 for LIST, $74, and 0 for LIST's comma, $75, which SetMode takes as it is.
    BNM1 SetMode

;; The number after this token is a line number: <LINE_NUMBER_MODE> becomes 0, which the number's DCR makes -1.
;; Also: CONTST (PA1)
LineNumberNext:
    SUB ACCUMULATOR

;; Also: CONTS2 (PA1)
SetMode:
    ST LINE_NUMBER_MODE
    BR NextToken
.endproc

;; APPEND (CALL -11076): loads a program from tape in front of the one in memory, whose lines must all be numbered
;; higher.
;;
;; It sets <HIMEM> to <PP>, so Integer BASIC's <LOAD> puts the program from tape below the one in memory, then puts
;; <HIMEM> back, so both show. After MEM FULL, CALL -11059 (<Renumber::Append::Restore>) brings the program in memory
;; back.
;; Entry:
;;   Restore = puts back the <HIMEM> Append kept, after a tape load or after MEM FULL
;;   Done = returns from SWEET16 and to the caller; <RenumberRange> ends here too
;; Also: APPEND (PA1)
.proc Append
.assert * = $D4BC, "Renumber::Append must stay at $D4BC, CALL -11076."
    jsr SW16
    SET APPEND_POINTER, HIMEM + 2
    ; Keeps HIMEM.
    POPD [APPEND_POINTER]
    ST PROGRAM_END
    SET POINTER, PP
    LDD [POINTER]
    ; HIMEM = PP, which keeps the program in memory.
    STD [APPEND_POINTER]
    RTN
    jsr LOAD

;; After a tape load, or CALL -11059 after MEM FULL: puts back the <HIMEM> <Append> kept, so both programs show.
Restore:
.assert * = $D4CD, "Renumber::Append::Restore must stay at $D4CD, CALL -11059."
    jsr SW16
    POPD [APPEND_POINTER]
    LD PROGRAM_END
    STD [APPEND_POINTER]

;; Apple's listing calls it DONE.
Done:
    RTN
    rts
.endproc

.endscope
