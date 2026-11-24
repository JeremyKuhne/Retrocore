; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: MEMORY LAYOUTS
;;
;; The layouts of the records BASIC keeps in memory and on the stack, which AppleSoft and every PET build share:
;; a simple variable, an array's header, a string descriptor, the `FOR` and `GOSUB` frames, an operator's table entry,
;; a program line and a `DEF FN` definition. They describe five-byte floating point, the only format these builds
;; use. Including this file emits no bytes and does not change the origin.
;;
;; Code reaches a field as an offset from the record's start. A frame on the stack is reached from the stack
;; pointer: after `tsx`, the frame that starts just above the stack pointer is at `Stack + 1 + offset,x`.

;; The 6502's stack, page one.
Stack = $0100

;; A simple variable's entry in the table at <VariablesStart>.
;;
;; The two bits 7 of the name give its type: neither for a real, the first for a `DEF FN` function, the second for a
;; string, both for an integer. A string's value is its <StringDescriptor>; a function's is its
;; <FunctionDefinition>.
.struct Variable
    NAME .word ;; The name's first two characters, each with its type bit.
    VALUE .res 5 ;; The value: a packed real, an integer high byte first, a descriptor or a definition.
.endstruct

;; The header of an array's entry in the table at <ArraysStart>.
;;
;; The bounds follow it, one two-byte count per dimension, high byte first, the last dimension first; then the
;; elements.
.struct ArrayHeader
    NAME .word ;; The name's first two characters, each with its type bit, as in <Variable>.
    LENGTH .word ;; The entry's whole size in bytes, header included, so a search can step over it.
    DIMENSIONS .byte ;; The number of dimensions.
.endstruct

;; A string's descriptor: in a variable, an array element or a temporary.
;;
;; The characters need not end in a zero; they are in the program's text, the input buffer or the string space.
.struct StringDescriptor
    LENGTH .byte ;; The number of characters.
    ADDRESS .word ;; The first character's address.
.endstruct

;; The size of a <StringDescriptor>.
;; Also: STRSIZ (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
DESCRIPTOR_SIZE = .sizeof(StringDescriptor)

;; The frame `FOR` pushes on the stack, from low addresses to high, which `NEXT` finds and steps.
;;
;; The text pointer is stored high byte first, the reverse of the line number.
.struct ForFrame
    TOKEN .byte ;; The `FOR` token, which marks the frame.
    VARIABLE .word ;; The address of the loop variable's value.
    STEP .res 5 ;; The step in packed order, its sign bit left as the mantissa's normalized bit (see <STEP_SIGN>).
    STEP_SIGN .byte ;; The step's sign: 1, 0 or $FF.
    LIMIT .res 5 ;; The limit, a packed real.
    LINE .word ;; The line number of the `FOR` statement.
    TEXT_POINTER_HIGH .byte ;; The high byte of the text pointer after the `FOR` statement.
    TEXT_POINTER .byte ;; The low byte of that text pointer.
.endstruct

;; The size of a <ForFrame>.
;; Also: FORSIZ (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
FOR_FRAME_SIZE = .sizeof(ForFrame)

;; The frame `GOSUB` pushes on the stack, from low addresses to high, which `RETURN` pops.
.struct GosubFrame
    TOKEN .byte ;; The `GOSUB` token, which marks the frame.
    LINE .word ;; The line number of the `GOSUB` statement.
    TEXT_POINTER .word ;; The text pointer at the target's line number, not yet read; `RETURN` skips it.
.endstruct

;; An entry of the operator table: what the expression evaluator needs to apply a binary operator.
.struct OperatorEntry
    PRECEDENCE .byte ;; The operator's precedence: higher binds tighter.
    HANDLER .word ;; The handler's address minus one, for a return through the stack.
.endstruct

;; The header of a program line, as lines are stored from <ProgramStart> on.
;;
;; The tokenized text follows it and ends in a zero. A zero link ends the program.
.struct ProgramLine
    LINK .word ;; The address of the next line.
    NUMBER .word ;; The line number.
.endstruct

;; A function's definition, which `DEF` stores as a <Variable>'s value.
.struct FunctionDefinition
    FORMULA .word ;; The text pointer to the formula after the equals sign.
    ARGUMENT .word ;; The address of the argument variable's value.
    FIRST_CHARACTER .byte ;; The formula's first character, which nothing reads.
.endstruct

;; The size of a packed real, which is the largest array element. The array code starts an element's size at it
;; and counts it down: to 2 for an integer, to 3 for a string.
FLOAT_SIZE = 5

;; The bound each dimension of an array used without `DIM` gets: indexes 0 to 10.
DEFAULT_BOUND = 11

; The layouts the code depends on.
.assert .sizeof(Variable) = 7, "A simple variable takes seven bytes."
.assert .sizeof(ArrayHeader) = 5, "An array's header takes five bytes."
.assert DESCRIPTOR_SIZE = 3, "A string descriptor takes three bytes."
.assert FOR_FRAME_SIZE = 18, "A FOR frame takes eighteen bytes."
.assert .sizeof(GosubFrame) = 5, "A GOSUB frame takes five bytes."
.assert .sizeof(OperatorEntry) = 3, "An operator entry takes three bytes."
.assert .sizeof(FunctionDefinition) = .sizeof(Variable::VALUE), "A definition fills a variable's value."
