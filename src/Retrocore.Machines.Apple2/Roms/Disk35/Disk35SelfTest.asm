;; THE CARD'S SELF-TESTS ($8F00-$99FF): THE START-UP TEST AND THE DIAGNOSTICS' CARD SIDE
;;
;; TestStartUp ($9649) runs at every reset, from the main firmware's reset at $D11D:
;;   1. copies the slot page's first 35 bytes ($Cn00-$Cn22) from the EPROM, so the host sees the SmartPort
;;      signature at once, and its entries wait on themselves (BOOTWAIT and CALLWAIT) until the card is ready;
;;   2. the EPROM's checksum: the sum of every byte but $FFF9 is 0, and $FFF9 plus the carries is 0;
;;   3. the SWIM: as an IWM, its data register and three modes; as the ISM, its phases, its status and its sixteen
;;      parameters; and as the IWM again;
;;   4. the RAM: the stack page with a rising and a falling count, and eight bytes from $0403 to $4003, for the
;;      address lines.
;; Then it turns the LED off and goes on to the main firmware's start-up at $D129. On a failure it makes every entry
;; of the slot page jump to the Monitor, clears the SmartPort signature and blinks the LED for ever.
;;
;; TestDiagnostics ($8F00) runs when the host sends command $3D (CMDDIAGNOSTICS). It tests page zero, puts the
;; diagnostics' page zero and host code in place, sends the host to DiagStart and reports to it, through $0002,
;; each of: the slot page ("Card pseudoROM"), the EPROM's CRCs, its checksum, the SWIM and the RAM. Then it leaves a
;; sum of its RAM for the host to check ("Host/Card shared data"), finds its units, and, only with Apple's factory
;; fixture in slot 1, writes and reads back a block on units 1 and 2. It then reads memory until the host says to
;; restart. A failure before the RAM's sum is reported to the host and blinks the LED until the host says to
;; restart.
;;
;; At the card's 2 MHz the start-up test takes about a quarter of a second, nearly all of it the checksum.

; The card's own 65C02, with the 65C02's instructions.
.cpu Wdc65C02

; The main firmware's routines.
TEST_CardReset = $D11D              ;; the reset: starts the stack, clears $00, and comes to TestStartUp
TEST_CardStartUp = $D129            ;; the start-up after the test: finds the units, unless page zero says it has
TEST_CardDoCommand = $D1E7          ;; carries out the command in $00 for the unit in $03; error in $56
TEST_CardFindUnits = $D2A1          ;; the cold start's search for drives: counts the units in $33
TEST_CardIwmIdle = $D80B            ;; puts the SWIM back to the IWM, its mode $1F, drives off
TEST_CardPointAtBuffer = $D9B0      ;; points $AB and $AF at the two pages of the 512-byte buffer A ($08-$1B: $1000-$37FF)

TEST_OLDRST = $FF59                 ;; the host's Monitor (OLDRST), where a failed card's slot page sends the host

; Page zero.
TEST_Command = $00                  ;; the command for TEST_CardDoCommand; $FF once it is done
TEST_CommandFlag = $01              ;; the main firmware's; the test sets it to $FF around each command
TEST_CardStatus = $02               ;; the diagnostics' report to the host (host $C802)
TEST_CommandParam = $02             ;; the command's second byte, which the test sets to the command again
TEST_Unit = $03                     ;; the unit for the command, from 1
TEST_Block = $05                    ;; the block for the command, low byte first
TEST_FailedBlock = $07              ;; the block that failed, for the host (host $C807)
TEST_Pattern = $00                  ;; TestCardRam's 16-bit pattern
TEST_RamPointer = $04               ;; TestCardRam's and TestIdle's place in memory
TEST_SumPointer = $00               ;; TestSharedData's place in memory
TEST_LastBuffer = $2D               ;; the buffer the last command used
TEST_UnitCount = $33                ;; the number of units (host $C833)
TEST_Error = $56                    ;; the last command's error, 0 for none (host $C856)
TEST_ForceRead = $5F                ;; set to $FF for the test's reads: apparently, from the disk and not the cache
TEST_BufferLow = $AB                ;; a pointer to a buffer's first page
TEST_BufferHigh = $AF               ;; a pointer to its second page
TEST_ForceWrite = $B9               ;; set to $FF during the test's writes: apparently, to the disk at once
TEST_Crc = $FC                      ;; TestRomCrc's CRC
TEST_RomPointer = $FE               ;; the checksum's and the CRC's place in the EPROM

; The card's RAM.
TEST_Stack = $0100
TEST_FixtureId = $03EE              ;; slot 1's first 16 bytes, which the host copies here (host $CBEE)
TEST_RandomBlock = $03FE            ;; a byte that varies, from the host (host $CBFE)
TEST_Signal = $03FF                 ;; the mailbox for the later steps (host $CBFF): see Disk35Diagnostics.asm
TEST_SavedBlock = $0400             ;; the 512 bytes written, $0400-$05FF
TEST_AddressCells = $0003           ;; plus $0400 to $4000: the bytes that test the address lines
TEST_SharedSum = $09FF              ;; the complement of TestSharedData's sum

; The EPROM.
TEST_RomCrcs = $FFDA                ;; the CRCs of the first fifteen 2 KB blocks, $8000-$F7FF, low byte first
TEST_RomCheckByte = $FFF9           ;; makes the checksum's carries add up to 0
TEST_DiagHostCode = DiagnosticsImage ;; the host's code at $CA00-$CBFF, two pages
TEST_DiagExpansion = DiagnosticsImage+$0200 ;; the host's code at $CC00-$CFFF, four pages
TEST_DiagZeroPage = DiagnosticsImage+$0600 ;; the card's page zero for the diagnostics
.assert SlotPageImage == $8100
.assert TEST_DiagZeroPage == $8E00

; The slot page's bytes the tests change.
TEST_SlotSignature = SHARED_SLOTPAGE+5 ;; $Cn05, the SmartPort signature's $03
TEST_BootWait = SHARED_SLOTPAGE+<BOOTWAIT+1 ;; BOOTWAIT's offset ($7B0C)
TEST_DiagWait = SHARED_SLOTPAGE+<DIAGWAIT_Loop+1 ;; DIAGWAIT's offset ($7B18)
TEST_CallWait = SHARED_SLOTPAGE+<CALLWAIT_Loop+1 ;; CALLWAIT's offset ($7B22)
TEST_SlotDiag = SHARED_SLOTPAGE+<DIAG ;; $Cn0D, where a released BOOTWAIT goes
TEST_SlotCall = SHARED_SLOTPAGE+<CALL ;; $Cn23, where a released CALLWAIT goes
.assert TEST_BootWait == $7B0C && TEST_DiagWait == $7B18 && TEST_CallWait == $7B22

