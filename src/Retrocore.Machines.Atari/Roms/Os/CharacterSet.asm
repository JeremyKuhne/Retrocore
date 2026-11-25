;; THE CHARACTER SET ($E000-$E3FF)
;;
;; The OS's 128 characters of 8x8 dots, in ANTIC's internal order rather than ATASCII's: $00-$1F are ATASCII's
;; $20-$3F (space, punctuation and digits), $20-$3F are $40-$5F (capitals), $40-$5F are $00-$1F (the graphics
;; characters) and $60-$7F are lower case, with a diamond before it and five symbols after it. Each character is
;; eight bytes from its top row, bit 7 at the left. Each open of the screen sets CHBAS to this page, $E0. Characters
;; $80-$FF are these shown in inverse video. Every revision has the same characters.

;; Starts a character: checks that it lands at its place in the set.
;;
;; Parameters: code = the character's internal code, $00-$7F
;; See: <ROW>
.macro GLYPH code
    .assert * = DISPLAY_CHARACTER_SET + (code) * 8, "A GLYPH is out of order."
.endmacro

;; One row of dots: eight characters from left to right, # for a lit dot and . for a dark one.
;;
;; Parameters: dots = the row's dots
;; See: <GLYPH>
.macro ROW dots
    .assert .strlen(dots) = 8, "A ROW has eight dots."
    Lit .set ((.strat(dots, 0) = '#') << 7) | ((.strat(dots, 1) = '#') << 6) | ((.strat(dots, 2) = '#') << 5)
    Lit .set Lit | ((.strat(dots, 3) = '#') << 4) | ((.strat(dots, 4) = '#') << 3) | ((.strat(dots, 5) = '#') << 2)
    .byte Lit | ((.strat(dots, 6) = '#') << 1) | (.strat(dots, 7) = '#')
.endmacro

;; The character set, whose page the editor's open stores in CHBAS. Each GLYPH's comment gives its ATASCII code.
DISPLAY_CHARACTER_SET:

