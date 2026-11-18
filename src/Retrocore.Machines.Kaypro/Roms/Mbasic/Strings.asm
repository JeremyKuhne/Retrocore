;; MBASIC 5.21: STRINGS (BISTRS)
;;
;; BASIC's string package, GW-BASIC's BISTRS.ASM in the same order.
;; Level2.asm has the same code for the TRS-80, under the same names. In order:
;;
;; - STRCMP and CSLOOP compare two strings for the relational operators.
;; - OCT$, HEX$ and STR$ (FN_OCT, FN_HEX, FN_STR) convert a number to text with FOUT and make it a string.
;; - The string temporaries: STRLIT scans a literal into a descriptor in DSCTMP, and PUTNEW copies DSCTMP into
;;   the next of the ten temporary descriptors at TEMPST, leaving FACLO pointing at it and VALTYP 3. FRETMP,
;;   and FRESTR, FREFAC and FRETM2 in front of it, give the last temporary back, and its string space too when
;;   that is the lowest string.
;; - STROUT prints a message: text ending in a zero or a quotation mark, made a temporary and printed by STRPRT.
;;   Every other module calls it for its messages.
;; - String space: GETSPA takes space below FRETOP, down towards STREND. When there is none it calls GARBAG,
;;   which moves every string still referred to by the temporaries, the simple variables (and the DEF FN
;;   parameter blocks chained from PRMPRV), and the string arrays up against MEMSIZ, the highest first, one
;;   string per pass.
;; - CAT joins two strings for +. The functions follow: LEN, ASC, CHR$, STRING$, SPACE$, LEFT$, RIGHT$, MID$,
;;   VAL and INSTR; then the MID$ statement (LHSMID) and FRE.
;;
;; Runs at $465C-$4B0C. A string is a descriptor of three bytes, its length and its address; string
;; functions find their arguments' descriptors through FACLO and on the stack, and return through PUTNEW.

;; Compares the string on the stack with the string in the FAC, for the relational operators.
;;
;; It frees both strings first. The left string's descriptor is on the stack, under the return address.
;; In:    FACLO = the right string's descriptor
;; Out:   A = 0 if equal, 1 if the left string is less, $FF if greater
STRCMP:
    CALL FRESTR                     ; HL = the right string's descriptor
    LD A,[HL]                       ; A = its length
    INC HL
    LD C,[HL]                       ; BC = its text
    INC HL
    LD B,[HL]
    POP DE                          ; DE = the left string's descriptor
    PUSH BC
    PUSH AF
    CALL FRETMP                     ; HL = the left string's descriptor
    POP AF
    LD D,A                          ; D = the right string's length
    LD E,[HL]                       ; E = the left string's length
    INC HL
    LD C,[HL]                       ; BC = the left string's text
    INC HL
    LD B,[HL]
    POP HL                          ; HL = the right string's text

;; Compares two strings a character at a time, the shorter being less when one starts the other.
;; In:    BC, E = the left string's text and length, HL, D = the right string's
;; Out:   A = 0 if equal, 1 if the left string is less, $FF if greater
CSLOOP:
    LD A,E
    OR D
    RET Z                           ; both ended: equal
    LD A,D
    SUB $01
    RET C                           ; the right one ended first: A = $FF
    XOR A
    CP E
    INC A
    RET NC                          ; the left one ended first: A = 1
    DEC D
    DEC E
    LD A,[BC]
    INC BC
    CP [HL]
    INC HL
    JP Z,CSLOOP
    CCF                             ; carry for the larger character
    JP SIGNS                        ; A = 1 or $FF by the carry

;; Runs OCT$, giving the octal digits of the number in the FAC as a string.
;;
;; In:    FACLO = the FAC, the number
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string)
;; See:   <FN_STR>
FN_OCT:
    CALL FOUTO                      ; the digits to FBUFFR
    JP STR1

;; Runs HEX$, giving the hexadecimal digits of the number in the FAC as a string.
;;
;; In:    FACLO = the FAC, the number
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string)
;; See:   <FN_STR>
FN_HEX:
    CALL FOUTH                      ; the digits to FBUFFR
    JP STR1

;; Runs STR$, giving the text PRINT would show for the number in the FAC as a string.
;;
;; The text FOUT leaves in its buffer is made a temporary by STRLIT, freed again, and copied into string space
;; by STRCPY, which returns into FINBCK to make the copy the result.
;;
;; In:    FACLO = the FAC, the number
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string)
;; Entry: STR1 = FN_OCT and FN_HEX, with the text at HL
FN_STR:
    CALL FOUT                       ; HL = the text, ending in a zero
STR1:
    CALL STRLIT
    CALL FREFAC                     ; HL = the literal's descriptor, freed
    LD BC,FINBCK                    ; STRCPY returns into FINBCK, which drops a word and calls PUTNEW
    PUSH BC

