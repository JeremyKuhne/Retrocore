; retrocore: style=strict
;; The dos33 environment: an Apple II program as a B file on a DOS 3.3 disk, started by the disk's HELLO
;;
;; A project includes it as <environment.inc>. The build writes a DOS 3.3 disk with HELLO, the program as a B file
;; named for the project, and the target's files; HELLO BRUNs the program, or BLOADs it and CALLs its entry. The
;; program has the Monitor's routines, which the Apple II's <machine.inc> names, and DOS 3.3, through the vectors DOS
;; keeps at $03D0. DOS watches what the Monitor's <CharacterOut> writes: a line that starts with <DOS_COMMAND>, Ctrl-D,
;; is a command for it, such as BLOAD, which DOS carries out before <CharacterOut> returns. DOS is in the output hook
;; only until the program sets its own, as the Monitor's <SetScreen> does, so a program gives DOS its commands before
;; that, or puts DOS back in the hooks with <HookDosJump>.

.assert .defined(RC_ENV_DOS33), "environment.inc for dos33 is for targets whose environment is dos33."

;; The character that starts a line DOS takes as a command, Ctrl-D with its high bit set, as <CharacterOut> takes
;; characters.
DOS_COMMAND = $84

; DOS's vector in page 3.

;; Inherit: <Dos33:DosWarmStartJump>
DosWarmStartJump = $03D0

;; Inherit: <Dos33:DosColdStartJump>
DosColdStartJump = $03D3

;; Inherit: <Dos33:FileManagerJump>
FileManagerJump = $03D6

;; Inherit: <Dos33:RwtsJump>
RwtsJump = $03D9

;; Inherit: <Dos33:LocateParameterListJump>
LocateParameterListJump = $03DC

;; Inherit: <Dos33:LocateIobJump>
LocateIobJump = $03E3

;; Inherit: <Dos33:HookDosJump>
HookDosJump = $03EA
