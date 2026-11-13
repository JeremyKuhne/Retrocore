; ---------------------------------------------------------------------------------------------------------------------
; BFM.INIT2: the block file manager's second initialization, at $B800-$BBFF.
;
; It runs while SOS starts, and is the copy protection check: it reads a key from the boot disk's address fields
; and, on a protected disk, decodes the interpreter with it. Once it has run, the BFM uses its 1K as the two bitmap
; buffers, A at $B800 (BMAPAGE) and B at $BA00 (BMBPAGE).
; ---------------------------------------------------------------------------------------------------------------------

I_BASE_P = $2                       ;; where in the caller's page zero the loader keeps the interpreter's address
KERNEL_BASE = $B800                 ;; the kernel's base: the decoding stops below it
ROMID = $A0                         ;; the byte at RDADR in the newer boot ROM
SLOT = $60                          ;; the built-in drive's slot times 16
BEGTRK = $9                         ;; the first track the key is read from
BEGSECT = $2                        ;; the sector the key's first address field must be
ENDSECT = $6                        ;; the sector the last address field is on a protected disk
TRACK = $99                         ;; the boot ROM's copy of an address field's track
SECTOR = $98                        ;; the boot ROM's copy of an address field's sector
VOLUME = $9A                        ;; the boot ROM's copy of an address field's volume
KEY = $E0                           ;; the key, eight bytes
PREV_K = KEY+$8                     ;; the decoder's running value
XIDX = KEY+$9                       ;; the next key byte <GETK> fills, counting down from 7
I = KEY+$A                          ;; the decoder's pointer (two bytes)
RDADR = $F1B9                       ;; the boot ROM's address field reader, in the newer ROM
RDADRX = $F1BD                      ;; the same in the older ROM
E_REG = $FFDF                       ;; the environment register
B_REG = $FFEF                       ;; the bank register
MOTORON = $C089                     ;; turns the drive's motor on, plus the slot
MOTOROFF = $C088                    ;; turns it off, plus the slot

;; How far BFM.INIT2 has got: $FE before it has run, $FF after the first call, 0 after the second and 1 when it
;; decoded the interpreter.
STATE:
    .byte $FE

;; Checks the boot disk's copy protection, and decodes the interpreter when the disk is protected.
;;
;; The first call does nothing. The next reads the key (<GETK>); when the disk turns out protected, NMI is turned off
;; and the interpreter decoded (<DC>).
;; Out: carry = set when the key could not be read
;; Uses: A, X, Y
;; See: <GETK>, <DC>
BFM_INIT2:
    inc STATE
    bmi BFMI050                     ; the first call
    jsr GETK
    lda RETRY
    beq BADNEWS                     ; the retries ran out
    bcc BFMI050                     ; not protected
    jsr NMIDSBL
    jsr DC
    inc STATE
BFMI050:
    clc
    rts
BADNEWS:
    sec
    rts

;; Decodes the interpreter in place, and points the loader at its real start.
;;
;; The interpreter is decoded from three bytes past the address the loader has for it up to <KERNEL_BASE>, in the
;; system bank. The three decoded bytes there are a JMP: its address becomes the loader's interpreter address, and
;; the three bytes are then zeroed.
;; In: KEY = the key, CZPAGE+I_BASE_P = the interpreter's address
;; Uses: A, X, Y, I, PREV_K
;; See: <DCLOOP>, <BFM_INIT2>
DC:
    lda B_REG
    pha
    lda SYSBANK
    sta B_REG
    clc
    lda CZPAGE+I_BASE_P
    adc #3
    sta I
    pha
    lda CZPAGE+I_BASE_P+1
    adc #0
    sta I+1
    pha
    lda #0
    sta SXPAGE+I+1                  ; I is not an extended pointer
    ldy I
    lda #0
    sta I                           ; I to the page, Y to the byte in it
    sta PREV_K
    jsr DCLOOP
    pla
    sta I+1
    pla
    sta I
    ldy #1
    lda (I),y
    sta CZPAGE+I_BASE_P
    iny
    lda (I),y
    sta CZPAGE+I_BASE_P+1
    ldy #2
    lda #0
DCA:
    sta (I),y
    dey
    bpl DCA
    pla
    sta B_REG
    rts

