;; MBASIC 5.21: WHILE, WEND, CALL, CHAIN, COMMON AND WRITE (FIVEO)
;;
;; The BASIC-80 5.0 statements that GW-BASIC keeps in FIVEO.ASM, in the same order, with CALL between WEND and
;; CHAIN, and after WRITE the file-number routines of the 8080 disk code (DSKCOM):
;;
;; - WHILE and WEND share FNWEND, which evaluates the condition and pushes or drops the 7-byte WHILE entry on the
;;   stack. FNDWND finds an entry, skipping FOR entries.
;; - CALL (ST_CALL, CALLS in Microsoft's source) calls a machine-language routine with up to 32 parameters' addresses,
;;   passed in HL, DE and BC.
;; - CHAIN loads and runs another program, keeping the variables COMMON names or all of them (ALL), and can MERGE
;;   it and DELETE lines first. It scans the program for COMMON statements and marks their variables (NTCHAL to
;;   CHKCST), squeezes out the rest (CLPFIN to CLPAKP), copies the strings in the program text into string space
;;   (DNCMDA to CDVARS), moves the variables up out of the way (DNCCLS) and loads the program through CHNENT or
;;   OKGETM in Disk1.asm, which come back to CHNRET to move the variables back and run it.
;; - WRITE prints values separated by commas, with strings in quotes.
;; - FILINP, FILGET, FILSCN and their entries read a #file number and point PTRFIL at the file's block, and
;;   GETPTR finds a file's data buffer.
;;
;; Runs at $4C58-$5160. The main entry points are the statement handlers, which GONE reaches through STMDSP;
;; CHNRET, which the loader returns to; and FILINP, FILGET, FILSET, FILSCN, FILFRM, FILIDX and GETPTR, which the
;; disk statements and functions call.

;; Runs WHILE: loops through the body while the condition is true, or skips past its WEND.
;;
;; A WHILE entry on the stack is the WHILE token ($B4), the text after the matching WEND, the text after the
;; WHILE and the WHILE's line number: 7 bytes. A WHILE already on the stack for the same WEND, left by a GOTO out
;; of the loop, is dropped with everything above it.
;; In:    HL = the text after WHILE, the condition
;; Errors: WHILE without WEND
ST_WHILE:
    LD [ENDFOR],HL                  ; keep the WHILE's text
    CALL WNDSCN                     ; HL = the matching WEND, or the error
    CALL CHRGTR                     ; the character after the WEND
    EX DE,HL                        ; DE = the text after the WEND
    CALL FNDWND                     ; an entry for this loop already?
    INC SP                          ; drop the return address to NEWSTT
    INC SP
    JP NZ,WNOTOL
    ADD HL,BC                       ; drop everything up to the old entry, and it
    LD SP,HL
    LD [SAVSTK],HL

;; Builds the WHILE entry and goes on to evaluate the condition.
WNOTOL:
    LD HL,[CURLIN]                  ; the WHILE's line
    PUSH HL
    LD HL,[ENDFOR]                  ; the text after WHILE
    PUSH HL
    PUSH DE                         ; the text after WEND
    JP FNWEND

;; Runs WEND: evaluates the condition of its WHILE again, and loops or goes on past the WEND.
;; In:    zero = set at the end of the statement, HL = the text after WEND
;; Errors: Syntax error if anything follows; WEND without WHILE
ST_WEND:
    JP NZ,SNERR                     ; WEND takes no argument
    EX DE,HL                        ; DE = the text after WEND
    CALL FNDWND                     ; HL = its WHILE entry
    JP NZ,WEERR
    LD SP,HL                        ; drop whatever is above the entry
    LD [SAVSTK],HL
    EX DE,HL
    LD HL,[CURLIN]
    EX DE,HL
    EX DE,HL
    LD [NXTLIN],HL                  ; the WEND's line, if the loop ends
    EX DE,HL
    INC HL                          ; skip the WEND text pointer
    INC HL
    LD E,[HL]                       ; DE = the text after WHILE
    INC HL
    LD D,[HL]
    INC HL
    LD A,[HL]                       ; HL = the WHILE's line
    INC HL
    LD H,[HL]
    LD L,A
    LD [CURLIN],HL                  ; back on the WHILE's line, for errors
    EX DE,HL

;; Evaluates the WHILE condition: true runs the body with the WHILE token pushed, false continues after the WEND.
;; In:    HL = the condition's text, the stack = the WHILE entry without its token
FNWEND:
    CALL FRMEVL
    PUSH HL
    CALL VSIGN                      ; zero = set for false
    POP HL
    JP Z,FLSWHL
    LD BC,$00B4                     ; the WHILE token
    LD B,C
    PUSH BC
    INC SP                          ; push just the one byte
    JP NEWSTT

;; Ends the loop: drops the WHILE entry and continues after the WEND, on its line.
FLSWHL:
    LD HL,[NXTLIN]                  ; the WEND's line
    LD [CURLIN],HL
    POP HL                          ; the text after WEND
    POP BC                          ; drop the text after WHILE
    POP BC                          ; and the line number
    JP NEWSTT

;; Searches the stack for the WHILE entry whose WEND text pointer is DE, skipping FOR entries.
;;
;; The search starts above the caller's two return addresses and stops at the first entry that is not a FOR or
;; a WHILE, such as a GOSUB.
;; In:    DE = the text after the WEND
;; Out:   zero = set if found, HL = the entry's WEND text pointer, BC = the rest of the entry's length, 6
FNDWND:
    LD HL,$0004                     ; past the return addresses
    ADD HL,SP

;; Looks at the entry at HL, skipping a FOR entry.
FNDWN2:
    LD A,[HL]                       ; the entry's token
    INC HL
    LD BC,$0082                     ; the FOR token
    CP C
    JP NZ,FNDWN3
    LD BC,$0010                     ; the rest of a FOR entry
    ADD HL,BC
    JP FNDWN2

;; Checks a WHILE entry's WEND text pointer, and returns if it matches or is not a WHILE entry.
FNDWN3:
    LD BC,$00B4                     ; the WHILE token
    CP C
    RET NZ                          ; neither: not found
    PUSH HL
    LD A,[HL]                       ; HL = the entry's WEND text pointer
    INC HL
    LD H,[HL]
    LD L,A
    CALL DCOMPR
    POP HL
    LD BC,$0006                     ; the rest of a WHILE entry
    RET Z                           ; this WEND's
    ADD HL,BC
    JP FNDWN2

;; Gives a WEND without WHILE error.
WEERR:
    LD DE,$001E                     ; error 30
    JP ERROR

;; Runs CALL: calls the machine-language routine whose address is in a variable, passing its parameters.
;;
;; The syntax is CALL var[(param,...)], with up to 32 parameters, each a variable. CALL passes the addresses of
;; their values: the first in HL, the second in DE, the third in BC. With more than three, BC points to the
;; third and the rest follow it. The routine returns with a RET to CALLS_4, which goes on with the next statement.
;; In:    HL = the text after CALL
;; Out:   HL = the text after the statement
;; Errors: Out of memory if the stack has no room for the parameters
ST_CALL:
    LD A,$80
    LD [SUBFLG],A                   ; PTRGET: no array, and no new variable
    CALL PTRGET                     ; DE = the variable
    PUSH HL
    EX DE,HL
    CALL GETYPR
    CALL VMOVFM                     ; FAC = the variable's value
    CALL FRQINT                     ; HL = the routine's address
    LD [TEMPA],HL                   ; kept for CALLS_3
    LD C,$20                        ; room for 32 words
    CALL GETSTK
    POP DE                          ; DE = the text
    LD HL,$FFC0                     ; 64 bytes for the parameters' addresses
    ADD HL,SP
    LD SP,HL
    EX DE,HL                        ; HL = the text, DE = the parameter block
    LD C,$20                        ; up to 32 parameters
    DEC HL
    CALL CHRGTR
    LD [TEMP],HL                    ; the text to continue at, if there are none
    JP Z,CALLS_3                    ; no parameters
    CALL SYNCHR
    .byte '('

;; Stores the next parameter's address in the parameter block.
;; In:    HL = the text, DE = the block's next word, C = the parameters still allowed, plus 1
CALLS_1:
    PUSH BC
    PUSH DE
    CALL PTRGET                     ; DE = the parameter's value
    EX [SP],HL                      ; HL = the block's next word
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    EX [SP],HL
    POP DE
    POP BC
    LD A,[HL]
    CP $2C                          ; another parameter?
    JP NZ,CALLS_2
    DEC C
    CALL CHRGTR
    JP CALLS_1

;; Loads the first three parameters' addresses into HL, DE and BC, or points BC at the third and the rest.
CALLS_2:
    CALL SYNCHR
    .byte ')'
    LD [TEMP],HL                    ; the text to continue at
    LD A,$21
    SUB C                           ; A = the number of parameters
    POP HL                          ; the first
    DEC A
    JP Z,CALLS_3
    POP DE                          ; the second
    DEC A
    JP Z,CALLS_3
    POP BC                          ; the third
    DEC A
    JP Z,CALLS_3
    PUSH BC                         ; more: BC points at the third, with the rest after it
    PUSH HL
    LD HL,$0002
    ADD HL,SP
    LD B,H
    LD C,L
    POP HL

;; Calls the routine at TEMPA with HL as it is, to return to CALLS_4.
CALLS_3:
    PUSH HL
    LD HL,CALLS_4
    EX [SP],HL                      ; the return address
    PUSH HL
    LD HL,[TEMPA]                   ; the routine
    EX [SP],HL
    RET                             ; jump to it, with HL restored

;; Returns from a CALLed routine: restores the stack and goes on with the next statement.
CALLS_4:
    LD HL,[SAVSTK]                  ; drop the parameter block, whatever the routine left
    LD SP,HL
    LD HL,[TEMP]
    JP NEWSTT

;; Runs CHAIN: loads and runs another program, keeping the variables COMMON names.
;;
;; The syntax is CHAIN [MERGE] file[,[line][,ALL][,DELETE range]]. With ALL every variable is kept. MERGE adds
;; the file, which must be in ASCII, to the program instead of replacing it, after deleting the lines of the
;; DELETE range. The new program starts at the given line, or its first.
;; In:    HL = the text after CHAIN
;; Errors: Illegal function call for a bad range, Undefined line number for a missing line, and the loader's
;;   file errors
ST_CHAIN:
    XOR A
    LD [MRGFLG],A                   ; assume no MERGE
    LD [MDLFLG],A                   ; and no DELETE
    LD A,[HL]
    LD DE,$00C5                     ; the MERGE token
    CP E
    JP NZ,NTCHNM
    LD [MRGFLG],A                   ; MERGE
    INC HL

;; Reads CHAIN's file name and opens the file, then the line number to start at.
NTCHNM:
    DEC HL
    CALL CHRGTR
    CALL PRGFLI                     ; open the program file
    PUSH HL
    LD HL,$0000
    LD [CHNLIN],HL                  ; no line given
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,NTCHAL                     ; nothing more
    CALL SYNCHR
    .byte ','
    CP $2C
    JP Z,NTLINF                     ; no line number
    CALL FRMEVL
    PUSH HL
    CALL FRQINT                     ; HL = the line number
    LD [CHNLIN],HL
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,NTCHAL

;; Reads CHAIN's ALL and DELETE options.
NTLINF:
    CALL SYNCHR
    .byte ','
    LD DE,$00AA                     ; the DELETE token
    CP E
    JP Z,CHMWDL
    CALL SYNCHR
    .byte 'A'
    CALL SYNCHR
    .byte 'L'
    CALL SYNCHR
    .byte 'L'
    JP Z,DNCMDA                     ; ALL: keep every variable
    CALL SYNCHR
    .byte ','
    CP E
    JP NZ,SNERR                     ; only DELETE may follow ALL
    OR A                            ; nonzero: ALL was given

;; Reads the DELETE range, checking that both ends exist, and keeps it for DNCCLS.
;; In:    zero = clear if ALL was given
CHMWDL:
    PUSH AF                         ; whether ALL was given
    LD [MDLFLG],A                   ; DELETE
    CALL CHRGTR
    CALL SCNLIN                     ; BC = the first line, the stack = the last's number
    PUSH BC
    CALL DEPTR                      ; line pointers back to numbers
    POP BC
    POP DE                          ; DE = the last line's number
    PUSH BC
    LD H,B
    LD L,C
    LD [CMSPTR],HL                  ; the range's first line
    CALL FNDLIN                     ; the last line, which must exist
    JP NC,CHNFCG
    LD D,H
    LD E,L
    LD [CMEPTR],HL                  ; the line after the range
    POP HL
    CALL DCOMPR                     ; the start must come before the end

;; Gives an Illegal function call error for a bad DELETE range, else goes on.
CHNFCG:
    JP NC,FCERR
    POP AF
    JP NZ,DNCMDA                    ; ALL: keep every variable

;; Scans the program for COMMON statements and marks their variables, setting bit 7 of each name's second byte.
NTCHAL:
    LD HL,[CURLIN]
    PUSH HL                         ; kept for CLPFIN
    LD HL,[TXTTAB]
    DEC HL

;; Starts scanning the next line.
CLPSC1:
    INC HL
    LD A,[HL]                       ; a zero link ends the program
    INC HL
    OR [HL]
    JP Z,CLPFIN
    INC HL
    LD E,[HL]                       ; DE = the line number
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [CURLIN],HL                  ; for errors
    EX DE,HL

;; Looks at the next statement's first token.
CSTSCN:
    CALL CHRGTR

;; Goes on scanning from the character in A, after a statement or a COMMON.
AFTCOM:
    OR A
    JP Z,CLPSC1                     ; the end of the line
    CP $3A
    JP Z,CSTSCN                     ; the next statement
    LD DE,$00B8                     ; the COMMON token
    CP E
    JP Z,DOCOMM
    CALL CHRGTR
    CALL ST_DATA                    ; skip the statement
    DEC HL
    JP CSTSCN

;; Starts reading a COMMON statement's variables.
DOCOMM:
    CALL CHRGTR
    JP Z,AFTCOM

;; Marks the next COMMON variable, an array if it is followed by a parenthesis.
NXTCOM:
    PUSH HL
    LD A,$01
    LD [SUBFLG],A                   ; PTRGTN: look for an array
    CALL PTRGTN                     ; zero = set if the array exists
    JP Z,FNDAAY
    LD A,B
    OR $80                          ; marked already?
    LD B,A
    XOR A
    CALL ERSFIN                     ; search the arrays for the marked name
    LD A,$00
    LD [SUBFLG],A
    JP NZ,NTFN2T
    LD A,[HL]
    CP $28
    JP NZ,SCNSMP                    ; no parenthesis: a simple variable
    POP AF                          ; drop the saved text pointer
    JP COMADY                       ; already marked

;; Gives an Illegal function call for an array COMMON names but no DIM created, else tries a simple variable.
NTFN2T:
    LD A,[HL]
    CP $28
    JP Z,FCERR

;; Looks the name up as a simple variable, marked or not, and marks it.
SCNSMP:
    POP HL                          ; the name again
    CALL PTRGTN                     ; DE = the variable, or 0
    LD A,D
    OR E
    JP NZ,COMFNS
    LD A,B
    OR $80                          ; marked already?
    LD B,A
    LD DE,COMPT2
    PUSH DE
    LD DE,PTRGTR                    ; NOARYS returns through PTRGTR to COMPT2
    PUSH DE
    LD A,[VALTYP]
    LD D,A
    JP NOARYS                       ; search the simple variables

;; Gives an Illegal function call error for a COMMON variable that does not exist, else marks it.
;; In:    DE = the variable's value, or 0
COMPT2:
    LD A,D
    OR E
    JP Z,FCERR

;; Marks the variable whose value DE points at, then goes on with BCKUCM.
COMFNS:
    PUSH HL
    LD B,D
    LD C,E
    LD HL,BCKUCM
    PUSH HL

;; Marks the variable name before BC as COMMON, setting bit 7 of its second character.
CBAKBL:
    DEC BC

;; Backs BC up over the name's extra characters, which have bit 7 set.
LPBKNC:
    LD A,[BC]
    DEC BC
    OR A
    JP M,LPBKNC
    LD A,[BC]
    OR $80                          ; COMMON
    LD [BC],A
    RET

;; Marks an existing array named in COMMON.
FNDAAY:
    LD [SUBFLG],A                   ; A = 0
    LD A,[HL]
    CP $28
    JP NZ,SCNSMP                    ; no parenthesis: a simple variable after all
    EX [SP],HL                      ; keep the text pointer, drop the saved one
    DEC BC                          ; back up over the length
    DEC BC
    CALL CBAKBL

;; Goes on after a marked variable: the end of the statement, a parenthesis or a comma.
BCKUCM:
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,AFTCOM
    CP $28
    JP NZ,CHKCST

;; Skips the parentheses after a COMMON array's name.
COMADY:
    CALL CHRGTR
    CALL SYNCHR
    .byte ')'
    JP Z,AFTCOM

;; Checks for the comma before the next COMMON variable.
CHKCST:
    CALL SYNCHR
    .byte ','
    JP NXTCOM

;; Deletes the simple variables not marked as COMMON, clearing the marks.
CLPFIN:
    POP HL
    LD [CURLIN],HL                  ; back to CHAIN's line
    EX DE,HL
    LD HL,[ARYTAB]
    EX DE,HL
    LD HL,[VARTAB]

;; Checks the next simple variable, deleting it unless it is marked.
CLPSLP:
    CALL DCOMPR
    JP Z,DNCMDS                     ; the end of the simple variables
    PUSH HL
    LD C,[HL]                       ; C = the type, the value's length
    INC HL
    INC HL
    LD A,[HL]                       ; the mark
    OR A
    PUSH AF
    AND $7F                         ; clear it
    LD [HL],A
    INC HL
    CALL IADAHL                     ; skip the rest of the name
    LD B,$00
    ADD HL,BC                       ; HL = the next variable
    POP AF
    POP BC                          ; BC = this one
    JP M,CLPSLP                     ; marked: keep it
    PUSH BC
    CALL VARDLS
    LD HL,[ARYTAB]
    ADD HL,DE                       ; the arrays moved down
    LD [ARYTAB],HL
    EX DE,HL
    POP HL
    JP CLPSLP

;; Deletes the variable or array from BC to HL, moving everything up to STREND down over it.
;; In:    BC = the start, HL = the end
;; Out:   DE = the change in size, negative, HL = BC = the new STREND
VARDLS:
    EX DE,HL
    LD HL,[STREND]

;; Moves the bytes from DE up to STREND down to BC.
DLSVLP:
    CALL DCOMPR
    LD A,[DE]
    LD [BC],A
    INC DE
    INC BC
    JP NZ,DLSVLP
    LD A,C                          ; DE = BC-HL, the change
    SUB L
    LD E,A
    LD A,B
    SBC A,H
    LD D,A
    DEC DE
    DEC BC
    LD H,B
    LD L,C
    LD [STREND],HL
    RET

;; Deletes the arrays not marked as COMMON, clearing the marks.
DNCMDS:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL

;; Checks the next array, deleting it unless it is marked.
CLPAKP:
    CALL DCOMPR
    JP Z,DNCMDA                     ; the end of the arrays
    PUSH HL
    INC HL
    INC HL
    LD A,[HL]                       ; the mark
    OR A
    PUSH AF
    AND $7F                         ; clear it
    LD [HL],A
    INC HL
    CALL IADAHL                     ; skip the rest of the name
    LD C,[HL]                       ; BC = the array's length
    INC HL
    LD B,[HL]
    INC HL
    ADD HL,BC                       ; HL = the next array
    POP AF
    POP BC                          ; BC = this one
    JP M,CLPAKP                     ; marked: keep it
    PUSH BC
    CALL VARDLS
    EX DE,HL                        ; DE = STREND
    POP HL
    JP CLPAKP

;; Copies the strings of the kept string variables that are in the program text into string space.
DNCMDA:
    LD HL,[VARTAB]

;; Checks the next simple variable, copying its string if it is a string variable.
CSVAR:
    EX DE,HL
    LD HL,[ARYTAB]
    EX DE,HL
    CALL DCOMPR
    JP Z,CAYVAR                     ; on to the arrays
    LD A,[HL]                       ; the type
    INC HL
    INC HL
    INC HL
    PUSH AF
    CALL IADAHL                     ; skip the rest of the name
    POP AF
    CP $03                          ; a string?
    JP NZ,CSKPVA
    CALL CDVARS
    XOR A                           ; CDVARS has skipped the descriptor

;; Skips the variable's value, A bytes.
CSKPVA:
    LD E,A
    LD D,$00
    ADD HL,DE
    JP CSVAR

;; Drops the saved array pointer and checks the next array.
CAYVA2:
    POP BC

;; Checks the next array, copying the strings of a string array.
CAYVAR:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    CALL DCOMPR
    JP Z,DNCCLS                     ; all done
    LD A,[HL]                       ; the type
    INC HL
    INC HL
    PUSH AF
    INC HL
    CALL IADAHL                     ; skip the rest of the name
    LD C,[HL]                       ; BC = the array's length
    INC HL
    LD B,[HL]
    INC HL
    POP AF
    PUSH HL
    ADD HL,BC                       ; HL = the next array
    CP $03                          ; a string array?
    JP NZ,CAYVA2
    LD [TEMP3],HL                   ; its end
    POP HL
    LD C,[HL]                       ; skip the number of dimensions and their sizes
    LD B,$00
    ADD HL,BC
    ADD HL,BC
    INC HL

;; Copies the next string of a string array, until TEMP3, its end.
CAYSTR:
    EX DE,HL
    LD HL,[TEMP3]
    EX DE,HL
    CALL DCOMPR
    JP Z,CAYVAR
    LD BC,CAYSTR                    ; come back for the next element
    PUSH BC

;; Copies the string of the descriptor at HL into string space if it is in the program text.
;;
;; Strings above VARTAB are in string space already, and strings below TXTTAB are in the file buffers; those
;; are left alone.
;; In:    HL = the descriptor
;; Out:   HL = the byte after the descriptor
CDVARS:
    LD A,[HL]                       ; A = the length
    INC HL
    LD E,[HL]                       ; DE = the text
    INC HL
    LD D,[HL]
    INC HL
    OR A
    RET Z                           ; an empty string
    PUSH HL
    LD HL,[VARTAB]
    CALL DCOMPR
    POP HL
    RET C                           ; in string space
    PUSH HL
    LD HL,[TXTTAB]
    CALL DCOMPR
    POP HL
    RET NC                          ; in a buffer
    PUSH HL
    DEC HL                          ; back to the descriptor
    DEC HL
    DEC HL
    PUSH HL
    CALL STRCPY                     ; copy the string into DSCTMP
    POP HL
    LD B,$03
    CALL MOVE1                      ; the new descriptor over the old
    POP HL
    RET

;; Moves the variables up into the top of string space, deletes the DELETE range, and loads the new program.
DNCCLS:
    CALL GARBA2                     ; collect the unused strings
    LD HL,[STREND]
    LD B,H
    LD C,L                          ; BC = the end of the variables
    EX DE,HL
    LD HL,[VARTAB]
    EX DE,HL
    LD HL,[ARYTAB]
    LD A,L                          ; HL = the simple variables' length
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    LD [TEMP9],HL                   ; kept for CHNRET
    LD HL,[FRETOP]
    LD [SAVFRE],HL                  ; FRETOP, restored by CHNRET
    CALL BLTUC                      ; move the variables up below FRETOP
    LD H,B
    LD L,C
    DEC HL
    LD [FRETOP],HL                  ; the strings end below them now
    LD A,[MDLFLG]                   ; DELETE?
    OR A
    JP Z,NTMDLT
    LD HL,[CMSPTR]
    LD B,H
    LD C,L
    LD HL,[CMEPTR]
    CALL DEL                        ; delete the range
    LD [ARYTAB],HL                  ; no variables, in case loading fails
    LD [STREND],HL
    CALL LINKER                     ; link the lines again

;; Loads the new program, by MERGE or by LOAD, which come back to CHNRET.
NTMDLT:
    LD A,$01
    LD [CHNFLG],A                   ; chaining
    LD A,[MRGFLG]
    OR A
    JP NZ,OKGETM                    ; merge it
    LD A,[MAXFIL]
    LD [MAXSAV],A                   ; kept while the loader closes the files
    JP CHNENT                       ; load it

;; Moves the kept variables back down after the new program and runs it, the end of CHAIN.
;;
;; The loader comes here after loading a program for CHAIN.
;; Errors: Undefined line number if the line to start at does not exist
CHNRET:
    XOR A
    LD [CHNFLG],A                   ; no longer chaining
    LD [MRGFLG],A
    LD HL,[VARTAB]
    LD B,H
    LD C,L                          ; BC = where the variables go
    LD HL,[TEMP9]                   ; the simple variables' length
    ADD HL,BC
    LD [ARYTAB],HL
    LD HL,[FRETOP]
    INC HL
    EX DE,HL                        ; DE = the variables, up in string space
    LD HL,[SAVFRE]
    LD [FRETOP],HL

;; Moves the variables down, from DE up to HL, to BC.
MVBKVR:
    CALL DCOMPR
    LD A,[DE]
    LD [BC],A
    INC DE
    INC BC
    JP NZ,MVBKVR
    DEC BC
    LD H,B
    LD L,C
    LD [STREND],HL                  ; their new end
    EX DE,HL
    LD HL,[CHNLIN]
    EX DE,HL
    LD HL,[TXTTAB]
    DEC HL
    LD A,D
    OR E
    JP Z,NEWSTT                     ; no line: run from the start
    CALL FNDLIN
    JP NC,USERR
    DEC BC                          ; just before the line
    LD H,B
    LD L,C
    JP NEWSTT
    ; COMMON's own handler, which nothing uses: STMDSP sends COMMON straight to ST_DATA, to skip it.
    JP ST_DATA

;; Runs WRITE: prints values separated by commas, strings in quotes, to the console or a #file.
;;
;; A number is printed without the space a positive number has before it. On a random file the rest of the
;; record is filled with spaces before the new line.
;; In:    HL = the text after WRITE
;; Errors: Bad file mode if the file is not open for output
ST_WRITE:
    LD C,$02                        ; sequential output
    CALL FILGET                     ; a #file, if there is one
    DEC HL
    CALL CHRGTR
    JP Z,WRTFIN                     ; nothing to write: just a new line

;; Evaluates and prints the next value.
WRTMLP:
    CALL FRMEVL
    PUSH HL
    CALL GETYPR                     ; zero = set for a string
    JP Z,WRTSTR
    CALL FOUT                       ; the number as text
    CALL STRLIT                     ; and as a string
    LD HL,[FACLO]                   ; its descriptor
    INC HL
    LD E,[HL]                       ; DE = its text
    INC HL
    LD D,[HL]
    LD A,[DE]
    CP $20                          ; the space of a positive number?
    JP NZ,WRTNEG
    INC DE                          ; drop it
    LD [HL],D
    DEC HL
    LD [HL],E
    DEC HL
    DEC [HL]                        ; one character shorter

;; Prints the number.
WRTNEG:
    CALL STRPRT

;; Goes on after a value: the end of the statement, or a comma or semicolon and the next value.
NXTWRV:
    POP HL
    DEC HL
    CALL CHRGTR
    JP Z,WRTFIN
    CP $3B                          ; a semicolon?
    JP Z,WASEMI
    CALL SYNCHR
    .byte ','
    DEC HL                          ; for the CHRGTR that follows

;; Skips the separator and prints a comma before the next value.
WASEMI:
    CALL CHRGTR
    LD A,$2C
    CALL OUTDO
    JP WRTMLP

;; Prints a string value in quotes.
WRTSTR:
    LD A,$22
    CALL OUTDO
    CALL STRPRT
    LD A,$22
    CALL OUTDO
    JP NXTWRV

;; Ends WRITE with a new line, first filling the rest of a random file's record with spaces.
WRTFIN:
    PUSH HL
    LD HL,[PTRFIL]
    LD A,H
    OR L
    JP Z,NTRNDW                     ; the console
    LD A,[HL]                       ; the file's mode
    CP $03                          ; random?
    JP NZ,NTRNDW
    CALL FLDCHK                     ; CMPFBC: DE = the bytes used
    LD A,L                          ; HL = the bytes left
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    LD DE,$FFFE                     ; less 2 for the return and line feed
    ADD HL,DE
    JP NC,NTRNDW                    ; no room: the error comes with the new line

;; Prints HL spaces.
NXTWSP:
    LD A,$20
    CALL OUTDO
    DEC HL
    LD A,H
    OR L
    JP NZ,NXTWSP

;; Prints the new line and sends output back to the console.
NTRNDW:
    POP HL
    CALL CRDO
    JP FINPRT

;; Reads a #file number, if there is one, for a statement that reads a sequential file, and points PTRFIL at it.
;; In:    HL = the text, A = its character
;; See:   <FILGET>
FILINP:
    LD C,$01                        ; sequential input

;; Reads a #file number, if there is one, checks the file's mode and points PTRFIL at it.
;;
;; A random file is accepted for either mode.
;; In:    HL = the text, A = its character, C = the mode wanted: 1 input, 2 output
;; Out:   HL = the text after the number and its comma, PTRFIL = the file, A unchanged if no # follows
;; Errors: Bad file number, Bad file mode
FILGET:
    CP $23                          ; #?
    RET NZ                          ; no: the console
    PUSH BC
    CALL FILSCN                     ; BC = the file's block, A = its mode
    POP DE
    CP E
    JP Z,GDFILM
    CP $03                          ; random files do for both
    JP NZ,DERBFM

;; Checks for the comma after the file number and sets PTRFIL.
GDFILM:
    CALL SYNCHR
    .byte ','

;; Points PTRFIL at the file block in BC.
;; In:    BC = the file's block
;; Out:   DE = BC
;; Keeps: AF, BC, HL
FILSET:
    LD D,B
    LD E,C
    EX DE,HL
    LD [PTRFIL],HL
    EX DE,HL
    RET

;; Reads a file number, with or without its #, and finds the file's block.
;; In:    HL = the text, at the #
;; Out:   BC = the file's block, A = its mode, 0 if closed, zero = set if closed, HL = the text after the number
;; Errors: Bad file number
FILSCN:
    DEC HL
    CALL CHRGTR
    CP $23                          ; skip the #
    CALL Z,CHRGTR
    CALL FRMEVL

;; Finds the block of the file whose number is in the FAC.
FILFRM:
    CALL CONINT                     ; A = the number

;; Finds the block of the file whose number is in A.
FILIDX:
    LD E,A

;; Finds the block of the file whose number is in E.
;; In:    E = the file number
;; Out:   BC = the file's block, A = its mode, 0 if closed, zero = set if closed
;; Errors: Bad file number if E is above MAXFIL
;; Keeps: HL
FILID2:
    LD A,[MAXFIL]
    CP E
    JP C,DERBFN
    LD D,$00
    PUSH HL
    LD HL,FILPTR                    ; the file blocks' addresses
    ADD HL,DE
    ADD HL,DE
    LD C,[HL]
    INC HL
    LD B,[HL]
    LD A,[BC]                       ; the mode, the block's first byte
    OR A
    POP HL
    RET

;; Finds the data buffer of the file whose number is in E.
;; In:    E = the file number
;; Out:   DE = the buffer, BC = the file's block, A = its mode
;; Errors: Bad file number
GETPTR:
    CALL FILID2
    LD HL,$0029                     ; DATOFS: a sequential file's buffer
    CP $03
    JP NZ,GETPTR_1
    LD HL,$00B2                     ; a random file's

;; Adds the buffer's offset in HL to the block's address.
GETPTR_1:
    ADD HL,BC
    EX DE,HL
    RET
