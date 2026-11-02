;; PROGRAMMER'S AID #1: RENUMBER'S BASIC ENTRIES ($D6DD-$D716)
;;
;; The CALLs that renumber an Integer BASIC program from BASIC's variables: they read the new numbering and the range,
;; put them in Renumber's SWEET16 registers, and enter <Renumber::RENUM>. The variables must be the program's first,
;; in this order, which `CLR` then `START=` and `STEP=` (and `FROM=` and `TO=`) give:
;;
;; - START, the first new line number, and STEP, the step between them;
;; - FROM and TO, the lowest and highest line renumbered, for <RenumberCalls::RNMRNG> only.
;;
;; Apple's listings do not include this part; its names are this source's. Part of ProgrammersAid.asm.

.scope RenumberCalls

;; Inherit: <IntegerBasic:LOMEM>
LOMEM = $4A

; Where each variable's value is, from LOMEM: its name, the byte after it and the 2-byte link come first.
STARTVAL = $08                      ;; START, the first variable
STEPVAL = $11                       ;; STEP, the second
FROMVAL = $1A                       ;; FROM, the third
TOVAL = $21                         ;; TO, the fourth

; Renumber's SWEET16 registers, as the page-zero bytes they live in: register n is at 2n.
NEWLOW = Renumber::NEWLOW * 2       ;; the first new number (2 bytes)
NEWINCR = Renumber::NEWINCR * 2     ;; the step (2 bytes)
LNLOW = Renumber::LNLOW * 2         ;; the lowest line renumbered (2 bytes)
LNHI = Renumber::LNHI * 2           ;; the highest (2 bytes)

;; CALL -10531: renumbers every line, from START by STEP.
RNMALL:
    ldy #$00                        ; $D6DD
    sty LNLOW                       ; $D6DF from line 0
    sty LNLOW+1                     ; $D6E1
    dey                             ; $D6E3
    tya                             ; $D6E4
    bne RNMALL_1                    ; $D6E5 always: to line 65535

;; CALL -10521: renumbers the lines from FROM to TO, from START by STEP.
RNMRNG:
    ldy #FROMVAL                    ; $D6E7
    jsr GETVAR                      ; $D6E9
    sta LNLOW                       ; $D6EC
    sty LNLOW+1                     ; $D6EE
    ldy #TOVAL                      ; $D6F0
    jsr GETVAR                      ; $D6F2

RNMALL_1:
    sta LNHI                        ; $D6F5
    sty LNHI+1                      ; $D6F7
    ldy #STARTVAL                   ; $D6F9
    jsr GETVAR                      ; $D6FB
    sta NEWLOW                      ; $D6FE
    sty NEWLOW+1                    ; $D700
    ldy #STEPVAL                    ; $D702
    jsr GETVAR                      ; $D704
    sta NEWINCR                     ; $D707
    sty NEWINCR+1                   ; $D709
    jmp Renumber::RENUM             ; $D70B

;; Reads the value of the variable at an offset from LOMEM.
;; In: Y = the offset of its value
;; Out: A = the value's low byte, Y = its high byte
GETVAR:
    lda (LOMEM),y                   ; $D70E
    pha                             ; $D710
    iny                             ; $D711
    lda (LOMEM),y                   ; $D712
    tay                             ; $D714
    pla                             ; $D715
    rts                             ; $D716

.endscope
