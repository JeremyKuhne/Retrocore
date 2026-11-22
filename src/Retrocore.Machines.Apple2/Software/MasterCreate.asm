; retrocore: style=strict
;; DOS 3.3 System Master: MASTER CREATE, which writes the master's DOS image to other disks
;;
;; The binary file MASTER CREATE from the 1980 Apple II Plus or ROMCARD System Master (680-0051-00 and 680-0051-01).
;; DOS loads its $06FF bytes at $0800 and starts it there. The 1982 master has the same code but different copyright
;; text. Assembles byte-identically to that file; SystemMasterBasicTests checks it.
;;
;; It reads the first 37 sectors of the master disk, the relocator and DOS as the master holds them, into
;; $1200-$36FF, asks for a greeting program's name, and writes the image to an initialized disk, which then boots
;; like a master on any memory size (docs/Dos.md). It changes the greeting name and volume fields in the image, but
;; does not create or catalog the greeting program. On exit it asks for a system disk and starts the disk
;; controller's boot ROM.

.cpu Mos6502

; DOS's equates include the IIe's equates and the Monitor's entry points.
.include "../Roms/Dos/Equates.asm"
.include "../Roms/System/FirmwareEquates.asm"

; The Monitor's line input and DOS's page-3 vector, which are labels rather than equates in their sources.

;; The Monitor's line input, at $FD6A: prints the prompt character and reads a line into the input buffer, with its
;; length in X.
;; Also: GETLN (A2RM78, A2RM79, IIEROM82, IIETRM85)
GetLine = $FD6A

;; DOS's page-3 jump to RWTS, through DISKIO, which carries out the request in the IOB whose address is in A (high)
;; and Y (low).
RwtsJump = $03D9

;; DOS's page-3 routine that returns the address of DOS's own IOB in A (high) and Y (low).
LocateIobJump = $03E3

; The IOB's fields this program reads from DOS's (IoBlock.asm has the layout).

;; The offset of an IOB's slot, times 16.
IOB_SLOT_TIMES_16 = 1

;; The offset of an IOB's drive.
IOB_DRIVE = 2

;; Inherit: <Dos33:RWTS_READ>
RWTS_READ = 1

;; Inherit: <Dos33:RWTS_WRITE>
RWTS_WRITE = 2

;; The size of an IOB less one, the last byte <PrepareRequest> copies, which is one more than the 17 that
;; <RequestTemplate> holds.
REQUEST_LAST = $11

;; A pointer this program uses for messages, DOS's IOB and the boot ROM, and where it keeps the input's length.
Pointer = $F0

; The master image in memory, and the fields in it this program reads and changes. The image's relocator and DOS
; are one page above their addresses in the master build.

;; The first of the 37 sector buffers.
ImageBuffer = $1200

;; The first byte after the image.
ImageBufferEnd = $3700

;; The volume in the boot loader's IOB.
ImageBootVolume = $13EB

;; The relocator's first byte, <Dos33:ImageStart>, a JMP.
ImageRelocatorStart = $1C00

;; The low byte of DOS's <Dos33:FileNameAddress>, the address of <Dos33:FileName>.
ImageFileNameAddress = $1E06

;; DOS's <Dos33:WriteStartAddress>, which names the relocator's first byte.
ImageWriteStartAddress = $1E0C

;; The low byte of the V option's value, <Dos33:KeywordVolume>.
ImageVolumeOption = $2B66

;; DOS's <Dos33:FileName>, the 30-character greeting name DOS runs after a boot.
ImageFileName = $2B75

;; The DOS release byte in DOS's VTOC buffer.
ImageDosRelease = $34BE

;; What the low byte of a master's <Dos33:FileName> address, $2A75, exclusive-ored with the high byte of its relocator's
;; address, $1B00, gives: a check that the image is a master's.
IMAGE_CHECK = $75^$1B

;; The DOS release byte of DOS 3.3.
RELEASE_DOS_33 = 4

;; A JMP's opcode, which the master image starts with.
JMP_OPCODE = $4C

;; The number of sectors on a track.
SECTORS_PER_TRACK = 16

;; The page of slot 0's ROM space; a slot's boot ROM is at $Cn00.
SLOT_ROM_PAGE = $C0

;; A blank, with bit 7 set.
BLANK = $A0

;; The length of a file name.
NAME_LENGTH = 30

; The rows the screen is cleared to before each message.

;; Where the title starts.
TITLE_ROW = 12

;; Where the name prompt, the write errors and the reboot prompt start.
PROMPT_ROW = 10

;; Where the read error and invalid image messages start.
ERROR_ROW = 8

