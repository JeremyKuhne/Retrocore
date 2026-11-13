;; TRS-80 COLOR COMPUTER EXTENDED BASIC EQUATES: ITS RAM, TOKENS AND ERROR CODES
;;
;; The RAM Extended Color BASIC adds to Color BASIC's, at the top of the direct page and in page 1, with the names
;; Microsoft's BASIC and Spectral Associates' Extended Basic Unravelled give them, and Extended BASIC's tokens and
;; error codes. Extended BASIC includes this file after ColorBasicEquates.asm, and Disk Extended Color BASIC can
;; include it too, so each name is defined and documented once.

; ----------------------------------------------------------------------------------------------------------------
; The direct page
; ----------------------------------------------------------------------------------------------------------------

;; Nonzero while TRON shows each line's number.
;;
;; <TRON> sets it and <TROFF> clears it; <XVEC20> shows the number in brackets before each line it runs.
;; See: <TRON>, <XVEC20>
TRCFLG = $AF

;; The USR table's address: ten addresses, for USR0 to USR9.
;;
;; <XBINIT> points it at <USR0> and fills the table with ?FC ERROR; <DEFUSR> sets an address, and <USRCALL> calls
;; one, through <USRSLOT>.
;; See: <USRSLOT>, <DEFUSR>, <USRCALL>
USRADR = $B0

;; The foreground color, as a pixel's bits.
;;
;; <COLOR> and DRAW's C set it, and <PMOD> and <GRINIT> set 3. <SETWORK> draws in it for PSET and LINE ...,PSET.
;; See: <BAKCOL>, <COLOR>, <SETWORK>
FORCOL = $B2

;; The background color, as a pixel's bits.
;;
;; <COLOR> sets it and <PMOD> clears it; PCLS fills with it, and PRESET draws in it.
;; See: <FORCOL>, <COLOR>, <PCLS>
BAKCOL = $B3

;; The working color: the pixel's bits graphics are drawing in now.
;;
;; <SETWORK> sets it from <FORCOL> or <BAKCOL>, or <SETWORK_COLOR> from a color given; <PAINT> keeps the paint
;; color here, and <ALLCOL> after it.
;; See: <ALLCOL>, <SETWORK>
WCOLOR = $B4

;; The working color in every pixel of a byte, which <PIXSET> masks a pixel out of.
;;
;; See: <WCOLOR>, <PIXSET>, <SETWORK_COLOR>
ALLCOL = $B5

;; The graphics mode, 0 to 4: 0, 2 and 4 two-color, 1 and 3 four-color, with 128 or 256 pixels across and 96 or 192
;; down.
;;
;; <PMOD> and <GRINIT> set it. <PIXRTN> and <RIGHTRTN> choose their routines by it, <GRSCALE> scales points for
;; it, <CHKCOLOR> turns colors into its pixels' bits, and <GRAPHSCREEN> sets the VDG and SAM for it.
;; See: <PMOD>, <PMODETAB>, <HORBYT>
PMODE = $B6

;; The end of the graphics page, its high byte the page's.
;;
;; <PMOD> sets it from the page's start and the mode's page size; PCLS clears up to it, and <PCLEAR> keeps the
;; program above it.
;; See: <BEGGRP>, <PMOD>, <PCLEAR>
ENDGRP = $B7

;; The graphics page's bytes a row: 16 or 32.
;;
;; <PMOD> sets it from <PMODETAB>; <PIXADR2>, <PIXADR4> and <PIXDOWN> step rows by it.
;; See: <PMODE>, <PIXADR2>
HORBYT = $B9

;; The start of the graphics page, its high byte the page's.
;;
;; <PMOD> sets it to the page asked for; <PIXADR2> and <PIXADR4> count from it, and <GRAPHSCREEN> points the SAM at
;; it.
;; See: <ENDGRP>, <GRPRAM>, <PMOD>
BEGGRP = $BA

;; The start of the graphics pages' memory, as its high byte: $06, for $0600.
;;
;; <GRINIT> sets it; <PMOD>, <PCLEAR> and <PAGEADR> count pages from it, 1.5K each.
;; See: <BEGGRP>, <PAGEADR>
GRPRAM = $BC

;; A point's horizontal coordinate: where a line starts, or the pixel being drawn.
;;
;; <GETXY> reads it, <GRSCALE> scales it, and <PIXADR> finds its pixel; <INCX> and <DECX> step it.
;; See: <VERBEG>, <HOREND>, <PIXADR>
HORBEG = $BD

;; A point's vertical coordinate, as <HORBEG> is the horizontal.
;;
;; See: <HORBEG>, <VEREND>, <INCY>
VERBEG = $BF

;; The color set: 0 for the first, 8 for the second, the VDG's CSS bit in PIA 1's port B.
;;
;; <SCREEN> sets it, and <SETCSS> and <GRAPHSCREEN> give it to the VDG; <PPOINT> adds it to a color's number.
;; See: <SCREEN>, <SETCSS>
CSSVAL = $C1

