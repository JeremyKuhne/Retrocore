; retrocore: style=strict
;; APPLE IIE EQUATES: PAGE ZERO, LOW MEMORY, SOFT SWITCHES AND KEYS
;;
;; The IIe's page-zero locations, low-memory vectors and buffers, soft switches and I/O locations, and keyboard
;; characters. The Monitor, both models' internal firmware, the Disk II boot ROM, DOS and the SDK's card and program
;; sources include this file, so each name here is defined and documented once, and each of those sources defines
;; only the names that are its own. The Monitor's entry points, which the Monitor defines as labels, are in
;; MonitorEntries.asm for the others.
;;
;; The names follow the assembly style guide. Each definition lists the names Apple's manuals and listings give its
;; location as its historical names, so code written with them, and the sources that still use them, assemble
;; unchanged.
;;
;; Three Monitor names are not here: <Monitor:LOC1> and <Monitor:CV>, which DOS uses for names of its own, are in
;; Monitor/Equates.asm and FirmwareEquates.asm, and <Monitor:CLRROM>, a label in the Enhanced IIe's firmware, is in
;; Monitor/Equates.asm and Firmware.Original.asm.

; Page zero: the Monitor's text window, cursor, lo-res graphics, hooks, addresses and saved registers.

;; The low byte of a pointer the Monitor borrows for short jobs.
;;
;; The Autostart and IIe Monitors' <Monitor:Startup::PowerUp> points <SlotPointer>/<Monitor:LOC1> at each slot's $Cn00
;; page in turn while it looks for a disk controller, then jumps through them to the one it finds. <Monitor:SetHook>
;; stores a hook through <SlotPointer>,X with X = <OutputHook> or <InputHook>, and the self-tests in the internal
;; firmware use it as a working pointer.
;; See: <Monitor:LOC1>, <Monitor:Startup::PowerUp>, <Monitor:SetHook>
;; Also: LOC0 (A2RM78, A2RM79, IIEROM82, IIETRM85)
SlotPointer = $00

