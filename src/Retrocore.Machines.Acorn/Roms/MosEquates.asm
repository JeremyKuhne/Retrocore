;; BBC MICRO EQUATES: SHEILA, ZERO PAGE, THE VECTORS, THE OS VARIABLES AND THE MOS WORKSPACE
;;
;; The BBC Micro's memory-mapped hardware in SHEILA (&FE00-&FEFF) and the RAM the MOS keeps: its share of zero page,
;; the vectors and OS variables in page two, the VDU and cassette workspace in page three, the buffers in pages
;; eight to ten, the soft keys, and the NMI and paged ROM workspace in page thirteen. The MOS includes this file,
;; and so can the paged ROMs, so each name here is defined and documented once.
;;
;; Acorn's documentation names the calls and vectors but not the workspace: the Advanced User Guide (chapter 11,
;; "Memory usage") describes each location and its use, and the names here are ours, taken from those descriptions.
;; Where an OS variable is read and written by OSBYTE &A6-&FF, its description says which.

; ---------------------------------------------------------------------------------------------------------------------
; SHEILA: the memory-mapped hardware, &FE00-&FEFF
; ---------------------------------------------------------------------------------------------------------------------

;; The 6845 CRTC's address register: a write selects the register the next access to <CRTC_DATA> reaches.
;; See: <CRTC_DATA>
CRTC_ADDRESS = $FE00

CRTC_DATA = $FE01                   ;; the 6845 register <CRTC_ADDRESS> selects

;; The 6850 ACIA's control register (writes) and status register (reads), shared by the cassette and RS-423.
;;
;; The status bits are receive data full (0), transmit data empty (1), carrier lost (2), not clear to send (3),
;; framing error (4), overrun (5), parity error (6) and interrupt (7). With the cassette, the serial ULA drives the
;; carrier input from the tape's high tone, so the cassette filing system reads bit 2 as high tone heard.
;; See: <ACIA_STATUS>, <ACIA_DATA>, <SERIAL_ULA>, <ACIA_CONTROL_COPY>
ACIA_CONTROL = $FE08

ACIA_STATUS = ACIA_CONTROL          ;; the 6850's status register, read at <ACIA_CONTROL>
ACIA_DATA = $FE09                   ;; the 6850's transmit (write) and receive (read) data registers

;; The serial ULA's control register (write only): the transmit and receive baud rates, cassette or RS-423, and the
;; cassette motor.
;;
;; Bits 0-2 are the transmit rate and bits 3-5 the receive rate (0 for 19200 baud to 7 for 75), bit 6 selects
;; RS-423 (set) or the cassette, and bit 7 turns the cassette motor on. The MOS keeps a copy in
;; <SERIAL_ULA_COPY>.
;; See: <SERIAL_ULA_COPY>, <ACIA_CONTROL>
SERIAL_ULA = $FE10

;; The Econet station ID register: reading it gives the station number set on the board's links.
;;
;; A read also holds the Econet's NMIs back until &FE20 is read, which the NFS does before each RTI. The Advanced User
;; Guide puts the register at Sheila &20, but the NFS reads the station number here.
STATION_ID = $FE18

;; The video ULA's control register (write only): the cursor, the clock rate, the characters per line, teletext and
;; the flash colour.
;;
;; Bit 0 selects the flashing colours, bit 1 teletext, bits 2-3 the characters per line, bit 4 the 2 MHz clock, and
;; bits 5-7 the cursor's width. The MOS keeps a copy in <VIDEO_ULA_CONTROL_COPY>.
;; See: <VIDEO_ULA_PALETTE>, <VIDEO_ULA_CONTROL_COPY>
VIDEO_ULA_CONTROL = $FE20

;; The video ULA's palette (write only): the high nibble is a logical colour and the low nibble its physical colour,
;; exclusive-ORed with 7.
;; See: <VIDEO_ULA_CONTROL>, <VIDEO_ULA_PALETTE_COPY>, <PALETTE>
VIDEO_ULA_PALETTE = $FE21

;; The paged ROM select latch (write only): the low nibble picks the ROM at &8000-&BFFF. The MOS keeps the number in
;; <ROMSEL_COPY>, which must always match.
;; See: <ROMSEL_COPY>
ROMSEL = $FE30

; The system 6522 VIA, &FE40-&FE4F. Port A is the slow data bus to the keyboard, the sound chip and the speech chip;
; port B bits 0-3 drive the addressable latch, bits 4-5 read the joystick buttons and bits 6-7 the speech chip.
; CA1 takes the 6845's vertical sync, CA2 the keyboard, CB1 the ADC's end of conversion and CB2 the light pen.

