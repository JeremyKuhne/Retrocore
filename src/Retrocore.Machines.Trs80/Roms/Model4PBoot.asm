;; TRS-80 MODEL 4P BOOT ROM ($0000-$0FFF), VERSION 1(16)
;;
;; The Model 4P's only ROM: 4K at $0000 that port $9C switches out, leaving RAM. It boots from the hard disk, floppy
;; drive 0 or the RS-232 port, and when a disk wants the Model III's ROM it loads the ROM image MODEL%/III from the
;; floppy into the RAM under it, so the 4P runs Model III software. Keys held at reset choose: F1 or 1 the hard disk,
;; F2 or 2 the floppy, F3 or 3 the ROM image, right SHIFT the RS-232 port, V the version, the period key a RAM
;; test; A-G pick the image MODELA/III-MODELG/III, L loads the image even when one is in RAM, N runs a boot sector
;; without it and P pauses after loading it. Errors show in English, German and French.
;;
;; The ROM works through restarts it copies to RAM: RST $08 disk I/O, $10 shows a text, $18 a message list, $20 gets
;; the next byte of a file, $28 loads a program file and $30 scans the keyboard.
;;
;; Frank Durda IV wrote it; his initials are its second to fifth bytes. The labels are our own, named after what
;; each routine does, as no source is known. The comments are our own, written with trs-80.com's annotated
;; disassembly of the 4P's boot ROM as a reference.
;;
;; Maintained by hand. Trs80RomSourceTests check that it assembles byte-identically to the ROM (8075332).

.cpu Z80

;; Message lists: a word of $FFFE comes before a new screen offset, and $FFFF ends the list.
NEXT_LINE = $FFFE
END_LIST = $FFFF

;; Ports.
MEMORY_MAP_PORT = $84               ;; bit 7 the video page, bits 0-1 the memory map
CRTC_ADDRESS_PORT = $88
CRTC_DATA_PORT = $89
BOOT_ROM_PORT = $9C                 ;; bit 0: the boot ROM at $0000-$0FFF
ARCNET_PORT = $B6
HD_CONTROL_PORT = $C1               ;; the hard disk board: bit 4 reset, bits 2-3 enable with wait states
HD_DATA_PORT = $C8                  ;; the WD1010 hard disk controller's registers
HD_ERROR_PORT = $C9
HD_COUNT_PORT = $CA
HD_SECTOR_PORT = $CB
HD_CYLINDER_LOW_PORT = $CC
HD_CYLINDER_HIGH_PORT = $CD
HD_DRIVE_HEAD_PORT = $CE
HD_STATUS_PORT = $CF                ;; the status, and the command when written
NMI_PORT = $E4
RS232_RESET_PORT = $E8
RS232_BAUD_PORT = $E9
RS232_STATUS_PORT = $EA
RS232_DATA_PORT = $EB
OPTIONS_PORT = $EC                  ;; bit 6: 4 MHz; bit 4: the I/O bus
FDC_STATUS_PORT = $F0               ;; the WD1793's status, and its command when written
FDC_TRACK_PORT = $F1
FDC_SECTOR_PORT = $F2
FDC_DATA_PORT = $F3
DRIVE_SELECT_PORT = $F4

;; A Model III ROM image in the RAM under the boot ROM: its jump table, and Level II's POP HL and JP [HL] at $000B.
MODEL3_JUMP_TABLE = $3000
IMAGE_SIGNATURE_ADDRESS = $000B
IMAGE_SIGNATURE = $E9E1

;; The keyboard's rows and video RAM.
KEYBOARD_ROW0 = $3801
KEYBOARD_ROW1 = $3802
KEYBOARD_ROW2 = $3804
KEYBOARD_ROW4 = $3810
KEYBOARD_ROW5 = $3820
KEYBOARD_ROW6 = $3840
KEYBOARD_ROW7 = $3880
VIDEO = $3C00

;; RAM: the restarts' vectors and RAM_BLOCK's copy.
RST08_VECTOR = $4000
RST10_VECTOR = $4003
RST18_VECTOR = $4006
RST20_VECTOR = $4009
RST28_VECTOR = $400C
RST30_VECTOR = $400F
RST38_VECTOR = $4012
NMI_VECTOR = $4015                  ;; RAM_BLOCK's copy starts here
IMAGE_NAME = NMI_VECTOR + 3         ;; MODEL%, whose % a letter held at reset replaces
IMAGE_LETTER = IMAGE_NAME + 5
EXIT_RAM = NMI_VECTOR + 11          ;; EXIT_BOOT's copy
EXIT_ADDRESS = EXIT_RAM + 4         ;; its JP's address
HALT_RAM = NMI_VECTOR + 18          ;; HALT_FDIV's copy
READ_WORD_RAM = NMI_VECTOR + 41     ;; READ_IMAGE_WORD's copy

;; RAM: the boot's variables, cleared at reset. Those marked are left for the booted program.
BOOT_TYPE = $4055                   ;; left: 1 floppy, 2 hard disk, 4 RS-232
BOOT_SIZE = $4056                   ;; left: the boot sector's 256-byte blocks
BAUD_CODE = $4057                   ;; left: the RS-232 baud rate
IMAGE_LOADED = $4058                ;; left: nonzero once the ROM image was loaded from disk
BOOT_KEY = $4059                    ;; the boot key's code: $80 V, $83 right shift, $86-$88 F1-F3
BREAK_HELD = $405B                  ;; left: nonzero when BREAK was held at reset
FIRST_SECTOR = $405C                ;; the disk's first sector number, 0 or 1
DIR_CYLINDER = $405D
NEXT_SECTOR = $405E                 ;; the next sector to read in the cylinder
SIDES = $405F
SECTORS_LEFT = $4060                ;; in the extent being read
FILE_CYLINDER = $4062
GRANULE_SECTORS = $4063
NO_IMAGE_HELD = $4064               ;; N was held
PAUSE_HELD = $4065                  ;; P was held
LOAD_HELD = $4066                   ;; L was held
RESTORE_ERROR = $4067               ;; the error of drive 0's restore at reset
ERROR_LETTER = $4068                ;; a one-letter text and its zero, for the RS-232 boot's messages
BOOT_VARIABLES_END = $406B          ;; the end of the cleared variables
STACK_TOP = $40A0
IMAGE_ENTRY = $40A2                 ;; MODEL%/III's directory entry, then $FE
SECTOR_BUFFER = $4300               ;; where sectors are read, and the boot sector runs

.org $0000

;; Power-up and reset. The four bytes after DI are FDIV, the initials of Frank Durda IV, run as harmless loads.
RESET:
    DI
    LD B,[HL]
    LD B,H
    LD C,C
    LD D,[HL]
    JR POWER_UP
    .byte $00

;; The restarts, each a jump through a vector in RAM at $4000-$4014. The JP after each is the vector's
;; image, which COPY_VECTORS copies there; RST $38's is a RET, as interrupts stay off.
RST_08:
    JP RST08_VECTOR

;; RST $08's vector: disk I/O.
VECTOR_IMAGE:
    JP DISK_IO
    .byte $00, $00
    JP RST10_VECTOR
    JP SHOW_TEXT
    .byte $00, $00
    JP RST18_VECTOR
    JP SHOW_LIST
    .byte $00, $00
    JP RST20_VECTOR
    JP NEXT_FILE_BYTE
    .byte $00, $00
    JP RST28_VECTOR
    JP LOAD_FILE
    .byte $00, $00
    JP RST30_VECTOR
    JP SCAN_KEYS
    .byte $00, $00
    JP RST38_VECTOR
    RET
    .byte $00, $00

;; Turns NMIs off and selects 4 MHz with the I/O bus.
POWER_UP:
    XOR A
    OUT [NMI_PORT],A
    LD A,$50
    OUT [OPTIONS_PORT],A

;; Copies the seven vector images, eight bytes apart, to RST08_VECTOR-RST38_VECTOR, sets the stack and goes on to
;; set up the hardware.
COPY_VECTORS:
    LD B,$07
    LD HL,VECTOR_IMAGE
    LD DE,RST08_VECTOR
COPY_VECTORS_1:
    LD C,$03
COPY_VECTORS_2:
    LD A,[HL]
    LD [DE],A
    INC DE
    INC HL
    DEC C
    JR NZ,COPY_VECTORS_2
    LD A,L
    ADD A,$05
    LD L,A
    DJNZ COPY_VECTORS_1
    LD SP,STACK_TOP
    LD C,CRTC_ADDRESS_PORT
    JR SET_UP
    .byte "III"

