; retrocore: style=strict
; COMMODORE 1541 DOS: THE COMMAND CHANNEL AND THE COMMANDS ($C000-$CE0D)

;; The $C000 chip's first byte, $97, chosen so the start-up's sum of the chip comes to its first page, $C0.
;; Also: CCHKSM (D1541)
LowerRomChecksum:
    .byte $97

;; The $C000 chip's unused bytes to $C0FF, filled with $AA.
;; Also: FREEC0 (D1541)
PatchSpace:
    .res 255, $AA

;; Lights DRVNUM's LED in LEDPRT, LED0 for drive 0 (LED1 is 0: the 1541 has one), the other cleared; interrupts off
;; meanwhile. Top level (Q9).
;; Also: SETLDS (D1541)
.proc TurnOnActivityLed
    sei
    lda #$F7
    and DriveControl
    pha
    lda DriveNumber
    beq Drive0
    pla
    ora #LED_DRIVE1
    bne Store

;; Drive 0: LED0.
;; Also: LEDS0 (D1541)
Drive0:
    pla
    ora #LED_DRIVE0

;; Writes LEDPRT.
;; Also: LEDS1 (D1541)
Store:
    sta DriveControl
    cli
    rts
    sei
    lda #$08
    ora DriveControl
    sta DriveControl
    cli
    rts
.endproc
.scope Errors

;; Stops the error LED's flashing: ERWORD and ERLED = 0.
;; Also: ERROFF (D1541)
.proc StopFlashing
    lda #$00
    sta ErrorFlash
    sta ErrorLed
    rts
.endproc

;; Starts the flashing: ERWORD = `$50` (80 decimal), ERLED = drive 0's mask from <LedMasks>, and that LED on; X kept,
;; interrupts off meanwhile.
;; Also: ERRON (D1541)
.proc StartFlashing
    sei
    txa
    pha
    lda #$50
    sta ErrorFlash
    ldx #$00
    lda LedMasks,x
    sta ErrorLed
    ora DriveControl
    sta DriveControl
    pla
    tax
    cli
    rts
.endproc
.endscope
.scope Commands continued

;; Runs the command in CMDBUF: WBAM cleared, DRVNUM from LSTDRV, the error channel to 00 OK; a string that came with an
;; OPEN on a data channel (ORGSA bit 7, channel not 15) is a file name, for Files' OPEN. Otherwise the first letter is
;; looked up in <CommandLetters> and its handler jumped to through <CommandRoutinesLow> and <CommandRoutinesHigh>, R, S
;; and N with their names parsed first.
;; Also: PARSXQ (D1541)
.proc Execute
    lda #$00
    sta BamWriteDeferred
    lda LastDrive
    sta DriveNumber
    jsr Errors::SetOk
    lda SecondaryCommand
    bpl CommandChannel
    and #$0F
    cmp #$0F
    beq CommandChannel
    jmp Files::Open

;; A command: CMDSIZ and the tables set up, the first letter into CHAR.
;; Also: PS05 (D1541)
CommandChannel:
    jsr Prepare
    lda (CommandPointer),y
    sta Character
    ldx #COUNT-1

;; Each of <CommandLetters>' letters, from the last; none matches: 31 SYNTAX ERROR.
;; Also: PS10 (D1541)
Search:
    lda CommandLetters,x
    cmp Character
    beq Found
    dex
    bpl Search
    lda #ERROR_INVALID_COMMAND
    jmp Fail

;; CMDNUM = the command's number; from PCMD on (R, S, N), <ParseNames> first.
;; Also: PS20 (D1541)
Found:
    stx CommandNumber
    cpx #FIRST_PARSED
    bcc Dispatch
    jsr ParseNames

;; The handler's address from <CommandRoutinesLow> and <CommandRoutinesHigh> into TEMP, and jumps there.
;; Also: PS30 (D1541)
Dispatch:
    ldx CommandNumber
    lda CommandRoutinesLow,x
    sta Temporary
    lda CommandRoutinesHigh,x
    sta Temporary+1
    jmp (Temporary)
.endproc

;; A command's successful end: WBAM cleared, then <Fail> if ERWORD holds an error; else the error channel's 00 OK with
;; track and sector 0, then the drive remembered, the command buffer cleared and both internal channels, read (IRSA,
;; $11) and write (IWSA, $12), freed.
;; Entry:
;;   KeepBamFlag = OPEN ends here
;;   Report = Scratch ends here
;;   NoMessage = CLOSE ends here
;; Also: ENDCMD (D1541)
.proc Finish
    lda #$00
    sta BamWriteDeferred

;; OPEN ends here: as <Finish>, but WBAM left as it is.
;; Also: ENDSAV (D1541)
KeepBamFlag:
    lda ErrorFlash
    bne Fail
    ldy #$00
    tya
    sty Track

;; Scratch ends here: the message A (1, FILES SCRATCHED) with TRACK (the count) and sector Y.
;; Also: SCREND (D1541)
Report:
    sty Sector
    sty CommandPointer
    jsr Errors::SetMessage
    jsr Errors::StopFlashing

;; CLOSE ends here: no message; LSTDRV = DRVNUM, the drive's NODRV flag cleared, CMDBUF cleared, both internal channels
;; (IRSA and IWSA) freed.
;; Also: SCREN1 (D1541)
NoMessage:
    lda DriveNumber
    sta LastDrive
    tax
    lda #$00
    sta NoDrive,x
    jsr ClearBuffer
    jmp Files::FreeInternalChannels
.endproc

;; Zeroes the CMDLEN bytes of CMDBUF.
;; Also: CLRCB (D1541)
.proc ClearBuffer
    ldy #COMMAND_LENGTH_MAX-1
    lda #$00

;; Each byte, from the last.
;; Also: CLRB2 (D1541)
Loop:
    sta CommandBuffer,y
    dey
    bpl Loop
    rts
.endproc

;; Ends a command with error A: track and sector 0 in the message, then the error channel's handling (CMDER2), which
;; does not return.
;; Also: CMDERR (D1541)
.proc Fail
    ldy #$00
    sty Track
    sty Sector
    jmp Errors::Abort
.endproc

;; For a string that names at most a drive (I, V, OPEN of "$"): FILTBL = the place before ':', or 0 without one; then
;; <FindDrive>.
;; Also: SIMPRS (D1541)
.proc ParseDriveOnly
    ldx #$00
    stx FileNameStart
    lda #$3A
    jsr ScanFor
    beq ToFindDrive
    dey
    dey
    sty FileNameStart

;; Jumps to <FindDrive>.
;; Also: SP10 (D1541)
ToFindDrive:
    jmp FindDrive
.endproc

;; Scans the string from its start for ':' (<ScanFor>): Y just past it, or 0 with Z set; X = the commas before it.
;; Also: PRSCLN (D1541)
.proc FindColon
    ldy #$00
    ldx #$00
    lda #$3A
    jmp ScanFor
.endproc

;; From ':' and '=', each name's start in FILTBL, the counts F1CNT and F2CNT, F2PTR, and IMAGE, the string's shape (bit
;; 7 a pattern in the first names, 6 more than one, 5 first names given; 3, 2 and 1 the same for the second names; 0 no
;; second names). Bits the command's byte of <CommandPatterns> forbids are a syntax error.
;; Entry:
;;   AfterColon = With Y past ':' and X its commas, as <FindColon> leaves them (C comes here)
;;   Equals = With FILTBL set (LOAD comes here)
;; Also: TAGCMD (D1541)
.proc ParseNames
    jsr FindColon
    bne AfterColon

;; No ':', or a ',' before it: 34 SYNTAX ERROR (no file given).
;; Also: TC25 (D1541)
NoName:
    lda #ERROR_NO_NAME
    jmp Fail

;; With Y past ':' and X its commas, as <FindColon> leaves them (C comes here): FILTBL = the place before ':', where the
;; drive is.
;; Also: TC30 (D1541)
AfterColon:
    dey
    dey
    sty FileNameStart
    txa
    bne NoName

;; With FILTBL set (LOAD comes here): scans on for '='.
;; Also: TC35 (D1541)
Equals:
    lda #$3D
    jsr ScanFor
    txa
    beq FirstNames
    lda #$40

;; IMAGE's bits 5 and 0 (bit 6 too if more than one name); F1CNT = F2CNT = the names' count, so no second names yet; bit
;; 7 if any had a pattern, and PATFLG cleared.
;; Also: TC40 (D1541)
FirstNames:
    ora #$21
    sta Structure
    inx
    stx FirstStreamEnd
    stx SecondStreamEnd
    lda PatternFlag
    beq SecondNames
    lda #$80
    ora Structure
    sta Structure
    lda #$00
    sta PatternFlag

;; Y = 0: no '='. Otherwise the second names' start into FILTBL, F2PTR = F1CNT, and the rest of the string scanned (for
;; shifted RETURN, $8D, which ends it); F2CNT = the names in all.
;; Also: TC50 (D1541)
SecondNames:
    tya
    beq Check
    sta FileNameStart,x
    lda FirstStreamEnd
    sta SecondStreamStart
    lda #$8D
    jsr ScanFor
    inx
    stx SecondStreamEnd
    dex
    lda PatternFlag
    beq CountSecond
    lda #$08

;; Bit 2 if there is more than one second name.
;; Also: TC60 (D1541)
CountSecond:
    cpx FirstStreamEnd
    beq SecondGiven
    ora #$04

;; Bit 1 set and bit 0 cleared (one EOR does both), with bits 3 and 2.
;; Also: TC70 (D1541)
SecondGiven:
    ora #$03
    eor Structure
    sta Structure

;; IMAGE against the command's byte of <CommandPatterns>: no bit in both, and it returns.
;; Also: TC75 (D1541)
Check:
    lda Structure
    ldx CommandNumber
    and PATTERN_ORIGIN,x
    bne BadSyntax
    rts

