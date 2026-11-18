;; The assembler: its mnemonic and opcode tables, and the code that assembles the text between [ and ] ($8451-$8820).
;;
;; - <MNEMONIC_LOW>, <MNEMONIC_HIGH> and <MNEMONIC_OPCODES>: the 58 mnemonics BASIC knows, packed into 15 bits each,
;;   and each one's base opcode, laid out by <ASSEMBLER_MNEMONICS>.
;; - <ASSEMBLER_START>, run by [, which assembles one statement at a time and lists it, and <ASSEMBLER_EXIT>, run
;;   by ], which goes back to BASIC.
;; - <ASSEMBLE_LABEL> and <ASSEMBLE_INSTRUCTION>, which read a statement's label and mnemonic, and the routines after
;;   them that read each kind of operand and add to the base opcode the offset of the addressing mode it gives.
;; - <ASSEMBLER_STORE>, which puts the bytes at P%, or at O% with OPT bit 2, and moves the two on.
;;
;; EQU (EQUB, EQUW, EQUD and EQUS) is assembled at <ASSEMBLE_EQU>, and the helpers that evaluate an operand and add to
;; the opcode are at <EVALUATE_INTEGER_A> and <ADD_16_TO_OPCODE>.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

ERROR_OUT_OF_RANGE = $01            ;; error 1, "Out of range": a branch's destination is too far away
ERROR_BYTE = $02                    ;; error 2, "Byte": an immediate or zero page operand above 255
ERROR_INDEX = $03                   ;; error 3, "Index": an indexed or indirect operand of a form the instruction lacks

; The parts of the assembler's work bytes that it uses for one purpose while it assembles a statement.
ASSEMBLER_ADDRESS = WORK            ;; P% before the statement, the address it is assembled for, which the listing shows
ASSEMBLER_COUNT = WORK + 2          ;; the number of bytes the statement assembles, or &FF for EQUS's string
ASSEMBLER_DESTINATION = WORK + 3    ;; where the bytes go, two bytes: P%, or O% with OPT bit 2
PACKED_MNEMONIC = FP_B_EXPONENT     ;; the mnemonic read, packed as <MNEMONIC> packs it, two bytes, low first
LISTING_INDENT = FP_B_MANTISSA + 1  ;; the column the listing's continuation lines of bytes start at

; The bits of OPT.
OPT_LIST = %001                     ;; OPT bit 0: list each statement as it is assembled
OPT_ERRORS = %010                   ;; OPT bit 1: report errors, and make an unknown variable an error
OPT_OFFSET = %100                   ;; OPT bit 2: put the bytes at O% instead of P%

; ---------------------------------------------------------------------------------------------------------------------
; The mnemonic tables
; ---------------------------------------------------------------------------------------------------------------------

; The tables <ASSEMBLER_MNEMONICS> lays out, one for each part of a mnemonic's entry.
MNEMONIC_PART_LOW = 0               ;; the low bytes of the packed mnemonics
MNEMONIC_PART_HIGH = 1              ;; the high bytes of the packed mnemonics
MNEMONIC_PART_OPCODE = 2            ;; the base opcodes

;; The number of mnemonics <MNEMONIC> has numbered so far; 58 once <MNEMONIC_LOW> is laid out.
.set MNEMONIC_COUNT, 0

;; The mnemonic <MNEMONIC> is laying out, packed into 15 bits.
.set MNEMONIC_PACKED, 0

;; Lays out a mnemonic's byte in one of the three mnemonic tables: <MNEMONIC_LOW>, <MNEMONIC_HIGH> or
;; <MNEMONIC_OPCODES>.
;;
;; A mnemonic's three letters are packed into 15 bits, as <ASSEMBLE_INSTRUCTION> packs the letters it reads, five
;; bits for each: its code's low five bits, 1 for A to 26 for Z. The first letter's are bits 10-14, the second's bits
;; 5-9 and the third's bits 0-4; bit 15 is clear.
;;
;; In the low table the macro also numbers the mnemonic, from 1, defining MNEMONIC_ and the mnemonic (MNEMONIC_BCC)
;; as its number: the index in X with which the assembler reads its entries and picks how to read its operand.
;; Parameters:
;;   part = the table: <MNEMONIC_PART_LOW>, <MNEMONIC_PART_HIGH> or <MNEMONIC_PART_OPCODE>
;;   text = the mnemonic, three capitals
;;   opcode = its base opcode, or nothing for OPT and EQU, which have none in the table
.macro MNEMONIC part, text, opcode
.set MNEMONIC_PACKED, ((.strat(text, 0) & $1F) << 10) | ((.strat(text, 1) & $1F) << 5) | (.strat(text, 2) & $1F)
.if part = MNEMONIC_PART_LOW
.set MNEMONIC_COUNT, MNEMONIC_COUNT + 1
.ident(.concat("MNEMONIC_", text)) = MNEMONIC_COUNT
    .byte <MNEMONIC_PACKED
.elseif part = MNEMONIC_PART_HIGH
    .byte >MNEMONIC_PACKED
.else
.ifnblank opcode
    .byte opcode
.endif
.endif
.endmacro

