; retrocore: style=strict
;; The card's firmware: reading and writing blocks
;;
;; The handlers of the commands that move blocks: READBLOCK, WRITEBLOCK, SmartPort's tagged READ and WRITE, the
;; slot ROM's boot read, and the card's own READAHEAD and READSPAN. A read fills the cache with the rest of the
;; block's track (<Cache>), handing the host its block as soon as it is read; <BlockMap::Locate> finds where a block
;; is.

; Other values.

;; The tag bytes before a block's data in SmartPort's READ and WRITE.
TAG_SIZE = 12

;; The bytes of a tagged block: its tags, then its 512 bytes of data.
TAGGED_BLOCK_SIZE = TAG_SIZE + 512

;; The retries a block's read or write gets.
BLOCK_RETRIES = 6

;; A track's sector in <SectorFlags>: read, or not wanted by READSPAN.
SECTOR_DONE = $40

;; A track's sector in <SectorFlags>: not one of the track's.
SECTOR_NOT_WANTED = $C0

;; <ReadState>'s bit 7: read the block asked for and no more of its track.
READ_STATE_BLOCK_ONLY = $80

;; <ReadState>'s bit 6: the block has been handed to the host, and the card goes on filling the cache.
READ_STATE_HANDED_OVER = $40

;; The buffer code of <InterleaveMap>, where READSPAN lists what it read.
SPAN_LIST_CODE = InterleaveMap >> 9

;; READSPAN's buffer code for a sector it could not read.
SPAN_FAILED = $A7

;; Counts a retry: <ResultA> and <ResultX> tally the errors, and <Retries> counts down.
;; Out: carry = set with ErrorCode = <ERROR_IO> when the retries are used up; otherwise A = <DiskErrors>, which is
;;   cleared
;; Keeps: X, Y
.proc CountRetry
    inc ResultA
    bne CountDown
    inc ResultX
CountDown:
    dec Retries
    bpl Again
    lda #ERROR_IO
    sta ErrorCode
    sec
    rts
Again:
    lda DiskErrors
    stz DiskErrors
    clc
    rts
.endproc

;; SmartPort READ ($08) and WRITE ($09): a 524-byte block with its 12 tag bytes, on a 400K or 800K GCR disk. The
;; byte count must be <TAGGED_BLOCK_SIZE>, and the address parameter is the block number.
;;
;; The read is taken only when <CardState> is 1, READBLOCK's command, which never reaches this handler: READ
;; arrives as $08, so as the code stands both READ and WRITE go to <WriteBlock>, and a READ writes the buffer's
;; bytes to the block. The read's copy also takes the data from $0E00-$0FFF, past the buffer <ReadTaggedBlock>
;; reads into ($0C00-$0DFF).
;; Out: on the read, the tags and data at $0C00-$0E0B and CardData = 6; on an error, ErrorCode = the error and
;;   CardData = 0
.proc ReadWriteTagged
    lda #ERROR_BAD_UNIT
    ldx Drive
    bpl CheckDisk
Fail:
    jmp SetError

    ; A 400K or 800K disk, its format found again if it was switched. The check reads MediaKind at Y, which
    ; Drives::CheckDisk leaves 0 and Drives::IdentifyMedia leaves a media kind, so it reads drive 1's kind, or a byte
    ; past it, whatever the drive.
CheckDisk:
    jsr Drives::CheckDisk
    bpl Known
    jsr Drives::IdentifyMedia
Known:
    bcs Fail
    lda MediaKind,Y
    cmp #MEDIA_800K
    beq CheckCount
    cmp #MEDIA_400K
    beq CheckCount
    lda #ERROR_IO
    jmp SetError
CheckCount:
    lda CountHigh
    cmp #>TAGGED_BLOCK_SIZE
    beq CheckCountLow
BadCount:
    jmp FailBadParameter
