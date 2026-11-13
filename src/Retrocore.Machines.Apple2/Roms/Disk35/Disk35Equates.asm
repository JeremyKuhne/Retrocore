;; THE APPLE II 3.5 DISK CONTROLLER CARD'S HARDWARE, AS ITS 65C02 SEES IT
;;
;; The card's own 65C02 runs at about 2 MHz with 32 KB of static RAM at $0000-$7FFF, its I/O page at $0A00-$0AFF
;; (over RAM), and the 32 KB EPROM at $8000-$FFFF. The host Apple II sees parts of the same RAM:
;;
;;   Host $Cn00-$CnFF  card $7B00-$7BFF   read only; the card writes the slot page there
;;   Host $C800-$CBFF  card $0000-$3FFF   a 1 KB window, bank n = card $n*$400, chosen by any access to $C080+$n0+n
;;   Host $CC00-$CFFF  card $7C00-$7FFF   always
;;
;; The SWIM (Sander-Wozniak Integrated Machine) answers at $0A00-$0A0F. At reset it is an IWM, whose sixteen
;; addresses are switches; written with the right sequence it becomes the ISM, whose registers are written at
;; $0A00-$0A07 and read at $0A08-$0A0F. Names follow the SWIM's in Apple's Macintosh sources.

; The SWIM as an IWM: each address is a switch, set by any access.
IWM_PH0L = $0A00                    ;; stepper phase 0 off
IWM_PH0H = $0A01                    ;; stepper phase 0 on
IWM_PH1L = $0A02                    ;; stepper phase 1 off
IWM_PH1H = $0A03                    ;; stepper phase 1 on
IWM_PH2L = $0A04                    ;; stepper phase 2 off
IWM_PH2H = $0A05                    ;; stepper phase 2 on
IWM_PH3L = $0A06                    ;; stepper phase 3 off
IWM_PH3H = $0A07                    ;; stepper phase 3 on
IWM_MTROFF = $0A08                  ;; drive motor (enable) off
IWM_MTRON = $0A09                   ;; drive motor (enable) on
IWM_DRIVE1 = $0A0A                  ;; select drive 1
IWM_DRIVE2 = $0A0B                  ;; select drive 2
IWM_Q6L = $0A0C                     ;; Q6 low: read data or the handshake
IWM_Q6H = $0A0D                     ;; Q6 high: read status, or write the mode with Q7 high
IWM_Q7L = $0A0E                     ;; Q7 low: read
IWM_Q7H = $0A0F                     ;; Q7 high: write

; The SWIM as the ISM: registers written at $0A00-$0A07 and read at $0A08-$0A0F.
ISM_wData = $0A00                   ;; the next byte to write
ISM_wMark = $0A01                   ;; the next byte to write, as a mark
ISM_wCRC = $0A02                    ;; writes the CRC in place of a byte
ISM_wParams = $0A03                 ;; the next of the sixteen timing parameters
ISM_wPhase = $0A04                  ;; the phase lines and their directions
ISM_wSetup = $0A05                  ;; the setup register
ISM_wZeroes = $0A06                 ;; clears the mode bits set in the byte
ISM_wOnes = $0A07                   ;; sets the mode bits set in the byte
ISM_rData = $0A08                   ;; the next byte read
ISM_rMark = $0A09                   ;; the next byte read, as a mark
ISM_rError = $0A0A                  ;; the error register, cleared by reading it
ISM_rParams = $0A0B                 ;; the next timing parameter
ISM_rPhase = $0A0C                  ;; the phase lines
ISM_rSetup = $0A0D                  ;; the setup register
ISM_rStatus = $0A0E                 ;; the mode register
ISM_rHandshake = $0A0F              ;; the FIFO's state

; The card's own latches, also set by any access.
HEADSEL0 = $0A40                    ;; selects the lower head (side 0)
HEADSEL1 = $0A41                    ;; selects the upper head (side 1)
LEDON = $0A80                       ;; the diagnostic LED on
LEDOFF = $0A81                      ;; the diagnostic LED off

; The RAM the host sees.
SHARED_SLOTPAGE = $7B00             ;; the host's $Cn00-$CnFF
SHARED_EXPANSION = $7C00            ;; the host's $CC00-$CFFF
