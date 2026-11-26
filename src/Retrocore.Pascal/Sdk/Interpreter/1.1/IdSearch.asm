; retrocore: style=strict
;; <IdSearch>, the Compiler's identifier search, and its table of reserved words.

; The record IdSearch reads and fills: offsets from its address.

;; The cursor, a word: the identifier's offset in the buffer. <IdSearch> moves it on to the identifier's last
;; character.
ID_CURSOR = 0

;; The token, a word: a reserved word's, or <IDENTIFIER_TOKEN>.
ID_TOKEN = 2

;; The operator, a word: a reserved word's, or <NOT_RESERVED_OPERATOR>.
ID_OPERATOR = 4

;; The identifier's first <ID_LENGTH> characters, in upper case and padded with spaces, which <IdSearch> stores when it
;; is not a reserved word.
ID_NAME = 6

;; The characters of an identifier <IdSearch> keeps and compares.
ID_LENGTH = 8

;; The token <IdSearch> gives an identifier that is not a reserved word.
IDENTIFIER_TOKEN = 0

;; The operator <IdSearch> gives an identifier that is not a reserved word.
NOT_RESERVED_OPERATOR = $15

; A reserved word's entry in ReservedWords: offsets from its address.

;; In a letter's first entry, the letter's count of words; 0 in the others.
WORD_COUNT = 0

;; The word, <ID_LENGTH> characters.
WORD_TEXT = 1

;; The word's token, for <ID_TOKEN>.
WORD_TOKEN = WORD_TEXT + ID_LENGTH

;; The word's operator, for <ID_OPERATOR>.
WORD_OPERATOR = WORD_TOKEN + 1

;; The size of an entry.
WORD_SIZE = WORD_OPERATOR + 1

;; One entry of <ReservedWords>' pointers: where a letter's reserved words start.
;; Parameters:
;;   letter = the letter, from "A" to "Z"; the entries go in order
;;   words = its first entry, or <NoWords>
.macro LetterWords letter, words
    .assert * = ReservedWords + 2 * (letter - 'A'), "ReservedWords' pointers are in letter order."
    .word words
.endmacro

;; A letter's first reserved word, which leads with the letter's count of words.
;; Parameters:
;;   count = the letter's words, this one included
;;   word = the word, up to <ID_LENGTH> characters; the entry pads it with spaces
;;   token = its token, the Compiler's number for it
;;   operator = its operator, the Compiler's number for it, or 0
.macro FirstReservedWord count, word, token, operator
    .assert .strlen(word) <= ID_LENGTH, "IdSearch compares only the first ID_LENGTH characters."
    .byte count, word
    .res ID_LENGTH - .strlen(word), ' '
    .byte token, operator
.endmacro

;; One of a letter's reserved words after the first, which leads with 0.
;; Parameters:
;;   word = the word, up to <ID_LENGTH> characters; the entry pads it with spaces
;;   token = its token, the Compiler's number for it
;;   operator = its operator, the Compiler's number for it, or 0
.macro ReservedWord word, token, operator
    FirstReservedWord 0, word, token, operator
.endmacro

;; The Compiler's identifier search, <CSP at OpCSP> <IDS at CspIDS>: reads the identifier at the record's cursor and
;; looks it up in <ReservedWords>.
;;
;; It keeps the identifier's first <ID_LENGTH> letters and digits in upper case, skipping "_", and moves the cursor to
;; its last character. For a reserved word it sets the record's token and operator to the word's; for any other
;; identifier it sets them to <IDENTIFIER_TOKEN> and <NOT_RESERVED_OPERATOR>, and stores the kept characters at
;; <ID_NAME>.
;;
;; It takes the identifier's first character as a letter, and does not compare it with the words', since a letter's
;; words all start with it. A letter with no words points at <NoWords>, whose count is 0: DEC takes the count to 255
;; before testing it, so IdSearch compares 256 entries of <WORD_SIZE> bytes from <NoWords> on, 3 bytes out of step with
;; the other letters' entries and on past the end of bank 2 to $E928, before it gives up.
;; Apple's BIOS document jumps to it as IDS (A2PBIOS), the standard procedure's name.
;; In: Stack = under the return address, the buffer's address, then the record's
.proc IdSearch

;; The return address, kept while <IdSearch> pulls its arguments from under it.
Caller = Pointer

;; The buffer's address.
TextBuffer = Work3

;; The record's address.
Record = Work4

;; The identifier's first character.
Identifier = ReturnAddress

;; The identifier's first <ID_LENGTH> characters, in upper case and padded with spaces.
Name = Mark

;; The entry being compared.
Entry = Work2

;; The entries still to compare, counting the one being compared.
WordsLeft = Work1

;; The reserved word's token.
Token = Procedure

