# The 3.5 disk controller: conversion log

Two sources:

- `src/Retrocore.Machines.Apple2/Roms/Disk35/`: Apple's Apple II 3.5 Disk Controller Card EPROM (341-0438-A), decoded
  by the SDK. Its root is `Disk35Controller.asm`: the card's page-zero image, the host's slot page and code, the
  diagnostics' host side, the card's self-tests and, from $D000, the card's own 65C02 firmware. One build, checked
  by `Apple2Disk35Tests.SourceMatchesTheChip` (SHA-256 of the 32 KB).
- `src/Retrocore.Machines.Apple2/Roms/Disk35.rom.asm`: the emulator's own 256-byte slot ROM, which carries each call
  to the C# card. One build, checked by `Apple2Disk35Tests.SlotRomMatchesItsDigest`, added before the conversion.

Documents cited by the converted names: IIGSFR87 (the Apple IIGS Firmware Reference) and UNKN. The EPROM's labels are
the SDK's own, given as it was decoded; no Apple listing of the card's firmware is known. The Monitor's and IIe's
names it uses keep the Monitor's citations (A2RM78, A2RM79, IIEROM82, IIETRM85) through `Inherit:` or the shared
IIeEquates.asm and MonitorEntries.asm.

## Cross-cutting decisions

- C1. The EPROM's and the slot ROM's names are the SDK's (Dos.md X12): they are renamed to the style with no `Also:`.
  `Also:` holds only names an Apple document or source gives: the ISM's registers as Apple's Macintosh sources
  (SonyEqu.a) name them (wData ... rHandshake), UNKN, since no document in the bibliography gives them; SmartPort's
  error codes (BADCMD ... OFFLINE, BUSERR) and the IIgs's registers (SHADOW, CYAREG, STATEREG, HORIZCNT), IIGSFR87
  (Q3). The IWM switches, which the SDK named PH0L ... Q7H, take the Disk II's names (Dos.md X9) and no `Also:`.
- C2. The Monitor's entries come from IIeEquates.asm and MonitorEntries.asm where they have them (the host code
  includes both); the rest are defined with `Inherit:` and the Monitor's `Also:` (NextSlot, SetText, LOC1,
  BasicColdStart, ExpansionRomOff, CarriageReturn, PrintHexByte ...), as Dos/Equates.asm does. Disk35.rom.asm defines
  all of its own, because the source generator assembles it alone.
- C3. Same job, same name: the slot ROM's entries are the EPROM's slot page's, `Boot`, `DiagnosticsEntry`,
  `ProDosEntry`, `SmartPortEntry` and `Call`. The slot ROM's exports, which C# reads as `Disk35Rom.*`, take those
  names.
- C4. Disk35Card.asm (5,700 lines) is split into subject files before the conversion, bytes unchanged: Disk35Card.asm
  (start-up, main loop, dispatch), Drives, Cache, Blocks, Gcr, Mfm, Control, Format and Bus.
- C5. The SWIM's addresses are two scopes in Disk35Equates.asm: `Iwm` (the switches: `Iwm::Phase0Off` ...
  `Iwm::WriteMode`) and `Ism` (the registers: `Ism::WriteData`, `Ism::ClearMode`, `Ism::ReadHandshake` ...).
- C6. Codes and bits shared by several files are prefixed constants in Disk35Equates.asm: `COMMAND_*` (the card's
  commands, which the host and the card share), `ERROR_*` (SmartPort's errors) and `DISK_ERROR_*` (the bits of
  `DiskErrors`). Sets one subject uses stay in its file (`SENSE_*`, `DRIVE_*`, `MEDIA_*`, `ISM_MODE_*` in Drives;
  `CACHE_*` in Card; the bus's in `Bus`). Where two files had named one value two ways, one name was kept (MEDIA_*,
  DISK_ERROR_NO_FIELD, MFM_MARK, MFM_INDEX_MARK, the MFM ID bytes `MFM_INDEX_ID`, `MFM_ADDRESS_ID`, `MFM_DATA_ID`).
- C7. The card's page zero (Disk35ZeroPage.asm) stays a labeled image: each byte a PascalCase location (`CardState`,
  `ParameterLow`, `Count`/`CountHigh`, `Drive` ...). The host reaches the mailbox as `CardWindow` plus the card's own
  label (`MailboxState = CardWindow + CardState`), with an `.assert`, so the two sides share one definition.
