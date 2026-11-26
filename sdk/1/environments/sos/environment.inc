; retrocore: style=strict
;; The sos environment: an Apple III program as SOS.INTERP on a SOS 1.3 boot disk, which SOS starts at its first byte
;;
;; A project includes it as <environment.inc>. The build writes the program as SOS.INTERP, loaded at $2000 in the
;; system bank, on a boot disk with the SDK's SOS 1.3 kernel and a SOS.DRIVER with the console's driver, and the
;; target's files. SOS starts the program at its first byte, which is its entry or a JMP on to its start, with its own
;; zero page at $1A00, all of it the program's to use, but not clear: SOS leaves bytes there and in the X-bytes of its
;; pointers, <EXTEND_PAGE>, some with bit 7 set, which sends a pointer's (zp),Y to another bank. A program that reads
;; its own memory through a zero-page pointer clears that pointer's X-byte first. The program calls SOS with <SosCall>:
;; BRK, the call's number, then the address of its parameter list, whose first byte is its count of parameters. SOS
;; returns with A the error, 0 when there is none, and Z set to match. A pointer in a parameter list is an address in
;; $2000-$B7FF, in the system bank.

.assert .defined(RC_ENV_SOS), "environment.inc for sos is for targets whose environment is sos."

;; The interpreter's extend page: the X-byte of the pointer in zero page at zp is at EXTEND_PAGE + zp + 1, the page that
;; is its zero page's ($1A00) with $0C00 flipped. With its bit 7 clear, (zp),Y and (zp,X) read the system bank as an
;; absolute address does; with it set, the bank it names.
EXTEND_PAGE = $1600

;; Makes a SOS call: BRK, then the call's number, its first argument, such as <OPEN_CALL>, then its second, the address
;; of the call's parameter list.
;; Out: A = the error, 0 when there is none; Z = set when there is none
.macro SosCall number, parameters
    brk
    .byte number
    .word parameters
.endmacro

; The calls, and their parameter lists' counts.

;; OPEN: opens a file or a device, such as .CONSOLE, by its pathname. Its list: the count, the pathname's address (a
;; length byte, then the name), the reference number OPEN returns, the option list's address, and its length.
OPEN_CALL = $C8

;; OPEN's count of parameters.
OPEN_COUNT = 4

;; NEWLINE: turns new-line mode on or off for an open file: with it on, a READ ends after the new-line character. Its
;; list: the count, the reference number, the mode (bit 7 on), and the character.
NEWLINE_CALL = $C9

;; NEWLINE's count of parameters.
NEWLINE_COUNT = 3

;; READ: reads up to a count of bytes from an open file into a buffer. Its list: the count, the reference number, the
;; buffer's address, the count asked for, and the count READ returns.
READ_CALL = $CA

;; READ's count of parameters.
READ_COUNT = 4

;; WRITE: writes a count of bytes from a buffer to an open file. Its list: the count, the reference number, the
;; buffer's address, and the count of bytes.
WRITE_CALL = $CB

;; WRITE's count of parameters.
WRITE_COUNT = 3

;; CLOSE: closes an open file, or with reference number 0, every file. Its list: the count, and the reference number.
CLOSE_CALL = $CC

;; CLOSE's count of parameters.
CLOSE_COUNT = 1

;; TERMINATE: ends the program; SOS asks for the next disk to boot. Its list: the count, 0.
TERMINATE_CALL = $65

;; TERMINATE's count of parameters.
TERMINATE_COUNT = 0

; The console.

;; The Return that ends a line the console reads, and that new-line mode ends a READ at. Written, it moves the cursor
;; to the start of its line, and down a line only when the console's automatic line feed is on, as it is not at first.
CONSOLE_RETURN = $0D

;; The line feed, which written moves the cursor down a line, scrolling at the bottom.
CONSOLE_LINE_FEED = $0A

;; The console's control code that clears its viewport and puts the cursor at its top left corner.
CONSOLE_CLEAR = $1C
