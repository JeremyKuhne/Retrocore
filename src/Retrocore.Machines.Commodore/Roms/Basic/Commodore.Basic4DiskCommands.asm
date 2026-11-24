; retrocore: style=strict
; COMMODORE BASIC 4: THE DISK STATEMENTS, THE DISK STATUS AND THE COMMAND BUILDER

; The codes in a disk-command template that <Disk::BuildCommand> replaces; every other byte is copied as it is.

;; Inserts the first filename, after making it the second too (<Disk::AppendFirstName>).
;; Also: XFN1 (K4S79, HVK4)
INSERT_FIRST_NAME = $F1

;; Inserts the second filename, or removes the separator before it when it is empty.
;; Also: XFN2 (K4S79, HVK4)
INSERT_SECOND_NAME = $F2

;; Inserts the two characters of the disk ID.
;; Also: XID (K4S79, HVK4)
INSERT_DISK_ID = $D0

;; Inserts <RecordLength>: a relative file's record length, or the `S` <Disk::ChooseFileType> left there; nothing
;; when it is 0.
;; Also: XREC (K4S79, HVK4)
INSERT_RECORD_LENGTH = $E0

;; Inserts the file's type or mode, as <Disk::ChooseFileType> chooses it.
;; Also: XWRT (K4S79, HVK4)
INSERT_FILE_TYPE = $E1

;; Inserts the first drive's digit.
;; Also: XD1 (K4S79, HVK4)
INSERT_FIRST_DRIVE = $D1

;; Inserts the second drive's digit.
;; Also: XD2 (K4S79, HVK4)
INSERT_SECOND_DRIVE = $D2

; Each template's offset in <Disk::CommandTemplates>, less one (<Disk::BuildCommand> steps Y before it reads), and
; its length. The table asserts each.

;; `CATALOG`'s template: `$` and the drive.
TEMPLATE_CATALOG = 0

;; The length of `CATALOG`'s template; without a drive, only its `$` is used.
TEMPLATE_CATALOG_LENGTH = 2

;; `DOPEN`'s template: the drive, the name, the file's type and its record length. `DSAVE` and `DLOAD` use its
;; drive and name alone.
TEMPLATE_OPEN = 2

;; The length of the drive and the name that begin `DOPEN`'s template.
TEMPLATE_NAME_LENGTH = 3

;; The length of `DOPEN`'s template, with the type and the record length.
TEMPLATE_OPEN_LENGTH = 7

;; `APPEND`'s template: the drive, the name and the append mode.
TEMPLATE_APPEND = 9

;; The length of `APPEND`'s template.
TEMPLATE_APPEND_LENGTH = 5

;; `HEADER`'s template: the new command, the drive, the name and the disk ID.
TEMPLATE_HEADER = 14

;; The length of `HEADER`'s template; without an ID, its last two bytes are left off.
TEMPLATE_HEADER_LENGTH = 6

;; `COLLECT`'s template: the validate command and the drive.
TEMPLATE_COLLECT = 20

;; The length of `COLLECT`'s template; without a drive, only the command is used.
TEMPLATE_COLLECT_LENGTH = 2

;; `BACKUP`'s template: the duplicate command and both drives.
TEMPLATE_BACKUP = 22

;; The length of `BACKUP`'s template.
TEMPLATE_BACKUP_LENGTH = 4

;; `COPY`'s template: the copy command, the destination drive and name, and the source drive and name.
TEMPLATE_COPY = 26

;; The length of `COPY`'s template.
TEMPLATE_COPY_LENGTH = 8

;; `CONCAT`'s template: the copy command, the destination, then the destination and the source as its sources.
TEMPLATE_CONCAT = 34

;; The length of `CONCAT`'s template.
TEMPLATE_CONCAT_LENGTH = 12

;; `RENAME`'s template: the rename command, the new name and the old.
TEMPLATE_RENAME = 46

;; The length of `RENAME`'s template.
TEMPLATE_RENAME_LENGTH = 8

;; `SCRATCH`'s template: the scratch command, the drive and the name.
TEMPLATE_SCRATCH = 54

;; The length of `SCRATCH`'s template.
TEMPLATE_SCRATCH_LENGTH = 4

; The drive's channels, as the secondary address a command sends on the IEEE bus.

;; Channel 0, which reads a file `$` opens as the directory.
DIRECTORY_CHANNEL = $60

;; Channel 15, the drive's command and error channel.
COMMAND_CHANNEL = $6F

;; The secondary address before the first <Disk::FindSecondaryAddress> gives a file.
FILE_CHANNELS_BEFORE = $61

; Other values.

;; The logical file `CATALOG` reads the directory through.
CATALOG_FILE = 14

;; The screen's device number.
SCREEN_DEVICE = 3

;; The length of the disk-status buffer behind `DS$`, before its two-byte back-link.
STATUS_LENGTH = 40

;; The length of the record-position command <Disk::PositionRecord> builds: `P`, the channel, the record and the
;; position.
POSITION_COMMAND_LENGTH = 5

;; Emits BASIC 4's disk statements, the disk status behind `DS` and `DS$`, and the command builder.
.macro CommodoreBasic4DiskCommands

    .scope Disk continued
    ; The command templates.

