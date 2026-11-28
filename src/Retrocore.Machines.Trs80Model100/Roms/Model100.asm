;; TRS-80 MODEL 100 AND TANDY 102 ROM ($0000-$7FFF)
;;
;; The Model 100's 32K ROM, which Microsoft wrote for Kyocera and Radio Shack: BASIC, the main menu, TEXT, TELCOM,
;; ADDRSS and SCHEDL, and the drivers for the screen, keyboard, cassette, printer, RS-232 port and modem, for the
;; 80C85. This file assembles all of it from the modules below, in the order of their addresses.
;;
;; The first page holds the restarts. BASIC uses them as one-byte calls: RST 1 checks the next character against the
;; byte that follows it (SYNCHR), RST 2 gets the next character (CHRGET, which jumps to CHRGTR), RST 3 compares HL
;; with DE (DCOMPR), RST 4 prints the character in A (OUTDO), RST 5 tests the accumulator's type (GETYPE, which
;; jumps to GETYPR) and RST 6 its sign (VSIGN). RST 7 takes a byte after it, the number of a hook in RAM that a
;; program can take over (HOOK). Between them are the 80C85's interrupts: TRAP (the power failing), RST55 (the bar
;; code wand), RST65 (the serial port) and RST75 (the clock's 256 Hz tick, which scans the keyboard).
;;
;; BASIC follows Microsoft's design, close to MBASIC's (the SDK's Kaypro/Roms/Mbasic), but its numbers are BCD:
;;
;; - A typed line is crunched into tokens (CRUNCH). With a line number, it goes into the program, which starts at
;;   TXTTAB, its lines linked in order; without one, it runs at once.
;; - NEWSTT runs a statement at a time, GONE dispatching each through STMDSP and the evaluator (FRMEVL) the
;;   functions through FUNDSP. CHRGTR reads the text, skipping spaces.
;; - Numbers are integers, or single or double precision BCD, in the floating accumulator, with their type in
;;   VALTYP. Simple variables follow the program at VARTAB, arrays at ARYTAB, and strings grow down from MEMSIZ to
;;   FRETOP.
;; - An error loads its code into E and jumps to ERROR, which prints its two letters from ERRTAB, or goes to the
;;   ON ERROR GOTO line.
;;
;; Files live in RAM, listed in the directory at DIRTBL: 11 bytes each, a type, an address and an eight-letter name.
;; The ROM's own programs have entries too (ROMDIR), so the menu shows and runs them like files.
;;
;; The modules:
;;
;; - Tables.asm ($0000-$0400): the restarts, FUNDSP, the reserved words, STMDSP, the operators, ERRTAB, the RAM
;;   image that the cold start copies to $F5F0, and the messages.
;; - Interpreter.asm ($0401-$0871): FNDFOR, the errors, READY and MAIN, line links and search, CRUNCH, FOR, NEWSTT,
;;   GONE and CHRGTR.
;; - Statements.asm ($0872-$0DA8): DEF, the line-number scanner, RUN, GOSUB, GOTO, RETURN, DATA, LET, ON, RESUME,
;;   ERROR, IF, PRINT, LINE INPUT, INPUT and READ.
;; - Evaluator.asm ($0DA9-$113A): the formula evaluator, the operators, LPOS, POS, INP, OUT and the argument
;;   helpers.
;; - List.asm ($113B-$12CA): LIST and LLIST, PEEK and POKE.
;; - Devices.asm ($12CB-$19AA): the keyboard queue, POWER, the cassette's motor and bytes, and the drivers that
;;   BASIC opens files on (DEVTAB, DEVDSP).
;; - Commands.asm ($19AB-$220E): the Model 100's own statements, TIME$ to NEW.
;; - Files.asm ($220F-$270B): making a text file, CSAVE and CLOAD.
;; - Strings.asm ($270C-$2B4B): the string package.
;; - Math1.asm and Math2.asm ($2B4C-$3EEF): FRE and the BCD math package.
;; - Misc.asm ($3EF0-$4221): RESTORE, STOP, END, CONT, CLEAR and NEXT.
;; - Lcd.asm ($4222-$4643): the screen's controls, its escape sequences and the function keys' line.
;; - LineInput.asm ($4644-$478A): INLIN, the line editor.
;; - Variables.asm ($478B-$4B43): DIM and the variable search.
;; - Output.asm ($4B44-$4CCA): character output to the screen, the printer and files.
;; - Disk.asm ($4CCB-$5145): OPEN, LOAD, MERGE, SAVE, CLOSE, the file input routines, LOF, LOC, LFILES and DSKO$.
;; - Telcom.asm ($5146-$5796): TELCOM.
;; - Menu.asm ($5797-$5DED): the main menu, the function keys, the directory search, ADDRSS and SCHEDL.
;; - Text.asm ($5DEE-$6B60): TEXT.
;; - Directory.asm ($6B61-$6CD5): inserting and deleting in RAM files, ROMDIR and BASIC's entry.
;; - Io.asm ($6CD6-$6F45): the devices' cold and warm resets, the printer, the RS-232 port and the modem.
;; - Cassette.asm ($6F46-$7241): the cassette's leaders, sync and bytes.
;; - Keyboard.asm ($7242-$744B): the keyboard's scan, BREAK, sound and the clock.
;; - LcdDriver.asm ($744C-$770A): PLOT, UNPLOT and the LCD's drivers.
;; - Font.asm ($770B-$7D32): the keyboard's tables and the character set.
;; - Startup.asm ($7D33-$7FFF): the cold start, the power-up messages and MAX.
;;
;; Equates.asm holds the RAM's names. The modules' boundaries and subjects are a first cut, to be refined as each
;; is named.
;;
;; Assembles byte-identically to the Model 100's ROM or the Tandy 102's: MODEL selects the machine (100, the
;; default, or 102). The 102 changes the reset vector and the cold start, the RAM image, a few routines and glyphs,
;; and adds code in the last bytes; each difference is an .if MODEL = 100 block.
;;
;; Labels are named but not yet converted to the maintained style, as MBASIC's were (docs/conversions/Model100.md):
;; Tandy's names for the documented entry points (M100TR), Microsoft's where the code matches MBASIC's, keywords for
;; the statement and function handlers (ST_FOR, FN_LEFT), and names that say what they are for the tables. The
;; labels the naming has not reached yet keep the disassembler's names, L_ for code and D_ for data, with their
;; address.
;;
;; Maintained by hand. Trs80Model100RomSourceTests check that it assembles to both ROMs.

.ifndef MODEL
MODEL = 100
.endif
.assert (MODEL = 100) | (MODEL = 102), "MODEL is 100 or 102."

.cpu I8085

;; A reserved word: its first letter with bit 7 set marks where it starts.
.macro KEYWORD word
    .byte .strat(word, 0) | $80
    .repeat .strlen(word) - 1, index
    .byte .strat(word, index + 1)
    .endrepeat
.endmacro

;; An entry in a table of keys: the character, then the routine for it.
.macro DISPATCH key, routine
    .byte key
    .word routine
.endmacro

.include "Equates.asm"

.include "Tables.asm"
.include "Interpreter.asm"
.include "Statements.asm"
.include "Evaluator.asm"
.include "List.asm"
.include "Devices.asm"
.include "Commands.asm"
.include "Files.asm"
.include "Strings.asm"
.include "Math1.asm"
.include "Math2.asm"
.include "Misc.asm"
.include "Lcd.asm"
.include "LineInput.asm"
.include "Variables.asm"
.include "Output.asm"
.include "Disk.asm"
.include "Telcom.asm"
.include "Menu.asm"
.include "Text.asm"
.include "Directory.asm"
.include "Io.asm"
.include "Cassette.asm"
.include "Keyboard.asm"
.include "LcdDriver.asm"
.include "Font.asm"
.include "Startup.asm"
