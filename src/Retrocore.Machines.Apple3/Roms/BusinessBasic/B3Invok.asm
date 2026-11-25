; retrocore: style=strict
;; B3Invok: the SOS calls, SOS errors, file types and file layouts BASIC uses
;;
;; The numbers of the SOS calls BASIC makes, the SOS errors it looks for, the file types it knows, the layout of the
;; control block it keeps for each open file, and the descriptor bytes that mark the items of a data file.
;;
;; How BASIC lays out the memory SOS gives it, from the bottom up (the pointers are in ZpgEqus.asm):
;;
;; - the program, from <ProgramStart>;
;; - the arrays, from <ArraysStart>;
;; - the simple variables, from <VariablesStart> up to <VariablesEnd>;
;; - free memory;
;; - the strings, which grow down to <StringsBottom> from <MemoryTop> (`HIMEM`). <NewString> points at the string
;;   made last.
;;
;; `INVOKE`'s modules and their procedure table have a segment of their own, from <ModulesStart> to <ModulesEnd>.
;; Apple's notes say the areas and the pointers within them are kept relative to the areas' starts, so the areas can
;; move.
;;
;; SOS's stack is page $17 and BASIC's is page $1B, each from $FF down.
;;
;; The entries in the variable areas, with Apple's notes calling the pointers in them relative:
;;
;; - A simple variable: its entry's length (one byte), its name, a type byte, then the value: 4 bytes for a real, 2
;;   for an integer, 8 for a long integer.
;; - A string variable: the same, with the value a length byte and a two-byte pointer to the string.
;; - An array: its length, name and type, the count of dimensions, two bytes for each dimension's size, then the
;;   values, one after another.
;; - A string, in string space: its characters, then a type byte that says whether its variable is a simple variable
;;   or an array element, then a two-byte pointer back to the variable's descriptor.
;;
;; The names say what each value is; Apple's names from its Business BASIC 1.3 listing are in each one's `Also:`.

; ---------------------------------------------------------------------------------------------------------------------
; SOS calls
;
; A SOS call is a BRK followed by the call's number and the address of its parameter list. SOS's own names for the
; calls are in each one's summary.
; ---------------------------------------------------------------------------------------------------------------------

;; SOS's `CREATE`: makes a file or directory.
;; Also: SCRT (BB13)
SOS_CREATE = $C0

;; SOS's `DESTROY`: deletes a file.
;; Also: SDST (BB13)
SOS_DESTROY = $C1

;; SOS's `RENAME`: renames a file.
;; Also: SRNM (BB13)
SOS_RENAME = $C2

;; SOS's `SET_FILE_INFO`: sets a file's type, access and dates.
;; Also: SSFI (BB13)
SOS_SET_FILE_INFO = $C3

;; SOS's `GET_FILE_INFO`: reads a file's type, access, size and dates.
;; Also: SGFI (BB13)
SOS_GET_FILE_INFO = $C4

;; SOS's `VOLUME`: reads the name and size of the volume in a device.
;; Also: SVLM (BB13)
SOS_VOLUME = $C5

;; SOS's `SET_PREFIX`: sets the prefix that partial pathnames start from.
;; Also: SETPREF (BB13)
SOS_SET_PREFIX = $C6

;; SOS's `GET_PREFIX`: reads the prefix.
;; Also: GETPREF (BB13)
SOS_GET_PREFIX = $C7

;; SOS's `OPEN`: opens a file and gives its reference number.
;; Also: SOPN (BB13)
SOS_OPEN = $C8

;; SOS's `NEWLINE`: makes a `READ` stop at a character, such as a carriage return.
;; Also: SNWL (BB13)
SOS_NEWLINE = $C9

;; SOS's `READ`.
;; Also: SRED (BB13)
SOS_READ = $CA

;; SOS's `WRITE`.
;; Also: SWRT (BB13)
SOS_WRITE = $CB

;; SOS's `CLOSE`.
;; Also: SCLS (BB13)
SOS_CLOSE = $CC

;; SOS's `FLUSH`: writes a file's buffer out.
;; Also: SFLS (BB13)
SOS_FLUSH = $CD

;; SOS's `SET_MARK`: moves to a place in a file.
;; Also: SSTM (BB13)
SOS_SET_MARK = $CE

;; SOS's `GET_MARK`: reads the place in a file.
;; Also: SGTM (BB13)
SOS_GET_MARK = $CF

;; SOS's `SET_EOF`: sets a file's length.
;; Also: SSTE (BB13)
SOS_SET_EOF = $D0

;; SOS's `GET_EOF`: reads a file's length.
;; Also: SGTE (BB13)
SOS_GET_EOF = $D1

;; SOS's `SET_LEVEL`: sets the file level, which `CLOSE` and `FLUSH` of reference number 0 go by.
;; Also: SSLVL (BB13)
SOS_SET_LEVEL = $D2