;; Where the success message starts.
SUCCESS_ROW = 6

;; Where the name summary starts.
SUMMARY_ROW = 2

; The messages, by their number in MessagePointers.

;; The title and copyright.
TEXT_TITLE = 0

;; Asks for the greeting program's name.
TEXT_NAME_PROMPT = 1

;; Reminds that the program itself is not created, and shows the name.
TEXT_NAME_SUMMARY = 2

;; Asks for the disk to write.
TEXT_INSERT_TARGET = 3

;; The disk is written.
TEXT_SUCCESS = 4

;; Offers to try again.
TEXT_RETRY = 5

;; Asks for a system disk to boot.
TEXT_REBOOT = 6

;; The image could not be read.
TEXT_READ_ERROR = 7

;; The image in memory is not a master's.
TEXT_INVALID_IMAGE = 8

;; The disk could not be written.
TEXT_WRITE_ERROR = 9

;; The disk is write-protected.
TEXT_WRITE_PROTECTED = 10

;; One entry of <MessagePointers>: a message's address.
;; Parameters: number = the TEXT_ code, text = the message
.macro MessagePointer number, text
    .assert * - MessagePointers = number * 2, "MessagePointers is in TEXT_ order."
    .word text
.endmacro

.org $0800

;; Reads and checks the master image, installs a greeting name, and writes it to selected disks.
;;
;; At $0800. A failed image read can still use an image already in memory if the checks pass. At the disk prompt,
;; Escape chooses another name; at the retry or completion prompt it leads to a reboot. The greeting program itself
;; must be on the target disk.
.proc MasterCreate
.assert * = $0800, "MASTER CREATE starts at $0800."
    lda #TITLE_ROW
    jsr ClearScreenAtRow
    jsr ConnectConsole
    lda #TEXT_TITLE
    jsr PrintMessage
    jsr ReadImage
    bcc ValidateImage

    ; After a read error, look for an image already in memory.
    lda #ERROR_ROW
    jsr ClearScreenAtRow
    lda ImageRelocatorStart
    cmp #JMP_OPCODE
    beq ValidateImage
    jmp InvalidImage

    ; No branch in this image reaches these NOPs and the original read-error path.
    nop
    nop
    nop
    nop
    lda #TEXT_READ_ERROR
    jsr PrintMessage
    jmp Reboot

ValidateImage:
    lda ImageFileNameAddress
    eor ImageWriteStartAddress+1
    eor #IMAGE_CHECK
    bne InvalidImage
    lda ImageDosRelease
    eor #RELEASE_DOS_33
    bne InvalidImage
    sta ImageVolumeOption           ; A is zero: clear the low byte of the V option
    sta ImageBootVolume             ; the boot RWTS accepts any disk volume
    beq GetName                     ; always

InvalidImage:
    lda #TEXT_INVALID_IMAGE
    jsr PrintMessage
    jmp Reboot

GetName:
    lda #PROMPT_ROW
    jsr ClearScreenAtRow
    lda #TEXT_NAME_PROMPT
    jsr PrintMessage
    jsr GetLine
    jsr ParseName
    bcs GetName
    ldy #NAME_LENGTH-1

CopyName:
    lda NameBuffer,y
    sta ImageFileName,y
    dey
    bpl CopyName

AskForDisk:
    lda #SUMMARY_ROW
    jsr ClearScreenAtRow
    lda #TEXT_NAME_SUMMARY
    jsr PrintMessage
    jsr PrintName
    lda #TEXT_INSERT_TARGET
    jsr PrintMessage
    jsr WaitForReturnOrEscape
    bcs GetName                     ; Escape chooses another name
    jsr WriteImage
    bcc Written

    ; RWTS's return code says why the write failed.
    lda #PROMPT_ROW
    jsr ClearScreenAtRow
    lda RequestStatus
    asl a                           ; status bit 7: a read error
    bcs WriteError
    asl a                           ; status bit 6: a drive error
    bcc WriteProtected

WriteError:
    lda #TEXT_WRITE_ERROR
    bne ShowWriteError              ; always

WriteProtected:
    lda #TEXT_WRITE_PROTECTED

ShowWriteError:
    jsr PrintMessage
    lda #TEXT_RETRY
    jsr PrintMessage
    jsr WaitForReturnOrEscape
    bcs Exit
    lda #PROMPT_ROW
    jsr ClearScreenAtRow
    jmp AskForDisk

Exit:
    lda #PROMPT_ROW
    jsr ClearScreenAtRow

Reboot:
    lda #TEXT_REBOOT
    jsr PrintMessage

