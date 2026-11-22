; COMMODORE BASIC 4: DISK COMMANDS AND MESSAGE CONSTRUCTION

; Substitutions in the disk-command template.
XFN1 = $F1                          ;; insert the first filename
XFN2 = $F2                          ;; insert the second filename
XID = $D0                           ;; insert the two-byte disk ID
XREC = $E0                          ;; insert the record length or sequential-file type
XWRT = $E1                          ;; insert the write or relative-file type
XD1 = $D1                           ;; insert the first drive number
XD2 = $D2                           ;; insert the second drive number

;; Emits BASIC 4's disk commands, status handling and command-string builder.
.macro COMMODORE_BASIC4_DISK_COMMANDS
;; Templates for CATALOG, DOPEN, APPEND, HEADER, COLLECT, BACKUP, COPY, CONCAT, RENAME and SCRATCH.
TABLD:
    .byte $FF, '$', XD1
    .byte XD1, ':', XFN1, ',', XWRT, ',', XREC
    .byte XD1, ':', XFN1, ',', 'A'
    .byte 'N', XD1, ':', XFN1, ',', XID
    .byte 'V', XD1
    .byte 'D', XD2, '=', XD1
    .byte 'C', XD2, ':', XFN2, '=', XD1, ':', XFN1
    .byte 'C', XD2, ':', XFN2, '=', XD2, ':', XFN2, ',', XD1, ':', XFN1
    .byte 'R', XD1, ':', XFN2, '=', XD1, ':', XFN1
    .byte 'S', XD1, ':', XFN1

;; Lists a disk directory, respecting the selected output channel, STOP and pause keys.
CATLOG:
    lda LA
    sta WSW
    jsr DOSPAR
    jsr CHK3
CATALG:
    ldy #$00
    ldx #$01
    lda PRSCHK
    and #$10
    beq CATBLD
    inx
CATBLD:
    txa
    jsr SENDP
    lda DFLTO
    sta CNTDN
    lda #$60
    sta SA
    lda #14
    sta LA
    jsr UNLSN
    jsr FOPEN
    lda #$00
    sta SATUS
    ldy #$03
WG220:
    sty FNLEN
    ldx #14
    jsr CHKIN
    jsr BASIN
    sta TMP2
    ldy SATUS
    bne WG230
    jsr BASIN
    sta TMP2+1
    ldy SATUS
    bne WG230
    ldy FNLEN
    dey
    bne WG220
    jsr CLRCHN
    jsr SUBB
    ldx TMP2
    lda TMP2+1
    jsr LINPRT
    lda #' '
SKIPB:
    jsr BSOUT
    jsr CLRCHN
WG250:
    ldx #14
    jsr CHKIN
    jsr BASIN
    pha
    jsr CLRCHN
    pla
    ldx SATUS
    bne WG230
    cmp #$00
    beq WG240
    jsr SUBA
    jsr STOP1
    beq WG230
    jsr GETIN
    beq WG250
    cmp #' '
    bne WG250
WG255:
    jsr GETIN
    beq WG255
    bne WG250
WG240:
    lda #CR
    jsr SUBA
    jsr UNLSN
    ldy #$02
    bne WG220
WG235:
    pla
WG230:
    jsr CLRCHN
    lda #14
    jmp FCLOSE

;; Prints a catalog character through the selected output and restores the channels.
SUBA:
    jsr SUBB
    jsr BSOUT
    jmp CLRCHN
;; Selects the saved catalog output channel unless the default is the screen.
SUBB:
    ldx CNTDN
    cpx #3
    beq SUBBR
    ldx WSW
    jsr CHKOUT
SUBBR:
    rts

;; Finds an unused disk secondary address beginning at $62.
;; Out: SA = selected secondary address, Y = selected secondary address
ENTRY0:
    ldy #$61
ENTRY1:
    iny
    tya
    ldx LDTND
ENTRY2:
    dex
    bmi RFOUND
    cmp SAT,x
    beq ENTRY1
    bne ENTRY2
