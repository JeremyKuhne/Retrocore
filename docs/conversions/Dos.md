# DOS 3.3 and 3.2: conversion log

`src/Retrocore.Machines.Apple2/Roms/Dos/`: the roots `Dos33.asm` (DOS 3.3, 1983 or 1980, as the System Master or
where DOS runs) and `Dos32.asm` (DOS 3.2), the shared command interpreter and file manager, and each version's RWTS,
boot loader and formatter. Also converted with it: `Software/MasterCreate.asm`, `Software/Boot13.1980.asm` and
`Software/Boot13.1983.asm`, which include or copy its names.

## Sources

- **DOS33**: Apple's DOS 3.3 C source listing (July 1983), the source of the current names. Checked by script:
  every name cited DOS33 is defined in the listing, and the only listing name not otherwise cited, ORIGIN, is
  Apple's too.
- **DOS31**: Apple's 1978 DOS listings, as the Computer History Museum released them. About 80% of the names are
  there; cited where the 1978 source defines the same name for the same thing. Names only in Scott LaBombard's
  reconstruction of DOS 3.1 are not cited.
- Names of code only DOS 3.2 has are the SDK's own (Dos32.asm says so): not historical, no `Also:`.

## Cross-cutting decisions

- X1. Struct, union and enum members carry `Also:` (members documented with their own `;;` blocks), so DOS's layouts
  keep Apple's field names.
- X2. Codes are prefixed constants: REQUEST_*, TRANSFER_*, ERROR_*, RWTS_*, COMMAND_*, OPTION_*, OUTPUT_STATE_*,
  INPUT_STATE_*.
- X3. Each data layout is a `.struct` with UPPER_SNAKE fields; DOS's own copy keeps labeled bytes tied to it by
  `.assert`s: Iob/DosIob, DeviceTable/DosDeviceTable, FileParameters/DosFileParameters, Vtoc/VtocBuffer,
  CatalogSector/CatalogBuffer, CatalogEntry, TrackSectorList, TrackSectorPair, FileBuffer.
- X4. The entries: USERENT is `CallFileManager` ($AAFD, where $3D6 goes), DOSENT `CallFileManager::ForDos`; DOSGO
  (the interpreter's call with its error handling) is `RunFileRequest`; DISKIO ($3D9's target) is `CallRwts`;
  RWTS is `Rwts`.
- X5. The relocator's range markers are top-level `<Range>Start` and `<Range>End` (the byte after), or
  `<Range>Last` for Apple's `* - 1` markers, each with `Also:` the old name.
- X6. The command interpreter's scopes: Scanner, Output, Commands (handlers named for the command word:
  Commands::Catalog, Commands::PrNumber), TextFile, Errors, FileBuffers.
- X7. DOS's names for locations IIeEquates defines (OUTSW, INSW, LBUFF, ZRSET, PWCNST) join those definitions'
  `Also:`; Monitor entries MonitorEntries.asm lacks are defined in DOS's Equates.asm with `Inherit:`; DOS's INPRT and
  OUTPRT point two bytes before the Monitor's routines of those names, so they go in prose, while its INSDS2 is the
  Monitor's own entry ($F88E) and joins DecodeOpcode's `Also:`; the
  Monitor keeps CV, and DOS's `KeywordVolume` names it in prose; BASIC names wait for the BASICs' conversion.
- X8. The 1978 listings' other spellings of the same routines (DOSLDR, WRITE, READ, RDADR, SEEKXIT, ICCFD2 ...) go in
  `Also:` with DOS31; RD1-RD5 clash with the file manager's RD1-RD5 and go in prose.
- X9. The Disk II's sixteen switch addresses are defined once, as ten names, in RwtsEquates.asm: Phase0Off, Phase0On, MotorOff, MotorOn,
  SelectDrive1, SelectDrive2, DataLatch, LoadLatch, ReadMode, WriteMode. The IOB, DCT and track/sector list, which
  both boot loaders repeat, move to one shared file.
- X10. RWTS is one `.proc Rwts` spanning Rwts1.asm and Rwts2.asm (Apple split it for size).
- X11. One ERROR_* set for DOS's errors 1-15, the file manager's return codes included; the messages' offsets are
  MESSAGE_*, written with a macro that asserts each position.
