; INVOKE: loading, relocating and linking the modules INVOKE names, and calling them: PERFORM for a procedure, EXFN.
; and EXFN%. for a function.
;
; A module is a code file (type 2) from the Pascal assembler, which BASIC loads much as Pascal's linker would:
;
; - The first block is the segment dictionary. BASIC takes only the code's length from it, the word at offset 6.
; - The code follows, from the second block. It ends with its procedure dictionary: the last word holds the count of
;   procedures in its high byte, and each word below it, one per procedure from 1 up, is a self-relative pointer to
;   the procedure's attribute table.
; - The linker information starts at the next block boundary and runs to the end of the file, in 16-byte records.
;
; Each procedure's attribute table, read downward from the pointer, holds a self-relative pointer to its entry
; point, then four relocation lists, each a count and that many self-relative pointers: base-relative,
; segment-relative, procedure-relative and interpreter-relative. BASIC applies the middle two and refuses a module
; that has either of the others.
;
; A linker record holds an 8-character name, its type at offset 8, and two words at offsets 10 and 12:
;
; - Type 11, .PROC, and 12, .FUNC: the procedure's number, then its count of parameter words.
; - Type 6, .DEF: the number of the procedure holding the label, then the label's offset from that procedure's entry.
; - Type 2, .REF: then the count of references; the offsets of the words that refer to the name follow the record,
;   padded to a multiple of 16 bytes.
; - Type 0 ends the records.
;
; Names follow Apple's Business BASIC 1.3 listing.

OFFSST = FORPNT                             ;; the address a self-relative pointer gives, from <RELPROC>
PROCPNT = INPPTR                            ;; the walking pointer: down the code's dictionaries, then along the records
SWPPNT = LOWDS                              ;; the zero-page pointer whose value <DOAREL> adds: <POINT1> or <HIGHTR>
TEMPTR = HEADER                             ;; <DOAREL>'s count of words left to relocate
POINT1 = INDEX1                             ;; the start of the module's code
POINT1B = POINT1+SYSPAG                     ;; <POINT1>'s bank byte
POINT2 = INDEX2                             ;; a second pointer: into the procedure dictionary, to a record, or a value
POINT2B = POINT2+SYSPAG                     ;; <POINT2>'s bank byte
PROCPNTB = PROCPNT+SYSPAG                   ;; <PROCPNT>'s bank byte
OFFSSTB = OFFSST+SYSPAG                     ;; <OFFSST>'s bank byte
SWPPNTB = SWPPNT+SYSPAG                     ;; <SWPPNT>'s bank byte, 0 to read the zero page directly

; The names above borrow other routines' zero-page space; a clash is fixed by changing an equate.

; ---------------------------------------------------------------------------------------------------------------------
; Loading
; ---------------------------------------------------------------------------------------------------------------------

;; Ends the statement with an out-of-memory error: there is no room for a module's first block.
INERROM:
    jmp OMERR

;; Loads, relocates and links each module the statement names, then moves the records kept up against the code.
;;
;; The free memory runs from <INVTAB> to <PROCTAB>, in one bank. Each module's code goes at the top of what is left,
;; below the module before it, and its linker records at <INVPNT>, after those kept from the module before. Only the
;; .PROC and .FUNC records are kept, for <PERFIND>.
;; In: TXTPTR = the first file name, INVTAB = the free memory's start, PROCTAB = its end
;; Out: INVPNT = the start of the records kept, which end just below the code
;; See: <INVOKE>, <DOAPROC>, <DOLIB>, <DOPAS2>, <DOCRNCH>
DOINVO:
    lda #0
    sta HEADERB
    sta SWPPNTB
    lda INVTAB
    sta INVPNT
    lda INVTAB+1
    sta INVPNT+1
    lda INVTABB
    sta INVPNTB
    lda PROCTAB
    ldx PROCTAB+1
    sta PROCPNT
    stx PROCPNT+1
    lda PROCTABB
    sta PROCPNTB
    sta OFFSSTB

