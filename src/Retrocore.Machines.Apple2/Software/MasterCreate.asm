;; DOS 3.3 SYSTEM MASTER: MASTER CREATE
;;
;; The binary file MASTER CREATE from the 1980 Apple II Plus or ROMCARD System Master (680-0051-00 and
;; 680-0051-01). DOS loads its $06FF bytes at $0800 and starts it there. The 1982 master has the same code
;; but different copyright text.
;;
;; It reads the first 37 sectors of the master disk into $1200-$36FF, asks for a greeting program's name,
;; and writes the image to an initialized disk. It changes the greeting name and volume fields in the
;; image, but does not create or catalog the greeting program. On exit it asks for a system disk and
;; starts the disk controller's boot ROM.

.cpu Mos6502

; DOS's equates include the common IIe equates and Monitor entry points.
.include "../Roms/Dos/Equates.asm"
.include "../Roms/System/FirmwareEquates.asm"

; Monitor and DOS page-3 entries that are labels rather than equates in their sources.
GETLN = $FD6A                       ;; Monitor's line input, into IN
DOS_RWTS = $03D9                    ;; DOS's DISKIO entry
DOS_IOBLDR = $03E3                  ;; returns DOS's current RWTS IOB address

Pointer = $F0                       ;; temporary pointer, also used to save the input length
ImageBuffer = $1200                 ;; first of the 37 sector buffers
ImageBufferEnd = $3700              ;; first byte after the image

; These addresses name fields in the buffered disk image, not the running DOS. The suffixes are the names
; in the DOS sources; the image's relocator and DOS are one page above their usual master-build addresses.
ImageIBVOL = $13EB                  ;; boot loader's IOB volume
ImageBEGIN = $1C00                  ;; relocator's first byte
ImageFN1ADR = $1E06                 ;; low byte of DOS's FNAME1 pointer
ImageASTART = $1E0C                 ;; DOS's pointer to the relocator
ImageCUROPT = $2B66                 ;; low byte of DOS's V keyword
ImageFNAME1 = $2B75                 ;; DOS's 30-byte greeting name
ImageVDOSRN = $34BE                 ;; DOS release byte in its VTOC image

HighSpace = $A0
NameLength = 30

MsgTitle = 0
MsgNamePrompt = 1
MsgNameSummary = 2
MsgInsertTarget = 3
MsgSuccess = 4
MsgRetry = 5
MsgReboot = 6
MsgReadError = 7
MsgInvalidImage = 8
MsgWriteError = 9
MsgWriteProtected = 10

.org $0800

;; Reads and checks the master image, installs a greeting name, and writes it to selected disks.
;;
;; A failed image read can still use an image already in memory if the checks pass. At the disk prompt,
;; Escape chooses another name; at the retry or completion prompt it leads to a reboot. The greeting
;; program itself must be on the target disk.
MasterCreate:
    lda #$0C
    jsr ClearScreenAtRow
    jsr ConnectConsole
    lda #MsgTitle
    jsr PrintMessage
    jsr ReadImage
    bcc MasterCreate_ValidateImage
    lda #$08
    jsr ClearScreenAtRow
    lda ImageBEGIN                  ; after a read error, look for an image already in memory
    cmp #$4C                        ; BEGIN starts with JMP
    beq MasterCreate_ValidateImage
    jmp MasterCreate_InvalidImage

; No branch in this image reaches these NOPs and the original read-error path.
    nop
    nop
    nop
    nop
    lda #MsgReadError
    jsr PrintMessage
    jmp MasterCreate_Reboot

MasterCreate_ValidateImage:
    lda ImageFN1ADR
    eor ImageASTART+1
    eor #$6E                        ; expected pointer bytes in a master image
    bne MasterCreate_InvalidImage
    lda ImageVDOSRN
    eor #4                          ; DOS 3.3's release byte
    bne MasterCreate_InvalidImage
    sta ImageCUROPT                 ; A is zero: clear the low byte of the V keyword
    sta ImageIBVOL                  ; boot RWTS accepts any disk volume
    beq MasterCreate_GetName        ; always taken

MasterCreate_InvalidImage:
    lda #MsgInvalidImage
    jsr PrintMessage
    jmp MasterCreate_Reboot

MasterCreate_GetName:
    lda #$0A
    jsr ClearScreenAtRow
    lda #MsgNamePrompt
    jsr PrintMessage
    jsr GETLN
    jsr ParseName
    bcs MasterCreate_GetName
    ldy #NameLength-1
