; retrocore: style=strict
;; DOS 3.3 and 3.2: the master's relocator, which moves DOS to the top of memory
;;
;; Only a System Master has this: the MASTER = 1 build puts it at $1B00-$1CFF, with DOS after it at $1D00-$3FFF,
;; $8000 below where DOS runs on a 48K machine. `BOOT 2` loads all of that and jumps to <RelocateDos> here. The
;; relocator finds how much memory the machine has, adjusts every address inside DOS for the place DOS will run,
;; the top of memory, and copies DOS there, so one master boots whatever the memory size. Disks that INIT writes
;; don't need it: they get the copy of DOS already running, which loads straight to its place. Apple's listing
;; calls this module RELOCTR.
;;
;; The boot chain, with the master's addresses (docs/Dos.md tells it in full):
;;
;; - `BOOT 0`, the Disk II ROM, reads track 0 sector 0 to $0800 and runs it (docs/DiskII.md, Boot16.asm). DOS 3.2's
;;   ROM reads it to $0300 (Boot13.asm).
;; - `BOOT 1`, that sector (the first page of BootLoader.asm), reads track 0's first ten sectors, itself again
;;   among them, to $3600-$3FFF and jumps to $3700, in both versions.
;; - `BOOT 2` reads the rest of DOS, $1B00-$35FF, from tracks 0 to 2 and ends at <RelocateDos>.
;; - This code moves DOS up and starts it at <ColdStart>.
;;
;; DOS needs two kinds of fixing. Tables of addresses are listed in <Relocator::AddressRanges>; ranges of code,
;; whose three-byte instructions may hold addresses, are listed in <Relocator::CodeRanges>. Only addresses inside
;; DOS change. The relocator is not itself moved, so its own addresses are those of the master image. The ranges'
;; edges are labels named for what each range holds, ending in Start for its first byte and End for the byte after
;; it, or Last for its last byte where Apple's listing marks that instead:
;;
;; - <InterpreterAddressesStart> to <InterpreterAddressesEnd> (DosInit.asm): DOS's table of its own addresses.
;; - <FileManagerAddressesStart> to <FileManagerAddressesEnd> (FileManagerEntry.asm): the file manager's.
;; - <InterpreterCodeStart> to <InterpreterCodeEnd>: the command interpreter's code, from DosInit.asm to
;;   CommandTables.asm.
;; - <FileManagerCodeStart> to <FileManagerCodeEnd>: the file manager's code.
;; - <BootCodeStart> to <BootCodeEnd>: `BOOT 2` and the patches in the boot loader's pages.
;; - `EmptyCodeStart` to `EmptyCodeEnd`: DOS 3.2's empty range before its boot page.
;; - <WriteAddressCodeStart> to <WriteAddressCodeEnd> (DOS 3.3): the formatter's address field writer.
;; - <LowLevelCodeStart> to `LowLevelCodeEnd`: RWTS's nibble, read, write and seek routines.
;; - `RwtsPatchCodeStart` to `RwtsPatchCodeEnd` (the 1983 DOS 3.3): the patches after <DiskII::Wait>.
;; - <RwtsCodeStart> to `RwtsCodeEnd` in DOS 3.3: RWTS itself and the formatter. In DOS 3.2 the range runs to
;;   `RwtsCodeLast`, the last byte of DOS, since its patches at the top of DOS come right after the formatter.
;; - `TopPatchCodeStart` to `TopPatchCodeLast` (DOS 3.3): the patches at the top of DOS (DosPatches.asm).

; The tables' layout.

;; One entry of the relocator's tables: a range of memory, from its first byte up to the byte after its last.
.struct RelocationRange
    START .word ;; the range's first byte
    END .word ;; the byte after the range, where the relocator stops
.endstruct

;; One entry of <Relocator::AddressRanges> or <Relocator::CodeRanges>.
;; Parameters: first = the range's first byte, after = the byte after its last, where the relocator stops
.macro Range first, after
    .word first, after
.endmacro

;; The first bytes of the master image: a jump to DOS's cold start where the image holds it.
;;
;; At $1B00, the start of the master image (<MASTER_ORIGIN>). `BOOT 2` reads DOS to here, and <RelocateDos> jumps
;; here to start DOS where it is when there is nowhere higher to move it. DOS's <WriteStartAddress>, where INIT
;; writes from, names this address until the relocator changes it.
;; Also: BEGIN (DOS33, DOS31)
.proc ImageStart
    jmp ColdStart