;; Loads the next module, or ends with <DOCRNCH> at the statement's end.
;;
;; The file's first block is read at <INVPNT> for the code's length; the code is read to just below <PROCPNT>; then
;; the linker information, from the next block boundary to the end of the file, is read at INVPNT.
DOFILE:
    jsr CHRGOT
    bne *+5
    jmp DOCRNCH                             ; no more names
    lda #1
    jsr OPNPRTB                             ; open it to read
    jsr CHRGOT
    beq *+5
    jsr CHKCOM                              ; another name follows a comma
    lda #<(INVPNT)                          ; read through the pointer in INVPNT
    sta SBFPTR
    lda #>(INVPNT)
    sta SBFPTR+1
    lda #0
    sta INBYTES
    lda #2                                  ; one block
    sta INBYTES+1
    sec
    lda PROCPNT+1
    sbc INVPNT+1
    cmp #3                                  ; room for the block?
    bcc INERROM
    ldy #RED
    jsr SETGO
    ldy #7
    lda (INVPNT),Y                          ; the code's length
    sta INBYTES+1
    dey
    lda (INVPNT),Y
    sta INBYTES
    sec
    lda PROCPNT
    sbc INBYTES                             ; the code goes just below PROCPNT
    sta POINT1
    lda PROCPNT+1
    sbc INBYTES+1
    sta POINT1+1
    lda INVPNTB
    sta POINT1B
    lda #<(POINT1)
    sta SBFPTR
    lda #>(POINT1)
    sta SBFPTR+1
    ldy #RED                                ; the code alone
    jsr SETGO
    ldy #GTM
    jsr SETGO
    lda OUTMRK                              ; round the mark up to a page
    beq MARKLOW
    inc OUTMRK+1
MARKLOW:
    lda OUTMRK+1                            ; then up to a block
    lsr
    adc #0
    asl
    sta OUTMRK+1+1                          ; SET_MARK's displacement starts a byte later than GET_MARK's mark
    lda #0
    sta OUTMRK+1
    sta OUTMRK+1+3
    sta BASE                                ; from the start of the file
    ldy #STM
    jsr SETGO
    sec
    lda POINT1                              ; the linker information: up to all the room below the code
    sbc INVPNT
    sta INBYTES
    lda #<(INVPNT)
    sta SBFPTR
    lda POINT1+1
    sbc INVPNT+1
    sta INBYTES+1
    lda #>(INVPNT)
    sta SBFPTR+1
    ldy #RED                                ; to the end of the file
    jsr SETGO
    jsr CLSEND
    jsr DEC2PROC                            ; the code's last word
    ldy #1
    lda (PROCPNT),Y
    sta KIMY                                ; the count of procedures
    lda PROCPNT                             ; kept for DOLIB
    pha
    lda PROCPNT+1
    pha

; ---------------------------------------------------------------------------------------------------------------------
; Relocating
; ---------------------------------------------------------------------------------------------------------------------

;; Relocates one procedure: puts its entry point's address in its procedure dictionary entry, then applies its
;; segment-relative and procedure-relative relocation lists.
;;
;; A nonzero count of base-relative or interpreter-relative relocations is an invoke error. When the last procedure
;; is done, linking goes on at <DOLIB>.
;; In: PROCPNT = the word above the procedure's dictionary entry, KIMY = the count of procedures left
;; See: <RELPROC>, <DOAREL>, <MAKESUR0>
DOAPROC:
    jsr RELPROC                             ; the attribute table
    lda PROCPNT
    sta POINT2                              ; the dictionary entry
    lda OFFSST
    sta PROCPNT
    lda PROCPNT+1
    sta POINT2+1
    lda OFFSST+1
    sta PROCPNT+1
    lda PROCPNTB
    sta POINT2B
    jsr RELPROC                             ; the entry point
    ldy #0
    lda OFFSST
    sta HIGHTR                              ; the base for procedure-relative relocation
    sta (POINT2),Y                          ; and the dictionary entry's new value
    iny
    lda OFFSST+1
    cmp #$82                                ; keep the page in BASIC's range, $02-$81
    bcc *+4
    sbc #$80
    sta HIGHTR+1
    sta (POINT2),Y
    jsr MAKESUR0                            ; no base-relative relocations
    lda #<(POINT1)                          ; segment-relative: add the code's start
    sta SWPPNT
    lda #>(POINT1)
    sta SWPPNT+1
    jsr DOAREL
    lda #>(HIGHTR)                          ; procedure-relative: add the entry point
    sta SWPPNT+1
    lda #<(HIGHTR)
    sta SWPPNT
    jsr DOAREL
    jsr MAKESUR0                            ; no interpreter-relative relocations
    dec KIMY
    beq DOLIB
    lda POINT2
    sta PROCPNT
    lda POINT2+1
    sta PROCPNT+1
    jmp DOAPROC

