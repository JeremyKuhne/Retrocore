; retrocore: style=strict
;; The game, loaded from the DOS 3.3 disk
;;
;; A dos33 target sets `GAME_LINKED` to 0 and puts Pirate Adventure on its disk as PIRATE.DAT, a B file, from the
;; project's files. <LoadGame> has DOS load it into <Game>, the buffer the engine reads, by writing a BLOAD command
;; through the Monitor's <CharacterOut>, which DOS watches. That is before the console starts, while DOS is still in the
;; output hook. The Monitor's names come from <machine.inc>, which the Apple II's console, before this file, includes.

.include <environment.inc>

; The packed game's size, which the packer writes beside it.
.include "../../../obj/pirate.inc"

.assert GAME_LINKED = 0, "A dos33 target loads its game from its disk: set GAME_LINKED to 0."
.assert TEST_GAME = 0, "A dos33 target loads Pirate Adventure, PIRATE.DAT, from its disk."

;; A Return, with its high bit set, as <CharacterOut> takes it, which ends DOS's command.
COMMAND_END = $8D

;; The high bit <CharacterOut> takes characters with.
SCREEN_BIT = $80

.section BSS

;; The packed game, which <LoadGame> has DOS load from the disk, and the engine reads.
Game:
    .res GAME_SIZE

.section CODE

;; Has DOS load PIRATE.DAT into <Game>: writes a Return, so the command starts a line, then Ctrl-D and
;; `BLOAD PIRATE.DAT,A$` with <Game>'s address in hex, and a Return, which DOS carries out. A missing file stops the
;; program at DOS's error, in BASIC.
.proc LoadGame
    ldx #0
NextCharacter:
    lda Command,x
    beq Address
    ora #SCREEN_BIT
    jsr CharacterOut
    inx
    bne NextCharacter
Address:
    lda #>Game
    jsr PrintHexByte
    lda #<Game
    jsr PrintHexByte
    lda #COMMAND_END
    jmp CharacterOut
.endproc

.section RODATA

;; The command up to the address, ending in 0: a Return, Ctrl-D, then the command, each character's high bit set
;; as it is written.
Command:
    .byte COMMAND_END, DOS_COMMAND, "BLOAD PIRATE.DAT,A$", 0