MasterCreate_CopyName:
    lda NameBuffer,y
    sta ImageFNAME1,y
    dey
    bpl MasterCreate_CopyName

MasterCreate_AskForDisk:
    lda #2
    jsr ClearScreenAtRow
    lda #MsgNameSummary
    jsr PrintMessage
    jsr PrintName
    lda #MsgInsertTarget
    jsr PrintMessage
    jsr WaitForReturnOrEscape
    bcs MasterCreate_GetName        ; Escape chooses another name
    jsr WriteImage
    bcc MasterCreate_Written
    lda #$0A
    jsr ClearScreenAtRow
    lda RequestStatus
    asl A                           ; status bit 7: read error
    bcs MasterCreate_WriteError
    asl A                           ; status bit 6: drive error
    bcc MasterCreate_WriteProtected
MasterCreate_WriteError:
    lda #MsgWriteError
    bne MasterCreate_ShowWriteError  ; always taken
MasterCreate_WriteProtected:
    lda #MsgWriteProtected
MasterCreate_ShowWriteError:
    jsr PrintMessage
    lda #MsgRetry
    jsr PrintMessage
    jsr WaitForReturnOrEscape
    bcs MasterCreate_Exit
    lda #$0A
    jsr ClearScreenAtRow
    jmp MasterCreate_AskForDisk

MasterCreate_Exit:
    lda #$0A
    jsr ClearScreenAtRow
MasterCreate_Reboot:
    lda #MsgReboot
    jsr PrintMessage
MasterCreate_WaitToBoot:
    jsr WaitForReturnOrEscape
    bcs MasterCreate_WaitToBoot
    lda RequestSlot                 ; slot * 16 becomes the $Cn00 boot ROM address
    lsr A
    lsr A
    lsr A
    lsr A
    ora #$C0
    sta Pointer+1
    lda #0
    sta Pointer
    jmp (Pointer)

MasterCreate_Written:
    lda #6
    jsr ClearScreenAtRow
    lda #MsgSuccess
    jsr PrintMessage
    jsr WaitForReturnOrEscape
    bcs MasterCreate_Reboot
    jmp MasterCreate_GetName

;; Prints the message indexed by A, including its high-bit-set terminating character.
;; In:   A = message index
;; Uses: A, X, Y, Pointer
PrintMessage:
    asl A
    tax
    lda MessagePointers,x
    sta Pointer
    lda MessagePointers+1,x
    sta Pointer+1
PrintMessage_Next:
    ldy #0
    lda (Pointer),y
    pha
    ora #$80                        ; the Monitor expects characters with bit 7 set
    jsr PRINT
    pla
    bmi PrintMessage_Done           ; bit 7 in the stored character marks the end
    inc Pointer
    bne PrintMessage_Next
    inc Pointer+1
    bne PrintMessage_Next
PrintMessage_Done:
    rts

;; Clears the screen and sets the Monitor's cursor row.
;; In: A = row to select after HOME
ClearScreenAtRow:
    pha
    jsr HOME
    pla
    sta CV
    rts

;; Prints a leading space, the 30-byte greeting name and a carriage return.
PrintName:
    lda #HighSpace
    ldx #0
PrintName_Next:
    jsr PRINT
    cpx #NameLength
    beq PrintName_Done
    lda NameBuffer,x
    inx
    bne PrintName_Next
PrintName_Done:
    lda #KEY_CR
    jmp PRINT

;; Connects the Monitor directly to the screen and keyboard, and sets the input prompt to a bell.
ConnectConsole:
    lda #<COUT1
    sta CSWL
    lda #<KEYIN
    sta KSWL
    lda #>COUT1
    sta CSWH
    sta KSWH
    sta PWREDUP                     ; replace the reset check byte
    lda #KEY_BELL
    sta PROMPT
    rts

;; Waits for Return or Escape, ignoring other keys.
;; Out: carry = clear for Return, set for Escape
WaitForReturnOrEscape:
    jsr GETKEY
    cmp #KEY_CR
    beq WaitForReturnOrEscape_Return
    cmp #KEY_ESC
    beq WaitForReturnOrEscape_Done  ; CMP leaves carry set on equality
    bne WaitForReturnOrEscape
WaitForReturnOrEscape_Return:
    clc
WaitForReturnOrEscape_Done:
    rts

