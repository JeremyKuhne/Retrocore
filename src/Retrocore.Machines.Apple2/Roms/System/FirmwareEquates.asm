;; APPLE IIE INTERNAL FIRMWARE ($C100-$CFFF): EQUATES BOTH MODELS SHARE
;;
;; The equates that the original and the Enhanced IIe firmware define alike and the other IIe sources don't share:
;; two of the Monitor's page-zero locations and the 80-column firmware's state in slot 3's screen holes.
;; Firmware.Original.asm and Firmware.Enhanced.asm both include this file after IIeEquates.asm and
;; MonitorEntries.asm, and each keeps the equates only its own model uses.

; Page zero not in IIeEquates.asm, because DOS has names of its own spelled the same.
;; Inherit: <Monitor:LOC1>
LOC1 = $01

;; Inherit: <Monitor:CV>
CV = $25

; The 80-column firmware's state in slot 3's screen holes.
OLDCH = $047B                       ;; 80-column firmware: the CH it last set
MODE80 = $04FB                      ;; 80-column firmware: mode flags (Apple's MODE)
OURCH = $057B                       ;; 80-column firmware: cursor column
OURCV = $05FB                       ;; 80-column firmware: cursor row
CHAR = $067B                        ;; 80-column firmware: current character
XCOORD = $06FB                      ;; 80-column firmware: GOTOXY column
OLDBASL = $077B                     ;; 80-column firmware: saved BASL
OLDBASH = $07FB                     ;; 80-column firmware: saved BASH
