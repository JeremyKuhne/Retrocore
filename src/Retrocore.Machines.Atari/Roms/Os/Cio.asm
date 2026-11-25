;; CIO, THE CENTRAL INPUT/OUTPUT UTILITY ($E4A6-$E6D4)
;;
;; CIO's initialization, its main routine behind CIOV, and its helpers: it checks the IOCB, copies it to the zero-page
;; IOCB, finds the device's handler in HATABS, and carries out OPEN, CLOSE, GET, PUT, STATUS and the device's own
;; commands by calling the handler's routines through its vector table, one byte at a time.

; CIO's constants.

CIO_CLOSED = $FF                    ;; ICHID's value for a closed IOCB
CIO_BINARY = %00000010              ;; the bit set in the byte commands' codes ($06-$07, $0A-$0B), clear in records'
CIO_FIRST_SPECIAL = $0E             ;; the first device-specific command: every command from here up calls SPECIAL
CIO_DEFAULT_UNIT = 1                ;; the device number for a name without a digit, such as "D:"
CIO_HATABS_ENTRIES = 12             ;; the number of entries HATABS holds, 3 bytes each
CIO_LAST_ENTRY = (CIO_HATABS_ENTRIES - 1) * 3 ;; the offset of HATABS's last entry
CIO_ZIOCB_SIZE = ICAX2Z + 1 - ICHIDZ ;; the bytes of an IOCB CIO copies to and from the zero-page IOCB

;; Initializes CIO: marks all eight IOCBs closed, with their put-byte vectors at <CIO_PUT_NOT_OPEN>.
;; Uses: A, X
;; See: <CIOINV>
CIO_INIT:
    ldx #$00
CIO_INIT_LOOP:
    lda #CIO_CLOSED
    sta ICHID,x
    lda #<(CIO_PUT_NOT_OPEN-1)
    sta ICPTL,x
    lda #>(CIO_PUT_NOT_OPEN-1)
    sta ICPTH,x
    txa
    clc
    adc #IOCB_SIZE
    tax
    cmp #IOCB_SIZE * IOCB_COUNT
    bcc CIO_INIT_LOOP
    rts

;; A closed IOCB's put-byte routine, which ICPTL/ICPTH point to (less 1): it fails with NOTOPN.
;; Out: Y = NOTOPN
CIO_PUT_NOT_OPEN:
    ldy #NOTOPN
    rts

;; Carries out the command in an IOCB: CIOV's routine.
;;
;; It copies the IOCB to the zero-page IOCB, dispatches on the command through <CIO_COMMAND_OFFSETS>, and copies the
;; zero-page IOCB back, with the buffer address as it was and the buffer length set to the number of bytes moved.
;; Commands below COPN fail with NVALID, and those from <CIO_FIRST_SPECIAL> up go to the handler's SPECIAL routine.
;; GET and PUT with a buffer length of 0 move the single byte in A.
;; In: A = the byte for a single-byte PUT, X = the IOCB's number times 16, ICCOM,X.. = the IOCB
;; Out: A = the byte from a single-byte GET, Y = the status, negative = set on error
;; Uses: ICHIDZ..ICAX2Z, ICCOMT, ICSPRZ, ICIDNO, CIOCHR
;; Keeps: X
;; Errors: Y = BADIOC for an invalid IOCB number, NVALID, PRVOPN, NONDEV, NOTOPN, WRONLY, RDONLY, TRNRCD, or the
;;   handler's status
;; See: <CIOV>, <ICHID>, <HATABS>
CIO_MAIN:
    sta CIOCHR
    stx ICIDNO
    txa
    and #IOCB_SIZE - 1
    bne CIO_BAD_IOCB                ; not a multiple of 16
    cpx #IOCB_SIZE * IOCB_COUNT
    bcc CIO_MAIN_COPY
CIO_BAD_IOCB:
    ldy #BADIOC
    jmp CIO_RETURN_STATUS           ; which still copies the zero-page IOCB to $0340+X