; ---------------------------------------------------------------------------------------------------------------------
; Linking
; ---------------------------------------------------------------------------------------------------------------------

;; Linking's first pass: replaces the procedure number in each .PROC, .FUNC and .DEF record with that procedure's
;; entry point, from the procedure dictionary.
;;
;; A record of any type but these, .REF and the end is an invoke error. The procedure dictionary's top is on the
;; stack, from <DOFILE>.
;; In: INVPNT = the module's records
;; See: <DOPA11>, <DOPAS2>
DOLIB:
    pla
    sta POINT2+1
    dec POINT2+1                            ; a page lower, so (POINT2),Y reaches down from Y = 256
    pla
    sta POINT2
    lda INVPNT
    sta PROCPNT
    lda INVPNT+1
    sta PROCPNT+1
    ldy #8
    lda (PROCPNT),Y                         ; the record's type

;; Takes the record at <PROCPNT> in the first pass.
;; In: A = its type
DOPAS1:
    beq DOPAS2                              ; the end
    cmp #$B                                 ; .PROC
    beq DOPA11
    cmp #$C                                 ; .FUNC
    beq DOPA11
    cmp #$6                                 ; .DEF
    beq DOPA11
    cmp #$2                                 ; .REF
    beq DOPA12
    jmp INVERROR

;; Moves <PROCPNT> past a .REF record's list of references, the count at offset 12 rounded up to 8 words, so that
;; <NXTPROC> then reaches the next record.
;; In: PROCPNT = the .REF record
;; Uses: A, Y, TEMP
DOPA13:
    ldy #12
    lda (PROCPNT),Y                         ; the count
    sta TEMP
    and #$F8
    cmp TEMP
    beq *+8                                 ; already a multiple of 8
    adc #$8
    bcc *+4
    inc PROCPNT+1
    asl                                     ; words to bytes
    bcc *+4
    inc PROCPNT+1
    jmp ADDPROC

;; Skips a .REF record in the first pass.
DOPA12:
    jsr DOPA13
    jmp DOPA14

;; Replaces a .PROC's, .FUNC's or .DEF's procedure number, at offset 10, with the procedure's entry point.
DOPA11:
    ldy #10
    lda #0
    sec
    sbc (PROCPNT),Y
    asl                                     ; the number times -2: the entry's offset below the dictionary's top
    tay
    lda (POINT2),Y
    tax
    iny
    lda (POINT2),Y
    ldy #11
    sta (PROCPNT),Y
    txa
    dey
    sta (PROCPNT),Y

;; Moves on to the next record in the first pass.
DOPA14:
    jsr NXTPROC
    bne DOPAS1

;; Linking's second pass: for each .REF record, finds the .DEF of the same name and adds the label's offset in the
;; code to each word that refers to it.
;;
;; A name with no .DEF is an invoke error. <PERFIND> searches from <INVTAB>, where the modules before this one have
;; kept only their .PROC and .FUNC records, so the .DEF must be in the same module.
;; See: <DOPA25>
DOPAS2:
    lda INVPNT
    sta PROCPNT
    lda INVPNT+1
    sta PROCPNT+1

;; Takes the record at <PROCPNT> in the second pass.
DOPA20:
    ldy #8
    lda (PROCPNT),Y
DOPA22:
    bne *+5
    jmp DOPAS3                              ; the end
    cmp #2
    bne DOPA29                              ; only .REF records matter here
    lda PROCPNT
    sta POINT2
    lda PROCPNT+1
    sta POINT2+1
    lda #6
    sta PROCFLG                             ; look for a .DEF of this name
    jsr PERFIND
    bne DOPA25
    jmp INVERROR

;; Moves on to the next record in the second pass.
DOPA29:
    jsr NXTPROC
    jmp DOPA22

