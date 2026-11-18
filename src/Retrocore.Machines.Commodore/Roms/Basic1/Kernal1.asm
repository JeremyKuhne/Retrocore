;; COMMODORE PET 2001 BASIC 1 KERNAL ($F000-$FFFF)
;;
;; The kernal is the PET 2001's input and output: the logical files BASIC opens, the IEEE-488 bus, the two
;; cassettes, LOAD, SAVE and VERIFY, the jiffy clock, the reset, and a factory test.
;;
;; BASIC calls it through the jump table at $FFC0 (<CQOPEN> to <JUDTIM>), whose entries keep their addresses while the
;; routines move. A logical file is a number in <LAT> with its device in <FAT> and secondary address in <SAT>; <CHKIN>
;; and <CHKOUT> make a file the input or output, so that <BASIN> and <BSOUT> read and write it, and <CLRCHN> goes back
;; to the keyboard and screen, which the screen editor (Editor1.asm) runs.
;;
;; The IEEE-488 routines (<TALK>, <LISTN>, <SECND>, <CIOUT>, <ACPTR> and the like) drive the bus's handshake
;; through PIA 2 and the VIA by hand, with timer 1 timing out a device that does not answer.
;;
;; A cassette is read and written a pulse at a time by interrupt routines that <BSIV> puts in <CINV>, while the
;; kernal waits in <TAPE>. Each block is preceded by a leader of short pulses, sent twice, each time after a
;; countdown of sync bytes ($89-$81, then $09-$01), and followed by its checksum. A byte is a long and a medium pulse,
;; then eight bits from bit 0 (a short and a medium for 0, a medium and a short for 1) and an odd parity bit. A file
;; starts with a 192-byte header (<TAPEH>): its kind, its start and end addresses and its name. Reading the second copy
;; of a block puts right the bytes the first copy read badly.
;;
;; Holding the diagnostic jumper on at reset starts the factory test (<DIAG>) instead of BASIC.
;;
;; The jump table's names are Microsoft's, from its 6502 BASIC. The routines take Commodore's names from its BASIC 4
;; kernal listing of 1979 where BASIC 4 has the same code, and otherwise are named after what they do.
;;
;; It includes ../PetEquates.asm (the hardware), Equates.asm (the RAM the editor and kernal share, and what they use
;; of BASIC) and EditorEntries.asm (the editor routines it calls).
;;
;; Assembles byte-identically to the 901447-06 and 901447-07 ROMs, $F000-$F7FF and $F800-$FFFF.
;;
;; Maintained by hand.

.cpu Mos6502

.include "../PetEquates.asm"
.include "Equates.asm"
.include "EditorEntries.asm"

DIAG_PTR = $00                      ;; the factory test's pointer into the RAM it checks, over BASIC's page zero
DIAG_PATTERN = $02                  ;; the factory test's pattern, exclusive-ORed into each byte it writes
TAPE_BUFFER_SIZE = 192              ;; the bytes in a cassette buffer, a block's length
MAX_FILES = 10                      ;; the files open at once, the length of <LAT>, <FAT> and <SAT>
DIRECT_LEADER = $69                 ;; <CHKSUM>'s leader count before a header, a long leader to find
DATA_LEADER = $14                   ;; <CHKSUM>'s leader count before a block of data

; The handlers in BSIT, by their offsets for BSIV.
IRQ_TIMETEST = 0                    ;; the test's check of the retrace's rate, <BSYI1>
IRQ_TEST1 = 2                       ;; the test's cassette 1 loop, <BCI1>
IRQ_TEST2 = 6                       ;; the test's cassette 2 loop, <BCI2>
IRQ_LEADER = 8                      ;; the tape write's leader, <WRTZ>
IRQ_WRITE = 10                      ;; the tape write's data, <WRTN>
IRQ_NORMAL = 12                     ;; the 60 Hz interrupt, <KEY> in the editor
IRQ_READ = 14                       ;; the tape read, <READ>

.org $F000

;; The kernal's messages, each with bit 7 set on its last character, which <Editor1:MSG> prints by their
;; offsets from here. Some start with RETURN; the errors follow a question mark, and end with " ERROR" from
;; BASIC's <TYPERR>. Some are printed from inside others: "ING " from <MS5> makes LOADING and
;; VERIFYING, and <MS10> and <MS21> without their RETURN name the errors.
MSG1:
MS1:
    .byte "TOO MANY FILE", 'S' | $80                  ; $00
MS2:
    .byte "FILE OPE", 'N' | $80                       ; $0E
MS3:
    .byte "FILE NOT OPE", 'N' | $80                   ; $17
MS4:
    .byte "FILE NOT FOUN", 'D' | $80                  ; $24
MS5:
    .byte CHR_RETURN, "SEARCHING", ' ' | $80          ; $32
MS6:
    .byte "FOR", ' ' | $80                            ; $3D
MS7:
    .byte CHR_RETURN, "PRESS PLAY", ' ' | $80         ; $41
MS8:
    .byte "& RECORD", ' ' | $80                       ; $4D
MS9:
    .byte "ON TAPE ", '#' | $80                       ; $56
MS10:
    .byte CHR_RETURN, "LOA", 'D' | $80                ; $5F
MS11:
    .byte CHR_RETURN, "WRITING", ' ' | $80            ; $64
MS21:
    .byte CHR_RETURN, "VERIF", 'Y' | $80              ; $6D
MS13:
    .byte "DEVICE NOT PRESEN", 'T' | $80              ; $74
MS15:
    .byte "NOT INPUT FIL", 'E' | $80                  ; $86
MS16:
    .byte "NOT OUTPUT FIL", 'E' | $80                 ; $94
MS17:
    .byte CHR_RETURN, "FOUND", ' ' | $80              ; $A3
MS18:
    .byte CHR_RETURN, "OK", CHR_RETURN | $80          ; $AA
MS19:
    .byte CHR_RETURN, "READY.", CHR_RETURN | $80      ; $AE

; The IEEE-488 bus.

;; Sends TALK and the device number in <FA> on the IEEE-488 bus, with ATN held low after it (<LIST1>).
;;
;; Uses: A
TALK:
    lda #IEEE_TALK
    bne LIST1

;; Sends LISTEN and the device number in <FA> on the IEEE-488 bus, with ATN held low after it (<LIST1>).
;;
;; Uses: A
LISTN:
    lda #IEEE_LISTEN

;; Sends a command on the IEEE-488 bus: lets NRFD and NDAC go, sends a character still buffered by <CIOUT> with EOI,
;; then waits for DAV to be free, pulls ATN low and sends the command with the device number in <FA> (<ISOUR>).
;;
;; In: A = the command
;; Uses: A
LIST1:
    pha
    lda VIA_ORB
    ora #VIAB_NRFD_OUT
    sta VIA_ORB                     ; let NRFD go
    lda #PIA_HIGH
    sta PIA2_CRA                    ; and NDAC
    bit C3PO                        ; a character buffered by CIOUT?
    beq LIST1_1
    lda #PIA_LOW                    ; send it with EOI
    sta PIA1_CRA
    jsr ISOUR
    lda #$00
    sta C3PO
    lda #PIA_HIGH
    sta PIA1_CRA

LIST1_1:
    pla
    ora FA                          ; the command, with the device
    sta BSOUR

LIST1_2:
    lda VIA_ORB                     ; wait for DAV to be free
    bpl LIST1_2
    and #$FF-VIAB_ATN               ; ATN low
    sta VIA_ORB

;; Sends the byte in <BSOUR> on the IEEE-488 bus with the three-wire handshake: when NRFD and NDAC are both high, no
;; device is there, and the status gets $80; otherwise it puts the byte on the data lines, waits for NRFD, pulls DAV
;; low, and waits for NDAC, with timer 1 timing out after about 65 ms ($01 in the status).
;;
;; Uses: A
ISOUR:
    lda #PIA_HIGH                   ; DAV high
    sta PIA2_CRB
    lda VIA_ORB                     ; NDAC and NRFD both high: no device
    and #VIAB_NDAC|VIAB_NRFD
    cmp #VIAB_NDAC|VIAB_NRFD
    beq ERRP7
    lda BSOUR
    eor #$FF                        ; the bus's data is inverted
    sta PIA2_PB

ISOUR_1:
    bit VIA_ORB                     ; wait for NRFD
    bvc ISOUR_1
    lda #PIA_LOW                    ; DAV low: the byte is there
    sta PIA2_CRB
    lda #$FF                        ; time out in about 65 ms
    sta VIA_T1CH

ISOUR_2:
    lda VIA_ORB                     ; wait for NDAC: the byte is taken
    bit VIA_IFR
    bvs ERRP0
    lsr a
    bcc ISOUR_2

ISOUR_3:
    lda #PIA_HIGH                   ; DAV high
    sta PIA2_CRB
    lda #$FF                        ; let the data lines go
    sta PIA2_PB
    rts

;; Sends a secondary address after LISTEN, and lets ATN go.
;;
;; In: A = the secondary address, with $60 or a CLOSE or OPEN command
;; Entry: SCATN = only lets ATN go
;; Uses: A
SECND:
    sta BSOUR
    jsr ISOUR

SCATN:
    lda VIA_ORB
    ora #VIAB_ATN                   ; ATN high
    sta VIA_ORB
    rts

;; Ends <ISOUR> when the device does not answer: sets $01 in the status (or $80 for no device) and lets the
;; bus go.
;;
;; Entry: ERR01 = with the status bit in A, ERRP7 = for no device
ERRP0:
    lda #$01

ERR01:
    jsr UDST
    bne ISOUR_3

ERRP7:
    lda #$80
    bmi ERR01

;; Ends <ACPTR> when the talker sends nothing: sets $02 in the status, holds the bus (<ER001>) and returns RETURN.
;;
;; Out: A = RETURN
ERRP1:
    lda #$02
    jsr UDST

