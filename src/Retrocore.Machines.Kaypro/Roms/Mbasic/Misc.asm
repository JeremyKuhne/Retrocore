;; MBASIC 5.21: NEW, CLEAR, NEXT AND THE OTHER SMALL STATEMENTS (BIMISC)
;;
;; The statements that reset or stop the interpreter, and the helpers the whole program shares with them. It
;; corresponds to GW-BASIC's BIMISC.ASM, from SCRATH to ISLET2 and CLEAR, followed by NEXT from NEXT86.ASM, in
;; the same order:
;;
;; - INIFIL marks every file closed and falls into NEW, for the first start (Init.asm).
;; - NEW (ST_NEW, SCRTCH) empties the program and falls into RUNC, which RUN also uses, and CLEARC, which clears
;;   the variables, the arrays, the strings, the DATA pointer and the default types. CLEARC falls into STKINI,
;;   which resets the stack and the string temporaries; STKERR is its second half, which error recovery enters
;;   with its own stack pointer.
;; - DCOMPR and SYNCHR are the 8080 source's COMPAR and SYNCHK restarts, called here as subroutines: DCOMPR
;;   compares HL with DE, and SYNCHR checks the text for the character in the byte after its call.
;; - RESTORE, STOP and END, then CONSTP, STPEND and ENDCON, which stop the program and remember where for CONT.
;;   CTROPT and CTRLPT echo ^O and ^C, then CONT, NULL, TRON and TROFF.
;; - SWAP and ERASE, then POPAHT, ISLET and ISLET2 (letter tests), CLEAR, SUBDE and NEXT.
;; - ISFLIO tests whether output is going to a file.
;;
;; Runs at $430A-$465B. The main entry points are the statement handlers, which GONE reaches through STMDSP, and
;; RUNC, CLEARC, STKINI, DCOMPR, SYNCHR, STPEND, CTRLPT, ISLET, ISLET2, NEXTS and ISFLIO, which the rest of
;; the program calls.

;; Marks every file closed and closes them, then falls into NEW, for the first start (Init.asm).
;;
;; The first byte of each file's data block, in the table at FILPTR, is set to 0 (closed), for MAXFILES (MAXFIL)
;; plus one files, file 0 being LOAD's and SAVE's.
INIFIL:
    LD A,[MAXFIL]                   ; the number of files
    LD B,A
    LD HL,FILPTR                    ; the table of their data blocks
    XOR A
    INC B                           ; and file 0
INIFIL_1:
    LD E,[HL]                       ; DE = the next data block
    INC HL
    LD D,[HL]
    INC HL
    LD [DE],A                       ; its mode: closed
    DEC B
    JP NZ,INIFIL_1
    CALL CLSALL                     ; close all files
    XOR A                           ; zero set, so NEW's RET NZ falls through

;; Runs NEW: erases the program and clears all variables.
;;
;; The line before it, at the end of Console.asm, ends with XOR A and falls in here with zero set.
;; In:    zero = set at the end of the statement
;; Entry: SCRTCH = erases the program without checking for the end of the statement
ST_NEW:
    RET NZ                          ; NEW takes no argument: leave it to the syntax check
SCRTCH:
    LD HL,[TXTTAB]
    CALL ST_TROFF                   ; trace off, and A = 0
    LD [PROFLG],A                   ; no longer a protected program
    LD [AUTFLG],A                   ; AUTO off
    LD [PTRFLG],A                   ; no line numbers have been turned into pointers
    LD [HL],A                       ; a zero link: the program is empty
    INC HL
    LD [HL],A
    INC HL
    LD [VARTAB],HL                  ; the variables start right after it

;; Clears the variables, strings and DATA pointer, and resets the stack, to run from the program's start.
;; Out:   HL = TXTTAB-1, the text pointer before the first line, A = 0
RUNC:
    LD HL,[TXTTAB]
    DEC HL                          ; just before the first line, as NEWSTT expects

