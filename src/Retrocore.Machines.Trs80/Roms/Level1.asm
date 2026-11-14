;; TRS-80 LEVEL I BASIC ($0000-$0FFF), FOR THE MODEL I AND MODEL III
;;
;; Level I is the Model I's first BASIC: 4K of ROM derived from Li-Chen Wang's Palo Alto Tiny BASIC,
;; with Radio Shack's floating point, screen graphics and cassette routines. The Model III offered it too,
;; in a ROM of its own (8040032) that MODEL = 3 builds: the same BASIC, with LPRINT and LLIST for the
;; printer, the Model III's ports for the cassette and the reset button's NMI at $0066, and its restarts
;; moved so that RST $18 skips blanks, RST $28 prints on the screen and EXPR is a call.
;;
;; Like Tiny BASIC it uses the restarts as one-byte calls: TSTC tests for a character, OUTC prints one,
;; EXPR evaluates an expression, COMP compares HL with DE, IGNBLK skips blanks, FINISH ends a statement and
;; TSTV finds a variable. TSTC is followed by the character and an offset to continue at when it does not
;; match, written here with the TSTC macro. Keywords live in tables of entries, each the word and then its
;; handler's address, high byte first with bit 7 set; EXEC looks a word up, allowing abbreviations that
;; end in a period, and an entry with no word is the table's default.
;;
;; Assembles byte-identically to the Level I ROM, and with MODEL = 3 to the Model III's. Labels keep Wang's names from
;; Palo Alto Tiny BASIC where Level I keeps his routine instruction for instruction (EXPR2, FNDLN, QTSTG, MVUP); keyword
;; handlers are named after their word, other routines after what they do, and their inner labels after the routine. The
;; comments are our own, written with trs-80.com's annotated disassembly of Level I as a reference.
;;
;; Maintained by hand. Trs80RomSourceTests check that each model's build assembles byte-identically to its ROM.

.cpu Z80

.ifndef MODEL
MODEL = 1
.endif
.assert MODEL = 1 || MODEL = 3, "MODEL is 1 or 3."

; The restarts that moved on the Model III: IGNBLK took RST $18, and EXPR became a call.
.if MODEL = 1
IGNBLK_RST = $28
.else
IGNBLK_RST = $18
.endif

;; Evaluates the expression at DE: RST $18 on the Model I, a call on the Model III.
.macro EVALUATE
.if MODEL = 1
    RST $18
.else
    CALL EXPR
.endif
.endmacro

;; TSTC: tests whether the next nonblank character is the given one. On a match it steps past it and
;; continues after the test; otherwise it continues at the mismatch label.
.macro TSTC character, mismatch
    RST $08
    .byte character
    .byte (mismatch) - * - 1
.endmacro

;; A table entry: the word, then its handler's address, high byte first with bit 7 set.
.macro ENTRY word, handler
    .byte word
    .byte >(handler) | $80, <(handler)
.endmacro

;; A table's last entry: where to go when no word matches.
.macro DEFAULT handler
    .byte >(handler) | $80, <(handler)
.endmacro

KEYBOARD_ROW0 = $3801
KEYBOARD_ALL = $387F                ;; every row at once: nonzero while any key is down
KEYBOARD_ROW7 = $3880               ;; SHIFT
VIDEO = $3C00
BLINKSTAR = $3C01                   ;; the screen's second character, where an asterisk blinks as tape lines are read
CURSOR = $4068                      ;; the cursor's address in video RAM
MEMTOP = $406A                      ;; the top of memory; the array grows down from it
TXTUNF = $406C                      ;; the end of the program text
LOPLMT = $406E                      ;; the innermost FOR loop's limit
.if MODEL = 1
PORT_FF_IMAGE = $4090               ;; the last value written to port $FF
.else
LPRINTING = $4090                   ;; nonzero while LPRINT or LLIST sends OUTC's characters to the printer
.endif
LOPINC = $4091                      ;; its STEP
LOPLN = $4093                       ;; the line holding its FOR
LOPPT = $4095                       ;; the text position after its FOR statement
STOPLN = $4097                      ;; the line STOP stopped, for CONT
INPPTR = $4099                      ;; a position kept in the input or the tape line buffer
SCRATCH = $409B                     ;; a word kept across a call: a GOSUB line, NEXT's variable or INPUT's stack
STOPPT = $409D                      ;; the text position where CONT resumes
CURRNT = $409F                      ;; the current line
DATAPTR = $40A1                     ;; where the next DATA item is
STKGOS = $40A3                      ;; the latest GOSUB frame on the stack
LOPVAR = $40A5                      ;; the innermost FOR loop's variable, or 0 for none

.org $0000

.if MODEL = 1
;; Power-up and reset: interrupts off, then the cold start.
START:
    DI
    LD HL,$00FF                     ; with the DEC H in COLD_START, the probe starts at $FFFF
    JP COLD_START
    .byte $00

;; RST $08: compares the next nonblank character at DE with the byte after the RST. On a match it steps
;; DE past it and returns past both inline bytes; otherwise it returns to the inline offset's target.
TSTC:
    EX [SP],HL                      ; HL = return address, pointing at the inline character
    RST IGNBLK_RST
    CP [HL]                         ; compare with the character TSTC is looking for
    JP TSTC_RESOLVE

;; Prints a carriage return, falling into OUTC.
CRLF:
    LD A,$0D

;; RST $10: prints the character in A on the screen, keeping every register.
OUTC:
    EXX                             ; switch to the alternate registers so callers keep theirs
    EX AF,AF'
    CALL PORT_FF_REFRESH            ; NZ while the tape motor runs, sending the character to tape
    JP OUTC_TAPE

;; RST $18: evaluates the expression at DE.
EXPR:
    CALL EXPR2
    NOP                             ; padding
    JP EXPR_RELOP
    .byte $00

;; RST $20: compares HL with DE, setting Z and C as for CP.
COMP:
    LD A,H                          ; high bytes first, low bytes only when they are equal
    CP D
    RET NZ
    LD A,L
    CP E
    RET
    .byte $00, $00

;; RST $28: skips spaces at DE and returns the next character in A.
IGNBLK:
    LD A,[DE]
    CP $20                          ; a space?
    RET NZ
    INC DE
    JP IGNBLK

;; RST $30: ends a statement: the line must end here, or it is a WHAT? error.
FINISH:
    POP AF
    CALL FIN
    JP QWHAT
    .byte $00

.else
;; Power-up and reset: interrupts off, then the cold start.
START:
    DI
    LD HL,$00FF                     ; with the DEC H in COLD_START, the probe starts at $FFFF

;; Finds the top of RAM by stepping down a page at a time until a byte can be changed. The probe goes on at
;; COLD_START_1, in the room TSTV leaves for the NMI's entry.
COLD_START:
    DEC H                           ; next page down
    LD A,[HL]                       ; try to change the byte
    JR COLD_START_1

;; RST $08: compares the next nonblank character at DE with the byte after the RST. On a match it steps
;; DE past it and returns past both inline bytes; otherwise it returns to the inline offset's target.
TSTC:
    EX [SP],HL                      ; HL = return address, pointing at the inline character
    RST IGNBLK_RST
    CP [HL]                         ; compare with the character TSTC is looking for
    JP TSTC_RESOLVE

;; Prints a carriage return, falling into OUTC.
CRLF:
    LD A,$0D

;; RST $10: prints the character in A on the screen, or the printer while LPRINTING is set, and to tape while
;; the cassette motor runs. It keeps every register while the motor is off.
OUTC:
    EX AF,AF'
    IN A,[$FF]
    AND $02                         ; the cassette motor, as port $EC set it
    JP OUTC_TAPE

;; RST $18: skips spaces at DE and returns the next character in A.
IGNBLK:
    LD A,[DE]
    CP $20                          ; a space?
    RET NZ
    INC DE
    JP IGNBLK

;; RST $20: compares HL with DE, setting Z and C as for CP.
COMP:
    LD A,H                          ; high bytes first, low bytes only when they are equal
    CP D
    RET NZ
    LD A,L
    CP E
    RET

;; Prints a carriage return on the screen, falling into SCREEN_OUTC.
SCREEN_CRLF:
    LD A,$0D

;; RST $28: prints the character in A on the screen, ending any LPRINT or LLIST. It keeps every register while
;; the cassette motor is off; while it runs, the character also goes to tape, which changes the flags.
SCREEN_OUTC:
    PUSH AF
    XOR A
    LD [LPRINTING],A
    POP AF
    JR OUTC

;; RST $30: ends a statement: the line must end here, or it is a WHAT? error.
FINISH:
    POP AF
    CALL FIN
    JP QWHAT
    .byte $00

.endif

