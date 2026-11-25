; retrocore: style=strict
;; The card's firmware: control and status
;;
;; The command handlers that answer SmartPort CONTROL and STATUS, the 3.5 controller's FORMATOPTIONS and SETFORMAT,
;; and the eject they share with the rest of the firmware. A handler's lists move through the transfer buffer,
;; <TransferBuffer>: CONTROL asks the host for its list there, and the status and format lists are built there for the
;; host to take.

;; The buffer code of <TransferBuffer>: its card address divided by $200.
TRANSFER_BUFFER_CODE = TransferBuffer / $200

; The card's own errors.

;; Control $0A's interleave is 13 or more.
ERROR_BAD_INTERLEAVE = $32

;; SmartPort CONTROL ($04) and the control calls the card takes, $00-$13. A drive takes every code that has a handler;
;; unit 0, the controller, takes only the ones that reach the card's RAM ($0C and $0E-$13).
.scope Control

;; How many control codes there are.
CODE_COUNT = $14

;; The largest control list, plus one: a list must be shorter than $400 bytes.
LIST_LIMIT_HIGH = $04

;; The interleaves control $0A and SETFORMAT take are below this.
INTERLEAVE_LIMIT = 13

;; Runs the control call in <ParameterLow>: asks the host for the control list (<Count> and CountHigh bytes) in
;; <TransferBuffer>, waits for it, and jumps to the code's handler, which ends the command.
;; Out: carry = clear; ErrorCode = <ERROR_BAD_CONTROL> for a code past $13 or one the unit does not take,
;;      <ERROR_BAD_CONTROL_PARAMETER> for a list of $400 bytes or more, else the handler's
;; Entry:
;;   BadCode = ends with <ERROR_BAD_CONTROL>
;;   BadParameter = ends with <ERROR_BAD_CONTROL_PARAMETER>
;;   Finish = ends with the error in A, through <SetError>
.proc Run
    ldx ParameterLow
    cpx #CODE_COUNT
    bcs BadCode
    lda Drive
    bpl TakeList

    ; Unit 0 takes a code whose UnitZeroCodes byte has bits 7 and 6 clear.
    bit UnitZeroCodes,x
    bmi BadCode
    bvc TakeList
    bra BadCode

    ; The list, from the host.
TakeList:
    ldx CountHigh
    cpx #LIST_LIMIT_HIGH
    bcs BadParameter
    lda #TRANSFER_BUFFER_CODE
    sta CardData
WaitList:
    lda CardData
    bpl WaitList
    lda ParameterLow
    asl a
    tax
    jmp (Handlers,x)
BadCode:
    lda #ERROR_BAD_CONTROL
    bra Finish
BadParameter:
    lda #ERROR_BAD_CONTROL_PARAMETER
Finish:
    jmp SetError
.endproc

;; The control codes unit 0 refuses: bit 7 set for a code it does not take.
UnitZeroCodes:
    .byte $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $00, $80, $00, $00
    .byte $00, $00, $00, $00
.assert * - UnitZeroCodes = CODE_COUNT, "A byte for each control code."

;; Each control code's handler, $00-$13.
Handlers:
    .word Reset, Run::BadCode, Run::BadCode, Run::BadCode, Eject                ; $00-$04
    .word Run::BadCode, Run::BadCode, Run::BadCode, Run::BadCode, SetSides      ; $05-$09
    .word SetInterleave, Run::BadCode, Poke, RestoreMarks, RestoreVectors       ; $0A-$0E
    .word SetCache, SetAddress, Download, Execute, Peek                         ; $0F-$13
.assert * - Handlers = CODE_COUNT * 2, "A handler for each control code."

;; Control $0D: puts the GCR marks and sync bytes (<Marks> to the end of <AddressMark>) back from the ROM.
;; Out: carry = clear, ErrorCode = 0
.proc RestoreMarks
    ldx #MARKS_LENGTH
Loop:
    lda ZeroPageImage + Marks - 1,x
    sta Marks - 1,x
    dex
    bne Loop
    bra SetSides::Succeed
.endproc

;; The length of the marks <RestoreMarks> puts back: <Marks>, <DataMark>, <SyncBytes>, <Epilogue> and <AddressMark>.
MARKS_LENGTH = $16
.assert MARKS_LENGTH = AddressMark + 4 - Marks, "The marks end with AddressMark's four bytes."

;; Control $0E: puts the page-zero vectors (<Vectors>, as long as <VectorLength> says) back from the ROM.
;; Out: carry = clear, ErrorCode = 0
.proc RestoreVectors
    ldx ZeroPageImage + VectorLength
