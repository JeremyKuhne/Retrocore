; retrocore: style=strict
;; DOS 3.3 and 3.2 command interpreter: the command and message tables
;;
;; The data the command scanner (CommandScan.asm) works from, at $A884-$AA4E where DOS runs (Apple's CMDTBLS
;; module): the commands' names, which operands and options each one takes, the option letters and their ranges,
;; and the text of the error messages <Errors::Report> prints (DosGoer.asm). The handlers' addresses are in
;; <CommandHandlers>, in DosInit.asm. Commands are numbered by their place in <CommandNames>, 0 for INIT to 27
;; for VERIFY (the COMMAND_ codes), and <CommandSyntax> and <CommandHandlers> are in the same order.

; The commands' numbers, in the order of CommandNames. <CommandOffset> holds a command's number times 2, its offset in
; CommandSyntax and CommandHandlers.

;; INIT, which formats a disk and writes DOS and the greeting program to it.
COMMAND_INIT = 0

;; LOAD, which loads a BASIC program.
COMMAND_LOAD = 1

;; SAVE, which saves the BASIC program.
COMMAND_SAVE = 2

;; RUN, which loads and runs a BASIC program.
COMMAND_RUN = 3

;; CHAIN, which loads and runs an Integer BASIC program, keeping the variables.
COMMAND_CHAIN = 4

;; DELETE, which deletes a file.
COMMAND_DELETE = 5

;; LOCK, which locks a file against changes.
COMMAND_LOCK = 6

;; UNLOCK, which unlocks a file.
COMMAND_UNLOCK = 7

;; CLOSE, which closes one file, or all.
COMMAND_CLOSE = 8

;; READ, which takes BASIC's input from a text file.
COMMAND_READ = 9

;; EXEC, which takes BASIC's input, commands included, from a text file.
COMMAND_EXEC = 10

;; WRITE, which sends BASIC's output to a text file.
COMMAND_WRITE = 11

;; POSITION, which moves through a text file by lines.
COMMAND_POSITION = 12

;; OPEN, which opens a text file, creating it if need be.
COMMAND_OPEN = 13

;; APPEND, which opens a text file at its end.
COMMAND_APPEND = 14

;; RENAME, which renames a file.
COMMAND_RENAME = 15

;; CATALOG, which lists the files on a disk.
COMMAND_CATALOG = 16

;; MON, which shows commands, input or output from files on the screen.
COMMAND_MON = 17

;; NOMON, which stops showing them.
COMMAND_NOMON = 18

;; PR#, which sends output to a slot.
COMMAND_PR_NUMBER = 19

;; IN#, which takes input from a slot.
COMMAND_IN_NUMBER = 20

;; MAXFILES, which sets how many file buffers DOS keeps.
COMMAND_MAXFILES = 21

;; FP, which selects Applesoft.
COMMAND_FP = 22

;; `INT`, which selects Integer BASIC.
COMMAND_INT = 23

;; BSAVE, which saves memory as a binary file.
COMMAND_BSAVE = 24

;; BLOAD, which loads a binary file.
COMMAND_BLOAD = 25

;; BRUN, which loads and runs a binary file.
COMMAND_BRUN = 26

;; VERIFY, which reads a file to check it.
COMMAND_VERIFY = 27

; The first byte of a command's CommandSyntax entry: its operands.

;; The command may have no operands, and then the line goes to BASIC (LOAD, SAVE and RUN, which BASIC has too).
;; Also: NPB (DOS33, DOS31)
SYNTAX_NONE_TO_BASIC = $80

;; The command may have no operands, and then DOS still carries it out.
;; Also: NPE (DOS33, DOS31)
SYNTAX_NONE_ALLOWED = $40

;; The command takes a file name.
;; Also: FN1 (DOS33, DOS31)
SYNTAX_FILE_NAME = $20

;; The command takes a second file name (RENAME).
;; Also: FN2 (DOS33, DOS31)
SYNTAX_SECOND_NAME = $10