;; Copies the string whose descriptor HL points at into new string space.
;;
;; In:    HL = the descriptor
;; Out:   DE = DSCTMP, holding the copy's descriptor
;; Uses:  A, BC, HL
STRCPY:
    LD A,[HL]                       ; A = the length
    INC HL
    PUSH HL
    CALL GETSPA                     ; DE = space for the copy
    POP HL
    LD C,[HL]                       ; BC = the original's characters
    INC HL
    LD B,[HL]
    CALL STRAD2                     ; DSCTMP = the copy's descriptor
    PUSH HL
    LD L,A                          ; L = the count to move
    CALL MOVSTR
    POP DE                          ; DE = DSCTMP
    RET

;; Makes room for a one-character string, for CHR$ and INKEY$.
;;
;; Out:   A = 1, DE = the string's space, HL = DSCTMP, which describes it
;; See:   <STRINI>
STRIN1:
    LD A,$01

;; Takes A bytes of string space and describes them in DSCTMP.
;;
;; In:    A = the length
;; Out:   DE = the space, HL = DSCTMP, which describes it
;; Errors: Out of string space (14)
STRINI:
    CALL GETSPA

;; Stores the length in A and the address in DE as the descriptor in DSCTMP.
;;
;; In:    A = the length, DE = the string's address
;; Out:   HL = DSCTMP
;; Keeps: A, BC, DE
STRAD2:
    LD HL,DSCTMP
    PUSH HL
    LD [HL],A                       ; the length
    INC HL
    LD [HL],E                       ; and the address
    INC HL
    LD [HL],D
    POP HL
    RET

;; Makes the text at HL, up to a zero or a quotation mark, a temporary string.
;;
;; The text is described in DSCTMP and PUTNEW copies it to a temporary. A closing quotation mark is skipped;
;; an unquoted string that ends at a comma, as INPUT and READ scan them, drops its trailing spaces.
;;
;; In:    HL = the text
;; Out:   HL = the text after the string, A = the character there (flags not set from it), FACLO = the
;;   temporary's descriptor, VALTYP = 3 (a string)
;; Errors: String formula too complex (16)
;; Entry: STRLTI = the text at HL+1, STRLT3 = the text at HL+1, ending at a zero or the character in B,
;;   STRLT2 = the text at HL+1, ending at a zero or the characters in B and D
STRLIT:
    DEC HL
STRLTI:
    LD B,$22                        ; ends at a quotation mark
STRLT3:
    LD D,B                          ; and only that
STRLT2:
    PUSH HL                         ; the start, less one
    LD C,$FF                        ; C counts the characters
STRGET:
    INC HL
    LD A,[HL]
    INC C
    OR A
    JP Z,STRFIN                     ; the end of the line ends the string
    CP D
    JP Z,STRFIN
    CP B
    JP NZ,STRGET
STRFIN:
    CP $22                          ; skip a closing quotation mark
    CALL Z,CHRGTR
    PUSH HL                         ; the text after the string
    LD A,B
    CP $2C                          ; an unquoted string, ending at a comma?
    JP NZ,NTTRLS
    INC C
LPTRLS:
    DEC C                           ; drop its trailing spaces
    JP Z,NTTRLS                     ; but not past its start
    DEC HL
    LD A,[HL]
    CP $20
    JP Z,LPTRLS
NTTRLS:
    POP HL
    EX [SP],HL                      ; the text pointer for PUTNEW, HL = the start, less one
    INC HL
    EX DE,HL                        ; DE = the string's address
    LD A,C                          ; A = its length
    CALL STRAD2

;; Copies the descriptor in DSCTMP to the next free temporary and makes it the result, a string.
;;
;; It is jumped to, not called, with the text pointer pushed on the stack, which it pops into HL; it returns
;; to the address under that.
;;
;; In:    SP = at the text pointer, then the return address
;; Out:   HL = the text pointer, A = the character there, FACLO = the temporary's descriptor, VALTYP = 3 (a string)
;; Errors: String formula too complex (16), when the ten temporaries are all in use
;; Entry: PUTTMP = copies the descriptor at DE instead, and returns DE in HL
PUTNEW:
    LD DE,DSCTMP
    .byte $3E                       ; LD A,n: skips the PUSH DE
PUTTMP:
    PUSH DE
    LD HL,[TEMPPT]                  ; HL = the next free temporary
    LD [FACLO],HL                   ; FACLO points at it
    LD A,$03                        ; a string
    LD [VALTYP],A
    CALL VMOVE                      ; copy the descriptor there, HL = past it
    LD DE,DSCTMP+3                  ; DSCTMP follows the temporaries: past it, TEMPPT had reached DSCTMP
    CALL DCOMPR
    LD [TEMPPT],HL
    POP HL
    LD A,[HL]
    RET NZ
    LD DE,ERR_ST                    ; String formula too complex
    JP ERROR

;; Prints the text at HL+1, up to a zero or a quotation mark.
;;
;; In:    HL = the text, less one
;; See:   <STROUT>
STROUI:
    INC HL

;; Prints the text at HL, up to a zero or a quotation mark: the messages of every module.
;;
;; The text is made a temporary string by STRLIT and printed by STRPRT.
;;
;; In:    HL = the text
;; Errors: String formula too complex (16)
STROUT:
    CALL STRLIT

