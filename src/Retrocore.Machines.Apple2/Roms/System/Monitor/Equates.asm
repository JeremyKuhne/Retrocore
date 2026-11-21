; retrocore: style=strict
;; The Monitor's own names for page zero, the entries it calls in the internal firmware and the language ROMs, and
;; the page zero the Apple II Monitor's step and arithmetic routines use.

; Page zero not in IIeEquates.asm, because DOS has names of its own spelled the same. The firmware inherits these.

;; The high byte of the pointer at <SlotPointer>.
;;
;; <Startup::PowerUp> counts it down from $C7 to $C1 as it tries each slot. On the Enhanced IIe, the interrupt return
;; code in the bytes the original IIe's <RestoreAfterFirmware> uses points it briefly at a slot's $Cn00 page to select
;; that slot's $C800 ROM, then restores it.
;; See: <SlotPointer>, <ExpansionRomSlot>
LOC1 = $01

;; The cursor's line on the screen, 0-23.
;;
;; It counts from the top of the screen, not of the window. <VerticalTabTo>, <CursorUp> and <LineFeed> change it, and
;; <VerticalTab> sets <TextBase>/<TextBaseHigh> for it. The 80-column firmware keeps a copy in
;; <Firmware:EightyColumns::CursorLine>.
;; See: <CursorColumn>, <TextBase>, <WindowTop>, <WindowBottom>, <VerticalTab>
CV = $25

; The internal firmware's entries, and the expansion ROM switch, a label in the Enhanced IIe's firmware. Each is named
; for what the firmware does there, the name its routine there takes when the firmware is converted.

;; The internal firmware's dispatcher, which runs the function whose number is in Y; the original IIe's
;; <CallFirmware> jumps here.
;; Also: B_FUNC (IIEROM82, IIETRM85)
DispatchFunction = $C100

;; Slot 3's input entry in the internal firmware's 80-column code; <CompareSlot3Rom> compares its bytes.
;; Also: BASICIN (IIEROM82, IIETRM85)
BasicInput = $C305

;; The Enhanced IIe firmware's interrupt handler, which the Enhanced IIe's interrupt vector points to.
;;
;; Apple's listing calls it IRQ, a name left out of Also: because <Interrupt> has it.
;; Also: IRQHANDLER (UNKN)
HandleInterrupt = $C3FA

;; Where the Enhanced IIe firmware's interrupt code goes on once the Monitor has selected the interrupted slot's
;; $C800 ROM again.
;; Also: IRQRESTORE (UNKN), IRQFIX (IIETRM85)
RestoreInterruptedState = $C47C

;; The Enhanced IIe firmware's cassette header routine, which the Monitor's <Cassette::WriteHeader> stub calls.
;; Also: TAPEHEADR (UNKN), XHEADER (IIETRM85)
WriteCassetteHeader = $C567

;; The Enhanced IIe firmware's cassette write, which the Monitor's W command (<WriteCassette>) calls.
;; Also: WRITETAPE (UNKN), WRITE2 (IIETRM85)
WriteCassetteData = $C5AA

;; The Enhanced IIe firmware's cassette read, which the Monitor's R command (<ReadCassette>) calls.
;; Also: READTAPE (UNKN), XREAD (IIETRM85)
ReadCassetteData = $C5D1

;; The Enhanced IIe firmware's mini-assembler, which assembles each line read at its "!" prompt.
;; Also: MINILINE (UNKN), DOINST (IIETRM85)
AssembleLine = $CF9C

;; Releases the $C800 expansion ROM: reading or writing it deselects every slot's.
;; Also: CLRROM (A2RM79, IIEROM82, IIETRM85)
ExpansionRomOff = $CFFF

; BASIC's entries.

;; BASIC's cold start: Integer BASIC's or AppleSoft's, whichever the ROMs hold.
;; Also: BASIC (A2RM78, A2RM79, IIEROM82, IIETRM85)
BasicColdStart = $E000

;; The warm start of the language in ROM, <BasicColdStart>'s second entry: it keeps the program in memory.
;; Also: BASIC2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
BasicWarmStart = $E003