;; The command takes a slot number, 0-7 (PR#, IN#).
;; Also: NUM1 (DOS33, DOS31)
SYNTAX_SLOT = $08

;; The command takes a count, 1-16 (MAXFILES).
;; Also: NUM2 (DOS33, DOS31)
SYNTAX_COUNT = $04

;; The command may only be given by a running program: typed in direct mode, it is NOT DIRECT COMMAND.
;; Also: RNONLY (DOS33)
SYNTAX_PROGRAM_ONLY = $02

;; The command may create the file it names. <FileManager::OpenFile> (FileOpenCloseReadWrite.asm) tests it, by shifting
;; it into the carry, before it creates a missing file.
;; Also: CREFLG (DOS33)
SYNTAX_CREATES = $01

; The second byte: the options the command allows. <GivenKeywords> has the same bits for the options given, and
; OptionBits gives the bit for each letter.

;; ,V: the volume number.
;; Also: V (DOS33, DOS31)
OPTION_VOLUME = $40

;; ,D: the drive.
;; Also: D (DOS33, DOS31)
OPTION_DRIVE = $20

;; ,S: the slot.
;; Also: S (DOS33, DOS31)
OPTION_SLOT = $10

;; ,L: the record length (OPEN) or the byte count (BSAVE).
;; Also: L (DOS33, DOS31)
OPTION_LENGTH = $08

;; ,R: the record number (READ, WRITE, POSITION, EXEC).
;; Also: R (DOS33, DOS31)
OPTION_RECORD = $04

;; ,B: the byte offset (READ, WRITE).
;; Also: B (DOS33, DOS31)
OPTION_BYTE = $02

;; ,A: the address (BSAVE, BLOAD, BRUN). DOS 3.1's listing calls it A, which is the register's name here.
;; Also: ADR (DOS33)
OPTION_ADDRESS = $01

;; ,C ,I or ,O (MON, NOMON).
;; Also: CIO (DOS33, DOS31)
OPTION_ECHO = $80

;; The options that pick the disk: volume, drive and slot.
OPTIONS_DISK = OPTION_VOLUME|OPTION_DRIVE|OPTION_SLOT

; The MON and NOMON options' bits in EchoOptions and EchoFlags. ECHO_COMMANDS, for ,C, is $40, in FileManagerEntry.asm.

;; ,I: show what is read from disk.
;; Also: MI (DOS33, DOS31)
ECHO_INPUT = $20

;; ,O: show what is written to disk.
;; Also: MO (DOS33, DOS31)
ECHO_OUTPUT = $10

;; The layout of a command's entry in <CommandSyntax>.
.struct CommandSyntaxEntry
    OPERANDS .byte ;; the operands it takes, SYNTAX_ bits
    OPTIONS .byte ;; the options it allows, OPTION_ bits
.endstruct

;; The layout of an option's entry in <OptionRanges>.
.struct OptionRange
    LOW .word ;; the lowest value allowed
    HIGH .word ;; the highest value allowed
.endstruct

; The macros for the tables.

;; How many names <CommandName> has placed, which it checks against the COMMAND_ codes.
.set CommandNameCount, 0

;; One entry of <CommandNames>: a command's name, with bit 7 set on its last character.
;; Parameters: command = the COMMAND_ code, text = the name
.macro CommandName command, text
    .assert command = CommandNameCount, "CommandNames is in the order of the COMMAND_ codes."
    .set CommandNameCount, CommandNameCount + 1
    MarkedText text
.endmacro

;; One entry of <CommandSyntax>: a command's operands and the options it allows.
;; Parameters: command = the COMMAND_ code, operands = its SYNTAX_ bits, options = its OPTION_ bits
.macro Syntax command, operands, options
    .assert * - CommandSyntax = command * .sizeof(CommandSyntaxEntry), "CommandSyntax is in COMMAND_ order."
    .byte operands, options
.endmacro

;; One entry of <OptionRanges>: the lowest and highest value an option may have.
;; Parameters: low = the lowest value, high = the highest
.macro OptionLimits low, high
    .word low, high
.endmacro

;; One message of <ErrorMessages>, with bit 7 set on its last character.
;; Parameters: offset = its MESSAGE_ offset, text = the message
.macro Message offset, text
    .assert * - ErrorMessages = offset, "The message is at its MESSAGE_ offset."
    MarkedText text
.endmacro

;; One entry of <ErrorMessageOffsets>: an error's message.
;; Parameters: error = the ERROR_ code, offset = its MESSAGE_ offset
.macro MessageOffset error, offset
    .assert * - ErrorMessageOffsets = error, "ErrorMessageOffsets is in ERROR_ order."
    .byte offset
.endmacro

;; The end of the relocator's first range of code, <InterpreterCodeStart> to here: the tables below hold no
;; addresses.
;; Also: EC1 (DOS33, DOS31)
InterpreterCodeEnd:

;; The command names, in the order of the COMMAND_ codes, each with bit 7 set on its last character; a 0 ends the
;; table.
;;
;; At $A884 where DOS runs. <Scanner::Scan> compares the names in order and takes the first that matches all the
;; way through, so a command line may go on after a name with no separator ("CATALOGD2" is CATALOG,D2).
;; Also: CMDNTB (DOS33, DOS31)
CommandNames:
.assert MASTER || * = $A884, "CommandNames is at $A884 where DOS runs."
    CommandName COMMAND_INIT, "INIT"
    CommandName COMMAND_LOAD, "LOAD"
    CommandName COMMAND_SAVE, "SAVE"
    CommandName COMMAND_RUN, "RUN"
    CommandName COMMAND_CHAIN, "CHAIN"
    CommandName COMMAND_DELETE, "DELETE"
    CommandName COMMAND_LOCK, "LOCK"
    CommandName COMMAND_UNLOCK, "UNLOCK"
    CommandName COMMAND_CLOSE, "CLOSE"
    CommandName COMMAND_READ, "READ"
    CommandName COMMAND_EXEC, "EXEC"
    CommandName COMMAND_WRITE, "WRITE"
    CommandName COMMAND_POSITION, "POSITION"
    CommandName COMMAND_OPEN, "OPEN"
    CommandName COMMAND_APPEND, "APPEND"
    CommandName COMMAND_RENAME, "RENAME"
    CommandName COMMAND_CATALOG, "CATALOG"
    CommandName COMMAND_MON, "MON"
    CommandName COMMAND_NOMON, "NOMON"
    CommandName COMMAND_PR_NUMBER, "PR#"
    CommandName COMMAND_IN_NUMBER, "IN#"
    CommandName COMMAND_MAXFILES, "MAXFILES"
    CommandName COMMAND_FP, "FP"
    CommandName COMMAND_INT, "INT"
    CommandName COMMAND_BSAVE, "BSAVE"
    CommandName COMMAND_BLOAD, "BLOAD"
    CommandName COMMAND_BRUN, "BRUN"
    CommandName COMMAND_VERIFY, "VERIFY"
    .byte 0

;; Each command's operands and allowed options, a <CommandSyntaxEntry> a command, in the order of the COMMAND_
;; codes; <CommandOffset>, the command's number times 2, indexes it.
;; Also: CMDSTB (DOS33, DOS31)
CommandSyntax:
    Syntax COMMAND_INIT, SYNTAX_FILE_NAME|SYNTAX_CREATES, OPTIONS_DISK
    Syntax COMMAND_LOAD, SYNTAX_NONE_TO_BASIC|SYNTAX_FILE_NAME, OPTIONS_DISK
    Syntax COMMAND_SAVE, SYNTAX_NONE_TO_BASIC|SYNTAX_FILE_NAME|SYNTAX_CREATES, OPTIONS_DISK
    Syntax COMMAND_RUN, SYNTAX_NONE_TO_BASIC|SYNTAX_FILE_NAME, OPTIONS_DISK
    Syntax COMMAND_CHAIN, SYNTAX_FILE_NAME, OPTIONS_DISK
    Syntax COMMAND_DELETE, SYNTAX_FILE_NAME, OPTIONS_DISK
    Syntax COMMAND_LOCK, SYNTAX_FILE_NAME, OPTIONS_DISK
    Syntax COMMAND_UNLOCK, SYNTAX_FILE_NAME, OPTIONS_DISK
    Syntax COMMAND_CLOSE, SYNTAX_NONE_ALLOWED|SYNTAX_FILE_NAME, 0
    Syntax COMMAND_READ, SYNTAX_FILE_NAME|SYNTAX_PROGRAM_ONLY, OPTION_BYTE|OPTION_RECORD
    Syntax COMMAND_EXEC, SYNTAX_FILE_NAME, OPTION_RECORD|OPTIONS_DISK
    Syntax COMMAND_WRITE, SYNTAX_FILE_NAME|SYNTAX_PROGRAM_ONLY, OPTION_BYTE|OPTION_RECORD
    Syntax COMMAND_POSITION, SYNTAX_FILE_NAME|SYNTAX_PROGRAM_ONLY, OPTION_RECORD
    Syntax COMMAND_OPEN, SYNTAX_FILE_NAME|SYNTAX_PROGRAM_ONLY|SYNTAX_CREATES, OPTION_LENGTH|OPTIONS_DISK
    Syntax COMMAND_APPEND, SYNTAX_FILE_NAME|SYNTAX_PROGRAM_ONLY, OPTIONS_DISK
    Syntax COMMAND_RENAME, SYNTAX_FILE_NAME|SYNTAX_SECOND_NAME, OPTIONS_DISK
    Syntax COMMAND_CATALOG, SYNTAX_NONE_ALLOWED, OPTIONS_DISK
    Syntax COMMAND_MON, SYNTAX_NONE_ALLOWED, OPTION_ECHO
    Syntax COMMAND_NOMON, SYNTAX_NONE_ALLOWED, OPTION_ECHO
    Syntax COMMAND_PR_NUMBER, SYNTAX_SLOT, 0
    Syntax COMMAND_IN_NUMBER, SYNTAX_SLOT, 0
    Syntax COMMAND_MAXFILES, SYNTAX_COUNT, 0
    Syntax COMMAND_FP, SYNTAX_NONE_ALLOWED, OPTIONS_DISK
    Syntax COMMAND_INT, SYNTAX_NONE_ALLOWED, 0
    Syntax COMMAND_BSAVE, SYNTAX_FILE_NAME|SYNTAX_CREATES, OPTIONS_DISK|OPTION_ADDRESS|OPTION_LENGTH
    Syntax COMMAND_BLOAD, SYNTAX_FILE_NAME, OPTIONS_DISK|OPTION_ADDRESS
    Syntax COMMAND_BRUN, SYNTAX_FILE_NAME, OPTIONS_DISK|OPTION_ADDRESS
    Syntax COMMAND_VERIFY, SYNTAX_FILE_NAME, OPTIONS_DISK

;; The option letters, with bit 7 set. An option's number is its place here, from 0; V to A are also the order of
;; their values in <KeywordValues> (<KeywordVolume> to <KeywordAddress>) and of their ranges in <OptionRanges>.
;; Also: OPTAB1 (DOS33, DOS31)
OptionLetters:
    .byte 'V'|$80, 'D'|$80, 'S'|$80, 'L'|$80
    .byte 'R'|$80, 'B'|$80, 'A'|$80, 'C'|$80
    .byte 'I'|$80, 'O'|$80

;; The number of option letters in <OptionLetters>, 10.
;; Also: OPT1L (DOS33, DOS31)
OPTION_LETTER_COUNT = *-OptionLetters

;; The bit for each letter of <OptionLetters>. Those with <OPTION_ECHO> (bit 7) take no number: the rest of the
;; byte is their <EchoFlags> bit.
;; Also: OPTAB2 (DOS33, DOS31)
OptionBits:
    .byte OPTION_VOLUME, OPTION_DRIVE, OPTION_SLOT, OPTION_LENGTH
    .byte OPTION_RECORD, OPTION_BYTE, OPTION_ADDRESS, OPTION_ECHO|ECHO_COMMANDS
    .byte OPTION_ECHO|ECHO_INPUT, OPTION_ECHO|ECHO_OUTPUT

;; The lowest and highest value of each numbered option, V to A: an <OptionRange> an option.
;; Also: OPTAB3 (DOS33, DOS31)
OptionRanges:
    OptionLimits 0, 254             ; V: volume 0-254; 0 matches any disk
    OptionLimits 1, 2               ; D: drive 1-2
    OptionLimits 1, 7               ; S: slot 1-7
    OptionLimits 1, 32767           ; L: 1-32767
    OptionLimits 0, 32767           ; R: 0-32767
    OptionLimits 0, 32767           ; B: 0-32767
    OptionLimits 0, $FFFF           ; A: any address

; The offsets of the error messages' texts in ErrorMessages, by error number.

;; The offset of error 1's text, LANGUAGE NOT AVAILABLE, in <ErrorMessages>.
;; Also: EM1 (DOS33)
MESSAGE_LANGUAGE_NOT_AVAILABLE = 3

;; The offset of error 2's text, RANGE ERROR, in <ErrorMessages>.
;; Also: EM2 (DOS33, DOS31)
MESSAGE_RANGE = 25

;; The offset of error 3's text, RANGE ERROR, in <ErrorMessages>. It shares RANGE ERROR's text.
;; Also: EM3 (DOS33, DOS31)
MESSAGE_TRANSFER_RANGE = 25

;; The offset of error 4's text, WRITE PROTECTED, in <ErrorMessages>.
;; Also: EM4 (DOS33, DOS31)
MESSAGE_WRITE_PROTECTED = 36

;; The offset of error 5's text, END OF DATA, in <ErrorMessages>.
;; Also: EM5 (DOS33, DOS31)
MESSAGE_END_OF_DATA = 51

;; The offset of error 6's text, FILE NOT FOUND, in <ErrorMessages>.
;; Also: EM6 (DOS33, DOS31)
MESSAGE_FILE_NOT_FOUND = 62

;; The offset of error 7's text, VOLUME MISMATCH, in <ErrorMessages>.
;; Also: EM7 (DOS33, DOS31)
MESSAGE_VOLUME_MISMATCH = 76

;; The offset of error 8's text, I/O ERROR, in <ErrorMessages>.
;; Also: EM8 (DOS33, DOS31)
MESSAGE_IO = 91

;; The offset of error 9's text, DISK FULL, in <ErrorMessages>.
;; Also: EM9 (DOS33, DOS31)
MESSAGE_DISK_FULL = 100

;; The offset of error 10's text, FILE LOCKED, in <ErrorMessages>.
;; Also: EM10 (DOS33, DOS31)
MESSAGE_FILE_LOCKED = 109

;; The offset of error 11's text, SYNTAX ERROR, in <ErrorMessages>.
;; Also: EM11 (DOS33, DOS31)
MESSAGE_SYNTAX = 120

;; The offset of error 12's text, NO BUFFERS AVAILABLE, in <ErrorMessages>.
;; Also: EM12 (DOS33, DOS31)
MESSAGE_NO_BUFFERS = 132

;; The offset of error 13's text, FILE TYPE MISMATCH, in <ErrorMessages>.
;; Also: EM13 (DOS33, DOS31)
MESSAGE_FILE_TYPE_MISMATCH = 152

;; The offset of error 14's text, PROGRAM TOO LARGE, in <ErrorMessages>.
;; Also: EM14 (DOS33, DOS31)
MESSAGE_PROGRAM_TOO_LARGE = 170

;; The offset of error 15's text, NOT DIRECT COMMAND, in <ErrorMessages>.
;; Also: EM15 (DOS33)
MESSAGE_NOT_DIRECT = 187

;; The error messages, each with bit 7 set on its last character, at the MESSAGE_ offsets.
;;
;; The table starts with return, bell, return ($0D has its top bit clear only so that the printing goes on), which
;; <Errors::Report> prints before each message. <ErrorMessageOffsets> lists the messages by error number.
;; Also: EMSG (DOS33, DOS31)
ErrorMessages:
    .byte $0D, $07, $8D
    Message MESSAGE_LANGUAGE_NOT_AVAILABLE, "LANGUAGE NOT AVAILABLE"
    Message MESSAGE_RANGE, "RANGE ERROR"
.assert MESSAGE_TRANSFER_RANGE = MESSAGE_RANGE, "Errors 2 and 3 share their text."
    Message MESSAGE_WRITE_PROTECTED, "WRITE PROTECTED"
    Message MESSAGE_END_OF_DATA, "END OF DATA"
    Message MESSAGE_FILE_NOT_FOUND, "FILE NOT FOUND"
    Message MESSAGE_VOLUME_MISMATCH, "VOLUME MISMATCH"
    Message MESSAGE_IO, "I/O ERROR"
    Message MESSAGE_DISK_FULL, "DISK FULL"
    Message MESSAGE_FILE_LOCKED, "FILE LOCKED"
    Message MESSAGE_SYNTAX, "SYNTAX ERROR"
    Message MESSAGE_NO_BUFFERS, "NO BUFFERS AVAILABLE"
    Message MESSAGE_FILE_TYPE_MISMATCH, "FILE TYPE MISMATCH"
    Message MESSAGE_PROGRAM_TOO_LARGE, "PROGRAM TOO LARGE"
    Message MESSAGE_NOT_DIRECT, "NOT DIRECT COMMAND"
    .byte $8D                       ; never printed: Errors::PrintMessage stops at the D above

;; Each error number's message, as its MESSAGE_ offset in <ErrorMessages>; entry 0 is the return, bell, return.
;; Also: EMDTB (DOS33, DOS31)
ErrorMessageOffsets:
    .byte 0
    MessageOffset ERROR_LANGUAGE_NOT_AVAILABLE, MESSAGE_LANGUAGE_NOT_AVAILABLE
    MessageOffset ERROR_RANGE, MESSAGE_RANGE
    MessageOffset ERROR_TRANSFER_RANGE, MESSAGE_TRANSFER_RANGE
    MessageOffset ERROR_WRITE_PROTECTED, MESSAGE_WRITE_PROTECTED
    MessageOffset ERROR_END_OF_DATA, MESSAGE_END_OF_DATA
    MessageOffset ERROR_FILE_NOT_FOUND, MESSAGE_FILE_NOT_FOUND
    MessageOffset ERROR_VOLUME_MISMATCH, MESSAGE_VOLUME_MISMATCH
    MessageOffset ERROR_IO, MESSAGE_IO
    MessageOffset ERROR_DISK_FULL, MESSAGE_DISK_FULL
    MessageOffset ERROR_FILE_LOCKED, MESSAGE_FILE_LOCKED
    MessageOffset ERROR_SYNTAX, MESSAGE_SYNTAX
    MessageOffset ERROR_NO_BUFFERS, MESSAGE_NO_BUFFERS
    MessageOffset ERROR_FILE_TYPE_MISMATCH, MESSAGE_FILE_TYPE_MISMATCH
    MessageOffset ERROR_PROGRAM_TOO_LARGE, MESSAGE_PROGRAM_TOO_LARGE
    MessageOffset ERROR_NOT_DIRECT, MESSAGE_NOT_DIRECT
