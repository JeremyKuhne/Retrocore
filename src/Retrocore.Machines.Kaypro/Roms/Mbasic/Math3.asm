;; MBASIC 5.21: MATH PACKAGE, PART 3: NUMBER OUTPUT AND THE TRANSCENDENTAL FUNCTIONS
;;
;; The end of the math package: turning numbers into text, then the power operator and the functions built on
;; polynomials. GW-BASIC's MATH1.ASM and MATH2.ASM hold the same routines rewritten for the 8086 ($FOUT, $PUFOT,
;; $FOUTH, $SIN and the rest), with BIPRTU.ASM's PRINT USING driving the formatted output. The code itself is
;; Microsoft's Z80 math package as in the TRS-80's Level II BASIC (Level2.asm), routine for routine, so the names
;; are Level II's; MBASIC adds octal and hex output, the overflow handling of ^, a new EXP, SIN and RND, and
;; fixed notation for small numbers.
;;
;; - Number output. FOUT converts the floating accumulator, of any numeric type, into text in FBUFFR and returns
;;   HL at it; LINPRT prints a line number with it, and INPRT, which falls into it, prints " in " first. PUFOUT is the PRINT USING entry (Console.asm), taking the
;;   format's flags in A and its field sizes in BC: FOUTFX lays out a fixed field and FOUBE1 makes the number
;;   fit, marking with % one that does not. FOUTNV scales a single or double value into the 6 or 16 digit range
;;   by powers of ten, FOUTCV, FOUTCS and FOUTCI write the digits by subtracting powers of ten from FODTBL,
;;   FOSTBL and FOITBL, and FOUTED inserts the decimal point and the commas as they fall due. FOUFRV is MBASIC's:
;;   it prints a small number such as 1E-06 as .000001 when the fixed form is no longer.
;; - FOUTO and FOUTH convert an integer into octal or hex digits for OCT$ and HEX$ (Strings.asm).
;; - The power operator (FPWRQ, through the operator table) and SQR raise a number to a power as
;;   EXP(power * LOG(base)). EXP, SIN, COS, TAN and ATN reduce their argument and evaluate a polynomial with
;;   POLY or POLYX, whose coefficient tables follow each function. RND steps a seed through tables of multipliers
;;   and addends.
;;
;; $3112-$397C. Its main entry points are LINPRT, FOUT, PUFOUT, FOUTO, FOUTH, the FN_ handlers in FUNDSP
;; (Tables.asm), FPWRQ, RNDMON for RND without an argument (Evaluator.asm) and POLY, which LOG uses (Math1.asm).

;; Prints " in " and then the line number in HL, as in "Break in 100".
;;
;; In:    HL = the line number
INPRT:
    PUSH HL
    LD HL,INTXT
    CALL STROUT
    POP HL

;; Prints the integer in HL as a decimal number, without a leading space.
;;
;; INPRT, just above, prints " in " and falls in here.
;;
;; In:    HL = the number, printed as a signed integer
;; Uses:  all
LINPRT:
    LD BC,STROUI                    ; return through STROUI, which prints the text after the sign position
    PUSH BC
    CALL MAKINT                     ; the FAC = HL as an integer
    XOR A                           ; A = 0: free format
    CALL FOUINI
    OR [HL]                         ; force NZ so the value is not treated as zero
    JP FOUT2

;; Converts the floating accumulator to text in free format, returning its address in HL.
;;
;; A positive number starts with a space, a negative one with -. Single and double precision use E or D notation
;; when the number is too large or too small for its digits: see <FOUFRV>.
;;
;; In:    FAC = the number, VALTYP = its type
;; Out:   HL = the text in FBUFFR, its sign first, ending in a zero byte
;; Uses:  all
FOUT:
    XOR A                           ; A = 0: no PRINT USING flags

;; Converts the floating accumulator to text under PRINT USING's format flags.
;;
;; In:
;;   A       = the flags: bit 7 = a PRINT USING field, bit 6 = commas, bit 5 = leading asterisks, bit 4 = a
;;             leading $, bit 3 = a + on positive numbers, bit 2 = the sign after the number, bit 0 = exponential
;;             notation (^^^^)
;;   B       = the field's digits before the decimal point, C = the places after it, counting the point
;;   FAC = the number, VALTYP = its type
;; Out:   HL = the text in FBUFFR, ending in a zero byte
;; Uses:  all
PUFOUT:
    CALL FOUINI
    AND $08                         ; bit 3 asks for a + sign on positive numbers
    JP Z,FOUT1
    LD [HL],'+'                     ; the + replaces the leading space

;; Puts the sign in the sign position at HL and makes the accumulator positive, continuing at <FOUT2>.
FOUT1:
    EX DE,HL                        ; DE keeps the buffer pointer while the sign is tested
    CALL VSIGN
    EX DE,HL
    JP P,FOUT2
    LD [HL],'-'                     ; negative: put a - in the sign position
    PUSH BC
    PUSH HL
    CALL VNEG                       ; print the magnitude, the sign is already stored
    POP HL
    POP BC
    OR H                            ; force NZ so FOUT2 does not treat the value as zero

;; Writes the accumulator's digits after the sign at HL, dispatching on the type and the format.
;;
;; In:    HL = the sign position, zero = set if the value is zero
FOUT2:
    INC HL
    LD [HL],'0'                     ; the text for zero is a single 0
    LD A,[TEMP3]                    ; A = the PRINT USING format flags
    LD D,A
    RLA                             ; bit 7 set means a PRINT USING field
    LD A,[VALTYP]                   ; A = the value's type: 2 integer, 4 single, 8 double
    JP C,FOUTFX                     ; PRINT USING: format into a fixed field
    JP Z,FOUTZR                     ; zero: the 0 already stored is the number
    CP $04
    JP NC,FOUFRV                    ; single and double take the floating-point path
    LD BC,$0000                     ; B = 0 and C = 0: no decimal point and no commas
    CALL FOUTCI

;; Blanks (or star-fills) the leading zeros and commas, adding $ and the sign as the format asks.
;;
;; In:    FBUFFR+1 = the formatted number, TEMP3 = the format flags
;; Out:   HL = the number's first character, B = its sign character, zero = clear if the sign goes after
;;        the number (bit 2)
;; Uses:  A, C, E
FOUTZS:
    LD HL,FBUFFR+1                  ; the sign position
    LD B,[HL]                       ; B = the sign character, kept for later
    LD C,' '                        ; C = the fill for leading zeros, normally a space
    LD A,[TEMP3]
    LD E,A
    AND $20                         ; bit 5 asks for leading asterisks
    JP Z,FOTZS1
    LD A,B
    CP C                            ; a space in the sign position means a positive number
    LD C,'*'                        ; fill with * instead of spaces
    JP NZ,FOTZS1                    ; leave a - or + sign as it is
    LD A,E
    AND $04                         ; a sign after the number stays a space
    JP NZ,FOTZS1
    LD B,C                          ; a positive number gets a * in its sign position too

FOTZS1:
    LD [HL],C                       ; blank out the sign position or a leading zero
    CALL CHRGTR
    JP Z,FOTZS4                     ; end of the text: put a single zero back
    CP 'E'                          ; an exponent marker: the number is all zeros, keep one 0
    JP Z,FOTZS4
    CP 'D'
    JP Z,FOTZS4
    CP '0'                          ; keep blanking leading zeros
    JP Z,FOTZS1
    CP ','                          ; and leading commas
    JP Z,FOTZS1
    CP '.'                          ; a decimal point: keep one 0 before it
    JP NZ,FOTZS2

FOTZS4:
    DEC HL                          ; step back to the last blanked position
    LD [HL],'0'                     ; put a 0 there so the number is not empty

FOTZS2:
    LD A,E
    AND $10                         ; bit 4 asks for a leading $
    JP Z,FOTZS3
    DEC HL
    LD [HL],'$'                     ; the $ goes just before the first digit

