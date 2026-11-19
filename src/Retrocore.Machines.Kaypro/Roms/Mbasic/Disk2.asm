;; MBASIC 5.21: DISK FILES, PART 2 (THE CP/M FILE LAYER)
;;
;; The half of BASIC's disk I/O that talks to CP/M: the file statements and functions that name files
;; (OPEN, NAME, KILL, FILES, SYSTEM, RESET, PUT, GET, LOC, LOF), the byte-level reading and writing of a file's
;; buffer, and the calls to CP/M's BDOS at $0005 underneath them. Part 1 (Disk1.asm) holds the statements built on
;; top: LOAD, SAVE, MERGE, CLOSE, FIELD, LSET and RSET, INPUT# and EOF.
;;
;; Each file number has a file data block (FDB, laid out by the FD_ constants in Equates.asm) that holds its mode, CP/M's
;; file control block, a 128-byte (DATPSC) record buffer and, for a random file, the record length and the record
;; buffer FIELD's variables point into. PTRFIL points at the FDB of the file being printed to or read from.
;;
;; - NAMFIL parses a file name string ("B:NAME.EXT") into FILNAM, an FCB that OPEN, NAME, KILL and FILES pass to
;;   the BDOS. PRGFIL, behind OPEN, LOAD, SAVE, RUN and MERGE, opens a file into its FDB and points PTRFIL at it.
;; - FILOUT (from OUTDO) and FILOU3 write a byte to PTRFIL's file: SEQOUT into a sequential file's buffer, flushed a
;;   record at a time, or RNDOUT into a random file's record buffer. INDSKC and INDSKB read one back: from the
;;   buffer, refilled by REDREC, or from a random file's record buffer by RNDIN. INDSKC stops at a Control-Z.
;; - PUT and GET move a random file's record buffer to or from the file, split across 128-byte CP/M records by
;;   PHYGET and PHYPUT, which position the file with RNDREC.
;; - CPMRW makes every read and write call, through the function numbers INIT stores in CPMREA and CPMWRI: random
;;   read and write (33, 34) on CP/M 2, which has them, and sequential (20, 21) on CP/M 1.4. Either way, it
;;   advances the FCB's random record as a sequential call would, and maps a random write's errors to the
;;   sequential ones. RNDREC moves CP/M 1.4 between extents itself.
;; - PROSAV saves a program protected (SAVE "NAME",P), encoding it with PROENC; LOAD decodes it with PROLOD, and
;;   PRODIR and PROCHK refuse to LIST or change it.
;;
;; GW-BASIC's source names this file DCPM.MAC (DSKCOM.ASM calls its fast loader "FSTLOD IN DCPM.MAC") but does not
;; include it, since GW-BASIC replaced it with MS-DOS device drivers; DSKCOM.ASM's references to INDSKC, PRGFIL and
;; CLSFIL, and GWDATA.ASM's FILNAM, FILNA2, CPMVRN, CPMREA and CPMWRI, give the names that survive. The rest are
;; descriptive. Runs at $5640-$5D6E.

;; Returns LOC(n): the current record of random file n, or the records read or written so far of a sequential one.
;; In:    FACLO = the file number in the FAC
;; Out:   FACLO = the record number as an integer in the FAC
;; Errors: DERBFN if the file is not open
FN_LOC:
    CALL FILFRM                     ; BC = the file's FDB, A = its mode
    JP Z,DERBFN                     ; not open
    CP MD_RND
    LD HL,FD_REC+1                  ; sequential: the records so far
    JP NZ,FN_LOC_1
    LD HL,FD_LREC+1                 ; random: the current record
FN_LOC_1:
    ADD HL,BC
    LD A,[HL]                       ; A = the high byte
    DEC HL
    LD L,[HL]                       ; L = the low byte
    JP GIVINT                       ; return A:L as an integer

;; Returns LOF(n): the number of 128-byte records in file n's current extent, from its FCB's record count.
;; In:    FACLO = the file number in the FAC
;; Out:   FACLO = the record count as an integer in the FAC
;; Errors: DERBFN if the file is not open
FN_LOF:
    CALL FILFRM                     ; BC = the file's FDB
    JP Z,DERBFN
    LD HL,FD_RC
    ADD HL,BC
    LD A,[HL]
    JP SNGFLT                       ; return A as an integer

;; Writes the character OUTDO is printing to the current file instead of the screen.
;;
;; OUTDO jumps here, rather than calling, when PTRFIL is set, with the character and its HL still pushed.
;; In:    PTRFIL = the file's FDB, the stack = the HL and AF that OUTDO pushed
;; See:   <FILOU3>
FILOUT:
    POP HL
    POP AF

;; Writes a byte to the current file, the one PTRFIL points at.
;;
;; A random file's byte goes into its record buffer (RNDOUT), a sequential output file's into its buffer (SEQOUT).
;; A byte written to a file open for input is dropped.
;; In:    A = the byte, PTRFIL = the file's FDB
;; Errors: DERFOV when a random file's record buffer is full, and the errors of writing the buffer out
;; Keeps: AF, BC, DE, HL
FILOU3:
    PUSH HL
    PUSH AF
    LD HL,[PTRFIL]                  ; HL = PTRFIL, the FDB
    LD A,[HL]                       ; A = the mode
    CP MD_SQI
    JP Z,POPAHT                     ; an input file: restore AF and HL, and return
    CP MD_RND
    JP Z,RNDOUT
    POP AF

;; Writes a byte into a sequential output file's buffer, first writing the buffer out to the file if it is full.
;;
;; It also keeps the file's column in FD_BREM, as PRINT's commas and TAB need it: a return sets it to 0, and each
;; character from a space up adds 1.
;; In:    A = the byte, HL = the file's FDB, the stack = the HL to return with
;; Out:   HL = the word popped from the stack
;; Errors: those of writing the buffer out (DERDFL when the disk is full, DERTMF, DERDIO)
;; Keeps: AF, BC, DE
SEQOUT:
    PUSH DE
    PUSH BC
    LD B,H                          ; BC = the FDB
    LD C,L
    PUSH AF
    LD DE,FD_BCNT
    ADD HL,DE
    LD A,[HL]                       ; A = the bytes in the buffer
    CP DATPSC
    PUSH HL
    CALL Z,OUTSEC                   ; full: write it to the file and empty it
    POP HL
    INC [HL]                        ; one more byte in the buffer
    LD C,[HL]                       ; BC = its position, from 1
    LD B,$00
    INC HL                          ; HL = FD_BREM, the column
    POP AF
    PUSH AF
    LD D,[HL]                       ; D = the column
    CP $0D
    LD [HL],B                       ; a return: back to column 0
    JP Z,SEQOUT_1
    ADD A,$E0                       ; carry = a printing character, from a space up
    LD A,D
    ADC A,B                         ; the column plus 1 for a printing character
    LD [HL],A
