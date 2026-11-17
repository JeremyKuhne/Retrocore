;; TRS-80 COLOR COMPUTER DISK BASIC EQUATES: ITS RAM, FILE LAYOUTS, CONTROLLER, TOKENS AND ERROR CODES
;;
;; The RAM Disk Extended Color BASIC adds, in the direct page and from $0600, with the names Microsoft's BASIC and
;; Spectral Associates' Disk Basic Unravelled give them; the layouts of a file control block, a directory entry
;; and the file allocation table; the disk controller's registers; and Disk BASIC's tokens and error codes. Disk
;; BASIC includes this file after Color and Extended BASIC's equates.

; ----------------------------------------------------------------------------------------------------------------
; Disks
; ----------------------------------------------------------------------------------------------------------------

;; The bytes in a sector.
SECLEN = 256

;; The sectors in a track, numbered from 1.
SECMAX = 18

;; The bytes in a track.
TRKLEN = SECMAX*SECLEN

;; The tracks on a disk, 0 to 34. Track 17 holds the directory; the rest hold two granules each.
TRKMAX = 35

;; The bytes in a directory entry, eight to a sector.
DIRLEN = 32

;; The granules on a disk: two of nine sectors in each track but the directory's.
GRANMX = (TRKMAX-1)*2

;; The bytes in a file allocation table: <FATCON> control bytes, then one byte for each granule.
FATLEN = 6+GRANMX

;; The bytes in a file control block: <FCBCON> control bytes, then a sector's data.
FCBLEN = SECLEN+25

;; Where DOS loads track 34 to and starts it: the boot track of an OS-9 disk.
;;
;; See: <DOS>
DOSBUF = $2600

; ----------------------------------------------------------------------------------------------------------------
; The file allocation table: a FAT, at <FATBL0> and after, holds its control bytes, then a byte for each granule:
; $FF when free, the next granule while a file goes on, or $C0 plus the sectors it uses in a file's last granule.
; ----------------------------------------------------------------------------------------------------------------

;; A FAT's count of open files on its drive: while any is open, the FAT in RAM is the one that counts, and it is
;; not read from the disk again.
FAT0 = 0

;; A FAT's flag: nonzero when it has changed since it was written to the disk.
FAT1 = 1

;; Where a FAT's granule bytes start.
FATCON = 6

; ----------------------------------------------------------------------------------------------------------------
; A directory entry: the directory is sectors 3 to 11 of track 17, eight entries to a sector. An entry whose name
; starts with 0 is a killed file, and with $FF one never used, which ends the directory.
; ----------------------------------------------------------------------------------------------------------------

;; The file's name, eight characters padded with spaces.
DIRNAM = 0

;; The file's extension, three characters.
DIREXT = 8

;; The file's type: 0 a BASIC program, 1 BASIC data, 2 machine language, 3 an editor's source.
DIRTYP = 11

;; The file's ASCII flag: 0 for a crunched program or binary, $FF for text.
DIRASC = 12

;; The file's first granule.
DIRGRN = 13

;; The bytes the file uses in its last sector, high byte first.
DIRLST = 14

; ----------------------------------------------------------------------------------------------------------------
; A file control block (FCB): 25 control bytes, then a sector's buffer. <FCBV1> holds where each is. Some control
; bytes mean one thing in a random file and another in a sequential one.
; ----------------------------------------------------------------------------------------------------------------

;; The FCB's file type: <INPFIL>, <OUTFIL> or <RANFIL>, or 0 when it is closed.
FCBTYP = 0

;; The file's drive.
FCBDRV = 1

;; The file's first granule.
FCBFGR = 2

;; The granule the FCB is in.
FCBCGR = 3

;; The sector of that granule the FCB is in, from 1.
FCBSEC = 4

;; Sequential files: an input file's place in its buffer, or for an output file 1 once its last sector is full.
FCBCPT = 5

;; Sequential output files: the print position, for TAB and commas; 0 in a random file.
FCBPOS = 6

;; The record number in a random file; the whole sectors read or written in a sequential one.
FCBREC = 7

;; A random file's record length.
FCBRLN = 9

;; Where a random file's record buffer is: a record's length, in the random file buffer space.
FCBBUF = 11

;; A random file's sector offset to the current record, its high byte set to $FF to read a fresh sector.
FCBSOF = 13

;; A random file's GET/PUT flag: 0 for GET, nonzero for PUT.
FCBFLG = 15

;; Sequential input files: nonzero when a character after a carriage return was read and is kept for next time.
FCBCFL = 16