;; Clears the variables, arrays and strings, the ON ERROR state and the DATA pointer, and resets the stack.
;;
;; Unless a CHAIN MERGE is under way (MRGFLG), it also forgets OPTION BASE, makes every letter single
;; precision and closes the files. A CHAIN (CHNFLG) keeps the strings, which it has moved out of the way.
;; It falls into STKINI, which replaces the caller's stack.
;; In:    HL = the text pointer to hand back
;; Out:   HL = the same text pointer, A = 0
CLEARC:
    LD [TEMP],HL                    ; GTMPRT returns it
    LD A,[MRGFLG]                   ; a CHAIN MERGE keeps the default types
    OR A
    JP NZ,LEVDTB
    XOR A
    LD [OPTFLG],A                   ; no OPTION BASE seen
    LD [OPTVAL],A                   ; OPTION BASE 0
    LD B,$1A                        ; one type for each letter, A to Z
    LD HL,DEFTBL

;; Sets each of the 26 letters' default types to single precision, the loop of CLEARC.
LOPDFT:
    LD [HL],$04                     ; 4 = single precision
    INC HL
    DEC B
    JP NZ,LOPDFT

;; Restarts the random numbers and clears the rest of the variables, the part of CLEARC a CHAIN MERGE does too.
LEVDTB:
    LD DE,RNDINI                    ; the first seed
    LD HL,RNDX
    CALL MOVE                       ; RNDX = the seed again
    LD HL,RNDCNT
    XOR A
    LD [HL],A                       ; and the generator's three counters back to zero
    INC HL
    LD [HL],A
    INC HL
    LD [HL],A
    XOR A
    LD [ONEFLG],A                   ; not inside an error trap
    LD L,A
    LD H,A
    LD [ONELIN],HL                  ; no ON ERROR GOTO line
    LD [OLDTXT],HL                  ; nothing to CONTinue
    LD HL,[MEMSIZ]
    LD A,[CHNFLG]                   ; a CHAIN keeps its strings
    OR A
    JP NZ,GODFRE
    LD [FRETOP],HL                  ; the string space is empty

;; Resets the DATA pointer and empties the simple variables and arrays, the end of CLEARC.
GODFRE:
    XOR A                           ; zero: RESTORE to the start of the program
    CALL ST_RESTORE
    LD HL,[VARTAB]
    LD [ARYTAB],HL                  ; no simple variables
    LD [STREND],HL                  ; no arrays
    LD A,[MRGFLG]                   ; a CHAIN MERGE leaves the files open
    OR A
    CALL Z,CLSALL

;; Resets the stack, discarding FOR, GOSUB and WHILE entries, and the string temporaries.
;;
;; It also turns off output to the printer or a file, frees the user functions' parameters and allows subscripts
;; again. The new stack starts with a zero word, so FNDFOR always stops at a non-FOR entry at its bottom.
;; In:    TEMP = the value to return in HL
;; Out:   HL = TEMP, A = 0
STKINI:
    POP BC                          ; BC = the caller's return address
    LD HL,[TOPMEM]
    DEC HL                          ; room for the zero word
    DEC HL
    LD [SAVSTK],HL                  ; the stack an error recovers to
    INC HL
    INC HL

;; Sets the stack pointer to HL and finishes STKINI's reset.
;; In:    HL = the new stack top, BC = the address to return to, TEMP = the value to return in HL
;; Out:   HL = TEMP, A = 0
STKERR:
    LD SP,HL
    LD HL,TEMPST
    LD [TEMPPT],HL                  ; no string temporaries
    CALL CLROVC                     ; overflows print their message again
    CALL FINLPT                     ; end any line on the printer
    CALL FINPRT                     ; output back to the console
    XOR A
    LD H,A
    LD L,A
    LD [PRMLEN],HL                  ; no active parameters
    LD [NOFUNS],A                   ; no user function active
    LD [PRMLN2],HL                  ; no parameters being built
    LD [FUNACT],HL                  ; no functions active
    LD [PRMSTK],HL                  ; no parameter blocks on the stack
    LD [SUBFLG],A                   ; allow subscripts
    PUSH HL                         ; the zero word at the bottom of the stack
    PUSH BC                         ; and the return address on the new stack