FOTZS3:
    LD A,E
    AND $04                         ; bit 2 puts the sign after the number
    RET NZ                          ; the caller appends it
    DEC HL
    LD [HL],B                       ; the sign goes just before the first digit
    RET

;; Stores the format flags and puts a space, the sign of a positive number, at FBUFFR+1.
;;
;; In:    A = the format flags
;; Out:   HL = FBUFFR+1, TEMP3 = the flags
;; Keeps: A, BC, DE
FOUINI:
    LD [TEMP3],A                    ; remember the format flags for the conversion
    LD HL,FBUFFR+1
    LD [HL],' '
    RET

;; Formats a single- or double-precision accumulator in free format, in fixed notation when that needs no more
;; digits than E or D notation.
;;
;; MBASIC's addition to Level II's routine (<FOUFRF>). It formats the number once and reads the result back: a
;; number written with a negative exponent whose digits, with the zeros the fixed form adds after the point, come
;; to 7 or fewer (16 or fewer in double precision) is formatted again with FOUFIX set, which keeps it in fixed
;; notation. So 1E-06 prints as .000001. The accumulator, which the scaling changes, is saved and put back.
;;
;; In:    A = VALTYP, 4 or 8, HL = FBUFFR+2, where the digits start
;; Out:   HL = the text at FBUFFR+1, ending in a zero byte
;; Uses:  all
FOUFRV:
    CALL PUSHF                      ; save the single-precision part of the FAC
    EX DE,HL
    LD HL,[DFACLO]                  ; and the double-precision low bytes
    PUSH HL
    LD HL,[DFAC_MID]
    PUSH HL
    EX DE,HL
    PUSH AF                         ; save the type
    XOR A
    LD [FOUFIX],A                   ; free choice of notation
    POP AF
    PUSH AF
    CALL FOUFRF
    LD B,'E'                        ; look for an E exponent, then a D
    LD C,$00                        ; C counts the digits before it

FOUFRV_1:
    PUSH HL
    LD A,[HL]

FOUFRV_2:
    CP B
    JP Z,FOUFRV_5                   ; the exponent letter: read the exponent
    CP '9'+1
    JP NC,FOUFRV_3
    CP '0'
    JP C,FOUFRV_3
    INC C                           ; count a digit

FOUFRV_3:
    INC HL
    LD A,[HL]
    OR A
    JP NZ,FOUFRV_2                  ; until the end of the text
    LD A,'D'
    CP B
    LD B,A
    POP HL
    LD C,$00
    JP NZ,FOUFRV_1                  ; no E: look for a D

; Not in E or D notation, or best left in it: put the accumulator back and return the text as it is.
FOUFRV_4:
    POP AF
    POP BC                          ; BC/DE = the saved double-precision low bytes
    POP DE
    EX DE,HL
    LD [DFACLO],HL
    LD H,B
    LD L,C
    LD [DFAC_MID],HL
    EX DE,HL                        ; HL = the text again
    POP BC                          ; drop the saved single-precision part
    POP DE
    RET

; The exponent letter in B, the digit count in C: read the exponent into B.
FOUFRV_5:
    PUSH BC
    LD B,$00                        ; B = the exponent
    INC HL
    LD A,[HL]

FOUFRV_6:
    CP '+'
    JP Z,FOUFRV_10                  ; a positive exponent stays in E or D notation
    CP '-'
    JP Z,FOUFRV_7
    SUB '0'
    LD C,A
    LD A,B
    ADD A,A                         ; B = B times 10 plus the digit
    ADD A,A
    ADD A,B
    ADD A,A
    ADD A,C
    LD B,A
    CP $10
    JP NC,FOUFRV_10                 ; so does an exponent of 16 or more

FOUFRV_7:
    INC HL
    LD A,[HL]
    OR A
    JP NZ,FOUFRV_6
    LD H,B                          ; H = the exponent
    POP BC                          ; B = the exponent letter, C = the digit count
    LD A,B
    CP 'E'
    JP NZ,FOUFRV_9
    LD A,C
    ADD A,H                         ; the digits after the point, plus one
    CP $09
    POP HL
    JP NC,FOUFRV_4                  ; more than 7: keep E notation

FOUFRV_8:
    LD A,$80
    LD [FOUFIX],A                   ; format again in fixed notation
    JP FOUFRV_11

FOUFRV_9:
    LD A,H
    ADD A,C
    CP $12                          ; more than 16 digits: keep D notation
    POP HL
    JP NC,FOUFRV_4
    JP FOUFRV_8

FOUFRV_10:
    POP BC
    POP HL
    JP FOUFRV_4

FOUFRV_11:
    POP AF                          ; A = the type
    POP BC
    POP DE
    EX DE,HL
    LD [DFACLO],HL                  ; put the double-precision low bytes back
    LD H,B
    LD L,C
    LD [DFAC_MID],HL
    EX DE,HL
    POP BC
    POP DE
    CALL MOVFR                      ; and the single-precision part
    INC HL                          ; HL = FBUFFR+2, where the digits start

;; Formats a single- or double-precision accumulator in free format, choosing fixed or E/D notation.
;;
;; In:    A = VALTYP, 4 or 8, HL = where the digits start, FOUFIX = bit 7 set to force fixed notation
;; Out:   HL = the text at FBUFFR+1, ending in a zero byte, DE = its end
;; Uses:  all
FOUFRF:
    CP $05                          ; carry if single precision
    PUSH HL
    SBC A,$00
    RLA
    LD D,A
    INC D                           ; D = 7 for single precision, 17 for double
    CALL FOUTNV                     ; scale to the digit range, A = the powers of ten applied
    LD BC,$0300                     ; B = 3: in E notation the point follows the first digit; C = 0: no commas
    PUSH AF
    LD A,[FOUFIX]
    OR A
    JP P,FOUFRF_1
    POP AF                          ; forced fixed notation, however small
    ADD A,D
    JP FOUFRF_2

FOUFRF_1:
    POP AF
    ADD A,D                         ; A = the digits before the decimal point, plus one
    JP M,FOFRS1                     ; too small to print without an exponent
    INC D
    CP D
    JP NC,FOFRS1                    ; too large: use E or D notation

FOUFRF_2:
    INC A                           ; fixed notation: B = the digits before the decimal point
    LD B,A
    LD A,$02                        ; so that the exponent computed next is zero

FOFRS1:
    SUB $02                         ; A = the exponent to print, zero for fixed notation
    POP HL
    PUSH AF                         ; save the exponent for after the digits
    CALL FOUTDZ                     ; the point and leading zeros of a number below 1 in fixed notation
    LD [HL],'0'                     ; a leading 0
    CALL Z,INXHRT                   ; kept only when the decimal point comes first
    CALL FOUTCV

;; Strips the trailing zeros and a bare decimal point from the formatted number, then adds any exponent.
FOFRS2:
    DEC HL                          ; back up over a trailing zero
    LD A,[HL]
    CP '0'
    JP Z,FOFRS2
    CP '.'                          ; a bare trailing decimal point goes too
    CALL NZ,INXHRT
    POP AF                          ; A = the exponent to print
    JP Z,FOUTDN                     ; zero: fixed notation, just end the text

;; Writes an E or D exponent with its sign and two digits at HL, then ends the text.
;;
;; In:    A = the power of ten, HL = where it goes, VALTYP = the type, which picks E or D
;; Out:   HL = FBUFFR+1, DE = the end of the text
;; Uses:  A, B
FOFLDN:
    PUSH AF
    CALL GETYPR                     ; carry is clear for double, set for single
    LD A,$22                        ; $22 doubled is D, plus the carry E
    ADC A,A
    LD [HL],A
    INC HL
    POP AF
    LD [HL],'+'                     ; assume a positive exponent
    JP P,FOUCE1
    LD [HL],'-'
    CPL                             ; make the exponent positive
    INC A

FOUCE1:
    LD B,'0'-1

