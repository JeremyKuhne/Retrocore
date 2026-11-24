; retrocore: style=strict
;; APPLE IIE INTERNAL FIRMWARE ($C100-$CFFF), ENHANCED IIE
;;
;; The Enhanced IIe's internal $C100-$CFFF ROM, which assembles byte-identically from these files, in address order:
;;
;; - Firmware.Enhanced/Functions.asm, $C100-$C2FF: the screen and keyboard functions the Monitor calls through
;;   <Monitor:CallFirmware>, with the internal ROM switched in and a function number in Y (FirmwareFunctions.asm),
;;   performed by <DispatchFunction>; every function returns through <Functions::Return>. Also the reset hook,
;;   <Functions::ResetFirmware>.
;; - Firmware.Enhanced/SlotEntry.asm, $C300-$C3FF: slot 3's entry points, <BasicInitialize> (`PR#3`), <BasicInput>
;;   and <BasicOutput>; the Pascal 1.1 signature and <PascalOffsets>; <AuxMove> and <AuxTransfer>; and
;;   <HandleInterrupt> at $C3FA, where the IRQ vector at $FFFE points.
;; - Firmware.Enhanced/Interrupts.asm, $C400-$C5FF: the interrupt handling that saves and restores the memory
;;   state, the mini-assembler's operand parser, and the cassette routines behind the Monitor's tape commands and
;;   AppleSoft's `SHLOAD`, `STORE` and `RECALL` (<AppleSoftCassette>).
;; - Firmware.Enhanced/SelfTest.asm, $C600-$C7FF: the built-in self-test, which the reset function runs when
;;   Solid-Apple is held.
;; - Firmware.Enhanced/EightyColumnsEntry.asm, EightyColumnsControl.asm, EightyColumnsScreen.asm and
;;   EightyColumnsMode.asm, $C800-$CFFF: the 80-column firmware: Pascal 1.0's hooks at $C800, $C84D and $C9AA, BASIC's
;;   output and input with the escape sequences, the control characters, Pascal's protocol, the 40/80-column
;;   conversion, the screen access through 80STORE, and the rest of the mini-assembler (<AssembleLine>).
;;
;; The 80-column firmware keeps its state in slot 3's screen holes (<EightyColumns>), with the mode bits
;; FirmwareEquates.asm names. Several routines are reached only through computed RTS addresses, from the tables of
;; <DispatchFunction> and <Control::Perform>. The files include IIeEquates.asm (the IIe's page zero, soft switches
;; and keys), MonitorEntries.asm (the Monitor's entry points), FirmwareEquates.asm (the equates both firmware models
;; share) and FirmwareFunctions.asm (the function numbers).
;;
;; Maintained by hand. The SystemSourceTests digests check that it assembles byte-identically.

.cpu Rockwell65C02

; Apple II text has bit 7 set, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

; The model, on which FirmwareEquates.asm's mode bits and FirmwareFunctions.asm's function numbers depend: the SDK
; predefines ENHANCED, and this is the default.
.ifndef ENHANCED
ENHANCED = 1
.endif
.assert ENHANCED, "Firmware.Enhanced.asm is the Enhanced IIe's firmware."

; The IIe's page zero, soft switches and keys, the Monitor's entry points, and the equates both firmware models share.
.include "IIeEquates.asm"
.include "MonitorEntries.asm"
.include "FirmwareEquates.asm"

; The firmware's function numbers, which depend on the model.
.include "FirmwareFunctions.asm"

; AppleSoft's page zero, for the cassette and `SHLOAD`/`STORE`/`RECALL` helpers: AppleSoft's names, until AppleSoft is
; converted.

;; Applesoft's line number, which the cassette helper borrows for a length: of a shape table, or of an array.
;;
;; <AppleSoftCassette> reads a shape table's two-byte length from the tape into <LINNUM>/<LINNUM>+1 for `SHLOAD`, and
;; <AppleSoftCassette::ArrayBlock> adds an array's length, which Applesoft leaves here, to its address for `STORE` and
;; `RECALL`.
;; See: <AppleSoft:LINNUM>, <AppleSoftCassette>, <AppleSoftCassette::ArrayBlock>
LINNUM = $50

;; Applesoft's end of the variables and arrays, the lowest address strings may grow down to.
;;
;; <AppleSoftCassette> refuses a shape table that would reach below it, returning carry set so that Applesoft reports
;; that memory is full.
;; See: <AppleSoft:STREND>, <AppleSoftCassette>, <MEMSIZ>
STREND = $6D

;; Applesoft's bottom of string space, where the next string is stored, just below the strings in use.
;;
;; <AppleSoftCassette::ShapeTable> moves it down with HIMEM, <MEMSIZ>, to make room for the shape table it loads.
;; See: <AppleSoft:FRETOP>, <MEMSIZ>, <AppleSoftCassette::ShapeTable>
FRETOP = $6F

;; Applesoft's HIMEM, the address just above the memory it uses.
;;
;; <AppleSoftCassette> checks that a shape table fits below it, and <AppleSoftCassette::ShapeTable> lowers it by the
;; table's length and loads the table there.
;; See: <AppleSoft:MEMSIZ>, <FRETOP>, <SHPTBL>, <AppleSoftCassette::ShapeTable>
MEMSIZ = $73

;; Applesoft's block pointer, which the `STORE` and `RECALL` helper takes as the start of the array's data.
;;
;; <AppleSoftCassette::ArrayBlock> copies it, as Applesoft's routine at $E0EF leaves it, to <A1L>/<A1H>, the start of
;; the block the Monitor then writes or reads.
;; See: <AppleSoft:HIGHDS>, <AppleSoftCassette::ArrayBlock>, <LOWTR>
HIGHDS = $94

;; Applesoft's pointer to the array that `STORE` or `RECALL` names, from its search for the array.
;;
;; <AppleSoftCassette::ArrayBlock> adds the array's length in <LINNUM> to it for <A2L>/<A2H>, the end of the block on
;; tape, and reads the header's fifth byte through it.
;; See: <AppleSoft:LOWTR>, <AppleSoftCassette::ArrayBlock>, <HIGHDS>
LOWTR = $9B

;; Applesoft's pointer to the shape table that `DRAW` and `XDRAW` use.
;;
;; <AppleSoftCassette::ShapeTable> sets it to the address where it loads the shape table, just below the new HIMEM.
;; See: <AppleSoft:SHPTBL>, <AppleSoftCassette::ShapeTable>, <MEMSIZ>
;; Also: SHAPEPTR (UNKN)
SHPTBL = $E8

; A Monitor entry point not in MonitorEntries.asm, since DOS has a routine of its own by its old name, GETNUM.

;; Inherit: <Monitor:ReadHexNumber>
ReadHexNumber = $FFA7

.org $C100

.include "Firmware.Enhanced/Functions.asm"
.include "Firmware.Enhanced/SlotEntry.asm"
.include "Firmware.Enhanced/Interrupts.asm"
.include "Firmware.Enhanced/SelfTest.asm"
.include "Firmware.Enhanced/EightyColumnsEntry.asm"
.include "Firmware.Enhanced/EightyColumnsControl.asm"
.include "Firmware.Enhanced/EightyColumnsScreen.asm"
.include "Firmware.Enhanced/EightyColumnsMode.asm"
