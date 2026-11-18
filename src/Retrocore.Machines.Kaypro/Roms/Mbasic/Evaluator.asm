;; MBASIC 5.21: THE FORMULA EVALUATOR
;;
;; Evaluates expressions into the floating accumulator (the FAC, at FACLO, with its type in VALTYP),
;; and holds the functions and statements that sit beside it in Microsoft's source: user functions (DEF FN, FN,
;; DEF USR, USR), VARPTR, INP, OUT, WAIT and WIDTH, and the GETBYT family that turns an expression into a byte
;; or an integer. It corresponds to GW-BASIC's GWEVAL.ASM, routine for routine and in the same order, without
;; GW-BASIC's DEF SEG and PC hardware functions; Level2.asm has the Z80 form of much of it.
;;
;; - FRMEVL evaluates an expression by operator precedence. LPOPER calls EVAL for an operand, then looks at the
;;   operator after it: one that binds tighter than the pending one (OPTAB) pushes the left operand with the
;;   address of its routine (APPLOP, EXPSTK's FPWRQ, ANDORD's DANDOR or FINREL's DOCMP) and evaluates the right
;;   operand at its own precedence; one that does not returns, so the pending operator is applied first.
;; - APPLOP brings the two operands of an arithmetic or comparison operator to one type and dispatches
;;   through INTDSP, SNGDSP or DBLDSP. DANDOR applies the integer operators AND, OR, XOR, EQV, IMP, MOD and \.
;; - EVAL evaluates one operand: a number, a variable, a string, unary minus and NOT, &H and &O constants, ERR,
;;   ERL, VARPTR, a function through ISFUN and FUNDSP, or an expression in parentheses (PARCHK).
;; - FNDOER calls a user function: it saves the current parameter block, binds the arguments to the
;;   parameters in a new one (PARM2, then PARM1) and evaluates the definition's formula.
;;
;; Runs at $19F7-$2083. FRMEVL, FRMPRN, GETYPR, GETBYT and CONINT are used throughout the interpreter.

;; Requires an equal sign, then evaluates the expression after it.
;;
;; In:    HL = the text, at the equal sign
;; Out:   HL = the text after the expression, FACLO = the value, VALTYP = its type
;; Errors: SN without the equal sign
FRMEQL:
    CALL SYNCHR
    .byte $F0                       ; the = token
    JP FRMEVL

;; Requires an opening parenthesis, then evaluates the expression after it.
;;
;; In:    HL = the text, at the parenthesis
;; Out:   HL = the text after the expression, FACLO = the value, VALTYP = its type
;; Errors: SN without the parenthesis
FRMPRN:
    CALL SYNCHR
    .byte '('

;; Evaluates the expression at HL into the FAC.
;;
;; In:    HL = the text, at the character before the expression
;; Out:   HL = the text after the expression, FACLO = the value, VALTYP = its type: 2 integer, 3 string
;;   (FACLO = its descriptor), 4 single, 8 double
;; Errors: MO without an operand, SN, TM, OV and the errors of the functions called
;; Entry: FRMCHK = HL at the expression's first character, already fetched,
;;   LPOPER = evaluates only the operators that bind tighter than the precedence in D
FRMEVL:
    DEC HL                          ; fetch the first character again
FRMCHK:
    LD D,$00                        ; any operator binds tighter than 0
LPOPER:
    PUSH DE                         ; keep the pending operator's precedence
    LD C,$01                        ; room for the recursion
    CALL GETSTK
    CALL EVAL                       ; the operand
    XOR A                           ; overflow messages again (FN calls set it)
    LD [FLGOVC],A

;; Goes on with an expression after an operand: keeps the text pointer, then applies the next operator.
;;
;; CAT (Strings.asm) has PUTNEW return here with the joined string, as an operand of its own.
;;
;; In:    HL = the text after the operand
TSTOP:
    LD [TEMP2],HL

;; Applies the operator after an operand, or returns at the end of the expression.
;;
;; An operator that binds no tighter than the pending one in B returns, so that the caller applies the
;; pending one first. Relations go to DORELS, and + of two strings to CAT.
;;
;; In:    TEMP2 = the text after the operand, the pending precedence on the stack
;; Out:   HL = the text at the character that ended the expression, TEMP3 = the same
RETAOP:
    LD HL,[TEMP2]                   ; HL = the text after the operand
    POP BC                          ; B = the pending precedence
    LD A,[HL]
    LD [TEMP3],HL
    CP $EF                          ; below >: not an operator
    RET C
    CP $F2                          ; > = <: a relation
    JP C,DORELS
    SUB $F2                         ; E = the operator, 0 for +
    LD E,A
    JP NZ,NTPLUS
    LD A,[VALTYP]                   ; + of a string joins strings
    CP $03
    LD A,E
    JP Z,CAT

;; Applies an arithmetic or logical operator, if it binds tighter than the pending one.
;;
;; Pushes the address of RETAOP, then the left operand as the operator needs it, and evaluates the right one.
;; An operator that does not bind tighter returns at once, unapplied.
;;
;; In:    A, E = the operator, from 0 for + to 11 for \, B = the pending precedence, HL = the text at the
;;   operator, the pending precedence on the stack
NTPLUS:
    CP $0C                          ; past \: not an operator
    RET NC
    LD HL,OPTAB
    LD D,$00
    ADD HL,DE
    LD A,B                          ; A = the pending precedence
    LD D,[HL]                       ; D = this operator's
    CP D                            ; binds no tighter: apply the pending one first
    RET NC
    PUSH BC                         ; keep the pending precedence
    LD BC,RETAOP                    ; come back there after applying it
    PUSH BC
    LD A,D
    CP $7F                          ; ^ works in single precision
    JP Z,EXPSTK
    CP $51                          ; AND, OR, XOR, EQV and IMP in integers,
    JP C,ANDORD
    AND $FE                         ; and so do MOD (122) and \ (123)
    CP $7A
    JP Z,ANDORD

;; Pushes the FAC as an operator's left operand, then evaluates the right one and applies them at APPLOP.
;;
;; The value is pushed in the FAC's order, then the type and operator as one word.
;;
;; In:    D = the operator's precedence, E = the operator
;; Errors: TM for a string
;; Entry: VPUSHD = pushes the type and operator, with A the type less 3
NUMREL:
    LD HL,FACLO
    LD A,[VALTYP]
    SUB $03                         ; zero for a string,
    JP Z,TMERR
    OR A                            ; negative for an integer, odd parity for a single
    LD C,[HL]                       ; push the low word
    INC HL
    LD B,[HL]
    PUSH BC
    JP M,VPUSHD                     ; an integer is all pushed
    INC HL                          ; push the high word
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    JP PO,VPUSHD                    ; a single is all pushed
    LD HL,DFACLO                    ; a double's low four bytes too
    LD C,[HL]
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
VPUSHD:
    ADD A,$03                       ; A = the type
    LD C,E                          ; C = the operator
    LD B,A                          ; B = the left operand's type
    PUSH BC
    LD BC,APPLOP                    ; apply it at APPLOP

;; Pushes the routine that will apply the operator, then evaluates the right operand from the operator.
;;
;; Continues at LPOPER.
;;
;; In:    BC = the routine, D = the operator's precedence, TEMP3 = the text at the operator
FINTMP:
    PUSH BC
    LD HL,[TEMP3]
    JP LPOPER

;; Gathers the relational operators after an operand into a mask in D: 1 for >, 2 for =, 4 for <.
;;
;; Continues at FINREL with D = the mask.
;;
;; In:    A = the first relational token, HL = the text there
;; Errors: SN for the same relation twice
;; Entry: LOPREL = takes the next token, with D the mask so far
DORELS:
    LD D,$00
LOPREL:
    SUB $EF                         ; > = < become 0 1 2
    JP C,FINREL
    CP $03
    JP NC,FINREL
    CP $01                          ; and 1 2 4
    RLA
    XOR D                           ; add the bit, a smaller result if it was there
    CP D
    LD D,A
    JP C,SNERR
    LD [TEMP3],HL                   ; the operator's position
    CALL CHRGTR
    JP LOPREL

;; Pushes the left operand of ^ in single precision, then evaluates the right one.
;;
;; Continues at FINTMP, to apply FPWRQ.
;;
;; In:    FACLO = the left operand
EXPSTK:
    CALL FN_CSNG                    ; ^ works in single precision
    CALL PUSHF                      ; push it
    LD BC,FPWRQ                     ; forces the right one too, and raises
    LD D,$7F                        ; ^'s precedence
    JP FINTMP

;; Pushes the left operand of AND, OR, XOR, EQV, IMP, MOD or \ as an integer, then evaluates the right one.
;;
;; Continues at FINTMP, to apply DANDOR.
;;
;; In:    D = the operator's precedence, which tells DANDOR the operator
ANDORD:
    PUSH DE
    CALL FN_CINT                    ; HL = the integer
    POP DE
    PUSH HL
    LD BC,DANDOR
    JP FINTMP

;; Pushes the left operand of a relation and evaluates the right one, comparing them at DOCMP.
;;
;; Numbers go through APPLOP as operator 4, the comparison; strings push their descriptor for STRCMP. If the
;; pending operator binds tighter, it returns at once, the relation unapplied.
;;
;; In:    D = the relations' mask, B = the pending precedence
FINREL:
    LD A,B                          ; relations have precedence 100
    CP $64
    RET NC
    PUSH BC                         ; keep the pending precedence
    PUSH DE                         ; and the mask, for DOCMP
    LD DE,$6404                     ; D = precedence 100, E = operator 4, compare
    LD HL,DOCMP                     ; the result becomes true or false there
    PUSH HL
    CALL GETYPR
    JP NZ,NUMREL                    ; a number
    LD HL,[FACLO]                   ; a string: its descriptor
    PUSH HL
    LD BC,STRCMP
    JP FINTMP

;; Applies an arithmetic operator or a numeric comparison to the left operand on the stack and the FAC.
;;
;; Both are brought to the wider of their types first. Integer routines get the left operand in DE and the
;; right in HL; single ones the left in BC/DE and the right in the FAC; double ones the left in the FAC and
;; the right in ARG.
;;
;; The stack holds the left operand's type (B) and the operator (C) as a word, then the left operand.
;; Errors: TM for a string on the right
APPLOP:
    POP BC                          ; B = the left type, C = the operator
    LD A,C
    LD [DORES],A                    ; kept for the dispatch
    LD A,[VALTYP]
    CP B                            ; the same types?
    JP NZ,VALNSM
    CP $02
    JP Z,INTDPC
    CP $04
    JP Z,SNGDPC
    JP NC,DBLDPC

;; Converts the operand of the narrower type, for APPLOP's operands of two types.
;;
;; In:    A = the FAC's type, B = the left operand's type
;; Errors: TM for a string in the FAC
VALNSM:
    LD D,A                          ; D = the FAC's type
    LD A,B
    CP $08                          ; the left one double
    JP Z,STKDBL
    LD A,D
    CP $08                          ; the right one double
    JP Z,FACDBL
    LD A,B
    CP $04                          ; the left one single
    JP Z,STKSNG
    LD A,D
    CP $03                          ; a string on the right
    JP Z,TMERR
    JP NC,FACSNG                    ; the right one single

;; Applies an integer operator through INTDSP, with the left operand in DE and the right in HL.
;;
;; In:    C = the operator, the left operand on the stack
INTDPC:
    LD HL,INTDSP
    LD B,$00
    ADD HL,BC                       ; two bytes an entry
    ADD HL,BC
    LD C,[HL]                       ; BC = the routine
    INC HL
    LD B,[HL]
    POP DE                          ; DE = the left operand
    LD HL,[FACLO]                   ; HL = the right operand
    PUSH BC                         ; run the routine
    RET

;; Applies a double precision operator whose left operand is double, converting the FAC to double.
;;
;; The left operand is on the stack.
;; Entry: DBLDPC = the FAC already double, SNGDBL = pops a single into the FAC,
;;   SETDBL = makes the FAC double and dispatches, DODSP = dispatches through the table in HL
STKDBL:
    CALL FN_CDBL
DBLDPC:
    CALL VMOVAF                     ; the right operand to ARG
    POP HL                          ; the left one's low half into the FAC
    LD [DFAC_MID],HL
    POP HL
    LD [DFACLO],HL
SNGDBL:
    POP BC                          ; and its high half
    POP DE
    CALL MOVFR
SETDBL:
    CALL FN_CDBL                    ; the left operand double
    LD HL,DBLDSP
DODSP:
    LD A,[DORES]                    ; the operator's entry,
    RLCA                            ; two bytes each
    ADD A,L
    LD L,A
    ADC A,H
    SUB L
    LD H,A
    LD A,[HL]                       ; HL = the routine
    INC HL
    LD H,[HL]
    LD L,A
    JP [HL]

;; Applies an operator to a double FAC and an integer or single left operand, which becomes double.
;;
;; In:    B = the left operand's type, the left operand on the stack
FACDBL:
    LD A,B
    PUSH AF
    CALL VMOVAF                     ; the right operand to ARG
    POP AF
    LD [VALTYP],A                   ; the FAC takes the left one's type
    CP $04
    JP Z,SNGDBL                     ; a single
    POP HL                          ; an integer
    LD [FACLO],HL
    JP SETDBL

;; Applies an operator whose left operand is single, converting the FAC to single.
;;
;; The left operand is on the stack.
;; Entry: SNGDPC = the FAC already single, SNGDO = dispatches, with BC/DE the left operand
STKSNG:
    CALL FN_CSNG
SNGDPC:
    POP BC                          ; BC/DE = the left operand
    POP DE
SNGDO:
    LD HL,SNGDSP
    JP DODSP

;; Applies an operator to a single FAC and an integer left operand, which becomes single.
;;
;; The left operand is on the stack.
FACSNG:
    POP HL                          ; HL = the left integer
    CALL PUSHF                      ; push the right operand
    CALL CONSIH                     ; the left one single,
    CALL MOVRF                      ; into BC/DE
    POP HL                          ; the right one back into the FAC
    LD [FACHI],HL
    POP HL
    LD [FACLO],HL
    JP SNGDO

;; Divides two integers with /, in single precision, so that 1/3 is .333333 and not 0.
;;
;; In:    DE = the dividend, HL = the divisor
;; Out:   FACLO = the quotient, a single
INTDIV:
    PUSH HL
    EX DE,HL
    CALL CONSIH                     ; the dividend single,
    POP HL
    CALL PUSHF                      ; pushed
    CALL CONSIH                     ; the divisor single
    JP FDIVT

;; Evaluates one operand at HL into the FAC.
;;
;; In:    HL = the text before the operand
;; Out:   HL = the text after the operand, FACLO = the value, VALTYP = its type
;; Errors: MO if there is no operand
EVAL:
    CALL CHRGTR
    JP Z,MOERR                      ; nothing there
    JP C,FIN                        ; a digit starts a number
    CALL ISLET2                     ; a letter starts a variable
    JP NC,ISVAR
    CP $20                          ; a crunched constant
    JP C,CONFAC
    INC A                           ; $FF starts a function
    JP Z,ISFUN
    DEC A
    CP $F2                          ; + is ignored
    JP Z,EVAL
    CP $F3                          ; -
    JP Z,DOMIN
    CP '"'                          ; a string
    JP Z,STRLTI
    CP $D5                          ; NOT
    JP Z,NOTER
    CP '&'                          ; &H or &O
    JP Z,OCTCNS
    CP $D7                          ; ERR
    JP NZ,NTERC
    CALL CHRGTR
    LD A,[ERRFLG]                   ; the last error's code
    PUSH HL
    CALL SNGFLT                     ; as an integer
    POP HL
    RET

;; Evaluates ERL, the line of the last error, or tries the next kind of operand.
;;
;; In:    A = the token, HL = the text at it
;; Out:   HL = the text after the operand, FACLO = the value
NTERC:
    CP $D6                          ; ERL
    JP NZ,NTERL
    CALL CHRGTR
    PUSH HL
    LD HL,[ERRLIN]
    CALL INEG2                      ; unsigned, as a single
    POP HL
    RET

;; Evaluates VARPTR: the address of a variable, or of a file's block for VARPTR(#n).
;;
;; In:    A = the token, HL = the text at it
;; Out:   HL = the text after the operand, FACLO = the address, an integer
;; Errors: FC for a variable that does not exist yet
NTERL:
    CP $DC                          ; VARPTR
    JP NZ,NTVARP
    CALL CHRGTR
    CALL SYNCHR
    .byte '('
    CP '#'                          ; a file?
    JP NZ,NVRFIL
    CALL GTBYTC                     ; the file's number
    PUSH HL
    CALL GETPTR                     ; DE = its block
    POP HL
    JP VARRET

;; Finds VARPTR's variable, without creating it.
;;
;; Continues at VARRET with DE = its address, or 0.
;;
;; In:    HL = the text at the variable
;; Entry: VARRET = returns the address in DE
NVRFIL:
    CALL PTRGTN
VARRET:
    CALL SYNCHR
    .byte ')'
    PUSH HL
    EX DE,HL
    LD A,H                          ; zero: it does not exist
    OR L
    JP Z,FCERR
    CALL MAKINT                     ; the address as an integer
    POP HL
    RET

;; Dispatches the operands that start with a token: USR, INSTR, INKEY$, STRING$, INPUT$ and FN.
;;
;; Anything else must be an expression in parentheses.
;;
;; In:    A = the token or character, HL = the text at it
;; Out:   HL = the text after the operand, FACLO = the value
NTVARP:
    CP $D2                          ; USR
    JP Z,USRFN
    CP $DA                          ; INSTR
    JP Z,FN_INSTR
    CP $DD                          ; INKEY$
    JP Z,INKEY
    CP $D8                          ; STRING$
    JP Z,FN_STRING
    CP $85                          ; INPUT$
    JP Z,FIXINP
    CP $D3                          ; FN
    JP Z,FNDOER

;; Evaluates an expression in parentheses.
;;
;; In:    HL = the text at the opening parenthesis
;; Out:   HL = the text after the closing one, FACLO = the value, VALTYP = its type
;; Errors: SN without either parenthesis
PARCHK:
    CALL FRMPRN
    CALL SYNCHR
    .byte ')'
    RET

;; Evaluates unary minus: the operand, at a precedence above everything but ^, then negates it.
;;
;; In:    HL = the text at the minus
;; Out:   HL = the text after the operand, FACLO = the value
;; Entry: LABBCK = pops HL and returns, where the functions return
DOMIN:
    LD D,$7D                        ; below ^, above the rest
    CALL LPOPER
    LD HL,[TEMP2]
    PUSH HL
    CALL VNEG                       ; negate it
LABBCK:
    POP HL
    RET

;; Evaluates a variable: a number's value into the FAC, a string's descriptor address into FACLO.
;;
;; In:    HL = the text at the name
;; Out:   HL = the text after the name, FACLO = the value or descriptor
;; Entry: RETVAR = PTRGET's return address here, which SMKVAR (Variables.asm) tests to give a missing
;;   variable's zero or empty string rather than create it
ISVAR:
    CALL PTRGET                     ; DE = the variable
RETVAR:
    PUSH HL
    EX DE,HL
    LD [FACLO],HL                   ; a string's descriptor
    CALL GETYPR
    CALL NZ,VMOVFM                  ; a number's value
    POP HL
    RET

;; Turns a lowercase letter into a capital.
;;
;; In:    HL = the character, for MAKUPL, A = the character, for MAKUPS
;; Out:   A = the character, in capitals
;; Keeps: BC, DE, HL
;; Entry: MAKUPS = takes the character in A
MAKUPL:
    LD A,[HL]
MAKUPS:
    CP 'a'
    RET C
    CP 'z'+1
    RET NC
    AND $5F
    RET

;; Reads a line number, or an &H or &O constant.
;;
;; Nothing in MBASIC calls it: line numbers are read by LINGET itself.
;;
;; In:    A = the first character, HL = the text at it
CNSGET:
    CP '&'
    JP NZ,LINGET

;; Reads an &H hexadecimal or &O (or plain &) octal constant into the FAC as an integer.
;;
;; In:    HL = the text at the &
;; Out:   HL = the text after the constant, FACLO = the value
;; Errors: OV for more than 4 hex digits or an octal value past 65535, SN for an 8 or 9 in an octal one
OCTCNS:
    LD DE,$0000                     ; DE = the value
    CALL CHRGTR
    CALL MAKUPS
    CP 'O'
    JP Z,LOPOCT
    CP 'H'
    JP NZ,LOPOC2                    ; & alone is octal
    LD B,$05                        ; at most 4 digits

;; Reads the digits of an &H constant.
;;
;; Continues at HOCFIN.
;;
;; In:    HL = the text before the digit, DE = the value so far, B = the digits allowed, plus one
;; Errors: OV for a fifth digit
LOPHEX:
    INC HL
    LD A,[HL]
    CALL MAKUPS
    CALL ISLET2                     ; a letter?
    EX DE,HL                        ; HL = the value
    JP NC,ALPTST
    CP '9'+1                        ; not a digit: the end
    JP NC,HOCFIN
    SUB '0'
    JP C,HOCFIN
    JP NXTHEX

;; Takes a letter of an &H constant, A to F, or ends the constant at another.
;;
;; In:    A = the letter, HL = the value
ALPTST:
    CP 'F'+1
    JP NC,HOCFIN
    SUB 'A'-10

;; Adds a hex digit to the value.
;;
;; In:    A = the digit, HL = the value
NXTHEX:
    ADD HL,HL                       ; four bits up
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    OR L
    LD L,A
    EX DE,HL
    DEC B
    JP NZ,LOPHEX
    JP OVERR

;; Reads the digits of an &O constant.
;;
;; Continues at HOCFIN.
;;
;; In:    HL = the text at the digit, for LOPOC2, or before it, DE = the value so far
;; Errors: OV past 65535, SN for an 8 or a 9
;; Entry: LOPOCT = HL before the digit
LOPOC2:
    DEC HL
LOPOCT:
    CALL CHRGTR
    EX DE,HL                        ; HL = the value
    JP NC,HOCFIN                    ; not a digit: the end
    CP '8'
    JP NC,SNERR
    LD BC,OVERR                     ; a bit out of the top overflows
    PUSH BC
    ADD HL,HL                       ; three bits up
    RET C
    ADD HL,HL
    RET C
    ADD HL,HL
    RET C
    POP BC
    LD B,$00
    SUB '0'
    LD C,A
    ADD HL,BC
    EX DE,HL
    JP LOPOCT

;; Ends an &H or &O constant: the value becomes the FAC's integer.
;;
;; In:    HL = the value, DE = the text
;; Out:   HL = the text, FACLO = the value
HOCFIN:
    CALL MAKINT
    EX DE,HL
    RET

;; Calls a built-in function through FUNDSP, first evaluating its arguments.
;;
;; LEFT$, RIGHT$ and MID$ get the string's descriptor and the byte argument on the stack, and the text
;; pointer in DE, and read the rest themselves. The others get their one argument in the FAC, in single
;; precision for the functions from SQR to ATN, and return through LABBCK. RND without an argument goes to
;; RNDMON.
;;
;; In:    HL = the text at the $FF before the function's token
;; Out:   HL = the text after the function, FACLO = the value
ISFUN:
    INC HL
    LD A,[HL]                       ; the function's token
    SUB $81                         ; A = its number from 0
    CP $07                          ; RND?
    JP NZ,NTMRND
    PUSH HL
    CALL CHRGTR
    CP '('                          ; RND without an argument
    POP HL
    JP NZ,RNDMON
    LD A,$07

;; Calls the function numbered A.
;;
;; In:    A = the function's number, HL = the text at its token
;; Out:   HL = the text after the function, FACLO = the value
NTMRND:
    LD B,$00
    RLCA                            ; BC = its offset in FUNDSP
    LD C,A
    PUSH BC
    CALL CHRGTR
    LD A,C
    CP $05                          ; LEFT$, RIGHT$ or MID$?
    JP NC,OKNORM
    CALL FRMPRN                     ; the string
    CALL SYNCHR
    .byte ','
    CALL CHKSTR
    EX DE,HL
    LD HL,[FACLO]                   ; its descriptor
    EX [SP],HL                      ; under the offset
    PUSH HL
    EX DE,HL
    CALL GETBYT                     ; E = the number
    EX DE,HL                        ; DE = the text, HL = the number
    EX [SP],HL                      ; under the offset
    JP FINGO

;; Evaluates a function's argument in parentheses, in single precision where needed, and calls it.
;;
;; In:    HL = the text at the parenthesis, the function's offset on the stack
;; Out:   HL = the text after the function, FACLO = the value
OKNORM:
    CALL PARCHK
    EX [SP],HL                      ; stack the text, HL = the offset
    LD A,L
    CP $0C                          ; SGN, INT and ABS take any type
    JP C,NOTFRF
    CP $1B                          ; SQR to ATN take singles
    PUSH HL
    CALL C,FN_CSNG
    POP HL

;; Calls the function at offset HL in FUNDSP, returning through LABBCK.
;;
;; In:    HL = the offset, the text pointer on the stack
;; Entry: FINGO = calls it without returning through LABBCK
NOTFRF:
    LD DE,LABBCK                    ; restore the text pointer after
    PUSH DE
    LD A,$01                        ; one overflow message at most
    LD [FLGOVC],A
FINGO:
    LD BC,FUNDSP

;; Jumps to the address in the table at BC, entry HL.
;;
;; In:    BC = the table, HL = the entry's offset
DISPAT:
    ADD HL,BC
    LD C,[HL]
    INC HL
    LD H,[HL]
    LD L,C
    JP [HL]

;; Reads the sign of a number's exponent, for FIN.
;;
;; In:    A = the character after the E, D = the exponent's sign flag, HL = the text
;; Out:   D = one less for a minus, zero = set for a sign, else HL = the text before the character
MINPLS:
    DEC D                           ; assume minus
    CP $F3                          ; the - token
    RET Z
    CP '-'
    RET Z
    INC D                           ; plus
    CP '+'
    RET Z
    CP $F2                          ; the + token
    RET Z
    DEC HL                          ; no sign: read the digit again
    RET

;; Turns a comparison's result into -1 for true or 0 for false, by the relations written.
;;
;; Continues at RETAOP with FACLO = the integer result.
;;
;; In:    A = the comparison: 1 for less, 0 for equal, -1 for greater, the mask from DORELS on the stack
DOCMP:
    INC A                           ; 1 2 4 for > = <
    ADC A,A
    POP BC                          ; B = the mask
    AND B                           ; any match?
    ADD A,$FF                       ; carry if so
    SBC A,A                         ; -1 or 0
    CALL CONIA                      ; as an integer
    JP RETAPG

;; Evaluates NOT: its operand, at the precedence above the relations, complemented as an integer.
;;
;; Continues at RETAOP with FACLO = the result.
;;
;; In:    HL = the text at the NOT
NOTER:
    LD D,$5A                        ; precedence 90
    CALL LPOPER
    CALL FN_CINT
    LD A,L
    CPL
    LD L,A
    LD A,H
    CPL
    LD H,A
    LD [FACLO],HL
    POP BC                          ; drop EVAL's return: the text pointer is in TEMP2

;; Goes back to RETAOP, to apply the operator after the operand.
RETAPG:
    JP RETAOP

;; Sets the flags for the FAC's type.
;;
;; Out:   A = the type less 3, carry = clear for a double, zero = set for a string,
;;   negative = set for an integer
;; Keeps: BC, DE, HL
GETYPR:
    LD A,[VALTYP]
    CP $08
    JP NC,NCASE
    SUB $03                         ; -1 0 1
    OR A
    SCF                             ; carry: not a double
    RET

;; Sets the flags for a double: carry, zero and negative clear.
NCASE:
    SUB $03
    OR A
    RET

;; Applies AND, OR, XOR, EQV, IMP, MOD or \ to the integer on the stack and the FAC.
;;
;; The operator's precedence in B tells which: 40 IMP, 50 EQV, 60 XOR, 70 OR, 80 AND, 122 MOD, 123 \.
;;
;; In:    B = the precedence, the left operand on the stack
;; Out:   FACLO = the integer result
DANDOR:
    LD A,B
    PUSH AF
    CALL FN_CINT                    ; HL = the right operand
    POP AF
    POP DE                          ; DE = the left one
    CP $7A                          ; MOD
    JP Z,IMOD
    CP $7B                          ; \
    JP Z,IDIV
    LD BC,GIVINT                    ; A and L become the result
    PUSH BC
    CP $46                          ; OR?
    JP NZ,NOTOR
    LD A,E
    OR L
    LD L,A
    LD A,H
    OR D
    RET

;; Applies AND, or tries the next operator, for DANDOR.
;;
;; In:    A = the precedence, DE, HL = the operands
;; Out:   A, L = the result
NOTOR:
    CP $50                          ; AND?
    JP NZ,NOTAND
    LD A,E
    AND L
    LD L,A
    LD A,H
    AND D
    RET

;; Applies XOR, or tries the next operator, for DANDOR.
;;
;; In:    A = the precedence, DE, HL = the operands
;; Out:   A, L = the result
NOTAND:
    CP $3C                          ; XOR?
    JP NZ,NOTXOR
    LD A,E
    XOR L
    LD L,A
    LD A,H
    XOR D
    RET

;; Applies EQV, or IMP, for DANDOR.
;;
;; In:    A = the precedence, DE, HL = the operands
;; Out:   A, L = the result
NOTXOR:
    CP $32                          ; EQV?
    JP NZ,NOTEQV
    LD A,E
    XOR L
    CPL
    LD L,A
    LD A,H
    XOR D
    CPL
    RET

;; Applies IMP for DANDOR: left IMP right is NOT (left AND NOT right).
;;
;; In:    DE = the left operand, HL = the right one
;; Out:   A, L = the result
NOTEQV:
    LD A,L
    CPL
    AND E
    CPL
    LD L,A
    LD A,H
    CPL
    AND D
    CPL
    RET

;; Subtracts DE from HL and floats the result, unsigned, into the FAC.
;;
;; In:    HL, DE = the numbers
;; Out:   FACLO = HL - DE, a single
GIVDBL:
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    JP INEG2

;; Returns LPOS: the printer's column, from 1.
;;
;; Out:   FACLO = the column, an integer
FN_LPOS:
    LD A,[LPTPOS]
    JP FN_POS_1

;; Returns POS: the cursor's column, from 1.
;;
;; Out:   FACLO = the column, an integer
;; Entry: FN_POS_1 = returns A plus one
FN_POS:
    LD A,[TTYPOS]
FN_POS_1:
    INC A

;; Returns the byte in A as an integer in the FAC.
;;
;; In:    A = the byte
;; Out:   FACLO = the integer, VALTYP = 2
;; Entry: GIVINT = returns A and L as the high and low bytes
SNGFLT:
    LD L,A
    XOR A
GIVINT:
    LD H,A
    JP MAKINT

;; Calls a USR function: its routine gets the argument in the FAC and returns through POPHRT.
;;
;; The routine is entered with A = the argument's type, HL = the address of the FAC, and DE = a string
;; argument's descriptor.
;;
;; In:    HL = the text at the USR token
;; Out:   HL = the text after the function, FACLO = the value the routine leaves
USRFN:
    CALL SCNUSR                     ; DE = the USRTAB entry
    PUSH DE
    CALL PARCHK                     ; the argument
    EX [SP],HL                      ; keep the text, HL = the entry
    LD E,[HL]                       ; DE = the routine
    INC HL
    LD D,[HL]
    LD HL,POPHRT                    ; return to restore the text pointer
    PUSH HL
    PUSH DE                         ; the routine, run by the RET
    LD A,[VALTYP]
    PUSH AF
    CP $03                          ; a string's temporary is freed
    CALL Z,FREFAC
    POP AF                          ; A = the type
    EX DE,HL                        ; DE = the descriptor
    LD HL,FACLO
    RET

;; Reads the digit after USR or DEF USR and finds its entry in USRTAB.
;;
;; In:    HL = the text at the USR token
;; Out:   DE = the entry, HL = the text after the digit
;; Entry: NOARGU = the entry at offset BC
SCNUSR:
    CALL CHRGTR
    LD BC,$0000                     ; USR alone is USR0
    CP $1B                          ; a one-digit constant, $11 to $1A?
    JP NC,NOARGU
    CP $11
    JP C,NOARGU
    CALL CHRGTR
    LD A,[CONLO]                    ; its value
    OR A
    RLA                             ; two bytes an entry
    LD C,A
NOARGU:
    EX DE,HL
    LD HL,USRTAB
    ADD HL,BC
    EX DE,HL
    RET

;; Runs DEF USR: sets a USR function's address.
;;
;; In:    HL = the text at the USR token
;; Out:   HL = the end of the statement
;; Errors: SN without the equal sign
DEFUSR:
    CALL SCNUSR                     ; DE = the entry
    PUSH DE
    CALL SYNCHR
    .byte $F0                       ; the = token
    CALL FRMQNT                     ; DE = the address
    EX [SP],HL
    LD [HL],E
    INC HL
    LD [HL],D
    POP HL
    RET

;; Runs DEF: DEF USR, or DEF FN, which stores the definition's text pointer as the function's value.
;;
;; The parameters are created as variables and the formula is skipped, as DATA skips a statement.
;;
;; In:    HL = the text after DEF, A = its first character
;; Out:   HL = the end of the statement
;; Errors: ID in direct mode, SN
ST_DEF:
    CP $D2                          ; DEF USR
    JP Z,DEFUSR
    CALL GETFNM                     ; DE = the function's value
    CALL ERRDIR
    EX DE,HL
    LD [HL],E                       ; the text after the name
    INC HL
    LD [HL],D
    EX DE,HL
    LD A,[HL]
    CP '('                          ; parameters?
    JP NZ,ST_DATA
    CALL CHRGTR

;; Creates the parameters of a DEF FN, then skips the rest of the statement.
;;
;; In:    HL = the text at a parameter
SCNLIS:
    CALL PTRGET
    LD A,[HL]
    CP ')'
    JP Z,ST_DATA
    CALL SYNCHR
    .byte ','
    JP SCNLIS

;; Calls a user function: binds the arguments to its parameters and evaluates its definition.
;;
;; Each argument is evaluated in the caller's context and converted to its parameter's type, then the
;; parameters are put in a new block (PARM2), with the name of each. Once all are bound, the current block
;; (PARM1) is pushed with its PRMSTK link and PARM2 becomes PARM1, so PTRGET finds the parameters first.
;;
;; In:    HL = the text at the FN token
;; Out:   HL = the text after the call, FACLO = the value, of the function's type
;; Errors: UF for an undefined function, SN when the arguments and the parameters differ, FC when the
;;   parameter block would pass 100 bytes
FNDOER:
    CALL GETFNM                     ; DE = the function's value
    LD A,[VALTYP]                   ; its type, with carry clear
    OR A
    PUSH AF
    LD [TEMP2],HL                   ; the text after the name
    EX DE,HL
    LD A,[HL]                       ; HL = the definition's text
    INC HL
    LD H,[HL]
    LD L,A
    LD A,H                          ; zero: never defined
    OR L
    JP Z,UFERR
    LD A,[HL]
    CP '('                          ; parameters?
    JP NZ,FINVLS
    CALL CHRGTR
    LD [TEMP3],HL                   ; the parameter list
    EX DE,HL
    LD HL,[TEMP2]                   ; the arguments must follow
    CALL SYNCHR
    .byte '('
    XOR A                           ; zero marks the last value to bind
    PUSH AF
    PUSH HL
    EX DE,HL

;; Binds the next argument of an FN call: finds its parameter, evaluates the argument and keeps its value.
;;
;; In:    HL = the parameter list, the argument list on the stack
ASGMOR:
    LD A,$80                        ; no arrays
    LD [SUBFLG],A
    CALL PTRGET                     ; DE = the parameter
    EX DE,HL
    EX [SP],HL                      ; stack it, HL = the argument
    LD A,[VALTYP]                   ; the parameter's type
    PUSH AF
    PUSH DE
    CALL FRMEVL                     ; the argument
    LD [TEMP2],HL
    POP HL
    LD [TEMP3],HL
    POP AF
    CALL DOCNVF                     ; to the parameter's type
    LD C,$04
    CALL GETSTK                     ; room for 8 bytes
    LD HL,$FFF8                     ; -8: the value goes on the stack
    ADD HL,SP
    LD SP,HL
    CALL VMOVMF
    LD A,[VALTYP]
    PUSH AF
    LD HL,[TEMP2]
    LD A,[HL]
    CP ')'                          ; the last argument
    JP Z,POPASG
    CALL SYNCHR
    .byte ','
    PUSH HL
    LD HL,[TEMP3]
    CALL SYNCHR                     ; then another parameter too
    .byte ','
    JP ASGMOR

;; Notes the parameter just bound in PARM2's length, then binds the next value on the stack.
;;
;; The new length is on the stack.
;; Entry: POPASG = binds the next value
POPAS2:
    POP AF
    LD [PRMLN2],A

;; Binds the values on the stack to their parameters in PARM2, from the last, until the zero type.
;;
;; The stack holds each value's type, the value in 8 bytes, then its parameter.
POPASG:
    POP AF                          ; the type
    OR A
    JP Z,FINASG                     ; zero: all bound
    LD [VALTYP],A
    LD HL,$0000
    ADD HL,SP
    CALL VMOVFM                     ; the value into the FAC
    LD HL,$0008
    ADD HL,SP
    LD SP,HL
    POP DE                          ; DE = the parameter
    LD L,$03                        ; L = the name's size

;; Counts the bytes of a parameter's name, back from its value, to copy the entry into PARM2.
;;
;; In:    DE = the parameter's value, L = the size so far
LPSIZL:
    INC L
    DEC DE
    LD A,[DE]
    OR A                            ; bit 7 set: still the name
    JP M,LPSIZL
    DEC DE                          ; back over the type and length
    DEC DE
    DEC DE
    LD A,[VALTYP]
    ADD A,L                         ; B = the entry's size
    LD B,A
    LD A,[PRMLN2]
    LD C,A                          ; C = PARM2's length
    ADD A,B
    CP $64                          ; at most 100 bytes
    JP NC,FCERR
    PUSH AF                         ; the new length
    LD A,L
    LD B,$00
    LD HL,PARM2
    ADD HL,BC                       ; HL = its end
    LD C,A
    CALL BCTRAN                     ; copy the name
    LD BC,POPAS2
    PUSH BC
    PUSH BC
    JP LETCN4                       ; assign the value there

;; Checks that the arguments and the parameters ended together, then evaluates the function.
;;
;; In:    TEMP2 = the argument list, TEMP3 = the parameter list
FINASG:
    LD HL,[TEMP2]
    CALL CHRGTR                     ; past the )
    PUSH HL
    LD HL,[TEMP3]
    CALL SYNCHR
    .byte ')'
    .byte $3E                       ; LD A,$D5: skip the PUSH DE