;; Adds the .DEF's offset in the code to each word the .REF record at <POINT2> lists, then moves past the list.
;;
;; With exactly 248 references, the step past the list's padding also adds a page to <PROCPNT>.
;; In: PROCPNT = the .DEF record, POINT2 = the .REF record
DOPA25:
    ldy #10
    lda (PROCPNT),Y                         ; the procedure's entry plus the label's offset
    clc
    ldy #12
    adc (PROCPNT),Y
    tax
    dey
    lda (PROCPNT),Y
    ldy #13
    adc (PROCPNT),Y
    pha
    txa
    sec
    sbc POINT1                              ; less the code's start
    tax
    pla
    sbc POINT1+1
    ldy POINT2+1
    sta POINT2+1
    sty PROCPNT+1
    lda POINT2                              ; PROCPNT back to the .REF, and POINT2 the label's offset
    stx POINT2
    sta PROCPNT
    ldy #12
    lda (PROCPNT),Y                         ; the count of references
    sta KIMY
    tax
    beq DOPA29
    jsr NXTPROC                             ; the list
DOPA27:
    ldy #0
    clc
    lda POINT1                              ; the referring word's address
    adc (PROCPNT),Y
    sta OFFSST
    iny
    lda POINT1+1
    adc (PROCPNT),Y
    sta OFFSST+1
    clc
    dey
    lda POINT2
    adc (OFFSST),Y
    sta (OFFSST),Y
    iny
    lda POINT2+1
    adc (OFFSST),Y
    sta (OFFSST),Y
    lda #2
    jsr ADDPROC
    dex
    bne DOPA27
    lda KIMY                                ; skip the padding to a multiple of 8 words
    eor #$7
    clc
    adc #1
    bcc *+4
    inc PROCPNT+1
    and #$7
    asl
    bcc *+4
    inc PROCPNT+1
    jsr ADDPROC
    jmp DOPA20

;; Compacts the module's records in place, keeping only its .PROC and .FUNC records, then loads the next module, with
;; the code's start as the top of the free memory.
DOPAS3:
    lda INVPNT
    sta PROCPNT
    sta POINT2
    lda INVPNT+1
    sta PROCPNT+1
    sta POINT2+1
    ldy #8
    lda (PROCPNT),Y

;; Keeps the record at <PROCPNT> if it is a .PROC or .FUNC.
;; In: A = its type
DOPA31:
    cmp #$B
    beq DOPA37
    cmp #$C
    beq DOPA37
    cmp #$2
    bne DOPA32
    jsr DOPA13                              ; a .REF: skip its list too

;; Moves on to the next record, or at the end loads the next module.
DOPA32:
    jsr NXTPROC
    bne DOPA31
    lda POINT2                              ; the records kept end here
    sta INVPNT
    lda POINT2+1
    sta INVPNT+1
    lda POINT1                              ; and the free memory below the code
    sta PROCPNT
    lda POINT1+1
    sta PROCPNT+1
    jmp DOFILE

;; Copies the 16-byte record at <PROCPNT> down to <POINT2>, and moves POINT2 past it.
DOPA37:
    ldy #15
DOPA38:
    lda (PROCPNT),Y
    sta (POINT2),Y
    dey
    bpl DOPA38
    lda #16
    clc
    adc POINT2
    sta POINT2
    bcc DOPA32
    inc POINT2+1
    bne DOPA32                              ; always

; ---------------------------------------------------------------------------------------------------------------------
; Finishing
; ---------------------------------------------------------------------------------------------------------------------

;; Moves the records kept, from <INVTAB> to <INVPNT>, up against the lowest module's code, so the free memory left is
;; all below them.
;;
;; The two bytes after the last record move with them. <PERFIND> stops at a record whose type, at offset 8, is 0;
;; after the last record that byte is the lowest module's seventh byte of code.
;; Out: INVPNT = the records' new start
;; See: <BLTUC>
DOCRNCH:
    lda PROCPNT
    sta HIGHDS
    lda PROCPNT+1
    sta HIGHDS+1
    lda INVPNT
    sta HIGHTR
    lda INVPNT+1
    sta HIGHTR+1
    lda PROCTABB
    sta HIGHDSB
    sta LOWTRB
    sta HIGHTRB
    lda INVTAB
    sta LOWTR
    lda INVTAB+1
    sta LOWTR+1
    lda #2
    clc
    adc HIGHTR
    sta HIGHTR
    bcc *+4
    inc HIGHTR+1
    jsr BLTUC
    lda HIGHDS
    sta INVPNT
    lda HIGHDS+1
    sta INVPNT+1
    lda HIGHDSB
    sta INVPNTB
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Walking the dictionaries and records
; ---------------------------------------------------------------------------------------------------------------------

