; retrocore: style=strict
; Invoke.asm: loading, relocating and linking the modules `INVOKE` names, and calling them: `PERFORM` for a procedure,
; `EXFN.` and `EXFN%.` for a function.
;
; Apple's listing calls this file INVOKE; its names are kept in each definition's Also: section.

;; The invokable modules: loading, relocating and linking the code files `INVOKE` names, and calling their procedures
;; and functions for `PERFORM`, `EXFN.` and `EXFN%.`, and the calls between BASIC and the modules.
;;
;; A module is a code file (type 2) from the Pascal assembler, which BASIC loads much as Pascal's linker would:
;;
;; - The first block is the segment dictionary. BASIC takes only the code's length from it, the word at offset 6.
;; - The code follows, from the second block. It ends with its procedure dictionary: the last word holds the count of
;;   procedures in its high byte, and each word below it, one per procedure from 1 up, is a self-relative pointer to
;;   the procedure's attribute table.
;; - The linker information starts at the next block boundary and runs to the end of the file, in 16-byte records,
;;   <Modules::LinkerRecord>.
;;
;; Each procedure's attribute table, read downward from the pointer, holds a self-relative pointer to its entry
;; point, then four relocation lists, each a count and that many self-relative pointers: base-relative,
;; segment-relative, procedure-relative and interpreter-relative. BASIC applies the middle two and refuses a module
;; that has either of the others.
;;
;; The names below borrow other routines' zero-page space; a clash is fixed by changing an equate.
.scope Modules

;; A linker record: a name the module defines or refers to.
;;
;; After a .REF record come the offsets of the words that refer to the name, padded to a multiple of 16 bytes.
.struct LinkerRecord
    NAME .res 8                             ;; the name, 8 characters, padded with spaces
    TYPE .byte                              ;; the record's type, a RECORD_ value; <RECORD_END> ends the records
    .res 1
    ;; For .PROC and .FUNC, the procedure's number, which linking replaces with its entry point; for .DEF, the number
    ;; of the procedure holding the label, likewise replaced.
    VALUE .word
    ;; For .PROC and .FUNC, the count of parameter words; for .DEF, the label's offset from its procedure's entry; for
    ;; .REF, the count of references.
    COUNT .word
    .res 2
.endstruct

;; The record type that ends the linker records.
RECORD_END = 0

;; The type of a .REF record: a name the module refers to.
RECORD_REF = 2

;; The type of a .DEF record: a label the module defines.
RECORD_DEF = 6

;; The type of a .PROC record: a procedure `PERFORM` calls.
RECORD_PROC = $B

;; The type of a .FUNC record: a function `EXFN.` and `EXFN%.` call.
RECORD_FUNC = $C

;; The pages of a file's block: SOS files are read in 512-byte blocks, and a module's first block is its segment
;; dictionary.
BLOCK_PAGES = 2

;; The offset of the code's length in the segment dictionary.
CODE_LENGTH = 6

;; The address a self-relative pointer gives, from <Modules::FollowPointer>, or the word a relocation fixes.
;; Also: OFFSST (BB13)
Target = FORPNT

;; The walking pointer: down the code's dictionaries, then along the records.
;; Also: PROCPNT (BB13)
WalkPointer = INPPTR

;; The zero-page pointer whose value <Modules::ApplyRelocations> adds: <Modules::CodeStart> or <HIGHTR>.
;; Also: SWPPNT (BB13)
AddendPointer = LOWDS

;; <Modules::ApplyRelocations>'s count of words left to relocate.
;; Also: TEMPTR (BB13)
RelocationsLeft = HEADER

;; The start of the module's code.
;; Also: POINT1 (BB13)
CodeStart = INDEX1

;; <Modules::CodeStart>'s X-byte.
;; Also: POINT1B (BB13)
CodeStartXByte = CodeStart+SYSPAG

;; A second pointer: into the procedure dictionary, to a record, or a value.
;; Also: POINT2 (BB13)
OtherPointer = INDEX2

;; <Modules::OtherPointer>'s X-byte.
;; Also: POINT2B (BB13)
OtherPointerXByte = OtherPointer+SYSPAG

;; <Modules::WalkPointer>'s X-byte.
;; Also: PROCPNTB (BB13)
WalkPointerXByte = WalkPointer+SYSPAG

;; <Modules::Target>'s X-byte.
;; Also: OFFSSTB (BB13)
TargetXByte = Target+SYSPAG

;; <Modules::AddendPointer>'s X-byte, 0 to read the zero page directly.
;; Also: SWPPNTB (BB13)
AddendPointerXByte = AddendPointer+SYSPAG

