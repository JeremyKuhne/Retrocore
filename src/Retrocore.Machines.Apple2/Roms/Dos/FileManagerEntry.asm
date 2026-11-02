;; DOS 3.3 AND 3.2 FILE MANAGER: ENTRY AND DISPATCH (FDOSENT)
;;
;; The door into the file manager, the layer of DOS that keeps files on a disk: the VTOC, the catalog and
;; each file's track/sector list (docs/Dos.md). Both DOS's own commands (through DOSGO) and other programs
;; (through the JMP at $03D6) come in at USERENT or DOSENT, which pick the routine for the request from
;; CMDVT. Where DOS runs, the module occupies $AA4F-$AB21.
;;
;; A request is described by the file manager parameter list, CCB at $B5BB, whose address a program gets by
;; calling $03DC (CCBLDR): Y = low byte, A = high byte. Its fields, defined in FileManagerData.asm, are:
;;
;; - +$00 CCBREQ, the opcode: 1 OPEN, 2 CLOSE, 3 READ, 4 WRITE, 5 DELETE, 6 CATALOG, 7 LOCK, 8 UNLOCK,
;;   9 RENAME, 10 POSITION, 11 INIT, 12 VERIFY (the CRQ... constants).
;; - +$01 CCBRQM, for READ and WRITE the subcode: 1 one byte, 2 a range of bytes, 3 and 4 the same after
;;   positioning (CRM...). For INIT it is CCBBSA, the page DOS's image starts at.
;; - +$02-$09 the request's arguments, under several names: record length (CCBRLN) or new name (CCBFN2) or
;;   record number (CCBRRN); byte offset (CCBBYT); volume (CCBVOL), drive (CCBDRV), slot (CCBSLT); range
;;   length (CCBBLN); file type (CCBFUC); file name address (CCBFN1), range address (CCBBBA) or data byte
;;   (CCBDAT).
;; - +$0A CCBSTA, the result: 0, or an error code CREFUN..CREFLK (1 language not available, 2 bad opcode,
;;   3 bad subcode, 4 write protected, 5 end of data, 6 file not found, 7 volume mismatch, 8 I/O error,
;;   9 disk full, 10 file locked). The carry flag is set on return when it is an error.
;; - +$0C-$11 the addresses of the open file's three buffers: its 45-byte work area (CCBFCB), its
;;   track/sector list sector (CCBDBP) and its data sector (CCBSBP). DOS keeps one set of these per file in
;;   each of its file buffers.
;;
;; The file manager's state for a file lives in the work area FCB between calls: CLCFCB copies it in at entry
;; and RTNFCB copies it back on the way out (FileDeleteCatalog.asm). The routines themselves are in
;; FileOpenCloseReadWrite.asm, FileDeleteCatalog.asm and FileManagerIo.asm; the exits GOODIO and ERROR1..
;; ERRR10 are in FileLocateSector.asm.
;;
;; Apple's module begins with variables of the command interpreter, not the file manager; they sit here only
;; because the module does. Beneath Apple DOS chapter 8 lists their uses.

; The command interpreter's variables.

;; Address of the DOS file buffer of the file a command is working on.
CFTABA:
    LEFTOVER $00, $2D, $2D
    LEFTOVER $00, $18, $18
;; DOS's input state: 0 normally, nonzero while DOS supplies input itself, as 1 while READ takes it from a
;; file and $C0 while FP loads the RAM Applesoft.
ISTATE:
    .byte 0
;; Which state DOS's output hook, CSW, is in; selects the routine in OUTSVT for the next character.
OSTATE:
    .byte 0
;; The output hook (CSW) DOS took over: where characters go once DOS has looked at them.
SVOUTS:
    LEFTOVER $00, $F0, $F0
    LEFTOVER $00, $FD, $FD
;; The input hook (KSW) DOS took over, likewise. SVREGS copies SVOUTS and SVINS back into CSW and KSW.
SVINS:
    LEFTOVER $00, $1B, $1B
    LEFTOVER $00, $FD, $FD
;; The number of file buffers DOS has, as MAXFILES set it.
CNFTBS:
    LEFTOVER $00, $03, $03
;; A default of 3 file buffers that nothing reads; DFNFTS is the one DOS uses.
DFNFTB:
    .byte 3
