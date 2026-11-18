;; MBASIC 5.21: START-UP (GWINIT)
;;
;; Starts BASIC when CP/M runs MBASIC.COM, from the JP at $0100, as GW-BASIC's GWINIT.ASM does, step for step.
;; Runs at $5D6F-$5FFF, the top of the image. In order, INIT:
;;
;; - sets up a stack, the console hooks that call CP/M's BIOS directly (its CONST, CONIN, CONOUT and LIST
;;   entries, found through the warm-start vector at $0001), and the record functions for the CP/M version
;;   (CPMVR1), and clears BASIC's flags;
;; - takes the top of memory from the BDOS address at $0006 and reads the command line in TBUFF,
;;   MBASIC [file] [/F:files] [/M:memory] [/S:record size], where a number may be decimal or &H or &O
;;   (CNSGET). The file name gets a quote before it, for RUN, and TEMP8 points at it. /F: sets MAXFIL (3 by
;;   default, at most 15), /M: the highest address BASIC may use, /S: the largest random record (128 by default);
;; - lays out the file data blocks from FILDB0 up: file 0's, of FD_RLEN bytes, then MAXFIL blocks of FD_FIELD bytes
;;   and a FIELD buffer of the record size each, filling FILPTR. The program's text starts after them;
;; - puts the stack an eighth of the free memory, at most 512 bytes, below the top, with string space under it
;;   (DONCMD, SMLSTK), and prints HEDING, the free bytes and BYTFRE;
;; - goes to INITSA, which closes the files and runs the file named on the command line (LRUN), or goes to READY.
;;
;; INIT, its messages and its command-line scan sit above INITSA so that they can be reclaimed once BASIC has
;; started: file 0's block starts at FILDB0, just below INIT, and the blocks and then the program's text cover the
;; rest. The variables TEMPB, FLDPTR, SECPTR and PUTFLG, of FIELD and the random GET and PUT (Disk2.asm), and
;; INITSA itself, stay below FILDB0.

;; FIELD: the total width of the fields so far; GET and PUT: the CP/M record (sector) being read or written.
TEMPB:
    .byte $00, $00

;; GET and PUT: where the record's next byte is in the FIELD buffer.
FLDPTR:
    .byte $00, $00

;; GET and PUT: where the record's next byte is in the sector buffer.
SECPTR:
    .byte $00, $00

;; GET and PUT: nonzero for PUT, zero for GET.
PUTFLG:
    .byte $00

;; Finishes start-up: clears every file's data block and runs the program named on the command line, if any.
;;
;; INIFIL clears each data block's mode and closes the files. The zero before the program's text is set; TEMP8
;; points at the command line's file name, after a quote that INIT put there, or at the zero in DSEGZ.
;;
;; It ends at LRUN, with HL at the name, or at READY.
;;
;; In:    TEMP8 = the command line's file name, or a zero
INITSA:
    CALL INIFIL                     ; clear and close the data blocks
    LD HL,[TXTTAB]
    DEC HL
    LD [HL],$00                     ; the zero before the program
    LD HL,[TEMP8]
    LD A,[HL]
    OR A
    JP NZ,LRUN                      ; RUN "file
    JP READY

;; The start of file 0's data block, which goes on over INIT once BASIC has started.
FILDB0:
    .byte $00, $00

;; Starts BASIC: reads the command line, lays out memory and the file blocks, and prints the sign-on banner.
;;
;; CURLIN is $FFFE while starting up. LOAD makes it $FFFF, a direct line, when it opens the command line's file
;; (NOTINI, Disk1.asm), so that a Control-C while that program loads does not leave BASIC. The BIOS's jump table is found from the warm-start vector at $0001; BASIC calls its console
;; routines directly, through the CALL operands it patches here (NEWSTT_1, CSTSVC and CSTKVC for the status,
;; CONIVC for input, CONOVC for output, LISTVC for the printer). Before CP/M 2 (S_BDOSVER returns 0), random
;; files are read and written with the sequential functions.
;;
;; It ends at INITSA.
;;
;; Errors: Syntax error for an unknown switch, Illegal function call (FCERR) for /F: above 15, Out of memory
;;   (OMERR) if the blocks or the stack do not fit
INIT:
    LD HL,$603F                     ; a stack above the image, until memory is laid out
    LD SP,HL
    XOR A
    LD [PROFLG],A                   ; not protected
    LD [TOPMEM],HL
    LD SP,HL
    LD HL,KBUF-1
    LD [HL],':'                     ; a colon before KBUF, so direct statements restart
    CALL STKINI                     ; A = 0
    LD [TTYPOS],A
    LD [SAVSTK],HL
    LD HL,[BIOSWB]                  ; the BIOS's warm-start entry, at its jump table's +3
    LD BC,$0004
    ADD HL,BC                       ; HL = the address in JP CONST
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [CSTKVC],HL                  ; the console status calls
    LD [CSTSVC],HL
    LD [NEWSTT_1],HL
    EX DE,HL
    INC HL
    INC HL                          ; JP CONIN
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [CONIVC],HL                  ; the console input call
    EX DE,HL
    INC HL
    INC HL                          ; JP CONOUT
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [CONOVC],HL                  ; the console output call
    EX DE,HL
    INC HL
    INC HL                          ; JP LIST
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [LISTVC],HL                  ; the printer call
    LD C,S_BDOSVER
    CALL CPMENT                     ; BDOS: the version
    LD [CPMVRN],A
    OR A
    LD HL,(F_WRITE << 8) | F_READ   ; CP/M 1: sequential records
    JP Z,CPMVR1
    LD HL,(F_WRITERAND << 8) | F_READRAND ; CP/M 2: random records
