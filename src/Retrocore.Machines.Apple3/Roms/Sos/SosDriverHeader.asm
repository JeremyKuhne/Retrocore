; retrocore: style=strict
;; SOS.DRIVER'S HEADER: THE BUILT-IN DRIVES, THE STANDARD CHARACTER SET AND THE SHOLES KEYBOARD LAYOUT
;;
;; SOS.DRIVER, the file of drivers SOS's loader reads at boot, starts with its label, "SOS DRVR", and a 2-byte count
;; of the header bytes that follow, before its driver modules. This source is that header, 1,314 bytes, as Apple's
;; System Configuration Program writes it:
;;
;;   $000   the number of built-in floppy drives to configure, .D1 to .D4 (a word, 1-4)
;;   $002   the character set's name, 16 characters padded with spaces
;;   $012   the character set: 128 glyphs of 8 bytes, which the loader moves to $0C00
;;   $412   the keyboard layout's name, 16 characters padded with spaces
;;   $422   the keyboard layout: a 256-byte table, which the loader moves to $1700
;;
;; The loader skips the two names. The console driver loads the character set into the video's character memory
;; and translates each key through the keyboard layout.
;;
;; The set is Apple's STANDARD, the same 1,024 bytes as the STANDARD font file on the Business BASIC disk. A glyph's
;; eight rows run from the top of the cell; bits 0-6 of a row are its seven dots from left to right, a lit dot is 1,
;; and bit 7 would make the row flash, which no glyph here does. The control codes $00-$1F have glyphs of their
;; own, small letters naming them.
;;
;; The layout is Apple's SHOLES, the US typewriter layout, named after Christopher Sholes. See <KeyboardLayout>.
;;
;; Assembles byte-identically to the header of SOS.DRIVER on the Business BASIC 1.23 disk (DRIVES = 3, the default)
;; and on the SOS 1.3 System Utilities disk (DRIVES = 2); nothing else differs between them. Maintained by hand;
;; SosDriverHeaderTests checks the digests, and the disks where they are present.

.ifndef DRIVES
DRIVES = 3
.endif

.assert DRIVES >= 1 && DRIVES <= 4, "DRIVES is the number of built-in drives: 1-4."

;; The size of a name in the header: 16 characters.
NAME_SIZE = 16

;; The bytes in a glyph: one for each of its eight rows.
GLYPH_SIZE = 8

;; The glyphs in the character set: codes $00-$7F.
GLYPHS = 128

;; The dots in a row.
DOTS_PER_ROW = 7

;; The keys the keyboard layout lists.
KEYS = 47

;; The bytes of a key's entry: its character alone, with Shift, with Control, and with both.
KEY_SIZE = 4

;; The size of the keyboard layout.
LAYOUT_SIZE = 256

;; The bit of a key's first character that has Alpha Lock type the shifted character instead.
ALPHA_LOCK = $80

;; The bits of a letter that make its control code.
CONTROL_BITS = $1F

;; The bit that makes a capital letter small.
SMALL_BIT = $20

;; The dots of the row being drawn: a lit dot is 1.
Dots .set 0

;; The row of the glyph being drawn, 0-7: <Glyph> starts it at 0 and each <Row> adds 1.
GlyphRow .set 0

;; Starts a glyph: checks that it lands in its place in the character set.
;; Parameters:
;;   code = the character's code, $00-$7F
.macro Glyph code
    .assert * - CharacterSet = (code) * GLYPH_SIZE, "A Glyph is out of order."
    .set GlyphRow, 0
.endmacro

;; One row of a glyph's dots, from the top: bit 0 is the leftmost dot, and a lit dot is 1.
;; Parameters:
;;   dots = seven characters from left to right, # for a lit dot and . for a dark one
.macro Row dots
    .assert .strlen(dots) = DOTS_PER_ROW, "A Row has seven dots."
    .assert GlyphRow < GLYPH_SIZE, "A glyph has eight rows."
    .set Dots, 0
    .repeat DOTS_PER_ROW, column
        .set Dots, Dots | ((.strat(dots, column) = '#') << column)
    .endrepeat
    .byte Dots
    .set GlyphRow, GlyphRow + 1