;; ERWORD = the clashing bits; 30 SYNTAX ERROR.
;; Also: TC80 (D1541)
BadSyntax:
    sta ErrorFlash
    lda #ERROR_SYNTAX
    jmp Fail
.endproc

;; Scans CMDBUF from Y to CMDSIZ for the character A, on the way putting the start of each name after a ',' into
;; FILTBL+1,X and marking in PATTYP the names with '*' or '?' (PATFLG counts them). Returns Y just past the character,
;; or 0 with Z set if it is not there or there are MXFILS-1 (4) commas or more; FILTBL+1,X = CMDSIZ, the end.
;; Also: PARSE (D1541)
.proc ScanFor
    sta Character

;; The next character; the string's end is <NotFound>.
;; Also: PR10 (D1541)
Next:
    cpy CommandLength
    bcs NotFound
    lda (CommandPointer),y
    iny
    cmp Character
    beq Found
    cmp #$2A
    beq Pattern
    cmp #$3F
    bne Comma

;; '*' or '?': PATFLG counts it.
;; Also: PR20 (D1541)
Pattern:
    inc PatternFlag

;; A ',' ends a name: the next one's start into FILTBL+1,X.
;; Also: PR25 (D1541)
Comma:
    cmp #$2C
    bne Next
    tya
    sta FileNameStart+1,x
    lda PatternFlag
    and #$7F
    beq NextName
    lda #$80
    sta FileNamePattern,x
    sta PatternFlag

;; X on; at MXFILS-1 names, stops as <NotFound>.
;; Also: PR28 (D1541)
NextName:
    inx
    cpx #FILE_NAME_COUNT-1
    bcc Next

;; Y = 0.
;; Also: PR30 (D1541)
NotFound:
    ldy #$00

;; The last name's end, CMDSIZ, into FILTBL+1,X, and its pattern mark.
;; Also: PR35 (D1541)
Found:
    lda CommandLength
    sta FileNameStart+1,x
    lda PatternFlag
    and #$7F
    beq Return
    lda #$80
    sta FileNamePattern,x

;; A = Y, Z set if it is 0.
;; Also: PR40 (D1541)
Return:
    tya
    rts
.endproc

;; Sets CMDSIZ from the command buffer's count, without a RETURN at the end (or one before the last character); more
;; than CMDLEN characters is 32 SYNTAX ERROR (line too long), with CMDNUM = $FF. Then falls into ClearTables.
;; Entry:
;;   ClearTables = Clears the buffer's count, REC, TYPE, TYPFLG, F1PTR, F2PTR, F1CNT, F2CNT, PATFLG and ERWOR
;; Also: CMDSET (D1541)
.proc Prepare
    ldy $A3
    beq SetSize
    dey
    beq Whole
    lda CommandBuffer,y
    cmp #CARRIAGE_RETURN
    beq SetSize
    dey
    lda CommandBuffer,y
    cmp #CARRIAGE_RETURN
    beq SetSize
    iny

;; No RETURN: the whole count.
;; Also: CS07 (D1541)
Whole:
    iny

;; CMDSIZ = Y, and the length checked.
;; Also: CS08 (D1541)
SetSize:
    sty CommandLength
    cpy #COMMAND_LENGTH_MAX+1
    ldy #$FF
    bcc ClearTables
    sty CommandNumber
    lda #ERROR_LINE_TOO_LONG
    jmp Fail

;; Clears the buffer's count, REC, TYPE, TYPFLG, F1PTR, F2PTR, F1CNT, F2CNT, PATFLG and ERWORD, and the MXFILS entries
;; of FILTBL, ENTSEC, ENTIND, FILDRV, PATTYP, FILTRK and FILSEC. LOAD comes here to search by name alone.
;; Also: CMDRST (D1541)
ClearTables:
    ldy #$00
    tya
    sta $A3
    sta RecordSize
    sta FileType
    sta MatchType
    sta NameIndex
    sta SecondStreamStart
    sta FirstStreamEnd
    sta SecondStreamEnd
    sta PatternFlag
    sta ErrorFlash
    ldx #FILE_NAME_COUNT

;; Each table's entry X-1, from the last.
;; Also: CS10 (D1541)
ClearEntry:
    sta FileNameStart-1,x
    sta FileNameEntrySector-1,x
    sta FileNameEntryIndex-1,x
    sta FileNameDrive-1,x
    sta FileNamePattern-1,x
    sta FileNameTrack-1,x
    sta FileNameSector-1,x
    dex
    bne ClearEntry
    rts
.endproc

;; Takes only the first name: F1CNT = F2CNT, F2CNT = F2PTR = 1; falls into <SetDrives>.
;; Also: ONEDRV (D1541)
.proc SetFirstDrive
    lda SecondStreamEnd
    sta FirstStreamEnd
    lda #$01
    sta SecondStreamEnd
    sta SecondStreamStart
.endproc

;; For each name, 0 to F2CNT-1: its drive (<DriveOfName>) into FILDRV, bit 7 if it was not given, and FILTBL moved past
;; its ':'.
;; Also: ALLDRS (D1541)
.proc SetDrives
    ldy LastDrive
    ldx #$00

;; Each name, F1PTR keeping the index.
;; Also: AD10 (D1541)
Next:
    stx NameIndex
    lda FileNameStart,x
    jsr DriveOfName
    ldx NameIndex
    sta FileNameStart,x
    tya
    sta FileNameDrive,x
    inx
    cpx SecondStreamEnd
    bcc Next
    rts
.endproc

;; In: A = the place of a name in CMDBUF. A "0:" or "1:" there gives its drive; a ':' alone, or a letter before ':',
;; gives drive 0; a name with no ':' gives drive 0 with bit 7, defaulted. Out: Y = the drive; A = the place past the ':'
;; when there is one, else the place as it came in. The listing says Y comes in as the default, but the code sets it to
;; 0 (one drive).
;; Also: SETDRV (D1541)
.proc DriveOfName
    tax
    ldy #$00
    lda #$3A
    cmp CommandBuffer+1,x
    beq Colon
    cmp CommandBuffer,x
    bne NoColon
    inx

;; Drive 0, not marked as defaulted.
;; Also: SD20 (D1541)
Default:
    tya

;; Bit 0 is the drive ('0' or '1', or 0).
;; Also: SD22 (D1541)
Number:
    and #$01

;; Y = the drive, A = the place.
;; Also: SD24 (D1541)
Return:
    tay
    txa
    rts

;; A ':' after the first character: the character before it, '0' or '1', is the drive.
;; Also: SD40 (D1541)
Colon:
    lda CommandBuffer,x
    inx
    inx
    cmp #$30
    beq Number
    cmp #$31
    beq Number
    bne Default

;; No ':' after the name: drive 0 with bit 7 (defaulted). The listing defines it as an equate (=*), but it is a label;
;; not a constant.
;; Also: SD50 (D1541)
NoColon:
    tya
    ora #$80
    and #$81
    bne Return
.endproc

;; For a command with at most a drive: DRVNUM from the character at FILTBL, or failing that the string's last character,
;; '0' or '1'; with neither, drive 0 and IMAGE = $FF. Then the drive's LEDs (SETLDS).
;; Also: SETANY (D1541)
.proc FindDrive
    lda #$00
    sta Structure
    ldy FileNameStart

;; Tests the character at Y; the next try is the last character.
;; Also: SA05 (D1541)
Try:
    lda (CommandPointer),y
    jsr DriveDigit
    bpl Found
    iny
    cpy CommandLength
    bcs Default
    ldy CommandLength
    dey
    bne Try

;; No drive given: IMAGE = $FF, drive 0.
;; Also: SA10 (D1541)
Default:
    dec Structure
    lda #$00

;; DRVNUM = bit 0, and the LEDs.
;; Also: SA20 (D1541)
Found:
    and #$01
    sta DriveNumber
    jmp TurnOnActivityLed
.endproc
.endscope
.scope Directory continued

;; DRVNUM to the other drive, 0 or 1.
;; Also: TOGDRV (D1541)
.proc ToggleDrive
    lda DriveNumber
    eor #$01
    and #$01
    sta DriveNumber
    rts
.endproc
.endscope
.scope Commands continued

;; With second names, the last is taken off (F2CNT down one) as a file type: its first letter looked up in TYPLST,
;; TYPFLG = the type's number; without, or for a letter not there, 0 (S0:name=P scratches only programs).
;; Also: FS1SET (D1541)
.proc TakeType
    ldy #$00
    lda FirstStreamEnd
    cmp SecondStreamEnd
    beq Store
    dec SecondStreamEnd
    ldy SecondStreamEnd
    lda FileNameStart,y
    tay
    lda (CommandPointer),y
    ldy #TYPE_COUNT-1

;; Each type letter but the first (D), from the last.
;; Also: FS10 (D1541)
Search:
    cmp TypeFirstLetters,y
    beq Store
    dey
    bne Search

;; TYPFLG = Y.
;; Also: FS15 (D1541)
Store:
    tya
    sta MatchType
    rts
.endproc

;; A = 0 or 1 for the character '0' or '1', N clear; any other character comes back with bit 7 set.
;; Also: TST0V1 (D1541)
.proc DriveDigit
    cmp #$30
    beq Mask
    cmp #$31
    beq Mask
    ora #$80

;; Keeps bits 7 and 0.
;; Also: T0V1 (D1541)
Mask:
    and #$81
    rts
.endproc
.endscope
.scope Directory continued

;; Sets DRVCNT and DRVNUM, the drives to search for the stream's names, from the drives they name (FILDRV, through
;; SCHTBL); checks each for a new disk (AutoInitialize), leaving out one with none, with error 74, DRIVE NOT READY, when
;; neither has one. Ends by turning on the LED.
;; Also: OPTSCH (D1541)
.proc ChooseDrives
    lda #$00
    sta Temporary
    sta DriveSearchFlag
    pha
    ldx SecondStreamEnd

