; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; COMMODORE BASIC 4: LINKED STRING-SPACE ALLOCATION
;
; StringAllocation invokes this BASIC 4 allocator before the BASIC 4 linked collector.
; It is not interchangeable with the ordinary Microsoft collector.

;; Emits BASIC 4's linked allocator, <Strings::ReserveSpace>.
.macro LinkedStringAllocation
    .scope Strings continued

    ;; Reserves string space below <StringsBottom>, with a two-byte link below it, collecting garbage once if a
    ;; nonempty request does not fit.
    ;;
    ;; A nonempty string gets a link containing its length followed by $FF, marking it as garbage until assignment.
    ;; Equality with <ArraysEnd> fits. A zero-length request returns at once with X = 0 and Y unchanged, without
    ;; changing <StringsBottom> or <NewString> or creating a link.
    ;; In: A = number of character bytes
    ;; Out: A = byte count after a successful check, X = low address for a nonempty string,
    ;;   Y = high address for a nonempty string, NewString = address for a nonempty string
    ;; Errors: OUT OF MEMORY if a nonempty request still does not fit after collection
    ;; Also: GETSPA (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc ReserveSpace
    lsr CollectionState

;; Returns at once for length 0, else computes the link address below <StringsBottom>.
;; Also: TRYAG2 (M6502, CBM4S79, HV4, HV4R)
Try:
    tax
    beq Done
    pha
    lda StringsBottom
    sec
    sbc #$02
    ldy StringsBottom+1
    bcs BelowLink
    dey

;; Saves the link address in <Pointer1> and subtracts the length. BASIC 4's documents give it Microsoft's old name of
;; the room check, so Commodore's historical names give it (Basic.md E4).
BelowLink:
    sta Pointer1
    sty Pointer1+1
    txa
    eor #$FF
    sec
    adc Pointer1
    bcs CheckLinkedRoom
    dey

;; Compares the new bottom with <ArraysEnd>.
CheckLinkedRoom:
    cpy ArraysEnd+1
    bcc Collect
    bne Take
    cmp ArraysEnd
    bcc Collect

;; Writes the garbage link (length, $FF) and sets <NewString> and <StringsBottom>.
;; Also: STRFRE (M6502, CBM4S79, HV4, HV4R)
Take:
    sta NewString
    sty NewString+1
    ldy #$01
    lda #$FF
    sta (Pointer1),y
    dey
    pla
    sta (Pointer1),y
    ldx NewString
    ldy NewString+1
    stx StringsBottom
    sty StringsBottom+1

;; Returns. BASIC 4's documents give it Microsoft's old name of the output routine's return, so Commodore's
;; historical names give it (Basic.md E3).
Done:
    rts

;; Collects once (OUT OF MEMORY if already collected) and retries.
;; Also: GARBAG (M6502, CBM4S79, HV4, HV4R)
Collect:
    ldx #<ERROR_OUT_OF_MEMORY
    lda CollectionState
    bmi PushTemporary::ToError
    jsr CollectGarbage
    sec
    ror CollectionState
    pla
    bne Try
    .endproc
    .endscope

.endmacro
