;; The copyright notice and credits, at &FC00-&FEFD.
;;
;; FRED, JIM and SHEILA cover &FC00-&FEFF, so the processor never reads these bytes; they are there for anyone who
;; reads the ROM chip itself. The notice begins with "(C)", the string a paged ROM's copyright offset must point
;; to, though nothing in the MOS looks for it here.
;; See: <FRED>, <JIM>, <SHEILA>
CREDITS:
    .byte "(C) 1981 Acorn Computers Ltd.Thanks are due to the following contributors to the development of th"
    .byte "e BBC Computer (among others too numerous to mention):- David Allen,Bob Austin,Ram Banerjee,Paul B"
    .byte "ond,Allen Boothroyd,Cambridge,Cleartone,John Coll,John Cox,Andy Cripps,Chris Curry,6502 designers,"
    .byte "Jeremy Dion,Tim Dobson,Joe Dunn,Paul Farrell,Ferranti,Steve Furber,Jon Gibbons,Andrew Gordon,Lawre"
    .byte "nce Hardwick,Dylan Harris,Hermann Hauser,Hitachi,Andy Hopper,ICL,Martin Jackson,Brian Jones,Chris "
    .byte "Jordan,David King,David Kitson,Paul Kriwaczek,Computer Laboratory,Peter Miller,Arthur Norman,Glyn "
    .byte "Phillips,Mike Prees,John Radcliffe,Wilberforce Road,Peter Robinson,Richard Russell,Kim Spence-Jone"
    .byte "s,Graham Tebby,Jon Thackray,Chris Turner,Adrian Warner,Roger Wilson,Alan Wright."

;; Two bytes that hold &D9CD, the address of <RESET>, just below <EXTENDED_VECTOR_ENTRIES>. SHEILA hides them, and
;; nothing reads them.
RESET_ADDRESS_COPY:
    .word RESET

    .assert * = $FF00, "The extended vector entries are at &FF00."

;; The extended vector entries: 27 calls to <EXTENDED_VECTOR_HANDLER>, one for each vector in page two.
;;
;; A paged ROM claims a vector by pointing it here, at &FF00 + 3 * n for vector n (USERV is 0 and IND3V 26), and
;; storing the address of its routine and its own ROM number at <EXTENDED_VECTORS> + 3 * n. A call through the vector
;; reaches the entry's JSR, which leaves the entry's address plus two on the stack: <EXTENDED_VECTOR_HANDLER> uses its
;; low byte, 3 * n + 2, to find the vector's three bytes.
;; See: <EXTENDED_VECTOR_HANDLER>, <EXTENDED_VECTORS_ADDRESS>
EXTENDED_VECTOR_ENTRIES:
    .repeat 27
        jsr EXTENDED_VECTOR_HANDLER
    .endrepeat

;; Calls a vector's routine in a paged ROM: selects the ROM, jumps to the routine with the caller's registers and
;; flags, and puts the ROM that was selected back when the routine returns.
;;
;; It builds a frame on the stack below the entry's return address: five bytes of space, then the flags, A, X and Y.
;; Into the space it writes, from the top, the ROM selected now, &FF88 (the address before
;; <EXTENDED_VECTOR_RETURN>), and the routine's address. Pulling Y, X and A and then an RTI restores the flags and
;; starts the routine, whose RTS returns to <EXTENDED_VECTOR_RETURN>.
;; In: STACK = the entry's address + 2, from its JSR; A, X, Y = the vector call's
;; Out: A, X, Y = as the vector's routine returns them
;; See: <EXTENDED_VECTOR_ENTRIES>, <EXTENDED_VECTOR_RETURN>, <EXTENDED_VECTORS>
EXTENDED_VECTOR_HANDLER:
    pha                             ; five bytes of space for the frame
    pha
    pha
    pha
    pha
    php
    pha
    txa
    pha
    tya
    pha
    tsx                             ; Y, X, A and the flags are at STACK+1 to STACK+4,x
    lda #>(EXTENDED_VECTOR_RETURN-1)
    sta STACK+8,x                   ; the routine's RTS returns to EXTENDED_VECTOR_RETURN
    lda #<(EXTENDED_VECTOR_RETURN-1)
    sta STACK+7,x
    ldy STACK+10,x                  ; the entry's return address, low byte: 3 * n + 2
    lda EXTENDED_VECTORS-2,y        ; the routine's address
    sta STACK+5,x
    lda EXTENDED_VECTORS-1,y
    sta STACK+6,x
    lda ROMSEL_COPY                 ; the ROM to restore afterwards
    sta STACK+9,x
    lda EXTENDED_VECTORS,y          ; the vector's ROM
    sta ROMSEL_COPY
    sta ROMSEL
    pla
    tay
    pla
    tax
    pla
    rti                             ; restores the flags and jumps to the routine

