; retrocore: style=strict
; Invoke1.asm: the `INVOKE` statement, which finds a segment for the modules and loads them; the SOS memory calls'
; parameter lists; and shrinking and growing BASIC's segment, which give its free memory back to SOS and take it again.
;
; BASIC's program and data live in one segment, ID $11, that <Segments::FindForBasic> takes at start; invoked modules
; live in another, ID $12, in one bank. Addresses here are BASIC's form: an offset in a bank, its page from $02 to
; $81, with the bank byte beside it. SOS gives a segment's base and limit as a bank and a page in the bank-switched
; window, $20 to $9F.
;
; Apple's listing calls this file INVOKE1; its names are kept in each definition's Also: section.

; ---------------------------------------------------------------------------------------------------------------------
; `INVOKE`
; ---------------------------------------------------------------------------------------------------------------------

; Statements: `INVOKE`.
.scope Statements continued

;; The `INVOKE` statement: replaces the invoked modules with the ones the statement names, or with none.
;;
;; Gives all free memory back to SOS with <Segments::Shrink> and releases the old modules' segment. Each file is then
;; opened once to add up its size, less its first block; a segment of that many pages and one more is found in one
;; bank, <Modules::Load> loads the modules into it, and the pages they leave unused are given back from its base.
;; <Segments::Grow> then takes back as much memory as SOS gives.
;;
;; An error part way, such as a file that can't be opened or no segment found, leaves the released segment's number
;; in <Segments::ModulesSegment>, so `PERFORM` and `EXFN.` still search the released memory for records.
;; In: TextPointer = the file names, separated by commas, or the statement's end
;; Errors: <ERROR_OUT_OF_MEMORY> = the files too big for one segment, or none found; the errors of opening a file and
;;   loading it
;; See: <Modules::Load>, <Segments::FindModulesList>, <Modules::FindRecord>
;; Also: INVOKE (BB13)
.proc Invoke
    lda #0                                  ; not RUN or CHAIN
    sta ProgramLoading
.if VERSION >= 130
    jsr ProgramPrefix::UseProgram           ; 1.3: use the program's prefix
.endif
    lda #0
    jsr Segments::Shrink                    ; all the free memory back to SOS
    lda a:Segments::ModulesSegment
    beq CheckNames                          ; nothing invoked yet
    brk
    .byte SOS_RELEASE_SEGMENT
    .word Segments::ReleaseModulesList

;; Loads the modules named, or with no name releases them all.
;; Also: INVOK1 (BB13)
CheckNames:
    jsr GetCurrentCharacter
    bne AddSizes
    jmp ReleaseAll

;; Adds up the files' sizes, in pages, in <ReferencePointers> (pages) and <ReferencePointers>+1 (bytes).
;; Also: INVOK3 (BB13)
AddSizes:
    lda #0
    sta ReferencePointers
    sta ReferencePointers+1
    jsr SaveTextPointer                     ; to read the names again

