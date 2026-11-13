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

;; The GIME's second initialization register: the timer's clock, in bit 5, and which of the MMU's two tasks maps
;; the address space, in bit 0.
;;
;; See: <MMUREG>, <SELTASK0>, <SELTASK1>
INIT1 = $FF91

;; Which of the GIME's interrupts reach IRQ: <TMR>, <HBORD>, <VBORD>, <EI2>, <EI1> and <EI0>.
IRQENR = $FF92

;; Which of the GIME's interrupts reach FIRQ, with the same bits as <IRQENR>.
FIRQENR = $FF93

;; The GIME's interrupt bit for its timer.
TMR = $20

;; The GIME's interrupt bit for the horizontal border.
HBORD = $10

;; The GIME's interrupt bit for the vertical border.
VBORD = $08

;; The GIME's interrupt bit for serial data.
EI2 = $04

;; The GIME's interrupt bit for the keyboard.
EI1 = $02

;; The GIME's interrupt bit for the cartridge.
EI0 = $01

;; The GIME's 12-bit timer, high byte first: writing it starts it counting down.
V_TIMER = $FF94

;; The GIME's video mode register: graphics or text, the alternate color set, and lines per row.
;;
;; <VIDEOREG>+1, $FF99, sets the resolution: the lines, bytes per row and colors, or the text's width and
;; attributes. <SETTEXT> and <SETGRAPH> write the eight registers from $FF98 from their images.
;; See: <VIDIMAGE>, <SETVIDEO>
VIDEOREG = $FF98

;; The border's color, a palette value.
V_BORDER = $FF9A

;; The vertical scroll: the first line of each row that shows.
V_SCROLL = $FF9C

;; The high byte of where the display starts in RAM, in units of eight bytes.
V_OFSET1 = $FF9D

;; The low byte of where the display starts in RAM.
V_OFSET0 = $FF9E

;; The horizontal offset, for a screen wider than the display.
H_OFSET0 = $FF9F

;; The MMU's registers: two sets of eight, for task 0 and task 1, each the block of RAM or ROM in one 8K of the
;; address space, $0000-$1FFF first.
;;
;; Blocks $38-$3F are the 64K a CoCo 2 program sees, and the internal ROM shows in $3C-$3F unless the SAM's map
;; type puts RAM there.
;; See: <MMUEN>, <BLOCK7_0>
MMUREG = $FFA0

;; The palette's sixteen registers, $FFB0-$FFBF: each the color, six bits, that a pixel or character's color
;; number shows.
;;
;; See: <PALETTE>, <PALIMAGE>
PALETREG = $FFB0

;; The hi-res graphics screen's first block: blocks $30-$33, 32K, which task 1 maps at <HRESSCRN>.
BLOCK6_0 = $30
BLOCK6_1 = $31                      ;; The hi-res graphics screen's second block.
BLOCK6_2 = $32                      ;; The hi-res graphics screen's third block.
BLOCK6_3 = $33                      ;; The hi-res graphics screen's last block.
BLOCK6_4 = $34                      ;; HGET and HPUT's buffers, at <HRESBUFF>; start-up's RAM.
BLOCK6_5 = $35                      ;; The block task 1 keeps its stack in, at <TMPSTACK>.
BLOCK6_6 = $36                      ;; The block the hi-res text screen is in, which <SELTEXT> maps at <HRESSCRN>.
BLOCK6_7 = $37                      ;; A block BASIC leaves free.

;; The 64K block BASIC runs in: blocks $38 to $3F, mapped in order to $0000-$FFFF.
BLOCK7_0 = $38
BLOCK7_1 = $39                      ;; The second of BASIC's blocks, $2000-$3FFF.
BLOCK7_2 = $3A                      ;; The third of BASIC's blocks, $4000-$5FFF.
BLOCK7_3 = $3B                      ;; The fourth of BASIC's blocks, $6000-$7FFF.
BLOCK7_4 = $3C                      ;; The fifth of BASIC's blocks, $8000-$9FFF.
BLOCK7_5 = $3D                      ;; The sixth of BASIC's blocks, $A000-$BFFF.
BLOCK7_6 = $3E                      ;; The seventh of BASIC's blocks, $C000-$DFFF.
BLOCK7_7 = $3F                      ;; The last of BASIC's blocks, $E000-$FFFF, which holds the constant page.

;; Where task 1 and <SELTEXT> map the hi-res screens: graphics from here to $9FFF, text to $3FFF.
HRESSCRN = $2000

;; Where task 1 maps <BLOCK6_4>, the HGET and HPUT buffers.
HRESBUFF = $C000

;; The top of the stack task 1 uses while hi-res graphics commands run: the top of <BLOCK6_5>.
TMPSTACK = $DFFF

;; The rows on the 40 and 80-column screens.
ROWMAX = 24

;; The character the hi-res text screen's cursor shows.
CURCHAR = ' '

;; The first command token Super Extended BASIC adds, past Disk BASIC's: $E2, less $80.
EBHITOK = $62

;; The first function token Super Extended BASIC adds, less $80.
EBHISTOK = $29

; ----------------------------------------------------------------------------------------------------------------
; An HGET and HPUT buffer's header, which HBUFF makes: buffers follow each other from <HRESBUFF>, each pointing
; to the next.
; ----------------------------------------------------------------------------------------------------------------

;; The address of the next buffer, $0000 after the last.
HB_ADDR = 0

;; The buffer's number.
HB_NUM = 2

