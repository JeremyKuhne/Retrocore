; Page zero not in IIeEquates.asm, because DOS has names of its own spelled the same. The firmware inherits these.
;; The high byte of the pointer at <LOC0>.
;;
;; <PWRUP> counts it down from $C7 to $C1 as it tries each slot. On the Enhanced IIe, the interrupt return code
;; at <VIDSYNC_1@Enhanced> points it briefly at a slot's $Cn00 page to select that slot's $C800 ROM, then restores it.
;; See: <LOC0>, <MSLOT>
LOC1 = $01

;; The cursor's line on the screen, 0-23.
;;
;; It counts from the top of the screen, not of the window. <TABV>, <UP> and <LF> change it, and <VTAB> sets
;; <BASL>/<BASH> for it. The 80-column firmware keeps a copy in <Firmware:OURCV>.
;; See: <CH>, <BASL>, <WNDTOP>, <WNDBTM>, <VTAB>
CV = $25

; The internal firmware's entries, CLRROM (a label in the Enhanced IIe's firmware) and AppleSoft's entries.
B_FUNC = $C100
BASICIN = $C305
IRQHANDLER = $C3FA
IRQRESTORE = $C47C
TAPEHEADR = $C567
WRITETAPE = $C5AA
READTAPE = $C5D1
MINILINE = $CF9C
CLRROM = $CFFF                      ;; releases the $C800 expansion ROM
BASIC = $E000                       ;; AppleSoft cold start
BASIC2 = $E003                      ;; AppleSoft warm start
.if MONITOR = MONITOR_II

; Names the Apple II Monitor's listing gives page zero for STEP and the multiply and divide routines.
;; The low byte of the Monitor command line's return address while STEP runs a user instruction.
;;
;; <STEP> pops the address its caller left on the stack into <RTNL>/<RTNH>, so the user's instruction
;; sees the user's stack, and <RTNJMP> pushes it back. The same bytes are <H2> and <V2>.
;; See: <RTNH>, <STEP>, <RTNJMP>
RTNL = $2C

;; The high byte of the return address <STEP> keeps at <RTNL>.
;; See: <RTNL>, <STEP>
RTNH = $2D

;; The sign count of <MULPM> and <DIVPM>: bit 0 is set when the result is negative.
;;
;; <MD1> clears it and adds one for each operand it makes positive; the caller applies the sign. The
;; same byte is <LENGTH>.
;; See: <MD1>, <MULPM>, <DIVPM>
SIGN = $2F

;; The nine bytes where STEP runs one user instruction, $3C-$44.
;;
;; <STEP> copies the instruction here, padded with NOPs and followed by jumps to <NBRNCH> and <BRANCH>
;; from <INITBL>, then jumps here. The area overlaps <A1L> through <A5L>.
;; See: <STEP>, <INITBL>
XQT = $3C

;; The low byte of the 16-bit accumulator of <MUL> and <DIV>.
;;
;; It holds the multiplier or dividend on entry and the low half of the product, or the quotient, on
;; return.
;; See: <ACH>, <XTNDL>, <AUXL>, <MUL>, <DIV>
ACL = $50

;; The high byte of the 16-bit accumulator at <ACL>.
;; See: <ACL>
ACH = $51

;; The low byte of the 16-bit extension of <MUL> and <DIV>.
;;
;; <MUL> adds it to the product and returns the product's high half here; <DIV> takes it as the high
;; half of the dividend and returns the remainder here.
;; See: <XTNDH>, <ACL>, <MUL>, <DIV>
XTNDL = $52

;; The high byte of the extension at <XTNDL>.
;; See: <XTNDL>
XTNDH = $53

;; The low byte of the 16-bit multiplicand or divisor of <MUL> and <DIV>.
;; See: <AUXH>, <ACL>, <MUL>, <DIV>
AUXL = $54

;; The high byte of the multiplicand or divisor at <AUXL>.
;; See: <AUXL>
AUXH = $55
.endif
