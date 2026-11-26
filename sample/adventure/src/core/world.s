; retrocore: style=strict
;; The world: the player's room, where each item is, the light, and what the player sees and carries
;;
;; An item is in a room, carried (<CARRIED>), or in room 0, which holds what is not in play. The last room is where
;; the player goes on dying. It is dark while <DARK_FLAG> is set, unless the light, <Header::LIGHT_ITEM>, is carried
;; or in the room.

;; The turns left at which the light starts to warn that it is growing dim, every fifth turn.
DIM_WARNINGS = 25

;; How often the light warns, in turns.
DIM_INTERVAL = 5

;; The score for every treasure stored.
FULL_SCORE = 100

;; The player, the items and the light.
.scope World

.section BSS

;; The room the player is in.
Room:
    .res 1

;; Where each item is, by item number.
Locations:
    .res 256

;; The light's turns left, or <ENDLESS>.
LightTime:
    .res 2

;; Set when the room is to be shown at the end of the turn, as after the player moves.
LookPending:
    .res 1

;; Set when the game is over.
Ended:
    .res 1

;; The direction <Look> and <Move> are working on.
Direction:
    .res 1

;; Set when <Look> or <ListItems> has listed something.
Listed:
    .res 1

;; Set while the player moves in the dark.
Dark:
    .res 1

;; The item <ListItems>, <Get> or <Score> is working on.
Item:
    .res 1

;; The noun <FindItem> looks for.
WantedNoun:
    .res 1

;; The location <FindItem> looks in.
WantedLocation:
    .res 1

;; The location <ListItems> lists.
ListLocation:
    .res 1

;; The heading <ListItems> writes before the first item.
ListHeading:
    .res 2

;; The line <ListItems> writes when there are none, or 0 to write nothing.
ListNone:
    .res 2

;; A bit of an item's byte of the game's treasure table, for <Score>.
Mask:
    .res 1

;; The treasures in the treasure room, for <Score>.
Stored:
    .res 1

.section CODE

;; Puts the player and the items where the game starts them.
.proc Start
    ldx #Tables::ITEM_LOCATIONS
    jsr UseTable
    ldy #0
NextItem:
    cpy Game + Header::ITEM_COUNT
    beq Placed
    lda (TablePointer),y
    sta Locations,y
    iny
    bne NextItem
Placed:
    lda Game + Header::START_ROOM
    sta Room
    lda Game + Header::LIGHT_TIME
    sta LightTime
    lda Game + Header::LIGHT_TIME + 1
    sta LightTime + 1
    lda #1
    sta LookPending
    rts
.endproc

;; Tells whether an item is with the player: carried, or in the player's room.
;; In: X = the item
;; Out: carry = set when it is
;; Keeps: X, Y
.proc IsHere
    lda Locations,x
    cmp #CARRIED
    beq Yes
    cmp Room
    beq Yes
    clc
    rts
Yes:
    sec
    rts
.endproc

;; Tells whether it is too dark to see.
;; Out: carry = set when it is
.proc IsDark
    lda #DARK_FLAG
    jsr Flags::Test
    bcc Done
    ldx Game + Header::LIGHT_ITEM
    jsr IsHere
    lda #0
    rol a
    eor #1
    lsr a
Done:
    rts
.endproc

;; Counts the items the player carries.
;; Out: A = the count
.proc CountCarried
    ldx #0
    ldy #0
NextItem:
    cpx Game + Header::ITEM_COUNT
    beq Counted
    lda Locations,x
    cmp #CARRIED
    bne Next
    iny
Next:
    inx
    bne NextItem
Counted:
    tya
    rts
.endproc

;; Shows the room: its description, its exits and the items in it, or that it is too dark to see.
.proc Look
    lda #0
    sta LookPending
    jsr IsDark
    bcc Lit
    Print Phrases::TooDark
    rts
Lit:
    lda Room
    ldx #Tables::ROOM_TEXTS
    jsr Printer::WriteString
    lda #NEW_LINE
    jsr Printer::Write

    ; The exits, by name.
    Print Phrases::ExitsHeading
    lda #0
    sta Listed
    sta Direction
NextExit:
    jsr UseExits
    ldy Direction
    lda (TablePointer),y
    beq NoExit
    lda Listed
    beq NamedFirst
    Print Phrases::Comma
NamedFirst:
    lda #1
    sta Listed
    lda Direction
    asl a
    tax
    lda DirectionNames,x
    ldy DirectionNames + 1,x
    jsr Printer::WriteText