;; The NMI: through NMI_VECTOR, which ends a floppy sector read.
NMI:
    JP NMI_VECTOR

;; The block COPY_RAM_BLOCK copies to NMI_VECTOR ($4015-$4047): the NMI's jump, the image file's name, and the routines
;; that must run with the boot ROM switched out.
RAM_BLOCK:
    JP FLOPPY_READ_END
    .byte "MODEL%  "

;; Runs at EXIT_RAM: switches the boot ROM out and goes to the booted program, at SECTOR_BUFFER or the address
;; BOOT_PROGRAM stores in EXIT_ADDRESS.
EXIT_BOOT:
    XOR A
    OUT [BOOT_ROM_PORT],A
    JP SECTOR_BUFFER
    .byte $00

;; Runs at HALT_RAM: halts, its bytes spelling fdiv.
HALT_FDIV:
    LD H,[HL]
    LD H,H
    LD L,C
    HALT
    .byte $00

;; The version, shown by the V key.
VERSION_TEXT:
    .byte "1(16) 18-Oct-83", $00, $00, $00

;; Runs at READ_WORD_RAM: reads the word at $000B of the RAM under the boot ROM, which tells whether a Model III ROM
;; image is there.
;; Out:   HL = the word, A = 1
READ_IMAGE_WORD:
    XOR A
    OUT [BOOT_ROM_PORT],A
    LD HL,[IMAGE_SIGNATURE_ADDRESS]
    INC A
    OUT [BOOT_ROM_PORT],A
    RET
RAM_BLOCK_END:
.assert RAM_BLOCK_END - RAM_BLOCK = $33, "RAM_BLOCK is $4015-$4047."

;; Shown before the version.
VERSION_MSG:
    .byte "Boot ROM Version Is ", $00

;; The 6845's registers R1-R15: all zero, as the Model III's display needs; the byte after them is not used.
CRTC_TABLE:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

;; Sets interrupt mode 1, stops the floppy disk controller and writes the 6845's registers.
SET_UP:
    IM 1
    LD A,$D0
    OUT [FDC_STATUS_PORT],A
    LD B,$0F
    LD HL,CRTC_TABLE + 14           ; R15's value: the loop runs down to R1
SET_UP_1:
    LD A,[HL]
    OUT [C],B
    OUT [CRTC_DATA_PORT],A
    DEC HL
    DJNZ SET_UP_1

;; The period key held at reset runs the RAM test.
TEST_KEY:
    LD A,[KEYBOARD_ROW5]
    BIT 6,A
    JP NZ,RAM_TEST

;; Clears both pages of video RAM, leaving page 0 shown.
CLEAR_PAGES:
    LD A,$80
    OUT [MEMORY_MAP_PORT],A
    CALL CLEAR_SCREEN
    LD A,$00
    OUT [MEMORY_MAP_PORT],A
    CALL CLEAR_SCREEN

;; Copies RAM_BLOCK to NMI_VECTOR.
COPY_RAM_BLOCK:
    LD DE,NMI_VECTOR
    LD HL,RAM_BLOCK
    LD BC,RAM_BLOCK_END - RAM_BLOCK
    LDIR

;; Clears the boot variables, scans the keyboard for keys held at reset, and restores the floppy drives.
SCAN_BOOT_KEYS:
    LD HL,BOOT_TYPE
    LD [HL],$00
    LD D,H
    LD E,L
    INC DE
    LD BC,BOOT_VARIABLES_END - BOOT_TYPE - 1
    LDIR
    LD BC,$7FFF
    RST $30
    PUSH AF
    LD A,$01
    LD B,$04
    RST $08
    JR Z,SCAN_BOOT_KEYS_1
    LD [RESTORE_ERROR],A
    CP $06
    JR Z,SCAN_BOOT_KEYS_2
SCAN_BOOT_KEYS_1:
    LD B,$32
    LD A,$01
    RST $08
SCAN_BOOT_KEYS_2:
    POP AF
    JR Z,AUTO_BOOT

;; Acts on the key held at reset: F1 or 1 boots the hard disk, F2 or 2 the floppy disk, F3 or 3 starts the ROM
;; image, right SHIFT boots over the RS-232 port and V shows the version.
KEY_ACTION:
    LD A,[BOOT_KEY]
    CP $86
    JR NZ,KEY_ACTION_1
    CALL HARD_DISK_BOOT
    JR KEY_ACTION_2
KEY_ACTION_1:
    CP $87
    JR NZ,KEY_ACTION_3
    CALL FLOPPY_BOOT
KEY_ACTION_2:
    OR A
    JR Z,KEY_ACTION_4
    JR SHOW_ERROR
KEY_ACTION_3:
    CP $88
KEY_ACTION_4:
    JR Z,START_IMAGE
    CP $80
    JR NZ,KEY_ACTION_5
    LD DE,$0000
    LD HL,VERSION_MSG
    RST $10
    LD HL,VERSION_TEXT
    RST $10
    JR STOP
KEY_ACTION_5:
    CP $83
    JP Z,RS232_BOOT
    JR SCAN_BOOT_KEYS

;; Shows the message of an error code, in English, German and French, and halts.
;; In:    A = the error code
SHOW_ERROR:
    ADD A,A
    LD HL,ERROR_LISTS
    LD D,$00
    LD E,A
    ADD HL,DE
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    XOR A
    LD E,A
    RST $18

;; Halts in RAM, with the boot ROM switched out.
STOP:
    JP HALT_RAM

;; No key was held: boots from an ARCNET board, the hard disk or the floppy disk, whichever answers first.
AUTO_BOOT:
    LD A,$55
    LD B,A
    OUT [ARCNET_PORT],A
    IN A,[ARCNET_PORT]
    CP B
    CALL Z,ARCNET_FOUND
    CALL HARD_DISK_BOOT
    OR A
    CALL NZ,FLOPPY_BOOT

;; Starts the Model III ROM image: the one in RAM, unless L was held, or MODEL%/III loaded from floppy drive 0.
START_IMAGE:
    LD A,[LOAD_HELD]
    OR A
    JR NZ,START_IMAGE_1
    CALL IMAGE_IN_RAM
    JR Z,BOOT_PROGRAM
START_IMAGE_1:
    LD A,[RESTORE_ERROR]
    OR A
    JR NZ,SHOW_ERROR
    LD A,$01
    OUT [MEMORY_MAP_PORT],A
    LD DE,$0000
    LD HL,MSG_LOADING_IMAGE
    RST $18
    CALL LOAD_IMAGE
    PUSH AF
    PUSH HL
    CALL CLEAR_SCREEN
    POP HL
    POP AF
    JR NZ,SHOW_ERROR
    LD A,$01
    LD [IMAGE_LOADED],A

;; Sets the program's address in EXIT_ADDRESS, waits for ENTER or BREAK after a load if P was held, and goes to
;; it with the boot ROM switched out.
;; In:    HL = the program's address
BOOT_PROGRAM:
    LD [EXIT_ADDRESS],HL
    LD A,[PAUSE_HELD]
    OR A
    JR Z,BOOT_PROGRAM_2
    LD HL,MSG_IMAGE_LOADED
    RST $18
BOOT_PROGRAM_1:
    LD A,[KEYBOARD_ROW6]
    AND $05
    JR Z,BOOT_PROGRAM_1
BOOT_PROGRAM_2:
    XOR A
    OUT [MEMORY_MAP_PORT],A
    LD A,$10
    OUT [OPTIONS_PORT],A
    JP EXIT_RAM

;; Boots from the hard disk. Returns only when it cannot: A = 0 when the boot sector needs the ROM image, else an
;; error code.
HARD_DISK_BOOT:
    LD A,$02
    LD B,$01
    RST $08
    RET NZ
    LD A,$02
    JR READ_BOOT_SECTOR

;; Boots from floppy drive 0, returning as HARD_DISK_BOOT does.
FLOPPY_BOOT:
    LD A,[RESTORE_ERROR]
    OR A
    RET NZ
    INC A

;; Reads the boot sector of the device in A, notes its size, and runs it unless it needs the ROM image.
;; In:    A = 1 for floppy, 2 for hard disk
READ_BOOT_SECTOR:
    LD BC,$0C01
    LD [BOOT_TYPE],A
    LD DE,$0000
    LD HL,SECTOR_BUFFER
    RST $08
    RET NZ
    LD A,E
    LD [BOOT_SIZE],A
    DEC A
    CALL Z,NEEDS_IMAGE
    JR Z,BOOT_PROGRAM_2
    LD A,$00
    RET

