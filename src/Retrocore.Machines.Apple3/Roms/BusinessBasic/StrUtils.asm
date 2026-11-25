; retrocore: style=strict
;; String space: <Strings::ReserveSpace> to make room for a string, the garbage collector that packs the strings
;; together (<Strings::CollectGarbage>), concatenation, and the routines that free a temporary string and find a string
;; from its descriptor.
;;
;; Strings live between <FRETOP> and <HIMEM>, growing down from <HIMEM>. Each string has three information bytes just
;; above its characters (<INFOSIZ>): a type (0 for free space, <TEMPTYP> for a temporary, <SIMTYP> for a simple
;; variable's, <ARYTYP> for an array element's), then for a string in use where its descriptor is, relative to
;; <VARTAB> or <ARYTAB>; free space holds 0 and its length instead. A descriptor is three bytes (<STRSIZ>): the
;; string's length, then the string's distance below <HIMEM>, low byte first, so that strings can move without their
;; descriptors pointing into another bank.

; ---------------------------------------------------------------------------------------------------------------------
; Getting space
; ---------------------------------------------------------------------------------------------------------------------

.scope Strings continued

;; Takes room for a string of A characters, and its information bytes, from the bottom of string space.
;;
;; When the room would reach <STREND>, or the strings would take more than 64K below <HIMEM>, the garbage collector
;; packs them and this tries again; when that is not enough, it asks SOS for more memory with <EXPAND> before
;; collecting again, until <EXPAND> ends the statement with OUT OF MEMORY. An empty string takes no room, and returns
;; at once.
;; In: A = the length
;; Out: X, Y = the room's address, <FRESPC>, <FRESPC>+1, FRESPCB = the room, HIGHDS = its information bytes,
;;   A = the length
;; See: <Strings::CollectGarbage>, <STRINI>
;; Also: GETSPA (BB13)
.proc ReserveSpace
;; The pages asked of <EXPAND> when collecting garbage was not enough.
EXPAND_PAGES = 4

    lsr GARBFL                              ; not collected yet
    and #$FF
    beq Done                                ; nothing to take for an empty string
    pha

;; Tries again to take the room for the length on the stack.
;; Also: TRYAG0 (BB13)
Try:
    lda FRETOP
    ldy FRETOP+1
    ldx FRETOPB
    sec
    sbc #INFOSIZ
    bcs KeepInformation
    jsr Memory::PreviousPage

;; Keeps the information bytes' address and takes the characters' room below them.
;; Also: TRYAG1 (BB13)
KeepInformation:
    sty HIGHDS+1
    stx HIGHDSB
    sta HIGHDS
    pla
    pha
    eor #$FF                                ; HIGHDS less the length
    sec
    adc HIGHDS
    bcs CheckRoom
    jsr Memory::PreviousPage

;; Collects garbage when the room would reach <STREND>.
;; Also: TRYAG4 (BB13)
CheckRoom:
    cpx STRENDB
    bcc Collect
    bne CheckDistance
    cpy STREND+1
    bcc Collect
    bne CheckDistance
    cmp STREND
    bcc Collect

;; Takes the room, unless string space would grow past 64K below <HIMEM>: two X-byte steps of 32K.
;; Also: TRYAG5 (BB13)
CheckDistance:
    sta FRESPC
    sty FRESPC+1
    stx FRESPCB
    pha
    clc
    sbc HIMEM
    tya
    sbc HIMEM+1
    txa
    sbc HIMEMB
    clc
    adc #2
    pla
    bcc Collect
    stx FRETOPB
    sta FRETOP
    sty FRETOP+1
    ldx FRESPC
    ldy FRESPC+1
    pla

;; Returns.
;; Also: STRRT2 (BB13)
Done:
    rts

;; Packs the strings and tries again; the second time round, first asks SOS for more memory.
;;
;; The LDX of OUT OF MEMORY is never used: <EXPAND> reports the error itself.
;; Also: GARBAG (BB13)
Collect:
    ldx #ERROM
    bit GARBFL                              ; collected already?
    bpl CollectAndRetry
    lda #EXPAND_PAGES
    jsr EXPAND

;; Packs the strings, then tries again.
;; Also: GARBA1 (BB13)
CollectAndRetry:
    jsr CollectGarbage
    lda #$80
    sta GARBFL
    bne Try                                 ; always
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The garbage collector
; ---------------------------------------------------------------------------------------------------------------------

