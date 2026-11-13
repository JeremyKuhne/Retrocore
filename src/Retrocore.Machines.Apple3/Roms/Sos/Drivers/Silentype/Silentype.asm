;; SOS .SILENTYPE DRIVER, RELEASE $1040
;;
;; The Apple III's driver for Apple's Silentype, a thermal printer with a head of seven heating elements. The printer
;; has no controller of its own on the Apple III: the driver runs the mechanism. It builds each character from its own
;; 5-by-7 font (<FONTDOTS>), heats the head's elements one column of dots at a time, steps the head motor and the
;; paper motor, and finds the carriage's left end by the printer's margin switch.
;;
;; The printer hangs on the joystick port. Each change to its lines is 16 bits, the seven dots to heat and the phases
;; of the two stepper motors, which the D VIA's shift register sends out and the analog-select switches at
;; $C058-$C05F then strobe into the printer (<LATCH>). The margin switch reads at $C061 (<MARGINSW>). The D VIA's
;; timer 2 times each step and each burst of heat (<DELAY>).
;;
;; The driver has two layers:
;;
;; - The text layer (SilentypeText.asm) collects the characters a program writes into a line (<LINEBUF>), with the
;;   control characters and commands that change the format along the way, and prints the line when it ends
;;   (<PRINTLINE>). It prints in both directions: a line whose end is nearer the head than its start is printed right
;;   to left, reading the line backward.
;; - The mechanism layer (SilentypeHead.asm) takes one byte at a time (<MECHBYTE>): a column of dots, a move of the
;;   head or the paper, or an order such as finding the margin. The text layer prints through it, and after the G
;;   command or control request 7 a program writes these bytes itself, which is how it prints graphics.
;;
;; Text: the characters $20-$7F print, with bit 7 ignored. Return prints the line and goes back to the left margin,
;; with a line feed when auto line feed is on; Line Feed and Control-N feed the paper a line forward and back; Form
;; Feed prints the line and feeds <FORMLEN> lines; Backspace backs up a character; Control-F prints what is buffered
;; and goes on from there. Other control characters are ignored, except the command character.
;;
;; Commands are the command character (<CMDCHAR>, Escape at first), a letter, and for some an argument byte:
;;
;; - less-than and greater-than print in both directions or left to right only, `E` and `e` turn auto line feed on and off, and `C`
;;   and `c` truncate long lines or wrap them.
;; - `J` n and `K` n set the left and right margins to n character cells; `.` n sets the dots between characters, `^` n
;;   the paper steps per line and `L` n the lines in a form feed, each 0-15.
;; - `H` n moves along the line n dots and `V` n moves the paper n steps, n signed.
;; - `W` n widens the characters (n 0-7, <WIDTHS>), `w` sets the normal width, and `B` and `b` turn bold on and off.
;; - `G` n starts graphics: the bytes that follow go to the mechanism layer until a $48 ends them.
;; - `=` resets the settings and the printer, `?` c makes c the command character, and `F` n does nothing.
;;
;; Requests:
;;
;; - D_OPEN claims the D VIA's control lines, shift register and timer 2 (<SIRTABLE>), then resets the settings and
;;   the printer; it fails with XNODRIVE when the margin switch is never found. D_CLOSE prints what is buffered and
;;   gives the resources back.
;; - D_WRITE prints (<PUTBYTE>); D_READ returns XREQCODE.
;; - D_STATUS 1 returns the 17-byte configuration (<SETTINGS>); 0 and 2 return nothing.
;; - D_CONTROL 0 resets the settings and the printer, 1 sets the configuration, 3 resets the printer alone, 5 sets the
;;   head's timing (six bytes, <HEATTIME>), 6 sets the widths table (eight bytes, <WIDTHS>), and 7 starts graphics; 2
;;   and 4 do nothing.
;; - D_INIT marks the device closed and loads the default settings.
;;
;; One DIB, .SILENTYPE: device type $41, subtype $02, Apple's (manufacturer 1), release $1040, with a 17-byte
;; configuration block (<DEFAULTS>). The copyright text in the code is part of it, not a SOS.DRIVER comment record.
;;
;; The names are ours; the standard parts follow the SOS Device Driver Writer's Guide
;; (https://archive.org/details/Apple_III_SOS_Device_Driver_Writers_Guide), and the joystick port's switches are named
;; as MAME's Apple III has them.
;;
;; Maintained by hand; SOS driver tests check it assembles byte-identically to Apple's .SILENTYPE.

.cpu Mos6502

;; Performs an N-way branch on a switch index, through a table of addresses less one.
;;
;; It loads the index (when given), checks it against the bounds (when given; carry set and falling through when
;; it is larger), then pushes the table entry and returns to it. With `*` as the fourth parameter it pushes the
;; address but falls through instead.
;; Parameters: index = the index's location, or blank for A, bounds = the largest index, or blank for no check,
;;   table = the table of addresses less one, low byte first, stay = `*` to fall through
.macro SWITCH index, bounds, table, stay
    .local M010
    .ifnblank index
    lda index
    .endif
    .ifnblank bounds
    cmp #<(bounds+$01)
    bcs M010
    .endif
    asl a
    tay
    lda table+$01,y
    pha
    lda table,y
    pha
    .if .not .xmatch({stay}, {*})
    rts
    .endif
M010:
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; SOS: the kernel's calls and error codes, and the request block in zero page.
; ---------------------------------------------------------------------------------------------------------------------

;; Allocates system internal resources: A = the table's length, X/Y = its address.
ALLOCSIR = $1913

;; Releases system internal resources: A = the table's length, X/Y = its address.
DEALCSIR = $1916

;; Returns an error from the SOS call: A = the error code. It doesn't return.
SYSERR = $1928

XREQCODE = $20                          ;; the request code is invalid
XCTLCODE = $21                          ;; the control or status code is invalid
XCTLPARM = $22                          ;; the control or status list is the wrong length
XNOTOPEN = $23                          ;; the device is not open
XNORESRC = $25                          ;; a resource the driver needs is not available
XIOERROR = $27                          ;; the printer failed: the margin switch was not found, or a bad graphics byte
XNODRIVE = $28                          ;; no printer answered

D_READ = 0                              ;; request: read
D_WRITE = 1                             ;; request: write
D_STATUS = 2                            ;; request: status
D_CONTROL = 3                           ;; request: control
D_OPEN = 6                              ;; request: open
D_CLOSE = 7                             ;; request: close
D_INIT = 8                              ;; request: initialize, at boot

;; The request block SOS passes to a driver, in zero page.
SOSINT = $C0

REQCODE = SOSINT+$00                    ;; the request code
BUFFER = SOSINT+$02                     ;; read/write: the buffer's address, with its extension byte at XPAGE+BUFFER+1
REQCNT = SOSINT+$04                     ;; read/write: the byte count
CTLSTAT = SOSINT+$02                    ;; status/control: the code
CSLIST = SOSINT+$03                     ;; status/control: the list's address, extension byte at XPAGE+CSLIST+1

;; The count of bytes a write has printed.
WRITECOUNT = SOSINT+$08

;; The extension bytes of zero-page pointers: a pointer at P has its bank pair at XPAGE+P+1, 0 for none.
XPAGE = $1400

; ---------------------------------------------------------------------------------------------------------------------
; The driver's zero page, $E0-$FE, used only while it runs.
; ---------------------------------------------------------------------------------------------------------------------

;; The font table column <GLYPHCOLUMN> reads.
FONTPTR = $E0

;; <PRINTGLYPH>'s copy of <STYLE>, shifted right a column at a time: bit 0 set prints the column twice.
WIDTHBITS = $E2

;; <PRINTGLYPH>'s previous column of dots, for bold.
BOLDCOL = $E3

;; The count of columns, steps or lines a routine has left to move or feed (two bytes for <SENDMOVES>); a column of
;; dots in <PRINTGLYPH>.
MOVECOUNT = $E4

;; A factor of <MULTIPLY>; the paper motion <FEEDPAPER> sends; a distance in <PRINTLINE>.
FACTOR1 = $E6

;; The other factor of <MULTIPLY>; a distance's high byte in <PRINTLINE>.
FACTOR2 = $E7

;; The product of <MULTIPLY> (two bytes); a distance in <PRINTLINE>.
PRODUCT = $E8

;; The character being printed.
CHAR = $EA

;; The columns in a glyph, from <GLYPHWIDTH>.
GLYPHCOLS = $EB

;; The kind of move <SENDMOVES> sends: <M_BACK>, <M_SPACE>, <M_FEED> or <M_UNFEED>.
MOVECMD = $EC

;; The glyph column <GLYPHCOLUMN> reads, 0-4.
GLYPHCOL = $ED

;; The byte a program wrote, and the byte <MECHBYTE> carries out.
INBYTE = $EE

;; The passes of <HOMESTEPS> steps <FINDHOME> has left.
HOMETRIES = $EF

;; The columns or steps a move byte has left (<MECHBYTE>).
REPEATS = $F0

;; The first byte <LATCH> sends: the dots to heat, the top dot in bit 7.
LATCHDOTS = $F1

;; The second byte <LATCH> sends: the head motor's phases in bits 0-3, the paper motor's in bits 4-7.
LATCHPHASES = $F2

;; A move byte shifted left twice: bit 7 set moves the paper, bit 6 set moves with the head's direction or backs the
;; paper up.
MOVEKIND = $F3

;; The error the current write ends with, or 0.
ERRCODE = $F4

;; The dots of a column that were not heated in the two columns before it (<COLUMN>).
NEWDOTS = $F5

;; The cycles <DELAY> waits, low byte first.
DELAYTIME = $F6

;; The column of dots <COLUMN> prints, the top dot in bit 7; a glyph column in bits 0-6 after <GLYPHCOLUMN>.
DOTS = $FB

;; The index in <LINEBUF> of the next entry a left-to-right print reads.
ENTRYINDEX = $FE

; ---------------------------------------------------------------------------------------------------------------------
; Hardware: the D VIA, whose shift register talks to the printer, and the joystick port's switches.
; ---------------------------------------------------------------------------------------------------------------------

;; The D VIA's timer 2 counter, low byte (writing sets the latch).
D_T2CL = $FFD8

;; The D VIA's timer 2 counter, high byte (writing loads the counter and starts it).
D_T2CH = $FFD9

;; The D VIA's shift register: writing a byte shifts it out.
D_SR = $FFDA

;; The D VIA's auxiliary control register: bits 2-4 set the shift register's mode.
D_ACR = $FFDB

;; The D VIA's peripheral control register: how the CA and CB lines work.
D_PCR = $FFDC

;; The D VIA's interrupt flags: bit 2 the shift register, bit 5 timer 2; writing ones clears them.
D_IFR = $FFDD

;; The D VIA's interrupt enables: writing ones with bit 7 clear turns those interrupts off.
D_IER = $FFDE

;; The environment register, the D VIA's port A: bit 7 set runs the system at 1 MHz.
E_REG = $FFDF

ACR_KEEP = $E3                          ;; the auxiliary control bits that keep the shift register's mode out
ACR_SROUT = $18                         ;; the shift register shifting out at the system clock
PCR_KEEP = $01                          ;; the peripheral control bit the driver leaves alone, CA1's edge
PCR_OPEN = $04                          ;; the control lines while the printer is open
PCR_CLOSED = $76                        ;; the control lines when it closes
PORT_IRQS = $3D                         ;; CA2, the shift register, CB2, CB1 and timer 2
IFR_SR = $04                            ;; the shift register's interrupt flag: a byte has gone out
IFR_T2 = $20                            ;; timer 2's interrupt flag
E_1MHZ = $80                            ;; the environment bit that slows the system to 1 MHz

;; Sets bit 0 of the analog-input number, which the printer shares.
AN0_ON = $C059

;; Clears bit 2 of the analog-input number, half the printer's strobe.
AN2_OFF = $C05A

;; Sets bit 2 of the analog-input number.
AN2_ON = $C05B

;; Clears bit 1 of the analog-input number, the printer's strobe.
AN1_OFF = $C05E

;; Sets bit 1 of the analog-input number.
AN1_ON = $C05F

;; Switch input 1: bit 7 set while the head is at the printer's margin switch, the left end of its travel.
MARGINSW = $C061

;; Turns on ENCSEL, one of the system's I/O switches, which the driver sets before it uses the port.
ENCSEL_ON = $C0DD

;; Turns on ENSIO, another of the system's I/O switches, which the driver sets before it uses the port.
ENSIO_ON = $C0DF

; ---------------------------------------------------------------------------------------------------------------------
; The driver's constants.
; ---------------------------------------------------------------------------------------------------------------------

;; The configuration's length in bytes: <DEFAULTS> and <SETTINGS>.
CONFIGLEN = 17

;; The timing settings' length in bytes, which control request 5 sets: <HEATTIME>, <PREHEAT> and <STEPTIME>.
TIMINGLEN = 6

;; The size of <LINEBUF>.
LINEBUFSIZE = 160

;; The line length at which <BUFFERBYTE> prints what is buffered, leaving room for a change's four bytes.
LINEMAX = 151

;; The largest right margin, in dot columns, plus one.
RMARGINMAX = $01F0

;; The extra heating time each line starts with (<EXTRAHEAT>).
LINEHEAT = $0300

;; The cycles of <WAIT>, about 4 milliseconds.
WAITTIME = $0FC0

;; The passes of <HOMESTEPS> steps <FINDHOME> takes looking for the margin switch.
HOMEPASSES = 22

;; The steps in each pass of <FINDHOME>.
HOMESTEPS = 36

;; Both motors' phase patterns at first: two adjacent phases on.
PHASE_START = $03

ASC_BS = $08                            ;; Backspace

IN_TEXT = 0                             ;; <STATE>: text
IN_COMMAND = 1                          ;; <STATE>: the command character came; a letter is next
IN_ARGUMENT = 2                         ;; <STATE>: the command's argument byte is next
IN_GRAPHICS = 3                         ;; <STATE>: bytes go to the mechanism layer

MODE_OVERFLOW = $01                     ;; <MODES>: the line passed the right margin and is being truncated
MODE_AUTOLF = $02                       ;; <MODES>: Return also feeds a line
MODE_TRUNCATE = $04                     ;; <MODES>: truncate lines at the right margin instead of wrapping
MODE_UNIDIR = $80                       ;; <MODES>: print every line left to right

STYLE_BOLD = $80                        ;; <STYLE>: bold

DIR_LEFT = $80                          ;; <DIRECTION>: the head moves left, toward the margin switch

;; A mark in <LINEBUF>: a change of <CHARSPACE>.
;;
;; The marks go around a change made in the middle of a line, so that printing it in either direction makes the change
;; at the right place. A change of a setting is the mark, the old value, the new value and the mark again; a move is
;; the mark, the distance and the mark.
;; See: <REPLAY_SPACING>
MARK_SPACING = $81
MARK_FONT = $82                         ;; a change of <FONT>; nothing makes one
MARK_STYLE = $83                        ;; a change of <STYLE>
MARK_HMOVE = $84                        ;; a move along the line, in dots
MARK_VMOVE = $85                        ;; a move of the paper, in steps

;; Mechanism byte $00-$0F: moves the head 1-15 columns, or 64 for 0, against its direction, without printing.
;; See: <MECHBYTE>
M_BACK = $00
M_SPACE = $10                           ;; $10-$1F: moves the head 1-15 (0: 64) columns in its direction
M_FEED = $20                            ;; $20-$2F: feeds the paper 1-15 (0: 64) steps
M_UNFEED = $30                          ;; $30-$3F: backs the paper up 1-15 (0: 64) steps
M_RESET = $40                           ;; sets up the port and finds the margin
M_HOME = $41                            ;; finds the margin
M_HEADOFF = $46                         ;; releases the head motor
M_PAPEROFF = $47                        ;; releases the paper motor
M_TEXT = $48                            ;; ends graphics: back to text, the head at the left margin
M_DOTS = $80                            ;; $80-$FF: prints a column of dots, bits 0-6, the top in bit 6

;; The entries of <MECHSW>, mechanism bytes $40-$48.
MECHCOUNT = 9

;; The control characters <TEXTBYTE> acts on.
CTLCOUNT = 6

;; The command letters.
CMDCOUNT = 21

;; The entries of <WIDTHS>.
WIDTHCOUNT = 8

; ---------------------------------------------------------------------------------------------------------------------
; The device information block and the configuration block.
; ---------------------------------------------------------------------------------------------------------------------

;; .SILENTYPE's device information block: the only device this driver has.
SILENTYPE_DIB:
    .word $0000                         ; no next DIB
    .word SILENTYPE_MAIN                ; the entry point
    .byte 10                            ; the name's length
    .byte ".SILENTYPE     "
    .byte $80                           ; active
    .byte $00, $00                      ; slot and unit
    .byte $41                           ; the device type
    .byte $02                           ; the subtype
    .byte $00
    .word $0000                         ; no blocks
    .word $0001                         ; the manufacturer: Apple
    .word $1040                         ; the release
    .word CONFIGLEN                     ; the configuration block's length

;; The configuration block: the default settings, which <LOADDEFAULTS> copies to <SETTINGS>, laid out as they are.
DEFAULTS:
    .byte $00                           ; FONT
    .byte $00                           ; STYLE: normal width, not bold
    .word 12                            ; LMARGIN, in dot columns
    .word 490                           ; RMARGIN
    .byte 1                             ; CHARSPACE: one dot column between characters
    .byte 6                             ; LINESPACE: six paper steps a line
    .byte $00                           ; MODES: both directions, no auto line feed, wrap
    .byte 10                            ; FORMLEN: ten lines a form feed
    .byte $1B                           ; CMDCHAR: Escape
    .word $0A40                         ; HEATTIME
    .word $0280                         ; PREHEAT
    .word $0200                         ; STEPTIME
    .assert * - DEFAULTS == CONFIGLEN

; ---------------------------------------------------------------------------------------------------------------------
; The driver's data.
; ---------------------------------------------------------------------------------------------------------------------

;; The head motor's phase pattern, four bits with two adjacent ones set, rotated a bit at each step.
;; See: <STEPRIGHT>, <STEPLEFT>
HEADPHASE:
    .byte PHASE_START

;; The paper motor's phase pattern, rotated a bit at each step.
;; See: <FEEDSTEP>, <UNFEEDSTEP>
PAPERPHASE:
    .byte PHASE_START

;; Negative after <HEADOFF> released the head motor: the next column's <PREHEAT> is 256 cycles longer.
HEADIDLE:
    .byte $00

;; The dots of the last column printed.
LASTCOL:
    .byte $00

;; The dots of the column before it.
PREVCOL:
    .byte $00

;; The head's direction: <DIR_LEFT> set to move left, toward the margin switch, clear to move right.
DIRECTION:
    .byte $00

;; The head's position: the dot columns right of the margin switch, low byte first.
HEADPOS:
    .word $0000

;; Heating time added to each column while it is positive: <LINEHEAT> at each line's start, less 4 for each column
;; of dots printed right to left.
EXTRAHEAT:
    .word $0000

;; Bit 7 set while .SILENTYPE is open.
OPENFLG:
    .byte $00

;; What the next byte written is: <IN_TEXT>, <IN_COMMAND>, <IN_ARGUMENT> or <IN_GRAPHICS>.
STATE:
    .byte IN_TEXT

;; The columns of a glyph, from <GLYPHWIDTH>.
GLYPHW:
    .byte $00

;; The current command's argument byte, 0 for a command without one.
CMDARG:
    .byte $00

;; The current command's index in <CMDLETTERS>.
CMDINDEX:
    .byte $00

;; The bytes in <LINEBUF>.
LINELEN:
    .byte $00

;; The columns a character gets beyond <GLYPHW>: the bits set in <STYLE>.
EXTRAW:
    .byte $00

;; Where the line ends, the next character's position: the dot columns right of the margin switch.
LINEEND:
    .word $0000

;; Where the line in <LINEBUF> starts.
LINESTART:
    .word $0000

;; The paper motion the line's moves add up to, in steps.
VMOVE:
    .byte $00

;; <FONT>, <STYLE> and <CHARSPACE> as they are where the line starts.
;; See: <SAVESTYLE>, <RESTSTYLE>
LINESTYLE:
    .byte $00, $00, $00

;; Apple's copyright.
COPYRIGHT:
    .byte "(C) 1980 Apple"

;; A font number, which nothing uses: the driver has one font.
FONT:
    .byte $00

;; The character style: bit 7 (<STYLE_BOLD>) bold, and bits 0-4 the glyph columns printed twice to widen it.
;; See: <WIDTHS>
STYLE:
    .byte $00

;; The left margin, in dot columns right of the margin switch.
LMARGIN:
    .word $0000

;; The right margin: a character that would start past it goes on the next line, or is dropped.
RMARGIN:
    .word $0000

;; The dot columns between characters, 0-15.
CHARSPACE:
    .byte $00

;; The paper steps in a line, 0-15.
LINESPACE:
    .byte $00

;; The mode bits: <MODE_UNIDIR>, <MODE_TRUNCATE>, <MODE_AUTOLF> and <MODE_OVERFLOW>.
MODES:
    .byte $00

;; The lines a form feed feeds, 0-15.
FORMLEN:
    .byte $00

;; The command character, which starts a command.
CMDCHAR:
    .byte $00

;; The cycles every dot of a column heats, after <PREHEAT>.
HEATTIME:
    .word $0000

;; The cycles the dots that were cold heat alone, before <HEATTIME>: those not heated in the last two columns.
PREHEAT:
    .word $0000

;; The cycles after each step of the head, before its dots heat, and after them.
STEPTIME:
    .word $0000

;; The settings, from <FONT> to <STEPTIME>: the configuration that status request 1 returns and control request 1
;; sets, laid out as <DEFAULTS>.
SETTINGS = FONT
    .assert * - SETTINGS == CONFIGLEN

;; The line being collected: characters, Backspaces and the changes made along it (<MARK_SPACING>).
LINEBUF:
    .res LINEBUFSIZE, $00

; ---------------------------------------------------------------------------------------------------------------------
; The requests.
; ---------------------------------------------------------------------------------------------------------------------

;; The driver's entry point: goes to the request's routine.
;; In: REQCODE = the request
;; See: <REQSTSW>
SILENTYPE_MAIN:
    SWITCH REQCODE, D_INIT, REQSTSW

;; Fails the request: its code is not one the driver has, or it is a read.
BADREQ:
    lda #XREQCODE
    jsr SYSERR
    lda #XNOTOPEN                       ; never reached
    jsr SYSERR

;; The request routines' addresses less one, by request code.
REQSTSW:
    .word BADREQ-1                      ; D_READ
    .word ST_WRITE-1                    ; D_WRITE
    .word ST_STATUS-1                   ; D_STATUS
    .word ST_CONTROL-1                  ; D_CONTROL
    .word BADREQ-1                      ; 4
    .word BADREQ-1                      ; 5
    .word ST_OPEN-1                     ; D_OPEN
    .word ST_CLOSE-1                    ; D_CLOSE
    .word ST_INIT-1                     ; D_INIT

;; Initializes the driver at boot: .SILENTYPE starts closed, with the default settings.
;; Out: carry = clear
;; Uses: A, X
ST_INIT:
    lda #$00                            ; closed
    sta a:OPENFLG

;; Copies the default settings, <DEFAULTS>, to <SETTINGS>.
;; Out: carry = clear
;; Uses: A, X
LOADDEFAULTS:
    ldx #CONFIGLEN-1
LOADDEFAULTS_1:
    lda a:DEFAULTS,x
    sta a:SETTINGS,x
    dex
    bpl LOADDEFAULTS_1
    clc
    rts

;; The system internal resources the driver claims while open, the D VIA's: CA2, the shift register, CB2, CB1 and
;; timer 2, with no interrupt handlers. Each entry is the resource, the ID byte, and the handler's address and bank.
SIRTABLE:
    .byte $09, $00                      ; CA2
    .word $0000
    .byte $00
    .byte $0B, $00                      ; the shift register
    .word $0000
    .byte $00
    .byte $0C, $00                      ; CB2
    .word $0000
    .byte $00
    .byte $0D, $00                      ; CB1
    .word $0000
    .byte $00
    .byte $0E, $00                      ; timer 2
    .word $0000
    .byte $00
SIRCOUNT = * - SIRTABLE                 ;; the table's length in bytes

;; The address of <SIRTABLE>, for <ALLOCSIR> and <DEALCSIR>.
SIRADDR:
    .word SIRTABLE

;; Opens .SILENTYPE: claims the D VIA's resources, then resets the settings and the printer.
;; Out: OPENFLG = $FF
;; Errors: XNORESRC = a resource is taken (as when already open), XNODRIVE = the margin switch was not found
;; Uses: A, X, Y
ST_OPEN:
    lda #SIRCOUNT
    ldx SIRADDR
    ldy SIRADDR+1
    jsr ALLOCSIR
    bcc ST_OPEN_1
    lda #XNORESRC
    jsr SYSERR
ST_OPEN_1:
    jsr CTL_RESET
    bcs ST_OPEN_2
    lda #$FF                            ; open
    sta a:OPENFLG
    rts
ST_OPEN_2:
    jsr RELEASE
    lda #XNODRIVE
    jsr SYSERR

;; Closes .SILENTYPE: prints what is buffered and goes back to the left margin, then <RELEASE>.
;; Errors: XNOTOPEN = not open
;; Uses: A, X, Y
ST_CLOSE:
    bit a:OPENFLG
    bpl NOTOPEN
    jsr NEWLINE

;; Marks the device closed, turns the shift register off, sets the control lines back, and gives the resources back.
;; Out: OPENFLG = 0
;; Uses: A, X, Y
RELEASE:
    lda #$00
    sta a:OPENFLG
    php
    sei
    lda D_ACR
    and #ACR_KEEP
    sta D_ACR
    lda D_PCR
    and #PCR_KEEP
    ora #PCR_CLOSED
    sta D_PCR
    plp
    lda #SIRCOUNT
    ldx SIRADDR
    ldy SIRADDR+1
    jsr DEALCSIR
RELEASE_1:
    rts

;; Fails the request: .SILENTYPE is not open.
NOTOPEN:
    lda #XNOTOPEN
    jsr SYSERR

;; Prints the caller's buffer, a byte at a time through <PUTBYTE>.
;; In: BUFFER = the bytes, REQCNT = their count
;; Errors: XNOTOPEN = not open, XIOERROR = the printer failed
;; Uses: A, X, Y, BUFFER, WRITECOUNT, ERRCODE
ST_WRITE:
    bit a:OPENFLG
    bpl NOTOPEN
    lda #$00
    sta WRITECOUNT
    sta WRITECOUNT+1
    sta ERRCODE
ST_WRITE_1:
    lda WRITECOUNT+1
    cmp REQCNT+1
    bcc ST_WRITE_2
    lda WRITECOUNT
    cmp REQCNT
    bcs RELEASE_1
ST_WRITE_2:
    ldy #$00
    lda (BUFFER),y
    jsr PUTBYTE
    lda ERRCODE
    beq ST_WRITE_3
    jsr SYSERR
ST_WRITE_3:
    inc BUFFER
    bne ST_WRITE_4
    inc BUFFER+1                        ; the next page
    bne ST_WRITE_4
    inc XPAGE+BUFFER+1                  ; past $FF: the next bank pair
    lda #$80                            ; back to $80
    sta BUFFER+1
ST_WRITE_4:
    inc WRITECOUNT
    bne ST_WRITE_1
    inc WRITECOUNT+1
    bne ST_WRITE_1

;; Answers a status request.
;; In: CTLSTAT = the status code, CSLIST = the status list
;; Errors: XNOTOPEN = not open, XCTLCODE = a code past 2
ST_STATUS:
    bit a:OPENFLG
    bpl NOTOPEN
    jsr FIXCSLIST
    SWITCH CTLSTAT, 2, STATSW

;; Fails the request: the status or control code is not one the driver has.
BADCTL:
    lda #XCTLCODE
    jsr SYSERR

;; The status routines' addresses less one, by status code.
STATSW:
    .word STAT_NONE-1                   ; 0: nothing
    .word STAT_CONFIG-1                 ; 1: the configuration
    .word STAT_NONE-1                   ; 2: nothing

;; Status request 1: returns the configuration, <SETTINGS>, after a length byte of 17.
;; In: CSLIST = the list, its first byte the room in it
;; Errors: XCTLPARM = less than 17 bytes of room
;; Uses: A, Y
STAT_CONFIG:
    ldy #$00
    lda (CSLIST),y                      ; the list's length byte
    cmp #CONFIGLEN
    bcs STAT_CONFIG_1
    lda #XCTLPARM
    jsr SYSERR
STAT_CONFIG_1:
    lda #CONFIGLEN
    sta (CSLIST),y
    tay                                 ; Y = 17
STAT_CONFIG_2:
    lda a:SETTINGS-1,y
    sta (CSLIST),y
    dey
    bne STAT_CONFIG_2

;; Status requests 0 and 2: nothing to report.
STAT_NONE:
    rts

;; Carries out a control request.
;; In: CTLSTAT = the control code, CSLIST = the control list
;; Errors: XNOTOPEN = not open, XCTLCODE = a code past 7
ST_CONTROL:
    bit a:OPENFLG
    bmi ST_CONTROL_1
    jmp NOTOPEN
ST_CONTROL_1:
    jsr FIXCSLIST
    SWITCH CTLSTAT, 7, CNTLSW
    jmp BADCTL

;; The control routines' addresses less one, by control code.
CNTLSW:
    .word CTL_RESET-1                   ; 0: reset
    .word CTL_CONFIG-1                  ; 1: set the configuration
    .word CTL_NONE-1                    ; 2: nothing
    .word CTL_RESTART-1                 ; 3: reset the printer
    .word CTL_NONE-1                    ; 4: nothing
    .word CTL_TIMING-1                  ; 5: set the timing
    .word CTL_WIDTHS-1                  ; 6: set the widths table
    .word CTL_GRAPHICS-1                ; 7: graphics

;; Control request 0 and the = command: loads the default settings, then <CTL_RESTART>.
;; Out: carry = set when the printer failed, ERRCODE = XIOERROR then
;; Uses: A, X, Y
CTL_RESET:
    jsr LOADDEFAULTS

;; Control request 3: resets the printer, finding the margin, and starts a line at the left margin.
;; Out: carry = set when the printer failed, ERRCODE = XIOERROR then
;; Uses: A, X, Y
CTL_RESTART:
    lda #M_RESET
    sta INBYTE
    jsr MECHBYTE
    bcc CTL_RESTART_1
    lda #XIOERROR
    sta ERRCODE
    rts
CTL_RESTART_1:
    jsr STARTTEXT
    clc

;; Control requests 2 and 4: nothing to do.
CTL_NONE:
    rts

;; Control request 1: sets the configuration, <SETTINGS>, from a list of a length byte of 17 and the settings.
;; In: CSLIST = the list
;; Errors: XCTLPARM = the length is not 17
;; Uses: A, Y
CTL_CONFIG:
    ldy #$00
    lda (CSLIST),y                      ; the list's length byte
    tay
    cpy #CONFIGLEN
    beq CTL_CONFIG_1
    lda #XCTLPARM
    jsr SYSERR
CTL_CONFIG_1:
    lda (CSLIST),y
    sta a:SETTINGS-1,y
    dey
    bne CTL_CONFIG_1
    rts

;; Control request 7: starts graphics, as the G command does.
CTL_GRAPHICS:
    jmp CMD_GRAPHICS

;; Control request 5: sets the head's timing, <HEATTIME>, <PREHEAT> and <STEPTIME>, from the list's six bytes.
;; In: CSLIST = the list
;; Uses: A, Y
CTL_TIMING:
    ldy #TIMINGLEN-1
CTL_TIMING_1:
    lda (CSLIST),y
    sta a:HEATTIME,y
    dey
    bpl CTL_TIMING_1
    rts

;; Control request 6: sets the widths table, <WIDTHS>, from the list's eight bytes.
;; In: CSLIST = the list
;; Uses: A, Y
CTL_WIDTHS:
    ldy #WIDTHCOUNT-1
CTL_WIDTHS_1:
    lda (CSLIST),y
    sta WIDTHS,y
    dey
    bpl CTL_WIDTHS_1
    rts

;; Moves a status or control list in page $FF of a bank pair to page $7F of the next, where it can be reached.
;; Uses: A, CSLIST
FIXCSLIST:
    lda CSLIST+1
    cmp #$FF
    bne FIXCSLIST_1
    lda #$7F                            ; page $FF is page $7F of the next bank
    sta CSLIST+1
    inc XPAGE+CSLIST+1
FIXCSLIST_1:
    rts

;; Starts printing after a reset: an empty line in text, a line feed, and the head at the left margin.
;; Uses: A, X, Y
STARTTEXT:
    jsr CLEARLINE
    lda #IN_TEXT
    sta a:STATE
    jsr LINEFEED
    jsr TOLEFTMARGIN
    jsr TOMARGIN
    jsr SETGLYPHW

;; Counts the columns <STYLE> adds to a character, its bits set, into <EXTRAW>.
;; Uses: A, X
COUNTEXTRA:
    lda #$00
    sta a:EXTRAW
    ldx #$07
    lda a:STYLE
COUNTEXTRA_1:
    lsr a
    bcc COUNTEXTRA_2
    inc a:EXTRAW
COUNTEXTRA_2:
    dex
    bpl COUNTEXTRA_1
    rts

;; Sets <GLYPHW>, the columns of a glyph.
;; Uses: A, CHAR
SETGLYPHW:
    lda #' '
    sta CHAR
    jsr GLYPHWIDTH
    sta a:GLYPHW
    rts

    .include "SilentypeText.asm"
    .include "SilentypeHead.asm"
    .include "SilentypeFont.asm"