;; Where a paged ROM's vector routine returns: puts back the ROM that was selected before the call and returns to the
;; vector's caller with the routine's registers and flags.
;;
;; The stack holds the ROM to restore, then the return address of the entry's JSR, which is no longer needed, then
;; the vector caller's return address. The routine's A and flags are copied over the unneeded address, so the last
;; pulls restore the ROM, A and the flags in turn.
;; In: A, X, Y = as the routine returns them, with its flags
;; Keeps: A, X, Y
;; See: <EXTENDED_VECTOR_HANDLER>
EXTENDED_VECTOR_RETURN:
    php
    pha
    txa
    pha
    tsx                             ; X, A and the flags are at STACK+1 to STACK+3,x
    lda STACK+2,x                   ; A over the entry's return address, low byte
    sta STACK+5,x
    lda STACK+3,x                   ; and the flags over its high byte
    sta STACK+6,x
    pla
    tax
    pla
    pla
    pla                             ; the ROM selected before the call
    sta ROMSEL_COPY
    sta ROMSEL
    pla
    plp

;; The default contents of the vectors the MOS has no routine for: an RTS.
;; See: <DEFAULT_VECTORS>
UNUSED_VECTOR:
    rts

;; OSBYTE &9D: writes the byte in X to the file whose handle is in Y, through OSBPUT. A Tube host uses it for a fast
;; BPUT.
;;
;; OSBYTE calls its routines with carry set, so the branch is always taken.
;; In: X = the byte, Y = the file handle, carry = set
;; See: <OSBPUT>
FAST_BPUT:
    txa
    bcs OSBPUT                      ; always

;; OSBYTE &92: reads a byte of FRED, the 1 MHz bus's device page.
;; In: X = the offset in FRED
;; Out: Y = the byte
;; See: <READ_JIM>, <READ_SHEILA>
READ_FRED:
    ldy FRED,x
    rts

;; OSBYTE &94: reads a byte of JIM, the 1 MHz bus's paged memory.
;; In: X = the offset in JIM
;; Out: Y = the byte
;; See: <READ_FRED>, <READ_SHEILA>
READ_JIM:
    ldy JIM,x
    rts

;; OSBYTE &96: reads a byte of SHEILA, the BBC's own hardware.
;; In: X = the offset in SHEILA
;; Out: Y = the byte
;; See: <READ_FRED>, <READ_JIM>
READ_SHEILA:
    ldy SHEILA,x
    rts

;; The length of <DEFAULT_VECTORS>, in bytes, as the Advanced User Guide documents it at &FFB6.
;; See: <DEFAULT_VECTORS_ADDRESS>
DEFAULT_VECTORS_LENGTH:
    .byte 54

;; The address of <DEFAULT_VECTORS>, as the Advanced User Guide documents it at &FFB7, for software that restores
;; the vectors.
;; See: <DEFAULT_VECTORS_LENGTH>
DEFAULT_VECTORS_ADDRESS:
    .word DEFAULT_VECTORS

    .assert * = $FFB9, "The documented calls start at &FFB9."

;; OSRDRM: reads a byte from a paged ROM.
;; In: Y = the ROM, ROM_POINTER = the address
;; Out: A = the byte
;; See: <OSRDRM_HANDLER>
OSRDRM:
    jmp OSRDRM_HANDLER

