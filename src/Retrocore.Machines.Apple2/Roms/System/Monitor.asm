; retrocore: style=strict
;; The Apple II, II Plus and IIe Monitors ($F800-$FFFF)
;;
;; The Monitor is each Apple II's lowest layer: reset and power-up, the BRK and IRQ entry points, character
;; input and output through the <CSWL>/<KSWL> hooks, the text screen and lo-res graphics primitives, the
;; mini disassembler, and the Monitor command line (the * prompt). This file builds four Monitors:
;;
;; - The Apple II Monitor of the first Apple IIs (1978).
;; - The Autostart Monitor of the Apple II Plus and later Apple IIs (1979).
;; - The original Apple IIe's.
;; - The Enhanced Apple IIe's.
;;
;; Documented entry points keep their addresses in all four, so programs can call them by address.
;;
;; The Apple II Monitor has no power-up or warm-start logic: its reset vector points at RESET (OLDRST in the later
;; listings), which sets up the screen and keyboard and enters the Monitor, so the user starts BASIC by hand and no disk
;; is booted. BRK shows the address and the registers directly, without a vector. Its S command steps a program one
;; instruction at a time (STEP) and T traces it (TRACE), and it carries 16-bit multiply and divide routines (MULPM,
;; DIVPM) at $FB60-$FBC0. Output goes to the screen without the Control-S pause (VIDOUT), and escape mode takes one
;; command, @ or A-F, at a time.
;;
;; The Autostart Monitor takes the machine from power-up to a program. Its RESET checks the soft entry
;; vector at $3F2-$3F4 (<SOFTEV> and its check byte <PWREDUP>): when it is valid, a reset continues the
;; program that set it; otherwise this is a power-up (PWRUP), which shows "APPLE ][", sets the vectors,
;; and boots the disk controller in the highest slot that has one, or starts BASIC. BRK goes through
;; the vector <BRKV> ($3F0). STEP, TRACE and the multiply and divide routines are gone; in their space are
;; the title and boot code, the Control-S pause on output (VIDWAIT) and the escape keys I, J, K and M.
;;
;; The IIe's Monitor keeps the Autostart Monitor's design but moves much of the screen work to the
;; internal firmware at $C100-$CFFF, which knows about 80 columns. Routines such as HOME, SCROLL,
;; CLREOL and KEYIN load a function number into Y and jump to GOTOCX, which switches internal ROM in and
;; enters the firmware's dispatcher at $C100. Its input line keeps lowercase, where the Apple II's
;; Monitors turn it into uppercase. The Enhanced IIe sends more routines that way (RDKEY, VTABZ,
;; INSDS2, OUTPORT), replaces the cassette routines with stubs into internal ROM, and
;; adds lowercase input; its IRQ entry goes to $C3FA.
;;
;; Two predefined symbols choose the build. MONITOR picks the Monitor: 0 (<MONITOR_II>) for the Apple II
;; Monitor, chip 341-0004; 1 (<MONITOR_AUTOSTART>) for the Autostart Monitor, chip 341-0020; 2
;; (<MONITOR_IIE>, the default) for the IIe. For the IIe, ENHANCED picks the model: 1 (the default) for
;; the Enhanced IIe, 0 for the original; the Apple II builds need 0, their default. Each build
;; assembles byte-identically to its chip, or to the $F800-$FFFF part of the IIe model's system ROM.
;; All but the Enhanced IIe's assemble for the NMOS 6502; the Enhanced IIe's for the 65C02.
;;
;; The source is in the files of Monitor/, by subject, included below in address order. Routines are .procs, and
;; the families that share code are scopes (<LowRes>, <Disassembler>, <Startup>, <Escape>, <Commands> ...), some in
;; several pieces where the ROM interleaves them. Names say what the code does; each name Apple's listings gave a
;; definition is in its Also: section, so code written with Apple's names still assembles and the editor offers the
;; current ones. The page-zero locations, soft switches and keys the other IIe sources share are in IIeEquates.asm,
;; which it includes; Monitor/Equates.asm has the few this source adds.
;;
;; Programs call the Monitor's documented entry points by address, so each one's comment gives its address, and an
;; .assert at it checks the address in every build.
;;
;; Maintained by hand. The SystemSourceTests and Apple2SourceTests digests check that every build assembles
;; byte-identically, and the root refuses any other MONITOR or ENHANCED.

;; The MONITOR value that builds the Apple II Monitor (1978), chip 341-0004.
;; See: <MONITOR_AUTOSTART>, <MONITOR_IIE>
MONITOR_II = 0

;; The MONITOR value that builds the Autostart Monitor of the Apple II Plus (1979), chip 341-0020.
;; See: <MONITOR_II>, <MONITOR_IIE>
MONITOR_AUTOSTART = 1

;; The MONITOR value that builds the Apple IIe's Monitor, original or enhanced by ENHANCED.
;; See: <MONITOR_II>, <MONITOR_AUTOSTART>
MONITOR_IIE = 2

.ifndef MONITOR
MONITOR = MONITOR_IIE
.endif
.ifndef ENHANCED
.if MONITOR = MONITOR_IIE
ENHANCED = 1
.else
ENHANCED = 0
.endif
.endif
; Only the four builds the digest tests check (SystemSourceTests and Apple2SourceTests): the Apple II and Autostart
; Monitors, and the original and Enhanced IIe's.
.assert MONITOR >= MONITOR_II && MONITOR <= MONITOR_IIE, "MONITOR is MONITOR_II, MONITOR_AUTOSTART or MONITOR_IIE."
.assert ENHANCED = 0 || ENHANCED = 1, "ENHANCED is 1 for the Enhanced IIe or 0 for the original."
.if MONITOR != MONITOR_IIE && ENHANCED
.error "Only the IIe's Monitor has an enhanced model."
.endif
.if ENHANCED
.cpu Rockwell65C02
.else
.cpu Mos6502
.endif

; Apple II text has bit 7 set, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

; The IIe's page zero, low memory, soft switches and keys, shared with the firmware, the Disk II boot ROM and DOS.
.include "IIeEquates.asm"

; The Monitor's own page zero, the firmware's entries and the build's other names.
.include "Monitor/Equates.asm"

; Values several of the Monitor's files use.

;; <INVFLG> for normal text: printable characters print as they are.
TEXT_NORMAL = $FF

;; Added to a slot number to make the high byte of its ROM's page, $Cn00.
SLOT_ROM_PAGE = $C0

.org $F800

.include "Monitor/LowRes.asm"
.include "Monitor/Disassembler.asm"
.include "Monitor/DisassemblerTables.asm"
.include "Monitor/BreakAndReset.asm"
.include "Monitor/Registers.asm"
.include "Monitor/ScreenSetup.asm"
.include "Monitor/ArithmeticAndEscape.asm"
.include "Monitor/Screen.asm"
.include "Monitor/Cassette.asm"
.include "Monitor/Keyboard.asm"
.include "Monitor/LineInput.asm"
.include "Monitor/Examine.asm"
.include "Monitor/Commands.asm"
.include "Monitor/CommandLine.asm"