Loop:
    lda ZeroPageImage + Vectors - 1,x
    sta Vectors - 1,x
    dex
    bne Loop
    bra SetSides::Succeed
.endproc

;; Control $0F: one byte, whose bit 7 goes to <CacheOption>; the cache is flushed. The list's length is checked but
;; not acted on, so a list of any length is taken.
;; Out: carry = clear, ErrorCode = 0
.proc SetCache
    lda #$01
    jsr CheckLength
    lda TransferBuffer
    and #$80
    sta CacheOption
    jsr Cache::Flush
    bra SetSides::Succeed
.endproc

;; Control $0A: one byte, the interleave for FORMAT, below 13, for the drive and as the next FORMAT's.
;; Out: carry = clear; ErrorCode = <ERROR_BAD_CONTROL_PARAMETER> for a list not one byte long,
;;      <ERROR_BAD_INTERLEAVE> for 13 or more, else 0
.proc SetInterleave
    lda #$01
    jsr CheckLength
    bne Run::BadParameter
    lda #ERROR_BAD_INTERLEAVE
    ldy TransferBuffer
    cpy #INTERLEAVE_LIMIT
    bcs Run::Finish
    sty Interleave
    ldx Drive
    sty FormatInterleave,x
    bra SetSides::Succeed
.endproc

;; Control $09: one byte, whose bit 7 set has FORMAT write both sides.
;; Out: carry = clear; ErrorCode = <ERROR_BAD_CONTROL_PARAMETER> for a list not one byte long, else 0
;; Entry:
;;   Succeed = ends the control call with no error
.proc SetSides
    lda #$01
    jsr CheckLength
    bne TakeAddress::ToBadParameter
    lda TransferBuffer
    and #$80
    sta TwoSided
Succeed:
    lda #$00
    jmp Run::Finish
.endproc

;; Control $00, reset: forgets the drive's disk and finds its format again.
;; Out: carry = clear; ErrorCode = the error (through <SetError>) when the drive has no disk it can use; after a
;;      success nothing is set
.proc Reset
    ldx Drive
    jsr Drives::ForgetDisk
    jsr Drives::CheckDisk
    bpl Checked
    jsr Drives::IdentifyMedia
Checked:
    bcc Done
    jmp SetError
Done:
    rts
.endproc

;; Control $04, eject: ejects the drive's disk and drops its sectors from the cache. The card's fixed entry points
;; (<CardVectors>) reach it too.
;; Out: carry = clear; ErrorCode = <ERROR_IO> if the disk did not leave
.proc Eject
    ldx Drive
    jsr Drives::ReadStatus
    jsr EjectDisk
    ldx Drive
    jsr Cache::Forget
    clc
    rts
.endproc

;; Control $12: calls code in the card at the address in the list's bytes 4 and 5, with A, X, Y and the status from
;; its first four (<CallUser>), and keeps what the code returns in <ResultA>, <ResultX>, <ResultY> and <ResultStatus>,
;; for status code 5.
;; Out: carry = clear
.proc Execute
    jsr CallUser
    sta ResultA
    stx ResultX
    sty ResultY
    php
    pla
    sta ResultStatus
    clc
    rts
.endproc

;; Control $13: two bytes, an address in the card, whose byte goes to <Retries> for status code 5. A list of the wrong
;; length ends the call with <ERROR_BAD_CONTROL_PARAMETER> but still reads the byte at the address set before.
;; Out: carry = clear
.proc Peek
    jsr SetAddress
    lda (UserPointer)
    sta Retries
    clc
    rts
.endproc

;; Control $0C: three bytes, an address in the card and a byte to store there, which is read from the list's fifth
;; byte, not its third. A list of the wrong length ends the call with <ERROR_BAD_CONTROL_PARAMETER> but still stores
;; the byte, at the address set before.
;; Out: carry = clear
.proc Poke
    lda #$03
    jsr TakeAddress
    lda TransferBuffer + 4
    sta (UserPointer)
    clc
    rts
.endproc

;; Control $10: two bytes, an address in the card, for <Download>, <Peek> and <Poke>.
;; Out: carry = clear; ErrorCode = <ERROR_BAD_CONTROL_PARAMETER> for a list not two bytes long
.proc SetAddress
    lda #$02
    ; Falls into TakeAddress.
.endproc