;; RST $38: tests for a variable at DE (A-Z, or A(n)), returning its address in HL; carry when there is none.
TSTV:
    RST IGNBLK_RST
    SUB $41                         ; letter number, 0 for A
    RET C                           ; below A: not a variable
    CP $1A                          ; past Z also sets carry
    CCF
    RET C
    INC DE                          ; step past the letter
    AND A                           ; any letter but A is a simple variable
    JR NZ,TSTV_SIMPLE
    TSTC '(', TSTV_PLAIN_A          ; A without ( is the plain variable A
    CALL EXPR_UINT                  ; the subscript, HOW? if negative
    INC HL                          ; element n is the (n+1)th, counting down from the top
    ADD HL,HL                       ; four bytes per element
    ADD HL,HL
    JP C,AHOW                       ; subscript too large to address
    PUSH HL                         ; save the element offset
    TSTC ')', TSTV_WHAT
.if MODEL = 3
    JR TSTV_ROOM                    ; over the cold start's end and the NMI's entry, which must be at $0066

;; The cold start's probe, continued: when a byte takes its complement, HL is the top of memory, and BASIC
;; starts with an empty program, through the NMI's entry.
COLD_START_1:
    CPL
    LD [HL],A
    CP [HL]                         ; zero when it took the new value: RAM found
    CPL
    LD [HL],A                       ; put the byte back
    JR NZ,COLD_START                ; ROM or nothing there: keep looking
    LD [MEMTOP],HL                  ; the top of memory
    LD HL,$4200                     ; an empty program
    LD [TXTUNF],HL

    .assert * = $0066, "The NMI's entry is at $0066."

;; The NMI, which the reset button raises: back to READY with a clean stack, the interrupts and NMIs masked,
;; the cassette's output quiet and the screen cleared.
NMI:
    DI
    LD SP,$4200
    XOR A
    OUT [$E0],A                     ; mask the interrupts
    OUT [$FF],A                     ; the cassette's output
    OUT [$E4],A                     ; mask the NMIs
    LD A,$20                        ; options: video wait, the cassette motor off
    OUT [$EC],A
    LD A,$0C                        ; clear the screen
    RST $28
    JP RSTART

;; Room for A(n)'s element: the free bytes, from the top of memory down to the program.
TSTV_ROOM:
.endif
    POP HL
    PUSH DE                         ; keep the text pointer
    PUSH HL
    LD HL,[MEMTOP]                  ; free bytes = top of memory minus end of program
    LD DE,[TXTUNF]
    XOR A
    SBC HL,DE
    POP DE                          ; DE = the element offset
    RST $20                         ; carry when the array would reach the program
.if MODEL = 1
    JP TSTV_ARRAY_ADDR
    DI                              ; NMI (reset button) entry: back to READY with a clean stack
    LD SP,$4200
    XOR A                           ; port $FF: motor off, 64 columns
    LD [PORT_FF_IMAGE],A
    OUT [$FF],A
    LD A,$0C                        ; clear the screen
    RST $10
    JP RSTART
.endif
;; Finishes A(n): SORRY? when the element would reach the program, otherwise returns its
;; address, counted down from the top of memory.
TSTV_ARRAY_ADDR:
    JP C,ERROR_3                    ; no room for the element: SORRY
    LD HL,[MEMTOP]                  ; element address = top of memory minus its offset
    SBC HL,DE
    POP DE                          ; restore the text pointer
    XOR A                           ; no carry: a variable was found
    RET
;; Treats an A with no parenthesis as the plain variable A.
TSTV_PLAIN_A:
    XOR A
;; Returns the address of a simple variable: $4000 plus four times its letter number.
;; Out: HL = the variable's address
TSTV_SIMPLE:
    LD H,$40                        ; variables live at $4000, four bytes each
    RLA
    RLA
    LD L,A
    XOR A                           ; no carry: a variable was found
    RET
;; Jumps to QWHAT when the closing parenthesis of A(n) is missing.
TSTV_WHAT:
    JP QWHAT

;; Tests the character at DE for a digit; returns its value in A, or carry when it is not one.
TSTDIG:
    LD A,[DE]
    CP $30                          ; below 0?
    RET C
    CP $3A                          ; past 9 also sets carry
    CCF
    RET C
    INC DE                          ; step past the digit
    AND $0F                         ; ASCII digit to its value
    RET
;; Finishes TSTC: on a match steps DE past the character, otherwise adds the inline offset
;; to the return address.
TSTC_RESOLVE:
    INC HL                          ; HL at the inline offset byte
    JR Z,TSTDIG_2                   ; matched: just step past the character
    PUSH BC
    LD C,[HL]                       ; BC = the mismatch offset
    LD B,$00
    ADD HL,BC                       ; HL moves to the mismatch target, less one
    POP BC
    DEC DE                          ; cancels the INC DE below, as nothing was matched
TSTDIG_2:
    INC DE                          ; step past the matched character
    INC HL                          ; past the offset byte: the address to continue at
    EX [SP],HL                      ; restore HL and make that the return address
    RET

;; Reads a numeric constant at DE, with an optional decimal point and E exponent, onto the
;; FP stack.
;; Out: zero = no digits; clear when a number was read and pushed
FP_PARSE_CONST:
    CALL FP_PARSE_RESET
    LD B,$00                        ; no flags: no digits, point, exponent or overflow yet
    LD C,B                          ; C = power of ten adjustment, starting at zero
    RST IGNBLK_RST

;; Handles characters one at a time until a handler leaves the loop.
FP_PARSE_LOOP:
    CALL FP_PARSE_CHAR
    JR FP_PARSE_LOOP

;; Handles one character of a number: adds a digit, or else checks for the decimal point.
FP_PARSE_CHAR:
    CALL TSTDIG                     ; a digit? otherwise check for the point
    JR C,FP_PARSE_POINT
    SET 6,B                         ; flag that a digit was read
    BIT 7,B                         ; mantissa already full?
    JR NZ,FP_PARSE_EXTRA
    CALL FP_PARSE_DIGIT
    BIT 0,B                         ; before the point the digit raises no power
    RET Z
    DEC C                           ; each digit after the point is one more power of ten down
    RET

;; Adds the digit in A to the mantissa; when it no longer fits, keeps the old value and
;; marks the mantissa full.
FP_PARSE_DIGIT:
    CALL MUL10                      ; mantissa times ten plus the digit
    RET Z                           ; Z: it still fits
    EXX
    LD H,D                          ; restore the mantissa saved by MUL10
    LD L,E
    EX AF,AF'                       ; and its top byte
    LD C,A
    EXX
    SET 7,B                         ; mark the mantissa full
    POP AF                          ; drop the return to FP_PARSE_CHAR, counting it as extra

;; Counts a digit that did not fit, raising the power of ten unless it follows the point.
FP_PARSE_EXTRA:
    BIT 0,B                         ; after the point an extra digit changes nothing
    RET NZ
    INC C                           ; before it, it multiplies the value by ten
    RET

;; Checks for a decimal point; a second one ends the number.
FP_PARSE_POINT:
    TSTC '.', FP_PARSE_END
    BIT 0,B                         ; first point?
    SET 0,B                         ; mark the point seen
    RET Z                           ; first point: keep reading digits

;; Ends the digits: with none returns Z, otherwise pushes the mantissa and goes on to look
;; for an E exponent.
FP_PARSE_END:
    POP AF                          ; drop the return to FP_PARSE_LOOP, leaving the loop
    BIT 6,B                         ; no digits: not a number
    RET Z
    LD L,$18                        ; exponent for the 24-bit integer mantissa
    LD H,$00
    PUSH BC
    PUSH DE
    EXX
    CALL FP_NORMALIZE
    LD BC,$000A
    ADD IX,BC                       ; two entries up, as FP_STORE_RESULT fills one and drops one
    POP DE
    LD BC,FP_PARSE_EXPONENT         ; the return address: just past this jump
    PUSH BC
    PUSH DE
    JP FP_STORE_RESULT

;; Goes on to the exponent, if any, after FP_STORE_RESULT stores the mantissa.
FP_PARSE_EXPONENT:
    POP BC                          ; recover the parse flags and power of ten
    PUSH DE                         ; keep the position in case E is not an exponent
    TSTC 'E', FP_NO_EXP             ; no E: the number has no exponent
    TSTC '+', FP_EXP_SIGN           ; skip a plus sign, or check for minus
    JR FP_EXP_START

;; Checks for a minus sign after the E, marking the exponent negative.
FP_EXP_SIGN:
    .byte $CF, $2D, $02, $CB, $C8

;; Clears the accumulator to read the exponent's digits.
FP_EXP_START:
    CALL FP_ACCUM_CLEAR

;; Adds each exponent digit to the accumulator, HOW? on overflow.
FP_EXP_DIGIT:
    CALL TSTDIG
    JR C,FP_EXP_END
    SET 5,B                         ; flag that an exponent digit was read
    CALL MUL10
    JP NZ,AHOW                      ; exponent too large
    JR FP_EXP_DIGIT

;; Moves DE back to where the E was looked for and uses an exponent of zero.
FP_NO_EXP:
    POP DE                          ; back to before the E
    XOR A                           ; exponent zero
    JR FP_SCALE

;; Ends the exponent: HOW? if it does not fit in seven bits, then applies its sign.
FP_EXP_END:
    BIT 5,B                         ; E with no digits after it is not an exponent
    JR Z,FP_NO_EXP
    POP AF                          ; drop the saved position before the E
    EXX
    LD A,C                          ; high bytes of the exponent must be zero
    OR H
    JR NZ,FP_EXP_HOW
    LD A,L
    EXX
    BIT 7,A                         ; over 127 is too large
    JP NZ,AHOW
    BIT 1,B                         ; negative exponent?
    JR Z,FP_SCALE
    NEG                             ; make the exponent negative

;; Adds the digit count adjustment in C to the power of ten in A.
FP_SCALE:
    ADD A,C                         ; combine with the digit count adjustment

;; Multiplies or divides the number by ten until the power of ten in A is used up.
FP_SCALE_LOOP:
    AND A
    JR Z,FP_PARSE_DONE              ; no power left: done
    BIT 7,A                         ; negative: divide by ten
    JR Z,FP_SCALE_UP
    INC A                           ; one power used up
    PUSH AF
    CALL FP_DIV10
    JR FP_SCALE_NEXT

;; Multiplies the number by ten for a positive power.
FP_SCALE_UP:
    DEC A                           ; one power used up
    PUSH AF
    CALL FP_MUL10

;; Recovers the remaining power and repeats.
FP_SCALE_NEXT:
    POP AF
    JR FP_SCALE_LOOP

;; Returns NZ when digits were read.
FP_PARSE_DONE:
    BIT 6,B                         ; NZ when the number had digits
    RET

;; Reports HOW? for an exponent that is too large.
FP_EXP_HOW:
    EXX
    JP AHOW

;; Clears the digit-seen flag (bit 6 of B) and the accumulator in C', H' and L'.
FP_PARSE_RESET:
    RES 6,B                         ; no digit seen yet

;; Clears the 24-bit accumulator in C', H' and L'.
FP_ACCUM_CLEAR:
    EXX
    LD L,$00
    LD H,L
    LD C,L
    EXX
    RET

;; Multiplies HL by ten and adds the digit in A.
MUL10:
    EX AF,AF'                       ; A' = the digit to add
    EXX
    LD D,H                          ; DE = old low word, kept to restore on overflow
    LD E,L
    LD A,C                          ; A = old top byte, likewise
    LD B,$00                        ; B collects bits shifted past 24
    PUSH AF                         ; save the old top byte
    ADD HL,HL                       ; times two
    RL C
    RL B
    ADD HL,HL                       ; times four
    RL C
    RL B
    ADD HL,DE                       ; plus the original makes times five
    ADC A,C
    LD C,A
    LD A,$00                        ; carry into the overflow byte
    ADC A,B
    LD B,A
    POP AF                          ; A = old top byte again
    ADD HL,HL                       ; times ten
    RL C
    RL B
    EX AF,AF'                       ; A = the digit, A' = old top byte
    ADD A,L                         ; add the digit, carrying up through every byte
    LD L,A
    LD A,$00
    ADC A,H
    LD H,A
    LD A,$00
    ADC A,C
    LD C,A
    LD A,$00
    ADC A,B
    LD B,A
    EXX
    RET
;; Finds the top of RAM by stepping down a page at a time until a byte can be changed, then
;; starts BASIC with an empty program.
.if MODEL = 1
COLD_START:
    DEC H                           ; next page down
    LD A,[HL]                       ; try to change the byte
    CPL
    LD [HL],A
    XOR [HL]                        ; zero when it took the new value: RAM found
    JR NZ,COLD_START                ; ROM or nothing there: keep looking
    LD [MEMTOP],HL                  ; the top of memory
    XOR A                           ; port $FF image: motor off, 64 columns
    LD [PORT_FF_IMAGE],A
    LD SP,$4200
    JP ST_NEW_CLEAR
.endif

;; HOW? error: a number or line outside its range.
AHOW:
    PUSH DE                         ; keep the text pointer for the error display
AHOW_1:
    LD DE,HOW_MSG
    JP ERROR

;; Holds the HOW? message, ending in a carriage return.
HOW_MSG:
    .byte "HOW?", $0D

.if MODEL = 1
READY_MSG:
    .byte "READY", $0D

WHAT_MSG:
    .byte "WHAT?", $0D

SORRY_MSG:
    .byte "SORRY", $0D
.endif

BREAK_MSG:
    .byte "BREAK AT", $00

;; Warm start: prints READY, then reads lines, storing numbered ones and running others.
RSTART:
    LD SP,$4200
    CALL CASSETTE_OFF               ; stop any tape motor left running
.if MODEL = 1
    CALL CRLF
.else
    CALL SCREEN_CRLF
.endif
    LD DE,READY_MSG
    CALL PRTSTG
;; Resets the stack and the run state, then reads the next line.
RSTART_RESET:
    LD SP,$4200
    CALL CLEAR_RUN_STATE
RSTART_2:
    LD IX,$40F4                     ; empty the FP stack
    CALL GETLN
    PUSH DE                         ; keep the end of the typed line
    LD DE,$40AC                     ; the input buffer
    CALL TSTNUM                     ; is there a line number?
    LD A,H
    OR L
    POP BC                          ; BC = the end of the line
    JP Z,DIRECT                     ; no number: run the line at once
    DEC DE                          ; store the line number in front of the text
    LD A,H
    LD [DE],A
    DEC DE
    LD A,L
    LD [DE],A
    PUSH BC                         ; keep the end and the start of the new line
    PUSH DE
    LD A,C                          ; A = the line's length with its number and CR
    SUB E
    PUSH AF                         ; keep the length
    CALL FNDLN                      ; find the line in the program, or where it goes
    PUSH DE                         ; keep where the line goes
    JR NZ,RSTART_3                  ; no such line yet: just insert
    PUSH DE                         ; a line with that number exists: delete it first
    CALL FNDNXT                     ; DE = the line after it
    POP BC                          ; BC = the old line's start
    LD HL,[TXTUNF]                  ; move the rest of the program down over it
    CALL MVUP
    LD H,B                          ; the program now ends where the move ended
    LD L,C
    LD [TXTUNF],HL
RSTART_3:
    POP BC                          ; BC = where the line goes
    LD HL,[TXTUNF]
    POP AF                          ; A = the new line's length
    PUSH HL                         ; keep the old end of the program
    CP $03                          ; just a number and CR: the line was only deleted
    JR Z,RSTART_RESET
    ADD A,L                         ; HL = the program's end after inserting
    LD L,A
    LD A,$00
    ADC A,H
    LD H,A
    LD DE,[MEMTOP]                  ; room below the top of memory?
    RST $20
    JP NC,QSORRY                    ; no: out of memory
    LD [TXTUNF],HL                  ; the program's new end
    POP DE                          ; DE = the old end
    CALL MVDOWN                     ; open a gap for the new line
    POP DE                          ; DE = start, HL = end of the line in the buffer
    POP HL
    CALL MVUP                       ; copy the line into the gap
    JR RSTART_RESET

;; Clears the ten bytes of run state at $409D-$40A6 and points DE at the program start.
;; Out: DE = $4200
CLEAR_RUN_STATE:
    LD B,$0A                        ; STOP point, current line, DATA pointer, GOSUB and FOR state
    PUSH HL
    LD HL,$409D

;; Clears one byte per pass.
CLEAR_RUN_LOOP:
    LD [HL],$00
    INC HL
    DJNZ CLEAR_RUN_LOOP
    LD DE,$4200                     ; the program starts at $4200
    POP HL
    RET

;; Lists the statement keywords and their handlers; a statement with no keyword is a LET.
TABLE1:
    ENTRY "LIST", ST_LIST
.if MODEL = 3
    ENTRY "LLIST", ST_LLIST
.endif
    ENTRY "RUN", ST_RUN
    ENTRY "NEW", ST_NEW
    ENTRY "CONT", ST_CONT
    ENTRY "CLOAD", ST_CLOAD
    ENTRY "CSAVE", ST_CSAVE
;; The statements a program can run; those before are direct only.
TABLE1_PROGRAM:
    ENTRY "NEXT", ST_NEXT
    ENTRY "LET", ST_LET
    ENTRY "INPUT", ST_INPUT
    ENTRY "IF", ST_IF
    ENTRY "ON", ST_ON
    ENTRY "GOTO", ST_GOTO
    ENTRY "GOSUB", ST_GOSUB
    ENTRY "RESET", ST_RESET
    ENTRY "RETURN", ST_RETURN
    ENTRY "READ", ST_READ
    ENTRY "RESTORE", ST_RESTORE
    ENTRY "REM", ST_REM
    ENTRY "DATA", ST_REM
    ENTRY "FOR", ST_FOR
    ENTRY "PRINT", ST_PRINT
    ENTRY "SET", ST_SET
    ENTRY "STOP", ST_STOP
    ENTRY "END", ST_END
    ENTRY "CLS", ST_CLS
.if MODEL = 3
    ENTRY "LPRINT", ST_LPRINT
.endif
    DEFAULT IMPLIED_LET

TABLE2:
    ENTRY "GOTO", ON_GOTO
    ENTRY "GOSUB", ON_GOSUB
    DEFAULT QWHAT

TABLE3:
    ENTRY "RND", FN_RND
    ENTRY "ABS", FN_ABS
    ENTRY "MEM", FN_MEM
    ENTRY "INT", FN_INT
    ENTRY "POINT", FN_POINT
    DEFAULT NOT_FUNCTION

TABLE4:
    ENTRY "TO", FOR_TO
    DEFAULT QWHAT

TABLE5:
    ENTRY "STEP", FOR_STEP
    DEFAULT FOR_NO_STEP

.if MODEL = 1
TABLE6:
    ENTRY "TAB", PRINT_TAB
    ENTRY "AT", PRINT_AT
    ENTRY "A$", PRINT_ASTRING
    ENTRY "B$", PRINT_BSTRING
    DEFAULT PRINT_ITEM

.endif

TABLE7:
    ENTRY ">", REL_GREATER
    ENTRY "=", REL_EQUAL
    ENTRY "<", REL_LESS
    DEFAULT REL_NONE

TABLE8:
    ENTRY "THEN", IF_THEN
    DEFAULT IF_NO_THEN

;; Runs a line typed without a line number, looking its keyword up in TABLE1.
DIRECT:
    LD HL,TABLE1 - 1                ; one before TABLE1, as EXEC steps first

;; Looks the word at DE up in the keyword table at HL, allowing abbreviations that end in a period, and
;; jumps to its handler, or to the table's default when nothing matches.
EXEC:
    RST IGNBLK_RST
    PUSH DE                         ; keep the word's start to retry with the next entry
    LD A,[DE]
    INC DE
    INC HL
    CP [HL]
    JR Z,EXEC_MATCH
    BIT 7,[HL]                      ; an address byte: this is the table's default entry
    JR NZ,EXEC_2
    JR EXEC_4                       ; mismatch: try the next entry
;; Keeps comparing while the word matches the entry.
EXEC_MATCH:
    LD A,[DE]
    INC DE
    INC HL
    CP [HL]
    JR Z,EXEC_MATCH
    BIT 7,[HL]                      ; the whole word matched?
    JR Z,EXEC_ABBREV
EXEC_2:
    DEC DE                          ; give back the character read past the word
    JR EXEC_6
;; Accepts a period as an abbreviation of the rest of the entry's word.
EXEC_ABBREV:
    CP $2E                          ; a period abbreviates the rest of the word
    JR Z,EXEC_FIND_ADDR
EXEC_4:
    INC HL                          ; skip to the entry's address bytes
    BIT 7,[HL]
    JR Z,EXEC_4
    INC HL                          ; past the low byte to the next entry
    POP DE                          ; back to the word's start
    JR EXEC
;; Skips the rest of an abbreviated word to reach the handler's address.
EXEC_FIND_ADDR:
    INC HL
    BIT 7,[HL]
    JR Z,EXEC_FIND_ADDR
EXEC_6:
    LD A,[HL]
    INC HL
    LD L,[HL]
    AND $7F                         ; clear the marker bit from the high byte
    LD H,A
    POP AF                          ; drop the saved word start
    JP [HL]                         ; to the handler, DE past the word
.if MODEL = 1
;; Handles NEW: clears the screen and the program, then returns to READY.
ST_NEW:
    CALL ENDCHK
;; Clears the screen and empties the program, then returns to READY; the cold start
;; enters here.
ST_NEW_CLEAR:
    LD A,$0C                        ; clear the screen
    RST $10
    LD HL,$4200                     ; an empty program: its end is its start
    LD [TXTUNF],HL
ST_NEW_2:
    JP RSTART
;; Handles END: returns to READY.
ST_END:
    CALL ENDCHK
    JR ST_NEW_2
;; Handles RUN: clears the run state and runs from the given line, or from the first.
ST_RUN:
    CALL LINENUM_ENDCHK
    CALL CLEAR_RUN_STATE            ; forget STOP, GOSUB, FOR and READ state
    JR ST_RUN_2
;; Runs the line after the one at DE, or returns to READY at the end of the program.
RUNNXL:
    LD HL,START                     ; line 0: the first line at or after DE
ST_RUN_2:
    CALL FNDLP                      ; find the line to run
    JR C,ST_NEW_2                   ; past the last line: READY
ST_RUN_3:
    LD [CURRNT],DE                  ; the current line
    INC DE                          ; skip the line number to the text
    INC DE
ST_RUN_4:
    CALL KBD_SCAN                   ; check for a key between statements
    CP $03                          ; BREAK?
    JR Z,ST_STOP
    CALL CASSETTE_OFF
    LD IX,$40F4                     ; empty the FP stack
    LD HL,TABLE1_PROGRAM - 1        ; TABLE1 from NEXT: LIST, RUN, NEW and the like are direct only
    JR EXEC
;; Handles GOTO: runs from the given line, HOW? if there is no such line.
ST_GOTO:
    CALL READ_LINENUM
    PUSH DE                         ; keep the text pointer for an error
    CALL ENDCHK
ST_GOTO_1:
    CALL FNDLN
    JP NZ,AHOW_1                    ; no such line: HOW?
    POP AF                          ; drop the saved text pointer
    JR ST_RUN_3
;; Handles STOP and BREAK: prints BREAK AT and the line number, keeping the place for CONT.
ST_STOP:
    LD [STOPPT],DE                  ; where CONT resumes
    LD A,$0D
    RST $10
    LD DE,BREAK_MSG
    CALL PRTSTG
    LD HL,[CURRNT]                  ; the stopped line
    LD [STOPLN],HL                  ; also kept for CONT
    LD E,[HL]                       ; DE = its line number
    INC HL
    LD D,[HL]
    LD HL,START                     ; no current line: back in direct mode
    LD [CURRNT],HL
    EX DE,HL
    CALL PRTNUM
    LD A,$0D
    RST $10
ST_STOP_1:
    JP RSTART_2                     ; read lines without READY, keeping CONT's state
;; Handles CONT: resumes after the last STOP or BREAK, or returns to READY if there is none.
ST_CONT:
    CALL ENDCHK
    LD HL,[STOPPT]                  ; the resume point saved by STOP
    LD A,H
    OR L
    JR Z,ST_NEW_2                   ; nothing to continue
    EX DE,HL
    LD HL,[STOPLN]                  ; the line that was stopped
    LD [CURRNT],HL
    CALL FIN                        ; at a statement end, move on to the next one
ST_CONT_1:
    JR ST_RUN_4
;; Handles LIST: lists twelve lines from the given line, then one more for each up arrow
;; until ENTER.
ST_LIST:
    CALL LINENUM_ENDCHK             ; the first line to list, or 0
    CALL FNDLN
    LD C,$0C                        ; twelve lines before waiting
ST_LIST_1:
    JR C,ST_LIST_4                  ; past the end of the program
    DEC C
    JR Z,LIST_MORE
    PUSH BC
    CALL PRTLN
    POP BC
    CALL FNDLP
    JR ST_LIST_1
;; Lists one more line, then waits for up arrow (another line) or ENTER (stop).
LIST_MORE:
    CALL PRTLN
    CALL FNDLP
    JR C,ST_LIST_4
ST_LIST_3:
    CALL KBD_SCAN                   ; wait for a key
    JR Z,ST_LIST_3
    CP $1B                          ; up arrow: one more line
    JR Z,LIST_MORE
    CP $0D                          ; ENTER stops the listing
    JR NZ,ST_LIST_3
ST_LIST_4:
    JR ST_STOP_1
;; Handles PRINT; after PRINT # the output goes to tape.
ST_PRINT:
    TSTC '#', PRINT_COLON
    LD HL,$40AC                     ; output collects in the buffer until a CR writes it
    LD [INPPTR],HL                  ; the tape line buffer pointer
    CALL CASSETTE_ON                ; output goes to tape while the motor runs
.else
;; Handles NEW: restarts, as at power-up, which clears the program and the screen.
ST_NEW:
    CALL ENDCHK
    RST $00

;; Handles END: returns to READY.
ST_END:
    CALL ENDCHK
ST_NEW_2:
    JP RSTART

;; Handles RUN: clears the run state and runs from the given line, or from the first.
ST_RUN:
    CALL LINENUM_ENDCHK
    CALL CLEAR_RUN_STATE            ; forget STOP, GOSUB, FOR and READ state
    JR ST_RUN_2

;; Runs the line after the one at DE, or returns to READY at the end of the program.
RUNNXL:
    LD HL,START                     ; line 0: the first line at or after DE
ST_RUN_2:
    CALL FNDLP                      ; find the line to run
    JR C,ST_NEW_2                   ; past the last line: READY
ST_RUN_3:
    LD [CURRNT],DE                  ; the current line
    INC DE                          ; skip the line number to the text
    INC DE
ST_RUN_4:
    CALL KBD_SCAN                   ; check for a key between statements
    CP $03                          ; BREAK?
    JR Z,ST_STOP
    CALL CASSETTE_OFF
    LD IX,$40F4                     ; empty the FP stack
    LD HL,TABLE1_PROGRAM - 1        ; TABLE1 from NEXT: LIST, RUN, NEW and the like are direct only
    JR EXEC

;; Handles GOTO: runs from the given line, HOW? if there is no such line.
ST_GOTO:
    CALL READ_LINENUM
    PUSH DE                         ; keep the text pointer for an error
ST_GOTO_1:
    CALL FNDLN
    JP NZ,AHOW_1                    ; no such line: HOW?
    POP AF                          ; drop the saved text pointer
    JR ST_RUN_3

;; Handles STOP and BREAK: prints BREAK AT and the line number on the screen, keeping the place for CONT.
ST_STOP:
    LD [STOPPT],DE                  ; where CONT resumes
    CALL SCREEN_CRLF
    LD DE,BREAK_MSG
    CALL PRTSTG
    LD HL,[CURRNT]                  ; the stopped line
    LD [STOPLN],HL                  ; also kept for CONT
    LD E,[HL]                       ; DE = its line number
    INC HL
    LD D,[HL]
    LD HL,START                     ; no current line: back in direct mode
    LD [CURRNT],HL
    EX DE,HL
    CALL PRTNUM
    LD A,$0D
    RST $10
ST_STOP_1:
    JP RSTART_2                     ; read lines without READY, keeping CONT's state

;; Handles CONT: resumes after the last STOP or BREAK, or returns to READY if there is none.
ST_CONT:
    CALL ENDCHK
    LD HL,[STOPPT]                  ; the resume point saved by STOP
    LD A,H
    OR L
    JR Z,ST_NEW_2                   ; nothing to continue
    EX DE,HL
    LD HL,[STOPLN]                  ; the line that was stopped
    LD [CURRNT],HL
    CALL FIN                        ; at a statement end, move on to the next one
ST_CONT_1:
    JR ST_RUN_4

;; Handles LLIST: lists on the printer.
ST_LLIST:
    LD A,$01
    LD [LPRINTING],A

;; Handles LIST: lists from the given line, pausing while a key is held, until BREAK or the end.
ST_LIST:
    CALL LINENUM_ENDCHK             ; the first line to list, or 0
    CALL FNDLN
    JR C,ST_LIST_4                  ; past the end of the program
ST_LIST_1:
    CALL PRTLN
    CALL KBD_SCAN
    JR Z,ST_LIST_3                  ; no key: on to the next line
    CP $03                          ; BREAK stops the listing
    JR Z,ST_LIST_4
ST_LIST_2:
    CALL KBD_SCAN                   ; any other key pauses until the next
    JR Z,ST_LIST_2
    CP $03
    JR Z,ST_LIST_4
ST_LIST_3:
    CALL FNDLP
    JR NC,ST_LIST_1
ST_LIST_4:
    JR ST_STOP_1

;; Handles LPRINT: prints on the printer.
ST_LPRINT:
    LD A,$01
    JR ST_PRINT_1

;; Handles PRINT; after PRINT # the output goes to tape.
ST_PRINT:
    XOR A                           ; the screen
ST_PRINT_1:
    LD [LPRINTING],A
    TSTC '#', PRINT_COLON
    LD HL,$40AC                     ; output collects in the buffer until a CR writes it
    LD [INPPTR],HL                  ; the tape line buffer pointer
    CALL CASSETTE_ON                ; output goes to tape while the motor runs

.endif
;; Checks for a colon: prints a new line and runs the next statement.
PRINT_COLON:
    TSTC ':', PRINT_ENTER
    CALL CRLF
    JR ST_CONT_1                    ; run the next statement
;; Checks for the end of the line: prints a new line and runs the next line.
PRINT_ENTER:
    TSTC $0D, PRINT_NEXT_ITEM
    CALL CRLF
    JP RUNNXL                       ; run the next line
;; Looks the next item up in TABLE6: TAB, AT, A$, B$, or else a string or expression.
PRINT_NEXT_ITEM:
    LD HL,TABLE6 - 1                ; one before TABLE6, as EXEC steps first
    JP EXEC
;; Prints a quoted string, or else evaluates and prints an expression.
PRINT_ITEM:
    CALL QTSTG
    JR PRINT_AT_5                   ; no string: an expression
    JR PRINT_BSTRING_2              ; string printed: look for a separator
;; Prints the string A$.
PRINT_ASTRING:
    LD HL,$4070                     ; the A$ buffer
    JR PRINT_BSTRING_1
;; Prints the string B$.
PRINT_BSTRING:
    LD HL,$4080                     ; the B$ buffer
PRINT_BSTRING_1:
    CALL PRINT_STRVAR
PRINT_BSTRING_2:
    TSTC ',', PRINT_AT_2            ; no comma: check for a semicolon
PRINT_BSTRING_3:
    LD A,[CURSOR]                   ; the cursor's column within its 16-column zone
    AND $0F
    JR Z,PRINT_AT_3                 ; at a zone start: next item
    LD A,$20                        ; pad with spaces to the next zone
    RST $10
    JR PRINT_BSTRING_3
PRINT_AT:
    CALL EXPR_INT                   ; the screen position, 0 to 1023
    LD BC,[CURSOR]                  ; erase the cursor at the old position
    LD A,$20
    LD [BC],A
    LD A,H                          ; map the position into video memory, $3C00-$3FFF
    OR $FC
    AND $3F
    LD H,A
    LD [HL],$5F                     ; draw the cursor at the new position
    LD [CURSOR],HL                  ; the new cursor position
PRINT_AT_1:
    TSTC ',', PRINT_AT_2
    JR PRINT_AT_3
PRINT_AT_2:
    TSTC ';', PRINT_AT_4
PRINT_AT_3:
    CALL FIN                        ; a statement end here means no new line
    JR PRINT_NEXT_ITEM
PRINT_AT_4:
    CALL CRLF                       ; no separator: end the line, and the statement must end
    RST $30
PRINT_AT_5:
    EVALUATE                        ; evaluate the expression
    CALL FP_PRINT
    JR PRINT_BSTRING_2
PRINT_TAB:
    CALL PARN_INT                   ; the column to move to
    LD A,L
    AND $3F                         ; columns 0-63
    LD L,A
PRINT_TAB_1:
    LD A,[CURSOR]                   ; the cursor's column
    AND $3F
    CP L
    JR Z,PRINT_AT_1
    JR NC,PRINT_AT_1                ; already at or past it
    LD A,$20                        ; one more space
    RST $10
    JR PRINT_TAB_1
ST_CLS:
    LD A,$0C                        ; clear the screen
    RST $10
    RST $30

;; Prints the string variable at HL, stopping at a zero byte or at the end of its 16 bytes.
;; In: HL = the string's buffer
PRINT_STRVAR:
    LD A,[HL]
    INC HL
    AND A                           ; a zero byte ends the string
    RET Z
    RST $10
    LD A,L                          ; the end of the 16-byte buffer also ends it
    AND $0F
    RET Z
    JR PRINT_STRVAR
ST_GOSUB:
    CALL PUSHA                      ; save the FOR state of the caller
    CALL READ_LINENUM
ST_GOSUB_1:
    PUSH DE                         ; keep the text pointer to return to
    CALL FNDLN
    JP NZ,AHOW_1                    ; no such line: HOW?
    LD HL,[CURRNT]                  ; save the current line for RETURN
    PUSH HL
    LD HL,[STKGOS]                  ; and the previous GOSUB frame
    PUSH HL
    LD HL,START                     ; no active FOR loop inside the subroutine
    LD [LOPVAR],HL
    ADD HL,SP                       ; HL = SP: this frame
    LD [STKGOS],HL
    JP ST_RUN_3
ST_RETURN:
    CALL ENDCHK
    LD HL,[STKGOS]                  ; the latest GOSUB frame
    LD A,H
    OR L
    JP Z,QWHAT                      ; RETURN without GOSUB
    LD SP,HL                        ; drop anything left above the frame
    POP HL                          ; the previous GOSUB frame
    LD [STKGOS],HL
    POP HL                          ; the calling line
    LD [CURRNT],HL
    POP DE                          ; DE = the text after the GOSUB
    JP ST_NEXT_5                    ; restore the caller's FOR state and finish
ST_ON:
    CALL EXPR_UINT                  ; N, HOW? if negative
    LD A,H
    OR L
    JR Z,ST_ON_1                    ; ON 0 does nothing
    PUSH HL                         ; keep N for ON_SELECT
    LD HL,TABLE2 - 1                ; one before TABLE2: GOTO or GOSUB
    JR ST_FOR_1
ST_ON_1:
    CALL SKIP_STATEMENT             ; skip the rest of the ON statement
    RST $30
ON_GOTO:
    POP HL                          ; HL = N
    CALL ON_SELECT                  ; HL = the Nth line number
ON_GOTO_1:
    PUSH DE                         ; text pointer for ST_GOTO_1 to drop
    JP ST_GOTO_1
ON_GOSUB:
    POP HL
    CALL ON_SELECT
    LD [SCRATCH],HL                 ; keep the line number across PUSHA
    CALL PUSHA
    LD HL,[SCRATCH]
    JR ST_GOSUB_1

;; Moves to the Nth line number in the list of an ON statement and evaluates it.
;; In: L = N, DE = the list
;; Out: HL = the line number
ON_SELECT:
    DEC L                           ; this item?
    JR Z,ON_SELECT_LINE

;; Skips one item of the list; at the statement's end ON goes on to the next statement.
ON_SKIP_ITEM:
    LD A,[DE]                       ; step through the list to the next comma
    CP $0D
    JR Z,ST_ON_1                    ; fewer than N items: on to the next statement
    CP $3A
    JR Z,ST_ON_1
    INC DE
    CP $2C
    JR Z,ON_SELECT                  ; past a comma: one item fewer to go
    JR ON_SKIP_ITEM

;; Evaluates the selected line number, then skips the rest of the statement.
ON_SELECT_LINE:
    CALL READ_LINENUM

;; Moves DE to the colon or carriage return that ends the statement.
;; Out: DE = the colon or carriage return, A = it
SKIP_STATEMENT:
    LD A,[DE]
    CP $3A
    RET Z
    CP $0D
    RET Z
    INC DE
    JR SKIP_STATEMENT
ST_FOR:
    CALL PUSHA                      ; save the enclosing loop's state
    CALL SETVAL                     ; assign the start value
    LD [LOPVAR],HL                  ; the loop variable
    LD HL,TABLE4 - 1                ; one before TABLE4: TO
ST_FOR_1:
    JP EXEC
FOR_TO:
    CALL EXPR_INT                   ; the limit
    LD [LOPLMT],HL
    LD HL,TABLE5 - 1                ; one before TABLE5: STEP
    JR ST_FOR_1
FOR_STEP:
    CALL EXPR_INT
    JR FOR_NO_STEP_1
FOR_NO_STEP:
    LD HL,$0001                     ; STEP 1 when there is none
FOR_NO_STEP_1:
    LD [LOPINC],HL                  ; the step
    LD HL,[CURRNT]                  ; the loop's line, to go back to
    LD [LOPLN],HL
    EX DE,HL                        ; HL = the text after the FOR statement
    LD [LOPPT],HL                   ; where NEXT goes back to
    LD BC,$000A                     ; ten bytes per saved FOR frame
    LD HL,[LOPVAR]                  ; DE = the loop variable
    EX DE,HL
    LD H,B                          ; HL = SP: search the frames for one of this variable
    LD L,B
    ADD HL,SP
    .byte $3E
FOR_NO_STEP_2:
    .byte $09
    LD A,[HL]                       ; a frame's variable zero: no older loop for it
    INC HL
    OR [HL]
    JR Z,FOR_NO_STEP_3
    LD A,[HL]                       ; same variable as this loop?
    DEC HL
    CP D
    JR NZ,FOR_NO_STEP_2
    LD A,[HL]
    CP E
    JR NZ,FOR_NO_STEP_2
    EX DE,HL                        ; remove the old loop's frame
    LD HL,START                     ; BC = the stack top
    ADD HL,SP
    LD B,H
    LD C,L
    LD HL,$000A                     ; HL = the end of the frame
    ADD HL,DE
    CALL MVDOWN                     ; move what lies above it up over it
    LD SP,HL                        ; the stack is ten bytes shorter
FOR_NO_STEP_3:
    LD HL,[LOPPT]                   ; go on after the FOR statement
    EX DE,HL
    RST $30
ST_NEXT:
    RST $38
    JP C,QWHAT                      ; NEXT needs a variable
    LD [SCRATCH],HL                 ; keep the variable named by NEXT
ST_NEXT_1:
    PUSH DE
    EX DE,HL
    LD HL,[LOPVAR]                  ; the innermost loop's variable
    LD A,H
    OR L
    JP Z,QWHAT_1                    ; NEXT without FOR
    RST $20                         ; the same variable?
    JR Z,ST_NEXT_2
    POP DE
    CALL POPA                       ; no: drop the inner loop and try the outer one
    LD HL,[SCRATCH]
    JR ST_NEXT_1
ST_NEXT_2:
    CALL FP_PUSH_VAR                ; the variable's value as an integer
    CALL FP_TO_INT
    EX DE,HL
    LD HL,[LOPINC]                  ; add the step
    PUSH HL                         ; keep the step for its sign
    ADD HL,DE
    PUSH HL                         ; keep the new value
    CALL FP_PUSH_INT                ; store the new value in the variable
    LD HL,[LOPVAR]
    CALL FP_POP_VAR
    POP DE                          ; DE = the new value
    LD HL,[LOPLMT]                  ; HL = the limit
    POP AF                          ; A = the step's high byte
    OR A
    JP P,ST_NEXT_3                  ; positive step: done when the value passes the limit
    EX DE,HL                        ; negative step: compare the other way
ST_NEXT_3:
    LD A,H                          ; same sign? an unsigned compare works
    XOR D
    JP P,ST_NEXT_4
    EX DE,HL                        ; signs differ: swap to fix the compare
ST_NEXT_4:
    RST $20
    POP DE                          ; restore the text pointer
    JR C,ST_NEXT_5                  ; past the limit: the loop is over
    LD HL,[LOPLN]                   ; loop again from the FOR line
    LD [CURRNT],HL
    JR FOR_NO_STEP_3
ST_NEXT_5:
    CALL POPA                       ; restore the enclosing loop and finish
    RST $30
;; Handles REM and DATA by going on to the next line.
ST_REM:
    LD HL,START                     ; a false condition skips the line
    JR ST_IF_1
;; Handles IF: when the condition is zero, skips to the next line.
ST_IF:
    CALL EXPR_INT
ST_IF_1:
    LD A,H
    OR L
    JR NZ,IF_TRUE                   ; nonzero is true
    CALL FNDSKP                     ; find the next line
    JP NC,ST_RUN_3                  ; run it, or READY at the program's end
    JP RSTART
;; Continues a true IF by looking for THEN in TABLE8.
IF_TRUE:
    LD HL,TABLE8 - 1                ; one before TABLE8: THEN
    JP EXEC
;; Handles THEN: a line number after it works as GOTO, otherwise the statement after it runs.
IF_THEN:
    CALL TSTNUM                     ; a line number after THEN?
    JP NZ,ON_GOTO_1                 ; yes: GOTO it
IF_NO_THEN:
    JP ST_RUN_4                     ; run the statement after IF or THEN
;; Recovers from bad input: restores the stack and current line saved by INPUT, then asks
;; again.
INPERR:
    LD SP,[SCRATCH]                 ; the stack as INPUT left it
    POP HL
    LD [CURRNT],HL                  ; the INPUT line
    POP DE                          ; DE = the INPUT statement, to try it again
;; Handles INPUT; after INPUT # the values come from tape.
ST_INPUT:
    TSTC '#', INPUT_KEYBOARD
    CALL TAPE_READ_BLOCK            ; read a tape block into the input buffer
    PUSH DE                         ; stack as for a keyboard INPUT
    LD HL,[CURRNT]
    PUSH HL
    JR ST_INPUT_3
;; Reads INPUT from the keyboard: prints any quoted prompt, then reads a line after a
;; question mark.
INPUT_KEYBOARD:
    PUSH DE                         ; the statement start, for INPERR
    CALL QTSTG
    JR ST_INPUT_2                   ; no prompt string
    .byte $CF, $3B, $18
ST_INPUT_2:
    LD HL,[CURRNT]                  ; keep the real current line
    PUSH HL
    LD HL,INPUT_KEYBOARD            ; a fake current line: its first bytes read as a negative number
    LD [CURRNT],HL                  ; so ERROR knows the input was bad and retries
    LD [SCRATCH],SP                 ; the stack for INPERR to restore
    PUSH DE
    LD A,$3F                        ; the ? prompt
    CALL GETLN_PROMPT
    POP DE
ST_INPUT_3:
    JP INPUT_VARS
    .byte $F1, $18, $76

;; Stores the value at DE in the variable at HL: a number by evaluating it, a string by
;; copying it into the 16-byte buffer.
;; In: HL = the variable, zero = numeric, DE = the value
STORE_VALUE:
    JP Z,SETVAL_EXPR                ; a numeric variable: evaluate
    RST IGNBLK_RST                  ; skip leading spaces

;; Copies unquoted text up to a comma, quote or carriage return.
STORE_STR_COPY:
    LD A,[DE]
    CP $0D
    JR Z,STORE_STR_PAD              ; carriage return ends the string
    CP $22
    JR Z,STORE_STR_QUOTE            ; a quote starts quoted text
    CP $2C
    JR Z,STORE_STR_PAD              ; a comma ends the item
    LD [HL],A
    INC HL
    INC DE
    LD A,L                          ; at the end of the 16-byte buffer?
    AND $0F
    JR Z,STORE_STR_SKIP             ; full: skip what is left
    JR STORE_STR_COPY

;; Fills the rest of the string's 16-byte buffer with zero bytes.
STORE_STR_PAD:
    LD [HL],$00
    INC HL
    LD A,L                          ; until the buffer's end
    AND $0F
    JR NZ,STORE_STR_PAD
    RET

;; Steps past the opening quote of a quoted string.
STORE_STR_QUOTE:
    INC DE

;; Copies quoted text up to the closing quote or a carriage return.
STORE_STR_QCOPY:
    LD A,[DE]
    CP $0D
    JR Z,STORE_STR_PAD              ; carriage return ends the string
    INC DE
    CP $22
    JR Z,STORE_STR_PAD              ; closing quote ends the string
    LD [HL],A
    INC HL
    LD A,L                          ; until the buffer's end
    AND $0F
    JR NZ,STORE_STR_QCOPY

;; Skips text that did not fit, up to a comma or carriage return.
STORE_STR_SKIP:
    LD A,[DE]
    CP $2C
    RET Z
    CP $0D
    RET Z
    INC DE
    JR STORE_STR_SKIP

;; Tests for a variable at DE, including the strings A$ and B$.
;; Out: HL = its address, zero = numeric (clear for a string), carry = no variable
TSTV_STR:
    RST $38
    RET C
    DEC DE                          ; look at the character before
    LD A,[DE]
    INC DE
    CP $29                          ; an A(n) element: always numeric
    RET Z
    LD A,[DE]
    CP $24                          ; a $ after the letter makes it a string
    JR Z,TSTV_STR_NAME
    XOR A                           ; Z: numeric
    RET

;; Gives the buffer of A$ or B$, WHAT? for any other string name.
TSTV_STR_NAME:
    LD A,L                          ; four times the letter number
    CP $07                          ; only A$ and B$ exist
    JP NC,QWHAT
    INC DE                          ; step past the $
    SLA A                           ; A$ at $4070, B$ at $4080
    SLA A
    ADD A,$70
    LD L,A
    AND A                           ; NZ: a string
    RET
;; Handles a statement with no keyword as LET; an empty statement does nothing.
IMPLIED_LET:
    LD A,[DE]
    CP $0D                          ; an empty statement
    JR Z,ST_LET_1
;; Handles LET: assigns a number, or a string to A$ or B$.
ST_LET:
    CALL TSTV_STR
    JR C,ST_LET_3                   ; no variable: WHAT?
    PUSH AF                         ; keep its type
    TSTC '=', ST_LET_3
    POP AF                          ; restore the type
    CALL STORE_VALUE
ST_LET_1:
    RST $30
;; Restores the current line saved by INPUT, then reports WHAT?.
INPUT_BAD_VAR:
    POP HL
    LD [CURRNT],HL
ST_LET_3:
    JP QWHAT
;; Handles RESTORE: makes the next READ start from the first DATA statement.
ST_RESTORE:
    LD HL,START                     ; no DATA pointer: READ starts over
    LD [DATAPTR],HL
    RST $30
;; Assigns the values in the input buffer at $40AC to the variables listed at DE.
INPUT_VARS:
    CALL TSTV_STR
    JR C,INPUT_BAD_VAR              ; not a variable: restore and WHAT?
    PUSH DE                         ; keep the position in the INPUT list
    LD DE,$40AC                     ; values come from the input buffer
ST_RESTORE_2:
    CALL STORE_VALUE
    LD [INPPTR],DE                  ; keep the position in the input
    POP DE
    TSTC ',', INPUT_DONE            ; no comma: the last variable
    CALL TSTV_STR
    JR C,INPUT_BAD_VAR
    PUSH DE
    PUSH AF                         ; keep the next variable's type
    LD DE,[INPPTR]                  ; back to the input
    TSTC ',', INPUT_MISSING         ; no comma there: too few values
    POP AF
    JR ST_RESTORE_2
;; Handles READ: assigns the next DATA items to the listed variables.
ST_READ:
    CALL TSTV_STR
    PUSH DE                         ; keep the position in the READ list
    JR C,ST_READ_7                  ; not a variable: WHAT?
    PUSH AF                         ; keep its type
    LD DE,[DATAPTR]                 ; where the next DATA item is
    LD A,D
    OR E
    JR NZ,ST_READ_2                 ; zero: find the first DATA statement
    LD DE,$4200                     ; search from the program's start
    PUSH HL
    CALL FIND_DATA
    POP HL
    JR C,READ_NO_DATA               ; no DATA in the program
ST_READ_1:
    POP AF
    LD BC,[CURRNT]                  ; keep the current line
    PUSH BC
    LD BC,START                     ; no current line while the DATA item is read
    LD [CURRNT],BC
    CALL STORE_VALUE
    POP BC
    LD [CURRNT],BC                  ; the READ line again
    LD [DATAPTR],DE                 ; where the next item will be
    POP DE                          ; back to the READ list
    TSTC ',', ST_READ_5             ; no comma: READ is done
    JR ST_READ
ST_READ_2:
    TSTC ',', ST_READ_3             ; more items on this DATA line?
    JR ST_READ_1
ST_READ_3:
    .byte $CF, $0D, $08, $18, $D0
;; Ends INPUT at the last variable: restores the current line and finishes the statement.
INPUT_DONE:
    POP HL                          ; the current line saved by INPUT
    LD [CURRNT],HL
    POP AF                          ; drop the saved statement start
ST_READ_5:
    RST $30
;; Reports WHAT? when the input holds fewer values than INPUT has variables.
INPUT_MISSING:
    POP AF
ST_READ_7:
    JP QWHAT_1
;; Reports HOW? when no DATA statement is left to read.
READ_NO_DATA:
    POP AF
    JP AHOW_1
;; The DATA table's match: a DATA statement found.
;; Out: carry = clear
DATA_FOUND:
    XOR A
    RET
;; Skips the rest of a line that does not start with DATA, then searches on.
DATA_SKIP_LINE:
    LD A,[DE]
    INC DE
    CP $0D                          ; carriage return ends the line
    JR NZ,DATA_SKIP_LINE

;; Searches from the line at DE for a line starting with DATA.
;; Out: DE = past the word DATA, carry = the program ended first
FIND_DATA:
    INC DE                          ; skip the line number
    INC DE
    LD HL,[TXTUNF]                  ; past the end of the program?
    RST $20
    RET C
    LD HL,DATA_TABLE - 1            ; one before the DATA table, as EXEC steps first
    JR EXEC_JUMP

.if MODEL = 3
;; Evaluates the expression at DE onto the FP stack, as EVALUATE calls it, then EXPR_RELOP.
EXPR:
    CALL EXPR2
.endif

;; Finishes EXPR: applies a relational operator if one follows, pushing 1 or 0.
EXPR_RELOP:
    CALL REL_LOOKUP                 ; HL = 1 or 0 when an operator follows
.if MODEL = 3
    LD H,$00                        ; the operators set only L
.endif
    JP FP_PUSH_INT                  ; push the truth value

;; Handles > and >=, leaving 1 when true and 0 when false.
REL_GREATER:
    TSTC '=', REL_GT                ; no = after >: plain >
    CALL REL_COMPARE
    RET C                           ; left less: false
    JR REL_TRUE

;; Handles > alone: true when the left value is the larger.
REL_GT:
    CALL REL_COMPARE
    RET Z                           ; equal or less: false
    RET C
    JR REL_TRUE

;; Handles <, <= and <>, leaving 1 when true and 0 when false.
REL_LESS:
    TSTC '=', REL_LT_OR_NE          ; no = after <: < or <>
    CALL REL_COMPARE
.if MODEL = 1
    LD HL,$0001                     ; true when equal or less
    RET Z
    RET C
    LD HL,START                     ; greater: false
.else
    LD L,$01                        ; true when equal or less
    RET Z
    RET C
    DEC L                           ; greater: false
.endif
    RET

;; Handles < without =: <> is not equal, otherwise less than.
REL_LT_OR_NE:
    TSTC '>', REL_LT
    CALL REL_COMPARE
    RET Z                           ; equal: false
    JR REL_TRUE

;; Handles =, leaving 1 when the values are equal and 0 otherwise.
REL_EQUAL:
    CALL REL_COMPARE
    RET NZ                          ; unequal: false
    JR REL_TRUE

;; Handles < alone: true when the left value is the smaller.
REL_LT:
    CALL REL_COMPARE
    RET NC                          ; equal or greater: false
    JR REL_TRUE

;; Returns from EXPR when no relational operator follows, leaving the value as it is.
REL_NONE:
    POP AF                          ; drop the return to EXPR_RELOP, so nothing is pushed
    RET

;; Evaluates the right side and compares it with the left, popping both from the FP stack.
;; Out: HL = 0 (on the Model III, L), zero = equal, carry = the left value is less
REL_COMPARE:
    CALL EXPR2                      ; the right side
    CALL FP_COMPARE
.if MODEL = 1
    LD HL,START                     ; false unless the caller changes it
.else
    LD L,$00
.endif
    RET

;; Returns 1, true: in HL, or on the Model III in L.
REL_TRUE:
.if MODEL = 1
    LD HL,$0001
.else
    LD L,$01
.endif
    RET

;; Looks for a relational operator in TABLE7.
REL_LOOKUP:
    LD HL,TABLE7 - 1                ; one before TABLE7

;; Jumps to EXEC to look the word at DE up in the table at HL.
EXEC_JUMP:
    JP EXEC

;; Evaluates a sum or difference of terms at DE, with an optional leading sign, onto the FP
;; stack.
EXPR2:
    TSTC '-', XP21                  ; a leading minus is 0 minus the first term
    LD HL,START
    CALL FP_PUSH_INT
    JR XP26

;; Steps past a leading plus sign.
XP21:
    TSTC '+', XP22                  ; a leading plus is ignored

;; Evaluates the first term.
XP22:
    CALL EXPR3

;; Adds the next term while a plus sign follows.
XP23:
    TSTC '+', XP25
    CALL EXPR3
    CALL FP_ADD
    JR XP23

;; Checks for a minus sign; anything else ends the sum.
XP25:
    TSTC '-', XP42

;; Evaluates a term and subtracts it from the value so far.
XP26:
    CALL EXPR3
    CALL FP_SUB
    JR XP23

;; Evaluates a product or quotient of factors at DE onto the FP stack.
EXPR3:
    CALL EXPR4

;; Multiplies by the next factor while an asterisk follows.
XP31:
    TSTC '*', XP34
    CALL EXPR4
    CALL FP_MUL
    JR XP31

;; Divides by the next factor after a slash; anything else ends the product.
XP34:
    TSTC '/', XP42
    CALL EXPR4
    CALL FP_DIV
    JR XP31

;; Evaluates a factor at DE, first looking for a function name in TABLE3.
EXPR4:
    LD HL,TABLE3 - 1                ; one before TABLE3
    JR EXEC_JUMP
;; Evaluates a factor that is not a function: a variable, a constant, or an expression in
;; parentheses.
NOT_FUNCTION:
    RST $38
    JR C,XP41                       ; not a variable
    JP FP_PUSH_VAR
;; Reads a numeric constant; when there is none, falls into PARN.
XP41:
    CALL FP_PARSE_CONST
    RET NZ                          ; a constant was read

;; Evaluates an expression in parentheses at DE, WHAT? when a parenthesis is missing.
PARN:
    TSTC '(', XP43
    EVALUATE                        ; the expression inside
    TSTC ')', XP43

;; Returns to the caller.
XP42:
    RET

;; Jumps to QWHAT.
XP43:
    JP QWHAT

;; Evaluates the expression at DE as an integer.
;; Out: HL = the integer
EXPR_INT:
    EVALUATE

;; Pops the value on the FP stack as an integer.
;; Out: HL = the integer
EXPR_INT_CONV:
    JP FP_TO_INT

;; Evaluates the expression at DE as an integer, HOW? when it is negative.
;; Out: HL = the integer
EXPR_UINT:
    CALL EXPR_INT
    BIT 7,H                         ; negative?
    JP NZ,AHOW
    RET

;; Evaluates an expression in parentheses at DE as an integer.
;; Out: HL = the integer
PARN_INT:
    CALL PARN
    JR EXPR_INT_CONV
;; Handles ABS(): clears the sign of the value on the FP stack.
FN_ABS:
    CALL PARN
    RES 7,[IX-$01]                  ; the sign bit of the top FP value
    RET
;; Handles MEM: pushes the number of bytes free between the program and the top of memory.
FN_MEM:
    PUSH DE
    LD DE,[TXTUNF]                  ; free bytes = top of memory minus end of program
    LD HL,[MEMTOP]
    XOR A
    SBC HL,DE
    POP DE
    JR FN_INT_1
;; Handles INT(): replaces the value with its integer part, rounded down.
FN_INT:
    CALL PARN
    CALL EXPR_INT_CONV
FN_INT_1:
    JP FP_PUSH_INT
;; Handles RESET(x,y): turns that graphics block off.
ST_RESET:
    LD A,$80                        ; RESET: clear the bit
    JR GRAPHICS
;; Handles SET(x,y): turns that graphics block on.
ST_SET:
    LD A,$01                        ; SET: set the bit
    JR GRAPHICS
;; Handles POINT(x,y): pushes 1 when that graphics block is on, otherwise 0.
FN_POINT:
    LD A,$00                        ; POINT: test the bit
;; Parses (x,y), finds that graphics block on the screen, and sets, resets or tests it.
;; In: A = 1 for SET, $80 for RESET, 0 for POINT
GRAPHICS:
    AND A                           ; flags tell the three apart: Z POINT, P SET, M RESET
    PUSH AF
    TSTC '(', FN_POINT_6
    CALL EXPR_UINT                  ; x
    PUSH HL                         ; keep x
    TSTC ',', FN_POINT_6
    CALL EXPR_UINT                  ; y
    TSTC ')', FN_POINT_6
    LD BC,FINISH                    ; 48 rows: FINISH is $0030, used as a constant
    AND A
FN_POINT_2:
    SBC HL,BC                       ; reduce y modulo 48
    JR NC,FN_POINT_2
    ADD HL,BC
    LD A,L                          ; A = y
    LD H,$FF                        ; H = the text row, y divided by 3
FN_POINT_3:
    INC H
    SUB $03
    JR NC,FN_POINT_3
    ADD A,$03                       ; A = y modulo 3, the block's row within the character
    POP BC                          ; C = x
    LD B,H                          ; BC = row times 64 plus x divided by 2
    SLA C
    RR B
    RR C
    RR B
    RR C
    RLA                             ; A = the bit number: two per row, plus x's low bit
    INC A
    SCF                             ; H = 1 shifted left by the bit number
    LD H,$00
FN_POINT_4:
    RL H
    DEC A
    JR NZ,FN_POINT_4
    LD A,B                          ; keep the address in video memory
    OR $FC
    AND $3F
    LD B,A
    LD A,[BC]
    BIT 7,A                         ; already a graphics character?
    JR NZ,FN_POINT_5
    LD A,$80                        ; no: make it a blank graphics character
    LD [BC],A
FN_POINT_5:
    POP AF                          ; recover which statement this is
    LD A,[BC]
    JR Z,POINT_RESULT
    JP P,SET_BLOCK                  ; SET
    LD A,H                          ; RESET: clear the block's bit
    CPL
    LD H,A
    LD A,[BC]
    AND H
    LD [BC],A
    RST $30
FN_POINT_6:
    JR QWHAT
;; Pushes 1 when the block's bit is set, otherwise 0.
POINT_RESULT:
    AND H
    LD HL,START                     ; 0 when the block is off
    JR Z,FN_POINT_8
    INC L                           ; 1 when it is on
FN_POINT_8:
    JP FP_PUSH_INT
;; Sets the block's bit on the screen and ends the statement.
SET_BLOCK:
    OR H
    LD [BC],A
    RST $30

;; Parses a variable and an equals sign at DE, then evaluates and stores the expression.
;; Out: HL = the variable's address
SETVAL:
    RST $38
    JR C,QWHAT                      ; no variable: WHAT?
    TSTC '=', QWHAT

;; Evaluates the expression at DE and stores it in the variable at HL.
;; In: HL = the variable
SETVAL_EXPR:
    PUSH HL                         ; the variable, for FP_STORE_PUSHED
    EVALUATE
    JP FP_STORE_PUSHED

;; Ends a statement at a colon or carriage return by running the next statement or line;
;; otherwise returns.
FIN:
    TSTC ':', FI1
    POP AF                          ; drop the caller's return
    JP ST_RUN_4                     ; run the next statement

;; Checks for a carriage return, going on to the next line.
FI1:
    TSTC $0D, FI2
    POP AF                          ; drop the caller's return
    JP RUNNXL                       ; run the next line

;; Returns when the statement does not end here.
FI2:
    RET

;; Reads an optional line number, then requires the end of the line.
;; Out: HL = the number, or 0
LINENUM_ENDCHK:
    CALL TSTNUM

;; Requires a carriage return as the next nonblank character at DE, WHAT? otherwise.
ENDCHK:
    RST IGNBLK_RST
    CP $0D
    RET Z

;; Reports WHAT?, saving DE for the error line display.
QWHAT:
    PUSH DE                         ; where the error is, for the display
QWHAT_1:
    LD DE,WHAT_MSG

;; Prints the message at DE and, while a program runs, the line it stopped at; then RSTART.
ERROR:
.if MODEL = 3
    XOR A                           ; errors print on the screen
    LD [LPRINTING],A
.endif
    CALL PRTSTG
    LD DE,[CURRNT]                  ; the current line
    LD A,D
    OR E
    JR Z,ERROR_1                    ; zero: a direct statement, no line to show
    INC DE                          ; the line number's high byte
    LD A,[DE]
    DEC DE
    OR A
    JP M,INPERR                     ; negative: the fake line of a bad INPUT, ask again
    POP HL                          ; HL = where the error was found
    LD A,[HL]
    PUSH AF                         ; save the character there
    SUB A
    LD [HL],A                       ; cut the line off at the error
    CALL PRTLN                      ; print the line up to the error
    DEC DE
    POP AF
    LD [DE],A                       ; put the character back
    LD A,$3F                        ; mark the error with a question mark
    RST $10
    SUB A                           ; then print the rest of the line
    CALL PRTSTG
ERROR_1:
    JP RSTART
;; Reports SORRY (out of memory), saving DE for the error line display.
QSORRY:
    PUSH DE                         ; where the error is, for the display
ERROR_3:
    LD DE,SORRY_MSG
    JR ERROR

;; Reads a line from the keyboard into the buffer at DE, with backspace, line delete and BREAK.
GETLN:
    LD A,$3E                        ; '>' is the command-line prompt

;; Prints the prompt character in A, then reads a line into the buffer at $40AC.
;; In: A = the prompt
;; Out: DE = past the carriage return
GETLN_PROMPT:
.if MODEL = 1
    RST $10
.else
    RST $28                         ; the prompt goes to the screen, ending any LPRINT
.endif
    LD DE,$40AC                     ; the line input buffer

;; Waits for a key and handles ENTER, backspace and BREAK; other control keys are ignored.
GETLN_KEY:
    CALL KBD_SCAN
    JR Z,GETLN_KEY                  ; no key yet: keep waiting
    CP $0D                          ; ENTER finishes the line
    JR Z,GETLN_STORE
    CP $1D                          ; $1D is backspace
    JR Z,GETLN_BACK
    CP $03                          ; BREAK abandons the line and goes back to READY
    JR Z,ERROR_1
    CP $20                          ; any other control code is ignored
    JR C,GETLN_KEY

;; Stores the character, returning at a carriage return; a full buffer drops the last one.
GETLN_STORE:
    LD [DE],A
    INC DE
    CP $0D                          ; the carriage return ends the line
    RET Z
    LD A,E
    CP $F3                          ; the buffer ends at $40F3
    JR NZ,GETLN_KEY
    LD A,$1D                        ; full: back the last character out on screen too
    RST $10

;; Removes the last character, or starts over when the buffer is empty.
GETLN_BACK:
    LD A,E
    CP $AC                          ; nothing typed yet: start over with a fresh prompt
    JR Z,GETLN
    DEC DE                          ; drop the last character
    JR GETLN_KEY

;; Searches the program from its start for line HL.
;; In: HL = the line number
;; Out: DE = that line or the next higher one, zero = found, carry = past the end
FNDLN:
    LD DE,$4200                     ; the program text starts at $4200

;; Searches from the line at DE for line HL; returns to READY when DE is below the program.
;; In: HL = the line number, DE = a line
;; Out: DE = that line or the next higher one, zero = found, carry = past the end
FNDLP:
    PUSH HL
    LD A,D
    CP $42                          ; an address below $4200 cannot be a program line
    JR C,ERROR_1
    LD HL,[TXTUNF]                  ; the end of the program text
    DEC HL
    RST $20                         ; past the program's last line?
    POP HL
    RET C                           ; past the end: return with C
    LD A,[DE]                       ; compare the line's number with HL, low byte first
    SUB L
    LD B,A
    INC DE
    LD A,[DE]
    SBC A,H
    JR C,FL2                        ; this line's number is lower: skip to the next
    DEC DE                          ; back to the line's start
    OR B                            ; Z only when both bytes of the number matched
    RET

;; Skips past the line at DE, then searches on for line HL.
FNDNXT:
    INC DE

;; Steps DE, then skips to the end of the line and searches on.
FL2:
    INC DE

;; Skips to the end of the line at DE, then searches on from the next line.
FNDSKP:
    LD A,[DE]
    CP $0D                          ; look for this line's carriage return
    JR NZ,FL2
    INC DE                          ; step to the next line's number
    JR FNDLP

;; Prints the string at DE through its carriage return.
PRTSTG:
    XOR A                           ; end only at a zero byte or the carriage return

;; Prints the string at DE up to the character in A, or through a carriage return.
;; In: A = the end character, DE = the string
;; Out: DE = past the last character read, A = it
PRTSTG_TERM:
    LD B,A

;; Prints one character per pass.
PS1:
    LD A,[DE]
    INC DE
    CP B
    RET Z                           ; the end character itself is not printed
    RST $10
    CP $0D                          ; the carriage return is printed and also ends it
    JR NZ,PS1
    RET

;; Prints a quoted string at DE; returns past the two-byte jump after the call when there is
;; one, or to that jump when there is not.
QTSTG:
    TSTC '"', QTSTG_NONE
    LD A,$22                        ; print up to the closing quote
    CALL PRTSTG_TERM
    CP $0D                          ; a line that ended before the closing quote
    POP HL                          ; the caller's return address, at its two-byte jump
    JP Z,RUNNXL                     ; the line ended: the statement is done, run the next line
    INC HL                          ; step past the caller's jump
    INC HL
    JP [HL]                         ; and continue after it

;; Returns when no quote follows.
QTSTG_NONE:
    RET

;; Prints the signed integer in HL as a decimal number.
;; In: HL = the number
PRTNUM:
    CALL FP_PUSH_INT

;; Prints and pops the number on the FP stack, in fixed or E notation, after a sign or space
;; and before a space.
FP_PRINT:
    PUSH DE
    PUSH BC
    PUSH HL
    LD A,[IX-$02]                   ; the exponent byte
    CP $80                          ; $80 means the value is zero
    JR NZ,FP_PRINT_SIGN
    LD A,$20                        ; zero prints as a space and a 0
    RST $10
    LD A,$30
    RST $10
    JP FP_PRINT_DONE

;; Picks a minus sign or a space for the sign.
FP_PRINT_SIGN:
    LD A,[IX-$01]                   ; the sign byte, nonzero for a negative number
    AND A
    LD A,$20
    JR Z,FP_PRINT_SIGN_OUT
    LD A,$2D                        ; a minus sign for a negative number

;; Prints the sign character, clears the sign and starts the power of ten at -1.
FP_PRINT_SIGN_OUT:
    RST $10
    XOR A                           ; from here on work with the magnitude
    LD [IX-$01],A
    LD A,$FF

;; Multiplies by ten, lowering the power, while the value is below the constant at $0EB9.
FP_PRINT_UP:
    PUSH AF                         ; keep the power of ten while scaling
    LD HL,$0EB9                     ; 0.1, the lower bound of the printing range
    CALL FP_CMP_CONST
    JR NC,FP_PRINT_DOWN             ; big enough: check against the upper bound
    CALL FP_MUL10
    POP AF
    DEC A
    JR FP_PRINT_UP

;; Divides by ten, raising the power, until the value is below the constant at $0EB5.
FP_PRINT_DOWN:
    LD HL,$0EB5                     ; 1.0, the upper bound of the printing range
    CALL FP_CMP_CONST
    JR C,FP_PRINT_ALIGN             ; in range: convert to digits
    CALL FP_DIV10
    POP AF
    INC A
    PUSH AF
    JR FP_PRINT_DOWN

;; Shifts the mantissa right by the binary exponent to make it a whole number.
FP_PRINT_ALIGN:
    LD A,[IX-$02]
    NEG                             ; a fraction below 1: shift by minus the exponent

;; Shifts the mantissa one bit per pass.
FP_PRINT_SHIFT:
    JR Z,FP_PRINT_DIGITS
    EXX                             ; the mantissa lives in the alternate registers C'H'L'
    SRL C
    RR H
    RR L
    EXX
    DEC A
    JR FP_PRINT_SHIFT

;; Converts the mantissa to seven decimal digits in the buffer at IX.
FP_PRINT_DIGITS:
    LD B,$07
    PUSH IX                         ; the digits go where the number sat on the FP stack
    POP HL
    LD [HL],$00                     ; a leading zero digit to absorb a rounding carry
    INC HL

;; Produces one digit per pass by multiplying by ten.
FP_PRINT_DIGIT:
    LD A,$00
    CALL MUL10                      ; times ten: the next digit overflows into B'
    EXX
    LD A,B                          ; the digit that came out of the top
    EXX
    LD [HL],A
    INC HL
    DJNZ FP_PRINT_DIGIT
    LD B,$06                        ; six digits are kept and rounded
    LD C,$00                        ; no nonzero digits seen yet
    DEC HL
    LD A,[HL]
    CP $05                          ; the seventh digit: 5 or more rounds up

;; Rounds the digits at the last one, carrying upward and noting the nonzero digits in C.
FP_PRINT_ROUND:
    CCF                             ; carry is now the carry into this digit
    LD A,$00
    DEC HL
    ADC A,[HL]                      ; add the carry to the digit
    SLA C                           ; make room for this digit's nonzero bit
    CP $0A                          ; ten means a carry into the next digit up
    JR C,FP_ROUND_STORE
    LD A,$00                        ; ten wraps to zero

;; Stores the rounded digit.
FP_ROUND_STORE:
    LD [HL],A
    PUSH AF                         ; keep the carry for the next digit
    AND A
    JR Z,FP_ROUND_NEXT
    SET 0,C                         ; note that this digit is nonzero

;; Moves on to the next digit up; a carry out of the top raises the power.
FP_ROUND_NEXT:
    POP AF
    DJNZ FP_PRINT_ROUND
    LD A,C                          ; the bits of the nonzero digits
    POP BC                          ; the power of ten back into B
    JR C,FP_PRINT_FORMAT            ; no carry out of the top digit
    INC B                           ; rounded up to a new leading digit: one more power of ten
    PUSH BC
    LD B,$01                        ; round once more, into the leading zero digit
    JR FP_PRINT_ROUND

;; Prints in fixed notation when the power of ten fits in six digits, otherwise in E
;; notation.
FP_PRINT_FORMAT:
    LD C,A                          ; the nonzero-digit bits, for PRINT_DIGITS
    LD A,B
    INC A                           ; the digits before the point
    JP M,FP_PRINT_EXP               ; a value below 0.1 goes to E notation
    CP $07                          ; seven or more digits before the point: E notation
    JR NC,FP_PRINT_EXP
    LD B,A
    CALL PRINT_DIGITS
    JR FP_PRINT_DONE

;; Prints the digits with one before the point, then E and the exponent's sign.
FP_PRINT_EXP:
    PUSH BC                         ; keep the power of ten for the exponent
    LD B,$01                        ; one digit before the point
    CALL PRINT_DIGITS
    LD A,$45                        ; 'E'
    RST $10
    POP BC
    BIT 7,B                         ; negative exponent?
    LD A,$2B                        ; '+'
    JR Z,FP_PRINT_EXP_PLUS
    LD A,$2D                        ; '-'
    RST $10
    LD A,B                          ; print the exponent's magnitude
    NEG
    JR FP_PRINT_EXP_VAL

;; Prints a plus sign for a positive exponent.
FP_PRINT_EXP_PLUS:
    RST $10
    LD A,B

;; Splits the exponent into its tens and units.
FP_PRINT_EXP_VAL:
    LD B,$00

;; Counts the tens, one per pass.
FP_PRINT_EXP_TENS:
    CP $0A
    JR C,FP_PRINT_EXP_DIG
    ADD A,$F6                       ; subtract ten
    INC B
    JR FP_PRINT_EXP_TENS

;; Prints the exponent's two digits.
FP_PRINT_EXP_DIG:
    OR $30                          ; units digit as ASCII
    LD C,A                          ; hold it while the tens digit prints
    LD A,B
    OR $30
    RST $10
    LD A,C
    RST $10

;; Prints a space, pops the number and restores the registers.
FP_PRINT_DONE:
    LD A,$20
    RST $10
    POP HL
    POP BC
    POP DE
    LD BC,$FFFB                     ; drop the five-byte number from the FP stack
    ADD IX,BC
    RET

;; Prints the digits at HL with a decimal point after B of them, up to the last nonzero one;
;; pads with zeros up to the point.
;; In: HL = the digits, B = digits before the point, C = a bit per digit left
PRINT_DIGITS:
    INC B                           ; offset the decrement at the loop's top

;; Prints the decimal point when B reaches zero.
PRINT_DIGITS_LOOP:
    DEC B
    JR NZ,PRINT_DIGIT_ONE
    LD A,$2E                        ; '.'
    RST $10

;; Prints one digit, continuing while digits are left in C.
PRINT_DIGIT_ONE:
    LD A,[HL]
    OR $30
    RST $10
    INC HL
    SRL C                           ; stop after the last nonzero digit
    JR NZ,PRINT_DIGITS_LOOP
    DEC B
    DEC B
    RET M                           ; the point is printed or not needed: done
    INC B                           ; otherwise pad with zeros up to the point
    JR PRINT_DIGITS

;; Prints the program line at DE: its number, then its text through the carriage return.
;; In: DE = the line
;; Out: DE = past the line
PRTLN:
    LD A,[DE]                       ; the line number, low byte first
    LD L,A
    INC DE
    LD A,[DE]
    LD H,A
    INC DE
    CALL PRTNUM
    JP PRTSTG

;; Copies the bytes from DE up to HL to BC, ascending.
;; In: DE = the source, HL = the source's end, BC = the destination
MVUP:
    RST $20                         ; reached the source's end?
    RET Z
    LD A,[DE]
    LD [BC],A
    INC DE
    INC BC
    JR MVUP

;; Copies bytes downward, decrementing DE and HL, until DE reaches BC.
;; In: DE = the source's end, HL = the destination's end, BC = the source's start
MVDOWN:
    LD A,B
    SUB D
    JR NZ,MD1
    LD A,C
    SUB E
    RET Z                           ; DE has come down to BC: done

;; Copies one byte downward.
MD1:
    DEC DE
    DEC HL
    LD A,[DE]
    LD [HL],A
    JR MVDOWN

;; Restores the FOR loop state saved by PUSHA from the stack.
POPA:
    POP BC                          ; the caller's return address
    POP HL
    LD [LOPVAR],HL                  ; the loop variable, zero when no FOR loop was active
    LD A,H
    OR L
    JR Z,PP1                        ; no loop was active, so nothing else was saved
    POP HL
    LD [LOPINC],HL                  ; the loop's STEP
    POP HL
    LD [LOPLMT],HL                  ; the loop's limit
    POP HL
    LD [LOPLN],HL                   ; the line holding the FOR
    POP HL
    LD [LOPPT],HL                   ; the text position after the FOR statement

;; Returns to the caller with its return address back on the stack.
PP1:
    PUSH BC                         ; the return address back on top
    RET

;; Saves the FOR loop state on the stack, SORRY if the stack would drop below $4180.
PUSHA:
    LD HL,$4180                     ; the lowest address the stack may reach
    LD A,H                          ; negate $4180
    CPL
    LD H,A
    LD A,L
    CPL
    LD L,A
    INC HL
    POP BC                          ; the caller's return address
    ADD HL,SP                       ; SP less $4180, carry when SP is above it
    JP NC,QSORRY                    ; one more loop's state would not fit: SORRY
    LD HL,[LOPVAR]
    LD A,H
    OR L
    JR Z,PU1                        ; no active loop: save only its zero variable
    LD HL,[LOPPT]                   ; the text position after the FOR
    PUSH HL
    LD HL,[LOPLN]                   ; the FOR's line
    PUSH HL
    LD HL,[LOPLMT]                  ; the limit
    PUSH HL
    LD HL,[LOPINC]                  ; the STEP
    PUSH HL
    LD HL,[LOPVAR]

;; Pushes the loop variable's address, then returns.
PU1:
    PUSH HL
    PUSH BC                         ; the return address back on top
    RET

;; Continues OUTC: while the motor runs, adds the character to the tape line buffer and
;; writes the line at a carriage return; otherwise shows it.
OUTC_TAPE:
.if MODEL = 1
    JR Z,OUTC_SCREEN                ; cassette motor off: the character goes to the screen
.else
    EXX                             ; work in the alternate registers so callers keep theirs
    JR Z,OUTC_PRINTER               ; cassette motor off: the printer or the screen
.endif
    EX AF,AF'                       ; the character
    LD DE,[INPPTR]                  ; the next free place in the tape line buffer
    LD [DE],A
    INC DE
    LD [INPPTR],DE
    CP $0D                          ; a line goes to tape only once it ends
    EXX                             ; back to the caller's registers
    RET NZ
    PUSH DE                         ; keep the caller's DE across the tape write
    EXX
    LD HL,$40AC                     ; write the buffered line, $40AC up to DE
    CALL TAPE_WRITE_BLOCK
    POP DE
    RET

.if MODEL = 3
;; Sends the character to the printer while LPRINTING is set, once it is ready; otherwise to the screen.
OUTC_PRINTER:
    LD A,[LPRINTING]
    AND A
    JR Z,OUTC_SCREEN
OUTC_PRINTER_1:
    IN A,[$F8]
    AND $F0                         ; busy, paper, select and fault
    CP $30                          ; ready: not busy, paper in, selected, no fault
    JR NZ,OUTC_PRINTER_1
    EX AF,AF'                       ; the character
    OUT [$F8],A
    EXX                             ; back to the caller's registers
    RET
.endif

;; Puts a printable character at the cursor, or handles a control character.
OUTC_SCREEN:
    LD HL,[CURSOR]                  ; the cursor's screen address
    EX AF,AF'                       ; the character
    PUSH AF                         ; kept to return unchanged to the caller
    CP $20                          ; codes below a space are control characters
    JP M,OUTC_CONTROL
    LD [HL],A
    INC HL

;; Scrolls the screen up a line when the cursor has passed its end.
OUTC_SCROLL:
    LD A,H                          ; past the screen's last byte at $3FFF?
    CP $40
    JR NZ,OUTC_CURSOR
    LD DE,VIDEO                     ; move screen lines 1 through 15 up one line
    LD HL,$3C40
    LD BC,$03C0                     ; 15 lines of 64 characters
    LDIR
    EX DE,HL                        ; HL to the bottom line, now to be blanked
    CALL CLEAR_TO_EOL
    LD HL,$3FC0                     ; the cursor goes to the start of the bottom line

;; Draws the cursor at HL, saves its place and restores the registers.
OUTC_CURSOR:
    LD [HL],$5F                     ; the underline cursor
    LD [CURSOR],HL
    POP AF                          ; the character back for the caller
    EXX                             ; the caller's registers back
    RET

;; Handles a carriage return by blanking the rest of the line.
OUTC_CONTROL:
    CP $0D
    JR NZ,OUTC_CLEAR
    CALL CLEAR_TO_EOL
    JR OUTC_SCROLL                  ; a new line may need the screen to scroll

;; Handles $0C by clearing the screen and homing the cursor.
OUTC_CLEAR:
    CP $0C
    JR NZ,OUTC_BACKSPACE
    LD HL,VIDEO

;; Blanks one screen line per pass.
OUTC_CLEAR_LOOP:
    CALL CLEAR_TO_EOL
    LD A,H                          ; until past the screen's last line
    CP $40
    JR NZ,OUTC_CLEAR_LOOP
    LD HL,VIDEO                     ; cursor home
    JR OUTC_CURSOR

;; Handles $1D by erasing the cursor and moving back one place; ignores other codes.
OUTC_BACKSPACE:
    CP $1D
    JR NZ,OUTC_CURSOR               ; other control codes do nothing
    LD [HL],$20                     ; erase the cursor
    DEC HL
    JR OUTC_CURSOR

;; Fills the screen with spaces from HL to the end of its 64-column line.
;; Out: HL = the start of the next line
CLEAR_TO_EOL:
    LD [HL],$20
    INC HL
    LD A,L
    AND $3F                         ; stop at a 64-column boundary
    JR NZ,CLEAR_TO_EOL
    RET

;; Returns the key pressed, if any, after echoing it and waiting for its release.
;; Out: A = the key, zero = no key
KBD_SCAN:
    LD A,[KEYBOARD_ALL]
    AND A
    RET Z
    EXX                             ; decode in the alternate registers
    CALL KEY_DECODE
    EXX
    RST $10                         ; echo the key
    AND A                           ; NZ reports that a key was pressed
    PUSH AF
KBD_SCAN_1:
    LD A,[KEYBOARD_ALL]             ; wait until every key is released
    AND A
    JR NZ,KBD_SCAN_1
    POP AF
    RET

;; Debounces, then turns the key down into its character, applying SHIFT; rescans if the
;; key is gone.
;; Out: A = the character
KEY_DECODE:
    LD B,$FF

;; Waits a moment for the key to settle.
KEY_DEBOUNCE:
    DJNZ KEY_DEBOUNCE
    LD DE,KEY_ROW_CODES             ; each row's first code less one, one byte per row
    LD HL,KEYBOARD_ROW0
    LD A,$00

;; Reads the keyboard rows in turn until one has a key down.
KEY_FIND_ROW:
    OR [HL]                         ; the keys down in this row
    JR NZ,KEY_FOUND
    INC E                           ; the next row's table byte
    SLA L                           ; the next row's address bit
    JP P,KEY_FIND_ROW               ; rows 0 to 6 only, row 7 is SHIFT
    EXX                             ; the key is gone: drop our return and scan again
    POP AF
    JR KBD_SCAN

;; Starts from the row's first code in KEY_ROW_CODES.
KEY_FOUND:
    EX DE,HL
    LD B,[HL]                       ; the row's first code less one

;; Adds the key's column to the code, then sorts it by range.
KEY_FIND_BIT:
    INC B                           ; one code per column up to the key's bit
    SRL A
    JR NZ,KEY_FIND_BIT
    LD A,B
    CP $40                          ; @ and the letters
    JR NC,KEY_LETTER
    CP $3C                          ; the codes $3C-$3F, the shifted , - . / keys
    JR NC,KEY_PUNCT
    CP $30                          ; digits, colon and semicolon
    JR NC,KEY_DIGIT
    LD HL,KEY_SPECIAL_CODES - 1     ; just before the special key table

;; Looks an ENTER, CLEAR, BREAK, arrow or space key up in KEY_SPECIAL_CODES.
KEY_SPECIAL:
    INC HL
    DEC B
    JR NZ,KEY_SPECIAL
    LD B,[HL]                       ; the key's code from the table
    CALL KEY_SHIFT
    RET NZ                          ; shifted: the table's code as it is
    AND $3F                         ; unshifted: the arrows become the codes $1B-$1E
    RET

;; Returns a letter, or its control code with SHIFT.
KEY_LETTER:
    CALL KEY_SHIFT
    RET Z                           ; unshifted: the letter
    AND $3F                         ; SHIFT gives the letter's control code
    RET

;; Returns a digit, colon or semicolon, or its shifted symbol.
KEY_DIGIT:
    CALL KEY_SHIFT
    RET Z                           ; unshifted: the digit, colon or semicolon

;; Masks the code with $2F to give the other symbol on the key.
KEY_MASK_2F:
    AND $2F                         ; e.g. 1 becomes ! and : becomes *
    RET

;; Returns a comma, minus, period or slash, or its shifted symbol.
KEY_PUNCT:
    CALL KEY_SHIFT
    RET NZ                          ; shifted: already the code for <, =, > or ?
    JR KEY_MASK_2F                  ; unshifted: comma, minus, period or slash

;; Reads the SHIFT key and returns the code from B.
;; Out: A = B, zero = SHIFT is up
KEY_SHIFT:
    LD A,[KEYBOARD_ROW7]            ; nonzero while SHIFT is down
    AND A
    LD A,B
    RET

.if MODEL = 1
    .byte $C9                       ; left over: a second RET

;; Each keyboard row's first code less one, for rows 0-6.
KEY_ROW_CODES:
    .byte "?GOW/7", $00

;; Row 6's codes: ENTER, CLEAR, BREAK, the up, down, left and right arrows, and SPACE.
KEY_SPECIAL_CODES:
    .byte $0D, $0C, $03, "[\]^ "
.else
TABLE6:
    ENTRY "TAB", PRINT_TAB
    ENTRY "AT", PRINT_AT
    ENTRY "A$", PRINT_ASTRING
    ENTRY "B$", PRINT_BSTRING
    DEFAULT PRINT_ITEM

.endif

;; Tells a line that starts with DATA from one that does not.
DATA_TABLE:
    ENTRY "DATA", DATA_FOUND
    DEFAULT DATA_SKIP_LINE

;; Pushes the 4-byte variable at HL onto the FP stack, unpacking its sign into a fifth byte.
;; In: HL = the variable
FP_PUSH_VAR:
    PUSH DE
    PUSH HL
    PUSH AF
    LD BC,$0004                     ; copy the four stored bytes to the FP stack's top
    PUSH IX
    POP DE
    LDIR
    RL [IX+$02]                     ; the exponent's low bit out of the mantissa's top
    RL [IX+$03]                     ; shift it into the exponent, pushing out the sign
    LD A,B                          ; B is zero after LDIR: A becomes $80 when negative
    RRA
    LD [IX+$04],A
    SCF                             ; restore the mantissa's implied leading 1
    RR [IX+$02]
    LD C,$05                        ; the FP stack grows by five bytes
    ADD IX,BC
    POP AF
    POP HL
    POP DE
    RET

;; Pops the variable's address from the stack and stores the FP value there.
FP_STORE_PUSHED:
    POP HL

;; Pops the top of the FP stack into the 4-byte variable at HL, packing the sign.
;; In: HL = the variable
FP_POP_VAR:
    LD BC,$FFFB                     ; pop five bytes off the FP stack
    ADD IX,BC
    LD BC,$0004                     ; four of them go to the variable
    PUSH DE
    PUSH HL
    EX DE,HL                        ; the variable as the destination
    PUSH IX
    POP HL
    LDIR
    EX DE,HL
    DEC HL                          ; back to the mantissa's top byte
    DEC HL
    RL [HL]                         ; drop the implied leading 1
    INC HL
    LD A,[IX+$04]                   ; the sign byte, whose bit 7 goes into carry
    RLA
    RR [HL]                         ; sign into the exponent byte, its low bit out
    DEC HL
    RR [HL]                         ; the exponent's low bit into the mantissa's top
    POP HL
    POP DE
    RET

;; Pops the top of the FP stack as an integer rounded down, HOW? when it needs over 15 bits.
;; Out: HL = the integer
FP_TO_INT:
    EXX                             ; work in the alternate registers
    LD BC,$FFFB
    ADD IX,BC                       ; pop the value
    LD DE,START                     ; DE = 0, the integer being built
    LD A,[IX+$03]                   ; the exponent
    LD C,[IX+$04]                   ; the sign byte
    CP $80                          ; $80 is zero: the integer is 0
    JR Z,FP_TO_INT_DONE
    CP $01                          ; exponent below 1: no integer part
    JP M,FP_TO_INT_FRAC
    CP $10                          ; up to 15 bits fits a positive integer
    JP M,FP_TO_INT_SHIFT
    EXX                             ; too large for an integer
    JP AHOW

;; Handles a value below one: integer part zero, with a fraction.
FP_TO_INT_FRAC:
    LD A,$FF                        ; nonzero A marks a fraction to round
    JR FP_TO_INT_SIGN

;; Loads the mantissa to shift its integer part into DE.
FP_TO_INT_SHIFT:
    LD B,A                          ; the exponent is the number of bits to shift
    LD A,[IX+$00]                   ; the mantissa, low byte in A
    LD L,[IX+$01]
    LD H,[IX+$02]

;; Shifts one bit into DE per pass.
FP_TO_INT_LOOP:
    SLA A
    RL L
    RL H
    RL E                            ; the integer's bits collect in DE
    RL D
    DJNZ FP_TO_INT_LOOP

;; Applies the sign; a negative value with a fraction is rounded down.
FP_TO_INT_SIGN:
    SLA C                           ; the sign bit into carry
    JR NC,FP_TO_INT_DONE            ; positive: dropping the fraction rounds down
    OR H                            ; any fraction bits left?
    OR L
    JR Z,FP_TO_INT_NEG              ; an exact negative: just negate
    INC DE                          ; a fraction rounds a negative one lower

;; Negates the integer.
FP_TO_INT_NEG:
    CALL NEG_DE

;; Returns the integer in HL.
FP_TO_INT_DONE:
    PUSH DE                         ; the result to the caller's HL
    EXX
    POP HL
    RET

;; Pushes 10 onto the FP stack.
FP_PUSH_TEN:
    LD HL,$000A

;; Pushes the signed integer in HL onto the FP stack.
;; In: HL = the integer
FP_PUSH_INT:
    PUSH DE
    EX DE,HL
    LD BC,$000A                     ; room for two entries: storing the result drops one
    ADD IX,BC
    CALL ABS_DE                     ; the magnitude, carry when it was negative
    PUSH DE
    LD H,$00                        ; H becomes $80 for a negative number
    RR H
    LD L,$10                        ; exponent 16 for a 16-bit integer
    EXX                             ; the magnitude into the alternate registers
    POP DE
    LD L,$00                        ; the mantissa C'H'L' is the integer at its top
    LD H,E
    LD C,D
    CALL FP_NORMALIZE
    JR FP_STORE_JR

;; Makes DE positive.
;; Out: DE = its magnitude, carry = it was negative
ABS_DE:
    XOR A
    ADD A,D
    RET P                           ; positive: carry is clear from the add

;; Negates DE and sets carry.
NEG_DE:
    LD A,E
    NEG
    LD E,A
    LD A,D                          ; high byte: complement, plus one if E was zero
    CPL
    CCF
    ADC A,$00
    LD D,A
    SCF                             ; report a negative number
    RET

;; Multiplies the top of the FP stack by ten.
FP_MUL10:
    CALL FP_PUSH_TEN

;; Replaces the top two FP stack entries with their product.
FP_MUL:
    CALL FP_FETCH2
    JR Z,FP_SUB_NEGATE              ; the second is zero: so is the product
    CP E                            ; the top is zero: the product is zero
    JP Z,FP_RESULT_ZERO
    CALL FP_MULTIPLY
    JR FP_STORE_JR

;; Divides the top of the FP stack by ten.
FP_DIV10:
    CALL FP_PUSH_TEN

;; Replaces the top two FP stack entries with the second divided by the top, HOW? when the
;; top is zero.
FP_DIV:
    CALL FP_FETCH2
    JR Z,FP_SUB_NEGATE              ; the dividend is zero: so is the quotient
    CP E                            ; division by zero
    JP Z,AHOW_1
    CALL FP_DIVIDE

;; Goes on to store the result.
FP_STORE_JR:
    JR FP_STORE_RESULT

;; Compares the top of the FP stack with the 4-byte constant at HL, leaving the stack as
;; it was.
;; Out: zero = equal, carry = the value is less
FP_CMP_CONST:
    CALL FP_PUSH_VAR                ; push the constant for the comparison
    CALL FP_FETCH2
    LD BC,$FFFB                     ; afterwards drop only the constant
    JR FP_CMP_DROP

;; Compares the second FP stack entry with the top and pops both.
;; Out: zero = equal, carry = the second is less
FP_COMPARE:
    CALL FP_FETCH2
    LD BC,$FFF6                     ; afterwards drop both entries

;; Drops entries from the FP stack, then sets the flags from the comparison.
FP_CMP_DROP:
    ADD IX,BC
    CP L                            ; Z when the second is zero, as FP_CMP_FLAGS expects
    CALL FP_CMP_FLAGS
    POP DE                          ; the caller's DE, saved by FP_FETCH2
    RET

;; Replaces the top two FP stack entries with the second minus the top.
FP_SUB:
    CALL FP_FETCH2
    JR NZ,FP_SUB_CHECK              ; the second is nonzero
    CALL FP_SET_TO_TOP              ; 0 minus x: the result is x
    JR FP_NEG_RESULT                ; then negated

;; Checks the top for zero before subtracting.
FP_SUB_CHECK:
    CP E                            ; is the top zero?

;; Drops the top, leaving the second, when Z; otherwise flips the top's sign and adds.
FP_SUB_NEGATE:
    JR Z,FP_DROP_TOP                ; x minus 0 is x
    XOR D                           ; A is $80: flip the subtrahend's sign, then add
    LD D,A
    JR FP_ADD_ALIGN
.if MODEL = 1
    CALL FP_PUSH_VAR                ; left over: nothing reaches it
.endif

;; Replaces the top two FP stack entries with their sum.
FP_ADD:
    CALL FP_FETCH2
    JR Z,FP_RESULT_TOP              ; 0 plus x is x
    CP E                            ; x plus 0 is x
    JR Z,FP_DROP_TOP

;; Compares the magnitudes, swapping the operands so the larger is in H, L and C'H'L'.
FP_ADD_ALIGN:
    CALL FP_CMP_MAG
    JR Z,FP_ADD_EQUAL               ; equal magnitudes need their own handling
    JR NC,FP_ADD_LARGER             ; the second is already the larger
    EX DE,HL                        ; swap the signs and exponents
    EXX
    EX DE,HL                        ; and the mantissas
    LD A,C
    LD C,B
    LD B,A
    EXX

;; Adds the mantissas and stores the result.
FP_ADD_LARGER:
    CALL FP_ADD_MANT
    JR FP_STORE_RESULT

;; Handles equal magnitudes: zero for opposite signs, else doubles by raising the exponent.
FP_ADD_EQUAL:
    LD A,H                          ; do the signs differ?
    XOR D
    JR NZ,FP_RESULT_ZERO            ; x plus -x is zero
    LD E,$01                        ; x plus x: raise the exponent by one
    CALL FP_ADD_EXP
    JR FP_STORE_RESULT

;; Flips the sign of the top FP stack entry and restores DE.
FP_NEG_RESULT:
    LD A,[IX-$01]
    XOR $80
    LD [IX-$01],A
    POP DE                          ; the caller's DE
    RET

;; Makes the top entry the result in place of the second, then pops.
FP_SET_TO_TOP:
    PUSH DE                         ; matched by the POP in FP_STORE_RESULT

;; Copies the top operand into the result registers and stores it.
FP_RESULT_TOP:
    LD H,D
    LD L,E
    EXX
    LD L,E
    LD H,D
    LD C,B
    EXX
    JR FP_STORE_RESULT

;; Sets the result to zero and stores it.
FP_RESULT_ZERO:
    LD L,$80                        ; exponent $80 means zero

;; Stores H, L and C'H'L' over the second entry, pops the top and restores DE.
FP_STORE_RESULT:
    LD [IX-$06],H                   ; the result goes where the second entry was
    LD [IX-$07],L
    EXX
    LD [IX-$0A],L
    LD [IX-$09],H
    LD [IX-$08],C
    EXX

;; Pops the top entry, restores DE and returns.
FP_DROP_TOP:
    LD BC,$FFFB
    ADD IX,BC
    POP DE                          ; the caller's DE, saved by FP_FETCH2
    RET

;; Multiplies the second value by the top with 24 shift-and-add steps, leaving the result
;; in H, L and C'H'L'.
FP_MULTIPLY:
    LD A,H                          ; the product's sign
    XOR D
    LD H,A
    DEC E
    PUSH HL                         ; keep the signs and exponents during the loop
    PUSH BC
    LD B,$18                        ; 24 multiplier bits
    LD L,[IX-$0A]                   ; the second's mantissa is the multiplier
    LD H,[IX-$09]
    LD C,[IX-$08]
    EXX
    XOR A                           ; the product in C'H'L' starts at zero
    LD L,A
    LD H,A
    LD C,A

;; Shifts the next multiplier bit out, adding the multiplicand when it is set.
FP_MUL_LOOP:
    EXX
    SRL C                           ; the multiplier's low bit into carry
    RR H
    RR L
    EXX
    JR NC,FP_MUL_NEXT               ; a clear bit adds nothing
    ADD HL,DE                       ; add the multiplicand B'D'E' to the product
    LD A,C
    ADC A,B
    LD C,A

;; Counts the step; after the last, goes on to the exponent.
FP_MUL_NEXT:
    EXX
    DJNZ FP_MUL_SHIFT
    POP BC                          ; the signs and exponents back
    POP HL
    EXX
    JR FP_MULDIV_END

;; Shifts the product right one bit.
FP_MUL_SHIFT:
    EXX
    RR C                            ; shift the product right, taking in the add's carry
    RR H
    RR L
    JR FP_MUL_LOOP

;; Divides the second value by the top with restoring division, leaving the result in H, L
;; and C'H'L'.
FP_DIVIDE:
    LD A,E                          ; dividing subtracts the divisor's exponent
    NEG
    LD E,A
    LD A,H                          ; the quotient's sign
    XOR D
    LD H,A
    PUSH HL                         ; keep the signs and exponents during the loop
    PUSH BC
    LD B,$19                        ; 25 quotient bits
    EXX

;; Subtracts the divisor, adding it back when the remainder goes negative.
FP_DIV_LOOP:
    SBC HL,DE                       ; try the remainder C'H'L' less the divisor B'D'E'
    LD A,C
    SBC A,B
    LD C,A
    JR NC,FP_DIV_BIT                ; it fit: a 1 bit
    ADD HL,DE                       ; it did not: restore the remainder
    ADC A,B
    LD C,A

;; Shifts the quotient bit in and counts the step.
FP_DIV_BIT:
    EXX
    CCF                             ; carry is now the quotient bit
    ADC HL,HL                       ; shift it into the quotient in C, H, L
    RL C
    DJNZ FP_DIV_SHIFT
    PUSH HL                         ; move the quotient to the alternate registers
    PUSH BC
    EXX
    POP BC
    POP HL
    EXX
    POP BC                          ; the signs and exponents back
    POP HL
    EXX

;; Goes on to handle the carry and add the exponents.
FP_MULDIV_END:
    JR FP_ADD_CARRY

;; Shifts the remainder left; a bit carried out forces a subtraction.
FP_DIV_SHIFT:
    EXX
    ADD HL,HL                       ; double the remainder
    RL C
    JR NC,FP_DIV_LOOP               ; no bit carried out: try the subtraction
    CCF                             ; over 24 bits, so the divisor surely fits
    SBC HL,DE
    LD A,C
    SBC A,B
    LD C,A
    OR A                            ; clear carry, which becomes a 1 bit
    JR FP_DIV_BIT

;; Sets the flags from comparing the second value (H, L) with the top (D, E).
;; Out: zero = equal, carry = the second is less
FP_CMP_FLAGS:
    JR Z,FP_CMP_ZERO                ; the second is zero
    CP E
    JR Z,FP_CMP_SIGN                ; the top is zero: the second's sign decides
    LD A,H                          ; do the signs agree?
    XOR D
    CALL Z,FP_CMP_MAG               ; same sign: the magnitudes decide
    JR FP_CMP_MAG_DONE

;; Handles a zero second value: equal when the top is zero, else the top's sign decides.
FP_CMP_ZERO:
    CP E
    RET Z                           ; both zero: equal
    SCF                             ; zero is below a positive top, above a negative one
    BIT 7,D
    JR FP_CMP_TO_CARRY

;; Returns when the values are equal.
FP_CMP_MAG_DONE:
    RET Z

;; Tests the sign in H, which decides the order for values of opposite sign.
FP_CMP_SIGN:
    BIT 7,H                         ; a negative second reverses the order

;; Keeps the carry and clears Z when the tested sign is positive.
FP_CMP_TO_CARRY:
    JR NZ,FP_CMP_INVERT
    RRA                             ; keep the carry while making A nonzero to clear Z
    SCF
    RL A
    RET

;; Inverts the carry and returns.
FP_CMP_INVERT:
    CCF
    RET

;; Compares the magnitudes: the exponents L and E, then the mantissas C'H'L' and B'D'E'.
;; Out: zero = equal, carry = the second is smaller
FP_CMP_MAG:
    LD A,L                          ; the exponents' difference
    SUB E
    JR Z,FP_CMP_MANT
    JP PO,FP_CMP_EXP_SIGN           ; no overflow: the difference's sign is valid
    NEG                             ; it overflowed: correct the sign

;; Moves the sign of the exponent difference into carry.
FP_CMP_EXP_SIGN:
    RLCA                            ; carry when the second's exponent is smaller
    RET

;; Compares the mantissas when the exponents match.
FP_CMP_MANT:
    EXX
    LD A,C                          ; the mantissas' top bytes first
    CP B
    JR NZ,FP_CMP_MANT_END
    LD A,H
    CP D
    JR NZ,FP_CMP_MANT_END
    LD A,L
    CP E

;; Switches back to the main registers and returns.
FP_CMP_MANT_END:
    EXX
    RET

;; Shifts the smaller mantissa right to align it, then adds or subtracts the mantissas.
;; Out: H = the result's sign, L = its exponent, C'H'L' = its mantissa
FP_ADD_MANT:
    LD A,L                          ; how far apart the exponents are
    SUB E
    JR Z,FP_ADD_SIGNS               ; already aligned
    CP $18                          ; 24 or more bits apart: the smaller adds nothing
    RET NC
    EXX

;; Shifts the smaller mantissa right one bit per pass.
FP_ALIGN_LOOP:
    SRL B
    RR D
    RR E
    DEC A
    JR NZ,FP_ALIGN_LOOP
    EXX

;; Adds the mantissas when the signs agree, or subtracts them when they differ.
FP_ADD_SIGNS:
    LD E,$00                        ; no exponent change unless there is a carry
    LD A,H                          ; opposite signs: subtract the magnitudes
    XOR D
    JP M,FP_SUB_MANT
    EXX
    ADD HL,DE
    LD A,C
    ADC A,B
    LD C,A

;; On a carry out, shifts the mantissa right and adds one to the exponent.
FP_ADD_CARRY:
    JR NC,FP_ADD_EXP_SW
    RR C                            ; put the carried bit back in at the top
    RR H
    RR L
    SCF                             ; and add one to the exponent

;; Switches to the main registers to adjust the exponent.
FP_ADD_EXP_SW:
    EXX

;; Adds E and the carry to the exponent in L, checking for overflow.
FP_ADD_EXP:
    LD A,L
    ADC A,E                         ; the exponent plus E and the carry

;; Stores A as the exponent unless it went out of range.
FP_SET_EXP:
    JP PE,FP_EXP_RANGE              ; overflowed the signed exponent
    LD L,A
    RET

;; Subtracts the mantissas, then normalizes the result.
FP_SUB_MANT:
    EXX
    SBC HL,DE                       ; the larger less the smaller, never negative
    LD A,C
    SBC A,B
    LD C,A

;; Shifts the mantissa left until its top bit is set, lowering the exponent to match; a
;; zero mantissa gives exponent $80, zero.
FP_NORMALIZE:
    LD B,$18                        ; at most 24 shifts
    XOR A                           ; A counts the change to the exponent
    INC C                           ; sets the sign flag from the mantissa's top bit
    DEC C

;; Shifts one bit per pass until the top bit is set.
FP_NORM_LOOP:
    JP M,FP_NORM_DONE               ; top bit set: normalized
    DEC A
    ADD HL,HL
    RL C
    DJNZ FP_NORM_LOOP

;; Sets the exponent byte to $80, meaning zero, and returns.
FP_ZERO_EXP:
    LD L,$80                        ; no bit in 24 shifts: the mantissa is zero
    RET

;; Adds the shift count to the exponent.
FP_NORM_DONE:
    EXX
    ADD A,L                         ; lower the exponent by the shifts
    JR FP_SET_EXP

;; Handles an exponent out of range: zero when bit 7 of H is set, otherwise HOW?.
FP_EXP_RANGE:
    LD A,H
    OR A
    JP M,FP_ZERO_EXP
    POP AF                          ; drop the return address
    JP AHOW_1

;; Loads the top two FP stack entries: the second into H, L and C'H'L', the top into D, E
;; and B'D'E', saving DE for the caller.
;; Out: A = $80, zero = the second is zero
FP_FETCH2:
    POP HL                          ; the return address
    PUSH DE                         ; save the caller's DE beneath it
    PUSH HL
    LD D,[IX-$01]                   ; the top's sign and exponent
    LD E,[IX-$02]
    EXX                             ; the top's mantissa in B'D'E'
    LD E,[IX-$05]
    LD D,[IX-$04]
    LD B,[IX-$03]
    EXX
    LD H,[IX-$06]                   ; the second's sign and exponent
    LD L,[IX-$07]
    EXX                             ; the second's mantissa in C'H'L'
    LD L,[IX-$0A]
    LD H,[IX-$09]
    LD C,[IX-$08]
    EXX
    LD A,$80                        ; $80 is the exponent of zero
    CP L
    RET
;; Handles RND(n): a random whole number from 1 to n, or a fraction below 1 for RND(0).
FN_RND:
    CALL PARN_INT
    LD A,H
    OR L
    JP Z,FP_RANDOM                  ; RND(0) gives a fraction below 1
    BIT 7,H                         ; a negative n is an error
    JP NZ,AHOW
    CALL FP_PUSH_INT
    CALL FP_RANDOM
    CALL FP_MUL                     ; n times a fraction below 1
    CALL FP_TO_INT                  ; a whole number from 0 to n-1
    INC HL                          ; one more gives 1 to n
    JP FP_PUSH_INT

;; Steps the 24-bit seed at $40A7 and pushes it onto the FP stack as a fraction below 1.
FP_RANDOM:
    PUSH DE
    EXX
    LD HL,$40A7                     ; the seed, into B'D'E'
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
    LD B,[HL]
    EXX
    CALL FP_PARSE_RESET             ; the product in C'H'L' starts at zero
    LD HL,$0EB2                     ; the three-byte multiplier
    LD C,$03

;; Multiplies by one byte of the constant at $0EB2 per pass.
RANDOM_BYTE:
    LD B,$08
    LD D,[HL]                       ; this byte of the multiplier

;; Shifts the product and adds the seed for each set bit.
RANDOM_BIT:
    EXX
    ADD HL,HL                       ; shift the product left
    RL C
    EXX
    RL D                            ; the multiplier's next bit
    JR NC,RANDOM_NEXT
    EXX
    ADD HL,DE                       ; add the seed
    LD A,C
    ADC A,B
    LD C,A
    EXX

;; Counts the bits, then moves on to the next byte.
RANDOM_NEXT:
    DJNZ RANDOM_BIT
    INC HL
    DEC C
    JR NZ,RANDOM_BYTE
    LD HL,START                     ; sign positive and exponent 0: a fraction below 1
    EXX
    LD DE,$40A7                     ; the new seed is the product plus $05B065
    LD A,L
    ADD A,$65
    LD [DE],A
    INC DE
    LD L,A
    LD A,H
    ADC A,$B0
    LD [DE],A
    INC DE
    LD H,A
    LD A,C
    ADC A,$05
    LD [DE],A
    LD C,A
    CALL FP_NORMALIZE               ; make it a normalized fraction
    LD BC,$000A                     ; room for two entries: storing the result drops one
    ADD IX,BC
    JP FP_STORE_RESULT
    .byte $40, $E6, $4D, $00, $00, $80, $00, $CC, $CC, $CC, $7E

;; Reads a line number at DE, WHAT? when there are no digits.
;; Out: HL = the number
READ_LINENUM:
    CALL TSTNUM
    RET NZ                          ; digits were read

;; Jumps to QWHAT.
LINENUM_WHAT:
    JP QWHAT

;; Reads a decimal number at DE into HL, with B the count of digits; HOW? past 32767.
TSTNUM:
    CALL FP_PARSE_RESET             ; clear the accumulator in C'H'L'
    LD HL,START                     ; the number and the digit count start at zero
    LD B,L
    RST IGNBLK_RST
TSTNUM_1:
    CALL TSTDIG
    JR C,TSTNUM_DONE                ; no more digits
    INC B                           ; count the digit
    CALL MUL10                      ; the number times ten plus the digit
    JR NC,TSTNUM_1                  ; no overflow past 24 bits: next digit
TSTNUM_2:
    JP AHOW
;; Ends the digits: HOW? when the number needs more than 15 bits, else returns it.
;; Out: HL = the number, A = B = the digit count, zero = no digits
TSTNUM_DONE:
    EXX
    PUSH HL                         ; the low 16 bits
    LD A,C                          ; the top byte
    BIT 7,H                         ; over 32767?
    EXX
    POP HL
    JR NZ,TSTNUM_2
    AND A                           ; any bits above 16 also overflow
    JR NZ,TSTNUM_2
    LD A,B                          ; Z when no digits were read
    AND A
    RET
;; Handles CLOAD: reads a program from tape, WHAT? on a checksum error.
ST_CLOAD:
    CALL TAPE_READ_BLOCK
    LD [TXTUNF],HL                  ; the program now ends where the block ended
    JR NZ,LINENUM_WHAT              ; a bad checksum
ST_CLOAD_1:
    JP RSTART

;; Starts the motor, waits for the $A5 sync byte, then reads the start and end addresses
;; and the bytes between into memory.
;; Out: HL = the end address, zero = the checksum is good
TAPE_READ_BLOCK:
    CALL CASSETTE_ON
    PUSH DE
    XOR A                           ; no bits read yet

;; Reads bits until the last eight form $A5.
TAPE_SYNC:
    CALL CASSETTE_READ_BIT
    CP $A5                          ; the sync byte ends the leader
    JR NZ,TAPE_SYNC
    LD A,$2A                        ; an asterisk in the top corner shows the load
    LD [VIDEO],A
    LD [BLINKSTAR],A                ; the second asterisk blinks with each line read
    CALL CASSETTE_READ
    LD D,A                          ; the block's start address
    CALL CASSETTE_READ
    LD E,A
    CALL CASSETTE_READ
    LD H,A                          ; the block's end address
    CALL CASSETTE_READ
    LD L,A
    LD C,$00                        ; the checksum starts at zero

;; Reads and stores a byte, flipping the screen's asterisk at each carriage return.
TAPE_READ_LOOP:
    CALL CASSETTE_READ
    LD [DE],A
    INC DE
    CP $0D                          ; a line ends at each carriage return
    JR NZ,TAPE_READ_SUM
    PUSH AF
    LD A,[BLINKSTAR]
    XOR $0A                         ; switch the asterisk and a space
    LD [BLINKSTAR],A
    POP AF

;; Adds the byte to the checksum and repeats through the end address.
TAPE_READ_SUM:
    ADD A,C
    LD C,A
    RST $20                         ; through the end address
    JR NC,TAPE_READ_LOOP
    PUSH HL                         ; CASSETTE_OFF changes HL
    CALL CASSETTE_OFF
    POP HL
    POP DE
    LD A,C                          ; a good block sums to zero with its checksum
    AND A
    RET
;; Handles CSAVE: writes the program to tape.
ST_CSAVE:
    CALL CASSETTE_ON
    LD HL,$4200                     ; from the program's start to its end
    LD DE,[TXTUNF]
    CALL TAPE_WRITE_BLOCK
.if MODEL = 1
    JP RSTART
.else
    JP ST_CLOAD_1
.endif

.if MODEL = 1
;; Writes 128 zero bytes, $A5, the addresses in HL and DE, the bytes from HL up to DE
;; and a checksum, then stops the motor.
;; In: HL = the start, DE = the end
TAPE_WRITE_BLOCK:
    LD A,$80                        ; 128 leader bytes
    PUSH BC                         ; the leader and header go into a discarded sum

;; Writes one zero byte of the leader per pass.
TAPE_LEADER:
    EX AF,AF'                       ; the count to the alternate A
    XOR A
    CALL CASSETTE_WRITE
    EX AF,AF'
    DEC A
    JR NZ,TAPE_LEADER
    LD A,$A5                        ; the sync byte
    CALL CASSETTE_WRITE
    LD A,H                          ; the start address, high byte first
    CALL CASSETTE_WRITE
    LD A,L
    CALL CASSETTE_WRITE
    POP BC
    LD A,D                          ; the end address
    CALL CASSETTE_WRITE
    LD A,E
    CALL CASSETTE_WRITE
    LD C,$00                        ; the checksum covers only the data

;; Writes one data byte per pass.
TAPE_WRITE_LOOP:
    LD A,[HL]
    CALL CASSETTE_WRITE
    INC HL
    RST $20
    JR NZ,TAPE_WRITE_LOOP           ; until HL reaches the end
    LD A,C                          ; a last byte that makes the data sum to zero
    NEG
    CALL CASSETTE_WRITE
    CALL CASSETTE_OFF
    RET

;; Waits for a clock pulse on the tape, then samples the data bit and shifts it into A.
;; In: A = the bits so far
;; Out: A = shifted left, with the new bit in bit 0
CASSETTE_READ_BIT:
    EXX
    EX AF,AF'                       ; the bits so far into A'
CASSETTE_READ_BIT_1:
    IN A,[$FF]
    RLA                             ; bit 7 latches a pulse: wait for the clock pulse
    JR NC,CASSETTE_READ_BIT_1
    LD B,$7C                        ; wait out the clock pulse
CASSETTE_READ_BIT_2:
    DJNZ CASSETTE_READ_BIT_2
    CALL PORT_FF_REFRESH            ; clear the latch
    LD B,$F8                        ; wait for where a data pulse would come
CASSETTE_READ_BIT_3:
    DJNZ CASSETTE_READ_BIT_3
    IN A,[$FF]                      ; a data pulse there has latched a 1
    LD B,A
    EX AF,AF'                       ; the bits so far
    RL B                            ; the latched bit into the bottom of A
    RLA
    PUSH AF                         ; clear the latch, keeping A
    CALL PORT_FF_REFRESH
    POP AF
    EXX
    RET

;; Reads a byte from the tape into A.
CASSETTE_READ:
    LD B,$08
CASSETTE_READ_1:
    CALL CASSETTE_READ_BIT
    DJNZ CASSETTE_READ_1
    RET

;; Writes the byte in A to the tape, adding it to the checksum in C.
CASSETTE_WRITE:
    EXX                             ; keeps the caller's registers
    LD C,$08                        ; eight bits
    LD D,A
CASSETTE_WRITE_1:
    CALL CASSETTE_WRITE_BIT         ; the clock pulse
    RLC D                           ; the next data bit, top bit first
    JR NC,CASSETTE_WRITE_GAP        ; a 0 bit has no data pulse
    CALL CASSETTE_WRITE_BIT         ; a 1 bit has a data pulse
CASSETTE_WRITE_2:
    DEC C
    JR NZ,CASSETTE_WRITE_1
    LD A,D                          ; D has rotated back to the byte
    EXX
    ADD A,C                         ; add it to the checksum in the caller's C
    LD C,A
    RET
;; Waits out the data pulse's time for a 0 bit.
CASSETTE_WRITE_GAP:
    LD B,$00                        ; 256 loops, as long as a pulse takes
CASSETTE_WRITE_4:
    DJNZ CASSETTE_WRITE_4
    JR CASSETTE_WRITE_2

;; Writes one pulse to the tape: a short swing up, then down, then a pause.
CASSETTE_WRITE_BIT:
    LD HL,$FC01                     ; drive the cassette output to one level
    CALL SET_PORT_FF
    LD B,$0A
CASSETTE_WRITE_BIT_1:
    DJNZ CASSETTE_WRITE_BIT_1
    LD HL,$FC02                     ; then the other
    CALL SET_PORT_FF
    LD B,$0A
CASSETTE_WRITE_BIT_2:
    DJNZ CASSETTE_WRITE_BIT_2
    LD HL,$FC00                     ; then back to rest
    CALL SET_PORT_FF
    LD B,$DA                        ; the gap after the pulse
CASSETTE_WRITE_BIT_3:
    DJNZ CASSETTE_WRITE_BIT_3
    RET

.else
;; Writes 128 zero bytes, $A5, the addresses in HL and DE, the bytes from HL up to DE
;; and a checksum, then stops the motor.
;; In: HL = the start, DE = the end
TAPE_WRITE_BLOCK:
    LD B,$80                        ; 128 leader bytes

;; Writes one zero byte of the leader per pass.
TAPE_LEADER:
    XOR A
    CALL CASSETTE_WRITE
    DJNZ TAPE_LEADER
    LD A,$A5                        ; the sync byte
    CALL CASSETTE_WRITE
    LD A,H                          ; the start address, high byte first
    CALL CASSETTE_WRITE
    LD A,L
    CALL CASSETTE_WRITE
    LD A,D                          ; the end address
    CALL CASSETTE_WRITE
    LD A,E
    CALL CASSETTE_WRITE
    LD C,$00                        ; the checksum covers only the data

;; Writes one data byte per pass.
TAPE_WRITE_LOOP:
    LD A,[HL]
    CALL CASSETTE_WRITE
    INC HL
    RST $20
    JR NZ,TAPE_WRITE_LOOP           ; until HL reaches the end
    LD A,C                          ; a last byte that makes the data sum to zero
    NEG
    CALL CASSETTE_WRITE
    JR CASSETTE_OFF

;; Waits for a clock pulse on the tape, then samples the data bit and shifts it into A.
;; In: A = the bits so far
;; Out: A = shifted left, with the new bit in bit 0
CASSETTE_READ_BIT:
    EXX
    LD C,A                          ; the bits so far
CASSETTE_READ_BIT_1:
    IN A,[$FF]
    RLA                             ; bit 7 latches a pulse: wait for the clock pulse
    JR NC,CASSETTE_READ_BIT_1
    LD B,$BB                        ; wait out the clock pulse
CASSETTE_READ_BIT_2:
    DJNZ CASSETTE_READ_BIT_2
    OUT [$FF],A                     ; clear the latch
    LD B,$00                        ; wait for where a data pulse would come
CASSETTE_READ_BIT_3:
    DJNZ CASSETTE_READ_BIT_3
    IN A,[$FF]                      ; a data pulse there has latched a 1
    RLA
    LD A,C                          ; the latched bit into the bottom of the bits so far
    RLA
    OUT [$FF],A                     ; clear the latch
    EXX
    RET

;; Reads a byte from the tape into A.
CASSETTE_READ:
    LD B,$08
CASSETTE_READ_1:
    CALL CASSETTE_READ_BIT
    DJNZ CASSETTE_READ_1
    RET

;; Writes the byte in A to the tape, adding it to the checksum in C.
CASSETTE_WRITE:
    EXX                             ; keeps the caller's registers
    LD C,$08                        ; eight bits
    LD D,A
CASSETTE_WRITE_1:
    CALL CASSETTE_WRITE_BIT         ; the clock pulse
    RLC D                           ; the next data bit, top bit first
    JR NC,CASSETTE_WRITE_GAP        ; a 0 bit has no data pulse
    CALL CASSETTE_WRITE_BIT         ; a 1 bit has a data pulse
CASSETTE_WRITE_2:
    DEC C
    JR NZ,CASSETTE_WRITE_1
    LD A,D                          ; D has rotated back to the byte
    EXX
    ADD A,C                         ; add it to the checksum in the caller's C
    LD C,A
    RET

;; Waits out the data pulse's time for a 0 bit.
CASSETTE_WRITE_GAP:
    LD B,$34
CASSETTE_WRITE_3:
    DJNZ CASSETTE_WRITE_3
CASSETTE_WRITE_4:
    DJNZ CASSETTE_WRITE_4           ; and 256 more loops
    JR CASSETTE_WRITE_2

;; Writes one pulse to the tape: a short swing up, then down, then a pause.
CASSETTE_WRITE_BIT:
    LD A,$01                        ; drive the cassette output to one level
    OUT [$FF],A
    LD B,$12
CASSETTE_WRITE_BIT_1:
    DJNZ CASSETTE_WRITE_BIT_1
    INC A                           ; then the other
    OUT [$FF],A
    LD B,$12
CASSETTE_WRITE_BIT_2:
    DJNZ CASSETTE_WRITE_BIT_2
    XOR A                           ; then back to rest
    OUT [$FF],A
    LD B,$0D                        ; the gap after the pulse
CASSETTE_WRITE_BIT_3:
    DJNZ CASSETTE_WRITE_BIT_3
CASSETTE_WRITE_BIT_4:
    DJNZ CASSETTE_WRITE_BIT_4       ; and 256 more loops
    RET

.endif

.if MODEL = 1
;; Turns the cassette motor off.
CASSETTE_OFF:
    LD HL,$FB00                     ; clear bit 2, the motor relay
    JR SET_PORT_FF

;; Turns the cassette motor on.
CASSETTE_ON:
    LD HL,$FF04                     ; set bit 2, the motor relay
    CALL SET_PORT_FF
    RET

;; Rewrites port $FF unchanged, which clears the cassette input latch.
;; Out: zero = the motor is off
PORT_FF_REFRESH:
    LD HL,$FF00                     ; keep every bit as it is

;; Clears port $FF's bits not in H and sets those in L, keeping a copy at PORT_FF_IMAGE.
SET_PORT_FF:
    LD A,[PORT_FF_IMAGE]
    AND H
    OR L
    OUT [$FF],A
    LD [PORT_FF_IMAGE],A
    BIT 2,A                         ; NZ while the motor is on
    RET
.else
    .byte $00, $00, $00             ; unused

;; Each keyboard row's first code less one, for rows 0-6.
KEY_ROW_CODES:
    .byte "?GOW/7", $00

;; Row 6's codes: ENTER, CLEAR, BREAK, the up, down, left and right arrows, and SPACE.
KEY_SPECIAL_CODES:
    .byte $0D, $0C, $03, "[\]^ "

;; Turns the cassette motor off, with the video wait back on.
CASSETTE_OFF:
    LD A,$20
    JR CASSETTE_OPTIONS

;; Turns the cassette motor on, with no video wait to upset the tape's timing.
CASSETTE_ON:
    LD A,$02

;; Writes the options port: bit 1 the cassette motor, bit 5 the video wait.
CASSETTE_OPTIONS:
    OUT [$EC],A
    RET

READY_MSG:
    .byte "READY", $0D

WHAT_MSG:
    .byte "WHAT?", $0D

SORRY_MSG:
    .byte "SORRY", $0D
.endif