;; Decodes memory from (I),Y up to <KERNEL_BASE>, a page at a time.
;;
;; Before each page, the eight-byte key turns left one bit, KEY its most significant byte. For each byte, the running
;; value PREV_K has two key bytes added, picked by the byte's address and by the first of them, and the byte is
;; exclusive-ored with it.
;; In: I = the page, Y = the first byte in it, KEY = the key, PREV_K = the running value
;; Uses: A, X, Y, I+1, PREV_K, KEY
;; See: <DC>
DCLOOP:
    ldx #7
    clc
    lda KEY
    bpl DC1
    sec                             ; the top bit comes round to the bottom
DC1:
    rol KEY,x
    dex
    bpl DC1
DC2:
    tya
    and #7
    eor #2
    tax
    lda KEY,x
    pha
    and #7
    tax
    pla
    clc
    adc PREV_K
    clc
    adc KEY,x
    sta PREV_K
    eor (I),y
    sta (I),y
    iny
    bne DC2
    inc I+1
    lda I+1
    cmp #>KERNEL_BASE
    bcc DCLOOP
    rts

;; How many more times <GETK> may start over after a read error; 0 when the key could not be read.
RETRY:
    .byte 10+1

;; The track <GETK> is on.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
OURTRACK:
    .res 1, $84

;; Reads the copy protection key from the built-in drive: the volume numbers of eight address fields.
;;
;; It seeks to track <BEGTRK> and waits for the address field of sector <BEGSECT>. Then, track by track for eight
;; tracks, it keeps the volume number of the address field it is at, steps in, waits a little and reads the next
;; address field it finds. A protected disk's tracks are laid out so that the last field is sector <ENDSECT>, and
;; its volume numbers differ from track to track; a normal disk has one volume number. A read error starts it over,
;; up to ten times. It runs at 1 MHz with the ROM switched in, which <SEEKDSK3> needs, and returns to 2 MHz and RAM.
;; Out: carry = set when the disk is protected, KEY = the key, RETRY = 0 when the retries ran out
;; Uses: A, X, Y, XIDX, OURTRACK
;; See: <BFM_INIT2>, <DOREAD>, <SEEKDSK3>
GETK:
    ldx #7
    stx XIDX
    ldx #SLOT
    lda MOTORON,x
    lda E_REG
    ora #$83                        ; 1 MHz, with the ROM and I/O
    sta E_REG
GETK010:
    lda #BEGTRK
    sta OURTRACK
    jsr SEEKDSK3
GETK020:
    ldx #SLOT
    jsr DOREAD
    bcs IOERROR
    lda SECTOR
    cmp #BEGSECT
    bne GETK020
GETK100:
    ldx #1
    jsr WAIT
    ldx XIDX
    lda VOLUME
    sta KEY,x
    dec XIDX
    bmi ENUFF                       ; eight bytes
    inc OURTRACK
    lda OURTRACK
    ldx #SLOT
    jsr SEEKDSK3
    ldx #SLOT
    jsr DOREAD
    bcc GETK100
    bcs IOERROR
ENUFF:
    ldx #SLOT
    lda MOTOROFF,x
    lda E_REG
    and #$7C                        ; 2 MHz, with RAM
    sta E_REG
    lda SECTOR
    cmp #ENDSECT
    bne NOTPROT
    lda KEY
    eor KEY+1
    beq NOTPROT                     ; one volume number: not protected
    sec
    rts
NOTPROT:
    lda #0
    clc
    rts

;; Reads the next address field, through the boot ROM's reader at whichever address this ROM has it.
;; In: X = the slot times 16
;; Out: carry = set on an error, SECTOR, TRACK and VOLUME = the field's
;; See: <WHICHROM>, <RDADR>
DOREAD:
    jsr WHICHROM
    bcs OLDREAD
    jmp RDADR
OLDREAD:
    jmp RDADRX

;; Tells the newer boot ROM from the older by the byte at <RDADR>.
;; Out: carry = clear for the newer ROM
;; Uses: A
;; Keeps: X, Y
;; See: <DOREAD>
WHICHROM:
    lda RDADR
    cmp #ROMID
    clc
    beq NEWROM
    sec
NEWROM:
    rts
IOERROR:                            ; GETK's read errors come here: start over
    dec RETRY
    beq ERR1
    jmp GETK
ERR1:
    jmp ENUFF

;; Waits about X times 1.3 milliseconds at 1 MHz.
;; In: X = the count
;; Out: X = 0, Y = 0
;; Keeps: A
WAIT:
    ldy #0
W1:
    dey
    bne W1
    dex
    bne W1
    rts
ZZLEN = $400                        ;; the module's length, which must be SosOrg.asm's LENBFMI
    .assert ZZLEN == LENBFMI, "SOSORG gives the module another length"
