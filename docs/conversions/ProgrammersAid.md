# Programmer's Aid #1: conversion log

`src/Retrocore.Machines.Apple2/Roms/ProgrammersAid/`: the root `ProgrammersAid.asm` and its subject files, one per
routine Apple assembled on its own (hi-res graphics, Renumber and Append, Relocate, Tape Verify, the RAM test, Music),
with `SetControlY.asm`, `RenumberCalls.asm`, `Sweet16.mac` and a new `Equates.asm`. Documents cited: PA1 (the
Programmer's Aid #1 manual's listings), UNKN, and for the Monitor's names the Monitor's own keys.

## Builds

| Build | Root | Switches | Digest |
| --- | --- | --- | --- |
| The chip, 341-0016, and the 1980 System Masters' INTBASIC | `ProgrammersAid.asm` | `RAMTESTFIX` = 0 (default) | `Apple2SourceTests`, "Programmer's Aid #1" |
| The 1983 System Master's INTBASIC (680-0210-A) | `ProgrammersAid.asm` | `RAMTESTFIX` = 1 | `Apple2SourceTests`, "Programmer's Aid #1 with RAMTESTFIX" (added before the conversion, from the source as it was) |

`RAMTESTFIX` selects one instruction in `RamTest::TestNeighbor`: the 1983 build prints the bad data byte where the chip
jumps to $02CB. The root asserts it is 0 or 1.

## Sources

- **PA1**: the manual's listings (archive.org's OCR text of the scan). Checked by script: each of the 246 names cited
  PA1 is found in the text, allowing for the OCR's confusions (0 and O, 1 and I) and its spaces inside a label
  (`HPLOT 1`, `GET INS`). The names come from the listings' equates and labels, which the source followed before the
  conversion; the RAM test's listing is of an earlier version, without the failing-chip report.
- **UNKN**: RELSETUP and TVSETUP (the Control-Y setups at $D4D5 and $D52E, which the listings leave out), and ERRBITS,
  BADBITS, YSAVE and SOCKETS (the failing-chip report, which the listed version lacks). The source used these names
  before the conversion; no listed document gives them.
- RenumberCalls.asm's names (RNMALL, RNMRNG, GETVAR ...) are the source's own, as it said; they get no `Also:`, nor do
  the generated numbered names (`ERRBITS_1`, `PRBYCR_1`, `RNMALL_1`, `APPEND_1`).

## Decisions

- P1. Each routine Apple assembled on its own stays a file and a scope (`HiResGraphics`, `Renumber`, `Relocate`,
  `TapeVerify`, `RamTest`, `Music`); each routine in it is a `.proc`, and a label another routine enters is an
  `Entry:` of the routine it sits in (`Position::SetColor`, `Plot::AtPosition`, `StepHorizontal::AlternateColor`,
  `Step::Draw`, `Step::DrawTurned`, `Step::UpOrDown`, `ReadX::RangeError`, `Append::Restore`, `Append::Done`).
  Renumber's BASIC entries, at $D6DD, are `.scope Renumber continued` in `RenumberCalls.asm`. `SetControlY`, which the
  three Control-Y setups share, is the only top-level routine.
- P2. One scope's old names can't repeat another's in the one assembly, though Apple assembled them apart: an old name
  two definitions give is ambiguous. So DOWN (hi-res and Music), DONE (Renumber and Music) and RTS1 (hi-res and the
  RAM test) are in prose on each; so are the names that would clash with the Monitor's and IIeEquates' old names:
  Music's LENGTH, Renumber's ACC and MODE, hi-res's UP, Relocate's INIT and Integer BASIC's ACC.
- P3. The SWEET16 macros keep Apple's mnemonics (`LD`, `ST`, `SET`, `BNC` ...) as their names, as an instruction set's
  mnemonics are kept, rather than PascalCase; macros take no `Also:`. Two new macros name what the listings write as
  bytes: `NUL` ($0D, which passes over the next byte) and `SetSkippingTwo` (a SET without its constant, which passes
  over two). The SDK's branch helper SW16BRANCH is `Sweet16Branch`.
