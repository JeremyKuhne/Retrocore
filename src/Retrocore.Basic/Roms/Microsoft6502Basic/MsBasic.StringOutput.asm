; MICROSOFT 6502 BASIC: STRING OUTPUT

;; Prints text up to a quotation mark or zero.
;; In: A = low string address, Y = high string address
;; See: <STRLIT>, <STRPRT>
STROUT:
    jsr STRLIT

;; Prints the string whose descriptor is addressed by <FACMO>, releasing the temporary if applicable.
;; In: FACMO/FACLO = string descriptor address
;; See: <FREFAC>, <OUTDO>
STRPRT:
    jsr FREFAC
    tax
    ldy #$00
    inx
STRPR2:
    dex
    beq PRTRTS
    lda (INDEX),y
    jsr OUTDO
    iny
    cmp #$0D
    bne STRPR2
    jsr CRFIN
    jmp STRPR2
