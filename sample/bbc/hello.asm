;; HELLO FOR THE BBC MICRO
;;
;; Prints a line through the MOS's OSASCI, then waits. Debug it with the "BBC Micro: 6502 sample" launch configuration:
;; the MOS and BASIC start for two seconds first, so the screen and the vectors are set up before the program runs.
;; Stepping into OSASCI goes on into the MOS's source, Mos.asm, and the call stack shows SHOW called from PRINT.

.cpu Mos6502

OSASCI = $FFE3                      ;; writes the character in A, a carriage return as a new line; keeps X and Y

.org $2000

START:
    ldx #0
PRINT:
    lda MESSAGE,x
    beq DONE
    jsr SHOW
    inx
    bne PRINT
DONE:
    jmp DONE

;; Prints the character in A.
;; In: A = the character
;; Keeps: X, Y
SHOW:
    jsr OSASCI
    rts

MESSAGE:
    .byte "HELLO FROM THE 6502", $0D, 0
