;; The first part of the .PROFILE driver: its comment record and device information block, the names it uses, its
;; variables, the main entry point and the initialize, status, control, repeat and read requests.

;; The driver's comment record, which SOS.DRIVER keeps apart from the code: $FFFF, the text's length and the text.
DRIVER_COMMENT:
    .word $FFFF
    .word DRIVER_COMMENT_END - DRIVER_COMMENT - 4
    .byte "Profile Driver -- "
    .byte "Copyright (C) 1983 by Apple Computer Inc."
DRIVER_COMMENT_END:
    .logicalorg * - (DRIVER_COMMENT_END - DRIVER_COMMENT)

; ---------------------------------------------------------------------------------------------------------------------
; Device information block
; ---------------------------------------------------------------------------------------------------------------------

;; The device information block of .PROFILE, the driver's one device: no next block, the entry point, the name,
;; the device number, slot and unit, the type and subtype, the block count, the manufacturer, the release and the
;; size of the configuration block that follows.
DIB_LINK1:
    .word $00
DIB_ENTRY1:
    .word MAIN
DIB_NAME1:
    .byte $08
    .byte ".PROFILE"
    .res $07, $00
;; The device number byte: $80, active, with no need for page-aligned buffers.
DIB_DNUM1:
    .byte $80
;; The slot of the ProFile interface card. Apple's listing has $FF, no slot; the System Configuration Program set
;; slot 4 in the System Utilities disk's copy, which this follows.
DIB_SLOT1:
    .byte $04
DIB_UNIT1:
    .byte $00
DIB_TYPE1:
    .byte DEVTYPE
DIB_SUBTYPE1:
    .byte SUBTYPE
    .byte $00
;; The number of blocks the device has; reads and writes past it fail.
DIB_BLOCK1:
    .word MAXBLOCK
DIB_MID1:
    .word MANUF
DIB_RLS1:
    .word RELEASE
DIB_DCBCNT1:
    .word $01
;; The configuration block's one byte: nonzero to verify each write (command 2), zero for plain writes (command 1).
WRTVER:
    .byte $FF

; ---------------------------------------------------------------------------------------------------------------------
; SOS names
; ---------------------------------------------------------------------------------------------------------------------

;; Kernel entry: claims system interrupt resources. A = the table's length, X/Y = its address.
ALLOCSIR = $1913
;; Kernel entry: gives system interrupt resources back.
DEALCSIR = $1916
;; Kernel entry: selects a slot's $C800 expansion space, A = the slot, or deselects it with A = 0; carry = set on
;; failure.
SELC800 = $1922
;; Kernel entry: reports the error code in A to the caller of the driver and does not return.
SYSERR = $1928
;; Where <RELCODE> runs: $18F0, reached as $F0 in the kernel's zero page.
DO_DMA = $18F0
;; <DO_DMA> as the zero-page address the copy is stored through.
INDDMA = $F0
;; The low byte of the JSR's target in the copy of <RELCODE>, set to enter the ROM's pseudo-DMA loop partway.
VECTLO = DO_DMA+$07
;; The kernel's zero page, $18, restored in the zero-page register after a pseudo-DMA transfer.
SOS_ZPAGE = $18

XREQCODE = $20                      ;; Error: bad request code.
XCTLCODE = $21                      ;; Error: bad control or status code.
XNORESRC = $25                      ;; Error: the slot's interrupt resource is taken.
XBADOP = $26                        ;; Error: bad operation.
XIOERROR = $27                      ;; Error: an I/O error.
XNODRIVE = $28                      ;; Error: no ProFile, or no card in the slot.
XNOWRITE = $2B                      ;; Error: write-protected; the driver never returns it.
XBYTECNT = $2C                      ;; Error: the byte count is not a multiple of 512, or runs past the last block.
XBLKNUM = $2D                       ;; Error: the block number is past the last block.
BADOLDDATA = $27                    ;; Error: the block held bad data; the driver never returns it.
SPTBLOVFLW = $27                    ;; Error: the spare table is full; the driver never returns it.

; ---------------------------------------------------------------------------------------------------------------------
; Hardware
; ---------------------------------------------------------------------------------------------------------------------