; ---------------------------------------------------------------------------------------------------------------------
; Loading
; ---------------------------------------------------------------------------------------------------------------------

;; Ends the statement with an out-of-memory error: there is no room for a module's first block.
;; Also: INERROM (BB13)
.proc ToOutOfMemoryError
    jmp OMERR
.endproc

;; Loads, relocates and links each module the statement names, then moves the records kept up against the code.
;;
;; The free memory runs from <INVTAB> to <PROCTAB>, in one bank. Each module's code goes at the top of what is left,
;; below the module before it, and its linker records at <INVPNT>, after those kept from the module before. Only the
;; .PROC and .FUNC records are kept, for <Modules::FindRecord>.
;; In: TXTPTR = the first file name, INVTAB = the free memory's start, PROCTAB = its end
;; Out: INVPNT = the start of the records kept, which end just below the code
;; See: <Statements::Invoke>, <Modules::RelocateProcedure>, <Modules::ResolveProcedures>, <Modules::LinkReferences>,
;;   <Modules::MoveRecordsUp>
;; Also: DOINVO (BB13)
.proc Load
    lda #0
    sta HEADERB
    sta AddendPointerXByte
    lda INVTAB
    sta INVPNT
    lda INVTAB+1
    sta INVPNT+1
    lda INVTABB
    sta INVPNTB
    lda PROCTAB
    ldx PROCTAB+1
    sta WalkPointer
    stx WalkPointer+1
    lda PROCTABB
    sta WalkPointerXByte
    sta TargetXByte
    ; Falls into LoadFile.
.endproc

;; Loads the next module, or ends with <Modules::MoveRecordsUp> at the statement's end.
;;
;; The file's first block is read at <INVPNT> for the code's length; the code is read to just below
;; <Modules::WalkPointer>; then the linker information, from the next block boundary to the end of the file, is read at
;; <INVPNT>.
;; In: TXTPTR = the next file name, or the statement's end, WalkPointer = the top of the free memory
;; Errors: ERROM = no room for the first block; the errors of opening and reading the file
;; Also: DOFILE (BB13)
.proc LoadFile
    jsr CHRGOT
    bne *+5
    jmp MoveRecordsUp                       ; no more names
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
    lda #BLOCK_PAGES                        ; one block
    sta INBYTES+1
    sec
    lda WalkPointer+1
    sbc INVPNT+1
    cmp #BLOCK_PAGES+1                      ; room for the block?
    bcc ToOutOfMemoryError
    ldy #RED
    jsr SETGO
    ldy #CODE_LENGTH+1
    lda (INVPNT),Y                          ; the code's length
    sta INBYTES+1
    dey
    lda (INVPNT),Y
    sta INBYTES
    sec
    lda WalkPointer
    sbc INBYTES                             ; the code goes just below WalkPointer
    sta CodeStart
    lda WalkPointer+1
    sbc INBYTES+1
    sta CodeStart+1
    lda INVPNTB
    sta CodeStartXByte
    lda #<(CodeStart)
    sta SBFPTR
    lda #>(CodeStart)
    sta SBFPTR+1
    ldy #RED                                ; the code alone
    jsr SETGO
    ldy #GTM
    jsr SETGO
    lda OUTMRK                              ; round the mark up to a page
    beq RoundUpToBlock
    inc OUTMRK+1

;; Rounds the mark's page up to a block, and sets the mark there.
;; Also: MARKLOW (BB13)
RoundUpToBlock:
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
    lda CodeStart                           ; the linker information: up to all the room below the code
    sbc INVPNT
    sta INBYTES
    lda #<(INVPNT)
    sta SBFPTR
    lda CodeStart+1
    sbc INVPNT+1
    sta INBYTES+1
    lda #>(INVPNT)
    sta SBFPTR+1
    ldy #RED                                ; to the end of the file
    jsr SETGO
    jsr CLSEND
    jsr StepBack                            ; the code's last word
    ldy #1
    lda (WalkPointer),Y
    sta KIMY                                ; the count of procedures
    lda WalkPointer                         ; kept for ResolveProcedures
    pha
    lda WalkPointer+1
    pha
    ; Falls into RelocateProcedure.
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Relocating
; ---------------------------------------------------------------------------------------------------------------------