;; Makes PARM2 the active parameter block, evaluates the definition, and restores the caller's block.
;;
;; A string result in a parameter's space is copied to a temporary first, as the block will be overwritten.
;;
;; In:    HL = the definition's text, at the equal sign, the caller's text in DE
;; Errors: SN if the definition does not end after its formula
FINVLS:
    PUSH DE                         ; the caller's text
    LD [TEMP3],HL                   ; the definition's
    LD A,[PRMLEN]                   ; PARM1 and its 4 bytes of header
    ADD A,$04
    PUSH AF
    RRCA
    LD C,A
    CALL GETSTK                     ; room on the stack
    POP AF
    LD C,A
    CPL                             ; HL = SP less the size
    INC A
    LD L,A
    LD H,$FF
    ADD HL,SP
    LD SP,HL
    PUSH HL
    LD DE,PRMSTK                    ; push PRMSTK, PRMLEN and PARM1
    CALL BCTRAN
    POP HL
    LD [PRMSTK],HL                  ; link to them
    LD HL,[PRMLN2]                  ; PARM2 becomes PARM1
    LD [PRMLEN],HL
    LD B,H
    LD C,L
    LD HL,PARM1
    LD DE,PARM2
    CALL BCTRAN
    LD H,A                          ; PARM2 empty
    LD L,A
    LD [PRMLN2],HL
    LD HL,[FUNACT]                  ; one more function active
    INC HL
    LD [FUNACT],HL
    LD A,H
    OR L
    LD [NOFUNS],A
    LD HL,[TEMP3]
    CALL FRMEQL                     ; the definition
    DEC HL
    CALL CHRGTR                     ; which must end there
    JP NZ,SNERR
    CALL GETYPR
    JP NZ,NOCPRS                    ; a number
    LD DE,DSCTMP                    ; a string in a temporary is safe
    LD HL,[FACLO]
    CALL DCOMPR
    JP C,NOCPRS
    CALL STRCPY                     ; else copy it
    CALL PUTTMP

