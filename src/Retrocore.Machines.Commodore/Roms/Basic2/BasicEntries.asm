;; PET BASIC 2 ENTRY POINTS, FOR THE EDITOR AND THE KERNAL
;;
;; The routines of BASIC 2 ($C000-$E1DD) that the kernal calls or jumps to, as equates at their addresses, named as
;; Microsoft's m6502.asm names them. The kernal reads the parameters of OPEN, CLOSE, LOAD, SAVE, VERIFY and SYS
;; with BASIC's evaluator, reports its errors through BASIC's error printer, and finishes a LOAD through BASIC's
;; own code. Both the editor and the kernal include this file.

TYPERR = $C377              ;; Resets the stack and prints " ERROR", the line number in a program, then READY.
READY = $C389               ;; Prints READY. and enters BASIC's direct mode, the main loop.
FINI = $C439                ;; Clears the variables, relinks the program and enters the main loop, after a direct LOAD.
FLOAD = $C590               ;; Restores DATA and resets the stack, continuing a program after a LOAD from it.
STXTPT = $C5A7              ;; Sets TXTPTR to just before the start of the program.
STOP = $C73F                ;; Zero and carry set, as <Kernal2:STOP1> leaves them for the STOP key, end the program with BREAK; zero set and carry clear end it as END does; zero clear returns.
FRMNUM = $CC8B              ;; Evaluates a numeric expression into the floating-point accumulator.
FRMEVL = $CC9F              ;; Evaluates an expression of either type.
CHKCOM = $CDF8              ;; Skips a comma in the program text, or gives a syntax error.
SNERR = $CE03               ;; Gives the ?SYNTAX ERROR.
FRESTR = $D57D              ;; Frees the string just evaluated: A = its length, INDEX = its address.
GETBYT = $D678              ;; Evaluates an expression into a byte in X.
GETADR = $D6D2              ;; Converts the floating-point accumulator to a 16-bit address in LINNUM.
INIT = $E116                ;; BASIC's cold start: sets up page zero, sizes memory and prints the sign-on message.