;; Packs the strings in use up against <HIMEM>, so that the free space is all below them, and sets <FRETOP> to the
;; lowest string.
;;
;; It walks string space down from <HIMEM>, a string at a time by its information bytes. Each run of strings in use
;; moves up with <BLTUC> over the free space found above it; <GRBPNT> counts the free bytes so far, and each string's
;; descriptor has its distance below <HIMEM> reduced by that count.
;; Uses: A, X, Y, TEMP, CNTDIGS, INPFLG, GRBPNT, HEADER, DECCNT, ANYNUM, HIGHDS, HIGHTR, LOWTR
;; Errors: ERRVA = a temporary string that no temporary descriptor points to
;; See: <Strings::ReserveSpace>
;; Also: GARBA2 (BB13)
.proc CollectGarbage
    lda #0
    sta TEMP
    sta CNTDIGS
    sta INPFLG                              ; whether the last string was in use
    sta GRBPNT                              ; the free bytes found so far
    sta GRBPNT+1
    lda HIMEM
    ldx HIMEMB
    ldy HIMEM+1
    sta HIGHDS                              ; where the next string in use goes
    stx HIGHDSB
    sty HIGHDS+1
    jmp CheckBottom                         ; always

;; Takes the string whose information bytes <DECCNT> points to: one in use has its descriptor adjusted, a free one
;; adds its length to <GRBPNT>.
;; Also: GMOVPTR (BB13)
TakeString:
    ldy #0
    lda (DECCNT),Y                          ; the type
    sta TEMP
    iny
    lda (DECCNT),Y
    sta HEADER                              ; where the descriptor is
    iny
    lda (DECCNT),Y
    sta HEADER+1
    sta ANYNUM                              ; the length, for free space
    lda TEMP
    beq AddFree                             ; free
    eor INPFLG
    and #1
    sta CNTDIGS                             ; set when free space ends here
    lda #1
    sta INPFLG
    lda TEMP
    cmp #TEMPTYP
    bne NotTemporary
    jmp FindTemporary                       ; a temporary
NotTemporary:
    cmp #ARYTYP
    bcc SimpleVariable                      ; a simple variable's
    lda ARYTAB+1                            ; an array element's
    pha
    lda ARYTABB
    pha
    lda ARYTAB
    bcs FindDescriptor                      ; always

;; Finds a simple variable's descriptor from <VARTAB>.
;; Also: GRELSIM (BB13)
SimpleVariable:
    lda VARTAB+1
    pha
    lda VARTABB
    pha
    lda VARTAB

;; Works out the descriptor's address from the base, <VARTAB> or <ARYTAB>, and the offset in <HEADER>.
;;
;; The offset is the base less the descriptor's address, packed to 16 bits by <Memory::PackPages>; its high byte, $FF
;; for every descriptor, is left out of the information bytes, so the bank comes out two X-byte steps low and gets
;; them back at the end.
;; Also: GARBREL (BB13)
FindDescriptor:
    sec
    sbc HEADER
    sta HEADER
    pla
    tay
    pla
    ldx HEADER+1
    jsr Memory::SubtractPageCount
    sta HEADER+1
    tya
    sbc #$FE                                ; the carry is set: plus 2
    sta HEADERB
    ldy #0
    lda (HEADER),Y                          ; the string's length
    sta ANYNUM

;; Moves the string's descriptor up by <GRBPNT> bytes, closer to <HIMEM>.
;; Also: GRBCMP2 (BB13)
MoveDescriptor:
    ldy #1
    sec
    lda (HEADER),Y
    sbc GRBPNT
    sta (HEADER),Y
    iny
    lda (HEADER),Y
    sbc GRBPNT+1
    sta (HEADER),Y
    bcs StepPastText                        ; always

;; Adds a free string and its information bytes to <GRBPNT>.
;; Also: SUBYSAV (BB13)
AddFree:
    lda GRBPNT
    ldy GRBPNT+1
    clc
    adc ANYNUM
    bcc AddInformation
    iny
AddInformation:
    clc
    adc #INFOSIZ
    bcc KeepCount
    iny
KeepCount:
    sta GRBPNT
    sty GRBPNT+1
    lda INPFLG
    ora TEMP
    sta CNTDIGS                             ; set when strings in use end here
    lda #0
    sta INPFLG

;; Steps <DECCNT> down past the string's characters.
;; Also: SUBYS2 (BB13)
StepPastText:
    lda DECCNT
    ldy DECCNT+1
    ldx DECCNTB
    sec
    sbc ANYNUM
    bcs CheckBoundary
    jsr Memory::PreviousPage
    stx DECCNTB
    sty DECCNT+1

