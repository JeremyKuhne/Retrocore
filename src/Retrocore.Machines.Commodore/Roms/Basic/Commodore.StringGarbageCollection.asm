; COMMODORE BASIC 4: LINKED STRING GARBAGE COLLECTION
;
; Include this after Commodore.Equates.asm in a composed build, then emit LINKED_STRING_GARBAGE_COLLECTION
; after the linked allocator. It cannot be used with the unlinked allocator or strings without link bytes.

; Supply the BASIC 4 workspace when this definitions-only file is opened on its own.
.ifndef INDEX
.ifndef LINE_WIDTH_STORAGE
LINE_WIDTH_STORAGE = 0              ;; BASIC 4 reuses the line-width storage
.endif
.ifndef DISK_STATUS_STRING
DISK_STATUS_STRING = 1              ;; BASIC 4 has the disk-status string descriptor
.endif
.include "Commodore.Equates.asm"
.endif

;; Emits BASIC 4's single-pass linked-string collector.
;;
;; Every nonempty allocated string ends in a two-byte link. A live link points back to its descriptor;
;; garbage has its length in the first link byte and $FF in the second. Starting at <MEMSIZ>, the
;; collector skips garbage, moves later live strings over it, and repairs their descriptor pointers.
;; It does not scan variable or temporary tables, so a valid link is essential even for a temporary.
;; The allocator initially marks a new string as garbage; collection before assignment links it to
;; a variable can reclaim it while a temporary descriptor still points at its former contents.
.macro LINKED_STRING_GARBAGE_COLLECTION

.scope Strings continued
;; Compacts linked strings and updates their descriptors: BASIC 4's <Strings::CollectGarbage>, by the classic
;; collector's name (Basic.md E6).
;; In: MEMSIZ = exclusive top of string space, FRETOP = first allocated byte, decimal = clear
;; Out: FRETOP = new first allocated byte, FRESPC = new first allocated byte
;; See: <ENDGRB>, <SETINX>
;; Also: GARBA2 (M6502, CBM4S79, HV4, HV4R)
CollectGarbage:
.endscope
    ldy #$00
    sty HIGHDS
    lda MEMSIZ
    ldy MEMSIZ+1
    sta GRBTOP
    sta GRBPNT
    sta FRESPC
    sty GRBTOP+1
    sty GRBPNT+1
    sty FRESPC+1

GLOOP:
    cpy FRETOP+1
    bcc GRBEND
    bne COL00
    cmp FRETOP
    beq GRBEND
    bcc GRBEND

COL00:
    ldx HIGHDS
    bmi COL00B
    lda #$02
    jsr MOVTOP

COL00B:
    jsr SKIP2A
    ldy #$01
    lda (GRBPNT),y
    cmp #$FF
    bne COL01

COL00A:
    dey
    lda (GRBPNT),y
    jsr MOVPNT
    sec
    ror HIGHDS
    bne GLOOP

COL01:
    jsr SETINX
    ldx HIGHDS
    bpl COL03
    lsr HIGHDS

COL02:
    ldy #$00
    lda (GRBPNT),y
    sta (GRBTOP),y
    iny
    lda (GRBPNT),y
    sta (GRBTOP),y
    dey
    lda (INDEX),y
    tax
    jsr MOVTOP
    sta FRESPC
    sty FRESPC+1
    txa
    jsr MOVPNT
    txa
    tay

GLOP1:
    dey
    lda (GRBPNT),y
    sta (GRBTOP),y
    dex
    bne GLOP1
    ldy #$02

COL02B:
    lda GRBTOP-1,y
    sta (INDEX),y
    dey
    bne COL02B
    lda GRBPNT
    ldy GRBPNT+1
    cpy FRETOP+1
    bcc GRBEND
    bne COL02A
    cmp FRETOP
    beq GRBEND
    bcc GRBEND

COL02A:
    jsr SKIP2
    ldy #$01
    lda (GRBPNT),y
    cmp #$FF
    beq COL00A
    jsr SETINX
    bmi COL02

GRBEND:
    jmp ENDGRB

COL03:
    ldy #$00
    lda (INDEX),y
    tax
    jsr MOVTOP
    sta FRESPC
    sty FRESPC+1
    txa
    jsr MOVPNT
    jmp GLOOP

;; Sets the final free-space boundary after the linked-string scan.
ENDGRB:
    lda FRESPC
    ldy FRESPC+1
    sta FRETOP
    sty FRETOP+1
    rts

;; Skips link bytes in the destination and source pointers.
SKIP2:
    lda #$02
    jsr MOVTOP

SKIP2A:
    lda #$02

;; Subtracts A from the source pointer <GRBPNT>.
MOVPNT:
    eor #$FF
    sec
    adc GRBPNT
    ldy GRBPNT+1
    bcs MOV00
    dey

MOV00:
    sta GRBPNT
    sty GRBPNT+1
    rts

;; Subtracts A from the destination pointer <GRBTOP>.
MOVTOP:
    eor #$FF
    sec
    adc GRBTOP
    ldy GRBTOP+1
    bcs MOV01
    dey

MOV01:
    sta GRBTOP
    sty GRBTOP+1
    rts

;; Loads <INDEX> from the link at <GRBPNT>.
;; Out: INDEX = descriptor address, negative = set
SETINX:
    ldy #$01

SET00:
    lda (GRBPNT),y
    sta INDEX,y
    dey
    bpl SET00
    rts
.endmacro
