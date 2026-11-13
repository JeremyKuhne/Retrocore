;; The second part of the .PROFILE driver: the write request, the data transfer and the ProFile handshakes.

; ---------------------------------------------------------------------------------------------------------------------
; Write request
; ---------------------------------------------------------------------------------------------------------------------

;; The write request: writes whole blocks from the caller's buffer to the ProFile, verifying them when <WRTVER>
;; says so.
;;
;; A parity error retries the block twice; a refused or unanswered handshake resets the ProFile once.
;; In: SOS_BUF = the buffer, SOS_BYTES = the byte count, SOS_BLOCK = the first block
;; Uses: A, X, Y
;; See: <SNDCMD>, <DATRANS>
DWRITE:
    lda SOS_REQCODE
    sta a:PREVCMD
    lda SOS_UNIT
    sta a:PREVUNIT
    jsr GETBYTES
    jsr ARBADR
    lda #$FF
    sta a:DATDIR
WRBLOCK:
    lda #$02
    sta BLK_RTRYCNT
WPAR_RETRY:
    lda #$00
    sta CMD_RTRYCNT
    sta RTRYCNT
    sta RTRYTHRESH
    jsr TSTBLKNUM
    bcc WCOM_RETRY
    jmp DW_ERR2
WCOM_RETRY:
    lda #<WDGTWRT
    ldy a:WRTVER
    beq @L10
    lda #<WDGTWRTVER
@L10:
    sta a:Z8CMD
    lda #$01
    sta RSPNS
    jsr SNDCMD
    bcs DW_ERR1
    bne WCOM_RETRY
    jsr SND_CMDBYTES
    bcs @L12
    lda a:Z8CMD
    adc #$02
    sta RSPNS
    jsr SNDCMD
    bcs DW_ERR1
    bne WCOM_RETRY
    jsr DATRANS
    bcc @L15
@L12:
    jmp WRRETRY
@L15:
    lda #$06
    sta RSPNS
    lda a:WRTVER
    beq @L20
    lda #$FF
    sta a:LONGWAIT
@L20:
    jsr SNDCMD
    bcs DW_ERR1
    beq WCONT
    jsr RSTORADR
    jmp WCOM_RETRY
DW_ERR1:
    inc a:PIPPIN_RESET
    bne @L10
    jsr RESET_PIPPIN
    lda #$00
    sta CMD_RTRYCNT
    jmp WCOM_RETRY
@L10:
    jsr NOTCMDLN
LDAXIOERR:
    lda #<XIOERROR
CSYSER1:
    jmp BADEXIT
DW_ERR2:
    lda #<XBLKNUM
    bne CSYSER1
WCONT:
    jsr GETSTAT
    bcs WRRETRY
    bpl @L10
    inc a:COUNTR
    beq WRRETRY
    bne DW_ERR1
@L10:
    and #$41
    bne LDAXIOERR
    lda a:STATUS2
    and #$48
    bne LDAXIOERR
    jsr TSTMORE
    beq DW_EXIT
    jmp WRBLOCK
DW_EXIT:
    jmp GOODEXIT
WRRETRY:
    jsr RSTORADR
    dec BLK_RTRYCNT
    bmi DW_ERR1
    jmp WPAR_RETRY

; ---------------------------------------------------------------------------------------------------------------------
; Data transfer
; ---------------------------------------------------------------------------------------------------------------------

;; Moves a block's 512 bytes between the caller's buffer and the ProFile, and after a write sends the check bytes.
;;
;; A few bytes move one at a time (<MOVE>) where the buffer's alignment needs it, the rest by the ROM's pseudo-DMA
;; loop (<GO_DMA>) up to a page at a time, and <LAST_PGE> finishes the block.
;; In: DATDIR = 0 to read or $FF to write, the buffer as <ARBADR> sets it
;; Out: carry = set on a parity error, the buffer pointer past the block
;; Uses: A, X, Y
DATRANS:
    php
    sei
    lda #$02
    sta a:CNTHI
    lda #$00
    sta a:CNTLO
    bit a:DATDIR
    bmi @L010
    jsr SETUPREAD
    jmp @L020
@L010:
    jsr SETUPWRITE
@L020:
    lda E_REG
    and #$7F
    sta E_REG
    plp
    lda ADRLO
    beq DATADMA
    cmp #$F5
    bcc @L030
    eor #$FF
    jsr MOVIT
    jmp FASTMOV
@L030:
    and #$01
    beq @L040
    lda #$00
    sta a:MVCNT
    jsr MOVE
@L040:
    lda ADRLO
