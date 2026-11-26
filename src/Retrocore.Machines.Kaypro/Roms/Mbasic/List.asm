;; MBASIC 5.21: LIST, DELETE, PEEK AND POKE, RENUM AND OPTION BASE
;;
;; The program-listing half of Microsoft's BINTRP, GW-BASIC's GWLIST.ASM with the PEEK, POKE, RENUM (RESEQ)
;; and OPTION BASE code that GW-BASIC keeps at the end of GWMAIN.ASM. In order:
;;
;; - ST_LLIST and ST_LIST parse a line range (SCNLIN) and print each line of it in LIST4: the line number,
;;   then the line expanded by BUFLIN into BUF and printed by LISPRT.
;; - BUFLIN is the detokenizer. It copies the crunched line into BUF, spells out each reserved word by searching
;;   the reserved word lists (ATAB on, in Tables.asm) for its token, and turns each embedded constant back into
;;   text through FOUT, FOUTO or FOUTH (NUMLIN). TEMPA remembers what was stored last, so a space goes
;;   between a word and a name or number, but not between operators. EDIT (Console.asm) uses it too.
;; - ST_DELETE removes a range of lines, printing Ok first, through DEL, which closes the gap in the text.
;; - FN_PEEK and ST_POKE, with FRMQNT and FRQINT, which read an address from -32768 to 65535.
;; - ST_RENUM renumbers lines (RESEQ), checking the new numbers, then fixes every line number in the program with
;;   SCCLIN. SCCLIN and SCCPTR convert the program's line number constants (LINCON) to pointers (PTRCON) and
;;   back, and print "Undefined line" for a reference to a missing line; DEPTR converts back if pointers exist.
;; - ST_OPTION sets OPTION BASE 0 or 1, before any array exists.
;; - STRPRN and CALTTY print a message straight to the console, for the math package's overflow message.
;;
;; Runs at $2084-$2486. The main entry points are ST_LIST, ST_LLIST, ST_DELETE, ST_RENUM, ST_OPTION, FN_PEEK and
;; ST_POKE from the dispatch tables, and BUFLIN, LISPRT, DEL, SCCPTR, DEPTR and FRQINT for other modules.

;; Runs LLIST, listing the program to the printer.
;;
;; Sets PRTFLG to send the output to the printer, then lists as LIST does.
;; In:    HL = the text after LLIST, zero = set at the end of the statement
ST_LLIST:
    LD A,$01                        ; output goes to the printer
    LD [PRTFLG],A

;; Runs LIST, printing the program or a range of its lines.
;;
;; Throws away NEWSTT's return address: LIST ends at READY, or at STPRDY after the range.
;; In:    HL = the text after LIST, zero = set at the end of the statement
;; Errors: FC error (PROCHK) if the program is protected
ST_LIST:
    POP BC                          ; drop the return to NEWSTT
    CALL SCNLIN                     ; BC = the first line, the last line number stacked
    PUSH BC
    CALL PROCHK                     ; not even a listing of a protected program

;; Prints the line at the top of the stack, and the lines after it up to the number under it.
;;
;; The stack holds the line to list, then the last line number of the range. Stops at the end of the
;; program (READY) or past the range (STPRDY), or on Control-C.
LIST4:
    LD HL,$FFFF                     ; Control-C must not set up CONT
    LD [CURLIN],HL
    POP HL                          ; HL = the line
    POP DE                          ; DE = the last line number
    LD C,[HL]                       ; BC = the link to the next line
    INC HL
    LD B,[HL]
    INC HL
    LD A,B                          ; a zero link ends the program
    OR C
    JP Z,READY
    CALL ISFLIO                     ; check for Control-C,
    CALL Z,ISCNTC                   ; through the console's status
    PUSH BC                         ; keep the link
    LD C,[HL]                       ; BC = the line's number
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    EX [SP],HL                      ; HL = the line number, the text pointer stacked
    EX DE,HL                        ; HL = the last line number, DE = this one
    CALL DCOMPR                     ; past the range?
    POP BC                          ; BC = the text pointer
    JP C,STPRDY                     ; past it: done
    EX [SP],HL                      ; stack the last line number, HL = the link
    PUSH HL
    PUSH BC
    EX DE,HL                        ; HL = the line number
    LD [DOT],HL                     ; the current line for EDIT and LIST .
    CALL LINPRT
    POP HL                          ; HL = the line's text
    LD A,[HL]
    CP $09                          ; a tab after the number needs no space
    JP Z,NOSPAL
    LD A,' '
    CALL OUTDO
