;; TRS-80 COLOR COMPUTER DISK EXTENDED COLOR BASIC ($C000-$DFFF), VERSIONS 1.0 AND 1.1
;;
;; Disk Extended Color BASIC is the disk controller cartridge's 8K ROM, which Extended BASIC finds at <DOSBAS> and
;; starts. It adds disk files to the other BASICs' devices: sequential and random files, numbered from 1, in a
;; directory of 72 entries and a file allocation table of 68 granules on 35-track disks; the commands DIR, DRIVE,
;; FILES, KILL, LOAD, SAVE, MERGE, RENAME, LOADM, SAVEM, COPY, BACKUP, DSKINI, UNLOAD, VERIFY, FIELD, LSET, RSET,
;; WRITE, DSKI$ and DSKO$; and the functions CVN, MKN$, LOC, LOF and FREE. <DSKCON> drives the WD1793 controller,
;; and programs can call it through <DCNVEC>.
;;
;; It adds itself the ways the other BASICs provide for. <DKINIT> copies its command tables into <COMVEC>, after
;; Extended BASIC's, and points the RAM hooks <RVEC0> to <RVEC18> at its own routines, which take over OPEN, CLOSE,
;; console in and out, INPUT, EOF and the rest when the device is a disk file. Its RAM, from $0600, is in
;; DiskBasicEquates.asm, and the Color and Extended BASIC routines it calls are in ColorBasicEntries.asm and
;; ExtendedBasicEntries.asm, at addresses every version shares.
;;
;; Assembles byte-identically to Disk Extended Color BASIC 1.0 or 1.1: VERSION selects the version (11, the
;; default, or 10). 1.1 adds DOS, which boots an OS-9 disk, and a statement loop that checks for BREAK only while
;; a key is down. It also fixes 1.0's FILES, which loses a program's place when it moves it; its writing of the FAT,
;; which clears one byte rather than the rest of the sector; its closing of a random file, which lets go of strings
;; in other files' buffers and leaves those files' buffers where they were; and its LOC and LOF, which go negative
;; past 32767.
;;
;; Labels follow the names Microsoft's BASIC and Spectral Associates' Disk Basic Unravelled use where they have them,
;; such as <DSKCON>, <DVEC0> and <FCBTMP>. The comments are our own.
;;
;; Maintained by hand. CocoRomSourceTests check that each version assembles byte-identically to its ROM.

.ifndef VERSION
VERSION = 11
.endif
.assert (VERSION = 10) | (VERSION = 11), "VERSION is 10 or 11."

.cpu M6809

.include "ColorBasicEquates.asm"
.include "ColorBasicEntries.asm"
.include "ExtendedBasicEquates.asm"
.include "ExtendedBasicEntries.asm"
.include "DiskBasicEquates.asm"

;; The highest command token: DSKO$ in 1.0, and DOS, which 1.1 adds.
.if VERSION = 10
DHITOK = TK_DSKO
.else
DHITOK = TK_DOS
.endif

.org $C000

DOSBAS:
    .byte "DK"                      ; Color BASIC and Extended BASIC look for these to find this ROM

;; Starts Disk Extended Color BASIC: Extended BASIC's start-up jumps here, at <DOSBAS>+2, when it finds this ROM.
DKCOLD:
    BRA DKINIT

;; Where DSKCON is, for programs to call it through: JSR [DCNVEC].
DCNVEC:
    .dbyt DSKCON

;; Where DSKCON's arguments are: <DCOPC> and the five bytes after it.
DSKVAR:
    .dbyt DCOPC

.if VERSION = 11
;; Where the start-up routine that points SWI2 and SWI3 is: <DOSINI>.
DSINIT:
    .dbyt DOSINI

;; Where DOS's routine is: <DOSCOM>.
DOSVEC:
    .dbyt DOSCOM
.endif

;; Sets Disk BASIC up at power on, after Extended BASIC: clears its RAM, adds its command tables to <COMVEC> and
;; its routines to the RAM hooks, moves the USR table to <DUSRVC>, takes the NMI and IRQ, makes two files' FCBs,
;; and moves the program up past them and four graphics pages. Then it resets the disk controller, signs on, and
;; enters BASIC.
DKINIT:
    LDX #DBUF0
DKINIT_CLEAR:
    CLR ,X+
    CMPX #DFLBUF
    BNE DKINIT_CLEAR
    LDX #DCOMVEC
    LDU #COMVEC+20                  ; the third table
    LDB #10
    JSR MOVEXU
    LDD #SNERR
    STD 3,U                         ; a user's command and function routines: ?SN ERROR, until one is added
    STD 8,U
    CLR ,U                          ; and no user commands
    CLR 5,U                         ;   or functions
    LDD #DXCVEC
    STD COMVEC+13                   ; Extended BASIC's commands and functions go through Disk BASIC first
    LDD #DXIVEC
    STD COMVEC+18
    LDU #RVEC0
DKINIT_HOOK:
    LDA #$7E                        ; JMP
    STA RVEC22
    STA ,U+
    LDD ,X++
    STD ,U++
    CMPX #DSIGNON                   ; the end of the hooks' table
    BNE DKINIT_HOOK
    LDX #DVEC22
    STX RVEC22+1
.if VERSION = 11
    LDX #DVEC20
    STX RVEC20+1
.endif
    LDX #DUSRVC
    STX USRADR
    LDU #FCERR
    LDB #10
DKINIT_USR:
    STU ,X++                        ; USR0 to USR9 all ?FC ERROR
    DECB
    BNE DKINIT_USR
    LDX #DNMISV
    STX NMIVEC+1
    LDA #$7E                        ; JMP
    STA NMIVEC
    LDX #DIRQSV
    STX IRQVEC+1
    LDA #19
    STA WFATVL                      ; write a FAT once 19 granules have been taken
    CLR FATBL0                      ; no files open on any drive
    CLR FATBL1
    CLR FATBL2
    CLR FATBL3
    LDX #DFLBUF
    STX RNBFAD                      ; 256 bytes of random file buffer space
    LEAX SECLEN,X
    STX FCBADR
    LEAX 1,X
    STX FCBV1                       ; file 1's FCB
    CLR <<FCBTYP,X
    LEAX FCBLEN,X
    STX FCBV1+2                     ; file 2's
    CLR <<FCBTYP,X
    LEAX FCBLEN,X
    STX FCBV1+4                     ; the system's
    CLR <<FCBTYP,X
    LDA #2
    STA FCBACT                      ; FILES 2
    LEAX FCBLEN,X
    TFR X,D
    TSTB
    BEQ DKINIT_EVEN
    INCA                            ; up to a page
.if VERSION = 11
DKINIT_EVEN:
    BITA #$01
    BEQ DKINIT_PAGES
    INCA                            ; and up to an even page, as graphics pages start on one
.else
DKINIT_EVEN:
.endif
DKINIT_PAGES:
    TFR A,B
    ADDB #$18                       ; four graphics pages of 1.5K
    STB TXTTAB
    JSR GRINIT_PAGES
    LDA BEGGRP
    ADDA #$06
    STA ENDGRP
.if VERSION = 11
    JSR [DSINIT]
.endif
    BSR FDCINIT
    ANDCC #$AF                      ; clear the interrupt and fast-interrupt masks
    LDX #DSIGNON-1
    JSR STROUT1
    LDX #DKWMST
    STX RSTVEC                      ; RESET now warm starts here
    JMP COLDST_RSTFLG

;; Disk BASIC's warm start, where <RSTVEC> points: resets the disk controller, closes the files, and warm starts
;; Extended BASIC.
DKWMST:
    NOP                             ; the warm start's mark: <WARMCK> looks for it
    BSR FDCINIT
    JSR DRESET
    JMP XBWMST

;; Resets the disk controller: turns the motors off and stops any command it is running.
FDCINIT:
    CLR NMIFLG
    CLR RDYTMR
    CLR DRGRAM
    CLR DSKREG
    LDA #$D0                        ; force interrupt, with no interrupt
    STA FDCREG
    EXG A,A                         ; give it time
    EXG A,A
    LDA FDCREG                      ; and clear its interrupt
    RTS

;; Disk BASIC's command tables, which <DKINIT> copies into <COMVEC>'s third ten bytes.
DCOMVEC:
    .byte DHITOK-TK_DIR+1           ; the commands, from TK_DIR
    .dbyt DCOMWRD                   ;   their reserved words
    .dbyt DCOMMAND                  ;   and the routine that runs them
    .byte 6                         ; 6 functions, from TK_CVN
    .dbyt DFUNWRD                   ;   their reserved words
    .dbyt DFUNCTION                 ;   and the routine that runs them

;; The RAM hooks Disk BASIC takes, from <RVEC0> to <RVEC18>, which <DKINIT> fills with JMPs to these.
DVECTAB:
    .dbyt DVEC0, DVEC1, DVEC2, DVEC3, DVEC4, DVEC5, DVEC6, DVEC7, DVEC8, XVEC9, DVEC10, DVEC11, DVEC12, DVEC13
    .dbyt DVEC14, DVEC15, DVEC12, DVEC17, DVEC18

;; The sign-on message, ended by a zero.
DSIGNON:
    .byte "DISK EXTENDED COLOR BASIC 1."
.if VERSION = 10
    .byte "0", $0D, "COPYRIGHT (C) 1981 BY TANDY", $0D
.else
    .byte "1", $0D, "COPYRIGHT (C) 1982 BY TANDY", $0D
.endif
    .byte "UNDER LICENSE FROM MICROSOFT", $0D, $0D, 0

;; The commands' reserved words, in token order from <TK_DIR>.
DCOMWRD:
    KEYWORD "DIR"
    KEYWORD "DRIVE"
    KEYWORD "FIELD"
    KEYWORD "FILES"
    KEYWORD "KILL"
    KEYWORD "LOAD"
    KEYWORD "LSET"
    KEYWORD "MERGE"
    KEYWORD "RENAME"
    KEYWORD "RSET"
    KEYWORD "SAVE"
    KEYWORD "WRITE"
    KEYWORD "VERIFY"
    KEYWORD "UNLOAD"
    KEYWORD "DSKINI"
    KEYWORD "BACKUP"
    KEYWORD "COPY"
    KEYWORD "DSKI$"
    KEYWORD "DSKO$"
.if VERSION = 11
    KEYWORD "DOS"
.endif

;; The commands' routines, in token order from <TK_DIR>.
DCOMDSP:
    .dbyt DIR
    .dbyt DRIVE
    .dbyt FIELD
    .dbyt FILES
    .dbyt KILL
    .dbyt LOAD
    .dbyt LSET
    .dbyt MERGE
    .dbyt RENAME
    .dbyt RSET
    .dbyt SAVE
    .dbyt WRITE
    .dbyt VERIFY
    .dbyt UNLOAD
    .dbyt DSKINI
    .dbyt BACKUP
    .dbyt COPY
    .dbyt DSKI
    .dbyt DSKO
.if VERSION = 11
    .dbyt DOS
.endif

;; The functions' reserved words, in token order from <TK_CVN>.
DFUNWRD:
    KEYWORD "CVN"
    KEYWORD "FREE"
    KEYWORD "LOC"
    KEYWORD "LOF"
    KEYWORD "MKN$"
    KEYWORD "AS"

;; The functions' routines, in token order from <TK_CVN>. AS is part of FIELD, so as a function it is ?SN ERROR.
DFUNDSP:
    .dbyt CVN
    .dbyt FREE
    .dbyt LOC
    .dbyt LOF
    .dbyt MKN
    .dbyt SNERR

;; Runs a Disk BASIC command, or passes a token past them on to a user's table.
;;
;; In:   A = the token
DCOMMAND:
    CMPA #DHITOK
    BHI DCOMMAND_USER
    LDX #DCOMDSP
    SUBA #TK_DIR
    JMP GONE_DISPATCH
DCOMMAND_USER:
    CMPA #DHITOK
    LBLS SNERR                      ; never, after the BHI above
    JMP [COMVEC+33]                 ; a user's commands

;; Runs a Disk BASIC function, or passes a token past them on to a user's table. Each takes one argument in
;; parentheses, which is evaluated first.
;;
;; In:   B = twice the token's second byte, less $80
DFUNCTION:
    CMPB #(TK_AS-$80)*2
    BLS DFUNCTION_OURS
    JMP [COMVEC+38]                 ; a user's functions
DFUNCTION_OURS:
    SUBB #(TK_CVN-$80)*2
    PSHS B
    JSR PARENS
    PULS B
    LDX #DFUNDSP
    JMP EVAL_FN_DISPATCH

;; The error hook: closes the files, and shows Disk BASIC's errors, which the other BASICs' tables do not have.
;;
;; In:   B = the error's code
DVEC17:
    PULS Y
    JSR RSTSTK
    JSR DRESET
    PSHS B,Y
    JSR DVEC7                       ; close every file
    PULS B
    CMPB #ERR_BR
    LBLO XVEC17                     ; Color or Extended BASIC's
    LEAS 2,S
    JSR MOTOROFF
    JSR SNDOFF
    CLR DEVNUM
    JSR NEWLIN
    JSR OUTQST
    LDX #DERRTAB-ERR_BR
    JMP ERROR_SHOW

;; Disk BASIC's errors' two-letter names, from <ERR_BR>.
DERRTAB:
    .byte "BR", "DF", "OB", "WP", "FN", "FS", "AE", "FO", "SE", "VF", "ER"

;; The extension a BASIC program is saved with.
BASEXT:
    .byte "BAS"

;; The extension a name without one gets: none, which matches any.
DEFEXT:
    .byte "   "

;; The extension a data file is opened with.
DATEXT:
    .byte "DAT"

;; The extension a machine language file is saved with.
BINEXT:
    .byte "BIN"
;; The hook CLS and Extended BASIC's GET and PUT call: runs GET # and PUT #, for a random file's records, when GET
;; or PUT is followed by #. Otherwise it returns, to go on as before.
;;
;; In:   A = the character after GET or PUT
DVEC22:
    PSHS CC,X
    LDX 3,S                         ; where the hook was called from
    CMPX #GETPUT_HOOKED
    BNE DVEC22_DONE
    CMPA #'#'
    BEQ DGETPUT
DVEC22_DONE:
    PULS CC,X,PC

;; Runs GET #file[,record] and PUT #file[,record]: copies a record of a random file from the disk into its record
;; buffer, or from the buffer to the disk. Without a record number, the record after the last one is used.
;;
;; The record is found through the sectors it spans: each sector is read into the FCB's buffer, and for PUT the
;; record's part copied in, the sector written back, and the file grown by a granule when the record is past its
;; end. A record of exactly one sector goes straight between the disk and the record buffer.
;;
;; In:   VD8 = 0 for GET, nonzero for PUT
;; Errors: ?BR ERROR for record 0 or a record past 612 sectors, ?IE ERROR to GET past the end of the file
DGETPUT:
    LEAS 5,S                        ; drop the hook's return and what it saved
    JSR RANFCB
    STX FCBTMP
    CLR FCBGET,X                    ; no characters taken from the record yet
    CLR FCBGET+1,X
    CLR FCBPUT,X                    ;   or put in it
    CLR FCBPUT+1,X
    CLR FCBPOS,X
    LDA FCBDRV,X
    STA DCDRV
    JSR GETCCH
    BEQ DGETPUT_CURRENT             ; no record number: the next record
    JSR SYNCOM
.if VERSION = 10
    JSR POSINT                      ; 1.0 takes record numbers to 32767
.else
    JSR GETADR
    TFR X,D
.endif
DGETPUT_RECNUM:
    LDX FCBTMP
    STD FCBREC,X
.if VERSION = 11
DGETPUT_CURRENT:
    LDD FCBREC,X
    BEQ BRERR                       ; record 0, which 1.0 lets through
.else
DGETPUT_CURRENT:
.endif
    JSR NEXTREC
    LDD FCBRLN,X
    LDX FCBBUF,X
    PSHS A,B,X                      ; the record's bytes left to move, and where they go in the record buffer
    LEAX -2,U                       ; the record number, less one
    JSR MUL16                       ; times the record length: the record's byte in the file
    PSHS Y,U
    LDA ,S+
    BNE BRERR                       ; past 16M bytes
    PULS X                          ; X = the sector it is in, from the file's start
    PULS B                          ; B = the byte in that sector
DGETPUT_SECTOR:
    CMPX #(TRKMAX-1)*SECMAX
    BLO DGETPUT_CHECK               ; a file has at most 612 sectors
;; Raises ?BR ERROR: a bad record number.
BRERR:
    LDB #ERR_BR
    JMP ERROR
DGETPUT_CHECK:
    LDU FCBTMP
    CMPX FCBSOF,U
    LBEQ DGETPUT_MOVE               ; that sector is in the buffer already
    PSHS B,X
    LDA FCBFLG,U
    BEQ DGETPUT_FIND
    CLR FCBFLG,U                    ; the buffer holds a PUT's data:
    LDB #3
    BSR FCBIO                       ;   write it first
DGETPUT_FIND:
    LDD 1,S
    JSR SECGRAN                       ; the sector's granule in the file
    PSHS B
    JSR MUL9                       ; times nine
    NEGB
    ADDB 3,S
    INCB                            ; the sector in that granule, from 1
    STB FCBSEC,U
    LDB FCBFGR,U
    JSR DRVFAT
    LEAU FATCON,X
    LDA ,S
    INCA
DGETPUT_GRANULE:
    LEAX ,U                         ; follow the file's granules in the FAT
    ABX
    DECA
    BEQ DGETPUT_FOUND
    STB ,S
    LDB ,X
    CMPB #$C0
    BLO DGETPUT_GRANULE             ; not the last
    LDB ,S                          ; the file ends before the record
    TST VD8
    BNE DGETPUT_GROW                ; PUT grows it
DGETPUT_IE:
    LDB #ERR_IE
    JMP ERROR

;; Reads or writes the sector an FCB is at, through its buffer.
;;
;; In:   B = DSKCON's operation, 2 to read or 3 to write; U = the FCB
FCBIO:
    LEAX FCBCON,U
;; Reads or writes the sector an FCB is at, through the buffer at X.
;;
;; In:   B = DSKCON's operation, 2 to read or 3 to write; U = the FCB; X = the buffer
FCBIO_BUFFER:
    STB DCOPC
    STX DCBPT
    LEAX ,U
    JSR FCBTS
    JMP DSKIO

DGETPUT_GROW:
    PSHS A,X                        ; add free granules to the file until it reaches the record
    JSR FREEGRAN
    TFR A,B
    PULS A,U
    STB ,U
    DECA
    BNE DGETPUT_GROW
    PSHS B,X
    JSR FATWRITE                       ; write the FAT
    PULS B,X
DGETPUT_FOUND:
    LEAS 1,S
    LDU FCBTMP
    STB FCBCGR,U
    LDA #$FF
    STA FCBSOF,U                    ; no sector in the buffer
    LDA ,X
    CMPA #$C0
    BLO DGETPUT_READ                ; not the file's last granule
    ANDA #$3F
    CMPA FCBSEC,U
    BHS DGETPUT_READ                ; the sector is within the file
    LDA VD8
    BEQ DGETPUT_IE                  ; GET past the end
    LDA FCBSEC,U
    ORA #$C0
    STA ,X                          ; PUT: the file now ends at this sector
    JSR FATCHG
    LDX FCBRLN,U
    CMPX #SECLEN
    BNE DGETPUT_EMPTY
    CMPX FCBLST,U
    BEQ DGETPUT_READ
    LDA #$81                        ; a whole sector, for the directory
    .byte $21                       ; BRN: skips the CLRA
DGETPUT_EMPTY:
    CLRA
    CLRB
    STD FCBLST,U
DGETPUT_READ:
    LDB #2
    LDX FCBRLN,U
    CMPX #SECLEN
    BNE DGETPUT_PART
    LEAS 7,S                        ; records of a sector go straight to or from the record buffer
    LDX FCBBUF,U
    LDA VD8
    BEQ DGETPUT_WHOLE
    LDB #3
DGETPUT_WHOLE:
    JMP FCBIO_BUFFER
DGETPUT_PART:
    JSR FCBIO                       ; read the sector into the FCB's buffer
    PULS B,X
    STX FCBSOF,U
