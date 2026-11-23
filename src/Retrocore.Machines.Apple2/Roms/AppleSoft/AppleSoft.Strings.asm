;; APPLESOFT: STRING STORAGE AND FUNCTIONS
;;
;; A string descriptor is three bytes: a length followed by a low/high address. The characters are counted,
;; not zero-terminated. String space grows down from <MEMSIZ>; temporary descriptors occupy a small
;; stack in page zero. The collector scans temporary, scalar and array descriptors and compacts live strings
;; toward the top of memory. Its high-byte-only sentinel stops at a selected page-zero descriptor without
;; moving it or the remaining lower strings; see <GARBA2>. A literal in program text can point directly at
;; that text; literals in the input or output buffers must be copied.

.include "../Microsoft6502Basic/MsBasic.StringFunctions.asm"
.include "../Microsoft6502Basic/MsBasic.StringStorage.asm"
.include "../Microsoft6502Basic/MsBasic.StringGarbageCollection.asm"
.include "../Microsoft6502Basic/MsBasic.StringConversion.asm"
.include "../Microsoft6502Basic/MsBasic.StringConcatenation.asm"

    STRING_FROM_NUMBER
    STRING_STORAGE INPUT_BUFFER_PAGE, 0
    STRING_ALLOCATION 0
    STRING_GARBAGE_COLLECTION 0, 0, 0
    STRING_CONCATENATION 0
    STRING_FUNCTIONS 1, 0, 0, 0
