;; APPLE IIE MONITOR ENTRY POINTS, FOR THE SOURCES THAT CALL THE MONITOR
;;
;; The Monitor's routines and tables that the internal firmware of both models, the Disk II boot ROM and DOS use,
;; as equates at their addresses in the Monitor. Monitor.asm defines and documents each of them as a label, so it
;; does not include this file; the others do, and each definition here inherits the Monitor's documentation. A few
;; are in only one model's Monitor, and only that model's firmware uses them: VIDSYNC and SLOTRTN in the original
;; IIe's, SKIPBLNK in the Enhanced IIe's.
;;
;; Two names are not here. GETNUM is also a routine of DOS's own, so the Enhanced IIe's firmware defines the
;; Monitor's itself. DOS's INSDS2, at $F88E, is two bytes into the Monitor's, so DOS defines it.

;; Inherit: <Monitor:PRBLNK>
PRBLNK = $F948

;; Inherit: <Monitor:CHAR1>
CHAR1 = $F9B4

CHAR2 = $F9BA                       ;; the disassembler's second operand characters, after CHAR1's
MNEML = $F9C0                       ;; the disassembler's mnemonics, left halves
MNEMR = $FA00                       ;; the disassembler's mnemonics, right halves

;; Inherit: <Monitor:INIT>
INIT = $FB2F

;; Inherit: <Monitor:VERSION>
VERSION = $FBB3

;; Inherit: <Monitor:UP>
UP = $FC1A

;; Inherit: <Monitor:VTAB>
VTAB = $FC22

;; Inherit: <Monitor:VTABZ>
VTABZ = $FC24

;; Inherit: <Monitor:HOME>
HOME = $FC58

;; Inherit: <Monitor:VIDSYNC>
VIDSYNC = $FC75

;; Inherit: <Monitor:WAIT>
WAIT = $FCA8

;; Inherit: <Monitor:NXTA1>
NXTA1 = $FCBA

;; Inherit: <Monitor:KEYIN>
KEYIN = $FD1B

;; Inherit: <Monitor:SLOTRTN>
SLOTRTN = $FD29

;; Inherit: <Monitor:CROUT>
CROUT = $FD8E

;; Inherit: <Monitor:PRHEX>
PRHEX = $FDE3

;; Inherit: <Monitor:COUT1>
COUT1 = $FDF0

A1PCLP = $FE78                      ;; the loop in A1PC that copies A1 to PC

;; Inherit: <Monitor:SETKBD>
SETKBD = $FE89

;; Inherit: <Monitor:SETVID>
SETVID = $FE93

;; Inherit: <Monitor:SLOTRTS>
SLOTRTS = $FEC5

;; Inherit: <Monitor:SKIPBLNK>
SKIPBLNK = $FF13

;; Inherit: <Monitor:PRERR>
PRERR = $FF2D

;; An RTS ($60) in the Monitor, the one that ends <Monitor:SAVE>: a routine that does nothing.
;;
;; Calling it returns at once, so it is a safe place to point a vector, and BIT IORTS sets V, since $60 has bit 6
;; set.
;; See: <Monitor:SAVE>
IORTS = $FF58

;; Inherit: <Monitor:ZMODE>
ZMODE = $FFC7
