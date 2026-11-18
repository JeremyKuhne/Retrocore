;; COMMODORE PET BASIC 2 KERNAL ($F000-$FFFF)
;;
;; The kernal is the PET's I/O and system ROM in the 2001-N and in the upgrade ROMs for the 2001: the files and
;; devices behind BASIC's OPEN, CLOSE, GET#, INPUT#, PRINT# and CMD, LOAD, SAVE and VERIFY on the cassettes and
;; the IEEE-488 bus, the jiffy clock, reset, and the machine-language monitor. The screen and keyboard are the
;; screen editor's ($E1DE-$E7FF), which also holds the interrupt entry and the monitor's number routines.
;;
;; It is laid out in this order:
;;
;; - The messages (<MSG1>), each ending at a character with bit 7 set.
;; - The IEEE-488 bus: commands under ATN (<TALK>, <LISTN>, <SECND>, <TKSA>, <UNTLK>, <UNLSN>) and the
;;   three-wire handshake that sends (<CIOUT>) and receives (<ACPTR>) a byte, with C3PO/BSOUR holding each byte
;;   back so that the last one goes out with EOI.
;; - The channel routines behind the jump table: <GETIN>, <BASIN>, <BSOUT>, <CLRCHN>, <CHKIN>, <CHKOUT>, and the
;;   file table (<LAT>, <FAT>, <SAT>) that <OPEN> and <CLOSE> keep.
;; - BASIC's I/O statements, which read their own parameters with BASIC's evaluator: <OPEN>, <CLOSE>, <LOAD>,
;;   <VER>, <SAVE> and <SYS>.
;; - The cassettes: a 192-byte block in each cassette's buffer for data files, headers that name a file and its
;;   addresses, and the interrupt handlers that read (<READ>) and write (<WRTN>, <WRTZ>) the
;;   pulses while the main program waits (<TWAIT>).
;; - The jiffy clock (<UDTIM>), reset (<START>) and the vectors.
;; - The monitor (<BRKE>), entered through BRK, or at reset when the diagnostic sense line is low.
;;
;; Devices are numbered as BASIC numbers them: 0 the keyboard, 1 and 2 the cassettes, 3 the screen, and 4-31 the
;; IEEE-488 bus, where BASIC 2 is the first PET whose routines work with Commodore's disk drives.
;;
;; A tape block is written twice. Each copy is a leader of short pulses, nine sync bytes ($89 down to $81 for the
;; first copy, $09 down to $01 for the second), the data, and an XOR checksum. A byte is a byte marker, a long
;; then a medium pulse, then eight bits from bit 0, a 0 as a short then a medium pulse and a 1 as a medium then a
;; short one, then an odd parity bit. Reading keeps the addresses of the first copy's bad bytes in <BAD> and takes
;; those bytes from the second copy. A header block is 192 bytes: the type (<TAPE_PROGRAM>, <TAPE_DATA_HEADER>
;; or <TAPE_END_OF_TAPE>), the start and end addresses, and the file name, padded with spaces.
;;
;; Assembles byte-identically to the kernal ROM 901465-03. The editor's routines it uses are equates in
;; EditorEntries.asm, and BASIC's in BasicEntries.asm, named as Microsoft's m6502.asm names them. The entries of
;; the jump table at $FFC0 take m6502.asm's names too, the names BASIC calls them by. The routines take Commodore's
;; names from its BASIC 4 kernal listing of 1979 where BASIC 4 has the same code, and otherwise are named after what
;; they do.
;;
;; Maintained by hand.

.cpu Mos6502

.include "../PetEquates.asm"
.include "Equates.asm"
.include "BasicEntries.asm"
.include "EditorEntries.asm"

; Indexes of the interrupt handlers in IRQ_VECTORS, which BSIV loads into CINV.
IRQV_LEADER = 8             ;; The index of <WRTZ>, writing a tape leader.
IRQV_WRITE = 10             ;; The index of <WRTN>, writing a tape block's bytes.
IRQV_NORMAL = 12            ;; The index of <KEY>, the editor's interrupt handler.
IRQV_READ = 14              ;; The index of <READ>, reading a tape block.

;; The length of a day on the jiffy clock, plus one: when <CQTIMR> reaches it, <UDTIM> sets the clock to zero.
JIFFIES_PER_DAY = 24 * 60 * 60 * 60 + 1

;; The 6502's BIT absolute opcode, which as a data byte makes the next two bytes its operand, skipping them.
BIT_ABSOLUTE = $2C

TAPE_HEADER_LEADER = $69    ;; A header's leader, in groups of 80 pulses: about 2 seconds.
TAPE_DATA_LEADER = $14      ;; A data block's leader, in groups of 80 pulses.

MON_COMMAND_L = 6           ;; The index of L in <CMDS>, which <S0> leaves in <WORKA>.
MON_COMMAND_S = 7           ;; The index of S in <CMDS>.

.org $F000

;; The kernal's messages. Each ends at a character with bit 7 set, and <MSG> prints one from its offset here, so a
;; message's offset is its label less this one. Some print in parts: <MS5> and <MS10> end with
;; <MS20>, and an error prints <MS22> or <MS12>, the last letters of another message, before " ERROR".
MSG1:
MS1: .byte "TOO MANY FILE", 'S' | $80                           ;; Error: <OPEN> with ten files open.
MS2: .byte "FILE OPE", 'N' | $80                                ;; Error: <OPEN> of a logical file already open.
MS3: .byte "FILE NOT OPE", 'N' | $80                            ;; Error: <CHKIN> or <CHKOUT> of a file not open.
MS4: .byte "FILE NOT FOUN", 'D' | $80                           ;; Error: no tape header with the name, before the end of the tape.
MS5: .byte $0D, "SEARCH"                                        ;; "SEARCHING", ended by <MS20>.
MS20: .byte "ING", ' ' | $80                                    ;; The end of "SEARCHING", "LOADING" and "VERIFYING".
MS6: .byte "FOR", ' ' | $80                                     ;; Before the name searched for.
MS7: .byte $0D, "PRESS PLAY", ' ' | $80                         ;; Asks for a cassette's PLAY key.
MS8: .byte "& RECORD", ' ' | $80                                ;; Follows <MS7> to write.
MS9: .byte "ON TAPE ", '#' | $80                                ;; Follows the request, before the cassette's number.
MS10: .byte $0D                                                 ;; "LOADING", from <MS22> and <MS20>.
MS22: .byte "LOA", 'D' | $80                                    ;; "LOAD", also the ?LOAD ERROR's.
MS11: .byte $0D, "WRITING", ' ' | $80                           ;; Before the name of a file being saved to tape.
MS21: .byte $0D                                                 ;; "VERIFYING", from <MS12> and <MS20>.
MS12: .byte "VERIF", 'Y' | $80                                  ;; "VERIFY", also the ?VERIFY ERROR's.
MS13: .byte "DEVICE NOT PRESEN", 'T' | $80                      ;; Error: no device answered on the bus, or none can do it.
MS15: .byte "NOT INPUT FIL", 'E' | $80                          ;; Error: <CHKIN> of a file only written.
MS16: .byte "NOT OUTPUT FIL", 'E' | $80                         ;; Error: <CHKOUT> of a file only read, or of the keyboard.
MS17: .byte $0D, "FOUND", ' ' | $80                             ;; Before the name of each tape header found.
MS18: .byte $0D, "OK", $0D | $80                                ;; After the cassette's key is down.
MS19: .byte $0D, "READY.", $0D | $80                            ;; After a LOAD in direct mode.

;; Commands the device in <FA> to talk, under ATN.
;; In: FA = the device
;; Out: CQSTAT = with <ST_NOT_PRESENT> when no device answered
;; Uses: A
TALK:
    lda #IEEE_TALK
    bne LIST1

;; Commands the device in <FA> to listen, under ATN.
;;
;; Like <TALK>, it first sends any byte <CIOUT> holds back, with EOI, so the device listening before gets its
;; last byte marked.
;; Inherit: <TALK> In, Out, Uses
;; Entry: LIST1 = sends the command in A, or'd with FA
LISTN:
    lda #IEEE_LISTEN
LIST1:
    pha
    lda VIA_ORB
    ora #VIA_NRFD_OUT
    sta VIA_ORB                             ; NRFD high: ready
    lda #PIA_HIGH
    sta PIA2_CRA
    bit C3PO
    beq LISTN_1
    lda #PIA_LOW
    sta PIA1_CRA
    jsr ISOUR
    lda #$00
    sta C3PO
    lda #PIA_HIGH
    sta PIA1_CRA
LISTN_1:
    pla
    ora FA
    sta BSOUR
LISTN_2:
    lda VIA_ORB                             ; wait for DAV high
    bpl LISTN_2
    and #(~VIA_ATN_OUT) & $FF
    sta VIA_ORB                             ; ATN low: attention

;; Sends the byte in <BSOUR> on the IEEE-488 bus with the three-wire handshake.
;;
;; It puts the byte on the data lines (inverted), waits for NRFD to rise, sets DAV, and waits for NDAC to rise
;; while the VIA's timer 1 runs for about 65 milliseconds. With both NRFD and NDAC high at the start, no device is
;; there.
;; In: BSOUR = the byte
;; Out: CQSTAT = with <ST_NOT_PRESENT> or <ST_WRITE_TIMEOUT> on failure
;; Uses: A
ISOUR:
    lda #PIA_HIGH
    sta PIA2_CRB
    lda VIA_ORB                             ; NDAC and NRFD both high: no device
    and #VIA_NDAC_IN | VIA_NRFD_IN
    cmp #VIA_NDAC_IN | VIA_NRFD_IN
    beq ERRP7
    lda BSOUR
    eor #$FF                                ; the bus is inverted
    sta PIA2_PB
ISOUR_1:
    bit VIA_ORB                             ; wait for NRFD high
    bvc ISOUR_1
    lda #PIA_LOW
    sta PIA2_CRB                            ; DAV low: data valid
    lda #$FF
    sta VIA_T1CH                            ; timer 1: about 65 ms