NOSPAL:
    CALL BUFLIN                     ; expand the line into BUF
    LD HL,BUF
    CALL LISPRT
    CALL CRDO                       ; end the line
    JP LIST4

;; Prints the zero-terminated text at HL, as a line from BUFLIN.
;;
;; A line feed is followed by a carriage return (OUTCH1).
;; In:    HL = the text
;; Out:   HL = the zero at its end
LISPRT:
    LD A,[HL]
    OR A
    RET Z
    CALL OUTCH1                     ; print it
    INC HL
    JP LISPRT

;; Expands the crunched line at HL into BUF, spelling out its reserved words and constants.
;;
;; At most 255 characters are stored; a longer line is cut short. TEMPA says what was stored last:
;; 0 a special character, 1 part of a name or number, $FF a reserved word. A space is put between a reserved
;; word and a name next to it.
;; In:    HL = the line's text, after its link and number
;; Out:   BUF = the line, ending in a zero
;; Errors: FC error (PROCHK) if the program is protected
BUFLIN:
    LD BC,BUF                       ; BC = where to store, BUF
    LD D,$FF                        ; D = room left
    XOR A
    LD [TEMPA],A                    ; TEMPA = special, no space first
    CALL PROCHK
    JP PLOOP2
PLOOP:
    INC BC                          ; next place in BUF
    INC HL                          ; next byte of the line
    DEC D
    RET Z                           ; BUF is full
PLOOP2:
    LD A,[HL]
    OR A
    LD [BC],A                       ; store it as it is
    RET Z                           ; the zero ends the line
    CP OCTCON                       ; below OCTCON: not a constant
    JP C,NTEMBL
    CP DBLCON+1                     ; tokens $0B-$1F are embedded constants
    LD E,A
    JP C,PRTVAR
NTEMBL:
    OR A
    JP M,PLOOPR                     ; a reserved word's token
    LD E,A                          ; E = the character
    CP '.'                          ; a dot is part of a name
    JP Z,PRTVAR
    CALL TSTANM                     ; a letter or digit?
    JP NC,PRTVAR
    XOR A                           ; no: a special character
    JP PLOOPH
PRTVAR:
    LD A,[TEMPA]                    ; what came before?
    OR A
    JP Z,PLOOPG                     ; a special character: no space
    INC A
    JP NZ,PLOOPG                    ; a name: no space
    LD A,' '                        ; a reserved word: a space after it
    LD [BC],A
    INC BC
    DEC D
    RET Z
PLOOPG:
    LD A,$01                        ; now in a name or number
PLOOPH:
    LD [TEMPA],A
    LD A,E                          ; A = the character again
    CP $0B
    JP C,PLOOPZ
    CP $20
    JP C,NUMLIN                     ; an embedded constant: expand it
PLOOPZ:
    LD [BC],A                       ; store it, after any space
    JP PLOOP
PLOOPR:
    INC A                           ; $FF prefixes a function's token
    LD A,[HL]
    JP NZ,NTFNTK
    INC HL                          ; A = the function's token, without bit 7
    LD A,[HL]
    AND $7F
NTFNTK:
    INC HL                          ; past the token
    CP TK_APOSTROPHE                ; ' is stored as :REM'
    JP NZ,NTQTTK
    DEC BC                          ; take back the :REM already stored
    DEC BC
    DEC BC
    DEC BC
    INC D
    INC D
    INC D
    INC D