;; Opens the next file, adds its size less the first block, and closes it again.
;;
;; Opening it now, before the segment is found, lets SOS find room for the file's buffer.
;; Also: INVOK4 (BB13)
AddSize:
    lda #1                                  ; to read
    ldx #FILE_TYPE_PASCAL_CODE              ; a code file
    jsr Files::OpenOfType
    lda SosCalls::FileEnd                   ; the file's size, from Files::OpenOfType
    clc
    adc ReferencePointers+1
    sta ReferencePointers+1
    lda SosCalls::FileEnd+1
    adc ReferencePointers
    bcs Modules::ToOutOfMemoryErrorForInvoke
    sec
    sbc #Modules::BLOCK_PAGES               ; less the first block
    bcc Modules::ToOutOfMemoryErrorForInvoke
    sta ReferencePointers
    jsr Files::CloseSosFile
    jsr GetCurrentCharacter
    beq *+8                                 ; the last name
    jsr CheckComma
    jmp AddSize
    ldx ReferencePointers                   ; one more page, for the bytes past the last
    inx
    beq Modules::ToOutOfMemoryErrorForInvoke
    stx a:Segments::ModulesPages
    ldx #0
    stx a:Segments::ModulesPages+1
    jsr RestoreTextPointer
    brk
    .byte SOS_FIND_SEGMENT                  ; a segment in one bank
    .word Segments::FindModulesList
    bne Modules::ToOutOfMemoryErrorForInvoke
    lda a:Segments::FoundModulesSegment
    sta a:Segments::ModulesSegment
    sta a:Segments::ShrinkModulesSegment
    lda a:Segments::ModulesBase
    ora #Segments::X_BYTE_ON                ; the bank as an X-byte
    sta ModulesXByte
    tay
    lda a:Segments::ModulesBase+1           ; SOS's page, $20-$9F, less $20
    sec
    sbc #Segments::WINDOW_PAGE
    jsr Memory::NormalizeAfterSubtract
    sta ModulesStart+1
    sty ModulesStartXByte
    sty ModulesEndXByte
    lda a:Segments::ModulesLimit
    ora #Segments::X_BYTE_ON
    tay
    lda a:Segments::ModulesLimit+1
    sec
    sbc #Segments::WINDOW_PAGE
    jsr Memory::NormalizeAfterSubtract
    cpy ModulesStartXByte
    beq *+5
    clc
    adc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST ; in the next bank: count it from the base's
    sta ModulesEnd+1
    lda #0
    sta ModulesEnd
    sta ModulesStart
    jsr Modules::Load
    lda ModuleLoadPointer                   ; the whole pages left below the records
    cmp ModulesStart
    lda ModuleLoadPointer+1
    sbc ModulesStart+1
    and #Segments::PAGES_PER_BANK-1
    beq Reclaim
    sta a:Segments::ShrinkModulesPages      ; give them back from the segment's base
    lda ModulesStart+1
    clc
    adc a:Segments::ShrinkModulesPages
    sta ModulesStart+1
    lda #0
    sta a:Segments::ShrinkModulesPages+1
    lda ModuleLoadPointer
    sta ModulesStart
    brk
    .byte SOS_CHANGE_SEGMENT
    .word Segments::ShrinkModulesList

;; Takes back all the memory SOS gives, and ends the statement.
;; Also: INVEXP1 (BB13)
Reclaim:
    lda #0
    jmp Segments::Grow

;; Marks nothing invoked, then takes the memory back.
;; Also: INVEXP2 (BB13)
ReleaseAll:
    lda #0
    sta a:Segments::ModulesSegment
    beq Reclaim                             ; always
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; BASIC's own segment
; ---------------------------------------------------------------------------------------------------------------------

;; The memory segments BASIC asks SOS for: its own, for the program and its data, which <Segments::Shrink> and
;; <Segments::Grow> change in size, and the invoked modules', and the parameter lists of those calls.
.scope Segments

;; The first page of the bank-switched window, $2000-$9FFF, through which SOS gives a segment's pages; BASIC's own
;; page numbers count from it.
WINDOW_PAGE = $20

;; The pages in a bank.
PAGES_PER_BANK = $80

;; The bit of an X-byte that turns extended addressing on, set over the bank's number.
X_BYTE_ON = $80

