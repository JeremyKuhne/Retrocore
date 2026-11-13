; SOSLDR, part F: placing and relocating driver modules, claiming memory segments, the error and welcome screens,
; the parameter lists of the loader's SOS calls, and the space INIT is assembled into.
;
; Driver modules are placed from the top of the space below the interpreter downward, last module first, each just
; below the one before. A module that no longer fits above $2000 goes to the top ($A000) of the next bank down; no
; module spans two banks. The pages used in each bank are added up in DSEGLIST, and ALLOC_DSEG claims them.

;; Finds where the next driver module goes, below the previous one, and counts its pages in the driver segments.
;; In:    DST_P = the previous module's address, DSTBANK = its bank, CNT = the module's length,
;;        PG_ALIGN = its alignment (0 for none)
;; Out:   DST_P = the module's address, DSTBANK = its bank (negative when the banks ran out),
;;        PREVBANK = the previous module's bank
;; Uses:  A, X, PREVDST, DSEGX, DSEGLIST
;; Keeps: Y
;; See:   <NEWDST>, <BUILD_DSEG>
GETMEM:
    lda DSTBANK
    sta PREVBANK
    lda DST_P
    sta PREVDST
    lda DST_P+1
    sta PREVDST+1
    jsr NEWDST
    lda DST_P+1
    cmp #$20
    bcc GETM010                     ; doesn't fit in this bank
    sec
    lda PREVDST+1
    sbc DST_P+1
    clc
    jsr BUILD_DSEG
    jmp GETM_EXIT
GETM010:
    dec DSTBANK                     ; the top of the next bank down
    lda #<($A000)
    sta PREVDST
    lda #>($A000)
    sta PREVDST+1
    jsr NEWDST
    sec
    lda PREVDST+1
    sbc DST_P+1
    sec
    jsr BUILD_DSEG
GETM_EXIT:
    rts

;; Works out a driver module's address: just below PREVDST, page-aligned when the module asks.
;;
;; With alignment, the address is moved down so that PG_ALIGN bytes into the module (the end of its first DIB and
;; DCB) is the start of a page.
;; In:    PREVDST = the top of the free space, CNT = the module's length, PG_ALIGN = its alignment (0 for none)
;; Out:   DST_P = the module's address, or 0 when it does not fit between $2000 and PREVDST
;; Uses:  A, X
;; Keeps: Y
NEWDST:
    sec
    lda PREVDST
    sbc #<($2000)
    tax
    lda PREVDST+1
    sbc #>($2000)
    cpx CNT
    sbc CNT+1
    bcs NEWD010
    lda #0
    sta DST_P
    sta DST_P+1
    beq NEWD_EXIT
NEWD010:
    sec
    lda PREVDST
    sbc CNT
    sta DST_P
    lda PREVDST+1
    sbc CNT+1
    sta DST_P+1
    lda PG_ALIGN
    ora PG_ALIGN+1
    beq NEWD_EXIT
    sec                             ; down to the page start, less the alignment
    lda #0
    sbc PG_ALIGN
    sta DST_P
    lda DST_P+1
    sbc PG_ALIGN+1
    sta DST_P+1
NEWD_EXIT:
    rts

;; Adds a driver module's pages to the current driver segment, or starts a segment for a new bank.
;; In:    A = the module's pages, carry = set when the module went to a new bank
;; Out:   DSEGX = the segment's index, DSEGLIST,DSEGX = its pages so far
;; Uses:  A, X
;; Keeps: Y
;; See:   <DSEGLIST>, <ALLOC_DSEG>
BUILD_DSEG:
    pha
    bcs BLDS010
    lda DSEGX
    bpl BLDS020
BLDS010:
    inc DSEGX                       ; a new bank, or the first module of all
BLDS020:
    ldx DSEGX
    clc
    pla
    adc DSEGLIST,x
    sta DSEGLIST,x
    rts

