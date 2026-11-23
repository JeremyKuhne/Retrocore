;; APPLESOFT: PEEK, POKE AND WAIT
;;
;; The shared entries follow the byte-conversion helpers in AppleSoft.Strings.asm. AppleSoft accepts negative
;; addresses, preserves <POKER> across <PEEK>, and reads ROM without a guard or padding. Its omitted WAIT mask
;; branches straight to <STORDO>, the plain wait, where Microsoft's source names the target ZSTORDO.

.include "../Microsoft6502Basic/MsBasic.MemoryAccess.asm"

    MEMORY_ACCESS_ADDRESS 0
    MEMORY_ACCESS_PEEK 1, 0, 0, 0
    MEMORY_ACCESS_POKE

;; Waits until the masked memory value is nonzero.
;; Entry: FNWAIT = the same WAIT entry
;; See: <FNWAIT>
WAIT:
    MEMORY_ACCESS_WAIT STORDO