;; The templates <Disk::BuildCommand> expands into the commands the disk statements send to the drive, one after
;; another, each at its `TEMPLATE_` offset. The first byte only puts `CATALOG`'s template at offset 1.
;;
;; Every template that has both filenames inserts the second before the first, since inserting the first
;; (<Disk::AppendFirstName>) overwrites the second's pointer and length. `COPY`'s one template serves both its
;; forms: for a whole drive the names are empty, and their separators are removed with them.
;; Also: TABLD (K4S79, HVK4)
CommandTemplates:
    .byte $FF
    .assert * - CommandTemplates - 1 = TEMPLATE_CATALOG, "CATALOG's template follows the first byte."
    .byte '$', INSERT_FIRST_DRIVE
    .assert * - CommandTemplates - 1 = TEMPLATE_OPEN, "DOPEN's template follows CATALOG's."
    .byte INSERT_FIRST_DRIVE, ':', INSERT_FIRST_NAME
    .assert * - CommandTemplates - 1 = TEMPLATE_OPEN + TEMPLATE_NAME_LENGTH, "DOPEN's name is its first part."
    .byte ',', INSERT_FILE_TYPE, ',', INSERT_RECORD_LENGTH
    .assert * - CommandTemplates - 1 = TEMPLATE_APPEND, "APPEND's template follows DOPEN's."
    .byte INSERT_FIRST_DRIVE, ':', INSERT_FIRST_NAME, ',', 'A'
    .assert * - CommandTemplates - 1 = TEMPLATE_HEADER, "HEADER's template follows APPEND's."
    .byte 'N', INSERT_FIRST_DRIVE, ':', INSERT_FIRST_NAME, ',', INSERT_DISK_ID
    .assert * - CommandTemplates - 1 = TEMPLATE_COLLECT, "COLLECT's template follows HEADER's."
    .byte 'V', INSERT_FIRST_DRIVE
    .assert * - CommandTemplates - 1 = TEMPLATE_BACKUP, "BACKUP's template follows COLLECT's."
    .byte 'D', INSERT_SECOND_DRIVE, '=', INSERT_FIRST_DRIVE
    .assert * - CommandTemplates - 1 = TEMPLATE_COPY, "COPY's template follows BACKUP's."
    .byte 'C', INSERT_SECOND_DRIVE, ':', INSERT_SECOND_NAME, '=', INSERT_FIRST_DRIVE, ':', INSERT_FIRST_NAME
    .assert * - CommandTemplates - 1 = TEMPLATE_CONCAT, "CONCAT's template follows COPY's."
    .byte 'C', INSERT_SECOND_DRIVE, ':', INSERT_SECOND_NAME, '=', INSERT_SECOND_DRIVE, ':', INSERT_SECOND_NAME
    .byte ',', INSERT_FIRST_DRIVE, ':', INSERT_FIRST_NAME
    .assert * - CommandTemplates - 1 = TEMPLATE_RENAME, "RENAME's template follows CONCAT's."
    .byte 'R', INSERT_FIRST_DRIVE, ':', INSERT_SECOND_NAME, '=', INSERT_FIRST_DRIVE, ':', INSERT_FIRST_NAME
    .assert * - CommandTemplates - 1 = TEMPLATE_SCRATCH, "SCRATCH's template follows RENAME's."
    .byte 'S', INSERT_FIRST_DRIVE, ':', INSERT_FIRST_NAME
    .assert TEMPLATE_CATALOG + TEMPLATE_CATALOG_LENGTH = TEMPLATE_OPEN, "CATALOG's template length."
    .assert TEMPLATE_OPEN + TEMPLATE_OPEN_LENGTH = TEMPLATE_APPEND, "DOPEN's template length."
    .assert TEMPLATE_APPEND + TEMPLATE_APPEND_LENGTH = TEMPLATE_HEADER, "APPEND's template length."
    .assert TEMPLATE_HEADER + TEMPLATE_HEADER_LENGTH = TEMPLATE_COLLECT, "HEADER's template length."
    .assert TEMPLATE_COLLECT + TEMPLATE_COLLECT_LENGTH = TEMPLATE_BACKUP, "COLLECT's template length."
    .assert TEMPLATE_BACKUP + TEMPLATE_BACKUP_LENGTH = TEMPLATE_COPY, "BACKUP's template length."
    .assert TEMPLATE_COPY + TEMPLATE_COPY_LENGTH = TEMPLATE_CONCAT, "COPY's template length."
    .assert TEMPLATE_CONCAT + TEMPLATE_CONCAT_LENGTH = TEMPLATE_RENAME, "CONCAT's template length."
    .assert TEMPLATE_RENAME + TEMPLATE_RENAME_LENGTH = TEMPLATE_SCRATCH, "RENAME's template length."
    .assert * - CommandTemplates - 1 = TEMPLATE_SCRATCH + TEMPLATE_SCRATCH_LENGTH, "SCRATCH's template length."

    .endscope

    .scope Statements continued
    ; `CATALOG`.

    ;; `CATALOG` and `DIRECTORY`: lists a disk's directory on the output channel selected when it began.
    ;;
    ;; The directory is read as the drive sends it for `LOAD "$"`: a load address, then a line for each entry, each
    ;; a link, a block count and the line's text, ending in a zero. `STOP` ends the listing, and a space pauses it
    ;; until another key. <CatalogOutputFile> and <CatalogOutputDevice> keep the output channel and its device
    ;; meanwhile.
    ;; In: LogicalFile = the kernal's current file, which the listing is written to unless the default output device
    ;;   is the screen (as after `CMD`)
    ;; Errors: SYNTAX for a parameter other than a drive and a unit
    ;; Also: CATLOG (K4S79, HVK4)
    .proc Catalog

    ;; The count of byte pairs left to read in a line's header, in <FilenameLength>'s byte.
    PairCount = FilenameLength

    ;; The pair just read: the line's block count, in <MonitorEndAddress>'s bytes.
    BlockCount = MonitorEndAddress

    lda LogicalFile
    sta CatalogOutputFile
    jsr Disk::ParseParameters
    jsr Disk::CheckDriveOnly

;; Chooses the template's length: with a drive, its digit too.
;; Also: CATALG (K4S79, HVK4)
SelectTemplate:
    ldy #TEMPLATE_CATALOG
    ldx #TEMPLATE_CATALOG_LENGTH - 1
    lda ParsedParameters
    and #PARSED_FIRST_DRIVE
    beq Open
    inx

;; Builds the `$` command and opens the directory as file 14.
;; Also: CATBLD (K4S79, HVK4)
Open:
    txa
    jsr Disk::BuildCommand
    lda DefaultOutputDevice
    sta CatalogOutputDevice
    lda #DIRECTORY_CHANNEL
    sta SecondaryAddress
    lda #CATALOG_FILE
    sta LogicalFile
    jsr KernalUnlisten
    jsr KernalOpenCurrentFile
    lda #0
    sta IoStatus

    ; The load address and the first line's link come before its block count.
    ldy #3