DATADMA:
    tax
    clc
    adc #$01
    and #$FE
    sta VECTLO
    txa
    eor #$FF
    sta a:MVCNT
    sta a:DMA_CNT
    jsr GO_DMA
    jsr ADJ_ADR
    lda a:CNTHI
    beq LAST_PGE
FASTMOV:
    lda #$00
    beq DATADMA
TRANSDNE:
    ldy #$00
    ldx a:SLOTX
    php
    sei
    lda E_REG
    ora #$80
    sta E_REG
    plp
    bit a:DATDIR
    bpl @L300
@L100:
    lda a:CHEKBYTS,y
    sta WR_PORT,x
    iny
    cpy #$06
    bne @L100
@L300:
    jsr CHKPARITY
    php
    sei
    jsr SETUPREAD
    jsr S2M
    plp
    rts

;; Moves what is left of the block after its whole pages: a short remainder a byte at a time, a longer one by the
;; pseudo-DMA loop, keeping bytes 0 and $FE of that page of the buffer intact.
;; In: CNTLO = the bytes left
;; Uses: A, X, Y
LAST_PGE:
    lda a:CNTLO
    beq TRANSDNE
    sec
    sbc #$01
    cmp #$20
    bcs @L20
    jsr MOVIT
    jmp TRANSDNE
@L20:
    pha
    lda #$01
    sta a:MVCNT
    jsr MOVE
    ldy #$00
    php
    sei
    lda (ADRLO),y
    sta a:TEMP00
    ldy #$FE
    lda (ADRLO),y
    sta a:TEMPFE
    pla
    tax
    pla
    and #$FC
    cmp #$84
    bne @L30
    sbc #$04
@L30:
    tay
    lsr a
    lsr a
    sbc #$01
    sta a:DMA_CNT
    txa
    pha
    tya
    sec
    sbc #$03
    sta a:MVCNT
    tay
    lda #$02
    sta VECTLO
    bit a:DATDIR
    bpl @L50
    lda (ADRLO),y
    ldy #$00
    sta (ADRLO),y
    ldy #$FE
    sta (ADRLO),y
@L50:
    jsr GO_DMA
    bit a:DATDIR
    bmi @L70
    ldy #$00
    bit a:MVCNT
    bmi @L60
    ldy #$FE
@L60:
    lda (ADRLO),y
    ldy a:MVCNT
    sta (ADRLO),y
@L70:
    ldy #$00
    lda a:TEMP00
    sta (ADRLO),y
    ldy #$FE
    lda a:TEMPFE
    sta (ADRLO),y
    plp
    jsr ADJ_ADR
    jmp LAST_PGE

;; Moves bytes a byte at a time, then advances the buffer past them.
;; In: A = the number of bytes minus one
;; Uses: A, X, Y
MOVIT:
    sta a:MVCNT
    jsr MOVE

;; Advances the buffer pointer and the count left past the bytes just moved, and works out the pseudo-DMA loop's
;; page and bank for the new address.
;; In: MVCNT = the bytes moved minus one, the buffer as <ARBADR> sets it
;; Out: CNTLO = the count left, ADRLO = the next address, ADDRDMA = its pseudo-DMA address, BANKDMA = its bank
;; Uses: A
;; Keeps: X, Y
ADJ_ADR:
    clc
    lda a:CNTLO
    sbc a:MVCNT
    sta a:CNTLO
    lda a:CNTHI
    sbc #$00
    sta a:CNTHI
    lda ADRLO
    adc a:MVCNT
    sta ADRLO
    lda ADRHI
    adc #$00
    sta ADRHI
    bit a:ADMODE
    bpl ADJ_DNE
    cmp #$81
    bcc ADJ_BNK
    and #$7F
    inc SISADR
ADJ_BNK:
    sta ADRHI
    lda SISADR
    sta a:BANKDMA
    lda ADRHI
    clc
    adc #$20
    cmp #$A0
    bcc ADJ_DNE
    and #$7F
    inc a:BANKDMA
ADJ_DNE:
    sta a:ADDRDMA
    rts

;; Moves bytes between the buffer and the ProFile a byte at a time, at 1 MHz with interrupts off.
;; In: MVCNT = the number of bytes minus one, DATDIR = 0 to read or $FF to write, ADRLO/ADRHI = the buffer
;; Uses: A, X, Y
MOVE:
    php
    sei
    ldx a:SLOTX
    ldy #$00
    lda E_REG
    ora #$80
    sta E_REG
    bit a:DATDIR
    bpl MOVIN
