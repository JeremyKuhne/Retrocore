; SCMGR, the system call manager. A program makes a SOS call with BRK followed by the call number and the address
; of its parameter list; IRQ_RCVR passes the BRK here. SCMGR checks the call, copies its parameters to SOS zero page
; as the tables below describe, and jumps to the file, device, utility or memory manager that carries it out.
;
; Names follow Apple's SOS 1.3 listing.

ZZORG:

; ---------------------------------------------------------------------------------------------------------------------
; Parameter description tables
;
; Each call has four bytes. The first is the number of parameters, which the first byte of the caller's list must
; match. The other three hold six four-bit descriptions, one per parameter, high nibble first:
;
; - bit 3 set: an output, which the call returns to the caller's list; clear: an input.
; - bit 2 set: the parameter is a pointer; clear: the parameter is the value itself.
; - bits 1-0: the parameter's length in bytes, less one.
; ---------------------------------------------------------------------------------------------------------------------

;; The highest request number of the file calls ($C0-$D3), the last entry of <FSC_TBL>.
FSC_CNT = $13

;; The parameter descriptions of the file calls, $C0-$D3, four bytes each.
;; See: <MOVE_PARMS>, <FMGR>
FSC_TBL:
    .byte $3, $5D, $00, $00                 ; $C0 CREATE
    .byte $1, $50, $00, $00                 ; $C1 DESTROY
    .byte $2, $55, $00, $00                 ; $C2 RENAME
    .byte $3, $5D, $00, $00                 ; $C3 SET_FILE_INFO
    .byte $3, $5D, $00, $00                 ; $C4 GET_FILE_INFO
    .byte $4, $55, $99, $00                 ; $C5 VOLUME
    .byte $1, $50, $00, $00                 ; $C6 SET_PREFIX
    .byte $2, $50, $00, $00                 ; $C7 GET_PREFIX
    .byte $4, $58, $D0, $00                 ; $C8 OPEN
    .byte $3, $00, $00, $00                 ; $C9 NEWLINE
    .byte $4, $05, $19, $00                 ; $CA READ
    .byte $3, $05, $10, $00                 ; $CB WRITE
    .byte $1, $00, $00, $00                 ; $CC CLOSE
    .byte $1, $00, $00, $00                 ; $CD FLUSH
    .byte $3, $00, $30, $00                 ; $CE SET_MARK
    .byte $2, $0B, $00, $00                 ; $CF GET_MARK
    .byte $3, $00, $30, $00                 ; $D0 SET_EOF
    .byte $2, $0B, $00, $00                 ; $D1 GET_EOF
    .byte $1, $00, $00, $00                 ; $D2 SET_LEVEL
    .byte $1, $80, $00, $00                 ; $D3 GET_LEVEL

;; The highest request number of the device calls ($80-$85), the last entry of <DSC_TBL>.
DSC_CNT = 5

;; The parameter descriptions of the device calls, $80-$85, four bytes each.
;; See: <MOVE_PARMS>, <DMGR>
DSC_TBL:
    .byte $5, $05, $11, $90                 ; $80 D_READ
    .byte $4, $05, $11, $00                 ; $81 D_WRITE
    .byte $3, $00, $50, $00                 ; $82 D_STATUS
    .byte $3, $00, $50, $00                 ; $83 D_CONTROL
    .byte $2, $58, $00, $00                 ; $84 GET_DEV_NUM
    .byte $4, $05, $D0, $00                 ; $85 D_INFO

;; The highest request number of the utility calls ($60-$65), the last entry of <USC_TBL>.
USC_CNT = 5

;; The parameter descriptions of the utility calls, $60-$65, four bytes each.
;;
;; COLD_START has no parameters: <MOVE_PARMS> still copies one byte for it, which nothing reads.
;; See: <MOVE_PARMS>, <UMGR>
USC_TBL:
    .byte $1, $00, $00, $00                 ; $60 SET_FENCE
    .byte $1, $80, $00, $00                 ; $61 GET_FENCE
    .byte $1, $50, $00, $00                 ; $62 SET_TIME
    .byte $1, $50, $00, $00                 ; $63 GET_TIME
    .byte $2, $0B, $00, $00                 ; $64 JOYSTICK
    .byte $0, $00, $00, $00                 ; $65 COLD_START