;; Reads Y byte pairs, leaving the last, the line's block count, in <BlockCount>.
;; Also: WG220 (K4S79, HVK4)
ReadPairs:
    sty PairCount
    ldx #CATALOG_FILE
    jsr KernalSetInputChannel
    jsr KernalInputCharacter
    sta BlockCount
    ldy IoStatus
    bne Close
    jsr KernalInputCharacter
    sta BlockCount+1
    ldy IoStatus
    bne Close
    ldy PairCount
    dey
    bne ReadPairs

    ; Print the block count and a space.
    jsr KernalRestoreChannels
    jsr SelectOutput
    ldx BlockCount
    lda BlockCount+1
    jsr Float::PrintDecimalAX
    lda #' '

;; Prints the space after the block count.
;; Also: SKIPB (K4S79, HVK4)
PrintSeparator:
    jsr KernalOutputCharacter
    jsr KernalRestoreChannels

;; Reads and prints one character of the line, then checks `STOP` and the space bar.
;; Also: WG250 (K4S79, HVK4)
NextCharacter:
    ldx #CATALOG_FILE
    jsr KernalSetInputChannel
    jsr KernalInputCharacter
    pha
    jsr KernalRestoreChannels
    pla
    ldx IoStatus
    bne Close
    cmp #0
    beq EndOfLine
    jsr OutputCharacter
    jsr KernalTestStopKey
    beq Close
    jsr KernalGetInput
    beq NextCharacter
    cmp #' '
    bne NextCharacter

;; Waits for a key after a space paused the listing.
;; Also: WG255 (K4S79, HVK4)
Paused:
    jsr KernalGetInput
    beq Paused
    bne NextCharacter

;; Ends the line, then reads the next line's link and block count.
;; Also: WG240 (K4S79, HVK4)
EndOfLine:
    lda #CARRIAGE_RETURN
    jsr OutputCharacter
    jsr KernalUnlisten
    ldy #2
    bne ReadPairs

;; Pulls a byte before closing; nothing branches here.
;; Also: WG235 (K4S79, HVK4)
DropAndClose:
    pla

;; Restores the default channels and closes the directory.
;; Also: WG230 (K4S79, HVK4)
Close:
    jsr KernalRestoreChannels
    lda #CATALOG_FILE
    jmp KernalCloseLogicalFile

    ;; Prints a character on the listing's output, then restores the default channels.
    ;; In: A = the character
    ;; Also: SUBA (K4S79, HVK4)
    .proc OutputCharacter
    jsr SelectOutput
    jsr KernalOutputCharacter
    jmp KernalRestoreChannels
    .endproc

    ;; Selects the listing's output file, unless its device is the screen, which is the default.
    ;; Also: SUBB (K4S79, HVK4)
    .proc SelectOutput
    ldx CatalogOutputDevice
    cpx #SCREEN_DEVICE
    beq Done
    ldx CatalogOutputFile
    jsr KernalSetOutputChannel

;; Returns.
;; Also: SUBBR (K4S79, HVK4)
Done:
    rts
    .endproc
    .endproc

    .endscope

    .scope Disk continued
    ; Choosing a file's channel.

    ;; Finds the first secondary address from $62 that no open file uses.
    ;; Out: SecondaryAddress = the address, Y = the address
    ;; Also: ENTRY0 (K4S79, HVK4)
    .proc FindSecondaryAddress
    ldy #FILE_CHANNELS_BEFORE

;; Tries the next secondary address.
;; Also: ENTRY1 (K4S79, HVK4)
NextAddress:
    iny
    tya
    ldx OpenFileCount

;; Compares it with the next open file's.
;; Also: ENTRY2 (K4S79, HVK4)
NextFile:
    dex
    bmi Found
    cmp SecondaryAddressTable,x
    beq NextAddress
    bne NextFile

;; Takes the address no open file uses.
;; Also: RFOUND (K4S79, HVK4)
Found:
    sty SecondaryAddress
    rts
    .endproc

    .endscope

    .scope Statements continued
    ; `DOPEN` and `APPEND`.

    ;; `DOPEN`: opens a disk file, for a relative file with its record length, and with `@` to replace it.
    ;; Errors: SYNTAX without a name and a file number, or with a second name or drive
    ;; Also: DOPEN (K4S79, HVK4)
    .proc DOpen
    jsr Disk::ParseParameters
    jsr Disk::RequireNameAndFile
    and #PARSED_SECOND_NAME | PARSED_SECOND_DRIVE
    beq Open
    jmp SyntaxError

;; Chooses a secondary address and the template's length: the drive and the name, with the type and the record
;; length when either was given.
;; Also: DOPEN2 (K4S79, HVK4)
Open:
    jsr Disk::FindSecondaryAddress
    ldy #TEMPLATE_OPEN
    ldx #TEMPLATE_NAME_LENGTH
    bit ParsedParameters
    bvc CheckReplace

;; With a type or a record length, the whole template.
;; Also: RECLCK (K4S79, HVK4)
TypedOpen:
    ldx #TEMPLATE_OPEN_LENGTH

;; With `@`, the command starts with it.
;; Also: LEAV (K4S79, HVK4)
CheckReplace:
    bit ParsedParameters
    bpl NoReplace
    lda #REPLACE_PREFIX
    sta DiskCommandBuffer
    txa
    ldx #1
    jsr Disk::BuildCommandAt
    jmp KernalOpenPrepared

;; Builds the command from its start and opens the file.
;; Also: LEAV1 (K4S79, HVK4)
NoReplace:
    txa
    jsr Disk::BuildCommand
    jmp KernalOpenPrepared
    .endproc

    ;; `APPEND`: opens a sequential disk file to write at its end.
    ;; Errors: SYNTAX without a name and a file number, or with another parameter but a drive and a unit
    ;; Also: APPEND (K4S79, HVK4)
    .proc Append
    jsr Disk::ParseParameters
    jsr Disk::RequireNameAndFile
    and #PARSED_SECOND_NAME | PARSED_SECOND_DRIVE | PARSED_RECORD | PARSED_REPLACE
    beq Open
    jmp SyntaxError