;; Takes <UserPointer> from the list's first two bytes, if the list has the length expected.
;; In: A = the length
;; Out: carry = clear; ErrorCode = <ERROR_BAD_CONTROL_PARAMETER> (and <UserPointer> unchanged) if not
;; Entry:
;;   ToBadParameter = ends with <ERROR_BAD_CONTROL_PARAMETER>
.proc TakeAddress
    jsr CheckLength
    bne ToBadParameter
    lda TransferBuffer
    sta UserPointer
    lda TransferBuffer + 1
    sta UserPointer + 1
    clc
    rts
ToBadParameter:
    jmp Run::BadParameter
.endproc

;; Control $11: copies the control list to the card's RAM at <UserPointer>, leaving the pointer where it was. It copies
;; <Count> bytes and 256 more for each in <CountHigh>, with a <Count> of 0 counting 256, so a list a multiple of 256
;; bytes long copies 256 bytes too many.
;; Out: carry = clear; Count and CountHigh used up
.proc Download
    ldx UserPointer + 1
    ldy #$00
    lda #<TransferBuffer
    sta WorkPointer
    lda #>TransferBuffer
    sta WorkPointer + 1
Loop:
    lda (WorkPointer),y
    sta (UserPointer),y
    iny
    bne Counted
    inc WorkPointer + 1
    inc UserPointer + 1
Counted:
    dec Count
    bne Loop
    dec CountHigh
    bpl Loop
    stx UserPointer + 1
    clc
    rts
.endproc

;; Loads A, X, Y and the status from the list's first four bytes and jumps to the address in its next two; the code
;; there returns to the caller.
.proc CallUser
    lda TransferBuffer + 4
    sta WorkPointer
    lda TransferBuffer + 5
    sta WorkPointer + 1
    lda TransferBuffer + 3
    pha
    ldx TransferBuffer + 1
    ldy TransferBuffer + 2
    lda TransferBuffer
    plp
    jmp (WorkPointer)
.endproc

;; Compares the control list's length with A.
;; In: A = the length expected, below 256
;; Out: zero = set when the list is that long, Y = CountHigh
;; Keeps: A, X
.proc CheckLength
    ldy CountHigh
    bne Done
    cmp Count
Done:
    rts
.endproc

.endscope

;; Ejects a drive's disk, if it has one: turns the motor off and waits 200 ms if it is on, gives the eject command,
;; then waits up to about 2 s, polling every 10 ms, for the disk to leave, and forgets the disk once it has. Sets
;; <Retries> to 3, and <EjectDrive> to the drive while it works (a reset meanwhile finishes the eject).
;; In: X = the drive, enabled
;; Out: carry = clear; ErrorCode = <ERROR_IO> if the disk did not leave
;; Keeps: X
.proc EjectDisk
    stx EjectDrive
    lda #SENSE_NO_DISK
    jsr Drives::SenseLine
    bcs Done
    lda #SENSE_MOTOR_OFF
    jsr Drives::SenseLine
    bcs Eject
    lda #DRIVE_MOTOR_OFF
    jsr Drives::SendCommand
    lda #MOTOR_STOP_DELAY
    jsr DelayMilliseconds
Eject:
    lda #$03
    sta Retries
    lda #DRIVE_EJECT
    jsr Drives::SendCommand
    ldy #EJECT_POLLS
Wait:
    lda #EJECT_POLL_DELAY
    jsr DelayMilliseconds
    lda #SENSE_NO_DISK
    jsr Drives::SenseLine
    bcs Gone
    dey
    bne Wait
    lda #ERROR_IO
    sta ErrorCode
    bra Done
Gone:
    jsr Drives::ForgetDisk
Done:
    lda #$80
    sta EjectDrive
    clc
    rts
.endproc

;; How long <EjectDisk> lets the motor stop, in milliseconds.
MOTOR_STOP_DELAY = 200

;; How many times <EjectDisk> looks for the disk to have left.
EJECT_POLLS = $C3

;; How long <EjectDisk> waits between looks, in milliseconds.
EJECT_POLL_DELAY = 10

;; SmartPort STATUS ($00), and ProDOS's status call: the status lists, built in <TransferBuffer> for the host.
.scope Status

;; The length of <ControllerName>.
CONTROLLER_NAME_LENGTH = 30

;; The byte that ends a DIB in <Apple35Information> and <FdhdInformation>.
DIB_END = $FF

;; Unit 0's name, for status code 1.
ControllerName:
    .byte "APPLE UNIVERSAL 3.5 CONTROLLER"
