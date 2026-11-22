;; APPLESOFT: STACK AND BLOCK MANAGEMENT
;;
;; The interpreter keeps FOR and GOSUB frames on the 6502 stack. Program editing and array allocation move
;; blocks upward as they grow; string collection also uses the unchecked entry of the same backward copy.
;; These routines follow the tables in AppleSoft.asm.
;;
;; Apple uses a $36-byte stack reserve rather than the generic Microsoft calculation based on <NUMLEV>.

.include "../Microsoft6502Basic/MsBasic.MemoryManagement.asm"

    MEMORY_MANAGEMENT $36
