;; TRS-80 MODEL III AND MODEL 4 EQUATES
;;
;; The ports, keyboard addresses and RAM the Model III ROM uses beyond Level II's, for Model3.asm and the Model III
;; blocks of Level2.asm. The RAM names are those of Radio Shack's Model III source; the ports, vectors and device
;; control blocks have names that say what they are, as in Level2.asm.

; Ports.
MEMORY_MAP_PORT = $84               ;; Model 4: bits 0-1 the memory map, 2 80x24, 3 inverse video, 4-6 paging, 7 the video page
CRTC_ADDRESS_PORT = $88             ;; Model 4: selects a 6845 register
CRTC_DATA_PORT = $89                ;; Model 4: writes the selected 6845 register
SOUND_PORT = $90                    ;; Model 4: bit 0 drives the speaker
INTERRUPT_PORT = $E0                ;; read: which devices interrupt, active low; write: which may
NMI_PORT = $E4                      ;; read: why the NMI came, active low (bit 7 the disk, 6 the motor timeout, 5 reset); write: which may
RS232_RESET_PORT = $E8              ;; read: the modem lines; write: resets the UART
RS232_BAUD_PORT = $E9               ;; the baud rate generator: receive in bits 0-3, send in 4-7
RS232_STATUS_PORT = $EA             ;; read: the UART's status; write: its control register
RS232_DATA_PORT = $EB               ;; the byte received or to send
OPTIONS_PORT = $EC                  ;; write: bit 1 the cassette motor, 2 wide characters, 3 the alternate characters, 5 video wait, 6 the Model 4's 4 MHz; read: acknowledges the clock
FDC_STATUS_PORT = $F0               ;; the FD1793's status, and its command when written
FDC_TRACK_PORT = $F1
FDC_SECTOR_PORT = $F2
FDC_DATA_PORT = $F3
DRIVE_SELECT_PORT = $F4             ;; bits 0-3 the drive, 4 the side, 6 wait for the controller, 7 double density
PRINTER_PORT = $F8                  ;; read: the printer's status; write: the byte to print
CASSETTE_PORT = $FF                 ;; read: bit 7 the 500 baud latch, bit 0 the 1500 baud level; write: bits 0-1 the output

; Bits of INTERRUPT_PORT, read active low and written to enable.
INT_CASSETTE_RISE = $01             ;; a 1500 baud tape's signal rose
INT_CASSETTE_FALL = $02             ;; a 1500 baud tape's signal fell
INT_CLOCK = $04                     ;; the real-time clock, 30 times a second

; Bits of NMI_PORT.
NMI_DISK = $80                      ;; the disk controller's INTRQ
NMI_RESET = $20                     ;; the reset button, when read

; Drive select.
DRIVE_0_DOUBLE = $81                ;; drive 0, side 0, double density
DRIVE_WAIT = $40                    ;; hold the Z80 until the controller asks for data

; 1500 baud tapes: SEEK's counts for a cycle of the signal.
LOWCT = 15                          ;; shorter is not a cycle
HIGHCT = 62                         ;; longer is not a cycle
HALF = 34                           ;; shorter is a 1, longer a 0
HALF_DIFFERENCE = 13                ;; a leader's cycles timed from the right edge differ by less

; Model 4: the function keys, kept where the Model III's RS-232 blocks keep their names.
FKEY1 = $41EB                       ;; F1's code
FKEY2 = $41EC                       ;; F2's code
FKEY3 = $41F3                       ;; F3's code
FKEYS = $41F4                       ;; the last reading of row 7's CTRL, CAPS and function keys

; Keyboard.
KBROW = KEYBOARD_ROW0               ;; the first row; each row's address is twice the last's
DNAROW = KEYBOARD_ROW6              ;; the row of the arrow keys
SHFKEY = KEYBOARD_ROW7              ;; the row of the shift keys
DARW = 4                            ;; the down arrow's bit in DNAROW
SKEY = 0                            ;; the left shift's bit in SHFKEY