CPMVR1:
    LD [CPMREA],HL                  ; the read function, then the write function (CPMWRI)
    LD HL,$FFFE
    LD [CURLIN],HL                  ; starting up
    XOR A
    LD [CNTOFL],A
    LD [ENDBUF],A
    LD [CHNFLG],A                   ; no CHAIN
    LD [MRGFLG],A                   ; no CHAIN MERGE
    LD [ERRFLG],A                   ; no EDIT after an error
    LD HL,$0000
    LD [LPTPOS],HL
    LD HL,DATPSC
    LD [MAXREC],HL                  ; the largest record: 128 bytes
    LD HL,TEMPST
    LD [TEMPPT],HL                  ; no string temporaries
    LD HL,PRMSTK
    LD [PRMPRV],HL                  ; PRMPRV = PRMSTK: no parameter blocks
    LD HL,[CPMMEM]                  ; the BDOS's address: the top of the memory programs may use
    LD [MEMSIZ],HL
    LD A,$03
    LD [MAXFIL],A                   ; 3 files
    LD HL,DSEGZ
    LD [TEMP8],HL                   ; no file to run
    LD A,[CMDDON]
    OR A
    JP NZ,DONCMD                    ; started again: the command line is gone
    INC A
    LD [CMDDON],A
    LD HL,TBUFF
    LD A,[HL]                       ; the command line's length
    OR A
    LD [TEMP8],HL
    JP Z,DONCMD                     ; none
    LD B,[HL]
    INC HL
TBFLP:
    LD A,[HL]                       ; move the line down over its length
    DEC HL
    LD [HL],A
    INC HL
    INC HL
    DEC B
    JP NZ,TBFLP
    DEC HL
    LD [HL],$00                     ; and end it, for CHRGTR
    LD [TEMP8],HL                   ; no file yet: this zero
    LD HL,TBUFF-1
    CALL CHRGTR                     ; the first character, past spaces
    OR A
    JP Z,DONCMD                     ; only spaces
    CP '/'
    JP Z,FNDSLH                     ; a switch, no file
    DEC HL
    LD [HL],'"'                     ; a quote before the name, for RUN
    LD [TEMP8],HL
    INC HL
ISSLH:
    CP '/'
    JP Z,FNDSLH
    CALL CHRGTR                     ; through the file name
    OR A
    JP NZ,ISSLH
    JP DONCMD
FNDSLH:
    LD [HL],$00                     ; end the name at the slash
    CALL CHRGTR
SCANS1:
    CALL MAKUPL                     ; the switch in capitals
    CP 'S'
    JP Z,WASS
    CP 'M'
    PUSH AF                         ; zero for /M:
    JP Z,WASMF
    CP 'F'
    JP NZ,SNERR
WASMF:
    CALL CHRGTR
    CALL SYNCHR
    .byte ':'
    CALL CNSGET                     ; DE = the number
    POP AF
    JP Z,WASM
    LD A,D                          ; /F:
    OR A
    JP NZ,FCERR
    LD A,E
    CP 16
    JP NC,FCERR                     ; at most 15 files
    LD [MAXFIL],A
    JP FOK
WASM:
    EX DE,HL
    LD [MEMSIZ],HL                  ; the top of memory to use
    EX DE,HL
FOK:
    DEC HL
    CALL CHRGTR
    JP Z,DONCMD                     ; the end of the line
    CALL SYNCHR
    .byte '/'
    JP SCANS1                       ; the next switch
