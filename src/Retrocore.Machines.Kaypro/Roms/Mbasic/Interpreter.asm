;; MBASIC 5.21: THE INTERPRETER'S CORE: FNDFOR, ERRORS, READY, MAIN, LINE LINKS AND SEARCH, AND CRUNCH
;;
;; The start of BINTRP, Microsoft's interpreter, from FNDFOR to BAKSP in the order GW-BASIC's GWMAIN.ASM keeps
;; (its "general storage management", "error handling", "STPRDY, READY, MAIN, CHEAD", "SCNLIN, FNDLIN" and
;; "fast crunch" parts). Level2.asm has most of the same routines for the TRS-80. In order:
;;
;; - FNDFOR searches the stack for a FOR entry, for FOR, NEXT and RETURN, stepping over WHILE entries.
;; - The error entries load an error code into E for ERROR: PRGEND (No RESUME at the end of the program), the
;;   disk errors DERDFL to DERFAE, then SNERR to TMERR. ERROR records the line for ERL, resets the stack
;;   (ERESET, through STKERR) and goes on in ERRMOR. ERRMOR records the error for ERR, RESUME and CONT, then
;;   jumps to the ON ERROR GOTO line, or finds the message in ERRTAB and prints it through ERRFIN.
;; - READY prints Ok and falls into MAIN, the command loop. MAIN reads a line, with the next AUTO line number as
;;   its prompt, and crunches it (EDENT). A line without a number runs at once (DIRDO, then GONE); one with a
;;   number replaces the program line with that number, or is inserted before the next higher one (INONLY to
;;   FINI), after which the variables are cleared (RUNC).
;; - CHEAD (and LINKER, from the start) rebuilds the lines' links. SCNLIN reads a line range for LIST and
;;   DELETE, and FNDLIN finds a line by its number.
;; - CRUNCH tokenizes a line into KBUF: reserved words through ALPTAB, with functions as $FF and a second byte;
;;   operators and other characters through SPCTAB; numbers as binary constants; and the numbers after the
;;   words in LINRES as line-number constants. Strings, DATA and REM are copied as typed.
;;
;; Runs at $0C50-$11BE. Its main entry points are FNDFOR and LOOPER, ERROR and the xxERR entries, ERRESM and
;; ERESET, ERRFIN, STPRDY, READY, READYR, MAIN, EDENT (where EDIT and AUTO hand over a line), LINKER, CHEAD,
;; SCNLIN, FNDLN1, FNDLIN and LOOP, CRUNCH, KRNSAV and BAKSP.

; Sizes.
KBFLEN = $013E ;; the length of KBUF, the buffer CRUNCH writes a line into

;; Searches the stack for the FOR entry of the loop variable at DE, or of the innermost loop when DE is 0.
;;
;; Remarks: The search starts past FNDFOR's return address and its caller's. It steps over WHILE entries (the
;; WHILE token and 6 bytes) and the FOR entries of other variables, and stops at any other entry, such as a
;; GOSUB's. A FOR entry is the FOR token, the loop variable's address, then 16 more bytes.
;;
;; In:    DE = the loop variable's address, or 0 for any loop
;; Out:   zero = set when found, HL = the FOR entry past its variable's address, BC = 16 (the rest of the
;;   entry), DE = the entry's variable when DE was 0; when not found, A = the token of the entry that ended
;;   the search, HL = the entry past its token
;; Entry: LOOPER = searches from the entry at HL
;; Uses:  A, BC, DE, HL
FNDFOR:
    LD HL,$0004                     ; skip the two return addresses
    ADD HL,SP
LOOPER:
    LD A,[HL]                       ; A = the entry's token
    INC HL
    CP $B4                          ; the WHILE token
    JP NZ,STKSRC
    LD BC,$0006                     ; step over the WHILE entry
    ADD HL,BC
    JP LOOPER
STKSRC:
    CP $82                          ; the FOR token
    RET NZ                          ; any other entry ends the search
    LD C,[HL]                       ; BC = the loop variable's address
    INC HL
    LD B,[HL]
    INC HL
    PUSH HL
    LD H,B
    LD L,C
    LD A,D                          ; DE = 0 matches any FOR
    OR E
    EX DE,HL                        ; DE = this loop's variable
    JP Z,POPGOF
    EX DE,HL
    CALL DCOMPR                     ; zero when it is the variable in DE
POPGOF:
    LD BC,$0010                     ; from here to the next entry
    POP HL
    RET Z                           ; found
    ADD HL,BC
    JP LOOPER

;; Resets the stack from SAVSTK and goes to STPRDY, which prints Ok and enters MAIN.
;;
;; Remarks: INIT hands this address to INITSA as where BASIC starts.
READYR:
    LD BC,STPRDY                    ; where ERESET goes on
    JP ERESET

;; Ends a run that has gone past the program's last line, with a No RESUME error (19) if an ON ERROR handler
;; is still running.
PRGEND:
    LD HL,[CURLIN]
    LD A,H
    AND L
    INC A                           ; zero in direct mode, line $FFFF
    JP Z,ENDCNJ
    LD A,[ONEFLG]                   ; nonzero while a handler runs
    OR A
    LD E,$13                        ; No RESUME
    JP NZ,ERROR
