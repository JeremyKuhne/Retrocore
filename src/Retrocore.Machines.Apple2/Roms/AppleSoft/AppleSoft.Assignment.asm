; retrocore: style=strict
; APPLESOFT: VARIABLE ASSIGNMENT
;
; AppleSoft has no time-string assignment, so the common AssignString entry falls directly into StoreString.

.include "../Microsoft6502Basic/MsBasic.Assignment.asm"

    AssignmentStart
    StringAssignment 0, 0
