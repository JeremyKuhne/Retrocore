;; IRQ and BRK entry, reached from the Monitor's IRQ ($FA44). Sets SETINTCXROM (code continues at
;; $C400 in internal ROM), reserves three stack bytes, saves X and Y, and builds a state byte while
;; switching to a known state: bit 0 internal $CX ROM was on; bit 6 80STORE and PAGE2 were on (sets
;; LOWSCR); bit 5 RAMRD aux and bit 4 RAMWRT aux (both set to main); bits 3-1 language card RAM read
;; ($0C bank 1, $0A bank 2; ROMIN is then selected); bit 7 alternate zero page (saves SP in $0101,
;; loads the main SP from $0100, SETSTDZP). A BRK (B flag) leaves the state in A5L, restores the
;; registers and goes to the Monitor's $FA47; an IRQ goes to IRQCALL.
;; In: A = the interrupted program's A (the Monitor's IRQ reloads it from A5H)
;; Uses: A5L, $0100/$0101
IRQHANDLER:
    bit RDCXROM                     ; $C3FA
    sta SETINTCXROM                 ; $C3FD execution continues in internal ROM at $C400
    cld                             ; $C400
    sec                             ; $C401
    bmi IRQHANDLER_1                ; $C402
    clc                             ; $C404

IRQHANDLER_1:
    pha                             ; $C405
    pha                             ; $C406
    pha                             ; $C407
    txa                             ; $C408
    tsx                             ; $C409
    inx                             ; $C40A
    inx                             ; $C40B
    inx                             ; $C40C
    inx                             ; $C40D
    pha                             ; $C40E
    tya                             ; $C40F
    pha                             ; $C410
    lda $0100,x                     ; $C411 P pushed by the interrupt: B flag selects BRK
    and #$10                        ; $C414
    tay                             ; $C416
    lda RD80STORE                   ; $C417
    and RDPAGE2                     ; $C41A
    and #$80                        ; $C41D
    beq IRQHANDLER_2                ; $C41F
    lda #$20                        ; $C421
    sta LOWSCR                      ; $C423

IRQHANDLER_2:
    rol a                           ; $C426
    bit RDRAMRD                     ; $C427
    bpl IRQHANDLER_3                ; $C42A
    sta RDMAINRAM                   ; $C42C
    ora #$20                        ; $C42F

IRQHANDLER_3:
    bit RDRAMWRT                    ; $C431
    bpl IRQHANDLER_4                ; $C434
    sta WRMAINRAM                   ; $C436
    ora #$10                        ; $C439

IRQHANDLER_4:
    bit RDLCRAM                     ; $C43B
    bpl IRQHANDLER_6                ; $C43E
    ora #$0C                        ; $C440
    bit RDLCBNK2                    ; $C442
    bpl IRQHANDLER_5                ; $C445
    eor #$06                        ; $C447

IRQHANDLER_5:
    sta ROMIN                       ; $C449

IRQHANDLER_6:
    bit RDALTZP                     ; $C44C
    bpl IRQHANDLER_7                ; $C44F
    tsx                             ; $C451
    stx $0101                       ; $C452
    ldx $0100                       ; $C455
    txs                             ; $C458
    sta SETSTDZP                    ; $C459
    ora #$80                        ; $C45C

IRQHANDLER_7:
    dey                             ; $C45E
    bmi IRQCALL                     ; $C45F
    sta A5L                         ; $C461
    pla                             ; $C463
    tay                             ; $C464
    pla                             ; $C465
    tax                             ; $C466
    pla                             ; $C467
    pla                             ; $C468
    pla                             ; $C469
    jmp $FA47                       ; $C46A

;; IRQ path: pushes the state byte and MSLOT, then a fake interrupt frame returning to $C3F4, and
;; goes to the Monitor's $FC74 (SETSLOTCXROM, jmp (IRQLOC)). The handler's RTI lands at $C3F4, which
;; selects ROMIN and goes to the Monitor's $FC7A to restore MSLOT's $C800 ROM and come back to
;; IRQRESTORE.
IRQCALL:
    pha                             ; $C46D
    lda MSLOT                       ; $C46E
    pha                             ; $C471
    lda #>IRQRETURN                 ; $C472
    pha                             ; $C474
    lda #<IRQRETURN                 ; $C475
    pha                             ; $C477
    php                             ; $C478
    jmp $FC74                       ; $C479

