; retrocore: style=strict
;; APPLE IIE INTERNAL FIRMWARE ($C100-$CFFF), ORIGINAL IIE
;;
;; The original IIe's internal $C100-$CFFF ROM, which assembles byte-identically from these files, in address order:
;;
;; - Firmware.Original/Functions.asm, $C100-$C2FF: the screen and keyboard functions the Monitor calls through
;;   <Monitor:CallFirmware>, with the internal ROM switched in and a function number in Y (FirmwareFunctions.asm):
;;   0 clear to the end of the window, 1 home, 2 scroll, 3 clear to the end of the line, 4 the same from a column,
;;   5 reset, 6 read a key with the cursor, 7 translate an escape key, 8 set the window. Functions 0-5 and 8 have a
;;   40-column and an 80-column handler; every function returns through <Functions::Return>, but the reset when it
;;   starts the self-test.
;; - Firmware.Original/SlotEntry.asm, $C300-$C3FF: slot 3's entry points, <BasicInitialize> (`PR#3`), <BasicInput>
;;   and <BasicOutput>; the Pascal 1.1 signature and <PascalOffsets>; <AuxMove> and <AuxTransfer>.
;; - Firmware.Original/SelfTest.asm, $C400-$C7FF: the built-in self-test, which the reset function runs when
;;   Solid-Apple is held.
;; - Firmware.Original/EightyColumnsEntry.asm, EightyColumnsControl.asm, EightyColumnsScreen.asm and
;;   EightyColumnsMode.asm, $C800-$CFFF: the 80-column firmware: BASIC's output and input with the escape keys, the
;;   control characters, Pascal's protocol, the 40/80-column conversion, and the screen access through 80STORE.
;;
;; The 80-column firmware keeps its state in slot 3's screen holes (<EightyColumns>), with the mode bits
;; FirmwareEquates.asm names, and uses <FirmwareScratch> as scratch. The files include IIeEquates.asm (the IIe's
;; page zero, soft switches and keys), MonitorEntries.asm (the Monitor's entry points), FirmwareEquates.asm (the
;; equates both firmware models share) and FirmwareFunctions.asm (the function numbers).
;;
;; Maintained by hand. The SystemSourceTests digests check that it assembles byte-identically.

.cpu Mos6502

; Apple II text has bit 7 set, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

; The model, on which FirmwareEquates.asm's mode bits and FirmwareFunctions.asm's function numbers depend: the SDK
; predefines ENHANCED, and this is the default.
.ifndef ENHANCED
ENHANCED = 0
.endif
.assert .not ENHANCED, "Firmware.Original.asm is the original IIe's firmware."

; The IIe's page zero, soft switches and keys, the Monitor's entry points, and the equates both firmware models share.
.include "IIeEquates.asm"
.include "MonitorEntries.asm"
.include "FirmwareEquates.asm"

; The firmware's function numbers, which depend on the model.
.include "FirmwareFunctions.asm"

; A screen hole only this model's firmware uses.

;; Slot 0's screen hole, which the original IIe's 80-column firmware uses as scratch: the status that says whether the
;; internal ROM was in before a function's call (<Functions::Prepare80>), the character under the cursor
;; (<Functions::GetKey>), and the code <Control::Perform> performs.
;; Also: TEMP1 (IIEROM82)
FirmwareScratch = $0478

; The expansion ROM switch, a label in the Enhanced IIe's firmware, so not in IIeEquates.asm.

;; Inherit: <Monitor:ExpansionRomOff>
;; Also: CLRROM (A2RM79, IIEROM82, IIETRM85)
ExpansionRomOff = $CFFF

.org $C100

.include "Firmware.Original/Functions.asm"
.include "Firmware.Original/SlotEntry.asm"
.include "Firmware.Original/SelfTest.asm"
.include "Firmware.Original/EightyColumnsEntry.asm"
.include "Firmware.Original/EightyColumnsControl.asm"
.include "Firmware.Original/EightyColumnsScreen.asm"
.include "Firmware.Original/EightyColumnsMode.asm"
