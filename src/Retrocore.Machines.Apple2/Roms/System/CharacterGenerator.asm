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
;; Assembles byte-identically to each chip. IIBOARD selects the II and II Plus's 7341-0036 (1; 0, the default,
;; for the IIe's); for the IIe, ENHANCED selects the model (1, the default, for the Enhanced IIe's 342-0265; 0
;; for the original's 342-0133). Maintained by hand; the SystemSourceTests digests check that all three
;; assemble byte-identically.

.ifndef IIBOARD
IIBOARD = 0
.endif
.ifndef ENHANCED
ENHANCED = 1
.endif

; 1 while the glyphs being drawn are stored inverse.
Inverse .set 0

; 1 while the II's glyphs being drawn set bit 7, as those for codes $40-$7F and $C0-$FF do.
Flash .set 0

; The row of the glyph being drawn, 0-7.
Row .set 0

;; Starts a character: checks that it lands in the right place of its 32-character group.
;;
;; For the II and II Plus's chip, it also stores the cell's blank top row, which moves the glyph down one row.
;; Parameters: code = the character's code, whose low five bits place it in its group
;; See: <ROW>
.macro GLYPH code
    .assert ((* >> 3) & $1F) = ((code) & $1F), "A GLYPH is out of order."
Row .set 0
.if IIBOARD
    .byte Flash << 7
.endif
.endmacro

;; One row of dots: seven characters from left to right, # for a lit dot and . for a dark one.
.macro ROW dots
    .assert .strlen(dots) = 7, "A ROW has seven dots."
.if IIBOARD
    ; The II's chip: bit 6 is the leftmost dot and a lit dot is 1. Its glyphs start a row lower, so the eighth
    ; row, blank in every glyph, has no room.
    Lit .set ((.strat(dots, 0) = '#') << 6) | ((.strat(dots, 1) = '#') << 5) | ((.strat(dots, 2) = '#') << 4) | ((.strat(dots, 3) = '#') << 3) | ((.strat(dots, 4) = '#') << 2) | ((.strat(dots, 5) = '#') << 1) | (.strat(dots, 6) = '#')
.if Row < 7
    .byte Lit | (Flash << 7)
.else
    .assert Lit = 0, "The II's glyphs have seven rows."
.endif
.else
    Lit .set (.strat(dots, 0) = '#') | ((.strat(dots, 1) = '#') << 1) | ((.strat(dots, 2) = '#') << 2) | ((.strat(dots, 3) = '#') << 3) | ((.strat(dots, 4) = '#') << 4) | ((.strat(dots, 5) = '#') << 5) | ((.strat(dots, 6) = '#') << 6)
.if Inverse
    .byte Lit
.else
    .byte Lit ^ $FF
.endif
.endif
Row .set Row + 1
.endmacro