ENDCNJ:
    JP ENDCON

;; Reports a Disk full error (61) through <ERROR>.
DERDFL:
    LD E,$3D
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a Disk I/O error (57) through <ERROR>.
DERDIO:
    LD E,$39
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a Bad file mode error (54) through <ERROR>.
DERBFM:
    LD E,$36
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a File not found error (53) through <ERROR>.
DERFNF:
    LD E,$35
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a Bad file number error (52) through <ERROR>.
DERBFN:
    LD E,$34
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports an Internal error (51) through <ERROR>.
DERIER:
    LD E,$33
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports an Input past end error (62) through <ERROR>.
DERRPE:
    LD E,$3E
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a File already open error (55) through <ERROR>.
DERFAO:
    LD E,$37
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a Bad file name error (64) through <ERROR>.
DERIFN:
    LD E,$40
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a Bad record number error (63) through <ERROR>.
DERBRN:
    LD E,$3F
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a FIELD overflow error (50) through <ERROR>.
DERFOV:
    LD E,$32
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a Too many files error (67) through <ERROR>.
DERTMF:
    LD E,$43
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a File already exists error (58) through <ERROR>.
DERFAE:
    LD E,$3A
    JP ERROR

;; Reports a Syntax error in a DATA statement against the DATA line (DATLIN), not the line READ is on.
;;
;; Remarks: Nothing in MBASIC jumps here.
DATSNE:
    LD HL,[DATLIN]
    LD [CURLIN],HL                  ; report the error against the DATA line

;; Reports a Syntax error (2) through <ERROR>.
SNERR:
    LD E,$02
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a Division by zero error (11) through <ERROR>.
DV0ERR:
    LD E,$0B
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a NEXT without FOR error (1) through <ERROR>.
NFERR:
    LD E,$01
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a Duplicate Definition error (10) through <ERROR>.
DDERR:
    LD E,$0A
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports an Undefined user function error (18) through <ERROR>.
UFERR:
    LD E,$12
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a RESUME without error error (20) through <ERROR>.
REERR:
    LD E,$14
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports an Overflow error (6) through <ERROR>.
OVERR:
    LD E,$06
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a Missing operand error (22) through <ERROR>.
MOERR:
    LD E,$16
    .byte $01                       ; LD BC,nn: skips the next LD E

;; Reports a Type mismatch error (13) through <ERROR>.
TMERR:
    LD E,$0D

;; Reports the error whose code is in E: records its line for ERL, then resets the stack and goes on in
;; <ERRMOR>.
;;
;; Remarks: An error also ends any CHAIN or MERGE (it clears MRGFLG and CHNFLG). In a program, the line becomes
;; the current line (DOT) for LIST . and EDIT ..
;;
;; In:    E = the error code
;; Entry: ERRESM = leaves ERRLIN, DOT and the CHAIN and MERGE flags as they are, ERESET = resets the stack
;;   and goes on at BC instead of ERRMOR
ERROR:
    LD HL,[CURLIN]
    LD [ERRLIN],HL                  ; the line ERL returns
    XOR A
    LD [MRGFLG],A                   ; end any MERGE
    LD [CHNFLG],A                   ; and any CHAIN
    LD A,H
    AND L
    INC A                           ; zero in direct mode, line $FFFF
    JP Z,ERRESM
    LD [DOT],HL
ERRESM:
    LD BC,ERRMOR                    ; where ERESET goes on
ERESET:
    LD HL,[SAVSTK]                  ; the stack as it was at the statement's start
    JP STKERR

;; Records the error for ERR, RESUME and CONT, then runs the ON ERROR GOTO handler, or prints the error's
;; message and returns to command level.
;;
;; Remarks: Entered on the stack that STKERR has reset. A handler takes the error unless one is running
;; already (ONEFLG), when the error is fatal. Otherwise the message is found in ERRTAB by counting its zero
;; bytes: codes 1 to 30 are the general errors, codes 50 to 67 the disk errors, which follow them in the table,
;; and any other code is Unprintable error (21).
;;
;; In:    E = the error code
ERRMOR:
    POP BC                          ; the zero word STKERR left
    LD A,E
    LD C,E                          ; C keeps the code
    LD [ERRFLG],A                   ; the code ERR returns
    LD HL,[SAVTXT]                  ; the failing statement
    LD [ERRTXT],HL                  ; where RESUME restarts
    EX DE,HL
    LD HL,[ERRLIN]
    LD A,H
    AND L
    INC A                           ; zero in direct mode, line $FFFF
    JP Z,NTMDCN                     ; a direct line can't be continued
    LD [OLDLIN],HL                  ; where CONT goes on
    EX DE,HL
    LD [OLDTXT],HL
NTMDCN:
    LD HL,[ONELIN]                  ; the ON ERROR GOTO line, 0 if none
    LD A,H
    OR L
    EX DE,HL                        ; DE = the handler line
    LD HL,ONEFLG
    JP Z,NOTRAP                     ; no ON ERROR GOTO
    AND [HL]
    JP NZ,NOTRAP                    ; an error in the handler is fatal
    DEC [HL]                        ; ONEFLG = $FF: the handler runs
    EX DE,HL
    JP GONE4                        ; run the handler line