.endproc

;; Moves DOS to the top of memory, adjusting its addresses, and starts it there. `BOOT 2` jumps here through
;; <Boot::StartDos::ToDos>.
;;
;; At $1B03. First it finds the highest page of RAM: from $BF00 down, it tests each page's first byte by
;; exclusive-oring it with 0 to 255 in turn, comparing each result with what the same arithmetic gives on a copy
;; of the byte. Memory passes all 256; the byte ends where it began, since the 256 values exclusive-ored together
;; give 0. Where nothing answers, or a ROM does, a comparison fails and the page below is tried.
;;
;; It doesn't return: it ends at DOS's cold start, <ColdStart>, in the moved copy.
;; Also: DOSREL (DOS33, DOS31), DR0 (DOS33, DOS31)
.proc RelocateDos
.assert * = ImageStart + 3, "RelocateDos follows ImageStart's JMP, at $1B03."
    .using Relocator

;; The relocator's copy of the byte under test while it looks for the top of RAM.
;;
;; It exclusive-ors the first byte of each page with each value from 0 to 255 in turn and does the same to
;; this copy; the page is RAM only if the two always agree. Apple's listing calls it LOC1, a name the Monitor
;; gives another byte.
TestCopy = LowResBase

;; Where the code-range pass keeps its place in <Relocator::CodeRanges> while <DecodeOpcode> uses X.
RangeIndex = FileManager::Scratch1

    ; From the page at $BF00 down. X stays 0, so (WorkPointer,x) is the byte WorkPointer points at.
    lda #$BF
    sta WorkPointer+1
    ldx #0
    stx WorkPointer

;; Also: DR0A (DOS33)
TestPage:
    ldy #0

;; Also: DR1B (DOS33, DOS31)
LoadTestByte:
    lda (WorkPointer,x)
    sta TestCopy

;; Also: DR1 (DOS33, DOS31)
TestValue:
    tya
    eor TestCopy
    sta TestCopy
    tya
    eor (WorkPointer,x)
    sta (WorkPointer,x)
    cmp TestCopy
    bne NotRam                      ; it didn't hold the value: not RAM
    iny
    bne TestValue
    beq CheckMirror                 ; always: all 256 passed, Y = 0

;; Also: DR1A (DOS33, DOS31)
NotRam:
    dec WorkPointer+1
    bne TestPage

; Some memory answers at two addresses 8K apart, so the page found may be the same RAM as the page 8K below it (bit
; 5 of the page number clear). The same test again, now writing below and reading at the page found: if every write
; shows up there, the two are one, and the top of memory is the lower page. Y is 0.

;; Also: DR2 (DOS33, DOS31)
CheckMirror:
    lda WorkPointer+1
    and #$DF
    sta FilePointer+1
    stx FilePointer
    lda (FilePointer,x)
    pha                             ; the lower page's byte, to put back
    sta TestCopy

;; Also: DR2A (DOS33)
MirrorValue:
    tya
    eor TestCopy
    sta TestCopy
    tya
    eor (WorkPointer,x)
    sta (FilePointer,x)
    cmp TestCopy
    bne Separate                    ; separate memory
    iny
    bne MirrorValue
    ldy FilePointer+1               ; one and the same: the byte is back as it was, by the same arithmetic
    pla
    jmp SetPages

;; Also: DR2B (DOS33)
Separate:
    pla
    sta (FilePointer,x)
    ldy WorkPointer+1

; Y is the top page of RAM. DOS ends just above it (NewEndPage), starts DosPages pages lower (NewFirstPage), and
; moves by PageOffset pages. With RAM to $3FFF PageOffset is 0: DOS is already in place and starts where it is.

