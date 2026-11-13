;; COCO 3 ENTRY POINTS, FOR THE PATCHES TO COLOR AND EXTENDED BASIC
;;
;; The CoCo 3's routines that its patches to Color and Extended BASIC call, as equates at their addresses.
;; Coco3.asm defines and documents each of them as a label, so it does not include this file; ColorBasic.asm and
;; ExtendedBasic.asm include it when COCO3 is set, and each definition here inherits Coco3.asm's documentation.

;; Inherit: <Coco3:COCO3RESET>
COCO3RESET = $C000

;; Inherit: <Coco3:HCLS>
HCLS = $F6AD

;; Inherit: <Coco3:HWAITKY>
HWAITKY = $F77E

;; Inherit: <Coco3:HPUTCHR>
HPUTCHR = $F7AE