WaitToBoot:
    jsr WaitForReturnOrEscape
    bcs WaitToBoot

    ; The slot times 16 becomes the $Cn00 boot ROM address.
    lda RequestSlot
    lsr a
    lsr a
    lsr a
    lsr a
    ora #SLOT_ROM_PAGE
    sta Pointer+1
    lda #0
    sta Pointer
    jmp (Pointer)

Written:
    lda #SUCCESS_ROW
    jsr ClearScreenAtRow
    lda #TEXT_SUCCESS
    jsr PrintMessage
    jsr WaitForReturnOrEscape
    bcs Reboot
    jmp GetName
.endproc

;; Prints a message, including its last character, which has bit 7 set.
;; In: A = the TEXT_ code
;; Uses: A, X, Y, Pointer
.proc PrintMessage
    asl a
    tax
    lda MessagePointers,x
    sta Pointer
    lda MessagePointers+1,x
    sta Pointer+1

Next:
    ldy #0
    lda (Pointer),y
    pha
    ora #$80                        ; the Monitor expects characters with bit 7 set
    jsr CharacterOut
    pla
    bmi Done                        ; bit 7 in the stored character marks the end
    inc Pointer
    bne Next
    inc Pointer+1
    bne Next

Done:
    rts
.endproc

;; Clears the screen and sets the Monitor's cursor row.
;; In: A = the row to select after clearing
.proc ClearScreenAtRow
    pha
    jsr Home
    pla
    sta CV
    rts
.endproc

;; Prints a leading blank, the 30-character greeting name and a return.
.proc PrintName
    lda #BLANK
    ldx #0

Next:
    jsr CharacterOut
    cpx #NAME_LENGTH
    beq Done
    lda NameBuffer,x
    inx
    bne Next

Done:
    lda #KEY_RETURN
    jmp CharacterOut
.endproc

;; Connects the Monitor directly to the screen and keyboard, and sets the input prompt to a bell.
.proc ConnectConsole
    lda #<ScreenOut
    sta OutputHook
    lda #<KeyboardIn
    sta InputHook
    lda #>ScreenOut
    sta OutputHookHigh
    sta InputHookHigh
    sta SoftEntryCheck              ; replace the reset check byte
    lda #KEY_BELL
    sta PromptCharacter
    rts
.endproc

;; Waits for Return or Escape, ignoring other keys.
;; Out: carry = clear for Return, set for Escape
.proc WaitForReturnOrEscape
    jsr ReadKey
    cmp #KEY_RETURN
    beq Return
    cmp #KEY_ESCAPE
    beq Done                        ; CMP leaves the carry set on equality
    bne WaitForReturnOrEscape

Return:
    clc

Done:
    rts
.endproc

;; Copies a greeting name from the Monitor's input buffer, padding it to 30 characters.
;;
;; Leading blanks are skipped; the first character must be at least an A. A return, a comma or the input length
;; ends the name. The characters and padding keep their high bits.
;; In: X = the input's length, InputBuffer = the input line
;; Out: carry = clear if accepted, set if empty or the first character is below an A
.proc ParseName
    txa
    beq Failed
    stx Pointer
    ldy #0

SkipSpaces:
    lda InputBuffer,y
    iny
    cmp #BLANK
    beq SkipSpaces
    cmp #'A'|$80
    bcc Failed
    ldx #0

Copy:
    sta NameBuffer,x
    inx
    cpx #NAME_LENGTH
    beq Done
    lda InputBuffer,y
    cmp #KEY_RETURN
    beq Pad
    cmp #','|$80
    beq Pad
    cpy Pointer
    beq Pad
    iny
    bne Copy

Failed:
    sec
    rts

Pad:
    lda #BLANK

PadNext:
    sta NameBuffer,x
    inx
    cpx #NAME_LENGTH
    bne PadNext

Done:
    clc
    rts
.endproc

;; Writes the buffered image to the first 37 sectors of the selected disk.
;; Out: carry = clear on success, set on an RWTS error
.proc WriteImage
    lda #RWTS_WRITE
    bne TransferImage               ; always
.endproc

;; Reads the master image and records the current DOS slot and drive for later writes. Falls into
;; <TransferImage>.
;; Out: carry = clear on success, set on an RWTS error
.proc ReadImage
    lda #RWTS_READ
    ; Falls into TransferImage.
.endproc

;; Transfers the 37 sectors through RWTS, starting at track 0, sector 0.
;; In: A = the RWTS command, <RWTS_READ> or <RWTS_WRITE>
;; Out: carry = clear on success, set on an RWTS error
.proc TransferImage
    jsr PrepareRequest