;; Chooses a secondary address and opens the file to append.
;; Also: DAPPEN (K4S79, HVK4)
Open:
    jsr Disk::FindSecondaryAddress
    ldy #TEMPLATE_APPEND
    lda #TEMPLATE_APPEND_LENGTH
    jsr Disk::BuildCommand
    jmp KernalOpenPrepared
    .endproc

    .endscope

    .scope Disk continued
    ; The disk status behind `DS` and `DS$`.

    ;; Reads the drive's error channel into the disk-status buffer, first allocating the buffer if `DS$` has none.
    ;; Out: DiskStatusDescriptor = the status, of 40 characters
    ;; Also: ERRCHL (K4S79, HVK4)
    .proc ReadStatus
    lda DiskStatusDescriptor
    bne ReadErrorChannel
    ; Falls into AllocateStatus.
    .endproc

    ;; Allocates the 40-byte disk-status buffer, links it back to <DiskStatusDescriptor>, clears <IoStatus>, then
    ;; falls into <Disk::ReadErrorChannel>.
    ;;
    ;; The back-link after the buffer's last byte is the descriptor's address, so the linked-string collector can
    ;; move the buffer.
    ;; Also: GETDS (K4S79, HVK4)
    .proc AllocateStatus
    lda #STATUS_LENGTH
    sta DiskStatusDescriptor
    jsr Strings::ReserveSpace
    stx DiskStatusDescriptor+StringDescriptor::ADDRESS
    sty DiskStatusDescriptor+StringDescriptor::ADDRESS+1

    ; Clear the I/O status and store the link's high byte, then its low byte below it.
    lda #>DiskStatusDescriptor
    ldy #STATUS_LENGTH + 1
    jsr StoreStatusLink
    lda #<DiskStatusDescriptor
    sta (DiskStatusDescriptor+StringDescriptor::ADDRESS),y
    ; Falls into ReadErrorChannel.
    .endproc
    .assert >DiskStatusDescriptor = 0, "The status link's high byte clears the I/O status."

    ;; Reads the drive's error channel into the disk-status buffer, up to a carriage return, and ends the text with a
    ;; zero.
    ;;
    ;; The unit defaults to 8. Nothing limits the length, and only a carriage return ends it (a zero is stored like
    ;; any other byte): a reply of more than 40 characters runs on over the buffer's back-link and beyond.
    ;; In: DeviceNumber = the unit, 0 for 8
    ;; Also: ECHKS (K4S79, HVK4)
    .proc ReadErrorChannel
    lda DeviceNumber
    bne SendTalk
    lda #DEFAULT_DISK_UNIT
    sta DeviceNumber

;; Has the unit talk on its error channel.
;; Also: EREAD (K4S79, HVK4)
SendTalk:
    jsr KernalTalk
    lda #COMMAND_CHANNEL
    sta SecondaryAddress
    jsr KernalSendSecondary
    ldy #$FF

;; Stores the next character received, until a carriage return. The `bne` after the store always branches: the
;; `cmp` that let the character through left zero clear.
;; Also: LOOP1 (K4S79, HVK4)
NextCharacter:
    iny
    jsr KernalReceiveByte
    cmp #CARRIAGE_RETURN
    beq Terminate
    sta (DiskStatusDescriptor+StringDescriptor::ADDRESS),y
    bne NextCharacter

;; Ends the text with a zero and releases the bus.
;; Also: ERREND (K4S79, HVK4)
Terminate:
    lda #0
    sta (DiskStatusDescriptor+StringDescriptor::ADDRESS),y
    jmp KernalUntalk
    .endproc

    .endscope

    .scope Statements continued
    ; `HEADER` and `DCLOSE`.

    ;; `HEADER`: formats a disk, with a new disk ID when `I` gives one, after asking in direct mode.
    ;;
    ;; It closes the unit's files before it asks, so they are closed even when the answer is no. A result of 20 or
    ;; more prints the bad-disk message in direct mode.
    ;; Errors: SYNTAX without a name and a drive, or with another parameter but a unit and the disk ID
    ;; Also: FORMAT (K4S79, HVK4)
    .proc Header
    jsr Disk::ParseParameters
    jsr Disk::CheckSingleName
    and #PARSED_FIRST_NAME | PARSED_FIRST_DRIVE
    cmp #PARSED_FIRST_NAME | PARSED_FIRST_DRIVE
    beq Confirm

;; Jumps on to <SyntaxError>.
;; Also: FERRO (K4S79, HVK4)
Reject:
    jmp SyntaxError

;; Closes the unit's files, then asks; a no returns.
;; Also: DFORMA (K4S79, HVK4)
Confirm:
    jsr Disk::CloseDeviceFiles
    jsr Disk::Confirm
    bcc Build
    rts

;; Chooses the template's length: with an ID, the ID too.
;; Also: FBUILD (K4S79, HVK4)
Build:
    ldy #TEMPLATE_HEADER
    lda #TEMPLATE_HEADER_LENGTH - 2
    ldx DiskId
    beq Send
    lda #TEMPLATE_HEADER_LENGTH

;; Sends the new command.
;; Also: FCONT (K4S79, HVK4)
Send:
    jsr Disk::SendCommand

;; Reads the result: an error number of 20 or more is a bad disk.
;; Also: FERRS (K4S79, HVK4)
CheckResult:
    jsr Disk::ReadStatus
    ldy #0
    lda (DiskStatusDescriptor+StringDescriptor::ADDRESS),y
    cmp #'2'
    bcs ToBadDisk
    rts

;; Jumps on to <Disk::BadDisk>.
;; Also: FERRP (K4S79, HVK4)
ToBadDisk:
    jmp Disk::BadDisk
    .endproc

    ;; `DCLOSE`: closes a disk file, or with no file number all the unit's files, forgetting `DS$`.
    ;; Errors: SYNTAX for a parameter other than a file number and a unit
    ;; Also: DCLOSE (K4S79, HVK4)
    .proc DClose
    jsr Disk::ParseParameters
    and #~(PARSED_FILE | PARSED_UNIT) & $FF
    beq Close
    jmp SyntaxError

