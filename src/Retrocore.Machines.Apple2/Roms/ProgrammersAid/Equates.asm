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
;; not export and Integer BASIC's addresses. Integer BASIC's keep the names its source gives them, or Programmer's Aid's
;; where it has none, until that source is converted (the conversion log, docs/conversions/ProgrammersAid.md),
;; with Programmer's Aid's other names for them as historical names.

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
;; In: A = the wait, in rounds of 256 half cycles, carry = set (clear makes it one round fewer),
;;   Address1/Address1High = the first address, Address2/Address2High = the last
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

;; Inherit: <IntegerBasic:LOMEM>
;; Also: LOMEML (PA1)
LOMEM = $4A

;; The high byte of <LOMEM>.
LOMEMH = LOMEM + 1

;; Inherit: <IntegerBasic:HIMEM>
HIMEM = $4C

;; Inherit: <IntegerBasic:NOUNSTKL>
NOUNSTKL = $50

;; Inherit: <IntegerBasic:PP>
;; Also: PPL (PA1)
PP = $CA

;; The high byte of <PP>.
PPH = PP + 1

;; Inherit: <IntegerBasic:PV>
;; Also: PVL (PA1)
PV = $CC

;; The high byte of <PV>.
PVH = PV + 1

;; Integer BASIC's main accumulator (2 bytes, low byte first), where its cassette routines keep a program's length.
;;
;; Integer BASIC's source calls it ACC, which here would clash with the Monitor's ACC, <SavedA>; this is Programmer's
;; Aid's name for it.
;; See: <IntegerBasic:ACC>
ACL = $CE

;; The high byte of <ACL>.
ACH = ACL + 1

;; Inherit: <IntegerBasic:XSAVE>
XSAVE = $D8

; Integer BASIC's routines.

;; Inherit: <IntegerBasic:MEMFULL>
;; Also: MEMFUL (PA1)
MEMFULL = $E36B

;; Inherit: <IntegerBasic:PRDEC>
PRDEC = $E51B

;; Inherit: <IntegerBasic:RANGERR>
;; Also: RNGERR (PA1)
RANGERR = $EE68

;; Inherit: <IntegerBasic:LOAD>
LOAD = $F0DF

;; Inherit: <IntegerBasic:SETHDR>
;; Also: HDRSET (PA1), ACADR (PA1)
SETHDR = $F11E

;; Inherit: <IntegerBasic:SETPRG>
;; Also: PRGSET (PA1)
SETPRG = $F12C

;; Inherit: <IntegerBasic:SW16>
SW16 = $F689
