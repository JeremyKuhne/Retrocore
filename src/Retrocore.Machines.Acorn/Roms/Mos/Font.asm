;; The MOS's font for characters 32-127, which modes 0-6 draw text with.
;;
;; Each character is eight bytes, one for each scan line from the top of its cell, with bit 7 the leftmost pixel.
;; <FIND_CHARACTER_DEFINITION> works out the page of this font's three zones of 32 characters, &C0, &C1 and &C2,
;; from the character code; only a zone that <FONT_FLAGS> marks as in RAM, after OSBYTE 20 explodes it, takes its
;; page from <FONT_LOCATIONS>. Character 96 is the pound sign, as on the keyboard; teletext shows it through
;; <TELETEXT_TRANSLATION>. Characters 128-255 have no ROM shapes: their four zones start out in RAM, all sharing
;; <FONT_RAM>, and an explosion gives each a page of its own.
;; See: <FONT_FLAGS>, <FONT_LOCATIONS>
FONT:

;; Starts a character's shape: checks that it lands where <FONT> puts the character code.
.macro GLYPH code
    .assert * = FONT + ((code) - 32) * 8, "A GLYPH is out of order."
.endmacro

;; One scan line of a character: eight characters, # for a foreground pixel and . for background, left to right.
.macro ROW dots
    .assert .strlen(dots) = 8, "A ROW has eight pixels."
    FONT_ROW .set 0
    .repeat 8, pixel
        FONT_ROW .set (FONT_ROW << 1) | (.strat(dots, pixel) = '#')
    .endrepeat
    .byte FONT_ROW
