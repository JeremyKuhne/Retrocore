; SOSLDR, part D: the loader's main program, MOVE, linking DIBs into the system device table, and SOSLDR1, which
; processes the kernel, interpreter and driver files.
;
; MOVE, LINK, LINK_INIT and ALLOC_DEV switch the bank register, so they must stay below $2000, where the code does
; not change with the bank.

;; The loader's entry point: loads SOS and starts the interpreter.
;;
;; The boot loader has read SOS.KERNEL into the highest bank, from $1E00 up, and jumps here. The loader clears the
;; caller's and SOS's zero, extend and stack pages, runs with the screen and reset enabled and RAM unprotected, and
;; calls <SOSLDR1> to do the work. Then it sets the environment the interpreter starts in (write protect on, the
;; alternate stack empty, the caller's zero page, the system bank) and jumps to the interpreter's first byte.
;; See: <SOSLDR1>
SOSLDR:
    lda #0
    tax
SLDR010:
    sta CZPAGE,x
    sta CXPAGE,x
    sta CSPAGE,x
    sta SZPAGE,x
    sta SXPAGE,x
    sta SSPAGE,x
    dex
    bne SLDR010
    lda #$30                        ; screen and reset enabled; 2 MHz, no I/O, RAM writable, alternate stack, no ROM
    sta E_REG
    ldx #$FB                        ; leave room: the console driver's initialization changes the stack above it
    txs
    lda #>CZPAGE
    sta Z_REG
    jsr SOSLDR1
    lda E_REG
    and #$10                        ; keep reset enable
    ora #$28                        ; turn on the screen and write protect
    sta E_REG
    ldx #$FF
    txs
    lda #>CZPAGE
    sta Z_REG
    lda SYSBANK
    sta B_REG
    jmp (I_BASE_P)                  ; start the interpreter

;; Copies a block of memory, in the given bank, from <SRC_P> to <DST_P>.
;;
;; It copies from the last page down, so it can move a block to a higher address over itself. The pointers' X bytes
;; select extended addressing as usual. <CNT> can be 0.
;; In:    A = the bank to switch in while copying, SRC_P = the source, DST_P = the destination,
;;        CNT = the number of bytes
;; Out:   SRC_P and DST_P as they were, B_REG as it was
;; Uses:  A, X, Y, CNT
MOVE:
    tax
    lda B_REG
    pha
    stx B_REG
    lda CNT+1
    ora CNT
    beq MOVE_EXIT
    lda CNT
    bne MOVE010
    dec CNT+1
MOVE010:
    dec CNT                         ; CNT = the last byte's offset
    clc
    lda SRC_P+1
    adc CNT+1
    sta SRC_P+1                     ; point both at the last page
    lda DST_P+1
    adc CNT+1
    sta DST_P+1
    inc CNT+1                       ; CNT+1 = pages to copy, counting a partial one
    ldy CNT
    beq MOVE020
MOVE_PAGE:
    lda (SRC_P),y
    sta (DST_P),y
    dey
    bne MOVE_PAGE
MOVE020:
    lda (SRC_P),y                   ; byte 0 of the page, then on to the page below from $FF
    sta (DST_P),y
    dey
    dec SRC_P+1
    dec DST_P+1
    dec CNT+1
    bne MOVE_PAGE
    inc SRC_P+1
    inc DST_P+1
MOVE_EXIT:
    pla
    sta B_REG
    rts

;; Links a driver module that has just been moved into place to the DIBs before it, and adds its devices to the
;; system device table.
;;
;; The previous module's last active DIB (left in <LINK_P>, in bank <PREVBANK>) gets the address of this module's
;; first active DIB. Then the chain is walked from there in bank <DSTBANK>, adding each DIB with <ALLOC_DEV>, until a
;; link of 0 or a DIB that links to itself, whose link is then set to 0.
;; In:    DST_P = the module's address, DSTBANK = its bank, FIRST_ADIB = its first active DIB's offset,
;;        LINK_P = the last DIB linked so far, PREVBANK = that DIB's bank
;; Out:   LINK_P = the module's last active DIB, B_REG = 0
;; Uses:  A, X, Y, FIRST_ADIB
;; Entry: WALKLINKS = adds the DIB at LINK_P and the chain after it, in the bank already selected
;; See:   <FLAGS>, <ALLOC_DEV>
LINK:
    clc
    lda DST_P
    adc FIRST_ADIB
    sta FIRST_ADIB
    lda DST_P+1
    adc FIRST_ADIB+1
    sta FIRST_ADIB+1
    lda #0
    sta CXPAGE+FIRST_ADIB+1
    lda PREVBANK
    sta B_REG
    ldy #0
    lda FIRST_ADIB
    sta (LINK_P),y
    iny
    lda FIRST_ADIB+1
    sta (LINK_P),y
    lda DSTBANK
    sta B_REG
    lda FIRST_ADIB
    sta LINK_P
    lda FIRST_ADIB+1
    sta LINK_P+1
WALKLINKS:
    jsr ALLOC_DEV
LINK010:
    ldy #0                          ; stop at a link of 0
    lda (LINK_P),y
    iny
    ora (LINK_P),y
    beq LINK100
    lda (LINK_P),y                  ; or at a DIB that links to itself
    cmp LINK_P+1
    bne LINK030
    dey
    lda (LINK_P),y
    cmp LINK_P
    beq LINK100
LINK030:
    ldy #0
    lda (LINK_P),y
    tax
    iny
    lda (LINK_P),y
    stx LINK_P
    sta LINK_P+1
    jsr ALLOC_DEV
    jmp LINK010
LINK100:
    ldy #0
    tya
    sta (LINK_P),y
    iny
    sta (LINK_P),y
    dey
    sty B_REG
    rts

;; Starts the system device table over with the built-in floppy drives' DIBs.
;;
;; The loader calls it twice: with the kernel file's drive count, so only .D1 is there while the interpreter and
;; drivers load, and again with the driver file's count before adding the drivers.
;; In:    A = the number of built-in drives (1-4)
;; Out:   MAX_DNUM, BLKDLST = the built-in drives, LINK_P = the last one's DIB, B_REG = 0
;; Uses:  A, X, Y
;; See:   <SET_DRIVES>, <LINK>
LINK_INIT:
    jsr SET_DRIVES
    lda #0
    sta MAX_DNUM
    sta BLKDLST
    sta CXPAGE+LINK_P+1
    lda #<DIB1
    sta LINK_P
    lda #>DIB1
    sta LINK_P+1
    jmp WALKLINKS

;; Adds a device to the device manager's system device table, and to the block device list if it is one.
;;
;; The table entry holds the DIB's bank, the DIB's address past its link and entry words, the entry point less 1
;; (the device manager calls it by RTS), and the unit number. Too many devices, or too many block devices, stop
;; the loader with an error.
;; In:    LINK_P = the DIB, B_REG = its bank
;; Out:   MAX_DNUM = the new device's number, BLKDLST = updated
;; Uses:  A, X, Y
;; See:   <LINK>, <ERROR>
ALLOC_DEV:
    inc MAX_DNUM
    ldx MAX_DNUM
    cpx #<SDT_SIZE
    bcc ADEV010
    ldx #ERR8X
    ldy #ERR8L
    jsr ERROR
ADEV010:
    lda B_REG
    sta SDT_BANK,x
    clc
    lda LINK_P
    adc #4
    sta SDT_DIBL,x
    lda LINK_P+1
    adc #0
    sta SDT_DIBH,x
    sec
    ldy #DIB_ENTRY
    lda (LINK_P),y
    sbc #1
    sta SDT_ADRL,x
    iny
    lda (LINK_P),y
    sbc #0
    sta SDT_ADRH,x
    ldy #DIB_UNIT
    lda (LINK_P),y
    sta SDT_UNIT,x
    ldy #DIB_DTYPE
    lda (LINK_P),y
    bpl ADEV_EXIT                   ; not a block device
    txa
    inc BLKDLST                     ; BLKDLST's first byte counts the block devices listed after it
    ldx BLKDLST
    cpx #<BLKD_SIZE
    bcc ADEV020
    ldx #ERR9X
    ldy #ERR9L
    jsr ERROR
ADEV020:
    sta BLKDLST,x
ADEV_EXIT:
    rts

;; Processes the kernel, interpreter and driver files: the loader's main work.
;;
;; In order, it:
;; - copies the boot ROM's disk locations ($0380-$039F) into SOS's zero page;
;; - moves the global page to $1900, sets <SYSBANK> and <MEMSIZE> from the bank the file was loaded in, and moves
;;   the kernel to $B800;
;; - copies the loader to bank 0 and switches to bank 0, freeing the system bank for the interpreter;
;; - sets up .D1, initializes the kernel (<INIT_KRNL>), shows the welcome screen, and checks the boot ROM;
;; - reads SOS.INTERP into banks 0 and 1, checks its label and size, and moves its code into the system bank;
;; - reads SOS.DRIVER the same way, moves its character set to $0C00 and keyboard table to $1700, and sets up the
;;   built-in drives it asks for;
;; - places the driver modules below the interpreter, from the last to the first, relocating, moving and linking
;;   each active one;
;; - initializes the kernel and all devices again, claims memory segments for the kernel, interpreter and drivers,
;;   sets the prefix to .D1, lets the console load the character set, and clears the screen.
;;
;; Any failure shows a message and stops (<ERROR>).
;; Uses:  A, X, Y, the loader's zero-page locations
;; See:   <SOSLDR>
SOSLDR1:
    ldx #$1F
LDR010:
    lda $380,x
    sta SZPAGE,x
    dex
    bpl LDR010
    lda #<LDR_ADR                   ; the global page: skip the loader to the next header
    sta WORK_P
    lda #>LDR_ADR
    sta WORK_P+1
    jsr ADVANCE
    lda B_REG
    jsr MOVE
    lda B_REG                       ; the boot loader put the file in the highest bank
    and #$0F
    sta SYSBANK
    asl a                           ; memory size in 16K units: two per bank, and 64K of fixed memory
    clc
    adc #4
    sta MEMSIZE
    jsr ADVANCE                     ; the kernel
    lda DST_P
    sta K_BASE
    lda DST_P+1
    sta K_BASE+1
    lda B_REG
    jsr MOVE
    lda #<($2000)                   ; copy $2000 to the loader's end into bank 0 ($8F:2000)
    sta SRC_P
    sta DST_P
    lda #>($2000)
    sta SRC_P+1
    sta DST_P+1
    lda #$8F
    sta CXPAGE+DST_P+1
    lda #<(LDREND-$2000)
    sta CNT
    lda #>(LDREND-$2000)
    sta CNT+1
    lda B_REG
    jsr MOVE
    lda #0                          ; and run in bank 0 from here on
    sta B_REG
    lda K_DRIVES
    jsr LINK_INIT
    jsr INIT_KRNL
    jsr WELCOME
    lda E_REG
    ora #$03                        ; switch the ROM in to check its revision
    sta E_REG
    lda ROM_ADR
    cmp #ROM_ID
    beq LDR020
    ldx #ERR7X
    ldy #ERR7L
    jsr ERROR
LDR020:
    lda E_REG
    and #$F6                        ; switch the ROM out, and keep RAM writable
    sta E_REG
    ldy I_PATH                      ; open SOS.INTERP
LDR030:
    lda I_PATH,y
    sta PATH,y
    dey
    bpl LDR030
    lda #<(LDREND-$2000)
    sta SYSBUF_P
    lda #>(LDREND-$2000)
    sta SYSBUF_P+1
    lda #$80
    sta CXPAGE+SYSBUF_P+1
    brk
    .byte OPEN
    .word OPEN_PARMS
    beq LDR040
    ldx #ERR1X
    ldy #ERR1L
    jsr ERROR
LDR040:
    lda OPEN_REF
    sta READ_REF
    sta CLOSE_REF
    lda #$80                        ; read all of it to $80:FILE, in banks 0 and 1
    sta CXPAGE+RDBUF_P+1
    lda #<FILE
    sta RDBUF_P
    lda #>FILE
    sta RDBUF_P+1
    brk
    .byte READ
    .word READ_PARMS
    beq LDR050
    ldx #ERR0X
    ldy #ERR0L
    jsr ERROR
LDR050:
    brk
    .byte CLOSE
    .word CLOSE_PARMS
    ldy #7                          ; check the label
LDR051:
    lda (RDBUF_P),y
    cmp I_LABEL,y
    bne LDR052
    dey
    bpl LDR051
    bmi LDR053
LDR052:
    ldx #ERR2X
    ldy #ERR2L
    jsr ERROR
LDR053:
    lda #<(I_HDR_CNT-2)             ; ADVANCE adds 4 more, skipping the label's last 2 bytes and the header count
    sta WORK_P
    lda #>(I_HDR_CNT-2)
    sta WORK_P+1
    lda #$80
    sta CXPAGE+WORK_P+1
    jsr ADVANCE
    lda DST_P
    sta I_BASE_P
    lda DST_P+1
    sta I_BASE_P+1
    lda #0
    sta CXPAGE+I_BASE_P+1
    clc                             ; the interpreter must end at or below the kernel
    lda CNT
    adc DST_P
    tax
    lda CNT+1
    adc DST_P+1
    cpx K_BASE
    sbc K_BASE+1
    beq LDR070
    bcc LDR070
    ldx #ERR3X
    ldy #ERR3L
    jsr ERROR
LDR070:
    lda SYSBANK
    jsr MOVE
    ldy D_PATH                      ; open SOS.DRIVER
LDR080:
    lda D_PATH,y
    sta PATH,y
    dey
    bpl LDR080
    brk
    .byte OPEN
    .word OPEN_PARMS
    beq LDR090
    ldx #ERR4X
    ldy #ERR4L
    jsr ERROR
LDR090:
    lda OPEN_REF
    sta READ_REF
    sta CLOSE_REF
    brk
    .byte READ
    .word READ_PARMS
    beq LDR100
    ldx #ERR0X
    ldy #ERR0L
    jsr ERROR
LDR100:
    brk
    .byte CLOSE
    .word CLOSE_PARMS
    ldy #$7                         ; check the label
LDR101:
    lda (RDBUF_P),y
    cmp D_LABEL,y
    bne LDR102
    dey
    bpl LDR101
    bmi LDR103
LDR102:
    ldx #ERR5X
    ldy #ERR5L
    jsr ERROR
LDR103:
    lda #<D_CHRSET                  ; the character set, to $0C00
    sta SRC_P
    lda #>D_CHRSET
    sta SRC_P+1
    lda #<($C00)
    sta DST_P
    lda #>($C00)
    sta DST_P+1
    lda #<($400)
    sta CNT
    lda #>($400)
    sta CNT+1
    lda #0
    jsr MOVE
    lda #<D_KYBD                    ; the keyboard table, to $1700
    sta SRC_P
    lda #>D_KYBD
    sta SRC_P+1
    lda #<($1700)
    sta DST_P
    lda #>($1700)
    sta DST_P+1
    lda #<($100)
    sta CNT
    lda #>($100)
    sta CNT+1
    lda #0
    jsr MOVE
    ldy #<(D_DRIVES-D_FILE)         ; the built-in drives the driver file asks for
    lda (RDBUF_P),y
    jsr LINK_INIT
    lda #0                          ; drivers go below the interpreter's page, and never above $A000
    sta CXPAGE+DST_P+1
    sta DST_P
    lda I_BASE_P+1
    sta DST_P+1
    cmp #$A0
    bcc LDR105
    lda #$A0
    sta DST_P+1
LDR105:
    lda SYSBANK
    sta DSTBANK
    jsr REVERSE
NEXTDRIVER:
    jsr DADVANCE
    bcs LDR140                      ; no modules left
    jsr FLAGS
    bvs NEXTDRIVER                  ; skip a module whose DIBs are all inactive
    jsr GETMEM
    jsr RELOC
    lda DSTBANK
    bmi LDR120                      ; ran out of banks
    lda CXPAGE+SRC_P+1              ; turn the source's extended address into a bank and an address in it
    and #$7F
    sta TEMP_BANK
    lda SRC_P+1
    bpl LDR110
    inc TEMP_BANK
LDR110:
    and #$7F
    clc
    adc #>($2000)
    sta TEMP_ADRH
    lda DST_P                       ; the module must not land below its source, over the modules still to go
    cmp SRC_P
    lda DST_P+1
    sbc TEMP_ADRH
    lda DSTBANK
    sbc TEMP_BANK
    bcs LDR130
LDR120:
    ldx #ERR6X
    ldy #ERR6L
    jsr ERROR
LDR130:
    lda DSTBANK
    jsr MOVE
    jsr LINK
    jmp NEXTDRIVER
LDR140:
    jsr INIT_KRNL                   ; again, now initializing every device
    jsr ALLOC_SEG
    jsr ALLOC_DSEG
    lda #0                          ; screen off while the character set loads, so it isn't seen changing
    sta SCRNMODE
    brk
    .byte SETPREFIX
    .word PREFX_PARMS
    cli                             ; the console driver loads the character set on interrupts
    lda #0                          ; clear both text pages, $0400-$0BFF, to spaces
    sta CXPAGE+SRC_P+1
    sta CXPAGE+DST_P+1
    lda #$04
    sta SRC_P+1
    sta DST_P+1
    lda #$00
    sta SRC_P
    lda #$80
    sta DST_P
    lda #$A0
    ldx #8
CLEAR0:
    ldy #$77                        ; the 120 bytes of each half page that show; the 8 after them are not screen
CLEAR1:
    sta (SRC_P),y
    sta (DST_P),y
    dey
    bpl CLEAR1
    inc SRC_P+1
    inc DST_P+1
    dex
    bne CLEAR0
WAIT:
    inc SRC_P                       ; 65,536 passes, long enough for the character set to finish loading
    bne WAIT
    inx
    bne WAIT
    lda #$80
    sta SCRNMODE
    rts
    .include "SosLdrE.asm"