;; Whether a Model III ROM image is in the RAM under the boot ROM: its jump table at $3000 and the word at $000B.
;; Out:   zero = set when it is
IMAGE_IN_RAM:
    LD HL,MODEL3_JUMP_TABLE             ; ten JPs
    LD B,$0A
    LD A,$C3
IMAGE_IN_RAM_1:
    CP [HL]
    RET NZ
    INC HL
    INC HL
    INC HL
    DJNZ IMAGE_IN_RAM_1
    CALL READ_WORD_RAM
    XOR A
    LD DE,IMAGE_SIGNATURE
    SBC HL,DE
    LD HL,MODEL3_JUMP_TABLE + 21
    RET

;; Fills video RAM with spaces.
CLEAR_SCREEN:
    LD A,$20
    LD HL,VIDEO
    LD BC,$03FF
    LD [HL],A
    LD D,H
    LD E,L
    INC DE
    LDIR
    RET

;; Whether the boot sector calls into the ROM area, and so needs the ROM image, unless N was held.
;; Out:   zero = set when it does
NEEDS_IMAGE:
    LD A,[NO_IMAGE_HELD]
    OR A
    JR NZ,NEEDS_IMAGE_3
    LD HL,SECTOR_BUFFER
    LD B,$FE
NEEDS_IMAGE_1:
    LD A,$CD
    CP [HL]
    JR Z,NEEDS_IMAGE_5
NEEDS_IMAGE_2:
    INC HL
    DJNZ NEEDS_IMAGE_1
NEEDS_IMAGE_3:
    CALL IMAGE_IN_RAM
    JR NZ,NEEDS_IMAGE_4
    LD A,$01
    OUT [MEMORY_MAP_PORT],A
    LD HL,MODEL3_JUMP_TABLE             ; erase the image's jump table, so it is loaded afresh next time
    LD D,H
    LD E,L
    LD [HL],L
    INC DE
    LD BC,30
    LDIR
NEEDS_IMAGE_4:
    XOR A
    RET
NEEDS_IMAGE_5:
    INC HL
    DEC B
    INC HL
    DEC B
    LD A,[HL]
    OR A
    JR NZ,NEEDS_IMAGE_2
    OR L
    RET

;; RST $10: shows a text, ended by a zero byte, at a screen offset.
;; In:    HL = the text, DE = the offset (or a video RAM address)
;; Out:   DE = past the text, HL = at its zero byte, A = 0
SHOW_TEXT:
    LD A,D
    OR $3C
    LD D,A
SHOW_TEXT_1:
    LD A,[HL]
    OR A
    RET Z
    LD [DE],A
    INC HL
    INC DE
    JR SHOW_TEXT_1

;; RST $18: shows a message list: words that are the addresses of texts, each shown after the one before, with
;; NEXT_LINE before a new screen offset and END_LIST at the end.
;; In:    HL = the list, zero = set when DE holds the first offset, else the list starts with it
SHOW_LIST:
    JR Z,SHOW_LIST_2
SHOW_LIST_1:
    LD E,[HL]
    INC HL
    LD D,[HL]
    INC HL
SHOW_LIST_2:
    LD B,H
    LD C,L
SHOW_LIST_3:
    LD A,[BC]
    INC BC
    LD L,A
    LD A,[BC]
    INC BC
    LD H,A
    INC A
    JR NZ,SHOW_LIST_4
    LD A,L
    INC A
    RET Z
    INC A
    JR NZ,SHOW_LIST_4
    PUSH BC
    POP HL
    JR SHOW_LIST_1
SHOW_LIST_4:
    RST $10
    JR SHOW_LIST_3

;; The message lists of the error codes 0-12.
ERROR_LISTS:
    .word MSG_ERROR0, MSG_ERROR1, MSG_ERROR2, MSG_ERROR3, MSG_ERROR4, MSG_ERROR5, MSG_ERROR6, MSG_ERROR7, MSG_ERROR8, MSG_ERROR9, MSG_ERROR10, MSG_ERROR11, MSG_ERROR12

;; Each error's message, in English, German and French on rows 0, 3 and 6 (errors 11 and 12 in English only).
MSG_ERROR0:
    .word TX_THE, TX_ROM_IMAGE, TX_WAS_NOT, TX_FOUND_ON_DRIVE, TX_0, NEXT_LINE, $00C0, TX_ROM_IMAGE, TX_IST_NICHT + 4, TX_GEFUNDEN_AUF, TX_DISKETTEN_LAUFWERK + 10, TX_0, NEXT_LINE, $0180, TX_ROM_IMAGE + 4, TX_DU_ROM + 3, TX_ABSENT, TX_E_DU, TX_OU_UTILISEZ_UNE_AUTRE + 22, TX_DANS_L_UNIT_0, END_LIST
MSG_ERROR1:
    .word TX_ARCNET, TX_BOOT, TX_IS_NOT, TX_AVAILABLE, NEXT_LINE, $00C0, TX_ARCNET, TX_BOOT, TX_IST_NICHT, TX_IM_SYSTEM, NEXT_LINE, $0180, TX_BOOT, TX_ARCNET, TX_ABSENT, TX_E_DU + 1, TX_SYST_ME, END_LIST
MSG_ERROR2:
    .word TX_ROM_IMAGE, TX_CAN_T_BE_LOADED, TX_TOO_MANY_EXTENTS, NEXT_LINE, $00C0, TX_ROM_IMAGE, TX_KANN, TX_IST_NICHT + 4, TX_IST_GELADEN + 4, TX_WERDEN, TX_CAN_T_BE_LOADED + 16, TX_ZU_VIELE_BEREICHE, NEXT_LINE, $0180, TX_ROM_IMAGE + 4, TX_DU_ROM + 3, TX_NON_CHARGEABLE, TX_CAN_T_BE_LOADED + 16, TX_SEGMENTS_TROP_NUMBREUX, END_LIST
MSG_ERROR3:
    .word TX_THE, TX_HARD_DISK, TX_FOUND_ON_DRIVE + 9, TX_IS_NOT, TX_WHEN_YOU_ARE_READY + 13, NEXT_LINE, $00C0, TX_DIE_FESTPLATTE, TX_IST_NICHT, TX_BEREIT, NEXT_LINE, $0180, TX_UNIT, TX_OU_UTILISEZ_UNE_AUTRE + 22, TX_DUR, TX_NON_PR_TE, END_LIST
MSG_ERROR4:
    .word TX_THE, TX_FLOPPY, TX_HARD_DISK + 5, TX_FOUND_ON_DRIVE + 9, TX_IS_NOT, TX_WHEN_YOU_ARE_READY + 13, NEXT_LINE, $00C0, TX_DISKETTEN_LAUFWERK, TX_IST_NICHT + 4, TX_BEREIT, NEXT_LINE, $0180, TX_UNIT, TX_OU_UTILISEZ_UNE_AUTRE + 22, TX_SOUPLE, TX_NON_PR_TE, END_LIST
MSG_ERROR5:
    .word TX_THE, TX_HARD_DISK, TX_FOUND_ON_DRIVE + 9, TX_IS_NOT, TX_AVAILABLE, NEXT_LINE, $00C0, TX_DIE_FESTPLATTE, TX_IST_NICHT, TX_IM_SYSTEM, NEXT_LINE, $0180, TX_UNIT, TX_OU_UTILISEZ_UNE_AUTRE + 22, TX_DUR, TX_ABSENT, TX_E_DU + 1, TX_SYST_ME, END_LIST
MSG_ERROR6:
    .word TX_THE, TX_FLOPPY, TX_HARD_DISK + 5, TX_FOUND_ON_DRIVE + 9, TX_IS_NOT, TX_AVAILABLE, NEXT_LINE, $00C0, TX_DISKETTEN_LAUFWERK, TX_IST_NICHT, TX_IM_SYSTEM, NEXT_LINE, $0180, TX_UNIT, TX_OU_UTILISEZ_UNE_AUTRE + 22, TX_SOUPLE, TX_ABSENT, TX_E_DU + 1, TX_SYST_ME, END_LIST
MSG_ERROR7:
    .word TX_CLOSE, TX_THE, TX_FLOPPY, TX_FOUND_ON_DRIVE + 9, TX_DOOR_AND_TRY_AGAIN, NEXT_LINE, $00C0, TX_DISKETTEN_LAUFWERK, TX_SCHLIE_EN_UND_ERNEUT, NEXT_LINE, $0180, TX_FERMEZ_PORTE_D_UNIT, END_LIST
