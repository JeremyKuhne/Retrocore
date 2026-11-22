; MICROSOFT 6502 BASIC: STRING DESCRIPTORS AND LITERALS
;
; STRING_STORAGE emits STRINI through PUTNEW. Follow it with STRING_ALLOCATION and the matching
; platform GARBA2 collector. The separate allocator bodies are macro definitions only; the linked body
; emits no bytes unless selected. Allocation is independent of the literal and temporary-descriptor choices.

.include "MsBasic.StringStorage.Classic.asm"
.include "MsBasic.StringStorage.Linked.asm"

;; Emits the common string initialization, literal scanning and temporary-descriptor routines.
;; Parameters: bufferPage = input buffer page, or 0 when it is already in page zero;
;;   clearFacOverflow = 1 to clear <FACOV> when making a temporary, 0 to leave it unchanged
.macro STRING_STORAGE bufferPage, clearFacOverflow
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."
    .assert clearFacOverflow = 0 || clearFacOverflow = 1, "clearFacOverflow must be 0 or 1."
    .assert STRSIZ = 3 && NUMTMP > 0, "String temporaries must have three-byte descriptors."
    .assert TEMPST >= 0 && TEMPST + STRSIZ * NUMTMP <= $FF, "The temporary stack must fit in page zero."

;; Allocates space for a result string, saving the current descriptor pointer in <DSCPNT>.
;; In: A = string length, FACMO/FACLO = descriptor address, low byte first
;; Out: DSCPNT = original descriptor address, DSCTMP = length and character address
STRINI:
    ldx FACMO
    ldy FACLO
    stx DSCPNT
    sty DSCPNT+1

;; Allocates space and builds a temporary descriptor without saving the previous descriptor.
;;
;; With the linked allocator, a zero-length descriptor has low address byte zero and the entry's Y as its
;; unused high byte. When reached through <STRINI>, Y is the original <FACLO>.
;; In: A = string length
;; Out: DSCTMP = length and character address
STRSPA:
    jsr GETSPA
    stx DSCTMP+1
    sty DSCTMP+2
    sta DSCTMP
    rts

;; Builds a temporary string from text beginning at A:Y, stopping at a quote or zero.
;;
;; For a quoted literal the leading quote has already been consumed; a closing quote is skipped.
;; See: <STRLT2>
;; In: A = low text address, Y = high text address
;; Out: FACMO/FACLO = temporary descriptor pointer, STRNG2 = position after a quote or at zero
STRLIT:
    ldx #$22
    stx CHARAC
    stx ENDCHR

;; Scans a literal using <CHARAC> and <ENDCHR> as additional terminators.
;;
;; A quote terminator is skipped, but a zero or other terminator is not. The initial text page alone
;; selects copying: page zero and the configured nonzero input-buffer page are copied to string space;
;; other pages remain in place. A terminator must occur within the first 256 bytes.
;; In: A = low text address, Y = high text address
;; Out: FACMO/FACLO = temporary descriptor pointer, STRNG2 = position after a quote or at another terminator
;; Errors: FORMULA TOO COMPLEX if no temporary descriptor is available, or OUT OF MEMORY while copying
STRLT2:
    sta STRNG1
    sty STRNG1+1
    sta DSCTMP+1
    sty DSCTMP+2
    ldy #$FF

STRGET:
    iny
    lda (STRNG1),y
    beq STRFI1
    cmp CHARAC
    beq STRFIN
    cmp ENDCHR
    bne STRGET

STRFIN:
    cmp #$22
    beq STRFI2

STRFI1:
    clc

STRFI2:
    sty DSCTMP
    tya
    adc STRNG1
    sta STRNG2
    ldx STRNG1+1
    bcc STRST2
    inx

STRST2:
    stx STRNG2+1
    lda STRNG1+1
.if bufferPage
    beq STRCP
    cmp #bufferPage
.endif
    bne PUTNEW

STRCP:
    tya
    jsr STRINI
    ldx STRNG1
    ldy STRNG1+1
    jsr MOVSTR

;; Copies <DSCTMP> to the next temporary descriptor and marks the result as a string.
;;
;; Only the low byte of <LASTPT> is updated; its high byte must already identify page zero.
;; The overflow check tests equality with the end of the temporary stack.
;; Out: FACMO/FACLO = temporary descriptor pointer, VALTYP = string
;; Errors: FORMULA TOO COMPLEX if no temporary descriptor is available
PUTNEW:
    ldx TEMPPT
    cpx #<(TEMPST+STRSIZ*NUMTMP)
    bne PUTNW1
    ldx #<ERRST

ERRGO2:
    jmp ERROR

PUTNW1:
    lda DSCTMP
    sta $00,x
    lda DSCTMP+1
    sta $01,x
    lda DSCTMP+2
    sta $02,x
    ldy #$00
    stx FACMO
    sty FACLO
.if clearFacOverflow
    sty FACOV
.endif
    dey
    sty VALTYP
    stx LASTPT
    inx
    inx
    inx
    stx TEMPPT
    rts
.endmacro

;; Emits the selected string-space allocator immediately before the matching <GARBA2>.
;; Parameters: linkedStrings = 1 for the BASIC 4 linked allocator, 0 for ordinary unlinked allocation
.macro STRING_ALLOCATION linkedStrings
    .assert linkedStrings = 0 || linkedStrings = 1, "linkedStrings must be 0 or 1."

;; Reserves string space, collecting garbage once if a nonempty request does not fit.
;;
;; Both allocators accept equality with <STREND>. The unlinked allocator also checks space for a
;; zero-length request; if that check fails, it calls <GARBA2> twice without retrying. The linked
;; allocator reserves two extra bytes for nonempty strings, marking the link as garbage. Its zero-length
;; request returns X = 0 and Y unchanged, without changing <FRETOP> or <FRESPC> or creating a link.
;; In: A = number of character bytes
;; Out: A = byte count after a successful check, X = low address for a nonempty string,
;;   Y = high address for a nonempty string, FRESPC = address for a nonempty string
;; Errors: OUT OF MEMORY if a nonempty request still does not fit after collection
GETSPA:
    lsr GARBFL
.if linkedStrings
    LINKED_STRING_ALLOCATION
.else
    UNLINKED_STRING_ALLOCATION
.endif
.endmacro
