;; ATARI 400/800 EQUATES: THE HARDWARE REGISTERS AND THE OS DATABASE
;;
;; The custom chips' registers (GTIA at $D000, POKEY at $D200, the PIA at $D300 and ANTIC at $D400), the OS's
;; database in zero page and pages two to four, the cartridge headers, and the codes CIO and SIO use. The OS includes
;; this file, and so can cartridges and DOS, so each name here is defined and documented once.
;;
;; Names follow Atari's documentation: the Hardware Manual names the registers, and the OS User's Manual (appendix L,
;; "The database") names and describes each OS variable. Where a register reads as one thing and writes as another,
;; both names are here at the same address.

; ---------------------------------------------------------------------------------------------------------------------
; GTIA (CTIA on early machines), $D000-$D01F
; ---------------------------------------------------------------------------------------------------------------------

HPOSP0 = $D000                      ;; player 0's horizontal position (write)
M0PF = HPOSP0                       ;; missile 0's collisions with the playfield (read)
HPOSP1 = $D001                      ;; player 1's horizontal position (write)
HPOSP2 = $D002                      ;; player 2's horizontal position (write)
HPOSP3 = $D003                      ;; player 3's horizontal position (write)
HPOSM0 = $D004                      ;; missile 0's horizontal position (write)
HPOSM1 = $D005                      ;; missile 1's horizontal position (write)
HPOSM2 = $D006                      ;; missile 2's horizontal position (write)
HPOSM3 = $D007                      ;; missile 3's horizontal position (write)
SIZEP0 = $D008                      ;; player 0's width (write)
SIZEP1 = $D009                      ;; player 1's width (write)
SIZEP2 = $D00A                      ;; player 2's width (write)
SIZEP3 = $D00B                      ;; player 3's width (write)
SIZEM = $D00C                       ;; the missiles' widths (write)
GRAFP0 = $D00D                      ;; player 0's graphics, when not from DMA (write)
GRAFP1 = $D00E                      ;; player 1's graphics (write)
GRAFP2 = $D00F                      ;; player 2's graphics (write)
GRAFP3 = $D010                      ;; player 3's graphics (write)
TRIG0 = GRAFP3                      ;; joystick 0's trigger, 0 when pressed (read)
TRIG1 = $D011                       ;; joystick 1's trigger (read)
GRAFM = TRIG1                       ;; the missiles' graphics (write)
TRIG2 = $D012                       ;; joystick 2's trigger (read)
COLPM0 = TRIG2                      ;; player and missile 0's colour (write)
TRIG3 = $D013                       ;; joystick 3's trigger (read)
COLPM1 = TRIG3                      ;; player and missile 1's colour (write)
PAL = $D014                         ;; the video standard: bits 1-3 are 0 on a PAL machine and set on NTSC (read)
COLPM2 = PAL                        ;; player and missile 2's colour (write)
COLPM3 = $D015                      ;; player and missile 3's colour (write)
COLPF0 = $D016                      ;; playfield colour 0 (write)
COLPF1 = $D017                      ;; playfield colour 1 (write)
COLPF2 = $D018                      ;; playfield colour 2 (write)
COLPF3 = $D019                      ;; playfield colour 3 (write)
COLBK = $D01A                       ;; the background colour (write)
PRIOR = $D01B                       ;; the priorities of players, missiles and playfield, and GTIA's modes (write)
VDELAY = $D01C                      ;; the vertical delay of players and missiles (write)
GRACTL = $D01D                      ;; graphics control: player and missile DMA, and latched triggers (write)
HITCLR = $D01E                      ;; clears the collision registers (write)

;; The console register: reads START (bit 0), SELECT (bit 1) and OPTION (bit 2), each 0 while held, and writes the
;; console keys' pull-ups and the speaker (bit 3), which the OS clicks for keys and buzzes for the cassette's beeps.
CONSOL = $D01F

; ---------------------------------------------------------------------------------------------------------------------
; POKEY, $D200-$D20F
; ---------------------------------------------------------------------------------------------------------------------

AUDF1 = $D200                       ;; audio channel 1's frequency divider (write)
POT0 = AUDF1                        ;; paddle 0's position (read)
AUDC1 = $D201                       ;; audio channel 1's distortion and volume (write)
POT1 = AUDC1                        ;; paddle 1's position (read)
AUDF2 = $D202                       ;; audio channel 2's frequency divider (write)
POT2 = AUDF2                        ;; paddle 2's position (read)
AUDC2 = $D203                       ;; audio channel 2's distortion and volume (write)
POT3 = AUDC2                        ;; paddle 3's position (read)
AUDF3 = $D204                       ;; audio channel 3's frequency divider (write)
POT4 = AUDF3                        ;; paddle 4's position (read)
AUDC3 = $D205                       ;; audio channel 3's distortion and volume (write)
POT5 = AUDC3                        ;; paddle 5's position (read)
AUDF4 = $D206                       ;; audio channel 4's frequency divider (write)
POT6 = AUDF4                        ;; paddle 6's position (read)
AUDC4 = $D207                       ;; audio channel 4's distortion and volume (write)
POT7 = AUDC4                        ;; paddle 7's position (read)
AUDCTL = $D208                      ;; audio control: the clocks, the joined channels and the filters (write)
ALLPOT = AUDCTL                     ;; which paddles are still being read, a bit each (read)
STIMER = $D209                      ;; restarts the audio channels' timers (write)
KBCODE = STIMER                     ;; the code of the last key pressed (read)
SKREST = $D20A                      ;; clears the serial port's error bits in SKSTAT (write)
RANDOM = SKREST                     ;; the top 8 bits of the 17-bit polynomial counter, a random number (read)
POTGO = $D20B                       ;; starts reading the paddles (write)
SEROUT = $D20D                      ;; the next byte the serial port sends (write)
SERIN = SEROUT                      ;; the byte the serial port received (read)

