;; APPLESOFT: PEEK, POKE AND WAIT
;;
;; The shared entries follow the byte-conversion helpers in AppleSoft.Strings.asm. AppleSoft accepts negative addresses,
;; preserves <POKER> across <Functions::Peek>, and reads ROM without a guard or padding. Its omitted WAIT mask branches
;; straight to <Statements::Wait::StoreMask>, the plain wait, where Microsoft's source names the target ZSTORDO.

.include "../Microsoft6502Basic/MsBasic.MemoryAccess.asm"

    AddressConversion 0
    PeekFunction 1, 0, 0, 0
    PokeStatement

;; Waits until the masked memory value is nonzero: AppleSoft's label for <Statements::Wait>, which follows.
WAIT:
    WaitStatement STORDO