;; Moves <PROCPNT> down two bytes, to the next word of a dictionary or attribute table.
;; Uses: A, TEMP
DEC2PROC:
    lda #2
    sta TEMP
    lda PROCPNT
    sec
    sbc TEMP
    sta PROCPNT
    bcs *+4
    dec PROCPNT+1
    rts

;; Moves <PROCPNT> down to the next word, which must be zero (an empty relocation list BASIC can't apply), or ends the
;; statement with an invoke error.
;; Uses: A, Y, TEMP
MAKESUR0:
    jsr DEC2PROC
    ldy #0
    lda (PROCPNT),Y
    bne INVERROR
    iny
    lda (PROCPNT),Y
    bne INVERROR
    rts

;; Ends the statement with the INVOKE error, <ERRIN>: a module BASIC can't load or link.
INVERROR:
    ldx #ERRIN
    jmp ERROR

;; Applies one relocation list of the attribute table at <PROCPNT>: adds the word <SWPPNT> points to, and $2000, to
;; each word the list points to.
;;
;; BASIC's addresses are offsets in a bank; the $2000 makes each relocated word the address the code runs at, in the
;; bank-switched window at $2000-$9FFF.
;; In: PROCPNT = the word above the list's count
;; Out: PROCPNT = the list's last pointer
;; Uses: A, Y, TEMP, TEMPTR, OFFSST
DOAREL:
    jsr DEC2PROC
    ldy #1
    lda (PROCPNT),Y                         ; the count
    sta TEMPTR+1
    dey
    lda (PROCPNT),Y
    sta TEMPTR
    bne DOARE1
DOARE0:
    dec TEMPTR+1
    bmi DOARTS
DOARE1:
    dec TEMPTR
    jsr RELPROC                             ; the word to fix
    clc
    ldy #0
    lda (OFFSST),Y
    adc (SWPPNT),Y
    sta (OFFSST),Y
    iny
    lda (OFFSST),Y
    adc (SWPPNT),Y
    clc
    adc #$20
    sta (OFFSST),Y
    lda TEMPTR
    bne DOARE1
    beq DOARE0                              ; always
DOARTS:
    rts

;; Moves <PROCPNT> down to the next word and follows it as a self-relative pointer.
;; Out: OFFSST = PROCPNT less the word there
;; Uses: A, Y, TEMP
RELPROC:
    jsr DEC2PROC
    sec
    ldy #0
    lda PROCPNT
    sbc (PROCPNT),Y
    sta OFFSST
    iny
    lda PROCPNT+1
    sbc (PROCPNT),Y
    sta OFFSST+1
    rts

;; Adds A to <PROCPNT>.
;; In: A = the count of bytes
;; Uses: TEMP
ADDPROC:
    sta TEMP
    clc
    lda PROCPNT
    adc TEMP
    sta PROCPNT
    bcc *+4
    inc PROCPNT+1
    rts

;; Moves <PROCPNT> to the next 16-byte linker record and loads its type.
;; Out: A = the type, zero = set at the records' end, Y = 8
;; Uses: TEMP
NXTPROC:
    lda #16
    jsr ADDPROC
    ldy #8
    lda (PROCPNT),Y
    rts

; ---------------------------------------------------------------------------------------------------------------------
; PERFORM, EXFN. and EXFN%.
; ---------------------------------------------------------------------------------------------------------------------

;; PERFORM: calls a procedure an invoked module defines with .PROC, passing the arguments in parentheses after its
;; name.
;;
;; Each argument is pushed on the 6502's stack as it is read, as Pascal's code expects; the count of 2-byte words
;; pushed must match the .PROC's count of parameter words, or it is a type mismatch:
;;
;; - `@name` passes a variable's address, high byte first: one word. It also goes, with its bank byte, into
;;   <BANKPNT> (the first such argument at BANKPNT, the next 2 bytes on), so the procedure can reach the variable
;;   through extended addressing.
;; - `%` and a formula passes an integer, high byte first: one word.
;; - `&` and a formula passes a long integer's 8 bytes, the FAC's first byte first: four words.
;; - Any other formula passes a real, rounded and pushed exponent first, then the sign with the mantissa's top 7 bits,
;;   then the next two bytes: two words.
;; - A string is a type mismatch.
;;
;; The name is up to 8 letters and digits, upper-cased into <NAMBUF>; a name not found is an undefined-function error.
;; See: <PERFEXF>, <PERFIND>, <JUMPDO>
PERFORM:
    lda #$B                                 ; a .PROC
    sta PROCFLG
    lda #0

;; Reads a procedure's or function's name and arguments, finds it, and calls it through <JUMPDO>.
;;
;; The caller's return address is set aside in <SAFE>, so the arguments lie right under the routine's own return
;; address; JUMPDO returns to the caller from SAFE. For a .FUNC, four placeholder bytes are pushed after the
;; arguments, as Pascal does. NPARAMS, NPOINTS, PROCFLG and SAFE are single copies, so an EXFN in another call's
;; arguments overwrites the outer call's.
;; In: A = the name's offset in <NAMBUF> (8 for each EXFN nested in another's arguments), PROCFLG = $B for a .PROC
;;   or $C for a .FUNC, TXTPTR = the name's first character
;; See: <PERFORM>, <EXFN>, <EXFNS>
PERFEXF:
    sta NAMPNT
    pla                                     ; set the return address aside
    sta SAFE
    pla
    sta SAFE+1
    lda #0
    sta NPARAMS
    sta NPOINTS
    lda #' '                                ; fill the name with spaces
    ldx NAMPNT
    inx
    ldy #8