;; The interrupt enables (write) and the pending interrupts (read as IRQST, each 0 while pending): BREAK (bit 7),
;; a key (6), serial input ready (5), serial output needed (4), serial output finished (3), and timers 4, 2 and 1
;; (2, 1 and 0). Writing 0 to a bit clears its interrupt. The OS keeps the enables it wants in POKMSK.
IRQEN = $D20E

IRQST = IRQEN                       ;; the pending interrupts, each bit 0 while pending (read)

;; Serial port control (write): the serial mode and clocks in bits 4-6, two-tone mode for the cassette in bit 3, a
;; forced break in bit 7, and keyboard debounce and scanning in bits 0-1. The OS keeps a copy in SSKCTL.
SKCTL = $D20F

SKSTAT = SKCTL                      ;; serial port and keyboard status, each bit 0 when true (read)

; ---------------------------------------------------------------------------------------------------------------------
; The 6520 PIA, $D300-$D303
; ---------------------------------------------------------------------------------------------------------------------

PORTA = $D300                       ;; joysticks 0 and 1, four bits each, 0 for each direction pushed
PORTB = $D301                       ;; joysticks 2 and 3
PACTL = $D302                       ;; port A's control: bit 3 is CA2, the cassette motor, on when 0
PBCTL = $D303                       ;; port B's control: bit 3 is CB2, the serial bus's command line, asserted when 0

; ---------------------------------------------------------------------------------------------------------------------
; ANTIC, $D400-$D40F
; ---------------------------------------------------------------------------------------------------------------------

DMACTL = $D400                      ;; DMA control: the playfield width, and display list and player DMA (write)
CHACTL = $D401                      ;; character control: inverse video and upside-down characters (write)
DLISTL = $D402                      ;; the display list's address, low byte (write)
DLISTH = $D403                      ;; the display list's address, high byte (write)
HSCROL = $D404                      ;; horizontal fine scroll (write)
VSCROL = $D405                      ;; vertical fine scroll (write)
PMBASE = $D407                      ;; the player and missile graphics' page (write)
CHBASE = $D409                      ;; the character set's page (write)
WSYNC = $D40A                       ;; any write halts the CPU until the end of the scan line (write)
VCOUNT = $D40B                      ;; the scan line being drawn, divided by 2 (read)
PENH = $D40C                        ;; the light pen's horizontal position (read)
PENV = $D40D                        ;; the light pen's vertical position (read)
NMIEN = $D40E                       ;; the NMI enables: display list interrupts (bit 7), vertical blank (6) (write)

;; The NMI status (read): a display list interrupt (bit 7), the vertical blank (bit 6) or SYSTEM RESET (bit 5). Any
;; write clears it, as NMIRES.
NMIST = $D40F

NMIRES = NMIST                      ;; clears NMIST (write)

; ---------------------------------------------------------------------------------------------------------------------
; Zero page, $0000-$007F
; ---------------------------------------------------------------------------------------------------------------------

LINZBS = $00                        ;; reserved for the linkage of multi-processor systems (2 bytes)
CASINI = $02                        ;; where a cassette boot's program initializes, then on SYSTEM RESET (2 bytes)
RAMLO = $04                         ;; the start-up memory test's pointer; then the disk boot's load address (2 bytes)
TRAMSZ = $06                        ;; the start-up's RAM size, in pages; then whether a left cartridge is there
TSTDAT = $07                        ;; the start-up memory test's data; then whether a right cartridge is there
WARMST = $08                        ;; the warm start flag: 0 on power-up, $FF after SYSTEM RESET

;; The boot flags: bit 0 set after a disk boot succeeded and bit 1 after a cassette boot, so that SYSTEM RESET calls
;; the booted program's initialization again. The manual names it BOOT?, which no assembler accepts.
BOOTQ = $09

