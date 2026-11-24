# IIeEquates.asm: conversion log

`src/Retrocore.Machines.Apple2/Roms/System/IIeEquates.asm`: the IIe's page zero, soft switches, keys and page-3
vectors, shared by the Monitor, the firmware, DOS and the IIe's other sources.

The IDs are the ones the rename table's review gave: a number not here (N2) is not a gap to fill, and U3-U6 are
one entry.

## Conventions

- C1. Soft switches and I/O locations are PascalCase locations (Keyboard, KeyboardStrobe, TextOn, Speaker);
  UPPER_SNAKE is for values (keys, counts, offsets).
- C2. Switch pairs are the feature plus On/Off/State (TextOff/TextOn/TextState, Store80On/Off/State, AuxReadOn/Off,
  Page2On, HiResOn, Annunciator0Off); State is the status read, bit 7 = on.
- C3. Two-byte values are Name and NameHigh (TextBase, TextBaseHigh).
- C4. The Monitor's A1-A5 are neutral Address1-Address5 (and High), with purpose names as scoped aliases; $45 is also
  SavedA (ACC).
- C5. Keys are spelled out: KEY_BACKSPACE, KEY_LINE_FEED, KEY_RETURN, KEY_ESCAPE, KEY_RIGHT_ARROW, KEY_CONTROL_X.
- C6. Every name a manual gives a location goes in its `Also:`; one that clashes with another definition in the same
  assembly is left out and noted.
- C7. LOC1 and CV wait for DOS, whose names collide with them.
- C8. The hardware's own short terms are allowed: Aux, Rom, Cx, Irq, Store80, Columns80, Annunciator0, Page2.

## Notes and names settled

- N1. The annunciators are Annunciator0Off/On and Annunciator1Off/On at Apple's addresses (SETANn even, CLRANn odd);
  the file had put CLRAN0 and CLRAN1 on the off addresses ($C058, $C05A), Apple's SETAN0 and SETAN1.
- N3. The Cx ROM switches are InternalCxRomOn ($C007), InternalCxRomOff ($C006), InternalCxRomState ($C015).
- N4. MODE goes only on CommandMode ($31).
- N5. Page 3: NmiJump ($3FB), SoftEntryVector ($3F2), UserIrqVector ($3FE).
- U1. WNDBTM is WindowBottom: it holds the line below the window (1-24), an exclusive end.
- U2. LOC0 is SlotPointer; its high byte stays LOC1 (C7), in Monitor/Equates.asm and FirmwareEquates.asm. Other
  uses of the two bytes get scoped aliases.
- U3-U6. LENGTH is OperandLength, INVFLG InverseMask, YSAV1 SavedOutputY, RDVBLBAR DrawingState.
- U7. The language card's names carry the prefix LanguageCard (LanguageCardBank2ReadOnly ...).
- U8. TXTCLR/TXTSET and LORES/HIRES follow the switch convention: TextOff/TextOn, HiResOff/HiResOn.
- $C001 (Store80On) has `Also: SET80COL`, once the Enhanced firmware's label of that name was renamed
  ([Firmware.md](Firmware.md), F7).