;; Restores the caller's parameter block from the stack, then converts the result to the function's type.
;;
;; In:    PRMSTK = the saved block, the caller's text and the function's type above it on the stack
NOCPRS:
    LD HL,[PRMSTK]                  ; the saved block
    LD D,H
    LD E,L
    INC HL
    INC HL
    LD C,[HL]                       ; BC = its length and header
    INC HL
    LD B,[HL]
    INC BC
    INC BC
    INC BC
    INC BC
    LD HL,PRMSTK                    ; back into PRMSTK and on
    CALL BCTRAN
    EX DE,HL                        ; drop it from the stack
    LD SP,HL
    LD HL,[FUNACT]                  ; one function less
    DEC HL
    LD [FUNACT],HL
    LD A,H
    OR L
    LD [NOFUNS],A
    POP HL                          ; the caller's text
    POP AF                          ; the function's type

;; Converts the FAC to the type in A through FRCTBL.
;;
;; In:    A = the type
;; Out:   FACLO = the value, of that type
;; Errors: TM for a string to a number or a number to a string
;; Keeps: HL
DOCNVF:
    PUSH HL
    AND $07                         ; 8 becomes 0
    LD HL,FRCTBL
    LD C,A
    LD B,$00
    ADD HL,BC
    CALL DISPAT
    POP HL
    RET

