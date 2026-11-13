;; HELLO FOR THE TRS-80 COLOR COMPUTER
;;
;; Prints a line through Color BASIC's character output vector, CHROUT ($A002), then waits. Debug it with the
;; "Color Computer: 6809 sample" launch configuration: BASIC starts for two seconds first, so the screen and
;; its RAM hooks are set up before the program runs. The call stack shows SHOW called from PRINT.

.cpu M6809

CHROUT = $A002                      ;; holds the address of the routine that prints the character in A

.org $3000

START:
    leax MESSAGE,pcr
PRINT:
    lda ,x+
    beq DONE
    bsr SHOW
    bra PRINT
DONE:
    bra DONE

;; Prints the character in A; CHROUT keeps every register.
SHOW:
    jsr [CHROUT]
    rts

MESSAGE:
    .byte "HELLO FROM THE 6809", $0D, 0
