;; EXTENDED BASIC ENTRY POINTS, FOR THE SOURCES THAT CALL EXTENDED BASIC
;;
;; The Extended Color BASIC routines and tables that Disk Color BASIC and the CoCo 3's ROM use, as equates at their
;; addresses, which are the same in Extended BASIC 1.0 and 1.1. ExtendedBasic.asm defines and documents each of them
;; as a label, so it does not include this file; the others do, and each definition here inherits Extended BASIC's
;; documentation. The places within a routine that the others enter or patch have a line of their own instead, as
;; do the routines only the CoCo 3's build has.

XBINIT_SIGNON = $80B2               ;; XBINIT where it shows the sign-on

XBINIT_RSTVEC = $80B8               ;; XBINIT past its sign-on: sets the warm start and ends the cold start

;; Inherit: <ExtendedBasic:XBWMST>
XBWMST = $80C0

;; Inherit: <ExtendedBasic:XSIGNON>
XSIGNON = $80E8

XSIGNON_LAST = $813A                ;; XSIGNON's second carriage return at its end

;; Inherit: <ExtendedBasic:XCOMMAND>
XCOMMAND = $813C

XCOMMAND_DISK = $8150               ;; XCOMMAND's jump to Disk BASIC's commands

;; Inherit: <ExtendedBasic:XFUNCTION>
XFUNCTION = $8168

XFUNCTION_DISK = $816C              ;; XFUNCTION's jump to Disk BASIC's functions

;; Inherit: <ExtendedBasic:XVEC3>
XVEC3 = $8273

;; Inherit: <ExtendedBasic:XVEC8>
XVEC8 = $8286

;; Inherit: <ExtendedBasic:XVEC18>
XVEC18 = $829C

XVEC20_CLOAD = $8311                ;; the statement loop's CLOAD: CLOADM when an M follows, else CLOAD
XVEC20_CSAVE = $8316                ;; the statement loop's CSAVE: CSAVEM when an M follows, else CSAVE

;; Inherit: <ExtendedBasic:COMADR>
COMADR = $836C

;; Inherit: <ExtendedBasic:FRMSTR>
FRMSTR = $8748

XVEC19_AMPERSAND = $87E7            ;; XVEC19's & check
HEXOCT = $87EB                      ;; XVEC19 past its & check: reads the number after &

HEXOCT_OCTAL_DIGIT = $8800          ;; HEXOCT's octal digit: ?SN ERROR for 9, else shifts it in

HEXOCT_OCTAL_CHECK = $880C          ;; HEXOCT's octal loop, where a character that is not a digit ends the number

;; Inherit: <ExtendedBasic:GIVINT>
GIVINT = $880E

GIVINT_TYPE = $8812                 ;; GIVINT with FPA0's top bytes left as they are
HEXOCT_HEX_END = $8826              ;; HEXOCT's hex loop, where a character that is not a letter ends the number

;; Inherit: <ExtendedBasic:HEXOCT_SHIFT>
HEXOCT_SHIFT = $8834

;; Inherit: <ExtendedBasic:XVEC15>
XVEC15 = $8846

NODIRECT_RUNNING = $886A            ;; NODIRECT's check for a running program

;; Inherit: <ExtendedBasic:XVEC17>
XVEC17 = $88F0

XIRQSV_TIMER = $8955                ;; the IRQ handler once the field sync is acknowledged: counts TIMER, then PLAY's and SOUND's timers
DLOAD_KIND = $8C1B                  ;; DLOAD once files are closed: reads M for DLOADM, then the name and baud

INTRESET = $8C1B                    ;; the CoCo 3's RESET, in place of DLOAD: maps the ROM in and starts the CoCo 3

CARTFIRQ = $8C28                    ;; the CoCo 3's ROM pack start from its FIRQ: the interrupt jumps invalid, then CARTROM

CARTROM = $8C2E                     ;; the CoCo 3's ROM pack mapping: the cartridge's ROM at $C000, the ROM switched in

PUTCHR3 = $8C37                     ;; the CoCo 3's screen output, which start-up patches into SCRCHR

CLS3 = $8C46                        ;; the CoCo 3's CLS, which start-up patches in after CLS's hook

;; Inherit: <ExtendedBasic:XVEC4>
XVEC4 = $8CF1

;; Inherit: <ExtendedBasic:XVEC9>
XVEC9 = $8E90

;; Inherit: <ExtendedBasic:COLOR>
COLOR = $9546

;; Inherit: <ExtendedBasic:TEXTSCREEN>
TEXTSCREEN = $95AC

PMOD_SET = $962E                    ;; PMODE with mode B on the page starting at A
PMODE_PAGE = $9650                  ;; PMODE's page: reads it and moves the graphics there
PCLEAR_DONE = $96CB                 ;; the end of PCLEAR: relinks the program, clears its variables and goes on
GRINIT_PAGES = $96EC                ;; GRINIT with the program moved: graphics pages from the page in A
GRINIT_END = $9703                  ;; GRINIT's end: erases the program
GETPUT_HOOKED = $975F               ;; where GET and PUT return to from their hook, which Disk BASIC uses for its own GET and PUT

;; Inherit: <ExtendedBasic:MUL16>
MUL16 = $9FB5