;; Prints the string in the FAC, freeing its temporary.
;;
;; In:    FACLO = the descriptor
;; Entry: STRPR2 = prints D-1 characters from BC
STRPRT:
    CALL FREFAC
    CALL GETBCD                     ; D = the length, BC = the characters
    INC D                           ; for the DEC that tests for none
STRPR2:
    DEC D
    RET Z
    LD A,[BC]
    CALL OUTDO
    CP $0D                          ; after a carriage return, the column is 0
    CALL Z,CRFIN
    INC BC
    JP STRPR2

;; Takes A bytes of string space, below FRETOP, collecting garbage if they don't fit.
;;
;; Remarks: the zero flag on the stack says whether it has collected yet. A failed first try calls GARBAG and
;; comes back to TRYGI2 with zero set; a second failure is the error.
;;
;; In:    A = the length, not zero
;; Out:   DE = the space, A = the length
;; Errors: Out of string space (14)
;; Uses:  BC, HL
;; Entry: TRYGI2 = the retry after collecting, with the length and zero on the stack
GETSPA:
    OR A                            ; zero clear: not collected yet
    .byte $0E                       ; LD C,n: skips the POP AF
TRYGI2:
    POP AF
    PUSH AF                         ; the length and the collected flag
    LD HL,[STREND]                  ; DE = the end of the arrays, the floor
    EX DE,HL
    LD HL,[FRETOP]
    CPL                             ; BC = -length-1
    LD C,A
    LD B,$FF
    ADD HL,BC
    INC HL                          ; HL = FRETOP - length
    CALL DCOMPR
    JP C,GARBAG                     ; below STREND: no room
    LD [FRETOP],HL
    INC HL
    EX DE,HL                        ; DE = the space, just above the new FRETOP

;; Pops AF and returns.
;;
;; Out:   AF = the word on the stack
PPSWRT:
    POP AF
    RET

;; Collects garbage for GETSPA, or gives Out of string space if it already has.
;;
;; In:    SP = at the length and GETSPA's flag
;; Errors: Out of string space (14)
GARBAG:
    POP AF
    LD DE,ERR_SO                    ; Out of string space
    JP Z,ERROR                      ; collected already
    CP A                            ; zero: collected
    PUSH AF
    LD BC,TRYGI2                    ; then try again
    PUSH BC

;; Compacts string space: moves every string in use up to MEMSIZ, leaving the free space below FRETOP.
;;
;; Remarks: each pass looks through the string temporaries, the simple variables, the DEF FN parameter blocks
;; chained from PRMPRV and the string arrays for the string highest below FRETOP, keeping the best so
;; far and its descriptor on the stack (DVARS). GRBPAS moves that string up to FRETOP, points its descriptor at
;; it, and starts another pass with FRETOP below it. Strings below STREND, in the program's text, are left
;; alone. The pass that finds none ends the collection.
;;
;; Out:   FRETOP = the bottom of the strings in use
;; Uses:  A, BC, DE, HL, TEMP8, ARYTA2, TEMP9
GARBA2:
    LD HL,[MEMSIZ]                  ; nothing in use above the top yet
FNDVAR:
    LD [FRETOP],HL
    LD HL,$0000                     ; no string found yet this pass
    PUSH HL
    LD HL,[STREND]                  ; the highest so far: STREND, so strings in the program are ignored
    PUSH HL
    LD HL,TEMPST
TVAR:
    EX DE,HL
    LD HL,[TEMPPT]                  ; DE = the end of the temporaries in use
    EX DE,HL
    CALL DCOMPR
    LD BC,TVAR                      ; DVARS returns to TVAR for the next
    JP NZ,DVAR2
    LD HL,PRMPRV                    ; the parameter blocks' chain starts there
    LD [TEMP9],HL
    LD HL,[ARYTAB]                  ; the simple variables end at the arrays
    LD [ARYTA2],HL
    LD HL,[VARTAB]
SVAR:
    EX DE,HL
    LD HL,[ARYTA2]                  ; DE = where this block of simple variables ends
    EX DE,HL
    CALL DCOMPR
    JP Z,ARYVAR
    LD A,[HL]                       ; A = the type, the value's length
    INC HL                          ; skip the type and the name's two characters
    INC HL
    INC HL
    PUSH AF
    CALL IADAHL                     ; skip the name's further characters
    POP AF
    CP $03
    JP NZ,SKPVAR                    ; not a string: skip the value
    CALL DVARS
    XOR A                           ; DVARS has passed the descriptor already
SKPVAR:
    LD E,A
    LD D,$00
    ADD HL,DE
    JP SVAR
ARYVAR:
    LD HL,[TEMP9]                   ; the next parameter block in the chain
    LD E,[HL]
    INC HL
    LD D,[HL]
    LD A,D
    OR E
    LD HL,[ARYTAB]
    JP Z,ARYVA4                     ; the end of the chain: the arrays
    EX DE,HL
    LD [TEMP9],HL
    INC HL                          ; skip the link
    INC HL
    LD E,[HL]                       ; DE = the block's length
    INC HL
    LD D,[HL]
    INC HL
    EX DE,HL
    ADD HL,DE                       ; its end
    LD [ARYTA2],HL
    EX DE,HL                        ; and its variables, like the simple ones
    JP SVAR