;; The index of the last driver segment in <DSEGLIST>; $FF until the first module is placed.
DSEGX:
    .byte $FF

;; The pages of driver modules in each bank used: the system bank first, then each bank below it.
;; See: <BUILD_DSEG>, <ALLOC_DSEG>
DSEGLIST:
    .byte $0
    .byte $0
    .byte $0
    .byte $0

;; Relocates a driver module's code for the address it will run at.
;;
;; A module is assembled to run at 0. Its relocation field is a list of 2-byte offsets into the code field, each
;; of a word that holds an address; this adds the module's address to each such word, working from the field's end.
;; In:    SRC_P = the code field, REL_P = the relocation field's count word (after the field), DST_P = the address
;;        the module will run at
;; Uses:  A, Y, REL_P, REL_END, CODE_P
;; Keeps: X
;; See:   <DADVANCE>
RELOC:
    sec
    ldy #0
    lda REL_P
    sbc (REL_P),y
    sta REL_END
    iny
    lda REL_P+1
    sbc (REL_P),y
    sta REL_END+1
REL_LOOP:
    sec
    lda REL_P
    sbc #2
    sta REL_P
    lda REL_P+1
    sbc #0
    sta REL_P+1
    lda REL_P
    cmp REL_END
    lda REL_P+1
    sbc REL_END+1
    bcc REL_EXIT
    ldy #0
    clc
    lda SRC_P
    adc (REL_P),y
    sta CODE_P
    iny
    lda SRC_P+1
    adc (REL_P),y
    sta CODE_P+1
    lda CXPAGE+SRC_P+1
    sta CXPAGE+CODE_P+1
    ldy #0
    clc
    lda (CODE_P),y
    adc DST_P
    sta (CODE_P),y
    iny
    lda (CODE_P),y
    adc DST_P+1
    sta (CODE_P),y
    jmp REL_LOOP
REL_EXIT:
    rts

;; Claims memory segments for SOS's low memory, the kernel and the interpreter, so the memory manager won't give
;; them out.
;;
;; The first segment (ID 0) is $0000-$1DFF, bank $F to the memory manager. The kernel's (ID 1) and the
;; interpreter's (ID 2) each run from their first page up to the page before the segment above; pages from $A0 up
;; are bank $10 to the memory manager, and the system bank's pages below that.
;; In:    K_BASE = the kernel's address, I_BASE_P = the interpreter's address, SYSBANK
;; Uses:  A, X, Y, SEGBASE, SEGLIM, SEGID
;; See:   <RSEG>
ALLOC_SEG:
    brk
    .byte REQSEG
    .word SEGMENT
    lda #$10
    sta SEGBASE
    sta SEGLIM
    lda #0                          ; so the kernel's limit is page $FF
    sta SEGBASE+1
    ldx K_BASE+1
    jsr RSEG
    ldx I_BASE_P+1
    jsr RSEG
    rts

;; Claims the segment from a base page up to the page below the last segment claimed, with the next ID.
;;
;; A range that crosses $A000 is claimed as two segments: $A0 up in bank $10, then the base up to $9F in the system
;; bank.
;; In:    X = the base page, SEGBASE = the base's and limit's bank, SEGBASE+1 = the last segment's base page
;; Out:   SEGBASE+1 = the base page, for the next call
;; Uses:  A, X, Y, SEGLIM, SEGID
;; See:   <ALLOC_SEG>
RSEG:
    inc SEGID
    ldy SEGBASE+1
    dey
    sty SEGLIM+1
    stx SEGBASE+1
    cpx #$A0
    bcs RSEG010
    lda SEGLIM+1
    cmp #$A0
    bcc RSEG010
    txa
    pha
    ldx #$A0
    stx SEGBASE+1
    brk
    .byte REQSEG
    .word SEGMENT
    pla
    sta SEGBASE+1
    lda #$9F
    sta SEGLIM+1
    lda SYSBANK
    sta SEGBASE
    sta SEGLIM
