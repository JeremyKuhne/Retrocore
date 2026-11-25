; retrocore: style=strict
;; Programmer's Aid #1: the Apple II addresses it uses
;;
;; The Monitor routines, page-zero locations and Integer BASIC entry points and variables that Programmer's Aid's
;; routines use but do not own. Apple assembled each routine on its own, each with its own equates; here each address
;; is defined once, and each routine's name for it is a historical name of the definition.
;;
;; The locations and routines Programmer's Aid shares with the Apple II's other sources come from
;; ../System/IIeEquates.asm and ../System/MonitorEntries.asm, which this file includes; the page-zero locations and soft
;; switches are the same on the II as on the IIe. The definitions here are the Monitor routines MonitorEntries.asm does
;; not export and Integer BASIC's addresses, under Integer BASIC's names, with Programmer's Aid's names for them as
;; historical names (the conversion log, docs/conversions/ProgrammersAid.md).

.include "../System/IIeEquates.asm"
.include "../System/MonitorEntries.asm"

; The Monitor's routines that MonitorEntries.asm does not export.

;; Inherit: <Monitor:CharacterOut>
;; Also: COUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
CharacterOut = $FDED

;; Inherit: <Monitor:PrintHexByte>
;; Also: PRBYTE (A2RM78, A2RM79, IIEROM82, IIETRM85)
PrintHexByte = $FDDA

;; Inherit: <Monitor:PrintAddress>
;; Also: PRA1 (A2RM78, A2RM79, IIEROM82)
PrintAddress = $FD92

;; Inherit: <Monitor:Beep>
;; Also: BELL (A2RM78, A2RM79, IIEROM82, IIETRM85)
Beep = $FF3A

;; Inherit: <Monitor:NextInRangeAndTarget>
;; Also: NXTA4 (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextInRangeAndTarget = $FCB4

;; Inherit: <Monitor:Disassembler::Decode::Opcode>
;; At $F88E. Relocate calls it to learn each instruction's length.
;; Also: INSDS2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
DecodeOpcode = $F88E

;; Inherit: <Monitor:ReadCassette>
;; Also: READ (A2RM78, A2RM79, IIEROM82, IIETRM85)
ReadCassette = $FEFD

;; The Monitor's <ReadCassette> from its wait for the header on: waits out the header tone as <Cassette::WriteHeader>
;; does for A and the carry, then reads the bytes from A1 to A2 and checks them, as <ReadCassette> does.
;;
;; At $FF02, where <ReadCassette> calls <Cassette::WriteHeader> as its delay; <ReadCassette> passes $16 there, and a
;; caller that has already waited for the tone can pass less.
;; In: A = the wait in rounds of 256 half cycles: A + 1 rounds with carry set, A with carry clear (one round for A = 0
;;   or 1), X = the first round's half cycles (0 for 256), Address1/Address1High = the first address,
;;   Address2/Address2High = the last
;; Also: READX1 (PA1)
ReadCassetteFromHeader = $FF02

;; The end of the Monitor's <ReadCassette>: reads the checksum byte from the tape, then beeps if it matches the checksum
;; kept in <PlotMask>'s byte, or prints ERR and beeps if it does not.
;;
;; At $FF26.
;; In: PlotMask = the checksum of the bytes read
;; Also: FINISH (PA1)
ReadCassetteChecksum = $FF26

;; The Monitor's cassette routines Programmer's Aid calls, under the scope the Monitor gives them.
.scope Cassette

;; Inherit: <Monitor:Cassette::WriteHeader>
;; Also: HEADR (A2RM78, A2RM79, IIEROM82, IIETRM85)
WriteHeader = $FCC9

;; Inherit: <Monitor:Cassette::ReadByte>
;; Also: RDBYTE (A2RM78, A2RM79, IIEROM82)
ReadByte = $FCEC

;; Inherit: <Monitor:Cassette::ReadBit>
;; Also: RD2BIT (A2RM78, A2RM79, IIEROM82)
ReadBit = $FCFA

;; Inherit: <Monitor:Cassette::ReadHalfCycle>
;; Also: RDBIT (A2RM78, A2RM79, IIEROM82)
ReadHalfCycle = $FCFD

.endscope

; Integer BASIC's page zero.

;; Inherit: <IntegerBasic:LowMemory>
;; Also: LOMEM (IBSM), LOMEML (PA1)
LowMemory = $4A

;; The high byte of <LowMemory>.
;; Also: LOMEMH (PA1)
LowMemoryHigh = LowMemory + 1

;; Inherit: <IntegerBasic:HighMemory>
;; Also: HIMEM (IBSM, PA1)
HighMemory = $4C

;; Inherit: <IntegerBasic:NounStackLow>
;; Also: NOUNSTKL (IBSM)
NounStackLow = $50

;; Inherit: <IntegerBasic:ProgramStart>
;; Also: PP (IBSM, PA1), PPL (PA1)
ProgramStart = $CA

;; The high byte of <ProgramStart>.
;; Also: PPH (PA1)
ProgramStartHigh = ProgramStart + 1

;; Inherit: <IntegerBasic:VariablesEnd>
;; Also: PV (IBSM), PVL (PA1)
VariablesEnd = $CC

;; The high byte of <VariablesEnd>.
;; Also: PVH (PA1)
VariablesEndHigh = VariablesEnd + 1

;; Inherit: <IntegerBasic:Accumulator>
;; Integer BASIC leaves a noun's value here, and its cassette routines a program's length. Its old name ACC is given in
;; prose, as here it would clash with the Monitor's ACC, <SavedA>.
;; Also: ACL (PA1)
Accumulator = $CE

;; The high byte of <Accumulator>.
;; Also: ACH (PA1)
AccumulatorHigh = Accumulator + 1

;; Inherit: <IntegerBasic:SavedX>
;; Integer BASIC's own name for it here is the Monitor's, <SavedX>.
;; Also: XSAVE (IBSM, PA1)
BasicSavedX = $D8

; Integer BASIC's routines.

;; Inherit: <IntegerBasic:MemoryFullError>
;; Also: MEMFULL (IBSM, PA1), MEMFUL (PA1)
MemoryFullError = $E36B

;; Inherit: <IntegerBasic:PrintDecimal>
;; Also: PRDEC (IBSM, PA1)
PrintDecimal = $E51B

;; Inherit: <IntegerBasic:RangeError>
;; Also: RANGERR (IBSM, PA1), RNGERR (PA1)
RangeError = $EE68

;; Integer BASIC's statements Programmer's Aid calls, under the scope Integer BASIC gives them.
.scope Statements

;; Inherit: <IntegerBasic:Statements::Load>
;; Also: LOAD (IBSM, PA1)
Load = $F0DF

.endscope

; Cassette: Integer BASIC's cassette setups, beside the Monitor's routines above, as Integer BASIC's scope of that
; name holds them.
.scope Cassette continued

;; Inherit: <IntegerBasic:Cassette::PointAtLength>
;; Also: SETHDR (IBSM), HDRSET (PA1), ACADR (PA1)
PointAtLength = $F11E

;; Inherit: <IntegerBasic:Cassette::PointAtProgram>
;; Also: SETPRG (IBSM), PRGSET (PA1)
PointAtProgram = $F12C

.endscope

;; SWEET16, the 16-bit interpreter in Integer BASIC's ROM, under the scope Integer BASIC gives it.
.scope Sweet16

;; Inherit: <IntegerBasic:Sweet16::Run>
;; Also: SW16 (A2RM78, PA1)
Run = $F689

.endscope