;; Also: DR2C (DOS33)
SetPages:
    iny
    sty a:NewEndPage
    sec
    tya
    sbc a:DosPages
    sta a:NewFirstPage
    sec
    sbc a:FirstPage
    beq ImageStart
    sta a:PageOffset

    ; Two fixes before the general ones. WriteStartAddress, which INIT uses as the first page of DOS to write to a
    ; disk, names ImageStart, the relocator; it is pointed at DosStart instead. And DI3, the JMP at the end of BOOT
    ; 2, is pointed at ColdStart, so a disk INIT writes from the moved DOS boots straight into DOS. Both are in
    ; ranges the next two passes adjust.
    lda a:FirstPage
    sta a:WriteStartAddress+1
    lda #>ColdStart
    sta a:Boot::StartDos::ToDos+2
    lda #<ColdStart
    sta a:Boot::StartDos::ToDos+1

    ; Adjusts the address tables. Each AddressRanges entry is a range of two-byte addresses; PageOffset is added to
    ; each one's high byte. Y and WorkPointer + 1 are the pointer, WorkPointer staying 0. The entries start after
    ; the table's count byte.
    ldx #0
    stx WorkPointer

;; Also: DR3 (DOS33, DOS31)
NextAddressRange:
    lda a:AddressRanges+1+RelocationRange::START,x
    tay
    lda a:AddressRanges+1+RelocationRange::START+1,x
    sta WorkPointer+1
    jmp NextAddress                 ; step to the first address's high byte

;; Also: DR4 (DOS33, DOS31)
AdjustAddress:
    clc
    lda (WorkPointer),y
    adc a:PageOffset
    sta (WorkPointer),y
    iny
    bne NextAddress
    inc WorkPointer+1

;; Also: DR5 (DOS33, DOS31)
NextAddress:
    iny
    bne CheckRangeEnd
    inc WorkPointer+1

;; Also: DR6 (DOS33, DOS31)
CheckRangeEnd:
    lda WorkPointer+1
    cmp a:AddressRanges+1+RelocationRange::END+1,x
    bcc AdjustAddress
    tya
    cmp a:AddressRanges+1+RelocationRange::END,x
    bcc AdjustAddress
    txa
    clc
    adc #.sizeof(RelocationRange)
    tax
    cpx a:AddressRanges
    bcc NextAddressRange

    ; Adjusts the code. Each CodeRanges entry is a range of instructions, walked one at a time with the Monitor's
    ; DecodeOpcode, which gives each opcode's length. In a three-byte instruction whose operand's high byte is a
    ; page of DOS (FirstPage up to EndPage), PageOffset is added to it. The ranges must hold only code, or the
    ; walk falls out of step.
    ldx #0

;; Also: DR7 (DOS33, DOS31)
NextCodeRange:
    stx a:RangeIndex                ; DecodeOpcode changes X
    lda a:CodeRanges+1+RelocationRange::START,x
    sta WorkPointer
    lda a:CodeRanges+1+RelocationRange::START+1,x
    sta WorkPointer+1

;; Also: DR8 (DOS33, DOS31)
NextInstruction:
    ldx #0
    lda (WorkPointer,x)
    jsr DecodeOpcode
    ldy OperandLength
    cpy #2
    bne SkipInstruction             ; not three bytes long
    lda (WorkPointer),y
    cmp a:FirstPage
    bcc SkipInstruction
    cmp a:EndPage
    bcs SkipInstruction
    adc a:PageOffset                ; the carry is clear: the BCS wasn't taken
    sta (WorkPointer),y

;; Also: DR9 (DOS33, DOS31)
SkipInstruction:
    sec                             ; past the instruction: OperandLength + 1 bytes
    lda OperandLength
    adc WorkPointer
    sta WorkPointer
    lda #0
    adc WorkPointer+1
    sta WorkPointer+1
    ldx a:RangeIndex
    cmp a:CodeRanges+1+RelocationRange::END+1,x
    bcc NextInstruction
    lda WorkPointer
    cmp a:CodeRanges+1+RelocationRange::END,x
    bcc NextInstruction
    txa
    clc
    adc #.sizeof(RelocationRange)
    tax
    cpx a:CodeRanges
    bcc NextCodeRange

    ; Copies DOS, now fixed, to its new place, a page at a time from the top page down: PagesToCopy pages, from the
    ; page holding DOS's last byte to the page below NewEndPage. The new place is higher, so working down never
    ; overwrites a page before it is copied.
    lda #>(DosEnd-$80)
    sta WorkPointer+1
    ldy a:NewEndPage
    dey
    sty FilePointer+1
    lda #0
    sta WorkPointer
    sta FilePointer
    tay

