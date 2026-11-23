; retrocore: style=strict
;; The Monitor's own names for page zero and the entries it calls in the internal firmware and the language ROMs:
;; locations only, the values several of its files use being in Monitor.asm. The page zero the Apple II Monitor's
;; step and arithmetic routines use is in their scopes.

; Page zero not in IIeEquates.asm, because DOS has names of its own spelled the same. The firmware inherits these.

;; The high byte of the pointer at <LOC0>.
;;
;; <Startup::PowerUp> counts it down from $C7 to $C1 as it tries each slot. On the Enhanced IIe, the interrupt return
;; code in the bytes the original IIe's <RestoreAfterFirmware> uses points it briefly at a slot's $Cn00 page to select
;; that slot's $C800 ROM, then restores it.
;; See: <LOC0>, <MSLOT>
LOC1 = $01

;; The cursor's line on the screen, 0-23.
;;
;; It counts from the top of the screen, not of the window. <VerticalTabTo>, <CursorUp> and <LineFeed> change it, and
;; <VerticalTab> sets <BASL>/<BASH> for it. The 80-column firmware keeps a copy in <Firmware:OURCV>.
;; See: <CH>, <BASL>, <WNDTOP>, <WNDBTM>, <VerticalTab>
CV = $25

; The internal firmware's entries, and CLRROM, a label in the Enhanced IIe's firmware.

;; The internal firmware's dispatcher, which runs the function whose number is in Y; both IIe models' <CallFirmware>
;; jump here.
B_FUNC = $C100

;; Slot 3's input entry in the internal firmware's 80-column code; <CompareSlot3Rom> compares its bytes.
BASICIN = $C305

;; The Enhanced IIe firmware's interrupt handler, which the Enhanced IIe's interrupt vector points to.
IRQHANDLER = $C3FA

;; Where the Enhanced IIe firmware's interrupt code goes on once the Monitor has selected the interrupted slot's
;; $C800 ROM again.
IRQRESTORE = $C47C

;; The Enhanced IIe firmware's cassette header routine, which the Monitor's <Cassette::WriteHeader> stub calls.
TAPEHEADR = $C567

;; The Enhanced IIe firmware's cassette write, which the Monitor's W command (<WriteCassette>) calls.
WRITETAPE = $C5AA

;; The Enhanced IIe firmware's cassette read, which the Monitor's R command (<ReadCassette>) calls.
READTAPE = $C5D1

;; The Enhanced IIe firmware's mini-assembler, which assembles each line read at its "!" prompt.
MINILINE = $CF9C

;; Releases the $C800 expansion ROM: reading or writing it deselects every slot's.
CLRROM = $CFFF

; BASIC's entries.

;; BASIC's cold start: Integer BASIC's or AppleSoft's, whichever the ROMs hold.
;; Also: BASIC (A2RM78, A2RM79, IIEROM82, IIETRM85)
BasicColdStart = $E000

;; The warm start of the language in ROM, <BasicColdStart>'s second entry: it keeps the program in memory.
;; Also: BASIC2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
BasicWarmStart = $E003