; Space, punctuation and digits: ATASCII $20-$3F.

    GLYPH $00    ; $20 space
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $01    ; $21 !
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "...##..."
    ROW "........"

    GLYPH $02    ; $22 "
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $03    ; $23 #
    ROW "........"
    ROW ".##..##."
    ROW "########"
    ROW ".##..##."
    ROW ".##..##."
    ROW "########"
    ROW ".##..##."
    ROW "........"

    GLYPH $04    ; $24 $
    ROW "...##..."
    ROW "..#####."
    ROW ".##....."
    ROW "..####.."
    ROW ".....##."
    ROW ".#####.."
    ROW "...##..."
    ROW "........"

    GLYPH $05    ; $25 %
    ROW "........"
    ROW ".##..##."
    ROW ".##.##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".##..##."
    ROW ".#...##."
    ROW "........"

    GLYPH $06    ; $26 &
    ROW "...###.."
    ROW "..##.##."
    ROW "...###.."
    ROW "..###..."
    ROW ".##.####"
    ROW ".##..##."
    ROW "..###.##"
    ROW "........"

    GLYPH $07    ; $27 '
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $08    ; $28 (
    ROW "........"
    ROW "....###."
    ROW "...###.."
    ROW "...##..."
    ROW "...##..."
    ROW "...###.."
    ROW "....###."
    ROW "........"

    GLYPH $09    ; $29 )
    ROW "........"
    ROW ".###...."
    ROW "..###..."
    ROW "...##..."
    ROW "...##..."
    ROW "..###..."
    ROW ".###...."
    ROW "........"

    GLYPH $0A    ; $2A *
    ROW "........"
    ROW ".##..##."
    ROW "..####.."
    ROW "########"
    ROW "..####.."
    ROW ".##..##."
    ROW "........"
    ROW "........"

    GLYPH $0B    ; $2B +
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW ".######."
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "........"

    GLYPH $0C    ; $2C ,
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "..##...."

    GLYPH $0D    ; $2D -
    ROW "........"
    ROW "........"
    ROW "........"
    ROW ".######."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $0E    ; $2E .
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $0F    ; $2F /
    ROW "........"
    ROW ".....##."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".##....."
    ROW ".#......"
    ROW "........"

    GLYPH $10    ; $30 0
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW ".##.###."
    ROW ".###.##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $11    ; $31 1
    ROW "........"
    ROW "...##..."
    ROW "..###..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW ".######."
    ROW "........"

    GLYPH $12    ; $32 2
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".######."
    ROW "........"

    GLYPH $13    ; $33 3
    ROW "........"
    ROW ".######."
    ROW "....##.."
    ROW "...##..."
    ROW "....##.."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $14    ; $34 4
    ROW "........"
    ROW "....##.."
    ROW "...###.."
    ROW "..####.."
    ROW ".##.##.."
    ROW ".######."
    ROW "....##.."
    ROW "........"

    GLYPH $15    ; $35 5
    ROW "........"
    ROW ".######."
    ROW ".##....."
    ROW ".#####.."
    ROW ".....##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $16    ; $36 6
    ROW "........"
    ROW "..####.."
    ROW ".##....."
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $17    ; $37 7
    ROW "........"
    ROW ".######."
    ROW ".....##."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW "..##...."
    ROW "........"

    GLYPH $18    ; $38 8
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $19    ; $39 9
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW "..#####."
    ROW ".....##."
    ROW "....##.."
    ROW "..###..."
    ROW "........"

    GLYPH $1A    ; $3A :
    ROW "........"
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $1B    ; $3B ;
    ROW "........"
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "..##...."

    GLYPH $1C    ; $3C <
    ROW ".....##."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW "...##..."
    ROW "....##.."
    ROW ".....##."
    ROW "........"

    GLYPH $1D    ; $3D =
    ROW "........"
    ROW "........"
    ROW ".######."
    ROW "........"
    ROW "........"
    ROW ".######."
    ROW "........"
    ROW "........"

    GLYPH $1E    ; $3E >
    ROW ".##....."
    ROW "..##...."
    ROW "...##..."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".##....."
    ROW "........"

    GLYPH $1F    ; $3F ?
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW "....##.."
    ROW "...##..."
    ROW "........"
    ROW "...##..."
    ROW "........"