;; @, A-Z and [ \ ] ^ _.
.macro UPPERCASE
    GLYPH $40    ; @
    ROW "..###.."
    ROW ".#...#."
    ROW ".#.#.#."
    ROW ".#.###."
    ROW ".#.##.."
    ROW ".#....."
    ROW "..####."
    ROW "......."

    GLYPH $41    ; A
    ROW "...#..."
    ROW "..#.#.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#####."
    ROW ".#...#."
    ROW ".#...#."
    ROW "......."

    GLYPH $42    ; B
    ROW ".####.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".####.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".####.."
    ROW "......."

    GLYPH $43    ; C
    ROW "..###.."
    ROW ".#...#."
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $44    ; D
    ROW ".####.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".####.."
    ROW "......."

    GLYPH $45    ; E
    ROW ".#####."
    ROW ".#....."
    ROW ".#....."
    ROW ".####.."
    ROW ".#....."
    ROW ".#....."
    ROW ".#####."
    ROW "......."

    GLYPH $46    ; F
    ROW ".#####."
    ROW ".#....."
    ROW ".#....."
    ROW ".####.."
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW "......."

    GLYPH $47    ; G
    ROW "..####."
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW ".#..##."
    ROW ".#...#."
    ROW "..####."
    ROW "......."

    GLYPH $48    ; H
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#####."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "......."

    GLYPH $49    ; I
    ROW "..###.."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "..###.."
    ROW "......."

    GLYPH $4A    ; J
    ROW ".....#."
    ROW ".....#."
    ROW ".....#."
    ROW ".....#."
    ROW ".....#."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $4B    ; K
    ROW ".#...#."
    ROW ".#..#.."
    ROW ".#.#..."
    ROW ".##...."
    ROW ".#.#..."
    ROW ".#..#.."
    ROW ".#...#."
    ROW "......."

    GLYPH $4C    ; L
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW ".#####."
    ROW "......."

    GLYPH $4D    ; M
    ROW ".#...#."
    ROW ".##.##."
    ROW ".#.#.#."
    ROW ".#.#.#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "......."

    GLYPH $4E    ; N
    ROW ".#...#."
    ROW ".#...#."
    ROW ".##..#."
    ROW ".#.#.#."
    ROW ".#..##."
    ROW ".#...#."
    ROW ".#...#."
    ROW "......."

    GLYPH $4F    ; O
    ROW "..###.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $50    ; P
    ROW ".####.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".####.."
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW "......."

    GLYPH $51    ; Q
    ROW "..###.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#.#.#."
    ROW ".#..#.."
    ROW "..##.#."
    ROW "......."

    GLYPH $52    ; R
    ROW ".####.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".####.."
    ROW ".#.#..."
    ROW ".#..#.."
    ROW ".#...#."
    ROW "......."

    GLYPH $53    ; S
    ROW "..###.."
    ROW ".#...#."
    ROW ".#....."
    ROW "..###.."
    ROW ".....#."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $54    ; T
    ROW ".#####."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "......."

    GLYPH $55    ; U
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $56    ; V
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..#.#.."
    ROW "...#..."
    ROW "......."

    GLYPH $57    ; W
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#.#.#."
    ROW ".#.#.#."
    ROW ".##.##."
    ROW ".#...#."
    ROW "......."

    GLYPH $58    ; X
    ROW ".#...#."
    ROW ".#...#."
    ROW "..#.#.."
    ROW "...#..."
    ROW "..#.#.."
    ROW ".#...#."
    ROW ".#...#."
    ROW "......."

    GLYPH $59    ; Y
    ROW ".#...#."
    ROW ".#...#."
    ROW "..#.#.."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "......."

    GLYPH $5A    ; Z
    ROW ".#####."
    ROW ".....#."
    ROW "....#.."
    ROW "...#..."
    ROW "..#...."
    ROW ".#....."
    ROW ".#####."
    ROW "......."

    GLYPH $5B    ; [
    ROW ".#####."
    ROW ".##...."
    ROW ".##...."
    ROW ".##...."
    ROW ".##...."
    ROW ".##...."
    ROW ".#####."
    ROW "......."

    GLYPH $5C    ; \
    ROW "......."
    ROW ".#....."
    ROW "..#...."
    ROW "...#..."
    ROW "....#.."
    ROW ".....#."
    ROW "......."
    ROW "......."

    GLYPH $5D    ; ]
    ROW ".#####."
    ROW "....##."
    ROW "....##."
    ROW "....##."
    ROW "....##."
    ROW "....##."
    ROW ".#####."
    ROW "......."

    GLYPH $5E    ; ^
    ROW "......."
    ROW "......."
    ROW "...#..."
    ROW "..#.#.."
    ROW ".#...#."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $5F    ; _
.if IIBOARD
    ; The II's underscore is five dots wide, on the cell's bottom row.
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW ".#####."
    ROW "......."
.else
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "#######"
.endif
.endmacro

