;; INTEGER BASIC: STRINGS, MULTIPLICATION AND SCRN( ($E0FB-$E2AF)
;;
;; The routines for string tokens: substrings, DIM of a string, string INPUT, string assignment and the string
;; comparisons; then multiplication and MOD, the line input INPUT uses for numbers, and SCRN(.
;;
;; On the noun stack a string takes two entries. The lower one is the string's address (the variable's first
;; character, or $0200 for a line just typed). The one above it is a range: the index of the first character in
;; NOUNSTKL and the index just past the last in NOUNSTKH. Indexes count from 0, so A$(2,3) is the range 1 to 3. A
;; string variable holds its characters and, after them, a byte with bit 7 clear; how many characters it can hold
;; is fixed by DIM and found from the address of the next variable.
;;
;; Part of IntegerBasic.asm; it follows Lister.asm, at $E0FB.

;; The opening parenthesis of a substring in an expression (token $2A): A$(n) starts the string at character n.
;;
;; The range's end stays where it was, and the start must stay before it: A$(0), or a start past the end, is a
;; STRING error.
;; In: X = the noun stack: the index, above the string's range and address
;; See: <COMMA_SUBSTR>, <GETSTRNDX>
PAREN_SUBSTR:
    jsr GETSTRNDX                   ; $E0FB
    sta NOUNSTKL,x                  ; $E0FE
    cmp NOUNSTKH,x                  ; $E100

;; Checks a substring range: carry clear passes, carry set is a STRING error.
;; Entry: PrintErr05 = the STRING error, STRERRMESS = an error with the message offset in Y
CHKSTRRNG:
    bcc SUBSTRDONE                  ; $E102

PrintErr05:
    ldy #<ErrMsg05                  ; $E104

STRERRMESS:
    jmp ERRMESS                     ; $E106

;; The comma of a substring (token $23): A$(m,n) ends the string after character n.
;;
;; The end must not come before the start, nor past the string's present end.
;; In: X = the noun stack: the second index, above the string's range
;; See: <PAREN_SUBSTR>, <CHKSTREND>
COMMA_SUBSTR:
    jsr GETBYTE                     ; $E109
    cmp NOUNSTKL,x                  ; $E10C
    bcc PrintErr05                  ; $E10E
    jsr CHKSTREND                   ; $E110
    sta NOUNSTKH,x                  ; $E113

;; Ends a substring token the way a left parenthesis ends, so the operators before it wait (<LEFT_PAREN>).
SUBSTRDONE:
    jmp LEFT_PAREN                  ; $E115

;; Takes a 1-based character position from the noun stack and returns it counted from 0.
;; Out: A = the position less 1
;; Errors: STRING for 0
;; Uses: ACC, X (popped)
GETSTRNDX:
    jsr GETBYTE                     ; $E118
    beq PrintErr05                  ; $E11B
    sec                             ; $E11D
    sbc #$01                        ; $E11E
    rts                             ; $E120

;; The opening parenthesis of a string being assigned to (token $42): A$(n)="..." stores from character n on.
;;
;; The position can be anywhere in the string or just after its end, so the string cannot get a gap.
;; In: X = the noun stack: the position, above the variable's range and address
;; See: <LET_STR>
PAREN_STRDEST:
    jsr GETSTRNDX                   ; $E121
    sta NOUNSTKL,x                  ; $E124
    clc                             ; $E126
    sbc NOUNSTKH,x                  ; $E127 carry is clear: position - end - 1
    jmp CHKSTRRNG                   ; $E129

;; The MEM FULL error.
PrintErr03:
    ldy #<ErrMsg03                  ; $E12C
    bne STRERRMESS                  ; $E12E

;; DIM of a string (token $4E, and $43 after a comma): reserves room for a string of n characters.
;;
;; A new variable gets 2 bytes for its value (<CMPVARNAME>), so DIM can only size the variable created last, the one
;; whose next-variable address is still <PV>; DIM of any other is a DIM error. It moves <PV>, and that address, past
;; n + 1 bytes: the characters and the byte that ends them.
;; In: X = the noun stack: the length, above the variable's address
;; See: <DIMNUM>, <SETVARSIZE>
DIMSTR:
    jsr GETSTRNDX                   ; $E130
    inx                             ; $E133 drop the range entry: the variable's address is on top

;; Makes the newest variable's value ACC + 1 bytes long (carry set) or ACC bytes (carry clear).
;;
;; The address after the value goes in both the variable's next-variable field and <PV>, if it stays below <PP>.
;; In: X = the noun stack: the variable's address, ACC = the size, carry = 1 to add a byte
;; Errors: MEM FULL, DIM for a variable that is not the newest
;; Uses: A, Y, AUX
;; Entry: DimErr = the DIM error
SETVARSIZE:
    lda NOUNSTKL,x                  ; $E134
    sta AUX                         ; $E136
    adc ACC                         ; $E138
    pha                             ; $E13A
    tay                             ; $E13B
    lda NOUNSTKH,x                  ; $E13C
    sta AUX+1                       ; $E13E
    adc ACC+1                       ; $E140
    pha                             ; $E142
    cpy PP                          ; $E143
    sbc PP+1                        ; $E145 the new end must stay below the program
    bcs PrintErr03                  ; $E147
    lda AUX                         ; $E149
    adc #$FE                        ; $E14B carry clear: AUX - 2, the variable's next-variable address
    sta AUX                         ; $E14D
    lda #$FF                        ; $E14F
    tay                             ; $E151
    adc AUX+1                       ; $E152
    sta AUX+1                       ; $E154
@Loop1:
    iny                             ; $E156
    lda (AUX),y                     ; $E157
    cmp PV,y                        ; $E159 compare it with PV, both bytes
    bne DimErr                      ; $E15C
    tya                             ; $E15E
    beq @Loop1                      ; $E15F Y = 0: compare the high byte too
@Loop2:
    pla                             ; $E161 store the new end in both
    sta (AUX),y                     ; $E162
    sta PV,y                        ; $E164
    dey                             ; $E167
    bpl @Loop2                      ; $E168
    inx                             ; $E16A
    rts                             ; $E16B
    .byte $EA                       ; $E16C an unused byte

DimErr:
    ldy #<ErrMsg17                  ; $E16D

SETVARSIZE_1:
    bne STRERRMESS                  ; $E16F

;; INPUT of a string: reads a line with the ? prompt, then assigns it to the variable as <LET_STR> does.
;;
;; It pushes the typed line as a string: address $0200 (<IN>) and the range 0 to the line's length.
;; In: X = the noun stack: the variable's range and address
;; See: <INPUT_STRVAR>, <RDKEY>, <LET_STR>
INPUTSTR:
    lda #$00                        ; $E171
    jsr PUSHNOUNLO                  ; $E173 push a range starting at 0
    ldy #$02                        ; $E176 and give it the address $0200
    sty NOUNSTKH,x                  ; $E178
    jsr PUSHNOUNLO                  ; $E17A the range entry; its end comes from the line
    stx XSAVE                       ; $E17D
    tax                             ; $E17F
    inc PROMPT                      ; $E180 the prompt becomes ?
    jsr RDKEY                       ; $E182
    dec PROMPT                      ; $E185
    txa                             ; $E187
    ldx XSAVE                       ; $E188
    sta NOUNSTKH,x                  ; $E18A

;; String assignment (token $70): copies the source string's range into the variable, from the variable's start
;; position, and ends it there.
;;
;; A character past the room DIM gave is a STR OVFL error.
;; In: X = the noun stack: the source's range and address above the variable's range and address
;; Errors: STR OVFL
;; See: <GETSTRROOM>, <PAREN_STRDEST>
LET_STR:
    lda NOUNSTKL+1,x                ; $E18C
    sta ACC                         ; $E18E
    lda NOUNSTKH+1,x                ; $E190
    sta ACC+1                       ; $E192
    inx                             ; $E194 pop the source; ACC = its address
    inx                             ; $E195
    jsr GETSTRROOM                  ; $E196

;; The copy loop, until the source's range is empty.
LET_STR_1:
    lda NOUNSTKL-2,x                ; $E199
    cmp NOUNSTKH-2,x                ; $E19B
    bcs LET_STR_3                   ; $E19D
    inc NOUNSTKL-2,x                ; $E19F
    tay                             ; $E1A1
    lda (ACC),y                     ; $E1A2
    ldy NOUNSTKL,x                  ; $E1A4
    cpy P2                          ; $E1A6 past the room the variable has?
    bcc LET_STR_2                   ; $E1A8
    ldy #<ErrMsg18                  ; $E1AA
    bne SETVARSIZE_1                ; $E1AC

LET_STR_2:
    sta (AUX),y                     ; $E1AE
    inc NOUNSTKL,x                  ; $E1B0
    bcc LET_STR_1                   ; $E1B2

;; Ends the string with X, which is below $80, then pops the variable and shows it if DSP is on (<LETSTREND>).
LET_STR_3:
    ldy NOUNSTKL,x                  ; $E1B4
    txa                             ; $E1B6
    sta (AUX),y                     ; $E1B7
    jmp LETSTREND                   ; $E1B9

;; Points AUX at the destination string and works out how many characters it can hold.
;;
;; The two bytes before a value are the next variable's address, so the low byte of that address, less the value's
;; address, less 1 for the ending byte, is the room DIM gave.
;; In: X = the noun stack, with the variable's address at X+1
;; Out: AUX = the variable's address, P2 = the number of characters it can hold
;; Uses: A, Y
;; Keeps: X
GETSTRROOM:
    lda NOUNSTKL+1,x                ; $E1BC
    sta AUX                         ; $E1BE
    sec                             ; $E1C0
    sbc #$02                        ; $E1C1
    sta P2                          ; $E1C3
    lda NOUNSTKH+1,x                ; $E1C5
    sta AUX+1                       ; $E1C7
    sbc #$00                        ; $E1C9
    sta P2+1                        ; $E1CB
    ldy #$00                        ; $E1CD
    lda (P2),y                      ; $E1CF
    clc                             ; $E1D1
    sbc AUX                         ; $E1D2
    sta P2                          ; $E1D4
    rts                             ; $E1D6

;; String comparison with = (token $39): replaces two strings with 1 if they are the same, 0 if not.
;;
;; The strings are compared a character at a time over their ranges; they are equal only if both ranges run out
;; together.
;; In: X = the noun stack: two strings, each a range above an address
;; Out: X = the noun stack, its top entry the result
;; See: <NE_STR>
EQ_STR:
    lda NOUNSTKL+3,x                ; $E1D7
    sta ACC                         ; $E1D9
    lda NOUNSTKH+3,x                ; $E1DB
    sta ACC+1                       ; $E1DD
    lda NOUNSTKL+1,x                ; $E1DF
    sta AUX                         ; $E1E1
    lda NOUNSTKH+1,x                ; $E1E3
    sta AUX+1                       ; $E1E5
    inx                             ; $E1E7
    inx                             ; $E1E8
    inx                             ; $E1E9 pop to the result entry
    ldy #$00                        ; $E1EA
    sty NOUNSTKH,x                  ; $E1EC
    sty NOUNSTKC,x                  ; $E1EE the result is a number
    iny                             ; $E1F0
    sty NOUNSTKL,x                  ; $E1F1 1: equal so far

;; Compares the next pair of characters.
EQ_STR_1:
    lda NOUNSTKL-3,x                ; $E1F3
    cmp NOUNSTKH-3,x                ; $E1F5 the first string's range
    php                             ; $E1F7
    pha                             ; $E1F8
    lda NOUNSTKL-1,x                ; $E1F9
    cmp NOUNSTKH-1,x                ; $E1FB the second string's range
    bcc EQ_STR_4                    ; $E1FD the second has a character left
    pla                             ; $E1FF
    plp                             ; $E200
    bcs EQ_STR_3                    ; $E201 both ran out together: equal

;; The strings differ: the result becomes 0.
EQ_STR_2:
    lsr NOUNSTKL,x                  ; $E203

EQ_STR_3:
    rts                             ; $E205

EQ_STR_4:
    tay                             ; $E206
    lda (ACC),y                     ; $E207
    sta P2                          ; $E209
    pla                             ; $E20B
    tay                             ; $E20C
    plp                             ; $E20D
    bcs EQ_STR_2                    ; $E20E the first ran out first
    lda (AUX),y                     ; $E210
    cmp P2                          ; $E212
    bne EQ_STR_2                    ; $E214
    inc NOUNSTKL-1,x                ; $E216
    inc NOUNSTKL-3,x                ; $E218
    bcs EQ_STR_1                    ; $E21A

;; String comparison with # (token $3A, not equal): the opposite of <EQ_STR>.
NE_STR:
    jsr EQ_STR                      ; $E21C
    jmp NOT                         ; $E21F

;; Multiplication (token $14): replaces the top two numbers with their product.
;;
;; <MDARGS> makes both numbers positive and keeps the product's sign. The product is built a bit of the multiplier at
;; a time, from the top: the partial product doubles each step and gains the multiplicand when the bit is 1.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, its top entry the product
;; Errors: >32767 if the product does not fit in 15 bits
;; Uses: A, Y, ACC, AUX, P2, P3
;; See: <MDARGS>, <MultEnd>
MULT:
    jsr MDARGS                      ; $E222

MULT_1:
    asl ACC                         ; $E225
    rol ACC+1                       ; $E227 the multiplier's next bit, from the top
    bcc MULT_2                      ; $E229
    clc                             ; $E22B add the multiplicand
    lda P3                          ; $E22C
    adc AUX                         ; $E22E
    sta P3                          ; $E230
    lda P3+1                        ; $E232
    adc AUX+1                       ; $E234
    sta P3+1                        ; $E236

MULT_2:
    dey                             ; $E238
    beq MultEnd                     ; $E239
    asl P3                          ; $E23B
    rol P3+1                        ; $E23D
    bpl MULT_1                      ; $E23F the product must stay below $8000
    jmp Err32767                    ; $E241

;; Pushes <P3> as the result, negated when the sign kept in <P2>+1 says so.
;;
;; MOD and division end here too.
;; In: P3 = the magnitude, P2+1 = bit 7 set for a negative result
MultEnd:
    lda P3                          ; $E244
    jsr PUSHNOUN                    ; $E246
    lda P3+1                        ; $E249 Y = 0: a number
    sta NOUNSTKC,x                  ; $E24B
    asl P2+1                        ; $E24D
    bcc POPABS_2                    ; $E24F
    jmp NEGATE                      ; $E251

;; Takes two numbers off the noun stack as positive values for multiplication or division.
;;
;; <P2>+1 starts as $55 (%01010101) and is shifted left for each negative operand, so its top bit, set after one
;; shift and clear after none or two, ends up as the sign of the result.
;; Out: AUX = the top number's magnitude, ACC = the one below's magnitude, P3 = 0, Y = 16 (the bits to work)
;; Uses: A, X (both popped), P2+1
MDARGS:
    lda #$55                        ; $E254
    sta P2+1                        ; $E256
    jsr POPABS                      ; $E258

;; Moves ACC to AUX and takes the next number off the noun stack into ACC, made positive.
POPABS:
    lda ACC                         ; $E25B
    sta AUX                         ; $E25D
    lda ACC+1                       ; $E25F
    sta AUX+1                       ; $E261
    jsr GET16BIT                    ; $E263
    sty P3                          ; $E266
    sty P3+1                        ; $E268
    lda ACC+1                       ; $E26A
    bpl POPABS_1                    ; $E26C
    dex                             ; $E26E negative: push it back
    asl P2+1                        ; $E26F one more negative operand
    jsr NEGATE                      ; $E271 negate it on the stack and take it again
    jsr GET16BIT                    ; $E274

POPABS_1:
    ldy #$10                        ; $E277

POPABS_2:
    rts                             ; $E279

;; MOD (token $1F): replaces two numbers with the remainder of dividing the lower by the top.
;;
;; <DIVMOD> divides, leaving the remainder in P3 and Y = 0, so the branch always goes to <MultEnd>.
;; In: X = the noun stack: two numbers
;; Out: X = the noun stack, its top entry the remainder
;; See: <DIVMOD>, <DIVIDE>
MOD:
    jsr DIVMOD                      ; $E27A
    beq MultEnd                     ; $E27D
    .byte $FF                       ; $E27F an unused byte

;; Reads a line for INPUT of numbers into <IN>, with the ? prompt.
;; Out: X = the index of the return that ends the line
;; See: <GETCMD>, <INPUTNUMLN>
GETQLINE:
    inc PROMPT                      ; $E280
    ldy #$00                        ; $E282
    jsr GETCMD                      ; $E284
    dec PROMPT                      ; $E287
    rts                             ; $E289

;; SCRN( (token $3D): replaces a column and a row with the color of that lo-res block, 0 to 15.
;;
;; A text byte holds two lo-res blocks: the even row in the low nibble, the odd row in the high nibble. The row
;; is not checked against the screen.
;; In: X = the noun stack: the column, then the row on top
;; Out: X = the noun stack, its top entry the color
;; See: <COMMA_SCRN>, <GBASCALC>
SCRN:
    jsr GETBYTE                     ; $E28A
    lsr a                           ; $E28D
    php                             ; $E28E carry = the row's lowest bit
    jsr GBASCALC                    ; $E28F
    jsr GETBYTE                     ; $E292
    tay                             ; $E295
    lda (GBASL),y                   ; $E296
    plp                             ; $E298
    bcc SCRN_1                      ; $E299
    lsr a                           ; $E29B
    lsr a                           ; $E29C odd row: the upper nibble
    lsr a                           ; $E29D
    lsr a                           ; $E29E

SCRN_1:
    and #$0F                        ; $E29F
    ldy #$00                        ; $E2A1
    jsr PUSHNOUN                    ; $E2A3
    sty NOUNSTKC,x                  ; $E2A6
    dey                             ; $E2A8 PRFLAG = $FF, as a left parenthesis sets it
    sty PRFLAG                      ; $E2A9

;; The comma of SCRN( (token $3E): nothing to do, as <SCRN> takes both numbers.
COMMA_SCRN:
    rts                             ; $E2AB
    .byte $FF, $FF, $FF, $FF        ; $E2AC unused bytes