FOUCE2:
    INC B                           ; B = the tens digit
    SUB $0A
    JP NC,FOUCE2                    ; subtract tens until the exponent goes negative
    ADD A,'0'+10                    ; undo the extra subtract: the units digit
    INC HL
    LD [HL],B
    INC HL
    LD [HL],A

FOUTZR:
    INC HL

;; Ends the formatted text at HL with a zero byte and returns its start.
;;
;; In:    HL = the end of the text
;; Out:   HL = FBUFFR+1, DE = the end of the text
FOUTDN:
    LD [HL],$00
    EX DE,HL                        ; DE = the end of the text
    LD HL,FBUFFR+1
    RET

;; Formats the accumulator into a PRINT USING field.
;;
;; In:    A = VALTYP, D = the format flags (as <PUFOUT>), HL = FBUFFR+2, BC = the field sizes (as <PUFOUT>)
;; Out:   HL = the field in FBUFFR, ending in a zero byte
;; Uses:  all
FOUTFX:
    INC HL
    PUSH BC                         ; save the field sizes
    CP $04
    LD A,D                          ; A = the format flags
    JP NC,FOUFXV                    ; single and double precision
    RRA                             ; bit 0 asks for exponential notation
    JP C,FFXIFL                     ; an integer with ^^^^: convert it to single precision
    LD BC,$0603                     ; B = 6 digits, C = 3 digits per comma group, if commas are wanted
    CALL FOUICC
    POP DE                          ; D = the digits wanted before the decimal point, E = the places after
    LD A,D
    SUB $05                         ; an integer has at most 5 digits
    CALL P,FOTZER                   ; a wider field: pad with leading zeros
    CALL FOUTCI

;; Writes the zeros after the decimal point of a fixed field, then finishes at <FOUTTS>.
;;
;; In:    E = the places after the decimal point, counting the point, HL = the end of the digits
FOUTTD:
    LD A,E
    OR A
    CALL Z,DCXHRT                   ; no places after the point: drop the decimal point
    DEC A                           ; one place is the point itself
    CALL P,FOTZER                   ; an integer has no fraction: the rest are zeros

;; Finishes a fixed field: adds a trailing sign, tidies the leading characters, and makes the number fit.
;;
;; In:    D = the digits wanted before the decimal point, HL = the end of the text, TEMP2 = the decimal point
;; Out:   HL = the field's start
FOUTTS:
    PUSH HL
    CALL FOUTZS                     ; blank the leading zeros, add $ and the sign
    POP HL
    JP Z,FFXIX1                     ; the sign was placed in front
    LD [HL],B                       ; append the sign after the digits
    INC HL

FFXIX1:
    LD [HL],$00                     ; end the text
    LD HL,FBUFFR                    ; one byte early: FOUBE1 steps onto the start

;; Drops leading zeros until the number fits the digits wanted before the point, or marks it with % if it can't.
;;
;; In:    D = the digits wanted before the decimal point, HL = the character before the field
;; Out:   HL = the field's start
FOUBE1:
    INC HL

FOUBE5:
    LD A,[TEMP2]                    ; A = the low byte of where the decimal point is
    SUB L
    SUB D                           ; zero when the digits exactly fill the space before the point
    RET Z
    LD A,[HL]
    CP ' '                          ; skip leading blanks to the first real character
    JP Z,FOUBE1
    CP '*'                          ; leading asterisks are blanks too
    JP Z,FOUBE1
    DEC HL                          ; HL = the start of the field
    PUSH HL

; Saves each character before the zero to be dropped: the first tagged NZ, then a sign or $ tagged Z.
FOUBE2:
    PUSH AF
    LD BC,FOUBE2                    ; a sign or $ returns here, to be saved as well
    PUSH BC
    CALL CHRGTR
    CP '-'
    RET Z
    CP '+'
    RET Z
    CP '$'
    RET Z
    POP BC                          ; discard the return to FOUBE2
    CP '0'                          ; only a leading 0 can be dropped to make room
    JP NZ,FOUBE4
    INC HL                          ; look past the 0 and the character after it
    CALL CHRGTR
    JP NC,FOUBE4                    ; no digit after the decimal point: the 0 stays
    DEC HL
    .byte $01                       ; LD BC,nnnn skips the next two bytes, landing on the POP

; Moves the saved characters back one place over the dropped zero, then checks again at FOUBE5.
FOUBE3:
    DEC HL
    LD [HL],A                       ; one saved character, one place to the right
    POP AF                          ; zero tags the saved signs, NZ the first character
    JP Z,FOUBE3
    POP BC                          ; discard the saved field start
    JP FOUBE5                       ; rescan in case the number now fits

; The number doesn't fit: drop the saved characters and put a % before the field.
FOUBE4:
    POP AF
    JP Z,FOUBE4
    POP HL                          ; HL = the start of the field
    LD [HL],'%'
    RET

;; Formats a single or double value into a PRINT USING field, choosing exponential or fixed-point layout.
;;
;; In:    A = the format flags, zero = set if single precision, HL = the first digit's position,
;;        SP = at the field sizes
;; Out:   HL = the field in FBUFFR, ending in a zero byte
;; Uses:  all
FOUFXV:
    PUSH HL
    RRA                             ; bit 0 asks for exponential notation
    JP C,FFXFLV
    JP Z,FFXSFX                     ; single precision
    LD DE,FFXDXM                    ; 1E16 in double precision
    CALL DCOMPD
    LD D,$10                        ; D = 16 digits of double precision
    JP M,FFXSDC                     ; below 1E16 fits a fixed field

;; Formats a value too large for fixed point in free format with <FOUT>, preceded by a %.
FFXSDO:
    POP HL
    POP BC                          ; discard the field sizes
    CALL FOUT
    DEC HL                          ; step back before the text for the %
    LD [HL],'%'
    RET

;; Formats a single-precision value in fixed point, falling back to % and free format at 1E16 or more.
FFXSFX:
    LD BC,$B60E                     ; BC/DE = 1E16 in single precision
    LD DE,$1BCA
    CALL FCOMP
    JP P,FFXSDO                     ; too big for a fixed field
    LD D,$06                        ; D = 6 digits of single precision

;; Formats a single or double value in fixed point with D significant digits, padding with zeros and
;; finishing at <FOUTTD>.
FFXSDC:
    CALL SIGN
    CALL NZ,FOUTNV                  ; scale a nonzero value, A = the powers of ten applied
    POP HL
    POP BC
    JP M,FFXXVS                     ; scaled up: the value has digits after the point
    PUSH BC
    LD E,A                          ; E = the powers of ten divided out, trailing zeros to add
    LD A,B
    SUB D                           ; A = the leading zeros the field needs
    SUB E
    CALL P,FOTZER
    CALL FOUTCD                     ; set up the point and comma counters
    CALL FOUTCV                     ; write the significant digits
    OR E                            ; the powers of ten divided out come back as zeros
    CALL NZ,FOTZEC
    OR E
    CALL NZ,FOUTED
    POP DE                          ; D = the digits before the point, E = the places after
    JP FOUTTD

;; Formats a fixed-point value that has digits after the decimal point, dropping the digits that don't fit.
FFXXVS:
    LD E,A                          ; E = the powers of ten multiplied in, a negative count
    LD A,C                          ; A = the places wanted after the decimal point
    OR A
    CALL NZ,DCRART                  ; one of them is the point itself
    ADD A,E                         ; A = the digits that won't fit and must go
    JP M,FFXXV8
    XOR A                           ; nothing to drop

FFXXV8:
    PUSH BC
    PUSH AF

FFXXV2:
    CALL M,FINDIV                   ; divide by ten once per digit to drop
    JP M,FFXXV2
    POP BC
    LD A,E
    SUB B                           ; E = the scale left after the digits dropped
    POP BC
    LD E,A
    ADD A,D
    LD A,B
    JP M,FFXXV3                     ; negative: no digits before the decimal point
    SUB D                           ; A = the leading zeros the field needs
    SUB E
    CALL P,FOTZER
    PUSH BC
    CALL FOUTCD
    JP FFXXV6