;; Relocates one procedure: puts its entry point's address in its procedure dictionary entry, then applies its
;; segment-relative and procedure-relative relocation lists.
;;
;; A nonzero count of base-relative or interpreter-relative relocations is an invoke error. When the last procedure
;; is done, linking goes on at <Modules::ResolveProcedures>. A module that gives a count of 0 procedures goes round
;; 256 times.
;; In: WalkPointer = the word above the procedure's dictionary entry, KIMY = the count of procedures left
;; Errors: ERRIN = a relocation BASIC can't apply
;; See: <Modules::FollowPointer>, <Modules::ApplyRelocations>, <Modules::CheckNoRelocations>
;; Also: DOAPROC (BB13)
.proc RelocateProcedure
    jsr FollowPointer                       ; the attribute table
    lda WalkPointer
    sta OtherPointer                        ; the dictionary entry
    lda Target
    sta WalkPointer
    lda WalkPointer+1
    sta OtherPointer+1
    lda Target+1
    sta WalkPointer+1
    lda WalkPointerXByte
    sta OtherPointerXByte
    jsr FollowPointer                       ; the entry point
    ldy #0
    lda Target
    sta HIGHTR                              ; the base for procedure-relative relocation
    sta (OtherPointer),Y                    ; and the dictionary entry's new value
    iny
    lda Target+1
    cmp #MAXPG                              ; keep the page in BASIC's range, $02-$81
    bcc *+4
    sbc #MAXPG-MINPG
    sta HIGHTR+1
    sta (OtherPointer),Y
    jsr CheckNoRelocations                  ; no base-relative relocations
    lda #<(CodeStart)                       ; segment-relative: add the code's start
    sta AddendPointer
    lda #>(CodeStart)
    sta AddendPointer+1
    jsr ApplyRelocations
    lda #>(HIGHTR)                          ; procedure-relative: add the entry point
    sta AddendPointer+1
    lda #<(HIGHTR)
    sta AddendPointer
    jsr ApplyRelocations
    jsr CheckNoRelocations                  ; no interpreter-relative relocations
    dec KIMY
    beq ResolveProcedures
    lda OtherPointer
    sta WalkPointer
    lda OtherPointer+1
    sta WalkPointer+1
    jmp RelocateProcedure
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Linking
; ---------------------------------------------------------------------------------------------------------------------

;; Linking's first pass: replaces the procedure number in each .PROC, .FUNC and .DEF record with that procedure's
;; entry point, from the procedure dictionary.
;;
;; A record of any type but these, .REF and the end is an invoke error. The procedure dictionary's top is on the
;; stack, from <Modules::LoadFile>.
;; In: INVPNT = the module's records
;; Errors: ERRIN = a record of a type BASIC doesn't know
;; Entry:
;;   SkipReferences = moves <WalkPointer> past a .REF record's list of references; <Modules::CompactRecords> and
;;     <Modules::FindRecord> call it
;; See: <Modules::LinkReferences>
;; Also: DOLIB (BB13)
.proc ResolveProcedures
    pla
    sta OtherPointer+1
    dec OtherPointer+1                      ; a page lower, so (OtherPointer),Y reaches down from Y = 256
    pla
    sta OtherPointer
    lda INVPNT
    sta WalkPointer
    lda INVPNT+1
    sta WalkPointer+1
    ldy #LinkerRecord::TYPE
    lda (WalkPointer),Y                     ; the record's type

;; Takes the record at <WalkPointer> in the first pass.
;; In: A = its type
;; Also: DOPAS1 (BB13)
TakeRecord:
    beq LinkReferences                      ; the end
    cmp #RECORD_PROC
    beq ResolveNumber
    cmp #RECORD_FUNC
    beq ResolveNumber
    cmp #RECORD_DEF
    beq ResolveNumber
    cmp #RECORD_REF
    beq SkipReferenceRecord
    jmp InvokeError

;; Moves WalkPointer past a .REF record's list of references, the count at offset 12 rounded up to 8 words, so that
;; <Modules::NextRecord> then reaches the next record.
;;
;; Only the count's low byte is taken.
;; In: WalkPointer = the .REF record
;; Uses: A, Y, TEMP
;; Keeps: X
;; Also: DOPA13 (BB13)
SkipReferences:
    ldy #LinkerRecord::COUNT
    lda (WalkPointer),Y                     ; the count
    sta TEMP
    and #$F8
    cmp TEMP
    beq *+8                                 ; already a multiple of 8
    adc #$8
    bcc *+4
    inc WalkPointer+1
    asl                                     ; words to bytes
    bcc *+4
    inc WalkPointer+1
    jmp AddToWalkPointer

;; Skips a .REF record in the first pass.
;; Also: DOPA12 (BB13)
SkipReferenceRecord:
    jsr SkipReferences
    jmp Advance

