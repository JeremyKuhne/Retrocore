; retrocore: style=strict ignore=unlinked-name:PLUS
;; APPLE II CHARACTER GENERATORS: THE IIE'S VIDEO ROM, ORIGINAL AND ENHANCED, AND THE II AND II PLUS'S
;;
;; The IIe draws text from a 4 KiB video ROM: 342-0133 in the original IIe and 342-0265 in the Enhanced IIe.
;; The lower 2 KiB is the text font, 256 characters of eight bytes, one per scanline from the top of the
;; cell. Bits 6-0 of a row are its seven dots from right to left, so bit 0 is the leftmost dot. A normal
;; character stores a lit dot as 0 and sets bit 7; an inverse one stores a lit dot as 1 and clears bit 7, the
;; complement of the normal byte.
;;
;;   $00-$3F   inverse uppercase and symbols
;;   $40-$5F   original: inverse uppercase again; Enhanced: MouseText
;;   $60-$7F   inverse lowercase
;;   $80-$BF   normal uppercase and symbols
;;   $C0-$DF   normal uppercase again
;;   $E0-$FF   normal lowercase
;;
;; Codes $40-$7F read these glyphs only with ALTCHARSET on. With it off, the video circuit shows them as
;; $00-$3F, flashing between inverse and normal, so the original IIe's second inverse uppercase set is seen
;; only through ALTCHARSET.
;;
;; The upper 2 KiB is the same in both chips: a table of 256 eight-byte patterns, one for each byte value.
;; Rows 0, 1, 4 and 5 are the byte's seven low bits stored as normal dots, with bit 7 set; rows 2 and 3 repeat
;; the low nibble's four dots twice across the row, the second time shifted by two dots, and rows 6 and 7 do
;; the same with the high nibble. Retrocore's video reads only the text font.
;;
;; The Apple II and II Plus use a 2 KiB character generator, 7341-0036 on revision 7 and later boards, with the
;; same 64 glyphs as the IIe's uppercase and symbols but stored another way. Each glyph's top row is blank and
;; its seven rows follow, one scanline lower than the IIe's; bit 6 is the leftmost dot and a lit dot is 1, never
;; stored inverse. Only the underscore differs in shape: five dots on the bottom row rather than seven. The
;; 64 glyphs fill the chip four times, for codes $00-$3F, $40-$7F, $80-$BF and $C0-$FF, and those for $40-$7F
;; and $C0-$FF set bit 7. The board draws a code below $40 inverse and one from $40 to $7F flashing itself,
;; so the chip holds no inverse glyphs and no lowercase.
;;
;; Each glyph is drawn as dots, a row at a time, with the macros <Glyph> and <Row>; <UppercaseGlyphs>,
;; <SymbolGlyphs>, <LowercaseGlyphs> and <MouseTextGlyphs> each draw a set of 32 glyphs, and the end of the file
;; lays the sets out for the chip being built. The chips are data the video circuit reads, not code: there are no
;; routines.
;;
;; Assembles byte-identically to each chip. IIBOARD selects the II and II Plus's 7341-0036 (1; 0, the default,
;; for the IIe's); for the IIe, ENHANCED selects the model (1, the default, for the Enhanced IIe's 342-0265; 0
;; for the original's 342-0133). Maintained by hand; the digests in SystemSourceTests (the IIe's) and
;; Apple2SourceTests (the II's) check that all three assemble byte-identically.

.ifndef IIBOARD
IIBOARD = 0
.endif
.ifndef ENHANCED
ENHANCED = 1
.endif

; Only the three builds the digest tests check: the II and II Plus's chip, and the original and Enhanced IIe's.
.assert IIBOARD = 0 || IIBOARD = 1, "IIBOARD is 1 for the II and II Plus's chip or 0 for the IIe's."
.assert ENHANCED = 0 || ENHANCED = 1, "ENHANCED is 1 for the Enhanced IIe or 0 for the original."

;; The bytes in a glyph: one for each of its eight scanlines.
GLYPH_SIZE = 8

;; The glyphs in a set that <UppercaseGlyphs>, <SymbolGlyphs>, <LowercaseGlyphs> or <MouseTextGlyphs> draws.
GLYPHS_PER_SET = 32

;; The dots in a row.
DOTS_PER_ROW = 7

;; A row's dots: bits 6-0.
DOT_BITS = $7F

;; Bit 7 of a row: set in the IIe's normal glyphs and in the II's glyphs for codes $40-$7F and $C0-$FF.
HIGH_BIT = $80

;; 1 while the glyphs being drawn are the IIe's inverse ones, which store a lit dot as 1 and clear bit 7; 0 for
;; normal ones, the complement.
Inverse .set 0

;; <HIGH_BIT> while the II's glyphs being drawn set bit 7, as those for codes $40-$7F and $C0-$FF do; 0 otherwise.
HighBit .set 0

;; The row of the glyph being drawn, 0-7: <Glyph> starts it at 0 and each <Row> adds 1.
GlyphRow .set 0

;; The dots of the row being drawn, as the chip's bits before bit 7 and the IIe's inversion: a lit dot is 1.
Dots .set 0

;; The low four bits of the byte value whose pattern is being drawn, in the IIe's upper 2 KiB.
LowNibble .set 0

;; The high four bits of the byte value whose pattern is being drawn, in the IIe's upper 2 KiB.
HighNibble .set 0

;; Starts a glyph: checks that it lands in its place in its set of 32.
;;
;; For the II and II Plus's chip, it also stores the cell's blank top row, which moves the glyph down one row.
;; Parameters:
;;   code = the character's code, whose low five bits place it in its set
.macro Glyph code
    .assert (* / GLYPH_SIZE) .mod GLYPHS_PER_SET = (code) .mod GLYPHS_PER_SET, "A Glyph is out of order."
    .set GlyphRow, 0
    .if IIBOARD
        .byte HighBit
    .endif
.endmacro

;; One row of a glyph's dots, from the top: a lit dot is 0 and bit 7 is set in the IIe's normal glyphs, a lit dot
;; is 1 and bit 7 clear in its inverse ones, and on the II's chip a lit dot is 1, with bit 7 as <HighBit> says.
;; The II's glyphs, a row lower, have no room for the eighth row, which must be blank.
;; Parameters:
;;   dots = seven characters from left to right, # for a lit dot and . for a dark one
.macro Row dots
    .assert .strlen(dots) = DOTS_PER_ROW, "A Row has seven dots."
    .set Dots, 0
    .repeat DOTS_PER_ROW, column
        .if IIBOARD
            ; The II's chip: bit 6 is the leftmost dot.
            .set Dots, Dots | ((.strat(dots, column) = '#') << (DOTS_PER_ROW - 1 - column))
        .else
            ; The IIe's chip: bit 0 is the leftmost dot.
            .set Dots, Dots | ((.strat(dots, column) = '#') << column)
        .endif
    .endrepeat
    .if IIBOARD
        .if GlyphRow < GLYPH_SIZE - 1
            .byte Dots | HighBit
        .else
            .assert Dots = 0, "The II's glyphs have seven rows."
        .endif
    .elseif Inverse
        .byte Dots
    .else
        ; A normal glyph is the inverse one's complement: a lit dot 0 and bit 7 set.
        .byte Dots ^ $FF
    .endif
    .set GlyphRow, GlyphRow + 1
.endmacro

;; @, A-Z and [ \ ] ^ _.
.macro UppercaseGlyphs
    Glyph $40    ; @
    Row "..###.."
    Row ".#...#."
    Row ".#.#.#."
    Row ".#.###."
    Row ".#.##.."
    Row ".#....."
    Row "..####."
    Row "......."

    Glyph $41    ; A
    Row "...#..."
    Row "..#.#.."
    Row ".#...#."
    Row ".#...#."
    Row ".#####."
    Row ".#...#."
    Row ".#...#."
    Row "......."

    Glyph $42    ; B
    Row ".####.."
    Row ".#...#."
    Row ".#...#."
    Row ".####.."
    Row ".#...#."
    Row ".#...#."
    Row ".####.."
    Row "......."

    Glyph $43    ; C
    Row "..###.."
    Row ".#...#."
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $44    ; D
    Row ".####.."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".####.."
    Row "......."

    Glyph $45    ; E
    Row ".#####."
    Row ".#....."
    Row ".#....."
    Row ".####.."
    Row ".#....."
    Row ".#....."
    Row ".#####."
    Row "......."

    Glyph $46    ; F
    Row ".#####."
    Row ".#....."
    Row ".#....."
    Row ".####.."
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row "......."

    Glyph $47    ; G
    Row "..####."
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row ".#..##."
    Row ".#...#."
    Row "..####."
    Row "......."

    Glyph $48    ; H
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#####."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "......."

    Glyph $49    ; I
    Row "..###.."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "..###.."
    Row "......."

    Glyph $4A    ; J
    Row ".....#."
    Row ".....#."
    Row ".....#."
    Row ".....#."
    Row ".....#."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $4B    ; K
    Row ".#...#."
    Row ".#..#.."
    Row ".#.#..."
    Row ".##...."
    Row ".#.#..."
    Row ".#..#.."
    Row ".#...#."
    Row "......."

    Glyph $4C    ; L
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row ".#####."
    Row "......."

    Glyph $4D    ; M
    Row ".#...#."
    Row ".##.##."
    Row ".#.#.#."
    Row ".#.#.#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "......."

    Glyph $4E    ; N
    Row ".#...#."
    Row ".#...#."
    Row ".##..#."
    Row ".#.#.#."
    Row ".#..##."
    Row ".#...#."
    Row ".#...#."
    Row "......."

    Glyph $4F    ; O
    Row "..###.."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $50    ; P
    Row ".####.."
    Row ".#...#."
    Row ".#...#."
    Row ".####.."
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row "......."

    Glyph $51    ; Q
    Row "..###.."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#.#.#."
    Row ".#..#.."
    Row "..##.#."
    Row "......."

    Glyph $52    ; R
    Row ".####.."
    Row ".#...#."
    Row ".#...#."
    Row ".####.."
    Row ".#.#..."
    Row ".#..#.."
    Row ".#...#."
    Row "......."

    Glyph $53    ; S
    Row "..###.."
    Row ".#...#."
    Row ".#....."
    Row "..###.."
    Row ".....#."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $54    ; T
    Row ".#####."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "......."

    Glyph $55    ; U
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $56    ; V
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "..#.#.."
    Row "...#..."
    Row "......."

    Glyph $57    ; W
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#.#.#."
    Row ".#.#.#."
    Row ".##.##."
    Row ".#...#."
    Row "......."

    Glyph $58    ; X
    Row ".#...#."
    Row ".#...#."
    Row "..#.#.."
    Row "...#..."
    Row "..#.#.."
    Row ".#...#."
    Row ".#...#."
    Row "......."

    Glyph $59    ; Y
    Row ".#...#."
    Row ".#...#."
    Row "..#.#.."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "......."

    Glyph $5A    ; Z
    Row ".#####."
    Row ".....#."
    Row "....#.."
    Row "...#..."
    Row "..#...."
    Row ".#....."
    Row ".#####."
    Row "......."

    Glyph $5B    ; [
    Row ".#####."
    Row ".##...."
    Row ".##...."
    Row ".##...."
    Row ".##...."
    Row ".##...."
    Row ".#####."
    Row "......."

    Glyph $5C    ; \
    Row "......."
    Row ".#....."
    Row "..#...."
    Row "...#..."
    Row "....#.."
    Row ".....#."
    Row "......."
    Row "......."

    Glyph $5D    ; ]
    Row ".#####."
    Row "....##."
    Row "....##."
    Row "....##."
    Row "....##."
    Row "....##."
    Row ".#####."
    Row "......."

    Glyph $5E    ; ^
    Row "......."
    Row "......."
    Row "...#..."
    Row "..#.#.."
    Row ".#...#."
    Row "......."
    Row "......."
    Row "......."

    Glyph $5F    ; _
    .if IIBOARD
        ; The II's underscore is five dots wide, on the cell's bottom row.
        Row "......."
        Row "......."
        Row "......."
        Row "......."
        Row "......."
        Row "......."
        Row ".#####."
        Row "......."
    .else
        Row "......."
        Row "......."
        Row "......."
        Row "......."
        Row "......."
        Row "......."
        Row "......."
        Row "#######"
    .endif
.endmacro

;; Space, punctuation and digits.
.macro SymbolGlyphs
    Glyph $20    ; space
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."

    Glyph $21    ; !
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "......."
    Row "...#..."
    Row "......."

    Glyph $22    ; "
    Row "..#.#.."
    Row "..#.#.."
    Row "..#.#.."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."

    Glyph $23    ; #
    Row "..#.#.."
    Row "..#.#.."
    Row ".#####."
    Row "..#.#.."
    Row ".#####."
    Row "..#.#.."
    Row "..#.#.."
    Row "......."

    Glyph $24    ; $
    Row "...#..."
    Row "..####."
    Row ".#.#..."
    Row "..###.."
    Row "...#.#."
    Row ".####.."
    Row "...#..."
    Row "......."

    Glyph $25    ; %
    Row ".##...."
    Row ".##..#."
    Row "....#.."
    Row "...#..."
    Row "..#...."
    Row ".#..##."
    Row "....##."
    Row "......."

    Glyph $26    ; &
    Row "..#...."
    Row ".#.#..."
    Row ".#.#..."
    Row "..#...."
    Row ".#.#.#."
    Row ".#..#.."
    Row "..##.#."
    Row "......."

    Glyph $27    ; '
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."

    Glyph $28    ; (
    Row "...#..."
    Row "..#...."
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row "..#...."
    Row "...#..."
    Row "......."

    Glyph $29    ; )
    Row "...#..."
    Row "....#.."
    Row ".....#."
    Row ".....#."
    Row ".....#."
    Row "....#.."
    Row "...#..."
    Row "......."

    Glyph $2A    ; *
    Row "...#..."
    Row ".#.#.#."
    Row "..###.."
    Row "...#..."
    Row "..###.."
    Row ".#.#.#."
    Row "...#..."
    Row "......."

    Glyph $2B    ; +
    Row "......."
    Row "...#..."
    Row "...#..."
    Row ".#####."
    Row "...#..."
    Row "...#..."
    Row "......."
    Row "......."

    Glyph $2C    ; ,
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "...#..."
    Row "...#..."
    Row "..#...."
    Row "......."

    Glyph $2D    ; -
    Row "......."
    Row "......."
    Row "......."
    Row ".#####."
    Row "......."
    Row "......."
    Row "......."
    Row "......."

    Glyph $2E    ; .
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "...#..."
    Row "......."

    Glyph $2F    ; /
    Row "......."
    Row ".....#."
    Row "....#.."
    Row "...#..."
    Row "..#...."
    Row ".#....."
    Row "......."
    Row "......."

    Glyph $30    ; 0
    Row "..###.."
    Row ".#...#."
    Row ".#..##."
    Row ".#.#.#."
    Row ".##..#."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $31    ; 1
    Row "...#..."
    Row "..##..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "..###.."
    Row "......."

    Glyph $32    ; 2
    Row "..###.."
    Row ".#...#."
    Row ".....#."
    Row "...##.."
    Row "..#...."
    Row ".#....."
    Row ".#####."
    Row "......."

    Glyph $33    ; 3
    Row ".#####."
    Row ".....#."
    Row "....#.."
    Row "...##.."
    Row ".....#."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $34    ; 4
    Row "....#.."
    Row "...##.."
    Row "..#.#.."
    Row ".#..#.."
    Row ".#####."
    Row "....#.."
    Row "....#.."
    Row "......."

    Glyph $35    ; 5
    Row ".#####."
    Row ".#....."
    Row ".####.."
    Row ".....#."
    Row ".....#."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $36    ; 6
    Row "...###."
    Row "..#...."
    Row ".#....."
    Row ".####.."
    Row ".#...#."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $37    ; 7
    Row ".#####."
    Row ".....#."
    Row "....#.."
    Row "...#..."
    Row "..#...."
    Row "..#...."
    Row "..#...."
    Row "......."

    Glyph $38    ; 8
    Row "..###.."
    Row ".#...#."
    Row ".#...#."
    Row "..###.."
    Row ".#...#."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $39    ; 9
    Row "..###.."
    Row ".#...#."
    Row ".#...#."
    Row "..####."
    Row ".....#."
    Row "....#.."
    Row ".###..."
    Row "......."

    Glyph $3A    ; :
    Row "......."
    Row "......."
    Row "...#..."
    Row "......."
    Row "...#..."
    Row "......."
    Row "......."
    Row "......."

    Glyph $3B    ; ;
    Row "......."
    Row "......."
    Row "...#..."
    Row "......."
    Row "...#..."
    Row "...#..."
    Row "..#...."
    Row "......."

    Glyph $3C    ; <
    Row "....#.."
    Row "...#..."
    Row "..#...."
    Row ".#....."
    Row "..#...."
    Row "...#..."
    Row "....#.."
    Row "......."

    Glyph $3D    ; =
    Row "......."
    Row "......."
    Row ".#####."
    Row "......."
    Row ".#####."
    Row "......."
    Row "......."
    Row "......."

    Glyph $3E    ; >
    Row "..#...."
    Row "...#..."
    Row "....#.."
    Row ".....#."
    Row "....#.."
    Row "...#..."
    Row "..#...."
    Row "......."

    Glyph $3F    ; ?
    Row "..###.."
    Row ".#...#."
    Row "....#.."
    Row "...#..."
    Row "...#..."
    Row "......."
    Row "...#..."
    Row "......."
.endmacro

;; ` a-z { | } ~ and DEL.
.macro LowercaseGlyphs
    Glyph $60    ; `
    Row "..#...."
    Row "...#..."
    Row "....#.."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."

    Glyph $61    ; a
    Row "......."
    Row "......."
    Row "..###.."
    Row ".....#."
    Row "..####."
    Row ".#...#."
    Row "..####."
    Row "......."

    Glyph $62    ; b
    Row ".#....."
    Row ".#....."
    Row ".####.."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".####.."
    Row "......."

    Glyph $63    ; c
    Row "......."
    Row "......."
    Row "..####."
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row "..####."
    Row "......."

    Glyph $64    ; d
    Row ".....#."
    Row ".....#."
    Row "..####."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "..####."
    Row "......."

    Glyph $65    ; e
    Row "......."
    Row "......."
    Row "..###.."
    Row ".#...#."
    Row ".#####."
    Row ".#....."
    Row "..####."
    Row "......."

    Glyph $66    ; f
    Row "...##.."
    Row "..#..#."
    Row "..#...."
    Row ".####.."
    Row "..#...."
    Row "..#...."
    Row "..#...."
    Row "......."

    Glyph $67    ; g
    Row "......."
    Row "......."
    Row "..###.."
    Row ".#...#."
    Row ".#...#."
    Row "..####."
    Row ".....#."
    Row "..###.."

    Glyph $68    ; h
    Row ".#....."
    Row ".#....."
    Row ".####.."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "......."

    Glyph $69    ; i
    Row "...#..."
    Row "......."
    Row "..##..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "..###.."
    Row "......."

    Glyph $6A    ; j
    Row "....#.."
    Row "......."
    Row "...##.."
    Row "....#.."
    Row "....#.."
    Row "....#.."
    Row ".#..#.."
    Row "..##..."

    Glyph $6B    ; k
    Row ".#....."
    Row ".#....."
    Row ".#...#."
    Row ".#..#.."
    Row ".###..."
    Row ".#..#.."
    Row ".#...#."
    Row "......."

    Glyph $6C    ; l
    Row "..##..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "..###.."
    Row "......."

    Glyph $6D    ; m
    Row "......."
    Row "......."
    Row ".##.##."
    Row ".#.#.#."
    Row ".#.#.#."
    Row ".#.#.#."
    Row ".#...#."
    Row "......."

    Glyph $6E    ; n
    Row "......."
    Row "......."
    Row ".####.."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "......."

    Glyph $6F    ; o
    Row "......."
    Row "......."
    Row "..###.."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "..###.."
    Row "......."

    Glyph $70    ; p
    Row "......."
    Row "......."
    Row ".####.."
    Row ".#...#."
    Row ".#...#."
    Row ".####.."
    Row ".#....."
    Row ".#....."

    Glyph $71    ; q
    Row "......."
    Row "......."
    Row "..####."
    Row ".#...#."
    Row ".#...#."
    Row "..####."
    Row ".....#."
    Row ".....#."

    Glyph $72    ; r
    Row "......."
    Row "......."
    Row ".#.###."
    Row ".##...."
    Row ".#....."
    Row ".#....."
    Row ".#....."
    Row "......."

    Glyph $73    ; s
    Row "......."
    Row "......."
    Row "..####."
    Row ".#....."
    Row "..###.."
    Row ".....#."
    Row ".####.."
    Row "......."

    Glyph $74    ; t
    Row "..#...."
    Row "..#...."
    Row ".####.."
    Row "..#...."
    Row "..#...."
    Row "..#..#."
    Row "...##.."
    Row "......."

    Glyph $75    ; u
    Row "......."
    Row "......."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row ".#..##."
    Row "..##.#."
    Row "......."

    Glyph $76    ; v
    Row "......."
    Row "......."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "..#.#.."
    Row "...#..."
    Row "......."

    Glyph $77    ; w
    Row "......."
    Row "......."
    Row ".#...#."
    Row ".#...#."
    Row ".#.#.#."
    Row ".#.#.#."
    Row ".##.##."
    Row "......."

    Glyph $78    ; x
    Row "......."
    Row "......."
    Row ".#...#."
    Row "..#.#.."
    Row "...#..."
    Row "..#.#.."
    Row ".#...#."
    Row "......."

    Glyph $79    ; y
    Row "......."
    Row "......."
    Row ".#...#."
    Row ".#...#."
    Row ".#...#."
    Row "..####."
    Row ".....#."
    Row "..###.."

    Glyph $7A    ; z
    Row "......."
    Row "......."
    Row ".#####."
    Row "....#.."
    Row "...#..."
    Row "..#...."
    Row ".#####."
    Row "......."

    Glyph $7B    ; {
    Row "...###."
    Row "..##..."
    Row "..##..."
    Row ".##...."
    Row "..##..."
    Row "..##..."
    Row "...###."
    Row "......."

    Glyph $7C    ; |
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."

    Glyph $7D    ; }
    Row ".###..."
    Row "...##.."
    Row "...##.."
    Row "....##."
    Row "...##.."
    Row "...##.."
    Row ".###..."
    Row "......."

    Glyph $7E    ; ~
    Row "..##.#."
    Row ".#.##.."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."

    Glyph $7F    ; DEL
    Row "......."
    Row ".#.#.#."
    Row "..#.#.."
    Row ".#.#.#."
    Row "..#.#.."
    Row ".#.#.#."
    Row "......."
    Row "......."
.endmacro

;; The Enhanced IIe's 32 MouseText glyphs, for codes $40-$5F, stored normal: Apple's symbols for menus, windows
;; and the mouse. Each comment gives the symbol's usual name.
.macro MouseTextGlyphs
    Glyph $40    ; closed apple
    Row "....#.."
    Row "...#..."
    Row ".##.##."
    Row "#######"
    Row "######."
    Row "######."
    Row ".######"
    Row ".##.##."

    Glyph $41    ; open apple
    Row "....#.."
    Row "...#..."
    Row ".##.##."
    Row "#.....#"
    Row "#....#."
    Row "#....#."
    Row ".#.#..#"
    Row ".##.##."

    Glyph $42    ; mouse pointer
    Row "......."
    Row "......."
    Row ".#....."
    Row ".##...."
    Row ".###..."
    Row ".####.."
    Row ".##.##."
    Row ".#....#"

    Glyph $43    ; hourglass
    Row "#######"
    Row ".#...#."
    Row "..#.#.."
    Row "...#..."
    Row "...#..."
    Row "..#.#.."
    Row ".#.#.#."
    Row "#######"

    Glyph $44    ; checkmark
    Row "......."
    Row "......#"
    Row ".....#."
    Row "#...#.."
    Row ".#.#..."
    Row "..#...."
    Row "..#...."
    Row "......."

    Glyph $45    ; inverse checkmark
    Row "#######"
    Row "######."
    Row "#####.#"
    Row "..##.##"
    Row "#.#.###"
    Row "##.####"
    Row "##.####"
    Row "#######"

    Glyph $46    ; running man
    Row "....###"
    Row ".....##"
    Row ".######"
    Row "#...##."
    Row "#..####"
    Row "....##."
    Row "######."
    Row ".#....."

    Glyph $47    ; running man, second half
    Row "......."
    Row "...##.."
    Row "###...."
    Row "......."
    Row "###...."
    Row "..##..."
    Row "...#..."
    Row "....###"

    Glyph $48    ; left arrow
    Row "...#..."
    Row "..#...."
    Row ".#....."
    Row "#######"
    Row ".#....."
    Row "..#...."
    Row "...#..."
    Row "......."

    Glyph $49    ; ellipsis
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row ".#.#.#."

    Glyph $4A    ; down arrow
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "#..#..#"
    Row ".#.#.#."
    Row "..###.."
    Row "...#..."

    Glyph $4B    ; up arrow
    Row "...#..."
    Row "..###.."
    Row ".#.#.#."
    Row "#..#..#"
    Row "...#..."
    Row "...#..."
    Row "...#..."
    Row "...#..."

    Glyph $4C    ; top bar
    Row "#######"
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."

    Glyph $4D    ; return arrow
    Row "......#"
    Row "......#"
    Row "......#"
    Row "..#...#"
    Row ".##...#"
    Row "#######"
    Row ".##...."
    Row "..#...."

    Glyph $4E    ; solid block
    Row "######."
    Row "######."
    Row "######."
    Row "######."
    Row "######."
    Row "######."
    Row "######."
    Row "######."

    Glyph $4F    ; scroll left
    Row "##..#.."
    Row "...##.."
    Row "..###.."
    Row ".######"
    Row "..###.."
    Row "...##.."
    Row "....#.."
    Row "####.##"

    Glyph $50    ; scroll right
    Row "..#..##"
    Row "..##..."
    Row "..###.."
    Row "######."
    Row "..###.."
    Row "..##..."
    Row "..#...."
    Row "##.####"

    Glyph $51    ; scroll down
    Row "......#"
    Row "...#..#"
    Row "...#..."
    Row "#######"
    Row ".#####."
    Row "..###.."
    Row "...#..#"
    Row "......#"

    Glyph $52    ; scroll up
    Row "......#"
    Row "...#..#"
    Row "..###.."
    Row ".#####."
    Row "#######"
    Row "...#..."
    Row "...#..#"
    Row "......#"

    Glyph $53    ; middle bar
    Row "......."
    Row "......."
    Row "......."
    Row "#######"
    Row "......."
    Row "......."
    Row "......."
    Row "......."

    Glyph $54    ; lower-left corner
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#######"

    Glyph $55    ; right arrow
    Row "...#..."
    Row "....#.."
    Row ".....#."
    Row "#######"
    Row ".....#."
    Row "....#.."
    Row "...#..."
    Row "......."

    Glyph $56    ; checkerboard
    Row ".#.#.#."
    Row "#.#.#.#"
    Row ".#.#.#."
    Row "#.#.#.#"
    Row ".#.#.#."
    Row "#.#.#.#"
    Row ".#.#.#."
    Row "#.#.#.#"

    Glyph $57    ; checkerboard, shifted
    Row "#.#.#.#"
    Row ".#.#.#."
    Row "#.#.#.#"
    Row ".#.#.#."
    Row "#.#.#.#"
    Row ".#.#.#."
    Row "#.#.#.#"
    Row ".#.#.#."

    Glyph $58    ; folder, left half
    Row "......."
    Row ".#####."
    Row "#.....#"
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#######"
    Row "......."

    Glyph $59    ; folder, right half
    Row "......."
    Row "......."
    Row "######."
    Row "......#"
    Row "......#"
    Row "......#"
    Row "#######"
    Row "......."

    Glyph $5A    ; right bar
    Row "......#"
    Row "......#"
    Row "......#"
    Row "......#"
    Row "......#"
    Row "......#"
    Row "......#"
    Row "......#"

    Glyph $5B    ; diamond
    Row "...#..."
    Row "..###.."
    Row ".#####."
    Row "#######"
    Row ".#####."
    Row "..###.."
    Row "...#..."
    Row "......."

    Glyph $5C    ; top and bottom bars
    Row "#######"
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "#######"

    Glyph $5D    ; crossing
    Row "..#.#.."
    Row "..#.#.."
    Row "###.###"
    Row "......."
    Row "###.###"
    Row "..#.#.."
    Row "..#.#.."
    Row "......."

    Glyph $5E    ; box
    Row "#######"
    Row "......#"
    Row "......#"
    Row "..##..#"
    Row "..##..#"
    Row "......#"
    Row "......#"
    Row "#######"

    Glyph $5F    ; left bar
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#......"
    Row "#......"
.endmacro

.org $0000

.if IIBOARD
; The II and II Plus: the 64 glyphs four times, bit 7 set in the second and fourth.
.repeat 2
    .set HighBit, 0
    UppercaseGlyphs
    SymbolGlyphs
    .set HighBit, HIGH_BIT
    UppercaseGlyphs
    SymbolGlyphs
.endrepeat
.else
    ; $00-$3F: inverse.
    .set Inverse, 1
    UppercaseGlyphs
    SymbolGlyphs

.if ENHANCED
    ; $40-$5F: MouseText.
    .set Inverse, 0
    MouseTextGlyphs
.else
    ; $40-$5F: inverse uppercase again.
    UppercaseGlyphs
.endif

    ; $60-$7F: inverse lowercase.
    .set Inverse, 1
    LowercaseGlyphs

    ; $80-$FF: normal.
    .set Inverse, 0
    UppercaseGlyphs
    SymbolGlyphs
    UppercaseGlyphs
    LowercaseGlyphs

; $800-$FFF: a pattern for each byte value. Multiplying a nibble by $11 repeats its four dots across the row's
; eight bits, and the rotation by two shifts the second copy two dots; the inversions make the dots normal.
.repeat 256, value
    .set LowNibble, value & $0F
    .set HighNibble, value >> 4
    .byte HIGH_BIT | (~value & DOT_BITS), HIGH_BIT | (~value & DOT_BITS)
    .byte ~(LowNibble * $11) & $FF, ~((((LowNibble << 2) | (LowNibble >> 2)) & $0F) * $11) & $FF
    .byte HIGH_BIT | (~value & DOT_BITS), HIGH_BIT | (~value & DOT_BITS)
    .byte ~(HighNibble * $11) & $FF, ~((((HighNibble << 2) | (HighNibble >> 2)) & $0F) * $11) & $FF
.endrepeat
.endif