- X12. The SDK's own names get no `Also:`; DOS 3.2's BOOT 1 macros, named as capital mnemonics, are renamed in the
  style.
- X13. DOS32, MASTER and YEAR (the SDK's build options, which C# predefines) are unchanged; Apple's DIAGMODE, DOS33B
  and ULC are renamed with `Also:`; ORIGIN is `MASTER_ORIGIN` with `Also: ORIGIN (DOS33)` and an `.assert`. Each
  root asserts the values its digests check: `Dos33.asm` a MASTER of 0 or 1 and a YEAR of 1983 or 1980, `Dos32.asm`
  a MASTER of 0 or 1 (YEAR selects nothing in DOS 3.2).
- X14. The owner's D5 decision: a routine both versions have is one definition, with `.if DOS32` where they differ
  in places (Stage2, StartDos, WriteDataField, ReadAddressField, MoveHead, Wait, WriteFourAndFour, WriteFieldNibble,
  SeekHalfTrack, FreeSector, besides those the same in both, such as CallRwts, ReadDataField and SetTrack); one
  that differs throughout (Stage1, WriteDos, TransferPages, PreNibble, PostNibble, Format, the translate tables and
  buffers) has a definition for each version, side by side under `.if DOS32` / `.else` in one module. `Rwts` stays a
  `.proc` per version: besides DOS 3.3's diagnostic build, which nearly doubles its length, it differs at some twenty-five
  places (the motor test, the seek counts, the recalibration, the sector translation), so one `.proc` would read
  as two interleaved. Modules are named for their subject, not their version (ReadData, not PostNibbleRead or
  ReadSector32; ReadSector.asm in prose would read as the file manager's ReadSector), and each root includes them in its memory
  order: PostNibble comes before ReadData in DOS 3.3 and after ReadAddress in DOS 3.2, and FourAndFour comes from
  WriteAddress.asm in DOS 3.3 and from the formatter in DOS 3.2. Software/Boot13.1980.asm, which includes DOS 3.2's
  nibble routines, includes the shared modules with DOS32 = 1. A definition each version has gives the same
  historical names in both, as the firmware's lineage rule has it (ConvertedSourceTests.DosLineagesCiteBothVersions):
  so DOS 3.3's buffers, tables and nibble routines cite the 1978 names too (NBUF6, DNIBL, PRENIBL ...), and DOS
  3.2's the C listing's (PRENIB16, POSTNB16, FORMERR ...). Two stay with DOS 3.3: NSYNC, a byte DOS 3.2's gap length
  is not kept in, and BRETRY, the 16-sector ROM's reader offset ($5C, where DOS 3.2's is $5D).

## Where the drafts disagreed

- K1. The IOB's fields: Type, SlotTimes16, Drive, Volume, Track, Sector, DeviceTable, Buffer, DataLength, Command,
  ReturnCode, VolumeFound, PreviousSlot, PreviousDrive, Spare.
- K2. IBVMME is RWTS_VOLUME_MISMATCH; the DCT is DosDeviceTable and struct DeviceTable.
- K3. IMBITS is EchoOptions.
- K4. Shared by both versions: Stage1::LastSector, ReadAddressField::WaitAddressMark, PostNibble::Loop; SEEKRTS takes
  the name of the routine it ends in each version.

## Per-part decisions

- P1. COMMAND_* values are command numbers (0-27); uses as table offsets write COMMAND_X * 2.
- P2. The BASIC vector: labels for the six live words (BasicRun ...), the three images written with a BasicEntries
  macro.
- P3. DCI is `MarkedText`; ASLMEM, unused, is dropped.
- P4. TSTRUN is top-level `TestProgramRunning`.
- P5. TSTFUC is `Commands::CheckFileType`; ELGO is `Commands::RequestAndClose`, a scope-level label.
- P6. The file manager's handlers take the request words (FileManager::Open ... Verify); DOPEN is
  `FileManager::OpenFile`.
- P7. The file manager's exits stay in FileManager (Succeed, Fail, Leave, SaveWorkArea); the patches that use them
  say they are the file manager's code.
- P8. The interpreter's variables at the start of FileManagerEntry.asm are top level (CommandOffset, KeywordVolume,
  ActiveBasic).