;; Undoes IRQHANDLER's state byte: restores the alternate zero page and its SP, touches the soft
;; switches in IRQSWITCHES for each set bit (page 2, RAMRD, RAMWRT, language card bank and RAM), then
;; writes a four-byte routine (sta $C006 or $C007; rti) just below the stack pointer, makes the
;; reserved stack bytes an address that returns into it, pulls X and A, and returns: the stub
;; restores the $CX ROM setting and does the RTI.
;; Uses: $0101 (the stack page below SP)
IRQRESTORE:
    lda ROMIN                       ; $C47C
    pla                             ; $C47F
    bpl IRQRESTORE_1                ; $C480
    sta SETALTZP                    ; $C482
    ldx $0101                       ; $C485
    txs                             ; $C488

IRQRESTORE_1:
    ldy #$06                        ; $C489

IRQRESTORE_2:
    bpl IRQRESTORE_4                ; $C48B

;; Part of IRQRESTORE's bit loop: touches the soft switch for a set state bit (ldx IRQSWITCHES,y; inc KBD,x).
IRQRESTORE_3:
    ldx IRQSWITCHES,y               ; $C48D
    inc KBD,x                       ; $C490

;; Part of IRQRESTORE's bit loop, not a separate routine.
IRQRESTORE_4:
    dey                             ; $C493
    bmi IRQRESTORE_5                ; $C494
    asl a                           ; $C496
    bne IRQRESTORE_2                ; $C497

IRQRESTORE_5:
    asl a                           ; $C499
    asl a                           ; $C49A
    pla                             ; $C49B
    tay                             ; $C49C
    tsx                             ; $C49D
    lda #$40                        ; $C49E builds "sta $C00x / rti" below the stack: rti
    pha                             ; $C4A0
    lda #>SETSLOTCXROM              ; $C4A1
    pha                             ; $C4A3
    lda #<SETSLOTCXROM              ; $C4A4 SETSLOTCXROM, or SETINTCXROM with carry set
    adc #$00                        ; $C4A6
    pha                             ; $C4A8
    lda #$8D                        ; $C4A9 sta absolute
    pha                             ; $C4AB
    txs                             ; $C4AC
    txa                             ; $C4AD
    adc #$03                        ; $C4AE
    tax                             ; $C4B0
    sec                             ; $C4B1
    sbc #$07                        ; $C4B2
    sta $0100,x                     ; $C4B4
    inx                             ; $C4B7
    lda #$01                        ; $C4B8
    sta $0100,x                     ; $C4BA
    pla                             ; $C4BD
    tax                             ; $C4BE
    pla                             ; $C4BF
    rts                             ; $C4C0

;; Soft switch offsets from $C000 that IRQRESTORE touches (inc KBD,x), indexed by state bit - 1: bits
;; 1-3 the language card (bank 2 RAM sets bits 3 and 1, bank 1 bits 3 and 2), bit 4 RAMWRT aux, bit 5
;; RAMRD aux, bit 6 page 2. The last entry is unused.
IRQSWITCHES:
    .byte <LCBANK2, <LCBANK1, <LCBANK1, <WRCARDRAM, <RDCARDRAM, <HISCR, $00 ; $C4C1

