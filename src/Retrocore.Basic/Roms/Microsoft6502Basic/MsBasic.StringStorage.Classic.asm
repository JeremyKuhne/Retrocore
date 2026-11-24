; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: UNLINKED STRING-SPACE ALLOCATION
;
; StringAllocation invokes this unlinked allocator. BASIC 4 needs the separate linked implementation.

;; Emits the ordinary unlinked allocator, <Strings::ReserveSpace>.
.macro UnlinkedStringAllocation
    .scope Strings continued

    ;; Reserves string space below <StringsBottom>, collecting garbage once if the request does not fit.
    ;;
    ;; Equality with <ArraysEnd> fits. A zero-length request is checked too; if that check fails, the zero after
    ;; collection falls through into <Strings::CollectGarbage> a second time rather than retrying.
    ;; In: A = number of character bytes
    ;; Out: A = byte count after a successful check, X = low address, Y = high address, NewString = the address
    ;; Errors: OUT OF MEMORY if a nonempty request still does not fit after collection
    ;; Also: GETSPA (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc ReserveSpace
    lsr CollectionState

;; Computes <StringsBottom> minus the length.
;; Also: TRYAG2 (M6502, HV1, HV1R, HV2)
Try:
    pha
    eor #$FF
    sec
    adc StringsBottom
    ldy StringsBottom+1
    bcs CheckRoom
    dey

;; Compares the new bottom with <ArraysEnd> (equality fits). Its old name is another step's in BASIC 4, so each
;; vendor's historical names give it (Basic.md E4).
CheckRoom:
    cpy ArraysEnd+1
    bcc Collect
    bne Take
    cmp ArraysEnd
    bcc Collect

;; Sets <StringsBottom> and <NewString> to the new bottom; returns X/Y = address, A = length.
;; Also: STRFRE (M6502, HV1, HV1R, HV2)
Take:
    sta StringsBottom
    sty StringsBottom+1
    sta NewString
    sty NewString+1
    tax
    pla
    rts

;; Collects once (OUT OF MEMORY if already collected) and retries a nonempty request.
;; Also: GARBAG (M6502, HV1, HV1R, HV2)
Collect:
    ldx #<ERROR_OUT_OF_MEMORY
    lda CollectionState
    bmi PushTemporary::ToError
    jsr CollectGarbage
    lda #$80
    sta CollectionState
    pla
    bne Try
    .endproc
    .endscope

.endmacro