.endmacro

;; A key's entry in the keyboard layout: the characters it types.
;; Parameters:
;;   alone = with no modifier
;;   shifted = with Shift
;;   control = with Control
;;   both = with Shift and Control
.macro Key alone, shifted, control, both
    .byte alone, shifted, control, both
.endmacro

;; A letter key's entry: small alone, with Alpha Lock typing the capital instead; the capital with Shift; and the
;; control code with Control, with or without Shift.
;; Parameters:
;;   letter = the capital letter
.macro LetterKey letter
    .byte (letter | SMALL_BIT) | ALPHA_LOCK, letter, letter & CONTROL_BITS, letter & CONTROL_BITS
.endmacro

;; An entry of <KeySlots>: the key whose entry a character the keyboard sends reads.
;; Parameters:
;;   key = the key's entry
.macro Slot key
    .byte key - KeyboardLayout
.endmacro

;; The number of built-in floppy drives SOS configures once the drivers load: .D1 and the next DRIVES - 1.
Drives:
    .word DRIVES

;; The character set's name.
CharacterSetName:
    .byte "STANDARD        "

    .assert * - CharacterSetName = NAME_SIZE, "A name is 16 characters."

;; The character set, STANDARD: a glyph for each code from $00 to $7F.
CharacterSet:
    Glyph $00    ; Control-@
    Row "#..#..."
    Row "##.#..."
    Row "#.##..."
    Row "#..#.#."
    Row "...#.#."
    Row "...#.#."
    Row "...###."
    Row "......."

    Glyph $01    ; Control-A
    Row ".##...."
    Row "#......"
    Row ".#.#.#."
    Row "..##.#."
    Row "##.###."
    Row "...#.#."
    Row "...#.#."
    Row "......."

    Glyph $02    ; Control-B
    Row ".##...."
    Row "#......"
    Row ".#.#.#."
    Row "..##.#."
    Row "##..#.."
    Row "...#.#."
    Row "...#.#."
    Row "......."

    Glyph $03    ; Control-C
    Row "###...."
    Row "#......"
    Row "##.#.#."
    Row "#..#.#."
    Row "###.#.."
    Row "...#.#."
    Row "...#.#."
    Row "......."

    Glyph $04    ; Control-D
    Row "###...."
    Row "#......"
    Row "##....."
    Row "#..###."
    Row "###.#.."
    Row "....#.."
    Row "....#.."
    Row "......."

    Glyph $05    ; Control-E
    Row "###...."
    Row "#......"
    Row "##....."
    Row "#...#.."
    Row "####.#."
    Row "...#.#."
    Row "....###"
    Row "......."

    Glyph $06    ; Control-F
    Row ".#....."
    Row "#.#...."
    Row "###...."
    Row "#.#...."
    Row "...#.#."
    Row "...##.."
    Row "...#.#."
    Row "......."

    Glyph $07    ; Control-G
    Row "......."
    Row "...#..."
    Row "..#.#.."
    Row "..#.#.."
    Row "..#.#.."
    Row ".#####."
    Row "...#..."
    Row "......."

    Glyph $08    ; Control-H
    Row "##....."
    Row "#.#...."
    Row "##..##."
    Row "#.##..."
    Row "##..#.."
    Row ".....#."
    Row "...##.."
    Row "......."

    Glyph $09    ; Control-I
    Row "#.#...."
    Row "#.#...."
    Row "###...."
    Row "#.####."
    Row "#.#.#.."
    Row "....#.."
    Row "....#.."
    Row "......."

    Glyph $0A    ; Control-J
    Row "#......"
    Row "#......"
    Row "#..###."
    Row "#..#..."
    Row "#####.."
    Row "...#..."
    Row "...#..."
    Row "......."

    Glyph $0B    ; Control-K
    Row "#.#...."
    Row "#.#...."
    Row "#.#...."
    Row ".#.###."
    Row "....#.."
    Row "....#.."
    Row "....#.."
    Row "......."

    Glyph $0C    ; Control-L
    Row "###...."
    Row "#......"
    Row "##....."
    Row "#..###."
    Row "#..#..."
    Row "...##.."
    Row "...#..."
    Row "......."

    Glyph $0D    ; Control-M
    Row ".##...."
    Row "#......"
    Row "#......"
    Row "#..##.."
    Row ".###.#."
    Row "...##.."
    Row "...#.#."
    Row "......."

    Glyph $0E    ; Control-N
    Row ".##...."
    Row "#......"
    Row ".#....."
    Row "..#.#.."
    Row "##.#.#."
    Row "...#.#."
    Row "....#.."
    Row "......."

    Glyph $0F    ; Control-O
    Row ".##...."
    Row "#......"
    Row ".#....."
    Row "..#.#.."
    Row "##..#.."
    Row "....#.."
    Row "....#.."
    Row "......."

    Glyph $10    ; Control-P
    Row "##....."
    Row "#.#...."
    Row "#.#...."
    Row "##.#..."
    Row "...#..."
    Row "...#..."
    Row "...###."
    Row "......."

    Glyph $11    ; Control-Q
    Row "##....."
    Row "#.#...."
    Row "#.#...."
    Row "##..#.."
    Row "....#.."
    Row "....#.."
    Row "....#.."
    Row "......."

    Glyph $12    ; Control-R
    Row "##....."
    Row "#.#...."
    Row "#.###.."
    Row "##...#."
    Row "....#.."
    Row "...#..."
    Row "...###."
    Row "......."

    Glyph $13    ; Control-S
    Row "##....."
    Row "#.#...."
    Row "#.###.."
    Row "##...#."
    Row "....#.."
    Row ".....#."
    Row "...##.."
    Row "......."

    Glyph $14    ; Control-T
    Row "##....."
    Row "#.#...."
    Row "#.#..#."
    Row "##..##."
    Row "...#.#."
    Row "...###."
    Row ".....#."
    Row "......."

    Glyph $15    ; Control-U
    Row "#..#..."
    Row "##.#..."
    Row "#.##..."
    Row "#..#..."
    Row "...#.#."
    Row "...##.."
    Row "...#.#."
    Row "......."

    Glyph $16    ; Control-V
    Row ".##...."
    Row "#......"
    Row ".#....."
    Row "..##.#."
    Row "##.#.#."
    Row "....#.."
    Row "....#.."
    Row "......."

    Glyph $17    ; Control-W
    Row "###...."
    Row "#......"
    Row "##.##.."
    Row "#..#.#."
    Row "#####.."
    Row "...#.#."
    Row "...##.."
    Row "......."

    Glyph $18    ; Control-X
    Row ".##...."
    Row "#......"
    Row "#......"
    Row "#.#..#."
    Row ".###.#."
    Row "..#.##."
    Row "..#..#."
    Row "......."

    Glyph $19    ; Control-Y
    Row "###...."
    Row "#......"
    Row "##....."
    Row "#..#.#."
    Row "######."
    Row "...#.#."
    Row "...#.#."
    Row "......."

    Glyph $1A    ; Control-Z
    Row ".##...."
    Row "#......"
    Row ".#.##.."
    Row "..##.#."
    Row "##.##.."
    Row "...#.#."
    Row "...##.."
    Row "......."

    Glyph $1B    ; Control-[
    Row "###...."
    Row "#......"
    Row "##....."
    Row "#...##."
    Row "####..."
    Row "...#..."
    Row "....##."
    Row "......."

    Glyph $1C    ; Control-\
    Row "###...."
    Row "#......"
    Row "##..##."
    Row "#..#..."
    Row "#...#.."
    Row ".....#."
    Row "...##.."
    Row "......."

    Glyph $1D    ; Control-]
    Row ".##...."
    Row "#......"
    Row "###.##."
    Row "#.##..."
    Row ".##.#.."
    Row ".....#."
    Row "...##.."
    Row "......."

    Glyph $1E    ; Control-^
    Row "##....."
    Row "#.#...."
    Row "##..##."
    Row "#.##..."
    Row "#.#.#.."
    Row ".....#."
    Row "...##.."
    Row "......."

    Glyph $1F    ; Control-_
    Row "#.#...."
    Row "#.#...."
    Row "#.#.##."
    Row "#.##..."
    Row "###.#.."
    Row ".....#."
    Row "...##.."
    Row "......."

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
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "......."
    Row "#######"

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
    Row "....#.."
    Row "...#..."
    Row ".#####."
    Row "#...#.."
    Row "#...#.."
    Row "#....#."
    Row ".####.."
    Row "......."
    .assert * - CharacterSet = GLYPHS * GLYPH_SIZE, "The character set is 128 glyphs."