CheckCountLow:
    lda Count
    cmp #<TAGGED_BLOCK_SIZE
    bne BadCount

    ; The block number is the address parameter.
    lda ParameterHigh
    sta ParameterLow
    lda Parameter3
    sta ParameterMiddle
    stz ParameterHigh
    stz Parameter3
    dec TagCall
    lda #TransferBuffer >> 9
    sta BufferCode
    lda CardState
    cmp #COMMAND_READ_BLOCK
    beq Read
    jmp WriteBlock

    ; The tags, then the data after them.
Read:
    jsr ReadTaggedBlock
    bcs Done
    ldy #TAG_SIZE - 1
CopyTags:
    lda TagBytes,Y
    sta TransferBuffer,Y
    dey
    bpl CopyTags
    ldy #0
CopyData:
    lda TransferBuffer+$200,Y
    sta TransferBuffer+TAG_SIZE,Y
    lda TransferBuffer+$300,Y
    sta TransferBuffer+TAG_SIZE+$100,Y
    iny
    bne CopyData
    lda BufferCode
    stz ErrorCode
    sta CardData
Done:
    clc
    rts
.endproc

;; Reads the block in <ParameterLow> and <ParameterMiddle>, with its tags (to <TagBytes>), into <BufferCode>'s buffer,
;; without the cache.
;; Out: carry = set if it failed, with ErrorCode = the error and CardData = 0
.proc ReadTaggedBlock
    jsr CheckBlock
    bcs Fail
    lda #BLOCK_RETRIES
    sta Retries
    stz SwimState
    jsr Drives::MotorOn
    jsr BlockMap::Locate
    bcs Fail

    ; Up to eight address fields for each sector in the track.
    asl a
    asl a
    asl a
    sta SectorCount
Seek:
    jsr Drives::Seek
    bcs IoError
ReadAgain:
    lda BufferCode
    jsr Cache::PointAtBuffer
    jsr Drives::WaitReadyForever
NextField:
    jsr ReadAddressField
    bcc Found
    jsr CountRetry
    bcs IoError
    bit #DISK_ERROR_WRONG_TRACK
    bne Seek
    bit #DISK_ERROR_NO_FIELD
    beq BadField
    jsr Drives::Recalibrate
    bcc Seek
BadField:
    bit #DISK_ERROR_BAD_FIELD
    beq IoError
NotThisOne:
    dec SectorCount
    bne NextField
IoError:
    lda #ERROR_IO
Fail:
    jsr SetError
    sec
    rts

    ; The sector wanted: its data field.
Found:
    lda AddressSector
    cmp Sector
    bne NotThisOne
    jsr ReadDataField
    bcc Done
    jsr CountRetry
    bcc ReadAgain
    bra IoError
Done:
    clc
    rts
.endproc