BANK_REG = $FFEF                    ;; The bank register: which bank is at $2000-$9FFF.
E_REG = $FFDF                       ;; The environment register; bit 7 = 1 MHz.
Z_REG = $FFD0                       ;; The zero-page register.
PSUEDO_DMA = $F800                  ;; The ROM's pseudo-DMA loop.
WR_PORT = $C080                     ;; Card, plus slot*16: writes a byte to the ProFile.
RD_PORT = $C081                     ;; Card, plus slot*16: reads a byte from the ProFile.
BUSY = $C082                        ;; Card, plus slot*16: bit 7 = BSY low, bit 6 = parity error, bit 0 = no drive.
CLR_PARITY = $C083                  ;; Card, plus slot*16: a write clears the parity error.

; The card's $CN00 locations, read through (<INDRCN>),Y: each switches one of its lines.
NOTCMD = $00                        ;; CMD low.
SETCMD = $04                        ;; CMD high.
SETWRT = $01                        ;; The card's direction line low, for writing.
SETRD = $05                         ;; The card's direction line high, for reading.
INTDSABL = $02                      ;; The card's interrupts off.
INTENABL = $06                      ;; The card's interrupts on.
RWLO = $03                          ;; The port's read/write line low, for writing.
RWHI = $07                          ;; The port's read/write line high, for reading.
RST = $0C                           ;; The ProFile's reset line on.
CLRRST = $08                        ;; The ProFile's reset line off.

WDGTRD = $00                        ;; ProFile command: read a block.
WDGTWRTVER = $02                    ;; ProFile command: write a block and verify it.
WDGTSTAT = $03                      ;; ProFile command: status; the driver does not send it.
WDGTWRT = $01                       ;; ProFile command: write a block.

; ---------------------------------------------------------------------------------------------------------------------
; Variables
; ---------------------------------------------------------------------------------------------------------------------

;; The address of <SIRTABLE>, for <ALLOCSIR>.
SIRADDR:
    .word SIRTABLE
;; The interrupt resource the driver claims: number $10 plus the slot (added by <DINIT>), with no handler.
SIRTABLE:
    .byte $10, $00
    .word $00
SIRBANK:
    .byte $00
;; The length of <SIRTABLE>.
SIRCOUNT = *-SIRTABLE
;; The slot times 16, for indexing the card's $C08x locations.
SLOTX:
    .byte $00
ERROR:
    .byte $00
;; The error the initialize request ran into, reported by every later request; 0 for none.
IERROR:
    .byte $00
;; The last read or write request code, for <DREPEAT>.
PREVCMD:
    .byte $00
;; The unit of the last read or write, for <DREPEAT>.
PREVUNIT:
    .byte $00
;; The number of blocks left in the request.
LENGTH:
    .byte $00
;; The buffer address of the block in progress, for a retry (<RSTORADR>).
ORGADR:
    .word $00
;; The buffer's extension byte for the block in progress.
ORGBNK:
    .byte $00
;; The card's page, $CN, once initialized; 0 before.
SLOTCN:
    .byte $00
;; The buffer's page as the pseudo-DMA loop sees it, with its bank in <BANKDMA>.
ADDRDMA:
    .byte $00
;; The bank to switch in for the pseudo-DMA loop.
BANKDMA:
    .byte $00
TEMP00:
    .byte $00
TEMPFE:
    .byte $00
;; The number of bytes to move, minus one.
MVCNT:
    .byte $00
;; The bytes of the block left to move, low byte.
CNTLO:
    .byte $00
;; The bytes of the block left to move, high byte.
CNTHI:
    .byte $00
;; Bit 7 set when the buffer is in extended (banked) memory.
ADMODE:
    .byte $00
;; The direction of the transfer: 0 to read, $FF to write.
DATDIR:
    .byte $00
;; The command to send the ProFile.
Z8CMD:
    .byte $00
;; Counts up from $FF: status with bit 7 set is retried once a call.
COUNTR:
    .byte $00
;; The block number's high byte for the ProFile: $FF for SOS blocks $FFFE and $FFFF, otherwise 0.
MSBLOCK:
    .byte $00
;; Nonzero once the driver has seen BSY low, the ProFile ready.
BSYLO:
    .byte $00
;; Nonzero to wait 16 times longer for BSY low, while the ProFile reads or writes.
LONGWAIT:
    .byte $00
WAITTIME:
    .byte $00
;; Counts up from $FF; the first failed handshake resets the ProFile, a later one is an I/O error.
PIPPIN_RESET:
    .byte $00
