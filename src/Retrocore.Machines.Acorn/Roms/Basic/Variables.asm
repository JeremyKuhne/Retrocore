;; The variable lists: finding, linking and making variables, FNs and PROCs, arrays and indirection ($945B-$97DC).
;;
;; BASIC keeps every variable but the resident integers in a variable information block on the heap: a two-byte link
;; to the next block in its list (whose high byte is zero at the end of the list), the name less its first
;; character, with any "%", "$" and "(" that end it, then a zero, then the value. Each character a name can start
;; with has its own list, whose head is in page four at <LIST_HEAD_BASE> + 2 * the character; new blocks go on the
;; end. PROCs and FNs found so far have a list each, <PROC_LIST> and <FN_LIST>, whose blocks keep the whole name and,
;; as their value, the address after the name in the DEF.
;;
;; A variable's value is an integer (4 bytes), a real (5) or a string's information block (4: its address, the
;; space allocated, and its length); an array's is described at <DIM_STATEMENT>. The routines here hand a variable
;; on as a descriptor in IntA: the address of its value at INT_A and its type at INT_A+2, one of the DESCRIPTOR_TYPE_
;; values below.
;;
;; - <SEARCH_VARIABLE_LIST> and <SEARCH_FN_PROC_LIST> look a name up; <LINK_VARIABLE> and <LINK_FN_PROC> add a block
;;   for one, and <ALLOCATE_VARIABLE> and <CLAIM_HEAP> give it room on the heap.
;; - <SCAN_VARIABLE_NAME> finds where a name ends.
;; - <FIND_VARIABLE> reads a variable, array element or indirection in the text and returns its descriptor;
;;   <FIND_OR_CREATE_VARIABLE> makes a variable that does not exist yet.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

ERROR_STRING_RANGE = 8              ;; "$ range": a string indirection into zero page
ERROR_ARRAY = 14                    ;; "Array": an array that DIM has not made, or a bad list of subscripts
ERROR_SUBSCRIPT = 15                ;; "Subscript": a subscript outside the array

;; The base the heads of the variable lists are indexed from: the list of the names starting with the character C
;; has its head at LIST_HEAD_BASE + 2 * C.
;;
;; The PROC and FN lists' heads are in the same page, so the search and link routines take a head as its low byte.
;; See: <VARIABLE_LISTS>, <PROC_LIST>, <FN_LIST>
LIST_HEAD_BASE = $0400

.assert LIST_HEAD_BASE + 2 * '@' = VARIABLE_LISTS, "The list of @ starts the variable lists."
.assert >PROC_LIST = >LIST_HEAD_BASE, "The PROC list's head is in the same page as the variable lists."
.assert >FN_LIST = >LIST_HEAD_BASE, "The FN list's head is in the same page as the variable lists."

; The work bytes, as these routines use them.

VARIABLE_NAME = WORK                ;; the name being looked up, less one: its first character is at VARIABLE_NAME+1
VARIABLE_NAME_END = WORK + 2        ;; the offset from <VARIABLE_NAME> of the name's last character
LIST_POINTER = WORK + 3             ;; &3A-&3B: a block in a variable list, or the link that points to it
LIST_NEXT = FP_B_OVERFLOW           ;; &3C-&3D: the next block, which the search alternates with <LIST_POINTER>
ARRAY_ADDRESS = WORK                ;; the address of the array's value, while an element is found
ARRAY_INDEX = WORK + 2              ;; the element's index so far, popped from BASIC's stack: four bytes

; ---------------------------------------------------------------------------------------------------------------------
; Searching and linking the lists
; ---------------------------------------------------------------------------------------------------------------------

;; Looks for a PROC or FN in its list of those already found.
;;
;; The name's first character is in the name compared, since one list holds every PROC and another every FN.
;; In:
;;   VARIABLE_NAME = the address before the token: the PROC or FN token at VARIABLE_NAME+1, then the name
;;   VARIABLE_NAME_END = the offset of the name's last character
;; Out: zero = clear when found, INT_A = the address of the block's value
;; Uses: A, Y, LIST_POINTER, LIST_NEXT
;; See: <SEARCH_VARIABLE_LIST>
SEARCH_FN_PROC_LIST:
    ldy #$01
    lda (VARIABLE_NAME),y
    ldy #<PROC_LIST
    cmp #TOKEN_PROC
    beq SEARCH_LIST
    ldy #<FN_LIST
    bne SEARCH_LIST                 ; always taken