; Capitals: ATASCII $40-$5F.

    GLYPH $20    ; $40 @
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW ".##.###."
    ROW ".##.###."
    ROW ".##....."
    ROW "..#####."
    ROW "........"

    GLYPH $21    ; $41 A
    ROW "........"
    ROW "...##..."
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".######."
    ROW ".##..##."
    ROW "........"

    GLYPH $22    ; $42 B
    ROW "........"
    ROW ".#####.."
    ROW ".##..##."
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW "........"

    GLYPH $23    ; $43 C
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW ".##....."
    ROW ".##....."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $24    ; $44 D
    ROW "........"
    ROW ".####..."
    ROW ".##.##.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##.##.."
    ROW ".####..."
    ROW "........"

    GLYPH $25    ; $45 E
    ROW "........"
    ROW ".######."
    ROW ".##....."
    ROW ".#####.."
    ROW ".##....."
    ROW ".##....."
    ROW ".######."
    ROW "........"

    GLYPH $26    ; $46 F
    ROW "........"
    ROW ".######."
    ROW ".##....."
    ROW ".#####.."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW "........"

    GLYPH $27    ; $47 G
    ROW "........"
    ROW "..#####."
    ROW ".##....."
    ROW ".##....."
    ROW ".##.###."
    ROW ".##..##."
    ROW "..#####."
    ROW "........"

    GLYPH $28    ; $48 H
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW ".######."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $29    ; $49 I
    ROW "........"
    ROW ".######."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW ".######."
    ROW "........"

    GLYPH $2A    ; $4A J
    ROW "........"
    ROW ".....##."
    ROW ".....##."
    ROW ".....##."
    ROW ".....##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $2B    ; $4B K
    ROW "........"
    ROW ".##..##."
    ROW ".##.##.."
    ROW ".####..."
    ROW ".####..."
    ROW ".##.##.."
    ROW ".##..##."
    ROW "........"

    GLYPH $2C    ; $4C L
    ROW "........"
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".######."
    ROW "........"

    GLYPH $2D    ; $4D M
    ROW "........"
    ROW ".##...##"
    ROW ".###.###"
    ROW ".#######"
    ROW ".##.#.##"
    ROW ".##...##"
    ROW ".##...##"
    ROW "........"

    GLYPH $2E    ; $4E N
    ROW "........"
    ROW ".##..##."
    ROW ".###.##."
    ROW ".######."
    ROW ".######."
    ROW ".##.###."
    ROW ".##..##."
    ROW "........"

    GLYPH $2F    ; $4F O
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $30    ; $50 P
    ROW "........"
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW ".##....."
    ROW ".##....."
    ROW "........"

    GLYPH $31    ; $51 Q
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##.##.."
    ROW "..##.##."
    ROW "........"

    GLYPH $32    ; $52 R
    ROW "........"
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW ".##.##.."
    ROW ".##..##."
    ROW "........"

    GLYPH $33    ; $53 S
    ROW "........"
    ROW "..####.."
    ROW ".##....."
    ROW "..####.."
    ROW ".....##."
    ROW ".....##."
    ROW "..####.."
    ROW "........"

    GLYPH $34    ; $54 T
    ROW "........"
    ROW ".######."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $35    ; $55 U
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".######."
    ROW "........"

    GLYPH $36    ; $56 V
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "...##..."
    ROW "........"

    GLYPH $37    ; $57 W
    ROW "........"
    ROW ".##...##"
    ROW ".##...##"
    ROW ".##.#.##"
    ROW ".#######"
    ROW ".###.###"
    ROW ".##...##"
    ROW "........"

    GLYPH $38    ; $58 X
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $39    ; $59 Y
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $3A    ; $5A Z
    ROW "........"
    ROW ".######."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".##....."
    ROW ".######."
    ROW "........"

    GLYPH $3B    ; $5B [
    ROW "........"
    ROW "...####."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...####."
    ROW "........"

    GLYPH $3C    ; $5C \
    ROW "........"
    ROW ".#......"
    ROW ".##....."
    ROW "..##...."
    ROW "...##..."
    ROW "....##.."
    ROW ".....##."
    ROW "........"

    GLYPH $3D    ; $5D ]
    ROW "........"
    ROW ".####..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW ".####..."
    ROW "........"

    GLYPH $3E    ; $5E ^
    ROW "........"
    ROW "....#..."
    ROW "...###.."
    ROW "..##.##."
    ROW ".##...##"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $3F    ; $5F _
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "........"

