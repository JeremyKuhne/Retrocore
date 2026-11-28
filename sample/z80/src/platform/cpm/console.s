; retrocore: style=strict
;; CP/M's console: the BDOS's console output, for any machine that runs CP/M
;;
;; CP/M owns the console, as SOS owns the Apple III's screen, so the console is the environment's, not a machine
;; family's: it serves the Kaypro II and every other CP/M machine alike.

.include <environment.inc>

;; The console the program writes to.
.scope Console

.section CODE

;; Readies the console. CP/M's console is ready once the CCP has run the program.
.proc Start
    RET
.endproc

;; Writes a character through the BDOS's console output, which keeps no register, so they are kept here.
;; In: A = the character, in ASCII
;; Keeps: BC, DE, HL
.proc Write
    PUSH BC
    PUSH DE
    PUSH HL
    LD E,A
    LD C,CONSOLE_OUTPUT
    CALL BdosEntry
    POP HL
    POP DE
    POP BC
    RET
.endproc

;; Ends the line: a Return and a line feed, which CP/M's console takes as two characters.
;; Keeps: BC, DE, HL
.proc NewLine
    LD A,RETURN
    CALL Write
    LD A,LINE_FEED
    JR Write
.endproc

.endscope