ISOUR_2:
    lda VIA_ORB                             ; wait for NDAC high, or the timeout
    bit VIA_IFR
    bvs ERRP0
    lsr a
    bcc ISOUR_2
ISOUR_3:
    lda #PIA_HIGH
    sta PIA2_CRB                            ; DAV high
    lda #$FF
    sta PIA2_PB                             ; release the data lines
    rts

;; Sends a secondary address after <LISTN> or <TALK>, then releases ATN.
;; In: A = the secondary address with its command bits ($60 and up)
;; Inherit: <ISOUR> Out, Uses
SECND:
    sta BSOUR
    jsr ISOUR

;; Releases ATN, ending a command on the bus.
;; Uses: A
SCATN:
    lda VIA_ORB
    ora #VIA_ATN_OUT
    sta VIA_ORB
    rts

;; Ends <ISOUR> with an error: sets <ST_WRITE_TIMEOUT>, then releases DAV and the data lines.
;; Entry: ERRP7 = sets ST_NOT_PRESENT instead
ERRP0:
    lda #ST_WRITE_TIMEOUT
ERRP0_1:
    jsr UDST
    bne ISOUR_3
ERRP7:
    lda #ST_NOT_PRESENT
    bmi ERRP0_1

;; Ends <ACPTR> when no byte came in time: sets <ST_READ_TIMEOUT> and stops the handshake.
;; Out: A = a carriage return
ERRP1:
    lda #ST_READ_TIMEOUT
    jsr UDST

;; Holds NRFD and NDAC low: the PET, as listener, is not ready for a byte and has not taken one.
;; Out: A = a carriage return
ER001:
    lda VIA_ORB
    and #(~VIA_NRFD_OUT) & $FF
    sta VIA_ORB
    lda #PIA_LOW
    sta PIA2_CRA                            ; NDAC low
    lda #KEY_RETURN
    rts

;; Prints one of the kernal's <MSG1> on the screen, whatever the output device.
;; In: Y = the message's offset from MSG1
;; Out: Y = just past it
;; Uses: A
MSG:
    lda MSG1,y
    php
    and #$7F
    jsr PRT
    iny
    plp
    bpl MSG
    rts

;; Sends a secondary address after <TALK>, then turns the bus around so that the device talks and the PET listens.
;; In: A = the secondary address with its command bits
;; Entry: TKATN = only turns the bus around, for a talker without a secondary address
;; Uses: A
TKSA:
    sta BSOUR
    jsr ISOUR
TKATN:
    jsr ER001
    jmp SCATN

;; Sends a byte to the device listening on the IEEE-488 bus.
;;
;; The byte is held back in <BSOUR>, and the one held back before goes out: so <UNLSN> or <LISTN> can send the
;; last byte with EOI.
;; In: A = the byte
;; Keeps: X, Y
CIOUT:
    bit C3PO
    bmi CIOUT_1
    dec C3PO
    bne CIOUT_2
CIOUT_1:
    pha
    jsr ISOUR
    pla
CIOUT_2:
    sta BSOUR
    rts

;; Sends UNTALK under ATN, so the device talking stops.
;; Uses: A
UNTLK:
    lda #IEEE_UNTALK
    bne UNLSN_1

;; Sends any byte <CIOUT> holds back, with EOI, then UNLISTEN under ATN, so the device listening stops.
;; Uses: A
UNLSN:
    lda #IEEE_UNLISTEN
UNLSN_1:
    nop
    nop
    jsr LIST1
    bne SCATN

;; Receives a byte from the device talking on the IEEE-488 bus.
;;
;; It sets NRFD, waits for DAV with the VIA's timer 1 as a timeout, takes the byte, and checks EOI.
;; Out: A = the byte, CQSTAT = with <ST_EOI> for the last byte, or <ST_READ_TIMEOUT> and A a carriage return
;; Keeps: X, Y
ACPTR:
    lda #PIA_LOW
    sta PIA2_CRA
    lda VIA_ORB
    ora #VIA_NRFD_OUT
    sta VIA_ORB
    lda #$FF
    sta VIA_T1CH
ACPTR_1:
    bit VIA_IFR                             ; wait for DAV low, or the timeout
    bvs ERRP1
    bit VIA_ORB
    bmi ACPTR_1
    lda VIA_ORB
    and #(~VIA_NRFD_OUT) & $FF
    sta VIA_ORB
    bit PIA1_PA                             ; EOI (PA6) low?
    bvs ACPTR_2
    lda #ST_EOI
    jsr UDST
ACPTR_2:
    lda PIA2_PA
    eor #$FF
    pha
    lda #PIA_HIGH
    sta PIA2_CRA                            ; NDAC high: taken
ACPTR_3:
    bit VIA_ORB                             ; wait for DAV high
    bpl ACPTR_3
    lda #PIA_LOW
    sta PIA2_CRA
    pla
    rts

;; Gets a character from the input device without waiting: GET and GET#.
;;
;; From the keyboard it takes the first key in <KEYD>, or returns 0; from another device it reads a byte as
;; <BASIN> does.
;; Out: A = the character, or 0 for no key
;; Uses: X, Y
GETIN:
    lda #$00
    sta CQSTAT
    lda DFLTN
    bne BN10
    lda NDX
    beq JTGET_3
    sei
    jmp LP2

;; Reads a character from the input device: INPUT and INPUT#.
;;
;; From the keyboard, the editor (<LOOP5>) waits for a line ended by RETURN and returns it a character at
;; a time, starting where the input began; from the screen, it reads the cursor's line. A tape file gives the
;; next byte of its buffer, with <ST_EOI> when the byte after it is the zero that ends the file; a device on the
;; bus gives the byte it sends, or a carriage return once <CQSTAT> is not zero.
;; Out: A = the character
;; Keeps: X
;; Entry: BN10 = reads from the device in A, not the keyboard
BASIN:
    lda DFLTN
    bne BN10
    lda PNTR
    sta INPUT_COLUMN
    lda TBLX
    sta INPUT_ROW
    jmp LOOP5
BN10:
    cmp #DEV_SCREEN
    bne BASIN_1
    sta CRSW
    lda LNMX
    sta INDX
    jmp LOOP5
BASIN_1:
    bcs JTGET_2
    stx XSAV
    jsr JTGET
    pha
    jsr JTGET
    bne BASIN_2
    lda #ST_EOI
    jsr UDST
BASIN_2:
    dec BUFPNT - 1,x
    ldx XSAV
    pla
    rts

;; Gets the next byte of the current cassette's buffer, reading the next block when it is used up.
;;
;; A new block's first byte is its type, which it skips.
;; In: FA = the cassette
;; Out: A = the byte, zero = set for a zero byte, X = FA, Y = the byte's index
;; Uses: A
JTGET:
    jsr JTP20
    bne JTGET_1
    jsr RBLK
    ldx FA
    lda #$00
    sta BUFPNT - 1,x
    beq JTGET
JTGET_1:
    lda (TAPE1),y
    rts
JTGET_2:
    lda CQSTAT
    beq JTGET_4
    lda #KEY_RETURN
JTGET_3:
    rts
JTGET_4:
    jmp ACPTR

;; Writes a character to the output device: PRINT, PRINT# and CMD.
;;
;; The screen goes through the editor (<PRT>), the bus through <CIOUT>, and a cassette into its buffer,
;; written to tape as a block when full.
;; In: A = the character
;; Keeps: A, X, Y
BSOUT:
    pha
    lda DFLTO
    cmp #DEV_SCREEN
    bne BSOUT_1
    pla
    jmp PRT
BSOUT_1:
    bmi BSOUT_2
    pla
    jmp CIOUT
BSOUT_2:
    pla

;; Puts a byte into the current cassette's buffer, writing the full buffer as a block first.
;;
;; Line feeds are dropped. A new block starts with the type <TAPE_DATA>.
;; In: A = the byte, FA = the cassette
;; Keeps: A, X, Y
BO21:
    sta WORKA
    cmp #$0A
    beq JTGET_3
    pha
    txa
    pha
    tya
    pha
    jsr JTP20
    bne BO21_1
    jsr WBLK
    ldx FA
    lda #$01
    sta BUFPNT - 1,x
    ldy #$00
    lda #TAPE_DATA
    sta (TAPE1),y
    iny
BO21_1:
    lda WORKA
    sta (TAPE1),y

;; Pulls Y, X and A from the stack, as the channel routines pushed them, and returns to the caller's caller.
RSTOR:
    pla
    tay
    pla
    tax
    pla
    rts

;; Forgets all the open files and restores the default channels.
;; Uses: A
CLALL:
    lda #$00
    sta LDTND

;; Restores the default channels, the keyboard for input and the screen for output, unlistening or untalking a
;; device on the bus first.
;; Out: A = 0
CLRCHN:
    lda DFLTO
    cmp #DEV_IEEE
    bcc CLRCHN_1
    jsr UNLSN
CLRCHN_1:
    lda DFLTN
    cmp #DEV_IEEE
    bcc JX770
    jsr UNTLK

;; Sets the input channel to the keyboard and the output channel to the screen.
;; Out: A = 0
JX770:
    lda #DEV_SCREEN
    sta DFLTO
    lda #$00
    sta DFLTN
    rts

;; Looks up a logical file in the file table.
;; In: A = the logical file
;; Out: zero = set when it is open, X = its index in <LAT>
;; Uses: X
JLTLK:
    ldx LDTND
JLTLK_1:
    dex
    bmi JZ100_1
    cmp LAT,x
    beq JZ100_1
    bne JLTLK_1

;; Makes the open file at an index the current file.
;; In: X = its index
;; Out: LA, FA, SA = its logical number, device and secondary address
;; Uses: A
JZ100:
    lda LAT,x
    sta LA
    lda FAT,x
    sta FA
    lda SAT,x
    sta SA
JZ100_1:
    rts