SEQOUT_1:
    ADD HL,BC                       ; HL = the byte's place in FD_BUF
    POP AF
    POP BC
    POP DE
    LD [HL],A
    POP HL
    RET

;; Positions a random file at a 128-byte record and reads it into the buffer, or writes the buffer to it.
;;
;; PHYGET and PHYPUT jump here; RNDWRT says which (nonzero to write). CP/M 2 is positioned by the FCB's random
;; record field. CP/M 1.4 has no random calls, so the record's extent is opened (or made) if it is not the FCB's
;; current one, and the current record set within it, for the sequential call CPMRW makes.
;;
;; Writing the last record of an extent (current record 127), the buffer is copied to DIRTMP before the write and
;; back after it. A write resets PTRFIL and the printer flag through FINPRT before returning.
;; In:    HL = FD_REC+1 in the file's FDB, DE = the record + 1, the stack = a word to discard, the FDB, then the
;;          return address
;; Errors: DERTMF if CP/M 1.4 cannot make the extent, and the errors of writing the buffer
RNDREC:
    DEC DE                          ; DE = the record, from 0
    DEC HL
    LD [HL],E                       ; the records so far = this one; REDREC counts it
    INC HL
    LD [HL],D
    INC HL
    LD [HL],DATPSC                  ; FD_BCNT: a full buffer
    INC HL
    LD [HL],DATPSC                  ; FD_BREM
    POP HL
    EX [SP],HL                      ; HL = the FDB
    LD B,H
    LD C,L
    PUSH HL
    LD A,[CPMVRN]                   ; nonzero on CP/M 2
    OR A
    JP Z,RNDREC_1
    LD HL,FD_RR                     ; CP/M 2: the FCB's random record = DE
    ADD HL,BC
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    LD [HL],$00
    JP RNDREC_4
RNDREC_1:
    LD HL,FD_EXT                    ; CP/M 1.4: the record's extent is the record / 128
    ADD HL,BC
    LD A,E
    RLA                             ; carry = bit 7 of the record
    LD A,D
    RLA                             ; A = the record's extent
    LD D,[HL]                       ; D = the FCB's extent
    CP D
    JP Z,RNDREC_3                   ; already in that extent
    PUSH DE
    PUSH AF
    PUSH HL
    PUSH BC
    LD DE,DIRTMP
    LD C,F_DMAOFF
    CALL CPMENT
    POP DE
    PUSH DE
    INC DE                          ; DE = the FCB
    LD C,F_CLOSE                    ; close the current extent
    CALL CPMENT
    POP DE
    POP HL
    POP AF
    LD [HL],A                       ; the FCB's extent = the record's
    PUSH DE
    INC DE
    LD C,F_OPEN
    PUSH DE
    CALL CPMENT
    POP DE
    INC A
    JP NZ,RNDREC_2                  ; opened
    LD C,F_MAKE                     ; a new extent
    CALL CPMENT
    INC A
    JP Z,DERTMF                     ; the directory is full
RNDREC_2:
    POP BC
    POP DE
RNDREC_3:
    LD HL,FD_CR                     ; the FCB's current record = the record within its extent
    ADD HL,BC
    LD A,E
    AND $7F
    LD [HL],A
RNDREC_4:
    POP HL                          ; HL = the FDB
    LD A,[RNDWRT]
    OR A
    JP NZ,RNDREC_5
    CALL REDREC                     ; read
    POP HL
    RET
RNDREC_5:
    LD HL,FD_CR                     ; write
    ADD HL,BC
    LD A,[HL]
    CP $7F                          ; zero = the extent's last record
    PUSH AF
    LD DE,DIRTMP
    LD HL,FD_BUF
    ADD HL,BC
    PUSH DE
    PUSH HL
    CALL Z,MOV128                   ; keep a copy of the buffer at DIRTMP
    CALL OUTSEC                     ; write the buffer
    POP DE
    POP HL
    POP AF
    CALL Z,MOV128                   ; and copy it back
    POP HL
    JP FINPRT                       ; clear PTRFIL, and return

;; Copies 128 bytes from HL to DE.
;; In:    HL = the source, DE = the destination
;; Out:   HL, DE = past the bytes, A = the last byte
;; Keeps: BC
MOV128:
    PUSH BC
    LD B,DATPSC
MOV128_1:
    LD A,[HL]
    INC HL
    LD [DE],A
    INC DE
    DEC B
    JP NZ,MOV128_1
    POP BC
    RET

;; Reads the next byte of the current file, refilling the buffer from the file when it is empty.
;;
;; A random file's byte comes from its record buffer (RNDIN). LOAD reads a binary program with it; INDSKC is the
;; same for text, stopping at a Control-Z.
;; In:    PTRFIL = the file's FDB
;; Out:   A = the byte, carry = set at the end of the file (A = Control-Z)
;; Errors: DERFOV reading past the end of a random file's record
;; Keeps: BC, DE, HL
INDSKB:
    PUSH BC
    PUSH HL
INDSKB_1:
    LD HL,[PTRFIL]                  ; HL = PTRFIL, the FDB
    LD A,[HL]
    CP MD_RND
    JP Z,RNDIN
    LD BC,FD_BREM
    ADD HL,BC
    LD A,[HL]                       ; A = the bytes left in the buffer
    OR A
    JP Z,INDSKB_2                   ; none
    DEC HL
    LD A,[HL]                       ; A = the bytes in the buffer
    INC HL
    DEC [HL]                        ; one fewer left
    SUB [HL]                        ; A = the next byte's position, from 1
    LD C,A
    ADD HL,BC
    LD A,[HL]                       ; A = the byte
    OR A                            ; carry clear
    POP HL
    POP BC
    RET
