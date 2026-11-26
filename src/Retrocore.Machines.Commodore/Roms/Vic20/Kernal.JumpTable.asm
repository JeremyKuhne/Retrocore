; retrocore: style=strict
; COMMODORE VIC-20 KERNAL: THE JUMP TABLE AND THE PROCESSOR'S VECTORS ($FF8A-$FFFF)

; The jump table: a JMP for each kernal call, at addresses that stay the same in every revision of the kernal (and
; in the PET's and the Commodore 64's for the calls they share), so that a program calls the kernal here and not at
; its routines. The calls from $FFC0 to $FFE7 jump through the RAM vectors, so a program can replace them; each entry
; takes the contract of the routine it reaches, or of the vector's default routine.

    .res $FF8A - *, $FF

.assert * = $FF8A, "RESTOR is at $FF8A."
;; $FF8A, RESTOR: puts every RAM vector back to the kernal's own routine.
;; Inherit: <Startup::RestoreVectors> In, Out, Errors, Keeps
;; Also: RESTOR (MTV, V20PRG)
KernalRestoreVectors:
    jmp Startup::RestoreVectors

.assert * = $FF8D, "VECTOR is at $FF8D."
;; $FF8D, VECTOR: reads the RAM vectors into a 32-byte table at X/Y, with carry set, or sets them from one, with carry
;; clear.
;; Inherit: <Startup::RestoreVectors::Copy> In, Out, Errors, Keeps
;; Also: VECTOR (MTV, V20PRG)
KernalCopyVectors:
    jmp Startup::RestoreVectors::Copy

.assert * = $FF90, "SETMSG is at $FF90."
;; $FF90, SETMSG: sets which messages the kernal prints, from A's bits 7 (control) and 6 (errors).
;; Inherit: <Channels::ReadStatus::SetMessages> In, Out, Errors, Keeps
;; Also: SETMSG (MTV, V20PRG)
KernalSetMessages:
    jmp Channels::ReadStatus::SetMessages

.assert * = $FF93, "SECOND is at $FF93."
;; $FF93, SECOND: sends a secondary address to the device told to listen.
;; Inherit: <Serial::SendSecondary> In, Out, Errors, Keeps
;; Also: SECOND (V20PRG)
KernalSendSecondary:
    jmp Serial::SendSecondary

.assert * = $FF96, "TKSA is at $FF96."
;; $FF96, TKSA: sends a secondary address to the device told to talk, and lets it talk.
;; Inherit: <Serial::SendTalkSecondary> In, Out, Errors, Keeps
;; Also: TKSA (V20PRG)
KernalSendTalkSecondary:
    jmp Serial::SendTalkSecondary

.assert * = $FF99, "MEMTOP is at $FF99."
;; $FF99, MEMTOP: reads the top of BASIC's RAM into X/Y, with carry set, or sets it from X/Y, with carry clear.
;; Inherit: <Startup::MemoryTop> In, Out, Errors, Keeps
;; Also: MEMTOP (V20PRG)
KernalMemoryTop:
    jmp Startup::MemoryTop

.assert * = $FF9C, "MEMBOT is at $FF9C."
;; $FF9C, MEMBOT: reads the bottom of BASIC's RAM into X/Y, with carry set, or sets it from X/Y, with carry clear.
;; Inherit: <Startup::MemoryBottom> In, Out, Errors, Keeps
;; Also: MEMBOT (MTV, V20PRG)
KernalMemoryBottom:
    jmp Startup::MemoryBottom

.assert * = $FF9F, "SCNKEY is at $FF9F."
;; $FF9F, SCNKEY: scans the keyboard once and buffers the key, for a program that runs with the jiffy interrupt
;; off.
;; Inherit: <Editor::ScanKeyboard> In, Out, Errors, Keeps
;; Also: SCNKEY (V20PRG)
KernalScanKeyboard:
    jmp Editor::ScanKeyboard

.assert * = $FFA2, "SETTMO is at $FFA2."
;; $FFA2, SETTMO: sets the IEEE-488 timeout switch, a leftover of the PET that the VIC-20 never reads.
;; Inherit: <Serial::SetTimeout> In, Out, Errors, Keeps
;; Also: SETTMO (MTV, V20PRG)
KernalSetTimeout:
    jmp Serial::SetTimeout

.assert * = $FFA5, "ACPTR is at $FFA5."
;; $FFA5, ACPTR: receives a byte from the device talking on the serial bus.
;; Inherit: <Serial::ReceiveByte> In, Out, Errors, Keeps
;; Also: ACPTR (V20PRG)
KernalReceiveByte:
    jmp Serial::ReceiveByte

.assert * = $FFA8, "CIOUT is at $FFA8."
;; $FFA8, CIOUT: sends a byte to the devices listening on the serial bus.
;; Inherit: <Serial::SendByte> In, Out, Errors, Keeps
;; Also: CIOUT (V20PRG)
KernalSendByte:
    jmp Serial::SendByte

