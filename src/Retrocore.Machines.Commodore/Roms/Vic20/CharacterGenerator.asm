;; COMMODORE VIC-20 CHARACTER ROM 901460-03
;;
;; The VIC-20's character ROM is the PET's 2001-N set with a pound sign and reversed copies; the shared source draws
;; both (see its header). This root selects the VIC-20's chip, 4K at the VIC's $0000-$0FFF (the processor's
;; $8000-$8FFF).
;;
;; Maintained by hand; Vic20RomSourceTests checks that it assembles byte-identically.

VIC20 = 1

.include "../CharacterGenerator.asm"

.assert * = $1000, "The VIC-20's character ROM is 4K."
