; retrocore: style=strict
;; APPLE II 3.5 DISK CONTROLLER CARD FIRMWARE (341-0438-A)
;;
;; Assembles byte-identically to the 341-0438-A EPROM (32768 bytes, SHA-1 440c3f84176c7b9f542da0b6ddf4fb13ec326c46),
;; which Apple2Disk35Tests.SourceMatchesTheChip pins by its SHA-256 (084587835C1D...). The EPROM is the card's own
;; 65C02's: it holds images of what the card copies into its RAM at start-up (its page zero, the host's code and the
;; diagnostics), the card's self-tests, and the firmware the card runs from $D000. Its names are the SDK's own, given as
;; the EPROM was decoded; the few that Apple's documents or sources give are kept in `Also:`.

.cpu Wdc65C02

.include "Disk35Equates.asm"

.org $8000

;; The image of the card's page zero, which <CopyZeroPage> copies at a cold start.
ZeroPageImage:
.include "Disk35ZeroPage.asm"

;; The image of the host's slot page and code, which <CopyHostCode> copies into the RAM the host sees.
SlotPageImage:
.include "Disk35Host.asm"
.assert * = $8800, "The diagnostics' image must start at $8800."

;; The image of the diagnostics' host code and page zero, which <SelfTest::CardDiagnostics> puts in place.
DiagnosticsImage:
.include "Disk35Diagnostics.asm"
.assert * = $8F00, "The self-tests must start at $8F00."
.include "Disk35SelfTest.asm"
.assert * = $9A00, "The self-tests must end at $9A00."

.org $D000
.include "Disk35Card.asm"
.assert * = $10000, "The firmware must end at the top of memory."
