# The VIC-20's ROMs: conversion log

The VIC-20's three ROMs as SDK sources (plan phase V4 of [the Commodore plan](../backlog/Commodore.md)): BASIC
(901486-01), the kernal (901486-06 for NTSC, -07 for PAL) and the character generator (901460-03). They are written
from the dumps in the maintained style; Commodore's listings give the old names only, kept in `Also:` (the plan's
answered question 1, the PET's rule). This log covers steps 1 to 3 of [the method](../ConvertingSources.md) for each
source, and the rename table, [Vic20KernalRenames.md](Vic20KernalRenames.md), drafted for the owner's review in
parts and complete, all seven parts settled (K11); then the conversions, the kernal's (step 4 below) and BASIC's
(step 5 below).

## Builds

| Tag | Build | Root and switches |
| --- | --- | --- |
| V | VIC-20 BASIC 2, 901486-01, `$C000-$DFFF`, and its last part in the kernal chip, `$E000-$E47B` | `Vic20/Basic.asm`, PAL = 0 or 1 for the kernal chip's checksum byte |
| VN | The NTSC kernal, 901486-06, from `$E47C` | `Vic20/Kernal.asm`, PAL = 0 |
| VP | The PAL kernal, 901486-07 | `Vic20/Kernal.asm`, PAL = 1 |
| VC | The character generator, 901460-03 | `Vic20/CharacterGenerator.asm`, over the PET's `CharacterGenerator.asm` with VIC20 = 1 |

BASIC's source and the kernal's together assemble byte-identically to the kernal chip, as BASIC 2's and the
editor's do for the PET's editor chip.

## Decisions accepted by the owner

- K1 (2026-11-25). The kernal is written in the maintained style from the start: every name renamed, every name
  Commodore's listing and the references give kept in its definition's `Also:`.
- K2 (2026-11-25). The kernal is one standalone source, `Vic20/Kernal.asm`, as the plan says (one kernal per
  machine, with switches for its revisions and standards). Its names are chosen so the 64's kernal can share them;
  whether the two share modules is decided at phase C3, when the 64's differences are known.
- K3 (2026-11-25). The kernal's rename table is reviewed whole before any conversion, in parts by area: the
  variables and I/O, the screen editor and keyboard, the serial bus, the tape, RS-232, the channels and files, and
  start-up, interrupts and the jump table. Each part is settled before the next is drafted.
- K4. BASIC's names follow the BASIC conversion's decisions ([Basic.md](Basic.md), X1-X16): the shared modules'
  names are the ones the VIC-20's BASIC assembles with, the jump-table entries BASIC calls keep X14's `Kernal`
  prefix (`KernalCharacterOut`), and the VIC-20's own names for shared code go in Commodore's historical-names file.
  The kernal's jump table defines those same names.
- K5 (2026-11-25). Part 1 of the rename table, the variables, RAM vectors, VIAs and constants, is accepted with its
  questions as recommended: the families (`Editor`, `Serial`, `Tape`, `Rs232`, `Channels`, `Clock`, `Startup`,
  `Interrupts`) with the widely used variables, vectors, hardware and jump table top level (K-P1-Q1); a byte with
  two jobs named once per job in each family (Q2); a location per VIA register, with the keyboard's aliases (Q3);
  the VIC's registers named for what they set, in part 7 (Q4); `Colour` (Q5); and 16 unused declarations left out,
  named in prose (Q6).
- K6 (2026-11-25). Part 2, the screen editor and keyboard, is accepted with its questions as recommended: PRT is
  the top-level `ScreenOut` (K-P2-Q1); KEY is `Interrupts::Jiffy` (Q2); IOBASE, SCRORG and PLOT are in `Editor`
  (Q3); labels entered mid-routine are entries (Q4); jump-on labels are named for the step they end (Q5); the
  Japanese version's traces are kept as NOPs, data and `Editor::SpareKeys`, with 13 unnamed labels dropped (Q6);
  and VPAN is `Editor::ResetScreen` (Q7).
- K7 (2026-11-25). Part 3, the serial bus, is accepted with its questions as recommended: the entry points named
  for what they send or receive, matching the jump table's BASIC names (K-P3-Q1); the line routines named for the
  bus line (`ReleaseClock`, `PullData`) (Q2); the patch-area routines in a `.scope Serial continued` piece (Q3); and
  the `BIT`-skip routines kept as `.proc`s with asserts (Q4).