TEST_WAITING = $FE                  ;; a branch offset that waits on itself

; TEST_CardStatus.
TEST_PASSED = $A1
TEST_FAILED = $4F

; TEST_Signal.
TEST_GO = $A1                       ;; from the host: take the next step
TEST_STOP = $4F                     ;; from the host: stop; to the host: no more steps
TEST_EXIT = $55                     ;; from the host: restart
TEST_RWFAILED = $4E                 ;; to the host: a read/write test failed

; Commands.
TEST_READ = 1                       ;; reads a block
TEST_WRITE = 2                      ;; writes a block

TEST_FIRSTBUFFER = $08              ;; the buffers TestFillBuffers fills: $08-$1B, $1000-$37FF, a track's worth
TEST_ENDBUFFER = $1C
TEST_PATTERNTAPS = $100B            ;; TestCardRam's pattern's feedback
TEST_CRCPOLY = $1021                ;; the CCITT CRC-16's polynomial

;; The next of TestCardRam's 16-bit patterns: shifts it left, and applies TEST_PATTERNTAPS when a bit falls out.
;; Goes on at the label given.
.macro TestNextPattern again
    clc
    rol TEST_Pattern
    rol TEST_Pattern+1
    bcc again
    lda #<TEST_PATTERNTAPS
    eor TEST_Pattern
    sta TEST_Pattern
    lda #>TEST_PATTERNTAPS
    eor TEST_Pattern+1
    sta TEST_Pattern+1
    bra again
.endmacro

;; Starts a pass of TestCardRam at $0006 with the first pattern, 1.
.macro TestFirstPattern
    lda #6
    sta TEST_RamPointer
    stz TEST_RamPointer+1
    lda #1
    sta TEST_Pattern
    stz TEST_Pattern+1
.endmacro

;; One bit of TestRomCrc: shifts the CRC left and takes the byte's next bit, lowest first, into carry (from the EPROM
;; for the first bit, then from Y); when the two differ, applies TEST_CRCPOLY.
.macro TestCrcBit first
    .local high, apply, done
    clc
    rol TEST_Crc
    rol TEST_Crc+1
    bcs high
.if first
    lda (TEST_RomPointer)
.else
    tya
.endif
    ror a
    tay
    bcc done
apply:
    lda #<TEST_CRCPOLY
    eor TEST_Crc
    sta TEST_Crc
    lda #>TEST_CRCPOLY
    eor TEST_Crc+1
    sta TEST_Crc+1
    bra done
high:
.if first
    lda (TEST_RomPointer)
.else
    tya
.endif
    ror a
    tay
    bcs done
    bra apply
done:
.endmacro

;; Waits about outer times 2030 cycles: 1 ms at 2 MHz for each count.
.macro TestDelay outer
    .local again, wait
    ldx #outer
again:
    lda #$CB
wait:
    dec a
    bne *+2                         ; goes on either way
    nop
    bne wait
    dex
    bne again
.endmacro

.assert * == $8F00

;; The diagnostics' card side, which the main firmware's command loop jumps to for command $3D. Tests page zero's
;; first six bytes, puts the diagnostics' page zero and the host's code at $CC00 in place, sends the host there, and
;; reports each test to it.
TestDiagnostics:
    sei
    cld
    ldx #$FF
    txs
    ldx #5
TestDiagnostics_Write:
    lda TestZeroPagePatterns,x
    sta $00,x
    dex
    bpl TestDiagnostics_Write
    ldx #5
TestDiagnostics_Check:
    lda TestZeroPagePatterns,x
    cmp $00,x
    beq TestDiagnostics_Same
    jmp TestDiagnosticsFailed
TestDiagnostics_Same:
    dex
    bpl TestDiagnostics_Check
    ldx #5
TestDiagnostics_WriteInverse:
    lda TestZeroPageInverse,x
    sta $00,x
    dex
    bpl TestDiagnostics_WriteInverse
    ldx #5
TestDiagnostics_CheckInverse:
    lda TestZeroPageInverse,x
    cmp $00,x
    beq TestDiagnostics_SameInverse
    jmp TestDiagnosticsFailed
TestDiagnostics_SameInverse:
    dex
    bpl TestDiagnostics_CheckInverse
    jsr TestCopyZeroPage
    jsr TestVerifyZeroPage
    bcc TestDiagnostics_ZeroPageOk
    jmp TestDiagnosticsFailed
TestDiagnostics_ZeroPageOk:
    jsr TestCopyExpansion
    stz TEST_CardStatus
    stz TEST_DiagWait               ; sends the host to DiagStart
    lda #TEST_WAITING
    sta TEST_BootWait
    sta TEST_CallWait
    jsr TestVerifySlotPage
    bcc TestDiagnostics_SlotPageOk
    jmp TestDiagnosticsFailed
TestDiagnostics_SlotPageOk:
    jsr TestVerifyExpansion
    bcc TestDiagnostics_ExpansionOk
    jmp TestDiagnosticsFailed
TestDiagnostics_ExpansionOk:
    jsr TestReportPass              ; Card pseudoROM
    jsr TestRomCrc
    bcc TestDiagnostics_CrcOk
    jmp TestDiagnosticsFailed
TestDiagnostics_CrcOk:
    jsr TestReportPass              ; Card ROM CRC
    jsr TestRomChecksum
    bcc TestDiagnostics_ChecksumOk
    jmp TestDiagnosticsFailed
TestDiagnostics_ChecksumOk:
    jsr TestReportPass              ; Card ROM Checksum
    jsr TestSwim
    bcc TestDiagnostics_SwimOk
    jmp TestDiagnosticsFailed
TestDiagnostics_SwimOk:
    jsr TestReportPass              ; SWIM Regs.
    ; Falls into TestCardRam.

;; Tests the RAM from $0006 to $7AFF, but for the I/O page ($0A00-$0AFF): writes a sequence of 16-bit patterns,
;; checks it, then does the same with their complements. The slot page and the host's $CC00 code are kept; the
;; host's $CA00 code is written over, and TestSharedData puts it back.
TestCardRam:
    TestFirstPattern
