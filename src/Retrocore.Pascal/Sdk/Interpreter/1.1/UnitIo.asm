; retrocore: style=strict
;; Unit I/O: the standard procedures <UNITREAD at UnitIo::CspUREAD>, <UNITWRITE at UnitIo::CspUWRITE>,
;; <UNITCLEAR at UnitIo::CspUCLEAR>, <UNITSTATUS at UnitIo::CspUSTAT>, <UNITBUSY at UnitIo::CspUBUSY> and
;; <UNITWAIT at UnitIo::CspUWAIT>, IORESULT and the I/O check, and the character units' reading and writing.
;;
;; A unit is a disk drive, a character device the interpreter handles by its unit number, or a driver routine, as
;; <UnitTable> says; or, with <ATTACHED_UNIT> set, a driver attached in <AttachedDrivers>.

; Unit numbers.

;; The bits of an attached driver's unit number that number the driver.
ATTACHED_DRIVER_MASK = $7F

;; The drivers <AttachedDrivers> has room for.
ATTACHED_DRIVERS = 16

; The requests a unit call makes of a driver, which it passes in X.

; I/O results, as SysIoResult holds them, numbered as SYSTEM.PASCAL numbers its I/O error messages.

; A UNITREAD or UNITWRITE control word's bits.

;; Raw transfer: no DLE expansion, and a read does not stop at the end-of-file character.
;; Also: NOSPEC (UCSD20IO)
CONTROL_RAW = $04

;; No line feed written after a carriage return.
CONTROL_NO_LINE_FEED = $08

;; <IoControl>'s bits that the control word's bits 4 and 5 set, shifted down.
IO_CONTROL_MASK = $03

; Characters.

;; A DLE's count byte is this plus the number of blanks.
DLE_BIAS = $20

;; One entry of <UnitWriters>: the BIOS call that writes a character to a character unit.
;; Parameters:
;;   unit = the unit; the entries go in unit order
;;   routine = the BIOS call, or 0 when the unit cannot write
.macro UnitWriter unit, routine
    .assert * = UnitWriters + 2 * unit, "UnitWriters' entries are in unit order."
    .word routine
.endmacro

;; One entry of <UnitReaders>: the BIOS call that reads a character from a character unit.
;; Parameters:
;;   unit = the unit; the entries go in unit order
;;   routine = the BIOS call, or 0 when the unit cannot read
.macro UnitReader unit, routine
    .assert * = UnitReaders + 2 * unit, "UnitReaders' entries are in unit order."
    .word routine
.endmacro

; BreakHandler, UnitWriters and UnitReaders overlap. Each table has a slot for unit 0 that nothing reads, as CheckUnit
; refuses unit 0: UnitWriters starts at BreakHandler's high byte, so its unit 0 slot is that byte and SavedIoControl,
; and UnitReaders starts at UnitWriters' unit 8 entry.

;; <ExecutionError::Interrupted>'s address, which <UNITCLEAR at UnitIo::CspUCLEAR> and <Initialize> give the console
;; driver for the break key.
BreakHandler:
    .word ExecutionError::Interrupted

;; Each character unit's BIOS write call, a word a unit from unit 0, or 0 for none. Its unit 0 slot is <BreakHandler>'s
;; high byte and <SavedIoControl>; its unit 8 entry is <UnitReaders>' unit 0 slot.
;; Also: WRITTBL (A2PBIOS)
UnitWriters = BreakHandler + 1

;; <IoControl> as it was before a <UNITREAD at UnitIo::CspUREAD> or <UNITWRITE at UnitIo::CspUWRITE>, put back when it
;; ends.
SavedIoControl:
    .res 1
    .assert SavedIoControl = UnitWriters + 1, "SavedIoControl is UnitWriters' unit 0 slot's high byte."
    UnitWriter UNIT_CONSOLE, BiosConsoleWrite
    UnitWriter UNIT_SYSTERM, BiosConsoleWrite
    UnitWriter UNIT_GRAPHICS, BiosGraphicsWrite
    ; The disks are no character units.
    UnitWriter UNIT_BOOT_DISK, 0
    UnitWriter UNIT_SECOND_DISK, 0
    UnitWriter UNIT_PRINTER, BiosPrinterWrite
    ; The remote line's input cannot write.
    UnitWriter UNIT_REMOTE_IN, 0

