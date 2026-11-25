;; THE PRINTER HANDLER (P:)
;;
;; The routines behind PRINTV's vectors. The printer prints a line at a time, so the handler gathers the bytes put to
;; it in PRNBUF and sends a line when it is full or ends with an end of line, padded with blanks. The open mode's
;; auxiliary byte 2 picks the line's length: normal, double width or sideways. A status asks the printer for its
;; 4 bytes, keeping its timeout for the lines that follow.

; The printer's serial bus ID, its commands and its modes.

PRINTER_WRITE = 'W'                 ;; send a line to print
PRINTER_GET_STATUS = 'S'            ;; read the printer's 4-byte status into DVSTAT
PRINTER_NORMAL = 'N'                ;; ICAX2's normal mode, 40 characters a line, also for any unknown mode
PRINTER_DOUBLE = 'D'                ;; ICAX2's double width mode, 20 characters a line
PRINTER_SIDEWAYS = 'S'              ;; ICAX2's sideways mode, 29 characters a line

PRINTER_NORMAL_WIDTH = 40           ;; the bytes in a normal line, PRNBUF's size
PRINTER_DOUBLE_WIDTH = 20           ;; the bytes in a double width line
PRINTER_SIDEWAYS_WIDTH = 29         ;; the bytes in a sideways line
PRINTER_STATUS_SIZE = 4             ;; the bytes in a status
PRINTER_STATUS_TIMEOUT = 2          ;; the offset in a status of the printer's timeout, in seconds
PRINTER_FIRST_TIMEOUT = 30          ;; the timeout, in seconds, until a status gives the printer's own

;; Initializes the printer handler: sets the timeout, PTIMOT, to 30 seconds.
;; Out: A = PRINTER_FIRST_TIMEOUT
;; Keeps: X, Y
;; See: <PRINTER_STATUS>
PRINTER_INIT:
    lda #PRINTER_FIRST_TIMEOUT
    sta PTIMOT
    rts

;; The address of DVSTAT, where a status goes, for <PRINTER_SET_DCB>.
PRINTER_STATUS_ADDRESS:
    .word DVSTAT

;; The address of PRNBUF, the line buffer, for <PRINTER_SET_DCB>.
PRINTER_BUFFER_ADDRESS:
    .word PRNBUF

;; The printer's STATUS: reads its 4-byte status into DVSTAT, and keeps its timeout from it in PTIMOT.
;;
;; The command's auxiliary byte is also 'S'. PBUFSZ is left at 4 until the next put or close sets it from the mode.
;; Out: Y = the status, negative = set on an error (on success the flags follow PTIMOT), DVSTAT = the printer's status
;; Uses: A, X, PBUFSZ, DDEVIC..DAUX1
;; Errors: Y = SIO's status: TIMOUT, DNACK, DERROR, FRMERR, OVRRUN, CHKERR or BRKABT
;; Entry: PRINTER_STATUS_DONE = returns at once, for GET and SPECIAL, which the printer lacks: Y is CIO's FNCNOT
;; See: <PRINTER_SAVE_TIMEOUT>
PRINTER_STATUS:
    lda #PRINTER_STATUS_SIZE
    sta PBUFSZ
    ldx PRINTER_STATUS_ADDRESS
    ldy PRINTER_STATUS_ADDRESS+1
    lda #PRINTER_GET_STATUS
    sta DCOMND
    sta DAUX1
    jsr PRINTER_SET_DCB
    jsr SIOV
    bmi PRINTER_STATUS_DONE
    jsr PRINTER_SAVE_TIMEOUT
PRINTER_STATUS_DONE:
    rts

;; The printer's OPEN: reads the printer's status, for its timeout, and empties the line buffer.
;;
;; The printer's mode is read from ICAX2Z on each put and close, so the open doesn't look at it.
;; Out: Y = the status; the flags don't follow it
;; Uses: A, X, PBPNT, PBUFSZ, DDEVIC..DAUX1
;; Errors: Y = SIO's status: TIMOUT, DNACK, DERROR, FRMERR, OVRRUN, CHKERR or BRKABT
;; See: <PRINTER_STATUS>
PRINTER_OPEN:
    jsr PRINTER_STATUS
    lda #$00
    sta PBPNT
    rts

;; The printer's PUT: adds a byte to the line in PRNBUF, and prints the line when it is full or the byte is an end of
;; line.
;;
;; An end of line stays in the line, and blanks fill the rest of it. Printing empties the buffer.
;; In: A = the byte, ICAX2Z = the mode
;; Out: Y = SUCCES, or the status when a line was printed, negative = set on an error
;; Uses: A, X, PTEMP, PBPNT, PBUFSZ, DDEVIC..DAUX1
;; Errors: Y = SIO's status: TIMOUT, DNACK, DERROR, FRMERR, OVRRUN, CHKERR or BRKABT
;; Entry: PRINTER_PUT_PAD = pads the line from X with blanks and prints it, for <PRINTER_CLOSE>
;; See: <PRINTER_SET_MODE>
PRINTER_PUT:
    sta PTEMP
    jsr PRINTER_SET_MODE
    ldx PBPNT
    lda PTEMP
    sta PRNBUF,x
    inx
    cpx PBUFSZ
    beq PRINTER_PUT_LINE                ; the line is full
    stx PBPNT
    cmp #EOL
    beq PRINTER_PUT_PAD
    ldy #SUCCES
    rts
