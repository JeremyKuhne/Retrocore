; retrocore: style=strict
;; DOS 3.3 and 3.2 command interpreter: the file buffers' layout, building their chain, and connecting DOS's hooks
;;
;; <FileBuffers::Build> sets up the file buffers, as many as MAXFILES asks for (3 at boot), in a chain going down in
;; memory from just below DOS, and lowers BASIC's HIMEM to below the last. Each open file uses one buffer.
;; <Commands::MaxFiles> and DOS's start (<FinishStart>) call it, and <FileBuffers::Find>, <FileBuffers::First> and
;; <FileBuffers::Next> (DosGoer.asm) walk the chain. The file also holds <ConnectDos>, which hooks DOS into the
;; Monitor's input and output (DosHook.asm). Runs at $A7D4-$A883 where DOS runs (in both versions).
;;
;; Each buffer is 595 bytes. From the top down:
;;
;; - a header, laid out as <FileBuffer>, which is the address the chain links: the name of the file open in the
;;   buffer, its first byte 0 while the buffer is free; then the addresses of the parts below and of the next
;;   buffer's header ($0000 in the last). <FileBuffers::CopyPointers> copies the addresses into the file manager's
;;   parameter list.
;; - <FILE_CONTROL_SIZE> bytes of work area, where the file manager keeps the open file's state, its copy of the
;;   file control block (<FileManager::FileControlBlock>).
;; - a 256-byte buffer for the file's track/sector list sector.
;; - a 256-byte buffer for its data sector.
;;
;; Where DOS runs at $9D00, the first header is at $9CD3 (<FileBuffersAddress>) and three buffers end at $9600, BASIC's
;; HIMEM. docs/Dos.md explains track/sector lists and the file control block.

; The file buffers' layout.

;; The layout of a DOS file buffer's header (38 bytes), at the top of each buffer: the file open in the buffer, and
;; the addresses of the buffer's other parts.
;;
;; <WorkPointer> points at the header of the buffer being worked on. Apple's listing has no names for its fields,
;; only offsets.
.struct FileBuffer
    ;; The name of the file open in the buffer, 30 characters with bit 7 set, padded with spaces; a first byte of 0
    ;; marks the buffer free. The length is <CATALOG_NAME_LENGTH>, which FileManagerData.asm defines after this file,
    ;; so an assert checks it.
    NAME .res 30
    WORK_AREA .addr                 ;; The address of the buffer's work area, just below the header.
    LIST_BUFFER .addr               ;; The address of its track/sector list buffer.
    DATA_BUFFER .addr               ;; The address of its data sector buffer.
    NEXT .addr                      ;; The address of the next buffer's header, $0000 in the last.
.endstruct

.assert FileBuffer::WORK_AREA = CATALOG_NAME_LENGTH, "A file buffer's name is a catalog entry's name."

;; The size of a file buffer's header, 38 bytes: the distance from a data sector buffer down to the next buffer's
;; header.
FILE_BUFFER_HEADER_SIZE = .sizeof(FileBuffer)

; FileBuffers: building the chain of buffers, at $A7D4.
.scope FileBuffers continued

;; Builds the chain of <FileBufferCount> file buffers below DOS, all free, and sets BASIC's HIMEM below the last.
;;
;; At $A7D4 where DOS runs. Any file open in a buffer is forgotten, which is why <Commands::MaxFiles> closes all
;; files first.
;; In:    FileBufferCount = the number of buffers, 1-16, ActiveBasic = 0 if Integer BASIC is active, else Applesoft
;; Out:   WorkPointer = the last buffer's header, IBHMEM/IBSOP = its data sector buffer under Integer BASIC (HIMEM
;;   and the program's start), ASHM1/ASHM2 = the same under Applesoft (HIMEM and the bottom of the strings)
;; Uses:  A, X, Y, InterpreterScratch
;; Also: BLDFTB (DOS33, DOS31)
.proc Build
.assert MASTER || * = $A7D4, "FileBuffers::Build is at $A7D4 where DOS runs."

    ; The first header, and the number of buffers still to build.
    sec
    lda FileBuffersAddress
    sta WorkPointer
    lda FileBuffersAddress+1
    sta WorkPointer+1
    lda a:FileBufferCount
    sta a:InterpreterScratch