.assert * - ControllerName = CONTROLLER_NAME_LENGTH, "The name's length."

;; Builds the status list for the status code in <ParameterLow>. Unit 0 takes code 0, the controller's eight bytes,
;; and code 1, its name. A drive takes code 0, its general status (the status byte and the block count, four bytes,
;; or five for an extended call); code 3, its DIB, which starts with the same bytes; and code 5, the last command's
;; result (<ErrorCode> and the seven bytes after it). Other codes answer <ERROR_BAD_CONTROL>; code 6 is tested apart
;; but answers it too.
;; Out: carry = clear; Count, CountHigh = the list's length and CardData = <TRANSFER_BUFFER_CODE>, or ErrorCode =
;;      the error
.proc Run
    stz Count
    stz CountHigh
    ldx Drive
    bpl ForDrive

    ; Unit 0.
    lda ParameterLow
    beq Controller
    cmp #$01
    bne BadCode

    ; Code 1: the controller's name, after its length.
    ldx #CONTROLLER_NAME_LENGTH
    stx TransferBuffer
CopyName:
    lda ControllerName - 1,x
    sta TransferBuffer,x
    dex
    bne CopyName
    ldx #CONTROLLER_NAME_LENGTH
    inx
    bra Done

    ; A drive: codes 0, 3 and 5.
ForDrive:
    ldx ParameterLow
    beq DriveStatus
    cpx #$03
    beq DriveStatus
    cpx #$05
    bne NotLastResult
    jmp LastResult
NotLastResult:
    cpx #$06
    bne BadCode
BadCode:
    lda #ERROR_BAD_CONTROL
    jmp SetError

    ; The list is X bytes long: gives it to the host, and lets the drive's motor go unless the call named
    ; the unit with bit 7 set (UnitWithHighBit).
Done:
    stx Count
    lda #TRANSFER_BUFFER_CODE
    sta CardData
    ldx Drive
    bit UnitWithHighBit
    bmi KeepDrive
    jsr Drives::Release
    clc
    rts
KeepDrive:
    clc
    rts

    ; Code 0 for unit 0: the number of units, then 0, $01 in byte 2 and $0100 in bytes 4 and 5.
Controller:
    lda UnitCount
    sta TransferBuffer
    ldx #$01
    lda #$00
ClearController:
    sta TransferBuffer,x
    inx
    cpx #$08
    bne ClearController
    lda #$01
    sta TransferBuffer + 2
    lda #$00
    sta TransferBuffer + 4
    lda #$01
    sta TransferBuffer + 5
ToDone:
    bra Done

    ; Code 5: the last command's result.
LastResult:
    ldx #$00
CopyResult:
    lda ErrorCode,x
    sta TransferBuffer,x
    inx
    cpx #$08
    bcc CopyResult
    bra Done

    ; Codes 0 and 3: the status byte. Bits 7, 6, 5 and 3: a block device that can be written, read and formatted;
    ; bit 4, a disk is in; bit 2, it is write protected; bit 0, for an extended call, the drive's switched latch
    ; is set (a disk taken out or put in), or a disk is in that was not at the last look.
DriveStatus:
    ldx Drive
    jsr Drives::ReadStatus
    php
    and Sense,x
    lsr a
    lsr a
    lsr a
    ora #$E8
    bvs NoDisk
    ora #$10
NoDisk:
    plp
    bmi Switched
    bvs StatusByte
    bit PreviousSense
    bvc StatusByte
Switched:
    bit CardCommand
    bvc StatusByte
    ora #$01
StatusByte:
    sta TransferBuffer

    ; The block count, three bytes, or four for an extended call.
    jsr Drives::CheckDisk
    bpl Blocks
    jsr Drives::IdentifyMedia
Blocks:
    ldx #$04
    ldy Drive
    lda BlockCount,y
    sta TransferBuffer + 1
    lda BlockCountHigh,y
    sta TransferBuffer + 2
    stz TransferBuffer + 3
    bit CardCommand
    bvc General
    stz TransferBuffer + 4
    inx
General:
    lda ParameterLow
    beq ToDone

    ; Code 3: the rest of the DIB, by the drive's kind, up to its end byte.
    ldy Drive
    lda DeviceKinds,y
    ldy #$00
    bit #$02
    beq CopyDib
    ldy #FdhdInformation - Apple35Information
CopyDib:
    lda Apple35Information,y
    sta TransferBuffer,x
    inx
    iny
    cmp #DIB_END
    bne CopyDib
    dex
    jmp Done
