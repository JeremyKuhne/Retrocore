; retrocore: style=strict
;; The dfs environment: a BBC Micro program as a *RUN file on an Acorn DFS disk, which the disk's !BOOT runs
;;
;; A project includes it as <environment.inc>. The build writes a DFS disk with the program, named for the project,
;; the target's files, and a !BOOT that *RUNs the program when SHIFT-BREAK boots the disk; the DFS loads it at its
;; load address and starts it at its entry. The program has the MOS's calls, which the BBC Micro's <machine.inc> names,
;; and the DFS behind them: <OSFILE> loads a whole file, given a control block laid out as these names give, its file
;; name a string that ends in a Return.

.assert .defined(RC_ENV_DFS), "environment.inc for dfs is for targets whose environment is dfs."

; OSFILE.

;; The <OSFILE> call, in A, that loads a file: to the control block's load address when the low byte of its execution
;; address is 0, otherwise to the file's own load address.
FILE_LOAD = $FF

;; The <OSFILE> call, in A, that saves memory as a file, from the control block's start address to its end address.
FILE_SAVE = $00

;; The offset in an <OSFILE> control block of the address of the file's name, two bytes.
FILE_BLOCK_NAME = 0

;; The offset of the load address, four bytes.
FILE_BLOCK_LOAD = 2

;; The offset of the execution address, four bytes.
FILE_BLOCK_EXECUTE = 6

;; The offset of the start address to save from, or the file's length once a call returns, four bytes.
FILE_BLOCK_START = 10

;; The offset of the end address to save to, or the file's attributes once a call returns, four bytes.
FILE_BLOCK_END = 14

;; The size of an <OSFILE> control block, which the call writes the file's details back into.
FILE_BLOCK_SIZE = 18

;; The Return that ends a file name.
NAME_END = $0D