MSG_ERROR8:
    .word TX_CRC, TX_SEEK_ERROR + 5, TX_SPACE, TX_DOOR_AND_TRY_AGAIN + 9, TX_OR_USE_ANOTHER, TX_HARD_DISK + 5, NEXT_LINE, $00C0, TX_CRC, TX_FEHLER, TX_NEU_STARTEN_ODER_EINE, NEXT_LINE, $0180, TX_ERREUR, TX_CRC_2, TX_FERMEZ_PORTE_D_UNIT + 24, TX_OU_UTILISEZ_UNE_AUTRE, END_LIST
MSG_ERROR9:
    .word TX_SEEK_ERROR, TX_SPACE, TX_DOOR_AND_TRY_AGAIN + 9, TX_OR_USE_ANOTHER, TX_HARD_DISK + 5, NEXT_LINE, $00C0, TX_SUCH, TX_FEHLER, TX_NEU_STARTEN_ODER_EINE, NEXT_LINE, $0180, TX_ERREUR, TX_DE_CHERCHER, TX_FERMEZ_PORTE_D_UNIT + 24, TX_OU_UTILISEZ_UNE_AUTRE, END_LIST
MSG_ERROR10:
    .word TX_THE, TX_ROM_IMAGE, TX_CAN_T_BE_LOADED, TX_FLOPPY, TX_HARD_DISK + 5, TX_FOUND_ON_DRIVE + 9, TX_IS_NOT, TX_WHEN_YOU_ARE_READY + 13, NEXT_LINE, $00C0, TX_ROM_IMAGE, TX_KANN, TX_IST_NICHT + 4, TX_IST_GELADEN + 4, TX_WERDEN, TX_CAN_T_BE_LOADED + 16, TX_DISKETTEN_LAUFWERK, NEXT_LINE, $0100, TX_IST_NICHT, TX_BEREIT, NEXT_LINE, $0180, TX_ROM_IMAGE + 4, TX_DU_ROM + 3, TX_NON_CHARGEABLE, TX_CAN_T_BE_LOADED + 16, TX_UNIT, TX_OU_UTILISEZ_UNE_AUTRE + 22, TX_SOUPLE, TX_NON_PR_TE, END_LIST
MSG_ERROR11:
    .word TX_LOST_DATA, TX_SEEK_ERROR + 5, END_LIST
MSG_ERROR12:
    .word TX_ID, TX_SEEK_ERROR + 5, END_LIST

;; Shown when P was held and the ROM image is loaded.
MSG_IMAGE_LOADED:
    .word $0000, TX_THE, TX_ROM_IMAGE, TX_HAS_BEEN, TX_CAN_T_BE_LOADED + 8, TX_SWITCH_DISKS_AND, NEXT_LINE, $0040, TX_PRESS_ENTER, TX_OR_BREAK, TX_WHEN_YOU_ARE_READY, NEXT_LINE, $00C0, TX_ROM_IMAGE, TX_IST_GELADEN, TX_CAN_T_BE_LOADED + 16, TX_DISKETTEN_WECHSELN_UND_DANN, TX_PRESS_ENTER + 6, NEXT_LINE, $0100, TX_ODER, TX_OR_BREAK + 3, TX_DR_CKEN, NEXT_LINE, $0180, TX_L_IMAGE, TX_DU_ROM, TX_CHARG_E, TX_CAN_T_BE_LOADED + 16, TX_CHANGEZ_DE, TX_OU_UTILISEZ_UNE_AUTRE + 22, TX_ET_APPUYEZ_SUR, NEXT_LINE, $01C0, TX_PRESS_ENTER + 6, TX_OU, TX_OR_BREAK + 3, TX_POUR_CONTINUER, END_LIST

;; Shown while the ROM image loads.
MSG_LOADING_IMAGE:
    .word TX_LOADING, TX_ROM_IMAGE, TX_CAN_T_BE_LOADED + 16, TX_PLEASE_WAIT, NEXT_LINE, $00C0, TX_ROM_IMAGE, TX_WIRD, TX_IST_GELADEN + 4, TX_CAN_T_BE_LOADED + 16, TX_BITTE_WARTEN, NEXT_LINE, $0180, TX_CHARGEMENT_DE, TX_L_IMAGE, TX_DU_ROM + 3, TX_CAN_T_BE_LOADED + 16, TX_VEUILLEZ_PATIENTER, END_LIST
TX_THE:
    .byte "The ", $00
TX_LOADING:
    .byte "Loading ", $00
TX_ROM_IMAGE:
    .byte "ROM Image ", $00
TX_WAS_NOT:
    .byte "Was Not ", $00
TX_FOUND_ON_DRIVE:
    .byte "Found On Drive ", $00
TX_0:
    .byte "0", $00
TX_ARCNET:
    .byte "Arcnet ", $00
TX_BOOT:
    .byte "Boot ", $00
TX_IS_NOT:
    .byte "Is Not ", $00
TX_AVAILABLE:
    .byte "Available ", $00
TX_CAN_T_BE_LOADED:
    .byte "Can't Be Loaded - ", $00
TX_TOO_MANY_EXTENTS:
    .byte "Too Many Extents", $00
TX_FLOPPY:
    .byte "Floppy ", $00
TX_HARD_DISK:
    .byte "Hard Disk ", $00
TX_WHEN_YOU_ARE_READY:
    .byte "When You Are Ready ", $00
TX_CLOSE:
    .byte "Close ", $00
TX_DOOR_AND_TRY_AGAIN:
    .byte "Door And Try Again ", $00
TX_LOST_DATA:
    .byte "Lost Data ", $00
TX_CRC:
    .byte "CRC ", $00
TX_SEEK_ERROR:
    .byte "Seek Error", $00
TX_SPACE:
    .byte ", ", $00
TX_OR_USE_ANOTHER:
    .byte "Or Use Another ", $00
TX_HAS_BEEN:
    .byte "Has Been", $00
TX_SWITCH_DISKS_AND:
    .byte "Switch Disks And ", $00
TX_PLEASE_WAIT:
    .byte "Please Wait", $00
TX_PRESS_ENTER:
    .byte "Press <Enter> ", $00
TX_OR_BREAK:
    .byte "Or <Break> ", $00
TX_ID:
    .byte "ID ", $00
TX_IST_NICHT:
    .byte "Ist Nicht ", $00
TX_GEFUNDEN_AUF:
    .byte "Gefunden Auf ", $00
TX_DISKETTEN_LAUFWERK:
    .byte "Disketten-Laufwerk ", $00
TX_KANN:
    .byte "Kann ", $00
TX_IST_GELADEN:
    .byte "Ist Geladen ", $00
TX_DISKETTEN_WECHSELN_UND_DANN:
    .byte "Disketten Wechseln Und Dann ", $00
TX_DIE_FESTPLATTE:
    .byte "Die Festplatte ", $00
TX_WERDEN:
    .byte "Werden ", $00
TX_ZU_VIELE_BEREICHE:
    .byte "Zu Viele Bereiche", $00
TX_BEREIT:
    .byte "Bereit ", $00
TX_SCHLIE_EN_UND_ERNEUT:
    .byte "Schlie", $04, "en Und Erneut Starten", $00
TX_DURDA:
    .byte "Durda", $00
TX_FEHLER:
    .byte "Fehler, ", $00
TX_NEU_STARTEN_ODER_EINE:
    .byte "Neu Starten Oder Eine Andere Platte Benutzen", $00
TX_DR_CKEN:
    .byte "Dr", $0A, "cken ", $00
TX_ODER:
    .byte "Oder ", $00
TX_WIRD:
    .byte "Wird ", $00
TX_BITTE_WARTEN:
    .byte "Bitte Warten", $00
TX_IM_SYSTEM:
    .byte "Im System", $00
TX_SUCH:
    .byte "Such ", $00
TX_ABSENT:
    .byte "Absent", $00
TX_E_DU:
    .byte "e Du ", $00
TX_DANS_L_UNIT_0:
    .byte " Dans l'Unit", $03, " 0", $00
TX_SYST_ME:
    .byte "Syst", $0C, "me ", $00
TX_NON_CHARGEABLE:
    .byte "Non Chargeable ", $00
TX_SEGMENTS_TROP_NUMBREUX:
    .byte "Segments Trop Numbreux", $00