;; Lays out one of the three mnemonic tables, a byte for each mnemonic in the order the assembler numbers them.
;;
;; The mnemonics are in groups that take the same operands, and the assembler picks the group by comparing the
;; mnemonic's number with the first of each. The base opcode is the one the assembler adds an addressing mode's
;; offset to: the instruction itself for the implied instructions, the branches, JMP and JSR; the (zp,X) form for
;; ORA to SBC and STA; the zero page form for the shifts, DEC, INC, STX and STY; the immediate form for CPX, CPY,
;; LDX and LDY; and BIT's &20, four below its zero page form, for BIT.
;; Parameters:
;;   part = the table: <MNEMONIC_PART_LOW>, <MNEMONIC_PART_HIGH> or <MNEMONIC_PART_OPCODE>
.macro ASSEMBLER_MNEMONICS part
    ; The instructions with no operand, &01-&19.
    MNEMONIC part, "BRK", $00
    MNEMONIC part, "CLC", $18
    MNEMONIC part, "CLD", $D8
    MNEMONIC part, "CLI", $58
    MNEMONIC part, "CLV", $B8
    MNEMONIC part, "DEX", $CA
    MNEMONIC part, "DEY", $88
    MNEMONIC part, "INX", $E8
    MNEMONIC part, "INY", $C8
    MNEMONIC part, "NOP", $EA
    MNEMONIC part, "PHA", $48
    MNEMONIC part, "PHP", $08
    MNEMONIC part, "PLA", $68
    MNEMONIC part, "PLP", $28
    MNEMONIC part, "RTI", $40
    MNEMONIC part, "RTS", $60
    MNEMONIC part, "SEC", $38
    MNEMONIC part, "SED", $F8
    MNEMONIC part, "SEI", $78
    MNEMONIC part, "TAX", $AA
    MNEMONIC part, "TAY", $A8
    MNEMONIC part, "TSX", $BA
    MNEMONIC part, "TXA", $8A
    MNEMONIC part, "TXS", $9A
    MNEMONIC part, "TYA", $98
    ; The branches, &1A-&21.
    MNEMONIC part, "BCC", $90
    MNEMONIC part, "BCS", $B0
    MNEMONIC part, "BEQ", $F0
    MNEMONIC part, "BMI", $30
    MNEMONIC part, "BNE", $D0
    MNEMONIC part, "BPL", $10
    MNEMONIC part, "BVC", $50
    MNEMONIC part, "BVS", $70
    ; Immediate, zero page, absolute, indexed and indirect, from (zp,X), &22-&28. AND, EOR and OR are tokens.
    MNEMONIC part, "AND", $21
    MNEMONIC part, "EOR", $41
    MNEMONIC part, "ORA", $01
    MNEMONIC part, "ADC", $61
    MNEMONIC part, "CMP", $C1
    MNEMONIC part, "LDA", $A1
    MNEMONIC part, "SBC", $E1
    ; The shifts, with A, zero page and absolute, and X indexed; then DEC and INC, &29-&2E.
    MNEMONIC part, "ASL", $06
    MNEMONIC part, "LSR", $46
    MNEMONIC part, "ROL", $26
    MNEMONIC part, "ROR", $66
    MNEMONIC part, "DEC", $C6
    MNEMONIC part, "INC", $E6
    ; Immediate, zero page and absolute, &2F-&30; then BIT, zero page and absolute, &31.
    MNEMONIC part, "CPX", $E0
    MNEMONIC part, "CPY", $C0
    MNEMONIC part, "BIT", $20
    ; Absolute, and for JMP indirect, &32-&33.
    MNEMONIC part, "JMP", $4C
    MNEMONIC part, "JSR", $20
    ; Immediate, zero page, absolute, and indexed by the other index register, &34-&35.
    MNEMONIC part, "LDX", $A2
    MNEMONIC part, "LDY", $A0
    ; As ORA to SBC but with no immediate form, &36.
    MNEMONIC part, "STA", $81
    ; Zero page, absolute, and zero page indexed by the other index register, &37-&38.
    MNEMONIC part, "STX", $86
    MNEMONIC part, "STY", $84
    ; The directives, &39-&3A, which have no opcode in the table.
    MNEMONIC part, "OPT"
    MNEMONIC part, "EQU"
.endmacro

;; The low bytes of the packed mnemonics, from BRK's, numbered from 1.
;;
;; <ASSEMBLE_INSTRUCTION> searches it backwards, from EQU's entry at X = &3A down to BRK's at X = 1, reading
;; MNEMONIC_LOW-1,x, so that the byte before the table, the last of <TOKEN_ROUTINES_HIGH>, is never read. When the low
;; byte matches, it compares the high byte in <MNEMONIC_HIGH>.
;; See: <MNEMONIC>, <ASSEMBLER_MNEMONICS>
MNEMONIC_LOW:
    ASSEMBLER_MNEMONICS MNEMONIC_PART_LOW

;; The high bytes of the packed mnemonics, laid out as <MNEMONIC_LOW>.
;; See: <MNEMONIC_LOW>
MNEMONIC_HIGH:
    ASSEMBLER_MNEMONICS MNEMONIC_PART_HIGH
    .assert MNEMONIC_HIGH - MNEMONIC_LOW = MNEMONIC_COUNT, "MNEMONIC_LOW has a byte for each mnemonic."
    .assert * - MNEMONIC_HIGH = MNEMONIC_COUNT, "MNEMONIC_HIGH has a byte for each mnemonic."

