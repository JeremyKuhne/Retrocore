; BASICEND: the routines through which BASIC and the invokable modules call each other, and the end of BASIC.
;
; These routines switch banks under themselves, so they must not be in memory that switches: they come last so that
; they land above $A000, out of the banks at $2000-$9FFF. A module may live in another bank than BASIC.
;
; Names follow Apple's Business BASIC 1.3 listing.

;; Calls one of BASIC's routines for an invokable module, by its number in <PASSAREG>, with BASIC's bank switched in,
;; then switches the modules' bank back.
;;
;; A module reaches it with a JSR to <DISPATCH>. The routine's address is the number's entry in <JMPRTAB>. A number
;; past the table's end ends the statement with an ILLEGAL QUANTITY error, with BASIC's bank already switched in.
;; In: PASSAREG = the routine's number, A, X, Y = passed on to the routine
;; Out: A, X, Y = as the routine left them
;; Uses: JMPER
;; See: <JMPRTAB>, <JUMPDO>
SWCHGO:
    pha
    txa
    pha
    lda PASSAREG
    asl
    tax
    lda JMPRTAB,X
    sta JMPER+1
    lda JMPRTAB+1,X
    sta JMPER+2
    lda BASICBNK
    sta $FFEF                               ; The bank register: BASIC's bank
    cpx #<(SWCHGO-JMPRTAB)
    bcs BCALERR                             ; Past the table's end
    pla
    tax
    pla
    jsr JMPER
    pha
    lda INVBNK
    sta $FFEF                               ; The modules' bank again
    pla
    rts

;; Ends the statement with ILLEGAL QUANTITY, for <SWCHGO>.
BCALERR:
    jmp FCERR

;; Calls the module routine whose address PERFORM or EXFN put in <JMPER>, with the modules' bank switched in, then
;; returns to the statement that called PERFORM or EXFN.
;;
;; The address is a pointer through the modules' bank pair; clearing bit 7 of its high byte and adding $20 makes it
;; the address in the switched bank. The return address was kept in <SAFE> before the call, and the bank that was
;; switched in is kept in SAFE+2 and switched back after.
;; Out: A = what the routine left in A
;; Uses: TEMP, YSAVE, JMPER
;; See: <PERFORM>, <SWCHGO>
JUMPDO:
    lda INVBNK
    sta TEMP
    lda $FFEF                               ; The bank switched in now
    sta SAFE+2
    lda TEMP
    sta $FFEF                               ; The modules' bank
    lda JMPER+2
    and #$7F
    clc
    adc #$20                                ; From the bank pair's address to the bank's
    sta JMPER+2
    jsr JMPER
    sta YSAVE
    lda SAFE+2                              ; Back to the bank that was in
    sta $FFEF
    lda SAFE+1                              ; Return to PERFORM's or EXFN's caller
    pha
    lda SAFE
    pha
    lda YSAVE
    rts
    .byte "TH..TH..TH..THATS ALL, FOLKS!"   ; Apple's sign-off, at the end of the code

;; The end of BASIC's code.
ZZZZZ:
.if DEBUG

;; The end of BASIC, with $1559 bytes past its code kept for the debugger.
BASICEND = $A200+$1559
    .res BASICEND-*
.else

;; The end of BASIC, which the header's length runs up to.
BASICEND:
.endif
.if VERSION = 123
; 1.23's file runs 21 bytes past the length its header gives: whatever was in memory when Apple built SOS.INTERP.
    .byte $52, $D3, $60, $00, $CF, $52, $54, $C9, $20, $00, $89, $52, $54, $CE, $60, $00
    .byte $23, $52, $54, $D3, $20
.endif