TX_UNIT:
    .byte "Unit", $03, " ", $00
TX_FRANK:
    .byte "Frank ", $00
TX_OU_UTILISEZ_UNE_AUTRE:
    .byte "Ou Utilisez Une Autre Disque", $00
TX_SOUPLE:
    .byte "-Souple ", $00
TX_DUR:
    .byte "-Dur ", $00
TX_NON_PR_TE:
    .byte "Non Pr", $12, "te ", $00
TX_FERMEZ_PORTE_D_UNIT:
    .byte "Fermez Porte d'Unit", $03, " Et R", $03, "essayez ", $00
TX_CRC_2:
    .byte "CRC, ", $00
TX_ERREUR:
    .byte "Erreur ", $00
TX_DE_CHERCHER:
    .byte "De Chercher, ", $00
TX_L_IMAGE:
    .byte "l'Image ", $00
TX_DU_ROM:
    .byte "Du ROM ", $00
TX_CHARG_E:
    .byte "Charg", $03, "e ", $00
TX_CHANGEZ_DE:
    .byte "Changez De ", $00
TX_ET_APPUYEZ_SUR:
    .byte " Et Appuyez Sur ", $00
TX_OU:
    .byte "Ou ", $00
TX_POUR_CONTINUER:
    .byte "Pour Continuer", $00
TX_CHARGEMENT_DE:
    .byte "Chargement De ", $00
TX_VEUILLEZ_PATIENTER:
    .byte "Veuillez Patienter ", $00

;; RST $30: scans the keyboard for the keys held at reset. A letter A-G replaces the % of MODEL%; L, N, P and BREAK
;; set their flags; the boot keys set BOOT_KEY. ENTER ends the scan.
;; In:    BC = the passes
;; Out:   A = the boot key's code, zero = set when none
SCAN_KEYS:
    LD A,[KEYBOARD_ROW6]
    RRCA
    JR C,SCAN_KEYS

;; One pass of the scan.
SCAN_PASS:
    LD A,[KEYBOARD_ROW0]
    AND $FE
    JR Z,SCAN_PASS_2
    LD D,$FF
SCAN_PASS_1:
    INC D
    RRCA
    JR NC,SCAN_PASS_1
    LD A,$40
    ADD A,D
    LD [IMAGE_LETTER],A
SCAN_PASS_2:
    LD A,[KEYBOARD_ROW6]
    BIT 2,A
    JR Z,SCAN_PASS_3
    LD [BREAK_HELD],A
SCAN_PASS_3:
    BIT 0,A
    JR NZ,SCAN_PASS_11
    LD A,[KEYBOARD_ROW1]
    BIT 6,A
    JR Z,SCAN_PASS_4
    LD [NO_IMAGE_HELD],A
SCAN_PASS_4:
    BIT 4,A
    JR Z,SCAN_PASS_5
    LD [LOAD_HELD],A
SCAN_PASS_5:
    LD D,$80
    LD A,[KEYBOARD_ROW2]
    BIT 6,A
    JR NZ,SCAN_PASS_9
    BIT 0,A
    JR Z,SCAN_PASS_6
    LD [PAUSE_HELD],A
SCAN_PASS_6:
    INC D
    INC D
    LD A,[KEYBOARD_ROW7]
    OR A
    JR Z,SCAN_PASS_8
SCAN_PASS_7:
    RRCA
    JR C,SCAN_PASS_9
    INC D
    JR SCAN_PASS_7
SCAN_PASS_8:
    LD A,[KEYBOARD_ROW4]
    LD D,$86
    BIT 1,A
    JR NZ,SCAN_PASS_9
    INC D
    BIT 2,A
    JR NZ,SCAN_PASS_9
    INC D
    BIT 3,A
    JR Z,SCAN_PASS_10
SCAN_PASS_9:
    LD A,D
    LD [BOOT_KEY],A
SCAN_PASS_10:
    DEC BC
    LD A,B
    OR C
    JR NZ,SCAN_PASS
SCAN_PASS_11:
    LD A,[BOOT_KEY]
    OR A
    RET

;; RST $08: disk I/O: restores, seeks or reads a sector of the floppy or hard disk.
;; In:    A = 1 floppy, 2 hard disk; B = the function; C = the sector; DE = the cylinder; HL = the buffer
;; Out:   A = 0 and zero = set, or an error code
DISK_IO:
    DEC A
    JP Z,FLOPPY_IO
    LD A,B
    CP $01
    JR NZ,HARD_DISK_IO
    CALL HD_RESET
    LD B,$04

;; The hard disk: a controller answers when its sector register reads back. Sets up the task file: the sector, the
;; cylinder, and drive 0 with 256-byte sectors.
HARD_DISK_IO:
    LD A,C
    OUT [HD_SECTOR_PORT],A
    IN A,[HD_SECTOR_PORT]
    CP C
    LD A,$05
    JR NZ,HD_WAIT_READY_4
    XOR A
    OUT [HD_DRIVE_HEAD_PORT],A
    LD A,D
    OUT [HD_CYLINDER_HIGH_PORT],A
    LD A,E
    OUT [HD_CYLINDER_LOW_PORT],A

;; Waits for the hard disk to be ready.
HD_WAIT_READY:
    PUSH BC
    LD D,$08
HD_WAIT_READY_1:
    LD BC,$0000
HD_WAIT_READY_2:
    IN A,[HD_STATUS_PORT]
    BIT 6,A
    JR NZ,HD_SEEK_READ
    DEC BC
    LD A,B
    OR C
    JR NZ,HD_WAIT_READY_2
    DEC D
    JR NZ,HD_WAIT_READY_1
    POP BC
    LD D,$03
HD_WAIT_READY_3:
    LD A,D
HD_WAIT_READY_4:
    OR A
    RET

;; Restores or seeks, then reads a sector into HL.
HD_SEEK_READ:
    POP BC
    LD A,B
    LD D,$16
    CP $04
    JR Z,HD_SEEK_READ_1
    LD D,$70
HD_SEEK_READ_1:
    LD A,D
    OUT [HD_STATUS_PORT],A
    CALL HD_WAIT
    JR NZ,HD_ERROR
    LD A,B
    CP $0C
    JR NZ,HD_SEEK_READ_3
    LD A,$20
    LD E,$00
    OUT [HD_STATUS_PORT],A
    CALL HD_WAIT
    JR Z,HD_SEEK_READ_2
    LD D,C
    CALL HD_ERROR_REGISTER
    BIT 4,C
    JR Z,HD_ERROR_1
    LD A,$20
    OUT [HD_DRIVE_HEAD_PORT],A
    LD A,D
    OUT [HD_SECTOR_PORT],A
    LD A,$20
    OUT [HD_STATUS_PORT],A
    CALL HD_WAIT
    JR NZ,HD_ERROR
    CALL HD_SEEK_READ_2
HD_SEEK_READ_2:
    LD BC,$00C8
    INIR
    INC E
HD_SEEK_READ_3:
    XOR A
    RET

;; Turns the hard disk's error register into an error code.
HD_ERROR:
    CALL HD_ERROR_REGISTER
HD_ERROR_1:
    LD D,$08
    BIT 6,A
    JR NZ,HD_WAIT_READY_3
    BIT 5,A
    JR NZ,HD_WAIT_READY_3
    LD D,$0C
    BIT 4,A
    JR NZ,HD_WAIT_READY_3
    LD D,$09
    JR HD_WAIT_READY_3

;; Reads the hard disk's error register.
;; Out:   A = C = the errors, B = the status
HD_ERROR_REGISTER:
    BIT 1,A
    LD B,A
    CALL NZ,HD_RESET_1
    IN A,[HD_ERROR_PORT]
    LD C,A
    RET

;; Resets the hard disk controller, then enables it with wait states.
HD_RESET:
    XOR A
    OUT [HD_CONTROL_PORT],A
HD_RESET_1:
    LD A,$10
    OUT [HD_CONTROL_PORT],A
    LD A,$0C
    OUT [HD_CONTROL_PORT],A
    RET

;; Waits while the hard disk controller is busy or its heads move.
;; Out:   A = the status, zero = set when there was no error
HD_WAIT:
    IN A,[HD_STATUS_PORT]
    BIT 7,A
    JR NZ,HD_WAIT
    BIT 4,A
    JR Z,HD_WAIT
    BIT 0,A
    RET