;; Space, punctuation and digits.
.macro SYMBOLS
    GLYPH $20    ; space
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $21    ; !
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "......."
    ROW "...#..."
    ROW "......."

    GLYPH $22    ; "
    ROW "..#.#.."
    ROW "..#.#.."
    ROW "..#.#.."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $23    ; #
    ROW "..#.#.."
    ROW "..#.#.."
    ROW ".#####."
    ROW "..#.#.."
    ROW ".#####."
    ROW "..#.#.."
    ROW "..#.#.."
    ROW "......."

    GLYPH $24    ; $
    ROW "...#..."
    ROW "..####."
    ROW ".#.#..."
    ROW "..###.."
    ROW "...#.#."
    ROW ".####.."
    ROW "...#..."
    ROW "......."

    GLYPH $25    ; %
    ROW ".##...."
    ROW ".##..#."
    ROW "....#.."
    ROW "...#..."
    ROW "..#...."
    ROW ".#..##."
    ROW "....##."
    ROW "......."

    GLYPH $26    ; &
    ROW "..#...."
    ROW ".#.#..."
    ROW ".#.#..."
    ROW "..#...."
    ROW ".#.#.#."
    ROW ".#..#.."
    ROW "..##.#."
    ROW "......."

    GLYPH $27    ; '
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $28    ; (
    ROW "...#..."
    ROW "..#...."
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW "..#...."
    ROW "...#..."
    ROW "......."

    GLYPH $29    ; )
    ROW "...#..."
    ROW "....#.."
    ROW ".....#."
    ROW ".....#."
    ROW ".....#."
    ROW "....#.."
    ROW "...#..."
    ROW "......."

    GLYPH $2A    ; *
    ROW "...#..."
    ROW ".#.#.#."
    ROW "..###.."
    ROW "...#..."
    ROW "..###.."
    ROW ".#.#.#."
    ROW "...#..."
    ROW "......."

    GLYPH $2B    ; +
    ROW "......."
    ROW "...#..."
    ROW "...#..."
    ROW ".#####."
    ROW "...#..."
    ROW "...#..."
    ROW "......."
    ROW "......."

    GLYPH $2C    ; ,
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "...#..."
    ROW "...#..."
    ROW "..#...."
    ROW "......."

    GLYPH $2D    ; -
    ROW "......."
    ROW "......."
    ROW "......."
    ROW ".#####."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $2E    ; .
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "...#..."
    ROW "......."

    GLYPH $2F    ; /
    ROW "......."
    ROW ".....#."
    ROW "....#.."
    ROW "...#..."
    ROW "..#...."
    ROW ".#....."
    ROW "......."
    ROW "......."

    GLYPH $30    ; 0
    ROW "..###.."
    ROW ".#...#."
    ROW ".#..##."
    ROW ".#.#.#."
    ROW ".##..#."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $31    ; 1
    ROW "...#..."
    ROW "..##..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "..###.."
    ROW "......."

    GLYPH $32    ; 2
    ROW "..###.."
    ROW ".#...#."
    ROW ".....#."
    ROW "...##.."
    ROW "..#...."
    ROW ".#....."
    ROW ".#####."
    ROW "......."

    GLYPH $33    ; 3
    ROW ".#####."
    ROW ".....#."
    ROW "....#.."
    ROW "...##.."
    ROW ".....#."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $34    ; 4
    ROW "....#.."
    ROW "...##.."
    ROW "..#.#.."
    ROW ".#..#.."
    ROW ".#####."
    ROW "....#.."
    ROW "....#.."
    ROW "......."

    GLYPH $35    ; 5
    ROW ".#####."
    ROW ".#....."
    ROW ".####.."
    ROW ".....#."
    ROW ".....#."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $36    ; 6
    ROW "...###."
    ROW "..#...."
    ROW ".#....."
    ROW ".####.."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $37    ; 7
    ROW ".#####."
    ROW ".....#."
    ROW "....#.."
    ROW "...#..."
    ROW "..#...."
    ROW "..#...."
    ROW "..#...."
    ROW "......."

    GLYPH $38    ; 8
    ROW "..###.."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..###.."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $39    ; 9
    ROW "..###.."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..####."
    ROW ".....#."
    ROW "....#.."
    ROW ".###..."
    ROW "......."

    GLYPH $3A    ; :
    ROW "......."
    ROW "......."
    ROW "...#..."
    ROW "......."
    ROW "...#..."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $3B    ; ;
    ROW "......."
    ROW "......."
    ROW "...#..."
    ROW "......."
    ROW "...#..."
    ROW "...#..."
    ROW "..#...."
    ROW "......."

    GLYPH $3C    ; <
    ROW "....#.."
    ROW "...#..."
    ROW "..#...."
    ROW ".#....."
    ROW "..#...."
    ROW "...#..."
    ROW "....#.."
    ROW "......."

    GLYPH $3D    ; =
    ROW "......."
    ROW "......."
    ROW ".#####."
    ROW "......."
    ROW ".#####."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $3E    ; >
    ROW "..#...."
    ROW "...#..."
    ROW "....#.."
    ROW ".....#."
    ROW "....#.."
    ROW "...#..."
    ROW "..#...."
    ROW "......."

    GLYPH $3F    ; ?
    ROW "..###.."
    ROW ".#...#."
    ROW "....#.."
    ROW "...#..."
    ROW "...#..."
    ROW "......."
    ROW "...#..."
    ROW "......."
.endmacro