.assert * = $FFAB, "UNTLK is at $FFAB."
;; $FFAB, UNTLK: tells the device talking on the serial bus to stop.
;; Inherit: <Serial::Untalk> In, Out, Errors, Keeps
;; Also: UNTLK (V20PRG)
KernalUntalk:
    jmp Serial::Untalk

.assert * = $FFAE, "UNLSN is at $FFAE."
;; $FFAE, UNLSN: tells the devices listening on the serial bus to stop, after the last byte, sent with EOI.
;; Inherit: <Serial::Unlisten> In, Out, Errors, Keeps
;; Also: UNLSN (V20PRG)
KernalUnlisten:
    jmp Serial::Unlisten

.assert * = $FFB1, "LISTEN is at $FFB1."
;; $FFB1, LISTEN: tells device A on the serial bus to listen. Commodore's listing names the routine LISTN.
;; Inherit: <Serial::Listen> In, Out, Errors, Keeps
;; Also: LISTEN (V20PRG)
KernalListen:
    jmp Serial::Listen

.assert * = $FFB4, "TALK is at $FFB4."
;; $FFB4, TALK: tells device A on the serial bus to talk.
;; Inherit: <Serial::Talk> In, Out, Errors, Keeps
;; Also: TALK (MTV, V20PRG)
KernalTalk:
    jmp Serial::Talk

.assert * = $FFB7, "READST is at $FFB7."
;; $FFB7, READST: returns the status of the last input or output in A. Commodore's listing names the routine READSS.
;; Inherit: <Channels::ReadStatus> In, Out, Errors, Keeps
;; Also: READST (MTV, V20PRG)
KernalReadStatus:
    jmp Channels::ReadStatus

.assert * = $FFBA, "SETLFS is at $FFBA."
;; $FFBA, SETLFS: sets the logical file number, the device and the secondary address for OPEN, LOAD and SAVE.
;; Inherit: <Channels::SetFile> In, Out, Errors, Keeps
;; Also: SETLFS (MTV, V20PRG)
KernalSetFile:
    jmp Channels::SetFile

.assert * = $FFBD, "SETNAM is at $FFBD."
;; $FFBD, SETNAM: sets the file name for OPEN, LOAD and SAVE.
;; Inherit: <Channels::SetFileName> In, Out, Errors, Keeps
;; Also: SETNAM (MTV, V20PRG)
KernalSetFileName:
    jmp Channels::SetFileName

.assert * = $FFC0, "OPEN is at $FFC0."
;; $FFC0, OPEN: opens the logical file SETLFS and SETNAM described, through <OpenVector>.
;; Inherit: <Channels::Open> In, Out, Errors
;; Also: OPEN (KV20, MTV, V20PRG)
KernalOpen:
    jmp (OpenVector)

.assert * = $FFC3, "CLOSE is at $FFC3."
;; $FFC3, CLOSE: closes logical file A, through <CloseVector>.
;; Inherit: <Channels::Close> In, Out, Errors
;; Also: CLOSE (KV20, MTV, V20PRG)
KernalClose:
    jmp (CloseVector)

.assert * = $FFC6, "CHKIN is at $FFC6."
;; $FFC6, CHKIN: makes logical file X the input channel, through <SelectInputVector>.
;; Inherit: <Channels::SelectInput> In, Out, Errors
;; Also: CHKIN (KV20, MTV, V20PRG)
KernalSelectInput:
    jmp (SelectInputVector)

.assert * = $FFC9, "CHKOUT is at $FFC9."
;; $FFC9, CHKOUT: makes logical file X the output channel, through <SelectOutputVector>.
;; Inherit: <Channels::SelectOutput> In, Out, Errors
;; Also: CKOUT (KV20), CHKOUT (MTV, V20PRG)
KernalSelectOutput:
    jmp (SelectOutputVector)

.assert * = $FFCC, "CLRCHN is at $FFCC."
;; $FFCC, CLRCHN: puts input back to the keyboard and output to the screen, through <ResetChannelsVector>.
;; Inherit: <Channels::ResetChannels> In, Out, Errors
;; Also: CLRCH (KV20), CLRCHN (MTV, V20PRG)
KernalResetChannels:
    jmp (ResetChannelsVector)

.assert * = $FFCF, "CHRIN is at $FFCF."
;; $FFCF, CHRIN: reads a character from the input channel, through <CharacterInVector>.
;; Inherit: <Channels::CharacterIn> In, Out, Errors
;; Also: BASIN (KV20), CHRIN (MTV, V20PRG)
KernalCharacterIn:
    jmp (CharacterInVector)