SYS_VIA_ORB = $FE40                 ;; the system VIA's port B: the addressable latch (write) and buttons (read)
SYS_VIA_ORA = $FE41                 ;; the system VIA's port A, the slow data bus, with handshaking
SYS_VIA_DDRB = $FE42                ;; the system VIA's port B data direction register
SYS_VIA_DDRA = $FE43                ;; the system VIA's port A data direction register
SYS_VIA_T1CL = $FE44                ;; the system VIA's timer 1 counter, low byte
SYS_VIA_T1CH = $FE45                ;; the system VIA's timer 1 counter, high byte
SYS_VIA_T1LL = $FE46                ;; the system VIA's timer 1 latch, low byte
SYS_VIA_T1LH = $FE47                ;; the system VIA's timer 1 latch, high byte
SYS_VIA_T2CL = $FE48                ;; the system VIA's timer 2 counter, low byte, which times speech
SYS_VIA_T2CH = $FE49                ;; the system VIA's timer 2 counter, high byte
SYS_VIA_SR = $FE4A                  ;; the system VIA's shift register
SYS_VIA_ACR = $FE4B                 ;; the system VIA's auxiliary control register
SYS_VIA_PCR = $FE4C                 ;; the system VIA's peripheral control register
SYS_VIA_IFR = $FE4D                 ;; the system VIA's interrupt flag register
SYS_VIA_IER = $FE4E                 ;; the system VIA's interrupt enable register
SYS_VIA_ORA_NH = $FE4F              ;; the system VIA's port A, the slow data bus, without handshaking

; The user 6522 VIA, &FE60-&FE6F. Port A is the printer port and port B the user port.

USER_VIA_ORB = $FE60                ;; the user VIA's port B, the user port
USER_VIA_ORA = $FE61                ;; the user VIA's port A, the printer's data
USER_VIA_DDRB = $FE62               ;; the user VIA's port B data direction register
USER_VIA_DDRA = $FE63               ;; the user VIA's port A data direction register
USER_VIA_T1CL = $FE64               ;; the user VIA's timer 1 counter, low byte
USER_VIA_T1CH = $FE65               ;; the user VIA's timer 1 counter, high byte
USER_VIA_T1LL = $FE66               ;; the user VIA's timer 1 latch, low byte
USER_VIA_T1LH = $FE67               ;; the user VIA's timer 1 latch, high byte
USER_VIA_T2CL = $FE68               ;; the user VIA's timer 2 counter, low byte
USER_VIA_T2CH = $FE69               ;; the user VIA's timer 2 counter, high byte
USER_VIA_SR = $FE6A                 ;; the user VIA's shift register
USER_VIA_ACR = $FE6B                ;; the user VIA's auxiliary control register
USER_VIA_PCR = $FE6C                ;; the user VIA's peripheral control register; CA2 strobes the printer
USER_VIA_IFR = $FE6D                ;; the user VIA's interrupt flag register; CA1 is the printer's acknowledge
USER_VIA_IER = $FE6E                ;; the user VIA's interrupt enable register
USER_VIA_ORA_NH = $FE6F             ;; the user VIA's port A without handshaking

;; The 8271 floppy disc controller's status register (read) and command register (write).
;;
;; A command is written here and its parameters to <FDC_PARAMETER>. The status's bit 7 is set while the 8271 is
;; busy, bit 6 while its command register is full, bit 5 while its parameter register is full, bit 4 when its result
;; is ready, bit 3 when it interrupts and bit 2 when it asks for a data byte without DMA.
;; See: <FDC_RESULT>, <FDC_DATA>
FDC_COMMAND = $FE80

FDC_STATUS = FDC_COMMAND            ;; the 8271's status register, read at <FDC_COMMAND>
FDC_PARAMETER = $FE81               ;; the 8271's parameter register (write)
FDC_RESULT = FDC_PARAMETER          ;; the 8271's result register, read at <FDC_PARAMETER>
FDC_RESET = $FE82                   ;; the 8271's reset register: 1 then 0 resets the controller
FDC_DATA = $FE84                    ;; the 8271's data register, read and written by the NMI routine during transfers

;; The 68B54 ADLC's control register 1 (write) and status register 1 (read), the Econet's data link controller.
;; See: <ADLC_CONTROL_2>, <ADLC_TX_CONTINUE>
ADLC_CONTROL_1 = $FEA0

ADLC_STATUS_1 = ADLC_CONTROL_1      ;; the 68B54's status register 1, read at <ADLC_CONTROL_1>
ADLC_CONTROL_2 = $FEA1              ;; the 68B54's control register 2, or 3 when control register 1's bit 0 is set
ADLC_STATUS_2 = ADLC_CONTROL_2      ;; the 68B54's status register 2, read at <ADLC_CONTROL_2>
ADLC_TX_CONTINUE = $FEA2            ;; the 68B54's transmit FIFO, continuing the frame; reads the receive FIFO
ADLC_RX_DATA = ADLC_TX_CONTINUE     ;; the 68B54's receive FIFO, read at <ADLC_TX_CONTINUE>
ADLC_TX_TERMINATE = $FEA3           ;; the 68B54's transmit FIFO, ending the frame; control register 4 with CR1 bit 0

;; The uPD7002 ADC's status register (read) and its command register (write), which starts a conversion.
;;
;; A command's bits 0-1 are the channel and bit 3 picks a 12-bit conversion. The status register's bit 7 is clear
;; once a conversion is complete.
;; See: <ADC_HIGH>, <ADC_LOW>, <ADC_STATUS>
ADC_COMMAND = $FEC0

ADC_STATUS = ADC_COMMAND            ;; the uPD7002's status register, read at <ADC_COMMAND>
ADC_HIGH = $FEC1                    ;; the uPD7002's conversion, high byte
ADC_LOW = $FEC2                     ;; the uPD7002's conversion, low byte