;; The ProFile's four status bytes from the last transfer, which status request 1 returns; the driver ORs its own
;; flags into the third: bit 0 a parity error, bit 1 a refused response, bit 2 a reset.
STATUS1:
    .byte $00
STATUS2:
    .byte $00
STATUS3:
    .byte $00
STATUS4:
    .byte $00
PARITY_ERR:
    .byte $00
RESET_FLAG:
    .byte $00
BAD_RESPONSE:
    .byte $00
;; The six check bytes sent after the data of a write: 0 and the block number, then their complements.
CHEKBYTS:
    .word $00
    .word $00
    .word $00
;; The environment register as the caller had it, with the screen bit clear.
SVENV:
    .byte $00
;; The page count passed to the pseudo-DMA loop.
DMA_CNT:
    .byte $00

; SOS's driver parameters.
SOS_REQCODE = $C0                   ;; The request code.
SOS_UNIT = $C1                      ;; The unit.
SOS_BUF = $C2                       ;; Read or write: the buffer's address.
SOS_BYTES = $C4                     ;; Read or write: the byte count.
SOS_BLOCK = $C6                     ;; Read or write: the first block.
SOS_BYTRD = $C8                     ;; Read: where to put the count of bytes read.
SOS_STCODE = $C2                    ;; Status or control: the code.
SOS_STLIST = $C3                    ;; Status or control: the list's address.
SOS_XPAGE = $1400                   ;; The extension page of the kernel's zero page.

; The driver's zero-page locations.
ADRLO = $CA                         ;; The buffer pointer.
ADRHI = ADRLO+$01
SISADR = SOS_XPAGE+ADRHI            ;; The buffer pointer's extension byte.
INDRCN = $CC                        ;; A pointer to the card's $CN00 locations.
SISCN = SOS_XPAGE+INDRCN+$01        ;; Its extension byte, 0.
TIMOUT = $CE                        ;; The timeout's high count.
RTRYCNT = $CF                       ;; The retry count sent with a command.
RTRYTHRESH = $D0                    ;; The sparing threshold sent with a command.
CMD_RTRYCNT = $D1                   ;; The refused handshakes so far.
RSPNS = $D2                         ;; The response the next handshake expects.
BLK_RTRYCNT = $D3                   ;; The parity-error retries left for the block.
BLOCKLO = $D4                       ;; The block in progress, low byte.
BLOCKHI = $D5                       ;; The block in progress, high byte.

; ---------------------------------------------------------------------------------------------------------------------
; Main entry point
; ---------------------------------------------------------------------------------------------------------------------

;; Calls the ROM's pseudo-DMA loop with another bank switched in; <MAIN> copies it to <DO_DMA>.
;; In: X = the bank, others as the loop takes them
;; Uses: A, Y
RELCODE:
    ldy BANK_REG
    stx BANK_REG
    jsr PSUEDO_DMA
    sty BANK_REG
    rts
;; The length of <RELCODE>.
CDELEN = *-RELCODE

;; The driver's entry point: does the request in SOS's driver parameters and returns to SOS.
;;
;; Except for the initialize request, it reports an earlier initialize error, selects the card's $C800 space and
;; checks that a ProFile answers. It copies <RELCODE> into place, and for the call slows the machine to 1 MHz.
;; In: SOS_REQCODE = the request, its parameters at $C1-$C9
;; Uses: A, X, Y
;; See: <DISPATCH>
MAIN:
    lda E_REG
    and #$DF
    sta a:SVENV
    lda SOS_REQCODE
    eor #$08
    beq INIT_ENT
    lda a:DIB_SLOT1
    jsr SELC800
    bcc @L20
    jmp NODRV
@L20:
    lda a:IERROR
    beq ONEMEG
    jsr SYSERR
INIT_ENT:
    sta a:SLOTCN
ONEMEG:
    lda #$FF
    sta a:PIPPIN_RESET
    sta a:COUNTR
    ldx #<(CDELEN-$01)