- P4. Page zero $00-$1F is SWEET16's registers, `Sweet16Registers` (Sweet16.mac), and every part names its bytes from
  it: Renumber's and Relocate's as registers (`Sweet16Registers + FIRST_NUMBER * SWEET16_REGISTER_SIZE`), and the RAM
  test's, Music's and the graphics' as the bytes they borrow. The Monitor's bytes the routines use for their own get
  scoped aliases (`HiResGraphics::LineBase = LowResBase`, `TapeVerify::Checksum = PlotMask`), as do Integer BASIC's
  noun stack bytes the graphics borrow (`DistanceX = NOUNSTKL`).
- P5. The root includes `Equates.asm`, which includes `../System/IIeEquates.asm` and `../System/MonitorEntries.asm`
  as DOS's does (Dos.md, X7), and defines the Monitor routines MonitorEntries.asm lacks with `Inherit:`. Programmer's
  Aid's names for Monitor locations that differ from the Monitor's join IIeEquates' definitions: A1 (PA1) on
  `Address1`, SPEAKER (PA1) on `Speaker`. Names it gives the same way (A1L, COUT, PRERR) are already the definitions'
  old names and are not cited again. Its names for two points inside the Monitor's READ, READX1 ($FF02) and FINISH
  ($FF26), are `ReadCassetteFromHeader` and `ReadCassetteChecksum`.
- P6. Integer BASIC's addresses take the names Integer BASIC's conversion gave them, which landed first
  (IntegerBasic.md): `LowMemory`, `HighMemory`, `NounStackLow`, `ProgramStart`, `VariablesEnd`, `Accumulator`,
  `MemoryFullError`, `PrintDecimal`, `RangeError`, `Statements::Load`, `Cassette::PointAtLength`,
  `Cassette::PointAtProgram` and `Sweet16::Run`, each with `Inherit:` from it and with Integer BASIC's old names (IBSM)
  and Programmer's Aid's (PA1: PPL, MEMFUL, RNGERR, HDRSET, ACADR ...) in `Also:`. Its `SavedX` ($D8) is `BasicSavedX`
  here, where `SavedX` is the Monitor's; the high bytes Programmer's Aid names are `LowMemoryHigh`, `ProgramStartHigh`,
  `VariablesEndHigh` and `AccumulatorHigh`. Integer BASIC's cassette setups join the `Cassette` scope beside the
  Monitor's routines, as Integer BASIC's own `Cassette` scope holds them. Two locals that would shadow
  `RangeError` are `HiResGraphics::ReadX::OutOfRange` and `Renumber::RenumberRange::OutOfOrder`.
- P7. Where a routine does the same job as AppleSoft's hi-res routine descended from it, it takes AppleSoft's
  converted name (Basic.md's renames): `Clear`, `Fill`, `Position`, `StepHorizontal`, `PixelMasks`,
  `FindCoordinates`. The lineage rule doesn't apply across the two vendors' sources, so the names are not cited across.
- P8. The setups' address checks: each documented entry point (the manual's CALL addresses and `D4D5G`, `D52EG`,
  `D5BCG`) asserts its address.
- P9. BASIC variable and statement names in prose are written in backticks (`START`, `TO`, `X0`, `SCALE`), since
  several are also old names or definitions here.

## Found in the code and documented

- Renumber updates the numbers after GOTO, GOSUB, THEN and LIST, not DEL's, though its listing defines a register for
  DEL's token (the previous source's comment said DEL too).
- Tape Verify stops at the first difference; the RAM test counts on the output hook keeping Y.
- `HiResGraphics::DrawInverted` takes its steps at right angles through `Step::DrawTurned`, so those dots are set in
  the color rather than inverted; `Step` counts a collision when the inverted dot was dark.
- Relocate's 1-byte instructions take the same path as 3-byte ones; only their opcode is stored.
- Renumber's pass 1 never reports a new number past 65535: the SWEET16 no-op that skips its compare leaves the `ST`
  before it as the last result, which has no carry, so the number wraps around.
- `HiResGraphics::LineFromOrigin` (HLINRL) draws from the current point by an offset; the previous comment said from
  (0,0).
- Music's second half is the shifted period plus the second byte plus 1, the carry its subtraction leaves; the path
  where the length's low byte carries, once in 256 loops, takes 2 cycles more than the others.
- The RAM test's gallop writes outside the block unless the block's length is a power of 2 and it starts on a
  multiple of it; the chip's gallop error jumps to $02CB, into stale input-buffer bytes, and may not come back to beep.