;; The Tube's first register pair, status then data. With no Tube fitted, the MOS's writes here are lost and its
;; reads see the floating bus.
;; See: <TUBE_PRESENT>
TUBE_R1_STATUS = $FEE0

TUBE_R1_DATA = $FEE1                ;; the Tube's register 1 data: OSWRCH's characters, and escapes and events
TUBE_R2_STATUS = $FEE2              ;; the Tube's register 2 status: bit 7 set when data waits, bit 6 when there is room
TUBE_R2_DATA = $FEE3                ;; the Tube's register 2 data, which carries the parasite's calls and their replies
TUBE_R3_STATUS = $FEE4              ;; the Tube's register 3 status
TUBE_R3_DATA = $FEE5                ;; the Tube's register 3 data, which carries file data
TUBE_R4_STATUS = $FEE6              ;; the Tube's register 4 status
TUBE_R4_DATA = $FEE7                ;; the Tube's register 4 data: transfer and release requests, and errors

FRED = $FC00                        ;; FRED, the 1 MHz bus's page of memory-mapped devices (&FC00-&FCFF)
JIM = $FD00                         ;; JIM, the 1 MHz bus's page of paged memory (&FD00-&FDFF)
SHEILA = $FE00                      ;; SHEILA, the BBC's own memory-mapped hardware (&FE00-&FEFF)

; ---------------------------------------------------------------------------------------------------------------------
; Zero page: &00-&8F belong to the current language and &90-&9F to Econet; the MOS's own begins at &A0
; ---------------------------------------------------------------------------------------------------------------------

NMI_WORKSPACE = $A0                 ;; &A0-&A7, for the current owner of the NMI, such as a disc filing system
OS_COMMAND_WORKSPACE = $A8          ;; &A8-&AF, for the MOS's commands while they run
FS_SCRATCH = $B0                    ;; &B0-&BF, filing system scratch space, not kept between calls
FS_WORKSPACE = $C0                  ;; &C0-&CF, the active filing system's own workspace

;; The VDU status byte, which OSBYTE &75 reads.
;;
;; The bits are the printer (bit 0, VDU 2), scrolling disabled (bit 1, also set while the copy cursor is current),
;; paged mode (bit 2, VDU 14), a text window (bit 3), text at the graphics cursor (bit 5, VDU 5), cursor editing,
;; with the input and output cursors apart (bit 6), and the VDU driver disabled (bit 7, VDU 21). Bit 4 is not used.
VDU_STATUS = $D0

;; A byte with a bit set for each bit of the screen byte that belongs to the current graphics point: &01 for a two
;; colour mode's rightmost pixel, &55 for a sixteen colour mode's.
GRAPHICS_MASK = $D1

TEXT_OR_MASK = $D2                  ;; the text colour pattern ORed into a character's screen bytes
TEXT_EOR_MASK = $D3                 ;; the text colour pattern then exclusive-ORed into them
GRAPHICS_OR_MASK = $D4              ;; the graphics colour pattern ORed into screen bytes, which carries the GCOL action
GRAPHICS_EOR_MASK = $D5             ;; the graphics colour pattern then exclusive-ORed into them
GRAPHICS_CELL = $D6                 ;; the address of the top line of the current graphics point's character cell
TEXT_CELL = $D8                     ;; the address of the top scan line of the current text character
VDU_TEMP = $DA                      ;; &DA-&DF, the VDU driver's temporary workspace

;; A pointer to the row multiplication table for the current mode: <ROW_OFFSETS_640> for modes 0-6, or
;; <ROW_OFFSETS_40> for teletext. The tables hold the high byte of each entry first. <CALCULATE_TEXT_CURSOR> halves
;; the 640-byte rows for the 10K and 8K memory maps (modes 4-6), whatever the columns: mode 1 has 40 columns and full
;; rows, mode 5 has 20 and half rows.
ROW_TABLE = $E0

;; The cassette filing system's status: input file open (bit 0), output file open (bit 1), cataloguing (bit 3), at
;; the end of the file (bit 6), and the end-of-file warning given (bit 7).
CFS_STATUS = $E2

;; The cassette filing system's options, as *OPT sets them: the high nibble for LOAD and SAVE, the low one for
;; sequential access.
;;
;; In each nibble, bit 0 set aborts after an error and bit 1 set retries (neither ignores it); bit 3 set gives
;; messages, and bit 2 makes them the long ones.
CFS_OPTIONS = $E3

OS_WORK = $E4                       ;; &E4-&E6, general MOS workspace
AUTO_REPEAT_TIMER = $E7             ;; the auto-repeat countdown, decremented at 100 Hz; at zero the key repeats
INPUT_BUFFER_POINTER = $E8          ;; the buffer that OSWORD 0 reads a line into

;; The RS-423 timeout counter: 1 when the cassette filing system has the 6850, 0 when RS-423 has it but has timed
;; out, and negative while RS-423 has it and has not.
RS423_TIMEOUT = $EA

