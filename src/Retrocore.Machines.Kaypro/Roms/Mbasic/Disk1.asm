;; MBASIC 5.21: DISK FILES, PART 1 (DSKCOM)
;;
;; The disk statements and functions that work on a file through its data block, as GW-BASIC's DSKCOM.ASM has
;; them, in the same order, and the first of the CP/M file routines under them. Runs at $5161-$563F. In order:
;;
;; - MKI$, MKS$ and MKD$ (FN_MKI and the rest) turn a number into a string of its 2, 4 or 8 bytes, and CVI, CVS
;;   and CVD (FN_CVI and the rest) turn one back, for random files' FIELD buffers.
;; - FILIND and DLINE read an item for INPUT # and LINE INPUT # from a sequential file, through INDSKC (Disk2.asm),
;;   into BUF, and hand it to the assignment code.
;; - PRGFLI and PRGFL2 open a program file as file 0 through PRGFIL (Disk2.asm). LOAD, RUN "file"
;;   (LRUN), CHAIN (CHNENT) and the command line's file (INITSA, Init.asm) then read it: a binary file ($FF, or
;;   $FE when protected) straight into the program area (BINLOD), an ASCII one a line at a time through MAIN, as
;;   if typed (MAINGO). MERGE (OKGETM) takes only ASCII. DIRDO stops a direct statement in such a file.
;; - SAVE writes the program in binary (BINSAV), protected (PROSAV) or as ASCII through LIST.
;; - CLOSE calls CLSFIL for each file named, or for every file; CLSALL closes them all for NEW, RUN and the rest.
;; - FIELD carves a random file's FIELD buffer into string variables; LSET and RSET copy a string into one.
;; - INPUT$ (FIXINP) reads a count of characters from the keyboard or a file, and EOF (FN_EOF) tests a file's end.
;; - OUTSEC writes a data block's sector buffer to its file, and CLSFIL closes a file.
;;
;; Numbers and strings pass through the floating accumulator, FAC (FACLO, holding a string's descriptor),
;; with its type in VALTYP.
;;
;; Each open file has a data block, which FILPTR points to by file number; PTRFIL points to
;; the one being read or written, zero for the console. File 0 is BASIC's own, for LOAD, SAVE, MERGE and CHAIN.
;; INIT (Init.asm) lays the blocks out. A block holds the file's mode, its CP/M file control block (FCB), counts
;; and a 128-byte sector buffer (the FD_ offsets in Equates.asm); a block for files 1 and up goes on with a random file's
;; record size and FIELD buffer.
;;
;; The CP/M calls go through BDOS (CPMENT) with the function in C and the FCB or address in DE. Their numbers are
;; the F_ constants in Equates.asm, by Digital Research's names. Version 1 CP/M has only the sequential reads and writes
;; (F_READ, F_WRITE), so INIT picks the functions BASIC uses for its records by the version (CPMREA, CPMWRI).

;; MKI$(n): the integer n as a string of its 2 bytes.
;;
;; MKS$ and MKD$ enter below, setting the length for a single (4 bytes) or double (8). DOCNVF converts
;; the argument to that type, STRINI makes room for the string, VMOVMF copies the floating
;; accumulator into it, and FINBCK returns it as a temporary.
;;
;; In:    FACLO = n, the argument
;; Out:   FACLO = the string's descriptor, VALTYP = 3, VALTYP's string type
;; Entry: FN_MKS = MKS$, 4 bytes, FN_MKD = MKD$, 8 bytes
FN_MKI:
    LD A,$02                        ; the type, and the length: integer
    .byte $01                       ; LD BC,nn: skips the next instruction
FN_MKS:
    LD A,$04                        ; single
    .byte $01                       ; LD BC,nn: skips the next instruction
FN_MKD:
    LD A,$08                        ; double
    PUSH AF
    CALL DOCNVF                     ; the argument to that type
    POP AF
    CALL STRINI                     ; room for A bytes
    LD HL,[DSCPTR]                  ; where the string's text goes
    CALL VMOVMF                     ; copy the number there
    JP FINBCK                       ; return the string

;; CVI(s$): the integer whose 2 bytes are the start of s$.
;;
;; CVS and CVD enter below for a single or a double. The string must be at least as long as the number, or it
;; is an Illegal function call.
;;
;; In:    FACLO = the string's descriptor
;; Out:   FACLO = the number, VALTYP = its type (VALTYP)
;; Errors: Illegal function call (FCERR) if the string is too short
;; Entry: FN_CVS = CVS, 4 bytes, FN_CVD = CVD, 8 bytes
FN_CVI:
    LD A,$01                        ; the type less one, the length less one: integer
    .byte $01                       ; LD BC,nn: skips the next instruction
FN_CVS:
    LD A,$03                        ; single
    .byte $01                       ; LD BC,nn: skips the next instruction
FN_CVD:
    LD A,$07                        ; double
    PUSH AF
    CALL FRESTR                     ; HL = the descriptor, freeing a temporary
    POP AF
    CP [HL]
    JP NC,FCERR                     ; shorter than the number: FCERR
    INC A
    LD [VALTYP],A                   ; the number's type
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A                          ; HL = the string's text
    JP VMOVFM                       ; into the floating accumulator

;; Reads the next item for INPUT # from the sequential file PTRFIL, into the variable being read.
;;
;; A number ends at a space, a comma or the end of a line; a string at a comma or the end of a line, or at its
;; closing quote if it starts with one. Leading spaces are skipped. The item goes to BUF and on to
;; DOASIG, which assigns it, by the return address pushed here. It goes on in DLINE's code at INPDOR, which
;; LINE INPUT # enters with no terminators, to take the whole line. The item is cut at 255 characters (STRCHR).
;;
;; In:    HL = the text, VALTYP = the variable's type (VALTYP)
;; Out:   DSCTMP = a string item, through STRLT2, FACLO = a number, through FIN
;; Errors: Input past end (DERRPE) at the end of the file before anything is read
FILIND:
    CALL GETYPR                     ; zero for a string
    LD BC,DOASIG                    ; return through the assignment of the item
    LD DE,(',' << 8) | ' '          ; terminators: a space and a comma, for a number
    JP NZ,INPDOR
    LD E,D                          ; a string: both terminators a comma
    JP INPDOR

;; LINE INPUT #: reads the rest of a line from a sequential file into a string variable.
;;
;; In:    HL = the text, after LINE INPUT
;; Out:   HL = the text after the statement, PTRFIL = 0, PTRFIL cleared by FINPRT on the way out
;; Errors: Input past end (DERRPE), Type mismatch (TMERR) if the variable is not a string
;; Entry: INPDOR = from FILIND, with the type in A, the return address in BC and the terminators in D and E
DLINE:
    CALL FILINP                     ; the file number, into PTRFIL
    CALL PTRGET                     ; DE = the variable
    CALL CHKSTR                     ; FRCSTR: it must be a string
    LD BC,FINPRT                    ; back to the console when done
    PUSH BC
    PUSH DE                         ; the variable
    LD BC,LETCON                    ; assign the string to it
    XOR A                           ; a string
    LD D,A                          ; no terminators: the whole line
    LD E,A
INPDOR:
    PUSH AF                         ; the type
    PUSH BC                         ; the return address
    PUSH HL                         ; the text
NOTNWT:
    CALL INDSKC                     ; the next character
    JP C,DERRPE                     ; the end of the file
    CP ' '
    JP NZ,NTSPCI
    INC D                           ; LINE INPUT keeps leading spaces
    DEC D
    JP NZ,NOTNWT                    ; skip it
NTSPCI:
    CP '"'
    JP NZ,NOTQTE
    LD B,A
    LD A,E
    CP ','                          ; a quote only starts a string
    LD A,B
    JP NZ,NOTQTE
    LD D,B                          ; only a quote ends it
    LD E,B
    CALL INDSKC                     ; past the quote
    JP C,QUITSI                     ; the end of the file
NOTQTE:
    LD HL,BUF                       ; BUF, where the item goes
    LD B,$FF                        ; at most 255 characters
LOPCRS:
    LD C,A
    LD A,D
    CP '"'
    LD A,C
    JP Z,NOTQTL                     ; in quotes, returns and line feeds are text
    CP $0D
    PUSH HL
    JP Z,ICASLF                     ; a return ends the item: eat a line feed after it
    POP HL
    CP $0A
    JP NZ,NOTQTL
    LD C,A                          ; a line feed: kept in a string, not a number
    LD A,E
    CP ','
    LD A,C
    CALL NZ,STRCHR
    CALL INDSKC
    JP C,QUITSI
    CP $0D                          ; a return after the line feed?
    JP NZ,NOTQTL
    LD A,E
    CP ' '
    JP Z,LPCRGT                     ; a number ignores it
    CP ','
    LD A,$0D
    JP Z,LPCRGT                     ; so does an unquoted string
NOTQTL:
    OR A
    JP Z,LPCRGT                     ; zeros are dropped: zero ends the item for STRLT2
    CP D
    JP Z,QUITSI                     ; a terminator
    CP E
    JP Z,QUITSI
    CALL STRCHR
LPCRGT:
    CALL INDSKC
    JP NC,LOPCRS
QUITSI:
    PUSH HL                         ; where the item ends
    CP '"'
    JP Z,MORSPC                     ; after a quote, skip spaces and a comma or line end
    CP ' '
    JP NZ,NOSKCR                    ; ended by anything but a space: skip nothing
MORSPC:
    CALL INDSKC
    JP C,NOSKCR
    CP ' '
    JP Z,MORSPC
    CP ','
    JP Z,NOSKCR                     ; a comma: skipped
    CP $0D
    JP NZ,BAKUPT                    ; anything else is read again
ICASLF:
    CALL INDSKC
    JP C,NOSKCR
    CP $0A
    JP Z,NOSKCR                     ; a line feed after the return: skipped
BAKUPT:
    LD HL,[PTRFIL]
    LD BC,FD_BREM
    ADD HL,BC
    INC [HL]                        ; back up over the character: one more to read
NOSKCR:
    POP HL
QUIT2B:
    LD [HL],$00                     ; end the item
    LD HL,BUF-1                     ; HL = the item, less one, as CHRGTR wants it
    LD A,E
    SUB ' '
    JP Z,NUMIMK                     ; a number
    LD B,D                          ; B = the quote, or a comma for an unquoted string
    LD D,$00
    CALL STRLT2                     ; the item as a string
    POP HL                          ; the text
    RET                             ; to the assignment

;; Scans the number read into BUF by FILIND as the type of the variable being read.
;;
;; The text pointer is on the stack.
;;
;; In:    HL = BUF-1, the item less one, VALTYP = the variable's type (VALTYP)
;; Out:   FACLO = the number, HL = the text
NUMIMK:
    CALL GETYPR                     ; carry for an integer or single
    PUSH AF
    CALL CHRGTR                     ; the first character
    POP AF
    PUSH AF
    CALL C,FIN                      ; an integer or single
    POP AF
    CALL NC,FINDBL                  ; a double, keeping its digits
    POP HL                          ; the text
    RET

;; Stores a character of the item FILIND is reading, ending the item if BUF is full.
;;
;; A zero is not stored. When the 255th character is stored, it drops its return address and ends the item
;; at QUIT2B.
;;
;; In:    A = the character, HL = where it goes, B = the room left
;; Out:   HL = past the character, B = the room left
STRCHR:
    OR A
    RET Z                           ; never store a zero
    LD [HL],A
    INC HL
    DEC B
    RET NZ
    POP BC                          ; full: drop the return address
    JP QUIT2B

;; Opens the program file named at HL for input as file 0, for LOAD, RUN, MERGE and CHAIN.
;;
;; PRGFL2 opens it in the mode in D, for SAVE. PRGFIL (Disk2.asm) reads the name and opens the file.
;;
;; In:    HL = the text, at the file name
;; Out:   HL = the text after the name, PTRFIL = file 0's data block
;; Entry: PRGFL2 = opens it in the mode in D
PRGFLI:
    LD D,MD_SQI                     ; sequential input
PRGFL2:
    XOR A                           ; file 0
    JP PRGFIL

;; RUN "file": loads a program from a file and runs it, closing the files first.
;;
;; It is LOAD with its run flag set: the OR below sets A nonzero and skips LOAD's XOR A. ST_RUN comes here when
;; a file name follows, and INITSA (Init.asm) for a file named on the command line.
;;
;; In:    HL = the text, at the file name
LRUN:
    .byte $F6                       ; OR n: A nonzero, to run, and skips the XOR A

;; LOAD "file"[,R]: loads a program from a file, binary or ASCII, closing the files first.
;;
;; ,R runs it and leaves the files open, as CHAIN does (CHNENT). It saves MAXFIL in MAXSAV and sets it
;; to zero so that SCRTCH closes no files, and keeps file 0, being read, from being closed by pointing its
;; FILPTR entry at a zero byte in TBUFF. A file that starts with $FF (or $FE, protected) is loaded byte for byte
;; (BINLOD); any other is read through MAIN, a line at a time, as if typed (MAINGO). RUNFLG says
;; whether to run the program when it is in.
;;
;; It ends at READY, at NEWSTT to run, or at CHNRET for CHAIN for a binary file, and at MAIN for an ASCII
;; one.
;;
;; In:    HL = the text, at the file name, A = 0 (nonzero from LRUN, to run)
;; Errors: Out of memory (OUTLOD) if the program does not fit
;; Entry: CHNENT = from CHAIN: run, leaving the files open, NOTRNL = the run flag on the stack
ST_LOAD:
    XOR A                           ; LOAD: don't run
    PUSH AF
    CALL PRGFLI                     ; open the file as file 0
    LD A,[MAXFIL]
    LD [MAXSAV],A                   ; saved, to be restored after SCRTCH
    DEC HL
    CALL CHRGTR
    JP Z,NOTRNL                     ; no ,R
    CALL SYNCHR
    .byte ','
    CALL SYNCHR
    .byte 'R'
    JP NZ,SNERR                     ; nothing may follow
    POP AF                          ; drop the run flag: ,R runs
CHNENT:
    XOR A
    LD [MAXFIL],A                   ; MAXFIL = 0: close no files
    .byte $F6                       ; OR n: A = $F1, nonzero, to run, and skips the POP AF
NOTRNL:
    POP AF                          ; the run flag
    LD [RUNFLG],A
    LD HL,TBUFF
    LD [HL],$00                     ; a closed file's mode
    LD [FILPTR],HL                  ; FILPTR for file 0: so SCRTCH leaves it open
    CALL SCRTCH                     ; clear the program and variables, close the files
    LD A,[MAXSAV]
    LD [MAXFIL],A                   ; MAXFIL back
    LD HL,[FILPT0]                  ; file 0's data block
    LD [FILPTR],HL                  ; back in FILPTR
    LD [PTRFIL],HL                  ; read the program from file 0
    LD HL,[CURLIN]
    INC HL
    LD A,H
    AND L
    INC A
    JP NZ,NOTINI                    ; not $FFFE, during INIT
    LD [CURLIN],HL                  ; $FFFF: a direct line, so a Control-C doesn't leave BASIC
NOTINI:
    CALL INDSKC                     ; the first byte
    JP C,MAIN                       ; an empty file
    CP $FE
    JP NZ,NTPROL
    LD [PROFLG],A                   ; a protected program
    JP BINLOD
NTPROL:
    INC A
    JP NZ,MAINGO                    ; not $FF: an ASCII file

;; Loads the binary program from file 0 into the program area, links it and, by RUNFLG, runs it.
;;
;; The bytes go from TXTTAB up through INDSKB (Disk2.asm), which reads them raw, to the end of the file; a
;; program that would come within 86 bytes of FRETOP is Out of memory. A protected program is decoded by
;; PROLOD. RUNC then clears the variables and closes file 0, with MAXFIL zero so that no
;; other file is closed.
;;
;; It ends at CHNRET for CHAIN, at READY for LOAD, or at NEWSTT to run.
;;
;; In:    PTRFIL = file 0, past the header byte
;; Errors: Out of memory (OUTLOD)
BINLOD:
    LD HL,[TXTTAB]
FSTLOD:
    EX DE,HL
    LD HL,[FRETOP]
    LD BC,$FFAA                     ; -86: leave room below the strings
    ADD HL,BC
    CALL DCOMPR
    EX DE,HL
    JP C,OUTLOD                     ; full
    CALL INDSKB                     ; the next byte, carry at the end of the file
    LD [HL],A
    INC HL
    JP NC,FSTLOD
    LD [VARTAB],HL                  ; the end, for decoding
    LD A,[PROFLG]
    OR A
    CALL NZ,PROLOD                  ; decode a protected program
    CALL LINKER                     ; fix the line links
    INC HL                          ; HL = the two zeros at the end
    INC HL
    LD [VARTAB],HL
    LD HL,MAXFIL
    LD A,[HL]
    LD [MAXSAV],A
    LD [HL],$00                     ; zero, so RUNC closes only file 0
    CALL RUNC                       ; clear the variables, close file 0
    LD A,[MAXSAV]
    LD [MAXFIL],A                   ; MAXFIL back
    LD A,[CHNFLG]
    OR A
    JP NZ,CHNRET                    ; back to CHAIN
    LD A,[RUNFLG]
    OR A
    JP Z,READY
    JP NEWSTT                       ; run it

;; Ends reading or writing a program file: back to the console, close file 0, and the text pointer back.
;;
;; Out:   HL = the text pointer saved in TEMP (GTMPRT), PTRFIL = 0
PRGFIN:
    CALL FINPRT                     ; PTRFIL = 0, A = 0
    CALL CLSFIL                     ; close file 0
    JP GTMPRT

;; Out of memory while loading: clears the partly loaded program and reports the error.
;;
;; Errors: Out of memory, through OMERR
OUTLOD:
    CALL SCRTCH
    JP OMERR

;; MERGE "file": merges the lines of an ASCII program file into the program.
;;
;; It drops NEWSTT's return address, since MAIN takes over; OKGETM reads the file, and CHAIN MERGE enters there.
;; Binary and protected files are a Bad file mode. MAINGO backs up over the first character and goes to MAIN,
;; which reads the file's lines as if typed until its end.
;;
;; It ends at MAIN.
;;
;; In:    HL = the text, at the file name
;; Errors: Bad file mode (DERBFM) for a binary file, Syntax error if anything follows the name
;; Entry: OKGETM = file 0 open: read it, MAINGO = back up over the file's first character and read it
ST_MERGE:
    POP BC                          ; drop NEWSTT's return
    CALL PRGFLI                     ; open the file as file 0
    DEC HL
    CALL CHRGTR
    JP Z,OKGETM                     ; nothing after the name: read it
    CALL PRGFIN                     ; close it again
    JP SNERR
OKGETM:
    XOR A
    LD [RUNFLG],A                   ; don't run
    CALL INDSKC                     ; the first byte
    JP C,MAIN                       ; an empty file
    INC A
    JP Z,DERBFM                     ; $FF: binary
    INC A
    JP Z,DERBFM                     ; $FE: protected
MAINGO:
    LD HL,[PTRFIL]
    LD BC,FD_BREM
    ADD HL,BC
    INC [HL]                        ; back up: the first character is read again
    JP MAIN

;; Runs a direct statement, unless the line came from a file being loaded: that is a Direct statement in file.
;;
;; It ends at GONE.
;;
;; In:    HL = the text, at the statement
;; Errors: Direct statement in file (66) if PTRFIL is set
DIRDO:
    PUSH HL
    LD HL,[PTRFIL]
    LD A,H
    OR L
    LD DE,$0042                     ; E = 66, Direct statement in file
    JP NZ,ERROR                     ; reading a file
    POP HL
    JP GONE

;; SAVE "file"[,A|,P]: writes the program to a file, in binary, as ASCII (,A) or protected (,P).
;;
;; The file is opened as file 0 for output first. ,A lists the program to it through ST_LIST; ,P goes to
;; PROSAV; with no option, BINSAV writes it in binary.
;;
;; In:    HL = the text, at the file name
;; Out:   HL = the text after the statement
ST_SAVE:
    LD D,MD_SQO                     ; sequential output
    CALL PRGFL2                     ; open the file as file 0
    DEC HL
    CALL CHRGTR
    JP Z,BINSAV                     ; no option: binary
    CALL SYNCHR
    .byte ','
    CP 'P'
    JP Z,PROSAV                     ; protected
    CALL SYNCHR
    .byte 'A'
    JP ST_LIST                      ; ASCII: list it to the file

;; Writes the program to file 0 in binary: $FF, then the program's bytes from TXTTAB to VARTAB.
;;
;; The line pointers are turned back to line numbers first (SCCPTR), and a protected program may not be saved
;; this way (PROCHK). PROSAV enters at BINSAV_1 with the header byte $FE, its program already encoded.
;;
;; It ends through PRGFIN, which closes the file and reloads HL with the text pointer from TEMP.
;;
;; In:    PTRFIL = file 0, open for output
;; Errors: Illegal function call (PROCHK) for a protected program
;; Entry: BINSAV_1 = the header byte in A
BINSAV:
    CALL SCCPTR                     ; line pointers back to numbers
    CALL PROCHK                     ; not if protected
    LD A,$FF                        ; a binary file's header
BINSAV_1:
    CALL FILOU3                     ; write it
    EX DE,HL
    LD HL,[VARTAB]
    EX DE,HL                        ; DE = the program's end
    LD HL,[TXTTAB]
BINSAV_2:
    CALL DCOMPR
    JP Z,PRGFIN                     ; all written: close the file
    LD A,[HL]
    INC HL
    PUSH DE
    CALL FILOU3                     ; write the byte
    POP DE
    JP BINSAV_2

;; CLOSE [[#]n[,[#]n]...]: closes the files named, or every file.
;;
;; The routine to apply to each file is in BC, here CLSFIL. With no file numbers it is called for each file
;; from MAXFIL down to 0, by pushing ST_CLOSE_2 as its return address; with numbers, for each, returning to
;; ST_CLOSE_3 to look for a comma and another.
;;
;; In:    HL = the text, after CLOSE, zero = set at the end of the statement
;; Out:   HL = the text after the statement
;; Entry: ST_CLOSE_1 = the loop over every file, from the file in A down, with the text on the stack
ST_CLOSE:
    LD BC,CLSFIL                    ; the routine for each file
    LD A,[MAXFIL]                   ; the highest file
    JP NZ,ST_CLOSE_4                ; file numbers follow
    PUSH HL                         ; the text
ST_CLOSE_1:
    PUSH BC
    PUSH AF
    LD DE,ST_CLOSE_2
    PUSH DE                         ; return to the loop
    PUSH BC
    RET                             ; call the routine for file A
ST_CLOSE_2:
    POP AF
    POP BC
    DEC A
    JP P,ST_CLOSE_1                 ; down to file 0
    POP HL                          ; the text
    RET
ST_CLOSE_3:
    POP BC                          ; the routine
    POP HL                          ; the text
    LD A,[HL]
    CP ','
    RET NZ                          ; no more file numbers
    CALL CHRGTR
ST_CLOSE_4:
    PUSH BC
    LD A,[HL]
    CP '#'
    CALL Z,CHRGTR                   ; the # is optional
    CALL GETBYT                     ; A = E = the file number
    EX [SP],HL                      ; HL = the routine, the text on the stack
    PUSH HL
    LD DE,ST_CLOSE_3
    PUSH DE                         ; return for the next file number
    JP [HL]

;; Closes every file, 0 to MAXFIL, for NEW, RUN, CLEAR, END and the rest.
;;
;; Out:   A = 0
;; Keeps: BC, DE
CLSALL:
    PUSH DE
    PUSH BC
    XOR A                           ; zero: no file numbers follow
    CALL ST_CLOSE
    POP BC
    POP DE
    XOR A
    RET

;; FIELD [#]n, w AS v$ [, w AS v$]...: points string variables into a random file's FIELD buffer.
;;
;; Each v$ gets a length of w and an address in the buffer, one after the other from FD_FIELD. The total may not
;; pass the file's record size (FD_RLEN), which TEMPA holds, against the running total in TEMPB.
;;
;; In:    HL = the text, after FIELD
;; Out:   HL = the text after the statement
;; Errors: Bad file number (DERBFN) if the file is not open, Bad file mode (DERBFM) if it is not random, FIELD
;;   overflow (DERFOV) past the record size
ST_FIELD:
    CALL FILSCN                     ; BC = the data block, A = its mode
    JP Z,DERBFN                     ; not open
    SUB MD_RND
    JP NZ,DERBFM                    ; not random
    EX DE,HL                        ; DE = the text
    LD HL,FD_RLEN
    ADD HL,BC
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    LD [TEMPA],HL                   ; TEMPA = the record size, the most allowed
    LD HL,$0000
    LD [TEMPB],HL                   ; none used yet
    LD A,H                          ; A = 0
    EX DE,HL
    LD DE,FD_FIELD                  ; the FIELD buffer
LOPFLD:
    EX DE,HL
    ADD HL,BC                       ; DE = the next field's address in the buffer
    LD B,A
    EX DE,HL
    LD A,[HL]
    CP ','
    RET NZ                          ; no more fields
    PUSH DE                         ; the field's address
    PUSH BC
    CALL GTBYTC                     ; A = the width
    PUSH AF
    CALL SYNCHR
    .byte 'A'
    CALL SYNCHR
    .byte 'S'
    CALL PTRGET                     ; DE = the variable
    CALL CHKSTR                     ; FRCSTR: it must be a string
    POP AF
    POP BC
    EX [SP],HL                      ; HL = the field's address, the text on the stack
    LD C,A                          ; C = the width
    PUSH DE
    PUSH HL
    LD HL,[TEMPB]
    LD B,$00
    ADD HL,BC
    LD [TEMPB],HL                   ; the total so far
    EX DE,HL
    LD HL,[TEMPA]
    CALL DCOMPR
    JP C,DERFOV                     ; past the record size
    POP HL
    POP DE
    EX DE,HL                        ; HL = the variable's descriptor
    LD [HL],C                       ; its length
    INC HL
    LD [HL],E                       ; its address, in the buffer
    INC HL
    LD [HL],D
    POP HL                          ; the text
    JP LOPFLD                       ; C = the width, to step past

;; RSET v$ = x$: copies x$ into v$ right-justified, padding its start with spaces; v$ keeps its length.
;;
;; It enters LSET with carry clear. A v$ in a FIELD buffer or in string space is written in place; one that
;; points into the program's text, a literal, gets a copy in string space first (MADESC). If that copy may
;; collect garbage (FRETOP too close to STREND) and x$ is a temporary, MAKDSC protects x$ with a new temporary.
;;
;; In:    HL = the text, after RSET
;; Out:   HL = the text after the statement
;; Errors: Type mismatch (TMERR) if either is not a string
ST_RSET:
    .byte $F6                       ; OR n: clears carry, for RSET, and skips the SCF

;; LSET v$ = x$: copies x$ into v$ left-justified, padding its end with spaces; v$ keeps its length.
;;
;; In:    HL = the text, after LSET, carry = clear from RSET
;; Out:   HL = the text after the statement
;; Errors: Type mismatch (TMERR) if either is not a string
ST_LSET:
    SCF                             ; LSET
    PUSH AF                         ; the LSET flag, in carry
    CALL PTRGET                     ; DE = v$
    CALL CHKSTR                     ; FRCSTR
    PUSH DE
    CALL FRMEQL                     ; "=" and x$
    POP BC                          ; BC = v$'s descriptor
    EX [SP],HL                      ; the text under the flag
    PUSH HL                         ; the flag
    PUSH BC
    CALL FRESTR                     ; HL = x$'s descriptor, zero if it was a temporary
    LD B,[HL]                       ; B = x$'s length
    EX [SP],HL                      ; HL = v$'s descriptor
    LD A,[HL]
    LD C,A                          ; C = v$'s length
    PUSH BC
    PUSH HL
    PUSH AF                         ; zero if x$ was a temporary
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]                       ; DE = v$'s text
    OR A
    JP Z,RETCUR                     ; v$ is empty: nothing to do
    LD HL,[TXTTAB]
    CALL DCOMPR
    JP NC,OLDSTR                    ; below the program: a FIELD buffer
    LD HL,[VARTAB]
    CALL DCOMPR
    JP C,OLDSTR                     ; above it: string space
    LD E,C                          ; a literal: copy it
    LD D,$00
    LD HL,[STREND]
    ADD HL,DE
    EX DE,HL
    LD HL,[FRETOP]
    CALL DCOMPR                     ; would GETSPA collect garbage?
    JP C,MAKDSC                     ; yes: keep x$ safe first
    POP AF                          ; drop the temporary flag
MADESC:
    LD A,C
    CALL GETSPA                     ; DE = room for v$'s length
    POP HL                          ; v$'s descriptor
    POP BC                          ; the lengths
    EX [SP],HL                      ; HL = x$'s descriptor
    PUSH DE
    PUSH BC
    CALL FRESTR                     ; free x$ if a temporary
    POP BC
    POP DE
    EX [SP],HL
    PUSH BC                         ; the stack as it was
    PUSH HL
    INC HL
    PUSH AF
    LD [HL],E                       ; v$ now points at the copy
    INC HL
    LD [HL],D
OLDSTR:
    POP AF
    POP HL                          ; v$'s descriptor
    INC HL
    LD E,[HL]
    INC HL
    LD D,[HL]                       ; DE = v$'s text
    POP BC                          ; the lengths
    POP HL                          ; x$'s descriptor
    INC HL
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A                          ; HL = x$'s text
    LD A,C
    CP B
    JP NC,FILDOK                    ; v$ is long enough for x$
    LD B,A                          ; copy only v$'s length
FILDOK:
    SUB B
    LD C,A                          ; C = the spaces to pad with
    POP AF                          ; the LSET flag
    CALL NC,BLKFIL                  ; RSET: pad the start
    INC B
COPLOP:
    DEC B
    JP Z,LRSTDN                     ; all copied
    LD A,[HL]
    LD [DE],A
    INC HL
    INC DE
    JP COPLOP
RETCUR:
    POP BC                          ; drop the five entries
    POP BC
    POP BC
    POP BC
    POP BC
LRSTDN:
    CALL C,BLKFIL                   ; LSET: pad the end
    POP HL                          ; the text
    RET

;; Fills C bytes at DE with spaces.
;;
;; In:    C = the count, DE = where
;; Out:   DE = past them, C = 0, A = ' '
BLKFIL:
    LD A,' '
    INC C                           ; in case it is zero
BLKFL1:
    DEC C
    RET Z
    LD [DE],A
    INC DE
    JP BLKFL1

;; LSET and RSET's copy of a literal, when GETSPA may collect garbage: a temporary x$ gets a new temporary.
;;
;; On the stack are the temporary flag, v$'s descriptor, the lengths and x$'s descriptor.
;;
;; It goes on to MADESC with the stack as it was.
;;
;; In:    zero = set if x$ was a temporary
MAKDSC:
    POP AF                          ; the temporary flag
    POP HL
    POP BC
    EX [SP],HL                      ; HL = x$'s descriptor
    EX DE,HL                        ; into DE, for STRINI
    JP NZ,MAKDS1                    ; not a temporary
    PUSH BC
    LD A,B
    CALL STRINI                     ; a temporary for x$
    CALL PUTNEW
    POP BC
MAKDS1:
    EX [SP],HL
    PUSH BC
    PUSH HL                         ; the stack as it was
    JP MADESC

;; INPUT$(n[,[#]f]): a string of the next n characters from the keyboard, or from file f.
;;
;; From the keyboard, characters are not echoed and not edited, and a Control-C ends the program (ENDCON). The
;; keyboard is read through CHARCG, a key typed ahead, and INCHRI (CONIN).
;;
;; In:    HL = the text, at INPUT
;; Out:   FACLO = the string, through PUTNEW
;; Errors: Illegal function call (FCERR) for n = 0, Bad file mode (DERBFM) for an output file, Input past end
;;   (DERRPE)
FIXINP:
    CALL CHRGTR
    CALL SYNCHR
    .byte '$'
    CALL SYNCHR
    .byte '('
    CALL GETBYT                     ; E = n
    PUSH DE
    LD A,[HL]
    CP ','
    JP NZ,REDTTY                    ; nonzero: from the keyboard
    CALL CHRGTR
    CALL FILSCN                     ; BC = the data block, A = its mode
    CP MD_SQO
    JP Z,DERBFM                     ; not an output file
    CALL FILSET                     ; PTRFIL = it
    XOR A                           ; zero: from the file
REDTTY:
    PUSH AF
    CALL SYNCHR
    .byte ')'
    POP AF
    EX [SP],HL                      ; L = n, the text on the stack
    PUSH AF
    LD A,L
    OR A
    JP Z,FCERR                      ; none: FCERR
    PUSH HL
    CALL STRINI                     ; room for n
    EX DE,HL                        ; HL = where they go
    POP BC                          ; C = n
FIXLOP:
    POP AF
    PUSH AF
    JP Z,DSKCHR                     ; from the file
    CALL CHARCG                     ; a key typed ahead
    JP NZ,CHARCW
    CALL INCHRI                     ; CONIN: wait for one
CHARCW:
    CP $03
    JP Z,FIXINP_1                   ; Control-C
PUTCHR:
    LD [HL],A
    INC HL
    DEC C
    JP NZ,FIXLOP
    POP AF
    CALL FINPRT                     ; PTRFIL = 0
    JP PUTNEW                       ; the string is the result
FIXINP_1:
    LD HL,[SAVSTK]
    LD SP,HL
    JP ENDCON                       ; stop, as for Control-C
DSKCHR:
    CALL INDSKC
    JP C,DERRPE                     ; past the end
    JP PUTCHR

;; EOF(f): -1 if sequential input file f is at its end, otherwise 0; always 0 for a random file.
;;
;; A file is at its end when its buffer is empty (FD_BCNT zero) or its next character is a Control-Z, CP/M's
;; end of a text file. When the buffer has been read through, the next sector is read (REDREC) to see.
;;
;; In:    FACLO = f
;; Out:   FACLO = -1 or 0, an integer (CONIA)
;; Errors: Bad file number (DERBFN) if not open, Bad file mode (DERBFM) for an output file
FN_EOF:
    CALL FILFRM                     ; BC = the data block, A = its mode
    JP Z,DERBFN                     ; not open
    CP MD_SQO
    JP Z,DERBFM
FN_EOF_1:
    LD HL,FD_BCNT
    ADD HL,BC
    LD A,[HL]
    OR A
    JP Z,FN_EOF_3                   ; nothing in the buffer: the end
    LD A,[BC]
    CP MD_RND
    JP Z,FN_EOF_3                   ; random: never (A = 3)
    INC HL                          ; FD_BREM
    LD A,[HL]
    OR A
    JP NZ,FN_EOF_2                  ; characters left
    PUSH BC
    LD H,B
    LD L,C
    CALL REDREC                     ; read the next sector
    POP BC
    JP FN_EOF_1
FN_EOF_2:
    LD A,$80
    SUB [HL]
    LD C,A
    LD B,$00
    ADD HL,BC
    INC HL                          ; HL = the next character in the buffer
    LD A,[HL]
    SUB $1A                         ; zero for a Control-Z
FN_EOF_3:
    SUB $01
    SBC A,A                         ; $FF if A was 0, else 0
    JP CONIA                        ; as an integer

;; Writes a data block's sector buffer to its file as the next record, and empties it.
;;
;; The BDOS function is the write function INIT chose (CPMWRI). CPMRW (Disk2.asm) makes the call and reports
;; its result as 0 for success, $FF for a full directory, 1 for an I/O error and 2 for a full disk; a random
;; write's full directory it reports itself, as Too many files. A full disk closes the file first, keeping what
;; was written.
;;
;; In:    BC = the data block
;; Out:   the block's FD_REC stepped, FD_BCNT = 0
;; Errors: Too many files (DERTMF) for a full directory, Disk I/O error (DERDIO), Disk full (DERDFL)
;; Entry: OUTSEC_1 = with DE already the block's FCB
OUTSEC:
    LD D,B
    LD E,C
    INC DE                          ; DE = the FCB
OUTSEC_1:
    LD HL,FD_BCNT
    ADD HL,BC
    PUSH BC
    XOR A
    LD [HL],A                       ; the buffer empty
    CALL SETDMA                     ; DMA = the block's buffer
    LD A,[CPMWRI]                   ; the write function
    CALL CPMRW                      ; write the record
    CP $FF
    JP Z,DERTMF                     ; the directory is full
    DEC A
    JP Z,DERDIO
    DEC A
    JP NZ,OUTSEC_2
    POP DE                          ; the disk is full: close the file
    XOR A
    LD [DE],A                       ; its mode: closed
    LD C,F_CLOSE
    INC DE                          ; the FCB
    CALL CPMENT                     ; BDOS
    JP DERDFL
OUTSEC_2:
    INC A
    JP Z,DERTMF                     ; never taken: A was 1 or $FF
    POP BC
    LD HL,FD_REC
    ADD HL,BC
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC DE                          ; one more record
    LD [HL],D
    DEC HL
    LD [HL],E
    RET

;; Closes file A: writes out an output file's last sector, ended by a Control-Z, and closes it with CP/M.
;;
;; A file that is not open is only cleared. In every case the block's first FD_BUF bytes, its mode, FCB and
;; counts, are zeroed, closing it for BASIC.
;;
;; In:    A = the file number
;; Out:   A = 0, zero = set
;; Errors: Bad file number (DERBFN) above MAXFIL, from FILIDX
CLSFIL:
    CALL FILIDX                     ; BC = the data block, A = its mode
    JP Z,CLSFIL_3                   ; not open
    PUSH BC
    LD A,[BC]
    LD D,B
    LD E,C
    INC DE
    PUSH DE                         ; the FCB
    CP MD_SQO
    JP NZ,CLSFIL_2                  ; not output: just close it
    LD HL,CLSFIL_1
    PUSH HL                         ; return here
    PUSH HL                         ; for SEQOUT to pop as HL
    LD H,B
    LD L,C
    LD A,$1A                        ; Control-Z, the end of the text
    JP SEQOUT                       ; write it to the file
CLSFIL_1:
    LD HL,FD_BCNT
    ADD HL,BC
    LD A,[HL]
    OR A
    CALL NZ,OUTSEC_1                ; write the last sector
CLSFIL_2:
    POP DE                          ; the FCB
    CALL SETDMA                     ; DMA = the block's buffer
    LD C,F_CLOSE
    CALL CPMENT                     ; BDOS
    POP BC
CLSFIL_3:
    LD D,FD_BUF                     ; the mode, FCB and counts
    XOR A
CLSFIL_4:
    LD [BC],A
    INC BC
    DEC D
    JP NZ,CLSFIL_4
    RET