;; Forgets `DS$`, then closes the file, or all the unit's files.
;; Also: DCLSE (K4S79, HVK4)
Close:
    jsr ForgetDiskStatus
    lda LogicalFile
    beq Disk::CloseDeviceFiles
    jmp KernalCloseLogicalFile
    .endproc

    .endscope

    .scope Disk continued
    ; Closing a unit's files.

    ;; Closes every open file on <DeviceNumber>, looking through the file tables again after each close.
    ;; Also: DCLALL (K4S79, HVK4)
    .proc CloseDeviceFiles
    lda DeviceNumber
    ldx OpenFileCount

;; Steps down the file tables.
;; Also: DCLLP (K4S79, HVK4)
NextFile:
    dex
    bmi Done
    cmp DeviceTable,x
    bne NextFile
    lda LogicalFileTable,x
    jsr KernalCloseFileAt
    clv
    bvc CloseDeviceFiles

;; Returns once no file of the unit is open.
;; Also: DCLBYE (K4S79, HVK4)
Done:
    rts
    .endproc

    ;; Sends the drive the position command for `RECORD`'s file: its channel, the record and the byte in it.
    ;; In: LogicalFile = the file, PokeAddress = the record, RecordPosition = the byte
    ;; Errors: `FILE NOT OPEN` when the file is not open
    ;; Also: BOBREC (K4S79, HVK4)
    .proc PositionRecord

    ;; The record number <Statements::Record> left in <PokeAddress>'s bytes.
    RecordNumber = PokeAddress

    lda LogicalFile
    jsr KernalFindLogicalFile
    beq FileOpen
    ldy #FileNotOpenMessage - KernalMessages
    jmp KernalReportMessage

;; Takes the file's channel from its table entries and forgets `DS$`.
;; Also: DRECG (K4S79, HVK4)
FileOpen:
    jsr KernalLoadFileEntry
    jsr ForgetDiskStatus

;; Builds the command and sends it on the command channel.
;; Also: DREBLD (K4S79, HVK4)
Build:
    lda #'P'
    sta DiskCommandBuffer
    lda SecondaryAddress
    sta DiskCommandBuffer+1
    lda RecordNumber
    sta DiskCommandBuffer+2
    lda RecordNumber+1
    sta DiskCommandBuffer+3
    lda RecordPosition
    sta DiskCommandBuffer+4
    ldx #POSITION_COMMAND_LENGTH
    jsr SetCommandName
    jmp OpenCommandChannel
    .endproc

    .endscope

    .scope Statements continued
    ; `COLLECT` and `BACKUP`.

    ;; `COLLECT`: validates a disk, freeing the blocks no file uses, after closing the unit's files.
    ;; Errors: SYNTAX for a parameter other than a drive and a unit
    ;; Also: COLECT (K4S79, HVK4)
    .proc Collect
    jsr Disk::ParseParameters
    jsr Disk::CheckDriveOnly

;; Closes the unit's files and chooses the template's length: with a drive, its digit too.
;; Also: DCOLLE (K4S79, HVK4)
CloseFiles:
    jsr Disk::CloseDeviceFiles
    ldy #TEMPLATE_COLLECT
    ldx #TEMPLATE_COLLECT_LENGTH - 1
    lda ParsedParameters
    and #PARSED_FIRST_DRIVE
    beq Send
    inx

;; Sends the validate command.
;; Also: DCOLL0 (K4S79, HVK4)
Send:
    txa
    jmp Disk::SendCommand
    .endproc

    ;; `BACKUP`: copies a whole disk to the unit's other drive, after closing the unit's files; then falls into
    ;; <Disk::SendCommand>.
    ;; Errors: SYNTAX without both drives, or with another parameter but a unit
    ;; Also: BACKUP (K4S79, HVK4)
    .proc Backup
    jsr Disk::ParseParameters
    and #PARSED_FIRST_DRIVE | PARSED_SECOND_DRIVE
    cmp #PARSED_FIRST_DRIVE | PARSED_SECOND_DRIVE
    beq CheckOthers

;; Jumps on to <SyntaxError>.
;; Also: BERRO (K4S79, HVK4)
Reject:
    jmp SyntaxError

;; Rejects the names, a file number, a record and a replacement.
;; Also: BBACK (K4S79, HVK4)
CheckOthers:
    lda ParsedParameters
    and #PARSED_FIRST_NAME | PARSED_SECOND_NAME | PARSED_FILE | PARSED_RECORD | PARSED_REPLACE
    bne Reject

;; Closes the unit's files and chooses the duplicate command.
;; Also: DBACKU (K4S79, HVK4)
CloseFiles:
    jsr Disk::CloseDeviceFiles
    ldy #TEMPLATE_BACKUP
    lda #TEMPLATE_BACKUP_LENGTH
    ; Falls into Disk::SendCommand.
    .endproc

    .endscope

    .scope Disk continued
    ; Sending a command.

    ;; Builds a command from a template, then falls into <Disk::OpenCommandChannel> to send it.
    ;; In: A = the template's length, Y = its offset less 1
    ;; Also: TRANS (K4S79, HVK4)
    .proc SendCommand
    jsr BuildCommand
    ; Falls into OpenCommandChannel.
    .endproc

    ;; Sends the command in <DiskCommandBuffer> to the unit's command channel, as an `OPEN` of it would.
    ;; In: FilenameLength and FilenamePointer = the command, DeviceNumber = the unit
    ;; Also: TRANS1 (K4S79, HVK4)
    .proc OpenCommandChannel
    lda #COMMAND_CHANNEL
    sta SecondaryAddress
    jsr KernalListen
    lda SecondaryAddress
    jmp KernalSendOpen
    .endproc

    .endscope

    .scope Statements continued
    ; `COPY` and `CONCAT`.

    ;; `COPY`: copies a file, or with two drives alone every file of one drive to the other.
    ;;
    ;; Both forms send the one template; for a whole drive the names are empty. Basic4.mac spells the routine DCOPY;
    ;; Commodore's kernal listing and its reconstruction (K4S79, HVK4) call it `COPY`, which in BASIC 4 is already
    ;; Microsoft's name for `StoreString::CopyCharacters`, so their name is here in prose.
    ;; Errors: SYNTAX for a file copy without two names, or with a file number, a record or a replacement
    ;; Also: DCOPY (UNKN)
    .proc Copy
    jsr Disk::ParseParameters
    and #PARSED_FIRST_DRIVE | PARSED_SECOND_DRIVE
    cmp #PARSED_FIRST_DRIVE | PARSED_SECOND_DRIVE
    bne CheckFiles
    lda ParsedParameters
    and #PARSED_FIRST_NAME | PARSED_SECOND_NAME | PARSED_FILE | PARSED_RECORD | PARSED_REPLACE
    beq Send

