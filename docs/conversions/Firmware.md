# The IIe internal firmware: conversion log

`src/Retrocore.Machines.Apple2/Roms/System/Firmware.Original.asm`, `Firmware.Enhanced.asm` and their subject files,
with the shared `FirmwareEquates.asm` and `FirmwareFunctions.asm`. Documents cited: IIEROM82 (the original IIe's
80-column listing and symbol table), IIETRM85 (the Enhanced IIe's listing), UNKN.

The IDs are the ones the rename table's review gave: numbers not here (F9, F13) are not gaps to fill, F10-F11 are
one entry, and the last two points are notes without IDs.

- F1. A routine that does the same job has the same name in both models' files; each file's `Also:` has that
  model's Apple name.
- F2. Apple's dotted and lower-case names are cited upper case with underscores: B_FUNC, F_CLREOP, X_FF.
- F3. The firmware function numbers are in a shared `FirmwareFunctions.asm`, included by the Monitor and both
  firmware files, with `.assert`s tying each number to its handler table entry.
- F4. One CONTROL_D ... CONTROL_UNDERSCORE set (bit 7 clear) in `FirmwareEquates.asm` for both models.
- F5. The 80-column firmware's screen-hole variables are a scope `EightyColumns` (EightyColumns::CursorColumn,
  ::Mode ...); no digit-led identifiers. Its mode bits are per-model MODE_* constants in `FirmwareEquates.asm`,
  with Apple's M_ names.
- F6. The Enhanced firmware's mini-assembler scope is `LineAssembler`.
- F7. SET80COL goes to the switch (Store80On); the firmware's Control-R routine is `Control::Columns80`, with
  SET80COL in prose.
- F8. AppleSoft's page-zero names stay until AppleSoft is converted (SHAPEPTR becomes SHPTBL).
- F10-F11. MonitorEntries exports scoped names (SetPcFromA1::Loop, SaveRegisters::Return) with their Apple names.
- F12. An Apple name is left out of `Also:` (and given in prose) only when it clashes inside one assembly (WAIT,
  VTAB, VTABZ, NXTA1, XFER); clashes with other modules' names are kept.
- F14. Comments the draft flagged as wrong were verified against the code and the assembled bytes, and fixed only
  where they held; bugs in the ROM (the original's escape Control-L lookup, the self-test's failure bits, the
  Enhanced BRK with ALTZP on) are documented, not changed.
- F15. The original's $C84D is Pascal 1.0's read entry, asserted, in the Pascal scope.
- F16. Names that would shadow top-level ones are avoided: Functions::GetKey, Functions::BaseOfLine.
- The scopes are Functions, CharacterIo, Pascal, Control, Columns, Screen, SelfTest and (Enhanced) LineAssembler,
  each opened at its first piece in address order and continued after.
- A scope's name in prose needs no link: scopes are often named for plain words ("Pascal's cursor", "Control-E").
