;; PET BASIC 4 KERNAL ENTRY POINTS, FOR THE SCREEN EDITORS
;;
;; The kernal's entries that the editors call, as equates at their addresses in the kernal ROM. Kernal4.asm defines
;; and documents each of them as a label, so it does not include this file; Editor4.asm does, and each definition
;; here inherits the kernal's documentation.

;; Inherit: <Kernal4:UDTIM>
UDTIM = $F768