NOTRAP:
    XOR A
    LD [HL],A                       ; no handler runs
    LD E,C                          ; E = the error code
    LD [CNTOFL],A                   ; end any Control-O, so the message shows
    CALL CRDONZ                     ; start a new line if needed
    LD HL,ERRTAB
    LD A,E
    CP $44                          ; past the last disk error
    JP NC,UPERR
    CP $32                          ; a disk error
    JP NC,NTDER2
    CP $1F                          ; a general error
    JP C,LEPSKP
UPERR:
    LD A,$28                        ; less $13 below: 21, Unprintable error
NTDER2:
    SUB $13                         ; a disk error's message follows the 30 general ones
    LD E,A
LEPSKP:
    CALL ST_REM                     ; HL = the next zero byte
    INC HL
    DEC E
    JP NZ,LEPSKP
    PUSH HL                         ; under it, the error's line
    LD HL,[ERRLIN]
    EX [SP],HL

;; Prints the message at HL, then " in " and the error's line unless in direct mode, then Ok.
;;
;; Remarks: The error's line number is on the stack's top. A message that starts with a question mark is a gap
;; in ERRTAB, printed as Unprintable error instead. Line $FFFE marks an error during INIT: BASIC then returns to
;; CP/M through CPMEXT.
;;
;; In:    HL = the message
ERRFIN:
    LD A,[HL]
    CP '?'                          ; a gap in ERRTAB
    JP NZ,ERRFN1
    POP HL
    LD HL,ERRTAB
    JP UPERR
ERRFN1:
    CALL STROUT                     ; print the message
    POP HL                          ; HL = the error's line
    LD DE,$FFFE                     ; INIT's line
    CALL DCOMPR
    CALL Z,CRDO                     ; during INIT: end the line
    JP Z,CPMEXT                     ; and return to CP/M
    LD A,H
    AND L
    INC A                           ; zero in direct mode, line $FFFF
    CALL NZ,INPRT                   ; print " in " and the line
    .byte $3E                       ; LD A,n: skips the POP BC

;; Discards the stack's top entry, then prints Ok and enters <MAIN> (<READY>).
STPRDY:
    POP BC

;; Finishes any printer and file output, prints Ok and enters <MAIN>, editing the line of a Syntax error.
;;
;; Remarks: The CALL that prints Ok is CALL $0000, a CP/M warm boot, until INIT stores STROUT's address in
;; REPCAL. After a Syntax error in a program line, ERREDT starts EDIT on that line.
READY:
    CALL FINLPT                     ; finish any line on the printer
    XOR A
    LD [CNTOFL],A                   ; end any Control-O
    CALL PRGFIN                     ; finish any file output
    CALL CRDONZ                     ; start a new line if needed
    LD HL,REDDY                     ; "Ok"
REPCAL = * + 1 ;; the address READY calls to print Ok: 0 until INIT stores STROUT's in it
    CALL $0000
    LD A,[ERRFLG]                   ; the last error's code
    SUB $02                         ; Syntax error
    CALL Z,ERREDT                   ; edit the line it was in

;; The command loop: reads a line, runs it when it has no line number, and otherwise stores it in the program.
;;
;; Remarks: With AUTO on, the prompt is the next AUTO line number and a star if that line exists, else a space.
;; Control-C then ends AUTO; otherwise AUTLIN moves on by AUTINC (AUTO ends past 65529) and the line, unless it
;; is empty, is stored through EDITRT. Without AUTO, Control-C and empty lines are ignored, and the line
;; number, if any, is read before CRUNCH runs (EDENT).
MAIN:
    LD HL,$FFFF                     ; line $FFFF is direct mode
    LD [CURLIN],HL
    LD A,[AUTFLG]
    OR A
    JP Z,NTAUTO
    LD HL,[AUTLIN]                  ; HL = the next AUTO line number
    PUSH HL
    CALL LINPRT                     ; as the prompt
    POP DE
    PUSH DE
    CALL FNDLIN                     ; carry when that line exists
    LD A,'*'
    JP C,AUTELN
    LD A,' '
AUTELN:
    CALL OUTDO
    CALL INLIN                      ; read the line into BUF
    POP DE                          ; DE = the line number
    JP NC,AUTGOD                    ; not Control-C
    XOR A                           ; Control-C ends AUTO
    LD [AUTFLG],A
    JP READY
AUTRES:
    XOR A                           ; the numbers ran out: end AUTO, but store this line
    LD [AUTFLG],A
    JP AUTGOD_1
AUTGOD:
    LD HL,[AUTINC]
    ADD HL,DE                       ; HL = the next AUTO line number
    JP C,AUTRES                     ; past 65535
    PUSH DE
    LD DE,$FFF9                     ; 65529, the last AUTO may offer
    CALL DCOMPR
    POP DE
    JP NC,AUTRES
    LD [AUTLIN],HL
