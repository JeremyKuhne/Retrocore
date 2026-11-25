; retrocore: style=strict
; APPLESOFT: PROGRAM LISTING
;
; LIST accepts a comma or minus token between its bounds and surrounds expanded words with spaces. The enhanced IIe
; prints the line number through PrintSpaceAndLineNumber; both builds use the page-carrying walk of ReservedWords.

.include "../Microsoft6502Basic/MsBasic.Lister.asm"

    ListRange 1, ResetStack::Done
.if ENHNCD
    ListLines 0, 0, 2, PrintSpaceAndLineNumber, 1, NextStatementSavingStack
.else
    ListLines 0, 0, 1, Float::PrintDecimalAX, 1, NextStatementSavingStack
.endif
    ListNextTableByte
    ListTokens 2, 0, 0, 1
