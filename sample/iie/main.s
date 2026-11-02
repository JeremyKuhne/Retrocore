; Copyright (c) 2025 Jeremy W Kuhne
; SPDX-License-Identifier: MIT
; See LICENSE file in the project root for full license information

.setcpu "6502"
.export entry, after_call, counter

.segment "CODE"
entry:                  ;; Shows an A at the top left, then counts X from 1 to 3 with <increment>.
    lda #$C1
    sta $0400
    ldx #0
loop:
    jsr increment
after_call:             ;; Where each call to <increment> returns.
    stx counter
    cpx #3
    bne loop
done:
    jmp done
increment:
    inx
    rts

.segment "BSS"
counter: .res 1         ;; The latest count.
