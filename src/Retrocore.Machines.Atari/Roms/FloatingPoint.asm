;; ATARI 400/800 FLOATING POINT PACKAGE ($D800-$DFFF)
;;
;; The 2K chip below the OS, the same in every 400/800 OS (co12399b): arithmetic on six-byte BCD numbers, ten digits
;; and a power of 100, in FR0 and FR1, through the entry points the OS User's Manual documents (section 8) at fixed
;; addresses. Atari BASIC does all its arithmetic with it, and uses its constant tables by address. The ROM is in parts,
;; each in its own file in FloatingPoint, in the order they sit in the ROM:
;;
;; - Conversion.asm ($D800-$DA43): AFP, FASC, IFP and FPI, between numbers and text or integers.
;; - Arithmetic.asm ($DA44-$DD3F): ZFR0, ZF1, FSUB, FADD, FMUL and FDIV, with the helpers the other parts share.
;; - Functions.asm ($DD40-$DFFF): PLYEVL, the loads and stores, EXP, EXP10, LOG and LOG10, and the constants.
;;
;; The registers and buffers it uses (FR0-FR2, FRE, LBUFF and the rest) are in OsEquates.asm, with the number format.
;; Names follow the manual for the entry points and the database; other labels are named after what the code does.
;;
;; Maintained by hand. AtariFloatingPointSourceTests check that it assembles byte-identically to the chip.

.cpu Mos6502

.include "OsEquates.asm"

.org $D800

.include "FloatingPoint/Conversion.asm"
.include "FloatingPoint/Arithmetic.asm"
.include "FloatingPoint/Functions.asm"