;; Looks for a variable in the list of the names that start with its first character.
;;
;; The search follows the list with two pointers in turn, <LIST_POINTER> and <LIST_NEXT>: the code for each is the
;; same, written out twice so that neither has to be copied to the other. A block's name matches when each character
;; after the first matches and the block's name ends at the same place.
;; In:
;;   VARIABLE_NAME = the address before the name, whose first character is at VARIABLE_NAME+1
;;   VARIABLE_NAME_END = the offset of the name's last character, its "%", "$" or "(" included
;; Out: zero = clear when found, INT_A = the address of the variable's value, A = 0 when not found
;; Uses: A, Y, LIST_POINTER, LIST_NEXT
;; Entry: SEARCH_LIST = searches the list whose head is at LIST_HEAD_BASE + Y
SEARCH_VARIABLE_LIST:
    ldy #$01
    lda (VARIABLE_NAME),y
    asl a
    tay
SEARCH_LIST:
    lda LIST_HEAD_BASE,y
    sta LIST_POINTER
    lda LIST_HEAD_BASE+1,y
    sta LIST_POINTER+1
SEARCH_LIST_EVEN:
    lda LIST_POINTER+1
    beq SEARCH_LIST_DONE            ; the end of the list
    ldy #$00
    lda (LIST_POINTER),y
    sta LIST_NEXT
    iny
    lda (LIST_POINTER),y
    sta LIST_NEXT+1
    iny
    lda (LIST_POINTER),y
    bne SEARCH_LIST_EVEN_COMPARE
    dey                             ; the block's name is one character
    cpy VARIABLE_NAME_END
    bne SEARCH_LIST_ODD
    iny
    bcs SEARCH_LIST_EVEN_FOUND      ; always taken: the compare was equal
SEARCH_LIST_EVEN_NAME:
    iny
    lda (LIST_POINTER),y
    beq SEARCH_LIST_ODD             ; the block's name is shorter
SEARCH_LIST_EVEN_COMPARE:
    cmp (VARIABLE_NAME),y
    bne SEARCH_LIST_ODD
    cpy VARIABLE_NAME_END
    bne SEARCH_LIST_EVEN_NAME
    iny
    lda (LIST_POINTER),y
    bne SEARCH_LIST_ODD             ; the block's name is longer
SEARCH_LIST_EVEN_FOUND:
    tya
    adc LIST_POINTER                ; carry is set: the value is after the name's zero
    sta INT_A
    lda LIST_POINTER+1
    adc #$00
    sta INT_A+1
SEARCH_LIST_DONE:
    rts
SEARCH_LIST_ODD:
    lda LIST_NEXT+1
    beq SEARCH_LIST_DONE            ; the end of the list
    ldy #$00
    lda (LIST_NEXT),y
    sta LIST_POINTER
    iny
    lda (LIST_NEXT),y
    sta LIST_POINTER+1
    iny
    lda (LIST_NEXT),y
    bne SEARCH_LIST_ODD_COMPARE
    dey
    cpy VARIABLE_NAME_END
    bne SEARCH_LIST_EVEN
    iny
    bcs SEARCH_LIST_ODD_FOUND       ; always taken
SEARCH_LIST_ODD_NAME:
    iny
    lda (LIST_NEXT),y
    beq SEARCH_LIST_EVEN
SEARCH_LIST_ODD_COMPARE:
    cmp (VARIABLE_NAME),y
    bne SEARCH_LIST_EVEN
    cpy VARIABLE_NAME_END
    bne SEARCH_LIST_ODD_NAME
    iny
    lda (LIST_NEXT),y
    bne SEARCH_LIST_EVEN