MOVCODE:
    lda a:RELCODE,x
    sta INDDMA,x
    dex
    bpl MOVCODE
    lda #$00
    sta a:PARITY_ERR
    sta a:BAD_RESPONSE
    sta a:RESET_FLAG
    sta INDRCN
    sta SISCN
    lda SOS_BLOCK
    sta BLOCKLO
    lda SOS_BLOCK+$01
    sta BLOCKHI
    ldx a:SLOTX
    php
    sei
    lda E_REG
    ora #$83
    sta E_REG
    plp
    lda a:SLOTCN
    bpl GO_INIT
    sta INDRCN+$01
    sta CLR_PARITY,x
    ldy BUSY,x
    jsr S2M
    tya
    and #$01
    bne NODRV
    tya
    bpl @L40
    lda #$FF
    sta a:BSYLO
    bne GO_INIT
@L40:
    lda a:BSYLO
    bne GO_INIT
    jsr RSTORENV
    lda #<XIOERROR
    jsr SYSERR
GO_INIT:
    jsr DISPATCH
    jsr SETUPWRITE
    lda #$00
    jsr SELC800
    ; Falls into RSTORENV.

;; Puts the environment register back as the caller had it, but for the screen bit, which it leaves.
;; Uses: A
;; Keeps: X, Y
RSTORENV:
    php
    sei
    lda E_REG
    and #$20
    ora a:SVENV
    sta E_REG
    plp
    rts

;; Returns the machine to 2 MHz.
;; Uses: A
;; Keeps: X, Y
S2M:
    php
    sei
    lda E_REG
    and #$7F
    sta E_REG
    plp
    rts

;; Jumps to the request's routine in <SW_TABLE>, or reports a bad request code.
;; In: SOS_REQCODE = the request
DISPATCH:
    SWITCH SOS_REQCODE, $09, SW_TABLE
;; Reports a bad request code.
BADREQ:
    lda #<XREQCODE
    jsr SYSERR
;; Reports a bad operation.
BADOP:
    lda #<XBADOP
    jsr SYSERR
;; Restores the environment and reports that no ProFile answered.
NODRV:
    jsr RSTORENV
    lda #<XNODRIVE
SYS_ERROR:
    jsr SYSERR
;; The requests' routines, minus one, by request code.
SW_TABLE:
    .word DREAD-$01
    .word DWRITE-$01
    .word DSTATUS-$01
    .word FDCONTROL-$01
    .word BADREQ-$01
    .word BADREQ-$01
    .word BADOP-$01
    .word BADOP-$01
    .word DINIT-$01
    .word DREPEAT-$01

; ---------------------------------------------------------------------------------------------------------------------
; Initialize, status, control and repeat requests
; ---------------------------------------------------------------------------------------------------------------------

;; The initialize request: sets up the slot's addresses, claims its interrupt resource and turns off the card's
;; interrupts.
;; In: DIB_SLOT1 = the slot
;; Out: carry = clear; errors are kept in <IERROR> and reported
;; Uses: A, X, Y
DINIT:
    lda a:DIB_SLOT1
    tax
    bmi DI_ERR1
    ora #$C0
    sta a:SLOTCN
    sta INDRCN+$01
    asl a
    asl a
    asl a
    asl a
    sta a:SLOTX
    lda #$00
    sta INDRCN
    sta SISCN
    lda a:DIB_SLOT1
    clc
    adc a:SIRTABLE
    sta a:SIRTABLE
    lda #<SIRCOUNT
    ldx a:SIRADDR
    ldy a:SIRADDR+$01
    jsr ALLOCSIR
    bcs DI_ERR2
    lda a:DIB_SLOT1
    jsr SELC800
    bcs DI_ERR1
    jsr SETUPREAD
    ldy #<INTDSABL
    lda (INDRCN),y
    jsr SETUPWRITE
    jsr SETUPREAD
    clc
    rts
DI_ERR1:
    lda #<XNODRIVE
    bne DI_ERR3
DI_ERR2:
    lda #<XNORESRC
DI_ERR3:
    sta a:IERROR
    jsr SYSERR

;; The status request: code 0 gives a byte with bit 7 = busy and bit 4 = online, code 1 the four status bytes
;; from the last transfer, and code $FE gives $FFFF.
;; In: SOS_STCODE = the code, SOS_STLIST = where to put the answer
;; Out: carry = clear
;; Uses: A, X, Y
DSTATUS:
    ldy #$00
    ldx SOS_STCODE
    bne @L10
    ldx a:SLOTX
    php
    sei
    lda E_REG
    ora #$80
    sta E_REG
    plp
    lda BUSY,x
    eor #$80
    asl a
    php
    asl a
    asl a
    asl a
    asl a
    and #$20
    plp
    ror a
    sta (SOS_STLIST),y
    rts
