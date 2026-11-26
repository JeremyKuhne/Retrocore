; retrocore: style=strict
;; Apple Pascal 1.1's p-machine interpreter, SYSTEM.APPLE, for the Apple II.
;;
;; Assembled with SYSTEM.APPLE.cfg, it is byte-identical to SYSTEM.APPLE on Apple Pascal 1.1's APPLE1 and APPLE3
;; disks. The file holds the language card's 16K in three sections, in this order: bank 2 at $D000, then
;; $E000-$FFFF, then bank 1 at $D000. Within each section the files follow in address order.

    .include <Pascal/Pcode.asm>             ; P-code macros, and the standard procedures' numbers, as CSP::IOC
    .cpu Mos6502

    .include "Macros.asm"                   ; The dispatch tables' macros
    .include "Constants.asm"                ; Constants the files share
    .include "ZeroPage.asm"                 ; The p-machine's registers, dispatch, working storage, the BIOS's bytes
    .include "Syscom.asm"                   ; SYSCOM, and the segment tables below it
    .include "Memory.asm"                   ; The stack, the disk's pages, screen holes, the BIOS's area
    .include "Hardware.asm"                 ; Soft switches and slot devices

    ; Bank 2 of the language card, $D000-$DFFF: the BIOS's drivers and Startup.
    .section BANK2
    .include "DiskTransfer.asm"             ; Disk II: transfers a track at a time, and seeks
    .include "DiskSectors.asm"              ; Disk II: sectors, nibbles and address fields
    .include "DiskArm.asm"                  ; Disk II: the arm, timing, prenibbling, finding the controllers
    .include "Startup.asm"                  ; Startup: memory, the slots' cards, the screen and disks
    .include "Console.asm"                  ; The keyboard, type-ahead, and reading keys
    .include "Devices.asm"                  ; The printer, remote and graphics units, and the card drivers
    .include "Screen.asm"                   ; The 80-column screen on two text pages
    .include "Status.asm"                   ; The BIOS's status calls
    .include "IdSearch.asm"                 ; The Compiler's identifier search, and its reserved words
    .include "DiskVariables.asm"            ; Disk II: its variables at the end of bank 2

    ; $E000-$FFFF: calls, segments, floating point, unit I/O, Restart and Initialize, the BIOS's stubs.
    .section HIGH
    .include "SetCompare.asm"               ; Set comparisons, continued from bank 1's SetsEqual
    .include "Calls.asm"                    ; Procedure calls and returns
    .include "Segments.asm"                 ; Reading segments in, relocating, and giving them back
    .include "StandardProcedures.asm"       ; CSP and the standard procedures not grouped elsewhere
    .include "RealMath.asm"                 ; Floating point
    .include "UnitIo.asm"                   ; Unit I/O and character I/O
    .include "Initialize.asm"               ; Restart and Initialize, which loads SYSTEM.PASCAL
    .include "UnitTables.asm"               ; Free storage, the attached drivers' JMPs, the unit table
    .include "Bios.asm"                     ; The BIOS's stubs and vectors, and the 6502 vectors

    ; Bank 1 of the language card, $D000-$DFFF: the dispatch tables, the fetch and most handlers.
    .section BANK1
    .include "OpcodeTables.asm"             ; OpcodeTable and CspTable
    .include "Core.asm"                     ; Big operands, static links, the heap's directory, .INTERP
    .include "Errors.asm"                   ; Execution errors
    .include "Fetch.asm"                    ; The fetch and dispatch
    .include "Jumps.asm"                    ; FJP and UJP
    .include "Variables.asm"                ; Constants, locals, globals, intermediates, indirect words
    .include "Moves.asm"                    ; Multiple-word constants, loads and stores, bytes, MOV
    .include "Logic.asm"                    ; Logical operations
    .include "Case.asm"                     ; XJP, the case jump
    .include "Heap.asm"                     ; NEW, MARK and RELEASE
    .include "Exit.asm"                     ; XIT, which leaves the system
    .include "IntegerMath.asm"              ; Integer arithmetic and CHK
    .include "Strings.asm"                  ; Strings and packed arrays of characters
    .include "Structures.asm"               ; Indirection, records, arrays and packed fields
    .include "Sets.asm"                     ; Sets
    .include "Comparisons.asm"              ; Comparisons
    .include "SetHelpers.asm"               ; The set comparisons' helpers, to SetsEqual
