; retrocore: style=strict
;; COMMODORE BASIC: START-UP WITH THE STANDARD KERNAL
;;
;; With the VIC-20's kernal, BASIC's cold start points its RAM vectors at the ROM's routines, sets up its page-zero
;; workspace, asks the kernal for the bottom and top of the RAM it found, and prints the sign-on; its warm start,
;; which STOP-RESTORE and BRK reach through the second word of the ROM, resets the channels and the stack and prints
;; READY. A root emits <CommodoreKernalColdStart>, then the character reader's template (<CharacterReader>), then
;; <CommodoreKernalInitialization>, as the VIC-20's ROM has them. Including this file emits no bytes.
;;
;; Commodore's names, from its listing of the VIC-20's BASIC (BV20), are kept in each definition's `Also:`.

;; The screen's clear code, which the sign-on starts with.
CLEAR_SCREEN = $93

;; Emits <ColdStart>.
.macro CommodoreKernalColdStart

    ;; Cold-starts BASIC: sets the RAM vectors, the workspace and the character reader, prints the sign-on and the
    ;; free bytes, and enters <ReadyForCommand> with the stack reset.
    ;; See: <InitializeVectors>, <InitializeWorkspace>, <PrintSignOn>
    ;; Also: INIT (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4, BV20)
    .proc ColdStart
    jsr InitializeVectors
    jsr InitializeWorkspace
    jsr PrintSignOn
    ldx #<(STACK_END-$100)
    txs
    jmp ReadyForCommand
    .endproc
.endmacro

;; Emits the workspace's set-up, the sign-on, the RAM vectors' defaults and the warm start.
.macro CommodoreKernalInitialization

    ;; Sets up the page-zero workspace: the `USR` and function jumps, the conversion vectors, the character reader and
    ;; the random seed, the flags, and the bottom and top of BASIC's RAM from the kernal, with a zero before the first
    ;; line.
    ;; Out: ProgramStart = the first line's address, one after the kernal's bottom of memory; MemoryTop and
    ;;   StringsBottom = the kernal's top of memory
    ;; Also: INITCZ (BV20)
    .proc InitializeWorkspace
    lda #$4C                        ; the JMP opcode for the vectors
    sta FunctionJump
    sta UserVector
    lda #<IllegalQuantityError
    ldy #>IllegalQuantityError
    sta UserVector+1
    sty UserVector+2
    lda #<ReturnSignedWord
    ldy #>ReturnSignedWord
    sta IntegerToFloatVector
    sty IntegerToFloatVector+1
    lda #<FacToSignedWord
    ldy #>FacToSignedWord
    sta FloatToIntegerVector
    sty FloatToIntegerVector+1
    ldx #<(RandomValue+4-GetNextCharacter)

;; Copies the character reader and the random seed to page zero.
;; Also: MOVCHG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CopyCharacterReader:
    lda CharacterReaderTemplate,x
    sta GetNextCharacter,x
    dex
    bpl CopyCharacterReader

    ; The flags, and the bytes before the input buffer nonzero for the line chaining.
    lda #DESCRIPTOR_SIZE
    sta CollectorStep
    lda #$00
    sta ShiftFill
    sta CurrentChannel
    sta LastTemporary+1
    ldx #$01
    stx InputBuffer-3
    stx InputBuffer-4
    ldx #TemporaryDescriptors
    stx NextTemporary

    ; The RAM the kernal found.
    sec
    jsr KernalMemoryBottom
    stx ProgramStart
    sty ProgramStart+1
    sec
    jsr KernalMemoryTop

;; Sets <MemoryTop> and <StringsBottom> from X and Y; nothing branches here, and the label is kept for its old name.
;; Also: USEDEF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SetMemoryTop:
    stx MemoryTop
    sty MemoryTop+1
    stx StringsBottom
    sty StringsBottom+1
    ldy #$00
    tya
    sta (ProgramStart),y
    inc ProgramStart
    bne Return
    inc ProgramStart+1

;; Returns.
;; Also: INIT20 (BV20)
Return:
    rts
    .endproc

    ;; Prints the sign-on and the number of bytes free, and clears the program.
    ;; See: <EraseProgram>
    ;; Also: INITMS (BV20)
    .proc PrintSignOn
    lda ProgramStart
    ldy ProgramStart+1
    jsr CheckFreeMemory
    lda #<SignOnMessage
    ldy #>SignOnMessage
    jsr PrintText
    lda MemoryTop
    sec
    sbc ProgramStart
    tax
    lda MemoryTop+1
    sbc ProgramStart+1
    jsr Float::PrintDecimalAX
    lda #<BytesFreeMessage
    ldy #>BytesFreeMessage
    jsr PrintText
    jmp EraseProgram
    .endproc

;; The free-memory count's suffix.
;; Also: WORDS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
BytesFreeMessage:
    .byte " BYTES FREE", CARRIAGE_RETURN, $00

;; The sign-on, printed on a cleared screen before the free-memory count.
;; Also: FREMES (M6502, CBM4S79, HV2, HV4, HV4R, BV20)
SignOnMessage:
    .byte CLEAR_SCREEN, "**** CBM BASIC V2 ****", CARRIAGE_RETURN, $00

;; The RAM vectors' defaults, copied to <ErrorVector> and the five vectors after it: the ROM's own routines.
;; Also: BVTRS (BV20)
VectorDefaults:
    .word ReportError::Default, CommandLoop::Default, Tokenize::Default
    .word Statements::List::CheckTokenDefault, ExecuteStatement::Default, EvaluateOperand::Default
    VECTOR_DEFAULTS_SIZE = * - VectorDefaults

    ;; Points BASIC's RAM vectors at the ROM's routines.
    ;; Out: X = $FF
    ;; Keeps: Y
    ;; Also: INITV (BV20)
    .proc InitializeVectors
    ldx #VECTOR_DEFAULTS_SIZE - 1

;; Copies the defaults, from the last byte down.
;; Also: INITV1 (BV20)
CopyVector:
    lda VectorDefaults,x
    sta ErrorVector,x
    dex
    bpl CopyVector
    rts
    .endproc

    ;; Warm-starts BASIC, as STOP-RESTORE and BRK do: puts the channels back to the keyboard and screen, resets the
    ;; stack, turns interrupts on and prints READY.
    ;; See: <ReadyForCommand>
    ;; Also: PANIC (BV20)
    .proc WarmStart
    jsr KernalResetChannels
    lda #$00
    sta CurrentChannel
    jsr ResetStack
    cli
    jmp ReadyForCommand
    .endproc
.endmacro