;; Nonzero for PSET, zero for PRESET: which color <SETWORK> chooses.
;;
;; See: <PSET>, <SETWORK>
SETFLG = $C2

;; Where a line ends horizontally; GET and PUT's width, and CIRCLE's last point.
;;
;; <LINEXY> reads it, <DIFFX> measures from <HORBEG> to it, and <DRAWTO> and <CIRCLE> set it.
;; See: <HORBEG>, <VEREND>, <DIFFX>
HOREND = $C3

;; Where a line ends vertically, as <HOREND> is horizontally.
;;
;; See: <VERBEG>, <HOREND>, <DIFFY>
VEREND = $C5

;; The last point drawn's horizontal coordinate: where LINE -(x,y) and DRAW start.
;;
;; <XVEC18> sets it to the screen's middle, 128; <LINE> sets it to each line's end, and <DRAWTO> to each move's.
;; See: <VERDEF>, <LINE>, <DRAWTO>
HORDEF = $C7

;; The last point drawn's vertical coordinate, 96 to start with, as <HORDEF> is the horizontal.
;;
;; See: <HORDEF>
VERDEF = $C9

;; Scratch, two bytes.
;;
;; <CIRCLE> keeps the center's horizontal coordinate here, and <PNTBACK> and <PNTPUSH> keep D.
;; See: <CIRCLE>, <PNTPUSH>
VCB = $CB

;; Scratch, two bytes.
;;
;; <CIRCLE> keeps the center's vertical coordinate here, and <PNTWIDE> a row's length.
;; See: <CIRCLE>, <PNTWIDE>
VCD = $CD

;; Scratch, two bytes.
;;
;; <RENUM> keeps the step here, <GETPUT> its place in the array, and <CIRCLE> the radius.
;; See: <RENUM>, <ARYNEXT>, <CIRCMUL>
VCF = $CF

;; Scratch, two bytes.
;;
;; <RENUM> keeps the first line to renumber here, <GETPUT> the array's end, <PAINT> a row's length, and <CIRCLE>
;; the height's ratio.
;; See: <RENUM>, <ARYNEXT>, <CIRCLE>
VD1 = $D1

;; Scratch, two bytes.
;;
;; <DEL> and <RENUM> keep a line here, <XCLOAD_TYPE> the offset, <USING> the format's characters left, and
;; <GRLIMIT> the page's last point, for <PAINT> and <CIRCLE>.
;; See: <GRLIMIT>, <DEL>, <USING>
VD3 = $D3

;; Scratch: GET and PUT's flag for a pixel at a time.
;;
;; See: <GETPUT>
VD4 = $D4

;; Scratch, two bytes; DRAW's N flag, with its B flag in <VD6>.
;;
;; <RENUM> keeps the new start here, <USING> the format, <GETPUT> PUT's routine for a pixel that is on, <PLAYTONE>
;; how much the timer counts down each sixtieth, and <GRLIMIT> the page's last row.
;; See: <DRAW>, <PLAYTONE>, <USING>
VD5 = $D5

;; Scratch: DRAW's B flag, nonzero to move without drawing; the page's last row's low byte, for <PAINT>.
;;
;; See: <DRAW>, <VD5>
VD6 = $D6

;; Scratch.
;;
;; <EDIT> keeps the line's length here, <PUPOINT> the digits to the next comma, <PAINT> its direction, and
;; <PLAYNUM> a digit.
;; See: <EDIT>, <PUPOINT>, <PAINT>
VD7 = $D7

;; Scratch.
;;
;; <EDIT> keeps whether to show the line here, <USING> the digits after the point, <GETPUT> whether it is PUT,
;; <PAINT> the border's color, <CIRCLE> the first point's flag, and PLAY and DRAW the string's characters left.
;; See: <PLAYCHR>, <USING>, <GETPUT>
VD8 = $D8

;; Scratch, two bytes.
;;
;; <USING> keeps the places before the point here, <GETPUT> PUT's routine for a pixel that is off, <PAINT> its
;; pixel routine, PLAY and DRAW the string's next character, and <CIRCLE> the arc's end.
;; See: <PLAYCHR>, <USING>, <PNTBORDER>
VD9 = $D9

;; PRINT USING's field flags: bit 6 commas, bit 5 asterisks, bit 4 a dollar sign, bit 3 a sign before, bit 2 a
;; sign after, bit 0 an exponent.
;;
;; See: <USING>, <PUFOUT>, <PUFILL>
VDA = $DA

;; Set when PIXSET changes a pixel, so PAINT knows whether a row did anything.
;;
;; See: <PIXSET>, <PAINT>
CHGFLG = $DB

;; The stack's place while PAINT works, to go back to when a row painted nothing.
;;
;; See: <PAINT>
TMPSTK = $DC

;; PLAY's octave, 0 to 4 for O1 to O5.
;;
;; See: <PLAYCMD>, <PLAYTONE>
OCTAVE = $DE

