; retrocore: style=strict
;; The conditions an action tests before it is performed
;;
;; A condition is a type, 1 to 19, and a value: an item, a room, a flag or a number to compare the counter with.
;; Type 0 is a parameter, which <Actions::TryPerform> keeps for the codes rather than testing.

;; Testing a condition.
.scope Conditions

.section BSS

;; The condition's type.
Type:
    .res 1

;; Its value's low byte: the item, room or flag.
ValueLow:
    .res 1

;; Its value's high byte, 0 to 7.
ValueHigh:
    .res 1

;; Where the item the value names is.
Location:
    .res 1

.section CODE

;; Tests a condition.
;; In: Type = the type, 1 to 31, ValueLow/ValueHigh = the value
;; Out: carry = set when it holds
.proc Holds
    ; Most conditions test where an item is.
    ldx ValueLow
    lda World::Locations,x
    sta Location
    lda Type
    cmp #TEST_COUNT
    bcs True

    ; Each type's test, through the table.
    asl a
    tax
    lda Tests + 1,x
    pha
    lda Tests,x
    pha
    rts

    ; The tests of where an item is.
Carried:
    lda Location
    cmp #CARRIED
    beq True
    bne False
InRoom:
    lda Location
    cmp World::Room
    beq True
    bne False
Available:
    lda Location
    cmp #CARRIED
    beq True
    cmp World::Room
    beq True
    bne False
NotInRoom:
    lda Location
    cmp World::Room
    beq False
    bne True
NotCarried:
    lda Location
    cmp #CARRIED
    beq False
    bne True
NotAvailable:
    lda Location
    cmp #CARRIED
    beq False
    cmp World::Room
    beq False
    bne True
InPlay:
    lda Location
    beq False
    bne True
OutOfPlay:
    lda Location
    beq True
    bne False
WhereItStarted:
    jsr Original
    cmp Location
    beq True
    bne False
Moved:
    jsr Original
    cmp Location
    beq False
    bne True

    ; The exits most tests take, in the middle of them so each branch reaches.
True:
    sec
    rts
False:
    clc
    rts

    ; The test of the counter that is a signed number against a value from 0 to 2047, near the exits.
CounterIs:
    lda Actions::Counter
    cmp ValueLow
    bne False
    lda Actions::Counter + 1
    cmp ValueHigh
    bne False
    beq True

    ; The tests of the player.
PlayerIn:
    lda ValueHigh
    bne False
    lda World::Room
    cmp ValueLow
    beq True
    bne False
PlayerNotIn:
    lda ValueHigh
    bne True
    lda World::Room
    cmp ValueLow
    beq False
    bne True
CarriesSomething:
    jsr World::CountCarried
    cmp #1
    rts
CarriesNothing:
    jsr World::CountCarried
    cmp #0
    beq True
    bne False

    ; The tests of a flag.
FlagSet:
    lda ValueLow
    jmp Flags::Test
FlagClear:
    lda ValueLow
    jsr Flags::Test
    bcs False
    bcc True

    ; The counter's other tests.
CounterAtMost:
    jmp IsCounterAtMost
CounterAbove:
    jsr IsCounterAtMost
    bcs False
    bcc True

;; Each type's test, as its address less 1 for the `rts` that goes there. Type 0, a parameter, is never tested.
Tests:
    .word True - 1, Carried - 1, InRoom - 1, Available - 1, PlayerIn - 1
    .word NotInRoom - 1, NotCarried - 1, PlayerNotIn - 1, FlagSet - 1, FlagClear - 1
    .word CarriesSomething - 1, CarriesNothing - 1, NotAvailable - 1, InPlay - 1, OutOfPlay - 1
    .word CounterAtMost - 1, CounterAbove - 1, WhereItStarted - 1, Moved - 1, CounterIs - 1

;; The number of types with a test; the types above them always hold.
TEST_COUNT = 20
.assert * - Tests = TEST_COUNT * 2, "Tests has a test for each type."
.endproc

;; Tells whether the counter, a signed number, is at most a condition's value, from 0 to 2047.
;; Out: carry = set when it is
.proc IsCounterAtMost
    lda Actions::Counter + 1
    bmi AtMost
    cmp ValueHigh
    bcc AtMost
    bne Above
    lda Actions::Counter
    cmp ValueLow
    bcc AtMost
    beq AtMost
Above:
    clc
    rts
AtMost:
    sec
    rts
.endproc

;; Finds where the item a condition's value names started.
;; Out: A = its location at the start, 0 for a value that is no item
.proc Original
    lda ValueHigh
    bne NoItem
    lda ValueLow
    cmp Game + Header::ITEM_COUNT
    bcs NoItem
    ldx #Tables::ITEM_LOCATIONS
    jsr UseTable
    ldy ValueLow
    lda (TablePointer),y
    rts
NoItem:
    lda #0
    rts
.endproc

.endscope