;; A file copy: checks the names and the options.
;; Also: COPY2 (K4S79, HVK4)
CheckFiles:
    lda ParsedParameters
    jsr Disk::CheckTwoNames

;; Loads the parameters' bits again, for nothing.
;; Also: COPCON (K4S79, HVK4)
LoadFlags:
    lda ParsedParameters

;; Sends the copy command.
;; Also: COPY3 (K4S79, HVK4)
Send:
    ldy #TEMPLATE_COPY
    lda #TEMPLATE_COPY_LENGTH
    jmp Disk::SendCommand
    .endproc

    ;; `CONCAT`: adds the first file to the end of the second.
    ;; Errors: SYNTAX without two names, or with a file number, a record or a replacement
    ;; Also: CONCAT (K4S79, HVK4)
    .proc Concat
    jsr Disk::ParseParameters
    jsr Disk::CheckTwoNames
    ldy #TEMPLATE_CONCAT
    lda #TEMPLATE_CONCAT_LENGTH
    jmp Disk::SendCommand
    .endproc

    .endscope

    .scope Disk continued
    ; Inserting a template's filenames and disk ID.

    ;; Makes the first filename the second as well, then falls into <Disk::AppendSecondName> to append it.
    ;;
    ;; Since it overwrites the second filename's pointer and length, a template inserts the second name first.
    ;; In: X = the command's length so far, Y = the template's offset
    ;; Out: X = past the name (for an empty name, one less: the separator is removed), A = Y = the template's offset,
    ;;   carry = set
    ;; Keeps: Y
    ;; Also: RSFN (K4S79, HVK4)
    .proc AppendFirstName
    lda FilenameLength
    sta SecondFilenameLength
    lda FilenamePointer
    sta SecondFilenamePointer
    lda FilenamePointer+1
    sta SecondFilenamePointer+1
    ; Falls into AppendSecondName.
    .endproc

    ;; Appends the second filename to <DiskCommandBuffer> at X, or, when it is empty, removes the separator before
    ;; it.
    ;; In: X = the command's length so far, Y = the template's offset
    ;; Out: X = past the name (for an empty name, one less: the separator is removed), A = Y = the template's offset,
    ;;   carry = set
    ;; Keeps: Y
    ;; Also: RDFN (K4S79, HVK4)
    .proc AppendSecondName
    tya
    pha
    ldy SecondFilenameLength
    beq Empty
    ldy #0

;; Copies one character.
;; Also: RDMOV (K4S79, HVK4)
NextCharacter:
    lda (SecondFilenamePointer),y
    sta DiskCommandBuffer,x
    inx
    iny
    cpy SecondFilenameLength
    bne NextCharacter
    beq Done

;; Removes the separator before an empty name.
;; Also: RDRT0 (K4S79, HVK4)
Empty:
    dex

;; Restores Y and sets carry.
;; Also: RDRT1 (K4S79, HVK4)
Done:
    pla
    tay
    sec
    rts
    .endproc

    ;; Appends the two characters of <DiskId> to <DiskCommandBuffer> at X.
    ;; In: X = the command's length so far
    ;; Out: X = past the ID, A = X
    ;; Keeps: Y
    ;; Also: RID (K4S79, HVK4)
    .proc AppendDiskId
    lda DiskId
    sta DiskCommandBuffer,x
    inx
    lda DiskId+1
    sta DiskCommandBuffer,x
    inx
    txa
    rts
    .endproc

    .endscope

    .scope Statements continued
    ; `DSAVE`, `DLOAD`, `RENAME` and `SCRATCH`.

    ;; `DSAVE`: saves the program to a disk file, replacing it when its name begins with `@`.
    ;; Errors: SYNTAX without a name, or with a parameter other than a drive, a unit and `@`
    ;; Also: DSAVE (K4S79, HVK4)
    .proc DSave
    jsr Disk::ParseParameters
    jsr Disk::RequireFirstName
    and #PARSED_SECOND_NAME | PARSED_FILE | PARSED_SECOND_DRIVE | PARSED_RECORD
    beq Save
    jmp SyntaxError

;; Chooses the name's template, with `@` before it when replacing.
;; Also: DSAVE2 (K4S79, HVK4)
Save:
    ldy #TEMPLATE_OPEN
    lda ParsedParameters
    and #PARSED_REPLACE
    beq NoReplace

;; Starts the command with `@`, then builds and saves.
;; Also: SAVLD0 (K4S79, HVK4)
Replace:
    lda #REPLACE_PREFIX
    sta DiskCommandBuffer
    ldx #1
    lda #TEMPLATE_NAME_LENGTH
    jsr Disk::BuildCommandAt
    jmp KernalBasicSave