TestCardRam_Word:
    lda #>IWM_PH0L
    cmp TEST_RamPointer+1
    bne TestCardRam_NotIo
    lda #>IWM_PH0L+1
    sta TEST_RamPointer+1
TestCardRam_NotIo:
    lda #>SHARED_SLOTPAGE
    cmp TEST_RamPointer+1
    beq TestCardRam_Check
    lda TEST_Pattern
    sta (TEST_RamPointer)
    inc TEST_RamPointer
    lda TEST_Pattern+1
    sta (TEST_RamPointer)
    inc TEST_RamPointer
    bne TestCardRam_Step
    inc TEST_RamPointer+1
TestCardRam_Step:
    TestNextPattern TestCardRam_Word
TestCardRam_Check:
    TestFirstPattern
TestCardRam_CheckWord:
    lda #>IWM_PH0L
    cmp TEST_RamPointer+1
    bne TestCardRam_CheckNotIo
    lda #>IWM_PH0L+1
    sta TEST_RamPointer+1
TestCardRam_CheckNotIo:
    lda #>SHARED_SLOTPAGE
    cmp TEST_RamPointer+1
    beq TestCardRam_Inverse
    lda TEST_Pattern
    cmp (TEST_RamPointer)
    beq TestCardRam_LowOk
    jmp TestDiagnosticsFailed
TestCardRam_LowOk:
    inc TEST_RamPointer
    lda TEST_Pattern+1
    cmp (TEST_RamPointer)
    beq TestCardRam_HighOk
    jmp TestDiagnosticsFailed
TestCardRam_HighOk:
    inc TEST_RamPointer
    bne TestCardRam_CheckStep
    inc TEST_RamPointer+1
TestCardRam_CheckStep:
    TestNextPattern TestCardRam_CheckWord
TestCardRam_Inverse:
    TestFirstPattern
TestCardRam_InverseWord:
    lda #>IWM_PH0L
    cmp TEST_RamPointer+1
    bne TestCardRam_InverseNotIo
    lda #>IWM_PH0L+1
    sta TEST_RamPointer+1
TestCardRam_InverseNotIo:
    lda #>SHARED_SLOTPAGE
    cmp TEST_RamPointer+1
    beq TestCardRam_CheckInverse
    lda TEST_Pattern
    eor #$FF
    sta (TEST_RamPointer)
    inc TEST_RamPointer
    lda TEST_Pattern+1
    eor #$FF
    sta (TEST_RamPointer)
    inc TEST_RamPointer
    bne TestCardRam_InverseStep
    inc TEST_RamPointer+1
TestCardRam_InverseStep:
    TestNextPattern TestCardRam_InverseWord
TestCardRam_CheckInverse:
    TestFirstPattern
TestCardRam_CheckInverseWord:
    lda #>IWM_PH0L
    cmp TEST_RamPointer+1
    bne TestCardRam_CheckInverseNotIo
    lda #>IWM_PH0L+1
    sta TEST_RamPointer+1
TestCardRam_CheckInverseNotIo:
    lda #>SHARED_SLOTPAGE
    cmp TEST_RamPointer+1
    beq TestSharedData
    lda TEST_Pattern
    eor #$FF
    cmp (TEST_RamPointer)
    beq TestCardRam_InverseLowOk
    jmp TestDiagnosticsFailed
TestCardRam_InverseLowOk:
    inc TEST_RamPointer
    lda TEST_Pattern+1
    eor #$FF
    cmp (TEST_RamPointer)
    beq TestCardRam_InverseHighOk
    jmp TestDiagnosticsFailed
TestCardRam_InverseHighOk:
    inc TEST_RamPointer
    bne TestCardRam_CheckInverseStep
    inc TEST_RamPointer+1
TestCardRam_CheckInverseStep:
    TestNextPattern TestCardRam_CheckInverseWord

;; Puts the host's $CA00-$CBFF code at $0200-$03FF, then sums the RAM the host can see, as DiagSharedData does,
;; and leaves the sum's complement in $09FF: $0006-$07FF, $0C00-$3FFF, $7C00-$7FFE, $0B00-$0BFF, the slot page and
;; $0800-$09FF. Reports "Card RAM" passed and waits for the host's check.
TestSharedData:
    ldy #0
TestSharedData_Copy:
    lda TEST_DiagHostCode,y
    sta $0200,y
    lda TEST_DiagHostCode+$0100,y
    sta $0300,y
    dey
    bne TestSharedData_Copy
    ; Puts in the stack the return address that the JSR below will push, so that it changes no byte of the sum.
    lda #>(TestSharedData_Await+2)
    pha
    lda #<(TestSharedData_Await+2)
    pha
    pla
    pla
    stz TEST_SumPointer
    stz TEST_SumPointer+1
    lda #0
    ldy #6
    stz TEST_SharedSum
TestSharedData_AddLow:
    clc
    adc (TEST_SumPointer),y
    iny
    bne TestSharedData_AddLow
    inc TEST_SumPointer+1
    ldx #$08
    cpx TEST_SumPointer+1
    bne TestSharedData_AddLow
    ldx #$0C
    stx TEST_SumPointer+1
TestSharedData_AddBanks:
    clc
    adc (TEST_SumPointer),y
    iny
    bne TestSharedData_AddBanks
    inc TEST_SumPointer+1
    ldx #$40
    cpx TEST_SumPointer+1
    bne TestSharedData_AddBanks
    ldx #>SHARED_EXPANSION
    stx TEST_SumPointer+1
TestSharedData_AddExpansion:
    clc
    adc (TEST_SumPointer),y
    iny
    bne TestSharedData_AddExpansion
    inc TEST_SumPointer+1
    ldx #$7F
    cpx TEST_SumPointer+1
    bne TestSharedData_AddExpansion
TestSharedData_AddLast:
    clc
    adc (TEST_SumPointer),y
    iny
    cpy #$FF                        ; not $7FFF, the host's $CFFF
    bne TestSharedData_AddLast
    iny
    ldx #$0B
    stx TEST_SumPointer+1
TestSharedData_AddPageB:
    clc
    adc (TEST_SumPointer),y
    iny
    bne TestSharedData_AddPageB
    ldx #>SHARED_SLOTPAGE
    stx TEST_SumPointer+1