.endproc

;; An Apple 3.5 drive's DIB, after the status byte and block count: the name's length and the name, padded to 16;
;; the type, subtype and version; then <DIB_END>.
Apple35Information:
    .byte 8, "DISK 3.5        "
    .byte $01, $C0, $10, $10
    .byte DIB_END

;; An FDHD drive's DIB, as <Apple35Information>'s. The name's length leaves out "HD".
FdhdInformation:
    .byte 8, "DISK 3.5HD      "
    .byte $01, $C1, $10, $10
    .byte DIB_END

.endscope

;; The list FORMATOPTIONS gives: this header, then a <FormatOption> for each format.
.struct FormatOptionList
    OPTIONS .word ;; How many formats follow.
    SHOWN .word ;; How many to show: the same count here.
    DEFAULT .word ;; The format FORMAT writes by default.
    CURRENT .word ;; The disk's kind, from <MediaKind>.
.endstruct

;; One format in a <FormatOptionList>.
.struct FormatOption
    KIND .word ;; The format's kind, the number SETFORMAT takes.
    LINK .word ;; Left 0.
    TYPE .word ;; Its type, from <FormatOptions::Kinds>.
    BLOCKS .dword ;; Its blocks.
    BLOCK_SIZE .word ;; 512.
    INTERLEAVE .word ;; Its interleave.
    SIZE .word ;; Its size in KB.
.endstruct

;; The 3.5 controller's FORMATOPTIONS ($0B) and SETFORMAT ($0A): the formats a drive can write, and the one the next
;; FORMAT writes. A format kind is <MediaKind>'s number: 2 400K, 4 800K, 6 800K (with interleave 2), 8 720K, $0A 1440K,
;; and $0C, 1440K with interleave 1, which FORMATOPTIONS lists after $0A.
.scope FormatOptions

;; The kinds are even numbers below this.
KIND_LIMIT = $0D

;; Lists the formats a drive can write, after an eight-byte header, following each kind's link in <Kinds>: 800K at
;; 2:1 and 4:1 interleave (kinds 6 and 4) on an Apple 3.5 drive, and on an FDHD drive 1440K twice (kinds $0A and $0C),
;; 800K twice and 720K (kind 8). 400K (kind 2) is never listed. The default is 1440K when <MediaMode> says the
;; disk is high density, else 800K.
;; Out: carry = clear; Count, CountHigh = the list's length and CardData = <TRANSFER_BUFFER_CODE>, or ErrorCode =
;;      <ERROR_BAD_UNIT> for unit 0, or the error <FailBadParameter> gives when <ParameterLow> and <ParameterMiddle> ask
;;      for fewer bytes than the list has
.proc List
    ldx Drive
    bpl Find
    lda #ERROR_BAD_UNIT
    jmp SetError