CASSETTE_CRITICAL = $EB             ;; bit 7 set while the CFS is called for an EXEC BGET or a SPOOL BPUT, to keep quiet
LAST_KEY_PRESSED = $EC              ;; the internal key number of the most recent key pressed, or 0
FIRST_KEY_PRESSED = $ED             ;; the first key pressed of those still held, or 0, for two-key rollover
;; Not a key the scan ignores: only its address is used, in Y, to pick OSBYTE &79 and &7A's byte of <ROLLOVER_WORK>,
;; the third. OSBYTE's scan takes the first pressed key it reaches, whatever is stored here.
OSBYTE_SCAN_SELECTOR = $EE
OS_A = $EF                          ;; the A register for the most recent OSBYTE or OSWORD
OS_X = $F0                          ;; the X register for the most recent OSBYTE or OSWORD, or S at the last BRK
OS_Y = $F1                          ;; the Y register for the most recent OSBYTE or OSWORD
TEXT_POINTER = $F2                  ;; a pointer to the command line or file name being read
ROMSEL_COPY = $F4                   ;; the number of the paged ROM selected in <ROMSEL>
ROM_FS_ROM = $F5                    ;; the ROM filing system's current ROM, or a speech PHROM when negative
ROM_POINTER = $F6                   ;; a pointer into a paged ROM or a speech PHROM, as OSRDRM and services &0D-&0E use
OS_SCRATCH = $FA                    ;; &FA-&FB, general MOS workspace, often a pointer
IRQ_A = $FC                         ;; where an interrupt saves A while it sets up the stack
ERROR_POINTER = $FD                 ;; the byte after the last BRK, or the current language's version string
ESCAPE_FLAG = $FF                   ;; bit 7 set while an escape is pending

; ---------------------------------------------------------------------------------------------------------------------
; Page one: the stack
; ---------------------------------------------------------------------------------------------------------------------

STACK = $0100                       ;; the 6502 stack, &0100-&01FF

;; The base the OS variables are indexed from: the variable OSBYTE &A6-&FF reads is at OS_VARIABLES + A, so OSBYTE
;; &A6 reads &0236.
;; See: <OS_VARIABLES_ADDRESS>
OS_VARIABLES = $0190

; ---------------------------------------------------------------------------------------------------------------------
; Page two: the vectors
; ---------------------------------------------------------------------------------------------------------------------

USERV = $0200                       ;; the user vector, which *CODE, *LINE and OSWORD &E0-&FF call
BRKV = $0202                        ;; the BRK vector, called after a BRK, normally the language's error handler
IRQ1V = $0204                       ;; the primary interrupt vector, the MOS's own interrupt handler
IRQ2V = $0206                       ;; the secondary interrupt vector, for interrupts the MOS does not recognize
CLIV = $0208                        ;; the command line interpreter vector, OSCLI
BYTEV = $020A                       ;; the OSBYTE vector
WORDV = $020C                       ;; the OSWORD vector
WRCHV = $020E                       ;; the write character vector, OSWRCH
RDCHV = $0210                       ;; the read character vector, OSRDCH
FILEV = $0212                       ;; the load and save file vector, OSFILE
ARGSV = $0214                       ;; the file arguments vector, OSARGS
BGETV = $0216                       ;; the byte get vector, OSBGET
BPUTV = $0218                       ;; the byte put vector, OSBPUT
GBPBV = $021A                       ;; the get and put bytes vector, OSGBPB
FINDV = $021C                       ;; the open and close file vector, OSFIND
FSCV = $021E                        ;; the filing system control vector
EVNTV = $0220                       ;; the event vector
UPTV = $0222                        ;; the user print vector, for printer type 3
NETV = $0224                        ;; the Econet vector
VDUV = $0226                        ;; the unrecognized VDU 23 and PLOT vector
KEYV = $0228                        ;; the keyboard vector
INSV = $022A                        ;; the insert into buffer vector
REMV = $022C                        ;; the remove from buffer vector
CNPV = $022E                        ;; the count and purge buffer vector
IND1V = $0230                       ;; spare vector 1
IND2V = $0232                       ;; spare vector 2
IND3V = $0234                       ;; spare vector 3

; ---------------------------------------------------------------------------------------------------------------------
; Page two: the OS variables, &0236-&028F, which OSBYTE &A6-&FF read and write
; ---------------------------------------------------------------------------------------------------------------------