;; Finds the largest free segment for BASIC's program and data, anywhere in memory, and sets <SegmentStart> and
;; <MemoryTop> from it.
;;
;; The first FIND_SEG asks for $FFFF pages, which fails, and SOS leaves the most it can give in the count; the second
;; asks for that. The call is made until it works.
;; Out: SegmentStart = the segment's start plus 1, MemoryTop = the page after its end
;; See: <Segments::FindBasicList>, <ColdStart>
;; Also: TRYSEG (BB13)
.proc FindForBasic
    brk
    .byte SOS_FIND_SEGMENT
    .word FindBasicList
    bne FindForBasic
    lda a:FoundBasicSegment
    sta a:ShrinkBasicSegment
    sta a:GrowBasicSegment                  ; for Shrink and Grow
    ldy #0
    sty MemoryTop
    iny
    sty SegmentStart
    lda a:BasicBase
    ora #X_BYTE_ON
    tay
    lda a:BasicBase+1
    sec
    sbc #WINDOW_PAGE
    jsr Memory::NormalizePage               ; into BASIC's range, $02-$81
    sta SegmentStart+1
    sty SegmentStartXByte
    lda a:BasicLimit
    ora #X_BYTE_ON
    tay
    lda a:BasicLimit+1
    sec
    sbc #WINDOW_PAGE-1                      ; the page after the limit
    jsr Memory::NormalizePage
    sta MemoryTop+1
    sty MemoryTopXByte
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The SOS memory calls' parameter lists
; ---------------------------------------------------------------------------------------------------------------------

;; The parameter list of SOS's RELEASE_SEG call.
.struct ReleaseParameters
    COUNT .byte                             ;; the parameters' count, <RELEASE_COUNT>
    SEGMENT .byte                           ;; the segment's number
.endstruct

;; The parameter list of SOS's FIND_SEG call.
.struct FindParameters
    COUNT .byte                             ;; the parameters' count, <FIND_COUNT>
    MODE .byte                              ;; the search mode, a FIND_MODE_ value
    ID .byte                                ;; the segment's ID, which marks whose it is
    PAGES .word                             ;; the pages asked for; on a failure, the most SOS could give
    BASE .res 2                             ;; the segment's base, from SOS: its bank, then its page
    LIMIT .res 2                            ;; the segment's limit, its last page: its bank, then its page
    SEGMENT .byte                           ;; the segment's number, from SOS
.endstruct

;; The parameter list of SOS's CHANGE_SEG call.
.struct ChangeParameters
    COUNT .byte                             ;; the parameters' count, <CHANGE_COUNT>
    SEGMENT .byte                           ;; the segment's number
    MODE .byte                              ;; which end moves, and which way, a CHANGE_ value
    PAGES .word                             ;; the pages it moves by; on a failure, the most SOS could give
.endstruct

;; The parameter list of SOS's REQUEST_SEG call.
.struct RequestParameters
    COUNT .byte                             ;; the parameters' count, <REQUEST_COUNT>
    BASE .res 2                             ;; the segment's base: its bank, then its page
    LIMIT .res 2                            ;; the segment's limit: its bank, then its page
    ID .byte                                ;; the segment's ID
    SEGMENT .byte                           ;; the segment's number, from SOS
.endstruct

;; RELEASE_SEG's count of parameters.
RELEASE_COUNT = 1

;; FIND_SEG's count of parameters.
FIND_COUNT = 6

;; CHANGE_SEG's count of parameters.
CHANGE_COUNT = 3

;; REQUEST_SEG's count of parameters.
REQUEST_COUNT = 4

;; FIND_SEG's search mode that keeps the segment within one bank.
FIND_MODE_ONE_BANK = 0

;; FIND_SEG's search mode that lets the segment cross banks.
FIND_MODE_ANY = 2

;; CHANGE_SEG's mode that moves the base up, giving pages back from the bottom.
CHANGE_BASE_UP = 0

;; CHANGE_SEG's mode that moves the limit up, adding pages at the top.
CHANGE_LIMIT_UP = 2

;; CHANGE_SEG's mode that moves the limit down, giving pages back from the top.
CHANGE_LIMIT_DOWN = 3

;; The segment ID of BASIC's program and data.
ID_BASIC = $11

;; The segment ID of the invoked modules.
ID_MODULES = $12

;; The segment ID of the reserved pages $2000-$21FF of bank 0.
ID_RESERVED = $13

;; RELEASE_SEG's parameter list for the invoked modules' segment.
;; See: <Statements::Invoke>
;; Also: SEGTAB1 (BB13)
ReleaseModulesList:
    .byte RELEASE_COUNT

