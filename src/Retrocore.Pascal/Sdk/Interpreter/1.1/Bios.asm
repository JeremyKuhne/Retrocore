; retrocore: style=strict
;; The common code at $FEE3-$FFFF: the bank switching entries, the BIOS's 22 stubs and their vectors, <BiosCall>, a few
;; of the console's helpers, and the 6502 vectors. It is in RAM shared by both banks, so it runs whichever is in.

; The BIOS's stubs and vectors.

;; The size of a BIOS stub, a JSR <BiosCall>.
BIOS_STUB_SIZE = 3

;; How far a stub's vector is past its JSR's return address, the stub's address plus 2. <BiosCall> adds it.
BIOS_VECTOR_OFFSET = $5A

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
;; <ConsoleInit> takes from its caller (<UCLEAR at StandardProcedures::UnitClear> and <Initialize>'s NoSystemFile give
;; it <ExecutionError::Interrupted>).
;; Also: TOBREAK (A2PBIOS), TOBRK (WK11)
.proc BreakJump
    lda LCBANK1
    jmp (ConsoleBreakVector)
.endproc

;; Switches bank 2 in and goes to <Startup>, which starts the system from the beginning. <Initialize>'s NoSystemFile
;; puts this address in the reset vector, so that RESET boots again once a boot disk is in.
;; Also: NOTOST (WK11)
.proc Boot
    lda LCBANK2
    jmp Startup
.endproc

;; Where the 6502's NMI, reset and IRQ vectors go: switches bank 1 in and jumps through <ResetHandler>, which
;; <Initialize> sets to <Pcodes::ExitSystem>.
.proc Reset
    lda LCBANK1
    jmp (ResetHandler)
.endproc

;; Where <Startup> ends: switches bank 1 in and goes to <Restart>, through <RestartJump> in bank 1.
;; Also: JPASCAL (A2PBIOS), OST (WK11)
.proc EnterRestart
    lda LCBANK1
    jmp RestartJump
.endproc

;; Has <PutScreen> show capital letters inverse.
;; Out: A = <INVERSE_CAPITALS>, zero = clear
;; Keeps: X, Y
;; Also: DOH12 (WK11)
.proc InverseCapitalsOn
    lda #INVERSE_CAPITALS
    sta InverseCapitals
    rts
.endproc

;; BIOS call 0: reads a character from the console, with <ConsoleRead>. The stubs are the table Apple's BIOS document
;; calls BIOSTBL in a comment.
;; Also: BIOS (A2PBIOS, WK11), CONSOLEREAD (UCSD20IO), JCREAD (WK11)
BiosConsoleRead:
    BiosStub 0, VectorConsoleRead

;; BIOS call 1: writes a character to the console, with <ConsoleWrite>.
;; Also: CONSOLEWRITE (UCSD20IO), JCWRT (WK11)
BiosConsoleWrite:
    BiosStub 1, VectorConsoleWrite

;; BIOS call 2: initializes the console, with <ConsoleInit>.
;; Also: CONSOLEINIT (UCSD20IO), JCINIT (WK11)
BiosConsoleInit:
    BiosStub 2, VectorConsoleInit

;; BIOS call 3: writes a character to the printer, with <PrinterWrite>.
;; Also: JPRTW (WK11), PRINTERWRITE (UCSD20IO)
BiosPrinterWrite:
    BiosStub 3, VectorPrinterWrite

;; BIOS call 4: initializes the printer, with <PrinterInit>.
;; Also: JPRTI (WK11), PRINTERINIT (UCSD20IO)
BiosPrinterInit:
    BiosStub 4, VectorPrinterInit

;; BIOS call 5: writes blocks to a Disk II drive, with <DiskWrite>.
;; Also: DISKWRITE (UCSD20IO), JDWRT (WK11)
BiosDiskWrite:
    BiosStub 5, VectorDiskWrite

;; BIOS call 6: reads blocks from a Disk II drive, with <DiskRead>.
;; Also: DISKREAD (UCSD20IO), JDREAD (WK11)
BiosDiskRead:
    BiosStub 6, VectorDiskRead

;; BIOS call 7: checks a Disk II drive's slot, with <DiskInit>.
;; Also: DISKINIT (UCSD20IO), JDINIT (WK11)
BiosDiskInit:
    BiosStub 7, VectorDiskInit

;; BIOS call 8: reads a character from the remote unit, with <RemoteRead>.
;; Also: JREMR (WK11), REMOTEREAD (UCSD20IO)
BiosRemoteRead:
    BiosStub 8, VectorRemoteRead

;; BIOS call 9: writes a character to the remote unit, with <RemoteWrite>.
;; Also: JREMW (WK11), REMOTEWRITE (UCSD20IO)
BiosRemoteWrite:
    BiosStub 9, VectorRemoteWrite