;; The reserved word's operator.
Operator = Procedure + 1

    ; Pull the return address, the buffer's address and the record's.
    pla
    sta Caller
    pla
    sta Caller+1
    pla
    sta TextBuffer
    pla
    sta TextBuffer+1
    pla
    sta Record
    pla
    sta Record+1

    ; Point at the identifier, the cursor's offset into the buffer.
    .assert ID_CURSOR = 0, "IdSearch reads the cursor with Y = 0 and 1."
    ldy #ID_CURSOR
    clc
    lda (Record),y
    adc TextBuffer
    sta Identifier
    iny
    lda (Record),y
    adc TextBuffer+1
    sta Identifier+1

    ; Fill Name with spaces.
    lda #' '
    sta Name
    sta Name+1
    sta Name+2
    sta Name+3
    sta Name+4
    sta Name+5
    sta Name+6
    sta Name+7

    ; Keep the first character, raised to upper case.
    ldy #0
    ldx #0
    lda (Identifier),y
    cmp #'a'
    bcc KeepFirst
    cmp #'z' + 1
    bcs KeepFirst
    sec
    sbc #'a' - 'A'
KeepFirst:
    sta Name

    ; Keep each letter or digit after it, a lower case letter raised, up to ID_LENGTH; skip "_", and stop at
    ; anything else.
NextCharacter:
    iny
    lda (Identifier),y
    cmp #'a'
    bcc NotLower
    cmp #'z' + 1
    bcs NotLower
    sec
    sbc #'a' - 'A'
    jmp Keep
NotLower:
    cmp #'0'
    bcc NotDigit
    cmp #'9' + 1
    bcs NotDigit
    bcc Keep
NotDigit:
    cmp #'A'
    bcc EndOfIdentifier
    cmp #'Z' + 1
    bcc Keep
    cmp #'_'
    bne EndOfIdentifier
    beq NextCharacter
Keep:
    inx
    cpx #ID_LENGTH
    bcs NextCharacter
    sta Name,x
    jmp NextCharacter

    ; Move the cursor on to the identifier's last character.
EndOfIdentifier:
    dey
    tya
    ldy #ID_CURSOR
    clc
    adc (Record),y
    sta (Record),y
    iny
    lda (Record),y
    adc #0
    sta (Record),y

    ; Find the first letter's words, and their count.
    lda Name
    sec
    sbc #'A'
    asl a
    tay
    lda ReservedWords,y
    sta Entry
    iny
    lda ReservedWords,y
    sta Entry+1
    ldy #WORD_COUNT
    lda (Entry),y
    sta WordsLeft

    ; Compare the entry's word with Name, from their second characters.
    ldx #0
    ldy #WORD_TEXT
Compare:
    inx
    iny
    lda (Entry),y
    cmp Name,x
    bne Mismatch
    cpx #ID_LENGTH - 1
    bne Compare
    beq Found

    ; Go on to the next entry, unless that was the last.
Mismatch:
    dec WordsLeft
    beq NotFound
    ldx #0
    ldy #WORD_TEXT
    lda Entry
    clc
    adc #WORD_SIZE
    sta Entry
    bcc NextEntry
    inc Entry+1
NextEntry:
    jmp Compare

    ; A reserved word: set the record's token and operator to its.
Found:
    .assert WORD_TOKEN = WORD_TEXT + ID_LENGTH, "Found steps Y on from the word's last character."
    iny
    lda (Entry),y
    sta Token
    iny
    lda (Entry),y
    sta Operator
    ldy #ID_TOKEN
    lda Token
    sta (Record),y
    iny
    lda #0
    sta (Record),y
    iny
    lda Operator
    sta (Record),y
    iny
    lda #0
    sta (Record),y
    jmp Return

    ; Not a reserved word: set the record's token and operator for an identifier, and store Name.
NotFound:
    .assert ID_OPERATOR = ID_TOKEN + 2 && ID_NAME = ID_OPERATOR + 2, "NotFound steps Y through the record."
    ldy #ID_TOKEN
    lda #0
    sta (Record),y
    iny
    sta (Record),y
    iny
    iny
    sta (Record),y
    dey
    lda #NOT_RESERVED_OPERATOR
    sta (Record),y
    .assert IDENTIFIER_TOKEN = 0, "NotFound stores the token's 0 with the operator's high byte."
    ldy #ID_NAME + ID_LENGTH
    ldx #ID_LENGTH - 1
StoreName:
    dey
    lda Name,x
    sta (Record),y
    dex
    bpl StoreName

    ; Put the return address back.
Return:
    lda Caller+1
    pha
    lda Caller
    pha
    rts
.endproc

;; Where each letter's reserved words start, a word a letter from "A" to "Z": an entry of <WORD_SIZE> bytes a word,
;; the first leading with the letter's count of words.
;; Also: RWREFS (WK11)
ReservedWords:
    LetterWords 'A', WordsA
    LetterWords 'B', WordsB
    LetterWords 'C', WordsC
    LetterWords 'D', WordsD
    LetterWords 'E', WordsE
    LetterWords 'F', WordsF
    LetterWords 'G', WordsG
    LetterWords 'H', NoWords
    LetterWords 'I', WordsI
    LetterWords 'J', NoWords
    LetterWords 'K', NoWords
    LetterWords 'L', WordsL
    LetterWords 'M', WordsM
    LetterWords 'N', WordsN
    LetterWords 'O', WordsO
    LetterWords 'P', WordsP
    LetterWords 'Q', NoWords
    LetterWords 'R', WordsR
    LetterWords 'S', WordsS
    LetterWords 'T', WordsT
    LetterWords 'U', WordsU
    LetterWords 'V', WordsV
    LetterWords 'W', WordsW
    LetterWords 'X', NoWords
    LetterWords 'Y', NoWords
    LetterWords 'Z', NoWords

