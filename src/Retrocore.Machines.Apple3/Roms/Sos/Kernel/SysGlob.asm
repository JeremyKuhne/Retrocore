; SYSGLOB: SOS's global page, $1900-$19FF, with the 4-byte headers the loader reads before and after it
; ($18FC-$1A03). The first $80 bytes are at fixed addresses that drivers use: system values and the jump table
; through which drivers call SOS. The rest is SOS's own data, and the error numbers SOS uses are defined at the end.

; The global page's header in SOS.KERNEL: its address and length, for the loader's ADVANCE.
    .word SYSGLOB
    .word $0100

;; The start of the global page, $1900.
SYSGLOB:
;; The memory size in 16K units: 8 for 128K. The loader sets it from the system bank's number.
MEMSIZE:
    .byte $08

;; The system bank: the highest bank, which holds the interpreter. The loader sets it.
SYSBANK:
    .byte $02

;; The console's suspend and flush flag for output.
SUSPFLSH:
    .byte $00

;; Bit 7 set while an NMI is pending; NMIDSBL waits for it to clear before it disables NMI.
;;
;; The two bytes after it, at $1904, hold the default NMI handler's address, <NMIEXIT>.
NMIFLAG:
    .byte $00
    .word NMIEXIT

;; The screen mode: bit 7 set while video is on. The loader turns it off while the character set loads.
SCRNMODE:
    .byte $80

;; The graphics area's size, set by a graphics driver.
GRSIZE:
    .byte $00
    .res SYSGLOB+$10-* , $00        ; $1908-$190F, for the mouse driver (see E1908)

;; The SOS jump table, at $1910, through which drivers call SOS. Each entry is a 3-byte JMP:
;;
;; - $1910 USERNMI: the keyboard NMI vector; <KYBDNMI> jumps here, and it goes to <NMIEXIT> until changed
;; - $1913 <ALLOCSIR>: claim system interrupt resources
;; - $1916 <DEALCSIR>: release system interrupt resources
;; - $1919 <NMIDSBL>: disable NMI
;; - $191C <NMIENBL>: enable NMI
;; - $191F <QUEEVENT>: queue an event
;; - $1922 <SELC800>: select a slot's expansion ROM
;; - $1925 <SYSDEATH>: stop SOS with a fatal error
;; - $1928 <SYSERR>: return an error from a SOS call
;; - $192B <REQBUF>: request a buffer
;; - $192E <GETBUFADR>: get a buffer's address
;; - $1931 <RELBUF>: release a buffer
;; - $1934 <CLRBMASK>: let the next SET_FILE_INFO clear a file's backup bit
USERNMI:
    jmp NMIEXIT
    jmp ALLOCSIR                    ; $1913
    jmp DEALCSIR                    ; $1916
    jmp NMIDSBL                     ; $1919
    jmp NMIENBL                     ; $191C
    jmp QUEEVENT                    ; $191F
    jmp SELC800                     ; $1922
    jmp SYSDEATH                    ; $1925
    jmp SYSERR                      ; $1928
    jmp REQBUF                      ; $192B
    jmp GETBUFADR                   ; $192E
    jmp RELBUF                      ; $1931
    jmp CLRBMASK                    ; $1934
    .res SYSGLOB+$80-* , $00

; ---------------------------------------------------------------------------------------------------------------------
; SOS's own data, from $1980. Only SOS uses it.
; ---------------------------------------------------------------------------------------------------------------------

;; The error code of the SOS call in progress, which <SYSERR> sets.
SERR:
    .byte $00

;; Called for the debug system call; as it stands, it returns past the call to its caller's caller.
;;
;; Its four bytes are there to be patched with a JMP to a debugger.
;; See: <SCMGR>
DBUGBRK:
    nop
    pla
    pla
    rts

;; Called by the NMI handler for a keyboard NMI: jumps to <USERNMI>.
;;
;; The JMP to <NMIDBUG> after it enters the boot ROM's monitor; nothing jumps there unless this is patched.
;; See: <NMI_RCVR>
KYBDNMI:
    jmp USERNMI
    jmp NMIDBUG