;; Each character unit's BIOS read call, a word a unit from unit 0, or 0 for none. Its unit 0 slot is <UnitWriters>'
;; unit 8 entry.
;; Also: READTBL (A2PBIOS)
UnitReaders:
    UnitWriter UNIT_REMOTE_OUT, BiosRemoteWrite
    UnitReader UNIT_CONSOLE, BiosConsoleRead
    UnitReader UNIT_SYSTERM, BiosConsoleRead
    ; The graphics screen and the printer cannot read, and the disks are no character units.
    UnitReader UNIT_GRAPHICS, 0
    UnitReader UNIT_BOOT_DISK, 0
    UnitReader UNIT_SECOND_DISK, 0
    UnitReader UNIT_PRINTER, 0
    UnitReader UNIT_REMOTE_IN, BiosRemoteRead
    ; The remote line's output cannot read.
    UnitReader UNIT_REMOTE_OUT, 0

;; The unit calls and the I/O result's standard procedures.
.scope UnitIo

;; The request the call makes of the unit's driver: <REQUEST_READ>, <REQUEST_WRITE>, <REQUEST_CLEAR> or
;; <REQUEST_STATUS>.
Request = Procedure

;; Not 0 when the control word has <CONTROL_RAW>.
Raw = Mark

;; Not 0 when the control word has <CONTROL_NO_LINE_FEED>.
NoLineFeed = Result

;; The control word.
;; Also: CONTROL (UCSD20IO)
Control = Result + 2

;; A <UNITREAD at UnitIo::CspUREAD> or <UNITWRITE at UnitIo::CspUWRITE>'s unit number, its low byte.
;; Also: UNITNUMBER (UCSD20IO)
Unit = Result + 4

;; A <UNITREAD at UnitIo::CspUREAD> or <UNITWRITE at UnitIo::CspUWRITE>'s block number.
;; Also: LOGICALBLOCK (UCSD20IO)
Block = Pointer2

;; A <UNITREAD at UnitIo::CspUREAD> or <UNITWRITE at UnitIo::CspUWRITE>'s byte count, counted down.
;; Also: BYTESTOTRANSFER (UCSD20IO)
Count = ProcedureNumber

;; 0 when a character unit's read echoes what it reads, as <UNIT_CONSOLE>'s does, or 1.
NoEcho = Pointer

;; The character unit's BIOS read call, from <UnitReaders>.
Reader = Work1

;; The character unit's BIOS write call, from <UnitWriters>.
Writer = Work3

;; Checks a unit call's unit number: 1 to <LAST_UNIT>, or <ATTACHED_UNIT> plus the number of a driver whose JMP in
;; <AttachedDrivers> has been filled in. A bad one ends the call, with <IO_BAD_UNIT>, and runs the next p-code.
;; In: A = X = the unit number's low byte (its high byte is not checked)
;; Out: A = X = the unit number; for an attached driver's unit, Y = the driver's number times 3
;; Keeps: X
;; Also: VALVNO (WK11)
.proc CheckUnit

;; The attached driver's number, while it is tripled.
DriverNumber = Work4

    ; An attached driver's unit?
    and #ATTACHED_UNIT
    bne Attached

    ; No: it must be FIRST_UNIT to LAST_UNIT.
    txa
    cmp #LAST_UNIT + 1
    bcs Bad
    cmp #FIRST_UNIT
    bcc Bad
    rts

    ; Yes: the driver must be in range, and its JMP's address filled in, its high byte no longer 0.