;; The highest request number of the memory calls ($40-$45), the last entry of <MSC_TBL>.
MSC_CNT = 5

;; The parameter descriptions of the memory calls, $40-$45, four bytes each.
;; See: <MOVE_PARMS>, <MMGR>
MSC_TBL:
    .byte $4, $11, $08, $00                 ; $40 REQUEST_SEG
    .byte $6, $00, $99, $98                 ; $41 FIND_SEG
    .byte $3, $00, $90, $00                 ; $42 CHANGE_SEG
    .byte $5, $09, $99, $80                 ; $43 GET_SEG_INFO
    .byte $2, $18, $00, $00                 ; $44 GET_SEG_NUM
    .byte $1, $00, $00, $00                 ; $45 RELEASE_SEG

;; The call number that calls <DBUGBRK>, the debugger's hook, before the call is checked.
DBUG = $FE

; ---------------------------------------------------------------------------------------------------------------------
; Registers, the interrupt receiver's saved state, and zero page
; ---------------------------------------------------------------------------------------------------------------------

Z_REG = $FFD0                       ;; the zero-page register: which page of memory is zero page
SP_SAVE = $01FF                     ;; the caller's stack pointer, which IRQ_RCVR saved on the SOS stack
Z_SAVE = $01FD                      ;; the caller's zero-page register, saved on the SOS stack
B_SAVE = $01FC                      ;; the caller's bank register, saved on the SOS stack

ADR_LOW = $2000                     ;; the lowest address a caller's pointer may hold
ADR_HIGH = $B800                    ;; the address above the highest a caller's pointer may hold
ADR_MID = $A000                     ;; the end of the switched bank ($2000-$9FFF); higher addresses are never switched

;; SCMGR's own zero-page locations, in SOS zero page.
SCM_VARS = $E0
SCNUM = SCM_VARS+0                  ;; the call number
SCRNUM = SCM_VARS+0                 ;; the request number: the call number less its manager's bits
SCPTR = SCM_VARS+1                  ;; the call's address, then the parameter list's (two bytes, with an X byte)

;; <MOVE_PARMS>'s zero-page locations, after <SCPTR>.
MOVE_VARS = SCPTR+2

F_TPARMX = $A0                      ;; where the file calls' parameters go in SOS zero page
D_TPARMX = $C0                      ;; where the device calls' parameters go
U_TPARMX = $C0                      ;; where the utility calls' parameters go
M_TPARMX = $60                      ;; where the memory calls' parameters go
TPARMX = MOVE_VARS+0                ;; where this call's parameters go
DFN_PTR = MOVE_VARS+1               ;; the parameter description table's address (two bytes, with an X byte)
DFN_PTRX = MOVE_VARS+3              ;; the index of the next description byte in the table
SCPTRX = MOVE_VARS+4                ;; the index of the next byte in the caller's parameter list
RGHT_NIB = MOVE_VARS+5              ;; zero while the high nibble's description is used, $FF for the low one's
SCT_DFN = MOVE_VARS+6               ;; the description byte, with the description in use in its high nibble
SCT_DCNT = MOVE_VARS+7              ;; the parameter's length less one
PARM_CNT = MOVE_VARS+8              ;; the parameters left to copy

; ---------------------------------------------------------------------------------------------------------------------
; The system call manager
; ---------------------------------------------------------------------------------------------------------------------