;; Holds the IEEE-488 bus between bytes: pulls NRFD and NDAC low.
;;
;; Out: A = RETURN
ER001:
    lda VIA_ORB
    and #$FF-VIAB_NRFD_OUT          ; NRFD low
    sta VIA_ORB
    lda #PIA_LOW                    ; NDAC low
    sta PIA2_CRA
    lda #CHR_RETURN
    rts

;; Sends a secondary address after TALK, then turns the bus round so that the device can talk (<TKATN>).
;;
;; In: A = the secondary address, with $60
;; Entry: TKATN = only turns the bus round: holds NRFD and NDAC low and lets ATN go
;; Uses: A
TKSA:
    sta BSOUR
    jsr ISOUR

TKATN:
    jsr ER001
    jmp SCATN

;; Sends a byte to the IEEE-488 device that is listening, one byte late: it keeps the byte in <BSOUR> and sends the
;; one before, so that <LIST1> can send the last with EOI.
;;
;; In: A = the byte
;; Keeps: A
CIOUT:
    bit C3PO
    bmi CIOUT_1                     ; a character already buffered: send it
    dec C3PO                        ; otherwise buffer this one
    bne CIOUT_2

CIOUT_1:
    pha
    jsr ISOUR
    pla

CIOUT_2:
    sta BSOUR
    rts

;; Sends UNTALK on the IEEE-488 bus and lets ATN go.
;;
;; Out: FA = the command
;; Uses: A
UNTLK:
    lda #IEEE_UNTALK
    bne UNLSN_1

;; Sends UNLISTEN on the IEEE-488 bus, after any byte <CIOUT> still holds, and lets ATN go.
;;
;; Out: FA = the command
;; Uses: A
UNLSN:
    lda #IEEE_UNLISTEN

UNLSN_1:
    sta FA
    jsr LIST1
    bne SCATN

;; Reads a byte from the IEEE-488 device that is talking: lets NRFD go, waits for DAV with timer 1 timing out
;; (<ERRP1>), notes EOI as $40 in the status, and takes the byte from PIA 2 with NDAC.
;;
;; Out: A = the byte
ACPTR:
    lda #PIA_LOW                    ; NDAC low
    sta PIA2_CRA
    lda VIA_ORB
    ora #VIAB_NRFD_OUT              ; NRFD high: ready
    sta VIA_ORB
    lda #$FF                        ; time out in about 65 ms
    sta VIA_T1CH

ACPTR_1:
    bit VIA_IFR                     ; wait for DAV
    bvs ERRP1
    bit VIA_ORB
    bmi ACPTR_1
    lda VIA_ORB
    and #$FF-VIAB_NRFD_OUT          ; NRFD low
    sta VIA_ORB
    bit PIA1_PA                     ; EOI with it?
    bvs ACPTR_2
    lda #$40
    jsr UDST

ACPTR_2:
    lda PIA2_PA                     ; the byte, inverted on the bus
    eor #$FF
    pha
    lda #PIA_HIGH
    sta PIA2_CRA                    ; NDAC high: taken

ACPTR_3:
    bit VIA_ORB                     ; wait for DAV to go
    bpl ACPTR_3
    lda #PIA_LOW                    ; NDAC low
    sta PIA2_CRA
    pla
    rts

; The channels.

;; Gets a character without waiting: from the keyboard buffer, or 0 when it is empty, while the keyboard is the input
;; device; otherwise as <BASIN> reads it.
;;
;; Out: A = the character, or 0
GETIN:
    lda #$00
    sta STATUS
    lda DFLTN                       ; the keyboard?
    bne BASIN_1
    lda NDX                         ; none waiting
    beq BASIN_7
    sei
    jmp LP2

;; Reads a character from the input device: a line typed on the screen for the keyboard (<Editor1:LOOP5>), the screen
;; line the cursor is on for the screen, the next byte of a cassette buffer, reading the next block when it is used up,
;; or a byte from the IEEE-488 bus while the status is clear.
;;
;; A zero byte on tape ends a record: it sets $40 in the status and is passed over.
;;
;; Out: A = the character
;; Keeps: X
BASIN:
    lda DFLTN
    bne BASIN_1
    lda PNTR                        ; input starts at the cursor
    sta LXSP+1
    lda TBLX
    sta LXSP
    jmp LOOP5

BASIN_1:
    cmp #DEV_SCREEN                 ; the screen: read the cursor's line
    bne BASIN_2
    sta CRSW
    lda LNMX
    sta INDX
    jmp LOOP5

BASIN_2:
    bcs BASIN_6                     ; the bus
    stx XSAV

BASIN_3:
    jsr JTP20                       ; a cassette
    bne BASIN_4
    jsr RBLK                        ; the buffer is used up: read the next block
    ldy #$00
    tya
    ldx FA
    sta BUFPT,x
    jmp BASIN_3

BASIN_4:
    lda (TAPE1),y                   ; zero ends a record
    bne BASIN_5
    lda #$40
    jsr UDST
    bne BASIN_3

BASIN_5:
    ldx XSAV
    rts

BASIN_6:
    lda STATUS                      ; the bus, while the status is clear
    beq BASIN_8

BASIN_7:
    rts

BASIN_8:
    jmp ACPTR

;; Writes a character to the output device: the screen (<Editor1:PRT>), a cassette buffer (<BO21>) or the IEEE-488
;; bus (<CIOUT>). Output to the keyboard ends in BASIC's error (<TYPERR>).
;;
;; In: A = the character
;; Keeps: A, X, Y
BSOUT:
    pha
    lda DFLTO                       ; the keyboard can't be written
    bne BSOUT_1
    jmp TYPERR

BSOUT_1:
    cmp #DEV_SCREEN                 ; the screen
    bne BSOUT_2
    pla
    jmp PRT

BSOUT_2:
    bmi BSOUT_3                     ; a cassette, or the bus
    pla
    jmp CIOUT

BSOUT_3:
    pla

;; Puts a character in the current cassette's buffer, writing the buffer as a block when it is full and starting a new
;; one, which begins with <TAPE_DATA>. Line feed is not written. A cursor right counts in <RIGHTS>, and is not written
;; when the count wraps to zero, as the first one after <CHKOUT> does; any other is written.
;;
;; In: A = the character
;; Keeps: A, X, Y
BO21:
    sta KTEMP
    cmp #CHR_RIGHT                  ; counted; not written when the count wraps
    bne BO21_1
    inc RIGHTS
    beq BASIN_7

BO21_1:
    cmp #CHR_LF                     ; not written
    beq BASIN_7
    pha
    txa
    pha
    tya
    pha
    jsr JTP20                       ; the buffer full?
    bne BO21_2
    jsr WBLK                        ; write it
    ldx FA
    lda #$01
    sta BUFPT,x
    jsr BLNKBUF
    lda #TAPE_DATA                  ; and start the next block
    sta (TAPE1),y
    iny

BO21_2:
    lda KTEMP
    sta (TAPE1),y

;; Restores Y, X and A from the stack, as <BO21>, <CHKIN> and <CHKOUT> pushed them, and returns.
RSTOR:
    pla
    tay
    pla
    tax
    pla
    rts

;; Ends the files that are input and output: sends UNLISTEN or UNTALK to a device on the IEEE-488 bus, and makes the
;; keyboard and screen the input and output again.
;;
;; Entry: JX770 = only resets the devices
;; Uses: A
CLRCHN:
    lda DFLTO                       ; the output on the bus?
    beq CLRCHN_1
    cmp #DEV_SCREEN
    beq CLRCHN_1
    bmi CLRCHN_1
    jsr UNLSN                       ; send UNLISTEN

CLRCHN_1:
    lda DFLTN                       ; the input on the bus?
    beq JX770
    cmp #DEV_SCREEN
    beq JX770
    bmi JX770
    jsr UNTLK                       ; send UNTALK

JX770:
    lda #$00
    sta DFLTN
    lda #DEV_SCREEN
    sta DFLTO
    rts

;; Forgets every open file, without closing them, and goes back to the keyboard and screen (<CLRCHN>).
;;
;; Uses: A
CLALL:
    lda #$00
    sta LDTND
    beq CLRCHN

;; Finds a logical file in the file table.
;;
;; In: A = the file number
;; Out: X = its place in <LAT>, zero = set when it is open
JLTLK:
    ldx LDTND

JLTLK_1:
    dex
    bmi JZ100_1
    cmp LAT,x
    beq JZ100_1
    bne JLTLK_1

;; Makes a file of the file table the current one: copies its number, device and secondary address to <LA>, <FA> and
;; <SA>.
;;
;; In: X = its place in <LAT>
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

;; BASIC's CLOSE: finishes the file the statement names and takes it out of the file table.
;;
;; A cassette file being written gets its last block, and with secondary address 2 an end-of-tape header after it; a
;; device on the IEEE-488 bus is sent CLOSE (<CLSE1>). Closing a file that is not open does nothing.
CLOSE:
    jsr PARS2
    lda LA
    jsr JLTLK
    bne JX120_1
    jsr JZ100
    txa
    pha
    lda FA                          ; the keyboard or the screen: nothing to do
    beq JX150
    cmp #DEV_SCREEN
    beq JX150
    bcs JX120                       ; the bus
    lda SA                          ; a cassette being read: nothing to do
    beq JX150
    jsr ZZZ
    ldx #$02

CLOSE_1:
    lda CLOSTX,x
    jsr BO21
    dex
    bpl CLOSE_1
    jsr WBLK                        ; the last block
    lda SA                          ; then an end-of-tape header for 2
    cmp #$02
    bne JX150
    lda #TAPE_EOT
    jsr TAPEH
    jmp JX150

;; What <CLOSE> writes to a cassette file before its last block, from the end: a zero, a 1 and RETURN.
CLOSTX:
    .byte CHR_RETURN, '1', 0

JX120:
    jsr CLSE1

JX150:
    pla
    tax
    dec LDTND                       ; move the last file into its place
    cpx LDTND
    beq JX120_1
    ldy LDTND
    lda LAT,y
    sta LAT,x
    lda FAT,y
    sta FAT,x
    lda SAT,y
    sta SAT,x

