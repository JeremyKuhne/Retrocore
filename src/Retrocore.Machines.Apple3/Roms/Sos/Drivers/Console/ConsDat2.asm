; ---------------------------------------------------------------------------------------------------------------------
; SOS's global page and jump table
; ---------------------------------------------------------------------------------------------------------------------

;; The suspend and flush flags for screen output, in SOS's global page, which the keyboard interrupt sets.
;;
;; Bit 7 set suspends output: <CNSLWRIT> waits until it clears. Bit 6 set throws output away.
SUSPFLSH = $1902

;; The screen mode, in SOS's global page: bit 7 set while the video is on, bit 6 set for graphics, bit 2 set for the
;; second page, bit 1 set for 80 columns and bit 0 set for color.
SCRNMODE = $1906

ALLOCSIR = $1913                    ;; claims system interrupt resources for the driver
DEALCSIR = $1916                    ;; releases system interrupt resources
QUEEVENT = $191F                    ;; queues an event for the interpreter
SYSERR = $1928                      ;; ends the request with the error code in A; it does not return

; ---------------------------------------------------------------------------------------------------------------------
; SOS error codes
; ---------------------------------------------------------------------------------------------------------------------

XREQCODE = $20                      ;; error: the request code is not one the driver takes
XCTLCODE = $21                      ;; error: the status or control code is not one the driver takes
XCTLPARM = $22                      ;; error: a status or control list is wrong
XNOTOPEN = $23                      ;; error: the console is not open
XNOTAVIL = $24                      ;; error: the device is not available; the console is already open
XNORESRC = $25                      ;; error: an interrupt resource the driver needs is in use

; ---------------------------------------------------------------------------------------------------------------------
; Hardware
; ---------------------------------------------------------------------------------------------------------------------

KAPORT = $C000                      ;; the keyboard's character; bit 7 set while a key is waiting
KBPORT = $C008                      ;; the keyboard's modifier keys and flags
KYBDSTRB = $C010                    ;; clears the keyboard's waiting key when touched
KYBDCLR = $01                       ;; the keyboard's bit in the VIA's interrupt flags, to clear it
KYBDDSBL = $01                      ;; the keyboard's bit in the VIA's interrupt enable, to disable it
KYBDENBL = $81                      ;; enables the keyboard interrupt in the VIA
BELL = $C040                        ;; sounds the bell when touched
VMODE0 = $C050                      ;; black and white when touched; color at VMODE0+1
VMODE1 = $C052                      ;; 40 columns when touched; 80 columns at VMODE1+1
VMODE2 = $C054                      ;; the first screen page when touched
VMODE3 = $C056                      ;; text when touched
SCRLDSBL = $C0D8                    ;; turns the graphics scroll off when touched
DNLDDSBL = $C0DA                    ;; turns character downloading off when touched
DNLDENBL = $C0DB                    ;; turns character downloading on when touched
VBLCLR = $18                        ;; both vertical-blanking bits in the VIA's interrupt flags, to clear them
VBLDSBL = $18                       ;; both vertical-blanking bits in the VIA's interrupt enable, to disable them
VBLENBL = $90                       ;; enables the vertical-blanking interrupt on CB1
E_REG = $FFDF                       ;; the environment register
E_IORB = $FFE0                      ;; the system VIA's port B; bit 6 follows the screen's composite blanking
E_PCR = $FFEC                       ;; the system VIA's peripheral control register
E_IFR = $FFED                       ;; the system VIA's interrupt flags
E_IER = $FFEE                       ;; the system VIA's interrupt enable
B_REG = $FFEF                       ;; the bank register

; ---------------------------------------------------------------------------------------------------------------------
; Characters and keys
; ---------------------------------------------------------------------------------------------------------------------

