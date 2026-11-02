;; HELLO FOR THE TRS-80 MODEL I
;;
;; Prints a line through the Level II ROM call DISPLAY_CHAR ($0033), then waits. Debug it with the
;; "Model I: Z80 sample" launch configuration: the ROM boots for a second first, so its RAM vectors and
;; device control blocks are set up before the program runs. Stepping into the CALL goes into the SDK's
;; Level2.asm.

.cpu Z80

DISPLAY_CHAR = $0033                ;; shows the character in A at the cursor

.org $7000

START:
    LD HL,MESSAGE
PRINT:
    LD A,[HL]
    OR A
    JR Z,DONE
    CALL DISPLAY_CHAR
    INC HL
    JR PRINT
DONE:
    JR DONE

MESSAGE:
    .byte "HELLO FROM THE Z80", $0D, 0