TestSharedData_AddSlot:
    clc
    adc (TEST_SumPointer),y
    iny
    bne TestSharedData_AddSlot
    ldx #$08
    stx TEST_SumPointer+1
TestSharedData_AddWindow:
    clc
    adc (TEST_SumPointer),y
    iny
    bne TestSharedData_AddWindow
    inc TEST_SumPointer+1
    ldx #$0A
    cpx TEST_SumPointer+1
    bne TestSharedData_AddWindow
    eor #$FF
    sta TEST_SharedSum
    lda #TEST_PASSED                ; Card RAM
    sta TEST_CardStatus
TestSharedData_Await:
    jsr TestAwaitHost
    ; Falls into TestUnits.

;; Finds the units, lets the host list them, and tests units 1 and 2 if Apple's factory fixture is in slot 1.
TestUnits:
    jsr TEST_CardFindUnits
    lda #$FF
    sta TEST_Command
    stz TEST_Signal                 ; done: the host lists the units
    jsr TestAwaitHost
    ldy #15
TestUnits_Compare:
    lda TEST_FixtureId,y
    cmp TestFixtureSignature,y
    bne TestUnits_Stop
    dey
    bpl TestUnits_Compare
    jmp TestUnits_Fixture
TestUnits_Stop:
    lda #TEST_STOP
    sta TEST_Signal
    jmp TestIdle
TestUnits_Fixture:
    lda TEST_UnitCount
    bne TestUnits_Some
    jmp TestUnits_Stop
TestUnits_Some:
    lda #1
    sta TEST_Unit
    jsr TestUnit
    lda TEST_UnitCount
    cmp #2
    bcc TestUnits_Done
    lda #2
    sta TEST_Unit
    jsr TestUnit
TestUnits_Done:
    lda #TEST_STOP
    sta TEST_Signal
    jmp TestIdle

;; Writes a block of a unit with a pattern and reads it back, then again with another, and tells the host; on a
;; failure, tells the host the block and goes to TestIdle. The second read's result is not checked.
;; In: TEST_Unit = the unit
TestUnit:
    jsr TestFillBuffers
    jsr TestWriteBlock
    bcs TestUnit_Failed
    jsr TestReadBlock
    bcs TestUnit_Failed
    jsr TestFillSecondPattern
    jsr TestWriteBlock
    bcs TestUnit_Failed
    jsr TestReadBlock
    stz TEST_Signal                 ; done
    lda IWM_MTROFF
    jsr TestAwaitHost
    rts
TestUnit_Failed:
    lda TEST_Block
    sta TEST_FailedBlock
    lda TEST_Block+1
    sta TEST_FailedBlock+1
    lda #TEST_RWFAILED
    sta TEST_Signal
    lda IWM_MTROFF
    jmp TestIdle

;; Writes the block the host's byte chooses (twice the byte, plus its bit 0: 0-511) from the last buffer, and keeps
;; a copy of what it wrote at $0400-$05FF.
;; In:  TEST_Unit = the unit
;; Out: carry = set on an error
TestWriteBlock:
    jsr TEST_CardIwmIdle
    lda #TEST_WRITE
    sta TEST_CommandParam
    lda TEST_RandomBlock
    lsr a
    lda TEST_RandomBlock
    stz TEST_Block+1
    rol a
    sta TEST_Block
    rol TEST_Block+1
    lda #$FF
    sta TEST_CommandFlag
    sta TEST_ForceWrite
    lda #TEST_WRITE
    sta TEST_Command
    jsr TEST_CardDoCommand
    stz TEST_ForceWrite
    bcs TestWriteBlock_Done
    lda #$FF
    sta TEST_Command
TestWriteBlock_Done:
    lda TEST_Error
    beq TestWriteBlock_Keep
    sec
    rts
TestWriteBlock_Keep:
    lda TEST_LastBuffer
    jsr TEST_CardPointAtBuffer
    ldy #0
TestWriteBlock_Copy:
    lda (TEST_BufferLow),y
    sta TEST_SavedBlock,y
    lda (TEST_BufferHigh),y
    sta TEST_SavedBlock+$0100,y
    iny
    bne TestWriteBlock_Copy
    clc
    rts

;; Reads the block TestWriteBlock wrote and compares it with the copy at $0400-$05FF.
;; In:  TEST_Unit = the unit
;; Out: carry = set on an error or a difference
TestReadBlock:
    jsr TEST_CardIwmIdle
    lda #TEST_READ
    sta TEST_CommandParam
    lda TEST_RandomBlock
    lsr a
    lda TEST_RandomBlock
    stz TEST_Block+1
    rol a
    sta TEST_Block
    rol TEST_Block+1
    lda #$FF
    sta TEST_CommandFlag
    sta TEST_ForceRead
    lda #TEST_READ
    sta TEST_Command
    jsr TEST_CardDoCommand
    lda #$FE
    sta TEST_Command
    lda TEST_LastBuffer
    jsr TEST_CardPointAtBuffer
    lda #$FF
    sta TEST_CommandFlag
    lda TEST_Error
    beq TestReadBlock_Compare
TestReadBlock_Failed:
    sec
    rts
TestReadBlock_Compare:
    ldy #0
TestReadBlock_Byte:
    lda (TEST_BufferLow),y
    cmp TEST_SavedBlock,y
    bne TestReadBlock_Failed
    lda (TEST_BufferHigh),y
    cmp TEST_SavedBlock+$0100,y
    bne TestReadBlock_Failed
    iny
    bne TestReadBlock_Byte
    clc
    rts

;; Fills the track's buffers with the second pattern, from $C3.
TestFillSecondPattern:
    ldy #$C3
    bra TestFillBuffers_Seed

;; Fills the track's buffers ($08-$1B) with the first pattern, from $A5, so that a read must come from the disk.
;; Out: A = TEST_ENDBUFFER
;; Keeps: Y
TestFillBuffers:
    ldy #$A5
TestFillBuffers_Seed:
    lda #TEST_FIRSTBUFFER
TestFillBuffers_Next:
    jsr TestFillBuffer
    inc a
    cmp #TEST_ENDBUFFER
    bcc TestFillBuffers_Next
    rts

;; Fills a 512-byte buffer with Y rotated left through carry, set at first, a bit more at each byte.
;; In:  A = the buffer, Y = the first byte
;; Keeps: A, Y
TestFillBuffer:
    pha
    jsr TEST_CardPointAtBuffer
    tya
    sec
    phy
    ldy #0
