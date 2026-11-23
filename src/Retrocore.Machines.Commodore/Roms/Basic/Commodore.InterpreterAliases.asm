; COMMODORE BASIC INTERPRETER ENTRY NAMES
;
; Commodore's names for shared interpreter entries, which resolve only in the PET builds that include this
; file. Each cites its documents by their keys in docs/Bibliography.md, as an Also: entry does: Commodore's BASIC 4
; listing of July 23, 1979 (CBM4S79), which gives them for BASIC 4, and Martin Hoffmann-Vetter's reconstructions of
; each PET BASIC (HV1, HV1R, HV2, HV4, HV4R), which give them for their own builds.

.cpu Mos6502

;; Copies a string's descriptor to the assigned variable.
;;
;; Commodore's name for <COPYZC>: COPYC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code6.
COPYC = COPYZC

;; Returns STR$(n).
;;
;; Commodore's name for <STR>: STRD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code14.
STRD = STR

;; Returns CHR$(n).
;;
;; Commodore's name for <CHR>: CHRD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code16.
CHRD = CHR

;; Returns LEFT$(string, count).
;;
;; Commodore's name for <LEFT>: LEFTD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code16.
LEFTD = LEFT

;; Returns RIGHT$(string, count).
;;
;; Commodore's name for <RIGHT>: RIGHTD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code16.
RIGHTD = RIGHT

;; Returns MID$(string, start [, length]).
;;
;; Commodore's name for <MID>: MIDD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code16.
MIDD = MID
