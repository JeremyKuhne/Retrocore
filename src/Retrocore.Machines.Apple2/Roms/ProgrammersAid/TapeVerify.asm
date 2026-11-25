; retrocore: style=strict
;; Programmer's Aid #1: Tape Verify ($D52E-$D5AF)
;;
;; Steve Wozniak's tape verify (1978): it reads a recording back and compares it with memory, without loading it, so a
;; SAVE can be checked while the program is still there. CALL -10955 (<TapeVerify::VerifyProgram>) checks an Integer
;; BASIC program against the one in memory; for machine code or data, D52EG sets the Monitor's Control-Y up
;; (<TapeVerify::SetUp>), and `begin.end` Control-Y checks that block against the tape. A difference prints ERR, the
;; address, and the byte in memory and then the byte from tape in parentheses, and stops that block's check (a program's
;; check goes on from its header to the program); a bad checksum beeps and prints ERR, as `LOAD` does.
;;
;; The listing's names are those of Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1). Part of ProgrammersAid.asm.

.scope TapeVerify

;; The running checksum of the bytes read, as the Monitor's <ReadCassette> keeps it: <PlotMask>'s byte.
;; Also: CHKSUM (PA1)
Checksum = PlotMask

;; The program's length (2 bytes), <HighMemory> - <ProgramStart>, which the tape's header holds: <Accumulator>'s bytes,
;; where Integer BASIC's `SAVE` and `LOAD` keep it.
;; Also: PRLEN (PA1)
ProgramLength = Accumulator

;; D52EG: points the Monitor's Control-Y command at <VerifyBlock>.
;; Keeps: X
;; Also: TVSETUP (UNKN)
.proc SetUp
.assert * = $D52E, "TapeVerify::SetUp must stay at $D52E, where the manual's D52EG enters it."
    lda #<VerifyBlock
    ldy #>VerifyBlock
    jmp SetControlY
.endproc

;; CALL -10955: checks the Integer BASIC program in memory against the one on tape, header first, as Integer BASIC's
;; `LOAD` reads them.
;; Keeps: X
;; Also: VFYBSC (PA1)
.proc VerifyProgram
.assert * = $D535, "TapeVerify::VerifyProgram must stay at $D535, CALL -10955."
    stx BasicSavedX
    sec
    ldx #$FF

;; ProgramLength = <HighMemory> - <ProgramStart>, low byte with X = $FF, then high byte with X = 0.
;; Also: GETLEN (PA1)
GetLength:
    lda HighMemory + 1,x
    sbc ProgramStart + 1,x
    sta ProgramLength + 1,x
    inx
    beq GetLength

    ; The header, then the program.
    jsr Cassette::PointAtLength
    jsr VerifyBlock
    ldx #1
    jsr Cassette::PointAtProgram
    jsr VerifyBlock
    ldx BasicSavedX
    rts
.endproc

;; Checks memory from A1 to A2 against the tape: the Monitor's <ReadCassette>, comparing instead of storing, with the
;; same timing.
;;
;; A difference prints ERR, then `address-memory (tape)` on the line after, and ends the check. Otherwise, at the end,
;; <ReadCassetteChecksum> checks the checksum, beeping, with ERR when it is wrong.
;; In: Address1/Address1High = the first address, Address2/Address2High = the last
;; Also: TAPEVFY (PA1)
.proc VerifyBlock

;; How long to let the header play once the tape is heard, as the Monitor's READ_HEADER_DELAY: about 3.5 seconds.
HEADER_DELAY = $16

;; The count that tells the sync bit from the header, as the Monitor's READ_SYNC_COUNT.
SYNC_COUNT = $24

;; The count before the first data byte, as the Monitor's READ_FIRST_COUNT.
FIRST_COUNT = $3B

;; The count before each later byte: the Monitor's READ_NEXT_COUNT less one, for the compare's extra time.
NEXT_COUNT = $34

    ; Waits for the tape's tone, then lets the header play.
    jsr Cassette::ReadBit
    lda #HEADER_DELAY
    jsr Cassette::WriteHeader
    ; Cassette::WriteHeader leaves A at $FF, where the checksum starts.
    sta Checksum
    jsr Cassette::ReadBit

;; Waits out the header's half cycles for the shorter one of the sync bit.
;; Also: VRFY2 (PA1)
FindSync:
    ldy #SYNC_COUNT
    jsr Cassette::ReadHalfCycle
    bcs FindSync
    jsr Cassette::ReadHalfCycle
    ldy #FIRST_COUNT

;; Reads a byte and compares it with the next in memory.
;; Also: VRFY3 (PA1)
NextByte:
    jsr Cassette::ReadByte
    ; Always taken: Cassette::ReadByte leaves X at 0.
    beq Compare

;; Adds the byte to the checksum and steps A1, until past A2; then checks the checksum.
;; Also: VFYLOOP (PA1)
Matched:
    eor Checksum
    sta Checksum
    jsr NextInRange
    ldy #NEXT_COUNT
    bcc NextByte
    jmp ReadCassetteChecksum

;; Compares the byte read with memory, after a delay that keeps the timing of the Monitor's read, which stores the
;; byte here.
;; Also: EXTDEL (PA1)
Compare:
    nop
    nop
    nop
    cmp (Address1,x)
    beq Matched

    ; A difference: "ERR", then "address-memory (tape)"; <PrintAddress> leaves Y at 0, with the screen as the output.
    pha
    jsr PrintError
    jsr PrintAddress
    lda (Address1),y
    jsr PrintHexByte
    lda #' '
    jsr CharacterOut
    lda #'('
    jsr CharacterOut
    pla
    jsr PrintHexByte
    lda #')'
    jsr CharacterOut
    lda #KEY_RETURN
    jmp CharacterOut

    ; A second copy of the last two instructions, which nothing reaches.
    lda #KEY_RETURN
    jmp CharacterOut
.endproc

.endscope
