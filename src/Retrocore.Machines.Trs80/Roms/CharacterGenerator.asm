;; TRS-80 MODEL I CHARACTER GENERATOR (MCM6670P)
;;
;; The Model I draws text from a Motorola MCM6670P character generator: 128 characters of 5x7 dots. Each
;; character takes eight bytes, one per scanline from the top of its cell; the video circuit shows the
;; first eight of a cell's twelve scanlines from here and leaves the rest blank. Bits 4-0 of a row are its
;; dots from left to right. The top row is always blank, so a character's seven rows sit below a gap.
;;
;; Video RAM on a stock Model I has no bit 6: the circuit reads it as the inverse of bit 5, so codes
;; $00-$1F show as $40-$5F and $60-$7F show as $20-$3F. The symbols at $00-$1F and the lowercase letters
;; at $60-$7F appear only with the lowercase modification's seventh bit. Codes $80-$FF are block graphics
;; and never reach the character generator.
;;
;; Assembles byte-identically to the MCM6670P dump (mcm6670p.z29). Maintained by hand.

.cpu Z80

;; Starts a character: checks that it lands at code * 8 and draws its blank top row.
.macro GLYPH code
    .assert * = (code) * 8, "A GLYPH is out of order."
    .byte 0
.endmacro

;; One row of dots: five characters, # for a lit dot and . for a dark one.
.macro ROW dots
    .assert .strlen(dots) = 5, "A ROW has five dots."
    .byte ((.strat(dots, 0) = '#') << 4) | ((.strat(dots, 1) = '#') << 3) | ((.strat(dots, 2) = '#') << 2) | ((.strat(dots, 3) = '#') << 1) | (.strat(dots, 4) = '#')
.endmacro