OS_VARIABLES_ADDRESS = $0236        ;; OSBYTE &A6-&A7: the address of <OS_VARIABLES>
EXTENDED_VECTORS_ADDRESS = $0238    ;; OSBYTE &A8-&A9: the address of the extended vectors, <EXTENDED_VECTORS>
ROM_TABLE_ADDRESS = $023A           ;; OSBYTE &AA-&AB: the address of the ROM type table, <ROM_TYPE_TABLE>
KEY_TABLE_ADDRESS = $023C           ;; OSBYTE &AC-&AD: the address of the keyboard translation table
VDU_VARIABLES_ADDRESS = $023E       ;; OSBYTE &AE-&AF: the address of the VDU variables, &0300
CFS_TIMEOUT = $0240                 ;; OSBYTE &B0: the CFS timeout counter, decremented at each vertical sync
INPUT_SOURCE = $0241                ;; OSBYTE &B1: the input source, 0 for the keyboard or 1 for RS-423 (OSBYTE 2)
KEYBOARD_SEMAPHORE = $0242          ;; OSBYTE &B2: &FF while a key is held; the scan raises it to 0 while it runs
PRIMARY_OSHWM = $0243               ;; OSBYTE &B3: the high water mark before any font explosion
OSHWM = $0244                       ;; OSBYTE &B4: the high water mark, the page user memory starts at
RS423_MODE = $0245                  ;; OSBYTE &B5: zero when RS-423 input is interpreted as keyboard input
FONT_EXPLOSION = $0246              ;; OSBYTE &B6: the character definition explosion state (OSBYTE 20)
CFS_RFS_SWITCH = $0247              ;; OSBYTE &B7: zero for the cassette filing system, 2 for the ROM filing system
VIDEO_ULA_CONTROL_COPY = $0248      ;; OSBYTE &B8: the MOS's copy of <VIDEO_ULA_CONTROL>
VIDEO_ULA_PALETTE_COPY = $0249      ;; OSBYTE &B9: the MOS's copy of the last write to <VIDEO_ULA_PALETTE>
BRK_ROM = $024A                     ;; OSBYTE &BA: the paged ROM selected at the last BRK
BASIC_ROM = $024B                   ;; OSBYTE &BB: the socket holding BASIC, or &FF
ADC_CHANNEL = $024C                 ;; OSBYTE &BC: the ADC channel being converted
ADC_MAX_CHANNEL = $024D             ;; OSBYTE &BD: the highest ADC channel to convert (OSBYTE 16)
ADC_CONVERSION = $024E              ;; OSBYTE &BE: the ADC conversion type, 8 or 12 bits, or 0 for the default
RS423_BUSY = $024F                  ;; OSBYTE &BF: the RS-423 use flag; bit 7 clear while RS-423 is busy
ACIA_CONTROL_COPY = $0250           ;; OSBYTE &C0: the MOS's copy of <ACIA_CONTROL>
FLASH_COUNTER = $0251               ;; OSBYTE &C1: fields left before the flashing colours change
MARK_PERIOD = $0252                 ;; OSBYTE &C2: the fields the second flashing colours show for (set by OSBYTE 10)
SPACE_PERIOD = $0253                ;; OSBYTE &C3: the fields the first flashing colours show for (set by OSBYTE 9)
AUTO_REPEAT_DELAY = $0254           ;; OSBYTE &C4: the centiseconds before a held key repeats (OSBYTE 11)
AUTO_REPEAT_PERIOD = $0255          ;; OSBYTE &C5: the centiseconds between repeats (OSBYTE 12)
EXEC_HANDLE = $0256                 ;; OSBYTE &C6: the *EXEC file's handle, or 0
SPOOL_HANDLE = $0257                ;; OSBYTE &C7: the *SPOOL file's handle, or 0
ESCAPE_BREAK_EFFECT = $0258         ;; OSBYTE &C8: bit 0 disables ESCAPE, bit 1 makes BREAK clear memory
KEYBOARD_DISABLE = $0259            ;; OSBYTE &C9: nonzero to disable the keyboard (Econet)
KEYBOARD_STATUS = $025A             ;; OSBYTE &CA: SHIFT (3), CAPS LOCK off (4), SHIFT LOCK off (5), CTRL (6)
RS423_HANDSHAKE = $025B             ;; OSBYTE &CB: the free space in the RS-423 input buffer below which RTS stops input
RS423_SUPPRESS = $025C              ;; OSBYTE &CC: nonzero to ignore RS-423 input
CASSETTE_RS423_SELECT = $025D       ;; OSBYTE &CD: which of the cassette and RS-423 the serial ULA is set for
ECONET_OS_INTERCEPT = $025E         ;; OSBYTE &CE: bit 7 set while Econet intercepts OSBYTE and OSWORD calls
ECONET_RDCH_INTERCEPT = $025F       ;; OSBYTE &CF: bit 7 set while Econet intercepts OSRDCH
ECONET_WRCH_INTERCEPT = $0260       ;; OSBYTE &D0: bit 7 set while Econet intercepts OSWRCH
SPEECH_SUPPRESS = $0261             ;; OSBYTE &D1: &50 to allow speech, &20 to suppress it
SOUND_SUPPRESS = $0262              ;; OSBYTE &D2: nonzero to suppress sound
BELL_CHANNEL = $0263                ;; OSBYTE &D3: the sound channel for VDU 7
BELL_AMPLITUDE = $0264              ;; OSBYTE &D4: the amplitude or envelope for VDU 7
BELL_PITCH = $0265                  ;; OSBYTE &D5: the pitch for VDU 7
BELL_DURATION = $0266               ;; OSBYTE &D6: the duration for VDU 7
STARTUP_MESSAGE_BOOT = $0267        ;; OSBYTE &D7: bit 7 clear hides the banner; bit 0 set locks up on an error
SOFT_KEY_LENGTH = $0268             ;; OSBYTE &D8: the characters of the soft key being expanded still to read
PAGED_LINES = $0269                 ;; OSBYTE &D9: the lines printed since the last halt in paged mode
VDU_QUEUE_COUNT = $026A             ;; OSBYTE &DA: minus the number of parameters still awaited for a VDU code
TAB_CHARACTER = $026B               ;; OSBYTE &DB: the character the TAB key gives
ESCAPE_CHARACTER = $026C            ;; OSBYTE &DC: the character that is ESCAPE (OSBYTE 220)
INPUT_INTERPRETATION = $026D        ;; OSBYTE &DD-&E0: how input characters &C0-&FF are taken, a byte for each 16
FUNCTION_KEY_STATUS = $0271         ;; OSBYTE &E1-&E4: how the function key codes &80-&BF are taken, a byte per 16
ESCAPE_KEY_STATUS = $0275           ;; OSBYTE &E5: zero when ESCAPE is an escape, otherwise it is an ordinary character
ESCAPE_EFFECTS = $0276              ;; OSBYTE &E6: zero when an escape's acknowledgement flushes buffers and closes EXEC
USER_VIA_IRQ_MASK = $0277           ;; OSBYTE &E7: the user VIA's interrupts the MOS handles
ACIA_IRQ_MASK = $0278               ;; OSBYTE &E8: the 6850's interrupts the MOS handles
SYS_VIA_IRQ_MASK = $0279            ;; OSBYTE &E9: the system VIA's interrupts the MOS handles
TUBE_PRESENT = $027A                ;; OSBYTE &EA: &FF when a Tube is fitted, otherwise 0
SPEECH_PRESENT = $027B              ;; OSBYTE &EB: &FF when a speech processor is fitted, otherwise 0
WRCH_DESTINATION = $027C            ;; OSBYTE &EC: OSWRCH's destinations (OSBYTE 3)
CURSOR_EDITING = $027D              ;; OSBYTE &ED: zero when the cursor keys edit (OSBYTE 4)
USER_FLAG = $0281                   ;; OSBYTE &F1: the user flag, which *FX 1 sets
SERIAL_ULA_COPY = $0282             ;; OSBYTE &F2: the MOS's copy of <SERIAL_ULA>
TIMER_SWITCH = $0283                ;; OSBYTE &F3: which of the two clocks is current, 5 or 10, the other's offset
SOFT_KEY_CONSISTENCY = $0284        ;; OSBYTE &F4: zero when the soft key buffer is consistent, nonzero while it changes
PRINTER_DESTINATION = $0285         ;; OSBYTE &F5: the printer type, 0-4 (OSBYTE 5)
PRINTER_IGNORE = $0286              ;; OSBYTE &F6: the character the printer ignores (OSBYTE 6)
BREAK_INTERCEPT = $0287             ;; OSBYTE &F7-&F9: a JMP called twice on BREAK, or not a JMP
LANGUAGE_ROM = $028C                ;; OSBYTE &FC: the current language's ROM
LAST_BREAK = $028D                  ;; OSBYTE &FD: the last reset: 0 a soft BREAK, 1 power on, 2 a hard BREAK
AVAILABLE_RAM = $028E               ;; OSBYTE &FE: the top of RAM's high byte, &40 for 16K or &80 for 32K
STARTUP_OPTIONS = $028F             ;; OSBYTE &FF: the start-up options, the keyboard links read at reset