;; The stack pointer when DOS's hooks were entered, as SVREGS computed it.
SVSTK:
    LEFTOVER $00, $FB, $FB
;; X when DOS's hooks were entered.
SVX:
    LEFTOVER $00, $0D, $0A
;; Y when DOS's hooks were entered.
SVY:
    LEFTOVER $00, $28, $28
;; A when DOS's hooks were entered: the character being read or written.
SVA:
    LEFTOVER $00, $8D, $8D
;; Index into the input line while a command is scanned.
LBUFD:
    LEFTOVER $00, $0D, $0A
;; The MON flags: which of commands, input and output DOS echoes to the screen.
MONMOD:
    .byte 0
MC = $40                            ;; MONMOD bit: echo commands (MON C)
;; The command being carried out, as its number times 2 (its offset in CMDSTB and CMDETB). It starts at 0,
;; which DOS's initialization takes to mean DOS has just been loaded. USERENT sets it too, to 0 (INIT) or 2
;; (LOAD), since DOPEN creates missing files only for commands whose CMDSTB entry allows it.
CMDNO:
    .byte $00
;; Where LOAD and BLOAD read each two-byte field at the start of a file, its address or length.
SVBL:
    LEFTOVER $00, $85, $00
    LEFTOVER $00, $03, $00
;; A command to carry out after the language changes (a CMDNO), or 0.
SVCMD:
    .byte 0
;; Scratch for the command interpreter.
TEMP1A:
    LEFTOVER $00, $0B, $0B
;; Scratch for the command scanner.
TEMP2A:
    LEFTOVER $00, $01, $00
;; Which keywords the command line gave, one bit each.
INOPTS:
    LEFTOVER $00, $20, $00
;; The keyword values, from the command line or defaulted, two bytes each: V, D, S, L, R, B and A. The
;; command scanner stores each into CUROPT indexed by keyword.
CUROPT:
;; The V keyword: volume number.
CV:
    .word 0
;; The D keyword: drive number.
CD:
    LEFTOVER $00, $01, $01
    LEFTOVER $00, $00, $00
;; The S keyword: slot number.
CS:
    LEFTOVER $00, $06, $06
    LEFTOVER $00, $00, $00
;; The L keyword: length, or record length for OPEN.
CL:
    .word 1
;; The R keyword: record number.
CR:
    .word 0
;; The B keyword: byte offset.
CB:
    .word 0
;; The A keyword: address.
CA:
    LEFTOVER $00, $00, $00
    LEFTOVER $00, $03, $00
;; The letters C, I and O given with MON or NOMON, one bit each.
IMBITS:
    .byte 0
;; The file name from the command line, 30 characters padded with spaces (high bits set).
;;
;; When DOS starts for the first time it runs the program named here (DosInit turns CMDNO 0 into a RUN), so
;; the name INIT leaves here as it writes DOS to a disk becomes that disk's greeting program. The master's
;; is HELLO.
FNAME1:
    .hiascii "HELLO                         "
;; The second file name, for RENAME.
FNAME2:
    .res 30,$A0
;; The number of file buffers DOS starts with: MAXFILES 3.
DFNFTS:
    .byte 3
;; The character that starts a DOS command in output: Control-D, high bit set.
CCHAR:
    .byte $84
;; Nonzero while an EXEC file is supplying input.
ESTATE:
    .byte 0
;; Address of the DOS file buffer of the EXEC file.
EFTABA:
    .byte 0, 0
;; Which BASIC is active: 0 Integer BASIC, $40 Applesoft in ROM, $80 Applesoft loaded into RAM.
ASIBSW:
    .byte 0
;; Nonzero while a RUN is waiting to be finished the next time output reaches DOS's hook (COS0 checks it).
RSTATE:
    .byte 0
;; The file name FP loads when the machine has no Applesoft in ROM: "APPLESOFT" with the high bits set.
FASB:
    .byte $C1, $D0, $D0, $CC
    .byte $C5, $D3, $CF, $C6
    .byte $D4
FASBL = *-FASB                      ;; the name's length, 9

; The file manager starts here. SAT2 to EAT2 is a table of addresses the relocator adjusts as words, when
; the master's DOS is moved to the top of memory (Relocator.asm, ADRTAB).
SAT2:
;; Address of the RWTS parameter list, IOB, which DCBIO fills in for every disk access.
AIOB:
    .word IOB
