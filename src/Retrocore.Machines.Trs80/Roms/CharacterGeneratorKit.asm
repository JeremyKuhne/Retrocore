;; TRS-80 MODEL I LOWERCASE KIT CHARACTER GENERATOR
;;
;; Radio Shack's lowercase kit (26-1104) added video RAM's seventh bit and replaced the MCM6670P with a
;; character generator whose lowercase letters sit on the line with true descenders. Its 128 characters
;; take eight bytes each, one per scanline from the top of the cell, and bits 4-0 of a row are its dots
;; from left to right, as in CharacterGenerator.asm. Unlike the MCM6670P it uses all eight rows: letters
;; without descenders start on the top row, and g, j, p, q and y reach the eighth.
;;
;; Codes $00-$1F repeat the uppercase letters at $40-$5F, so the codes Level II leaves in video RAM for
;; them show as letters. The backquote ($60) is a pound sign and the tilde ($7E) a yen sign.
;;
;; No dump of the kit's chip is known. This source follows xtrs's reconstruction of it (trs_chars.c, CG 2),
;; which Tim Mann made from the MCM6674 data sheet and memory and Ulrich Müller checked and corrected against
;; a real Model I. Trs80RomSourceTests compares the two when that file is in the cache. xtrs's stock set
;; matches the MCM6670P dump in every glyph but one. Maintained by hand.