;; The stack pointer NMIDBUG saves while the monitor runs, for NMICONT to restore.
;;
;; The JMP after it, at $198C, continues SOS after the monitor (<NMICONT>).
NMISPSV:
    .byte 0
    jmp NMICONT

;; Returns at once: the default NMI handler and keyboard NMI vector.
;; Keeps: A, X, Y
NMIEXIT:
    rts

;; SOS's version, which the welcome screen shows; the copyright follows it.
SOSVER:
    .byte "SOS 1.3   01-NOV-82"
SOSVERL = * - SOSVER                ;; the version's length
    .byte "(C) 1980, 1982 BY APPLE COMPUTER INC."
E1908 = $1908                       ;; the mouse driver's flag, which the disk driver sets while it reads or writes
SZPAGE = $1800                      ;; SOS's zero page
SXPAGE = $1400                      ;; SOS's extend page: the X bytes of pointers in SZPAGE
SSPAGE = $0100                      ;; SOS's stack page
CZPAGE = $1A00                      ;; the caller's (interpreter's) zero page
CXPAGE = $1600                      ;; the caller's extend page
CSPAGE = $1B00                      ;; the caller's stack page

;; The event priority of the code SOS interrupted or was called from.
CEVPRI:
    .byte $00

;; ALLOCSIR's and DEALCSIR's work byte.
SIRTEMP:
    .byte $00

;; ALLOCSIR's and DEALCSIR's count of the resources in the request.
SIRARGSIZ:
    .byte $00

;; A count of IRQs no device claimed.
IRQCNTR:
    .word $0000

;; A count used while waiting to lock out NMI.
NMICNTR:
    .word $0000

;; QUEEVENT's work byte.
QEVTEMP:
    .byte $00

;; QUEEVENT's pointer to the queue entry it is at.
QEV_THIS:
    .byte $00

;; QUEEVENT's pointer to the entry before it.
QEV_LAST:
    .byte $00

;; The mask the block file manager uses when it sets a file's backup bit: <BACKBIT>, unless <CLRBMASK> changed it.
BACKMASK:
    .byte BACKBIT

;; Sets the backup bit mask, so the next SET_FILE_INFO can clear a file's backup bit.
;;
;; A program calls it through the jump table ($1934) and then makes the SET_FILE_INFO call, with no other SOS call
;; between: any SOS call sets the mask back.
;; In:    A = the mask: 0 to clear the bit
;; Out:   BACKMASK = A AND BACKBIT
;; Keeps: X, Y
CLRBMASK:
    and #BACKBIT
    sta BACKMASK
    rts
    .res SYSGLOB+$F6-* , $00

;; The registers SYSDEATH saves for its report: bank, zero page, environment, Y, X, A, status, the program counter
;; (2 bytes) and the stack pointer.
;; See: <SYSDEATH>
SDEATH_REGS:
    .byte $00
    .byte $00
    .byte $00
    .byte $00
    .byte $00
    .byte $00
    .byte $00
    .word $00
    .byte $00

; ---------------------------------------------------------------------------------------------------------------------
; SYSDEATH's error numbers.
; ---------------------------------------------------------------------------------------------------------------------

BADBRK = $01                        ;; a BRK from inside SOS
BADINT1 = $02                       ;; an interrupt that no allocated device claimed
BADINT2 = $03                       ;; interrupts nested too deep for the zero page
NMIHANG = $04                       ;; NMI could not be locked out
EVQOVFL = $05                       ;; the event queue overflowed
STKOVFL = $06                       ;; the stack overflowed
BADSYSCALL = $07                    ;; the device manager got a request code it doesn't know
DEV_OVFLOW = $08                    ;; too many device drivers
MEM2SML = $09                       ;; less than 64K of memory
VCBERR = $0A                        ;; a volume control block is unusable
FCBERR = $0B                        ;; a file control block is damaged
ALCERR = $0C                        ;; a volume's allocation blocks are invalid
TOOLONG = $0E                       ;; the pathname buffer overflowed
BADBUFNUM = $0F                     ;; a buffer number is invalid
BADBUFSIZ = $10                     ;; a buffer size is 0 or over 16K

