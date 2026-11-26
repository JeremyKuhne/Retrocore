; retrocore: style=strict
;; The game, loaded from the DFS disk
;;
;; A dfs target sets `GAME_LINKED` to 0 and puts Pirate Adventure on its disk as $.PIRATE, from the project's files.
;; <LoadGame> has the filing system load it into <Game>, the buffer the engine reads, through <OSFILE>: from the disk,
;; or from a tape under *TAPE, as the same call loads from either. The MOS's names come from <machine.inc>, which the
;; BBC Micro's console, before this file, includes.

.include <environment.inc>

; The packed game's size, which the packer writes beside it.
.include "../../../obj/pirate.inc"

.assert GAME_LINKED = 0, "A dfs target loads its game from its disk: set GAME_LINKED to 0."
.assert TEST_GAME = 0, "A dfs target loads Pirate Adventure, $.PIRATE, from its disk."

.section BSS

;; The packed game, which <LoadGame> has the filing system load, and the engine reads.
Game:
    .res GAME_SIZE

.section CODE

;; Has the filing system load PIRATE into <Game>, through <OSFILE> with the control block <FileBlock>. A missing file
;; stops the program at the MOS's error.
.proc LoadGame
    ldx #<FileBlock
    ldy #>FileBlock
    lda #FILE_LOAD
    jmp OSFILE
.endproc

.section DATA

;; The <OSFILE> control block: the file's name, then <Game> as the load address, and an execution address whose low
;; byte is 0, so the file loads there rather than at its own load address. <OSFILE> writes the file's details back into
;; the rest.
FileBlock:
    .word FileName
    .word Game, 0
    .word 0, 0
    .res FILE_BLOCK_SIZE - FILE_BLOCK_START

;; The game's file name, ending in a Return.
FileName:
    .byte "PIRATE", NAME_END
