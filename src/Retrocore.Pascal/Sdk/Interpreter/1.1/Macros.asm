; retrocore: style=strict
;; Macros for SYSTEM.APPLE's tables, so each entry says what it is and is checked to be in its place.

;; One entry of <OpcodeTable>: the routine that runs an opcode.
;; Parameters:
;;   number = the opcode, from <FIRST_TABLE_OPCODE> up; the entries go in opcode order
;;   routine = the routine that runs it
.macro Opcode number, routine
    .assert * = OpcodeTable + 2 * (number - FIRST_TABLE_OPCODE), "OpcodeTable's entries are in opcode order."
    .word routine
.endmacro

;; Entries of <OpcodeTable> for a run of opcodes that one routine runs.
;; Parameters:
;;   first = the run's first opcode
;;   last = its last opcode
;;   routine = the routine that runs them all
.macro Opcodes first, last, routine
    .assert * = OpcodeTable + 2 * (first - FIRST_TABLE_OPCODE), "OpcodeTable's entries are in opcode order."
    .repeat last - first + 1
        .word routine
    .endrepeat
.endmacro

;; One entry of <CspTable>: the routine that runs a standard procedure, which <CSP at OpCSP> calls by number.
;; Parameters:
;;   number = the standard procedure's number, as Pcode.asm's `CSP` scope names it; the entries go in order
;;   routine = the routine that runs it
.macro StandardProcedure number, routine
    .assert * = CspTable + 2 * number, "CspTable's entries are in standard procedure order."
    .word routine
.endmacro

;; Entries of <CspTable> for standard procedure numbers that SYSTEM.APPLE has no routine for: each is 0.
;; Parameters:
;;   first = the first number with no routine
;;   last = the last
.macro NoStandardProcedures first, last
    .assert * = CspTable + 2 * first, "CspTable's entries are in standard procedure order."
    .repeat last - first + 1
        .word 0
    .endrepeat
.endmacro