;; Copies a greeting name from the Monitor's input buffer, padding it to 30 characters.
;;
;; Leading spaces are skipped; the first character must be at least $C1. A carriage return, comma or the
;; input length ends the name. The characters and padding retain their high bits.
;; In:  X = input length, IN = input line
;; Out: carry = clear if accepted, set if empty or the first character is below $C1
ParseName:
    txa
    beq ParseName_Failed
    stx Pointer
    ldy #0
ParseName_SkipSpaces:
    lda IN,y
    iny
    cmp #HighSpace
    beq ParseName_SkipSpaces
    cmp #$C1
    bcc ParseName_Failed
    ldx #0
ParseName_Copy:
    sta NameBuffer,x
    inx
    cpx #NameLength
    beq ParseName_Done
    lda IN,y
    cmp #KEY_CR
    beq ParseName_Pad
    cmp #$AC                        ; comma with its high bit set
    beq ParseName_Pad
    cpy Pointer
    beq ParseName_Pad
    iny
    bne ParseName_Copy
ParseName_Failed:
    sec
    rts
ParseName_Pad:
    lda #HighSpace
ParseName_PadNext:
    sta NameBuffer,x
    inx
    cpx #NameLength
    bne ParseName_PadNext
ParseName_Done:
    clc
    rts

;; Writes the buffered image to the first 37 sectors of the selected disk.
;; Out: carry = clear on success, set on an RWTS error
WriteImage:
    lda #2                          ; RWTS write command
    bne TransferImage               ; always taken

;; Reads the master image and records the current DOS slot and drive for later writes.
;; Out: carry = clear on success, set on an RWTS error
ReadImage:
    lda #1                          ; RWTS read command

;; Transfers the 37 sectors through RWTS, starting at track 0, sector 0.
;; In:  A = RWTS command, 1 for read or 2 for write
;; Out: carry = clear on success, set on an RWTS error
TransferImage:
    jsr PrepareRequest
TransferImage_Sector:
    lda #>Request
    ldy #<Request
    jsr DOS_RWTS
    bcs TransferImage_Done
    ldy RequestSector
    iny
    cpy #$10
    bne TransferImage_NextSector
    ldy #0
    inc RequestTrack
TransferImage_NextSector:
    sty RequestSector
    inc RequestBufferHi
    lda RequestBufferHi
    cmp #>ImageBufferEnd            ; $1200-$36FF: 37 sectors
    bne TransferImage_Sector
    clc
TransferImage_Done:
    rts

;; Copies the initial RWTS request and selects its read or write command.
;;
;; On a read, it obtains the slot and drive from DOS's IOB and stores them as both the requested and last
;; slot/drive. The original copies 18 bytes: the extra byte comes from the DCT and overwrites the first
;; byte of the unused filler after the request.
;; In: A = RWTS command, 1 for read or 2 for write
PrepareRequest:
    pha
    cmp #1
    bne PrepareRequest_Copy
    jsr DOS_IOBLDR                  ; A/Y = high/low address of DOS's IOB
    sta Pointer+1
    sty Pointer
    ldy #1
    lda (Pointer),y                 ; current slot * 16
    sta RequestTemplateSlot
    sta RequestTemplateLastSlot
    iny
    lda (Pointer),y                 ; current drive
    sta RequestTemplateDrive
    sta RequestTemplateLastDrive
PrepareRequest_Copy:
    ldy #$11
PrepareRequest_CopyByte:
    lda RequestTemplate,y
    sta Request,y
    dey
    bpl PrepareRequest_CopyByte
    pla
    sta RequestCommand
    rts

;; Message pointers indexed by PrintMessage; the last character of each message has bit 7 set.
MessagePointers:
    .word TitleText, NamePromptText, NameSummaryText, InsertTargetText
    .word SuccessText, RetryText, RebootText, ReadErrorText
    .word InvalidImageText, WriteErrorText, WriteProtectedText

TitleText:
    .byte $0D
    .byte "   DOS 3.3   MASTER - CREATE UTILITY", $0D
    .byte $0D
    .byte "  COPYRIGHT 1980 BY APPLE COMPUTER INC", $0D
    .byte "          ALL RIGHTS RESERVED.", $0D
    .byte $0D, $0D, $0D
    .byte "        (NOW LOADING DOS IMAGE)", KEY_CR

NamePromptText:
    .byte $0D
    .byte "PLEASE INPUT THE ", $22, "GREETING", $22, " PROGRAM'S", $0D
    .byte "FILE NAME:", HighSpace

