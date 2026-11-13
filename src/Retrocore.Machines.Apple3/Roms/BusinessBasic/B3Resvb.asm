; B3RESVB: BASIC's keywords and their tokens, the operators, the error messages, and the SOS errors BASIC turns into
; its own.
;
; A program is kept as tokens: each keyword in RESLST is one byte, its token, from $80 for END. The keywords in RESL2
; (operators, functions and words that only follow others) are two bytes: $FF, then the keyword's token, from $80
; for TAB(. Each keyword's token is its place in its table plus $80, and is in the comment beside it. The names of
; the form "A " hold tokens with no keyword.
;
; Names follow Apple's Business BASIC 1.3 listing.

;; Ends the statement with a TYPE MISMATCH error.
;; See: <ERROR>
TMERR:
    ldx #ERRTM
    jmp ERROR

; ---------------------------------------------------------------------------------------------------------------------
; Statements and the words that give a value
; ---------------------------------------------------------------------------------------------------------------------

;; The keywords with one-byte tokens, from $80 to $E0, each with the last character's bit 7 set.
;;
;; The statements' routines are in <STMDSP>, in the same order. FRE to EOF and the words to EXFN%. give a value with
;; no parentheses, through <RESTBL>; some of them are statements as well. From LOAD on are the file commands, whose
;; file names CRUNCH leaves as typed.
;; See: <RESL2>, <STMDSP>, <CRUNCH>
RESLST:
    DCI "END"                               ; $80
ENDTK = $80                                 ;; END's token, the first one-byte token
    DCI "FOR"                               ; $81
FORTK = ENDTK+1                             ;; FOR's token, $81
    DCI "NEXT"                              ; $82
    DCI "INPUT"                             ; $83
INPTKN = FORTK+2                            ;; INPUT's token, $83
    DCI "OUTPUT"                            ; $84
OUTTKN = INPTKN+1                           ;; OUTPUT's token, $84
    DCI "DIM"                               ; $85
    DCI "READ"                              ; $86
    DCI "WRITE"                             ; $87
    DCI "OPEN"                              ; $88
OPENTK = OUTTKN+4                           ;; OPEN's token, $88
    DCI "CLOSE"                             ; $89
    DCI "A "                                ; $8A, unused
    DCI "TEXT"                              ; $8B
TEXTTK = OPENTK+3                           ;; TEXT's token, $8B
    DCI "A "                                ; $8C, unused
    DCI "BYE"                               ; $8D
    DCI "A "                                ; $8E, unused
    DCI "A "                                ; $8F, unused
    DCI "A "                                ; $90, unused
    DCI "A "                                ; $91, unused
    DCI "A "                                ; $92, unused
    DCI "WINDOW"                            ; $93
    DCI "INVOKE"                            ; $94
INVOKTK = TEXTTK+9                          ;; INVOKE's token, $94
    DCI "PERFORM"                           ; $95
    DCI "A "                                ; $96, unused
    DCI "A "                                ; $97, unused
    DCI "FRE"                               ; $98
FRETK = INVOKTK+4                           ;; FRE's token, $98, the first in RESTBL
    DCI "HPOS"                              ; $99
HPOSTK = FRETK+1                            ;; HPOS's token, $99
    DCI "VPOS"                              ; $9A
VPOSTK = HPOSTK+1                           ;; VPOS's token, $9A
    DCI "ERRLIN"                            ; $9B
ERRLINTK = VPOSTK+1                         ;; ERRLIN's token, $9B
    DCI "ERR"                               ; $9C
ERRTK = ERRLINTK+1                          ;; ERR's token, $9C
    DCI "KBD"                               ; $9D
KBDTK = ERRTK+1                             ;; KBD's token, $9D
    DCI "EOF"                               ; $9E
EOFTK = KBDTK+1                             ;; EOF's token, $9E
    DCI "TIME$"                             ; $9F
    DCI "DATE$"                             ; $A0
    DCI "PREFIX$"                           ; $A1
    DCI "EXFN."                             ; $A2
    DCI "EXFN%."                            ; $A3
EXFNSTK = EOFTK+5                           ;; EXFN%.'s token, $A3
    DCI "OUTREC"                            ; $A4
    DCI "INDENT"                            ; $A5
.if VERSION >= 130
    DCI "PROGPREFIX$"                       ; $A6
.else
    DCI "A "                                ; $A6, unused
.endif
    DCI "A "                                ; $A7, unused
    DCI "A "                                ; $A8, unused
    DCI "A "                                ; $A9, unused
    DCI "A "                                ; $AA, unused
    DCI "A "                                ; $AB, unused
    DCI "A "                                ; $AC, unused
    DCI "POP"                               ; $AD
POPTKN = EXFNSTK+10                         ;; POP's token, $AD, the first past RESTBL's words
    DCI "HOME"                              ; $AE
.if DEBUG
    DCI "SHIT"                              ; $AF, the debugger's command, in the debugger build
.else
    DCI "A   "                              ; $AF, unused
.endif
    DCI "SUB$("                             ; $B0
    DCI "OFF"                               ; $B1
    DCI "TRACE"                             ; $B2
    DCI "NOTRACE"                           ; $B3
    DCI "NORMAL"                            ; $B4
    DCI "INVERSE"                           ; $B5
    DCI "SCALE("                            ; $B6
SCALETK = POPTKN+9                          ;; SCALE('s token, $B6
    DCI "RESUME"                            ; $B7
    DCI "A "                                ; $B8, unused
    DCI "LET"                               ; $B9
    DCI "GOTO"                              ; $BA
GOTOTK = SCALETK+4                          ;; GOTO's token, $BA
    DCI "IF"                                ; $BB
IFTOKN = GOTOTK+1                           ;; IF's token, $BB
    DCI "RESTORE"                           ; $BC
    DCI "SWAP"                              ; $BD
    DCI "GOSUB"                             ; $BE
GOSUTK = IFTOKN+3                           ;; GOSUB's token, $BE
    DCI "RETURN"                            ; $BF
    DCI "REM"                               ; $C0
REMTK = GOSUTK+2                            ;; REM's token, $C0
    DCI "STOP"                              ; $C1
    DCI "ON"                                ; $C2
    DCI "A "                                ; $C3, unused
    DCI "LOAD"                              ; $C4
LDTKN = REMTK+4                             ;; LOAD's token, $C4, the first of the file commands
    DCI "SAVE"                              ; $C5
    DCI "DELETE"                            ; $C6
    DCI "RUN"                               ; $C7
    DCI "RENAME"                            ; $C8
RENMTK = LDTKN+4                            ;; RENAME's token, $C8
    DCI "LOCK"                              ; $C9
    DCI "UNLOCK"                            ; $CA
    DCI "CREATE"                            ; $CB
    DCI "EXEC"                              ; $CC
    DCI "CHAIN"                             ; $CD
    DCI "A "                                ; $CE, unused
    DCI "A "                                ; $CF, unused
    DCI "A "                                ; $D0, unused
    DCI "CATALOG"                           ; $D1
CATATK = RENMTK+9                           ;; CATALOG's token, $D1
    DCI "A "                                ; $D2, unused
    DCI "A "                                ; $D3, unused
DSKCOMS = CATATK+2                          ;; $D3, the last of the file commands' tokens
    DCI "DATA"                              ; $D4
DATATK = DSKCOMS+1                          ;; DATA's token, $D4
    DCI "IMAGE"                             ; $D5
IMAGETK = DATATK+1                          ;; IMAGE's token, $D5
    DCI "CAT"                               ; $D6
CATTK = IMAGETK+1                           ;; CAT's token, $D6
    DCI "DEF"                               ; $D7
    DCI "A "                                ; $D8, unused
    DCI "PRINT"                             ; $D9
PRINTK = CATTK+3                            ;; PRINT's token, $D9
    DCI "DEL"                               ; $DA
    DCI "ELSE"                              ; $DB
ELSETK = PRINTK+2                           ;; ELSE's token, $DB
    DCI "CONT"                              ; $DC
    DCI "LIST"                              ; $DD
    DCI "CLEAR"                             ; $DE
    DCI "GET"                               ; $DF
    DCI "NEW"                               ; $E0
SCRATK = ELSETK+5                           ;; NEW's token, $E0, the last one-byte token

; ---------------------------------------------------------------------------------------------------------------------
; Operators, functions and other words
; ---------------------------------------------------------------------------------------------------------------------

;; The keywords with two-byte tokens, $FF and then $80-$D3, each with the last character's bit 7 set.
;;
;; From SGN( (<ONEFUN>) on are the functions, whose routines are in <FUNDSP> in the same order; those past <LASNUM>
;; take more than one argument. The list ends with a zero.
;; See: <RESLST>, <FUNDSP>
RESL2:
    DCI "TAB("                              ; $80
TABTK = $80                                 ;; TAB('s token, the first two-byte token after $FF
    DCI "TO"                                ; $81
TOTK = TABTK+1                              ;; TO's token, $81
    DCI "SPC("                              ; $82
SPCTK = TOTK+1                              ;; SPC('s token, $82
    DCI "USING"                             ; $83
USINGTK = SPCTK+1                           ;; USING's token, $83
    DCI "THEN"                              ; $84
THENTK = USINGTK+1                          ;; THEN's token, $84
    DCI "A "                                ; $85, unused
ATTKN = THENTK+1                            ;; $85, a token named for AT, which has no keyword
    DCI "MOD"                               ; $86
MODTK = ATTKN+1                             ;; MOD's token, $86
    DCI "STEP"                              ; $87
STEPTK = MODTK+1                            ;; STEP's token, $87
    DCI "AND"                               ; $88
ANDTK = STEPTK+1                            ;; AND's token, $88
    DCI "OR"                                ; $89
ORTK = ANDTK+1                              ;; OR's token, $89
    DCI "EXTENSION"                         ; $8A
EXTKN = ORTK+1                              ;; EXTENSION's token, $8A
    DCI "DIV"                               ; $8B
DIVTK = EXTKN+1                             ;; DIV's token, $8B
    DCI "A "                                ; $8C, unused
    DCI "FN"                                ; $8D
FNTK = DIVTK+2                              ;; FN's token, $8D
    DCI "NOT"                               ; $8E
NOTTK = FNTK+1                              ;; NOT's token, $8E
    DCI "A "                                ; $8F, unused
    DCI "A "                                ; $90, unused
    DCI "A "                                ; $91, unused
    DCI "A "                                ; $92, unused
    DCI "A "                                ; $93, unused
    DCI "A "                                ; $94, unused
    DCI "A "                                ; $95, unused
    DCI "A "                                ; $96, unused
    DCI "A "                                ; $97, unused
    DCI "A "                                ; $98, unused
    DCI "A "                                ; $99, unused
    DCI "A "                                ; $9A, unused
    DCI "A "                                ; $9B, unused
    DCI "AS"                                ; $9C
ASTKN = NOTTK+14                            ;; AS's token, $9C
    DCI "SGN("                              ; $9D
ONEFUN = ASTKN+1                            ;; SGN('s token, $9D, the first function's
    DCI "INT("                              ; $9E
    DCI "ABS("                              ; $9F
    DCI "A "                                ; $A0, unused
    DCI "TYP("                              ; $A1
    DCI "REC("                              ; $A2
    DCI "A "                                ; $A3, unused
    DCI "A "                                ; $A4, unused
    DCI "A "                                ; $A5, unused
    DCI "A "                                ; $A6, unused
    DCI "A "                                ; $A7, unused
    DCI "A "                                ; $A8, unused
    DCI "A "                                ; $A9, unused
    DCI "A "                                ; $AA, unused
    DCI "A "                                ; $AB, unused
    DCI "A "                                ; $AC, unused
    DCI "PDL("                              ; $AD
    DCI "BUTTON("                           ; $AE
    DCI "SQR("                              ; $AF
    DCI "RND("                              ; $B0
    DCI "LOG("                              ; $B1
    DCI "EXP("                              ; $B2
    DCI "COS("                              ; $B3
    DCI "SIN("                              ; $B4
    DCI "TAN("                              ; $B5
    DCI "ATN("                              ; $B6
    DCI "A "                                ; $B7, unused
    DCI "A "                                ; $B8, unused
    DCI "A "                                ; $B9, unused
    DCI "A "                                ; $BA, unused
    DCI "A "                                ; $BB, unused
    DCI "A "                                ; $BC, unused
    DCI "A "                                ; $BD, unused
    DCI "A "                                ; $BE, unused
    DCI "A "                                ; $BF, unused
    DCI "A "                                ; $C0, unused
    DCI "A "                                ; $C1, unused
    DCI "A "                                ; $C2, unused
    DCI "STR$("                             ; $C3
STRTK = ONEFUN+38                           ;; STR$('s token, $C3
    DCI "HEX$("                             ; $C4
HEXTK = STRTK+1                             ;; HEX$('s token, $C4
    DCI "CHR$("                             ; $C5
CHRTK = HEXTK+1                             ;; CHR$('s token, $C5
    DCI "LEN("                              ; $C6
LENTK = CHRTK+1                             ;; LEN('s token, $C6
    DCI "VAL("                              ; $C7
    DCI "ASC("                              ; $C8
    DCI "TEN("                              ; $C9
    DCI "A "                                ; $CA, unused
DEXPTK = LENTK+4                            ;; $CA, a token with no keyword
    DCI "A "                                ; $CB, unused
DLOGTK = DEXPTK+1                           ;; $CB, a token with no keyword
    DCI "CONV("                             ; $CC
CONVTK = DLOGTK+1                           ;; CONV('s token, $CC
    DCI "CONV&("                            ; $CD
    DCI "CONV$("                            ; $CE
    DCI "CONV%("                            ; $CF
LASNUM = CONVTK+3                           ;; CONV%('s token, $CF, the last function with one argument
    DCI "LEFT$("                            ; $D0
    DCI "RIGHT$("                           ; $D1
    DCI "MID$("                             ; $D2
    DCI "INSTR("                            ; $D3
INSTRTK = LASNUM+4                          ;; INSTR('s token, $D3, the last
    .byte 0                                 ; The end of the list
RELNOT = 4                                  ;; added to an operator's place in OPTAB to give its number

;; The operators, as the expression evaluator looks for them: the relational characters, then ^, AND, OR, MOD, DIV,
;; /, *, - and +, and a zero for the end of the expression.
;;
;; AND, OR, MOD and DIV are their tokens in <RESL2>; the others are characters. An operator's number is its place
;; here plus <RELNOT>, except that the relational ones combine into 1-7 (1 for >, 2 for =, 4 for <).
;; See: <PRECTB>, <OPDSPT>, <FRMEVL>
OPTAB:
    .byte '>', '=', '<'
RELOPS = *-OPTAB+RELNOT                     ;; 7, the highest relational operator's number
    .byte $5E, ANDTK, ORTK, MODTK           ; ^ is $5E
    .byte DIVTK, '/', '*', '-'
    .byte '+', 0
ENDOP = *-OPTAB+RELNOT                      ;; 17, the number of the end of the expression
NUMOPS = *-OPTAB                            ;; 13, the count of entries in OPTAB

; ---------------------------------------------------------------------------------------------------------------------
; Error messages
; ---------------------------------------------------------------------------------------------------------------------

;; The error messages, each with the last character's bit 7 set, in the order of their numbers from 1.
;;
;; The message is followed by <ERR>, then " IN " and the line number when a program was running.
;; See: <ERROR>, <ERRNUM>
ERRTAB:
    DCI "NEXT WITHOUT FOR"                  ; error 1
ERRNF = 1                                   ;; NEXT WITHOUT FOR
    DCI "SYNTAX"                            ; error 2
ERRSN = ERRNF+1                             ;; SYNTAX, 2
    DCI "RETURN WITHOUT GOSUB"              ; error 3
ERRRG = ERRSN+1                             ;; RETURN WITHOUT GOSUB, 3
    DCI "OUT OF DATA"                       ; error 4
ERROD = ERRRG+1                             ;; OUT OF DATA, 4
    DCI "ILLEGAL QUANTITY"                  ; error 5
ERRFC = ERROD+1                             ;; ILLEGAL QUANTITY, 5
    DCI "OVERFLOW"                          ; error 6
ERROV = ERRFC+1                             ;; OVERFLOW, 6
    DCI "OUT OF MEMORY"                     ; error 7
ERROM = ERROV+1                             ;; OUT OF MEMORY, 7
    DCI "UNDEF'D STATEMENT"                 ; error 8
ERRUS = ERROM+1                             ;; UNDEF'D STATEMENT, 8
    DCI "BAD SUBSCRIPT"                     ; error 9
ERRBS = ERRUS+1                             ;; BAD SUBSCRIPT, 9
    DCI "RANGE"                             ; error 10
ERRNG = ERRBS+1                             ;; RANGE, 10
    DCI "INVOKE"                            ; error 11
ERRIN = ERRNG+1                             ;; INVOKE, 11
    DCI "STACK OVERFLOW"                    ; error 12
ERRSK = ERRIN+1                             ;; STACK OVERFLOW, 12
    DCI "REDIM'D ARRAY"                     ; error 13
ERRDD = ERRSK+1                             ;; REDIM'D ARRAY, 13
    DCI "DIVISION BY ZERO"                  ; error 14
ERRDV0 = ERRDD+1                            ;; DIVISION BY ZERO, 14
    DCI "ILLEGAL DIRECT"                    ; error 15
ERRID = ERRDV0+1                            ;; ILLEGAL DIRECT, 15
    DCI "TYPE MISMATCH"                     ; error 16
ERRTM = ERRID+1                             ;; TYPE MISMATCH, 16
    DCI "STRING TOO LONG"                   ; error 17
ERRLS = ERRTM+1                             ;; STRING TOO LONG, 17
    DCI "FORMULA TOO COMPLEX"               ; error 18
ERRST = ERRLS+1                             ;; FORMULA TOO COMPLEX, 18
    DCI "CAN'T CONTINUE"                    ; error 19
ERRCN = ERRST+1                             ;; CAN'T CONTINUE, 19
    DCI "UNDEF'D FUNCTION"                  ; error 20
ERRUF = ERRCN+1                             ;; UNDEF'D FUNCTION, 20
    DCI "VARIABLE"                          ; error 21
ERRVA = ERRUF+1                             ;; VARIABLE, 21
    DCI "SOS CALL"                          ; error 22
SSSSSS = ERRVA+1                            ;; SOS CALL, 22: a SOS error with no message of its own, its code in SOSLOC
    DCI "FILES BUSY"                        ; error 23
ERRFB = SSSSSS+1                            ;; FILES BUSY, 23
    DCI "NOT SOS"                           ; error 24
ERRNS = ERRFB+1                             ;; NOT SOS, 24
    DCI "I/O"                               ; error 25
ERRIO = ERRNS+1                             ;; I/O, 25
    DCI "FILE TOO LARGE"                    ; error 26
ERRCR = ERRIO+1                             ;; FILE TOO LARGE, 26
    DCI "WRITE PROTECT"                     ; error 27
ERRWP = ERRCR+1                             ;; WRITE PROTECT, 27
    DCI "DISK SWITCHED"                     ; error 28
ERRDS = ERRWP+1                             ;; DISK SWITCHED, 28
    DCI "BAD PATH"                          ; error 29
ERRBP = ERRDS+1                             ;; BAD PATH, 29
    DCI "FILE NOT FOUND"                    ; error 30
ERRFN = ERRBP+1                             ;; FILE NOT FOUND, 30
    DCI "PATH NOT FOUND"                    ; error 31
ERRPN = ERRFN+1                             ;; PATH NOT FOUND, 31
    DCI "VOLUME NOT FOUND"                  ; error 32
ERRVN = ERRPN+1                             ;; VOLUME NOT FOUND, 32
    DCI "DUPLICATE FILE"                    ; error 33
ERRDF = ERRVN+1                             ;; DUPLICATE FILE, 33
    DCI "DISK FULL"                         ; error 34
ERRFU = ERRDF+1                             ;; DISK FULL, 34
    DCI "FILE LOCKED"                       ; error 35
ERRFL = ERRFU+1                             ;; FILE LOCKED, 35
    DCI "FILE NOT OPEN"                     ; error 36
ERRNO = ERRFL+1                             ;; FILE NOT OPEN, 36
    DCI "DEVICE DISCONNECTED"               ; error 37
ERRDO = ERRNO+1                             ;; DEVICE DISCONNECTED, 37
    DCI "RESOURCE UNAVAILABLE"              ; error 38
ERRDU = ERRDO+1                             ;; RESOURCE UNAVAILABLE, 38
    DCI "DIRECTORY FULL"                    ; error 39
ERRFD = ERRDU+1                             ;; DIRECTORY FULL, 39
    DCI "DUPLICATE VOLUME"                  ; error 40
ERRDV = ERRFD+1                             ;; DUPLICATE VOLUME, 40

;; " ERROR" and a bell, which follow every error message, ending in a zero.
ERR:
    .byte " ERROR"
    .byte 7, 0

;; The run-time build's message after a program ends, asking for the space bar before BASIC starts again.
RTMSG:
    .byte 13, 10, 10                        ; Return, line feed, line feed
    .byte "Please Press SPACE BAR"
    .byte 0

;; " IN ", between an error message and its line number.
INTXT:
    .byte " IN "
    .byte 0

;; The message for CONTROL-C, with the screen turned back on and a bell.
BRKTXT:
    .byte 13, 10, 10, 15                    ; Return, line feed, line feed, and 15 turns the screen on
    .byte "PROGRAM INTERRUPTED"
    .byte 7, 0

; ---------------------------------------------------------------------------------------------------------------------
; SOS errors
; ---------------------------------------------------------------------------------------------------------------------

;; Pairs of a SOS error code and the BASIC error <SERROR> gives for it, in rising order of the code, ending with $FF.
;;
;; The search stops at the first code higher than the one it has. A code not here gives SOS CALL (<SSSSSS>), with
;; the code in <SOSLOC>.
;; See: <SERROR>
ERRTBL:
    .byte $10, ERRFN                        ; No such device
    .byte $25, ERRDU                        ; No resource
    .byte $27, ERRIO                        ; I/O error
    .byte $28, ERRDO                        ; No drive
    .byte $2B, ERRWP                        ; Write-protected
    .byte $2E, ERRDS                        ; The disk was switched
    .byte $40, ERRBP                        ; Bad pathname
    .byte $43, ERRNO                        ; Bad reference number
    .byte $44, ERRPN                        ; Path not found
    .byte $45, ERRVN                        ; Volume not found
    .byte $46, ERRFN                        ; File not found
    .byte $47, ERRDF                        ; Duplicate file
    .byte $48, ERRFU                        ; Disk full
    .byte $49, ERRFD                        ; Directory full
    .byte $4D, ERRCR                        ; Position out of range
    .byte $4E, ERRFL                        ; Access not allowed
    .byte $50, ERRFB                        ; File busy
    .byte $51, ERRNS                        ; Directory error
    .byte $52, ERRNS                        ; Not a SOS volume, such as an Apple II Pascal disk
    .byte $54, ERROM                        ; Out of memory
    .byte $57, ERRDV                        ; Duplicate volume
    .byte $58, ERRTM                        ; Not a block device
    .byte $FF                               ; The end

; ---------------------------------------------------------------------------------------------------------------------
; X-bytes of BASIC's own tables
;
; Routines that read through a pointer with its X-byte take these for tables in BASIC itself: zero, so the access
; reads the bank that is switched in.
; ---------------------------------------------------------------------------------------------------------------------

ERRTABB = 0                                 ;; the X-byte for <ERRTAB> and the other messages
RESLSTB = ERRTABB                           ;; the X-byte for <RESLST> and <RESL2>
NUMSTRB = 0                                 ;; the X-byte for <NUMSTR>
CON1MB = 0                                  ;; the X-byte for <CON1M>, -1
FHALFB = 0                                  ;; the X-byte for <FHALF>, one half
SQR0B = 0                                   ;; the X-byte for <SQR0_5> and LOG's other constants
TEN_CB = 0                                  ;; the X-byte for <TEN_C>, ten, and for <FDIVF>'s divisor
INTXTB = 0                                  ;; the X-byte for <INTXT>
N_MILB = 0                                  ;; the X-byte for <N_0999> and <N_9999>
TEMPF3B = 0                                 ;; the X-byte for <TEMPF3>, in zero page
RNDXB = 0                                   ;; the X-byte for <RNDX>, in zero page
