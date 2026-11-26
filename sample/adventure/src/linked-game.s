; retrocore: style=strict
;; The game, linked into the program
;;
;; A target with `GAME_LINKED` set to 1, the project's define, links its packed game in, as the project's steps write
;; it with the packer before the build assembles: Pirate Adventure, `obj/pirate.bin`, or with `TEST_GAME` set to 1, the
;; test game, `obj/test.bin`. A target that loads the game from its disk sets `GAME_LINKED` to 0, and its environment's
;; platform folder gives <Game> and <LoadGame> instead.
;;
;; | Build | `GAME_LINKED` | `TEST_GAME` | The game |
;; | --- | --- | --- | --- |
;; | Pirate Adventure, linked in | 1 (the project's define) | 0 (the project's define) | `obj/pirate.bin` |
;; | The test game, `apple2-test` | 1 | 1 (the target's define) | `obj/test.bin` |
;; | Pirate Adventure from the disk, `apple2-dos` and `bbc-dfs` | 0 (the target's define) | 0 | `PIRATE.DAT` or `$.PIRATE`, loaded |

.assert TEST_GAME = 0 || TEST_GAME = 1, "TEST_GAME is 1 for the test game or 0 for Pirate Adventure."
.assert GAME_LINKED = 0 || GAME_LINKED = 1, "GAME_LINKED is 1 for a game linked in or 0 for one loaded from a disk."

.if GAME_LINKED

.section RODATA

;; The packed game, which the engine reads.
Game:
.if TEST_GAME
    .incbin "../obj/test.bin"
.else
    .incbin "../obj/pirate.bin"
.endif

.section CODE

;; Loads the game, which is linked in, so there is nothing to load.
.proc LoadGame
    rts
.endproc

.endif
