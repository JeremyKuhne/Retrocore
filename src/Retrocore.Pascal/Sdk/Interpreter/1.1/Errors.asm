; retrocore: style=strict
;; Execution errors: an entry for each error SYSTEM.APPLE raises, which loads its number and goes to Report. Report
;; records the error in SYSCOM and runs <ExecutionError::Call>, a <CXP at Pcodes::CallExternalProcedure> to
;; SYSTEM.PASCAL's execution error handler.
.scope ExecutionError

; Each entry's number is positive, so its BPL always goes to Report.

;; Reports <ERROR_VALUE_RANGE>.
;; Also: ERR1 (WK11)
ValueRange:
    lda #ERROR_VALUE_RANGE
    bpl Report

;; Reports <ERROR_NO_PROC_IN_SEG_TABLE>.
NoProcInSegTable:
    lda #ERROR_NO_PROC_IN_SEG_TABLE
    bpl Report

;; Reports <ERROR_EXIT_FROM_UNCALLED_PROC>.
;; Also: ERR3 (WK11)
ExitFromUncalledProc:
    lda #ERROR_EXIT_FROM_UNCALLED_PROC
    bpl Report

;; Makes room to report a stack overflow, and reports it: forgets the heap's directory, and moves <HeapTop> to
;; <OVERFLOW_HEAP> and <ProgramStackTop> to <OVERFLOW_STACK>.
;; Also: OOMERR (WK11)
ResetForOverflow:
    .assert <OVERFLOW_HEAP = 0 && <OVERFLOW_STACK = 0, "ResetForOverflow stores one 0 as both low bytes."

    ; Forget the directory.
    lda #0
    sta Syscom::Directory
    sta Syscom::Directory+1

    ; Move the heap and the stack out of the error handler's way.
    sta HeapTop
    sta ProgramStackTop
    lda #>OVERFLOW_STACK
    sta ProgramStackTop+1
    lda #>OVERFLOW_HEAP
    sta HeapTop+1

;; Reports <ERROR_STACK_OVERFLOW>.
StackOverflow:
    lda #ERROR_STACK_OVERFLOW
    bpl Report

;; Reports <ERROR_INTEGER_OVERFLOW>.
IntegerOverflow:
    lda #ERROR_INTEGER_OVERFLOW
    bpl Report

;; Reports <ERROR_DIVIDE_BY_ZERO>.
;; Also: ERR6 (WK11)
DivideByZero:
    lda #ERROR_DIVIDE_BY_ZERO
    bpl Report

;; Reports <ERROR_INTERRUPTED>. <UCLEAR at StandardProcedures::UnitClear> gives the console driver this address, through
;; <BreakHandler>, for the break key.
;; Also: ERR8 (WK11)
Interrupted:
    lda #ERROR_INTERRUPTED
    bpl Report

;; Reports <ERROR_SYSTEM_IO>.
;; Also: ERR9 (WK11)
SystemIo:
    lda #ERROR_SYSTEM_IO
    bpl Report

;; Reports <ERROR_USER_IO>.
;; Also: ERR10 (WK11)
UserIo:
    lda #ERROR_USER_IO
    bpl Report

;; Reports <ERROR_UNIMPLEMENTED>: what <EFJ>, <NFJ> and the standard procedures SIN to SQT run, as 1.1 does not
;; implement them.
;; Also: EFJ (A2POSRM), ERR11 (WK11), NFJ (A2POSRM)
Unimplemented:
    lda #ERROR_UNIMPLEMENTED
    bpl Report

;; Reports <ERROR_FLOATING_POINT>.
;; Also: ERR12 (WK11)
FloatingPoint:
    lda #ERROR_FLOATING_POINT
    bpl Report

;; Reports <ERROR_STRING_OVERFLOW>.
;; Also: ERR13 (WK11)
StringOverflow:
    lda #ERROR_STRING_OVERFLOW
    bpl Report

;; Records an execution error in SYSCOM and runs <Call>, which hands it to SYSTEM.PASCAL.
;; In: A = the error's number
Report:
    ; Record the error's number.
    sta Syscom::ErrorNumber
    lda #0
    sta Syscom::ErrorNumber+1

    ; Record where it happened.
    lda InstructionPointer
    sta Syscom::ErrorInstruction
    lda InstructionPointer+1
    sta Syscom::ErrorInstruction+1

    ; Record ProgramStackTop less a mark stack frame and the word below it.
    lda ProgramStackTop
    sec
    sbc #.sizeof(MarkStack) + KP_LINK_SIZE
    sta Syscom::ErrorFrame
    lda ProgramStackTop+1
    sbc #0
    sta Syscom::ErrorFrame+1

    ; Run Call.
    lda CallAddress
    sta InstructionPointer
    lda CallAddress+1
    sta InstructionPointer+1
    jmp Fetch::Next

    .cpu Pcode
;; The p-code <Report> runs: <CXP at Pcodes::CallExternalProcedure> 0,2, a call to SYSTEM.PASCAL's procedure 2, its
;; execution error handler, which prints the message with its PRINTERR segment.
;; Also: EXECERROR (A2POSRM, UCSD20)
Call:
    CXP 0, 2
    .cpu Mos6502

;; Call's address, for <Report> to set <InstructionPointer> to.
CallAddress:
    .word Call

.endscope