; The glyphs follow xtrs (https://github.com/TimothyPMann/xtrs), whose license asks that its notice be kept:
;
; Copyright (C) 1992 Clarendon Hill Software.
;
; Permission is granted to any individual or institution to use, copy,
; or redistribute this software, provided this copyright notice is retained.
;
; This software is provided "as is" without any expressed or implied
; warranty.  If this software brings on any sort of damage -- physical,
; monetary, emotional, or brain -- too bad.  You've got no one to blame
; but yourself.
;
; The software may be modified for your own purposes, but modified versions
; must retain this notice.
;
; ***
;
; Copyright (c) 1996-2020, Timothy P. Mann
;
; Permission is hereby granted, free of charge, to any person
; obtaining a copy of this software and associated documentation
; files (the "Software"), to deal in the Software without
; restriction, including without limitation the rights to use, copy,
; modify, merge, publish, distribute, sublicense, and/or sell copies
; of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be
; included in all copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.

.cpu Z80

;; Starts a character: checks that it lands at code * 8.
.macro GLYPH code
    .assert * = (code) * 8, "A GLYPH is out of order."
.endmacro

;; One row of dots: five characters, # for a lit dot and . for a dark one.
.macro ROW dots
    .assert .strlen(dots) = 5, "A ROW has five dots."
    .byte ((.strat(dots, 0) = '#') << 4) | ((.strat(dots, 1) = '#') << 3) | ((.strat(dots, 2) = '#') << 2) | ((.strat(dots, 3) = '#') << 1) | (.strat(dots, 4) = '#')
.endmacro

.org $0000

    GLYPH $00                      ; a copy of @
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW ".##.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".###."
    ROW "....."

    GLYPH $01                      ; a copy of A
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $02                      ; a copy of B
    ROW "####."
    ROW ".#..#"
    ROW ".#..#"
    ROW ".###."
    ROW ".#..#"
    ROW ".#..#"
    ROW "####."
    ROW "....."

    GLYPH $03                      ; a copy of C
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $04                      ; a copy of D
    ROW "####."
    ROW ".#..#"
    ROW ".#..#"
    ROW ".#..#"
    ROW ".#..#"
    ROW ".#..#"
    ROW "####."
    ROW "....."

    GLYPH $05                      ; a copy of E
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "###.."
    ROW "#...."
    ROW "#...."
    ROW "#####"
    ROW "....."

    GLYPH $06                      ; a copy of F
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "###.."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "....."

    GLYPH $07                      ; a copy of G
    ROW ".####"
    ROW "#...."
    ROW "#...."
    ROW "#..##"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....."

    GLYPH $08                      ; a copy of H
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#####"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $09                      ; a copy of I
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "....."

    GLYPH $0A                      ; a copy of J
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $0B                      ; a copy of K
    ROW "#...#"
    ROW "#..#."
    ROW "#.#.."
    ROW "##..."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"
    ROW "....."

    GLYPH $0C                      ; a copy of L
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "#####"
    ROW "....."

    GLYPH $0D                      ; a copy of M
    ROW "#...#"
    ROW "##.##"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $0E                      ; a copy of N
    ROW "#...#"
    ROW "##..#"
    ROW "#.#.#"
    ROW "#..##"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $0F                      ; a copy of O
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $10                      ; a copy of P
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "....."

    GLYPH $11                      ; a copy of Q
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "#..#."
    ROW ".##.#"
    ROW "....."

    GLYPH $12                      ; a copy of R
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"
    ROW "....."

    GLYPH $13                      ; a copy of S
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW ".###."
    ROW "....#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $14                      ; a copy of T
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $15                      ; a copy of U
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $16                      ; a copy of V
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW ".#.#."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $17                      ; a copy of W
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "##.##"
    ROW "#...#"
    ROW "....."

    GLYPH $18                      ; a copy of X
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $19                      ; a copy of Y
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $1A                      ; a copy of Z
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "#...."
    ROW "#####"
    ROW "....."

    GLYPH $1B                      ; a copy of [
    ROW "..#.."
    ROW ".###."
    ROW "#.#.#"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $1C                      ; a copy of \
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."
    ROW "....."

    GLYPH $1D                      ; a copy of ]
    ROW "....."
    ROW "..#.."
    ROW ".#..."
    ROW "#####"
    ROW ".#..."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $1E                      ; a copy of ^
    ROW "....."
    ROW "..#.."
    ROW "...#."
    ROW "#####"
    ROW "...#."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $1F                      ; a copy of _
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#####"

    GLYPH $20                      ; space
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

    GLYPH $22                      ; "
    ROW ".#.#."
    ROW ".#.#."
    ROW ".#.#."
    ROW "....."
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
    ROW "....."

    GLYPH $24                      ; $
    ROW "..#.."
    ROW ".####"
    ROW "#.#.."
    ROW ".###."
    ROW "..#.#"
    ROW "####."
    ROW "..#.."
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

    GLYPH $26                      ; &
    ROW ".#..."
    ROW "#.#.."
    ROW "#.#.."
    ROW ".#..."
    ROW "#.#.#"
    ROW "#..#."
    ROW ".##.#"
    ROW "....."

    GLYPH $27                      ; '
    ROW ".##.."
    ROW ".##.."
    ROW ".#..."
    ROW "#...."
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

    GLYPH $29                      ; )
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "...#."
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "....."

    GLYPH $2A                      ; *
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "#####"
    ROW ".###."
    ROW "#.#.#"
    ROW "..#.."
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

    GLYPH $2C                      ; ,
    ROW "....."
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
    ROW "....."

    GLYPH $2E                      ; .
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW ".##.."
    ROW ".##.."
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

    GLYPH $30                      ; 0
    ROW ".###."
    ROW "#...#"
    ROW "#..##"
    ROW "#.#.#"
    ROW "##..#"
    ROW "#...#"
    ROW ".###."
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

    GLYPH $32                      ; 2
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW ".###."
    ROW "#...."
    ROW "#...."
    ROW "#####"
    ROW "....."

    GLYPH $33                      ; 3
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW "..##."
    ROW "....#"
    ROW "#...#"
    ROW ".###."
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

    GLYPH $35                      ; 5
    ROW "#####"
    ROW "#...."
    ROW "####."
    ROW "....#"
    ROW "....#"
    ROW "#...#"
    ROW ".###."
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

    GLYPH $37                      ; 7
    ROW "#####"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW ".#..."
    ROW ".#..."
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

    GLYPH $39                      ; 9
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW "...#."
    ROW ".##.."
    ROW "....."

    GLYPH $3A                      ; :
    ROW "....."
    ROW ".##.."
    ROW ".##.."
    ROW "....."
    ROW ".##.."
    ROW ".##.."
    ROW "....."
    ROW "....."

    GLYPH $3B                      ; ;
    ROW "....."
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

    GLYPH $3E                      ; >
    ROW ".#..."
    ROW "..#.."
    ROW "...#."
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW ".#..."
    ROW "....."

    GLYPH $3F                      ; ?
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW "...#."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "....."

    GLYPH $40                      ; @
    ROW ".###."
    ROW "#...#"
    ROW "....#"
    ROW ".##.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW ".###."
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

    GLYPH $42                      ; B
    ROW "####."
    ROW ".#..#"
    ROW ".#..#"
    ROW ".###."
    ROW ".#..#"
    ROW ".#..#"
    ROW "####."
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

    GLYPH $44                      ; D
    ROW "####."
    ROW ".#..#"
    ROW ".#..#"
    ROW ".#..#"
    ROW ".#..#"
    ROW ".#..#"
    ROW "####."
    ROW "....."

    GLYPH $45                      ; E
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "###.."
    ROW "#...."
    ROW "#...."
    ROW "#####"
    ROW "....."

    GLYPH $46                      ; F
    ROW "#####"
    ROW "#...."
    ROW "#...."
    ROW "###.."
    ROW "#...."
    ROW "#...."
    ROW "#...."
    ROW "....."

    GLYPH $47                      ; G
    ROW ".####"
    ROW "#...."
    ROW "#...."
    ROW "#..##"
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
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

    GLYPH $49                      ; I
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
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

    GLYPH $4B                      ; K
    ROW "#...#"
    ROW "#..#."
    ROW "#.#.."
    ROW "##..."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"
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

    GLYPH $4D                      ; M
    ROW "#...#"
    ROW "##.##"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "....."

    GLYPH $4E                      ; N
    ROW "#...#"
    ROW "##..#"
    ROW "#.#.#"
    ROW "#..##"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
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

    GLYPH $50                      ; P
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#...."
    ROW "#...."
    ROW "#...."
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

    GLYPH $52                      ; R
    ROW "####."
    ROW "#...#"
    ROW "#...#"
    ROW "####."
    ROW "#.#.."
    ROW "#..#."
    ROW "#...#"
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

    GLYPH $54                      ; T
    ROW "#####"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
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

    GLYPH $56                      ; V
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW ".#.#."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $57                      ; W
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#.#.#"
    ROW "##.##"
    ROW "#...#"
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

    GLYPH $59                      ; Y
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
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

    GLYPH $5B                      ; up arrow
    ROW "..#.."
    ROW ".###."
    ROW "#.#.#"
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $5C                      ; down arrow
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "#.#.#"
    ROW ".###."
    ROW "..#.."
    ROW "....."

    GLYPH $5D                      ; left arrow
    ROW "....."
    ROW "..#.."
    ROW ".#..."
    ROW "#####"
    ROW ".#..."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $5E                      ; right arrow
    ROW "....."
    ROW "..#.."
    ROW "...#."
    ROW "#####"
    ROW "...#."
    ROW "..#.."
    ROW "....."
    ROW "....."

    GLYPH $5F                      ; underline
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "....."
    ROW "#####"

    GLYPH $60                      ; pound sign
    ROW "..#.."
    ROW ".#.#."
    ROW ".#..."
    ROW "###.."
    ROW ".#..."
    ROW ".#..#"
    ROW "####."
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

    GLYPH $62                      ; b
    ROW "#...."
    ROW "#...."
    ROW "#.##."
    ROW "##..#"
    ROW "#...#"
    ROW "##..#"
    ROW "#.##."
    ROW "....."

    GLYPH $63                      ; c
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#...."
    ROW "#...#"
    ROW ".###."
    ROW "....."

    GLYPH $64                      ; d
    ROW "....#"
    ROW "....#"
    ROW ".##.#"
    ROW "#..##"
    ROW "#...#"
    ROW "#..##"
    ROW ".##.#"
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

    GLYPH $66                      ; f
    ROW "...#."
    ROW "..#.#"
    ROW "..#.."
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $67                      ; g
    ROW "....."
    ROW "....."
    ROW ".###."
    ROW "#...#"
    ROW "#...#"
    ROW ".####"
    ROW "....#"
    ROW ".###."

    GLYPH $68                      ; h
    ROW "#...."
    ROW "#...."
    ROW "#.##."
    ROW "##..#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
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

    GLYPH $6A                      ; j
    ROW "....#"
    ROW "....."
    ROW "...##"
    ROW "....#"
    ROW "....#"
    ROW "....#"
    ROW ".#..#"
    ROW "..##."

    GLYPH $6B                      ; k
    ROW ".#..."
    ROW ".#..."
    ROW ".#..#"
    ROW ".#.#."
    ROW ".##.."
    ROW ".#.#."
    ROW ".#..#"
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

    GLYPH $6D                      ; m
    ROW "....."
    ROW "....."
    ROW "##.#."
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "#.#.#"
    ROW "....."

    GLYPH $6E                      ; n
    ROW "....."
    ROW "....."
    ROW "#.##."
    ROW "##..#"
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
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

    GLYPH $70                      ; p
    ROW "....."
    ROW "....."
    ROW "#.##."
    ROW "##..#"
    ROW "##..#"
    ROW "#.##."
    ROW "#...."
    ROW "#...."

    GLYPH $71                      ; q
    ROW "....."
    ROW "....."
    ROW ".##.#"
    ROW "#..##"
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

    GLYPH $74                      ; t
    ROW "..#.."
    ROW "..#.."
    ROW ".###."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.#"
    ROW "...#."
    ROW "....."

    GLYPH $75                      ; u
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW "#..##"
    ROW ".##.#"
    ROW "....."

    GLYPH $76                      ; v
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW "#...#"
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
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

    GLYPH $78                      ; x
    ROW "....."
    ROW "....."
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW ".#.#."
    ROW "#...#"
    ROW "....."

    GLYPH $79                      ; y
    ROW "....."
    ROW "....."
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

    GLYPH $7B                      ; {
    ROW "...#."
    ROW "..#.."
    ROW "..#.."
    ROW ".#..."
    ROW "..#.."
    ROW "..#.."
    ROW "...#."
    ROW "....."

    GLYPH $7C                      ; |
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."
    ROW "..#.."
    ROW "..#.."
    ROW "..#.."
    ROW "....."

    GLYPH $7D                      ; }
    ROW ".#..."
    ROW "..#.."
    ROW "..#.."
    ROW "...#."
    ROW "..#.."
    ROW "..#.."
    ROW ".#..."
    ROW "....."

    GLYPH $7E                      ; yen sign
    ROW "#...#"
    ROW ".#.#."
    ROW "..#.."
    ROW "#####"
    ROW "..#.."
    ROW "#####"
    ROW "..#.."
    ROW "....."

    GLYPH $7F                      ; checkerboard
    ROW "#.#.#"
    ROW ".#.#."
    ROW "#.#.#"
    ROW ".#.#."
    ROW "#.#.#"
    ROW ".#.#."
    ROW "#.#.#"
    ROW ".#.#."
