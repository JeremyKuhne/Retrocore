; retrocore: style=strict
;; The codes: what an action does
;;
;; Codes 1 to 51 print those messages, and 102 to 149 messages 52 to 99. Codes 52 to 88 change the world, the flags
;; and the counter, and the codes that need a value take the action's parameters in order. The others do nothing.

; The codes with a meaning of their own.

;; The first code that is no message.
FIRST_SPECIAL = 52

;; The code after the last that has a meaning of its own.
SPECIAL_END = 89

;; The first code that prints a message after 51.
LATE_MESSAGES = 102

;; The code after the last message's.
MESSAGES_END = 150

;; What the late messages' codes are above their messages' numbers.
LATE_OFFSET = 50

;; Performing a code.
.scope Codes

.section BSS

;; The item a code is moving.
Item:
    .res 1

.section CODE

;; Performs a code.
;; In: A = the code
.proc Perform
    cmp #FIRST_SPECIAL
    bcs NotEarlyMessage
    cmp #0
    beq Done
    jmp Printer::WriteMessage
NotEarlyMessage:
    cmp #LATE_MESSAGES
    bcc Special
    cmp #MESSAGES_END
    bcs Done
    sec
    sbc #LATE_OFFSET
    jmp Printer::WriteMessage

    ; Codes 52 to 88, through the table.
Special:
    cmp #SPECIAL_END
    bcs Done
    sec
    sbc #FIRST_SPECIAL
    asl a
    tax
    lda Handlers + 1,x
    pha
    lda Handlers,x
    pha
    ; The rts goes to the handler, which returns to the caller.
Done:
    rts

;; Each of the codes from 52, as its address less 1 for the `rts` that goes there.
Handlers:
    .word GetItem - 1, DropItem - 1, GoTo - 1, Destroy - 1, Night - 1, Day - 1, SetFlag - 1, Destroy - 1
    .word ClearFlag - 1, Die - 1, PutItem - 1, EndGame - 1, Look - 1, Score - 1, Inventory - 1, SetFlagZero - 1
    .word ClearFlagZero - 1, Refill - 1, ClearScreen - 1, Save - 1, Swap - 1, Continue - 1, Take - 1, PutWith - 1
    .word Look - 1, CountDown - 1, ShowCounter - 1, SetCounter - 1, SwapRoomZero - 1, SwapCounter - 1
    .word AddCounter - 1, SubtractCounter - 1, SayNoun - 1, SayNounLine - 1, NewLine - 1, SwapRoom - 1, Pause - 1
.assert * - Handlers = (SPECIAL_END - FIRST_SPECIAL) * 2, "Handlers has a routine for each code from 52 to 88."
.endproc

; Codes 52 to 55: items and the player.

;; 52: picks the parameter's item up, unless the player carries too much already.
.proc GetItem
    jsr Actions::NextParameter
    sta Item
    jsr World::CountCarried
    cmp Game + Header::CARRY_LIMIT
    bcc Take
    Print Phrases::TooMuch
    rts
Take:
    ldx Item
    lda #CARRIED
    sta World::Locations,x
    rts
.endproc

;; 53: puts the parameter's item in the player's room.
.proc DropItem
    jsr Actions::NextParameter
    tax
    lda World::Room
    sta World::Locations,x
    rts
.endproc

;; 54: moves the player to the parameter's room.
.proc GoTo
    jsr Actions::NextParameter
    sta World::Room
    lda #1
    sta World::LookPending
    rts
.endproc

;; 55 and 59: takes the parameter's item out of play.
.proc Destroy
    jsr Actions::NextParameter
    tax
    lda #0
    sta World::Locations,x
    rts
.endproc

; Codes 56 to 60: flags.

;; 56: makes it dark.
.proc Night
    lda #DARK_FLAG
    jmp Flags::Set
.endproc

;; 57: makes it light.
.proc Day
    lda #DARK_FLAG
    jmp Flags::Clear
.endproc

;; 58: sets the parameter's flag.
.proc SetFlag
    jsr Actions::NextParameter
    jmp Flags::Set
.endproc

;; 60: clears the parameter's flag.
.proc ClearFlag
    jsr Actions::NextParameter
    jmp Flags::Clear
.endproc

; Codes 61 to 66: the game.

;; 61: the player dies, and goes to the last room, where it is light.
.proc Die
    Print Phrases::Dead
    lda #DARK_FLAG
    jsr Flags::Clear
    ldx Game + Header::ROOM_COUNT
    dex
    stx World::Room
    lda #1
    sta World::LookPending
    rts
.endproc

;; 62: puts the first parameter's item in the second parameter's room.
.proc PutItem
    jsr Actions::NextParameter
    sta Item
    jsr Actions::NextParameter
    ldx Item
    sta World::Locations,x
    rts
.endproc

;; 63: ends the game.
.proc EndGame
    lda #1
    sta World::Ended
    rts
.endproc

;; 64 and 76: shows the room.
.proc Look
    jmp World::Look
.endproc

;; 65: gives the score, and ends the game when every treasure is stored.
.proc Score
    jmp World::Score
.endproc

;; 66: lists what the player carries.
.proc Inventory
    jmp World::Inventory
.endproc

; Codes 67 to 71: flag 0, the light and the screen.