NoExit:
    inc Direction
    lda Direction
    cmp #DIRECTIONS
    bne NextExit
    lda Listed
    bne ExitsListed
    Print Phrases::NoExits
ExitsListed:
    Print Phrases::LineEnd

    ; The items here.
    lda #<Phrases::ItemsHeading
    sta ListHeading
    lda #>Phrases::ItemsHeading
    sta ListHeading + 1
    lda #0
    sta ListNone + 1
    lda Room
    jmp ListItems

;; Each direction's name, north to down.
DirectionNames:
    .word Phrases::North, Phrases::South, Phrases::East, Phrases::West, Phrases::Up, Phrases::Down
.assert * - DirectionNames = DIRECTIONS * 2, "DirectionNames names each direction."
.endproc

;; Points <TablePointer> at the player's room's exits.
.proc UseExits
    ; Each room has DIRECTIONS exits: its row is six times the room's number in.
    lda #0
    sta TablePointer + 1
    lda Room
    asl a
    rol TablePointer + 1
    sta TablePointer
    ldx TablePointer + 1
    asl a
    rol TablePointer + 1
    clc
    adc TablePointer
    sta TablePointer
    txa
    adc TablePointer + 1
    sta TablePointer + 1

    ; From the table's start.
    clc
    lda TablePointer
    adc TableAddress + Tables::EXITS
    sta TablePointer
    lda TablePointer + 1
    adc TableAddress + Tables::EXITS + 1
    sta TablePointer + 1
    rts
.endproc
.assert DIRECTIONS = 6, "UseExits multiplies by six."

;; Lists the items at a location after <ListHeading>, or writes <ListNone> when there are none.
;; In: A = the location
.proc ListItems
    sta ListLocation
    lda #0
    sta Listed
    sta Item
NextItem:
    ldx Item
    cpx Game + Header::ITEM_COUNT
    beq Finished
    lda Locations,x
    cmp ListLocation
    bne Next

    ; The heading before the first, and commas between the rest.
    lda Listed
    bne Comma
    lda ListHeading
    ldy ListHeading + 1
    jsr Printer::WriteText
    jmp Name
Comma:
    Print Phrases::Comma
Name:
    lda #1
    sta Listed
    lda Item
    ldx #Tables::ITEM_TEXTS
    jsr Printer::WriteString
Next:
    inc Item
    jmp NextItem
Finished:
    lda Listed
    beq None
    Print Phrases::LineEnd
    rts
None:
    lda ListNone + 1
    beq Done
    lda ListNone
    ldy ListNone + 1
    jmp Printer::WriteText
Done:
    rts
.endproc

;; Lists what the player carries.
.proc Inventory
    lda #<Phrases::CarryingHeading
    sta ListHeading
    lda #>Phrases::CarryingHeading
    sta ListHeading + 1
    lda #<Phrases::CarryingNothing
    sta ListNone
    lda #>Phrases::CarryingNothing
    sta ListNone + 1
    lda #CARRIED
    jmp ListItems
.endproc

;; Moves the player one way. In the dark, there is a warning, and a way that leads nowhere is a fatal fall.
;; In: A = the direction's noun, <NOUN_NORTH> to <NOUN_DOWN>
.proc Move
    sta Direction
    dec Direction
    jsr IsDark
    lda #0
    rol a
    sta Dark
    beq Lit
    Print Phrases::Dangerous
Lit:
    jsr UseExits
    ldy Direction
    lda (TablePointer),y
    beq NoExit
    sta Room
    lda #1
    sta LookPending
    rts
NoExit:
    lda Dark
    beq Blocked
    Print Phrases::BrokeNeck
    lda #1
    sta Ended
    rts
Blocked:
    Print Phrases::NoWay
    rts
.endproc

;; Finds the first item at a location that GET and DROP know by a noun. Noun 0, a word the game doesn't know, names
;; none.
;; In: A = the noun, Y = the location
;; Out: carry = set when found, X = the item
.proc FindItem
    sta WantedNoun
    sty WantedLocation
    cmp #0
    beq NotFound
    ldx #Tables::ITEM_NOUNS
    jsr UseTable
    ldy #0
NextItem:
    cpy Game + Header::ITEM_COUNT
    beq NotFound
    lda (TablePointer),y
    cmp WantedNoun
    bne Next
    lda Locations,y
    cmp WantedLocation
    beq Found
Next:
    iny
    bne NextItem
NotFound:
    clc
    rts
