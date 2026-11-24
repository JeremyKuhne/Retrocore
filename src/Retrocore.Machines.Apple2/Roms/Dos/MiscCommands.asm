; retrocore: style=strict
;; DOS 3.3 and 3.2 command interpreter: the handlers for text files, INIT, CATALOG and the BASICs, and a text file's
;; characters
;;
;; The last command handler module, $A510-$A6A7 where DOS runs (in both versions): the handlers for WRITE, READ, INIT,
;; CATALOG, FP, `INT`, EXEC and POSITION, which the command table <CommandHandlers> lists, and the code DOS's input and
;; output hooks (DosHook.asm) call to move the characters of a text file once READ, WRITE or EXEC has started.
;;
;; Text files work through BASIC's own PRINT and INPUT. READ and WRITE only open the file and set a state:
;; <OutputState>, the state of the output hook, becomes <OUTPUT_STATE_FILE_LINE_START>, so that what the program prints
;; next goes to the file (<TextFile::WriteCharacter>); <InputState> becomes <INPUT_STATE_READING>, so that the program's
;; INPUT reads the file (<TextFile::ReadCharacter>). EXEC feeds a file to the input hook in place of the keyboard
;; (<TextFile::ReadExecCharacter>). The file stays open until CLOSE, the end of its data, or BASIC going back to
;; immediate mode (<TestProgramRunning>).
;;
;; FP and `INT` choose the BASIC. The Apple II has Integer BASIC or Applesoft in ROM at $D000-$FFFF, and a language
;; card in slot 0 can hold the other in RAM at the same addresses; <Commands::FindBasic> finds the one wanted.
;; Without Applesoft in either, FP runs the System Master's APPLESOFT program, which loads Applesoft into lower RAM.
;; OpenClose.asm and LoadSave.asm hold the other handlers; docs/Dos.md describes the command interpreter.

; INIT's default.

;; The volume number INIT writes when V is not given, or is 0.
DEFAULT_VOLUME = 254

; Commands: the handlers for text files, INIT, CATALOG and the BASICs, at $A510.
.scope Commands continued

;; WRITE: positions the file named in <FileName> (opening it if need be) and sends the program's output to it.
;;
;; At $A510 where DOS runs.
;; Also: EWRITE (DOS33, DOS31)
.proc Write
.assert MASTER || * = $A510, "Commands::Write is at $A510 where DOS runs."
    jsr FindAndPosition
    lda #OUTPUT_STATE_FILE_LINE_START
    sta a:OutputState
    jmp EndCommand
.endproc

;; READ: positions the file named in <FileName> (opening it if need be) and makes the program's input come from it.
;;
;; At $A51B where DOS runs.
;; Also: EREAD (DOS33, DOS31)
.proc Read
.assert MASTER || * = $A51B, "Commands::Read is at $A51B where DOS runs."
    jsr FindAndPosition
    lda #INPUT_STATE_READING
    sta a:InputState
    jmp EndCommand
.endproc

