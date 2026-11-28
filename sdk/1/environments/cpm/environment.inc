; retrocore: style=strict
;; The cpm environment: a CP/M 2.2 program as a .COM file, which the CCP loads at $0100 and runs
;;
;; A project includes it as <environment.inc>. The build writes the program as a .COM file, the project's name in
;; capitals cut to eight, and puts it on a copy of the machine's CP/M system disk, which has 4K free; a launch boots
;; the disk and types the name at CP/M's prompt. The CCP loads the program at $0100 and calls it there, with the CCP's return on the stack,
;; so the program goes back with RET while it leaves the CCP alone, or with a warm boot, JP <WarmBoot>, which reloads
;; the CCP from the disk. It calls CP/M through the BDOS: the function's number in C, its argument in E or DE, then
;; CALL <BdosEntry>; a byte comes back in A, and a word in HL. The BDOS keeps no register a program can count on.

.assert .defined(RC_ENV_CPM), "environment.inc for cpm is for targets whose environment is cpm."

;; The warm boot's jump, at the start of page zero: a jump here ends a program and reloads the CCP.
;; Also: BOOT (CPM22OSM)
WarmBoot = $0000

;; The BDOS's entry, the jump at $0005, which every CP/M call goes through. The word at $0006 is the address it
;; jumps to, a few bytes into the BDOS: below it is the memory a program has that ends with a warm boot; one that
;; returns to the CCP keeps the CCP's 2K below the BDOS as well.
;; Also: BDOS (CPM22OSM)
BdosEntry = $0005

;; The default file control block, which the CCP fills from the command's first argument.
;; Also: FCB (CPM22OSM)
DefaultFcb = $005C

;; The default record buffer, which holds the command's tail, its length first, and which file reads and writes use
;; until a program sets another.
;; Also: BUFF (CPM22OSM)
DefaultBuffer = $0080

; The BDOS's functions, by their numbers in C.

;; System reset: ends the program with a warm boot.
SYSTEM_RESET = 0

;; Console input: waits for a key, echoes it, and returns it in A.
CONSOLE_INPUT = 1

;; Console output: writes the character in E.
CONSOLE_OUTPUT = 2

;; Direct console I/O: with $FF in E, returns a waiting key in A, or 0; with another E, writes it.
DIRECT_CONSOLE_IO = 6

;; Print string: writes the characters at DE up to a $.
PRINT_STRING = 9

;; Read console buffer: reads a line into the buffer at DE, whose first byte is its size; the second comes back as
;; the line's length.
READ_CONSOLE_BUFFER = 10

;; Open file: opens the file the FCB at DE names; A comes back $FF when there is none.
OPEN_FILE = 15

;; Close file: closes the file the FCB at DE names.
CLOSE_FILE = 16

;; Read sequential: reads the file's next 128-byte record into the record buffer; A comes back 0, or 1 at the end.
READ_SEQUENTIAL = 20

;; Set DMA address: makes DE the record buffer.
SET_DMA_ADDRESS = 26

; Characters.

;; The character that ends a string for <PRINT_STRING>.
STRING_END = '$'

;; A Return, which with <LINE_FEED> ends a line on the console.
RETURN = $0D

;; A line feed.
LINE_FEED = $0A
