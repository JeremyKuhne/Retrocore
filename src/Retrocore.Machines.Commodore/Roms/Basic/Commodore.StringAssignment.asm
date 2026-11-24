; retrocore: style=strict
; COMMODORE BASIC 4: DISK-STATUS AND LINKED-STRING ASSIGNMENT
;
; BASIC 4's collector keeps a two-byte link after each string in string space. These macros extend the shared
; StringAssignment: StringStatusCheck and LinkedStringRelease expand inside its StoreString, LinkedStringStore after it,
; and StringLinkAdjust follows the assignment in the ROM.

.include "../../Microsoft6502Basic/MsBasic.Families.asm"

;; Emits <StoreString>'s check that copies a string whose characters are the disk status's (`DS$`), since that
;; buffer is rewritten by every disk command.
;;
;; The check compares the source's address with <DiskStatusDescriptor>'s, high byte, then (when `DS$` is not empty)
;; low byte; its length is not compared.
;; In: A = the source string's address (high byte), Y = 2, FacMantissa3 = the descriptor's address (low byte),
;;   FacMantissa4 = its high byte
;; Out: A = the address's high byte and Y = 2 when the ordinary assignment goes on
.macro StringStatusCheck
    cmp DiskStatusDescriptor+StringDescriptor::ADDRESS+1
    bne NotStatus
    pha
    dey
    lda DiskStatusDescriptor+StringDescriptor::LENGTH
    beq RestoreOffset
    lda (FacMantissa3),y
    cmp DiskStatusDescriptor+StringDescriptor::ADDRESS
    bne RestoreOffset
    pla
    jmp CopyCharacters

;; Not `DS$`'s characters: pulls the high byte back and restores Y = 2.
;; Also: NOTDS1 (UNKN), DSKX1 (HV4, HV4R)
RestoreOffset:
    pla
    iny

;; The ordinary assignment goes on.
;; Also: NOTDS (UNKN), DSKX2 (HV4, HV4R)
NotStatus:
.endmacro

;; Emits the end of <StoreString>'s copy for the linked collector: releases the source string's temporary and points
;; at <NewDescriptor>, falling into BASIC 4's <StoreLinkedDescriptor>.
;; In: StringPointer = the source descriptor, NewDescriptor = the copy's descriptor
.macro LinkedStringRelease
    lda StringPointer
    ldy StringPointer+1
    jsr Strings::ReleaseTemporary
    lda #<NewDescriptor
    ldy #>NewDescriptor
.endmacro

;; Emits BASIC 4's descriptor copy, <StoreLinkedDescriptor>, which also keeps the strings' links.
.macro LinkedStringStore

    ;; Releases the descriptor at Y:A if it is the latest temporary, links its string to the variable, marks the
    ;; variable's old string as garbage, and copies the descriptor to the variable: BASIC 4's <StoreDescriptor>, which
    ;; Commodore.HistoricalNames.asm gives BASIC 4's name (Basic.md E6).
    ;;
    ;; A live string's link holds its variable's address. Garbage's link holds $FF in its high byte and the string's
    ;; length in its low byte, so the collector can step over it.
    ;; In: A = the descriptor's address (low byte), Y = its high byte, AssignedVariable = the destination variable
    ;; Also: COPYZC (M6502)
    .proc StoreLinkedDescriptor
    sta DescriptorPointer
    sty DescriptorPointer+1
    sta Pointer1
    sty Pointer1+1
    jsr Strings::ReleaseTemporary
    jsr FindStringLink
    bcc ReleaseOld
    ldy #$00
    lda AssignedVariable
    sta (Pointer1),y
    iny
    lda AssignedVariable+1
    sta (Pointer1),y

;; Marks the variable's old string, if it has a link, as garbage: its length, then $FF.
;; Also: COPY00 (CBM4S79, HV4, HV4R)
ReleaseOld:
    lda AssignedVariable
    sta Pointer1
    lda AssignedVariable+1
    sta Pointer1+1
    jsr FindStringLink
    bcc CopyDescriptor
    dey
    lda #$FF
    sta (Pointer1),y
    dey
    txa
    sta (Pointer1),y