WASS:
    CALL CHRGTR
    CALL SYNCHR
    .byte ':'
    CALL CNSGET                     ; DE = the record size
    EX DE,HL
    LD [MAXREC],HL                  ; the largest record
    EX DE,HL
    JP FOK

;; A zero for TEMP8 to point at when there is no file to run.
DSEGZ:
    .byte $00

;; Nonzero once INIT has read the command line, so that starting again does not read what is left of it.
CMDDON:
    .byte $00

;; Lays out memory once the command line is read: the file data blocks, the program, strings and the stack.
;;
;; The top byte of memory is left unused, since VAL puts a zero after its string. The blocks are laid from
;; FILDB0 up: file 0's FD_RLEN bytes, then FD_FIELD bytes and the record size for each of files 1 to MAXFIL. The
;; stack takes an eighth of what is left, but no more than 512 bytes (SMLSTK), at the top, with string space
;; below it down to MEMSIZ. REASON checks MEMSIZ against FRETOP. The free bytes are MEMSIZ - TXTTAB - 2.
;;
;; It sets TXTTAB, MEMSIZ, TOPMEM, FRETOP and SP, and ends at INITSA.
;;
;; In:    MEMSIZ = the top of memory, MAXFIL = the files (MAXFIL), MAXREC = the largest record
;; Errors: Out of memory (OMERR)
DONCMD:
    DEC HL                          ; no effect: HL is loaded next
    LD HL,[MEMSIZ]
    DEC HL                          ; leave the top byte unused
    LD [MEMSIZ],HL
    DEC HL                          ; the stack's top
    PUSH HL
    LD A,[MAXFIL]
    LD HL,FILDB0
    LD [FILPT0],HL                  ; file 0's block
    LD DE,FILPTR
    LD [MAXFIL],A
    INC A                           ; files 0 to MAXFIL
    LD BC,FD_RLEN                   ; file 0's block is the shortest
DONCMD_1:
    EX DE,HL
    LD [HL],E                       ; the block's address into FILPTR
    INC HL
    LD [HL],D
    INC HL
    EX DE,HL
    ADD HL,BC                       ; past the block
    PUSH HL
    LD HL,[MAXREC]
    LD BC,FD_FIELD
    ADD HL,BC
    LD B,H                          ; the rest: a FIELD buffer each
    LD C,L
    POP HL
    DEC A
    JP NZ,DONCMD_1
    INC HL
    LD [TXTTAB],HL                  ; the program after the blocks
    LD [SAVSTK],HL
    POP DE                          ; the stack's top
    LD A,E
    SUB L
    LD L,A
    LD A,D
    SBC A,H
    LD H,A                          ; HL = the memory left
    JP C,OMERR                      ; none: OMERR
    LD B,$03
DONCMD_2:
    OR A
    LD A,H
    RRA
    LD H,A
    LD A,L
    RRA
    LD L,A
    DEC B
    JP NZ,DONCMD_2                  ; HL = an eighth of it
    LD A,H
    CP $02
    JP C,SMLSTK                     ; under 512 bytes
    LD HL,$0200                     ; at most 512
SMLSTK:
    LD A,E
    SUB L
    LD L,A
    LD A,D
    SBC A,H
    LD H,A                          ; HL = the stack's top less its size
    JP C,OMERR
    LD [MEMSIZ],HL                  ; strings below the stack
    EX DE,HL
    LD [TOPMEM],HL
    LD [FRETOP],HL
    LD SP,HL
    LD [SAVSTK],HL
    LD HL,[TXTTAB]
    EX DE,HL
    CALL REASON
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    DEC HL
    DEC HL                          ; HL = the bytes free
    PUSH HL
    LD HL,HEDING
    CALL STROUT                     ; the banner
    POP HL
    CALL LINPRT
    LD HL,BYTFRE
    CALL STROUT
    LD HL,STROUT
    LD [REPCAL],HL                  ; READY prints "Ok" from now on
    CALL CRDO
    LD HL,READYR                    ; unused: INITSA loads HL itself
    JP INITSA

; A message nothing prints, perhaps for an OEM's or owner's name to be patched in.
    .byte $0D, $0A, $0A, "Owned by Microsoft", $0D, $0A, 0

;; The message after the free bytes count.
BYTFRE:
    .byte " Bytes free", 0

;; The sign-on banner.
HEDING:
    .byte "BASIC-80 Rev. 5.21", $0D, $0A
    .byte "[CP/M Version]", $0D, $0A
    .byte "Copyright 1977-1981 (C) by Microsoft", $0D, $0A
    .byte "Created: 28-Jul-81", $0D, $0A, 0

; The rest of the image's last record.
    .byte $00, $00, $00, $00, $00, $00, $00
