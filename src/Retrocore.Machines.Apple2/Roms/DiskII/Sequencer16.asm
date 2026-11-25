; retrocore: style=strict
;; Apple Disk II logic state sequencer, 16 sectors (P6, 341-0028)
;;
;; The state machine of the 16-sector Disk II controller, which reads and writes the 6-and-2 nibbles of DOS 3.3
;; and ProDOS. Those nibbles can have two 0 bits in a row, which the 13-sector sequencer cannot read.
;; Sequencer.asm describes the commands, the inputs and how the chip is wired, and holds the writing table, the
;; same on both cards; this file holds the reading table. docs/DiskII.md describes the controller.
;;
;; Assembles byte-identically to the 341-0028 PROM. Maintained by hand; DiskIISourceTests pin it by digest.

.include "Sequencer.asm"

    ; Reading. The read columns follow the read pulses (RP 0) and shift in a nibble, holding it once QA is 1. While
    ; QA is 1, state 2 waits without shifting until the next pulse: this is how the extra 0 bits after each
    ; self-sync $FF are discarded. State D with QA 0 waits for a cell without a pulse, so a run of 1 bits in every
    ; state holds it there, which some copy protection uses. The sense write protect columns shift the write-protect
    ; sensor in from the left, eight times over, so the latch reads $FF while the disk is protected and $00
    ; otherwise; the 6502 tests bit 7.
    ;
    ;              read                                             sense write protect
    ;  QA RP:      00          01          10          11           00          01          10          11
    ReadState  $0, Hold($1),   Hold($1),   Hold($1),   Hold($1),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $1, Shift1($2), Shift1($2), Hold($3),   Hold($3),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $2, Hold($D),   Hold($3),   Hold($0),   Hold($2),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $3, Hold($D),   Hold($4),   Hold($4),   Hold($4),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $4, Hold($D),   Hold($5),   Hold($D),   Hold($5),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $5, Hold($D),   Hold($6),   Hold($D),   Hold($6),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $6, Hold($D),   Hold($7),   Hold($D),   Hold($7),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $7, Hold($D),   Hold($8),   Hold($D),   Hold($8),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $8, Hold($D),   Hold($9),   Hold($D),   Hold($9),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $9, Hold($D),   Shift0($2), Hold($D),   Hold($A),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $A, Shift1($C), Shift1($B), Hold($D),   Hold($B),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $B, Shift0($D), Shift0($5), Hold($D),   Hold($C),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $C, Shift0($D), Shift0($D), Hold($D),   Clear($A),   Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $D, Hold($D),   Hold($0),   Hold($E),   Hold($E),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $E, Shift1($F), Shift1($F), Hold($F),   Hold($F),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $F, Shift1($D), Shift1($4), Clear($E),  Clear($E),   Sense($0),  Sense($0),  Sense($0),  Sense($0)

    EmitChip