;; Loads HL from TEMP and returns.
;; Out:   HL = TEMP
;; Keeps: AF, BC, DE
GTMPRT:
    LD HL,[TEMP]
    RET

;; Compares HL with DE.
;; Out:   zero = set if HL = DE, carry = set if HL < DE
;; Uses:  A
;; Keeps: BC, DE, HL
DCOMPR:
    LD A,H
    SUB D                           ; the high bytes decide, unless they are equal
    RET NZ
    LD A,L
    SUB E
    RET

;; Checks that the text at HL is the character in the byte after the call, then fetches the next character.
;;
;; Called as CALL SYNCHR followed by the expected character, the 8080 source's SYNCHK. It returns past that
;; byte, and gives a Syntax error if the text does not match.
;; In:    HL = the text, the byte after the call = the character expected
;; Out:   HL = the next character's address, A = the next character, as CHRGTR returns it
;; Errors: Syntax error if the character is not there
SYNCHR:
    LD A,[HL]
    EX [SP],HL                      ; HL = the return address, at the expected character
    CP [HL]
    JP NZ,SYNERR
    INC HL                          ; return past it
    EX [SP],HL
    INC HL                          ; skip the matched character
    LD A,[HL]
    CP $3A
    RET NC                          ; not a digit or a space: no more to do
    JP CHRCON                       ; the rest of CHRGTR

;; Gives a Syntax error for SYNCHR.
SYNERR:
    JP SNERR

;; Runs RESTORE: points the DATA pointer at the start of the program, or at the given line.
;; In:    HL = the text after RESTORE, zero = set if no line number follows
;; Out:   HL = the text after the statement
;; Errors: Undefined line number if the line does not exist
ST_RESTORE:
    EX DE,HL                        ; keep the text pointer
    LD HL,[TXTTAB]
    JP Z,BGNRST                     ; no line number: the start of the program
    EX DE,HL
    CALL LINGET                     ; DE = the line number
    PUSH HL
    CALL FNDLIN                     ; BC = the line, carry = set if found
    LD H,B
    LD L,C
    POP DE                          ; DE = the text pointer
    JP NC,USERR                     ; no such line

;; Sets DATPTR to HL-1, just before a line, and returns with the text pointer in HL.
;; In:    HL = the line READ starts at, DE = the text pointer
;; Out:   HL = the text pointer, DE = the new DATPTR
;; Entry: RESFIN = sets DATPTR to HL itself, for READ's end
BGNRST:
    DEC HL
RESFIN:
    LD [DATPTR],HL                  ; READ finishes come here too
    EX DE,HL
    RET

;; Runs STOP: stops the program with the Break message, ready for CONT.
;; In:    zero = set at the end of the statement
ST_STOP:
    RET NZ                          ; STOP takes no argument
    INC A                           ; nonzero: print the Break message
    JP CONSTP

;; Runs END: closes the files and stops the program without a message.
;; In:    zero = set at the end of the statement
ST_END:
    RET NZ                          ; END takes no argument
    PUSH AF
    CALL Z,CLSALL
    POP AF                          ; zero again: no message

;; Saves the text pointer for CONT, frees the string temporaries and stops the program.
;; In:    HL = the text pointer, zero = clear to print the Break message
CONSTP:
    LD [SAVTXT],HL                  ; where CONT resumes
    LD HL,TEMPST
    LD [TEMPPT],HL                  ; discard the string temporaries
    .byte $21                       ; LD HL,nn: skips the OR $FF

;; Stops the program with the Break message, discarding the return address to NEWSTT: Control-C's entry.
;;
;; Microsoft's name for it is CONSTP, which this source gave CONSTP's address; see notes.
STPEND:
    OR $FF                          ; nonzero: print the Break message
    POP BC                          ; discard the return address to NEWSTT

