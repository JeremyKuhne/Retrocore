# The Apple II Monitor: conversion log

`src/Retrocore.Machines.Apple2/Roms/System/Monitor.asm` and its subject files in `Monitor/`: one source for the
1978 Monitor, the Autostart Monitor and the original and Enhanced IIe's, chosen by `MONITOR` and `ENHANCED`.
Documents cited: A2RM78, A2RM79 (the Apple II Reference Manuals), IIEROM82 (the IIe ROM listings), IIETRM85 (the
IIe Technical Reference Manual), UNKN. `Monitor.asm` asserts the MONITOR and ENHANCED values its
digests check.

1. Every name is renamed to the style, including Apple names that already fit (`HOME` is `Home`); the old name goes
   in `Also:`.
2. The lo-res graphics family is the scope `LowRes`.
3. Apple labels nothing references (PRBL3, INITAN, SETPG3, RTS4C, VFYOK, RESTR1, MD3) stay as named locals with
   `Also:`: a label with a documented name is kept.
4. Locals that jump on to a firmware routine are `ToFirmware`, not `CallFirmware`.
5. IIe names are cited only from documents in hand (the IIe Technical Reference Manual, the ROM listing), and only
   names checked in them.
6. Names that may be this source's own (MEMFIND, MINIASM, TITLE2E, RDKEYHOOK ...) stay in `Also:` as UNKN;
   XGOTOCX (IIEROM82) and DOCOUT1 (IIETRM85), which the IIe listings give, cite them. Obviously generated numbered
   locals (`GETLN_1`, `CLREOP_2`) are dropped with no `Also:`.
7. The firmware's entry equates (B_FUNC, BASICIN, IRQHANDLER ...) wait for the firmware conversion.
8. Families spread through the ROM are continued scopes: `Commands`, `Startup`, `Stepper` (the 1978 STEP and
   TRACE), each later piece `.scope X continued` with a plain comment saying which part.
9. Widely called documented entry points are top level (SetKeyboard, SetScreen, GetLine, ReadHexNumber); family
   scopes hold what is internal to them.
10. Where builds differ mid-routine, each build's routines are whole `.if` blocks of complete `.proc`s.
11. VLINEZ is a scope-level label `LowRes::NextVerticalRow`, shared by the family's routines.
12. SLOTRTS on the original IIe is `Commands::UserText` (Control-Y runs the text bytes and falls into USR); other
    builds keep `SelectSlotRom`.
13. The Enhanced IIe's `CompareSlot3Rom` is a top-level proc outside `Disassembler`, which continues after it.
14. The disassembler's addressing-mode enum's members are full words (ZERO_PAGE_X, INDIRECT_INDEXED).
15. RESET is `Startup::Reset` (Also: RESET); `ResetToMonitor` mentions the 1978 listing's RESET in prose only.
16. GETLN1 is `GetLine::NoPrompt` (Also: GETLN1); the source's GETLN_1 spelling is dropped.
17. DOS's INSDS2 ($F88E) stays DOS's: no `Also:` on the disassembler's opcode decoder.
18. Top level is for the I/O everything uses; subsystem routines stay in their families even when programs call
    them (LowRes::Plot, Disassembler::PrintInstruction, Cassette::WriteHeader, Startup::PowerUp).
19. `Commands` is one scope in nine pieces.
20. `Escape` opens under an `.if` per build (`.scope Escape` in the 1978 build, `.scope Escape continued` in the
    others), its `;;` block above whichever opening comes first.
21. No per-line address comments: each documented entry point states its address once (per build where they
    differ) and `.assert`s it.
22. Both models' SLOTRTS definitions keep `Also: SLOTRTS`; the tools resolve an old name to the definition the
    build assembles.
23. The IIe's escape-key reader is `Escape::ReadEscapeKey`, so `ReadKey` always means the top-level routine.
