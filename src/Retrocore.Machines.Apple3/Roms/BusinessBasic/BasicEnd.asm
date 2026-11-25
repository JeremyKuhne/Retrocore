; retrocore: style=strict
; BasicEnd.asm: the routines through which BASIC and the invokable modules call each other, and the end of BASIC.
;
; These routines switch banks under themselves, so they must not be in memory that switches: they come last so that
; they land above $A000, out of the banks at $2000-$9FFF. A module may live in another bank than BASIC.
;
; Apple's listing calls this file BASICEND; its names are kept in each definition's Also: section.

; Modules: the calls between BASIC and the modules.
.scope Modules continued

;; The Apple III's bank register: which bank of memory shows at $2000-$9FFF.
BankRegister = $FFEF

;; Calls one of BASIC's routines for an invokable module, by its number in <ModuleRoutineNumber>, with BASIC's bank
;; switched in, then switches the modules' bank back.
;;
;; A module reaches it with a JSR to <ModuleCallJump>. The routine's address is the number's entry in <ModuleRoutines>,
;; which ends just before this routine. A number past the table's end ends the statement with an ILLEGAL QUANTITY error,
;; with BASIC's bank already switched in. The number is doubled in a byte, so its bit 7 is lost: a number from 128 up
;; calls the routine 128 below it.
;; In: ModuleRoutineNumber = the routine's number, A, X, Y = passed on to the routine
;; Out: A, X, Y = as the routine left them
;; Uses: FunctionJump
;; Errors: <ERROR_ILLEGAL_QUANTITY> = a number past the table's end
;; Entry:
;;   ToIllegalQuantityError = ends the statement with ILLEGAL QUANTITY
;; See: <ModuleRoutines>, <Modules::CallModule>
;; Also: SWCHGO (BB13)
.proc CallBasic
    pha
    txa
    pha
    lda ModuleRoutineNumber
    asl
    tax
    lda ModuleRoutines,X
    sta FunctionJump+1
    lda ModuleRoutines+1,X
    sta FunctionJump+2
    lda BasicBank
    sta BankRegister                        ; BASIC's bank
    cpx #<(Modules::CallBasic-ModuleRoutines)
    bcs ToIllegalQuantityError              ; past the table's end
    pla
    tax
    pla
    jsr FunctionJump
    pha
    lda ModulesXByte
    sta BankRegister                        ; the modules' bank again
    pla
    rts

;; Ends the statement with ILLEGAL QUANTITY.
;; Also: BCALERR (BB13)
ToIllegalQuantityError:
    jmp IllegalQuantityError
.endproc

;; Calls the module routine whose address `PERFORM` or `EXFN.` put in <FunctionJump>, with the modules' bank switched
;; in, then returns to the statement that called `PERFORM` or `EXFN.`.
;;
;; The address is a pointer through the modules' bank pair; clearing bit 7 of its high byte and adding $20 makes it
;; the address in the switched bank. The return address was kept in <PerformSavedReturn> before the call, and the bank
;; that was switched in is kept in <PerformSavedReturn>+2 and switched back after.
;; Out: A = what the routine left in A
;; Uses: Temporary, SavedY, FunctionJump
;; See: <Modules::CallByName>, <Modules::CallBasic>
;; Also: JUMPDO (BB13)
.proc CallModule
    lda ModulesXByte
    sta Temporary
    lda BankRegister                        ; the bank switched in now
    sta PerformSavedReturn+2
    lda Temporary
    sta BankRegister                        ; the modules' bank
    lda FunctionJump+2
    and #Segments::PAGES_PER_BANK-1
    clc
    adc #Segments::WINDOW_PAGE              ; from the bank pair's address to the bank's
    sta FunctionJump+2
    jsr FunctionJump
    sta SavedY
    lda PerformSavedReturn+2                ; back to the bank that was in
    sta BankRegister
    lda PerformSavedReturn+1                ; return to the caller of `PERFORM` or `EXFN.`
    pha
    lda PerformSavedReturn
    pha
    lda SavedY
    rts
.endproc

    ; Apple's sign-off, at the end of the code.
    .byte "TH..TH..TH..THATS ALL, FOLKS!"

.endscope

;; The end of BASIC's code.
;; Also: ZZZZZ (BB13)
CodeEnd:
.if DEBUG

;; The end of BASIC, with the memory up to $A200+$1559 kept for the debugger.
;; Also: BASICEND (BB13)
BasicEnd = $A200+$1559
    .res BasicEnd-*
.else

;; The end of BASIC, which the header's length runs up to.
;; Also: BASICEND (BB13)
BasicEnd:
.endif
.if VERSION = 123
    ; 1.23's file runs 21 bytes past the length its header gives: whatever was in memory when Apple built SOS.INTERP.
    .byte $52, $D3, $60, $00, $CF, $52, $54, $C9, $20, $00, $89, $52, $54, $CE, $60, $00
    .byte $23, $52, $54, $D3, $20
.endif