DOSVEC = $0A                        ;; where the OS jumps for DOS, or for a cartridge or cassette program (2 bytes)
DOSINI = $0C                        ;; where a disk boot's program initializes, then on SYSTEM RESET (2 bytes)
APPMHI = $0E                        ;; the top of the application's memory, below which the screen must not go (2 bytes)
POKMSK = $10                        ;; the copy of POKEY's interrupt enables, IRQEN, which the interrupt handlers keep
BRKKEY = $11                        ;; 0 when BREAK has been pressed
RTCLOK = $12                        ;; the clock, counted up each vertical blank, high byte first (3 bytes)
BUFADR = $15                        ;; the disk handler's buffer pointer (2 bytes)
ICCOMT = $17                        ;; the command CIO is running, with any device-specific command as $0E
DSKFMS = $18                        ;; DOS's file manager's pointer (2 bytes)
DSKUTL = $1A                        ;; DOS's utility pointer (2 bytes)
PTIMOT = $1C                        ;; the printer's timeout, from its status
PBPNT = $1D                         ;; the printer buffer's position
PBUFSZ = $1E                        ;; the printer buffer's size: 40 normally, 29 sideways, 20 for double width
PTEMP = $1F                         ;; the printer handler's character being written

; The zero-page IOCB: CIO copies the IOCB in use here for the handler, and back when it returns.

ICHIDZ = $20                        ;; the zero-page IOCB's handler index, into HATABS
ICDNOZ = $21                        ;; the zero-page IOCB's device number
ICCOMZ = $22                        ;; the zero-page IOCB's command
ICSTAZ = $23                        ;; the zero-page IOCB's status
ICBALZ = $24                        ;; the zero-page IOCB's buffer address, low byte
ICBAHZ = $25                        ;; the zero-page IOCB's buffer address, high byte
ICPTLZ = $26                        ;; the zero-page IOCB's put-byte routine, less 1, low byte
ICPTHZ = $27                        ;; the zero-page IOCB's put-byte routine, less 1, high byte
ICBLLZ = $28                        ;; the zero-page IOCB's buffer length, low byte
ICBLHZ = $29                        ;; the zero-page IOCB's buffer length, high byte
ICAX1Z = $2A                        ;; the zero-page IOCB's auxiliary byte 1, the open mode
ICAX2Z = $2B                        ;; the zero-page IOCB's auxiliary byte 2
ICSPRZ = $2C                        ;; CIO's working storage, which it also uses for the handler's vector (4 bytes)
ICIDNO = $2E                        ;; the IOCB number in use, times 16
CIOCHR = $2F                        ;; the byte CIO is reading or writing, for a single-byte call

; SIO's variables.

STATUS = $30                        ;; the status of the SIO operation in progress
CHKSUM = $31                        ;; the frame's checksum, the sum with end-around carry of its bytes
BUFRLO = $32                        ;; the next byte's address in the buffer, low byte
BUFRHI = $33                        ;; the next byte's address in the buffer, high byte
BFENLO = $34                        ;; the address after the buffer's last byte, low byte
BFENHI = $35                        ;; the address after the buffer's last byte, high byte
CRETRY = $36                        ;; the command frame's retries left, from 13
DRETRY = $37                        ;; the whole command's retries left, from 1
BUFRFL = $38                        ;; set when all but the checksum of a received frame is in
RECVDN = $39                        ;; set when the last byte of a received frame is in
XMTDON = $3A                        ;; set when the last byte of a sent frame is out
CHKSNT = $3B                        ;; set when the frame's checksum has been sent
NOCKSM = $3C                        ;; set when the next frame received has no checksum

; The cassette handler's variables, and DOS's and the screen's.

