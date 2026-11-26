; retrocore: style=strict
;; The game, linked into the program
;;
;; Every target links its packed game in, as the project's steps write it with the packer before the build
;; assembles: Pirate Adventure, `obj/pirate.bin`, or with `TEST_GAME` set to 1, the test game, `obj/test.bin`.
;;
;; | Build | `TEST_GAME` | The game |
;; | --- | --- | --- |
;; | Pirate Adventure, every target but `apple2-test` | 0 (the project's define) | `obj/pirate.bin` |
;; | The test game, `apple2-test` | 1 (the target's define) | `obj/test.bin` |

.assert TEST_GAME = 0 || TEST_GAME = 1, "TEST_GAME is 1 for the test game or 0 for Pirate Adventure."

.section RODATA

;; The packed game, which the engine reads.
Game:
.if TEST_GAME
    .incbin "../obj/test.bin"
.else
    .incbin "../obj/pirate.bin"
.endif
