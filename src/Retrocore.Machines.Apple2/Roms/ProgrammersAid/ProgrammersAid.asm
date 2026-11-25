; retrocore: style=strict
;; Apple II Programmer's Aid #1 ($D000-$D7FF)
;;
;; Apple's 2 KB ROM of utilities for Integer BASIC (1978), on a chip (341-0016) for the II's D0 socket, and in the
;; INTBASIC image DOS 3.3's System Master loads into a language card. A program CALLs its routines, or the Monitor runs
;; them through Control-Y:
;;
;; - High-resolution graphics ($D000, HiResGraphics.asm): INIT, CLEAR, PLOT, LINE, DRAW and shape tables from tape.
;; - Renumber and Append ($D400, Renumber.asm; RenumberCalls.asm at $D6DD): renumbering a program, all of it or a
;;   range, and loading a program from tape in front of the one in memory.
;; - Relocate ($D4D5, Relocate.asm): moving 6502 code to another address and adjusting its addresses.
;; - Tape Verify ($D52E, TapeVerify.asm): checking a recording against memory, for a program or for a block.
;; - RAM Test ($D5BC, RamTest.asm): testing memory and naming the failing chips.
;; - Music ($D717, Music.asm): playing a note on the speaker.
;;
;; Apple assembled each routine on its own, so each file is a scope of its own, and its old names are its listing's.
;; <SetControlY>, in `SetControlY.asm`, which the Control-Y setups share, the macros that assemble SWEET16's
;; instructions (Sweet16.mac) and the addresses of the Monitor and Integer BASIC (Equates.asm) are the routines' only
;; common ground. Renumber and Relocate are partly written in SWEET16, the 16-bit interpreter in Integer BASIC's ROM.
;;
;; One predefined symbol chooses the build. RAMTESTFIX 0, the default, builds the chip and the 1980 System Masters'
;; INTBASIC. RAMTESTFIX 1 builds the 1983 System Master's (680-0210-A), whose RAM test prints the bad data byte at
;; $D670 where the chip jumps to $02CB: three bytes differ.
;;
;; The names are the conversion's (its log, docs/conversions/ProgrammersAid.md); the names of Apple's listings
;; in the Programmer's Aid #1 manual (1978, https://archive.org/details/programmers-aid-1) are their historical names.
;; Maintained by hand; it assembles byte-identically to the chip at origin $D000 (Apple2SourceTests checks both builds
;; by digest).

.cpu Mos6502

.ifndef RAMTESTFIX
RAMTESTFIX = 0
.endif

; Only the two builds Apple2SourceTests checks by digest: the chip's, and the 1983 System Master's.
.assert RAMTESTFIX = 0 || RAMTESTFIX = 1, "RAMTESTFIX is 1 for the 1983 System Master's build or 0 for the chip's."

; Apple II text has bit 7 set, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

.include "Equates.asm"
.include "Sweet16.mac"

.org $D000

.include "HiResGraphics.asm"
.assert * = $D400, "Hi-res graphics fills $D000-$D3FF."
.include "Renumber.asm"
.assert * = $D4D5, "Renumber and Append end at $D4D4."
.include "Relocate.asm"
.assert * = $D52E, "Relocate ends at $D52D."
.include "TapeVerify.asm"
.assert * = $D5B0, "Tape Verify ends at $D5AF."
.include "SetControlY.asm"
.include "RamTest.asm"
.assert * = $D6DD, "The RAM test ends at $D6DC."
.include "RenumberCalls.asm"
.assert * = $D717, "Renumber's BASIC entries end at $D716."
.include "Music.asm"

    ; The rest of the chip is unprogrammed.
    .res $D800 - *, $FF

.assert * = $D800, "The routines fill $D000-$D7FF."
