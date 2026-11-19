;; MBASIC 5.21: STATEMENTS: FOR, NEWSTT, CHRGTR AND THE CONTROL STATEMENTS
;;
;; The heart of the interpreter's statement loop and the statements that steer it, in the order of GW-BASIC's
;; GWMAIN.ASM from FOR to IF (MBASIC's BINTRP). In order:
;;
;; - ST_FOR builds a FOR entry on the stack, then scans ahead to the matching NEXT (NXTSCN) and runs it at once
;;   (NEXTS), so a loop whose start is already past its limit never runs its body. NXTCON is where NEXT comes back
;;   to put the FOR token on again and fall into NEWSTT.
;; - NEWSTT runs the program a statement at a time: it calls the console status routine (NEWSTT_1, patched by
;;   Init.asm) to check for Control-C and Control-S, saves SAVTXT and SAVSTK, moves to the next line at a line's end
;;   (tracing its number in brackets under TRON), and falls into GONE, which pushes NEWSTT as every statement's
;;   return address and dispatches the statement's token through STMDSP (Tables.asm). Other characters start an
;;   implied LET; tokens past the statements go to MID$ assignment (Evaluator.asm).
;; - CHRGTR fetches the next character of the program text, skipping blanks and expanding the constants CRUNCH
;;   embeds in a line: CONSAV, CONTYP, CONLO and CONTXT (CONSAV, CONTYP, CONLO, CONTXT) hold the last one, and
;;   CONFC1 moves it into the floating accumulator.
;; - DEFSTR, DEFINT, DEFSNG and DEFDBL fill DEFTBL through DEFCON. INTIDX and INTID2 read a non-negative integer,
;;   and FCERR is the Illegal function call error.
;; - LINSPC, LINGET and LINGT2 read a line number, taking the embedded line-number and line-pointer constants.
;; - RUN, GOSUB, GOTO (GOTO2 finds the line and changes its number in the text into a pointer), RETURN, DATA and
;;   REM (which skip to the end of the statement or line), LET (with LETCN2 and INPCOM, which INPUT and READ share),
;;   ON ERROR GOTO and ON ... GOTO/GOSUB, RESUME, ERROR, AUTO, and IF with its ELSE search (FALSIF).
;;
;; Runs at $11BF-$1693. The main entry points are NEWSTT, GONE, CHRGTR, LINGET and the ST_ handlers in STMDSP.

;; Runs FOR: assigns the start value, drops a loop left by this same FOR, pushes a FOR entry and runs its NEXT.
;;
;; The start value is converted to the loop variable's type and kept in FVALSV. An entry already on the
;; stack for the same variable is dropped, with everything above it, only when it was made by this same FOR
;; statement (its end-of-statement pointer equals ENDFOR). The new entry holds, from the top: the FOR token, the
;; loop variable's address, the text pointer at the NEXT, the loop type (B, negative for integer) and step sign
;; (C), the step, the limit, the FOR's line number and the text pointer after the FOR statement. Integer loops
;; keep two-byte step and limit values; strings and double precision give a TM error. FOR then scans ahead to
;; the matching NEXT (an FN error if there is none) and jumps to NEXTS, which tests the loop before its first
;; pass.
;;
;; In:    HL = the text, at the loop variable
;; Errors: SN, TM, FN, OM
ST_FOR:
    LD A,$64                        ; 100: subscripted variables are not allowed
    LD [SUBFLG],A
    CALL PTRGET                     ; DE = the loop variable's address
    CALL SYNCHR                     ; an equals sign must follow
    .byte TK_EQUAL                  ; the = token
    PUSH DE                         ; keep the variable's address
    EX DE,HL
    LD [TEMP],HL                    ; and in TEMP, for later
    EX DE,HL
    LD A,[VALTYP]                   ; the loop variable's type
    PUSH AF
    CALL FRMEVL                     ; the start value
    POP AF                          ; A = the loop variable's type
    PUSH HL
    CALL DOCNVF                     ; convert the start value to the loop's type
    LD HL,FVALSV                    ; FVALSV, where NEXT finds the start value
    CALL MOVMF                      ; store the FAC there
    POP HL                          ; HL = the text pointer
    POP DE                          ; DE = the loop variable's address
    POP BC                          ; drop the return to NEWSTT
    PUSH HL
    CALL ST_DATA                    ; HL = the end of the FOR statement
    LD [ENDFOR],HL                  ; to recognize an entry from this same FOR
    LD HL,$0002                     ; HL = the stack above the text pointer
    ADD HL,SP

;; Looks for a FOR entry on the loop variable DE made by this same FOR, and drops it with everything above it.
LPFORM:
    CALL LOOPER                     ; the next FOR entry on the variable in DE
    JP NZ,NOTOL                     ; none: nothing to drop
    ADD HL,BC                       ; HL = past the matching entry
    PUSH DE                         ; keep the variable's address
    DEC HL
    LD D,[HL]                       ; DE = the entry's end-of-FOR text pointer, its last word
    DEC HL
    LD E,[HL]
    INC HL
    INC HL
    PUSH HL
    LD HL,[ENDFOR]
    CALL DCOMPR                     ; COMPAR: made by this FOR statement?
    POP HL
    POP DE
    JP NZ,LPFORM                    ; another FOR on the variable: keep looking
    POP DE                          ; DE = the text pointer
    LD SP,HL                        ; drop the old entry and everything above it
    LD [SAVSTK],HL
    .byte $0E                       ; LD C,n: skips the POP DE

;; Builds the new FOR entry on the stack, from the line number down to the step, and runs the loop's NEXT.
NOTOL:
    POP DE                          ; DE = the text pointer
    EX DE,HL
    LD C,$08                        ; room for 16 bytes
    CALL GETSTK
    PUSH HL
    LD HL,[ENDFOR]
    EX [SP],HL                      ; stack the end of the FOR statement
    PUSH HL
    LD HL,[CURLIN]
    EX [SP],HL                      ; stack the FOR's line number
    CALL SYNCHR                     ; TO must follow
    .byte TK_TO                     ; the TO token
    CALL GETYPR                     ; the loop variable's type
    JP Z,TMERR                      ; strings cannot be loop variables
    JP NC,TMERR                     ; nor can double precision
    PUSH AF                         ; keep the integer (negative) or single flag
    CALL FRMEVL                     ; the limit
    POP AF
    PUSH HL
    JP P,SNGFOR                     ; positive: a single-precision loop
    CALL FN_CINT                    ; FRCINT: HL = the integer limit
    EX [SP],HL                      ; stack the limit, HL = the text
    LD DE,$0001                     ; the default STEP of 1
    LD A,[HL]
    CP TK_STEP                      ; the STEP token
    CALL Z,GETINT                   ; DE = the step
    PUSH DE                         ; stack the step
    PUSH HL
    EX DE,HL
    CALL ISIGN                      ; A = the sign of the step
    JP STPSGN

;; Stacks the single-precision limit and step of a FOR, and the step's sign.
SNGFOR:
    CALL FN_CSNG                    ; FRCSNG
    CALL MOVRF                      ; BCDE = the limit
    POP HL                          ; HL = the text
    PUSH BC                         ; stack the limit
    PUSH DE
    LD BC,$8100                     ; BCDE = 1.0, the default step
    LD D,C
    LD E,D
    LD A,[HL]
    CP TK_STEP                      ; the STEP token
    LD A,$01                        ; the sign of the default step
    JP NZ,ONEON
    CALL FRMCHK                     ; the step
    PUSH HL
    CALL FN_CSNG                    ; FRCSNG
    CALL MOVRF                      ; BCDE = the step
    CALL SIGN                       ; A = the sign of the step

;; Finishes the FOR entry: the step, the type and sign word, the NEXT's text pointer, the variable and the token.
STPSGN:
    POP HL                          ; HL = the text
ONEON:
    PUSH BC                         ; stack the step (a dummy word too for integers)
    PUSH DE
    LD C,A                          ; C = the sign of the step
    CALL GETYPR                     ; negative for an integer loop
    LD B,A
    PUSH BC                         ; stack the type and sign
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR                     ; the FOR statement must end here
    CALL NXTSCN                     ; find the matching NEXT, else an FN error
    CALL CHRGTR                     ; the first character after NEXT
    PUSH HL                         ; stack the NEXT's text pointer
    PUSH HL
    LD HL,[NXTLIN]                  ; the NEXT's line becomes the current one
    LD [CURLIN],HL
    LD HL,[TEMP]
    EX [SP],HL                      ; stack the loop variable's address
    LD B,TK_FOR                     ; the FOR token tags the entry
    PUSH BC
    INC SP                          ; only the token byte stays pushed
    PUSH AF                         ; the character after NEXT
    PUSH AF                         ; stands in for the return to NEWSTT
    JP NEXTS                        ; test the loop before its first pass

;; Pushes the FOR token back onto the entry NEXT keeps, and goes on to the next statement.
NXTCON:
    LD B,TK_FOR                     ; the FOR token
    PUSH BC
    INC SP                          ; only the token byte stays pushed

;; Runs the next statement: checks the console, moves to the next line at a line's end and traces it under TRON.
;;
;; Every statement returns here. The console status routine, which Init.asm puts in NEWSTT_1, says whether a key is
;; waiting; if one is, the console routine at CNTCCN reads it, pausing on Control-S and stopping on Control-C.
;; At the end of the program (a zero link) it ends through PRGEND.
;;
;; In:    HL = the text, at the colon or zero that ended the last statement
;; Errors: SN
;; Entry: GONE4 = starts the line whose link HL points to, for an ON ERROR GOTO handler (ERRMOR)
NEWSTT:
    PUSH HL
    CALL $0000                      ; the console status, patched by Init: A = nonzero for a key
NEWSTT_1 = * - 2                    ;; the console status routine NEWSTT calls, set by Init.asm
    POP HL
    OR A
    CALL NZ,CNTCCN                  ; a key: Control-S pauses, Control-C stops
    LD [SAVTXT],HL                  ; where CONT and errors find the statement
    EX DE,HL
    LD HL,$0000
    ADD HL,SP
    LD [SAVSTK],HL                  ; the stack to recover after an error
    EX DE,HL
    LD A,[HL]
    CP $3A                          ; a colon: another statement on this line
    JP Z,GONE
    OR A
    JP NZ,SNERR                     ; anything but the end of the line is a syntax error
    INC HL                          ; HL = the next line's link
GONE4:
    LD A,[HL]
    INC HL
    OR [HL]
    JP Z,PRGEND                     ; a zero link: the program has run out
    INC HL
    LD E,[HL]                       ; DE = the new line's number
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [CURLIN],HL                  ; the line being executed
    LD A,[TRCFLG]                   ; is TRON on?
    OR A
    JP Z,NOTTRC
    PUSH DE                         ; keep the text pointer
    LD A,$5B                        ; the line number is shown in brackets
    CALL OUTDO
    CALL LINPRT
    LD A,$5D
    CALL OUTDO
    POP DE

;; Restores the text pointer after the trace and executes the statement.
NOTTRC:
    EX DE,HL

;; Gets the first character of a statement and executes it, returning to NEWSTT afterwards.
;;
;; In:    HL = the text, just before the statement
GONE:
    CALL CHRGTR                     ; A = the statement's first character
    LD DE,NEWSTT                    ; NEWSTT is every statement's return address
    PUSH DE
    RET Z                           ; an empty statement does nothing

;; Dispatches the statement token in A through STMDSP; other characters start an implied LET.
;;
;; The handler is entered through CHRGTR's RET, with the character after the token in A and its flags. Tokens
;; past the statements go to ISMID, for a MID$ assignment.
;;
;; In:    A = the statement's first character, HL = the text at it
GONE2:
    SUB TK_END                      ; the first statement token, END
    JP C,LET                        ; not a keyword: an assignment without LET
    CP TK_RESET-TK_END+1            ; past the last statement token
    JP NC,ISMID                     ; maybe a MID$ assignment
    RLCA                            ; two bytes per entry of STMDSP
    LD C,A
    LD B,$00
    EX DE,HL
    LD HL,STMDSP
    ADD HL,BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC                         ; the handler becomes the return address
    EX DE,HL                        ; HL = the text, then fetch the next character

;; Fetches the next character of the program text, skipping blanks and reading embedded constants.
;;
;; An embedded constant comes back as its token, with HL at NUMCON, a stand-in text whose next fetch returns to
;; the text after the constant (CONTXT); the constant itself is in CONLO, and CONFC1 moves it into the FAC.
;;
;; In:    HL = the text, just before the character
;; Out:   HL = the text at the character, A = the character, carry = set for a digit,
;;        zero = set for the end of a statement (a colon or zero)
;; Entry: CHRGT2 = fetches the character at HL
CHRGTR:
    INC HL
CHRGT2:
    LD A,[HL]
    CP $3A
    RET NC                          ; not a digit or below: a colon gives zero

;; Finishes CHRGTR for characters below the colon: skips blanks, reads constants, flags digits and the end.
CHRCON:
    CP $20
    JP Z,CHRGTR                     ; spaces are skipped
    JP NC,NOTLFT                    ; a printable character: is it a digit?
    OR A
    RET Z                           ; the end of the line
    CP OCTCON                       ; OCTCON: below it, tabs and line feeds
    JP C,NOTCON
    CP CONCON                       ; CONCON: rescanning a constant already read
    JP NZ,NTRSCC
    LD A,[CONSAV]                   ; the constant's token again
    OR A                            ; neither zero nor carry
    RET

;; Reads the embedded constant whose token is in A, or passes over one (CONCN2) already read.
NTRSCC:
    CP CONCN2                       ; CONCN2: go past the constant
    JP Z,CONSCN
    PUSH AF                         ; keep the token to return
    INC HL                          ; HL = the constant's value
    LD [CONSAV],A
    SUB INTCON                      ; INTCON and above: integer, single and double constants
    JP NC,MAKTKN
    SUB (ONECON-INTCON) & $FF       ; the digits 0 to 9, in the token
    JP NC,ONEI
    CP (IN2CON-ONECON) & $FF        ; a one-byte integer
    JP NZ,FRCINC                    ; else a line number or pointer, two bytes
    LD A,[HL]
    INC HL

;; Saves a small integer constant in A as the integer constant in CONLO.
ONEI:
    LD [CONTXT],HL                  ; the text after the constant
    LD H,$00
ONEI2:
    LD L,A
    LD [CONLO],HL
    LD A,$02                        ; an integer
    LD [CONTYP],A
    LD HL,NUMCON                    ; the stand-in text
    POP AF                          ; A = the token
    OR A                            ; neither zero nor carry
    RET

;; Reads a two-byte integer, line number or line pointer constant.
FRCINC:
    LD A,[HL]                       ; the low byte
    INC HL
    INC HL
    LD [CONTXT],HL                  ; past the constant
    DEC HL
    LD H,[HL]                       ; the high byte
    JP ONEI2

;; Moves the constant last read into the FAC and fetches the character after it.
;;
;; Out:   HL = the text at the character after the constant, A = that character
CONFAC:
    CALL CONFC1

;; Continues the fetch at the text after an embedded constant.
CONSCN:
    LD HL,[CONTXT]
    JP CHRGT2

;; Copies an integer, single or double constant into CONLO, setting CONTYP.
MAKTKN:
    INC A                           ; 0, 1 or 3 become the type: 2, 4 or 8
    RLCA
    LD [CONTYP],A
    PUSH DE
    PUSH BC
    LD DE,CONLO
    EX DE,HL
    LD B,A                          ; the value's length
    CALL MOVE1                      ; copy it from the text
    EX DE,HL                        ; HL = the text after the constant
    POP BC
    POP DE
    LD [CONTXT],HL
    POP AF                          ; A = the token
    LD HL,NUMCON                    ; the stand-in text
    OR A                            ; neither zero nor carry
    RET

;; Skips tabs and line feeds, and returns other control characters as they are.
NOTCON:
    CP $09                          ; a tab or line feed is skipped
    JP NC,CHRGTR

;; Sets carry for a digit and zero for a zero byte.
NOTLFT:
    CP $30
    CCF                             ; carry for a digit
    INC A
    DEC A                           ; zero for the zero byte
    RET

;; The stand-in text CHRGTR leaves HL at after an embedded constant: CONCON to see the constant again, then
;; CONCN2 to go past it.
NUMCON:
    .byte $1E, $10

;; Moves the constant last read by CHRGTR into the FAC, a line number or pointer as a single-precision line number.
;;
;; Out:   VALTYP = the constant's type, FACLO = the value in the FAC (DFACLO for a double)
CONFC1:
    LD A,[CONSAV]
    CP LINCON+1                     ; above LINCON: a number
    JP NC,NTLINE
    CP PTRCON                       ; below PTRCON: a number
    JP C,NTLINE
    LD HL,[CONLO]
    JP NZ,FLTLIN                    ; LINCON: HL is the line number
    INC HL                          ; PTRCON: get the number from the line
    INC HL
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
FLTLIN:
    JP INEG2                        ; float the unsigned line number

;; Moves a numeric constant from CONLO into the FAC.
NTLINE:
    LD A,[CONTYP]
    LD [VALTYP],A
    CP $08
    JP Z,CONFDB                     ; double precision
    LD HL,[CONLO]
    LD [FACLO],HL
    LD HL,[CONHI]
    LD [FACHI],HL
    RET

;; Moves a double-precision constant from CONLO into the FAC.
CONFDB:
    LD HL,CONLO
    JP VMOVFM

;; Runs DEFSTR: makes variables starting with the given letters strings by default.
ST_DEFSTR:
    LD E,$03                        ; 3 = string
    .byte $01                       ; LD BC,nn: skips the next instruction

;; Runs DEFINT: makes variables starting with the given letters integers by default.
ST_DEFINT:
    LD E,$02                        ; 2 = integer
    .byte $01                       ; LD BC,nn: skips the next instruction

;; Runs DEFSNG: makes variables starting with the given letters single precision by default.
ST_DEFSNG:
    LD E,$04                        ; 4 = single precision
    .byte $01                       ; LD BC,nn: skips the next instruction

;; Runs DEFDBL: makes variables starting with the given letters double precision by default.
ST_DEFDBL:
    LD E,$08                        ; 8 = double precision

;; Sets the default type of each letter or letter range in the list to the type code in E.
;;
;; In:    E = the type code (2 integer, 3 string, 4 single, 8 double), HL = the text, at the first letter
;; Errors: SN
DEFCON:
    CALL ISLET                      ; carry when not a letter
    LD BC,SNERR                     ; the return for an error
    PUSH BC
    RET C                           ; a letter must start the range
    SUB $41                         ; C = the first letter as an index from A
    LD C,A
    LD B,A                          ; B = the last letter, the same for one letter
    CALL CHRGTR
    CP TK_MINUS                     ; the minus token makes a range
    JP NZ,NOTRNG
    CALL CHRGTR
    CALL ISLET                      ; a letter must end the range
    RET C
    SUB $41                         ; B = the last letter as an index
    LD B,A
    CALL CHRGTR

;; Stores the type code in E for the letters from C to B in DEFTBL.
NOTRNG:
    LD A,B
    SUB C
    RET C                           ; a backward range is a syntax error
    INC A                           ; A = how many letters to set
    EX [SP],HL                      ; drop the error return, keep the text pointer
    LD HL,DEFTBL
    LD B,$00                        ; BC = the first letter's index
    ADD HL,BC

;; Stores E in A entries of DEFTBL, then moves on to the next letter range after a comma.
LPDCHG:
    LD [HL],E
    INC HL
    DEC A
    JP NZ,LPDCHG
    POP HL                          ; HL = the text
    LD A,[HL]
    CP $2C                          ; a comma brings another range
    RET NZ
    CALL CHRGTR
    JP DEFCON

;; Gets the next character and evaluates a non-negative integer into DE, else an FC error.
;;
;; In:    HL = the text, just before the expression
;; Out:   DE = the integer, HL = the text after it
;; Errors: FC, and the expression's errors
INTIDX:
    CALL CHRGTR

;; Evaluates a non-negative integer expression into DE, else an FC error.
;;
;; In:    HL = the text, at the expression
;; Out:   DE = the integer, HL = the text after it
;; Errors: FC, and the expression's errors
INTID2:
    CALL GETIN2                     ; DE = the integer, negative for a negative one
    RET P

;; Reports an FC (Illegal function call) error.
FCERR:
    LD E,ERR_FC                     ; ERRFC
    JP ERROR

;; Reads a line number at HL into DE, accepting a period for the current line (DOT).
;;
;; In:    HL = the text, at the line number
;; Out:   DE = the line number, HL = the text at the character after it, A = that character,
;;        zero = set for the end of the statement
LINSPC:
    LD A,[HL]
    CP $2E                          ; a period means the current line
    EX DE,HL
    LD HL,[DOT]                     ; DE = the line last entered, listed or in error
    EX DE,HL
    JP Z,CHRGTR                     ; skip the period

;; Reads a line number into DE, taking an embedded line number or line pointer constant as it is.
;;
;; A number is read digit by digit up to 65529; a digit that would take it further is left as the terminator,
;; for the caller to give a syntax error. After a constant, CONSAV holds its token, LINCON or PTRCON (DE then
;; being the line's address); after digits it is zero.
;;
;; In:    HL = the text, at the line number
;; Out:   DE = the line number, HL = the text at the character after it, A = that character,
;;        zero = set for the end of the statement
;; Entry: LINGT2 = starts at the character after HL, LINGT3 = takes the embedded line number in CONLO
LINGET:
    DEC HL
LINGT2:
    CALL CHRGTR
    CP LINCON                       ; LINCON: an embedded line number
    JP Z,LINGT3
    CP PTRCON                       ; PTRCON: a line already converted to a pointer
LINGT3:
    EX DE,HL
    LD HL,[CONLO]                   ; the constant's value
    EX DE,HL
    JP Z,CHRGTR                     ; a constant: fetch the character after it
    XOR A
    LD [CONSAV],A                   ; CONSAV = 0: no constant, so GOTO2 leaves the text alone
    DEC HL
    LD DE,$0000                     ; the number so far

;; Adds the next digit to the line number in DE.
MORLIN:
    CALL CHRGTR
    RET NC                          ; not a digit: done
    PUSH HL
    PUSH AF                         ; keep the digit
    LD HL,$1998                     ; 6552: another digit could pass 65529
    CALL DCOMPR                     ; COMPAR
    JP C,POPHSR                     ; too big: leave the digit for a syntax error
    LD H,D
    LD L,E
    ADD HL,DE                       ; HL = the number times 2
    ADD HL,HL                       ; times 4
    ADD HL,DE                       ; times 5
    ADD HL,HL                       ; times 10
    POP AF
    SUB $30                         ; the digit's value
    LD E,A
    LD D,$00
    ADD HL,DE
    EX DE,HL                        ; DE = the new number
    POP HL
    JP MORLIN

;; Restores the digit's flags and the text pointer, ending the line number at the digit.
POPHSR:
    POP AF
    POP HL
    RET

;; Runs RUN: runs the program from its start or from a line, or loads and runs a file (LRUN).
;;
;; In:    A = the character after RUN, zero = set for the end of the statement, HL = the text at it
ST_RUN:
    JP Z,RUNC                       ; no argument, run from the start
    CP LINCON                       ; LINCON: a line number
    JP Z,CONRUN
    CP PTRCON
    JP NZ,LRUN                      ; a file name

;; Clears the variables and the stack, then goes to the line number at HL, returning to NEWSTT.
CONRUN:
    CALL CLEARC                     ; keeps only HL
    LD BC,NEWSTT
    JP RUNC2

;; Runs GOSUB: pushes a GOSUB entry with the text pointer and line number, then goes to the line.
;;
;; The entry is the GOSUB token, the line number of the GOSUB and the text pointer after its line number.
;;
;; In:    HL = the text, at the line number
;; Errors: SN, UL, OM
ST_GOSUB:
    LD C,$03                        ; room for 6 bytes
    CALL GETSTK
    CALL LINGET                     ; DE = the line number
    POP BC                          ; BC = the return to NEWSTT
    PUSH HL                         ; the text, to continue after RETURN
    PUSH HL
    LD HL,[CURLIN]
    EX [SP],HL                      ; stack the line of the GOSUB
    LD A,TK_GOSUB                   ; the GOSUB token tags the entry
    PUSH AF
    INC SP                          ; only the token byte stays pushed
    PUSH BC
    JP GOTO2

;; Pushes the return address in BC and goes to the line number in the text.
RUNC2:
    PUSH BC

;; Runs GOTO: reads a line number and continues the program at that line.
;;
;; In:    HL = the text, at the line number
;; Errors: SN, UL
ST_GOTO:
    CALL LINGET

;; Goes to the line DE, searching from the next line when it lies ahead, and makes the text's number a pointer.
;;
;; A line-pointer constant (CONSAV = PTRCON) is used at once. A line-number constant is looked up, and the text
;; then gets a pointer to the line in its place (CONCH2), so the next GOTO there needs no search.
;;
;; In:    DE = the line number, or the line pointer for PTRCON, CONSAV = the constant's token,
;;        HL = the text after it
;; Out:   HL = the line, just before its link, for NEWSTT
;; Errors: SN, UL
GOTO2:
    LD A,[CONSAV]                   ; what LINGET read
    CP PTRCON                       ; PTRCON: DE is the line's address
    EX DE,HL
    RET Z                           ; go straight on there
    CP LINCON                       ; LINCON: the only other choice
    JP NZ,SNERR
    EX DE,HL
    PUSH HL
    LD HL,[CONTXT]                  ; just after the constant
    EX [SP],HL                      ; stack it, HL = the text
    CALL ST_REM                     ; HL = the end of the line, keeping DE
    INC HL                          ; HL = the next line
    PUSH HL
    LD HL,[CURLIN]
    CALL DCOMPR                     ; COMPAR: is the target after the current line?
    POP HL
    CALL C,LOOP                     ; ahead, search from the next line
    CALL NC,FNDLIN                  ; behind, or not found, search from the start
    JP NC,USERR                     ; no such line
    DEC BC                          ; BC = the zero ending the line before
    LD A,PTRCON
    LD [PTRFLG],A                   ; the program now has line pointers
    POP HL                          ; HL = just after the constant
    CALL CONCH2                     ; change the constant to a pointer
    LD H,B
    LD L,C
    RET

;; Reports a UL (Undefined line number) error.
USERR:
    LD E,ERR_US                     ; ERRUS
    JP ERROR

;; Runs RETURN: pops the stack to the latest GOSUB entry and continues after that GOSUB, or gives an RG error.
;;
;; In:    zero = set for the end of the statement
;; Errors: RG
ST_RETURN:
    RET NZ                          ; RETURN takes no argument
    LD D,$FF                        ; a variable no FOR entry matches
    CALL FNDFOR                     ; past all the FOR entries
    LD SP,HL                        ; drop them
    LD [SAVSTK],HL
    CP TK_GOSUB                     ; the GOSUB token?
    LD E,ERR_RG                     ; ERRRG
    JP NZ,ERROR                     ; no GOSUB is active
    POP HL                          ; HL = the line of the GOSUB
    LD [CURLIN],HL
    LD HL,NEWSTT
    EX [SP],HL                      ; HL = the text after the GOSUB's line number
    .byte $3E                       ; LD A,n: skips the POP HL

;; Pops the text pointer into HL and skips to the end of the statement.
DATAH:
    POP HL

;; Runs DATA: skips to the end of the statement, passing over quoted strings.
;;
;; Inside a quoted string only the end of the line ends it. The IF tokens passed outside quotes are counted in
;; D, so a false IF can find its own ELSE (FALSIF).
;;
;; In:    HL = the text
;; Out:   HL = the text at the colon or zero, A = it, zero = set, D = D plus the IFs passed
;; Uses:  BC
ST_DATA:
    .byte $01                       ; LD BC,nn: C = the colon, B = $0E
    .byte $3A

;; Runs REM: skips to the end of the line, passing over quoted strings.
;;
;; In:    HL = the text
;; Out:   HL = the text at the zero ending the line, A = 0, zero = set
;; Uses:  BC
;; Keeps: DE
ST_REM:
    .byte $0E                       ; LD C,n: C = 0 for REM, which ends only at the line's end
    NOP
    LD B,$00                        ; B = 0, the terminator inside quotes

;; Trades the terminators in B and C, at a quote.
EXCHQT:
    LD A,C
    LD C,B
    LD B,A
REMER:
    DEC HL                          ; undo CHRGTR's step
REMER1:
    CALL CHRGTR
    OR A
    RET Z                           ; the end of the line
    CP B
    RET Z                           ; the terminator, unless in quotes
    INC HL
    CP '"'                          ; a quote trades the terminators
    JP Z,EXCHQT
    INC A                           ; $FF: a function token, skip its number
    JP Z,REMER1
    SUB TK_IF+1                     ; the IF token
    JP NZ,REMER
    CP B                            ; carry for DATA outside quotes
    ADC A,D                         ; which counts the IFs in D
    LD D,A
    JP REMER

;; Assigns the FAC to the variable on the stack, with the variable's type minus 3 (from GETYPR) pushed above it.
;;
;; Microsoft's entry for a caller that has the type from GETYPR; nothing in MBASIC 5.21 jumps here.
;;
;; In:    HL = the text
LETCON:
    POP AF
    ADD A,$03                       ; A = the variable's type
    JP LETCN2

;; Runs LET: evaluates the expression after the equals sign and assigns it to the variable.
;;
;; In:    HL = the text, at the variable's name
;; Out:   DE = the variable's address, HL = the text after the expression
;; Errors: SN, TM, and the expression's errors
LET:
    CALL PTRGET                     ; DE = the variable's address
    CALL SYNCHR                     ; an equals sign must follow
    .byte TK_EQUAL                  ; the = token
    EX DE,HL
    LD [TEMP],HL                    ; for FOR, and user functions
    EX DE,HL
    PUSH DE                         ; keep the variable's address
    LD A,[VALTYP]                   ; the variable's type
    PUSH AF
    CALL FRMEVL                     ; the value to assign
    POP AF

;; Assigns the FAC to the variable whose address is on the stack, converting it to the type in A.
;;
;; A string is copied into string space when its text is in a buffer or belongs to another variable; a literal
;; in the program or a temporary's string is used where it is.
;;
;; In:    A = the variable's type, HL = the text
;; Out:   DE = the variable's address, HL = the text
;; Entry: INPCOM = with the variable's address in HL and the text on the stack, LETCN4 = with no conversion
LETCN2:
    EX [SP],HL                      ; HL = the variable, stack the text
INPCOM:
    LD B,A
    LD A,[VALTYP]                   ; the value's type
    CP B
    LD A,B
    JP Z,LETCN5                     ; the same: no conversion
    CALL DOCNVF                     ; convert to the variable's type
LETCN4:
    LD A,[VALTYP]
LETCN5:
    LD DE,FACLO                     ; where integers and singles are
    CP $05
    JP C,LETCN6
    LD DE,DFACLO                    ; where doubles are
LETCN6:
    PUSH HL                         ; keep the variable's address
    CP $03
    JP NZ,COPNUM                    ; numbers are copied straight in
    LD HL,[FACLO]                   ; the string's descriptor
    PUSH HL
    INC HL
    LD E,[HL]                       ; DE = the string's text
    INC HL
    LD D,[HL]
    LD HL,[TXTTAB]
    CALL DCOMPR                     ; COMPAR: below the program, in a buffer?
    JP NC,INBUFC                    ; buffer text must be copied
    LD HL,[STREND]
    CALL DCOMPR                     ; COMPAR: below the string space, a literal in the program?
    POP DE                          ; DE = the descriptor
    JP NC,DNTCPY                    ; literals are pointed at, not copied
    LD HL,DSCTMP
    CALL DCOMPR                     ; COMPAR: a temporary descriptor?
    JP NC,DNTCPY                    ; a temporary's string can be used as it is
    .byte $3E                       ; LD A,n: skips the POP DE

;; Copies a string to string space, for a string in a buffer or another variable's string.
INBUFC:
    POP DE                          ; DE = the descriptor
    CALL FRETMS                     ; free the temporary
    EX DE,HL
    CALL STRCPY                     ; copy the string

;; Frees the temporary descriptor and stores the string's descriptor in the variable.
DNTCPY:
    CALL FRETMS                     ; free the temporary, keeping its string
    EX [SP],HL                      ; HL = the variable

;; Copies the value or descriptor at DE into the variable at HL, and gets back the text pointer.
COPNUM:
    CALL VMOVE                      ; VALTYP bytes from DE to HL
    POP DE                          ; DE = the variable's address, for FOR
    POP HL                          ; HL = the text
    RET

;; Runs ON: sets the error trap line for ON ERROR GOTO, or dispatches ON n GOTO and ON n GOSUB.
;;
;; In:    A = the character after ON, HL = the text at it
;; Errors: SN, UL, FC
ST_ON:
    CP TK_ERROR                     ; the ERROR token
    JP NZ,NTOERR
    CALL CHRGTR
    CALL SYNCHR                     ; GOTO must follow ON ERROR
    .byte TK_GOTO                   ; the GOTO token
    CALL LINGET                     ; DE = the trap line
    LD A,D
    OR E
    JP Z,RESTRP                     ; line 0 turns the trap off
    CALL FNDLN1                     ; BC = the line, carry when it exists
    LD D,B                          ; DE = the line's address
    LD E,C
    POP HL                          ; HL = the text
    JP NC,USERR                     ; no such line

;; Stores the error trap line; turning the trap off inside a trap routine reports the pending error.
RESTRP:
    EX DE,HL
    LD [ONELIN],HL                  ; the trap line's address, zero for none
    EX DE,HL
    RET C                           ; a trap set: done
    LD A,[ONEFLG]                   ; in a trap routine?
    OR A
    LD A,E
    RET Z                           ; no: just turned off
    LD A,[ERRFLG]                   ; the error being trapped is reported now
    LD E,A
    JP ERRESM

;; Runs ON n GOTO or ON n GOSUB: dispatches the nth line number, or goes on if there is none.
NTOERR:
    CALL GETBYT                     ; E = n
    LD A,[HL]
    LD B,A                          ; B = the GOTO or GOSUB token
    CP TK_GOSUB                     ; the GOSUB token
    JP Z,ISGOSU
    CALL SYNCHR                     ; otherwise it must be GOTO
    .byte TK_GOTO                   ; the GOTO token
    DEC HL
ISGOSU:
    LD C,E                          ; C counts down to the line number
LOOPON:
    DEC C
    LD A,B                          ; the nth one: run the GOTO or GOSUB from here
    JP Z,GONE2
    CALL LINGT2                     ; skip a line number
    CP $2C
    RET NZ                          ; no more: carry on after ON
    JP LOOPON

;; Runs RESUME: leaves an error trap, continuing at the failing statement, the next one or a line.
;;
;; In:    HL = the text after RESUME, zero = set for the end of the statement
;; Errors: RESUME without error (REERR) outside a trap, SN, UL
ST_RESUME:
    LD DE,ONEFLG
    LD A,[DE]
    OR A
    JP Z,REERR                      ; not in a trap routine
    INC A                           ; A = 0: the trap routine ends
    LD [ERRFLG],A                   ; ERRFLG, so Control-C gives no error
    LD [DE],A
    LD A,[HL]
    CP TK_NEXT                      ; the NEXT token, for RESUME NEXT
    JP Z,RESNXT
    CALL LINGET                     ; DE = the line, zero when none
    RET NZ                          ; anything more: syntax error
    LD A,D
    OR E
    JP NZ,GOTO2                     ; RESUME n continues at line n
    INC A                           ; nonzero: retry the failing statement
    JP RESTXT

;; Runs RESUME NEXT: continues after the statement that caused the error.
RESNXT:
    CALL CHRGTR
    RET NZ                          ; anything more: syntax error

;; Goes back to the line and statement of the error: retries it if nonzero, else skips it.
;;
;; In:    zero = set to continue after the failing statement
RESTXT:
    LD HL,[ERRTXT]
    EX DE,HL                        ; DE = the text of the error
    LD HL,[ERRLIN]
    LD [CURLIN],HL                  ; back in the line of the error
    EX DE,HL
    RET NZ                          ; retry: execute the statement again
    LD A,[HL]
    OR A                            ; at a line's start?
    JP NZ,NOTBGL
    INC HL                          ; skip the link and line number
    INC HL
    INC HL
    INC HL

;; Steps to the failing statement's start, then skips it.
NOTBGL:
    INC HL
    JP ST_DATA

;; Runs ERROR: makes the error with the given code happen.
;;
;; In:    HL = the text, at the code
;; Errors: the given code, FC for 0, SN
ST_ERROR:
    CALL GETBYT                     ; A = E = the code
    RET NZ                          ; anything more: syntax error
    OR A
    JP Z,FCERR                      ; code 0 is an FC error
    JP ERROR

;; Runs AUTO: numbers new lines automatically from a start line by an increment, both 10 by default.
;;
;; A period is the current line; a comma with no increment after it keeps the last increment.
;;
;; In:    HL = the text after AUTO, zero = set for the end of the statement
;; Errors: SN, FC for an increment of 0
ST_AUTO:
    LD DE,$000A                     ; 10, the default start and increment
    PUSH DE                         ; the start line
    JP Z,SNGAUT                     ; AUTO alone: 10, 10
    CALL LINSPC                     ; DE = the start line
    EX DE,HL
    EX [SP],HL                      ; stack the start, HL = 10
    JP Z,SNGAU1                     ; no increment: 10
    EX DE,HL
    CALL SYNCHR                     ; a comma must follow
    .byte ','
    EX DE,HL
    LD HL,[AUTINC]                  ; the last increment
    EX DE,HL
    JP Z,SNGAUT                     ; a trailing comma keeps it
    CALL LINGET                     ; DE = the increment
    JP NZ,SNERR                     ; anything more: syntax error

;; Sets AUTO going with the increment in DE and the start line on the stack.
SNGAUT:
    EX DE,HL

;; Sets AUTO going with the increment in HL and the start line on the stack.
SNGAU1:
    LD A,H
    OR L
    JP Z,FCERR                      ; an increment of 0 is an FC error
    LD [AUTINC],HL
    LD [AUTFLG],A                   ; nonzero: AUTO on
    POP HL
    LD [AUTLIN],HL                  ; the first line number offered
    POP BC                          ; drop the return to NEWSTT
    JP MAIN                         ; the command level now offers the numbers

;; Runs IF: evaluates the condition and runs the THEN part if it is true, else the matching ELSE part.
;;
;; In:    HL = the text, at the condition
;; Errors: SN, and the expression's errors
ST_IF:
    CALL FRMEVL                     ; the condition
    LD A,[HL]
    CP $2C                          ; a comma may come before THEN
    CALL Z,CHRGTR
    CP TK_GOTO                      ; GOTO may stand for THEN
    JP Z,OKGOTO
    CALL SYNCHR                     ; otherwise THEN must follow
    .byte TK_THEN                   ; the THEN token
    DEC HL

;; Tests the condition in the FAC, running the THEN part if it is true and looking for an ELSE if not.
OKGOTO:
    PUSH HL
    CALL VSIGN                      ; zero when false
    POP HL
    JP Z,FALSIF

;; Runs the THEN or ELSE part: goes to a line number, or executes the statement.
DOCOND:
    CALL CHRGTR
    RET Z                           ; THEN or ELSE with nothing after them
    CP LINCON                       ; LINCON: a line number means GOTO
    JP Z,ST_GOTO
    CP PTRCON                       ; PTRCON: a line pointer
    JP NZ,GONE2                     ; anything else is a statement
    LD HL,[CONLO]                   ; HL = the line, for NEWSTT
    RET

;; Skips a false IF's THEN part to its matching ELSE, counting nested IFs, or to the end of the line.
FALSIF:
    LD D,$01                        ; one ELSE to find
SKPMRF:
    CALL ST_DATA                    ; skip a statement, counting IFs in D
    OR A
    RET Z                           ; the line ended with no ELSE
    CALL CHRGTR
    CP TK_ELSE                      ; the ELSE token
    JP NZ,SKPMRF
    DEC D                           ; a nested IF's ELSE: keep looking
    JP NZ,SKPMRF
    JP DOCOND                       ; the matching ELSE: run what follows it
