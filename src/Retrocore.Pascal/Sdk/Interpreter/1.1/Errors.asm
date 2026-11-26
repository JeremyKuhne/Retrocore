; retrocore: style=strict
;; Execution errors: an entry for each error SYSTEM.APPLE raises, which loads its number and goes to Report. Report
;; records the error in SYSCOM and runs <ExecutionError::Call>, a <CXP at OpCXP> to SYSTEM.PASCAL's execution error
;; handler.
.scope ExecutionError

; Each entry's number is positive, so its BPL always goes to Report.

;; Reports <ERROR_VALUE_RANGE>.
ValueRange:
    lda #ERROR_VALUE_RANGE
    bpl Report

;; Reports <ERROR_NO_PROC_IN_SEG_TABLE>.
NoProcInSegTable:
    lda #ERROR_NO_PROC_IN_SEG_TABLE
    bpl Report

;; Reports <ERROR_EXIT_FROM_UNCALLED_PROC>.
ExitFromUncalledProc:
    lda #ERROR_EXIT_FROM_UNCALLED_PROC
    bpl Report

;; Makes room to report a stack overflow, and reports it: forgets the heap's directory, and moves <NP> to
;; <OVERFLOW_HEAP> and <KP> to <OVERFLOW_STACK>.
ResetForOverflow:
    .assert <OVERFLOW_HEAP = 0 && <OVERFLOW_STACK = 0, "ResetForOverflow stores one 0 as both low bytes."

    ; Forget the directory.
    lda #0
    sta SysDirectory
    sta SysDirectory+1

    ; Move the heap and the stack out of the error handler's way.
    sta NP
    sta KP
    lda #>OVERFLOW_STACK
    sta KP+1
    lda #>OVERFLOW_HEAP
    sta NP+1

;; Reports <ERROR_STACK_OVERFLOW>.
StackOverflow:
    lda #ERROR_STACK_OVERFLOW
    bpl Report

;; Reports <ERROR_INTEGER_OVERFLOW>.
IntegerOverflow:
    lda #ERROR_INTEGER_OVERFLOW
    bpl Report

;; Reports <ERROR_DIVIDE_BY_ZERO>.
DivideByZero:
    lda #ERROR_DIVIDE_BY_ZERO
    bpl Report

;; Reports <ERROR_INTERRUPTED>. <UCLEAR at UnitIo::CspUCLEAR> gives the console driver this address, through
;; <BreakHandler>, for the break key.
Interrupted:
    lda #ERROR_INTERRUPTED
    bpl Report

;; Reports <ERROR_SYSTEM_IO>.
SystemIo:
    lda #ERROR_SYSTEM_IO
    bpl Report

;; Reports <ERROR_USER_IO>.
UserIo:
    lda #ERROR_USER_IO
    bpl Report

;; Reports <ERROR_UNIMPLEMENTED>: what EFJ, NFJ and the standard procedures SIN to SQT run, as 1.1 does not implement
;; them.
Unimplemented:
    lda #ERROR_UNIMPLEMENTED
    bpl Report

;; Reports <ERROR_FLOATING_POINT>.
FloatingPoint:
    lda #ERROR_FLOATING_POINT
    bpl Report

;; Reports <ERROR_STRING_OVERFLOW>.
StringOverflow:
    lda #ERROR_STRING_OVERFLOW
    bpl Report

;; Records an execution error in SYSCOM and runs <Call>, which hands it to SYSTEM.PASCAL.
;; In: A = the error's number
Report:
    ; Record the error's number.
    sta SysErrorNumber
    lda #0
    sta SysErrorNumber+1

    ; Record where it happened.
    lda IPC
    sta SysIpc
    lda IPC+1
    sta SysIpc+1

    ; Record KP less a mark stack frame and the word below it.
    lda KP
    sec
    sbc #MSCW_SIZE + KP_LINK_SIZE
    sta SysErrorStack
    lda KP+1
    sbc #0
    sta SysErrorStack+1

    ; Run Call.
    lda CallAddress
    sta IPC
    lda CallAddress+1
    sta IPC+1
    jmp Fetch::Next

    .cpu Pcode
;; The p-code <Report> runs: <CXP at OpCXP> 0,2, a call to SYSTEM.PASCAL's procedure 2, its execution error handler,
;; which prints the message with its PRINTERR segment.
Call:
    CXP 0, 2
    .cpu Mos6502

;; Call's address, for <Report> to set <IPC> to.
CallAddress:
    .word Call

.endscope
