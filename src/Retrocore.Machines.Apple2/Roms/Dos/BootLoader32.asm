;; DOS 3.2: THE BOOT LOADER
;;
;; The two pages before RWTS, $B600-$B7FF where DOS runs ($3600-$37FF in the master image), hold the stages of
;; a boot that come after the Disk II's ROM, and the code that writes DOS to a disk for INIT. The boot chain:
;;
;; - BOOT 0, the 13-sector controller's ROM at $Cn00 (Boot13.asm, docs/DiskII.md), reads track 0 sector 0 into
;;   $0300, rebuilds its bytes from the 5-and-3 nibbles, and jumps to $0301 with X = slot * 16. Its sector
;;   reader, READ at $Cn5D, can be called again: it reads the sector in $3D into the page in $27 and $0800 as
;;   five-bit values, without making bytes of them, and returns.
;; - BOOT 1 is that sector, the page at TRK0LDR. Running at $0300, it calls READ for track 0 sectors 0 to 9 and
;;   decodes each into a page, from $B600 up to $BFFF (the master: $3600 to $3FFF). Then it jumps to the page
;;   after its own copy: $B700, or the master's $3700.
;; - BOOT 2, DOSLODR, uses RWTS, which BOOT 1 has just loaded with it, to read the rest of DOS from tracks 0 to
;;   2: $9D00-$B5FF, or the master's $1B00-$35FF, from track 0 sector 10 on. It resets the screen and keyboard
;;   and ends at DI3.
;; - DI3 jumps to the relocator on a master (Relocator.asm), which moves DOS to the top of memory, or straight
;;   to DBINIT, DOS's cold start (DosInit.asm), on a disk INIT wrote. The relocator changes DI3 to DBINIT, so
;;   every disk INIT writes boots straight into DOS.
;;
;; DOS 3.3's boot reads its sectors backwards with a table to translate sector numbers; DOS 3.2's reads them
;; forwards, sector numbers as they are on the disk. After BOOT 2 come RWTS's small helpers, the IOB and DCT
;; that DOS passes to RWTS, and the layout of a track/sector list sector.

; Two zero bytes before the boot page: the start and end of an empty code range in the relocator's CDETAB.
SC4:
EC4:
    .byte $00, $00
    .assert <* = 0

; BOOT 1 is stored in DOS, and on the disk, in the order DOS's own RWTS reads and writes a sector's bytes, but
; it runs in the order the ROM leaves them in, which is different: the ROM keeps the 5-and-3 groups in the
; order they come off the disk. The macros below let the source show BOOT 1 as it runs at $0300. Its
; instructions, written in capitals, are macros that record each byte under the name BOOT1_n, n being the
; byte's offset at $0300, inside a .dum block that gives the labels their running addresses without emitting
; anything. BOOT1EMIT then emits the 256 recorded bytes in DOS's order.
;
; The order: RWTS stores a sector as 51 groups of five bytes and one last byte, 5 * i + q being byte q of
; group i. The nibbles on the disk carry group 50 first and group 0 last, and the ROM puts byte q of each group
; in its own run of 51, so byte 5 * i + q is at $0300 + 51 * q + 50 - i. The last byte, 255, is not rebuilt:
; $03FF holds only its top five bits, its value shifted right three places.

B1PC .set 0                         ; the running offset of BOOT 1's next byte

;; Records BOOT 1's next byte, as BOOT1_n for its offset n at $0300.
;; Parameters: value = the byte
.macro B1BYTE value
    .ident(.sprintf("BOOT1_%d", B1PC)) = value
B1PC .set B1PC + 1
.endmacro

;; Records one instruction of BOOT 1, of one to three bytes, and moves on past it.
;; Parameters: size = 1 to 3, opcode = its first byte, operand = the byte or address that follows
.macro B1OP size, opcode, operand
    B1BYTE opcode
.if size = 2
    B1BYTE <(operand)
.elseif size = 3
    B1BYTE <(operand)
    B1BYTE >(operand)
.endif
    .res size
.endmacro