;; Mini-assembler operand parser: for X down to 0 compares the input (via the Monitor's $FF13) with
;; the CHAR1/CHAR2 address-mode characters and shifts a match bit into A5L; at X = 3 reads a number
;; with GETNUM into A2 and sets YSAV1 (one higher when A2H is nonzero).
;; In: X = 5 (from MINIPARSE), Y = input index
;; Out: A5L = mode bits, A2 = operand, YSAV1, Y advanced
;; Uses: YSAV, A1H
MINIOPND:
    jsr SKIPBLNK                    ; $C4C8
    sty YSAV                        ; $C4CB
    cmp CHAR1,x                     ; $C4CD
    bne MINIOPND_1                  ; $C4D0
    jsr SKIPBLNK                    ; $C4D2
    cmp CHAR2,x                     ; $C4D5
    beq MINIOPND_3                  ; $C4D8
    lda CHAR2,x                     ; $C4DA
    beq MINIOPND_2                  ; $C4DD
    cmp #'$'                        ; $C4DF
    beq MINIOPND_2                  ; $C4E1
    ldy YSAV                        ; $C4E3

MINIOPND_1:
    clc                             ; $C4E5

MINIOPND_2:
    dey                             ; $C4E6

MINIOPND_3:
    rol A5L                         ; $C4E7
    cpx #$03                        ; $C4E9
    bne MINIOPND_5                  ; $C4EB
    jsr GETNUM                      ; $C4ED
    lda A2H                         ; $C4F0
    beq MINIOPND_4                  ; $C4F2
    inx                             ; $C4F4

MINIOPND_4:
    stx YSAV1                       ; $C4F5
    ldx #$03                        ; $C4F7
    dey                             ; $C4F9

MINIOPND_5:
    stx A1H                         ; $C4FA
    dex                             ; $C4FC
    bpl MINIOPND                    ; $C4FD
    rts                             ; $C4FF

;; AppleSoft cassette helper (from AppleSoft's $F777 with internal ROM switched in).
;; Carry set (SHLOAD): reads the two-byte length into LINNUM with READTAPE, then if the table fits
;; below HIMEM (MEMSIZ) and above STREND continues at TAPESHLOAD; otherwise returns carry set
;; (AppleSoft reports out of memory).
;; Carry clear (STORE/RECALL): continues at TAPEARRAY.
;; Out:   carry = clear on success
BASTAPE:
    bcc TAPEARRAY                   ; $C500
    lda #$00                        ; $C502
    sta A1H                         ; $C504
    sta A2H                         ; $C506
    ldy #LINNUM                     ; $C508
    sty A1L                         ; $C50A
    iny                             ; $C50C
    sty A2L                         ; $C50D
    jsr READTAPE                    ; $C50F
    clc                             ; $C512
    lda MEMSIZ                      ; $C513
    tax                             ; $C515
    dex                             ; $C516
    stx A2L                         ; $C517
    sbc LINNUM                      ; $C519
    pha                             ; $C51B
    lda MEMSIZ+1                    ; $C51C
    tay                             ; $C51E
    inx                             ; $C51F
    bne BASTAPE_1                   ; $C520
    dey                             ; $C522

BASTAPE_1:
    sty A2H                         ; $C523
    sbc LINNUM+1                    ; $C525
    cmp STREND+1                    ; $C527
    bcc BASTAPE_2                   ; $C529
    bne TAPESHLOAD                  ; $C52B

BASTAPE_2:
    sec                             ; $C52D
    rts                             ; $C52E

;; SHLOAD: sets HIMEM, FRETOP, the shape table pointer (SHAPEPTR) and A1 to HIMEM - length,
;; then reads the table from tape (READTAPE's entry at $C5D6 with a short header).
TAPESHLOAD:
    sta MEMSIZ+1                    ; $C52F
    sta FRETOP+1                    ; $C531
    sta A1H                         ; $C533
    sta SHAPEPTR+1                  ; $C535
    pla                             ; $C537
    sta SHAPEPTR                    ; $C538
    sta MEMSIZ                      ; $C53A
    sta FRETOP                      ; $C53C
    sta A1L                         ; $C53E
    jsr RDTAPE2BIT                  ; $C540
    lda #$03                        ; $C543
    jsr READTAPE_1                  ; $C545
    clc                             ; $C548
    rts                             ; $C549

;; STORE/RECALL: A2 = LOWTR + LINNUM, calls AppleSoft's $E0EF with the array header's byte 4, and
;; copies HIGHDS into A1 for the Monitor's WRITE or READ that follows.
TAPEARRAY:
    lda LOWTR                       ; $C54A
    adc LINNUM                      ; $C54C
    sta A2L                         ; $C54E
    lda LOWTR+1                     ; $C550
    adc LINNUM+1                    ; $C552
    sta A2H                         ; $C554
    ldy #$04                        ; $C556
    lda (LOWTR),y                   ; $C558
    jsr $E0EF                       ; $C55A
    lda HIGHDS                      ; $C55D
    sta A1L                         ; $C55F
    lda HIGHDS+1                    ; $C561
    sta A1H                         ; $C563
    clc                             ; $C565
    rts                             ; $C566

;; Cassette header tone (the Monitor's HEADR calls it): toggles TAPEOUT in timed loops; $C574 writes
;; one bit (carry selects the length).
;; In: A = header length, X
;; Uses: Y, TAPEOUT
TAPEHEADR:
    ldy #$4B                        ; $C567
    jsr TAPEHEADR_2                 ; $C569
    bne TAPEHEADR                   ; $C56C
    adc #$FE                        ; $C56E
    bcs TAPEHEADR                   ; $C570
    ldy #$21                        ; $C572

TAPEHEADR_1:
    jsr TAPEHEADR_2                 ; $C574 write one bit (carry = bit)
    iny                             ; $C577
    iny                             ; $C578

TAPEHEADR_2:
    dey                             ; $C579
    bne TAPEHEADR_2                 ; $C57A
    bcc TAPEHEADR_4                 ; $C57C
    ldy #$32                        ; $C57E

TAPEHEADR_3:
    dey                             ; $C580
    bne TAPEHEADR_3                 ; $C581

TAPEHEADR_4:
    ldy TAPEOUT                     ; $C583
    ldy #$2C                        ; $C586
    dex                             ; $C588
    rts                             ; $C589

;; Reads 8 bits from tape into A, one RDTAPE2BIT per bit.
;; Out: A = byte
RDTAPEBYTE:
    ldx #$08                        ; $C58A

RDTAPEBYTE_1:
    pha                             ; $C58C
    jsr RDTAPE2BIT                  ; $C58D
    pla                             ; $C590
    rol a                           ; $C591
    ldy #$3A                        ; $C592
    dex                             ; $C594
    bne RDTAPEBYTE_1                ; $C595
    rts                             ; $C597

;; Waits for two TAPEIN level changes; $C59B waits for one. LENGTH holds the last level; Y counts down
;; during the wait.
;; Out:   carry = the bit, from cpy #$80 on the elapsed time
;; Uses: LENGTH, Y
RDTAPE2BIT:
    jsr RDTAPE2BIT_1                ; $C598

RDTAPE2BIT_1:
    dey                             ; $C59B one level change
    lda TAPEIN                      ; $C59C
    eor LENGTH                      ; $C59F
    bpl RDTAPE2BIT_1                ; $C5A1
    eor LENGTH                      ; $C5A3
    sta LENGTH                      ; $C5A5
    cpy #$80                        ; $C5A7
    rts                             ; $C5A9

;; Cassette write (the Monitor's WRITE): header, then A1..A2 a byte at a time with a running exclusive
;; or, then that checksum; $C5C8 writes the byte in A.
;; In: A1/A2, A = header length
;; Out:   zero = set at the end
WRITETAPE:
    jsr TAPEHEADR                   ; $C5AA
    ldy #$27                        ; $C5AD

WRITETAPE_1:
    ldx #$00                        ; $C5AF
    eor (A1L,x)                     ; $C5B1
    pha                             ; $C5B3
    lda (A1L,x)                     ; $C5B4
    jsr WRITETAPE_2                 ; $C5B6
    jsr NXTA1                       ; $C5B9
    ldy #$1D                        ; $C5BC
    pla                             ; $C5BE
    bcc WRITETAPE_1                 ; $C5BF
    ldy #$22                        ; $C5C1
    jsr WRITETAPE_2                 ; $C5C3
    beq WRITETAPE_4                 ; $C5C6

WRITETAPE_2:
    ldx #$10                        ; $C5C8 write one byte

WRITETAPE_3:
    asl a                           ; $C5CA
    jsr TAPEHEADR_1                 ; $C5CB
    bne WRITETAPE_3                 ; $C5CE

WRITETAPE_4:
    rts                             ; $C5D0

;; Cassette read (the Monitor's READ): finds the header and sync, reads bytes into A1..A2, then reads
;; the checksum byte and compares it with the running exclusive or in MASK. $C5D6 starts with a given
;; header length in A (used by SHLOAD).
;; In: A1/A2
;; Out:   zero = set when the checksum matches
;; Uses: MASK, LENGTH, A1
READTAPE:
    jsr RDTAPE2BIT                  ; $C5D1
    lda #$16                        ; $C5D4

READTAPE_1:
    jsr TAPEHEADR                   ; $C5D6
    sta MASK                        ; $C5D9
    jsr RDTAPE2BIT                  ; $C5DB

READTAPE_2:
    ldy #$24                        ; $C5DE
    jsr RDTAPE2BIT_1                ; $C5E0
    bcs READTAPE_2                  ; $C5E3
    jsr RDTAPE2BIT_1                ; $C5E5
    ldy #$3B                        ; $C5E8

READTAPE_3:
    jsr RDTAPEBYTE                  ; $C5EA
    sta (A1L,x)                     ; $C5ED
    eor MASK                        ; $C5EF
    sta MASK                        ; $C5F1
    jsr NXTA1                       ; $C5F3
    ldy #$35                        ; $C5F6
    bcc READTAPE_3                  ; $C5F8
    jsr RDTAPEBYTE                  ; $C5FA
    cmp MASK                        ; $C5FD
    rts                             ; $C5FF
