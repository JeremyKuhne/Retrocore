; retrocore: style=strict
;; The packed game: its header, the addresses of its tables, and the format's fixed numbers
;;
;; The packer, `tools/packer.cs`, writes the game in the format `PackedFormat.md` describes. Each target puts it at
;; <Game>: linked into the program, or loaded beside it. Its header gives each table's offset from <Game>, and
;; <LocateTables> turns those into addresses in <TableAddress> once, at the start.

; The format's fixed numbers.

;; The location of an item the player carries.
CARRIED = 255

;; The verb that moves the player, as in GO NORTH.
VERB_GO = 1

;; The verb that picks an item up.
VERB_GET = 10

;; The verb that puts an item down.
VERB_DROP = 18

;; The first direction's noun: the nouns 1 to 6 are north, south, east, west, up and down.
NOUN_NORTH = 1

;; The last direction's noun.
NOUN_DOWN = 6

;; The number of directions, and of each room's exits.
DIRECTIONS = 6

;; The flag that is set while it is dark: without the light, nothing can be seen.
DARK_FLAG = 15

;; The flag the light sets when it runs out.
LIGHT_OUT_FLAG = 16

;; The light's time that means it never runs out.
ENDLESS = $FFFF

;; The format's version this engine plays.
FORMAT_VERSION = 1

;; The packed game's header.
.struct Header
    ;; The two letters `SA`.
    MAGIC .res 2
    VERSION .byte ;; The format's version.
    WORD_LENGTH .byte ;; How many letters of a word are significant, 1 to 8.
    ITEM_COUNT .byte ;; The number of items.
    ROOM_COUNT .byte ;; The number of rooms, room 0 included.
    MESSAGE_COUNT .byte ;; The number of messages, message 0 included.
    WORD_COUNT .byte ;; The number of verbs, which is also the number of nouns.
    START_ROOM .byte ;; The room the player starts in.
    TREASURE_ROOM .byte ;; The room where treasures are stored for the score.
    CARRY_LIMIT .byte ;; The most items the player may carry.
    TREASURE_COUNT .byte ;; The number of treasures the score counts out of.
    LIGHT_ITEM .byte ;; The item that gives light.
    LIGHT_TIME .word ;; The light's turns, or <ENDLESS>.
    ACTION_COUNT .word ;; The number of actions.
    DICTIONARY .word ;; The offset of the dictionary.
    VERBS .word ;; The offset of the verbs.
    NOUNS .word ;; The offset of the nouns.
    EXITS .word ;; The offset of the rooms' exits.
    ROOM_TEXTS .word ;; The offset of the rooms' descriptions.
    MESSAGES .word ;; The offset of the messages.
    ITEM_LOCATIONS .word ;; The offset of where each item starts.
    ITEM_NOUNS .word ;; The offset of the noun GET and DROP know each item by.
    TREASURES .word ;; The offset of a bit for each item that is a treasure.
    ITEM_TEXTS .word ;; The offset of the items' descriptions.
    ACTIONS .word ;; The offset of the actions.
.endstruct

;; The game's tables, as addresses: <TableAddress> holds them in the order the header gives their offsets.
.struct Tables
    ;; The dictionary: its number of entries, then each entry's length and characters.
    DICTIONARY .word
    ;; The verbs, each <Header::WORD_LENGTH> bytes, padded with 0, a synonym's first byte with its top bit set.
    VERBS .word
    ;; The nouns, as the verbs.
    NOUNS .word
    ;; Six exits for each room, north to down, 0 for none.
    EXITS .word
    ROOM_TEXTS .word ;; The rooms' descriptions, each a string ending in 0.
    MESSAGES .word ;; The messages, each a string ending in 0.
    ITEM_LOCATIONS .word ;; The room each item starts in.
    ITEM_NOUNS .word ;; The noun GET and DROP know each item by, 0 for none.
    TREASURES .word ;; A bit for each item that is a treasure, item 0 in the first byte's bit 0.
    ITEM_TEXTS .word ;; The items' descriptions, each a string ending in 0.
    ACTIONS .word ;; The actions.
.endstruct
.assert .sizeof(Tables) = .sizeof(Header) - Header::DICTIONARY, "Tables has a member for each table in Header."

.section BSS

;; The address of each of the game's tables, by <Tables>' members.
TableAddress:
    .res .sizeof(Tables)

.section CODE

;; Checks that <Game> is a game in this format, and works out its tables' addresses.
;; Out: carry = set when it is not a game this engine plays
.proc LocateTables
    ; The header must be this format's.
    lda Game + Header::MAGIC
    cmp #'S'
    bne NotAGame
    lda Game + Header::MAGIC + 1
    cmp #'A'
    bne NotAGame
    lda Game + Header::VERSION
    cmp #FORMAT_VERSION
    bne NotAGame

    ; Each table is at the game's address plus its offset.
    ldx #0
NextTable:
    clc
    lda Game + Header::DICTIONARY,x
    adc #<Game
    sta TableAddress,x
    lda Game + Header::DICTIONARY + 1,x
    adc #>Game
    sta TableAddress + 1,x
    inx
    inx
    cpx #.sizeof(Tables)
    bne NextTable
    clc
    rts
NotAGame:
    sec
    rts
.endproc

;; Points <TablePointer> at one of the game's tables.
;; In: X = the table, a member of <Tables>
;; Keeps: X, Y
.proc UseTable
    lda TableAddress,x
    sta TablePointer
    lda TableAddress + 1,x
    sta TablePointer + 1
    rts
.endproc
