;; COUNT ON THE Z80 SOFTCARD
;;
;; Counts from 0 to 9, over and over, in the top-left corner of the Apple's text screen, from the
;; SoftCard's Z80. Debug it with the "II Plus: SoftCard Z80 sample" launch configuration: the source
;; loads at $0100, where the Z80's addresses reach the Apple's $1100, and the Z80 takes the bus at
;; START. It runs on the "SoftCard Z80" thread; the 6502 waits on its own.

.cpu Z80

SCREEN = $F400                      ;; the Apple's text page one, $0400, as the Z80 sees it
ZERO = $B0                          ;; "0" in the Apple's normal text

START:
    LD A,ZERO
SHOW:
    LD [SCREEN],A
    CALL NEXT
    JR SHOW

;; Steps A to the next digit, from "9" back to "0".
NEXT:
    INC A
    CP ZERO + 10
    RET NZ
    LD A,ZERO
    RET