CIO_MAIN_COPY:
    ldy #$00
CIO_MAIN_COPY_LOOP:
    lda ICHID,x
    sta ICHIDZ,y
    inx
    iny
    cpy #CIO_ZIOCB_SIZE
    bcc CIO_MAIN_COPY_LOOP
    ldy #NVALID
    lda ICCOMZ
    cmp #COPN
    bcc CIO_OPEN_FAIL               ; commands 0-2 are invalid
    tay
    cpy #CIO_FIRST_SPECIAL
    bcc CIO_MAIN_DISPATCH
    ldy #CIO_FIRST_SPECIAL          ; every device-specific command is one
CIO_MAIN_DISPATCH:
    sty ICCOMT
    lda CIO_COMMAND_OFFSETS - COPN,y
    beq CIO_OPEN
    cmp #HANDLER_CLOSE
    beq CIO_CLOSE
    cmp #HANDLER_STATUS
    bcs CIO_STATUS                  ; STATUS or SPECIAL
    cmp #HANDLER_GET
    beq CIO_GET
    jmp CIO_PUT

;; Opens the IOCB: finds the device named in the buffer, calls its handler's OPEN, and sets the put-byte vector.
;;
;; The IOCB counts as open even when the handler's OPEN fails, so it must still be closed.
;; In: ICBALZ/ICBAHZ = the device's name, such as "D1:FILE", ICAX1Z/ICAX2Z = the handler's open options
;; Errors: Y = PRVOPN when the IOCB is already open, NONDEV when HATABS has no such device, or the handler's status
;; Entry: CIO_OPEN_FAIL = returns the status in Y, for the other commands' checks too
CIO_OPEN:
    lda ICHIDZ
    cmp #CIO_CLOSED
    beq CIO_OPEN_DEVICE
    ldy #PRVOPN
CIO_OPEN_FAIL:
    jmp CIO_RETURN_STATUS
CIO_OPEN_DEVICE:
    jsr CIO_FIND_DEVICE
    bcs CIO_OPEN_FAIL
    jsr CIO_FIND_ROUTINE
    bcs CIO_OPEN_FAIL
    jsr CIO_CALL_HANDLER
    lda #CPBINR                     ; any put command finds the PUT BYTE routine
    sta ICCOMT
    jsr CIO_FIND_ROUTINE
    lda ICSPRZ
    sta ICPTLZ
    lda ICSPRZ+1
    sta ICPTHZ
    jmp CIO_RETURN

;; Closes the IOCB, calling its handler's CLOSE when it is open, and points its put-byte vector at
;; <CIO_PUT_NOT_OPEN>.
;;
;; Closing a closed IOCB succeeds.
;; Errors: Y = the handler's status
CIO_CLOSE:
    ldy #SUCCES
    sty ICSTAZ
    jsr CIO_FIND_ROUTINE
    bcs CIO_CLOSE_MARK              ; not open
    jsr CIO_CALL_HANDLER
CIO_CLOSE_MARK:
    lda #CIO_CLOSED
    sta ICHIDZ
    lda #>(CIO_PUT_NOT_OPEN-1)
    sta ICPTHZ
    lda #<(CIO_PUT_NOT_OPEN-1)
    sta ICPTLZ
    jmp CIO_RETURN

;; Carries out STATUS or a device-specific command through the handler's STATUS or SPECIAL routine.
;;
;; On a closed IOCB it finds the device from the name in the buffer, as OPEN does, and leaves the IOCB closed.
;; Errors: Y = NONDEV when a closed IOCB names no device in HATABS, or the handler's status
CIO_STATUS:
    lda ICHIDZ
    cmp #CIO_CLOSED
    bne CIO_STATUS_CALL
    jsr CIO_FIND_DEVICE
    bcs CIO_OPEN_FAIL
CIO_STATUS_CALL:
    jsr CIO_FIND_ROUTINE
    jsr CIO_CALL_HANDLER
    ldx ICIDNO
    lda ICHID,x                     ; closed again, if it was
    sta ICHIDZ
    jmp CIO_RETURN