## Open questions for the owner

- Q2. P3: SWEET16's macros keep Apple's upper-case mnemonics. The alternative is lower case, like the 6502's, which
  would read as instructions but differs from every SWEET16 listing.

## Renames

The names this conversion gave definitions that have historical names from PA1 or UNKN, by file; the Monitor's own
names, which the definitions in Equates.asm inherit, are not listed.

The listing names given in prose instead (P2): DOWN on `HiResGraphics::Step::Down` and on `Music::Play`'s second
half, `Music::Play::SecondHalf`; UP on `HiResGraphics::Step::Up`; RTS1 on `HiResGraphics::StepHorizontal::Done` and
`RamTest::TestBlock::Done`; DONE on `Renumber::Append::Done` and `Music::LookUp::SplitPeriod`; LENGTH on
`Music::NoteLength`; ACC on `Renumber::ACCUMULATOR`; MODE on `Renumber::LINE_NUMBER_MODE`; INIT on
`Relocate::Command::DefineBlocks`; and Integer BASIC's ACC on `Accumulator`.

### Equates.asm

| Historical names | Name |
| --- | --- |
| READX1 (PA1) | `ReadCassetteFromHeader` |
| FINISH (PA1) | `ReadCassetteChecksum` |
| LOMEM (IBSM), LOMEML (PA1) | `LowMemory` |
| LOMEMH (PA1) | `LowMemoryHigh` |
| HIMEM (IBSM, PA1) | `HighMemory` |
| PP (IBSM, PA1), PPL (PA1) | `ProgramStart` |
| PPH (PA1) | `ProgramStartHigh` |
| PV (IBSM), PVL (PA1) | `VariablesEnd` |
| PVH (PA1) | `VariablesEndHigh` |
| ACL (PA1) | `Accumulator` |
| ACH (PA1) | `AccumulatorHigh` |
| XSAVE (IBSM, PA1) | `BasicSavedX` |
| MEMFULL (IBSM, PA1), MEMFUL (PA1) | `MemoryFullError` |
| PRDEC (IBSM, PA1) | `PrintDecimal` |
| RANGERR (IBSM, PA1), RNGERR (PA1) | `RangeError` |
| LOAD (IBSM, PA1) | `Statements::Load` |
| SETHDR (IBSM), HDRSET (PA1), ACADR (PA1) | `Cassette::PointAtLength` |
| SETPRG (IBSM), PRGSET (PA1) | `Cassette::PointAtProgram` |
| SW16 (A2RM78, PA1) | `Sweet16::Run` |

### HiResGraphics.asm

