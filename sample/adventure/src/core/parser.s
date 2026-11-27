; retrocore: style=strict
;; The parser: turns the line the player typed into a verb and a noun
;;
;; A command is a verb and an optional noun, the first two words of the line; more are ignored. Only the game's word
;; length of each word counts, so with a length of 3, INVENTORY is INV. A synonym, marked in the game's word lists,
;; counts as the word it follows. A direction alone moves the player (NORTH, or just N), and I alone is INVENTORY.

;; The most characters <InputLine> holds, its ending 0 included.
INPUT_SIZE = 64

.section BSS

;; The line the player typed, in capitals, ending in 0. The platform's <Console::ReadLine> fills it.
InputLine:
    .res INPUT_SIZE

.section CODE

;; Reading a command.
.scope Parser

.section BSS

;; The command's verb.
Verb:
    .res 1

;; The command's noun, 0 for none.
Noun:
    .res 1

;; Where the first word starts in <InputLine>.
FirstStart:
    .res 1

;; The first word's length, 0 for an empty line.
FirstLength:
    .res 1

;; Where the second word starts in <InputLine>.
SecondStart:
    .res 1

;; The second word's length, 0 for none.
SecondLength:
    .res 1

;; The word being looked up, cut to the game's word length and padded with 0.
Letters:
    .res 8

;; The length of the word <PackWord> packs.
Length:
    .res 1

;; The number of the word <Find> is comparing.
Index:
    .res 1

;; The number of the first of its synonyms.
First:
    .res 1

.section CODE

;; Reads the command in <InputLine>, or says that the game doesn't know its verb.
;; Out: carry = clear with the command in <Verb> and <Noun>, set for a line with no command
.proc Parse
    ; Find the two words.
    ldx #0
    jsr SkipSpaces
    stx FirstStart
    jsr SkipWord
    txa
    sec
    sbc FirstStart
    sta FirstLength
    jsr SkipSpaces
    stx SecondStart
    jsr SkipWord
    txa
    sec
    sbc SecondStart
    sta SecondLength
    lda FirstLength
    bne HasWord
    sec
    rts
HasWord:

    ; A letter alone is a direction, or I for INVENTORY.
    lda SecondLength
    bne FirstWord
    lda FirstLength
    cmp #1
    bne FirstWord
    ldx FirstStart
    lda InputLine,x
    ldy #DIRECTIONS - 1
NextLetter:
    cmp DirectionLetters,y
    beq Direction
    dey
    bpl NextLetter
    cmp #'I'
    bne FirstWord
    lda #<Inventory
    sta WordPointer
    lda #>Inventory
    sta WordPointer + 1
    ldx #INVENTORY_LENGTH
    jsr PackWord
    jmp FindVerb
Direction:
    iny
    sty Noun
    lda #VERB_GO
    sta Verb
    clc
    rts

    ; The first word is the verb.
FirstWord:
    lda FirstStart
    ldx FirstLength
    jsr PackInput
FindVerb:
    ldx #Tables::VERBS
    jsr Find
    bcc KnownVerb

    ; A word that is no verb may be a direction alone.
    lda SecondLength
    bne Unknown
    ldx #Tables::NOUNS
    jsr Find
    bcs Unknown
    cmp #NOUN_NORTH
    bcc Unknown
    cmp #NOUN_DOWN + 1
    bcs Unknown
    sta Noun
    lda #VERB_GO
    sta Verb
    clc
    rts

    ; The second word, if any, is the noun; one that is no noun is noun 0, which the actions with noun 0 answer.
KnownVerb:
    sta Verb
    lda #0
    sta Noun
    lda SecondLength
    beq Known
    lda SecondStart
    ldx SecondLength
    jsr PackInput
    ldx #Tables::NOUNS
    jsr Find
    bcs Known
    sta Noun
Known:
    clc
    rts
Unknown:
    Print Phrases::UnknownWord
    sec
    rts

;; The letters that are directions alone, north to down.
DirectionLetters:
    .byte "NSEWUD"
.assert * - DirectionLetters = DIRECTIONS, "DirectionLetters has a letter for each direction."

;; The word I stands for.
Inventory:
    .byte "INVENTORY"

;; The length of <Inventory>.
INVENTORY_LENGTH = 9
.assert * - Inventory = INVENTORY_LENGTH, "Inventory is INVENTORY_LENGTH letters."
.endproc

;; Moves past spaces in <InputLine>.
;; In: X = where to start
;; Out: X = the first character that isn't a space
.proc SkipSpaces
    lda InputLine,x
    cmp #' '
    bne Done
    inx
    bne SkipSpaces
Done:
    rts
.endproc

;; Moves past a word in <InputLine>.
;; In: X = its first letter
;; Out: X = the space or 0 after it
.proc SkipWord
    lda InputLine,x
    beq Done
    cmp #' '
    beq Done
    inx
    bne SkipWord
Done:
    rts
.endproc

;; Packs a word of <InputLine> into <Letters>.
;; In: A = where it starts, X = its length
.proc PackInput
    clc
    adc #<InputLine
    sta WordPointer
    lda #>InputLine
    adc #0
    sta WordPointer + 1
    ; Falls into PackWord.
.endproc

;; Packs a word into <Letters>, as the game's word lists hold it: cut to the game's word length, and padded with 0.
;; In: WordPointer = its first letter, X = its length
.proc PackWord
    stx Length
    ldy #0
NextLetter:
    cpy Game + Header::WORD_LENGTH
    beq Done
    lda #0
    cpy Length
    bcs Store
    lda (WordPointer),y
Store:
    sta Letters,y
    iny
    bne NextLetter
Done:
    rts
.endproc

;; Looks <Letters> up in one of the game's word lists. Word 0 is never matched.
;; In: X = the list, <Tables::VERBS> or <Tables::NOUNS>
;; Out: carry = clear when found, A = the word's number, as the first of its synonyms
.proc Find
    jsr UseTable
    lda #0
    sta Index
    sta First
NextWord:
    ; A word that isn't a synonym starts a new set of them.
    ldy #0
    lda (TablePointer),y
    bmi Compare
    lda Index
    sta First
Compare:
    lda Index
    beq Advance
NextLetter:
    lda (TablePointer),y
    and #$7F
    cmp Letters,y
    bne Advance
    iny
    cpy Game + Header::WORD_LENGTH
    bne NextLetter
    lda First
    clc
    rts

    ; On to the next word.
Advance:
    clc
    lda TablePointer
    adc Game + Header::WORD_LENGTH
    sta TablePointer
    bcc Moved
    inc TablePointer + 1
Moved:
    inc Index
    lda Index
    cmp Game + Header::WORD_COUNT
    bne NextWord
    sec
    rts
.endproc

;; Writes the command's second word as it was typed, for the actions that say it.
.proc WriteNoun
    ldx SecondStart
    ldy SecondLength
    beq Done
NextLetter:
    lda InputLine,x
    jsr Printer::Write
    inx
    dey
    bne NextLetter
Done:
    rts
.endproc

.endscope
