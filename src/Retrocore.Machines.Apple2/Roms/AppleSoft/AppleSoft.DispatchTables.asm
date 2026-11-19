;; APPLESOFT: DISPATCH, RESERVED WORDS AND ERROR TEXT
;;
;; These tables begin at $D000. <CRUNCH> searches <RESLST> in order; <LIST> expands its token bytes back
;; through the same list. <GONE> dispatches statement tokens with <STMDSP>, while expression evaluation uses
;; <FUNDSP> and <OPTAB>. <ERROR> indexes <ERRTAB> by byte offset, not by an ordinal error number.


;; Handler addresses minus one for the 64 statements, indexed by token $80-$BF.
;;
;; <GONE> pushes the high and low bytes and returns through <CHRGET>; the RTS increments the stacked
;; address before entering the handler. HOME enters the Monitor and & enters the RAM vector <AMPERV>.
STMDSP:
    .word END - 1                   ; $80 END
    .word FOR - 1                   ; $81 FOR
    .word NEXT - 1                  ; $82 NEXT
    .word DATA - 1                  ; $83 DATA
    .word INPUT - 1                 ; $84 INPUT
    .word DEL - 1                   ; $85 DEL
    .word DIM - 1                   ; $86 DIM
    .word READ - 1                  ; $87 READ
    .word GR - 1                    ; $88 GR
    .word TEXT - 1                  ; $89 TEXT
    .word PRNUM - 1                 ; $8A PR#
    .word INNUM - 1                 ; $8B IN#
    .word CALL - 1                  ; $8C CALL
    .word PLOT - 1                  ; $8D PLOT
    .word HLIN - 1                  ; $8E HLIN
    .word VLIN - 1                  ; $8F VLIN
    .word HGR2 - 1                  ; $90 HGR2
    .word HGR - 1                   ; $91 HGR
    .word HCOLOR - 1                ; $92 HCOLOR=
    .word HPLOT - 1                 ; $93 HPLOT
    .word DRAW - 1                  ; $94 DRAW
    .word XDRAW - 1                 ; $95 XDRAW
    .word HTAB - 1                  ; $96 HTAB
    .word HOME - 1                  ; $97 HOME
    .word ROT - 1                   ; $98 ROT=
    .word SCALE - 1                 ; $99 SCALE=
    .word SHLOAD - 1                ; $9A SHLOAD
    .word TRACE - 1                 ; $9B TRACE
    .word NOTRAC - 1                ; $9C NOTRACE
    .word NRMSTM - 1                ; $9D NORMAL
    .word INVERS - 1                ; $9E INVERSE
    .word FLASH - 1                 ; $9F FLASH
    .word COLSTM - 1                ; $A0 COLOR=
    .word POP - 1                   ; $A1 POP
    .word VTAB - 1                  ; $A2 VTAB
    .word HIMEM - 1                 ; $A3 HIMEM:
    .word LOMEM - 1                 ; $A4 LOMEM:
    .word ONERR - 1                 ; $A5 ONERR
    .word RESUME - 1                ; $A6 RESUME
    .word RECALL - 1                ; $A7 RECALL
    .word STORE - 1                 ; $A8 STORE
    .word SPEED - 1                 ; $A9 SPEED=
    .word LET - 1                   ; $AA LET
    .word GOTO - 1                  ; $AB GOTO
    .word RUNSTM - 1                ; $AC RUN
    .word IF - 1                    ; $AD IF
    .word RESTOR - 1                ; $AE RESTORE
    .word AMPERV - 1                ; $AF &
    .word GOSUB - 1                 ; $B0 GOSUB
    .word POP - 1                   ; $B1 RETURN
    .word REM - 1                   ; $B2 REM
    .word STOP - 1                  ; $B3 STOP
    .word ON - 1                    ; $B4 ON
    .word WAIT - 1                  ; $B5 WAIT
    .word LOAD - 1                  ; $B6 LOAD
    .word SAVE - 1                  ; $B7 SAVE
    .word DEF - 1                   ; $B8 DEF
    .word POKE - 1                  ; $B9 POKE
    .word PRINT - 1                 ; $BA PRINT
    .word CONT - 1                  ; $BB CONT
    .word LIST - 1                  ; $BC LIST
    .word CLEAR - 1                 ; $BD CLEAR
    .word GET - 1                   ; $BE GET
    .word NEW - 1                   ; $BF NEW

