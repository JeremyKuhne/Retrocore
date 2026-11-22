; MICROSOFT 6502 BASIC: DIM STATEMENT

;; Consumes the comma between arrays in a DIM statement.
DIM3:
    jsr CHKCOM

;; Dimensions each array in a comma-separated DIM statement.
;;
;; <DIMFLG> tells the variable search to create arrays with the supplied bounds and reject a second DIM.
DIM:
    tax
DIM1:
    jsr PTRGT1
DIMCON:
    jsr CHRGOT
    bne DIM3
    rts