;; Closes a file: BASIC's CLOSE statement.
;;
;; A tape file being written gets a zero to end it and its last block, and, opened with secondary address 2, an
;; end-of-tape header; a file on the bus gets the CLOSE command. The file leaves the table, the last entry taking
;; its place.
;; Uses: A, X, Y
CLOSE:
    jsr PARS2
    lda LA
    jsr JLTLK
    bne CLOSE_3
    jsr JZ100
    txa
    pha
    lda FA
    beq CLOSE_2
    cmp #DEV_SCREEN
    beq CLOSE_2
    bcs CLOSE_1
    lda SA
    and #$0F
    beq CLOSE_2
    jsr ZZZ
    lda #$00
    jsr BO21
    jsr WBLK
    lda SA
    cmp #SA_READ | 2
    bne CLOSE_2
    lda #TAPE_END_OF_TAPE
    jsr TAPEH
    jmp CLOSE_2
CLOSE_1:
    jsr CLSE1
CLOSE_2:
    pla
    tax
    dec LDTND
    cpx LDTND
    beq CLOSE_3
    ldy LDTND
    lda LAT,y
    sta LAT,x
    lda FAT,y
    sta FAT,x
    lda SAT,y
    sta SAT,x
CLOSE_3:
    rts

;; Checks whether STOP is down; if it is, restores the default channels and empties the keyboard buffer.
;; Out: zero = set when STOP is down
;; Uses: A
STOP1:
    lda STKEY                               ; row 9 with only STOP down?
    cmp #(~$10) & $FF
    bne STOP1_1
    php
    jsr CLRCHN
    sta NDX
    plp
STOP1_1:
    rts

;; Checks for STOP and stops the program with BREAK if it is down, through BASIC's <STOP>.
;; Uses: A
STOP_KEY:
    jsr STOP1
    jmp STOP

;; Prints one of the kernal's <MSG1> in direct mode only.
;; In: Y = the message's offset
;; Uses: A, Y
SPMSG:
    jsr TXTST
    bne STOP1_1
    jmp MSG

;; Tells whether BASIC is in direct mode: whether TXTPTR is in the input buffer, page 2.
;; Out: zero = set in direct mode
;; Uses: A
TXTST:
    lda TXTPTR+1
    cmp #>BUF
    rts

;; Loads or verifies a program from the device in <FA>, a cassette or a disk, into the memory from <STAL>.
;;
;; A program on the bus is read from its first two bytes, its address, to EOI; one on tape is found by its header,
;; or the first program when there is no name, and read into the memory its header names.
;; In: FA = the device, VERCK = 0 to load, 1 to verify, FNADR/FNLEN = the name
;; Out: EAL = the end of what was loaded, CQSTAT = the result
LD15:
    lda FA
    bne LD15_2
LD15_1:
    jmp SNERR
LD15_2:
    cmp #DEV_SCREEN
    beq LD15_1
    bcc LD100
    lda #SA_READ
    sta SA
    ldy FNLEN
    bne LD15_3
    jmp SNERR
LD15_3:
    jsr LD300
    jsr OPENI
    jsr TALK
    lda SA
    jsr SECND
    jsr ACPTR
    sta STAL
    jsr ACPTR
    sta STAL+1
    jsr LD400
LD15_4:
    lda #(~ST_READ_TIMEOUT) & $FF
    and CQSTAT
    sta CQSTAT
    jsr STOP_KEY
    jsr ACPTR
    tax
    lda CQSTAT
    lsr a
    lsr a
    bcs LD15_4
    txa
    ldy VERCK
    beq LD15_5
    dey
    cmp (STAL),y
    beq LD15_6
    ldx #ST_READ_ERROR
    stx CQSTAT
    bne LD15_6
LD15_5:
    sta (STAL),y
LD15_6:
    inc STAL
    bne LD15_7
    inc STAL+1
LD15_7:
    bit CQSTAT
    bvc LD15_4
    nop
    nop
    nop
    lda STAL
    sta EAL
    lda STAL+1
    sta EAL+1
    jsr UNTLK
    jmp CLSE1

;; Inherit: <LD15>
;; Finds the program's header on the cassette and starts reading its data block.
LD100:
    jsr ZZZ
    jsr CSTE1
    jsr LD300
LD100_1:
    lda FNLEN
    beq LD100_3
    jsr FAF
    bne LD100_4
LD100_2:
    jmp OP160
LD100_3:
    jsr FAH
    beq LD100_2
LD100_4:
    cpx #TAPE_PROGRAM
    bne LD100_1
    lda CQSTAT
    and #ST_READ_ERROR
    bne LD105_2
    jsr LDAD2
    jsr LD400
    jmp TRD

;; Loads a program: BASIC's LOAD statement.
;;
;; After waiting for the keys of row 9 to be up (for shifted RUN, which types LOAD), it loads from the device. In
;; direct mode the program's end becomes <VARTAB> and BASIC prints READY. and relinks it; in a program, the program
;; loaded runs from its start, keeping the variables. A failed load gives the ?LOAD ERROR.
;; Entry: LD10 = loads or verifies, by VERCK
LOAD:
    lda #$00
    sta VERCK
LD10:
    jsr PARS1
    jsr SV60
    lda #$FF                                ; wait until row 9 has no key down
LOAD_1:
    cmp STKEY
    bne LOAD_1
    cmp STKEY
    bne LOAD_1
    jsr LD15
    lda VERCK
    bne LD105_2
    jsr TWAIT
    lda CQSTAT
    and #ST_READ_ERROR
    beq LOAD_2
    ldy #$00
    sty NDX
    ldy #MS22 - MSG1
    jmp ERMSG
LOAD_2:
    ldy #MS19 - MSG1
    jsr SPMSG
    jsr TXTST
    bne LOAD_3
    lda EAL+1                               ; the end of the program loaded
    sta VARTAB+1
    lda EAL
    sta VARTAB
    jmp FINI
LOAD_3:
    jsr STXTPT
    jmp FLOAD

;; Prints "SEARCHING" and, with a name, "FOR" and the name, in direct mode.
;; Uses: A, Y
LD300:
    jsr TXTST
    bne LD105_2
    ldy #MS5 - MSG1
    jsr MSG
    lda FNLEN
    beq LD105_2
    ldy #MS6 - MSG1
    jsr MSG

;; Prints the file name at <FNADR>.
;; Uses: A, Y
LD105:
    ldy FNLEN
    beq LD105_2
    ldy #$00
LD105_1:
    lda (FNADR),y
    jsr OUTCH
    iny
    cpy FNLEN
    bne LD105_1
LD105_2:
    rts

;; Prints "LOADING" or "VERIFYING", by <VERCK>, in direct mode.
;; Uses: A, Y
LD400:
    ldy #MS10 - MSG1
    lda VERCK
    beq LD400_1
    ldy #MS21 - MSG1
LD400_1:
    jsr SPMSG
    ldy #MS20 - MSG1
    jmp SPMSG

;; Reads the parameters of LOAD, SAVE and VERIFY from the program text: a name, the device (1 by default) and the
;; secondary address (0).
;; Out: FNADR/FNLEN = the name, FA = the device, SA = the secondary address, CQSTAT = 0
;; Uses: A, X, Y
PARS1:
    ldx #$00
    stx CQSTAT
    stx FNLEN
    stx SA
    inx
    stx FA
    jsr PR140
    jsr PR200
    jsr PR140
    jsr PR070
    stx FA
    jsr PR140
    jsr PR070
    stx SA
PARS1_1:
    rts

;; Reads a comma and a byte from the program text, or gives a syntax error.
;; Out: X = the byte
;; Uses: A, Y
PR070:
    jsr PR150
    jmp GETBYT

;; Sends a file's name to the device on the bus with the OPEN command for its secondary address.
;;
;; Nothing is sent for a secondary address with bit 7 set or an empty name.
;; In: SA = the secondary address, FNADR/FNLEN = the name
;; Errors: ?DEVICE NOT PRESENT when no device answers
;; Uses: A, Y
;; Entry: OP37 = gives the ?DEVICE NOT PRESENT error
OPENI:
    lda SA
    bmi PARS1_1
    ldy FNLEN
    beq PARS1_1
    jsr LISTN
    lda SA
    ora #IEEE_OPEN
    jsr SECND
    lda CQSTAT
    bpl OPENI_1
OP37:
    ldy #MS13 - MSG1
    jmp ERMSG
OPENI_1:
    lda FNLEN
    beq OPENI_3
    ldy #$00
OPENI_2:
    lda (FNADR),y
    jsr CIOUT
    iny
    cpy FNLEN
    bne OPENI_2
OPENI_3:
    jmp UNLSN

;; Reads tape headers until one with the name at <FNADR>, or the end of the tape.
;; Out: zero = clear when found, X = its type
;; Uses: A, Y
FAF:
    jsr FAH
    beq FAF_3
    ldy #$05
    sty WORKB
    ldy #$00
    sty WORKA
FAF_1:
    cpy FNLEN
    beq FAF_2
    lda (FNADR),y
    ldy WORKB
    cmp (TAPE1),y
    bne FAF
    inc WORKA
    inc WORKB
    ldy WORKA
    bne FAF_1
FAF_2:
    tya
FAF_3:
    rts

;; Verifies a program against memory: BASIC's VERIFY statement.
;;
;; It prints OK when they match, or gives the ?VERIFY ERROR.
VER:
    lda #$01
    sta VERCK
    jsr LD10
    lda CQSTAT
    and #ST_READ_ERROR
    beq VER_1
    ldy #MS12 - MSG1
    jmp ERMSG
VER_1:
    ldy #MS18 - MSG1
    jmp MSG

;; Reads the parameters of OPEN and CLOSE from the program text: the logical file, then optionally the device (1),
;; the secondary address (0, or $FF for a device from 3 up) and a name.
;; Out: LA, FA, SA, FNADR/FNLEN = them, CQSTAT = 0
;; Uses: A, X, Y
PARS2:
    ldx #$00
    stx SA
    stx CQSTAT
    stx FNLEN
    inx
    stx FA
    jsr PR130
    jsr GETBYT
    stx LA
    jsr PR140
    jsr PR070
    stx FA
    cpx #DEV_SCREEN
    bcc PARS2_1
    dec SA
PARS2_1:
    jsr PR140
    jsr PR070
    stx SA
    jsr PR140
    jsr PR150

