; retrocore: style=strict
;; The Apple III's I/O page, system VIAs and text screen
;;
;; A project includes it as <machine.inc> on the Apple III. It includes the SDK's Apple3Equates.asm, the built-in I/O
;; at $C000-$C0FF, the slot spaces, the RAM vectors under the ROM and the two system VIAs, with the names Apple's boot
;; ROM listing gives them, then adds the text screen. The boot ROM documents no routines for a program to call: a
;; bare program reads the keyboard and writes the screen itself, as SOS's console driver does.

.assert .defined(RC_MACHINE_APPLE3), "machine.inc for the Apple III is for targets whose machine is an Apple III."

.include <Roms/Apple3/Apple3Equates.asm>

; The text screen.

;; The first byte of text page 1, which 40-column text shows: 24 rows of 40 characters, in three groups of eight rows
;; laid out as the Apple II's text page is. A character from $80 up shows normally, below $80 inverse, from the
;; character set in RAM.
TextPage = $0400