;; Copies BC bytes from DE to HL, forward.
;;
;; In:    DE = the source, HL = the destination, BC = the count
;; Out:   DE, HL = past the bytes, BC = 0, A = 0
;; Entry: BCTRAN = checks the count first
BCTRAL:
    LD A,[DE]
    LD [HL],A
    INC HL
    INC DE
    DEC BC
BCTRAN:
    LD A,B
    OR C
    JP NZ,BCTRAL
    RET

;; Gives an ID error in direct mode.
;;
;; Keeps: BC, DE, HL
;; Errors: ID
ERRDIR:
    PUSH HL
    LD HL,[CURLIN]                  ; direct mode is line 65535
    INC HL
    LD A,H
    OR L
    POP HL
    RET NZ
    LD E,$0C                        ; Illegal direct
    JP ERROR

;; Requires FN, then finds the function's variable: its name with bit 7 set in the first letter.
;;
;; In:    HL = the text at the FN token
;; Out:   DE = the function's value, HL = the text after the name, VALTYP = its type
;; Errors: SN without FN
GETFNM:
    CALL SYNCHR
    .byte $D3                       ; the FN token
    LD A,$80                        ; no arrays
    LD [SUBFLG],A
    OR [HL]                         ; C = the first letter, bit 7 set
    LD C,A
    JP PTRGT2