Sector:
    lda #>Request
    ldy #<Request
    jsr RwtsJump
    bcs Done
    ldy RequestSector
    iny
    cpy #SECTORS_PER_TRACK
    bne NextSector
    ldy #0
    inc RequestTrack

NextSector:
    sty RequestSector
    inc RequestBufferHigh
    lda RequestBufferHigh
    cmp #>ImageBufferEnd            ; $1200-$36FF: 37 sectors
    bne Sector
    clc

Done:
    rts
.endproc

;; Copies the initial RWTS request and selects its read or write command.
;;
;; On a read, it obtains the slot and drive from DOS's IOB and stores them as both the requested and the last slot
;; and drive. The original copies 18 bytes: the extra byte comes from the device table and overwrites the first
;; byte of the unused filler after the request.
;; In: A = the RWTS command, <RWTS_READ> or <RWTS_WRITE>
.proc PrepareRequest
    pha
    cmp #RWTS_READ
    bne Copy
    jsr LocateIobJump               ; A/Y = the high and low address of DOS's IOB
    sta Pointer+1
    sty Pointer
    ldy #IOB_SLOT_TIMES_16
    lda (Pointer),y
    sta RequestTemplateSlot
    sta RequestTemplateLastSlot
    iny
    lda (Pointer),y                 ; IOB_DRIVE
    sta RequestTemplateDrive
    sta RequestTemplateLastDrive

Copy:
    ldy #REQUEST_LAST

CopyByte:
    lda RequestTemplate,y
    sta Request,y
    dey
    bpl CopyByte
    pla
    sta RequestCommand
    rts
.endproc

;; The messages' addresses, by TEXT_ code; the last character of each message has bit 7 set.
MessagePointers:
.assert * = $09E2, "The message table starts at $09E2."
    MessagePointer TEXT_TITLE, TitleText
    MessagePointer TEXT_NAME_PROMPT, NamePromptText
    MessagePointer TEXT_NAME_SUMMARY, NameSummaryText
    MessagePointer TEXT_INSERT_TARGET, InsertTargetText
    MessagePointer TEXT_SUCCESS, SuccessText
    MessagePointer TEXT_RETRY, RetryText
    MessagePointer TEXT_REBOOT, RebootText
    MessagePointer TEXT_READ_ERROR, ReadErrorText
    MessagePointer TEXT_INVALID_IMAGE, InvalidImageText
    MessagePointer TEXT_WRITE_ERROR, WriteErrorText
    MessagePointer TEXT_WRITE_PROTECTED, WriteProtectedText

;; The title and copyright, <TEXT_TITLE>.
TitleText:
    .byte $0D
    .byte "   DOS 3.3   MASTER - CREATE UTILITY", $0D
    .byte $0D
    .byte "  COPYRIGHT 1980 BY APPLE COMPUTER INC", $0D
    .byte "          ALL RIGHTS RESERVED.", $0D
    .byte $0D, $0D, $0D
    .byte "        (NOW LOADING DOS IMAGE)", KEY_RETURN

;; The name prompt, <TEXT_NAME_PROMPT>.
NamePromptText:
    .byte $0D
    .byte "PLEASE INPUT THE ", $22, "GREETING", $22, " PROGRAM'S", $0D
    .byte "FILE NAME:", BLANK

;; The reminder and the name, <TEXT_NAME_SUMMARY>.
NameSummaryText:
    .byte $0D, $0D
    .byte "REMEMBER THAT ", $22, "MASTER", $22, " DOES NOT CREATE", $0D
    .byte "THE ", $22, "GREETING", $22, " PROGRAM, OR PLACE IT IN", $0D
    .byte "THE DISK DIRECTORY", $0D, $0D
    .byte "  THIS IS THE FILE NAME THAT WILL BE", $0D
    .byte "PLACED WITHIN THE IMAGE:", $0D, $0D
    .byte "   ", BLANK

;; The prompt for the disk to write, <TEXT_INSERT_TARGET>.
InsertTargetText:
    .byte $0D
    .byte "  PLACE THE DISKETTE TO BE MASTERED  IN", $0D
    .byte "THE DISK DRIVE.", $0D, $0D
    .byte "  PRESS [RETURN] WHEN READY", $0D, $0D
    .byte "NOTE: IF YOU WANT A DIFFERENT FILE NAME,PRESS [ESC].", KEY_RETURN

