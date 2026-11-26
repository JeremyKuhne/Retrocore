; retrocore: style=strict
;; SYSCOM, the record the interpreter and SYSTEM.PASCAL share, from $BDDE, and the memory around it.

;; SYSCOM's layout: the system communication area, 288 bytes. It is UCSD's SYSCOMREC (UCSD20) up to the segment table,
;; which Apple makes 32 entries long where UCSD's has 16. The interpreter reaches most of it by address, through
;; <Syscom>'s words, and the console's keys by offset from <SyscomPointer>.
.struct SyscomRecord
    IO_RESULT .word                 ;; The last I/O call's result.
    ERROR_NUMBER .word              ;; The last execution error.
    BOOT_UNIT .word                 ;; The unit the system booted from.

    ;; For a debugger: 1.1 has none, and nothing uses it.
    ;; Also: BUGSTATE (A2POSRM, UCSD20)
    DEBUG_STATE .word

    DIRECTORY .word                 ;; A directory read onto the heap, or 0.
    ERROR_FRAME .word               ;; The program stack an execution error left.
    GLOBAL_FRAME .word              ;; The calls' copy of <GlobalFrame>.
    LOCAL_FRAME .word               ;; The calls' copy of <LocalFrame>.
    JUMP_TABLE .word                ;; The calls' copy of <JumpTable>.
    PROCEDURE_DICTIONARY .word      ;; The calls' copy of <ProcedureDictionary>.
    MEMORY_TOP .word                ;; Where the program stack starts.
    ERROR_INSTRUCTION .word         ;; The p-code an execution error happened at.

    ;; For a debugger: unused.
    ;; Also: HLTLINE (A2POSRM, UCSD20)
    HALT_LINE .word

    ;; For a debugger, four words: unused.
    ;; Also: BRKPTS (A2POSRM, UCSD20)
    BREAKPOINTS .res 8

    ;; Where UCSD's drivers count retries; Apple's disk driver keeps its own counts.
    ;; Also: RETRIES (UCSD20)
    RETRIES .word

    ;; Nine spare words.
    ;; Also: EXPANSION (UCSD20)
    EXPANSION .res 18

    ;; The clock's low word: 1.1 has no clock, and <StandardProcedures::Time> returns 0 without reading it.
    ;; Also: LOWTIME (UCSD20)
    LOW_TIME .word

    ;; The clock's high word.
    ;; Also: HIGHTIME (UCSD20)
    HIGH_TIME .word

    ;; The terminal's and machine's flags, from SYSTEM.MISCINFO; the interpreter reads none of them.
    ;; Also: MISCINFO (UCSD20)
    MISCELLANEOUS .word

    ;; The terminal's type.
    ;; Also: CRTTYPE (UCSD20)
    TERMINAL_TYPE .word

    ;; The terminal's control characters, from SYSTEM.MISCINFO, which SYSTEM.PASCAL uses.
    ;; Also: CRTCTRL (UCSD20)
    TERMINAL_CONTROL .res 12

    ;; The screen's height, in rows: the first word of the terminal's information, UCSD's CRTINFO (UCSD20).
    ;; Also: CRTINFO_HEIGHT (UCSD20)
    SCREEN_HEIGHT .word

    ;; The screen's width, in columns.
    ;; Also: CRTINFO_WIDTH (UCSD20)
    SCREEN_WIDTH .word

    ;; The key that moves the cursor up.
    ;; Also: CRTINFO_UP (UCSD20)
    UP_KEY .byte

    ;; The key that moves the cursor down.
    ;; Also: CRTINFO_DOWN (UCSD20)
    DOWN_KEY .byte

    ;; The key that moves the cursor left.
    ;; Also: CRTINFO_LEFT (UCSD20)
    LEFT_KEY .byte

    ;; The key that moves the cursor right.
    ;; Also: CRTINFO_RIGHT (UCSD20)
    RIGHT_KEY .byte

    EOF_CHARACTER .byte             ;; The character that ends input from a character unit.

    ;; The key that switches <ConsoleFlags>' <CONSOLE_FLUSHED> on or off.
    ;; Also: CRTINFO_FLUSH (A2POSRM, UCSD20)
    FLUSH_KEY .byte

    ;; The key that runs the break handler.
    ;; Also: CRTINFO_BREAK (A2POSRM, UCSD20)
    BREAK_KEY .byte

    ;; The key that switches <ConsoleFlags>' <CONSOLE_STOPPED> on or off.
    ;; Also: CRTINFO_STOP (A2POSRM, UCSD20)
    STOP_KEY .byte

    ;; The key that deletes a character.
    ;; Also: CRTINFO_CHARDEL (UCSD20)
    CHARACTER_DELETE_KEY .byte

    ;; The character shown for a bad one.
    ;; Also: CRTINFO_BADCH (UCSD20)
    BAD_CHARACTER .byte

    ;; The key that deletes a line.
    ;; Also: CRTINFO_LINEDEL (UCSD20)
    LINE_DELETE_KEY .byte

    ;; The escape key.
    ;; Also: CRTINFO_ALTMODE (UCSD20)
    ESCAPE_KEY .byte

    ;; The character that prefixes a key the terminal sends as two.
    ;; Also: CRTINFO_PREFIX (UCSD20)
    PREFIX .byte

    ;; The end of text key.
    ;; Also: CRTINFO_ETX (UCSD20)
    END_KEY .byte

    ;; The backspace key.
    ;; Also: CRTINFO_BACKSPACE (UCSD20)
    BACKSPACE_KEY .byte

    UNUSED .byte                    ;; Unused, aligning the next word.

    ;; A bit for each key above: whether the terminal sends it after <SyscomRecord::PREFIX>.
    ;; Also: CRTINFO_PREFIXED (UCSD20)
    PREFIXED .word

    SEGMENT_TABLE .res 32 * 6       ;; Where each segment is on disk.
