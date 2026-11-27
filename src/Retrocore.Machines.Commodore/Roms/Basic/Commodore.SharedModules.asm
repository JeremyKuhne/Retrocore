; retrocore: style=strict
;; COMMODORE BASIC: THE SHARED MODULES THAT EMIT CODE WHEN INCLUDED
;;
;; Six of the shared Microsoft modules emit their code where they are included, rather than defining a macro. A root
;; in this folder includes them directly; a root in another folder, such as the VIC-20's, calls these macros instead,
;; so that each module is found beside this file in the repository and in the SDK alike. Each macro is called once,
;; where the module's code goes. Including this file emits no bytes.

;; Emits MsBasic.LineSearch.asm: <FindLine>.
.macro SharedLineSearch
    .include "../../Microsoft6502Basic/MsBasic.LineSearch.asm"
.endmacro

;; Emits MsBasic.For.asm: `FOR`.
.macro SharedFor
    .include "../../Microsoft6502Basic/MsBasic.For.asm"
.endmacro

;; Emits MsBasic.LineNumber.asm: <ReadLineNumber>.
.macro SharedLineNumber
    .include "../../Microsoft6502Basic/MsBasic.LineNumber.asm"
.endmacro

;; Emits MsBasic.StringOutput.asm: <PrintText>.
.macro SharedStringOutput
    .include "../../Microsoft6502Basic/MsBasic.StringOutput.asm"
.endmacro

;; Emits MsBasic.Dim.asm: `DIM`.
.macro SharedDim
    .include "../../Microsoft6502Basic/MsBasic.Dim.asm"
.endmacro

;; Emits MsBasic.ArrayMultiplication.asm, the array-size multiplication.
.macro SharedArrayMultiplication
    .include "../../Microsoft6502Basic/MsBasic.ArrayMultiplication.asm"
.endmacro
