; retrocore: style=strict
;; The Apple IIe Monitor's entry points, for the sources that call the Monitor
;;
;; The Monitor's routines and tables that the internal firmware of both models and the other ROM sources and DOS use,
;; as equates at their addresses in the Monitor, with the Monitor's names. Monitor.asm defines and documents each of
;; them as a label, so it does not include this file; the others do, and each definition here inherits the Monitor's
;; documentation and repeats its historical names, so code written with Apple's names assembles. A few are in only
;; one model's Monitor, and only that model's firmware uses them: <RestoreAfterFirmware> and <SlotRomReturn> in the
;; original IIe's, <SelectSlotRom> and <SkipBlanks> in the Enhanced IIe's. The name Apple's listings give both
;; models' returns from the firmware, at different addresses, is left out here, since the two would clash.
;;
;; Two labels inside Monitor routines are here in scopes of the routines' names, so that the callers write them as
;; the Monitor's own code does: <SetPcFromA1::Loop> and <SaveRegisters::Return>.
;;
;; Two of the Monitor's names are not here. <GETNUM at Monitor:ReadHexNumber> is also the name of a routine of DOS's
;; own, so the Enhanced IIe's firmware defines the Monitor's itself. DOS names $F88E, the Monitor's
;; <Monitor:Disassembler::Decode::Opcode>, with the name the Monitor's listings give $F88C, so DOS defines it.

;; Inherit: <Monitor:PrintThreeBlanks>
;; Also: PRBLNK (A2RM78, A2RM79, IIEROM82, IIETRM85)
PrintThreeBlanks = $F948

;; Inherit: <Monitor:FormatCharacter1>
;; Also: CHAR1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
FormatCharacter1 = $F9B4

;; Inherit: <Monitor:FormatCharacter2>
;; Also: CHAR2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
FormatCharacter2 = $F9BA

;; Inherit: <Monitor:MnemonicsLeft>
;; Also: MNEML (A2RM78, A2RM79, IIEROM82, IIETRM85)
MnemonicsLeft = $F9C0

;; Inherit: <Monitor:MnemonicsRight>
;; Also: MNEMR (A2RM78, A2RM79, IIEROM82, IIETRM85)
MnemonicsRight = $FA00

;; Inherit: <Monitor:InitDisplay>
;; Also: INIT (A2RM78, A2RM79, IIEROM82, IIETRM85)
InitDisplay = $FB2F

;; Inherit: <Monitor:ModelId>
;; Also: VERSION (A2RM78, IIEROM82, IIETRM85), F8VERSION (IIEROM82, IIETRM85)
ModelId = $FBB3

;; Inherit: <Monitor:CursorUp>
;; Also: UP (A2RM78, A2RM79, IIEROM82, IIETRM85)
CursorUp = $FC1A

;; Inherit: <Monitor:VerticalTab>
;; Also: VTAB (A2RM78, A2RM79, IIEROM82, IIETRM85)
VerticalTab = $FC22

;; Inherit: <Monitor:SetLineBase>
;; Also: VTABZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetLineBase = $FC24

;; Inherit: <Monitor:Home>
;; Also: HOME (A2RM78, A2RM79, IIEROM82, IIETRM85)
Home = $FC58

;; Inherit: <Monitor:RestoreAfterFirmware>
;; Also: VIDSYNC (UNKN), SNIFFIRQ (IIEROM82)
RestoreAfterFirmware = $FC75

;; Inherit: <Monitor:Delay>
;; Also: WAIT (A2RM78, A2RM79, IIEROM82, IIETRM85)
Delay = $FCA8

;; Inherit: <Monitor:NextInRange>
;; Also: NXTA1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextInRange = $FCBA

;; Inherit: <Monitor:KeyboardIn>
;; Also: KEYIN (A2RM78, A2RM79, IIEROM82, IIETRM85)
KeyboardIn = $FD1B

;; Inherit: <Monitor:SlotRomReturn>
;; Also: SLOTRTN (UNKN)
SlotRomReturn = $FD29

;; Inherit: <Monitor:PrintReturn>
;; Also: CROUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
PrintReturn = $FD8E

;; Inherit: <Monitor:PrintHexDigit>
;; Also: PRHEX (A2RM78, A2RM79, IIEROM82, IIETRM85)
PrintHexDigit = $FDE3

;; Inherit: <Monitor:ScreenOut>
;; Also: COUT1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
ScreenOut = $FDF0

;; The label inside the Monitor's <Monitor:SetPcFromA1>, which copies A1 to PC, that other sources call.
.scope SetPcFromA1

;; Inherit: <Monitor:SetPcFromA1::Loop>
;; Also: A1PCLP (A2RM78, IIEROM82)
Loop = $FE78

.endscope

;; Inherit: <Monitor:SetKeyboard>
;; Also: SETKBD (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetKeyboard = $FE89

;; Inherit: <Monitor:SetScreen>
;; Also: SETVID (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetScreen = $FE93

;; Inherit: <Monitor:SelectSlotRom>
;; Also: SLOTRTS (UNKN), RETCX1 (IIETRM85)
SelectSlotRom = $FEC5

;; Inherit: <Monitor:SkipBlanks>
;; Also: SKIPBLNK (UNKN), NNBL (IIETRM85)
SkipBlanks = $FF13

;; Inherit: <Monitor:PrintError>
;; Also: PRERR (A2RM78, A2RM79, IIEROM82, IIETRM85)
PrintError = $FF2D

;; The label inside the Monitor's <Monitor:SaveRegisters>, which saves the registers, that other sources call.
.scope SaveRegisters

;; Inherit: <Monitor:SaveRegisters::Return>
;; Also: IORTS (IIEROM82)
Return = $FF58

.endscope

;; Inherit: <Monitor:ClearMode>
;; Also: ZMODE (A2RM78, A2RM79, IIEROM82, IIETRM85)
ClearMode = $FFC7