;; Address of the buffer holding the VTOC (volume table of contents) of the disk in use.
AVTOC:
    .word VTOC
;; Address of the buffer holding the catalog sector in use.
AVOLDR:
    .word VOLDIR
;; One past the last byte of DOS, $C000 where DOS runs; nothing in DOS reads it.
AEND:
    .word ENDOFDOS

;; The opcode table: for each value of CCBREQ, 0 to 13, the address less 1 of its routine, for DOSENT to
;; reach with an RTS.
;;
;; Opcode 0 does nothing but return. DOSENT rejects opcodes from CRQMAX (13) up, so the last entry is never
;; used.
CMDVT:
    .word GOODIO-1                  ; 0, no operation
    .word FOPEN-1                   ; 1, OPEN
    .word FCLOSE-1                  ; 2, CLOSE
    .word FREAD-1                   ; 3, READ
    .word FWRITE-1                  ; 4, WRITE
    .word FDEL-1                    ; 5, DELETE
    .word RDIR-1                    ; 6, CATALOG
    .word FLOCK-1                   ; 7, LOCK
    .word FUNLCK-1                  ; 8, UNLOCK
    .word FRNME-1                   ; 9, RENAME
    .word FPOSTN-1                  ; 10, POSITION
    .word FFMT-1                    ; 11, INIT
    .word FVAR-1                    ; 12, VERIFY
    .word GOODIO-1                  ; 13, never reached
;; The READ subcode table: for each value of CCBRQM, 0 to 5, the address less 1 of its routine. FREAD
;; rejects subcodes from CRMMAX (5) up, so the last entry is never used.
RVT:
    .word GOODIO-1                  ; 0, no operation
    .word RNXBYT-1                  ; 1, the next byte
    .word RNXBLK-1                  ; 2, the next range of bytes
    .word RSPBYT-1                  ; 3, position, then one byte
    .word RSPBLK-1                  ; 4, position, then a range
    .word GOODIO-1                  ; 5, never reached
;; The WRITE subcode table, laid out as RVT.
WVT:
    .word GOODIO-1                  ; 0, no operation
    .word WNXBYT-1                  ; 1, the next byte
    .word WNXBLK-1                  ; 2, the next range of bytes
    .word WSPBYT-1                  ; 3, position, then one byte
    .word WSPBLK-1                  ; 4, position, then a range
    .word GOODIO-1                  ; 5, never reached

; The end of the address table, and the start of a stretch of code (SC2 to EC2, the end of
; FileLocateSector.asm) whose instructions the relocator adjusts (Relocator.asm, CDETAB).
EAT2:
SC2:
;; The file manager's entry for programs, reached through the JMP at $03D6; carries out the request in CCB.
;;
;; X says whether a missing file may be created: USERENT sets CMDNO as if the command were INIT (X = 0,
;; create) or LOAD (otherwise, don't), which is what DOPEN looks at. A created file is still reported with
;; code 6, file not found, but with the carry clear. The parameter list is always CCB; A and Y are not used.
;; In:    X = 0 to allow creating a file, CCB = the request
;; Out:   CCBSTA = the result, and the fields each request returns
;; Errors: carry = set when CCBSTA holds an error code
;; Uses:  A, X, Y, CMDNO
;; Entry: DOSENT = DOS's own entry, keeping CMDNO, the command being carried out
USERENT:
    cpx #0
; NOT is a label with no use.
NOT:
    beq USRCR
    ldx #2                          ; LOAD's CMDNO: no create
USRCR:
    stx CMDNO
DOSENT:
    tsx                             ; remember the stack: every exit (RETURN) resets S to this and
    stx a:ENTSTK                    ; returns to the caller, however deep it has gone
    jsr CLCFCB                      ; bring in the file's work area, and clear CCBSTA
    lda a:CCBREQ
    cmp #CRQMAX
    bcs ERR2
    asl a
    tax
    lda CMDVT+1,x                   ; push the routine's address less 1, high byte first, and "return"
    pha                             ; to it
    lda CMDVT,x
    pha
DENRTS:
    rts
;; Returns error code 2, bad opcode.
ERR2:
    jmp ERROR2