RFOUND:
    sty SA
    rts

;; Parses and opens a disk file, including relative and replacement forms.
DOPEN:
    jsr DOSPAR
    jsr CHK6
    and #$22
    beq DOPEN2
    jmp SNERR
DOPEN2:
    jsr ENTRY0
    ldy #$02
    ldx #$03
    bit PRSCHK
    bvc LEAV
RECLCK:
    ldx #$07
LEAV:
    bit PRSCHK
    bpl LEAV1
    lda #'@'
    sta TBUFF
    txa
    ldx #$01
    jsr SENDP1
    jmp OP94
LEAV1:
    txa
    jsr SENDP
    jmp OP94

;; Opens an existing disk file for appending.
APPEND:
    jsr DOSPAR
    jsr CHK6
    and #$E2
    beq DAPPEN
    jmp SNERR
DAPPEN:
    jsr ENTRY0
    ldy #9
    lda #5
    jsr SENDP
    jmp OP94

;; Allocates the disk-status string if needed and reads the drive's error channel into it.
;;
;; The primary device defaults to 8 if <FA> is zero. New storage is 40 bytes plus its two-byte
;; collector backlink; the status text is terminated by a zero when the drive sends carriage return
;; or a zero byte.
ERRCHL:
    lda DSDESC
    bne ECHKS
;; Allocates and links the disk-status buffer before reading the error channel.
GETDS:
    lda #40
    sta DSDESC
    jsr GETSPA
    stx DSDESC+1
    sty DSDESC+2
    lda #$00
    ldy #41
    jsr DSLINK
    lda #$0D
    sta (DSDESC+1),y
ECHKS:
    lda FA
    bne EREAD
    lda #8
    sta FA
EREAD:
    jsr TALK
    lda #$6F
    sta SA
    jsr SECND
    ldy #$FF
LOOP1:
    iny
    jsr ACPTR
    cmp #CR
    beq ERREND
    sta (DSDESC+1),y
    bne LOOP1
ERREND:
    lda #$00
    sta (DSDESC+1),y
    jmp UNTLK

;; Formats a disk after validating its parameters and obtaining direct-mode confirmation.
;;
;; Files on the selected device are closed before the confirmation prompt, even if it is declined.
FORMAT:
    jsr DOSPAR
    jsr CHK1
    and #$11
    cmp #$11
    beq DFORMA
FERRO:
    jmp SNERR
DFORMA:
    jsr DCLALL
    jsr RUSURE
    bcc FBUILD
    rts
FBUILD:
    ldy #14
    lda #4
    ldx DISKID
    beq FCONT
    lda #6
FCONT:
    jsr TRANS
FERRS:
    jsr ERRCHL
    ldy #$00
    lda (DSDESC+1),y
    cmp #'2'
    bcs FERRP
    rts
FERRP:
    jmp BADDIS

;; Closes one disk file or all files on the selected device.
DCLOSE:
    jsr DOSPAR
    and #$F3
    beq DCLSE
    jmp SNERR
DCLSE:
    jsr OLDCLR
    lda LA
    beq DCLALL
    jmp CLOS5
;; Closes all logical files belonging to the current primary device.
DCLALL:
    lda FA
    ldx LDTND
DCLLP:
    dex
    bmi DCLBYE
    cmp FAT,x
    bne DCLLP
    lda LAT,x
    jsr CLOS10
    clv
    bvc DCLALL
DCLBYE:
    rts

;; Sends the relative-record position command for the selected logical file.
BOBREC:
    lda LA
    jsr JLTLK
    beq DRECG
    ldy #(MS3-MS1)
    jmp ERMSG
DRECG:
    jsr JZ100
    jsr OLDCLR
DREBLD:
    lda #'P'
    sta TBUFF
    lda SA
    sta TBUFF+1
    lda POKER
    sta TBUFF+2
    lda POKER+1
    sta TBUFF+3
    lda FNLEN2
    sta TBUFF+4
    ldx #5
    jsr TRANR
    jmp TRANS1

