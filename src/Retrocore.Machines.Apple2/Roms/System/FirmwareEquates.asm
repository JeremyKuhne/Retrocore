; retrocore: style=strict
;; APPLE IIE INTERNAL FIRMWARE ($C100-$CFFF): EQUATES BOTH MODELS SHARE
;;
;; The equates that the original and the Enhanced IIe firmware define alike and the other IIe sources don't share:
;; two of the Monitor's page-zero locations, the 80-column firmware's state in slot 3's screen holes
;; (<EightyColumns>), and the control codes with bit 7 clear that the 80-column firmware's control characters and
;; Pascal take. Firmware.Original.asm and Firmware.Enhanced.asm both include this file after IIeEquates.asm and
;; MonitorEntries.asm, and each keeps the equates only its own model uses.
;;
;; Each definition lists the names the firmware sources used before as its historical names, so the code that still
;; uses them assembles unchanged.

; Page zero not in IIeEquates.asm, because DOS has names of its own spelled the same.

;; Inherit: <Monitor:LOC1>
LOC1 = $01

;; Inherit: <Monitor:CV>
CV = $25

;; The 80-column firmware's state, which it keeps in slot 3's screen holes: bytes of the text screen's first page that
;; the display does not show, which slot 3's card owns.
;;
;; Both models keep the same state at the same addresses. The original IIe's firmware also uses $0478 as scratch,
;; and the Enhanced IIe's borrows <EightyColumns::SavedTextBase> as scratch between Pascal calls.
.scope EightyColumns

;; The <CursorColumn at ::CursorColumn> the firmware last stored, so that it can tell when a program has changed
;; <CursorColumn at ::CursorColumn> itself.
;; See: <EightyColumns::CursorColumn>
;; Also: OLDCH (IIEROM82, IIETRM85)
LastCursorColumn = $047B

;; The 80-column firmware's mode bits; <MODE_INACTIVE> while the firmware is not active.
;;
;; The bits differ between the models: the MODE_ constants below name them. On the original IIe: bit 0 interrupts
;; allowed (or, for Pascal, transparent), 1 Pascal 1.0, 2 inverse, 3 a GOTOXY pending, 4 inside quotes, 5 Pascal, 6
;; inside BASIC's input, 7 uppercase input. On the Enhanced IIe: bit 0 MouseText off, 1 Pascal 1.0, 2 inverse, 3
;; escape mode or a GOTOXY pending, 4 the cursor hidden, 5 control characters disabled, 7 Pascal. Apple calls it MODE
;; (IIEROM82, IIETRM85); that name is left out here, since it is <CommandMode>'s.
;; Also: MODE80 (UNKN)
Mode = $04FB

;; The column of the 80-column firmware's cursor, 0-79, which it copies to <::CursorColumn> for the Monitor in 40
;; columns.
;; See: <EightyColumns::CursorLine>, <EightyColumns::LastCursorColumn>
;; Also: OURCH (IIEROM82, IIETRM85)
CursorColumn = $057B

;; The line of the 80-column firmware's cursor, 0-23: its copy of <Monitor:CV>.
;; See: <EightyColumns::CursorColumn>
;; Also: OURCV (IIEROM82, IIETRM85)
CursorLine = $05FB

;; The character the firmware is printing, or the key it has read.
;; Also: CHAR (IIEROM82, IIETRM85)
CurrentCharacter = $067B

;; The column of Pascal's GOTOXY, once its first byte has arrived; $FF while the firmware waits for it.
;; Also: XCOORD (IIEROM82, IIETRM85)
GotoXYColumn = $06FB

;; <TextBase> as it was before a Pascal call, kept so that the firmware can put it back.
;; See: <EightyColumns::SavedTextBaseHigh>
;; Also: OLDBASL (IIEROM82, IIETRM85)
SavedTextBase = $077B

;; <TextBaseHigh> as it was before a Pascal call.
;; See: <EightyColumns::SavedTextBase>
;; Also: OLDBASH (IIEROM82, IIETRM85)
SavedTextBaseHigh = $07FB

.endscope

; The bits of <EightyColumns::Mode>. ENHANCED picks the model's set; a program that includes this file without it
; gets only MODE_INACTIVE.

;; <EightyColumns::Mode> while the 80-column firmware is not active.
MODE_INACTIVE = $FF

.ifdef ENHANCED
.if ENHANCED