Attached:
    txa
    and #ATTACHED_DRIVER_MASK
    sta DriverNumber
    cmp #ATTACHED_DRIVERS
    bcs Bad
    asl a
    adc DriverNumber
    tay
    lda AttachedDrivers+2,y
    beq Bad
    txa
    rts

    ; Bad: record IO_BAD_UNIT, drop the return address, and end the call.
Bad:
    ldx #IO_BAD_UNIT
    stx SysIoResult
    pla
    pla
    jmp Fetch::Skip2
.endproc

;; <IOR at UnitIo::CspIOR>, the standard procedure IORESULT: pushes the last I/O call's result.
;; Also: IORESULT (UCSD20, UCSD20IO), PSHIOR (WK11)
.proc CspIOR
    lda SysIoResult+1
    pha
    lda SysIoResult
    pha
    jmp Fetch::Skip2
.endproc

;; <IOC at UnitIo::CspIOC>, the I/O check the compiler puts after I/O: reports <ERROR_USER_IO> when the last I/O call's
;; result was not <IO_OK>.
;; Also: CSP0 (WK11), IOC (UCSD20)
.proc CspIOC
    lda SysIoResult
    beq Done
    jmp ExecutionError::UserIo
Done:
    jmp Fetch::Skip2
.endproc

;; <UBUSY at UnitIo::CspUBUSY>, the standard procedure <UNITBUSY at UnitIo::CspUBUSY>: pops a unit number, checks it,
;; and pushes FALSE, as no unit is ever busy.
;; Also: CSP35 (WK11), UNITBUSY (UCSD20, UCSD20IO)
.proc CspUBUSY
    ; Pop the unit and check it.
    pla
    tax
    pla
    txa
    jsr CheckUnit

    ; Push FALSE.
    lda #0
    pha
    pha
    jmp Fetch::Skip2
.endproc

;; <UWAIT at UnitIo::CspUWAIT>, the standard procedure <UNITWAIT at UnitIo::CspUWAIT>: pops a unit number and checks it.
;; Every transfer is done before its call returns, so there is nothing to wait for.
;; Also: CSP37 (WK11), UNITWAIT (UCSD20, UCSD20IO)
.proc CspUWAIT
    pla
    tax
    pla
    txa
    jsr CheckUnit
    jmp Fetch::Skip2
.endproc

;; <USTAT at UnitIo::CspUSTAT>, the standard procedure <UNITSTATUS at UnitIo::CspUSTAT>: pops the control word, the
;; status record's address (two words, added) and the unit, and has the unit's device fill the record. A character unit
;; with no status routine gets <IO_NO_DEVICE>.
;; Also: CSP12 (WK11)
.proc CspUSTAT
    ; Pop the control word.
    lda #REQUEST_STATUS
    sta Request
    pla
    sta Control
    pla
    sta Control+1

    ; Pop the record's address: a word, plus a word.
    pla
    sta Buffer
    pla
    sta Buffer+1
    clc
    pla
    adc Buffer
    sta Buffer
    pla
    adc Buffer+1
    sta Buffer+1

    ; Pop the unit and check it.
    pla
    tax
    pla
    txa
    jsr CheckUnit

    ; Push the control word and the record's address again, for the status routine.
    lda Control+1
    pha
    lda Control
    pha
    lda Buffer+1
    pha
    lda Buffer
    pha

    ; An attached driver's unit: call it as UNITCLEAR does.
    txa
    and #ATTACHED_UNIT
    beq NotAttached
    bne CspUCLEAR::CallAttached

    ; The remote units are one device: unit 7 is unit 8.
NotAttached:
    txa
    cmp #UNIT_REMOTE_IN
    bne FindDevice
    lda #UNIT_REMOTE_OUT
    tax

    ; A disk, a character device, or a driver's unit, which is called as UNITCLEAR does?
FindDevice:
    asl a
    tay
    lda UnitTable+1,y
    beq Disk
    cmp #>CHARACTER_DEVICE
    beq Characters
    bne CspUCLEAR::CallDriver

    ; A disk: its drive's status.
