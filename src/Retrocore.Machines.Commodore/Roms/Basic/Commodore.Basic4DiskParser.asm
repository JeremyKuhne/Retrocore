; retrocore: style=strict
; COMMODORE BASIC 4: THE DISK STATEMENTS' PARAMETER PARSER

; The bits of <ParsedParameters>, one for each parameter <Disk::ParseParameters> has read. The checks in
; Commodore.Basic4Record.asm reject a statement's unwanted parameters by these.

;; A first filename was given.
PARSED_FIRST_NAME = $01

;; A second filename was given, after `TO`.
PARSED_SECOND_NAME = $02

;; A logical file number was given, after `#`.
PARSED_FILE = $04

;; A unit (device) number was given, after `U` or `ON U`.
PARSED_UNIT = $08

;; A first drive was given, after `D`.
PARSED_FIRST_DRIVE = $10

;; A second drive was given, after `TO` and `D`.
PARSED_SECOND_DRIVE = $20

;; A record length (`L`) or the write option (`W`) was given.
PARSED_RECORD = $40

;; A filename began with `@`, asking the drive to replace the file.
PARSED_REPLACE = $80

;; The character that starts a replacement filename.
REPLACE_PREFIX = '@'

;; The longest filename the drive takes.
FILENAME_LIMIT = 16

;; The device a disk statement uses when it names no unit.
DEFAULT_DISK_UNIT = 8

;; The lowest unit a disk statement may name: units 0 to 2 are the keyboard, the cassette and the screen.
FIRST_DISK_UNIT = 3

;; The unit after the highest a disk statement may name.
UNIT_LIMIT = 32

;; The number of drives a unit has.
DRIVE_COUNT = 2

;; The length of a disk ID.
DISK_ID_LENGTH = 2

;; Emits the disk parameter parser, <Disk::ParseParameters>, and its unit, filename and value helpers.
.macro CommodoreBasic4DiskParser

    .scope Disk continued
    ; The parameter parser.

    ;; Parses a disk statement's parameters into the kernal's file fields and <ParsedParameters>.
    ;;
    ;; It clears the fields, with the unit defaulting to 8, then reads the parameters in any order: `#` and a file
    ;; number (not 0), `W`, `L` and a record length (not 0 or 255), `R`, `D` and a drive (0 or 1, which sets both
    ;; drives), `U` or `ON U` and a unit (3 to 31), `I` and the two characters of a disk ID, and a filename, quoted
    ;; or in parentheses. `TO` then starts the second part: a second drive, a unit and a second filename. Each
    ;; parameter sets its bit, and giving one twice is a syntax error. `R` is accepted and skipped, with no effect.
    ;; The first filename is copied to <FirstFilename>, without the leading `@` of a replacement; the second is left
    ;; where it is, `@` and all.
    ;;
    ;; <DiskIdSeen> shares <RecordLength>'s byte, so a record length given before `I` makes the `I` a syntax error,
    ;; and `I` leaves $FF as the record length.
    ;; In: TextPointer = the statement's first parameter character
    ;; Out: A = <ParsedParameters>, ParsedParameters = a bit for each parameter given, LogicalFile = the file or 0,
    ;;   DeviceNumber = the unit or 8, FirstDrive = the first drive or 0, SecondDrive = the second drive, else the
    ;;   first, RecordLength = the record length or 0, DiskId = the disk ID, FilenameLength = the first name's length
    ;;   or 0, FilenamePointer = the first name, SecondFilenameLength = the second name's length or 0,
    ;;   SecondFilenamePointer = the second name
    ;; Errors: SYNTAX for an unknown or repeated parameter; ILLEGAL QUANTITY for a value out of range or an empty
    ;;   name; STRING TOO LONG for a long name
    ;; Entry:
    ;;   RejectParameter = jumps to <SyntaxError>; <Disk::ParseOnUnit> and <Disk::EvaluateName> branch here
    ;; Also: DOSPAR (K4S79, HVK4)
    .proc ParseParameters

    ;; The first filename's length, in <TemplateCount>'s byte, while the name is copied.
    NameLength = TemplateCount

    ; Clear the fields; the unit defaults to 8.
    ldx #0
    stx ParsedParameters
    stx LogicalFile
    stx RecordLength
    stx FirstDrive
    stx SecondDrive
    stx FilenameLength
    stx SecondFilenameLength
    stx DiskId
    ldx #DEFAULT_DISK_UNIT
    stx DeviceNumber
    jsr GetCurrentCharacter
    beq ToDone

;; Dispatches on a parameter of the first part.
;; Also: PARSEL (K4S79, HVK4)
NextParameter:
    cmp #'#'
    beq ReadLogicalFile
    cmp #'W'
    beq ReadRecordLength
    cmp #'L'
    beq ReadRecordLength
    cmp #'R'
    bne CheckDrive
    jsr GetNextCharacter
    jmp FirstDelimiter

