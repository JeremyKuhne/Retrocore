; retrocore: style=strict
;; The actions: the game's table of what happens, walked for each command and each turn
;;
;; Each action is a verb and a noun it answers, or verb 0 and the chance in 100 that it happens on its own each turn;
;; up to five conditions, which must all hold; and up to four codes, what it does. A condition of type 0 holds no
;; test but a parameter, which the codes that need one take in order. An action with verb 0 and noun 0 continues the
;; one before it, after that one's code 73.

; An action's layout.

;; The offset of an action's verb.
ACTION_VERB = 0

;; The offset of an action's noun, or its chance in 100 for verb 0.
ACTION_NOUN = 1

;; The offset of the byte with an action's number of conditions in its high four bits and of codes in its low four.
ACTION_COUNTS = 2

;; The offset of an action's first condition.
ACTION_CONDITIONS = 3

;; The bits of a condition's first byte that give its type.
CONDITION_TYPE = %00011111

;; The most conditions an action has.
MOST_CONDITIONS = 5

;; The number of counters and of saved rooms.
COUNTER_SLOTS = 16

;; Walking the actions, and the counters and saved rooms they keep.
.scope Actions

.section BSS

;; The actions not yet looked at, counting the one at <ActionPointer>.
Remaining:
    .res 2

;; The current counter, a signed number.
Counter:
    .res 2

;; The counters <Counter> can be swapped with.
Counters:
    .res 2 * COUNTER_SLOTS

;; The rooms code 87 swaps the player's room with.
SavedRooms:
    .res COUNTER_SLOTS

;; The room code 80 swaps the player's room with.
SavedRoom:
    .res 1

;; Set when an action has asked for the actions after it to be continued.
Continuing:
    .res 1

;; The parameters of the action being performed, low bytes.
ParametersLow:
    .res MOST_CONDITIONS

;; The parameters' high bytes.
ParametersHigh:
    .res MOST_CONDITIONS

;; The number of parameters.
ParameterCount:
    .res 1

;; The number of parameters the codes have taken.
ParametersTaken:
    .res 1

;; The parameter <NextParameter> took last.
Parameter:
    .res 2

;; The conditions left to test.
ConditionsLeft:
    .res 1

;; The codes left to perform.
CodesLeft:
    .res 1

;; Where in the action <TryPerform> is reading.
Position:
    .res 1

.section CODE

;; Starts at the first action.
.proc First
    lda TableAddress + Tables::ACTIONS
    sta ActionPointer
    lda TableAddress + Tables::ACTIONS + 1
    sta ActionPointer + 1
    lda Game + Header::ACTION_COUNT
    sta Remaining
    lda Game + Header::ACTION_COUNT + 1
    sta Remaining + 1
    rts
.endproc

;; Tells whether every action has been looked at.
;; Out: zero = set when they all have
.proc AtEnd
    lda Remaining
    ora Remaining + 1
    rts
.endproc

;; Moves on to the next action.
.proc Next
    ; An action is three bytes, two for each condition and one for each code.
    ldy #ACTION_COUNTS
    lda (ActionPointer),y
    pha
    lsr a
    lsr a
    lsr a
    and #%00011110
    sta Position
    pla
    and #$0F
    clc
    adc Position
    adc #ACTION_CONDITIONS
    adc ActionPointer
    sta ActionPointer
    bcc Moved
    inc ActionPointer + 1
Moved:
    lda Remaining
    bne LowOnly
    dec Remaining + 1
LowOnly:
    dec Remaining
    rts
.endproc

;; Performs the action at <ActionPointer> if all its conditions hold.
;; Out: carry = set when they held and it was performed
.proc TryPerform
    ldy #ACTION_COUNTS
    lda (ActionPointer),y
    lsr a
    lsr a
    lsr a
    lsr a
    sta ConditionsLeft
    lda #0
    sta ParameterCount
    sta ParametersTaken
    ldy #ACTION_CONDITIONS

    ; Each condition is its type in the low five bits and its value's high three bits above them, then the value's
    ; low byte.
NextCondition:
    lda ConditionsLeft
    beq Perform
    lda (ActionPointer),y
    pha
    and #CONDITION_TYPE
    sta Conditions::Type
    pla
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    sta Conditions::ValueHigh
    iny
    lda (ActionPointer),y
    sta Conditions::ValueLow
    iny
    sty Position
    lda Conditions::Type
    bne Test

    ; A parameter, for the codes.
    ldx ParameterCount
    lda Conditions::ValueLow
    sta ParametersLow,x
    lda Conditions::ValueHigh
    sta ParametersHigh,x
    inc ParameterCount
    jmp Tested
Test:
    jsr Conditions::Holds
    bcc Failed
Tested:
    ldy Position
    dec ConditionsLeft
    jmp NextCondition
Failed:
    clc
    rts

    ; Then each code, until one ends the game.
Perform:
    sty Position
    ldy #ACTION_COUNTS
    lda (ActionPointer),y
    and #$0F
    sta CodesLeft
NextCode:
    lda CodesLeft
    beq Done
    ldy Position
    lda (ActionPointer),y
    inc Position
    jsr Codes::Perform
    lda World::Ended
    bne Done
    dec CodesLeft
    jmp NextCode
Done:
    sec
    rts
.endproc

;; Takes the action's next parameter, or 0 when it has none left.
;; Out: A = its low byte, Parameter = it
.proc NextParameter
    ldx ParametersTaken
    cpx ParameterCount
    bcs None
    inc ParametersTaken
    lda ParametersHigh,x
    sta Parameter + 1
    lda ParametersLow,x
    sta Parameter
    rts
None:
    lda #0
    sta Parameter + 1
    sta Parameter
    rts
.endproc

.endscope

;; The bits that are set or clear, 32 of them.
.scope Flags

.section BSS

;; Each flag's bit, flag 0 in the first byte's bit 0.
Bits:
    .res 4

;; The flag's bit in its byte.
Mask:
    .res 1

.section CODE

;; Sets a flag.
;; In: A = the flag, of which the low five bits count
.proc Set
    jsr Locate
    ora Bits,x
    sta Bits,x
    rts
.endproc

;; Clears a flag.
;; In: A = the flag, of which the low five bits count
.proc Clear
    jsr Locate
    eor #$FF
    and Bits,x
    sta Bits,x
    rts
.endproc

;; Tells whether a flag is set.
;; In: A = the flag, of which the low five bits count
;; Out: carry = set when it is
.proc Test
    jsr Locate
    and Bits,x
    cmp #1
    rts
.endproc

;; Finds a flag's byte and bit.
;; In: A = the flag, of which the low five bits count
;; Out: X = its byte in <Bits>, A = its bit's mask
.proc Locate
    and #31
    pha
    and #7
    tax
    lda BitMasks,x
    sta Mask
    pla
    lsr a
    lsr a
    lsr a
    tax
    lda Mask
    rts
.endproc

.endscope

;; Each bit's mask, bit 0 first.
BitMasks:
    .byte %00000001, %00000010, %00000100, %00001000, %00010000, %00100000, %01000000, %10000000
