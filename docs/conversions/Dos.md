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
  `Also:`; Monitor entries MonitorEntries.asm lacks are defined in DOS's Equates.asm with `Inherit:`; DOS's INPRT,
  OUTPRT and INSDS2 point at other addresses than the Monitor's routines of those names, so they go in prose; the
  Monitor keeps CV, and DOS's `KeywordVolume` names it in prose; BASIC names wait for the BASICs' conversion.
- X8. The 1978 listings' other spellings of the same routines (DOSLDR, WRITE, READ, RDADR, SEEKXIT, ICCFD2 ...) go in
  `Also:` with DOS31; RD1-RD5 clash with the file manager's RD1-RD5 and go in prose.
- X9. The sixteen Disk II switches are defined once, in RwtsEquates.asm: Phase0Off, Phase0On, MotorOff, MotorOn,
  SelectDrive1, SelectDrive2, DataLatch, LoadLatch, ReadMode, WriteMode. The IOB, DCT and track/sector list, which
  both boot loaders repeat, move to one shared file.
- X10. RWTS is one `.proc Rwts` spanning Rwts1.asm and Rwts2.asm (Apple split it for size).
- X11. One ERROR_* set for DOS's errors 1-15, the file manager's return codes included; the messages' offsets are
  MESSAGE_*, written with a macro that asserts each position.
- X12. The SDK's own names get no `Also:`; DOS 3.2's BOOT 1 macros, named as capital mnemonics, are renamed in the
  style.
- X13. DOS32, MASTER and YEAR (the SDK's build options, which C# predefines) are unchanged; Apple's DIAGMODE, DOS33B
  and ULC are renamed with `Also:`; ORIGIN is `MASTER_ORIGIN` with `Also: ORIGIN (DOS33)` and an `.assert`.

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

## For the conversion

- Comments found wrong in drafting (CREFLG is tested; a record length of 0 means 256; the success exit reloads A;
  the DCT's step count; DISKIO's carry; several DOS 3.2 counts) are fixed against the code; `docs/DiskII.md`'s
  DRV0EN/DRV1EN is DRV1EN/DRV2EN, as Apple's listing has it.
- The structs' comments link `docs/Dos.md`'s explanations of the VTOC, the catalog and track/sector lists, and the
  IOB.