ARYVA2:
    POP BC                          ; drop the pointer to the dimensions
ARYVA4:
    EX DE,HL
    LD HL,[STREND]                  ; the end of the arrays?
    EX DE,HL
    CALL DCOMPR
    JP Z,GRBPAS
    LD A,[HL]                       ; A = the type
    INC HL
    PUSH AF
    INC HL                          ; skip the name
    INC HL
    CALL IADAHL                     ; and its further characters
    LD C,[HL]                       ; BC = the array's length
    INC HL
    LD B,[HL]
    INC HL
    POP AF
    PUSH HL                         ; the dimensions
    ADD HL,BC                       ; HL = the next array
    CP $03
    JP NZ,ARYVA2                    ; not strings: skip it
    LD [TEMP8],HL                   ; the array's end
    POP HL
    LD C,[HL]                       ; skip the count of dimensions and two bytes each
    LD B,$00
    ADD HL,BC
    ADD HL,BC
    INC HL
ARYSTR:
    EX DE,HL
    LD HL,[TEMP8]
    EX DE,HL
    CALL DCOMPR                     ; the array's last element done?
    JP Z,ARYVA4
    LD BC,ARYSTR                    ; DVARS returns to ARYSTR for the next
DVAR2:
    PUSH BC

;; Checks the string descriptor at HL during garbage collection: keeps it if its string is the highest yet.
;;
;; Remarks: called with two words under its return address, the highest string address so far and the
;; descriptor's end that goes with it. A string at or above FRETOP has been moved already.
;;
;; In:    HL = the descriptor
;; Out:   HL = past the descriptor
DVARS:
    XOR A
    OR [HL]                         ; A = the length
    INC HL
    LD E,[HL]                       ; DE = the string's address
    INC HL
    LD D,[HL]
    INC HL
    RET Z                           ; an empty string has no space
    LD B,H
    LD C,L
    LD HL,[FRETOP]
    CALL DCOMPR
    LD H,B
    LD L,C
    RET C                           ; moved already
    POP HL                          ; the return address
    EX [SP],HL                      ; HL = the highest so far
    CALL DCOMPR
    EX [SP],HL
    PUSH HL
    LD H,B
    LD L,C
    RET NC                          ; not higher
    POP BC                          ; the return address
    POP AF                          ; drop the old best
    POP AF
    PUSH HL                         ; the descriptor's end
    PUSH DE                         ; and its string, the new best
    PUSH BC
    RET

;; Ends a pass of garbage collection: moves the highest string found up to FRETOP, then starts the next pass.
;;
;; In:    SP = at the highest string's address, then the end of its descriptor (zero if none was found)
GRBPAS:
    POP DE
    POP HL
    LD A,H
    OR L
    RET Z                           ; none: the collection is done
    DEC HL
    LD B,[HL]                       ; BC = the string's address
    DEC HL
    LD C,[HL]
    PUSH HL                         ; where the address goes back
    DEC HL
    LD L,[HL]                       ; HL = the length
    LD H,$00
    ADD HL,BC
    LD D,B                          ; DE = the string's start
    LD E,C
    DEC HL
    LD B,H                          ; BC = its last character
    LD C,L
    LD HL,[FRETOP]
    CALL BLTUC                      ; move it up to end at FRETOP, BC = its new start
    POP HL
    LD [HL],C                       ; the descriptor's new address
    INC HL
    LD [HL],B
    LD H,B
    LD L,C
    DEC HL                          ; FRETOP goes below it
    JP FNDVAR

;; Joins the string in the FAC and the string expression after the + at HL, for the evaluator.
;;
;; The result is built in DSCTMP and made a temporary by PUTNEW, which returns into the evaluator at TSTOP.
;;
;; In:    FACLO = the first string's descriptor, HL = the text after the +, BC = the operator's precedence
;; Out:   FACLO = the joined string's descriptor
;; Errors: String too long (15), Type mismatch, String formula too complex (16), Out of string space (14)
CAT:
    PUSH BC                         ; the precedence, back on the stack
    PUSH HL
    LD HL,[FACLO]
    EX [SP],HL                      ; stack the first string's descriptor
    CALL EVAL                       ; the second operand
    EX [SP],HL                      ; stack the text pointer, HL = the first's descriptor
    CALL CHKSTR                     ; the second must be a string
    LD A,[HL]
    PUSH HL
    LD HL,[FACLO]                   ; the second's descriptor
    PUSH HL
    ADD A,[HL]                      ; A = the two lengths
    LD DE,ERR_LS                    ; String too long
    JP C,ERROR
    CALL STRINI
    POP DE
    CALL FRETMP                     ; free the second
    EX [SP],HL
    CALL FRETM2                     ; and the first
    PUSH HL
    LD HL,[DSCPTR]                  ; DE = the new space
    EX DE,HL
    CALL MOVINS                     ; the first string
    CALL MOVINS                     ; and the second after it
    LD HL,TSTOP                     ; PUTNEW returns into the evaluator
    EX [SP],HL
    PUSH HL
    JP PUTNEW