JX120_1:
    rts

; The STOP key, LOAD, SAVE, VERIFY, OPEN and SYS.

;; Tests the STOP key, as the last keyboard scan left it in <STKEY>, emptying the keyboard buffer when it is down.
;;
;; Out: zero = set when STOP is down, carry = set then
;; Uses: A
STOP1:
    lda STKEY
    cmp #$EF
    bne STOP1_1
    php
    lda #$00
    sta NDX
    plp

STOP1_1:
    rts

;; Stops the program when the STOP key is down: tests it (<STOP1>) and goes to BASIC's <STOP>, which breaks or
;; returns.
CHKSTOP:
    jsr STOP1
    jmp STOP

;; Prints one of the kernal's messages (<Editor1:MSG>), but only in direct mode.
;;
;; In: Y = the message's offset in <MSG1>
;; Uses: A, Y
SPMSG:
    lda TXTPTR+1
    bne STOP1_1
    jmp MSG

;; BASIC's LOAD: loads a program from a cassette or the IEEE-488 bus to $0400, then starts BASIC on it.
;;
;; It takes the name, device and secondary address after the statement (<PARS1>), waits for STOP to be let go, and
;; from tape finds the program's header, by name when one is given, and reads it to the addresses the header gives.
;; In direct mode it prints what it does and READY., sets <VARTAB> to the program's end, and relinks the program
;; (<FINI>); in a program it goes on from the program's start with the variables kept (<FLOAD>). A read error gives
;; ?LOAD ERROR. The keyboard and the screen give ?SYNTAX ERROR.
;;
;; Entry: LD10 = for LOAD and VERIFY both, with VERCK set
LOAD:
    lda #$00
    sta VERCK

LD10:
    jsr PARS1
    lda #$FF                        ; wait for STOP to be let go

LOAD_1:
    cmp STKEY
    bne LOAD_1
    cmp STKEY
    bne LOAD_1
    lda #$04                        ; programs load at $0400
    sta STAL+1
    lda #$00
    sta STAL
    lda FA                          ; the keyboard or the screen: an error
    bne LOAD_3

LOAD_2:
    jmp SNERR

LOAD_3:
    cmp #DEV_SCREEN
    beq LOAD_2
    bcc LOAD_7                      ; a cassette
    jsr NEWSA                       ; the bus
    jsr LD300
    jsr OPENI
    jsr TALK
    jsr LD400

LOAD_4:
    jsr CHKSTOP                     ; each byte until there is no device
    jsr ACPTR
    ldx STATUS
    bmi LOAD_12
    ldy VERCK                       ; verifying?
    beq LOAD_5
    dey
    cmp (STAL),y
    beq LOAD_6
    ldx #$02                        ; a difference sets the status to $02
    stx STATUS
    bne LOAD_6

LOAD_5:
    sta (STAL),y

LOAD_6:
    inc STAL
    bne LOAD_4
    inc STAL+1
    jmp LOAD_4

LOAD_7:
    jsr ZZZ                         ; the tape: find the header
    jsr CSTE1
    jsr LD300

LOAD_8:
    lda FNLEN
    beq LOAD_10
    jsr FAF
    bne LOAD_11

LOAD_9:
    jmp OP160

LOAD_10:
    jsr FAH
    beq LOAD_9

LOAD_11:
    cpx #$01                        ; a program's header?
    bne LOAD_8
    jsr LDAD2                       ; load to its addresses
    jsr LD400
    jsr TRD

LOAD_12:
    lda VERCK                       ; a verify ends with its own message
    bne LD300_2
    jsr TWAIT
    lda STATUS                      ; a bad block?
    and #$10
    beq LOAD_13
    ldy #$00
    sty NDX
    ldy #MS10-MSG1+1
    jmp ERMSG

LOAD_13:
    ldy #MS19-MSG1                  ; READY.
    jsr SPMSG
    lda TXTPTR+1                    ; in a program, go on running it
    bne LOAD_14
    lda EAL+1                       ; the variables start past the program
    sta VARTAB+1
    lda EAL
    sta VARTAB
    jmp FINI

LOAD_14:
    jsr STXTPT
    jmp FLOAD

;; Prints SEARCHING, then FOR and the file name when there is one, in direct mode.
;;
;; Entry: LD105 = prints only the file name
;; Uses: A, Y
LD300:
    lda TXTPTR+1
    bne LD300_2
    ldy #MS5-MSG1
    jsr MSG
    lda FNLEN
    beq LD300_2
    ldy #MS6-MSG1
    jsr MSG

LD105:
    ldy FNLEN
    beq LD300_2
    ldy #$00

LD300_1:
    lda (FNADR),y
    jsr PRT
    iny
    cpy FNLEN
    bne LD300_1

LD300_2:
    rts

;; Prints LOADING, or VERIFYING while verifying, in direct mode.
;;
;; Uses: A, Y
LD400:
    ldy #MS10-MSG1
    lda VERCK
    beq LD400_1
    ldy #MS21-MSG1

LD400_1:
    jsr SPMSG
    ldy #MS5-MSG1+7
    jmp SPMSG

;; Takes the parameters of LOAD, SAVE and VERIFY after the statement: a file name, a device (1 if none) and a secondary
;; address (0 if none), each after a comma, stopping where the statement ends. It clears the status.
;;
;; Its store meant for <EAL>+1 stores the 1 in X instead of the 4 in A.
PARS1:
    ldx #$00                        ; no status, name or secondary address
    stx STATUS
    stx EAL
    stx FNLEN
    stx SA
    inx                             ; device 1, cassette 1
    stx FA
    lda #$04                        ; meant for EAL+1
    stx EAL+1
    jsr PR140                       ; a name
    jsr PR200
    jsr PR140                       ; a device
    jsr PR070
    stx FA
    jsr PR140                       ; a secondary address
    jsr PR070
    stx SA

PARS1_1:
    rts

;; Takes a comma and a byte after it (<GETBYT>), giving a ?SYNTAX ERROR for a comma at the statement's end.
;;
;; Out: X = the byte
PR070:
    jsr PR150
    jmp GETBYT

;; Opens a file on an IEEE-488 device: sends LISTEN, then OPEN with the secondary address, then the file name, and
;; UNLISTEN. Without a name or a secondary address it does nothing; without the device it is ?DEVICE NOT PRESENT.
;;
;; Uses: A, Y
OPENI:
    lda SA                          ; no secondary address
    bmi PARS1_1
    ldy FNLEN                       ; no name
    beq PARS1_1
    jsr LISTN
    lda SA                          ; OPEN with the secondary address
    ora #$40
    sta SA
    ora #IEEE_OPEN
    jsr SECND
    lda STATUS                      ; no device?
    bpl OP37_1

;; Gives the ?DEVICE NOT PRESENT error.
OP37:
    ldy #MS13-MSG1
    jmp ERMSG

OP37_1:
    lda FNLEN                       ; the name
    beq OP37_3
    ldy #$00

OP37_2:
    lda (FNADR),y
    jsr CIOUT
    iny
    cpy FNLEN
    bne OP37_2

OP37_3:
    jmp UNLSN

;; Reads headers from the tape until one has the file name at <FNADR> at the start of its name.
;;
;; Out: zero = set when the end-of-tape header came first, X = the header's kind
FAF:
    jsr FAH
    beq FAF_3
    ldy #5                          ; the name starts at byte 5
    sty HDRIDX
    ldy #$00
    sty KTEMP

FAF_1:
    cpy FNLEN                       ; all of the given name matched
    beq FAF_2
    lda (FNADR),y
    ldy HDRIDX
    cmp (TAPE1),y
    bne FAF
    inc KTEMP
    inc HDRIDX
    ldy KTEMP
    bne FAF_1

FAF_2:
    tya

FAF_3:
    rts

;; BASIC's VERIFY: compares a program on a cassette or the IEEE-488 bus with memory, as <LOAD> would read it, and prints
;; OK, or gives ?VERIFY ERROR.
VER:
    lda #$01                        ; verify
    sta VERCK
    jsr LD10
    lda STATUS                      ; a difference?
    and #$10
    beq VER_1
    ldy #MS21-MSG1+1
    jmp ERMSG

VER_1:
    ldy #MS18-MSG1                  ; OK
    jmp MSG

;; Takes the parameters of OPEN and CLOSE after the statement: the file number, then after commas a device (1 if none),
;; a secondary address (none for the bus or the screen and keyboard, 0 for a cassette) and a file name.
PARS2:
    ldx #$00
    stx SA
    stx STATUS
    stx FNLEN
    inx
    stx FA
    jsr PR130                       ; the file number
    jsr GETBYT
    stx LA
    jsr PR140
    jsr PR070                       ; the device
    stx FA
    cpx #DEV_SCREEN                 ; the bus, or the screen and keyboard?
    bcc PARS2_1
    dec SA                          ; no secondary address unless given

PARS2_1:
    jsr PR140
    jsr PR070                       ; the secondary address
    stx SA
    jsr PR140
    jsr PR150                       ; the name

;; Evaluates the file name's string, and makes it the current file name.
;;
;; Out: FNLEN = its length, FNADR = its address
PR200:
    jsr FRMEVL
    jsr FRESTR
    sta FNLEN
    lda INDEX
    sta FNADR
    lda INDEX+1
    sta FNADR+1
    rts

;; Returns from its caller's caller when the statement ends here, so that the parameters after are left as they are.
PR140:
    jsr CHRGOT                      ; the statement's end?
    bne PR140_1
    pla                             ; return from the caller
    pla

PR140_1:
    rts

;; Takes a comma, which must not end the statement.
;;
;; Entry: PR130 = only checks that the statement does not end here
PR150:
    lda #','
    jsr SYNCHR

PR130:
    jsr CHRGOT
    bne PR140_1
    jmp SNERR