; ---------------------------------------------------------------------------------------------------------------------
; Page two: the rest of the MOS's workspace
; ---------------------------------------------------------------------------------------------------------------------

TV_VERTICAL_ADJUST = $0290          ;; the vertical adjustment of the picture that *TV sets
TV_INTERLACE = $0291                ;; the interlace that *TV sets: bit 0 clear for interlace

;; The system clock, kept twice: TIME reads one copy while the 100 Hz interrupt updates the other. Each is five bytes,
;; high byte first, and <TIMER_SWITCH> says which is current.
;; See: <TIMER_SWITCH>
CLOCK_A = $0292

CLOCK_B = $0297                     ;; the system clock's second copy
INTERVAL_TIMER = $029C              ;; the interval timer, five bytes, which raises event 5 when it reaches zero
ROM_TYPE_TABLE = $02A1              ;; the ROM type table: each socket's ROM type byte, or 0 for none
INKEY_TIMER = $02B1                 ;; the INKEY countdown, two bytes, decremented at 100 Hz
LINE_INPUT_WORK = $02B3             ;; &02B3-&02B5, OSWORD 0's maximum length and character range
ADC_LOW_BYTES = $02B6               ;; the low bytes of the last conversion on channels 1-4, channel 1 first
ADC_HIGH_BYTES = $02BA              ;; the high bytes of the last conversion on channels 1-4, channel 1 first
ADC_LAST_CHANNEL = $02BE            ;; the channel last converted, or 0 since OSBYTE &80 read it
EVENT_ENABLE = $02BF                ;; a byte for each event 0-9, nonzero when it is enabled
SOFT_KEY_POINTER = $02C9            ;; the offset in <SOFT_KEYS> of the next soft key character to expand
FIRST_AUTO_REPEAT = $02CA           ;; the next value for <AUTO_REPEAT_TIMER>, a one-byte queue
ROLLOVER_WORK = $02CB               ;; &02CB-&02CD, the lowest key number each kind of keyboard scan reports
SOUND_SEMAPHORE = $02CE             ;; zero while the envelope interrupt is processing, &FF when it is free
;; A byte per buffer 0-8, whose bit 7 means the printer is dormant or a sound channel flushed. It is not whether a
;; buffer is empty: that is <BUFFER_START> equal to <BUFFER_END>, and inserting into the keyboard buffer leaves it set.
BUFFER_BUSY = $02CF
BUFFER_START = $02D8                ;; each buffer's offset of the next byte to remove
BUFFER_END = $02E1                  ;; each buffer's offset where the next byte goes; equal to the start when empty
CFS_BLOCK_SIZE = $02EA              ;; the size of the open input file's resident block
CFS_BLOCK_FLAG = $02EC              ;; the flag of the open input file's resident block
CFS_LAST_CHARACTER = $02ED          ;; the last character of the open input file's resident block
OSFILE_BLOCK = $02EE                ;; &02EE-&02FF, where *LOAD and *SAVE build their OSFILE control block