;; Builds the command from its start and saves.
;; Also: SAVLD1 (K4S79, HVK4)
NoReplace:
    lda #TEMPLATE_NAME_LENGTH
    jsr Disk::BuildCommand
    jmp KernalBasicSave
    .endproc

    ;; `DLOAD`: loads a program from a disk file.
    ;; Entry:
    ;;   Reject = jumps to <SyntaxError>; <Statements::Rename> branches here
    ;; Errors: SYNTAX without a name, or with a parameter other than a drive and a unit
    ;; Also: DLOAD (K4S79, HVK4)
    .proc DLoad
    jsr Disk::ParseParameters
    jsr Disk::RequireFirstName
    and #PARSED_SECOND_NAME | PARSED_FILE | PARSED_SECOND_DRIVE | PARSED_RECORD | PARSED_REPLACE
    beq Load

;; Jumps on to <SyntaxError>.
;; Also: DLOERR (K4S79, HVK4)
Reject:
    jmp SyntaxError

;; Builds the name, clears <LoadVerifyFlag> for a load, and loads.
;; Also: DLOAD2 (K4S79, HVK4)
Load:
    ldy #TEMPLATE_OPEN
    lda #TEMPLATE_NAME_LENGTH
    jsr Disk::BuildCommand
    lda #0
    sta LoadVerifyFlag
    jmp KernalLoadWithoutName
    .endproc

    ;; `RENAME`: renames a disk file, from the first name to the second.
    ;; Errors: SYNTAX without two names, or with a parameter other than a drive and a unit
    ;; Also: RENAME (K4S79, HVK4)
    .proc Rename
    jsr Disk::ParseParameters
    jsr Disk::RequireTwoNames
    and #PARSED_FILE | PARSED_SECOND_DRIVE | PARSED_RECORD | PARSED_REPLACE
    bne DLoad::Reject

;; Sends the rename command.
;; Also: DREN (K4S79, HVK4)
Send:
    ldy #TEMPLATE_RENAME
    lda #TEMPLATE_RENAME_LENGTH
    jmp Disk::SendCommand
    .endproc

    ;; `SCRATCH`: deletes disk files, after asking in direct mode, and in direct mode prints the drive's reply.
    ;;
    ;; Basic4.mac spells the routine DSCRTC; Commodore's kernal listing and its reconstruction (K4S79, HVK4) call it
    ;; `SCRTCH`, Microsoft's name for `EraseProgram`, so their name is here in prose.
    ;; Errors: SYNTAX without a name, or with a parameter other than a drive and a unit
    ;; Also: DSCRTC (UNKN)
    .proc Scratch
    jsr Disk::ParseParameters
    jsr Disk::CheckSingleName

;; Asks; a no returns.
;; Also: DSCRAT (K4S79, HVK4)
Confirm:
    jsr Disk::Confirm
    bcs Done
    ldy #TEMPLATE_SCRATCH
    lda #TEMPLATE_SCRATCH_LENGTH
    jsr Disk::SendCommand

;; In direct mode, reads the status and prints it between carriage returns.
;; Also: NUMSCR (K4S79, HVK4)
ShowResult:
    jsr Disk::TestDirect
    bne Done
    jsr Disk::ReadStatus
    lda #CARRIAGE_RETURN
    jsr ScreenOut
    ldy #0

;; Prints the status's next character, up to its zero.
;; Also: NUMLP (K4S79, HVK4)
NextCharacter:
    lda (DiskStatusDescriptor+StringDescriptor::ADDRESS),y
    cmp #0
    beq EndLine
    jsr ScreenOut
    iny
    bne NextCharacter

;; Prints the closing carriage return.
;; Also: NUMPRT (K4S79, HVK4)
EndLine:
    lda #CARRIAGE_RETURN
    jsr ScreenOut

;; Returns.
;; Also: NUMBYE (K4S79, HVK4)
Done:
    rts
    .endproc

    .endscope

    .scope Disk continued
    ; Direct mode, confirmation and the bad-disk message.

    ;; Tests for direct mode: whether <TextPointer> is in the input buffer's page.
    ;; Out: zero = set in direct mode
    ;; Keeps: X, Y
    ;; Also: DDIREC (K4S79, HVK4)
    .proc TestDirect
    lda TextPointer+1
    cmp #INPUT_BUFFER_PAGE

;; Returns.
;; Also: DXCR0 (K4S79, HVK4)
Done:
    rts
    .endproc

    ;; In direct mode, asks `ARE YOU SURE ?` and accepts `Y` or `YES`, then a carriage return; in a program,
    ;; accepts at once.
    ;;
    ;; A rejected answer is read to its carriage return. A zero read meanwhile ends the answer too, but as accepted.
    ;; Out: carry = set when the answer is no
    ;; Also: RUSURE (K4S79, HVK4)
    .proc Confirm
    jsr TestDirect
    bne Accepted

;; Asks, and restores the default channels to read the answer.
;; Also: RUSUR1 (K4S79, HVK4)
Ask:
    ldy #ConfirmMessage - KernalMessages
    jsr KernalPrintMessage
    jsr KernalRestoreChannels

;; Matches the answer against `Y` and `YES`.
;; Also: RUSUR2 (K4S79, HVK4)
ReadAnswer:
    jsr KernalInputCharacter
    cmp #'Y'
    bne Rejected
    jsr KernalInputCharacter
    cmp #CARRIAGE_RETURN
    beq Accepted
    cmp #'E'
    bne Rejected
    jsr KernalInputCharacter
    cmp #'S'
    bne Rejected
    jsr KernalInputCharacter
    cmp #CARRIAGE_RETURN
    beq Accepted

;; Reads the rest of a rejected answer to its carriage return, with carry set.
;; Also: ANSNO (K4S79, HVK4)
Rejected:
    cmp #CARRIAGE_RETURN
    sec
    beq Return
    jsr KernalInputCharacter
    bne Rejected

;; Clears carry: the answer is yes.
;; Also: ANSYES (K4S79, HVK4)
Accepted:
    clc
    ; Falls into Return.
    .endproc

