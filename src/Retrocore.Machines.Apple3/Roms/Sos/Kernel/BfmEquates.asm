; SOS 1.3 kernel, block file manager: the names the BFM shares across its files, the layouts of its control blocks
; and directory headers, its zero-page parameter and work areas, and its work variables at $00-$3E.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

DLIMIT = $2F                        ;; the pathname delimiter, '/'
SEEDTYP = 1                         ;; storage type: a seedling file, one data block and no index
SAPTYP = 2                          ;; storage type: a sapling file, one index block over up to 256 data blocks
TRETYP = 3                          ;; storage type: a tree file, a master index over up to 128 index blocks
DIRTYP = $D                         ;; storage type: a subdirectory's entry in its parent directory
HEDTYP = $E                         ;; storage type: a subdirectory's header; the volume header is $F
RDCMD = $0                          ;; device request: read a block
WRTCMD = $1                         ;; device request: write a block
RPTCMD = $9                         ;; device request: repeat the unit's last read or write, at the block now given
STATCMD = $02                       ;; device request: status; bit 0 of the reply means write-protected
STATSUB = $0                        ;; the status code STATCMD asks for

;; Dispatch flag: the call needs the current date and time in <DATELO>..<TIMEHI> before it runs.
;; See: <DISPTCH>, <BFMGR>
PRETIME = $20

;; Dispatch flag: the call names an open file by reference number, which <FINDFCB> checks first.
;; See: <DISPTCH>, <BFMGR>
PREREF = $40

;; Dispatch flag: the call has a pathname, which <SETPATH> parses into <PATHBUF> first.
;; See: <DISPTCH>, <BFMGR>
PREPATH = $80

;; The X-byte page: the extension bytes of SOS's zero-page pointers, $0C00 below its zero page.
;;
;; An indirect access through a zero-page pointer at P uses the byte at SISTER+P+1 to pick the bank, so
;; SISTER+name+1 is the bank byte of the pointer called name. Zero means the bank that is switched in.
SISTER = $1400

;; VCB status bit: the volume's disk may have been switched while it had open files, so the BFM checks the
;; volume before the next call that uses it.
;; See: <VCBSTAT>, <BFMGR>
DSWITCH = $40

; File status bits, in an FCB's FCBSTAT byte.
DATALC = $1                         ;; the current data block is not allocated yet
IDXALC = $2                         ;; the current index block is not allocated yet
TOPALC = $4                         ;; the master index block is not allocated yet
STPMOD = $8                         ;; the storage type changed
USEMOD = $10                        ;; the count of blocks used changed
EOFMOD = $20                        ;; the end of file changed
DATMOD = $40                        ;; the data block in memory changed and must be written
IDXMOD = $80                        ;; the index block in memory changed and must be written
FCBMOD = $80                        ;; the FCB or its directory entry changed and must be flushed

; File access attribute bits, in a directory entry and an FCB's FCBATTR byte.
READEN = $1                         ;; the file may be read
WRITEN = $2                         ;; the file may be written
NLINEN = $10                        ;; newline mode is on: reads stop at the newline character
BKBITVAL = $20                      ;; the file changed since its last backup
RENAMEN = $40                       ;; the file may be renamed
DSTROYEN = $80                      ;; the file may be destroyed