RSEG010:
    brk
    .byte REQSEG
    .word SEGMENT
    rts

;; Claims a segment (ID 3) for the driver modules in each bank used, with FIND_SEG.
;;
;; The memory manager finds each segment from the top of memory down, where the modules were placed. A driver file
;; whose modules are all inactive stops the loader with INVALID DRIVER FILE.
;; In:    DSEGX, DSEGLIST
;; Uses:  A, X, Y, SEGPGCNT
;; See:   <BUILD_DSEG>
ALLOC_DSEG:
    inc DSEGX                       ; DSEGX becomes the number of segments
    bne ALDS010
    ldx #ERR5X
    ldy #ERR5L
    jsr ERROR
ALDS010:
    ldy #$FF
ALDS020:
    iny
    cpy DSEGX
    bcs ALDS_EXIT
    lda DSEGLIST,y
    sta SEGPGCNT
    brk
    .byte FINDSEG
    .word SEGMENT1
    jmp ALDS020
ALDS_EXIT:
    rts

;; Shows an error message and stops SOS; only Control-Reset gets out.
;;
;; The message is centered on the screen's 16th line (<EMSGADR>), in inverse, as its characters have bit 7 clear.
;; It switches I/O and the ROM in, beeps by reading $C040, and loops.
;; In:    X = the message's ERRnX value (its last character's index in <ERR>), Y = its ERRnL length
ERROR:
    sty ETEMP
    sec
    lda #40                         ; Y = the column after the message: (40 - length) / 2 + length
    sbc ETEMP
    lsr a
    clc
    adc ETEMP
    tay
PRNT010:
    lda ERR,x
    sta EMSGADR-1,y
    dex
    dey
    dec ETEMP
    bne PRNT010
    lda #$73                        ; I/O, screen, reset and the ROM
    sta E_REG
    lda a:$C040
    jmp *
EMSGADR = $7A8                      ;; the screen line ERROR uses, the 16th of the text page

;; The loader's error messages, one after another.
;;
;; For each message ERRn, ERRnL is its length and ERRnX the index of its last character from ERR, the values
;; <ERROR> takes.
ERR:
ERR0:
    .byte "I/O ERROR"
ERR0L = * - ERR0
ERR0X = * - ERR-1
ERR1:
    .byte "INTERPRETER FILE NOT FOUND"
ERR1L = * - ERR1
ERR1X = * - ERR-1
ERR2:
    .byte "INVALID INTERPRETER FILE"
ERR2L = * - ERR2
ERR2X = * - ERR-1
ERR3:
    .byte "INCOMPATIBLE INTERPRETER"
ERR3L = * - ERR3
ERR3X = * - ERR-1
ERR4:
    .byte "DRIVER FILE NOT FOUND"
ERR4L = * - ERR4
ERR4X = * - ERR-1
ERR5:
    .byte "INVALID DRIVER FILE"
ERR5L = * - ERR5
ERR5X = * - ERR-1
ERR6:
    .byte "DRIVER FILE TOO LARGE"
ERR6L = * - ERR6
ERR6X = * - ERR-1
ERR7:
    .byte "ROM ERROR:  PLEASE NOTIFY YOUR DEALER"
ERR7L = * - ERR7
ERR7X = * - ERR-1
ERR8:
    .byte "TOO MANY DEVICES"
ERR8L = * - ERR8
ERR8X = * - ERR-1
ERR9:
    .byte "TOO MANY BLOCK DEVICES"
ERR9L = * - ERR9
ERR9X = * - ERR-1
ERR10:
    .byte "EMPTY DRIVER FILE"
ERR10L = * - ERR10
ERR10X = * - ERR-1

