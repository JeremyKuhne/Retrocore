; FMGR, the file manager. SCMGR jumps here for every file call ($C0-$D3), and FMGR sends the call on to the block
; file manager (BFMGR), for files on disks, or to the character file manager (CFMGR), for character devices opened
; as files. It carries out SET_LEVEL and GET_LEVEL, the system file level, itself.
;
; Names follow Apple's SOS 1.3 listing.

ZZORG:

F_TPARMX = $A0                      ;; where SCMGR put the file call's parameters
OPEN = $8                           ;; OPEN's request number ($C8)
CLOSE = $C                          ;; CLOSE's request number ($CC)
SETLEVEL = $12                      ;; SET_LEVEL's request number ($D2)
GETLEVEL = $13                      ;; GET_LEVEL's request number ($D3)
F_REQCODE = F_TPARMX                ;; the request number
F_LEVEL = F_TPARMX+$1               ;; SET_LEVEL's new level, or GET_LEVEL's pointer for the result
PATHNAME = F_TPARMX+$1              ;; OPEN's pointer to the pathname (a length byte, then the name)
REFNUM = F_TPARMX+$1                ;; the file's reference number; bit 7 is set for a character file
PERIOD = $2E                        ;; '.', which starts a device name

;; The system file level, 1-3, which SET_LEVEL sets and GET_LEVEL returns.
;;
;; Each file opened records the level; a CLOSE or FLUSH of all files (reference number 0) acts on the files opened at
;; the current level or above.
;; See: <SLEVEL>, <GLEVEL>
LEVEL:
    .byte $1

;; Sends a file call to the block or character file manager, or carries out SET_LEVEL or GET_LEVEL.
;;
;; - OPEN of a pathname starting with '.' goes to CFMGR first, as a device name. If no character device has that name
;;   (file not found), the error is cleared and BFMGR tries it as a volume name.
;; - NEWLINE, READ and WRITE go by the reference number: bit 7 set to CFMGR, clear to BFMGR.
;; - CLOSE goes the same way, except that CLOSE of reference number 0, all files, goes to both.
;; - Every other call goes to BFMGR: CREATE through GET_PREFIX, FLUSH through GET_EOF, and any request number above
;;   GET_LEVEL.
;;
;; Each manager returns to FMGR's caller.
;; In: F_REQCODE = the request number, with the call's parameters after it
;; Out: SERR = 0 or the error code, carry = set for an error
;; See: <SCMGR>, <CFMGR>, <BFMGR>, <LEVEL>
FMGR:
    lda F_REQCODE
    cmp #OPEN
    bcc FMGR010
    beq FMGR020
    cmp #CLOSE
    bcc FMGR030
    beq FMGR040
    cmp #SETLEVEL
    beq SLEVEL
    cmp #GETLEVEL
    beq GLEVEL
FMGR010:
    jmp BFMGR
FMGR020:
    ldy #1                          ; OPEN: does the name start with '.'?
    lda (PATHNAME),y
    cmp #PERIOD
    bne FMGR010
    jsr CFMGR
    bcc FMGR024
    lda SERR
    cmp #FNFERR
    beq FMGR026
FMGR024:
    rts
FMGR026:
    lda #0                          ; no such device: try it as a volume
    sta SERR
    jmp BFMGR
FMGR030:
    lda REFNUM
FMGR031:
    bpl FMGR010
    jmp CFMGR
FMGR040:
    lda REFNUM                      ; CLOSE
    bne FMGR031
    jsr BFMGR                       ; CLOSE of all files: both managers
    jmp CFMGR

;; SET_LEVEL: sets the system file level, which must be 1-3.
;; In: F_LEVEL = the new level
;; Out: carry = set for an error
;; Errors: LVLERR (returned through <SYSERR>)
;; See: <LEVEL>, <FMGR>
SLEVEL:
    lda F_LEVEL
    beq LVL_ERR
    cmp #4
    bcs LVL_ERR
    sta LEVEL
    rts
LVL_ERR:
    lda #LVLERR
    jsr SYSERR

;; GET_LEVEL: returns the system file level in the caller's parameter list.
;; In: F_LEVEL = SCMGR's pointer to the result
;; Out: A = the level
;; See: <LEVEL>, <FMGR>
GLEVEL:
    ldy #0
    lda LEVEL
    sta (F_LEVEL),y
    rts
ZZEND:
ZZLEN = ZZEND-ZZORG
    .assert ZZLEN == LENFMGR, "SOSORG gives the module another length"