;; Copies the string whose descriptor is on the stack, under the return address, to DE.
;;
;; In:    DE = where it goes, SP = at the descriptor
;; Out:   DE = past the copy
;; Uses:  A, BC, HL
MOVINS:
    POP HL
    EX [SP],HL                      ; HL = the descriptor
    LD A,[HL]
    INC HL
    LD C,[HL]                       ; BC = its characters
    INC HL
    LD B,[HL]
    LD L,A

;; Copies L bytes from BC to DE.
;;
;; In:    BC = from, DE = to, L = the count
;; Out:   BC, DE = past the bytes, L = 0
;; Uses:  A
;; Keeps: H
MOVSTR:
    INC L                           ; for the DEC that tests for none
MOVLP:
    DEC L
    RET Z
    LD A,[BC]
    LD [DE],A
    INC BC
    INC DE
    JP MOVLP

;; Checks that the FAC holds a string and frees it if it is a temporary.
;;
;; In:    FACLO = the descriptor
;; Out:   HL = the descriptor
;; Errors: Type mismatch
;; See:   <FRETMP>
FRESTR:
    CALL CHKSTR

;; Frees the string in the FAC if it is the last temporary.
;;
;; In:    FACLO = the descriptor
;; Out:   HL = the descriptor
;; See:   <FRETMP>
FREFAC:
    LD HL,[FACLO]

;; Frees the string whose descriptor HL points at, if it is the last temporary.
;;
;; In:    HL = the descriptor
;; Out:   HL = the descriptor
;; See:   <FRETMP>
FRETM2:
    EX DE,HL

;; Frees the string whose descriptor DE points at if it is the last temporary, and its space if it is lowest.
;;
;; The descriptor still describes the string, so the caller can use it until it takes more string space.
;;
;; In:    DE = the descriptor
;; Out:   HL = the descriptor
FRETMP:
    CALL FRETMS
    EX DE,HL
    RET NZ                          ; not the last temporary
    PUSH DE
    LD D,B                          ; DE = the string's address, less one
    LD E,C
    DEC DE
    LD C,[HL]                       ; C = its length
    LD HL,[FRETOP]
    CALL DCOMPR                     ; the lowest string?
    JP NZ,NOTLST
    LD B,A                          ; A = 0 after the match: BC = the length
    ADD HL,BC
    LD [FRETOP],HL                  ; give its space back
NOTLST:
    POP HL
    RET

;; Gives the last temporary descriptor back if DE points at it.
;;
;; In:    DE = the descriptor
;; Out:   zero = it was the last temporary and is free, BC = the last temporary's string address,
;;   HL = the last temporary
;; Uses:  A
;; Keeps: DE
FRETMS:
    LD HL,[TEMPPT]
    DEC HL
    LD B,[HL]                       ; BC = the last temporary's address
    DEC HL
    LD C,[HL]
    DEC HL
    CALL DCOMPR
    RET NZ
    LD [TEMPPT],HL
    RET

;; Runs LEN, giving the length of the string argument.
;;
;; In:    FACLO = the argument's descriptor
;; Out:   FACLO = the FAC, the length, an integer
FN_LEN:
    LD BC,SNGFLT                    ; the result, from A
    PUSH BC

;; Frees the string argument and gets its length.
;;
;; In:    FACLO = the descriptor
;; Out:   A = the length, zero = an empty string, D = 0, HL = the descriptor
;; Errors: Type mismatch
LEN1:
    CALL FRESTR
    XOR A
    LD D,A                          ; D = 0, for VAL's DE = the length
    LD A,[HL]
    OR A
    RET

;; Runs ASC, giving the code of the string argument's first character.
;;
;; In:    FACLO = the argument's descriptor
;; Out:   FACLO = the FAC, the code, an integer
;; Errors: Illegal function call (5), for an empty string
FN_ASC:
    LD BC,SNGFLT                    ; the result, from A
    PUSH BC

;; Gets the first character of the string argument, freeing it.
;;
;; In:    FACLO = the descriptor
;; Out:   A = the character, DE = the string's characters, HL = the descriptor's address field + 1
;; Errors: Illegal function call (5), for an empty string
ASC2:
    CALL LEN1
    JP Z,FCERR                      ; an empty string
    INC HL
    LD E,[HL]                       ; DE = the characters
    INC HL
    LD D,[HL]
    LD A,[DE]
    RET

;; Runs CHR$, giving the one-character string of the code in the FAC.
;;
;; In:    FACLO = the FAC, the code, 0 to 255
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string)
;; Errors: Illegal function call (5)
FN_CHR:
    CALL STRIN1
    CALL CONINT                     ; E = the code