;; Addresses of the functions in token order, from SGN through MID$.
;;
;; Unlike <STMDSP>, these words are the actual entry addresses. The SCRN( entry goes to <ERROR>; its
;; special handling is elsewhere in expression evaluation. USR enters the writable <USRPOK> vector.
FUNDSP:
    .word SGN                       ; SGN
    .word INT                       ; INT
    .word ABS                       ; ABS
    .word USRPOK                    ; USR
    .word FRE                       ; FRE
    .word ERROR                     ; SCRN(
    .word PDL                       ; PDL
    .word POS                       ; POS
    .word SQR                       ; SQR
    .word RND                       ; RND
    .word LOG                       ; LOG
    .word EXP                       ; EXP
    .word COS                       ; COS
    .word SIN                       ; SIN
    .word TAN                       ; TAN
    .word ATN                       ; ATN
    .word PEEK                      ; PEEK
    .word LEN                       ; LEN
    .word STR                       ; STR$
    .word VAL                       ; VAL
    .word ASC                       ; ASC
    .word CHR                       ; CHR$
    .word LEFT                      ; LEFT$
    .word RIGHT                     ; RIGHT$
    .word MID                       ; MID$

;; Operator precedence bytes and handler addresses, in the order of tokens + through OR.
;;
;; Each entry is one precedence byte followed by a little-endian handler address minus one. The evaluator
;; stacks that address for RTS dispatch. Higher precedence binds more tightly; the following entries provide
;; unary negation, NOT and the shared relational handler.
OPTAB:
    .byte $79
    .word FADDT - 1
    .byte $79
    .word FSUBT - 1
    .byte $7B
    .word FMULTT - 1
    .byte $7B
    .word FDIVT - 1
    .byte $7D
    .word FPWRT - 1
    .byte $50
    .word OROP1 - 1
    .byte $46
    .word OROP - 1

;; Precedence and handler address minus one for unary negation.
NEGTAB:
    .byte $7F
    .word NEGOP - 1

;; Precedence and handler address minus one for NOT.
NOTTAB:
    .byte $7F
    .word NOTOP - 1

;; Precedence and handler address minus one for relational comparisons.
PTDORL:
    .byte $64
    .word DOREL - 1
;; Assembly-time counter retained from the Microsoft table definitions, not a runtime location.
;;
;; It tracks token values while defining <RESLST>, then byte offsets into <ERRTAB>.
Q .set $7F
Q .set $80

;; Reserved-word spellings in token order, starting at $80 and ending with a zero byte.
;;
;; Each spelling has bit 7 set on its last character; the preceding characters have bit 7 clear. The token
;; is $80 plus the spelling's index, not its offset in this variable-length table. Ordering matters when one
;; spelling is a prefix of another. REM, DATA and quoted text have special treatment during tokenization.
RESLST:
    .byte "EN", 'D' | $80           ; $80 END
ENDTK = $80                         ;; END
Q .set $81
    .byte "FO", 'R' | $80           ; $81 FOR
FORTK = $81                         ;; FOR
Q .set $82
    .byte "NEX", 'T' | $80          ; $82 NEXT
Q .set $83
    .byte "DAT", 'A' | $80          ; $83 DATA
DATATK = $83                        ;; DATA
Q .set $84
    .byte "INPU", 'T' | $80         ; $84 INPUT
Q .set $85
    .byte "DE", 'L' | $80           ; $85 DEL
Q .set $86
    .byte "DI", 'M' | $80           ; $86 DIM
Q .set $87
    .byte "REA", 'D' | $80          ; $87 READ
Q .set $88
    .byte "G", 'R' | $80            ; $88 GR
Q .set $89
    .byte "TEX", 'T' | $80          ; $89 TEXT
Q .set $8A
    .byte "PR", '#' | $80           ; $8A PR#
Q .set $8B
    .byte "IN", '#' | $80           ; $8B IN#
Q .set $8C
    .byte "CAL", 'L' | $80          ; $8C CALL
Q .set $8D
    .byte "PLO", 'T' | $80          ; $8D PLOT
Q .set $8E
    .byte "HLI", 'N' | $80          ; $8E HLIN
Q .set $8F
    .byte "VLI", 'N' | $80          ; $8F VLIN
Q .set $90
    .byte "HGR", '2' | $80          ; $90 HGR2
Q .set $91
    .byte "HG", 'R' | $80           ; $91 HGR
Q .set $92
    .byte "HCOLOR", '=' | $80       ; $92 HCOLOR=
Q .set $93
    .byte "HPLO", 'T' | $80         ; $93 HPLOT
Q .set $94
    .byte "DRA", 'W' | $80          ; $94 DRAW
Q .set $95
    .byte "XDRA", 'W' | $80         ; $95 XDRAW
Q .set $96
    .byte "HTA", 'B' | $80          ; $96 HTAB
Q .set $97
    .byte "HOM", 'E' | $80          ; $97 HOME
Q .set $98
    .byte "ROT", '=' | $80          ; $98 ROT=
Q .set $99
    .byte "SCALE", '=' | $80        ; $99 SCALE=
Q .set $9A
    .byte "SHLOA", 'D' | $80        ; $9A SHLOAD
Q .set $9B
    .byte "TRAC", 'E' | $80         ; $9B TRACE
Q .set $9C
    .byte "NOTRAC", 'E' | $80       ; $9C NOTRACE
Q .set $9D
    .byte "NORMA", 'L' | $80        ; $9D NORMAL
Q .set $9E
    .byte "INVERS", 'E' | $80       ; $9E INVERSE
Q .set $9F
    .byte "FLAS", 'H' | $80         ; $9F FLASH
Q .set $A0
    .byte "COLOR", '=' | $80        ; $A0 COLOR=
Q .set $A1
    .byte "PO", 'P' | $80           ; $A1 POP
POPTK = $A1                         ;; POP
Q .set $A2
    .byte "VTA", 'B' | $80          ; $A2 VTAB
Q .set $A3
    .byte "HIMEM", ':' | $80        ; $A3 HIMEM:
Q .set $A4
    .byte "LOMEM", ':' | $80        ; $A4 LOMEM:
Q .set $A5
    .byte "ONER", 'R' | $80         ; $A5 ONERR
Q .set $A6
    .byte "RESUM", 'E' | $80        ; $A6 RESUME
Q .set $A7
    .byte "RECAL", 'L' | $80        ; $A7 RECALL
Q .set $A8
    .byte "STOR", 'E' | $80         ; $A8 STORE
Q .set $A9
    .byte "SPEED", '=' | $80        ; $A9 SPEED=
Q .set $AA
    .byte "LE", 'T' | $80           ; $AA LET
Q .set $AB
    .byte "GOT", 'O' | $80          ; $AB GOTO
GOTOTK = $AB                        ;; GOTO
Q .set $AC
    .byte "RU", 'N' | $80           ; $AC RUN
Q .set $AD
    .byte "I", 'F' | $80            ; $AD IF
Q .set $AE
    .byte "RESTOR", 'E' | $80       ; $AE RESTORE
Q .set $AF
    .byte '&' | $80                 ; $AF &
Q .set $B0
    .byte "GOSU", 'B' | $80         ; $B0 GOSUB
GOSUTK = $B0                        ;; GOSUB
Q .set $B1
    .byte "RETUR", 'N' | $80        ; $B1 RETURN
Q .set $B2
    .byte "RE", 'M' | $80           ; $B2 REM
REMTK = $B2                         ;; REM
Q .set $B3
    .byte "STO", 'P' | $80          ; $B3 STOP
Q .set $B4
    .byte "O", 'N' | $80            ; $B4 ON
Q .set $B5
    .byte "WAI", 'T' | $80          ; $B5 WAIT
Q .set $B6
    .byte "LOA", 'D' | $80          ; $B6 LOAD
Q .set $B7
    .byte "SAV", 'E' | $80          ; $B7 SAVE
Q .set $B8
    .byte "DE", 'F' | $80           ; $B8 DEF
Q .set $B9
    .byte "POK", 'E' | $80          ; $B9 POKE
Q .set $BA
    .byte "PRIN", 'T' | $80         ; $BA PRINT
PRINTK = $BA                        ;; PRINT
Q .set $BB
    .byte "CON", 'T' | $80          ; $BB CONT
Q .set $BC
    .byte "LIS", 'T' | $80          ; $BC LIST
Q .set $BD
    .byte "CLEA", 'R' | $80         ; $BD CLEAR
Q .set $BE
    .byte "GE", 'T' | $80           ; $BE GET
Q .set $BF
    .byte "NE", 'W' | $80           ; $BF NEW
SCRATK = $BF                        ;; NEW
Q .set $C0
    .byte "TAB", '(' | $80          ; $C0 TAB(
TABTK = $C0                         ;; TAB(
Q .set $C1
    .byte "T", 'O' | $80            ; $C1 TO
TOTK = $C1                          ;; TO
Q .set $C2
    .byte "F", 'N' | $80            ; $C2 FN
FNTK = $C2                          ;; FN
Q .set $C3
    .byte "SPC", '(' | $80          ; $C3 SPC(
SPCTK = $C3                         ;; SPC(
Q .set $C4
    .byte "THE", 'N' | $80          ; $C4 THEN
THENTK = $C4                        ;; THEN
Q .set $C5
    .byte "A", 'T' | $80            ; $C5 AT
ATTK = $C5                          ;; AT
Q .set $C6
    .byte "NO", 'T' | $80           ; $C6 NOT
NOTTK = $C6                         ;; NOT
Q .set $C7
    .byte "STE", 'P' | $80          ; $C7 STEP
STEPTK = $C7                        ;; STEP
Q .set $C8
    .byte '+' | $80                 ; $C8 +
PLUSTK = $C8                        ;; +
Q .set $C9
    .byte '-' | $80                 ; $C9 -
MINUTK = $C9                        ;; -
Q .set $CA
    .byte '*' | $80                 ; $CA *
Q .set $CB
    .byte '/' | $80                 ; $CB /
Q .set $CC
    .byte '^' | $80                 ; $CC ^
Q .set $CD
    .byte "AN", 'D' | $80           ; $CD AND
Q .set $CE
    .byte "O", 'R' | $80            ; $CE OR
    .byte '>' | $80                 ; $CF >
Q .set $CF
GREATK = $CF                        ;; >
Q .set $D0
    .byte '=' | $80                 ; $D0 =
EQULTK = $D0                        ;; =
    .byte '<' | $80                 ; $D1 <
Q .set $D1
LESSTK = $D1                        ;; <
Q .set $D2
    .byte "SG", 'N' | $80           ; $D2 SGN
ONEFUN = $D2                        ;; SGN, the first function
Q .set $D3
    .byte "IN", 'T' | $80           ; $D3 INT
Q .set $D4
    .byte "AB", 'S' | $80           ; $D4 ABS
Q .set $D5
    .byte "US", 'R' | $80           ; $D5 USR
Q .set $D6
    .byte "FR", 'E' | $80           ; $D6 FRE
Q .set $D7
    .byte "SCRN", '(' | $80         ; $D7 SCRN(
SCRNTK = $D7                        ;; SCRN(
Q .set $D8
    .byte "PD", 'L' | $80           ; $D8 PDL
Q .set $D9
    .byte "PO", 'S' | $80           ; $D9 POS
Q .set $DA
    .byte "SQ", 'R' | $80           ; $DA SQR
Q .set $DB
    .byte "RN", 'D' | $80           ; $DB RND
Q .set $DC
    .byte "LO", 'G' | $80           ; $DC LOG
Q .set $DD
    .byte "EX", 'P' | $80           ; $DD EXP
Q .set $DE
    .byte "CO", 'S' | $80           ; $DE COS
Q .set $DF
    .byte "SI", 'N' | $80           ; $DF SIN
Q .set $E0
    .byte "TA", 'N' | $80           ; $E0 TAN
Q .set $E1
    .byte "AT", 'N' | $80           ; $E1 ATN
Q .set $E2
    .byte "PEE", 'K' | $80          ; $E2 PEEK
Q .set $E3
    .byte "LE", 'N' | $80           ; $E3 LEN
Q .set $E4
    .byte "STR", '$' | $80          ; $E4 STR$
Q .set $E5
    .byte "VA", 'L' | $80           ; $E5 VAL
Q .set $E6
    .byte "AS", 'C' | $80           ; $E6 ASC
Q .set $E7
    .byte "CHR", '$' | $80          ; $E7 CHR$
LASNUM = $E7                        ;; CHR$, the last single-argument function
Q .set $E8
    .byte "LEFT", '$' | $80         ; $E8 LEFT$
Q .set $E9
    .byte "RIGHT", '$' | $80        ; $E9 RIGHT$
Q .set $EA
    .byte "MID", '$' | $80          ; $EA MID$
    .byte $00
Q .set $00

;; Error messages addressed by the ERR constants' byte offsets.
;;
;; Each message ends in a character with bit 7 set. <ERROR> prints until that byte, then appends <ERR>;
;; all offsets fit in one byte.
ERRTAB:
    .byte "NEXT WITHOUT FO", 'R' | $80
ERRNF = $00                         ;; offset of NEXT WITHOUT FOR in <ERRTAB>
Q .set $10
    .byte "SYNTA", 'X' | $80
ERRSN = $10                         ;; offset of SYNTAX in <ERRTAB>
Q .set $16
    .byte "RETURN WITHOUT GOSU", 'B' | $80
ERRRG = $16                         ;; offset of RETURN WITHOUT GOSUB in <ERRTAB>
Q .set $2A
    .byte "OUT OF DAT", 'A' | $80
ERROD = $2A                         ;; offset of OUT OF DATA in <ERRTAB>
Q .set $35
    .byte "ILLEGAL QUANTIT", 'Y' | $80
ERRFC = $35                         ;; offset of ILLEGAL QUANTITY in <ERRTAB>
Q .set $45
    .byte "OVERFLO", 'W' | $80
ERROV = $45                         ;; offset of OVERFLOW in <ERRTAB>
Q .set $4D
    .byte "OUT OF MEMOR", 'Y' | $80
ERROM = $4D                         ;; offset of OUT OF MEMORY in <ERRTAB>
Q .set $5A
    .byte "UNDEF'D STATEMEN", 'T' | $80
ERRUS = $5A                         ;; offset of UNDEF'D STATEMENT in <ERRTAB>
Q .set $6B
    .byte "BAD SUBSCRIP", 'T' | $80
ERRBS = $6B                         ;; offset of BAD SUBSCRIPT in <ERRTAB>
Q .set $78
    .byte "REDIM'D ARRA", 'Y' | $80
ERRDD = $78                         ;; offset of REDIM'D ARRAY in <ERRTAB>
Q .set $85
    .byte "DIVISION BY ZER", 'O' | $80
ERRDV0 = $85                        ;; offset of DIVISION BY ZERO in <ERRTAB>
Q .set $95
    .byte "ILLEGAL DIREC", 'T' | $80
ERRID = $95                         ;; offset of ILLEGAL DIRECT in <ERRTAB>
Q .set $A3
    .byte "TYPE MISMATC", 'H' | $80
ERRTM = $A3                         ;; offset of TYPE MISMATCH in <ERRTAB>
Q .set $B0
    .byte "STRING TOO LON", 'G' | $80
ERRLS = $B0                         ;; offset of STRING TOO LONG in <ERRTAB>
Q .set $BF
    .byte "FORMULA TOO COMPLE", 'X' | $80
ERRST = $BF                         ;; offset of FORMULA TOO COMPLEX in <ERRTAB>
Q .set $D2
    .byte "CAN'T CONTINU", 'E' | $80
ERRCN = $D2                         ;; offset of CAN'T CONTINUE in <ERRTAB>
Q .set $E0
    .byte "UNDEF'D FUNCTIO", 'N' | $80
ERRUF = $E0                         ;; offset of UNDEF'D FUNCTION in <ERRTAB>

;; Error suffix: a space, ERROR, a bell and a zero terminator.
ERR:
    .byte " ERROR", $07, $00

;; Line-number introduction: a space, IN, a space and a zero terminator.
INTXT:
    .byte " IN ", $00

;; Break message: carriage return, BREAK, a bell and a zero terminator.
BRKTXT:
    .byte $0D, "BREAK", $07, $00
REDDY = $00                         ;; legacy READY message offset (no READY string is stored here)
GOTK = $FF                          ;; legacy GO token value; no GO spelling occurs in <RESLST>
FORSIZ = $12                        ;; size in bytes of a FOR stack frame
