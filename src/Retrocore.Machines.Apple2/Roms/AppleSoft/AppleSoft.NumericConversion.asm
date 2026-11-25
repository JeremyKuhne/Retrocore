; retrocore: style=strict
; APPLESOFT: PEEK, POKE AND WAIT
;
; The shared entries follow the byte-conversion helpers in AppleSoft.Strings.asm. AppleSoft accepts negative
; addresses, preserves PokeAddress across Functions::Peek, and reads ROM without a guard or padding. Its omitted WAIT
; mask branches straight to Statements::Wait::StoreMask, the plain wait, where Microsoft's source names the target
; ZSTORDO. AppleSoft's own label for Statements::Wait, WAIT, is an alias in AppleSoft.HistoricalNames.asm.

.include "../Microsoft6502Basic/MsBasic.MemoryAccess.asm"

    AddressConversion 0
    PeekFunction 1, 0, 0, 0
    PokeStatement

    WaitStatement Statements::Wait::StoreMask