;; Shows the welcome screen: "APPLE ///", the SOS version, the date and time, and Apple's copyright.
;;
;; Each line is centered. The date and time line is left out when GET_TIME gives no weekday, which means there is
;; no clock.
;; Uses:  A, X, Y, WTEMP, DMSG, DATETIME
;; See:   <AMSG>, <SOSVER>, <DMSG>, <CMSG>
WELCOME:
    ldy #AMSGL
WAM010:
    lda AMSG-1,y
    sta AMSGADR-1,y
    dey
    bne WAM010
    clc                             ; X = the column after the version: (40 + length) / 2
    lda #40
    adc #<SOSVERL
    lsr a
    tax
    ldy #<SOSVERL
WSM010:
    lda SOSVER-1,y
    ora #$80
    sta SMSGADR-1,x
    dex
    dey
    bne WSM010
    brk
    .byte GETTIME
    .word DTPARMS
    lda DATETIME+8                  ; the weekday, 1 for Sunday; 0 when there is no clock
    and #$0F
    beq WDM040
    sta WTEMP
    asl a
    adc WTEMP
    tax
    ldy #3
WDM010:
    lda DAYNAME-1,x
    sta DMSG-1,y
    dex
    dey
    bne WDM010
    lda DATETIME+7                  ; the day of the month
    ldx DATETIME+6
    sta DMSG+6
    stx DMSG+5
    lda DATETIME+5                  ; the month, 1-12, from its two digits
    and #$0F
    ldx DATETIME+4
    cpx #$31
    bcc WDM020
    adc #9                          ; carry is set: adds 10
WDM020:
    sta WTEMP
    asl a
    adc WTEMP
    tax
    ldy #3
WDM030:
    lda MONNAME-1,x
    sta DMSG+7,y
    dex
    dey
    bne WDM030
    lda DATETIME+3                  ; the year's last two digits
    ldx DATETIME+2
    sta DMSG+13
    stx DMSG+12
    lda DATETIME+10                 ; the hour
    ldx DATETIME+09
    sta DMSG+17
    stx DMSG+16
    lda DATETIME+12                 ; the minute
    ldx DATETIME+11
    sta DMSG+20
    stx DMSG+19
    ldy #DMSGL
WDM050:
    lda DMSG-1,y
    ora #$80
    sta DMSGADR-1,y
    dey
    bne WDM050
WDM040:
    ldy #CMSGL
WCM010:
    lda CMSG-1,y
    sta CMSGADR-1,y
    dey
    bne WCM010
    rts

;; "APPLE ///", the welcome screen's first line.
AMSG:
    .hiascii "APPLE ///"
AMSGL = * - AMSG
AMSGADR = (((40-AMSGL)/2)+$4A8)     ;; centered on the 10th line
SMSGADR = $5A8                      ;; the version's line, the 12th; WELCOME centers the version on it

;; The date and time line, a template WELCOME fills in from GET_TIME.
DMSG:
    .byte "DAY, DD-MON-YY  HH:MM"
DMSGL = * - DMSG
DMSGADR = (((40-DMSGL)/2)+$6A8)     ;; centered on the 14th line

;; The weekdays' three-letter names, Sunday first.
DAYNAME:
    .byte "SUNMONTUEWEDTHUFRISAT"

;; The months' three-letter names, January first.
MONNAME:
    .byte "JANFEBMARAPRMAYJUN"
    .byte "JULAUGSEPOCTNOVDEC"

;; Apple's copyright line, at the bottom of the welcome screen.
CMSG:
    .hiascii "(C)1980,1981,1982 BY APPLE COMPUTER INC."
CMSGL = * - CMSG
CMSGADR = (((40-CMSGL)/2)+$7D0)     ;; centered on the 24th line, the last

; ---------------------------------------------------------------------------------------------------------------------
; The loader's SOS calls: each is a BRK followed by the call number and the address of its parameter list.
; ---------------------------------------------------------------------------------------------------------------------

OPEN = $C8                          ;; the OPEN call

