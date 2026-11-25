# The ProFile card and slot 7 block device firmware: conversion log

`src/Retrocore.Machines.Apple2/Roms/ProFile.rom.asm` (the emulated ProFile interface card's ROM, in any slot,
assembled at $C500) and `src/Retrocore.Machines.Apple2/Roms/Slot7.rom.asm` (the emulated slot 7 block device's ROM,
$C700): two 256-byte ProDOS block-device ROMs the SDK wrote. Each is one build, with no switches. Documents cited:
none. `Apple2ProFileTests.FirmwareBytesAreUnchanged` (added before the conversion, from the old source) and
`Slot7RomTests` pin their bytes.

## Decisions

- B1. Both firmwares are the SDK's own, so every name they define is the SDK's: renamed to the style, with no
  `Also:` (as the Boot13 programs and DOS 3.2's own code, Dos.md X12). The old names are in the table below and in
  git history, not in the sources.
- B2. The Monitor's names the ProFile firmware uses are defined locally with `Inherit:` and the Monitor's current
  names, as FirmwareEquates.asm does for LOC1: `SlotPointer` (LOC0), `LOC1`, `SaveRegisters::Return` (IORTS) and
  `Startup::PowerUp::NextSlot` (SLOOP), the last two in scopes shaped like the Monitor's. The firmware doesn't include
  MonitorEntries.asm or IIeEquates.asm: it runs on the II Plus too, and its debug module is relocated into every slot,
  so it carries only the names it uses.
- B3. The same job has the same name in both firmwares: the entry ProDOS calls is `Driver` in both (slot 7's
  `DriverEntry` was renamed, with its C# export `Slot7Rom.Driver`), and the mailbox, commands and capability bits are
  spelled alike.
- B4. The ProDOS mailbox ($42-$47) is locations: `Command`, `UnitNumber`, and the two-byte `Buffer`/`BufferHigh` and
  `Block`/`BlockHigh` (the Name/NameHigh rule). It stays equates in each file, not a struct: the code addresses its
  bytes directly, and there is no copy of the layout to tie to one.
- B5. Codes are prefixed constants: `COMMAND_*`, `ERROR_*`, the ProFile's `RESPONSE_*` (named as ProFileDrive's C#
  constants name the same responses) and `ANSWER_*`, and the capability bits `CAPABILITY_*` (with `ONE_VOLUME` for
  the volume-count field). Slot 7's exported write bit is `CAPABILITY_WRITE` in C# too (`Slot7Rom.CAPABILITY_WRITE`).
- B6. The signature bytes the boot's first loads carry are named by their offset in the page (`SIGNATURE_01` ...
  `SIGNATURE_07`), and the constants a value stands for are named (`OPCODE_LDY_IMMEDIATE`, `OPCODE_JMP`, `BOOT_PAGE`,
  `UNIT_SLOT_7_DRIVE_1`); the slot mask `$70` stays a number in the code, with the unit number's layout on
  `UnitNumber`.
- B7. Each routine is a `.proc`. In the ProFile firmware the shared exits are `Succeed`, `Fail` and `FailNoDevice`
  (DOS's file manager's words, Dos.md P7); the handshake's steps are `SendCommand`, `SendData`, `Handshake`,
  `ReadResult` and `Refuse`, and the boot's return target is `FinishBoot`. Their fall-throughs are comments only:
  each falls into the next lines of the same file.
- B8. Slot 7's header keeps its explanations for newcomers; its paragraph on the assembler dialect is replaced by a
  pointer to docs/NativeAssembly.md.

## Found in the conversion and documented

- The ProFile `Driver`'s `Out:` said X/Y are the block count for status, which is false with no ProFile: then every
  command, status included, returns `ERROR_NO_DEVICE` with X = the slot times 16 and Y unchanged. It now gives each
  register its own entry, with that case, and `Uses: Y` for read and write. The driver also keeps the mailbox
  (`BufferHigh` is stepped and restored), which its `Keeps:` now says.
- Slot 7's status reads `CommandPort` twice, once through the read and write path; kept, as before.

## Renames