| Historical names | Name |
| --- | --- |
| SHAPEL (PA1) | `HiResGraphics::ShapePointer` |
| SHAPEH (PA1) | `HiResGraphics::ShapePointerHigh` |
| HCOLOR1 (PA1) | `HiResGraphics::ShiftedColor` |
| COUNTH (PA1) | `HiResGraphics::CountHigh` |
| HBASL (PA1) | `HiResGraphics::LineBase` |
| HBASH (PA1) | `HiResGraphics::LineBaseHigh` |
| HMASK (PA1) | `HiResGraphics::DotMask` |
| DXL (PA1) | `HiResGraphics::DistanceX` |
| DXH (PA1) | `HiResGraphics::DistanceXHigh` |
| SHAPEX (PA1) | `HiResGraphics::ShapeBits` |
| DY (PA1) | `HiResGraphics::DistanceY` |
| QDRNT (PA1) | `HiResGraphics::Direction` |
| EL (PA1) | `HiResGraphics::ErrorTerm` |
| EH (PA1) | `HiResGraphics::ErrorTermHigh` |
| X0L (PA1) | `HiResGraphics::LastX` |
| X0H (PA1) | `HiResGraphics::LastXHigh` |
| Y0 (PA1) | `HiResGraphics::LastY` |
| BXSAV (PA1) | `HiResGraphics::KeptX` |
| HCOLOR (PA1) | `HiResGraphics::Color` |
| HNDX (PA1) | `HiResGraphics::ByteIndex` |
| HPAG (PA1) | `HiResGraphics::Page` |
| SCALE (PA1) | `HiResGraphics::Scale` |
| SHAPXL (PA1) | `HiResGraphics::ShapeTable` |
| SHAPXH (PA1) | `HiResGraphics::ShapeTableHigh` |
| COLLSN (PA1) | `HiResGraphics::Collisions` |
| SETHRL (PA1) | `HiResGraphics::ShowAndClear` |
| HCLR (PA1) | `HiResGraphics::Clear` |
| BKGND0 (PA1) | `HiResGraphics::Fill` |
| BKGND (PA1) | `HiResGraphics::Fill::FillPage` |
| BKGND1 (PA1) | `HiResGraphics::Fill::NextFillByte` |
| HPOSN (PA1) | `HiResGraphics::Position` |
| HPOSN1 (PA1) | `HiResGraphics::Position::NextByte` |
| HPOSN2 (PA1) | `HiResGraphics::Position::Divide` |
| HPOSN3 (PA1) | `HiResGraphics::Position::SetColor` |
| HPLOT (PA1) | `HiResGraphics::Plot` |
| HPLOT1 (PA1) | `HiResGraphics::Plot::AtPosition` |
| LFTRT (PA1) | `HiResGraphics::StepHorizontal` |
| LEFT (PA1) | `HiResGraphics::StepHorizontal::Left` |
| LR1 (PA1) | `HiResGraphics::StepHorizontal::StoreMask` |
| LEFT1 (PA1) | `HiResGraphics::StepHorizontal::PreviousByte` |
| LEFT2 (PA1) | `HiResGraphics::StepHorizontal::LastDot` |
| NEWNDX (PA1) | `HiResGraphics::StepHorizontal::NewByte` |
| CSHIFT (PA1) | `HiResGraphics::StepHorizontal::ShiftColor` |
| CSHFT2 (PA1) | `HiResGraphics::StepHorizontal::AlternateColor` |
| RIGHT (PA1) | `HiResGraphics::StepHorizontal::Right` |
| LRUDX1 (PA1) | `HiResGraphics::Step` |
| LRUDX2 (PA1) | `HiResGraphics::Step::Invert` |
| LRUD1 (PA1) | `HiResGraphics::Step::Draw` |
| LRUD2 (PA1) | `HiResGraphics::Step::DrawTurned` |
| LRUD3 (PA1) | `HiResGraphics::Step::StoreDot` |
| LRUD4 (PA1) | `HiResGraphics::Step::Move` |
| EQ3 (PA1) | `HiResGraphics::Step::MaskBits0And1` |
| LRUD (PA1) | `HiResGraphics::Step::MoveLeftOrRight` |
| UPDWN (PA1) | `HiResGraphics::Step::UpOrDown` |
| UP1 (PA1) | `HiResGraphics::Step::UpInGroup` |
| UP5 (PA1) | `HiResGraphics::Step::StoreUpLow` |
| UP2 (PA1) | `HiResGraphics::Step::UpWrap` |
| UP3 (PA1) | `HiResGraphics::Step::UpRotate` |
| UP4 (PA1) | `HiResGraphics::Step::UpPlain` |
| UPDWN1 (PA1) | `HiResGraphics::Step::StoreHigh` |
| DOWN4 (PA1) | `HiResGraphics::Step::DownFromA` |
| EQ4 (PA1) | `HiResGraphics::Step::MaskBit2` |
| DOWN3 (PA1) | `HiResGraphics::Step::StoreDownLow` |
| DOWN1 (PA1) | `HiResGraphics::Step::DownWrap` |
| DOWN2 (PA1) | `HiResGraphics::Step::DownRotate` |
| HLINRL (PA1) | `HiResGraphics::LineFromOrigin` |
| HLIN (PA1) | `HiResGraphics::Line` |
| HLIN2 (PA1) | `HiResGraphics::Line::StoreDistanceX` |
| HLIN3 (PA1) | `HiResGraphics::Line::StoreDistanceY` |
| MOVEX (PA1) | `HiResGraphics::Line::MoveX` |
| MOVEX2 (PA1) | `HiResGraphics::Line::StepY` |
| HCOUNT (PA1) | `HiResGraphics::Line::PlotDot` |
| HLIN4 (PA1) | `HiResGraphics::Line::NextDot` |
| MSKTBL (PA1) | `HiResGraphics::PixelMasks` |
| EQ1C (PA1) | `HiResGraphics::MaskBits2To4` |
| COS (PA1) | `HiResGraphics::Cosines` |
| HFIND (PA1) | `HiResGraphics::FindCoordinates` |
| HFIND1 (PA1) | `HiResGraphics::FindCoordinates::CountBit` |
| HFIND2 (PA1) | `HiResGraphics::FindCoordinates::StoreX` |
| RTS2 (PA1) | `HiResGraphics::FindCoordinates::Return` |
| DRAW (PA1) | `HiResGraphics::Draw` |
| DRAW1 (PA1) | `HiResGraphics::Draw::Rotate` |
| DRAW2 (PA1) | `HiResGraphics::Draw::Start` |
| DRAW3 (PA1) | `HiResGraphics::Draw::NextVector` |
| DRAW4 (PA1) | `HiResGraphics::Draw::Repeat` |
| DRAW5 (PA1) | `HiResGraphics::Draw::TurnedStep` |
| DRAW6 (PA1) | `HiResGraphics::Draw::NextRepeat` |
| DRAW7 (PA1) | `HiResGraphics::Draw::NextShapeByte` |
| XDRAW (PA1) | `HiResGraphics::DrawInverted` |
| XDRAW1 (PA1) | `HiResGraphics::DrawInverted::Rotate` |
| XDRAW2 (PA1) | `HiResGraphics::DrawInverted::Start` |
| XDRAW3 (PA1) | `HiResGraphics::DrawInverted::NextVector` |
| XDRAW4 (PA1) | `HiResGraphics::DrawInverted::Repeat` |
| XDRAW5 (PA1) | `HiResGraphics::DrawInverted::TurnedStep` |
| XDRAW6 (PA1) | `HiResGraphics::DrawInverted::NextRepeat` |
| XDRAW7 (PA1) | `HiResGraphics::DrawInverted::NextShapeByte` |
| BPOSN (PA1) | `HiResGraphics::BasicPosition` |
| BPLOT (PA1) | `HiResGraphics::BasicPlot` |
| BLIN1 (PA1) | `HiResGraphics::BasicLine` |
| BLINE (PA1) | `HiResGraphics::BasicLine::ToPoint` |
| BGND (PA1) | `HiResGraphics::BasicFill` |
| BDRAW1 (PA1) | `HiResGraphics::BasicMoveAndDraw` |
| BDRAW (PA1) | `HiResGraphics::BasicDraw` |
| BXDRW1 (PA1) | `HiResGraphics::BasicMoveAndDrawInverted` |
| BXDRAW (PA1) | `HiResGraphics::BasicDrawInverted` |
| BDRAWX (PA1) | `HiResGraphics::ShapeParameters` |
| BDRWX1 (PA1) | `HiResGraphics::ShapeParameters::FindShape` |
| BDRWX2 (PA1) | `HiResGraphics::ShapeParameters::ShapeAddress` |
| PCOLR (PA1) | `HiResGraphics::ReadColor` |
| PBYTE (PA1) | `HiResGraphics::ReadByteVariable` |
| RTSB (PA1) | `HiResGraphics::ReadByteVariable::Return` |
| GETX0 (PA1) | `HiResGraphics::ReadX` |
| RERR1 (PA1) | `HiResGraphics::ReadX::OutOfRange` |
| GETY0 (PA1) | `HiResGraphics::ReadY` |
| SHLOAD (PA1) | `HiResGraphics::LoadShapes` |
| SHLOD1 (PA1) | `HiResGraphics::LoadShapes::SetLomem` |
| MFULL1 (PA1) | `HiResGraphics::LoadShapes::MemoryFull` |