Found:
    tya
    tax
    sec
    rts
.endproc

;; Picks up the item a noun names, for GET when no action of the game's takes the command.
;; In: A = the noun
.proc Get
    sta WantedNoun
    lda Parser::SecondLength
    bne Named
    Print Phrases::What
    rts
Named:
    jsr IsDark
    bcc Lit
    Print Phrases::TooDark
    rts
Lit:
    lda WantedNoun
    ldy Room
    jsr FindItem
    bcs Found
    Print Phrases::NotHere
    rts
Found:
    stx Item
    jsr CountCarried
    cmp Game + Header::CARRY_LIMIT
    bcc Take
    Print Phrases::TooMuch
    rts
Take:
    ldx Item
    lda #CARRIED
    sta Locations,x
    Print Phrases::Done
    rts
.endproc

;; Puts down the item a noun names, for DROP when no action of the game's takes the command.
;; In: A = the noun
.proc Drop
    sta WantedNoun
    lda Parser::SecondLength
    bne Named
    Print Phrases::What
    rts
Named:
    lda WantedNoun
    ldy #CARRIED
    jsr FindItem
    bcs Found
    Print Phrases::NotCarried
    rts
Found:
    lda Room
    sta Locations,x
    Print Phrases::Done
    rts
.endproc

;; Burns the light for a turn, while it is in play: it warns as it grows dim, and sets <LIGHT_OUT_FLAG> when it runs
;; out. The warnings are only for a light the player has with them.
.proc LightTimer
    ldx Game + Header::LIGHT_ITEM
    lda Locations,x
    beq Done
    lda LightTime
    and LightTime + 1
    cmp #$FF
    beq Done
    lda LightTime
    ora LightTime + 1
    beq Done

    ; A turn's light.
    lda LightTime
    bne LowOnly
    dec LightTime + 1
LowOnly:
    dec LightTime
    lda LightTime
    ora LightTime + 1
    bne Burning
    lda #LIGHT_OUT_FLAG
    jsr Flags::Set
    ldx Game + Header::LIGHT_ITEM
    jsr IsHere
    bcc Done
    Print Phrases::LightOut
Done:
    rts

    ; With fewer than DIM_WARNINGS turns left, a warning every DIM_INTERVAL.
Burning:
    lda LightTime + 1
    bne Done
    lda LightTime
    cmp #DIM_WARNINGS
    bcs Done
    sec
Interval:
    sbc #DIM_INTERVAL
    beq Warn
    bcs Interval
    rts
Warn:
    ldx Game + Header::LIGHT_ITEM
    jsr IsHere
    bcc Done
    Print Phrases::LightDim
    rts
.endproc

;; Counts the treasures in the treasure room and gives the score out of 100. All of them win the game.
.proc Score
    lda #0
    sta Stored
    sta Item
    ldx #Tables::TREASURES
    jsr UseTable
NextItem:
    ldx Item
    cpx Game + Header::ITEM_COUNT
    beq Counted

    ; Item n's bit is bit n mod 8 of byte n / 8.
    txa
    and #7
    tay
    lda BitMasks,y
    sta Mask
    txa
    lsr a
    lsr a
    lsr a
    tay
    lda (TablePointer),y
    and Mask
    beq Next
    lda Locations,x
    cmp Game + Header::TREASURE_ROOM
    bne Next
    inc Stored
Next:
    inc Item
    jmp NextItem

    ; The count, then the score: the count times 100, over the treasures there are.
Counted:
    Print Phrases::StoredStart
    lda Stored
    ldx #0
    jsr Printer::WriteNumber
    Print Phrases::StoredMiddle
    lda #0
    sta Numbers::Dividend
    sta Numbers::Dividend + 1
    lda Game + Header::TREASURE_COUNT
    beq Rated
    sta Numbers::Divisor
    lda Stored
    ldx #FULL_SCORE
    jsr Numbers::Multiply
    sta Numbers::Dividend + 1
    lda Numbers::Product
    sta Numbers::Dividend
    jsr Numbers::Divide
Rated:
    lda Numbers::Dividend
    ldx Numbers::Dividend + 1
    jsr Printer::WriteNumber
    Print Phrases::LineEnd

    ; Every treasure stored wins.
    lda Game + Header::TREASURE_COUNT
    beq Done
    lda Stored
    cmp Game + Header::TREASURE_COUNT
    bcc Done
    Print Phrases::WellDone
    lda #1
    sta Ended
Done:
    rts
.endproc

.endscope