;; The base opcodes of the mnemonics, laid out as <MNEMONIC_LOW>, which the assembler adds an addressing mode's
;; offset to.
;;
;; OPT and EQU have no entry: their numbers would read the first two bytes of <ASSEMBLER_EXIT>, which follows, and
;; <ASSEMBLE_INSTRUCTION> does put one of those in <OPCODE>, but OPT stores nothing and EQU overwrites it.
;; See: <ASSEMBLER_MNEMONICS>
MNEMONIC_OPCODES:
    ASSEMBLER_MNEMONICS MNEMONIC_PART_OPCODE
    .assert * - MNEMONIC_OPCODES = MNEMONIC_OPT - 1, "MNEMONIC_OPCODES ends before OPT's entry."

; ---------------------------------------------------------------------------------------------------------------------
; [ and ]
; ---------------------------------------------------------------------------------------------------------------------

;; ]: leaves the assembler and goes on running the statements after it.
;;
;; OPT is set back to &FF, its value outside the assembler. Its bit 1 is set, so an unknown variable is an error;
;; inside the assembler, with bit 1 clear, an unknown variable reads as P% instead (see <EVALUATE_FACTOR_UNKNOWN>).
;; See: <ASSEMBLER_START>
ASSEMBLER_EXIT:
    lda #$FF
    sta OPT
    jmp EXECUTE_STATEMENT