;; Tests for `D`, `ON`, `U` and `I`.
;; Also: PARNXT (K4S79, HVK4)
CheckDrive:
    cmp #'D'
    beq ReadFirstDrive
    cmp #TOKEN_ON
    beq OnUnit
    cmp #'U'
    beq Unit
    cmp #'I'
    bne CheckName
    jmp ReadDiskId

;; Tests for a filename, quoted or in parentheses.
;; Also: NEXT7 (K4S79, HVK4)
CheckName:
    cmp #'"'
    beq ToFirstName
    cmp #'('
    beq ToFirstName

;; Jumps on to <SyntaxError>, for an unknown or repeated parameter of the first part.
;; Also: SNER1 (K4S79, HVK4)
Reject:
    jmp SyntaxError

;; Reads the file number after `#`, which may not be 0.
;; Also: LOGADR (K4S79, HVK4)
ReadLogicalFile:
    lda ParsedParameters
    and #PARSED_FILE
    bne Reject
    jsr ReadNextValue
    cpx #0
    beq ToQuantityError
    stx LogicalFile
    lda ParsedParameters
    ora #PARSED_FILE
    sta ParsedParameters
    jmp FirstDelimiter

;; `W` sets the record bit alone; `L` also reads a record length, which may not be 0 or 255.
;; Also: RECLEN (K4S79, HVK4)
ReadRecordLength:
    tax
    lda ParsedParameters
    and #PARSED_RECORD
    bne Reject
    cpx #'W'
    bne ReadLength
    jsr GetNextCharacter
    jmp RecordSeen

;; Reads `L`'s record length.
;; Also: RECOO (K4S79, HVK4)
ReadLength:
    jsr ReadNextValue
    cpx #0
    beq ToQuantityError
    cpx #255
    beq ToQuantityError
    stx RecordLength

;; Sets the record bit.
;; Also: RECON (K4S79, HVK4)
RecordSeen:
    lda ParsedParameters
    ora #PARSED_RECORD
    sta ParsedParameters
    jmp FirstDelimiter

;; Jumps on to <Disk::ParseParameters::Done>.
;; Also: DONE1 (K4S79, HVK4)
ToDone:
    jmp Done

;; Jumps on to <Disk::ParseParameters::FirstName>.
;; Also: NAME11 (K4S79, HVK4)
ToFirstName:
    jmp FirstName

;; Reads `ON U` and a unit.
;; Also: ON1 (K4S79, HVK4)
OnUnit:
    jsr ParseOnUnit
    jmp FirstDelimiter

;; Reads `U` and a unit.
;; Also: UNIT1 (K4S79, HVK4)
Unit:
    jsr ParseUnit
    jmp FirstDelimiter

;; Reads the drive after `D`, 0 or 1, as both the first and the second drive.
;; Also: DRV1 (K4S79, HVK4)
ReadFirstDrive:
    lda ParsedParameters
    and #PARSED_FIRST_DRIVE
    bne Reject
    jsr ReadNextValue
    cpx #DRIVE_COUNT
    bcs ToQuantityError
    stx FirstDrive
    stx SecondDrive
    lda ParsedParameters
    ora #PARSED_FIRST_DRIVE
    sta ParsedParameters
    jmp FirstDelimiter

;; Jumps on to <Disk::QuantityError>.
;; Also: QTYER2 (K4S79, HVK4)
ToQuantityError:
    jmp QuantityError

;; Reads the two characters of the disk ID after `I`; a second `I` is a syntax error.
;; Also: IDENT (K4S79, HVK4)
ReadDiskId:
    lda DiskIdSeen
    and #$FF                    ; sets zero from A, as the load already did
    beq CopyId
    jmp SyntaxError

;; Copies the two ID characters to <DiskId>.
;; Also: IDCON (K4S79, HVK4)
CopyId:
    ldy #0
    ldx #0

;; Advances <TextPointer> to the next ID character.
;; Also: NEXT3 (K4S79, HVK4)
NextIdByte:
    inc TextPointer
    bne StoreIdByte
    inc TextPointer+1

;; Stores one ID character.
;; Also: NEXT4 (K4S79, HVK4)
StoreIdByte:
    lda (TextPointer),y
    sta DiskId,x
    inx
    cpx #DISK_ID_LENGTH
    bcc NextIdByte
    lda #$FF
    sta DiskIdSeen
    jsr GetNextCharacter
    jmp FirstDelimiter