SEARCH_LIST_ODD_FOUND:
    tya
    adc LIST_NEXT
    sta INT_A
    lda LIST_NEXT+1
    adc #$00
    sta INT_A+1
    rts

;; Adds a block for a PROC or FN at the top of the heap to the end of its list.
;; Inherit: <LINK_VARIABLE> Out, Uses
;; In:
;;   VARIABLE_NAME = the address before the token: the PROC or FN token at VARIABLE_NAME+1, then the name
;;   VARIABLE_NAME_END = the offset of the name's last character
LINK_FN_PROC:
    ldy #$01
    lda (VARIABLE_NAME),y
    tax
    lda #<PROC_LIST
    cpx #TOKEN_PROC
    beq LINK_TO_LIST
    lda #<FN_LIST
    bne LINK_TO_LIST                ; always taken

;; Adds a block for a new variable at the top of the heap to the end of its list, and copies its name into it.
;;
;; It walks the list to the last link, the head's if the list is empty, and points it at <HEAP>. The new block's link
;; gets a high byte of zero, ending the list, and the name after its first character is copied in. The name's zero,
;; the value, and moving HEAP past them are left to the caller, with <ALLOCATE_VARIABLE> or <CLAIM_HEAP>; LIST_POINTER
;; is left at the link to the new block, so that <CLAIM_HEAP> can take it off the list again.
;; In:
;;   VARIABLE_NAME = the address before the name, whose first character is at VARIABLE_NAME+1
;;   VARIABLE_NAME_END = the offset of the name's last character
;; Out: Y = the offset in the block of the last byte written: VARIABLE_NAME_END, LIST_POINTER = the link to the block
;; Uses: A, X
;; Entry: LINK_TO_LIST = links to the list whose head's low byte is in A, with Y = 1
LINK_VARIABLE:
    ldy #$01
    lda (VARIABLE_NAME),y
    asl a
LINK_TO_LIST:
    sta LIST_POINTER
    lda #>LIST_HEAD_BASE
    sta LIST_POINTER+1
LINK_TO_LIST_LOOP:
    lda (LIST_POINTER),y            ; Y = 1: the link's high byte
    beq LINK_TO_LIST_END
    tax
    dey
    lda (LIST_POINTER),y
    sta LIST_POINTER
    stx LIST_POINTER+1
    iny
    bpl LINK_TO_LIST_LOOP           ; always taken
LINK_TO_LIST_END:
    lda HEAP+1
    sta (LIST_POINTER),y
    lda HEAP
    dey
    sta (LIST_POINTER),y
    tya
    iny
    sta (HEAP),y                    ; the new block's link: a high byte of zero
    cpy VARIABLE_NAME_END
    beq CLAIM_HEAP_DONE             ; a name of one character
LINK_TO_LIST_NAME_LOOP:
    iny
    lda (VARIABLE_NAME),y
    sta (HEAP),y
    cpy VARIABLE_NAME_END
    bne LINK_TO_LIST_NAME_LOOP
    rts

;; Zeroes bytes after a new block's name, its zero and value, then falls into <CLAIM_HEAP> to claim the block.
;; In: X = the number of zeros, Y = the offset in the block of its last byte so far
;; Out: HEAP = the address after the block
;; Uses: A, X, Y
ALLOCATE_VARIABLE:
    lda #$00
ALLOCATE_VARIABLE_LOOP:
    iny
    sta (HEAP),y
    dex
    bne ALLOCATE_VARIABLE_LOOP

;; Claims a new block at the top of the heap, moving HEAP past it.
;;
;; If the heap would reach BASIC's stack, it takes the block off its list again, by clearing the high byte of the link
;; at <LIST_POINTER>, and gives the "No room" error.
;; In: Y = the offset in the block of its last byte, LIST_POINTER = the link to the block
;; Out: HEAP = the address after the block
;; Uses: A, Y
CLAIM_HEAP:
    sec
    tya
    adc HEAP
    bcc CLAIM_HEAP_CHECK
    inc HEAP+1
