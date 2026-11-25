; retrocore: style=strict
;; COMMODORE BASIC: THE INTERPRETER'S MACROS
;;
;; Defines Commodore's platform macros (Commodore.Platform.asm) and the shared Microsoft modules' macros, without
;; emitting bytes. Each PET root then invokes them with its own options, in its ROM's order.

.include "Commodore.Platform.asm"
.include "../../Microsoft6502Basic/MsBasic.Next.asm"
.include "../../Microsoft6502Basic/MsBasic.ExpressionCore.asm"
.include "../../Microsoft6502Basic/MsBasic.OperandEvaluation.asm"
.include "../../Microsoft6502Basic/MsBasic.CharacterReader.asm"
.include "../../Microsoft6502Basic/MsBasic.Assignment.asm"
.include "../../Microsoft6502Basic/MsBasic.UserFunctions.asm"
.include "../../Microsoft6502Basic/MsBasic.SimpleFunctions.asm"
.include "../../Microsoft6502Basic/MsBasic.MemoryManagement.asm"
.include "../../Microsoft6502Basic/MsBasic.MemoryAccess.asm"
.include "../../Microsoft6502Basic/MsBasic.IntegerConversion.asm"
.include "../../Microsoft6502Basic/MsBasic.Lister.asm"
.include "../../Microsoft6502Basic/MsBasic.ProgramTransfers.asm"
.include "../../Microsoft6502Basic/MsBasic.ProgramReset.asm"
.include "../../Microsoft6502Basic/MsBasic.Print.asm"
.include "../../Microsoft6502Basic/MsBasic.Relational.asm"
.include "../../Microsoft6502Basic/MsBasic.StatementFlow.asm"
.include "../../Microsoft6502Basic/MsBasic.StringFunctions.asm"
.include "../../Microsoft6502Basic/MsBasic.StringConversion.asm"
.include "../../Microsoft6502Basic/MsBasic.StringConcatenation.asm"
.include "../../Microsoft6502Basic/MsBasic.StringGarbageCollection.asm"
.include "../../Microsoft6502Basic/MsBasic.StringStorage.asm"
.include "../../Microsoft6502Basic/MsBasic.VariableInput.asm"
.include "../../Microsoft6502Basic/MsBasic.VariableLookup.asm"
.include "../../Microsoft6502Basic/MsBasic.Arrays.asm"