DGETPUT_MOVE:
    PSHS B
    JSR DRVFAT
    LEAX FATCON,X
    LDB FCBCGR,U
    ABX
    LDA ,X
    CMPA #$C0
    BLO DGETPUT_COPY                ; not the file's last granule
    ANDA #$3F
    CMPA FCBSEC,U
    BNE DGETPUT_COPY                ;   or not its last sector
    LDD FCBLST,U
    ANDA #$7F
    PSHS A,B
    CLRA
    LDB 2,S
    ADDD 3,S                        ; where the record ends
    CMPD ,S++
    BLS DGETPUT_COPY                ; within the bytes the file uses
    TST VD8
    LBEQ DGETPUT_IE                 ; GET past the end
.if VERSION = 10
    ANDA #$01                       ; 1.0 keeps the low nine bits, which can pass a sector
.else
    CMPD #SECLEN
    BLS DGETPUT_LAST
    LDD #SECLEN                     ; the file uses at most the whole sector
.endif
DGETPUT_LAST:
    ORA #$80                        ; and the directory's count must change
    STD FCBLST,U
DGETPUT_COPY:
    PULS B
    LEAX FCBCON,U
    ABX                             ; the record's place in the buffer
    LDU 2,S
    PSHS B
    LDA #$FF                        ; D = the bytes left in the sector, negated
    ADDD 1,S
    BHS DGETPUT_FITS                ; the rest of the record fits
    STD 1,S                         ; the bytes left after this sector
    PULS B
    NEGB                            ; the rest of the sector
    BRA DGETPUT_XFER
DGETPUT_FITS:
    LDB 2,S
    CLR 1,S
    CLR 2,S
    LEAS 1,S
DGETPUT_XFER:
    LDA VD8
    BEQ DGETPUT_GET
    EXG X,U                         ; PUT copies from the record buffer
DGETPUT_GET:
    JSR MOVEXU
    STU 2,S
    LDU FCBTMP
    LDA VD8
    BEQ DGETPUT_NEXT
    STA FCBFLG,U                    ; the buffer now holds a PUT's data
    STX 2,S
DGETPUT_NEXT:
    LDX FCBSOF,U
    LEAX 1,X                        ; the next sector
    CLRB
    LDU ,S
    LBNE DGETPUT_SECTOR             ; while bytes are left
    PULS A,B,X,PC
;; The OPEN hook: runs OPEN mode,#file,name[,length] for a disk file, a file number from 1. Other devices go on to
;; Color BASIC's OPEN.
;;
;; The mode is I for sequential input, O for sequential output, and R or D for a random file, whose records are
;; the length given, or 256 bytes. A name without an extension gets DAT.
DVEC0:
    LEAS 2,S                        ; not back to Color BASIC's OPEN
    JSR FRMEVL
    JSR FIRSTC                      ; the mode's first letter
    PSHS B
    JSR COMDEV
    TSTB
    LBLE OPEN_NAME                  ; not a disk file
    PULS A
    PSHS A,B
    CLR DEVNUM
    JSR SYNCOM
    LDX #DATEXT
    JSR GETFNAM_DEF
    LDD #$01FF
    STD DFLTYP                      ; a data file, in ASCII
    LDX #SECLEN
    JSR GETCCH
    BEQ DVEC0_LENGTH
    JSR SYNCOM
    JSR POSINT
    LDX FPA0+2
DVEC0_LENGTH:
    STX DFFLEN
    LBEQ FCERR                      ; a length of 0
    JSR NAMEND_CHECK
    PULS A,B
;; Opens a disk file, its name and extension in <DNAMBF> and its type and ASCII flag in <DFLTYP> and <DASCFL>.
;;
;; An input file must exist; an output file replaces one that does; a random file is made when it does not
;; exist, and gets <DFFLEN>-byte records.
;;
;; In:   A = the mode, I, O, R or D; B = the file number; DCDRV = the drive
;; Errors: ?AO ERROR when the file number is open, ?NE ERROR for an input file not found, ?FM ERROR for another
;; mode, ?OB ERROR when the random file buffer space is full, ?DF ERROR when the directory is
DOPEN:
    PSHS A
    JSR FILEFCB
    LBNE AOERR
    STX FCBTMP
    JSR FATLOAD
    JSR DIRSRCH
    PULS B
    LDA #INPFIL
    PSHS A
    CMPB #'I'
    BNE DOPEN_OUTPUT
    JSR FILECHK
    JSR OPENCHK
    LDX FNDDIR
    LDD DIRTYP,X
    STD DFLTYP
    BSR FCBINPUT
    JSR FCBREAD                       ; read the first sector
DOPEN_DONE:
    JSR DRVFAT
    INC <<FAT0,X                    ; one more file open on the drive
    LDX FCBTMP
    PULS A
    STA <<FCBTYP,X
    RTS
DOPEN_OUTPUT:
    ASL ,S                          ; OUTFIL
    CMPB #'O'
    BNE DOPEN_RANDOM
    TST FNDSEC
    BEQ DOPEN_NEW
    JSR KILLFILE                       ; it exists: kill it, and reuse its entry
    LDA FNDSEC
    STA NEWSEC
    LDX FNDDIR
    STX NEWDIR
.if VERSION = 10
DOPEN_NEW:
    BSR NEWFILE
.else
DOPEN_NEW:
    JSR NEWFILE
.endif
    BSR FCBINIT
    BRA DOPEN_DONE
DOPEN_RANDOM:
    CMPB #'R'
    BEQ DOPEN_DIRECT
    CMPB #'D'
    LBNE FMERR
DOPEN_DIRECT:
    ASL ,S                          ; RANFIL
    LDD RNBFAD
    PSHS A,B                        ; the record buffer's start
    ADDD DFFLEN
    BLO OBERR
    CMPD FCBADR
    BLS DOPEN_ROOM
;; Raises ?OB ERROR: no room for the record buffer.
OBERR:
    LDB #ERR_OB
    JMP ERROR
DOPEN_ROOM:
    PSHS A,B                        ; and its end
    TST FNDSEC
    BNE DOPEN_EXISTS
    BSR NEWFILE
.if VERSION = 11
    BRA DOPEN_FCB
DOPEN_EXISTS:
    LDA #$FF                        ; no type matches: ?AO ERROR if it is open at all
    JSR OPENCHK
.else
DOPEN_EXISTS:
.endif
DOPEN_FCB:
    BSR FCBINPUT
    COM FCBSOF,X                    ; no sector in the buffer
    INC FCBREC+1,X                  ; record 1
    PULS A,B,U
    STD RNBFAD
    STU FCBBUF,X
    LDU DFFLEN
    STU FCBRLN,X
    BRA DOPEN_DONE

;; Sets up an FCB for a file found in the directory: as <FCBINIT> does, and the bytes its last sector uses.
;;
;; In:   FCBTMP = the FCB; FNDDIR = its directory entry
;; Out:  X = the FCB
FCBINPUT:
    BSR FCBINIT
    LDU FNDDIR
    LDU DIRLST,U
    STU FCBLST,X
    RTS

;; Sets up an FCB for the file the directory search found: clears its control bytes, then sets its drive, its
;; first and current granules, and its directory entry's number.
;;
;; In:   FCBTMP = the FCB; DCDRV = the drive; FNDSEC, FNDDIR and FNDGRN = the file's entry
;; Out:  X = the FCB
FCBINIT:
    LDX FCBTMP
    LDB #FCBCON
FCBINIT_CLEAR:
    CLR ,X+
    DECB
    BNE FCBINIT_CLEAR
    LDX FCBTMP
    LDA DCDRV
    STA FCBDRV,X
    LDA FNDGRN
    STA FCBFGR,X
    STA FCBCGR,X
    LDB FNDSEC
    SUBB #3                         ; the directory starts at sector 3
    ASLB
    ASLB
    ASLB                            ; eight entries to a sector
    PSHS B
    LDD FNDDIR
    SUBD #DBUF0
    LDA #8
    MUL                             ; the entry within the sector, in A
    ADDA ,S+
    STA FCBDIR,X
    RTS

;; Makes a directory entry for a new file in the first unused one: names it from <DNAMBF>, sets its type and ASCII
;; flag, gives it a free granule, and writes the sector back. Then counts the change to the FAT, as <FATCHG> does.
;;
;; Out:  FNDSEC = the new file's directory sector; FNDDIR = its entry; FNDGRN = its first granule
;; Errors: ?DF ERROR when the directory has no unused entry
NEWFILE:
    LDB #ERR_DF
    LDA NEWSEC
    LBEQ ERROR
    STA FNDSEC
    STA DSEC
    LDB #2                          ; read the entry's sector
    STB DCOPC
    JSR DSKIO
    LDX NEWDIR
    STX FNDDIR
    LEAU ,X
    LDB #DIRLEN
NEWFILE_CLEAR:
    CLR ,X+
    DECB
    BNE NEWFILE_CLEAR
    LDX #DNAMBF
    LDB #11
    JSR MOVEXU                      ; the name and extension
    LDD DFLTYP
    STD <<0,U                       ; the type and ASCII flag, at DIRTYP
    LDB #33                         ; from the granules beside the directory
    JSR FREEGRAN
    STA FNDGRN
    STA 2,U                         ; the first granule, at DIRGRN
    LDB #3                          ; write the sector back
    STB DCOPC
    JSR DSKIO
;; Counts a change to the drive's FAT, and writes the FAT to the disk once <WFATVL> changes have built up.
;;
;; In:   DCDRV = the drive
FATCHG:
    PSHS A,B,X,U
    JSR DRVFAT
    INC FAT1,X
    LDA FAT1,X
    CMPA WFATVL
    BLO FATCHG_DONE
    JSR FATWRITE
FATCHG_DONE:
    PULS A,B,X,U,PC
;; The console in hook: reads a character from a disk file, when the device is one.
;;
;; Out:  A = the character; CINBFL = nonzero when the file has none left
DVEC4:
    LDA DEVNUM
    LBLE XVEC4                      ; not a disk file
    LEAS 2,S                        ; not back to Color BASIC's CONIN
;; Reads a character from the open disk file <DEVNUM>: from a random file's record buffer, or from a sequential
;; file's sector buffer, reading the file's next sector when it is used up.
;;
;; Out:  A = the character; CINBFL = nonzero when the file has none left
DCONIN:
    PSHS B,X
    CLR CINBFL
    LDX #FCBV1-2
    LDB DEVNUM
    ASLB
    LDX B,X                         ; the file's FCB
    LDB ,X
    CMPB #RANFIL
    BNE DCONIN_SEQ
    LDD FCBGET,X                    ; a random file: the record's next character
    CMPD FCBRLN,X
    BHS DCONIN_EMPTY                ; the record is used up
    ADDD #1
    STD FCBGET,X
    LDX FCBBUF,X
    LEAX D,X
    LDA -1,X
    PULS B,X,PC
DCONIN_SEQ:
    LDB FCBCFL,X
    BEQ DCONIN_LEFT
    LDA FCBCDT,X                    ; the character kept from last time
    CLR FCBCFL,X
    PULS B,X,PC
DCONIN_LEFT:
    LDB FCBDFL,X
    BEQ DCONIN_CHAR
DCONIN_EMPTY:
    COM CINBFL                      ; none left
    PULS B,X,PC
DCONIN_CHAR:
    LDB FCBCPT,X
    INC FCBCPT,X
    DEC FCBLFT,X
    BEQ DCONIN_REFILL               ; the buffer's last character
    ABX
    LDA FCBCON,X
    PULS B,X,PC
DCONIN_REFILL:
    PSHS Y,U
    CLRA
    LEAU D,X
    LDA FCBCON,U
    PSHS A                          ; keep it, then read the next sector
    CLR FCBCPT,X
    LDA FCBDRV,X
    STA DCDRV
    BSR FCBREAD
    PULS A,Y,U
    PULS B,X,PC

;; Reads a sequential input file's next sector into its FCB's buffer, following the file's granules in the FAT,
;; and sets the characters the buffer holds: 256, or what the file's last sector uses, setting <FCBDFL> after it.
;;
;; In:   X = the FCB; DCDRV = its drive
;; Errors: ?FS ERROR when the FAT says a granule uses more than nine sectors
FCBREAD:
    LDA FCBSEC,X
FCBREAD_NEXT:
    INCA
    PSHS A
    CMPA #9
    BLS FCBREAD_SECTOR
    CLRA                            ; past the granule's last sector
FCBREAD_SECTOR:
    STA FCBSEC,X
    LDB FCBCGR,X
    LEAU ,X
    JSR DRVFAT
    ABX
    LDB FATCON,X                    ; the granule after this one
    LEAX ,U
    CMPB #$C0
    BHS FCBREAD_LAST                ; this is the file's last
    PULS A
    SUBA #10
    BNE FCBREAD_READ
    STB FCBCGR,X                    ; on to the next granule
    BRA FCBREAD_NEXT
FCBREAD_LAST:
    ANDB #$3F                       ; the sectors the last granule uses
    CMPB #9
    BLS FCBREAD_LEFT
;; Raises ?FS ERROR: a bad file structure.
FSERR:
    LDB #ERR_FS
    JMP ERROR
FCBREAD_LEFT:
    SUBB ,S+
    BLO FCBREAD_END                 ; past the file's last sector
    TFR B,A
FCBREAD_READ:
    PSHS A                          ; the sectors after this one, in its last granule
    BSR NEXTREC
    LDA #2
    STA DCOPC
    JSR FCBTS
    LEAU FCBCON,X
    STU DCBPT
    JSR DSKIO
    CLR FCBLFT,X                    ; 256 characters
    LDB ,S+
    BNE FCBREAD_DONE
    LDD FCBLST,X                    ; the file's last sector
    BNE FCBREAD_COUNT
FCBREAD_END:
    CLRB
    COM FCBDFL,X                    ; no data left after this
FCBREAD_COUNT:
    STB FCBLFT,X
FCBREAD_DONE:
    RTS

;; Counts a record or sector more in an FCB.
;;
;; In:   X = the FCB
NEXTREC:
    LDU FCBREC,X
    LEAU 1,U
    STU FCBREC,X
    RTS

;; Searches the directory for the file named in <DNAMBF>, and notes the first unused entry on the way.
;;
;; In:   DCDRV = the drive
;; Out:  FNDSEC = the sector of the file's entry, or 0 when it is not there; FNDDIR and FNDGRN = where its
;;       entry is in DBUF0 and its first granule; NEWSEC and NEWDIR = the first unused entry, or NEWSEC 0
;;       when there is none
DIRSRCH:
    CLR FNDSEC
    CLR NEWSEC
    LDD #$1102                      ; track 17, read
    STA DCTRK
    STB DCOPC
    LDB #3                          ; from sector 3
DIRSRCH_SECTOR:
    STB DSEC
    LDU #DBUF0
    STU DCBPT
    JSR DSKIO
DIRSRCH_ENTRY:
    STU FNDDIR
    LEAY ,U
    LDA ,U
    BNE DIRSRCH_USED
    BSR DIRSRCH_FREE                ; a killed file's entry
DIRSRCH_NAME:
    LDX #DNAMBF
DIRSRCH_CHAR:
    LDA ,X+
    CMPA ,U+
    BNE DIRSRCH_NEXT
    CMPX #DNAMBF+11
    BNE DIRSRCH_CHAR
    STB FNDSEC                      ; found
    LDA 2,U                         ; DIRGRN
    STA FNDGRN
    RTS
DIRSRCH_NEXT:
    LEAU DIRLEN,Y
    CMPU #DBUF0+SECLEN
    BNE DIRSRCH_ENTRY
    INCB
    CMPB #11
    BLS DIRSRCH_SECTOR              ; to the directory's last sector
    RTS
DIRSRCH_USED:
    COMA
    BNE DIRSRCH_NAME                ; not $FF: a file's entry
DIRSRCH_FREE:
    LDA NEWSEC                      ; an unused entry: note it, if it is the first
    BNE DVEC12
    STB NEWSEC
    STU NEWDIR
;; The hooks Disk BASIC leaves doing nothing: <RVEC12> and <RVEC16>.
DVEC12:
    RTS

;; Raises ?NE ERROR unless the directory search found the file.
FILECHK:
    LDB #ERR_NE
    TST FNDSEC
    BNE DVEC12
    JMP ERROR

;; Runs KILL "name": deletes a file, freeing its granules.
;;
;; Errors: ?NE ERROR when it does not exist, ?AO ERROR when it is open
KILL:
    JSR GETFNAM
    JSR NAMEND_CHECK
    JSR FATLOAD
    BSR DIRSRCH
    BSR FILECHK
;; Deletes the file the directory search found: marks its entry killed, frees its granules in the FAT, and writes
;; the FAT.
;;
;; Errors: ?AO ERROR when it is open
KILLFILE:
    LDA #$FF                        ; no type matches: ?AO ERROR if it is open at all
    JSR OPENCHK
    LDX FNDDIR
    CLR DIRNAM,X                    ; killed
    LDB #3                          ; write the directory sector back
    STB DCOPC
    JSR DSKIO
    LDB DIRGRN,X
KILLFILE_FREE:
    BSR DRVFAT
    LEAX FATCON,X
    ABX
    LDB ,X                          ; the granule after this one
    LDA #$FF
    STA ,X                          ; is free now
    CMPB #$C0
    BLO KILLFILE_FREE
;; Writes the drive's FAT to sector 2 of the directory track, through <DBUF0>: its granules' bytes, and zeros to
;; the sector's end. Its six control bytes stay in RAM.
;;
;; In:   DCDRV = the drive
FATWRITE:
    LDU #DBUF0
    STU DCBPT
    LDD #$1103                      ; track 17, write
    STA DCTRK
    STB DCOPC
    LDB #2
    STB DSEC
    BSR DRVFAT
    CLR FAT1,X                      ; no changes waiting
    LEAX FATCON,X
    LDB #GRANMX
    JSR MOVEXU
.if VERSION = 10
FATWRITE_CLEAR:
    CLR ,X+                         ; 1.0 clears just the byte after the FAT in RAM, not the rest of the sector
    CMPX #DBUF0+SECLEN
.else
FATWRITE_CLEAR:
    CLR ,U+
    CMPU #DBUF0+SECLEN
    BNE FATWRITE_CLEAR
.endif
    JMP DSKIO

;; Finds the FCB of the file <DEVNUM>.
;;
;; Out:  X = the FCB; the flags from its file type, so Z when it is closed
DEVFCB:
    PSHS B
    LDB DEVNUM
    .byte $8C                       ; CMPX #: skips the PSHS below
;; Finds the FCB of a file.
;;
;; In:   B = the file number
;; Out:  X = the FCB; the flags from its file type, so Z when it is closed
FILEFCB:
    PSHS B
    ASLB
    LDX #FCBV1-2
    LDX B,X
    LDB <<FCBTYP,X
    PULS B,PC

;; Finds the FAT in RAM for the drive <DCDRV>.
;;
;; Out:  X = the FAT
DRVFAT:
    PSHS A,B
    LDA DCDRV
    LDB #FATLEN
    MUL
    LDX #FATBL0
    LEAX D,X
    PULS A,B,PC

;; Sets DSKCON's track and sector to where an FCB is: its granule's track, skipping the directory's, and the
;; sector in it.
;;
;; In:   X = the FCB
FCBTS:
    LDB FCBCGR,X
    LSRB                            ; two granules to a track
    STB DCTRK
    CMPB #17
    BLO FCBTS_GRANULE
    INC DCTRK                       ; past the directory's
FCBTS_GRANULE:
    ASLB
    NEGB
    ADDB FCBCGR,X                   ; 0 for the track's first granule, 1 for its second
    BSR MUL9                       ; times nine
    ADDB FCBSEC,X
    STB DSEC
    RTS
;; Multiplies D by nine: sectors in that many granules.
;;
;; In:   D = the number
;; Out:  D = nine times it
MUL9:
    PSHS A,B
    ASLB
    ROLA
    ASLB
    ROLA
    ASLB
    ROLA
    ADDD ,S++
    RTS

;; Divides a count of sectors by nine: the whole granules in them, 0 to 67. It divides by 90, then multiplies by
;; ten and works back, which is quicker.
;;
;; In:   D = the sectors
;; Out:  D = the granules
SECGRAN:
    CLR ,-S
SECGRAN_90:
    INC ,S
    SUBD #90
    BPL SECGRAN_90
    LDA ,S                          ; the quotient, plus one
    STB ,S                          ; and the remainder, less 90
    LDB #10
    MUL
    PULS A
SECGRAN_FIX:
    DECB                            ; a granule less for each nine sectors short
    ADDA #9
    BMI SECGRAN_FIX
    CLRA
SECGRAN_DONE:
    RTS