CLAIM_HEAP_CHECK:
    ldy HEAP+1
    cpy BASIC_STACK+1
    bcc CLAIM_HEAP_OK
    bne CLAIM_HEAP_NO_ROOM
    cmp BASIC_STACK
    bcc CLAIM_HEAP_OK
CLAIM_HEAP_NO_ROOM:
    lda #$00
    ldy #$01
    sta (LIST_POINTER),y            ; unlink the block
    jmp NO_ROOM_ERROR
CLAIM_HEAP_OK:
    sta HEAP
CLAIM_HEAP_DONE:
    rts

;; Finds the end of a name: the first character that is not a letter, a digit, "@", "_" or "`".
;;
;; A digit cannot start the name at offset 1, though it can one starting further in, as a PROC or FN name does.
;; In: VARIABLE_NAME = the address before the name, X = a count to advance with the name
;; Out: Y = the offset of the character after the name, A = that character, X = X + the name's length
;; Entry: SCAN_VARIABLE_NAME_AT_Y = scans from offset Y instead of 1
SCAN_VARIABLE_NAME:
    ldy #$01
SCAN_VARIABLE_NAME_AT_Y:
    lda (VARIABLE_NAME),y
    cmp #'0'
    bcc SCAN_VARIABLE_NAME_END
    cmp #'@'
    bcs SCAN_VARIABLE_NAME_LETTER
    cmp #'9' + 1
    bcs SCAN_VARIABLE_NAME_END
    cpy #$01
    beq SCAN_VARIABLE_NAME_END      ; a digit at the start
SCAN_VARIABLE_NAME_NEXT:
    inx
    iny
    bne SCAN_VARIABLE_NAME_AT_Y
SCAN_VARIABLE_NAME_LETTER:
    cmp #'_'
    bcs SCAN_VARIABLE_NAME_LOWER
    cmp #'Z' + 1
    bcc SCAN_VARIABLE_NAME_NEXT     ; "@" or a capital
SCAN_VARIABLE_NAME_END:
    rts
SCAN_VARIABLE_NAME_LOWER:
    cmp #'z' + 1
    bcc SCAN_VARIABLE_NAME_NEXT     ; "_", "`" or a small letter
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Finding variables
; ---------------------------------------------------------------------------------------------------------------------

;; Allocates the value of a variable <FIND_OR_CREATE_VARIABLE> has just linked, then finds it again.
CREATE_VARIABLE_VALUE:
    jsr ALLOCATE_VARIABLE

;; Finds the variable at PTRA, making it, with a value of zero or an empty string, if it is a name not seen before.
;;
;; A new variable's block is linked and given its value, then the name is looked up again from the start. A new
;; variable is returned as found, so only text that is not a variable leaves zero set.
;; In: PTR_A, PTR_A_OFFSET = the text
;; Inherit: <FIND_VARIABLE> Out
;; See: <FIND_VARIABLE>
FIND_OR_CREATE_VARIABLE:
    jsr FIND_VARIABLE_A
    bne FIND_INDIRECTION_RETURN     ; found
    bcs FIND_INDIRECTION_RETURN     ; not a variable
    jsr LINK_VARIABLE
    ldx #VARIABLE_REAL       ; the name's zero and four bytes of value
    cpx INT_A+2
    bne CREATE_VARIABLE_VALUE
    inx                             ; a real: the name's zero and five bytes
    bne CREATE_VARIABLE_VALUE       ; always taken

;; Finds the address a unary indirection operator gives, ?address, !address or $address, part of <FIND_VARIABLE>.
;;
;; A string indirection into zero page gives the "$ range" error.
;; In: A = the character, Y = its offset at PTRB
;; Inherit: <FIND_VARIABLE> Out
;; Entry: FIND_INDIRECTION_RETURN = returns, for <FIND_OR_CREATE_VARIABLE>
FIND_INDIRECTION:
    cmp #'!'
    beq FIND_INDIRECTION_WORD
    cmp #'$'
    beq FIND_INDIRECTION_STRING
    eor #'?'
    beq FIND_INDIRECTION_ADDRESS    ; A = 0, the type of a byte
    lda #$00                        ; not a variable
    sec