;; Stops the program, remembering the line and statement for CONT unless in direct mode, and goes to Ready.
;; In:    CURLIN = the line, SAVTXT = the statement, zero = clear to print Break in the line
ENDCON:
    LD HL,[CURLIN]
    PUSH HL                         ; the line for Break in
    PUSH AF                         ; and whether to print it
    LD A,L
    AND H
    INC A                           ; line 65535 is direct mode
    JP Z,DIRIS                      ; which cannot be continued
    LD [OLDLIN],HL                  ; the line for CONT to resume in
    LD HL,[SAVTXT]
    LD [OLDTXT],HL                  ; and the statement

;; Finishes a stop: prints Break in the line if the saved flag is nonzero, else goes straight to Ready.
DIRIS:
    XOR A
    LD [CNTOFL],A                   ; cancel ^O, so the message is seen
    CALL FINLPT                     ; end any line on the printer
    CALL CRDONZ                     ; start a new line if the cursor is not at its start
    POP AF
    LD HL,BRKTXT
    JP NZ,ERRFIN                    ; "Break in" the line, then Ready
    JP STPRDY                       ; END: Ready without a message

;; Echoes ^O, for the Control-O that turns console output off and on.
CTROPT:
    LD A,$0F                        ; Control-O

;; Echoes a control character as ^ and its letter, then a new line.
;;
;; A Control-C also turns off output to the printer and cancels ^O.
;; In:    A = the control character
CTRLPT:
    PUSH AF
    SUB $03                         ; Control-C?
    JP NZ,NTCTCT
    LD [PRTFLG],A                   ; output back to the console
    LD [CNTOFL],A                   ; cancel ^O

;; Prints the ^ and the control character's letter, and a new line.
NTCTCT:
    LD A,$5E                        ; ^
    CALL OUTDO
    POP AF
    ADD A,$40                       ; the control character's letter
    CALL OUTDO
    JP CRDO

;; Runs CONT: resumes the program at the statement where it stopped, or gives a Can't continue error.
;; Out:   HL = the statement to resume at, CURLIN = its line
;; Errors: Can't continue if nothing stopped, or the program was changed
ST_CONT:
    LD HL,[OLDTXT]                  ; zero: nothing to continue
    LD A,H
    OR L
    LD DE,$0011                     ; error 17, Can't continue
    JP Z,ERROR
    EX DE,HL                        ; keep the resume position
    LD HL,[OLDLIN]
    EX DE,HL
    EX DE,HL
    LD [CURLIN],HL                  ; back in the line that stopped
    EX DE,HL                        ; HL = where to resume, then on to NEWSTT
    RET

;; Runs NULL: sets the number of nulls printed after each new line.
;; In:    HL = the text after NULL
ST_NULL:
    CALL GETBYT                     ; A = the count
    RET NZ                          ; it must end the statement
    INC A                           ; CRDO expects at least 1
    LD [NULCNT],A
    RET

;; Runs TRON: turns on the trace of line numbers.
ST_TRON:
    .byte $3E                       ; LD A,n: a nonzero A, skipping the XOR A

;; Runs TROFF: turns off the trace of line numbers.
;; Out:   A = 0 (from TROFF)
ST_TROFF:
    XOR A                           ; zero: no trace
    LD [TRCFLG],A
    RET

;; Runs SWAP: exchanges the values of two variables of the same type.
;; In:    HL = the text after SWAP
;; Out:   HL = the text after the second variable
;; Errors: Type mismatch if the types differ; Illegal function call if the second variable created an array
;;   entry that moved the first
ST_SWAP:
    CALL PTRGET                     ; DE = the first variable's value
    PUSH DE
    PUSH HL
    LD HL,SWPTMP
    CALL VMOVE                      ; SWPTMP = the first value
    LD HL,[ARYTAB]                  ; to notice the variables moving
    EX [SP],HL
    CALL GETYPR
    PUSH AF                         ; the first value's type
    CALL SYNCHR
    .byte ','
    CALL PTRGET                     ; DE = the second variable's value
    POP AF
    LD B,A
    CALL GETYPR                     ; the second value's type
    CP B
    JP NZ,TMERR
    EX [SP],HL                      ; HL = the old ARYTAB, keep the text pointer
    EX DE,HL
    PUSH HL                         ; the second value
    LD HL,[ARYTAB]
    CALL DCOMPR
    JP NZ,GFCERR                    ; creating the second variable moved the first
    POP DE
    POP HL
    EX [SP],HL                      ; HL = the first value, keep the text pointer
    PUSH DE
    CALL VMOVE                      ; the second value into the first
    POP HL
    LD DE,SWPTMP
    CALL VMOVE                      ; the first value into the second
    POP HL
    RET