;; Finds the file named in <FileName>, opening it as a text file if it is not open, and moves to the record R and byte
;; B when R or B is given.
;;
;; At $A526 where DOS runs. R and B are passed straight to the file manager's POSITION request, so they count from
;; the start of the file: records of the length given when the file was opened.
;; In:    KeywordRecord = the record, KeywordByte = the byte, if <GivenKeywords> has R or B
;; Out:   WorkPointer = the file's buffer, whose work areas are in the parameter list
;; Entry: CallPosition = makes the POSITION request with the parameter list as it is (DOS 3.2's APPEND, the 1980
;;   DOS 3.3's <AppendFix::NextRecord>)
;; Also: RWPOSN (DOS33, DOS31)
.proc FindAndPosition
.assert MASTER || * = $A526, "Commands::FindAndPosition is at $A526 where DOS runs."
    jsr FileBuffers::Find
    bcc Found
    jsr Open
    jmp TestPosition

;; The file is open already: its work areas go in the parameter list.
;; Also: RWP1 (DOS33, DOS31)
Found:
    jsr FileBuffers::CopyPointers

;; Nothing more unless R or B was given.
;; Also: RWP2 (DOS33, DOS31)
TestPosition:
    lda a:GivenKeywords
    and #OPTION_RECORD + OPTION_BYTE
    beq Done
    ldx #FileParameters::BYTE_OFFSET + 1 - FileParameters::RECORD

;; Copies R, then B, to the parameter list's record and byte offset, from the last byte down.
;; Also: RWP2A (DOS33, DOS31)
CopyPosition:
    lda a:KeywordRecord,x
    sta a:DosFileParameters::Record,x
    dex
    bpl CopyPosition

;; Makes the POSITION request.
;; Also: RWP3 (DOS33, DOS31)
CallPosition:
.assert MASTER || * = $A546, "Commands::FindAndPosition::CallPosition is at $A546 where DOS runs."
    lda #REQUEST_POSITION
    sta a:DosFileParameters::Request
    jsr RunFileRequest

;; Also: RWPR (DOS33, DOS31)
Done:
    rts
.endproc

;; INIT: formats the disk, writes DOS onto it, then SAVEs the BASIC program in memory under the name in <FileName> as
;; the disk's greeting program.
;;
;; At $A54F where DOS runs. The volume number is V if given and not 0, otherwise <DEFAULT_VOLUME>.
;; <DosFileParameters::ImagePage> gives the file manager the first page of the DOS to copy: the high byte of
;; <WriteStartAddress>, $9D on a 48K machine.
;; Also: EINIT (DOS33, DOS31)
.proc Init
.assert MASTER || * = $A54F, "Commands::Init is at $A54F where DOS runs."
    lda #OPTION_VOLUME
    and a:GivenKeywords
    beq DefaultVolume
    lda a:KeywordVolume
    bne Format

;; V not given, or 0.
;; Also: DFVOL (DOS33)
DefaultVolume:
    lda #DEFAULT_VOLUME
    sta a:KeywordVolume

;; Makes the INIT request, then saves the program.
;; Also: EINITA (DOS33)
Format:
    lda WriteStartAddress+1
    sta a:DosFileParameters::ImagePage
    lda #REQUEST_INIT
    jsr FileRequest
    jmp Save
.endproc

;; CATALOG: has the file manager list the disk's files on the output device.
;;
;; At $A56E where DOS runs. CATALOG takes no file name, so the buffer <FileRequest> lends to the file manager is never
;; claimed. The volume the file manager found is stored in <KeywordVolume>.
;; Also: ECAT (DOS33, DOS31)
.proc Catalog
.assert MASTER || * = $A56E, "Commands::Catalog is at $A56E where DOS runs."
    lda #REQUEST_CATALOG
    jsr FileRequest
    lda a:DosFileParameters::Volume
    sta a:KeywordVolume
    rts
.endproc

;; FP: makes Applesoft the active BASIC and starts DOS and Applesoft afresh, losing the program in memory.
;;
;; At $A57A where DOS runs. If Applesoft is in ROM or the language card, <ColdStart> starts DOS with it. If not, Integer
;; BASIC becomes the active BASIC and DOS RUNs the program named APPLESOFT, with <InputState> =
;; <INPUT_STATE_STARTING_RAM_APPLESOFT>. That program loads Applesoft into RAM and starts it, and at Applesoft's first
;; input the state tells DOS's input hook to finish starting DOS for RAM Applesoft (<FinishStart>). With that state, a
;; disk without APPLESOFT gives LANGUAGE NOT AVAILABLE rather than FILE NOT FOUND (<FileManager::Open>).
;;
;; <MatchBasic> (LoadSave.asm) comes here to switch to Applesoft for a program of that type.
;; Also: EAS (DOS33, DOS31)
.proc Fp
.assert MASTER || * = $A57A, "Commands::Fp is at $A57A where DOS runs."
    lda #APPLESOFT_ID
    jsr FindBasic
    beq Int::StartDos

    ; Integer BASIC (ActiveBasic = 0) runs the APPLESOFT program.
    lda #0
    sta a:ActiveBasic

;; Blanks <FileName> for the name.
;; Also: EAS0 (DOS33, DOS31)
SetName:
    ldy #CATALOG_NAME_LENGTH
    jsr ClearFileNames::FromY
    ldx #APPLESOFT_FILE_NAME_LENGTH

;; Copies "APPLESOFT" in, from the last character down.
;; Also: EAS1 (DOS33, DOS31)
CopyName:
    lda a:ApplesoftFileName - 1,x
    sta a:FileName - 1,x
    dex
    bne CopyName

;; Runs the program that loads Applesoft into RAM.
;; Also: EAS2 (DOS33, DOS31)
RunLoader:
    lda #INPUT_STATE_STARTING_RAM_APPLESOFT
    sta a:InputState
    jmp Run
.endproc

;; `INT`: makes Integer BASIC the active BASIC and starts DOS and Integer BASIC afresh, losing the program in memory.
;;
;; At $A59E where DOS runs. <MatchBasic> (LoadSave.asm) comes here to switch to Integer BASIC for a program of that
;; type.
;; Errors: LANGUAGE NOT AVAILABLE if Integer BASIC is in neither the ROM nor the language card
;; Entry: StartDos = starts DOS with whichever BASIC $E000 now shows (FP's)
;; Also: EINT (DOS33, DOS31)
.proc Int
.assert MASTER || * = $A59E, "Commands::Int is at $A59E where DOS runs."
    lda #INTEGER_BASIC_ID
    jsr FindBasic
    beq Found
    lda #ERROR_LANGUAGE_NOT_AVAILABLE
    jmp Errors::Report

;; Integer BASIC is there: no RUN is waiting.
;; Also: GOINT (DOS33)
Found:
    lda #0
    sta a:RunPending

;; Starts DOS afresh.
;; Also: GOINIT (DOS33, DOS31)
StartDos:
.assert MASTER || * = $A5AF, "Commands::Int::StartDos is at $A5AF where DOS runs."
    jmp ColdStart
.endproc

;; Looks for the BASIC whose first byte is A at <RomBasicId>, switching the language card to it if need be.
;;
;; At $A5B2 where DOS runs. Applesoft starts with a JMP (<APPLESOFT_ID>), Integer BASIC with a JSR
;; (<INTEGER_BASIC_ID>). The test is made with memory as it is, then with the language card's RAM bank 2 read
;; (<LanguageCardBank2ReadOnly>), then with the ROM read (<LanguageCardRomWriteBank2>). The language card's switches
;; respond to any access, so the writes select them as reads would. Without a language card the switches do nothing
;; and the test fails the same way three times.
;; In:    A = <APPLESOFT_ID> or <INTEGER_BASIC_ID>
;; Out:   zero = set if found, with the memory it was found in selected
;; Keeps: A, X, Y
;; Also: SWTST (DOS33, DOS31)
.proc FindBasic
.assert MASTER || * = $A5B2, "Commands::FindBasic is at $A5B2 where DOS runs."
    cmp RomBasicId
    beq Done
    sta LanguageCardBank2ReadOnly
    cmp RomBasicId
    beq Done
    sta LanguageCardRomWriteBank2
    cmp RomBasicId

;; Also: SWTR (DOS33, DOS31)
Done:
    rts
.endproc

;; EXEC: opens the text file named in <FileName> and takes the input of BASIC and DOS from it, line by line, in place
;; of the keyboard, skipping the first R lines when R is given.
;;
;; At $A5C6 where DOS runs. <ExecFileBuffer> keeps the file's buffer, and <ExecState>, nonzero while EXEC runs, takes
;; the first character of the name.
;; Also: EEXEC (DOS33, DOS31)
.proc Exec
.assert MASTER || * = $A5C6, "Commands::Exec is at $A5C6 where DOS runs."
    jsr Open
    lda a:CurrentFileBuffer
    sta a:ExecFileBuffer
    lda a:CurrentFileBuffer+1
    sta a:ExecFileBuffer+1
    lda a:FileName
    sta a:ExecState
    bne Position::SkipLines         ; always: a name was given
.endproc

;; POSITION: moves forward R lines from where the file named in <FileName> is, opening it as a text file if it is not
;; open.
;;
;; At $A5DD where DOS runs. Unlike R in READ and WRITE, this R counts lines, Returns read one byte at a time from the
;; current position; the file manager's POSITION request is not used.
;; In:    KeywordRecord = the number of lines, if <GivenKeywords> has R
;; Errors: END OF DATA if the file ends first
;; Entry: SkipLines = with the file open and its work areas in the parameter list (EXEC)
;; Also: EPOS (DOS33, DOS31)
.proc Position
.assert MASTER || * = $A5DD, "Commands::Position is at $A5DD where DOS runs."
    jsr FileBuffers::Find
    bcc Found
    jsr Open
    jmp SkipLines

;; The file is open already: its work areas go in the parameter list.
;; Also: EXP1 (DOS33, DOS31)
Found:
    jsr FileBuffers::CopyPointers

;; Nothing to skip unless R was given.
;; Also: EXP2 (DOS33, DOS31)
SkipLines:
.assert MASTER || * = $A5EB, "Commands::Position::SkipLines is at $A5EB where DOS runs."
    lda a:GivenKeywords
    and #OPTION_RECORD
    beq Done

;; Counts R down to 0, a line at a time.
;; Also: EX0 (DOS33, DOS31)
CountLine:
    lda a:KeywordRecord
    bne CountLow
    ldx a:KeywordRecord+1
    beq Done
    dec a:KeywordRecord+1

;; Also: EX1A (DOS33, DOS31)
CountLow:
    dec a:KeywordRecord

;; Reads to the end of the line; the zero at the end of the data is END OF DATA.
;; Also: EX1 (DOS33, DOS31)
ReadToReturn:
    jsr TextFile::ReadByte
    beq TextFile::ReadCharacter::EndOfData
    cmp #KEY_RETURN
    bne ReadToReturn
    beq CountLine                   ; always

;; Returns. <TextFile::ReadCharacter> returns through it too, at the end of an EXEC file.
;; Also: EX2 (DOS33, DOS31)
Done:
    rts
.endproc

.endscope

;; The characters of an open READ, WRITE or EXEC file, which DOS's input and output hooks (DosHook.asm) call once
;; the command has set its state: what a program prints goes to the WRITE file, and what it reads comes from the
;; READ or EXEC file.
;;
;; In MiscCommands.asm, in two pieces around <TestProgramRunning>: $A60E-$A65D and $A679-$A6A7 where DOS runs.
.scope TextFile

;; Writes the character the program printed to the open file: the output hook's handling of a WRITE.
;;
;; At $A60E where DOS runs. If BASIC is no longer running a program, the WRITE has ended: the file is closed, the
;; input and output states are cleared, and the character is dropped (<EndTransfer>).
;; In:    HookA = the character, WorkPointer = the file's buffer, its work areas in the parameter list
;; Also: OCTD (DOS33, DOS31)
.proc WriteCharacter
.assert MASTER || * = $A60E, "TextFile::WriteCharacter is at $A60E where DOS runs."
    jsr TestProgramRunning
    bcs EndTransfer
    lda a:HookA
    sta a:DosFileParameters::Data
    lda #REQUEST_WRITE
    sta a:DosFileParameters::Request
    lda #TRANSFER_NEXT_BYTE
    sta a:DosFileParameters::Transfer
    jmp RunFileRequest
.endproc

;; Gives BASIC the next character of the open file as if it had been typed: the input hook's handling of a READ. It
;; leaves DOS through <ExitDos> with the character in A.
;;
;; At $A626 where DOS runs. <OUTPUT_STATE_FILE_ECHO> makes the output hook swallow the echo BASIC prints of the
;; character (<Output::FileEcho>). If BASIC is not running a program, the READ has ended, as in <WriteCharacter>. At the
;; end of the data the file is closed and END OF DATA reported, except for EXEC, where the end of the file just ends the
;; EXEC.
;;
;; A lowercase character ($E0 and up) is passed with bit 7 off, which the Monitor's line input on the II and II Plus
;; would otherwise turn into a capital. On the next call, the character before in the input line, <InputBuffer>, has
;; bit 7 set again, through <HookX>, the line input's index into it.
;; In:    WorkPointer = the file's buffer, its work areas in the parameter list
;; Errors: END OF DATA at the end of the file, outside EXEC
;; Entry: WithState = with A = the output state to set (<OUTPUT_STATE_ECHO> for EXEC), EndOfData = reports END OF
;;   DATA (POSITION's)
;; Also: ICFD (DOS33, DOS31)
.proc ReadCharacter
.assert MASTER || * = $A626, "TextFile::ReadCharacter is at $A626 where DOS runs."

;; The first of the characters $E0-$FF, the lowercase letters and five symbols.
FIRST_LOWERCASE = '`' | $80

;; Bit 7 of a character, set in the Apple II's normal text.
HIGH_BIT = $80

    jsr TestProgramRunning
    bcs EndTransfer
    lda #OUTPUT_STATE_FILE_ECHO

;; Sets the output state and reads the next byte.
;; Also: ICFD3 (DOS33, DOS31)
WithState:
.assert MASTER || * = $A62D, "TextFile::ReadCharacter::WithState is at $A62D where DOS runs."
    sta a:OutputState
    jsr ReadByte
    bne Pass

;; The zero at the end of the file: closes it. For EXEC, returns to the input hook, which reads the keyboard.
;; Also: ICFD2 (DOS33), ICCFD2 (DOS31)
EndOfFile:
    jsr Commands::CloseBuffer
    lda #OUTPUT_STATE_ECHO
    cmp a:OutputState
    beq Commands::Position::Done

;; Reports END OF DATA.
;; Also: ICFD4 (DOS33, DOS31)
EndOfData:
.assert MASTER || * = $A63F, "TextFile::ReadCharacter::EndOfData is at $A63F where DOS runs."
    lda #ERROR_END_OF_DATA
    jmp Errors::Report

;; Passes the character, a lowercase one with bit 7 off.
;; Also: ICFD1 (DOS33, DOS31)
Pass:
    cmp #FIRST_LOWERCASE
    bcc NotLowercase
    and #~HIGH_BIT & $FF

;; Keeps the character, and sets bit 7 again on the line's last character, if any.
;; Also: ICFNLC (DOS33)
NotLowercase:
    sta a:HookA
    ldx a:HookX
    beq Leave
    dex
    lda InputBuffer,x
    ora #HIGH_BIT
    sta InputBuffer,x

;; Leaves DOS with the character.
;; Also: ICFD0 (DOS33, DOS31)
Leave:
    jmp ExitDos
.endproc

.endscope

;; Tells whether BASIC is running a program or is in immediate mode.
;;
;; At $A65E where DOS runs. Applesoft is taken to be running unless the high byte of its current line number is $FF,
;; as it is in immediate mode, or the prompt (<PromptCharacter>) is "]". Integer BASIC is running when bit 7 of its
;; run flag is set.
;; Out:   carry = clear if a program is running, set if not
;; Uses:  X
;; Keeps: A, Y
;; Also: TSTRUN (DOS33, DOS31)
.proc TestProgramRunning
.assert MASTER || * = $A65E, "TestProgramRunning is at $A65E where DOS runs."

;; The high byte of Applesoft's current line number (its <AppleSoft:CURLIN>), $FF in immediate mode.
ApplesoftLineHigh = $76

;; Integer BASIC's run flag (its <IntegerBasic:RUNFLAG>): bit 7 is set while a program runs.
IntegerRunFlag = $D9

    pha
    lda a:ActiveBasic
    beq Integer
    ldx ApplesoftLineHigh
    inx
    beq NotRunning
    ldx PromptCharacter
    cpx #']' + $80
    beq NotRunning

;; A program is running: carry clear.
;; Also: TR0 (DOS33, DOS31)
Running:
    pla
    clc
    rts

;; Integer BASIC: its run flag says.
;; Also: TR1 (DOS33, DOS31)
Integer:
    lda IntegerRunFlag
    bmi Running

;; No program is running: carry set.
;; Also: NOTRUN (DOS33, DOS31)
NotRunning:
    pla
    sec
    rts
.endproc

; TextFile: ending a transfer, the EXEC file's characters, and the byte reader, at $A679.
.scope TextFile continued

;; Ends a READ or WRITE that BASIC has left: closes the file, clears the input and output states and leaves DOS
;; through <ExitDos>.
;;
;; At $A679 where DOS runs.
;; Also: ICFDB (DOS33, DOS31)
.proc EndTransfer
.assert MASTER || * = $A679, "TextFile::EndTransfer is at $A679 where DOS runs."
    jsr Commands::CloseBuffer
    jsr ClearStates
    jmp ExitDos
.endproc

;; Gives BASIC the next character of the EXEC file in place of a key: the input hook calls it while <ExecState> is set.
;; It leaves DOS through <ExitDos> with the character, and returns only at the end of the file.
;;
;; At $A682 where DOS runs. <OUTPUT_STATE_ECHO> makes the output hook treat what BASIC prints next as the echo of an
;; EXEC character (<Output::Echo>).
;; Also: NXTEXC (DOS33, DOS31)
.proc ReadExecCharacter
.assert MASTER || * = $A682, "TextFile::ReadExecCharacter is at $A682 where DOS runs."
    jsr PointAtExecBuffer
    jsr FileBuffers::CopyPointers
    lda #OUTPUT_STATE_ECHO
    bne ReadCharacter::WithState    ; always
.endproc

;; Reads the next byte of the open file.
;;
;; At $A68C where DOS runs.
;; In:    DosFileParameters::WorkArea, DosFileParameters::ListBuffer, DosFileParameters::DataBuffer = the file's
;;   buffers
;; Out:   A = the byte, zero = set if it is 0, which a text file ends with and <RunFileRequest> gives at the end of
;;   the data
;; Also: RBYTE (DOS33, DOS31)
.proc ReadByte
.assert MASTER || * = $A68C, "TextFile::ReadByte is at $A68C where DOS runs."
    lda #REQUEST_READ
    sta a:DosFileParameters::Request
    lda #TRANSFER_NEXT_BYTE
    sta a:DosFileParameters::Transfer
    jsr RunFileRequest
    lda a:DosFileParameters::Data
    rts
.endproc

;; Points <WorkPointer> at the EXEC file's buffer.
;;
;; At $A69D where DOS runs. <FinishStart> calls it too, to put the EXEC file's name back in its buffer once DOS's start
;; has rebuilt the buffers.
;; In:    ExecFileBuffer = the EXEC file's buffer
;; Out:   WorkPointer = the same
;; Keeps: X, Y
;; Also: MVEFTA (DOS33, DOS31)
.proc PointAtExecBuffer
.assert MASTER || * = $A69D, "TextFile::PointAtExecBuffer is at $A69D where DOS runs."
    lda a:ExecFileBuffer+1
    sta WorkPointer+1
    lda a:ExecFileBuffer
    sta WorkPointer
    rts
.endproc

.endscope