NameSummaryText:
    .byte $0D, $0D
    .byte "REMEMBER THAT ", $22, "MASTER", $22, " DOES NOT CREATE", $0D
    .byte "THE ", $22, "GREETING", $22, " PROGRAM, OR PLACE IT IN", $0D
    .byte "THE DISK DIRECTORY", $0D, $0D
    .byte "  THIS IS THE FILE NAME THAT WILL BE", $0D
    .byte "PLACED WITHIN THE IMAGE:", $0D, $0D
    .byte "   ", HighSpace

InsertTargetText:
    .byte $0D
    .byte "  PLACE THE DISKETTE TO BE MASTERED  IN", $0D
    .byte "THE DISK DRIVE.", $0D, $0D
    .byte "  PRESS [RETURN] WHEN READY", $0D, $0D
    .byte "NOTE: IF YOU WANT A DIFFERENT FILE NAME,PRESS [ESC].", KEY_CR

SuccessText:
    .byte $0D
    .byte "  THE DISKETTE HAS BEEN UPDATED, YOU MAYREMOVE IT AT THIS TIME.", $0D, $0D
    .byte "  IF YOU WISH TO ", $22, "MASTER", $22, " ANOTHER DISK-", $0D
    .byte "ETTE, PRESS [RETURN].", $0D, $0D
    .byte "  OTHERWISE PRESS [ESC] TO EXIT ", $22, "MASTER", $22, KEY_CR

RetryText:
    .byte $0D, $0D
    .byte "  IF YOU WISH TO RETRY PRESS [RETURN]", $0D, $0D
    .byte "  OTHERWISE PRESS [ESC] TO EXIT ", $22, "MASTER", $22, KEY_CR

RebootText:
    .byte $0D
    .byte "  INSERT A SYSTEM DISKETTE AND PRESS", $0D
    .byte "[RETURN] TO REBOOT DOS", HighSpace

ReadErrorText:
    .byte $0D, $07, $07, $07, "  UNABLE TO READ IMAGE.", $0D, KEY_CR

InvalidImageText:
    .byte $0D, $07, $07, $07, "  IMAGE OF DOS 3.3   (MASTER) IS NOT", $0D, $0D
    .byte "AVAILABLE.  CHECK INSTRUCTIONS.", $0D, KEY_CR

WriteErrorText:
    .byte $0D, $07, $07, $07, "  UNABLE TO WRITE.  DISKETTE MUST BE", $0D
    .byte "INITIALIZED PROPERLY.  CHECK DISKETTE", $0D
    .byte "FOR PROPER INSERTION.", KEY_CR

WriteProtectedText:
    .byte $0D, $07, $07, $07, "  DISKETTE IS WRITE PROTECTED.  REMOVE", $0D
    .byte "WRITE PROTECT TAB.", KEY_CR

;; Workspace for the greeting name; its original bytes are replaced by ParseName.
NameBuffer:
    .res 11,$FF
    .byte $FB
    .res 15,$FF
    .byte $FB
    .res 2,$FF

;; Initial 17-byte RWTS IOB, copied into Request before each transfer.
RequestTemplate:
    .byte 1                         ; IOB type
RequestTemplateSlot:
    .byte $60                       ; slot * 16
RequestTemplateDrive:
    .byte 1
    .byte 0, 0, 0                   ; volume, track, sector
    .word DeviceCharacteristics
    .word ImageBuffer
    .word 0                         ; byte count, unused by this RWTS
    .byte 0, 0, 0                   ; command, status, volume found
RequestTemplateLastSlot:
    .byte $60
RequestTemplateLastDrive:
    .byte 1

;; Disk II device characteristics: type, phases per track and motor start-up count.
DeviceCharacteristics:
    .byte 0, 1, $EF, $D8

;; Working RWTS IOB, initially identical to RequestTemplate.
Request:
    .byte 1
RequestSlot:
    .byte $60
    .byte 1, 0                      ; drive, volume
RequestTrack:
    .byte 0
RequestSector:
    .byte 0
    .word DeviceCharacteristics
    .byte <ImageBuffer
RequestBufferHi:
    .byte >ImageBuffer
    .word 0
RequestCommand:
    .byte 0
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

.assert MasterCreate = $0800, "MASTER CREATE starts at $0800."
.assert MessagePointers = $09E2, "The message table starts at $09E2."
.assert NameBuffer = $0E31, "The name buffer starts at $0E31."
.assert Request = $0E64, "The RWTS request starts at $0E64."
.assert * = $0EFF, "The binary ends at $0EFE."