;; SmartPort READBLOCK ($01), and ProDOS's read: hands over the block from the cache, or reads its track into the
;; cache, handing the host the block's buffer as soon as it is read and going on with the rest of the track until
;; the host sends its next command.
;;
;; A tagged call (<ReadWriteTagged>) on an MFM disk sets <TagError> to <ERROR_BAD_CONTROL> and returns without an
;; answer.
;; Out: CardData = the buffer code the host copies from, or 0 with ErrorCode = the error; carry = set when the block
;;   was handed over and the card went on reading (the main loop then runs the host's next command at once)
.proc ReadBlock
    lda #ERROR_BAD_UNIT
    ldx Drive
    bpl CheckDisk
Fail:
    jmp SetError

    ; A disk, its format found again if it was switched, with the block on it.
CheckDisk:
    jsr Drives::CheckDisk
    bpl Known
    jsr Drives::IdentifyMedia
Known:
    bcs Fail
    jsr CheckBlock
    bcs Fail
    lda #$80
    sta Reading

    ; An MFM disk: no tags.
    ldx Drive
    lda #MEDIA_MODE_MFM
    bit MediaMode,X
    beq Locate
    bit TagCall
    bpl Mfm
    lda #ERROR_BAD_CONTROL
    sta TagError
    rts
Mfm:
    jsr Swim::UseMfm

    ; Where the block is; the address fields to look at, $60 on a GCR disk and $80 on an 18-sector MFM one.
Locate:
    jsr BlockMap::Locate
    bcs Fail
    sta SectorsPerTrack
    and #$10
    asl a
    adc #$60
    sta SectorTries
    jsr Cache::Find
    bcc ReadTrack
    sta CardData
    clc
    rts

    ; Not in the cache: read the track. ResultStatus counts the seeks and ResultY the sectors besides the block
    ; that may fail.
ReadTrack:
    lda #BLOCK_RETRIES
    sta Retries
    lda #4
    sta ResultStatus
    lda #20
    sta ResultY
    jsr Drives::MotorOn

    ; Every sector of the track is wanted.
    lda #0
    sta SpanStart
    lda SectorsPerTrack
    sta SpanEnd
    dec a
    sta SectorCount
    lda #SECTOR_NOT_WANTED
    ldx SectorsPerTrack
MarkSectors:
    sta SectorFlags,X
    cpx SpanStart
    bcc NextMark
    cpx SpanEnd
    bcs NextMark
    stz SectorFlags,X
NextMark:
    dex
    bpl MarkSectors
    lda CacheOption
    sta ReadState
    bra Seek
Recalibrate:
    jsr Drives::Recalibrate
    bcs IoError
Seek:
    dec ResultStatus
    bmi IoError
    jsr Drives::Seek
    bcs IoError
    jsr Drives::WaitReady
    bcc NextField
Offline:
    lda #ERROR_OFFLINE
    bra Error

    ; The next address field.
NextField:
    stz DiskErrors
    jsr ReadAddressField
    bcc Found
    lda DiskErrors
    bit #DISK_ERROR_WRONG_TRACK
    bne Seek
    bit #DISK_ERROR_BAD_FIELD
    beq NoField
    dec SectorTries
    beq IoError

    ; A bad field: recalibrate once half the tries left (bits 0-5) equal the track's sectors; otherwise read on,
    ; or seek again while bit 3 of half the tries left is set.
    lda SectorTries
    and #$3F
    lsr a
    cmp SectorsPerTrack
    beq TrackOfBadFields
    bit #$08
    beq NextField
    bra Seek
TrackOfBadFields:
    bit ReadState
    bvc Recalibrate
HandedOver:
    jsr Swim::EnsureIwm
    sec
    rts

    ; No field: the disk may be gone, or the head lost.
NoField:
    bit #DISK_ERROR_NO_FIELD
    beq IoError
    bit ReadState
    bvs HandedOver
    lda #SENSE_NO_DISK
    jsr Drives::SenseLine
    bcs Offline
    dec ResultStatus
    bmi IoError
    jsr Drives::Recalibrate
    stz DiskErrors
    jsr ReadAddressField
    bcc Seek
    ldx Drive
    jsr Drives::ForgetDisk
IoError:
    lda #ERROR_IO
Error:
    bit ReadState
    bvs HandedOver
    jmp SetError

    ; A field read: the block's sector is handed over as soon as its data is read.
Found:
    ldx AddressSector
    cpx Sector
    bne OtherSector
    bit ReadState
    bvs HandedOver
    jsr Cache::ClaimSlot
    stz Reading
    jsr ReadDataField
    bcc HandOver
    jsr CountRetry
    bcs IoError
    bra TryNext
HandOver:
    lda BufferCode
    sta CardData
    lda SectorCount
    ora #$80
    sta CardState
    lda #READ_STATE_HANDED_OVER
    tsb ReadState
    bra Cached

    ; Another sector of the track: into the cache, unless it is there already.
OtherSector:
    bit ReadState
    bmi TryNext
    bit SectorFlags,X
    bvs AlreadyDone
    ldy Cache::SectorSlots,X
    lda CacheOwners-1,Y
    bmi ReadOther
    cmp Drive
    bne ReadOther
    lda CacheCylinders-1,Y
    cmp Cylinder
    bne ReadOther
    lda CacheSectors-1,Y
    cmp AddressSector
    bne ReadOther
    lda #SECTOR_DONE
    sta SectorFlags,X
    bra CheckDone

    ; A sector read already: once the block is handed over, wait a little for the host's next command.
AlreadyDone:
    bit ReadState
    bvc TryNext
    ldx #8
Wait:
    lda #$CC
WaitInner:
    bit CardState
    bpl Finish
    dec a
    bne WaitInner
    dex
    bne Wait
    bra TryNext

    ; Too many sectors besides the block that fail stop the filling.
ReadOther:
    jsr Cache::ClaimSlot
    jsr ReadDataField
    bcc Cached
    dec ResultY
    bpl CheckDone
    lda #READ_STATE_BLOCK_ONLY
    tsb ReadState
    bra CheckDone
Cached:
    ldx AddressSector
    lda #SECTOR_DONE
    sta SectorFlags,X
    lda AddressSector
    jsr Cache::Record
    bcc CheckDone
ToIoError:
    jmp IoError

    ; Done once the block is handed over and the track is read, or the host has sent a command.
CheckDone:
    bit ReadState
    bvc TryNext
    bmi Finish
    dec SectorCount
    beq Finish
    lda CardState
    bpl Finish
TryNext:
    jsr Swim::EnsureIwm
    dec SectorTries
    beq ToIoError
    jmp NextField
Finish:
    jsr Swim::EnsureIwm
    bit ReadState
    bvs Continued
    clc
    rts
Continued:
    sec
    rts
.endproc

;; SmartPort WRITEBLOCK ($02), and ProDOS's write: asks the host for the block in <BufferCode>'s buffer and writes it;
;; on a IIgs the card starts nibblizing while the host is still copying (<WriteProgress>).
;;
;; A tagged call on an MFM disk sets <TagError> to <ERROR_BAD_CONTROL> and returns without an answer.
;; Out: ErrorCode = the error, or unchanged; carry = clear
.proc WriteBlock
    lda #ERROR_BAD_UNIT
    ldx Drive
    bmi Fail
    jsr Drives::CheckDisk
    bpl Known
    jsr Drives::IdentifyMedia
Known:
    bcc Writable
Fail:
    jmp SetError

    ; A disk that is not write-protected, with the block on it.
Writable:
    bne Fail
    jsr CheckBlock
    bcs Fail

    ; An MFM disk: no tags.
    ldx Drive
    lda #MEDIA_MODE_MFM
    bit MediaMode,X
    beq Locate
    bit TagCall
    bpl Mfm
    lda #ERROR_BAD_CONTROL
    sta TagError
    rts
Mfm:
    jsr Swim::UseMfm

    ; Where the block is: ResultStatus counts the seeks; the address fields to look at are $70 on a GCR disk
    ; with 8 to 12 sectors and $80 on an 18-sector MFM one.
Locate:
    lda #BLOCK_RETRIES
    sta Retries
    lda #3
    sta ResultStatus
    jsr BlockMap::Locate
    bcs Fail
    sta SectorsPerTrack
    and #$18
    asl a
    adc #$60
    sta SectorTries
    ldx Sector
    jsr Cache::ClaimSlot

    ; A IIgs's host code paces the card through WriteProgress, unless this is the self-test's call, a tagged one or
    ; one on an MFM disk.
    stz WriteProgress
    bit TestCall
    bmi AskHost
    bit SharedExpansion+HOST_TYPE_OFFSET
    bvc AskHost
    bit TagCall
    bmi AskHost
    bit SwimState
    bmi AskHost
    dec WriteProgress

    ; Asks the host for the data while the head moves.
AskHost:
    lda BufferCode
    sta CardData
    jsr Drives::MotorOn
    jsr Drives::Seek
    bcs IoError
    bit TestCall
    bmi Prepare
    bit WriteProgress
    bmi PrepareData
WaitForHost:
    lda CardData
    bpl WaitForHost
PrepareData:
    bit TagCall
    bpl Prepare
    jsr NibblizeSectorWithTags
    bra WaitReady
Prepare:
    jsr NibblizeSector
WaitReady:
    jsr Drives::WaitReady
    bcc NextField
Offline:
    lda #ERROR_OFFLINE
    bra Error

    ; The next address field.
NextField:
    jsr ReadAddressField
    bcc Found
    lda DiskErrors
    bit #DISK_ERROR_WRONG_TRACK
    bne Seek
    bit #DISK_ERROR_BAD_FIELD
    beq NoField
    dec SectorTries
    beq IoError

    ; A bad field: recalibrate once half the tries left (bits 0-5) equal the track's sectors; otherwise read on,
    ; or seek again while bit 3 of half the tries left is set.
    lda SectorTries
    and #$3F
    lsr a
    cmp SectorsPerTrack
    beq Recalibrate
    bit #$08
    beq NextField
    bra Seek
Recalibrate:
    jsr Drives::Recalibrate
    bcs IoError
Seek:
    dec ResultStatus
    bmi IoError
    jsr Drives::Seek
    bcc WaitReady
    bra IoError

    ; No field: the disk may be gone, or the head lost.
NoField:
    bit #DISK_ERROR_NO_FIELD
    beq IoError
    lda #SENSE_NO_DISK
    jsr Drives::SenseLine
    bcs Offline
    bra Recalibrate

    ; The block's sector: write its data field, and keep the sector in the cache.
Found:
    lda AddressSector
    cmp Sector
    beq Write
    dec SectorTries
    beq IoError
    jsr Swim::EnsureIwm
    bra NextField
Write:
    jsr WriteDataField
    bcs IoError
    bit TestCall
    bmi Done
    lda Sector
    jsr Cache::Record
Done:
    clc
    rts
IoError:
    lda #ERROR_IO
Error:
    sta ErrorCode
    clc
    rts
.endproc

;; The boot command (<COMMAND_BOOT>): READBLOCK of block 0 of unit 1, as a ProDOS call, or <ERROR_NO_DRIVE> when there
;; is no unit 1. A SmartPort bus device as unit 1 is read through the bus.
.proc BootRead
    stz ErrorCode
    stz Side
    stz Track
    stz Cylinder
    jsr Cache::Flush

    ; A ProDOS READBLOCK of block 0, unit 1.
    lda #COMMAND_READ_BLOCK
    sta CardState
    ora #$80
    sta CardCommand
    stz ParameterLow
    stz ParameterMiddle
    stz ParameterHigh
    stz Drive
    lda #1
    sta CardUnit
    stz SavedDrive
    ldx SavedDrive
    lda DeviceKinds,X
    beq NoDrive
    bmi BusDevice
    jsr Drives::ForgetDisk
    jmp RunCommand::CallHandler
BusDevice:
    lda #$FF
    jsr DelayMillisecondPairs
    jmp RunCommand::PassToBus
NoDrive:
    lda #ERROR_NO_DRIVE
    sta ErrorCode
    stz CardData
    clc
    rts
.endproc

    ; Unused, to put the tables below on a page.
    .res $E200-*

;; The high two bits of the first of the three bytes a 6-and-2 auxiliary nibble completes, by the nibble's six bits,
;; in bits 6 and 7, for <ReadGcrDataField>.
GcrHighBits1:
.repeat 64, I
    .byte ((I >> 4) & 3) << 6
.endrepeat

;; The same for the second byte.
GcrHighBits2:
.repeat 64, I
    .byte ((I >> 2) & 3) << 6
.endrepeat

;; The same for the third byte.
GcrHighBits3:
.repeat 64, I
    .byte ((I >> 0) & 3) << 6
.endrepeat

;; Command <COMMAND_READ_AHEAD>: checks a run of blocks (<Parameter4> and <Parameter5> more after the first) and works
;; out how many of them lie in the first block's track, for the host in <Count>, then waits briefly for the next
;; command.
;;
;; Two bugs: the run's last block's high byte is stored in <ParameterLow>, not <ParameterMiddle>, so the check is of
;; another block; and when that check fails, the two bytes of the block number pushed meanwhile stay on the stack,
;; and <SetError>'s RTS returns through them.
;; Out: carry = set (the host's next command is run at once); Count = the blocks, CardData = 0
.proc ReadAhead
    lda #ERROR_BAD_UNIT
    ldx Drive
    bpl CheckDisk
Fail:
    jmp SetError
CheckDisk:
    jsr Drives::CheckDisk
    bpl Known
    jsr Drives::IdentifyMedia
Known:
    bcs Fail
    jsr CheckBlock
    bcs Fail
    lda #$80
    sta Reading
    ldx Drive
    lda #MEDIA_MODE_MFM
    bit MediaMode,X
    beq CheckEnd
    jsr Swim::UseMfm

    ; The run's end must be on the disk.
CheckEnd:
    lda ParameterMiddle
    pha
    lda ParameterLow
    pha
    clc
    adc Parameter4
    sta ParameterLow
    lda ParameterMiddle
    adc Parameter5
    sta ParameterLow
    jsr CheckBlock
    bcs Fail
    pla
    sta ParameterLow
    pla
    sta ParameterMiddle

    ; The blocks left in the first block's track, but no more than the run.
    jsr BlockMap::Locate
    bcs Fail
    sta SectorsPerTrack
    stz CountHigh
    lda SectorsPerTrack
    sec
    sbc Sector
    sta SectorCount
    ldy Parameter5
    bne SetCount
    cmp Parameter4
    beq SetCount
    bcc SetCount
    lda Parameter4
SetCount:
    sta Count
    stz CardData

    ; Ready for the next command, which runs at once if it comes within about 1,500 passes.
    lda #$FF
    sta CardState
    lda #5
    sta WorkPointer+1
    stz WorkPointer
Wait:
    dec WorkPointer
    bne Check
    dec WorkPointer+1
    bmi Done
Check:
    lda CardState
    bmi Wait
Done:
    sec
    rts
.endproc

;; Command <COMMAND_READ_SPAN>: reads the sectors of a run of blocks (<Parameter4> and <Parameter5> blocks, the
;; first included) that share a cylinder, and lists them in <InterleaveMap> for the host: at $0600 how many were read,
;; at $0601 1 if one failed, and from $0602 each one's buffer code (<SPAN_FAILED> for one that failed). The
;; sectors' cache slots stay claimed (filling) until the cache is next flushed.
;; Out: carry = set when all were read (the host's next command is run at once); otherwise ErrorCode = the error
.proc ReadSpan
    lda #ERROR_BAD_UNIT
    ldx Drive
    bpl CheckDisk
Fail:
    jmp SetError
CheckDisk:
    jsr Drives::CheckDisk
    bpl Known
    jsr Drives::IdentifyMedia
Known:
    bcs Fail
    jsr CheckBlock
    bcs Fail
    lda #$80
    sta Reading
    ldx Drive
    lda #MEDIA_MODE_MFM
    bit MediaMode,X
    beq Locate
    jsr Swim::UseMfm

    ; The first block's place, then the last block's, which must be on the same cylinder.
Locate:
    jsr BlockMap::Locate
    bcs Fail
    sta SectorsPerTrack
    lda Sector
    sta SpanFirst
    lda Cylinder
    sta SpanCylinder
    lda Parameter4
    clc
    adc ParameterLow
    sta ParameterLow
    lda Parameter5
    adc ParameterMiddle
    sta ParameterMiddle
    lda ParameterLow
    bne LastBlock
    dec ParameterMiddle
LastBlock:
    dec ParameterLow
    jsr CheckBlock
    bcs Fail
    jsr BlockMap::Locate
    bcs Fail
    lda Cylinder
    cmp SpanCylinder
    beq ClearList
    lda #ERROR_BAD_BLOCK
    jmp SetError

    ; The list empty, the sectors of the span wanted, four tries each.
ClearList:
    stz InterleaveMap
    stz InterleaveMap+1
    ldx SectorsPerTrack
Clear:
    dex
    stz InterleaveMap+2,X
    bne Clear
    lda SpanFirst
    sta SpanStart
    lda Sector
    inc a
    sta SpanEnd
    sec
    sbc SpanFirst
    sta SectorCount
    asl a
    asl a
    sta Retries
    lda #SECTOR_DONE
    ldx SectorsPerTrack
    stx AddressSector
MarkSectors:
    sta SectorFlags,X
    cpx SpanStart
    bcc NextMark
    cpx SpanEnd
    bcs NextMark
    stz SectorFlags,X
NextMark:
    dex
    bpl MarkSectors
    lda #SPAN_LIST_CODE
    sta CardData

    ; Four address fields for each sector in the track, and two seeks.
    lda SectorsPerTrack
    asl a
    asl a
    inc a
    sta SectorTries
    lda #2
    sta ResultStatus
    jsr Drives::MotorOn
    bra Seek
Recalibrate:
    jsr Drives::Recalibrate
    bcs ToIoError
Seek:
    dec ResultStatus
    bmi ToIoError
    jsr Drives::Seek
    bcs ToIoError
    jsr Drives::WaitReady
    bcc NextField
Offline:
    lda #ERROR_OFFLINE
    bra Error
LeaveIsm:
    jsr Swim::EnsureIwm

    ; The next address field.
NextField:
    stz DiskErrors
    jsr ReadAddressField
    bcc Found
    lda DiskErrors
    bit #DISK_ERROR_WRONG_TRACK
    bne Seek
    bit #DISK_ERROR_BAD_FIELD
    bne BadField
    bit #DISK_ERROR_NO_FIELD
    bne Offline
ToIoError:
    bra IoError

    ; A bad field: recalibrate once the tries left (which good fields also count down) equal the track's sectors;
    ; otherwise read on, or seek again while bit 3 of the tries left is set.
BadField:
    dec SectorTries
    beq IoError
    lda SectorTries
    cmp SectorsPerTrack
    bne SeekOrNext
    bra Recalibrate
SeekOrNext:
    bit #$08
    beq NextField
    bra Seek

    ; A sector of the span: read it and list its buffer.
Found:
    ldx AddressSector
    bit SectorFlags,X
    bvs Skip
    jsr Cache::ClaimSlot
    jsr ReadDataField
    bcs DataFailed
    ldx AddressSector
    lda #SECTOR_DONE
    sta SectorFlags,X
    txa
    sec
    sbc SpanFirst
    tax
    lda BufferCode
    sta InterleaveMap+2,X
    inc InterleaveMap
    dec SectorCount
    beq Read
    bra Next

    ; Another sector: a pause whose test of Scratch, just cleared, changes nothing.
Skip:
    stz Scratch
    ldx #8
Pause:
    lda #$CC
PauseInner:
    bit Scratch
    bpl PauseNext
PauseNext:
    dec a
    bne PauseInner
    dex
    bne Pause
Next:
    dec SectorTries
    bne LeaveIsm
    bra IoError

    ; A data field that failed: retried until the tries are used up, then listed as failed.
DataFailed:
    dec Retries
    bpl LeaveIsm
    lda AddressSector
    sec
    sbc SpanFirst
    tax
    lda #SPAN_FAILED
    sta InterleaveMap+2,X
IoError:
    lda #ERROR_IO
Error:
    sta ErrorCode
    lda #1
    sta InterleaveMap+1
    clc
    rts

    ; All read: ready for the next command, which runs at once if it comes within about 1,500 passes.
Read:
    lda #$FF
    sta CardState
    lda #5
    sta WorkPointer+1
    stz WorkPointer
Wait:
    dec WorkPointer
    bne Check
    dec WorkPointer+1
    bmi Done
Check:
    lda CardState
    bmi Wait
Done:
    sec
    rts
.endproc

    ; Unused, to put ReadAddressField on a page: GcrDecode is indexed from it.
    .res $E500-*
