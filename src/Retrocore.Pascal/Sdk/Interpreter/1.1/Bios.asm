; retrocore: style=strict
;; The common code at $FEE3-$FFFF: the bank switching entries, the BIOS's 22 stubs and their vectors, <BiosCall>, a few
;; of the console's helpers, and the 6502 vectors. It is in RAM shared by both banks, so it runs whichever is in.

; The BIOS's stubs and vectors.

;; The size of a BIOS stub, a JSR <BiosCall>.
BIOS_STUB_SIZE = 3

;; How far a stub's vector is past its JSR's return address, the stub's address plus 2. <BiosCall> adds it.
BIOS_VECTOR_OFFSET = $5A

; The console's flags.

; The 80-column screen's two halves.

; The keys ConsoleCheck turns into others.

;; One of the BIOS's stubs, <BiosConsoleRead> and the 21 after it: a JSR to <BiosCall>, which runs the vector
;; <BIOS_VECTOR_OFFSET> bytes past the JSR's return address.
;; Parameters:
;;   number = the BIOS call's number, from 0; the stubs go in call order, <BIOS_STUB_SIZE> bytes apart
;;   vector = the call's vector, which must be where <BiosCall> looks for it
.macro BiosStub number, vector
    .assert * = BiosConsoleRead + BIOS_STUB_SIZE * number, "The BIOS's stubs are in call order."
    .assert vector = * + 2 + BIOS_VECTOR_OFFSET, "A stub's vector is BIOS_VECTOR_OFFSET past its return address."
    jsr BiosCall
.endmacro

;; One of the BIOS's vectors: a JMP to the routine that runs a BIOS call, which <BiosCall> jumps to with bank 2 in.
;; Parameters:
;;   routine = the routine
.macro VectorTo routine
    jmp routine
.endmacro

;; Where the console's break key goes, from bank 2: switches bank 1 in and jumps through <ConsoleBreakVector>, which
;; <ConsoleInit> takes from its caller (<UCLEAR at UnitIo::CspUCLEAR> and <Initialize>'s NoSystemFile give it
;; <ExecutionError::Interrupted>).
.proc BreakJump
    lda LCBANK1
    jmp (ConsoleBreakVector)
.endproc

;; Switches bank 2 in and goes to <Startup>, which starts the system from the beginning. <Initialize>'s NoSystemFile
;; puts this address in the reset vector, so that RESET boots again once a boot disk is in.
.proc Boot
    lda LCBANK2
    jmp Startup
.endproc

;; Where the 6502's NMI, reset and IRQ vectors go: switches bank 1 in and jumps through <ResetHandler>, which
;; <Initialize> sets to <OpXIT>.
.proc Reset
    lda LCBANK1
    jmp (ResetHandler)
.endproc

;; Where <Startup> ends: switches bank 1 in and goes to <Restart>, through <RestartJump> in bank 1.
.proc EnterRestart
    lda LCBANK1
    jmp RestartJump
.endproc

;; Has <PutScreen> show capital letters inverse.
;; Out: A = <INVERSE_CAPITALS>, zero = clear
;; Keeps: X, Y
.proc InverseCapitalsOn
    lda #INVERSE_CAPITALS
    sta InverseCapitals
    rts
.endproc

;; BIOS call 0: reads a character from the console, with <ConsoleRead>.
BiosConsoleRead:
    BiosStub 0, VectorConsoleRead

;; BIOS call 1: writes a character to the console, with <ConsoleWrite>.
BiosConsoleWrite:
    BiosStub 1, VectorConsoleWrite

;; BIOS call 2: initializes the console, with <ConsoleInit>.
BiosConsoleInit:
    BiosStub 2, VectorConsoleInit

;; BIOS call 3: writes a character to the printer, with <PrinterWrite>.
BiosPrinterWrite:
    BiosStub 3, VectorPrinterWrite

;; BIOS call 4: initializes the printer, with <PrinterInit>.
BiosPrinterInit:
    BiosStub 4, VectorPrinterInit

;; BIOS call 5: writes blocks to a Disk II drive, with <DiskWrite>.
BiosDiskWrite:
    BiosStub 5, VectorDiskWrite

;; BIOS call 6: reads blocks from a Disk II drive, with <DiskRead>.
BiosDiskRead:
    BiosStub 6, VectorDiskRead

;; BIOS call 7: checks a Disk II drive's slot, with <DiskInit>.
BiosDiskInit:
    BiosStub 7, VectorDiskInit

