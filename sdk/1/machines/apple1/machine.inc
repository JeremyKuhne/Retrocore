; retrocore: style=strict
;; The Apple-1's PIA and its Woz Monitor's entry points
;;
;; A project includes it as <machine.inc> on the Apple-1. The Apple-1 has one I/O chip, a 6820 PIA at $D010-$D013:
;; port A reads the keyboard and port B writes to the terminal, which shows 40 columns by 24 rows and scrolls. The Woz
;; Monitor's ROM at $FF00 has three routines a program can call, and its command line to return to. Each name keeps
;; the one the Monitor's listing in the operation manual gives it.

.assert .defined(RC_MACHINE_APPLE1), "machine.inc for the Apple-1 is for targets whose machine is an Apple-1."

; The PIA.

;; Inherit: <WozMonitor:KBD>
;; Also: KBD (A1OM)
Keyboard = $D010

;; Inherit: <WozMonitor:KBDCR>
;; Also: KBDCR (A1OM)
KeyboardControl = $D011

;; Inherit: <WozMonitor:DSP>
;; Also: DSP (A1OM)
Display = $D012

;; Inherit: <WozMonitor:DSPCR>
;; Also: DSPCR (A1OM)
DisplayControl = $D013

;; The bit of <Keyboard> and <KeyboardControl> that is set on every key and while a key waits, and of <Display> that
;; reads 1 while the terminal is busy.
KEY_BIT = $80

; The Woz Monitor.

;; Inherit: <WozMonitor:IN>
;; Also: IN (A1OM)
InputBuffer = $0200

;; Inherit: <WozMonitor:GETLINE>
;; Also: GETLINE (A1OM)
MonitorCommandLine = $FF1F

;; Inherit: <WozMonitor:PRBYTE>
;; Also: PRBYTE (A1OM)
PrintHexByte = $FFDC

;; Inherit: <WozMonitor:PRHEX>
;; Also: PRHEX (A1OM)
PrintHexDigit = $FFE5

;; Inherit: <WozMonitor:ECHO>
;; Also: ECHO (A1OM)
CharacterOut = $FFEF
