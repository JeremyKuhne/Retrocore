;; APPLESOFT: PROGRAM LISTING
;;
;; LIST accepts a comma or minus token between its bounds and surrounds expanded words with spaces.
;; The enhanced IIe uses the width-aware helpers; both builds use the page-carrying <RESLST> walker.

.include "../Microsoft6502Basic/MsBasic.Lister.asm"

    ListRange 1, STKRTS
.if ENHNCD
    ListLines 0, 0, 2, SPCLIN, 1, NXTCO1
.else
    ListLines 0, 0, 1, LINPRT, 1, NXTCO1
.endif
    ListNextTableByte
    ListTokens 2, 0, 0, 1
