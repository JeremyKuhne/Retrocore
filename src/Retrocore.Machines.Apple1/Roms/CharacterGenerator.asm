;; APPLE-1 CHARACTER GENERATOR: THE SIGNETICS 2513
;;
;; The Apple-1's terminal draws its 40x24 text with a Signetics 2513, a mask ROM of 64 characters, each seven
;; rows of five dots. The terminal stores only six bits of each character, and those six bits are the 2513's
;; character address: ASCII bits 0-4, and bit 6 inverted as the high bit, with bit 5 dropped. So the
;; uppercase letters and @ [ \ ] ^ _ ($40-$5F) are characters 0-31, and space, the digits and the punctuation
;; ($20-$3F) are characters 32-63. Lowercase ($60-$7F) lands on the same characters as uppercase.
;;
;; The 2513 is a mask ROM with five outputs, not a byte-wide chip, and no dump of the Apple-1's is published,
;; so this source keeps its own layout: eight bytes a character, one per scanline from the top of the cell,
;; with bits 4-0 the row's five dots from left to right (bit 4 leftmost) and a lit dot 1. The eighth row is
;; always blank, the gap between text lines.
;;
;; The first Apple II boards used the same 2513, and the 7341-0036 that replaced it on later boards holds the
;; same 64 glyphs. Apple1RomTests checks these glyphs against the II board's character generator source, dot for
;; dot. The terminal's cursor is character 0, the @, blinking with character 32, the space.
;;
;; Maintained by hand.

; The row of the character being drawn, 0-6.
Row .set 0

;; Starts a character: checks that it lands at the 2513 address its ASCII code selects.
;;
;; Parameters: code = the character's ASCII code, $20-$5F
;; See: <ROW>
.macro GLYPH code
    .assert (* >> 3) = (((code) & $1F) | ((~(code) & $40) >> 1)), "A GLYPH is out of order."
Row .set 0
.endmacro

;; One row of dots: five characters from left to right, # for a lit dot and . for a dark one. The seventh row
;; also stores the blank eighth.
.macro ROW dots
    .assert .strlen(dots) = 5, "A ROW has five dots."
    .byte ((.strat(dots, 0) = '#') << 4) | ((.strat(dots, 1) = '#') << 3) | ((.strat(dots, 2) = '#') << 2) | ((.strat(dots, 3) = '#') << 1) | (.strat(dots, 4) = '#')
Row .set Row + 1
.if Row = 7
    .byte 0
.endif
.endmacro

    .org 0

; Characters 0-31: @, A-Z and [ \ ] ^ _.
    GLYPH $40    ; @
    ROW ".###."
    ROW "#...#"
    ROW "#.#.#"
    ROW "#.###"
    ROW "#.##."
    ROW "#...."
    ROW ".####"

    GLYPH $41    ; A
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"

    GLYPH $42    ; B
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."

    GLYPH $43    ; C
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...#"
    ROW ".###."

    GLYPH $44    ; D
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "####."

    GLYPH $45    ; E
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#####"

    GLYPH $46    ; F
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#...."

    GLYPH $47    ; G
    ROW ".####"
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#..##"
    ROW "#...#"
    ROW ".####"

    GLYPH $48    ; H
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"

    GLYPH $49    ; I
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."

    GLYPH $4A    ; J
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $4B    ; K
    ROW "#...#"
    ROW "#..#."
    ROW "#.#.."
    ROW "##..."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"

    GLYPH $4C    ; L
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#####"

    GLYPH $4D    ; M
    ROW "#...#"
    ROW "##.##"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"

    GLYPH $4E    ; N
    ROW "#...#"
    ROW "#...#"
    ROW "##..#"
    ROW "#.#.#"
    ROW "#..##"
    ROW "#...#"
    ROW "#...#"

    GLYPH $4F    ; O
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $50    ; P
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#...."

    GLYPH $51    ; Q
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#..#."
    ROW ".##.#"

    GLYPH $52    ; R
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"

    GLYPH $53    ; S
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW ".###."
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $54    ; T
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."

    GLYPH $55    ; U
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $56    ; V
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."

    GLYPH $57    ; W
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "##.##"
    ROW "#...#"

    GLYPH $58    ; X
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"

    GLYPH $59    ; Y
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."

    GLYPH $5A    ; Z
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "#####"

    GLYPH $5B    ; [
    ROW "#####"
    ROW "##..."
    ROW "##..."
    ROW "##..."
    ROW "##..."
    ROW "##..."
    ROW "#####"

    GLYPH $5C    ; \
    ROW "....."
    ROW "#...."
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "....#"
    ROW "....."

    GLYPH $5D    ; ]
    ROW "#####"
    ROW "...##"
    ROW "...##"
    ROW "...##"
    ROW "...##"
    ROW "...##"
    ROW "#####"

    GLYPH $5E    ; ^
    ROW "....."
    ROW "....."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "....."
    ROW "....."

    GLYPH $5F    ; _
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#####"