;; Reads the drive's FAT into RAM, unless a file is open on it, when the one in RAM is newer.
;;
;; In:   DCDRV = the drive
FATLOAD:
    BSR DRVFAT
    TST <<FAT0,X
    BNE SECGRAN_DONE
    CLR FAT1,X                      ; no changes waiting
    LEAU FATCON,X
    LDX #DBUF0
    STX DCBPT
    LDD #$1102                      ; track 17, read
    STA DCTRK
    STB DCOPC
    LDB #2                          ; sector 2
    STB DSEC
    JSR DSKIO
    LDB #GRANMX
    JMP MOVEXU

;; Takes the free granule nearest a granule, looking a track up and down in turn from its track, and marks it the
;; last of a file, using no sectors yet.
;;
;; In:   B = the granule to look from; DCDRV = the drive
;; Out:  A = the granule
;; Errors: ?DF ERROR when no granule is free
FREEGRAN:
    BSR DRVFAT
    LEAX FATCON,X
    CLRA                            ; the granules looked at
    ANDB #$FE                       ; from the track's first
    CLR ,-S                         ; which way to look next
FREEGRAN_TRY:
    COM B,X
    BEQ FREEGRAN_FOUND              ; $FF: free
    COM B,X
    INCA
    CMPA #GRANMX
    BHS DFERR                       ; all of them
    INCB
    BITB #$01
    BNE FREEGRAN_TRY                ; the track's second granule
    PSHS A,B
    SUBB #2
    COM 2,S
    BNE FREEGRAN_UP
    SUBB ,S+                        ; a track further down
    BPL FREEGRAN_NEXT
    LDB ,S                          ; past the first: look up instead
FREEGRAN_TURN:
    COM 1,S
FREEGRAN_NEXT:
    LEAS 1,S
    BRA FREEGRAN_TRY
FREEGRAN_UP:
    ADDB ,S+                        ; a track further up
    CMPB #GRANMX
    BLO FREEGRAN_NEXT
    LDB ,S                          ; past the last: look down instead
    SUBB #4
    BRA FREEGRAN_TURN
;; Raises ?DF ERROR: the disk is full.
DFERR:
    LDB #ERR_DF
    JMP ERROR
FREEGRAN_FOUND:
    LEAS 1,S
    TFR B,A
    ABX
    LDB #$C0                        ; the last granule, no sectors used
    STB ,X
FREEGRAN_DONE:
    RTS

;; Checks that the file the directory search found is not open, or is open only as the same type: an FCB is the
;; file's when its drive and first granule are.
;;
;; In:   A = the file type it is being opened as, or $FF to allow none
;; Errors: ?AO ERROR when it is open otherwise
OPENCHK:
    PSHS A
    LDB FCBACT
    INCB                            ; the user files and the system's
OPENCHK_FILE:
    JSR FILEFCB
    BEQ OPENCHK_NEXT                ; closed
    LDA DCDRV
    CMPA FCBDRV,X
    BNE OPENCHK_NEXT
    LDU FNDDIR
    LDA DIRGRN,U
    CMPA FCBFGR,X
    BNE OPENCHK_NEXT
    LDA <<FCBTYP,X
    CMPA ,S
    LBNE AOERR
OPENCHK_NEXT:
    DECB
    BNE OPENCHK_FILE
    PULS A,PC

;; Reads #file and finds its FCB, which must be a random file's.
;;
;; Out:  X = the FCB
;; Errors: ?FC ERROR for a device that is not a disk file, ?NO ERROR when it is not open, ?FM ERROR when it is
;; not random
RANFCB:
    JSR GETDEV
    CLR DEVNUM
    TSTB
    LBLE FCERR
    JSR FILEFCB
    LDA <<FCBTYP,X
    LBEQ NOTOPN
    CMPA #RANFIL
    BEQ FREEGRAN_DONE
RANFCB_FM:
    JMP FMERR

;; The input device check hook: a disk file must be open for input, or random.
;;
;; Errors: ?NO ERROR when it is not open, ?FM ERROR when it is open for output
DVEC5:
    LDA #INPFIL
    .byte $8C                       ; CMPX #: skips the LDA below
;; The output device check hook: a disk file must be open for output, or random.
;;
;; In 1.1, INPUT # from a random file, through <DVEC5>, also reads INPUT's prompt here, and goes on at
;; <INPDEV_LINE>, past INPUT's own reading of it.
;;
;; Errors: ?NO ERROR when it is not open, ?FM ERROR when it is open for input
DVEC6:
    LDA #OUTFIL
    TST DEVNUM
    BLE FREEGRAN_DONE               ; not a disk file
    STX ,S                          ; not back to the check, but X saved there
    JSR DEVFCB
.if VERSION = 10
    PSHS A
.else
    PSHS A,B
.endif
    LDA <<FCBTYP,X
    LBEQ NOTOPN
    CMPA #RANFIL
    BEQ DVEC6_RANDOM
    CMPA ,S
    BNE RANFCB_FM
.if VERSION = 10
DVEC6_RANDOM:
    PULS A,X,PC
.else
DVEC6_DONE:
    PULS A,B,X,PC
DVEC6_RANDOM:
    LDX 4,S
    CMPX #INPDEV_FILE
    BNE DVEC6_DONE                  ; not INPUT #
    JSR SYNCOM
    CMPA #'"'
    BNE DVEC6_INPUT
    JSR STRLIT                      ; a prompt: read past it, and the ;
    JSR FREFAC
    LDB #';'
    JSR SYNCHR
DVEC6_INPUT:
    LDX #INPDEV_LINE
    STX 4,S
    PULS A,B,X,PC
.endif

;; The device number check hook: a file number up to <FCBACT> is a disk file.
;;
;; In:   B = the device number
;; Errors: ?DN ERROR past <FCBACT>
DVEC1:
.if VERSION = 10
    BLE FREEGRAN_DONE
.else
    BLE DVEC11_DONE
.endif
    CMPB FCBACT
    LBHI DNERR
    PULS X,PC                       ; past Color BASIC's own check

;; The print parameters hook: a disk file has 16-column comma fields, a line of 256, and its FCB's print position.
DVEC2:
    TST DEVNUM
.if VERSION = 10
    BLE FREEGRAN_DONE
.else
    BLE DVEC11_DONE
.endif
    LEAS 2,S
    PSHS A,B,X
    CLR PRTDEV
    JSR DEVFCB
    LDB FCBPOS,X
    CLRA
    LDX #$1000
    JMP SETPRM_STORE

;; The BREAK check hook: a disk file is not checked for BREAK.
DVEC11:
    TST DEVNUM
    BLE DVEC11_DONE
    LEAS 2,S
DVEC11_DONE:
    RTS
.if VERSION = 11
;; The statement loop's hook, which 1.1 adds: runs every statement from here on, as Extended BASIC's <XVEC20> does,
;; but scans the keyboard for BREAK only while a key is down, which runs programs faster.
DVEC20:
    LEAS 2,S                        ; never return to <NEWSTT>
DVEC20_NEXT:
    ANDCC #$AF                      ; clear the interrupt and fast-interrupt masks
    CLR PIA0+2                      ; all the keyboard's columns
    LDA PIA0
    COMA
    ANDA #$7F
    BEQ DVEC20_KEYS                 ; no key down
    JSR ISCNTC
DVEC20_KEYS:
    LDX CHARAD
    STX TINPTR
    LDA ,X+
    BEQ DVEC20_LINE                 ; the line has ended
    CMPA #':'
    BEQ DVEC20_RUN                  ; the next statement on the line
    JMP SNERR
DVEC20_LINE:
    LDA ,X++                        ; the next line's link
    STA ENDFLG
    BNE DVEC20_NUMBER
    JMP ENDPRG                      ; past the last line: END
DVEC20_NUMBER:
    LDD ,X+
    STD CURLIN
    STX CHARAD                      ; GETNCH starts after the number
    LDA TRCFLG
    BEQ DVEC20_RUN
    LDA #'['
    JSR PUTCHR
    LDA CURLIN                      ; B still has its low byte
    JSR LINPRT
    LDA #']'
    JSR PUTCHR
DVEC20_RUN:
    JSR GETNCH
    TFR CC,B
    CMPA #TK_CSAVE
    BNE DVEC20_CLOAD
    JMP XVEC20_CSAVE
DVEC20_CLOAD:
    CMPA #TK_CLOAD
    BNE DVEC20_GONE
    JMP XVEC20_CLOAD
DVEC20_GONE:
    TFR B,CC                        ; the flags GETNCH left
    JSR GONE2
    BRA DVEC20_NEXT
.endif

;; The EOF hook: EOF(file) for a disk file is -1 once a sequential input file has no characters left, else 0.
;;
;; Errors: ?FM ERROR for a random file
DVEC14:
    LEAS 2,S                        ; not back to Color BASIC's EOF
    LDA DEVNUM
    PSHS A
    JSR SETDEV
    JSR CHKIN
    TST DEVNUM
    LBLE EOF_CHECK                  ; not a disk file
    JSR DEVFCB
    LDB <<FCBTYP,X
    CMPB #RANFIL
.if VERSION = 10
    BEQ RANFCB_FM
.else
    LBEQ FMERR
.endif
    CLRB
    LDA FCBCFL,X
    BNE DVEC14_DONE                 ; a character kept: not the end
    LDB FCBDFL,X
DVEC14_DONE:
    JMP EOF_RESULT

;; Reads a file name from the program, with no default extension.
GETFNAM:
    LDX #DEFEXT
;; Reads a file name from the program, as a string: [drive:]name[.ext][:drive], where the drive is 0 to 3 and /
;; may stand for the point. The name goes into <DNAMBF> and the extension into <DEXTBF>, both padded with spaces.
;;
;; In:   X = the extension to use when the name has none
;; Out:  DCDRV = the drive, or DEFDRV when the name has none
;; Errors: ?FN ERROR for a bad name
GETFNAM_DEF:
    CLR ,-S                         ; no drive yet
    LDA DEFDRV
    STA DCDRV
    LDU #DNAMBF
    LDD #$2008                      ; eight spaces
GETFNAM_BLANK:
    STA ,U+
    DECB
    BNE GETFNAM_BLANK
    LDB #3
    JSR MOVEXU                      ; the default extension
    JSR FRMSTR
    LEAU ,X
    CMPB #2
    BLO GETFNAM_PARSE
    LDA 1,U
    CMPA #':'
    BNE GETFNAM_PARSE
    LDA ,U
    CMPA #'0'
    BLO GETFNAM_PARSE
    CMPA #'3'
    BHI GETFNAM_PARSE
    BSR GETFNAM_DRVNUM              ; the drive first
GETFNAM_PARSE:
    LDX #DNAMBF
    INCB
GETFNAM_CHAR:
    DECB
    BNE GETFNAM_NAME
    LEAS 1,S                        ; the end
GETFNAM_CHECK:
    CMPX #DNAMBF
    BNE GETFNAM_OK                  ; the name is not empty
;; Raises ?FN ERROR: a bad file name.
FNERR:
    LDB #ERR_FN
    JMP ERROR
GETFNAM_NAME:
    LDA ,U+
    CMPA #'.'
    BEQ GETFNAM_EXTN
    CMPA #'/'
    BEQ GETFNAM_EXTN
    CMPA #':'
    BEQ GETFNAM_DRIVE
    CMPX #DEXTBF
    BEQ FNERR                       ; more than eight characters
    BSR GETFNAM_STORE
    BRA GETFNAM_CHAR
GETFNAM_DRIVE:
    BSR GETFNAM_CHECK
    BSR GETFNAM_DRVNUM
    TSTB
    BNE FNERR                       ; the drive must end it
GETFNAM_DONE:
    PULS A,PC
GETFNAM_DRVNUM:
    COM 2,S
    BEQ FNERR                       ; a second drive
    LDA ,U++
    SUBB #2
    SUBA #'0'
    BLO FNERR
    CMPA #3
    BHI FNERR
    STA DCDRV
    RTS
GETFNAM_EXTN:
    BSR GETFNAM_CHECK
    LDX #DEXTBF+3
    LDA #' '
GETFNAM_PAD:
    STA ,-X                         ; no default extension now
    CMPX #DEXTBF
    BNE GETFNAM_PAD
GETFNAM_EXTCHAR:
    DECB
    BEQ GETFNAM_DONE
    LDA ,U+
    CMPA #':'
    BEQ GETFNAM_DRIVE
    CMPX #DEXTBF+3
    BEQ FNERR                       ; more than three characters
    BSR GETFNAM_STORE
    BRA GETFNAM_EXTCHAR
GETFNAM_STORE:
    STA ,X+
    BEQ FNERR                       ; a name may not hold 0, a point, / or $FF
    CMPA #'.'
    BEQ FNERR
    CMPA #'/'
    BEQ FNERR
    INCA
    BEQ FNERR
GETFNAM_OK:
    RTS

;; Runs SAVE "name"[,A]: saves the program, as a BASIC file with extension BAS: crunched, or with A as text, as
;; LIST shows it. SAVEM saves memory instead.
SAVE:
    CMPA #'M'
    LBEQ SAVEM
    BSR BASNAM
    LDX ZERO
    STX DFLTYP                      ; a BASIC program, crunched
    JSR GETCCH
    BEQ SAVE_BINARY
    JSR SYNCOM
    LDB #'A'
    JSR SYNCHR
    BNE GETFNAM_OK                  ; more after it: ?SN ERROR from the statement loop
    COM DASCFL
    BSR SYSOUT
    CLRA
    JMP LIST                        ; the whole program, to the file

;; Opens the system's FCB for output, as the file after the user's.
SYSOUT:
    LDA #'O'
    .byte $8C                       ; CMPX #: skips the LDA below
;; Opens the system's FCB for input, as the file after the user's.
SYSIN:
    LDA #'I'
    LDB FCBACT
    INCB
    STB DEVNUM
    JMP DOPEN

SAVE_BINARY:
    BSR SYSOUT
    LDA #$FF                        ; a crunched program's mark
    JSR DCONOUT
    LDD VARTAB
    SUBD TXTTAB                     ; its length
    JSR DCONOUT
    TFR B,A
    JSR DCONOUT
    LDX TXTTAB
SAVE_BYTE:
    LDA ,X+
    JSR DCONOUT
    CMPX VARTAB
    BNE SAVE_BYTE
    JMP CLSONE

;; Reads a BASIC program's file name: as <GETFNAM_DEF> does, with BAS when it has no extension.
BASNAM:
    LDX #BASEXT
    JMP GETFNAM_DEF
;; Runs MERGE "name"[,R]: merges a program saved as text into the one in memory, as if its lines were typed. With
;; R it then runs.
;;
;; Errors: ?FM ERROR for a crunched program
MERGE:
    CLRA                            ; don't run
    LDB #$FF                        ; merge
    BRA LOAD_FILE

;; The RUN hook: RUN "name"[,R] loads a program and runs it.
;;
;; In:   A = the character after RUN
DVEC18:
    CMPA #'"'
    LBNE XVEC18                     ; RUN without a name
    LDA #2                          ; run, closing the files
    BRA LOAD_NOMERGE

;; Runs LOAD "name"[,R]: loads a BASIC program, crunched or as text, in place of the one in memory. With R it then
;; runs, keeping the files open. LOADM loads memory instead.
;;
;; Errors: ?FM ERROR for a file that is not a BASIC program; ?OM ERROR for a program too big
LOAD:
    CMPA #'M'
    LBEQ LOADM
    CLRA                            ; don't run
LOAD_NOMERGE:
    CLRB                            ; don't merge
LOAD_FILE:
    STA DRUNFL
    STB DMRGFL
    BSR BASNAM
    JSR GETCCH
    BEQ LOAD_OPEN
    JSR SYNCOM
    LDB #'R'
    JSR SYNCHR
    JSR NAMEND_CHECK
    LDA #3                          ; run, keeping the files open
    STA DRUNFL
LOAD_OPEN:
    BSR SYSIN
    LDA DASCFL
    BEQ LOAD_CRUNCHED
    TST DMRGFL
    BNE LOAD_TEXT
    JSR ERASEP
LOAD_TEXT:
    JMP MAINLP                      ; the main loop reads the lines from the file, as if typed, until <DVEC13>
LOAD_CRUNCHED:
    LDA DFLTYP
    ORA DMRGFL
    LBNE FMERR                      ; not a BASIC program, or MERGE
    JSR ERASEP
    COM DLODFL                      ; an error from here on erases the program
    JSR DGETCH                       ; the $FF mark
    JSR DGETCH
    PSHS A
    JSR DGETCH
    TFR A,B
    PULS A                          ; the program's length
    ADDD TXTTAB
    JSR CHKMEM
    LDX TXTTAB
LOAD_BYTE:
    JSR DCONIN
    LDB CINBFL
    BNE LOAD_END
    STA ,X+
    BRA LOAD_BYTE
LOAD_END:
    CLR DLODFL
    STX VARTAB
    LDB #3
LOAD_ZERO:
    LDA ,-X                         ; a program ends with three zeros:
    BNE LOAD_ENDS
    DECB
    BNE LOAD_ZERO
LOAD_ENDS:
    LDX VARTAB
LOAD_CLEAR:
    STX VARTAB                      ;   add the ones it lacks
    CLR ,X+
    DECB
    BPL LOAD_CLEAR
LOAD_DONE:
    JSR CLSONE
    JSR CLRVAR
    JSR XVEC18
    JSR LINKLN
    ASR DRUNFL
    BLO LOAD_KEEP
    JSR CLSALL
LOAD_KEEP:
    ASR DRUNFL
    LBLO NEWSTT                     ; run it
    JMP OKPRMT

;; The hook for the end of a program loaded as text: finishes as a crunched LOAD does, when it came from a disk
;; file.
DVEC13:
    TST DEVNUM
    BGT LOAD_DONE
    RTS

;; The close all files hook: closes every disk file, the system's too.
DVEC7:
    LDB FCBACT
    INCB
DVEC7_FILE:
    PSHS B
    STB DEVNUM
    BSR DCLOSE
    PULS B
    DECB
    BNE DVEC7_FILE
DVEC7_DONE:
    RTS

;; The close one file hook: closes <DEVNUM>, when it is a disk file.
DVEC8:
    TST DEVNUM
    LBLE XVEC8
    LEAS 2,S
;; Closes the disk file <DEVNUM>, and sets the device back to the screen.
DCLOSE:
    JSR DEVFCB
    CLR DEVNUM
;; Closes a file. An output file's last sector and its count go to the disk; a random file's record buffer is
;; freed, its strings in FIELD let go and the buffers above moved down; the FAT is written when it has changed;
;; and the directory entry gets the bytes the last sector uses.
;;
;; In:   X = the FCB
DCLOSE_FCB:
    STX FCBTMP
    LDA <<FCBTYP,X
    BEQ DVEC7_DONE                  ; it is not open
    PSHS A
    CLR <<FCBTYP,X
    LDB FCBDRV,X
    STB DCDRV
    CMPA #OUTFIL
    BNE DCLOSE_RANDOM
    LDB FCBLFT,X                    ; an output file: the bytes in the last sector
    LDA #$80                        ; for the directory
.if VERSION = 11
    ORA FCBCPT,X                    ; 1.1: a full last sector counts as 256
.endif
    STD FCBLST,X
    INC FCBSEC,X
    LDB FCBCGR,X
    JSR DRVFAT
    STA FAT1,X                      ; the FAT has changed
    ABX
    INC FATCON,X                    ; a sector more in the last granule
.if VERSION = 10
DCLOSE_INPUT = DCLOSE_FAT
    BRA DCLOSE_FAT
.else
DCLOSE_INPUT:
    JMP DCLOSE_FAT
.endif
DCLOSE_RANDOM:
    CMPA #RANFIL
    BNE DCLOSE_INPUT
    LDD FCBRLN,X                    ; a random file
    LDX FCBBUF,X
    LEAY D,X
    PSHS A,B,X,Y                    ; the record length, and the buffer's start and end
.if VERSION = 11
    LEAY ,S
.endif
    LDU VARTAB
DCLOSE_VAR:
    CMPU ARYTAB
    BEQ DCLOSE_ARRAY
    LDA 1,U
    LEAU 2,U
    BPL DCLOSE_VAR_NEXT             ; numeric
    BSR DCLOSE_STRING
DCLOSE_VAR_NEXT:
    LEAU 5,U
    BRA DCLOSE_VAR
DCLOSE_ARRAY_NEXT:
    PULS U