;; The Enhanced IIe's mode bit 0: MouseText off, so that inverse capitals written as $40-$5F show as inverse capitals
;; with the alternate character set. Control-X sets it and Control-[ clears it.
;; Also: M_MOUSE (IIETRM85)
MODE_MOUSETEXT_OFF = %00000001

;; The Enhanced IIe's mode bit 1: Pascal 1.0, which <Pascal::Init10> starts.
;; Also: M_PAS1_0 (IIETRM85)
MODE_PASCAL10 = %00000010

;; The Enhanced IIe's mode bit 2: Pascal's text is inverse.
;; Also: M_VMODE (IIETRM85)
MODE_INVERSE = %00000100

;; The Enhanced IIe's mode bit 3 while BASIC calls the firmware: the key being read may start an escape sequence, and
;; control characters are not printed. <CharacterIo::Enter> sets it for a key read that allows them, and printing a
;; character clears it.
;; Also: M_CTL (IIETRM85)
MODE_ESCAPES = %00001000

;; The Enhanced IIe's mode bit 3 in Pascal: <Pascal::Write> has started a GOTOXY and waits for its column and line.
;; Also: M_GOXY (IIETRM85)
MODE_GOTOXY = %00001000

;; The Enhanced IIe's mode bit 4: Pascal's cursor is hidden (Control-F; Control-E shows it).
;; Also: M_CURSOR (IIETRM85)
MODE_CURSOR_OFF = %00010000

;; The Enhanced IIe's mode bit 5: the control characters are off, but for those with
;; <Control::RUNS_WHEN_DISABLED> (escape Control-D turns them off, escape Control-E on).
;; Also: M_CTL2 (IIETRM85)
MODE_CONTROLS_OFF = %00100000

;; The Enhanced IIe's mode bit 7: the firmware is Pascal's.
;; Also: M_PASCAL (IIETRM85)
MODE_PASCAL = %10000000

.else

;; The original IIe's mode bit 0 while BASIC calls the firmware: the caller had interrupts enabled, which
;; <CharacterIo::Enter> records on every call, so <LineBase> lets them in while the firmware works.
;; Also: M_IRQ (IIEROM82)
MODE_INTERRUPTS = %00000001

;; The original IIe's mode bit 0 in Pascal: transparent mode, which keeps the window a program set; <Pascal::Write>
;; stops at the window's right edge instead of wrapping.
;; Also: M_TRANS (IIEROM82)
MODE_TRANSPARENT = %00000001

;; The original IIe's mode bit 1: Pascal 1.0, which <Pascal::Init10> starts.
;; Also: M_PAS1_0 (IIEROM82)
MODE_PASCAL10 = %00000010

;; The original IIe's mode bit 2: Pascal's text is inverse.
;; Also: M_VMODE (IIEROM82)
MODE_INVERSE = %00000100

;; The original IIe's mode bit 3: <Pascal::Write> has started a GOTOXY and waits for its column and line.
;; Also: M_GOXY (IIEROM82)
MODE_GOTOXY = %00001000

;; The original IIe's mode bit 4: the line being typed is inside quotes, so <CharacterIo::FinishKey> leaves its case
;; alone.
;; Also: M_LIT (IIEROM82)
MODE_QUOTES = %00010000

;; The original IIe's mode bit 5: the firmware is Pascal's.
;; Also: M_PASCAL (IIEROM82)
MODE_PASCAL = %00100000

;; The original IIe's mode bit 6: the firmware is reading a key for BASIC's input, so a return clears the rest of its
;; line.
;; Also: M_BINPUT (IIEROM82)
MODE_INPUT = %01000000

;; The original IIe's mode bit 7: lowercase keys are typed as uppercase outside quotes; escape R sets it and escape T
;; clears it.
;; Also: M_ESCR (IIEROM82)
MODE_UPPERCASE = %10000000

.endif
.endif

; The control codes, with bit 7 clear, as the 80-column firmware's control characters and Pascal take them.

;; Control-D: on the Enhanced IIe, typed after the escape key, disables the control characters.
;; Also: CTRL_D (UNKN)
CONTROL_D = $04

;; Control-E: on the Enhanced IIe, Pascal's cursor on, and typed after the escape key, enables the control characters.
;; Also: CTRL_E (UNKN)
CONTROL_E = $05

;; Control-F: on the Enhanced IIe, Pascal's cursor off.
;; Also: CTRL_F (UNKN)
CONTROL_F = $06

;; Control-G: the bell.
;; Also: CTRL_G (UNKN)
CONTROL_G = $07

;; Control-H: the cursor left, a backspace.
;; Also: CTRL_H (UNKN)
CONTROL_H = $08

;; Control-J: the cursor down, a line feed.
;; Also: CTRL_J (UNKN)
CONTROL_J = $0A

;; Control-K: clears to the end of the window.
;; Also: CTRL_K (UNKN)
CONTROL_K = $0B

;; Control-L: homes the cursor and clears the window.
;; Also: CTRL_L (UNKN)
CONTROL_L = $0C

;; Control-M: a return.
;; Also: CTRL_M (UNKN)
CONTROL_M = $0D

;; Control-N: normal text.
;; Also: CTRL_N (UNKN)
CONTROL_N = $0E

;; Control-O: inverse text.
;; Also: CTRL_O (UNKN)
CONTROL_O = $0F

;; Control-Q: 40 columns; typed after the escape key, quits the 80-column firmware.
;; Also: CTRL_Q (UNKN)
CONTROL_Q = $11

;; Control-R: 80 columns.
;; Also: CTRL_R (UNKN)
CONTROL_R = $12

;; Control-U: quits the 80-column firmware.
;; Also: CTRL_U (UNKN)
CONTROL_U = $15

;; Control-V: scrolls the window down a line.
;; Also: CTRL_V (UNKN)
CONTROL_V = $16

;; Control-W: scrolls the window up a line.
;; Also: CTRL_W (UNKN)
CONTROL_W = $17

;; Control-X: on the Enhanced IIe, MouseText off.
;; Also: CTRL_X (UNKN)
CONTROL_X = $18

;; Control-Y: homes the cursor.
;; Also: CTRL_Y (UNKN)
CONTROL_Y = $19

;; Control-Z: clears the line.
;; Also: CTRL_Z (UNKN)
CONTROL_Z = $1A

;; The escape key's code as a control character, Control-[: on the Enhanced IIe, MouseText on.
;; Also: CTRL_ESC (UNKN)
CONTROL_ESCAPE = $1B

;; Control-\: the cursor right.
;; Also: CTRL_BACKSLASH (UNKN)
CONTROL_BACKSLASH = $1C

;; Control-]: clears to the end of the line.
;; Also: CTRL_RBRACKET (UNKN)
CONTROL_RIGHT_BRACKET = $1D

;; Control-^: starts Pascal's GOTOXY, whose column and line follow.
;; Also: CTRL_CARET (UNKN)
CONTROL_CARET = $1E

;; Control-_: the cursor up.
;; Also: CTRL_UNDERSCORE (UNKN)
CONTROL_UNDERSCORE = $1F