Disk:
    lda UnitTable,y
    jsr BiosDiskStatus
    jmp Finish

    ; A character device: the console's, the printer's or the remote line's status. X = REQUEST_STATUS, as for a
    ; driver; the BIOS's status routines do not read it.
Characters:
    txa
    tay
    ldx #REQUEST_STATUS
    cpy #UNIT_GRAPHICS
    bcs NotConsole
    jsr BiosConsoleStatus
    jmp Finish
NotConsole:
    cpy #UNIT_PRINTER
    bne NotPrinter
    jsr BiosPrinterStatus
    jmp Finish
NotPrinter:
    cpy #UNIT_REMOTE_OUT
    bne NoDevice
    jsr BiosRemoteStatus
    jmp Finish

    ; The graphics screen has no status: drop the arguments pushed for it.
NoDevice:
    ldx #IO_NO_DEVICE
    pla
    pla
    pla
    pla
    jmp Finish
.endproc

;; <UCLEAR at UnitIo::CspUCLEAR>, the standard procedure <UNITCLEAR at UnitIo::CspUCLEAR>: pops a unit number and has
;; its device reset. The graphics screen is reset, but gets <IO_NO_DEVICE> all the same.
;; Also: CSP38 (WK11), UNITCLEAR (UCSD20, UCSD20IO)
.proc CspUCLEAR
    ; Pop the unit and check it.
    lda #REQUEST_CLEAR
    sta Request
    pla
    tax
    pla
    txa
    jsr CheckUnit
    and #ATTACHED_UNIT
    beq NotAttached

;; Calls an attached driver, for <UNITCLEAR at UnitIo::CspUCLEAR> and <UNITSTATUS at UnitIo::CspUSTAT>, and ends the
;; call with its result.
;; In: X = the unit, Request = the request
CallAttached:
    txa
    ldx Request
    jsr BiosAttachedDriver
    jmp Finish

    ; The remote units are one device: unit 7 is unit 8.
NotAttached:
    txa
    cmp #UNIT_REMOTE_IN
    bne FindDevice
    lda #UNIT_REMOTE_OUT
    tax

    ; A disk, a character device, or a driver's unit?
FindDevice:
    asl a
    tay
    lda UnitTable+1,y
    beq Disk
    cmp #>CHARACTER_DEVICE
    beq Characters

;; Calls a unit's driver routine, from <UnitTable>, for <UNITCLEAR at UnitIo::CspUCLEAR> and
;; <UNITSTATUS at UnitIo::CspUSTAT>, and ends the call with its result.
;; In: X = the unit, Y = the unit times 2, Request = the request
CallDriver:
    txa
    ldx Request
    jsr BiosUnitDriver
    jmp Finish

    ; A disk: reset its drive.
Disk:
    lda UnitTable,y
    jsr BiosDiskInit
    jmp Finish

    ; A character device. X = REQUEST_CLEAR, as for a driver; the BIOS's routines do not read it.
