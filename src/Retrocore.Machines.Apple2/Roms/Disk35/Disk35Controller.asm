;; APPLE II 3.5 DISK CONTROLLER CARD FIRMWARE (341-0438-A)
;;
;; Assembles byte-identically to the 341-0438-A EPROM (32768 bytes, SHA-1 440c3f84176c7b9f542da0b6ddf4fb13ec326c46).

.cpu Wdc65C02

.include "Disk35Equates.asm"

.org $8000
ZeroPageImage:
.include "Disk35ZeroPage.asm"
SlotPageImage:
.include "Disk35Host.asm"
.assert * == $8800
DiagnosticsImage:
.include "Disk35Diagnostics.asm"
.assert * == $8F00
.include "Disk35SelfTest.asm"
.assert * == $9A00
.org $D000
.include "Disk35Card.asm"
.assert * == $10000