;; Gets a record or bytes into the buffer, or a single byte into A when the buffer length is 0.
;;
;; A record (a get command with <CIO_BINARY> clear, $04-$05) ends with its <EOL>, which is stored. When the
;; buffer fills first, the rest of the record is read and dropped, and the status is TRNRCD.
;; In: ICBALZ/ICBAHZ = the buffer, ICBLLZ/ICBLHZ = its length
;; Out: CIOCHR = the last byte read
;; Errors: Y = WRONLY when the IOCB isn't open for reading, NOTOPN, TRNRCD, or the handler's status
CIO_GET:
    lda ICCOMZ
    and ICAX1Z                      ; the get commands' bit 2 is OREAD
    bne CIO_GET_OPEN
    ldy #WRONLY
CIO_GET_FAIL:
    jmp CIO_RETURN_STATUS
CIO_GET_OPEN:
    jsr CIO_FIND_ROUTINE
    bcs CIO_GET_FAIL
    lda ICBLLZ
    ora ICBLHZ
    bne CIO_GET_LOOP
    jsr CIO_CALL_HANDLER            ; a single byte
    sta CIOCHR
    jmp CIO_RETURN
CIO_GET_LOOP:
    jsr CIO_CALL_HANDLER
    sta CIOCHR
    bmi CIO_GET_DONE                ; an error
    ldy #$00
    sta (ICBALZ),y
    jsr CIO_NEXT_ADDRESS
    lda ICCOMZ
    and #CIO_BINARY
    bne CIO_GET_NEXT
    lda CIOCHR
    cmp #EOL
    bne CIO_GET_NEXT
    jsr CIO_COUNT_DOWN              ; the record's end
    jmp CIO_GET_DONE
CIO_GET_NEXT:
    jsr CIO_COUNT_DOWN
    bne CIO_GET_LOOP
    lda ICCOMZ
    and #CIO_BINARY
    bne CIO_GET_DONE
CIO_GET_DISCARD:
    jsr CIO_CALL_HANDLER            ; the buffer is full: drop the rest of the record
    sta CIOCHR
    bmi CIO_GET_DONE
    lda CIOCHR
    cmp #EOL
    bne CIO_GET_DISCARD
    lda #TRNRCD
    sta ICSTAZ
CIO_GET_DONE:
    jsr CIO_SET_COUNT
    jmp CIO_RETURN

;; Puts a record or bytes from the buffer, or the single byte in CIOCHR when the buffer length is 0.
;;
;; A record ends at its first <EOL>; when the buffer holds none, an EOL is put after it. So a single-byte put
;; record of anything but an EOL puts the byte and then an EOL.
;; In: ICBALZ/ICBAHZ = the buffer, ICBLLZ/ICBLHZ = its length, CIOCHR = the single byte
;; Errors: Y = RDONLY when the IOCB isn't open for writing, NOTOPN, or the handler's status
CIO_PUT:
    lda ICCOMZ
    and ICAX1Z                      ; the put commands' bit 3 is OWRIT
    bne CIO_PUT_OPEN
    ldy #RDONLY
CIO_PUT_FAIL:
    jmp CIO_RETURN_STATUS
CIO_PUT_OPEN:
    jsr CIO_FIND_ROUTINE
    bcs CIO_PUT_FAIL
    lda ICBLLZ
    ora ICBLHZ
    bne CIO_PUT_LOOP
    lda CIOCHR                      ; a single byte: count it as a buffer of one
    inc ICBLLZ
    bne CIO_PUT_BYTE                ; always
CIO_PUT_LOOP:
    ldy #$00
    lda (ICBALZ),y
    sta CIOCHR
