; retrocore: style=strict
;; The game, loaded from the SOS disk
;;
;; A sos target sets `GAME_LINKED` to 0 and puts Pirate Adventure on its boot disk as PIRATE.DAT, from the project's
;; files. <LoadGame> has SOS read it into <Game>, the buffer the engine reads: OPEN, READ of the whole buffer, CLOSE.
;; The SOS names come from <environment.inc>, which the console, before this file, includes.

; The packed game's size, which the packer writes beside it.
.include "../../../obj/pirate.inc"

.assert GAME_LINKED = 0, "A sos target loads its game from its disk: set GAME_LINKED to 0."
.assert TEST_GAME = 0, "A sos target loads Pirate Adventure, PIRATE.DAT, from its disk."

.section BSS

;; The packed game, which <LoadGame> has SOS read, and the engine reads.
Game:
    .res GAME_SIZE

.section DATA

;; The game's pathname, on the boot disk in .D1: its length, then its name.
GamePath:
    .byte GamePathEnd - GamePath - 1, ".D1/PIRATE.DAT"
GamePathEnd:

;; OPEN's parameters for the game.
GameOpen:
    .byte OPEN_COUNT
    .word GamePath
GameReference:
    .byte 0
    .word 0
    .byte 0

;; READ's parameters for the whole game.
GameRead:
    .byte READ_COUNT
GameReadReference:
    .byte 0
    .word Game
    .word GAME_SIZE
GameReadLength:
    .word 0

;; CLOSE's parameters for the game.
GameClose:
    .byte CLOSE_COUNT
GameCloseReference:
    .byte 0

.section CODE

;; Has SOS read PIRATE.DAT into <Game>. A file that is missing or short leaves <Game> as it was, which the engine
;; finds is not a game.
.proc LoadGame
    SosCall OPEN_CALL, GameOpen
    bne Done
    lda GameReference
    sta GameReadReference
    sta GameCloseReference
    SosCall READ_CALL, GameRead
    SosCall CLOSE_CALL, GameClose
Done:
    rts
.endproc