; The graphics characters: ATASCII $00-$1F, typed with CTRL.

    GLYPH $40    ; $00 heart
    ROW "........"
    ROW "..##.##."
    ROW ".#######"
    ROW ".#######"
    ROW "..#####."
    ROW "...###.."
    ROW "....#..."
    ROW "........"

    GLYPH $41    ; $01 vertical line with a right branch
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...#####"
    ROW "...#####"
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."

    GLYPH $42    ; $02 vertical bar at the right
    ROW "......##"
    ROW "......##"
    ROW "......##"
    ROW "......##"
    ROW "......##"
    ROW "......##"
    ROW "......##"
    ROW "......##"

    GLYPH $43    ; $03 lower right corner
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "#####..."
    ROW "#####..."
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $44    ; $04 vertical line with a left branch
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "#####..."
    ROW "#####..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."

    GLYPH $45    ; $05 upper right corner
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "#####..."
    ROW "#####..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."

    GLYPH $46    ; $06 diagonal rising to the right
    ROW "......##"
    ROW ".....###"
    ROW "....###."
    ROW "...###.."
    ROW "..###..."
    ROW ".###...."
    ROW "###....."
    ROW "##......"

    GLYPH $47    ; $07 diagonal falling to the right
    ROW "##......"
    ROW "###....."
    ROW ".###...."
    ROW "..###..."
    ROW "...###.."
    ROW "....###."
    ROW ".....###"
    ROW "......##"

    GLYPH $48    ; $08 lower right triangle
    ROW ".......#"
    ROW "......##"
    ROW ".....###"
    ROW "....####"
    ROW "...#####"
    ROW "..######"
    ROW ".#######"
    ROW "########"

    GLYPH $49    ; $09 lower right quarter block
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "....####"
    ROW "....####"
    ROW "....####"
    ROW "....####"

    GLYPH $4A    ; $0A lower left triangle
    ROW "#......."
    ROW "##......"
    ROW "###....."
    ROW "####...."
    ROW "#####..."
    ROW "######.."
    ROW "#######."
    ROW "########"

    GLYPH $4B    ; $0B upper right quarter block
    ROW "....####"
    ROW "....####"
    ROW "....####"
    ROW "....####"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $4C    ; $0C upper left quarter block
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $4D    ; $0D bar at the top
    ROW "########"
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $4E    ; $0E bar at the bottom
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "########"

    GLYPH $4F    ; $0F lower left quarter block
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."

    GLYPH $50    ; $10 club
    ROW "........"
    ROW "...###.."
    ROW "...###.."
    ROW ".###.###"
    ROW ".###.###"
    ROW "....#..."
    ROW "...###.."
    ROW "........"

    GLYPH $51    ; $11 upper left corner
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "...#####"
    ROW "...#####"
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."

    GLYPH $52    ; $12 horizontal line
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $53    ; $13 cross
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "########"
    ROW "########"
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."

    GLYPH $54    ; $14 ball
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".######."
    ROW ".######."
    ROW ".######."
    ROW "..####.."
    ROW "........"

    GLYPH $55    ; $15 lower half block
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "########"
    ROW "########"
    ROW "########"

    GLYPH $56    ; $16 vertical bar at the left
    ROW "##......"
    ROW "##......"
    ROW "##......"
    ROW "##......"
    ROW "##......"
    ROW "##......"
    ROW "##......"
    ROW "##......"

    GLYPH $57    ; $17 horizontal line with a lower branch
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "########"
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."

    GLYPH $58    ; $18 horizontal line with an upper branch
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "########"
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $59    ; $19 left half block
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."

    GLYPH $5A    ; $1A lower left corner
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...#####"
    ROW "...#####"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $5B    ; $1B escape
    ROW ".####..."
    ROW ".##....."
    ROW ".####..."
    ROW ".##....."
    ROW ".######."
    ROW "...##..."
    ROW "...####."
    ROW "........"

    GLYPH $5C    ; $1C up arrow
    ROW "........"
    ROW "...##..."
    ROW "..####.."
    ROW ".######."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $5D    ; $1D down arrow
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW ".######."
    ROW "..####.."
    ROW "...##..."
    ROW "........"

    GLYPH $5E    ; $1E left arrow
    ROW "........"
    ROW "...##..."
    ROW "..##...."
    ROW ".######."
    ROW "..##...."
    ROW "...##..."
    ROW "........"
    ROW "........"

    GLYPH $5F    ; $1F right arrow
    ROW "........"
    ROW "...##..."
    ROW "....##.."
    ROW ".######."
    ROW "....##.."
    ROW "...##..."
    ROW "........"
    ROW "........"