NTQTTK:
    CP TK_ELSE                      ; ELSE is stored as :ELSE
    CALL Z,DCXBRT                   ; take back the colon
    CP TK_WHILE                     ; WHILE may be followed by a + token
    JP NZ,BFNTWH
    LD A,[HL]
    INC HL
    CP TK_PLUS                      ; the + token: skip it
    LD A,TK_WHILE
    JP Z,BFNTWH
    DEC HL
BFNTWH:
    PUSH HL
    PUSH BC
    PUSH DE
    LD HL,ATAB-1                    ; search the reserved word lists, A to Z, then SPCTAB
    LD B,A                          ; B = the token to find
    LD C,'A'-1                      ; C = the list's letter
RESSR3:
    INC C                           ; the next letter's list
RESSR1:
    INC HL
    LD D,H                          ; DE = the start of this word
    LD E,L
RESSR2:
    LD A,[HL]
    OR A
    JP Z,RESSR3                     ; the end of this letter's list
    INC HL
    JP P,RESSR2                     ; up to the word's last character, with bit 7 set
    LD A,[HL]                       ; A = the word's token
    CP B
    JP NZ,RESSR1
    EX DE,HL                        ; HL = the word, after its first letter
    CP TK_USR                       ; USR and FN take no space after them
    JP Z,NOISPA
    CP TK_FN
NOISPA:
    LD A,C                          ; A = the word's letter
    POP DE
    POP BC
    LD E,A                          ; E = the word's letter
    JP NZ,NTFNEX
    LD A,[TEMPA]                    ; USR or FN: a space unless an operator came before
    OR A
    LD A,$00                        ; and none after it
    LD [TEMPA],A
    JP MORLNZ
NTFNEX:
    CP 'Z'+1                        ; an operator, from SPCTAB?
    JP NZ,NTSPCH
    XOR A                           ; no spaces around an operator
    LD [TEMPA],A
    JP MORPUR                       ; and it has no letter to store
NTSPCH:
    LD A,[TEMPA]                    ; a space unless an operator came before
    OR A
    LD A,$FF                        ; now in a reserved word
    LD [TEMPA],A
MORLNZ:
    JP Z,MORLN0
    LD A,' '
    LD [BC],A
    INC BC
    DEC D
    JP Z,PPSWRT                     ; BUF is full
MORLN0:
    LD A,E                          ; store the word's letter first
    JP MORLN1
MORPUR:
    LD A,[HL]                       ; the word's next character
    INC HL
    LD E,A