;; BIOS call 10: initializes the remote unit, with <RemoteInit>.
;; Also: JREMI (WK11), REMOTEINIT (UCSD20IO)
BiosRemoteInit:
    BiosStub 10, VectorRemoteInit

;; BIOS call 11: graphics write, which does nothing.
;; Also: JGRAFW (WK11)
BiosGraphicsWrite:
    BiosStub 11, VectorGraphicsWrite

;; BIOS call 12: graphics init, which shows text, with <GraphicsInit>.
;; Also: JGRAFI (WK11)
BiosGraphicsInit:
    BiosStub 12, VectorGraphicsInit

;; BIOS call 13: reserved, doing nothing. Apple's BIOS document gives it as the printer's read, which does nothing.
BiosReserved:
    BiosStub 13, VectorReserved

;; BIOS call 14: the console's status, with <ConsoleStatus>.
;; Also: JCONS (WK11)
BiosConsoleStatus:
    BiosStub 14, VectorConsoleStatus

;; BIOS call 15: the printer's status, with <SerialStatus>.
;; Also: JPRTS (WK11)
BiosPrinterStatus:
    BiosStub 15, VectorPrinterStatus

;; BIOS call 16: a disk's status, with <DiskStatus>.
;; Also: JDSKS (WK11)
BiosDiskStatus:
    BiosStub 16, VectorDiskStatus

;; BIOS call 17: the remote unit's status, with <SerialStatus>.
;; Also: JREMS (WK11)
BiosRemoteStatus:
    BiosStub 17, VectorRemoteStatus

;; BIOS call 18: polls the console's keys, with <ConsoleCheck>.
;; Also: KCONCK (A2PBIOS)
BiosConsoleCheck:
    BiosStub 18, VectorConsoleCheck

;; BIOS call 19: runs an attached unit's driver from <AttachedDrivers>, with <AttachedDriver>.
;; Also: JUSER (WK11)
BiosAttachedDriver:
    BiosStub 19, VectorAttachedDriver

;; BIOS call 20: runs a unit's driver from <UnitTable>, with <UnitDriver>.
;; Also: JUDDRV (WK11)
BiosUnitDriver:
    BiosStub 20, VectorUnitDriver

;; BIOS call 21: the Compiler's identifier search, with <IdSearch>.
;; Also: JTREE (WK11)
BiosIdSearch:
    BiosStub 21, VectorIdSearch

;; BIOS call 20's routine: runs a unit's driver, whose address less 1 is the unit's <UnitTable> entry, by pushing it
;; and returning to it.
;; In:
;;   Y = the unit times 2
;;   A, X, Stack = for the driver
;; Also: PSUBDR (A2PBIOS, WK11)
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
;; Also: DOH14 (WK11)
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
;; Also: IORTS (A2PBIOS)
.proc IgnoreCall
    rts
.endproc

;; A vector before call 0's, where a stub at $FEFD would find it. None is there, and nothing in SYSTEM.APPLE jumps
;; here.
;; Also: JCONCK (WK11)
VectorUnused:
    VectorTo ConsoleCheck

;; BIOS call 0's vector.
;; Also: BIOSAF (A2PBIOS, WK11)
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
;; Also: SAVERET (A2PBIOS), SAVRET (WK11)
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
;; Also: GOBACK (A2PBIOS)
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
;; Also: SAVRET2 (A2PBIOS)
Jump:
    jmp (BiosVector)
.endproc

;; The keys <ConsoleCheck> turns into others, by <ShiftKeysTo>, while the shift key is held: the keyboard's Shift-M,
;; Shift-N and Shift-P (], ^ and @), and its Control-Shift-M, N and P.
;; Also: XLTIN (WK11)
ShiftKeysFrom:
    .byte ']', '^', '@', CTRL_RIGHT_BRACKET, CTRL_CARET, CTRL_AT

;; What <ConsoleCheck> turns each of <ShiftKeysFrom> into: M, N and P, and ], ^ and @.
;; Also: XLTOUT (WK11)
ShiftKeysTo:
    .byte 'M', 'N', 'P', ']', '^', '@'

;; Moves the 40-column view to one half of the 80-column screen.
.scope ViewHalf

;; Moves the view to the other half: to the left half when <ViewLeft> is at the middle of the right or beyond, or else
;; to the right half.
;; Also: HTAB (A2PBIOS, WK11)
Toggle:
    lda ViewLeft
    cmp #PAGE_COLUMNS / 2
    bcs ShowLeft

;; Moves the view to the right half, columns 40-79.
ShowRight:
    lda #PAGE_COLUMNS
    bne Scroll

;; Moves the view to the left half, columns 0-39.
;; Also: TAB3 (A2PBIOS, WK11)
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