;; [: assembles the statements that follow, up to ], listing each as OPT asks.
;;
;; The statement loop comes here from <STATEMENT_NOT_VARIABLE> when a statement starts with [. OPT starts at 3, which
;; lists the code and reports errors, until an OPT statement changes it. An assembler statement runs to a colon or the
;; end of the line, and is empty, a comment after \, a label (. and a variable name, set to P%), an instruction, or OPT
;; or EQU; a label may be followed by any of the others. Anything after an instruction's operand is skipped, so a
;; comment can follow it without a \. At the end of a program line the assembler goes on to the next line; at the end of
;; a line typed in immediate mode it goes back to <IMMEDIATE_MODE>.
;;
;; With OPT bit 0 set, each statement is listed: P% before it in hexadecimal, the bytes it assembled, three to a line,
;; padded so that the text starts in the same column, then the statement's text, with its tokens printed as keywords.
;; The bytes listed are read back from where they were put, at P% or at O%.
;;
;; Errors: those of <ASSEMBLE_INSTRUCTION>
;; Entry: ASSEMBLER_NEXT_STATEMENT = assembles the next statement, at PTR_A_OFFSET in the text at PTR_A
ASSEMBLER_START:
    lda #OPT_LIST | OPT_ERRORS
    sta OPT
ASSEMBLER_NEXT_STATEMENT:
    jsr GET_CHARACTER_A
    cmp #']'
    beq ASSEMBLER_EXIT
    jsr ADVANCE_PTR_A                       ; PTR_A moves to the statement's first character, with PTR_A_OFFSET 1
    dec PTR_A_OFFSET
    jsr ASSEMBLE_INSTRUCTION
    dec PTR_A_OFFSET                ; back to the character that ended the operand
    lda OPT
    lsr a                           ; carry = OPT_LIST
    bcc ASSEMBLER_SKIP_STATEMENT
    lda COUNT
    adc #$04                        ; with the carry: the column after the address and its space
    sta LISTING_INDENT
    lda ASSEMBLER_ADDRESS+1
    jsr PRINT_HEX_BYTE
    lda ASSEMBLER_ADDRESS
    jsr PRINT_HEX_BYTE_SPACE                       ; the low byte and a space
    ldx #$FC                        ; counts up to zero after the third byte on a line
    ldy ASSEMBLER_COUNT
    bpl ASSEMBLER_LIST_COUNT
    ldy STRING_LENGTH               ; EQUS: the string's length
ASSEMBLER_LIST_COUNT:
    sty ASSEMBLER_ADDRESS+1         ; now the count of bytes still to list
    beq ASSEMBLER_LIST_PAD
    ldy #$00
ASSEMBLER_LIST_BYTE_LOOP:
    inx
    bne ASSEMBLER_LIST_BYTE
    jsr PRINT_NEWLINE               ; a fourth byte starts a new line, indented under the first
    ldx LISTING_INDENT
ASSEMBLER_LIST_INDENT:
    jsr PRINT_SPACE
    dex
    bne ASSEMBLER_LIST_INDENT
    ldx #$FD
ASSEMBLER_LIST_BYTE:
    lda (ASSEMBLER_DESTINATION),y
    jsr PRINT_HEX_BYTE_SPACE
    iny
    dec ASSEMBLER_ADDRESS+1
    bne ASSEMBLER_LIST_BYTE_LOOP
ASSEMBLER_LIST_PAD:
    inx                             ; three spaces for each byte the line lacks
    bpl ASSEMBLER_LIST_TEXT
    jsr PRINT_SPACE
    jsr PRINT_CHARACTER             ; A is still a space
    jsr PRINT_CHARACTER
    jmp ASSEMBLER_LIST_PAD
ASSEMBLER_LIST_TEXT:
    ldy #$00
ASSEMBLER_LIST_TEXT_LOOP:
    lda (PTR_A),y
    cmp #':'
    beq ASSEMBLER_LIST_COLON
    cmp #CARRIAGE_RETURN
    beq ASSEMBLER_LIST_END
ASSEMBLER_LIST_CHARACTER:
    jsr PRINT_CHARACTER_OR_TOKEN
    iny
    bne ASSEMBLER_LIST_TEXT_LOOP
ASSEMBLER_LIST_COLON:
    cpy PTR_A_OFFSET                ; a colon before the operand's end is in a string
    bcc ASSEMBLER_LIST_CHARACTER
ASSEMBLER_LIST_END:
    jsr PRINT_NEWLINE
ASSEMBLER_SKIP_STATEMENT:
    ldy PTR_A_OFFSET
    dey
ASSEMBLER_SKIP_LOOP:
    iny
    lda (PTR_A),y
    cmp #':'
    beq ASSEMBLER_STATEMENT_END
    cmp #CARRIAGE_RETURN
    bne ASSEMBLER_SKIP_LOOP
ASSEMBLER_STATEMENT_END:
    jsr CHECK_END_OF_STATEMENT_Y                       ; PTR_A moves to the colon or return, with PTR_A_OFFSET 1
    dey
    lda (PTR_A),y
    cmp #':'
    beq ASSEMBLER_CONTINUE
    lda PTR_A+1
    cmp #>LINE_BUFFER
    bne ASSEMBLER_NEXT_LINE
    jmp IMMEDIATE_MODE
ASSEMBLER_NEXT_LINE:
    jsr MOVE_TO_NEXT_LINE                       ; the next line of the program
ASSEMBLER_CONTINUE:
    jmp ASSEMBLER_NEXT_STATEMENT

; ---------------------------------------------------------------------------------------------------------------------
; Labels and mnemonics
; ---------------------------------------------------------------------------------------------------------------------

;; Assembles a statement that starts with a label: sets the variable named after the . to P%, then assembles the
;; rest of the statement.
;;
;; The variable is made if it does not exist yet. Falls into <ASSEMBLE_INSTRUCTION>.
;; In: PTR_A = the text, PTR_A_OFFSET = the offset of the label's name, after the .
;; Errors: "Syntax error", when the label is not a variable, or is a string variable
ASSEMBLE_LABEL:
    jsr FIND_OR_CREATE_VARIABLE
    beq ASSEMBLE_INSTRUCTION_SYNTAX_ERROR
    bcs ASSEMBLE_INSTRUCTION_SYNTAX_ERROR
    jsr PUSH_INTEGER                ; the variable's address and type
    jsr LOAD_P_PERCENT                       ; P% into IntA
    sta EXPRESSION_TYPE
    jsr ASSIGN_NUMBER
    jsr SET_PTR_A_OFFSET_FROM_B                       ; PTR_A_OFFSET moves past the name

;; Assembles one assembler statement: reads its mnemonic and operand and stores the bytes they make.
;;
;; A colon, carriage return or \ (a comment) assembles nothing; a . is a label, for <ASSEMBLE_LABEL>. Otherwise up to
;; three letters are read and packed as <MNEMONIC> packs them, and the packed value is looked for in
;; <MNEMONIC_LOW> and <MNEMONIC_HIGH>. AND, EOR and OR are tokens in the text, so a token is taken as the mnemonic
;; with the same letters, OR only when A follows it. The mnemonic's number in X picks the routine that reads the
;; operand, each of which adds an addressing mode's offset to the base opcode in <OPCODE> and stores the
;; instruction. The implied instructions, numbers below MNEMONIC_BCC, fall into <ASSEMBLER_STORE> as they are.
;; In: PTR_A = the text, PTR_A_OFFSET = the offset of the statement
;; Out: P_PERCENT = moved past the bytes, O_PERCENT = moved past them too with OPT bit 2, PTR_A_OFFSET = past the
;;   operand, ASSEMBLER_ADDRESS = P% before the bytes, ASSEMBLER_COUNT = their number,
;;   ASSEMBLER_DESTINATION = where they were put
;; Errors: "Syntax error", for an unknown mnemonic, and those of the operand routines after it
;; Entry: ASSEMBLE_INSTRUCTION_SYNTAX_ERROR = raises Syntax error
ASSEMBLE_INSTRUCTION:
    ldx #$03                        ; three letters
    jsr GET_CHARACTER_A
    ldy #$00                        ; no bytes, for an empty statement
    sty PACKED_MNEMONIC
    cmp #':'
    beq ASSEMBLER_STORE
    cmp #CARRIAGE_RETURN
    beq ASSEMBLER_STORE
    cmp #'\'
    beq ASSEMBLER_STORE
    cmp #'.'
    beq ASSEMBLE_LABEL
    dec PTR_A_OFFSET
ASSEMBLE_INSTRUCTION_LETTER:
    ldy PTR_A_OFFSET
    inc PTR_A_OFFSET
    lda (PTR_A),y
    bmi ASSEMBLE_INSTRUCTION_TOKEN
    cmp #' '
    beq ASSEMBLE_INSTRUCTION_SEARCH
    ldy #$05
    asl a                           ; drop the top three bits
    asl a
    asl a
ASSEMBLE_INSTRUCTION_PACK:
    asl a                           ; shift the letter's five bits into the packed value
    rol PACKED_MNEMONIC
    rol PACKED_MNEMONIC+1
    dey
    bne ASSEMBLE_INSTRUCTION_PACK
    dex
    bne ASSEMBLE_INSTRUCTION_LETTER
ASSEMBLE_INSTRUCTION_SEARCH:
    ldx #MNEMONIC_EQU               ; the last mnemonic
    lda PACKED_MNEMONIC
ASSEMBLE_INSTRUCTION_SEARCH_LOOP:
    cmp MNEMONIC_LOW-1,x
    bne ASSEMBLE_INSTRUCTION_NEXT
    ldy MNEMONIC_HIGH-1,x
    cpy PACKED_MNEMONIC+1
    beq ASSEMBLE_INSTRUCTION_FOUND
ASSEMBLE_INSTRUCTION_NEXT:
    dex
    bne ASSEMBLE_INSTRUCTION_SEARCH_LOOP
ASSEMBLE_INSTRUCTION_SYNTAX_ERROR:
    jmp SYNTAX_ERROR
ASSEMBLE_INSTRUCTION_TOKEN:
    ldx #MNEMONIC_AND
    cmp #TOKEN_AND
    beq ASSEMBLE_INSTRUCTION_FOUND
    inx                             ; MNEMONIC_EOR
    cmp #TOKEN_EOR
    beq ASSEMBLE_INSTRUCTION_FOUND
    inx                             ; MNEMONIC_ORA
    cmp #TOKEN_OR
    bne ASSEMBLE_INSTRUCTION_SYNTAX_ERROR
    inc PTR_A_OFFSET
    iny
    lda (PTR_A),y
    cmp #'A'
    bne ASSEMBLE_INSTRUCTION_SYNTAX_ERROR
ASSEMBLE_INSTRUCTION_FOUND:
    lda MNEMONIC_OPCODES-1,x
    sta OPCODE
    ldy #$01                        ; one byte, for an implied instruction
    cpx #MNEMONIC_BCC
    bcs ASSEMBLE_BRANCH
    .assert (MNEMONIC_EOR = MNEMONIC_AND + 1) & (MNEMONIC_ORA = MNEMONIC_EOR + 1), "AND, EOR and ORA are in order."

;; Stores the instruction or data the statement assembled at P%, or at O% with OPT bit 2, and moves P% (and O%) on.
;;
;; The bytes come from <OPCODE> and the two bytes after it, IntA's low bytes, or for EQUS from <STRING_BUFFER>.
;; Before storing them it sets <ASSEMBLER_ADDRESS>, <ASSEMBLER_COUNT> and <ASSEMBLER_DESTINATION> for the listing,
;; even when there are none. EQU (at <ASSEMBLE_EQU_STORE>) comes here too.
;; In: Y = the number of bytes, 0-4, or &FF for StrA's string, OPCODE and INT_A = the bytes
;; Out: P_PERCENT, O_PERCENT, ASSEMBLER_ADDRESS, ASSEMBLER_COUNT, ASSEMBLER_DESTINATION
;; Uses: A, X, Y
ASSEMBLER_STORE:
    lda P_PERCENT
    sta ASSEMBLER_ADDRESS
    sty ASSEMBLER_COUNT
    ldx OPT
    cpx #OPT_OFFSET                 ; carry = set to put the bytes at O%, kept through the loop
    ldx P_PERCENT+1
    stx ASSEMBLER_ADDRESS+1
    bcc ASSEMBLER_STORE_DESTINATION
    lda O_PERCENT
    ldx O_PERCENT+1
ASSEMBLER_STORE_DESTINATION:
    sta ASSEMBLER_DESTINATION
    stx ASSEMBLER_DESTINATION+1
    tya
    beq ASSEMBLER_STORE_DONE
    bpl ASSEMBLER_STORE_LOOP
    ldy STRING_LENGTH
    beq ASSEMBLER_STORE_DONE
ASSEMBLER_STORE_LOOP:
    dey                             ; the last byte first
    lda a:OPCODE,y
    bit ASSEMBLER_COUNT
    bpl ASSEMBLER_STORE_BYTE
    lda STRING_BUFFER,y
ASSEMBLER_STORE_BYTE:
    sta (ASSEMBLER_DESTINATION),y
    inc P_PERCENT
    bne ASSEMBLER_STORE_OFFSET
    inc P_PERCENT+1
ASSEMBLER_STORE_OFFSET:
    bcc ASSEMBLER_STORE_NEXT
    inc O_PERCENT
    bne ASSEMBLER_STORE_NEXT
    inc O_PERCENT+1
ASSEMBLER_STORE_NEXT:
    tya
    bne ASSEMBLER_STORE_LOOP
ASSEMBLER_STORE_DONE:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The operands
; ---------------------------------------------------------------------------------------------------------------------

;; Assembles a branch, BCC to BVS, with its operand: the destination's address, as a byte relative to the next
;; instruction.
;;
;; A destination more than 128 bytes back or 127 forward is error 1, "Out of range", unless OPT is 0 or 1; then the
;; offset is assembled as 0, so that a first pass can run before every label is known. OPT 4 and 5 still report
;; it, since the test is on OPT's bits 1 and 2 together. Numbers from <MNEMONIC_AND> go on to <ASSEMBLE_GROUP_ONE>.
;; In: X = the mnemonic's number, OPCODE = the branch
;; Errors: "Out of range"
ASSEMBLE_BRANCH:
    cpx #MNEMONIC_AND
    bcs ASSEMBLE_GROUP_ONE
    jsr EVALUATE_INTEGER_A                       ; the destination, in IntA
    clc
    lda INT_A
    sbc P_PERCENT                   ; less P%, less 1
    tay
    lda INT_A+1
    sbc P_PERCENT+1
    cpy #$01
    dey                             ; less 1 more: the offset from P% + 2, in A and Y
    sbc #$00
    beq ASSEMBLE_BRANCH_FORWARD
    cmp #$FF
    beq ASSEMBLE_BRANCH_BACKWARD
ASSEMBLE_BRANCH_OUT_OF_RANGE:
    lda OPT
    lsr a
    beq ASSEMBLE_BRANCH_IGNORE
    brk
    .byte ERROR_OUT_OF_RANGE
    .byte "Out of range",0
ASSEMBLE_BRANCH_IGNORE:
    tay                             ; an offset of 0
ASSEMBLE_BRANCH_OFFSET:
    sty INT_A

;; Stores the opcode and the low byte of IntA, an instruction with a one-byte operand.
;;
;; The branch's range checks, for <ASSEMBLE_BRANCH>, follow it.
;; In: OPCODE = the opcode, INT_A = the operand
;; See: <ASSEMBLER_STORE>
STORE_TWO_BYTES:
    ldy #$02
    jmp ASSEMBLER_STORE
ASSEMBLE_BRANCH_BACKWARD:
    tya
    bmi ASSEMBLE_BRANCH_OFFSET
    bpl ASSEMBLE_BRANCH_OUT_OF_RANGE  ; always taken
ASSEMBLE_BRANCH_FORWARD:
    tya
    bpl ASSEMBLE_BRANCH_OFFSET
    bmi ASSEMBLE_BRANCH_OUT_OF_RANGE  ; always taken

;; Assembles AND, EOR, ORA, ADC, CMP, LDA or SBC with its operand, any addressing mode but implied.
;;
;; # is the immediate form; any other operand goes to <ASSEMBLE_GROUP_ONE_MEMORY>, as STA's does. Numbers from
;; <MNEMONIC_ASL> go on to <ASSEMBLE_STA>.
;; In: X = the mnemonic's number, OPCODE = its (zp,X) form
ASSEMBLE_GROUP_ONE:
    cpx #MNEMONIC_ASL
    bcs ASSEMBLE_STA
    jsr GET_CHARACTER_A
    cmp #'#'
    bne ASSEMBLE_GROUP_ONE_MEMORY
    jsr ADD_8_TO_OPCODE                       ; +8, the immediate form

;; Assembles an immediate operand: the expression after the #, which must be a byte.
;;
;; In: OPCODE = the immediate form
;; Errors: "Byte", when the operand is above 255
;; Entry: ASSEMBLE_BYTE_OPERAND = stores OPCODE and the byte in IntA, checking it is one; ASSEMBLE_BYTE_ERROR = raises
;;   "Byte"
ASSEMBLE_IMMEDIATE:
    jsr EVALUATE_INTEGER_A
ASSEMBLE_BYTE_OPERAND:
    lda INT_A+1
    beq STORE_TWO_BYTES
ASSEMBLE_BYTE_ERROR:
    brk
    .byte ERROR_BYTE
    .byte "Byte",0

;; Assembles STA with its operand: any of ORA's addressing modes but immediate.
;;
;; Numbers above STA's go on to <ASSEMBLE_SHIFT>.
;;
;; From ASSEMBLE_GROUP_ONE_MEMORY it reads the operand of any of these instructions: ( starts (zp,X) or (zp),Y, and
;; anything else is an address, for <ASSEMBLE_GROUP_ONE_ADDRESS>.
;; In: X = the mnemonic's number, OPCODE = the (zp,X) form
;; Errors: "Index", for an indirect operand of another form, and "Byte", for an indirect address above 255
;; Entry: ASSEMBLE_GROUP_ONE_MEMORY = reads the operand of any of them, with its first character in A
ASSEMBLE_STA:
    cpx #MNEMONIC_STA
    bne ASSEMBLE_SHIFT
    jsr GET_CHARACTER_A
ASSEMBLE_GROUP_ONE_MEMORY:
    cmp #'('
    bne ASSEMBLE_GROUP_ONE_ADDRESS
    jsr EVALUATE_INTEGER_A
    jsr GET_CHARACTER_A
    cmp #')'
    bne ASSEMBLE_INDEXED_INDIRECT
    jsr GET_CHARACTER_A             ; (zp),Y
    cmp #','
    bne ASSEMBLE_INDEX_ERROR
    jsr ADD_16_TO_OPCODE                       ; +16, the (zp),Y form
    jsr GET_CHARACTER_A
    cmp #'Y'
    bne ASSEMBLE_INDEX_ERROR
    beq ASSEMBLE_BYTE_OPERAND       ; always taken
ASSEMBLE_INDEXED_INDIRECT:
    cmp #','                        ; (zp,X), the base form
    bne ASSEMBLE_INDEX_ERROR
    jsr GET_CHARACTER_A
    cmp #'X'
    bne ASSEMBLE_INDEX_ERROR
    jsr GET_CHARACTER_A
    cmp #')'
    beq ASSEMBLE_BYTE_OPERAND

;; Raises error 3, "Index": an indexed or indirect operand the instruction cannot have.
ASSEMBLE_INDEX_ERROR:
    brk
    .byte ERROR_INDEX
    .byte "Index",0

;; Assembles the address operand of ORA to SBC or STA: zero page or absolute, and indexed by X or Y.
;;
;; A zero page address indexed by Y is assembled as absolute, since these instructions have no zp,Y form.
;; In: OPCODE = the (zp,X) form
;; Errors: "Index", after a comma with neither X nor Y
ASSEMBLE_GROUP_ONE_ADDRESS:
    dec PTR_A_OFFSET
    jsr EVALUATE_INTEGER_A
    jsr GET_CHARACTER_A
    cmp #','
    bne ASSEMBLE_ADDRESS
    jsr ADD_16_TO_OPCODE                       ; +16, the zp,X form less 4
    jsr GET_CHARACTER_A
    cmp #'X'
    beq ASSEMBLE_ADDRESS
    cmp #'Y'
    bne ASSEMBLE_INDEX_ERROR

;; Adds 8 to the opcode and stores it with the two-byte address in IntA.
;;
;; Adding 8 makes a zero page form absolute, and makes the (zp),Y form of ORA to SBC and STA their abs,Y form.
;; In: OPCODE = the opcode less 8, INT_A = the address
ASSEMBLE_ABSOLUTE:
    jsr ADD_8_TO_OPCODE
    jmp ASSEMBLE_THREE_BYTES

;; Adds 4 to the opcode, then stores it with the address in IntA, as zero page when the address is below 256 and as
;; absolute, 8 higher, when it is not.
;; In: OPCODE = the zero page form less 4, INT_A = the address
;; Entry: ASSEMBLE_ADDRESS_SIZE = does not add the 4
ASSEMBLE_ADDRESS:
    jsr ADD_4_TO_OPCODE
ASSEMBLE_ADDRESS_SIZE:
    lda INT_A+1
    bne ASSEMBLE_ABSOLUTE
    jmp STORE_TWO_BYTES

;; Assembles ASL, LSR, ROL, ROR, DEC or INC with its operand: A for the shifts, or zero page or absolute, indexed by
;; X or not.
;;
;; An operand that starts with A is the accumulator, whatever follows. Numbers from <MNEMONIC_CPX> go on to
;; <ASSEMBLE_COMPARE_INDEX>.
;; In: X = the mnemonic's number, OPCODE = the zero page form
;; Errors: "Index", after a comma with no X
ASSEMBLE_SHIFT:
    cpx #MNEMONIC_CPX
    bcs ASSEMBLE_COMPARE_INDEX
    cpx #MNEMONIC_DEC
    bcs ASSEMBLE_SHIFT_ADDRESS
    jsr GET_CHARACTER_A
    cmp #'A'
    beq ASSEMBLE_SHIFT_ACCUMULATOR
    dec PTR_A_OFFSET
ASSEMBLE_SHIFT_ADDRESS:
    jsr EVALUATE_INTEGER_A
    jsr GET_CHARACTER_A
    cmp #','
    bne ASSEMBLE_ADDRESS_SIZE
    jsr ADD_16_TO_OPCODE                       ; +16, the zp,X form
    jsr GET_CHARACTER_A
    cmp #'X'
    beq ASSEMBLE_ADDRESS_SIZE
    jmp ASSEMBLE_INDEX_ERROR
ASSEMBLE_SHIFT_ACCUMULATOR:
    jsr ADD_4_TO_OPCODE                       ; +4, the accumulator form
    ldy #$01
    bne ASSEMBLE_JUMP_STORE         ; always taken

;; Assembles CPX or CPY with an immediate, zero page or absolute operand, or BIT with a zero page or absolute one.
;;
;; Numbers from <MNEMONIC_JMP> go on to <ASSEMBLE_JUMP>.
;; In: X = the mnemonic's number, OPCODE = the immediate form, or &20 for BIT
ASSEMBLE_COMPARE_INDEX:
    cpx #MNEMONIC_JMP
    bcs ASSEMBLE_JUMP
    cpx #MNEMONIC_BIT
    beq ASSEMBLE_COMPARE_INDEX_ADDRESS
    jsr GET_CHARACTER_A
    cmp #'#'
    bne ASSEMBLE_COMPARE_INDEX_UNREAD
    jmp ASSEMBLE_IMMEDIATE
ASSEMBLE_COMPARE_INDEX_UNREAD:
    dec PTR_A_OFFSET
ASSEMBLE_COMPARE_INDEX_ADDRESS:
    jsr EVALUATE_INTEGER_A
    jmp ASSEMBLE_ADDRESS

;; Assembles JMP or JSR with an absolute address, or JMP with an indirect one in brackets.
;;
;; Numbers from <MNEMONIC_LDX> go on to <ASSEMBLE_LOAD_STORE_INDEX>.
;; In: X = the mnemonic's number, OPCODE = the absolute form
;; Errors: "Index", when the indirect address's ) is missing
;; Entry: ASSEMBLE_THREE_BYTES = stores OPCODE and the two bytes of IntA; ASSEMBLE_JUMP_STORE = stores Y bytes
ASSEMBLE_JUMP:
    cpx #MNEMONIC_JSR
    beq ASSEMBLE_JUMP_ADDRESS
    bcs ASSEMBLE_LOAD_STORE_INDEX
    jsr GET_CHARACTER_A
    cmp #'('
    beq ASSEMBLE_JUMP_INDIRECT
    dec PTR_A_OFFSET
ASSEMBLE_JUMP_ADDRESS:
    jsr EVALUATE_INTEGER_A
ASSEMBLE_THREE_BYTES:
    ldy #$03
ASSEMBLE_JUMP_STORE:
    jmp ASSEMBLER_STORE
ASSEMBLE_JUMP_INDIRECT:
    jsr ADD_16_TO_OPCODE                       ; +32, &6C
    jsr ADD_16_TO_OPCODE
    jsr EVALUATE_INTEGER_A
    jsr GET_CHARACTER_A
    cmp #')'
    beq ASSEMBLE_THREE_BYTES
    jmp ASSEMBLE_INDEX_ERROR

;; Assembles LDX, LDY, STX or STY with its operand, which may be indexed by the other index register.
;;
;; The index register is the mnemonic's last letter with its bit 0 changed, Y for LDX and STX, X for LDY and STY,
;; and is compared by its low five bits, so either case will do. LDX and LDY take immediate, zero page and absolute
;; operands, indexed or not; STX and STY take zero page and absolute ones, indexed only on zero page. Numbers from
;; <MNEMONIC_OPT> go on to <ASSEMBLE_DIRECTIVE>.
;; In: X = the mnemonic's number, OPCODE = the immediate form for LDX and LDY, the zero page form for STX and STY
;; Errors: "Index", when the index is the wrong register, and "Byte", for STX or STY indexed above 255
ASSEMBLE_LOAD_STORE_INDEX:
    cpx #MNEMONIC_OPT
    bcs ASSEMBLE_DIRECTIVE
    lda PACKED_MNEMONIC             ; the last letter, in bits 0-4
    eor #$01                        ; X <-> Y
    and #$1F
    pha
    cpx #MNEMONIC_STX
    bcs ASSEMBLE_STORE_INDEX
    jsr GET_CHARACTER_A
    cmp #'#'
    bne ASSEMBLE_LOAD_INDEX_ADDRESS
    pla
    jmp ASSEMBLE_IMMEDIATE
ASSEMBLE_LOAD_INDEX_ADDRESS:
    dec PTR_A_OFFSET
    jsr EVALUATE_INTEGER_A
    pla
    sta WORK                        ; the index register's letter
    jsr GET_CHARACTER_A
    cmp #','
    beq ASSEMBLE_LOAD_INDEX_INDEXED
    jmp ASSEMBLE_ADDRESS
ASSEMBLE_LOAD_INDEX_INDEXED:
    jsr GET_CHARACTER_A
    and #$1F
    cmp WORK
    bne ASSEMBLE_LOAD_INDEX_ERROR
    jsr ADD_16_TO_OPCODE                       ; +16, the indexed zero page form less 4
    jmp ASSEMBLE_ADDRESS
ASSEMBLE_LOAD_INDEX_ERROR:
    jmp ASSEMBLE_INDEX_ERROR
ASSEMBLE_STORE_INDEX:
    jsr EVALUATE_INTEGER_A
    pla
    sta WORK                        ; the index register's letter
    jsr GET_CHARACTER_A
    cmp #','
    bne ASSEMBLE_STORE_INDEX_SIZE
    jsr GET_CHARACTER_A
    and #$1F
    cmp WORK
    bne ASSEMBLE_LOAD_INDEX_ERROR
    jsr ADD_16_TO_OPCODE                       ; +16, the zp,Y or zp,X form
    lda INT_A+1
    beq ASSEMBLE_STORE_INDEX_SIZE
    jmp ASSEMBLE_BYTE_ERROR         ; there is no absolute indexed form
ASSEMBLE_STORE_INDEX_SIZE:
    jmp ASSEMBLE_ADDRESS_SIZE

;; Assembles OPT, which sets the assembler's options from its operand, or EQU, at <ASSEMBLE_EQU>.
;;
;; OPT assembles no bytes, but goes through <ASSEMBLER_STORE> so that the statement is listed with P%.
;; In: X = the mnemonic's number, zero = set for OPT
ASSEMBLE_DIRECTIVE:
    bne ASSEMBLE_EQU
    jsr EVALUATE_INTEGER_A
    lda INT_A
    sta OPT
    ldy #$00
    jmp ASSEMBLER_STORE