;; Where free space and strings in use meet, marks the top of the run of strings to move, or moves the run.
;; Also: GSUBINF (BB13)
CheckBoundary:
    pha
    lda CNTDIGS
    beq NextString                          ; no change here
    lda TEMP
    beq MoveRun                             ; free space starts here
    lda FRESPC                              ; strings in use start here: the run's top
    sta HIGHTR
    lda FRESPCB
    sta HIGHTRB
    lda FRESPC+1
    sta HIGHTR+1
    jmp NextString                          ; always

;; Moves the run of strings in use, from <LOWTR> up to <HIGHTR>, to just under <HIGHDS>.
;; Also: GSUBIN1 (BB13)
MoveRun:
    lda FRESPC
    sta LOWTR
    lda FRESPCB
    sta LOWTRB
    lda FRESPC+1
    sta LOWTR+1
    txa
    pha
    tya
    pha
    jsr BLTUC
    pla
    tay
    pla
    tax

;; Goes on to the next string down.
;; Also: GSUBIN2 (BB13)
NextString:
    pla

;; Goes on to the string below A, Y and bank X, or ends at <FRETOP>, moving the last run of strings in use.
;; Also: GSUBIN3 (BB13)
CheckBottom:
    sta FRESPC
    sty FRESPC+1
    stx FRESPCB
    cpx FRETOPB
    bne PointAtInformation
    cpy FRETOP+1
    bne PointAtInformation
    cmp FRETOP
    bne PointAtInformation
    lda TEMP                                ; free space at the bottom?
    beq Finish
    lda FRETOP
    sta LOWTR
    stx LOWTRB
    sty LOWTR+1
    jmp MoveLastRun

;; Points <DECCNT> at the next string's information bytes.
;; Also: GMOVCHK (BB13)
PointAtInformation:
    sec
    sbc #INFOSIZ
    bcs SetPointer
    jsr Memory::PreviousPage

;; Sets <DECCNT> and takes the next string.
;; Also: GSUBIN4 (BB13)
SetPointer:
    stx DECCNTB
    sty DECCNT+1
    sta DECCNT
    jmp TakeString

;; Moves the last run of strings in use up.
;; Also: GRBLTUC (BB13)
MoveLastRun:
    jsr BLTUC

;; Sets <FRETOP> to the lowest string, and ends the collection.
;; Also: GRBDON (BB13)
Finish:
    lda HIGHDS
    sta FRETOP
    lda HIGHDS+1
    sta FRETOP+1
    lda HIGHDSB
    sta FRETOPB
    rts

;; Finds the temporary descriptor in <TEMPST> that points to this string, and adjusts it; a temporary string that
;; none points to ends the statement with a VARIABLE error.
;; Also: GFINDTEMP (BB13)
FindTemporary:
    lda #0
    sta HEADERB
    lda #<(TEMPST)
    ldx #>(TEMPST)
    sta HEADER
    stx HEADER+1

;; Tries the temporary descriptor at <HEADER>: is its string's end this string's information bytes?
;; Also: GARBTEMP (BB13)
CheckTemporary:
    cmp TEMPPT                              ; past the last temporary?
    beq NoTemporary
    ldy #0
    lda (HEADER),Y                          ; the length
    beq NextTemporary                       ; empty
    sta ANYNUM
    iny
    iny
    lda (HEADER),Y                          ; the distance below HIMEM: the high byte
    tax
    dey
    lda HIMEM
    sec
    sbc (HEADER),Y                          ; and the low
    sta LOWTR
    lda HIMEM+1
    ldy HIMEMB
    jsr Memory::SubtractPageCount
    sta LOWTR+1
    sty LOWTRB
    lda LOWTR
    clc
    adc ANYNUM                              ; the string's end
    sta LOWTR
    ldy LOWTR+1
    ldx LOWTRB
    bcc CompareEnd
    iny
    jsr Memory::WrapPage
CompareEnd:
    cpx DECCNTB
    bne NextTemporary
    cpy DECCNT+1
    bne NextTemporary
    cmp DECCNT
    bne NextTemporary
    jmp MoveDescriptor                      ; this one

;; Steps to the next temporary descriptor.
;; Also: DVARTS (BB13)
NextTemporary:
    lda #STRSIZ
    clc
    adc HEADER
    sta HEADER
    jmp CheckTemporary