;; Evaluates a string expression as the file name.
;; Out: FNADR/FNLEN = the string
;; Uses: A, X, Y
PR200:
    jsr FRMEVL
    jsr FRESTR
    sta FNLEN
    lda INDEX
    sta FNADR
    lda INDEX+1
    sta FNADR+1
    rts

;; Returns from its caller's caller when the statement has ended, so a parameter list may stop early.
;; Uses: A
PR140:
    jsr CHRGOT
    bne PR140_1
    pla
    pla
PR140_1:
    rts

;; Reads a comma, and gives a syntax error unless more of the statement follows it.
;; Uses: A, Y
PR150:
    jsr CHKCOM

;; Gives a syntax error if the statement has ended.
;; Uses: A
PR130:
    jsr CHRGOT
    bne PR140_1
PR130_1:
    jmp SNERR

;; Opens a file: BASIC's OPEN statement.
;;
;; It adds the file to the table, with $60 added to its secondary address. A tape file to read waits for PLAY and
;; finds its header, by name or the first; one to write waits for PLAY and RECORD and writes a data header; a file
;; on the bus sends its name.
;; Errors: ?TOO MANY FILES, ?FILE OPEN, ?FILE NOT FOUND, ?DEVICE NOT PRESENT
;; Uses: A, X, Y
OPEN:
    jsr PARS2
    lda LA
    beq PR130_1
    ldy #MS2 - MSG1
    jsr JLTLK
    beq ERMSG
    ldx LDTND
    ldy #MS1 - MSG1
    sty CQSTAT
    cpx #MAX_FILES
    beq ERMSG
    inc LDTND
    lda LA
    sta LAT,x
    lda SA
    ora #SA_READ
    sta SA
    sta SAT,x
    lda FA
    sta FAT,x
    beq OP170_4
    cmp #DEV_SCREEN
    beq OP170_4
    bcc OPEN_1
    jmp OPENI
OPEN_1:
    lda SA
    and #$0F
    bne OP170_1
    jsr CSTE1
    jsr LD300
    lda FNLEN
    beq OP170
    jsr FAF
    bne OP170_2

;; Gives the ?FILE NOT FOUND error.
OP160:
    ldy #MS4 - MSG1

;; Gives a kernal error: closes all files, prints "?" and the message, and goes on through BASIC's <TYPERR>,
;; which prints " ERROR".
;; In: Y = the message's offset in <MSG1>
ERMSG:
    jsr CLALL
    lda #KEY_RETURN
    jsr OUTCH
    lda #'?'
    jsr OUTCH
    jsr MSG
    jmp TYPERR

;; Finishes <OPEN> for a tape file: finds the first header when reading without a name, and sets the buffer's index,
;; past the end for a file read so the first byte reads a block, or past a <TAPE_DATA> type for a file written.
OP170:
    jsr FAH
    beq OP160
    bne OP170_2
OP170_1:
    jsr CSTE2
    lda #TAPE_DATA_HEADER
    jsr TAPEH
OP170_2:
    ldx FA
    lda #TAPE_BUFFER_SIZE - 1
    ldy SA
    cpy #SA_READ
    beq OP170_3
    ldy #$00
    lda #TAPE_DATA
    sta (TAPE1),y
    tya
OP170_3:
    sta BUFPNT - 1,x
OP170_4:
    rts

;; Reads tape blocks until a program header, a data file's header or the end-of-tape header; in direct mode it
;; prints "FOUND" and the name of each header found.
;; Out: zero = set at the end of the tape, X = the type found
;; Keeps: VERCK
;; Uses: A, Y
FAH:
    lda VERCK
    pha
FAH_1:
    jsr RBLK
    ldy #$00
    lda (TAPE1),y
    cmp #TAPE_END_OF_TAPE
    beq FAH_5
    cmp #TAPE_PROGRAM
    beq FAH_2
    cmp #TAPE_DATA_HEADER
    bne FAH_1
FAH_2:
    tax
    jsr TXTST
    bne FAH_4
    ldy #MS17 - MSG1
    jsr MSG
    ldy #$05
FAH_3:
    lda (TAPE1),y
    jsr OUTCH
    iny
    cpy #5 + 16
    bne FAH_3
FAH_4:
    ldy #$01
FAH_5:
    pla
    sta VERCK
    tya
    rts

;; Writes a tape header: the type, <STAL> and <EAL>, and the file name, in a block padded with spaces.
;; In: A = the type, FA = the cassette, FNADR/FNLEN = the name
;; Keeps: STAL, EAL
TAPEH:
    sta WORKA
    jsr ZZZ
    lda STAL+1
    pha
    lda STAL
    pha
    lda EAL+1
    pha
    lda EAL
    pha
    ldy #TAPE_BUFFER_SIZE - 1
    lda #' '
TAPEH_1:
    sta (TAPE1),y
    dey
    bne TAPEH_1
    lda WORKA
    sta (TAPE1),y
    iny
    lda STAL
    sta (TAPE1),y
    iny
    lda STAL+1
    sta (TAPE1),y
    iny
    lda EAL
    sta (TAPE1),y
    iny
    lda EAL+1
    sta (TAPE1),y
    iny
    sty WORKB
    ldy #$00
    sty WORKA
TAPEH_2:
    ldy WORKA
    cpy FNLEN
    beq TAPEH_3
    lda (FNADR),y
    ldy WORKB
    sta (TAPE1),y
    inc WORKA
    inc WORKB
    bne TAPEH_2
TAPEH_3:
    jsr LDAD1
    lda #TAPE_HEADER_LEADER
    sta CHECKSUM
    jsr TWRT2
    pla
    sta EAL
    pla
    sta EAL+1
    pla
    sta STAL
    pla
    sta STAL+1
    rts

;; Takes the start and end addresses from the header in the cassette's buffer.
;; Out: SAL/EAL = them, STAL = the start
;; Uses: A, X, Y
LDAD2:
    jsr TWAIT
    ldx #$00
    ldy #$01
LDAD2_1:
    lda (TAPE1),y
    sta SAL,x
    inx
    iny
    cpx #$04
    bne LDAD2_1
    lda SAL
    sta STAL
    lda SAL+1
    sta STAL+1
    rts

;; Points <TAPE1> at the buffer of the cassette in <FA>: <TBUFFR1>, or <TBUFFR2> for cassette 2.
;; Uses: A
ZZZ:
    lda #<TBUFFR1
    sta TAPE1
    lda #>TBUFFR1
    sta TAPE1+1
    lda FA
    lsr a
    bcs ZZZ_1
    lda #<TBUFFR2
    sta TAPE1
    lda #>TBUFFR2
    sta TAPE1+1
ZZZ_1:
    rts

;; Sets the range a tape block reads or writes to the cassette's buffer, once the tape is idle.
;; Out: STAL = the buffer, EAL = its end
;; Uses: A
LDAD1:
    jsr TWAIT
    jsr ZZZ
    lda TAPE1
    sta STAL
    clc
    adc #TAPE_BUFFER_SIZE
    sta EAL
    lda TAPE1+1
    sta STAL+1
    adc #$00
    sta EAL+1
    rts

;; Calls a machine-language routine: BASIC's SYS statement.
;;
;; It evaluates the address into <LINNUM> and jumps there; the routine returns to BASIC with RTS.
SYS:
    jsr FRMNUM
    jsr GETADR
    jmp (LINNUM)

;; Sets the range a LOAD or SAVE covers to the BASIC program, <TXTTAB> to <VARTAB>.
;; Out: STAL = the start, EAL = the end
;; Uses: A
SV60:
    lda VARTAB
    sta EAL
    lda VARTAB+1
    sta EAL+1
    lda TXTTAB+1
    sta STAL+1
    lda TXTTAB
    sta STAL
    rts

;; Saves the program: BASIC's SAVE statement.
;;
;; On the bus it opens the file with secondary address 1 and sends the start address, then the bytes; on tape it
;; writes a program header and the data block, and, for secondary address 2 or 3, an end-of-tape header.
;; Errors: ?DEVICE NOT PRESENT for the keyboard or the screen
;; Entry: SV5 = saves STAL to EAL to the device in FA, for the monitor
SAVE:
    jsr PARS1
    jsr SV60
SV5:
    lda FA
    bne SAVE_2
SAVE_1:
    ldy #MS13 - MSG1
    jmp ERMSG
SAVE_2:
    cmp #DEV_SCREEN
    beq SAVE_1
    bcc SV100
    lda #SA_SAVE
    sta SA
    ldy FNLEN
    bne SAVE_3
    jmp SNERR
SAVE_3:
    jsr OPENI
    jsr LISTN
    lda SA
    jsr SECND
    ldy #$00
    jsr RD300                               ; the start address first
    lda SAL
    jsr CIOUT
    lda SAL+1
    jsr CIOUT
SAVE_4:
    jsr WRT62
    beq SAVE_5
    lda (SAL),y
    jsr CIOUT
    jsr STOP_KEY
    inc SAL
    bne SAVE_4
    inc SAL+1
    bne SAVE_4
SAVE_5:
    jsr UNLSN

;; Sends the CLOSE command for the current file's secondary address to the device on the bus.
;;
;; Nothing is sent for a secondary address with bit 7 set.
;; In: SA = the secondary address
;; Uses: A
CLSE1:
    bit SA
    bmi UDTIM_8
    jsr LISTN
    lda SA
    and #(~$10) & $FF
    ora #IEEE_CLOSE
    jsr SECND
    jmp UNLSN

;; Inherit: <SAVE>
;; Saves STAL to EAL to a cassette.
SV100:
    jsr ZZZ
    jsr CSTE2
    jsr TXTST
    bne SV100_1
    ldy #MS11 - MSG1
    jsr MSG
    jsr LD105
SV100_1:
    lda #TAPE_PROGRAM
    jsr TAPEH
    jsr TWRT
    lda SA
    and #$02
    beq UDTIM_8
    lda #TAPE_END_OF_TAPE
    jmp TAPEH

;; Updates the jiffy clock and reads the STOP key, sixty times a second.
;;
;; The clock counts up in <CQTIMR>, skipping a count every 623 to keep time with the retrace's slightly faster
;; rate, and goes back to zero after a day. Then keyboard row 9, which the scan leaves selected, is read into
;; <STKEY>.
;; Uses: A, X
UDTIM:
    inc SKIP_COUNT
    lda SKIP_COUNT
    bne UDTIM_1
    inc SKIP_COUNT+1
