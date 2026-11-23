# The Apple II Monitor: conversion log

`src/Retrocore.Machines.Apple2/Roms/System/Monitor.asm` and its subject files in `Monitor/`: one source for the
1978 Monitor, the Autostart Monitor and the original and Enhanced IIe's, chosen by `MONITOR` and `ENHANCED`.
Documents cited: A2RM78, A2RM79 (the Apple II Reference Manuals), IIEROM82 (the IIe ROM listings), IIETRM85 (the
IIe Technical Reference Manual), UNKN. `Monitor.asm` asserts the MONITOR and ENHANCED values its
digests check.

1. Every name is renamed to the style, including Apple names that already fit (`HOME` is `Home`); the old name goes
   in `Also:`. LOC1 and CV wait for DOS, and the firmware's entry equates for the firmware (7).
2. The lo-res graphics family is the scope `LowRes`.
3. Apple labels nothing references (PRBL3, INITAN, SETPG3, RTS4C, VFYOK, RESTR1, MD3) stay as named locals with
   `Also:`: a label with a documented name is kept.
4. Locals that jump on to a firmware routine are `ToFirmware`, not `CallFirmware`.
5. Names are cited only from documents in hand, and only names checked against each document's listing: A2RM78 the
   Apple II Monitor, A2RM79 that and the Autostart Monitor, IIEROM82 the original IIe's, IIETRM85 the Enhanced IIe's.
   A routine that descends through the builds is one lineage (the owner's decision): each of its definitions, even
   one written per build, cites every document that names the routine in any build, so CLEOLZ (the Apple II's
   spelling) and CLREOLZ (the IIe's) are on every build's ClearLineFrom. A document whose builds lack the routine is
   not cited (STEP and BRANCH have no IIe document).
6. Names that may be this source's own (MEMFIND, MINIASM, TITLE2E, RDKEYHOOK ...) stay in `Also:` as UNKN;
   XGOTOCX (IIEROM82) and DOCOUT1 (IIETRM85), which the IIe listings give, cite them. Obviously generated numbered
   locals (`GETLN_1`, `CLREOP_2`) are dropped with no `Also:`.
7. The firmware's entry equates (B_FUNC, BASICIN, IRQHANDLER ...) wait for the firmware conversion.
8. Families spread through the ROM are continued scopes: `Commands`, `Startup`, `Stepper` (the 1978 STEP's
   stepping; TRACE is `Commands::Trace`), each later piece `.scope X continued` with a plain comment saying which part.
9. Widely called documented entry points are top level (SetKeyboard, SetScreen, GetLine, ReadHexNumber); family
   scopes hold what is internal to them.
10. Where builds differ only in places, the routine is one `.proc` with `.if` inside it (the owner's D5), so the
    source shows what each version changed: Decode, GetLine, Echo, SetHook and ReadKey. Return, the same in every
    build, is written once between the per-build cassette code. The routines that differ throughout (the IIe's
    calls into its firmware, the Enhanced IIe's cassette stubs, the Apple II's TRACE and STEP) are a `.proc` per
    build under `.if`. Both IIes' ClearToEndOfLine and ClearLineFrom have one shape, but the original IIe flips the
    carry, keeps the column at $1F instead of BAS2L and leaves through Scroll's firmware call instead of
    KeyboardIn's, so an `.if` would sit on most lines; they stay a `.proc` per build.
11. VLINEZ is a scope-level label `LowRes::NextVerticalRow`, shared by the family's routines.
12. SLOTRTS on the original IIe is `Commands::UserText` (Control-Y runs the text bytes and falls into USR), and on
    the Enhanced IIe `SelectSlotRom`; the Apple II and Autostart Monitors have none.
13. The Enhanced IIe's `CompareSlot3Rom` is a top-level proc outside `Disassembler`, which continues after it.
14. The disassembler's addressing-mode enum's members are full words (ZERO_PAGE_X, INDIRECT_INDEXED).
15. RESET is `Startup::Reset` (Also: RESET); `ResetToMonitor` mentions the 1978 listing's RESET in prose only.
16. GETLN1 is `GetLine::NoPrompt` (Also: GETLN1); the source's GETLN_1 spelling is dropped.
17. INSDS2 is `Disassembler::Decode::Opcode` ($F88E), where DOS's relocator, the Apple II's Integer BASIC
    mini-assembler and Programmer's Aid, and the Enhanced IIe's firmware call it with the opcode in A; `Decode`
    ($F88C) loads the opcode first.
18. Top level is for the I/O everything uses; subsystem routines stay in their families even when programs call
    them (LowRes::Plot, Disassembler::PrintInstruction, Cassette::WriteHeader, Startup::PowerUp).
19. `Commands` is one scope in nine pieces on the Enhanced IIe and eight in the other builds.
20. `Escape` opens under an `.if` per build: in the 1978 build empty in Screen.asm, in the others in Registers.asm,
    each opening with the scope's `;;` block; later pieces are `.scope Escape continued`.
21. No per-line address comments: each documented entry point states its address once (per build where they
    differ) and `.assert`s it.
22. Both models' SLOTRTS definitions keep `Also: SLOTRTS`; the tools resolve an old name to the definition the
    build assembles.
23. The IIe's escape-key reader is `Escape::ReadEscapeKey`, so `ReadKey` always means the top-level routine; for
    the same reason lo-res's row address is `LowRes::RowAddress` and line input's backspace `GetLine::TakeBack`.