FIND_INDIRECTION_RETURN:
    rts
FIND_INDIRECTION_WORD:
    lda #VARIABLE_INTEGER
FIND_INDIRECTION_ADDRESS:
    pha
    inc PTR_B_OFFSET
    jsr EVALUATE_INTEGER_FACTOR     ; the address
    jmp FIND_VARIABLE_TYPE
FIND_INDIRECTION_STRING:
    inc PTR_B_OFFSET
    jsr EVALUATE_INTEGER_FACTOR
    lda INT_A+1
    beq STRING_RANGE_ERROR
    lda #VARIABLE_STRING_AT
    sta INT_A+2
    sec
    rts

;; Gives the "$ range" error: a string indirection into zero page.
STRING_RANGE_ERROR:
    brk
    .byte ERROR_STRING_RANGE, "$ range", 0

;; Finds the variable at PTRA, skipping spaces before it.
;;
;; It points PTRB at PTRA and falls into <FIND_VARIABLE>.
;; In: PTR_A, PTR_A_OFFSET = the text
;; Inherit: <FIND_VARIABLE> Out
;; Entry: FIND_VARIABLE_B = finds the variable at PTRB offset Y, skipping spaces
FIND_VARIABLE_A:
    lda PTR_A
    sta PTR_B
    lda PTR_A+1
    sta PTR_B+1
    ldy PTR_A_OFFSET
    dey
FIND_VARIABLE_A_SPACE:
    iny
FIND_VARIABLE_B:
    sty PTR_B_OFFSET
    lda (PTR_B),y
    cmp #' '
    beq FIND_VARIABLE_A_SPACE

;; Finds the variable, array element or indirection at PTRB, and returns its descriptor.
;;
;; It handles:
;;
;; - the resident integers @% and A% to Z%, at <RESIDENT_INTEGERS>, without a search;
;; - a name, looked up with <SEARCH_VARIABLE_LIST>: a real, or an integer with "%", or a string with "$";
;; - an array element, name(subscripts), found with <FIND_ARRAY_ELEMENT>;
;; - the unary indirections ?address, !address and $address;
;; - after a numeric variable or element, the binary indirections variable?offset and variable!offset, whose offset
;;   is a factor.
;;
;; A name that is not found leaves its description in <VARIABLE_NAME> and <VARIABLE_NAME_END> and its type at
;; INT_A+2, as <LINK_VARIABLE> and <FIND_OR_CREATE_VARIABLE> need to make it. An array that does not exist gives the
;; "Array" error.
;; In: A = the character at PTRB, Y = its offset, PTR_B_OFFSET = the same
;; Out:
;;   zero = clear when found
;;   carry = when found, set for a string; when not, set when the text is not a variable and clear for a new name
;;   INT_A = the address of the value, when found
;;   INT_A+2 = the type, when found
;;   PTR_B_OFFSET = after the variable, when found
;;   A = &00 when not found
;; See: <FIND_VARIABLE_A>, <FIND_OR_CREATE_VARIABLE>
FIND_VARIABLE:
    cmp #'@'
    bcc FIND_INDIRECTION
    cmp #'Z' + 1
    bcs FIND_VARIABLE_NAME          ; a name in small letters
    asl a
    asl a
    sta INT_A                       ; RESIDENT_INTEGERS + 4 * (the letter - "@"), if it is one
    lda #>RESIDENT_INTEGERS
    sta INT_A+1
    iny
    lda (PTR_B),y
    iny
    cmp #'%'
    bne FIND_VARIABLE_NAME
    ldx #VARIABLE_INTEGER
    stx INT_A+2
    lda (PTR_B),y
    cmp #'('
    bne FIND_VARIABLE_OPERATOR      ; a resident integer
FIND_VARIABLE_NAME:
    ldx #VARIABLE_REAL
    stx INT_A+2
    lda PTR_B_OFFSET
    clc
    adc PTR_B
    ldx PTR_B+1
    bcc FIND_VARIABLE_1
    inx
    clc
