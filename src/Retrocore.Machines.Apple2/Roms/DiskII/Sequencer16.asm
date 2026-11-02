;; APPLE DISK II LOGIC STATE SEQUENCER, 16 SECTORS (P6, 341-0028)
;;
;; The state machine of the 16-sector Disk II controller, which reads and writes the 6-and-2 nibbles of DOS 3.3
;; and ProDOS. Those nibbles can have two 0 bits in a row, which the 13-sector sequencer cannot read.
;; Sequencer.asm describes the commands, the inputs and how the chip is wired, and holds the writing table, the
;; same on both cards; this file holds the reading table. docs/DiskII.md describes the controller.
;;
;; Assembles byte-identically to the 341-0028 PROM. Maintained by hand; DiskIISourceTests pin it by digest.

.include "Sequencer.asm"

; Reading. The read columns follow the read pulses (RP 0) and shift in a nibble, holding it once QA is 1. While QA is
; 1, state 2 waits without shifting until the next pulse: this is how the extra 0 bits after each self-sync $FF are
; discarded. State D with QA 0 waits for a cell without a pulse, so a run of 1 bits in every state holds it there,
; which some copy protection uses. The sense write protect columns shift the write-protect sensor in from the left,
; eight times over, so the latch reads $FF while the disk is protected and $00 otherwise; the 6502 tests bit 7.
;
;               read                                  sense write protect
;  QA RP:       00       01       10       11         00       01       10       11
    READING $0, NOP($1), NOP($1), NOP($1), NOP($1),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $1, SL1($2), SL1($2), NOP($3), NOP($3),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $2, NOP($D), NOP($3), NOP($0), NOP($2),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $3, NOP($D), NOP($4), NOP($4), NOP($4),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $4, NOP($D), NOP($5), NOP($D), NOP($5),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $5, NOP($D), NOP($6), NOP($D), NOP($6),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $6, NOP($D), NOP($7), NOP($D), NOP($7),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $7, NOP($D), NOP($8), NOP($D), NOP($8),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $8, NOP($D), NOP($9), NOP($D), NOP($9),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $9, NOP($D), SL0($2), NOP($D), NOP($A),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $A, SL1($C), SL1($B), NOP($D), NOP($B),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $B, SL0($D), SL0($5), NOP($D), NOP($C),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $C, SL0($D), SL0($D), NOP($D), CLR($A),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $D, NOP($D), NOP($0), NOP($E), NOP($E),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $E, SL1($F), SL1($F), NOP($F), NOP($F),   SR($0),  SR($0),  SR($0),  SR($0)
    READING $F, SL1($D), SL1($4), CLR($E), CLR($E),   SR($0),  SR($0),  SR($0),  SR($0)

    SEQUENCER