.endmacro


    GLYPH $20                       ; a space
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $21                       ; '!'
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "...##..."
    ROW "........"

    GLYPH $22                       ; '"'
    ROW ".##.##.."
    ROW ".##.##.."
    ROW ".##.##.."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $23                       ; '#'
    ROW "..##.##."
    ROW "..##.##."
    ROW ".#######"
    ROW "..##.##."
    ROW ".#######"
    ROW "..##.##."
    ROW "..##.##."
    ROW "........"

    GLYPH $24                       ; '$'
    ROW "....##.."
    ROW "..######"
    ROW ".##.#..."
    ROW "..#####."
    ROW "....#.##"
    ROW ".######."
    ROW "...##..."
    ROW "........"

    GLYPH $25                       ; '%'
    ROW ".##....."
    ROW ".##..##."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".##..##."
    ROW ".....##."
    ROW "........"

    GLYPH $26                       ; '&'
    ROW "..###..."
    ROW ".##.##.."
    ROW ".##.##.."
    ROW "..###..."
    ROW ".##.##.#"
    ROW ".##..##."
    ROW "..###.##"
    ROW "........"

    GLYPH $27                       ; "'"
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $28                       ; '('
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW "..##...."
    ROW "..##...."
    ROW "...##..."
    ROW "....##.."
    ROW "........"

    GLYPH $29                       ; ')'
    ROW "..##...."
    ROW "...##..."
    ROW "....##.."
    ROW "....##.."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW "........"

    GLYPH $2A                       ; '*'
    ROW "........"
    ROW "...##..."
    ROW ".######."
    ROW "..####.."
    ROW ".######."
    ROW "...##..."
    ROW "........"
    ROW "........"

    GLYPH $2B                       ; '+'
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW ".######."
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "........"

    GLYPH $2C                       ; ','
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "..##...."

    GLYPH $2D                       ; '-'
    ROW "........"
    ROW "........"
    ROW "........"
    ROW ".######."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $2E                       ; '.'
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $2F                       ; '/'
    ROW "........"
    ROW ".....##."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".##....."
    ROW "........"
    ROW "........"

    GLYPH $30                       ; '0'
    ROW "..####.."
    ROW ".##..##."
    ROW ".##.###."
    ROW ".######."
    ROW ".###.##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $31                       ; '1'
    ROW "...##..."
    ROW "..###..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW ".######."
    ROW "........"

    GLYPH $32                       ; '2'
    ROW "..####.."
    ROW ".##..##."
    ROW ".....##."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".######."
    ROW "........"

    GLYPH $33                       ; '3'
    ROW "..####.."
    ROW ".##..##."
    ROW ".....##."
    ROW "...###.."
    ROW ".....##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $34                       ; '4'
    ROW "....##.."
    ROW "...###.."
    ROW "..####.."
    ROW ".##.##.."
    ROW ".######."
    ROW "....##.."
    ROW "....##.."
    ROW "........"

    GLYPH $35                       ; '5'
    ROW ".######."
    ROW ".##....."
    ROW ".#####.."
    ROW ".....##."
    ROW ".....##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $36                       ; '6'
    ROW "...###.."
    ROW "..##...."
    ROW ".##....."
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $37                       ; '7'
    ROW ".######."
    ROW ".....##."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW "..##...."
    ROW "..##...."
    ROW "........"

    GLYPH $38                       ; '8'
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $39                       ; '9'
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW ".....##."
    ROW "....##.."
    ROW "..###..."
    ROW "........"

    GLYPH $3A                       ; ':'
    ROW "........"
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $3B                       ; ';'
    ROW "........"
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "..##...."

    GLYPH $3C                       ; '<'
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".##....."
    ROW "..##...."
    ROW "...##..."
    ROW "....##.."
    ROW "........"

    GLYPH $3D                       ; '='
    ROW "........"
    ROW "........"
    ROW ".######."
    ROW "........"
    ROW ".######."
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $3E                       ; '>'
    ROW "..##...."
    ROW "...##..."
    ROW "....##.."
    ROW ".....##."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW "........"

    GLYPH $3F                       ; '?'
    ROW "..####.."
    ROW ".##..##."
    ROW "....##.."
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "...##..."
    ROW "........"

    GLYPH $40                       ; '@'
    ROW "..####.."
    ROW ".##..##."
    ROW ".##.###."
    ROW ".##.#.#."
    ROW ".##.###."
    ROW ".##....."
    ROW "..####.."
    ROW "........"

    GLYPH $41                       ; 'A'
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".######."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $42                       ; 'B'
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW "........"

    GLYPH $43                       ; 'C'
    ROW "..####.."
    ROW ".##..##."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $44                       ; 'D'
    ROW ".####..."
    ROW ".##.##.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##.##.."
    ROW ".####..."
    ROW "........"

    GLYPH $45                       ; 'E'
    ROW ".######."
    ROW ".##....."
    ROW ".##....."
    ROW ".#####.."
    ROW ".##....."
    ROW ".##....."
    ROW ".######."
    ROW "........"

    GLYPH $46                       ; 'F'
    ROW ".######."
    ROW ".##....."
    ROW ".##....."
    ROW ".#####.."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW "........"

    GLYPH $47                       ; 'G'
    ROW "..####.."
    ROW ".##..##."
    ROW ".##....."
    ROW ".##.###."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $48                       ; 'H'
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".######."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $49                       ; 'I'
    ROW ".######."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW ".######."
    ROW "........"

    GLYPH $4A                       ; 'J'
    ROW "..#####."
    ROW "....##.."
    ROW "....##.."
    ROW "....##.."
    ROW "....##.."
    ROW ".##.##.."
    ROW "..###..."
    ROW "........"

    GLYPH $4B                       ; 'K'
    ROW ".##..##."
    ROW ".##.##.."
    ROW ".####..."
    ROW ".###...."
    ROW ".####..."
    ROW ".##.##.."
    ROW ".##..##."
    ROW "........"

    GLYPH $4C                       ; 'L'
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".######."
    ROW "........"

    GLYPH $4D                       ; 'M'
    ROW ".##...##"
    ROW ".###.###"
    ROW ".#######"
    ROW ".##.#.##"
    ROW ".##.#.##"
    ROW ".##...##"
    ROW ".##...##"
    ROW "........"

    GLYPH $4E                       ; 'N'
    ROW ".##..##."
    ROW ".##..##."
    ROW ".###.##."
    ROW ".######."
    ROW ".##.###."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $4F                       ; 'O'
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $50                       ; 'P'
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW "........"

    GLYPH $51                       ; 'Q'
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##.#.#."
    ROW ".##.##.."
    ROW "..##.##."
    ROW "........"

    GLYPH $52                       ; 'R'
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW ".##.##.."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $53                       ; 'S'
    ROW "..####.."
    ROW ".##..##."
    ROW ".##....."
    ROW "..####.."
    ROW ".....##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $54                       ; 'T'
    ROW ".######."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $55                       ; 'U'
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $56                       ; 'V'
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "...##..."
    ROW "........"

    GLYPH $57                       ; 'W'
    ROW ".##...##"
    ROW ".##...##"
    ROW ".##.#.##"
    ROW ".##.#.##"
    ROW ".#######"
    ROW ".###.###"
    ROW ".##...##"
    ROW "........"

    GLYPH $58                       ; 'X'
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "...##..."
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $59                       ; 'Y'
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $5A                       ; 'Z'
    ROW ".######."
    ROW ".....##."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".##....."
    ROW ".######."
    ROW "........"

    GLYPH $5B                       ; '['
    ROW ".#####.."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW ".#####.."
    ROW "........"

    GLYPH $5C                       ; '\\'
    ROW "........"
    ROW ".##....."
    ROW "..##...."
    ROW "...##..."
    ROW "....##.."
    ROW ".....##."
    ROW "........"
    ROW "........"

    GLYPH $5D                       ; ']'
    ROW "..#####."
    ROW ".....##."
    ROW ".....##."
    ROW ".....##."
    ROW ".....##."
    ROW ".....##."
    ROW "..#####."
    ROW "........"

    GLYPH $5E                       ; '^'
    ROW "...##..."
    ROW "..####.."
    ROW ".##..##."
    ROW ".#....#."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $5F                       ; '_'
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"

    GLYPH $60                       ; the pound sign
    ROW "...###.."
    ROW "..##.##."
    ROW "..##...."
    ROW ".#####.."
    ROW "..##...."
    ROW "..##...."
    ROW ".######."
    ROW "........"

    GLYPH $61                       ; 'a'
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".....##."
    ROW "..#####."
    ROW ".##..##."
    ROW "..#####."
    ROW "........"

    GLYPH $62                       ; 'b'
    ROW ".##....."
    ROW ".##....."
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW "........"

    GLYPH $63                       ; 'c'
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW ".##....."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $64                       ; 'd'
    ROW ".....##."
    ROW ".....##."
    ROW "..#####."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW "........"

    GLYPH $65                       ; 'e'
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW ".######."
    ROW ".##....."
    ROW "..####.."
    ROW "........"

    GLYPH $66                       ; 'f'
    ROW "...###.."
    ROW "..##...."
    ROW "..##...."
    ROW ".#####.."
    ROW "..##...."
    ROW "..##...."
    ROW "..##...."
    ROW "........"

    GLYPH $67                       ; 'g'
    ROW "........"
    ROW "........"
    ROW "..#####."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW ".....##."
    ROW "..####.."

    GLYPH $68                       ; 'h'
    ROW ".##....."
    ROW ".##....."
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $69                       ; 'i'
    ROW "...##..."
    ROW "........"
    ROW "..###..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "..####.."
    ROW "........"

    GLYPH $6A                       ; 'j'
    ROW "...##..."
    ROW "........"
    ROW "..###..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW ".###...."

    GLYPH $6B                       ; 'k'
    ROW ".##....."
    ROW ".##....."
    ROW ".##..##."
    ROW ".##.##.."
    ROW ".####..."
    ROW ".##.##.."
    ROW ".##..##."
    ROW "........"

    GLYPH $6C                       ; 'l'
    ROW "..###..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "..####.."
    ROW "........"

    GLYPH $6D                       ; 'm'
    ROW "........"
    ROW "........"
    ROW "..##.##."
    ROW ".#######"
    ROW ".##.#.##"
    ROW ".##.#.##"
    ROW ".##...##"
    ROW "........"

    GLYPH $6E                       ; 'n'
    ROW "........"
    ROW "........"
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "........"

    GLYPH $6F                       ; 'o'
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "........"

    GLYPH $70                       ; 'p'
    ROW "........"
    ROW "........"
    ROW ".#####.."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".#####.."
    ROW ".##....."
    ROW ".##....."

    GLYPH $71                       ; 'q'
    ROW "........"
    ROW "........"
    ROW "..#####."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW ".....##."
    ROW ".....###"

    GLYPH $72                       ; 'r'
    ROW "........"
    ROW "........"
    ROW ".##.##.."
    ROW ".###.##."
    ROW ".##....."
    ROW ".##....."
    ROW ".##....."
    ROW "........"

    GLYPH $73                       ; 's'
    ROW "........"
    ROW "........"
    ROW "..#####."
    ROW ".##....."
    ROW "..####.."
    ROW ".....##."
    ROW ".#####.."
    ROW "........"

    GLYPH $74                       ; 't'
    ROW "..##...."
    ROW "..##...."
    ROW ".#####.."
    ROW "..##...."
    ROW "..##...."
    ROW "..##...."
    ROW "...###.."
    ROW "........"

    GLYPH $75                       ; 'u'
    ROW "........"
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW "........"

    GLYPH $76                       ; 'v'
    ROW "........"
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..####.."
    ROW "...##..."
    ROW "........"

    GLYPH $77                       ; 'w'
    ROW "........"
    ROW "........"
    ROW ".##...##"
    ROW ".##.#.##"
    ROW ".##.#.##"
    ROW ".#######"
    ROW "..##.##."
    ROW "........"

    GLYPH $78                       ; 'x'
    ROW "........"
    ROW "........"
    ROW ".##..##."
    ROW "..####.."
    ROW "...##..."
    ROW "..####.."
    ROW ".##..##."
    ROW "........"

    GLYPH $79                       ; 'y'
    ROW "........"
    ROW "........"
    ROW ".##..##."
    ROW ".##..##."
    ROW ".##..##."
    ROW "..#####."
    ROW ".....##."
    ROW "..####.."

    GLYPH $7A                       ; 'z'
    ROW "........"
    ROW "........"
    ROW ".######."
    ROW "....##.."
    ROW "...##..."
    ROW "..##...."
    ROW ".######."
    ROW "........"

    GLYPH $7B                       ; '{'
    ROW "....##.."
    ROW "...##..."
    ROW "...##..."
    ROW ".###...."
    ROW "...##..."
    ROW "...##..."
    ROW "....##.."
    ROW "........"

    GLYPH $7C                       ; '|'
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $7D                       ; '}'
    ROW "..##...."
    ROW "...##..."
    ROW "...##..."
    ROW "....###."
    ROW "...##..."
    ROW "...##..."
    ROW "..##...."
    ROW "........"

    GLYPH $7E                       ; '~'
    ROW "..##...#"
    ROW ".##.#.##"
    ROW ".#...##."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $7F                       ; DELETE
    ROW "########"
    ROW "########"
    ROW "########"
    ROW "########"
    ROW "########"
    ROW "########"
    ROW "########"
    ROW "########"
