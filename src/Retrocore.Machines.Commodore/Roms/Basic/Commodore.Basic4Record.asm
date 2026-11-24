; retrocore: style=strict
; COMMODORE BASIC 4: THE RECORD STATEMENT AND THE DISK STATEMENTS' PARAMETER CHECKS

;; Emits the `RECORD` statement, <Statements::Record>, and the checks the disk statements make of the parameters
;; <Disk::ParseParameters> found, from <Disk::CheckSingleName> to <Disk::RequireNameAndFile>.
.macro CommodoreBasic4Record

    .scope Statements continued
    ; The BASIC 4 extension's statements, which the kernal's jump table at $FF93 leads to.

;; Jumps on to <SyntaxError>; <Statements::Record> branches back here.
;; Also: SYNERR (K4S79, HVK4)
ToSyntaxError:
    jmp SyntaxError

    ;; `RECORD #file, record[, position]`: positions a relative file at a record, and at a byte in it.
    ;;
    ;; The record is a number, or an expression in parentheses; the position is 1 to 254 and defaults to 1. The record
    ;; number is left in <PokeAddress>, which <Disk::PositionRecord> reads as the record number.
    ;; Out: LogicalFile = the file, RecordPosition = the position, PokeAddress = the record number
    ;; Errors: ILLEGAL QUANTITY for file 0 or a position of 0 or 255; SYNTAX for a missing record or text after the
    ;;   position; `FILE NOT OPEN` (from <Disk::PositionRecord>) for a file that is not open
    ;; Also: RECORD (K4S79, HVK4)
    .proc Record

    ; The position defaults to the record's first byte.
    lda #1
    sta RecordPosition

    ; The file number, after `#`.
    jsr GetCurrentCharacter
    lda #'#'
    jsr CheckCharacter
    jsr Disk::ReadValue
    cpx #0
    beq ToQuantityError
    stx LogicalFile

    ; The record: a number, or an expression in parentheses.
    jsr CheckComma
    beq ToSyntaxError
    bcc Number
    jsr CheckOpenParenthesis
    jsr EvaluateExpression
    jsr ConvertToAddress
    jsr CheckCloseParenthesis
    jmp Position

;; A record given as a number.
;; Also: NUMADR (K4S79, HVK4)
Number:
    jsr EvaluateExpression
    jsr ConvertToAddress

;; Reads the optional position, 1 to 254, after a comma; nothing may follow it.
;; Also: REXNEX (K4S79, HVK4)
Position:
    jsr GetCurrentCharacter
    beq ToPositionRecord
    jsr CheckComma
    beq ToSyntaxError
    jsr Disk::ReadValue
    cpx #0
    beq ToQuantityError
    cpx #255
    beq ToQuantityError
    stx RecordPosition
    jsr GetCurrentCharacter
    bne ToSyntaxError

;; Jumps on to <Disk::PositionRecord>, which sends the position to the drive.
;; Also: DONER (K4S79, HVK4)
ToPositionRecord:
    jmp Disk::PositionRecord

;; Jumps on to <Disk::QuantityError>.
;; Also: QTYER1 (K4S79, HVK4)
ToQuantityError:
    jmp Disk::QuantityError
    .endproc

    .endscope

    .scope Disk continued
    ; The checks of the parsed parameters. Each takes A = <ParsedParameters>, as <Disk::ParseParameters> returns it,
    ; rejects the parameters its statement does not take with SYNTAX ERROR, and returns A = <ParsedParameters>, but
    ; for <Disk::CheckDriveOnly>, which returns 0. They test only the parameters' bits, so `I`, `R` and a repeated
    ; unit, which set none, pass every check.

    ;; `HEADER` and `SCRATCH`: rejects all but a first name, a unit and a first drive, then branches to
    ;; <Disk::RequireFirstName>'s test.
    ;; In: A = the parsed parameters
    ;; Out: A = <ParsedParameters>
    ;; Errors: SYNTAX for another parameter or a missing name
    ;; Also: CHK1 (K4S79, HVK4)
    .proc CheckSingleName
    and #PARSED_SECOND_NAME | PARSED_FILE | PARSED_SECOND_DRIVE | PARSED_RECORD | PARSED_REPLACE
    beq RequireFirstName
    ; Falls into ToSyntaxError.
    .endproc

;; Jumps on to <SyntaxError>; every check branches here.
;; Also: CHKER1 (K4S79, HVK4)
ToSyntaxError:
    jmp SyntaxError

    ;; Requires a first filename.
    ;; Out: A = <ParsedParameters>
    ;; Errors: SYNTAX for a missing name
    ;; Also: CHK2 (K4S79, HVK4)
    .proc RequireFirstName
    lda ParsedParameters
    and #PARSED_FIRST_NAME
    cmp #PARSED_FIRST_NAME
    bne ToSyntaxError
    lda ParsedParameters
    rts
    .endproc

    ;; `COLLECT` and `CATALOG`: rejects all but a unit and a first drive.
    ;; In: A = the parsed parameters
    ;; Out: A = 0
    ;; Errors: SYNTAX for another parameter
    ;; Also: CHK3 (K4S79, HVK4)
    .proc CheckDriveOnly
    and #PARSED_FIRST_NAME | PARSED_SECOND_NAME | PARSED_FILE | PARSED_SECOND_DRIVE | PARSED_RECORD | PARSED_REPLACE
    bne ToSyntaxError
    rts
    .endproc

    ;; `COPY` and `CONCAT`: rejects a file number, a record and a replacement, then falls into
    ;; <Disk::RequireTwoNames>.
    ;; In: A = the parsed parameters
    ;; Out: A = <ParsedParameters>
    ;; Errors: SYNTAX for another parameter or a missing name
    ;; Also: CHK4 (K4S79, HVK4)
    .proc CheckTwoNames
    and #PARSED_FILE | PARSED_RECORD | PARSED_REPLACE
    bne ToSyntaxError
    lda ParsedParameters
    ; Falls into RequireTwoNames.
    .endproc

    ;; Requires both filenames; `RENAME` calls it first.
    ;; In: A = the parsed parameters
    ;; Out: A = <ParsedParameters>
    ;; Errors: SYNTAX for a missing name
    ;; Also: CHK5 (K4S79, HVK4)
    .proc RequireTwoNames
    and #PARSED_FIRST_NAME | PARSED_SECOND_NAME
    cmp #PARSED_FIRST_NAME | PARSED_SECOND_NAME
    bne ToSyntaxError
    lda ParsedParameters
    rts
    .endproc

    ;; `DOPEN` and `APPEND`: requires a first filename and a file number.
    ;; In: A = the parsed parameters
    ;; Out: A = <ParsedParameters>
    ;; Errors: SYNTAX for a missing name or file number
    ;; Also: CHK6 (K4S79, HVK4)
    .proc RequireNameAndFile
    and #PARSED_FIRST_NAME | PARSED_FILE
    cmp #PARSED_FIRST_NAME | PARSED_FILE
    bne ToSyntaxError
    lda ParsedParameters
    rts
    .endproc

    .endscope
.endmacro
