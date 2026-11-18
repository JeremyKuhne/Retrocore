;; KAYPRO II CHARACTER GENERATOR 81-146A
;;
;; The Kaypro II draws text from a 2K character generator: 256 characters of eight bytes, one for each of a
;; character's top eight scanlines (the last two of its ten are always dark). Only bits 4-0 reach the screen, bit 4 at
;; the left, and a dot is lit where its bit is clear; bits 7-5 are always set.
;;
;; The display inverts bit 7 of a video RAM code before it addresses the chip, so the characters a program sees, $00-$7F,
;; are the chip's second half. The first half is blank: a code with bit 7 set addresses it while its blink is off,
;; and the second half while it is on. Codes $00-$1F are the Greek letters that ESC G shows for lowercase ones, and
;; $7F is a checkerboard.
;;
;; Maintained by hand. KayproRomSourceTests check that it assembles byte-identically to the chip's dump.

.cpu Z80

;; Starts a character: checks that it lands at its code's place in the chip's second half.
.macro GLYPH code
    .assert * = $400 + (code) * 8, "A GLYPH is out of order."
.endmacro

;; One scanline: five characters, # for a lit dot and . for a dark one. The chip stores lit dots as clear bits.
.macro ROW dots
    .assert .strlen(dots) = 5, "A ROW has five dots."
    .byte $E0 | (((.strat(dots, 0) != '#') << 4) | ((.strat(dots, 1) != '#') << 3) | ((.strat(dots, 2) != '#') << 2) | ((.strat(dots, 3) != '#') << 1) | (.strat(dots, 4) != '#'))
.endmacro

.org $0000