FIND_VARIABLE_1:
    sbc #$00                        ; carry is clear: VARIABLE_NAME = PTRB + offset - 1
    sta VARIABLE_NAME
    bcs FIND_VARIABLE_2
    dex
FIND_VARIABLE_2:
    stx VARIABLE_NAME+1
    ldx PTR_B_OFFSET
    ldy #$01
FIND_VARIABLE_SCAN:
    lda (VARIABLE_NAME),y           ; a name's characters: digits, capitals, "_", "`" and small letters
    cmp #'A'
    bcs FIND_VARIABLE_UPPER
    cmp #'0'
    bcc FIND_VARIABLE_SUFFIX
    cmp #'9' + 1
    bcs FIND_VARIABLE_SUFFIX
    inx
    iny
    bne FIND_VARIABLE_SCAN
FIND_VARIABLE_UPPER:
    cmp #'Z' + 1
    bcs FIND_VARIABLE_LOWER
    inx
    iny
    bne FIND_VARIABLE_SCAN
FIND_VARIABLE_LOWER:
    cmp #'_'
    bcc FIND_VARIABLE_SUFFIX
    cmp #'z' + 1
    bcs FIND_VARIABLE_SUFFIX
    inx
    iny
    bne FIND_VARIABLE_SCAN
FIND_VARIABLE_SUFFIX:
    dey
    beq FIND_VARIABLE_BAD_NAME      ; no name
    cmp #'$'
    beq FIND_VARIABLE_STRING
    cmp #'%'
    bne FIND_VARIABLE_SEARCH
    dec INT_A+2                     ; an integer
    iny
    inx
    iny
    lda (VARIABLE_NAME),y           ; the character after the "%"
    dey
FIND_VARIABLE_SEARCH:
    sty VARIABLE_NAME_END
    cmp #'('
    beq FIND_VARIABLE_ARRAY
    jsr SEARCH_VARIABLE_LIST
    beq FIND_VARIABLE_NOT_FOUND
    stx PTR_B_OFFSET
FIND_VARIABLE_FOUND:
    ldy PTR_B_OFFSET
    lda (PTR_B),y
FIND_VARIABLE_OPERATOR:
    cmp #'!'
    beq FIND_VARIABLE_WORD_OFFSET
    cmp #'?'
    beq FIND_VARIABLE_BYTE_OFFSET
    clc
    sty PTR_B_OFFSET
    lda #$FF
    rts
FIND_VARIABLE_BAD_NAME:
    lda #$00
    sec
    rts
FIND_VARIABLE_NOT_FOUND:
    lda #$00
    clc
    rts
FIND_VARIABLE_BYTE_OFFSET:
    lda #VARIABLE_BYTE
    beq FIND_VARIABLE_OFFSET        ; always taken
FIND_VARIABLE_WORD_OFFSET:
    lda #VARIABLE_INTEGER
FIND_VARIABLE_OFFSET:
    pha
    iny
    sty PTR_B_OFFSET
    jsr READ_VARIABLE               ; the base address
    jsr CONVERT_A_TO_INTEGER
    lda INT_A+1
    pha
    lda INT_A
    pha
    jsr EVALUATE_INTEGER_FACTOR     ; the offset
    clc
    pla
    adc INT_A
    sta INT_A
    pla
    adc INT_A+1
    sta INT_A+1
FIND_VARIABLE_TYPE:
    pla
    sta INT_A+2                     ; the type, pushed by the caller
    clc
    lda #$FF
    rts
FIND_VARIABLE_ARRAY:
    inx
    inc VARIABLE_NAME_END           ; the "(" is part of the name
    jsr FIND_ARRAY_ELEMENT
    jmp FIND_VARIABLE_FOUND
FIND_VARIABLE_STRING:
    inx
    iny
    sty VARIABLE_NAME_END           ; the "$" is part of the name
    iny
    dec INT_A+2                     ; four bytes of value, should it be made
    lda (VARIABLE_NAME),y
    cmp #'('
    beq FIND_VARIABLE_STRING_ARRAY
    jsr SEARCH_VARIABLE_LIST
    beq FIND_VARIABLE_NOT_FOUND
    stx PTR_B_OFFSET
    lda #VARIABLE_STRING
    sta INT_A+2
    sec
    rts