### Renumber.asm

| Historical names | Name |
| --- | --- |
| NEWLOW (PA1) | `Renumber::FIRST_NUMBER` |
| NEWINCR (PA1) | `Renumber::STEP` |
| LNLOW (PA1) | `Renumber::LOWEST_LINE` |
| LNHI (PA1) | `Renumber::HIGHEST_LINE` |
| TBLSTRT (PA1) | `Renumber::TABLE_START` |
| TBLNDX1 (PA1) | `Renumber::PASS1_TABLE_INDEX` |
| TBLND (PA1) | `Renumber::TABLE_END` |
| TBLIM (PA1) | `Renumber::TABLE_LIMIT` |
| PRGNDX2 (PA1) | `Renumber::PASS2_PROGRAM_INDEX` |
| HMEM (PA1) | `Renumber::PROGRAM_END` |
| SCR9 (PA1) | `Renumber::POINTER` |
| PRGNDX (PA1) | `Renumber::PASS1_PROGRAM_INDEX` |
| CHR0 (PA1) | `Renumber::DIGIT_ZERO` |
| PRGNDX1 (PA1) | `Renumber::PASS1_LINE` |
| CHRA (PA1) | `Renumber::LETTER_A` |
| NEWLN (PA1) | `Renumber::NEXT_NUMBER` |
| TBLNDX2 (PA1) | `Renumber::PASS2_TABLE_INDEX` |
| STRCON (PA1) | `Renumber::STRING_TOKEN` |
| NEWLN1 (PA1) | `Renumber::LAST_NUMBER` |
| REM (PA1) | `Renumber::REM_TOKEN` |
| SCRC (PA1) | `Renumber::APPEND_POINTER` |
| R13 (PA1) | `Renumber::COMPARE_RESULT` |
| OLDLN (PA1) | `Renumber::LOOKUP_NUMBER` |
| THEN (PA1) | `Renumber::THEN_TOKEN` |
| LIST (PA1) | `Renumber::LIST_TOKEN` |
| R0L (PA1) | `Renumber::OldNumber` |
| R0H (PA1) | `Renumber::OldNumberHigh` |
| R11L (PA1) | `Renumber::NewNumber` |
| R11H (PA1) | `Renumber::NewNumberHigh` |
| RENX (PA1) | `Renumber::RenumberAll` |
| RENUM (PA1) | `Renumber::RenumberRange` |
| RNUM3 (PA1) | `Renumber::RenumberRange::FindTable` |
| PASS1 (PA1) | `Renumber::RenumberRange::Pass1` |
| P1A (PA1) | `Renumber::RenumberRange::InRange` |
| P1B (PA1) | `Renumber::RenumberRange::BelowRange` |
| RERR (PA1) | `Renumber::RenumberRange::OutOfOrder` |
| MERR (PA1) | `Renumber::RenumberRange::MemoryFull` |
| P1C (PA1) | `Renumber::RenumberRange::AboveRange` |
| PASS2 (PA1) | `Renumber::RenumberRange::Pass2` |
| P2A (PA1) | `Renumber::RenumberRange::NextLine` |
| UPDATE (PA1) | `Renumber::RenumberRange::Update` |
| UD2 (PA1) | `Renumber::RenumberRange::NextTableEntry` |
| UD3 (PA1) | `Renumber::RenumberRange::AfterNumber` |
| GOTCON (PA1) | `Renumber::RenumberRange::GotNumber` |
| ITEM (PA1) | `Renumber::RenumberRange::NextToken` |
| SKPASC (PA1) | `Renumber::RenumberRange::SkipText` |
| CHKTOK (PA1) | `Renumber::RenumberRange::CheckToken` |
| CONTST (PA1) | `Renumber::RenumberRange::LineNumberNext` |
| CONTS2 (PA1) | `Renumber::RenumberRange::SetMode` |
| APPEND (PA1) | `Renumber::Append` |