TestFillBuffer_Byte:
    sta (TEST_BufferLow),y
    sta (TEST_BufferHigh),y
    rol a
    iny
    bne TestFillBuffer_Byte
    ply
    pla
    rts

;; The diagnostics' end: reads all of memory over and over, but for the SWIM's registers, whose reads have side
;; effects, until the host says to restart.
TestIdle:
    ldy #0
    sty TEST_RamPointer
    sty TEST_RamPointer+1
TestIdle_Byte:
    lda #>IWM_PH0L
    cmp TEST_RamPointer+1
    bne TestIdle_Read
    tya
    and #$C0                        ; $0A00-$0A3F
    bne TestIdle_Read
    bra TestIdle_Next
TestIdle_Read:
    lda (TEST_RamPointer),y
TestIdle_Next:
    iny
    bne TestIdle_Byte
    inc TEST_RamPointer+1
    bne TestIdle_Byte
    lda TEST_Signal
    cmp #TEST_EXIT
    bne TestIdle
    ; Falls into TestRestart.

;; Tells the host the card is restarting, turns the LED on and restarts the card from its reset.
TestRestart:
    lda #0
    sta TEST_Signal
    sta LEDON
    nop
    nop
    nop
    nop
    jmp TEST_CardReset

;; Waits for the host to let the card take its next step. If the host says to stop, goes to TestIdle instead.
;; Out: A = TEST_GO
;; Keeps: X, Y
TestAwaitHost:
    lda TEST_Signal
    cmp #TEST_GO
    bne TestAwaitHost_NotGo
    rts
TestAwaitHost_NotGo:
    cmp #TEST_STOP
    bne TestAwaitHost
    pla
    pla
    jmp TestIdle

;; Reports a test passed to the host, and waits for the host to see it.
;; Out: A = 0
;; Keeps: X, Y
TestReportPass:
    lda #TEST_PASSED
    sta TEST_CardStatus
TestReportPass_Wait:
    lda TEST_CardStatus
    bne TestReportPass_Wait
    rts

;; Tests the SWIM. As the IWM, with the drives off: the data register reads $FF, and the mode register holds $1F,
;; $00 and $0F. Then as the ISM: the phases read $F0, the status shows the ISM, and the sixteen parameters hold a
;; walking one and a walking zero. Then as the IWM again.
;; Out: carry = set on a failure
TestSwim:
    bit IWM_Q7L
    bit IWM_Q6L
    bit IWM_PH0L
    bit IWM_PH1L
    bit IWM_PH2L
    bit IWM_PH3L
    bit IWM_MTROFF
    lda IWM_Q7L                     ; Q6 and Q7 low: the data register
    cmp #$FF
    beq TestSwim_DataOk
    sec
    rts
TestSwim_DataOk:
    lda #$1F
    bit IWM_Q6H
    sta IWM_Q7H                     ; Q6 and Q7 high: writes the mode
    eor IWM_Q7L                     ; Q6 high: reads the status, the mode in its low five bits
    and #$1F
    beq TestSwim_Mode1F
    sec
    rts
TestSwim_Mode1F:
    lda #$00
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    beq TestSwim_Mode00
    sec
    rts
TestSwim_Mode00:
    lda #$0F
    bit IWM_Q6H
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    beq TestSwim_Mode0F
    sec
    rts
TestSwim_Mode0F:
    lda #$4F                        ; bit 6 written 1, 0, 1, 1: the ISM
    bit IWM_Q6H
    sta IWM_Q7H
    eor #$40
    sta IWM_Q7H
    eor #$40
    sta IWM_Q7H
    sta IWM_Q7H
    lda #5
TestSwim_Settle:
    dec a
    bne TestSwim_Settle
    lda ISM_rPhase
    cmp #$F0
    bne TestSwim_Failed
    lda ISM_rStatus
    and #$C0
    cmp #$40
    bne TestSwim_Failed
    stz ISM_wZeroes                 ; clears nothing, but starts the parameters again
    lda #$01
TestSwim_WriteOne:
    sta ISM_wParams
    asl a
    bcc TestSwim_WriteOne
    lda #$FE
TestSwim_WriteZero:
    sta ISM_wParams
    rol a
    bcs TestSwim_WriteZero
    stz ISM_wZeroes
    lda #$01
TestSwim_ReadOne:
    cmp ISM_rParams
    bne TestSwim_Failed
    asl a
    bcc TestSwim_ReadOne
    lda #$FE
TestSwim_ReadZero:
    cmp ISM_rParams
    bne TestSwim_Failed
    sec
    rol a
    bcs TestSwim_ReadZero
    bra TestSwim_Iwm
TestSwim_Failed:
    sec
    rts
TestSwim_Iwm:
    lda #$F8                        ; clears bit 6: the IWM again
    sta ISM_wZeroes
    bit IWM_Q7L
    bit IWM_Q6L
    bit IWM_PH0L
    bit IWM_PH1L
    bit IWM_PH2L
    bit IWM_PH3L
    bit IWM_MTROFF
    lda IWM_Q7L
    cmp #$FF
    beq TestSwim_AgainDataOk
    sec
    rts
TestSwim_AgainDataOk:
    lda #$1F
    bit IWM_Q6H
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    beq TestSwim_AgainMode1F
    sec
    rts
TestSwim_AgainMode1F:
    lda #$00
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    beq TestSwim_AgainMode00
    sec
    rts
TestSwim_AgainMode00:
    lda #$0F
    bit IWM_Q6H
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    bne TestSwim_AgainFailed
    clc
    rts
TestSwim_AgainFailed:
    sec
    rts

;; Checks the EPROM's checksum: the sum of every byte but TEST_RomCheckByte is 0, and that byte plus the sum's
;; carries is 0. A wrong sum goes to TestStartUpFailed, as at start-up.
;; Out: carry = set when the carries are wrong
TestRomChecksum:
    stz TEST_RomPointer
    lda #$80
    sta TEST_RomPointer+1
    lda #0
    tax
    tay
TestRomChecksum_Add:
    clc
    adc (TEST_RomPointer),y
    bcc TestRomChecksum_NoCarry
    inx
TestRomChecksum_NoCarry:
    iny
    bne TestRomChecksum_Add
    inc TEST_RomPointer+1
    tay
    lda TEST_RomPointer+1
    inc a
    beq TestRomChecksum_LastPage
    tya
    ldy #0
    bra TestRomChecksum_Add