AUTGOD_1:
    LD A,[BUF]                      ; the line's first character
    OR A
    JP Z,MAIN                       ; an empty line is not stored
    JP EDITRT                       ; store it under the number in DE
NTAUTO:
    CALL INLIN                      ; read the line into BUF
    JP C,MAIN                       ; Control-C
    CALL CHRGTR                     ; carry when it starts with a digit
    INC A                           ; zero for an empty line, carry kept
    DEC A
    JP Z,MAIN
    PUSH AF                         ; carry = the line has a number
    CALL LINGET                     ; DE = the line number, 0 if none
    CALL BAKSP
    LD A,[HL]
    CP ' '                          ; drop one space after the number
    CALL Z,INXHRT

;; Crunches the line at HL, runs it when it has no line number, and otherwise puts it into the program.
;;
;; Remarks: The caller has pushed AF with carry set when the line has a number. Such a line replaces the line
;; with that number, or is inserted before the next higher one. A number alone deletes its line, with an
;; Undefined line number error (USERR) when there is none. A protected program (PROCHK) can't be changed. The
;; program's line pointers are made line numbers again first (DEPTR), and the variables are cleared after
;; (RUNC). RUNC closes the files, so file 0, which LOAD reads a program from, is made to look closed while it
;; runs, and the current file (PTRFIL) is kept. It does not return: it ends in GONE or MAIN.
;;
;; In:    HL = the line, past any line number, DE = the line number
EDENT:
    PUSH DE
    CALL CRUNCH                     ; BC = the line's length in the program
    POP DE
    POP AF                          ; carry = the line has a number
    LD [SAVTXT],HL                  ; for resuming a direct statement
    JP NC,DIRDO                     ; none: run it
    PUSH DE                         ; the line number
    PUSH BC                         ; and the length
    CALL PROCHK                     ; a protected program can't be listed or changed
    CALL CHRGTR                     ; zero when only the number was typed
    OR A
    PUSH AF
    EX DE,HL
    LD [DOT],HL                     ; the line becomes the current line
    EX DE,HL
    CALL FNDLIN                     ; BC = the line, or where it goes
    JP C,INONLY                     ; it exists
    POP AF
    PUSH AF
    JP Z,USERR                      ; deleting a line that isn't there
    OR A                            ; carry clear: nothing to delete
INONLY:
    PUSH BC
    PUSH AF
    PUSH HL
    CALL DEPTR                      ; make line pointers line numbers again
    POP HL
    POP AF
    POP BC
    PUSH BC                         ; the place to insert
    CALL C,DEL                      ; delete the old line
    POP DE                          ; DE = the place to insert
    POP AF                          ; zero = a number alone
    PUSH DE                         ; where FINI starts relinking
    JP Z,FINI
    POP DE
    LD A,[CHNFLG]                   ; while CHAINing, keep the strings
    OR A
    JP NZ,LEVFRE
    LD HL,[MEMSIZ]                  ; drop the strings, so BLTU has the room
    LD [FRETOP],HL
LEVFRE:
    LD HL,[VARTAB]                  ; the program's end
    EX [SP],HL                      ; HL = the length, in its place the end
    POP BC                          ; BC = the old end
    PUSH HL
    ADD HL,BC                       ; HL = the new end
    PUSH HL
    CALL BLTU                       ; move the rest of the program up
    POP HL
    LD [VARTAB],HL
    EX DE,HL                        ; HL = the new line
    LD [HL],H                       ; a nonzero link, so CHEAD goes on
    POP BC                          ; BC = the length
    POP DE                          ; DE = the line number
    PUSH HL                         ; where FINI starts relinking
    INC HL
    INC HL
    LD [HL],E                       ; the line number
    INC HL
    LD [HL],D
    INC HL
    LD DE,KBUF                      ; the crunched line
    DEC BC                          ; less the link and number
    DEC BC
    DEC BC
    DEC BC
MLOOPR:
    LD A,[DE]
    LD [HL],A
    INC HL
    INC DE
    DEC BC
    LD A,C
    OR B
    JP NZ,MLOOPR

;; Finishes a change to the program: relinks the lines from the one changed, clears the variables and goes back
;; to MAIN.
;;
;; File 0, which LOAD may be reading the program from, is made to look closed while RUNC clears the variables, and
;; the current file is kept, so that loading goes on. The caller pushes the first line whose link may be wrong.
FINI:
    POP DE                          ; the first line whose link may be wrong
    CALL CHEAD
    LD HL,TBUFF                     ; a zero byte in CP/M's buffer
    LD [HL],$00
    LD [FILPTR],HL                  ; file 0, which LOAD reads, looks closed
    LD HL,[PTRFIL]                  ; keep the current file
    LD [TEMP2],HL
    CALL RUNC                       ; clear the variables
    LD HL,[FILPT0]                  ; file 0's own block again
    LD [FILPTR],HL
    LD HL,[TEMP2]
    LD [PTRFIL],HL
    JP MAIN

;; Rebuilds the links of all the program's lines (<CHEAD> from TXTTAB).
LINKER:
    LD HL,[TXTTAB]
    EX DE,HL