;; Gives an Illegal function call error.
GFCERR:
    JP FCERR

;; Runs ERASE: deletes the named arrays, moving the arrays above each one down.
;; In:    HL = the text after ERASE
;; Out:   HL = the text after the last array
;; Errors: Illegal function call if an array is not dimensioned
ST_ERASE:
    LD A,$01
    LD [SUBFLG],A                   ; PTRGET: ERASE wants an array's entry
    CALL PTRGET                     ; BC = after the name, DE = the entry's length
    JP NZ,GFCERR                    ; no such array
    PUSH HL
    LD [SUBFLG],A                   ; A = 0 again
    LD H,B
    LD L,C                          ; HL = the array's data
    DEC BC                          ; back up over the type and length
    DEC BC
    DEC BC

;; Backs BC up over the array name's extra characters, which have bit 7 set, to the start of its entry.
LPBKNM:
    LD A,[BC]
    DEC BC
    OR A
    JP M,LPBKNM
    DEC BC
    DEC BC
    ADD HL,DE                       ; HL = the end of the array
    EX DE,HL
    LD HL,[STREND]

;; Moves the arrays from DE to STREND down to BC, over the erased array.
ERSLOP:
    CALL DCOMPR
    LD A,[DE]
    LD [BC],A
    INC DE
    INC BC
    JP NZ,ERSLOP
    DEC BC
    LD H,B
    LD L,C
    LD [STREND],HL                  ; the arrays end lower now
    POP HL
    LD A,[HL]
    CP $2C                          ; another array after a comma?
    RET NZ
    CALL CHRGTR
    JP ST_ERASE

;; Pops AF and HL and returns.
POPAHT:
    POP AF
    POP HL
    RET

;; Tests whether the character at HL is a letter.
;; In:    HL = the character
;; Out:   A = the character, carry = clear for a letter
;; Keeps: BC, DE, HL
ISLET:
    LD A,[HL]

;; Tests whether A is a letter.
;; In:    A = the character
;; Out:   carry = clear for a letter
;; Keeps: A, BC, DE, HL
ISLET2:
    CP $41                          ; below A
    RET C
    CP $5B                          ; above Z: carry clear, then set
    CCF
    RET

;; Goes on to CLEARC, for CLEAR.
GCLERC:
    JP CLEARC

;; Runs CLEAR: clears the variables, and can set the top of memory and the stack's size.
;;
;; The syntax is CLEAR [,[top][,stack]]. A first argument, the string space of older BASICs, is read and
;; ignored. The stack's size defaults to its present size.
;; In:    HL = the text after CLEAR, zero = set if nothing follows
;; Errors: Illegal function call for a size of 0; Out of memory if there is no room
ST_CLEAR:
    JP Z,GCLERC                     ; no arguments: just clear
    CP $2C
    JP Z,CSKPCM                     ; no first argument
    CALL INTID2                     ; the ignored first argument
    DEC HL
    CALL CHRGTR
    JP Z,GCLERC

;; Reads CLEAR's top of memory, after the comma.
CSKPCM:
    CALL SYNCHR
    .byte ','
    JP Z,GCLERC
    EX DE,HL
    LD HL,[TOPMEM]                  ; DE = the present top: the default
    EX DE,HL
    CP $2C
    JP Z,CLEARS                     ; no top given
    CALL GETMPM                     ; DE = the new top of memory

