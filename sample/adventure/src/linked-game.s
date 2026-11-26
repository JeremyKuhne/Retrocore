; retrocore: style=strict
;; The test game, linked into the program
;;
;; Every target links the packed game in for now, as `obj/test.bin`, which the packer writes:
;;
;; > dotnet run tools/packer.cs -- pack games/test.dat obj/test.bin

.section RODATA

;; The packed game, which the engine reads.
Game:
    .incbin "../obj/test.bin"
