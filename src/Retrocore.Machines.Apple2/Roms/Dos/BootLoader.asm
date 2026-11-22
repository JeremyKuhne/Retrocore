; retrocore: style=strict ignore=unlinked-name:PR|RWTS|INIT|APPEND|SAVE|BSAVE|VERIFY|READ -- stages, commands
;; DOS 3.3: the boot loader, the boot page's patches and RWTS's entry
;;
;; The two pages before RWTS, $B600-$B7FF where DOS runs ($3600-$37FF in the master image), hold the stages of a
;; boot that come after the Disk II's ROM, and the code that writes DOS to a disk for INIT. The boot chain:
;;
;; - `BOOT 0`, the controller's ROM at $Cn00 (Boot16.asm, docs/DiskII.md), reads track 0 sector 0 into $0800 and
;;   jumps to $0801 with X = slot * 16. Its sector reader, READ at $Cn5C, can be called again: it reads the sector
;;   in $3D into the page in $27 and comes back to $0801.
;; - `BOOT 1` is that sector, a copy of the page at <Boot::Stage1>. Running at $0800, it calls READ once for each of
;;   track 0's first ten sectors, reading them backwards into $BF00 down to $B600 (the master: $3F00 to $3600),
;;   then jumps to the page after its own copy: $B700, or the master's $3700.
;; - `BOOT 2`, <Boot::Stage2>, uses RWTS, which `BOOT 1` has just loaded with it, to read the rest of DOS from tracks 0
;;   to 2: $9D00-$B5FF, or the master's $1B00-$35FF. It resets the screen and keyboard and ends at
;;   <Boot::StartDos::ToDos>.
;; - That jumps to the relocator on a master (Relocator.asm), which moves DOS to the top of memory, or straight to
;;   DBINIT, DOS's cold start (DosInit.asm), on a disk INIT wrote. The relocator changes the jump to DBINIT, so
;;   every disk INIT writes boots straight into DOS.
;;
;; Between `BOOT 1` and the end of its page are patches made to DOS 3.3 later (AppendFix, <SaveAndVerify>); after
;; `BOOT 2` come <CallRwts>, the entry DOS and programs call RWTS through, a helper of the file manager's, and the
;; IOB and DCT that DOS passes to RWTS (IoBlock.asm). docs/Dos.md explains how DOS boots.

    ; Leftover: the end of the page before, which Apple's source fills to the page boundary.
    Leftover $FD, $00
    Leftover $FE, $00
.assert <* = 0, "The boot page starts a page."

;; The boot loader: `BOOT 1`, the boot sector that the Disk II's ROM loads at $0800, and `BOOT 2`, which reads the rest
;; of DOS through RWTS and starts it, with the code that writes DOS to a new disk for INIT.
;;
;; DOS keeps both stages in its boot loader's pages, $B600-$B7FF where DOS runs: <Boot::Stage1> is the copy of the
;; boot sector that INIT writes to track 0 sector 0, and <Boot::Stage2> the page after it. Their variables and
;; <Boot::TransferPages>, the loop that reads or writes a run of pages through RWTS, are shared by the boot and by
;; <Boot::WriteDos>. docs/Dos.md explains how DOS boots, and docs/DiskII.md the boot ROM.
.scope Boot

;; Where `BOOT 0` loads the boot sector and where `BOOT 1` runs, $0800.
;;
;; `BOOT 1`'s absolute addresses point into this copy of its page, not into <Stage1> where DOS keeps it: Apple's
;; listing makes each from $800 plus the byte's offset in the page (BHERE2 to BHERE5).
RunAddress = $0800

;; The pointer to the page the boot ROM's sector reader fills, the ROM's <Boot16:BUFFER> (2 bytes).
;;
;; `BOOT 1` sets its high byte to each page in turn, down from $BF, before it calls READ. On the first entry the ROM
;; has left it at $09, the page after the boot sector, which is how `BOOT 1` knows it has just started.
;; See: <Sector>, <JumpVector>, <Boot16:BUFFER>
;; Also: POINTA (DOS33)
BufferPointer = LowResBase