; The blank half, for blinking characters.
    .res $400, $FF


    GLYPH $00
    ROW ".##.."
    ROW ".##.."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $01
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".##.#"
    ROW "#..#."
    ROW "#..#."
    ROW ".##.#"
    ROW "....."

    GLYPH $02
    ROW "....."
    ROW "....."
    ROW "###.."
    ROW "#..#."
    ROW "###.."
    ROW "#..#."
    ROW "###.."
    ROW "#...."

    GLYPH $03
    ROW "....."
    ROW "....."
    ROW "....#"
    ROW "##.#."
    ROW "..#.."
    ROW ".#.##"
    ROW "#...."
    ROW "....."

    GLYPH $04
    ROW "....."
    ROW ".#..."
    ROW "#...."
    ROW ".##.."
    ROW "#..#."
    ROW "#..#."
    ROW ".##.."
    ROW "....."

    GLYPH $05
    ROW "....."
    ROW "....."
    ROW ".##.."
    ROW "#...."
    ROW "###.."
    ROW "#...."
    ROW ".##.."
    ROW "....."

    GLYPH $06
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."
    ROW "..#.."

    GLYPH $07
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".#..#"
    ROW "#.#.#"
    ROW "...#."
    ROW "...#."
    ROW "..#.."

    GLYPH $08
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#####"
    ROW "#####"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $09
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".#..."
    ROW ".#..."
    ROW ".#.#."
    ROW "..#.."
    ROW "....."

    GLYPH $0A
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".####"
    ROW "#..#."
    ROW "#..#."
    ROW ".##.."
    ROW "....."

    GLYPH $0B
    ROW "....."
    ROW "....."
    ROW "#..#."
    ROW "#..#."
    ROW "###.."
    ROW "#..#."
    ROW "#..#."
    ROW "....."

    GLYPH $0C
    ROW "....."
    ROW "....."
    ROW "#...."
    ROW ".#..."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "....."

    GLYPH $0D
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#..#."
    ROW "#..#."
    ROW "###.."
    ROW "#...."
    ROW "#...."

    GLYPH $0E
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW ".#..#"
    ROW ".#..#"
    ROW "..##."
    ROW "..#.."
    ROW "....."

    GLYPH $0F
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".###."
    ROW "....."

    GLYPH $10
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".####"
    ROW "##.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW "....."

    GLYPH $11
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#.##."
    ROW "##..#"
    ROW "#...#"
    ROW "#...#"
    ROW "....#"

    GLYPH $12
    ROW "....."
    ROW "....."
    ROW "..##."
    ROW ".#..#"
    ROW ".#..#"
    ROW ".###."
    ROW ".#..."
    ROW ".#..."

    GLYPH $13
    ROW "#####"
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#####"
    ROW "....."

    GLYPH $14
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".####"
    ROW "#.#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $15
    ROW "....."
    ROW ".#.#."
    ROW "#.#.#"
    ROW "..#.#"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $16
    ROW "..#.."
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $17
    ROW "....."
    ROW "....."
    ROW "...#."
    ROW "#####"
    ROW "..#.."
    ROW "#####"
    ROW ".#..."
    ROW "....."

    GLYPH $18
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW ".###."
    ROW "....."
    ROW "#####"
    ROW "....."

    GLYPH $19
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "##.##"
    ROW "....."

    GLYPH $1A
    ROW "....."
    ROW "#...."
    ROW "#.##."
    ROW ".###."
    ROW "..#.."
    ROW "...#."
    ROW "...#."
    ROW ".##.."

    GLYPH $1B
    ROW "..##."
    ROW ".#..."
    ROW ".#..."
    ROW "#...."
    ROW ".#..."
    ROW ".#..."
    ROW "..##."
    ROW "....."

    GLYPH $1C
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $1D
    ROW ".##.."
    ROW "...#."
    ROW "...#."
    ROW "....#"
    ROW "...#."
    ROW "...#."
    ROW ".##.."
    ROW "....."

    GLYPH $1E
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".#..."
    ROW "#.#.#"
    ROW "...#."
    ROW "....."
    ROW "....."

    GLYPH $1F
    ROW "#####"
    ROW "#####"
    ROW "#####"
    ROW "#####"
    ROW "#####"
    ROW "#####"
    ROW "#####"
    ROW "....."

    GLYPH $20                      ; space
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $21                      ; '!'
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "....."

    GLYPH $22                      ; '"'
    ROW ".#.#."
    ROW ".#.#."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $23                      ; '#'
    ROW ".#.#."
    ROW ".#.#."
    ROW "#####"
    ROW ".#.#."
    ROW "#####"
    ROW ".#.#."
    ROW ".#.#."
    ROW "....."

    GLYPH $24                      ; '$'
    ROW "..#.."
    ROW ".####"
    ROW "#.#.."
    ROW ".###."
    ROW "..#.#"
    ROW "####."
    ROW "..#.."
    ROW "....."

    GLYPH $25                      ; '%'
    ROW "##..."
    ROW "##..#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#..##"
    ROW "...##"
    ROW "....."

    GLYPH $26                      ; '&'
    ROW ".#..."
    ROW "#.#.."
    ROW "#.#.."
    ROW ".#..."
    ROW "#.#.#"
    ROW "#..#."
    ROW ".##.#"
    ROW "....."

    GLYPH $27
    ROW "..##."
    ROW "..##."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $28                      ; '('
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "....."

    GLYPH $29                      ; ')'
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "...#."
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "....."

    GLYPH $2A                      ; '*'
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."
    ROW ".###."
    ROW "#.#.#"
    ROW "..#.."
    ROW "....."

    GLYPH $2B                      ; '+'
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $2C                      ; ','
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "..##."
    ROW "..##."
    ROW "..#.."

    GLYPH $2D                      ; '-'
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $2E                      ; '.'
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "..##."
    ROW "..##."
    ROW "....."

    GLYPH $2F                      ; '/'
    ROW "....."
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "....."
    ROW "....."

    GLYPH $30                      ; '0'
    ROW ".###."
    ROW "#...#"
    ROW "#..##"
    ROW "#.#.#"
    ROW "##..#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $31                      ; '1'
    ROW "..#.."
    ROW ".##.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "....."

    GLYPH $32                      ; '2'
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#####"
    ROW "....."

    GLYPH $33                      ; '3'
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW "..##."
    ROW "....#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $34                      ; '4'
    ROW "...#."
    ROW "..##."
    ROW ".#.#."
    ROW "#..#."
    ROW "#####"
    ROW "...#."
    ROW "...#."
    ROW "....."

    GLYPH $35                      ; '5'
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "....#"
    ROW "....#"
    ROW "####."
    ROW "....."

    GLYPH $36                      ; '6'
    ROW ".###."
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $37                      ; '7'
    ROW "#####"
    ROW "#...#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW "....."

    GLYPH $38                      ; '8'
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $39                      ; '9'
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW "....#"
    ROW ".###."
    ROW "....."

    GLYPH $3A                      ; ':'
    ROW "....."
    ROW ".##.."
    ROW ".##.."
    ROW "....."
    ROW ".##.."
    ROW ".##.."
    ROW "....."
    ROW "....."

    GLYPH $3B                      ; ';'
    ROW "....."
    ROW "....."
    ROW ".##.."
    ROW ".##.."
    ROW "....."
    ROW ".##.."
    ROW ".##.."
    ROW ".#..."

    GLYPH $3C                      ; '<'
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "....."

    GLYPH $3D                      ; '='
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $3E                      ; '>'
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "....."

    GLYPH $3F                      ; '?'
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "...#."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "....."

    GLYPH $40                      ; '@'
    ROW ".###."
    ROW "#...#"
    ROW "#.#.#"
    ROW "##.##"
    ROW "#.##."
    ROW "#...."
    ROW ".###."
    ROW "....."

    GLYPH $41                      ; 'A'
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $42                      ; 'B'
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "....."

    GLYPH $43                      ; 'C'
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $44                      ; 'D'
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "....."

    GLYPH $45                      ; 'E'
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#####"
    ROW "....."

    GLYPH $46                      ; 'F'
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "....."

    GLYPH $47                      ; 'G'
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW "#..##"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $48                      ; 'H'
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $49                      ; 'I'
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "....."

    GLYPH $4A                      ; 'J'
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $4B                      ; 'K'
    ROW "#...#"
    ROW "#..#."
    ROW "#.#.."
    ROW "##..."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"
    ROW "....."

    GLYPH $4C                      ; 'L'
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#####"
    ROW "....."

    GLYPH $4D                      ; 'M'
    ROW "#...#"
    ROW "##.##"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $4E                      ; 'N'
    ROW "#...#"
    ROW "#...#"
    ROW "##..#"
    ROW "#.#.#"
    ROW "#..##"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $4F                      ; 'O'
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $50                      ; 'P'
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "....."

    GLYPH $51                      ; 'Q'
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#..#."
    ROW ".##.#"
    ROW "....."

    GLYPH $52                      ; 'R'
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"
    ROW "....."

    GLYPH $53                      ; 'S'
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW ".###."
    ROW "....#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $54                      ; 'T'
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $55                      ; 'U'
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $56                      ; 'V'
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW "....."

    GLYPH $57                      ; 'W'
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "##.##"
    ROW "#...#"
    ROW "....."

    GLYPH $58                      ; 'X'
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $59                      ; 'Y'
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $5A                      ; 'Z'
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "#####"
    ROW "....."

    GLYPH $5B                      ; '['
    ROW ".###."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW ".###."
    ROW "....."

    GLYPH $5C
    ROW "....."
    ROW "#...."
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "....#"
    ROW "....."
    ROW "....."

    GLYPH $5D                      ; ']'
    ROW ".###."
    ROW "...#."
    ROW "...#."
    ROW "...#."
    ROW "...#."
    ROW "...#."
    ROW ".###."
    ROW "....."

    GLYPH $5E                      ; '^'
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $5F                      ; '_'
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."

    GLYPH $60                      ; '`'
    ROW ".##.."
    ROW ".##.."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $61                      ; 'a'
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "....#"
    ROW ".####"
    ROW "#...#"
    ROW ".####"
    ROW "....."

    GLYPH $62                      ; 'b'
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "....."

    GLYPH $63                      ; 'c'
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW "#...."
    ROW ".###."
    ROW "....."

    GLYPH $64                      ; 'd'
    ROW "....#"
    ROW "....#"
    ROW ".####"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....."

    GLYPH $65                      ; 'e'
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#####"
    ROW "#...."
    ROW ".###."
    ROW "....."

    GLYPH $66                      ; 'f'
    ROW "..##."
    ROW ".#..#"
    ROW "###.."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW "....."

    GLYPH $67                      ; 'g'
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW ".###."

    GLYPH $68                      ; 'h'
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $69                      ; 'i'
    ROW "..#.."
    ROW "....."
    ROW ".##.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "....."

    GLYPH $6A                      ; 'j'
    ROW "....#"
    ROW "....."
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $6B                      ; 'k'
    ROW ".#..."
    ROW ".#..."
    ROW ".#..#"
    ROW ".#.#."
    ROW ".##.."
    ROW ".#.#."
    ROW ".#..#"
    ROW "....."

    GLYPH $6C                      ; 'l'
    ROW ".##.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "....."

    GLYPH $6D                      ; 'm'
    ROW "....."
    ROW "....."
    ROW "##.#."
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "....."

    GLYPH $6E                      ; 'n'
    ROW "....."
    ROW "....."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $6F                      ; 'o'
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $70                      ; 'p'
    ROW "....."
    ROW "....."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...."
    ROW "#...."

    GLYPH $71                      ; 'q'
    ROW "....."
    ROW "....."
    ROW ".####"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW "....#"

    GLYPH $72                      ; 'r'
    ROW "....."
    ROW "....."
    ROW "#.##."
    ROW ".#..#"
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW "....."

    GLYPH $73                      ; 's'
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...."
    ROW ".###."
    ROW "....#"
    ROW ".###."
    ROW "....."

    GLYPH $74                      ; 't'
    ROW ".#..."
    ROW ".#..."
    ROW "###.."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..#"
    ROW "..##."
    ROW "....."

    GLYPH $75                      ; 'u'
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $76                      ; 'v'
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW ".#.#."
    ROW "..#.."
    ROW "....."

    GLYPH $77                      ; 'w'
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#####"
    ROW ".#.#."
    ROW "....."

    GLYPH $78                      ; 'x'
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "....."

    GLYPH $79                      ; 'y'
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW ".###."

    GLYPH $7A                      ; 'z'
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#####"
    ROW "....."

    GLYPH $7B                      ; '{'
    ROW "..##."
    ROW ".#..."
    ROW ".#..."
    ROW "#...."
    ROW ".#..."
    ROW ".#..."
    ROW "..##."
    ROW "....."

    GLYPH $7C                      ; '|'
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $7D                      ; '}'
    ROW ".##.."
    ROW "...#."
    ROW "...#."
    ROW "....#"
    ROW "...#."
    ROW "...#."
    ROW ".##.."
    ROW "....."

    GLYPH $7E                      ; '~'
    ROW "....."
    ROW "....."
    ROW ".#..."
    ROW "#.#.#"
    ROW "...#."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $7F                      ; delete, a checkerboard
    ROW ".#.#."
    ROW "#.#.#"
    ROW ".#.#."
    ROW "#.#.#"
    ROW ".#.#."
    ROW "#.#.#"
    ROW ".#.#."
    ROW "....."

.assert * = $0800, "The chip is 2K."