;; Each name, from the last: adds its drive bit to the mask on the stack.
;; Also: OS10 (D1541)
NextName:
    pla
    ora Temporary
    pha
    lda #$01
    sta Temporary
    dex
    bmi Choose
    lda FileNameDrive,x
    bpl DriveBit
    asl Temporary
    asl Temporary

;; Drive 1's bit is the one for drive 0 shifted once.
;; Also: OS15 (D1541)
DriveBit:
    lsr
    bcc NextName
    asl Temporary
    bne NextName

;; The mask picks SCHTBL's entry: DRVCNT is its bits 0-1.
;; Also: OS30 (D1541)
Choose:
    pla
    tax
    lda SearchOrder-1,x
    pha
    and #$03
    sta DriveSearches
    pla
    asl
    bpl FixedDrive
    lda FileNameDrive

;; DRVNUM = bit 0 of A; with one drive to search, it is checked alone.
;; Also: OS35 (D1541)
SetDrive:
    and #$01
    sta DriveNumber
    lda DriveSearches
    beq OneDrive
    jsr Bam::AutoInitialize
    beq CheckOther
    jsr ToggleDrive
    lda #$00
    sta DriveSearches
    jsr Bam::AutoInitialize
    beq Done

;; Error 74, DRIVE NOT READY.
;; Also: OS45 (D1541)
NotReady:
    lda #ERROR_DRIVE_NOT_READY
    jsr Commands::Fail

;; The first drive has a disk: the other is checked too (DRVNUM put back), and left out of the search if it has none.
;; Also: OS50 (D1541)
CheckOther:
    jsr ToggleDrive
    jsr Bam::AutoInitialize
    php
    jsr ToggleDrive
    plp
    beq Done
    lda #$00
    sta DriveSearches
    beq Done

;; One drive: error 74 if it has no disk.
;; Also: OS60 (D1541)
OneDrive:
    jsr Bam::AutoInitialize
    bne NotReady

;; On to <TurnOnActivityLed> (SETLDS).
;; Also: OS70 (D1541)
Done:
    jmp TurnOnActivityLed

;; Bit 6 clear: the entry's bit 7 is the drive to start on.
;; Also: OS40 (D1541)
FixedDrive:
    rol
    jmp SetDrive
.endproc

;; For each mask of drives the names ask for (bits 0-1 named, 2-3 by default): bits 0-1 the drives after the first to
;; search, bit 6 set to start on the first name's drive, else bit 7 the drive.
;; Also: SCHTBL (D1541)
SearchOrder:
    .byte $00, $80, $41
    .byte $01, $01, $01, $01
    .byte $81, $81, $81, $81
    .byte $42, $42, $42, $42

;; LOOKUP: looks up every name in the stream on the drives <ChooseDrives> picks, filling the tables (FILTRK, FILSEC,
;; PATTYP, ENTSEC, ENTIND) for each found; FOUND nonzero once all are.
;; Also: LOOKUP (D1541)
.proc FindAll
    jsr ChooseDrives

;; A search from the drive's first directory block (DELIND = 0: in-use entries only).
;; Also: LK05 (D1541)
SearchDrive:
    lda #$00
    sta FreeEntryIndex
    jsr Search
    bne Compare

;; The directory is used up: on to the other drive, if DRVCNT says so.
;; Also: LK10 (D1541)
NextDrive:
    dec DriveSearches
    bpl OtherDrive
    rts

;; DRVFLG set, the drive toggled and its LED on.
;; Also: LK15 (D1541)
OtherDrive:
    lda #$01
    sta DriveSearchFlag
    jsr ToggleDrive
    jsr TurnOnActivityLed
    jmp SearchDrive

;; The next entry in use; Z set at the directory's end.
;; Also: LK20 (D1541)
NextEntry:
    jsr Search::Next
    beq EndOfDirectory

;; The entry against the names not yet found.
;; Also: LK25 (D1541)
Compare:
    jsr MatchEntry
    lda Found
    beq NotAllFound
    rts

;; ENTFND minus: no name matched, so the next entry; else the same entry again for the other names.
;; Also: LK26 (D1541)
NotAllFound:
    lda EntryFound
    bmi NextEntry
    bpl Compare

;; Not all found: the other drive.
;; Also: LK30 (D1541)
EndOfDirectory:
    lda Found
    beq NextDrive
    rts
.endproc

;; FFRE: the next entry matching any name in the stream, after the one last found, whose sector (DIRSEC) is read again;
;; its details go in the tables. The three find routines share one body.
;; Entry:
;;   First = FFST
;;   Next = FNDFIL
;; Also: FFRE (D1541)
.proc FindFile
    jsr Search::Again
    beq EndOfDirectory
    bne Compare

;; DRVFLG set, the drive toggled and its LED on, then a search from its start.
;; Also: FF15 (D1541)
OtherDrive:
    lda #$01
    sta DriveSearchFlag
    jsr ToggleDrive
    jsr TurnOnActivityLed

;; FFST: the first matching entry, from the start of the directory (<Files::Open> and the scratch command enter here).
;; Also: FFST (D1541)
First:
    lda #$00
    sta FreeEntryIndex
    jsr Search
    bne Compare
    sta Found

;; Done if FOUND says so, else the other drive, if DRVCNT has one left.
;; Also: FF10 (D1541)
EndOfDirectory:
    lda Found
    bne Done
    dec DriveSearches
    bpl OtherDrive
    rts

;; FNDFIL: the next matching entry, going on with the search without reading the sector again (the transfer code enters
;; here).
;; Also: FNDFIL (D1541)
Next:
    jsr Search::Next
    beq EndOfDirectory

;; The entry against the names; no match, and not all found: the next entry.
;; Also: FF25 (D1541)
Compare:
    jsr MatchEntry
    ldx EntryFound
    bpl CheckType
    lda Found
    beq Next
    bne Done

;; A match: with TYPFLG set, its type must be that one, or the search goes on.
;; Also: FF30 (D1541)
CheckType:
    lda MatchType
    beq Done
    lda FileNamePattern,x
    and #TYPE_MASK
    cmp MatchType
    bne Next

;; Returns.
;; Also: FF40 (D1541)
Done:
    rts
.endproc

;; Compares the entry at DIRBUF with each name in the stream not yet found, on its drive, with ? and * as patterns; on a
;; match ENTFND = the name's index and its tables get the entry's type, track, sector, place and record size. Falls into
;; <NextUnfound>.
;; Also: COMPAR (D1541)
.proc MatchEntry
    ldx #$FF
    stx EntryFound
    inx
    stx PatternFlag
    jsr NextUnfound
    beq CheckDrive

;; Every name found: returns.
;; Also: CP02 (D1541)
Done:
    rts

;; The next name not yet found.
;; Also: CP05 (D1541)
NextName:
    jsr NextUnfound::Continue
    bne Done

;; The name's drive must be this one, or a default drive while both are searched.
;; Also: CP10 (D1541)
CheckDrive:
    lda DriveNumber
    eor FileNameDrive,x
    lsr
    bcc CompareName
    and #$40
    beq NextName
    lda #$02
    cmp DriveSearches
    beq NextName

;; From the name's start (FILTBL, FNDLMT for its end) and the entry's byte 3.
;; Also: CP20 (D1541)
CompareName:
    lda FileNameStart,x
    tax
    jsr Commands::FindNameEnd
    ldy #$03
    jmp CheckPattern

;; A character that differs fails unless it is ? and the entry's name has not ended (shifted space).
;; Also: CP30 (D1541)
CompareCharacter:
    lda CommandBuffer,x
    cmp (BufferPointer),y
    beq NextCharacter
    cmp #$3F
    bne NextName
    lda (BufferPointer),y
    cmp #$A0
    beq NextName

;; Both indexes on.
;; Also: CP32 (D1541)
NextCharacter:
    inx
    iny

;; At the pattern's end (LIMIT), or a * that matches the rest.
;; Also: CP33 (D1541)
CheckPattern:
    cpx StringEnd
    bcs EndOfPattern
    lda CommandBuffer,x
    cmp #$2A
    beq Matched
    bne CompareCharacter

;; The pattern ended: the entry's name must end there too (16 characters or a shifted space).
;; Also: CP34 (D1541)
EndOfPattern:
    cpy #$13
    bcs Matched
    lda (BufferPointer),y
    cmp #$A0
    bne NextName

;; A match: ENTFND, PATFLG, ENTIND and ENTSEC for it.
;; Also: CP40 (D1541)
Matched:
    ldx SecondStreamStart
    stx EntryFound
    lda FileNamePattern,x
    and #$80
    sta PatternFlag
    lda EntryOffset
    sta FileNameEntryIndex,x
    lda Sector
    sta FileNameEntrySector,x
    ldy #$00
    lda (BufferPointer),y
    iny
    pha
    and #$40
    sta Temporary
    pla
    and #$DF
    bmi StoreType
    ora #$20

;; PATTYP = the entry's type with its locked bit, bit 5 set for a file not closed, the name's pattern bit kept; then the
;; drive, the first track and sector, and the record size if REC has none.
;; Also: CP42 (D1541)
StoreType:
    and #$27
    ora Temporary
    sta Temporary
    lda #$80
    and FileNamePattern,x
    ora Temporary
    sta FileNamePattern,x
    lda FileNameDrive,x
    and #$80
    ora DriveNumber
    sta FileNameDrive,x
    lda (BufferPointer),y
    sta FileNameTrack,x
    iny
    lda (BufferPointer),y
    sta FileNameSector,x
    lda RecordSize
    bne NextUnfound
    ldy #$15
    lda (BufferPointer),y
    sta RecordSize
.endproc