Characters:
    txa
    tay
    ldx #REQUEST_CLEAR
    cpy #UNIT_GRAPHICS
    bcs NotConsole

    ; The console: clear both its units' DLE states, and reset it, giving it BreakHandler and SYSCOM's address
    ; (BootAddresses' third word).
    lda #0
    sta DleFlags+UNIT_CONSOLE
    sta DleFlags+UNIT_SYSTERM
    lda BreakHandler+1
    pha
    lda BreakHandler
    pha
    lda BootAddresses+5
    pha
    lda BootAddresses+4
    pha
    jsr BiosConsoleInit
    jmp Finish

    ; The printer: clear its DLE state, and reset it.
NotConsole:
    cpy #UNIT_PRINTER
    bne NotPrinter
    lda #0
    sta DleFlags+UNIT_PRINTER
    jsr BiosPrinterInit
    jmp Finish

    ; The remote line.
NotPrinter:
    cpy #UNIT_REMOTE_OUT
    bne NotRemote
    jsr BiosRemoteInit
    jmp Finish

    ; The graphics screen: reset it, and fall into IO_NO_DEVICE.
NotRemote:
    cpy #UNIT_GRAPHICS
    bne NoDevice
    jsr BiosGraphicsInit
NoDevice:
    ldx #IO_NO_DEVICE
    jmp Finish
.endproc

;; Ends a <UNITREAD at UnitIo::CspUREAD> or <UNITWRITE at UnitIo::CspUWRITE>: puts <IoControl> back, and ends the call
;; as <Finish> does.
;; In: X = the I/O result
;; Also: UNTOKX (WK11)
FinishRestoring:
    lda SavedIoControl
    sta IoControl

;; Ends a unit call: records its I/O result and runs the next p-code.
;; In: X = the I/O result
;; Also: STOIOR (WK11)
Finish:
    stx SysIoResult
    jmp Fetch::Skip2

;; Pushes a <UNITREAD at UnitIo::CspUREAD> or <UNITWRITE at UnitIo::CspUWRITE>'s arguments again, under the return
;; address, for a driver that takes them from the stack: the control word, the unit (or the drive), the buffer, the byte
;; count and, on top, the block.
;; In: X = the unit, or for a disk its drive
;; Keeps: X, Y
.proc PushUnitArguments
    ; Take the return address off the stack.
    pla
    sta ReturnAddress
    pla
    sta ReturnAddress+1

    ; Push the arguments, a word each, high byte first.
    lda Control+1
    pha
    lda Control
    pha
    lda #0
    pha
    txa
    pha
    lda Buffer+1
    pha
    lda Buffer
    pha
    lda Count+1
    pha
    lda Count
    pha
    lda Block+1
    pha
    lda Block
    pha

    ; Put the return address back.
    lda ReturnAddress+1
    pha
    lda ReturnAddress
    pha
    rts
.endproc

;; Ends a character unit's <UNITREAD at UnitIo::CspUREAD> or <UNITWRITE at UnitIo::CspUWRITE>, whose I/O result
;; <StoreIoResult> has recorded: puts <IoControl> back and runs the next p-code.
FinishCharacters:
    lda SavedIoControl
    sta IoControl
    jmp Fetch::Skip2

;; <UREAD at UnitIo::CspUREAD>, the standard procedure <UNITREAD at UnitIo::CspUREAD>: reads, as
;; <UWRITE at UnitIo::CspUWRITE> writes.
;; Also: UNITRD (WK11), UNITREAD (UCSD20, UCSD20IO), URD (UCSD20)
.proc CspUREAD
    lda #REQUEST_READ
    jmp CspUWRITE::Transfer
.endproc

;; <UWRITE at UnitIo::CspUWRITE>, the standard procedure <UNITWRITE at UnitIo::CspUWRITE>: pops the control word, the
;; block, the byte count, the buffer's address (two words, added) and the unit, and writes the buffer to the unit. A
;; count of 0 or less does nothing.
;; Also: UNITWR (WK11), UNITWRITE (UCSD20, UCSD20IO), UWT (UCSD20)
.proc CspUWRITE
    lda #REQUEST_WRITE

;; The transfer <UNITREAD at UnitIo::CspUREAD> and <UNITWRITE at UnitIo::CspUWRITE> share.
;; In: A = the request, <REQUEST_READ> or <REQUEST_WRITE>
;; Also: UNITRW (WK11)
Transfer:
    ; Keep the request, and IoControl to put back.
    sta Request
    ldy #1
    sty Raw
    sty NoLineFeed
    ldy IoControl
    sty SavedIoControl

    ; Pop the control word. Its bits 4 and 5 set IoControl's bits 0 and 1 for the call.
    pla
    tax
    sta Control
    lsr a
    lsr a
    lsr a
    lsr a
    and #IO_CONTROL_MASK
    ora IoControl
    sta IoControl

    ; No error so far. Take CONTROL_RAW and CONTROL_NO_LINE_FEED.
    ldy #0
    sty SysIoResult
    txa
    and #CONTROL_RAW
    bne TakeNoLineFeed
    sty Raw
TakeNoLineFeed:
    txa
    and #CONTROL_NO_LINE_FEED
    bne TakeHighByte
    sty NoLineFeed
TakeHighByte:
    pla
    sta Control+1

    ; Pop the block.
    pla
    sta Block
    pla
    sta Block+1

    ; Pop the count, which must be above 0.
    pla
    sta Count
    beq LowByteZero
    pla
    sta Count+1
    bmi NothingToDo
    jmp TakeBuffer

;; Nothing to do: drops the buffer's address and the unit, and ends the call, leaving IoControl changed.
;; Also: UNTERX (WK11)
NothingToDo:
    pla
    pla
    pla
    pla
    pla
    pla
    jmp Fetch::Skip2
LowByteZero:
    pla
    beq NothingToDo
    bmi NothingToDo
    sta Count+1

    ; Pop the buffer's address: a word, plus a word.
TakeBuffer:
    pla
    sta Buffer
    pla
    sta Buffer+1
    clc
    pla
    adc Buffer
    sta Buffer
    pla
    adc Buffer+1
    sta Buffer+1

    ; Pop the unit and check it.
    pla
    sta Unit
    tax
    pla
    txa
    jsr CheckUnit
    and #ATTACHED_UNIT
    beq NotAttached

    ; An attached driver's unit: call it, with the arguments on the stack.
    jsr PushUnitArguments
    txa
    ldx Request
    jsr BiosAttachedDriver
    jmp FinishRestoring

    ; A disk, a character device, or a driver's unit, which is called with the arguments on the stack?
NotAttached:
    txa
    asl a
    tay
    lda UnitTable+1,y
    beq Disk
    cmp #>CHARACTER_DEVICE
    beq Characters
    jsr PushUnitArguments
    txa
    ldx Request
    jsr BiosUnitDriver
    jmp FinishRestoring

    ; A disk: read or write its drive.
Disk:
    ldx UnitTable,y
    jsr PushUnitArguments
    lda Request
    bne WriteDisk
    jsr BiosDiskRead
    jmp FinishRestoring
WriteDisk:
    jsr BiosDiskWrite
    jmp FinishRestoring

    ; A character device: UNIT_CONSOLE echoes what it reads.
Characters:
    lda #1
    cpx #UNIT_CONSOLE
    bne SetEcho
    lda #0
SetEcho:
    sta NoEcho

    ; Take its write and read calls.
    txa
    asl a
    tax
    lda UnitWriters,x
    sta Writer
    lda UnitWriters+1,x
    sta Writer+1
    lda UnitReaders,x
    sta Reader
    lda UnitReaders+1,x
    sta Reader+1

    ; Without the call the request needs, the result is IO_BAD_REQUEST. (Echoing needs no check: only the console
    ; echoes, and it writes.)
    lda Request
    beq NeedReader
    lda Writer+1
    bne Start
BadRequest:
    ldx #IO_BAD_REQUEST
    jmp FinishRestoring
NeedReader:
    lda Reader+1
    beq BadRequest

    ; Transfer Count characters.
Start:
    ldx Count
    jmp CountDown

    ; Read a character into the buffer.
NextCharacter:
    lda Request
    bne WriteNext
    jsr ReadCharacter
    ldx #0
    sta (Buffer,x)

    ; Unless raw, SysEofCharacter ends the read. UNIT_CONSOLE puts zeros in the rest of the buffer, from the
    ; end-of-file character on; any other unit leaves it there and stops.
    ldy Raw
    bne Echo
    cmp SysEofCharacter
    bne Echo
    ldy #UNIT_CONSOLE
    cpy Unit
    beq FillZeros
    jmp FinishCharacters
FillZeros:
    lda #0
NextZero:
    sta (Buffer,x)
    inc Buffer
    bne CountZero
    inc Buffer+1
CountZero:
    dec Count
    bne NextZero
    dec Count+1
    bpl NextZero
    jmp FinishCharacters

    ; Echo it, if the unit echoes.
Echo:
    ldy NoEcho
    bne Advance
    jsr WriteExpanded
    jmp Advance

    ; Write a character from the buffer.
WriteNext:
    ldx #0
    lda (Buffer,x)
    jsr WriteExpanded

    ; Step to the next, until Count is done.
Advance:
    inc Buffer
    bne CountCharacter
    inc Buffer+1
CountCharacter:
    dec Count
CountDown:
    bne NextCharacter
    dec Count+1
    bpl NextCharacter
    jmp FinishCharacters
.endproc

;; Writes a character to a character unit through <Writer>. Unless <Raw>, a DLE is not written but noted in the unit's
;; <DleFlags> byte, and the count byte after it becomes its blanks; unless <NoLineFeed>, a carriage return
;; (<ASCII_CR>) is followed by a line feed (<ASCII_LF>).
;; In: A = the character, Unit = the unit
.proc WriteExpanded

;; The blanks still to write, plus one.
BlankCount = ReturnAddress

    ; Raw: only a carriage return (ASCII_CR) to look at.
    ldy Raw
    bne CheckReturn

    ; Is this the count byte after a DLE?
    ldy Unit
    ldx DleFlags,y
    beq CheckDle

    ; Yes: write its blanks.
    sec
    sbc #DLE_BIAS - 1
    sta BlankCount
NextBlank:
    lda #ASCII_SPACE
    dec BlankCount
    beq BlanksDone
    jsr WriteCharacter
    jmp NextBlank

    ; Forget the DLE.
BlanksDone:
    ldx #0
    ldy Unit
    stx DleFlags,y
    rts

    ; A DLE: note it, for the count byte.
CheckDle:
    cmp #ASCII_DLE
    bne CheckReturn
    lda #1
    sta DleFlags,y
    rts

    ; A carriage return: write it and a line feed, unless NoLineFeed.
CheckReturn:
    ldy NoLineFeed
    bne WriteIt
    cmp #ASCII_CR
    bne WriteIt
    jsr WriteCharacter
    lda #ASCII_LF
    jsr WriteCharacter
    rts

    ; Anything else: write it.
WriteIt:
    jsr WriteCharacter
    rts
.endproc

;; The return address <WriteCharacter> and <ReadCharacter> push for the BIOS call: <StoreIoResult>'s, less one, as RTS
;; takes it.
IoReturn:
    .word StoreIoResult - 1

;; Where a BIOS character call returns: records its result as the I/O result, and returns to the caller of
;; <WriteCharacter> or <ReadCharacter>.
;; In: X = the BIOS call's result
.proc StoreIoResult
    stx SysIoResult
    rts
.endproc

;; Writes a character through <Writer>, the unit's BIOS write call, which returns through <StoreIoResult>.
;; In: A = the character, Unit = the unit
;; Out: X = the I/O result, also in <SysIoResult>
.proc WriteCharacter
    ; Have the BIOS call return to StoreIoResult.
    tay
    lda IoReturn+1
    pha
    lda IoReturn
    pha

    ; Call it, with Y = the unit and X = REQUEST_WRITE, as for a driver; the BIOS's routines read only A.
    tya
    ldy Unit
    ldx #REQUEST_WRITE
    jmp (Writer)
.endproc

;; Reads a character through <Reader>, the unit's BIOS read call, which returns through <StoreIoResult>.
;; In: Unit = the unit
;; Out: A = the character, X = the I/O result, also in <SysIoResult>
.proc ReadCharacter
    ; Have the BIOS call return to StoreIoResult.
    tay
    lda IoReturn+1
    pha
    lda IoReturn
    pha

    ; Call it, with Y = the unit and X = REQUEST_READ, as for a driver.
    tya
    ldy Unit
    ldx #REQUEST_READ
    jmp (Reader)
.endproc

.endscope
