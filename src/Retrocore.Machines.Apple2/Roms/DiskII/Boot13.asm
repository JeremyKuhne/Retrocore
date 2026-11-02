;; APPLE DISK II INTERFACE CARD BOOT ROM, 13 SECTORS (P5, 341-0009)
;;
;; The first Disk II boot ROM, for the 5-and-3 nibbles of DOS 3.1 to 3.2.1. It reads the boot sector into
;; $0300-$03FF, rebuilds its first 153 bytes in DENIB, and jumps to $0301 if the sector's first byte is $99, or
;; prints ERR if not. $CnFF = $FF marks it as a 13-sector ROM. Boot.asm holds the code, shared with the 16-sector
;; ROM.
;;
;; Assembles byte-identically to the 341-0009 PROM. Maintained by hand; DiskIISourceTests pin it by digest.

SECTORS = 13                        ;; sectors per track on the disks this ROM reads

.cpu Mos6502

.include "Boot.asm"