;; CP50: <MatchEntry>'s label on NextUnfound's first instruction, where it falls in; one name, with CP50 in Also:.
;; Entry:
;;   Continue = From the name before F2PTR (<MatchEntry> enters here for its next name)
;; Also: CP50 (D1541), CMPCHK (D1541)
.proc NextUnfound
    lda #$FF
    sta Found
    lda SecondStreamEnd
    sta SecondStreamStart

;; From the name before F2PTR (<MatchEntry> enters here for its next name).
;; Also: CC10 (D1541)
Continue:
    dec SecondStreamStart
    bpl Check
    rts

;; A pattern always counts as not found; a name with a track is found.
;; Also: CC15 (D1541)
Check:
    ldx SecondStreamStart
    lda FileNamePattern,x
    bmi NotFound
    lda FileNameTrack,x
    bne Continue

;; FOUND = 0.
;; Also: CC20 (D1541)
NotFound:
    lda #$00
    sta Found
    rts
.endproc

;; SRCHST: starts a search at the directory's first block (track DIRTRK, sector 1) through the internal read channel,
;; and returns the first entry: one in use (Z clear, INDEX and DIRSEC set), or with DELIND set the first deleted one; Z
;; set at the end. DELSEC = the first deleted entry's sector.
;; Entry:
;;   Again = SRRE
;;   Next = SEARCH
;; Also: SRCHST (D1541)
.proc Search
    ldy #$00
    sty FreeEntrySector
    dey
    sty EntryFound
    lda DirectoryTrack
    sta Track
    lda #$01
    sta Sector
    sta LastBlock
    jsr Files::OpenInternalRead

;; Z set (the end) when the last block (LSTBUF 0) is used up.
;; Also: SR10 (D1541)
NextBlock:
    lda LastBlock
    bne ReadBlock
    rts

;; Eight entries; LSTBUF = the block's link track.
;; Also: SR15 (D1541)
ReadBlock:
    lda #$07
    sta EntriesLeft
    lda #$00
    jsr Files::PeekByte
    sta LastBlock

;; The entry at the pointer: type 0 is a deleted one, noted in DELSEC the first time; returned if DELIND asks for
;; deleted entries.
;; Also: SR20 (D1541)
NextEntry:
    jsr Files::GetPointer
    dec EntriesLeft
    ldy #$00
    lda (BufferPointer),y
    bne InUse
    lda FreeEntrySector
    bne Next
    jsr Files::GetChannelBlock
    lda Sector
    sta FreeEntrySector
    lda BufferPointer
    ldx FreeEntryIndex
    sta FreeEntryIndex
    beq Next
    rts

;; An entry in use: returned, unless DELIND = 1 asks only for deleted ones.
;; Also: SR30 (D1541)
InUse:
    ldx #$01
    cpx FreeEntryIndex
    bne Found
    beq Next

;; SRRE: reads the sector of the entry last returned (DIRSEC) again, and goes on from it (INDEX); Validate and
;; <FindFile> enter here.
;; Also: SRRE (D1541)
Again:
    lda DirectoryTrack
    sta Track
    lda SearchSector
    sta Sector
    jsr Files::OpenInternalRead
    lda EntryOffset
    jsr Files::SetPointer

;; SEARCH: the entry after the last returned, ENTFND cleared (<FindAll>, <FindFile> and <AddEntry> enter here).
;; Also: SEARCH (D1541)
Next:
    lda #$FF
    sta EntryFound
    lda EntriesLeft
    bmi EndOfBlock
    lda #$20
    jsr Files::AdvancePointer
    jmp NextEntry

;; The block's eighth entry was the last: the next block (<Files::FollowLink>).
;; Also: SR40 (D1541)
EndOfBlock:
    jsr Files::FollowLink
    jmp NextBlock

;; INDEX and DIRSEC = the entry's place; Z clear.
;; Also: SR50 (D1541)
Found:
    lda BufferPointer
    sta EntryOffset
    jsr Files::GetChannelBlock
    lda Sector
    sta SearchSector
    rts
.endproc
.endscope
.scope Bam continued

;; AUTOI: unless <AutoInitializeOff> (AUTOFG) turns it off, a drive whose disk has changed (WPSW bit 0) is initialized,
;; or marked in NODRV when the seek finds no disk (job results 2, 3 and $0F: no header, no sync, not ready; the
;; listing's comments swap the first two). A = NODRV, Z set when the drive has a disk.
;; Also: AUTOI (D1541)
.proc AutoInitialize
    lda AutoInitializeOff
    bne Done
    ldx DriveNumber
    lsr DiskChanged,x
    bcc Done
    lda #$FF
    sta JobErrorReturn
    jsr SeekHeader
    ldy #$FF
    cmp #$02
    beq SetNoDrive
    cmp #$03
    beq SetNoDrive
    cmp #$0F
    beq SetNoDrive
    ldy #$00

;; NODRV = Y; a drive with a disk is initialized.
;; Also: AUTO1 (D1541)
SetNoDrive:
    ldx DriveNumber
    tya
    sta NoDrive,x
    bne Done
    jsr InitializeDrive

;; A = NODRV for DRVNUM.
;; Also: AUTO2 (D1541)
Done:
    ldx DriveNumber
    lda NoDrive,x
    rts
.endproc
.endscope
.scope Commands continued

;; Copies the name at X in CMDBUF (to ',' or '=', at most 16 characters) into buffer Y at its pointer, then pads with
;; shifted spaces ($A0) to A characters.
;; Also: TRNAME (D1541)
.proc CopyName
    pha
    jsr FindNameEnd
    jsr CopyToBuffer
    pla
    sec
    sbc StringLength
    tax
    beq Return
    bcc Return
    lda #$A0

;; Each shifted space.
;; Also: TN10 (D1541)
Pad:
    sta (BufferPointer),y
    iny
    dex
    bne Pad

;; Returns; the name filled the field.
;; Also: TN20 (D1541)
Return:
    rts
.endproc

;; DIRBUF = buffer Y's pointer; copies CMDBUF from X up to LIMIT there, stopping at the buffer's end.
;; Also: TRCMBF (D1541)
.proc CopyToBuffer
    tya
    asl
    tay
    lda a:BufferPositions,y
    sta BufferPointer
    lda a:BufferPositions+1,y
    sta BufferPointer+1
    ldy #$00

;; Each character.
;; Also: TR10 (D1541)
Loop:
    lda CommandBuffer,x
    sta (BufferPointer),y
    iny
    beq Return
    inx
    cpx StringEnd
    bcc Loop

;; Returns.
;; Also: TR20 (D1541)
Return:
    rts
.endproc

;; LIMIT = the place of the ',' or '=' that ends the name at X, or the string's end, at most 16 characters on; STRSIZ =
;; its length. X kept.
;; Also: FNDLMT (D1541)
.proc FindNameEnd
    lda #$00
    sta StringLength
    txa
    pha

;; Each character.
;; Also: FL05 (D1541)
Next:
    lda CommandBuffer,x
    cmp #$2C
    beq Done
    cmp #$3D
    beq Done
    inc StringLength
    inx
    lda #$0F
    cmp StringLength
    bcc Done
    cpx CommandLength
    bcc Next

;; LIMIT set; X back.
;; Also: FL10 (D1541)
Done:
    stx StringEnd
    pla
    tax
    rts
.endproc
.endscope
.scope Directory continued

;; The directory listing's next line, built in NAMBUF (<BuildLine>), with SA and LINDX kept across it: C clear after the
;; last.
;; Also: GETNAM (D1541)
.proc NextLine
    lda SecondaryAddress
    pha
    lda Channel
    pha
    jsr BuildLine
    pla
    sta Channel
    pla
    sta SecondaryAddress
    rts
.endproc

;; On the internal read channel: the next entry's line, or after the last the blocks-free line (C clear); DRVFLG steps
;; the two-drive listing through a drive's free line and the next drive's header.
;; Also: GNSUB (D1541)
.proc BuildLine
    lda #INTERNAL_READ_SECONDARY
    sta SecondaryAddress
    jsr Files::FindReadChannel
    jsr Files::GetPointer
    lda EntryFound
    bpl More
    lda DriveSearchFlag
    bne Pending
    jsr FreeLine
    clc
    rts

;; An entry: DRVFLG 0 means its line.
;; Also: GN05 (D1541)
More:
    lda DriveSearchFlag
    beq Entry

;; DRVFLG counts down: at 0, this drive's blocks-free line (the other drive's DRVNUM for the count) and C set; otherwise
;; the next header.
;; Also: GN050 (D1541)
Pending:
    dec DriveSearchFlag
    bne Header
    dec DriveSearchFlag
    jsr ToggleDrive
    jsr FreeLine
    sec
    jmp ToggleDrive

;; A drive's header line (<HeaderLine>), DRVFLG and the line number's high byte cleared; C set.
;; Also: GN051 (D1541)
Header:
    lda #$00
    sta BlockTotal+1
    sta DriveSearchFlag
    jsr HeaderLine
    sec
    rts

;; A file's line: the blocks (entry bytes 28 and 29) as its line number in NBTEMP, and X where the name ends, one place
;; less for 10 or more blocks and another for 100 or more, so the names line up.
;; Also: GN10 (D1541)
Entry:
    ldx #BLOCK_COUNT_END
    ldy #$1D
    lda (BufferPointer),y
    sta BlockTotal+1
    beq Low
    ldx #BLOCK_COUNT_END-2

;; The low byte of the block count.
;; Also: GN12 (D1541)
Low:
    dey
    lda (BufferPointer),y
    sta BlockTotal
    cpx #BLOCK_COUNT_END-2
    beq Type
    cmp #$0A
    bcc Type
    dex
    cmp #$64
    bcc Type
    dex