;; Marks the buffer free, by a first name byte of 0, and stores its three addresses.
;; Also: BFT1 (DOS33, DOS31)
NextBuffer:
    ldy #FileBuffer::NAME
    tya
    sta (WorkPointer),y

    ; The low byte is the same in all three addresses: each part is 256 bytes below the last, after the work area,
    ; so the high byte drops by one each time. First the work area, the header less FILE_CONTROL_SIZE.
    ldy #FileBuffer::WORK_AREA
    sec
    lda WorkPointer
    sbc #FILE_CONTROL_SIZE
    sta (WorkPointer),y
    pha
    lda WorkPointer+1
    sbc #0
    iny
    sta (WorkPointer),y

    ; The track/sector list buffer, 256 below the work area.
    tax
    dex
    pla
    pha
    iny
    sta (WorkPointer),y
    txa
    iny
    sta (WorkPointer),y

    ; The data buffer, 256 below that.
    tax
    dex
    pla
    pha
    iny
    sta (WorkPointer),y
    iny
    txa
    sta (WorkPointer),y
    dec a:InterpreterScratch
    beq Last

    ; The next header is FILE_BUFFER_HEADER_SIZE below the data buffer: link to it and go on there.
    tax
    pla
    sec
    sbc #FILE_BUFFER_HEADER_SIZE
    iny
    sta (WorkPointer),y
    pha
    txa
    sbc #0
    iny
    sta (WorkPointer),y
    sta WorkPointer+1
    pla
    sta WorkPointer
    jmp NextBuffer

;; The last buffer: its link is $0000, and its data buffer, whose address is on the stack (the high byte on top),
;; becomes BASIC's HIMEM.
;; Also: BFT2 (DOS33, DOS31)
Last:
    pha
    lda #0
    iny
    sta (WorkPointer),y
    iny
    sta (WorkPointer),y
    lda a:ActiveBasic
    beq Integer

    ; Applesoft's HIMEM, and the bottom of its string space, which grows down from HIMEM.
    pla
    sta ASHM1+1
    sta ASHM2+1
    pla
    sta ASHM1
    sta ASHM2
    rts

;; Integer BASIC's HIMEM, and its program's start, which grows down from HIMEM: no program.
;; Also: BFTIB (DOS33, DOS31)
Integer:
    pla
    sta IBHMEM+1
    sta IBSOP+1
    pla
    sta IBHMEM
    sta IBSOP
    rts
.endproc

.endscope

;; Hooks DOS into the Monitor's input and output: puts DOS's input handler (<InputHandlerAddress>) in <InputHook> and
;; its output handler (<OutputHandlerAddress>) in <OutputHook>, first saving what is there in <SavedInputHook> and
;; <SavedOutputHook> as the real input and output routines.
;;
;; At $A851 where DOS runs; programs reach it through the page-3 vector at $03EA, to reconnect DOS after changing the
;; hooks. DOS calls it each time it gives control back, since BASIC, PR# and IN# replace the hooks. A hook already
;; pointing into DOS's handler's page is left alone: only the high bytes are compared.
;; Uses:  A
;; Keeps: X, Y
;; Entry: Output = the output hook only
;; Also: MVCSW (DOS33, DOS31)
.proc ConnectDos
.assert MASTER || * = $A851, "ConnectDos is at $A851 where DOS runs."
    lda InputHook+1
    cmp InputHandlerAddress+1
    beq Output
    sta a:SavedInputHook+1
    lda InputHook
    sta a:SavedInputHook
    lda InputHandlerAddress
    sta InputHook
    lda InputHandlerAddress+1
    sta InputHook+1

;; The output hook, the same way.
;; Also: MVOSW (DOS33, DOS31)
Output:
.assert MASTER || * = $A86A, "ConnectDos::Output is at $A86A where DOS runs."
    lda OutputHook+1
    cmp OutputHandlerAddress+1
    beq Done
    sta a:SavedOutputHook+1
    lda OutputHook
    sta a:SavedOutputHook
    lda OutputHandlerAddress
    sta OutputHook
    lda OutputHandlerAddress+1
    sta OutputHook+1

;; Also: MVSRTN (DOS33, DOS31)
Done:
    rts
.endproc
