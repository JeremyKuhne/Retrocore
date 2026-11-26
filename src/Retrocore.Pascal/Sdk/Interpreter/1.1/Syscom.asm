; retrocore: style=strict
;; SYSCOM: the record the interpreter and SYSTEM.PASCAL share, from $BDDE, and the memory around it.

;; SYSCOM's first word.
Syscom = $BDDE

;; The last I/O call's result.
SysIoResult = Syscom

;; The execution error <ExecutionError::Report> records, for SYSTEM.PASCAL's handler.
SysErrorNumber = Syscom + 2

;; The unit the system booted from: <Initialize> sets 4.
SysBootUnit = Syscom + 4

;; A directory SYSTEM.PASCAL has read onto the heap, or 0 for none. <FreeDirectory> gives the heap back down to it
;; when the stack runs out of room.
SysDirectory = Syscom + 8

;; <KP>, less a mark stack frame and the word below it, when an execution error happened.
SysErrorStack = Syscom + 10

;; <BASE>, which the calls keep here as they change it.
SysBase = Syscom + 12

;; <MP>, which the calls keep here as they change it.
SysMp = Syscom + 14

;; <JTAB>, which the calls keep here as they change it.
SysJtab = Syscom + 16

;; <SEG>, which the calls keep here as they change it.
SysSeg = Syscom + 18

;; Where <KP> and <MP> start, which <Initialize> sets to <MemoryTop>.
SysMemoryTop = Syscom + 20

;; The <IPC> an execution error happened at.
SysIpc = Syscom + 22

;; The character that ends input from a character unit. Reading the console, <UREAD at UnitIo::CspUREAD> fills the rest
;; of its buffer with zeros when it comes; reading another unit, it stops there and keeps it. A raw read does not look
;; for it.
SysEofCharacter = Syscom + 82

;; Where each segment is on disk, 6 bytes a segment by number: its unit, its first block, and its size in bytes.
;; Initialize fills it from SYSTEM.PASCAL's segment dictionary.
SegmentTable = Syscom + 96

;; 32 bytes after SYSCOM, which <Initialize> clears with it.
SyscomExtra = Syscom + 256

; The tables below SYSCOM.

;; The top of the p-machine's memory, just below <SegmentUses>: where <KP> and <MP> start.
MemoryTop = $BD1C

;; How many active calls use each segment, a word a segment by number. A segment is read in when its count goes up
;; from 0.
SegmentUses = $BD1E

;; The <KP> before each segment was read in, a word a segment by number, given back when its uses fall to 0.
SegmentKp = $BD5E

;; Where each segment is in memory, a word a segment by number: a code segment's last word, as <SEG> holds it, and a
;; data segment's globals, for <LDE at OpLDE>, <LAE at OpLAE> and <STE at OpSTE>.
SegmentAddresses = $BD9E