CIO_PUT_BYTE:
    jsr CIO_CALL_HANDLER
    bmi CIO_PUT_DONE                ; an error
    jsr CIO_NEXT_ADDRESS
    lda ICCOMZ
    and #CIO_BINARY
    bne CIO_PUT_NEXT
    lda CIOCHR
    cmp #EOL
    bne CIO_PUT_NEXT
    jsr CIO_COUNT_DOWN              ; the record's end
    jmp CIO_PUT_DONE
CIO_PUT_NEXT:
    jsr CIO_COUNT_DOWN
    bne CIO_PUT_LOOP
    lda ICCOMZ
    and #CIO_BINARY
    bne CIO_PUT_DONE
    lda #EOL                    ; end the record
    jsr CIO_CALL_HANDLER
CIO_PUT_DONE:
    jsr CIO_SET_COUNT
    jmp CIO_RETURN

;; Returns from CIOV with the status in Y, copying the zero-page IOCB back to the IOCB.
;;
;; The IOCB keeps its own buffer address, which CIO advanced only in the zero-page copy.
;; In: Y = the status, ICIDNO = the IOCB
;; Out: A = CIOCHR, X = ICIDNO, Y = the status, negative = set on error
;; Entry: CIO_RETURN = returns the status already in ICSTAZ
CIO_RETURN_STATUS:
    sty ICSTAZ
CIO_RETURN:
    ldy ICIDNO
    lda ICBAL,y
    sta ICBALZ
    lda ICBAH,y
    sta ICBAHZ
    ldx #$00
CIO_RETURN_LOOP:
    lda ICHIDZ,x
    sta ICHID,y
    inx
    iny
    cpx #CIO_ZIOCB_SIZE
    bcc CIO_RETURN_LOOP
    lda CIOCHR
    ldx ICIDNO
    ldy ICSTAZ
    rts

;; Finds the address, less 1, of the handler's routine for the command in ICCOMT.
;; In: ICHIDZ = the handler's offset in HATABS, ICCOMT = the command, $03-$0E
;; Out: ICSPRZ = the routine's address, less 1, carry = set when the IOCB isn't open
;; Uses: A, X, Y
;; Errors: Y = NOTOPN
CIO_FIND_ROUTINE:
    ldy ICHIDZ
    cpy #CIO_LAST_ENTRY + 1
    bcc CIO_FIND_ROUTINE_1
    ldy #NOTOPN
    bcs CIO_FIND_ROUTINE_DONE       ; always
CIO_FIND_ROUTINE_1:
    lda HATABS+1,y                  ; the handler's vector table
    sta ICSPRZ
    lda HATABS+2,y
    sta ICSPRZ+1
    ldy ICCOMT
    lda CIO_COMMAND_OFFSETS - COPN,y
    tay
    lda (ICSPRZ),y
    tax
    iny
    lda (ICSPRZ),y
    sta ICSPRZ+1
    stx ICSPRZ
    clc
CIO_FIND_ROUTINE_DONE:
    rts

;; Counts one byte off the zero-page IOCB's buffer length.
;; Out: A = the length's two bytes ORed, zero = set when the length is now 0
CIO_COUNT_DOWN:
    dec ICBLLZ
    lda ICBLLZ
    cmp #$FF
    bne CIO_COUNT_DOWN_1
    dec ICBLHZ
CIO_COUNT_DOWN_1:
    ora ICBLHZ
    rts

;; Advances the zero-page IOCB's buffer address by one.
;; Keeps: A, X, Y
CIO_NEXT_ADDRESS:
    inc ICBALZ
    bne CIO_NEXT_ADDRESS_DONE
    inc ICBAHZ
CIO_NEXT_ADDRESS_DONE:
    rts

;; Sets the zero-page IOCB's buffer length to the number of bytes moved: the IOCB's length less what is left.
;; Out: X = ICIDNO
;; Uses: A
CIO_SET_COUNT:
    ldx ICIDNO
    sec
    lda ICBLL,x
    sbc ICBLLZ
    sta ICBLLZ
    lda ICBLH,x
    sbc ICBLHZ
    sta ICBLHZ
    rts