; ---------------------------------------------------------------------------------------------------------------------
; Page three: the VDU workspace, &0300-&037F, which OSBYTE &A0 reads
; ---------------------------------------------------------------------------------------------------------------------

;; The graphics window, in internal co-ordinates: the left column, bottom row, right column and top row, each two
;; bytes.
GRAPHICS_WINDOW = $0300

TEXT_WINDOW_LEFT = $0308            ;; the text window's left column
TEXT_WINDOW_BOTTOM = $0309          ;; the text window's bottom row
TEXT_WINDOW_RIGHT = $030A           ;; the text window's right column
TEXT_WINDOW_TOP = $030B             ;; the text window's top row
GRAPHICS_ORIGIN = $030C             ;; the graphics origin, in external co-ordinates: X then Y, two bytes each
GRAPHICS_CURSOR = $0310             ;; the graphics cursor in external co-ordinates, for relative PLOTs
OLD_GRAPHICS_CURSOR = $0314         ;; the previous graphics cursor in internal co-ordinates, for triangles
TEXT_CURSOR_X = $0318               ;; the text cursor's column
TEXT_CURSOR_Y = $0319               ;; the text cursor's row
GRAPHICS_LINE = $031A               ;; the line within its character cell of the current graphics point

;; The VDU queue: a control code's parameters, arranged so that the last one is always at <VDU_QUEUE_END>. Its first
;; four bytes are also graphics workspace.
;; See: <VDU_QUEUE_COUNT>
VDU_QUEUE = $031B

VDU_QUEUE_END = $0323               ;; the last parameter queued
GRAPHICS_CURSOR_INTERNAL = $0324    ;; the graphics cursor in internal co-ordinates
GRAPHICS_WORK = $0328               ;; &0328-&0349, general graphics co-ordinate workspace
TEXT_CURSOR_ADDRESS = $034A         ;; the text cursor's byte address, unwrapped, before the 6845 is sent it
TEXT_WINDOW_WIDTH = $034C           ;; the text window's width in bytes, how much a soft scroll moves on each line
SCREEN_BOTTOM = $034E               ;; the high byte of the first address of screen memory
BYTES_PER_CHARACTER = $034F         ;; the screen bytes a character takes: 8, 16 or 32, or 1 for teletext
SCREEN_START = $0350                ;; the screen's top left byte address, before the 6845 is sent it
BYTES_PER_ROW = $0352               ;; the screen bytes in a character row: 40, 320 or 640
SCREEN_SIZE = $0354                 ;; the high byte of the screen memory's size
SCREEN_MODE = $0355                 ;; the current screen mode
MEMORY_MAP_TYPE = $0356             ;; the screen's size: 0 for 20K, 1 for 16K, 2 for 10K, 3 for 8K and 4 for teletext
TEXT_FOREGROUND = $0357             ;; the foreground text colour, as a byte of that colour
TEXT_BACKGROUND = $0358             ;; the background text colour, as a byte of that colour
GRAPHICS_FOREGROUND = $0359         ;; the foreground graphics colour, as a byte of that colour
GRAPHICS_BACKGROUND = $035A         ;; the background graphics colour, as a byte of that colour
GRAPHICS_FOREGROUND_ACTION = $035B  ;; the foreground plotting action, GCOL's first parameter
GRAPHICS_BACKGROUND_ACTION = $035C  ;; the background plotting action
VDU_JUMP = $035D                    ;; a jump vector for decoding VDU control codes and PLOT numbers
CURSOR_START = $035F                ;; the last setting of the 6845's cursor start register, for VDU 23,1
COLOUR_COUNT = $0360                ;; the logical colours in the current mode, less one
PIXELS_PER_BYTE = $0361             ;; the pixels in a screen byte, less one, or 0 in a text-only mode
LEFT_COLOUR_MASK = $0362            ;; a byte with the bits of a screen byte's leftmost pixel set
RIGHT_COLOUR_MASK = $0363           ;; a byte with the bits of a screen byte's rightmost pixel set
OUTPUT_CURSOR_X = $0364             ;; the output cursor's column, where COPYed characters are written
OUTPUT_CURSOR_Y = $0365             ;; the output cursor's row
TELETEXT_CURSOR = $0366             ;; the character teletext shows as the output cursor, &7F after a reset
FONT_FLAGS = $0367                  ;; a bit per font zone in RAM: bit 6 for &20-&3F down to bit 0 for &E0-&FF
FONT_LOCATIONS = $0368              ;; each font zone's page, seven bytes: &20-&3F first, &E0-&FF last
PALETTE = $036F                     ;; the physical colour of each logical colour, sixteen bytes