DCLOSE_ARRAY:
    CMPU ARYEND
    BEQ DCLOSE_BUFFERS
    TFR U,D
    ADDD 2,U
    PSHS A,B                        ; the next array
    LDA 1,U
    BPL DCLOSE_ARRAY_NEXT           ; numeric
    LDB 4,U
    ASLB
    ADDB #5
    CLRA
    LEAU D,U                        ; its first element
DCLOSE_ELEMENT:
    CMPU ,S
    BEQ DCLOSE_ARRAY_NEXT
    BSR DCLOSE_STRING
    LEAU 5,U
    BRA DCLOSE_ELEMENT
DCLOSE_STRING:
    LDX 2,U                         ; a string: where its text is
    CMPX RNBFAD
    BHS DCLOSE_STRING_DONE          ; not in the random file buffers
.if VERSION = 10
    CMPX 4,S                        ; 1.0 finds the buffer through the stack, two bytes off for an array
    BLO DCLOSE_STRING_CLEAR         ;   and lets go of strings below it too
    CMPX 6,S
.else
    CMPX 2,Y
    BLO DCLOSE_STRING_DONE          ; in a buffer below this one
    CMPX 4,Y
.endif
    BLO DCLOSE_STRING_CLEAR         ; in this one: the string is let go
    TFR X,D
.if VERSION = 10
    SUBD 2,S
.else
    SUBD ,Y
.endif
    STD 2,U                         ; above it: the string moves down with its buffer
DCLOSE_STRING_DONE:
    RTS
DCLOSE_STRING_CLEAR:
    CLR ,U
    CLR 2,U
    CLR 3,U
    RTS
.if VERSION = 11
DCLOSE_BUFFERS:
    LDB FCBACT                      ; the buffers above move down: 1.0 leaves the files' pointers to them
    INCB
DCLOSE_BUFFER:
    PSHS B
    JSR FILEFCB
    LDA <<FCBTYP,X
    CMPA #RANFIL
    BNE DCLOSE_BUFFER_NEXT
    LDD FCBBUF,X
    CMPD 4,Y
    BLO DCLOSE_BUFFER_NEXT
    SUBD ,Y
    STD FCBBUF,X
DCLOSE_BUFFER_NEXT:
    PULS B
    DECB
    BNE DCLOSE_BUFFER
.else
DCLOSE_BUFFERS:
.endif
    PULS A,B,X,U
DCLOSE_SHIFT:
    CMPU RNBFAD
    BEQ DCLOSE_FREED
    LDA ,U+
    STA ,X+
    BRA DCLOSE_SHIFT
DCLOSE_FREED:
    STX RNBFAD
DCLOSE_FAT:
    JSR DRVFAT
    DEC <<FAT0,X                    ; a file less open on the drive
    TST FAT1,X
    BEQ DCLOSE_LAST
    JSR FATWRITE
DCLOSE_LAST:
    LDX FCBTMP
    PULS A
    CMPA #OUTFIL
    BEQ DCLOSE_WRITE
    CMPA #RANFIL
    BNE DCLOSE_STRING_DONE          ; an input file is done
    LDA FCBFLG,X
    BEQ DCLOSE_DIR
DCLOSE_WRITE:
    JSR FCBTS                       ; write the buffer's sector
    LEAU FCBCON,X
    STU DCBPT
    BSR WRITESEC
DCLOSE_DIR:
    LDA FCBLST,X
    BPL DCLOSE_STRING_DONE          ; the directory's count is right
    LDB FCBDIR,X
    ANDB #$07
    LDA #DIRLEN
    MUL
    LDU #DBUF0
    STU DCBPT
    LEAY D,U                        ; the entry, in the sector read
    LDB FCBDIR,X
    LSRB
    LSRB
    LSRB
    ADDB #3
    STB DSEC
    LDD #$1102                      ; track 17, read
    STA DCTRK
    BSR DOSEC
    LDD FCBLST,X
    ANDA #$7F
    STD DIRLST,Y
;; Writes a sector, as DSKCON's other arguments say.
WRITESEC:
    LDB #3
;; Reads or writes a sector, as DSKCON's other arguments say.
;;
;; In:   B = DSKCON's operation
DOSEC:
    STB DCOPC
    JMP DSKIO
;; The console out hook: writes a character to a disk file, when the device is one.
;;
;; In:   A = the character
DVEC3:
    TST DEVNUM
    LBLE XVEC3                      ; not a disk file
    LEAS 2,S                        ; not back to Color BASIC's PUTCHR
;; Writes a character to the open disk file <DEVNUM>: into a random file's record buffer, or into a sequential
;; output file's sector buffer, writing the sector and taking the next, and a new granule when one is used up,
;; once it is full. A carriage return sets the print position back to 0, and other control characters do not
;; move it. An input file is not written.
;;
;; In:   A = the character
;; Errors: ?ER ERROR past the end of a random file's record
DCONOUT:
    PSHS A,B,X
    LDX #FCBV1-2
    LDB DEVNUM
    ASLB
    LDX B,X                         ; the file's FCB
    LDB ,X
    CMPB #INPFIL
    BEQ DCONOUT_DONE
    CMPA #$0D
    BNE DCONOUT_PRINT
    CLR FCBPOS,X
DCONOUT_PRINT:
    CMPA #' '
    BLO DCONOUT_RANDOM              ; a control character
    INC FCBPOS,X
DCONOUT_RANDOM:
    CMPB #RANFIL
    BNE DCONOUT_SEQ
    LDD FCBPUT,X                    ; a random file: into the record
    ADDD #1
    CMPD FCBRLN,X
    LBHI ERERR
    STD FCBPUT,X
    LDX FCBBUF,X
    LEAX D,X
    PULS A
    STA -1,X
    PULS B,X,PC
DCONOUT_SEQ:
    INC FCBLFT,X
    LDB FCBLFT,X
    BEQ DCONOUT_FULL                ; the sector's last byte
    ABX
    STA FCBCON-1,X
DCONOUT_DONE:
    PULS A,B,X,PC
DCONOUT_FULL:
    PSHS Y,U
    STA FCBCON+SECLEN-1,X
.if VERSION = 10
    JSR NEXTREC
.endif
    LDB FCBDRV,X
    STB DCDRV
    INC FCBSEC,X
    JSR DCLOSE_WRITE                ; write the sector
    LEAY ,X
    LDB FCBCGR,X
    JSR DRVFAT
    ABX
    LEAU FATCON,X                   ; the granule's byte in the FAT
    LDA FCBSEC,Y
    CMPA #9
    BLO DCONOUT_LAST                ; sectors left in the granule
.if VERSION = 11
    DEC FCBSEC,Y                    ; noted in case the disk is full: the sector still counts
    INC FCBCPT,Y
    JSR FREEGRAN
.endif
    CLR FCBSEC,Y
.if VERSION = 10
    JSR FREEGRAN
.else
    CLR FCBCPT,Y
.endif
    STA FCBCGR,Y                    ; a new granule
    .byte $8C                       ; CMPX #: skips the ORA, to link the old granule to the new one
DCONOUT_LAST:
    ORA #$C0                        ; the last granule, with the sectors it uses
    STA ,U
.if VERSION = 11
    LEAX ,Y
    JSR NEXTREC
.endif
    JSR FATCHG
    PULS Y,U
    PULS A,B,X,PC