@L10:
    dex
    bne FORMATUS
    ldy #$03
@L15:
    lda a:STATUS1,y
    sta (SOS_STLIST),y
    dey
    bpl @L15
    clc
    rts
FORMATUS:
    lda SOS_STCODE
    cmp #$FE
    bne FCODE
    ldy #$00
    lda #$FF
    sta (SOS_STLIST),y
    iny
    sta (SOS_STLIST),y
    clc
    rts
;; Reports a bad control or status code.
FCODE:
    lda #<XCTLCODE
    jsr SYSERR

;; The control request: accepts codes 0 (reset) and $FE (format), which have nothing to do.
;; In: SOS_STCODE = the code
;; Out: carry = clear
;; Uses: A
FDCONTROL:
    lda SOS_STCODE
    beq @L010
    cmp #$FE
    bne FCODE
@L010:
    clc
    rts

;; The repeat request: does the last read or write again, with the new parameters, when it was to the same unit.
;; In: SOS_UNIT = the unit
;; Uses: A, X, Y
DREPEAT:
    lda a:PREVUNIT
    cmp SOS_UNIT
    bne @L1
    lda a:PREVCMD
    sta SOS_REQCODE
    bne @L2
    jmp DREAD
@L2:
    cmp #$02
    bcs @L1
    jmp DWRITE
@L1:
    jmp BADOP

; ---------------------------------------------------------------------------------------------------------------------
; Read request
; ---------------------------------------------------------------------------------------------------------------------

;; Checks the block in progress and sets the high byte of its ProFile block number.
;;
;; SOS blocks $FFFE and $FFFF stand for the ProFile's own blocks $FFFFFE and $FFFFFF.
;; In: BLOCKLO/BLOCKHI = the block
;; Out: carry = clear when the block is below <DIB_BLOCK1> or is $FFFE or $FFFF, MSBLOCK = $FF for those two
;; Uses: A
;; Keeps: X, Y
TSTBLKNUM:
    lda #$FF
    sta a:MSBLOCK
    cmp BLOCKHI
    clc
    bne @L10
    lda BLOCKLO
    cmp #$FE
    bcc @L10
    clc
    rts
@L10:
    inc a:MSBLOCK
    lda BLOCKLO
    cmp a:DIB_BLOCK1
    lda BLOCKHI
    sbc a:DIB_BLOCK1+$01
    rts

;; Checks a read or write request's blocks, sets the number to move, and makes the first block's check bytes.
;;
;; A zero byte count returns from the caller, the request done. A bad first block reports a bad block number;
;; a byte count that is not a multiple of 512, or that runs past the last block, a bad byte count.
;; In: SOS_BYTES = the byte count, BLOCKLO/BLOCKHI = the first block
;; Out: LENGTH = the number of blocks, CHEKBYTS = the first block's check bytes
;; Uses: A, X, Y
GETBYTES:
    jsr TSTBLKNUM
    bcc @L01
    pla
    pla
    lda #<XBLKNUM
    jsr SYSERR
@L01:
    lda SOS_BYTES
    bne @L10
    lda SOS_BYTES+$01
    lsr a
    bcs @L10
    sta a:LENGTH
    bne @L05
    pla
    pla
    rts
@L05:
    ldx BLOCKHI
    ldy BLOCKLO
    sec
    sbc #$01
    clc
    adc BLOCKLO
    sta BLOCKLO
    lda BLOCKHI
    adc #$00
    bcs @L10
    sta BLOCKHI
    jsr TSTBLKNUM
    stx BLOCKHI
    sty BLOCKLO
    bcc CALCHEK
@L10:
    pla
    pla
    lda #<XBYTECNT
    jsr SYSERR

;; Makes a block's six check bytes in <CHEKBYTS>.
;; In: X = the block's high byte, Y = its low byte
;; Uses: A
;; Keeps: X, Y
CALCHEK:
    tya
    sta a:CHEKBYTS+$02
    eor #$FF
    sta a:CHEKBYTS+$05
    txa
    sta a:CHEKBYTS+$01
    eor #$FF
    sta a:CHEKBYTS+$04
    lda #$00
    sta a:CHEKBYTS
    lda #$FF
    sta a:CHEKBYTS+$03
    rts

