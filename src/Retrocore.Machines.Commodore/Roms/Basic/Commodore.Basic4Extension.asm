; COMMODORE BASIC 4: MONITOR AND DISK ROM COMPOSITION
;
; Include only for BASIC 4, after Commodore.Equates.asm with DISK_STATUS_STRING=1,
; LINE_WIDTH_STORAGE=0, EXTENDED_DISK_VECTORS=1, INPUT_BUFFER_PAGE=2 and the later terminal defaults
; TERMINAL_FIRST=NULL_COMMAND=LOCAL_TERMINAL_POSITION=0. These definitions emit no bytes.
; Invoke COMMODORE_BASIC4_EXTENSION immediately after the LASTWR label at $D472; it emits
; through $DFFF. Its external BASIC entries are READY, SNERR, SYNCHR, CHKCOM, CHKOPN,
; CHKCLS, FRMEVL, GETADR, GETBYT, GETSPA, FRESTR, LINPRT and ERROR, plus the ERRFC,
; ERRLS and TOTK table values. Commodore.Equates.asm supplies the BASIC workspace;
; Commodore.Basic4SystemEquates.asm supplies the kernal workspace and ROM entries.
;
; The $D000 chip is identical in both revisions. Select the corresponding $B000-chip
; fixes separately with COMMODORE_BASIC4_OPERAND_SPLIT revised in Commodore.Basic4Patches.asm.

; Supply the BASIC 4 workspace when this definitions-only file is opened on its own.
.ifndef INDEX
.ifndef DISK_STATUS_STRING
DISK_STATUS_STRING = 1              ;; BASIC 4 has the disk-status string descriptor
.endif
.ifndef LINE_WIDTH_STORAGE
LINE_WIDTH_STORAGE = 0              ;; BASIC 4 reuses the line-width storage
.endif
.ifndef EXTENDED_DISK_VECTORS
EXTENDED_DISK_VECTORS = 1           ;; BASIC 4 has the disk-command vectors
.endif
.include "Commodore.Equates.asm"
.endif

.include "Commodore.Basic4SystemEquates.asm"
.include "Commodore.Basic4Monitor.asm"
.include "Commodore.Basic4Record.asm"
.include "Commodore.Basic4DiskCommands.asm"
.include "Commodore.Basic4DiskParser.asm"
.include "Commodore.Basic4RomEnd.asm"

.assert DISK_STATUS_STRING = 1 && LINE_WIDTH_STORAGE = 0, "BASIC 4 needs the disk-status workspace."
.assert TERMINAL_FIRST = 0 && NULL_COMMAND = 0 && LOCAL_TERMINAL_POSITION = 0, "BASIC 4 needs the later terminal and scratch workspace."
.assert EXTENDED_DISK_VECTORS = 1, "BASIC 4 needs the disk-command vectors."
.assert INPUT_BUFFER_PAGE = 2 && CQSTAT = SATUS, "BASIC 4 needs the page-two input buffer and page-zero I/O status."

;; Emits BASIC 4's monitor and disk-command extension after the startup messages.
;; Parameters: revised = 1 for the revised $B000 ROM, 0 for the original
.macro COMMODORE_BASIC4_EXTENSION revised
    .assert revised = 0 || revised = 1, "revised is 0 or 1."
    .assert * = $D472, "The BASIC 4 extension must begin at $D472."
    COMMODORE_BASIC4_MONITOR
    COMMODORE_BASIC4_RECORD
    COMMODORE_BASIC4_DISK_COMMANDS
    COMMODORE_BASIC4_DISK_PARSER
    COMMODORE_BASIC4_ROM_END
.endmacro
