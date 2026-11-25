# The Disk II boot ROMs and sequencers: conversion log

`src/Retrocore.Machines.Apple2/Roms/DiskII/`: the roots `Boot16.asm` (341-0027) and `Boot13.asm` (341-0009), which
set `SECTORS` and include `Boot.asm`, and `Sequencer16.asm` (341-0028) and `Sequencer13.asm` (341-0010), which add
their reading tables to `Sequencer.asm`. Also converted with them: `Software/LanguageCardFinder.asm`, the System
Master HELLO's POKEd test. Documents cited: DOS33 and DOS31 (on the switches only), UNKN.

## Sources

- No document in hand gives the boot ROM's names. Beneath Apple DOS's chapter 8 describes `BOOT 0` by address and
  names none of its routines or page-zero bytes; Andy McFadden's commented disassembly (docs/DiskII.md) could not be
  fetched to check. The names this source had before (BOOT0, READ, SLOTX16, DENIB ...) are kept in `Also:` as UNKN.
- Sather's Understanding the Apple II (chapter 9, Table 9.3, checked against the archive's text) gives the sequencer
  commands as CLR, NOP, SL0, SL1, SR and LD, and says they are his own, "in the absence of any labels and formats
  published by Apple". They are named in prose (D6), so the bibliography has no key for it.
- The macros `ENTRY`, `READING`, `WRITING` and `SEQUENCER`, the generated `SEQ_xx`, and the language card finder's
  `Status`, `Finder` and its locals are the SDK's own: renamed (but `Status`) with no `Also:`.

## Decisions

- D1. Names shared with DOS are DOS's ([Dos.md](Dos.md)): the page-zero bytes `BufferPointer`, `SlotTimes16` and
  `Sector` (P15, P16), the switches `Phase0Off`, `Phase0On`, `MotorOn`, `SelectDrive1`, `DataLatch` and `ReadMode`
  (X9), the marks `PROLOGUE_FIRST`, `PROLOGUE_SECOND`, `ADDRESS_MARK` and `DATA_MARK`, the table `ReadTranslate`
  (DNIBL), `LowBits`, `LOW_BITS_SIZE` and `GROUP_COUNT`, and the reader's locals (`WaitD5`, `CheckD5`, `WaitAA`,
  `WaitOdd`, `WaitEven`).
- D2. The boot ROM defines its six switches itself rather than including Dos/RwtsEquates.asm, which brings RWTS's
  variables and DOS's `DOS32` switch. Each switch's `Also:` cites DOS's name for the same switch with DOS's
  documents (PHASEOFF, Q6L ...), beside the source's old name as UNKN where it differs (MOTORON is both).
- D3. Page-zero bytes are aliases of IIeEquates' names (`BufferPointer = LowResBase`), as in DOS (P14). BITS, which
  holds a nibble, a half byte or a count by turns, is `Scratch`.
- D4. Three routines, each one definition for both ROMs with `.if SECTORS` where they differ (the owner's D5):
  `Boot` (BOOT0), which falls into `ReadSector` (READ), and the 13-sector ROM's `PostNibble` (DENIB), which
  `ReadSector`'s RTS reaches through the address `Boot` pushed on the boot's own read. Only the 13-sector
  `ReadSector` returns to a caller (DOS 3.2's boot sector calls it at $Cn5D); none has `Keeps:`. READ2 is the local
  `ReadSector::NextField`. `ReadSector` asserts $C65C in the 16-sector build only,
  since the 13-sector ROM's reader is at $C65D (Dos.md, X14's BRETRY).
- D5. `SECTORS`, the SDK's build switch, is unchanged; `Boot.asm` asserts it is 13 or 16, the builds the digest tests
  check.
- D6. The sequencer commands are `Clear`, `Hold`, `Shift0`, `Shift1`, `Sense` and `Load`: a `.define` can't carry
  `Also:`, so each names Sather's mnemonic in prose, and the names are short so that a state's eight entries stay
  one row of 120 columns. The table macros are `ReadState`, `WriteState` and `Entry`, the layout macro `EmitChip`,
  and the entries `ENTRY_xx`.
- D7. The language card finder's routine is `TestLanguageCard`, its locations `BankByte` ($D000) and `SharedByte`
  ($E000), its codes `STATUS_FOUND` and `STATUS_NOT_FOUND`; it uses IIeEquates' current switch names. Its bytes
  had no test: `SystemMasterBasicTests.LanguageCardFinderSourceMatchesHello` pins them by digest, added before the
  conversion.

## Found in the conversion

- `ReadSector` searches for ever for a sector that is not on the track: nothing counts the tries.

## Open questions for the owner

- Q1. If McFadden's disassembly or another listing gives the boot ROM's old names, they could cite it instead of
  UNKN.
- Q2. `Hold` for Sather's NOP reads as "leave the latch alone"; `NoChange` or `Idle` would also fit.
- Q3. A shared file of the Disk II's sixteen switches, included by DOS and the boot ROMs, would replace D2's copy.