; Characters 32-63: space, punctuation and digits.
    GLYPH $20    ; space
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $21    ; !
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "..#.."

    GLYPH $22    ; "
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $23    ; #
    ROW ".#.#."
    ROW ".#.#."
    ROW "#####"
    ROW ".#.#."
    ROW "#####"
    ROW ".#.#."
    ROW ".#.#."

    GLYPH $24    ; $
    ROW "..#.."
    ROW ".####"
    ROW "#.#.."
    ROW ".###."
    ROW "..#.#"
    ROW "####."
    ROW "..#.."

    GLYPH $25    ; %
    ROW "##..."
    ROW "##..#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#..##"
    ROW "...##"

    GLYPH $26    ; &
    ROW ".#..."
    ROW "#.#.."
    ROW "#.#.."
    ROW ".#..."
    ROW "#.#.#"
    ROW "#..#."
    ROW ".##.#"

    GLYPH $27    ; '
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $28    ; (
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW ".#..."
    ROW "..#.."

    GLYPH $29    ; )
    ROW "..#.."
    ROW "...#."
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "...#."
    ROW "..#.."

    GLYPH $2A    ; *
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."
    ROW ".###."
    ROW "#.#.#"
    ROW "..#.."

    GLYPH $2B    ; +
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $2C    ; ,
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW ".#..."

    GLYPH $2D    ; -
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "....."
    ROW "....."

    GLYPH $2E    ; .
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "..#.."

    GLYPH $2F    ; /
    ROW "....."
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "....."

    GLYPH $30    ; 0
    ROW ".###."
    ROW "#...#"
    ROW "#..##"
    ROW "#.#.#"
    ROW "##..#"
    ROW "#...#"
    ROW ".###."

    GLYPH $31    ; 1
    ROW "..#.."
    ROW ".##.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."

    GLYPH $32    ; 2
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW "..##."
    ROW ".#..."
    ROW "#...."
    ROW "#####"

    GLYPH $33    ; 3
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..##."
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $34    ; 4
    ROW "...#."
    ROW "..##."
    ROW ".#.#."
    ROW "#..#."
    ROW "#####"
    ROW "...#."
    ROW "...#."

    GLYPH $35    ; 5
    ROW "#####"
    ROW "#...."
    ROW "####."
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."

    GLYPH $36    ; 6
    ROW "..###"
    ROW ".#..."
    ROW "#...."
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $37    ; 7
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."

    GLYPH $38    ; 8
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".###."

    GLYPH $39    ; 9
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW "...#."
    ROW "###.."

    GLYPH $3A    ; :
    ROW "....."
    ROW "....."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $3B    ; ;
    ROW "....."
    ROW "....."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW ".#..."

    GLYPH $3C    ; <
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW ".#..."
    ROW "..#.."
    ROW "...#."

    GLYPH $3D    ; =
    ROW "....."
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "#####"
    ROW "....."
    ROW "....."

    GLYPH $3E    ; >
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."

    GLYPH $3F    ; ?
    ROW ".###."
    ROW "#...#"
    ROW "...#."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    .assert * = 512, "The 2513 holds 64 characters."
