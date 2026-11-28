; retrocore: style=strict
;; The game, loaded from the ProDOS disk
;;
;; A prodos target sets `GAME_LINKED` to 0 and puts Pirate Adventure on its disk as PIRATE.DAT, a BIN file, from the
;; project's files. <LoadGame> has ProDOS read it into <Game>, the buffer the engine reads, through the MLI: OPEN, READ
;; of the whole buffer, CLOSE. ProDOS starts the program with the boot volume as its prefix, so the file's name is its
;; pathname.

.include <environment.inc>

; The packed game's size, which the packer writes beside it.
.include "../../../obj/pirate.inc"

.assert GAME_LINKED = 0, "A prodos target loads its game from its disk: set GAME_LINKED to 0."
.assert TEST_GAME = 0, "A prodos target loads Pirate Adventure, PIRATE.DAT, from its disk."

;; The I/O buffer ProDOS keeps while the game is open, which starts a page: the four pages below the program, which
;; loads at $2000, in the free RAM the map gives from $0800. A section's .align is from the section's start, not a
;; page's, so the buffer is not in BSS.
GameBuffer = $2000 - IO_BUFFER_SIZE

.section BSS

;; The packed game, which <LoadGame> has ProDOS read, and the engine reads.
Game:
    .res GAME_SIZE

.section DATA

;; The game's pathname, in the prefix: its length, then its name.
GamePath:
    .byte GamePathEnd - GamePath - 1, "PIRATE.DAT"
GamePathEnd:

;; OPEN's parameters for the game.
GameOpen:
    .byte OPEN_COUNT
    .word GamePath
    .word GameBuffer
GameReference:
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

;; Has ProDOS read PIRATE.DAT into <Game>. A missing file leaves <Game> clear, which the engine finds is not a game; a
;; short one is read as far as it goes.
.proc LoadGame
    MliCall OPEN_CALL, GameOpen
    bne Done
    lda GameReference
    sta GameReadReference
    sta GameCloseReference
    MliCall READ_CALL, GameRead
    MliCall CLOSE_CALL, GameClose
Done:
    rts
.endproc
