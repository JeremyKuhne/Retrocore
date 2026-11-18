;; MBASIC 5.21: DIM AND THE VARIABLE SEARCH (PTRGET)
;;
;; Finds or creates the variable or array element named in the program text, Microsoft's DIMENSION AND
;; VARIABLE SEARCHING, GW-BASIC's BIPTRG.ASM (with the search loops GW-BASIC moved to MATH1.ASM).
;;
;; - PTRGET reads a name of up to 40 characters: the first in C, the second in B, any others in NAMBUF with
;;   their count in NAMCNT, each with bit 7 set. The type comes from a %, $, ! or # after it, or from
;;   DEFTBL for its first letter. ST_DIM enters it with DIMFLG set, so that each array is created.
;; - A simple variable is searched for by LOPFND: first in a user function's parameters (PARM1), then from
;;   VARTAB to ARYTAB. Each entry is the type (2, 3, 4 or 8, the value's size), the first and second characters,
;;   the count of the others and the others, then the value. A missing variable is made by SMKVAR, except for
;;   VARPTR (through PTRGTN), which gets DE = 0, and an expression (RETVAR), which reads zero or "".
;; - ISARY evaluates an array's subscripts onto the stack, and LOPFDA searches ARYTAB to STREND. An array's
;;   entry has the same name bytes, then its size, the number of dimensions, each dimension's size, then the
;;   elements. NOTFDD makes a missing array, with 11 elements a dimension (10 in OPTION BASE 1) unless DIM gave
;;   the sizes; GETDEF works out the element's address.
;; - ERSFIN is ERASE's way in: it finds the array and returns its address instead of an element's.
;;
;; Runs at $397D-$3CD4. It starts with DIMCON, where DIM returns for each array. The main entry points are
;; ST_DIM, PTRGET, PTRGT2, PTRGTN, NOARYS, ERSFIN and IADAHL.

;; Goes on to DIM's next array after a comma, or returns at the end of the statement.
;;
;; ST_DIM, just below, pushes it as the return address of each array it dimensions.
;;
;; In:    HL = the text after an array's dimensions
DIMCON:
    DEC HL
    CALL CHRGTR
    RET Z                           ; the end of the statement
    CALL SYNCHR
    .byte ','

;; Runs DIM, creating each array in the list with the sizes given.
;;
;; Returns to DIMCON after each array, which goes on at a comma and returns at the end of the statement.
;; In:    HL = the text after DIM
;; Errors: SN error for a bad name, DD error for an array that exists already, BS, OM error
ST_DIM:
    LD BC,DIMCON                    ; back to DIMCON after each array
    PUSH BC
    .byte $F6                       ; OR $AF: A = nonzero for DIMFLG, skipping the XOR

;; Finds the variable or array element named at HL, creating it if it does not exist.
;;
;; Evaluating subscripts can call PTRGET again, so everything it needs to keep is on the stack.
;; In:    HL = the text, at the name
;; Out:   DE = the value's address, HL = the text after the name and any subscripts,
;;   VALTYP = the type: 2 integer, 3 string, 4 single, 8 double
;; Errors: SN error for a name that doesn't start with a letter or is too long, BS error for a subscript out of
;;   range, OM error
;; Entry: PTRGT2 = with DIMFLG set and the first character in C, bit 7 set for a user function's name
PTRGET:
    XOR A                           ; not DIM
    LD [DIMFLG],A
    LD C,[HL]                       ; C = the first character
PTRGT2:
    CALL ISLET                      ; it must be a letter
    JP C,SNERR
    XOR A
    LD B,A                          ; B = the second character, none yet
    LD [NAMCNT],A                   ; NAMCNT = no more characters
    INC HL
    LD A,[HL]
    CP '.'                          ; below the dot: the name ends
    JP C,NOSEC
    JP Z,ISSEC                      ; a dot is part of a name
    CP '9'+1
    JP NC,PTRGT3
    CP '0'
    JP NC,ISSEC                     ; a digit
PTRGT3:
    CALL ISLET2                     ; a letter?
    JP C,NOSEC
ISSEC:
    LD B,A                          ; B = the second character
    PUSH BC
    LD B,$FF                        ; B counts the characters after the second
    LD DE,NAMCNT                    ; the second goes to NAMCNT and is overwritten there
VMORCH:
    OR $80                          ; the rest have bit 7 set, so they can be scanned backwards
    INC B
    LD [DE],A
    INC DE
    INC HL
    LD A,[HL]
    CP '9'+1
    JP NC,VMORC1
    CP '0'
    JP NC,VMORCH                    ; a digit
VMORC1:
    CALL ISLET2                     ; a letter?
    JP NC,VMORCH
    CP '.'
    JP Z,VMORCH
    LD A,B
    CP $27                          ; at most 38 more, 40 in all
    JP NC,SNERR
    POP BC
    LD [NAMCNT],A
    LD A,[HL]                       ; A = the character after the name
NOSEC:
    CP '%'+1                        ; a type character?
    JP NC,TABTYP
    LD DE,HAVTYP                    ; each match returns to HAVTYP with the type in D
    PUSH DE
    LD D,$02                        ; % integer
    CP '%'
    RET Z
    INC D                           ; $ string
    CP '$'
    RET Z
    INC D                           ; ! single
    CP '!'
    RET Z
    LD D,$08                        ; # double
    CP '#'
    RET Z
    POP AF                          ; none of them
TABTYP:
    LD A,C                          ; the type DEFINT and the rest gave the first letter
    AND $7F                         ; without the user function bit
    LD E,A
    LD D,$00
    PUSH HL
    LD HL,DEFTBL-'A'
    ADD HL,DE
    LD D,[HL]                       ; D = the type
    POP HL
    DEC HL                          ; no type character to pass
HAVTYP:
    LD A,D
    LD [VALTYP],A
    CALL CHRGTR                     ; past the name
    LD A,[SUBFLG]
    DEC A
    JP Z,ERSFIN                     ; SUBFLG = 1: ERASE wants the array itself
    JP P,NOARYS                     ; above 1: no arrays allowed
    LD A,[HL]
    SUB '('                         ; ( or [ starts the subscripts
    JP Z,ISARY
    SUB '['-'('
    JP Z,ISARY

;; Searches for the simple variable whose name and type PTRGET has read, creating it if it does not exist.
;;
;; In a user function (NOFUNS, nonzero), its parameters in PARM1 are searched first, PRMFLG
;; being set while they are. ARYTA2 is where the table being searched ends.
;; In:    HL = the text after the name, C, B, NAMCNT and NAMBUF = the name, VALTYP = the type
;; Out:   DE = the value's address, HL = the text
;; Errors: OM error
NOARYS:
    XOR A                           ; allow arrays again
    LD [SUBFLG],A
    PUSH HL                         ; keep the text pointer
    LD A,[NOFUNS]                   ; in a user function?
    OR A
    LD [PRMFLG],A                   ; its parameters to search first
    JP Z,SNFUNS
    LD HL,[PRMLEN]
    LD DE,PARM1
    ADD HL,DE
    LD [ARYTA2],HL                  ; ARYTA2 = the parameters' end
    EX DE,HL                        ; HL = the first parameter
    JP LOPFND
LOPTOP:
    LD A,[DE]                       ; the entry's type, which is its value's size
    LD L,A
    INC DE
    LD A,[DE]                       ; the first character
    INC DE
    CP C
    JP NZ,NOTIT1
    LD A,[VALTYP]                   ; the same type?
    CP L
    JP NZ,NOTIT1
    LD A,[DE]                       ; the second character
    CP B
    JP Z,ISIT                       ; perhaps this one
NOTIT1:
    INC DE                          ; DE = the count of the other characters
LOPTOP_1:
    LD A,[DE]
NOTIT0:
    LD H,$00                        ; HL = DE + the count + 1 + the value's size: the next entry
    ADD A,L
    INC A
    LD L,A
    ADD HL,DE
LOPFND:
    EX DE,HL                        ; DE = the entry
    LD A,[ARYTA2]                   ; at ARYTA2, the table's end?
    CP E
    JP NZ,LOPTOP
    LD A,[ARYTA2_HI]
    CP D
    JP NZ,LOPTOP
    LD A,[PRMFLG]                   ; were those the parameters?
    OR A
    JP Z,SMKVAR                     ; no: not found
    XOR A
    LD [PRMFLG],A
SNFUNS:
    LD HL,[ARYTAB]                  ; now the variables, VARTAB to ARYTAB
    LD [ARYTA2],HL
    LD HL,[VARTAB]
    JP LOPFND

;; Looks a variable up as PTRGET does, but gives DE = 0 instead of creating it, for VARPTR.
;;
;; SMKVAR tells this caller by the return address, PTRGTR.
;; In:    HL = the text, at the name
;; Out:   DE = the value's address, or 0 with A = 0 if the variable does not exist, HL = the text after the name
;; Entry: PTRGTR = PTRGET's return address here, which SMKVAR tests
PTRGTN:
    CALL PTRGET
PTRGTR:
    RET

;; Returns DE = 0 from PTRGET, for PTRGTN's missing variable.
;; Out:   DE = 0, A = 0, HL = the text
VARNOT:
    LD D,A                          ; A = 0
    LD E,A
    POP BC                          ; drop the table's end
    EX [SP],HL                      ; the return address back, HL = the text
    RET

;; Makes a new simple variable at the end of the variable table, moving the arrays up, and zeroes it.
;;
;; Called from PTRGTN, it returns DE = 0 instead (VARNOT); from RETVAR in the expression evaluator, it gives
;; zero, or an empty string, without making the variable (FINZER).
;; In:    DE = the table's end, the stack = the text, then the return address
;; Out:   DE = the value's address, HL = the text
;; Errors: OM error
SMKVAR:
    POP HL                          ; HL = the text
    EX [SP],HL                      ; HL = the return address, the text stacked
    PUSH DE
    LD DE,PTRGTR                    ; from PTRGTN?
    CALL DCOMPR
    JP Z,VARNOT
    LD DE,RETVAR                    ; from the expression evaluator?
    CALL DCOMPR
    POP DE
    JP Z,FINZER
    EX [SP],HL                      ; the return address back, HL = the text
    PUSH HL
    PUSH BC                         ; keep the name
    LD A,[VALTYP]
    LD B,A
    LD A,[NAMCNT]
    ADD A,B
    INC A                           ; C = the value, the count and the other characters
    LD C,A
    PUSH BC                         ; B = the type, kept
    LD B,$00
    INC BC                          ; and the type and two characters
    INC BC
    INC BC
    LD HL,[STREND]
    PUSH HL
    ADD HL,BC                       ; HL = the new STREND
    POP BC
    PUSH HL
    CALL BLTU                       ; move the arrays up
    POP HL
    LD [STREND],HL
    LD H,B                          ; HL = the arrays' new start
    LD L,C
    LD [ARYTAB],HL
ZEROER:
    DEC HL                          ; zero the entry, down to DE
    LD [HL],$00
    CALL DCOMPR
    JP NZ,ZEROER
    POP DE                          ; D = the type
    LD [HL],D
    INC HL
    POP DE                          ; the name: E the first character, D the second
    LD [HL],E
    INC HL
    LD [HL],D
    CALL NPUTSB                     ; the count and the other characters
    EX DE,HL
    INC DE                          ; DE = the value
    POP HL                          ; HL = the text
    RET

;; Checks the rest of a simple variable's name once its first two characters and type match.
;; In:    DE = the entry's second character, L = its type, the stack = the text
;; Out:   DE = the value's address and HL = the text, returning from PTRGET, if it matches; otherwise goes on
;;   with the next entry
ISIT:
    INC DE                          ; DE = the entry's count of other characters
    LD A,[NAMCNT]                   ; the same length?
    LD H,A
    LD A,[DE]
    CP H
    JP NZ,LOPTOP_1
    OR A
    JP NZ,LENMAT
    INC DE                          ; a two-character name: found
    POP HL
    RET
LENMAT:
    EX DE,HL
    CALL NAMCMP
    EX DE,HL                        ; DE = past the name
    JP NZ,NOTIT0                    ; A = $FF, so NOTIT0 skips just the value
    POP HL                          ; found
    RET

;; Reads a missing variable as zero, or as an empty string, and returns past the expression evaluator's
;; RETVAR without making the variable.
;; In:    A = 0, the stack = the text
;; Out:   FAC = zero, FACLO = zero or an empty string's descriptor, HL = the text
FINZER:
    LD [FAC],A                      ; a zero exponent is zero
    LD H,A
    LD L,A
    LD [FACLO],HL
    CALL GETYPR                     ; a string?
    JP NZ,POPHR2
    LD HL,REDDY-1                   ; a zero byte (the end of " in "), an empty string
    LD [FACLO],HL
POPHR2:
    POP HL                          ; HL = the text
    RET

;; Evaluates an array reference's subscripts onto the stack, then looks the array up.
;;
;; DIMFLG and VALTYP, and a long name's characters, are kept on the stack while each subscript is evaluated,
;; since the subscript can use PTRGET too. In OPTION BASE 1, each subscript is made one less.
;; In:    HL = the text, at the ( or [, A = 0, C, B, NAMCNT and NAMBUF = the name
;; Out:   DE = the element's address, HL = the text after the subscripts
;; Errors: SN error for a bad subscript list, BS error for a subscript out of range, DD error, OM error
ISARY:
    PUSH HL
    LD HL,[DIMFLG]                  ; DIMFLG and VALTYP, kept for recursion
    EX [SP],HL
    LD D,A                          ; D = the subscripts so far
INDLOP:
    PUSH DE
    PUSH BC                         ; keep the name
    LD DE,NAMCNT
    LD A,[DE]
    OR A
    JP Z,SHTNAM                     ; a two-character name
    EX DE,HL                        ; HL = NAMCNT, DE = the text
    ADD A,$02                       ; (NAMCNT + 2) / 2 words hold the count and the characters
    RRA
    LD C,A
    CALL GETSTK                     ; room for them?
    LD A,C
LPPSNM:
    LD C,[HL]                       ; push them
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    DEC A
    JP NZ,LPPSNM
    PUSH HL                         ; where to put them back
    LD A,[NAMCNT]
    PUSH AF
    EX DE,HL                        ; HL = the text
    CALL INTIDX                     ; DE = the subscript
    POP AF
    LD [NAMTMP],HL                  ; NAMTMP = the text
    POP HL
    ADD A,$02
    RRA
LPLNAM:
    POP BC                          ; put the name back
    DEC HL
    LD [HL],B
    DEC HL
    LD [HL],C
    DEC A
    JP NZ,LPLNAM
    LD HL,[NAMTMP]
    JP LNGNAM
SHTNAM:
    CALL INTIDX                     ; DE = the subscript
    XOR A
    LD [NAMCNT],A                   ; NAMCNT = 0 again
LNGNAM:
    LD A,[OPTVAL]
    OR A
    JP Z,OPTB0
    LD A,D                          ; base 1: 0 is out of range
    OR E
    JP Z,BSERR
    DEC DE
OPTB0:
    POP BC                          ; the name
    POP AF                          ; A = the subscripts so far
    EX DE,HL                        ; HL = the subscript, DE = the text
    EX [SP],HL                      ; stack it, HL = DIMFLG and VALTYP
    PUSH HL                         ; and them above it
    EX DE,HL
    INC A
    LD D,A
    LD A,[HL]
    CP ','                          ; another subscript?
    JP Z,INDLOP
    CP ')'
    JP Z,DOCHRT
    CP ']'
    JP NZ,SNERR
DOCHRT:
    CALL CHRGTR
    LD [TEMP2],HL                   ; keep the text pointer
    POP HL
    LD [DIMFLG],HL                  ; DIMFLG and VALTYP back
    LD E,$00                        ; popped as AF: A = the count, zero clear
    PUSH DE
    .byte $11                       ; LD DE,n: skips ERSFIN's pushes

;; Finds the array that ERASE names, with SUBFLG = 1, giving the address of its dimension count.
;;
;; Pushes a zero flag in place of a subscript count; LOPFDA's ending then returns through POPHRT.
;; In:    HL = the text after the name, C, B, NAMCNT and NAMBUF = the name, VALTYP = the type
;; Out:   BC = the array's dimension count's address, HL = the text; or A = $FF, carry = set if the array
;;   does not exist
ERSFIN:
    PUSH HL
    PUSH AF                         ; zero set: no subscripts
    LD HL,[ARYTAB]
    .byte $3E                       ; LD A,n: skips the ADD

;; Searches the arrays, ARYTAB to STREND, for the one named, then makes it or finds the element.
;;
;; A match with DIMFLG set is a DD error.
;; In:    HL = the array, DE = the size of the one before, the stack = the subscript count, the subscripts
LOPFDA:
    ADD HL,DE                       ; past the array before
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL                        ; DE = STREND
    CALL DCOMPR                     ; the end?
    JP Z,NOTFDD
    LD E,[HL]                       ; E = the type
    INC HL
    LD A,[HL]                       ; the first character
    INC HL
    CP C
    JP NZ,NMARY1
    LD A,[VALTYP]
    CP E
    JP NZ,NMARY1
    LD A,[HL]                       ; the second character
    CP B
    JP Z,LOPFDA_1
NMARY1:
    INC HL                          ; HL = the count of the other characters
NMARY2:
    LD E,[HL]                       ; skip them; INC E leaves zero clear
    INC E
    LD D,$00
    ADD HL,DE
NMARY4:
    LD E,[HL]                       ; DE = the array's size
    INC HL
    LD D,[HL]
    INC HL
    JP NZ,LOPFDA                    ; not this one
    LD A,[DIMFLG]                   ; DIM of an array that exists
    OR A
    JP NZ,DDERR
    POP AF                          ; A = the subscript count
    LD B,H                          ; BC = the dimension count's address
    LD C,L
    JP Z,POPHRT                     ; ERASE is done
    SUB [HL]                        ; the same number of dimensions?
    JP Z,GETDEF

;; Gives a BS error, a subscript out of range.
BSERR:
    LD DE,$0009                     ; Subscript out of range
    JP ERROR
LOPFDA_1:
    INC HL                          ; HL = the count of the other characters
    LD A,[NAMCNT]                   ; the same length?
    CP [HL]
    JP NZ,NMARY2
    INC HL
    OR A
    JP Z,NMARY4                     ; a two-character name: found, zero set
    DEC HL
    CALL NAMCMP
    JP NMARY4                       ; zero = found

;; Makes a new array at the end of the arrays, zeroes it, and finds the element unless DIM is making it.
;;
;; Each dimension's size is its subscript plus one if DIM gave it, otherwise 11 (10 in OPTION BASE 1).
;; In:    HL = STREND, C, B, NAMCNT and NAMBUF = the name, the stack = the subscript count, the subscripts
;; Out:   DE = the element's address, HL = the text
;; Errors: OM error
NOTFDD:
    LD A,[VALTYP]                   ; the type
    LD [HL],A
    INC HL
    LD E,A                          ; DE = an element's size
    LD D,$00
    POP AF                          ; A = the subscript count
    JP Z,PTRRNZ                     ; zero set: from ERSFIN, nothing to make
    LD [HL],C                       ; the name
    INC HL
    LD [HL],B
    CALL NPUTSB                     ; and the rest of it
    INC HL
    LD C,A                          ; C = the number of dimensions
    CALL GETSTK
    INC HL                          ; skip the size, stored last
    INC HL
    LD [TEMP3],HL                   ; where the dimension count goes
    LD [HL],C
    INC HL
    LD A,[DIMFLG]                   ; carry = set for DIM
    RLA
    LD A,C
LOPPTA:
    JP C,POPDIM
    PUSH AF
    LD A,[OPTVAL]                   ; 0 gives 11 elements, 1 gives 10
    XOR $0B
    LD C,A
    LD B,$00
    POP AF
    JP NC,NOTDIM
POPDIM:
    POP BC                          ; BC = DIM's subscript
    INC BC                          ; plus element zero
NOTDIM:
    LD [HL],C                       ; this dimension's size
    PUSH AF
    INC HL
    LD [HL],B
    INC HL
    CALL UMULT                      ; DE = the size so far
    POP AF
    DEC A
    JP NZ,LOPPTA
    PUSH AF                         ; keep the DIM carry
    LD B,D                          ; BC = the elements' size
    LD C,E
    EX DE,HL                        ; DE = the first element
    ADD HL,DE                       ; HL = the end
    JP C,OMERR
    CALL REASON                     ; room for it?
    LD [STREND],HL
ZERITA:
    DEC HL                          ; zero the elements
    LD [HL],$00
    CALL DCOMPR
    JP NZ,ZERITA
    INC BC                          ; the size, with the dimension count
    LD D,A                          ; D = 0
    LD HL,[TEMP3]
    LD E,[HL]                       ; E = the number of dimensions
    EX DE,HL
    ADD HL,HL                       ; two bytes for each
    ADD HL,BC
    EX DE,HL                        ; DE = the array's size
    DEC HL
    DEC HL
    LD [HL],E                       ; store it
    INC HL
    LD [HL],D
    INC HL                          ; HL = the dimension count
    POP AF
    JP C,FINNOW                     ; DIM only makes the array

;; Works out the address of the element the stacked subscripts give.
;;
;; The offset is built a dimension at a time, then multiplied by the element's size: 2, 3, 4 or 8.
;; In:    HL = the array's dimension count, A = 0, the stack = the subscripts, then the first element's address
;; Out:   DE = the element's address, HL = TEMP2, the text after the subscripts
;; Errors: BS error for a subscript too large
GETDEF:
    LD B,A                          ; BC = the offset, 0
    LD C,A
    LD A,[HL]                       ; A = the number of dimensions
    INC HL
    .byte $16                       ; LD D,n: skips the POP
INLPNM:
    POP HL                          ; HL = the next dimension's size
    LD E,[HL]                       ; DE = it
    INC HL
    LD D,[HL]
    INC HL
    EX [SP],HL                      ; keep the pointer, HL = the subscript
    PUSH AF
    CALL DCOMPR                     ; below the size?
    JP NC,BSERR
    CALL UMULT                      ; DE = the offset times the size
    ADD HL,DE                       ; plus the subscript
    POP AF
    DEC A
    LD B,H                          ; BC = the offset
    LD C,L
    JP NZ,INLPNM
    LD A,[VALTYP]                   ; the element's size
    LD B,H
    LD C,L
    ADD HL,HL                       ; times 2
    SUB $04
    JP C,SMLVAL                     ; an integer or string
    ADD HL,HL                       ; times 4 for a single
    JP Z,DONMUL
    ADD HL,HL                       ; times 8 for a double
SMLVAL:
    OR A                            ; odd parity for an integer, even for a string
    JP PO,DONMUL
    ADD HL,BC                       ; times 3 for a string
DONMUL:
    POP BC                          ; BC = the first element
    ADD HL,BC
    EX DE,HL
FINNOW:
    LD HL,[TEMP2]                   ; the text after the subscripts
    RET

;; Returns nonzero to ERASE for an array that does not exist, popping the text pointer ERSFIN pushed.
;; Out:   A = $FF, carry = set, zero = clear, HL = the text
PTRRNZ:
    SCF
    SBC A,A
    POP HL
    RET

;; Adds the count at HL, and one, to HL: skips a long name's count and characters.
;; In:    HL = the count
;; Out:   HL = past the characters, A = the count
;; Keeps: BC, DE
IADAHL:
    LD A,[HL]
    INC HL

;; Adds A to HL.
;; In:    A = the number, HL = the address
;; Out:   HL = HL + A
;; Keeps: A, BC, DE
ADDAHL:
    PUSH BC
    LD B,$00
    LD C,A
    ADD HL,BC
    POP BC
    RET

;; Stores NAMCNT and the characters in NAMBUF after HL, in a new variable's or array's entry.
;; In:    HL = the byte before where they go
;; Out:   HL = the last byte stored
;; Keeps: A, BC, DE
NPUTSB:
    PUSH BC
    PUSH DE
    PUSH AF
    LD DE,NAMCNT                    ; NAMCNT, then NAMBUF
    LD A,[DE]
    LD B,A                          ; B = the count, and the count itself
    INC B
SLPLNG:
    LD A,[DE]
    INC DE
    INC HL
    LD [HL],A
    DEC B
    JP NZ,SLPLNG
    POP AF
    POP DE
    POP BC
    RET

;; Compares the characters after a table entry's count with those in NAMBUF.
;; In:    HL = the entry's count of other characters, A = the count, the same as NAMCNT
;; Out:   zero = set if they match, HL = past the characters, A = $FF if they don't
;; Keeps: BC, DE
NAMCMP:
    PUSH DE
    PUSH BC
    LD DE,NAMBUF
    LD B,A
    INC HL
    INC B
NAMCMP_1:
    DEC B
    JP Z,NAMCMP_2                   ; all match
    LD A,[DE]
    INC DE
    CP [HL]
    INC HL
    JP Z,NAMCMP_1
    LD A,B                          ; skip the rest
    DEC A
    CALL NZ,ADDAHL
    XOR A                           ; A = $FF, zero clear
    DEC A
NAMCMP_2:
    POP BC
    POP DE
    RET