;; The floppy disk.
FLOPPY_IO:
    LD A,$D0
    OUT [FDC_STATUS_PORT],A
    CALL DELAY
    LD A,$81
    OUT [DRIVE_SELECT_PORT],A
    LD A,C
    OUT [FDC_SECTOR_PORT],A
    LD A,B
    CP $05
    JR NC,RESTORE_DRIVES

;; Restores drive 0 to track 0.
FLOPPY_RESTORE:
    LD A,$0C
    OUT [FDC_STATUS_PORT],A
    CALL FLOPPY_WAIT
    LD B,A
    AND $DF
    CP $81
    JR NZ,FLOPPY_SEEK_READ_2
    LD A,C
    AND $9E
    LD D,$06
    JR Z,FLOPPY_RESTORE_1
    LD D,$04
    CP $06
    JR Z,FLOPPY_RESTORE_1
    LD D,$07
FLOPPY_RESTORE_1:
    LD A,D
    OR A
    RET

;; Function $32: restores drives 1, 2 and 3.
RESTORE_DRIVES:
    CP $32
    JR NZ,FLOPPY_SEEK_READ
    LD B,$03
    LD D,$02
RESTORE_DRIVES_1:
    LD A,$D0
    OUT [FDC_STATUS_PORT],A
    CALL DELAY
    LD A,D
    OUT [DRIVE_SELECT_PORT],A
    RLCA
    LD D,A
    IN A,[FDC_STATUS_PORT]
    AND $20
    JR Z,RESTORE_DRIVES_3
    XOR A
    OUT [FDC_STATUS_PORT],A
    CALL DELAY_1
RESTORE_DRIVES_2:
    IN A,[FDC_STATUS_PORT]
    XOR $01
    AND $05
    JR Z,RESTORE_DRIVES_2
RESTORE_DRIVES_3:
    DJNZ RESTORE_DRIVES_1
    RET

;; Seeks, then reads a sector.
FLOPPY_SEEK_READ:
    LD A,E
    OUT [FDC_DATA_PORT],A
    LD A,$1C
    OUT [FDC_STATUS_PORT],A
    CALL FLOPPY_WAIT
    LD D,A
    AND $98
    JR NZ,FLOPPY_SEEK_READ_1
    LD A,B
    CP $0C
    JR Z,FLOPPY_READ
FLOPPY_SEEK_READ_1:
    LD B,D
FLOPPY_SEEK_READ_2:
    LD D,$09
    JR FLOPPY_ERROR_1

;; Turns the floppy disk controller's status into an error code.
FLOPPY_ERROR:
    LD D,$0B
    BIT 2,B
    JR NZ,FLOPPY_RESTORE_1
    LD D,$0C
FLOPPY_ERROR_1:
    BIT 4,B
    JR NZ,FLOPPY_RESTORE_1
    LD D,$08
    BIT 3,B
    JR NZ,FLOPPY_RESTORE_1
    LD D,$04
    BIT 7,B
    JR NZ,FLOPPY_RESTORE_1
    XOR A
    RET

;; Reads a sector into HL: INI takes each byte, with the drive select's wait holding the Z80, until the
;; controller's NMI ends the read at FLOPPY_READ_END.
FLOPPY_READ:
    LD A,[FIRST_SECTOR]
    LD B,A
    LD D,$81
    LD C,$86
    IN A,[FDC_SECTOR_PORT]
    CP $12
    JR C,FLOPPY_READ_1
    SUB $12
    SET 4,D
    SET 3,C
FLOPPY_READ_1:
    ADD A,B
    OUT [FDC_SECTOR_PORT],A
    LD A,D
    OUT [DRIVE_SELECT_PORT],A
    LD B,$00
    LD E,B
    LD A,C
    LD C,$F3
    OUT [FDC_STATUS_PORT],A
    LD A,$80
    OUT [NMI_PORT],A
    CALL DELAY_1
    LD A,D
    OUT [DRIVE_SELECT_PORT],A
FLOPPY_READ_2:
    IN A,[FDC_STATUS_PORT]
    BIT 1,A
    JP NZ,FLOPPY_READ_3
    RLCA
    JP NC,FLOPPY_READ_2
    JR FLOPPY_READ_END_1
FLOPPY_READ_3:
    INI
    LD A,D
    OR $40
FLOPPY_READ_4:
    OUT [DRIVE_SELECT_PORT],A
    INI
    JR NZ,FLOPPY_READ_4
    INC E
    JP FLOPPY_READ_4

;; The NMI at the end of a sector read: returns past the read loop with the status.
FLOPPY_READ_END:
    POP IY
    XOR A
    OUT [NMI_PORT],A
FLOPPY_READ_END_1:
    IN A,[FDC_STATUS_PORT]
    LD B,A
    LD C,B
    CALL FLOPPY_READ_END_2
    JR FLOPPY_ERROR
FLOPPY_READ_END_2:
    RETN

;; Waits 256 passes of a 13 T-state loop; DELAY_1 waits 18.
;; Keeps: BC
DELAY:
    PUSH BC
    LD B,$00
    JR DELAY_2
DELAY_1:
    PUSH BC
    LD B,$12
DELAY_2:
    DJNZ DELAY_2
    POP BC
    RET

;; Waits for the floppy disk controller to finish a command, or for the drive to be not ready.
;; Out:   A = the status
FLOPPY_WAIT:
    CALL DELAY_1
FLOPPY_WAIT_1:
    IN A,[FDC_STATUS_PORT]
    BIT 0,A
    RET Z
    BIT 7,A
    RET NZ
    LD C,A
    JR FLOPPY_WAIT_1

;; Loads the ROM image MODEL%/III from floppy drive 0: finds the directory from the boot sector, searches it for the
;; file and loads it into the RAM under the boot ROM.
LOAD_IMAGE:
    LD A,[RESTORE_ERROR]
    OR A
    JR NZ,NEXT_DIRECTORY_SECTOR_1
    LD A,$01
    LD E,$00
    CALL READ_SECTOR
    JR NZ,NEXT_DIRECTORY_SECTOR_1
    LD A,E
    CP $01
    JR NZ,LOAD_IMAGE_1
    LD A,[SECTOR_BUFFER]
    OR A
    JR Z,LOAD_IMAGE_2
    CP $FE
LOAD_IMAGE_1:
    LD A,$00
    RET NZ
LOAD_IMAGE_2:
    LD A,C
    AND $20
    LD C,$01
    LD B,$03
    LD HL,[SECTOR_BUFFER + 1]
    LD A,L
    JR NZ,LOAD_IMAGE_3
    LD A,H
    DEC C
    LD B,$06
LOAD_IMAGE_3:
    LD [DIR_CYLINDER],A
    LD E,A
    LD A,B
    LD [GRANULE_SECTORS],A
    LD A,C
    LD [FIRST_SECTOR],A
    LD A,[FIRST_SECTOR]
    OR A
    JR NZ,LOAD_IMAGE_4
    XOR A
    CALL READ_SECTOR
    JR NZ,NEXT_DIRECTORY_SECTOR_1
    LD A,[SECTOR_BUFFER + $CD]
    AND $20
    LD A,$01
    JR Z,LOAD_IMAGE_4
    INC A
LOAD_IMAGE_4:
    LD [SIDES],A
    LD A,$02
    LD [NEXT_SECTOR],A

;; Reads the next directory sector.
NEXT_DIRECTORY_SECTOR:
    LD HL,[DIR_CYLINDER]
    LD E,L
    LD A,H
    CALL READ_SECTOR
    LD A,$00
    JR Z,SEARCH_DIRECTORY
NEXT_DIRECTORY_SECTOR_1:
    CP $04
    JR NZ,NEXT_DIRECTORY_SECTOR_2
    LD A,$0A
    OR A
NEXT_DIRECTORY_SECTOR_2:
    RET

;; Searches a directory sector for MODEL%/III.
SEARCH_DIRECTORY:
    LD IX,SECTOR_BUFFER
SEARCH_DIRECTORY_1:
    LD A,[IX+$00]
    BIT 7,A
    JR NZ,SEARCH_DIRECTORY_2
    BIT 4,A
    JR Z,SEARCH_DIRECTORY_2
    PUSH IX
    POP HL
    LD DE,$0005
    ADD HL,DE
    LD DE,IMAGE_NAME
    LD B,$08
    CALL COMPARE_NAMES
    JR NZ,SEARCH_DIRECTORY_2
    PUSH IX
    POP HL
    LD DE,$000D
    ADD HL,DE
    LD B,$03
    LD DE,$0063
    CALL COMPARE_NAMES
    JR Z,FOUND_IMAGE