;; The buffer's size in bytes.
HB_SIZE = 3

;; The header's length.
HB_LEN = 5

; ----------------------------------------------------------------------------------------------------------------
; The start-up's RAM, in block $34 at $4000-$5FFF while it runs
; ----------------------------------------------------------------------------------------------------------------

;; The stack pointer, kept while <ROMTORAM> borrows S.
COPYSTK = $5F00

;; The end of the range <ROMTORAM> copies.
COPYEND = $5F02

; ----------------------------------------------------------------------------------------------------------------
; Disk BASIC, which start-up patches when the cartridge port has it
; ----------------------------------------------------------------------------------------------------------------

;; Where Disk BASIC keeps DSKCON's address: its high byte is $D6 in 1.0 and $D7 in 1.1.
DCNVEC = $C004

;; Disk BASIC 1.0's cold start where it loads the sign-on: <DSKPATCH> jumps from here to <DISK20MS>.
DSKSIGNON10 = $C0C6

;; Disk BASIC 1.1's cold start where it loads the sign-on: <DSKPATCH> jumps from here to <DISK21MS>.
DSKSIGNON11 = $C0D9

;; Disk BASIC 1.1's statement loop where it checks the keyboard quickly: <DSKPATCH> fills its eleven bytes with NOP.
DVEC20_KEYS11 = $C8B4

; ----------------------------------------------------------------------------------------------------------------
; The constant page, $FE00-$FEFF
; ----------------------------------------------------------------------------------------------------------------

;; The hi-res text cursor's address, in the screen as <SELTEXT> maps it.
H_CRSLOC = $FE00

;; The hi-res text cursor's column.
H_CURSX = $FE02

;; The hi-res text cursor's row.
H_CURSY = $FE03

;; The hi-res text screen's columns: 40 or 80.
H_COLUMN = $FE04

;; The hi-res text screen's rows.
H_ROW = $FE05

;; The end of the hi-res text screen, plus one.
H_DISPEN = $FE06

;; The attributes characters are printed with on the hi-res text screen: the foreground and background colors,
;; blinking and underlining, as ATTR sets them.
H_CRSATT = $FE08

;; The hi-res graphics' foreground color, as HCOLOR sets it.
H_FCOLOR = $FE0A

;; The hi-res graphics' background color, as HCOLOR sets it.
H_BCOLOR = $FE0B

;; The line ON BRK GOTO goes to, or 0.
H_ONBRK = $FE0C

;; The line ON ERR GOTO goes to, or 0.
H_ONERR = $FE0E

;; The last error's code, which ERNO returns, or $FF for none.
H_ERROR = $FE10

;; The line the ON ERR statement is in.
H_ONERRS = $FE11

;; The line the last error was in, which ERLIN returns.
H_ERLINE = $FE13

;; The line the ON BRK statement is in.
H_ONBRKS = $FE15

;; Whether ON ERR or ON BRK is taking over: 0 for an error, nonzero for BREAK.
H_ERRBRK = $FE17

;; The characters in <H_PBUF> that HPRINT still has to draw.
H_PCOUNT = $FE18

;; HPRINT's buffer: the text it draws on the graphics screen, up to 80 characters.
H_PBUF = $FE19

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

; ----------------------------------------------------------------------------------------------------------------
; Tokens and error codes
; ----------------------------------------------------------------------------------------------------------------

;; Tokens: Super Extended BASIC's commands follow Disk BASIC's, from $E2, in the order of <COMDIC20>.
TK_WIDTH = $E2                      ;; WIDTH
TK_PALETTE = $E3                    ;; PALETTE
TK_HSCREEN = $E4                    ;; HSCREEN
TK_LPOKE = $E5                      ;; LPOKE
TK_HCLS = $E6                       ;; HCLS
TK_HCOLOR = $E7                     ;; HCOLOR
TK_HPAINT = $E8                     ;; HPAINT
TK_HCIRCLE = $E9                    ;; HCIRCLE
TK_HLINE = $EA                      ;; HLINE
TK_HGET = $EB                       ;; HGET
TK_HPUT = $EC                       ;; HPUT
TK_HBUFF = $ED                      ;; HBUFF
TK_HPRINT = $EE                     ;; HPRINT
TK_ERR = $EF                        ;; ERR, as in ON ERR
TK_BRK = $F0                        ;; BRK, as in ON BRK
TK_LOCATE = $F1                     ;; LOCATE
TK_HSTAT = $F2                      ;; HSTAT
TK_HSET = $F3                       ;; HSET
TK_HRESET = $F4                     ;; HRESET
TK_HDRAW = $F5                      ;; HDRAW
TK_CMP = $F6                        ;; CMP
TK_RGB = $F7                        ;; RGB
TK_ATTR = $F8                       ;; ATTR

;; Function tokens: $FF, then Super Extended BASIC's functions follow Disk BASIC's, from $A8, in the order of
;; <FUNDIC20>.
TK_LPEEK = $A8                      ;; LPEEK
TK_BUTTON = $A9                     ;; BUTTON
TK_HPOINT = $AA                     ;; HPOINT
TK_ERNO = $AB                       ;; ERNO
TK_ERLIN = $AC                      ;; ERLIN

;; Error codes: Super Extended BASIC's follow Disk BASIC's, twice the error's number.
ERR_HR = 76                         ;; HR: a hi-res graphics command with no HSCREEN
ERR_HP = 78                         ;; HP: HPRINT with no HSCREEN