;; Runs DIR [drive]: lists the files in the directory, each with its extension, its type (0 a BASIC program, 1
;; BASIC data, 2 machine language, 3 an editor's source), B for binary or A for ASCII, and the granules it uses.
DIR:
    JSR GETDRV
    JSR FATLOAD
    JSR PRNTCR
    LDD #$1102                      ; track 17, read
    STA DCTRK
    STB DCOPC
    LDB #3
DIR_SECTOR:
    STB DSEC
    LDX #DBUF0
    STX DCBPT
    JSR DSKIO
DIR_ENTRY:
    PULS U
    JSR CHKBRK
    PSHS U
    LDA DIRNAM,X
    BEQ DIR_NEXT                    ; a killed file
    COMA
    BEQ DIR_DONE                    ; an unused entry: the end
    PSHS X
    LDB #8
    JSR STRPRT_COUNT                ; the name
    BSR OUTSP
    LDB #3
    JSR STRPRT_COUNT                ; the extension
    BSR OUTSP
    LDB <<0,X                       ; X is at DIRTYP now
    CMPB #10
    BHS DIR_TYPE
    BSR OUTSP
DIR_TYPE:
    CLRA
    JSR LINPRT
    BSR OUTSP
    LDX ,S
    LDA #'A'+1                      ; B, or A for $FF
    ADDA DIRASC,X
    BSR OUTCHSP
    LDB DIRGRN,X
    BSR GRANCNT
    TFR A,B
    CLRA
    JSR LINPRT
    JSR PRNTCR
    PULS X
DIR_NEXT:
    LEAX DIRLEN,X
    CMPX #DBUF0+SECLEN
    BLO DIR_ENTRY
    LDB DSEC
    INCB
    CMPB #SECMAX
    BLS DIR_SECTOR
DIR_DONE:
    RTS

;; Prints A, then a space.
OUTCHSP:
    JSR PUTCHR
;; Prints a space.
OUTSP:
    JMP OUTSPC

;; Counts the granules of a file, following them in the FAT.
;;
;; In:   B = its first granule; DCDRV = the drive
;; Out:  A = the granules; B = the last one's byte, $C0 and the sectors it uses
;; Errors: ?FS ERROR when the chain runs past 68 granules
GRANCNT:
    JSR DRVFAT
    LEAU FATCON,X
    CLRA
GRANCNT_NEXT:
    INCA
    CMPA #GRANMX
    LBHI FSERR
    LEAX ,U
    ABX
    LDB ,X
    CMPB #$C0
    BLO GRANCNT_NEXT
    RTS
;; The INPUT hook: reads the next item from a disk file into <LINBUF>, for INPUT to read as it would a line typed.
;;
;; A string item ends at a comma, or a quoted one at its closing quote; a number at a space or a comma; and either
;; at a carriage return, a carriage return and line feed counting as one. A carriage return after a line feed is
;; kept, as part of the item.
;;
;; Out:  X = LINBUF; the item at X+1, ended by a zero
;; Errors: ?IE ERROR past the end of a sequential file, ?ER ERROR past the end of a random file's record
DVEC10:
    TST DEVNUM
    BLE DVEC10_DONE                 ; not a disk file
    LDX #INPRD_ITEM
    STX ,S                          ; INPUT goes on reading the item, not a line
    LDX #LINBUF+1
    LDB #','                        ; a string ends at a comma
    STB CHARAC
    LDA VALTYP
    BNE DVEC10_SPACE
    LDB #' '                        ; and a number at a space
DVEC10_SPACE:
    BSR DGETCH
    CMPA #' '
    BEQ DVEC10_SPACE                ; skip the spaces before it
    CMPA #'"'
    BNE DVEC10_CHAR
    CMPB #','
    BNE DVEC10_CHAR
    TFR A,B                         ; a quoted string ends at the quote
    STB CHARAC
    BRA DVEC10_STORE
DVEC10_CHAR:
    CMPB #'"'
    BEQ DVEC10_TEST                 ; within quotes a carriage return is kept
    CMPA #$0D
    BNE DVEC10_TEST
    CMPX #LINBUF+1
    BEQ DVEC10_LF
    LDA -1,X
    CMPA #$0A
    BNE DVEC10_LF
    LDA #$0D                        ; a line feed and then a carriage return: keep it
DVEC10_TEST:
    TSTA
    BEQ DVEC10_NEXT                 ; a zero is left out
    CMPA CHARAC
    BEQ DVEC10_SEP
    PSHS B
    CMPA ,S+
    BEQ DVEC10_SEP
DVEC10_STORE:
    STA ,X+
    CMPX #LINBUF+LBUFMX
    BNE DVEC10_NEXT
    BSR INFILE                      ; the buffer is full
    BNE DVEC10_END
    BRA DVEC10_CR
DVEC10_NEXT:
    BSR INFILE
    BEQ DVEC10_CHAR
DVEC10_END:
    CLR ,X
    LDX #LINBUF
DVEC10_DONE:
    RTS
DVEC10_SEP:
    CMPA #'"'
    BEQ DVEC10_SKIP
    CMPA #' '
    BNE DVEC10_END
DVEC10_SKIP:
    BSR INFILE                      ; skip the spaces after it
    BNE DVEC10_END
    CMPA #' '
    BEQ DVEC10_SKIP
    CMPA #','
    BEQ DVEC10_END                  ; and a comma
DVEC10_CR:
    CMPA #$0D
    BNE DVEC10_BACK
DVEC10_LF:
    BSR INFILE                      ; and a line feed after a carriage return
    BNE DVEC10_END
    CMPA #$0A
    BEQ DVEC10_END
DVEC10_BACK:
    BSR UNREAD                      ; anything else is the next item's
    BRA DVEC10_END

;; Reads a character from the disk file <DEVNUM>, which must have one.
;;
;; Out:  A = the character
;; Errors: ?IE ERROR past the end of a sequential file, ?ER ERROR past the end of a random file's record
DGETCH:
    BSR INFILE
    BEQ INFILE_DONE
    JSR DEVFCB
    LDB <<FCBTYP,X
    CMPB #RANFIL
    LBNE DGETPUT_IE
;; Raises ?ER ERROR: past the end of a random file's record.
ERERR:
    LDB #ERR_ER
    JMP ERROR

;; Reads a character from the device <DEVNUM>.
;;
;; Out:  A = the character; Z clear when there was none
INFILE:
    JSR CONIN
    TST CINBFL
INFILE_DONE:
    RTS

;; Puts back the character just read from the disk file <DEVNUM>: a random file's record goes back a character;
;; a sequential file keeps it for next time.
;;
;; In:   A = the character
UNREAD:
    PSHS B,X
    JSR DEVFCB
    LDB <<FCBTYP,X
    CMPB #RANFIL
    BNE UNREAD_SEQ
    LDD FCBGET,X
    SUBD #1
    STD FCBGET,X
    PULS B,X,PC
UNREAD_SEQ:
    STA FCBCDT,X
    COM FCBCFL,X
    PULS B,X,PC

;; Runs the CVN function: the number a five-byte string from MKN$ holds.
;;
;; Errors: ?FC ERROR for a string shorter than five
CVN:
    JSR FRESTR
    CMPB #5
    LBLO FCERR
    CLR VALTYP
    JMP MOVFM

;; Runs the MKN$ function: a number as a five-byte string, for a random file's record.
MKN:
    JSR CKNUM
    LDB #5
    JSR STRSPA
    JSR MOVMF
    JMP CHRSTR_DONE

;; Runs the LOC function: a random file's record number, or the sectors a sequential file has read or written.
LOC:
    BSR FILARG
    LDD FCBREC,X
;; Returns D as a function's result: from 0 to 65535, but in 1.0 from -32768 to 32767.
;;
;; In:   D = the result
GIVD:
.if VERSION = 10
    JMP GIVABF
.else
    STD FPA0+2
    JMP GIVINT
.endif

;; Reads a function's file number, which must be an open disk file, without changing the device.
;;
;; Out:  X = its FCB
;; Errors: ?FC ERROR for a device that is not a disk file, ?NO ERROR when the file is not open
FILARG:
    LDA DEVNUM
    PSHS A
    JSR CKNUM
    JSR SETDEV
    TST DEVNUM
    LBLE FCERR
    JSR DEVFCB
    PULS A
    STA DEVNUM
    TST <<FCBTYP,X
    LBEQ NOTOPN
    RTS

;; Runs the LOF function: the records in a random file, or the sectors in a sequential one.
LOF:
    BSR FILARG
    LDA FCBDRV,X
    STA DCDRV
    LDB FCBFGR,X
    PSHS X
    JSR GRANCNT
    DECA                            ; the whole granules
    ANDB #$3F
    PSHS B                          ; and the last one's sectors
    TFR A,B
    CLRA
    JSR MUL9
    ADDB ,S+
    ADCA #0                         ; the file's sectors
    PULS X
    PSHS A
    LDA <<FCBTYP,X
    CMPA #RANFIL
    PULS A
    BNE GIVD                        ; a sequential file
    PSHS X
    SUBD ZERO
    BEQ LOF_BYTES
    SUBD #1                         ; the last sector counts only the bytes it uses
LOF_BYTES:
    BSR GIVD
    LDB FP0EXP
    BEQ LOF_FULL
    ADDB #8                         ; times 256
    STB FP0EXP
LOF_FULL:
    JSR MOVAF
    LDX ,S
    LDD FCBLST,X
    ANDA #$7F
    BSR GIVD
    CLR RESSGN
    LDA FP1EXP
    LDB FP0EXP
    JSR FPADD                       ; the file's bytes
    JSR MOVAF
    PULS X
    LDD FCBRLN,X
    BSR GIVD
    CLR RESSGN
    LDA FP1EXP
    LDB FP0EXP
    JSR FPDIV                       ; over the record length
    JMP INT

;; Runs the FREE function: the free granules on a drive.
;;
;; Errors: ?DN ERROR for a drive past 3
FREE:
    JSR CKNUM
    JSR BYTCHK
    CMPB #3
    LBHI DNERR
    STB DCDRV
    JSR FATLOAD
    JSR DRVFAT
    LEAX FATCON,X
    CLR ,-S
    LDB #GRANMX
FREE_COUNT:
    LDA ,X+
    COMA
    BNE FREE_NEXT
    INC ,S                          ; $FF: free
FREE_NEXT:
    DECB
    BNE FREE_COUNT
    PULS B
    JMP GIVB

;; Runs DRIVE n: sets the drive a file name without one uses.
;;
;; Errors: ?DN ERROR for a drive past 3
DRIVE:
    JSR GETBYT
    CMPB #3
    LBHI DNERR
    STB DEFDRV
    RTS
;; The expression hook: when LET's expression is a string variable FIELD put in a random file's buffer, LET goes on
;; at <DLET>, which copies the string into string space rather than share the buffer.
DVEC15:
    LDA 4,S
    BNE DVEC15_EB                   ; not the expression's end
    LDX 5,S
    CMPX #LET_VALUE
    BNE DVEC15_EB                   ; not LET's expression
    LDX 2,S
    CMPX #FRMEVL_TERM
    BNE DVEC15_EB
    LDX #DLET
    STX 5,S
DVEC15_EB:
    JMP XVEC15

;; LET past its expression, for Disk BASIC: a string whose text is in the random file buffers is copied.
DLET:
    PULS A
    RORA                            ; the variable's type, in the carry
    JSR CKTYPE
    LBEQ MOVVAR                     ; numeric: store FPA0
    LDX FPA0+2
    LDD 2,X                         ; where the string's text is
    CMPD #DFLBUF
    BLO DLET_STRING
    SUBD FCBADR
    LBLO LETSTR_COPY                ; in the buffers: copy it
DLET_STRING:
    JMP LETSTR

;; Runs Extended BASIC's commands, with Disk BASIC's changes: DLOAD closes the files first, and PMODE starts the
;; graphics pages after Disk BASIC's RAM.
;;
;; In:   A = the token
DXCVEC:
    CMPA #TK_DLOAD
    BEQ DXCVEC_DLOAD
    CMPA #TK_PMODE
    LBNE XCOMMAND
    JSR GETNCH
    CMPA #','
    LBEQ PMODE_PAGE
    JSR GETBYT
    CMPB #4
    LBHI FCERR
    LDA GRPRAM
    JMP PMOD_SET
DXCVEC_DLOAD:
    JSR CLSALL_CASSETTE
    JSR GETNCH
    JMP DLOAD_KIND

;; Runs Extended BASIC's functions, with Disk BASIC's change: POS(file) of a random file is where PRINT puts the
;; next character in the record.
;;
;; In:   B = twice the token's second byte, less $80
DXIVEC:
    CMPB #(TK_POS-$80)*2
    LBNE XFUNCTION
    JSR PARENS
    LDA DEVNUM
    PSHS A
    JSR SETDEV
    JSR CHKOUT
    TST DEVNUM
    BLE DXIVEC_POS                  ; not a disk file
    JSR DEVFCB
    LDB <<FCBTYP,X
    CMPB #RANFIL
    BNE DXIVEC_POS
    PULS A
    STA DEVNUM
    LDD FCBPUT,X
    JMP GIVABF
DXIVEC_POS:
    JSR SETPRM
    PULS A
    STA DEVNUM
    LDB DEVPOS
    JMP GIVB

;; Runs SAVEM "name",start,end,exec: saves memory from start to end as a machine language file, with extension BIN,
;; to load at start and run at exec.
;;
;; The file is blocks of a 0, a length and an address, then the bytes, and ends with $FF, two zeros and the exec
;; address, as LOADM reads it.
;;
;; Errors: ?FC ERROR when end is below start
SAVEM:
    JSR GETNCH
    BSR BINNAM
    JSR COMADR                      ; start
    JSR COMADR                      ; end
    CMPX 2,S
    LBLO FCERR
    JSR COMADR                      ; exec
    JSR NAMEND_CHECK
    LDD #$0200
    STD DFLTYP                      ; machine language, binary
    JSR SYSOUT
    CLRA
    BSR OUTAB                       ; a block
    LDD 2,S
    SUBD 4,S
    ADDD #1
    TFR D,Y
    BSR OUTD                        ; of the bytes from start to end
    LDD 4,S
    BSR OUTD                        ; at start
    LDX 4,S
SAVEM_BYTE:
    LDA ,X+
    JSR DCONOUT
    LEAY -1,Y
    BNE SAVEM_BYTE
    LDA #$FF                        ; the end
    BSR OUTAB
    CLRA
    CLRB
    BSR OUTD
    PULS A,B,X,Y
    BSR OUTD                        ; and the exec address
    JMP CLSONE

;; Writes D to the file <DEVNUM>, high byte first.
OUTD:
    BSR OUTAB
;; Writes A to the file <DEVNUM>, then swaps A and B.
OUTAB:
    JSR DCONOUT
    EXG A,B
    RTS

;; Reads a machine language file's name: as <GETFNAM_DEF> does, with BIN when it has no extension.
BINNAM:
    LDX #BINEXT
    JMP GETFNAM_DEF

;; Runs LOADM "name"[,offset]: loads a machine language file SAVEM saved, each block at its address plus the
;; offset, and sets EXEC's address.
;;
;; Errors: ?FM ERROR for another kind of file, ?IO ERROR when a byte does not store, as in ROM
LOADM:
    JSR GETNCH
    BSR BINNAM
    JSR SYSIN
    LDD DFLTYP
    SUBD #$0200
    LBNE FMERR                      ; not machine language, binary
    LDX ZERO
    JSR GETCCH
    BEQ LOADM_OFFSET
    JSR SYNCOM
    JSR GETADR
LOADM_OFFSET:
    STX VD3
    JSR NAMEND_CHECK
LOADM_BLOCK:
    JSR DGETCH
    PSHS A                          ; 0 a block, or $FF the end
    BSR INWORD
    TFR D,Y                         ; the length
    BSR INWORD
    ADDD VD3                        ; the address
    STD EXECJP
    TFR D,X
    LDA ,S+
    LBNE CLSONE                     ; the end: its address is EXEC's
LOADM_BYTE:
    JSR DCONIN
    LDB CINBFL
    BEQ LOADM_STORE
    JMP DGETPUT_IE
LOADM_STORE:
    STA ,X
    CMPA ,X+
    BEQ LOADM_NEXT
    JMP DIOERR
LOADM_NEXT:
    LEAY -1,Y
    BNE LOADM_BYTE
    BRA LOADM_BLOCK

;; Reads a word from the disk file <DEVNUM>, high byte first.
;;
;; Out:  D = the word
INWORD:
    BSR INWORD_BYTE
INWORD_BYTE:
    JSR DGETCH
    EXG A,B
    RTS

;; Runs RENAME "old" TO "new": renames a file, on the same drive.
;;
;; Errors: ?FC ERROR for two drives, ?NE ERROR when the file does not exist, ?AE ERROR when the new name does
RENAME:
    LDX CHARAD
    PSHS X
    BSR RENAME_NAME
    LDA DCDRV
    PSHS A
    BSR RENAME_TO
    PULS A
    CMPA DCDRV
    LBNE FCERR
    BSR NEWNAME
    PULS X
    STX CHARAD                      ; read the old name again
    BSR RENAME_NAME
    JSR DIRSRCH
    JSR FILECHK
    BSR RENAME_TO
    LDX #DNAMBF
    LDU FNDDIR
    LDB #11
    JSR MOVEXU                      ; the new name into the old entry
    LDB #3                          ; write it back
    STB DCOPC
    JMP DSKIO
RENAME_TO:
    LDB #TK_TO
    JSR SYNCHR
RENAME_NAME:
    JMP GETFNAM

;; Raises ?AE ERROR when the file named in <DNAMBF> exists.
NEWNAME:
    JSR DIRSRCH
    LDB #ERR_AE
    TST FNDSEC
    LBNE ERROR
    RTS

;; Runs WRITE [#file,]items: prints the items separated by commas, strings in quotes, then a carriage return. To
;; the cassette, the items are separated by carriage returns, without quotes.
WRITE:
    LBEQ PRNTCR                     ; no items
    BSR WRITE_ITEMS
    CLR DEVNUM
WRITE_DONE:
    RTS
WRITE_ITEMS:
    CMPA #'#'
    BNE WRITE_ITEM
    JSR GETDEV
    JSR CHKOUT
    JSR GETCCH
    LBEQ PRNTCR
WRITE_COMMA:
    JSR SYNCOM
WRITE_ITEM:
    JSR FRMEVL
    LDA VALTYP
    BNE WRITE_STRING
    JSR FOUT                        ; a number, without the spaces PRINT puts round it
    JSR STRLX
    JSR STRPRT
WRITE_NEXT:
    JSR GETCCH
    LBEQ PRNTCR
    LDA #','
    JSR SETPRM
    TST PRTDEV
    BEQ WRITE_SEP
    LDA #$0D
WRITE_SEP:
    BSR WRITE_OUT
    BRA WRITE_COMMA
WRITE_STRING:
    BSR WRITE_QUOTE
    JSR STRPRT
    BSR WRITE_QUOTE
    BRA WRITE_NEXT
WRITE_QUOTE:
    JSR SETPRM
    TST PRTDEV
    BNE WRITE_DONE
    LDA #'"'
WRITE_OUT:
    JMP PUTCHR
;; Runs FIELD #file,length AS variable[,length AS variable...]: makes each string variable a length of the random
;; file's record buffer, one after the other, so GET fills them and PUT writes them.
;;
;; Errors: ?FO ERROR when the fields pass the record's length, ?TM ERROR for a numeric variable
FIELD:
    JSR RANFCB
    CLRA
    CLRB
    PSHS A,B,X                      ; the fields' length so far, and the FCB
FIELD_NEXT:
    JSR GETCCH
    BNE FIELD_ITEM
    PULS A,B,X,PC
FIELD_ITEM:
    JSR COMBYT
    PSHS B,X                        ; the field's length, and room for where it is
    CLRA
    ADDD 3,S
    BLO FOERR
    LDX 5,S
    CMPD FCBRLN,X
    BLS FIELD_FITS
;; Raises ?FO ERROR: a field overflow.
FOERR:
    LDB #ERR_FO
    JMP ERROR
FIELD_FITS:
    LDU 3,S
    STD 3,S
    LDD FCBBUF,X
    LEAU D,U
    STU 1,S                         ; the field's place in the record buffer
    LDB #$FF                        ; a function token's first byte
    JSR SYNCHR
    LDB #TK_AS
    JSR SYNCHR
    JSR PTRGET
    JSR CKSTR
    PULS B,U
    STB ,X                          ; the string's length
    STU 2,X                         ;   and where it is
    BRA FIELD_NEXT

;; Runs RSET field=string: puts the string into a FIELD variable on the right, padded with spaces on the left. A
;; string longer than the field is cut on the right, as LSET does.
RSET:
    .byte $86                       ; LDA #$4F: nonzero for RSET
;; Runs LSET field=string: puts the string into a FIELD variable on the left, padded with spaces on the right, or
;; cut on the right when it is longer.
;;
;; Errors: ?SE ERROR for a variable not in a random file's buffer
LSET:
    CLRA
    PSHS A
    JSR PTRGET
    JSR CKSTR
    PSHS X
    LDX 2,X                         ; where the variable's text is
    CMPX #DFLBUF
    BLO SEERR
    CMPX FCBADR
    BLO LSET_FIELD                  ; in the random file buffers
;; Raises ?SE ERROR: set to a string that is not a field.
SEERR:
    LDB #ERR_SE
    JMP ERROR
LSET_FIELD:
    LDB #TK_EQUAL
    JSR SYNCHR
    JSR FRMSTR
    PULS Y                          ; the field's descriptor
    LDA ,Y
    BEQ LSET_DONE                   ; an empty field
    PSHS B
    LDB #' '
    LDU 2,Y
LSET_BLANK:
    STB ,U+
    DECA
    BNE LSET_BLANK
    LDB ,S+
    BEQ LSET_DONE                   ; an empty string
    CMPB ,Y
    BLO LSET_MOVE
    LDB ,Y                          ; as long as the field or longer: cut on the right, as LSET does
    CLR ,S
LSET_MOVE:
    LDU 2,Y
    TST ,S+
    BEQ LSET_COPY
    PSHS B                          ; RSET: to the field's right end
    CLRA
    NEGB
    SBCA #0
    ADDB ,Y
    ADCA #0
    LEAU D,U
    PULS B
LSET_COPY:
    JMP MOVEXU
LSET_DONE:
    PULS A,PC

;; Runs FILES [files][,bytes]: sets how many files can be open, 0 to 15, and how many bytes the random file buffers
;; have, which start as 2 and 256. It closes every file, makes the FCBs, and moves the graphics pages and the
;; program up or down to fit.
;;
;; Errors: ?FC ERROR for more than 15 files, ?OM ERROR when there is no room
FILES:
    JSR TEXTSCREEN
    LDD FCBADR
    SUBD #DFLBUF
    PSHS A,B                        ; the buffer space now
    LDB FCBACT
    PSHS B                          ; the files now
    JSR GETCCH
    CMPA #','
    BEQ FILES_SIZE
    JSR GETBYT
    CMPB #15
    LBHI FCERR
    STB ,S
    JSR GETCCH
    BEQ FILES_CLOSE
FILES_SIZE:
    JSR SYNCOM
    JSR POSINT
.if VERSION = 10
    ADDD #1                         ; 1.0 makes a byte more than asked for
.endif
    STD 1,S
FILES_CLOSE:
    JSR DVEC7                       ; close every file
    LDB ,S
    PSHS B
    LDD #DFLBUF
    ADDD 2,S
    BLO FILES_OM
    STD 2,S                         ; where the FCBs start
FILES_FCB:
    ADDD #FCBLEN
    BLO FILES_OM
    DEC ,S
    BPL FILES_FCB                   ; one more for the system
    TSTB
.if VERSION = 11
    BEQ FILES_EVEN
    INCA                            ; up to a page
    BEQ FILES_OM
FILES_EVEN:
    BITA #$01
.else
FILES_EVEN:
.endif
    BEQ FILES_PAGE
    INCA                            ; and in 1.1 up to an even page; 1.0 rounds just to a page
    BEQ FILES_OM
FILES_PAGE:
    STA ,S                          ; the first graphics page
    LDD VARTAB
    SUBA GRPRAM
    ADDA ,S
    BLO FILES_OM
    TFR D,X                         ; the program's end, moved
    INCA
    BEQ FILES_OM
    CMPD FRETOP
    BHS FILES_OM
    DECA
    SUBD VARTAB
    ADDD TXTTAB
    TFR D,Y                         ; and its start
    LDA ,S
    SUBA GRPRAM
    TFR A,B
    ADDA BEGGRP
    STA BEGGRP                      ; the graphics page moves too
    ADDB ENDGRP
    STB ENDGRP
    PULS A,B,U
    STA GRPRAM
    STB FCBACT
    STU FCBADR
.if VERSION = 11
    LDA CURLIN
    INCA
    BEQ FILES_MOVE                  ; a direct line
    TFR Y,D                         ; in a program, its place moves with it: 1.0 loses it
    SUBD TXTTAB
    ADDD CHARAD
    STD CHARAD
.endif
FILES_MOVE:
    LDU VARTAB
    STX VARTAB
    CMPU VARTAB
    BHI FILES_DOWN
FILES_UP:
    LDA ,-U                         ; up: from the end
    STA ,-X
    CMPU TXTTAB
    BNE FILES_UP
    STY TXTTAB
    CLR -1,Y
    BRA FILES_FCBS
FILES_OM:
    JMP OMERR
FILES_DOWN:
    LDU TXTTAB                      ; down: from the start
    STY TXTTAB
    CLR -1,Y
FILES_DOWN_BYTE:
    LDA ,U+
    STA ,Y+
    CMPY VARTAB
    BNE FILES_DOWN_BYTE
FILES_FCBS:
    LDU #FCBV1
    LDX FCBADR
    CLRB
FILES_FCB_NEXT:
    STX ,U++
    CLR <<FCBTYP,X
    LEAX FCBLEN,X
    INCB
    CMPB FCBACT
    BLS FILES_FCB_NEXT
    JMP PCLEAR_DONE

;; Runs UNLOAD [drive]: closes the files open on a drive.
UNLOAD:
    BSR GETDRV
    CLRB
UNLOAD_FILE:
    INCB
    JSR FILEFCB
    BEQ UNLOAD_NEXT
    LDA FCBDRV,X
    CMPA DCDRV
    BNE UNLOAD_NEXT
    PSHS B
    JSR DCLOSE_FCB
    PULS B
UNLOAD_NEXT:
    CMPB FCBACT
    BLS UNLOAD_FILE
    RTS
;; Reads a drive number from the program, or takes <DEFDRV> when the statement has ended.
;;
;; Out:  B = the drive; DCDRV = the drive
;; Errors: ?DN ERROR for a drive past 3
GETDRV:
    LDB DEFDRV
    JSR GETCCH
    BEQ GETDRV_SET
;; Reads a drive number from the program.
;;
;; Out:  B = the drive; DCDRV = the drive
;; Errors: ?DN ERROR for a drive past 3
GETDRV_NUM:
    JSR GETBYT
    CMPB #3
    LBHI DNERR
GETDRV_SET:
    STB DCDRV
    RTS

;; Runs BACKUP drive [TO drive]: copies a whole disk, track by track, through as much free memory as there is, with
;; the stack moved into <DBUF0>. With one drive, or the same drive twice, it asks for the disks to be swapped.
;;
;; The program is erased once it is done, since its memory held the tracks.
;;
;; Errors: ?DN ERROR without a drive, ?OM ERROR for less than a track's room
BACKUP:
    LBEQ DNERR
    JSR TEXTSCREEN
    JSR GETDRV_NUM
    STB DBUF0+$FF                   ; the source, at the top of the new stack
    JSR GETCCH
    BEQ BACKUP_TO
    LDB #TK_TO
    JSR SYNCHR
    JSR GETDRV_NUM
BACKUP_TO:
    LDS #DBUF0+$FF
    PSHS B                          ; the destination
    JSR NAMEND_CHECK
    JSR DVEC7                       ; close every file
    CLR ,-S
    LDX #DFLBUF-1
BACKUP_ROOM:
    INC ,S                          ; the tracks that fit in memory
    LEAX TRKLEN,X
    CMPX MEMSIZ
    BLS BACKUP_ROOM
    DEC ,S
    LBEQ OMERR
    LDA #TRKMAX                     ; the tracks left
    CLRB                            ; and the tracks done
    PSHS A,B
    COM DRESFL                      ; erase the program afterwards
BACKUP_PASS:
    CLRB
BACKUP_COUNT:
    INCB                            ; the tracks this time
    DEC ,S
    BEQ BACKUP_MOVE
    CMPB 2,S
    BNE BACKUP_COUNT
BACKUP_MOVE:
    STB TMPLOC
    LDB 4,S
    BSR READTRKS                    ; from the source
    LDA #$FF
    JSR SWAPDSK
    LDB 3,S
    BSR WRITETRKS                   ; to the destination
    TST ,S
    BEQ BACKUP_DONE
    CLRA
    JSR SWAPDSK
    LDB 1,S
    ADDB TMPLOC
    STB 1,S
    BRA BACKUP_PASS
BACKUP_DONE:
    BSR DRESET
    JMP OKPRMT

;; Clears up after something that took Disk BASIC's memory or failed while loading: when <DRESFL> is set, closes
;; every FCB without writing and erases the program; when <DLODFL> is, erases the program.
DRESET:
    PULS U
    LDA DRESFL
    BEQ DRESET_LOAD
    LDX #FCBV1
    CLRA
DRESET_FCB:
    CLR [,X++]
    INCA
    CMPA FCBACT
    BLS DRESET_FCB
    LDX TXTTAB
    CLR -1,X
    JSR ERASEP
    CLR DRESFL
DRESET_LOAD:
    LDA DLODFL
    BEQ DRESET_DONE
    CLR DLODFL
    JSR ERASEP
DRESET_DONE:
    JMP ,U

;; Reads <TMPLOC> tracks into memory from <DFLBUF>, from the track the stack's caller is at.
;;
;; In:   B = the drive
READTRKS:
    LDA #2
    .byte $8C                       ; CMPX #: skips the LDA below
;; Writes <TMPLOC> tracks from memory at <DFLBUF>, to the track the stack's caller is at.
;;
;; In:   B = the drive
WRITETRKS:
    LDA #3
    STD DCOPC                       ; the operation, and DCDRV
    LDA 3,S                         ; the tracks done so far
    STA DCTRK
    LDX #DFLBUF
    STX DCBPT
    LDA TMPLOC
TRKS_TRACK:
    LDB #1
TRKS_SECTOR:
    STB DSEC
    JSR DSKIO
    INC DCBPT                       ; the next 256 bytes
    INCB
    CMPB #SECMAX
    BLS TRKS_SECTOR
    INC DCTRK
    DECA
    BNE TRKS_TRACK
    RTS

;; With the same drive as source and destination, turns the motors off and asks for the next disk, with a beep, and
;; waits for ENTER.
;;
;; In:   A = 0 for the source disk, $FF for the destination
SWAPDSK:
    LDB 5,S
    CMPB 6,S
;; As <SWAPDSK> does, the flags saying whether the drives differ: Z set when they are the same.
SWAPDSK_SAME:
    BNE SWAPDSK_DONE                ; two drives
    CLR RDYTMR
    CLR DSKREG
    CLR DRGRAM
    PSHS A
    JSR CLRSCN
    LDX #SRCMSG
    LDB #13
    LDA ,S+
    BEQ SWAPDSK_SHOW
    LDX #DSTMSG
    LDB #18
SWAPDSK_SHOW:
    JSR STRPRT_COUNT
    LDX #DSKMSG
    LDB #27
    JSR STRPRT_COUNT
    LDD #$6405
    STA SNDTON
    JSR SOUND_DURATION
SWAPDSK_WAIT:
    JSR INCHR
    CMPA #$0D
    BNE SWAPDSK_WAIT
SWAPDSK_DONE:
    RTS

;; The disk swap's messages: which disk, then the rest.
SRCMSG:
    .byte "INSERT SOURCE"
DSTMSG:
    .byte "INSERT DESTINATION"
DSKMSG:
    .byte " DISKETTE AND", $0D, "PRESS 'ENTER'"

;; Pushes the file name, extension and drive onto the stack, under the return address, for COPY.
PUSHNAM:
    PULS Y
    LDB #11
    LDX #DEXTBF+3
PUSHNAM_BYTE:
    LDA ,-X
    PSHS A
    DECB
    BNE PUSHNAM_BYTE
    LDA DCDRV
    PSHS A
    JMP ,Y

;; Sets the drive, name and extension from a copy <PUSHNAM> made.
;;
;; In:   X = the copy
POPNAM:
    LDA ,X+
    STA DCDRV
    LDB #11
    LDU #DNAMBF
    JMP MOVEXU

;; Runs COPY "from" [TO "to"]: copies a file, through as much free memory as there is, a part at a time. With no
;; destination, or the same drive twice, it asks for the disks to be swapped.
;;
;; The program is erased once it is done, since its memory held the file.
;;
;; Errors: ?NE ERROR when the file does not exist, ?OM ERROR for no room
COPY:
    JSR GETFNAM
    BSR PUSHNAM                     ; the source
    CLR ,-S                         ; no destination yet
    JSR GETCCH
    BEQ COPY_NAMES
COPY_TO:
    COM ,S                          ; a destination
    LDB #TK_TO
    JSR SYNCHR
    JSR GETFNAM
COPY_NAMES:
    BSR PUSHNAM                     ; the destination, or the source again
    JSR NAMEND_CHECK
    JSR DVEC7                       ; close every file
    CLR ,-S
.if VERSION = 10
    LEAX -100,S                     ; 1.0 leaves the stack 100 bytes
.else
    LEAX -SECLEN,S                  ; 1.1 a sector
.endif
COPY_ROOM:
    INC ,S                          ; the sectors that fit in free memory
    LEAX -SECLEN,X
    CMPX ARYEND
    BHS COPY_ROOM
    DEC ,S
    LBEQ OMERR
    LEAX 14,S
    BSR POPNAM                      ; the source
    JSR DIRSRCH
    JSR FILECHK
    LDX FNDDIR
    LDU DIRLST,X
    LDX DIRTYP,X
    PSHS X,U                        ; its type, ASCII flag and last sector's bytes
    JSR FATLOAD
    LDB FNDGRN
    JSR GRANCNT
    PSHS A                          ; its granules: the room the destination needs
    DECA
    ANDB #$3F
    PSHS B
    TFR A,B
    CLRA
    JSR MUL9
    ADDB ,S
    ADCA #0
    LDX #1                          ; from record 1
    PSHS A,B,X                      ; and its sectors
COPY_PASS:
    CLRB
    LDX ,S
    BEQ COPY_MOVE
COPY_COUNT:
    INCB                            ; the sectors this time
    LEAX -1,X
    BEQ COPY_MOVE
    CMPB 10,S
    BNE COPY_COUNT
COPY_MOVE:
    STX ,S
    STB 4,S
    BSR COPY_READ
    LDA #$FF
    BSR COPY_SWAP
    TST 5,S
    BEQ COPY_PUT                    ; the destination was checked already
    LEAX 11,S
    JSR POPNAM                      ; the destination
    JSR NEWNAME
    JSR FATLOAD
    JSR DRVFAT
    LEAX FATCON,X
    LDA 5,S
    LDB #GRANMX
COPY_FREE:
    COM ,X                          ; enough free granules?
    BNE COPY_FREE_NEXT
    DECA
    BEQ COPY_FITS
COPY_FREE_NEXT:
    COM ,X+
    DECB
    BNE COPY_FREE
    JMP DFERR
COPY_FITS:
    COM ,X
COPY_PUT:
    BSR COPY_WRITE
    LDX ,S
    BEQ COPY_DONE
    LDD 2,S
    ADDB 4,S
    ADCA #0
    STD 2,S                         ; the next record
    CLRA
    BSR COPY_SWAP
    BRA COPY_PASS
COPY_DONE:
    LEAS 36,S
    RTS
COPY_SWAP:
    TST 25,S                        ; asks for the other disk, unless there are two drives
    JMP SWAPDSK_SAME

;; Writes the sectors in memory to the destination, as records of a random file.
COPY_WRITE:
    LDA #$FF                        ; PUT
    LEAX 13,S
    BRA COPY_SECTORS
;; Reads the next sectors from the source into memory, as records of a random file.
COPY_READ:
    CLRA                            ; GET
    LEAX 26,S
COPY_SECTORS:
    STA VD8
    JSR POPNAM
    LDX 8,S
    STX DFLTYP
    LDX #SECLEN
    STX DFFLEN                      ; records of a sector
    LDA #'R'
    LDB FCBACT
    INCB
    JSR DOPEN                       ; in the system's FCB
    LDX FCBTMP
    LDD #SECLEN
    STD FCBLST,X
    LDB 6,S
    BEQ COPY_CLOSE
    LDB VD8
    ANDB 7,S
    BEQ COPY_RECORD
    LDD 2,S                         ; the first PUT reaches the file's last record first, which takes all its
    ADDB 6,S                        ;   granules
    ADCA #0
    JSR DGETPUT_RECNUM
COPY_RECORD:
    LDX FCBTMP
    LDU 4,S
    STU FCBREC,X
    LDB 6,S
    LDU ARYEND
COPY_SECTOR:
    PSHS B,U
    LDX FCBTMP
    STU FCBBUF,X                    ; each sector's place in memory
    JSR DGETPUT_CURRENT
    INC 1,S                         ; the next 256 bytes
    PULS B,U
    DECB
    BNE COPY_SECTOR
COPY_CLOSE:
    LDX FCBTMP
    LDU #DFLBUF
    STU FCBBUF,X
    LDB VD8
    ANDB 7,S
    BEQ COPY_LAST
    CLR 7,S
    LDD 10,S
    ORA #$80                        ; the last sector's bytes, for the directory
    STD FCBLST,X
COPY_LAST:
    JMP DCLOSE_FCB
;; Runs DSKI$ drive,track,sector,string1,string2: reads a sector, its first 128 bytes into string1 and the rest into
;; string2.
;;
;; Errors: ?FC ERROR for a bad drive, track or sector, ?TM ERROR for a numeric variable
DSKI:
    BSR DSKARGS
    BSR DSKI_VAR
    PSHS X
    BSR DSKI_VAR
    PSHS X
    LDB #2
    JSR DSKSEC
    LDU #DBUF0+128
    PULS X
    BSR DSKI_STRING
    LDU #DBUF0
    PULS X
DSKI_STRING:
    PSHS X,U                        ; make the variable at X a new 128-byte string, from U
    LDB #128
    JSR STRSPA
    LEAU ,X
    PULS X
    STB ,X
    STU 2,X
    PULS X
DSK_MOVE:
    JMP MOVEXU
DSKI_VAR:
    JSR SYNCOM
    LDX #PTRGET
    BSR DSKKEEP
DSK_CKSTR:
    JMP CKSTR

;; Reads DSKI$ and DSKO$'s drive, track and sector into DSKCON's arguments.
;;
;; Errors: ?FC ERROR for a drive past 3, a track past 34, or a sector not from 1 to 18
DSKARGS:
    JSR GETBYT
    CMPB #3
    BHI DSKARGS_FC
    PSHS B
    JSR COMBYT
    CMPB #TRKMAX-1
    BHI DSKARGS_FC
    PSHS B
    JSR COMBYT
    STB DSEC
    DECB
    CMPB #SECMAX-1
    BHI DSKARGS_FC
    PULS A,B
    STA DCTRK
    STB DCDRV
    RTS
DSKARGS_FC:
    JMP FCERR

DSKO_EXPR:
    JSR SYNCOM
    LDX #FRMEVL
;; Calls a routine, keeping DSKCON's drive, track and sector, which evaluating can change.
;;
;; In:   X = the routine
DSKKEEP:
    LDB DCDRV
    LDU DCTRK
    PSHS B,U
    JSR ,X
    PULS B,U
    STB DCDRV
    STU DCTRK
    RTS

;; Runs DSKO$ drive,track,sector,string1,string2: writes a sector, string1 in its first 128 bytes and string2 in
;; the rest, padded with zeros.
;;
;; Errors: ?FC ERROR for a bad drive, track or sector, ?TM ERROR for a number
DSKO:
    BSR DSKARGS
    BSR DSKO_EXPR
    BSR DSK_CKSTR
    LDX FPA0+2
    PSHS X
    BSR DSKO_EXPR
    JSR FRESTR
    PSHS B,X
    CLRB
    LDX #DBUF0
DSKO_CLEAR:
    CLR ,X+
    DECB
    BNE DSKO_CLEAR
    PULS B,X
    LDU #DBUF0+128
    BSR DSK_MOVE
    PULS X
    JSR FRETMP
    LDU #DBUF0
    BSR DSK_MOVE
    LDB #3
;; Reads or writes a sector through <DBUF0>.
;;
;; In:   B = DSKCON's operation
DSKSEC:
    LDX #DBUF0
    STX DCBPT
    STB DCOPC
    JMP DSKIO

;; Runs DSKINI drive[,skip]: formats a disk, 35 tracks of 18 sectors of 256 bytes, its sectors laid out skip apart
;; (4 if not given, up to 16) for speed, then reads every sector back. Each track is built in memory and written
;; whole, the CPU halted between bytes until the controller's NMI ends it.
;;
;; The program is erased once it is done, since its memory held the track.
;;
;; Errors: ?DN ERROR without a drive, ?FC ERROR for a skip past 16, ?OM ERROR for no room, ?IO ERROR or ?WP ERROR
DSKINI:
    LBEQ DNERR
    JSR GETDRV_NUM
    LDB #4
    JSR GETCCH
    BEQ DSKINI_SKIP
    JSR COMBYT
    CMPB #17
    LBHS FCERR
    JSR NAMEND_CHECK
DSKINI_SKIP:
    PSHS B
    LDX #DBUF1+SECMAX               ; the sector at each place round the track, in DBUF1
    LDB #SECMAX
DSKINI_CLEAR:
    CLR ,-X
    DECB
    BNE DSKINI_CLEAR
    CLRA
    BRA DSKINI_SET
DSKINI_NEXT:
    ADDB ,S                         ; skip places on
DSKINI_TRY:
    INCB
DSKINI_WRAP:
    SUBB #SECMAX
    BHS DSKINI_WRAP
    ADDB #SECMAX
    TST B,X
    BNE DSKINI_TRY                  ; taken already: the next
DSKINI_SET:
    INCA
    STA B,X
    CMPA #SECMAX
    BLO DSKINI_NEXT
    LEAS 1,S
    LDX #DFLBUF+$1888-2             ; the track's image
    CMPX MEMSIZ
    LBHI OMERR
    JSR DVEC7                       ; close every file
    COM DRESFL                      ; erase the program afterwards
    LDS #DBUF1+SECLEN
    JSR TEXTSCREEN
    LDA #0                          ; restore to track 0
    STA DCOPC
.if VERSION = 11
    CLR DCTRK
.endif
    JSR DSKIO
    CLR RDYTMR
    LDA #$C0                        ; read address, to see that the drive is ready
    STA FDCREG
    JSR FDCWAIT
.if VERSION = 10
    LBNE DSKINI_ERROR
    CLR DCTRK
    BRA DSKINI_WRITE
.else
    BEQ DSKINI_WRITE
    JMP DSKINI_ERROR
.endif
DSKINI_TRACK:
    CMPA #22
    BLO DSKINI_STEP
    LDA DRGRAM
    ORA #$10                        ; write precompensation from track 22
    STA DSKREG
DSKINI_STEP:
    LDA #$53                        ; step in
    STA FDCREG
    EXG A,A
    EXG A,A
    JSR FDCWAIT
    BNE DSKINI_ERROR
DSKINI_WRITE:
    JSR FDCDELAY
    BSR FMTTRK
    LDY #FDCREG+3
    ORCC #$50                       ; no interrupts
    LDX #DSKINI_WRITTEN
    STX DNMIVC
    LDX #DFLBUF
    LDA FDCREG
    LDA #$FF
    STA NMIFLG                      ; the NMI ends the write
    LDB #$F4                        ; write track
    STB FDCREG
    LDA DRGRAM
    ORA #$80                        ; halt the CPU until the controller wants each byte
    STA DSKREG
DSKINI_BYTE:
    LDB ,X+
    STB ,Y
    BRA DSKINI_BYTE
DSKINI_WRITTEN:
    LDA FDCREG
    ANDCC #$AF
    ANDA #$44                       ; write protected, or lost data
    STA DCSTA
    BNE DSKINI_ERROR
    INC DCTRK
    LDA DCTRK
    CMPA #TRKMAX
    BNE DSKINI_TRACK
    LDA #2                          ; then read every sector back
    STA DCOPC
    LDX #DBUF0
    STX DCBPT
    LDU #DBUF1
    CLRA
DSKINI_VERIFY:
    STA DCTRK
    CLRB
DSKINI_SECTOR:
    LDA B,U
    STA DSEC
    JSR DSKIO
    INCB
    CMPB #SECMAX
    BLO DSKINI_SECTOR
    LDA DCTRK
    INCA
    CMPA #TRKMAX
    BLO DSKINI_VERIFY
    JMP BACKUP_DONE
DSKINI_ERROR:
    CLR DRGRAM
    CLR DSKREG
    JMP DSKERR

;; Builds a track's image at <DFLBUF> for DSKINI, from <FMTTAB>: a gap, then each sector's ID and data fields, in
;; the order <DBUF1> holds, then a gap to the end.
;;
;; In:   DCTRK = the track
FMTTRK:
    LDX #DFLBUF
    LDD #$204E                      ; 32 bytes of $4E
    BSR FILLX
    CLRB
FMTTRK_SECTOR:
    PSHS B
    LDU #DBUF1
    LDB B,U
    STB DSEC
    LDU #FMTTAB
    LDB #3
    BSR FMTFILL                     ; to the ID mark
    LDA DCTRK
    STA ,X+                         ; the track
    CLR ,X+                         ; side 0
    LDA DSEC
    STA ,X+                         ; the sector
    LDB #9
    BSR FMTFILL                     ; and the rest
    PULS B
    INCB
    CMPB #SECMAX
    BLO FMTTRK_SECTOR
    LDD #$C84E                      ; 200 bytes of $4E
;; Stores A copies of B at X, or 256 when A is 0.
FILLX:
    STB ,X+
    DECA
    BNE FILLX
    RTS
;; Stores B of <FMTTAB>'s runs at X.
;;
;; In:   U = the next run
FMTFILL:
    PSHS B
    LDD ,U++
    BSR FILLX
    PULS B
    DECB
    BNE FMTFILL
    RTS

;; A sector's fields for DSKINI, as runs of a count and a byte, much as IBM's System 34 format lays out a 256-byte
;; sector in double density, with short gaps and $FF in the data.
FMTTAB:
    .byte 8, $00                    ; sync
    .byte 3, $F5
    .byte 1, $FE                    ; the ID mark; the track, side and sector follow
    .byte 1, $01                    ; 256-byte sectors
    .byte 1, $F7                    ; the CRC
    .byte 22, $4E                   ; gap 2
    .byte 12, $00                   ; sync
    .byte 3, $F5
    .byte 1, $FB                    ; the data mark
    .byte 0, $FF                    ; 256 bytes of data
    .byte 1, $F7                    ; the CRC
    .byte 24, $4E                   ; gap 3

.if VERSION = 11
;; Runs DOS, which 1.1 adds: boots an OS-9 disk in drive 0, through <DOSVEC>, which points at <DOSCOM>.
DOS:
    BNE DSKIO_DONE                       ; DOS takes nothing after it
    JMP [DOSVEC]
.endif
;; Reads or writes a sector through DSKCON, as its arguments say, trying it five times before an error. With
;; VERIFY ON, a sector written is read back into <DBUF1> and compared, and written again when it differs.
;;
;; Errors: ?IO ERROR when the sector cannot be read or written, ?WP ERROR when the disk is write protected,
;; ?VF ERROR when a write still differs after five tries
DSKIO:
    PSHS B
    LDB #5
    STB ATTCTR
    PULS B
DSKIO_TRY:
    BSR DSKCON
    TST DCSTA
    BEQ DSKIO_VERIFY
;; Raises the error DSKCON's status says: ?WP ERROR for a write protected disk, else ?IO ERROR.
DSKERR:
    LDA DCSTA
    LDB #ERR_WP
    BITA #$40
    BNE DSKERR_RAISE
;; Raises ?IO ERROR.
DIOERR:
    LDB #ERR_IO
DSKERR_RAISE:
    JMP ERROR
DSKIO_VERIFY:
    PSHS A
    LDA DCOPC
    CMPA #3
    PULS A
    BNE DSKIO_DONE                  ; not a write
    TST DVERFL
    BEQ DSKIO_DONE                  ; VERIFY OFF
    PSHS A,B,X,U
    LDA #2
    STA DCOPC
    LDU DCBPT
    LDX #DBUF1
    STX DCBPT
    BSR DSKCON                      ; read it back into DBUF1
    STU DCBPT
    LDA #3
    STA DCOPC
    LDA DCSTA
    BNE DSKIO_RETRY
    CLRB
DSKIO_COMPARE:
    LDA ,X+
    CMPA ,U+
    BNE DSKIO_RETRY
    DECB
    BNE DSKIO_COMPARE
    PULS A,B,X,U
DSKIO_DONE:
    RTS
DSKIO_RETRY:
    PULS A,B,X,U
    DEC ATTCTR
    BNE DSKIO_TRY
    LDB #ERR_VF
    BRA DSKERR_RAISE

;; Runs VERIFY ON and VERIFY OFF: whether each sector written is read back and compared.
VERIFY:
    CLRB
    CMPA #TK_OFF
    BEQ VERIFY_SET
    COMB
    CMPA #TK_ON
    LBNE SNERR
VERIFY_SET:
    STB DVERFL
    JMP GETNCH

;; Runs an operation on the disk controller, as <DCOPC> and the arguments after it say: selects the drive, turns
;; its motor on, waiting for it when it was off, and runs the operation, trying it five times, the head restored to
;; track 0 between tries. The motors turn off two seconds later, at <DIRQSV>. Programs call it through <DCNVEC>.
;;
;; Out:  DCSTA = 0 when it worked, or the controller's error bits
DSKCON:
    PSHS A,B,X,Y,U
    LDA #5
    PSHS A                          ; the tries left
DSKCON_TRY:
    CLR RDYTMR
    LDB DCDRV
    LDX #DRVMASK
    LDA DRGRAM
    ANDA #$A8                       ; keep the halt, density and motor bits
    ORA B,X                         ; select the drive
    ORA #$20                        ; double density
    LDB DCTRK
    CMPB #22
    BLO DSKCON_SELECT
    ORA #$10                        ; write precompensation from track 22
DSKCON_SELECT:
    TFR A,B
    ORA #$08                        ; the motor on
    STA DRGRAM
    STA DSKREG
    BITB #$08
    BNE DSKCON_READY                ; it was on already
    JSR DELAY                       ; else give it a second to come up to speed
    JSR DELAY
DSKCON_READY:
    BSR FDCWAIT
    BNE DSKCON_CHECK                ; not ready
    CLR DCSTA
    LDX #DSKOPS
    LDB DCOPC
    ASLB
    JSR [B,X]
DSKCON_CHECK:
    PULS A
    LDB DCSTA
    BEQ DSKCON_DONE
    DECA
    BEQ DSKCON_DONE                 ; the last try
    PSHS A
    BSR DSKREST
    BNE DSKCON_CHECK
    BRA DSKCON_TRY
DSKCON_DONE:
    LDA #120                        ; motors off in two seconds
    STA RDYTMR
    PULS A,B,X,Y,U,PC

;; DSKCON's operation 0: restores the drive's head to track 0.
;;
;; Out:  DCSTA = the seek error bit, or $80 when the drive is not ready; Z set when it worked
DSKREST:
    LDX #DR0TRK
    LDB DCDRV
    CLR B,X
    LDA #$03                        ; restore
    STA FDCREG
    EXG A,A
    EXG A,A
    BSR FDCWAIT
    BSR FDCDELAY
    ANDA #$10                       ; seek error
    STA DCSTA
;; DSKCON's operation 1, seek: nothing, since a read or write seeks first.
DSKSEEK:
    RTS

;; Waits for the controller to finish its command, or for a long while; a time out stops the command.
;;
;; Out:  A = its status; DCSTA = $80 on a time out; Z clear on a time out
FDCWAIT:
    LDX ZERO
FDCWAIT_LOOP:
    LEAX -1,X
    BEQ FDCTIMEOUT
    LDA FDCREG
    BITA #$01                       ; busy
    BNE FDCWAIT_LOOP
    RTS
;; Stops the controller's command and sets <DCSTA> to $80: the drive is not ready.
FDCTIMEOUT:
    LDA #$D0                        ; force interrupt
    STA FDCREG
    EXG A,A
    EXG A,A
    LDA FDCREG
    LDA #$80
    STA DCSTA
    RTS

;; Waits a while, for the head to settle.
FDCDELAY:
    LDX #$222E
FDCDELAY_LOOP:
    LEAX -1,X
    BNE FDCDELAY_LOOP
    RTS

;; DSKCON's operation 2: reads a sector into <DCBPT>.
DSKREAD:
    LDA #$80                        ; read sector
    .byte $8C                       ; CMPX #: skips the LDA below
;; DSKCON's operation 3: writes a sector from <DCBPT>.
;;
;; Both seek first, when the head is not on the track, then move the sector's bytes with the CPU halted between
;; them until the controller wants the next; its NMI ends the loop, at <DSKRW_DONE>.
DSKWRITE:
    LDA #$A0                        ; write sector
    PSHS A
    LDX #DR0TRK
    LDB DCDRV
    ABX
    LDB ,X
    STB FDCREG+1                    ; the track the head is on
    CMPB DCTRK
    BEQ DSKRW_SECTOR
    LDA DCTRK
    STA FDCREG+3
    STA ,X
    LDA #$17                        ; seek, and check the track
    STA FDCREG
    EXG A,A
    EXG A,A
    BSR FDCWAIT
    BNE DSKRW_FAIL
    BSR FDCDELAY
    ANDA #$18                       ; seek error, or CRC error
    BEQ DSKRW_SECTOR
    STA DCSTA
DSKRW_FAIL:
    PULS A,PC
DSKRW_SECTOR:
    LDA DSEC
    STA FDCREG+2
    LDX #DSKRW_DONE
    STX DNMIVC
    LDX DCBPT
    LDA FDCREG
    LDA DRGRAM
    ORA #$80                        ; halt the CPU until the controller wants each byte
    PULS B
    LDY ZERO
    LDU #FDCREG
    COM NMIFLG
    ORCC #$50                       ; no interrupts
    STB FDCREG
    EXG A,A
    EXG A,A
    CMPB #$80
    BEQ DSKRW_READ
    LDB #$02                        ; data request
DSKRW_WAITW:
    BITB ,U
    BNE DSKRW_WRITE
    LEAY -1,Y
    BNE DSKRW_WAITW
DSKRW_TIMEOUT:
    CLR NMIFLG
    ANDCC #$AF
    JMP FDCTIMEOUT
DSKRW_WRITE:
    LDB ,X+
    STB FDCREG+3
    STA DSKREG
    BRA DSKRW_WRITE
DSKRW_READ:
    LDB #$02                        ; data request
DSKRW_WAITR:
    BITB ,U
    BNE DSKRW_BYTE
    LEAY -1,Y
    BNE DSKRW_WAITR
    BRA DSKRW_TIMEOUT
DSKRW_BYTE:
    LDB FDCREG+3
    STB ,X+
    STA DSKREG
    BRA DSKRW_BYTE
DSKRW_DONE:
    ANDCC #$AF
    LDA FDCREG
    ANDA #$7C                       ; the error bits
    STA DCSTA
    RTS

;; DSKCON's operations, by <DCOPC>.
DSKOPS:
    .dbyt DSKREST, DSKSEEK, DSKREAD, DSKWRITE

;; The drive select bits of <DSKREG>, for drives 0 to 3.
DRVMASK:
    .byte $01, $02, $04, $40

;; Disk BASIC's NMI handler: while <NMIFLG> is set, the controller's NMI ends a read or write by returning to
;; <DNMIVC> instead.
DNMISV:
    LDA NMIFLG
    BEQ DNMISV_DONE
    LDX DNMIVC
    STX 10,S                        ; the return address RTI pulls
    CLR NMIFLG
DNMISV_DONE:
    RTI

;; Disk BASIC's IRQ handler: on the field sync interrupt, counts <RDYTMR> down and turns the motors off at 0, then
;; goes on to Extended BASIC's handler.
DIRQSV:
    LDA PIA0+3
    BPL DNMISV_DONE                 ; not the field sync
    LDA PIA0+2                      ; acknowledge it
    LDA RDYTMR
    BEQ DIRQSV_EB
    DECA
    STA RDYTMR
    BNE DIRQSV_EB
    LDA DRGRAM
    ANDA #$B0                       ; motors and drives off
    STA DRGRAM
    STA DSKREG
DIRQSV_EB:
    JMP XIRQSV_TIMER

; Unused: in 1.1 to $DF00, where DOS's routine is, and in 1.0 to the end. These are the bytes the ROM holds.
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.if VERSION = 10
    .byte $00, $00, $00, $A7, $FC, $8F, $EC, $94, $BC, $8C, $F5, $BC, $F8, $D1, $FA, $FD
    .byte $FD, $AC, $E5, $EC, $F8, $8A, $EA, $AD, $EC, $B9, $FF, $BC, $FD, $CC, $ED, $8C
    .byte $E5, $9C, $F4, $A2, $A6, $E8, $FC, $AE, $E5, $94, $EC, $BE, $EE, $8C, $ED, $EA
    .byte $E5, $ED, $7C, $BE, $FC, $8E, $ED, $FE, $EC, $9C, $AC, $DC, $FD, $FB, $F5, $AD
    .byte $FD, $AF, $E9, $A0, $30, $24, $8A, $14, $84, $2C, $C4, $24, $08, $E0, $21, $20
    .byte $80, $28, $00, $20, $88, $A4, $A0, $A4, $80, $AC, $11, $30, $90, $24, $D4, $01
    .byte $A1, $A0, $84, $64, $80, $34, $04, $34, $80, $20, $21, $A1, $81, $A4, $80, $20
    .byte $90, $88, $C0, $00, $9A, $A0, $A0, $E0, $80, $B6, $A4, $20, $A2, $20, $98, $20
    .byte $88, $7C, $AE, $BD, $EE, $EE, $FE, $F1, $EC, $AD, $BC, $ED, $EC, $DD, $F9, $EC
    .byte $75, $B5, $BD, $EF, $FD, $A9, $E4, $96, $FC, $94, $E4, $AE, $AD, $DA, $B4, $AC
    .byte $7C, $C3, $EC, $BD, $FC, $AE, $FD, $EE, $FD, $85, $F4, $AD, $EF, $76, $FC, $D6
    .byte $6E, $EF, $ED, $F6, $BD, $ED, $FE, $58, $ED, $F7, $FD, $85, $EC, $FC, $E8, $F2
    .byte $E4, $BF, $A8, $30, $80, $A0, $05, $A4, $20, $B0, $80, $20, $84, $04, $80, $30
    .byte $8E, $E0, $A4, $B0, $02, $04, $80, $61, $84, $20, $00, $A0, $80, $20, $88, $24
    .byte $94, $24, $A4, $80, $04, $00, $84, $24, $84, $28, $9C, $44, $28, $A0, $80, $80
    .byte $90, $30, $80, $E8, $80, $A4, $88, $30, $94, $20, $80, $00, $8C, $68, $AC, $A4
    .byte $84, $30, $06, $86, $E4, $BC, $FC, $AE, $EC, $87, $BD, $9C, $FD, $EC, $BC, $FD
    .byte $B5, $A9, $ED, $A7, $AC, $8B, $7C, $A5, $FC, $CC, $BC, $AA, $B6, $C9, $FC, $A5
    .byte $FC, $47, $FC, $DD, $6D, $84, $FE, $AC, $EE, $20, $F4, $C5, $FF, $F4, $EE, $F7
    .byte $F4, $AA, $FC, $EF, $FF, $9C, $FD, $EE, $E4, $AF, $FC, $BE, $BC, $DF, $A5, $EB
    .byte $EC, $EE, $A4, $34, $86, $AC, $84, $A4, $21, $90, $88, $A0, $A0, $24, $C0, $E0
    .byte $80, $70, $E5, $3C, $A5, $A1, $8C, $34, $A4, $E4, $84, $24, $80, $F8, $81, $A0
    .byte $8D, $EC, $4A, $2C, $E2, $A4, $93, $20, $88, $B0, $C0, $34, $10, $20, $91, $A4
    .byte $84, $A4, $AE, $0C, $92, $B0, $CD, $B0, $AA, $74, $E8, $A0, $12, $B9, $85, $21
    .byte $F5, $E0, $8E, $9E, $BD, $81, $F5, $CF, $E4, $CC, $66, $A7, $AD, $98, $BD, $BC
    .byte $BC, $88, $BC, $8E, $ED, $A4, $A8, $AD, $88, $EE, $FE, $CD, $FC, $AC, $FD, $8C
    .byte $FC, $9A, $F5, $B4, $E4, $8E, $FC, $FE, $E4, $CC, $AC, $9D, $FC, $97, $E4, $8B
    .byte $EC, $EA, $EC, $DB, $EC, $DF, $EC, $AC, $E4, $AE, $FC, $D4, $F4, $CD, $EC, $B4
    .byte $EC, $EF, $EE, $B2, $24, $28, $20, $AC, $D0, $24, $1C, $30, $81, $AC, $84, $80
    .byte $01, $A4, $A4, $70, $88, $A4, $C4, $A4, $84, $24, $60, $08, $04, $A0, $88, $20
    .byte $98, $64, $A8, $24, $10, $D4, $90, $A0, $81, $30, $EC, $AC, $09, $64, $E0, $60
    .byte $18, $30, $B0, $24, $80, $6C, $88, $A4, $8C, $A4, $8C, $A8, $10, $21, $A8, $68
    .byte $84, $A8, $A0, $8D, $E5, $A4, $66, $98, $FD, $87, $FC, $DE, $AC, $9C, $F4, $8C
    .byte $F5, $B5, $F5, $B6, $F5, $A9, $F8, $AF, $ED, $E6, $E5, $B8, $F1, $B1, $FC, $FC
    .byte $E9, $8C, $EC, $86, $F9, $B5, $F7, $CD, $BC, $84, $E6, $8C, $FC, $81, $E4, $BC
    .byte $E4, $4F, $FC, $8C, $FC, $AE, $E7, $BD, $FC, $DC, $FC, $F4, $E8, $9F, $EC, $EA
    .byte $FC, $EF, $6C, $20, $82, $A4, $40, $A8, $8C, $AC, $08, $60, $82, $A1, $95, $E0
    .byte $30, $60, $80, $64, $48, $20, $04, $20, $84, $A4, $82, $A0, $04, $20, $94, $44
    .byte $A0, $E0, $80, $04, $C8, $2C, $82, $24, $04, $30, $B8, $24, $00, $20, $A0, $A4
    .byte $82, $A0, $80, $84, $81, $2C, $84, $20, $80, $24, $8C, $80, $80, $24, $02, $64
    .byte $A8, $24, $88, $ED, $BD, $D1, $FF, $B4, $E4, $AA, $EC, $80, $F1, $8C, $ED, $89
    .byte $AC, $B6, $FC, $6E, $FD, $AE, $ED, $89, $EC, $B6, $EC, $AE, $FD, $EE, $F0, $9F
    .byte $7E, $9F, $FE, $D9, $EC, $AE, $ED, $C6, $EC, $FE, $7D, $BC, $FC, $B9, $AC, $DA
    .byte $FC, $A5, $BD, $CC, $FD, $AD, $E6, $AE, $F4, $CD, $F4, $F2, $ED, $84, $78, $CC
    .byte $EC, $AB, $74, $A4, $94, $20, $84, $20, $00, $A0, $00, $A4, $05, $28, $0C, $24
    .byte $04, $24, $00, $A0, $84, $80, $80, $18, $80, $24, $0C, $E0, $88, $04, $8A, $2C
    .byte $88, $0C, $84, $00, $80, $E0, $04, $20, $A1, $20, $85, $20, $90, $80, $9C, $24
    .byte $C0, $E0, $8D, $A0, $80, $20, $82, $A0, $A2, $20, $40, $80, $82, $10, $B8, $00
    .byte $84, $60, $92, $DF, $EF, $D1, $EC, $A4, $EC, $C9, $FD, $E6, $AD, $C6, $E5, $D4
    .byte $FD, $9A, $ED, $AE, $E4, $AC, $BC, $9F, $EC, $8A, $ED, $0F, $E5, $8F, $EC, $D7
    .byte $E4, $AC, $EC, $CE, $EF, $9E, $F4, $D7, $E4, $CF, $F5, $CE, $F4, $E6, $6C, $81
    .byte $EC, $9B, $EE, $9F, $7C, $BC, $F7, $CC, $6D, $FE, $EF, $8E, $6E, $EF, $BD, $BE
    .byte $BD, $8F, $E4, $A0, $04, $20, $E0, $B4, $82, $B4, $82, $20, $8C, $B0, $90, $B0
    .byte $90, $B8, $84, $24, $90, $6A, $86, $28, $84, $A0, $A8, $24, $CF, $B8, $88, $A0
    .byte $A0, $B1, $81, $10, $B6, $E0, $98, $C8, $B4, $34, $AF, $34, $00, $B0, $82, $20
    .byte $90, $E4, $AC, $28, $84, $84, $88, $24, $AC, $AC, $A4, $25, $98, $20, $A0, $20
    .byte $80, $32, $00, $AE, $EC, $8D, $BD, $9F, $F7, $FF, $A1, $CA, $BE, $8D, $7C, $8E
    .byte $74, $EF, $EC, $D4, $F5, $9E, $B8, $8E, $35, $C6, $E4, $90, $ED, $ED, $FC, $8C
    .byte $25, $BE, $A4, $FC, $6C, $89, $EE, $EC, $AD, $AE, $78, $EE, $EC, $AD, $ED, $AD
    .byte $EC, $BC, $BD, $2E, $76, $AE, $EC, $8E, $BD, $EF, $FD, $AC, $EC, $EF, $B5, $BE
    .byte $A4, $BF, $E8, $04, $00, $24, $08, $04, $84, $24, $80, $28, $82, $60, $04, $24
    .byte $94, $28, $00, $2C, $84, $20, $80, $B5, $86, $30, $04, $23, $84, $A0, $80, $A0
    .byte $06, $24, $AD, $A4, $80, $A6, $86, $80, $00, $E0, $80, $66, $90, $20, $8C, $00
    .byte $8C, $04, $82, $A4, $46, $00, $01, $20, $98, $A0, $88, $20, $2A, $24, $E0, $00
    .byte $08, $64, $02, $8D, $A5, $B5, $E5, $AD, $F7, $CD, $F4, $A8, $29, $BC, $64, $F8
    .byte $EC, $AD, $AE, $A8, $F5, $8C, $A7, $E7, $E5, $A9, $F4, $F4, $FD, $94, $ED, $5C
    .byte $E4, $C0, $BE, $8C, $FD, $CD, $A4, $94, $FF, $A5, $EC, $FC, $E5, $AC, $E4, $AE
    .byte $BD, $9D, $BD, $A8, $EC, $84, $68, $C9, $AD, $8E, $AC, $EA, $ED, $8F, $EC, $BF
    .byte $AF, $F7, $ED, $24, $91, $A0, $04, $B4, $04, $82, $90, $AC, $08, $B0, $A0, $C0
    .byte $08, $34, $A0, $65, $88, $73, $80, $20, $80, $2C, $04, $20, $84, $21, $26, $20
    .byte $94, $00, $20, $A4, $96, $A4, $80, $B0, $84, $24, $82, $25, $86, $A0, $00, $7C
    .byte $30, $A2, $25, $24, $9E, $A0, $88, $20, $80, $20, $00, $20, $A9, $20, $A2, $C0
    .byte $B2, $A1, $0E, $AE, $EC, $A8, $EE, $AC, $F8, $FA, $B4, $A4, $FE, $FC, $F4, $1C
    .byte $ED, $AE, $F4, $D7, $F8, $FD, $ED, $8E, $FE, $DC, $E8, $FE, $ED, $FC, $ED, $9F
    .byte $FC, $9C, $ED, $B0, $E7, $BE, $FE, $84, $E4, $A7, $FE, $AD, $E4, $BC, $64, $8D
    .byte $BF, $AF, $FD, $AA, $2C, $CD, $ED, $8F, $E4, $FC, $BD, $BF, $EF, $E5, $ED, $BF
    .byte $FE, $E5, $FD, $84, $82, $A4, $83, $A4, $08, $A0, $80, $00, $84, $30, $86, $08
    .byte $20, $B0, $90, $14, $B4, $A0, $80, $20, $90, $A4, $88, $EC, $80, $A4, $84, $A0
    .byte $84, $28, $80, $B4, $81, $F0, $A0, $E4, $80, $00, $84, $34, $B1, $E4, $80, $24
    .byte $5D, $20, $D2, $44, $83, $B0, $88, $20, $14, $30, $BC, $20, $A0, $C4, $9D, $68
    .byte $00, $A0, $20, $CF, $EC, $AA, $66, $B8, $75, $9E, $FC, $FE, $B4, $BC, $FF, $AC
    .byte $FD, $9A, $BC, $BA, $EC, $8E, $F4, $EC, $FC, $96, $FD, $D2, $EA, $84, $FC, $AE
    .byte $E4, $E5, $FD, $BD, $EC, $DC, $AC, $A5, $B0, $CF, $EC, $7A, $B5, $E4, $EA, $EF
    .byte $EC, $A4, $FE, $E5, $FF, $F8, $BC, $86, $E4, $FF, $E5, $AF, $6C, $EE, $EC, $EE
    .byte $6C, $2A, $6C, $28, $A0, $64, $84, $B4, $92, $04, $94, $80, $00, $B8, $0C, $20
    .byte $88, $A0, $84, $A0, $40, $B0, $00, $A0, $84, $A0, $CA, $00, $14, $24, $C0, $A0
    .byte $64, $24, $88, $00, $18, $ED, $88, $28, $80, $A1, $80, $00, $85, $20, $80, $A4
    .byte $34, $00, $04, $24, $A4, $AC, $8C, $34, $88, $2C, $04, $24, $84, $60, $88, $A0
    .byte $A0, $A0, $9C, $B9, $F4, $97, $EC, $68, $AD, $E4, $F0, $F4, $EC, $CB, $FC, $A8
    .byte $F5, $FD, $3E, $FC, $EE, $9D, $EC, $5E, $FC, $9C, $F6, $80, $ED, $A2, $E4, $AD
    .byte $B6, $BF, $F4, $ED, $FE, $B3, $FC, $DC, $B5, $B3, $ED, $EF, $FC, $BF, $FC, $BC
    .byte $FE, $EA, $F4, $C5, $E4, $89, $FC, $7C, $BD, $DE, $FD, $87, $E4, $9E, $EC, $AF
    .byte $E4, $FE, $E4, $34, $C6, $30, $26, $24, $80, $20, $1C, $B4, $04, $B4, $28, $24
    .byte $98, $20, $00, $A4, $A4, $A0, $80, $21, $48, $B9, $24, $20, $80, $28, $00, $20
    .byte $80, $84, $1E, $60, $BC, $28, $88, $AC, $74, $E0, $04, $24, $A6, $00, $20, $70
    .byte $85, $A0, $89, $30, $0B, $A0, $80, $20, $10, $A0, $14, $24, $04, $20, $82, $A0
    .byte $80, $35, $A0, $EE, $BC, $BE, $FD, $BE, $B9, $89, $E4, $FD, $3D, $13, $E4, $9E
    .byte $EC, $8D, $EC, $DE, $FC, $8E, $E5, $8F, $F4, $BE, $FF, $E6, $E6, $8C, $E6, $CD
    .byte $AE, $EE, $ED, $FE, $EC, $DC, $EC, $8E, $FC, $96, $FD, $A6, $FC, $CE, $CD, $BE
    .byte $FE, $EE, $FC, $9E, $F4, $EE, $6E, $CF, $ED, $EE, $E0, $FC, $EE, $AE, $A0, $FD
    .byte $ED, $A6, $6C, $A8, $04, $20, $00, $30, $80, $A0, $90, $20, $80, $60, $00, $20
    .byte $82, $90, $40, $24, $10, $04, $00, $84, $00, $24, $18, $E0, $00, $00, $02, $20
    .byte $B4, $24, $00, $22, $80, $04, $04, $A0, $80, $84, $0A, $28, $14, $A0, $80, $00
    .byte $86, $40, $86, $20, $90, $10, $30, $84, $84, $00, $00, $74, $80, $30, $00, $20
    .byte $08, $20, $80, $FB, $FD, $C9, $E6, $91, $FD, $C8, $EE, $B4, $7C, $BE, $EC, $89
    .byte $EC, $BD, $FC, $A5, $FD, $D9, $EC, $8A, $FD, $AE, $EC, $AD, $FC, $AE, $EC, $8D
    .byte $EC, $8F, $F4, $BF, $6D, $AC, $BD, $EA, $ED, $AF, $AC, $FD, $FC, $EA, $FD, $F0
    .byte $F9, $B3, $EE, $8E, $E4, $FD, $EC, $FF, $E0, $8E, $E4, $FD, $AD, $DC, $6C, $A0
    .byte $E4, $8E, $E4, $28, $00, $B4, $00, $22, $00, $B4, $00, $6C, $00, $A4, $1B, $B2
    .byte $9C, $20, $84, $24, $C4, $24, $A8, $A0, $80, $64, $88, $80, $AC, $30, $85, $20
    .byte $9C, $74, $F2, $88, $88, $38, $80, $2C, $A0, $20, $04, $B8, $80, $24, $90, $A8
    .byte $F8, $BC, $88, $20, $20, $A0, $E0, $6C, $80, $00, $E8, $20, $80, $24, $C0, $23
    .byte $9C, $24, $82, $B5, $E0, $A4, $ED, $8E, $E4, $A9, $FC, $F8, $EE, $CE, $FC, $89
    .byte $E4, $98, $F5, $A1, $EC, $A1, $E0, $B8, $EC, $D0, $FC, $CF, $F9, $AE, $EC, $8A
    .byte $FD, $6B, $6E, $94, $A8, $B8, $E4, $CE, $A6, $8C, $F4, $EE, $BD, $8D, $EC, $ED
    .byte $F4, $CF, $6C, $99, $6C, $C8, $F9, $F9, $A5, $B6, $79, $8C, $C1, $E4, $F5, $AA
    .byte $24, $F7, $64, $24, $A8, $A4, $80, $A0, $96, $20, $09, $20, $18, $A8, $08, $B0
    .byte $C0, $7C, $CD, $24, $DC, $20, $98, $64, $84, $E0, $82, $34, $A0, $EA, $88, $60
    .byte $C4, $70, $E8, $30, $06, $E5, $1C, $20, $84, $20, $9C, $A0, $80, $A0, $1C, $A8
    .byte $80, $88, $22, $24, $80, $24, $B0, $E4, $14, $E4, $80, $E0, $86, $00, $D6, $8C
    .byte $80, $B8, $AB, $AF, $A2, $84, $E8, $86, $2F, $8A, $F5, $D4, $FF, $86, $EF, $8E
    .byte $F4, $C8, $6C, $F5, $F4, $4C, $F4, $E8, $74, $04, $EE, $EE, $E0, $26, $2C, $9F
    .byte $EC, $90, $E5, $BC, $E5, $F8, $E0, $FB, $F4, $B4, $ED, $4E, $E4, $E6, $EC, $8C
    .byte $E4, $BF, $ED, $9F, $E0, $CC, $7C, $BF, $ED, $9D, $ED, $AD, $F8, $AF, $64, $EF
    .byte $ED, $ED, $E4, $A0, $8C, $20, $95, $30, $38, $A0, $84, $64, $80, $E0, $76, $2C
    .byte $20, $B4, $04, $3F, $B1, $A4, $24, $24, $80, $24, $A9, $31, $97, $AC, $28, $64
    .byte $50, $A0, $04, $38, $80, $B4, $8E, $20, $CC, $BC, $38, $64, $8C, $A0, $90, $E4
    .byte $A0, $64, $99, $64, $AF, $24, $E5, $60, $80, $A4, $3C, $2C, $8E, $B4, $BC, $A4
    .byte $CC, $24, $CC
.else
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $13, $34, $06, $9D, $A5, $27, $03, $BD, $95, $81, $96, $B5, $97, $D8, $35, $06
    .byte $DD, $B4, $4F, $34, $56, $BD, $95, $22, $BD, $92, $8F, $DF, $D9, $BD, $99, $DF
    .byte $27, $0F, $BD, $99, $CB, $86, $01, $97, $D7, $BD, $99, $BA, $00, $D7, $BD, $99
    .byte $BA, $10, $DF, $DC, $0D, $DB, $26, $03, $10, $DE, $DC, $35, $56, $0F, $DB, $10
    .byte $DF, $DC, $30, $01, $9F, $BD, $DF, $D1, $97, $D7, $27, $9F, $2B, $06, $5C, $D1
    .byte $D6, $23, $05, $5F, $5D, $27, $DD, $5A, $D7, $C0, $BD, $99, $DF, $27, $0F, $10
    .byte $83, $00, $03, $25, $04, $30, $1E, $8D, $38, $BD, $99, $CB, $8D, $4C, $43, $53
    .byte $D3, $D1, $DD, $D1, $2F, $16, $BD, $95, $06, $BD, $9A, $12, $26, $05, $CC, $FF
    .byte $FF, $20, $ED, $BD, $95, $14, $8D, $3E, $8D, $5E, $20, $E0, $BD, $95, $06, $30
    .byte $8B, $9F, $BD, $43, $53, $83, $00, $01, $2F, $04, $1F, $01, $8D, $03, $7E, $99
    .byte $34, $DD, $CB, $35, $20, $DC, $BD, $34, $16, $96, $D7, $40, $D6, $C0, $34, $06
    .byte $34, $20, $C6, $02, $BD, $AC, $33, $DC, $CB, $39, $DD, $CB, $35, $20, $DC, $C3
    .byte $34, $16, $96, $D7, $20, $E6, $9E, $BD, $9F, $C3, $39, $DD, $CD, $10, $9E, $C3
    .byte $8D, $F4, $10, $9F, $BD, $8D, $11, $9E, $CD, $30, $8B, $C3, $00, $01, $39, $BD
    .byte $99, $C6, $10, $8E, $95, $14, $20, $06, $10, $8E, $95, $06, $AD, $A4, $DE, $8A
    .byte $9E, $BD, $2B, $17, $9C, $D3, $22, $13, $34, $60, $8D, $16, $27, $0B, $BD, $93
    .byte $77, $35, $60, $33, $41, $AD, $A4, $20, $E9, $35, $60, $1F, $30, $1F, $01, $93
    .byte $8A, $39, $AD, $9F, $00, $D9, $1F, $89, $D4, $D8, $34, $06, $A4, $84, $A1, $61
    .byte $35, $86, $9E, $8A, $C6, $01, $34, $14, $BD, $B1, $56, $5F, $BD, $A9, $A2, $BD
    .byte $A9, $76, $BD, $B6, $54, $20, $02, $35, $14, $D7, $D8, $27, $FA, $9F, $D9, $10
    .byte $27, $0F, $31, $0D, $D8, $27, $F0, $BD, $9B, $98, $81, $3B, $27, $F5, $81, $27
    .byte $27, $F1, $81, $58, $10, $27, $01, $B2, $8D, $02, $20, $E7, $81, $4F, $26, $0D
    .byte $D6, $DE, $5C, $8D, $5B, $5A, $C1, $04, $22, $63, $D7, $DE, $39, $81, $56, $26
    .byte $1A, $D6, $DF, $54, $54, $C0, $1F, $8D, $47, $C1, $1F, $22, $50, $58, $58, $34
    .byte $04, $CC, $7E, $7E, $AB, $E4, $E0, $E0, $DD, $DF, $39, $81, $4C, $26, $23, $D6
    .byte $E1, $8D, $2D, $5D, $27, $37, $D7, $E1, $0F, $E5, $8D, $03, $24, $FC, $39, $0D
    .byte $D8, $27, $0A, $BD, $9B, $98, $81, $2E, $27, $05, $BD, $9B, $E2, $43, $39, $0C
    .byte $E5, $39, $81, $54, $26, $0D, $D6, $E2, $8D, $06, $5D, $27, $10, $D7, $E2, $39
    .byte $7E, $9B, $AC, $81, $50, $26, $24, $BD, $9C, $CB, $5D, $26, $03, $7E, $B4, $4A
    .byte $96, $E5, $9E, $DF, $34, $12, $86, $7E, $97, $DF, $97, $E0, $0F, $E5, $8D, $07
    .byte $35, $12, $97, $E5, $9F, $DF, $39, $6F, $E2, $20, $40, $81, $4E, $26, $03, $BD
    .byte $9B, $98, $81, $41, $25, $04, $81, $47, $23, $05, $BD, $9B, $BE, $20, $23, $80
    .byte $41, $8E, $9C, $5B, $E6, $86, $0D, $D8, $27, $18, $BD, $9B, $98, $81, $23, $27
    .byte $04, $81, $2B, $26, $03, $5C, $20, $0A, $81, $2D, $26, $03, $5A, $20, $03, $BD
    .byte $9B, $E2, $5A, $C1, $0B, $22, $A6, $34, $04, $D6, $E1, $96, $E2, $3D, $DD, $D5
    .byte $33, $61, $96, $DE, $81, $01, $22, $2C, $8E, $9C, $62, $C6, $18, $3D, $3A, $35
    .byte $04, $58, $3A, $31, $84, $8D, $45, $DD, $E3, $8D, $0C, $96, $DF, $8D, $0B, $8D
    .byte $06, $96, $E0, $8D, $05, $20, $F2, $86, $7E, $12, $B7, $FF, $20, $AE, $A4, $30
    .byte $1F, $26, $FC, $39, $8E, $9C, $7A, $C6, $0C, $3D, $3A, $35, $04, $3A, $8D, $1C
    .byte $DD, $E3, $8D, $0C, $96, $DF, $8D, $0B, $8D, $06, $96, $E0, $8D, $05, $20, $F2
    .byte $86, $7E, $12, $B7, $FF, $20, $A6, $84, $4A, $26, $FD, $39, $C6, $FF, $96, $E5
    .byte $27, $05, $8B, $02, $3D, $44, $56, $39, $34, $10, $0D, $D8, $27, $4D, $9E, $D9
    .byte $A6, $80, $9F, $D9, $0A, $D8, $81, $20, $27, $F0, $35, $90, $8D, $EA, $81, $2B
    .byte $27, $3C, $81, $2D, $27, $3C, $81, $3E, $27, $42, $81, $3C, $27, $39, $81, $3D
    .byte $27, $3F, $BD, $90, $AA, $25, $24, $5F, $80, $30, $97, $D7, $86, $0A, $3D, $4D
    .byte $26, $19, $DB, $D7, $25, $15, $0D, $D8, $27, $17, $BD, $9B, $98, $BD, $90, $AA
    .byte $24, $E6, $0C, $D8, $9E, $D9, $30, $1F, $9F, $D9, $39, $7E, $B4, $4A, $5C, $27
    .byte $FA, $39, $5D, $27, $F6, $5A, $39, $5D, $27, $F1, $54, $39, $5D, $2B, $EC, $58
    .byte $39, $34, $60, $8D, $16, $BD, $B7, $0E, $35, $E0, $BD, $9C, $1B, $C6, $02, $BD
    .byte $AC, $33, $D6, $D8, $9E, $D9, $34, $14, $7E, $9A, $32, $9E, $D9, $34, $10, $BD
    .byte $9B, $98, $BD, $B3, $A2, $25, $C4, $BD, $9B, $98, $81, $3B, $26, $F9, $35, $10
    .byte $DE, $A6, $34, $40, $9F, $A6, $BD, $B2, $84, $35, $10, $9F, $A6, $39, $4F, $1F
    .byte $8B, $DC, $E3, $10, $27, $0D, $74, $93, $D5, $DD, $E3, $22, $0D, $0F, $E3, $0F
    .byte $E4, $35, $02, $10, $EE, $67, $84, $7F, $34, $02, $3B, $0A, $0C, $01, $03, $05
    .byte $06, $08, $01, $A8, $01, $90, $01, $7A, $01, $64, $01, $50, $01, $3D, $01, $2B
    .byte $01, $1A, $01, $0A, $00, $FB, $00, $ED, $00, $DF, $00, $D3, $00, $C7, $00, $BB
    .byte $00, $B1, $00, $A6, $00, $9D, $00, $94, $00, $8B, $00, $83, $00, $7C, $00, $75
    .byte $00, $6E, $A6, $9C, $93, $8B, $83, $7B, $74, $6D, $67, $61, $5B, $56, $51, $4C
    .byte $47, $43, $3F, $3B, $37, $34, $31, $2E, $2B, $28, $26, $23, $21, $1F, $1D, $1B
    .byte $19, $18, $16, $14, $13, $12, $9E, $8A, $C6, $01, $34, $14, $D7, $C2, $9F, $D5
    .byte $BD, $95, $9A, $BD, $B1, $56, $BD, $B6, $54, $20, $08, $BD, $9B, $98, $7E, $9B
    .byte $BE, $35, $14, $D7, $D8, $27, $FA, $9F, $D9, $10, $27, $00, $EA, $0D, $D8, $27
    .byte $F0, $BD, $9B, $98, $81, $3B, $27, $F5, $81, $27, $27, $F1, $81, $4E, $26, $04
    .byte $03, $D5, $20, $E9, $81, $42, $26, $04, $03, $D6, $20, $E1, $81, $58, $10, $27
    .byte $00, $96, $81, $4D, $10, $27, $01, $2A, $34, $02, $C6, $01, $0D, $D8, $27, $11
    .byte $BD, $9B, $98, $BD, $B3, $A2, $34, $01, $BD, $9B, $E2, $35, $01, $24, $02, $8D
    .byte $AA, $35, $02, $81, $43, $27, $28, $81, $41, $27, $2E, $81, $53, $27, $32, $81
    .byte $55, $27, $5C, $81, $44, $27, $55, $81, $4C, $27, $4C, $81, $52, $27, $43, $80
    .byte $45, $27, $2F, $4A, $27, $27, $4A, $27, $32, $4A, $27, $1D, $7E, $B4, $4A, $BD
    .byte $95, $5D, $D7, $B2, $BD, $95, $9A, $20, $84, $C1, $04, $24, $EF, $D7, $E8, $20
    .byte $F6, $C1, $3F, $24, $E7, $D7, $E9, $20, $EE, $4F, $8D, $58, $21, $4F, $1F, $01
    .byte $20, $59, $4F, $1F, $01, $8D, $4D, $1E, $01, $20, $50, $4F, $1F, $01, $8D, $44
    .byte $20, $49, $4F, $9E, $8A, $20, $44, $4F, $8D, $3A, $20, $F7, $4F, $20, $03, $4F
    .byte $8D, $32, $9E, $8A, $1E, $10, $20, $33, $BD, $9C, $1B, $C6, $02, $BD, $AC, $33
    .byte $D6, $D8, $9E, $D9, $34, $14, $7E, $9C, $C6, $D6, $E9, $27, $1B, $4F, $1E, $01
    .byte $A7, $E2, $2A, $02, $8D, $0D, $BD, $9F, $B5, $1F, $30, $44, $56, $44, $56, $6D
    .byte $E0, $2A, $04, $40, $50, $82, $00, $39, $1F, $10, $39, $34, $06, $8D, $DA, $35
    .byte $10, $34, $06, $8D, $D4, $35, $10, $10, $9E, $E8, $34, $20, $6D, $E4, $27, $08
    .byte $1E, $10, $8D, $DF, $6A, $E4, $20, $F4, $35, $20, $DE, $8A, $D3, $C7, $2B, $02
    .byte $1F, $03, $1F, $10, $9E, $8A, $D3, $C9, $2B, $02, $1F, $01, $11, $83, $01, $00
    .byte $25, $03, $CE, $00, $FF, $8C, $00, $C0, $25, $03, $8E, $00, $BF, $DC, $C7, $DD
    .byte $BD, $DC, $C9, $DD, $BF, $9F, $C5, $DF, $C3, $0D, $D5, $26, $04, $9F, $C9, $DF
    .byte $C7, $BD, $94, $20, $0D, $D6, $26, $03, $BD, $94, $A1, $0F, $D5, $0F, $D6, $7E
    .byte $9C, $DD, $BD, $9B, $98, $34, $02, $BD, $9E, $5E, $34, $06, $BD, $9B, $98, $81
    .byte $2C, $10, $26, $FF, $07, $BD, $9E, $5B, $1F, $01, $35, $40, $35, $02, $81, $2B
    .byte $27, $04, $81, $2D, $26, $A6, $1F, $30, $7E, $9D, $CB, $BD, $9B, $98, $81, $2B
    .byte $27, $07, $81, $2D, $27, $04, $BD, $9B, $E2, $4F, $34, $02, $BD, $9C, $CB, $35
    .byte $02, $4D, $27, $04, $4F, $50, $82, $00, $39, $00, $00, $00, $01, $FE, $C5, $19
    .byte $19, $FB, $16, $31, $F2, $F4, $FB, $4A, $51, $EC, $84, $61, $F9, $E1, $C7, $78
    .byte $AE, $D4, $DC, $8E, $3B, $C5, $E5, $A2, $69, $B5, $06, $B5, $06, $81, $40, $26
    .byte $02, $9D, $9F, $BD, $95, $22, $BD, $93, $B2, $BD, $93, $1D, $AE, $C4, $9F, $CB
    .byte $AE, $42, $9F, $CD, $BD, $B2, $6D, $BD, $B7, $3D, $CE, $00, $CF, $AF, $C4, $BD
    .byte $93, $20, $86, $01, $97, $C2, $BD, $95, $81, $8E, $01, $00, $9D, $A5, $27, $0F
    .byte $BD, $B2, $6D, $BD, $B1, $41, $96, $4F, $8B, $08, $97, $4F, $BD, $B7, $40, $96
    .byte $B6, $85, $02, $27, $04, $1F, $10, $30, $8B, $9F, $D1, $C6, $01, $D7, $C2, $D7
    .byte $D8, $BD, $9F, $E2, $34, $06, $BD, $9F, $E2, $DD, $D9, $35, $06, $34, $06, $9E
;; DOS's routine, at $DF00 in 1.1: reads track 34 of drive 0, all 18 sectors, into memory from <DOSBUF>, and runs it
;; at <DOSBUF>+2 when it starts with OS, as an OS-9 boot track does. Otherwise it clears the mark and warm starts
;; BASIC. It starts with SWI3, which <DOSINI> points at an RTI, so a debugger can stop there.
;;
;; Errors: ?IO ERROR when a sector cannot be read
DOSCOM:
    SWI3
    CLR TMPLOC                      ; the sector
    LDD #DOSBUF
    PSHS A,B
DOSCOM_SECTOR:
    LDX DSKVAR
    INC TMPLOC
    LDA TMPLOC
    CMPA #SECMAX
    BHI DOSCOM_LOADED
    STA 3,X                         ; DSEC
    LDD #$0200
    STA ,X                          ; read; the drive is not stored, so the one DSKCON used last is read
    LDA #TRKMAX-1
    STA 2,X                         ; DCTRK
    PULS A,B
    STD 4,X                         ; DCBPT
    ADDA #1                         ; the next 256 bytes
    PSHS A,B
    JSR [DCNVEC]
    TST 6,X                         ; DCSTA
    BEQ DOSCOM_SECTOR
    PULS A,B
    LDB #ERR_IO
    JMP ERROR
DOSCOM_LOADED:
    PULS A,B
    LDD DOSBUF
    CMPD #$4F53                     ; "OS"
    LBEQ DOSBUF+2
    CLR DOSBUF
    CLR DOSBUF+1
    JMP BAWMST

;; Points SWI3 and SWI2 at an RTI, for <DOSCOM>: <DKINIT> calls it through <DSINIT>.
DOSINI:
    LDD #$3B3B                      ; RTI, RTI
    STD SW3VEC
    STD SW3VEC+2
    STD SW2VEC+1
    RTS

; Unused, to the end.
    .byte $00, $00, $00, $00, $00, $00, $00, $05, $10, $93, $D3, $25, $02, $DC, $D3, $DD
    .byte $C3, $A6, $E4, $81, $04, $25, $0A, $DC, $CD, $93, $C5, $24, $11, $4F, $5F, $20
    .byte $0D, $DC, $CD, $D3, $C5, $25, $05, $10, $93, $D5, $25, $02, $DC, $D5, $DD, $C5
    .byte $0D, $D8, $26, $02, $8D, $50, $35, $06, $04, $D8, $25, $05, $10, $93, $D9, $27
    .byte $0C, $5C, $C1, $08, $26, $04, $4C, $5F, $84, $07, $7E, $9E, $FD, $39, $9E, $CF
    .byte $EC, $C4, $27, $07, $83, $00, $01, $8D, $03, $1F, $21, $39, $34, $76, $6F, $64
    .byte $A6, $63, $3D, $ED, $66, $EC, $61, $3D, $EB, $66, $89, $00, $ED, $65, $E6, $E4
    .byte $A6, $63, $3D, $E3, $65, $ED, $65, $24, $02, $6C, $64, $A6, $E4, $E6, $62, $3D
    .byte $E3, $64, $ED, $64, $35, $F6, $7E, $94, $A1, $5F, $9D, $A5, $27, $11, $BD, $B2
    .byte $6D, $BD, $B1, $41, $96, $4F, $8B, $06, $97, $4F, $BD, $B7, $0E, $C4, $3F, $1F
    .byte $98, $C4, $07, $44, $44, $44, $39
.endif