;; Reads CLEAR's stack size, if there is one.
CLEARS:
    DEC HL
    CALL CHRGTR
    PUSH DE                         ; the new top
    JP Z,CDFSTK                     ; no stack size: keep the present one
    CALL SYNCHR
    .byte ','
    JP Z,CDFSTK
    CALL GETMPM                     ; DE = the stack size
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR                     ; nothing may follow

;; Checks the new top of memory and stack size, sets them and clears.
;; The new top of memory is on the stack, above the text pointer's place.
;; In:    DE = the stack size, HL = the text pointer
CLEART:
    EX [SP],HL                      ; keep the text pointer, HL = the new top
    PUSH HL
    LD HL,$004E                     ; the smallest stack allowed, 78 bytes
    CALL DCOMPR
    JP NC,GOMERR
    POP HL
    CALL SUBDE                      ; DE = the top less the stack: the stack's bottom
    JP C,GOMERR                     ; more stack than memory
    PUSH HL
    LD HL,[VARTAB]
    LD BC,$0014                     ; 20 bytes to spare above the program
    ADD HL,BC
    CALL DCOMPR
    JP NC,GOMERR                    ; no room: do not even clear
    EX DE,HL
    LD [MEMSIZ],HL                  ; the strings start below the stack
    POP HL
    LD [TOPMEM],HL                  ; the new top
    POP HL                          ; the text pointer
    JP GCLERC

;; Evaluates a memory size for CLEAR, which may not be zero.
;; In:    HL = the text
;; Out:   DE = the size, HL = the text after it
;; Errors: Illegal function call for zero
GETMPM:
    CALL FRMQNT                     ; DE = the expression's integer
    LD A,D
    OR E
    JP Z,FCERR
    RET

;; Gives an Out of memory error.
GOMERR:
    JP OMERR

;; Uses the present stack size, TOPMEM-MEMSIZ, as CLEAR's stack size.
CDFSTK:
    PUSH HL
    LD HL,[TOPMEM]
    EX DE,HL
    LD HL,[MEMSIZ]
    LD A,E                          ; DE = TOPMEM-MEMSIZ
    SUB L
    LD E,A
    LD A,D
    SBC A,H
    LD D,A
    POP HL
    JP CLEART

;; Subtracts DE from HL into DE.
;; In:    HL, DE = the numbers
;; Out:   DE = HL-DE, carry = set if DE was greater
;; Uses:  A
;; Keeps: BC, HL
SUBDE:
    LD A,L
    SUB E
    LD E,A
    LD A,H
    SBC A,D
    LD D,A
    RET

;; Runs NEXT: steps the loop variable and loops back to the FOR unless it passed its limit.
;;
;; Each variable of a comma list is stepped in turn. A FOR statement uses the same code, through NEXTS, to
;; check whether its loop runs at all: NXTFLG is then zero, and the variable is given its first value,
;; FVALSV, instead of being stepped.
;; In:    HL = the text after NEXT, zero = set if no variable follows
;; Errors: NEXT without FOR, and Overflow if an integer variable leaves the integer range
;; Entry: NEXTS = FOR's entry, with NXTFLG zero
ST_NEXT:
    PUSH AF
    .byte $F6                       ; OR n: a nonzero A, skipping the XOR A
NEXTS:
    XOR A                           ; zero: called from FOR
    LD [NXTFLG],A
    POP AF
    LD DE,$0000                     ; no variable: any FOR matches