;; Rebuilds the links of the program's lines from the line at DE to the end.
;;
;; Remarks: A line ends at its zero byte. Embedded constants (tokens $0B to $1F) are stepped over through
;; CHRGTR, so that a zero byte in a number does not end the line.
;;
;; In:    DE = the first line to relink
CHEAD:
    LD H,D
    LD L,E
    LD A,[HL]                       ; a zero link ends the program
    INC HL
    OR [HL]
    RET Z
    INC HL                          ; skip the line number
    INC HL
CZLOOP:
    INC HL
    LD A,[HL]
CZLOO2:
    OR A
    JP Z,CZLIN                      ; the line's end
    CP $20                          ; past the last constant token
    JP NC,CZLOOP
    CP $0B                          ; before the first
    JP C,CZLOOP
    CALL CHRGT2                     ; take in the constant
    CALL CHRGTR                     ; and step past it
    JP CZLOO2
CZLIN:
    INC HL                          ; HL = the next line
    EX DE,HL
    LD [HL],E                       ; store the link
    INC HL
    LD [HL],D
    JP CHEAD

;; Reads a line range (n, n-, -n, n-m or nothing) for LIST and DELETE, then finds its first line.
;;
;; Remarks: The range's last line number, 65530 when none is given, is left on the stack's top for the caller.
;;
;; In:    HL = the text, at the range, zero = set when the statement ends there
;; Out:   DE = the first line number, BC = that line or the next, carry = set when it exists (<FNDLIN>)
;; Errors: Syntax error after the range
SCNLIN:
    LD DE,$0000                     ; from the start
    PUSH DE
    JP Z,ALLLST                     ; no range: all of it
    POP DE
    CALL LINSPC                     ; DE = the first line number
    PUSH DE
    JP Z,SNGLIN                     ; that line alone
    CALL SYNCHR                     ; a dash must follow
    .byte $F3                       ; the minus token
ALLLST:
    LD DE,$FFFA                     ; 65530: to the end
    CALL NZ,LINSPC                  ; DE = the last line number
    JP NZ,SNERR
SNGLIN:
    EX DE,HL                        ; HL = the last line number
    POP DE                          ; DE = the first

;; Leaves HL on the stack under the return address, then finds the line DE (<FNDLIN>).
FNDLN1:
    EX [SP],HL
    PUSH HL

;; Finds the program line whose number is in DE.
;;
;; Out:   carry = set when found: BC = the line, HL = the next line; else BC = the first line with a higher
;;   number, HL = the line after that, or, past the program's end (zero = set), BC = HL = its zero link
;; Entry: LOOP = searches from the line at HL
;; Uses:  A
;; Keeps: DE
FNDLIN:
    LD HL,[TXTTAB]
LOOP:
    LD B,H                          ; BC = this line
    LD C,L
    LD A,[HL]                       ; a zero link ends the program
    INC HL
    OR [HL]
    DEC HL
    RET Z                           ; not found
    INC HL
    INC HL
    LD A,[HL]                       ; HL = the line's number
    INC HL
    LD H,[HL]
    LD L,A
    CALL DCOMPR                     ; compare it with DE
    LD H,B                          ; HL = the next line
    LD L,C
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    CCF
    RET Z                           ; found: carry set
    CCF
    RET NC                          ; past it: carry clear
    JP LOOP

;; Crunches the line at HL into KBUF: reserved words become tokens and numbers binary constants.
;;
;; Remarks: Strings, and the rest of a DATA statement or of a remark, are copied as typed. A number is a line
;; number after a word in LINRES (DONUM = 1), stored as token $0E and two bytes, and otherwise a constant:
;; tokens $11 to $1A for 0 to 9, $0F and a byte for 10 to 255, then $1C, $1D and $1F with 2, 4 and 8 bytes
;; for other integers, single and double precision. Digits in a variable's name (DONUM = $FF) stay digits.
;;
;; GO TO and GO SUB may have spaces after GO. GO and a space are matched first (GOSTEX), then CHRGTR steps
;; over the next character and any spaces after it. So GO SUB with one space matches UB (SUBTEX), while GO TO
;; with one space is left to its own entry in ALPTAB (O TO). With more spaces, GO TO matches TO (TOTEX), but
;; that jump lands on the load of GOSUB's token: as assembled, GO TO with two or more spaces crunches as GOSUB.
;;
;; In:    HL = the line, ending in a zero byte
;; Out:   KBUF = the crunched line and three zero bytes, HL = KBUF-1, BC = the line's length in the program:
;;   the bytes crunched plus 5, for its zero byte, link and line number
;; Errors: Line buffer overflow when KBUF fills
CRUNCH:
    XOR A
    LD [DONUM],A                    ; numbers are constants
    LD [DORES],A                    ; crunch words
    LD BC,KBFLEN-3                  ; BC = the room left, less the three zeros
    LD DE,KBUF
KLOOP:
    LD A,[HL]
    OR A
    JP NZ,NCRDON
CRDONE:
    LD HL,KBFLEN+2                  ; BC = KBFLEN+2 less the room left
    LD A,L
    SUB C
    LD C,A
    LD A,H
    SBC A,B
    LD B,A
    LD HL,KBUF-1                    ; GONE fetches the first byte with CHRGTR
    XOR A
    LD [DE],A                       ; the line's zero byte
    INC DE
    LD [DE],A                       ; and a zero link, so a direct line looks like the program's end
    INC DE
    LD [DE],A
    RET