INDSKB_2:
    DEC HL
    LD A,[HL]                       ; FD_BCNT: 0 once the file has ended
    OR A
    JP Z,INDSKB_3
    CALL REDPTR                     ; read the next record
    JP NZ,INDSKB_1                  ; and take its first byte
INDSKB_3:
    SCF                             ; the end of the file
    POP HL
    POP BC
    LD A,$1A                        ; Control-Z
    RET

;; Reads the next record of the current file into its buffer.
;; In:    PTRFIL = the file's FDB
;; See:   <REDREC>
REDPTR:
    LD HL,[PTRFIL]

;; Reads the next record of a file into its buffer, counting it in FD_REC.
;;
;; The buffer is cleared first. A read that fails, which is how CP/M reports the end of the file, leaves the
;; buffer empty (FD_BCNT and FD_BREM 0).
;; In:    HL = the file's FDB
;; Out:   A = the bytes read (DATPSC, or 0 at the end of the file), zero = set at the end of the file
;; Keeps: DE
REDREC:
    PUSH DE
    LD D,H
    LD E,L
    INC DE                          ; DE = the FCB
    LD BC,FD_REC
    ADD HL,BC
    LD C,[HL]                       ; count the record
    INC HL
    LD B,[HL]
    INC BC
    DEC HL
    LD [HL],C
    INC HL
    LD [HL],B
    INC HL
    INC HL
    PUSH HL                         ; FD_BREM
    LD C,DATPSC
REDREC_1:
    INC HL                          ; clear the buffer
    LD [HL],$00
    DEC C
    JP NZ,REDREC_1
    CALL SETDMA
    LD A,[CPMREA]                   ; F_READ or F_READRAND
    CALL CPMRW
    OR A
    LD A,$00                        ; failed: nothing read
    JP NZ,REDREC_2
    LD A,DATPSC
REDREC_2:
    POP HL
    LD [HL],A                       ; FD_BREM = FD_BCNT = the bytes read
    DEC HL
    LD [HL],A
    OR A
    POP DE
    RET

;; Points CP/M's DMA at a file's buffer.
;; In:    DE = the file's FCB (FD_FCB in its FDB)
;; Keeps: BC, DE, HL
SETDMA:
    PUSH BC
    PUSH DE
    PUSH HL
    LD HL,FD_BUF-FD_FCB
    ADD HL,DE
    EX DE,HL                        ; DE = FD_BUF
    LD C,F_DMAOFF
    CALL CPMENT
    POP HL
    POP DE
    POP BC
    RET

;; Reads the next character of the current file, ending the file at a Control-Z.
;;
;; A Control-Z empties the buffer for good, so every read after it ends the file too.
;; In:    PTRFIL = the file's FDB
;; Out:   A = the character, carry = set at the end of the file
;; Errors: DERFOV reading past the end of a random file's record
;; Keeps: BC, DE, HL
INDSKC:
    CALL INDSKB
    RET C
    CP $1A
    SCF
    CCF                             ; carry clear
    RET NZ                          ; not a Control-Z
    PUSH BC
    PUSH HL
    LD HL,[PTRFIL]
    LD BC,FD_BCNT
    ADD HL,BC
    LD [HL],$00                     ; FD_BCNT = FD_BREM = 0: ended
    INC HL
    LD [HL],$00
    SCF
    POP HL
    POP BC
    RET

