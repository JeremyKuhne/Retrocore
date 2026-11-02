;; DOS 3.3 AND 3.2 COMMAND INTERPRETER: COMMAND AND MESSAGE TABLES (CMDTBLS)
;;
;; The data the command scanner (CommandScan.asm) works from: the commands' names, which operands and options
;; each one takes, the option letters and their ranges, and the text of the error messages ERROR prints
;; (DosGoer.asm). The handlers' addresses are in CMDETB, in DosInit.asm. Commands are numbered by their place
;; in CMDNTB, 0 for INIT to 27 for VERIFY, and CMDSTB and CMDETB are in the same order.
;;
;; Runs at $A884-$AA4E where DOS runs.

;; The command names, in command-number order. Each is stored with the top bit set on its last character
;; (DCI), and a 0 ends the table.
;;
;; SCNCMD compares the names in order and takes the first that matches all the way through, so a command
;; line may go on after a name with no separator ("CATALOGD2" is CATALOG,D2).
;; Entry: EC1 = the end of the first stretch of code the relocator adjusts (SC1 to EC1, Relocator.asm)
EC1:
CMDNTB:
    DCI "INIT"
    DCI "LOAD"
    DCI "SAVE"
    DCI "RUN"
    DCI "CHAIN"
    DCI "DELETE"
    DCI "LOCK"
    DCI "UNLOCK"
    DCI "CLOSE"
    DCI "READ"
    DCI "EXEC"
    DCI "WRITE"
    DCI "POSITION"
    DCI "OPEN"
    DCI "APPEND"
    DCI "RENAME"
    DCI "CATALOG"
    DCI "MON"
    DCI "NOMON"
    DCI "PR#"
    DCI "IN#"
    DCI "MAXFILES"
    DCI "FP"
    DCI "INT"
    DCI "BSAVE"
    DCI "BLOAD"
    DCI "BRUN"
    DCI "VERIFY"
    .byte 0

