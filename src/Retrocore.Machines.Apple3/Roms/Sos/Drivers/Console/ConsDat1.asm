; ---------------------------------------------------------------------------------------------------------------------
; The comment record and the device information block
; ---------------------------------------------------------------------------------------------------------------------

;; The driver's comment record: $FFFF, the text's length, then the text.
;;
;; SOS.DRIVER keeps the comment apart from the driver's code, so the code's addresses count from <IDBLK>, the first
;; byte after it.
DRIVER_COMMENT:
    .word $FFFF
    .word DRIVER_COMMENT_END - DRIVER_COMMENT_TEXT
DRIVER_COMMENT_TEXT:
    .byte "Console Driver -- "
    .byte "Copyright (C) 1983 by Apple Computer Inc."
DRIVER_COMMENT_END:
    .logicalorg * - (DRIVER_COMMENT_END - DRIVER_COMMENT)

;; The device information block (DIB), through which SOS finds the driver: the entry point, the device's name, its
;; slot and unit, its type, the manufacturer and the version.
;; See: <CNSLDH>, <DEVTYPE>, <RELEASE>
IDBLK:
    .word $00                       ; the next DIB: none, the driver runs one device
    .word CNSLDH                    ; the entry point
    .byte $08                       ; the name's length
    .byte ".CONSOLE       "         ; the name, padded to 15 characters
    .byte $80, $00, $00             ; active; built in, so no slot; unit 0
    .byte DEVTYPE
    .byte SUBTYPE
    .byte $00                       ; reserved
    .word $00                       ; no blocks: a character device
    .word APPLE
    .word RELEASE
    .word $00                       ; no configuration block
