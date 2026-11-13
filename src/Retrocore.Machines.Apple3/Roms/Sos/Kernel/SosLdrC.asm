; SOSLDR, part C: the header at the start of SOS.KERNEL, and the names the loader uses.
;
; SOS.KERNEL, SOS.INTERP and SOS.DRIVER all start with an 8-byte label and a 2-byte header count, followed by that
; many header bytes. In SOS.KERNEL and SOS.INTERP, each piece of code that follows has a 4-byte header of its own: the
; address it runs at and its length. The kernel file has three pieces: the loader (address 0, as it runs where it is
; loaded), the global page, and the kernel. SOS.DRIVER's header holds the number of floppy drives, the character set
; and the keyboard table; its driver modules follow, each a title, a code field and a relocation field, each with a
; 2-byte count before it, and $FFFF ends the file.

;; SOS.KERNEL's label, which the boot loader checks.
K_FILE:
    .byte "SOS KRNL"

;; The kernel file's header count: the bytes from <K_DRIVES> up to <LDR_ADR>.
K_HDR_CNT:
    .word LDR_ADR-K_DRIVES

;; The number of built-in floppy drives to configure while SOS.INTERP and SOS.DRIVER load: 1, only .D1.
;; See: <LINK_INIT>, <SET_DRIVES>
K_DRIVES:
    .byte $1

;; Reserved flags; 0.
K_FLAGS:
    .byte $0

;; The interpreter's pathname, as a length byte and the name, in a 48-byte field.
;;
;; The 33 bytes after the name fill the rest of the field. They are whatever was in memory when Apple built
;; SOS.KERNEL, and nothing reads them.
;; See: <D_PATH>, <PATH>
I_PATH:
    .byte $E
    .byte ".D1/SOS.INTERP"
    .byte $AA, $A5, $A0, $F9, $A0, $A0, $A5, $A0, $A0, $A5, $A0, $A0, $C5, $A0, $A0, $98
    .byte $A0, $F0, $A1, $A0, $CC, $A0, $A0, $C5, $A0, $A0, $A0, $A0, $A0, $EE, $A0, $A0
    .byte $C4

;; The driver file's pathname, as a length byte and the name, in a 48-byte field.
;;
;; The 33 bytes after the name fill the rest of the field. They are whatever was in memory when Apple built
;; SOS.KERNEL, and nothing reads them.
;; See: <I_PATH>, <PATH>
D_PATH:
    .byte $E
    .byte ".D1/SOS.DRIVER"
    .byte $FF, $9A, $A0, $FF, $9A, $A0, $A0, $A0, $A0, $D0, $A0, $A0, $C1, $A0, $A0, $8A
    .byte $A0, $A0, $F9, $A0, $C1, $E9, $A0, $9E, $A1, $A0, $F5, $A0, $A0, $A5, $A0, $A0
    .byte $88

;; The loader's own address-and-count header: an unused address of 0, then the loader's length.
;;
;; <SOSLDR1> starts its walk through the kernel file here; <ADVANCE> skips the loader by its count to reach the
;; global page's header.
LDR_ADR:
    .word $0

;; The loader's length, from <SOSLDR> to the end of INIT's space.
LDR_CNT:
    .word ZZEND-SOSLDR

; ---------------------------------------------------------------------------------------------------------------------
; Constants and hardware.
; ---------------------------------------------------------------------------------------------------------------------

TRUE = $80                          ;; a true flag: bit 7 set
FALSE = $0                          ;; a false flag
Z_REG = $FFD0                       ;; the zero-page register: which page the 6502's zero page is
E_REG = $FFDF                       ;; the environment register (speed, I/O, screen, reset, write protect, stack, ROM)
B_REG = $FFEF                       ;; the bank register: which RAM bank shows at $2000-$9FFF
CZPAGE = $1A00                      ;; the caller's (interpreter's) zero page
CSPAGE = $1B00                      ;; the caller's stack page
CXPAGE = $1600                      ;; the caller's extend page: the X bytes of pointers in CZPAGE
SZPAGE = $1800                      ;; SOS's zero page
SXPAGE = $1400                      ;; SOS's extend page
SSPAGE = $0100                      ;; SOS's stack page
ROM_ADR = $F1B9                     ;; a byte in the boot ROM that identifies its revision
ROM_ID = $A0                        ;; the value SOS 1.3 needs at ROM_ADR

; ---------------------------------------------------------------------------------------------------------------------
; The loader's zero-page locations, in the caller's zero page. A name ending in _P is a 3-byte pointer: the address
; here, and its X byte at the same place in CXPAGE, which selects extended addressing ($8n reaches banks n and n+1
; as one 64K space starting at bank n's $2000).
; ---------------------------------------------------------------------------------------------------------------------

ZPAGE = $00                         ;; the base of the loader's zero-page locations
K_BASE = ZPAGE+$0                   ;; where the kernel starts ($B800); the interpreter must end below it
I_BASE_P = ZPAGE+$2                 ;; the interpreter's address and entry point
RDBUF_P = ZPAGE+$4                  ;; where SOS.INTERP and SOS.DRIVER are read to: $80:FILE
SYSBUF_P = ZPAGE+$6                 ;; the 1K buffer SOS uses for the open file: $80:LDREND-$2000
TEMP_BANK = ZPAGE+$8                ;; a driver module's source bank, while its fit is checked
TEMP_ADRH = ZPAGE+$9                ;; the high byte of a driver module's source address in that bank
WORK_P = ZPAGE+$A                   ;; the place in the file being walked
REV_SAVE = ZPAGE+$C                 ;; the count REVERSE moves forward to the next count word
FIRST_ADIB = ZPAGE+$10              ;; the first active DIB, as an offset in its module and then as an address
PREV_ADIB_P = ZPAGE+$12             ;; the last active DIB FLAGS found, whose link it sets
DIB_P = ZPAGE+$14                   ;; the DIB FLAGS is looking at
PG_ALIGN = ZPAGE+$16                ;; for a page-aligned module, the bytes before the code that must start a page
DIB_FLAGS = $14                     ;; a DIB's flags byte: bit 7 set when active, bit 6 set to page-align the module
DIB_DCB = $20                       ;; a DIB's DCB length word; the DCB itself follows it
PREVBANK = ZPAGE+$18                ;; the bank of the previous driver module, holding the DIB the next one links to
PREVDST = ZPAGE+$19                 ;; the previous driver module's address, the top of the space below it (2 bytes)
CODE_P = ZPAGE+$1C                  ;; the word RELOC is adjusting
REL_P = ZPAGE+$1E                   ;; the relocation entry RELOC is reading
REL_END = ZPAGE+$20                 ;; the start of the relocation field, where RELOC stops
SRC_P = ZPAGE+$22                   ;; MOVE's source
DST_P = ZPAGE+$24                   ;; MOVE's destination
CNT = ZPAGE+$26                     ;; MOVE's byte count
DSTBANK = ZPAGE+$2A                 ;; the bank the current driver module goes to
LINK_P = ZPAGE+$2C                  ;; the DIB LINK and ALLOC_DEV are working on
DIB_ENTRY = 2                       ;; a DIB's entry-point word
DIB_UNIT = 4+16+2                   ;; a DIB's unit number
DIB_DTYPE = 4+16+3                  ;; a DIB's device type: bit 7 set for a block device
ETEMP = ZPAGE+$2E                   ;; ERROR's count of characters left
WTEMP = ZPAGE+$2F                   ;; WELCOME's work byte, for multiplying by 3
    .include "SosLdrD.asm"