;; Runs MID$ on the left of an assignment, the one function allowed there.
;;
;; In:    A = the token less $81, $7E for a function, HL = the text at it
;; Errors: SN for anything but MID$
ISMID:
    CP $7E                          ; a function?
    JP NZ,SNERR
    INC HL
    LD A,[HL]
    INC HL
    CP $83                          ; MID$
    JP Z,LHSMID
    JP SNERR

;; Returns INP: the byte read from a port.
;;
;; In:    FACLO = the port
;; Out:   FACLO = the byte, an integer
;; Errors: FC for a port past 255
FN_INP:
    CALL CONINT
    LD [INPORT],A                   ; into the IN below
INPORT = * + 1                      ;; FN_INP's port: the operand of its IN, which it sets
    IN A,[$00]
    JP SNGFLT

;; Runs OUT: writes a byte to a port.
;;
;; In:    HL = the text after OUT
;; Out:   HL = the end of the statement
;; Errors: FC for a port or byte past 255
ST_OUT:
    CALL SETIO                      ; A = the byte, the port set below
OUTPRT = * + 1                      ;; OUT's port: the operand of its OUT, which SETIO sets
    OUT [$00],A
    RET

;; Runs WAIT: waits until a port's byte, XORed with the third value and ANDed with the second, is not zero.
;;
;; In:    HL = the text after WAIT
;; Out:   HL = the end of the statement
;; Errors: FC for a value past 255
ST_WAIT:
    CALL SETIO                      ; A = the AND mask, the port set below
    PUSH AF
    LD E,$00                        ; the XOR mask is 0 if not given
    DEC HL
    CALL CHRGTR
    JP Z,NOTTHR
    CALL SYNCHR
    .byte ','
    CALL GETBYT                     ; E = the XOR mask