FIND_VARIABLE_STRING_ARRAY:
    inx
    sty VARIABLE_NAME_END
    dec INT_A+2                     ; any type but a real has four-byte cells
    jsr FIND_ARRAY_ELEMENT
    lda #VARIABLE_STRING
    sta INT_A+2
    sec
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Arrays
; ---------------------------------------------------------------------------------------------------------------------

;; Gives the "Array" error: an array that DIM has not made, or subscripts not separated by commas.
ARRAY_ERROR:
    brk
    .byte ERROR_ARRAY, "Array", 0

;; Finds an array element: looks the array up, reads its subscripts and returns the element's address.
;;
;; With D dimensions of N1..ND elements and subscripts S1..SD, the element's index is (..(S1 * N2 + S2) * N3 ..) + SD,
;; and its address is the array's value + the offset of its cells + the index times the cell size, 5 for a real and 4
;; for the others. Each subscript is checked by <CHECK_SUBSCRIPT>. While the subscripts before the last are read, the
;; index so far is kept on BASIC's stack, with the offset of the next dimension's size in its top byte, and the
;; array's address, type and the descriptor's on the 6502 stack.
;; In:
;;   VARIABLE_NAME, VARIABLE_NAME_END = the array's name, its "(" included
;;   INT_A+2 = the cells' type: VARIABLE_REAL for five-byte cells, anything else for four
;;   X = the offset at PTRB after the "("
;; Out: INT_A = the element's address, INT_A+2 = the type, PTR_B_OFFSET = after the ")"
;; Uses: A, X, Y, ARRAY_ADDRESS, ARRAY_INDEX, SIZE_MULTIPLIER
FIND_ARRAY_ELEMENT:
    jsr SEARCH_VARIABLE_LIST
    beq ARRAY_ERROR
    stx PTR_B_OFFSET
    lda INT_A+2
    pha
    lda INT_A
    pha
    lda INT_A+1
    pha                             ; the array's address
    ldy #$00
    lda (INT_A),y                   ; the offset of the cells
    cmp #$04
    bcc FIND_ARRAY_ELEMENT_SINGLE   ; 3: one dimension
    tya
    jsr LOAD_INT_A_BYTE                       ; IntA = 0, the index so far
    lda #$01
    sta INT_A+3                     ; the offset of the first dimension's size
FIND_ARRAY_ELEMENT_LOOP:
    jsr PUSH_INTEGER
    jsr EVALUATE_INTEGER            ; the subscript
    inc PTR_B_OFFSET
    cpx #','
    bne ARRAY_ERROR
    ldx #ARRAY_INDEX
    jsr POP_INTEGER_TO
    ldy ARRAY_INDEX+3               ; the offset of this dimension's size
    pla
    sta ARRAY_ADDRESS+1
    pla
    sta ARRAY_ADDRESS
    pha
    lda ARRAY_ADDRESS+1
    pha                             ; leave the array's address on the stack
    jsr CHECK_SUBSCRIPT
    sty INT_A+3                     ; the offset of the next dimension's size
    lda (ARRAY_ADDRESS),y
    sta SIZE_MULTIPLIER
    iny
    lda (ARRAY_ADDRESS),y
    sta SIZE_MULTIPLIER+1
    lda INT_A                       ; carry is clear
    adc ARRAY_INDEX
    sta INT_A
    lda INT_A+1
    adc ARRAY_INDEX+1
    sta INT_A+1
    jsr MULTIPLY_SIZE               ; IntA = (the index + the subscript) * the next size
    ldy #$00
    sec
    lda (ARRAY_ADDRESS),y
    sbc INT_A+3
    cmp #$03
    bcs FIND_ARRAY_ELEMENT_LOOP     ; until the next is the last dimension
    jsr PUSH_INTEGER
    jsr EVALUATE_TO_CLOSE_BRACKET                       ; the last subscript and the ")"
    jsr CONVERT_A_TO_INTEGER
    pla
    sta ARRAY_ADDRESS+1
    pla
    sta ARRAY_ADDRESS
    ldx #ARRAY_INDEX
    jsr POP_INTEGER_TO
    ldy ARRAY_INDEX+3
    jsr CHECK_SUBSCRIPT
    clc
    lda ARRAY_INDEX
    adc INT_A
    sta INT_A
    lda ARRAY_INDEX+1
    adc INT_A+1
    sta INT_A+1
    bcc FIND_ARRAY_ELEMENT_SCALE    ; always taken: the index fits in 16 bits
