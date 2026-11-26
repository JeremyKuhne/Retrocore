; retrocore: style=strict
;; COMMODORE BASIC: THE VIC-20'S SWITCHES
;;
;; The switches that select the VIC-20's BASIC, its workspace and its code, over the PET's. Each defaults to the PET's
;; value, 0 but for <OUTPUT_SUPPRESSION_FLAG>; a root that wants another predefines it, or defines it before including
;; Commodore.Equates.asm, which includes this file to lay out the workspace. The modules whose code the switches change
;; include this file too, so that one assembled without the workspace, by a test or in the editor, builds the PET's
;; code. Only the first inclusion defines anything, and including it emits no bytes.

;; Set once the switches are defined, so a later inclusion of this file defines nothing.
.ifndef COMMODORE_SWITCHES_DEFINED
COMMODORE_SWITCHES_DEFINED = 1

.ifndef CONVERSION_VECTORS
;; 1 reserves two vectors after the `USR` jump, to the float-to-integer and integer-to-float routines.
CONVERSION_VECTORS = 0
.endif
.ifndef CURSOR_COLUMN_FROM_PLOT
;; 1 reads the cursor's column through the kernal's PLOT, keeping `TAB`'s copy in a byte of BASIC's own.
CURSOR_COLUMN_FROM_PLOT = 0
.endif
.ifndef OUTPUT_SUPPRESSION_FLAG
;; 1 reserves the Control-O output-suppression flag where the disk-status string does not replace it.
OUTPUT_SUPPRESSION_FLAG = 1
.endif
.ifndef STANDARD_KERNAL
;; 1 for the VIC-20's kernal: its jump table, status and clock, its errors returned with carry set, and BASIC's own
;; `LOAD`, `SAVE`, `VERIFY`, `OPEN`, `CLOSE` and `SYS` over it.
STANDARD_KERNAL = 0
.endif
.ifndef BASIC_RAM_VECTORS
;; 1 sends errors, the command loop, tokenizing, listing, statements and operands through the vectors at $0300.
BASIC_RAM_VECTORS = 0
.endif
.ifndef NUMBERED_ERRORS
;; 1 numbers the errors from 1, the kernal's first, and finds each message through a table of addresses.
NUMBERED_ERRORS = 0
.endif

.assert CONVERSION_VECTORS = 0 || CONVERSION_VECTORS = 1, "CONVERSION_VECTORS is 0 or 1."
.assert CURSOR_COLUMN_FROM_PLOT = 0 || CURSOR_COLUMN_FROM_PLOT = 1, "CURSOR_COLUMN_FROM_PLOT is 0 or 1."
.assert OUTPUT_SUPPRESSION_FLAG = 0 || OUTPUT_SUPPRESSION_FLAG = 1, "OUTPUT_SUPPRESSION_FLAG is 0 or 1."
.assert STANDARD_KERNAL = 0 || STANDARD_KERNAL = 1, "STANDARD_KERNAL is 0 or 1."
.assert BASIC_RAM_VECTORS = 0 || BASIC_RAM_VECTORS = 1, "BASIC_RAM_VECTORS is 0 or 1."
.assert NUMBERED_ERRORS = 0 || NUMBERED_ERRORS = 1, "NUMBERED_ERRORS is 0 or 1."
.assert STANDARD_KERNAL = 0 || BASIC_RAM_VECTORS = 1, "SYS keeps the registers beside the RAM vectors."
.endif
