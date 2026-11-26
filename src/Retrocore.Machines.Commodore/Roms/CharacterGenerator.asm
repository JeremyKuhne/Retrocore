;; COMMODORE PET AND VIC-20 CHARACTER ROMS: THE 2001'S 901447-08, THE 2001-N'S 901447-10 AND THE VIC-20'S 901460-03
;;
;; The PET draws its 40 × 25 characters from a 2K character ROM: two sets of 128 characters, eight bytes each, one
;; a scanline from the top of the cell. Bit 7 of a row is its leftmost dot and a lit dot is 1. The VIA's CA2 picks
;; the set: low the first, at $000-$3FF; high the second, at $400-$7FF. Bit 7 of a byte in video RAM draws its
;; character reversed, so the ROM holds no reversed glyphs.
;;
;;   First set:   $00 @, $01-$1A A-Z, $1B-$1F [ \ ] ↑ ←, $20-$3F space, signs and digits, $40-$7F graphics
;;   Second set:  as the first, but $01-$1A a-z and $41-$5A A-Z, with four other graphics at $5E, $5F, $69 and $7A
;;
;; The 2001's chip, 901447-08, has the second set's letters the other way round: capitals at $01-$1A and lowercase
;; at $41-$5A. Its editor, BASIC 1's, stores an unshifted letter as $01-$1A in either set, so on a 2001 switched to
;; the second set the letters typed unshifted show as capitals and shifted ones as lowercase.
;;
;; The VIC-20's 4K chip, 901460-03, is the 901447-10's two sets with a pound sign, £, at $1C in place of the
;; backslash, and each set followed by its reversed copy: the VIC chip has no reverse of its own, so the VIC-20's
;; editor stores a reversed character as its code plus $80, which is the copy. Its sets are at $000-$7FF and
;; $800-$FFF, which bit 1 of the VIC's register 5 picks.
;;
;; Assembles byte-identically to each chip: ORIGINAL selects the 2001's 901447-08 (1; 0, the default, for the
;; 2001-N's 901447-10), and VIC20 the VIC-20's 901460-03 (1; 0, the default, for a PET's). Maintained by hand; the
;; PetRomSourceTests and Vic20RomSourceTests digests check that each assembles byte-identically.

.ifndef ORIGINAL
ORIGINAL = 0
.endif

.ifndef VIC20
VIC20 = 0
.endif

.assert ORIGINAL = 0 || VIC20 = 0, "The VIC-20's chip has the 901447-10's sets, not the 901447-08's."

; 1 while ROW draws a set's reversed copy, with each dot lit and dark the other way round.
Reversed .set 0

;; Starts a character: checks that it lands in its place in the set.
;;
;; Parameters: code = the character's code in its set, $00-$7F
;; See: <ROW>
.macro GLYPH code
    .assert ((* >> 3) & $7F) = (code), "A GLYPH is out of order."
.endmacro

;; One row of dots: eight characters from left to right, # for a lit dot and . for a dark one; while a reversed copy
;; is drawn, each dot is the other way round.
;;
;; Parameters: dots = the row
.macro ROW dots
    .assert .strlen(dots) = 8, "A ROW has eight dots."
.if Reversed
    .byte $FF ^ (((.strat(dots, 0) = '#') << 7) | ((.strat(dots, 1) = '#') << 6) | ((.strat(dots, 2) = '#') << 5) | ((.strat(dots, 3) = '#') << 4) | ((.strat(dots, 4) = '#') << 3) | ((.strat(dots, 5) = '#') << 2) | ((.strat(dots, 6) = '#') << 1) | (.strat(dots, 7) = '#'))
.else
    .byte ((.strat(dots, 0) = '#') << 7) | ((.strat(dots, 1) = '#') << 6) | ((.strat(dots, 2) = '#') << 5) | ((.strat(dots, 3) = '#') << 4) | ((.strat(dots, 4) = '#') << 3) | ((.strat(dots, 5) = '#') << 2) | ((.strat(dots, 6) = '#') << 1) | (.strat(dots, 7) = '#')
.endif
.endmacro

;; The capitals A-Z.
;;
;; Parameters: first = the code of A
.macro UPPERCASE first
    GLYPH first    ; A
    ROW "...##..."
    ROW "..#..#.."
    ROW ".#....#."
    ROW ".######."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 1    ; B
    ROW ".#####.."
    ROW "..#...#."
    ROW "..#...#."
    ROW "..####.."
    ROW "..#...#."
    ROW "..#...#."
    ROW ".#####.."
    ROW "........"

    GLYPH first + 2    ; C
    ROW "...###.."
    ROW "..#...#."
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW "..#...#."
    ROW "...###.."
    ROW "........"

    GLYPH first + 3    ; D
    ROW ".####..."
    ROW "..#..#.."
    ROW "..#...#."
    ROW "..#...#."
    ROW "..#...#."
    ROW "..#..#.."
    ROW ".####..."
    ROW "........"

    GLYPH first + 4    ; E
    ROW ".######."
    ROW ".#......"
    ROW ".#......"
    ROW ".####..."
    ROW ".#......"
    ROW ".#......"
    ROW ".######."
    ROW "........"

    GLYPH first + 5    ; F
    ROW ".######."
    ROW ".#......"
    ROW ".#......"
    ROW ".####..."
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW "........"

    GLYPH first + 6    ; G
    ROW "...###.."
    ROW "..#...#."
    ROW ".#......"
    ROW ".#..###."
    ROW ".#....#."
    ROW "..#...#."
    ROW "...###.."
    ROW "........"

    GLYPH first + 7    ; H
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".######."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 8    ; I
    ROW "...###.."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "...###.."
    ROW "........"

    GLYPH first + 9    ; J
    ROW "....###."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".#...#.."
    ROW "..###..."
    ROW "........"

    GLYPH first + 10    ; K
    ROW ".#....#."
    ROW ".#...#.."
    ROW ".#..#..."
    ROW ".###...."
    ROW ".#..#..."
    ROW ".#...#.."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 11    ; L
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW ".######."
    ROW "........"

    GLYPH first + 12    ; M
    ROW ".#....#."
    ROW ".##..##."
    ROW ".#.##.#."
    ROW ".#.##.#."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 13    ; N
    ROW ".#....#."
    ROW ".##...#."
    ROW ".#.#..#."
    ROW ".#..#.#."
    ROW ".#...##."
    ROW ".#....#."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 14    ; O
    ROW "...##..."
    ROW "..#..#.."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "..#..#.."
    ROW "...##..."
    ROW "........"

    GLYPH first + 15    ; P
    ROW ".#####.."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#####.."
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW "........"

    GLYPH first + 16    ; Q
    ROW "...##..."
    ROW "..#..#.."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#..#.#."
    ROW "..#..#.."
    ROW "...##.#."
    ROW "........"

    GLYPH first + 17    ; R
    ROW ".#####.."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#####.."
    ROW ".#..#..."
    ROW ".#...#.."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 18    ; S
    ROW "..####.."
    ROW ".#....#."
    ROW ".#......"
    ROW "..####.."
    ROW "......#."
    ROW ".#....#."
    ROW "..####.."
    ROW "........"

    GLYPH first + 19    ; T
    ROW "..#####."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "........"

    GLYPH first + 20    ; U
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "..####.."
    ROW "........"

    GLYPH first + 21    ; V
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "..#..#.."
    ROW "..#..#.."
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH first + 22    ; W
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#.##.#."
    ROW ".#.##.#."
    ROW ".##..##."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 23    ; X
    ROW ".#....#."
    ROW ".#....#."
    ROW "..#..#.."
    ROW "...##..."
    ROW "..#..#.."
    ROW ".#....#."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 24    ; Y
    ROW "..#...#."
    ROW "..#...#."
    ROW "..#...#."
    ROW "...###.."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "........"

    GLYPH first + 25    ; Z
    ROW ".######."
    ROW "......#."
    ROW ".....#.."
    ROW "...##..."
    ROW "..#....."
    ROW ".#......"
    ROW ".######."
    ROW "........"
.endmacro

;; The lowercase letters a-z.
;;
;; Parameters: first = the code of a
.macro LOWERCASE first
    GLYPH first    ; a
    ROW "........"
    ROW "........"
    ROW "..###..."
    ROW ".....#.."
    ROW "..####.."
    ROW ".#...#.."
    ROW "..###.#."
    ROW "........"

    GLYPH first + 1    ; b
    ROW ".#......"
    ROW ".#......"
    ROW ".#.###.."
    ROW ".##...#."
    ROW ".#....#."
    ROW ".##...#."
    ROW ".#.###.."
    ROW "........"

    GLYPH first + 2    ; c
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".#....#."
    ROW ".#......"
    ROW ".#....#."
    ROW "..####.."
    ROW "........"

    GLYPH first + 3    ; d
    ROW "......#."
    ROW "......#."
    ROW "..###.#."
    ROW ".#...##."
    ROW ".#....#."
    ROW ".#...##."
    ROW "..###.#."
    ROW "........"

    GLYPH first + 4    ; e
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".#....#."
    ROW ".######."
    ROW ".#......"
    ROW "..####.."
    ROW "........"

    GLYPH first + 5    ; f
    ROW "....##.."
    ROW "...#..#."
    ROW "...#...."
    ROW ".#####.."
    ROW "...#...."
    ROW "...#...."
    ROW "...#...."
    ROW "........"

    GLYPH first + 6    ; g
    ROW "........"
    ROW "........"
    ROW "..###.#."
    ROW ".#...##."
    ROW ".#...##."
    ROW "..###.#."
    ROW "......#."
    ROW "..####.."

    GLYPH first + 7    ; h
    ROW ".#......"
    ROW ".#......"
    ROW ".#.###.."
    ROW ".##...#."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 8    ; i
    ROW "....#..."
    ROW "........"
    ROW "...##..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "...###.."
    ROW "........"

    GLYPH first + 9    ; j
    ROW ".....#.."
    ROW "........"
    ROW "....##.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".#...#.."
    ROW "..###..."

    GLYPH first + 10    ; k
    ROW ".#......"
    ROW ".#......"
    ROW ".#...#.."
    ROW ".#..#..."
    ROW ".#.#...."
    ROW ".##.#..."
    ROW ".#...#.."
    ROW "........"

    GLYPH first + 11    ; l
    ROW "...##..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "...###.."
    ROW "........"

    GLYPH first + 12    ; m
    ROW "........"
    ROW "........"
    ROW ".###.##."
    ROW ".#..#..#"
    ROW ".#..#..#"
    ROW ".#..#..#"
    ROW ".#..#..#"
    ROW "........"

    GLYPH first + 13    ; n
    ROW "........"
    ROW "........"
    ROW ".#.###.."
    ROW ".##...#."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 14    ; o
    ROW "........"
    ROW "........"
    ROW "..####.."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "..####.."
    ROW "........"

    GLYPH first + 15    ; p
    ROW "........"
    ROW "........"
    ROW ".#.###.."
    ROW ".##...#."
    ROW ".##...#."
    ROW ".#.###.."
    ROW ".#......"
    ROW ".#......"

    GLYPH first + 16    ; q
    ROW "........"
    ROW "........"
    ROW "..###.#."
    ROW ".#...##."
    ROW ".#...##."
    ROW "..###.#."
    ROW "......#."
    ROW "......#."

    GLYPH first + 17    ; r
    ROW "........"
    ROW "........"
    ROW ".#.###.."
    ROW ".##...#."
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW "........"

    GLYPH first + 18    ; s
    ROW "........"
    ROW "........"
    ROW "..#####."
    ROW ".#......"
    ROW "..####.."
    ROW "......#."
    ROW ".#####.."
    ROW "........"

    GLYPH first + 19    ; t
    ROW "...#...."
    ROW "...#...."
    ROW ".#####.."
    ROW "...#...."
    ROW "...#...."
    ROW "...#..#."
    ROW "....##.."
    ROW "........"

    GLYPH first + 20    ; u
    ROW "........"
    ROW "........"
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#...##."
    ROW "..###.#."
    ROW "........"

    GLYPH first + 21    ; v
    ROW "........"
    ROW "........"
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "..#..#.."
    ROW "...##..."
    ROW "........"

    GLYPH first + 22    ; w
    ROW "........"
    ROW "........"
    ROW ".#.....#"
    ROW ".#..#..#"
    ROW ".#..#..#"
    ROW ".#..#..#"
    ROW "..##.##."
    ROW "........"

    GLYPH first + 23    ; x
    ROW "........"
    ROW "........"
    ROW ".#....#."
    ROW "..#..#.."
    ROW "...##..."
    ROW "..#..#.."
    ROW ".#....#."
    ROW "........"

    GLYPH first + 24    ; y
    ROW "........"
    ROW "........"
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#...##."
    ROW "..###.#."
    ROW "......#."
    ROW "..####.."

    GLYPH first + 25    ; z
    ROW "........"
    ROW "........"
    ROW ".######."
    ROW ".....#.."
    ROW "...##..."
    ROW "..#....."
    ROW ".######."
    ROW "........"
.endmacro

;; [ \ ] ↑ ←, the space, and the signs and digits of ASCII's $21-$3F, at the same codes in both sets.
.macro SIGNS
    GLYPH $1B    ; [
    ROW "..####.."
    ROW "..#....."
    ROW "..#....."
    ROW "..#....."
    ROW "..#....."
    ROW "..#....."
    ROW "..####.."
    ROW "........"

.if VIC20
    GLYPH $1C    ; £
    ROW "....##.."
    ROW "...#...."
    ROW "...#...."
    ROW "..####.."
    ROW "...#...."
    ROW ".###...."
    ROW ".##.###."
    ROW "........"
.else
    GLYPH $1C    ; \
    ROW "........"
    ROW ".#......"
    ROW "..#....."
    ROW "...#...."
    ROW "....#..."
    ROW ".....#.."
    ROW "......#."
    ROW "........"
.endif

    GLYPH $1D    ; ]
    ROW "..####.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW "..####.."
    ROW "........"

    GLYPH $1E    ; ↑
    ROW "........"
    ROW "....#..."
    ROW "...###.."
    ROW "..#.#.#."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."

    GLYPH $1F    ; ←
    ROW "........"
    ROW "........"
    ROW "...#...."
    ROW "..#....."
    ROW ".#######"
    ROW "..#....."
    ROW "...#...."
    ROW "........"

    GLYPH $20    ; space
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $21    ; !
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "........"
    ROW "........"
    ROW "....#..."
    ROW "........"

    GLYPH $22    ; "
    ROW "..#..#.."
    ROW "..#..#.."
    ROW "..#..#.."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $23    ; #
    ROW "..#..#.."
    ROW "..#..#.."
    ROW ".######."
    ROW "..#..#.."
    ROW ".######."
    ROW "..#..#.."
    ROW "..#..#.."
    ROW "........"

    GLYPH $24    ; $
    ROW "....#..."
    ROW "...####."
    ROW "..#.#..."
    ROW "...###.."
    ROW "....#.#."
    ROW "..####.."
    ROW "....#..."
    ROW "........"

    GLYPH $25    ; %
    ROW "........"
    ROW ".##...#."
    ROW ".##..#.."
    ROW "....#..."
    ROW "...#...."
    ROW "..#..##."
    ROW ".#...##."
    ROW "........"

    GLYPH $26    ; &
    ROW "..##...."
    ROW ".#..#..."
    ROW ".#..#..."
    ROW "..##...."
    ROW ".#..#.#."
    ROW ".#...#.."
    ROW "..###.#."
    ROW "........"

    GLYPH $27    ; '
    ROW ".....#.."
    ROW "....#..."
    ROW "...#...."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $28    ; (
    ROW ".....#.."
    ROW "....#..."
    ROW "...#...."
    ROW "...#...."
    ROW "...#...."
    ROW "....#..."
    ROW ".....#.."
    ROW "........"

    GLYPH $29    ; )
    ROW "..#....."
    ROW "...#...."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "...#...."
    ROW "..#....."
    ROW "........"

    GLYPH $2A    ; *
    ROW "....#..."
    ROW "..#.#.#."
    ROW "...###.."
    ROW "..#####."
    ROW "...###.."
    ROW "..#.#.#."
    ROW "....#..."
    ROW "........"

    GLYPH $2B    ; +
    ROW "........"
    ROW "....#..."
    ROW "....#..."
    ROW "..#####."
    ROW "....#..."
    ROW "....#..."
    ROW "........"
    ROW "........"

    GLYPH $2C    ; ,
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "....#..."
    ROW "....#..."
    ROW "...#...."

    GLYPH $2D    ; -
    ROW "........"
    ROW "........"
    ROW "........"
    ROW ".######."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $2E    ; .
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "...##..."
    ROW "...##..."
    ROW "........"

    GLYPH $2F    ; /
    ROW "........"
    ROW "......#."
    ROW ".....#.."
    ROW "....#..."
    ROW "...#...."
    ROW "..#....."
    ROW ".#......"
    ROW "........"

    GLYPH $30    ; 0
    ROW "..####.."
    ROW ".#....#."
    ROW ".#...##."
    ROW ".#.##.#."
    ROW ".##...#."
    ROW ".#....#."
    ROW "..####.."
    ROW "........"

    GLYPH $31    ; 1
    ROW "....#..."
    ROW "...##..."
    ROW "..#.#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "..#####."
    ROW "........"

    GLYPH $32    ; 2
    ROW "..####.."
    ROW ".#....#."
    ROW "......#."
    ROW "....##.."
    ROW "..##...."
    ROW ".#......"
    ROW ".######."
    ROW "........"

    GLYPH $33    ; 3
    ROW "..####.."
    ROW ".#....#."
    ROW "......#."
    ROW "...###.."
    ROW "......#."
    ROW ".#....#."
    ROW "..####.."
    ROW "........"

    GLYPH $34    ; 4
    ROW ".....#.."
    ROW "....##.."
    ROW "...#.#.."
    ROW "..#..#.."
    ROW ".######."
    ROW ".....#.."
    ROW ".....#.."
    ROW "........"

    GLYPH $35    ; 5
    ROW ".######."
    ROW ".#......"
    ROW ".####..."
    ROW ".....#.."
    ROW "......#."
    ROW ".#...#.."
    ROW "..###..."
    ROW "........"

    GLYPH $36    ; 6
    ROW "...###.."
    ROW "..#....."
    ROW ".#......"
    ROW ".#####.."
    ROW ".#....#."
    ROW ".#....#."
    ROW "..####.."
    ROW "........"

    GLYPH $37    ; 7
    ROW ".######."
    ROW ".#....#."
    ROW ".....#.."
    ROW "....#..."
    ROW "...#...."
    ROW "...#...."
    ROW "...#...."
    ROW "........"

    GLYPH $38    ; 8
    ROW "..####.."
    ROW ".#....#."
    ROW ".#....#."
    ROW "..####.."
    ROW ".#....#."
    ROW ".#....#."
    ROW "..####.."
    ROW "........"

    GLYPH $39    ; 9
    ROW "..####.."
    ROW ".#....#."
    ROW ".#....#."
    ROW "..#####."
    ROW "......#."
    ROW ".....#.."
    ROW "..###..."
    ROW "........"

    GLYPH $3A    ; :
    ROW "........"
    ROW "........"
    ROW "....#..."
    ROW "........"
    ROW "........"
    ROW "....#..."
    ROW "........"
    ROW "........"

    GLYPH $3B    ; ;
    ROW "........"
    ROW "........"
    ROW "....#..."
    ROW "........"
    ROW "........"
    ROW "....#..."
    ROW "....#..."
    ROW "...#...."

    GLYPH $3C    ; <
    ROW "....###."
    ROW "...##..."
    ROW "..##...."
    ROW ".##....."
    ROW "..##...."
    ROW "...##..."
    ROW "....###."
    ROW "........"

    GLYPH $3D    ; =
    ROW "........"
    ROW "........"
    ROW ".######."
    ROW "........"
    ROW ".######."
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $3E    ; >
    ROW ".###...."
    ROW "...##..."
    ROW "....##.."
    ROW ".....##."
    ROW "....##.."
    ROW "...##..."
    ROW ".###...."
    ROW "........"

    GLYPH $3F    ; ?
    ROW "..####.."
    ROW ".#....#."
    ROW "......#."
    ROW "....##.."
    ROW "...#...."
    ROW "........"
    ROW "...#...."
    ROW "........"
.endmacro

;; The graphics, $40-$7F, typed with SHIFT.
;;
;; Remarks: in the second set, $41-$5A hold letters instead, and $5E, $5F, $69 and $7A other graphics.
;; Parameters: second = 1 for the second set, letters = in the second set, 1 for capitals at $41-$5A, as the
;;   901447-10 has, and 0 for lowercase, as the 901447-08 has
.macro GRAPHICS second, letters
    GLYPH $40
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"

.if second
.if letters
    UPPERCASE $41
.else
    LOWERCASE $41
.endif
.else
    GLYPH $41
    ROW "....#..."
    ROW "...###.."
    ROW "..#####."
    ROW ".#######"
    ROW ".#######"
    ROW "...###.."
    ROW "..#####."
    ROW "........"

    GLYPH $42
    ROW "...#...."
    ROW "...#...."
    ROW "...#...."
    ROW "...#...."
    ROW "...#...."
    ROW "...#...."
    ROW "...#...."
    ROW "...#...."

    GLYPH $43
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $44
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $45
    ROW "........"
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $46
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "........"
    ROW "........"

    GLYPH $47
    ROW "..#....."
    ROW "..#....."
    ROW "..#....."
    ROW "..#....."
    ROW "..#....."
    ROW "..#....."
    ROW "..#....."
    ROW "..#....."

    GLYPH $48
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."
    ROW ".....#.."

    GLYPH $49
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "###....."
    ROW "...#...."
    ROW "....#..."
    ROW "....#..."

    GLYPH $4A
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW ".....#.."
    ROW "......##"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $4B
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "...#...."
    ROW "###....."
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $4C
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "########"

    GLYPH $4D
    ROW "#......."
    ROW ".#......"
    ROW "..#....."
    ROW "...#...."
    ROW "....#..."
    ROW ".....#.."
    ROW "......#."
    ROW ".......#"

    GLYPH $4E
    ROW ".......#"
    ROW "......#."
    ROW ".....#.."
    ROW "....#..."
    ROW "...#...."
    ROW "..#....."
    ROW ".#......"
    ROW "#......."

    GLYPH $4F
    ROW "########"
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."

    GLYPH $50
    ROW "########"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"

    GLYPH $51
    ROW "........"
    ROW "..####.."
    ROW ".######."
    ROW ".######."
    ROW ".######."
    ROW ".######."
    ROW "..####.."
    ROW "........"

    GLYPH $52
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "........"

    GLYPH $53
    ROW "..##.##."
    ROW ".#######"
    ROW ".#######"
    ROW ".#######"
    ROW "..#####."
    ROW "...###.."
    ROW "....#..."
    ROW "........"

    GLYPH $54
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"
    ROW ".#......"

    GLYPH $55
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "......##"
    ROW ".....#.."
    ROW "....#..."
    ROW "....#..."

    GLYPH $56
    ROW "#......#"
    ROW ".#....#."
    ROW "..#..#.."
    ROW "...##..."
    ROW "...##..."
    ROW "..#..#.."
    ROW ".#....#."
    ROW "#......#"

    GLYPH $57
    ROW "........"
    ROW "..####.."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW ".#....#."
    ROW "..####.."
    ROW "........"

    GLYPH $58
    ROW "....#..."
    ROW "...###.."
    ROW "..#.#.#."
    ROW ".###.###"
    ROW "..#.#.#."
    ROW "....#..."
    ROW "....#..."
    ROW "........"

    GLYPH $59
    ROW "......#."
    ROW "......#."
    ROW "......#."
    ROW "......#."
    ROW "......#."
    ROW "......#."
    ROW "......#."
    ROW "......#."

    GLYPH $5A
    ROW "....#..."
    ROW "...###.."
    ROW "..#####."
    ROW ".#######"
    ROW "..#####."
    ROW "...###.."
    ROW "....#..."
    ROW "........"
.endif

    GLYPH $5B
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "########"
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."

    GLYPH $5C
    ROW "#.#....."
    ROW ".#.#...."
    ROW "#.#....."
    ROW ".#.#...."
    ROW "#.#....."
    ROW ".#.#...."
    ROW "#.#....."
    ROW ".#.#...."

    GLYPH $5D
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."

.if second
    GLYPH $5E
    ROW "##..##.."
    ROW "##..##.."
    ROW "..##..##"
    ROW "..##..##"
    ROW "##..##.."
    ROW "##..##.."
    ROW "..##..##"
    ROW "..##..##"
.else
    GLYPH $5E
    ROW "........"
    ROW "........"
    ROW ".......#"
    ROW "..#####."
    ROW ".#.#.#.."
    ROW "...#.#.."
    ROW "...#.#.."
    ROW "........"
.endif

.if second
    GLYPH $5F
    ROW "##..##.."
    ROW ".##..##."
    ROW "..##..##"
    ROW "#..##..#"
    ROW "##..##.."
    ROW ".##..##."
    ROW "..##..##"
    ROW "#..##..#"
.else
    GLYPH $5F
    ROW "########"
    ROW ".#######"
    ROW "..######"
    ROW "...#####"
    ROW "....####"
    ROW ".....###"
    ROW "......##"
    ROW ".......#"
.endif

    GLYPH $60
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $61
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."

    GLYPH $62
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "########"
    ROW "########"
    ROW "########"

    GLYPH $63
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $64
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"

    GLYPH $65
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."
    ROW "#......."

    GLYPH $66
    ROW "#.#.#.#."
    ROW ".#.#.#.#"
    ROW "#.#.#.#."
    ROW ".#.#.#.#"
    ROW "#.#.#.#."
    ROW ".#.#.#.#"
    ROW "#.#.#.#."
    ROW ".#.#.#.#"

    GLYPH $67
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"

    GLYPH $68
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "#.#.#.#."
    ROW ".#.#.#.#"
    ROW "#.#.#.#."
    ROW ".#.#.#.#"

.if second
    GLYPH $69
    ROW "#..##..#"
    ROW "..##..##"
    ROW ".##..##."
    ROW "##..##.."
    ROW "#..##..#"
    ROW "..##..##"
    ROW ".##..##."
    ROW "##..##.."
.else
    GLYPH $69
    ROW "########"
    ROW "#######."
    ROW "######.."
    ROW "#####..."
    ROW "####...."
    ROW "###....."
    ROW "##......"
    ROW "#......."
.endif

    GLYPH $6A
    ROW "......##"
    ROW "......##"
    ROW "......##"
    ROW "......##"
    ROW "......##"
    ROW "......##"
    ROW "......##"
    ROW "......##"

    GLYPH $6B
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....####"
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."

    GLYPH $6C
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "....####"
    ROW "....####"
    ROW "....####"
    ROW "....####"

    GLYPH $6D
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....####"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $6E
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "#####..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."

    GLYPH $6F
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "########"

    GLYPH $70
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "....####"
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."

    GLYPH $71
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $72
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."

    GLYPH $73
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "#####..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."

    GLYPH $74
    ROW "##......"
    ROW "##......"
    ROW "##......"
    ROW "##......"
    ROW "##......"
    ROW "##......"
    ROW "##......"
    ROW "##......"

    GLYPH $75
    ROW "###....."
    ROW "###....."
    ROW "###....."
    ROW "###....."
    ROW "###....."
    ROW "###....."
    ROW "###....."
    ROW "###....."

    GLYPH $76
    ROW ".....###"
    ROW ".....###"
    ROW ".....###"
    ROW ".....###"
    ROW ".....###"
    ROW ".....###"
    ROW ".....###"
    ROW ".....###"

    GLYPH $77
    ROW "########"
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $78
    ROW "########"
    ROW "########"
    ROW "########"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $79
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "########"
    ROW "########"
    ROW "########"

.if second
    GLYPH $7A
    ROW ".......#"
    ROW "......#."
    ROW ".#...#.."
    ROW ".#..#..."
    ROW ".#.#...."
    ROW ".##....."
    ROW ".#......"
    ROW "........"
.else
    GLYPH $7A
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW ".......#"
    ROW "########"
.endif

    GLYPH $7B
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."

    GLYPH $7C
    ROW "....####"
    ROW "....####"
    ROW "....####"
    ROW "....####"
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $7D
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "....#..."
    ROW "#####..."
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $7E
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "........"
    ROW "........"
    ROW "........"
    ROW "........"

    GLYPH $7F
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "####...."
    ROW "....####"
    ROW "....####"
    ROW "....####"
    ROW "....####"
.endmacro

.org $0000

;; The first set, uppercase and graphics.
.macro FIRSTSET
    GLYPH $00    ; @
    ROW "...###.."
    ROW "..#...#."
    ROW ".#..#.#."
    ROW ".#.#.##."
    ROW ".#..##.."
    ROW "..#....."
    ROW "...####."
    ROW "........"
    UPPERCASE $01
    SIGNS
    GRAPHICS 0, 0
.endmacro

;; The second set, with lowercase.
.macro SECONDSET
    GLYPH $00    ; @
    ROW "...###.."
    ROW "..#...#."
    ROW ".#..#.#."
    ROW ".#.#.##."
    ROW ".#..##.."
    ROW "..#....."
    ROW "...####."
    ROW "........"
.if ORIGINAL
    UPPERCASE $01
.else
    LOWERCASE $01
.endif
    SIGNS
    GRAPHICS 1, 1 - ORIGINAL
.endmacro

.if VIC20
; $000-$7FF: the first set and its reversed copy; $800-$FFF: the second set and its copy.
    FIRSTSET
Reversed .set 1
    FIRSTSET
Reversed .set 0
    SECONDSET
Reversed .set 1
    SECONDSET
Reversed .set 0
.else
; $000-$3FF: the first set, uppercase and graphics; $400-$7FF: the second set, with lowercase.
    FIRSTSET
    SECONDSET
.endif