;; OPEN's parameters: 4 of them, the pathname <PATH>, the reference number returned, and the option list.
OPEN_PARMS:
    .byte $4
    .word PATH
;; The reference number OPEN returns, which READ and CLOSE use.
OPEN_REF:
    .byte $0
    .word OPEN_LIST
    .byte $4
;; OPEN's option list: any access, 4 pages of file buffer, and the buffer's address in <SYSBUF_P>.
OPEN_LIST:
    .byte $0, $4
    .word SYSBUF_P

;; The pathname of the file to open, which the loader copies from <I_PATH> or <D_PATH>.
;;
;; The initial 64 bytes are whatever was in memory when Apple built SOS.KERNEL; the loader sets them at run time.
PATH:
    .byte $A0, $86, $A0, $CD, $BD, $A0, $A0, $A3, $A0, $A0, $9A, $A0, $81, $A0, $A0, $CF
    .byte $A0, $A0, $81, $A0, $A0, $95, $A0, $A0, $90, $A0, $A0, $D0, $A0, $85, $A0, $A0
    .byte $A0, $A0, $A0, $A5, $A0, $A0, $83, $A0, $A0, $A0, $A0, $80, $A0, $A0, $AE, $A0
    .byte $A0, $F2, $A0, $A0, $C1, $A0, $A0, $85, $A0, $A0, $D0, $A0, $A0, $A9, $D3, $CC
;; The label SOS.INTERP must start with.
I_LABEL:
    .byte "SOS NTRP"

;; The label SOS.DRIVER must start with.
D_LABEL:
    .byte "SOS DRVR"

READ = $CA                          ;; the READ call

;; READ's parameters: 4 of them, which read the whole file into banks 0 and 1 from $80:FILE.
READ_PARMS:
    .byte $4
;; The file to read, from <OPEN_REF>.
READ_REF:
    .byte $0
;; The buffer: the zero-page pointer <RDBUF_P>, whose X byte reaches banks 0 and 1.
READ_BUF:
    .word RDBUF_P
;; Bytes to read: everything up to the end of the 64K the X byte reaches.
READ_BYT:
    .word $FFFF-FILE+1
;; Bytes read, returned.
READ_BYTRD:
    .word $0
CLOSE = $CC                         ;; the CLOSE call

;; CLOSE's parameters: 1 of them, the file to close.
CLOSE_PARMS:
    .byte $1

;; The file to close, from <OPEN_REF>.
CLOSE_REF:
    .byte $0
FINDSEG = $41                       ;; the FIND_SEG call

;; FIND_SEG's parameters, for the driver segments: 6 of them.
SEGMENT1:
    .byte $6
;; The search mode (0) and the segment ID (3, for drivers).
SEGSRCH:
    .byte $0, $3
;; The segment's pages, set for each segment; then the base, limit and segment number, returned.
SEGPGCNT:
    .word $0000
    .word $0
    .word $0
    .byte $0
REQSEG = $40                        ;; the REQUEST_SEG call

;; REQUEST_SEG's parameters: 4 of them, the base, the limit, the segment ID and the segment number returned.
SEGMENT:
    .byte $4
;; The segment's first bank and page; at first bank $F, page 0, for SOS's low memory.
SEGBASE:
    .byte $F, $0
;; The segment's last bank and page; at first bank $F, page $1D.
SEGLIM:
    .byte $F, $1D
;; The segment's ID, counted up from 0 by <RSEG>, then the segment number returned.
SEGID:
    .byte $0, $0
SETPREFIX = $C6                     ;; the SET_PREFIX call

;; SET_PREFIX's parameters: 1 of them, the prefix.
PREFX_PARMS:
    .byte $1
    .word PREFX_PATH
;; The prefix the interpreter starts with: the boot volume, .D1.
PREFX_PATH:
    .byte $3
    .byte ".D1"
GETTIME = $63                       ;; the GET_TIME call