- P9. "Range", not "block", for multi-byte transfers (ReadNextRange, TRANSFER_NEXT_RANGE, RangeLength); Apple's
  block names in `Also:`.
- P10. FNDFIL's tail is its own `.proc FileManager::EndOfCatalog`.
- P11. Locals that would shadow routines get other words (Finish, VtocWritten, NextLink).
- P12. Layout sizes are named `.sizeof` constants with Apple's names in `Also:` (FILE_PARAMETERS_SIZE ...).
- P13. The file manager's own data (buffers, FCB, work cells, CATALOG's tables) live in FileManager.
- P14. RWTS's zero page: aliases inside the one routine that uses a byte; top-level aliases for bytes modules share.
- P15. Slot is 1-7, SlotTimes16 is slot * 16.
- P16. The boot stages are Boot::Stage1 and Boot::Stage2 in both versions.
- P17. The APPEND end-of-file fix is a scope AppendFix in four pieces; the other patches are top-level
  SaveAndVerify, TurnOff80Columns and Uppercase.
- P18. Apple's assembly-time position names (BHERE1-5, XP, PD1 ...) are constants only where the name explains
  something to the reader; pure fill arithmetic is inline, with Apple's label in prose.
- P19. BTEMP is `Boot::JumpVector`; DOS 3.2's buffers cite the 1978 NBUF6 and NBUF1.
- P20. DOS 3.2's dead CHKPOSITION is `Formatter::LeftoverPositionCheck`.

## Settled during the conversion

These came after the rename table's review, so, like the section *For the conversion* below, they have no IDs.

- Apple's names for the IOB's and the parameter list's bytes (IBTRK, CCBREQ ...) are on DOS's labeled copies
  (`DosIob::Track`, `DosFileParameters::Request`), which DOS's code uses as addresses; one old name belongs to one
  definition, so the structs' fields carry none. The track/sector list's fields, which nothing labels, carry them.
- Error 2 is `ERROR_RANGE` (its message is RANGE ERROR, and the scanner gives it for numbers too); the message
  offsets take the errors' suffixes (`MESSAGE_RANGE`). The DCT's bit 0 is `WHOLE_TRACKS`: "phases per track" was
  wrong.
- Names that would have shadowed another definition were changed: DCBIO is `FileManager::AccessDisk` (not
  `CallRwts`), INITZ `FinishStart::ClearAndResume` (not `ClearStates`), CONWAIT `Rwts::DelayLoop` and the
  formatter's waits `Pause` (not `Delay`, the Monitor's), SD1 `Rwts::Drive2` (not `SelectDrive2`, the switch),
  GETNUM `Scanner::ParseNumber` (beside `Scanner::ReadNumber`), BOOT 1's B1READ `Stage1::JumpThroughVector`.
- The relocator's ranges: InterpreterAddresses, InterpreterCode, FileManagerAddresses, FileManagerCode, BootCode,
  EmptyCode (DOS 3.2), WriteAddressCode, LowLevelCode, RwtsPatchCode (PSC1/PEC1), RwtsCode, TopPatchCode, each
  `Start` and `End` (or `Last` for Apple's `* - 1` markers).
- The Boot13 programs are the SDK's own copies: their names follow DOS's, with no `Also:`.
- Found in the conversion and documented, not changed: a file of type A passes LOAD's BASIC check
  and then matches neither BASIC; a program calling the file manager with X = 0 gets INIT's create rule, so LOCK
  or DELETE of a missing file creates it; the formatter returns the wrong code after 47 failed tries for sector 0;
  the APPEND fix is mostly in the 1980 DOS already (only MOVEOF and FIXIT2 are 1983).
- Two assembler limits worked around: `.sizeof` of a `.proc` in an equate, and a forward `.sizeof` of a struct
  (which assembles as 0); sizes there are numbers with an `.assert`.

## For the conversion

- Comments found wrong in drafting (CREFLG is tested; a record length of 0 means 256; the success exit reloads A;
  the DCT's step count; DISKIO's carry; several DOS 3.2 counts) are fixed against the code; `docs/DiskII.md`'s
  DRV0EN/DRV1EN is DRV1EN/DRV2EN, as Apple's listing has it.
- The structs' comments link `docs/Dos.md`'s explanations of the VTOC, the catalog and track/sector lists, and the
  IOB.
