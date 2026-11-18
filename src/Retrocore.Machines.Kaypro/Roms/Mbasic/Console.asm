;; MBASIC 5.21: EDIT, PRINT USING, CONSOLE AND PRINTER I/O, AND MEMORY CHECKS
;;
;; The line editor, the formatter, and the character layer every other module prints and reads through. In order:
;;
;; - ERREDT has READY start EDIT on the line that had a syntax error.
;; - ST_EDIT is the EDIT statement: it expands a program line into BUF and runs the editor's commands on it,
;;   each optionally preceded by a repeat count: space, backspace and rubout move the cursor; S and K search for a
;;   character; I, X and H insert; D deletes; C changes; L lists; E and Return keep the change (EDITRT, which
;;   enters it through the line-entry code); Q and A abandon it. The same editor edits a typed line when INLIN
;;   (LineInput.asm) hands it one after Control-A (INLED, line number $FFFF), and the error handler starts it after a
;;   syntax error in a program (EREDIT). GW-BASIC replaced this editor with its screen editor; Level2.asm keeps a
;;   close relative, whose names it takes. MBASIC brackets deleted text with backslashes, not exclamation marks.
;; - PRINUS is PRINT USING, matching BIPRTU.ASM routine for routine: it scans the format string for string fields
;;   (\ \, ! and &), numeric fields (# . + - , ** $$ **$ and ^^^^), and the literal escape _, printing each value
;;   through PUFOUT or LEFTUS and reusing the format until the values run out.
;; - OUTDO prints a character on the current device: an open file when PTRFIL is set (FILOUT), the
;;   printer when PRTFLG is set (LPTOUT, tracking LPTPOS against the width in LPTSIZ), and
;;   otherwise the console (OUTCON, tracking TTYPOS against the width in LINLEN, and printing nothing while
;;   Control-O has output suppressed). Tabs become spaces to the next multiple of 8, and a line at the width wraps.
;;   CRDO prints a new line, CRFIN resets the column and sends NULCNT nulls, CRDONZ starts a new line
;;   only when needed, FINLPT ends LPRINT output, and OUTCH1 prints a line feed as a new line.
;; - INCHR reads a character from the file being loaded, or from the console through INCHRI, which handles Control-O.
;;   ISCNTC polls the console between statements for Control-C, and pauses on Control-S; INKEY is INKEY$.
;; - BLTU and BLTUC move a block of memory up; GETSTK, REASON and OMERR check for room and report Out of memory.
;;
;; MBASIC does not use the BDOS for the console and printer: its startup (Init.asm) reads the BIOS's jump table
;; through the warm-boot vector at $0001 and patches the addresses of CONST (BIOS+6), CONIN (BIOS+9), CONOUT (BIOS+12)
;; and LIST (BIOS+15) into the CALLs at CSTSVC, CSTKVC, CONIVC, CONOVC and LISTVC (and NEWSTT's in Statements.asm),
;; so no BDOS function numbers appear here. Each patched call passes the character in C and returns it in A, as the
;; BIOS does, saving BC, DE and HL around the call.
;;
;; The GW-BASIC counterparts are BIPRTU.ASM (PRINT USING), BIMISC.ASM and MATH1.ASM (GETSTK, REASON, OMERR, BLTU),
;; with GWMAIN.ASM's and GWLIST.ASM's callers of OUTDO, CRDO, OUTCH1 and FINLPT; GW-BASIC's own console layer is the
;; IBM PC's screen driver, so MBASIC's CP/M one has no counterpart there. Level2.asm's OUTDO, CRDO and ISCNTC are
;; close relatives. Runs at $3CD5-$4309. The main entry points are ST_EDIT, PRINUS, OUTDO, CRDO,
;; CRDONZ, OUTCH1, INCHR, INCHRI, ISCNTC, INKEY, BLTU, BLTUC, GETSTK, REASON and OMERR.

;; Starts EDIT on the line that had a syntax error, from READY, unless the error was in direct mode.
;;
;; Doesn't return when it edits: EDIT's entry drops this call's return address.
;; In:    A = 0, ERRLIN = the line with the error
;; Out:   ERRFLG = 0, zero = set in direct mode, DE = the line
ERREDT:
    LD [ERRFLG],A                   ; ERRFLG = 0
    LD HL,[ERRLIN]
    OR H                            ; $FFFF is direct mode
    AND L
    INC A
    EX DE,HL                        ; DE = the line
    RET Z
    JP EREDIT                       ; EDIT it

;; Executes EDIT, letting the user change a program line with the editor's commands; UL error if it is missing.
;;
;; The line is expanded into BUF, its number printed, and the editor's command loop (DISPED) run on it.
;; B is the cursor's position in the line, C the line's length, D the command's repeat count and HL the cursor.
;; Every command handler returns to DISPED for the next command, through the address NOTDGI pushes.
;;
;; In:    HL = the text after EDIT, at the line number or period
;; Errors: UL (8) when the line does not exist
;; Entry: EREDIT = after a syntax error in a program line, from the error handler (Variables.asm), with DE = the
;;          line's number and a return address to drop, EEDITS = DE = the line's number
ST_EDIT:
    CALL LINSPC                     ; DE = the line number
    RET NZ                          ; anything after it is a syntax error
EREDIT:
    POP HL                          ; drop the return address to NEWSTT
EEDITS:
    EX DE,HL
    LD [DOT],HL                     ; the edited line becomes the current line
    EX DE,HL
    CALL FNDLIN                     ; BC = the line, carry = found
    JP NC,USERR                     ; no such line: UL error
    LD H,B                          ; HL = the line found
    LD L,C
    INC HL                          ; step past its link
    INC HL
    LD C,[HL]                       ; BC = the line number
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC                         ; save it for printing
    CALL BUFLIN                     ; expand the line into BUF
LLED:
    POP HL                          ; HL = the line number

;; Prints the line number, or ! for a typed line, then runs the editor's command loop on the line in BUF.
;;
;; INLIN (LineInput.asm) jumps here on Control-A, with HL = $FFFF, to edit the line being typed.
;;
;; In:    HL = the line's number, $FFFF for a typed line, BUF = the line, ending in a zero
INLED:
    PUSH HL                         ; keep the number for reprints and the end of the edit
    LD A,H
    AND L
    INC A                           ; zero when the number is $FFFF
    LD A,'!'
    CALL Z,OUTDO                    ; a typed line shows ! for its number
    CALL NZ,LINPRT
    LD A,' '
    CALL OUTDO
    LD HL,BUF                       ; HL = the text in BUF
    PUSH HL                         ; save the text's start
    LD C,$FF                        ; C counts the line's length
LENLP:
    INC C
    LD A,[HL]
    INC HL
    OR A
    JP NZ,LENLP                     ; until the zero that ends it
    POP HL                          ; back to the start of the text
    LD B,A                          ; B = the cursor's position, 0

;; Reads one EDIT command, with its repeat count, and runs it; every handler returns here.
;;
;; In:    HL = the cursor in BUF, B = its position, C = the line's length
DISPED:
    LD D,$00                        ; no repeat count yet
DISPI:
    CALL INCHRI
    OR A
    JP Z,DISPI                      ; Control-O returns zero: wait for a real key
    CALL MAKUPS                     ; raise a lowercase letter to a capital
    SUB '0'                         ; digit keys build a repeat count
    JP C,NOTDGI
    CP 10
    JP NC,NOTDGI
    LD E,A                          ; E = the digit's value
    LD A,D                          ; D = D times ten
    RLCA
    RLCA
    ADD A,D
    RLCA
    ADD A,E                         ; plus the new digit
    LD D,A
    JP DISPI

;; Dispatches an EDIT command key, less '0', to its handler, which returns to DISPED; unknown keys beep.
;;
;; In:    A = the key less '0', D = the repeat count, 0 for none, HL = the cursor, B = its position, C = the length
NOTDGI:
    PUSH HL
    LD HL,DISPED                    ; the handlers return to DISPED for the next key
    EX [SP],HL
    DEC D
    INC D
    JP NZ,NTZERD
    INC D                           ; no count given: do the command once
NTZERD:
    CP $D8                          ; backspace ($08) less '0'
    JP Z,DELED
    CP $4F                          ; rubout ($7F) less '0'
    JP Z,RUBED
    CP $DD                          ; Return ($0D) less '0'
    JP Z,CRED
    CP $F0                          ; space less '0'
    JP Z,SPED
    CP 'a'-'0'
    JP C,NOTLW4
    SUB 'a'-'A'                     ; fold a lowercase command to its capital (MAKUPS has already)
NOTLW4:
    CP 'Q'-'0'                      ; Q quits without changes
    JP Z,QED
    CP 'L'-'0'                      ; L lists the line
    JP Z,LED
    CP 'S'-'0'                      ; S searches for a character
    JP Z,SED
    CP 'I'-'0'                      ; I inserts
    JP Z,IED
    CP 'D'-'0'                      ; D deletes
    JP Z,DED
    CP 'C'-'0'                      ; C changes characters
    JP Z,CED
    CP 'E'-'0'                      ; E ends the edit, keeping the changes
    JP Z,EED
    CP 'X'-'0'                      ; X extends the line at its end
    JP Z,XED
    CP 'K'-'0'                      ; K kills up to a character
    JP Z,KED
    CP 'H'-'0'                      ; H hacks off the rest and inserts
    JP Z,HED
    CP 'A'-'0'                      ; A starts again with the unchanged line
    LD A,$07                        ; any other key rings the bell
    JP NZ,OUTDO
    POP BC                          ; drop the return address to DISPED
    POP DE                          ; DE = the line number
    CALL CRDO
    JP EEDITS

;; Handles space in EDIT, printing and moving past up to D characters of the line.
;; In:    HL = the cursor, B = its position, D = the count
;; Out:   HL, B = moved past the characters
SPED:
    LD A,[HL]
    OR A
    RET Z                           ; stop at the end of the line
    INC B                           ; advance the cursor's position
    CALL OUTCH1
    INC HL
    DEC D
    JP NZ,SPED                      ; repeat count times
    RET

;; Handles the EDIT K command, deleting characters up to the D-th occurrence of a typed character.
;;
;; The deleted characters are shown between backslashes; K returns through TYPSLH to print the closing one.
;;
;; In:    HL = the cursor, B = its position, C = the line's length, D = the count
KED:
    PUSH HL
    LD HL,TYPSLH                    ; return through TYPSLH to close the backslashes
    EX [SP],HL
    SCF                             ; carry selects K's delete mode

;; Handles the EDIT S command, moving the cursor to the D-th occurrence of a typed character.
;; In:    HL = the cursor, B = its position, D = the count, carry = set for K (delete the characters passed)
SED:
    PUSH AF                         ; save the K or S mode
    CALL INCHRI                     ; E = the character to search for
    LD E,A
    POP AF
    PUSH AF
    CALL C,TYPSLH                   ; K opens its backslash
SRCALP:
    LD A,[HL]
    OR A
    JP Z,POPART                     ; the line ended: stop searching
    CALL OUTCH1
    POP AF
    PUSH AF
    CALL C,DELCHR                   ; K deletes the character instead of passing it
    JP C,NOTSRC
    INC HL                          ; S moves past it
    INC B
NOTSRC:
    LD A,[HL]
    CP E
    JP NZ,SRCALP                    ; not the character: keep going
    DEC D
    JP NZ,SRCALP                    ; stop at its D-th occurrence
POPART:
    POP AF                          ; drop the mode
    RET

;; Handles the EDIT L command, printing the rest of the line and starting again at its beginning.
LED:
    CALL LISPRT                     ; print the rest of the line
    CALL CRDO
    POP BC                          ; drop the return address to DISPED
    JP LLED

;; Handles the EDIT D command, deleting D characters and showing them between backslashes.
;; In:    HL = the cursor, C = the line's length, D = the count
DED:
    LD A,[HL]
    OR A
    RET Z                           ; nothing to delete at the end of the line
    LD A,$5C                        ; open the backslashes
    CALL OUTCH1
DELLP:
    LD A,[HL]
    OR A
    JP Z,TYPSLH                     ; the line ended: close the backslashes
    CALL OUTCH1
    CALL DELCHR                     ; remove it from the line
    DEC D
    JP NZ,DELLP

;; Prints the backslash that brackets the characters EDIT deletes.
;; Out:   A = the backslash
TYPSLH:
    LD A,$5C
    CALL OUTDO
    RET

;; Handles the EDIT C command, replacing D characters with typed ones.
;;
;; A replacement must be printable, or a line feed, bell or tab; any other key rings the bell and is ignored.
;;
;; In:    HL = the cursor, B = its position, D = the count
CED:
    LD A,[HL]
    OR A
    RET Z                           ; nothing to change at the end of the line
CED_1:
    CALL INCHRI                     ; read the replacement
    CP ' '
    JP NC,CED_2                     ; printable
    CP $0A                          ; line feed
    JP Z,CED_2
    CP $07                          ; bell
    JP Z,CED_2
    CP $09                          ; tab
    JP Z,CED_2
    LD A,$07                        ; any other control character: ring the bell
    CALL OUTDO
    JP CED_1
CED_2:
    LD [HL],A                       ; overwrite the line's character
    CALL OUTCH1
    INC HL
    INC B
    DEC D
    JP NZ,CED
    RET

;; Handles the EDIT H command, removing the rest of the line and entering insert mode.
HED:
    LD [HL],$00                     ; end the line at the cursor
    LD C,B                          ; C = the new length

;; Handles the EDIT X command, moving to the end of the line and entering insert mode.
XED:
    LD D,$FF                        ; as many characters as remain
    CALL SPED                       ; move to the end of the line

;; Handles the EDIT I command, inserting typed characters until Return or Escape.
;;
;; Rubout and underline delete the character before the cursor, echoing an underline; backspace deletes it,
;; backing up. Return ends the edit, Escape returns to the command loop, and other control characters except
;; line feed, bell and tab are ignored.
;;
;; In:    HL = the cursor, B = its position, C = the line's length
IED:
    CALL INCHRI
    CP $7F                          ; rubout
    JP Z,TYPARW
    CP $08                          ; backspace
    JP Z,TYPAR1
    CP $0D
    JP Z,CRED                       ; Return ends the edit
    CP $1B
    RET Z                           ; Escape leaves insert mode
    CP $08
    JP Z,TYPAR1
    CP $0A                          ; line feed, bell and tab are inserted
    JP Z,NTARRW
    CP $07
    JP Z,NTARRW
    CP $09
    JP Z,NTARRW
    CP ' '
    JP C,IED                        ; ignore other control characters
    CP '_'
    JP NZ,NTARRW                    ; insert anything else; underline is a rubout

;; Deletes the character before the cursor in EDIT's insert mode, echoing an underline (rubout) or A (backspace).
;; In:    HL = the cursor, B = its position, C = the line's length
;; Entry: TYPAR1 = A = the character to echo
TYPARW:
    LD A,'_'
TYPAR1:
    DEC B
    INC B
    JP Z,DINGI                      ; at the line's start: nothing to delete
    CALL OUTCH1
    DEC HL                          ; move the cursor back
    DEC B
    LD DE,IED                       ; return to insert mode after deleting
    PUSH DE

;; Deletes the character at HL in EDIT by moving the rest of the line, with its zero, down a byte.
;; In:    HL = the character, C = the line's length
;; Out:   C = one less, carry = set
;; Keeps: HL, B, DE
DELCHR:
    PUSH HL
    DEC C                           ; the line is one shorter
CMPRSS:
    LD A,[HL]
    OR A
    SCF
    JP Z,POPHRT                     ; done at the zero, with carry set
    INC HL
    LD A,[HL]                       ; move the next character down
    DEC HL
    LD [HL],A
    INC HL
    JP CMPRSS

;; Inserts the typed character in A at the cursor in EDIT if the line has room; otherwise rings the bell.
;; In:    A = the character, HL = the cursor, B = its position, C = the line's length
NTARRW:
    PUSH AF
    LD A,C
    CP $FF                          ; room only while the length is under 255
    JP C,OKINS
    POP AF                          ; the line is full: refuse the key
DINGI:
    LD A,$07                        ; ring the bell
    CALL OUTDO
DINGI_1:
    JP IED
OKINS:
    SUB B                           ; A = the characters after the cursor
    INC C                           ; the line is one longer
    INC B                           ; the cursor moves right
    PUSH BC
    EX DE,HL                        ; DE = the cursor
    LD L,A
    LD H,$00
    ADD HL,DE                       ; HL = the zero at the line's end
    LD B,H                          ; BC = the last byte to move
    LD C,L
    INC HL                          ; HL = its destination, a byte up
    CALL BLTUC                      ; open a gap at the cursor
    POP BC
    POP AF
    LD [HL],A                       ; put the typed character in the gap
    CALL OUTCH1
    INC HL
    JP DINGI_1

;; Handles backspace in EDIT's command mode, moving the cursor back and echoing a backspace.
;;
;; With a repeat count, only the first step backspaces: the rest continue as rubouts (RUBED).
;;
;; In:    HL = the cursor, B = its position, D = the count
DELED:
    LD A,B
    OR A
    RET Z                           ; already at the line's start
    DEC HL                          ; move the cursor back
    LD A,$08                        ; and back up on the screen
    CALL OUTCH1
    DEC B
    DEC D
    JP NZ,RUBED
    RET

;; Handles rubout in EDIT's command mode, moving the cursor back D characters and echoing each one.
;; In:    HL = the cursor, B = its position, D = the count
RUBED:
    LD A,B
    OR A
    RET Z                           ; already at the line's start
    DEC B
    DEC HL
    LD A,[HL]                       ; echo the character passed over
    CALL OUTCH1
    DEC D
    JP NZ,RUBED
    RET

;; Handles Return in EDIT, printing the rest of the line and ending the edit as E does.
CRED:
    CALL LISPRT                     ; print the rest of the line

;; Handles the EDIT E command, ending the edit and entering the changed line.
;;
;; A typed line (number $FFFF) returns to INLIN's caller with HL at BUFMIN; a program line is entered through the
;; line-entry code (EDENT), as if typed.
EED:
    CALL CRDO
    POP BC                          ; drop the return address to DISPED
    POP DE                          ; DE = the line number
    LD A,D
    AND E
    INC A                           ; zero when DE is $FFFF, a typed line

;; Returns a typed line from EDIT, or enters an edited program line in the program.
;;
;; Interpreter.asm jumps here with zero clear after AUTO, to enter the line it read.
;;
;; In:    DE = the line number, zero = set for a typed line, BUF = the line
;; Out:   HL = BUFMIN, for a typed line
EDITRT:
    LD HL,BUFMIN
    RET Z                           ; a typed line: back to INLIN's caller
    SCF                             ; carry: the line has a number
    PUSH AF
    INC HL                          ; HL = BUF
    JP EDENT                        ; enter it in the program

;; Handles the EDIT Q command, abandoning the changes: a program line is left as it was, a typed line ends at the
;; cursor.
QED:
    POP BC                          ; drop the return address to DISPED
    POP DE                          ; DE = the line number
    LD A,D
    AND E
    INC A                           ; zero when DE is $FFFF, a typed line
    JP Z,FININL                     ; end the typed line at the cursor and return it
    JP READY                        ; leave the program line unchanged

;; Executes the USING part of PRINT, printing the values that follow by the format string.
;;
;; The format is scanned for fields; text between them is printed as it is. Each field's description is built in
;; registers: D = the flags ($80 formatted, $40 commas, $20 asterisk fill, $10 dollar sign, $08 a + sign,
;; $04 a trailing sign, $01 exponential form), E = the digits before the point and C = those after it, B = the
;; format characters left. The stack holds the format's descriptor, whether values remain, and the text pointer.
;; FLGINP is USFLG here: whether a pass over the format printed a value.
;;
;; In:    HL = the text after USING
;; Errors: FC (5) for an empty format, a format without fields, or a field over 24 digits; SN (2) for a bad
;;          separator; TM (13) for a format or string field that is not a string
PRINUS:
    CALL FRMCHK                     ; evaluate the format string
    CALL CHKSTR                     ; it must be a string
    CALL SYNCHR                     ; check for the semicolon
    .byte ';'
    EX DE,HL                        ; DE = the text pointer
    LD HL,[FACLO]                   ; HL = the format's descriptor, from FACLO
    JP INIUS

;; Starts another pass over the format string for the values left, unless the last pass printed none.
REUSST:
    LD A,[FLGINP]                   ; was a value printed in the last pass?
    OR A
    JP Z,FCERR3                     ; a format with no fields cannot print values
    POP DE                          ; DE = the format's descriptor
    EX DE,HL                        ; HL = the descriptor, DE = the text pointer
INIUS:
    PUSH HL                         ; save the format's descriptor
    XOR A
    LD [FLGINP],A                   ; no value printed in this pass yet
    INC A                           ; zero clear: values remain
    PUSH AF
    PUSH DE                         ; save the text pointer
    LD B,[HL]                       ; B = the format's length
    OR B
FCERR3:
    JP Z,FCERR                      ; an empty format is an FC error
    INC HL                          ; HL = the format's text
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    JP PRCCHR

;; Scans a \...\ string field after its opening backslash, its width the backslashes and the spaces between.
;; In:    HL = the format after the backslash, B = the characters left
BGSTRF:
    LD E,B                          ; E = the characters left, in case no field forms
    PUSH HL                         ; save the position after the backslash
    LD C,$02                        ; a \ \ field is at least two wide
LPSTRF:
    LD A,[HL]
    INC HL
    CP $5C
    JP Z,ISSTRF                     ; a closing backslash completes the field
    CP ' '
    JP NZ,NOSTRF                    ; only spaces may come between the backslashes
    INC C                           ; widen the field
    DEC B
    JP NZ,LPSTRF

;; Prints the backslash of an unfinished string field as text and resumes the scan.
NOSTRF:
    POP HL                          ; back to just after the backslash
    LD B,E                          ; restore the count of characters left
    LD A,$5C                        ; print the backslash as text

;; Prints the format character in A as text, after any pending +, then scans for the next field.
NEWUCH:
    CALL PLSPRT
    CALL OUTDO

;; Scans the format string at HL for the next field, printing the text before it.
;; In:    HL = the format, B = the characters left
PRCCHR:
    XOR A                           ; start a new field: no flags or digits yet
    LD E,A
    LD D,A
PLSFIN:
    CALL PLSPRT
    LD D,A                          ; D = the field's flags
    LD A,[HL]                       ; A = the next format character
    INC HL
    CP '!'                          ; ! is a one-character string field
    JP Z,SMSTRF
    CP '#'                          ; # starts a numeric field
    JP Z,NUMNUM
    CP '&'                          ; & prints the whole string
    JP Z,VARSTR
    DEC B
    JP Z,REUSIN                     ; the format's last character
    CP '+'                          ; + asks for a sign before the number
    LD A,$08                        ; the leading sign flag
    JP Z,PLSFIN
    DEC HL
    LD A,[HL]                       ; reread the character
    INC HL
    CP '.'                          ; a period may start a numeric field
    JP Z,DOTNUM
    CP '_'                          ; an underline prints the next character as text
    JP Z,LITCHR
    CP $5C                          ; a backslash may start a string field
    JP Z,BGSTRF
    CP [HL]                         ; the rest need a doubled character
    JP NZ,NEWUCH
    CP '$'                          ; $$ is a floating dollar sign
    JP Z,DOLRNM
    CP '*'                          ; ** fills leading spaces with asterisks
    JP NZ,NEWUCH
    LD A,B
    INC HL
    CP $02                          ; room for a $ after the **?
    JP C,NOTSPC
    LD A,[HL]                       ; **$ adds a dollar sign too
    CP '$'
NOTSPC:
    LD A,$20                        ; the asterisk fill flag
    JP NZ,SPCNUM                    ; a plain ** field
    DEC B                           ; count the $
    INC E                           ; which takes a digit position
    .byte $FE                       ; CP n: skips the XOR A
DOLRNM:
    XOR A
    ADD A,$10                       ; add the dollar sign flag
    INC HL                          ; skip the doubled character
SPCNUM:
    INC E                           ; the doubled characters count as digits
    ADD A,D
    LD D,A                          ; merge into the field's flags
NUMNUM:
    INC E                           ; one more digit before the point
    LD C,$00                        ; no digits after the point yet
    DEC B
    JP Z,ENDNUS                     ; the format ended within the field
    LD A,[HL]
    INC HL
    CP '.'                          ; a period starts the fraction's digits
    JP Z,AFTDOT
    CP '#'                          ; another digit
    JP Z,NUMNUM
    CP ','                          ; a comma asks for thousands separators
    JP NZ,FINNUM
    LD A,D
    OR $40                          ; the comma flag
    LD D,A
    JP NUMNUM

;; Starts a numeric field at a period in the format string if a number sign follows it.
DOTNUM:
    LD A,[HL]
    CP '#'                          ; a digit must follow the period
    LD A,'.'
    JP NZ,NEWUCH                    ; otherwise print the period as text
    LD C,$01                        ; C counts the point
    INC HL
AFTDOT:
    INC C                           ; count a digit after the point
    DEC B
    JP Z,ENDNUS                     ; the format ended within the field
    LD A,[HL]
    INC HL
    CP '#'
    JP Z,AFTDOT                     ; more of the fraction's digits

;; Checks a numeric field for the four carets that ask for exponential form.
;;
;; Without them, it returns to NOTSCI, which puts the format pointer and the field back.
FINNUM:
    PUSH DE                         ; save the field's flags and digit count
    LD DE,NOTSCI                    ; return there to undo the lookahead if no carets
    PUSH DE
    LD D,H                          ; DE = the position to restore
    LD E,L
    CP '^'
    RET NZ
    CP [HL]                         ; four in a row are needed
    RET NZ
    INC HL
    CP [HL]
    RET NZ
    INC HL
    CP [HL]
    RET NZ
    INC HL
    LD A,B
    SUB $04
    RET C                           ; not enough format left for all four
    POP DE                          ; drop the NOTSCI return address
    POP DE                          ; restore the field's flags
    LD B,A                          ; B = the characters left after the carets
    INC D                           ; the exponential flag
    INC HL
    .byte $CA                       ; JP Z,nn, never taken after INC D: skips NOTSCI
NOTSCI:
    EX DE,HL                        ; HL = the position after the field
    POP DE                          ; restore the field's flags and digits

;; Finishes a numeric field: places its sign, a leading + or a trailing + or -, and prints the next value in it.
ENDNUS:
    LD A,D                          ; A = the field's flags
    DEC HL                          ; back to the character after the field
    INC E                           ; count a position for the sign
    AND $08
    JP NZ,ENDNUM                    ; a leading + already gives the sign a place
    DEC E
    LD A,B
    OR A
    JP Z,ENDNUM                     ; the end of the format: no trailing sign
    LD A,[HL]
    SUB '-'
    JP Z,SGNTRL                     ; a trailing - prints a minus after negatives
    CP $FE                          ; '+' less '-': a trailing +
    JP NZ,ENDNUM
    LD A,$08                        ; the trailing plus flag
SGNTRL:
    ADD A,$04                       ; the trailing sign flags: $04 minus, $0C plus
    ADD A,D
    LD D,A
    DEC B                           ; the sign character is used

;; Evaluates the next value and prints it in the numeric field just scanned; FC error over 24 digits.
ENDNUM:
    POP HL                          ; HL = the text pointer
    POP AF                          ; zero when no values remain
    JP Z,FLDFIN                     ; no value left: finish the statement
    PUSH BC                         ; save the digit counts and flags
    PUSH DE
    CALL FRMEVL                     ; evaluate the value to print
    POP DE
    POP BC
    PUSH BC
    PUSH HL
    LD B,E                          ; B = the digits before the point
    LD A,B
    ADD A,C                         ; the digits in all
    CP 25
    JP NC,FCERR                     ; more than 24 is an FC error
    LD A,D
    OR $80                          ; bit 7 asks PUFOUT for formatted output
    CALL PUFOUT                     ; format the number into a string
    CALL STROUT                     ; and print it

;; Reads the separator after a value, then recomputes the position in the format and continues the scan.
FNSTRF:
    POP HL                          ; HL = the text pointer
    DEC HL                          ; reread the character after the value
    CALL CHRGTR
    SCF                             ; carry asks for a new line at the end
    JP Z,CRDNUS                     ; the statement ends after this value
    LD [FLGINP],A                   ; a value was printed in this pass
    CP ';'                          ; a semicolon or comma may separate the values
    JP Z,SEMUSN
    CP ','
    JP NZ,SNERR                     ; anything else is a syntax error
SEMUSN:
    CALL CHRGTR                     ; skip the separator
CRDNUS:
    POP BC                          ; B = the format characters left
    EX DE,HL                        ; DE = the text pointer
    POP HL                          ; HL = the format's descriptor
    PUSH HL                         ; keep it for the next value
    PUSH AF                         ; save whether the statement ended
    PUSH DE                         ; save the text pointer
    LD A,[HL]
    SUB B                           ; A = the format characters used
    INC HL                          ; HL = the format's text
    LD D,$00
    LD E,A
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    ADD HL,DE                       ; HL = the position after this field
CHKUSI:
    LD A,B
    OR A
    JP NZ,PRCCHR                    ; format remains: keep scanning
    JP FINUSI                       ; the format is used up

;; Prints the format's last character as text and ends the pass, reusing the format if values remain.
REUSIN:
    CALL PLSPRT
    CALL OUTDO
FINUSI:
    POP HL                          ; HL = the text pointer
    POP AF                          ; zero clear when values remain
    JP NZ,REUSST                    ; values remain: start the format over

;; Ends PRINT USING: a new line unless a separator ended the statement, then frees the format string.
FLDFIN:
    CALL C,CRDO                     ; new line unless a separator ended the statement
    EX [SP],HL                      ; HL = the format's descriptor
    CALL FRETM2                     ; free the format string
    POP HL                          ; HL = the text pointer
    JP FINPRT                       ; finish the PRINT

;; Prints the format character after an underline as text.
LITCHR:
    CALL PLSPRT
    DEC B
    LD A,[HL]                       ; the character after the underline
    INC HL
    CALL OUTDO
    JP CHKUSI

;; Handles the & field, which prints a whole string.
VARSTR:
    LD C,$00                        ; width 0: the string's own length
    JP ISSTR1

;; Handles the ! field, which prints a string's first character.
SMSTRF:
    LD C,$01                        ; a ! field is one wide
    .byte $3E                       ; LD A,n: skips the POP AF

;; Prints the next value, a string, in a string field of width C, padding it with spaces.
;; Entry: ISSTR1 = the format pointer saved by BGSTRF already dropped
ISSTRF:
    POP AF                          ; drop the position saved by BGSTRF
ISSTR1:
    DEC B                           ; count the field's last character
    CALL PLSPRT
    POP HL                          ; HL = the text pointer
    POP AF                          ; zero when no values remain
    JP Z,FLDFIN                     ; nothing left to print
    PUSH BC                         ; save the counts
    CALL FRMEVL                     ; evaluate the value to print
    CALL CHKSTR                     ; it must be a string
    POP BC
    PUSH BC
    PUSH HL
    LD HL,[FACLO]                   ; HL = its descriptor, from FACLO
    LD B,C                          ; B = the field's width
    LD C,$00                        ; taken from the first character
    LD A,B
    PUSH AF                         ; save the width
    LD A,B
    OR A
    CALL NZ,LEFTUS                  ; take up to the width, unless & 
    CALL STRPRT                     ; print it
    LD HL,[FACLO]
    POP AF
    OR A
    JP Z,FNSTRF                     ; & pads nothing
    SUB [HL]                        ; B = the padding after the string
    LD B,A
    LD A,' '                        ; pad with spaces
    INC B                           ; offset the DEC B at UPRTSP

;; Pads a string field with B-1 spaces, then reads the separator after the value.
UPRTSP:
    DEC B
    JP Z,FNSTRF                     ; padding done: on to the next value
    CALL OUTDO
    JP UPRTSP

;; Prints a plus sign when D is not zero, for a + before a PRINT USING field.
;; In:    D = the field's flags, not zero when a + is pending
;; Keeps: AF
PLSPRT:
    PUSH AF
    LD A,D                          ; D not zero: a + is pending
    OR A
    LD A,'+'
    CALL NZ,OUTDO
    POP AF
    RET

;; Prints the character in A on the current device: an open file, the printer, or the console.
;;
;; With PTRFIL set, the character goes to the file through FILOUT. With PRTFLG set, it
;; goes to the printer, here: backspace moves LPTPOS back, tab prints spaces to the next multiple of 8,
;; Return sets LPTPOS to 0, other control characters leave it alone, and a printable character at the width in
;; LPTSIZ ($FF for none) ends the line first. Otherwise it goes to the console through OUTCON.
;;
;; In:    A = the character
OUTDO:
    PUSH AF
    PUSH HL
    CALL ISFLIO                     ; is a file open for output?
    JP NZ,FILOUT                    ; yes: write the character to it
    POP HL
    LD A,[PRTFLG]                   ; LPRINT or LLIST
    OR A
    JP Z,OUTCON                     ; no: the console
    POP AF
    PUSH AF
    CP $08
    JP NZ,OUTDO_2
    LD A,[LPTPOS]                   ; backspace: one column back, not past 0
    SUB $01
    JP C,OUTDO_1
    LD [LPTPOS],A
OUTDO_1:
    POP AF
    JP LPTOUT
OUTDO_2:
    CP $09
    JP NZ,OUTDO_4
OUTDO_3:
    LD A,' '                        ; tab: spaces to the next multiple of 8
    CALL OUTDO
    LD A,[LPTPOS]
    AND $07
    JP NZ,OUTDO_3
    POP AF
    RET
OUTDO_4:
    POP AF
    PUSH AF
    SUB $0D
    JP Z,OUTDO_6                    ; Return: back to column 0
    JP C,OUTDO_7                    ; other control characters below it keep the column
    LD A,[LPTSIZ]                   ; the printer's width
    INC A
    LD A,[LPTPOS]
    JP Z,OUTDO_5                    ; width 255: no limit
    PUSH HL
    LD HL,LPTSIZ
    CP [HL]
    POP HL
    CALL Z,LPCRLF                   ; at the width: end the line first, A = 0
OUTDO_5:
    CP $FF
    JP Z,OUTDO_7                    ; the column stops at 255
    INC A
OUTDO_6:
    LD [LPTPOS],A
OUTDO_7:
    POP AF

;; Sends the character in A to the printer through the BIOS's LIST entry.
;; In:    A = the character
;; Keeps: AF, BC, DE, HL
LPTOUT:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    LD C,A
LISTVC = * + 1                      ;; the BIOS's LIST address, patched in by Init.asm
    CALL $0000                      ; the BIOS's LIST: print C
    POP HL
    POP DE
    POP BC
    POP AF
    RET

;; Ends LPRINT or LLIST output: sends output back to the console and ends a pending printer line.
;; Out:   A = 0, PRTFLG = 0
;; Keeps: BC, DE, HL
FINLPT:
    XOR A
    LD [PRTFLG],A                   ; output back to the console
    LD A,[LPTPOS]
    OR A
    RET Z                           ; the printer is at the start of a line

;; Sends Return and line feed to the printer and sets its column, LPTPOS, to 0.
;; Out:   A = 0
;; Keeps: BC, DE, HL
LPCRLF:
    LD A,$0D
    CALL LPTOUT
    LD A,$0A
    CALL LPTOUT
    XOR A
    LD [LPTPOS],A
    RET

;; Prints the character on the stack on the console, tracking TTYPOS, unless Control-O suppresses output.
;;
;; Backspace moves TTYPOS back and is not printed at column 0; tab prints spaces to the next multiple of 8; other
;; control characters leave TTYPOS alone; a printable character at the width in LINLEN ($FF for none) starts a new
;; line first. List.asm pushes AF and jumps here to print on the console whatever the device.
;;
;; In:    SP = at the AF pushed with the character in A, over the return address
OUTCON:
    LD A,[CNTOFL]                   ; Control-O suppresses output
    OR A
    JP NZ,PPSWRT                    ; suppressed: drop the character
    POP AF
    PUSH BC
    PUSH AF
    CP $08
    JP NZ,OUTCON_1
    LD A,[TTYPOS]                   ; backspace: one column back
    OR A
    JP Z,OUTCON_3                   ; not past column 0, and not printed there
    DEC A
    LD [TTYPOS],A
    LD A,$08
    JP OUTCON_6
OUTCON_1:
    CP $09
    JP NZ,OUTCON_4
OUTCON_2:
    LD A,' '                        ; tab: spaces to the next multiple of 8
    CALL OUTDO
    LD A,[TTYPOS]
    AND $07
    JP NZ,OUTCON_2
OUTCON_3:
    POP AF
    POP BC
    RET
OUTCON_4:
    CP ' '
    JP C,OUTCON_6                   ; control characters keep the column
    LD A,[LINLEN]                   ; the console's width
    LD B,A
    LD A,[TTYPOS]
    INC B
    JP Z,OUTCON_5                   ; width 255: no limit
    DEC B
    CP B
    CALL Z,CRDO                     ; at the width: start a new line, A = 0
OUTCON_5:
    CP $FF
    JP Z,OUTCON_6                   ; the column stops at 255
    INC A
    LD [TTYPOS],A
OUTCON_6:
    POP AF
    POP BC
    PUSH AF                         ; a PUSH and POP that do nothing
    POP AF
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    LD C,A
CONOVC = * + 1                      ;; the BIOS's CONOUT address, patched in by Init.asm
    CALL $0000                      ; the BIOS's CONOUT: print C
    POP HL
    POP DE
    POP BC
    POP AF
    RET

;; Reads a character for INLIN: from the file being loaded when PTRFIL is set, otherwise from the console.
;;
;; At the end of the file being loaded, it closes it (PRGFIN), then goes back to CHAIN (CHNRET) if
;; CHNFLG is set, runs the program through NEWSTT if the load was a RUN (RUNFLG), or prints Ok and returns
;; zero.
;;
;; Out:   A = the character, zero at the end of a loaded file
INCHR:
    CALL ISFLIO                     ; reading a file?
    JP Z,INCHRI                     ; no: the console
    CALL INDSKC                     ; read a character from it, carry = the end
    RET NC
    PUSH BC
    PUSH DE
    PUSH HL
    CALL PRGFIN                     ; close the file
    POP HL
    POP DE
    POP BC
    LD A,[CHNFLG]                   ; a CHAIN in progress?
    OR A
    JP NZ,CHNRET                    ; yes: back to the chain code
    LD A,[RUNFLG]                   ; RUN "file", or LOAD "file",R?
    OR A
    JP Z,INCHR_1
    LD HL,NEWSTT                    ; yes: clear the variables and run it
    PUSH HL
    JP RUNC
INCHR_1:
    PUSH HL
    PUSH BC
    PUSH DE
    LD HL,REDDY                     ; a LOAD: print Ok
    CALL STROUT                     ; (STROUT)
    POP DE
    POP BC
    XOR A
    POP HL
    RET

;; Waits for a key at the console through the BIOS's CONIN, toggling output on Control-O.
;;
;; Control-O complements CNTOFL, printing ^O when it turns output off and again when it turns it back on,
;; and returns zero in place of the key.
;;
;; Out:   A = the key, without its top bit; zero after Control-O
INCHRI:
    PUSH BC
    PUSH DE
    PUSH HL
CONIVC = * + 1                      ;; the BIOS's CONIN address, patched in by Init.asm
    CALL $0000                      ; the BIOS's CONIN: A = the key
    POP HL
    POP DE
    POP BC
    AND $7F
    CP $0F
    RET NZ                          ; anything but Control-O
    LD A,[CNTOFL]
    OR A
    CALL Z,CTROPT                   ; turning output off: print ^O first, A = 0
    CPL
    LD [CNTOFL],A
    OR A
    JP Z,CTROPT                     ; turning it back on: print ^O, A = 0
    XOR A
    RET

;; Starts a new line on the console unless it is already at the start of one (TTYPOS, zero).
;; Out:   A = 0
CRDONZ:
    LD A,[TTYPOS]
    OR A
    RET Z                           ; already at the start of a line
    JP CRDO

;; Ends the line typed into the buffer at HL with a zero and prints a new line, returning HL at BUFMIN.
;; In:    HL = the end of the line
;; Out:   HL = BUFMIN, A = 0
FININL:
    LD [HL],$00
    LD HL,BUFMIN

;; Prints Return and line feed on the current device, and resets its column.
;; Out:   A = 0
CRDO:
    LD A,$0D
    CALL OUTDO
    LD A,$0A
    CALL OUTDO

;; Resets the current device's column after a new line, sending the console NULCNT less one nulls.
;; Out:   A = 0, zero = set
CRFIN:
    CALL ISFLIO                     ; a file?
    JP Z,CRFIN_1
    XOR A                           ; a file keeps no column here
    RET
CRFIN_1:
    LD A,[PRTFLG]
    OR A
    JP Z,CRFIN_2
    XOR A                           ; the printer: column 0
    LD [LPTPOS],A
    RET
CRFIN_2:
    XOR A                           ; the console: column 0
    LD [TTYPOS],A
    LD A,[NULCNT]                   ; then the nulls a slow terminal needs
CRFIN_3:
    DEC A
    RET Z
    PUSH AF
    XOR A
    CALL OUTDO
    POP AF
    JP CRFIN_3

;; Checks the console between statements for Control-C, through the BIOS's CONST; Control-S pauses.
;; Out:   A = 0 when no key was waiting
;; See:   <CNTCCN>
ISCNTC:
    PUSH BC
    PUSH DE
    PUSH HL
CSTSVC = * + 1                      ;; the BIOS's CONST address, patched in by Init.asm
    CALL $0000                      ; the BIOS's CONST: A not zero when a key waits
    POP HL
    POP DE
    POP BC
    OR A
    RET Z                           ; no key

;; Reads the waiting key: Control-S pauses until another, Control-C stops the program, and any other is kept.
;;
;; The key, or the one that ends a pause, is kept in CHARC for INKEY$ and INLIN. Control-C prints ^C and
;; stops the program through ST_STOP, which returns at once for any other key. NEWSTT calls here when its own
;; CONST call finds a key.
CNTCCN:
    CALL INCHRI
    CP $13                          ; Control-S: wait for another key
    CALL Z,INCHRI
    LD [CHARC],A                    ; keep the key in CHARC
    CP $03                          ; Control-C?
    CALL Z,CTRLPT                   ; print ^C, with zero set
    JP ST_STOP                      ; stops for Control-C, returns for any other key

;; Returns INKEY$: the key kept in CHARC or waiting at the console, or the null string.
;; In:    HL = the text at INKEY$
;; Out:   HL = the text after it, FACLO = the string's descriptor, VALTYP = 3
INKEY:
    CALL CHRGTR                     ; step past the token
    PUSH HL
    CALL CHARCG                     ; a key kept from ISCNTC?
    JP NZ,INKEY_1
CSTKVC = * + 1                      ;; the BIOS's CONST address, patched in by Init.asm
    CALL $0000                      ; the BIOS's CONST: A not zero when a key waits
    OR A
    JP Z,INKEY_2                    ; no key: the null string
    CALL INCHRI
INKEY_1:
    PUSH AF
    CALL STRIN1                     ; make a one-character string
    POP AF
    LD E,A
    CALL SETSTR                     ; store the key in it and return it, not here
INKEY_2:
    LD HL,REDDY-1                   ; the zero before Ok, a null string's descriptor
    LD [FACLO],HL                   ; in FACLO
    LD A,$03                        ; a string
    LD [VALTYP],A
    POP HL
    RET

;; Takes the key ISCNTC kept in CHARC, clearing it.
;; Out:   A = the key, zero = set when there was none
;; Keeps: BC, DE, HL
CHARCG:
    LD A,[CHARC]
    OR A
    RET Z
    PUSH AF
    XOR A
    LD [CHARC],A
    POP AF
    RET

;; Prints the character in A through OUTDO; a line feed becomes a new line, ending with the column reset.
;; In:    A = the character
;; Out:   A = the character
OUTCH1:
    CALL OUTDO
    CP $0A
    RET NZ
    LD A,$0D                        ; follow a line feed with Return
    CALL OUTDO
    CALL CRFIN                      ; and reset the column
    LD A,$0A
    RET

;; Checks that the destination leaves room below the strings (REASON), then moves a block up in memory (BLTUC).
;; In:    HL = the destination of the block's top byte, DE = the block's first byte, BC = its top byte
;; Out:   HL = DE, BC = the destination of the first byte, less one
;; Errors: OM (7) when there is no room, even after a garbage collection
BLTU:
    CALL REASON

;; Copies bytes downward from BC to HL until the source reaches DE, which moves a block up in memory.
;; In:    BC = the block's top byte, HL = its destination, DE = the block's first byte
;; Out:   HL = DE, BC = the destination of the first byte, less one
BLTUC:
    PUSH BC
    EX [SP],HL                      ; swap HL and BC
    POP BC
BLTLOP:
    CALL DCOMPR                     ; zero once the source reaches DE (COMPAR)
    LD A,[HL]
    LD [BC],A
    RET Z
    DEC BC
    DEC HL
    JP BLTLOP

;; Checks that 2*C bytes of stack can be used and still leave 29 levels free above MEMSIZ; OM error if not.
;;
;; MBASIC's stack lives between MEMSIZ and TOPMEM, so the room is measured from MEMSIZ.
;;
;; In:    C = the number of two-byte entries needed
;; Out:   B = 0
;; Errors: OM (7), through OMERR
;; Keeps: DE, HL
GETSTK:
    PUSH HL
    LD HL,[MEMSIZ]                  ; the stack's lowest address
    LD B,$00
    ADD HL,BC
    ADD HL,BC                       ; HL = that plus two bytes per entry
    LD A,$C6                        ; HL = $FFC6 less HL: 256 - 2*29 levels kept free
    SUB L
    LD L,A
    LD A,$FF
    SBC A,H
    LD H,A
    JP C,OMERR                      ; an address that high can never fit
    ADD HL,SP                       ; carry when the stack is clear of it
    POP HL
    RET C

;; Reports Out of memory after dropping every stack context, so that SAVSTK restarts at TOPMEM less 2.
;; Errors: OM (7)
;; Entry: OMERRR = reports the error without touching SAVSTK
OMERR:
    LD HL,[TOPMEM]
    DEC HL                          ; keep room for the FNDFOR stopper
    DEC HL
    LD [SAVSTK],HL                  ; where the stack restarts after the error
OMERRR:
    LD DE,$0007                     ; Out of memory
    JP ERROR

;; Checks that HL is below the strings (FRETOP), collecting garbage once if not; OM error if it still is not.
;; In:    HL = the highest address that will be used
;; Errors: OM (7), through OMERRR
;; Keeps: BC, DE, HL
REASON:
    CALL FRECHK
    RET NC                          ; room enough
    PUSH BC
    PUSH DE
    PUSH HL
    CALL GARBA2                     ; collect the garbage in string space
    POP HL
    POP DE
    POP BC
    CALL FRECHK
    RET NC                          ; room now
    JP OMERRR

;; Compares HL with FRETOP.
;; In:    HL = the address
;; Out:   carry = set when HL is above FRETOP
;; Keeps: BC, DE, HL
FRECHK:
    PUSH DE
    EX DE,HL                        ; DE = the address
    LD HL,[FRETOP]
    CALL DCOMPR                     ; FRETOP less the address (COMPAR)
    EX DE,HL
    POP DE
    RET