; Lower case and five symbols: ATASCII $60-$7F.

    GLYPH $60    ; $60 diamond
    ROW "........"
    ROW "...##..."
    ROW "..####.."
    ROW ".######."
    ROW ".######."
    ROW "..####.."
    ROW "...##..."
    ROW "........"

    GLYPH $61    ; $61 a
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".....##."
    ROW "..#####."
    ROW ".##..##."
    ROW "..#####."
    ROW "........"

    GLYPH $62    ; $62 b
    ROW "........"
    ROW ".##....."
    ROW ".##....."
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW "........"

    GLYPH $63    ; $63 c
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW "..####.."
    ROW "........"

    GLYPH $64    ; $64 d
    ROW "........"
    ROW ".....##."
    ROW ".....##."
    ROW "..#####."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW "........"

    GLYPH $65    ; $65 e
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW ".######."
    ROW ".##....."
    ROW "..####.."
    ROW "........"

    GLYPH $66    ; $66 f
    ROW "........"
    ROW "....###."
    ROW "...##..."
    ROW "..#####."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $67    ; $67 g
    ROW "........"
    ROW "........"
    ROW "..#####."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW ".....##."
    ROW ".#####.."

    GLYPH $68    ; $68 h
    ROW "........"
    ROW ".##....."
    ROW ".##....."
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $69    ; $69 i
    ROW "........"
    ROW "...##..."
    ROW "........"
    ROW "..###..."
    ROW "...##..."
    ROW "...##..."
    ROW "..####.."
    ROW "........"

    GLYPH $6A    ; $6A j
    ROW "........"
    ROW ".....##."
    ROW "........"
    ROW ".....##."
    ROW ".....##."
    ROW ".....##."
    ROW ".....##."
    ROW "..####.."

    GLYPH $6B    ; $6B k
    ROW "........"
    ROW ".##....."
    ROW ".##....."
    ROW ".##.##.."
    ROW ".####..."
    ROW ".##.##.."
    ROW ".##..##."
    ROW "........"

    GLYPH $6C    ; $6C l
    ROW "........"
    ROW "..###..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "..####.."
    ROW "........"

    GLYPH $6D    ; $6D m
    ROW "........"
    ROW "........"
    ROW ".##..##."
    ROW ".#######"
    ROW ".#######"
    ROW ".##.#.##"
    ROW ".##...##"
    ROW "........"

    GLYPH $6E    ; $6E n
    ROW "........"
    ROW "........"
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $6F    ; $6F o
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $70    ; $70 p
    ROW "........"
    ROW "........"
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW ".##....."
    ROW ".##....."

    GLYPH $71    ; $71 q
    ROW "........"
    ROW "........"
    ROW "..#####."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW ".....##."
    ROW ".....##."

    GLYPH $72    ; $72 r
    ROW "........"
    ROW "........"
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW "........"

    GLYPH $73    ; $73 s
    ROW "........"
    ROW "........"
    ROW "..#####."
    ROW ".##....."
    ROW "..####.."
    ROW ".....##."
    ROW ".#####.."
    ROW "........"

    GLYPH $74    ; $74 t
    ROW "........"
    ROW "...##..."
    ROW ".######."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "....###."
    ROW "........"

    GLYPH $75    ; $75 u
    ROW "........"
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW "........"

    GLYPH $76    ; $76 v
    ROW "........"
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "...##..."
    ROW "........"

    GLYPH $77    ; $77 w
    ROW "........"
    ROW "........"
    ROW ".##...##"
    ROW ".##.#.##"
    ROW ".#######"
    ROW "..#####."
    ROW "..##.##."
    ROW "........"

    GLYPH $78    ; $78 x
    ROW "........"
    ROW "........"
    ROW ".##..##."
    ROW "..####.."
    ROW "...##..."
    ROW "..####.."
    ROW ".##..##."
    ROW "........"

    GLYPH $79    ; $79 y
    ROW "........"
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW "....##.."
    ROW ".####..."

    GLYPH $7A    ; $7A z
    ROW "........"
    ROW "........"
    ROW ".######."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".######."
    ROW "........"

    GLYPH $7B    ; $7B spade
    ROW "........"
    ROW "...##..."
    ROW "..####.."
    ROW ".######."
    ROW ".######."
    ROW "...##..."
    ROW "..####.."
    ROW "........"

    GLYPH $7C    ; $7C vertical line
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."

    GLYPH $7D    ; $7D clear screen arrow
    ROW "........"
    ROW ".######."
    ROW ".####..."
    ROW ".#####.."
    ROW ".##.###."
    ROW ".##..##."
    ROW ".....##."
    ROW "........"

    GLYPH $7E    ; $7E backspace triangle
    ROW "....#..."
    ROW "...##..."
    ROW "..###..."
    ROW ".####..."
    ROW "..###..."
    ROW "...##..."
    ROW "....#..."
    ROW "........"

    GLYPH $7F    ; $7F tab triangle
    ROW "...#...."
    ROW "...##..."
    ROW "...###.."
    ROW "...####."
    ROW "...###.."
    ROW "...##..."
    ROW "...#...."
    ROW "........"