;; NAMBUF blanked; the entry's type byte: '<' after a locked file (bit 6), then its three letters from TYPLST, TP1LST
;; and TP2LST.
;; Also: GN14 (D1541)
Type:
    jsr BlankLine
    lda (BufferPointer),y
    pha
    asl
    bpl TypeLetters
    lda #$3C
    sta ListingLine+1,x

;; The type's three letters, backwards.
;; Also: GN15 (D1541)
TypeLetters:
    pla
    and #$0F
    tay
    lda TypeThirdLetters,y
    sta ListingLine,x
    dex
    lda TypeSecondLetters,y
    sta ListingLine,x
    dex
    lda TypeFirstLetters,y
    sta ListingLine,x
    dex
    dex
    bcs Name
    lda #$2A
    sta ListingLine+1,x

;; A '*' before the type of a file never closed (bit 7 clear), a space, then the 16 characters of the name, backwards.
;; Also: GN20 (D1541)
Name:
    lda #$A0
    sta ListingLine,x
    dex
    ldy #$12

;; Each character, from the 16th.
;; Also: GN22 (D1541)
NameCharacters:
    lda (BufferPointer),y
    sta ListingLine,x
    dex
    dey
    cpy #$03
    bcs NameCharacters
    lda #$22
    sta ListingLine,x

;; A '"' before the name, then a search for its end: a shifted space, a '"' or the line's end.
;; Also: GN30 (D1541)
Quote:
    inx
    cpx #$20
    bcs CloseQuote
    lda ListingLine,x
    cmp #$22
    beq CloseQuote
    cmp #$A0
    bne Quote

;; The closing '"'.
;; Also: GN35 (D1541)
CloseQuote:
    lda #$22
    sta ListingLine,x

;; Bit 7 off for the rest, so shifted spaces print as spaces.
;; Also: GN37 (D1541)
Unshift:
    inx
    cpx #$20
    bcs NextEntry
    lda #$7F
    and ListingLine,x
    sta ListingLine,x
    bpl Unshift

;; The next matching entry found (FNDFIL); C set.
;; Also: GN40 (D1541)
NextEntry:
    jsr FindFile::Next
    sec
    rts
.endproc

;; Fills NAMBUF's NBSIZ bytes with spaces.
;; Also: BLKNB (D1541)
.proc BlankLine
    ldy #LISTING_TEXT_LENGTH
    lda #$20

;; Each byte, from the last.
;; Also: BLKNB1 (D1541)
Loop:
    sta ListingLine-1,y
    dey
    bne Loop
    rts
.endproc

;; The listing's header line from the BAM, read first: the drive as its line number, reverse on ($12), and the disk name
;; in quotes then its ID and format from the BAM sector, shifted spaces as spaces; a missing format letter is '1'.
;; Also: NEWDIR (D1541)
.proc HeaderLine
    jsr Bam::ChannelIndexInX
    jsr Bam::ReadIfNeeded
    jsr BlankLine
    lda #$FF
    sta Temporary
    ldx DriveNumber
    stx BlockTotal
    lda #$00
    sta BlockTotal+1
    ldx JobNumber
    lda BufferPages,x
    sta BufferPointer+1
    lda DiskNameOffset
    sta BufferPointer
    ldy #$16
    lda (BufferPointer),y
    cmp #$A0
    bne Store
    lda #$31
    .byte $2C

;; Each byte down to the first: a shifted space becomes a space.
;; Also: ND15 (D1541)
Next:
    lda (BufferPointer),y
    cmp #$A0
    bne Store
    lda #$20

;; Into NAMBUF+2 on.
;; Also: ND20 (D1541)
Store:
    sta ListingLine+2,y
    dey
    bpl Next
    lda #$12
    sta ListingLine
    lda #$22
    sta ListingLine+1
    sta ListingLine+18
    lda #$20
    sta ListingLine+19
    rts
.endproc

;; The line 'BLOCKS FREE.' in NAMBUF, and the free count as its number (NUMFRE).
;; Also: MSGFRE (D1541)
.proc FreeLine
    jsr BlankLine
    ldy #BLOCKS_FREE_LENGTH-1

;; Each character, from the last.
;; Also: MSG1 (D1541)
Loop:
    lda FreeText,y
    sta ListingLine,y
    dey
    bpl Loop
    jmp Bam::CopyFreeBlocks
.endproc

;; The text 'BLOCKS FREE.'; MSGLEN is its length.
;; Also: FREMSG (D1541)
FreeText:
    .byte "BLOCKS FREE."
.endscope
.scope Commands continued

;; S: a type filter (<TakeType>), the drives, then each matching entry, unless its file is open or locked (bit 6): the
;; entry cleared and written, a relative file's side-sector chain freed, then the file's chain, unless the file was
;; never closed. Ends with 01 FILES SCRATCHED, TRACK the count. (Reached through the command table, so a routine, not a
;; local.)
;; Also: SCRTCH (D1541)
.proc Scratch
    jsr TakeType
    jsr SetDrives
    jsr Directory::ChooseDrives
    lda #$00
    sta Work0
    jsr Directory::FindFile::First
    bmi Done

;; An entry that matches: open (TSTCHN) or locked is left.
;; Also: SC15 (D1541)
Match:
    jsr Files::TestEntryOpen
    bcc NextMatch
    ldy #$00
    lda (BufferPointer),y
    and #$40
    bne NextMatch
    jsr Directory::DeleteEntry
    ldy #$13
    lda (BufferPointer),y
    beq Chain
    sta Track
    iny
    lda (BufferPointer),y
    sta Sector
    jsr Bam::FreeChain

;; The file's own chain from FILTRK and FILSEC, unless PATTYP's bit 5 says it was never closed.
;; Also: SC17 (D1541)
Chain:
    ldx EntryFound
    lda #$20
    and FileNamePattern,x
    bne Count
    lda FileNameTrack,x
    sta Track
    lda FileNameSector,x
    sta Sector
    jsr Bam::FreeChain

;; R0, the count, up one.
;; Also: SC20 (D1541)
Count:
    inc Work0

;; The next match (FFRE).
;; Also: SC25 (D1541)
NextMatch:
    jsr Directory::FindFile
    bpl Match

;; TRACK = the count; to <Finish::Report> with message 1.
;; Also: SC30 (D1541)
Done:
    lda Work0
    sta Track
    lda #$01
    ldy #$00
    jmp Finish::Report
.endproc
.endscope
.scope Bam continued

;; Frees a file's blocks from TRACK and SECTOR along their links: each freed in the BAM (FRETS) and read for the next
;; link (on the internal read channel), WBAM's bit 6 set while the BAM is in memory; at the last, the BAM written out
;; (MAPOUT) and the channel freed. CLOSE uses it for a replaced file.
;; Also: DELFIL (D1541)
.proc FreeChain
    jsr MarkFree
    jsr Files::OpenInternalRead
    jsr ChannelIndexInX
    lda ChannelBuffer,x
    cmp #$FF
    beq Next
    lda BamWriteDeferred
    ora #$40
    sta BamWriteDeferred

;; Each block: the link at its start into TRACK and SECTOR; track 0 is the last. One address with DEL2, both in Also.
;; Also: DEL10 (D1541), DEL2 (D1541)
Next:
    lda #$00
    jsr Files::SetPointer
    jsr Files::ReadByte
    sta Track
    jsr Files::ReadByte
    sta Sector
    lda Track
    bne FreeNext
    jsr WriteForChannel
    jmp Files::FreeChannel

;; Frees the next block and reads it.
;; Also: DEL1 (D1541)
FreeNext:
    jsr MarkFree
    jsr Files::FollowLink
    jmp Next
.endproc
.endscope
.scope Directory continued

;; The directory entry at DIRBUF gets type 0 (deleted), and its sector is written and waited for.
;; Also: DELDIR (D1541)
.proc DeleteEntry
    ldy #$00
    tya
    sta (BufferPointer),y
    jsr Files::WriteBuffer
    jmp Jobs::Wait
.endproc
.endscope
.scope Commands continued

;; D: there is no second drive to copy to: 31 SYNTAX ERROR. A C without ':' comes here too. (Reached through the command
;; table.)
;; Also: DUPLCT (D1541)
.proc Duplicate
    lda #ERROR_INVALID_COMMAND
    jmp Fail
.endproc

;; Puts a JMP to the controller's format routine (FORMT) at buffer 3's start ($0600), then gives buffer 3 the execute
;; job for DRVNUM, and waits; a result of 2 or more is reported as error 3, 21 READ ERROR, whatever the job's code
;; (ERROR). The ROM's vector at $FFE6 points here too.
;; Also: FORMAT (D1541)
.proc Format
    lda #$4C
    sta Buffers+768
    lda #<Controller::Format
    sta Buffers+769
    lda #>Controller::Format
    sta Buffers+770
    lda #$03
    jsr Jobs::SetHeader::ForBuffer
    lda DriveNumber
    ora #JOB_EXECUTE
    sta JobQueue+3

;; Until the job's bit 7 clears.
;; Also: FMT105 (D1541)
Wait:
    lda JobQueue+3
    bmi Wait
    cmp #$02
    bcc Return
    lda #$03
    ldx #$00
    jmp Errors::JobError

;; Done.
;; Also: FMT110 (D1541)
Return:
    rts
.endproc

