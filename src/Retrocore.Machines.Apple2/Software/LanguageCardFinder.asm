;; DOS 3.3 SYSTEM MASTER LANGUAGE CARD FINDER
;;
;; The Apple II Plus or ROMCARD System Master's HELLO program, dated 08/25/80, POKEs these bytes into
;; $0300-$0340 in lines 90-125, then CALLs $0301 and checks the result at $0300. If the test passes, HELLO
;; loads INTBASIC at $D000 and reads $C082 to write-protect the card. This source preserves the POKEd bytes.

.cpu Mos6502

.include "../Roms/System/IIeEquates.asm"

.org $0300

;; HELLO reads this byte after CALL: 1 if the test passes, otherwise 0.
Status:
    .byte 0

;; Tests whether Language Card bank 2 retains two values at $D000.
;;
;; If the byte initially read at $E000 differs from the ROM's, the write test is skipped. The test overwrites
;; $D000 without restoring it. The saved $E000 byte also determines whether RAM is selected at the end.
;; Out:   Status = 1 if both values read back, otherwise 0
;; Uses:  A, $D000
;; Keeps: X, Y
Finder:
    lda $E000                       ; save the byte under the current mapping
    pha
    lda ROMIN                       ; select ROM for reading
    pla
    pha                             ; keep the original byte for the final comparison
    cmp $E000                       ; compare the original byte with the ROM
    bne Finder_Failed               ; skip the write test if they differ

    lda LCBANK2                     ; select bank 2 RAM for reading
    lda LCBANK2                     ; the second read enables writes
    lda #$A5
    sta $D000
    cmp $D000                       ; check the first pattern
    bne Finder_Failed

    lsr A                           ; $A5 becomes $52
    sta $D000
    cmp $D000                       ; check the second pattern
    bne Finder_Failed

    lda ROMIN                       ; select ROM for reading
    lda ROMIN                       ; keep bank 2 RAM write-enabled
    lda #1
    bne Finder_StoreStatus          ; always taken, as in HELLO

Finder_Failed:
    lda #0

Finder_StoreStatus:
    sta Status
    pla                             ; recover the original $E000 byte
    cmp $E000
    beq Finder_Done                 ; leave the current mapping if the byte matches
    lda LCRAM2                      ; otherwise select bank 2 RAM, with writes off

Finder_Done:
    rts

.assert Finder = $0301, "HELLO calls the finder at $0301."
.assert * = $0341, "HELLO pokes through $0340."