;; Waits on WAIT's port with the masks.
;;
;; In:    E = the XOR mask, the AND mask on the stack
;; Entry: LOPINP = the loop, with D the AND mask
NOTTHR:
    POP AF
    LD D,A                          ; D = the AND mask
LOPINP:
WAITPT = * + 1                      ;; WAIT's port: the operand of its IN, which SETIO sets
    IN A,[$00]
    XOR E
    AND D
    JP Z,LOPINP                     ; Ctrl+C cannot stop it
    RET

;; Gives a syntax error, for the CONSOLE statement of other versions; nothing jumps here.
CONSOL:
    JP SNERR

;; Runs WIDTH: sets the console's or, for WIDTH LPRINT, the printer's line width.
;;
;; The last print zone's column is set too, for PRINT's commas.
;;
;; In:    HL = the text after WIDTH, A = its first character
;; Out:   HL = the end of the statement
;; Errors: FC for a width past 255
;; Entry: ST_WIDTH_1 = sets the console's width
ST_WIDTH:
    CP $9E                          ; LPRINT
    JP NZ,ST_WIDTH_1
    CALL CHRGTR
    CALL GETBYT
    LD [LPTSIZ],A                   ; the printer's width
    LD E,A
    CALL CLMCAL
    LD [NLPPOS],A                   ; its last zone
    RET
