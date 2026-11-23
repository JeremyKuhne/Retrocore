; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: THE FAMILIES OF ROUTINES
;;
;; The scopes the shared modules' routines belong to, declared here, empty, so that each module's macros can add
;; their pieces with `.scope Name continued` in whatever order a build expands them. Each module that adds to them
;; includes this file, and only the first inclusion declares them. Including it emits no bytes and does not change the
;; origin.

;; Set once the families are declared, so a later inclusion of this file declares nothing.
.ifndef FAMILIES_DECLARED
FAMILIES_DECLARED = 1

;; The floating-point package: arithmetic on <Fac> and the argument register, packing and unpacking, conversion to
;; and from integers and text, and the polynomial evaluator, with the constants they use.
;;
;; A number in memory is packed: an exponent byte (zero for zero, otherwise 128 plus the binary exponent), then four
;; mantissa bytes, most significant first, whose top bit is the sign. Unpacked in <Fac> or the argument register, the
;; sign is a byte of its own and the mantissa's top bit is set.
.scope Float
.endscope

;; The handlers of BASIC's functions, each named for its keyword, which the function table dispatches to.
.scope Functions
.endscope

;; The handlers of BASIC's statements and commands, each named for its keyword, which the statement table dispatches
;; to, with the entries they share.
.scope Statements
.endscope

;; The handlers of BASIC's logical operators, which the operator table dispatches to.
.scope Operators
.endscope

;; The string package: allocating string space and building temporary strings, copying and releasing them, joining
;; them, and collecting the garbage left in string space.
.scope Strings
.endscope

;; The internals of variable and array lookup: creating a variable or an array, finding an array element's address,
;; and the zero an absent variable reads.
.scope Variables
.endscope
.endif
