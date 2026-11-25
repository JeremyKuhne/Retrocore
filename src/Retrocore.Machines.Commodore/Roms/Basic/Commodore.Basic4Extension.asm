; retrocore: style=strict
;; COMMODORE BASIC 4: THE MONITOR AND DISK-COMMAND ROM
;;
;; Defines the BASIC 4 extension, which fills the $D000 chip after the interpreter: the machine-language monitor, the
;; `RECORD` statement, the disk statements, their parameter parser, and the chip's checksum byte, status helper and
;; sign-on. Including this file emits no bytes; <CommodoreBasic4Extension> emits the extension.
;;
;; Include it only for BASIC 4, after Commodore.Equates.asm with <DISK_STATUS_STRING> = 1, <LINE_WIDTH_STORAGE> = 0,
;; <EXTENDED_DISK_VECTORS> = 1, <INPUT_BUFFER_PAGE> = 2 and the later terminal defaults (<TERMINAL_FIRST>,
;; <NULL_COMMAND> and <LOCAL_TERMINAL_POSITION> all 0). The extension calls these BASIC entries: <ReadyForCommand>,
;; <SyntaxError>, <CheckCharacter>, <CheckComma>, <CheckOpenParenthesis>, <CheckCloseParenthesis>,
;; <EvaluateExpression>, <ConvertToAddress>, <EvaluateByte>, <Strings::ReserveSpace>, <Strings::ReleaseFacString>,
;; <Float::PrintDecimalAX> and <ReportError>. It also uses the error offsets <ERROR_ILLEGAL_QUANTITY> and
;; <ERROR_STRING_TOO_LONG>, the tokens <TOKEN_TO> and <TOKEN_ON>, and <CARRIAGE_RETURN>, all defined with the
;; interpreter. Commodore.Equates.asm gives BASIC's workspace, and Commodore.Basic4SystemEquates.asm the kernal's.
;;
;; The $D000 chip is the same in both BASIC 4 revisions. The revised chip's fixes are on the $B000 chip, in
;; Commodore.Basic4Patches.asm.

; Supply BASIC 4's workspace when this file is opened on its own.
.ifndef Pointer1
.ifndef DISK_STATUS_STRING
;; BASIC 4 has the disk-status string's descriptor.
DISK_STATUS_STRING = 1
.endif
.ifndef LINE_WIDTH_STORAGE
;; BASIC 4 reuses the line-width storage.
LINE_WIDTH_STORAGE = 0
.endif
.ifndef EXTENDED_DISK_VECTORS
;; BASIC 4 has the disk-command vectors.
EXTENDED_DISK_VECTORS = 1
.endif
.include "Commodore.Equates.asm"
.endif

;; The helpers of the BASIC 4 disk statements: their parameter parser and checks, the command builder that sends a
;; disk command, the status reader behind `DS` and `DS$`, the confirmation prompt, and the helpers that close a
;; unit's files. Only the disk statements and, through the kernal's READDS entry, BASIC's `DS` and `DS$` use them.
;; Declared here, empty, so that each of the extension's files continues it.
.scope Disk
.endscope

.include "Commodore.Basic4SystemEquates.asm"
.include "Commodore.Basic4Monitor.asm"
.include "Commodore.Basic4Record.asm"
.include "Commodore.Basic4DiskCommands.asm"
.include "Commodore.Basic4DiskParser.asm"
.include "Commodore.Basic4RomEnd.asm"

.assert DISK_STATUS_STRING = 1 && LINE_WIDTH_STORAGE = 0, "BASIC 4 needs the disk-status workspace."
.assert TERMINAL_FIRST = 0 && NULL_COMMAND = 0, "BASIC 4 needs the later terminal and scratch workspace."
.assert LOCAL_TERMINAL_POSITION = 0, "BASIC 4 needs the later terminal and scratch workspace."
.assert EXTENDED_DISK_VECTORS = 1, "BASIC 4 needs the disk-command vectors."
.assert INPUT_BUFFER_PAGE = 2 && IoStatus = $96, "BASIC 4 needs the page-two input buffer and page-zero I/O status."

;; Emits BASIC 4's monitor and disk-command extension, from <InterpreterEnd> at $D472 to the end of the chip.
;; Parameters: revised = 1 for the revised $B000 chip, 0 for the original; the $D000 chip is the same in both, so
;;   this only checks it
.macro CommodoreBasic4Extension revised
    .assert revised = 0 || revised = 1, "revised is 0 or 1."
    .assert * = $D472, "The BASIC 4 extension must begin at $D472."
    CommodoreBasic4Monitor
    CommodoreBasic4Record
    CommodoreBasic4DiskCommands
    CommodoreBasic4DiskParser
    CommodoreBasic4RomEnd
.endmacro