;; C: the BAM's buffer and the channels freed (the BAM marked out of memory), ':' found (none: <Duplicate>'s error), the
;; names parsed and their drives; one destination name, no patterns, else 30 SYNTAX ERROR; then <CopyFiles>. (When none
;; of IMAGE's bits 6, 4, 2 and 0 is set, one destination and one source, it also tests whether the destination name
;; starts with '*'; a '*' sets bit 7, which the check at NoPatterns (AND #%11011001) rejects anyway, so that test is
;; redundant.) (Reached through the command table.)
;; Also: DSKCPY (D1541)
.proc Copy
    lda #$E0
    sta BuffersInUse
    jsr Bam::ForgetImages
    jsr Bam::ChannelIndexInX
    lda #$FF
    sta ChannelBuffer,x
    lda #$0F
    sta FreeChannels
    jsr FindColon
    bne Parse
    jmp Duplicate

;; The names (<ParseNames::AfterColon>) and their drives.
;; Also: DX0000 (D1541)
Parse:
    jsr ParseNames::AfterColon
    jsr SetDrives
    lda Structure
    and #$55
    bne NoPatterns
    ldx FileNameStart
    lda CommandBuffer,x
    cmp #$2A
    bne NoPatterns

;; 30 SYNTAX ERROR.
;; Also: DX0010 (D1541)
BadSyntax:
    lda #ERROR_SYNTAX
    jmp Fail

;; IMAGE: no pattern, one destination, second names given; then <CopyFiles>.
;; Also: DX0020 (D1541)
NoPatterns:
    lda Structure
    and #$D9
    bne BadSyntax
    jmp CopyFiles
.endproc

;; Nothing calls it: what is left of copying a whole disk (the rest is commented out in the listing). Clears REC, DRVCNT
;; and the first two FILTRK entries, DRVNUM from the second name's drive, DELSEC nonzero, and the first name's place
;; from the second's. Kept, since its bytes are in the ROM.
;; Also: PUPS1 (D1541)
.proc SetUpCopyAll
    lda #$00
    sta RecordSize
    sta DriveSearches
    sta FileNameTrack
    sta FileNameTrack+1
    lda FileNameDrive+1
    and #$01
    sta DriveNumber
    ora #$01
    sta FreeEntrySector
    lda FileNameStart+1
    sta FileNameStart
    rts
.endproc

;; Looks the names up; with two or more sources the first of which is the destination itself (same drive, entry sector
;; and index), the rest are appended to it (a relative file or program cannot be: 64 FILE TYPE MISMATCH); otherwise
;; <CreateCopy>. Then <Finish>.
;; Also: COPY (D1541)
.proc CopyFiles
    jsr Directory::FindAll
    lda SecondStreamEnd
    cmp #$03
    bcc ToNew
    lda FileNameDrive
    cmp FileNameDrive+1
    bne ToNew
    lda FileNameEntryIndex
    cmp FileNameEntryIndex+1
    bne ToNew
    lda FileNameEntrySector
    cmp FileNameEntrySector+1
    bne ToNew
    jsr CheckSources
    lda #$01
    sta SecondStreamStart
    jsr OpenSource
    jsr Files::ChannelType
    beq Mismatch
    cmp #TYPE_PROGRAM
    bne Append

;; 64 FILE TYPE MISMATCH.
;; Also: COP01 (D1541)
Mismatch:
    lda #ERROR_FILE_TYPE_MISMATCH
    jsr Fail

;; The destination's channel moved from the internal read address to the write one, positioned at its end (APPEND), then
;; <CreateCopy::CopySources> from the second source.
;; Also: COP05 (D1541)
Append:
    lda #INTERNAL_WRITE_SECONDARY
    sta SecondaryAddress
    lda $023C
    sta $023D
    lda #$FF
    sta $023C
    jsr Files::Append
    ldx #$02
    jsr CreateCopy::CopySources
    jmp Finish

;; An ordinary copy: <CreateCopy>, then <Finish>.
;; Also: COP10 (D1541)
ToNew:
    jsr CreateCopy
    jmp Finish
.endproc

;; The sources must exist and the destination not (<CheckFiles>); the destination opened on the internal write channel
;; and added to the directory; then CopySources from the first source.
;; Entry:
;;   CopySources = For each source from X (F2PTR) to F2CNT-1
;; Also: CY (D1541)
.proc CreateCopy
    jsr CheckFiles
    lda FileNameDrive
    and #$01
    sta DriveNumber
    jsr Files::OpenInternalWrite
    jsr Directory::AddEntry
    ldx FirstStreamEnd

;; For each source from X (F2PTR) to F2CNT-1: opened (<OpenSource>), a relative one's records made first
;; (<CopyRelative>), then its bytes put to the write channel; the write channel closed after the last.
;; Also: CY10 (D1541)
CopySources:
    stx SecondStreamStart
    jsr OpenSource
    lda #INTERNAL_READ_SECONDARY
    sta SecondaryAddress
    jsr Files::FindReadChannel
    jsr Files::ChannelType
    bne Start
    jsr CopyRelative

;; EOIFLG to 'not the end'.
;; Also: CY10A (D1541)
Start:
    lda #CHANNEL_MORE
    sta MoreBytes
    jmp NextByte

;; The byte to the write channel (PIBYTE).
;; Also: CY15 (D1541)
Put:
    jsr Files::AcceptInternalByte

;; The next byte (<GetInternalByte>), until the last-record flag is set.
;; Also: CY20 (D1541)
NextByte:
    jsr GetInternalByte
    lda #RELATIVE_LAST_RECORD
    jsr Files::TestFlag
    beq Put
    jsr Files::ChannelType
    beq NextFile
    jsr Files::AcceptInternalByte

;; The next source, if any; else the copy's channel and file closed.
;; Also: CY30 (D1541)
NextFile:
    ldx SecondStreamStart
    inx
    cpx SecondStreamEnd
    bcc CopySources
    lda #INTERNAL_WRITE_SECONDARY
    sta SecondaryAddress
    jmp Files::CloseChannel
.endproc

;; Opens source F2PTR for reading on the internal channel: its drive, its entry (directory track, ENTSEC, ENTIND), TYPE
;; from PATTYP, then OPREAD; the pointer at its first data byte (1 for a relative file, 2 for others).
;; Also: OPIRFL (D1541)
.proc OpenSource
    ldx SecondStreamStart
    lda FileNameDrive,x
    and #$01
    sta DriveNumber
    lda DirectoryTrack
    sta Track
    lda FileNameEntrySector,x
    sta Sector
    jsr Files::OpenInternalRead
    ldx SecondStreamStart
    lda FileNameEntryIndex,x
    jsr Files::SetPointer
    ldx SecondStreamStart
    lda FileNamePattern,x
    and #TYPE_MASK
    sta FileType
    lda #$00
    sta RecordSize
    jsr Files::OpenRead
    ldy #$01
    jsr Files::ChannelType
    beq SetPointer
    iny

;; The pointer to Y.
;; Also: OPIR10 (D1541)
SetPointer:
    tya
    jmp Files::SetPointer
.endproc

;; The next byte of the internal read channel into DATA; falls into AnyChannel.
;; Entry:
;;   AnyChannel = The same from the channel SA selects (APPEND comes here)
;; Also: GIBYTE (D1541)
.proc GetInternalByte
    lda #INTERNAL_READ_SECONDARY
    sta SecondaryAddress

;; The same from the channel SA selects (APPEND comes here): DATA = the byte, EOIFLG = 0 if it was the last, and then
;; for a file that is not relative the channel's last-record flag (LRF) set.
;; Also: GCBYTE (D1541)
AnyChannel:
    jsr Files::ReadChannelByte
    sta DataByte
    ldx Channel
    lda ChannelStatus,x
    and #CHANNEL_MORE
    sta MoreBytes
    bne Return
    jsr Files::ChannelType
    beq Return
    lda #RELATIVE_LAST_RECORD
    jsr Files::SetFlag

;; Returns.
;; Also: GIB20 (D1541)
Return:
    rts
.endproc

;; A relative source: finds the last side sector of the source and of the copy, then adds records to the copy
;; (Relative's ADDR1) until it is as long as the source.
;; Also: CYEXT (D1541)
.proc CopyRelative
    jsr Files::SetDriveFromBuffer
    jsr Relative::SeekEnd
    lda SideSectorIndex
    pha
    lda SideSectorNumber
    pha
    lda #INTERNAL_WRITE_SECONDARY
    sta SecondaryAddress
    jsr Files::FindWriteChannel
    jsr Files::SetDriveFromBuffer
    jsr Relative::SeekEnd
    jsr Relative::LoadBlocks
    lda SideSectorIndex
    sta Work1
    lda SideSectorNumber
    sta Work0
    lda #$00
    sta Work2
    sta RecordOffset
    sta BlockOffset
    pla
    sta SideSectorNumber
    pla
    sta SideSectorIndex
    jmp Relative::AddBlocks::CheckRoom
.endproc

;; R: both names' drives (both drives searched if they differ), looked up; the old name must exist and the new not
;; (<CheckFiles>). The old entry's sector read, the new name written over the old (16 characters, padded), and the
;; sector written back. (Reached through the command table.)
;; Also: RENAME (D1541)
.proc Rename
    jsr SetDrives
    lda FileNameDrive+1
    and #$01
    sta FileNameDrive+1
    cmp FileNameDrive
    beq LookUp
    ora #$80

;; FILDRV set; both names looked up.
;; Also: RN10 (D1541)
LookUp:
    sta FileNameDrive
    jsr Directory::FindAll
    jsr CheckFiles
    lda FileNameDrive+1
    and #$01
    sta DriveNumber
    lda FileNameEntrySector+1
    sta Sector
    jsr Files::ReadBlock
    jsr Jobs::Wait
    lda FileNameEntryIndex+1
    clc
    adc #$03
    jsr Files::SetPointer
    jsr Files::GetActiveBuffer
    tay
    ldx FileNameStart
    lda #$10
    jsr CopyName
    jsr Files::WriteBuffer
    jsr Jobs::Wait
    jmp Finish
.endproc

;; TYPE = the first source's type; each source, F2CNT-1 down to F1CNT, must have been found (FILTRK not 0), else 62 FILE
;; NOT FOUND. Returns X = F1CNT-1.
;; Also: CHKIN (D1541)
.proc CheckSources
    lda FileNamePattern+1
    and #TYPE_MASK
    sta FileType
    ldx SecondStreamEnd

;; Each source.
;; Also: CK10 (D1541)
Next:
    dex
    cpx FirstStreamEnd
    bcc Return
    lda FileNameTrack,x
    bne Next
    lda #ERROR_FILE_NOT_FOUND
    jmp Fail

;; All found.
;; Also: CK20 (D1541)
Return:
    rts
.endproc

;; <CheckSources>, then each destination name, F1CNT-1 down to 0, must not exist, else 63 FILE EXISTS.
;; Also: CHKIO (D1541)
.proc CheckFiles
    jsr CheckSources

;; Found is the error.
;; Also: CK25 (D1541)
Test:
    lda FileNameTrack,x
    beq Next
    lda #ERROR_FILE_EXISTS
    jmp Fail

;; The next name down.
;; Also: CK30 (D1541)
Next:
    dex
    bpl Test
    rts
.endproc

;; M-R, M-W and M-E: the '-' must be character 1 (else 31 SYNTAX ERROR); the address from characters 3 and 4 into TEMP.
;; M-R reads, M-W writes from character 6 on (character 5 the count), M-E jumps to the address. None ends through
;; <Finish>: they return to the idle loop with the error channel as <Execute> set it, 00 OK (JSR OKERR at $C150).
;; (Reached through the command table.)
;; Also: MEM (D1541)
.proc Memory
    lda CommandBuffer+1
    cmp #$2D
    bne BadSyntax
    lda CommandBuffer+3
    sta Temporary
    lda CommandBuffer+4
    sta Temporary+1
    ldy #$00
    lda CommandBuffer+2
    cmp #$52
    beq Read
    jsr DisableProtection
    cmp #$57
    beq Write
    cmp #$45
    bne BadSyntax
    jmp (Temporary)

;; M-R: the byte at the address into DATA; with a count (character 5) of 0 or 2 or more, the error channel's pointer set
;; to the address plus one (the first byte goes through DATA) and its last byte to the address plus the count less one
;; (0 gives 256 bytes), so the bytes are read on channel 15 straight from memory; a count of 1, or none, takes
;; <OneByte>.
;; Also: MEMRD (D1541)
Read:
    lda (Temporary),y
    sta DataByte
    lda CommandLength
    cmp #$06
    bcc OneByte
    ldx CommandBuffer+5
    dex
    beq OneByte
    txa
    clc
    adc Temporary
    inc Temporary
    sta $0249
    lda Temporary
    sta CommandPointer+2
    lda Temporary+1
    sta CommandPointer+3
    jmp Files::NextByte::ErrorReady

;; One byte: Files' NextByte::ErrorEnd (GE15) resets the error channel's pointer to ERRBUF-1, and NextByte::ErrorReady
;; (GE20) makes DATA ready to talk.
;; Also: M30 (D1541)
OneByte:
    jsr Files::FindReadChannel
    jmp Files::NextByte::ErrorEnd

;; 31 SYNTAX ERROR.
;; Also: MEMERR (D1541)
BadSyntax:
    lda #ERROR_INVALID_COMMAND
    jmp Fail

;; The listing's second name for M10's address.
;; Also: MEMWRT (D1541), M10 (D1541)
Write:
    lda CommandBuffer+6,y
    sta (Temporary),y
    iny
    cpy CommandBuffer+5
    bcc Write
    rts
.endproc

;; U: U0 falls into Reset and returns by its RTS, without <Finish>; any other runs its entry (<UserJump>), then
;; <Finish>. (Reached through the command table.)
;; Entry:
;;   Reset = UserVectorsPointer = <UserCommandVectors>, the ROM's table
;; Also: USER (D1541)
.proc User
    ldy CommandBuffer+1
    cpy #$30
    bne Run

;; UserVectorsPointer = <UserCommandVectors>, the ROM's table. Start-up calls it.
;; Also: USRINT (D1541)
Reset:
    lda #<UserCommandVectors
    sta UserVectorsPointer
    lda #>UserCommandVectors
    sta UserVectorsPointer+1
    rts

;; The entry for the character, then <Finish>.
;; Also: US10 (D1541)
Run:
    jsr UserJump
    jmp Finish
.endproc

;; Jumps through entry ((Y-1) and 15) of the table at <UserVectorsPointer>, by IP: U1 or UA the first, U2 the second ...
;; U9 or UI the ninth, U: or UJ the tenth.
;; Also: USREXC (D1541)
.proc UserJump
    dey
    tya
    and #$0F
    asl
    tay
    lda (UserVectorsPointer),y
    sta Pointer
    iny
    lda (UserVectorsPointer),y
    sta Pointer+1
    jmp (Pointer)
.endproc
.endscope
.scope Files continued

;; OPEN "#": a direct-access channel for the block commands. The disk initialised if needed (SA kept across it); "#"
;; alone takes any free buffer, "#n" buffer n if it is free (fewer than BFCNT, 5: the listing's comment says 13), else
;; 70 NO CHANNEL. Files' OPEN jumps here.
;; Also: OPNBLK (D1541)
.proc OpenDirect
    lda LastDrive
    sta DriveNumber
    lda SecondaryAddress
    pha
    jsr Bam::AutoInitialize
    pla
    sta SecondaryAddress
    ldx CommandLength
    dex
    bne Requested
    lda #$01
    jsr GetReadChannel
    jmp SetChannel

;; 70 NO CHANNEL.
;; Also: OB05 (D1541)
NoChannel:
    lda #ERROR_NO_CHANNEL
    jmp Commands::Fail

;; "#n": n from character 1 (BlockParameters::FromY) into FILSEC; marked used in BUFUSE if it was free, and given the
;; drive's job.
;; Also: OB10 (D1541)
Requested:
    ldy #$01
    jsr Commands::BlockParameters::FromY
    ldx FileNameSector
    cpx #BUFFER_COUNT
    bcs NoChannel
    lda #$00
    sta Temporary
    sta Temporary+1
    sec

;; The buffer's bit in TEMP, TEMP+1.
;; Also: OB15 (D1541)
Bit:
    rol Temporary
    rol Temporary+1
    dex
    bpl Bit
    lda Temporary
    and BuffersInUse
    bne NoChannel
    lda Temporary+1
    and BuffersInUse+1
    bne NoChannel
    lda Temporary
    ora BuffersInUse
    sta BuffersInUse
    lda Temporary+1
    ora BuffersInUse+1
    sta BuffersInUse+1
    lda #$00
    jsr GetReadChannel
    ldx Channel
    lda FileNameSector
    sta ChannelBuffer,x
    tax
    lda DriveNumber
    sta JobQueue,x
    sta LastJobs,x

;; The channel set up: LINTAB's bit 6 (reads and writes), LSTCHR $FF, ready to talk and listen, the buffer's number as
;; its first byte to read, the pointer at 1, the direct type. Then Finish.
;; Also: OB30 (D1541)
SetChannel:
    ldx SecondaryAddress
    lda SecondaryChannels,x
    ora #$40
    sta SecondaryChannels,x
    ldy Channel
    lda #$FF
    sta ChannelLastByte,y
    lda #CHANNEL_RANDOM
    sta a:ChannelStatus,y
    lda a:ChannelBuffer,y
    sta ChannelByte,y
    asl
    tax
    lda #$01
    sta BufferPositions,x
    lda #$0E
    sta a:ChannelFileType,y
    jmp Commands::Finish
.endproc
.endscope
.scope Commands continued

;; B-: finds the '-', looks the next letter up in Subcommands (no ',' before it, else 30; not there, 31), CMDNUM = its
;; index with bit 7, the parameters parsed (<BlockParameters>), and jumps to its handler. (Reached through the command
;; table.)
;; Entry:
;;   BadSyntax = 30 SYNTAX ERROR
;; Also: BLOCK (D1541)
.proc Block
    ldy #$00
    ldx #$00
    lda #$2D
    jsr ScanFor
    bne Dash

;; 31 SYNTAX ERROR (no '-' or an unknown letter).
;; Also: BLK10 (D1541)
BadCommand:
    lda #ERROR_INVALID_COMMAND
    jmp Fail

;; 30 SYNTAX ERROR; an entry of <Block>, since <BlockParameters> (BCS at $CC9F, outside <Block>) comes here with too
;; many numbers.
;; Also: BLK30 (D1541)
BadSyntax:
    lda #ERROR_SYNTAX
    jmp Fail

;; The '-': no ',' before it, then the letter after.
;; Also: BLK40 (D1541)
Dash:
    txa
    bne BadSyntax
    ldx #BLOCK_SUBCOMMAND_COUNT-1
    lda CommandBuffer,y

;; Each letter, from the last.
;; Also: BLK50 (D1541)
Search:
    cmp Subcommands,x
    beq Dispatch
    dex
    bpl Search
    bmi BadCommand

;; The handler from <SubcommandHandlers> into TEMP, and jumps there.
;; Also: BLK60 (D1541)
Dispatch:
    txa
    ora #$80
    sta CommandNumber
    jsr BlockParameters
    lda CommandNumber
    asl
    tax
    lda SubcommandHandlers+1,x
    sta Temporary+1
    lda SubcommandHandlers,x
    sta Temporary
    jmp (Temporary)

;; The block commands' letters: A, F, R, W, E, P.
;; Also: BCTAB (D1541)
Subcommands:
    .byte "AFRWEP"

;; Their handlers, in <Subcommands>' order: <BlockAllocate>, <BlockFree>, <BlockRead>, <BlockWrite>, <BlockExecute>,
;; <SetBufferPosition>.
;; Also: BCJMP (D1541)
SubcommandHandlers:
    .word BlockAllocate
    .word BlockFree
    .word BlockRead
    .word BlockWrite
    .word BlockExecute
    .word SetBufferPosition
.endproc

;; The numbers after ':', or from character 3 without one, separated by spaces, commas or cursor-rights (29), each into
;; the parameter list (<ParseNumber>), F1CNT counting them; a fifth is 30 SYNTAX ERROR.
;; Entry:
;;   FromY = From character Y (OpenDirect comes here for "#n")
;; Also: BLKPAR (D1541)
.proc BlockParameters
    ldy #$00
    ldx #$00
    lda #$3A
    jsr ScanFor
    bne FromY
    ldy #$03

;; From character Y (OpenDirect comes here for "#n").
;; Also: BP05 (D1541)
FromY:
    lda CommandBuffer,y
    cmp #$20
    beq Skip
    cmp #$1D
    beq Skip
    cmp #$2C
    bne Number

;; Past a separator; at the string's end, returns.
;; Also: BP10 (D1541)
Skip:
    iny
    cpy CommandLength
    bcc FromY
    rts

;; A number, then the next.
;; Also: BP20 (D1541)
Number:
    jsr ParseNumber
    inc FirstStreamEnd
    ldy SecondStreamStart
    cpx #FILE_NAME_COUNT-1
    bcc Skip
    bcs Block::BadSyntax
.endproc

;; The decimal number at Y (its last three digits count; any of $30-$3F is a digit, its low four bits) into FILSEC,X
;; (low) and FILTRK,X (high) at X = F1CNT; F2PTR = the place after it.
;; Also: ASCHEX (D1541)
.proc ParseNumber
    lda #$00
    sta Temporary
    sta Temporary+1
    sta Temporary+3
    ldx #$FF

;; Each digit, the earlier ones moved up through TEMP, TEMP+1, TEMP+2.
;; Also: AH10 (D1541)
Digit:
    lda CommandBuffer,y
    cmp #$40
    bcs Convert
    cmp #$30
    bcc Convert
    and #$0F
    pha
    lda Temporary+1
    sta Temporary+2
    lda Temporary
    sta Temporary+1
    pla
    sta Temporary
    iny
    cpy CommandLength
    bcc Digit

;; F2PTR = Y; the digits times their place values summed.
;; Also: AH20 (D1541)
Convert:
    sty SecondStreamStart
    clc
    lda #$00

;; Each place, units first (X from $FF; the first INX gives 0, DECTAB,0 = 1; TEMP holds the last digit), then tens and
;; hundreds.
;; Also: AH30 (D1541)
Place:
    inx
    cpx #$03
    bcs Store
    ldy Temporary,x

;; Adds the place value once per unit of the digit, carrying into TEMP+3.
;; Also: AH35 (D1541)
Add:
    dey
    bmi Place
    adc PlaceValues,x
    bcc Add
    clc
    inc Temporary+3
    bne Add

;; Into the parameter list at F1CNT.
;; Also: AH40 (D1541)
Store:
    pha
    ldx FirstStreamEnd
    lda Temporary+3
    sta FileNameTrack,x
    pla
    sta FileNameSector,x
    rts
.endproc

;; 1, 10, 100, the decimal places.
;; Also: DECTAB (D1541)
PlaceValues:
    .byte $01, $0A, $64

;; B-F drive track sector: checked (<CheckBlock>), freed in the BAM, then <Finish>. Five bytes after it, LDA #1 and STA
;; WBAM, are reached by nothing.
;; Also: BLKFRE (D1541)
.proc BlockFree
    jsr CheckBlock
    jsr Bam::MarkFree
    jmp Finish
    lda #$01
    sta BamWriteDeferred
.endproc

;; B-A drive track sector: a free block is allocated (WUSED); a used one is 65 NO BLOCK with the next free block after
;; it in the message, or track and sector 0 when none is left.
;; Also: BLKALC (D1541)
.proc BlockAllocate
    jsr CheckBlock
    lda Sector
    pha
    jsr Bam::FindFreeSector
    beq NextTrack
    pla
    cmp Sector
    bne Taken
    jsr Bam::FlushAndMarkUsed
    jmp Finish

;; None free above it on this track: the sector off the stack.
;; Also: BA15 (D1541)
NextTrack:
    pla

;; Sector 0 of each later track, up to MAXTRK, for a free one.
;; Also: BA20 (D1541)
Search:
    lda #$00
    sta Sector
    inc Track
    lda Track
    cmp TrackLimit
    bcs Full
    jsr Bam::FindFreeSector
    beq Search

;; 65 NO BLOCK, with the free block's track and sector (CMDER2 keeps them).
;; Also: BA30 (D1541)
Taken:
    lda #ERROR_NO_BLOCK
    jsr Errors::Abort

;; 65 NO BLOCK, track and sector 0.
;; Also: BA40 (D1541)
Full:
    lda #ERROR_NO_BLOCK
    jsr Fail
.endproc

;; Checks the channel and the block (<CheckChannelBlock>), and reads it into the channel's buffer
;; (<Jobs::ReadTrackSector>).
;; Also: BLKRD2 (D1541)
.proc FetchBlock
    jsr CheckChannelBlock
    jmp Jobs::ReadTrackSector
.endproc

;; The channel's byte at its pointer, without moving it; Y = LINDX.
;; Also: GETSIM (D1541)
.proc PeekByte
    jsr Files::BufferIndexes
    lda (BufferPositions,x)
    rts
.endproc

;; <FetchBlock>, then the block's first byte into LSTCHR, the last byte to read, and the channel ready.
;; Also: BLKRD3 (D1541)
.proc FetchCountedBlock
    jsr FetchBlock
    lda #$00
    jsr Files::SetPointer
    jsr PeekByte
    sta ChannelLastByte,y
    lda #CHANNEL_RANDOM
    sta a:ChannelStatus,y
    rts
.endproc

;; B-R channel drive track sector: the block, read from byte 1 to the count in byte 0. Then <Finish>.
;; Also: BLKRD (D1541)
.proc BlockRead
    jsr FetchCountedBlock
    jsr Files::NextByte::NextRandom
    jmp Finish
.endproc

;; U1 (the first entry of <UserCommandVectors>): the parameters (<User> does not parse them), the block, and all 256
;; bytes to read from byte 0, LSTCHR $FF. Then <Finish>.
;; Also: UBLKRD (D1541)
.proc UserRead
    jsr BlockParameters
    jsr FetchCountedBlock
    lda ChannelLastByte,y
    sta ChannelByte,y
    lda #$FF
    sta ChannelLastByte,y
    jmp Finish
.endproc

;; B-W channel drive track sector: byte 0 = the channel's pointer less one (the bytes written, at least 1), the block
;; written, the channel's next byte made ready. Then <Finish>.
;; Also: BLKWT (D1541)
.proc BlockWrite
    jsr CheckChannelBlock
    jsr Files::GetPointer
    tay
    dey
    cmp #$02
    bcs SetCount
    ldy #$01

;; The count into byte 0.
;; Also: BW10 (D1541)
SetCount:
    lda #$00
    jsr Files::SetPointer
    tya
    jsr Files::PutByte
    txa
    pha
    jsr Jobs::WriteTrackSector
    pla
    tax
    jsr Files::NextByte::RandomAtPointer
    jmp Finish
.endproc

;; U2 (<UserCommandVectors>' second entry): the parameters, then the buffer written as it is. Then <Finish>.
;; Also: UBLKWT (D1541)
.proc UserWrite
    jsr BlockParameters
    jsr CheckChannelBlock
    jsr Jobs::WriteTrackSector
    jmp Finish
.endproc

;; B-E channel drive track sector: the block read into the channel's buffer and called at its first byte; then <Finish>.
;; Also: BLKEXC (D1541)
.proc BlockExecute
    jsr DisableProtection
    jsr FetchBlock
    lda #$00
    sta Temporary
    ldx JobNumber
    lda BufferPages,x
    sta Temporary+1
    jsr Call
    jmp Finish

;; JMP (TEMP), which the JSR before it makes a call.
;; Also: BE10 (D1541)
Call:
    jmp (Temporary)
.endproc

;; B-P channel position: the channel's buffer pointer set to the position, its byte made ready to read. Then <Finish>.
;; Also: BLKPTR (D1541)
.proc SetBufferPosition
    jsr FindBlockChannel
    lda JobNumber
    asl
    tax
    lda FileNameSector+1
    sta BufferPositions,x
    jsr Files::BufferIndexes
    jsr Files::NextByte::RandomAtPointer
    jmp Finish
.endproc

;; The next parameter (F1PTR, moved on) as a channel: 2 to 13 with an open channel, else 70 NO CHANNEL; SA and JOBNUM,
;; its buffer, set.
;; Also: BUFTST (D1541)
.proc FindBlockChannel
    ldx NameIndex
    inc NameIndex
    lda FileNameSector,x
    tay
    dey
    dey
    cpy #$0C
    bcc Valid

;; 70 NO CHANNEL.
;; Also: BT15 (D1541)
NoChannel:
    lda #ERROR_NO_CHANNEL
    jmp Fail

;; SA set and the channel found.
;; Also: BT20 (D1541)
Valid:
    sta SecondaryAddress
    jsr Files::FindReadChannel
    bcs NoChannel
    jsr Files::GetActiveBuffer
    sta JobNumber
    rts
.endproc

;; <FindBlockChannel>; falls into <CheckBlock>.
;; Also: BKOTST (D1541)
.proc CheckChannelBlock
    jsr FindBlockChannel
.endproc

;; From the parameters at F1PTR: DRVNUM, TRACK and SECTOR; the track and sector checked (TSCHK), then the LEDs.
;; Also: BLKTST (D1541)
.proc CheckBlock
    ldx NameIndex
    lda FileNameSector,x
    and #$01
    sta DriveNumber
    lda FileNameSector+2,x
    sta Sector
    lda FileNameSector+1,x
    sta Track
    jsr Jobs::CheckTrackSector
    jmp TurnOnActivityLed
.endproc
.endscope