.endstruct

    .assert SyscomRecord::EOF_CHARACTER = 82 && SyscomRecord::SEGMENT_TABLE = 96, "SYSCOM's fields are UCSD's."
    .assert .sizeof(SyscomRecord) = 288, "SYSCOM is 288 bytes."

;; SYSCOM's words, at <Syscom::Start>, as the interpreter reaches them.
.scope Syscom

;; SYSCOM's first byte.
;; Also: SYSCOM (A2POSRM, UCSD20IO)
Start = $BDDE

;; The last I/O call's result.
;; Also: IORSLT (A2POSRM, UCSD20, WK11)
IoResult = Start + SyscomRecord::IO_RESULT

;; The execution error <ExecutionError::Report> records, for SYSTEM.PASCAL's handler.
;; Also: XEQERR (A2POSRM, UCSD20)
ErrorNumber = Start + SyscomRecord::ERROR_NUMBER

;; The unit the system booted from: <Initialize> sets 4.
;; Also: SYSUNIT (A2POSRM, UCSD20)
BootUnit = Start + SyscomRecord::BOOT_UNIT

;; A directory SYSTEM.PASCAL has read onto the heap, or 0 for none. <FreeDirectory> gives the heap back down to it
;; when the stack runs out of room.
;; Also: GDIRP (A2POSRM, UCSD20), SYCGDP (WK11)
Directory = Start + SyscomRecord::DIRECTORY

;; <ProgramStackTop>, less a mark stack frame and the word below it, when an execution error happened.
;; Also: BOMBP (A2POSRM, UCSD20)
ErrorFrame = Start + SyscomRecord::ERROR_FRAME

;; <GlobalFrame>, which the calls keep here as they change it.
;; Also: STKBASE (A2POSRM, UCSD20), SYCBAS (WK11)
SavedGlobalFrame = Start + SyscomRecord::GLOBAL_FRAME

;; <LocalFrame>, which the calls keep here as they change it.
;; Also: LASTMP (A2POSRM, UCSD20), SYCMS (WK11)
SavedLocalFrame = Start + SyscomRecord::LOCAL_FRAME

;; <JumpTable>, which the calls keep here as they change it. UCSD calls this field JTAB (UCSD20), the name of the
;; register it copies.
;; Also: SYCJTB (WK11)
SavedJumpTable = Start + SyscomRecord::JUMP_TABLE

;; <ProcedureDictionary>, which the calls keep here as they change it. UCSD calls this field SEG (UCSD20), the name of
;; the register it copies.
;; Also: SYCSEG (WK11)
SavedProcedureDictionary = Start + SyscomRecord::PROCEDURE_DICTIONARY

;; Where <ProgramStackTop> and <LocalFrame> start, which <Initialize> sets to <MemoryTop>.
;; Also: MEMTOP (UCSD20)
StackTop = Start + SyscomRecord::MEMORY_TOP

;; The <InstructionPointer> an execution error happened at.
;; Also: BOMBIPC (UCSD20), BOMIPC (A2POSRM)
ErrorInstruction = Start + SyscomRecord::ERROR_INSTRUCTION

;; The character that ends input from a character unit. Reading the console, <UREAD at StandardProcedures::UnitRead>
;; fills the rest of its buffer with zeros when it comes; reading another unit, it stops there and keeps it. A raw read
;; does not look for it.
;; Also: CRTINFO_EOF (A2POSRM, UCSD20)
EofCharacter = Start + SyscomRecord::EOF_CHARACTER

;; Where each segment is on disk, a <SegmentEntry> a segment by number. Initialize fills it from SYSTEM.PASCAL's segment
;; dictionary.
;; Also: SEGTABLE (A2POSRM, UCSD20), SYPTBL (WK11)
SegmentTable = Start + SyscomRecord::SEGMENT_TABLE

;; SYSCOM's last 32 bytes, past the 256 that <Initialize>'s first loop clears.
Rest = Start + 256

.endscope

; The tables below SYSCOM.

;; The top of the p-machine's memory, just below <SegmentUses>: where <ProgramStackTop> and <LocalFrame> start.
MemoryTop = $BD1C

;; How many active calls use each segment, a word a segment by number. A segment is read in when its count goes up
;; from 0.
;; Also: SUCTBL (WK11)
SegmentUses = $BD1E

;; The <ProgramStackTop> before each segment was read in, a word a segment by number, given back when its uses fall to
;; 0.
;; Also: SLATBL (WK11)
SegmentKp = $BD5E

;; Where each segment is in memory, a word a segment by number: a code segment's last word, as <ProcedureDictionary>
;; holds it, and a data segment's globals, for <LDE at Pcodes::LoadExtended>, <LAE at Pcodes::LoadExtendedAddress> and
;; <STE at Pcodes::StoreExtended>.
;; Also: IUTBL (WK11)
SegmentAddresses = $BD9E
