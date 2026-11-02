;; DOS 3.2 RWTS: THE NIBBLE BUFFERS AND THE VALUE-TO-NIBBLE TABLE
;;
;; NBUF1 and NBUF2 hold a sector as the 410 five-bit values of its data field, between PRENIB13 and WRITE13 or
;; between READ13 and POSTNB13; NIBL turns a value into the nibble written for it. Runs at $BB00-$BCFF where
;; DOS runs. The buffers' contents on the master are whatever they held when it was written.

;; The top five bits of each of a sector's 256 bytes, in five runs of 51 and the last byte's (PRENIB13). After
;; a read, the values are shifted left three places.
NBUF1:
    ; leftover
    .byte $1B, $18, $06, $14, $05, $05, $04, $0D, $04, $03, $02, $01, $0A, $01, $00, $03
    .byte $00, $03, $03, $03, $03, $06, $00, $00, $1A, $05, $1F, $1C, $13, $15, $05, $04
    .byte $10, $01, $15, $12, $00, $0F, $12, $09, $05, $00, $00, $02, $00, $00, $00, $00
    .byte $00, $00, $03, $1C, $19, $06, $06, $06, $05, $10, $04, $04, $03, $02, $01, $0B
    .byte $07, $04, $00, $00, $03, $03, $0E, $03, $05, $1A, $1C, $1F, $0C, $04, $04, $07
    .byte $17, $00, $0F, $18, $00, $00, $01, $00, $00, $00, $00, $03, $00, $00, $00, $00
    .byte $03, $00, $00, $00, $00, $03, $07, $1A, $06, $15, $06, $05, $11, $04, $04, $03
    .byte $02, $02, $01, $08, $05, $00, $00, $03, $03, $05, $03, $04, $1E, $08, $1C, $14
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $00, $00, $02, $03, $00
    .byte $00, $01, $02, $03, $00, $00, $01, $01, $00, $1D, $07, $07, $16, $06, $05, $12
    .byte $0E, $04, $03, $02, $02, $01, $01, $06, $00, $01, $00, $00, $00, $03, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $02, $03, $00, $00, $00, $03, $00, $03, $00, $01
    .byte $00, $00, $00, $00, $02, $00, $02, $00, $00, $00, $00, $02, $1E, $07, $07, $17
    .byte $13, $05, $05, $0F, $0C, $00, $03, $00, $00, $00, $00, $00, $00, $00, $00, $02
    .byte $00, $00, $00, $00, $00, $00, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $03, $00, $00, $00, $00, $00, $00, $01, $02, $02, $03, $00, $00, $00, $00, $1F

;; The low three bits of a sector's bytes, five bits to a value: three runs of 51 and the last byte's 3 bits
;; (PRENIB13). After a read, the values are shifted left three places.
NBUF2:
    ; leftover
    .byte $0C, $00, $0C, $00, $0C, $00, $00, $00, $14, $1D, $01, $00, $00, $00, $00, $00
    .byte $00, $04, $18, $1E, $07, $04, $00, $00, $00, $00, $0F, $00, $10, $15, $01, $00
    .byte $00, $00, $1C, $1F, $19, $10, $0D, $1B, $0F, $00, $14, $1E, $05, $01, $1C, $01
    .byte $04, $03, $11, $00, $03, $00, $00, $00, $00, $02, $00, $1D, $1E, $03, $0A, $04
    .byte $01, $02, $00, $02, $04, $13, $19, $05, $08, $08, $04, $00, $10, $15, $15, $0E
    .byte $18, $0F, $0C, $0C, $04, $1C, $01, $14, $01, $0C, $00, $00, $11, $02, $05, $00
    .byte $1C, $10, $01, $00, $00, $00, $00, $04, $00, $00, $00, $00, $00, $00, $11, $1F
    .byte $00, $00, $00, $0D, $0A, $00, $02, $19, $0C, $1A, $03, $0C, $0C, $00, $00, $10
    .byte $0C, $01, $00, $00, $00, $02, $05, $12, $10, $16, $00, $09, $09, $09, $0C, $05
    .byte $11, $03, $00, $01, $00, $10, $00, $01, $10, $07

;; The 32 nibbles, in order: entry n is the nibble written for the five-bit value n. They are the bytes from
;; $AB up whose top bit is set and which have no two 0 bits next to each other, apart from $D5, which only
;; starts a field.
NIBL:
    .byte $AB, $AD, $AE, $AF, $B5, $B6, $B7, $BA
    .byte $BB, $BD, $BE, $BF, $D6, $D7, $DA, $DB
    .byte $DD, $DE, $DF, $EA, $EB, $ED, $EE, $EF
    .byte $F5, $F6, $F7, $FA, $FB, $FD, $FE, $FF

; Leftover, but for a piece of code and a table in it that nothing uses. The code would look up the sector
; number an address field gave (SECT) in the table and go on at CORRECTVOL's compare (Rwts32.asm), comparing the
; result with the IOB's sector; the table, 0, 5, 10, ... modulo 13, would make that a software interleave. Its
; addresses are those of the master image, $3CD0 and $3E0A, and the relocator doesn't adjust this page.
    .byte $1C, $1C, $1C, $00, $00, $00
    ldy SECT
    lda $3CD0,y
    ldy #5
    jmp $3E0A
    .byte $00, $00, $00, $00, $00, $00
    .assert <* = $D0
    .byte $00, $05, $0A, $02, $07, $0C, $04, $09, $01, $06, $0B, $03, $08
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00