;; Picks the opcode for an operand as it is written: #value, address, address,x, address,y or (address),y. An
;; address is zero page when it is a constant below $100; with ,y, which has no zero-page mode in these
;; instructions, a zero-page address means (address),y. 0 marks a mode the instruction lacks.
;; Parameters:
;;   arg   = the operand, up to its comma
;;   index = the operand after its comma
;;   imm   = the opcode for #value
;;   zp    = the opcode for a zero-page address
;;   zpx   = the opcode for a zero-page address,x
;;   abs   = the opcode for an absolute address
;;   absx  = the opcode for address,x
;;   absy  = the opcode for address,y
;;   indy  = the opcode for (address),y
.macro B1MODES arg, index, imm, zp, zpx, abs, absx, absy, indy
B1ZP .set 0
.if .xmatch(.left(1, {arg}), #)
    .assert imm, "BOOT 1: no immediate mode"
    B1OP 2, imm, .right(.tcount({arg}) - 1, {arg})
.exitmacro
.endif
.ifconst arg
.if (arg) < $100
B1ZP .set 1
.endif
.endif
.if .blank({index})
.if B1ZP
    B1OP 2, zp, arg
.else
    B1OP 3, abs, arg
.endif
.elseif .xmatch({index}, x)
.if B1ZP
    B1OP 2, zpx, arg
.else
    B1OP 3, absx, arg
.endif
.elseif B1ZP
    .assert indy, "BOOT 1: no (zp),y mode"
    B1OP 2, indy, arg
.else
    B1OP 3, absy, arg
.endif
.endmacro

;; A branch of BOOT 1.
;; Parameters: opcode = the branch's opcode, target = where it goes
.macro B1BRANCH opcode, target
    .assert (target) - (* + 2) >= -128 && (target) - (* + 2) <= 127, "BOOT 1: branch out of range"
    B1OP 2, opcode, ((target) - (* + 2)) & $FF
.endmacro

; The instructions BOOT 1 uses, in the modes it uses them.
.macro LDA arg, index
    B1MODES arg, index, $A9, $A5, $B5, $AD, $BD, $B9, $B1
.endmacro
.macro STA arg, index
    B1MODES arg, index, 0, $85, $95, $8D, $9D, $99, $91
.endmacro
.macro ORA arg, index
    B1MODES arg, index, $09, $05, $15, $0D, $1D, $19, $11
.endmacro
.macro AND arg, index
    B1MODES arg, index, $29, $25, $35, $2D, $3D, $39, $31
.endmacro
.macro EOR arg, index
    B1MODES arg, index, $49, $45, $55, $4D, $5D, $59, $51
.endmacro
.macro LDX arg
    B1MODES arg, , $A2, $A6, 0, $AE, 0, 0, 0
.endmacro
.macro LDY arg
    B1MODES arg, , $A0, $A4, 0, $AC, 0, 0, 0
.endmacro
.macro STY arg
    B1MODES arg, , 0, $84, 0, $8C, 0, 0, 0
.endmacro
.macro INC arg
    B1MODES arg, , 0, $E6, 0, $EE, 0, 0, 0
.endmacro
.macro ROL arg
.if .xmatch({arg}, a)
    B1OP 1, $2A
.else
    B1MODES arg, , 0, $26, 0, $2E, 0, 0, 0
.endif
.endmacro
.macro ASL arg
    .assert .xmatch({arg}, a), "BOOT 1: ASL A only"
    B1OP 1, $0A
.endmacro
.macro LSR arg
    .assert .xmatch({arg}, a), "BOOT 1: LSR A only"
    B1OP 1, $4A
.endmacro
.macro JSR target
    B1OP 3, $20, target
.endmacro
;; JMP: (address) in zero page, the only indirect jump BOOT 1 makes, or an address of its own.
.macro JMP target
B1ZP .set 0
.ifconst target
.if (target) < $100
B1ZP .set 1
.endif
.endif
.if B1ZP
    B1OP 3, $6C, target
.else
    B1OP 3, $4C, target
.endif
.endmacro
.macro BNE target
    B1BRANCH $D0, target
.endmacro
.macro BEQ target
    B1BRANCH $F0, target
.endmacro
.macro BPL target
    B1BRANCH $10, target
.endmacro
.macro INY
    B1OP 1, $C8
.endmacro
.macro DEX
    B1OP 1, $CA
.endmacro
.macro TXA
    B1OP 1, $8A
.endmacro
.macro RTS
    B1OP 1, $60
.endmacro

;; Bytes of BOOT 1 that are data.
;; Parameters: count = how many, value = each one's value
.macro B1DATA count, value
B1N .set count                      ; count may depend on B1PC, which the bytes change
.repeat B1N
    B1BYTE value
.endrepeat
    .res B1N
.endmacro

;; Emits BOOT 1 in DOS's order: byte n = 5 * i + q is the one recorded for offset 51 * q + 50 - i at $0300,
;; and the last byte is $03FF's five bits shifted back into place, with its low three bits 0.
.macro BOOT1EMIT
    .assert B1PC = 256, "BOOT 1 must be 256 bytes"
.repeat 255, N
B1J .set 51 * (N .mod 5) + 50 - N / 5
    .byte .ident(.sprintf("BOOT1_%d", B1J))
.endrepeat
    .byte BOOT1_255 << 3
.endmacro

; Addresses BOOT 1 uses, as it runs at $0300.
;; Inherit: <Dos33:POINTA>
;; DOS 3.2's BOOT 1 points it at <BFIVES>, $0900, where the 13-sector ROM's READ puts each sector's values.
POINTA = $26

;; The low bits of each group's fourth byte, which <B1DECODE> gathers from the group's three low-bit values.
;; See: <LOW5>, <B1DECODE>
LOW4 = $2A

;; Inherit: <Dos33:BSLOT>
BSLOT = $2B

;; The low bits of each group's fifth byte, which <B1DECODE> gathers from the group's three low-bit values.
;; See: <LOW4>, <B1DECODE>
LOW5 = $3C

;; Inherit: <Dos33:BSECTR>
;; DOS 3.2's BOOT 1 counts it up from the ROM's 0, a sector to a page, until it reaches <BGRPGC>.
BSECTR = $3D

;; The address BOOT 1 jumps through (2 bytes): first the ROM's READ, at $Cn5D, then BOOT 2.
;;
;; BOOT 1 sets it from <BSLOT> and <BREAD> to call READ for each sector, and at the end points it at the page
;; after the first one it loaded, where BOOT 2 starts.
;; See: <BSLOT>, <BREAD>, <B1READ>
BTEMP = $3E

;; The pointer to the page <B1DECODE> puts the decoded sector in, the same bytes as <ZPGWRK> (2 bytes).
;;
;; BOOT 1 starts it at <BGRSPG>'s page and moves it up a page after each sector.
;; See: <B1DECODE>, <BGRSPG>, <ZPGWRK>
BDEST = ZPGWRK

BREAD = $5D                         ;; READ's offset in the ROM's page: READ is at $Cn5D
BLOWS = $0800                       ;; the 154 values READ reads first, each holding three bytes' low bits
BDNIBL = $0800                      ;; the ROM's table from nibble to value, $08AB-$08FF
BFIVES = $0900                      ;; the 256 values READ reads next, each a byte's top five bits

;; BOOT 1: the boot sector, track 0 sector 0, which BOOT 0 loads at $0300 and enters at $0301. DOS keeps this
;; copy of it at $B600 so that INIT can write it to new disks; it only runs at $0300.
;;
;; The first byte, $99, is the one the ROM checks. The ROM rebuilds the first 153 bytes; its leftover bits go
;; to BUPPER and BLOWER, which hold the five-bit values of the next 102, and complete those as well. So all
;; but the last byte, $03FF, are whole when BOOT 1 starts, though in the ROM's order. BOOT 1 reads ten sectors
;; with the ROM's READ, decoding each into a page.
TRK0LDR:
.assert <(TRK0LDR) = 0
    .dum $0300
BOOT1:
    B1DATA 1, $99

; The ROM's table turns each nibble into its five-bit value. Shifting the entries left three places makes READ
; leave each byte's top five bits in place, as DOS's RWTS does with its own table. Y is $99 from the ROM, and
; the entries are $08AB-$08FF.
B1SHIFT:
    LDA BDNIBL,y
    ASL a
    ASL a
    ASL a
    STA BDNIBL,y
    INY
    BNE B1SHIFT

; READ is to put its values at $0900; BOOT 1 decodes each sector to BDEST, from BGRSPG's page on, and makes
; BTEMP point at READ in the ROM, $Cn5D. Y is 0.
    LDX BSLOT
    LDA #>BFIVES
    STA POINTA+1
    LDA BGRSPG
    STA BDEST+1
    STY BDEST
    TXA
    LSR a
    LSR a
    LSR a
    LSR a
    ORA #$C0
    STA BTEMP+1
    LDA #BREAD
    STA BTEMP

; Reads sector BSECTR, the ROM's choice at first: 0, this sector again. The sectors go to consecutive pages, up
; to sector BGRPGC.
READNEXT:
    JSR B1READ
    JSR B1DECODE
    LDA BSECTR
    EOR BGRPGC
    BEQ GOLOADER
    INC BDEST+1
    INC BSECTR
    BNE READNEXT                    ; always

; All read, A = 0: on to BOOT 2, in the page after the first one loaded.
GOLOADER:
    STA BTEMP
    LDA BGRSPG
    STA BTEMP+1
    INC BTEMP+1
B1READ:
    JMP (BTEMP)

;; Decodes the sector READ has just read, putting its bytes in DOS's order at BDEST. READ leaves BFIVES holding
;; each byte's top five bits, in place, and BLOWS the low bits, shifted up three places like every value.
;;
;; Each of the 51 groups of five bytes takes one value from each of BLOWS's three runs of 51. A value holds the
;; low three bits of one of the group's first three bytes in its bits 4-2; its bits 1 and 0 are a bit of the
;; fourth byte and a bit of the fifth, which LOW4 and LOW5 gather over the three values. The groups come
;; backwards: X counts from 50 down while Y counts the bytes up. The last byte comes from the last value.
;; Out:   X = slot * 16, Y = $FF
B1DECODE:
    LDX #$32
    LDY #0
B1DECODE1:
    LDA BLOWS,x
    LSR a
    LSR a
    LSR a
    STA LOW5
    LSR a
    STA LOW4
    LSR a
    ORA BFIVES,x
    STA (BDEST),y
    INY
    LDA BLOWS+$33,x
    LSR a
    LSR a
    LSR a
    LSR a
    ROL LOW5
    LSR a
    ROL LOW4
    ORA BFIVES+$33,x
    STA (BDEST),y
    INY
    LDA BLOWS+$66,x
    LSR a
    LSR a
    LSR a
    LSR a
    ROL LOW5
    LSR a
    ROL LOW4
    ORA BFIVES+$66,x
    STA (BDEST),y
    INY
    LDA LOW4
    AND #7
    ORA BFIVES+$99,x
    STA (BDEST),y
    INY
    LDA LOW5
    AND #7
    ORA BFIVES+$CC,x
    STA (BDEST),y
    INY
    DEX
    BPL B1DECODE1
    LDA BLOWS+$99
    LSR a
    LSR a
    LSR a
    ORA BFIVES+$FF
    STA (BDEST),y
    LDX BSLOT
    RTS

; Unused: $FF to the end of the page, but for two bytes. These are the bytes the ROM completes with its
; leftover bits, three bits to each, from $0399 (BUPPER) and from $03CC (BLOWER).
BUPPER = $0399
BLOWER = $03CC
    B1DATA $CC-B1PC, $FF

;; The page BOOT 1 loads sector 0 into, the boot page; the next sectors go to the pages after it, and BOOT 2 is
;; in the second. WBOOT sets it, as GRSPG, to where the running DOS is, so a disk takes its loader to the same
;; place.
BGRSPG:
    B1DATA 1, >(TRK0LDR)
    B1DATA $FF-B1PC, $FF

;; The last sector BOOT 1 reads, 9: only the top five bits of this byte reach $03FF, so DOS stores it shifted
;; left three places, as GRPGC.
BGRPGC:
    B1DATA 1, 9
    .assert * = $0400
    .dend

    BOOT1EMIT

;; BOOT 1's two variables, where DOS stores them in the boot page: the bytes that run as BGRSPG and BGRPGC.
GRSPG = TRK0LDR + 5 * (50 - $CC .mod 51) + $CC / 51
GRPGC = TRK0LDR + 255
.assert BGRSPG = $03CC && BGRPGC = $03FF

;; BOOT 2, entered from BOOT 1 at $B700 (the master: $3700). It reads the rest of DOS through RWTS, NDPGS
;; pages from track 0 sector LDSECT, 10, upwards, into the pages from LDPAGE up: $9D00-$B5FF (the master:
;; $1B00-$35FF). BOOT 1 left RWTS and this page in place.
;;
;; It records the boot slot and drive 1 in the IOB, and tells RWTS that the drive's head is on track 0
;; (RWTS keeps each drive's track at $478 + slot and $4F8 + slot; BOOT 0 left the head on track 0).
;; In:    X = slot * 16
DOSLODR:
SC3:
.assert <(DOSLODR) = 0
    stx a:IBSLOT
    stx a:IBPSLT
    lda #1
    sta a:IBPDRV
    sta a:IBDRVN
    lda a:NDPGS
    sta a:BRWCNT
    lda #0
    sta a:IBTRK
    lda a:LDSECT
    sta a:IBSECT
    lda a:LDPAGE
    sta a:IBBUFP+1
    lda #IBCRTS
    sta a:IBCMD
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda #0
    sta $4F8,x
    sta $478,x
    jsr BOOTIO

;; DOS is in memory: starts it. A new stack, IBVOL set to $FF as the file manager leaves it, the screen and
;; keyboard as output and input, then on to DI3.
DOSINT:
    ldx #$FF
    txs
    stx a:IBVOL
    jsr SETVID
    jsr SETKBD

;; The end of a boot: jumps to the relocator on a master. The relocator rewrites it to jump to DBINIT; in the
;; running build DOSREL is DBINIT itself.
DI3:
    jmp DOSREL

;; Writes DOS to tracks 0 to 2 of a disk, for INIT, once DLDSUP has set the IOB's buffer to DOS's first page.
;;
;; First the ten pages from TRK0LDR to the end of DOS, to track 0 sectors 0 to 9: the boot sector, BOOT 2 and
;; RWTS. Before that, GRSPG is set to this DOS's TRK0LDR page and GRPGC to 9 (shifted, as BOOT 1 needs it), so
;; the boot sector written loads to where this DOS is; LDPAGE, LDSECT and NDPGS are set for BOOT 2 to read the
;; rest. Then the pages from DOS's first up to TRK0LDR, from track 0 sector 10 on. The first pass leaves the
;; IOB at sector 10.
;; Errors: carry = set if RWTS failed on the last sector (BOOTIO doesn't stop on an error)
WBOOT:
    lda a:IBBUFP+1
    sta a:LDPAGE
    sec
    lda a:ADOSLD+1
    sbc a:LDPAGE
    sta a:NDPGS
    lda #0
    sta a:IBTRK
    sta a:IBSECT
    sta a:IBBUFP
    lda a:ADOSLD+1
    sta a:IBBUFP+1
    sta a:GRSPG
    lda #10
    sta a:BRWCNT
    sta a:LDSECT
    lda #9 << 3                     ; 9 as BOOT 1 sees it, in the byte's top five bits
    sta a:GRPGC
    lda #IBCWTS
    sta a:IBCMD
    jsr BOOTIO
    lda a:LDPAGE
    sta a:IBBUFP+1
    lda a:NDPGS
    sta a:BRWCNT
    jsr BOOTIO
    rts

;; Reads or writes BRWCNT pages through RWTS, as the IOB says, from the page and sector it gives forwards:
;; after each page, one page higher in memory and one sector higher on the disk, from sector 12 to sector 0
;; of the next track. It doesn't stop on an error: the carry it returns is that of the last page.
BOOTIO:
    lda a:BAIOB+1
    ldy a:BAIOB
    jsr DISKIO
    ldy a:IBSECT
    iny
    cpy #13
    bne BIO1
    ldy #0
    inc a:IBTRK
BIO1:
    sty a:IBSECT
    inc a:IBBUFP+1
    dec a:BRWCNT
    bne BOOTIO
    rts

;; Calls RWTS with interrupts off: RWTS's timing can't be interrupted. DOS's $3D9 entry comes here.
;; In:    A = the IOB's address's high byte, Y = its low byte
;; Out:   carry = clear if the call succeeded, set if not (the error in the IOB's IBSTAT)
DISKIO:
    php
    sei
    jsr RWTS
    bcs DSKERR

; PLP brings back the caller's interrupt flag, and its carry too: the carry is set again after it.
    plp
    clc
    rts
DSKERR:
    plp
    sec
    rts

;; Prepares the IOB for WBOOT: the buffer at the page in CCBBSA (DOS's first page, which INIT takes from
;; ASTART), and the volume from DCBVOL, which holds it inverted.
DLDSUP:
    lda CCBBSA
    sta a:IBBUFP+1
    lda #0
    sta a:IBBUFP
    lda DCBVOL
    eor #$FF
    sta a:IBVOL
    rts

;; Zeros the page at ZPGFCB.
;; Out:   A = 0, Y = 0
CLRSEC:
    lda #0
    tay
CS1:
    sta (ZPGFCB),y
    iny
    bne CS1
    rts
    brk                             ; unused

;; The number of pages BOOT 2 reads: from BEGIN up to TRK0LDR, 25 ($19) where DOS runs, 27 ($1B) on the
;; master, which includes the relocator. WBOOT sets it for the disk it writes.
EC3:
NDPGS:
    .byte >(TRK0LDR-BEGIN)

;; Pages left for BOOTIO to read or write.
BRWCNT:
    .byte $09                       ; leftover

;; The sector BOOT 2 starts reading at, on track 0: the one after BOOT 1's ten.
LDSECT:
    .byte 10

;; The page BOOT 2 reads the first of those sectors into: DOS's first, BEGIN. WBOOT sets it for the disk it
;; writes.
LDPAGE:
    .byte >(BEGIN)

;; The IOB's address, for BOOTIO.
BAIOB:
    .word IOB

;; The address of the boot page, TRK0LDR: BOOT 2 loads DOS below it and WBOOT writes from it.
ADOSLD:
    .word TRK0LDR

;; The IOB, the parameter list for a call to RWTS: DOS's own, which BOOT 2, the file manager and INIT fill in.
;; Beneath Apple DOS chapter 6 describes it field by field.
IOB:
IBTYPE:
    .byte 1                         ; the IOB's type, always 1
IBSLOT:
    .byte 6*16                      ; slot * 16
IBDRVN:
    .byte 1                         ; drive, 1 or 2
IBVOL:
    .byte $00                       ; the volume expected, 0 for any
IBTRK:
    .byte 0                         ; track, 0 to 34
IBSECT:
    .byte $01                       ; sector, 0 to 12; leftover
IBDCTP:
    .word DCT                       ; the address of the drive's DCT
IBBUFP:
    .byte $00, $37                  ; the address of the 256-byte buffer; leftover
IBDLEN:
    .byte $00, $00                  ; data length; leftover
IBCMD:
    .byte $02                       ; the command; leftover
IBCNUL = 0                          ;; command: seek only
IBCRTS = 1                          ;; command: read a sector
IBCWTS = 2                          ;; command: write a sector
IBFMT = 4                           ;; command: format the disk
IBSTAT:
    .byte $07                       ; the error, when RWTS returns with the carry set; leftover
IBRERR = $80                        ;; error: a sector couldn't be read
IBDERR = $40                        ;; error: the drive failed
IBVMME = $20                        ;; error: the disk's volume isn't the one expected
IBWPER = $10                        ;; error: the disk is write-protected
IBSMOD:
    .byte $FE                       ; the volume RWTS found; leftover
IBPSLT:
    .byte 6*16                      ; the slot * 16 of the previous call
IBPDRV:
    .byte 1                         ; the drive of the previous call
IBSPAR:
    .res 2,0                        ; spare

;; The DCT, the device characteristics table: device type 0, one phase per track, and the motor-on time
;; ($D8EF, low byte first).
DCT:
    .byte 0, 1, $EF, $D8
    .res 1,0                        ; unused, the page's last byte

.dum 0

;; The layout of a track/sector list sector, which Apple's names call a file directory: offsets into it.
;; Bytes 1 and 2 link to the next such sector, bytes 5 and 6 give the file's sector number of the first pair
;; here, and the track and sector pairs start at FDENT. Code reads the fields with Y = an offset.
FILDIR:
FDUCDE:
    .res 1
FDLTRK:
    .res 1
FDLSEC:
    .res 1
FDNSA:
    .res 1
FDLSDL:
    .res 1
FDFRS:
    .res 2
FDSPAR:
    .res 5
FDENT:
    .res 1
FDTRK = 0                           ;; in a pair: the track
FDSEC = 1                           ;; in a pair: the sector
FDLAST = FILDIR+256                 ;; the end of the sector
.dend