UDTIM_1:
    cmp #<623
    bne UDTIM_2
    lda SKIP_COUNT+1
    cmp #>623
    beq UDTIM_6
UDTIM_2:
    inc CQTIMR+2                            ; count a jiffy, high byte first
    bne UDTIM_3
    inc CQTIMR+1
    bne UDTIM_3
    inc CQTIMR
UDTIM_3:
    ldx #$00                                ; a day gone?
UDTIM_4:
    lda CQTIMR,x
    cmp UD70,x
    bcc UDTIM_7
    inx
    cpx #$03
    bne UDTIM_4
    lda #$00
UDTIM_5:
    sta CQTIMR - 1,x
    dex
    bne UDTIM_5
    beq UDTIM_7
UDTIM_6:
    lda #$00
    sta SKIP_COUNT
    sta SKIP_COUNT+1
UDTIM_7:
    lda PIA1_PB                             ; read row 9 until steady
    cmp PIA1_PB
    bne UDTIM_7
    sta STKEY
UDTIM_8:
    rts

;; <JIFFIES_PER_DAY>, high byte first, as <CQTIMR> holds the clock.
UD70:
    .byte (JIFFIES_PER_DAY >> 16) & $FF, (JIFFIES_PER_DAY >> 8) & $FF, JIFFIES_PER_DAY & $FF

;; Makes an open file the input channel: GET#, INPUT# and the like.
;;
;; A file on the bus is commanded to talk.
;; In: X = the logical file
;; Errors: ?FILE NOT OPEN, ?NOT INPUT FILE, ?DEVICE NOT PRESENT
;; Keeps: A, X, Y
CHKIN:
    pha
    txa
    pha
    tya
    pha
    lda #$00
    sta CQSTAT
    txa
    jsr JLTLK
    beq CHKIN_3
CHKIN_1:
    ldy #MS3 - MSG1
CHKIN_2:
    jmp ERMSG
CHKIN_3:
    jsr JZ100
    lda FA
    beq CHKIN_4
    cmp #DEV_SCREEN
    beq CHKIN_4
    bcs CHKIN_5
    ldx SA
    cpx #SA_READ
    beq CHKIN_4
    ldy #MS15 - MSG1
    bne CHKIN_2
CHKIN_4:
    sta DFLTN
    jmp RSTOR
CHKIN_5:
    pha
    jsr TALK
    lda SA
    bpl CHKIN_6
    jsr TKATN
    jmp CHKIN_7
CHKIN_6:
    jsr TKSA
CHKIN_7:
    lda CQSTAT
    bpl CHKIN_8
    jmp OP37
CHKIN_8:
    pla
    jmp CHKIN_4

;; Makes an open file the output channel: PRINT# and CMD.
;;
;; A file on the bus is commanded to listen.
;; In: X = the logical file
;; Errors: ?FILE NOT OPEN, ?NOT OUTPUT FILE, ?DEVICE NOT PRESENT
;; Keeps: A, X, Y
CHKOUT:
    pha
    txa
    pha
    tya
    pha
    lda #$00
    sta CQSTAT
    txa
    jsr JLTLK
    bne CHKIN_1
    jsr JZ100
    lda FA
    bne CHKOUT_1
    ldy #MS16 - MSG1
    bne CHKIN_2
CHKOUT_1:
    cmp #DEV_SCREEN
    beq CHKOUT_2
    bpl CHKOUT_3
    ldx SA
    cpx #SA_READ
    bne CHKOUT_2
    ldy #MS16 - MSG1
    bne CHKIN_2
CHKOUT_2:
    sta DFLTO
    jmp RSTOR
CHKOUT_3:
    pha
    jsr LISTN
    lda SA
    bpl CHKOUT_4
    jsr SCATN
    bne CHKOUT_5
CHKOUT_4:
    jsr SECND
CHKOUT_5:
    lda CQSTAT
    bpl CHKOUT_6
    jmp OP37
CHKOUT_6:
    pla
    jmp CHKOUT_2

;; Moves the current cassette's buffer index to the next byte.
;; In: FA = the cassette
;; Out: Y = the index, zero = set when the buffer is full, X = FA
;; Uses: A
JTP20:
    jsr ZZZ
    ldx FA
    inc BUFPNT - 1,x
    ldy BUFPNT - 1,x
    cpy #TAPE_BUFFER_SIZE
    rts

;; Asks for PLAY on the cassette in <FA> and waits for it, unless it is already down; STOP stops the program.
;; Uses: A, X, Y
CSTE1:
    jsr CS10
    beq CS10_2
    ldy #MS7 - MSG1
CSTE1_1:
    jsr MSG
    ldy #MS9 - MSG1
    jsr MSG
    lda FA
    ora #'0'
    jsr PRT
CSTE1_2:
    jsr TSTOP
    jsr CS10
    bne CSTE1_2
    ldy #MS18 - MSG1
    jmp MSG

;; Reads the keys of the cassette in <FA>.
;; Out: zero = set while PLAY is down
;; Uses: A, X
CS10:
    lda #PIA1_SENSE1
    ldx FA
    dex
    beq CS10_1
    lda #PIA1_SENSE2
CS10_1:
    bit PIA1_PA
    bne CS10_2
    bit PIA1_PA
CS10_2:
    rts

;; Asks for PLAY and RECORD on the cassette in <FA> and waits for a key, unless one is already down.
;; Uses: A, X, Y
CSTE2:
    jsr CS10
    beq CS10_2
    ldy #MS7 - MSG1
    jsr MSG
    ldy #MS8 - MSG1
    bne CSTE1_1

;; Reads the next tape block into the cassette's buffer, and waits for it.
;; Out: CQSTAT = the result
RBLK:
    lda #$00
    sta CQSTAT
    sta VERCK
    jsr LDAD1

;; Starts reading a tape block into <STAL> to <EAL>, after PLAY.
;;
;; It enables the cassette's read-line interrupt, CA1 of PIA 1 for cassette 1 or CB1 of the VIA for cassette 2,
;; and starts the motor with <READ> as the interrupt handler.
TRD:
    jsr TWAIT
    jsr CSTE1
    sei
    lda #$00
    sta BLOCK_STATE
    sta TIMER_ON
    sta TAPE_SPEED
    sta PTR1
    sta PTR2
    sta DPSW
    ldx FA
    dex
    beq TRD_1
    lda #VIA_IER_SET | VIA_IRQ_CB1
    sta VIA_IER                             ; the CB1 interrupt for cassette 2
    bne TRD_2
TRD_1:
    inc PIA1_CRA                            ; the CA1 interrupt for cassette 1
TRD_2:
    ldx #IRQV_READ
    bne TAPE

;; Writes the cassette's buffer to tape as a block.
WBLK:
    jsr LDAD1

;; Writes <STAL> to <EAL> to tape after a short leader, the length a data block has.
TWRT:
    jsr TWAIT
    lda #TAPE_DATA_LEADER
    sta CHECKSUM

;; Starts writing <STAL> to <EAL> to tape, after PLAY and RECORD, and waits until it is written.
;; In: CHECKSUM = the leader's length
TWRT2:
    jsr CSTE2
    sei
    lda #VIA_IER_SET | VIA_IRQ_T2
    sta VIA_IER                             ; timer 2's interrupt
    ldx #IRQV_LEADER

;; Starts the tape: sets the interrupt handler, the two copies, the motor and its interlock, waits a third of a
;; second for the motor's speed, starts the VIA's timer 2, then waits for the handler to finish.
;;
;; The retrace interrupt is off while the tape runs, so this updates the clock itself.
;; In: X = the handler's index in <IRQ_VECTORS>
TAPE:
    jsr BSIV
    lda #2
    sta FSBLK
    jsr NEWCH
    dec PIA1_CRB                            ; the retrace interrupt off
    ldx FA
    dex
    bne TAPE_1
    lda #PIA_LOW
    sta PIA1_CRB                            ; cassette 1 motor on
    sta CAS1
    bne TAPE_2
TAPE_1:
    lda VIA_ORB
    stx CAS2
    and #(~VIA_MOTOR2) & $FF
    sta VIA_ORB                             ; cassette 2 motor on
TAPE_2:
    ldx #$FF                                ; let the motor reach speed
TAPE_3:
    ldy #$FF
TAPE_4:
    dey
    bne TAPE_4
    dex
    bne TAPE_3
    sta VIA_T2CH                            ; start timer 2
    cli
TAPE_5:
    lda #>KEY
    cmp CINV+1
    beq TAPE_6
    jsr TSTOP
    bit PIA1_CRB
    bpl TAPE_5
    bit PIA1_PB
    jsr UDTIM                               ; count the jiffy the retrace would have
    jmp TAPE_5
TAPE_6:
    rts

;; Waits until the tape's interrupt handler has finished and <CINV> points at the editor's again; STOP stops the
;; program.
;; Uses: A
TWAIT:
    jsr TSTOP
    lda #>KEY
    cmp CINV+1
    bne TWAIT
    rts

;; Checks for STOP while the tape runs: if it is down, stops the tape, restores the channels and stops the program.
;; Uses: A
TSTOP:
    jsr STOP1
    bne TSTOP_1
    jsr TNIF
    jsr JX770
    sta CHANNL
TSTOP_1:
    jmp STOP

;; Starts the VIA's timer 1 to time out after a period scaled by <TAPE_SPEED>, so a missing pulse is noticed.
;; In: X = the period
;; Uses: A, X
STT1:
    stx PULSE_WIDTH
    lda TAPE_SPEED
    asl a
    asl a
    clc
    adc TAPE_SPEED
    clc
    adc PULSE_WIDTH
    sta PULSE_WIDTH
    lda #$00
    bit TAPE_SPEED
    bmi STT1_1
    rol a
STT1_1:
    asl PULSE_WIDTH
    rol a
    asl PULSE_WIDTH
    rol a
    tax