| Old | New | File |
| --- | --- | --- |
| Unit | UnitNumber | both |
| BufferLow | Buffer | both |
| BlockLow | Block | both |
| BlocksLow, BlocksHigh | BlockCount, BlockCountHigh | ProFile |
| BlockCountLow | BlockCount | Slot 7 |
| IORTS | SaveRegisters::Return | ProFile |
| LOC0 | SlotPointer | ProFile |
| SLOOP | Startup::PowerUp::NextSlot | ProFile |
| LdyImmediate | OPCODE_LDY_IMMEDIATE | ProFile |
| BootPage | BOOT_PAGE | both (Slot 7's was a number) |
| Status | CardStatus | ProFile |
| CommandLow, CommandHigh | CommandOff, CommandOn | ProFile |
| ReadyResponse, ReadResponse, WriteResponse, WrittenResponse | RESPONSE_READY_FOR_COMMAND, RESPONSE_READ, RESPONSE_WRITE, RESPONSE_WRITE_DATA | ProFile |
| Acknowledge, Refuse | ANSWER_GO_ON, ANSWER_REFUSE | ProFile |
| FormatCommand | COMMAND_FORMAT | ProFile |
| IoError, NoDevice | ERROR_IO, ERROR_NO_DEVICE | ProFile |
| OneVolume, RemovableMask, InterruptibleMask, ...CapabilityMask | ONE_VOLUME, CAPABILITY_REMOVABLE, CAPABILITY_INTERRUPT, CAPABILITY_... | both |
| NoDrive, Done, Failed | FailNoDevice, Succeed, Fail | ProFile |
| Driver_Block | Driver::Transfer | ProFile |
| SendData_Low/High, Result_Low/High | SendData::FirstPage/SecondPage, ReadResult::FirstPage/SecondPage | ProFile |
| Handshake_Busy, Handshake_Ready | Handshake::WaitForResponse, Handshake::WaitForDone | ProFile |
| Result, Result_Status, Result_Done | ReadResult, ReadResult::OtherStatus, ReadResult::Done | ProFile |
| Refused | Refuse | ProFile |
| BootRead, BootRead_Failed, BootRead_Stop | FinishBoot, FinishBoot::Failed, FinishBoot::Stop | ProFile |
| DriverEntry, ExecuteCommand, Success | Driver, Driver::Perform, Driver::Succeed | Slot 7 |
| WriteCapabilityMask | CAPABILITY_WRITE | Slot 7 |

## The open questions, settled by the owner

- B9 (was Q1). The ProDOS block-device interface is one include,
  [ProDosBlockDevice.asm](../../src/Retrocore.Machines.Apple2/Roms/ProDosBlockDevice.asm), in a scope `ProDos`: the
  mailbox (`ProDos::Command`, `ProDos::UnitNumber`, `ProDos::Buffer`/`BufferHigh`, `ProDos::Block`/`BlockHigh`), the
  commands `COMMAND_*`, the errors `ERROR_IO` and `ERROR_NO_DEVICE`, and the capability bits `CAPABILITY_*` with
  `ONE_VOLUME`, `FOUR_VOLUMES` and `CAPABILITY_EVERY_COMMAND`. The ProFile, slot 7 and 3.5 card ROMs include it, and so
  does the 3.5 controller's EPROM (Disk35Host.asm, whose `ProDosCommand` ... `ProDosBlock` it replaces): the scope keeps
  its names apart from the EPROM's SmartPort `COMMAND_*` and `ERROR_*`, where `COMMAND_READ` is $08. The mouse's ROM
  has none of these. The ProFile, which uses the names throughout, writes `.using ProDos`; slot 7 qualifies them, since
  its exported `CAPABILITY_WRITE` stays a top-level alias for the C# card (`Slot7Rom.CAPABILITY_WRITE`). The source
  generator takes the include as an `AdditionalFiles` item of Retrocore.Machines.Apple2.csproj, and the tests and the
  debug host copy it beside the card ROMs. This replaces B4's equates in each file.
- B10 (was Q2). Each card's ProDOS driver has its own name, so a typed name reaches the card meant: `ProFileDriver`,
  `Slot7Driver` (`Slot7Rom.Slot7Driver`) and the 3.5 card's `Disk35Driver` (`Disk35Rom.Disk35Driver`, and the EPROM's
  slot-page entry too, by Disk35.md's C3). No document gives the old names, so none has an `Also:`.
- B11 (was Q3). Same job, same name across the card ROMs: the Monitor's SLOOP is `Startup::PowerUp::NextSlot`, the
  Monitor's own path, in the ProFile, the 3.5 slot ROM and the EPROM's host code (whose card start-up, `Startup`
  before, is `CardStartup`, beside `CardReset`, to leave the name to the Monitor's scope); $0801, where a boot block
  runs, is `BootEntry` (the 3.5 slot ROM's `BootBlock` and the EPROM's `BootCode` before); the stack page is
  `StackPage` (the mouse's `Stack` before); and the routine that carries a call to the card is `CallCard` (the 3.5
  ROMs' `Call` before). The Monitor's names each card defines cite the Monitor's documents alike (LOC0, IORTS, SLOOP).