;; Also: DR10 (DOS33, DOS31)
CopyByte:
    lda (WorkPointer),y
    sta (FilePointer),y
    iny
    bne CopyByte
    dec a:PagesToCopy
    beq StartDos
    dec WorkPointer+1
    dec FilePointer+1
    bne CopyByte

; Starts DOS. The second JMP of VectorImage, a JMP to ColdStart, is still in the old copy of DOS; its address was
; adjusted with the rest, so it goes to the cold start in the new copy.

;; Also: DR11 (DOS33, DOS31)
StartDos:
    jmp VectorImage+DosColdStartJump-DosWarmStartJump
.endproc

;; The master's relocator's tables and variables: the ranges of DOS it adjusts and the pages it moves DOS between.
;;
;; Only the System Master has them, at $1B00-$1CFF with <RelocateDos>, which uses them to move DOS to the top of
;; memory. <Relocator::AddressRanges> lists DOS's tables of addresses and <Relocator::CodeRanges> its code, each
;; range a <RelocationRange>.
.scope Relocator

;; The address tables to adjust: a count of bytes used, then <RelocationRange> entries, each a run of two-byte
;; addresses whose high bytes change.
;;
;; The BASIC vectors in DosInit.asm, between <InterpreterAddressesEnd> and <InterpreterCodeStart>, hold addresses
;; outside DOS too, so only the entries that point into DOS are listed. The table has room for three more.
;; Also: ADRTAB (DOS33, DOS31)
AddressRanges:
    .byte 9*.sizeof(RelocationRange)
    Range InterpreterAddressesStart, InterpreterAddressesEnd
    Range BasicRun, BasicRun+2
    Range IntegerVector+BasicRun-BasicVector, IntegerVector+BasicError-BasicVector
    Range RomAppleSoftVector, RomAppleSoftVector+BasicError-BasicVector
    Range RamAppleSoftVector, RamAppleSoftVector+BasicError-BasicVector
    Range RamAppleSoftVector+BasicColdStart-BasicVector, RamAppleSoftVector+BasicWarmStart-BasicVector
    Range FileManagerAddressesStart, FileManagerAddressesEnd                ; the file manager's tables
    Range Boot::IobAddress, Boot::Stage1Address+2           ; `BOOT 2`'s pointers to the IOB and the boot page
    Range DosIob::DeviceTable, DosIob::DeviceTable+2
    .res 3*.sizeof(RelocationRange), 0

;; The code ranges to adjust: a count of bytes used, then <RelocationRange> entries, each a run of instructions.
;;
;; DOS 3.2's RWTS is laid out differently, its patches inside its RWTS range: its table has six entries and room for
;; one more. The 1980 DOS 3.3 has no patch code after <DiskII::Wait>, only leftover bytes.
;; Also: CDETAB (DOS33, DOS31)
CodeRanges:
.if DOS32
    .byte 6*.sizeof(RelocationRange)
    Range InterpreterCodeStart, InterpreterCodeEnd
    Range FileManagerCodeStart, FileManagerCodeEnd                  ; the file manager
    Range BootCodeStart, BootCodeEnd                  ; `BOOT 2` and its helpers
    Range EmptyCodeStart, EmptyCodeEnd                  ; an empty range, just before the boot page
    Range LowLevelCodeStart, DiskII::Wait::LowLevelCodeEnd ; RWTS's low-level routines
    Range RwtsCodeStart, RwtsCodeLast        ; RWTS, the formatter and the patches at the top of DOS
    .res .sizeof(RelocationRange), 0
.else
.if REVISION_B
    .byte 8*.sizeof(RelocationRange)
.else
    .byte 7*.sizeof(RelocationRange)
.endif
    Range InterpreterCodeStart, InterpreterCodeEnd
    Range FileManagerCodeStart, FileManagerCodeEnd                  ; the file manager
    Range BootCodeStart, BootCodeEnd                  ; the patches and `BOOT 2` in the boot loader's pages
    Range WriteAddressCodeStart, WriteAddressCodeEnd            ; RWTS, in pieces between its tables
    Range LowLevelCodeStart, LowLevelCodeEnd
