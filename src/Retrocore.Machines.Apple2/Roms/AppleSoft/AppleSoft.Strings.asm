; retrocore: style=strict
; APPLESOFT: STRING STORAGE AND FUNCTIONS
;
; A string descriptor is three bytes: a length followed by a low/high address. The characters are counted, not
; zero-terminated. String space grows down from MemoryTop; temporary descriptors occupy a small stack in page zero.
; The collector scans temporary, scalar and array descriptors and compacts live strings toward the top of memory. Its
; high-byte-only sentinel stops at a selected page-zero descriptor without moving it or the remaining lower strings;
; see Strings::CollectGarbage. A literal in program text can point directly at that text; literals in the input or
; output buffers must be copied.

.include "../Microsoft6502Basic/MsBasic.StringFunctions.asm"
.include "../Microsoft6502Basic/MsBasic.StringStorage.asm"
.include "../Microsoft6502Basic/MsBasic.StringGarbageCollection.asm"
.include "../Microsoft6502Basic/MsBasic.StringConversion.asm"
.include "../Microsoft6502Basic/MsBasic.StringConcatenation.asm"

    StringFromNumber
    StringStorage INPUT_BUFFER_PAGE, 0
    StringAllocation 0
    StringGarbageCollection 0, 0, 0
    StringConcatenation 0
    StringFunctions 1, 0, 0, 0