;; 67: sets flag 0.
.proc SetFlagZero
    lda #0
    jmp Flags::Set
.endproc

;; 68: clears flag 0.
.proc ClearFlagZero
    lda #0
    jmp Flags::Clear
.endproc

;; 69: refills the light, which the player then carries.
.proc Refill
    lda Game + Header::LIGHT_TIME
    sta World::LightTime
    lda Game + Header::LIGHT_TIME + 1
    sta World::LightTime + 1
    ldx Game + Header::LIGHT_ITEM
    lda #CARRIED
    sta World::Locations,x
    lda #LIGHT_OUT_FLAG
    jmp Flags::Clear
.endproc

;; 70: clears the screen.
.proc ClearScreen
    jsr Printer::AtLineStart
    jmp Console::Clear
.endproc

;; 71: would save the game, which this engine can't do yet.
.proc Save
    Print Phrases::NoSaving
    rts
.endproc

; Codes 72 to 75: more items.

;; 72: swaps where the two parameters' items are.
.proc Swap
    jsr Actions::NextParameter
    sta Item
    jsr Actions::NextParameter
    tay
    ldx Item
    lda World::Locations,x
    pha
    lda World::Locations,y
    sta World::Locations,x
    pla
    sta World::Locations,y
    rts
.endproc

;; 73: performs the actions after this one that continue it.
.proc Continue
    lda #1
    sta Actions::Continuing
    rts
.endproc

;; 74: the player takes the parameter's item, however much they carry.
.proc Take
    jsr Actions::NextParameter
    tax
    lda #CARRIED
    sta World::Locations,x
    rts
.endproc

;; 75: puts the first parameter's item where the second's is.
.proc PutWith
    jsr Actions::NextParameter
    sta Item
    jsr Actions::NextParameter
    tax
    lda World::Locations,x
    ldx Item
    sta World::Locations,x
    rts
.endproc

; Codes 77 to 83: the counter.

;; 77: counts the counter down by 1, unless it is below 0.
.proc CountDown
    lda Actions::Counter + 1
    bmi Done
    lda Actions::Counter
    bne LowOnly
    dec Actions::Counter + 1
LowOnly:
    dec Actions::Counter
Done:
    rts
.endproc

;; 78: writes the counter.
.proc ShowCounter
    lda Actions::Counter
    ldx Actions::Counter + 1
    jmp Printer::WriteNumber
.endproc

;; 79: sets the counter to the parameter.
.proc SetCounter
    jsr Actions::NextParameter
    sta Actions::Counter
    lda Actions::Parameter + 1
    sta Actions::Counter + 1
    rts
.endproc

;; 80: swaps the player's room with a saved room of its own, apart from code 87's.
.proc SwapRoomZero
    lda Actions::SavedRoom
    ldy World::Room
    sta World::Room
    sty Actions::SavedRoom
    lda #1
    sta World::LookPending
    rts
.endproc

;; 81: swaps the counter with the parameter's counter, of which the low four bits count.
.proc SwapCounter
    jsr Actions::NextParameter
    and #COUNTER_SLOTS - 1
    asl a
    tax
    lda Actions::Counters,x
    ldy Actions::Counter
    sta Actions::Counter
    tya
    sta Actions::Counters,x
    lda Actions::Counters + 1,x
    ldy Actions::Counter + 1
    sta Actions::Counter + 1
    tya
    sta Actions::Counters + 1,x
    rts
.endproc

;; 82: adds the parameter to the counter.
.proc AddCounter
    jsr Actions::NextParameter
    clc
    adc Actions::Counter
    sta Actions::Counter
    lda Actions::Parameter + 1
    adc Actions::Counter + 1
    sta Actions::Counter + 1
    rts
.endproc

;; 83: takes the parameter from the counter, which goes no lower than -1.
.proc SubtractCounter
    jsr Actions::NextParameter
    sec
    lda Actions::Counter
    sbc Actions::Parameter
    sta Actions::Counter
    lda Actions::Counter + 1
    sbc Actions::Parameter + 1
    sta Actions::Counter + 1
    bpl Done

    ; A negative result other than -1 becomes -1.
    cmp #$FF
    bne Least
    lda Actions::Counter
    cmp #$FF
    beq Done
Least:
    lda #$FF
    sta Actions::Counter
    sta Actions::Counter + 1
Done:
    rts
.endproc

; Codes 84 to 88: words and time.

;; 84: writes the command's second word in full.
.proc SayNoun
    jmp Parser::WriteNoun
.endproc

;; 85: writes the command's second word in full, and ends the line.
.proc SayNounLine
    jsr Parser::WriteNoun
    ; Falls into NewLine.
.endproc

;; 86: ends the line.
.proc NewLine
    lda #NEW_LINE
    jmp Printer::Write
.endproc

;; 87: swaps the player's room with the parameter's saved room, of which the low four bits count.
.proc SwapRoom
    jsr Actions::NextParameter
    and #COUNTER_SLOTS - 1
    tax
    lda Actions::SavedRooms,x
    ldy World::Room
    sta World::Room
    tya
    sta Actions::SavedRooms,x
    lda #1
    sta World::LookPending
    rts
.endproc

;; 88: waits a moment.
.proc Pause
    jmp Console::Pause
.endproc

.endscope
