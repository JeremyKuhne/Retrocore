; COMMODORE BASIC FLOATING-POINT NAMES
;
; Commodore's names for shared floating-point constants, which resolve only in the PET builds that include this
; file. Each cites its documents by their keys in docs/Bibliography.md, as an Also: entry does: Commodore's BASIC 4
; listing of July 23, 1979 (CBM4S79), which gives them for BASIC 4, and Martin Hoffmann-Vetter's reconstructions of
; each PET BASIC (HV1, HV1R, HV2, HV4, HV4R), which give them for their own builds.

.cpu Mos6502

;; The packed square root of one half.
;;
;; Commodore's name for <SQRHLF>: SQR05 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code18.
SQR05 = SQRHLF

;; The packed square root of two.
;;
;; Commodore's name for <SQRTWO>: SQR20 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code18.
SQR20 = SQRTWO

;; The packed constant ten.
;;
;; Commodore's name for <TENZC>: TENC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code19.
TENC = TENZC

;; The packed lower decimal-output threshold.
;;
;; Commodore's name for <NZ0999>: N0999 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code22.
N0999 = NZ0999

;; The packed upper decimal-output threshold.
;;
;; Commodore's name for <NZ9999>: N9999 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code22.
N9999 = NZ9999

;; The packed constant one billion.
;;
;; Commodore's name for <NZMIL>: NMIL (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code22.
NMIL = NZMIL

;; The random-number multiplier.
;;
;; Commodore's name for <RMULZC>: RMULC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code25.
RMULC = RMULZC

;; The random-number addend.
;;
;; Commodore's name for <RADDZC>: RADDC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), in code25.
RADDC = RADDZC
