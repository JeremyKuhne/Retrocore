; retrocore: style=strict
; APPLESOFT: COLD START ($F10B-$F1D4)
;
; CharacterReaderTemplate initializes the page-zero character reader and random seed; ColdStart installs the
; interpreter vectors, discovers available memory and enters CommandLoop. CharacterReaderTemplate immediately follows
; Float::ArctangentPolynomial in MsBasic.Transcendental.asm. AppleSoft.AppleCommands.asm follows this module.

    CharacterReader $58

;; Cold-starts AppleSoft, initializes its workspace and enters <CommandLoop>.
;;
;; It installs the restart and `USR` vectors, copies <CharacterReaderTemplate> and four bytes of the initial random
;; value to page zero, probes RAM by complementing and restoring a byte on each page, rounds the upper limit down to a 4
;; KB boundary, initializes the program at $0800 and resets the interpreter. The probe stops at the first location that
;; fails either test.
;; Also: INIT (M6502)
.proc ColdStart
    ldx #$FF
    stx CurrentLine+1
    ldx #$FB
    txs
    lda #<ColdStart
    ldy #>ColdStart
    sta RestartJump+1
    sty RestartJump+2
    sta PrintStringJump+1
    sty PrintStringJump+2
    jsr NRMSTM
    lda #$4C                        ; the JMP opcode for the vectors
    sta RestartJump
    sta PrintStringJump
    sta FunctionJump
    sta UserVector
    lda #<IllegalQuantityError
    ldy #>IllegalQuantityError
    sta UserVector+1
    sty UserVector+2
    ldx #$1C                        ; the reader and the four bytes of the random seed after it

;; Copies the character reader and the random seed to page zero.
;; Also: MOVCHG (M6502)
CopyCharacterReader:
    lda CharacterReaderTemplate-1,x
    sta GetNextCharacter-1,x
    stx OutputDelay
    dex
    bne CopyCharacterReader
    stx TraceMode
    txa
    sta ShiftFill
    sta LastTemporary+1
    pha
    lda #DESCRIPTOR_SIZE
    sta CollectorStep
    jsr PrintNewline
    lda #1
    sta BUF-3
    sta BUF-4
    ldx #TemporaryDescriptors
    stx NextTemporary
    lda #0
    ldy #8
    sta LineNumber
    sty LineNumber+1
    ldy #0

;; Complements and restores a byte on each page until one fails.
;; Also: LOOPMM (M6502)
ProbeMemory:
    inc LineNumber+1
    lda (LineNumber),y
    eor #$FF
    sta (LineNumber),y
    cmp (LineNumber),y
    bne FoundMemoryTop
    eor #$FF
    sta (LineNumber),y
    cmp (LineNumber),y
    beq ProbeMemory

;; Rounds the failing page down to 4 KB and sets <MemoryTop> and <StringsBottom>, then starts the program at $0801.
;; Also: USEDEC (M6502)
FoundMemoryTop:
    ldy LineNumber
    lda LineNumber+1
    and #$F0
    sty MemoryTop
    sta MemoryTop+1
    sty StringsBottom
    sta StringsBottom+1
    ldx #0
    ldy #8
    stx ProgramStart
    sty ProgramStart+1
    ldy #0
    sty RunOnly
    tya
    sta (ProgramStart),y
    inc ProgramStart
    bne CheckRoom
    inc ProgramStart+1

;; Checks room for the program, clears it and points the restart vector at <CommandLoop>.
;; Also: QROOM (M6502)
CheckRoom:
    lda ProgramStart
    ldy ProgramStart+1
    jsr CheckFreeMemory
    jsr EraseProgram
    lda #<PrintText
    ldy #>PrintText
    sta PrintStringJump+1
    sty PrintStringJump+2
    lda #<CommandLoop
    ldy #>CommandLoop
    sta RestartJump+1
    sty RestartJump+2
    jmp (RestartJump+1)
.endproc