STT1_2:
    lda VIA_T2CL
    cmp #$15
    bcc STT1_2
    adc PULSE_WIDTH
    sta VIA_T1CL
    txa
    adc VIA_T2CH
    sta VIA_T1CH
    cli
    rts

;; Handles each pulse read from the tape, as the interrupt handler while a block is read.
;;
;; It times the pulse with the VIA's timer 2, sorts it as short, medium or long against <TAPE_SPEED> (which it
;; adjusts as the tape's speed drifts), and pairs the pulses into bits, the bits into bytes, checking parity. A
;; byte marker starts each byte; the VIA's timer 1 runs out in the gap after a block. Each complete byte goes to
;; <RADJ>.
READ:
    ldx VIA_T2CH                            ; the pulse's length from timer 2
    ldy #$FF
    tya
    sbc VIA_T2CL
    cpx VIA_T2CH
    bne READ
    stx PULSE_WIDTH
    tax
    sty VIA_T2CL                            ; restart timer 2
    sty VIA_T2CH
    tya
    sbc PULSE_WIDTH
    stx PULSE_WIDTH
    lsr a                                   ; in units of 4 microseconds
    ror PULSE_WIDTH
    lsr a
    ror PULSE_WIDTH
    lda TAPE_SPEED
    clc
    adc #$3C
    bit VIA_ORB                             ; clear the read lines' interrupt flags
    bit PIA1_PA
    cmp PULSE_WIDTH                         ; shorter is noise
    bcs READ_7
    ldx DPSW                                ; a byte marker seen?
    beq READ_1
    jmp RADJ
READ_1:
    ldx BITCI                               ; expecting a byte marker?
    bmi READ_2
    ldx #$00
    adc #$30
    adc TAPE_SPEED
    cmp PULSE_WIDTH                         ; short?
    bcs READ_4
    inx
    adc #$26
    adc TAPE_SPEED
    cmp PULSE_WIDTH                         ; medium?
    bcs READ_5
    adc #$2C
    adc TAPE_SPEED
    cmp PULSE_WIDTH                         ; long?
    bcc READ_3
READ_2:
    jmp READ_14
READ_3:
    lda TIMER_ON
    beq READ_7
    sta PULSE_ERROR
    bne READ_7
READ_4:
    inc SEQUENCE
    bcs READ_6
READ_5:
    dec SEQUENCE
READ_6:
    sec                                     ; track the drift from the expected length
    sbc #$13
    sbc PULSE_WIDTH
    adc TAPE_DRIFT
    sta TAPE_DRIFT
    lda PULSE_PHASE                         ; the first or the second pulse of a bit?
    eor #$01
    sta PULSE_PHASE
    beq READ_10
    stx CHAR_TEMP
READ_7:
    lda TIMER_ON
    beq READ_9
    bit VIA_IFR                             ; the gap after the block?
    bvc READ_9
    lda #$00
    sta PULSE_PHASE
    lda BITCI
    bpl READ_13
    bmi READ_2
READ_8:
    ldx #$A6
    jsr STT1
    lda PRTY
    bne READ_3
READ_9:
    jmp PREND
READ_10:
    lda TAPE_DRIFT                          ; adjust the timing to the drift
    beq READ_12
    bmi READ_11
    dec TAPE_SPEED
    dec TAPE_SPEED
READ_11:
    inc TAPE_SPEED
READ_12:
    lda #$00
    sta TAPE_DRIFT
    cpx CHAR_TEMP                           ; the same pulse twice: not a bit
    bne READ_13
    txa
    bne READ_3
    lda SEQUENCE
    bmi READ_7
    cmp #$10                                ; a leader: 16 short pulses
    bcc READ_7
    sta LEADER_SEEN
    bcs READ_7
READ_13:
    txa                                     ; a bit: into the parity and the byte
    eor PRTY
    sta PRTY
    lda TIMER_ON
    beq READ_9
    dec BITCI
    bmi READ_8                              ; the parity bit next?
    lsr CHAR_TEMP
    ror MYCH
    ldx #$DA
    jsr STT1
    jmp PREND
READ_14:
    lda LEADER_SEEN                         ; a long pulse: a byte marker
    beq READ_15
    lda TIMER_ON
    beq READ_16
READ_15:
    lda BITCI
    bmi READ_16
    jmp READ_5
READ_16:
    lsr PULSE_WIDTH
    lda #$93
    sec
    sbc PULSE_WIDTH
    adc TAPE_SPEED
    asl a
    tax
    jsr STT1
    inc DPSW
    lda TIMER_ON
    bne READ_17
    lda LEADER_SEEN
    beq READ_19
    sta PULSE_ERROR
    lda #$00
    sta LEADER_SEEN
    lda #VIA_IER_SET | VIA_IRQ_T1           ; watch for the gap with timer 1
    sta VIA_IER
    sta TIMER_ON
READ_17:
    lda LEADER_SEEN
    sta END_SEEN
    beq READ_18
    lda #$00
    sta TIMER_ON
    lda #VIA_IRQ_T1
    sta VIA_IER
READ_18:
    lda MYCH                                ; the byte is complete
    sta TAPE_BYTE
    lda PULSE_ERROR
    ora SEQUENCE
    sta BYTE_ERROR
READ_19:
    jmp PREND

;; Takes a complete byte read from tape: finds the leader's end and the sync bytes, then stores or compares each
;; data byte, logging the first copy's bad bytes in <BAD> and correcting them from the second, and at the block's
;; end checks the checksum.
RADJ:
    jsr NEWCH
    sta DPSW
    ldx #$DA
    jsr STT1
    lda FSBLK
    beq RADJ_1
    sta PASSES
RADJ_1:
    lda #$0F                                ; what the byte is for
    bit BLOCK_STATE
    bpl RADJ_4
    lda END_SEEN
    bne RADJ_2
    ldx FSBLK
    dex
    bne RADJ_3
    lda #ST_LONG_BLOCK
    jsr UDST
    bne RADJ_3
RADJ_2:
    lda #$00
    sta BLOCK_STATE
RADJ_3:
    jmp PREND
RADJ_4:
    bvs RADJ_8                              ; reading data?
    bne RADJ_6                              ; counting sync bytes?
    lda END_SEEN
    bne RADJ_3
    lda BYTE_ERROR
    bne RADJ_3
    lda PASSES                              ; a sync byte of the copy expected?
    lsr a
    lda TAPE_BYTE
    bmi RADJ_5
    bcc RADJ_7
    clc
RADJ_5:
    bcs RADJ_7
    and #$0F
    sta BLOCK_STATE
RADJ_6:
    dec BLOCK_STATE
    bne RADJ_3
    lda #$40
    sta BLOCK_STATE
    jsr RD300
    lda #$00
    sta CHECKSUM
    beq RADJ_3
RADJ_7:
    lda #$80
    sta BLOCK_STATE
    bne RADJ_3
RADJ_8:
    lda END_SEEN
    beq RADJ_9
    lda #ST_SHORT_BLOCK
    jsr UDST
    lda #$00
    jmp RADJ_18
RADJ_9:
    jsr WRT62                               ; past the end address?
    bne RADJ_10
    jmp RADJ_17
RADJ_10:
    ldx PASSES
    dex                                     ; the first copy or the second?
    beq RADJ_12
    lda VERCK
    beq RADJ_11
    ldy #$00
    lda TAPE_BYTE
    cmp (SAL),y
    beq RADJ_11
    lda #$01
    sta BYTE_ERROR
RADJ_11:
    lda BYTE_ERROR
    beq RADJ_15
    ldx #$3D                                ; log a bad byte of the first copy
    cpx PTR1
    bcc RADJ_14
    ldx PTR1
    lda SAL+1
    sta BAD+1,x
    lda SAL
    sta BAD,x
    inx
    inx
    stx PTR1
    jmp RADJ_15
RADJ_12:
    ldx PTR2                                ; the second copy: only the bytes logged
    cpx PTR1
    beq RADJ_16
    lda SAL
    cmp BAD,x
    bne RADJ_16
    lda SAL+1
    cmp BAD+1,x
    bne RADJ_16
    inc PTR2
    inc PTR2
    lda VERCK
    beq RADJ_13
    lda TAPE_BYTE
    ldy #$00
    cmp (SAL),y
    beq RADJ_16
    lda #$01
    sta BYTE_ERROR
RADJ_13:
    lda BYTE_ERROR
    beq RADJ_15
RADJ_14:
    lda #ST_READ_ERROR
    jsr UDST
    bne RADJ_16
RADJ_15:
    lda VERCK                               ; store the byte, unless verifying
    bne RADJ_16
    lda TAPE_BYTE
    ldy #$00
    sta (SAL),y
RADJ_16:
    inc SAL
    bne RADJ_21
    inc SAL+1
    bne RADJ_21
RADJ_17:
    lda #$80
RADJ_18:
    sta BLOCK_STATE
    ldx FSBLK
    dex
    bmi RADJ_19
    stx FSBLK
RADJ_19:
    dec PASSES                              ; both copies read?
    beq RADJ_20
    lda PTR1
    bne RADJ_21
    sta FSBLK
    beq RADJ_21
RADJ_20:
    jsr TNIF                                ; stop the tape and check the sum
    jsr RD300
    ldy #$00
    sty CHECKSUM
    jsr VPRTY
    lda CHECKSUM
    eor TAPE_BYTE
    beq RADJ_21
    lda #ST_CHECKSUM
    jsr UDST
RADJ_21:
    jmp PREND

;; Sets <SAL> to <STAL>, the start of the block.
;; Uses: A
RD300:
    lda STAL+1
    sta SAL+1
    lda STAL
    sta SAL
    rts

;; Adds bits to the I/O status.
;; In: A = the bits
;; Out: A = CQSTAT
UDST:
    ora CQSTAT
    sta CQSTAT
    rts

;; Resets the tape's bit state for a new byte: 8 bits to come, parity and error flags clear.
;; Out: A = 0
NEWCH:
    lda #$08
    sta BITCI
    lda #$00
    sta PULSE_PHASE
    sta PULSE_ERROR
    sta PRTY
    sta SEQUENCE
    rts

