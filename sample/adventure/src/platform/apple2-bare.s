; retrocore: style=strict
;; The adventure on a bare Apple II, with the test game linked in
;;
;; The program loads at $0800 and starts there, and needs nothing but the Monitor's ROM: no DOS and no BASIC. Pack the
;; game first, as `obj/test.bin`:
;;
;; > dotnet run tools/packer.cs -- pack games/test.dat obj/test.bin
;;
;; Then debug this file with a `source` launch on the Apple II, or assemble it with `apple2-bare.cfg`.

.cpu Mos6502

;; Starts the game.
.proc Entry
    jmp Engine::Start
.endproc

.include "apple2/console.s"
.include "../core/game.s"
.include "../core/text.s"
.include "../core/phrases.s"
.include "../core/numbers.s"
.include "../core/parser.s"
.include "../core/world.s"
.include "../core/actions.s"
.include "../core/conditions.s"
.include "../core/codes.s"
.include "../core/engine.s"

.section RODATA

;; The packed game.
Game:
    .incbin "../../obj/test.bin"
