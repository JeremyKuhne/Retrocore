; B3INVOK: the equates for BASIC's SOS calls: the call numbers, the SOS errors BASIC looks for, the file types, the
; layout of a file control block, and the descriptors of the items in a data file.
;
; How BASIC lays out the memory SOS gives it, from the bottom up (the pointers are in ZPG.EQUS):
;
; - the program, from TXTTAB;
; - the arrays, from ARYTAB;
; - the simple variables, from VARTAB (also called SMVARS) up to STREND;
; - free memory;
; - the strings, which grow down to FRETOP from MEMSIZ (HIMEM). FRESPC points at the string made last.
;
; INVOKE's modules and their procedure table have a segment of their own, from INVTAB to PROCTAB. Apple's notes say
; the areas and the pointers within them are kept relative to the areas' starts, so the areas can move.
;
; SOS's stack is page $17 and BASIC's is page $1B, each from $FF down.
;
; The entries in the variable areas, with Apple's notes calling the pointers in them relative:
;
; - A simple variable: its entry's length (one byte), its name, a type byte, then the value: 4 bytes for a real, 2
;   for an integer, 8 for a long integer.
; - A string variable: the same, with the value a length byte and a two-byte pointer to the string.
; - An array: its length, name and type, the count of dimensions, two bytes for each dimension's size, then the
;   values, one after another.
; - A string, in string space: its characters, then a type byte that says whether its variable is a simple variable
;   or an array element, then a two-byte pointer back to the variable's descriptor.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; SOS calls
; ---------------------------------------------------------------------------------------------------------------------

SCRT = $C0                                  ;; CREATE
SDST = $C1                                  ;; DESTROY
SRNM = $C2                                  ;; RENAME
SSFI = $C3                                  ;; SET_FILE_INFO
SGFI = $C4                                  ;; GET_FILE_INFO
SVLM = $C5                                  ;; VOLUME
SETPREF = $C6                               ;; SET_PREFIX
GETPREF = $C7                               ;; GET_PREFIX
SOPN = $C8                                  ;; OPEN
SNWL = $C9                                  ;; NEWLINE
SRED = $CA                                  ;; READ
SWRT = $CB                                  ;; WRITE
SCLS = $CC                                  ;; CLOSE
SFLS = $CD                                  ;; FLUSH
SSTM = $CE                                  ;; SET_MARK
SGTM = $CF                                  ;; GET_MARK
SSTE = $D0                                  ;; SET_EOF
SGTE = $D1                                  ;; GET_EOF
SSLVL = $D2                                 ;; SET_LEVEL
SGLVL = $D3                                 ;; GET_LEVEL
SDSTAT = $82                                ;; D_STATUS
SDCNT = $83                                 ;; D_CONTROL
SDGDN = $84                                 ;; GET_DEV_NUM
MREQ = $40                                  ;; REQUEST_SEG
MCHG = $42                                  ;; CHANGE_SEG
MFND = $41                                  ;; FIND_SEG
MRLS = $45                                  ;; RELEASE_SEG
GETCLOK = $63                               ;; GET_TIME
CLDSTRT = $65                               ;; COLD_START, which BYE makes

; ---------------------------------------------------------------------------------------------------------------------
; SOS errors
; ---------------------------------------------------------------------------------------------------------------------

SEMEM = $54                                 ;; SOS's error: out of memory
SEBDP = $40                                 ;; SOS's error: a bad pathname
SEFNF = $46                                 ;; SOS's error: file not found
SEEOF = $4C                                 ;; SOS's error: the end of the file
SEFNO = $43                                 ;; SOS's error: a bad reference number, which BASIC calls file not open
SENBK = $58                                 ;; SOS's error: not a block device
SEDFU = $48                                 ;; SOS's error: the disk is full

; ---------------------------------------------------------------------------------------------------------------------
; File types
;
; SOS's file types: 0 unknown, 1 bad blocks, 2 Pascal code, 3 Pascal text, 4 text, 5 Pascal data, 6 binary, 7 font,
; 8 picture, 9 Business BASIC program, 10 Business BASIC data, 11 word processor text, 12 SOS system, 13 and 14
; reserved, 15 directory, 16 RPS data, 17 RPS index, 18 AppleFile discard, 19 AppleFile model, 20 AppleFile report
; format, 21 screen library. Types $E0-$FF are kept for ProDOS.
; ---------------------------------------------------------------------------------------------------------------------

PRGTY = $09                                 ;; the file type of a BASIC program
TXTTYP = $04                                ;; the file type of a text file
BINTIP = 10                                 ;; the file type of a BASIC data file
UNKNTY = $0                                 ;; the file type of a file of no known type
PCODTYP = 2                                 ;; the file type of a Pascal code file, as INVOKE loads

; ---------------------------------------------------------------------------------------------------------------------
; File control blocks
;
; BASIC keeps a control block of FCBLEN bytes in FCB for each of its files, 1-10; CATALOG uses an eleventh, CATFCB.
; These are the offsets of its fields. A file's place in the file is its record number times its record length.
; ---------------------------------------------------------------------------------------------------------------------

XRFNM = 0                                   ;; the file's SOS reference number
XUID = 1                                    ;; the file's type in bits 0-3; bit 4 set to read, bit 5 to write

XBUFPT = 2                                  ;; the file's buffer: its X-byte, then its address's high byte
XBUFOFS = 4                                 ;; how far into the buffer the next item is
; It starts at 0 for each record: SOS's mark does the rest.

XRNUM = 6                                   ;; the record number
XRECL = 8                                   ;; the record length, 512 unless the file says otherwise

XFLGS = 10                                  ;; the file's state: bit 7 set for a buffer changed and not yet written
; Bit 6 is set until the open is finished and BASIC knows whether the file holds text or data. While CATALOG reads
; a directory, which looks like a text file, bits 0-2 count the stage CATALOG has reached.

XSEGNM = 11                                 ;; the number of the buffer's memory segment
XBLKS = 12                                  ;; for a volume's directory, the volume's count of blocks
FCBLEN = 14                                 ;; the length of a file control block

; ---------------------------------------------------------------------------------------------------------------------
; Data file descriptors
;
; In a data file each item has a descriptor byte before it, the low digit of which, for numbers, is the size.
; ---------------------------------------------------------------------------------------------------------------------

DDINT = $12                                 ;; an integer: two bytes follow
DDFP = $14                                  ;; a real: four bytes follow
DDLNT = $18                                 ;; a long integer: eight bytes follow
DDSTR = $21                                 ;; a string: its length follows, then the characters
DDMXSTR = $20                               ;; a string of 255 characters, which follow with no length
DDEOR = $00                                 ;; the end of a record, zero as SOS expects