;; Replaces a .PROC's, .FUNC's or .DEF's procedure number, at offset 10, with the procedure's entry point.
;; Also: DOPA11 (BB13)
ResolveNumber:
    ldy #LinkerRecord::VALUE
    lda #0
    sec
    sbc (WalkPointer),Y
    asl                                     ; the number times -2: the entry's offset below the dictionary's top
    tay
    lda (OtherPointer),Y
    tax
    iny
    lda (OtherPointer),Y
    ldy #LinkerRecord::VALUE+1
    sta (WalkPointer),Y
    txa
    dey
    sta (WalkPointer),Y

;; Moves on to the next record in the first pass.
;; Also: DOPA14 (BB13)
Advance:
    jsr NextRecord
    bne TakeRecord
    ; Falls into LinkReferences.
.endproc

;; Linking's second pass: for each .REF record, finds the .DEF of the same name and adds the label's offset in the
;; code to each word that refers to it.
;;
;; A name with no .DEF is an invoke error. <Modules::FindRecord> searches from <INVTAB>, where the modules before this
;; one have kept only their .PROC and .FUNC records, so the .DEF must be in the same module.
;; Errors: ERRIN = a name with no .DEF
;; Also: DOPAS2 (BB13)
.proc LinkReferences
    lda INVPNT
    sta WalkPointer
    lda INVPNT+1
    sta WalkPointer+1

;; Takes the record at <WalkPointer> in the second pass.
;; Also: DOPA20 (BB13)
TakeRecord:
    ldy #LinkerRecord::TYPE
    lda (WalkPointer),Y

;; Takes a record of type A.
;; Also: DOPA22 (BB13)
CheckType:
    bne *+5
    jmp CompactRecords                      ; the end
    cmp #RECORD_REF
    bne Skip                                ; only .REF records matter here
    lda WalkPointer
    sta OtherPointer
    lda WalkPointer+1
    sta OtherPointer+1
    lda #RECORD_DEF
    sta PROCFLG                             ; look for a .DEF of this name
    jsr FindRecord
    bne AddOffset
    jmp InvokeError

;; Moves on to the next record in the second pass.
;; Also: DOPA29 (BB13)
Skip:
    jsr NextRecord
    jmp CheckType

;; Adds the .DEF's offset in the code to each word the .REF record at OtherPointer lists, then moves past the list.
;;
;; With exactly 248 references, the step past the list's padding also adds a page to WalkPointer.
;; In: WalkPointer = the .DEF record, OtherPointer = the .REF record
;; Also: DOPA25 (BB13)
AddOffset:
    ldy #LinkerRecord::VALUE
    lda (WalkPointer),Y                     ; the procedure's entry plus the label's offset
    clc
    ldy #LinkerRecord::COUNT
    adc (WalkPointer),Y
    tax
    dey
    lda (WalkPointer),Y
    ldy #LinkerRecord::COUNT+1
    adc (WalkPointer),Y
    pha
    txa
    sec
    sbc CodeStart                           ; less the code's start
    tax
    pla
    sbc CodeStart+1
    ldy OtherPointer+1
    sta OtherPointer+1
    sty WalkPointer+1
    lda OtherPointer                        ; WalkPointer back to the .REF, and OtherPointer the label's offset
    stx OtherPointer
    sta WalkPointer
    ldy #LinkerRecord::COUNT
    lda (WalkPointer),Y                     ; the count of references
    sta KIMY
    tax
    beq Skip
    jsr NextRecord                          ; the list

;; Adds the label's offset to the next referring word.
;; Also: DOPA27 (BB13)
AddToWord:
    ldy #0
    clc
    lda CodeStart                           ; the referring word's address
    adc (WalkPointer),Y
    sta Target
    iny
    lda CodeStart+1
    adc (WalkPointer),Y
    sta Target+1
    clc
    dey
    lda OtherPointer
    adc (Target),Y
    sta (Target),Y
    iny
    lda OtherPointer+1
    adc (Target),Y
    sta (Target),Y
    lda #2
    jsr AddToWalkPointer
    dex
    bne AddToWord
    lda KIMY                                ; skip the padding to a multiple of 8 words
    eor #$7
    clc
    adc #1
    bcc *+4
    inc WalkPointer+1
    and #$7
    asl
    bcc *+4
    inc WalkPointer+1
    jsr AddToWalkPointer
    jmp TakeRecord
.endproc

;; Compacts the module's records in place, keeping only its .PROC and .FUNC records, then loads the next module, with
;; the code's start as the top of the free memory.
;; Also: DOPAS3 (BB13)
.proc CompactRecords
    lda INVPNT
    sta WalkPointer
    sta OtherPointer
    lda INVPNT+1
    sta WalkPointer+1
    sta OtherPointer+1
    ldy #LinkerRecord::TYPE
    lda (WalkPointer),Y