;; Returns, for <Disk::Confirm> and <Disk::BadDisk>.
;; Also: ANSBYE (K4S79, HVK4)
Return:
    rts

    ;; In direct mode, prints the kernal's bad-disk message.
    ;; Also: BADDIS (K4S79, HVK4)
    .proc BadDisk
    jsr TestDirect
    bne Return
    ldy #BadDiskMessage - KernalMessages
    jmp KernalPrintMessage
    .endproc

    .endscope

    ;; Forgets the disk status last read, so that the next `DS` or `DS$` reads the drive again, and clears
    ;; <IoStatus>.
    ;;
    ;; It marks the status buffer as garbage for the linked-string collector: the back-link becomes the buffer's
    ;; length and $FF. The kernal's talk and listen routines call it.
    ;; Out: DiskStatusDescriptor = 0 (its length byte only), IoStatus = 0, A = Y
    ;; Keeps: X, Y
    ;; Also: OLDCLR (K4S79, HVK4)
    .proc ForgetDiskStatus
    tya
    pha
    lda DiskStatusDescriptor
    beq Clear
    ldy #STATUS_LENGTH
    tya
    sta (DiskStatusDescriptor+StringDescriptor::ADDRESS),y
    iny
    lda #$FF
    sta (DiskStatusDescriptor+StringDescriptor::ADDRESS),y

;; Clears <IoStatus> and the status's length.
;; Also: OLDCL1 (K4S79, HVK4)
Clear:
    lda #0
    sta IoStatus
    sta DiskStatusDescriptor
    pla
    tay
    rts
    .endproc

    .scope Disk continued
    ; The command builder.

    ;; Builds a command from a template at the start of <DiskCommandBuffer>, falling into <Disk::BuildCommandAt>.
    ;; In: A = the template's length, Y = its offset less 1
    ;; Out: FilenameLength = the command's length, FilenamePointer = <DiskCommandBuffer>
    ;; Also: SENDP (K4S79, HVK4)
    .proc BuildCommand
    ldx #0
    ; Falls into BuildCommandAt.
    .endproc

    ;; Forgets `DS$`, then expands a template into <DiskCommandBuffer> after the X bytes already there, and goes on
    ;; to <Disk::SetCommandName> to make it the kernal's filename (by a branch when the template ends; it falls in only
    ;; if X wraps past 255).
    ;;
    ;; Each insertion code is replaced by what it names; any other byte is copied, and a byte from $80 that is not a
    ;; code is dropped.
    ;; In: A = the template's length, Y = its offset less 1, X = the bytes already in the buffer
    ;; Out: FilenameLength = the command's length, FilenamePointer = <DiskCommandBuffer>
    ;; Also: SENDP1 (K4S79, HVK4)
    .proc BuildCommandAt
    sta TemplateCount
    jsr ForgetDiskStatus

;; Counts the template's bytes down and reads the next.
;; Also: SENDP2 (K4S79, HVK4)
NextByte:
    dec TemplateCount
    bmi SetCommandName
    iny
    lda CommandTemplates,y
    bpl StoreByte

    ; Each insertion returns with A no longer a code, so the tests after it fail.

;; Tests for the first filename.
;; Also: RXFN1 (K4S79, HVK4)
FirstName:
    cmp #INSERT_FIRST_NAME
    bne SecondName
    jsr AppendFirstName

;; Tests for the second filename.
;; Also: RXFN2 (K4S79, HVK4)
SecondName:
    cmp #INSERT_SECOND_NAME
    bne PutRecordLength
    jsr AppendSecondName

;; Tests for the record length, which is left out when it is 0.
;; Also: RXREC (K4S79, HVK4)
PutRecordLength:
    cmp #INSERT_RECORD_LENGTH
    bne PutDiskId
    lda RecordLength
    bne StoreByte

;; Tests for the disk ID.
;; Also: RXID (K4S79, HVK4)
PutDiskId:
    cmp #INSERT_DISK_ID
    bne FileType
    jsr AppendDiskId

;; Tests for the file's type.
;; Also: RXWRT (K4S79, HVK4)
FileType:
    cmp #INSERT_FILE_TYPE
    bne PutFirstDrive
    jsr ChooseFileType
    bne StoreByte

;; Tests for the first drive.
;; Also: RXD1 (K4S79, HVK4)
PutFirstDrive:
    cmp #INSERT_FIRST_DRIVE
    bne PutSecondDrive
    lda FirstDrive
    bpl DriveDigit

;; Tests for the second drive; any other byte is dropped.
;; Also: RXD2 (K4S79, HVK4)
PutSecondDrive:
    cmp #INSERT_SECOND_DRIVE
    bne NextByte
    lda SecondDrive

;; Makes the drive a digit.
;; Also: RXDD (K4S79, HVK4)
DriveDigit:
    ora #'0'

;; Stores the byte and goes on.
;; Also: RPLCE (K4S79, HVK4)
StoreByte:
    sta DiskCommandBuffer,x
    inx
    bne NextByte
    ; Falls into SetCommandName.
    .endproc

    ;; Makes the X bytes in <DiskCommandBuffer> the kernal's current filename.
    ;; In: X = the command's length
    ;; Out: FilenameLength = X, FilenamePointer = <DiskCommandBuffer>
    ;; Keeps: X, Y
    ;; Also: TRANR (K4S79, HVK4)
    .proc SetCommandName
    stx FilenameLength
    lda #<DiskCommandBuffer
    sta FilenamePointer
    lda #>DiskCommandBuffer
    sta FilenamePointer+1
    rts
    .endproc

    ;; Chooses the file's type or mode for `DOPEN`: `L` for a relative file, given a record length; otherwise `W`, to
    ;; write a sequential file, leaving `S` in <RecordLength> for the template's record slot.
    ;; Out: A = `L` or `W`, zero = clear
    ;; Keeps: X, Y
    ;; Also: RWRT (K4S79, HVK4)
    .proc ChooseFileType
    lda RecordLength
    beq Sequential
    lda #'L'
    bne Done

;; A sequential file to write: `W` here, and `S` as its type in the record slot.
;; Also: RWRT1 (K4S79, HVK4)
Sequential:
    lda #'S'
    sta RecordLength
    lda #'W'

;; Returns.
;; Also: RWRTS (K4S79, HVK4)
Done:
    rts
    .endproc

    .endscope
.endmacro