BPTR = $3D                          ;; the cassette buffer's position
FTYPE = $3E                         ;; the cassette's gaps between records: 0 for long, $80 for short
FEOF = $3F                          ;; set when the cassette handler has reached the end of the file
FREQ = $40                          ;; the beep count, for the cassette's prompts
SOUNDR = $41                        ;; 0 for quiet serial I/O, otherwise SIO plays it on channel 4 (and 1, 2 for tape)
CRITIC = $42                        ;; nonzero in a critical section, when the vertical blank does only its first stage
FMSZPG = $43                        ;; DOS's file manager's zero page (7 bytes)
CKEY = $4A                          ;; set when START was held at power-up, to boot the cassette
CASSBT = $4B                        ;; set during a cassette boot
DSTAT = $4C                         ;; the display handler's status
ATRACT = $4D                        ;; attract mode: counts every 4 s without a key; dims the colours when negative
DRKMSK = $4E                        ;; the mask attract mode ANDs with each colour: $FE normally, $F6 when dimmed
COLRSH = $4F                        ;; what attract mode exclusive-ORs with each colour, from RTCLOK
TMPCHR = $50                        ;; the display handler's working byte
HOLD1 = $51                         ;; the display handler's working byte
LMARGN = $52                        ;; the text window's left margin, 2 at power-up
RMARGN = $53                        ;; the text window's right margin, 39 at power-up
ROWCRS = $54                        ;; the cursor's row
COLCRS = $55                        ;; the cursor's column (2 bytes)
DINDEX = $57                        ;; the screen's display mode, the GRAPHICS number
SAVMSC = $58                        ;; the address of the screen's top left corner (2 bytes)
OLDROW = $5A                        ;; the row of the last point drawn, where DRAWTO starts
OLDCOL = $5B                        ;; the column of the last point drawn (2 bytes)
OLDCHR = $5D                        ;; the data under the text cursor
OLDADR = $5E                        ;; the address of the text cursor in screen memory (2 bytes)
NEWROW = $60                        ;; the row DRAWTO goes to
NEWCOL = $61                        ;; the column DRAWTO goes to (2 bytes)
LOGCOL = $63                        ;; the cursor's column in its logical line, 0-119
ADRESS = $64                        ;; the display handler's working pointer (2 bytes)
TOADR = $66                         ;; the display handler's working pointer and multiply result (2 bytes)
SAVADR = $68                        ;; the display handler's working pointer (2 bytes)
RAMTOP = $6A                        ;; the top of usable RAM, in pages, below which the screen goes
BUFCNT = $6B                        ;; the length of the logical line the editor is returning
BUFSTR = $6C                        ;; the editor's pointer into the logical line (2 bytes)
BITMSK = $6E                        ;; the mask of a TABMAP or LOGMAP bit, for the map routines
SHFAMT = $6F                        ;; the pixel's shift in its byte
ROWAC = $70                         ;; DRAWTO's row accumulator (2 bytes)
COLAC = $72                         ;; DRAWTO's column accumulator (2 bytes)
ENDPT = $74                         ;; DRAWTO's count of points, the larger of the changes (2 bytes)
DELTAR = $76                        ;; DRAWTO's change in rows
DELTAC = $77                        ;; DRAWTO's change in columns (2 bytes)
ROWINC = $79                        ;; DRAWTO's row step, 1 or -1
COLINC = $7A                        ;; DRAWTO's column step, 1 or -1
SWPFLG = $7B                        ;; $FF while the text window's variables are swapped in for a split screen
HOLDCH = $7C                        ;; the keyboard's character before the CTRL and SHIFT tests
INSDAT = $7D                        ;; the display handler's working byte for inserts and deletes
COUNTR = $7E                        ;; DRAWTO's iteration counter (2 bytes)

; ---------------------------------------------------------------------------------------------------------------------
; Page two: the interrupt vectors, the timers, the shadow registers and the screen editor
; ---------------------------------------------------------------------------------------------------------------------

