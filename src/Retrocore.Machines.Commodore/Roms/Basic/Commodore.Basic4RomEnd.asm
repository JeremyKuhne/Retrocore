; retrocore: style=strict
; COMMODORE BASIC 4: THE $D000 CHIP'S CHECKSUM, STATUS-LINK HELPER AND SIGN-ON

;; The byte the $D000 chip's patch area runs to: the chip ends at $DFFF.
EXTENSION_ROM_END = $E000

.ifndef PATCH_FILL
;; The fill of BASIC 4's unused ROM bytes, which both chips reserve for patches (defined here and in
;; Commodore.Basic4Patches.asm, whichever a source includes first).
PATCH_FILL = $AA
.endif

;; Emits the end of the $D000 chip: its checksum byte, <Disk::StoreStatusLink>, <Basic4SignOnMessage> and the patch
;; space to the chip's end.
.macro CommodoreBasic4RomEnd

;; The byte that adjusts the $D000 chip's checksum; nothing reads it.
;; Also: CKSUMD (K4S79, HVK4)
ExtensionChecksum:
    .byte $F4

    .scope Disk continued
    ; The status-link helper, placed with the chip's patches.

    ;; Stores A in <IoStatus> and in the disk-status buffer at offset Y, then steps Y down.
    ;;
    ;; <Disk::AllocateStatus> calls it with A = 0 and Y at the buffer's back-link: it clears the I/O status and
    ;; stores the link's high byte in one call.
    ;; In: A = the byte, Y = its offset in the buffer at <DiskStatusDescriptor>
    ;; Out: Y = the offset less 1
    ;; Keeps: A, X
    ;; Also: DSLINK (UNKN), PATCH5 (HVK4)
    .proc StoreStatusLink
    sta IoStatus
    sta (DiskStatusDescriptor+StringDescriptor::ADDRESS),y
    dey
    rts
    .endproc

    .endscope

;; BASIC 4's sign-on banner, then two carriage returns, ending in a zero.
;; Also: SIGNON (HV4, HV4R, HVK4)
Basic4SignOnMessage:
    .byte "*** COMMODORE BASIC 4.0 ***", CARRIAGE_RETURN, CARRIAGE_RETURN, 0

    ; The rest of the chip is reserved for patches.
    .res EXTENSION_ROM_END - *, PATCH_FILL
    .assert * = EXTENSION_ROM_END, "The BASIC 4 ROM must end at $E000."
.endmacro