;; The keyboard layout's name.
KeyboardLayoutName:
    .byte "SHOLES          "

    .assert * - KeyboardLayoutName = NAME_SIZE, "A name is 16 characters."

;; The keyboard layout, SHOLES, which the console driver reads to turn what the keyboard sends into the character
;; typed.
;;
;; The keyboard sends a character with bit 7 clear (capitals for the letter keys) and the state of Shift, Control
;; and Alpha Lock. The driver folds the character into one of the 64 entries at the table's end, <KeySlots>: a
;; character below $7B by setting its bits 6 and 7, so that 1 ($31) reads $F1 and ! ($21) reads $E1; { | } by
;; first clearing bit 5, so they read with [ \ ]; and ~ and DEL by flipping bits 6 and 7, to $BE and $BF. Each of
;; those entries holds the offset of a key's entry, and the driver reads the character at that offset, plus 1 for
;; Shift and 2 for Control. When the key's first character has <ALPHA_LOCK> set and Alpha Lock is down, it reads
;; the shifted character instead; and it clears bit 7 of what it read.
;;
;; The keys are listed row by row, as on the keyboard. Return and the keys that send bit 7 set (Escape, Tab, space,
;; the arrows and the keypad) never reach the table.
KeyboardLayout:
KeyOne:
    Key '1', '!', '1', '!'
