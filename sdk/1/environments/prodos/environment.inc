; retrocore: style=strict
;; The prodos environment: an Apple II program as a system file that ProDOS loads at $2000 and starts
;;
;; A project includes it as <environment.inc>. The build writes a ProDOS disk with ProDOS 2.4.3's boot blocks and
;; PRODOS, the program as its system file, named for the project and ending .SYSTEM, which ProDOS runs, when it starts,
;; as the volume's first system file whose name ends .SYSTEM, and the target's files as BIN files. ProDOS loads the
;; program at $2000 and starts it at its first byte, which is its entry or a JMP on to it, with the volume it booted as
;; its prefix, so a file on the disk is opened by its name alone. The program has the Monitor's routines, which the
;; Apple II's <machine.inc> names, and ProDOS's Machine Language Interface, the MLI, which it calls with <MliCall>: JSR
;; <MliEntry>, the call's number, then the address of its parameter list, whose first byte is its count of parameters.
;; The MLI returns with A the error, 0 when there is none, carry set when there is one, and zero set when there is none.
;; ProDOS keeps $BF00-$BFFF, its global page, and the language card's RAM, which it runs in.

.assert .defined(RC_ENV_PRODOS), "environment.inc for prodos is for targets whose environment is prodos."

;; The MLI's entry, at the start of ProDOS's global page, which a program calls with <MliCall>.
;; Also: MLI (P8TRM)
MliEntry = $BF00

;; Makes an MLI call: JSR <MliEntry>, then the call's number, its first argument, such as <OPEN_CALL>, then its second,
;; the address of the call's parameter list.
;; Out: A = the error, 0 when there is none; carry = set when there is one; zero = set when there is none
.macro MliCall number, parameters
    jsr MliEntry
    .byte number
    .word parameters
.endmacro

; The calls, and their parameter lists' counts.

;; QUIT: leaves the program for ProDOS's quit code, which in ProDOS 2.4.3 is Bitsy Bye, its menu of the volumes' files.
;; Its list: the count, the quit type (0), a pointer (0), a byte (0) and a pointer (0).
QUIT_CALL = $65

;; QUIT's count of parameters.
QUIT_COUNT = 4

;; OPEN: opens a file by its pathname. Its list: the count, the pathname's address (a length byte, then the name), the
;; address of a 1,024-byte I/O buffer, which starts a page and is ProDOS's until the file is closed, and the reference
;; number OPEN returns.
OPEN_CALL = $C8

;; OPEN's count of parameters.
OPEN_COUNT = 3

;; NEWLINE: turns new-line mode on or off for an open file: with it on, a READ ends after a byte that, ANDed with the
;; mask, is the new-line character. Its list: the count, the reference number, the mask (0 turns the mode off), and the
;; character.
NEWLINE_CALL = $C9

;; NEWLINE's count of parameters.
NEWLINE_COUNT = 3

;; READ: reads up to a count of bytes from an open file into a buffer. Its list: the count, the reference number, the
;; buffer's address, the count asked for, and the count READ returns.
READ_CALL = $CA

;; READ's count of parameters.
READ_COUNT = 4

;; WRITE: writes a count of bytes from a buffer to an open file. Its list: the count, the reference number, the
;; buffer's address, the count of bytes, and the count WRITE returns.
WRITE_CALL = $CB

;; WRITE's count of parameters.
WRITE_COUNT = 4

;; CLOSE: closes an open file, or with reference number 0, every file. Its list: the count, and the reference number.
CLOSE_CALL = $CC

;; CLOSE's count of parameters.
CLOSE_COUNT = 1

;; The size of the I/O buffer OPEN takes, which starts a page.
IO_BUFFER_SIZE = 1024