;; Steps the loop variable at HL, the one in DE, or the innermost one if none is named.
;; In:    HL = the text, zero = set if no variable follows
NEXTC:
    LD [NXTTXT],HL                  ; this NEXT's text
    CALL NZ,PTRGET                  ; DE = the named variable
    LD [TEMP],HL                    ; the text after it, for LOOPDN
    CALL FNDFOR                     ; HL = the variable's FOR entry
    JP NZ,NFERR
    LD SP,HL                        ; discard the inner FOR and GOSUB entries
    PUSH DE
    LD E,[HL]                       ; DE = the entry's NEXT text pointer
    INC HL
    LD D,[HL]
    INC HL
    PUSH HL
    LD HL,[NXTTXT]
    CALL DCOMPR
    JP NZ,NFERR                     ; this FOR belongs to another NEXT
    POP HL
    POP DE
    PUSH DE                         ; the variable
    LD A,[HL]                       ; the sign of the STEP
    PUSH AF
    INC HL
    PUSH DE
    LD A,[HL]                       ; negative for an integer loop
    INC HL
    OR A
    JP M,INTNXT
    CALL MOVFM                      ; FAC = the STEP
    EX [SP],HL                      ; keep the entry pointer, HL = the variable
    PUSH HL
    LD A,[NXTFLG]                   ; FOR's check?
    OR A
    JP NZ,NXTDO
    LD HL,FVALSV
    CALL MOVFM                      ; FAC = the first value
    XOR A                           ; zero: do not add

;; Adds the variable to the STEP in the FAC, unless this is FOR's check, and compares it with the limit.
NXTDO:
    CALL NZ,FADDS                   ; FAC = the variable plus the STEP
    POP HL
    CALL MOVMF                      ; store it in the variable
    POP HL                          ; the entry, at the limit
    CALL MOVRM                      ; BCDE = the limit
    PUSH HL
    CALL FCOMP                      ; A = the sign of the variable less the limit
    JP FINNXT

;; Steps an integer loop variable, giving an Overflow error if it leaves the integer range.
INTNXT:
    INC HL                          ; skip the single precision STEP
    INC HL
    INC HL
    INC HL
    LD C,[HL]                       ; BC = the integer STEP
    INC HL
    LD B,[HL]
    INC HL
    EX [SP],HL                      ; keep the entry pointer, HL = the variable
    LD E,[HL]                       ; DE = its value
    INC HL
    LD D,[HL]
    PUSH HL
    LD L,C
    LD H,B
    LD A,[NXTFLG]                   ; FOR's check?
    OR A
    JP NZ,INXTDO
    LD HL,[FVALSV]                  ; the first value
    JP IFORIN

;; Adds the integer STEP in HL to the variable in DE.
INXTDO:
    CALL IADD
    LD A,[VALTYP]                   ; single precision after an overflow
    CP $04
    JP Z,OVERR

;; Stores the integer loop variable's new value and compares it with the limit.
;; In:    HL = the new value
IFORIN:
    EX DE,HL
    POP HL
    LD [HL],D                       ; store the new value
    DEC HL
    LD [HL],E
    POP HL                          ; the entry, at the limit
    PUSH DE
    LD E,[HL]                       ; DE = the limit
    INC HL
    LD D,[HL]
    INC HL
    EX [SP],HL                      ; keep the entry pointer, HL = the value
    CALL ICOMP                      ; A = the sign of the value less the limit

;; Ends the loop if the variable passed its limit, else continues after the FOR statement.
;; The stack holds the entry pointer, then the STEP's sign.
;; In:    A = the sign of the variable less the limit
FINNXT:
    POP HL
    POP BC
    SUB B                           ; zero when the variable is past the limit
    CALL MOVRM                      ; DE = the FOR's line, BC = its text
    JP Z,LOOPDN
    EX DE,HL
    LD [CURLIN],HL                  ; back to the FOR's line
    LD L,C
    LD H,B
    JP NXTCON                       ; run the loop's body again

;; Drops the finished FOR entry and runs the next statement, or steps the next variable after a comma.
LOOPDN:
    LD SP,HL                        ; drop the FOR entry
    LD [SAVSTK],HL
    LD HL,[TEMP]                    ; the text after the variable
    LD A,[HL]
    CP $2C                          ; another variable?
    JP NZ,NEWSTT
    CALL CHRGTR
    CALL NEXTC                      ; never returns: the call is for FNDFOR's sake

;; Tests whether output is going to a file.
;; Out:   zero = clear if it is, PTRFIL being nonzero
;; Uses:  A
;; Keeps: BC, DE, HL
ISFLIO:
    PUSH HL
    LD HL,[PTRFIL]
    LD A,H
    OR L
    POP HL
    RET
