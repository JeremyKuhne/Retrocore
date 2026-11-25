; retrocore: style=strict
;; DOS 3.3 System Master: the language card finder
;;
;; The Apple II Plus or ROMCARD System Master's HELLO program, dated 08/25/80, POKEs these bytes into $0300-$0340 in
;; lines 90-125, then CALLs $0301 (<TestLanguageCard>) and checks the result at $0300 (<Status>). If the test passes,
;; HELLO loads INTBASIC at $D000 and reads $C082 to write-protect the card. This source preserves the POKEd bytes;
;; its names are the SDK's own. SystemMasterBasicTests pin it by digest.
;;
;; A language card puts 16K of RAM in place of the ROM at $D000-$FFFF: two 4K banks at $D000-$DFFF and 8K at
;; $E000-$FFFF. Its switches are at $C080-$C08F; ../Roms/System/IIeEquates.asm names the ones this test reads.

.cpu Mos6502

.include "../Roms/System/IIeEquates.asm"

;; The first byte of the language card's 4K banks, which the test writes.
BankByte = $D000

;; A byte of the language card's shared 8K, which tells the ROM from the card's RAM: the test compares it before and
;; after it selects the ROM.
SharedByte = $E000

;; The first value the test writes; it shifts it right for the second, $52.
TEST_PATTERN = $A5

;; <Status> when both values read back: a language card is there.
STATUS_FOUND = 1

;; <Status> when the test fails or is skipped.
STATUS_NOT_FOUND = 0

.org $0300

;; HELLO reads this byte after CALL: <STATUS_FOUND> if the test passes, otherwise <STATUS_NOT_FOUND>.
Status:
    .byte 0

;; Tests whether language card bank 2 keeps two values written at <BankByte>.
;;
;; If the byte read at <SharedByte> under the current mapping differs from the ROM's, the write test is skipped. The
;; test overwrites <BankByte> without restoring it. At the end it compares the byte first read at <SharedByte> with
;; <SharedByte> under the mapping it has left: the ROM after a skipped or passed test, bank 2 RAM after a failed
;; write. If they match it keeps that mapping; otherwise it selects bank 2 RAM for reading, with writes off.
;; Out:   Status = <STATUS_FOUND> if both values read back, otherwise <STATUS_NOT_FOUND>
;; Uses:  A, BankByte
;; Keeps: X, Y
.proc TestLanguageCard

    ; Save the byte under the current mapping, then compare it with the ROM's.
    lda SharedByte
    pha
    lda LanguageCardRomWriteBank2   ; select ROM for reading
    pla
    pha                             ; keep the original byte for the final comparison
    cmp SharedByte
    bne Failed                      ; skip the write test if they differ

    ; Write two values to bank 2 and read each back.
    lda LanguageCardBank2ReadWrite  ; select bank 2 RAM for reading
    lda LanguageCardBank2ReadWrite  ; the second read enables writes
    lda #TEST_PATTERN
    sta BankByte
    cmp BankByte
    bne Failed

    lsr a                           ; $A5 becomes $52
    sta BankByte
    cmp BankByte
    bne Failed

    ; Passed: select the ROM again.
    lda LanguageCardRomWriteBank2   ; select ROM for reading
    lda LanguageCardRomWriteBank2   ; keep bank 2 RAM write-enabled
    lda #STATUS_FOUND
    bne StoreStatus                 ; always taken, as in HELLO

Failed:
    lda #STATUS_NOT_FOUND

StoreStatus:
    sta Status

    ; Keep the current mapping if it shows the original byte; otherwise select bank 2 RAM.
    pla
    cmp SharedByte
    beq Done
    lda LanguageCardBank2ReadOnly   ; select bank 2 RAM, with writes off

Done:
    rts
.endproc

.assert TestLanguageCard = $0301, "HELLO calls the finder at $0301."
.assert * = $0341, "HELLO pokes through $0340."