KeyTwo:
    Key '2', '@', '2', $00
KeyThree:
    Key '3', '#', '3', '#'
KeyFour:
    Key '4', '$', '4', '$'
KeyFive:
    Key '5', '%', '5', '%'
KeySix:
    Key '6', '^', '6', $1E
KeySeven:
    Key '7', '&', '7', '&'
KeyEight:
    Key '8', '*', '8', '*'
KeyNine:
    Key '9', '(', '9', '('
KeyZero:
    Key '0', ')', '0', ')'
KeyMinus:
    Key '-', '_', '-', $1F
KeyEquals:
    Key '=', '+', '=', '+'
KeyBackslash:
    Key $5C, '|', $1C, $7F
KeyQ:
    LetterKey 'Q'
KeyW:
    LetterKey 'W'
KeyE:
    LetterKey 'E'
KeyR:
    LetterKey 'R'
KeyT:
    LetterKey 'T'
KeyY:
    LetterKey 'Y'
KeyU:
    LetterKey 'U'
KeyI:
    LetterKey 'I'
KeyO:
    LetterKey 'O'
KeyP:
    LetterKey 'P'
KeyLeftBracket:
    Key '[', '{', $1B, $1B
KeyRightBracket:
    Key ']', '}', $1D, $1D
KeyGrave:
    Key '`', '~', '`', '~'
KeyA:
    LetterKey 'A'
KeyS:
    LetterKey 'S'
KeyD:
    LetterKey 'D'
KeyF:
    LetterKey 'F'
KeyG:
    LetterKey 'G'
KeyH:
    LetterKey 'H'
KeyJ:
    LetterKey 'J'
KeyK:
    LetterKey 'K'
KeyL:
    LetterKey 'L'
KeySemicolon:
    Key ';', ':', ';', ':'
KeyQuote:
    Key $27, $22, $27, $22
KeyZ:
    LetterKey 'Z'
KeyX:
    LetterKey 'X'