;; Where the letters with no reserved words point: a count of 0, and two bytes with no known purpose. <IdSearch>
;; compares the second, and the next 6 bytes, as the first entry's word.
;; Also: ATSK (WK11)
NoWords:
    .byte 0
    .byte $40, $23

;; The reserved words that start with "A".
;; Also: ANDK (WK11)
WordsA:
    FirstReservedWord 2, "AND", $27, $02
    ReservedWord "ARRAY", $2C, $00

;; The reserved words that start with "B".
;; Also: BEGK (WK11)
WordsB:
    FirstReservedWord 1, "BEGIN", $13, $00

;; The reserved words that start with "C".
;; Also: CASK (WK11)
WordsC:
    FirstReservedWord 2, "CASE", $15, $00
    ReservedWord "CONST", $1C, $00

;; The reserved words that start with "D".
;; Also: DIVK (WK11)
WordsD:
    FirstReservedWord 3, "DIV", $27, $03
    ReservedWord "DO", $06, $00
    ReservedWord "DOWNTO", $08, $00

;; The reserved words that start with "E".
;; Also: ENDK (WK11)
WordsE:
    FirstReservedWord 3, "END", $09, $00
    ReservedWord "ELSE", $0D, $00
    ReservedWord "EXTERNAL", $35, $00

;; The reserved words that start with "F".
;; Also: FORK (WK11)
WordsF:
    FirstReservedWord 4, "FOR", $18, $00
    ReservedWord "FILE", $2E, $00
    ReservedWord "FORWARD", $22, $00
    ReservedWord "FUNCTION", $20, $00

;; The reserved words that start with "G".
;; Also: GOTOK (WK11)
WordsG:
    FirstReservedWord 1, "GOTO", $1A, $00

;; The reserved words that start with "I". IMPLEMENTATION and INTERFACE are kept to their first 8 characters.
;; Also: IFK (WK11)
WordsI:
    FirstReservedWord 4, "IF", $14, $00
    ReservedWord "IMPLEMEN", $34, $00
    ReservedWord "IN", $29, $0E
    ReservedWord "INTERFAC", $33, $00

;; The reserved words that start with "L".
;; Also: LABK (WK11)
WordsL:
    FirstReservedWord 1, "LABEL", $1B, $00

;; The reserved words that start with "M".
;; Also: MODK (WK11)
WordsM:
    FirstReservedWord 1, "MOD", $27, $04

;; The reserved words that start with "N".
;; Kusche's listing calls it NOTK (WK11), the name Apple's BIOS gives a label in ConsoleCheck.
WordsN:
    FirstReservedWord 1, "NOT", $26, $00

;; The reserved words that start with "O".
;; Also: OFK (WK11)
WordsO:
    FirstReservedWord 2, "OF", $0B, $00
    ReservedWord "OR", $28, $07

;; The reserved words that start with "P". PROCEDURE is kept to its first 8 characters.
;; Also: PROCK (WK11)
WordsP:
    FirstReservedWord 3, "PROCEDUR", $1F, $00
    ReservedWord "PROGRAM", $21, $00
    ReservedWord "PACKED", $2B, $00

;; The reserved words that start with "R".
;; Also: REPK (WK11)
WordsR:
    FirstReservedWord 2, "REPEAT", $16, $00
    ReservedWord "RECORD", $2D, $00

;; The reserved words that start with "S". SEGMENT has PROGRAM's token.
;; Also: SETK (WK11)
WordsS:
    FirstReservedWord 3, "SET", $2A, $00
    ReservedWord "SEGMENT", $21, $00
    ReservedWord "SEPARATE", $36, $00

;; The reserved words that start with "T".
;; Also: THENK (WK11)
WordsT:
    FirstReservedWord 3, "THEN", $0C, $00
    ReservedWord "TO", $07, $00
    ReservedWord "TYPE", $1D, $00

;; The reserved words that start with "U".
;; Also: UNITK (WK11)
WordsU:
    FirstReservedWord 3, "UNIT", $32, $00
    ReservedWord "UNTIL", $0A, $00
    ReservedWord "USES", $31, $00

;; The reserved words that start with "V".
;; Also: VARK (WK11)
WordsV:
    FirstReservedWord 1, "VAR", $1E, $00

;; The reserved words that start with "W".
;; Also: WHILK (WK11)
WordsW:
    FirstReservedWord 2, "WHILE", $17, $00
    ReservedWord "WITH", $19, $00