;; The column where the text window starts, 0 for a full screen.
;;
;; <Monitor:SetWindow> clears it, and <Monitor:SetLineBase> adds it to <TextBase> (on the Enhanced IIe, through the
;; firmware's <Firmware:VTAB80>), so <CursorColumn> counts columns from the window's left edge. In 80 columns, the
;; firmware adds half of it, since each byte of a line then holds two columns.
;; See: <WindowWidth>, <WindowTop>, <WindowBottom>, <Monitor:SetWindow>
;; Also: WNDLFT (A2RM78, A2RM79, IIEROM82, IIETRM85)
WindowLeft = $20

;; The width of the text window in columns: 40, or 80 when the 80-column firmware is active.
;;
;; <Monitor:AdvanceCursor> starts a new line when <CursorColumn> reaches it, and <Monitor:Backspace> moves to the
;; column before it on the line above. <Monitor:SetWindow> sets it to 40 on the Apple II's Monitors; on the IIe,
;; the internal firmware sets it there and when it switches between 40 and 80 columns.
;; See: <WindowLeft>, <CursorColumn>, <Monitor:SetWindow>
;; Also: WNDWDTH (A2RM78, A2RM79, IIEROM82, IIETRM85)
WindowWidth = $21

;; The first line of the text window, 0-23.
;;
;; <Monitor:SetWindow> sets it from A: <Monitor:SetText> gives 0, a full screen, and <Monitor:SetGraphics> 20, the
;; four text lines below mixed graphics. <Monitor:CursorUp> stops at it, and <Monitor:Home> and <Monitor:Scroll>
;; start there.
;; See: <WindowBottom>, <Monitor:CV>, <Monitor:SetWindow>
;; Also: WNDTOP (A2RM78, A2RM79, IIEROM82, IIETRM85)
WindowTop = $22

;; The line below the text window, 1-24, not the window's last line: 24 for a window that reaches the bottom of the
;; screen.
;;
;; The window's lines run from <WindowTop> up to, but not including, this one. <Monitor:LineFeed> scrolls the window
;; instead of moving <Monitor:CV> to it. <Monitor:SetWindow> sets it to 24, through the internal firmware on the
;; IIe.
;; See: <WindowTop>, <Monitor:CV>, <Monitor:LineFeed>, <Monitor:Scroll>
;; Also: WNDBTM (A2RM78, A2RM79, IIEROM82, IIETRM85)
WindowBottom = $23

;; The cursor's column, counted from the window's left edge, <WindowLeft>.
;;
;; <Monitor:StoreAndAdvance> stores each character at (<TextBase>),Y with Y = <CursorColumn>, and
;; <Monitor:AdvanceCursor>, <Monitor:Backspace> and <Monitor:CarriageReturn> move it. The 80-column firmware keeps
;; its own column in <Firmware:OURCH>, copies it here after each character in 40 columns, and takes up a new value a
;; program stores here (<Firmware:SYNCCH>).
;; See: <Monitor:CV>, <TextBase>, <WindowWidth>, <Firmware:OURCH>
;; Also: CH (A2RM78, A2RM79, IIEROM82, IIETRM85)
CursorColumn = $24

;; The low byte of the address of the text line that holds the lo-res row being drawn.
;;
;; <Monitor:LowRes::RowAddress> sets <LowResBase>/<LowResBaseHigh> from a text line, half the row: each text line
;; holds two lo-res rows, one in each nibble. <Monitor:LowRes::Plot::SameRow> and <Monitor:LowRes::ReadColor> then
;; read and write (<LowResBase>),Y with Y = the column.
;; See: <LowResBaseHigh>, <Monitor:LowRes::RowAddress>, <Monitor:LowRes::Plot>, <Monitor:LowRes::ReadColor>
;; Also: GBASL (A2RM78, A2RM79, IIEROM82, IIETRM85)
LowResBase = $26

;; The high byte of the lo-res line address at <LowResBase>.
;;
;; <Monitor:LowRes::RowAddress> sets it to $04-$07, the text and lo-res page one.
;; See: <LowResBase>, <Monitor:LowRes::RowAddress>
;; Also: GBASH (A2RM78, A2RM79, IIEROM82, IIETRM85)
LowResBaseHigh = $27

;; The low byte of the address of the text line the cursor is on, plus the window's left edge.
;;
;; <Monitor:BaseAddress> sets <TextBase>/<TextBaseHigh> from a line number, and <Monitor:VerticalTab> sets them for
;; <Monitor:CV>, adding <WindowLeft>. <Monitor:StoreAndAdvance> then stores each character at (<TextBase>),Y with
;; Y = <CursorColumn>. On the Enhanced IIe, <Monitor:SetLineBase> has the internal firmware's <Firmware:VTAB80>
;; compute them.
;; See: <TextBaseHigh>, <Monitor:BaseAddress>, <Monitor:VerticalTab>, <Monitor:CV>, <CursorColumn>
;; Also: BASL (A2RM78, A2RM79, IIEROM82, IIETRM85)
TextBase = $28

;; The high byte of the text line address at <TextBase>.
;;
;; <Monitor:BaseAddress> sets it to $04-$07, text page one.
;; See: <TextBase>, <Monitor:BaseAddress>
;; Also: BASH (A2RM78, A2RM79, IIEROM82, IIETRM85)
TextBaseHigh = $29

;; The low byte of a second text line address, the line a scroll copies to.
;;
;; <Monitor:Scroll> sets <ScrollBase> and <ScrollBaseHigh> to the line at <TextBase>, moves <TextBase> down a line
;; and copies that line up into this one; on the IIe, the internal firmware's scroll routines do. On the Enhanced
;; IIe, <Monitor:ClearLineFrom> and <Monitor:Disassembler::Decode> also pass a value to the firmware here: the column
;; to clear from, or the opcode to decode.
;; See: <TextBase>, <ScrollBaseHigh>, <Monitor:Scroll>, <Monitor:ClearLineFrom>
;; Also: BAS2L (A2RM78, A2RM79, IIEROM82, IIETRM85)
ScrollBase = $2A

;; The high byte of the second text line address at <ScrollBase>, the line a scroll copies to.
;;
;; The scroll routines set it with <ScrollBase>. The original IIe's 40/80-column conversion also counts columns here
;; while it copies the screen.
;; See: <ScrollBase>, <TextBaseHigh>
;; Also: BAS2H (A2RM78, A2RM79, IIEROM82, IIETRM85)
ScrollBaseHigh = $2B

;; The rightmost column of a horizontal lo-res line.
;;
;; <Monitor:LowRes::HorizontalLine> plots from the column in Y to <HorizontalLineEnd>. The disassembler's
;; <Monitor:Disassembler::PrintInstruction> uses it while it unpacks a mnemonic.
;; See: <VerticalLineEnd>, <Monitor:LowRes::HorizontalLine>
;; Also: H2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
HorizontalLineEnd = $2C

;; The bottom row of a vertical lo-res line.
;;
;; <Monitor:LowRes::VerticalLine> plots from the row in A down to <VerticalLineEnd>, and <Monitor:LowRes::Clear> and
;; <Monitor:LowRes::ClearTop> set it to clear the screen. The disassembler's
;; <Monitor:Disassembler::PrintInstruction> uses it while it unpacks a mnemonic.
;; See: <HorizontalLineEnd>, <Monitor:LowRes::VerticalLine>, <Monitor:LowRes::Clear>
;; Also: V2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
VerticalLineEnd = $2D

;; The nibble a lo-res plot changes: $0F for an even row, $F0 for an odd one.
;;
;; <Monitor:LowRes::Plot> sets it and <Monitor:LowRes::Plot::SameRow> uses it, so <Monitor:LowRes::Plot::SameRow>
;; can plot again on the same row. The disassembler's <Monitor:Disassembler::Decode> also leaves an instruction's
;; operand format here for <Monitor:Disassembler::PrintInstruction::FormatCharacter>, the cassette
;; <Monitor:ReadCassette> keeps its checksum here, and the Enhanced IIe's mini-assembler uses it too.
;; See: <Monitor:LowRes::Plot>, <Monitor:LowRes::Plot::SameRow>, <PlotColor>, <Monitor:Disassembler::Decode>
;; Also: MASK (A2RM78, A2RM79, IIEROM82, IIETRM85)
PlotMask = $2E

;; The number of operand bytes of the instruction being disassembled, 0-2.
;;
;; <Monitor:Disassembler::Decode> sets it from the opcode, and <Monitor:Disassembler::PrintInstruction> and
;; <Monitor:NextInstruction> use it to print the bytes and step to the next instruction. The cassette routines keep
;; the last input level here while they read a bit.
;;
;; On the Enhanced IIe, the internal firmware's <Firmware:CXINSDS2> sets it for <Monitor:Disassembler::Decode>, and
;; its <Firmware:RDTAPE2BIT> keeps the cassette input level. DOS's relocator, <Dos33:DOSREL>, calls <Dos33:INSDS2> on
;; each instruction and reads the instruction's length here to step to the next.
;; See: <Monitor:Disassembler::Decode>, <Monitor:NextInstruction>, <ProgramCounter>, <PlotMask>
;; Also: LENGTH (A2RM78, A2RM79, IIEROM82, IIETRM85)
OperandLength = $2F

;; The lo-res color to plot, the same color in both nibbles.
;;
;; <Monitor:LowRes::SetColor> sets it from a color number (0-15) and <Monitor:LowRes::NextColor> steps to the next.
;; <Monitor:LowRes::Plot::SameRow> merges it into the screen through <PlotMask>, and <Monitor:LowRes::Clear> and
;; <Monitor:LowRes::ClearTop> set it to 0, black.
;; See: <Monitor:LowRes::SetColor>, <Monitor:LowRes::NextColor>, <Monitor:LowRes::Plot>, <PlotMask>
;; Also: COLOR (A2RM78, A2RM79, IIEROM82, IIETRM85)
PlotColor = $30

;; The Monitor command that is waiting for its second number: ".", ":", "+" or "-", or 0 for none.
;;
;; <Monitor:Commands::SetMode> sets it from the command character, and <Monitor:Commands::Blank::Store> keeps it at
;; ":" so each number after a colon is stored. While it is not 0, <Monitor:Commands::CopyNumber> does not copy a new
;; number to <Address1> and <Address3>. <Monitor:Commands::RunCommand> passes it to each command in A, and
;; <Monitor:ClearMode> clears it.
;; See: <Monitor:Commands::SetMode>, <Monitor:ClearMode>, <Monitor:Commands::RunCommand>,
;;   <Monitor:CommandLine::NextItem>
;; Also: MODE (A2RM78, A2RM79, IIEROM82, IIETRM85)
CommandMode = $31

;; The mask <Monitor:ScreenOut> ands with each printable character: $FF for normal text, $3F for inverse, $7F for
;; flashing.
;;
;; <Monitor:SetNormal> and <Monitor:SetInverse> set it, and <Monitor:Startup::Reset> restores normal text. The
;; 80-column firmware tests only its bit 7, showing inverse text when it is clear. The Apple II's
;; Monitors' <Monitor:LineInput::Echo> sets it to $FF while it echoes a character, then restores it.
;; See: <Monitor:SetNormal>, <Monitor:SetInverse>, <Monitor:ScreenOut>
;; Also: INVFLG (A2RM78, A2RM79, IIEROM82, IIETRM85)
InverseMask = $32

;; The character <Monitor:GetLine> prints before it reads a line.
;;
;; The Monitor sets "*" (<Monitor:CommandLine>), and the Enhanced IIe's mini-assembler "!". Applesoft sets "]" and
;; Integer `BASIC` ">". DOS watches its output for this character to spot an input line (<Dos33:COS0>), and
;; <Dos33:TSTRUN> takes "]" to mean that Applesoft is not running a program.
;;
;; DOS changes it too: its command scanner (<Dos33:SYN1>) stores a value other than "]" for RUN, and <Dos33:ASRUN1>
;; and <Dos33:ASRUN2> store 0, so that <Dos33:TSTRUN> sees a program running.
;; See: <Monitor:GetLine>, <Monitor:CommandLine>, <Dos33:TSTRUN>
;; Also: PROMPT (A2RM78, A2RM79, IIEROM82, IIETRM85)
PromptCharacter = $33

;; Where the Monitor's command line resumes: the index in <InputBuffer> after the last command character.
;;
;; <Monitor:CommandLine::NextItem> saves Y here after <Monitor:ReadHexNumber>, and <Monitor:Commands::SetMode> and
;; <Monitor:CommandLine::Search>, after the command it runs, read it back. <Monitor:Commands::ExamineNextOrBlank> counts
;; it down so that Return alone shows the next eight bytes. The Enhanced IIe's mini-assembler uses it too.
;; See: <Monitor:CommandLine::NextItem>, <Monitor:ReadHexNumber>, <InputBuffer>
;; Also: YSAV (A2RM78, A2RM79, IIEROM82, IIETRM85)
CommandPosition = $34

;; Y, saved by <Monitor:ScreenOutNoInverse> while it prints a character.
;;
;; <Monitor:ScreenOutNoInverse> stores Y here first and reloads it at the end, so <Monitor:ScreenOut> keeps Y. On
;; the Enhanced IIe, the internal firmware's 80-column output reads it and the mini-assembler uses it as scratch.
;; See: <Monitor:ScreenOutNoInverse>, <Monitor:ScreenOut>
;; Also: YSAV1 (A2RM78, A2RM79, IIEROM82, IIETRM85), SAVY1 (IIETRM85)
SavedOutputY = $35

;; The low byte of the output hook: the address of the routine <Monitor:CharacterOut> sends each character to.
;;
;; <Monitor:CharacterOut> jumps through <OutputHook>/<OutputHookHigh>. <Monitor:SetScreen> points it at
;; <Monitor:ScreenOut>, the screen, and <Monitor:SetOutput>, which the Monitor's Control-P command uses, at a slot's
;; $Cn00. DOS keeps the hook pointed at itself (<Dos33:OUTSW>) and passes characters on.
;; See: <Monitor:CharacterOut>, <Monitor:SetScreen>, <Monitor:SetOutput>, <InputHook>, <OutputHookHigh>
;; Also: CSWL (A2RM78, A2RM79, IIEROM82, IIETRM85)
OutputHook = $36

;; The high byte of the output hook at <OutputHook>.
;;
;; Sending output to slot 3 and the 80-column firmware's start-up point the hook at <Firmware:BASICOUT@Enhanced>
;; ($C307); <Monitor:SetOutput> first points it at $C300. Quitting the firmware with Control-U points it back at
;; <Monitor:ScreenOut>.
;; See: <OutputHook>, <Monitor:CharacterOut>
;; Also: CSWH (A2RM78, A2RM79, IIEROM82, IIETRM85)
OutputHookHigh = $37

;; The low byte of the input hook: the address of the routine <Monitor:ReadKey> reads each key from.
;;
;; <Monitor:ReadKey> jumps through <InputHook>/<InputHookHigh>. <Monitor:SetKeyboard> points it at
;; <Monitor:KeyboardIn>, the keyboard, and <Monitor:SetInput> at a slot's $Cn00. DOS keeps the hook pointed at itself
;; (<Dos33:INSW>) and passes keys on.
;; See: <Monitor:ReadKey>, <Monitor:SetKeyboard>, <Monitor:SetInput>, <OutputHook>, <InputHookHigh>
;; Also: KSWL (A2RM78, A2RM79, IIEROM82, IIETRM85)
InputHook = $38

;; The high byte of the input hook at <InputHook>.
;;
;; The 80-column firmware's start-up points the hook at <Firmware:BASICIN@Enhanced> ($C305). Quitting the firmware
;; with Control-U points it back at <Monitor:KeyboardIn>.
;; See: <InputHook>, <Monitor:ReadKey>
;; Also: KSWH (A2RM78, A2RM79, IIEROM82, IIETRM85)
InputHookHigh = $39

;; The low byte of the Monitor's program counter, the address the disassembler and G work from.
;;
;; <Monitor:Break> sets <ProgramCounter>/<ProgramCounterHigh> from the return address a BRK pushed, and
;; <Monitor:SetPcFromA1> copies a typed address to them. <Monitor:Disassembler::PrintInstruction> disassembles the
;; instruction there, <Monitor:ListInstructions> steps through, and <Monitor:Commands::Go> jumps through them. The
;; Enhanced IIe's mini-assembler works from it too: <Firmware:MINIREL> computes a branch's offset from it.
;; See: <ProgramCounterHigh>, <Monitor:Disassembler::PrintInstruction>, <Monitor:ListInstructions>,
;;   <Monitor:Commands::Go>, <Monitor:Break>
;; Also: PCL (A2RM78, A2RM79, IIEROM82, IIETRM85)
ProgramCounter = $3A

;; The high byte of the Monitor's program counter at <ProgramCounter>.
;; See: <ProgramCounter>
;; Also: PCH (A2RM78, A2RM79, IIEROM82, IIETRM85)
ProgramCounterHigh = $3B

;; The low byte of the Monitor's first address: the start of the range a command works on.
;;
;; <Monitor:Commands::CopyNumber> copies each number typed to <Address1>/<Address1High> unless <CommandMode> holds a
;; command, and <Monitor:NextInRange> steps it through the range up to <Address2>. Examine, <Monitor:MoveMemory>,
;; <Monitor:VerifyMemory>, the cassette routines and the firmware's <Firmware:AUXMOVE@Enhanced> all start there.
;; See: <Address1High>, <Address2>, <Monitor:NextInRange>, <Monitor:Commands::ExamineLine::Range>
;; Also: A1L (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address1 = $3C

;; The high byte of the Monitor's first address at <Address1>.
;; See: <Address1>
;; Also: A1H (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address1High = $3D

;; The low byte of the Monitor's second address: the number just typed, and the end of a range.
;;
;; <Monitor:ReadHexNumber> builds each number in <Address2>/<Address2High>, and <Monitor:Commands::CopyNumber>
;; copies it to <Address1> and <Address3>. <Monitor:NextInRange> ends a range there, and <Monitor:SetOutput> and
;; <Monitor:SetInput> take the slot from it.
;; See: <Address2High>, <Address1>, <Monitor:ReadHexNumber>, <Monitor:NextInRange>
;; Also: A2L (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address2 = $3E

;; The high byte of the Monitor's second address at <Address2>.
;; See: <Address2>
;; Also: A2H (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address2High = $3F

;; The low byte of the Monitor's third address: where the next byte typed after a colon is stored.
;;
;; <Monitor:Commands::CopyNumber> sets <Address3>/<Address3High> with <Address1>, and
;; <Monitor:Commands::Blank::Store> stores each number there and advances it. <Monitor:ShowRegisters::NoReturn>
;; borrows it to point at the saved registers.
;; See: <Address3High>, <Monitor:Commands::Blank::Store>, <Monitor:Commands::CopyNumber>
;; Also: A3L (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address3 = $40

;; The high byte of the Monitor's third address at <Address3>.
;; See: <Address3>
;; Also: A3H (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address3High = $41

;; The low byte of the Monitor's fourth address: the destination of a move or verify.
;;
;; The < command (<Monitor:Commands::Destination>) copies <Address2>/<Address2High> here and to <Address5>.
;; <Monitor:MoveMemory> and <Monitor:VerifyMemory> step it with <Monitor:NextInRangeAndTarget> along with
;; <Address1>, and the firmware's <Firmware:AUXMOVE@Enhanced> uses it the same way. The Enhanced IIe's search,
;; <Monitor:Commands::Search>, takes the bytes to find from <Address4> and <Address4High> instead.
;; See: <Address4High>, <Monitor:Commands::Destination>, <Monitor:MoveMemory>, <Monitor:VerifyMemory>,
;;   <Monitor:NextInRangeAndTarget>
;; Also: A4L (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address4 = $42

;; The high byte of the Monitor's fourth address at <Address4>.
;; See: <Address4>
;; Also: A4H (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address4High = $43

;; The low byte of the Monitor's fifth address, a copy of the destination the < command sets.
;;
;; <Monitor:Commands::Destination> copies <Address2>/<Address2High> to <Address4> and here. The Enhanced IIe's
;; interrupt handler leaves the memory state it found here for a BRK, and its mini-assembler collects an operand's
;; address mode in it.
;; See: <Address5High>, <Monitor:Commands::Destination>, <Address4>
;; Also: A5L (A2RM78, A2RM79, IIEROM82, IIETRM85), MACSTAT (IIETRM85)
Address5 = $44

;; The high byte of the Monitor's fifth address at <Address5>, the same byte as <SavedA>.
;;
;; The Monitor saves the accumulator here, as <SavedA>, and its < command copies a destination's high byte here
;; (<Monitor:Commands::Destination::Copy>).
;; See: <Address5>, <SavedA>
;; Also: A5H (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address5High = $45

;; The accumulator, saved by the Monitor's BRK and interrupt entries and by <Monitor:SaveRegisters>; on the Enhanced
;; IIe, whose IRQ vector reaches the firmware, only for a BRK.
;;
;; <Monitor:Interrupt> and <Monitor:SaveRegisters> store A here and <Monitor:RestoreRegisters> reloads it. It is the
;; first of the five saved registers, ahead of <SavedX>, <SavedY>, <SavedStatus> and <SavedStackPointer>, which
;; <Monitor:ShowRegisters> shows in that order. It is the same byte as <Address5High>.
;; See: <Monitor:SaveRegisters>, <Monitor:RestoreRegisters>, <Monitor:ShowRegisters>, <SavedX>
;; Also: ACC (A2RM78, A2RM79, IIEROM82, IIETRM85)
SavedA = Address5High

;; The X register, saved by <Monitor:SaveRegisters>.
;;
;; <Monitor:SaveRegisters::ExceptA> stores X here and <Monitor:RestoreRegisters> reloads it before
;; <Monitor:Commands::Go> runs a program. <Monitor:ShowRegisters> shows it as X=.
;; See: <SavedA>, <SavedY>, <Monitor:SaveRegisters>, <Monitor:RestoreRegisters>
;; Also: XREG (A2RM78, A2RM79, IIEROM82, IIETRM85)
SavedX = $46

;; The Y register, saved by <Monitor:SaveRegisters>.
;;
;; <Monitor:SaveRegisters::ExceptA> stores Y here and <Monitor:RestoreRegisters> reloads it before
;; <Monitor:Commands::Go> runs a program. <Monitor:ShowRegisters> shows it as Y=.
;; See: <SavedA>, <SavedX>, <Monitor:SaveRegisters>, <Monitor:RestoreRegisters>
;; Also: YREG (A2RM78, A2RM79, IIEROM82, IIETRM85)
SavedY = $47

;; The processor status, P, saved by <Monitor:SaveRegisters>.
;;
;; <Monitor:SaveRegisters::ExceptA> stores P here and <Monitor:RestoreRegisters> pulls it into P before
;; <Monitor:Commands::Go> runs a program. <Monitor:InitDisplay> clears it, and <Monitor:ShowRegisters> shows it as P=.
;; See: <SavedA>, <SavedStackPointer>, <Monitor:SaveRegisters>, <Monitor:RestoreRegisters>
;; Also: STATUS (A2RM78, A2RM79, IIEROM82, IIETRM85)
SavedStatus = $48

;; The stack pointer, S, saved by <Monitor:SaveRegisters>.
;;
;; <Monitor:SaveRegisters::ExceptA> stores S here for <Monitor:ShowRegisters> to show as S=.
;; <Monitor:RestoreRegisters> does not reload it.
;; See: <SavedA>, <SavedStatus>, <Monitor:SaveRegisters>
;; Also: SPNT (A2RM78, A2RM79, IIEROM82, IIETRM85)
SavedStackPointer = $49

;; The low byte of a count that runs while the firmware waits for a key, a seed for random numbers.
;;
;; The keyboard input routines increment <RandomSeed> on every pass of their wait loop, and <RandomSeedHigh> when it
;; wraps, so the count depends on how long the user takes to type. Programs read it to seed their random numbers.
;; See: <RandomSeedHigh>, <Monitor:KeyboardIn>
;; Also: RNDL (A2RM78, A2RM79, IIEROM82, IIETRM85)
RandomSeed = $4E

;; The high byte of the key-wait count at <RandomSeed>.
;;
;; The Enhanced IIe's 40-column key wait also blinks the cursor each time bit 6 of it changes.
;; See: <RandomSeed>
;; Also: RNDH (A2RM78, A2RM79, IIEROM82, IIETRM85)
RandomSeedHigh = $4F

; Pages 2 to 7: the input buffer, the vectors in page 3, text page one and the screen hole for the $C800 ROM.

;; The input line buffer, $0200-$02FF, that <Monitor:GetLine> fills.
;;
;; <Monitor:GetLine> stores each character typed here, ending the line with a carriage return, and the Monitor's
;; command line reads its commands from it.
;; See: <Monitor:GetLine>, <CommandPosition>
;; Also: IN (A2RM78, A2RM79, IIEROM82, IIETRM85)
InputBuffer = $0200

;; The address <Monitor:Break> jumps through once it has saved the registers: the BRK handler.
;;
;; The Autostart and IIe Monitors' <Monitor:Startup::PowerUp> points it at <Monitor:ShowBreak>, which shows the
;; registers and enters the Monitor; a program can point it at a handler of its own. The Apple II Monitor has no
;; such vector.
;; See: <Monitor:Break>, <Monitor:ShowBreak>, <Monitor:Startup::PowerUp>
;; Also: BRKV (A2RM79, IIEROM82, IIETRM85)
BreakVector = $03F0

;; The soft entry: the address a reset jumps through once <SoftEntryCheck> shows it is valid.
;;
;; The Autostart and IIe Monitors' <Monitor:Startup::Reset> jumps through it when <SoftEntryCheck> matches its high
;; byte, and otherwise powers up; the Apple II Monitor has no soft entry.
;; <Monitor:Startup::PowerUp> points it at <Monitor:BasicColdStart>, and <Monitor:Startup::Reset::FixSoftEntry>,
;; which the first reset after that or a power-up that finds no disk goes through, at <Monitor:BasicWarmStart>, so
;; later resets keep the program.
;; See: <SoftEntryCheck>, <Monitor:Startup::Reset>, <Monitor:ValidateSoftEntry>
;; Also: SOFTEV (A2RM79, IIEROM82, IIETRM85)
SoftEntryVector = $03F2

;; The byte that shows <SoftEntryVector> is valid: its high byte exclusive-ored with $A5.
;;
;; <Monitor:ValidateSoftEntry> sets it for the vector's current value, so a program that changes the vector calls it.
;; A check byte that does not match makes the Autostart and IIe Monitors' <Monitor:Startup::Reset> power up instead.
;; See: <SoftEntryVector>, <Monitor:ValidateSoftEntry>, <Monitor:Startup::Reset>
;; Also: PWREDUP (A2RM79, IIEROM82, IIETRM85)
SoftEntryCheck = $03F4

;; A JMP instruction, placed by a program, that the Monitor's Control-Y command runs.
;;
;; <Monitor:Commands::User> jumps here, so the JMP takes Control-Y to the program's own routine.
;; See: <Monitor:Commands::User>, <KEY_CONTROL_Y>
;; Also: USRADR (A2RM78, A2RM79, IIEROM82, IIETRM85)
UserJump = $03F8

;; A JMP instruction, placed by a program, that a non-maskable interrupt runs.
;;
;; The 6502's NMI vector in the Monitor ROM, <Monitor:NmiVector>, points here.
;; See: <Monitor:NmiVector>
;; Also: NMI (A2RM78, A2RM79, IIEROM82, IIETRM85)
NmiJump = $03FB

;; The address the Monitor's interrupt handler jumps through for an IRQ that is not a BRK.
;;
;; On all but the Enhanced IIe, <Monitor:Interrupt> sends a BRK to <Monitor:Break> and any other IRQ through this
;; vector. On the Enhanced IIe, whose IRQ vector reaches the firmware instead, the firmware's interrupt code goes
;; through <Monitor:CallUserIrq> to it.
;; See: <Monitor:Interrupt>, <Monitor:CallUserIrq>, <BreakVector>
;; Also: IRQLOC (A2RM78, A2RM79, IIEROM82)
UserIrqVector = $03FE

;; Text page one, $0400-$07FF, which is also lo-res page one.
;; Also: LINE1 (A2RM79, IIEROM82, IIETRM85)
TextPage1 = $0400

;; The $Cn of the slot whose $C800 expansion ROM is selected, in a screen hole of text page one.
;;
;; The Autostart and IIe Monitors' <Monitor:Startup::PowerUp> stores each slot's $Cn here as it tries it. On the
;; Enhanced IIe, the interrupt code (<Monitor:SelectInterruptRom>) selects that slot's ROM again after the user's
;; handler, and <Monitor:Escape::ReadKeyAllowEscape> clears bit 7 to tell the 80-column firmware to take escape
;; sequences.
;; See: <Monitor:Startup::PowerUp>, <Monitor:SelectInterruptRom>
;; Also: MSLOT (A2RM79, IIEROM82, IIETRM85)
ExpansionRomSlot = $07F8

; Soft switches and I/O locations.

;; The keyboard: bit 7 is set when a key has been typed, and bits 0-6 are its code.
;;
;; The key stays here, bit 7 set, until a program clears the strobe by touching <KeyboardStrobe>.
;; <Monitor:KeyboardIn> waits on it, and on all but the Apple II Monitor, <Monitor:ScreenOutPausing> looks here for
;; Control-S. Writing the same address turns 80STORE off (<Store80Off>). Apple's IOADR names it as the start of the
;; I/O area.
;; See: <KeyboardStrobe>, <Monitor:KeyboardIn>, <Store80Off>
;; Also: KBD (A2RM78, A2RM79, IIEROM82, IIETRM85), IOADR (A2RM78, A2RM79, IIEROM82, IIETRM85)
Keyboard = $C000

;; Writing it turns 80STORE off: PAGE2 then chooses the displayed page again. It is the same address as <Keyboard>.
;;
;; <Store80On> turns it on, and <Store80State> reports it.
;; See: <Store80On>, <Store80State>, <Keyboard>
;; Also: CLR80COL (IIEROM82, IIETRM85)
Store80Off = $C000

;; Writing it turns 80STORE on: PAGE2 then maps main or auxiliary memory at the text page instead of choosing the
;; displayed page.
;;
;; With 80STORE on, <Page2On> maps auxiliary memory at $0400-$07FF and <Page2Off> main memory, and while hi-res
;; graphics are on (<HiResOn>), at $2000-$3FFF too; <AuxReadOff> and its partners then leave those pages alone. The
;; 80-column firmware turns it on to reach the even columns, which are in auxiliary memory. <Store80Off> turns it
;; off, and <Store80State> reports it. Apple's listings call it SET80COL, a name left out of Also: because the
;; Enhanced IIe's firmware has a label of that name, its Control-R routine.
;; See: <Store80Off>, <Store80State>, <Page2On>, <Page2Off>
;; Also: SET80STORE (UNKN)
Store80On = $C001

;; Writing it turns RAMRD off: reads from $0200-$BFFF come from main memory.
;;
;; <AuxReadOn> reads auxiliary memory instead, and <AuxReadState> reports the switch. With 80STORE on, the text page
;; follows PAGE2 instead. <Firmware:AUXMOVE@Enhanced> and the Enhanced IIe's interrupt handler set it.
;; See: <AuxReadOn>, <AuxReadState>, <AuxWriteOff>, <Firmware:AUXMOVE@Enhanced>
;; Also: RDMAINRAM (IIEROM82, IIETRM85)
AuxReadOff = $C002

;; Writing it turns RAMRD on: reads from $0200-$BFFF come from auxiliary memory.
;;
;; <AuxReadOff> reads main memory again, and <AuxReadState> reports the switch. Writes still follow RAMWRT
;; (<AuxWriteOn>). <Firmware:AUXMOVE@Enhanced> uses it to copy from auxiliary memory, and
;; <Firmware:XFER@Enhanced> to pass control to it.
;; See: <AuxReadOff>, <AuxReadState>, <AuxWriteOn>, <Firmware:AUXMOVE@Enhanced>, <Firmware:XFER@Enhanced>
;; Also: RDCARDRAM (IIEROM82, IIETRM85)
AuxReadOn = $C003

;; Writing it turns RAMWRT off: writes to $0200-$BFFF go to main memory.
;;
;; <AuxWriteOn> writes auxiliary memory instead, and <AuxWriteState> reports the switch. With 80STORE on, the text
;; page follows PAGE2 instead. <Firmware:AUXMOVE@Enhanced> and the Enhanced IIe's interrupt handler set it.
;; See: <AuxWriteOn>, <AuxWriteState>, <AuxReadOff>, <Firmware:AUXMOVE@Enhanced>
;; Also: WRMAINRAM (IIEROM82, IIETRM85)
AuxWriteOff = $C004

;; Writing it turns RAMWRT on: writes to $0200-$BFFF go to auxiliary memory.
;;
;; <AuxWriteOff> writes main memory again, and <AuxWriteState> reports the switch. Reads still follow RAMRD
;; (<AuxReadOn>). <Firmware:AUXMOVE@Enhanced> and <Firmware:XFER@Enhanced> use it to copy to auxiliary memory.
;; See: <AuxWriteOff>, <AuxWriteState>, <AuxReadOn>, <Firmware:AUXMOVE@Enhanced>, <Firmware:XFER@Enhanced>
;; Also: WRCARDRAM (IIEROM82, IIETRM85)
AuxWriteOn = $C005

;; Writing it turns INTCXROM off: the peripheral cards' ROMs are at $C100-$CFFF.
;;
;; <InternalCxRomOn> maps the IIe's internal ROM there instead, and <InternalCxRomState> reports which is mapped in
;; bit 7. Slot 3's page, $C300, shows the card's ROM only while SLOTC3ROM is on too (<SlotC3RomOn>). The Monitor
;; writes it on its way back from the internal firmware: <Monitor:SelectSlotRom> on the Enhanced IIe,
;; <Monitor:SlotRomReturn> on the original.
;; See: <InternalCxRomOn>, <InternalCxRomState>, <Monitor:CallFirmware>, <Monitor:SelectSlotRom>,
;;   <Monitor:SlotRomReturn>
;; Also: SETSLOTCXROM (IIEROM82, IIETRM85), SLOTCXROM (IIETRM85)
InternalCxRomOff = $C006

;; Writing it turns INTCXROM on: the IIe's internal ROM is at $C100-$CFFF.
;;
;; <Monitor:CallFirmware> writes it before it enters the internal firmware at $C100, and the Enhanced IIe's cassette
;; and mini-assembler entries write it too. <InternalCxRomOff> maps the peripheral cards' ROMs back, and
;; <InternalCxRomState> reports which is mapped in bit 7.
;; See: <InternalCxRomOff>, <InternalCxRomState>, <Monitor:CallFirmware>
;; Also: SETINTCXROM (IIEROM82, IIETRM85), INTCXROM (IIETRM85)
InternalCxRomOn = $C007

;; Writing it turns ALTZP off: page zero, the stack and the language card area come from main memory.
;;
;; ALTZP switches $0000-$01FF and $D000-$FFFF together, so a program switching it keeps its own stack pointer for
;; each. <AuxZeroPageOn> uses auxiliary memory instead, and <AuxZeroPageState> reports the switch.
;; <Firmware:XFER@Enhanced> and the Enhanced IIe's interrupt handler set it.
;; See: <AuxZeroPageOn>, <AuxZeroPageState>, <Firmware:XFER@Enhanced>
;; Also: SETSTDZP (IIEROM82, IIETRM85)
AuxZeroPageOff = $C008

;; Writing it turns ALTZP on: page zero, the stack and the language card area come from auxiliary memory.
;;
;; <AuxZeroPageOff> uses main memory again, and <AuxZeroPageState> reports the switch. <Firmware:XFER@Enhanced> sets
;; it when asked to, and the self-tests use it to test auxiliary memory.
;; See: <AuxZeroPageOff>, <AuxZeroPageState>, <Firmware:XFER@Enhanced>
;; Also: SETALTZP (IIEROM82, IIETRM85)
AuxZeroPageOn = $C009

;; Writing it maps the IIe's internal ROM at $C300-$C3FF, turning SLOTC3ROM off.
;;
;; The internal page holds the 80-column firmware's entry points (<Firmware:BASICINT@Enhanced>,
;; <Firmware:BASICIN@Enhanced>, <Firmware:BASICOUT@Enhanced>), and running code there also maps the internal $C800
;; ROM. <SlotC3RomOn> maps slot 3's card instead; the reset code chooses between them by what it finds in slot 3.
;; See: <SlotC3RomOn>, <InternalCxRomOn>, <Firmware:BASICINT@Enhanced>
;; Also: SETINTC3ROM (IIETRM85)
SlotC3RomOff = $C00A

;; Writing it maps the ROM of the card in slot 3 at $C300-$C3FF, turning SLOTC3ROM on.
;;
;; It takes effect only while <InternalCxRomOff> maps the slots' ROMs. <SlotC3RomOff> maps the internal firmware
;; there again.
;; See: <SlotC3RomOff>, <InternalCxRomOff>
;; Also: SETSLOTC3ROM (IIEROM82, IIETRM85)
SlotC3RomOn = $C00B

;; Writing it turns 80COL off: the display shows 40 columns.
;;
;; <Columns80On> turns 80 columns on, and <Columns80State> reports the switch. The firmware writes it when it changes
;; to 40 columns.
;; See: <Columns80On>, <Columns80State>
;; Also: CLR80VID (IIEROM82, IIETRM85)
Columns80Off = $C00C

;; Writing it turns 80COL on: the display shows 80 columns, interleaving auxiliary and main memory.
;;
;; Each line's even columns come from auxiliary memory and its odd columns from main memory. The 80-column firmware
;; writes it when it starts and when it changes to 80 columns; <Columns80Off> turns it off, and <Columns80State>
;; reports it.
;; See: <Columns80Off>, <Columns80State>, <Store80On>
;; Also: SET80VID (IIEROM82, IIETRM85)
Columns80On = $C00D

;; Writing it turns ALTCHAR off: text shows the primary character set, with flashing characters.
;;
;; <AlternateCharactersOn> chooses the alternate set, and <AlternateCharactersState> reports the switch. The firmware
;; writes it when the 80-column firmware quits.
;; See: <AlternateCharactersOn>, <AlternateCharactersState>
;; Also: CLRALTCHAR (IIEROM82, IIETRM85)
AlternateCharactersOff = $C00E

;; Writing it turns ALTCHAR on: text shows the alternate character set, which has no flashing characters, with
;; lowercase in both normal and inverse.
;;
;; On the Enhanced IIe, the alternate set also holds the MouseText symbols. The 80-column firmware turns it on when
;; it starts, and <AlternateCharactersOff> turns it off; <AlternateCharactersState> reports it.
;; See: <AlternateCharactersOff>, <AlternateCharactersState>
;; Also: SETALTCHAR (IIEROM82, IIETRM85)
AlternateCharactersOn = $C00F

;; Reading or writing it clears the keyboard strobe, bit 7 of <Keyboard>; reading it reports in bit 7 whether a key
;; is down.
;;
;; <Monitor:KeyboardIn> clears the strobe after it takes a key, so the next read of <Keyboard> waits for a new one.
;; On all but the Apple II Monitor, <Monitor:Startup::Reset>, <Monitor:ScreenOutPausing> and
;; <Monitor:ScreenOutPausing::WaitForKey> clear it too.
;; See: <Keyboard>, <Monitor:KeyboardIn>, <Monitor:ScreenOutPausing::WaitForKey>
;; Also: KBDSTRB (A2RM78, A2RM79, IIEROM82, IIETRM85)
KeyboardStrobe = $C010

;; Reading it reports in bit 7 which language card bank is at $D000-$DFFF: 1 for bank 2, 0 for bank 1.
;;
;; The bank-switching reads (<LanguageCardRomWriteBank2>, <LanguageCardBank2ReadWrite>,
;; <LanguageCardBank1ReadWrite> and the rest) choose it. The Enhanced IIe's interrupt handler reads it to restore
;; the bank afterwards.
;; See: <LanguageCardRamState>, <LanguageCardBank1ReadWrite>, <LanguageCardBank2ReadWrite>
;; Also: RDLCBNK2 (IIEROM82, IIETRM85)
LanguageCardBank2State = $C011

;; Reading it reports in bit 7 whether $D000-$FFFF reads come from language card RAM (1) or ROM (0).
;;
;; The bank-switching reads (<LanguageCardRomWriteBank2>, <LanguageCardRomOnly>, <LanguageCardBank2ReadWrite>,
;; <LanguageCardBank1ReadWrite>) set it. The Enhanced IIe's interrupt handler reads it, with
;; <LanguageCardBank2State>, so that it can restore the language card.
;; See: <LanguageCardBank2State>, <LanguageCardRomWriteBank2>, <LanguageCardBank2ReadWrite>
;; Also: RDLCRAM (IIEROM82, IIETRM85)
LanguageCardRamState = $C012

;; Reading it reports in bit 7 whether RAMRD is on, reads of $0200-$BFFF coming from auxiliary memory.
;;
;; <AuxReadOn> turns it on and <AuxReadOff> off. <Firmware:AUXMOVE@Enhanced> and the Enhanced IIe's interrupt
;; handler read it.
;; See: <AuxReadOn>, <AuxReadOff>, <AuxWriteState>
;; Also: RDRAMRD (IIEROM82, IIETRM85)
AuxReadState = $C013

;; Reading it reports in bit 7 whether RAMWRT is on, writes to $0200-$BFFF going to auxiliary memory.
;;
;; <AuxWriteOn> turns it on and <AuxWriteOff> off. <Firmware:AUXMOVE@Enhanced> and the Enhanced IIe's interrupt
;; handler read it.
;; See: <AuxWriteOn>, <AuxWriteOff>, <AuxReadState>
;; Also: RDRAMWRT (IIEROM82, IIETRM85)
AuxWriteState = $C014

;; Reading it reports in bit 7 whether INTCXROM is on: 1 for the IIe's internal ROM at $C100-$CFFF, 0 for the
;; cards'.
;;
;; <Monitor:CallFirmware> pushes the state, through BIT and PHP, before it switches internal ROM in, and the
;; firmware's return pulls it to decide whether to switch slot ROM back (<Monitor:SelectSlotRom> on the Enhanced IIe,
;; <Monitor:SlotRomReturn> on the original). <InternalCxRomOff> and <InternalCxRomOn> set the switch. On the Enhanced
;; IIe, the interrupt handler, <Firmware:IRQHANDLER>, reads it first, so that it can restore the ROM the interrupted
;; program was using.
;; See: <InternalCxRomOff>, <InternalCxRomOn>, <Monitor:CallFirmware>
;; Also: RDCXROM (IIEROM82, IIETRM85)
InternalCxRomState = $C015

;; Reading it reports in bit 7 whether ALTZP is on: page zero, the stack and the language card area in auxiliary
;; memory.
;;
;; <AuxZeroPageOn> turns it on and <AuxZeroPageOff> off. The Enhanced IIe's interrupt handler reads it to switch to
;; the main stack.
;; See: <AuxZeroPageOn>, <AuxZeroPageOff>
;; Also: RDALTZP (IIETRM85)
AuxZeroPageState = $C016

;; Reading it reports in bit 7 whether SLOTC3ROM is on, slot 3's card ROM mapped at $C300-$C3FF.
;;
;; <SlotC3RomOn> turns it on and <SlotC3RomOff> off. The original IIe's self-test reads it to check that the switch
;; works.
;; See: <SlotC3RomOn>, <SlotC3RomOff>, <Firmware:SELFTEST@Original>
;; Also: RDC3ROM (IIETRM85)
SlotC3RomState = $C017

;; Reading it reports in bit 7 whether 80STORE is on.
;;
;; With 80STORE on, <Page2On> and <Page2Off> pick auxiliary or main memory for text page one instead of picking the
;; displayed page. <Store80Off> turns it off and <Store80On> on. The original IIe's
;; <Monitor:RestoreAfterFirmware> reads it to tell how to restore the page.
;; See: <Store80Off>, <Store80On>, <Page2State>, <Page2On>
;; Also: RD80STORE (IIEROM82, IIETRM85), RD80COL (IIEROM82, IIETRM85)
Store80State = $C018

;; Reading it reports in bit 7 whether the display is drawing the screen: 1 while it draws, 0 during vertical
;; blanking.
;;
;; The Enhanced IIe's self-test reads it between passes to vary its test patterns a little, since the time of each
;; pass against the display is not fixed.
;; See: <Firmware:SELFTEST@Enhanced>, <Firmware:RAMTEST@Enhanced>
;; Also: RDVBLBAR (IIEROM82, IIETRM85)
DrawingState = $C019

;; Reading it reports in bit 7 whether TEXT is on, the display showing only text.
;;
;; <TextOn> turns it on and <TextOff> off. When the 80-column firmware sets a full window, it reads it to start the
;; window at line 20, below the graphics, while graphics are shown.
;; See: <TextOn>, <TextOff>
;; Also: RDTEXT (IIEROM82, IIETRM85)
TextState = $C01A

;; Reading it reports in bit 7 whether MIXED is on, four lines of text below the graphics.
;;
;; <MixedOn> turns it on and <MixedOff> off. The original IIe's self-test reads it to check that the switch works.
;; See: <MixedOn>, <MixedOff>, <Firmware:SELFTEST@Original>
;; Also: RDMIXED (IIETRM85)
MixedState = $C01B

;; Reading it reports in bit 7 whether PAGE2 is on.
;;
;; <Page2Off> turns PAGE2 off and <Page2On> on. With 80STORE on, PAGE2 on means text page one is mapped to auxiliary
;; memory rather than page two being displayed. The original IIe's <Monitor:RestoreAfterFirmware> reads it to put
;; the page back.
;; See: <Page2Off>, <Page2On>, <Store80State>
;; Also: RDPAGE2 (IIEROM82, IIETRM85)
Page2State = $C01C

;; Reading it reports in bit 7 whether hi-res graphics are chosen, the HIRES switch on.
;;
;; <HiResOn> turns it on and <HiResOff> off. The original IIe's self-test reads it to check that the switch works.
;; See: <HiResOn>, <HiResOff>, <Firmware:SELFTEST@Original>
;; Also: RDHIRES (IIETRM85)
HiResState = $C01D

;; Reading it reports in bit 7 whether ALTCHAR is on, the alternate character set shown.
;;
;; <AlternateCharactersOn> turns it on and <AlternateCharactersOff> off. The Enhanced IIe's firmware reads it to
;; choose the screen codes it stores for inverse and normal characters, which differ between the two sets.
;; See: <AlternateCharactersOn>, <AlternateCharactersOff>
;; Also: RDALTCHAR (IIETRM85), ALTCHARSET (IIETRM85)
AlternateCharactersState = $C01E

;; Reading it reports in bit 7 whether the 80-column display, 80COL, is on.
;;
;; <Columns80On> turns it on and <Columns80Off> off. The Enhanced Monitor's <Monitor:ScreenOutByWidth> and
;; <Monitor:GetLine::NextCharacter> read it, and the internal firmware reads it throughout to choose its 40- or
;; 80-column code. The Technical Reference Manual's table of display switches calls this switch RD80COL, and
;; <Store80State> RD80STORE; its listings, like Apple's ROM listings, give RD80COL to <Store80State>.
;; See: <Columns80On>, <Columns80Off>
;; Also: RD80VID (IIEROM82, IIETRM85)
Columns80State = $C01F

;; Reading it toggles the cassette output.
;;
;; The cassette write routines, <Monitor:Cassette::WriteHeader> and <Monitor:WriteCassette>, toggle it at timed
;; intervals to write tones; each half cycle is one read. On the Enhanced IIe they are in the internal firmware
;; (<Firmware:TAPEHEADR>).
;; See: <CassetteIn>, <Monitor:Cassette::WriteHeader>, <Monitor:WriteCassette>
;; Also: TAPEOUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
CassetteOut = $C020

;; Reading it toggles the speaker, a click.
;;
;; <Monitor:RingBell> toggles it every 0.5 ms or so for about 0.1 seconds to ring the bell. Repeated toggles at a
;; steady rate make a tone.
;; See: <Monitor:RingBell>, <Monitor:Beep>
;; Also: SPKR (A2RM78, A2RM79, IIEROM82, IIETRM85)
Speaker = $C030

;; Reading or writing it turns TEXT off: the display shows graphics instead of text.
;;
;; <MixedOn> keeps four lines of text below the graphics, and <HiResOff> and <HiResOn> choose the kind.
;; <Monitor:SetGraphics> uses it for lo-res, and <TextOn> turns text back on.
;; See: <TextOn>, <MixedOn>, <HiResOff>, <Monitor:SetGraphics>, <TextState>
;; Also: TXTCLR (A2RM78, A2RM79, IIEROM82, IIETRM85)
TextOff = $C050

;; Reading or writing it turns TEXT on: the display shows text instead of graphics.
;;
;; <Monitor:SetText> and <Monitor:InitDisplay> use it. <TextOff> turns graphics back on, and <TextState> reports the
;; switch in bit 7. With 80COL on (<Columns80On>), the text is 80 columns wide.
;; See: <TextOff>, <Monitor:SetText>, <TextState>, <Columns80On>
;; Also: TXTSET (A2RM78, A2RM79, IIEROM82, IIETRM85)
TextOn = $C051

;; Reading or writing it turns MIXED off: the graphics fill the whole screen.
;;
;; It matters only while graphics are shown (<TextOff>). <MixedOn> keeps four lines of text below them, and
;; <MixedState> reports the switch. The original IIe's RAM test uses it to show memory as full-screen hi-res
;; graphics.
;; See: <MixedOn>, <MixedState>, <Firmware:RAMTEST@Original>
;; Also: MIXCLR (A2RM78, A2RM79, IIEROM82, IIETRM85)
MixedOff = $C052

;; Reading or writing it turns MIXED on: four lines of text show below the graphics.
;;
;; It matters only while graphics are shown (<TextOff>): the bottom four lines, 20-23, show text.
;; <Monitor:SetGraphics> uses it, and <MixedOff> turns it off for full-screen graphics.
;; See: <TextOff>, <Monitor:SetGraphics>, <MixedOff>
;; Also: MIXSET (A2RM78, A2RM79, IIEROM82, IIETRM85)
MixedOn = $C053

;; Reading or writing it turns PAGE2 off: page one is displayed, or main memory is used for text page one.
;;
;; With 80STORE off, it shows page one of text or graphics. With 80STORE on, it maps main memory at text page one
;; ($0400-$07FF), and at hi-res page one too while HIRES is on. <Monitor:InitDisplay> uses it, and <Page2State>
;; reports it.
;; See: <Page2On>, <Page2State>, <Store80State>
;; Also: LOWSCR (A2RM78, A2RM79, IIEROM82, IIETRM85), TXTPAGE1 (IIEROM82, IIETRM85)
Page2Off = $C054

;; Reading or writing it turns PAGE2 on: page two is displayed, or auxiliary memory is used for text page one.
;;
;; With 80STORE off, it shows page two of text or graphics. With 80STORE on, it maps auxiliary memory at text page
;; one ($0400-$07FF), and at hi-res page one too while HIRES is on: the 80-column firmware uses it to reach the even
;; columns. <Page2Off> turns it off, and <Page2State> reports it.
;; See: <Page2Off>, <Page2State>, <Store80State>
;; Also: HISCR (A2RM78, A2RM79, IIEROM82, IIETRM85), TXTPAGE2 (IIEROM82, IIETRM85)
Page2On = $C055

;; Reading or writing it turns HIRES off: graphics are shown in lo-res.
;;
;; It matters only while graphics are shown (<TextOff>). <Monitor:InitDisplay> uses it so that later graphics are
;; lo-res, and <HiResOn> chooses hi-res.
;; See: <TextOff>, <Monitor:InitDisplay>, <HiResOn>
;; Also: LORES (A2RM78, A2RM79, IIEROM82, IIETRM85)
HiResOff = $C056

;; Reading or writing it turns HIRES on: graphics are shown in hi-res.
;;
;; It matters only while graphics are shown (<TextOff>). With 80STORE on, it also lets PAGE2 choose main or
;; auxiliary memory at hi-res page one. <HiResOff> chooses lo-res, and <HiResState> reports the switch. The original
;; IIe's RAM test uses it to show memory as it tests it.
;; See: <HiResOff>, <HiResState>, <Firmware:RAMTEST@Original>
;; Also: HIRES (A2RM78, A2RM79, IIEROM82, IIETRM85)
HiResOn = $C057

;; Reading or writing it turns annunciator 0 off.
;;
;; The annunciators are four outputs on the game I/O connector; each has an off address and an on address, the next
;; one up, and none can be read back. <Monitor:Startup::Reset> turns annunciators 0 and 1 off.
;;
;; Apple's listings call this address SETAN0 and the next one, <Annunciator0On>, CLRAN0.
;; See: <Annunciator0On>, <Annunciator1Off>, <Monitor:Startup::Reset>
;; Also: SETAN0 (A2RM79, IIEROM82, IIETRM85)
Annunciator0Off = $C058

;; Reading or writing it turns annunciator 0 on.
;;
;; See: <Annunciator0Off>
;; Also: CLRAN0 (IIEROM82, IIETRM85)
Annunciator0On = $C059

;; Reading or writing it turns annunciator 1 off.
;;
;; <Annunciator1On>, the next address, turns it on. <Monitor:Startup::Reset> turns it off along with annunciator 0.
;; Apple's listings call this address SETAN1 and the next one CLRAN1.
;; See: <Annunciator1On>, <Annunciator0Off>, <Monitor:Startup::Reset>
;; Also: SETAN1 (A2RM79, IIEROM82, IIETRM85)
Annunciator1Off = $C05A

;; Reading or writing it turns annunciator 1 on.
;;
;; See: <Annunciator1Off>
;; Also: CLRAN1 (IIEROM82, IIETRM85)
Annunciator1On = $C05B

;; Reading or writing it turns annunciator 2 off.
;;
;; See: <Annunciator2On>
;; Also: SETAN2 (IIEROM82, IIETRM85)
Annunciator2Off = $C05C

;; Reading or writing it turns annunciator 2 on; <Annunciator2Off> turns it off.
;;
;; The Autostart Monitor's reset and the IIe firmware's reset function read it, along with <Annunciator3On>.
;; See: <Annunciator3On>, <Annunciator0Off>
;; Also: CLRAN2 (A2RM79, IIEROM82, IIETRM85)
Annunciator2On = $C05D

;; Reading or writing it turns annunciator 3 off.
;;
;; While IOUDIS is on, it turns double hi-res on instead.
;; See: <Annunciator3On>
;; Also: SETAN3 (IIEROM82, IIETRM85)
Annunciator3Off = $C05E

;; Reading or writing it turns annunciator 3 on; <Annunciator3Off> turns it off.
;;
;; While IOUDIS is on, the same addresses turn double hi-res off ($C05F) and on ($C05E) instead. The Autostart
;; Monitor's reset and the IIe firmware's reset function read it, along with <Annunciator2On>.
;; See: <Annunciator2On>, <Annunciator0Off>
;; Also: CLRAN3 (A2RM79, IIEROM82, IIETRM85)
Annunciator3On = $C05F

;; Reading it reports the cassette input in bit 7.
;;
;; The cassette read routine, <Monitor:ReadCassette>, times the changes of bit 7 to tell zeros from ones. On the
;; Enhanced IIe it is in the internal firmware (<Firmware:RDTAPE2BIT>).
;; See: <CassetteOut>, <Monitor:ReadCassette>
;; Also: TAPEIN (A2RM78, A2RM79, IIEROM82, IIETRM85)
CassetteIn = $C060

;; Reading it reports in bit 7 whether button 0, the Open Apple key, is down.
;;
;; At reset, with Open Apple down, the firmware writes over two bytes of each page of main RAM from $0200 to $BFFF, so
;; that a program in memory does not survive. With both Apple keys down at the end of the self-test, the test runs
;; again.
;; See: <Button1>, <Firmware:SELFTEST@Enhanced>
;; Also: BUTN0 (IIETRM85)
Button0 = $C061

;; Reading it reports in bit 7 whether button 1, the Solid Apple key, is down.
;;
;; At reset, with Solid Apple down, the firmware runs its self-test (<Firmware:SELFTEST@Enhanced>) instead of
;; starting up.
;; See: <Button0>, <Firmware:SELFTEST@Enhanced>
;; Also: BUTN1 (IIETRM85)
Button1 = $C062

;; Reading it reports in bit 7 whether paddle 0's timer is still running; <Paddle0> + n does paddle n, 0-3.
;;
;; Touching <PaddleTrigger> starts all four timers, setting bit 7, and each runs for a time that grows with its
;; paddle's position, up to about 3 milliseconds. <Monitor:ReadPaddle> counts until bit 7 clears.
;; See: <PaddleTrigger>, <Monitor:ReadPaddle>
;; Also: PADDL0 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Paddle0 = $C064

;; Reading or writing it starts the four paddle timers.
;;
;; Each paddle's bit 7, at <Paddle0> + n, then stays set for a time that grows with the paddle's position.
;; <Monitor:ReadPaddle> touches it, then counts.
;; See: <Paddle0>, <Monitor:ReadPaddle>
;; Also: PTRIG (A2RM78, A2RM79, IIEROM82, IIETRM85)
PaddleTrigger = $C070

; Language card switches.

;; Reading it maps language card RAM bank 2 at $D000-$FFFF for reading, with writes off.
;;
;; <LanguageCardBank2ReadWrite> also write-enables the bank when read twice, and <LanguageCardBank1ReadOnly> maps
;; bank 1. The original IIe's <Firmware:COPYROM> reads it to put back a bank 2 RAM it found selected.
;; See: <LanguageCardBank2ReadWrite>, <LanguageCardBank1ReadOnly>, <Firmware:COPYROM>, <LanguageCardRamState>
;; Also: LCRAM2 (UNKN)
LanguageCardBank2ReadOnly = $C080

;; Reading it maps ROM at $D000-$FFFF; reading it twice in a row also write-enables language card RAM bank 2.
;;
;; A single read, or a write, maps the ROM for reading without enabling writes. <LanguageCardRomOnly> maps the ROM
;; with writes off, and <LanguageCardRamState> reports which is read. The Enhanced IIe's interrupt handler selects it
;; so that the Monitor is in place.
;; See: <LanguageCardRomOnly>, <LanguageCardBank2ReadWrite>, <LanguageCardRamState>
;; Also: ROMIN (IIETRM85)
LanguageCardRomWriteBank2 = $C081

;; Reading it maps ROM at $D000-$FFFF and write-protects the language card RAM.
;;
;; <LanguageCardRomWriteBank2> maps the ROM while allowing writes to bank 2, and <LanguageCardRamState> reports
;; which is read. The original IIe's self-test reads it to put the ROM back.
;; See: <LanguageCardRomWriteBank2>, <LanguageCardBank2ReadWrite>, <LanguageCardRamState>
;; Also: LCROM (UNKN)
LanguageCardRomOnly = $C082

;; Reading it maps language card RAM bank 2 at $D000-$FFFF; reading it twice in a row also write-enables it.
;;
;; Bank 2 holds $D000-$DFFF and the RAM at $E000-$FFFF is shared by both banks. <LanguageCardBank1ReadWrite> maps
;; bank 1 instead, and <LanguageCardBank2State> and <LanguageCardRamState> report the choice.
;; See: <LanguageCardBank1ReadWrite>, <LanguageCardRomWriteBank2>, <LanguageCardBank2State>, <LanguageCardRamState>
;; Also: LCBANK2 (IIETRM85)
LanguageCardBank2ReadWrite = $C083

;; Reading it maps language card RAM bank 1 at $D000-$FFFF for reading, with writes off.
;;
;; <LanguageCardBank1ReadWrite> also write-enables the bank when read twice, and <LanguageCardBank2ReadOnly> maps
;; bank 2. The original IIe's <Firmware:COPYROM> reads it to put back a bank 1 RAM it found selected.
;; See: <LanguageCardBank1ReadWrite>, <LanguageCardBank2ReadOnly>, <Firmware:COPYROM>, <LanguageCardBank2State>
;; Also: LCRAM1 (UNKN)
LanguageCardBank1ReadOnly = $C088

;; Reading it maps ROM at $D000-$FFFF and selects bank 1; reading it twice in a row also write-enables bank 1.
;;
;; <LanguageCardRomWriteBank2> does the same with bank 2. The original IIe's <Firmware:COPYROM> reads it once to
;; put back ROM with bank 1 selected.
;; See: <LanguageCardRomWriteBank2>, <LanguageCardBank1ReadOnly>, <Firmware:COPYROM>
;; Also: ROMIN1 (UNKN)
LanguageCardRomWriteBank1 = $C089

;; Reading it maps language card RAM bank 1 at $D000-$FFFF; reading it twice in a row also write-enables it.
;;
;; Bank 1 holds $D000-$DFFF and the RAM at $E000-$FFFF is shared by both banks. <LanguageCardBank2ReadWrite> maps
;; bank 2 instead, and <LanguageCardBank2State> and <LanguageCardRamState> report the choice.
;; See: <LanguageCardBank2ReadWrite>, <LanguageCardBank2State>, <LanguageCardRamState>
;; Also: LCBANK1 (IIETRM85)
LanguageCardBank1ReadWrite = $C08B

; Characters, with bit 7 set as the keyboard and the output routines use them.

;; Control-B: the Monitor's command that starts `BASIC`, clearing its program (<Monitor:Commands::StartBasic>).
;; Also: KEY_CTRL_B (UNKN)
KEY_CONTROL_B = $82

;; Control-C: the Monitor's command that continues `BASIC` (<Monitor:Commands::ContinueBasic>).
;;
;; It is also left in the keyboard when it ends a Control-S pause, on all but the Apple II Monitor.
;; Also: KEY_CTRL_C (UNKN)
KEY_CONTROL_C = $83

;; Control-E: the Monitor's command that shows the registers.
;; Also: KEY_CTRL_E (UNKN)
KEY_CONTROL_E = $85

;; Control-G, the bell: printing it rings the bell.
KEY_BELL = $87

;; Control-H: backspace on output, and the left arrow key on input.
;; Also: KEY_BS (UNKN)
KEY_BACKSPACE = $88

;; Control-J: line feed on output, and the down arrow key on input.
;; Also: KEY_LF (UNKN)
KEY_LINE_FEED = $8A

;; Control-K: the up arrow key, the Monitor's IN# command, and, in the 80-column firmware's output, clear to the end
;; of the window.
;; Also: KEY_CTRL_K (UNKN)
KEY_CONTROL_K = $8B

;; Control-M, Return: the key that ends a line, and the carriage return on output.
;; Also: KEY_CR (UNKN)
KEY_RETURN = $8D

;; Control-P: the Monitor's command that sends output to a slot.
;; Also: KEY_CTRL_P (UNKN)
KEY_CONTROL_P = $90

;; Control-S: pauses output at the next carriage return until a key is typed, on all but the Apple II Monitor.
;; Also: KEY_CTRL_S (UNKN)
KEY_CONTROL_S = $93

;; Control-U, the right arrow key.
;; Also: KEY_RIGHT (UNKN)
KEY_RIGHT_ARROW = $95

;; Control-X: cancels an input line.
;; Also: KEY_CTRL_X (UNKN)
KEY_CONTROL_X = $98

;; Control-Y: the Monitor's command that jumps to the user's routine through <UserJump>.
;; Also: KEY_CTRL_Y (UNKN)
KEY_CONTROL_Y = $99

;; Escape: on input, starts escape mode, in which keys move the cursor.
;; Also: KEY_ESC (UNKN)
KEY_ESCAPE = $9B