FIND_ARRAY_ELEMENT_SINGLE:
    jsr EVALUATE_TO_CLOSE_BRACKET                       ; the subscript and the ")"
    jsr CONVERT_A_TO_INTEGER
    pla
    sta ARRAY_ADDRESS+1
    pla
    sta ARRAY_ADDRESS
    ldy #$01
    jsr CHECK_SUBSCRIPT
FIND_ARRAY_ELEMENT_SCALE:
    pla
    sta INT_A+2
    cmp #VARIABLE_REAL
    bne FIND_ARRAY_ELEMENT_TIMES_4
    ldx INT_A+1                     ; a real: the index times 5
    lda INT_A
    asl INT_A
    rol INT_A+1
    asl INT_A
    rol INT_A+1
    adc INT_A
    sta INT_A
    txa
    adc INT_A+1
    sta INT_A+1
    bcc FIND_ARRAY_ELEMENT_ADD      ; always taken
FIND_ARRAY_ELEMENT_TIMES_4:
    asl INT_A
    rol INT_A+1
    asl INT_A
    rol INT_A+1
FIND_ARRAY_ELEMENT_ADD:
    tya                             ; the offset of the cells
    adc INT_A
    sta INT_A
    bcc FIND_ARRAY_ELEMENT_BASE
    inc INT_A+1
    clc
FIND_ARRAY_ELEMENT_BASE:
    lda ARRAY_ADDRESS
    adc INT_A
    sta INT_A
    lda ARRAY_ADDRESS+1
    adc INT_A+1
    sta INT_A+1
    rts

;; Checks a subscript against the number of elements in its dimension.
;;
;; A subscript that is negative, 16384 or more, or not less than the number of elements gives the "Subscript" error.
;; In: INT_A = the subscript, ARRAY_ADDRESS = the array's value, Y = the offset in it of the dimension's size
;; Out: Y = the offset after the size, carry = clear
;; Uses: A
CHECK_SUBSCRIPT:
    lda INT_A+1
    and #$C0
    ora INT_A+2
    ora INT_A+3
    bne SUBSCRIPT_ERROR
    lda INT_A
    cmp (ARRAY_ADDRESS),y
    iny
    lda INT_A+1
    sbc (ARRAY_ADDRESS),y
    bcs SUBSCRIPT_ERROR
    iny
    rts

;; Gives the "Subscript" error: a subscript outside its dimension.
SUBSCRIPT_ERROR:
    brk
    .byte ERROR_SUBSCRIPT, "Subscript", 0

; The BASIC ROM User Guide's summary of routines gives the BASIC II addresses of these.

.assert SEARCH_FN_PROC_LIST = $945B, "The guide puts the FN and PROC search at &945B."
.assert SEARCH_VARIABLE_LIST = $9469, "The guide puts the variable search at &9469."
.assert LINK_FN_PROC = $94ED, "The guide puts linking a PROC or FN at &94ED."
.assert LINK_VARIABLE = $94FC, "The guide puts linking a variable at &94FC."
.assert ALLOCATE_VARIABLE = $9531, "The guide puts clearing a new block at &9531."
.assert SCAN_VARIABLE_NAME = $9559, "The guide puts scanning a name at &9559."
.assert FIND_OR_CREATE_VARIABLE = $9582, "The guide puts finding or making a variable at &9582."
.assert FIND_VARIABLE_A = $95C9, "The guide puts finding a variable at PTRA at &95C9."
.assert FIND_VARIABLE = $95DD, "The guide puts finding a variable at PTRB at &95DD."
