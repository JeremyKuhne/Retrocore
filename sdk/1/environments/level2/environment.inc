; retrocore: style=strict
;; The level2 environment: a TRS-80 program on a Level II SYSTEM tape, which the ROM's SYSTEM command loads
;;
;; A project includes it as <environment.inc>. The build writes the program as a 500 baud SYSTEM tape, under the
;; project's name in capitals cut to six, with its entry address. SYSTEM loads it at the *? prompt, and / starts it at
;; its entry with the stack SYSTEM set at $4288: on the Model I with interrupts off, as Level II runs, and on the Model
;; III with them on and its clock interrupting 30 times a second, as its cassette and video drivers leave them; the
;; program has the ROM's calls, which the TRS-80's <machine.inc> names, and goes back to the ROM's prompt with
;; <BasicReady>, or stays in a loop of its own. On the Model III the ROM's RS-232 and cassette state takes $41E5-$4224,
;; so a program loads from $4400 there, and from $4300 on the Model I.

.assert .defined(RC_ENV_LEVEL2), "environment.inc for level2 is for targets whose environment is level2."

;; Inherit: <Level2:READY>
;; Also: READY (UNKN)
BasicReady = $1A19
