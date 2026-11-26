; retrocore: style=strict
;; The engine's own text, which every game shares
;;
;; Each ends in <STRING_END>, and those that end a line in <NEW_LINE> first. `tools/ReferenceEngine.cs` has the same
;; text, so its transcripts match the engine's.

;; The engine's own text.
.scope Phrases

;; What the engine prints when it waits for a command.
Prompt:
    .byte "> ", STRING_END

;; The room, when it is too dark to see it.
TooDark:
    .byte "It's too dark to see.", NEW_LINE, STRING_END

;; What comes before the room's exits.
ExitsHeading:
    .byte "Obvious exits: ", STRING_END

;; A room with no exits.
NoExits:
    .byte "none", STRING_END

;; What comes before the items in the room.
ItemsHeading:
    .byte "I can also see: ", STRING_END

;; What comes between the exits or items of a list.
Comma:
    .byte ", ", STRING_END

;; What ends a list.
LineEnd:
    .byte ".", NEW_LINE, STRING_END

;; Direction 1's name.
North:
    .byte "North", STRING_END

;; Direction 2's name.
South:
    .byte "South", STRING_END

;; Direction 3's name.
East:
    .byte "East", STRING_END

;; Direction 4's name.
West:
    .byte "West", STRING_END

;; Direction 5's name.
Up:
    .byte "Up", STRING_END

;; Direction 6's name.
Down:
    .byte "Down", STRING_END

;; A command whose verb the game doesn't know.
UnknownWord:
    .byte "I don't know that word.", NEW_LINE, STRING_END

;; GO with no direction.
NeedDirection:
    .byte "Give me a direction too.", NEW_LINE, STRING_END

;; A direction the room has no exit for.
NoWay:
    .byte "I can't go that way.", NEW_LINE, STRING_END

;; A move in the dark.
Dangerous:
    .byte "It's dangerous to move in the dark!", NEW_LINE, STRING_END

;; A move in the dark that leads nowhere.
BrokeNeck:
    .byte "I fell and broke my neck.", NEW_LINE, STRING_END

;; An item picked up or put down.
Done:
    .byte "OK", NEW_LINE, STRING_END

;; An item the player can't pick up, carrying as much as the game allows.
TooMuch:
    .byte "I can't carry any more.", NEW_LINE, STRING_END

;; GET of an item that isn't here.
NotHere:
    .byte "I don't see it here.", NEW_LINE, STRING_END

;; DROP of an item the player doesn't carry.
NotCarried:
    .byte "I'm not carrying it.", NEW_LINE, STRING_END

;; GET or DROP with no noun.
What:
    .byte "What?", NEW_LINE, STRING_END

;; A command the game's actions know, but whose conditions don't hold.
NotYet:
    .byte "I can't do that yet.", NEW_LINE, STRING_END

;; A command no action of the game's knows.
NotUnderstood:
    .byte "I don't understand.", NEW_LINE, STRING_END

;; The player's death.
Dead:
    .byte "I'm dead!", NEW_LINE, STRING_END

;; The end of the game.
GameOver:
    .byte "The game is now over.", NEW_LINE, STRING_END

;; The light running out.
LightOut:
    .byte "My light has run out!", NEW_LINE, STRING_END

;; The light growing dim.
LightDim:
    .byte "My light is growing dim.", NEW_LINE, STRING_END

;; What comes before the items the player carries.
CarryingHeading:
    .byte "I'm carrying: ", STRING_END

;; The player carrying nothing.
CarryingNothing:
    .byte "I'm carrying nothing.", NEW_LINE, STRING_END

;; What comes before the number of treasures stored.
StoredStart:
    .byte "I've stored ", STRING_END

;; What comes between the treasures stored and the score.
StoredMiddle:
    .byte " treasures. On a scale of 0 to 100, that rates ", STRING_END

;; Every treasure stored.
WellDone:
    .byte "Well done!", NEW_LINE, STRING_END

;; The game asking to be saved.
NoSaving:
    .byte "I can't save the game yet.", NEW_LINE, STRING_END

;; A game this engine can't play.
NotAGame:
    .byte "This is not a game this engine plays.", NEW_LINE, STRING_END

.endscope
