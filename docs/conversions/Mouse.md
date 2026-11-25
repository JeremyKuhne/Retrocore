# The mouse card's firmware: conversion log

`src/Retrocore.Machines.Apple2/Roms/Mouse.rom.asm`, the emulator's own 256-byte mouse firmware (the SDK's, which
carries each call to C#'s `Apple2MouseCard`), and `src/Retrocore.Machines.Apple2/Roms/Mouse/MouseInterface.asm`,
Apple's 341-0270-C EPROM rebuilt from its bytes, which the emulator does not run. Each is one build. Documents cited:
MOUSETN (Apple's Mouse Technical Notes), IICTRM89 (the IIc Technical Reference, second edition), IIGSFR87 (the IIGS
Firmware Reference), IIEROM82 and the Monitor's own keys (through the equates both files inherit), UNKN.

## Sources

- **MOUSETN**, **IICTRM89** and **IIGSFR87** give the routines' names (see the bibliography for how each was
  checked). The notes cover the AppleMouse card itself: TimeData at $Cn1C, GetClamp at $Cn1A, ServeMouse's 6805 bug.
  The IIc reference's second edition says (Appendix D) that its calls drive the card in a IIe, and the IIGS Firmware
  Reference lists its entries, $Cn1A-$Cn1F and BASIC's included, as compatible with the AppleMouse card. The 1985
  first edition gives the names for the IIc's own firmware only, and is not cited. Two other Apple documents read in
  full give none: the Tech Info Library's "Apple II: Mouse Memory Locations" (article 8720, 1991) and the French
  AppleMouse user's manual (1983). The AppleMouse II User's Manual was not found.
- **The EPROM dump** (`342-0270-C.bin`, of the 341-0270-C chip, from the Apple II Documentation Project's mirror)
  matches the SHA-1 in the source's header, and `MouseInterfaceSourceTests.SourceMatchesTheDump` passes against it
  (with `RETROCORE_MOUSE_ROMS` pointing at it).
- M1. **The routines cite the documents that give each name**: SETMOUSE, SERVEMOUSE, READMOUSE, CLEARMOUSE, POSMOUSE,
  CLAMPMOUSE and INITMOUSE all three, HOMEMOUSE IICTRM89 and IIGSFR87. Apple's notes and the IIc reference write them in
  mixed case (SetMouse, PosMouse); they are cited upper case, as code writes Apple's names. Mouse.rom.asm's routines
  cite the same, for the same calls. The entries the drafts called the factory's take Apple's names: $Cn1A
  `ReadClampByte` (GETCLAMP, MOUSETN; DIAGMOUSE, IIGSFR87), $Cn1B `ShowCopyright` (COPYRIGHT), $Cn1C `SetInterruptRate`
  (TIMEDATA, MOUSETN and IIGSFR87), $Cn1D `SetVblCounts` (SETVBLCNTS), $Cn1E `SetMouseOptions` (OPTMOUSE) and $Cn1F
  `StartTimer` (STARTTIMER), the last four IIGSFR87's alone, which gives no more than the names; and BASIC's entries
  BINITENTRY, BASICINPUT and BASICOUTPUT (IIGSFR87). The emulator's card has none of $Cn1A-$Cn1F, so their names are on
  Apple's firmware only, and its stand-in is `UnsupportedEntry`. The screen holes' names (MOUXL, MOUXH, MOUYL, MOUYH,
  MOUSTAT, MOUMODE) are in none of the documents and keep UNKN.
- M2. **Every other old name is the SDK's own** and is dropped with no `Also:`: both files say so in their file
  comment. MouseInterface.asm's labels were the disassembly's (BANK3_SWITCH, SENDBANK_1, MCUREQUEST1_5, PARAMBANK
  ...), with no listing behind them; Mouse.rom.asm's were its author's (BASICIN_ENTRY, Common_Slot, NOTHING ...).
  MOUBANK, MOUARG, MOUPTR and BASICCALL, which read like Apple's, are in none of the documents searched, so they stay
  dropped.

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
- The emulator's card answers $Cn1A-$Cn1F with carry set, where Apple's returns carry clear from all six (TimeData's as
  Mouse Technical Note #2 documents, the others by their code); `UnsupportedEntry`'s comment says so. Changing that is a
  behavior change, outside a conversion.