;; The slot times 16, which the boot ROM keeps here as <Boot16:SLOTX16>.
;;
;; `BOOT 1` makes READ's address, $Cn5C, from it, and passes it on in X, to READ and to `BOOT 2`.
;; See: <JumpVector>, <Boot16:SLOTX16>
;; Also: BSLOT (DOS33)
SlotTimes16 = ScrollBaseHigh

;; The sector the boot ROM's sector reader reads next, the ROM's <Boot16:SECTOR>.
;;
;; `BOOT 1` sets it from <Stage1::SectorOrder> before each call, reading DOS's sectors backwards from the last page
;; down.
;; See: <BufferPointer>, <Stage1::SectorOrder>, <Boot16:SECTOR>
;; Also: BSECTR (DOS33)
Sector = Address1High

;; The address `BOOT 1` jumps through to call the ROM's sector reader, READ at $Cn5C (2 bytes).
;;
;; `BOOT 1` sets it on its first entry from <SlotTimes16> and <READ_OFFSET>. READ returns to $0801, `BOOT 1`'s own
;; entry, rather than to the jump.
;; See: <SlotTimes16>, <READ_OFFSET>
;; Also: BTEMP (DOS33)
JumpVector = Address2

;; The offset of READ, the boot ROM's sector reader, in the ROM's page: READ is at $Cn5C.
;; Also: BRETRY (DOS33)
READ_OFFSET = $5C

;; The high byte of the slot ROMs' pages: slot n's ROM is at $Cn00.
SLOT_ROM_HIGH = $C0