;; GET_TIME's parameters: 1 of them, where to put the date and time.
DTPARMS:
    .byte 1
    .word DATETIME
;; The date and time GET_TIME returns, as 18 ASCII digits: year, month, day, weekday, hour, minute, second and
;; milliseconds. The initial text only names the fields.
DATETIME:
    .byte "YYYYMMDDWHHMMSSMMM"

; ---------------------------------------------------------------------------------------------------------------------
; The end of the loader's code. The space up to INITMODULE, and the rest of INIT's $200 bytes after its code, are
; padding; their bytes are whatever was in memory when Apple built SOS.KERNEL, and nothing reads them.
; ---------------------------------------------------------------------------------------------------------------------

SLOP = <($F8-*)                     ;; the padding's length, to put INITMODULE at an address ending in $F8
    .byte $A0, $CC, $B1, $A0, $E5, $BF, $A0, $CE, $A0, $A0, $86, $A0, $CD, $BD, $A0, $A0
    .byte $A3, $A0, $A0, $C5, $A0, $81, $A0, $A0, $E5, $A0, $A0, $81, $A0, $A0, $95, $A0
    .byte $A0, $90, $A0, $A0, $D0, $A0, $85, $A0, $A0, $A0, $A0, $A0, $A5, $A0, $A0, $83
    .byte $A0, $A0, $A0, $A0, $80, $A8, $A0, $AE, $A0, $A0, $CD, $A0, $A0, $C1, $A0, $A0
    .byte $85, $A0, $A0, $D0, $AE, $A0, $A9, $D3, $CC, $A0, $BA, $98, $A0, $C6, $86, $A0
; INITMODULE: the $200 bytes the loader keeps for INIT (Init.asm), which runs here at ORGINIT. INIT is $1B2 bytes;
; padding fills the rest.
INITMODULE:
.scope INIT
    .include "Init.asm"
.endscope
    .byte $8E, $BF, $A0, $CE, $A0, $C5, $86, $A0, $CD, $C9, $A0, $A0, $A3, $A0, $A0, $C5
    .byte $A0, $81, $A0, $A0, $E5, $A0, $A0, $81, $A0, $A0, $95, $A0, $A0, $A5, $A0, $A0
    .byte $D0, $A0, $D1, $A0, $A0, $A0, $A0, $A0, $A5, $A0, $A0, $9D, $A0, $A0, $A0, $A0
    .byte $83, $A8, $A0, $AE, $A0, $A0, $CD, $A0, $A0, $C1, $A0, $A0, $85, $A0, $A0, $E0
    .byte $AE, $A0, $A9, $D3, $99, $A0, $BA, $98, $A0, $C6, $86, $A0, $C5, $FD
; LDREND: the end of the loader. In bank 0 the open file's 1K buffer follows it, and then the file buffer, FILE.
LDREND:
FILE = * - $2000+$400               ;; where SOS.INTERP and SOS.DRIVER are read to, as an address under X byte $80
I_FILE = FILE                       ;; SOS.INTERP's label
I_HDR_CNT = I_FILE+$8               ;; SOS.INTERP's header count
D_FILE = FILE                       ;; SOS.DRIVER's label
D_HDR_CNT = D_FILE+$8               ;; SOS.DRIVER's header count
D_DRIVES = D_HDR_CNT+$2             ;; the number of built-in drives SOS.DRIVER asks for
D_CHRSET = D_DRIVES+$2+$10          ;; the character set ($400 bytes), after 16 bytes the loader skips
D_KYBD = D_CHRSET+$10+$400          ;; the keyboard table ($100 bytes), after 16 more bytes the loader skips
ZZEND:                              ; the end of the loader module
ZZLEN = ZZEND-ZZORG
    .assert INITMODULE == ORGINIT, "INIT runs where SOSORG puts it"
    .assert ZZLEN == LENLODR + $200, "The loader and the space it keeps for INIT"