;; ` a-z { | } ~ and DEL.
.macro LOWERCASE
    GLYPH $60    ; `
    ROW "..#...."
    ROW "...#..."
    ROW "....#.."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $61    ; a
    ROW "......."
    ROW "......."
    ROW "..###.."
    ROW ".....#."
    ROW "..####."
    ROW ".#...#."
    ROW "..####."
    ROW "......."

    GLYPH $62    ; b
    ROW ".#....."
    ROW ".#....."
    ROW ".####.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".####.."
    ROW "......."

    GLYPH $63    ; c
    ROW "......."
    ROW "......."
    ROW "..####."
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW "..####."
    ROW "......."

    GLYPH $64    ; d
    ROW ".....#."
    ROW ".....#."
    ROW "..####."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..####."
    ROW "......."

    GLYPH $65    ; e
    ROW "......."
    ROW "......."
    ROW "..###.."
    ROW ".#...#."
    ROW ".#####."
    ROW ".#....."
    ROW "..####."
    ROW "......."

    GLYPH $66    ; f
    ROW "...##.."
    ROW "..#..#."
    ROW "..#...."
    ROW ".####.."
    ROW "..#...."
    ROW "..#...."
    ROW "..#...."
    ROW "......."

    GLYPH $67    ; g
    ROW "......."
    ROW "......."
    ROW "..###.."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..####."
    ROW ".....#."
    ROW "..###.."

    GLYPH $68    ; h
    ROW ".#....."
    ROW ".#....."
    ROW ".####.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "......."

    GLYPH $69    ; i
    ROW "...#..."
    ROW "......."
    ROW "..##..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "..###.."
    ROW "......."

    GLYPH $6A    ; j
    ROW "....#.."
    ROW "......."
    ROW "...##.."
    ROW "....#.."
    ROW "....#.."
    ROW "....#.."
    ROW ".#..#.."
    ROW "..##..."

    GLYPH $6B    ; k
    ROW ".#....."
    ROW ".#....."
    ROW ".#...#."
    ROW ".#..#.."
    ROW ".###..."
    ROW ".#..#.."
    ROW ".#...#."
    ROW "......."

    GLYPH $6C    ; l
    ROW "..##..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "..###.."
    ROW "......."

    GLYPH $6D    ; m
    ROW "......."
    ROW "......."
    ROW ".##.##."
    ROW ".#.#.#."
    ROW ".#.#.#."
    ROW ".#.#.#."
    ROW ".#...#."
    ROW "......."

    GLYPH $6E    ; n
    ROW "......."
    ROW "......."
    ROW ".####.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "......."

    GLYPH $6F    ; o
    ROW "......."
    ROW "......."
    ROW "..###.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..###.."
    ROW "......."

    GLYPH $70    ; p
    ROW "......."
    ROW "......."
    ROW ".####.."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".####.."
    ROW ".#....."
    ROW ".#....."

    GLYPH $71    ; q
    ROW "......."
    ROW "......."
    ROW "..####."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..####."
    ROW ".....#."
    ROW ".....#."

    GLYPH $72    ; r
    ROW "......."
    ROW "......."
    ROW ".#.###."
    ROW ".##...."
    ROW ".#....."
    ROW ".#....."
    ROW ".#....."
    ROW "......."

    GLYPH $73    ; s
    ROW "......."
    ROW "......."
    ROW "..####."
    ROW ".#....."
    ROW "..###.."
    ROW ".....#."
    ROW ".####.."
    ROW "......."

    GLYPH $74    ; t
    ROW "..#...."
    ROW "..#...."
    ROW ".####.."
    ROW "..#...."
    ROW "..#...."
    ROW "..#..#."
    ROW "...##.."
    ROW "......."

    GLYPH $75    ; u
    ROW "......."
    ROW "......."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#..##."
    ROW "..##.#."
    ROW "......."

    GLYPH $76    ; v
    ROW "......."
    ROW "......."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..#.#.."
    ROW "...#..."
    ROW "......."

    GLYPH $77    ; w
    ROW "......."
    ROW "......."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#.#.#."
    ROW ".#.#.#."
    ROW ".##.##."
    ROW "......."

    GLYPH $78    ; x
    ROW "......."
    ROW "......."
    ROW ".#...#."
    ROW "..#.#.."
    ROW "...#..."
    ROW "..#.#.."
    ROW ".#...#."
    ROW "......."

    GLYPH $79    ; y
    ROW "......."
    ROW "......."
    ROW ".#...#."
    ROW ".#...#."
    ROW ".#...#."
    ROW "..####."
    ROW ".....#."
    ROW "..###.."

    GLYPH $7A    ; z
    ROW "......."
    ROW "......."
    ROW ".#####."
    ROW "....#.."
    ROW "...#..."
    ROW "..#...."
    ROW ".#####."
    ROW "......."

    GLYPH $7B    ; {
    ROW "...###."
    ROW "..##..."
    ROW "..##..."
    ROW ".##...."
    ROW "..##..."
    ROW "..##..."
    ROW "...###."
    ROW "......."

    GLYPH $7C    ; |
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."

    GLYPH $7D    ; }
    ROW ".###..."
    ROW "...##.."
    ROW "...##.."
    ROW "....##."
    ROW "...##.."
    ROW "...##.."
    ROW ".###..."
    ROW "......."

    GLYPH $7E    ; ~
    ROW "..##.#."
    ROW ".#.##.."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $7F    ; DEL
    ROW "......."
    ROW ".#.#.#."
    ROW "..#.#.."
    ROW ".#.#.#."
    ROW "..#.#.."
    ROW ".#.#.#."
    ROW "......."
    ROW "......."