PERFE1:
    sta NAMBUF-1,X
    inx
    dey
    bne PERFE1
    ldx NAMPNT
    jsr CHRGOT
    bne PERFE3

;; Ends the statement with a syntax error: no name.
PERERR:
    jmp SNERR

;; Goes to <PERFE5>, out of a branch's reach.
PERFE05:
    jmp PERFE5

;; Reads the name's next character.
;;
;; A character that is not a letter, a digit or an opening parenthesis ends the name, and is skipped. Nothing limits
;; the name to 8 characters: a longer one runs on past its 8 bytes of NAMBUF, though only the first 8 are compared.
PERFE2:
    jsr CHRGET
PERFE3:
    beq PERFE05                             ; the statement's end
    bcc PERFE35                             ; a digit
    jsr ISLETC
    bcs PERFE35
    cmp #'('
    beq PERFE4
    txa
    beq PERERR
    jmp PERFE6

;; Adds a letter or digit to the name, in upper case.
PERFE35:
    inx
    cmp #'Z'+1
    bcc *+4
    sbc #$20
    sta NAMBUF-1,X
    bne PERFE2                              ; always

; ---------------------------------------------------------------------------------------------------------------------
; The arguments
; ---------------------------------------------------------------------------------------------------------------------

;; Reads one argument and pushes it.
PERFE4:
    lda #$20                                ; any type, for now
    sta VALTYP
    jsr CHRGET
    cmp #'@'
    beq PERVAL1
    cmp #'%'
    beq PERINT1
    cmp #'&'
    beq PERLONG1
    cmp #'$'
    bne *+5
    jmp TMERR                               ; no strings
    jsr DOPAR                               ; a real
    jsr CONV2FLT
    jsr ROUNDER
    lda FACEXP
    pha
    lda FACSGN                              ; the sign over the mantissa's top bit
    ora #$7F
    and FACHO
    pha
    lda FACMOH
    pha
    lda FACMO
    pha
    lda #2
    bne PERVAL2                             ; always

;; Pushes an integer argument, after its `%`.
PERINT1:
    jsr CHRGET
    jsr DOPAR
    jsr CONV2INT
    jsr AYINT
    lda FACMO
    pha
    lda FACMO+1
    pha
    lda #1
    bne PERVAL2                             ; always

;; Pushes a long-integer argument, after its `&`.
PERLONG1:
    jsr CHRGET
    jsr DOPAR
    jsr CONV2LNG
    ldx #0
PERLNG1:
    lda FAC,X
    pha
    inx
    cpx #8
    bcc PERLNG1
    lda #4
    bne PERVAL2

;; Pushes a variable's address, after its `@`, and puts it with its bank byte in <BANKPNT>.
PERVAL1:
    jsr CHRGET
    jsr PTRGET
    lda VARPNT+1
    pha
    ldx NPOINTS
    sta BANKPNT+1,X
    lda VARPNT
    pha
    sta BANKPNT,X
    lda VARPNTB
    sta BANKPNTB,X
    inc NPOINTS
    inc NPOINTS
    lda #1