.if REVISION_B
    Range RwtsPatchCodeStart, RwtsPatchCodeEnd                ; the 1983 patch area after DiskII::Wait
.endif
    Range RwtsCodeStart, RwtsCodeEnd
    Range TopPatchCodeStart, TopPatchCodeLast
.endif

;; DOS's first page in the master image.
;; Also: RSPAGE (DOS33, DOS31)
FirstPage:
    .byte >DosStart

;; The page just after DOS in the master image.
;; Also: REPAGE (DOS33, DOS31)
EndPage:
    .byte >DosEnd

;; DOS's first page once moved.
;; Also: NSPAGE (DOS33, DOS31)
NewFirstPage:
    Leftover $00, $1D, $00

;; The page just after DOS once moved.
;; Also: NEPAGE (DOS33, DOS31)
NewEndPage:
    Leftover $00, $40, $00

;; DOS's length in pages.
;; Also: DOSLNG (DOS33, DOS31)
DosPages:
    .byte >(DosEnd-DosStart)

;; How many pages DOS moves up.
;; Also: DELTA (DOS33, DOS31)
PageOffset:
    .byte 0

;; Pages left to copy.
;; Also: DPGCNT (DOS33, DOS31)
PagesToCopy:
    .byte >(DosEnd-DosStart)
.if DOS32 = 0 && YEAR = 1983
    ; leftover: the rest of the page holds whatever was in memory when the master was written
    .byte $FC, $FD, $FD, $FD, $FC, $FD, $FC, $FC, $FC, $FE, $FE, $FC, $FE, $FC, $FC, $FD
    .byte $FE, $FC, $FF, $FC, $FD, $FC, $FC, $FC, $FF, $FC, $FF, $FC, $FE, $FF, $FF, $FF
    .byte $FF, $FD, $FE, $FC, $FD, $FC, $FC, $FC, $FC, $FD, $FC, $FE, $FE, $FE, $FC, $FD
    .byte $FF, $FC, $FC, $FC, $FE, $FC, $FD, $FC, $FC, $FC, $FE, $FC, $FD, $FC, $FC, $FC
    .byte $FD, $FC, $FD, $FD, $FC, $FC, $FC, $FD, $FD, $FC, $FE, $FC, $FC, $FE, $FC, $FC
    .byte $FD, $FD, $FC, $FF, $FE, $FC, $FF, $FC, $FC, $FD, $FC, $FD, $FE, $FC, $FC, $FD
    .byte $FC, $FF, $FC, $FE, $FF, $FF, $FF, $FD, $FC, $FE, $FE, $FC, $FC, $FE, $FC, $FC
    .byte $FE, $FC, $FE, $FC, $FE, $FE, $FC, $FE, $FE, $FC, $FC, $FE, $FC, $FD, $FD
.else
    ; leftover: the 1980 master's rest of the page, which the DOS 3.2 master has too
    .byte $A5, $74, $86, $6F, $85, $70, $A0, $00, $84, $8B, $A5, $6D, $A6, $6E, $85, $9B
    .byte $86, $9C, $A9, $55, $A2, $00, $85, $5E, $86, $5F, $C5, $52, $F0, $05, $20, $1A
    .byte $1D, $F0, $F7, $A9, $07, $85, $8F, $A5, $69, $A6, $6A, $85, $5E, $86, $5F, $E4
    .byte $6C, $D0, $04, $C5, $6B, $F0, $05, $20, $10, $1D, $F0, $F3, $85, $94, $86, $95
    .byte $A9, $03, $85, $8F, $A5, $94, $A6, $95, $E4, $6E, $D0, $07, $C5, $6D, $D0, $03
    .byte $4C, $59, $1D, $85, $5E, $86, $00, $A0, $00, $B1, $5E, $AA, $C8, $B1, $5E, $08
    .byte $C8, $B1, $5E, $65, $94, $85, $94, $C8, $B1, $5E, $65, $95, $85, $95, $28, $10
    .byte $D3, $8A, $30, $D0, $A6, $1C, $A6, $1B, $A6, $1A, $80, $1A, $65, $5E, $85, $5E
    .byte $90, $02, $E6
.endif
.assert <* = 0, "The relocator fills its two pages."

.endscope
