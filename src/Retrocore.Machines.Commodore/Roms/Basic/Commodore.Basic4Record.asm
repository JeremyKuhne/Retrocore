; COMMODORE BASIC 4: RECORD PARSING AND DISK PARAMETER CHECKS

;; Emits the RECORD statement and the checks shared by the disk commands.
.macro COMMODORE_BASIC4_RECORD
;; Enters BASIC's syntax-error handler from the disk-command code.
SYNERR:
    jmp SNERR

;; Parses RECORD's logical file, record number and optional position.
;;
;; The position defaults to 1; an explicit position of 0 or 255 is rejected.
RECORD:
    lda #$01
    sta RECPOS
    jsr CHRGOT
    lda #'#'
    jsr SYNCHR
    jsr GTVL2
    cpx #$00
    beq QTYER1
    stx LA
    jsr CHKCOM
    beq SYNERR
    bcc NUMADR
    jsr CHKOPN
    jsr FRMEVL
    jsr GETADR
    jsr CHKCLS
    jmp REXNEX
NUMADR:
    jsr FRMEVL
    jsr GETADR
REXNEX:
    jsr CHRGOT
    beq DONER
    jsr CHKCOM
    beq SYNERR
    jsr GTVL2
    cpx #$00
    beq QTYER1
    cpx #$FF
    beq QTYER1
    stx RECPOS
    jsr CHRGOT
    bne SYNERR
DONER:
    jmp BOBREC
QTYER1:
    jmp QTYERR

;; Checks optional HEADER or SCRATCH parameters and requires a first filename.
CHK1:
    and #$E6
    beq CHK2
CHKER1:
    jmp SNERR
;; Requires a first filename in <PRSCHK>.
CHK2:
    lda PRSCHK
    and #$01
    cmp #$01
    bne CHKER1
    lda PRSCHK
    rts

;; Rejects unsupported COLLECT and CATALOG parameters.
CHK3:
    and #$E7
    bne CHKER1
    rts

;; Checks COPY and CONCAT parameters and requires two filenames.
CHK4:
    and #$C4
    bne CHKER1
    lda PRSCHK
;; Requires two filenames for RENAME.
CHK5:
    and #$03
    cmp #$03
    bne CHKER1
    lda PRSCHK
    rts

;; Requires a filename and logical file number for APPEND and DOPEN.
CHK6:
    and #$05
    cmp #$05
    bne CHKER1
    lda PRSCHK
    rts
.endmacro