;; The success message, <TEXT_SUCCESS>.
SuccessText:
    .byte $0D
    .byte "  THE DISKETTE HAS BEEN UPDATED, YOU MAYREMOVE IT AT THIS TIME.", $0D, $0D
    .byte "  IF YOU WISH TO ", $22, "MASTER", $22, " ANOTHER DISK-", $0D
    .byte "ETTE, PRESS [RETURN].", $0D, $0D
    .byte "  OTHERWISE PRESS [ESC] TO EXIT ", $22, "MASTER", $22, KEY_RETURN

;; The offer to try again, <TEXT_RETRY>.
RetryText:
    .byte $0D, $0D
    .byte "  IF YOU WISH TO RETRY PRESS [RETURN]", $0D, $0D
    .byte "  OTHERWISE PRESS [ESC] TO EXIT ", $22, "MASTER", $22, KEY_RETURN

;; The reboot prompt, <TEXT_REBOOT>.
RebootText:
    .byte $0D
    .byte "  INSERT A SYSTEM DISKETTE AND PRESS", $0D
    .byte "[RETURN] TO REBOOT DOS", BLANK

;; The read error, <TEXT_READ_ERROR>.
ReadErrorText:
    .byte $0D, $07, $07, $07, "  UNABLE TO READ IMAGE.", $0D, KEY_RETURN

;; The invalid image message, <TEXT_INVALID_IMAGE>.
InvalidImageText:
    .byte $0D, $07, $07, $07, "  IMAGE OF DOS 3.3   (MASTER) IS NOT", $0D, $0D
    .byte "AVAILABLE.  CHECK INSTRUCTIONS.", $0D, KEY_RETURN

;; The write error, <TEXT_WRITE_ERROR>.
WriteErrorText:
    .byte $0D, $07, $07, $07, "  UNABLE TO WRITE.  DISKETTE MUST BE", $0D
    .byte "INITIALIZED PROPERLY.  CHECK DISKETTE", $0D
    .byte "FOR PROPER INSERTION.", KEY_RETURN

;; The write-protected message, <TEXT_WRITE_PROTECTED>.
WriteProtectedText:
    .byte $0D, $07, $07, $07, "  DISKETTE IS WRITE PROTECTED.  REMOVE", $0D
    .byte "WRITE PROTECT TAB.", KEY_RETURN

;; Workspace for the greeting name; its original bytes are replaced by <ParseName>.
NameBuffer:
.assert * = $0E31, "The name buffer starts at $0E31."
    .res 11,$FF
    .byte $FB
    .res 15,$FF
    .byte $FB
    .res 2,$FF

;; The initial RWTS IOB, 17 bytes, copied into <Request> before each transfer.
RequestTemplate:
    .byte 1                         ; the IOB's type
;; The slot times 16, from DOS's IOB.
RequestTemplateSlot:
    .byte $60
;; The drive, from DOS's IOB.
RequestTemplateDrive:
    .byte 1
    .byte 0, 0, 0                   ; volume, track, sector
    .word DeviceCharacteristics
    .word ImageBuffer
    .word 0                         ; byte count, unused by this RWTS
    .byte 0, 0, 0                   ; command, status, volume found
;; The last slot times 16, from DOS's IOB.
RequestTemplateLastSlot:
    .byte $60
;; The last drive, from DOS's IOB.
RequestTemplateLastDrive:
    .byte 1

;; The Disk II's device table: type, phases per track and motor start-up count.
DeviceCharacteristics:
    .byte 0, 1, $EF, $D8

;; The working RWTS IOB, initially identical to <RequestTemplate>.
Request:
.assert * = $0E64, "The RWTS request starts at $0E64."
    .byte 1
;; The slot times 16.
RequestSlot:
    .byte $60
    .byte 1, 0                      ; drive, volume
;; The track.
RequestTrack:
    .byte 0
;; The sector.
RequestSector:
    .byte 0
    .word DeviceCharacteristics
    .byte <ImageBuffer
;; The high byte of the buffer's address.
RequestBufferHigh:
    .byte >ImageBuffer
    .word 0
;; The command.
RequestCommand:
    .byte 0
;; RWTS's return code.
RequestStatus:
    .byte 0
    .byte 0, $60, 1                 ; volume found, last slot, last drive

    ; The original file's unused filler follows the IOB.
    .byte "WRITTEN BY JAMES R. HUSTON DECEMBER 15, 1978 "
    .byte "(THIS MESSAGE IS FILLER, WHY READ IT?)"
.repeat 3
    .byte $EF
    .res 15,$FF
.endrepeat
    .byte $EF
    .res 6,$FF

.assert * = $0EFF, "The binary ends at $0EFE."
