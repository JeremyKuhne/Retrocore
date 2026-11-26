; retrocore: style=strict
;; SYSCOM: the record the interpreter and SYSTEM.PASCAL share, from $BDDE, and the memory around it.

;; SYSCOM's first word.
;; Also: SYSCOM (A2POSRM, UCSD20IO), SYSCOMREC (UCSD20)
Syscom = $BDDE

;; The last I/O call's result.
;; Also: IORSLT (A2POSRM, UCSD20, WK11)
SysIoResult = Syscom

;; The execution error <ExecutionError::Report> records, for SYSTEM.PASCAL's handler.
;; Also: XEQERR (A2POSRM, UCSD20)
SysErrorNumber = Syscom + 2

;; The unit the system booted from: <Initialize> sets 4.
;; Also: SYSUNIT (A2POSRM, UCSD20)
SysBootUnit = Syscom + 4

;; A directory SYSTEM.PASCAL has read onto the heap, or 0 for none. <FreeDirectory> gives the heap back down to it
;; when the stack runs out of room.
;; Also: GDIRP (A2POSRM, UCSD20), SYCGDP (WK11)
SysDirectory = Syscom + 8

;; <ProgramStackTop>, less a mark stack frame and the word below it, when an execution error happened.
;; Also: BOMBP (A2POSRM, UCSD20)
SysErrorStack = Syscom + 10

;; <GlobalFrame>, which the calls keep here as they change it.
;; Also: STKBASE (A2POSRM, UCSD20), SYCBAS (WK11)
SysBase = Syscom + 12

;; <LocalFrame>, which the calls keep here as they change it.
;; Also: LASTMP (A2POSRM, UCSD20), SYCMS (WK11)
SysMp = Syscom + 14

;; <JumpTable>, which the calls keep here as they change it. UCSD calls this field JTAB (UCSD20), the name of the
;; register it copies.
;; Also: SYCJTB (WK11)
SysJtab = Syscom + 16

;; <ProcedureDictionary>, which the calls keep here as they change it. UCSD calls this field SEG (UCSD20), the name of
;; the register it copies.
;; Also: SYCSEG (WK11)
SysSeg = Syscom + 18

;; Where <ProgramStackTop> and <LocalFrame> start, which <Initialize> sets to <MemoryTop>.
;; Also: MEMTOP (UCSD20)
SysMemoryTop = Syscom + 20

;; The <InstructionPointer> an execution error happened at.
;; Also: BOMBIPC (UCSD20), BOMIPC (A2POSRM)
SysIpc = Syscom + 22

;; The character that ends input from a character unit. Reading the console, <UREAD at StandardProcedures::UnitRead>
;; fills the rest of its buffer with zeros when it comes; reading another unit, it stops there and keeps it. A raw read
;; does not look for it.
;; Also: CRTINFO_EOF (A2POSRM, UCSD20)
SysEofCharacter = Syscom + 82

;; Where each segment is on disk, 6 bytes a segment by number: its unit, its first block, and its size in bytes.
;; Initialize fills it from SYSTEM.PASCAL's segment dictionary.
;; Also: SEGTABLE (A2POSRM, UCSD20), SYPTBL (WK11)
SegmentTable = Syscom + 96

;; 32 bytes after SYSCOM, which <Initialize> clears with it.
SyscomExtra = Syscom + 256

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