;; The invoked modules' segment number, 0 when nothing is invoked.
;; Also: SEGNUMB (BB13)
ModulesSegment:
    .byte 0

;; FIND_SEG's parameter list for the invoked modules: within one bank, the modules' ID and <Segments::ModulesPages>
;; pages; SOS returns the base, the limit and the segment number.
;; Also: SEGTAB2 (BB13)
FindModulesList:
    .byte FIND_COUNT
    .byte FIND_MODE_ONE_BANK
    .byte ID_MODULES

;; The pages the invoked modules need.
;; Also: PGCNT2 (BB13)
ModulesPages:
    .word 1

;; The modules' segment's base: its bank, then its page.
;; Also: BASPTR (BB13)
ModulesBase:
    .word 0

;; The modules' segment's limit: its bank, then its page.
;; Also: LIMPTR (BB13)
ModulesLimit:
    .word 0

;; The modules' segment number, from FIND_SEG.
;; Also: SEGNUM2 (BB13)
FoundModulesSegment:
    .byte 0

;; CHANGE_SEG's parameter list that gives the modules' unused pages back from the segment's base.
;; Also: SEGTAB3 (BB13)
ShrinkModulesList:
    .byte CHANGE_COUNT

;; The modules' segment number, for <Segments::ShrinkModulesList>.
;; Also: SEGNUM3 (BB13)
ShrinkModulesSegment:
    .byte 0
    .byte CHANGE_BASE_UP

;; The pages <Segments::ShrinkModulesList> gives back.
;; Also: PGECNT (BB13)
ShrinkModulesPages:
    .word 0

;; REQUEST_SEG's parameter list that reserves bank 0's $2000-$21FF, which BASIC's bank-switched pointers can't
;; reach.
;; See: <ColdStart>
;; Also: SEGTAB4 (BB13)
ReserveList:
    .byte REQUEST_COUNT
    .byte 0                                 ; the base: bank 0, page $20
    .byte WINDOW_PAGE
    .byte 0                                 ; the limit: bank 0, page $21
    .byte WINDOW_PAGE+1
    .byte ID_RESERVED

;; The reserved segment's number.
;; Also: SEGNUM4 (BB13)
ReservedSegment:
    .byte 0

;; CHANGE_SEG's parameter list that gives pages back from the top of BASIC's segment, for <Segments::Shrink>.
;; Also: SEGTAB5 (BB13)
ShrinkBasicList:
    .byte CHANGE_COUNT

;; BASIC's segment number, set by <Segments::FindForBasic>.
;; Also: SEGNUM5 (BB13)
ShrinkBasicSegment:
    .byte ID_BASIC
    .byte CHANGE_LIMIT_DOWN

;; The pages <Segments::Shrink> gives back.
;; Also: SEGSIZ5 (BB13)
ShrinkBasicPages:
    .word 0

;; CHANGE_SEG's parameter list that adds pages to the top of BASIC's segment, for <Segments::Grow>.
;; Also: SEGTAB6 (BB13)
GrowBasicList:
    .byte CHANGE_COUNT

;; BASIC's segment number, set by <Segments::FindForBasic>.
;; Also: SEGNUM6 (BB13)
GrowBasicSegment:
    .byte ID_BASIC
    .byte CHANGE_LIMIT_UP

;; The pages <Segments::Grow> asks for; when SOS can't give them, it leaves the most it can here.
;; Also: SEGSIZ6 (BB13)
GrowBasicPages:
    .word 0

;; FIND_SEG's parameter list for BASIC's program and data: across banks, BASIC's ID and $FFFF pages, which fails and
;; leaves the largest count SOS can give.
;; See: <Segments::FindForBasic>
;; Also: SEGTAB7 (BB13)
FindBasicList:
    .byte FIND_COUNT
    .byte FIND_MODE_ANY
    .byte ID_BASIC
    .byte $FF                               ; all the pages there are
    .byte $FF

;; BASIC's segment's base: its bank, then its page.
;; Also: BASBNK (BB13)
BasicBase:
    .word 0