; No digits before the point: zeros, the point, more zeros, then the digits.
FFXXV3:
    CALL FOTZER
    LD A,C                          ; A = the places wanted after the decimal point
    CALL FOUTDP
    LD C,A
    XOR A
    SUB D                           ; A = the zeros between the point and the first digit
    SUB E
    CALL FOTZER
    PUSH BC
    LD B,A                          ; no more points or commas
    LD C,A

FFXXV6:
    CALL FOUTCV
    POP BC
    OR C                            ; any places wanted after the decimal point?
    JP NZ,FFXXV7
    LD HL,[TEMP2]                   ; none: end at the decimal point

; Writes the trailing zeros the field still needs, then finishes at FOUTTS.
FFXXV7:
    ADD A,E
    DEC A
    CALL P,FOTZER
    LD D,B                          ; D = the digits before the point, for FOUTTS
    JP FOUTTS

;; Formats an integer in PRINT USING's exponential layout, by converting it to single precision first.
FFXIFL:
    PUSH HL
    PUSH DE                         ; keep the format flags in D
    CALL CONSI
    POP DE
    XOR A                           ; zero sends FFXFLV down the single-precision path

;; Formats a single or double value in PRINT USING's exponential layout, with 6 or 16 significant digits.
;;
;; In:    zero = set if single precision, D = the format flags, SP = at the first digit's position and
;;        the field sizes
FFXFLV:
    JP Z,FFXSFL
    LD E,$10                        ; E = 16 digits for double precision
    .byte $01                       ; LD BC,nnnn skips the LD E,$06

FFXSFL:
    LD E,$06
    CALL SIGN
    SCF                             ; carry marks a zero value, which needs no exponent
    CALL NZ,FOUTNV                  ; scale a nonzero value, A = the powers of ten applied
    POP HL
    POP BC
    PUSH AF                         ; save the scale and the zero-value carry
    LD A,C                          ; A = the places wanted after the decimal point
    OR A
    PUSH AF
    CALL NZ,DCRART                  ; one of them is the point itself
    ADD A,B
    LD C,A                          ; C = the digit positions in the field
    LD A,D
    AND $04                         ; bit 2 set means the sign follows the number
    CP $01
    SBC A,A                         ; A = $FF if the sign leads the field, else 0
    LD D,A
    ADD A,C                         ; a leading sign takes one digit position
    LD C,A
    SUB E                           ; A = the digits beyond the precision, negative to drop
    PUSH AF
    PUSH BC

FFXLV1:
    CALL M,FINDIV                   ; divide by ten for each digit that doesn't fit
    JP M,FFXLV1
    POP BC
    POP AF
    PUSH BC
    PUSH AF
    JP M,FFXLV3                     ; digits were dropped: count them as zeros to add
    XOR A

FFXLV3:
    CPL
    INC A
    ADD A,B
    INC A
    ADD A,D
    LD B,A                          ; B = the digits before the point
    LD C,$00                        ; no commas in exponential notation
    CALL FOUTCV                     ; write the digits
    POP AF
    CALL P,FOTZNC                   ; pad with zeros where digits were dropped
    CALL FOUTED                     ; the point may fall after the last digit
    POP BC
    POP AF
    JP NZ,FFXFLV_1
    CALL DCXHRT                     ; no places after the point: back up over the last character
    LD A,[HL]
    CP '.'
    CALL NZ,INXHRT                  ; and keep it unless it is the point
    LD [TEMP2],HL                   ; where the point is, or would be

FFXFLV_1:
    POP AF
    JP C,FFXLV2                     ; a zero value: the exponent stays zero
    ADD A,E                         ; A = the exponent to print, adjusted for the field
    SUB B
    SUB D

FFXLV2:
    PUSH BC
    CALL FOFLDN                     ; write the E or D exponent
    EX DE,HL                        ; HL = the end of the text
    POP DE                          ; D = the digits before the point, for FOUTTS
    JP FOUTTS

;; Scales the accumulator by powers of ten into the 6- or 16-digit range, counting them in A.
;;
;; Single precision ends from 99999.95 to below 999999.5, double precision from 999999999999999.5 to below
;; 9999999999999999.5, so that rounding gives 6 or 16 digits.
;;
;; In:    FAC = a positive single or double value
;; Out:   A = the powers of ten divided out, negative for those multiplied in, with the flags set to match
;; Keeps: DE
FOUTNV:
    PUSH DE
    XOR A                           ; no powers of ten applied yet
    PUSH AF
    CALL GETYPR
    JP PO,FOUNDB                    ; single precision needs no rough scaling first

; A small double is multiplied by 1E10 at a time, until it is 65536 or more.
FORBIG:
    LD A,[FAC]                      ; A = the exponent byte
    CP $91                          ; $91 and up is 65536 or more
    JP NC,FOUNDB
    LD DE,TENTEN
    LD HL,ARGLO
    CALL VMOVE                      ; ARG = 1E10
    CALL DMULT                      ; times 1E10
    POP AF
    SUB $0A                         ; count the ten powers of ten
    PUSH AF
    JP FORBIG

FOUNDB:
    CALL FOUNVC                     ; bring a large value below the upper bound

FOUNV1:
    CALL GETYPR
    JP PE,FOUTNV_1                  ; double precision compares with its own bound
    LD BC,$9143                     ; BC/DE = 99999.95 in single precision
    LD DE,$4FF9
    CALL FCOMP
    JP FOUTNV_2

FOUTNV_1:
    LD DE,FOUTDL
    CALL DCOMPD

FOUTNV_2:
    JP P,FOUTNV_4                   ; at or above the lower bound: done
    POP AF                          ; A = the scale count
    CALL FINMLT                     ; multiply by ten, decrementing A
    PUSH AF
    JP FOUNV1

FOUTNV_3:
    POP AF
    CALL FINDIV                     ; divide by ten, incrementing A
    PUSH AF
    CALL FOUNVC                     ; check again against the upper bound

FOUTNV_4:
    POP AF                          ; A = the scale count
    OR A                            ; set the flags from it
    POP DE
    RET

;; Divides the accumulator by ten until it is below the upper bound of the single or double range, then returns
;; to its caller.
;;
;; It is called with FOUTNV's scale count on the stack, and each division goes through FOUTNV_3, which counts it
;; and calls FOUNVC again.
FOUNVC:
    CALL GETYPR
    JP PE,FONVC1
    LD BC,$9474                     ; BC/DE = 999999.5 in single precision
    LD DE,$23F8
    CALL FCOMP
    JP FONVC2

FONVC1:
    LD DE,FOUTDU
    CALL DCOMPD

FONVC2:
    POP HL                          ; HL = the return address, so a division can bypass it
    JP P,FOUTNV_3                   ; still too big: divide by ten again
    JP [HL]                         ; return to the caller

;; Writes A zeros at HL.
;;
;; In:    A = the count, HL = where they go
;; Out:   A = 0, HL = after the zeros
;; Keeps: BC, DE
FOTZER:
    OR A

FOTZR1:
    RET Z
    DEC A
    LD [HL],'0'
    INC HL
    JP FOTZR1

;; Writes A zeros at HL with the decimal point or commas between them as they fall due, or nothing if zero is
;; set.
;;
;; In:    A = the count, zero = set to write nothing, BC = the counters of <FOUTED>, HL = where they go
;; Out:   A = 0, HL = after the zeros
;; Entry: FOTZEC = writes a zero before checking for the point
FOTZNC:
    JP NZ,FOTZEC

FOTZRC:
    RET Z
    CALL FOUTED                     ; the point or a comma, if one is due here

FOTZEC:
    LD [HL],'0'
    INC HL
    DEC A
    JP FOTZRC

;; Sets B to the digits before the decimal point and C to count down to the first comma.
;;
;; In:    D = the significant digits, E = the powers of ten divided out, TEMP3 = the format flags
;; Out:   B = E+D+1, C = the digits before the first comma, plus one, or 0 for no commas
;; Uses:  A
;; Keeps: DE, HL
FOUTCD:
    LD A,E
    ADD A,D
    INC A
    LD B,A                          ; B = the digits before the decimal point
    INC A

