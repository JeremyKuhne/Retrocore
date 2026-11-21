;; PR#3 entry (also the first output call after PR#3). The bit of an rts opcode sets V, which selects
;; initialization in C3ENTRY. The sec at $C305 and clc at $C307 double as the bytes the Monitor's $F8B7
;; compares to recognize this kind of slot 3 firmware.
BASICINT:
    bit PUTINV_2                    ; $C300 the bit of an rts opcode ($60) sets V
    bvs C3ENTRY                     ; $C303

;; IN#3 input hook: carry set, V clear.
BASICIN:
    sec                             ; $C305
    .byte $90                       ; $C306 bcc: skips the next byte

;; Output hook: carry clear, V clear.
BASICOUT:
    clc                             ; $C307
    clv                             ; $C308
    bvc C3ENTRY                     ; $C309

;; Pascal 1.1 protocol ID bytes: $01 and $88.
PASCALID:
    .byte $01, $88                  ; $C30B

;; Pascal 1.1 entry offsets in page $C3: init, read, write, status.
PASCALOFS:
    .byte <PASINIT, <PASREAD, <PASWRITE, <PASSTATUS ; $C30D

;; Moves memory between main and auxiliary RAM (see DOAUXMOVE).
;; In:  A1 = source start, A2 = source end, A4 = destination, carry = set for main to aux, clear for aux to main
AUXMOVE:
    jmp DOAUXMOVE                   ; $C311

;; Transfers control to the address in $03ED/$03EE in main or auxiliary memory (see DOXFER).
;; In:  carry = set for aux RAM, clear for main; overflow = set for aux zero page and stack, clear for main
XFER:
    jmp DOXFER                      ; $C314

;; Common slot 3 entry: saves A in $067B, pushes Y and X, then sets MSLOT = $C3 (reading $CFFF to
;; release other cards' $C800 ROM). If MSLOT bit 7 was clear on entry (the Monitor's RDCHAR does lsr
;; MSLOT before reading), sets $04FB bit 3 so escape sequences are processed. V set: initialize
;; (C3INIT). Carry clear: output (CHARIO80). Carry set: input (CHARIO80) when $04FB bit 7 is clear;
;; otherwise sets KSW to the Monitor's KEYIN and continues through it.
;; $04FB bits as the code uses them: 0 MouseText translation off; 1 set by the $C800 Pascal entry;
;; 2 Pascal inverse; 3 escapes allowed (BASIC) or GOTOXY pending (Pascal); 4 Pascal cursor off;
;; 5 control characters disabled; 7 Pascal mode, or not initialized ($FF).
;; In: A = character, carry and V as set by BASICINT/BASICIN/BASICOUT
;; Uses: $04FB, $067B, MSLOT, KSWL/KSWH
C3ENTRY:
    sta CHAR                        ; $C317
    tya                             ; $C31A
    pha                             ; $C31B
    txa                             ; $C31C
    pha                             ; $C31D
    php                             ; $C31E
    lda MODE80                      ; $C31F
    bit MSLOT                       ; $C322
    bmi C3ENTRY_1                   ; $C325
    ora #$08                        ; $C327
    sta MODE80                      ; $C329

C3ENTRY_1:
    jsr SETMSLOT3                   ; $C32C
    plp                             ; $C32F
    bvs C3GOINIT                    ; $C330
    bcc C3CHARIO                    ; $C332
    tax                             ; $C334
    bpl C3CHARIO                    ; $C335
    jsr QUIT80_1                    ; $C337
    pla                             ; $C33A
    tax                             ; $C33B
    pla                             ; $C33C
    tay                             ; $C33D
    lda CHAR                        ; $C33E
    jmp (KSWL)                      ; $C341

;; Jumps into CHARIO80 at its carry test (input or output).
C3CHARIO:
    jmp CHARIO80_2                  ; $C344

;; Jumps to C3INIT.
C3GOINIT:
    jmp C3INIT                      ; $C347

;; Pascal init: sets MSLOT, then C9PASINIT_1 with mode $81.
;; Out: X = 0 (or 9 when there is no auxiliary text memory)
PASINIT:
    jsr SETMSLOT3                   ; $C34A
    jmp C9PASINIT_1                 ; $C34D

;; Pascal read: sets MSLOT, then PASGETKEY.
;; Out: A = character, X = result
PASREAD:
    jsr SETMSLOT3                   ; $C350
    jmp PASGETKEY                   ; $C353

;; Pascal write: sets MSLOT, then PASPUTCHAR.
;; In: A = character
PASWRITE:
    jsr SETMSLOT3                   ; $C356
    jmp PASPUTCHAR                  ; $C359

;; Pascal status request.
;; In: A = request: 0 always answers ready; 1 answers ready when a key is waiting
;; Out:   X = 0, or 3 (with carry clear) for any other request, carry = set when ready, clear when not
PASSTATUS:
    tax                             ; $C35C
    beq PASSTATUS_1                 ; $C35D
    dex                             ; $C35F
    bne PASSTATUS_2                 ; $C360
    bit KBD                         ; $C362
    bpl PASSTATUS_3                 ; $C365