KeyC:
    LetterKey 'C'
KeyV:
    LetterKey 'V'
KeyB:
    LetterKey 'B'
KeyN:
    LetterKey 'N'
KeyM:
    LetterKey 'M'
KeyComma:
    Key ',', '<', ',', '<'
KeyPeriod:
    Key '.', '>', '.', '>'
KeySlash:
    Key '/', '?', '/', '?'


    .assert * - KeyboardLayout = KEYS * KEY_SIZE, "The layout lists 47 keys."

    ; Two bytes no character reads.
    .res 2

;; The key for each character the keyboard sends, as the driver folds it: ~ and DEL at $BE and $BF, then
;; @ A-Z [ \ ] ^ _ at $C0-$DF (with the control codes $00-$1F and { | }), then the other characters, from ` and !
;; to ? at $E0-$FF.
KeySlots:
    Slot KeyGrave       ; $BE: ~
    Slot KeyBackslash   ; $BF: DEL
    Slot KeyTwo         ; $C0: @
    Slot KeyA           ; $C1: A
    Slot KeyB           ; $C2: B
    Slot KeyC           ; $C3: C
    Slot KeyD           ; $C4: D
    Slot KeyE           ; $C5: E
    Slot KeyF           ; $C6: F
    Slot KeyG           ; $C7: G
    Slot KeyH           ; $C8: H
    Slot KeyI           ; $C9: I
    Slot KeyJ           ; $CA: J
    Slot KeyK           ; $CB: K
    Slot KeyL           ; $CC: L
    Slot KeyM           ; $CD: M
    Slot KeyN           ; $CE: N
    Slot KeyO           ; $CF: O
    Slot KeyP           ; $D0: P
    Slot KeyQ           ; $D1: Q
    Slot KeyR           ; $D2: R
    Slot KeyS           ; $D3: S
    Slot KeyT           ; $D4: T
    Slot KeyU           ; $D5: U
    Slot KeyV           ; $D6: V
    Slot KeyW           ; $D7: W
    Slot KeyX           ; $D8: X
    Slot KeyY           ; $D9: Y
    Slot KeyZ           ; $DA: Z
    Slot KeyLeftBracket ; $DB: [
    Slot KeyBackslash   ; $DC: \
    Slot KeyRightBracket; $DD: ]
    Slot KeySix         ; $DE: ^
    Slot KeyMinus       ; $DF: _
    Slot KeyGrave       ; $E0:  
    Slot KeyOne         ; $E1: !
    Slot KeyQuote       ; $E2: "
    Slot KeyThree       ; $E3: #
    Slot KeyFour        ; $E4: $
    Slot KeyFive        ; $E5: %
    Slot KeySeven       ; $E6: &
    Slot KeyQuote       ; $E7: '
    Slot KeyNine        ; $E8: (
    Slot KeyZero        ; $E9: )
    Slot KeyEight       ; $EA: *
    Slot KeyEquals      ; $EB: +
    Slot KeyComma       ; $EC: ,
    Slot KeyMinus       ; $ED: -
    Slot KeyPeriod      ; $EE: .
    Slot KeySlash       ; $EF: /
    Slot KeyZero        ; $F0: 0
    Slot KeyOne         ; $F1: 1
    Slot KeyTwo         ; $F2: 2
    Slot KeyThree       ; $F3: 3
    Slot KeyFour        ; $F4: 4
    Slot KeyFive        ; $F5: 5
    Slot KeySix         ; $F6: 6
    Slot KeySeven       ; $F7: 7
    Slot KeyEight       ; $F8: 8
    Slot KeyNine        ; $F9: 9
    Slot KeySemicolon   ; $FA: :
    Slot KeySemicolon   ; $FB: ;
    Slot KeyComma       ; $FC: <
    Slot KeyEquals      ; $FD: =
    Slot KeyPeriod      ; $FE: >
    Slot KeySlash       ; $FF: ?

    .assert * - KeyboardLayout = LAYOUT_SIZE, "The keyboard layout is 256 bytes."