;; Stores the character in E as the one-character string described in DSCTMP and makes that the result.
;;
;; In:    E = the character, DSCTMP = the string, SP = at a word to drop, then the text pointer
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string)
;; Entry: FINBCK = only drops the word and makes DSCTMP the result
SETSTR:
    LD HL,[DSCPTR]                  ; the string's space
    LD [HL],E
FINBCK:
    POP BC                          ; drop the function's return to the numeric check
    JP PUTNEW

;; Runs STRING$(count, character), the character given by its code or as a string's first character.
;;
;; The evaluator jumps here at the STRING$ token. The repeat count stays on the stack, and the call to SPACE2
;; pushes the word FINBCK drops.
;;
;; In:    HL = the text, at the STRING$ token
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string), HL = the text after the ")"
;; Errors: Syntax error, Illegal function call (5), Out of string space (14)
FN_STRING:
    CALL CHRGTR                     ; skip the token
    CALL SYNCHR
    .byte '('
    CALL GETBYT                     ; E = the count
    PUSH DE
    CALL SYNCHR
    .byte ','
    CALL FRMEVL                     ; the character
    CALL SYNCHR
    .byte ')'
    EX [SP],HL                      ; stack the text pointer, HL = the count
    PUSH HL
    CALL GETYPR                     ; zero = a string
    JP Z,STRSTR
    CALL CONINT                     ; A = the code
    JP CALSPA
STRSTR:
    CALL ASC2                       ; A = the string's first character
CALSPA:
    POP DE                          ; E = the count
    CALL SPACE2

;; Runs SPACE$, giving a string of as many spaces as the number in the FAC.
;;
;; In:    FACLO = the FAC, the count, 0 to 255
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string)
;; Errors: Illegal function call (5), Out of string space (14)
;; Entry: SPACE2 = E copies of the character in A, for STRING$
FN_SPACE:
    CALL CONINT                     ; E = the count
    LD A,$20
SPACE2:
    PUSH AF
    LD A,E
    CALL STRINI                     ; a string of E characters
    LD B,A                          ; B = the count
    POP AF
    INC B                           ; none?
    DEC B
    JP Z,FINBCK
    LD HL,[DSCPTR]                  ; the string's space
SPLP:
    LD [HL],A
    INC HL
    DEC B
    JP NZ,SPLP
    JP FINBCK

;; Runs LEFT$(string, count), giving the string's first characters.
;;
;; In:    DE = the text, at the ")", SP = at the return address, the count (in E), the string's descriptor
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string)
;; Entry: LEFT3 = RIGHT$, with the offset of the first character in A
FN_LEFT:
    CALL PREAM
    XOR A                           ; from the first character
LEFT3:
    EX [SP],HL                      ; stack the text pointer, HL = the descriptor
    LD C,A                          ; C = the offset
    .byte $3E                       ; LD A,n: skips LEFTUS's PUSH HL

;; Makes a temporary of B characters, or fewer, from offset C of the string whose descriptor HL points at.
;;
;; Remarks: PRINT USING enters at LEFTUS, which pushes a word for PUTNEW to pop; MID$ returns into LEFT2.
;;
;; In:    HL = the descriptor, B = the count, C = the offset of the first character
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string)
;; Entry: LEFT2 = with the text pointer on the stack
LEFTUS:
    PUSH HL                         ; a stand-in for the text pointer
LEFT2:
    PUSH HL                         ; the descriptor, for FRETMP
    LD A,[HL]                       ; A = the length
    CP B
    JP C,ALLSTR                     ; shorter than the count: all of it
    LD A,B
    .byte $11                       ; LD DE,nn: skips the LD C,$00
ALLSTR:
    LD C,$00                        ; all of it, from the start
    PUSH BC
    CALL GETSPA                     ; DE = the space for A characters
    POP BC
    POP HL
    PUSH HL
    INC HL
    LD B,[HL]                       ; HL = the string's characters
    INC HL
    LD H,[HL]
    LD L,B
    LD B,$00
    ADD HL,BC                       ; from the offset
    LD B,H
    LD C,L
    CALL STRAD2                     ; DSCTMP = the result
    LD L,A
    CALL MOVSTR
    POP DE                          ; free the argument
    CALL FRETMP
    JP PUTNEW

;; Runs RIGHT$(string, count), giving the string's last characters.
;;
;; In:    DE = the text, at the ")", SP = at the return address, the count (in E), the string's descriptor
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string)
FN_RIGHT:
    CALL PREAM
    POP DE                          ; DE = the descriptor
    PUSH DE
    LD A,[DE]
    SUB B                           ; the offset: the length less the count
    JP LEFT3