;; SOS's `GET_LEVEL`: reads the file level.
;; Also: SGLVL (BB13)
SOS_GET_LEVEL = $D3

;; SOS's `D_STATUS`: reads a device's status.
;; Also: SDSTAT (BB13)
SOS_DEVICE_STATUS = $82

;; SOS's `D_CONTROL`: sends a device a control request.
;; Also: SDCNT (BB13)
SOS_DEVICE_CONTROL = $83

;; SOS's `GET_DEV_NUM`: gives a device's number from its name.
;; Also: SDGDN (BB13)
SOS_GET_DEVICE_NUMBER = $84

;; SOS's `REQUEST_SEG`: takes a segment of memory.
;; Also: MREQ (BB13)
SOS_REQUEST_SEGMENT = $40

;; SOS's `FIND_SEG`: finds a free segment of memory of a size, and takes it.
;; Also: MFND (BB13)
SOS_FIND_SEGMENT = $41

;; SOS's `CHANGE_SEG`: makes a segment longer or shorter.
;; Also: MCHG (BB13)
SOS_CHANGE_SEGMENT = $42

;; SOS's `RELEASE_SEG`: gives a segment back.
;; Also: MRLS (BB13)
SOS_RELEASE_SEGMENT = $45

;; SOS's `GET_TIME`: reads the clock.
;; Also: GETCLOK (BB13)
SOS_GET_TIME = $63

;; SOS's `TERMINATE`, which `BYE` makes: SOS ends the interpreter and asks for the system to be restarted.
;;
;; Apple's listing calls it `COLD.START`.
;; Also: CLDSTRT (BB13)
SOS_TERMINATE = $65

; ---------------------------------------------------------------------------------------------------------------------
; SOS errors
;
; The codes SOS returns in A, with the negative and zero flags set from them, for a call that failed. <SosErrors> turns
; each into one of BASIC's errors.
; ---------------------------------------------------------------------------------------------------------------------

;; SOS's error: no such device.
SOS_ERROR_NO_DEVICE = $10

;; SOS's error: a resource the call needs is not available.
SOS_ERROR_NO_RESOURCE = $25

;; SOS's error: an I/O error on the device.
SOS_ERROR_IO = $27

;; SOS's error: no drive is connected.
SOS_ERROR_NO_DRIVE = $28

;; SOS's error: the disk is write-protected.
SOS_ERROR_WRITE_PROTECTED = $2B

;; SOS's error: the disk was switched while a file on it was open.
SOS_ERROR_DISK_SWITCHED = $2E

;; SOS's error: a bad pathname.
;; Also: SEBDP (BB13)
SOS_ERROR_BAD_PATH = $40

;; SOS's error: a bad reference number, which BASIC calls file not open.
;; Also: SEFNO (BB13)
SOS_ERROR_BAD_REFERENCE_NUMBER = $43

;; SOS's error: a directory in the path was not found.
SOS_ERROR_PATH_NOT_FOUND = $44

;; SOS's error: the volume was not found.
SOS_ERROR_VOLUME_NOT_FOUND = $45

;; SOS's error: file not found.
;; Also: SEFNF (BB13)
SOS_ERROR_FILE_NOT_FOUND = $46

;; SOS's error: a file of that name is already there.
SOS_ERROR_DUPLICATE_FILE = $47

;; SOS's error: the disk is full.
;; Also: SEDFU (BB13)
SOS_ERROR_DISK_FULL = $48

;; SOS's error: the volume's directory is full.
SOS_ERROR_DIRECTORY_FULL = $49

;; SOS's error: the end of the file.
;; Also: SEEOF (BB13)
SOS_ERROR_END_OF_FILE = $4C

;; SOS's error: a position past the file's end.
SOS_ERROR_POSITION_OUT_OF_RANGE = $4D

;; SOS's error: the file's access doesn't allow the call, such as a write to a locked file.
SOS_ERROR_ACCESS_NOT_ALLOWED = $4E

;; SOS's error: the file is open already.
SOS_ERROR_FILE_BUSY = $50

;; SOS's error: the directory is damaged.
SOS_ERROR_DIRECTORY_ERROR = $51

;; SOS's error: not a SOS volume, such as an Apple II Pascal disk.
SOS_ERROR_NOT_SOS_VOLUME = $52

;; SOS's error: out of memory.
;; Also: SEMEM (BB13)
SOS_ERROR_OUT_OF_MEMORY = $54

;; SOS's error: a volume of that name is in another drive already.
SOS_ERROR_DUPLICATE_VOLUME = $57

;; SOS's error: not a block device.
;; Also: SENBK (BB13)
SOS_ERROR_NOT_BLOCK_DEVICE = $58