;; Carries out a SOS call: reads the call after the caller's BRK, copies its parameters and runs its manager.
;;
;; A call is a BRK, the call number and the two-byte address of its parameter list. The return address the BRK left
;; on the caller's stack (the page at CSPAGE) points at that address; SCMGR reads the call number from the byte
;; before it, and moves the return address two bytes on, so the program goes on after the call.
;;
;; The call number's top bits pick the manager, and the rest is the request number:
;;
;; - $C0-$D3, file calls: <FMGR>, with the parameters at <F_TPARMX>.
;; - $80-$85, device calls: <DMGR>, with the parameters at <D_TPARMX>.
;; - $60-$65, utility calls: <UMGR>, with the parameters at <U_TPARMX>.
;; - $40-$45, memory calls: <MMGR>, with the parameters at <M_TPARMX>.
;;
;; The manager is jumped to, so it returns to SCMGR's caller, <IRQ_RCVR>, which hands the error code back to the
;; program in A. The caller's zero page must be SOS's user zero page, $1A (CZPAGE).
;; In: SP_SAVE = the caller's stack pointer, Z_SAVE = the caller's zero page, B_SAVE = the caller's bank
;; Out: SERR = 0 or the error code, carry = set for an error
;; Errors: BADCZPAGE, BADSCNUM, BADSCPCNT, BADXBYTE, BADSCBNDS (returned through <SYSERR>)
;; See: <MOVE_PARMS>, <POINTER>, <IRQ_RCVR>, <SYSERR>
SCMGR:
    lda #>SZPAGE                    ; SOS's own zero page
    sta Z_REG
    lda #0
    sta SXPAGE+SCPTR+1              ; SCPTR starts as a plain address
    sta SERR
    lda Z_SAVE
    cmp #>CZPAGE
    beq SCM005
    lda #<BADCZPAGE
    jsr SYSERR
SCM005:
    ldx SP_SAVE                     ; the BRK's return address is above the saved Y, X, A and P
    lda CSPAGE+6,x
    sta SCPTR+1
    lda CSPAGE+5,x
    sta SCPTR
    bne SCM010
    dec SCPTR+1
SCM010:
    dec SCPTR                       ; SCPTR points at the call number
    clc
    lda CSPAGE+5,x                  ; return after the parameter list's address
    adc #2
    sta CSPAGE+5,x
    bcc SCM020
    inc CSPAGE+6,x
SCM020:
    ldy #0
    lda (SCPTR),y
    cmp #DBUG
    bne SCM025
    jsr DBUGBRK
SCM025:
    sta SCNUM
    iny
    ldx #<SCPTR                     ; SCPTR becomes the parameter list's address
    jsr POINTER
    bcc SCM030
    rts
SCM030:
    lda #$20                        ; for BIT: bit 5 picks utility or memory
    bit SCNUM
    bpl SCM050
    lda SCNUM                       ; $80-$FF: the request number is the low six bits
    and #$3F
    sta SCRNUM
    bvc SCM040
    lda #F_TPARMX                   ; %11xxxxxx: a file call
    sta TPARMX
    ldx #<FSC_TBL
    ldy #>FSC_TBL
    lda #FSC_CNT
    jsr MOVE_PARMS
    bcs SCM_ERR1
    jmp FMGR
SCM040:
    lda #D_TPARMX                   ; %10xxxxxx: a device call
    sta TPARMX
    ldx #<DSC_TBL
    ldy #>DSC_TBL
    lda #DSC_CNT
    jsr MOVE_PARMS
    bcs SCM_ERR1
    jmp DMGR
SCM050:
    bvc SCM_ERR                     ; %00xxxxxx is no call
    php
    lda SCNUM                       ; $40-$7F: the request number is the low five bits
    and #$1F
    sta SCRNUM
    plp
    beq SCM060
    lda #U_TPARMX                   ; %011xxxxx: a utility call
    sta TPARMX
    ldx #<USC_TBL
    ldy #>USC_TBL
    lda #USC_CNT
    jsr MOVE_PARMS
    bcs SCM_ERR1
    jmp UMGR
SCM060:
    lda #M_TPARMX                   ; %010xxxxx: a memory call
    sta TPARMX
    ldx #<MSC_TBL
    ldy #>MSC_TBL
    lda #MSC_CNT
    jsr MOVE_PARMS
    bcs SCM_ERR1
    jmp MMGR
SCM_ERR:
    lda #<BADSCNUM
SCM_ERR1:
    jsr SYSERR