;; BASIC's segment's limit: its bank, then its page.
;; Also: LIMBNK (BB13)
BasicLimit:
    .word 0

;; BASIC's segment number, from FIND_SEG.
;; Also: SEGNUM7 (BB13)
FoundBasicSegment:
    .byte 0

.assert ModulesSegment - ReleaseModulesList = ReleaseParameters::SEGMENT, "ModulesSegment is RELEASE_SEG's segment."
.assert ModulesPages - FindModulesList = FindParameters::PAGES, "ModulesPages is FIND_SEG's pages."
.assert ModulesBase - FindModulesList = FindParameters::BASE, "ModulesBase is FIND_SEG's base."
.assert ModulesLimit - FindModulesList = FindParameters::LIMIT, "ModulesLimit is FIND_SEG's limit."
.assert FoundModulesSegment - FindModulesList = FindParameters::SEGMENT, "FoundModulesSegment is FIND_SEG's segment."
.assert ShrinkModulesList - FindModulesList = .sizeof(FindParameters), "FIND_SEG's list is 10 bytes."
.assert ShrinkModulesSegment - ShrinkModulesList = ChangeParameters::SEGMENT, "The modules' CHANGE_SEG segment."
.assert ShrinkModulesPages - ShrinkModulesList = ChangeParameters::PAGES, "ShrinkModulesPages is CHANGE_SEG's pages."
.assert ReservedSegment - ReserveList = RequestParameters::SEGMENT, "ReservedSegment is REQUEST_SEG's segment."
.assert ShrinkBasicSegment - ShrinkBasicList = ChangeParameters::SEGMENT, "ShrinkBasicSegment is CHANGE_SEG's segment."
.assert ShrinkBasicPages - ShrinkBasicList = ChangeParameters::PAGES, "ShrinkBasicPages is CHANGE_SEG's pages."
.assert GrowBasicSegment - GrowBasicList = ChangeParameters::SEGMENT, "GrowBasicSegment is CHANGE_SEG's segment."
.assert GrowBasicPages - GrowBasicList = ChangeParameters::PAGES, "GrowBasicPages is CHANGE_SEG's pages."
.assert BasicBase - FindBasicList = FindParameters::BASE, "BasicBase is FIND_SEG's base."
.assert BasicLimit - FindBasicList = FindParameters::LIMIT, "BasicLimit is FIND_SEG's limit."
.assert FoundBasicSegment - FindBasicList = FindParameters::SEGMENT, "FoundBasicSegment is FIND_SEG's segment."

.endscope

; Functions: the parameter lists of PREFIX$'s and the clock's calls.
.scope Functions continued

;; The parameter list of SOS's GET_PREFIX call.
.struct GetPrefixParameters
    COUNT .byte                             ;; the parameters' count, 2
    PATHNAME .addr                          ;; where SOS puts the prefix: its length, then its characters
    LENGTH .byte                            ;; the room there
.endstruct

;; The parameter list of SOS's GET_TIME call.
.struct GetTimeParameters
    COUNT .byte                             ;; the parameters' count, 1
    TIME .addr                              ;; where SOS puts the date and time, 18 characters
.endstruct

;; GET_PREFIX's parameter list, into <CatalogBuffer>+1, for `PREFIX$` and 1.3's prefix handling.
;; See: <Functions::Prefix>
;; Also: PREFTAB (BB13)
PrefixList:
    .byte 2
    .word CatalogBuffer+1
    .byte <(InputBuffer-CatalogBuffer-4)

;; GET_TIME's parameter list, into <CatalogBuffer>+2, for `DATE$` and `TIME$`.
;; See: <Functions::Date>, <Functions::Time>
;; Also: DATETAB (BB13)
TimeList:
    .byte 1
    .word CatalogBuffer+2

.assert TimeList - PrefixList = .sizeof(GetPrefixParameters), "PrefixList is GET_PREFIX's list."