SEARCH_DIRECTORY_2:
    PUSH IX
    POP HL
    LD DE,$0020
    ADD HL,DE
    LD A,[FIRST_SECTOR]
    OR A
    JR Z,SEARCH_DIRECTORY_3
    LD DE,$0010
    ADD HL,DE
SEARCH_DIRECTORY_3:
    PUSH HL
    POP IX
    LD A,L
    OR A
    JR Z,SEARCH_DIRECTORY_4
    CP $F0
    JR NZ,SEARCH_DIRECTORY_1
SEARCH_DIRECTORY_4:
    LD A,[NEXT_SECTOR]
    INC A
    LD [NEXT_SECTOR],A
    JR NEXT_DIRECTORY_SECTOR

;; Copies the file's directory entry to IMAGE_ENTRY and loads it.
FOUND_IMAGE:
    LD DE,IMAGE_ENTRY
    PUSH IX
    POP HL
    LD BC,$0030
    LDIR
    LD A,$FE
    LD [DE],A
    LD IX,IMAGE_ENTRY + 20

;; RST $28: loads a program file in load module format through RST $20.
;; Out:   HL = its transfer address
LOAD_FILE:
    LD E,$00
LOAD_FILE_1:
    RST $20
    RET NZ
    DEC A
    JR Z,LOAD_FILE_3
    DEC A
    JR Z,LOAD_FILE_5
    RST $20
    LD B,A
LOAD_FILE_2:
    RST $20
    RET NZ
    DJNZ LOAD_FILE_2
    JR LOAD_FILE_1
LOAD_FILE_3:
    RST $20
    RET NZ
    DEC A
    DEC A
    LD B,A
    CALL LOAD_FILE_6
    RET NZ
LOAD_FILE_4:
    RST $20
    RET NZ
    LD [HL],A
    INC HL
    DJNZ LOAD_FILE_4
    JR LOAD_FILE_1
LOAD_FILE_5:
    RST $20
    RET NZ
LOAD_FILE_6:
    RST $20
    RET NZ
    LD L,A
    RST $20
    RET NZ
    LD H,A
    RET

;; RST $20: the next byte of the file being loaded from floppy disk.
;; Out:   A = the byte
NEXT_FILE_BYTE:
    PUSH BC
    PUSH HL
    LD A,E
    OR A
    JR NZ,NEXT_FILE_BYTE_1
    CALL Z,NEXT_FILE_SECTOR
    JR NZ,NEXT_FILE_BYTE_2
    LD DE,SECTOR_BUFFER
NEXT_FILE_BYTE_1:
    XOR A
    LD A,[DE]
    INC DE
NEXT_FILE_BYTE_2:
    POP HL
    POP BC
    RET

;; Reads the file's next sector.
NEXT_FILE_SECTOR:
    LD HL,SECTORS_LEFT
    LD A,[HL]
    OR A
    JR NZ,NEXT_FILE_SECTOR_1
    CALL NEXT_EXTENT
    RET NZ
NEXT_FILE_SECTOR_1:
    DEC [HL]
    LD B,$12
    LD A,[SIDES]
    DEC A
    JR Z,NEXT_FILE_SECTOR_2
    LD B,$24
NEXT_FILE_SECTOR_2:
    LD A,[NEXT_SECTOR]
    CP B
    JR NZ,NEXT_FILE_SECTOR_3
    LD A,[FILE_CYLINDER]
    INC A
    LD [FILE_CYLINDER],A
    XOR A
NEXT_FILE_SECTOR_3:
    LD C,A
    INC A
    LD [NEXT_SECTOR],A
    LD A,[FILE_CYLINDER]
    LD E,A
    JR READ_SECTOR_1

;; Moves to the file's next extent.
NEXT_EXTENT:
    INC IX
    INC IX
    LD A,[IX+$00]
    LD B,A
    AND $FE
    CP $FE
    JR NZ,NEXT_EXTENT_1
    LD A,$02
    OR A
    RET
NEXT_EXTENT_1:
    LD A,B
    LD [FILE_CYLINDER],A
    LD A,[IX+$01]
    LD E,A
    AND $E0
    RLCA
    RLCA
    RLCA
    LD B,A
    LD A,[GRANULE_SECTORS]
    CALL MULTIPLY
    LD [NEXT_SECTOR],A
    LD A,E
    AND $1F
    LD B,A
    LD A,[FIRST_SECTOR]
    XOR $01
    ADD A,B
    LD B,A
    LD A,[GRANULE_SECTORS]
    CALL MULTIPLY
    LD [SECTORS_LEFT],A
    XOR A
    RET

;; Compares B bytes of a name with a pattern, in which % matches any character.
;; In:    DE = the pattern, HL = the name
;; Out:   zero = set when they match
COMPARE_NAMES:
    LD A,[DE]
    CP $25
    JR Z,COMPARE_NAMES_1
    CP [HL]
    RET NZ
COMPARE_NAMES_1:
    INC DE
    INC HL
    DJNZ COMPARE_NAMES
    RET

;; Multiplies A by B.
;; Out:   A = the product's low byte
MULTIPLY:
    LD C,A
    LD A,B
    OR A
    RET Z
    XOR A
MULTIPLY_1:
    ADD A,C
    DJNZ MULTIPLY_1
    RET

;; Reads a floppy sector into SECTOR_BUFFER.
READ_SECTOR:
    LD C,A
READ_SECTOR_1:
    LD HL,SECTOR_BUFFER
    LD B,$0C
    LD A,$01
    RST $08
    RET

;; An ARCNET board answered: shows that it cannot boot from it.
ARCNET_FOUND:
    LD A,$01
    JP SHOW_ERROR

;; Boots over the RS-232 port (right SHIFT at reset): finds the baud rate, then loads a program file through RST
;; $20 from the port.
RS232_BOOT:
    LD A,$04
    LD [BOOT_TYPE],A
RS232_BOOT_1:
    LD A,$64
    OUT [RS232_STATUS_PORT],A
    OR A
    LD HL,NOT_READY_LIST
    RST $18
RS232_BOOT_2:
    IN A,[RS232_RESET_PORT]
    AND $20
    JR NZ,RS232_BOOT_2
    LD DE,$0000
    LD HL,BLANK_TEXT
    RST $10
    LD HL,RS232_RECEIVE
    LD [RST20_VECTOR + 1],HL
    LD HL,BAUD_CODE

;; Finds the baud rate of the sender's characters.
FIND_BAUD:
    LD A,$FF
FIND_BAUD_1:
    LD [HL],A
    OUT [RS232_BAUD_PORT],A
    OUT [RS232_RESET_PORT],A
    LD B,$0A
FIND_BAUD_2:
    RST $20
    JR NZ,FIND_BAUD_3
    CP $55
    JR Z,FIND_BAUD_4
FIND_BAUD_3:
    DJNZ FIND_BAUD_2
    LD A,[HL]
    SUB $11
    JR NC,FIND_BAUD_1
    JR FIND_BAUD
FIND_BAUD_4:
    LD B,$0A
FIND_BAUD_5:
    RST $20
    JR NZ,FIND_BAUD
    CP $55
    JR NZ,FIND_BAUD
    DJNZ FIND_BAUD_5
    LD A,[HL]
    AND $0F
    CALL CODE_LETTER
    LD HL,FOUND_BAUD_LIST
    RST $18
    LD HL,FOUND_BAUD_TEXT
    CALL RS232_SEND_TEXT
    IN A,[RS232_DATA_PORT]
FIND_BAUD_6:
    RST $20
    JR NZ,RS232_ERROR
    CP $FF
    JR NZ,FIND_BAUD_6
    LD DE,$0244
    LD HL,$04BC
    PUSH HL
    RST $10
    POP HL
    CALL RS232_SEND_TEXT
    RST $28
    JR NZ,RS232_ERROR
    JP [HL]

;; Shows a receive error and starts again.
RS232_ERROR:
    RRCA
    RRCA
    RRCA
    CALL CODE_LETTER
    CALL CLEAR_SCREEN
    PUSH BC
    LD HL,RECEIVE_ERROR_LIST
    RST $18
    LD HL,TX_SEEK_ERROR + 5
    CALL RS232_SEND_TEXT
    POP BC
    RST $30
    JP RS232_BOOT_1

;; Receives a byte from the RS-232 port: RST $20 during an RS-232 boot.
;; Out:   A = the byte
RS232_RECEIVE:
    IN A,[RS232_STATUS_PORT]
    BIT 7,A
    JR Z,RS232_RECEIVE
    AND $38
    RET NZ
    IN A,[RS232_DATA_PORT]
    RET

