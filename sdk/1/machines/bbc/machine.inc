; retrocore: style=strict
;; The BBC Micro's MOS calls, hardware and MOS workspace
;;
;; A project includes it as <machine.inc> on the BBC Micro, model A or B. It includes the SDK's MosEquates.asm, the
;; hardware in <SHEILA> and the RAM the MOS keeps, and MosEntries.asm, the MOS calls at the top of the ROM, which
;; inherit the MOS's documentation. Their names are Acorn's: <OSWRCH> writes a character, <OSRDCH> reads one,
;; <OSWORD> 0 reads a line, and <OSBYTE> does the rest. The MOS's own workspace is named so that a program can read
;; what the MOS keeps there; a program writes only what the Advanced User Guide says it may.

.assert .defined(RC_MACHINE_BBC), "machine.inc for the BBC Micro is for targets whose machine is a BBC Micro."

.include <Roms/Acorn/MosEquates.asm>
.include <Roms/Acorn/MosEntries.asm>