.endscope

; Statements: the parameter lists of PREFIX$ = and CATALOG.
.scope Statements continued

;; The parameter list of SOS's SET_PREFIX call.
.struct SetPrefixParameters
    COUNT .byte                             ;; the parameters' count, 1
    PATHNAME .addr                          ;; the new prefix: its length, then its characters
.endstruct

;; SET_PREFIX's parameter list, from the pathname in <NameBuffer>, for `PREFIX$ =`.
;; See: <Statements::Prefix>
;; Also: PREFTB2 (BB13)
SetPrefixList:
    .byte 1
    .word NameBuffer

;; GET_PREFIX's parameter list, into <NameBuffer>, up to 128 bytes, for `CATALOG`.
;; See: <Catalog>
;; Also: PREFTB3 (BB13)
CatalogPrefixList:
    .byte 2
    .word NameBuffer
    .byte 128

.assert CatalogPrefixList - SetPrefixList = .sizeof(SetPrefixParameters), "SetPrefixList is SET_PREFIX's list."

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Giving memory back to SOS and taking it again
; ---------------------------------------------------------------------------------------------------------------------

; Segments: shrinking and growing BASIC's segment.
.scope Segments continued

;; Gives free memory back to SOS: moves the strings and buffers, from <StringsBottom> to <MemoryTop>, down by A pages,
;; or by all the free space when A is 0, and shrinks BASIC's segment by as much.
;;
;; The strings' garbage is collected first, so the free space runs from <VariablesEnd> to <StringsBottom>.
;; <MoveDistance> is zero, so the move adjusts no pointers. With no free page it is an out-of-memory error, and a
;; CHANGE_SEG that fails ends the statement with SOS's error.
;; In: A = the pages, 0 for all the free space; more than there are gives all of it
;; Errors: <ERROR_OUT_OF_MEMORY> = no free page; SOS's error from CHANGE_SEG
;; See: <Segments::Grow>, <Segments::ShrinkBasicList>
;; Also: SCRUNCH (BB13)
.proc Shrink
    pha
    jsr Strings::CollectGarbage
    pla
    tax
    lda StringsBottom                       ; the free space, in pages and banks
    cmp VariablesEnd
    lda StringsBottom+1
    sbc VariablesEnd+1
    sta Pointer2
    lda StringsBottomXByte
    sbc VariablesEndXByte
    sta Pointer2+1
    asl Pointer2                            ; banks are 128 pages: make it a count of pages
    lsr Pointer2+1
    ror Pointer2
    txa
    beq Move                                ; all of it
    ldx Pointer2+1
    bne Fewer                               ; 256 pages or more: A is fewer
    cmp Pointer2
    bcs Move                                ; A is more: all of it

;; Takes A pages.
;; Also: SCRUN0 (BB13)
Fewer:
    sta Pointer2
    lda #0
    sta Pointer2+1

