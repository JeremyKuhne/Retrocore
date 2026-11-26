; retrocore: style=strict
;; The test game, linked into the program
;;
;; Every target links the packed game in for now, as `obj/test.bin`, which the project's step writes with the
;; packer before the build assembles.

.section RODATA

;; The packed game, which the engine reads.
Game:
    .incbin "../obj/test.bin"