;; Evaluates the first filename and copies it to <FirstFilename>; a leading `@` stays in the copy but not in the
;; kernal's filename.
;; Also: NAME1 (K4S79, HVK4)
FirstName:
    lda ParsedParameters
    and #PARSED_FIRST_NAME
    jsr EvaluateName
    sta FilenameLength
    sta NameLength
    lda #<FirstFilename
    sta FilenamePointer
    lda #>FirstFilename
    sta FilenamePointer+1
    ldy #0

;; Copies one character; a leading `@` moves the kernal's filename past itself.
;; Also: LOOP6 (K4S79, HVK4)
CopyName:
    lda (Pointer1),y
    cpy #0
    bne StoreNameByte
    cmp #REPLACE_PREFIX
    bne StoreNameByte
    inc FilenamePointer
    dec FilenameLength

;; Stores the character in <FirstFilename>.
;; Also: NAMCON (K4S79, HVK4)
StoreNameByte:
    sta FirstFilename,y
    iny
    cpy NameLength
    bcc CopyName
    lda ParsedParameters
    ora #PARSED_FIRST_NAME
    sta ParsedParameters

;; After a parameter of the first part: the end, a comma and another parameter, `ON`, or `TO` and the second part.
;; Also: DELIM1 (K4S79, HVK4)
FirstDelimiter:
    jsr GetCurrentCharacter
    bne ExpectComma
    jmp ToDone

;; A comma goes on with the first part.
;; Also: NXXX (K4S79, HVK4)
ExpectComma:
    cmp #','
    bne CheckOn
    jsr GetNextCharacter
    jmp NextParameter

;; `ON` needs no comma before it.
;; Also: NEXT6 (K4S79, HVK4)
CheckOn:
    cmp #TOKEN_ON
    bne CheckTo
    jmp OnUnit

;; `TO` starts the second part.
;; Also: NEXT6A (K4S79, HVK4)
CheckTo:
    cmp #TOKEN_TO
    beq SecondPart

;; Jumps on to <SyntaxError>, for another character after a parameter.
;; Also: SNER8 (K4S79, HVK4)
RejectDelimiter:
    jmp SyntaxError

;; Dispatches on a parameter of the second part: `D`, `ON`, `U` or a filename.
;; Also: PARSE2 (K4S79, HVK4)
SecondPart:
    jsr GetNextCharacter
    cmp #'D'
    beq ReadSecondDrive
    cmp #TOKEN_ON
    beq SecondOnUnit
    cmp #'U'
    beq SecondUnit
    cmp #'"'
    beq SecondName
    cmp #'('
    beq SecondName

;; Jumps on to <SyntaxError>, for an unknown parameter of the second part.
;; Also: SNER2 (K4S79, HVK4)
RejectSecond:
    jmp SyntaxError

;; Reads the second drive, 0 or 1.
;; Also: DRV2 (K4S79, HVK4)
ReadSecondDrive:
    lda ParsedParameters
    and #PARSED_SECOND_DRIVE
    bne RejectSecond
    jsr ReadNextValue
    cpx #DRIVE_COUNT
    bcs QuantityError
    stx SecondDrive
    lda ParsedParameters
    ora #PARSED_SECOND_DRIVE
    sta ParsedParameters
    jmp SecondDelimiter

;; Reads `ON U` and a unit in the second part.
;; Also: ON2 (K4S79, HVK4)
SecondOnUnit:
    jsr ParseOnUnit
    jmp SecondDelimiter

;; Reads `U` and a unit in the second part.
;; Also: UNIT2 (K4S79, HVK4)
SecondUnit:
    jsr ParseUnit
    jmp SecondDelimiter

;; Evaluates the second filename, which stays where the expression left it.
;; Also: NAME2 (K4S79, HVK4)
SecondName:
    lda ParsedParameters
    and #PARSED_SECOND_NAME
    jsr EvaluateName
    sta SecondFilenameLength
    stx SecondFilenamePointer
    sty SecondFilenamePointer+1
    lda ParsedParameters
    ora #PARSED_SECOND_NAME
    sta ParsedParameters

;; After a parameter of the second part: the end, a comma and another, `ON` or `U`.
;; Also: DELIM2 (K4S79, HVK4)
SecondDelimiter:
    jsr GetCurrentCharacter
    beq Done
    cmp #','
    beq SecondPart
    cmp #TOKEN_ON
    beq SecondOnUnit
    cmp #'U'
    beq SecondUnit

;; Jumps on to <SyntaxError>; the unit and filename helpers branch here too.
;; Also: SNER3 (K4S79, HVK4)
RejectParameter:
    jmp SyntaxError