MOVOUT:
    lda (ADRLO),y
    sta WR_PORT,x
    cpy a:MVCNT
    beq MVDONE
    iny
    bne MOVOUT
MOVIN:
    lda RD_PORT,x
    sta (ADRLO),y
    cpy a:MVCNT
    beq MVDONE
    iny
    bne MOVIN
MVDONE:
    jsr S2M
    plp
    rts

;; Sets up the buffer pointer from SOS's buffer address and works out the page and bank the pseudo-DMA loop sees.
;;
;; An extension byte with bit 7 clear means the current bank; otherwise its low four bits pick the bank, and $8F
;; counts as an ordinary address in bank 0.
;; In: SOS_BUF = the buffer, its extension byte
;; Out: ADRLO = the buffer's address, ORGADR = the same, ORGBNK = its bank, ADDRDMA = its pseudo-DMA address,
;;   BANKDMA = its bank, ADMODE = the addressing mode
;; Uses: A
;; Keeps: X, Y
ARBADR:
    lda SOS_BUF
    sta ADRLO
    sta a:ORGADR
    lda SOS_BUF+$01
    sta ADRHI
    sta a:ORGADR+$01
    sta a:ADDRDMA
    lda SOS_XPAGE+SOS_BUF+$01
    sta SISADR
    sta a:ORGBNK
    sta a:ADMODE
    bpl NOBANK
    and #$0F
    sta a:BANKDMA
    eor #$0F
    beq BANK0
    lda SOS_BUF+$01
    bpl @L010
    and #$7F
    inc a:BANKDMA
@L010:
    clc
    adc #$20
    sta a:ADDRDMA
    rts
NOBANK:
    lda BANK_REG
    and #$0F
BANK0:
    sta a:BANKDMA
    sta a:ADMODE
    rts

;; Runs the ROM's pseudo-DMA loop through the copy of <RELCODE>, with interrupts off and the zero-page register on
;; the buffer's page.
;; In: ADDRDMA = the page, BANKDMA = the bank, DMA_CNT = the count, VECTLO = where to enter the loop
;; Uses: A, X, Y
GO_DMA:
    php
    sei
    lda E_REG
    pha
    and #$24
    ora #$8B
    sta E_REG
    lda a:ADDRDMA
    sta Z_REG
    ldx a:BANKDMA
    lda a:DMA_CNT
    sec
    jsr DO_DMA
    pla
    sta E_REG
    lda #<SOS_ZPAGE
    sta Z_REG
    plp
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Handshakes
; ---------------------------------------------------------------------------------------------------------------------

;; Makes a CMD-BSY handshake and checks the ProFile's response, refusing a wrong one.
;; In: RSPNS = the response expected
;; Out: carry = set on a timeout or after a second refusal, zero = clear after a first refusal (to retry), else set
;; Uses: A, X, Y
SNDCMD:
    php
    sei
    lda E_REG
    ora #$80
    sta E_REG
    plp
    jsr WAITBSYLO
    bcs SENDERR
    jsr SETCMDLN
    jsr WAITBSYHI
    bcs SENDERR
    ldy RD_PORT,x
    cpy RSPNS
    beq CONT
    lda #$02
    sta a:BAD_RESPONSE
    ora a:STATUS3
    sta a:STATUS3
    lda #$AA
    jsr BSYACK
    bcs SENDERR
    inc CMD_RTRYCNT
    ldy CMD_RTRYCNT
    cpy #$02
    bcs SENDERR
    rts
CONT:
    lda #$55
    jsr BSYACK
    bcs SENDERR
    lda #$00
SENDERR:
    rts

;; Waits for BSY high, about half a second at most.
;; Out: carry = set on a timeout, X = the slot times 16
;; Uses: A, Y
WAITBSYHI:
    ldy #$00
    sty TIMOUT
    clc
    ldx a:SLOTX
ALOOP:
    lda BUSY,x
    bpl BSYHIRET
    dey
    bne ALOOP
    dec TIMOUT
    bne ALOOP
    sec
BSYHIRET:
    rts

;; Waits for BSY low, the ProFile ready, about half a second at most, or 16 times longer when <LONGWAIT> is set.
;; Out: carry = set on a timeout, X = the slot times 16
;; Uses: A, Y
WAITBSYLO:
    ldy #$01
    lda a:LONGWAIT
    beq @L10
    ldy #$10
@L10:
    sty a:WAITTIME
    ldy #$00
    sty TIMOUT
    clc
    ldx a:SLOTX