;; Moves the strings and buffers down by <Pointer2> pages and gives the pages to SOS.
;; Also: SCRUN1 (BB13)
Move:
    lda Pointer2
    ora Pointer2+1
    bne *+5
    jmp ReportOutOfMemory                   ; no free page
    lda Pointer2
    asl                                     ; StringInformationPointer = the count as pages and banks
    tax
    lda Pointer2+1
    rol
    sta StringInformationPointer+1
    txa
    lsr
    sta StringInformationPointer
    lda StringsBottom
    sta Pointer1
    sta SourceStart
    lda StringsBottom+1
    sta Pointer1+1
    ldy StringsBottomXByte
    sty Pointer1XByte
    sec
    sbc StringInformationPointer
    jsr Memory::NormalizeAfterSubtract
    sta SourceStart+1                       ; SourceStart = where the strings go
    tya
    sbc StringInformationPointer+1
    sta SourceStartXByte
    lda VariablesEnd
    pha
    lda VariablesEnd+1
    pha
    lda VariablesEndXByte
    pha
    lda MemoryTop                           ; CloseGap moves up to VariablesEnd: here, MemoryTop
    sta VariablesEnd
    lda MemoryTop+1
    sta VariablesEnd+1
    lda MemoryTopXByte
    sta VariablesEndXByte
    lda #0
    sta MoveDistance
    sta MoveDistance+1
    sta MoveDistanceXByte
    jsr CloseGap
    pla
    sta VariablesEndXByte
    pla
    sta VariablesEnd+1
    pla
    sta VariablesEnd
    lda SourceStart
    sta StringsBottom
    lda SourceStart+1
    sta StringsBottom+1
    lda SourceStartXByte
    sta StringsBottomXByte
    lda MemoryTop+1
    ldy MemoryTopXByte
    sec
    sbc StringInformationPointer
    jsr Memory::NormalizeAfterSubtract
    sta MemoryTop+1
    tya
    sbc StringInformationPointer+1
    sta MemoryTopXByte
    lda Pointer2
    sta ShrinkBasicPages
    lda Pointer2+1
    sta ShrinkBasicPages+1
    brk
    .byte SOS_CHANGE_SEGMENT
    .word ShrinkBasicList
    beq *+5
    jmp ReportSosError
    rts
.endproc

;; Takes memory back from SOS: grows BASIC's segment by A pages, or by as many as SOS gives when A is 0, and moves the
;; strings and buffers up to the new top.
;;
;; When SOS can't give the pages asked for, the call is made again for the count SOS leaves in
;; <Segments::GrowBasicPages>, until it works, so fewer pages than A may be taken. When SOS gives none, it is an
;; out-of-memory error if A was not 0.
;; In: A = the pages, 0 for as many as SOS gives
;; Errors: <ERROR_OUT_OF_MEMORY> = no page given, when A was not 0
;; See: <Segments::Shrink>, <Segments::GrowBasicList>
;; Also: EXPAND (BB13)
.proc Grow
    ldy #0
    tax
    bne SetCount
    ldy #>GROW_ALL                          ; A is 0: ask for $FFF pages
    lda #<GROW_ALL

;; Asks for A pages, Y above 256.
;; Also: EXPAN0 (BB13)
SetCount:
    sta GrowBasicPages
    sty GrowBasicPages+1

;; Grows BASIC's segment by <GrowBasicPages> pages, trying again with SOS's count until it works.
;; Also: EXPAN1 (BB13)
Ask:
    brk
    .byte SOS_CHANGE_SEGMENT
    .word GrowBasicList
    bne Ask
    lda GrowBasicPages
    ora GrowBasicPages+1
    bne MoveUp
    tya                                     ; none: Y is nonzero when A was 0
    bne *+5
    jmp ReportOutOfMemory
    rts

;; Moves the strings and buffers up by the pages SOS gave, to the new <MemoryTop>.
;; Also: EXPAN2 (BB13)
MoveUp:
    lda MemoryTop
    sta SourceEnd
    sta DestinationEnd
    clc
    lda MemoryTop+1
    sta SourceEnd+1
    ldy MemoryTopXByte
    sty SourceEndXByte
    adc GrowBasicPages
    jsr Memory::NormalizeAfterAdd
    sta MemoryTop+1
    sta DestinationEnd+1
    tya
    adc GrowBasicPages+1
    adc GrowBasicPages+1                    ; twice: each 256 pages is two banks
    sta MemoryTopXByte
    sta DestinationEndXByte
    lda StringsBottom
    sta SourceStart
    lda StringsBottom+1
    sta SourceStart+1
    lda StringsBottomXByte
    sta SourceStartXByte
    jsr MoveRangeUp::Unchecked
    lda DestinationEnd
    sta StringsBottom
    lda DestinationEnd+1
    sta StringsBottom+1
    lda DestinationEndXByte
    sta StringsBottomXByte
    rts
.endproc

;; The pages <Segments::Grow> asks for when it is to take all SOS gives: more than there are.
GROW_ALL = $0FFF

.endscope