;; Returns the parameters' bits.
;; Also: DONE (K4S79, HVK4)
Done:
    lda ParsedParameters
    rts
    .endproc

    ;; Gives ILLEGAL QUANTITY ERROR, for a parameter's value out of range.
    ;; Also: QTYERR (K4S79, HVK4)
    .proc QuantityError
    ldx #ERROR_ILLEGAL_QUANTITY
    jmp ReportError
    .endproc

    ;; Requires `U` after the `ON` token, then falls into <Disk::ParseUnit>.
    ;; Out: DeviceNumber = the unit, ParsedParameters = with <PARSED_UNIT> set
    ;; Errors: SYNTAX without the `U`; ILLEGAL QUANTITY for a unit out of range
    ;; Also: ON (K4S79, HVK4)
    .proc ParseOnUnit
    jsr GetNextCharacter
    cmp #'U'
    bne ParseParameters::RejectParameter
    ; Falls into ParseUnit.
    .endproc

    ;; Reads a unit, 3 to 31, into <DeviceNumber>, and sets its bit. Giving a unit twice is not checked.
    ;; Out: DeviceNumber = the unit, ParsedParameters = with <PARSED_UNIT> set
    ;; Errors: ILLEGAL QUANTITY for a unit out of range
    ;; Also: UNIT (K4S79, HVK4)
    .proc ParseUnit
    jsr ReadNextValue
    cpx #UNIT_LIMIT
    bcs QuantityError
    cpx #FIRST_DISK_UNIT
    bcc QuantityError
    stx DeviceNumber
    lda ParsedParameters
    ora #PARSED_UNIT
    sta ParsedParameters
    rts
    .endproc

    ;; Evaluates a filename of 1 to 16 characters, or 17 with a leading `@`, which sets <PARSED_REPLACE>.
    ;;
    ;; A second filename that begins with `@`, once one has, is a syntax error.
    ;; In: zero = set when this filename has not been given yet
    ;; Out: A = the length, `@` included, X = the name's address, low byte, Y = its high byte
    ;; Errors: SYNTAX for a repeated name; ILLEGAL QUANTITY for an empty name; STRING TOO LONG for a long one
    ;; Also: NEWNAM (K4S79, HVK4)
    .proc EvaluateName
    bne ParseParameters::RejectParameter
    jsr EvaluateExpression
    jsr Strings::ReleaseFacString
    tax
    cmp #0
    beq QuantityError
    cmp #FILENAME_LIMIT + 2
    bcs TooLong
    ldy #0
    lda (Pointer1),y
    cmp #REPLACE_PREFIX
    bne CheckLength
    lda ParsedParameters
    and #PARSED_REPLACE
    beq Replace
    jmp SyntaxError

;; Without `@`, the name may have at most 16 characters.
;; Also: LENCHK (K4S79, HVK4)
CheckLength:
    txa
    cmp #FILENAME_LIMIT + 1
    bcs TooLong
    jmp LoadAddress

;; Gives STRING TOO LONG ERROR.
;; Also: ERRLEN (K4S79, HVK4)
TooLong:
    ldx #ERROR_STRING_TOO_LONG
    jmp ReportError

;; Sets the replacement bit.
;; Also: NXXT5 (K4S79, HVK4)
Replace:
    lda ParsedParameters
    ora #PARSED_REPLACE
    sta ParsedParameters

;; Returns the length in A.
;; Also: NEXT5 (K4S79, HVK4)
LoadLength:
    txa

;; Returns the name's address in X and Y.
;; Also: NXX5 (K4S79, HVK4)
LoadAddress:
    ldx Pointer1
    ldy Pointer1+1
    rts
    .endproc

    ;; Advances to the next character, then falls into <Disk::ReadValue>.
    ;; Out: X = the value
    ;; Errors: SYNTAX at the statement's end; ILLEGAL QUANTITY for a value over 255
    ;; Also: GETVAL (K4S79, HVK4)
    .proc ReadNextValue
    jsr GetNextCharacter
    ; Falls into ReadValue.
    .endproc

    ;; Evaluates a parameter's byte value: a number, or an expression in parentheses.
    ;; In: A = the current character, as <GetCurrentCharacter> returns it, with carry clear for a numeral and zero set
    ;;   at the statement's end
    ;; Out: X = the value
    ;; Errors: SYNTAX at the statement's end; ILLEGAL QUANTITY for a value over 255
    ;; Also: GTVL2 (K4S79, HVK4)
    .proc ReadValue
    bne Present
    jmp SyntaxError

;; A character other than a digit must start an expression in parentheses.
;; Also: GTVLCN (UNKN)
Present:
    bcc Number
    jsr CheckOpenParenthesis
    jsr EvaluateByte
    jmp CheckCloseParenthesis

;; A digit starts a number.
;; Also: NUMERC (K4S79, HVK4)
Number:
    jmp EvaluateByte
    .endproc

    .endscope
.endmacro
