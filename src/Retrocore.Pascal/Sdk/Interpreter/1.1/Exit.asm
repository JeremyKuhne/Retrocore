; retrocore: style=strict
;; <XIT at Pcodes::ExitSystem>, which leaves the system.

; Pcodes: ExitSystem.
.scope Pcodes continued

;; <XIT at Pcodes::ExitSystem>: restarts the machine from the ROMs. It writes LDA <LCROM1> and JMP (<ResetVector>) into
;; zero page and runs it there, since the language card it runs in is switched out under it; the JMP then goes through
;; the ROM's reset vector.
;; Also: XIT (A2PBIOS, A2POSRM, UCSD20, WK11)
.proc ExitSystem

;; Where <XIT at Pcodes::ExitSystem> writes its code: zero page's first 6 bytes.
Code = $00

    ; Write LDA LCROM1.
    lda #LDA_ABSOLUTE
    sta Code
    lda #<LCROM1
    sta Code+1
    lda #>LCROM1
    sta Code+2

    ; Write JMP (ResetVector).
    lda #JMP_INDIRECT
    sta Code+3
    lda #<ResetVector
    sta Code+4
    lda #>ResetVector
    sta Code+5

    ; Run it.
    jmp Code
.endproc
.endscope
