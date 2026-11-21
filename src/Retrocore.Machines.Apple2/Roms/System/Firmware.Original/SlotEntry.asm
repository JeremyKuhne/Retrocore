;; BASICINT, the PR#3 entry: sets V (the byte at $FF58 is an RTS) and enters the common BASIC entry, which
;; initializes the 80-column firmware and then prints A.
BASICINT:
    bit IORTS                       ; $C300
    bvs BASICENT                    ; $C303

;; BASICIN, the input hook (KSW): carry set, V clear. The SEC here and the CLC at $C307 are also the $38 and
;; $18 bytes a Pascal 1.1 card is identified by.
BASICIN:
    sec                             ; $C305
    .byte $90                       ; $C306 bcc: skips the next byte

;; BASICOUT, the output hook (CSW): carry clear, V clear.
BASICOUT:
    clc                             ; $C307
    clv                             ; $C308
    bvc BASICENT                    ; $C309

;; Pascal 1.1 firmware ID: $01 marks the protocol, $88 is the device signature byte.
PASCALID:
    .byte $01, $88                  ; $C30B

;; Pascal 1.1 entry offsets into page $C3: init $C34B, read $C351, write $C357, status $C35D.
PASCALOFS:
    .byte <JPINIT, <JPREAD, <JPWRITE, <JPSTAT ; $C30D

;; AUXMOVE: copies memory between main and auxiliary RAM (C3_MOVE).
AUXMOVE:
    jmp C3_MOVE                     ; $C311

;; XFER: transfers control to an address in main or auxiliary memory (C3_XFER).
XFER:
    jmp C3_XFER                     ; $C314

;; Common entry for BASICINT, BASICIN and BASICOUT. Saves A in $067B and pushes A, Y, X and P. Sets mode
;; bit 0 if the caller had interrupts enabled. Copies CV to $05FB and sets MSLOT to $C3. V set goes to
;; BASICINIT, otherwise to the shared input/output path at C8BASIC (carry set = input).
;; In: A = character, C/V as set by the entry
BASICENT:
    sta CHAR                        ; $C317
    pha                             ; $C31A
    tya                             ; $C31B
    pha                             ; $C31C
    txa                             ; $C31D
    pha                             ; $C31E
    php                             ; $C31F
    lda MODE80                      ; $C320
    and #$FE                        ; $C323
    sta MODE80                      ; $C325
    pla                             ; $C328
    pha                             ; $C329
    and #$04                        ; $C32A
    bne BASICENT2                   ; $C32C
    lda MODE80                      ; $C32E
    ora #$01                        ; $C331
    sta MODE80                      ; $C333

BASICENT2:
    lda CLRROM                      ; $C336 reading $CFFF releases every $C800 ROM; the next fetch from $C3xx selects the internal one again
    lda CV                          ; $C339
    sta OURCV                       ; $C33B
    jsr SETC8                       ; $C33E
    plp                             ; $C341
    php                             ; $C342
    bvs JBASINIT                    ; $C343
    jmp C8BASIC                     ; $C345

;; Path for BASICINT: jumps to BASICINIT.
JBASINIT:
    jmp BASICINIT                   ; $C348

;; Pascal init entry (offset $4B): sets MSLOT and jumps to PINIT.
JPINIT:
    jsr SETC8                       ; $C34B
    jmp PINIT                       ; $C34E

;; Pascal read entry (offset $51): sets MSLOT and jumps to C8_PREAD.
JPREAD:
    jsr SETC8                       ; $C351
    jmp C8_PREAD                    ; $C354

;; Pascal write entry (offset $57): sets MSLOT and jumps to PWRITE.
JPWRITE:
    jsr SETC8                       ; $C357
    jmp PWRITE                      ; $C35A

;; Pascal status entry (offset $5D): sets MSLOT and jumps to PSTATUS.
JPSTAT:
    jsr SETC8                       ; $C35D
    jmp PSTATUS                     ; $C360