;; BASIC's OPEN: puts a file in the file table, and opens it on its device.
;;
;; On the IEEE-488 bus it sends the name (<OPENI>). On a cassette, secondary address 0 opens a file to read: it waits
;; for PLAY and finds the file's header, by name when one is given; any other opens one to write, with a data file's
;; header written first. ?FILE OPEN is a number already open. With ten files open it does not give ?TOO MANY FILES:
;; the branch to it is taken only with zero clear, so it goes round its check for ever.
OPEN:
    jsr PARS2
    lda LA
    bne OPEN_1
    jmp SNERR

OPEN_1:
    jsr JLTLK                       ; already open?
    bne OPEN_3
    ldy #MS2-MSG1                   ; FILE OPEN

OPEN_2:
    bne ERMSG                       ; with zero set it falls through, and loops

OPEN_3:
    ldx LDTND
    ldy #MS1-MSG1
    sty STATUS
    cpx #MAX_FILES                  ; ten files open?
    beq OPEN_2
    inc LDTND                       ; add it to the table
    lda LA
    sta LAT,x
    lda SA
    sta SAT,x
    lda FA
    sta FAT,x
    beq OP175                       ; the keyboard or the screen: open
    cmp #DEV_SCREEN
    beq OP175
    bcc OPEN_4                      ; a cassette
    jmp OPENI                       ; the bus

OPEN_4:
    lda SA                          ; read or write?
    bne OP200
    jsr CSTE1                       ; read: find the header
    jsr LD300
    lda FNLEN
    beq OP170
    jsr FAF
    bne OP171

;; Gives the ?FILE NOT FOUND error.
OP160:
    ldy #MS4-MSG1

;; Gives a kernal error: prints RETURN, a question mark and the message, then ends through BASIC's <TYPERR>, which adds
;; " ERROR".
;;
;; In: Y = the message's offset in <MSG1>
ERMSG:
    lda #CHR_RETURN                 ; RETURN, ?, the message, " ERROR"
    jsr PRT
    lda #'?'
    jsr PRT
    jsr MSG
    jmp TYPERR

;; The rest of <OPEN>.
OP170:
    jsr FAH
    beq OP160
    bne OP171

OP200:
    jsr CSTE2                       ; write: a data file's header first
    lda #TAPE_FILE
    jsr TAPEH

OP171:
    ldx FA
    lda #TAPE_BUFFER_SIZE-1         ; read: the buffer is used up
    ldy SA
    beq OP170_1
    jsr BLNKBUF                     ; write: a new block
    lda #TAPE_DATA
    sta (TAPE1),y
    tya

OP170_1:
    sta BUFPT,x                     ; the buffer's next byte

OP175:
    rts

;; Reads blocks from the tape until a header: a program's, a data file's or the end of the tape, and in direct mode
;; prints FOUND and the name of the first two.
;;
;; Out: zero = set at the end of the tape, X = the header's kind
;; Keeps: VERCK
FAH:
    lda VERCK
    pha

FAH_1:
    jsr RBLK                        ; read blocks until a header
    ldy #$00
    lda (TAPE1),y
    cmp #TAPE_EOT                   ; the end of the tape
    beq FAH_5
    cmp #TAPE_PROGRAM               ; a program
    beq FAH_2
    cmp #TAPE_FILE                  ; a data file
    bne FAH_1

FAH_2:
    tax
    lda TXTPTR+1
    bne FAH_4
    ldy #MS17-MSG1                  ; FOUND and the name
    jsr MSG
    ldy #5

FAH_3:
    lda (TAPE1),y
    jsr PRT
    iny
    cpy #21
    bne FAH_3

FAH_4:
    ldy #$01

FAH_5:
    pla                             ; zero at the end of the tape
    sta VERCK
    tya
    rts

;; Fills bytes 1-191 of the current cassette buffer with spaces.
;;
;; Out: Y = 0
;; Uses: A
BLNKBUF:
    ldy #TAPE_BUFFER_SIZE-1
    lda #' '

BLNKBUF_1:
    sta (TAPE1),y
    dey
    bne BLNKBUF_1
    rts

;; Writes a header to the current cassette: its kind, the addresses at <STAL> and <EAL>, and the file name, with a long
;; leader before it.
;;
;; In: A = the header's kind
;; Keeps: STAL, EAL
TAPEH:
    sta KTEMP
    lda STAL+1
    pha
    lda STAL
    pha
    lda EAL+1
    pha
    lda EAL
    pha
    jsr BLNKBUF
    lda KTEMP                       ; the kind
    sta (TAPE1),y
    iny
    lda STAL                        ; the start
    sta (TAPE1),y
    iny
    lda STAL+1
    sta (TAPE1),y
    iny
    lda EAL                         ; the end
    sta (TAPE1),y
    iny
    lda EAL+1
    sta (TAPE1),y
    iny
    sty HDRIDX                      ; then the name
    ldy #$00
    sty KTEMP

TAPEH_1:
    ldy KTEMP
    cpy FNLEN
    beq TAPEH_2
    lda (FNADR),y
    ldy HDRIDX
    sta (TAPE1),y
    inc KTEMP
    inc HDRIDX
    bne TAPEH_1

TAPEH_2:
    jsr LDAD1                       ; write the buffer
    jsr TWAIT
    lda #DIRECT_LEADER              ; after a long leader
    sta CHKSUM
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

;; Takes the start and end addresses from the header just read, into <SAL>, <EAL> and <STAL>.
;;
;; Uses: A, X, Y
LDAD2:
    jsr TWAIT
    ldx #$00
    ldy #$01

LDAD2_1:
    lda (TAPE1),y                   ; bytes 1-4: the start and end
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

;; Points <TAPE1> at the buffer for the cassette in <FA>.
;;
;; Uses: A
ZZZ:
    lda #<TBUFFR1                   ; cassette 1's buffer
    sta TAPE1
    lda #>TBUFFR1
    sta TAPE1+1
    lda FA
    lsr a
    bcs ZZZ_1
    lda #<TBUFFR2                   ; or cassette 2's
    sta TAPE1
    lda #>TBUFFR2
    sta TAPE1+1

ZZZ_1:
    rts

;; Makes the current cassette buffer what is read or written: points <STAL> at it and <EAL> just past it, once the
;; tape is idle.
;;
;; Uses: A
LDAD1:
    jsr TWAIT
    jsr ZZZ
    lda TAPE1                       ; the buffer, and its end
    sta STAL
    clc
    adc #TAPE_BUFFER_SIZE
    sta EAL
    lda TAPE1+1
    sta STAL+1
    adc #$00
    sta EAL+1
    rts

;; BASIC's SYS: evaluates the address and jumps to it.
SYS:
    jsr FRMNUM
    jsr GETADR
    jmp (LINNUM)

;; BASIC's SAVE: saves the program, from $0400 to <VARTAB>, to a cassette or the IEEE-488 bus.
;;
;; To tape it writes a program's header and the program, and after them an end-of-tape header when the secondary address
;; is 2 or more. The keyboard and the screen give ?DEVICE NOT PRESENT.
SAVE:
    jsr PARS1
    lda VARTAB                      ; the program's end
    sta EAL
    lda VARTAB+1
    sta EAL+1
    lda #$04                        ; and its start, $0400
    sta STAL+1
    lda #$00
    sta STAL
    lda FA                          ; the keyboard or the screen?
    bne SAVE_2

SAVE_1:
    ldy #MS13-MSG1
    jmp ERMSG

SAVE_2:
    cmp #DEV_SCREEN
    beq SAVE_1
    bcc SV100                       ; a cassette
    jsr NEWSA                       ; the bus
    jsr OPENI
    jsr LISTN
    ldy #$00
    jsr RD300

SAVE_3:
    jsr WRT62                       ; each byte to the end
    beq SAVE_4
    lda (SAL),y
    jsr CIOUT
    jsr CHKSTOP
    inc SAL
    bne SAVE_3
    inc SAL+1
    bne SAVE_3

SAVE_4:
    jsr UNLSN

;; Sends CLOSE for the secondary address to the IEEE-488 device, when there is a secondary address.
;;
;; Uses: A
CLSE1:
    bit SA
    bmi NEWSA_3                     ; no secondary address
    jsr LISTN
    lda SA                          ; CLOSE with it
    and #$EF
    ora #IEEE_CLOSE
    jmp SECND

;; The rest of <SAVE>, for a cassette.
SV100:
    jsr ZZZ
    jsr CSTE2
    lda TXTPTR+1                    ; in direct mode
    bne SV100_1
    ldy #MS11-MSG1
    jsr MSG
    jsr LD105

SV100_1:
    lda #TAPE_PROGRAM               ; a program's header
    jsr TAPEH
    jsr TWRT                        ; and the program
    ldx SA                          ; an end-of-tape header for 2 and up
    beq NEWSA_3
    dex
    beq NEWSA_3
    lda #TAPE_EOT
    jmp TAPEH

;; Picks a secondary address no open file uses, from 1 up.
;;
;; Out: SA = the address
;; Uses: A, X
NEWSA:
    ldx #$00
    stx SA

NEWSA_1:
    ldx #$00
    inc SA                          ; try the next

NEWSA_2:
    cpx LDTND                       ; is any file using it?
    beq UDTIM_7
    lda SAT,x
    and #$1F
    cmp SA
    beq NEWSA_1
    inx
    bne NEWSA_2

NEWSA_3:
    rts

;; Counts a jiffy: adds one to the clock in <TIME>, but for one tick in about 623 (<TIMADJ>), wraps it to zero at 24
;; hours, and reads the STOP key's row into <STKEY>.
;;
;; Uses: A, X
UDTIM:
    lda TIMADJ                      ; carry from the caller
    adc #$01
    sta TIMADJ
    bcc UDTIM_1
    inc TIMADJ+1

UDTIM_1:
    cmp #<623                       ; the 623rd?
    bne UDTIM_2
    lda TIMADJ+1
    cmp #>623
    beq UDTIM_6

UDTIM_2:
    inc TIME+2                      ; tick
    bne UDTIM_3
    inc TIME+1
    bne UDTIM_3
    inc TIME

