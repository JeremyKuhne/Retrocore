; COMMODORE BASIC FLOATING-POINT NAMES
;
; Commodore's July 23, 1979 BASIC 4 source, code18, code19, code22 and code25:
; https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V4_1979-07-23
; The same names appear in M. Hoffmann-Vetter's reconstructions, in code18, code19, code22 and code25:
; https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168
; (folders BASIC_PET_V1_REC, BASIC_PET_V1R_REC, BASIC_PET_V2_REC and BASIC_PET_V4R_REC).

.cpu Mos6502

SQR05 = SQRHLF                      ;; Commodore BASIC 4 code18 name for the square-root-of-one-half constant.
SQR20 = SQRTWO                      ;; Commodore BASIC 4 code18 name for the square-root-of-two constant.
TENC = TENZC                        ;; Commodore BASIC 4 code19 name for the packed constant ten.
N0999 = NZ0999                      ;; Commodore BASIC 4 code22 name for the lower decimal-output threshold.
N9999 = NZ9999                      ;; Commodore BASIC 4 code22 name for the upper decimal-output threshold.
NMIL = NZMIL                        ;; Commodore BASIC 4 code22 name for the packed constant one billion.
RMULC = RMULZC                      ;; Commodore BASIC 4 code25 name for the random multiplier.
RADDC = RADDZC                      ;; Commodore BASIC 4 code25 name for the random addend.