;; PLAY's wave's high DAC level: $7E plus four times the volume.
;;
;; <XVEC18> sets the middle volume, and PLAY's V command a new one, with <VOLLOW> after it.
;; See: <VOLLOW>, <PLAYCMD>
VOLHI = $DF

;; PLAY's wave's low DAC level: $7E less four times the volume.
;;
;; See: <VOLHI>
VOLLOW = $E0

;; PLAY's note length: 4 for a quarter note.
;;
;; See: <PLAYCMD>, <PLAYNOTE>
NOTELN = $E1

;; PLAY's tempo, 1 to 255: higher is faster.
;;
;; See: <PLAYCMD>, <PLAYTONE>
TEMPO = $E2

;; PLAY's timer: the note plays until the IRQ handler counts it down to zero.
;;
;; <PLAYTONE> sets it, <PLAYIRQ> counts it down and ends the note, and <XBWMST> clears it.
;; See: <PLAYTONE>, <PLAYIRQ>
PLYTMR = $E3

;; PLAY's dots after the length or note: each makes it half as long again.
;;
;; See: <PLAYDOT>, <PLAYTIME>
DOTVAL = $E5

;; DLOAD's baud rate, as <RSHALF>'s delay: $B0 for 300 baud, $2C for 1200.
;;
;; See: <DLOAD>, <RSHALF>
DLBAUD = $E6

;; DLOAD's timeout: <RSIN> waits this many times 65536 samples for a byte.
;;
;; See: <RSIN>
TIMOUT = $E7

;; DRAW's angle, 0 to 3, in quarter turns clockwise.
;;
;; See: <DRAW>, <DRAWBY>
ANGLE = $E8

;; DRAW's scale, 0 to 62, in quarters; 0 is unscaled.
;;
;; See: <DRAW>, <DRAWSCALE>
SCALE = $E9

; ----------------------------------------------------------------------------------------------------------------
; Page 1
; ----------------------------------------------------------------------------------------------------------------

;; TIMER's count of sixtieths of a second, where Color BASIC keeps <USRJMP>.
;;
;; <XIRQSV> counts it up, <TIMEQ> sets it and <TIMER> reads it.
;; See: <XIRQSV>, <TIMER>
TIMVAL = $0112

; ----------------------------------------------------------------------------------------------------------------
; Tokens and error codes
; ----------------------------------------------------------------------------------------------------------------

;; Tokens: Extended BASIC's commands follow Color BASIC's, from $B5, in the order of <XCOMWRD>.
TK_DEL = $B5                        ;; DEL
TK_EDIT = $B6                       ;; EDIT
TK_TRON = $B7                       ;; TRON
TK_TROFF = $B8                      ;; TROFF
TK_DEF = $B9                        ;; DEF
TK_LET = $BA                        ;; LET
TK_LINE = $BB                       ;; LINE
TK_PCLS = $BC                       ;; PCLS
TK_PSET = $BD                       ;; PSET
TK_PRESET = $BE                     ;; PRESET
TK_SCREEN = $BF                     ;; SCREEN
TK_PCLEAR = $C0                     ;; PCLEAR
TK_COLOR = $C1                      ;; COLOR
TK_CIRCLE = $C2                     ;; CIRCLE
TK_PAINT = $C3                      ;; PAINT
TK_GET = $C4                        ;; GET
TK_PUT = $C5                        ;; PUT
TK_DRAW = $C6                       ;; DRAW
TK_PCOPY = $C7                      ;; PCOPY
TK_PMODE = $C8                      ;; PMODE
TK_PLAY = $C9                       ;; PLAY
TK_DLOAD = $CA                      ;; DLOAD
TK_RENUM = $CB                      ;; RENUM
TK_FN = $CC                         ;; FN
TK_USING = $CD                      ;; USING

;; Function tokens: $FF, then Extended BASIC's functions follow Color BASIC's, from $94, in the order of <XFUNWRD>.
TK_ATN = $94                        ;; ATN
TK_COS = $95                        ;; COS
TK_TAN = $96                        ;; TAN
TK_EXP = $97                        ;; EXP
TK_FIX = $98                        ;; FIX
TK_LOG = $99                        ;; LOG
TK_POS = $9A                        ;; POS
TK_SQR = $9B                        ;; SQR
TK_HEX = $9C                        ;; HEX$
TK_VARPTR = $9D                     ;; VARPTR
TK_INSTR = $9E                      ;; INSTR
TK_TIMER = $9F                      ;; TIMER
TK_PPOINT = $A0                     ;; PPOINT
TK_STRING = $A1                     ;; STRING$

;; Error codes: Extended BASIC's follow Color BASIC's, twice the error's place in <XERRTAB>, plus 50.
ERR_UF = 50                         ;; UF: undefined function
ERR_NE = 52                         ;; NE: file not found, which Disk BASIC raises