;; Copies a call's parameters from the caller's list to SOS zero page, as the call's entry in a description table says.
;;
;; It checks the request number against the table's last one and the list's parameter count against the table's,
;; stores the request number at TPARMX, then handles each parameter after it:
;;
;; - An input value is copied.
;; - An output value gets a pointer, with its X byte, to its place in the caller's list, so the manager writes the
;;   result straight there.
;; - A pointer goes through <POINTER>. A pointer to an output list is skipped, and its two zero-page bytes left
;;   alone, when the length parameter after it is 0.
;; In: A = the table's highest request number, X/Y = the table's address (low, high), SCRNUM = the request number,
;;   SCPTR = the caller's parameter list, TPARMX = where the parameters go
;; Out: carry = set for an error
;; Errors: BADSCNUM, BADSCPCNT, BADXBYTE, BADSCBNDS (returned through <SYSERR>)
;; Uses: A, X, Y, DFN_PTR, DFN_PTRX, SCPTRX, RGHT_NIB, SCT_DFN, SCT_DCNT, PARM_CNT
;; See: <FSC_TBL>, <POINTER>, <SCMGR>
MOVE_PARMS:
    stx DFN_PTR
    sty DFN_PTR+1
    cmp SCRNUM
    bcs MOVE010
    lda #<BADSCNUM
    bcc SYSERR1                     ; always
MOVE010:
    lda SCRNUM                      ; four bytes per call
    asl a
    asl a
    sta DFN_PTRX
    lda #0
    sta SXPAGE+DFN_PTR+1
    sta SCPTRX
    tay
    lda (SCPTR),y                   ; the list's parameter count must be the table's
    ldy DFN_PTRX
    cmp (DFN_PTR),y
    beq INITLOOPCT
    lda #<BADSCPCNT
SYSERR1:
    jsr SYSERR
INITLOOPCT:
    sta PARM_CNT
    inc SCPTRX
    inc DFN_PTRX
    lda SCRNUM                      ; the request number comes first
    ldx TPARMX
    sta 0,x
    inx
    lda #$FF                        ; so that the first pass takes the high nibble
    sta RGHT_NIB
PARMLOOP:
    lda RGHT_NIB
    eor #$FF
    sta RGHT_NIB
    bne ELSE_RNIB
    ldy DFN_PTRX                    ; high nibble: fetch the next description byte
    lda (DFN_PTR),y
    sta SCT_DFN
    and #$30
    lsr a
    lsr a
    lsr a
    lsr a
    sta SCT_DCNT
    bpl VALUE                       ; always
ELSE_RNIB:
    lda SCT_DFN                     ; low nibble: move it to the high nibble
    tay
    and #$03
    sta SCT_DCNT
    tya
    asl a
    asl a
    asl a
    asl a
    sta SCT_DFN
    inc DFN_PTRX
VALUE:
    bit SCT_DFN                     ; negative = output, overflow = pointer
    bvs REFERENCE
    bmi VAL_OUT
    ldy SCPTRX                      ; an input value: copy its bytes
VAL_IN:
    lda (SCPTR),y
    sta 0,x
    iny
    inx
    dec SCT_DCNT
    bpl VAL_IN
    sty SCPTRX
    jmp ENDLOOP1
VAL_OUT:
    clc                             ; an output value: point at it in the caller's list
    lda SCPTR
    adc SCPTRX
    sta 0,x
    inx
    lda SCPTR+1
    adc #0
    sta 0,x
    clc
    lda SCPTRX
    adc SCT_DCNT
    sta SCPTRX
    lda SXPAGE+SCPTR+1
    sta SXPAGE,x
    jmp ENDLOOP2
REFERENCE:
    bpl REF1
    ldy SCPTRX                      ; a pointer to an output list: is the length after it 0?
    iny
    iny
    lda (SCPTR),y
    beq ENDLOOP0
REF1:
    ldy SCPTRX
    jsr POINTER
    bcs PARM_ERR
ENDLOOP0:
    inx
    inc SCPTRX
ENDLOOP2:
    inx
    inc SCPTRX
ENDLOOP1:
    dec PARM_CNT
    beq PARM_EXIT
    bmi PARM_EXIT                   ; a call with no parameters (COLD_START)
    jmp PARMLOOP