;; The read request: reads whole blocks from the ProFile into the caller's buffer.
;;
;; A parity error retries the block twice; a refused or unanswered handshake resets the ProFile once.
;; In: SOS_BUF = the buffer, SOS_BYTES = the byte count, SOS_BLOCK = the first block, SOS_BYTRD = where to put
;;   the count of bytes read
;; Uses: A, X, Y
;; See: <SNDCMD>, <DATRANS>
DREAD:
    lda #$00
    tay
    sta (SOS_BYTRD),y
    iny
    sta (SOS_BYTRD),y
    lda SOS_UNIT
    sta a:PREVUNIT
    lda SOS_REQCODE
    sta a:PREVCMD
    jsr GETBYTES
    jsr ARBADR
RDBLOCK:
    lda #$02
    sta BLK_RTRYCNT
RPAR_RETRY:
    lda #$00
    sta a:DATDIR
    sta CMD_RTRYCNT
    lda #$0A
    sta RTRYCNT
    lda #$03
    sta RTRYTHRESH
    jsr TSTBLKNUM
    bcc RCOM_RETRY
    lda #<XBLKNUM
    jsr SYSERR
RCOM_RETRY:
    lda #$00
    sta a:LONGWAIT
    lda #<WDGTRD
    sta a:Z8CMD
    lda #$01
    sta RSPNS
    jsr SNDCMD
    bcc @L70
    jmp DR_ERR1
@L70:
    bne RCOM_RETRY
    jsr SND_CMDBYTES
    bcs RDRETRY
    lda #$02
    sta RSPNS
    lda #$FF
    sta a:LONGWAIT
    jsr SNDCMD
    bcs DR_ERR1
    bne RCOM_RETRY
    jsr GETSTAT
    bcs RDRETRY
    bpl @L10
    inc a:COUNTR
    beq RCOM_RETRY
    bne DR_ERR1
@L10:
    jsr DATRANS
    bcs RDRETRY
    lda a:STATUS1
    and #$01
    bne LDAXIO
    lda a:STATUS2
    and #$58
    bne LDAXIO
    lda #$02
    ldy #$01
    adc (SOS_BYTRD),y
    sta (SOS_BYTRD),y
    jsr TSTMORE
    beq GOODEXIT
    jmp RDBLOCK
RDRETRY:
    jsr RSTORADR
    dec BLK_RTRYCNT
    bmi DR_ERR1
    jmp RPAR_RETRY
DR_ERR1:
    inc a:PIPPIN_RESET
    bne @L10
    jsr RESET_PIPPIN
    lda #$00
    sta CMD_RTRYCNT
    jmp RCOM_RETRY
@L10:
    jsr NOTCMDLN
LDAXIO:
    lda #<XIOERROR
    bne BADEXIT

;; Moves on to the next block: counts it off, makes its check bytes and keeps its buffer address for retries.
;; Out: zero = set when no blocks are left
;; Uses: A, X, Y
TSTMORE:
    inc BLOCKLO
    bne @L010
    inc BLOCKHI
@L010:
    ldy BLOCKLO
    ldx BLOCKHI
    jsr CALCHEK
    lda ADRHI
    sta a:ORGADR+$01
    lda SISADR
    sta a:ORGBNK
    dec a:LENGTH
    rts

;; Ends a read or write: one more handshake and command $FF, so the ProFile finishes any update to its spare
;; table, then raises and drops CMD.
;; Uses: A, X, Y
GOODEXIT:
    lda #$01
    sta RSPNS
    jsr SNDCMD
    lda #$FF
    sta a:Z8CMD
    jsr SND_CMDBYTES
    jsr SETCMDLN
    jsr SETCMDLN
    jsr NTCMDLN1
    rts

;; Ends a read or write as <GOODEXIT> does, then reports an error.
;; In: A = the error code
BADEXIT:
    pha
    jsr GOODEXIT
    pla
    jsr SYSERR

;; Points the buffer back at the start of the block in progress, for a retry.
;; Uses: A
;; See: <ARBADR>
RSTORADR:
    lda a:ORGADR
    sta SOS_BUF
    lda a:ORGADR+$01
    sta SOS_BUF+$01
    lda a:ORGBNK
    sta SOS_XPAGE+SOS_BUF+$01
    jmp ARBADR
