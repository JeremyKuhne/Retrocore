;; APPLE IIE INTERNAL FIRMWARE ($C100-$CFFF), ORIGINAL IIE
;;
;; Layout of the original IIe's internal $C100-$CFFF ROM:
;;   $C100-$C2FF  Screen and keyboard helpers for the Monitor. The Monitor's switch routine at $FBB4 saves P,
;;                sets SETINTCXROM and jumps to $C100 with a function number in Y: 0 CLREOP, 1 HOME, 2 SCROLL,
;;                3 CLREOL, 4 CLREOLZ, 5 reset, 6 KEYIN (blinking cursor), 7 escape-key translation. Functions
;;                0-5 have a 40-column and an 80-column version. All return through F_RETURN ($FD29/$FD2C), which
;;                switches slot ROMs back in unless internal ROM was already in.
;;   $C300-$C3FF  Slot-3 entry points: BASICINT ($C300, PR#3), BASICIN ($C305) and BASICOUT ($C307) for the
;;                KSW/CSW hooks; the Pascal 1.1 ID bytes and PASCALOFS offsets to JPINIT/JPREAD/JPWRITE/
;;                JPSTAT; AUXMOVE and XFER for main/auxiliary memory. Running from $C3xx selects the internal
;;                $C800 ROM; BASICINT/IN/OUT also read $CFFF so no peripheral card's $C800 ROM stays selected.
;;   $C400-$C7FF  Built-in self-test, entered from the reset function when Solid-Apple (BUTN1) is held: MMU and
;;                IOU switch checks, ROM checksums, a RAM test, and a message on failure.
;;   $C800-$CFFF  The body of the 80-column firmware: output, input with escape-mode cursor moves, control
;;                characters, 40/80 conversion, Pascal I/O, and the low-level screen access through 80STORE.
;; The 80-column firmware keeps its state in slot 3's screen holes: $047B last CH it set, $04FB mode
;; flags ($FF = firmware inactive; bit 7 uppercase input, 6 in BASICIN, 5 Pascal, 4 inside quotes, 3 GOTOXY
;; pending, 2 inverse, 0 interrupts allowed), $057B 80-column cursor column, $05FB cursor row, $067B
;; current character, $06FB GOTOXY column, $077B/$07FB saved BASL/BASH. $0478 is scratch.
;;
;; Assembles byte-identically to the internal $C100-$CFFF ROM: the 80-column firmware in slot three's
;; space and $C800, and the routines the Monitor calls with internal ROM switched in. Names are Apple's
;; documented entry points; other labels are named after the routine they are in.
;; It includes IIeEquates.asm (the IIe's page zero, soft switches and keys), MonitorEntries.asm (the Monitor's
;; entry points) and FirmwareEquates.asm (the equates both firmware models share).
;;
;; Maintained by hand. The SystemSourceTests digests check that it assembles byte-identically.

.cpu Mos6502

; Apple II text has bit 7 set, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

; The IIe's page zero, soft switches and keys, the Monitor's entry points, and the equates both firmware models share.
.include "IIeEquates.asm"
.include "MonitorEntries.asm"
.include "FirmwareEquates.asm"

; A screen hole only this model's firmware uses.
TEMP1 = $0478                       ;; 80-column firmware: scratch (slot-3 screen hole)

; The expansion ROM switch, a label in the Enhanced IIe's firmware, so not in IIeEquates.asm.
;; Inherit: <Monitor:CLRROM>
CLRROM = $CFFF

; More characters with bit 7 set. CTLCHAR and Pascal take control characters with bit 7 clear, written KEY_x & $7F.
KEY_FF = $8C                        ;; Control-L: home and clear
KEY_CTRL_Q = $91                    ;; 40 columns
KEY_CTRL_R = $92                    ;; 80 columns
KEY_FS = $9C                        ;; Control-\: cursor right
KEY_GS = $9D                        ;; Control-]: clear to the end of the line
KEY_GOTOXY = $9E                    ;; Control-^: Pascal's GOTOXY
KEY_US = $9F                        ;; Control-_: cursor up

.org $C100

.include "Firmware.Original/Functions.asm"
.include "Firmware.Original/SlotEntry.asm"
.include "Firmware.Original/SelfTest.asm"
.include "Firmware.Original/EightyColumnsEntry.asm"
.include "Firmware.Original/EightyColumnsControl.asm"
.include "Firmware.Original/EightyColumnsScreen.asm"
.include "Firmware.Original/EightyColumnsMode.asm"
