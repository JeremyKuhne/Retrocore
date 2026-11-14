;; SOFTCARD /// ADDRESS MAPPING PROM
;;
;; Microsoft's SoftCard /// puts a Z80 on an Apple III slot card. The Z80 has no memory of its own: it reaches the
;; Apple III's memory by DMA, through the 6502's view of it, so the bank register and the zero-page register apply.
;; This 256-byte PROM maps each Z80 page to an Apple page. The card puts the Z80's low address byte on the bus
;; unchanged and the PROM's entry for its high byte above it.
;;
;; The map:
;;
;;   Z80 $0000-$DEFF  Apple $2000-$FEFF: the switchable bank, then the system bank, with the I/O page at Z80 $A000
;;   Z80 $DF00-$EFFF  Apple $1000-$1FFF in another order, with the vectors' page, $FF, at Z80 $E400
;;   Z80 $F000-$FFFF  Apple $0000-$0FFF: zero page (wherever the zero-page register puts it), the stack and the
;;                    text screen
;;
;; Maintained by hand. SoftCard3Tests check that it assembles byte-identically to the PROM (MAME's softcard3.rom).

.cpu Z80

;; Maps COUNT Z80 pages, from Z80 page FIRST, to Apple pages counting up from APPLE.
.macro PAGES first, apple, count
    .assert * = (first), "PAGES are out of order."
.repeat count, N
    .byte (apple) + N
.endrepeat
.endmacro

.org $0000

    PAGES $00, $20, $DF     ; Z80 $0000-$DEFF: Apple $2000-$FEFF
    PAGES $DF, $16, 1
    PAGES $E0, $10, 4       ; Z80 $E000-$E3FF: Apple $1000-$13FF
    PAGES $E4, $FF, 1       ; Z80 $E400: the vectors' page
    PAGES $E5, $14, 2       ; Z80 $E500-$E6FF: Apple $1400-$15FF
    PAGES $E7, $17, 9       ; Z80 $E700-$EFFF: Apple $1700-$1FFF
    PAGES $F0, $00, $10     ; Z80 $F000-$FFFF: Apple $0000-$0FFF