VDSLST = $0200                      ;; the display list interrupt's vector, for the NMI
VPRCED = $0202                      ;; the serial bus's proceed line's interrupt vector (the PIA's CA1)
VINTER = $0204                      ;; the serial bus's interrupt line's interrupt vector (the PIA's CB1)
VBREAK = $0206                      ;; the BRK instruction's vector
VKEYBD = $0208                      ;; the keyboard interrupt's vector
VSERIN = $020A                      ;; the serial input ready interrupt's vector
VSEROR = $020C                      ;; the serial output needed interrupt's vector
VSEROC = $020E                      ;; the serial output finished interrupt's vector
VTIMR1 = $0210                      ;; POKEY timer 1's interrupt vector
VTIMR2 = $0212                      ;; POKEY timer 2's interrupt vector
VTIMR4 = $0214                      ;; POKEY timer 4's interrupt vector
VIMIRQ = $0216                      ;; the IRQ's vector, through which every IRQ is handled
CDTMV1 = $0218                      ;; system timer 1's count, in vertical blanks; SIO's timeouts (2 bytes)
CDTMV2 = $021A                      ;; system timer 2's count (2 bytes)
CDTMV3 = $021C                      ;; system timer 3's count, which clears CDTMF3 at zero (2 bytes)
CDTMV4 = $021E                      ;; system timer 4's count, which clears CDTMF4 at zero (2 bytes)
CDTMV5 = $0220                      ;; system timer 5's count, which clears CDTMF5 at zero (2 bytes)
VVBLKI = $0222                      ;; the immediate vertical blank's vector
VVBLKD = $0224                      ;; the deferred vertical blank's vector
CDTMA1 = $0226                      ;; where system timer 1 jumps at zero (2 bytes)
CDTMA2 = $0228                      ;; where system timer 2 jumps at zero (2 bytes)
CDTMF3 = $022A                      ;; system timer 3's flag, cleared when it counts to zero
SRTIMR = $022B                      ;; the keyboard's auto-repeat timer
CDTMF4 = $022C                      ;; system timer 4's flag
INTEMP = $022D                      ;; SETVBV's working byte
CDTMF5 = $022E                      ;; system timer 5's flag
SDMCTL = $022F                      ;; the shadow of DMACTL, which the vertical blank copies
SDLSTL = $0230                      ;; the shadow of DLISTL
SDLSTH = $0231                      ;; the shadow of DLISTH
SSKCTL = $0232                      ;; the shadow of SKCTL, which the OS writes along with it
LPENH = $0234                       ;; the shadow of PENH
LPENV = $0235                       ;; the shadow of PENV
BRKKY = $0236                       ;; the BREAK key interrupt's vector, in rev. B (2 bytes)
CDEVIC = $023A                      ;; the command frame's device: DDEVIC + DUNIT - 1
CCOMND = $023B                      ;; the command frame's command, from DCOMND
CAUX1 = $023C                       ;; the command frame's first auxiliary byte, from DAUX1
CAUX2 = $023D                       ;; the command frame's second auxiliary byte, from DAUX2
TEMP = $023E                        ;; SIO's one-byte response: ACK, NAK, COMPLETE or ERROR
ERRFLG = $023F                      ;; set when a device answered ERROR
DFLAGS = $0240                      ;; the first boot sector's flags byte
DBSECT = $0241                      ;; the number of boot sectors, from the first boot sector
BOOTAD = $0242                      ;; where the boot sectors load, from the first boot sector (2 bytes)
COLDST = $0244                      ;; nonzero until the start-up has finished, so that SYSTEM RESET starts again
DSKTIM = $0246                      ;; the disk's format timeout, in seconds, from its status; other commands take 7
LINBUF = $0247                      ;; the screen editor's buffer for a line it moves (40 bytes)
GPRIOR = $026F                      ;; the shadow of PRIOR
PADDL0 = $0270                      ;; the shadow of POT0; PADDL0-PADDL7 are read each vertical blank
PADDL1 = $0271                      ;; the shadow of POT1
PADDL2 = $0272                      ;; the shadow of POT2
PADDL3 = $0273                      ;; the shadow of POT3
PADDL4 = $0274                      ;; the shadow of POT4
PADDL5 = $0275                      ;; the shadow of POT5
PADDL6 = $0276                      ;; the shadow of POT6
PADDL7 = $0277                      ;; the shadow of POT7
STICK0 = $0278                      ;; joystick 0's shadow, a nibble from PORTA
STICK1 = $0279                      ;; joystick 1's shadow
STICK2 = $027A                      ;; joystick 2's shadow
STICK3 = $027B                      ;; joystick 3's shadow
PTRIG0 = $027C                      ;; paddle 0's trigger, from the joystick ports, 0 when pressed
PTRIG1 = $027D                      ;; paddle 1's trigger
PTRIG2 = $027E                      ;; paddle 2's trigger
PTRIG3 = $027F                      ;; paddle 3's trigger
PTRIG4 = $0280                      ;; paddle 4's trigger
PTRIG5 = $0281                      ;; paddle 5's trigger
PTRIG6 = $0282                      ;; paddle 6's trigger
PTRIG7 = $0283                      ;; paddle 7's trigger
STRIG0 = $0284                      ;; the shadow of TRIG0
STRIG1 = $0285                      ;; the shadow of TRIG1
STRIG2 = $0286                      ;; the shadow of TRIG2
STRIG3 = $0287                      ;; the shadow of TRIG3
CSTAT = $0288                       ;; the cassette's status
WMODE = $0289                       ;; the cassette's mode: $80 when writing, 0 when reading
BLIM = $028A                        ;; the number of data bytes in the cassette buffer
TXTROW = $0290                      ;; the text window's cursor row
TXTCOL = $0291                      ;; the text window's cursor column (2 bytes)
TINDEX = $0293                      ;; the text window's display mode
TXTMSC = $0294                      ;; the text window's screen address (2 bytes)
TXTOLD = $0296                      ;; the text window's OLDROW, OLDCOL, OLDCHR and OLDADR (6 bytes)
TMPX1 = $029C                       ;; the display handler's working byte
HOLD3 = $029D                       ;; the display handler's working byte
SUBTMP = $029E                      ;; the display handler's working byte
HOLD2 = $029F                       ;; the display handler's working byte
DMASK = $02A0                       ;; the mask of a pixel, for the display mode
TMPLBT = $02A1                      ;; the display handler's working byte
ESCFLG = $02A2                      ;; set after ESC, so the next character is shown rather than obeyed
TABMAP = $02A3                      ;; the tab stops, a bit for each column of a logical line (15 bytes)
LOGMAP = $02B2                      ;; which screen lines start a logical line, a bit each (4 bytes)
INVFLG = $02B6                      ;; $80 when inverse video is on, from the Atari key
FILFLG = $02B7                      ;; set while DRAWTO is filling
TMPROW = $02B8                      ;; the display handler's working row
TMPCOL = $02B9                      ;; the display handler's working column (2 bytes)
SCRFLG = $02BB                      ;; the number of lines scrolled off the top during a logical line's insertion
HOLD4 = $02BC                       ;; the display handler's working byte
HOLD5 = $02BD                       ;; the display handler's working byte
SHFLOK = $02BE                      ;; the caps lock: 0 for lower case, $40 for upper, $80 for CTRL
BOTSCR = $02BF                      ;; the number of text lines on the screen: 24, or 4 in a split screen
PCOLR0 = $02C0                      ;; the shadow of COLPM0
PCOLR1 = $02C1                      ;; the shadow of COLPM1
PCOLR2 = $02C2                      ;; the shadow of COLPM2
PCOLR3 = $02C3                      ;; the shadow of COLPM3
COLOR0 = $02C4                      ;; the shadow of COLPF0
COLOR1 = $02C5                      ;; the shadow of COLPF1
COLOR2 = $02C6                      ;; the shadow of COLPF2
COLOR3 = $02C7                      ;; the shadow of COLPF3
COLOR4 = $02C8                      ;; the shadow of COLBK
RUNAD = $02E0                       ;; where a binary load file runs, once loaded (2 bytes)
INITAD = $02E2                      ;; what a binary load file calls after a segment (2 bytes)
RAMSIZ = $02E4                      ;; the top of RAM, in pages, as the start-up test found it
MEMTOP = $02E5                      ;; the top of free memory, below the screen (2 bytes)
MEMLO = $02E7                       ;; the bottom of free memory, above the OS and DOS (2 bytes)
DVSTAT = $02EA                      ;; the status a STATUS command returns from the device (4 bytes)
CBAUDL = $02EE                      ;; the cassette's baud rate as POKEY's divider, low byte
CBAUDH = $02EF                      ;; the cassette's baud rate as POKEY's divider, high byte
CRSINH = $02F0                      ;; nonzero to hide the text cursor
KEYDEL = $02F1                      ;; the keyboard's debounce count
CH1 = $02F2                         ;; the previous key's code, for the debounce
CHACT = $02F3                       ;; the shadow of CHACTL
CHBAS = $02F4                       ;; the shadow of CHBASE
CHAR = $02FA                        ;; the internal code of the last character read or written
ATACHR = $02FB                      ;; the ATASCII character being read or written, or the colour to draw
CH = $02FC                          ;; the key's code from KBCODE, or $FF for none
FILDAT = $02FD                      ;; the colour a fill draws in
DSPFLG = $02FE                      ;; nonzero to show control characters rather than obey them
SSFLAG = $02FF                      ;; the start/stop flag, which CTRL+1 toggles to pause the screen

; ---------------------------------------------------------------------------------------------------------------------
; Page three: the device control block, CIO's handler table and the IOCBs
; ---------------------------------------------------------------------------------------------------------------------

DDEVIC = $0300                      ;; the device control block's serial bus ID, $31 for disks
DUNIT = $0301                       ;; the device control block's unit number, 1-4 for D1:-D4:
DCOMND = $0302                      ;; the device control block's command, such as 'R' or 'W'
DSTATS = $0303                      ;; the data direction ($40 read, $80 write) going in, the status coming out
DBUFLO = $0304                      ;; the device control block's buffer address, low byte
DBUFHI = $0305                      ;; the device control block's buffer address, high byte
DTIMLO = $0306                      ;; the device control block's timeout, in about seconds
DUNUSE = $0307                      ;; unused in the device control block
DBYTLO = $0308                      ;; the device control block's byte count, low byte
DBYTHI = $0309                      ;; the device control block's byte count, high byte
DAUX1 = $030A                       ;; the device control block's first auxiliary byte, the sector's low byte for a disk
DAUX2 = $030B                       ;; the device control block's second auxiliary byte
TIMER1 = $030C                      ;; the cassette's baud timing: VCOUNT and RTCLOK at the leader's start (2 bytes)
ADDCOR = $030E                      ;; the cassette's baud calculation's correction
CASFLG = $030F                      ;; set by a cassette read, and left set until SIO's next bus command
TIMER2 = $0310                      ;; the cassette's baud timing at the leader's end (2 bytes)
TEMP1 = $0312                       ;; SIO's working storage (2 bytes)
TEMP2 = $0314                       ;; SIO's working byte
TEMP3 = $0315                       ;; SIO's working byte
SAVIO = $0316                       ;; the serial port's input level, which the cassette's baud measurement watches
TIMFLG = $0317                      ;; SIO's timeout flag, cleared by system timer 1 when an operation takes too long
STACKP = $0318                      ;; SIO's stack pointer at entry, to return from wherever it fails
TSTAT = $0319                       ;; SIO's working status

;; The handler address table: up to 12 devices, each a one-letter name and the address of its handler's table of
;; vectors, ending with a 0. The OS puts P:, C:, E:, S: and K: here at power-up, and DOS adds D:.
HATABS = $031A

; Each IOCB is 16 bytes; IOCB 0 is the screen editor's, opened by the OS.

ICHID = $0340                       ;; IOCB 0's handler index into HATABS, $FF when closed
ICDNO = $0341                       ;; IOCB 0's device number
ICCOM = $0342                       ;; IOCB 0's command
ICSTA = $0343                       ;; IOCB 0's status
ICBAL = $0344                       ;; IOCB 0's buffer address, low byte
ICBAH = $0345                       ;; IOCB 0's buffer address, high byte
ICPTL = $0346                       ;; IOCB 0's put-byte routine, less 1, low byte
ICPTH = $0347                       ;; IOCB 0's put-byte routine, less 1, high byte
ICBLL = $0348                       ;; IOCB 0's buffer length, low byte
ICBLH = $0349                       ;; IOCB 0's buffer length, high byte
ICAX1 = $034A                       ;; IOCB 0's auxiliary byte 1, the open mode
ICAX2 = $034B                       ;; IOCB 0's auxiliary byte 2
ICAX3 = $034C                       ;; IOCB 0's auxiliary byte 3
ICAX4 = $034D                       ;; IOCB 0's auxiliary byte 4
ICAX5 = $034E                       ;; IOCB 0's auxiliary byte 5
ICAX6 = $034F                       ;; IOCB 0's auxiliary byte 6
IOCB_SIZE = $10                     ;; the size of an IOCB
IOCB_COUNT = 8                      ;; the number of IOCBs, $0340-$03BF

PRNBUF = $03C0                      ;; the printer handler's buffer (40 bytes)
CASBUF = $03FD                      ;; the cassette's buffer: two speed bytes, a control byte, 128 data bytes

; ---------------------------------------------------------------------------------------------------------------------
; The floating point package's registers and buffers, $00D4-$00FF and page five
; ---------------------------------------------------------------------------------------------------------------------

; A floating point number is six bytes: an exponent byte (bit 7 the sign, bits 0-6 a power of 100 biased by 64) and
; five bytes of BCD mantissa, ten digits, with the decimal point after the first byte.

FP_SIZE = 6                         ;; the bytes in a floating point number
FP_MANTISSA_BYTES = 5               ;; the mantissa's bytes, each two BCD digits
FP_SIGN = $80                       ;; the exponent byte's bit that is set for a negative number
FP_EXPONENT_BIAS = $40              ;; the exponent byte of 100^0: the power of 100 is the byte less this

FR0 = $D4                           ;; FP register 0, every routine's operand and result (6 bytes)
FRE = $DA                           ;; FP register E, the package's own (6 bytes)
FR1 = $E0                           ;; FP register 1, the second operand (6 bytes)
FR2 = $E6                           ;; FP register 2, the package's own (6 bytes)
FRX = $EC                           ;; the digit a mantissa shift moves out, and where AFP was before an E
EEXP = $ED                          ;; the exponent AFP reads after an E
NSIGN = $EE                         ;; the sign of the number AFP reads
ESIGN = $EF                         ;; the sign of the exponent AFP reads
FCHRFLG = $F0                       ;; AFP's first character flag
DIGRT = $F1                         ;; the digits AFP has read to the right of the decimal point
CIX = $F2                           ;; the index of AFP's next character in INBUFF, and FASC's
INBUFF = $F3                        ;; the text AFP reads and FASC writes (2 bytes)
ZTEMP1 = $F5                        ;; the package's temporary storage (2 bytes)
ZTEMP4 = $F7                        ;; the package's temporary storage (2 bytes)
ZTEMP3 = $F9                        ;; the package's temporary storage (2 bytes)
DEGFLG = $FB                        ;; 0 for radians, 6 for degrees, for BASIC's trigonometry
FLPTR = $FC                         ;; the pointer to the FP number FLD0P, FLD1P and FST0P use (2 bytes)
FPTR2 = $FE                         ;; the package's pointer, to PLYEVL's coefficients (2 bytes)
LBPR1 = $057E                       ;; LBUFF's preamble
LBPR2 = $057F                       ;; LBUFF's preamble
LBUFF = $0580                       ;; FASC's text buffer (96 bytes)
PLYARG = $05E0                      ;; PLYEVL's argument, the package's FP register (6 bytes)
FPSCR = $05E6                       ;; the package's FP register (6 bytes)
FPSCR1 = $05EC                      ;; the package's FP register (6 bytes)

; The signs <FP_NUMBER> takes.

FP_POSITIVE = 0                     ;; the sign of a positive <FP_NUMBER>
FP_NEGATIVE = FP_SIGN               ;; the sign of a negative <FP_NUMBER>

;; Emits a floating point number from its sign, its power of 100 and its mantissa's five bytes.
;;
;; The mantissa reads as its ten BCD digits with the point after the first byte, so FP_NUMBER FP_POSITIVE, 0, $03, $16,
;; $22, $77, $66 is 03.16227766, sqrt(10), and FP_NUMBER FP_NEGATIVE, -1, $51, $70, $49, $47, $08 is -0.5170494708.
;; Parameters: sign = FP_POSITIVE or FP_NEGATIVE, power = the power of 100 (-64 to 63), m1 = the first mantissa byte,
;;   the integer part's two digits, m2 = the second, m3 = the third, m4 = the fourth, m5 = the fifth
.macro FP_NUMBER sign, power, m1, m2, m3, m4, m5
    .byte (sign) | (FP_EXPONENT_BIAS + (power)), m1, m2, m3, m4, m5
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; The cartridge headers
; ---------------------------------------------------------------------------------------------------------------------

; The last six bytes of each cartridge slot tell the OS what is there. The left slot's (A) end at $BFFF, the right
; slot's (B) at $9FFF.

CARTCS = $BFFA                      ;; the left cartridge's start address, where the OS jumps for it (2 bytes)
CART = $BFFC                        ;; 0 when a left cartridge is there; RAM or an empty slot reads otherwise
CARTFG = $BFFD                      ;; the left cartridge's flags: boot the disk (bit 0), run (2), diagnostic (7)
CARTAD = $BFFE                      ;; the left cartridge's initialization address, called at start-up (2 bytes)
CARTCSB = $9FFA                     ;; the right cartridge's start address (2 bytes)
CARTB = $9FFC                       ;; 0 when a right cartridge is there
CARTFGB = $9FFD                     ;; the right cartridge's flags, as CARTFG's
CARTADB = $9FFE                     ;; the right cartridge's initialization address (2 bytes)

; The cartridge flags, in CARTFG and CARTFGB (bit 7, a diagnostic cartridge, rev. B tests with BPL).

CART_BOOT_DISK = $01                ;; boot the disk before starting the cartridge
CART_RUN = $04                      ;; start the cartridge, through CARTCS or CARTCSB
CART_DIAGNOSTIC = $80               ;; a diagnostic cartridge, which takes over before the memory test

; ---------------------------------------------------------------------------------------------------------------------
; Bits and codes the OS's parts share
; ---------------------------------------------------------------------------------------------------------------------

; POKEY's interrupts, a bit each in IRQEN and IRQST (and in POKMSK, the OS's copy of IRQEN).

IRQ_BREAK = %10000000               ;; the BREAK key
IRQ_KEY = %01000000                 ;; a key other than BREAK and the console keys
IRQ_SERIAL_INPUT = %00100000        ;; serial input ready: a byte has arrived (VSERIN)
IRQ_SERIAL_OUTPUT = %00010000       ;; serial output needed: POKEY wants the next byte to send (VSEROR)
IRQ_SERIAL_DONE = %00001000         ;; serial output finished: the last byte has gone (VSEROC)
IRQ_TIMER_4 = %00000100             ;; POKEY timer 4 (VTIMR4)
IRQ_TIMER_2 = %00000010             ;; POKEY timer 2 (VTIMR2)
IRQ_TIMER_1 = %00000001             ;; POKEY timer 1 (VTIMR1)

; ANTIC's NMIs, a bit each in NMIEN and NMIST.

NMI_DLI = %10000000                 ;; a display list interrupt (VDSLST)
NMI_VBLANK = %01000000              ;; the vertical blank (VVBLKI)
NMI_RESET = %00100000               ;; SYSTEM RESET (NMIST only)

; The serial bus's device IDs, in DDEVIC, and the data's direction, in DSTATS.

DISK_ID = $31                       ;; drive 1; SIO adds DUNIT - 1 for D2: to D4:
PRINTER_ID = $40                    ;; the printer
CASSETTE_ID = $60                   ;; the cassette, which SIO drives itself rather than over the bus
DCB_RECEIVE = $40                   ;; the device sends data to the computer
DCB_SEND = $80                      ;; the computer sends data to the device

; ATASCII's control characters that the OS's parts send or test for.

EOL = $9B                           ;; the end of line, which RETURN types and which ends a record
CLEAR_SCREEN = $7D                  ;; clear the screen

; ---------------------------------------------------------------------------------------------------------------------
; CIO's commands and the status codes
; ---------------------------------------------------------------------------------------------------------------------

; The commands, in ICCOM. Those from $0E up are the device's own, passed to its handler's SPECIAL vector.

COPN = $03                          ;; open a device or file
CGTXTR = $05                        ;; get a record: bytes up to and including an end of line
CGBINR = $07                        ;; get bytes
CPTXTR = $09                        ;; put a record
CPBINR = $0B                        ;; put bytes
CCLOSE = $0C                        ;; close
CSTATUS = $0D                       ;; get the device's status
CDRAW = $11                         ;; the screen's DRAWTO
CFILL = $12                         ;; the screen's FILL

; The open modes, in ICAX1.

OREAD = $04                         ;; open for reading
OWRIT = $08                         ;; open for writing
OSPLIT = $10                        ;; the screen: a text window below the graphics
OCLEAR = $20                        ;; the screen: don't clear it

; The status codes, in ICSTA and DSTATS. 1 is success; from $80 up, each is an error.

SUCCES = $01                        ;; the operation succeeded
BRKABT = $80                        ;; BREAK was pressed during the operation
PRVOPN = $81                        ;; the IOCB is already open
NONDEV = $82                        ;; no such device in HATABS
WRONLY = $83                        ;; the IOCB is open for writing only
NVALID = $84                        ;; an invalid command
NOTOPN = $85                        ;; the IOCB isn't open
BADIOC = $86                        ;; an invalid IOCB number
RDONLY = $87                        ;; the IOCB is open for reading only
EOFERR = $88                        ;; the end of the file
TRNRCD = $89                        ;; a record was too long for the buffer, and was cut short
TIMOUT = $8A                        ;; the device didn't answer in time
DNACK = $8B                         ;; the device didn't acknowledge the command
FRMERR = $8C                        ;; a serial frame error
CRSROR = $8D                        ;; the cursor is out of range for the display mode
OVRRUN = $8E                        ;; a serial input overrun
CHKERR = $8F                        ;; a frame's checksum was wrong
DERROR = $90                        ;; the device answered ERROR
BADMOD = $91                        ;; an invalid display mode
FNCNOT = $92                        ;; the function isn't implemented in the handler
SCRMEM = $93                        ;; not enough memory for the display mode