### Relocate.asm

| Historical names | Name |
| --- | --- |
| FRMBEG (PA1) | `Relocate::SOURCE_START` |
| FRMEND (PA1) | `Relocate::SOURCE_END` |
| TOBEG (PA1) | `Relocate::TARGET_START` |
| ADR (PA1) | `Relocate::OPERAND` |
| R1L (PA1) | `Relocate::Blocks` |
| INST (PA1) | `Relocate::Instruction` |
| RELSETUP (UNKN) | `Relocate::SetUp` |
| RELOC (PA1) | `Relocate::Command` |
| RELOC2 (PA1) | `Relocate::Command::NextInstruction` |
| GETINS (PA1) | `Relocate::Command::CopyInstruction` |
| XLATE (PA1) | `Relocate::Command::Translate` |
| SW16RT (PA1) | `Relocate::Command::Translated` |
| STINST (PA1) | `Relocate::Command::StoreInstruction` |
| STINS2 (PA1) | `Relocate::Command::StoreByte` |

### TapeVerify.asm

| Historical names | Name |
| --- | --- |
| CHKSUM (PA1) | `TapeVerify::Checksum` |
| PRLEN (PA1) | `TapeVerify::ProgramLength` |
| TVSETUP (UNKN) | `TapeVerify::SetUp` |
| VFYBSC (PA1) | `TapeVerify::VerifyProgram` |
| GETLEN (PA1) | `TapeVerify::VerifyProgram::GetLength` |
| TAPEVFY (PA1) | `TapeVerify::VerifyBlock` |
| VRFY2 (PA1) | `TapeVerify::VerifyBlock::FindSync` |
| VRFY3 (PA1) | `TapeVerify::VerifyBlock::NextByte` |
| VFYLOOP (PA1) | `TapeVerify::VerifyBlock::Matched` |
| EXTDEL (PA1) | `TapeVerify::VerifyBlock::Compare` |