;; VDUCHR: sends a character to the VDU driver, whatever OSWRCH's destinations.
;; In: A = the character
;; See: <VDU_DRIVER>
VDUCHR:
    jmp VDU_DRIVER

;; OSEVEN: raises an event, calling EVNTV if the event is enabled.
;; In: Y = the event number
;; See: <OSEVEN_HANDLER>, <EVNTV>
OSEVEN:
    jmp OSEVEN_HANDLER

;; GSINIT: starts reading a string from the text at TEXT_POINTER + Y, for <GSREAD>.
;; See: <GSINIT_HANDLER>
GSINIT:
    jmp GSINIT_HANDLER

;; GSREAD: reads the next character of a string that <GSINIT> started, decoding | escapes.
;; See: <GSREAD_HANDLER>
GSREAD:
    jmp GSREAD_HANDLER

;; NVRDCH: OSRDCH that does not go through RDCHV.
;; See: <RDCHV_DEFAULT>
NVRDCH:
    jmp RDCHV_DEFAULT

;; NVWRCH: OSWRCH that does not go through WRCHV.
;; See: <WRCHV_DEFAULT>
NVWRCH:
    jmp WRCHV_DEFAULT

;; OSFIND: opens or closes a file, through FINDV.
;; See: <FINDV>
OSFIND:
    jmp (FINDV)

;; OSGBPB: reads or writes a group of bytes, through GBPBV. The cassette filing system has no routine for it.
;; See: <GBPBV>
OSGBPB:
    jmp (GBPBV)

;; OSBPUT: writes a byte to a file, through BPUTV.
;; See: <BPUTV>
OSBPUT:
    jmp (BPUTV)

;; OSBGET: reads a byte from a file, through BGETV.
;; See: <BGETV>
OSBGET:
    jmp (BGETV)

;; OSARGS: reads or writes a file's arguments, through ARGSV.
;; See: <ARGSV>
OSARGS:
    jmp (ARGSV)

;; OSFILE: loads or saves a whole file, through FILEV.
;; See: <FILEV>
OSFILE:
    jmp (FILEV)

;; OSRDCH: reads a character from the current input stream, through RDCHV.
;; See: <RDCHV>
OSRDCH:
    jmp (RDCHV)

;; OSASCI: writes a character, writing a carriage return as a line feed and a carriage return.
;; In: A = the character
;; See: <OSNEWL>, <OSWRCH>
OSASCI:
    cmp #$0D
    bne OSWRCH

;; OSNEWL: writes a line feed and a carriage return.
;; Out: A = &0D
;; See: <OSASCI>, <OSWRCR>
OSNEWL:
    lda #$0A
    jsr OSWRCH

;; Writes a carriage return. Not one of the documented calls, but where <OSNEWL> and <OSASCI> finish.
;; Out: A = &0D
OSWRCR:
    lda #$0D

;; OSWRCH: writes a character to the current output streams, through WRCHV.
;; In: A = the character
;; See: <WRCHV>, <NVWRCH>
OSWRCH:
    jmp (WRCHV)

;; OSWORD: an OS call with a parameter block, through WORDV.
;; In: A = the call, X = the parameter block's address, low byte, Y = its high byte
;; See: <WORDV>, <OSBYTE>
OSWORD:
    jmp (WORDV)

;; OSBYTE: an OS call with byte parameters, through BYTEV.
;; In: A = the call, X = its first parameter, Y = its second
;; See: <BYTEV>, <OSWORD>
OSBYTE:
    jmp (BYTEV)

;; OSCLI: interprets a command line, through CLIV.
;; In: X = the command's address, low byte, Y = its high byte; the command ends with a carriage return
;; See: <CLIV>
OSCLI:
    jmp (CLIV)

;; The 6502's NMI, reset and IRQ vectors. An NMI runs the routine in page &0D that the NMI's owner (a disc or network
;; filing system) puts there; an IRQ or BRK goes to <IRQ_ENTRY>.
;; See: <NMI_ROUTINE>, <RESET>, <IRQ_ENTRY>
HARDWARE_VECTORS:
    .word NMI_ROUTINE
    .word RESET
    .word IRQ_ENTRY