;; BIOS call 8: reads a character from the remote unit, with <RemoteRead>.
BiosRemoteRead:
    BiosStub 8, VectorRemoteRead

;; BIOS call 9: writes a character to the remote unit, with <RemoteWrite>.
BiosRemoteWrite:
    BiosStub 9, VectorRemoteWrite

;; BIOS call 10: initializes the remote unit, with <RemoteInit>.
BiosRemoteInit:
    BiosStub 10, VectorRemoteInit

;; BIOS call 11: graphics write, which does nothing.
BiosGraphicsWrite:
    BiosStub 11, VectorGraphicsWrite

;; BIOS call 12: graphics init, which shows text, with <GraphicsInit>.
BiosGraphicsInit:
    BiosStub 12, VectorGraphicsInit

;; BIOS call 13: reserved, and does nothing.
BiosReserved:
    BiosStub 13, VectorReserved

;; BIOS call 14: the console's status, with <ConsoleStatus>.
BiosConsoleStatus:
    BiosStub 14, VectorConsoleStatus

;; BIOS call 15: the printer's status, with <SerialStatus>.
BiosPrinterStatus:
    BiosStub 15, VectorPrinterStatus

;; BIOS call 16: a disk's status, with <DiskStatus>.
BiosDiskStatus:
    BiosStub 16, VectorDiskStatus

;; BIOS call 17: the remote unit's status, with <SerialStatus>.
BiosRemoteStatus:
    BiosStub 17, VectorRemoteStatus

;; BIOS call 18: polls the console's keys, with <ConsoleCheck>.
BiosConsoleCheck:
    BiosStub 18, VectorConsoleCheck

;; BIOS call 19: runs an attached unit's driver from <AttachedDrivers>, with <AttachedDriver>.
BiosAttachedDriver:
    BiosStub 19, VectorAttachedDriver

;; BIOS call 20: runs a unit's driver from <UnitTable>, with <UnitDriver>.
BiosUnitDriver:
    BiosStub 20, VectorUnitDriver

;; BIOS call 21: the Compiler's identifier search, with <IdSearch>.
BiosIdSearch:
    BiosStub 21, VectorIdSearch

;; BIOS call 20's routine: runs a unit's driver, whose address less 1 is the unit's <UnitTable> entry, by pushing it
;; and returning to it.
;; In:
;;   Y = the unit times 2
;;   A, X, Stack = for the driver
.proc UnitDriver
    ; Push the driver's address less 1, which RTS goes to, keeping A for it.
    sta BiosSavedA
    lda UnitTable+1,y
    pha
    lda UnitTable,y
    pha
    lda BiosSavedA
    rts
.endproc

;; Locks the keyboard in upper case and has <PutScreen> show capital letters normally, as output $14 does.
;; Out: A = 0
;; Keeps: X, Y
.proc UpperCaseLock
    lda #KEYBOARD_UPPER
    sta KeyboardCase

    ; KEYBOARD_UPPER shifted left is 0.
    asl a
    sta InverseCapitals
    rts
.endproc

    ; An unused byte.
    .byte 0

;; What BIOS calls 11 and 13, graphics write and the reserved call, run: returns at once.
;; Keeps: A, X, Y
.proc IgnoreCall
    rts
.endproc

;; A vector before call 0's, where a stub at $FEFD would find it. None is there, and nothing in SYSTEM.APPLE jumps
;; here.
VectorUnused:
    VectorTo ConsoleCheck

;; BIOS call 0's vector.
VectorConsoleRead:
    VectorTo ConsoleRead

;; BIOS call 1's vector.
VectorConsoleWrite:
    VectorTo ConsoleWrite

;; BIOS call 2's vector.
VectorConsoleInit:
    VectorTo ConsoleInit

;; BIOS call 3's vector.
VectorPrinterWrite:
    VectorTo PrinterWrite

;; BIOS call 4's vector.
VectorPrinterInit:
    VectorTo PrinterInit

;; BIOS call 5's vector.
VectorDiskWrite:
    VectorTo DiskWrite

;; BIOS call 6's vector.
VectorDiskRead:
    VectorTo DiskRead

;; BIOS call 7's vector.
VectorDiskInit:
    VectorTo DiskInit

;; BIOS call 8's vector.
VectorRemoteRead:
    VectorTo RemoteRead

;; BIOS call 9's vector.
VectorRemoteWrite:
    VectorTo RemoteWrite