Find:
    jsr Drives::CheckDisk
    bpl Clear
    jsr Drives::IdentifyMedia

    ; Clears the buffer (but for the second page's first byte), then the header.
Clear:
    ldx #$FF
ClearByte:
    stz TransferBuffer,x
    stz TransferBuffer + $100,x
    dex
    bne ClearByte
    lda #<(TransferBuffer + .sizeof(FormatOptionList))
    sta SecondBufferPointer
    lda #>(TransferBuffer + .sizeof(FormatOptionList))
    sta SecondBufferPointer + 1
    stz TransferBuffer + FormatOptionList::OPTIONS
    stz TransferBuffer + FormatOptionList::SHOWN
    ldx Drive
    lda MediaKind,x
    sta TransferBuffer + FormatOptionList::CURRENT
    lda #$02
    bit DeviceKinds,x
    beq Apple35

    ; An FDHD drive.
    lda #$0A
    sta TransferBuffer + FormatOptionList::DEFAULT
    lda MediaMode,x
    bit #$40
    bne Fdhd
    lda #$06
    sta TransferBuffer + FormatOptionList::DEFAULT
Fdhd:
    lda #$0A
    jsr Add
    lda #$06
    jsr Add
    lda #$08
    jsr Add
    bra Length

    ; An Apple 3.5 Drive.
Apple35:
    lda #$06
    sta TransferBuffer + FormatOptionList::DEFAULT
    lda #$06
    jsr Add

    ; The length, 16 bytes a format and the header, must fit what the host asked for.
Length:
    ldy #$00
    lda TransferBuffer + FormatOptionList::OPTIONS
    asl a
    asl a
    asl a
    asl a
    bcc AddHeader
    iny
AddHeader:
    clc
    adc #.sizeof(FormatOptionList)
    cpy ParameterMiddle
    bcc Fits
    beq CheckLow
TooShort:
    jmp FailBadParameter
CheckLow:
    cmp ParameterLow
    beq Fits
    bcs TooShort
Fits:
    sta Count
    sty CountHigh
    lda #TRANSFER_BUFFER_CODE
    sta CardData
    clc
    rts
.endproc

;; Adds a format to the list, and the formats linked after it in <Kinds>.
;; In: A = the format kind, SecondBufferPointer = where its entry goes
;; Out: SecondBufferPointer = past the last entry added
.proc Add
    inc TransferBuffer + FormatOptionList::OPTIONS
    inc TransferBuffer + FormatOptionList::SHOWN
    ldy #FormatOption::KIND
    sta (SecondBufferPointer)
    tax
    lda Kinds,x
    and #$0F
    ldy #FormatOption::TYPE
    sta (SecondBufferPointer),y
    lda Kinds,x
    lsr a
    lsr a
    lsr a
    lsr a
    ldy #FormatOption::INTERLEAVE
    sta (SecondBufferPointer),y
    lda BlockCounts,x
    ldy #FormatOption::BLOCKS
    sta (SecondBufferPointer),y
    iny
    lda BlockCounts + 1,x
    sta (SecondBufferPointer),y
    ldy #FormatOption::BLOCK_SIZE + 1
    lda #>512
    sta (SecondBufferPointer),y

    ; The size in KB, half the blocks.
    lda BlockCounts + 1,x
    lsr a
    ldy #FormatOption::SIZE + 1
    sta (SecondBufferPointer),y
    lda BlockCounts,x
    ror a
    dey
    sta (SecondBufferPointer),y

    ; The next entry, and the next kind.
    lda SecondBufferPointer
    clc
    adc #.sizeof(FormatOption)
    sta SecondBufferPointer
    bcc Next
    inc SecondBufferPointer + 1
Next:
    lda Kinds + 1,x
    beq Done
    bpl Add
Done:
    rts
.endproc

;; One format kind's entry in <FormatOptions::Kinds>.
;; Parameters:
;;   interleave = its interleave
;;   type = its type, which FORMATOPTIONS gives
;;   next = the kind listed after it, or 0
.macro FormatKind interleave, type, next
    .byte (interleave << 4) | type, next
.endmacro

;; Each format kind's interleave and type, and the kind listed after it, indexed by the kind: 0 (none), 2, 4, 6, 8,
;; $0A and $0C.
Kinds:
    FormatKind 0, 0, 0
    FormatKind 2, 5, 0
    FormatKind 4, 5, 0
    FormatKind 2, 5, $04
    FormatKind 1, 6, 0
    FormatKind 2, 4, $0C
    FormatKind 1, 4, 0
.assert * - Kinds = KIND_LIMIT + 1, "An entry for each kind."

;; Each format kind's block count, indexed by the kind (0 and $0E: none).
BlockCounts:
    .word 0, 800, 1600, 1600, 1440, 2880, 2880, 0

;; Chooses the format the next FORMAT writes, and its interleave. Kind 0 puts back the defaults, through
;; <Format::ForgetChoice>, which acts only on a drive with a kind chosen, so kind 2 is stored first. A bad interleave is
;; refused after the kind is stored.
;; In: ParameterLow = the format kind (0, or an even number below $0D), ParameterMiddle = 0, ParameterHigh = the
;;     interleave (below 13), or 0 for the kind's own
;; Out: carry = clear; ErrorCode = <ERROR_BAD_CONTROL> for a bad kind or interleave; CardData = 0
.proc Set
    lda ParameterMiddle
    beq CheckKind
Bad:
    jmp Control::Run::BadCode
CheckKind:
    lda ParameterLow
    cmp #KIND_LIMIT
    bcs Bad
    and #$01
    bne Bad
    ldx Drive
    lda ParameterLow
    bne Kind
    lda #$02
    sta FormatKind,x
    jsr Format::ForgetChoice
    bra Done
Kind:
    sta FormatKind,x
    tay
    lda Kinds,y
    lsr a
    lsr a
    lsr a
    lsr a
    sta FormatInterleave,x
    lda ParameterHigh
    beq Done
    cmp #Control::INTERLEAVE_LIMIT
    bcs Bad
    sta FormatInterleave,x
Done:
    stz CardData
    clc
    rts
.endproc

.endscope