UDTIM_3:
    ldx #$00

UDTIM_4:
    lda TIME,x                      ; 24 hours?
    cmp UD70,x
    bcc UD60
    inx
    cpx #$03
    bne UDTIM_4
    lda #$00                        ; back to zero

UDTIM_5:
    sta TIME-1,x
    dex
    bne UDTIM_5
    beq UD60

UDTIM_6:
    lda #$00                        ; a tick missed, and start counting again
    sta TIMADJ
    sta TIMADJ+1

UD60:
    lda PIA1_PB                     ; read the row until it holds still
    cmp PIA1_PB
    bne UD60
    sta STKEY

UDTIM_7:
    rts

;; The jiffy clock at 24 hours, 5,184,000 sixtieths, plus one, high byte first.
UD70:
    .byte $4F, $1A, $01

;; Makes a logical file the input: on the IEEE-488 bus it sends TALK and the secondary address. ?FILE NOT OPEN is a
;; number not open, and ?NOT INPUT FILE a cassette file being written.
;;
;; In: X = the file number
;; Keeps: A, X, Y
;; Entry: JX300 = gives ?FILE NOT OPEN, JX305 = gives the error at Y, for CHKIN and CHKOUT
CHKIN:
    pha
    txa
    pha
    tya
    pha
    lda #$00                        ; no status
    sta STATUS
    txa
    jsr JLTLK
    beq CHKIN_1

JX300:
    ldy #MS3-MSG1

JX305:
    jmp ERMSG

CHKIN_1:
    jsr JZ100
    lda FA                          ; the keyboard or the screen
    beq CHKIN_2
    cmp #DEV_SCREEN
    beq CHKIN_2
    bcs CHKIN_3                     ; the bus
    ldx SA                          ; a cassette being written?
    beq CHKIN_2
    ldy #MS15-MSG1
    bne JX305

CHKIN_2:
    sta DFLTN
    jmp RSTOR

CHKIN_3:
    pha
    jsr TALK
    lda SA                          ; a secondary address?
    bpl CHKIN_4
    jsr TKATN                       ; none: only turn the bus round
    jmp CHKIN_5

CHKIN_4:
    and #$1F                        ; as a TALK secondary address
    ora #IEEE_SECOND
    jsr TKSA

CHKIN_5:
    lda STATUS                      ; no device?
    bpl CHKIN_6
    jmp OP37

CHKIN_6:
    pla
    jmp CHKIN_2

;; Makes a logical file the output: on the IEEE-488 bus it sends LISTEN and the secondary address. ?FILE NOT OPEN is a
;; number not open or the keyboard, and ?NOT OUTPUT FILE a cassette file being read.
;;
;; In: X = the file number
;; Keeps: A, X, Y
CHKOUT:
    pha
    txa
    pha
    tya
    pha
    lda #$00
    sta STATUS
    lda #$FF                        ; no cursor-rights yet
    sta RIGHTS
    txa
    jsr JLTLK
    bne JX300
    jsr JZ100
    lda FA                          ; the keyboard
    beq JX300
    cmp #DEV_SCREEN                 ; the screen
    beq CHKOUT_1
    bpl CHKOUT_2                    ; the bus
    ldx SA                          ; a cassette being read?
    bne CHKOUT_1
    ldy #MS16-MSG1
    bne JX305

CHKOUT_1:
    sta DFLTO
    jmp RSTOR

CHKOUT_2:
    pha
    jsr LISTN
    lda SA                          ; a secondary address?
    bpl CHKOUT_3
    jsr SCATN
    jmp CHKOUT_4

CHKOUT_3:
    and #$1F
    ora #IEEE_SECOND
    jsr SECND

CHKOUT_4:
    lda STATUS                      ; no device?
    bpl CHKOUT_5
    jmp OP37

CHKOUT_5:
    pla
    jmp CHKOUT_1

;; Moves to the next byte of the current cassette's buffer.
;;
;; Out: Y = its offset, zero = set when the buffer is used up
;; Uses: A, X
JTP20:
    jsr ZZZ
    ldx FA
    inc BUFPT,x
    ldy BUFPT,x
    cpy #TAPE_BUFFER_SIZE           ; used up at 192
    rts

; The cassettes.

;; Waits for the current cassette's PLAY key: when it is not down, prints PRESS PLAY ON TAPE # and the cassette's
;; number, waits for it, checking STOP, and prints OK.
;;
;; Entry: CS30 = prints the message at Y, then ON TAPE # and waits
;; Uses: A, X, Y
CSTE1:
    jsr CS10                        ; PLAY already down?
    beq CS10_2
    ldy #MS7-MSG1

CS30:
    jsr MSG
    ldy #MS9-MSG1
    jsr MSG
    lda FA                          ; the cassette's number
    ora #'0'
    jsr PRT

CSTE1_1:
    jsr CHKSTOP                     ; wait for it
    jsr CS10
    bne CSTE1_1
    ldy #MS18-MSG1
    jmp MSG

;; Tests the current cassette's PLAY key.
;;
;; Out: zero = set while it is down
CS10:
    lda #PIA1A_SENSE1               ; cassette 1's keys
    ldx FA
    cpx #$01
    beq CS10_1
    lda #PIA1A_SENSE2               ; or cassette 2's

CS10_1:
    bit PIA1_PA
    bne CS10_2
    bit PIA1_PA

CS10_2:
    rts

;; Waits for the current cassette's keys before writing: as <CSTE1>, asking for PLAY & RECORD.
;;
;; Uses: A, X, Y
CSTE2:
    jsr CS10
    beq CS10_2
    ldy #MS7-MSG1
    jsr MSG
    ldy #MS8-MSG1
    bne CS30

;; Reads a block from the current cassette into its buffer, clearing the status and the verify flag first.
;;
;; Entry: TRD = reads to the addresses at <STAL> and <EAL>
RBLK:
    lda #$00                        ; no status, no verify
    sta STATUS
    sta VERCK
    jsr LDAD1

TRD:
    jsr TWAIT
    jsr CSTE1
    sei
    lda #$00                        ; start the read afresh
    sta RDSTATE
    sta RDBYTE
    sta CMP0
    sta PTR1
    sta PTR2
    sta MARKER
    ldx #IRQ_READ                   ; the read's interrupt
    jsr BSIV
    ldx FA
    dex
    beq RBLK_1
    lda #$90                        ; cassette 2: the VIA's CB1
    sta VIA_IER
    bne TAPE

RBLK_1:
    inc PIA1_CRA                    ; cassette 1: PIA 1's CA1
    bne TAPE

;; Writes the current cassette's buffer as a block, with the short leader of data.
;;
;; Entry: TWRT = writes from <STAL> to <EAL>, TWRT2 = with the leader count already in <CHKSUM>
WBLK:
    jsr LDAD1

TWRT:
    jsr TWAIT
    lda #DATA_LEADER                ; a short leader
    sta CHKSUM

TWRT2:
    jsr CSTE2
    sei
    lda #$A0                        ; timer 2's interrupt
    sta VIA_IER
    ldx #IRQ_LEADER                 ; the leader first
    jsr BSIV

;; Runs the cassette for a read or write the tape interrupts do: two copies of the block, the retrace interrupt off,
;; the motor on and held (<CAS1>, <CAS2>), and timer 2 started; then waits for the interrupts to finish, counting the
;; jiffy clock from the retrace by hand and checking STOP.
TAPE:
    lda #$02                        ; two copies
    sta BLKCNT
    jsr NEWCH
    dec PIA1_CRB                    ; the retrace interrupt off
    ldx FA
    dex
    bne TAPE_1
    lda #PIA_LOW                    ; cassette 1's motor on, and held
    sta PIA1_CRB
    sta CAS1
    bne TAPE_2

TAPE_1:
    lda VIA_ORB                     ; cassette 2's
    stx CAS2
    and #$FF-VIAB_MOTOR2
    sta VIA_ORB

TAPE_2:
    sta VIA_T2CH                    ; start timer 2
    cli

TAPE_3:
    lda #>KEY                       ; until the interrupts are done
    cmp CINV+1
    beq TAPE_4
    jsr TSTOP
    bit PIA1_CRB                    ; a retrace?
    bpl TAPE_3
    bit PIA1_PB                     ; clear it, and count the clock
    jsr UDTIM
    jmp TAPE_3

TAPE_4:
    rts

;; Waits for a tape read or write to finish, when <CINV> is back at the editor's <Editor1:KEY>, checking STOP.
;;
;; Uses: A
TWAIT:
    jsr TSTOP
    lda #>KEY
    cmp CINV+1
    bne TWAIT
    rts

;; Checks STOP during tape work: when it is down, stops the tape (<TNIF>) and goes back to the keyboard and screen,
;; then BASIC breaks (<STOP>); otherwise it returns.
TSTOP:
    jsr STOP1
    bne TSTOP_1                     ; STOP?
    php
    jsr TNIF                        ; stop the tape
    jsr JX770                       ; the keyboard and the screen again
    plp

TSTOP_1:
    jmp STOP

;; Sets timer 1 to time out a pulse: to timer 2's count now, plus four times the sum of X and five times <CMP0>, and
;; enables interrupts.
;;
;; In: X = the base length
;; Uses: A, X
STT1:
    stx TIMTMP                      ; X plus five times CMP0
    lda CMP0
    asl a
    asl a
    clc
    adc CMP0
    clc
    adc TIMTMP
    sta TIMTMP
    lda #$00
    bit CMP0
    bmi STT1_1
    rol a

STT1_1:
    asl TIMTMP
    rol a
    asl TIMTMP
    rol a
    tax

STT1_2:
    lda VIA_T2CL                    ; wait for timer 2 to be clear of zero
    cmp #$15
    bcc STT1_2
    adc TIMTMP
    sta VIA_T1CL
    txa
    adc VIA_T2CH
    sta VIA_T1CH
    cli
    rts

