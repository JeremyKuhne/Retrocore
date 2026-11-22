;; APPLESOFT: PEEK, POKE AND WAIT
;;
;; The shared entries follow the byte-conversion helpers in AppleSoft.Strings.asm. AppleSoft accepts negative
;; addresses, preserves <POKER> across <PEEK>, and reads ROM without a guard or padding. Its omitted WAIT mask
;; branches to <ZSTORD>, an alias of <STORDO> defined in MsBasic.FloatingPoint.asm.

.include "../Microsoft6502Basic/MsBasic.MemoryAccess.asm"

    MEMORY_ACCESS_ADDRESS 0
    MEMORY_ACCESS_PEEK 1, 0, 0, 0
    MEMORY_ACCESS_POKE

;; Waits until the masked memory value is nonzero.
;; Entry: FNWAIT = the same WAIT entry
;; See: <FNWAIT>
WAIT:
    MEMORY_ACCESS_WAIT ZSTORD
