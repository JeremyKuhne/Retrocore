;; TRS-80 COLOR COMPUTER 3 EQUATES: THE GIME, THE CONSTANT PAGE AND SUPER EXTENDED BASIC'S RAM
;;
;; The CoCo 3's own I/O, the GIME's registers and their bits, the memory blocks BASIC maps, and the RAM Super
;; Extended BASIC adds, with the names Spectral Associates' Super Extended Basic Unravelled gives them. Coco3.asm
;; includes this file after Color and Extended BASIC's equates, and ColorBasic.asm and ExtendedBasic.asm include it
;; when COCO3 is set.

; ----------------------------------------------------------------------------------------------------------------
; The GIME
; ----------------------------------------------------------------------------------------------------------------

;; The GIME's first initialization register: the CoCo compatible mode, the MMU, the GIME's interrupts, the
;; constant page and the ROM's map.
;;
;; Its bits are <COCO>, <MMUEN>, <IEN>, <FEN>, <MC3>, <MC2>, and <MC1> and <MC0>, which map the ROM: 0x, 16K
;; internal and 16K from the cartridge; 10, 32K internal; 11, 32K from the cartridge.
;; See: <INIT1>
INIT0 = $FF90

;; INIT0's bit for the CoCo compatible mode: the video and the SAM's display bits work as the VDG's did.
COCO = $80

;; INIT0's bit that turns the MMU on, which maps each 8K of the 64K address space to a block of RAM or ROM.
;;
;; See: <MMUREG>
MMUEN = $40

;; INIT0's bit that lets the GIME's interrupts reach IRQ.
IEN = $20

;; INIT0's bit that lets the GIME's interrupts reach FIRQ.
FEN = $10

;; INIT0's bit that keeps $FE00-$FEFF in the last block of RAM whatever the MMU maps there: the constant page.
MC3 = $08

;; INIT0's bit for the standard cartridge select, SCS, at $FF40.
MC2 = $04

;; INIT0's high bit of the ROM map.
MC1 = $02

;; INIT0's low bit of the ROM map.
MC0 = $01

;; The MMU's registers: two sets of eight, for task 0 and task 1, each the block of RAM or ROM in one 8K of the
;; address space, $0000-$1FFF first.
;;
;; Blocks $38-$3F are the 64K a CoCo 2 program sees, and the internal ROM shows in $3C-$3F unless the SAM's map
;; type puts RAM there.
;; See: <MMUEN>, <BLOCK7_0>
MMUREG = $FFA0

;; The 64K block BASIC runs in: blocks $38 to $3F, mapped in order to $0000-$FFFF.
BLOCK7_0 = $38
BLOCK7_1 = $39                      ;; The second of BASIC's blocks, $2000-$3FFF.
BLOCK7_2 = $3A                      ;; The third of BASIC's blocks, $4000-$5FFF.
BLOCK7_3 = $3B                      ;; The fourth of BASIC's blocks, $6000-$7FFF.
BLOCK7_4 = $3C                      ;; The fifth of BASIC's blocks, $8000-$9FFF.
BLOCK7_5 = $3D                      ;; The sixth of BASIC's blocks, $A000-$BFFF.
BLOCK7_6 = $3E                      ;; The seventh of BASIC's blocks, $C000-$DFFF.
BLOCK7_7 = $3F                      ;; The last of BASIC's blocks, $E000-$FFFF, which holds the constant page.

; ----------------------------------------------------------------------------------------------------------------
; The constant page, $FE00-$FEFF
; ----------------------------------------------------------------------------------------------------------------

;; Whether the interrupt jumps at $FEEE are set up: $55 when they are.
;;
;; Start-up copies them from <INTIMAGE> when it is not $55; <CARTFIRQ> clears it before a ROM pack starts.
;; See: <INTIMAGE>
INT_FLAG = $FEED

;; The SWI3 vector's jump, in the constant page so it is there whatever the MMU maps.
INT_SWI3 = $FEEE
INT_SWI2 = $FEF1                    ;; The SWI2 vector's jump.
INT_FIRQ = $FEF4                    ;; The FIRQ vector's jump.
INT_IRQ = $FEF7                     ;; The IRQ vector's jump.
INT_SWI = $FEFA                     ;; The SWI vector's jump.
INT_NMI = $FEFD                     ;; The NMI vector's jump.

; ----------------------------------------------------------------------------------------------------------------
; The direct page
; ----------------------------------------------------------------------------------------------------------------

;; The hi-res graphics mode HSCREEN set, 0 when none is on; DLOAD's baud rate, <DLBAUD>, on a CoCo 2.
HRMODE = $E6

;; The hi-res text screen's width, 40 or 80, or 0 for the 32-column screen; DLOAD's timeout, <TIMOUT>, on a CoCo 2.
HRWIDTH = $E7