ASC_NUL = $00
ASC_SOH = $01
ASC_STX = $02
ASC_ETX = $03
ASC_ENQ = $05
ASC_ACK = $06
ASC_BS = $08
ASC_HT = $09
ASC_LF = $0A
ASC_VT = $0B
ASC_FF = $0C
ASC_CR = $0D
ASC_NAK = $15
ASC_CAN = $18
ASC_ESC = $1B
ASC_FS = $1C
ASC_GS = $1D
ASC_US = $1F
ASC_SP = $20
LARROW = ASC_BS                     ;; the left-arrow key's code
RARROW = ASC_NAK                    ;; the right-arrow key's code
UARROW = ASC_VT                     ;; the up-arrow key's code
DARROW = ASC_LF                     ;; the down-arrow key's code

; ---------------------------------------------------------------------------------------------------------------------
; Flags and bits
; ---------------------------------------------------------------------------------------------------------------------

TRUE = $80                          ;; a flag's value when on: bit 7 set
FALSE = $00                         ;; a flag's value when off
BITON0 = $01
BITON2 = $04
BITON3 = $08
BITON4 = $10
BITON5 = $20
BITON6 = $40
BITON7 = $80
BITOFF0 = $FE
BITOFF4 = $EF
BITOFF5 = $DF
BITOFF7 = $7F
BUFMAX = $80                        ;; the largest type-ahead buffer, in keys
TEXTCSA = $0C00                     ;; the text character set's 1K image, from which characters are downloaded

; ---------------------------------------------------------------------------------------------------------------------
; The request's parameters, in the driver's zero page
; ---------------------------------------------------------------------------------------------------------------------

SOSINT = $C0                        ;; where SOS puts a request's parameters
REQCODE = SOSINT+$00                ;; the request code
BUFFPTR = SOSINT+$02                ;; read and write: the caller's buffer, an extended pointer
REQCNT = SOSINT+$04                 ;; read and write: how many bytes
RTNCNT = SOSINT+$08                 ;; read: where to put how many bytes were read
SCCODE = SOSINT+$02                 ;; status and control: the code
SCLIST = SOSINT+$03                 ;; status and control: the caller's list, an extended pointer

; ---------------------------------------------------------------------------------------------------------------------
; Zero-page data the driver keeps between requests
; ---------------------------------------------------------------------------------------------------------------------

ZPDATA = SOSINT+10                  ;; the driver's own zero page, after the parameters
BASEPTRS = ZPDATA+$00               ;; the two screen pointers
BASE1 = BASEPTRS+$00                ;; the current line: its text in 40 columns, its even columns in 80
BASE2 = BASEPTRS+$02                ;; the current line: its colors in 40 columns, its odd columns in 80
ZPLENGTH = $04                      ;; the bytes of zero page kept between requests

;; Where the zero page the driver keeps, <BASE1> and <BASE2>, waits between requests.
;; See: <CNSLDH>, <ZPOUT>
ZPSAVE:
    .res ZPLENGTH

; ---------------------------------------------------------------------------------------------------------------------
; Zero-page work space, which lasts only for a request
; ---------------------------------------------------------------------------------------------------------------------

WORKPTRS = ZPDATA+ZPLENGTH          ;; two work pointers, partners of BASE1 and BASE2
WORK1 = WORKPTRS+$00                ;; a work pointer, used with BASE1
WORK2 = WORKPTRS+$02                ;; a work pointer, used with BASE2
COUNT = WORKPTRS+$04                ;; read and write: the bytes done so far (two bytes)
ONEBYTE = COUNT+$02                 ;; read: bit 7 set when the request is for one byte
BLANK = ONEBYTE+$01                 ;; a space, normal or inverse, for clearing
TEMPX = BLANK+$01                   ;; a place to keep X
FLAGS = TEMPX+$01                   ;; flags for SCROLL, SHIFT and SCRNDUMP
TEMP1 = FLAGS+$01                   ;; work bytes for SCROLL, SHIFT and SCRNDUMP
TEMP2 = TEMP1+$01
TEMP3 = TEMP2+$01
TEMP4 = TEMP3+$01