- K8 (2026-11-25). Part 4, the tape, is accepted with its questions as recommended: four of part 1's tape
  variables corrected from the read routines' comments, and second names for four bytes' second jobs (K-P4-Q1); the
  tape's interrupt handlers as routines (Q2); and the tape's error bits as IoStatus constants (Q3).
- K9 (2026-11-25). Part 5, RS-232 and the NMI, is accepted with its questions as recommended: the NMI handler in
  `Interrupts`, with BRK's target its entry `Break` (K-P5-Q1); NMIRTI and PREND one entry, `Return` (Q2); RS-232's
  signal names kept short in comments (Q3); and each standard's baud rate table written out under `.if PAL` (Q4).
- K10 (2026-11-25). The owner accepted the work so far and left the remaining questions to the drafter's
  judgement, so parts 6 and 7 are settled as recommended without a separate review. Part 6, the channels, files,
  messages, errors and clock: the RAM vectors' defaults are the `Channels` routines (K-P6-Q1); the messages one
  table (Q2); ERROR1-ERROR9 entries of `Channels::Error`, with `KERNAL_ERROR_*` constants (Q3); the ROMs' own patch
  (901486-06 and -07 alike) named `Channels::CloseTapePatch`, the listing's STPTCH and ITSSET dropped (Q4); and no
  local shadowing a family (Q5).
- K11 (2026-11-25). Part 7, start-up, the IRQ, the jump table and the VIC's registers, settled the same way: the
  jump table's entries top level with the `Kernal` prefix and both the listing's and the reference guide's names
  in `Also:` (K-P7-Q1); SETNAM, SETLFS, READST and SETMSG in `Channels`, SETTMO in `Serial`, MEMTOP and MEMBOT in
  `Startup` (Q2); table ends used only for a length as constants (Q3); the VIC's registers named for what they set
  (Q4); and the code's slips documented, not changed (Q5). With it the table is complete: 901 rows in seven parts.

## Step 1: the inventory

Made by script, outside the repository:

- **The listings.** Commodore's VIC-20 sources from [mist64/cbmsrc](https://github.com/mist64/cbmsrc):
  `BASIC_VIC` (33 files) and `KERNAL_VIC_04` (29 files, listing date 9 October 1980). A small assembler for
  Commodore's syntax assembled each, giving every label an address: 908 in BASIC, 831 in the kernal. They stay in the
  scratchpad, never in the repository (D8 of the BASIC log).
- **Against the dumps.** At the same addresses, 8,803 of BASIC's 9,309 bytes and 6,618 of the kernal's 6,965 match
  901486-01 and -06; nothing is shifted. The bytes that differ are single operands and the patches the later
  revisions added (at `$E4CF-$E4FF`, `$ED69-$ED71` and a few others). So each listing name is tied to its ROM
  address directly.
- **The kernal's names**, by the listing's files: the declarations (199: zero page, pages 2 and 3, the VIC, the
  VIAs, the colour RAM and constants), the screen editor (215, in `EDITOR.1`-`3` and `CONKAT`), the serial bus
  (49), RS-232 (72), the channels and files (`CHANNELIO`, `OPENCHANNEL`, `CLOSE`, `CLALL`, `OPEN`, `MESSAGES`,
  `ERRORHANDLER`: 112), loading and saving (53), the clock (10), the tape (115) and start-up, the interrupts and the
  jump table (55).
- **Unused declarations.** 22 declared names are not used by the kernal's code: the PET monitor's registers at
  `$00-$08` (PCH, PCL, FLGS, ACC, XR, YR, SP, INVH, INVL, which are BASIC's zero page in the VIC-20), TMPC, FREKZP,
  BASZPT, M51AJB, USRCMD, the VIAs' timer 1 latches and shift registers (D1T1LL, D1T1LH, D1SR, D2T1LL, D2T1LH,
  D2SR), and the constants LLEN2 and CR. As the conversion rules say for an equate a source never uses, the 16 that
  are not VIA registers are left out and named in prose where the layout is described (K-P1-Q6); the six VIA
  registers are kept, since the `Via` layout names every register.
