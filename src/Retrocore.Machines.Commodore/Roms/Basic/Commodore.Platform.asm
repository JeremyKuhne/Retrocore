;; COMMODORE BASIC PLATFORM DEFINITIONS
;;
;; Include this once before the shared interpreter sections. It defines the selected PET workspace and the
;; Commodore-specific dispatch, assignment and channel macros; it emits no bytes.

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
