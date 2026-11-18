;; PET BASIC 4 ENTRY POINTS, FOR THE KERNAL
;;
;; The routines of BASIC 4 ($B000-$DFFF) that the kernal calls or jumps to, as equates at their addresses. The kernal
;; reads the parameters of OPEN, CLOSE, LOAD, SAVE, VERIFY and SYS with BASIC's evaluator, reports its errors through
;; BASIC's error printer, and finishes a LOAD through BASIC's own code; those routines are named as Microsoft's
;; m6502.asm names them.
;;
;; BASIC 4 also holds what BASIC 2's kernal did not have room for: the machine-language monitor, which moved out of
;; the kernal, and the disk commands (DOPEN, DIRECTORY and the rest), which BASIC reaches through the kernal's jump
;; table at $FF93. These take the names of Commodore's 1979 BASIC 4 kernal listing, as Basic4.mac names them; where
;; one would clash with a name of m6502.asm's, the overlay changed it (DCOPY, DSCRTC). The jump table's entries take
;; m6502.asm's convention for the kernal's entries, CQ and the command (<CQCONC> and the rest). The kernal includes
;; this file; the editors use nothing of BASIC's.

TYPERR = $B3ED              ;; Resets the stack and prints " ERROR", the line number in a program, then READY.
READY = $B3FF               ;; Prints READY. and enters BASIC's direct mode, the main loop.
FINI = $B4AD                ;; Clears the variables, relinks the program and enters the main loop, after a direct LOAD.
FLOAD = $B60B               ;; Restores DATA and resets the stack, continuing a program after a LOAD from it.
STXTPT = $B622              ;; Sets TXTPTR to just before the start of the program.
STOP = $B7C6                ;; Zero and carry set, as <Kernal4:STOP1> leaves them for the STOP key, end the program with BREAK; zero set and carry clear end it as END does; zero clear returns.
FRMNUM = $BD84              ;; Evaluates a numeric expression into the floating-point accumulator.
FRMEVL = $BD98              ;; Evaluates an expression of either type.
CHKCOM = $BEF5              ;; Skips a comma in the program text, or gives a syntax error.
SNERR = $BF00               ;; Gives the ?SYNTAX ERROR.
FRESTR = $C7B5              ;; Frees the string just evaluated: A = its length, INDEX = its address.
GETBYT = $C8D4              ;; Evaluates an expression into a byte in X.
GETADR = $C92D              ;; Converts the floating-point accumulator to a 16-bit address in LINNUM.
INIT = $D3B6                ;; BASIC's cold start: sets up page zero, sizes memory and prints the sign-on message.

; The monitor.
CALLE = $D472               ;; Enters the monitor at reset, showing "C*" and the registers.
BRKE = $D478                ;; Enters the monitor from BRK, showing "B*" and the registers.
ERROPR = $D7A4              ;; Prints "?" and returns to the monitor's prompt, for a command it couldn't read.

; The disk commands, which the jump table at $FF93 leads to.
RECORD = $D7AF          ;; RECORD: positions a relative file at a record.
CATLOG = $D873          ;; CATALOG and DIRECTORY: lists a disk's directory.
DOPEN = $D942           ;; DOPEN: opens a disk file.
APPEND = $D977          ;; APPEND: opens a sequential disk file to add to its end.
GETDS = $D995           ;; Makes room for DS$ and reads the disk's error channel into it.
FORMAT = $D9D2          ;; HEADER: formats a disk.
DCLOSE = $DA07          ;; DCLOSE: closes a disk file, or all of a unit's files.
COLECT = $DA65          ;; COLLECT: validates a disk, freeing the blocks no file uses.
BACKUP = $DA7E          ;; BACKUP: copies a whole disk to the other drive.
DCOPY = $DAA7            ;; COPY: copies a file, or all of a disk's files to the other drive.
CONCAT = $DAC7          ;; CONCAT: adds one disk file to the end of another.
DSAVE = $DB0D           ;; DSAVE: saves the program to disk.
DLOAD = $DB3A           ;; DLOAD: loads a program from disk.
RENAME = $DB55          ;; RENAME: renames a disk file.
DSCRTC = $DB66          ;; SCRATCH: deletes disk files.
OLDCLR = $DBE1              ;; Forgets the disk status DS$ last read, so that the next use reads it again, and clears ST.