;; Keeps the record at <WalkPointer> if it is a .PROC or .FUNC.
;; In: A = its type
;; Also: DOPA31 (BB13)
CheckRecord:
    cmp #RECORD_PROC
    beq KeepRecord
    cmp #RECORD_FUNC
    beq KeepRecord
    cmp #RECORD_REF
    bne Skip
    jsr ResolveProcedures::SkipReferences   ; a .REF: skip its list too

;; Moves on to the next record, or at the end loads the next module.
;; Also: DOPA32 (BB13)
Skip:
    jsr NextRecord
    bne CheckRecord
    lda OtherPointer                        ; the records kept end here
    sta INVPNT
    lda OtherPointer+1
    sta INVPNT+1
    lda CodeStart                           ; and the free memory below the code
    sta WalkPointer
    lda CodeStart+1
    sta WalkPointer+1
    jmp LoadFile

;; Copies the 16-byte record at <WalkPointer> down to <OtherPointer>, and moves <OtherPointer> past it.
;; Also: DOPA37 (BB13)
KeepRecord:
    ldy #.sizeof(LinkerRecord)-1

;; Copies the next byte, from the last.
;; Also: DOPA38 (BB13)
CopyByte:
    lda (WalkPointer),Y
    sta (OtherPointer),Y
    dey
    bpl CopyByte
    lda #.sizeof(LinkerRecord)
    clc
    adc OtherPointer
    sta OtherPointer
    bcc Skip
    inc OtherPointer+1
    bne Skip                                ; always
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Finishing
; ---------------------------------------------------------------------------------------------------------------------

;; Moves the records kept, from <INVTAB> to <INVPNT>, up against the lowest module's code, so the free memory left is
;; all below them.
;;
;; The two bytes after the last record move with them. <Modules::FindRecord> stops at a record whose type, at offset
;; 8, is 0; after the last record that byte is the lowest module's seventh byte of code, so the search ends there only
;; when that byte is 0, and otherwise goes on to read the code as records.
;; Out: INVPNT = the records' new start
;; See: <BLTUC>
;; Also: DOCRNCH (BB13)
.proc MoveRecordsUp
    lda WalkPointer
    sta HIGHDS
    lda WalkPointer+1
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
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Walking the dictionaries and records
; ---------------------------------------------------------------------------------------------------------------------

;; Moves <Modules::WalkPointer> down two bytes, to the next word of a dictionary or attribute table.
;; Uses: A, TEMP
;; Keeps: X, Y
;; Also: DEC2PROC (BB13)
.proc StepBack
    lda #2
    sta TEMP
    lda WalkPointer
    sec
    sbc TEMP
    sta WalkPointer
    bcs *+4
    dec WalkPointer+1
    rts
.endproc