;; Adds the argument's words to <NPARAMS>, then reads the next argument after a comma, or ends at the closing
;; parenthesis.
;; In: A = the argument's count of words
PERVAL2:
    clc
    adc NPARAMS
    sta NPARAMS
    jsr CHRGOT
    cmp #')'
    beq PERFE6
    cmp #','
    beq *+5
    jmp SNERR
    jmp PERFE4

;; Skips the character that ended the name or the arguments.
PERFE6:
    jsr CHRGET

;; Finds the routine by name and type, checks its count of parameter words, and calls it.
PERFE5:
    lda #<(NAMBUF)
    clc
    adc NAMPNT
    sta POINT2
    lda #>(NAMBUF)
    adc #0
    sta POINT2+1
    lda #0
    sta POINT2B
    jsr PERFIND
    beq PERFERR
    ldy #12
    lda (PROCPNT),Y                         ; the count of parameter words
    cmp NPARAMS
    beq PTMOK
    jmp TMERR

;; Calls the routine found, from the entry point in its record, with room for a function's result.
PTMOK:
    dey
    lda (PROCPNT),Y
    sta JMPER+2
    dey
    lda (PROCPNT),Y
    sta JMPER+1
    lda PROCFLG
    cmp #$C                                 ; a .FUNC?
    bne *+6
    pha                                     ; then four placeholder bytes
    pha
    pha
    pha
    jmp JUMPDO

;; The EXFN%. function: calls a .FUNC and takes the integer it leaves on the stack, low byte on top.
;; Out: FAC = the result
;; See: <EXFN>, <PERFEXF>
EXFNS:
    jsr PERFEX1
    pla
    tay
    pla
    jsr GIVAYF
    jmp RESTNAM

;; Starts an EXFN. or EXFN%.: a .FUNC, its name 8 bytes further on in <NAMBUF> than the call around it.
PERFEX1:
    lda #$C
    sta PROCFLG
    lda NAMPNT
    clc
    adc #8
    jmp PERFEXF

;; The EXFN. function: calls a .FUNC and takes the real it leaves on the stack, in the order a real argument is
;; pushed.
;; Out: FAC = the result
;; See: <EXFNS>, <PERFEXF>
EXFN:
    jsr PERFEX1
    pla
    sta FACMO
    pla
    sta FACMOH
    pla
    sta FACSGN
    ora #$80
    sta FACHO
    pla
    sta FACEXP
    lda #0
    sta FACLO
    sta FACOV

;; Finishes a function call: checks the stack, frees the name's place in <NAMBUF>, and backs TXTPTR up one character
;; unless it is at the statement's end.
;;
;; The function must leave the stack as it found it, with the return into the evaluator, <EVALRET>, on top; anything
;; else is an undefined-function error.
RESTNAM:
    pla
    pha
    cmp #<(EVALRET)
    bne PERFERR
    lda NAMPNT
    sec
    sbc #8
    sta NAMPNT
    jsr CHRGOT
    beq *+5
    jmp DECTPT
    rts

;; Ends the statement with an undefined-function error.
PERFERR:
    jmp ERRGUF

;; Finds the linker record of type <PROCFLG> whose 8-character name matches the one at <POINT2>, searching from
;; <INVTAB>.
;; Out: zero = clear when found (set when not, or when nothing is invoked), PROCPNT = the record found
;; Uses: A, Y, TEMP
PERFIND:
    lda a:SEGNUMB
    beq PERFI05                             ; nothing invoked
    lda INVTAB
    sta PROCPNT
    lda INVTAB+1
    sta PROCPNT+1
    lda INVTABB
    sta PROCPNTB
    ldy #8
    lda (PROCPNT),Y
PERFI01:
    beq PERFI05                             ; the end
    cmp #2
    bne PERFI02
    jsr DOPA13                              ; a .REF: skip its list
    jmp PERFI04
PERFI02:
    cmp PROCFLG
    bne PERFI04
PERFI06:
    dey
    bmi PERFI05                             ; all 8 matched
    lda (POINT2),Y
    cmp (PROCPNT),Y
    beq PERFI06
PERFI04:
    jsr NXTPROC
    jmp PERFI01
PERFI05:
    rts

;; Ends the statement with an out-of-memory error, for <INVOKE>.
INVERR1:
    jmp OMERR