PRINTER_PUT_PAD:
    lda #' '
PRINTER_PUT_PAD_LOOP:
    sta PRNBUF,x
    inx
    cpx PBUFSZ
    bne PRINTER_PUT_PAD_LOOP
PRINTER_PUT_LINE:
    lda #$00
    sta PBPNT
    ldx PRINTER_BUFFER_ADDRESS
    ldy PRINTER_BUFFER_ADDRESS+1
    jsr PRINTER_SET_DCB
    jsr SIOV
    rts

;; The printer's CLOSE: prints the line in PRNBUF, padded with blanks, if it holds anything.
;; In: ICAX2Z = the mode
;; Out: Y = SUCCES, or the status when a line was printed, negative = set on an error
;; Uses: A, X, PBPNT, PBUFSZ, DDEVIC..DAUX1
;; Errors: Y = SIO's status: TIMOUT, DNACK, DERROR, FRMERR, OVRRUN, CHKERR or BRKABT
;; See: <PRINTER_PUT>
PRINTER_CLOSE:
    jsr PRINTER_SET_MODE
    ldx PBPNT
    bne PRINTER_PUT_PAD
    ldy #SUCCES
    rts

;; Fills in DDEVIC..DAUX1 for the printer, with DCOMND and DAUX1 already set.
;;
;; A status receives; a line is sent. The byte count is PBUFSZ and the timeout PTIMOT.
;; In: X = the buffer's low byte, Y = its high byte, DCOMND = the command
;; Uses: A, X, DBUFLO/DBUFHI, DDEVIC, DUNIT, DSTATS, DBYTLO/DBYTHI, DTIMLO
;; Keeps: Y
PRINTER_SET_DCB:
    stx DBUFLO
    sty DBUFHI
    lda #PRINTER_ID
    sta DDEVIC
    lda #$01
    sta DUNIT                           ; P1:, the only printer
    lda #DCB_SEND
    ldx DCOMND
    cpx #PRINTER_GET_STATUS
    bne PRINTER_SET_DCB_1
    lda #DCB_RECEIVE
PRINTER_SET_DCB_1:
    sta DSTATS
    lda PBUFSZ
    sta DBYTLO
    lda #$00
    sta DBYTHI
    lda PTIMOT
    sta DTIMLO
    rts

;; Keeps the printer's timeout from the status in DVSTAT, in PTIMOT.
;; Out: A = PTIMOT = the timeout, in seconds
;; Keeps: X, Y
PRINTER_SAVE_TIMEOUT:
    lda DVSTAT+PRINTER_STATUS_TIMEOUT
    sta PTIMOT
    rts

;; Sets up a line for the mode in ICAX2Z: its length in PBUFSZ, and a write command with the mode as its auxiliary
;; byte.
;;
;; A mode other than 'N', 'D' or 'S' is taken as 'N'. The OS User's Manual names 'W' for wide printing, but the code
;; tests 'D'.
;; In: ICAX2Z = the mode
;; Out: PBUFSZ = the line's length, DCOMND = 'W', DAUX1 = the mode
;; Uses: A, X, Y
PRINTER_SET_MODE:
    ldy #PRINTER_WRITE
    lda ICAX2Z
PRINTER_SET_MODE_TEST:
    cmp #PRINTER_NORMAL
    bne PRINTER_SET_MODE_DOUBLE
    ldx #PRINTER_NORMAL_WIDTH
    bne PRINTER_SET_MODE_STORE          ; always
PRINTER_SET_MODE_DOUBLE:
    cmp #PRINTER_DOUBLE
    bne PRINTER_SET_MODE_SIDEWAYS
    ldx #PRINTER_DOUBLE_WIDTH
    bne PRINTER_SET_MODE_STORE          ; always
PRINTER_SET_MODE_SIDEWAYS:
    cmp #PRINTER_SIDEWAYS
    bne PRINTER_SET_MODE_UNKNOWN
    ldx #PRINTER_SIDEWAYS_WIDTH
PRINTER_SET_MODE_STORE:
    stx PBUFSZ
    sty DCOMND
    sta DAUX1
    rts
PRINTER_SET_MODE_UNKNOWN:
    lda #PRINTER_NORMAL
    bne PRINTER_SET_MODE_TEST           ; always