.assert * = $FFD2, "CHROUT is at $FFD2."
;; $FFD2, CHROUT: writes the character in A to the output channel, through <CharacterOutVector>.
;; Inherit: <Channels::CharacterOut> In, Out, Errors
;; Also: BSOUT (KV20), CHROUT (V20PRG)
KernalCharacterOut:
    jmp (CharacterOutVector)

.assert * = $FFD5, "LOAD is at $FFD5."
;; $FFD5, LOAD: loads, or verifies, a file into memory: <Channels::LoadToAddress> keeps the address in X/Y, then
;; goes through <LoadVector>. Commodore's listing names the routine LOADSP.
;; Inherit: <Channels::Load> In, Out, Errors
;; Also: LOAD (MTV, V20PRG)
KernalLoad:
    jmp Channels::LoadToAddress

.assert * = $FFD8, "SAVE is at $FFD8."
;; $FFD8, SAVE: saves memory to a file: <Channels::SaveRange> keeps the range, from the address in the zero-page pair
;; A points at to X/Y, then goes through <SaveVector>. Commodore's listing names the routine SAVESP.
;; Inherit: <Channels::Save> In, Out, Errors
;; Also: SAVE (MTV, V20PRG)
KernalSave:
    jmp Channels::SaveRange

.assert * = $FFDB, "SETTIM is at $FFDB."
;; $FFDB, SETTIM: sets the jiffy clock.
;; Inherit: <Clock::Set> In, Out, Errors, Keeps
;; Also: SETTIM (MTV, V20PRG)
KernalSetClock:
    jmp Clock::Set

.assert * = $FFDE, "RDTIM is at $FFDE."
;; $FFDE, RDTIM: reads the jiffy clock.
;; Inherit: <Clock::Read> In, Out, Errors, Keeps
;; Also: RDTIM (MTV, V20PRG)
KernalReadClock:
    jmp Clock::Read

.assert * = $FFE1, "STOP is at $FFE1."
;; $FFE1, STOP: tells whether the STOP key is down, through <TestStopKeyVector>.
;; Inherit: <Channels::TestStopKey> In, Out, Errors
;; Also: STOP (KV20, MTV, V20PRG)
KernalTestStopKey:
    jmp (TestStopKeyVector)

.assert * = $FFE4, "GETIN is at $FFE4."
;; $FFE4, GETIN: gets a character from the input channel without waiting for one, through <GetInputVector>.
;; Inherit: <Channels::GetInput> In, Out, Errors
;; Also: GETIN (KV20, MTV, V20PRG)
KernalGetInput:
    jmp (GetInputVector)

.assert * = $FFE7, "CLALL is at $FFE7."
;; $FFE7, CLALL: forgets every open file and resets the channels, through <CloseAllFilesVector>.
;; Inherit: <Channels::CloseAll> In, Out, Errors
;; Also: CLALL (KV20, MTV, V20PRG)
KernalCloseAll:
    jmp (CloseAllFilesVector)

.assert * = $FFEA, "UDTIM is at $FFEA."
;; $FFEA, UDTIM: counts a jiffy on the clock and reads the STOP key's row, for a program that takes the IRQ over.
;; Inherit: <Clock::Tick> In, Out, Errors, Keeps
;; Also: UDTIM (MTV, V20PRG)
KernalTickClock:
    jmp Clock::Tick

.assert * = $FFED, "SCREEN is at $FFED."
;; $FFED, SCREEN: returns the screen's size, its columns in X and its rows in Y.
;; Inherit: <Editor::ScreenSize> In, Out, Errors, Keeps
;; Also: JSCROG (KV20), SCREEN (V20PRG)
KernalScreenSize:
    jmp Editor::ScreenSize

.assert * = $FFF0, "PLOT is at $FFF0."
;; $FFF0, PLOT: reads the cursor's row and column into X and Y, with carry set, or moves the cursor there, with carry
;; clear.
;; Inherit: <Editor::Plot> In, Out, Errors, Keeps
;; Also: JPLOT (KV20), PLOT (MTV, V20PRG)
KernalPlot:
    jmp Editor::Plot

.assert * = $FFF3, "IOBASE is at $FFF3."
;; $FFF3, IOBASE: returns the I/O's address, VIA 1's at $9110, in X/Y.
;; Inherit: <Editor::IoBase> In, Out, Errors, Keeps
;; Also: JIOBAS (KV20), IOBASE (MTV, V20PRG)
KernalIoBase:
    jmp Editor::IoBase

    ; Unused, up to the processor's vectors.
    .res $FFFA - *, $FF

; The 6502's vectors, which the processor reads: the NMI's at $FFFA, the reset's at $FFFC and the IRQ's (BRK's too)
; at $FFFE.
.assert * = $FFFA, "The processor's vectors start at $FFFA."
    .word Interrupts::Nmi                   ; $FFFA: NMI, the RESTORE key and RS-232
    .word Startup::Reset                    ; $FFFC: reset
    .word Interrupts::Irq                   ; $FFFE: IRQ and BRK