PASSTATUS_1:
    sec                             ; $C367
    rts                             ; $C368

;; Status for an unknown request: X = 3, carry clear.
PASSTATUS_2:
    ldx #$03                        ; $C369

PASSTATUS_3:
    clc                             ; $C36B
    rts                             ; $C36C

;; MSLOT = $C3, and reads $CFFF (CLRROM) to release any slot's $C800 expansion ROM.
;; Out: X = $DF (the byte read)
SETMSLOT3:
    ldx #$C3                        ; $C36D
    stx MSLOT                       ; $C36F
    ldx CLRROM                      ; $C372
    rts                             ; $C375

;; AUXMOVE: copies A1..A2 (inclusive) to A4. Carry set: reads main, writes aux; clear: reads aux,
;; writes main. The previous RAMRD/RAMWRT states are saved and restored.
;; In: A1L/A1H, A2L/A2H, A4L/A4H, carry
;; Out: A1 = A2+1, A4 advanced; A and Y preserved
DOAUXMOVE:
    pha                             ; $C376
    tya                             ; $C377
    pha                             ; $C378
    lda RDRAMRD                     ; $C379
    pha                             ; $C37C
    lda RDRAMWRT                    ; $C37D
    pha                             ; $C380
    bcc DOAUXMOVE_1                 ; $C381
    sta RDMAINRAM                   ; $C383
    sta WRCARDRAM                   ; $C386
    bcs DOAUXMOVE_2                 ; $C389

DOAUXMOVE_1:
    sta WRMAINRAM                   ; $C38B
    sta RDCARDRAM                   ; $C38E

DOAUXMOVE_2:
    ldy #$00                        ; $C391

DOAUXMOVE_3:
    lda (A1L),y                     ; $C393
    sta (A4L),y                     ; $C395
    inc A4L                         ; $C397
    bne DOAUXMOVE_4                 ; $C399
    inc A4H                         ; $C39B

DOAUXMOVE_4:
    lda A1L                         ; $C39D
    cmp A2L                         ; $C39F
    lda A1H                         ; $C3A1
    sbc A2H                         ; $C3A3
    inc A1L                         ; $C3A5
    bne DOAUXMOVE_5                 ; $C3A7
    inc A1H                         ; $C3A9

DOAUXMOVE_5:
    bcc DOAUXMOVE_3                 ; $C3AB
    sta WRMAINRAM                   ; $C3AD
    pla                             ; $C3B0
    bpl DOAUXMOVE_6                 ; $C3B1
    sta WRCARDRAM                   ; $C3B3

DOAUXMOVE_6:
    sta RDMAINRAM                   ; $C3B6
    pla                             ; $C3B9
    bpl DOAUXMOVE_7                 ; $C3BA
    sta RDCARDRAM                   ; $C3BC

DOAUXMOVE_7:
    pla                             ; $C3BF
    tay                             ; $C3C0
    pla                             ; $C3C1
    rts                             ; $C3C2

;; XFER: sets RAMRD/RAMWRT both aux (carry set) or both main (carry clear), copies $03ED/$03EE into
;; the newly selected bank, picks the alternate (V set) or main (V clear) zero page and stack, and
;; jumps through ($03ED).
;; The bytes after it at $C3F4 (sta ROMIN; jmp $FC7A) are the return path of IRQHANDLER's fake
;; interrupt frame.
;; In: $03ED/$03EE = target, carry, V; A preserved
DOXFER:
    pha                             ; $C3C3
    lda $03ED                       ; $C3C4
    pha                             ; $C3C7
    lda $03EE                       ; $C3C8
    pha                             ; $C3CB
    bcc DOXFER_1                    ; $C3CC
    sta RDCARDRAM                   ; $C3CE
    sta WRCARDRAM                   ; $C3D1
    bcs DOXFER_2                    ; $C3D4

DOXFER_1:
    sta RDMAINRAM                   ; $C3D6
    sta WRMAINRAM                   ; $C3D9

DOXFER_2:
    pla                             ; $C3DC
    sta $03EE                       ; $C3DD
    pla                             ; $C3E0
    sta $03ED                       ; $C3E1
    pla                             ; $C3E4
    bvs DOXFER_3                    ; $C3E5
    sta SETSTDZP                    ; $C3E7
    bvc DOXFER_4                    ; $C3EA

DOXFER_3:
    sta SETALTZP                    ; $C3EC

DOXFER_4:
    jmp ($03ED)                     ; $C3EF
    .byte $00, $00                  ; $C3F2

;; The IRQ handler's return path: switches language-card ROM back in (ROMIN) and continues in the
;; Monitor at $FC7A.
IRQRETURN:
    sta ROMIN                       ; $C3F4
    jmp $FC7A                       ; $C3F7