;; Copies the descriptor's three bytes to the variable.
;; Also: COPY01 (CBM4S79, HV4, HV4R)
CopyDescriptor:
    ldy #DESCRIPTOR_SIZE-1

;; Copies one byte, the last first.
;; Also: COPY02 (CBM4S79, HV4, HV4R)
CopyByte:
    lda (DescriptorPointer),y
    sta (AssignedVariable),y
    dey
    bpl CopyByte
    rts
    .endproc

    ;; BASIC 4's <StoreLinkedDescriptor>, by the name with which the shared modules reach their builds' descriptor copy.
    StoreDescriptor = StoreLinkedDescriptor
.endmacro

;; Emits <FindStringLink>, which finds a string's link.
;; Parameters: patchedStatus = 1 to jump to the revised chip's `TestStatusString`, 0 to compare `DS$`'s address high
;;   byte inline (the original chip)
.macro StringLinkAdjust patchedStatus
    .assert patchedStatus = 0 || patchedStatus = 1, "patchedStatus must be 0 or 1."

    ;; Finds the link after a string's characters, for a nonempty string in string space that is not the disk status
    ;; (`DS$`).
    ;;
    ;; A string whose address has bit 15 set is in ROM or I/O; one below <StringsBottom> is in the program text or
    ;; the input buffer. Neither has a link. The test against <ROM_ORIGIN> after the bit-15 test never branches,
    ;; since BASIC 4's ROM starts above $8000. The original chip recognizes `DS$`'s characters by their address
    ;; alone, so after <ForgetDiskStatus> releases the buffer, a string later given the same address is taken for
    ;; `DS$` and never linked; the revised chip's `TestStatusString` also requires `DS$` to be nonempty.
    ;; In: Pointer1 = the string's descriptor
    ;; Out: carry = set if a link was found, Pointer1 = the link's address when found, X = the length when found,
    ;;   A = the length when not found, Y = 2 unless the string is empty (then 0)
    ;; Entry:
    ;;   CompareStatusLow = compares the address's low byte with `DS$`'s; the revised chip's `TestStatusString` jumps
    ;;     here when the high bytes match
    ;;   AddLength = adds the length to the address to give the link's; `TestStatusString` jumps here when they differ
    ;; Also: STRADJ (CBM4S79, HV4, HV4R)
    .proc FindStringLink
    ldy #$00
    lda (Pointer1),y
    pha
    beq NoLink
    iny
    lda (Pointer1),y
    tax
    iny
    lda (Pointer1),y
    bmi NoLink
    cmp #>ROM_ORIGIN
    bcs NoLink
    cmp StringsBottom+1
    bcc NoLink
    bne CheckStatus
    cpx StringsBottom
    bcc NoLink

;; In string space: is it `DS$`'s? The revised chip asks `TestStatusString`.
;; Also: ADJ (HV4, HV4R)
CheckStatus:
    .if patchedStatus
        jmp TestStatusString
        nop
    .else
        cmp DiskStatusDescriptor+StringDescriptor::ADDRESS+1
        bne AddLength
    .endif

;; Compares the address's low byte with `DS$`'s: equal means `DS$`, which has no link.
;; Also: ADJDS1 (UNKN)
CompareStatusLow:
    cpx DiskStatusDescriptor+StringDescriptor::ADDRESS
    beq NoLink

;; Pointer1 = the string's address plus its length: the link's address.
;; Also: ADJ02 (UNKN)
AddLength:
    stx Pointer1
    sta Pointer1+1
    pla
    tax
    clc
    adc Pointer1
    sta Pointer1
    bcc Found
    inc Pointer1+1

;; Returns with carry set: found.
;; Also: ADJ00 (CBM4S79, HV4, HV4R)
Found:
    sec
    rts

;; Returns with carry clear and the length in A: no link.
;; Also: ADJ01 (CBM4S79, HV4, HV4R)
NoLink:
    pla
    clc
    rts
    .endproc
.endmacro