; ---------------------------------------------------------------------------------------------------------------------
; Page three: the cassette filing system's workspace, &0380-&03DF, and the keyboard buffer
; ---------------------------------------------------------------------------------------------------------------------

CFS_OUTPUT_HEADER = $0380           ;; &0380-&039C, the header of the BPUT file's block being written
CFS_OUTPUT_OFFSET = $039D           ;; the offset of the next byte BPUT writes into its buffer
CFS_INPUT_OFFSET = $039E            ;; the offset of the next byte BGET reads from its buffer
CFS_INPUT_NAME = $03A7              ;; &03A7-&03B1, the name of the file BGET reads

;; The header of the last block read: its name (ending in zero), load address, execution address, block number,
;; length, flag, four spare bytes and CRC.
;; See: <CFS_BLOCK_LOAD>, <CFS_BLOCK_EXEC>, <CFS_BLOCK_NUMBER>, <CFS_BLOCK_LENGTH>, <CFS_BLOCK_FLAGS>
CFS_BLOCK_NAME = $03B2

CFS_BLOCK_LOAD = $03BE              ;; the last block's load address, four bytes
CFS_BLOCK_EXEC = $03C2              ;; the last block's execution address, four bytes
CFS_BLOCK_NUMBER = $03C6            ;; the last block's number, two bytes
CFS_BLOCK_LENGTH = $03C8            ;; the last block's length, two bytes
CFS_BLOCK_FLAGS = $03CA             ;; the last block's flag: bit 0 protected, bit 6 empty, bit 7 the last block
CFS_BLOCK_SPARE = $03CB             ;; the last block's four spare bytes
CFS_HEADER_CRC = $03CF              ;; the last block's header CRC, two bytes
CFS_BLOCK_GAP = $03D1               ;; the gap between sequential blocks, as *OPT 3 sets it
CFS_SEARCH_NAME = $03D2             ;; &03D2-&03DC, the name of the file being searched for, ending in zero
CFS_NEXT_BLOCK = $03DD              ;; the number of the next block BGET expects, two bytes
CFS_LAST_FLAGS = $03DF              ;; the flag of the last block read, for the catalogue's new lines
KEYBOARD_BUFFER = $03E0             ;; &03E0-&03FF, the keyboard buffer

; ---------------------------------------------------------------------------------------------------------------------
; Pages four to thirteen
; ---------------------------------------------------------------------------------------------------------------------

TUBE_CODE = $0400                   ;; the Tube host code's entry, which takes a language across the Tube
TUBE_ESCAPE = $0403                 ;; the Tube host code's entry that passes an escape across
TUBE_TRANSFER = $0406               ;; the Tube host code's entry that claims the Tube and starts transfers

SOUND_WORKSPACE = $0800             ;; &0800-&083F, the sound system's workspace
SOUND_BUFFERS = $0840               ;; &0840-&087F, the four sound channels' buffers, sixteen bytes each
PRINTER_BUFFER = $0880              ;; &0880-&08BF, the printer buffer
ENVELOPES = $08C0                   ;; &08C0-&08FF, envelopes 1-4, sixteen bytes each
;; &0900-&09BF as the RS-423 output buffer, or envelopes 5-16. The cassette output buffer is the whole page,
;; &0900-&09FF: <BPUTV_DEFAULT> fills all 256 bytes before writing a block, over <SPEECH_BUFFER>.
OUTPUT_BUFFER = $0900
SPEECH_BUFFER = $09C0               ;; &09C0-&09FF, the speech buffer, which a cassette file being written also uses
INPUT_BUFFER = $0A00                ;; &0A00-&0AFF, the RS-423 or cassette input buffer

;; The soft key buffer: the start offset of soft key n is at SOFT_KEYS+n, its text begins at SOFT_KEYS+1 plus that
;; offset, and SOFT_KEYS+16 is where the free space starts.
SOFT_KEYS = $0B00

FONT_RAM = $0C00                    ;; the font for characters &E0-&FF, eight bytes each; &80-&DF share it until exploded
NMI_ROUTINE = $0D00                 ;; &0D00-&0D9E, the NMI routine, where the NMI vector points
EXTENDED_VECTORS = $0D9F            ;; &0D9F-&0DEF, three bytes per vector: a paged ROM's address and its number
ROM_WORKSPACE_TABLE = $0DF0         ;; a byte for each paged ROM, the page its private workspace starts at

; ---------------------------------------------------------------------------------------------------------------------
; A paged ROM's header, at &8000
; ---------------------------------------------------------------------------------------------------------------------

LANGUAGE_ENTRY = $8000              ;; a paged ROM's language entry
SERVICE_ENTRY = $8003               ;; a paged ROM's service entry
ROM_TYPE = $8006                    ;; a paged ROM's type: bit 7 service, bit 6 language, bit 5 relocation address
COPYRIGHT_OFFSET = $8007            ;; the offset of a paged ROM's copyright string, which begins with a zero
ROM_TITLE = $8009                   ;; a paged ROM's title, after its version number at &8008