MORLN1:
    AND $7F
    LD [BC],A
    INC BC
    DEC D
    JP Z,PPSWRT                     ; BUF is full
    OR E                            ; bit 7 marks the word's last character
    JP P,MORPUR
    CP '(' | $80                    ; SPC( and TAB( need no space after them
    JP NZ,NTSPCT
    XOR A
    LD [TEMPA],A
NTSPCT:
    POP HL                          ; back to the line
    JP PLOOP2

;; Tests whether the character in A is a letter or a digit.
;; In:    A = the character
;; Out:   carry = clear for a letter or digit
TSTANM:
    CALL ISLET2                     ; a letter?
    RET NC
    CP '0'
    RET C
    CP '9'+1
    CCF                             ; carry clear for a digit
    RET

;; Expands an embedded constant into BUF as text, during BUFLIN.
;;
;; CONFC1 loads the constant into FAC, which FOUT prints as decimal, FOUTO as octal and FOUTH as hex, returning
;; to CONLIN with the text in FBUFFR. A number's type marker (! or #) is added when its text does not show it,
;; and octal and hex constants get &O and &H.
;; In:    A = the constant's token, E = A, HL = the token, BC = the place in BUF, D = room left
;; Out:   BC = the place in BUF after the constant, D = the room left, HL = the line after it
NUMLIN:
    DEC HL                          ; CHRGTR starts with an INC
    CALL CHRGTR                     ; scan the constant, setting CONTXT
    PUSH DE
    PUSH BC
    PUSH AF
    CALL CONFC1                     ; the constant to FAC
    POP AF                          ; A = its token
    LD BC,CONLIN                    ; the printing returns there
    PUSH BC
    CP OCTCON
    JP Z,FOUTO
    CP HEXCON
    JP Z,FOUTH
    LD HL,[CONLO]                   ; a line number constant's value
    JP FOUT

;; Copies the constant's text that FOUT made into BUF, then goes on with the line.
;; In:    HL = the number's text, ending in a zero, the stack = the place in BUF, the room left
;; Out:   BC = the place in BUF after the constant, D = the room left, HL = the line after it
CONLIN:
    POP BC                          ; BC = the place in BUF
    POP DE                          ; D = room left
    LD A,[CONSAV]                   ; the constant's token
    LD E,'O'
    CP $0B                          ; octal?
    JP Z,SAVBAS
    CP $0C                          ; hex?
    LD E,'H'
    JP NZ,NUMSLN
SAVBAS:
    LD A,'&'                        ; &O or &H first
    LD [BC],A
    INC BC
    DEC D
    RET Z
    LD A,E
    LD [BC],A
    INC BC
    DEC D
    RET Z
NUMSLN:
    LD A,[CONTYP]                   ; below 4 is an integer, without a marker
    CP $04
    LD E,$00
    JP C,TYPSET
    LD E,'!'                        ; 4 is single precision
    JP Z,TYPSET
    LD E,'#'                        ; 8 is double
TYPSET:
    LD A,[HL]
    CP ' '                          ; skip FOUT's leading space
    CALL Z,INXHRT
NUMSL2:
    LD A,[HL]
    INC HL
    OR A
    JP Z,NUMDN                      ; the end of the number
    LD [BC],A
    INC BC
    DEC D
    RET Z
    LD A,[CONTYP]
    CP $04
    JP C,NUMSL2                     ; an integer needs no check
    DEC BC                          ; A = the character just stored
    LD A,[BC]
    INC BC
    JP NZ,DBLSCN                    ; a double: only an exponent shows it
    CP '.'                          ; a single with a point shows it is one
    JP Z,ZERE
DBLSCN:
    CP 'D'                          ; an exponent shows the type
    JP Z,ZERE
    CP 'E'
    JP NZ,NUMSL2
ZERE:
    LD E,$00                        ; no marker needed
    JP NUMSL2
NUMDN:
    LD A,E                          ; add the marker, if any
    OR A
    JP Z,NOD
    LD [BC],A
    INC BC
    DEC D
    RET Z
NOD:
    LD HL,[CONTXT]                  ; the text after the constant
    JP PLOOP2

;; Runs DELETE, removing a range of lines from the program.
;;
;; Prints Ok before it deletes, then returns to FINI, which fixes the links and clears the variables.
;; In:    HL = the text after DELETE
;; Errors: FC error if the range's last line does not exist or comes before its first
ST_DELETE:
    CALL SCNLIN                     ; BC = the first line, the last line number stacked
    PUSH BC
    CALL DEPTR                      ; line pointers back to numbers
    POP BC
    POP DE                          ; DE = the last line number
    PUSH BC                         ; keep the first line's pointer for FINI
    PUSH BC
    CALL FNDLIN                     ; find the last line
    JP NC,FCERRG                    ; it must exist
    LD D,H                          ; DE = the line after it
    LD E,L
    EX [SP],HL                      ; stack that, HL = the first line
    PUSH HL
    CALL DCOMPR                     ; the first must come before it
FCERRG:
    JP NC,FCERR
    LD HL,REDDY                     ; Ok, before the lines go
    CALL STROUT
    POP BC                          ; BC = the first line
    LD HL,FINI                      ; FINI, when done
    EX [SP],HL                      ; HL = the line after the range

;; Removes program text from BC up to HL, moving the rest of the program down.
;; In:    BC = the first byte to remove, HL = the first byte to keep
;; Out:   HL, VARTAB = the program's new end
;; Uses:  A, BC, DE
DEL:
    EX DE,HL                        ; DE = the first byte to keep
    LD HL,[VARTAB]                  ; move up to the program's end
MLOOP:
    LD A,[DE]
    LD [BC],A
    INC BC
    INC DE
    CALL DCOMPR                     ; at the end?
    JP NZ,MLOOP
    LD H,B
    LD L,C
    LD [VARTAB],HL
    RET

;; Runs the PEEK function, giving the byte at an address.
;; In:    FAC = the address, -32768 to 65535
;; Out:   FAC = the byte, as an integer
;; Errors: FC error (PRODIR) in direct mode with a protected program
FN_PEEK:
    CALL FRQINT                     ; HL = the address
    CALL PRODIR
    LD A,[HL]
    JP SNGFLT                       ; A to FAC

;; Runs POKE, storing a byte at an address.
;; In:    HL = the text after POKE
;; Errors: FC error (PRODIR) in direct mode with a protected program
ST_POKE:
    CALL FRMQNT                     ; DE = the address
    PUSH DE
    CALL PRODIR
    CALL SYNCHR
    .byte ','
    CALL GETBYT                     ; A = the byte
    POP DE
    LD [DE],A
    RET

;; Evaluates the expression at HL as an address from -32768 to 65535.
;; In:    HL = the text
;; Out:   DE = the address, HL = the text after the expression
FRMQNT:
    CALL FRMEVL
    PUSH HL
    CALL FRQINT
    EX DE,HL                        ; DE = the address
    POP HL
    RET

;; Converts FAC to an integer address, taking 32768 to 65535 as the addresses -32768 to -1 stand for.
;;
;; A single or double from 32768 to 65535 has 65536 subtracted before FRCINT (FN_CINT) makes it an integer.
;; In:    FAC = the number
;; Out:   HL = the integer
;; Errors: OV error outside -32768 to 65535
FRQINT:
    LD BC,FN_CINT                   ; FRCINT when done
    PUSH BC
    CALL GETYPR
    RET M                           ; an integer already
    LD A,[FAC]                      ; FAC's exponent
    CP $90                          ; 32768 to 65535?
    RET NZ
    CALL SIGN
    RET M                           ; negative: FRCINT gives the error, or -32768
    CALL FN_CSNG
    LD BC,$9180                     ; -65536
    LD DE,$0000
    JP FADD

;; Runs RENUM, renumbering the program's lines and the line numbers that refer to them.
;;
;; RENUM [new][,[old][,increment]]: the lines from old (the first line by default) on are numbered from new (10)
;; in steps of increment (10). First checks that the new numbers fit, below 65530 and not overlapping the lines
;; before old; then converts the references to pointers (SCCLIN), renumbers, and converts them back to the
;; new numbers (SCCPTR, through STPRDY).
;; In:    HL = the text after RENUM, A = its first character, zero = set at the end of the statement
;; Errors: FC error for a zero increment or numbers that don't fit, SN error for anything after the increment
ST_RENUM:
    LD BC,$000A                     ; the increment, 10 unless given
    PUSH BC
    LD D,B                          ; DE = old, 0 for the first line
    LD E,B
    JP Z,RESNN                      ; just RENUM
    CP ','                          ; no new number?
    JP Z,EATCOM
    PUSH DE
    CALL LINSPC                     ; DE = new
    LD B,D                          ; BC = new
    LD C,E
    POP DE
    JP Z,RESNN
EATCOM:
    CALL SYNCHR
    .byte ','
    CALL LINSPC                     ; DE = old
    JP Z,RESNN
    POP AF                          ; drop the default increment
    CALL SYNCHR
    .byte ','
    PUSH DE
    CALL LINGET                     ; DE = the increment
    JP NZ,SNERR                     ; it must end the statement
    LD A,D
    OR E
    JP Z,FCERR                      ; a zero increment
    EX DE,HL                        ; stack the increment, DE = old
    EX [SP],HL
    EX DE,HL
RESNN:
    PUSH BC                         ; keep new
    CALL FNDLIN                     ; BC = the line old
    POP DE                          ; DE = new
    PUSH DE
    PUSH BC
    CALL FNDLIN                     ; BC = the line numbered new, or the one after
    LD H,B
    LD L,C
    POP DE                          ; DE = the line old
    CALL DCOMPR                     ; the renumbered lines must not overtake earlier ones
    EX DE,HL
    JP C,FCERR
    POP DE                          ; DE = new
    POP BC                          ; BC = the increment
    POP AF                          ; drop the return to NEWSTT
    PUSH HL                         ; keep the first line to renumber
    PUSH DE                         ; and new
    JP NXTRSL
NXTRSC:
    ADD HL,BC                       ; the next line's new number
    JP C,FCERR                      ; past 65535
    EX DE,HL                        ; DE = the number, HL = the line
    PUSH HL
    LD HL,$FFF9                     ; 65529, the largest line number
    CALL DCOMPR
    POP HL
    JP C,FCERR
NXTRSL:
    PUSH DE                         ; keep the number
    LD E,[HL]                       ; DE = the line's link
    INC HL
    LD D,[HL]
    LD A,D
    OR E
    EX DE,HL                        ; HL = the next line
    POP DE                          ; DE = the number
    JP Z,RESSD1                     ; the end of the program
    LD A,[HL]                       ; is the next line the last, with a zero link?
    INC HL
    OR [HL]
    DEC HL
    EX DE,HL                        ; HL = the number, DE = the next line
    JP NZ,NXTRSC
RESSD1:
    PUSH BC
    CALL SCCLIN                     ; line numbers in the text to pointers
    POP BC                          ; BC = the increment
    POP DE                          ; DE = new
    POP HL                          ; HL = the first line to renumber
RESNX1:
    PUSH DE                         ; keep the number
    LD E,[HL]                       ; DE = the link
    INC HL
    LD D,[HL]
    LD A,D
    OR E
    JP Z,SCCALL                     ; the end of the program
    EX DE,HL                        ; stack the link, DE = the number
    EX [SP],HL
    EX DE,HL
    INC HL                          ; store the line's new number
    LD [HL],E
    INC HL
    LD [HL],D
    EX DE,HL                        ; the next number
    ADD HL,BC
    EX DE,HL
    POP HL                          ; HL = the next line
    JP RESNX1
SCCALL:
    LD BC,STPRDY                    ; done: pointers back to numbers, then STPRDY drops the number left
                                    ; on the stack
    PUSH BC
    .byte $FE                       ; CP n: skips SCCLIN's OR, so A = 0 at SCCPTR

;; Converts the line numbers in the program text to pointers to their lines.
;;
;; Prints "Undefined line n in m" for a number with no line, leaving it a number.
;; Out:   PTRFLG = nonzero
;; Entry: SCCPTR = converts the pointers back to line numbers, setting PTRFLG to zero
SCCLIN:
    .byte $F6                       ; OR n: A = nonzero, skipping the XOR
SCCPTR:
    XOR A
    LD [PTRFLG],A                   ; nonzero while the text has pointers
    LD HL,[TXTTAB]
    DEC HL
SCNPLN:
    INC HL                          ; HL = the next line
    LD A,[HL]
    INC HL
    OR [HL]
    RET Z                           ; a zero link ends the program
    INC HL
    LD E,[HL]                       ; DE = the line's number, for the message
    INC HL
    LD D,[HL]
SCNEXT:
    CALL CHRGTR
SCNEX2:
    OR A
    JP Z,SCNPLN                     ; the end of the line
    LD C,A
    LD A,[PTRFLG]                   ; which way?
    OR A
    LD A,C
    JP Z,SCNPT2                     ; pointers to numbers
    CP TK_ERROR                     ; ERROR
    JP NZ,NTERRG
    CALL CHRGTR
    CP TK_GOTO                      ; ERROR GOTO
    JP NZ,SCNEX2
    CALL CHRGTR
    CP LINCON
    JP NZ,SCNEX2
    PUSH DE
    CALL LINGT3                     ; DE = the line number
    LD A,D
    OR E
    JP NZ,CHGPTR
    JP SCNEX3                       ; ON ERROR GOTO 0 stays a number
NTERRG:
    CP LINCON                       ; LINCON: a line number
    JP NZ,SCNEXT
    PUSH DE
    CALL LINGT3                     ; DE = the line number
CHGPTR:
    PUSH HL
    CALL FNDLIN                     ; find the line
    DEC BC                          ; BC = the zero ending the line before
    LD A,PTRCON
    JP C,MAKPTR                     ; found: make it a pointer
    CALL CRDONZ
    LD HL,LINM
    PUSH DE
    CALL STROUT
    POP HL
    CALL LINPRT                     ; the missing number
    POP BC
    POP HL                          ; HL = the number of the line it is in
    PUSH HL
    PUSH BC
    CALL INPRT                      ; " in m"
SCNPOP:
    POP HL                          ; HL = the text pointer
SCNEX3:
    POP DE                          ; DE = the line's number
    DEC HL
JSCNXT:
    JP SCNEXT

;; The message for a line number with no line.
LINM:
    .byte "Undefined line ", 0
SCNPT2:
    CP PTRCON                       ; PTRCON: a pointer
    JP NZ,JSCNXT
    PUSH DE
    CALL LINGT3                     ; DE = the pointer
    PUSH HL
    EX DE,HL
    INC HL                          ; past the zero and the link
    INC HL
    INC HL
    LD C,[HL]                       ; BC = the line's number
    INC HL
    LD B,[HL]
    LD A,LINCON
MAKPTR:
    LD HL,SCNPOP                    ; go on scanning after the change
    PUSH HL
    LD HL,[CONTXT]                  ; the text after the constant

;; Rewrites the three-byte constant before HL as the token in A with the value in BC.
;; In:    HL = the text after the constant, A = the token, BC = the value
;; Out:   HL = unchanged
;; Keeps: A, BC, DE, HL
CONCH2:
    PUSH HL
    DEC HL
    LD [HL],B
    DEC HL
    LD [HL],C
    DEC HL
    LD [HL],A
    POP HL
    RET

;; Converts the program's line pointers back to line numbers, if it has any.
;; Out:   PTRFLG = zero
DEPTR:
    LD A,[PTRFLG]
    OR A
    RET Z
    JP SCCPTR

;; Runs OPTION BASE, making 0 or 1 the arrays' lowest subscript.
;;
;; It can be set only once, and only before any array exists.
;; In:    HL = the text after OPTION
;; Errors: SN error for anything but BASE 0 or BASE 1, DD error if it is set already or an array exists
ST_OPTION:
    CALL SYNCHR
    .byte 'B'
    CALL SYNCHR
    .byte 'A'
    CALL SYNCHR
    .byte 'S'
    CALL SYNCHR
    .byte 'E'
    LD A,[OPTFLG]                   ; set once already?
    OR A
    JP NZ,DDERR
    PUSH HL
    LD HL,[ARYTAB]                  ; any arrays?
    EX DE,HL
    LD HL,[STREND]
    CALL DCOMPR
    JP NZ,DDERR
    POP HL
    LD A,[HL]                       ; the base
    SUB '0'
    JP C,SNERR
    CP $02
    JP NC,SNERR
    LD [OPTVAL],A
    INC A
    LD [OPTFLG],A                   ; OPTFLG = nonzero
    CALL CHRGTR
    RET

;; Prints the zero-terminated message at HL to the console, whatever the output is going to.
;; In:    HL = the message
;; Out:   HL = the zero at its end
STRPRN:
    LD A,[HL]
    OR A
    RET Z
    CALL CALTTY
    INC HL
    JP STRPRN

;; Prints the character in A to the console, whatever the output is going to.
;; In:    A = the character
CALTTY:
    PUSH AF                         ; the console output routine pops it
    JP OUTCON