;; Body of AUXMOVE: copies A1L/A1H through A2L/A2H to A4L/A4H. Carry set copies main to auxiliary memory
;; (reads main, writes card), carry clear copies auxiliary to main. Restores RAMRD and RAMWRT afterwards.
;; In: A1 = source start, A2 = source end, A4 = destination, carry = direction
;; Out: A1 = A2+1, A4 advanced past the copy
;; Keeps: A, Y
C3_MOVE:
    pha                             ; $C363
    tya                             ; $C364
    pha                             ; $C365
    lda RDRAMRD                     ; $C366
    pha                             ; $C369
    lda RDRAMWRT                    ; $C36A
    pha                             ; $C36D
    bcc MOVEC2M                     ; $C36E
    sta RDMAINRAM                   ; $C370
    sta WRCARDRAM                   ; $C373
    bcs MOVESTRT                    ; $C376

MOVEC2M:
    sta WRMAINRAM                   ; $C378
    sta RDCARDRAM                   ; $C37B

MOVESTRT:
    ldy #$00                        ; $C37E

MOVELOOP:
    lda (A1L),y                     ; $C380
    sta (A4L),y                     ; $C382
    inc A4L                         ; $C384
    bne C3_NXTA1                    ; $C386
    inc A4H                         ; $C388

C3_NXTA1:
    lda A1L                         ; $C38A
    cmp A2L                         ; $C38C
    lda A1H                         ; $C38E
    sbc A2H                         ; $C390
    inc A1L                         ; $C392
    bne C01                         ; $C394
    inc A1H                         ; $C396

C01:
    bcc MOVELOOP                    ; $C398
    sta WRMAINRAM                   ; $C39A
    pla                             ; $C39D
    bpl C03                         ; $C39E
    sta WRCARDRAM                   ; $C3A0

C03:
    sta RDMAINRAM                   ; $C3A3
    pla                             ; $C3A6
    bpl MOVERET                     ; $C3A7
    sta RDCARDRAM                   ; $C3A9

MOVERET:
    pla                             ; $C3AC
    tay                             ; $C3AD
    pla                             ; $C3AE
    rts                             ; $C3AF

;; Body of XFER: jumps to the address in $03ED/$03EE with main (carry clear) or auxiliary (carry set) memory
;; selected for reading and writing, and the standard (V clear) or alternate (V set) zero page and stack.
;; Keeps: A
C3_XFER:
    pha                             ; $C3B0
    lda $03ED                       ; $C3B1 the address is pushed and pulled back so it is stored again into the newly selected bank
    pha                             ; $C3B4
    lda $03EE                       ; $C3B5
    pha                             ; $C3B8
    bcc XFERC2M                     ; $C3B9
    sta RDCARDRAM                   ; $C3BB
    sta WRCARDRAM                   ; $C3BE
    bvc XFERSZP                     ; $C3C1
    bvs XFERAZP                     ; $C3C3

XFERC2M:
    sta RDMAINRAM                   ; $C3C5
    sta WRMAINRAM                   ; $C3C8
    bvc XFERSZP                     ; $C3CB

XFERAZP:
    pla                             ; $C3CD
    sta $03EE                       ; $C3CE
    pla                             ; $C3D1
    sta $03ED                       ; $C3D2
    pla                             ; $C3D5
    sta SETALTZP                    ; $C3D6
    jmp ($03ED)                     ; $C3D9

;; XFER with V clear: rewrites $03ED/$03EE, selects the standard zero page and stack and jumps.
XFERSZP:
    pla                             ; $C3DC
    sta $03EE                       ; $C3DD
    pla                             ; $C3E0
    sta $03ED                       ; $C3E1
    pla                             ; $C3E4
    sta SETSTDZP                    ; $C3E5
    jmp ($03ED)                     ; $C3E8

;; Stores $C3 in MSLOT so interrupt handlers know whose $C800 ROM is selected.
;; Keeps: A
SETC8:
    pha                             ; $C3EB
    lda #$C3                        ; $C3EC
    sta MSLOT                       ; $C3EE
    pla                             ; $C3F1
    rts                             ; $C3F2
    .byte $00, $00, $00, $00, $00, $00, $00, $00 ; $C3F3
    .byte $00, $00, $00, $00, $00   ; $C3FB
