;; HELLO FOR THE ATARI 400 AND 800
;;
;; Prints a line through CIO, the OS's central input/output, on IOCB 0, the screen editor, then waits. Debug it with
;; the "Atari 800: 6502 sample" launch configuration: the OS and BASIC start for two seconds first, so CIO and the
;; screen are set up before the program runs. The call stack shows PRINT called from START.

.cpu Mos6502

CIOV = $E456                        ;; CIO's entry: X = the IOCB's number times 16
ICCOM = $0342                       ;; IOCB 0's command
ICBAL = $0344                       ;; IOCB 0's buffer address, low byte
ICBAH = $0345                       ;; IOCB 0's buffer address, high byte
ICBLL = $0348                       ;; IOCB 0's buffer length, low byte
ICBLH = $0349                       ;; IOCB 0's buffer length, high byte
CPBINR = $0B                        ;; CIO's put bytes command, which writes a buffer's characters
EOL = $9B                           ;; ATASCII's end of line

.org $2000

START:
    jsr PRINT
DONE:
    jmp DONE

;; Prints MESSAGE on the screen through IOCB 0, the screen editor, which the OS opens as it starts.
;; Out: Y = CIO's status, negative = set on an error
;; Uses: A, X
PRINT:
    ldx #$00
    lda #CPBINR
    sta ICCOM
    lda #<MESSAGE
    sta ICBAL
    lda #>MESSAGE
    sta ICBAH
    lda #MESSAGE_LENGTH
    sta ICBLL
    lda #$00
    sta ICBLH
    jmp CIOV

MESSAGE:
    .byte "HELLO FROM THE 6502", EOL
MESSAGE_LENGTH = * - MESSAGE        ;; the message's length, its EOL included