;; Ends the statement with a VARIABLE error: a temporary string that no temporary descriptor points to.
;; Also: NOTEMP (BB13)
NoTemporary:
    ldx #ERRVA
    jmp ERROR
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Concatenation
; ---------------------------------------------------------------------------------------------------------------------

;; Concatenates two strings into a new temporary string, freeing their temporaries.
;; In: ARGMO, ARGMO+1, ARGMOB = the left string's descriptor, <FACMO>, <FACMO>+1, FACMOB = the right string's
;; Out: FACMO, FACMO+1 = the new temporary descriptor
;; Errors: ERRLS = the two together are longer than 255 characters
;; See: <STRINI>, <Strings::CopyString>, <PUTNEW>
;; Also: CONCAT (BB13)
.proc Concatenate
    ldy #0
    lda (FACMO),Y
    clc
    adc (ARGMO),Y                           ; the two lengths
    bcc LengthOk
    jsr ReleaseOperands
    ldx #ERRLS
    jmp ERROR

;; Takes room for the joined string, and copies the left string into it.
;; Also: SIZEOK (BB13)
LengthOk:
    jsr STRINI
    ldx ARGMO
    ldy ARGMO+1
    stx STRNG1
    sty STRNG1+1
    ldx ARGMOB
    stx STRNG1B
    jsr CopyString
    clc
    adc FRESPC                              ; past the left string
    sta FRESPC
    bcc CopyRight
    inc FRESPC+1
    lda FRESPC+1
    cmp #MAXPG
    bcc CopyRight
    sbc #MAXPG-MINPG
    inc FRESPCB
    sta FRESPC+1

;; Copies the right string after it, frees both temporaries and makes the result's.
;; Also: CAT10 (BB13)
CopyRight:
    ldx FACMO
    ldy FACMO+1
    stx STRNG1
    sty STRNG1+1
    ldx FACMOB
    stx STRNG1B
    jsr CopyString
    jsr ReleaseOperands
    jmp PUTNEW
.endproc

;; Frees the <FAC>'s and <ARG>'s strings, if they are the last temporaries.
;; See: <FRECNOW>, <FRETNOW>
;; Also: CAT11 (BB13)
.proc ReleaseOperands
    jsr FRECNOW
    lda ARGMO
    ldy ARGMO+1
    ldx ARGMOB
    jmp FRETNOW
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Finding and freeing strings
; ---------------------------------------------------------------------------------------------------------------------

;; Turns <INDEX> from a distance below <HIMEM> into an address, or back: it is <HIMEM> less <INDEX> either way.
;; In: INDEX, INDEX+1, INDEXB = the address or the distance
;; Out: INDEX, INDEX+1, INDEXB = the other
;; Uses: YSAVE
;; Keeps: A, X, Y
;; Also: MAKREL (BB13)
.proc SubtractFromHighMemory
    pha
    lda HIMEM
    sec
    sbc INDEX
    sta INDEX
    lda HIMEM+1
    sty YSAVE
    ldy HIMEMB
    sbc INDEX+1
    jsr Memory::NormalizeAfterSubtract
    sta INDEX+1
    tya
    sbc INDEXB
    sta INDEXB
    ldy YSAVE
    pla
    rts
.endproc

;; Copies the string whose descriptor <STRNG1> points to into the room at <FRESPC>.
;; In: STRNG1, STRNG1+1, STRNG1B = the descriptor's address
;; Out: A = the length
;; See: <Strings::CopyBytes>
;; Also: MOVINS (BB13)
.proc CopyString
    ldy #0
    lda (STRNG1),Y                          ; the length
    pha
    iny
    lda (STRNG1),Y
    tax
    iny
    lda (STRNG1),Y
    ldy #0
    jsr Memory::UnpackPages
    sty INDEXB
    stx INDEX
    sta INDEX+1
    jsr SubtractFromHighMemory              ; the string's address
    pla
    ; Falls into CopyBytes.
.endproc

;; Copies A bytes from <INDEX> to <FRESPC>, last byte first.
;; In: A = the count, INDEX = the source
;; Out: A = the count, Y = 0
;; Keeps: X
;; Also: MOVDO (BB13)
.proc CopyBytes
    tay
    beq Done
    pha

;; Copies one byte.
;; Also: MOVLP (BB13)
Loop:
    dey
    lda (INDEX),Y
    sta (FRESPC),Y
    tya
    bne Loop
    pla

;; Returns.
;; Also: MVSTRT (BB13)
Done:
    rts
.endproc