PARM_EXIT:
    clc
PARM_ERR:
    rts

;; Copies a pointer from the caller's parameter list to SOS zero page, checked and made an extended address.
;;
;; A pointer whose high byte is 0 is indirect: its low byte is the zero-page location, in the caller's zero page
;; (CZPAGE), of the real pointer, whose X byte comes from CXPAGE. The result's X byte is then settled:
;;
;; - X byte 0, a plain address: it must be in $2000-$B7FF. $A000-$B7FF stays as it is. $2000-$9FFF is in the
;;   caller's switched bank: bank 0 becomes X byte $8F, and another bank n becomes X byte $8n with $2000 taken off
;;   the address.
;; - X byte $8F: the address must be in $2000-$B7FF.
;; - X byte $80-$8E: the address must not be in page $00; one in page $FF moves to page $7F of the next bank pair.
;; - Any other X byte is an error.
;;
;; Last, an extended address in page $01 moves to page $81 of the bank pair below, the same memory, because the block
;; file manager can't use page $01 there; $80:01xx has no such pair and is an error.
;;
;; The result goes in the two zero-page bytes at X, with its X byte at SXPAGE+1,X.
;; In: SCPTR,Y = the caller's pointer (two bytes), X = the zero-page location for the result
;; Out: carry = set for an error
;; Errors: BADXBYTE, BADSCBNDS (returned through <SYSERR>)
;; Uses: A, Y
;; Keeps: X
;; See: <MOVE_PARMS>, <SCMGR>
POINTER:
    lda (SCPTR),y
    pha
    iny
    lda (SCPTR),y
    beq INDIRECT
    sta 1,x                         ; direct: the address itself
    pla
    sta 0,x
    ldy #0                          ; X byte 0
    beq PTR010
INDIRECT:
    pla                             ; indirect: take the pointer from the caller's zero page
    tay
    lda CZPAGE,y
    sta 0,x
    lda CZPAGE+1,y
    sta 1,x
    lda CXPAGE+1,y
    tay
PTR010:
    lda 1,x                         ; A = the high byte, Y = the X byte
    cpy #$8F
    bcc PTR_X808E
    beq PTR_X8F
    bcs PTR_ERR1
PTR_X8F:
    cmp #>ADR_LOW
    bcc PTR_ERR
    cmp #>ADR_HIGH
    bcs PTR_ERR
    bcc PTR_EXIT
PTR_X808E:
    cpy #$80
    bcc PTR_X0
    cmp #0
    beq PTR_ERR
    cmp #$FF
    bne PATCH
    iny                             ; $8n:FFxx is $8n+1:7Fxx
    lda #$7F
    bne PTR_EXIT
PTR_X0:
    cpy #0
    bne PTR_ERR1
    cmp #>ADR_LOW
    bcc PTR_ERR
    cmp #>ADR_HIGH
    bcs PTR_ERR
    cmp #>ADR_MID
    bcs PTR_EXIT
    pha
    lda B_SAVE                      ; the caller's bank
    and #$0F
    bne PTR030
    pla                             ; bank 0: $2000-$9FFF is $8F:2000-9FFF
    ldy #$8F
    bne PTR_EXIT
PTR030:
    ora #$80                        ; bank n: $2000-$9FFF is $8n:0000-7FFF
    tay
    pla
    sec
    sbc #$20
    bne PATCH
    dey                             ; $8n:00xx is $8n-1:80xx
    lda #$80
PATCH:
    cpy #$80
    bcc PTR_EXIT
    cmp #1
    bne PTR_EXIT
    cpy #$80
    beq PTR_ERR
    dey                             ; $8n:01xx is $8n-1:81xx
    lda #$81
PTR_EXIT:
    sta 1,x
    tya
    sta SXPAGE+1,x
    clc
    rts
PTR_ERR:
    lda #<BADSCBNDS
    jsr SYSERR
PTR_ERR1:
    lda #<BADXBYTE
    jsr SYSERR
ZZEND:
ZZLEN = ZZEND-ZZORG
    .assert ZZLEN == LENSCMGR, "SOSORG gives the module another length"