;; Runs the MID$ function, MID$(string, start[, count]).
;;
;; Without a count, or with one past the end, it gives the rest of the string; with a start past the end,
;; an empty string. It returns into LEFT2 with the count and offset in B and C.
;;
;; In:    DE = the text, after the start, SP = at the return address, the start (in E), the string's descriptor
;; Out:   FACLO = the result's temporary descriptor, VALTYP = 3 (a string)
;; Errors: Illegal function call (5), for a start of 0
FN_MID:
    EX DE,HL                        ; HL = the text
    LD A,[HL]
    CALL PREAM2                     ; B = the start
    INC B
    DEC B
    JP Z,FCERR                      ; a start of 0
    PUSH BC
    CALL MIDRST                     ; E = the count
    POP AF                          ; A = the start
    EX [SP],HL                      ; stack the text pointer, HL = the descriptor
    LD BC,LEFT2
    PUSH BC
    DEC A                           ; the offset
    CP [HL]
    LD B,$00
    RET NC                          ; past the end: none
    LD C,A
    LD A,[HL]
    SUB C                           ; A = the characters from the offset
    CP E
    LD B,A
    RET C                           ; fewer than the count: those
    LD B,E
    RET

;; Runs VAL, giving the number the string argument starts with.
;;
;; A zero is put after the string for the number reader, and the byte it replaces put back.
;;
;; In:    FACLO = the argument's descriptor
;; Out:   FACLO = the FAC, the number, 0 for an empty string
FN_VAL:
    CALL LEN1
    JP Z,SNGFLT                     ; an empty string is 0
    LD E,A                          ; DE = the length
    INC HL
    LD A,[HL]                       ; HL = the characters
    INC HL
    LD H,[HL]
    LD L,A
    PUSH HL
    ADD HL,DE                       ; the byte after them
    LD B,[HL]
    LD [HL],D                       ; ends them with a zero
    EX [SP],HL
    PUSH BC
    DEC HL
    CALL CHRGTR                     ; skip leading spaces
    CALL FINDBL                     ; read the number
    POP BC
    POP HL
    LD [HL],B                       ; the byte back
    RET

;; Checks the ")" of LEFT$ and RIGHT$ and takes their count and descriptor from the stack.
;;
;; In:    DE = the text, SP = at the return address, then the count (in E) and the string's descriptor
;; Out:   HL = the text after the ")", B = the count, DE = the word the count was in
;; Errors: Syntax error
;; Entry: PREAM2 = for MID$, without the ")" check
PREAM:
    EX DE,HL
    CALL SYNCHR
    .byte ')'
PREAM2:
    POP BC                          ; the return address
    POP DE                          ; E = the count
    PUSH BC
    LD B,E
    RET

;; Runs INSTR([start,] string, substring), giving the position of the substring in the string.
;;
;; It gives 0 when the substring is not found or the start is past the string's end, and the start for an
;; empty substring. The evaluator jumps here at the INSTR token; the result returns through SNGFLT and POPHRT.
;;
;; In:    HL = the text, at the INSTR token
;; Out:   FACLO = the FAC, the position, an integer, HL = the text after the ")"
;; Errors: Syntax error, Type mismatch, Illegal function call (5), for a start of 0
FN_INSTR:
    CALL CHRGTR                     ; skip the token
    CALL FRMPRN                     ; "(" and the first argument
    CALL GETYPR                     ; zero = a string
    LD A,$01                        ; then the search starts at the first character
    PUSH AF
    JP Z,WUZSTR
    POP AF
    CALL CONINT                     ; A = the start
    OR A
    JP Z,FCERR                      ; a start of 0
    PUSH AF
    CALL SYNCHR
    .byte ','
    CALL FRMEVL                     ; the string
    CALL CHKSTR
WUZSTR:
    CALL SYNCHR
    .byte ','
    PUSH HL
    LD HL,[FACLO]
    EX [SP],HL                      ; stack the string's descriptor
    CALL FRMEVL                     ; the substring
    CALL SYNCHR
    .byte ')'
    PUSH HL
    CALL FRESTR
    EX DE,HL                        ; DE = the substring's descriptor
    POP BC                          ; BC = the text pointer
    POP HL                          ; HL = the string's descriptor
    POP AF                          ; A = the start
    PUSH BC
    LD BC,POPHRT                    ; restores the text pointer
    PUSH BC
    LD BC,SNGFLT                    ; the result, from A
    PUSH BC
    PUSH AF
    PUSH DE
    CALL FRETM2                     ; free the string
    POP DE
    POP AF
    LD B,A                          ; B = the start
    DEC A
    LD C,A                          ; C = the offset
    CP [HL]
    LD A,$00
    RET NC                          ; past the string's end: 0
    LD A,[DE]
    OR A
    LD A,B
    RET Z                           ; an empty substring: the start
    LD A,[HL]
    INC HL
    LD B,[HL]                       ; HL = the string's characters
    INC HL
    LD H,[HL]
    LD L,B
    LD B,$00
    ADD HL,BC                       ; from the offset
    SUB C
    LD B,A                          ; B = the characters left to search
    PUSH BC
    PUSH DE
    EX [SP],HL                      ; HL = the substring's descriptor
    LD C,[HL]                       ; C = its length
    INC HL
    LD E,[HL]                       ; DE = its characters
    INC HL
    LD D,[HL]
    POP HL
CHK1:
    PUSH HL                         ; this position in the string
    PUSH DE
    PUSH BC