;; The tape read's interrupt, at each pulse: measures the pulse with timer 2, sorts it as short, medium or long against
;; lengths set by <CMP0>, and builds bits, then bytes, from the pulse pairs.
;;
;; A long and a medium pulse mark each byte; a parity error, a pulse of the wrong length, or timer 1 timing out marks
;; it bad (<BYTERR>). It finds the countdown of sync bytes before each copy of a block, then stores each byte, or in a
;; verify compares it. A bad byte in the first copy is logged in <BADLOG>, and the second copy stores only the logged
;; bytes; more than 31 bad, or one bad in both copies, sets $10 in the status. At the end of the second copy it checks
;; the checksum ($20 in the status), stops the tape and puts <Editor1:KEY> back. The drift of the pulses moves <CMP0>
;; to follow the tape's speed.
READ:
    ldx VIA_T2CH                    ; timer 2's count since the last pulse
    ldy #$FF
    tya
    sbc VIA_T2CL
    cpx VIA_T2CH
    bne READ
    stx TIMTMP
    tax
    sty VIA_T2CL                    ; restart it
    sty VIA_T2CH
    tya
    sbc TIMTMP
    stx TIMTMP
    lsr a                           ; a quarter of the length
    ror TIMTMP
    lsr a
    ror TIMTMP
    lda CMP0                        ; shorter than CMP0 + $3C: noise
    clc
    adc #$3C
    bit VIA_ORB
    bit PIA1_PA
    cmp TIMTMP
    bcs READ_9
    ldx MARKER                      ; just after a marker: a byte is done
    beq READ_1
    jmp READ_22

READ_1:
    ldx BITCNT                      ; past the parity bit?
    bmi READ_2
    ldx #$00
    adc #$30                        ; short?
    adc CMP0
    cmp TIMTMP
    bcs READ_5
    inx
    adc #$26                        ; medium?
    adc CMP0
    cmp TIMTMP
    bcs READ_7
    adc #$2C                        ; long?
    adc CMP0
    cmp TIMTMP
    bcc READ_3

READ_2:
    jmp READ_16                     ; a marker

READ_3:
    nop

READ_4:
    lda RDBYTE
    beq READ_9
    sta TMARK1
    bne READ_9

READ_5:
    inc TMARK2                      ; a short
    bcs READ_8

READ_6:
    nop

READ_7:
    dec TMARK2                      ; a medium

READ_8:
    sec                             ; how far it was from the expected length
    sbc #$13
    sbc TIMTMP
    adc TDRIFT
    sta TDRIFT
    lda PHASE                       ; the second pulse of a bit?
    eor #$01
    sta PHASE
    beq READ_12
    stx DATAX                       ; the first: keep its kind

READ_9:
    lda RDBYTE
    beq READ_11
    bit VIA_IFR                     ; timer 1 timed the byte out?
    bvc READ_11
    lda #$00
    sta PHASE
    lda BITCNT
    bpl READ_15
    bmi READ_2

READ_10:
    ldx #$A6
    jsr STT1
    lda PRTY
    bne READ_4

READ_11:
    jmp PREND

READ_12:
    lda TDRIFT                      ; move CMP0 by the drift
    beq READ_14
    bmi READ_13
    dec CMP0
    dec CMP0

READ_13:
    inc CMP0

READ_14:
    lda #$00
    sta TDRIFT
    cpx DATAX                       ; the two pulses the same?
    bne READ_15
    txa
    bne READ_4
    lda TMARK2                      ; shorts run on: a leader
    bmi READ_9
    cmp #$10
    bcc READ_9
    sta LDRCNT
    bcs READ_9

READ_15:
    txa                             ; the bit into the parity
    eor PRTY
    sta PRTY
    lda RDBYTE
    beq READ_11
    dec BITCNT
    bmi READ_10
    lsr DATAX                       ; and into the byte
    ror RDBITS
    ldx #$DA
    jsr STT1
    jmp PREND

READ_16:
    lda LDRCNT                      ; a long pulse: a marker
    beq READ_17
    lda RDBYTE
    beq READ_18

READ_17:
    lda BITCNT
    bmi READ_18
    jmp READ_6

READ_18:
    lsr TIMTMP                      ; time the marker's medium pulse
    lda #$93
    sec
    sbc TIMTMP
    adc CMP0
    asl a
    tax
    jsr STT1
    inc MARKER                      ; the byte is done
    lda RDBYTE
    bne READ_19
    lda LDRCNT                      ; the first marker after a leader
    beq READ_21
    sta TMARK1
    lda #$00
    sta LDRCNT
    lda #$C0                        ; timer 1 times the bytes
    sta VIA_IER
    sta RDBYTE

READ_19:
    lda LDRCNT                      ; a leader came before
    sta NEWBLK
    beq READ_20
    lda #$00
    sta RDBYTE
    lda #$40
    sta VIA_IER

READ_20:
    lda RDBITS                      ; the byte
    sta TBYTE
    lda TMARK1                      ; bad if its pulses were
    ora TMARK2
    sta BYTERR

READ_21:
    jmp PREND

READ_22:
    jsr NEWCH                       ; a byte: ready for the next
    sta MARKER
    ldx #$DA
    jsr STT1
    lda BLKCNT                      ; the copy
    beq READ_23
    sta TCOUNT

READ_23:
    lda #$0F
    bit RDSTATE                     ; looking for the sync bytes?
    bpl READ_26
    lda NEWBLK                      ; a leader: the block begins
    bne READ_24
    ldx BLKCNT
    dex
    bne READ_25
    lda #$08                        ; a byte with no leader in the second copy: a long block
    jsr UDST
    bne READ_25

READ_24:
    lda #$00
    sta RDSTATE

READ_25:
    jmp PREND

READ_26:
    bvs READ_30                     ; in the data
    bne READ_28
    lda NEWBLK
    bne READ_25
    lda BYTERR
    bne READ_25
    lda TCOUNT                      ; the sync count expected
    lsr a
    lda TBYTE
    bmi READ_27
    bcc READ_29
    clc

READ_27:
    bcs READ_29
    and #$0F                        ; the countdown starts
    sta RDSTATE

READ_28:
    dec RDSTATE                     ; the countdown's next
    bne READ_25
    lda #$40                        ; the data next
    sta RDSTATE
    jsr RD300
    lda #$00
    sta CHKSUM
    beq READ_25

READ_29:
    lda #$80                        ; look for sync again
    sta RDSTATE
    bne READ_25

READ_30:
    lda NEWBLK                      ; a leader in the data: the block is short
    beq READ_31
    lda #$04
    jsr UDST
    lda #$00
    jmp READ_40

READ_31:
    jsr WRT62                       ; past the end?
    bne READ_32
    jmp READ_39

READ_32:
    ldx TCOUNT                      ; the first copy or the second?
    dex
    beq READ_34
    lda VERCK                       ; verifying?
    beq READ_33
    ldy #$00
    lda TBYTE
    cmp (SAL),y
    beq READ_33
    lda #$01
    sta BYTERR

READ_33:
    lda BYTERR                      ; a bad byte in the first copy
    beq READ_37
    ldx #$3D                        ; the log full?
    cpx PTR1
    bcc READ_36
    ldx PTR1                        ; log its address
    lda SAL+1
    sta BADLOG+1,x
    lda SAL
    sta BADLOG,x
    inx
    inx
    stx PTR1
    jmp READ_37

READ_34:
    ldx PTR2                        ; the second copy: is this byte logged?
    cpx PTR1
    beq READ_38
    lda SAL
    cmp BADLOG,x
    bne READ_38
    lda SAL+1
    cmp BADLOG+1,x
    bne READ_38
    inc PTR2                        ; yes: the next logged byte
    inc PTR2
    lda VERCK
    beq READ_35
    lda TBYTE
    ldy #$00
    cmp (SAL),y
    beq READ_38
    lda #$01
    sta BYTERR

READ_35:
    lda BYTERR                      ; bad again
    beq READ_37

READ_36:
    lda #$10                        ; a read error
    jsr UDST
    bne READ_38

READ_37:
    lda VERCK                       ; store it, unless verifying
    bne READ_38
    lda TBYTE
    ldy #$00
    sta (SAL),y

READ_38:
    inc SAL                         ; the next address
    bne READ_43
    inc SAL+1
    bne READ_43

READ_39:
    lda #$80                        ; the block is done: look for sync

READ_40:
    sta RDSTATE
    ldx BLKCNT
    dex
    bmi READ_41
    stx BLKCNT

READ_41:
    dec TCOUNT                      ; the second copy done?
    beq READ_42
    lda PTR1                        ; none bad: no need of it
    bne READ_43
    sta BLKCNT
    beq READ_43

READ_42:
    jsr TNIF                        ; stop the tape
    jsr RD300                       ; check the checksum
    ldy #$00
    sty CHKSUM
    jsr VPRTY
    lda CHKSUM
    eor TBYTE
    beq READ_43
    lda #$20
    jsr UDST

READ_43:
    jmp PREND

;; Points <SAL> at the start, <STAL>.
;;
;; Uses: A
RD300:
    lda STAL+1
    sta SAL+1
    lda STAL
    sta SAL
    rts

;; Sets bits in the I/O status.
;;
;; In: A = the bits
;; Out: A = the status
UDST:
    ora STATUS
    sta STATUS
    rts

;; Readies the tape routines for a new byte: eight bits to go, the first pulse of a bit, and the parity and marker flags
;; cleared.
;;
;; Uses: A
NEWCH:
    lda #$08
    sta BITCNT
    lda #$00
    sta PHASE
    sta TMARK1
    sta PRTY
    sta TMARK2
    rts

;; Writes the next pulse of a bit: short for a zero in bit 0 of <TBYTE>, medium for a one.
;;
;; Entry: WRTW = a medium pulse, WRT1 = a pulse of A's length, WRTX = one of A and X's length, X the high byte
;; Out: zero = set when the write line went low
WRITE:
    lda TBYTE                       ; bit 0
    lsr a
    lda #$60                        ; short
    bcc WRT1

WRTW:
    lda #$B0                        ; medium