;; Calls the handler's routine that ICSPRZ points to (less 1), and keeps the status it returns.
;;
;; The routine starts with Y = FNCNOT, so one that only returns reports the function as not implemented.
;; In: A = the byte for the handler, ICSPRZ = the routine's address, less 1
;; Out: A = the handler's byte, X = ICIDNO (on the handler's entry), Y = the status, negative = set on error
;; See: <HANDLER_OPEN>
CIO_CALL_HANDLER:
    ldy #FNCNOT
    jsr CIO_JUMP_TO_ROUTINE
    sty ICSTAZ
    cpy #$00
    rts

;; Jumps to the routine ICSPRZ points to (less 1), by pushing it and returning, with X = ICIDNO.
;; In: A = the byte for the handler, ICSPRZ = the routine's address, less 1
;; Keeps: A, Y
CIO_JUMP_TO_ROUTINE:
    tax
    lda ICSPRZ+1
    pha
    lda ICSPRZ
    pha
    txa
    ldx ICIDNO
    rts

;; Finds the device named at the buffer in HATABS, and its device number.
;;
;; The name is a letter and an optional digit: "D2:" is unit 2, and a name without a digit, such as "D:", is unit
;; 1. The table is searched from its last entry down, so a handler added later wins.
;; In: ICBALZ/ICBAHZ = the name
;; Out: ICHIDZ = the device's offset in HATABS, ICDNOZ = the device number, carry = set when not found
;; Uses: A, Y
;; Errors: Y = NONDEV
CIO_FIND_DEVICE:
    ldy #$00
    lda (ICBALZ),y
    beq CIO_FIND_DEVICE_NONE        ; 0 marks HATABS's free entries
    ldy #CIO_LAST_ENTRY
CIO_FIND_DEVICE_LOOP:
    cmp HATABS,y
    beq CIO_FIND_DEVICE_FOUND
    dey
    dey
    dey
    bpl CIO_FIND_DEVICE_LOOP
CIO_FIND_DEVICE_NONE:
    ldy #NONDEV
    sec
    bcs CIO_FIND_DEVICE_DONE        ; always
CIO_FIND_DEVICE_FOUND:
    tya
    sta ICHIDZ
    sec
    ldy #$01
    lda (ICBALZ),y
    sbc #'0'
    cmp #10
    bcc CIO_FIND_DEVICE_UNIT
    lda #CIO_DEFAULT_UNIT           ; not a digit
CIO_FIND_DEVICE_UNIT:
    sta ICDNOZ
    clc
CIO_FIND_DEVICE_DONE:
    rts

;; The offset in a handler's vector table of the routine for each command, from COPN to <CIO_FIRST_SPECIAL>.
;;
;; The commands' codes are indexed from COPN, so the code reads it at CIO_COMMAND_OFFSETS - COPN. The undocumented
;; codes $04, $06, $08 and $0A act as $05, $07, $09 and $0B.
;; See: <HANDLER_OPEN>, <CIO_MAIN>, <CIO_FIND_ROUTINE>
CIO_COMMAND_OFFSETS:
    .byte HANDLER_OPEN              ; $03 COPN
    .byte HANDLER_GET               ; $04
    .byte HANDLER_GET               ; $05 CGTXTR, get record
    .byte HANDLER_GET               ; $06
    .byte HANDLER_GET               ; $07 CGBINR, get bytes
    .byte HANDLER_PUT               ; $08
    .byte HANDLER_PUT               ; $09 CPTXTR, put record
    .byte HANDLER_PUT               ; $0A
    .byte HANDLER_PUT               ; $0B CPBINR, put bytes
    .byte HANDLER_CLOSE             ; $0C CCLOSE
    .byte HANDLER_STATUS            ; $0D CSTATUS
    .byte HANDLER_SPECIAL           ; $0E and up, the device's own
    .assert * - CIO_COMMAND_OFFSETS = CIO_FIRST_SPECIAL + 1 - COPN, "Each command COPN-$0E has an offset."