CHK:
    LD A,[DE]
    CP [HL]
    JP NZ,OHWELL
    INC DE
    DEC C
    JP Z,GOTSTR                     ; all the substring matches
    INC HL
    DEC B
    JP NZ,CHK
    POP DE                          ; the string ended first
    POP DE
    POP BC
RETZR1:
    POP DE
    XOR A                           ; not found: 0
    RET
GOTSTR:
    POP HL                          ; H = the characters left where the match started
    POP DE
    POP DE
    POP BC
    LD A,B                          ; the position: the count to search less those left, plus the offset, plus 1
    SUB H
    ADD A,C
    INC A
    RET
OHWELL:
    POP BC
    POP DE
    POP HL
    INC HL                          ; try the next position
    DEC B
    JP NZ,CHK1
    JP RETZR1

;; Runs the MID$ statement, MID$(variable, start[, count]) = string, replacing characters in place.
;;
;; A variable whose string is not in string space, a literal in the program, is copied there first, but not a
;; field of a random file's buffer (below TXTTAB). The length never changes: the characters replaced are the
;; fewest of the count, the replacement's length and the characters from the start to the end.
;;
;; In:    HL = the text, after the MID$ token
;; Out:   HL = the text after the statement
;; Errors: Syntax error, Type mismatch, Illegal function call (5), for a start of 0 or past the end
LHSMID:
    CALL SYNCHR
    .byte '('
    CALL PTRGET                     ; DE = the variable
    CALL CHKSTR
    PUSH HL
    PUSH DE
    EX DE,HL
    INC HL
    LD E,[HL]                       ; DE = its characters
    INC HL
    LD D,[HL]
    LD HL,[STREND]
    CALL DCOMPR
    JP C,NCPMID                     ; in string space already
    LD HL,[TXTTAB]
    CALL DCOMPR
    JP NC,NCPMID                    ; a field in a file buffer: not copied
    POP HL
    PUSH HL
    CALL STRCPY                     ; copy it into string space
    POP HL
    PUSH HL
    CALL VMOVE                      ; and point the variable at the copy
NCPMID:
    POP HL
    EX [SP],HL                      ; stack the descriptor, HL = the text
    CALL SYNCHR
    .byte ','
    CALL GETBYT                     ; the start
    OR A
    JP Z,FCERR                      ; a start of 0
    PUSH AF
    LD A,[HL]
    CALL MIDRST                     ; E = the count
    PUSH DE
    CALL FRMEQL                     ; "=" and the replacement
    PUSH HL
    CALL FRESTR
    EX DE,HL                        ; DE = the replacement's descriptor
    POP HL
    POP BC                          ; C = the count
    POP AF
    LD B,A                          ; B = the start
    EX [SP],HL                      ; stack the text pointer, HL = the variable's descriptor
    PUSH HL
    LD HL,POPHRT                    ; restores the text pointer
    EX [SP],HL
    LD A,C
    OR A
    RET Z                           ; a count of 0: nothing
    LD A,[HL]
    SUB B                           ; the characters after the start
    JP C,FCERR                      ; a start past the end
    INC A
    CP C
    JP C,BIGLEN
    LD A,C                          ; no more than the count
BIGLEN:
    LD C,B                          ; BC = the offset
    DEC C
    LD B,$00
    PUSH DE
    INC HL
    LD E,[HL]                       ; HL = the variable's characters
    INC HL
    LD H,[HL]
    LD L,E
    ADD HL,BC                       ; from the offset
    LD B,A                          ; B = the characters there
    POP DE
    EX DE,HL
    LD C,[HL]                       ; C = the replacement's length
    INC HL
    LD A,[HL]                       ; DE = its characters
    INC HL
    LD H,[HL]
    LD L,A
    EX DE,HL
    LD A,C
    OR A
    RET Z                           ; an empty replacement: nothing
MIDLP:
    LD A,[DE]
    LD [HL],A
    INC DE
    INC HL
    DEC C
    RET Z                           ; the replacement is used up
    DEC B
    JP NZ,MIDLP                     ; or the variable's characters
    RET

;; Reads MID$'s optional count and its ")".
;;
;; In:    HL = the text, A = the character there
;; Out:   E = the count, 255 if there is none, HL = the text after the ")"
;; Errors: Syntax error, Illegal function call (5)
MIDRST:
    LD E,$FF                        ; all the characters
    CP $29                          ; ")": no count
    JP Z,MID2
    CALL SYNCHR
    .byte ','
    CALL GETBYT                     ; E = the count
MID2:
    CALL SYNCHR
    .byte ')'
    RET

;; Runs FRE, giving the free bytes between the arrays and the strings, after collecting garbage for a string
;; argument.
;;
;; In:    FACLO = the FAC: the argument
;; Out:   FACLO = the FAC, FRETOP - STREND, an integer
FN_FRE:
    CALL GETYPR                     ; zero = a string
    JP NZ,CLCDIF
    CALL FREFAC
    CALL GARBA2
CLCDIF:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    LD HL,[FRETOP]
    JP GIVDBL                       ; HL - DE as the result