BLOOP:
    lda BUSY,x
    bmi BSYLORET
    dey
    bne BLOOP
    dec TIMOUT
    bne BLOOP
    dec a:WAITTIME
    bne BLOOP
    sec
BSYLORET:
    rts

;; Sends the six command bytes: the command, the block number, the retry count and the sparing threshold.
;; In: X = the slot times 16
;; Out: carry = set on a parity error
;; Uses: A, X, Y
SND_CMDBYTES:
    jsr SETUPWRITE
    lda a:Z8CMD
    sta WR_PORT,x
    lda a:MSBLOCK
    sta WR_PORT,x
    lda BLOCKHI
    sta WR_PORT,x
    lda BLOCKLO
    sta WR_PORT,x
    lda RTRYCNT
    sta WR_PORT,x
    lda RTRYTHRESH
    sta WR_PORT,x
    jsr SETUPREAD
    jsr CHKPARITY
    rts

;; Reads the ProFile's four status bytes into <STATUS1>-<STATUS4>, the driver's flags ORed into the third.
;; Out: A = the first status byte, negative = its bit 7, carry = set on a parity error
;; Uses: A, X
;; Keeps: Y
GETSTAT:
    ldx a:SLOTX
    php
    sei
    lda E_REG
    ora #$80
    sta E_REG
    plp
    lda RD_PORT,x
    sta a:STATUS1
    lda RD_PORT,x
    sta a:STATUS2
    lda RD_PORT,x
    pha
    lda RD_PORT,x
    sta a:STATUS4
    jsr CHKPARITY
    pla
    ora a:PARITY_ERR
    ora a:BAD_RESPONSE
    ora a:RESET_FLAG
    sta a:STATUS3
    lda a:STATUS1
    rts

;; Checks for a parity error, records one in <PARITY_ERR> and <STATUS3>, clears it, and returns to 2 MHz.
;; Out: carry = set on a parity error, X = the slot times 16
;; Uses: A
;; Keeps: Y
CHKPARITY:
    ldx a:SLOTX
    lda BUSY,x
    sta CLR_PARITY,x
    asl a
    asl a
    bcc @L10
    lda #$01
    sta a:PARITY_ERR
    ora a:STATUS3
    sta a:STATUS3
@L10:
    jmp S2M

;; Sets the card up to write to the ProFile, at 1 MHz.
;; Uses: A, Y
;; Keeps: X
SETUPWRITE:
    ldy #<SETWRT
    php
    sei
    lda E_REG
    ora #$80
    sta E_REG
    plp
    lda (INDRCN),y

;; Sets the card's port to write.
;; Uses: A, Y
;; Keeps: X
SET_WRITEDIR:
    ldy #<RWLO
    lda (INDRCN),y
    rts

;; Sets the card up to read from the ProFile, at 1 MHz.
;; Uses: A, Y
;; Keeps: X
SETUPREAD:
    ldy #<SETRD
    php
    sei
    lda E_REG
    ora #$80
    sta E_REG
    plp
    lda (INDRCN),y
    ldy #<RWHI
    lda (INDRCN),y
    rts

;; Ends a handshake: sends the answer, drops CMD and waits for BSY low.
;; In: A = $55 to go on or $AA to refuse, X = the slot times 16
;; Out: carry = set on a timeout
;; Uses: A, X, Y
BSYACK:
    sta WR_PORT,x
    jsr SET_WRITEDIR
    jsr NTCMDLN1
    jsr WAITBSYLO
    jsr SETUPREAD
    jmp S2M

;; Sets the card up to read and drops CMD.
;; Uses: A, Y
;; Keeps: X
NOTCMDLN:
    jsr SETUPREAD

;; Drops CMD.
;; Uses: A, Y
;; Keeps: X
NTCMDLN1:
    ldy #<NOTCMD
    lda (INDRCN),y
    rts

;; Sets the card up to read and raises CMD.
;; Uses: A, Y
;; Keeps: X
SETCMDLN:
    jsr SETUPREAD
    ldy #<SETCMD
    lda (INDRCN),y
    rts

;; Resets the ProFile with the card's reset line and records the reset in <STATUS3>.
;; Uses: A, Y
;; Keeps: X
RESET_PIPPIN:
    lda #$04
    sta a:RESET_FLAG
    ora a:STATUS3
    sta a:STATUS3
    ldy #<RST
    php
    sei
    lda E_REG
    ora #$80
    sta E_REG
    plp
    lda (INDRCN),y
    ldy #$25
@L10:
    dey
    bne @L10
    ldy #<CLRRST
    lda (INDRCN),y
    jmp S2M