FOTCD1:
    SUB $03
    JP NC,FOTCD1
    ADD A,$05                       ; C = the digits before the first comma, plus one
    LD C,A

;; Clears the comma counter in C unless the format flags ask for commas.
;;
;; In:    C = the comma counter, TEMP3 = the format flags
;; Out:   C = unchanged, or 0 if bit 6 is clear
;; Uses:  A
;; Keeps: B, DE, HL
FOUICC:
    LD A,[TEMP3]
    AND $40                         ; bit 6 asks for commas
    RET NZ
    LD C,A                          ; A is 0 here: no commas
    RET

;; Counts a digit off B like <FOUTED>, but for a B of zero or less writes the decimal point and the zeros of a
;; number below 1 in fixed notation.
;;
;; MBASIC's: FOUFRF calls it before the first digit, where Level II calls FOUTED.
;;
;; In:    B = the digits before the decimal point, zero or negative for none, C = the comma counter,
;;        HL = where to write
;; Out:   BC = counted down, HL = after anything written, TEMP2 = the decimal point's address,
;;        zero = set if the point or a comma was written
;; Keeps: A, DE
FOUTDZ:
    DEC B
    JP P,FOUTED_1                   ; a digit before the point: as FOUTED
    LD [TEMP2],HL
    LD [HL],'.'

FOUTDZ_1:
    INC HL
    LD [HL],'0'                     ; a zero for each place before the first digit
    INC B
    JP NZ,FOUTDZ_1
    INC HL
    LD C,B                          ; no commas after the decimal point
    RET

;; Counts a digit off B, writing the decimal point at HL when it is due, or a comma when C counts down.
;;
;; In:    B = the digits left before the decimal point, C = the digits left before the next comma, 0 for no
;;        commas, HL = where to write
;; Out:   BC = counted down, HL = after anything written, TEMP2 = the decimal point's address,
;;        zero = set if the point or a comma was written
;; Keeps: A, DE
FOUTED:
    DEC B

FOUTED_1:
    JP NZ,FOUED1

;; Writes the decimal point at HL and records its address in TEMP2.
;;
;; In:    B = 0, HL = where it goes
;; Out:   C = 0, no commas after the point, HL = after the point
;; Keeps: A, DE
FOUTDP:
    LD [HL],'.'
    LD [TEMP2],HL                   ; remember where the point went
    INC HL
    LD C,B                          ; C = 0: no commas after the decimal point
    RET

; Counts C down to the next thousands separator, writing a comma every third digit.
FOUED1:
    DEC C
    RET NZ
    LD [HL],','
    INC HL
    LD C,$03                        ; the next comma three digits later
    RET

;; Writes the integer value of a single or double accumulator at HL as decimal digits, rounding it first.
;;
;; In:    FAC = a value scaled by <FOUTNV>, BC = the counters of <FOUTED>, HL = where to write
;; Out:   HL = after the digits, which end in a zero byte, A = 0
;; Keeps: DE
FOUTCV:
    PUSH DE
    CALL GETYPR
    JP PO,FOUTCS                    ; single precision
    PUSH BC
    PUSH HL
    CALL VMOVAF                     ; ARG = the value
    LD HL,DHALF
    CALL VMOVFM
    CALL DADD                       ; add 0.5 to round to the nearest whole number
    XOR A
    CALL DINTFO                     ; drop the fraction, leaving a 56-bit integer
    POP HL
    POP BC
    LD DE,FODTBL                    ; the powers of ten from 10^15 down
    LD A,$0A                        ; ten digits come from the double table

;; Writes A digits at HL by subtracting the 7-byte powers of ten at DE from the double accumulator, then the rest
;; as single precision.
FOUCD1:
    CALL FOUTED
    PUSH BC
    PUSH AF
    PUSH HL
    PUSH DE
    LD B,'0'-1

FOUCD2:
    INC B
    POP HL                          ; HL = this power of ten, kept on the stack
    PUSH HL
    LD A,$9E                        ; SBC A,[HL]: subtract it once
    CALL DADDFO
    JP NC,FOUCD2                    ; until the value goes negative
    POP HL
    LD A,$8E                        ; ADC A,[HL]: add back the last one subtracted
    CALL DADDFO
    EX DE,HL                        ; DE = the next, smaller power of ten
    POP HL
    LD [HL],B                       ; store the digit
    INC HL
    POP AF
    POP BC
    DEC A
    JP NZ,FOUCD1
    PUSH BC                         ; the rest is below 10^6 and fits in 24 bits
    PUSH HL
    LD HL,DFACLO                    ; the low bytes of the double accumulator
    CALL MOVFM
    JP FOUCDC                       ; the last six digits as single precision

;; Rounds a single-precision accumulator to an integer and writes its decimal digits at HL.
FOUTCS:
    PUSH BC
    PUSH HL
    CALL FADDH                      ; add 0.5 to round to the nearest whole number
    LD A,$01
    CALL QINT                       ; CDE = the value as a 24-bit integer
    CALL MOVFR                      ; kept in the FAC

FOUCDC:
    POP HL
    POP BC
    XOR A                           ; clear carry; the CCF below sets it for the first pass
    LD DE,FOSTBL                    ; 100000, then 10000

;; Writes the two highest digits of the 24-bit integer in the FAC at HL, using the table at DE, then the other
;; four with <FOUCI1>.
FOUCS1:
    CCF                             ; carry set on the first pass only
    CALL FOUTED
    PUSH BC
    PUSH AF
    PUSH HL
    PUSH DE
    CALL MOVRF                      ; CDE = the remaining value
    POP HL
    LD B,'0'-1

FOUCS2:
    INC B
    LD A,E                          ; subtract the 3-byte power of ten from CDE
    SUB [HL]
    LD E,A
    INC HL
    LD A,D
    SBC A,[HL]
    LD D,A
    INC HL
    LD A,C
    SBC A,[HL]
    LD C,A
    DEC HL                          ; HL back to the start of this power
    DEC HL
    JP NC,FOUCS2                    ; until the value goes negative
    CALL FADDA                      ; add back the last one subtracted
    INC HL                          ; HL = the next power of ten
    CALL MOVFR
    EX DE,HL                        ; DE = the next table entry
    POP HL
    LD [HL],B                       ; store the digit
    INC HL
    POP AF
    POP BC
    JP C,FOUCS1                     ; the second pass, for the 10000 digit
    INC DE                          ; DE = 1000 in FOITBL: the value is now below 10000
    INC DE
    LD A,$04                        ; four digits remain
    JP FOUCI1

;; Writes the integer in FACLO as five decimal digits at HL, with the decimal point and commas as they fall due.
;;
;; In:    FACLO = the integer, BC = the counters of <FOUTED>, HL = where to write
;; Out:   HL = after the digits, which end in a zero byte, A = 0
;; Keeps: DE
FOUTCI:
    PUSH DE
    LD DE,FOITBL                    ; 10000 down to 1
    LD A,$05                        ; five digits for a full integer

;; Writes A digits of FACLO at HL using the 16-bit powers of ten at DE.
FOUCI1:
    CALL FOUTED
    PUSH BC
    PUSH AF
    PUSH HL
    EX DE,HL
    LD C,[HL]                       ; BC = this power of ten
    INC HL
    LD B,[HL]
    PUSH BC
    INC HL
    EX [SP],HL                      ; the stack keeps the next entry, HL = this power
    EX DE,HL                        ; DE = this power of ten
    LD HL,[FACLO]                   ; HL = the remaining value
    LD B,'0'-1