;; Sequential input files: the character <FCBCFL> keeps.
FCBCDT = 17

;; The file's directory entry, 0 to 71.
FCBDIR = 18

;; The bytes the file uses in its last sector, high byte first, as in the directory. Bit 15 is set when the
;; directory's count must change, which CLOSE does.
FCBLST = 19

;; A random file's GET count: the characters INPUT has taken from the record.
FCBGET = 21

;; A random file's PUT count: where in the record PRINT puts the next character.
FCBPUT = 23

;; Sequential input files: nonzero when the file has no data left.
FCBDFL = 23

;; Sequential files: the characters left in the buffer of an input file, or in the buffer of an output file.
FCBLFT = 24

;; Where an FCB's sector buffer starts.
FCBCON = 25

;; <FCBTYP> for a sequential input file.
INPFIL = $10

;; <FCBTYP> for a sequential output file.
OUTFIL = $20

;; <FCBTYP> for a random file.
RANFIL = $40

; ----------------------------------------------------------------------------------------------------------------
; The direct page: DSKCON's arguments
; ----------------------------------------------------------------------------------------------------------------

;; DSKCON's operation: 0 restores the head to track 0, 1 seeks, 2 reads a sector and 3 writes one.
;;
;; <DSKVAR> points programs at this and the five arguments after it.
;; See: <DSKCON>, <DCDRV>, <DCTRK>, <DSEC>, <DCBPT>, <DCSTA>
DCOPC = $EA

;; DSKCON's drive, 0 to 3.
;;
;; See: <DSKCON>, <DCOPC>
DCDRV = $EB

;; DSKCON's track, 0 to 34.
;;
;; See: <DSKCON>, <DCOPC>
DCTRK = $EC

;; DSKCON's sector, 1 to 18.
;;
;; See: <DSKCON>, <DCOPC>
DSEC = $ED

;; DSKCON's buffer: where a sector read goes, or a sector written comes from.
;;
;; See: <DSKCON>, <DCOPC>
DCBPT = $EE

;; DSKCON's status: 0 when it worked, or the controller's error bits.
;;
;; Bit 7 is not ready, 6 write protected, 5 a write fault, 4 a seek error or record not found, 3 a CRC error and 2
;; lost data.
;; See: <DSKCON>, <DCOPC>
DCSTA = $F0

;; The file control block the routine at hand is working on.
FCBTMP = $F1

; ----------------------------------------------------------------------------------------------------------------
; The RAM from $0600: buffers, the FATs and the file system's state. Disk BASIC moves the program up past them.
; ----------------------------------------------------------------------------------------------------------------

;; A sector buffer, which the directory and FAT are read through.
DBUF0 = $0600

;; A second sector buffer, for copying and checking.
DBUF1 = $0700

;; Drive 0's file allocation table, as in RAM: <FATLEN> bytes, as laid out from <FAT0>.
FATBL0 = $0800

;; Drive 1's file allocation table.
FATBL1 = $084A

;; Drive 2's file allocation table.
FATBL2 = $0894

;; Drive 3's file allocation table.
FATBL3 = $08DE

;; Where each file control block is: sixteen addresses, for files 1 to 15 and then the system's own, which LOAD,
;; SAVE, MERGE, COPY and the rest use. FILES sets how many there are.
FCBV1 = $0928

;; Where the random file buffer space starts: FILES reserves it, and each random file's record buffer is in it.
RNBFAD = $0948

;; Where the file control blocks start, after the random file buffer space.
FCBADR = $094A

;; The file name being looked for or made: eight characters padded with spaces.
DNAMBF = $094C

;; The file's extension: three characters padded with spaces.
DEXTBF = $0954

;; The file type for a new directory entry, as <DIRTYP>.
DFLTYP = $0957

;; The ASCII flag for a new directory entry, as <DIRASC>.
DASCFL = $0958

;; LOAD's flags: bit 1 runs the program after loading it, and bit 0 keeps the files open when it does.
DRUNFL = $0959

;; The drive a name without one uses, which DRIVE sets.
DEFDRV = $095A

;; The number of user file control blocks, which FILES sets.
FCBACT = $095B

;; Nonzero when a reset must do a NEW and close every file: set while a program is loading or merging.
DRESFL = $095C

;; Nonzero while a load is under way, so an error in it does a NEW.
DLODFL = $095D

;; Nonzero when LOAD merges, for MERGE.
DMRGFL = $095E

;; The USR table, when Disk BASIC moves it here: ten addresses, for USR0 to USR9.
DUSRVC = $095F