; The first byte of a command's CMDSTB entry: its operands.
NPB = $80                           ;; may have no operands, and then the line goes to BASIC (LOAD, SAVE, RUN)
NPE = $40                           ;; may have no operands, and then DOS still carries it out
FN1 = $20                           ;; takes a file name
FN2 = $10                           ;; takes a second file name (RENAME)
NUM1 = $08                          ;; takes a slot number, 0-7 (PR#, IN#)
NUM2 = $04                          ;; takes a count, 1-16 (MAXFILES)
RNONLY = $02                        ;; only from a running program: in direct mode, NOT DIRECT COMMAND
CREFLG = $01                        ;; the command can create a file (not tested anywhere in DOS)

; The second byte: the options the command allows. INOPTS has the same bits for the options given, and
; OPTAB2 gives the bit for each letter.
V = $40                             ;; ,V: volume number
D = $20                             ;; ,D: drive
S = $10                             ;; ,S: slot
L = $08                             ;; ,L: record length (OPEN) or byte count (BSAVE)
R = $04                             ;; ,R: record number (READ, WRITE, POSITION, EXEC)
B = $02                             ;; ,B: byte offset (READ, WRITE)
ADR = $01                           ;; ,A: address (BSAVE, BLOAD, BRUN)
CIO = $80                           ;; ,C ,I or ,O (MON, NOMON)

;; Each command's operands and allowed options, two bytes a command, indexed by the command's number * 2.
CMDSTB:
    .byte FN1+CREFLG, V+D+S         ; INIT
    .byte NPB+FN1, V+D+S            ; LOAD
    .byte NPB+FN1+CREFLG, V+D+S     ; SAVE
    .byte NPB+FN1, V+D+S            ; RUN
    .byte FN1, V+D+S                ; CHAIN
    .byte FN1, V+D+S                ; DELETE
    .byte FN1, V+D+S                ; LOCK
    .byte FN1, V+D+S                ; UNLOCK
    .byte NPE+FN1, 0                ; CLOSE
    .byte FN1+RNONLY, B+R           ; READ
    .byte FN1, R+V+D+S              ; EXEC
    .byte FN1+RNONLY, B+R           ; WRITE
    .byte FN1+RNONLY, R             ; POSITION
    .byte FN1+RNONLY+CREFLG,L+V+D+S ; OPEN
    .byte FN1+RNONLY, V+D+S         ; APPEND
    .byte FN1+FN2, V+D+S            ; RENAME
    .byte NPE, V+D+S                ; CATALOG
    .byte NPE, CIO                  ; MON
    .byte NPE, CIO                  ; NOMON
    .byte NUM1, 0                   ; PR#
    .byte NUM1, 0                   ; IN#
    .byte NUM2, 0                   ; MAXFILES
    .byte NPE, V+D+S                ; FP
    .byte NPE, 0                    ; INT
    .byte FN1+CREFLG, V+D+S+ADR+L   ; BSAVE
    .byte FN1, V+D+S+ADR            ; BLOAD
    .byte FN1, V+D+S+ADR            ; BRUN
    .byte FN1, V+D+S                ; VERIFY

;; The option letters, high-bit ASCII. An option's number is its place here, from 0; V to A are also the order
;; of their values in CUROPT (CV to CA) and of their ranges in OPTAB3.
OPTAB1:
    .byte 'V'+$80, 'D'+$80, 'S'+$80, 'L'+$80
    .byte 'R'+$80, 'B'+$80, 'A'+$80, 'C'+$80
    .byte 'I'+$80, 'O'+$80
OPT1L = *-OPTAB1                    ;; the number of option letters

; The MON and NOMON options' bits in IMBITS and MONMOD. MC, for ,C, is $40, in FileManagerEntry.asm.
MI = $20                            ;; ,I: show what is read from disk
MO = $10                            ;; ,O: show what is written to disk

;; The bit for each letter of OPTAB1. Those with CIO (bit 7) take no number: the rest of the byte is their
;; MONMOD bit.
OPTAB2:
    .byte V, D, S, L
    .byte R, B, ADR, CIO+MC
    .byte CIO+MI, CIO+MO

;; The lowest and highest value of each numbered option, V to A: two words an option.
OPTAB3:
    .word 0                         ; V: volume 0-254; 0 matches any disk
    .word 254
    .word 1                         ; D: drive 1-2
    .word 2
    .word 1                         ; S: slot 1-7
    .word 7
    .word 1                         ; L: 1-32767
    .word 32767
    .word 0                         ; R: 0-32767
    .word 32767
    .word 0                         ; B: 0-32767
    .word 32767
    .word 0                         ; A: any address
    .word $FFFF

;; The error messages, each with the top bit set on its last character. The table starts with return, bell,
;; return ($0D has its top bit clear only so that the printing goes on), which ERROR prints before each message.
;; EMx is message x's offset from EMSG; EMDTB lists them by error number.
EMSG:
    .byte $0D, $07, $8D
EM1 = *-EMSG                        ;; 1
    DCI "LANGUAGE NOT AVAILABLE"
EM2 = *-EMSG                        ;; 2: the command scanner's out-of-range number
EM3 = *-EMSG                        ;; 3: shares error 2's text
    DCI "RANGE ERROR"
EM4 = *-EMSG                        ;; 4
    DCI "WRITE PROTECTED"
EM5 = *-EMSG                        ;; 5
    DCI "END OF DATA"
EM6 = *-EMSG                        ;; 6
    DCI "FILE NOT FOUND"
EM7 = *-EMSG                        ;; 7
    DCI "VOLUME MISMATCH"
EM8 = *-EMSG                        ;; 8
    DCI "I/O ERROR"
EM9 = *-EMSG                        ;; 9
    DCI "DISK FULL"
EM10 = *-EMSG                       ;; 10
    DCI "FILE LOCKED"
EM11 = *-EMSG                       ;; 11: ESYNTX
    DCI "SYNTAX ERROR"
EM12 = *-EMSG                       ;; 12: ENFA
    DCI "NO BUFFERS AVAILABLE"
EM13 = *-EMSG                       ;; 13: ETYP, ERNU1
    DCI "FILE TYPE MISMATCH"
EM14 = *-EMSG                       ;; 14: MFERR
    DCI "PROGRAM TOO LARGE"
EM15 = *-EMSG                       ;; 15: a run-only command in direct mode
    DCI "NOT DIRECT COMMAND"
    .byte $8D                       ; never printed: EMPR stops at the D above

;; Each error number's message, as its offset in EMSG; entry 0 is the return, bell, return.
EMDTB:
    .byte 0, EM1, EM2, EM3
    .byte EM4, EM5, EM6, EM7
    .byte EM8, EM9, EM10, EM11
    .byte EM12, EM13, EM14
    .byte EM15