; ---------------------------------------------------------------------------------------------------------------------
; File types
;
; SOS's file types: 0 unknown, 1 bad blocks, 2 Pascal code, 3 Pascal text, 4 text, 5 Pascal data, 6 binary, 7 font,
; 8 picture, 9 Business BASIC program, 10 Business BASIC data, 11 word processor text, 12 SOS system, 13 and 14
; reserved, 15 directory, 16 RPS data, 17 RPS index, 18 AppleFile discard, 19 AppleFile model, 20 AppleFile report
; format, 21 screen library. Types $E0-$FF are kept for ProDOS.
; ---------------------------------------------------------------------------------------------------------------------

;; The file type of a BASIC program.
;; Also: PRGTY (BB13)
FILE_TYPE_BASIC_PROGRAM = $09

;; The file type of a text file.
;; Also: TXTTYP (BB13)
FILE_TYPE_TEXT = $04

;; The file type of a BASIC data file.
;; Also: BINTIP (BB13)
FILE_TYPE_BASIC_DATA = 10

;; The file type of a file of no known type.
;; Also: UNKNTY (BB13)
FILE_TYPE_UNKNOWN = $0

;; The file type of a Pascal code file, as `INVOKE` loads.
;; Also: PCODTYP (BB13)
FILE_TYPE_PASCAL_CODE = 2

; ---------------------------------------------------------------------------------------------------------------------
; File control blocks
; ---------------------------------------------------------------------------------------------------------------------

;; How many files BASIC can have open, numbered 1 to 10.
FILE_COUNT = 10

;; The control block BASIC keeps for each of its files in <FileControlBlocks>; `CATALOG` uses an eleventh,
;; <CatalogControlBlock>.
;;
;; A file's place in the file is its record number times its record length.
.struct FileControlBlock
    ;; The file's SOS reference number, 0 while the file is not open.
    ;; Also: XRFNM (BB13)
    REFERENCE_NUMBER .byte
    ;; The file's type, a FILE_TYPE_ code such as <FILE_TYPE_TEXT>, in bits 0-3; bit 4 set to read it, bit 5 to
    ;; write it.
    ;; Also: XUID (BB13)
    TYPE_AND_ACCESS .byte
    ;; The file's buffer: its X-byte, then its address's high byte.
    ;; Also: XBUFPT (BB13)
    BUFFER .res 2
    ;; How far into the buffer the next item is. It starts at 0 for each record: SOS's mark does the rest.
    ;; Also: XBUFOFS (BB13)
    BUFFER_OFFSET .word
    ;; The record number.
    ;; Also: XRNUM (BB13)
    RECORD_NUMBER .word
    ;; The record length, 512 unless the file says otherwise; for a volume's directory, `CATALOG` keeps the volume's
    ;; count of blocks here.
    ;; Also: XRECL (BB13)
    RECORD_LENGTH .word
    ;; The file's state: bit 7 set for a buffer changed and not yet written.
    ;;
    ;; Bit 6 is set until the open is finished and BASIC knows whether the file holds text or data. While `CATALOG`
    ;; reads a directory, which looks like a text file, bits 0-2 count the stage `CATALOG` has reached.
    ;; Also: XFLGS (BB13)
    FLAGS .byte
    ;; The number of the buffer's memory segment, 0 for none, as for a directory `CATALOG` reads.
    ;; Also: XSEGNM (BB13)
    SEGMENT .byte
    ;; For a volume's directory, the count of the volume's blocks in use, which `CATALOG`'s summary line gives.
    ;; Also: XBLKS (BB13)
    BLOCKS_USED .word
.endstruct

;; The length of a file control block.
;; Also: FCBLEN (BB13)
FILE_CONTROL_BLOCK_SIZE = .sizeof(FileControlBlock)
.assert FILE_CONTROL_BLOCK_SIZE = 14, "A file control block is 14 bytes, as Apple's FCBLEN."

; ---------------------------------------------------------------------------------------------------------------------
; Data file descriptors
;
; In a data file each item has a descriptor byte before it, the low digit of which, for numbers, is the size.
; ---------------------------------------------------------------------------------------------------------------------

;; An integer: two bytes follow.
;; Also: DDINT (BB13)
DATA_ITEM_INTEGER = $12

;; A real: four bytes follow.
;; Also: DDFP (BB13)
DATA_ITEM_REAL = $14

;; A long integer: eight bytes follow.
;; Also: DDLNT (BB13)
DATA_ITEM_LONG_INTEGER = $18

;; A string: its length follows, then the characters.
;; Also: DDSTR (BB13)
DATA_ITEM_STRING = $21

;; A string of 255 characters, which follow with no length.
;; Also: DDMXSTR (BB13)
DATA_ITEM_LONGEST_STRING = $20

;; The end of a record, zero as SOS expects.
;; Also: DDEOR (BB13)
DATA_ITEM_END_OF_RECORD = $00