FOUCI2:
    INC B
    LD A,L
    SUB E                           ; subtract this power of ten
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    JP NC,FOUCI2                    ; until the value goes negative
    ADD HL,DE                       ; add back the last one subtracted
    LD [FACLO],HL                   ; the remainder goes on to the next digit
    POP DE
    POP HL
    LD [HL],B                       ; store the digit
    INC HL
    POP AF
    POP BC
    DEC A
    JP NZ,FOUCI1
    CALL FOUTED                     ; the decimal point may fall after the last digit
    LD [HL],A                       ; A is 0: end the text
    POP DE
    RET

;; 1E10 in double precision, the factor FORBIG scales small doubles up by.
TENTEN:
    .byte $00, $00, $00, $00, $F9, $02, $15, $A2 ; 1E10

;; The double-precision lower bound of FOUTNV's range.
FOUTDL:
    .byte $E1, $FF, $9F, $31, $A9, $5F, $63, $B2 ; 999999999999999.5

;; The double-precision upper bound of FOUTNV's range.
FOUTDU:
    .byte $FE, $FF, $03, $BF, $C9, $1B, $0E, $B6 ; 9999999999999999.5

;; One half in double precision: four low zero bytes, then FHALF.
DHALF:
    .byte $00, $00, $00, $00        ; the low bytes of 0.5

;; One half in single precision, which FOUTCS adds to round and SQR uses as the power.
FHALF:
    .byte $00, $00, $00, $80        ; 0.5

;; 1E16 in double precision, the largest double FOUFXV puts in a fixed field.
FFXDXM:
    .byte $00, $00, $04, $BF, $C9, $1B, $0E, $B6 ; 1E16

;; The powers of ten from 10^15 down to 10^6 as 7-byte integers, low byte first, for double-precision output.
FODTBL:
    .byte $00, $80, $C6, $A4, $7E, $8D, $03 ; 10^15
    .byte $00, $40, $7A, $10, $F3, $5A, $00 ; 10^14
    .byte $00, $A0, $72, $4E, $18, $09, $00 ; 10^13
    .byte $00, $10, $A5, $D4, $E8, $00, $00 ; 10^12
    .byte $00, $E8, $76, $48, $17, $00, $00 ; 10^11
    .byte $00, $E4, $0B, $54, $02, $00, $00 ; 10^10
    .byte $00, $CA, $9A, $3B, $00, $00, $00 ; 10^9
    .byte $00, $E1, $F5, $05, $00, $00, $00 ; 10^8
    .byte $80, $96, $98, $00, $00, $00, $00 ; 10^7
    .byte $40, $42, $0F, $00, $00, $00, $00 ; 10^6

;; 100000 and 10000 as 3-byte integers, for single-precision output.
FOSTBL:
    .byte $A0, $86, $01             ; 100000
    .byte $10, $27, $00             ; 10000

;; The powers of ten from 10000 down to 1 as 16-bit integers, for integer output.
FOITBL:
    .word 10000, 1000, 100, 10, 1

;; Converts the integer accumulator to octal digits for OCT$.
;;
;; Leading zeros are dropped, keeping at least one digit.
;;
;; In:    FAC = the number, which may be up to 65535
;; Out:   HL = the digits at FBUFFR, ending in a zero byte
;; Uses:  all
FOUTO:
    XOR A
    LD B,A                          ; B = 0: octal
    .byte $C2                       ; JP NZ,nnnn, never taken, skips the LD B,$01

;; Converts the integer accumulator to hex digits for HEX$.
;;
;; Leading zeros are dropped, keeping at least one digit.
;;
;; In:    FAC = the number, which may be up to 65535
;; Out:   HL = the digits at FBUFFR, ending in a zero byte
;; Uses:  all
FOUTH:
    LD B,$01                        ; B = 1: hex
    PUSH BC
    CALL FRQINT                     ; HL = the number as 16 bits
    POP BC
    LD DE,FBUFFR
    PUSH DE
    XOR A
    LD [DE],A                       ; no digit stored yet, for the zero suppression
    DEC B
    INC B
    LD C,$06                        ; octal: six digits, the first the top bit alone
    JP Z,FOUTH_3
    LD C,$04                        ; hex: four digits

FOUTH_1:
    ADD HL,HL                       ; shift the next four or three bits into A
    ADC A,A

FOUTH_2:
    ADD HL,HL
    ADC A,A
    ADD HL,HL
    ADC A,A

FOUTH_3:
    ADD HL,HL
    ADC A,A
    OR A
    JP NZ,FOUTH_4                   ; a nonzero digit is always stored
    LD A,C
    DEC A
    JP Z,FOUTH_4                    ; so is the last, A = 0
    LD A,[DE]
    OR A
    JP Z,FOUTH_6                    ; a leading zero is dropped
    XOR A

FOUTH_4:
    ADD A,'0'
    CP '9'+1
    JP C,FOUTH_5
    ADD A,'A'-'9'-1                 ; 10 to 15 become A to F

FOUTH_5:
    LD [DE],A
    INC DE
    LD [DE],A                       ; a nonzero byte at the next place says a digit has been stored

FOUTH_6:
    XOR A
    DEC C
    JP Z,FOUTH_7                    ; all the digits done
    DEC B
    INC B
    JP Z,FOUTH_2                    ; octal: three bits a digit
    JP FOUTH_1                      ; hex: four

FOUTH_7:
    LD [DE],A                       ; end the text
    POP HL                          ; HL = FBUFFR
    RET

;; Makes the caller's return go through NEG, negating the accumulator, then resumes the caller.
;;
;; Uses:  HL
PSHNEG:
    LD HL,NEG
    EX [SP],HL                      ; the caller's return now goes through NEG
    JP [HL]                         ; resume the caller

;; Computes SQR: the square root of the accumulator, as the accumulator raised to the power 0.5.
;;
;; In:    FAC = x, single precision
;; Out:   FAC = SQR(x)
;; Uses:  all
FN_SQR:
    CALL PUSHF                      ; save x as the base
    LD HL,FHALF
    CALL MOVFM                      ; the power is 0.5
    JP FPWRT

;; Applies the ^ operator: raises the number on the stack to the power in the accumulator, in single precision.
;;
;; The operator table (Evaluator.asm) gives this address.
;;
;; In:    SP = at the base in single precision, as PUSHF pushes it, FAC = the power
;; Out:   FAC = the result
;; Uses:  all
FPWRQ:
    CALL FN_CSNG                    ; the power must be single precision