; ---------------------------------------------------------------------------------------------------------------------
; Directory header offsets, from the start of the header entry (4 bytes into the directory's first block).
; ---------------------------------------------------------------------------------------------------------------------

HNLEN = $0                          ;; the storage type (high nibble) and the name's length (low nibble)
HPENAB = $10                        ;; the password-enable byte
HPASS = $11                         ;; the encoded password
HCRDT = $18                         ;; the creation date and time (four bytes)
HVER = $1C                          ;; the version of SOS that made the directory
HCMP = $1D                          ;; the oldest version of SOS that can read it; the BFM needs 0
HATTR = $1E                         ;; the directory's access attributes
HCENT = $21                         ;; the number of files in the directory (two bytes)
HRBLK = $23                         ;; a subdirectory's: the block holding its entry in the parent
HRENT = $25                         ;; a subdirectory's: that entry's number in the block
HRELN = $26                         ;; a subdirectory's: the parent's entry length
VBMAP = HRBLK                       ;; the volume header's: the first block of the volume bitmap
VTBLK = HRENT                       ;; the volume header's: the number of blocks on the volume

; ---------------------------------------------------------------------------------------------------------------------
; Volume control blocks: eight 32-byte entries at VCB ($1100), one for each volume the BFM knows about.
; ---------------------------------------------------------------------------------------------------------------------

VCBSIZE = $20                       ;; the size of a VCB entry
VCBNML = 0                          ;; the volume name's length; 0 when the entry is free
VCBNAM = 1                          ;; the volume name (up to 15 characters)
VCBDEV = $10                        ;; the device number of the drive the volume is in
VCBSTAT = $11                       ;; the status: bit 7 set while files are open, DSWITCH when switched
VCBTBLK = $12                       ;; the number of blocks on the volume
VCBTFRE = $14                       ;; the number of free blocks; 0 until counted (see <TSFRBLK>)
VCBROOT = $16                       ;; the block of the root directory
VCBDMAP = $1A                       ;; the first block of the volume bitmap
VCBCMAP = $1C                       ;; the bitmap block with free space, counted from VCBDMAP
VCBOPNC = $1E                       ;; the number of open files
VCBSWAP = $1F                       ;; nonzero when the volume is swapped out ($80 plus the entry's number)

; ---------------------------------------------------------------------------------------------------------------------
; File control blocks: sixteen 32-byte entries in the two pages at FCBADDRH, one for each open file.
; ---------------------------------------------------------------------------------------------------------------------

FCBREFN = 0                         ;; the file's reference number; 0 when the entry is free
FCBDEVN = 1                         ;; the device number of the file's volume
FCBENTN = 6                         ;; the file's entry number in its directory block
FCBSTYP = 7                         ;; the storage type: seedling, sapling or tree
FCBSTAT = 8                         ;; the status bits (DATALC through IDXMOD)
FCBATTR = 9                         ;; the access attributes and newline enable
FCBNEWL = $A                        ;; the newline character
FCBBUFN = $B                        ;; the number of the file's I/O buffer
FCBFRST = $C                        ;; the file's key block
FCBIDXB = $E                        ;; the block of the index in memory; 0 when there is none
FCBDATB = $10                       ;; the block of the data in memory
FCBMARK = $12                       ;; the current position (three bytes)
FCBEOF = $15                        ;; the end of file (three bytes)
FCBUSE = $18                        ;; the number of blocks the file uses
FCBSWAP = $1A                       ;; the VCB's swap byte when the file was opened, to tell volumes apart
FCBLEVL = $1B                       ;; the file level the file was opened at
FCBDIRTY = $1C                      ;; nonzero when the FCB changed

; ---------------------------------------------------------------------------------------------------------------------
; Zero page: the call's parameters. The file manager copies the caller's parameter list here, so each name gives
; one call's view of the same bytes.
; ---------------------------------------------------------------------------------------------------------------------

PAR = $A0                           ;; the start of the call's parameters
COMMAND = PAR                       ;; the call number, which <BFMGR> dispatches on
C_DNAMP = PAR+1                     ;; VOLUME: the pointer to the device name
C_PATH = PAR+1                      ;; the pointer to the pathname
C_REFNUM = PAR+1                    ;; the reference number of an open file
C_ISNEWL = PAR+2                    ;; NEWLINE: the enable flag
C_OUTEOF = PAR+2                    ;; GET_EOF: the pointer for the result
C_BASE = PAR+2                      ;; SET_MARK: the base the position is relative to
C_MRKPTR = PAR+2                    ;; GET_MARK: the pointer for the result
C_OUTBUF = PAR+2                    ;; READ, WRITE: the pointer to the data
C_NWPATH = PAR+3                    ;; RENAME: the pointer to the new pathname
C_FILIST = PAR+3                    ;; GET_FILE_INFO, SET_FILE_INFO: the pointer to the information list
C_NEWL = PAR+3                      ;; NEWLINE: the newline character
C_OUTVOL = PAR+3                    ;; VOLUME: the pointer for the volume name
C_OUTREF = PAR+3                    ;; OPEN: the pointer for the reference number
C_XLIST = PAR+3                     ;; CREATE: the pointer to the option list
C_MAXPTH = PAR+3                    ;; GET_PREFIX: the size of the caller's buffer
C_MARK = PAR+3                      ;; SET_MARK: the position
C_NEWEOF = PAR+3                    ;; SET_EOF: the base for the new end of file
C_BYTES = PAR+4                     ;; READ, WRITE: the byte count
C_FILSTLN = PAR+5                   ;; GET_FILE_INFO, SET_FILE_INFO: the list's length
C_OUTBLK = PAR+5                    ;; VOLUME: the pointer for the block counts
C_OPLIST = PAR+5                    ;; OPEN: the pointer to the option list
C_XLEN = PAR+5                      ;; CREATE: the option list's length
C_FILID = PAR+6                     ;; CREATE: the file type
C_OUTCNT = PAR+6                    ;; READ: the pointer for the count of bytes read
C_OPLSTLN = PAR+7                   ;; OPEN: the option list's length
C_AUXID = PAR+7                     ;; CREATE: the auxiliary type (two bytes)
C_STOR = PAR+9                      ;; CREATE: the storage type
C_EOFLL = PAR+$A                    ;; CREATE: the size to allocate, low byte
C_EOFLH = PAR+$B                    ;; CREATE: the size's second byte
C_EOFHL = PAR+$C                    ;; CREATE: the size's third byte
DEBUPTR = PAR+$D                    ;; the pointer to the searched directory's own entry in its parent, in GBUF
C_EOFHH = PAR+$D                    ;; CREATE: the size's high byte, which must be 0

; ---------------------------------------------------------------------------------------------------------------------
; Zero page: the device manager's request block.
; ---------------------------------------------------------------------------------------------------------------------

DEVICE = $C0                        ;; the start of the request block
DHPCMD = DEVICE                     ;; the request (RDCMD, WRTCMD, STATCMD, or 4 for a device's number)
UNITNUM = DEVICE+1                  ;; the device number
DSTATREQ = DEVICE+2                 ;; a status request's code
DBUFPL = DEVICE+2                   ;; the buffer's address, low byte
DBUFPH = DBUFPL+1                   ;; the buffer's address, high byte
DSTATBFL = DEVICE+3                 ;; the pointer for a status reply, low byte
DSTATBFH = DSTATBFL+1               ;; the pointer for a status reply, high byte
RQCNTL = DEVICE+4                   ;; the byte count, low byte
RQCNTH = RQCNTL+1                   ;; the byte count, high byte
BLOKNML = DEVICE+6                  ;; the block number, low byte
BLOKNMH = BLOKNML+1                 ;; the block number, high byte
BRDPTR = DEVICE+8                   ;; the pointer for the count of bytes read (two bytes)
DVNAMP = DEVICE+1                   ;; a device-number request's pointer to the device name
DVDNUM = DEVICE+3                   ;; a device-number request's pointer for the number
SISBPH = SISTER+DBUFPH              ;; the bank byte of the buffer pointer
SISDSTAT = SISTER+DSTATBFH          ;; the bank byte of the status reply pointer
SSBRDPH = SISTER+BRDPTR+1           ;; the bank byte of the bytes-read pointer

; ---------------------------------------------------------------------------------------------------------------------
; Zero page: the BFM's pointers. <BFMGR> clears their bank bytes at the start of each call.
; ---------------------------------------------------------------------------------------------------------------------

ZTEMPS = $B0                        ;; the start of the pointers
PATHNML = ZTEMPS                    ;; the pointer to the current name in the parsed pathname, low byte
PATHNMH = PATHNML+1                 ;; the pointer's high byte
USRBUF = ZTEMPS                     ;; the pointer to the caller's data, in READ and WRITE
TPATH = ZTEMPS+2                    ;; the pointer into the caller's pathname while it is parsed
WRKPATH = ZTEMPS+4                  ;; the pointer to the name being built in PATHBUF
TINDX = ZTEMPS+2                    ;; the pointer to the index block buffer
DRBUFPL = ZTEMPS+4                  ;; the pointer to a directory entry in GBUF, low byte
DRBUFPH = DRBUFPL+1                 ;; the pointer's high byte
VCBPTR = ZTEMPS+6                   ;; the pointer to the current VCB entry
BMADR = ZTEMPS+8                    ;; the pointer to the bitmap in memory
FCBPTR = ZTEMPS+$A                  ;; the pointer to the current FCB entry
DATPTR = ZTEMPS+$C                  ;; the pointer to the data block buffer
POSPTR = ZTEMPS+$E                  ;; the pointer to the current position in the data buffer
MAXTEMPS = $F                       ;; the offset of the last pointer byte, for clearing their bank bytes
SISTEMPS = SISTER+ZTEMPS            ;; the bank bytes of the pointers
SSTIDXH = SISTER+TINDX+1            ;; the bank byte of TINDX
SISPATH = SISTER+C_PATH+1           ;; the bank byte of the caller's pathname pointer
SSNWPATH = SISTER+C_NWPATH+1        ;; the bank byte of RENAME's new pathname pointer
SISUSRBF = SISTER+USRBUF+1          ;; the bank byte of USRBUF
SISOUTBF = SISTER+C_OUTBUF+1        ;; the bank byte of the caller's data pointer
SISTPATH = SISTER+TPATH+1           ;; the bank byte of TPATH
SISBMADR = SISTER+BMADR+1           ;; the bank byte of BMADR
SISFCBP = SISTER+FCBPTR+1           ;; the bank byte of FCBPTR
SISDATP = SISTER+DATPTR+1           ;; the bank byte of DATPTR
SISPOSP = SISTER+POSPTR+1           ;; the bank byte of POSPTR

; ---------------------------------------------------------------------------------------------------------------------
; Buffers
; ---------------------------------------------------------------------------------------------------------------------

;; The pathname buffer, one page: the parsed pathname from its start, and the prefix ending at its last byte.
;;
;; A parsed pathname is a list of names, each a length byte and its characters, ended by a zero length. The
;; prefix is kept the same way but without the ending zero, finishing at $10FF. Names are found by adding to
;; the low byte of <PATHNML> only, so a partial pathname reads on from the prefix's end around to the buffer's
;; start, where its own names were put.
;; See: <SYNPATH>, <SETPREFX>, <PFIXPTR>
PATHBUF = $1000

;; The volume control blocks: eight entries of VCBSIZE bytes (VCBNML through VCBSWAP).
;; See: <VCBSIZE>, <VCBPTR>
VCB = $1100

;; The general buffer, $1200-$13FF: one 512-byte block, used for directory blocks and bitmaps.
;; See: <RDGBUF>, <WRTGBUF>
GBUF = $1200

; Initialization values, for the BFM's setup code.
BFMFCB1 = $1C                       ;; the page of the first eight FCBs
BFMFCB2 = $1D                       ;; the page of the other eight
BMAPAGE = >($B800)                  ;; the page of bitmap buffer A
BMBPAGE = >($BA00)                  ;; the page of bitmap buffer B
FCBZPP = FCBPTR                     ;; the FCB pointer, for the setup code

; ---------------------------------------------------------------------------------------------------------------------
; The BFM's work variables, at $00-$3E.
; ---------------------------------------------------------------------------------------------------------------------

DATBLKL = $0000                     ;; CREATE: the number of data blocks to allocate, low byte
DATBLKH = $0001                     ;; the number's high byte
IDXADRL = $0002                     ;; the block of the index block being written, low byte
IDXADRH = $0003                     ;; that block's high byte
REQL = $0004                        ;; the number of blocks wanted, low byte
REQH = $0005                        ;; the number's high byte
INDXBLK = $0006                     ;; CREATE: the number of index blocks still to allocate
LEVELS = $0007                      ;; CREATE: the storage type, which is the number of index levels plus one
TOTENT = $0008                      ;; the number of used entries seen in the current directory block
ENTCNTL = $0009                     ;; the number of files in the directory not seen yet, low byte
ENTCNTH = $000A                     ;; the number's high byte
CNTENT = $000B                      ;; the entries left to look at in the current directory block
NOFREE = $000C                      ;; nonzero once a free directory entry is found; also a free-block count's
                                    ; first bitmap with space ($FF until found)
BMCNT = $000D                       ;; the bitmap blocks left to count
SAPTR = $000E                       ;; the index into the index block being filled
TREPTR = $000F                      ;; the index into the master index block being filled
TLINK = $0010                       ;; a directory block number: the block being written, or a saved count
FLINK = $0012                       ;; the next directory block's number
PATHCNT = $0014                     ;; the characters of the caller's pathname still to parse
PFIXPTR = $0015                     ;; where the prefix starts in PATHBUF: low byte, 0 for none, then high byte
BMPTR = $0017                       ;; the byte's index in the bitmap block
BASVAL = $0018                      ;; the bitmap search: the base of the block numbers, 2048 for each page searched
HALF = $0019                        ;; the bitmap search: which page of the bitmap block holds the bit
BMTABSZ = $6                        ;; the size of each bitmap buffer's description
BMTAB = $001A                       ;; the bitmap buffer in use: 0 for A, BMTABSZ for B
BMBUFBNK = $001B                    ;; the bank byte for the bitmap buffers
BMASTAT = $001C                     ;; bitmap buffer A: its status; bit 7 set when changed
BMADEV = $001D                      ;; bitmap buffer A: the device it belongs to
BMAMADR = $001E                     ;; bitmap buffer A: its page in memory
BMADADR = $001F                     ;; bitmap buffer A: the bitmap's block on disk (two bytes)
BMACMAP = $0021                     ;; bitmap buffer A: which of the volume's bitmap blocks it holds
BMBSTAT = $0022                     ;; bitmap buffer B: its status
BMBDEV = $0023                      ;; bitmap buffer B: its device
BMBMADR = $0024                     ;; bitmap buffer B: its page, then its block and bitmap number
FCBADDRH = $0028                    ;; the page of the FCBs
FCBANKNM = $0029                    ;; the bank byte of the FCBs
TPOSLL = $002A                      ;; the position wanted, low byte
TPOSLH = $002B                      ;; the position's middle byte
TPOSHI = $002C                      ;; the position's high byte
RWREQL = $002D                      ;; the bytes READ or WRITE still has to move, low byte
RWREQH = $002E                      ;; the count's high byte
BULKCNT = $002F                     ;; a count of whole pages to move
NLCHAR = $0030                      ;; the newline character of the file being read
NPATHDEV = $0031                    ;; RENAME: the new pathname's device and directory header block (3 bytes)
IOACCESS = $0034                    ;; nonzero once the call has reached the device manager
DEVNUM = $0035                      ;; the device number of the drive being used
TOTDEVS = $0036                     ;; the number of block devices to look through
CMDTEMP = $0037                     ;; the call's dispatch flags, shifted out one at a time by <BFMGR>
DATELO = $0038                      ;; the date, low byte; must be here for the date call
DATEHI = $0039                      ;; the date, high byte
TIMELO = $003A                      ;; the time, low byte
TIMEHI = $003B                      ;; the time, high byte
DUPLFLAG = $003C                    ;; nonzero when a volume could not be logged in for an open one of its name
ZPGTEMP = $003D                     ;; a byte for brief use
VCBENTRY = $003E                    ;; the offset of a VCB entry kept aside (see <TSTDUPVOL>)
    .include "Path.asm"