### SetControlY.asm

| Historical names | Name |
| --- | --- |
| SETCTLY (PA1) | `SetControlY` |

### RamTest.asm

| Historical names | Name |
| --- | --- |
| DATA (PA1) | `RamTest::TestData` |
| NDATA (PA1) | `RamTest::InverseData` |
| TESTD (PA1) | `RamTest::GallopData` |
| R3L (PA1) | `RamTest::CheckAddress` |
| R3H (PA1) | `RamTest::CheckAddressHigh` |
| R4L (PA1) | `RamTest::WriteAddress` |
| R4H (PA1) | `RamTest::WriteAddressHigh` |
| R5L (PA1) | `RamTest::TestCell` |
| R5H (PA1) | `RamTest::TestCellHigh` |
| R6L (PA1) | `RamTest::GallopMask` |
| R6H (PA1) | `RamTest::GallopMaskHigh` |
| BADBITS (UNKN) | `RamTest::BadBits` |
| YSAVE (UNKN) | `RamTest::KeptY` |
| SETUP (PA1) | `RamTest::SetUp` |
| RAMTST (PA1) | `RamTest::Command` |
| TEST (PA1) | `RamTest::TestBlock` |
| TEST01 (PA1) | `RamTest::TestBlock::Fill` |
| TEST02 (PA1) | `RamTest::TestBlock::Check` |
| TEST03 (PA1) | `RamTest::TestBlock::NextCheck` |
| TEST04 (PA1) | `RamTest::TestBlock::NextTestCell` |
| TEST05 (PA1) | `RamTest::TestBlock::NextNeighbor` |
| TEST6 (PA1) | `RamTest::TestNeighbor` |
| PRBYCR (PA1) | `RamTest::PrintByteAndError` |
| PRBYSP (PA1) | `RamTest::PrintByteSpace` |
| ERRBITS (UNKN) | `RamTest::PrintFailingChips` |
| SOCKETS (UNKN) | `RamTest::SocketDigits` |

### Music.asm

| Historical names | Name |
| --- | --- |
| DOWNTIME (PA1) | `Music::SecondHalfCount` |
| UPTIME (PA1) | `Music::FirstHalfCount` |
| VOICE (PA1) | `Music::Timbre` |
| LONG (PA1) | `Music::Duration` |
| NOTE (PA1) | `Music::Pitch` |
| ENTRY (PA1) | `Music::PlayNote` |
| PLAY (PA1) | `Music::Play` |
| PLAY2 (PA1) | `Music::Play::FirstHalfLoop` |
| PATH1 (PA1) | `Music::Play::FirstNotCarried` |
| PATH2 (PA1) | `Music::Play::CountFirstHalf` |
| PATH3 (PA1) | `Music::Play::NextFirstHalf` |
| PLAY3 (PA1) | `Music::Play::SecondHalfLoop` |
| PATH4 (PA1) | `Music::Play::SecondNotCarried` |
| PATH5 (PA1) | `Music::Play::CountSecondHalf` |
| PATH6 (PA1) | `Music::Play::NextSecondHalf` |
| LOOKUP (PA1) | `Music::LookUp` |
| SHIFT (PA1) | `Music::LookUp::ShiftByTimbre` |
| REST (PA1) | `Music::Rest` |
| REST2 (PA1) | `Music::Rest::CountRest` |
| REST3 (PA1) | `Music::Rest::RestNotCarried` |
| REST4 (PA1) | `Music::Rest::NextRest` |
| NOTES (PA1) | `Music::NotePeriods` |
