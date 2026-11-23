; COMMODORE BASIC INTERPRETER ENTRY NAMES
;
; Commodore's July 23, 1979 BASIC 4 source, code6, code14 and code16:
; https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V4_1979-07-23
; The same names appear in M. Hoffmann-Vetter's reconstructions, in the corresponding code files:
; https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168
; (folders BASIC_PET_V1_REC, BASIC_PET_V1R_REC, BASIC_PET_V2_REC and BASIC_PET_V4R_REC).

.cpu Mos6502

COPYC = COPYZC                      ;; Commodore BASIC 4 code6 name for the descriptor-copy entry.
STRD = STR                          ;; Commodore BASIC 4 code14 name for STR$.
CHRD = CHR                          ;; Commodore BASIC 4 code16 name for CHR$.
LEFTD = LEFT                        ;; Commodore BASIC 4 code16 name for LEFT$.
RIGHTD = RIGHT                      ;; Commodore BASIC 4 code16 name for RIGHT$.
MIDD = MID                          ;; Commodore BASIC 4 code16 name for MID$.