WRT1:
    ldx #$00

WRTX:
    sta VIA_T2CL                    ; timer 2 times the pulse
    stx VIA_T2CH
    lda VIA_ORB                     ; toggle the write line
    eor #VIAB_WRITE
    sta VIA_ORB
    and #VIAB_WRITE
    rts

;; Marks the end of the block's data in the tape write, with bit 7 of <SAL>+1, and goes on to its end.
WRTL3:
    sec
    ror SAL+1                       ; the end of the data
    bmi WRT3

;; The tape write's interrupt for a block's bytes, at each timer 2 timeout: writes each byte's long and medium marker,
;; its eight bits and parity, first a countdown of sync bytes, then the bytes from <SAL> to <EAL>, then the checksum;
;; then the block's end and the gap after it, through <WRTZ>.
WRTN:
    lda TMARK1                      ; the long marker written?
    bne WRTN_1
    lda #$10                        ; a long marker pulse
    ldx #$01
    jsr WRTX
    bne WRT3
    inc TMARK1
    lda SAL+1
    bpl WRT3
    jmp WRTN_10

WRTN_1:
    lda TMARK2                      ; the medium marker written?
    bne WRTN_2
    jsr WRTW                        ; a medium
    bne WRT3
    inc TMARK2
    bne WRT3

WRTN_2:
    jsr WRITE                       ; a bit's pulse
    bne WRT3
    lda PHASE                       ; the second pulse of a bit?
    eor #$01
    sta PHASE
    beq WRTN_3
    lda TBYTE                       ; the second is the other length
    eor #$01
    sta TBYTE
    and #$01                        ; into the parity
    eor PRTY
    sta PRTY

WRT3:
    jmp PREND

WRTN_3:
    lsr TBYTE                       ; the next bit
    dec BITCNT
    lda BITCNT
    beq WRTN_8
    bpl WRT3

WRTN_4:
    jsr NEWCH                       ; the byte is done
    cli
    lda BUFPT                       ; sync bytes to go?
    beq WRTN_6
    ldx #$00                        ; the checksum starts
    stx DATAX
    dec BUFPT
    ldx BLKCNT                      ; $89-$81 before the first copy, $09-$01 before the second
    cpx #$02
    bne WRTN_5
    ora #$80

WRTN_5:
    sta TBYTE
    bne WRT3

WRTN_6:
    jsr WRT62                       ; the data
    bcc WRTN_7
    bne WRTL3
    inc SAL+1                       ; the end: the checksum
    lda DATAX
    sta TBYTE
    bcs WRT3

WRTN_7:
    ldy #$00                        ; a byte of data
    lda (SAL),y
    sta TBYTE
    eor DATAX
    sta DATAX
    inc SAL
    bne WRT3
    inc SAL+1
    bne WRT3

WRTN_8:
    lda PRTY                        ; odd parity
    eor #$01
    sta TBYTE

WRTN_9:
    jmp PREND

WRTN_10:
    dec BLKCNT                      ; the copies done?
    bne WRTN_11
    jsr TNOF                        ; stop the motors

WRTN_11:
    lda #$50                        ; a leader's pulses
    sta TCOUNT
    ldx #IRQ_LEADER                 ; for the gap after the block
    sei
    jsr BSIV
    bne WRTN_9

;; The tape write's interrupt for a leader: writes short pulses, <TCOUNT> of them for each count of <CHKSUM>, then hands
;; over to <WRTN> for the block's bytes; after the last copy it stops the tape (<STKY>).
WRTZ:
    lda #$78                        ; a short pulse
    jsr WRT1
    bne WRTN_9
    dec TCOUNT                      ; a count of pulses?
    bne WRTN_9
    jsr NEWCH                       ; a count of the leader
    dec CHKSUM
    bpl WRTN_9
    ldx #IRQ_WRITE                  ; the leader done: the bytes
    jsr BSIV
    cli
    inc CHKSUM                      ; the checksum starts at zero
    lda BLKCNT                      ; the last copy done?
    beq STKY
    jsr RD300                       ; from the start again
    ldx #9                          ; nine sync bytes
    stx BUFPT
    jmp WRTN_4

;; Stops the tape: both motors off, the VIA's interrupts off, PIA 1's cassette interrupt off and its retrace interrupt
;; on, and <CINV> back at the editor's <Editor1:KEY>.
;;
;; Keeps: interrupt
TNIF:
    php
    sei
    jsr TNOF
    lda #$7F                        ; the VIA's interrupts off
    sta VIA_IER
    lda #PIA_HIGH                   ; the cassette 1 interrupt off
    sta PIA1_CRA
    lda #PIA_HIGH_IRQ               ; the retrace interrupt on
    sta PIA1_CRB
    ldx #IRQ_NORMAL                 ; the editor's interrupt again
    jsr BSIV
    plp
    rts

;; Ends the tape write: stops the tape, and returns from the interrupt.
STKY:
    jsr TNIF
    beq WRTN_9

;; Points <CINV> at one of the interrupt handlers in <BSIT>.
;;
;; In: X = its offset in the table
;; Uses: A
BSIV:
    lda BSIT,x
    sta CINV
    lda BSIT+1,x
    sta CINV+1
    rts

;; The interrupt handlers <BSIV> puts in <CINV>, by the offsets <IRQ_TIMETEST> to <IRQ_READ>.
BSIT:
    .word BSYI1                       ; IRQ_TIMETEST
    .word BCI1                        ; IRQ_TEST1
    .word 0                           ; unused
    .word BCI2                        ; IRQ_TEST2
    .word WRTZ                        ; IRQ_LEADER
    .word WRTN                        ; IRQ_WRITE
    .word KEY                         ; IRQ_NORMAL
    .word READ                        ; IRQ_READ

; The reset, and the factory test.

;; The reset: starts the hardware and the editor (<Editor1:CINT>), then BASIC's cold start (<INIT>), or the factory
;; test (<DIAG>) when the diagnostic jumper holds PIA 1's PA7 low.
START:
    ldx #$FF
    txs
    cld
    jsr CINT
    lda PIA1_PA                     ; the diagnostic jumper?
    bpl DIAG
    cli                             ; no: BASIC
    jmp INIT

;; The factory test's RAM check: fills $0003 up to page X with a pattern from each byte's place and <DIAG_PATTERN>,
;; then checks it, stopping in a loop on a byte that differs. It runs twice (<RAMPASS>).
;;
;; In: X = the page past the RAM, Y = 0
RAMTEST:
    sty DIAG_PTR
    sty DIAG_PTR+1
    ldy #$03

RAMTEST_1:
    tya                             ; fill the pages with the pattern
    clc
    adc DIAG_PTR+1
    eor DIAG_PATTERN
    sta (DIAG_PTR),y
    iny
    bne RAMTEST_1
    inc DIAG_PTR+1
    cpx DIAG_PTR+1
    bne RAMTEST_1
    sty DIAG_PTR
    sty DIAG_PTR+1
    ldy #$03

RAMTEST_2:
    tya                             ; check them
    clc
    adc DIAG_PTR+1
    eor DIAG_PATTERN
    cmp (DIAG_PTR),y

RAMTEST_3:
    bne RAMTEST_3                   ; a byte differs: stop here
    iny
    bne RAMTEST_2
    inc DIAG_PTR+1
    cpx DIAG_PTR+1
    bne RAMTEST_2
    jmp RAMPASS

; Unused: a BRK that nothing reaches.
    .byte 0

;; Adds the bytes from <SAL> to <EAL> into the checksum: exclusive-ORs each into <CHKSUM>.
;;
;; In: Y = 0
;; Out: SAL = EAL
;; Uses: A
VPRTY:
    lda (SAL),y
    eor CHKSUM
    sta CHKSUM
    inc SAL
    bne VPRTY_1
    inc SAL+1

VPRTY_1:
    jsr WRT62
    bne VPRTY
    rts

;; Compares <SAL> with <EAL>.
;;
;; Out: zero = set when they are equal, carry = set when SAL is at or past EAL
;; Uses: A
WRT62:
    lda SAL+1
    cmp EAL+1
    bne WRT62_1
    lda SAL
    cmp EAL

WRT62_1:
    rts

;; The factory test, which the diagnostic jumper starts: it times the retrace interrupt with timer 1 (<BSYI1>), and
;; waits.
DIAG:
    stx PIA1_CRA                    ; PIA 1's port A all inputs
    stx PIA1_PA
    lda #$04
    sta PIA1_CRA
    sta PIA1_PA
    jsr BSIV                        ; the timer check's interrupt
    dex
    stx VIA_T1CL
    bit PIA1_PB

DIAG_1:
    bit PIA1_CRB                    ; start timer 1 at a retrace
    bpl DIAG_1
    stx VIA_T1CH
    bit PIA1_PB
    cli

DIAG_2:
    jmp DIAG_2                      ; wait for the interrupt

;; The factory test's first interrupt: checks that a retrace came a frame after the last, then that the ROMs'
;; exclusive OR (<VPRTY>) is zero, sizes and checks the RAM (<RAMTEST>), and goes on to the keyboard (<RAMPASS>).
;; Each check that fails stops in a loop.
BSYI1:
    lda VIA_T1CL                    ; how long since
    ldy VIA_T1CH
    bit PIA1_CRB

BSYI1_1:
    bpl BSYI1_1                     ; wait for the retrace
    and #$C0                        ; a frame since: about $BEC0 left
    cmp #$C0

BSYI1_2:
    bne BSYI1_2
    cpy #$BE

BSYI1_3:
    bne BSYI1_3
    dec PIA1_CRB                    ; the retrace interrupt off
    bit PIA1_PB
    lda #$00                        ; the ROMs' exclusive OR: $C000-$E7FF
    sta CHKSUM
    sta SAL
    sta EAL
    tay
    ldx #$C0
    stx SAL+1
    ldx #$E8
    stx EAL+1
    jsr VPRTY
    ldx #$F0                        ; and $F000-$FFFF
    stx SAL+1
    sty EAL+1
    jsr VPRTY
    cpy CHKSUM                      ; must be zero

