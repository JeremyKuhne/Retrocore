;; APPLESOFT: VARIABLES AND ARRAYS
;;
;; Simple variables occupy seven-byte entries from <VARTAB> to <ARYTAB>; arrays follow up to <STREND>.
;; The first two bytes encode the significant characters and the variable type. A read of an absent simple
;; variable can use <SIMZER> instead of allocating it; assignment creates an entry and moves the array table.
;; Arrays carry their own lengths and dimension bounds, followed by values: five bytes per floating-point
;; value, two per integer, or three per string descriptor. The tables are searched sequentially, not sorted.

.include "../Microsoft6502Basic/MsBasic.IntegerConversion.asm"
.include "../Microsoft6502Basic/MsBasic.VariableLookup.asm"
.include "../Microsoft6502Basic/MsBasic.Dim.asm"
.include "../Microsoft6502Basic/MsBasic.Arrays.asm"

    VARIABLE_NAME 1, (ENHNCD * $C4), 0, 1, 0, 0
    LETTER_TEST
    SIMPLE_VARIABLE_LOOKUP 1, 1, 1, 0, 0, 0, 0, 1

    INTEGER_CONVERSION_BOUNDARY
    INTEGER_CONVERSION FRMNUM, 0
    EXISTING_ARRAY_ENTRY
    ARRAY_LOOKUP 1, 0, 1