; RAM: the keyboard and video drivers' state in their device control blocks.
SKROB = $4018                       ;; the right shift key as last read, to see it go down
SHFLCK = $4019                      ;; nonzero while shift lock (shift and 0) is on
BLKCNT = $401A                      ;; clock ticks until the cursor blinks again
BLKFLG = $401B                      ;; bit 0: the cursor is showing in its blink
BLKON = $401C                       ;; zero for a blinking cursor
CURCAR = $4022                      ;; the character under the cursor, or zero when the cursor is off
CURSOR_CHAR = $4023                 ;; the character the cursor shows
CURSWT = $4024                      ;; bit 0: codes $C0-$FF show as characters rather than space compression

; RAM: the vectors and devices the Model III adds.
DOS_EXIT_VECTOR = $402D             ;; JP: where a DOS's exit goes
DOS_ABORT_VECTOR = $4030            ;; RST $00: where a DOS's abort goes
IO_BUS_VECTOR = $403D               ;; JP: the I/O bus's interrupt
RS232_ERROR_VECTOR = $4040          ;; JP: the UART's error interrupt
INTERRUPT7_VECTOR = $4043           ;; JP: interrupt bit 7, which nothing drives
CLOCK_VECTOR = $4046                ;; JP: the real-time clock's interrupt
NMI_VECTOR = $4049                  ;; the disk NMI's handler: RST $00 until a DOS puts a JP there
MSTACK = $407D                      ;; the stack while the ROM starts
RUBSW = $409F                       ;; Model III: bit 0 inside quotes, bit 1 in DATA, bit 2 in a remark, as a line is crunched
RS232_INPUT_DCB = $41E5             ;; type 1, the RS-232 input driver, the byte received, flags, error, "RI"
RS232_INPUT_BUFFER = $41E8
RS232_OUTPUT_DCB = $41ED            ;; type 2, the RS-232 output driver, the byte to send, flags, error, "RO"
RS232_OUTPUT_BUFFER = $41F0
RS232_INIT_DCB = $41F5              ;; type 2, the RS-232 set-up driver, baud, UART control, wait, "RN"
LROW = $41FD                        ;; the row of the key last pressed, for repeat
LCOL = $41FE                        ;; its bit in the row
TDELAY = $41FF                      ;; keyboard scans before a held key repeats
TCOUNT = $4201                      ;; keyboard scans the key has been held
BREAK_VECTOR = $4203                ;; JP: where BREAK during a tape or RS-232 transfer goes
RS232_RECEIVE_VECTOR = $4206        ;; JP: the UART's receive interrupt
RS232_TRANSMIT_VECTOR = $4209       ;; JP: the UART's transmit interrupt
WRILOC = $420C                      ;; the tape byte writer: WDATA at 500 baud, DATAW at 1500
REDLOC = $420E                      ;; the tape byte reader: RDATA at 500 baud, DATAR at 1500
IOSTAT = $4210                      ;; the last value written to OPTIONS_PORT; bit 0 shows the clock on the screen
CASDCB = $4211                      ;; zero for 500 baud tapes, nonzero for 1500
BLINK = $4212                       ;; counts tape bytes, to blink the asterisk
MSKSTA = $4213                      ;; the interrupt mask to restore after a tape
SCRLCT = $4214                      ;; the number of lines, 0-7, at the top of the screen that do not scroll
MSKSAV = $4215
TICKIT = $4216                      ;; clock ticks left in this second, from 30
SECOND = $4217                      ;; the clock: seconds, minutes, hours, year, day and month
MINUTE = $4218
HOUR = $4219
YEAR = $421A
DAY = $421B
MONTH = $421C
ROUTE_DCB = $421D                   ;; type 2, the router, the source and destination devices' letters
ROUTE_SOURCE = $4220
ROUTE_DESTINATION = $4222
CNTFLG = $4224                      ;; $1F while shift and the down arrow (the Model III's control) are down, else $FF
BOOT_BUFFER = $4300                 ;; where the disk's boot sector is read to and run
DOS_EXIT_DEFAULT = $5000            ;; where DOS_EXIT_VECTOR jumps until a DOS sets it
