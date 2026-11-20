;; PET BASIC 2 KERNAL ENTRY POINTS, FOR THE SCREEN EDITOR
;;
;; The kernal's entries that the editor calls, as equates at their addresses in the kernal ROM. Kernal2.asm defines
;; and documents each of them as a label, so it does not include this file; Editor2.asm does, and each definition
;; here inherits the kernal's documentation.

;; Inherit: <Kernal2:MON_RESUME>
MON_RESUME = $FD54

;; Inherit: <Kernal2:STRT>
STRT = $FD56

;; Inherit: <Kernal2:CQINCH>
CQINCH = $FFCF

;; Inherit: <Kernal2:OUTCH>
OUTCH = $FFD2

;; Inherit: <Kernal2:JUDTIM>
JUDTIM = $FFEA