BSYI1_4:
    bne BSYI1_4
    ldy #$FF                        ; RAM at $1000-$1FFF?
    sty DIAG_PATTERN
    iny
    sty DIAG_PTR
    lda #$10
    sta DIAG_PTR+1
    ldx #$20

BSYI1_5:
    lda (DIAG_PTR),y
    eor DIAG_PATTERN
    sta (DIAG_PTR),y
    cmp (DIAG_PTR),y
    beq BSYI1_6
    iny

BSYI1_6:
    inc DIAG_PTR+1
    cpx DIAG_PTR+1
    bne BSYI1_5
    cpy #$00                        ; all of it: 8K
    beq BSYI1_8
    cpy #$10                        ; none of it: 4K; otherwise stop

BSYI1_7:
    bne BSYI1_7
    ldx #$10
    ldy #$00

BSYI1_8:
    jmp RAMTEST                     ; check the RAM

;; The factory test after a RAM pass: runs the RAM check again with the pattern's next value, then checks the keyboard
;; lines through the test plug, row by row, and loops the cassette write line back to cassette 1's read line for an
;; interrupt (<BCI1>).
RAMPASS:
    inc DIAG_PATTERN                ; the next pattern
    cpy DIAG_PATTERN
    beq BSYI1_8
    sty PIA1_CRA                    ; the keyboard through the test plug
    lda #$0F
    sta PIA1_PA
    lda #PIA_HIGH
    sta PIA1_CRA
    lda #$FD
    ldx #$09

RAMPASS_1:
    stx PIA1_PA
    cmp PIA1_PB

RAMPASS_2:
    bne RAMPASS_2
    lsr a
    bcc RAMPASS_3
    ora #$80

RAMPASS_3:
    dex
    bpl RAMPASS_1
    stx PIA1_PA                     ; no row
    cpx PIA1_PB

RAMPASS_4:
    bne RAMPASS_4
    sty PIA1_CRA
    sty PIA1_PA
    lda #PIA_HIGH
    sta PIA1_CRA
    ldx #IRQ_TEST1                  ; cassette 1's loop
    jsr BSIV
    ldx #$F7                        ; the write line low
    stx VIA_ORB
    inc PIA1_CRA
    bit PIA1_PA
    cli
    asl VIA_ORB                     ; a pulse on it
    lsr VIA_ORB

RAMPASS_5:
    bne RAMPASS_5                   ; wait for the interrupt

;; The factory test's interrupt from cassette 1's read line: then loops the write line back to cassette 2's, for
;; <BCI2>.
BCI1:
    dec PIA1_CRA                    ; cassette 1's interrupt off: it came?

BCI1_1:
    bpl BCI1_1
    bit PIA1_PA
    ldx #IRQ_TEST2                  ; cassette 2's loop
    jsr BSIV
    bit VIA_ORB
    lda #$90
    sta VIA_IER
    cli
    asl VIA_ORB                     ; a pulse
    lsr VIA_ORB

BCI1_2:
    bne BCI1_2

;; The factory test's interrupt from cassette 2's read line: then checks the user port (<DIAGUSR>).
BCI2:
    bit VIA_IFR                     ; it came?

BCI2_1:
    bpl BCI2_1
    lda #$7F
    sta VIA_IER
    bit VIA_ORB
    jmp DIAGUSR

;; The factory test's user port handshake: waits for PA6 to go low, then for a pulse on CA1.
;;
;; Out: A = the VIA's CA1 flag, zero = clear when it was set again
USRWAIT:
    bit VIA_ORA
    bvs USRWAIT

USRWAIT_1:
    bit VIA_ORANH
    bvc USRWAIT_1

USRWAIT_2:
    bit VIA_ORANH
    bvs USRWAIT_2
    lda VIA_IFR
    and #$02
    rts

;; The factory test's last checks: the user port's lines, the screen (stepping a reversed space over every place, then
;; filling it), the IEEE-488 data lines and handshake looped back through the test plug, and PIA 1's lines. It ends in
;; a loop, as every failed check does.
DIAGUSR:
    ldx #$0A

DIAGUSR_1:
    bit VIA_ORA
    bpl DIAGUSR_1

DIAGUSR_2:
    bit VIA_ORA
    bmi DIAGUSR_2

DIAGUSR_3:
    dex
    bne DIAGUSR_3
    bit VIA_ORA
    bmi DIAGUSR_5

DIAGUSR_4:
    bpl DIAGUSR_4

DIAGUSR_5:
    inc IRQVEC+1                    ; a write to ROM, which changes nothing
    bit VIA_ORA

DIAGUSR_6:
    bmi DIAGUSR_6

DIAGUSR_7:
    bit VIA_ORA
    bvc DIAGUSR_7

DIAGUSR_8:
    bit VIA_ORA
    bvs DIAGUSR_8

DIAGUSR_9:
    bit VIA_ORA
    bvc DIAGUSR_9

DIAGUSR_10:
    bit VIA_ORA
    bvs DIAGUSR_10
    jsr CINT_PAGE2
    jsr USRWAIT

DIAGUSR_11:
    bne DIAGUSR_11
    ldy #$00

DIAGUSR_12:
    lda #' ' | $80
    sta (PNT),y
    jsr USRWAIT

DIAGUSR_13:
    beq DIAGUSR_13
    lda #' '
    sta (PNT),y
    jsr USRWAIT

DIAGUSR_14:
    bne DIAGUSR_14
    cpy #$E7
    bne DIAGUSR_15
    lda #$83
    cmp PNT+1
    beq DIAGUSR_17

DIAGUSR_15:
    iny
    bne DIAGUSR_12
    inc PNT+1
    bne DIAGUSR_12

DIAGUSR_16:
    beq DIAGUSR_16

DIAGUSR_17:
    tya
    sta (PNT),y
    dey
    cpy #$FF
    bne DIAGUSR_17
    dec PNT+1
    lda #$7F
    cmp PNT+1
    bne DIAGUSR_17
    lda #PIA_LOW
    sta PIA1_CRA
    jsr USRWAIT

DIAGUSR_18:
    bne DIAGUSR_18
    lda #PIA_HIGH
    sta PIA1_CRA
    ldx DIAG_PTR

DIAGUSR_19:
    stx PIA2_PB
    cpx PIA2_PA

DIAGUSR_20:
    bne DIAGUSR_20
    inx
    bne DIAGUSR_19
    bit PIA2_PA
    lda #$FB
    sta VIA_ORB
    bit PIA2_CRA

DIAGUSR_21:
    bpl DIAGUSR_21
    bit VIA_ORB

DIAGUSR_22:
    bvc DIAGUSR_22
    lsr a
    sta VIA_ORB
    bit VIA_ORB

DIAGUSR_23:
    bvs DIAGUSR_23

DIAGUSR_24:
    bpl DIAGUSR_24
    lda #PIA_LOW
    sta PIA2_CRB
    lda VIA_ORB

DIAGUSR_25:
    bmi DIAGUSR_25
    lsr a

DIAGUSR_26:
    bcc DIAGUSR_26
    lda #PIA_LOW
    sta PIA2_CRA
    lsr VIA_ORB

DIAGUSR_27:
    bcs DIAGUSR_27
    lda #$02
    sta VIA_DDRA
    sta VIA_ORA
    bit PIA1_PA

DIAGUSR_28:
    bvc DIAGUSR_28
    stx VIA_ORA
    bit PIA1_PA
    bvc DIAGUSR_30
    nop
    nop

DIAGUSR_29:
    jmp DIAGUSR_29

DIAGUSR_30:
    stx PIA1_CRA
    ldy #$0F
    sty PIA1_PA
    asl a
    sta PIA1_CRA
    eor #$FF
    sta PIA1_PA

DIAGUSR_31:
    jmp DIAGUSR_31

;; A byte that makes the exclusive OR of all the ROMs zero, for the factory test, then the unused bytes before the jump
;; table.
CKFIX:
    .byte $61
    .res 13, 0

; The jump table.

;; Inherit: <OPEN>
CQOPEN:
    jmp OPEN

;; Inherit: <CLOSE>
CQCLOS:
    jmp CLOSE

;; Inherit: <CHKIN>
CQOIN:
    jmp CHKIN

;; Inherit: <CHKOUT>
CQOOUT:
    jmp CHKOUT

;; Inherit: <CLRCHN>
CQCCHN:
    jmp CLRCHN

;; Inherit: <BASIN>
CQINCH:
    jmp BASIN

;; Inherit: <BSOUT>
OUTCH:
    jmp BSOUT

;; Inherit: <LOAD>
CQLOAD:
    jmp LOAD

;; Inherit: <SAVE>
CQSAVE:
    jmp SAVE

;; Inherit: <VER>
CQVERF:
    jmp VER

;; Inherit: <SYS>
CQSYS:
    jmp SYS

;; Inherit: <CHKSTOP>
ISCNTC:
    jmp CHKSTOP

;; Inherit: <GETIN>
CZGETL:
    jmp GETIN

;; Inherit: <CLALL>
CQCALL:
    jmp CLALL

;; Inherit: <UDTIM>
JUDTIM:
    jmp UDTIM

;; Stops both cassette motors, and turns PIA 1's retrace interrupt off.
;;
;; Its RTS is also the low byte of the 6502's NMI vector, which so points into BASIC (<NMIENT>).
;;
;; Uses: A
TNOF:
    lda #PIA_HIGH
    sta PIA1_CRB
    lda VIA_ORB
    ora #VIAB_MOTOR2
    sta VIA_ORB
    rts                             ; $FFFA, and the NMI vector's low byte
    .byte >NMIENT                   ; $FFFB, the NMI vector's high byte
    .assert <NMIENT = $60, "TNOF's RTS is the low byte of the NMI vector."

;; The 6502's reset vector.
RESVEC:
    .word START

;; The 6502's IRQ and BRK vector.
IRQVEC:
    .word PULS
