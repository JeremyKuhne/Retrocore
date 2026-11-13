;; EXTENDED BASIC ENTRY POINTS, FOR THE SOURCES THAT CALL EXTENDED BASIC
;;
;; The Extended Color BASIC routines and tables Disk Color BASIC uses, as equates at their addresses, which are
;; the same in Extended BASIC 1.0 and 1.1. ExtendedBasic.asm defines and documents each of them as a label, so it
;; does not include this file; Disk BASIC does, and each definition here inherits Extended BASIC's documentation.
;; The places within a routine that Disk BASIC enters have a line of their own instead.

;; Inherit: <ExtendedBasic:XBWMST>
XBWMST = $80C0

;; Inherit: <ExtendedBasic:XCOMMAND>
XCOMMAND = $813C

;; Inherit: <ExtendedBasic:XFUNCTION>
XFUNCTION = $8168

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

;; Inherit: <ExtendedBasic:GIVINT>
GIVINT = $880E

;; Inherit: <ExtendedBasic:XVEC15>
XVEC15 = $8846

;; Inherit: <ExtendedBasic:XVEC17>
XVEC17 = $88F0

XIRQSV_TIMER = $8955                ;; the IRQ handler once the field sync is acknowledged: counts TIMER, then PLAY's and SOUND's timers
DLOAD_KIND = $8C1B                  ;; DLOAD once files are closed: reads M for DLOADM, then the name and baud

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
GETPUT_HOOKED = $975F               ;; where GET and PUT return to from their hook, which Disk BASIC uses for its own GET and PUT

;; Inherit: <ExtendedBasic:MUL16>
MUL16 = $9FB5