- **BASIC.** The VIC-20's BASIC has 3,956 of its 4,282 instructions in the order PET BASIC 2 has them. The
  differences are in about 35 places: the start-up vectors and the `CBMBASIC` signature, the RAM vectors at
  `$0300` through which it calls its main loop, tokenizer, lister, statement and expression evaluation, the
  kernal calls where the PET's BASIC calls its own I/O, and its last part (`$E000-$E47B`: the I/O statements,
  `SYS`, start-up and the sign-on).
- **The PAL chip** differs from the NTSC one in 22 bytes at nine places: the chip's checksum byte (`$E475`, in
  BASIC's part), and in the kernal 21 bytes: the screen's position in the VIC's start-up table (`$EDE4-$EDE5`), the
  jiffy timer (`$FE3F`, `$FE44`) and the RS-232 baud rate table (`$FF5C-$FF70`, in five runs).
- **The character generator** is the PET 2001-N's 901447-10 with £ at `$1C` in both sets, each set followed by its
  reversed copy. It is built from the PET's source with a `VIC20` switch (done; both chips assemble
  byte-identically).

## Step 2: the documents

The bibliography keys, now in [the bibliography](../Bibliography.md):

| Key | Document |
| --- | --- |
| KV20 | VIC-20 kernal source, listing of 9 October 1980 (`KERNAL_VIC_04` in mist64/cbmsrc) |
| BV20 | VIC-20 BASIC source (`BASIC_VIC` in mist64/cbmsrc), with revisions to 6 March 1981 |
| V20PRG | VIC-20 Programmer's Reference Guide (Commodore, 1982), first edition, sixth printing |
| MTV | *COMPUTE!'s Mapping the VIC*, Russ Davies (COMPUTE! Books, 1984) |

The checks, by script against each document's text (an OCR, allowing for its damage):

- **KV20 and BV20**: a name is the listing's for an address when the listing, assembled, puts the label there.
- **MTV and V20PRG**: a name is checked when it appears as a word within 300 characters of its address (decimal,
  or hex with `$`); "spelling only" when it appears but not by its address. For the kernal's declarations (part 1
  of the table, 199 rows), MTV gives 103 of the listing's names by their addresses and V20PRG 7, and spells 8 and 32
  more not by their addresses (the rows' Documents column); MTV also gives its own names for the VIC's and VIAs'
  registers (`VICCR5`, `VIA1PB`), which go in `Also:` as MTV's.

## Step 3: the rename table

[Vic20KernalRenames.md](Vic20KernalRenames.md), in parts (K3). Each part's questions are listed there, before its
rows.

## Step 4: the kernal

`Vic20/Kernal.asm` and the ten files it includes: the equates, then nine in address order from `$E47C`. Both
builds are byte-identical (VN and VP), and `Vic20RomSourceTests` pins them by digest; `BuildLinkTests` and
`Vic20RomSourceTests.KernalOldNamesCiteItsDocuments` check each build's links and citations (the second found
`SIXTY` only in the PAL build, its comment above the `.if`; each branch now has its own). Each file's routines were then
documented by hand, one person or agent per file, with their contracts (`In:`, `Out:`, `Errors:`, `Keeps:`, traced
through what they call), step headings and named constants.

