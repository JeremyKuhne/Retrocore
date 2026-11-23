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
;; From low to high addresses the <FOR_FRAME_SIZE>-byte frame holds <TOKEN_FOR>, the variable address, the five-byte step, its
;; sign, the five-byte packed limit, the line number and the text pointer after the FOR statement.
;; Entry:
;;   ReadStep = Its address is the continuation the limit's push (FORPSH) jumps to: loads 1.0, or evaluates the STEP
;;     expression
;; See: <FindForFrame>, <FORPSH>, <Statements::Next>
;; Also: FOR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
.proc For
    lda #$80
    sta SubscriptMode
    jsr LET
    jsr FindForFrame
    bne BuildFrame
    txa
    adc #(FOR_FRAME_SIZE-3)
    tax
    txs

;; Drops the statement loop's return, <CheckStack>(9), pushes the text after the statement and <CurrentLine>,
;; evaluates TO's limit.
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
    jsr SYNCHR
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
    jmp FORPSH

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

;; Pushes the step (PUSHF), its sign (SIGN) and <AssignedVariable>.
;; Also: ONEON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
PushStep:
    jsr Float::GetSign
    jsr PUSHF
    lda AssignedVariable+1
    pha
    lda AssignedVariable
    pha

;; Pushes TOKEN_FOR to complete the frame; falls into the vendor's statement loop.
;; Also: NXTCON (M6502)
PushToken:
    lda #TOKEN_FOR
    pha
.endproc
.endscope