;; Frees the temporary descriptor of the <FAC>'s string, if it is the last temporary, and finds the string, returning
;; as <Strings::ReleaseDescriptor> does.
;; Also: FREFAC (BB13)
.proc ReleaseFac
    lda FACMO
    ldx FACMOB
    ldy FACMO+1
    ; Falls into ReleaseDescriptor.
.endproc

;; Frees a temporary descriptor, if it is the last one made, and finds its string.
;;
;; The string's own space is freed only by <Strings::FreeSpaceIfReleased>, when the zero flag says the descriptor was
;; freed.
;; In: A, Y = the descriptor's address, X = its bank
;; Out: A = the length, X, Y = the string's address, <INDEX>, <INDEX>+1, INDEXB = the string,
;;   zero = set when the descriptor was the last temporary and is now free
;; See: <Strings::ReleaseTemporary>, <Strings::FindFromDescriptor>
;; Also: FRETMP (BB13)
.proc ReleaseDescriptor
    sta INDEX
    stx INDEXB
    sty INDEX+1
    jsr ReleaseTemporary
    ; Falls into FindFromDescriptor.
.endproc

;; Finds the string whose descriptor <INDEX> points to.
;; In: INDEX, INDEX+1, INDEXB = the descriptor's address
;; Out: A = the length, X, Y = the string's address, <INDEX>, <INDEX>+1, INDEXB = the string, the flags as they came in
;; Also: NOTNOW (BB13)
.proc FindFromDescriptor
    php                                     ; ReleaseTemporary's zero flag, for the caller
    ldy #0
    lda (INDEX),Y                           ; the length
    pha
    iny
    lda (INDEX),Y
    tax
    iny
    lda (INDEX),Y
    ldy #0
    jsr Memory::UnpackPages
    sty INDEXB
    sta INDEX+1
    stx INDEX
    jsr SubtractFromHighMemory
    ldx INDEX
    ldy INDEX+1
    pla
    plp
    rts
.endproc

;; Finds the <FAC>'s string again and frees its space when the zero flag says to.
;; In: zero = set to free it
;; See: <Strings::FreeSpaceIfReleased>
;; Also: FREFC1 (BB13)
.proc FreeFacIfReleased
    php
    jsr ReleaseFac
    plp
    ; Falls into FreeSpaceIfReleased.
.endproc

;; Frees a string's space, when the zero flag says its temporary descriptor was freed.
;; In: zero = set to free it, A = the length, INDEX = the string
;; See: <Strings::FreeSpace>
;; Also: FRENOW (BB13)
.proc FreeSpaceIfReleased
    bne ReleaseTemporary::Done
    ; Falls into FreeSpace.
.endproc

;; Marks a string's space free, unless the string is empty.
;; In: A = the length, INDEX = the string
;; See: <Strings::MarkFree>
;; Also: FRESPA (BB13)
.proc FreeSpace
    cmp #0
    beq ReleaseTemporary::Done
    jmp MarkFree
.endproc

;; Frees the temporary descriptor at A, Y, if it is the last one made.
;; In: A, Y = the descriptor's address
;; Out: zero = set when it was freed
;; Keeps: X
;; Entry:
;;   Done = returns; <Strings::FreeSpaceIfReleased> and <Strings::FreeSpace> branch here
;; Also: FRETMS (BB13)
.proc ReleaseTemporary
    pha
    lda #<(TEMPST)
    cmp TEMPPT                              ; any temporaries?
    pla
    bcc Some
    lda #$FF                                ; none: zero clear
    rts
Some:
    cpy LASTPT+1                            ; the last one?
    bne Done
    cmp LASTPT
    bne Done
    sta TEMPPT
    sbc #STRSIZ
    sta LASTPT
    ldy #0                                  ; zero set: freed

;; Returns.
;; Also: FRERTS (BB13)
Done:
    rts
.endproc

;; Finds the <FAC>'s string from its descriptor, without freeing anything, returning as
;; <Strings::FindFromDescriptor> does.
;; Also: NOTFAC (BB13)
.proc FindFacString
    lda FACMO
    ldy FACMO+1
    ldx FACMOB
    ; Falls into FindFromDescriptorAt.
.endproc

;; Finds the string whose descriptor is at A, Y and bank X, without freeing anything, returning as
;; <Strings::FindFromDescriptor> does.
;; Also: NOTNW2 (BB13)
.proc FindFromDescriptorAt
    sta INDEX
    sty INDEX+1
    stx INDEXB
    jmp FindFromDescriptor
.endproc

.endscope
