;; TRS-80 MODEL II BOOT ROM ($0000-$07FF)
;;
;; The Model II's, 12's and 16's only ROM: 2K at $0000 that tests the machine and loads a disk's boot code into the
;; RAM under it. It checks the CPU, the RAM from $1000 up and (before version 5) its own checksum, then boots from
;; a hard disk when one is ready and from floppy drive 0 otherwise. A floppy disk boots by reading track 0 to
;; $0E00-$1AFF, checking for BOOT at $1000 and DIAG at $1400, calling $1404 and jumping to $1004. A hard disk
;; boots by reading sectors to $0000 up until one starts /* END BOOT */, and jumping to it. A failure shows
;; BOOT ERROR and two letters in the middle of the screen; ESC or BREAK during a hard disk boot boots from the
;; floppy instead.
;;
;; VERSION picks the ROM, by the number in its last bytes:
;;   1 8043216 (MAME's c8ff): the first, booting only from floppies;
;;   2 8047316 (2bff): adds the hard disk boot;
;;   3 cpu_2119 (2119): seeks the disks away from track 0 before restoring them; FILL_11BE = 1 builds MAME's
;;     cpu_11be (11be), the same ROM with seven stray bytes in its unused space;
;;   5 u54 (9733): also quiets the DMA, CTC, PIO and SIO, checks for the hard disk board by its registers, and
;;     drops the checksum.
;;
;; The labels are our own, named after what each routine does, as no source is known.
;;
;; Maintained by hand. Trs80RomSourceTests check that each version assembles byte-identically to its ROM.

.cpu Z80

.ifndef VERSION
VERSION = 5
.endif
.ifndef FILL_11BE
FILL_11BE = 0
.endif
.assert VERSION = 1 || VERSION = 2 || VERSION = 3 || VERSION = 5, "VERSION is 1, 2, 3 or 5."
.assert FILL_11BE = 0 || VERSION = 3, "FILL_11BE is a version 3 ROM."

;; Ports.
HD_CONTROL_PORT = $C1               ;; the hard disk board: bit 4 resets it, bits 0-3 enable it
HD_BOARD_PORT = $C2                 ;; versions 2 and 3 take zero in bits 0-3 as no hard disk
HD_DATA_PORT = $C8                  ;; the WD1010 hard disk controller's registers
HD_ERROR_PORT = $C9
HD_COUNT_PORT = $CA
HD_SECTOR_PORT = $CB
HD_CYLINDER_LOW_PORT = $CC
HD_CYLINDER_HIGH_PORT = $CD
HD_DRIVE_HEAD_PORT = $CE            ;; bits 5-6 the sector size, 3-4 the drive, 0-2 the head
HD_STATUS_PORT = $CF                ;; the status, and the command when written
PIO_A_CONTROL_PORT = $E2
PIO_B_CONTROL_PORT = $E3
FDC_STATUS_PORT = $E4               ;; the FD1791's status, and its command when written
FDC_TRACK_PORT = $E5
FDC_SECTOR_PORT = $E6
FDC_DATA_PORT = $E7
DRIVE_SELECT_PORT = $EF             ;; bits 0-3 the drives, active low; bit 6 clear for side 1; bit 7 double density
CTC0_PORT = $F0
CTC1_PORT = $F1
CTC2_PORT = $F2
CTC3_PORT = $F3
SIO_A_CONTROL_PORT = $F6
SIO_B_CONTROL_PORT = $F7
DMA_PORT = $F8
KEYBOARD_PORT = $FC                 ;; read: the key; write: selects a 6845 register
CRTC_ADDRESS_PORT = $FC
CRTC_DATA_PORT = $FD
CONTROL_PORT = $FF                  ;; write: bit 7 maps video RAM at $F800; read: bit 7 set when a key is ready

;; Hard disk commands.
HD_RESTORE = $1F                    ;; to cylinder 0, stepping at the slowest rate
HD_READ = $20

;; Floppy disk controller commands.
FDC_READ = $80                      ;; one sector
FDC_FORCE_INTERRUPT = $D0           ;; stops a command
FDC_INTERRUPT_NOW = $D8             ;; stops a command and interrupts

;; Drive select: drive 0, side 0, single density; and no drive.
DRIVE_0 = $4E
NO_DRIVE = $4F

;; Keys that skip a hard disk boot.
ESC = $1B
BREAK = $03

;; Memory.
VIDEO = $F800                       ;; 80 columns by 24 lines, when CONTROL_PORT maps it
VIDEO_END = $10000
MESSAGE_SCREEN = VIDEO + 11 * 80 + 30 ;; where messages show, in the middle of the screen
BOOT_LOAD = $0E00                   ;; where a floppy's track 0 is read: 26 sectors of 128 bytes
BOOT_SIGNATURE = $1000              ;; sector 5: BOOT
BOOT_ENTRY = BOOT_SIGNATURE + 4
DIAG_SIGNATURE = $1400              ;; sector 13: DIAG
DIAG_ENTRY = DIAG_SIGNATURE + 4
TEST_RAM_START = $1000              ;; the RAM test covers $1000-$7FFF
TEST_RAM_END = $8000
INITIAL_STACK = $2800
BOOT_STACK = $2000
SECTORS = 26                        ;; on a floppy's track 0
TRIES = 40                          ;; reads of a floppy sector before giving up

.org $0000

;; Power-up and reset: maps video RAM in.
RESET:
    DI
.if VERSION >= 2
    LD SP,INITIAL_STACK
.endif
    LD A,$80
    OUT [CONTROL_PORT],A
.if VERSION = 1
    LD SP,BOOT_STACK
.endif

.if VERSION = 5
;; Stops the DMA controller and resets the CTC's channels, the PIO's interrupts and the SIO's channels.
RESET_DEVICES:
    LD A,$83                        ; disable
    OUT [DMA_PORT],A
    LD A,$C3                        ; reset
    OUT [DMA_PORT],A
    OUT [DMA_PORT],A
    OUT [DMA_PORT],A
    OUT [DMA_PORT],A
    OUT [DMA_PORT],A
    LD A,$03                        ; the CTC's reset, and the PIO's interrupts off
    OUT [CTC0_PORT],A
    OUT [CTC1_PORT],A
    OUT [CTC2_PORT],A
    OUT [CTC3_PORT],A
    OUT [PIO_B_CONTROL_PORT],A
    OUT [PIO_A_CONTROL_PORT],A
    LD A,$18                        ; channel reset
    OUT [SIO_A_CONTROL_PORT],A
    OUT [SIO_B_CONTROL_PORT],A
.endif

;; Fills the screen with inverse spaces, which shows white once the display starts.
TEST_SCREEN:
    LD BC,VIDEO_END - VIDEO - 1
    LD DE,VIDEO_END - 2
    LD HL,VIDEO_END - 1
    LD [HL],' ' | $80
    LDDR

;; Writes the 6845's registers from CRTC_TABLE, R15 first.
SET_CRTC:
    LD BC,15 << 8 | CRTC_ADDRESS_PORT
    LD HL,CRTC_TABLE + 15
SET_CRTC_1:
    LD A,[HL]
    OUT [C],B
    OUT [CRTC_DATA_PORT],A
    DEC HL
    DEC B
    JP P,SET_CRTC_1

.if VERSION = 1
;; Checks that the ROM's bytes before CHECKSUM_BYTE add up to its complement.
CHECKSUM:
    LD HL,$0000
    LD DE,CHECKSUM_BYTE
    XOR A
CHECKSUM_1:
    LD B,[HL]
    ADD A,B
    INC HL
    DEC DE
    LD C,A
    LD A,D
    OR E
    LD A,C
    JR NZ,CHECKSUM_1
    CPL
    CP [HL]
    LD HL,[CODE_CK]
    JP NZ,SHOW_ERROR
.elseif VERSION <= 3
;; Checks that the ROM's bytes add up to zero.
CHECKSUM:
    XOR A
    LD BC,ROM_END
    LD HL,$0000
CHECKSUM_1:
    ADD A,[HL]
    LD D,A
    INC HL
    DEC BC
    LD A,B
    OR C
    LD A,D
    JR NZ,CHECKSUM_1
    OR A
    JP NZ,ERROR_CK
.endif

;; Passes $AA through the registers and checks that it comes out unchanged.
TEST_CPU:
    LD A,$55
    CPL
    OR A
    AND A
.if VERSION = 1
    EX AF,AF'
    EX AF,AF'
.endif
    LD B,A
    LD C,B
    LD D,C
    LD E,D
    LD H,E
    LD L,H
.if VERSION = 1
    EX DE,HL
    EXX
    EXX
    INC L
    DEC L
    CP L
    LD HL,[CODE_Z8]
    JP NZ,SHOW_ERROR
.else
    INC L
    DEC L
    EX DE,HL
    EX AF,AF'
    LD A,E
    EXX                             ; on through the second register set and I
    LD B,A
    LD C,B
    LD D,C
    LD E,D
    LD H,E
    LD L,H
    LD A,L
    LD I,A
    LD A,I
    LD L,A
    EX AF,AF'
    CP L
    JP NZ,ERROR_Z8
.endif

;; Checks that each byte of RAM from TEST_RAM_START up holds its complement, leaving it as it was.
TEST_RAM:
.if VERSION = 1
    LD HL,TEST_RAM_START
TEST_RAM_1:
    LD A,[HL]
    CPL
    LD [HL],A
    CP [HL]
    CPL
    LD [HL],A
    JP NZ,ERROR_MF
    INC HL
    LD A,H
    CP >TEST_RAM_END
    JR NZ,TEST_RAM_1
.else
    LD BC,TEST_RAM_END - TEST_RAM_START
    LD HL,TEST_RAM_START
    LD D,H
    LD E,L
TEST_RAM_1:
    LD A,[DE]
    CPL
    LD [DE],A
    CP [HL]
    CPL
    LD [HL],A
    JP NZ,ERROR_MF
    LDI                             ; steps HL and DE together, and counts BC down
    JP PE,TEST_RAM_1
.endif

;; Waits a while for the drives, reading and dropping any keys.
SETTLE:
    LD D,200
SETTLE_1:
    IN A,[CONTROL_PORT]
    BIT 7,A
    JR Z,SETTLE_2
    IN A,[KEYBOARD_PORT]
SETTLE_2:
    LD BC,$0080
    CALL DELAY
    DEC D
    JR NZ,SETTLE_1

.if VERSION = 5
;; Seeks each floppy drive, 3 down to 0, to track 5, so that the restore that boots one checks its stepping.
SEEK_FLOPPIES:
    LD B,4
    LD DE,$40 << 8 | $F7            ; D: side 0, single density; E: drive 3's select bit low
SEEK_FLOPPIES_1:
    PUSH BC
    PUSH DE
    LD A,E
    AND $0F
    OR D
    OUT [DRIVE_SELECT_PORT],A
    CALL RESET_FDC
    XOR A
    OUT [FDC_TRACK_PORT],A
    LD A,5
    OUT [FDC_DATA_PORT],A
    LD A,$13                        ; seek
    OUT [FDC_STATUS_PORT],A
    CALL WAIT_FDC
    POP DE
    RRC E                           ; the next drive down
    POP BC
    DJNZ SEEK_FLOPPIES_1
.endif

.if VERSION >= 2
;; Boots from the hard disk, when there is one, waiting for it to be ready. ESC or BREAK boots from the floppy.
HARD_DISK_BOOT:
.if VERSION = 5
    LD A,$0F                        ; no drive
    OUT [DRIVE_SELECT_PORT],A
.endif
    XOR A
    OUT [HD_CONTROL_PORT],A
    LD A,$10                        ; reset the board
    OUT [HD_CONTROL_PORT],A
.if VERSION = 2
    LD A,$0C
.elseif VERSION = 3
    LD A,$0F
.else
    LD A,$0E
.endif
    OUT [HD_CONTROL_PORT],A
.if VERSION = 5
    LD A,$AA                        ; no hard disk when the sector count does not read back
    OUT [HD_COUNT_PORT],A
    IN A,[HD_COUNT_PORT]
    CP $AA
    JP NZ,FLOPPY_BOOT
    LD D,30
    LD BC,$0000
HARD_DISK_BOOT_1:
    IN A,[HD_STATUS_PORT]
    BIT 6,A                         ; ready
    JR NZ,HARD_DISK_BOOT_2
    CALL DELAY
    DEC D
    JR NZ,HARD_DISK_BOOT_1
HARD_DISK_BOOT_2:
    LD A,$AA
    OUT [HD_COUNT_PORT],A
    IN A,[HD_COUNT_PORT]
    CP $AA
    JP NZ,HARD_DISK_TIMEOUT
.else
    IN A,[HD_BOARD_PORT]
    AND $0F
    JP Z,FLOPPY_BOOT
    LD D,21
HARD_DISK_BOOT_1:
    CALL DELAY
    IN A,[HD_STATUS_PORT]
    BIT 6,A                         ; ready
    JR NZ,HARD_DISK_RESTORE
    CALL CHECK_BREAK
    JP Z,FLOPPY_BOOT
    DEC D
    JR NZ,HARD_DISK_BOOT_1
    JR HARD_DISK_TIMEOUT
.endif

.if VERSION = 5
;; Restores each ready hard disk, 3 down to 0, and seeks it to cylinder 5, then restores drive 0.
HARD_DISK_RESTORE:
    LD BC,4 << 8 | $38              ; C: drive 3, 512-byte sectors
HARD_DISK_RESTORE_1:
    LD A,C
    OUT [HD_DRIVE_HEAD_PORT],A
    IN A,[HD_STATUS_PORT]
    BIT 6,A
    JR Z,HARD_DISK_RESTORE_2
    LD A,HD_RESTORE
    OUT [HD_STATUS_PORT],A
    CALL HARD_DISK_WAIT
    XOR A
    OUT [HD_CYLINDER_HIGH_PORT],A
    LD A,5
    OUT [HD_CYLINDER_LOW_PORT],A
    LD A,$73                        ; seek
    OUT [HD_STATUS_PORT],A
    CALL HARD_DISK_WAIT
HARD_DISK_RESTORE_2:
    LD A,C
    SUB $08                         ; the next drive down
    LD C,A
    DJNZ HARD_DISK_RESTORE_1

;; Restores drive 0, trying 30 times. A failure is error H0.
HARD_DISK_RESTORE_0:
    CALL CHECK_BREAK
    JP Z,FLOPPY_BOOT
    LD A,HD_RESTORE
    OUT [HD_STATUS_PORT],A
    LD D,30
HARD_DISK_RESTORE_0_1:
    CALL HARD_DISK_WAIT
    JR Z,HARD_DISK_LOAD
    CALL CHECK_BREAK
    JP Z,FLOPPY_BOOT
    CALL DELAY
    DEC D
    JR NZ,HARD_DISK_RESTORE_0_1
    LD A,$01
    OR A
    JR HARD_DISK_ERROR_1
.else
;; Restores drive 0, from cylinder 5 in version 3. A failure is error H0.
HARD_DISK_RESTORE:
    LD A,$20                        ; drive 0, 512-byte sectors
    OUT [HD_DRIVE_HEAD_PORT],A
.if VERSION = 3
    XOR A
    OUT [HD_CYLINDER_HIGH_PORT],A
    LD A,5
    OUT [HD_CYLINDER_LOW_PORT],A
    LD A,$7F                        ; seek
    OUT [HD_STATUS_PORT],A
    CALL HARD_DISK_WAIT
.endif
    LD A,HD_RESTORE
    OUT [HD_STATUS_PORT],A
    CALL HARD_DISK_WAIT
    JR NZ,HARD_DISK_ERROR_1
.endif

;; Reads the hard disk's sectors from sector 1 into RAM from $0000 up, until one starts with END_BOOT_TEXT, and
;; jumps to that one.
HARD_DISK_LOAD:
.if VERSION = 5
    XOR A
    OUT [HD_CYLINDER_LOW_PORT],A
    OUT [HD_CYLINDER_HIGH_PORT],A
.endif
    LD HL,$0000
    LD BC,1 << 8 | HD_SECTOR_PORT
HARD_DISK_LOAD_1:
    LD D,H
    LD E,L
    OUT [C],B
    LD A,HD_READ
    OUT [HD_STATUS_PORT],A
    CALL HARD_DISK_WAIT
    JR NZ,HARD_DISK_ERROR
HARD_DISK_LOAD_2:
    IN A,[HD_STATUS_PORT]
    BIT 3,A                         ; data ready
    JR Z,HARD_DISK_LOAD_2
    CALL CHECK_BREAK
    JR Z,FLOPPY_BOOT
    INC B
    PUSH BC
    LD A,2
    LD BC,HD_DATA_PORT              ; 256 bytes, twice
.if VERSION = 2
HARD_DISK_LOAD_3:
    INIR
    DEC A
    JR NZ,HARD_DISK_LOAD_3
.else
    INIR
    INIR
.endif
    PUSH HL
    LD HL,END_BOOT_TEXT
    LD B,BOOT_ERROR_TEXT - END_BOOT_TEXT
    CALL COMPARE
    POP HL
    POP BC
    JR NZ,HARD_DISK_LOAD_1
    LD BC,$0000
    CALL DELAY
    CALL CHECK_BREAK
    JR Z,FLOPPY_BOOT
    XOR A
    OUT [HD_CONTROL_PORT],A
    EX DE,HL
    JP [HL]

;; The hard disk was not ready: error HT.
HARD_DISK_TIMEOUT:
    LD E,'T'
    JR SHOW_HARD_DISK_ERROR

;; Names a hard disk error by the first bit set in the WD1010's error register: HC bit 6 (a CRC error), HI bit 5,
;; HN bit 4 (the sector not found), HA bit 2 (an aborted command), H0 bit 1 (track 0 not found), HM bit 0 (no
;; data mark), and HD otherwise.
;; In:    A = the error register
HARD_DISK_ERROR:
    BIT 6,A
    LD E,'C'
    JR NZ,SHOW_HARD_DISK_ERROR
    BIT 5,A
    LD E,'I'
    JR NZ,SHOW_HARD_DISK_ERROR
    BIT 4,A
    LD E,'N'
    JR NZ,SHOW_HARD_DISK_ERROR
    BIT 2,A
    LD E,'A'
    JR NZ,SHOW_HARD_DISK_ERROR
    BIT 1,A
HARD_DISK_ERROR_1:
    LD E,'0'
    JR NZ,SHOW_HARD_DISK_ERROR
    BIT 0,A
    LD E,'M'
    JR NZ,SHOW_HARD_DISK_ERROR
    LD E,'D'

;; Shows the hard disk error H and E, and waits for ESC or BREAK to boot from the floppy.
SHOW_HARD_DISK_ERROR:
    LD D,'H'
    LD HL,MESSAGE_SCREEN + 12
    LD [HL],D
    INC HL
    LD [HL],E
    INC HL
    LD [HL],' '
    LD HL,BOOT_ERROR_TEXT
    LD DE,MESSAGE_SCREEN
    LD BC,INSERT_TEXT - BOOT_ERROR_TEXT
    LDIR
SHOW_HARD_DISK_ERROR_1:
    CALL CHECK_BREAK
    JR NZ,SHOW_HARD_DISK_ERROR_1
.endif

;; Boots from floppy drive 0: asks for a disk until the drive is ready, clears the screen and restores the drive
;; to track 0. A failure there is error DC, D0 when the drive is not ready, or SC on a CRC error.
FLOPPY_BOOT:
.if VERSION >= 2
    LD SP,BOOT_STACK
    XOR A
    OUT [HD_CONTROL_PORT],A
.endif
    LD A,DRIVE_0
    OUT [DRIVE_SELECT_PORT],A
    LD HL,INSERT_TEXT
    LD DE,MESSAGE_SCREEN
.if VERSION = 1
    LD B,$00
    LD C,[HL]                       ; the text's length
    INC HL
.else
    LD BC,DIAG_TEXT - INSERT_TEXT
.endif
    LDIR
FLOPPY_BOOT_1:
    CALL RESET_FDC
    BIT 7,A                         ; not ready
    JR NZ,FLOPPY_BOOT_1
    LD BC,VIDEO_END - VIDEO - 1
    LD DE,VIDEO_END - 2
    LD HL,VIDEO_END - 1
    LD [HL],' '
    LDDR
    CALL RESET_FDC
.if VERSION = 3
    LD B,5
FLOPPY_BOOT_2:
    LD A,$5B                        ; step in
    OUT [FDC_STATUS_PORT],A
    PUSH BC
    LD BC,$0C03
    CALL DELAY
    POP BC
    DJNZ FLOPPY_BOOT_2
    CALL RESET_FDC
.endif
.if VERSION = 1
    LD A,$06                        ; restore and verify
.elseif VERSION = 2
    LD A,$0E                        ; restore, load the head and verify
.else
    LD A,$0B                        ; restore and load the head
.endif
    OUT [FDC_STATUS_PORT],A
    LD D,7
.if VERSION = 5
FLOPPY_BOOT_3:
    CALL DELAY
    IN A,[FDC_STATUS_PORT]
    BIT 0,A                         ; busy
    JR Z,FLOPPY_BOOT_4
    DEC D
    JR NZ,FLOPPY_BOOT_3
FLOPPY_BOOT_4:
.else
FLOPPY_BOOT_3:
    CALL DELAY
    DEC D
    JR NZ,FLOPPY_BOOT_3
.endif
    IN A,[FDC_STATUS_PORT]
.if VERSION = 1
    BIT 0,A                         ; busy
    JR NZ,ERROR_DC
    BIT 4,A                         ; seek error
    JR NZ,ERROR_DC
    BIT 2,A                         ; track 0
    JR Z,ERROR_DC
.else
    PUSH AF
    XOR $04
    AND $15                         ; busy, seek error, or not at track 0
    JR NZ,ERROR_DC
    POP AF
.endif
    BIT 7,A                         ; not ready
    JR NZ,ERROR_D0
    BIT 3,A                         ; CRC error
    JR NZ,ERROR_SC
.if VERSION = 1
    JR LOAD_TRACK

;; Load the error's two letters and show it.
ERROR_DC:
    LD HL,[CODE_DC]
    JR SHOW_ERROR
ERROR_MF:
    LD HL,[CODE_MF]
    JR SHOW_ERROR
ERROR_D0:
    LD HL,[CODE_D0]
    JR SHOW_ERROR
ERROR_TK:
    LD HL,[CODE_TK]
    JR SHOW_ERROR
ERROR_SC:
    LD HL,[CODE_SC]
    JR SHOW_ERROR
ERROR_LD:
    LD HL,[CODE_LD]

;; Shows BOOT ERROR and the error's letters. ESC runs what loaded; otherwise the drive is restored and deselected
;; and the Z80 halts.
;; In:    HL = the letters
SHOW_ERROR:
    LD DE,MESSAGE_SCREEN + 11
    EX DE,HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    LD [HL],' '
    LD DE,MESSAGE_SCREEN
    LD HL,BOOT_ERROR_TEXT
    LD BC,CODE_DC - BOOT_ERROR_TEXT
    LDIR
    IN A,[CONTROL_PORT]
    BIT 7,A
    JR Z,SHOW_ERROR_1
    IN A,[KEYBOARD_PORT]
    CP ESC
    JR NZ,SHOW_ERROR_1
    JP BOOT_ENTRY
SHOW_ERROR_1:
    CALL RESET_FDC
    LD A,$02                        ; restore
    OUT [FDC_STATUS_PORT],A
    LD BC,$0000
    CALL DELAY
    CALL RESET_FDC
    LD A,NO_DRIVE
    OUT [DRIVE_SELECT_PORT],A
    DI
    HALT
    RST $00

;; Names a failed read: TK when the sector was not found, SC on a CRC error, else LD (lost data).
;; In:    A = the controller's status
LOAD_ERROR:
    BIT 4,A
    JR NZ,ERROR_TK
    BIT 3,A
    JR NZ,ERROR_SC
    JR ERROR_LD
.endif

;; Reads track 0's sectors to BOOT_LOAD, each up to TRIES times.
LOAD_TRACK:
    LD HL,BOOT_LOAD
    LD DE,SECTORS << 8 | TRIES
    LD BC,128 << 8 | 1              ; B: the bytes, C: the sector
    LD A,FDC_READ
    EX AF,AF'
LOAD_TRACK_1:
    PUSH HL
    PUSH DE
    PUSH BC
    CALL RESET_FDC
    LD A,C
    OUT [FDC_SECTOR_PORT],A
    EX AF,AF'
    OUT [FDC_STATUS_PORT],A
    EX AF,AF'
    CALL SHORT_DELAY
    POP BC
    PUSH BC
    LD C,FDC_DATA_PORT
LOAD_TRACK_2:
    IN A,[FDC_STATUS_PORT]
    BIT 1,A                         ; a byte is ready
    JR Z,LOAD_TRACK_3
    INI
    JR Z,LOAD_TRACK_4               ; the sector is read
LOAD_TRACK_3:
    BIT 0,A                         ; busy
.if VERSION = 1
    JP NZ,LOAD_TRACK_2
.else
    JR NZ,LOAD_TRACK_2
.endif
LOAD_TRACK_4:
    POP BC
    POP DE
    IN A,[FDC_STATUS_PORT]
    AND $1C                         ; not found, CRC error or lost data
    JR Z,LOAD_TRACK_5
    POP HL                          ; read it again
    DEC E
    JR NZ,LOAD_TRACK_1
.if VERSION = 1
    JR LOAD_ERROR
.else
    BIT 4,A
    JR NZ,ERROR_TK
    BIT 3,A
    JR NZ,ERROR_SC
    JR ERROR_LD
.endif
LOAD_TRACK_5:
    POP AF                          ; drop the sector's address
    INC C
    LD E,TRIES
    DEC D
    JR NZ,LOAD_TRACK_1

;; Checks for BOOT and DIAG in the loaded track, then calls the disk's diagnostics and runs its boot code. A disk
;; without them is error RS.
CHECK_SIGNATURES:
.if VERSION = 1
    LD HL,BOOT_ERROR_TEXT
.else
    LD HL,BOOT_ERROR_TEXT + 1
.endif
    LD DE,BOOT_SIGNATURE
    LD B,4
    CALL COMPARE
.if VERSION >= 2
    JR NZ,ERROR_RS
.endif
    LD HL,DIAG_TEXT
    LD DE,DIAG_SIGNATURE
    LD B,4
    CALL COMPARE
.if VERSION >= 2
    JR NZ,ERROR_RS
.endif
    CALL DIAG_ENTRY
    JP BOOT_ENTRY

.if VERSION >= 2
;; The errors, each with its two letters in D and E. Floppy disk errors restore and deselect the drive first.
ERROR_DC:
    LD DE,'D' << 8 | 'C'
    JR FLOPPY_ERROR
ERROR_D0:
    LD DE,'D' << 8 | '0'
    JR FLOPPY_ERROR
ERROR_SC:
    LD DE,'S' << 8 | 'C'
    JR FLOPPY_ERROR
.if VERSION <= 3
ERROR_CK:
    LD DE,'C' << 8 | 'K'
    JR SHOW_ERROR
.endif
ERROR_Z8:
    LD DE,'Z' << 8 | '8'
    JR SHOW_ERROR
ERROR_MF:
    LD DE,'M' << 8 | 'F'
    JR SHOW_ERROR
ERROR_TK:
    LD DE,'T' << 8 | 'K'
    JR FLOPPY_ERROR
ERROR_LD:
    LD DE,'L' << 8 | 'D'
    JR FLOPPY_ERROR
ERROR_RS:
    LD DE,'R' << 8 | 'S'

;; Restores the floppy drive (before version 5) and deselects it.
FLOPPY_ERROR:
.if VERSION <= 3
    CALL RESET_FDC
    LD A,$02                        ; restore
    OUT [FDC_STATUS_PORT],A
    LD BC,$0000
    CALL DELAY
    CALL RESET_FDC
.endif
    LD A,NO_DRIVE
    OUT [DRIVE_SELECT_PORT],A

;; Shows BOOT ERROR and the error's letters, and halts. It means to run what loaded on ESC or BREAK, but compares
;; the keyboard's status rather than the key, so never does.
;; In:    D, E = the letters
SHOW_ERROR:
    LD HL,MESSAGE_SCREEN + 12
    LD [HL],D
    INC HL
    LD [HL],E
    INC HL
    LD [HL],' '
    LD HL,BOOT_ERROR_TEXT
    LD DE,MESSAGE_SCREEN
    LD BC,INSERT_TEXT - BOOT_ERROR_TEXT
    LDIR
    IN A,[CONTROL_PORT]
    BIT 7,A
    JR Z,STOP
    CP ESC
    JP Z,BOOT_ENTRY
    CP BREAK
    JP Z,BOOT_ENTRY
STOP:
    HALT
    RST $00
.endif

;; Waits about 5 loops, or BC loops from DELAY.
;; Out:   BC = 0
SHORT_DELAY:
    LD BC,5
DELAY:
    DEC BC
    LD A,B
    OR C
    JR NZ,DELAY
    RET

;; Stops any floppy disk controller command and clears its data and status.
;; Out:   A = the status
;; Keeps: BC
RESET_FDC:
    PUSH BC
.if VERSION = 1 || VERSION = 2
    LD A,FDC_FORCE_INTERRUPT
    OUT [FDC_STATUS_PORT],A
    CALL SHORT_DELAY
    IN A,[FDC_DATA_PORT]
    IN A,[FDC_STATUS_PORT]
    LD A,FDC_FORCE_INTERRUPT
    OUT [FDC_STATUS_PORT],A
    CALL SHORT_DELAY
.else
    LD A,FDC_INTERRUPT_NOW
    OUT [FDC_STATUS_PORT],A
    LD A,FDC_FORCE_INTERRUPT
    OUT [FDC_STATUS_PORT],A
.if VERSION = 5
    CALL WAIT_FDC
.else
    CALL SHORT_DELAY
.endif
    IN A,[FDC_DATA_PORT]
.endif
    IN A,[FDC_STATUS_PORT]
    POP BC
    RET

;; Compares B bytes at DE and HL. In version 1, a difference is error RS.
;; Out:   zero = set when they match
COMPARE:
    LD A,[DE]
    CP [HL]
.if VERSION = 1
    JR NZ,ERROR_RS
.else
    RET NZ
.endif
    INC HL
    INC DE
    DJNZ COMPARE
    RET

.if VERSION = 1
ERROR_RS:
    LD HL,[CODE_RS]
    JP SHOW_ERROR
.else
;; Reads a key, if one is ready.
;; Out:   zero = set when it is ESC or BREAK
CHECK_BREAK:
    IN A,[CONTROL_PORT]
    XOR $80
    BIT 7,A
    RET NZ
    IN A,[KEYBOARD_PORT]
    CP ESC
    RET Z
    CP BREAK
    RET

;; Waits for the hard disk controller to finish a command.
;; Out:   zero = set when it succeeded, else A = the error register, or the status with bit 3 set when it timed
;;        out
;; Keeps: BC
HARD_DISK_WAIT:
    PUSH BC
.if VERSION = 5
    LD BC,$7FFF
.else
    LD BC,$0000
.endif
HARD_DISK_WAIT_1:
    IN A,[HD_STATUS_PORT]
    BIT 7,A                         ; busy
    JR NZ,HARD_DISK_WAIT_2
    BIT 4,A                         ; seek complete
    JR NZ,HARD_DISK_WAIT_3
HARD_DISK_WAIT_2:
    EX [SP],IX                      ; a pause
    EX [SP],IX
    DEC BC
    LD A,B
    OR C
    JR NZ,HARD_DISK_WAIT_1
.if VERSION = 2
    LD A,$08
    OR A
.else
    OR $08
.endif
    POP BC
    RET
HARD_DISK_WAIT_3:
    POP BC
    BIT 0,A                         ; error
    RET Z
.if VERSION = 5
    BIT 1,A
    JR Z,HARD_DISK_WAIT_4
    LD A,$10                        ; reset the board
    OUT [HD_CONTROL_PORT],A
    LD A,$0E
    OUT [HD_CONTROL_PORT],A
HARD_DISK_WAIT_4:
    IN A,[HD_ERROR_PORT]
    OR A
.else
    IN A,[HD_ERROR_PORT]
.endif
    RET
.endif

.if VERSION = 5
;; Waits for the floppy disk controller to start and finish a command. When it does not finish, error DC.
;; Keeps: AF, BC
WAIT_FDC:
    PUSH AF
    IN A,[FDC_STATUS_PORT]
    PUSH BC
    LD BC,5
WAIT_FDC_1:
    RRA                             ; busy
    JR C,WAIT_FDC_2
    DEC BC
    LD A,B
    OR C
    IN A,[FDC_STATUS_PORT]
    JR NZ,WAIT_FDC_1
WAIT_FDC_2:
    LD BC,$0000
WAIT_FDC_3:
    DEC BC
    LD A,B
    OR C
    JR Z,WAIT_FDC_4
    IN A,[FDC_STATUS_PORT]
    RRA
    JR C,WAIT_FDC_3
    POP BC
    POP AF
    RET
WAIT_FDC_4:
    POP AF                          ; drop BC, AF and the return
    POP AF
    POP AF
    JP ERROR_DC
.endif

.if VERSION >= 2
;; The sector that ends a hard disk's boot code starts with this.
END_BOOT_TEXT:
    .byte "/* END BOOT */"
BOOT_ERROR_TEXT:
    .byte " BOOT ERROR "
.else
BOOT_ERROR_TEXT:
    .byte "BOOT ERROR "

;; The errors' letters.
CODE_DC:
    .byte "DC"                      ; the drive did not restore
CODE_TK:
    .byte "TK"                      ; a sector was not found
CODE_D0:
    .byte "D0"                      ; drive 0 is not ready
CODE_SC:
    .byte "SC"                      ; a CRC error
CODE_LD:
    .byte "LD"                      ; lost data
CODE_Z8:
    .byte "Z8"                      ; the CPU failed
CODE_MF:
    .byte "MF"                      ; the memory failed
CODE_CK:
    .byte "CK"                      ; the ROM's checksum is wrong
CODE_RS:
    .byte "RS"                      ; the disk has no BOOT or DIAG
.endif

INSERT_TEXT:
.if VERSION = 1
    .byte DIAG_TEXT - INSERT_TEXT - 1
.endif
    .byte " INSERT DISKETTE "
DIAG_TEXT:
    .byte "DIAG"

;; The 6845's registers R0-R15: 80 of 99 characters a line, 24 of 26 rows of 10 lines, and the cursor at $03E9.
CRTC_TABLE:
    .byte $63, $50, $55, $08, $19, $00, $18, $18, $00, $09, $65, $09, $00, $00, $03, $E9

; The version, then what reads as a date and time in BCD.
.if VERSION = 1
    .byte VERSION, $FF, $FF, $FF, $FF
CHECKSUM_BYTE:
    .byte $3A                       ; the complement of the sum of the bytes before it
.elseif VERSION = 2
    .byte VERSION, $81, $07, $29, $10, $24      ; 29 July 1981, 10:24
    .byte $6B                       ; makes the bytes sum to zero
ROM_END:
.elseif VERSION = 3
    .byte VERSION, $82, $05, $07, $12, $43      ; 7 May 1982, 12:43
    .byte $95                       ; makes the bytes sum to zero
ROM_END:
.else
    .byte VERSION, $83, $07, $29, $15, $00      ; 29 July 1983, 15:00
.endif

.if FILL_11BE
    .res $04CC - *, $FF
    .byte $87, $87
    .res $0583 - *, $FF
    .byte $00
    .res $05C8 - *, $FF
    .byte $06, $FF, $FF, $FF, $86
    .res $0783 - *, $FF
    .byte $00
    .res $07C8 - *, $FF
    .byte $04
.endif
.if VERSION = 5
    .res $0800 - *, $00
.else
    .res $0800 - *, $FF
.endif
