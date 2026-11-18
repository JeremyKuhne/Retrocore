;; MBASIC 5.21: PRINT, LINE INPUT, INPUT AND READ
;;
;; The statements that move values between the program and the outside: PRINT and LPRINT write a list of
;; expressions, and LINE INPUT, INPUT and READ assign values to a list of variables from the keyboard, a file or
;; the program's DATA statements. GW-BASIC's GWMAIN.ASM holds the same LINE INPUT, INPUT and READ code under the
;; same names; its PRINT code was not published, so PRINT's names are those of Microsoft's 8080 BASIC as Level
;; II BASIC (Level2.asm) has them.
;;
;; - ST_PRINT picks the output with FILGET for PRINT #, and NEWCHR and PRINTC take the items in turn:
;;   USING goes to PRINT USING (PRINUS), TAB( and SPC( to TABER, a comma to COMPRT's next 14-column zone, and an
;;   expression is evaluated by FRMEVL and printed by STRDON, after a new line if it would not fit. FINPRT
;;   puts the output back to the console.
;; - ST_LINE (LINE INPUT) reads a whole line into one string variable.
;; - ST_INPUT prints its prompt with QTINP, reads a line, and checks the reply in a first pass (VARLOP) that
;;   assigns nothing, so that a reply of the wrong type or length asks again ("?Redo from start") instead of
;;   assigning half the variables. The second pass is READ's.
;; - ST_READ and the second pass of INPUT share LOPDAT: each variable gets the next value, a string through
;;   STRLT2 or a number through FIN, assigned by LET's code. DATLOP finds READ's next DATA statement.
;;
;; Runs at $1694-$19F6. FINPRT, QTINP and the DATA scan are also entered from the disk statements.

;; Runs LPRINT: PRINT to the printer.
;;
;; In:    HL = the text after LPRINT, A = its first character
;; Out:   HL = the end of the statement
ST_LPRINT:
    LD A,$01                        ; 1 = the printer
    LD [PRTFLG],A
    JP NEWCHR

;; Runs PRINT: picks the file for PRINT #, then prints each item of the list.
;;
;; Items are separated by commas, which move to the next print zone, or by semicolons, which print nothing.
;; Numbers are printed with a space after them, and an item that would not fit on the line starts a new one.
;; A list that does not end in a comma or semicolon ends with a new line.
;;
;; In:    HL = the text after PRINT, A = its first character
;; Out:   HL = the end of the statement
;; Entry: NEWCHR = takes the next item, the text pointer at the character before it,
;;   PRINTC = takes the item at HL, A and the flags from CHRGTR
ST_PRINT:
    LD C,$02                        ; the mode PRINT # needs: sequential output
    CALL FILGET                     ; PRINT #n, sets the file to print to
NEWCHR:
    DEC HL                          ; fetch the character again
    CALL CHRGTR
    CALL Z,CRDO                     ; PRINT alone prints an empty line
PRINTC:
    JP Z,FINPRT                     ; the statement ended
    CP $D9                          ; the USING token
    JP Z,PRINUS
    CP $D0                          ; the TAB( token
    JP Z,TABER
    CP $D4                          ; the SPC( token
    JP Z,TABER
    PUSH HL                         ; keep the text pointer
    CP ','                          ; a comma moves to the next print zone
    JP Z,COMPRT
    CP ';'                          ; a semicolon prints nothing
    JP Z,NOTABR
    POP BC                          ; drop the text pointer
    CALL FRMEVL                     ; evaluate the item
    PUSH HL
    CALL GETYPR
    JP Z,STRDON                     ; a string is printed as it is
    CALL FOUT                       ; a number becomes its text,
    CALL STRLIT                     ; a temporary string
    LD [HL],' '                     ; with a space after it:
    LD HL,[FACLO]                   ; HL = its descriptor
    INC [HL]                        ; one character longer

;; Prints the string in the FAC, first starting a new line if it would not fit on this one.
;;
;; Continues with the next item at NEWCHR.
;;
;; A file, a printer or console width of 255, and a cursor in the first column never start a new line.
;;
;; In:    FACLO = the string's descriptor, the text pointer on the stack
STRDON:
    CALL ISFLIO                     ; a file has no line length to check
    JP NZ,LINCH2
    LD HL,[FACLO]                   ; HL = the descriptor, its length first
    LD A,[PRTFLG]
    OR A
    JP Z,ISTTY                      ; zero: the console
    LD A,[LPTSIZ]                   ; B = the printer's width
    LD B,A
    INC A                           ; 255 is an endless line
    JP Z,LINCH2
    LD A,[LPTPOS]                   ; the printer's column
    OR A                            ; at the start of a line, it is printed there
    JP Z,LINCH2
    ADD A,[HL]                      ; plus the item's length
    CCF                             ; past 255: carry clear for a new line
    JP NC,LINCHK
    DEC A                           ; the last column it takes
    CP B                            ; carry clear when it is past the width
    JP LINCHK

;; Starts a new console line if the item at HL would not fit on the current one, then prints it.
;;
;; Continues with the next item at NEWCHR.
;;
;; In:    HL = the string's descriptor, the text pointer on the stack
ISTTY:
    LD A,[LINLEN]                   ; B = the console's width
    LD B,A
    INC A                           ; 255 is an endless line
    JP Z,LINCH2
    LD A,[TTYPOS]                   ; the cursor's column
    OR A                            ; at the start of a line, it is printed there
    JP Z,LINCH2
    ADD A,[HL]                      ; plus the item's length
    CCF                             ; past 255: carry clear for a new line
    JP NC,LINCHK
    DEC A                           ; the last column it takes
    CP B                            ; carry clear when it is past the width

;; Starts a new line if carry is clear, then prints the string in the FAC and goes on to the next item.
;;
;; Continues with the next item at NEWCHR.
;;
;; In:    carry = clear for a new line first, FACLO = the string's descriptor, the text pointer on the stack
;; Entry: LINCH2 = prints the string without a new line
LINCHK:
    CALL NC,CRDO
LINCH2:
    CALL STRPRT                     ; print the string
    POP HL                          ; HL = the text pointer
    JP NEWCHR

;; Moves PRINT's output to the next 14-column print zone, for a comma.
;;
;; Continues with the next item at PRINTC.
;;
;; The console and the printer start a new line instead from their last zone's column (CLMLST and NLPPOS,
;; which WIDTH sets); a file and a width of 255 never do.
;;
;; In:    HL = the text at the comma, also on the stack
COMPRT:
    LD BC,$0028                     ; the column's offset in a file's block
    LD HL,[PTRFIL]
    ADD HL,BC                       ; HL = the file's column
    CALL ISFLIO
    LD A,[HL]
    JP NZ,MORCOM                    ; a file: from its own column
    LD A,[PRTFLG]
    OR A
    JP Z,ISCTTY                     ; zero: the console
    LD A,[NLPPOS]                   ; B = the printer's last zone
    LD B,A
    INC A                           ; 255: no last zone
    LD A,[LPTPOS]                   ; A = the printer's column
    JP Z,MORCOM
    CP B
    JP CHKCOM

;; Moves to the console's next print zone, or starts a new line from the last zone's column.
;;
;; Continues with the next item at PRINTC.
;;
;; The text pointer is on the stack.
ISCTTY:
    LD A,[CLMLST]                   ; B = the console's last zone
    LD B,A
    LD A,[TTYPOS]                   ; A = the cursor's column
    CP $FF
    JP Z,MORCOM
    CP B                            ; at or past the last zone: a new line

;; Starts a new line if carry is clear, else prints the spaces to the next 14-column zone.
;;
;; Continues with the next item at PRINTC.
;;
;; In:    carry = clear for a new line, A = the column, the text pointer on the stack
;; Entry: MORCOM = prints the spaces from the column in A
CHKCOM:
    CALL NC,CRDO
    JP NC,NOTABR                    ; a new line is already a zone's start
MORCOM:
    SUB 14                          ; the column within its zone
    JP NC,MORCOM
    CPL                             ; A = the spaces to the next zone, less one
    JP ASPA2

;; Runs TAB( and SPC( in PRINT: prints spaces up to a column, or a number of spaces.
;;
;; Continues with the next item at PRINTC.
;;
;; The count is taken modulo the line's width, unless the width is 255 or the output is a file. TAB( to a
;; column left of the cursor starts a new line first.
;;
;; In:    HL = the text at the TAB( or SPC( token, A = the token
TABER:
    PUSH AF                         ; keep the token
    CALL CHRGTR
    CALL GETIN2                     ; DE = the column or count
    POP AF
    PUSH AF
    CP $D4                          ; SPC( counts spaces;
    JP Z,TABER_1
    DEC DE                          ; TAB( columns start from 1
TABER_1:
    LD A,D
    OR A
    JP P,TABER_2
    LD DE,$0000                     ; a negative value is 0
TABER_2:
    PUSH HL
    CALL ISFLIO                     ; a file: no width
    JP NZ,TABER_4
    LD A,[PRTFLG]
    OR A
    LD A,[LPTSIZ]                   ; the printer's width
    JP NZ,TABER_3
    LD A,[LINLEN]                   ; or the console's
TABER_3:
    LD L,A
    INC A                           ; 255: no width
    JP Z,TABER_4
    LD H,$00
    CALL IMOD                       ; HL = DE MOD the width
    EX DE,HL                        ; into DE
TABER_4:
    POP HL
    CALL SYNCHR                     ; the closing parenthesis
    .byte ')'
    DEC HL                          ; fetch the next character again later
    POP AF
    SUB $D4                         ; A = 0 for SPC(, the count from no column
    PUSH HL
    JP Z,DOSIZT
    LD BC,$0028                     ; TAB( counts from the column:
    LD HL,[PTRFIL]
    ADD HL,BC
    CALL ISFLIO
    LD A,[HL]                       ; a file's,
    JP NZ,DOSIZT
    LD A,[PRTFLG]
    OR A
    JP Z,TTYIST
    LD A,[LPTPOS]                   ; the printer's
    JP DOSIZT

;; Prints spaces from the cursor's column up to the column in E.
;;
;; Continues with the next item at PRINTC.
;;
;; In:    E = the column to tab to, the text pointer on the stack
TTYIST:
    LD A,[TTYPOS]                   ; or the console's

;; Prints the spaces from the column in A to the column in E, starting a new line if E is left of A.
;;
;; Continues with the next item at PRINTC.
;;
;; In:    A = the current column, E = the column to tab to, the text pointer on the stack
DOSIZT:
    CPL                             ; A = E - A - 1, carry when E is to the right
    ADD A,E
    JP C,ASPA2
    INC A                           ; already there
    JP Z,NOTABR
    CALL CRDO                       ; to the left: a new line,
    LD A,E                          ; then E spaces
    DEC A
    JP M,NOTABR

;; Prints A plus one spaces, then goes on to the next PRINT item.
;;
;; Continues with the next item at PRINTC.
;;
;; In:    A = the number of spaces, less one, the text pointer on the stack
;; Entry: NOTABR = prints nothing
ASPA2:
    INC A
    LD B,A                          ; B counts the spaces
    LD A,' '
REPOUT:
    CALL OUTDO
    DEC B
    JP NZ,REPOUT
NOTABR:
    POP HL                          ; HL = the text pointer
    CALL CHRGTR                     ; the next item or the end of the statement
    JP PRINTC

;; Ends PRINT, INPUT or READ: sends output back to the console.
;;
;; In:    HL = the text pointer
;; Out:   PRTFLG = 0, PTRFIL = 0, A = 0, HL kept
FINPRT:
    XOR A
    LD [PRTFLG],A                   ; not the printer
    PUSH HL
    LD H,A
    LD L,A
    LD [PTRFIL],HL                  ; nor a file
    POP HL
    RET

;; Runs LINE INPUT: reads a whole line, prompt and all, into a string variable.
;;
;; LINE INPUT # goes to the disk code (DLINE). Commas and quotes are part of the line.
;;
;; In:    HL = the text after LINE, A = its first character
;; Out:   HL = the end of the statement
;; Errors: SN if INPUT does not follow, TM if the variable is not a string
ST_LINE:
    CALL SYNCHR                     ; INPUT must follow LINE
    .byte $85                       ; the INPUT token
    CP '#'                          ; LINE INPUT # reads a file
    JP Z,DLINE
    CALL SCNSEM                     ; a semicolon: no new line after the reply
    CALL QTINP                      ; print a quoted prompt
    CALL PTRGET                     ; DE = the variable
    CALL CHKSTR                     ; which must be a string
    PUSH DE
    PUSH HL
    CALL SINLIN                     ; read the line
    POP DE                          ; DE = the text pointer
    POP BC                          ; BC = the variable
    JP C,STPEND                     ; Ctrl+C stops the program
    PUSH BC
    PUSH DE
    LD B,$00                        ; the line ends only at its zero
    CALL STRLT3                     ; make it a temporary string
    POP HL
    LD A,$03                        ; a string
    JP LETCN2                       ; assign it

;; The message INPUT prints when the reply does not fit the variables.
TRYAGN:
    .byte "?Redo from start", $0D, $0A, 0

;; Skips a quoted string in a subscript of INPUT's variable list, for the first pass.
;;
;; Continues the subscript scan at SCNCON.
;;
;; In:    HL = the text at the opening quote, B = the parenthesis depth
;; Errors: SN if the line ends inside the string
SCNSTR:
    INC HL
    LD A,[HL]
    OR A                            ; the line may not end in the string
    JP Z,SNERR
    CP '"'
    JP NZ,SCNSTR
    JP SCNCON                       ; the quote ends it

;; Drops INPUT's two data pointers and asks for the whole reply again.
;;
;; Returns to NEWSTT with HL = the INPUT statement, to run it again.
;;
;; Pass one's and pass two's data pointers are on the stack, above the variable list pointer and the return.
INPBAK:
    POP HL                          ; pass one's data pointer
    POP HL                          ; pass two's
    JP RDOIN2

;; Handles badly formed data: a syntax error at the DATA line for READ, or asks again for INPUT.
;;
;; Returns to NEWSTT with HL = the INPUT statement, to run it again.
;;
;; In:    FLGINP = nonzero for READ
;; Errors: SN, at the DATA line, for READ
;; Entry: RDOIN2 = asks again, dropping the variable list pointer
TRMNOK:
    LD A,[FLGINP]                   ; READ or INPUT?
    OR A
    JP NZ,DATSNE                    ; READ: the DATA is wrong
RDOIN2:
    POP BC                          ; drop the variable list pointer
    LD HL,TRYAGN                    ; "?Redo from start"
    CALL STROUT
    LD HL,[SAVTXT]                  ; back to the start of the INPUT statement
    RET

;; Runs INPUT #: reads the values from a file.
;;
;; Continues at INPCN3 with BUFMIN's comma as the data.
;;
;; In:    HL = the text at the #
FILSTI:
    CALL FILINP                     ; the file, which must be open for input
    PUSH HL
    LD HL,BUFMIN                    ; the comma before the buffer
    JP INPCN3

;; Runs INPUT: prints the prompt, reads a reply and assigns its values to the variables listed.
;;
;; The reply is checked first (VARLOP) without assigning anything: each variable must get a value of its type,
;; and there must be as many values as variables. If not, "?Redo from start" asks again.
;;
;; In:    HL = the text after INPUT, A = its first character
;; Out:   HL = the end of the statement
ST_INPUT:
    CP '#'                          ; INPUT # reads a file
    JP Z,FILSTI
    CALL SCNSEM                     ; a semicolon: no new line after the reply
    LD BC,NOTQTI                    ; read the reply after the prompt
    PUSH BC

;; Prints the quoted prompt at HL and the semicolon or comma after it, or returns at once if there is none.
;;
;; Turns Ctrl+O's output suppression off. A comma after the prompt leaves out the "? ".
;;
;; In:    HL = the text, A = the character there
;; Out:   HL = the text after the prompt, TEMPA_HI = 0 if a comma followed the prompt, else $FF
;; Errors: SN if neither a comma nor a semicolon follows the prompt
QTINP:
    CP '"'                          ; a prompt?
    LD A,$00
    LD [CNTOFL],A                   ; output on again
    LD A,$FF                        ; print "? " after it
    LD [TEMPA_HI],A
    RET NZ                          ; no prompt
    CALL STRLTI                     ; make it a string
    LD A,[HL]
    CP ','                          ; a comma: no "? "
    JP NZ,NTICMA
    XOR A
    LD [TEMPA_HI],A
    CALL CHRGTR                     ; skip the comma
    JP INPCMA

;; Requires the semicolon after INPUT's prompt, then prints the prompt.
;;
;; In:    HL = the text after the prompt, FACLO = the prompt string
;; Out:   HL = the text after the semicolon
;; Errors: SN if it is not a semicolon
;; Entry: INPCMA = prints the prompt
NTICMA:
    CALL SYNCHR
    .byte ';'
INPCMA:
    PUSH HL
    CALL STRPRT                     ; print the prompt
    POP HL
    RET

;; Prints "? " unless the prompt ended in a comma, reads the reply, and checks it against the variables.
;;
;; Continues with the second pass at INPCN3, or asks again at INPBAK or RDOIN2.
;;
;; This is the first pass: it walks the variable list with PTRGTN, skipping subscripts without evaluating
;; them, and scans a value for each with SCNVAL, which assigns nothing (INPPAS zero). The reply must have a
;; value of the right type for each variable and nothing after the last.
;;
;; In:    HL = the variable list
;; Errors: SN for a badly formed variable list
NOTQTI:
    PUSH HL                         ; keep the variable list pointer
    LD A,[TEMPA_HI]                 ; "? "?
    OR A
    JP Z,SUPPRS
    LD A,'?'
    CALL OUTDO
    LD A,' '
    CALL OUTDO

;; Reads INPUT's reply and checks it, without the "? ".
;;
;; Continues with the second pass at INPCN3.
;;
;; The variable list pointer is on the stack.
SUPPRS:
    CALL SINLIN                     ; read the reply into the buffer
    POP BC
    JP C,STPEND                     ; Ctrl+C stops the program
    PUSH BC
    XOR A                           ; INPUT, so SCNVAL stops strings at commas only
    LD [FLGINP],A
    LD [HL],','                     ; a comma in front of the reply
    EX DE,HL                        ; DE = the data pointer
    POP HL                          ; HL = the variable list
    PUSH HL                         ; kept for pass two
    PUSH DE                         ; the data pointer for pass two
    PUSH DE                         ; and for pass one
    DEC HL

;; Skips the next variable of INPUT's list, subscripts and all, and scans a value for it from the reply.
;;
;; Continues at INPCN3 when the list and the reply end together, else asks again.
;;
;; In:    HL = the variable list, at the comma or before the first variable,
;;   pass one's data pointer, pass two's and the variable list on the stack
;; Errors: SN for a badly formed list
VARLOP:
    LD A,$80                        ; no subscripts: stop at the "("
    LD [SUBFLG],A
    CALL CHRGTR
    CALL PTRGTN                     ; scan the name, DE = the variable
    LD A,[HL]
    DEC HL                          ; fetch the terminator again
    CP '['                          ; brackets work as parentheses
    JP Z,SCNBKT
    CP '('                          ; an array?
    JP NZ,ENDSCN

;; Skips a subscript in INPUT's variable list, counting nested parentheses and brackets.
;;
;; Continues at ENDSCN after the closing parenthesis.
;;
;; In:    HL = the text before the opening parenthesis
;; Errors: SN if the statement ends inside the subscript
;; Entry: SCNOPN = counts one more level, SCNCON = takes the next character
SCNBKT:
    INC HL
    LD B,$00                        ; B = the depth
SCNOPN:
    INC B
SCNCON:
    CALL CHRGTR
    JP Z,SNERR                      ; no end to the subscript
    CP '"'                          ; a string may hold parentheses
    JP Z,SCNSTR
    CP '('
    JP Z,SCNOPN
    CP '['
    JP Z,SCNCON
    CP ']'
    JP Z,LEFPRN
    CP ')'
    JP NZ,SCNCON

;; Closes one level of a subscript in INPUT's variable list; at the outermost, the variable is done.
;;
;; Continues at SCNCON or ENDSCN.
;;
;; In:    B = the depth
LEFPRN:
    DEC B
    JP NZ,SCNCON

;; Checks what follows a variable of INPUT's list, then scans the reply's value for it.
;;
;; Continues at VARLOP for the next variable, at INPCN3 when all is well, or asks again.
;;
;; In:    HL = the text before the terminator, DE = the variable
;; Errors: SN unless a comma or the end of the statement follows
ENDSCN:
    CALL CHRGTR
    JP Z,OKVLST                     ; the last variable
    CP ','                          ; else a comma must follow
    JP NZ,SNERR

;; Scans one value of INPUT's reply for the variable at DE, checking its type and that it ended well.
;;
;; Continues at VARLOP, INPCN3, INPBAK or RDOIN2.
;;
;; In:    HL = the variable list, at the terminator, the data pointer on the stack
OKVLST:
    EX [SP],HL                      ; keep the list, HL = the data
    LD A,[HL]
    CP ','                          ; each value follows a comma
    JP NZ,INPBAK
    LD A,$01                        ; OVCSTR counts overflows from 1
    LD [OVCSTR],A
    CALL SCNVAL                     ; scan the value, assigning nothing
    LD A,[OVCSTR]                   ; a number too big asks again
    DEC A
    JP NZ,INPBAK
    PUSH HL
    CALL GETYPR                     ; free a string scanned
    CALL Z,FREFAC
    POP HL
    DEC HL                          ; skip spaces after the value
    CALL CHRGTR
    EX [SP],HL                      ; keep the data, HL = the list
    LD A,[HL]
    CP ','                          ; another variable?
    JP Z,VARLOP
    POP HL                          ; HL = the data after the last value
    DEC HL
    CALL CHRGTR
    OR A                            ; it must end there
    POP HL                          ; HL = the data, for pass two
    JP NZ,RDOIN2

;; Puts the comma before INPUT's data and starts the assignment pass shared with READ.
;;
;; Continues at INPCON.
;;
;; In:    HL = the byte before the data, the variable list on the stack
INPCN3:
    LD [HL],','
    JP INPCON

;; Runs READ: assigns values from the DATA statements, from where the last READ stopped.
;;
;; In:    HL = the text after READ, A = its first character
;; Out:   HL = the end of the statement, DATPTR = where the data stopped
;; Errors: OD if the DATA runs out, SN at the DATA line for a badly formed value
;; Entry: INPCON = enters for INPUT's second pass, with HL at the data and the variable list on the stack
ST_READ:
    PUSH HL                         ; keep the variable list pointer
    LD HL,[DATPTR]                  ; HL = where the last READ stopped
    .byte $F6                       ; OR $AF: skip the XOR A, A nonzero for READ
INPCON:
    XOR A                           ; zero for INPUT
    LD [FLGINP],A
    EX [SP],HL                      ; stack the data, HL = the variable list
    JP LOPDAT

;; Requires the comma between variables, then assigns the next one.
;;
;; In:    HL = the variable list, the data pointer on the stack
;; Errors: SN without the comma
;; Entry: LOPDAT = assigns the variable at HL
LOPDT2:
    CALL SYNCHR
    .byte ','
LOPDAT:
    CALL PTRGET                     ; DE = the variable to fill
    EX [SP],HL                      ; stack the list, HL = the data
    PUSH DE
    LD A,[HL]
    CP ','                          ; a comma: a value follows
    JP Z,DATBK
    LD A,[FLGINP]                   ; else READ looks for the next DATA
    OR A
    JP NZ,DATLOP

;; Reads one value from the data at HL into the variable on the stack, a string or a number by its type.
;;
;; Continues at STRDN2 once the value is assigned.
;;
;; A quoted string ends at its quote. An unquoted one ends at a comma, or for READ a colon too. Files go to
;; FILIND.
;;
;; In:    HL = the data, at the comma before the value, the variable and the data list on the stack
;; Entry: SCNVAL = scans the value without assigning it, for INPUT's first pass, and returns
DATBK:
    .byte $F6                       ; OR $AF: skip the XOR A, A nonzero to assign
SCNVAL:
    XOR A                           ; zero: scan only
    LD [INPPAS],A
    CALL ISFLIO                     ; a file has its own rules
    JP NZ,FILIND
    CALL GETYPR                     ; the variable's type
    PUSH AF
    JP NZ,NUMINS                    ; a number
    CALL CHRGTR
    LD D,A                          ; a quoted string ends at its quote
    LD B,A
    CP '"'
    JP Z,NOWGET
    LD A,[FLGINP]
    OR A
    LD D,A                          ; INPUT: a colon is part of the string
    JP Z,NCOLST
    LD D,':'                        ; READ: a colon ends it

;; Sets the comma as an unquoted string's other terminator and makes the string.
;;
;; Continues at DOASIG.
;;
;; In:    HL = the text at the string's first character, D = the other terminator
NCOLST:
    LD B,','
    DEC HL                          ; include the first character

;; Makes a string from the data at HL, ending at the terminator in B or D, and assigns it.
;;
;; Continues at DOASIG.
;;
;; In:    HL = the text before the string, B, D = the terminators
NOWGET:
    CALL STRLT2                     ; make the string

;; Assigns the value in the FAC to the variable on the stack, through LET's code, then goes on at STRDN2.
;;
;; For INPUT's first pass (INPPAS zero) it returns instead, to OKVLST.
;;
;; In:    HL = the data after the value, GETYPR's flags and the variable on the stack
DOASIG:
    POP AF                          ; A = the type less 3
    ADD A,$03
    LD C,A                          ; C = the type
    LD A,[INPPAS]                   ; scanning only?
    OR A
    RET Z
    LD A,C
    EX DE,HL                        ; DE = the data
    LD HL,STRDN2                    ; return there,
    EX [SP],HL                      ; HL = the variable
    PUSH DE
    JP INPCOM                       ; assign it

;; Converts the number in the data at HL into the FAC, in double precision for a double variable.
;;
;; Continues at DOASIG.
;;
;; In:    HL = the data, GETYPR's flags on the stack
NUMINS:
    CALL CHRGTR                     ; skip spaces before it
    POP AF
    PUSH AF
    LD BC,DOASIG                    ; then assign it
    PUSH BC
    JP C,FIN                        ; carry: not double precision
    JP FINDBL                       ; double precision

;; Checks that a value read ended at a comma or at the end of the data, then goes on to the next variable.
;;
;; Continues at LOPDT2 for another variable, or ends the statement.
;;
;; At the end of the list, READ keeps the data pointer in DATPTR and INPUT's statement ends.
;;
;; In:    HL = the data after the value, the variable list on the stack
;; Entry: TRMOK = goes on to the next variable
STRDN2:
    DEC HL
    CALL CHRGTR
    JP Z,TRMOK                      ; the data ended
    CP ','                          ; or a comma follows
    JP NZ,TRMNOK
TRMOK:
    EX [SP],HL                      ; stack the data, HL = the list
    DEC HL
    CALL CHRGTR
    JP NZ,LOPDT2                    ; another variable follows
    POP DE                          ; DE = the data
    LD A,[FLGINP]
    OR A
    EX DE,HL                        ; HL = the data, DE = the text
    JP NZ,RESFIN                    ; READ: keep the data pointer
    PUSH DE                         ; INPUT: HL = the text pointer
    POP HL
    JP FINPRT

;; Skips to the next DATA statement for READ, keeping each line's number in DATLIN for errors.
;;
;; Continues at DATBK with HL at the DATA statement.
;;
;; In:    HL = the text, the variable and the data list on the stack
;; Errors: OD at the end of the program
;; Entry: NOWLIN = checks the statement at HL
DATLOP:
    CALL ST_DATA                    ; skip the statement
    OR A                            ; zero: the line ended
    JP NZ,NOWLIN
    INC HL                          ; the link to the next line
    LD A,[HL]
    INC HL
    OR [HL]                         ; zero: the end of the program
    LD E,$04                        ; Out of DATA
    JP Z,ERROR
    INC HL
    LD E,[HL]                       ; DE = the line's number
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [DATLIN],HL
    EX DE,HL
NOWLIN:
    CALL CHRGTR                     ; the statement's token
    CP $84                          ; DATA?
    JP NZ,DATLOP
    JP DATBK