.org $0000

    GLYPH $00
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#####"

    GLYPH $01
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."

    GLYPH $02
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "#####"

    GLYPH $03
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "#####"

    GLYPH $04
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW ".####"
    ROW "..#.."
    ROW "...#."
    ROW "....#"

    GLYPH $05
    ROW "#####"
    ROW "#...#"
    ROW "##.##"
    ROW "#.#.#"
    ROW "##.##"
    ROW "#...#"
    ROW "#####"

    GLYPH $06
    ROW "....."
    ROW "....#"
    ROW "...#."
    ROW "#.#.."
    ROW "##..."
    ROW "#...."
    ROW "....."

    GLYPH $07
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW ".#.#."
    ROW ".#.#."
    ROW "##.##"

    GLYPH $08
    ROW "..#.."
    ROW ".#..."
    ROW "####."
    ROW ".#..#"
    ROW "..#.#"
    ROW "....#"
    ROW "....#"

    GLYPH $09
    ROW "....."
    ROW "..#.."
    ROW "...#."
    ROW "#####"
    ROW "...#."
    ROW "..#.."
    ROW "....."

    GLYPH $0A
    ROW "#####"
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "....."
    ROW "#####"

    GLYPH $0B
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."
    ROW "....."

    GLYPH $0C
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."

    GLYPH $0D
    ROW "....."
    ROW "..#.."
    ROW ".#..."
    ROW "#####"
    ROW ".#..."
    ROW "..#.."
    ROW "....."

    GLYPH $0E
    ROW ".###."
    ROW "#...#"
    ROW "##.##"
    ROW "#.#.#"
    ROW "##.##"
    ROW "#...#"
    ROW ".###."

    GLYPH $0F
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $10
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "#####"

    GLYPH $11
    ROW ".###."
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.###"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $12
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#.###"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".###."

    GLYPH $13
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "###.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".###."

    GLYPH $14
    ROW ".###."
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "###.#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $15
    ROW "....."
    ROW "..#.#"
    ROW "...#."
    ROW "#.#.#"
    ROW "##..."
    ROW "#...."
    ROW "....."

    GLYPH $16
    ROW ".###."
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW "##.##"

    GLYPH $17
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "#####"
    ROW "....#"
    ROW "....#"
    ROW "....#"

    GLYPH $18
    ROW "#####"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#####"

    GLYPH $19
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."

    GLYPH $1A
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW ".#..."
    ROW "..#.."
    ROW "....."
    ROW "..#.."

    GLYPH $1B
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $1C
    ROW "#####"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "###.#"
    ROW "#...#"
    ROW "#...#"
    ROW "#####"

    GLYPH $1D
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "###.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#####"

    GLYPH $1E
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "#.###"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#####"

    GLYPH $1F
    ROW "#####"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.###"
    ROW "#...#"
    ROW "#...#"
    ROW "#####"

    GLYPH $20                      ; space
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $21                      ; !
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "..#.."

    GLYPH $22                      ; "
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $23                      ; #
    ROW ".#.#."
    ROW ".#.#."
    ROW "#####"
    ROW ".#.#."
    ROW "#####"
    ROW ".#.#."
    ROW ".#.#."

    GLYPH $24                      ; $
    ROW "..#.."
    ROW ".####"
    ROW "#.#.."
    ROW ".###."
    ROW "..#.#"
    ROW "####."
    ROW "..#.."

    GLYPH $25                      ; %
    ROW "##..."
    ROW "##..#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#..##"
    ROW "...##"

    GLYPH $26                      ; &
    ROW ".#..."
    ROW "#.#.."
    ROW "#.#.."
    ROW ".#..."
    ROW "#.#.#"
    ROW "#..#."
    ROW ".##.#"

    GLYPH $27                      ; '
    ROW ".##.."
    ROW ".##.."
    ROW ".#..."
    ROW "#...."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $28                      ; (
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW "..#.."
    ROW "...#."

    GLYPH $29                      ; )
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "...#."
    ROW "...#."
    ROW "..#.."
    ROW ".#..."

    GLYPH $2A                      ; *
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "#####"
    ROW ".###."
    ROW "#.#.#"
    ROW "..#.."

    GLYPH $2B                      ; +
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $2C                      ; ,
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".##.."
    ROW ".##.."
    ROW ".#..."
    ROW "#...."

    GLYPH $2D                      ; -
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $2E                      ; .
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".##.."
    ROW ".##.."

    GLYPH $2F                      ; /
    ROW "....."
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "....."

    GLYPH $30                      ; 0
    ROW ".###."
    ROW "#...#"
    ROW "#..##"
    ROW "#.#.#"
    ROW "##..#"
    ROW "#...#"
    ROW ".###."

    GLYPH $31                      ; 1
    ROW "..#.."
    ROW ".##.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."

    GLYPH $32                      ; 2
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW ".###."
    ROW "#...."
    ROW "#...."
    ROW "#####"

    GLYPH $33                      ; 3
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW "..##."
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $34                      ; 4
    ROW "...#."
    ROW "..##."
    ROW ".#.#."
    ROW "#..#."
    ROW "#####"
    ROW "...#."
    ROW "...#."

    GLYPH $35                      ; 5
    ROW "#####"
    ROW "#...."
    ROW "####."
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $36                      ; 6
    ROW "..##."
    ROW ".#..."
    ROW "#...."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $37                      ; 7
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "#...."

    GLYPH $38                      ; 8
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $39                      ; 9
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW "...#."
    ROW ".##.."

    GLYPH $3A                      ; :
    ROW "....."
    ROW ".##.."
    ROW ".##.."
    ROW "....."
    ROW ".##.."
    ROW ".##.."
    ROW "....."

    GLYPH $3B                      ; ;
    ROW ".##.."
    ROW ".##.."
    ROW "....."
    ROW ".##.."
    ROW ".##.."
    ROW ".#..."
    ROW "#...."

    GLYPH $3C                      ; <
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW ".#..."
    ROW "..#.."
    ROW "...#."

    GLYPH $3D                      ; =
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "....."

    GLYPH $3E                      ; >
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."

    GLYPH $3F                      ; ?
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW "....."
    ROW "..#.."

    GLYPH $40                      ; @
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW ".##.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".###."

    GLYPH $41                      ; A
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"

    GLYPH $42                      ; B
    ROW "####."
    ROW ".#..#"
    ROW ".#..#"
    ROW ".###."
    ROW ".#..#"
    ROW ".#..#"
    ROW "####."

    GLYPH $43                      ; C
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...#"
    ROW ".###."

    GLYPH $44                      ; D
    ROW "####."
    ROW ".#..#"
    ROW ".#..#"
    ROW ".#..#"
    ROW ".#..#"
    ROW ".#..#"
    ROW "####."

    GLYPH $45                      ; E
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "###.."
    ROW "#...."
    ROW "#...."
    ROW "#####"

    GLYPH $46                      ; F
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "###.."
    ROW "#...."
    ROW "#...."
    ROW "#...."

    GLYPH $47                      ; G
    ROW ".####"
    ROW "#...."
    ROW "#...."
    ROW "#..##"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"

    GLYPH $48                      ; H
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"

    GLYPH $49                      ; I
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."

    GLYPH $4A                      ; J
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $4B                      ; K
    ROW "#...#"
    ROW "#..#."
    ROW "#.#.."
    ROW "##..."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"

    GLYPH $4C                      ; L
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#####"

    GLYPH $4D                      ; M
    ROW "#...#"
    ROW "##.##"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"

    GLYPH $4E                      ; N
    ROW "#...#"
    ROW "##..#"
    ROW "#.#.#"
    ROW "#..##"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"

    GLYPH $4F                      ; O
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $50                      ; P
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#...."

    GLYPH $51                      ; Q
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#..#."
    ROW ".##.#"

    GLYPH $52                      ; R
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"

    GLYPH $53                      ; S
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW ".###."
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $54                      ; T
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."

    GLYPH $55                      ; U
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $56                      ; V
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW ".#.#."
    ROW "..#.."
    ROW "..#.."

    GLYPH $57                      ; W
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "##.##"
    ROW "#...#"

    GLYPH $58                      ; X
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"

    GLYPH $59                      ; Y
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."

    GLYPH $5A                      ; Z
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "#####"

    GLYPH $5B                      ; up arrow
    ROW "..#.."
    ROW ".###."
    ROW "#.#.#"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."

    GLYPH $5C                      ; down arrow
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."

    GLYPH $5D                      ; left arrow
    ROW "....."
    ROW "..#.."
    ROW ".#..."
    ROW "#####"
    ROW ".#..."
    ROW "..#.."
    ROW "....."

    GLYPH $5E                      ; right arrow
    ROW "....."
    ROW "..#.."
    ROW "...#."
    ROW "#####"
    ROW "...#."
    ROW "..#.."
    ROW "....."

    GLYPH $5F                      ; underline
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#####"

    GLYPH $60                      ; `
    ROW "..##."
    ROW "..##."
    ROW "..#.."
    ROW "...#."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $61                      ; a
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "....#"
    ROW ".####"
    ROW "#...#"
    ROW ".####"

    GLYPH $62                      ; b
    ROW "#...."
    ROW "#...."
    ROW "#.##."
    ROW "##..#"
    ROW "#...#"
    ROW "##..#"
    ROW "#.##."

    GLYPH $63                      ; c
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW "#...#"
    ROW ".###."

    GLYPH $64                      ; d
    ROW "....#"
    ROW "....#"
    ROW ".##.#"
    ROW "#..##"
    ROW "#...#"
    ROW "#..##"
    ROW ".##.#"

    GLYPH $65                      ; e
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#####"
    ROW "#...."
    ROW ".###."

    GLYPH $66                      ; f
    ROW "...#."
    ROW "..#.#"
    ROW "..#.."
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."

    GLYPH $67                      ; g
    ROW ".##.#"
    ROW "#..##"
    ROW "#..##"
    ROW ".##.#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $68                      ; h
    ROW "#...."
    ROW "#...."
    ROW "#.##."
    ROW "##..#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"

    GLYPH $69                      ; i
    ROW "..#.."
    ROW "....."
    ROW ".##.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."

    GLYPH $6A                      ; j
    ROW "....#"
    ROW "....."
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $6B                      ; k
    ROW "#...."
    ROW "#...."
    ROW "#..#."
    ROW "#.#.."
    ROW "##..."
    ROW "#.#.."
    ROW "#..#."

    GLYPH $6C                      ; l
    ROW ".##.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."

    GLYPH $6D                      ; m
    ROW "....."
    ROW "....."
    ROW "##.#."
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.#.#"

    GLYPH $6E                      ; n
    ROW "....."
    ROW "....."
    ROW "#.##."
    ROW "##..#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"

    GLYPH $6F                      ; o
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $70                      ; p
    ROW "#.##."
    ROW "##..#"
    ROW "#...#"
    ROW "##..#"
    ROW "#.##."
    ROW "#...."
    ROW "#...."

    GLYPH $71                      ; q
    ROW ".##.#"
    ROW "#..##"
    ROW "#...#"
    ROW "#..##"
    ROW ".##.#"
    ROW "....#"
    ROW "....#"

    GLYPH $72                      ; r
    ROW "....."
    ROW "....."
    ROW "#.##."
    ROW "##..#"
    ROW "#...."
    ROW "#...."
    ROW "#...."

    GLYPH $73                      ; s
    ROW "....."
    ROW "....."
    ROW ".####"
    ROW "#...."
    ROW ".###."
    ROW "....#"
    ROW "####."

    GLYPH $74                      ; t
    ROW "..#.."
    ROW "..#.."
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.#"
    ROW "...#."

    GLYPH $75                      ; u
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#..##"
    ROW ".##.#"

    GLYPH $76                      ; v
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."

    GLYPH $77                      ; w
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".#.#."

    GLYPH $78                      ; x
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"

    GLYPH $79                      ; y
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $7A                      ; z
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#####"

    GLYPH $7B                      ; {
    ROW "...#."
    ROW "..#.."
    ROW "..#.."
    ROW ".#..."
    ROW "..#.."
    ROW "..#.."
    ROW "...#."

    GLYPH $7C                      ; |
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."

    GLYPH $7D                      ; }
    ROW ".#..."
    ROW "..#.."
    ROW "..#.."
    ROW "...#."
    ROW "..#.."
    ROW "..#.."
    ROW ".#..."

    GLYPH $7E                      ; ~
    ROW ".#..."
    ROW "#.#.#"
    ROW "...#."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $7F
    ROW ".#.#."
    ROW "#.#.#"
    ROW ".#.#."
    ROW "#.#.#"
    ROW ".#.#."
    ROW "#.#.#"
    ROW ".#.#."