;; Evaluates a file name string and parses it into FILNAM, an FCB for the BDOS: "D:NAME.EXT".
;;
;; The drive letter is optional (FILNAM's drive byte is 0 for the current drive), and so is the extension. The name
;; and the extension are padded with spaces to 8 and 3 characters; characters past the 11th are ignored. Letters
;; are not raised to capitals, except the drive's.
;; In:    HL = the text, at the file name's expression
;; Out:   HL = the text after it, FILNAM = the drive, name and extension, with the extent byte
;;          (FILNAM_EXTENT) 0, A = the string's length, carry = set if the name has a period
;; Errors: DERIFN for an empty string, a bad drive letter, a period with no name before it, or a period in the
;;          extension
NAMFIL:
    CALL FRMEVL                     ; evaluate the string
    PUSH HL
    CALL FRESTR                     ; HL = its descriptor
    LD A,[HL]                       ; A = its length
    OR A
    JP Z,DERIFN
    PUSH AF                         ; keep the length, with carry clear: no period yet
    INC HL
    LD E,[HL]
    INC HL
    LD H,[HL]
    LD L,E                          ; HL = the characters
    LD E,A                          ; E = the characters left
    CP $02
    JP C,NAMFIL_1                   ; too short for a drive
    LD C,[HL]                       ; C = the first character
    INC HL
    LD A,[HL]
    DEC E
    CP ':'
    JP Z,NAMFIL_2                   ; a drive letter in C
    DEC HL                          ; none: back to the first character
    INC E
NAMFIL_1:
    DEC HL
    INC E
    LD C,'@'                        ; the current drive, 0 after the subtraction
NAMFIL_2:
    DEC E
    JP Z,NAMERR                     ; nothing after the drive
    LD A,C
    AND $DF                         ; a capital letter
    SUB '@'                         ; A = the drive: 0 current, 1 for A: on
    JP C,NAMERR
    CP 27
    JP NC,NAMERR
    LD BC,FILNAM
    LD [BC],A                       ; FILNAM's drive
    INC BC
    LD D,11                         ; D = the places left in the name and extension
NAMFIL_3:
    INC HL
NAMFIL_4:
    DEC E
    JP M,NAMDOT_1                   ; the end of the string
    LD A,[HL]
    CP '.'
    JP NZ,NAMFIL_5
    CALL NAMDOT                     ; pad the name to the extension
    POP AF
    SCF                             ; carry = it has a period
    PUSH AF
    JP NAMFIL_3
NAMFIL_5:
    LD [BC],A
    INC BC
    INC HL
    DEC D
    JP NZ,NAMFIL_4
NAMFIL_6:
    XOR A
    LD [FILNAM_EXTENT],A            ; FILNAM's extent = 0
    POP AF                          ; A = the length, carry = a period
    POP HL
    RET

;; Pads a file name being parsed into FILNAM with spaces up to its extension, at a period.
;; In:    BC = the next place in FILNAM, D = the places left of 11
;; Out:   BC = FILNAM's extension, D = 3
;; Errors: DERIFN if no name came before the period, or the period is in the extension
NAMDOT:
    LD A,D
    CP 11
    JP Z,NAMERR                     ; no name
    CP $03
    JP C,NAMERR                     ; already in the extension
    RET Z                           ; at the extension
    LD A,' '
    LD [BC],A
    INC BC
    DEC D
    JP NAMDOT

NAMDOT_1:
    INC D
    DEC D
    JP Z,NAMFIL_6                   ; all 11 places filled
NAMDOT_2:
    LD A,' '                        ; pad the rest with spaces
    LD [BC],A
    INC BC
    DEC D
    JP NZ,NAMDOT_2
    JP NAMFIL_6
NAMERR:
    JP DERIFN

;; Runs NAME old AS new: renames a file, on the same drive.
;; In:    HL = the text after NAME
;; Out:   HL = the text after the statement
;; Errors: DERFNF if the old file does not exist, DERFAE if the new one does, FCERR for different drives, and
;;          NAMFIL's errors
ST_NAME:
    CALL NAMFIL                     ; the old name
    PUSH HL
    LD DE,DIRTMP
    LD C,F_DMAOFF
    CALL CPMENT
    LD DE,FILNAM
    LD C,F_OPEN                     ; does it exist?
    CALL CPMENT
    INC A
    JP Z,DERFNF
    LD HL,FILNA2                    ; move it to FILNA2, 16 bytes before FILNAM
    LD DE,FILNAM
    LD B,12
ST_NAME_1:
    LD A,[DE]
    LD [HL],A
    INC HL
    INC DE
    DEC B
    JP NZ,ST_NAME_1
    POP HL
    CALL SYNCHR                     ; "AS"
    .byte 'A'
    CALL SYNCHR
    .byte 'S'
    CALL NAMFIL                     ; the new name, in FILNAM
    PUSH HL
    LD A,[FILNAM]
    LD HL,FILNA2
    CP [HL]
    JP NZ,FCERR                     ; another drive
    LD DE,FILNAM
    LD C,F_OPEN                     ; does the new name exist?
    CALL CPMENT
    INC A
    JP NZ,DERFAE
    LD C,F_RENAME                   ; rename FILNA2 to FILNAM, 16 bytes on
    LD DE,FILNA2
    CALL CPMENT
    POP HL
    RET

;; Runs OPEN mode, [#]n, name [, record length]: opens a file for input ("I"), output ("O") or random access ("R").
;;
;; Only the mode string's first letter counts. It returns through FINPRT, leaving PTRFIL clear.
;; In:    HL = the text after OPEN
;; Out:   HL = the text after the statement
;; Errors: DERBFM for a bad mode, DERBFN for file number 0, and PRGFIL's errors
ST_OPEN:
    LD BC,FINPRT                    ; return through it, clearing PTRFIL
    PUSH BC
    CALL FRMEVL                     ; evaluate the mode
    PUSH HL
    CALL FRESTR
    LD A,[HL]
    OR A
    JP Z,DERBFM                     ; an empty mode
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]
    LD A,[BC]                       ; A = its first letter
    AND $DF                         ; a capital
    LD D,MD_SQO
    CP 'O'
    JP Z,ST_OPEN_1
    LD D,MD_SQI
    CP 'I'
    JP Z,ST_OPEN_1
    LD D,MD_RND
    CP 'R'
    JP NZ,DERBFM
ST_OPEN_1:
    POP HL
    CALL SYNCHR
    .byte ','
    PUSH DE                         ; D = the mode
    CP '#'
    CALL Z,CHRGTR                   ; skip an optional #
    CALL GETBYT                     ; E = the file number
    CALL SYNCHR
    .byte ','
    LD A,E
    OR A
    JP Z,DERBFN                     ; file 0 is BASIC's own
    POP DE

;; Opens a file into the FDB of a file number and points PTRFIL at it.
;;
;; Output (MD_SQO) deletes any file of the name and makes a new one. Input (MD_SQI) needs the file to exist, and
;; reads its first record. Random (MD_RND) makes the file if it does not exist, and takes the optional record
;; length after the name. File 0, which LOAD, SAVE, RUN and MERGE use (through PRGFL2 in Disk1.asm), gets the
;; extension BAS when the name has none and no period.
;; In:    A = the file number, D = the mode, HL = the text, at the file name
;; Out:   PTRFIL = the FDB, HL = the text after the name (and record length), from TEMP
;; Errors: DERFAO if the file number is already open, DERFNF if an input file does not exist, DERTMF if the
;;          directory is full, and NAMFIL's and RECLEN's errors
PRGFIL:
    LD E,A
    PUSH DE
    CALL FILIDX                     ; BC = the file number's FDB
    JP NZ,DERFAO                    ; already open
    POP DE
    PUSH BC
    PUSH DE
    CALL NAMFIL                     ; FILNAM = the name, carry = it has a period
    POP DE
    POP BC
    PUSH BC
    PUSH AF
    LD A,D
    CALL RECLEN                     ; a random file's record length
    POP AF
    LD [TEMP],HL                    ; keep the text pointer
    JP C,PRGFIL_1                   ; a period: keep the extension as given
    LD A,E
    OR A
    JP NZ,PRGFIL_1                  ; only file 0 gets BAS
    LD HL,FILNAM+9                  ; FILNAM's extension
    LD A,[HL]
    CP ' '
    JP NZ,PRGFIL_1
    LD [HL],'B'
    INC HL
    LD [HL],'A'
    INC HL
    LD [HL],'S'
PRGFIL_1:
    POP HL                          ; HL = the FDB
    LD A,D
    PUSH AF                         ; A = the mode
    LD [PTRFIL],HL
    PUSH HL
    INC HL                          ; copy FILNAM to the FDB's FCB
    LD DE,FILNAM
    LD C,12
PRGFIL_2:
    LD A,[DE]
    LD [HL],A
    INC DE
    INC HL
    DEC C
    JP NZ,PRGFIL_2
    XOR A
    LD [HL],A                       ; FD_EXT = 0
    LD DE,FD_CR-FD_EXT
    ADD HL,DE
    LD [HL],A                       ; FD_CR = 0
    POP DE
    PUSH DE
    INC DE                          ; DE = the FCB
    CALL SETDMA
    POP HL
    POP AF
    PUSH AF
    PUSH HL
    CP MD_SQO
    JP NZ,PRGFIL_4
    PUSH DE                         ; output: delete any old file
    LD C,F_DELETE
    CALL CPMENT
    POP DE
PRGFIL_3:
    LD C,F_MAKE
    CALL CPMENT
    INC A
    JP Z,DERTMF                     ; the directory is full
    JP PRGFIL_5
PRGFIL_4:
    LD C,F_OPEN
    CALL CPMENT
    INC A
    JP NZ,PRGFIL_5                  ; opened
    POP DE                          ; not found
    POP AF
    PUSH AF
    PUSH DE
    CP MD_RND
    JP NZ,DERFNF                    ; an input file must exist
    INC DE
    JP PRGFIL_3                     ; a random file is made
PRGFIL_5:
    POP DE                          ; DE = the FDB
    POP AF
    LD [DE],A                       ; FD_MODE: the file is open
    PUSH DE
    LD HL,FD_REC                    ; FD_REC, FD_BCNT and FD_BREM = 0
    ADD HL,DE
    XOR A
    LD [HL],A
    INC HL
    LD [HL],A
    INC HL
    LD [HL],A
    INC HL
    LD [HL],A
    POP HL
    LD A,[HL]
    CP MD_RND
    JP Z,PRGFIL_6
    CP MD_SQI
    JP NZ,GTMPRT                    ; output: done, HL = TEMP
    CALL REDPTR                     ; input: read the first record
    LD HL,[TEMP]
    RET
PRGFIL_6:
    LD BC,FD_BUF                    ; random: clear the buffer (B = 0)
    ADD HL,BC
    LD C,DATPSC
PRGFIL_7:
    LD [HL],B
    INC HL
    DEC C
    JP NZ,PRGFIL_7
    JP GTMPRT                       ; HL = TEMP

;; Runs SYSTEM: closes every file and returns to CP/M.
;; In:    HL = the text after SYSTEM, zero = set at the end of the statement
ST_SYSTEM:
    RET NZ                          ; anything after it is a syntax error
    CALL CLSALL                     ; close all files

;; Leaves BASIC for CP/M, through its warm start at $0000. A Control-C while INIT runs a program given on
;; MBASIC's command line leaves here too.
CPMEXT:
    JP CPMWRM

;; Runs RESET: closes every file and resets CP/M's disk system, so disks can be changed, keeping the current
;; drive.
;; In:    HL = the text after RESET, zero = set at the end of the statement
;; Out:   HL = the text
ST_RESET:
    RET NZ
    PUSH HL
    CALL CLSALL                     ; close all files
    LD C,DRV_GET
    CALL CPMENT
    PUSH AF                         ; A = the current drive
    LD C,DRV_ALLRESET
    CALL CPMENT
    POP AF
    LD E,A
    LD C,DRV_SET                    ; select it again
    CALL CPMENT
    POP HL
    RET

;; Runs KILL name: deletes a file.
;; In:    HL = the text after KILL
;; Out:   HL = the text after the statement
;; Errors: DERFNF if the file does not exist, and NAMFIL's errors
ST_KILL:
    CALL NAMFIL
    PUSH HL
    LD DE,DIRTMP
    LD C,F_DMAOFF
    CALL CPMENT
    LD DE,FILNAM
    PUSH DE
    LD C,F_OPEN                     ; does it exist?
    CALL CPMENT
    INC A
    POP DE
    PUSH DE
    PUSH AF                         ; zero = not found
    LD C,F_CLOSE
    JP Z,ST_KILL_1
    CALL CPMENT                     ; close it again
ST_KILL_1:
    POP AF
    POP DE
    JP Z,DERFNF
    LD C,F_DELETE
    CALL CPMENT
    POP HL
    RET

;; Runs FILES [name]: lists the directory entries matching a name, all of them without one.
;;
;; A * as the first character of the name or the extension matches anything there. Each entry is printed as NAME.EXT
;; in 12 columns and 2 spaces, as many to a line as the width allows.
;; In:    HL = the text after FILES, zero = set at the end of the statement
;; Out:   HL = the text after the statement
;; Errors: DERFNF if nothing matches, and NAMFIL's errors
ST_FILES:
    JP NZ,ST_FILES_1                ; a name given
    PUSH HL
    LD HL,FILNAM
    LD [HL],$00                     ; the current drive
    INC HL
    LD C,11
    CALL FILLQ                      ; ????????.???, leaving zero set
    POP HL
ST_FILES_1:
    CALL NZ,NAMFIL
    XOR A
    LD [FILNAM_EXTENT],A            ; FILNAM's extent = 0
    PUSH HL
    LD HL,FILNAM+1                  ; a * in the name
    LD C,8
    CALL STARQ
    LD HL,FILNAM+9                  ; and in the extension
    LD C,3
    CALL STARQ
    LD DE,DIRTMP
    LD C,F_DMAOFF
    CALL CPMENT
    LD DE,FILNAM
    LD C,F_SFIRST
    CALL CPMENT
    CP $FF
    JP Z,DERFNF                     ; nothing matches
ST_FILES_2:
    AND $03                         ; A = the entry's place in the record
    ADD A,A
    ADD A,A
    ADD A,A
    ADD A,A
    ADD A,A                         ; times 32, the size of an entry
    LD C,A
    LD B,$00
    LD HL,DIRTMP+1                  ; HL = the entry's name
    ADD HL,BC
    LD C,11
ST_FILES_3:
    LD A,[HL]
    INC HL
    CALL OUTDO
    LD A,C
    CP $04
    JP NZ,ST_FILES_5                ; not the end of the name
    LD A,[HL]
    CP ' '
    JP Z,ST_FILES_4                 ; no extension: a space
    LD A,'.'
ST_FILES_4:
    CALL OUTDO
ST_FILES_5:
    DEC C
    JP NZ,ST_FILES_3
    LD A,[TTYPOS]                   ; TTYPOS, the column
    ADD A,13                        ; room for another entry?
    LD D,A
    LD A,[LINLEN]                   ; the width
    CP D
    JP C,ST_FILES_6
    LD A,' '                        ; yes: two spaces
    CALL OUTDO
    CALL OUTDO
ST_FILES_6:
    CALL C,CRDO                     ; no: a new line
    LD DE,FILNAM
    LD C,F_SNEXT
    CALL CPMENT
    CP $FF
    JP NZ,ST_FILES_2
    POP HL
    RET

;; Fills a field of FILNAM with ? if it starts with *, for FILES.
;; In:    HL = the field, C = its length
;; Out:   HL = past the field if filled
;; See:   <FILLQ>
STARQ:
    LD A,[HL]
    CP '*'
    RET NZ

;; Fills a field of FILNAM with ?, which matches any character in a directory search.
;; In:    HL = the field, C = its length
;; Out:   HL = past the field, C = 0, zero = set
FILLQ:
    LD [HL],'?'
    INC HL
    DEC C
    JP NZ,FILLQ
    RET

;; Reads or writes a file's next record with the BDOS, advancing the FCB's random record as CP/M's sequential
;; calls advance their position.
;;
;; A is CPMREA or CPMWRI (CPMREA, CPMWRI), which INIT sets to the random calls on CP/M 2 and the sequential ones on
;; CP/M 1.4; counting the random record makes the random calls step through a file as the sequential ones do. A
;; random write's result is changed to a sequential write's, as OUTSEC expects: 5 (no directory space) is DERTMF,
;; 3 (an extent could not be closed) becomes 1, and the rest are raised by 1.
;; In:    A = the BDOS function, DE = the file's FCB
;; Out:   A = the result, 0 when it worked, zero = set when it worked (for a random write), C = the function
;; Errors: DERTMF if a random write runs out of directory space
;; Keeps: B, DE
CPMRW:
    PUSH DE
    LD C,A
    PUSH BC
    CALL CPMENT
    POP BC
    POP DE
    PUSH AF
    LD HL,FD_RR-FD_FCB              ; add 1 to the 3-byte random record
    ADD HL,DE
    INC [HL]
    JP NZ,CPMRW_1
    INC HL
    INC [HL]
    JP NZ,CPMRW_1
    INC HL
    INC [HL]
CPMRW_1:
    LD A,C
    CP F_WRITERAND
    JP NZ,CPMRW_2                   ; not a random write: as it came
    POP AF
    OR A
    RET Z                           ; written
    CP $05
    JP Z,DERTMF                     ; no directory space
    CP $03
    LD A,$01
    RET Z
    INC A
    RET
CPMRW_2:
    POP AF
    RET

;; Sets a random file's record length from OPEN's optional last argument, 128 if none, and clears its positions.
;;
;; The character after the name is taken to be the comma, without checking it.
;; In:    A = the mode, HL = the text after the file name, BC = the FDB
;; Out:   HL = the text after the record length
;; Errors: FCERR if the length is over the most the /S: switch allows (MAXREC)
;; Keeps: BC, DE
RECLEN:
    CP MD_RND
    RET NZ                          ; not a random file
    DEC HL
    CALL CHRGTR
    PUSH DE
    LD DE,DATPSC                    ; the default length
    JP Z,RECLEN_1                   ; none given
    PUSH BC
    CALL INTIDX                     ; DE = the length
    POP BC
RECLEN_1:
    PUSH HL
    LD HL,[MAXREC]                  ; the longest record allowed
    CALL DCOMPR
    JP C,FCERR                      ; too long
    LD HL,FD_RLEN
    ADD HL,BC
    LD [HL],E
    INC HL
    LD [HL],D
    XOR A
    LD E,FD_FIELD-FD_PREC           ; clear FD_PREC to FD_FPOS
RECLEN_2:
    INC HL
    LD [HL],A
    DEC E
    JP NZ,RECLEN_2
    POP HL
    POP DE
    RET

;; Runs PUT [#]n [, record]: writes a random file's record buffer to the file as a record.
;; In:    HL = the text after PUT
;; See:   <ST_GET>
ST_PUT:
    .byte $F6                       ; OR $AF: skips the XOR A, leaving A nonzero

;; Runs GET [#]n [, record]: reads a record of a random file into its record buffer.
;;
;; Without a record number, it is the one after the current one. A record of FD_RLEN bytes starts (record - 1) *
;; FD_RLEN bytes into the file, so it may straddle 128-byte CP/M records: each pass of the loop moves the part in
;; one of them, between the record buffer (at LBUFF, FLDPTR) and the file's buffer (at PBUFF, SECPTR), with RECRD
;; (TEMPB) counting the CP/M records. A PUT of less than a whole CP/M record reads it first.
;; In:    HL = the text after GET
;; Out:   HL = the text after the statement
;; Errors: DERBFM if the file is not random, DERBRN for record 0, FCERR for a record too far into the file,
;;          SNERR for anything after the statement
ST_GET:
    XOR A
    LD [PUTFLG],A                   ; PGTFLG: nonzero for PUT
    CALL FILSCN                     ; BC = the file's FDB, A = its mode
    CP MD_RND
    JP NZ,DERBFM
    PUSH BC
    PUSH HL
    LD HL,FD_LREC
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC DE                          ; DE = the next record, the default
    EX [SP],HL
    LD A,[HL]
    CP ','
    CALL Z,INTIDX                   ; DE = the record given
    DEC HL
    CALL CHRGTR
    JP NZ,SNERR                     ; must end there
    EX [SP],HL
    LD A,D
    OR E
    JP Z,DERBRN                     ; there is no record 0
    DEC HL
    LD [HL],E                       ; the current record
    INC HL
    LD [HL],D
    DEC DE                          ; DE = the record, from 0
    POP HL
    POP BC
    PUSH HL
    PUSH BC
    LD HL,FD_FPOS                   ; back to the start of the record buffer
    ADD HL,BC
    XOR A
    LD [HL],A
    INC HL
    LD [HL],A
    LD HL,FD_RLEN
    ADD HL,BC
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    EX DE,HL                        ; DE = the record length, HL = the record
    PUSH DE
    PUSH HL
    LD HL,DATPSC
    CALL DCOMPR
    POP HL
    JP NZ,ST_GET_1
    LD DE,$0000                     ; a 128-byte record is a CP/M record
    JP ST_GET_8
ST_GET_1:
    LD B,D                          ; the record times its length, a 32-bit product
    LD C,E                          ; BC = the length
    LD A,16
    EX DE,HL                        ; DE = the record
    LD HL,$0000                     ; HL = the product's low word
    PUSH HL                         ; and its high word, on the stack
ST_GET_2:
    ADD HL,HL                       ; shift the product left
    EX [SP],HL
    JP NC,ST_GET_3
    ADD HL,HL
    INC HL
    JP ST_GET_4
ST_GET_3:
    ADD HL,HL
ST_GET_4:
    EX [SP],HL
    EX DE,HL
    ADD HL,HL                       ; the record's next bit
    EX DE,HL
    JP NC,ST_GET_6
    ADD HL,BC                       ; set: add the length
    EX [SP],HL
    JP NC,ST_GET_5
    INC HL
ST_GET_5:
    EX [SP],HL
ST_GET_6:
    DEC A
    JP NZ,ST_GET_2
    LD A,L
    AND $7F
    LD E,A                          ; DE = the offset into the CP/M record
    LD D,$00
    POP BC                          ; BC = the high word
    LD A,L
    LD L,H
    LD H,C
    ADD HL,HL                       ; HL = the product / 128, the CP/M record
    JP C,FCERR                      ; past 65535 CP/M records
    RLA
    JP NC,ST_GET_7
    INC HL
ST_GET_7:
    LD A,B
    OR A
    JP NZ,FCERR
ST_GET_8:
    LD [TEMPB],HL                   ; RECRD = the CP/M record
    POP HL                          ; HL = the record length
    POP BC                          ; BC = the FDB
    PUSH HL                         ; the bytes left to move
    LD HL,FD_FIELD
    ADD HL,BC
    LD [FLDPTR],HL                  ; LBUFF = the record buffer
ST_GET_9:
    LD HL,FD_BUF
    ADD HL,BC
    ADD HL,DE
    LD [SECPTR],HL                  ; PBUFF = the offset into the file's buffer
    POP HL
    PUSH HL
    LD HL,DATPSC                    ; HL = the bytes from there to the end of the CP/M record
    LD A,L
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    POP DE                          ; DE = the bytes left
    PUSH DE
    CALL DCOMPR
    JP C,ST_GET_10
    LD H,D                          ; HL = the fewer of them, the bytes to move this pass
    LD L,E
ST_GET_10:
    LD A,[PUTFLG]
    OR A
    JP Z,ST_GET_13                  ; GET
    LD DE,DATPSC
    CALL DCOMPR
    JP NC,ST_GET_11                 ; a whole CP/M record: no need to read it
    PUSH HL
    CALL PHYGET                     ; read the CP/M record to change part of it
    POP HL
ST_GET_11:
    PUSH BC
    LD B,H
    LD C,L
    EX DE,HL
    LD HL,[SECPTR]
    EX DE,HL
    LD HL,[FLDPTR]
    CALL BLKMOV                     ; the record buffer to the file's buffer
    LD [FLDPTR],HL
    LD D,B
    LD E,C                          ; DE = the bytes moved
    POP BC
    CALL PHYPUT                     ; write the CP/M record
ST_GET_12:
    LD HL,[TEMPB]                   ; the next CP/M record
    INC HL
    LD [TEMPB],HL
    POP HL
    LD A,L                          ; fewer bytes left
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    LD A,H
    OR L
    LD DE,$0000                     ; from the next CP/M record's start
    PUSH HL
    JP NZ,ST_GET_9
    POP HL
    POP HL                          ; HL = the text
    RET
ST_GET_13:
    PUSH HL
    CALL PHYGET                     ; read the CP/M record
    POP HL
    PUSH BC
    LD B,H
    LD C,L
    EX DE,HL
    LD HL,[FLDPTR]
    EX DE,HL
    LD HL,[SECPTR]
    CALL BLKMOV                     ; the file's buffer to the record buffer
    EX DE,HL
    LD [FLDPTR],HL
    LD D,B
    LD E,C                          ; DE = the bytes moved
    POP BC
    JP ST_GET_12

;; Writes a random file's buffer to the 128-byte CP/M record RECRD names.
;; In:    BC = the FDB, TEMPB = RECRD, the CP/M record, from 0
;; See:   <PHYGET>
PHYPUT:
    .byte $F6                       ; OR $AF: skips the XOR A, leaving A nonzero

;; Reads the 128-byte CP/M record RECRD names into a random file's buffer, unless it is there already.
;;
;; FD_PREC remembers the record in the buffer. PHYPUT always writes.
;; In:    BC = the FDB, TEMPB = RECRD, the CP/M record, from 0
;; Errors: the errors of reading and writing (RNDREC)
;; Keeps: BC, DE, HL
PHYGET:
    XOR A
    LD [RNDWRT],A                   ; nonzero to write
    PUSH BC
    PUSH DE
    PUSH HL
    EX DE,HL
    LD HL,[TEMPB]
    EX DE,HL
    LD HL,FD_PREC
    ADD HL,BC
    PUSH HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A                          ; HL = the record in the buffer, plus 1
    INC DE                          ; DE = the one wanted, plus 1
    CALL DCOMPR
    POP HL
    LD [HL],E                       ; it will be in the buffer
    INC HL
    LD [HL],D
    JP NZ,PHYGET_1                  ; another record
    LD A,[RNDWRT]
    OR A
    JP Z,PHYGET_2                   ; reading the one already there
PHYGET_1:
    LD HL,PHYGET_2                  ; the stack RNDREC expects
    PUSH HL
    PUSH BC
    PUSH HL
    LD HL,FD_REC+1
    ADD HL,BC
    JP RNDREC
PHYGET_2:
    POP HL
    POP DE
    POP BC
    RET

;; Copies BC bytes from HL to DE, low addresses first.
;; In:    HL = the source, DE = the destination, BC = the count (not 0)
;; Out:   HL, DE = past the bytes
;; Uses:  A
;; Keeps: BC
BLKMOV:
    PUSH BC
BLKMOV_1:
    LD A,[HL]
    LD [DE],A
    INC HL
    INC DE
    DEC BC
    LD A,B
    OR C
    JP NZ,BLKMOV_1
    POP BC
    RET

;; Writes a byte into a random file's record buffer, for PRINT#, keeping the file's column as SEQOUT does.
;; In:    HL = the FDB, the stack = AF (the byte), then HL, as FILOU3 pushed them
;; Errors: DERFOV if the record buffer is full
RNDOUT:
    POP AF
    PUSH DE
    PUSH BC
    PUSH AF
    LD B,H
    LD C,L                          ; BC = the FDB
    CALL FLDCHK_1
    JP Z,RNDFOV                     ; full
    CALL NXTFPS                     ; DE = the byte's position, from 1
    LD HL,FD_FIELD-1
    ADD HL,BC
    ADD HL,DE
    POP AF
    LD [HL],A
    PUSH AF
    LD HL,FD_BREM                   ; the column
    ADD HL,BC
    LD D,[HL]
    LD [HL],$00
    CP $0D
    JP Z,RNDOUT_1                   ; a return: back to column 0
    ADD A,$E0                       ; carry = a printing character
    LD A,D
    ADC A,$00
    LD [HL],A
RNDOUT_1:
    POP AF
    POP BC
    POP DE
    POP HL
    RET
RNDFOV:
    JP DERFOV

;; Reads the next byte of a random file's record buffer, for INPUT#.
;; In:    HL = the FDB, the stack = HL, then BC, as INDSKB pushed them
;; Out:   A = the byte, carry clear
;; Errors: DERFOV at the end of the record
RNDIN:
    PUSH DE
    CALL FLDCHK
    JP Z,RNDFOV                     ; read it all
    CALL NXTFPS
    LD HL,FD_FIELD-1
    ADD HL,BC
    ADD HL,DE
    LD A,[HL]
    OR A                            ; carry clear
    POP DE
    POP HL
    POP BC
    RET

;; Returns a random file's record length.
;; In:    BC = the FDB
;; Out:   DE = FD_RLEN, HL = its high byte's address
;; Keeps: A, BC
GETRLN:
    LD HL,FD_RLEN
    JP GETFPS_1

;; Returns a random file's position in its record buffer.
;; In:    BC = the FDB
;; Out:   DE = FD_FPOS, HL = its high byte's address
;; Keeps: A, BC
GETFPS:
    LD HL,FD_FPOS
GETFPS_1:
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    RET

;; Advances a random file's position in its record buffer.
;; In:    BC = the FDB, DE = the position
;; Out:   DE = FD_FPOS = the position + 1
;; Keeps: A, BC
NXTFPS:
    INC DE
    LD HL,FD_FPOS
    ADD HL,BC
    LD [HL],E
    INC HL
    LD [HL],D
    RET

;; Compares a random file's position in its record buffer with the record length.
;; In:    HL = the FDB
;; Out:   BC = the FDB, DE = the position, HL = the record length, zero = set if the buffer is full
;; Entry: FLDCHK_1 = with BC = the FDB
FLDCHK:
    LD B,H
    LD C,L
FLDCHK_1:
    CALL GETFPS
    PUSH DE
    CALL GETRLN
    EX DE,HL
    POP DE
    CALL DCOMPR
    RET

;; Runs SAVE name,P: saves the program in binary, encoded so that it can be loaded and run but not listed.
;;
;; The program is encoded in place with PROENC, written as by a binary SAVE but with $FE for its first byte, and
;; decoded again with PROLOD.
;; In:    HL = the text at the P
;; Out:   HL = the text after the P, from TEMP
PROSAV:
    CALL CHRGTR                     ; skip the P
    LD [TEMP],HL
    CALL SCCPTR                     ; line numbers, not pointers, in the program
    CALL PROENC
    LD A,$FE                        ; a protected file
    CALL BINSAV_1                   ; write it and the program, and close the file
    CALL PROLOD
    JP GTMPRT

;; Encodes the program from TXTTAB to VARTAB in place for a protected SAVE.
;;
;; Each byte becomes ((byte - B) XOR ATNCON[C] XOR SINCON[B]) + C, where B counts down from 13 to 1 and C from 11
;; to 1, each starting again at its top. The keys are the bytes of the math package's series coefficients.
;; Uses:  A, BC, DE, HL
PROENC:
    LD BC,$0D0B                     ; B = 13, C = 11
    LD HL,[TXTTAB]
    EX DE,HL
PROENC_1:
    LD HL,[VARTAB]
    CALL DCOMPR
    RET Z                           ; at the end
    LD HL,ATNCON
    LD A,L
    ADD A,C
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A                          ; HL = ATNCON + C
    LD A,[DE]
    SUB B
    XOR [HL]
    PUSH AF
    LD HL,SINCON
    LD A,L
    ADD A,B
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A                          ; HL = SINCON + B
    POP AF
    XOR [HL]
    ADD A,C
    LD [DE],A
    INC DE
    DEC C
    JP NZ,PROENC_2
    LD C,11
PROENC_2:
    DEC B
    JP NZ,PROENC_1
    LD B,13
    JP PROENC_1

;; Decodes a protected program from TXTTAB to VARTAB in place, undoing PROENC.
;;
;; Each byte becomes ((byte - C) XOR SINCON[B] XOR ATNCON[C]) + B, with B and C counting as in PROENC.
;; Uses:  A, BC, DE, HL
PROLOD:
    LD BC,$0D0B                     ; B = 13, C = 11
    LD HL,[TXTTAB]
    EX DE,HL
PROLOD_1:
    LD HL,[VARTAB]
    CALL DCOMPR
    RET Z
    LD HL,SINCON
    LD A,L
    ADD A,B
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A                          ; HL = SINCON + B
    LD A,[DE]
    SUB C
    XOR [HL]
    PUSH AF
    LD HL,ATNCON
    LD A,L
    ADD A,C
    LD L,A
    LD A,H
    ADC A,$00
    LD H,A                          ; HL = ATNCON + C
    POP AF
    XOR [HL]
    ADD A,B
    LD [DE],A
    INC DE
    DEC C
    JP NZ,PROLOD_2
    LD C,11
PROLOD_2:
    DEC B
    JP NZ,PROLOD_1
    LD B,13
    JP PROLOD_1

;; Refuses a direct statement while a protected program is loaded.
;; Errors: FCERR in direct mode (CURLIN = $FFFF) when a protected program is loaded
;; Keeps: BC, DE, HL
PRODIR:
    PUSH HL
    LD HL,[CURLIN]
    LD A,H
    AND L
    POP HL
    INC A
    RET NZ                          ; running a program

;; Refuses to list or change a protected program.
;; Errors: FCERR if a protected program is loaded (PROFLG)
;; Keeps: AF, BC, DE, HL
PROCHK:
    PUSH AF
    LD A,[PROFLG]
    OR A
    JP NZ,FCERR
    POP AF
    RET