;; `BOOT 1`, the boot sector, track 0 sector 0, which `BOOT 0` loads at $0800 and enters at $0801.
;;
;; DOS keeps this copy of it at $B600 so that INIT can write it to new disks; it only runs at <RunAddress>, where
;; its absolute addresses point into the copy there. The first byte, 1, tells `BOOT 0` to read just this sector. On
;; the first entry, `BOOT 1` points <JumpVector> at READ in the ROM, and <Stage1::LoadAddress> at the last page to fill:
;; <FirstPage> (the boot page's own page number, $B6) plus <LastSector> (9). Each entry after that reads the next
;; sector down, until all ten are in; the last is sector 0 again, this sector, into $B600. Then it resets the
;; input and output hooks and the screen and jumps to <Stage2> with X = slot * 16. At $B600 where DOS runs.
;; In:    X = slot * 16, BufferPointer+1 = the page after the last one read ($09 on the first entry)
;; Also: TRK0LDR (DOS33), DOSLDR (DOS31)
.proc Stage1
.assert MASTER || * = $B600, "BOOT 1's copy is at $B600 where DOS runs."

;; The count of sectors `BOOT 0` reads, 1: the boot sector alone. Nothing reads it here.
;; Also: BOOTCNT (DOS33)
SectorCount = RunAddress + (* - Stage1)
    .byte 1

    ; `BOOT 0` enters here, at $0801, and READ comes back here after each sector.
    lda BufferPointer+1
    cmp #>RunAddress + 1
    bne NextSector

    ; The first entry: point JumpVector at READ, $Cn5C, and LoadAddress at the last page to fill.
    lda SlotTimes16
    lsr a
    lsr a
    lsr a
    lsr a
    ora #SLOT_ROM_HIGH
    sta JumpVector+1
    lda #READ_OFFSET
    sta JumpVector
    clc
    lda a:LoadAddress+1
    adc a:LastSector
    sta a:LoadAddress+1

    ; LastSector counts DOS's logical sectors down from 9 to 0; SectorOrder gives the physical sector to read for
    ; each.
;; Reads the next sector down into the next page down, through READ, which returns to $0801 and so comes back here.
;; Also: READNEXT (DOS33)
NextSector:
    ldx a:LastSector
    bmi ToStage2
    lda a:SectorOrder,x
    sta Sector
    dec a:LastSector
    lda a:LoadAddress+1
    sta BufferPointer+1
    dec a:LoadAddress+1
    ldx SlotTimes16
    jmp (JumpVector)

    ; LoadAddress has gone one page below the boot page; two more make it `BOOT 2`'s page.
;; All ten sectors are in: sets the input and output hooks back to the keyboard and screen, in case `BOOT 0` was
;; started with IN# or PR#, resets the text window and jumps to <Stage2>.
;; Also: GOLOADER (DOS33)
ToStage2:
    inc a:LoadAddress+1
    inc a:LoadAddress+1
    jsr SetKeyboard
    jsr SetScreen
    jsr InitDisplay
    ldx SlotTimes16
    jmp (LoadAddress)

;; The physical sector holding each of DOS's logical sectors 0 to 15 on track 0, as `BOOT 1` reads the table at
;; <RunAddress>.
;;
;; The address field of each sector holds its physical number, which READ looks for; DOS numbers sectors in a
;; different order, so that sectors it reads one after another are spread around the track. The order is
;; <PhysicalSectors>'.
;; Also: TABLE (DOS33)
SectorOrder = RunAddress + (* - Stage1)
    .byte $00, 13, 11
    .byte 09, 07, 05
    .byte 03, 01, 14
    .byte 12, 10, 08
    .byte 06, 04, 02, 15

;; The page `BOOT 1` loads into next, and at the end `BOOT 2`'s address, as a word at $08FD (2 bytes).
;;
;; Its low byte is the boot page's byte $FD, 0, and its high byte <FirstPage>.
;; Also: LOADADDR (DOS33)
LoadAddress = RunAddress + (FirstPage - 1 - Stage1)

;; <Boot::LastSector> as `BOOT 1` sees it at $08FF: the next logical sector to read, counted down to -1.
;; Also: BGRPGC (DOS33)
LastSector = RunAddress + (Boot::LastSector - Stage1)
.endproc

.endscope

;; The start of the relocator's third range of code, the boot page's patches up to <BootCodeEnd>
;; ($B65D-$B7DF where DOS runs). See Relocator.asm.
;; Also: SC3 (DOS33, DOS31)
BootCodeStart:

;; Apple's fix for APPEND at the end of a file, in the spare space of the boot page and, in the 1983 DOS, of the
;; nibble table's page.
;;
;; When a read for APPEND reaches the end of a file whose position is not 0, <AppendFix::EndOfData> sets
;; <AppendFix::EndOfFile>, so that <AppendFix::NextRecord> moves the record number on by one at the end of APPEND;
;; <AppendFix::CloseOnError> clears it on other errors. The 1980 DOS has these; the 1983 DOS's revision B patches add
;; <AppendFix::ClearUnlessAppend>, which clears the flag for every command but APPEND, and <AppendFix::Finish>.
.scope AppendFix

;; Set when a read reaches the end of a file whose position is not 0, so that the end of APPEND moves the record
;; number on by one.
;;
;; <EndOfData> sets it, and <CloseOnError>, <NextRecord> and <ClearUnlessAppend> clear it; <NextRecord> reads it.
;; Also: EOFFLAG (DOS33)
EndOfFile:
    .byte 0

;; Frees the current file's buffer, clears <EndOfFile> and reports the error, for a file manager call from
;; <RunFileRequest> that fails with an error other than END OF DATA.
;;
;; <FileBuffers::Find> finds the buffer of the file named in the command; a buffer whose name starts with 0 is free. It
;; goes on to <Errors::Report>, which reports the error in the parameter list's return code and does not come back.
;; In:    DosFileParameters::ReturnCode = the error
;; Also: CLOSFILE (DOS33)
.proc CloseOnError
    jsr FileBuffers::Find
    bcs Report

    ; Free the buffer.
    lda #0
    tay
    sta EndOfFile
    sta (WorkPointer),y

;; Reports the error, the file's buffer freed or not found.
;; Also: NOTFOUND (DOS33)
Report:
    lda DosFileParameters::ReturnCode
    jmp Errors::Report
.endproc

.if REVISION_B
;; The end of APPEND, once it has read to the end of the file: if <EndOfFile> is set, moves the record number in
;; the parameter list on by one; then clears the flag and finishes in <Finish>.
;; Also: BUMPER (DOS33)
.proc NextRecord
    lda EndOfFile
    beq ClearFlag
    inc DosFileParameters::Record
    bne ClearFlag
    inc DosFileParameters::Record+1

;; Clears <EndOfFile>, then finishes.
;; Also: GOBACK (DOS33)
ClearFlag:
    lda #0
    sta EndOfFile

    ; In the 1983 DOS, the patch's last part is after the delay routine (MsWait.asm), not in this page.
    jmp Finish
.endproc
.else
;; The end of APPEND, once it has read to the end of the file: if <EndOfFile> is set, moves the record number in
;; the parameter list on by one; then clears the flag and goes on to POSITION's file manager call.
;; Also: BUMPER (DOS33)
.proc NextRecord
    lda EndOfFile
    beq ClearFlag
    inc DosFileParameters::Record
    bne ClearFlag
    inc DosFileParameters::Record+1

;; Clears <EndOfFile>, then goes on.
;; Also: GOBACK (DOS33)
ClearFlag:
    lda #0
    sta EndOfFile

    ; The 1980 DOS goes straight on to the file manager call that READ and WRITE make (MiscCommands.asm).
    jmp Commands::FindAndPosition::CallPosition
.endproc
.endif

.endscope

;; The end of SAVE and BSAVE: writes the file through <RunFileRequest>, closes it, and then checks it as VERIFY does.
;;
;; LoadSave.asm jumps here; <Commands::Close> closes the file and <Commands::Verify> reads it back.
;; In:    A = the transfer to store in the parameter list
;; Also: VPATCH (DOS33)
.proc SaveAndVerify
    sta DosFileParameters::Transfer
    jsr RunFileRequest
    jsr Commands::Close
    jmp Commands::Verify
.endproc

; AppendFix: the end of data, for DOSGO.
.scope AppendFix continued

;; Sets <EndOfFile> for a file manager call from <RunFileRequest> that ends with END OF DATA, unless the file is empty.
;;
;; The file's position is the sector and byte in its file control block, at FilePointer. If it is not 0, the flag
;; is set. If it is 0, the file is empty: the record number and byte offset in the control block are copied to the
;; parameter list. Either way it goes back to <RunFileRequest::ReturnZero>, which returns a zero data byte.
;; In:    FilePointer = the file's control block
;; Also: EOFFIX (DOS33)
.proc EndOfData

;; The offset of the file's position, its sector and byte in the sector (4 bytes), in its file control block.
POSITION = FileManager::FileControlBlock::PositionSector - FileManager::FileControlBlock

;; The offset of the file's record number and byte in the record (4 bytes), in its file control block.
RECORD = FileManager::FileControlBlock::PositionRecord - FileManager::FileControlBlock

    ldy #POSITION

;; Tests the next byte of the position.
;; Also: CHKFILE (DOS33)
CheckPosition:
    lda (FilePointer),y
    bne SetFlag
    iny
    cpy #POSITION + 4
    bne CheckPosition

    ; The position is 0: copy the record and byte to the parameter list.
    ldy #RECORD

;; Copies the next byte of the record and byte to the parameter list.
;; Also: MOVE (DOS33)
CopyPosition:
    lda (FilePointer),y
    sta DosFileParameters::Record - RECORD,y
    iny
    cpy #RECORD + 4
    bne CopyPosition

;; Goes back to <RunFileRequest>, which returns a zero data byte.
;; Also: BACK (DOS33)
Return:
    jmp RunFileRequest::ReturnZero

;; The position is not 0: sets the flag.
;; Also: FIXIT (DOS33)
SetFlag:
    ldx #$FF
    stx EndOfFile
    bne Return                      ; always
.endproc

.assert EndOfData::POSITION = $13 && EndOfData::RECORD = $19, "The position and record bytes of the FCB."
.assert DosFileParameters::ByteOffset = DosFileParameters::Record + 2, "The record, then the byte."

.endscope

.if LOWERCASE_INPUT
;; Turns the input line's lowercase letters into capitals, outside quotes, for the command scanner.
;;
;; A build option of Apple's source (ULC = 1), which no DOS 3.3 was built with; CommandScan.asm calls it under the
;; same option. It ends at the line's return, setting CMDNO to $FF, no command found yet.
;; In:    X = the first character's index in InputBuffer
;; Out:   Y = $FF
;; Uses:  A, X
;; Also: UPRCASE (DOS33)
.proc Uppercase

;; The quote that starts a quoted run, with its high bit set.
QUOTE = '"' | $80

;; The first character that is lowercased, $E0 (` with its high bit set): the lowercase letters follow it.
FIRST_LOWERCASE = $E0

;; Clears bit 5, turning a lowercase letter into its capital.
UPPERCASE_MASK = $DF

;; Tests the next character: a quote starts a quoted run.
;; Also: LUP1 (DOS33)
Scan:
    lda InputBuffer,x
    cmp #QUOTE
    bne CheckLowercase

;; Skips the characters inside quotes, up to the closing quote or the return.
;; Also: LUP2 (DOS33)
SkipQuoted:
    inx
    lda InputBuffer,x
    cmp #QUOTE
    beq Next
    cmp #KEY_RETURN
    bne SkipQuoted

;; At the return: no command yet, and done.
;; Also: ULFINI (DOS33)
Finish:
    ldy #$FF
    sty CommandOffset
    rts

;; Capitalizes a lowercase letter.
;; Also: CHK4UC (DOS33)
CheckLowercase:
    cmp #FIRST_LOWERCASE
    bcc CheckReturn
    and #UPPERCASE_MASK
    sta InputBuffer,x

;; The return ends the line.
;; Also: CHK4CR (DOS33)
CheckReturn:
    cmp #KEY_RETURN
    beq Finish

;; Goes on to the next character.
;; Also: NEXTCHR (DOS33)
Next:
    inx
    bne Scan
.endproc
.endif

; Zeros up to the boot page's last three bytes (Apple's BHERE1 marks where the patches end). In Apple's listing the
; APPEND fix's last part is here; the 1983 master has it after the delay routine (MsWait.asm).
.if YEAR = 1983
    .res $FD - <*, 0
.else
    ; Leftover: what the 1980 master holds here.
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $20, $58, $FC
    .byte $A9, $C2, $20, $ED, $FD, $A9, $01, $20, $DA, $FD, $A9, $AD, $20, $ED, $FD, $A9
    .byte $00, $20, $DA, $FD, $60, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.endif

; Boot: `BOOT 1`'s variables at the end of the boot page, `BOOT 2` and the INIT writer.
.scope Boot continued

.assert <* = $FD, "BOOT 1's variables are the boot page's last three bytes."

    ; The boot page's last three bytes are `BOOT 1`'s variables. The first is the low byte of Stage1::LoadAddress,
    ; whose high byte starts as FirstPage.
    .byte 0

;; The page of <Stage1>: where `BOOT 1` loads track 0's sectors, from this page up.
;;
;; <WriteDos> sets it to where the running DOS is, so that a disk takes its loader to the same place.
;; Also: GRSPG (DOS33, DOS31)
FirstPage:
    .byte >Stage1

;; The last logical sector `BOOT 1` reads, 9: it reads sectors 9 down to 0, ten pages from <Stage1> to the end of
;; DOS.
;;
;; <WriteDos> sets it. `BOOT 1` counts it down at $08FF, as <Stage1::LastSector>.
;; Also: GRPGC (DOS33, DOS31)
LastSector:
    .byte >(DosEnd - Stage1 - $100)

;; The number of pages of the boot tracks' last stretch, from <Stage1> to the end of DOS: track 0 sectors 0 to 9.
BOOT_PAGES = 10

;; The track of the last page below <Stage1>, the first that <Stage2> reads and <WriteDos> writes.
DOS_LAST_TRACK = 2

;; The sector of that page.
DOS_LAST_SECTOR = 4

;; `BOOT 2`, which reads the rest of DOS through RWTS and starts it; `BOOT 1` jumps here.
;;
;; It reads <DosPages> pages from track 2 sector 4 backwards to track 0 sector 12 (the master: sector 10), into the
;; pages from just below <Stage1> down. `BOOT 1` left RWTS and this page in place. It records the boot slot and drive
;; 1 in the IOB, and tells RWTS that the drive's head is on track 0 (RWTS keeps each drive's half-track at
;; <Drive1HalfTracks> and <Drive2HalfTracks> plus the slot; `BOOT 0` left the head on track 0). Falls into
;; <StartDos>. At $B700 where DOS runs (the master: $3700).
;; In:    X = slot * 16
;; Also: DOSLODR (DOS33)
.proc Stage2
.assert MASTER || * = $B700, "BOOT 2 is at $B700 where DOS runs."

    ; The boot slot and drive 1, as this call's and the last call's.
    stx a:DosIob::SlotTimes16
    stx a:DosIob::PreviousSlot
    lda #1
    sta a:DosIob::PreviousDrive
    sta a:DosIob::Drive

    ; DosPages pages, read from the last one down.
    lda a:DosPages
    sta a:PagesLeft
    lda #DOS_LAST_TRACK
    sta a:DosIob::Track
    lda #DOS_LAST_SECTOR
    sta a:DosIob::Sector
    ldy a:Stage1Address+1
    dey
    sty a:DosIob::Buffer+1          ; the page below Stage1 first
    lda #RWTS_READ
    sta a:DosIob::Command

    ; Both of the slot's drives are on half-track 0.
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda #0
    sta Drive2HalfTracks,x
    sta Drive1HalfTracks,x
    jsr TransferPages
    ; Falls into StartDos.
.endproc

;; Starts DOS, now that it is in memory.
;;
;; A new stack, the IOB's volume set to $FF as the file manager leaves it, the screen and language card reset
;; (<ResetScreenAndCard>, in DosPatches.asm, which comes back to <StartDos::AfterReset>), the keyboard as input, then on
;; to <StartDos::ToDos>.
;; Entry: AfterReset = where RCPATCH comes back
;; Also: DOSINT (DOS33, DOS31)
.proc StartDos
    ldx #$FF
    txs
    stx a:DosIob::Volume
    jmp ResetScreenAndCard

;; Where <ResetScreenAndCard> (DosPatches.asm) comes back to, once it has reset the screen and language card.
;; Also: RCBACK (DOS33)
AfterReset:
    jsr SetKeyboard

;; The end of a boot: jumps to the relocator on a master.
;;
;; The relocator rewrites the jump's address to DBINIT, DOS's cold start, in the copy it moves; in the build where
;; DOS runs, <RelocateDos> is DBINIT itself.
;; Also: DI3 (DOS33, DOS31)
ToDos:
    jmp RelocateDos
.endproc

;; Writes DOS to tracks 0 to 2 of a disk, for INIT, once <PrepareWrite> has set the IOB's buffer to DOS's first
;; page.
;;
;; First the pages from there up to <Stage1>, from track 2 sector 4 backwards (the last page first). Then the ten
;; pages from <Stage1> to the end of DOS, to track 0 sectors 9 down to 0: the boot sector, `BOOT 2` and RWTS. Before
;; that, <FirstPage> is set to this DOS's boot page and <LastSector> to 9, so the boot sector written loads to where
;; this DOS is. The first pass leaves the IOB's track at 0 for the second. FileManagerIo.asm calls it.
;; Errors: carry = set if RWTS failed on the last sector (<TransferPages> does not stop on an error)
;; Also: WBOOT (DOS33, DOS31)
.proc WriteDos

    ; The pages below Stage1, from the last one down.
    lda a:Stage1Address+1
    sec
    sbc a:DosIob::Buffer+1
    sta a:PagesLeft
    lda a:Stage1Address+1
    sta a:DosIob::Buffer+1
    dec a:DosIob::Buffer+1
    lda #DOS_LAST_TRACK
    sta a:DosIob::Track
    lda #DOS_LAST_SECTOR
    sta a:DosIob::Sector
    lda #RWTS_WRITE
    sta a:DosIob::Command
    jsr TransferPages

    ; The ten boot pages, the boot sector's variables set for this DOS.
    lda a:Stage1Address+1
    sta FirstPage
    clc
    adc #BOOT_PAGES - 1
    sta a:DosIob::Buffer+1
    lda #BOOT_PAGES
    sta a:PagesLeft
    sec
    sbc #1
    sta LastSector
    sta a:DosIob::Sector
    jsr TransferPages
    rts
.endproc

    ; Unused.
    .res 6, 0

;; Reads or writes <PagesLeft> pages through RWTS, as the IOB says, from the page and sector it gives backwards.
;;
;; After each page, one page lower in memory and one sector lower on the disk, from sector 0 to sector 15 of the
;; track before. It does not stop on an error: the carry it returns is that of the last page.
;; Out:   carry = clear if the last page succeeded, set if not (the error in <DosIob::ReturnCode>)
;; Also: BOOTIO (DOS33, DOS31)
.proc TransferPages
    lda a:IobAddress+1
    ldy a:IobAddress
    jsr CallRwts

    ; The sector before, the last of the track before after sector 0. The two NOPs keep the routine as long as DOS
    ; 3.2's, whose test for the end of a track (counting up to 13) takes two bytes more.
    ldy a:DosIob::Sector
    dey
    bpl NextSector
    ldy #SECTORS_PER_TRACK - 1
    nop
    nop
    dec a:DosIob::Track

;; Stores the next sector and steps the buffer and the count.
;; Also: BIO1 (DOS33, DOS31)
NextSector:
    sty a:DosIob::Sector
    dec a:DosIob::Buffer+1
    dec a:PagesLeft
    bne TransferPages
    rts
.endproc

.endscope

;; Calls RWTS with interrupts off, since RWTS's timing must not be interrupted.
;;
;; The vector at $03D9 comes here, as do the file manager and DOS's start (DosInit.asm). At $B7B5 where DOS runs.
;; In:    A = the IOB's address's high byte, Y = its low byte
;; Out:   carry = clear if the call succeeded, set if not (the error in the IOB's return code), X = slot * 16
;; Keeps: interrupt, decimal
;; Also: DISKIO (DOS33)
.proc CallRwts
.assert MASTER || * = $B7B5, "CallRwts is at $B7B5 where DOS runs."
    php
    sei
    jsr Rwts
    bcs Failed

    ; PLP brings back the caller's interrupt flag, and its carry with it: the carry is then cleared or set again.
    plp
    clc
    rts

;; RWTS set the carry: brings back the caller's flags, and sets the carry again.
;; Also: DSKERR (DOS33)
Failed:
    plp
    sec
    rts
.endproc

; Boot: the INIT writer's preparation.
.scope Boot continued

;; Prepares the IOB for <WriteDos>: the buffer at DOS's first page, and the volume.
;;
;; The page is the parameter list's image page, which INIT takes from <WriteStartAddress>; the volume comes from the
;; file control block, which holds it inverted. FileManagerIo.asm calls it.
;; Uses:  A
;; Keeps: X, Y
;; Also: DLDSUP (DOS33, DOS31)
.proc PrepareWrite
    lda DosFileParameters::ImagePage
    sta a:DosIob::Buffer+1
    lda #0
    sta a:DosIob::Buffer
    lda FileManager::FileControlBlock::VolumeComplement
    eor #$FF
    sta a:DosIob::Volume
    rts
.endproc

.endscope

;; Zeros the page at <FilePointer>, for the file manager.
;; Out:   A = 0, Y = 0
;; Keeps: X
;; Also: CLRSEC (DOS33, DOS31)
.proc ClearSector
    lda #0
    tay

;; Zeros the next byte.
;; Also: CS1 (DOS33, DOS31)
Loop:
    sta (FilePointer),y
    iny
    bne Loop
    rts
.endproc

    ; Unused.
    brk

;; The end of the relocator's third range of code, the byte after it ($B7E0 where DOS runs).
;; Also: EC3 (DOS33, DOS31)
BootCodeEnd:

; Boot: `BOOT 2`'s variables.
.scope Boot continued

;; The number of pages `BOOT 2` reads: from <ImageStart> up to <Stage1>, 25 ($19) where DOS runs, 27 ($1B) on the
;; master, which includes the relocator.
;; Also: NDPGS (DOS33, DOS31)
DosPages:
    .byte >(Stage1 - ImageStart)

;; The pages left for <TransferPages> to read or write.
;; Also: BRWCNT (DOS33, DOS31)
PagesLeft:
    Leftover $00, $02

    ; Two bytes no code reads, $0A (10) and $1B (27): where DOS 3.2 keeps the sector and page `BOOT 2` starts at
    ; (DOS 3.1's BSDSEC and BGNDOS).
    .byte $0A
    .byte $1B

;; The IOB's address, for <TransferPages>; the relocator adjusts it.
;; Also: BAIOB (DOS33, DOS31)
IobAddress:
    .word DosIob

;; The address of <Stage1>, the boot page: `BOOT 2` loads DOS below it and <WriteDos> writes from it. The relocator
;; adjusts it.
;; Also: ADOSLD (DOS33, DOS31)
Stage1Address:
    .word Stage1

.endscope

.include "IoBlock.asm"

    ; Unused: the page's last byte.
    .res 1, 0
