; retrocore: style=strict
;; COMMODORE BASIC: THE PLATFORM'S DEFINITIONS
;;
;; Include this once, before the shared interpreter's macros. It defines the selected workspace, the PET's or the
;; VIC-20's, and Commodore's own macros: the dispatch tables, command input, the clock-string and string assignment,
;; channel output and input, BASIC 4's and BASIC 1's patches, the variable operand, initialization, statement
;; dispatch, and the VIC-20's kernal statements and start-up, with the start-up's <CLEAR_SCREEN>. Including it emits
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
.include "Commodore.KernalStatements.asm"
.include "Commodore.KernalStartup.asm"