TestRomChecksum_LastPage:
    tya
    ldy #0
TestRomChecksum_AddLast:
    clc
    adc (TEST_RomPointer),y
    bcc TestRomChecksum_LastNoCarry
    inx
TestRomChecksum_LastNoCarry:
    iny
    beq TestRomChecksum_Sum
    cpy #<TEST_RomCheckByte
    bne TestRomChecksum_AddLast
    iny
    bra TestRomChecksum_AddLast
TestRomChecksum_Sum:
    tay
    beq TestRomChecksum_SumOk
    jmp TestStartUpFailed
TestRomChecksum_SumOk:
    txa
    clc
    adc TEST_RomCheckByte
    beq TestRomChecksum_Ok
    sec
    rts
TestRomChecksum_Ok:
    clc
    rts

;; Checks the CCITT CRC-16 (from 0, each byte's bits lowest first) of each 2 KB block of $8000-$F7FF against
;; TEST_RomCrcs. The last block holds the CRCs, so has none.
;; Out: carry = set on a failure
TestRomCrc:
    stz TEST_RomPointer
    lda #$80
    sta TEST_RomPointer+1
TestRomCrc_Block:
    stz TEST_Crc
    stz TEST_Crc+1
TestRomCrc_Byte:
    TestCrcBit 1
    TestCrcBit 0
    TestCrcBit 0
    TestCrcBit 0
    TestCrcBit 0
    TestCrcBit 0
    TestCrcBit 0
    TestCrcBit 0
    inc TEST_RomPointer
    beq TestRomCrc_Page
    jmp TestRomCrc_Byte
TestRomCrc_Page:
    inc TEST_RomPointer+1
    lda TEST_RomPointer+1
    sec
    sbc #$80
    tax
    and #$07
    beq TestRomCrc_BlockDone
    jmp TestRomCrc_Byte
TestRomCrc_BlockDone:
    txa                             ; pages done, 8 times the blocks
    clc
    ror a
    ror a
    ror a
    dec a
    asl a
    tax
    lda TEST_RomCrcs,x
    cmp TEST_Crc
    beq TestRomCrc_LowOk
TestRomCrc_Failed:
    sec
    rts
TestRomCrc_LowOk:
    lda TEST_RomCrcs+1,x
    cmp TEST_Crc+1
    bne TestRomCrc_Failed
    cpx #2*14
    beq TestRomCrc_Ok
    jmp TestRomCrc_Block
TestRomCrc_Ok:
    clc
    rts

;; Checks that the slot page is the EPROM's, but for DIAGWAIT's offset, which must be 0.
;; Out: carry = set on a difference
TestVerifySlotPage:
    ldx #0
TestVerifySlotPage_Byte:
    cpx #<DIAGWAIT_Loop+1
    bne TestVerifySlotPage_Image
    lda #0
    bra TestVerifySlotPage_Compare
TestVerifySlotPage_Image:
    lda SlotPageImage,x
TestVerifySlotPage_Compare:
    cmp SHARED_SLOTPAGE,x
    bne TestVerifySlotPage_Failed
    dex
    bne TestVerifySlotPage_Byte
    clc
    rts
TestVerifySlotPage_Failed:
    sec
    rts

;; Copies the diagnostics' host code for $CC00-$CFFF to $7C00-$7FFF.
;; Out: X = 0
TestCopyExpansion:
    ldx #0
TestCopyExpansion_Page0:
    lda TEST_DiagExpansion,x
    sta SHARED_EXPANSION,x
    dex
    bne TestCopyExpansion_Page0
TestCopyExpansion_Page1:
    lda TEST_DiagExpansion+$0100,x
    sta SHARED_EXPANSION+$0100,x
    dex
    bne TestCopyExpansion_Page1
TestCopyExpansion_Page2:
    lda TEST_DiagExpansion+$0200,x
    sta SHARED_EXPANSION+$0200,x
    dex
    bne TestCopyExpansion_Page2
TestCopyExpansion_Page3:
    lda TEST_DiagExpansion+$0300,x
    sta SHARED_EXPANSION+$0300,x
    dex
    bne TestCopyExpansion_Page3
    rts

;; Checks the copy TestCopyExpansion made.
;; Out: carry = set on a difference
TestVerifyExpansion:
    ldx #0
TestVerifyExpansion_Page0:
    lda TEST_DiagExpansion,x
    cmp SHARED_EXPANSION,x
    bne TestVerifyExpansion_Failed
    dex
    bne TestVerifyExpansion_Page0
TestVerifyExpansion_Page1:
    lda TEST_DiagExpansion+$0100,x
    cmp SHARED_EXPANSION+$0100,x
    bne TestVerifyExpansion_Failed
    dex
    bne TestVerifyExpansion_Page1
TestVerifyExpansion_Page2:
    lda TEST_DiagExpansion+$0200,x
    cmp SHARED_EXPANSION+$0200,x
    bne TestVerifyExpansion_Failed
    dex
    bne TestVerifyExpansion_Page2
TestVerifyExpansion_Page3:
    lda TEST_DiagExpansion+$0300,x
    cmp SHARED_EXPANSION+$0300,x
    bne TestVerifyExpansion_Failed
    dex
    bne TestVerifyExpansion_Page3
    clc
    rts
TestVerifyExpansion_Failed:
    sec
    rts

;; Copies the diagnostics' page zero in.
;; Out: X = 0
TestCopyZeroPage:
    ldx #0
TestCopyZeroPage_Byte:
    lda TEST_DiagZeroPage,x
    sta $00,x
    dex
    bne TestCopyZeroPage_Byte
    rts

;; Checks the copy TestCopyZeroPage made.
;; Out: carry = set on a difference
TestVerifyZeroPage:
    ldx #0
TestVerifyZeroPage_Byte:
    lda TEST_DiagZeroPage,x
    cmp $00,x
    bne TestVerifyZeroPage_Failed
    dex
    bne TestVerifyZeroPage_Byte
    clc
    rts
TestVerifyZeroPage_Failed:
    sec
    rts

;; A failure of the diagnostics' own tests: reports it to the host, then blinks the LED, a long flash and two short
;; ones, until the host says to restart.
TestDiagnosticsFailed:
    lda #TEST_FAILED
    sta TEST_CardStatus
TestDiagnosticsFailed_Blink:
    sta LEDOFF
    ldx #0                          ; off about 0.39 s (65536 times 12 cycles)
TestDiagnosticsFailed_Off:
    lda #0
TestDiagnosticsFailed_OffWait:
    dec a
    bne *+2                         ; goes on either way
    nop
    nop
    bne TestDiagnosticsFailed_OffWait
    dex
    bne TestDiagnosticsFailed_Off
    sta LEDON
    ldx #0                          ; on about 0.82 s (65536 times 25 cycles)
TestDiagnosticsFailed_On:
    lda #0
TestDiagnosticsFailed_OnWait:
    dec a
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    nop
    bne TestDiagnosticsFailed_OnWait
    dex
    bne TestDiagnosticsFailed_On
    sta LEDOFF
    TestDelay $FF                   ; off about 0.26 s
    sta LEDON
    TestDelay $96                   ; on about 0.15 s
    sta LEDOFF
    TestDelay $FF
    sta LEDON
    TestDelay $96
    sta LEDOFF
    lda TEST_Signal
    cmp #TEST_EXIT
    bne TestDiagnosticsFailed_Blink
    jmp TestRestart

.assert * == $9649

;; The start-up test, which the main firmware's reset ($D11D) jumps to. Puts the slot page's start in place, and
;; checks the EPROM's checksum, the SWIM and some of the RAM; then turns the LED off and goes on with the main
;; firmware's start-up. A failure goes to TestStartUpFailed.
TestStartUp:
    ldy #<CALLWAIT_Loop+1           ; through CALLWAIT's offset
TestStartUp_Slot:
    lda SlotPageImage,y
    sta SHARED_SLOTPAGE,y
    dey
    bpl TestStartUp_Slot
    stz TEST_RomPointer
    lda #$80
    sta TEST_RomPointer+1
    lda #0
    tax
    tay
TestStartUp_Add:
    clc
    adc (TEST_RomPointer),y
    bcc TestStartUp_NoCarry
    inx
TestStartUp_NoCarry:
    iny
    bne TestStartUp_Add
    inc TEST_RomPointer+1
    tay
    lda TEST_RomPointer+1
    inc a
    beq TestStartUp_LastPage
    tya
    ldy #0
    bra TestStartUp_Add
TestStartUp_LastPage:
    tya
    ldy #0
TestStartUp_AddLast:
    clc
    adc (TEST_RomPointer),y
    bcc TestStartUp_LastNoCarry
    inx
TestStartUp_LastNoCarry:
    iny
    beq TestStartUp_Sum
    cpy #<TEST_RomCheckByte
    bne TestStartUp_AddLast
    iny
    bra TestStartUp_AddLast
TestStartUp_Sum:
    tay
    beq TestStartUp_SumOk
    jmp TestStartUpFailed
TestStartUp_SumOk:
    txa
    clc
    adc TEST_RomCheckByte
    beq TestStartUp_Swim
    jmp TestStartUpFailed
TestStartUp_Swim:
    bit IWM_Q7L
    bit IWM_Q6L
    bit IWM_PH0L
    bit IWM_PH1L
    bit IWM_PH2L
    bit IWM_PH3L
    bit IWM_MTROFF
    lda IWM_Q7L
    cmp #$FF
    beq TestStartUp_DataOk
    jmp TestStartUpFailed
TestStartUp_DataOk:
    lda #$1F
    bit IWM_Q6H
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    beq TestStartUp_Mode1F
    jmp TestStartUpFailed
TestStartUp_Mode1F:
    lda #$00
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    beq TestStartUp_Mode00
    jmp TestStartUpFailed
TestStartUp_Mode00:
    lda #$0F
    bit IWM_Q6H
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    beq TestStartUp_Mode0F
    jmp TestStartUpFailed
TestStartUp_Mode0F:
    lda #$4F                        ; bit 6 written 1, 0, 1, 1: the ISM
    bit IWM_Q6H
    sta IWM_Q7H
    eor #$40
    sta IWM_Q7H
    eor #$40
    sta IWM_Q7H
    sta IWM_Q7H
    lda #5
TestStartUp_Settle:
    dec a
    bne TestStartUp_Settle
    lda ISM_rPhase
    cmp #$F0
    bne TestStartUp_SwimFailed
    lda ISM_rStatus
    and #$C0
    cmp #$40
    bne TestStartUp_SwimFailed
    stz ISM_wZeroes
    lda #$01
TestStartUp_WriteOne:
    sta ISM_wParams
    asl a
    bcc TestStartUp_WriteOne
    lda #$FE
TestStartUp_WriteZero:
    sta ISM_wParams
    rol a
    bcs TestStartUp_WriteZero
    stz ISM_wZeroes
    lda #$01
TestStartUp_ReadOne:
    cmp ISM_rParams
    bne TestStartUp_SwimFailed
    asl a
    bcc TestStartUp_ReadOne
    lda #$FE
TestStartUp_ReadZero:
    cmp ISM_rParams
    bne TestStartUp_SwimFailed
    sec
    rol a
    bcs TestStartUp_ReadZero
    bra TestStartUp_Iwm
TestStartUp_SwimFailed:
    jmp TestStartUpFailed
TestStartUp_Iwm:
    lda #$F8                        ; clears bit 6: the IWM again
    sta ISM_wZeroes
    bit IWM_Q7L
    bit IWM_Q6L
    bit IWM_PH0L
    bit IWM_PH1L
    bit IWM_PH2L
    bit IWM_PH3L
    bit IWM_MTROFF
    lda IWM_Q7L
    cmp #$FF
    beq TestStartUp_AgainDataOk
    jmp TestStartUpFailed
TestStartUp_AgainDataOk:
    lda #$1F
    bit IWM_Q6H
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    beq TestStartUp_AgainMode1F
    jmp TestStartUpFailed
TestStartUp_AgainMode1F:
    lda #$00
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    beq TestStartUp_AgainMode00
    jmp TestStartUpFailed
TestStartUp_AgainMode00:
    lda #$0F
    bit IWM_Q6H
    sta IWM_Q7H
    eor IWM_Q7L
    and #$1F
    beq TestStartUp_Ram
    jmp TestStartUpFailed
TestStartUp_Ram:
    lda #0
    tax
TestStartUp_FillStack:
    sta TEST_Stack,x
    inc a
    inx
    bne TestStartUp_FillStack
    lda #$01
    sta TEST_AddressCells+$0400
    asl a
    sta TEST_AddressCells+$0500
    asl a
    sta TEST_AddressCells+$0600
    asl a
    sta TEST_AddressCells+$0800
    asl a
    sta TEST_AddressCells+$1000
    asl a
    sta TEST_AddressCells+$1200
    asl a
    sta TEST_AddressCells+$2000
    asl a
    sta TEST_AddressCells+$4000
    lda #$01
    cmp TEST_AddressCells+$0400
    beq TestStartUp_Cell0500
    jmp TestStartUpFailed
TestStartUp_Cell0500:
    asl a
    cmp TEST_AddressCells+$0500
    beq TestStartUp_Cell0600
    jmp TestStartUpFailed
TestStartUp_Cell0600:
    asl a
    cmp TEST_AddressCells+$0600
    beq TestStartUp_Cell0800
    jmp TestStartUpFailed
TestStartUp_Cell0800:
    asl a
    cmp TEST_AddressCells+$0800
    beq TestStartUp_Cell1000
    jmp TestStartUpFailed
TestStartUp_Cell1000:
    asl a
    cmp TEST_AddressCells+$1000
    beq TestStartUp_Cell1200
    jmp TestStartUpFailed
TestStartUp_Cell1200:
    asl a
    cmp TEST_AddressCells+$1200
    beq TestStartUp_Cell2000
    jmp TestStartUpFailed
TestStartUp_Cell2000:
    asl a
    cmp TEST_AddressCells+$2000
    beq TestStartUp_Cell4000
    jmp TestStartUpFailed
TestStartUp_Cell4000:
    asl a
    cmp TEST_AddressCells+$4000
    beq TestStartUp_CheckStack
    jmp TestStartUpFailed
TestStartUp_CheckStack:
    lda #0
    tax
TestStartUp_CheckRising:
    cmp TEST_Stack,x
    bne TestStartUp_StackFailed
    inc a
    inx
    bne TestStartUp_CheckRising
    bra TestStartUp_Falling
TestStartUp_StackFailed:
    jmp TestStartUpFailed
TestStartUp_Falling:
    lda #$FF
    ldx #0
TestStartUp_FillFalling:
    sta TEST_Stack,x
    dec a
    inx
    bne TestStartUp_FillFalling
    lda #$FF
    ldx #0
TestStartUp_CheckFalling:
    cmp TEST_Stack,x
    bne TestStartUp_FallingFailed
    dec a
    inx
    bne TestStartUp_CheckFalling
    bra TestStartUp_Recheck
TestStartUp_FallingFailed:
    jmp TestStartUpFailed
TestStartUp_Recheck:
    lda #$01
    cmp TEST_AddressCells+$0400
    beq TestStartUp_Recheck0500
    jmp TestStartUpFailed
TestStartUp_Recheck0500:
    asl a
    cmp TEST_AddressCells+$0500
    beq TestStartUp_Recheck0600
    jmp TestStartUpFailed
TestStartUp_Recheck0600:
    asl a
    cmp TEST_AddressCells+$0600
    beq TestStartUp_Recheck0800
    jmp TestStartUpFailed
TestStartUp_Recheck0800:
    asl a
    cmp TEST_AddressCells+$0800
    beq TestStartUp_Recheck1000
    jmp TestStartUpFailed
TestStartUp_Recheck1000:
    asl a
    cmp TEST_AddressCells+$1000
    beq TestStartUp_Recheck1200
    jmp TestStartUpFailed
TestStartUp_Recheck1200:
    asl a
    cmp TEST_AddressCells+$1200
    beq TestStartUp_Recheck2000
    jmp TestStartUpFailed
TestStartUp_Recheck2000:
    asl a
    cmp TEST_AddressCells+$2000
    beq TestStartUp_Recheck4000
    jmp TestStartUpFailed
TestStartUp_Recheck4000:
    asl a
    cmp TEST_AddressCells+$4000
    bne TestStartUpFailed
    sta LEDOFF
    jmp TEST_CardStartUp

;; A failure of the start-up test: makes the slot page's start, its DIAG entry and its call jump to the host's
;; Monitor, releases BOOTWAIT and CALLWAIT into those jumps, clears the SmartPort signature's $03 and the rest of
;; the page, and blinks the LED, a long flash and a short one, for ever.
TestStartUpFailed:
    stz TEST_SlotSignature
    lda #$4C                        ; JMP
    sta SHARED_SLOTPAGE
    sta TEST_SlotDiag
    sta TEST_SlotCall
    lda #<TEST_OLDRST
    sta SHARED_SLOTPAGE+1
    sta TEST_SlotDiag+1
    sta TEST_SlotCall+1
    lda #>TEST_OLDRST
    sta SHARED_SLOTPAGE+2
    sta TEST_SlotDiag+2
    sta TEST_SlotCall+2
    stz TEST_BootWait
    stz TEST_CallWait
    ldx #<CALL+3
TestStartUpFailed_Clear:
    stz SHARED_SLOTPAGE,x
    inx
    bne TestStartUpFailed_Clear
TestStartUpFailed_Blink:
    sta LEDOFF
    ldx #0                          ; off about 0.39 s
TestStartUpFailed_Off:
    lda #0
TestStartUpFailed_OffWait:
    dec a
    bne *+2                         ; goes on either way
    nop
    nop
    bne TestStartUpFailed_OffWait
    dex
    bne TestStartUpFailed_Off
    sta LEDON
    ldx #0                          ; on about 0.82 s
TestStartUpFailed_On:
    lda #0
TestStartUpFailed_OnWait:
    dec a
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    nop
    bne TestStartUpFailed_OnWait
    dex
    bne TestStartUpFailed_On
    sta LEDOFF
    TestDelay $FF                   ; off about 0.26 s
    sta LEDON
    TestDelay $96                   ; on about 0.15 s
    sta LEDOFF
    jmp TestStartUpFailed_Blink

;; TestDiagnostics's patterns for page zero's first six bytes, and their complements.
TestZeroPagePatterns:
    .byte $00, $FF, $55, $AA, $CC, $33
TestZeroPageInverse:
    .byte $FF, $00, $AA, $55, $33, $CC

;; The first 16 bytes of the ROM of Apple's factory fixture (AVEX Electronics made the card), in slot 1.
TestFixtureSignature:
    .byte $4C, <TEST_OLDRST, >TEST_OLDRST ; JMP OLDRST
    .byte "AVEX Manufact"

    .res 217                        ; unused