;; Writes the next pulse of a bit to tape: medium for a 1 in bit 0 of <TAPE_BYTE>, short for a 0.
;; Out: zero = clear after the first half of the pulse
;; Uses: A, X
;; Entry: WRTW = writes a medium pulse, WRT1 = a pulse of the length in A
WRITE:
    lda TAPE_BYTE
    lsr a
    lda #$60
    bcc WRT1
WRTW:
    lda #$B0
WRT1:
    ldx #$00

;; Writes half of a tape pulse: sets the VIA's timer 2 to its length and toggles the write line.
;; In: A = the length's low byte, X = its high byte
;; Out: zero = set when the write line went low, the end of a pulse
WRTX:
    sta VIA_T2CL
    stx VIA_T2CH
    lda VIA_ORB
    eor #VIA_TAPE_WRITE
    sta VIA_ORB
    and #VIA_TAPE_WRITE
    rts

;; Marks the end of a block's data, the checksum sent, by setting bit 7 of <SAL>'s high byte.
WRTL3:
    sec
    ror SAL+1
    bmi WRTN_3

;; Writes a tape block's bytes, as the interrupt handler while a block is written.
;;
;; Each byte is a byte marker, a long then a medium pulse, then its eight bits and the parity bit, two pulses each.
;; The bytes are the nine sync bytes, the data from <SAL> to <EAL>, and the checksum. At the block's end
;; <WRNC> goes on to the second copy or stops the tape.
WRTN:
    lda PULSE_ERROR                         ; the byte marker's long pulse
    bne WRTN_1
    lda #$10
    ldx #$01
    jsr WRTX
    bne WRTN_3
    inc PULSE_ERROR
    lda SAL+1
    bpl WRTN_3
    jmp WRNC
WRTN_1:
    lda SEQUENCE                            ; then its medium pulse
    bne WRTN_2
    jsr WRTW
    bne WRTN_3
    inc SEQUENCE
    bne WRTN_3
WRTN_2:
    jsr WRITE                               ; then the bits, two pulses each
    bne WRTN_3
    lda PULSE_PHASE
    eor #$01
    sta PULSE_PHASE
    beq WRTN_4
    lda TAPE_BYTE                           ; the second pulse is the bit's other length
    eor #$01
    sta TAPE_BYTE
    and #$01
    eor PRTY
    sta PRTY
WRTN_3:
    jmp PREND
WRTN_4:
    lsr TAPE_BYTE
    dec BITCI                               ; all bits and the parity bit sent?
    lda BITCI
    beq WRTS_4
    bpl WRTN_3

;; Picks the next byte to write: a sync byte, the next data byte (adding it to the checksum), or the checksum.
WRTS:
    jsr NEWCH
    cli
    lda SYNC_COUNT                          ; a sync byte next?
    beq WRTS_2
    ldx #$00
    stx CHAR_TEMP
    dec SYNC_COUNT
    ldx FSBLK
    cpx #$02
    bne WRTS_1
    ora #$80                                ; the first copy's have bit 7 set
WRTS_1:
    sta TAPE_BYTE
    bne WRTN_3
WRTS_2:
    jsr WRT62                               ; a data byte, or the checksum?
    bcc WRTS_3
    bne WRTL3
    inc SAL+1
    lda CHAR_TEMP
    sta TAPE_BYTE
    bcs WRTN_3
WRTS_3:
    ldy #$00
    lda (SAL),y
    sta TAPE_BYTE
    eor CHAR_TEMP
    sta CHAR_TEMP
    inc SAL
    bne WRTN_3
    inc SAL+1
    bne WRTN_3
WRTS_4:
    lda PRTY                                ; the odd parity bit
    eor #$01
    sta TAPE_BYTE
WRTS_5:
    jmp PREND

;; Ends a copy of a block: stops the motor after the second, and writes the gap's leader before the next.
WRNC:
    dec FSBLK
    bne WRNC_1
    jsr TNOF
WRNC_1:
    lda #$50                                ; the gap before the next copy
    sta PASSES
    ldx #IRQV_LEADER
    sei
    jsr BSIV
    bne WRTS_5

;; Writes a leader of short pulses, as the interrupt handler before each copy of a block.
;;
;; Groups of 80 pulses repeat <CHECKSUM> times; then <WRTN> writes the copy.
WRTZ:
    lda #$78
    jsr WRT1
    bne WRTS_5
    dec PASSES
    bne WRTS_5
    jsr NEWCH                               ; a group of 80 pulses done
    dec CHECKSUM
    bpl WRTS_5
    ldx #IRQV_WRITE
    jsr BSIV
    cli
    inc CHECKSUM
    lda FSBLK
    beq STKY
    jsr RD300                               ; the next copy, from the start
    ldx #$09
    stx SYNC_COUNT
    bne WRTS

;; Stops the tape: motors off, the VIA's interrupts off, cassette 1's read interrupt off and the retrace interrupt
;; on, and <CINV> back to the editor's handler.
;; Keeps: interrupt
TNIF:
    php
    sei
    jsr TNOF
    lda #VIA_IRQ_ALL
    sta VIA_IER
    lda #PIA_HIGH
    sta PIA1_CRA
    lda #PIA_HIGH_IRQ
    sta PIA1_CRB
    ldx #IRQV_NORMAL
    jsr BSIV
    plp
    rts

;; Stops the tape after the last copy of a block and leaves the interrupt.
STKY:
    jsr TNIF
    beq WRTS_5

;; Sets the interrupt handler.
;; In: X = its index in <IRQ_VECTORS>
;; Uses: A
BSIV:
    lda IRQ_VECTORS - 8,x
    sta CINV
    lda IRQ_VECTORS - 8 + 1,x
    sta CINV+1
    rts

;; Stops both cassettes' motors and the retrace interrupt.
;; Uses: A
TNOF:
    lda #PIA_HIGH
    sta PIA1_CRB
    lda VIA_ORB
    ora #VIA_MOTOR2
    sta VIA_ORB
    rts

;; Adds <SAL> up to <EAL> into <CHECKSUM> with exclusive or.
;; In: Y = 0
;; Uses: A
VPRTY:
    lda (SAL),y
    eor CHECKSUM
    sta CHECKSUM
    inc SAL
    bne VPRTY_1
    inc SAL+1
VPRTY_1:
    jsr WRT62
    bne VPRTY
    rts

;; Compares <SAL> with <EAL>.
;; Out: zero = set when equal, carry = set when SAL is at or past EAL
;; Uses: A
WRT62:
    lda SAL+1
    cmp EAL+1
    bne WRT62_1
    lda SAL
    cmp EAL
WRT62_1:
    rts

;; Starts the PET at power-up and reset.
;;
;; It sets up the I/O and the screen (<CINT>), the NMI vector to BASIC's <READY>, the BRK vector to the
;; monitor, and the monitor's vector for unknown commands, then starts BASIC (<INIT>), or the monitor when the
;; diagnostic sense line is low.
START:
    ldx #$FF
    txs
    cld
    jsr CINT                                ; set up the I/O and the screen
    lda #<READY
    sta NMINV
    lda #>READY
    sta NMINV+1
    lda #<BRKE
    sta CBINV
    lda #>BRKE
    sta CBINV+1
    lda #<ERROPR
    sta USRCMD
    lda #>ERROPR
    sta USRCMD+1
    cli
    lda PIA1_PA                             ; the diagnostic sense line (PA7)
    bmi START_1
    jmp CALLE
START_1:
    jmp INIT

;; Handles NMI through <NMINV>.
NMI:
    jmp (NMINV)
    .byte 0, 0, 0, 0, 0, 0, 0, 0                                ; unused: BSIV's indexes start at 8

;; The interrupt handlers <BSIV> loads into <CINV>, at the indexes <IRQV_LEADER>, <IRQV_WRITE>, <IRQV_NORMAL>
;; and <IRQV_READ> from 8 bytes before this table.
IRQ_VECTORS:
    .word WRTZ, WRTN, KEY, READ
    .assert IRQ_VECTORS + IRQV_READ - 8 = $FD0F, "BSIV's indexes reach the table."

;; Enters the monitor at reset, showing "C*" and the registers.
CALLE:
    lda #'C'
    sta WORKB
    bne B3

;; Enters the monitor from BRK, showing "B*" and the registers.
;;
;; It saves the registers the interrupt pushed, the program counter less one (after BRK, the address of its
;; padding byte), <CINV> and the stack pointer, from <MON_PCH> up.
;; Entry: B3 = saves from the program counter on
BRKE:
    lda #'B'
    sta WORKB
    cld
    lsr a                                   ; clear carry, so the PC's low byte drops one
    pla
    sta MON_YR
    pla
    sta MON_XR
    pla
    sta MON_AC
    pla
    sta MON_SR
B3:
    pla
    adc #$FF
    sta MON_PCL
    pla
    adc #$FF
    sta MON_PCH
    lda CINV
    sta MON_INVL
    lda CINV+1
    sta MON_INVH
    tsx
    stx MON_SP
    cli
    jsr CRLF
    ldx WORKB
    lda #'*'
    jsr WRTWO
    lda #'R'

;; Inherit: <STRT>
;; With zero clear, runs the command in A instead of prompting.
MON_RESUME:
    bne S0

;; Prompts for and runs monitor commands: prints "." on a new line, skips dots and spaces, and runs the command
;; letter typed; one it doesn't know goes through <USRCMD>.
;;
;; It stores 2 in the low byte of BASIC's <TXTPTR>.
;; Entry: S0 = runs the command in A
STRT:
    lda #$02
    sta TXTPTR                              ; (BASIC tests the high byte)
    lda #$00
    sta FSBLK
    ldx #KEY_RETURN
    lda #'.'
    jsr WRTWO
STRT_1:
    jsr RDOC
    cmp #'.'
    beq STRT_1
    cmp #' '
    beq STRT_1
S0:
    ldx #ADRH - CMDS - 1
STRT_2:
    cmp CMDS,x
    bne STRT_3
    stx WORKA
    lda ADRH,x
    pha                                     ; the routine less one, for RTS
    lda ADRL,x
    pha
    rts
STRT_3:
    dex
    bpl STRT_2
    jmp (USRCMD)

