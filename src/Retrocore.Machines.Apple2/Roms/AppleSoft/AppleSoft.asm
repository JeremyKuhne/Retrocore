;; APPLESOFT II ($D000-$F7FF)
;;
;; Apple's floating-point BASIC, derived from Microsoft 6502 BASIC 1.1. This hand-maintained native listing
;; assembles the II Plus, original IIe and enhanced IIe ROMs byte for byte. The original Microsoft source and
;; its license are in Microsoft6502Basic; the selectable MACRO-10 overlay applesoft.mac remains here.
;;
;; Memory. <TXTTAB> points to the first program line, and <VARTAB> to the simple variables after the
;; program. A line has a two-byte link to the next line, a two-byte line number, tokenized text and a zero
;; terminator; a zero link ends the program. Simple variables precede arrays at <ARYTAB>; <STREND> ends the
;; arrays. Each simple variable occupies seven bytes: two for its encoded name and five for its value.
;; An array record has a name, length, dimension count and bounds, followed by its values. A string descriptor
;; holds a byte count and a two-byte character address; characters need not be zero-terminated. Strings occupy
;; memory downwards from <MEMSIZ>, with <FRETOP> at their lower edge. <REASON> runs string collection before
;; reporting OUT OF MEMORY when the growing regions meet.
;;
;; Input is converted by <CRUNCH> using <RESLST>. Tokens select statement handlers through <STMDSP> and
;; function handlers through <FUNDSP>; <OPTAB> supplies operator precedence and handlers. Startup copies
;; <INITAT> to <CHRGET> in page zero, where its self-modifying load operand is <TXTPTR>. Monitor entry
;; points provide the machine's input, output and graphics.
;;
;; The included files follow ROM address order. Their names describe the main contents, not isolated call
;; boundaries: routines share entries and scratch locations across modules. The last module also reserves
;; $F800-$F863 for the Monitor; those bytes are outside the $D000-$F7FF Applesoft ROM.
;;
;; <ENHNCD> selects the enhanced IIe changes when 1 (the default); <APLPLS> selects the II Plus final ROM byte
;; when 1 (default 0). Set <APLPLS> only with <ENHNCD> = 0.

.cpu Mos6502

; Microsoft's configuration values that AppleSoft fixes, renamed in the BASIC conversion (decision X15). A predefined
; old name would shadow the old name the definition carries and change nothing, so it is an error.
.assert .not .defined(BUFPAG), "AppleSoft fixes INPUT_BUFFER_PAGE; BUFPAG cannot be predefined."
.assert .not .defined(BUFLEN), "AppleSoft fixes INPUT_BUFFER_LENGTH; BUFLEN cannot be predefined."
.assert .not .defined(NULCMD), "AppleSoft fixes NULL_COMMAND; NULCMD cannot be predefined."
.assert .not .defined(NUMLEV), "AppleSoft fixes STACK_LEVELS; NUMLEV cannot be predefined."
.assert .not .defined(STKEND), "AppleSoft fixes STACK_END; STKEND cannot be predefined."
.assert .not .defined(INTPRC), "AppleSoft fixes INTEGER_VARIABLES; INTPRC cannot be predefined."
.assert .not .defined(ADDPRC), "AppleSoft fixes ADDITIONAL_PRECISION; ADDPRC cannot be predefined."
.assert .not .defined(LNGERR), "AppleSoft fixes LONG_ERRORS; LNGERR cannot be predefined."

.ifndef ENHNCD
ENHNCD = 1                          ;; 1 for the enhanced IIe ROM
.endif
.ifndef APLPLS
APLPLS = 0                          ;; 1 for the II Plus ROM, with ENHNCD = 0
.endif

.include "AppleSoft.Equates.asm"
; This root composes its I/O explicitly; the legacy values do not retarget it.
.assert TIME = 0, "AppleSoft requires TIME = 0."
.assert EXTIO = 0, "AppleSoft requires EXTIO = 0."
.assert DISKO = 0, "AppleSoft requires DISKO = 0."
.include "../Microsoft6502Basic/MsBasic.CharacterReader.asm"
.include "AppleSoft.DispatchTables.asm"
.include "AppleSoft.MemoryManagement.asm"
.include "AppleSoft.ErrorAndInput.asm"
.include "AppleSoft.Lister.asm"
.include "AppleSoft.ControlFlow.asm"
.include "AppleSoft.Assignment.asm"
.include "AppleSoft.Print.asm"
.include "AppleSoft.InputOutput.asm"
.include "AppleSoft.Expressions.asm"
.include "AppleSoft.Arrays.asm"
.include "../Microsoft6502Basic/MsBasic.ArrayMultiplication.asm"
.include "AppleSoft.Functions.asm"
.include "AppleSoft.Strings.asm"
.include "AppleSoft.NumericConversion.asm"
.include "../Microsoft6502Basic/MsBasic.FloatingPoint.asm"
.include "../Microsoft6502Basic/MsBasic.FloatArithmetic.asm"
.include "../Microsoft6502Basic/MsBasic.FloatMovement.asm"
.include "../Microsoft6502Basic/MsBasic.FloatConversion.asm"
.include "../Microsoft6502Basic/MsBasic.FloatOutput.asm"
.include "AppleSoft.HistoricalNames.asm"
.include "AppleSoft.InterpreterAliases.asm"
.include "../Microsoft6502Basic/MsBasic.Transcendental.asm"
.include "AppleSoft.Initialization.asm"
.include "AppleSoft.AppleCommands.asm"
.include "AppleSoft.HighResolution.asm"
.include "AppleSoft.PlatformHelpers.asm"

.assert * = $F864, "AppleSoft and its reserved Monitor workspace have moved."