;; A directory search's result for the file found: the directory sector it is in.
FNDSEC = $0973

;; Where its entry is, in the sector read into <DBUF0>.
FNDDIR = $0974

;; Its first granule.
FNDGRN = $0976

;; A directory search's result for the first unused entry: the directory sector it is in, or 0 for none.
NEWSEC = $0977

;; Where that entry is, in the sector read into <DBUF0>.
NEWDIR = $0978

;; The free granules a FAT gives up before it is written to the disk.
WFATVL = $097A

;; The record length random files open with.
DFFLEN = $097C

;; The track each drive's head is on, drives 0 to 3.
DR0TRK = $097E

;; Nonzero while a disk read or write waits for the controller's NMI, which then jumps to <DNMIVC>.
NMIFLG = $0982

;; Where the NMI goes when <NMIFLG> is set: the read or write's way out.
DNMIVC = $0983

;; Counts down to turning the drive motors off, at each field sync interrupt.
RDYTMR = $0985

;; What was last written to <DSKREG>.
DRGRAM = $0986

;; Nonzero when each sector written is read back to check it, which VERIFY ON sets.
DVERFL = $0987

;; The tries left on a sector read or write before it fails.
ATTCTR = $0988

;; Where the random file buffer space starts at power on: past the rest of Disk BASIC's RAM.
DFLBUF = $0989

; ----------------------------------------------------------------------------------------------------------------
; The disk controller's registers, in the cartridge's I/O at $FF40
; ----------------------------------------------------------------------------------------------------------------

;; The drive control latch, which can only be written.
;;
;; Bits 0 to 2 select drives 0 to 2, bit 3 turns the motors on, bit 4 sets write precompensation, bit 5 selects
;; double density, bit 6 selects drive 3, and bit 7 lets the controller's data request halt the CPU.
;; See: <DRGRAM>
DSKREG = $FF40

;; The WD1793 controller's command register when written, and its status register when read.
;;
;; Its track register follows at +1, its sector register at +2 and its data register at +3.
FDCREG = $FF48

; ----------------------------------------------------------------------------------------------------------------
; Tokens and error codes
; ----------------------------------------------------------------------------------------------------------------

; Command tokens: Disk BASIC's follow Extended BASIC's, from $CE.
TK_DIR = $CE                        ;; DIR
TK_DRIVE = $CF                      ;; DRIVE
TK_FIELD = $D0                      ;; FIELD
TK_FILES = $D1                      ;; FILES
TK_KILL = $D2                       ;; KILL
TK_LOAD = $D3                       ;; LOAD
TK_LSET = $D4                       ;; LSET
TK_MERGE = $D5                      ;; MERGE
TK_RENAME = $D6                     ;; RENAME
TK_RSET = $D7                       ;; RSET
TK_SAVE = $D8                       ;; SAVE
TK_WRITE = $D9                      ;; WRITE
TK_VERIFY = $DA                     ;; VERIFY
TK_UNLOAD = $DB                     ;; UNLOAD
TK_DSKINI = $DC                     ;; DSKINI
TK_BACKUP = $DD                     ;; BACKUP
TK_COPY = $DE                       ;; COPY
TK_DSKI = $DF                       ;; DSKI$
TK_DSKO = $E0                       ;; DSKO$
TK_DOS = $E1                        ;; DOS, in 1.1

; Function tokens: $FF, then Disk BASIC's functions follow Extended BASIC's, from $A2.
TK_CVN = $A2                        ;; CVN
TK_FREE = $A3                       ;; FREE
TK_LOC = $A4                        ;; LOC
TK_LOF = $A5                        ;; LOF
TK_MKN = $A6                        ;; MKN$
TK_AS = $A7                         ;; AS, which FIELD reads

; Error codes: Disk BASIC's follow Extended BASIC's, twice the error's place in its table, plus 54.
ERR_BR = 54                         ;; BR: bad record
ERR_DF = 56                         ;; DF: disk full
ERR_OB = 58                         ;; OB: out of buffer space
ERR_WP = 60                         ;; WP: write protected
ERR_FN = 62                         ;; FN: bad file name
ERR_FS = 64                         ;; FS: bad file structure
ERR_AE = 66                         ;; AE: file already exists
ERR_FO = 68                         ;; FO: field overflow
ERR_SE = 70                         ;; SE: set to a string that is not a field
ERR_VF = 72                         ;; VF: verify failed
ERR_ER = 74                         ;; ER: write or input past the end of a record