NCRDON:
    CP '"'
    JP Z,STRNG                      ; copy a string as typed
    CP ' '
    JP Z,STUFFH
    LD A,[DORES]                    ; in DATA: copy as typed
    OR A
    LD A,[HL]
    JP Z,NTDATA
STUFFH:
    INC HL
    PUSH AF
    CALL KRNSAV
    POP AF
    SUB ':'                         ; a colon starts crunching again
    JP Z,COLIS
    CP $4A                          ; the DATA token less the colon
    JP NZ,NODATT
    LD A,$01                        ; DATA: copy the rest as typed
COLIS:
    LD [DORES],A
    LD [DONUM],A
NODATT:
    SUB $55                         ; the REM token less the colon
    JP NZ,KLOOP
    PUSH AF                         ; REM: copy to the line's end (terminator 0)
KRNSTR:
    LD A,[HL]
    OR A
    EX [SP],HL                      ; A = the terminator, from the pushed AF
    LD A,H
    POP HL
    JP Z,CRDONE                     ; the line ended
    CP [HL]
    JP Z,STUFFH                     ; the terminator ends the copy
STRNG:
    PUSH AF                         ; A = the terminator
    LD A,[HL]
STRNG2:
    INC HL
    CALL KRNSAV
    JP KRNSTR
NTDATA:
    CP '?'                          ; ? for PRINT
    LD A,$91                        ; the PRINT token
    PUSH DE
    PUSH BC
    JP Z,NOTFN2
    LD DE,SPCTAB
    CALL MAKUPL                     ; uppercase
    CALL ISLET2                     ; carry when not a letter
    JP C,TSTNUM
    PUSH HL
    LD DE,GOSTEX                    ; GO TO and GO SUB may have spaces after GO
    CALL CHKRES
    JP NZ,NOTGOS
    CALL CHRGTR                     ; skip a character and any spaces
    LD DE,TOTEX
    CALL CHKRES
    LD A,$89                        ; the GOTO token
    JP Z,PUTGOS                     ; lands on the LD A below, so GO TO crunches as GOSUB
    LD DE,SUBTEX
    CALL CHKRES
    JP NZ,NOTGOS
PUTGOS:
    LD A,$8D                        ; the GOSUB token
    POP BC                          ; drop the saved text pointer
    JP NOTFN2

;; Compares the text at HL, in uppercase, with the zero-ended word at DE.
;;
;; In:    HL = the text, DE = the word
;; Out:   zero = set when it matches: HL = the text after it; else HL = the first character that differs
;; Uses:  A, C, DE
;; Keeps: B
CHKRES:
    LD A,[DE]
    OR A
    RET Z                           ; all of it matched
    LD C,A
    CALL MAKUPL                     ; uppercase
    CP C
    RET NZ
    INC HL
    INC DE
    JP CHKRES

; The words CRUNCH looks for after GO.
GOSTEX: .byte "GO ", 0 ;; GO and a space, which may start GO TO or GO SUB
TOTEX: .byte "TO", 0 ;; TO, after GO and two or more spaces
SUBTEX: .byte "UB", 0 ;; UB, after GO, a space and the S that CHRGTR steps over

;; Continues <CRUNCH> at a letter: looks for a reserved word in that letter's list in ALPTAB.
;;
;; Remarks: A word is found when it is followed by a character that can't continue a name, unless it ends in
;; a parenthesis or is FN or USR. Otherwise the text is a variable's name, copied in uppercase (NOTRES).
;; Functions are stored as $FF and their number with bit 7 set.
NOTGOS:
    POP HL
    CALL MAKUPL                     ; A = the letter, uppercase
    PUSH HL
    LD HL,ALPTAB
    SUB 'A'
    ADD A,A
    LD C,A
    LD B,$00
    ADD HL,BC
    LD E,[HL]                       ; DE = the letter's list
    INC HL
    LD D,[HL]
    POP HL
    INC HL                          ; the words are stored without their letter
TRYAGA:
    PUSH HL                         ; where this word's comparison starts
