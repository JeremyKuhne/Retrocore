;; SAA5050 TELETEXT CHARACTER GENERATOR: THE CHARACTERS
;;
;; Mode 7's text comes from a Mullard SAA5050, which turns each character code in the screen memory into dots and
;; carries out the teletext control codes itself. Its mask ROM holds 96 characters, codes &20-&7F, each ten rows of
;; five dots from the top of its cell; bits 4-0 of a row are its dots from left to right. The top row is always blank
;; and the characters sit in the nine below it, the lowest only for descenders. Each glyph is six dots wide on the
;; screen, the sixth always blank, and ten scanlines high in each field.
;;
;; The chip draws a character at twice its resolution, interlaced: it rounds the diagonals by filling half-dots
;; where two dots touch only at a corner, so the five-by-nine matrix shows as ten by eighteen. Retrocore's
;; BbcTeletext does that rounding from these rows, and makes the block graphics (codes &20-&3F and &60-&7F after a
;; graphics colour code) and double height itself, as the chip does; only these 96 characters come from the ROM.
;;
;; This is the English character set: the codes where ASCII has #, [, \, ], ^, _, `, {, |, } and ~ show the pound
;; sign, the arrows, the fractions and the other teletext symbols. In mode 7 the MOS's OSWRCH translates # to &5F,
;; _ to &60 and the pound sign (&60) to &23, so that a program's text shows as typed.
;; See: <Mos:TELETEXT_TRANSLATION>
;;
;; Assembles byte-identically to the 960 bytes of characters in MAME's saa5050 set. Maintained by hand;
;; BbcSaa5050SourceTests check it.

;; Starts a character: checks that it lands at its place, (code - &20) * 10, and draws its blank top row.
;; Parameters:
;;   code = the character code, &20-&7F
.macro GLYPH code
    .assert * = ((code) - $20) * 10, "A GLYPH is out of order."
    .byte 0
.endmacro

;; One row of a character: five dots, # for a lit dot and . for a dark one.
;; Parameters:
;;   dots = the row, a string of five characters
.macro ROW dots
    .assert .strlen(dots) = 5, "A ROW has five dots."
    SAA5050_ROW .set 0
    .repeat 5, dot
        SAA5050_ROW .set (SAA5050_ROW << 1) | (.strat(dots, dot) = '#')
    .endrepeat
    .byte SAA5050_ROW
.endmacro