;; Validates a disk's allocation map, optionally selecting a drive.
COLECT:
    jsr DOSPAR
    jsr CHK3
DCOLLE:
    jsr DCLALL
    ldy #20
    ldx #$01
    lda PRSCHK
    and #$10
    beq DCOLL0
    inx
DCOLL0:
    txa
    jmp TRANS

;; Copies a whole disk between the specified drives.
BACKUP:
    jsr DOSPAR
    and #$30
    cmp #$30
    beq BBACK
BERRO:
    jmp SNERR
BBACK:
    lda PRSCHK
    and #$C7
    bne BERRO
DBACKU:
    jsr DCLALL
    ldy #22
    lda #4
;; Builds and sends a disk command on secondary address 15.
TRANS:
    jsr SENDP
TRANS1:
    lda #$6F
    sta SA
    jsr LISTN
    lda SA
    jmp OPENIB

;; Copies a file or a whole drive using the disk command channel.
DCOPY:
    jsr DOSPAR
    and #$30
    cmp #$30
    bne COPY2
    lda PRSCHK
    and #$C7
    beq COPY3
COPY2:
    lda PRSCHK
    jsr CHK4
COPCON:
    lda PRSCHK
COPY3:
    ldy #26
    lda #8
    jmp TRANS

;; Concatenates the source file to the destination file.
CONCAT:
    jsr DOSPAR
    jsr CHK4
    ldy #34
    lda #12
    jmp TRANS

;; Makes the first filename available as the second and appends it to <TBUFF>.
RSFN:
    lda FNLEN
    sta FNLEN2
    lda FNADR
    sta FNADR2
    lda FNADR+1
    sta FNADR2+1
;; Appends the second filename to <TBUFF>, or removes the preceding separator if it is empty.
RDFN:
    tya
    pha
    ldy FNLEN2
    beq RDRT0
    ldy #$00
RDMOV:
    lda (FNADR2),y
    sta TBUFF,x
    inx
    iny
    cpy FNLEN2
    bne RDMOV
    beq RDRT1
RDRT0:
    dex
RDRT1:
    pla
    tay
    sec
    rts

;; Appends the two disk-ID bytes to <TBUFF>.
RID:
    lda DISKID
    sta TBUFF,x
    inx
    lda DISKID+1
    sta TBUFF,x
    inx
    txa
    rts

;; Saves BASIC to a disk file, retaining the replacement prefix when requested.
DSAVE:
    jsr DOSPAR
    jsr CHK2
    and #$66
    beq DSAVE2
    jmp SNERR
DSAVE2:
    ldy #$02
    lda PRSCHK
    and #$80
    beq SAVLD1
SAVLD0:
    lda #'@'
    sta TBUFF
    ldx #$01
    lda #$03
    jsr SENDP1
    jmp SV3
SAVLD1:
    lda #$03
    jsr SENDP
    jmp SV3

;; Loads BASIC from a disk file, clearing the VERIFY selector.
DLOAD:
    jsr DOSPAR
    jsr CHK2
    and #$E6
    beq DLOAD2
DLOERR:
    jmp SNERR
DLOAD2:
    ldy #$02
    lda #$03
    jsr SENDP
    lda #$00
    sta VERCK
    jmp LOADNP

;; Renames a disk file.
RENAME:
    jsr DOSPAR
    jsr CHK5
    and #$E4
    bne DLOERR
DREN:
    ldy #46
    lda #8
    jmp TRANS

;; Scratches a disk file, asking for confirmation in direct mode.
DSCRTC:
    jsr DOSPAR
    jsr CHK1
DSCRAT:
    jsr RUSURE
    bcs NUMBYE
    ldy #54
    lda #4
    jsr TRANS
;; In direct mode, prints the disk's scratch-result message.
NUMSCR:
    jsr DDIREC
    bne NUMBYE
    jsr ERRCHL
    lda #CR
    jsr PRT
    ldy #$00
