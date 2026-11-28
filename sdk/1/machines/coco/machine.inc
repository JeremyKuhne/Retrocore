; retrocore: style=strict
;; The Color Computer's text screen and Color BASIC's documented ROM calls
;;
;; A project includes it as <machine.inc> on a Color Computer 1, 2 or 3. Color BASIC starts on the 32 by 16 text
;; screen at $0400. The ROM calls Radio Shack documents for programs are a table at $A000, the same on every model:
;; each holds the address of its routine, so a program calls one through it, as `JSR [CharacterOutVector]`. Each
;; inherits Color BASIC's documentation and keeps the name it is known by.

.assert .defined(RC_MACHINE_COCO), "machine.inc for the Color Computer is for targets whose machine is a CoCo."

; The screen.

;; Inherit: <ColorBasic:VIDRAM>
;; Also: VIDRAM (UNKN)
TextScreen = $0400

;; The text screen's width, in characters.
SCREEN_COLUMNS = 32

;; The text screen's height, in rows.
SCREEN_ROWS = 16

; Color BASIC's documented calls, each through the address it holds.

;; Inherit: <ColorBasic:POLCAT>
;; Also: POLCAT (UNKN)
KeyboardPollVector = $A000

;; Inherit: <ColorBasic:CHROUT>
;; Also: CHROUT (UNKN)
CharacterOutVector = $A002

;; Inherit: <ColorBasic:CSRDON>
;; Also: CSRDON (UNKN)
CassetteOnVector = $A004

;; Inherit: <ColorBasic:BLKIN>
;; Also: BLKIN (UNKN)
BlockInVector = $A006

;; Inherit: <ColorBasic:BLKOUT>
;; Also: BLKOUT (UNKN)
BlockOutVector = $A008

;; Inherit: <ColorBasic:JOYIN>
;; Also: JOYIN (UNKN)
JoystickInVector = $A00A

;; Inherit: <ColorBasic:WRTLDR>
;; Also: WRTLDR (UNKN)
WriteLeaderVector = $A00C

; Characters.

;; The character <CharacterOutVector>'s routine takes as Return, which ends a line.
RETURN = $0D
