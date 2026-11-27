; retrocore: style=strict
; COMMODORE BASIC 4: PATCH AREA BEFORE THE VARIABLE OPERAND

.include "../../Microsoft6502Basic/MsBasic.Families.asm"

;; The bit of <IoStatus> that reports the end of a file.
STATUS_END_OF_FILE = $40

;; Where the variable operand resumes after the $B000 chip's patch area, at `EvaluateVariableBody` (BASIC 4).
PATCH_AREA_END = $BF8C

.ifndef PATCH_FILL
;; The fill of BASIC 4's unused ROM bytes, which both chips reserve for patches (defined here and in
;; Commodore.Basic4RomEnd.asm, whichever a source includes first).
PATCH_FILL = $AA
.endif

;; Emits the $B000 chip's checksum byte, BASIC 4's variable-operand trampoline, the revised chip's patches and the
;; unused patch space, up to `EvaluateVariableBody`.
;; Parameters: revised = 1 for the revised chip's checksum byte and patches, 0 for the original chip's
.macro CommodoreBasic4OperandSplit revised
    .assert revised = 0 || revised = 1, "revised is 0 or 1."

    ;; The byte that adjusts the $B000 chip's checksum; nothing reads it.
    ;; Also: CKSUMB (HV4, HV4R)
InterpreterChecksum:
    .if revised
        .byte $B8
    .else
        .byte $E1
    .endif

    ;; BASIC 4's variable operand: jumps over the patch area to <EvaluateVariableBody>. The shared evaluator branches
    ;; here, as it does to the other builds' own <EvaluateVariable>, so the patches can grow without moving its target.
    ;;
    ;; ISVAR is here because the overlay puts it here, and it cites, by the lineage rule, every bibliography document
    ;; naming Microsoft's ISVAR; BASIC 4's own documents (CBM4S79, HV4, HV4R) put the label on the lookup itself,
    ;; which in HV4 and HV4R is the code the trampoline jumps to.
    ;; Also: ISVAR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc EvaluateVariable
    jmp EvaluateVariableBody
    .endproc

    .if revised
        ;; The revised chip's test of whether a string is the disk status (`DS$`), for <FindStringLink>: `DS$` must be
        ;; nonempty as well as at the same address, so a string that later takes the released buffer's address is
        ;; linked.
        ;; In: A = the string's address (high byte), X = its low byte
        ;; Also: ADJDS (UNKN), PATCHG (HV4R)
        .proc TestStatusString
        pha
        lda DiskStatusDescriptor+StringDescriptor::LENGTH
        beq NoStatus
        pla
        cmp DiskStatusDescriptor+StringDescriptor::ADDRESS+1
        bne ToAddLength
        jmp FindStringLink::CompareStatusLow

;; `DS$` is empty: pulls the high byte back.
;; Also: ADJDS2 (UNKN), PATH0 (HV4R)
NoStatus:
        pla

;; Not `DS$`: jumps on to <FindStringLink::AddLength>.
;; Also: ADJDS3 (UNKN), PATH1 (HV4R)
ToAddLength:
        jmp FindStringLink::AddLength
        .endproc

        ;; The revised chip's statement fetch: gets the next character, and gives SYNTAX ERROR for the `PI` token,
        ;; which the original chip's <DispatchStatement> takes past the disk statements to an entry beyond the end of
        ;; <StatementTable>.
        ;; Out: A = the character, as <GetNextCharacter> leaves it, with its flags from <GetCurrentCharacter>
        ;; Errors: SYNTAX for `PI` as a statement
        ;; Also: GONEGT (UNKN), PATCHH (HV4R)
        .proc FetchStatementCharacter
        jsr GetNextCharacter
        cmp #<TOKEN_PI
        bne ToGetCurrentCharacter
        jmp SyntaxError

;; Jumps on to <GetCurrentCharacter>, which reloads the character and sets its flags.
;; Also: GONEG1 (UNKN)
ToGetCurrentCharacter:
        jmp GetCurrentCharacter
        .endproc

        ;; The revised chip's handling of a blank `INPUT` line: from the keyboard it stops the program; from a file it
        ;; reads the next line, or at the file's end goes on to assign the empty line.
        ;; In: CurrentChannel = the input channel, 0 for the keyboard
        ;; Also: INPNUL (UNKN), PATCHI (HV4R)
        .proc HandleBlankInput
        lda CurrentChannel
        bne FromFile
        jmp StopEmptyInput

;; From a file: at its end, the empty line is assigned; otherwise the next line is read.
;; Also: INPNU1 (UNKN)
FromFile:
        lda IoStatus
        and #STATUS_END_OF_FILE
        bne ToInputContinue
        jmp Statements::Input::ReadLine

;; Jumps on to <AssignInputList>.
;; Also: INPNU2 (UNKN)
ToInputContinue:
        jmp AssignInputList
        .endproc
    .endif

    ; The rest of the space is left for patches.
    .res PATCH_AREA_END - *, PATCH_FILL
    .assert * = PATCH_AREA_END, "BASIC 4's variable operand must resume at $BF8C."
.endmacro