What the conversion changed in the table (its rows now give the source's names):

- `STKY` (part 4, a local of `Tape::WriteLeader`) is its own routine, `Tape::AllWritten`: its code follows
  `Tape::Finish`, another routine, so it cannot be a local (X2 of the BASIC log).
- `CCTTA2` (dropped) is the Japanese table's name left on `Editor::CaseCodes`' address, which `Editor::KeyTables`
  points at; the table names `CaseCodes`.
- Four locals that shadowed a family's name were renamed: `Editor::InsertLine::ClearOpenedRow`,
  `Editor::ScanKeyboard::CountInterval`, `Rs232::Open::TakeOutputPage` and `Tape::ReadInterrupt::CheckParity`.
- An old name that two definitions would give (Commodore's label on a routine and the reference guide's name for
  its jump-table entry, such as RESTOR) stays on the jump-table entry, which is what programs call; the routine says
  in prose that the listing names it so. A byte's second job names its main job's old name in prose (`SHCNL` is
  `Tape::ShortCountLow`'s; `Tape::CopiesLeft` says so), so part 4's rows for the second jobs give no old name, only
  the part 1 row whose byte they share.
- `CARTRIDGE_SIGNATURE_LENGTH` and `RAM_VECTORS_SIZE` (part 7) are in `Startup`, beside their tables.
- New names for the ROMs' own code (901486-06 and -07 alike): `Channels::Close::LastBlockWritten` and
  `Channels::Close::Return`, where the patch at `$E4CF` comes back (the ROMs' CLOSE returns with carry set after
  STOP at the last block, where the listing cleared it), and CTRL with the left arrow gives `$06` in
  `Editor::ControlKeys`, where the listing has `$FF`.

Facts the table's reasons had wrong, corrected in the source: `Startup::Temporary` is `RestoreVectors::Copy`'s
pointer, not the RAM test's; the cartridge signature is "A0" in plain ASCII and "CBM" with bit 7 set; the screen
moves to `$1000` only when RAM reaches `$2100`; the tape's bad-byte log holds 31 addresses; CHROUT does not keep A
when it starts RS-232's sender; and `ScrollDownOff` (AUTODN) pushes the rows below down when it is non-zero, the
opposite of what its name and *Mapping the VIC* suggest. The name stays as the owner accepted it; its comment says
which way the code reads it.

Reasons corrected in the table itself, to agree with the source: BUF (`InputBuffer`) holds no file name, the
kernal uses only its page, as the lowest a tape buffer may be; SYNO (`Tape::BlockSync`) is set by 16 more short
pulses than long, about 8 dipoles, not 16 dipoles; FAH (`Tape::FindHeader`) returns `VerifyFlag` in A for STOP,
not 0; LIST2 never releases CLK for UNLISTEN; CKO232 tests only x-line handshaking, not half duplex; CKI232 and
CKI020 wait on DTR, not DCD; RSTEXT's bit is bit 5 of the peripheral control register, not PB5; and OP170 takes the
next header of any kind, not only a data file's. The rows of routines whose names moved to their jump-table
entries now say the routine cites them in prose: KV20 and MTV, which gives each at the routine's address, for
IOBASE, PLOT and SCNKEY (part 2), TALK, TKSA, CIOUT, UNTLK, UNLSN and ACPTR (part 3), UDTIM, RDTIM and SETTIM (part
6), and RESTOR, VECTOR, SETNAM, SETLFS, SETMSG, READST, SETTMO, MEMTOP and MEMBOT (part 7); KV20 alone for LOAD and
SAVE (part 6).

The code's slips are documented in their comments and left as they are (K-P7-Q5). Among them, by the addresses of
their instructions: the x-line handshake reads VIA 2's port B (the keyboard) for DSR and CTS (`$EFF4`, `$F512`), as
*Mapping the VIC* reports; the DCD wait tests the wrong bit; the received parity check is wrong and
`ReceivedParity` is never cleared by RS-232's code; the start bit's `bne` to the next instruction (`$FF36`, and
OPEN's at `$F4F2`) leaves baud code 0 reading the bytes before `Rs232::BaudRates`; READST returns 0 for RS-232; the
tape's wait for the end of the operation tests VIA 2's timer flag (`$F93B`) and clears VIA 1's (`$F942`); VECTOR
changes the IRQ vector with interrupts on; and each RESTORE without a cartridge adds a jiffy to the clock.

## Step 5: BASIC

`Vic20/Basic.asm` is a root over the shared Commodore and Microsoft modules, as the PET's are, with the names of the
BASIC conversion (K4). It assembles byte-identically to 901486-01 and the kernal chip's `$E000-$E47B`, of 901486-06
with PAL = 0 or -07 with PAL = 1, and every PET build and AppleSoft still assemble to their bytes.
`Vic20SdkModules`, in the debug host's library (`Retrocore.Debug`, called only by the tests so far), builds the
three ROMs from the sources, the kernal chip from both BASIC's and the kernal's, and the machine starts from them to
`READY.` on both standards with no dumps (`Vic20RomSourceTests`).

Switches, each named for what it changes and defaulting to the PET's code, so the 64's BASIC can use them too (in
`Commodore.Switches.asm`): `CONVERSION_VECTORS` (ADRAY1 and ADRAY2 after the `USR` jump), `CURSOR_COLUMN_FROM_PLOT`
(the column read through PLOT, with `TAB`'s copy in BASIC's own byte at `$09`), `OUTPUT_SUPPRESSION_FLAG` (0 drops
Control-O's flag), `STANDARD_KERNAL` (the VIC-20's jump table, status and clock, the kernal's errors, BASIC's own
I/O statements), `BASIC_RAM_VECTORS` (the six vectors at `$0300`) and `NUMBERED_ERRORS` (errors from 1, found through
a table of addresses). In `Commodore.FloatingPoint.asm`: `SQR_PATCH_SPACE` and `UNSPACED_LINE_NUMBERS`.
`LINE_LENGTH` and `ZONE_WIDTH` can be predefined (22 and 11 for the VIC-20). The shared modules took new trailing
parameters, empty for their old code, or new values of existing ones.

The VIC-20's own code is in new modules, in the maintained style: `Commodore.KernalStatements.asm` (the kernal's
error check, the checked kernal calls, `SYS`, `LOAD`, `SAVE`, `VERIFY`, `OPEN`, `CLOSE` and their parameters),
`Commodore.KernalStartup.asm` (cold start, the workspace, the sign-on, the vectors' defaults and the warm start) and
`Commodore.NumberedErrors.asm`. `Commodore.SharedModules.asm` wraps the six modules that emit code where they are
included, so that a root outside `Roms/Basic` finds them in the repository and in the SDK alike.

New names, with the listing's in `Also:` (BV20): the RAM vectors `ErrorVector`, `CommandLoopVector`,
`TokenizeVector`, `ListTokenVector`, `StatementVector` and `OperandVector` (IERROR to IEVAL), each routine behind one
a `Default` entry of the routine that jumps through it (NERROR is `ReportError::Default`); `FloatToIntegerVector` and
`IntegerToFloatVector` (ADRAY1, ADRAY2); `LoadVerifyFlag` (VERCK); `SysAccumulator`, `SysX`, `SysY` and `SysStatus`
(SAREG to SPREG); `ReportKernalError` (EREXIT); `CheckedCharacterOut`, `CheckedCharacterIn`, `CheckedSelectOutput`
and `CheckedSelectInput` (OUTCH, INCHR, COOUT, COIN); `Statements::Sys`, `Load`, `Save`, `Verify`, `Open` and
`Close`; `ParseLoadSave`, `ParseOpenClose` and their helpers (PLSV, PAOC); `InitializeWorkspace`, `PrintSignOn`,
`VectorDefaults`, `InitializeVectors` and `WarmStart` (INITCZ, INITMS, BVTRS, INITV, PANIC); `RelinkLoadedProgram`
(PLINK); the checksum bytes `BasicRomChecksumAdjustment` and `KernalRomChecksumAdjustment` (CKSMC0, CHKE0); and the
kernal entries BASIC calls with the kernal source's names and the `Kernal` prefix (`KernalReadStatus`,
`KernalSetClock`, `KernalReadClock`, `KernalPlot`, `KernalIoBase`, `KernalSetMessages` and others). Four listing
names for shared definitions are aliases in `Commodore.HistoricalNames.asm`: CLEART, NQPLOP, NEVAL and FLPINT.

What the work found:

- `$E475`, the one byte that differs between the NTSC and PAL kernal chips in BASIC's part, is the kernal chip's
  checksum byte: each chip sums to `$E0` with end-around carry. `$DF52` does the same for the BASIC chip (`$C0`).
- `VERIFY` (`$E187`) tests the text pointer's low byte instead of its page to decide whether it runs in direct mode,
  so it prints `OK` in a program whenever that byte is not 2; `LOAD`'s test (`$E1A1`) reads the page.
- Error 30's message is `BREAK`, a zero and `$A0`, so reporting it prints the zero and a space before the end.
- The ROM's load from a program ends with `jsr` to reset the text pointer and `jmp` to the relink patch at `$E476`
  (the listing's revision of 6 March 1981); start-up jumps to `READY`.

Left for later: `BV20` on the `Also:` lines of shared definitions whose names the listing shares, a mechanical
pass; and `LAST_COMMA_COLUMN` (NCMPOS), which this build computes as 11 where the listing keeps 30, unused by the
code either way.