;; Moves <Modules::WalkPointer> down to the next word, which must be zero (an empty relocation list BASIC can't apply),
;; or ends the statement with an invoke error.
;; Errors: ERRIN = a nonzero count
;; Uses: A, Y, TEMP
;; Keeps: X
;; Also: MAKESUR0 (BB13)
.proc CheckNoRelocations
    jsr StepBack
    ldy #0
    lda (WalkPointer),Y
    bne InvokeError
    iny
    lda (WalkPointer),Y
    bne InvokeError
    rts
.endproc

;; Ends the statement with the `INVOKE` error, <ERRIN>: a module BASIC can't load or link.
;; Also: INVERROR (BB13)
.proc InvokeError
    ldx #ERRIN
    jmp ERROR
.endproc

;; Applies one relocation list of the attribute table at <Modules::WalkPointer>: adds the word
;; <Modules::AddendPointer> points to, and $2000, to each word the list points to.
;;
;; BASIC's addresses are offsets in a bank; the $2000 makes each relocated word the address the code runs at, in the
;; bank-switched window at $2000-$9FFF.
;; In: WalkPointer = the word above the list's count
;; Out: WalkPointer = the list's last pointer
;; Uses: A, Y, TEMP, RelocationsLeft, Target
;; Keeps: X
;; Also: DOAREL (BB13)
.proc ApplyRelocations
    jsr StepBack
    ldy #1
    lda (WalkPointer),Y                     ; the count
    sta RelocationsLeft+1
    dey
    lda (WalkPointer),Y
    sta RelocationsLeft
    bne NextWord

;; Counts down the count's high byte, at each 256 words.
;; Also: DOARE0 (BB13)
NextHigh:
    dec RelocationsLeft+1
    bmi Done

;; Relocates the next word.
;; Also: DOARE1 (BB13)
NextWord:
    dec RelocationsLeft
    jsr FollowPointer                       ; the word to fix
    clc
    ldy #0
    lda (Target),Y
    adc (AddendPointer),Y
    sta (Target),Y
    iny
    lda (Target),Y
    adc (AddendPointer),Y
    clc
    adc #Segments::WINDOW_PAGE
    sta (Target),Y
    lda RelocationsLeft
    bne NextWord
    beq NextHigh                            ; always

;; Returns.
;; Also: DOARTS (BB13)
Done:
    rts
.endproc

;; Moves <Modules::WalkPointer> down to the next word and follows it as a self-relative pointer.
;; Out: Target = <WalkPointer> less the word there
;; Uses: A, Y, TEMP
;; Keeps: X
;; Also: RELPROC (BB13)
.proc FollowPointer
    jsr StepBack
    sec
    ldy #0
    lda WalkPointer
    sbc (WalkPointer),Y
    sta Target
    iny
    lda WalkPointer+1
    sbc (WalkPointer),Y
    sta Target+1
    rts
.endproc

;; Adds A to <Modules::WalkPointer>.
;; In: A = the count of bytes
;; Uses: TEMP
;; Keeps: X, Y
;; Also: ADDPROC (BB13)
.proc AddToWalkPointer
    sta TEMP
    clc
    lda WalkPointer
    adc TEMP
    sta WalkPointer
    bcc *+4
    inc WalkPointer+1
    rts
.endproc

;; Moves <Modules::WalkPointer> to the next 16-byte linker record and loads its type.
;; Out: A = the type, zero = set at the records' end, Y = 8
;; Uses: TEMP
;; Keeps: X
;; Also: NXTPROC (BB13)
.proc NextRecord
    lda #.sizeof(LinkerRecord)
    jsr AddToWalkPointer
    ldy #LinkerRecord::TYPE
    lda (WalkPointer),Y
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; `PERFORM`, `EXFN.` and `EXFN%.`
; ---------------------------------------------------------------------------------------------------------------------

; Statements: `PERFORM`.
.scope Statements continued

;; The `PERFORM` statement: calls a procedure an invoked module defines with .PROC, passing the arguments in
;; parentheses after its name.
;;
;; Each argument is pushed on the 6502's stack as it is read, as Pascal's code expects; the count of 2-byte words
;; pushed must match the .PROC's count of parameter words, or it is a type mismatch:
;;
;; - `@name` passes a variable's address, high byte first: one word. It also goes, with its bank byte, into
;;   <BANKPNT> (the first such argument at <BANKPNT>, the next 2 bytes on), so the procedure can reach the variable
;;   through extended addressing. Nothing stops a ninth, which goes past the 16 bytes of <BANKPNT>.
;; - `%` and a formula passes an integer, high byte first: one word.
;; - `&` and a formula passes a long integer's 8 bytes, the <FAC>'s first byte first: four words.
;; - Any other formula passes a real, rounded and pushed exponent first, then the sign with the mantissa's top 7 bits,
;;   then the next two bytes: two words.
;; - A string is a type mismatch.
;;
;; The name is up to 8 letters and digits, upper-cased into <NAMBUF>; a name not found is an undefined-function error.
;; Errors: ERRSN = no name, ERRTM = the wrong count of words or a string, ERRUF = the name not found
;; See: <Modules::CallByName>, <Modules::FindRecord>, <Modules::CallModule>
;; Also: PERFORM (BB13)
.proc Perform
    lda #Modules::RECORD_PROC
    sta PROCFLG
    lda #0
    ; Falls into Modules::CallByName.
.endproc

.endscope

; Modules: reading a call's name and arguments.
.scope Modules continued

;; Reads a procedure's or function's name and arguments, finds it, and calls it through <Modules::CallModule>.
;;
;; The caller's return address is set aside in <SAFE>, so the arguments lie right under the routine's own return
;; address; <CallModule> returns to the caller from <SAFE>. For a .FUNC, four placeholder bytes are pushed after the
;; arguments, as Pascal does. <NPARAMS>, <NPOINTS>, <PROCFLG> and <SAFE> are single copies, so an `EXFN.` in another
;; call's arguments overwrites the outer call's.
;; In: A = the name's offset in <NAMBUF> (8 for each `EXFN.` nested in another's arguments), PROCFLG = <RECORD_PROC> for
;;   a .PROC or <RECORD_FUNC> for a .FUNC, TXTPTR = the name's first character
;; Errors: ERRSN = no name, ERRTM = the wrong count of words or a string, ERRUF = the name not found
;; See: <Statements::Perform>, <Functions::ExFn>, <Functions::ExFnInteger>
;; Also: PERFEXF (BB13)
.proc CallByName
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
    ldy #NAME_LENGTH

