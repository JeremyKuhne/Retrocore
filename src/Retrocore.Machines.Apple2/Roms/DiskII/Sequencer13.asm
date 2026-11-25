; retrocore: style=strict
;; Apple Disk II logic state sequencer, 13 sectors (P6, 341-0010)
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

    ; Reading. The read columns follow the read pulses (RP 0) and shift in a nibble, holding it once QA is 1. The sense
    ; write protect columns shift the write-protect sensor in from the left, eight times over, so the latch reads $FF
    ; while the disk is protected and $00 otherwise; the 6502 tests bit 7.
    ;
    ;              read                                             sense write protect
    ;  QA RP:      00          01          10          11           00          01          10          11
    ReadState  $0, Hold($D),   Hold($1),   Hold($1),   Hold($0),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $1, Hold($D),   Hold($2),   Hold($2),   Hold($2),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $2, Hold($D),   Hold($3),   Hold($3),   Hold($3),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $3, Hold($D),   Hold($4),   Hold($D),   Hold($4),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $4, Hold($D),   Hold($5),   Hold($D),   Hold($5),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $5, Hold($D),   Hold($6),   Hold($D),   Hold($6),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $6, Hold($D),   Hold($7),   Hold($D),   Hold($7),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $7, Hold($D),   Hold($8),   Hold($D),   Hold($8),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $8, Hold($D),   Hold($9),   Hold($D),   Hold($9),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $9, Hold($D),   Shift0($0), Hold($D),   Hold($A),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $A, Shift1($C), Shift1($B), Hold($D),   Hold($B),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $B, Shift0($D), Shift0($3), Hold($D),   Hold($C),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $C, Shift0($D), Shift0($D), Hold($D),   Clear($A),   Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $D, Shift1($1), Shift1($0), Hold($E),   Hold($E),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $E, Shift1($F), Shift1($F), Hold($F),   Hold($F),    Sense($0),  Sense($0),  Sense($0),  Sense($0)
    ReadState  $F, Shift1($D), Shift1($4), Clear($E),  Clear($E),   Sense($0),  Sense($0),  Sense($0),  Sense($0)

    EmitChip