- C8. Scopes: `Drives` and `Swim` (Drives.asm), `Cache` and `BlockMap`, `Control`, `Status` and `FormatOptions`,
  `Format`, `Bus`, `Host` (the host's code at $CA00-$CFFF), `Diagnostics` (the diagnostics' host side) and `SelfTest`.
  Top level is for what several files reach: the main loop and dispatch, `SetError`, the field routines the page-zero
  vectors and the format reach (`ReadGcrAddressField` ...), `ReadBlock`/`WriteBlock`, the delays, and the host's
  entries.
- C9. No scoped name shadows a top-level one: the host's handlers are `Host::ReadBlockCall`, `Host::WriteBlockCall`
  and `Host::ControlCall`, the self-test's are `SelfTest::CardDiagnostics`, `SelfTest::ReadTestBlock`,
  `SelfTest::WriteTestBlock` and `SelfTest::CopyDiagnosticsZeroPage`, and no local is named for a page-zero byte.
- C10. The self-test's equates that named card routines and page-zero bytes by number now name the definitions
  (`CardReset`, `RunCommand`, `CardState`), with `.assert`s on the addresses the self-test and the slot page rely on
  ($D100, $D11D, $D129, $D1E7, $D2A1, $D80B, $8F00, $9649).

## Found in the code and documented, not changed

- SmartPort READ ($08) takes the write path: `ReadWriteTagged` reads only when `CardState` is 1, which READ, arriving
  as $08, never is, so a READ writes the buffer to the block. The dead read path also copies from $0E00, past the
  buffer it read into. Its media check reads `MediaKind` at a leftover Y (0, or a media kind after a fresh
  identification), so it checks drive 1's kind whatever the drive.
- READAHEAD stores the run's high byte in `ParameterLow`, and on a failed check leaves two bytes on the stack that
  `SetError`'s RTS returns through. READSPAN's skip pause tests a byte it has just cleared.
- `WriteMfmDataField` always returns carry clear; control $0C stores the list's fifth byte, not its third; $0C and $13
  keep the old address after a wrong-length list; $0F takes any length; $11 copies 256 bytes too many for a list a
  multiple of 256 bytes; `FormatOptions::Set` (SETFORMAT) stores the kind before refusing a bad interleave; an MFM
  data-mark failure sets no `DiskErrors` bit.
- The bus's receive error $8A can never happen; commands $0A-$0C read `Bus::CommandTable` past its end (asserted);
  `Bus::Initialize` marks units X to 3 empty, not 4; a failed FORMAT ejects the disk.
- Comments fixed against the code: `ClearCache`'s slot values, `WaitReady`'s time (0.74 s), `SelectHead` reads `Side`
  itself, `IdentifyMedia`'s carry and A, `Release` turns the motor line on, `BlockMap::Gcr400`'s groups are 16 blocks,
  `DelayMillisecondPairs` does not keep A, `Bus::Enable`'s phases, the 2-byte write lengths' count.

## Settled by the owner

These were the conversion's open questions, settled after it merged.

- Q1. SmartPort READ ($08) taking the write path is a bug in Apple's firmware, as decoded: the host passes READ to the
  card as $08, and `ReadWriteTagged` reads only for command 1. The emulated card (`Apple2Disk35Card`) keeps doing a
  correct tagged READ rather than copy the bug. Running the EPROM, once the hardware mode of
  docs/backlog/Disk35Hardware.md exists, can confirm it.
- Q2. The names worked out from the code alone stand: the ISM's mode bits (`ISM_MODE_ACTION` $08, `ISM_MODE_WRITE`
  $10, `ISM_MODE_MOTOR` $80), `MediaMode`'s values as commented numbers, and `FormatOptionList`'s fields (`SHOWN`,
  `LINK`, `CURRENT`).
- Q3. The Apple IIGS Firmware Reference (1987) is in the bibliography as IIGSFR87, checked against its Internet Archive
  OCR text: SmartPort's error names (Table 7-6) and SHADOW, CYAREG, STATEREG and HORIZCNT (Appendix E) cite it. The
  ISM's register names stay UNKN, and so do ZIDBYTE and IDROUTINE, which the check did not reach.
