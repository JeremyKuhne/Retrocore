; retrocore: style=strict
;; The PET's video RAM and I/O chips and its kernal's jump table
;;
;; A project includes it as <machine.inc> on every PET: the 2001 with BASIC 1 or 2 and the 4032. It includes the SDK's
;; PetEquates.asm, the video RAM and the two PIAs and the VIA, named after the chips' data sheets, then adds the
;; entries of the kernal's jump table at $FFC0 that a program calls for the screen and keyboard. The jump table is at
;; the same addresses in every PET's kernal, so these work on each model; each inherits BASIC 4's kernal's
;; documentation, takes the name PET BASIC's own sources give it, and keeps Microsoft's and Commodore's names.
;;
;; The screen and keyboard take PETSCII, not ASCII: letters from $41 to $5A are capitals, and $0D is Return.

.assert .defined(RC_MACHINE_PET), "machine.inc for the PET is for targets whose machine is a PET."

.include <Roms/Pet/PetEquates.asm>

; The kernal's jump table.

;; Inherit: <Kernal4:CQINCH>
;; Also: CQINCH (M6502), CINCH (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalCharacterIn = $FFCF

;; Inherit: <Kernal4:OUTCH>
;; Also: OUTCH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KernalCharacterOut = $FFD2

;; Inherit: <Kernal4:CZGETL>
;; Also: CZGETL (M6502), CGETL (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
GetCharacter = $FFE4

; PETSCII.

;; Clears the screen and homes the cursor, written with <KernalCharacterOut>.
CLEAR_SCREEN = $93