;; Fills the next byte of the name.
;; Also: PERFE1 (BB13)
FillName:
    sta NAMBUF-1,X
    inx
    dey
    bne FillName
    ldx NAMPNT
    jsr CHRGOT
    bne CheckCharacter

;; Ends the statement with a syntax error: no name.
;; Also: PERERR (BB13)
ToSyntaxError:
    jmp SNERR

;; Goes to <Find>, out of a branch's reach.
;; Also: PERFE05 (BB13)
ToFind:
    jmp Find

;; Reads the name's next character.
;;
;; A character that is not a letter, a digit or an opening parenthesis ends the name, and is skipped. Nothing limits
;; the name to 8 characters: a longer one runs on past its 8 bytes of <NAMBUF>, though only the first 8 are compared.
;; An empty name is a syntax error only for the outermost call, where X is 0.
;; Also: PERFE2 (BB13)
NextCharacter:
    jsr CHRGET

;; Takes the character in A.
;; Also: PERFE3 (BB13)
CheckCharacter:
    beq ToFind                              ; the statement's end
    bcc AddCharacter                        ; a digit
    jsr ISLETC
    bcs AddCharacter
    cmp #'('
    beq ReadArgument
    txa
    beq ToSyntaxError
    jmp SkipEnd

;; Adds a letter or digit to the name, in upper case.
;; Also: PERFE35 (BB13)
AddCharacter:
    inx
    cmp #'Z'+1
    bcc *+4
    sbc #'a'-'A'
    sta NAMBUF-1,X
    bne NextCharacter                       ; always

; The arguments.

;; Reads one argument and pushes it.
;; Also: PERFE4 (BB13)
ReadArgument:
    lda #$20                                ; any type, for now
    sta VALTYP
    jsr CHRGET
    cmp #'@'
    beq AddressArgument
    cmp #'%'
    beq IntegerArgument
    cmp #'&'
    beq LongArgument
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
    bne CountWords                          ; always

;; Pushes an integer argument, after its `%`.
;; Also: PERINT1 (BB13)
IntegerArgument:
    jsr CHRGET
    jsr DOPAR
    jsr CONV2INT
    jsr AYINT
    lda FACMO
    pha
    lda FACMO+1
    pha
    lda #1
    bne CountWords                          ; always

;; Pushes a long-integer argument, after its `&`.
;; Also: PERLONG1 (BB13)
LongArgument:
    jsr CHRGET
    jsr DOPAR
    jsr CONV2LNG
    ldx #0

;; Pushes the next byte of the long integer.
;; Also: PERLNG1 (BB13)
PushLongByte:
    lda FAC,X
    pha
    inx
    cpx #LONG_SIZE
    bcc PushLongByte
    lda #LONG_SIZE/2
    bne CountWords                          ; always

;; Pushes a variable's address, after its `@`, and puts it with its bank byte in <BANKPNT>.
;; Also: PERVAL1 (BB13)
AddressArgument:
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
;; Also: PERVAL2 (BB13)
CountWords:
    clc
    adc NPARAMS
    sta NPARAMS
    jsr CHRGOT
    cmp #')'
    beq SkipEnd
    cmp #','
    beq *+5
    jmp SNERR
    jmp ReadArgument

;; Skips the character that ended the name or the arguments.
;; Also: PERFE6 (BB13)
SkipEnd:
    jsr CHRGET

;; Finds the routine by name and type, checks its count of parameter words, and calls it.
;; Also: PERFE5 (BB13)
Find:
    lda #<(NAMBUF)
    clc
    adc NAMPNT
    sta OtherPointer
    lda #>(NAMBUF)
    adc #0
    sta OtherPointer+1
    lda #0
    sta OtherPointerXByte
    jsr FindRecord
    beq ToUndefinedFunctionError
    ldy #LinkerRecord::COUNT
    lda (WalkPointer),Y                     ; the count of parameter words
    cmp NPARAMS
    beq CallFound
    jmp TMERR

;; Calls the routine found, from the entry point in its record, with room for a function's result.
;; Also: PTMOK (BB13)
CallFound:
    dey
    lda (WalkPointer),Y
    sta JMPER+2
    dey
    lda (WalkPointer),Y
    sta JMPER+1
    lda PROCFLG
    cmp #RECORD_FUNC                        ; a .FUNC?
    bne *+6
    pha                                     ; then four placeholder bytes
    pha
    pha
    pha
    jmp CallModule