;; Makes <STAL> the program counter G and the registers return to.
;; Uses: A
PUTP:
    lda STAL
    sta MON_PCL
    lda STAL+1
    sta MON_PCH
    rts

;; Shows bytes from <STAL>, each after a space.
;; In: A = the count
;; Out: STAL = past them
;; Uses: A, X, Y
DM:
    sta WORKB
    ldy #$00
DM_1:
    jsr SPACE
    lda (STAL),y
    jsr WROB
    jsr INCTMP
    dec WORKB
    bne DM_1
    rts

;; Reads a hexadecimal byte typed and stores it at <STAL>, which then moves on; two spaces leave the byte as it is.
;; Errors: ? when the byte doesn't read back as stored
;; Uses: A, X
BYTE:
    jsr RDOB
    bcc BYTE_1
    ldx #$00
    sta (STAL,x)
    cmp (STAL,x)
    beq BYTE_1
    pla
    pla
    jmp ERROPR
BYTE_1:
    jsr INCTMP
    dec WORKB
    rts

;; Points <STAL> at the saved registers, <MON_SR> on, and returns their count.
;; Out: A = 5
SETR:
    lda #<MON_SR
    sta STAL
    lda #>MON_SR
    sta STAL+1
    lda #MON_SP - MON_SR + 1
    rts

;; Prints two spaces.
;; Uses: A
SPAC2:
    jsr SPACE

;; Prints a space.
;; Uses: A
SPACE:
    lda #' '
    .byte BIT_ABSOLUTE                                          ; skips the lda #$0D: prints the space

;; Prints a carriage return.
;; Uses: A
CRLF:
    lda #KEY_RETURN
    jmp OUTCH

;; Moves <STAL> to the next address, setting <FSBLK> when it wraps past $FFFF.
INCTMP:
    inc STAL
    bne INCTMP_1
    inc STAL+1
    bne INCTMP_1
    inc FSBLK
INCTMP_1:
    rts

;; The monitor's command letters, searched from the end: : alters memory, ; the registers, R shows the registers,
;; M memory, G runs a program, X returns to BASIC, and L and S load and save.
CMDS:
    .byte ":;RMGXLS"

;; The high bytes of each command's routine less one, for an RTS to jump to.
ADRH:
    .byte >(ALTM - 1), >(ALTR - 1), >(DSPLYR - 1), >(DSPLYM - 1)
    .byte >(GO - 1), >(EXIT - 1), >(LD - 1), >(LD - 1)

;; The low bytes of each command's routine less one.
ADRL:
    .byte <(ALTM - 1), <(ALTR - 1), <(DSPLYR - 1), <(DSPLYM - 1)
    .byte <(GO - 1), <(EXIT - 1), <(LD - 1), <(LD - 1)

;; The heading <DSPLYR> prints over the registers.
REGK:
    .byte $0D, "     PC  IRQ  SR AC XR YR SP"
MON_HEADER_END:

;; Starts a line the monitor can read back: a carriage return, ".", the command letter and two spaces.
;; In: Y = the letter
;; Uses: A, X
ALTRIT:
    tya
    pha
    jsr CRLF
    pla
    ldx #'.'
    jsr WRTWO
    jmp SPAC2

;; Shows the registers: the R command, and what BRK shows.
DSPLYR:
    ldx #0
DSPLYR_1:
    lda REGK,x
    jsr OUTCH
    inx
    cpx #MON_HEADER_END - REGK
    bne DSPLYR_1
    ldy #';'
    jsr ALTRIT
    lda MON_PCH
    jsr WROB
    lda MON_PCL
    jsr WROB
    jsr SPACE
    lda MON_INVH
    jsr WROB
    lda MON_INVL
    jsr WROB
    jsr SETR
    jsr DM
    beq BEQS1

;; Shows memory, eight bytes a line from the first address typed to the second: the M command.
;;
;; Each line starts with ".:" so that changes typed over it and RETURN store them. STOP ends it.
DSPLYM:
    jsr RDOC
    jsr RDOA
    bcc ERRS1
    jsr T2T2
    jsr RDOC
    jsr RDOA
    bcc ERRS1
    jsr T2T2
DSPLYM_1:
    jsr STOP1
    beq BEQS1
    ldx FSBLK
    bne BEQS1
    sec
    lda MEMUSS
    sbc STAL
    lda MEMUSS+1
    sbc STAL+1
    bcc BEQS1
    ldy #':'
    jsr ALTRIT
    jsr WROA
    lda #$08
    jsr DM
    beq DSPLYM_1

;; Ends a command, returning to the prompt.
BEQS1:
    jmp STRT

;; Ends a command that couldn't be read, printing "?".
ERRS1:
    jmp ERROPR

;; Changes the saved registers from a line the R command showed: the ; command.
ALTR:
    jsr RDOB
    jsr RDOA
    bcc ALTR_1
    jsr PUTP
ALTR_1:
    jsr CQINCH
    jsr RDOA
    bcc ALTR_2
    lda STAL
    sta MON_INVL
    lda STAL+1
    sta MON_INVH
ALTR_2:
    jsr SETR
    bne ALTM_1

;; Stores eight bytes typed at the address typed: the : command, a line the M command showed.
ALTM:
    jsr RDOB
    jsr RDOA
    bcc ERRS1
    lda #$08
ALTM_1:
    sta WORKB
ALTM_2:
    jsr RDOC
    jsr BYTE
    bne ALTM_2
    beq BEQS1

;; Runs a program, from the address typed or the saved program counter, with the saved registers: the G command.
GO:
    jsr CQINCH
    cmp #KEY_RETURN
    beq GO_1
    cmp #' '
    bne ERRS1
    jsr RDOA
    bcc GO_1
    jsr PUTP
GO_1:
    ldx MON_SP
    txs
    sei
    lda MON_INVH
    sta CINV+1
    lda MON_INVL
    sta CINV
    lda MON_PCH
    pha
    lda MON_PCL
    pha
    lda MON_SR
    pha
    lda MON_AC
    ldx MON_XR
    ldy MON_YR
    rti                                     ; into the program

;; Returns to BASIC: the X command.
EXIT:
    ldx MON_SP
    txs
    jmp READY

;; Ends an L or S command that couldn't be read, printing "?".
ERRL:
    jmp ERROPR

;; Loads or saves memory: the L and S commands.
;;
;; L "NAME",D loads from device D (1 by default) to the program's own address; S "NAME",D,START,END saves START up
;; to END. The name may be left out for L.
LD:
    ldy #$01
    sty FA
    dey
    sty FNLEN
    sty VERCK
    lda #>MON_NAME
    sta FNADR+1
    lda #<MON_NAME
    sta FNADR
LD_1:
    jsr CQINCH
    cmp #' '
    beq LD_1
    cmp #KEY_RETURN
    beq LD_5
    cmp #'"'
LD_2:
    bne ERRL
LD_3:
    jsr CQINCH
    cmp #'"'
    beq LD_8
    cmp #KEY_RETURN
    beq LD_5
    sta (FNADR),y
    inc FNLEN
    iny
    cpy #16
LD_4:
    beq ERRL
    bne LD_3
LD_5:
    lda WORKA
    cmp #MON_COMMAND_L
LD_6:
    bne LD_2
    jsr LD15
    jsr TWAIT
    lda CQSTAT
    and #$10
LD_7:
    bne LD_6
    jmp STRT
LD_8:
    jsr CQINCH
    cmp #KEY_RETURN
    beq LD_5
    cmp #','
LD_9:
    bne LD_7
    jsr RDOB
    and #$0F
LD_10:
    beq LD_4
    cmp #DEV_SCREEN
    beq LD_10
    sta FA
    jsr CQINCH
    cmp #KEY_RETURN
    beq LD_5
    cmp #','
LD_11:
    bne LD_9
    jsr RDOA
    jsr T2T2
    jsr CQINCH
    cmp #','
LD_12:
    bne LD_11
    jsr RDOA
    lda STAL
    sta EAL
    lda STAL+1
    sta EAL+1
    jsr T2T2
LD_13:
    jsr CQINCH
    cmp #' '
    beq LD_13
    cmp #KEY_RETURN
LD_14:
    bne LD_12
    lda WORKA
    cmp #MON_COMMAND_S
    bne LD_14
    jsr SV5
    jmp STRT

;; Commodore's mark, which nothing reads.
SIGNATURE:
    .byte "C. 0978 CBM "
    .byte $AA, $AA, $AA                                         ; unused

; The jump table, at the addresses programs and BASIC call.

;; Opens a file: <OPEN>, BASIC's OPEN.
CQOPEN:
    jmp OPEN

;; Closes a file: <CLOSE>, BASIC's CLOSE.
CQCLOS:
    jmp CLOSE

;; Sets the input channel: <CHKIN>.
CQOIN:
    jmp CHKIN

;; Sets the output channel: <CHKOUT>.
CQOOUT:
    jmp CHKOUT

;; Restores the default channels: <CLRCHN>.
CQCCHN:
    jmp CLRCHN

;; Reads a character: <BASIN>.
CQINCH:
    jmp BASIN

;; Writes a character: <BSOUT>.
OUTCH:
    jmp BSOUT

;; Loads a program: <LOAD>, BASIC's LOAD.
CQLOAD:
    jmp LOAD

;; Saves the program: <SAVE>, BASIC's SAVE.
CQSAVE:
    jmp SAVE

;; Verifies a program: <VER>, BASIC's VERIFY.
CQVERF:
    jmp VER

;; Calls machine language: <SYS>, BASIC's SYS.
CQSYS:
    jmp SYS

;; Checks the STOP key: <STOP_KEY>.
ISCNTC:
    jmp STOP_KEY

;; Gets a character without waiting: <GETIN>.
CZGETL:
    jmp GETIN

;; Inherit: <CLALL>
CQCALL:
    jmp CLALL

;; Updates the jiffy clock: <UDTIM>, which the editor's interrupt handler calls.
JUDTIM:
    jmp UDTIM
    .byte $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA   ; unused

;; The 6502's vectors: NMI through <NMINV>, reset, and IRQ and BRK into the editor.
VECTORS:
    .word NMI, START, PULS
