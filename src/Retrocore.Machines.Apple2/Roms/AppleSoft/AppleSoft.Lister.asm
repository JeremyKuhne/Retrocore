;; APPLESOFT: PROGRAM LISTING
;;
;; LIST accepts a comma or minus token between its bounds and surrounds expanded words with spaces.
;; The enhanced IIe uses the width-aware helpers; both builds use the page-carrying <RESLST> walker.

.include "../Microsoft6502Basic/MsBasic.Lister.asm"

    LIST_RANGE 1, STKRTS
.if ENHNCD
    LIST_LINES 0, 0, 2, SPCLIN, 1, NXTCO1
.else
    LIST_LINES 0, 0, 1, LINPRT, 1, NXTCO1
.endif
    LIST_TABLE_NEXT
    LIST_TOKENS 2, 0, 0, 1