;; BIOS call 10's vector.
VectorRemoteInit:
    VectorTo RemoteInit

;; BIOS call 11's vector.
VectorGraphicsWrite:
    VectorTo IgnoreCall

;; BIOS call 12's vector.
VectorGraphicsInit:
    VectorTo GraphicsInit

;; BIOS call 13's vector.
VectorReserved:
    VectorTo IgnoreCall

;; BIOS call 14's vector.
VectorConsoleStatus:
    VectorTo ConsoleStatus

;; BIOS call 15's vector.
VectorPrinterStatus:
    VectorTo SerialStatus

;; BIOS call 16's vector.
VectorDiskStatus:
    VectorTo DiskStatus

;; BIOS call 17's vector.
VectorRemoteStatus:
    VectorTo SerialStatus

;; BIOS call 18's vector.
VectorConsoleCheck:
    VectorTo ConsoleCheck

;; BIOS call 19's vector.
VectorAttachedDriver:
    VectorTo AttachedDriver

;; BIOS call 20's vector.
VectorUnitDriver:
    VectorTo UnitDriver

;; BIOS call 21's vector.
VectorIdSearch:
    VectorTo IdSearch

;; Runs the BIOS call whose stub called it: switches bank 2 in, jumps through the stub's vector, then switches bank 1
;; back in and returns to the stub's caller.
;; In:
;;   A, X, Y = the call's
;;   Stack = the stub's return address, over its caller's and the call's arguments
;; Out: A, X, Y, carry = as the call's routine leaves them
.proc BiosCall
    ; The vector is BIOS_VECTOR_OFFSET past the stub's return address.
    sta BiosSavedA
    pla
    clc
    adc #BIOS_VECTOR_OFFSET
    sta BiosVector
    pla
    adc #0
    sta BiosVector+1

    ; Keep the caller's return address, so that the routine finds the call's arguments just under its own.
    pla
    sta BiosCaller
    pla
    sta BiosCaller+1

    ; Switch bank 2 in and run the routine, which returns to Return.
    lda LCBANK2
    lda BiosSavedA
    jsr Jump

;; Where a BIOS call's routine returns to: switches bank 1 back in and returns to the stub's caller. The status
;; routines, which drop their return address, come here with JMP.
;; In: A = the call's result
;; Out: A, X, Y, carry = as the routine left them
Return:
    sta BiosSavedA
    lda BiosCaller+1
    pha
    lda BiosCaller
    pha
    lda LCBANK1
    lda BiosSavedA
    rts

;; Jumps through the vector <BiosCall> worked out.
Jump:
    jmp (BiosVector)
.endproc

;; The keys <ConsoleCheck> turns into others, by <ShiftKeysTo>, while the shift key is held: the keyboard's Shift-M,
;; Shift-N and Shift-P (], ^ and @), and its Control-Shift-M, N and P.
ShiftKeysFrom:
    .byte ']', '^', '@', CTRL_RIGHT_BRACKET, CTRL_CARET, CTRL_AT

;; What <ConsoleCheck> turns each of <ShiftKeysFrom> into: M, N and P, and ], ^ and @.
ShiftKeysTo:
    .byte 'M', 'N', 'P', ']', '^', '@'

;; Moves the 40-column view to one half of the 80-column screen.
.scope ViewHalf

;; Moves the view to the other half: to the left half when <ViewLeft> is at the middle of the right or beyond, or else
;; to the right half.
Toggle:
    lda ViewLeft
    cmp #PAGE_COLUMNS / 2
    bcs ShowLeft

;; Moves the view to the right half, columns 40-79.
ShowRight:
    lda #PAGE_COLUMNS
    bne Scroll

;; Moves the view to the left half, columns 0-39.
ShowLeft:
    lda #0

    ; Scroll by the difference.
Scroll:
    sec
    sbc ViewLeft
    jmp ScrollView

.endscope

    ; Unused.
    .res 10

;; Boot's address, which <Initialize>'s NoSystemFile puts in the reset vector.
BootVector:
    .word Boot

    .assert * = $FFFA, "The 6502's vectors are at $FFFA."

;; The 6502's NMI vector.
NmiVector:
    .word Reset

;; The 6502's reset vector. <Initialize>'s NoSystemFile puts <BootVector> here while it waits, and <Initialize> puts the
;; old value back.
ResetVector:
    .word Reset

;; The 6502's IRQ and BRK vector.
IrqVector:
    .word Reset