;; Sends a text, ended by a zero byte, over the RS-232 port.
;; In:    HL = the text
RS232_SEND_TEXT:
    IN A,[RS232_STATUS_PORT]
    AND $40
    JR Z,RS232_SEND_TEXT
    LD A,[HL]
    OR A
    RET Z
    OUT [RS232_DATA_PORT],A
    INC HL
    JR RS232_SEND_TEXT

;; Makes a code 0-15 the letter A-P in ERROR_LETTER, a one-letter text for a message list.
;; Out:   zero = clear
CODE_LETTER:
    ADD A,$41
    LD [ERROR_LETTER],A
    RET

;; Ended by the zero that starts NOT_READY_LIST.
FOUND_BAUD_TEXT:
    .byte "Found Baud Rate "

;; The RS-232 boot's message lists.
NOT_READY_LIST:
    .word $0000, TX_WAS_NOT + 4, TX_WHEN_YOU_ARE_READY + 13, END_LIST
;; Three spaces, to erase the "Not" while the port is ready.
BLANK_TEXT:
    .byte "   ", $00
FOUND_BAUD_LIST:
    .word $0184, FOUND_BAUD_TEXT, ERROR_LETTER, END_LIST
RECEIVE_ERROR_LIST:
    .word $03C4, TX_SEEK_ERROR + 5, TX_SPACE, ERROR_LETTER, END_LIST

;; The RAM test (the period key at reset), which runs until RESET with its stack in video RAM.
RAM_TEST:
    LD SP,VIDEO + $3FE
    LD IY,VIDEO + 128
    LD A,$08
    OUT [OPTIONS_PORT],A
    XOR A
    OUT [MEMORY_MAP_PORT],A
    LD IX,RAM_TEST_TITLE

;; Fills the screen with spaces and goes on at IX.
CLEAR_AND_GO:
    LD A,$20
    LD DE,VIDEO
    LD [DE],A
    LD H,D
    LD L,E
    LD BC,$03FF
    INC DE
    LDIR
    JP [IX]

;; Shows the title and waits for ENTER.
RAM_TEST_TITLE:
    LD HL,RAM_TEST_TEXTS
    LD DE,VIDEO
    CALL SHOW_TEXT
    LD HL,RAM_ENTER_TEXT
    LD DE,VIDEO + 64
    CALL SHOW_TEXT
    LD HL,RAM_ERRORS_TEXT
    LD DE,$00C0                     ; the screen's fourth line: SHOW_TEXT makes it a video RAM address
    CALL SHOW_TEXT
RAM_TEST_TITLE_1:
    LD A,[KEYBOARD_ROW6]
    CP $01
    JR NZ,RAM_TEST_TITLE_1
    LD IX,RAM_TEST_HEADINGS
    JP CLEAR_AND_GO

;; Shows the column headings.
RAM_TEST_HEADINGS:
    LD HL,RAM_HEADINGS_TEXT
    LD DE,VIDEO + 128
    CALL SHOW_TEXT
    LD HL,RAM_STACK_TEXT
    LD DE,$03F4                     ; just below the stack, at the end of video RAM
    CALL SHOW_TEXT

;; Round 1: writes and reads $55 through RAM.
RAM_ROUND1:
    LD HL,RAM_PATTERN_TEXT
    LD DE,VIDEO + 64
    CALL SHOW_TEXT
    LD HL,RST08_VECTOR
    LD D,H
    LD E,L
    LD BC,$BFFF
    LD A,$55
    LD [DE],A
    INC DE
    LDIR
    LD HL,RST08_VECTOR
    LD BC,$BFFF
RAM_ROUND1_1:
    LD A,$55
    LD E,[HL]
    CP E
    LD IX,RAM_ROUND1_2
    JP NZ,RAM_ERROR
RAM_ROUND1_2:
    DEC BC
    INC HL
    LD A,C
    OR B
    JR NZ,RAM_ROUND1_1

;; Round 2: $AA.
RAM_ROUND2:
    LD HL,RAM_AA_TEXT
    LD DE,VIDEO + 80
    CALL SHOW_TEXT
    LD HL,RST08_VECTOR
    LD D,H
    LD E,L
    LD BC,$BFFF
    LD A,$AA
    LD [DE],A
    INC DE
    LDIR
    LD HL,RST08_VECTOR
    LD BC,$BFFF
RAM_ROUND2_1:
    LD A,$AA
    LD E,[HL]
    CP E
    LD IX,RAM_ROUND2_2
    JP NZ,RAM_ERROR
RAM_ROUND2_2:
    DEC BC
    INC HL
    LD A,C
    OR B
    JP NZ,RAM_ROUND2_1

;; Round 3: each byte's own address.
RAM_ROUND3:
    LD D,$00
RAM_ROUND3_1:
    LD B,D
    LD HL,RAM_ADDRESS_TEXT
    LD DE,VIDEO + 64
    CALL SHOW_TEXT
    LD H,D
    LD L,E
    LD D,B
    INC HL
    RRA
    RRA
    RRA
    RRA
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [HL],A
    INC HL
    LD A,D
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [HL],A
    LD HL,RST08_VECTOR
    LD BC,$BFFF
RAM_ROUND3_2:
    LD A,D
    XOR L
    XOR H
    LD [HL],A
    INC HL
    DEC BC
    LD A,C
    OR B
    JR NZ,RAM_ROUND3_2
    LD A,D
    AND $03
    JR NZ,RAM_ROUND3_3
    LD A,$40
    OUT [DRIVE_SELECT_PORT],A
RAM_ROUND3_3:
    LD HL,RST08_VECTOR
    LD BC,$BFFF
RAM_ROUND3_4:
    LD A,D
    XOR L
    XOR H
    LD E,[HL]
    CP E
    LD IX,RAM_ROUND3_5
    JR NZ,RAM_ERROR
RAM_ROUND3_5:
    INC HL
    DEC BC
    LD A,C
    OR B
    JR NZ,RAM_ROUND3_4
    INC D
    JR NZ,RAM_ROUND3_1
    JP RAM_ROUND1

;; Shows a failing address and its bits.
RAM_ERROR:
    EX AF,AF'
    EXX
    LD BC,$0040
    ADD IY,BC
    LD BC,$C040
    ADD IY,BC
    JR NC,RAM_ERROR_1
    LD IY,$0000
RAM_ERROR_1:
    LD BC,VIDEO + $3C0
    ADD IY,BC
    EXX
    LD A,H
    RRA
    RRA
    RRA
    RRA
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$01],A
    LD A,H
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$02],A
    LD A,L
    RRA
    RRA
    RRA
    RRA
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$03],A
    LD A,L
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$04],A
    LD A,[HL]
    LD I,A
    RRA
    RRA
    RRA
    RRA
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$0A],A
    LD A,I
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$0B],A
    LD A,E
    RRA
    RRA
    RRA
    RRA
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$11],A
    LD A,E
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$12],A
    EX AF,AF'
    LD I,A
    RRA
    RRA
    RRA
    RRA
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$17],A
    LD A,I
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$18],A
    LD A,D
    RRA
    RRA
    RRA
    RRA
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$20],A
    LD A,D
    AND $0F
    ADD A,$90
    DAA
    ADC A,$40
    DAA
    LD [IY+$21],A
    JP [IX]

;; The RAM test's texts.
RAM_TEST_TEXTS:
    .byte "Dynamic RAM Test", $00
RAM_ENTER_TEXT:
    .byte "Press <Enter> To Begin And RESET To Exit", $00
RAM_ERRORS_TEXT:
    .byte "Any Errors Detected Will Be Displayed", $00
RAM_HEADINGS_TEXT:
    .byte "Address  Retry  Read  Written  Mask", $00
RAM_PATTERN_TEXT:
    .byte "Test Pattern Is 55h", $00
;; Written over the 55h for round 2.
RAM_AA_TEXT:
    .byte "AAh", $00
;; Round 3's title, its pattern after it.
RAM_ADDRESS_TEXT:
    .byte "Modified Address Test  ld (hl),mask", $00
;; Shown where the stack is, as video RAM holds it.
RAM_STACK_TEXT:
    .byte "Stack", $00

; Not used.
    .res 83, $00

COPYRIGHT:
    .byte "(c) 1983, Tandy Corp."
.assert * = $1000, "The boot ROM is 4K."
