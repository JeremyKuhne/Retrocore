; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: FOR
;
; The platform's next-statement entry follows <Statements::For::PushToken>. NEXT and the FOR-frame
; search are in separate shared modules.

.scope Statements continued

;; Assigns the initial value and builds a loop frame, replacing an earlier FOR for the same variable.
;;
;; The frame is a <ForFrame>, built on the stack from its last field down, so that from low addresses to high it holds
;; the `FOR` token, the variable's address, the step in packed order (its top mantissa bit the normalized 1, not the
;; sign), the step's sign, the packed limit, the line number and the text pointer after the statement. A frame for the
;; same variable, and every frame above it, is discarded first.
;; Entry:
;;   ReadStep = the continuation the limit's push jumps to: loads 1, or evaluates the expression after `STEP`
;; See: <FindForFrame>, <EvaluateExpression::PushFac>, <Statements::Next>
;; Also: FOR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
.proc For
    lda #$80
    sta SubscriptMode
    jsr Statements::Let
    jsr FindForFrame
    bne BuildFrame
    txa
    adc #(FOR_FRAME_SIZE-3)
    tax
    txs

;; Drops the statement loop's return address (where an earlier frame for the variable was found, the stack pointer
;; already left it behind, and this drops the old frame's last two bytes), makes sure the stack has room for nine more
;; two-byte entries (<CheckStack>), and pushes the text pointer after the statement and <CurrentLine>. Then it requires
;; `TO`, evaluates the limit, puts its sign into the mantissa's top bit, and has <EvaluateExpression::PushFac> push it
;; and continue at <ReadStep>.
;; Also: NOTOL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
BuildFrame:
    pla
    pla
    lda #(8+ADDITIONAL_PRECISION)
    jsr CheckStack
    jsr FindStatementEnd
    clc
    tya
    adc TextPointer
    pha
    lda TextPointer+1
    adc #$00
    pha
    lda CurrentLine+1
    pha
    lda CurrentLine
    pha
    lda #TOKEN_TO
    jsr CheckCharacter
    jsr RequireNumber
    jsr EvaluateNumber
    lda FacSign
    ora #$7F
    and FacMantissa1
    sta FacMantissa1
    lda #<ReadStep
    ldy #>ReadStep
    sta Pointer1
    sty Pointer1+1
    jmp EvaluateExpression::PushFac

;; Loads the default step of one, or evaluates the expression after STEP, and completes the FOR frame.
;; Also: LDFONE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ReadStep:
    lda #<Float::One
    ldy #>Float::One
    jsr Float::LoadFac
    jsr GetCurrentCharacter
    cmp #TOKEN_STEP
    bne PushStep
    jsr GetNextCharacter
    jsr EvaluateNumber

;; Pushes the step through <EvaluateExpression::PushSignedFac>, its sign first (from <Float::GetSign>), then
;; <AssignedVariable>.
;; Also: ONEON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
PushStep:
    jsr Float::GetSign
    jsr EvaluateExpression::PushSignedFac
    lda AssignedVariable+1
    pha
    lda AssignedVariable
    pha

;; Pushes the `FOR` token, which completes the frame, and falls into the vendor's statement loop.
;; Also: NXTCON (M6502)
PushToken:
    lda #TOKEN_FOR
    pha
.endproc
.endscope

