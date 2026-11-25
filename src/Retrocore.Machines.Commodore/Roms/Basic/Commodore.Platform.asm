; retrocore: style=strict
;; COMMODORE BASIC: THE PLATFORM'S DEFINITIONS
;;
;; Include this once, before the shared interpreter's macros. It defines the selected PET workspace and Commodore's
;; own macros: the dispatch tables, command input, the clock-string and string assignment, channel output and input,
;; BASIC 4's and BASIC 1's patches, the variable operand, initialization and statement dispatch. Including it emits
;; no bytes and does not change the origin.

.include "Commodore.Equates.asm"
.include "Commodore.DispatchTables.asm"
.include "Commodore.CommandInput.asm"
.include "Commodore.TimeAssignment.asm"
.include "Commodore.StringAssignment.asm"
.include "Commodore.ChannelPrint.asm"
.include "Commodore.ChannelInput.asm"
.include "Commodore.Basic4Patches.asm"
.include "Commodore.Basic1Patches.asm"
.include "Commodore.VariableEvaluation.asm"
.include "Commodore.Initialization.asm"
.include "Commodore.StatementDispatch.asm"