LOPPSI:
    CALL MAKUPL
    LD C,A                          ; C = the text's character
    LD A,[DE]
    AND $7F
    JP Z,NOTRES                     ; the list's end: not a reserved word
    INC HL
    CP C
    JP NZ,LOPSKP                    ; try the next word
    LD A,[DE]                       ; bit 7 marks the word's last letter
    INC DE
    OR A
    JP P,LOPPSI
    LD A,C
    CP '('                          ; TAB( and the like need no separator
    JP Z,ISRESW
    LD A,[DE]                       ; A = the token
    CP $D3                          ; FN
    JP Z,ISRESW
    CP $D2                          ; USR
    JP Z,ISRESW
    CALL MAKUPL
    CP '.'                          ; a dot continues a name
    JP Z,ISVARS
    CALL TSTANM                     ; carry clear for a letter or digit
ISVARS:
    LD A,$00
    JP NC,NOTRES                    ; part of a name
ISRESW:
    POP AF                          ; drop the start of the comparison
    LD A,[DE]                       ; A = the token
    OR A
    JP M,NOTFNT                     ; a statement or operator
    POP BC                          ; a function
    POP DE
    OR $80
    PUSH AF
    LD A,$FF                        ; functions follow $FF
    CALL KRNSAV
    XOR A
    LD [DONUM],A                    ; numbers are constants
    POP AF
    CALL KRNSAV
    JP KLOOP
LOPSKP:
    POP HL                          ; back to the start of the word
LOPSK2:
    LD A,[DE]                       ; skip to the word's last letter
    INC DE
    OR A
    JP P,LOPSK2
    INC DE                          ; and its token
    JP TRYAGA

;; Stores the token in A for <CRUNCH>, setting DONUM by whether a line number may follow it.
;;
;; Remarks: ELSE is stored after a colon, WHILE with a plus after it (so a number after WHILE isn't taken for
;; a signed constant), and an apostrophe as a colon, REM and the apostrophe, with the rest of the line as typed.
;; A & starts an octal or hexadecimal constant (&O, &H), stored as token $0B or $0C and two bytes.
;;
;; In:    A = the token, HL = the text after the word; the room left and KBUF's pointer are on the stack
;; Entry: NOTFN2 = HL at the word's last character, NOTRS6 = with A = DONUM's new value and the character
;;   pushed
NOTFNT:
    DEC HL                          ; STUFFH steps past it again
NOTFN2:
    PUSH AF
    LD DE,LINRES
    LD C,A
NOTFN3:
    LD A,[DE]
    OR A
    JP Z,NOTFN4                     ; not in the list
    INC DE
    CP C
    JP NZ,NOTFN3
    JP NOTRS2

;; The tokens a line number may follow, which NOTFN2 looks for, ending in 0.
LINRES:
    .byte $8C                       ; RESTORE
    .byte $AB                       ; AUTO
    .byte $AC                       ; RENUM
    .byte $AA                       ; DELETE
    .byte $A7                       ; EDIT
    .byte $A9                       ; RESUME
    .byte $D6                       ; ERL
    .byte $A2                       ; ELSE
    .byte $8A                       ; RUN
    .byte $93                       ; LIST
    .byte $9F                       ; LLIST
    .byte $89                       ; GOTO
    .byte $CF                       ; THEN
    .byte $8D                       ; GOSUB
    .byte $00
NOTFN4:
    XOR A                           ; numbers are constants
    .byte $C2                       ; JP NZ,nn: never taken, skips the LD A
NOTRS2:
    LD A,$01                        ; numbers are line numbers
NOTRS6:
    LD [DONUM],A
    POP AF
    POP BC
    POP DE
    CP $A2                          ; the ELSE token
    PUSH AF
    CALL Z,KRNSVC                   ; a colon before ELSE
    POP AF
    CP $B4                          ; the WHILE token
    JP NZ,CKSNGQ
    CALL KRNSAV
    LD A,$F2                        ; the plus token after it
CKSNGQ:
    CP $DB                          ; the apostrophe's token
    JP NZ,NTSNGT
    PUSH AF
    CALL KRNSVC                     ; a colon
    LD A,$8F                        ; the REM token
    CALL KRNSAV
    POP AF
    PUSH AF                         ; the terminator for KRNSTR, never found
    JP STRNG2                       ; the apostrophe and the rest as typed

;; Continues <CRUNCH> at a character that is not a letter: a number, or a character in SPCTAB.
;;
;; In:    HL = the text, A = its character; the room left and KBUF's pointer are on the stack
TSTNUM:
    LD A,[HL]
    CP '.'                          ; a number may start with a dot
    JP Z,NUMTRY
    CP '9'+1
    JP NC,SRCSPC
    CP '0'
    JP C,SRCSPC
NUMTRY:
    LD A,[DONUM]
    OR A
    LD A,[HL]
    POP BC
    POP DE
    JP M,STUFFH                     ; a digit in a name
    JP Z,FLTGET                     ; a constant
    CP '.'                          ; LIST . and EDIT .
    JP Z,STUFFH
    LD A,$0E                        ; the line number token
    CALL KRNSAV
    PUSH DE
    CALL LINGET                     ; DE = the line number
    CALL BAKSP
SAVINT:
    EX [SP],HL                      ; HL = KBUF's pointer, the text pushed
    EX DE,HL                        ; HL = the number
SAVI:
    LD A,L
    CALL KRNSAV
    LD A,H
POPSTF:
    POP HL                          ; HL = the text
    CALL KRNSAV
    JP KLOOP

;; Crunches the number at HL as a constant, in the shortest form for its value and type.
;;
;; In:    HL = the text, A = its first character, DE = KBUF's pointer, BC = the room left
FLTGET:
    PUSH DE
    PUSH BC
    LD A,[HL]
    CALL FIN                        ; FAC = the number
    CALL BAKSP
    POP BC
    POP DE
    PUSH HL
    LD A,[VALTYP]
    CP $02
    JP NZ,NTINTG
    LD HL,[FACLO]                   ; an integer below 256
    LD A,H
    OR A
    LD A,$02
    JP NZ,NTINTG
    LD A,L
    LD H,L
    LD L,$0F                        ; token $0F and the byte
    CP $0A
    JP NC,SAVI
    ADD A,$11                       ; 0 to 9: tokens $11 to $1A
    JP POPSTF
NTINTG:
    PUSH AF                         ; A = VALTYP, the bytes to copy
    RRCA
    ADD A,$1B                       ; $1C, $1D or $1F for 2, 4 or 8 bytes
    CALL KRNSAV
    LD HL,FACLO                     ; from FACLO
    CALL GETYPR                     ; carry when not double precision
    JP C,NTDBL
    LD HL,DFACLO                    ; from DFACLO
NTDBL:
    POP AF
MOVCON:
    PUSH AF
    LD A,[HL]
    CALL KRNSAV
    POP AF
    INC HL
    DEC A
    JP NZ,MOVCON
    POP HL                          ; HL = the text
    JP KLOOP

;; Crunches a character that is not a letter or a number through SPCTAB: an operator's token, or the character.
;;
;; In:    HL = the text; the room left and KBUF's pointer are on the stack
SRCSPC:
    LD DE,SPCTAB-1
SRCSP2:
    INC DE
    LD A,[DE]                       ; the character, with bit 7 set
    AND $7F
    JP Z,NOTRS5                     ; not in the table
    INC DE
    CP [HL]
    LD A,[DE]                       ; A = its token
    JP NZ,SRCSP2
    JP NOTRS1

;; Stores the character or token in A, or for & an octal or hexadecimal constant (<NOTFNT> goes on here).
;;
;; In:    A = the character or token, HL = the text at it, DE = KBUF's pointer, BC = the room left
NTSNGT:
    CP '&'
    JP NZ,STUFFH
    PUSH HL
    CALL CHRGTR
    POP HL
    CALL MAKUPS                     ; uppercase
    CP 'H'
    LD A,$0B                        ; the octal token
    JP NZ,WUZOCT
    LD A,$0C                        ; the hexadecimal token
WUZOCT:
    CALL KRNSAV
    PUSH DE
    PUSH BC
    CALL OCTCNS                     ; DE = the value
    POP BC
    JP SAVINT

;; Stores a colon in KBUF (<KRNSAV>).
;;
;; In:    DE = where it goes in KBUF, BC = the room left
;; Out:   DE = after it, BC = the room left
;; Errors: Line buffer overflow (23) when KBUF is full
;; Uses:  A
;; Keeps: HL
KRNSVC:
    LD A,':'

;; Stores the byte in A in KBUF.
;;
;; In:    A = the byte, DE = where it goes in KBUF, BC = the room left
;; Out:   DE = after it, BC = the room left
;; Errors: Line buffer overflow (23) when KBUF is full
;; Uses:  A
;; Keeps: HL
KRNSAV:
    LD [DE],A
    INC DE
    DEC BC
    LD A,C
    OR B
    RET NZ

;; Reports a Line buffer overflow error (23) through <ERROR>.
LBOERR:
    LD E,$17
    JP ERROR

;; Copies a variable's name into KBUF in uppercase, setting DONUM so that digits in it stay digits.
;;
;; Remarks: The stack holds the text after the name's first letter, then the room left and KBUF's pointer.
;;
;; In:    A = 0
NOTRES:
    POP HL
    DEC HL                          ; HL = the first letter
    DEC A
    LD [DONUM],A                    ; DONUM = $FF: in a name
    POP BC
    POP DE
    CALL MAKUPL
KRNVAR:
    CALL KRNSAV
    INC HL
    CALL MAKUPL
    CALL ISLET2                     ; carry when not a letter
    JP NC,KRNVAR
    CP '9'+1
    JP NC,JKLOOP
    CP '0'
    JP NC,KRNVAR
    CP '.'
    JP Z,KRNVAR
JKLOOP:
    JP KLOOP

;; Stores a character that SPCTAB lacks, as a space if it is a control character other than tab or line feed.
;;
;; In:    HL = the text; the room left and KBUF's pointer are on the stack
;; Entry: NOTRS1 = stores the character or token in A
NOTRS5:
    LD A,[HL]
    CP ' '
    JP NC,NOTRS1
    CP $09                          ; tab
    JP Z,NOTRS1
    CP $0A                          ; line feed
    JP Z,NOTRS1
    LD A,' '
NOTRS1:
    PUSH AF
    LD A,[DONUM]
    INC A                           ; after a name, numbers are constants again
    JP Z,JNTRS6
    DEC A                           ; else DONUM stays
JNTRS6:
    JP NOTRS6

;; Backs HL up over the spaces, tabs and line feeds before it.
;;
;; In:    HL = just after them
;; Out:   HL = after the last other character
;; Uses:  A
;; Keeps: BC, DE
BAKSP:
    DEC HL
    LD A,[HL]
    CP ' '
    JP Z,BAKSP
    CP $09                          ; tab
    JP Z,BAKSP
    CP $0A                          ; line feed
    JP Z,BAKSP
    INC HL
    RET