.endmacro

.org $0000

.if IIBOARD
; The II and II Plus: the 64 glyphs four times, bit 7 set in the second and fourth.
.repeat 2
Flash .set 0
    UPPERCASE
    SYMBOLS
Flash .set 1
    UPPERCASE
    SYMBOLS
.endrepeat
.else
; $00-$3F: inverse.
Inverse .set 1
    UPPERCASE
    SYMBOLS

.if ENHANCED
; $40-$5F: MouseText.
Inverse .set 0
    GLYPH $40    ; closed apple
    ROW "....#.."
    ROW "...#..."
    ROW ".##.##."
    ROW "#######"
    ROW "######."
    ROW "######."
    ROW ".######"
    ROW ".##.##."

    GLYPH $41    ; open apple
    ROW "....#.."
    ROW "...#..."
    ROW ".##.##."
    ROW "#.....#"
    ROW "#....#."
    ROW "#....#."
    ROW ".#.#..#"
    ROW ".##.##."

    GLYPH $42    ; mouse pointer
    ROW "......."
    ROW "......."
    ROW ".#....."
    ROW ".##...."
    ROW ".###..."
    ROW ".####.."
    ROW ".##.##."
    ROW ".#....#"

    GLYPH $43    ; hourglass
    ROW "#######"
    ROW ".#...#."
    ROW "..#.#.."
    ROW "...#..."
    ROW "...#..."
    ROW "..#.#.."
    ROW ".#.#.#."
    ROW "#######"

    GLYPH $44    ; checkmark
    ROW "......."
    ROW "......#"
    ROW ".....#."
    ROW "#...#.."
    ROW ".#.#..."
    ROW "..#...."
    ROW "..#...."
    ROW "......."

    GLYPH $45    ; inverse checkmark
    ROW "#######"
    ROW "######."
    ROW "#####.#"
    ROW "..##.##"
    ROW "#.#.###"
    ROW "##.####"
    ROW "##.####"
    ROW "#######"

    GLYPH $46    ; running man
    ROW "....###"
    ROW ".....##"
    ROW ".######"
    ROW "#...##."
    ROW "#..####"
    ROW "....##."
    ROW "######."
    ROW ".#....."

    GLYPH $47    ; running man, second half
    ROW "......."
    ROW "...##.."
    ROW "###...."
    ROW "......."
    ROW "###...."
    ROW "..##..."
    ROW "...#..."
    ROW "....###"

    GLYPH $48    ; left arrow
    ROW "...#..."
    ROW "..#...."
    ROW ".#....."
    ROW "#######"
    ROW ".#....."
    ROW "..#...."
    ROW "...#..."
    ROW "......."

    GLYPH $49    ; ellipsis
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW ".#.#.#."

    GLYPH $4A    ; down arrow
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "#..#..#"
    ROW ".#.#.#."
    ROW "..###.."
    ROW "...#..."

    GLYPH $4B    ; up arrow
    ROW "...#..."
    ROW "..###.."
    ROW ".#.#.#."
    ROW "#..#..#"
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."
    ROW "...#..."

    GLYPH $4C    ; top bar
    ROW "#######"
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $4D    ; return arrow
    ROW "......#"
    ROW "......#"
    ROW "......#"
    ROW "..#...#"
    ROW ".##...#"
    ROW "#######"
    ROW ".##...."
    ROW "..#...."

    GLYPH $4E    ; solid block
    ROW "######."
    ROW "######."
    ROW "######."
    ROW "######."
    ROW "######."
    ROW "######."
    ROW "######."
    ROW "######."

    GLYPH $4F    ; scroll left
    ROW "##..#.."
    ROW "...##.."
    ROW "..###.."
    ROW ".######"
    ROW "..###.."
    ROW "...##.."
    ROW "....#.."
    ROW "####.##"

    GLYPH $50    ; scroll right
    ROW "..#..##"
    ROW "..##..."
    ROW "..###.."
    ROW "######."
    ROW "..###.."
    ROW "..##..."
    ROW "..#...."
    ROW "##.####"

    GLYPH $51    ; scroll down
    ROW "......#"
    ROW "...#..#"
    ROW "...#..."
    ROW "#######"
    ROW ".#####."
    ROW "..###.."
    ROW "...#..#"
    ROW "......#"

    GLYPH $52    ; scroll up
    ROW "......#"
    ROW "...#..#"
    ROW "..###.."
    ROW ".#####."
    ROW "#######"
    ROW "...#..."
    ROW "...#..#"
    ROW "......#"

    GLYPH $53    ; middle bar
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "#######"
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."

    GLYPH $54    ; lower-left corner
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#######"

    GLYPH $55    ; right arrow
    ROW "...#..."
    ROW "....#.."
    ROW ".....#."
    ROW "#######"
    ROW ".....#."
    ROW "....#.."
    ROW "...#..."
    ROW "......."

    GLYPH $56    ; checkerboard
    ROW ".#.#.#."
    ROW "#.#.#.#"
    ROW ".#.#.#."
    ROW "#.#.#.#"
    ROW ".#.#.#."
    ROW "#.#.#.#"
    ROW ".#.#.#."
    ROW "#.#.#.#"

    GLYPH $57    ; checkerboard, shifted
    ROW "#.#.#.#"
    ROW ".#.#.#."
    ROW "#.#.#.#"
    ROW ".#.#.#."
    ROW "#.#.#.#"
    ROW ".#.#.#."
    ROW "#.#.#.#"
    ROW ".#.#.#."

    GLYPH $58    ; folder, left half
    ROW "......."
    ROW ".#####."
    ROW "#.....#"
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#######"
    ROW "......."

    GLYPH $59    ; folder, right half
    ROW "......."
    ROW "......."
    ROW "######."
    ROW "......#"
    ROW "......#"
    ROW "......#"
    ROW "#######"
    ROW "......."

    GLYPH $5A    ; right bar
    ROW "......#"
    ROW "......#"
    ROW "......#"
    ROW "......#"
    ROW "......#"
    ROW "......#"
    ROW "......#"
    ROW "......#"

    GLYPH $5B    ; diamond
    ROW "...#..."
    ROW "..###.."
    ROW ".#####."
    ROW "#######"
    ROW ".#####."
    ROW "..###.."
    ROW "...#..."
    ROW "......."

    GLYPH $5C    ; top and bottom bars
    ROW "#######"
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "......."
    ROW "#######"

    GLYPH $5D    ; crossing
    ROW "..#.#.."
    ROW "..#.#.."
    ROW "###.###"
    ROW "......."
    ROW "###.###"
    ROW "..#.#.."
    ROW "..#.#.."
    ROW "......."

    GLYPH $5E    ; box
    ROW "#######"
    ROW "......#"
    ROW "......#"
    ROW "..##..#"
    ROW "..##..#"
    ROW "......#"
    ROW "......#"
    ROW "#######"

    GLYPH $5F    ; left bar
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#......"
    ROW "#......"

.else
; $40-$5F: inverse uppercase again.
    UPPERCASE
.endif

; $60-$7F: inverse lowercase.
Inverse .set 1
    LOWERCASE

; $80-$FF: normal.
Inverse .set 0
    UPPERCASE
    SYMBOLS
    UPPERCASE
    LOWERCASE

; $800-$FFF: a pattern for each byte value.
.repeat 256, Value
    Low .set Value & $0F
    High .set Value >> 4
    .byte $80 | (~Value & $7F), $80 | (~Value & $7F)
    .byte ~(Low * $11) & $FF, ~((((Low << 2) | (Low >> 2)) & $0F) * $11) & $FF
    .byte $80 | (~Value & $7F), $80 | (~Value & $7F)
    .byte ~(High * $11) & $FF, ~((((High << 2) | (High >> 2)) & $0F) * $11) & $FF
.endrepeat
.endif