;; Pops the base from the stack into BCDE and raises it to the power in the accumulator.
;;
;; It sets FLGOVC, the once-only overflow flag (GW-BASIC's $FLGOV), and returns through CLROVC, which clears
;; it. Zero to a negative power is a division by zero, and a negative base needs a whole-number power.
;;
;; In:    SP = at the base in single precision, as PUSHF pushes it, FAC = the power
;; Out:   FAC = the result
;; Uses:  all
FPWRT:
    POP BC
    POP DE
    LD HL,CLROVC                    ; return through the code that clears FLGOVC
    PUSH HL
    LD A,$01
    LD [FLGOVC],A
    CALL SIGN                       ; test the power
    LD A,B                          ; A = the base's exponent byte, zero if the base is 0
    JP Z,FN_EXP                     ; anything to the power zero is 1, which EXP(0) gives
    JP P,POSEXP                     ; a positive power: a zero base is fine
    OR A
    JP Z,DIV0S                      ; zero to a negative power divides by zero

;; Continues the power with a nonzero power: a zero base gives 0, and a negative base needs a whole-number power.
POSEXP:
    OR A
    JP Z,ZERO0                      ; zero to a positive power is zero
    PUSH DE
    PUSH BC
    LD A,C                          ; A = the base's sign byte
    OR $7F
    CALL MOVRF                      ; BCDE = the power
    JP P,FPWR1                      ; a positive base: no sign to work out
    PUSH AF
    LD A,[FAC]
    CP $99                          ; a power of 2^24 or more is too large to test
    JP C,POSEXP_1
    POP AF                          ; leave the base negative for LOG
    JP FPWR1

POSEXP_1:
    POP AF
    PUSH DE
    PUSH BC
    CALL INT                        ; INT of the power
    POP BC
    POP DE
    PUSH AF                         ; keep its low byte
    CALL FCOMP                      ; zero if the power was already a whole number
    POP HL
    LD A,H                          ; A = the low byte of the whole power
    RRA                             ; carry = an odd power

;; Computes the power as EXP(power * LOG(base)), fixing the sign for a negative base.
FPWR1:
    POP HL                          ; put the base back into the accumulator
    LD [FACHI],HL
    POP HL
    LD [FACLO],HL
    CALL C,PSHNEG                   ; an odd power of a negative base: negate the result
    CALL Z,NEG                      ; a whole power: take the log of the base's magnitude
    PUSH DE                         ; keep the power for the multiply
    PUSH BC
    CALL FN_LOG
    POP BC
    POP DE
    CALL FMULT                      ; the power times the log of the base

;; Computes EXP: e raised to the accumulator, as 2 raised to x * LOG2(e).
;;
;; The whole part of the power of two becomes the result's exponent, and a polynomial (Hart 1302, EXPCON) gives
;; 2 to the fraction. A result too large overflows; one too small is zero.
;;
;; In:    FAC = x, single precision
;; Out:   FAC = EXP(x)
;; Uses:  all
FN_EXP:
    LD BC,$8138                     ; BC/DE = LOG2(e), 1.442695
    LD DE,$AA3B
    CALL FMULT                      ; y = x * LOG2(e)
    LD A,[FAC]
    CP $88                          ; 128 or more overflows or underflows
    JP NC,EXP110
    CP $68                          ; so small that the result is 1
    JP C,EXP200
    CALL PUSHF                      ; save y
    CALL INT                        ; INT(y), A = its low byte
    ADD A,$81                       ; A = the exponent byte of 2^INT(y)
    POP BC
    POP DE
    JP Z,EXP100                     ; too large
    PUSH AF
    CALL FSUB                       ; the fraction, y - INT(y)
    LD HL,EXPCON
    CALL POLY                       ; 2 to the fraction
    POP BC
    LD DE,$0000                     ; BCDE = 2^INT(y): only the exponent byte is nonzero
    LD C,D
    JP FMULT                        ; 2^INT(y) * 2^fraction

; y is too large: overflow if it is positive, zero if negative.
EXP110:
    CALL PUSHF                      ; so that the stack matches EXP100's

EXP100:
    LD A,[FACHI]
    OR A
    JP P,EXP115
    POP AF
    POP AF
    JP ZERO                         ; underflow: zero

EXP115:
    JP FACOVP                       ; overflow

EXP200:
    LD BC,$8100                     ; 1.0
    LD DE,$0000
    JP MOVFR

;; The count and coefficients of the polynomial for 2^x, 0 <= x < 1 (Hart 1302).
EXPCON:
    .byte $07                       ; seven coefficients, highest power first
    .byte $7C, $88, $59, $74        ; 0.000207455771
    .byte $E0, $97, $26, $77        ; 0.00127100572
    .byte $C4, $1D, $1E, $7A        ; 0.00965065137
    .byte $5E, $50, $63, $7C        ; 0.055496566
    .byte $1A, $FE, $75, $7E        ; 0.240227133
    .byte $18, $72, $31, $80        ; 0.693147182
    .byte $00, $00, $00, $81        ; 1

;; Evaluates the odd polynomial x*P(x^2) for the accumulator, with the coefficient table at HL.
;;
;; In:    FAC = x, single precision, HL = the table, as <POLY>'s
;; Out:   FAC = the result
;; Uses:  all
POLYX:
    CALL PUSHF                      ; save x
    LD DE,FMULTT                    ; return through FMULTT, which multiplies the sum by x
    PUSH DE
    PUSH HL
    CALL MOVRF
    CALL FMULT                      ; x squared
    POP HL

;; Evaluates the polynomial with the coefficient table at HL for the accumulator, by Horner's rule.
;;
;; In:    FAC = x, single precision, HL = the table: a count, then the coefficients in single precision,
;;        highest power first
;; Out:   FAC = the result
;; Uses:  all
POLY:
    CALL PUSHF                      ; save x for each step
    LD A,[HL]                       ; A = the number of coefficients
    INC HL
    CALL MOVFM                      ; the sum = the first coefficient
    .byte $06                       ; LD B,n skips the POP AF on the first pass

POLY1:
    POP AF                          ; A = the coefficients left
    POP BC                          ; BCDE = x
    POP DE
    DEC A
    RET Z                           ; all the terms done
    PUSH DE
    PUSH BC
    PUSH AF
    PUSH HL
    CALL FMULT                      ; the sum times x
    POP HL
    CALL MOVRM                      ; BCDE = the next coefficient
    PUSH HL
    CALL FADD                       ; plus the next coefficient
    POP HL
    JP POLY1

;; The value RNDX starts with, which clearing the variables (Misc.asm) copies back into it.
RNDINI:
    .byte $52, $C7, $4F, $80        ; 0.811635137

;; Returns the next random number for RND written without an argument, skipping the RND token.
;;
;; In:    HL = the text at the RND token
;; Out:   FAC = the number, VALTYP = 4, HL = the text after the token
;; Uses:  all
RNDMON:
    CALL CHRGTR

;; Returns the next random number in the accumulator, as RND(1).
;;
;; RANDOMIZE (Math1.asm) calls it after storing the new seed in RNDXM.
;;
;; Out:   FAC = the number, VALTYP = 4
;; Keeps: HL
RNDMN2:
    PUSH HL
    LD HL,FONE
    CALL MOVFM                      ; the FAC = 1
    CALL FN_RND
    POP HL
    JP VALSNG                       ; VALTYP = single precision

;; Computes RND(x): the next random number from 0 to 1 for x > 0, the last one again for x = 0, and a new
;; sequence seeded from x for x < 0.
;;
;; Each number is the last, RNDX, times one of eight multipliers (RNDMUL) plus one of three tiny addends
;; (RNDADD), each taken in turn. The result's mantissa bytes are then shuffled and its exponent made $80, so that
;; it is a fraction below 1 once normalized, and every 171st number is nudged.
;;
;; In:    FAC = x, single precision
;; Out:   FAC = the number, RNDX = the same
;; Uses:  all
FN_RND:
    CALL SIGN                       ; A = the sign of x: 1, 0 or -1
    LD HL,RNDMLI
    JP M,RNDSED                     ; negative: a new sequence
    LD HL,RNDX
    CALL MOVFM                      ; the FAC = the last number
    LD HL,RNDMLI
    RET Z                           ; RND(0) returns it again
    ADD A,[HL]                      ; the next multiplier, of the eight
    AND $07
    LD B,$00
    LD [HL],A
    INC HL                          ; HL = RNDMUL
    ADD A,A
    ADD A,A
    LD C,A
    ADD HL,BC
    CALL MOVRM                      ; BCDE = the multiplier
    CALL FMULT                      ; times the last number
    LD A,[RNDADI]
    INC A                           ; the next addend: 1, 2, 3, 1, ...
    AND $03
    LD B,$00
    CP $01
    ADC A,B
    LD [RNDADI],A
    LD HL,RNDX                      ; the addends follow RNDX, counted from 1
    ADD A,A
    ADD A,A
    LD C,A
    ADD HL,BC
    CALL FADDS                      ; plus the addend

; Shuffles the number in the FAC into a fraction and stores it as the new RNDX.
RND1:
    CALL MOVRF                      ; BCDE = the FAC, HL = the sign byte after it
    LD A,E                          ; swap the low and high mantissa bytes,
    LD E,C
    XOR $4F                         ; scrambling the new high byte
    LD C,A
    LD [HL],$80                     ; a positive result
    DEC HL
    LD B,[HL]                       ; the old exponent becomes the lowest bits
    LD [HL],$80                     ; exponent $80: a fraction below 1
    LD HL,RNDCNT
    INC [HL]
    LD A,[HL]
    SUB $AB                         ; every 171st number,
    JP NZ,RND2
    LD [HL],A                       ; restart the count
    INC C                           ; and nudge the mantissa
    DEC D
    INC E

RND2:
    CALL NORMAL                     ; normalize CDEB into the FAC
    LD HL,RNDX
    JP MOVMF                        ; store it as the new last number

; x < 0: set the counters to $FF and make x itself the seed.
RNDSED:
    LD [HL],A                       ; A = $FF
    DEC HL
    LD [HL],A
    DEC HL
    LD [HL],A
    JP RND1

; RND's state.
RNDCNT: .byte $00                   ;; the numbers RND has made since the last nudge, up to 171
RNDADI: .byte $00                   ;; which addend of RNDADD was used last, 1 to 3
RNDMLI: .byte $00                   ;; which multiplier of RNDMUL was used last, 0 to 7

;; The eight multipliers RND takes in turn.
RNDMUL:
    .byte $35, $4A, $CA, $99        ; -26514538
    .byte $39, $1C, $76, $98        ; 16129081
    .byte $22, $95, $B3, $98        ; -11769122
    .byte $0A, $DD, $47, $98        ; 13098250
    .byte $53, $D1, $99, $99        ; -20161190
    .byte $0A, $1A, $9F, $98        ; -10426890
    .byte $65, $BC, $CD, $98        ; -13483109
    .byte $D6, $77, $3E, $98        ; 12482518

;; The last random number, in single precision, 0.811635137 at first (RNDINI).
RNDX:
    .byte $52
RNDXM: .byte $C7, $4F               ;; the middle mantissa bytes of RNDX, which RANDOMIZE sets
    .byte $80

;; The three addends RND takes in turn, which it reaches from RNDX.
RNDADD:
    .byte $68, $B1, $46, $68        ; 4.62618175E-08
    .byte $99, $E9, $92, $69        ; -6.84114596E-08
    .byte $10, $D1, $75, $68        ; 5.72336489E-08

;; Computes COS of the accumulator in radians, as the sine of the accumulator plus pi/2.
;;
;; In:    FAC = x, single precision
;; Out:   FAC = COS(x)
;; Uses:  all
FN_COS:
    LD HL,PI2
    CALL FADDS                      ; COS(x) = SIN(x + pi/2)

;; Computes SIN of the accumulator in radians, reducing the angle to a quarter turn for a polynomial.
;;
;; SIN(-x) = -SIN(x), so it works with the magnitude. The angle is taken in turns, x/(2*pi), and its fraction f
;; brought into -1/4 to 1/4 as f, 1/2 - f or f - 1. SINCON's polynomial (Hart 3341) takes the angle in turns.
;;
;; In:    FAC = x, single precision
;; Out:   FAC = SIN(x)
;; Uses:  all
FN_SIN:
    LD A,[FAC]
    CP $77                          ; below 2^-9, SIN(x) = x
    RET C
    LD A,[FACHI]
    OR A
    JP P,FN_SIN_1
    AND $7F                         ; negative: work with -x
    LD [FACHI],A
    LD DE,NEG                       ; and negate the result
    PUSH DE

FN_SIN_1:
    LD BC,$7E22                     ; BC/DE = 1/(2*pi), 0.159155
    LD DE,$F983
    CALL FMULT                      ; the angle in turns
    CALL PUSHF
    CALL INT                        ; whole turns
    POP BC
    POP DE
    CALL FSUB                       ; f = the fraction of a turn
    LD BC,$7F00                     ; BC/DE = 0.25
    LD DE,$0000
    CALL FCOMP
    JP M,FN_SIN_2                   ; f below a quarter turn: as it is
    LD BC,$7F80                     ; BC/DE = -0.25
    LD DE,$0000
    CALL FADD
    LD BC,$8080                     ; BC/DE = -0.5
    LD DE,$0000
    CALL FADD                       ; f - 3/4
    CALL SIGN
    CALL P,NEG                      ; the last quarter: 3/4 - f
    LD BC,$7F00                     ; BC/DE = 0.25
    LD DE,$0000
    CALL FADD
    CALL NEG                        ; 1/2 - f, or f - 1

FN_SIN_2:
    LD A,[FACHI]
    OR A
    PUSH AF                         ; save the reduced angle's sign
    JP P,FN_SIN_3
    XOR $80                         ; and evaluate for its magnitude
    LD [FACHI],A

FN_SIN_3:
    LD HL,SINCON
    CALL POLYX
    POP AF
    RET P
    LD A,[FACHI]                    ; a negative angle: negate the result
    XOR $80
    LD [FACHI],A
    RET

;; 1/(2*pi) in double precision, its low bytes zeroed as in GW-BASIC's $IN2PI; nothing here uses it.
IN2PI:
    .byte $00, $00, $00, $00, $83, $F9, $22, $7E ; 0.159154937

;; pi/2, which COS adds and ATN subtracts from.
PI2:
    .byte $DB, $0F, $49, $81        ; 1.57079637

;; A quarter, as in Level II's sine; nothing here uses it.
FR4:
    .byte $00, $00, $00, $7F        ; 0.25

;; The count and coefficients of SIN's polynomial, for the angle in turns (Hart 3341).
;;
;; The protection of SAVE ,P (Disk2.asm) also uses its bytes as one of its two keys.
SINCON:
    .byte $05                       ; five coefficients, highest power first
    .byte $FB, $D7, $1E, $86        ; 39.7109184
    .byte $65, $26, $99, $87        ; -76.5749893
    .byte $58, $34, $23, $87        ; 81.6022339
    .byte $E1, $5D, $A5, $86        ; -41.3416786
    .byte $DB, $0F, $49, $83        ; 6.28318548

;; Computes TAN of the accumulator in radians, as its sine divided by its cosine.
;;
;; In:    FAC = x, single precision
;; Out:   FAC = TAN(x)
;; Uses:  all
FN_TAN:
    CALL PUSHF                      ; save x
    CALL FN_SIN
    POP BC                          ; recover x
    POP HL
    CALL PUSHF                      ; save SIN(x)
    EX DE,HL                        ; BCDE = x
    CALL MOVFR                      ; the FAC = x again
    CALL FN_COS
    JP FDIVT                        ; SIN(x) / COS(x)

;; Computes ATN of the accumulator in radians, using pi/2 - ATN(1/x) for arguments of 1 or more.
;;
;; In:    FAC = x, single precision
;; Out:   FAC = ATN(x)
;; Uses:  all
FN_ATN:
    CALL SIGN
    CALL M,PSHNEG                   ; negative x: negate the result
    CALL M,NEG                      ; and work with -x
    LD A,[FAC]
    CP $81                          ; $81 and up is 1 or more
    JP C,ATN2                       ; below 1: the series directly
    LD BC,$8100                     ; BC/DE = 1.0
    LD D,C
    LD E,C
    CALL FDIV                       ; the FAC = 1/x
    LD HL,FSUBS                     ; return through FSUBS: pi/2 minus the series
    PUSH HL

ATN2:
    LD HL,ATNCON
    CALL POLYX
    LD HL,PI2                       ; for FSUBS
    RET

;; The count and coefficients of ATN's polynomial, for x from 0 to 1.
;;
;; The protection of SAVE ,P (Disk2.asm) also uses its bytes as one of its two keys.
ATNCON:
    .byte $09                       ; nine coefficients, highest power first
    .byte $4A, $D7, $3B, $78        ; 0.00286622578
    .byte $02, $6E, $84, $7B        ; -0.0161657371
    .byte $FE, $C1, $2F, $7C        ; 0.0429096147
    .byte $74, $31, $9A, $7D        ; -0.0752896369
    .byte $84, $3D, $5A, $7D        ; 0.106562644
    .byte $C8, $7F, $91, $7E        ; -0.142089009
    .byte $E4, $BB, $4C, $7E        ; 0.199935496
    .byte $6C, $AA, $AA, $7F        ; -0.333331466
    .byte $00, $00, $00, $81        ; 1
