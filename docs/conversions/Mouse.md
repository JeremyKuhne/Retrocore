# The mouse card's firmware: conversion log

`src/Retrocore.Machines.Apple2/Roms/Mouse.rom.asm`, the emulator's own 256-byte mouse firmware (the SDK's, which
carries each call to C#'s `Apple2MouseCard`), and `src/Retrocore.Machines.Apple2/Roms/Mouse/MouseInterface.asm`,
Apple's 341-0270-C EPROM rebuilt from its bytes, which the emulator does not run. Each is one build. Documents cited:
IIEROM82 and the Monitor's own keys (through the equates both files inherit), UNKN.

## Sources

- **No document in hand gives the firmware's names.** Apple's AppleMouse II User's Manual and the IIc Technical
  Reference, which give SETMOUSE ... INITMOUSE, were not reachable. Two Apple documents that were read in full give
  none of them: the Tech Info Library's "Apple II: Mouse Memory Locations" (article 8720, 1991: slot 4's position
  bytes only) and the French AppleMouse user's manual (1983: BASIC's `IN#` and `PR#` only). No bibliography key was
  added.
- M1. **The eight routine names and the screen holes' names cite UNKN**: SETMOUSE, SERVEMOUSE, READMOUSE,
  CLEARMOUSE, POSMOUSE, CLAMPMOUSE, HOMEMOUSE, INITMOUSE, and MOUXL, MOUXH, MOUYL, MOUYH, MOUSTAT, MOUMODE. They are
  the names mouse programs use, so they stay reachable; a key replaces UNKN once a document that gives them is in
  hand. In Mouse.rom.asm the routines cite the same names, for the same calls.
- M2. **Every other old name is the SDK's own** and is dropped with no `Also:`: both files say so in their file
  comment. MouseInterface.asm's labels were the disassembly's (BANK3_SWITCH, SENDBANK_1, MCUREQUEST1_5, PARAMBANK
  ...), with no listing behind them; Mouse.rom.asm's were its author's (BASICIN_ENTRY, Common_Slot, NOTHING ...).
  Open question for the owner: whether MOUBANK, MOUARG, MOUPTR and BASICCALL, which read like Apple's, should
  keep UNKN too.

## Decisions

- M3. **Routine names are the documented calls in full words**: SetMouse, ServeMouse, ReadMouse, ClearMouse,
  PositionMouse, ClampMouse, HomeMouse, InitializeMouse, in both files (same job, same name). They stay top level:
  Mouse.rom.asm exports them to C# (`MouseRom.SetMouse`), whose generator takes plain identifiers.
- M4. **BASIC's entries**: `BasicEntry` ($Cn00), `BasicInput` ($Cn05) and `BasicOutput` ($Cn07) in both files, as
  the IIe firmware names slot 3's. In Mouse.rom.asm $Cn07 is the CLC that is BasicInput's branch offset, so
  `BasicOutput = BasicInput + 2` is an equate, and an `.assert` ties the offset to the CLC opcode. The commands they
  send are `WriteBasicLine` and `WriteBasicCharacter`; Apple's slot-finding routine is `EnterBasic`.
- M5. **Apple's eight banks** are bank 0 at top level and a scope per bank named for its subject: CopyrightBank,
  InitializeBank, CommandBank, BasicBank, LineBank, ByteBank, ParameterBank. Each bank's code at $Cn70 is its
  `Switch` (bank 0's `SwitchBank::Switch`), asserted at $Cn70 in every bank. Port B's bank bits take the bank times
  2, written `BANK_* * 2`; the entry codes a bank pulls are ENTRY_MAIN, ENTRY_SECOND, ENTRY_THIRD and ENTRY_RETURN,
  and each `Switch` says what they mean there.
- M6. **Constants**: the microcontroller's commands COMMAND_* (Mouse.rom.asm's COMMAND_* are Apple2MouseCard's
  numbers: separate modules), STATUS_* and MODE_* bits, the PIA's PORT_B_* handshake bits, SELECT_DATA, and the
  line's LINE_* places. The PIA's registers are PortA, PortAControl, PortB, PortBControl; the holes MouseX,
  MouseXHigh, MouseY, MouseYHigh, MouseStatus, MouseMode, with slot 0's ClampMinimum/ClampMaximum aliases for
  ClampMouse's bounds. The firmware's own holes are NextBank (MOUBANK) and Argument (MOUARG).
- M7. **Equates from the IIe sources** are used by their current names (ExpansionRomSlot, OutputHook, InputBuffer,
  DrawingState ...); CharacterOut and ExpansionRomOff, which MonitorEntries.asm lacks, are defined with `Inherit:`
  and their historical names, as DOS and the original IIe firmware define them. Mouse.rom.asm defines the Monitor's
  `SaveRegisters::Return` ($FF58, IORTS) the same way. SAVEY is `BasicY`: `SavedY` is IIeEquates' $47.
- M8. **Entries go in prose, not `Entry:`**, inside the banked code: the lint finds a routine's end by the next
  documented routine's address, and the banks' routines share addresses, so every bank's entry would be reported
  outside its routine. `Fail`, `Done`, `Return`, `PushCode` and the like are named in backticks in their routine's
  comment.
- M9. **Mouse.rom.asm's byte digest is pinned** (`Apple2MouseTests.FirmwareBytesArePinned`), added before the
  conversion; MouseInterface.asm already had `MouseInterfaceSourceTests`.

## Found in the conversion

- InitializeBank's IIe wait: `DrawingState`'s bit 7 is set while the display draws, so the three loops wait out the
  picture, then blanking, then the picture again, and the reset goes as vertical blanking starts. The old comments
  had the first and last loop's meaning reversed.
- Apple's BASIC input returns the line's length in X and Y; the old `Keeps: X, Y` on its BASIC entry was false for
  input. Its comment now says output keeps A, X and Y.
- Each bank's last byte ($C2, $C1, $C3, $C8, $CD, $C1, $CE) is never read by the firmware; its purpose is not known.