; ---------------------------------------------------------------------------------------------------------------------
; Error numbers SOS calls return.
; ---------------------------------------------------------------------------------------------------------------------

BADSCNUM = $01                      ;; the system call manager: no such call
BADCZPAGE = $02                     ;; the caller's zero page is not $1A
BADXBYTE = $03                      ;; a pointer's X byte has bits 4-6 set
BADSCPCNT = $04                     ;; the call's parameter count is wrong
BADSCBNDS = $05                     ;; a parameter's address is out of bounds
NODNAME = $10                       ;; the device manager: no device by that name
BADDNUM = $11                       ;; the device number is invalid
XREQCODE = $20                      ;; drivers: the request code is invalid
XCTLCODE = $21                      ;; the control or status code is invalid
XCTLPARM = $22                      ;; the control or status parameter is invalid
XNOTOPEN = $23                      ;; the device is not open
XNOTAVAIL = $24                     ;; the device is not available
XNORESRC = $25                      ;; a resource the driver needs is not available
XBADOP = $26                        ;; the operation is invalid
XIOERROR = $27                      ;; an I/O error
XNODRIVE = $28                      ;; no drive is connected
XNOWRITE = $2B                      ;; the disk is write-protected
XBYTECNT = $2C                      ;; the byte count is not a multiple of 512
XBLKNUM = $2D                       ;; the block number is too large
XDISKSW = $2E                       ;; the disk was switched ($30-$3F are left to each driver)
BADPATH = $40                       ;; the file manager: the pathname's syntax is invalid
CFCBFULL = $41                      ;; the character file control block table is full
FCBFULL = $42                       ;; the block file control block table is full
BADREFNUM = $43                     ;; the reference number is invalid
PATHNOTFND = $44                    ;; the path was not found
VNFERR = $45                        ;; the volume was not found
FNFERR = $46                        ;; the file was not found
DUPERR = $47                        ;; a file by that name already exists
OVRERR = $48                        ;; the disk has too little space for the preallocation
DIRFULL = $49                       ;; the directory is full
CPTERR = $4A                        ;; the file's SOS version is incompatible
TYPERR = $4B                        ;; the file's storage type is not supported
EOFERR = $4C                        ;; the position is past the end of the file
POSNERR = $4D                       ;; the position is out of range
ACCSERR = $4E                       ;; the file's access attributes don't allow the request
BTSERR = $4F                        ;; the caller's buffer is too small
FILBUSY = $50                       ;; the file is already open for writing, or a write open conflicts
DIRERR = $51                        ;; a directory error
NOTSOS = $52                        ;; not a SOS disk
BADLSTCNT = $53                     ;; a value in the option list is invalid
OUTOFMEM = $54                      ;; no free memory for a buffer
BUFTBLFULL = $55                    ;; the buffer table is full
BADSYSBUF = $56                     ;; the system buffer parameter is invalid
DUPVOL = $57                        ;; two volumes with the same name are on line
NOTBLKDEV = $58                     ;; not a block device
LVLERR = $59                        ;; the file level is invalid
BITMAPADR = $5A                     ;; a volume bitmap's block address is invalid
BACKBIT = $20                       ;; a file's backup bit, in its access byte
BADJMODE = $70                      ;; the utility manager: the joystick mode is invalid
BADBKPG = $E0                       ;; the memory manager: the bank and page are invalid
SEGRQDN = $E1                       ;; the segment request was denied
SEGTBLFULL = $E2                    ;; the segment table is full
BADSEGNUM = $E3                     ;; the segment number is invalid
SEGNOTFND = $E4                     ;; no segment was found
BADSRCHMODE = $E5                   ;; the search mode is invalid
BADCHGMODE = $E6                    ;; the change mode is invalid
BADPGCNT = $E7                      ;; the page count is invalid

; The kernel's header in SOS.KERNEL, for the loader's ADVANCE: it runs at $B800 and is $47C0 bytes, to $FFBF.
    .word $B800
    .word $47C0
