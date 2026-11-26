; retrocore: style=strict
;; The engine: the start, the turn, and how a command and the turn's own events find their actions
;;
;; A turn runs the actions that happen on their own, shows the room if the player moved, reads a command and
;; performs it, and burns the light. `PackedFormat.md` gives the rules in full, and `tools/ReferenceEngine.cs`
;; follows the same ones.

;; A chance in 100 that always comes up, and what a random byte is scaled to.
CERTAIN = 100

;; Playing the game.
.scope Engine

.section BSS

;; Set when an action of the command's has been performed.
Performed:
    .res 1

;; Set when an action answers the command's words, whether or not its conditions held.
Matched:
    .res 1

;; The chance in 100 that <Chance> tries.
Percent:
    .res 1

.section CODE

;; Plays the game at <Game>, and never returns.
.proc Start
    cld
    jsr Console::Start
    jsr ClearState
    jsr LocateTables
    bcc Found
    Print Phrases::NotAGame
    jmp Console::Finish
Found:
    jsr Numbers::Seed
    jsr World::Start
    ; Falls into Turn.
.endproc

;; Plays turns until the game is over.
.proc Turn
    ; What happens on its own, then the room if it is to be shown.
    jsr Occurrences
    lda World::LookPending
    beq Looked
    jsr World::Look
Looked:
    lda World::Ended
    bne Finish

    ; A command, after the prompt. A line with no command, or with a word the game doesn't know, takes no turn.
Prompt:
    jsr Printer::EndLine
    Print Phrases::Prompt
    jsr Printer::Flush
    jsr Console::ReadLine
    jsr Printer::AtLineStart
    jsr Parser::Parse
    bcs Prompt
    jsr Command
    lda World::Ended
    bne Ending

    ; Then the light burns.
    jsr World::LightTimer
    jmp Turn

    ; A command that ends the game shows the room it leaves the player in.
Ending:
    lda World::LookPending
    beq Finish
    jsr World::Look
Finish:
    Print Phrases::GameOver
    jsr Printer::Flush
    jmp Console::Finish
.endproc

;; Clears the engine's state, all of it in the BSS section, which loading the program does not clear.
.proc ClearState
    lda #<__BSS_RUN__
    sta TablePointer
    lda #>__BSS_RUN__
    sta TablePointer + 1
    ldx #>__BSS_SIZE__
    lda #0
    ldy #0

    ; Whole pages first.
    cpx #0
    beq LastPage
NextPage:
    sta (TablePointer),y
    iny
    bne NextPage
    inc TablePointer + 1
    dex
    bne NextPage

    ; Then what is left.
LastPage:
    cpy #<__BSS_SIZE__
    beq Done
    sta (TablePointer),y
    iny
    jmp LastPage
Done:
    rts
.endproc

;; Performs the actions that happen on their own: those with verb 0 whose chance comes up and whose conditions
;; hold, and the actions that continue them.
.proc Occurrences
    lda #0
    sta Actions::Continuing
    jsr Actions::First
NextAction:
    jsr Actions::AtEnd
    beq Done
    ldy #ACTION_VERB
    lda (ActionPointer),y
    bne Ordinary
    ldy #ACTION_NOUN
    lda (ActionPointer),y
    bne Happens

    ; Verb 0 and noun 0 continue the action before.
    lda Actions::Continuing
    beq Next
    jsr Actions::TryPerform
    jmp Next

    ; Verb 0 and a chance happens if the chance comes up.
Happens:
    pha
    lda #0
    sta Actions::Continuing
    pla
    jsr Chance
    bcc Next
    jsr Actions::TryPerform
    jmp Next

    ; A command's action ends what was being continued.
Ordinary:
    lda #0
    sta Actions::Continuing
Next:
    lda World::Ended
    bne Done
    jsr Actions::Next
    jmp NextAction
Done:
    rts
.endproc

;; Performs the command in <Parser::Verb> and <Parser::Noun>: GO and a direction moves the player, and otherwise the
;; first action that answers the words and whose conditions hold, with the actions that continue it. With none, GET
;; and DROP take the item the noun names; anything else gets a reason.
.proc Command
    lda Parser::Verb
    cmp #VERB_GO
    bne FindAction
    lda Parser::Noun
    cmp #NOUN_NORTH
    bcc FindAction
    cmp #NOUN_DOWN + 1
    bcs FindAction
    jmp World::Move

    ; The actions, in order.
FindAction:
    lda #0
    sta Matched
    sta Performed
    sta Actions::Continuing
    jsr Actions::First
NextAction:
    jsr Actions::AtEnd
    beq NoneLeft
    ldy #ACTION_VERB
    lda (ActionPointer),y
    bne Answers
    ldy #ACTION_NOUN
    lda (ActionPointer),y
    bne Answers

    ; Verb 0 and noun 0 continue the action before.
    lda Actions::Continuing
    beq Next
    jsr Actions::TryPerform
    lda World::Ended
    beq Next
    rts

    ; Any other action ends a performed action's continuation, and the command with it. One that answers the
    ; command has its verb, and its noun or noun 0, which answers any.
Answers:
    lda Performed
    bne Done
    ldy #ACTION_VERB
    lda (ActionPointer),y
    cmp Parser::Verb
    bne Next
    ldy #ACTION_NOUN
    lda (ActionPointer),y
    beq Matches
    cmp Parser::Noun
    bne Next
Matches:
    lda #1
    sta Matched
    jsr Actions::TryPerform
    lda #0
    rol a
    sta Performed
    lda World::Ended
    bne Done
Next:
    jsr Actions::Next
    jmp NextAction

    ; With no action performed, GET and DROP know the items, and the rest get a reason.
NoneLeft:
    lda Performed
    bne Done
    lda Parser::Verb
    cmp #VERB_GET
    bne NotGet
    lda Parser::Noun
    jmp World::Get
NotGet:
    cmp #VERB_DROP
    bne NotDrop
    lda Parser::Noun
    jmp World::Drop
NotDrop:
    lda Matched
    beq NotMatched
    Print Phrases::NotYet
    rts
NotMatched:
    lda Parser::Verb
    cmp #VERB_GO
    bne NotUnderstood
    lda Parser::Noun
    bne NoWay
    Print Phrases::NeedDirection
    rts
NoWay:
    Print Phrases::NoWay
    rts
NotUnderstood:
    Print Phrases::NotUnderstood
Done:
    rts
.endproc

;; Tries a chance: whether a random byte, scaled to 0 to 99, is below it. A chance of 100 or more always comes up,
;; and takes no random byte.
;; In: A = the chance in 100
;; Out: carry = set when it comes up
.proc Chance
    cmp #CERTAIN
    bcs Done
    sta Percent
    jsr Numbers::NextRandom
    ldx #CERTAIN
    jsr Numbers::Multiply
    cmp Percent
    bcs Missed
    sec
    rts
Missed:
    clc
Done:
    rts
.endproc

.endscope