NUMLP:
    lda (DSDESC+1),y
    cmp #$00
    beq NUMPRT
    jsr PRT
    iny
    bne NUMLP
NUMPRT:
    lda #CR
    jsr PRT
NUMBYE:
    rts

;; Tests whether <TXTPTR> points to page two, the direct-mode input-buffer page.
;; Out: zero = set when direct
DDIREC:
    lda TXTPTR+1
    cmp #$02
DXCR0:
    rts

;; Requests Y or YES confirmation only for a direct-mode destructive command.
;;
;; A rejected answer is drained through carriage return. A zero read while draining also ends the
;; historical loop, but falls through to the acceptance path.
;; Out: carry = set for a rejected direct answer terminated by carriage return
RUSURE:
    jsr DDIREC
    bne ANSYES
RUSUR1:
    ldy #(MSG30-MSG1)
    jsr MSG
    jsr CLRCH
RUSUR2:
    jsr BASIN
    cmp #'Y'
    bne ANSNO
    jsr BASIN
    cmp #CR
    beq ANSYES
    cmp #'E'
    bne ANSNO
    jsr BASIN
    cmp #'S'
    bne ANSNO
    jsr BASIN
    cmp #CR
    beq ANSYES
ANSNO:
    cmp #CR
    sec
    beq ANSBYE
    jsr BASIN
    bne ANSNO
ANSYES:
    clc
ANSBYE:
    rts

;; Prints the bad-disk message in direct mode.
BADDIS:
    jsr DDIREC
    bne ANSBYE
    ldy #(MSG31-MSG1)
    jmp MSG

;; Invalidates the cached disk status and marks its linked string as garbage.
;; Out: DSDESC = 0 (length byte only), SATUS = 0
;; Keeps: Y
OLDCLR:
    tya
    pha
    lda DSDESC
    beq OLDCL1
    ldy #40
    tya
    sta (DSDESC+1),y
    iny
    lda #$FF
    sta (DSDESC+1),y
OLDCL1:
    lda #$00
    sta SATUS
    sta DSDESC
    pla
    tay
    rts

;; Builds a disk command from <TABLD>, substituting filenames, drives and file attributes.
;; In: A = template length, Y = offset before its first byte
;; Out: FNADR = <TBUFF>, FNLEN = constructed command length
SENDP:
    ldx #$00
;; Builds a command after X bytes already in <TBUFF>.
SENDP1:
    sta KCOUNT
    jsr OLDCLR
SENDP2:
    dec KCOUNT
    bmi TRANR
    iny
    lda TABLD,y
    bpl RPLCE
RXFN1:
    cmp #XFN1
    bne RXFN2
    jsr RSFN
RXFN2:
    cmp #XFN2
    bne RXREC
    jsr RDFN
RXREC:
    cmp #XREC
    bne RXID
    lda LRECL
    bne RPLCE
RXID:
    cmp #XID
    bne RXWRT
    jsr RID
RXWRT:
    cmp #XWRT
    bne RXD1
    jsr RWRT
    bne RPLCE
RXD1:
    cmp #XD1
    bne RXD2
    lda DRIVE1
    bpl RXDD
RXD2:
    cmp #XD2
    bne SENDP2
    lda DRIVE2
RXDD:
    ora #48
RPLCE:
    sta TBUFF,x
    inx
    bne SENDP2

;; Makes the X-byte command in <TBUFF> the current kernal filename.
TRANR:
    stx FNLEN
    lda #<TBUFF
    sta FNADR
    lda #>TBUFF
    sta FNADR+1
    rts

;; Selects the relative-file type or the sequential write type for a disk command.
RWRT:
    lda LRECL
    beq RWRT1
    lda #'L'
    bne RWRTS
RWRT1:
    lda #'S'
    sta LRECL
    lda #'W'
RWRTS:
    rts
.endmacro
