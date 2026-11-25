; retrocore: style=strict
;; String space: <Strings::ReserveSpace> to make room for a string, the garbage collector that packs the strings
;; together (<Strings::CollectGarbage>), concatenation, and the routines that free a temporary string and find a string
;; from its descriptor.
;;
;; Strings live between <StringsBottom> and <MemoryTop>, growing down from <MemoryTop>. Each string has three
;; information bytes just above its characters (<STRING_INFORMATION_SIZE>): a type (0 for free space,
;; <STRING_TYPE_TEMPORARY> for a temporary, <STRING_TYPE_SIMPLE_VARIABLE> for a simple variable's,
;; <STRING_TYPE_ARRAY_ELEMENT> for an array element's), then for a string in use where its descriptor is, relative to
;; <VariablesStart> or <ArraysStart>; free space holds 0 and its length instead. A descriptor is three bytes
;; (<DESCRIPTOR_SIZE>): the string's length, then the string's distance below <MemoryTop>, low byte first, so that
;; strings can move without their descriptors pointing into another bank.

; ---------------------------------------------------------------------------------------------------------------------
; Getting space
; ---------------------------------------------------------------------------------------------------------------------

;; String space: making room for strings, temporaries, freeing and collecting garbage, and the helpers of the string
;; functions; the scope is in pieces through the files.
.scope Strings

;; Takes room for a string of A characters, and its information bytes, from the bottom of string space.
;;
;; When the room would reach <VariablesEnd>, or the strings would take more than 64K below <MemoryTop>, the garbage
;; collector packs them and this tries again; when that is not enough, it asks SOS for more memory with <Segments::Grow>
;; before collecting again, until <Segments::Grow> ends the statement with `OUT OF MEMORY`. An empty string takes no
;; room, and returns at once.
;; In: A = the length
;; Out: X, Y = the room's address, <NewString>, <NewString>+1, NewStringXByte = the room, DestinationEnd = its
;;   information bytes,
;;   A = the length
;; See: <Strings::CollectGarbage>, <AllocateForFac>
;; Also: GETSPA (BB13)
.proc ReserveSpace
;; The pages asked of <Segments::Grow> when collecting garbage was not enough.
EXPAND_PAGES = 4

    lsr CollectionState                     ; not collected yet
    and #$FF
    beq Done                                ; nothing to take for an empty string
    pha

;; Tries again to take the room for the length on the stack.
;; Also: TRYAG0 (BB13)
Try:
    lda StringsBottom
    ldy StringsBottom+1
    ldx StringsBottomXByte
    sec
    sbc #STRING_INFORMATION_SIZE
    bcs KeepInformation
    jsr Memory::PreviousPage

;; Keeps the information bytes' address and takes the characters' room below them.
;; Also: TRYAG1 (BB13)
KeepInformation:
    sty DestinationEnd+1
    stx DestinationEndXByte
    sta DestinationEnd
    pla
    pha
    eor #$FF                                ; DestinationEnd less the length
    sec
    adc DestinationEnd
    bcs CheckRoom
    jsr Memory::PreviousPage

;; Collects garbage when the room would reach <VariablesEnd>.
;; Also: TRYAG4 (BB13)
CheckRoom:
    cpx VariablesEndXByte
    bcc Collect
    bne CheckDistance
    cpy VariablesEnd+1
    bcc Collect
    bne CheckDistance
    cmp VariablesEnd
    bcc Collect

;; Takes the room, unless string space would grow past 64K below <MemoryTop>: two X-byte steps of 32K.
;; Also: TRYAG5 (BB13)
CheckDistance:
    sta NewString
    sty NewString+1
    stx NewStringXByte
    pha
    clc
    sbc MemoryTop
    tya
    sbc MemoryTop+1
    txa
    sbc MemoryTopXByte
    clc
    adc #2
    pla
    bcc Collect
    stx StringsBottomXByte
    sta StringsBottom
    sty StringsBottom+1
    ldx NewString
    ldy NewString+1
    pla

;; Returns.
;; Also: STRRT2 (BB13)
Done:
    rts

;; Packs the strings and tries again; the second time round, first asks SOS for more memory.
;;
;; The LDX of `OUT OF MEMORY` is never used: <Segments::Grow> reports the error itself.
;; Also: GARBAG (BB13)
Collect:
    ldx #ERROR_OUT_OF_MEMORY
    bit CollectionState                     ; collected already?
    bpl CollectAndRetry
    lda #EXPAND_PAGES
    jsr Segments::Grow

;; Packs the strings, then tries again.
;; Also: GARBA1 (BB13)
CollectAndRetry:
    jsr CollectGarbage
    lda #$80
    sta CollectionState
    bne Try                                 ; always
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The garbage collector
; ---------------------------------------------------------------------------------------------------------------------

;; Packs the strings in use up against <MemoryTop>, so that the free space is all below them, and sets <StringsBottom>
;; to the lowest string.
;;
;; It walks string space down from <MemoryTop>, a string at a time by its information bytes. Each run of strings in use
;; moves up with <MoveRangeUp::Unchecked> over the free space found above it; <CollectorDistance> counts the free bytes
;; so far, and each string's descriptor has its distance below <MemoryTop> reduced by that count. It borrows the
;; number reader's and `INPUT`'s bytes for its own state, under the names <CollectGarbage::ScanPointer>,
;; <CollectGarbage::FreeLength>, <CollectGarbage::FreeRunEnds> and <CollectGarbage::LastInUse>.
;; Uses: A, X, Y, Temporary, DigitsLeft, InputMode, CollectorDistance, StringInformationPointer, DigitCount,
;;   DigitsSeen, DestinationEnd, SourceEnd, SourceStart
;; Errors: <ERROR_VARIABLE> = a temporary string that no temporary descriptor points to
;; See: <Strings::ReserveSpace>
;; Also: GARBA2 (BB13)
.proc CollectGarbage

; The number reader's and INPUT's bytes, which the collector borrows while it runs.

;; The string being looked at: a pointer to its information bytes, walking down string space.
ScanPointer = DigitCount

;; <ScanPointer>'s X-byte.
ScanPointerXByte = DigitCountXByte

;; The string's length, read with its information bytes or from its descriptor.
FreeLength = DigitsSeen

;; Set when a run of free space ends at the string just taken.
FreeRunEnds = DigitsLeft

;; Whether the last string taken was in use.
LastInUse = InputMode

    lda #0
    sta Temporary
    sta FreeRunEnds
    sta LastInUse                           ; whether the last string was in use
    sta CollectorDistance                   ; the free bytes found so far
    sta CollectorDistance+1
    lda MemoryTop
    ldx MemoryTopXByte
    ldy MemoryTop+1
    sta DestinationEnd                      ; where the next string in use goes
    stx DestinationEndXByte
    sty DestinationEnd+1
    jmp CheckBottom                         ; always

;; Takes the string whose information bytes <ScanPointer> points to: one in use has its descriptor adjusted, a free one
;; adds its length to <CollectorDistance>.
;; Also: GMOVPTR (BB13)
TakeString:
    ldy #0
    lda (ScanPointer),Y                     ; the type
    sta Temporary
    iny
    lda (ScanPointer),Y
    sta StringInformationPointer            ; where the descriptor is
    iny
    lda (ScanPointer),Y
    sta StringInformationPointer+1
    sta FreeLength                          ; the length, for free space
    lda Temporary
    beq AddFree                             ; free
    eor LastInUse
    and #1
    sta FreeRunEnds                         ; set when free space ends here
    lda #1
    sta LastInUse
    lda Temporary
    cmp #STRING_TYPE_TEMPORARY
    bne NotTemporary
    jmp FindTemporary                       ; a temporary
NotTemporary:
    cmp #STRING_TYPE_ARRAY_ELEMENT
    bcc SimpleVariable                      ; a simple variable's
    lda ArraysStart+1                       ; an array element's
    pha
    lda ArraysStartXByte
    pha
    lda ArraysStart
    bcs FindDescriptor                      ; always

;; Finds a simple variable's descriptor from <VariablesStart>.
;; Also: GRELSIM (BB13)
SimpleVariable:
    lda VariablesStart+1
    pha
    lda VariablesStartXByte
    pha
    lda VariablesStart

;; Works out the descriptor's address from the base, <VariablesStart> or <ArraysStart>, and the offset in
;; <StringInformationPointer>.
;;
;; The offset is the base less the descriptor's address, packed to 16 bits by <Memory::PackPages>; its high byte, $FF
;; for every descriptor, is left out of the information bytes, so the bank comes out two X-byte steps low and gets
;; them back at the end.
;; Also: GARBREL (BB13)
FindDescriptor:
    sec
    sbc StringInformationPointer
    sta StringInformationPointer
    pla
    tay
    pla
    ldx StringInformationPointer+1
    jsr Memory::SubtractPageCount
    sta StringInformationPointer+1
    tya
    sbc #$FE                                ; the carry is set: plus 2
    sta StringInformationPointerXByte
    ldy #0
    lda (StringInformationPointer),Y        ; the string's length
    sta FreeLength

;; Reduces the distance below <MemoryTop> in the string's descriptor by <CollectorDistance>, as the string moves up.
;; Also: GRBCMP2 (BB13)
MoveDescriptor:
    ldy #1
    sec
    lda (StringInformationPointer),Y
    sbc CollectorDistance
    sta (StringInformationPointer),Y
    iny
    lda (StringInformationPointer),Y
    sbc CollectorDistance+1
    sta (StringInformationPointer),Y
    bcs StepPastText                        ; always

;; Adds a free string and its information bytes to <CollectorDistance>.
;; Also: SUBYSAV (BB13)
AddFree:
    lda CollectorDistance
    ldy CollectorDistance+1
    clc
    adc FreeLength
    bcc AddInformation
    iny
AddInformation:
    clc
    adc #STRING_INFORMATION_SIZE
    bcc KeepCount
    iny
KeepCount:
    sta CollectorDistance
    sty CollectorDistance+1
    lda LastInUse
    ora Temporary
    sta FreeRunEnds                         ; set when strings in use end here
    lda #0
    sta LastInUse

;; Steps <ScanPointer> down past the string's characters.
;; Also: SUBYS2 (BB13)
StepPastText:
    lda ScanPointer
    ldy ScanPointer+1
    ldx ScanPointerXByte
    sec
    sbc FreeLength
    bcs CheckBoundary
    jsr Memory::PreviousPage
    stx ScanPointerXByte
    sty ScanPointer+1

;; Where free space and strings in use meet, marks the top of the run of strings to move, or moves the run.
;; Also: GSUBINF (BB13)
CheckBoundary:
    pha
    lda FreeRunEnds
    beq NextString                          ; no change here
    lda Temporary
    beq MoveRun                             ; free space starts here
    lda NewString                           ; strings in use start here: the run's top
    sta SourceEnd
    lda NewStringXByte
    sta SourceEndXByte
    lda NewString+1
    sta SourceEnd+1
    jmp NextString                          ; always

;; Moves the run of strings in use, from <SourceStart> up to <SourceEnd>, to just under <DestinationEnd>.
;; Also: GSUBIN1 (BB13)
MoveRun:
    lda NewString
    sta SourceStart
    lda NewStringXByte
    sta SourceStartXByte
    lda NewString+1
    sta SourceStart+1
    txa
    pha
    tya
    pha
    jsr MoveRangeUp::Unchecked
    pla
    tay
    pla
    tax

;; Goes on to the next string down.
;; Also: GSUBIN2 (BB13)
NextString:
    pla

;; Goes on to the string below A, Y and bank X, or ends at <StringsBottom>, moving the last run of strings in use.
;; Also: GSUBIN3 (BB13)
CheckBottom:
    sta NewString
    sty NewString+1
    stx NewStringXByte
    cpx StringsBottomXByte
    bne PointAtInformation
    cpy StringsBottom+1
    bne PointAtInformation
    cmp StringsBottom
    bne PointAtInformation
    lda Temporary                           ; free space at the bottom?
    beq Finish
    lda StringsBottom
    sta SourceStart
    stx SourceStartXByte
    sty SourceStart+1
    jmp MoveLastRun

;; Points <ScanPointer> at the next string's information bytes.
;; Also: GMOVCHK (BB13)
PointAtInformation:
    sec
    sbc #STRING_INFORMATION_SIZE
    bcs SetPointer
    jsr Memory::PreviousPage

;; Sets <ScanPointer> and takes the next string.
;; Also: GSUBIN4 (BB13)
SetPointer:
    stx ScanPointerXByte
    sty ScanPointer+1
    sta ScanPointer
    jmp TakeString

;; Moves the last run of strings in use up.
;; Also: GRBLTUC (BB13)
MoveLastRun:
    jsr MoveRangeUp::Unchecked

;; Sets <StringsBottom> to the lowest string, and ends the collection.
;; Also: GRBDON (BB13)
Finish:
    lda DestinationEnd
    sta StringsBottom
    lda DestinationEnd+1
    sta StringsBottom+1
    lda DestinationEndXByte
    sta StringsBottomXByte
    rts

;; Finds the temporary descriptor in <TemporaryDescriptors> that points to this string, and adjusts it; a temporary
;; string that none points to ends the statement with a VARIABLE error.
;; Also: GFINDTEMP (BB13)
FindTemporary:
    lda #0
    sta StringInformationPointerXByte
    lda #<(TemporaryDescriptors)
    ldx #>(TemporaryDescriptors)
    sta StringInformationPointer
    stx StringInformationPointer+1

;; Tries the temporary descriptor at <StringInformationPointer>: is its string's end this string's information bytes?
;; Also: GARBTEMP (BB13)
CheckTemporary:
    cmp NextTemporary                       ; past the last temporary?
    beq NoTemporary
    ldy #0
    lda (StringInformationPointer),Y        ; the length
    beq NextTemporaryDescriptor             ; empty
    sta FreeLength
    iny
    iny
    lda (StringInformationPointer),Y        ; the distance below MemoryTop: the high byte
    tax
    dey
    lda MemoryTop
    sec
    sbc (StringInformationPointer),Y        ; and the low
    sta SourceStart
    lda MemoryTop+1
    ldy MemoryTopXByte
    jsr Memory::SubtractPageCount
    sta SourceStart+1
    sty SourceStartXByte
    lda SourceStart
    clc
    adc FreeLength                          ; the string's end
    sta SourceStart
    ldy SourceStart+1
    ldx SourceStartXByte
    bcc CompareEnd
    iny
    jsr Memory::WrapPage
CompareEnd:
    cpx ScanPointerXByte
    bne NextTemporaryDescriptor
    cpy ScanPointer+1
    bne NextTemporaryDescriptor
    cmp ScanPointer
    bne NextTemporaryDescriptor
    jmp MoveDescriptor                      ; this one

;; Steps to the next temporary descriptor.
;; Also: DVARTS (BB13)
NextTemporaryDescriptor:
    lda #DESCRIPTOR_SIZE
    clc
    adc StringInformationPointer
    sta StringInformationPointer
    jmp CheckTemporary

;; Ends the statement with a VARIABLE error: a temporary string that no temporary descriptor points to.
;; Also: NOTEMP (BB13)
NoTemporary:
    ldx #ERROR_VARIABLE
    jmp ReportError
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Concatenation
; ---------------------------------------------------------------------------------------------------------------------

;; Concatenates two strings into a new temporary string, freeing their temporaries.
;; In: ArgMantissa3, ArgMantissa3+1, ArgMantissa3XByte = the left string's descriptor, <FacMantissa3>, <FacMantissa3>+1,
;;   FacMantissa3XByte = the right string's
;; Out: FacMantissa3, FacMantissa3+1 = the new temporary descriptor
;; Errors: <ERROR_STRING_TOO_LONG> = the two together are longer than 255 characters
;; See: <AllocateForFac>, <Strings::CopyString>, <PushTemporary>
;; Also: CONCAT (BB13)
.proc Concatenate
    ldy #0
    lda (FacMantissa3),Y
    clc
    adc (ArgMantissa3),Y                    ; the two lengths
    bcc LengthOk
    jsr ReleaseOperands
    ldx #ERROR_STRING_TOO_LONG
    jmp ReportError

;; Takes room for the joined string, and copies the left string into it.
;; Also: SIZEOK (BB13)
LengthOk:
    jsr AllocateForFac
    ldx ArgMantissa3
    ldy ArgMantissa3+1
    stx StringPointer
    sty StringPointer+1
    ldx ArgMantissa3XByte
    stx StringPointerXByte
    jsr CopyString
    clc
    adc NewString                           ; past the left string
    sta NewString
    bcc CopyRight
    inc NewString+1
    lda NewString+1
    cmp #POINTER_PAGE_LIMIT
    bcc CopyRight
    sbc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST
    inc NewStringXByte
    sta NewString+1

;; Copies the right string after it, frees both temporaries and makes the result's.
;; Also: CAT10 (BB13)
CopyRight:
    ldx FacMantissa3
    ldy FacMantissa3+1
    stx StringPointer
    sty StringPointer+1
    ldx FacMantissa3XByte
    stx StringPointerXByte
    jsr CopyString
    jsr ReleaseOperands
    jmp PushTemporary
.endproc

;; Frees the <Fac>'s and <Arg>'s strings, if they are the last temporaries.
;; See: <FreeFacTemporary>, <FreeTemporary>
;; Also: CAT11 (BB13)
.proc ReleaseOperands
    jsr FreeFacTemporary
    lda ArgMantissa3
    ldy ArgMantissa3+1
    ldx ArgMantissa3XByte
    jmp FreeTemporary
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Finding and freeing strings
; ---------------------------------------------------------------------------------------------------------------------

;; Turns <Pointer1> from a distance below <MemoryTop> into an address, or back: it is <MemoryTop> less <Pointer1> either
;; way.
;; In: Pointer1, Pointer1+1, Pointer1XByte = the address or the distance
;; Out: Pointer1, Pointer1+1, Pointer1XByte = the other
;; Uses: SavedY
;; Keeps: A, X, Y
;; Also: MAKREL (BB13)
.proc SubtractFromHighMemory
    pha
    lda MemoryTop
    sec
    sbc Pointer1
    sta Pointer1
    lda MemoryTop+1
    sty SavedY
    ldy MemoryTopXByte
    sbc Pointer1+1
    jsr Memory::NormalizeAfterSubtract
    sta Pointer1+1
    tya
    sbc Pointer1XByte
    sta Pointer1XByte
    ldy SavedY
    pla
    rts
.endproc

;; Copies the string whose descriptor <StringPointer> points to into the room at <NewString>.
;; In: StringPointer, StringPointer+1, StringPointerXByte = the descriptor's address
;; Out: A = the length
;; See: <Strings::CopyBytes>
;; Also: MOVINS (BB13)
.proc CopyString
    ldy #0
    lda (StringPointer),Y                   ; the length
    pha
    iny
    lda (StringPointer),Y
    tax
    iny
    lda (StringPointer),Y
    ldy #0
    jsr Memory::UnpackPages
    sty Pointer1XByte
    stx Pointer1
    sta Pointer1+1
    jsr SubtractFromHighMemory              ; the string's address
    pla
    ; Falls into CopyBytes.
.endproc

;; Copies A bytes from <Pointer1> to <NewString>, last byte first.
;; In: A = the count, Pointer1 = the source
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
    lda (Pointer1),Y
    sta (NewString),Y
    tya
    bne Loop
    pla

;; Returns.
;; Also: MVSTRT (BB13)
Done:
    rts
.endproc

;; Frees the temporary descriptor of the <Fac>'s string, if it is the last temporary, and finds the string, returning
;; as <Strings::ReleaseDescriptor> does.
;; Also: FREFAC (BB13)
.proc ReleaseFac
    lda FacMantissa3
    ldx FacMantissa3XByte
    ldy FacMantissa3+1
    ; Falls into ReleaseDescriptor.
.endproc

;; Frees a temporary descriptor, if it is the last one made, and finds its string.
;;
;; The string's own space is freed only by <Strings::FreeSpaceIfReleased>, when the zero flag says the descriptor was
;; freed.
;; In: A, Y = the descriptor's address, X = its bank
;; Out: A = the length, X, Y = the string's address, <Pointer1>, <Pointer1>+1, Pointer1XByte = the string,
;;   zero = set when the descriptor was the last temporary and is now free
;; See: <Strings::ReleaseTemporary>, <Strings::FindFromDescriptor>
;; Also: FRETMP (BB13)
.proc ReleaseDescriptor
    sta Pointer1
    stx Pointer1XByte
    sty Pointer1+1
    jsr ReleaseTemporary
    ; Falls into FindFromDescriptor.
.endproc

;; Finds the string whose descriptor <Pointer1> points to.
;; In: Pointer1, Pointer1+1, Pointer1XByte = the descriptor's address
;; Out: A = the length, X, Y = the string's address, <Pointer1>, <Pointer1>+1, Pointer1XByte = the string, the flags as
;;   they came in
;; Also: NOTNOW (BB13)
.proc FindFromDescriptor
    php                                     ; ReleaseTemporary's zero flag, for the caller
    ldy #0
    lda (Pointer1),Y                        ; the length
    pha
    iny
    lda (Pointer1),Y
    tax
    iny
    lda (Pointer1),Y
    ldy #0
    jsr Memory::UnpackPages
    sty Pointer1XByte
    sta Pointer1+1
    stx Pointer1
    jsr SubtractFromHighMemory
    ldx Pointer1
    ldy Pointer1+1
    pla
    plp
    rts
.endproc

;; Finds the <Fac>'s string again and frees its space when the zero flag says to.
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
;; In: zero = set to free it, A = the length, Pointer1 = the string
;; See: <Strings::FreeSpace>
;; Also: FRENOW (BB13)
.proc FreeSpaceIfReleased
    bne ReleaseTemporary::Done
    ; Falls into FreeSpace.
.endproc

;; Marks a string's space free, unless the string is empty.
;; In: A = the length, Pointer1 = the string
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
    lda #<(TemporaryDescriptors)
    cmp NextTemporary                       ; any temporaries?
    pla
    bcc Some
    lda #$FF                                ; none: zero clear
    rts
Some:
    cpy LastTemporary+1                     ; the last one?
    bne Done
    cmp LastTemporary
    bne Done
    sta NextTemporary
    sbc #DESCRIPTOR_SIZE
    sta LastTemporary
    ldy #0                                  ; zero set: freed

;; Returns.
;; Also: FRERTS (BB13)
Done:
    rts
.endproc

;; Finds the <Fac>'s string from its descriptor, without freeing anything, returning as
;; <Strings::FindFromDescriptor> does.
;; Also: NOTFAC (BB13)
.proc FindFacString
    lda FacMantissa3
    ldy FacMantissa3+1
    ldx FacMantissa3XByte
    ; Falls into FindFromDescriptorAt.
.endproc

;; Finds the string whose descriptor is at A, Y and bank X, without freeing anything, returning as
;; <Strings::FindFromDescriptor> does.
;; Also: NOTNW2 (BB13)
.proc FindFromDescriptorAt
    sta Pointer1
    sty Pointer1+1
    stx Pointer1XByte
    jmp FindFromDescriptor
.endproc

.endscope