ST_WIDTH_1:
    CALL GETBYT
    LD [LINLEN],A                   ; the console's width
    LD E,A
    CALL CLMCAL
    LD [CLMLST],A                   ; its last zone
    RET

;; Works out the column of the last 14-column print zone a line of a given width can start a comma's item in.
;;
;; In:    A, E = the width
;; Out:   A = the width less its remainder by 14, less 14
CLMCAL:
    SUB 14                          ; the remainder by 14, less 14
    JP NC,CLMCAL
    ADD A,28                        ; the remainder plus 14
    CPL                             ; negated
    INC A
    ADD A,E
    RET

;; Evaluates the expression after the next character as an integer.
;;
;; In:    HL = the text, at the character before the expression's
;; Out:   DE = the integer, HL = the text after it, A = D, zero = set if it is 0-255,
;;   negative = set if it is negative
;; Errors: OV past the integer range
;; Entry: GETIN2 = HL before the expression, INTFR2 = the value is in the FAC
GETINT:
    CALL CHRGTR
GETIN2:
    CALL FRMEVL
INTFR2:
    PUSH HL
    CALL FN_CINT                    ; HL = the integer
    EX DE,HL
    POP HL
    LD A,D                          ; flags for the high byte
    OR A
    RET

;; Reads OUT's or WAIT's port and first value, setting the port in both their instructions.
;;
;; In:    HL = the text at the port
;; Out:   A, E = the value, HL = the text after it
;; Errors: SN without the comma, FC for a value past 255
SETIO:
    CALL GETBYT                     ; the port
    LD [WAITPT],A
    LD [OUTPRT],A
    CALL SYNCHR
    .byte ','
    JP GETBYT

;; Evaluates the expression after the next character as a byte.
;;
;; In:    HL = the text, at the character before the expression's
;; Out:   A, E = the byte, HL = the text after it, zero = set at the end of the statement
;; Errors: FC past 255
;; Entry: GETBYT = HL before the expression, CONINT = the value is in the FAC
GTBYTC:
    CALL CHRGTR
GETBYT:
    CALL FRMEVL
CONINT:
    CALL INTFR2
    JP NZ,FCERR                     ; past 255
    DEC HL                          ; flags for the character after it
    CALL CHRGTR
    LD A,E
    RET
