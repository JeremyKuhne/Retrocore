;; APPLE DISK II LOGIC STATE SEQUENCER, 13 SECTORS (P6, 341-0010)
;;
;; The state machine of the first Disk II controller, for the 5-and-3 nibbles of DOS 3.1 to 3.2.1, which never
;; have two 0 bits in a row. The 16-sector upgrade replaced it, with the boot ROM, to read the 6-and-2 nibbles
;; that can. Sequencer.asm describes the commands, the inputs and how the chip is wired, and holds the writing
;; table, the same on both cards; this file holds the reading table. docs/DiskII.md describes the controller.
;;
;; Assembles byte-identically to the 341-0010 PROM as the card wires it. The known dump of the chip is in the order
;; the boot ROM's socket reads it, with address lines A5 and A7 exchanged and data lines D7-D4 reversed;
;; DiskIISourceTests put those lines back to compare with it, and pin the build by digest. Maintained by hand.

.include "Sequencer.asm"

; Reading. The read columns follow the read pulses (RP 0) and shift in a nibble, holding it once QA is 1. The
; sense write protect columns shift the write-protect sensor in from the left, eight times over, so the
; latch reads $FF while the disk is protected and $00 otherwise; the 6502 tests bit 7.
;
;               read                                  sense write protect
;  QA RP:       00       01       10       11         00       01       10       11
    READING $0, NOP($D), NOP($1), NOP($1), NOP($0),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $1, NOP($D), NOP($2), NOP($2), NOP($2),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $2, NOP($D), NOP($3), NOP($3), NOP($3),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $3, NOP($D), NOP($4), NOP($D), NOP($4),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $4, NOP($D), NOP($5), NOP($D), NOP($5),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $5, NOP($D), NOP($6), NOP($D), NOP($6),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $6, NOP($D), NOP($7), NOP($D), NOP($7),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $7, NOP($D), NOP($8), NOP($D), NOP($8),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $8, NOP($D), NOP($9), NOP($D), NOP($9),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $9, NOP($D), SL0($0), NOP($D), NOP($A),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $A, SL1($C), SL1($B), NOP($D), NOP($B),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $B, SL0($D), SL0($3), NOP($D), NOP($C),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $C, SL0($D), SL0($D), NOP($D), CLR($A),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $D, SL1($1), SL1($0), NOP($E), NOP($E),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $E, SL1($F), SL1($F), NOP($F), NOP($F),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $F, SL1($D), SL1($4), CLR($E), CLR($E),   SR($0),  SR($0),  SR($0),  SR($0)

    SEQUENCER