.org $0000

    GLYPH $20                      ; space
    ROW "....."
    ROW "....."
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
    ROW "....."
    ROW "....."

    GLYPH $22                      ; quotation mark
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $23                      ; pound sign
    ROW "..##."
    ROW ".#..#"
    ROW ".#..."
    ROW "###.."
    ROW ".#..."
    ROW ".#..."
    ROW "#####"
    ROW "....."
    ROW "....."

    GLYPH $24                      ; $
    ROW ".###."
    ROW "#.#.#"
    ROW "#.#.."
    ROW ".###."
    ROW "..#.#"
    ROW "#.#.#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $25                      ; %
    ROW "##..."
    ROW "##..#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#..##"
    ROW "...##"
    ROW "....."
    ROW "....."

    GLYPH $26                      ; &
    ROW ".#..."
    ROW "#.#.."
    ROW "#.#.."
    ROW ".#..."
    ROW "#.#.#"
    ROW "#..#."
    ROW ".##.#"
    ROW "....."
    ROW "....."

    GLYPH $27                      ; apostrophe
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."
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
    ROW "....."
    ROW "....."

    GLYPH $29                      ; )
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "...#."
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "....."
    ROW "....."

    GLYPH $2A                      ; *
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."
    ROW ".###."
    ROW "#.#.#"
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $2B                      ; +
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $2C                      ; comma
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW ".#..."
    ROW "....."

    GLYPH $2D                      ; hyphen
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $2E                      ; full stop
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $2F                      ; /
    ROW "....."
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $30                      ; 0
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $31                      ; 1
    ROW "..#.."
    ROW ".##.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $32                      ; 2
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW "..##."
    ROW ".#..."
    ROW "#...."
    ROW "#####"
    ROW "....."
    ROW "....."

    GLYPH $33                      ; 3
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..##."
    ROW "....#"
    ROW "#...#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $34                      ; 4
    ROW "...#."
    ROW "..##."
    ROW ".#.#."
    ROW "#..#."
    ROW "#####"
    ROW "...#."
    ROW "...#."
    ROW "....."
    ROW "....."

    GLYPH $35                      ; 5
    ROW "#####"
    ROW "#...."
    ROW "####."
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $36                      ; 6
    ROW "..##."
    ROW ".#..."
    ROW "#...."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $37                      ; 7
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW "....."
    ROW "....."

    GLYPH $38                      ; 8
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $39                      ; 9
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW "...#."
    ROW ".##.."
    ROW "....."
    ROW "....."

    GLYPH $3A                      ; :
    ROW "....."
    ROW "....."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $3B                      ; ;
    ROW "....."
    ROW "....."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW ".#..."
    ROW "....."

    GLYPH $3C                      ; <
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "....."
    ROW "....."

    GLYPH $3D                      ; =
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "....."
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
    ROW "....."
    ROW "....."

    GLYPH $3F                      ; ?
    ROW ".###."
    ROW "#...#"
    ROW "...#."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $40                      ; @
    ROW ".###."
    ROW "#...#"
    ROW "#.###"
    ROW "#.#.#"
    ROW "#.###"
    ROW "#...."
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $41                      ; A
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $42                      ; B
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "....."
    ROW "....."

    GLYPH $43                      ; C
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $44                      ; D
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "....."
    ROW "....."

    GLYPH $45                      ; E
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#####"
    ROW "....."
    ROW "....."

    GLYPH $46                      ; F
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "....."
    ROW "....."

    GLYPH $47                      ; G
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW "#...."
    ROW "#..##"
    ROW "#...#"
    ROW ".####"
    ROW "....."
    ROW "....."

    GLYPH $48                      ; H
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $49                      ; I
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $4A                      ; J
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $4B                      ; K
    ROW "#...#"
    ROW "#..#."
    ROW "#.#.."
    ROW "##..."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $4C                      ; L
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#####"
    ROW "....."
    ROW "....."

    GLYPH $4D                      ; M
    ROW "#...#"
    ROW "##.##"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $4E                      ; N
    ROW "#...#"
    ROW "#...#"
    ROW "##..#"
    ROW "#.#.#"
    ROW "#..##"
    ROW "#...#"
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $4F                      ; O
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $50                      ; P
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "....."
    ROW "....."

    GLYPH $51                      ; Q
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#..#."
    ROW ".##.#"
    ROW "....."
    ROW "....."

    GLYPH $52                      ; R
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $53                      ; S
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW ".###."
    ROW "....#"
    ROW "#...#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $54                      ; T
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $55                      ; U
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $56                      ; V
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW ".#.#."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $57                      ; W
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".#.#."
    ROW "....."
    ROW "....."

    GLYPH $58                      ; X
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $59                      ; Y
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $5A                      ; Z
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "#####"
    ROW "....."
    ROW "....."

    GLYPH $5B                      ; left arrow
    ROW "....."
    ROW "..#.."
    ROW ".#..."
    ROW "#####"
    ROW ".#..."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $5C                      ; one half
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#.##."
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW "..###"

    GLYPH $5D                      ; right arrow
    ROW "....."
    ROW "..#.."
    ROW "...#."
    ROW "#####"
    ROW "...#."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $5E                      ; up arrow
    ROW "....."
    ROW "..#.."
    ROW ".###."
    ROW "#.#.#"
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $5F                      ; hash
    ROW ".#.#."
    ROW ".#.#."
    ROW "#####"
    ROW ".#.#."
    ROW "#####"
    ROW ".#.#."
    ROW ".#.#."
    ROW "....."
    ROW "....."

    GLYPH $60                      ; long dash
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "....."
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
    ROW "....."
    ROW "....."

    GLYPH $62                      ; b
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "....."
    ROW "....."

    GLYPH $63                      ; c
    ROW "....."
    ROW "....."
    ROW ".####"
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW ".####"
    ROW "....."
    ROW "....."

    GLYPH $64                      ; d
    ROW "....#"
    ROW "....#"
    ROW ".####"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....."
    ROW "....."

    GLYPH $65                      ; e
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#####"
    ROW "#...."
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $66                      ; f
    ROW "...#."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $67                      ; g
    ROW "....."
    ROW "....."
    ROW ".####"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW ".###."

    GLYPH $68                      ; h
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $69                      ; i
    ROW "..#.."
    ROW "....."
    ROW ".##.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $6A                      ; j
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".#..."

    GLYPH $6B                      ; k
    ROW ".#..."
    ROW ".#..."
    ROW ".#..#"
    ROW ".#.#."
    ROW ".##.."
    ROW ".#.#."
    ROW ".#..#"
    ROW "....."
    ROW "....."

    GLYPH $6C                      ; l
    ROW ".##.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $6D                      ; m
    ROW "....."
    ROW "....."
    ROW "##.#."
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "....."
    ROW "....."

    GLYPH $6E                      ; n
    ROW "....."
    ROW "....."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $6F                      ; o
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."
    ROW "....."

    GLYPH $70                      ; p
    ROW "....."
    ROW "....."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...."
    ROW "#...."

    GLYPH $71                      ; q
    ROW "....."
    ROW "....."
    ROW ".####"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW "....#"

    GLYPH $72                      ; r
    ROW "....."
    ROW "....."
    ROW ".#.##"
    ROW ".##.."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW "....."
    ROW "....."

    GLYPH $73                      ; s
    ROW "....."
    ROW "....."
    ROW ".####"
    ROW "#...."
    ROW ".###."
    ROW "....#"
    ROW "####."
    ROW "....."
    ROW "....."

    GLYPH $74                      ; t
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "...#."
    ROW "....."
    ROW "....."

    GLYPH $75                      ; u
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....."
    ROW "....."

    GLYPH $76                      ; v
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW ".#.#."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $77                      ; w
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".#.#."
    ROW "....."
    ROW "....."

    GLYPH $78                      ; x
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $79                      ; y
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW ".###."

    GLYPH $7A                      ; z
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#####"
    ROW "....."
    ROW "....."

    GLYPH $7B                      ; one quarter
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..#"
    ROW "...##"
    ROW "..#.#"
    ROW "..###"
    ROW "....#"

    GLYPH $7C                      ; double vertical bar
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW "....."
    ROW "....."

    GLYPH $7D                      ; three quarters
    ROW "##..."
    ROW "..#.."
    ROW "##..."
    ROW "..#.."
    ROW "##..#"
    ROW "...##"
    ROW "..#.#"
    ROW "..###"
    ROW "....#"

    GLYPH $7E                      ; divide
    ROW "....."
    ROW "..#.."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $7F                      ; solid block
    ROW "#####"
    ROW "#####"
    ROW "#####"
    ROW "#####"
    ROW "#####"
    ROW "#####"
    ROW "#####"
    ROW "....."
    ROW "....."

    .assert * = 960, "The ROM holds 96 characters of ten rows."
