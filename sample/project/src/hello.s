;; HELLO FROM A PROJECT
;;
;; Prints a line through the Monitor's COUT, then waits. It is built by retrocore.json beside this folder, for a II Plus
;; and an enhanced IIe as bare targets, loaded at $6000; the IIe's target defines LOWERCASE, so it prints its line in
;; lowercase, which the II Plus cannot show.

COUT = $FDED                        ;; writes the character in A at the cursor

START:
    ldx #0
PRINT:
    lda MESSAGE,x
    beq DONE
    jsr COUT
    inx
    bne PRINT
DONE:
    jmp DONE

MESSAGE:
.ifdef LOWERCASE
    .hiascii $0D, "hello from a project", $0D
.else
    .hiascii $0D, "HELLO FROM A PROJECT", $0D
.endif
    .byte 0
