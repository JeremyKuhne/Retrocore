; retrocore: style=strict
;; Apple Disk II interface card boot ROM, 16 sectors (P5, 341-0027)
;;
;; The boot ROM of the 16-sector card, for the 6-and-2 nibbles of DOS 3.3 and ProDOS. It reads the boot sector
;; into $0800-$08FF, then as many sectors after it as the sector's first byte says, and jumps to $0801; DOS 3.3
;; and ProDOS call its sector reader ($Cn5C) to load more. $CnFF = $00 marks it as a 16-sector ROM. Boot.asm holds the
;; code, shared with the 13-sector ROM.
;;
;; Assembles byte-identically to the 341-0027 PROM. Maintained by hand; DiskIISourceTests pin it by digest.

;; The sectors per track on the disks this ROM reads, 16: the build switch of `Boot.asm`.
SECTORS = 16

.cpu Mos6502

.include "Boot.asm"