.endproc

;; The length of a procedure's name in <NAMBUF> and in a linker record.
NAME_LENGTH = 8

;; The size of a long integer in the <FAC>, in bytes.
LONG_SIZE = 8

.endscope

; Functions: `EXFN%.`.
.scope Functions continued

;; The `EXFN%.` function: calls a .FUNC and takes the integer it leaves on the stack, low byte on top.
;; Out: FAC = the result
;; See: <Functions::ExFn>, <Modules::CallByName>
;; Also: EXFNS (BB13)
.proc ExFnInteger
    jsr Modules::StartFunction
    pla
    tay
    pla
    jsr GIVAYF
    jmp Modules::FinishFunction
.endproc

.endscope

; Modules: starting a function call.
.scope Modules continued

;; Starts an `EXFN.` or `EXFN%.`: a .FUNC, its name 8 bytes further on in <NAMBUF> than the call around it.
;; Also: PERFEX1 (BB13)
.proc StartFunction
    lda #RECORD_FUNC
    sta PROCFLG
    lda NAMPNT
    clc
    adc #NAME_LENGTH
    jmp CallByName
.endproc

.endscope

; Functions: `EXFN.`.
.scope Functions continued

;; The `EXFN.` function: calls a .FUNC and takes the real it leaves on the stack, in the order a real argument is
;; pushed.
;; Out: FAC = the result
;; See: <Functions::ExFnInteger>, <Modules::CallByName>
;; Also: EXFN (BB13)
.proc ExFn
    jsr Modules::StartFunction
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
    ; Falls into Modules::FinishFunction.
.endproc

.endscope

; Modules: finishing a function call, and finding a record.
.scope Modules continued

;; Finishes a function call: checks the stack, frees the name's place in <NAMBUF>, and backs <TXTPTR> up one character
;; unless it is at the statement's end.
;;
;; The function must leave the stack as it found it, with the return into the evaluator, <EVALRET>, on top; anything
;; else is an undefined-function error. Only the return's low byte is compared.
;; Errors: ERRUF = the stack not as it was
;; Also: RESTNAM (BB13)
.proc FinishFunction
    pla
    pha
    cmp #<(EVALRET)
    bne ToUndefinedFunctionError
    lda NAMPNT
    sec
    sbc #NAME_LENGTH
    sta NAMPNT
    jsr CHRGOT
    beq *+5
    jmp DECTPT
    rts
.endproc

;; Ends the statement with an undefined-function error.
;; Also: PERFERR (BB13)
.proc ToUndefinedFunctionError
    jmp ERRGUF
.endproc

;; Finds the linker record of type <PROCFLG> whose 8-character name matches the one at <Modules::OtherPointer>,
;; searching from <INVTAB>.
;; Out: zero = clear when found (set when not, or when nothing is invoked), WalkPointer = the record found
;; Uses: A, Y, TEMP
;; Keeps: X
;; Also: PERFIND (BB13)
.proc FindRecord
    lda a:Segments::ModulesSegment
    beq Done                                ; nothing invoked
    lda INVTAB
    sta WalkPointer
    lda INVTAB+1
    sta WalkPointer+1
    lda INVTABB
    sta WalkPointerXByte
    ldy #LinkerRecord::TYPE
    lda (WalkPointer),Y

;; Takes the record of type A.
;; Also: PERFI01 (BB13)
CheckRecord:
    beq Done                                ; the end
    cmp #RECORD_REF
    bne CheckType
    jsr ResolveProcedures::SkipReferences   ; a .REF: skip its list
    jmp Skip

;; Compares the name when the type is <PROCFLG>.
;; Also: PERFI02 (BB13)
CheckType:
    cmp PROCFLG
    bne Skip

;; Compares the name, from its last character.
;; Also: PERFI06 (BB13)
CompareName:
    dey
    bmi Done                                ; all 8 matched
    lda (OtherPointer),Y
    cmp (WalkPointer),Y
    beq CompareName

;; Moves on to the next record.
;; Also: PERFI04 (BB13)
Skip:
    jsr NextRecord
    jmp CheckRecord

;; Returns.
;; Also: PERFI05 (BB13)
Done:
    rts
.endproc

;; Ends the statement with an out-of-memory error, for <Statements::Invoke>.
;; Also: INVERR1 (BB13)
.proc ToOutOfMemoryErrorForInvoke
    jmp OMERR
.endproc

.endscope
