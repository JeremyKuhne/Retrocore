# BASIC rename table (draft)

The rename table for the BASIC sources, step 3 of [the method](../ConvertingSources.md): a draft for the owner's
review. Nothing is renamed yet. The decisions, the documents, the inventory's method and counts, and every question
this table raises are in the log, [Basic.md](Basic.md); a note such as "see A-Q4" points at a part's question
there, and the cross-cutting ones are X1 to X16, which the owner settled as recommended on 2026-11-23. The table follows
them: statement names keep their keyword split at its words (X13), every local is written by its full path
(X16), and the kernal routines BASIC calls have the `Kernal` prefix (X14).

One row per name per file (but for three pairs of same-named macro parameters): 2,411 rows, grouped by module (the shared Microsoft modules first, then AppleSoft's,
then Commodore's), in the module's source order within each. The columns:

- **#**: the row's number, for reference in reviews.
- **Old**: the name as the source defines it today.
- **New**: the proposed name, as it will be written: `FindLine`, a scope member `Statements::Next`, a local
  `FindLine::Done`, a constant `TOKEN_FOR`. KEEP keeps the name (the SDK's own switches and macro parameters,
  and the names C# predefines); DROP removes the definition (see Basic.md, step 3, for what happens to a dropped
  name). A name with a per-build bracket (`[PET]`, `[IIeE]`) differs by build.
  Rows with the same new name in one build are one definition with several old names (`INDEX` and `INDEX1` are
  `Pointer1`).
- **Kind**: routine, entry (a labeled entry into a routine), local, location, alias (a scoped second name for a
  location), constant, token, error, message, table, data, switch, macro or macro parameter.
- **Builds**: the builds the definition is in: II+, IIe, IIeE; P1, P1R, P2, P4, P4R; "AS" for the three AppleSoft
  builds, "PET" for the five PET builds, "all" for the eight.
- **Documents (checked)**: the documents checked to give the old name for this thing, by key (Basic.md, step 2),
  with the builds a key covers in brackets where it covers fewer than the row's builds. These are the row's
  `Also:` entries. "Spelling only" lists documents that spell the name but where the check could not tie it to this
  thing: they are not cited. "Other names here" lists names a document gives at this address under another
  spelling: they go in the `Also:` of this definition, or (for shared code) of the vendor's alias (X5). "None found"
  means no listed document gives the name: the owner decides between UNKN and no `Also:`.
- **D3**: for shared code, whether the old names are vendor-only. "no" means Microsoft's name, valid in every
  build; "aliases: ..." lists the vendors' other names, which go in the vendor's own file (X5); "vendor" marks a
  definition in a vendor's own file, whose names are the vendor's anyway.
- **Reason**: one line from the code, then any note from drafting.

The inventory and the document checks were made by script against the eight builds; the names were drafted in
seven parts and merged; where the parts disagreed, and what two independent reviews corrected, the log says (K1
to K12, R1 to R10).



### MsBasic.AdditionCore

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1 | `ADD_ENTRIES` | `AddEntries` | macro | all |  | — | emits AddHalf, SubtractFromPacked and SubtractFromArg, the entries that precede vendor code — SDK macro name, PascalCase per the style |
| 2 | `FADDH` | `Float::AddHalf` | routine | all | M6502, ASTIL [AS], AS82 [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | loads Half's address into Y:A and jumps to AddPacked: Fac = Fac + 0.5 |
| 3 | `FSUB` | `Float::SubtractFromPacked` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | unpacks Y:A into Arg (LoadArg), then falls into SubtractFromArg: Fac = packed - Fac — Falls into SubtractFromArg |
| 4 | `FSUBT` | `Float::SubtractFromArg` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | flips FacSign, recomputes ResultSign, loads FacExponent and jumps to AddArg: Fac = Arg - Fac — operator-table target for '-' |
| 5 | `ADD_AND_NORMALIZE` | `AddAndNormalize` | macro | all |  | — | emits the adder, normalizer, complementer, rounding increment, overflow error and right shifter |
| 6 | `FADD5` | `Float::ShiftAndAdd` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | shifts the smaller operand right through ShiftRight (eight bits or more), then joins AlignAndAdd::Combine — placed before AddPacked; reached only from AlignAndAdd::Align; see A-Q4 |
| 7 | `FADD` | `Float::AddPacked` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | unpacks Y:A into Arg (LoadArg), then falls into AddArg: Fac = packed + Fac — Falls into AddArg; Monitor's top-level Multiply/Divide are why the pair is not plain Add/Multiply, see A-Q5 |
| 8 | `FADDT` | `Float::AddArg` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Fac = Arg + Fac: a zero Fac takes Arg (CopyArgToFac); otherwise saves FacExtension and aligns with X = Arg — operator-table target for '+'; Falls into AlignAndAdd |
| 9 | `FADDC` | `Float::AlignAndAdd` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | with A = Arg's exponent, shifts the smaller-exponent operand into line, then adds or subtracts the mantissas by ResultSign — MultiplyByTen's AddScaledArgAndDouble calls it; zero A branches to WAIT's ZERRTS rts (B1's label), see note in md |
| 10 | `FADDA` | `Float::AlignAndAdd::ArgSmaller` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Arg has the smaller exponent: clears FacExtension, which takes Arg's shifted-out bits |
| 11 | `FADD1` | `Float::AlignAndAdd::Align` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | a shift of eight bits or more goes to ShiftAndAdd; a shorter one shifts the operand at X through ShiftRight::ShiftLow |
| 12 | `FADD4` | `Float::AlignAndAdd::Combine` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | tests ResultSign: equal signs go to AddMantissas, opposite signs subtract — reached from ShiftAndAdd; see A-Q4 |
| 13 | `FADD3` | `Float::AlignAndAdd::OppositeSigns` | local | all | M6502 | no | picks Y as the operand that was not shifted, so the shifted one (X) is subtracted from it — nothing references it; M6502 names it, so kept |
| 14 | `SUBIT` | `Float::AlignAndAdd::Subtract` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | subtracts the operand at X from the one at Y, guard bytes first, into Fac's mantissa; falls into NormalizeSigned |
| 15 | `FADFLT` | `Float::NormalizeSigned` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | carry clear (a negative result): complements Fac first, then falls into Normalize — ConvertMantissa and Functions::Int jump here |
| 16 | `NORMAL` | `Float::Normalize` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS], AS82 [AS] | no | shifts Fac left a byte at a time, then a bit at a time, lowering the exponent; underflow gives zero — ASTIL lists it only weakly; NormalizeResult and Functions::Rnd call it |
| 17 | `NORM3` | `Float::Normalize::ShiftBytes` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | while the top mantissa byte is zero, moves each byte up one and counts 8 in A; four zero bytes fall into SetZero |
| 18 | `ZEROFC` | `Float::SetZero` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores 0 in FacExponent and FacSign, which makes Fac zero (its mantissa is left as it is) — named SetZero so that ZERO's data can be ZeroValue; StringFunctions and Underflow jump here |
| 19 | `ZEROF1` | `Float::SetExponentAndSign` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores A in FacExponent and falls into SetSign; RaiseArg reaches it with A = 0 — Falls into SetSign |
| 20 | `ZEROML` | `Float::SetSign` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores A in FacSign and returns; AddExponent reaches it with A = 0 for a zero result |
| 21 | `FADD2` | `Float::AddMantissas` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | equal signs: adds Arg's mantissa and the saved guard byte to Fac's, then goes to NormalizeBits::CheckCarry — reached from AlignAndAdd::Combine; placed after SetSign; see A-Q4 |
| 22 | `NORM2` | `Float::NormalizeBits` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the bit loop: adds 1 to the shift count and shifts Fac (and FacExtension) left one bit — entered at NormalizeBits::Test, not at its first byte; see A-Q4 |
| 23 | `NORM1` | `Float::NormalizeBits::Test` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | loops until Fac's top bit is set, then subtracts the count from FacExponent; underflow goes to SetZero — reached from Normalize::ShiftBytes; see A-Q4 |
| 24 | `SQUEEZ` | `Float::NormalizeBits::CheckCarry` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | a carry out of the addition (carry set) falls into ShiftInCarry; none returns — reached from AddMantissas; see A-Q4 |
| 25 | `RNDSHF` | `Float::ShiftInCarry` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | increments FacExponent and rotates the carry into the top of Fac and its extension; an exponent that wraps is OVERFLOW — Round::Increment jumps here |
| 26 | `RNDRTS` | `Float::ShiftInCarry::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the shared rts — reached from NormalizeBits::CheckCarry; see A-Q4 |
| 27 | `NEGFAC` | `Float::Complement` | routine | all | M6502, AS82 [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | flips FacSign and two's-complements the mantissa and extension; falls into ComplementMantissa — AS82 also names it |
| 28 | `NEGFCH` | `Float::ComplementMantissa` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | complements Fac's four mantissa bytes and FacExtension and adds one; falls into IncrementMantissa when the extension carries — ToLongInteger calls it |
| 29 | `INCFAC` | `Float::IncrementMantissa` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | adds one to Fac's mantissa, low byte first, carrying upward — Round::Increment calls it |
| 30 | `INCFRT` | `Float::IncrementMantissa::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the shared rts — reached from ComplementMantissa; see A-Q4 |
| 31 | `OVERR` | `Float::OverflowError` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; other names here: OVERFLOW (AS82) | aliases: OVERFLOW (AppleSoft) | loads OVERFLOW's error offset into X and jumps to the error handler — ShiftInCarry, ToOverflowError and AccumulateExponentDigit reach it |
| 32 | `MULSHF` | `Float::ShiftProductByte` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | sets X to the byte before Result1 and falls into ShiftRightByte, moving the product right a byte — MultiplyByte jumps here for a zero multiplier byte |
| 33 | `SHFTR2` | `Float::ShiftRightByte` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | moves the four bytes at X+1..X+4 down a byte, the low one into FacExtension, filling the top from Bits; falls into ShiftRight — ShiftRight branches back here for each whole byte |
| 34 | `SHIFTR` | `Float::ShiftRight` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | shifts the four bytes after X right by the negative count in A: whole bytes first, then bits, keeping the top byte's sign — ShiftAndAdd and ToLongInteger call it |
| 35 | `SHFTR3` | `Float::ShiftRight::NextBit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | copies the top byte's bit 7 into carry so the rotate keeps the sign |
| 36 | `SHFTR4` | `Float::ShiftRight::ShiftHigh` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | rotates the top byte right twice, the first to place the copied sign bit, the second to shift |
| 37 | `ROLSHF` | `Float::ShiftRight::ShiftLow` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | rotates the lower three bytes and A right with the caller's carry — reached from AlignAndAdd::Align and ToLongInteger::ShortShift; see A-Q4 |
| 38 | `SHFTR7` | `Float::ShiftRight::Count` | local | all | M6502 | no | counts one bit up toward zero and loops while bits remain — nothing references it; M6502 names it, so kept |
| 39 | `SHFTRT` | `Float::ShiftRight::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | clears carry and returns |

### MsBasic.ArithmeticCore

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 40 | `FLOAT_ARITHMETIC` | `FloatArithmetic` | macro | all |  | — | emits multiplication, unpacking into Arg, exponent combining, times ten, ten, divide by ten and division |
| 41 | `shortZeroBranch` | `KEEP` | parameter of FLOAT_ARITHMETIC | all |  | — | SDK's descriptive parameter: 1 branches straight from MultiplyArg's zero test to its rts — camelCase parameter, kept |
| 42 | `FMULT` | `Float::MultiplyPacked` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | unpacks Y:A into Arg (LoadArg), then falls into MultiplyArg: Fac = packed * Fac — Falls into MultiplyArg |
| 43 | `FMULTT` | `Float::MultiplyArg` | routine | all | M6502, ASTIL [AS], HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | no | Fac = Arg * Fac: combines exponents, then adds Arg into Result for each multiplier bit, low byte first, and normalizes — operator-table target for '*' |
| 44 | `MLTPLY` | `Float::MultiplyByte` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | for the multiplier byte in A: a zero byte shifts Result a whole byte; otherwise adds Arg per set bit, shifting Result right |
| 45 | `MLTPL1` | `Float::MultiplyByte::NonZero` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | skips the zero test: shifts A right and sets bit 7 as the marker that ends the bit loop — reached from MultiplyArg for the top byte; the module's comment says "the implicit high bit", but bit 7 here is the loop's end marker, see md |
| 46 | `MLTPL2` | `Float::MultiplyByte::NextBit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | carry set: adds Arg's mantissa to Result |
| 47 | `MLTPL3` | `Float::MultiplyByte::Shift` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | rotates Result and FacExtension right; loops until only the marker bit has gone |
| 48 | `MULTRT` | `Float::MultiplyByte::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the shared rts — reached from MultiplyArg when Fac is zero; see A-Q4 |
| 49 | `CONUPK` | `Float::LoadArg` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | unpacks the five bytes at Y:A into Arg, sets ResultSign to the signs' XOR; returns A = FacExponent with Z set if Fac is zero — ASTIL documents it (CONUPK) |
| 50 | `MULDIV` | `Float::CombineExponents` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | loads Arg's exponent into A and falls into AddExponent — Falls into AddExponent |
| 51 | `MLDEXP` | `Float::AddExponent` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | adds the biased exponent in A to FacExponent and takes ResultSign as FacSign; underflow drops the caller and gives zero, overflow is an error — Functions::Exp calls it to scale by a power of two |
| 52 | `TRYOFF` | `Float::AddExponent::NoCarry` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | no carry from the add: a sum under $80 underflows; otherwise rebiases and stores the exponent — reached also through the BIT-skip ($2C) from the overflow test |
| 53 | `MLDVEX` | `Float::ExponentOutOfRange` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | for Functions::Exp: a positive Fac is OVERFLOW, a negative one falls into Underflow |
| 54 | `ZEREMV` | `Float::Underflow` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | drops the caller's return address and sets Fac to zero, so the caller's caller gets zero — AddExponent branches here |
| 55 | `GOOVER` | `Float::ToOverflowError` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jumps on to OverflowError — only jumps on, so To plus the target; shared by AddExponent, ExponentOutOfRange, MultiplyByTen and DivideArg (not a local), see A-Q4 |
| 56 | `MUL10` | `Float::MultiplyByTen` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | copies Fac to Arg, then adds Arg to Fac with Arg's exponent raised by 2 and doubles: Fac * 10 — Falls into AddScaledArgAndDouble |
| 57 | `FINML6` | `Float::AddScaledArgAndDouble` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | with A = Arg's exponent: clears ResultSign, AlignAndAdd, then doubles Fac (exponent + 1); overflow is an error — Commodore's TI$ assignment calls it to multiply by six |
| 58 | `MUL10R` | `Float::AddScaledArgAndDouble::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the shared rts — reached from MultiplyByTen for a zero Fac; see A-Q4 |
| 59 | `TENZC` | `Float::Ten` | data | all | M6502 | no; alias TENC in Commodore | the packed constant 10 — Commodore's TENC alias, see row 2275 |
| 60 | `DIV10` | `Float::DivideByTen` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | copies Fac to Arg (rounded), points Y:A at Ten with a positive ResultSign, and falls into DivideArgByPacked — Falls into DivideArgByPacked |
| 61 | `FDIVF` | `Float::DivideArgByPacked` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores X as ResultSign, loads the packed divisor at Y:A into Fac, and divides: Fac = Arg / packed — Functions::Sin calls it with TwoPi |
| 62 | `FDIV` | `Float::DividePacked` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | unpacks Y:A into Arg (LoadArg), then falls into DivideArg: Fac = packed / Fac — Falls into DivideArg |
| 63 | `FDIVT` | `Float::DivideArg` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, ASTIL; spelling only: AS82 [AS]; other names here: FIDVT (ASTIL) | aliases: FIDVT (AppleSoft) | Fac = Arg / Fac: rounds the divisor, combines exponents, builds quotient bits by compare and subtract, normalizes; zero divisor is an error — operator-table target for '/'; ASTIL spells it FIDVT: keep both in Also, see A-Q1 |
| 64 | `DIVIDE` | `Float::DivideArg::Compare` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | compares Arg's mantissa with Fac's, top byte first |
| 65 | `SAVQUO` | `Float::DivideArg::SaveBit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | rotates the comparison's carry into the quotient byte; each full byte is stored in Result, the fifth goes to LastBits |
| 66 | `QSHFT` | `Float::DivideArg::TestSubtract` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | restores the comparison's flags: Arg >= Fac subtracts |
| 67 | `SHFARG` | `Float::DivideArg::ShiftDividend` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | shifts Arg left one bit and compares again (a carry out means it is larger) |
| 68 | `DIVSUB` | `Float::DivideArg::Subtract` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | subtracts Fac's mantissa from Arg's, then shifts |
| 69 | `LD100` | `Float::DivideArg::LastBits` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: K4S79 [P4 P4R], HVK4 [P4 P4R] | no | after four quotient bytes, sets A to $40 to collect two more bits |
| 70 | `DIVNRM` | `Float::DivideArg::Finish` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | moves the two extra bits to the top of FacExtension and normalizes the quotient (NormalizeResult) |
| 71 | `DV0ERR` | `Float::DivideArg::DivisionByZero` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | loads DIVISION BY ZERO's error offset into X and jumps to the error handler |

### MsBasic.ArrayMultiplication

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 72 | `UMULT` | `Variables::MultiplyByBound` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Saves Y in Pointer1, loads the big-endian bound at (SourceStart),Y into A:Addend and falls into Variables::MultiplyUnsigned — Called by CreateArray and ElementAddress only; see B2-Q2 (Variables scope) |
| 73 | `UMULTD` | `Variables::MultiplyUnsigned` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Multiplies LinearIndex by A:Addend in 16 shift-and-add steps; product in X (low) and A/Y (high); OUT OF MEMORY on overflow — Uses DigitsBeforePoint (DECCNT) as its bit counter: needs a scoped alias, see glossary list |
| 74 | `UMULTC` | `Variables::MultiplyUnsigned::NextBit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Doubles the partial product in X/Y and adds the multiplier when the bit shifted out of LinearIndex is set |
| 75 | `UMLCNT` | `Variables::MultiplyUnsigned::CountBit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Decrements the 16-bit counter and loops to NextBit |
| 76 | `UMLRTS` | `Variables::MultiplyUnsigned::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The routine's RTS; nothing branches here — Unreferenced but documented (M6502): kept as a local |

### MsBasic.Arrays

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 77 | `ARRAY_LOOKUP` | `ArrayLookup` | macro | all |  | — | Emits array subscript parsing, search, creation and element addressing (ISARY through DIMRTS) |
| 78 | `existingArrays` | `KEEP` | parameter of ARRAY_LOOKUP | all |  | — | 1 assembles Apple's existing-array (STORE/RECALL) search paths — SDK's own name; same parameter name in VariableSearch |
| 79 | `clearWithY` | `KEEP` | parameter of ARRAY_LOOKUP | all |  | — | 1 clears the array allocation counter with LDY/STY instead of LDA/TAY/STA — SDK's own name |
| 80 | `saveOffsetHigh` | `KEEP` | parameter of ARRAY_LOOKUP | all |  | — | 1 stores the final element offset's high byte in LinearIndex before scaling; 0 keeps BASIC 1's array bug — SDK's own name; see B2-Q9 (D5: weaker-contract variant) |
| 81 | `ISARY` | `Variables::FindArray` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stacks each subscript (via integer conversion) and the type flags, then searches the array table from ArraysStart for VariableName — Reached by FindVariable's JMP or by Variables::ChooseArrayLookup's fall-through |
| 82 | `INDLOP` | `Variables::FindArray::NextSubscript` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Evaluates one subscript and swaps it under the saved flags on the stack; loops while a comma follows |
| 83 | `INDLO1` | `Variables::FindArray::Search` | entry | AS | none found | — | Starts the table search at ArraysStart (AS: entered from Variables::ChooseArrayLookup to skip subscripts) — Entry used across macros by EXISTING_ARRAY_ENTRY |
| 84 | `LOPFDA` | `Variables::FindArray::CheckEnd` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Points SourceStart at the next array header and stops at ArraysEnd |
| 85 | `LOPFDV` | `Variables::FindArray::CompareName` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Compares the header's two name bytes with VariableName |
| 86 | `NMARY1` | `Variables::FindArray::NextArray` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Adds the header's length to SourceStart; on an address carry falls into BadSubscriptError — Falling into BAD SUBSCRIPT on a wrapped table address is odd but unreachable in practice |
| 87 | `BSERR` | `BadSubscriptError` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Loads the BAD SUBSCRIPT offset and skips into IllegalQuantityError's jump with a BIT — Falls into IllegalQuantityError; see B2-Q5 (error entries) |
| 88 | `FCERR` | `IllegalQuantityError` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Loads the ILLEGAL QUANTITY offset and jumps to the error handler — Called from many modules and both vendors; see B2-Q5 |
| 89 | `ERRGO3` | `IllegalQuantityError::ToError` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | JMP ERROR with X = the error offset; Variables::ArrayFound branches here with REDIM'D ARRAY — To + ERROR's new name (another part) |
| 90 | `GOTARY` | `Variables::ArrayFound` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Reports REDIM'D ARRAY when dimensioning; else checks the dimension count (BAD SUBSCRIPT) and jumps to ElementAddress — Reached by branch from FindArray; AS returns carry set for an existing-array lookup |
| 91 | `GOTAR1` | `Variables::ArrayFound::CheckDimensions` | local | AS | none found | — | (AS) Ordinary reference: sets ArrayPointer and compares the stacked dimension count with the header's |
| 92 | `GOTAR2` | `Variables::ArrayMissing` | routine | AS | none found | — | (AS) Array not found: an ordinary reference goes on to CreateArray, an existing-array lookup reports OUT OF DATA — Reached by branch from FindArray; separate .proc because it falls into CreateArray |
| 93 | `NOTFDD` | `Variables::CreateArray` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Writes a new array header (name, element size, bounds from DIM or 11), checks room, zeroes the values and sets the length — Returns at ElementAddress::Done for DIM, else falls into ElementAddress |
| 94 | `NOTFLT` | `Variables::CreateArray::CheckSecond` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Element size so far: 5, minus 1 if the first name byte has bit 7 set; now tests the second byte |
| 95 | `STOMLT` | `Variables::CreateArray::StoreSize` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Saves the element size (5, 3 or 2) in LinearIndex and writes the dimension count |
| 96 | `LOPPTA` | `Variables::CreateArray::NextDimension` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Takes the next bound: 11 by default, or the stacked DIM subscript plus one |
| 97 | `NOTDIM` | `Variables::CreateArray::StoreBound` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Writes the bound high byte first and multiplies it into the running size |
| 98 | `GREASE` | `Variables::CreateArray::CheckRoom` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Calls REASON for the new ArraysEnd and stores it, then clears the values page by page |
| 99 | `ZERITA` | `Variables::CreateArray::ClearLoop` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Zeroes the bytes of one page of values downward |
| 100 | `DECCUR` | `Variables::CreateArray::NextPage` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Moves ArrayPointer down a page and counts pages, then writes the header's length |
| 101 | `GETDEF` | `Variables::ElementAddress` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Checks each stacked subscript against its bound, forms the linear index, scales it by the element size and returns the element's address in VariablePointer and A/Y |
| 102 | `INLPNM` | `Variables::ElementAddress::NextSubscript` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Pops the next subscript into ArrayIndex and compares it with the bound, high byte first |
| 103 | `BSERR7` | `Variables::ElementAddress::ToBadSubscriptError` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | JMP BSERR for a subscript at or above its bound |
| 104 | `OMERR1` | `Variables::ElementAddress::ToOutOfMemoryError` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | JMP OMERR; CreateArray and MultiplyUnsigned branch here on overflow — Entered from other routines, so an entry; To + OMERR's new name (another part) |
| 105 | `INLPN2` | `Variables::ElementAddress::SkipLow` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | High byte below the bound: skips the bound's low byte |
| 106 | `INLPN1` | `Variables::ElementAddress::InBounds` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Multiplies the index so far by this dimension's bound and adds the subscript's low byte |
| 107 | `ADDIND` | `Variables::ElementAddress::AddSubscript` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Adds the subscript's high byte and counts down the dimensions |
| 108 | `NOTFL1` | `Variables::ElementAddress::CheckSecond` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Element size so far from the first name byte; now tests the second |
| 109 | `STOML1` | `Variables::ElementAddress::ScaleBySize` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Multiplies the linear index by the element size and adds ArrayPointer to give VariablePointer |
| 110 | `DIMRTS` | `Variables::ElementAddress::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The RTS; CreateArray (for DIM) and ERRDIR in UserFunctions branch here as the nearest RTS — ERRDIR (part B1) uses it as a borrowed RTS; see B2-Q6 |

### MsBasic.Assignment

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 111 | `ASSIGNMENT_START` | `AssignmentStart` | macro | all |  | — | Emits LET, the numeric store and the start of the string assignment (LET through INPCOM) |
| 112 | `LET` | `Statements::Let` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Finds the variable, requires '=', evaluates the expression, checks its type and stores it — Falls into StoreNumber; string results go through Statements::LetString |
| 113 | `COPNUM` | `Statements::Let::Number` | local | all | M6502 | no | Numeric result: pulls the saved IntegerType into A and falls into StoreNumber — Unreferenced but documented (M6502): kept |
| 114 | `QINTGR` | `StoreNumber` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stores FAC in the variable at AssignedVariable: rounded two-byte integer (high byte first) when A is negative, else packed float — Called by AssignVariableList; LET falls into it |
| 115 | `COPFLT` | `StoreNumber::ToPackFac` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | JMP MOVVF: packs FAC into the variable — To + MOVVF's new name (part A) |
| 116 | `COPSTR` | `Statements::LetString` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | LET's string path: drops the saved flag and falls into AssignString — Physically after StoreNumber, so its own .proc; see B2-Q7 |
| 117 | `INPCOM` | `AssignString` | routine | all | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | no | Assigns the string in FAC to the variable at AssignedVariable; the PET's TI$ check is assembled here before StoreString — In AS it has no code and shares StoreString's address |
| 118 | `STRING_ASSIGNMENT` | `StringAssignment` | macro | all |  | — | Emits StoreString, with the PET 4 status and linked-collector hooks |
| 119 | `statusCheck` | `KEEP` | parameter of STRING_ASSIGNMENT | all |  | — | 1 expands STRING_STATUS_CHECK (DS$ buffer forces a copy) — SDK's own name |
| 120 | `linkedCollector` | `KEEP` | parameter of STRING_ASSIGNMENT | all |  | — | 1 expands LINKED_STRING_STORE instead of the unlinked StoreDescriptor — SDK's own name |
| 121 | `GETSPT` | `StoreString` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Copies the characters into string space when they are already there but belong to another variable, then stores the descriptor at AssignedVariable — ASTIL entry; called by the PET's TI$ assignment |
| 122 | `QVARIA` | `StoreString::CheckDescriptor` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | String is in string space: copies it only if its descriptor lies at or above VariablesStart (a variable's) |
| 123 | `DNTCPY` | `StoreString::KeepCharacters` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Uses the source descriptor as it is and jumps to StoreDescriptor |
| 124 | `COPY` | `StoreString::CopyCharacters` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS], K4S79 [P4 P4R], HVK4 [P4 P4R] | no | Allocates the length, copies the characters with CopyString and stores NewDescriptor — Apple's COPY (Orchard) names StoreDescriptor, so it clashes in AS: prose; see B2-Q8 |
| 125 | `COPYZC` | `StoreDescriptor` | routine | AS P1 P1R P2 | M6502 | no; alias COPYC in Commodore | Releases the descriptor at Y:A if it is the latest temporary and copies its three bytes to AssignedVariable — P4's copy is in Commodore.StringAssignment (part F): same name; Commodore's COPYC alias |

### MsBasic.CharacterReader

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 126 | `LETTER_TEST` | `LetterTest` | macro | all |  | — | emits IsLetter once per build (x1) |
| 127 | `ISLETC` | `IsLetter` | routine | all | M6502, ASTIL [AS], AS82 [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | carry set for A..Z: cmp #'A', then two subtractions leave carry set only below '['; used by variable lookup and operand evaluation |
| 128 | `ISLRTS` | `IsLetter::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts below-'A' branches to — kept: documented (M6502, CBM4S79, HV*) |
| 129 | `CHARACTER_READER` | `CharacterReader` | macro | all |  | — | emits the page-zero reader's template and the seed bytes (x1) |
| 130 | `seedTail` | `KEEP` | parameter of CHARACTER_READER | all |  | — | the fifth seed byte ($58 or BASIC 1's $59); already descriptive camelCase |
| 131 | `INITAT` | `CharacterReaderTemplate` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the code startup copies to GetNextCharacter in page zero (lda CharacterReaderTemplate-1,x loop), with the four seed bytes after it — see B1-Q3; executed only as the page-zero copy |
| 132 | `CHZGOT` | `CharacterReaderTemplate::GetCurrent` | local | all | M6502; other names here: CHDGOT (HV1, HV1R, HV2, HV4, HV4R) | aliases: CHDGOT | the copy's GetCurrentCharacter: lda abs (operand becomes TextPointer), then classify — Also: CHDGOT (HV1, HV1R, HV2, HV4, HV4R) in the PET builds |
| 133 | `CHZRTS` | `CharacterReaderTemplate::Done` | local | all | M6502; other names here: CHDRTS (HV1, HV1R, HV2, HV4, HV4R) | aliases: CHDRTS | the rts the colon-or-above test branches to; the seed bytes follow — Also: CHDRTS (HV*) in the PET builds; QNUM/CHRRTS equates: see B1-Q3 |

### MsBasic.CommandCore

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 134 | `BASIC_ERROR_FINISH` | `ErrorFinish` | macro | all |  | — | emits the tail of the error report: reset, " ERROR", message and line (x1) — dropped the redundant BASIC_ prefix |
| 135 | `TYPERR` | `ReportError::AddErrorSuffix` | local | all | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | no | the error loop falls here: ResetStack, then A/Y = the " ERROR" text, falls into ReportMessage — kept unreferenced: documented; ReportError is part C's ERROR (name to align); BasicSharedCommandInputTests looks up TYPERR |
| 136 | `ERRFIN` | `ReportMessage` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | prints the message at A/Y, then " IN" and the line unless CurrentLine+1 is $FF (direct), falls into the vendor's READY — reached by StopOrEnd's BREAK path, so its own proc |
| 137 | `BASIC_DELETE_OLD_LINE` | `DeleteOldLine` | macro | all |  | — | emits the numbered-line path: read number, tokenize, find, close the old line's gap (x1) |
| 138 | `source` | `KEEP` | parameter of BASIC_DELETE_OLD_LINE | all |  | — | the page-zero pointer the move reads through (Pointer1); already descriptive |
| 139 | `MAIN1` | `CommandLoop::EditLine` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | numbered input: ReadLineNumber, Tokenize, FindLine; an exact match is removed by moving the rest of the program down — CommandLoop is part C's MAIN (name to align) |
| 140 | `QDECT1` | `CommandLoop::SetMoveSource` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | both borrow paths join here to add the low offset into the move's source pointer |
| 141 | `MLOOP` | `CommandLoop::MoveDown` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | copies (source),y to (Pointer2),y a page at a time, X pages, closing the gap |
| 142 | `BASIC_LINK_LINE` | `LinkLine` | macro | all |  | — | emits LinkProgram's per-line scan and link store (x1) |
| 143 | `addHighToY` | `KEEP` | parameter of BASIC_LINK_LINE | all |  | — | selects the BASIC 4 high-byte addition; already descriptive |
| 144 | `CZLOOP` | `LinkProgram::ScanLine` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | from offset 5, steps Y to the line's zero byte, then stores the next line's address in the link — not FindLineEnd: that is REMN's top-level name; LinkProgram is part C's LNKPRG |
| 145 | `BASIC_TOKEN_STORE` | `TokenStore` | macro | all |  | — | emits the tokenizer's store and literal-copy paths (x1) |
| 146 | `inputBase` | `KEEP` | parameter of BASIC_TOKEN_STORE | all |  | — | the indexed input base (InputBuffer or the PET's BUFOFS); already descriptive |
| 147 | `foldCase` | `KEEP` | parameter of BASIC_TOKEN_STORE | all |  | — | 1 calls the Enhanced IIe's case folder (ENHNCD); already descriptive |
| 148 | `GETBPT` | `Tokenize::StoreToken` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | reloads Y from TokenizePointer before storing the token in A; the keyword matcher's exit — Tokenize is part C's CRUNCH (name to align) |
| 149 | `STUFFH` | `Tokenize::StoreByte` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores A at the output position (InputBuffer-5,y), ends at zero, sets TokenizeState after a colon or DATA, starts REM copying |
| 150 | `COLIS` | `Tokenize::SetTokenizeState` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores the colon (0) or DATA (nonzero) difference in TokenizeState |
| 151 | `NODATT` | `Tokenize::CheckRem` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | not REM: back to the keyword loop; REM: EndDelimiter = 0, copy the rest of the line |
| 152 | `STR1` | `Tokenize::CopyLiteral` | local | all | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | no | reads the next input character (or folds case), stops at zero or EndDelimiter |
| 153 | `STRNG` | `Tokenize::StoreLiteral` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | stores the literal character and continues copying; the vendor tokenizer enters here at a quote |

### MsBasic.ConversionCore

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 154 | `SIGN_INTEGER_ROUTINES` | `SignAndIntegerRoutines` | macro | all |  | — | emits the sign tests, the integer-to-float conversions, ABS, the comparison and the conversions to integer — SIGN_INTEGER_ROUTINES in full words |
| 155 | `SIGN` | `Float::GetSign` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | returns A = 0 for a zero Fac, else $FF for negative and 1 for positive — ASTIL (SIGN); For, Functions::Log and Functions::Rnd call it |
| 156 | `FCSIGN` | `Float::GetSign::FromSignByte` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | takes the sign from FacSign without testing the exponent — reached from CompareAtPointer2; see A-Q4 |
| 157 | `FCOMPS` | `Float::GetSign::FromBit7` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | returns $FF if bit 7 of A is set, else 1 — reached from CompareAtPointer2::ToSignFromBit7; see A-Q4 |
| 158 | `SIGNRT` | `Float::GetSign::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the shared rts |
| 159 | `SGN` | `Functions::Sgn` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | SGN: GetSign, then falls into Float::ConvertSignedByte — Falls into Float::ConvertSignedByte; see A-Q3 |
| 160 | `FLOAT` | `Float::ConvertSignedByte` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | makes the signed byte in A a number in Fac (exponent $88), through ConvertSignedWord — ASTIL (FLOAT); Relational and Commodore's TI path call it |
| 161 | `FLOATS` | `Float::ConvertSignedWord` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | with FacMantissa1:2 a signed word and X the exponent: sets carry from its sign and falls into ConvertWord — ReturnSignedWord jumps here |
| 162 | `FLOATC` | `Float::ConvertWord` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | clears FacMantissa3:4 and falls into ConvertMantissa; carry clear means the word is negative — PrintDecimalAX calls it with carry set (unsigned) |
| 163 | `FLOATB` | `Float::ConvertMantissa` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores X as FacExponent and A as FacExtension and FacSign, then normalizes (NormalizeSigned) — Commodore's TI path calls it |
| 164 | `ABS` | `Functions::Abs` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | ABS: clears FacSign's bit 7 — see A-Q3 |
| 165 | `FCOMP` | `Float::Compare` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | compares Fac with the packed number at Y:A: A = 1 if Fac is larger, 0 if equal, $FF if smaller — ASTIL (FCOMP); FacToInteger, FormatFac, RaiseArg and ApplyRelation call it; falls into CompareAtPointer2 |
| 166 | `FCOMPN` | `Float::CompareAtPointer2` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | as Compare, with the operand's low byte already in Pointer2 and its high byte in Y — NEXT calls it |
| 167 | `FOUTCP` | `Float::CompareAtPointer2::SameSign` | local | all | M6502 | no | signs agree: compares exponents, then mantissa bytes, the last against FacMantissa4 and FacExtension's bit 7 — nothing references it; M6502 names it, so kept |
| 168 | `FCOMPC` | `Float::CompareAtPointer2::Unequal` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | turns the carry of the unequal byte and FacSign into the order: inverts FacSign when Fac is larger |
| 169 | `FCOMPD` | `Float::CompareAtPointer2::ToSignFromBit7` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jumps on to GetSign::FromBit7 — only jumps on: To plus the target |
| 170 | `QINT` | `Float::ToLongInteger` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | shifts Fac's mantissa into a signed four-byte integer (rounded down) in FacMantissa1..4; exponent and sign bytes are left — ASTIL (QINT); FormatFac, FacToInteger, MemoryAccess and Commodore's TI path call it |
| 171 | `QISHFT` | `Float::ToLongInteger::Shift` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | a long shift goes through ShiftRight, then restores Bits from Y |
| 172 | `QINTRT` | `Float::ToLongInteger::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the shared rts — reached from CompareAtPointer2 for equal numbers; see A-Q4 |
| 173 | `QINT1` | `Float::ToLongInteger::ShortShift` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | fewer than eight bits: puts FacSign's bit back in the top byte and shifts through ShiftRight::ShiftLow |
| 174 | `INT` | `Functions::Int` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | INT: unless already whole (exponent $A0 or more), ToLongInteger then normalizes back; leaves the low byte in SmallInteger — RaiseArg, Functions::Exp and Functions::Sin call it; see A-Q3 |
| 175 | `CLRFAC` | `Float::ClearMantissa` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | clears Fac's mantissa and Y (ToLongInteger's case for a zero exponent) — placed after Functions::Int; reached from ToLongInteger |
| 176 | `INTRTS` | `Float::ClearMantissa::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the shared rts — reached from Functions::Int for an already-whole Fac; see A-Q4 |

### MsBasic.DecimalInputCore

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 177 | `DECIMAL_INPUT` | `DecimalInput` | macro | all |  | — | emits ReadNumber, AddSignedByte and AccumulateExponentDigit |
| 178 | `limitAt120` | `KEEP` | parameter of DECIMAL_INPUT | all |  | — | SDK's descriptive parameter: 1 for the earlier exponent limit (12 rather than 10) — camelCase, kept; its name reads oddly next to the code's 12, see md |
| 179 | `FIN` | `Float::ReadNumber` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | reads a decimal number, with sign, point and E exponent, from the text at TextPointer into Fac — ASTIL (FIN); operand evaluation, VAL and INPUT call it; name as DOS's Scanner::ReadNumber |
| 180 | `FINZLP` | `Float::ReadNumber::ClearLoop` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | zeroes the eleven work bytes from DigitsBeforePoint up without touching carry |
| 181 | `QPLUS` | `Float::ReadNumber::CheckPlus` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | skips a leading plus sign |
| 182 | `FINC` | `Float::ReadNumber::NextCharacter` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | reads the next character (GetNextCharacter) |
| 183 | `FINDGQ` | `Float::ReadNumber::TestDigit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | a digit (carry clear) goes to Digit |
| 184 | `FIN1` | `Float::ReadNumber::CheckPoint` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | tests for '.' and 'E'; after E reads the exponent's sign, as a character or a sign token |
| 185 | `FINEC1` | `Float::ReadNumber::NegativeExponent` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | sets ExponentSign's bit 7 for a minus sign after E |
| 186 | `FINEC` | `Float::ReadNumber::NextExponentCharacter` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | reads the next exponent character — reached from AccumulateExponentDigit; see A-Q4 |
| 187 | `FNEDG1` | `Float::ReadNumber::TestExponentDigit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | a digit goes to AccumulateExponentDigit |
| 188 | `FINEC2` | `Float::ReadNumber::ExponentDone` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | negates DecimalExponent if ExponentSign is set, then scales |
| 189 | `FINDP` | `Float::ReadNumber::DecimalPoint` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | rotates carry into DecimalPointSeen; a second point (bit 6 then set) ends the number |
| 190 | `FINE` | `Float::ReadNumber::EndOfNumber` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | loads DecimalExponent to scale |
| 191 | `FINE1` | `Float::ReadNumber::AdjustExponent` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | subtracts the digits counted after the point from DecimalExponent and picks the scaling loop — the count is in DECCNT's byte: see the glossary point in md |
| 192 | `FINDIV` | `Float::ReadNumber::DivideLoop` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | DivideByTen until DecimalExponent is zero |
| 193 | `FINMUL` | `Float::ReadNumber::MultiplyLoop` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | MultiplyByTen until DecimalExponent is zero |
| 194 | `FINQNG` | `Float::ReadNumber::ApplySign` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | negates the result if InputSign is negative |
| 195 | `NEGXQS` | `Float::ReadNumber::ToNegate` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jumps on to Negate — only jumps on: To plus the target |
| 196 | `FINDIG` | `Float::ReadNumber::Digit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; other names here: INSRTDIG (AS82) | aliases: INSRTDIG (AppleSoft) | counts a digit after the point, then multiplies Fac by ten |
| 197 | `FINDG1` | `Float::ReadNumber::AddDigit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | MultiplyByTen, then adds the digit's value (AddSignedByte) |
| 198 | `FINLOG` | `Float::AddSignedByte` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | copies Fac to Arg, makes the signed byte in A a number, and adds Arg: Fac = Fac + A — Functions::Log and Commodore's TI$ assignment call it |
| 199 | `FINEDG` | `Float::AccumulateExponentDigit` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | DecimalExponent = DecimalExponent * 10 + digit, with the build's limit: a positive overflow is OVERFLOW — placed after AddSignedByte; reached from ReadNumber, returns to ReadNumber::NextExponentCharacter |
| 200 | `MLEXMI` | `Float::AccumulateExponentDigit::ClampNegative` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | negative exponent over the limit: earlier build continues with 11, later build stores 100 — one name for both variants' definitions (lines 151 and 175), each clamps a negative exponent |
| 201 | `MLEX10` | `Float::AccumulateExponentDigit::TimesTen` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | computes A * 10 + the digit at TextPointer |

### MsBasic.Dim

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 202 | `DIM3` | `Statements::DimNextArray` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Requires the comma between arrays and falls into Statements::Dim — Before the handler's entry, so its own .proc; see B2-Q7 |
| 203 | `DIM` | `Statements::Dim` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | For each array, calls FindVariable::WithDimensionFlag with the DIM flag set, looping while a comma follows |
| 204 | `DIM1` | `Statements::Dim::DefineArray` | local | all | M6502 | no | Calls FindVariable::WithDimensionFlag, which creates the array — Unreferenced but documented (M6502): kept |
| 205 | `DIMCON` | `Statements::Dim::CheckMore` | local | all | M6502 | no | Rereads the current character; a non-terminator goes back to DimNextArray — Unreferenced but documented (M6502): kept |

### MsBasic.ExpressionCore

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 206 | `EXPRESSION_CORE` | `ExpressionCore` | macro | all |  | — | Emits the precedence evaluator and its operand stack routines (FRMEVL through UNPRTS) |
| 207 | `carryReturn` | `KEEP` | parameter of EXPRESSION_CORE | all |  | — | 1 carries PushSignedFac's return-address increment into the high byte — SDK's own name |
| 208 | `FRMEVL` | `EvaluateExpression` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R]; spelling only: AS82 [AS] | no | Evaluates an expression with precedence, stacking pending operations; FAC and ValueType hold the result — ASTIL entry; one .proc because the push helpers sit inside its loop, see B2-Q3 |
| 209 | `FRMEV1` | `EvaluateExpression::BackUpLow` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Decrements TextPointer's low byte so the first operand's character is reread; starts with precedence 0 |
| 210 | `LPOPER` | `EvaluateExpression::NextOperand` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Pushes the precedence and mask, checks stack room and evaluates the next operand |
| 211 | `TSTOP` | `EvaluateExpression::NextOperator` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: K4S79 [P4 P4R], HVK4 [P4 P4R] | no | Rereads the character after an operand; Strings::Concatenate jumps back here |
| 212 | `LOPREL` | `EvaluateExpression::NextRelation` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Accumulates <, = and > into OperatorMask; SYNTAX on a repeated relation |
| 213 | `ENDREL` | `EvaluateExpression::EndRelations` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | No more relations: finishes a relation, ends without an operator, or picks the arithmetic operator (+ on strings jumps to Concatenate) |
| 214 | `QPREC` | `EvaluateExpression::ComparePrecedence` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Compares the pending precedence with the new operator's in OperatorTable |
| 215 | `DOPREC` | `EvaluateExpression::DeferOperator` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The new operator binds tighter: keeps the pending precedence on the stack |
| 216 | `NEGPRC` | `EvaluateExpression::Prefix` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Pushes the operation at Y and evaluates its operand; ApplyPrefixOperator jumps here for unary minus and NOT |
| 217 | `FINREL` | `EvaluateExpression::FinishRelation` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Combines the relation mask with the operand type and backs up TextPointer |
| 218 | `FINRE2` | `EvaluateExpression::RelationBackUpLow` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Decrements TextPointer's low byte and selects the relational operator's table entry |
| 219 | `QPREC1` | `EvaluateExpression::CompareAfterPrefix` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | After a prefix operation: compares precedence with the operator at OperatorPointer |
| 220 | `DOPRE1` | `EvaluateExpression::PushOperation` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Pushes the operator's dispatch address and FAC with its precedence, then evaluates the next operand |
| 221 | `SNERR5` | `EvaluateExpression::ToSyntaxError` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | JMP SNERR |
| 222 | `PUSHF1` | `EvaluateExpression::PushOperand` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Loads FAC's sign and the operator's precedence and falls into PushSignedFac — Called only by PushOperation |
| 223 | `PUSHF` | `EvaluateExpression::PushSignedFac` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Pops its return address into Pointer1, pushes A (the sign) and the rounded FAC, and jumps back — Called by FOR; see B2-Q3 |
| 224 | `FORPSH` | `EvaluateExpression::PushFac` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Rounds FAC, pushes its five bytes and jumps through Pointer1 — Called by FOR; see B2-Q3 |
| 225 | `QOP` | `EvaluateExpression::NoOperator` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | End of the expression: Y = $FF and pulls the pending precedence |
| 226 | `QOPGO` | `EvaluateExpression::CheckDone` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Precedence 0 means no pending operation: returns the result |
| 227 | `QCHNUM` | `EvaluateExpression::CheckOperands` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Relational precedence ($64) skips the numeric check; others require a number |
| 228 | `UNPSTK` | `EvaluateExpression::SaveOperator` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Saves Y in OperatorPointer |
| 229 | `PULSTK` | `EvaluateExpression::PopOperand` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Pulls the mask into RelationMask and the stacked operand into Arg, setting ResultSign |
| 230 | `QOPRTS` | `EvaluateExpression::Finish` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Loads FacExponent (sets the flags) before the RTS that dispatches to the operator or returns |
| 231 | `UNPRTS` | `EvaluateExpression::Return` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The RTS: returns into the operator routine whose address was pushed, or to the caller — Unreferenced but documented (M6502): kept |

### MsBasic.FloatConstants

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 232 | `FLOAT_ONE` | `FloatOne` | macro | all |  | — | emits the packed constant 1 — expanded three times; defines no label |
| 233 | `LOG_CONSTANTS` | `LogarithmConstants` | macro | all |  | — | emits One, LogPolynomial, SquareRootOfHalf, SquareRootOfTwo, MinusHalf and LogOfTwo — LOG_CONSTANTS in full words |
| 234 | `FONE` | `Float::One` | data | all | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R]; spelling only: AS82 [AS] | no | the packed constant 1 — For and Functions::Atn use it |
| 235 | `LOGCN2` | `Float::LogPolynomial` | table | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; other names here: LOGSER (AS82) | aliases: LOGSER (AppleSoft) | degree 3 and four packed coefficients for Functions::Log |
| 236 | `SQRHLF` | `Float::SquareRootOfHalf` | data | all | M6502 | no; alias SQR05 in Commodore | the packed square root of 1/2 — Commodore's SQR05 alias, row 2273 |
| 237 | `SQRTWO` | `Float::SquareRootOfTwo` | data | all | M6502 | no; alias SQR20 in Commodore | the packed square root of 2 — Commodore's SQR20 alias, row 2274 |
| 238 | `NEGHLF` | `Float::MinusHalf` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the packed constant -1/2 |
| 239 | `LOG2` | `Float::LogOfTwo` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the packed natural logarithm of 2 |
| 240 | `OUTPUT_CONSTANTS` | `OutputConstants` | macro | all |  | — | emits FormatFac's scaling limits and the constant one billion |
| 241 | `preciseUpper` | `KEEP` | parameter of OUTPUT_CONSTANTS | all |  | — | SDK's descriptive parameter: selects the upper limit's last byte |
| 242 | `NZ0999` | `Float::LowerOutputLimit` | data | all | M6502 | no; alias N0999 in Commodore | the packed 99,999,999.9: FormatFac multiplies by ten while Fac is below it — Commodore's N0999 alias, row 2276 |
| 243 | `NZ9999` | `Float::UpperOutputLimit` | data | all | M6502 | no; alias N9999 in Commodore | the packed 999,999,999.x (by build): FormatFac divides by ten while Fac is above it — Commodore's N9999 alias, row 2277 |
| 244 | `NZMIL` | `Float::Billion` | data | all | M6502; other names here: BILLION (AS82) | no; alias NMIL in Commodore; aliases: BILLION (AppleSoft) | the packed 1,000,000,000: FormatFac multiplies a Fac below 1 by it — Commodore's NMIL alias, row 2278 |
| 245 | `OUTPUT_TABLES` | `OutputTables` | macro | all |  | — | emits Half, ZeroValue (by build), PowersOfTen and the TI$ divisors (by build) |
| 246 | `defineZero` | `KEEP` | parameter of OUTPUT_TABLES | all |  | — | SDK's descriptive parameter: 1 defines ZeroValue inside Half |
| 247 | `includeTime` | `KEEP` | parameter of OUTPUT_TABLES | all |  | — | SDK's descriptive parameter: 1 adds the TI$ divisors — same name as DecimalOutput's parameter (row 455) |
| 248 | `FHALF` | `Float::Half` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | the packed constant 1/2 — Basic1, AddHalf and Functions::Sqr use it |
| 249 | `ZERO` | `ZeroValue` | data | AS P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R; spelling only: AS82 [AS] | no | three zero bytes in Half's mantissa: the value variable lookup returns for a variable not yet created — same job as B2's row 860 (P1's ZERO in VariableLookup): same name there; top level needs the label outside Float, see A-Q7 |
| 250 | `FOUTBL` | `Float::PowersOfTen` | table | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | nine signed four-byte powers of ten, alternating sign, that FormatFac adds to extract digits — Commodore's TI$ output uses it |
| 251 | `FDCEND` | `Float::PowersOfTenEnd` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the byte after PowersOfTen (where the TI$ divisors begin in PET builds) — End = the byte after, as DOS's X5 |
| 252 | `TIMEND` | `Float::TimeDivisorsEnd` | data | PET | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | no | the byte after the six alternating TI$ divisors that follow PowersOfTen — PET builds only; the divisors themselves have no label |
| 253 | `EXP_CONSTANTS` | `ExponentialConstants` | macro | all |  | — | emits LogBase2OfE and ExponentialPolynomial — EXP_CONSTANTS in full words |
| 254 | `LOGEB2` | `Float::LogBase2OfE` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the packed log base 2 of e |
| 255 | `EXPCON` | `Float::ExponentialPolynomial` | table | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | degree 7 and eight packed coefficients for Functions::Exp |
| 256 | `SIN_CONSTANTS` | `SineConstants` | macro | all |  | — | emits HalfPi, TwoPi, Quarter and SinePolynomial — SIN_CONSTANTS in full words |
| 257 | `PI2` | `Float::HalfPi` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the packed pi/2 — Functions::Cos and Functions::Atn use it |
| 258 | `TWOPI` | `Float::TwoPi` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the packed 2*pi |
| 259 | `FR4` | `Float::Quarter` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the packed 1/4 |
| 260 | `SINCON` | `Float::SinePolynomial` | table | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | degree 5 and six packed coefficients for the odd polynomial of Functions::Sin |
| 261 | `ATN_CONSTANTS` | `ArctangentConstants` | macro | all |  | — | emits ArctangentPolynomial — ATN_CONSTANTS in full words |
| 262 | `ATNCON` | `Float::ArctangentPolynomial` | table | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | degree 11 and twelve packed coefficients for the odd polynomial of Functions::Atn |

### MsBasic.FloatingPoint

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 263 | `ZSTORD` | `DROP` | alias | AS | M6502 | no | AppleSoft's equate making the WAIT macro's omitted-mask target the plain wait (STORDO) — AppleSoft can pass B1's new name for STORDO directly; Microsoft's ZSTORDO (six-character ZSTORD) goes in prose; see A-Q6 |

### MsBasic.For

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 264 | `FOR` | `Statements::For` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS], AS82 [AS] | no | LET assigns the start value; FindForFrame removes an older frame for the same variable; builds an 18-byte ForFrame — see B1-Q2 (ForFrame struct) |
| 265 | `NOTOL` | `Statements::For::BuildFrame` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | drops the statement loop's return, CheckStack(9), pushes the text after the statement and CurrentLine, evaluates TO's limit |
| 266 | `LDFONE` | `Statements::For::ReadStep` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | its address is the continuation the limit's push (FORPSH) jumps to: loads 1.0, or evaluates the STEP expression — address taken via Pointer1 |
| 267 | `ONEON` | `Statements::For::PushStep` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | pushes the step (PUSHF), its sign (SIGN) and AssignedVariable |
| 268 | `NXTCON` | `Statements::For::PushToken` | local | all | M6502 | no | pushes TOKEN_FOR to complete the frame; falls into the vendor's statement loop — kept unreferenced: documented (M6502) |

### MsBasic.IntegerConversion

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 269 | `INTEGER_CONVERSION_BOUNDARY` | `IntegerConversionBoundary` | macro | all |  | — | emits MinimumInteger's four bytes |
| 270 | `N32768` | `MinimumInteger` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | four bytes of the packed -32768; FacToInteger's compare takes EvaluateSubscript's JSR opcode ($20) as the fifth — documented quirk, not a bug to fix: exact -32768 with a zero guard compares unequal |
| 271 | `INTEGER_CONVERSION` | `IntegerConversion` | macro | all |  | — | emits EvaluateSubscript, FacToNonnegativeInteger and FacToInteger |
| 272 | `evaluateEntry` | `KEEP` | parameter of INTEGER_CONVERSION | all |  | — | SDK's descriptive parameter: the evaluator EvaluateSubscript calls |
| 273 | `checkType` | `KEEP` | parameter of INTEGER_CONVERSION | all |  | — | SDK's descriptive parameter: 1 adds the numeric-type check |
| 274 | `INTIDX` | `EvaluateSubscript` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | reads the next character, evaluates an expression and falls into FacToNonnegativeInteger — Arrays calls it; Falls into FacToNonnegativeInteger |
| 275 | `POSINT` | `FacToNonnegativeInteger` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | optionally checks the type, rejects a set sign bit (ILLEGAL QUANTITY), then falls into FacToInteger — StringFunctions and Basic1 call it |
| 276 | `AYINT` | `FacToInteger` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | makes Fac a signed 16-bit integer in FacMantissa3:4; outside -32768..32767 is ILLEGAL QUANTITY — ASTIL (AYINT) |
| 277 | `NONONO` | `FacToInteger::FailUnlessEqual` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | a nonzero result (Compare unequal, or FacSign negative) goes to ILLEGAL QUANTITY — reached from FacToNonnegativeInteger; see A-Q4 |
| 278 | `QINTGO` | `FacToInteger::ToLongInteger` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jumps on to Float::ToLongInteger — only jumps on: To plus the target; reads as Float's name under a .using Float, see md |

### MsBasic.LineNumber

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 279 | `LINGET` | `ReadLineNumber` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | accumulates decimal digits into LineNumber (x10 by shifts and adds); a high byte of $19 or more before a digit is an error — bug, see B1-Q6: the overflow branch enters On::RequireGoto |
| 280 | `MORLIN` | `ReadLineNumber::NextDigit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | a non-digit exits through Statements::On::Done; otherwise multiplies by 10 and adds the digit |
| 281 | `NXTLGC` | `ReadLineNumber::NextCharacter` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | GetNextCharacter and loop |

### MsBasic.LineSearch

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 282 | `FNDLIN` | `FindLine` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | walks the links from ProgramStart until a line number >= LineNumber; SourceStart = that line, carry set on an exact match |
| 283 | `FNDLNC` | `FindLine::FromAddress` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | starts the walk at the line A (low) / X (high); GoTo enters here for a forward search |
| 284 | `FNDLO1` | `FindLine::CompareLow` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | high bytes equal: compares the low bytes |
| 285 | `AFFRTS` | `FindLine::NextLine` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | loads the link into A/X and loops |
| 286 | `FLINRT` | `FindLine::NotFound` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | zero link (end of program): clears carry |
| 287 | `FLNRTS` | `FindLine::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts; Statements::New and List's range parsing branch here for a syntax error return — shared exit: see B1-Q1 |

### MsBasic.Lister

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 288 | `LIST_RANGE` | `ListRange` | macro | all |  | — | emits LIST's bound parsing (x1) |
| 289 | `commaRange` | `KEEP` | parameter of LIST_RANGE | all |  | — | AppleSoft's comma between bounds; already descriptive |
| 290 | `secondBoundReturn` | `KEEP` | parameter of LIST_RANGE | all |  | — | where trailing text after the second bound returns; already descriptive |
| 291 | `LIST` | `Statements::List` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS], AS82 [AS] | no | parses [first][-[last]], finds the first line, lists through the bound; one proc over ListRange, ListLines, ListNextTableByte and ListTokens — see B1-Q4: no label inside is reached from outside the native sources |
| 292 | `GOLST` | `Statements::List::ReadFirstBound` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | ReadLineNumber, FindLine, then checks for the end, minus (or comma) |
| 293 | `GOLST1` | `Statements::List::ReadSecondBound` | local | AS | none found | — | AppleSoft: after minus or comma, reads the upper bound — SDK's own (no document): no Also |
| 294 | `LSTEND` | `Statements::List::StartListing` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | drops the statement loop's return; a zero upper bound becomes $FFFF; falls into NextLine |
| 295 | `LIST_LINES` | `ListLines` | macro | all |  | — | emits the line walker (x1; AppleSoft chooses one of two expansions by ENHNCD) |
| 296 | `trackQuotes` | `KEEP` | parameter of LIST_LINES | all |  | — | quote tracking through TokenizeState; already descriptive |
| 297 | `guardOffset` | `KEEP` | parameter of LIST_LINES | all |  | — | stop when the line offset wraps; already descriptive |
| 298 | `columnMode` | `KEEP` | parameter of LIST_LINES | all |  | — | 0, 1 or 2: no wrap, fixed column, CHKCOL; already descriptive |
| 299 | `linePrinter` | `KEEP` | parameter of LIST_LINES | all |  | — | the line-number printer (LINPRT or SPCLIN); already descriptive |
| 300 | `finalCr` | `KEEP` | parameter of LIST_LINES | all |  | — | output a carriage return before resuming; already descriptive |
| 301 | `resume` | `KEEP` | parameter of LIST_LINES | all |  | — | where the listing ends (READY or NXTCO1); already descriptive |
| 302 | `LIST4` | `Statements::List::NextLine` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: K4S79 [P4 P4R], HVK4 [P4 P4R] | no | zero link high byte ends; checks Control-C, new line, compares the line number with the bound |
| 303 | `TSTDUN` | `Statements::List::CheckPastEnd` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | carry set (line above the bound) finishes |
| 304 | `TYPLIN` | `Statements::List::ListLine` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | saves the offset in ListString, prints the line number, then a space |
| 305 | `PRIT4` | `Statements::List::ResumeLine` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | reloads the line offset, clears bit 7 of A, falls into ListCharacter |
| 306 | `PLOOP` | `Statements::List::ListCharacter` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | outputs A; with columnMode wraps at the column and indents to 5 — not PrintCharacter: avoids a likely top-level output name |
| 307 | `LIST_QUOTE_CHECK` | `Statements::List::CheckQuote` | local | none | none found | — | restores the character saved around the wrap check, then the quote test — SDK's own; no build assembles it (no build combines trackQuotes and columnMode) |
| 308 | `PLOOP1` | `Statements::List::NextByte` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | next byte: nonzero to CheckToken; zero follows the link to the next line |
| 309 | `GRODY` | `Statements::List::Finish` | local | all | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | no | optional carriage return, then jmp to the resume entry |
| 310 | `LIST_TABLE_NEXT` | `ListNextTableByte` | macro | AS |  | — | emits AppleSoft's page-carrying keyword-table reader (x1) |
| 311 | `GRODY1` | `Statements::List::NextTableByte` | local | AS | none found | — | subroutine: iny, carrying into the pointer's high byte (FacMantissa1), then reads (Fac),y — called by jsr within List |
| 312 | `GRODY2` | `Statements::List::ReadTableByte` | local | AS | none found | — | lda (Fac),y; rts |
| 313 | `LIST_TOKENS` | `ListTokens` | macro | all |  | — | emits the character and keyword expansion (x1) |
| 314 | `tableMode` | `KEEP` | parameter of LIST_TOKENS | all |  | — | 0, 1 or 2: indexed, Pointer1, or Fac table walk; already descriptive |
| 315 | `trackQuotes` | `KEEP` | parameter of LIST_TOKENS | all |  | — | print high-bit bytes inside quotes literally; already descriptive |
| 316 | `literalPi` | `KEEP` | parameter of LIST_TOKENS | all |  | — | print the PI byte literally; already descriptive |
| 317 | `spaceWords` | `KEEP` | parameter of LIST_TOKENS | all |  | — | spaces around each keyword (AppleSoft); already descriptive |
| 318 | `QPLOP` | `Statements::List::CheckToken` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | bit 7 clear (or PI, or inside quotes): an ordinary character; else counts down to the token's keyword |
| 319 | `RESRCH` | `Statements::List::FindWord` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | dex per keyword; reaching the token's count prints that word |
| 320 | `RESCR1` | `Statements::List::SkipWord` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | reads table bytes until one with bit 7 set (a word's last byte) |
| 321 | `RESCR2` | `Statements::List::ReadWordByte` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | BASIC 4: reads (Pointer1),y after advancing the pointer |
| 322 | `PRIT3` | `Statements::List::ListWord` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | prints the keyword's bytes up to the one with bit 7 set |
| 323 | `PRIT3B` | `Statements::List::ListFirstWord` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | BASIC 4: the first token ($80) skips the search |
| 324 | `PRIT31` | `Statements::List::ListWordCharacter` | local | AS | none found | — | AppleSoft: reads and prints the next keyword byte — SDK's own: no Also |
| 325 | `PRIT32` | `Statements::List::ListLastCharacter` | local | AS | none found | — | AppleSoft: prints the last keyword byte and a space, back to ResumeLine — SDK's own: no Also |

### MsBasic.Logarithm

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 326 | `LOG_ROUTINE` | `LogarithmRoutine` | macro | all |  | — | emits Functions::Log, which ends by falling into MultiplyPacked — LOG_ROUTINE in full words |
| 327 | `LOG` | `Functions::Log` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | LOG: reduces Fac to [0.5,1), evaluates LogPolynomial, adds the binary exponent and multiplies by LogOfTwo — RaiseArg calls it; Falls into Float::MultiplyPacked; see A-Q3 |
| 328 | `LOGERR` | `Functions::Log::ToIllegalQuantity` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jumps on to the ILLEGAL QUANTITY error for zero or a negative argument — To plus FCERR's new name (other part): adjust to it |
| 329 | `LOG1` | `Functions::Log::Reduce` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | saves the unbiased exponent and sets Fac's exponent to $80 |
| 330 | `MULLN2` | `Functions::Log::MultiplyByLogOfTwo` | local | all | M6502 [PET], CBM4S79 [P4 P4R], HV4, HV4R | yes: Commodore | points Y:A at LogOfTwo; the code falls into Float::MultiplyPacked — nothing references it; M6502 gives the name for PET builds only (vendor), so its Also goes in Commodore's alias file, see A-Q1 |

### MsBasic.MemoryAccess

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 331 | `MEMORY_ACCESS_ADDRESS` | `AddressConversion` | macro | all |  | — | emits ReadAddressAndByte, ReadCommaAndByte and ConvertToAddress (x1) |
| 332 | `rejectNegative` | `KEEP` | parameter of MEMORY_ACCESS_ADDRESS | all |  | — | reject a negative Fac address (PET); already descriptive |
| 333 | `GETNUM` | `ReadAddressAndByte` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | evaluates a number, converts it to PokeAddress, then falls into ReadCommaAndByte; X = the byte — used by POKE and WAIT |
| 334 | `COMBYT` | `ReadCommaAndByte` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no; alias COMBYTE in AppleSoft | requires a comma and jumps to GETBYT; X = the byte — Also: COMBYTE (ASTIL 76) as the comment has it |
| 335 | `GETADR` | `ConvertToAddress` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R]; spelling only: AS82 [AS] | no | rejects exponent >= $91 (and a negative sign where selected), QINT, stores the low 16 bits in PokeAddress; A = high, Y = low |
| 336 | `MEMORY_ACCESS_PEEK` | `PeekFunction` | macro | all |  | — | emits PEEK with its save, guard and padding choices (x1) |
| 337 | `preserveAddress` | `KEEP` | parameter of MEMORY_ACCESS_PEEK | all |  | — | restore PokeAddress around PEEK; already descriptive |
| 338 | `highFirst` | `KEEP` | parameter of MEMORY_ACCESS_PEEK | all |  | — | push the high byte first; already descriptive |
| 339 | `guardRom` | `KEEP` | parameter of MEMORY_ACCESS_PEEK | all |  | — | return 0 for ROM pages (BASIC 1); already descriptive |
| 340 | `padGuard` | `KEEP` | parameter of MEMORY_ACCESS_PEEK | all |  | — | eight NOPs where the guard was; already descriptive |
| 341 | `PEEK` | `Functions::Peek` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | converts Fac to an address, reads the byte, returns it as a float (SNGFLT) |
| 342 | `GETCON` | `Functions::Peek::Fetch` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | lda (PokeAddress),y; tay — not ReadByte: avoids a likely top-level name |
| 343 | `DOSGFL` | `Functions::Peek::ToReturnByte` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | restores PokeAddress where selected, then jmp SNGFLT; the ROM guard branches here with Y = 0 |
| 344 | `MEMORY_ACCESS_POKE` | `PokeStatement` | macro | all |  | — | emits POKE (x1) |
| 345 | `POKE` | `Statements::Poke` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | ReadAddressAndByte, stores X at (PokeAddress) |
| 346 | `MEMORY_ACCESS_WAIT` | `WaitStatement` | macro | all |  | — | emits WAIT (x1) |
| 347 | `defaultTarget` | `KEEP` | parameter of MEMORY_ACCESS_WAIT | all |  | — | branch target for an omitted second mask (STORDO or ZSTORD); already descriptive |
| 348 | `FNWAIT` | `Statements::Wait` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | reads address and AND mask, optional XOR mask (default 0), polls until ((byte XOR mask) AND mask) is nonzero |
| 349 | `STORDO` | `Statements::Wait::StoreMask` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores X as WaitXorMask; BASIC 2's hidden-message extension (ZSTORD) continues here — reached from the vendors' floating-point files |
| 350 | `WAITER` | `Statements::Wait::Poll` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the polling loop |
| 351 | `ZERRTS` | `Statements::Wait::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts; the addition core (AdditionCore) branches here as its own return — shared exit: see B1-Q1 |

### MsBasic.MemoryManagement

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 352 | `MEMORY_MANAGEMENT` | `MemoryManagement` | macro | all |  | — | emits FindForFrame, MoveRangeUp, CheckStack and CheckFreeMemory (x1) |
| 353 | `stackReserve` | `KEEP` | parameter of MEMORY_MANAGEMENT | all |  | — | the byte CheckStack adds ($36 or $3E); already descriptive |
| 354 | `FNDFOR` | `FindForFrame` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | from 4 bytes above the caller, steps FOR_FRAME_SIZE at a time while frames are TOKEN_FOR; zero set on the variable's frame — zero high AssignedVariable takes the first frame; see B1-Q2 |
| 355 | `FFLOOP` | `FindForFrame::NextFrame` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stops at a frame not marked TOKEN_FOR; a zero AssignedVariable high byte adopts this frame's variable |
| 356 | `CMPFOR` | `FindForFrame::Compare` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | compares the frame's variable pointer with AssignedVariable |
| 357 | `ADDFRS` | `FindForFrame::SkipFrame` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | adds FOR_FRAME_SIZE to X and loops unless X wraps to 0 — wrap leaves zero set, as if matched (documented) |
| 358 | `FFRTS` | `FindForFrame::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts |
| 359 | `BLTU` | `MoveRangeUp` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | CheckFreeMemory on the new end, sets ArraysEnd, then copies SourceStart..SourceEnd up to end at DestinationEnd, backward — see B1-Q5 (Range vs Block) |
| 360 | `BLTUC` | `MoveRangeUp::Unchecked` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the copy without the check or ArraysEnd; the string collector enters here |
| 361 | `BLT1` | `MoveRangeUp::SetDestination` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | lowers DestinationEnd by the partial-page length |
| 362 | `BLTLP` | `MoveRangeUp::CopyByte` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | (SourceEnd),y to (DestinationEnd),y |
| 363 | `MOREN1` | `MoveRangeUp::NextByte` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | dey; loop; then copies offset 0 |
| 364 | `DECBLT` | `MoveRangeUp::NextPage` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | steps both high bytes down a page; X pages |
| 365 | `GETSTK` | `CheckStack` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | 2 x A + the reserve must not carry and must stay below the stack pointer, else OUT OF MEMORY |
| 366 | `REASON` | `CheckFreeMemory` | routine | all | M6502, ASTIL [AS], AS82 [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | A/Y below StringsBottom returns; otherwise saves the transfer scratch, collects strings, rechecks: OUT OF MEMORY |
| 367 | `TRYMOR` | `CheckFreeMemory::Collect` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | pushes A, Y and nine scratch bytes, calls GARBA2 |
| 368 | `REASAV` | `CheckFreeMemory::SaveScratch` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | pushes FloatTemporary1+x for x = 9 down to 1 — its last load (x = 0) is never pushed, as documented |
| 369 | `REASTO` | `CheckFreeMemory::RestoreScratch` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | pulls the nine bytes back after collection |
| 370 | `REARTS` | `CheckFreeMemory::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts |

### MsBasic.MovementCore

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 371 | `FLOAT_MOVEMENT` | `FloatMovement` | macro | all |  | — | emits the pack, unpack and copy routines and Round |
| 372 | `MOVFR` | `Float::NormalizeResult` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | copies Result1..4 into Fac's mantissa and normalizes — MultiplyArg and DivideArg end here |
| 373 | `MOVFM` | `Float::LoadFac` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | unpacks the five bytes at Y:A into Fac, clearing FacExtension; returns A = the exponent — ASTIL (MOVFM); used by evaluator, FOR, NEXT, Functions |
| 374 | `MOV2F` | `Float::StoreFacInTemporary2` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | sets X to FloatTemporary2 and skips the next LDX (BIT absolute), going on as StoreFacInTemporary1 does — Falls into StoreFacInTemporary1 (over its LDX) |
| 375 | `MOV1F` | `Float::StoreFacInTemporary1` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | sets X to FloatTemporary1, Y to 0, and stores Fac there (StoreFac) — ASTIL (MOV1F) |
| 376 | `MOVML` | `Float::StoreFacInTemporary1::InPageZero` | local | all | M6502, ASTIL [AS]; spelling only: AS82 [AS] | no | sets Y = 0 and branches to StoreFac: stores Fac at the page-zero address in X — nothing references it; ASTIL documents it as an entry (MOVML), so kept |
| 377 | `MOVVF` | `Float::StoreFacInVariable` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores Fac (StoreFac) at the variable AssignedVariable points to — Assignment and NEXT call it |
| 378 | `MOVMF` | `Float::StoreFac` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | rounds Fac and packs it into the five bytes at Y:X; returns Y = 0 with FacExtension cleared — ASTIL (MOVMF) |
| 379 | `MOVFA` | `Float::CopyArgToFac` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | loads ArgSign and falls into CopyArgToFacWithSign — ASTIL (MOVFA) |
| 380 | `MOVFA1` | `Float::CopyArgToFacWithSign` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores A as FacSign, copies Arg's exponent and mantissa into Fac and clears FacExtension — RaiseArg calls it |
| 381 | `MOVFAL` | `Float::CopyArgToFacWithSign::Loop` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | copies one byte, from the top down |
| 382 | `MOVAF` | `Float::CopyFacToArg` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | rounds Fac and falls into CopyFacToArgUnrounded — ASTIL (MOVAF) |
| 383 | `MOVEF` | `Float::CopyFacToArgUnrounded` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | copies Fac's exponent, mantissa and sign into Arg and clears FacExtension — Functions::Exp calls it |
| 384 | `MOVAFL` | `Float::CopyFacToArgUnrounded::Loop` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | copies one byte, from the top down |
| 385 | `MOVRTS` | `Float::CopyFacToArgUnrounded::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the shared rts — reached from Round; see A-Q4 |
| 386 | `ROUND` | `Float::Round` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | if FacExtension's bit 7 is set (and Fac is not zero), adds one to the mantissa; a carry out shifts it right — Assignment, ExpressionCore, DivideArg call it |
| 387 | `INCRND` | `Float::Round::Increment` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | IncrementMantissa; a mantissa that wrapped to zero goes to ShiftInCarry — reached from Functions::Exp; see A-Q4 |

### MsBasic.Next

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 388 | `NEXT_ENTRIES` | `NextEntries` | macro | all |  | — | emits NEXT and the type checks after it (x1) — settled as NextEntries (K1) |
| 389 | `countedStack` | `KEEP` | parameter of NEXT_ENTRIES | all |  | — | SDK switch: 1 steps X through the frame — KEEP |
| 390 | `nextStatement` | `KEEP` | parameter of NEXT_ENTRIES | all |  | — | the continuation after NEXT (NEWSTT or NXTCO1); already descriptive |
| 391 | `NEXT` | `Statements::Next` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | finds the frame (named variable or innermost), adds the step, compares with the limit; loops to the frame's line and text, or removes the frame |
| 392 | `GETFOR` | `Statements::Next::WithVariable` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | NEXT names a variable: PTRGET; the comma path jsr's here for the next variable — not FindVariable: avoids PTRGET's likely name |
| 393 | `STXFOR` | `Statements::Next::SearchFrame` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | AssignedVariable = A/Y (Y = 0: any), FindForFrame; no frame: NEXT WITHOUT FOR |
| 394 | `ERRGO5` | `Statements::Next::ToError` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | relays to RequireType::ToError; READ's input path (VariableInput) branches here too |
| 395 | `HAVFOR` | `Statements::Next::AddStep` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | sets the stack to the frame, adds ForFrame::STEP to the variable, stores, compares with ForFrame::LIMIT signed by STEP_SIGN |
| 396 | `NEWSGO` | `Statements::Next::ToNextStatement` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jmp to the continuation |
| 397 | `LOOPDN` | `Statements::Next::EndLoop` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | removes the frame (adds FOR_FRAME_SIZE); a comma continues with the next variable |
| 398 | `FRMNUM` | `EvaluateNumber` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R]; spelling only: AS82 [AS] | no | FRMEVL, then falls into RequireNumber |
| 399 | `CHKNUM` | `RequireNumber` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | clears carry and BIT-skips RequireString's sec; falls into RequireType |
| 400 | `CHKSTR` | `RequireString` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | sets carry; falls into RequireType |
| 401 | `CHKVAL` | `RequireType` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | ValueType's sign must equal carry, else TYPE MISMATCH |
| 402 | `CHKOK` | `RequireType::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts |
| 403 | `DOCSTR` | `RequireType::IsString` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | a string result: succeeds only with carry set |
| 404 | `CHKERR` | `RequireType::Mismatch` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; other names here: MISMTCH (AS82) | aliases: MISMTCH (AppleSoft) | X = the TYPE MISMATCH error |
| 405 | `ERRGO4` | `RequireType::ToError` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jmp ERROR; Statements::Next::ToError relays here |

### MsBasic.OperandEvaluation

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 406 | `OPERAND_EVALUATION` | `OperandEvaluation` | macro | all |  | — | Emits the operand evaluator, the parenthesis and character checks, SNERR and the prefix-operator entries (EVAL through GONPRC) |
| 407 | `piToken` | `KEEP` | parameter of OPERAND_EVALUATION | all |  | — | 1 assembles the PI token's constant and its check — SDK's own name |
| 408 | `bitwiseNot` | `KEEP` | parameter of OPERAND_EVALUATION | all |  | — | 1 makes NOT a signed 16-bit complement, 0 a zero-or-one Boolean — SDK's own name |
| 409 | `functionEntry` | `KEEP` | parameter of OPERAND_EVALUATION | all |  | — | The routine EvaluateFunctionOperand jumps to for a function token (CallFunction, or AS's SCRN check) — SDK's own name |
| 410 | `EVAL` | `EvaluateOperand` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Clears ValueType and reads one operand: a number, variable, PI, '.', unary +/-, or a quoted string — Falls into ReadQuotedString; branches on to EvaluateTokenOperand |
| 411 | `EVAL0` | `EvaluateOperand::NextCharacter` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Reads the next character (also skips a unary plus) |
| 412 | `EVAL1` | `EvaluateOperand::ToParseNumber` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | JMP FIN for a digit or decimal point — To + FIN's new name (part A) |
| 413 | `EVAL2` | `EvaluateOperand::NotDigit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Not a digit: a letter goes to the variable operand (vendor ISVAR) |
| 414 | `PIVAL` | `EvaluateOperand::Pi` | data | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | (PET) The packed float of pi that the PI token loads with MOVFM |
| 415 | `QDOT` | `EvaluateOperand::CheckPoint` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Checks for '.', the minus and plus tokens and a quote |
| 416 | `STRTXT` | `ReadQuotedString` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Builds a temporary for the quoted text after TextPointer (Strings::FromText) and moves TextPointer past it — ASTIL entry; vendors' INPUT prompt uses it |
| 417 | `STRTX2` | `ReadQuotedString::HaveAddress` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Text address in A/Y (carry from the quote added): makes the string and sets TextPointer |
| 418 | `EVAL3` | `EvaluateTokenOperand` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | An operand starting with a token: NOT goes to ApplyPrefixOperator with NOT's table entry, others to EvaluateFunctionOperand — Reached by branch from EvaluateOperand; see B2-Q3 |
| 419 | `NOTOP` | `Operators::Not` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The NOT operator: Boolean 1 for zero, else 0 (AS); or the signed 16-bit complement (PET) — Dispatched from OperatorTable; see B2-Q4 (Operators scope) |
| 420 | `NOTOP1` | `Operators::Not::LoadFalse` | local | AS | none found | — | (AS) Nonzero operand: result 0 |
| 421 | `EVAL4` | `EvaluateFunctionOperand` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | FN goes to FNDOER; a token below the first function falls into EvaluateParenthesized; a function jumps to functionEntry — Falls into EvaluateParenthesized |
| 422 | `PARCHK` | `EvaluateParenthesized` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS], K4S79 [P4 P4R], HVK4 [P4 P4R] | no | Requires '(', evaluates an expression and falls into CheckCloseParenthesis — ASTIL entry |
| 423 | `CHKCLS` | `CheckCloseParenthesis` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | no | Loads ')' and skips into CheckCharacter with BITs — ASTIL entry |
| 424 | `CHKOPN` | `CheckOpenParenthesis` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | no | Loads '(' and skips into CheckCharacter with BITs — ASTIL entry |
| 425 | `CHKCOM` | `CheckComma` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | no | Loads ',' and falls into CheckCharacter — ASTIL entry |
| 426 | `SYNCHR` | `CheckCharacter` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R]; spelling only: AS82 [AS] | no | Requires the character in A at TextPointer and reads the next one; SYNTAX otherwise — ASTIL entry |
| 427 | `CHRGO5` | `CheckCharacter::ToGetNextCharacter` | local | all | M6502 | no | JMP CHRGET after a match — Unreferenced but documented (M6502): kept |
| 428 | `SNERR` | `SyntaxError` | routine | all | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | no | Loads the SYNTAX error offset and jumps to the error handler — Called from many modules and both vendors; see B2-Q5 |
| 429 | `DOMIN` | `ApplyMinus` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Selects the unary-minus entry of OperatorTable and falls into ApplyPrefixOperator — Reached by branch from EvaluateOperand |
| 430 | `GONPRC` | `ApplyPrefixOperator` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Drops EvaluateOperand's return address and jumps to EvaluateExpression::Prefix with Y = the operator's table offset |
| 431 | `INTEGER_VARIABLE_VALUE` | `IntegerVariableValue` | macro | all |  | — | Emits the integer-variable load that the vendor's variable operand code reaches (GOOO, GOOOOO) |
| 432 | `GOOO` | `LoadNumericVariable` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | For an integer variable, loads its two bytes (high first) at the address in FacMantissa3/4 and converts them with GIVAYF — The vendor's ISVAR branches here; a float falls out of the macro into the vendor's MOVFM jump |
| 433 | `GOOOOO` | `LoadNumericVariable::NotInteger` | local | all | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | no | Float variable: falls out to the vendor's code that loads it |
| 434 | `FUNCTION_DISPATCH` | `FunctionDispatch` | macro | all |  | — | Emits the built-in function dispatcher (ISFUN, OKNORM, FINGO) |
| 435 | `ISFUN` | `CallFunction` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Parses a function's arguments (string and byte for LEFT$/RIGHT$/MID$, else one parenthesized expression) and calls its routine through FunctionJump — The PET passes it as functionEntry; AS's SCRN check falls into it |
| 436 | `OKNORM` | `CallFunction::OneArgument` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Ordinary function: evaluates the parenthesized argument |
| 437 | `FINGO` | `CallFunction::Dispatch` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stores the routine's address from FUNDSP in FunctionJump, calls it, then requires a numeric result — String functions drop this return (SliceArguments, Chr, Str) and so skip the check |
| 438 | `LOGICAL_OPERATORS` | `LogicalOperators` | macro | all |  | — | Emits the OR and AND operators in the variant's Boolean or bitwise form |
| 439 | `bitwise` | `KEEP` | parameter of LOGICAL_OPERATORS | all |  | — | 1 for signed 16-bit OR and AND, 0 for zero-or-one Boolean results — SDK's own name |
| 440 | `OROP` | `Operators::Or` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The OR operator: PET complements both operands and their AND (Y = $FF) by skipping into And; AS falls through its Boolean test — Dispatched from OperatorTable |
| 441 | `ANDOP` | `Operators::And` [PET]; `Operators::Or` [AS] | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | yes: AS (on Operators::Or) | (PET) The signed 16-bit AND of Arg and FAC, with COUNT as the complement mask that OR sets — In AS this label sits at OR's entry: there ANDOP goes on Operators::Or and And is OROP1; see B2-Q4 |
| 442 | `OROP1` | `Operators::And` | routine | AS | none found | — | (AS) The Boolean AND: 1 when both exponents are nonzero, else 0 — Same job as the PET's ANDOP, so the same name; Apple's dispatch table names it |
| 443 | `OROP11` | `Operators::And::LoadFalse` | local | AS | none found | — | (AS) A zero operand: result 0 |
| 444 | `OROP12` | `Operators::And::LoadTrue` | entry | AS | none found | — | (AS) Result 1; Operators::Or branches here when either operand is nonzero — Entered from Or |

### MsBasic.OperatorTable

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 445 | `OPERATOR_TABLE` | `OperatorEntries` | macro | all |  | — | emits OperatorTable with the two precedence choices and the AND handler (x1) — not OperatorTable: the table's own name |
| 446 | `powerBelowNegation` | `KEEP` | parameter of OPERATOR_TABLE | all |  | — | precedence of ^ below unary minus (AppleSoft); already descriptive |
| 447 | `highNot` | `KEEP` | parameter of OPERATOR_TABLE | all |  | — | NOT at unary precedence (AppleSoft); already descriptive |
| 448 | `andEntry` | `KEEP` | parameter of OPERATOR_TABLE | all |  | — | AND's handler (OROP1 or ANDOP); already descriptive |
| 449 | `OPTAB` | `OperatorTable` | table | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS] | no | three-byte entries for + - * / ^ AND OR: precedence, handler address - 1 (pushed for an RTS dispatch) — see B1-Q2 (OperatorEntry struct) |
| 450 | `NEGTAB` | `OperatorTable::Negation` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | unary minus's entry; operands use its offset from OperatorTable |
| 451 | `NOTTAB` | `OperatorTable::Not` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | NOT's entry ($7F or $5A) |
| 452 | `PTDORL` | `OperatorTable::Relation` | data | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the relational operators' shared entry (precedence $64, DOREL) |

### MsBasic.OutputCore

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 453 | `DECIMAL_OUTPUT` | `DecimalOutput` | macro | all |  | — | emits the line-number printers, PrintFac and FormatFac |
| 454 | `omitPositiveSpace` | `KEEP` | parameter of DECIMAL_OUTPUT | all |  | — | SDK's descriptive parameter: 1 omits the space before a positive number |
| 455 | `includeTime` | `KEEP` | parameter of DECIMAL_OUTPUT | all |  | — | SDK's descriptive parameter: 1 lets FormatFac also run the TI$ divisors — same name as OutputTables' parameter (row 247) |
| 456 | `INPRT` | `Float::PrintInLineNumber` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | prints " IN " (through ToPrintString), then CurrentLine through PrintDecimalAX — ASTIL (INPRT); CommandCore and Commodore call it; Falls into PrintDecimalAX; see A-Q8 |
| 457 | `LINPRT` | `Float::PrintDecimalAX` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R]; spelling only: AS82 [AS] | no | prints the unsigned word in A (high) and X (low) as a decimal number — ASTIL (LINPRT); as the Monitor's PrintAX, in decimal; Falls into PrintFac; see A-Q8 |
| 458 | `LINPRT_FOUT` | `Float::PrintFac` | routine | all | none found | no; alias PRNTFAC in AppleSoft | formats Fac (FormatFac) and prints the string, falling into ToPrintString — AppleSoft's PRNTFAC (row 1287) names it; LINPRT_FOUT is the SDK's own name, no Also |
| 459 | `STROU2` | `Float::PrintFac::ToPrintString` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jumps on to STROUT, printing the string at Y:A — reached from PrintInLineNumber; To plus STROUT's new name (string part): adjust; see A-Q4 |
| 460 | `FOUT` | `Float::FormatFac` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | sets Y = 1 and falls into FormatFacAtOffset: formats Fac into NumberBuffer; returns Y:A = NumberBuffer — ASTIL (FOUT); Print calls it |
| 461 | `FOUTC` | `Float::FormatFacAtOffset` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | formats Fac as a zero-terminated decimal string starting at NumberBuffer-1+Y (STR$ passes Y = 0); Fac is changed — StringConversion (STR$) calls it |
| 462 | `FOUT1` | `Float::FormatFacAtOffset::StoreSign` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores the sign character (space or minus, by build) — two definitions, one per variant (lines 61 and 71) |
| 463 | `FOUT13` | `Float::FormatFacAtOffset::SignDone` | local | AS | none found | — | a positive number in the omitted-space build stores no sign character — AppleSoft only; no document name, so no Also |
| 464 | `FOUT37` | `Float::FormatFacAtOffset::ScaleUpSmall` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Fac below 1: multiplies by Billion and starts the decimal scale at -9 |
| 465 | `FOUT7` | `Float::FormatFacAtOffset::SetScale` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores the starting decimal scale in DigitsBeforePoint |
| 466 | `FOUT4` | `Float::FormatFacAtOffset::CheckUpper` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | compares with UpperOutputLimit: equal goes straight to ConvertInteger, larger divides |
| 467 | `FOUT3` | `Float::FormatFacAtOffset::CheckLower` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | compares with LowerOutputLimit: larger rounds |
| 468 | `FOUT38` | `Float::FormatFacAtOffset::MultiplyUp` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | MultiplyByTen and lowers the scale |
| 469 | `FOUT9` | `Float::FormatFacAtOffset::DivideDown` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | DivideByTen and raises the scale |
| 470 | `FOUT5` | `Float::FormatFacAtOffset::RoundHalf` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | adds 1/2 (AddHalf) to round |
| 471 | `BIGGES` | `Float::FormatFacAtOffset::ConvertInteger` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | ToLongInteger, then decides between fixed point and an E exponent from the scale |
| 472 | `FOUTPI` | `Float::FormatFacAtOffset::UseExponent` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | outside the fixed-point range: sets carry so the exponent is kept |
| 473 | `FOUT6` | `Float::FormatFacAtOffset::SetExponent` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores the printed exponent in DecimalExponent (0 means fixed point) and the digits before the point |
| 474 | `FOUT39` | `Float::FormatFacAtOffset::LeadingPoint` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | no digits before the point: writes '.' and, if needed, '0' |
| 475 | `FOUT16` | `Float::FormatFacAtOffset::SavePosition` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | saves the buffer position |
| 476 | `FOUT8` | `Float::FormatFacAtOffset::FirstPower` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | starts at the first power of ten |
| 477 | `FOUTIM` | `Float::FormatFacAtOffset::ExtractDigits` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | with Y at a power of ten: sets X's bit 7 for the first pass and extracts digits — reached from Commodore's TI$ output; see A-Q4 |
| 478 | `FOUT2` | `Float::FormatFacAtOffset::AddPower` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | adds the current signed power of ten to the integer in Fac, counting in X |
| 479 | `FOUT41` | `Float::FormatFacAtOffset::Carried` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | a carry with a negative power: keep adding |
| 480 | `FOUT40` | `Float::FormatFacAtOffset::DigitFound` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | turns the count into the digit (complemented for a positive power) |
| 481 | `FOUTYP` | `Float::FormatFacAtOffset::StoreDigit` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | makes the count an ASCII digit, stores it and writes '.' when the digits before the point are done |
| 482 | `STXBUF` | `Float::FormatFacAtOffset::SavePointer` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | saves the buffer position and reloads the table offset |
| 483 | `FOUTCM` | `Float::FormatFacAtOffset::NextPower` | local | all | M6502 | no | flips X's bit 7 for the next power's sign; loops until the table (or the TI$ divisors) ends — nothing references it; M6502 names it, so kept |
| 484 | `FOULDY` | `Float::FormatFacAtOffset::DigitsDone` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | reloads the buffer position |
| 485 | `FOUT11` | `Float::FormatFacAtOffset::TrimZeros` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | removes trailing zeros and an unneeded point |
| 486 | `FOUT12` | `Float::FormatFacAtOffset::Exponent` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | writes no exponent for fixed point; otherwise picks its sign |
| 487 | `FOUT14` | `Float::FormatFacAtOffset::StoreExponentSign` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | writes 'E' and the exponent's sign |
| 488 | `FOUT15` | `Float::FormatFacAtOffset::ExponentTens` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | counts the exponent's tens, then writes its two digits and the terminator |
| 489 | `FOUT19` | `Float::FormatFacAtOffset::StoreZero` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Fac is zero: writes '0' |
| 490 | `FOUT17` | `Float::FormatFacAtOffset::Terminate` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | writes the zero terminator |
| 491 | `FOUT20` | `Float::FormatFacAtOffset::ReturnBuffer` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | returns Y:A = NumberBuffer |
| 492 | `FPWRRT` | `Float::FormatFacAtOffset::Return` | local | all | M6502 | no | the rts — nothing references it; M6502 names it, so kept |

### MsBasic.Print

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 493 | `PRINT_CORE` | `PrintItems` | macro | all |  | — | emits PRINT's item loop (x1; AppleSoft chooses one of two expansions by ENHNCD) |
| 494 | `tabEntry` | `KEEP` | parameter of PRINT_CORE | all |  | — | TAB and SPC handler (TABER or LINCH1); already descriptive |
| 495 | `clearSpaceCarry` | `KEEP` | parameter of PRINT_CORE | all |  | — | clc before the SPC dispatch; already descriptive |
| 496 | `clearCommaCarry` | `KEEP` | parameter of PRINT_CORE | all |  | — | clc before the comma dispatch; already descriptive |
| 497 | `trailingSpace` | `KEEP` | parameter of PRINT_CORE | all |  | — | a space after each number (PET); already descriptive |
| 498 | `STRDON` | `Statements::PrintStringItem` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | prints the string result (STRPRT), falls into PrintNextItem — before Statements::Print, so its own proc |
| 499 | `NEWCHR` | `Statements::PrintNextItem` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | rereads the current character, falls into Print |
| 500 | `PRINT` | `Statements::Print` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | end of statement: new line (CRDO); else falls into the item dispatch |
| 501 | `PRINTC` | `Statements::Print::Item` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | end: return; TAB/SPC, comma, semicolon, or an expression (string, or number via FOUT and STRLIT); the vendors' channel PRINT enters here |
| 502 | `LINCHK` | `Statements::Print::NumberItem` | local | PET | M6502 | no | PET: prints the converted number and a space, back to PrintNextItem — kept unreferenced: documented; AppleSoft's own LINCHK is a different label (comma zones) |

### MsBasic.ProgramReset

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 503 | `PROGRAM_RESET` | `ProgramReset` | macro | all |  | — | emits NEW, EraseProgram and ResetProgramState (x1) |
| 504 | `newAlias` | `DROP` | parameter of PROGRAM_RESET | all |  | — | only defines AppleSoft's NEW at Statements::New's address; NEW becomes an Also there — see B1-Q7 |
| 505 | `resetLock` | `KEEP` | parameter of PROGRAM_RESET | all |  | — | clears AppleSoft's LOCK; already descriptive |
| 506 | `mirrorEnd` | `KEEP` | parameter of PROGRAM_RESET | all |  | — | copies VariablesStart to PRGEND (AppleSoft); already descriptive |
| 507 | `clearCarry` | `KEEP` | parameter of PROGRAM_RESET | all |  | — | clc before adding 2; already descriptive |
| 508 | `runSetsZero` | `KEEP` | parameter of PROGRAM_RESET | all |  | — | lda #0 so the fall into Clear sees zero; already descriptive |
| 509 | `NEW` | `Statements::New` | alias | AS | spelling only: ASTIL [AS], AS82 [AS] | — | AppleSoft's second label at SCRATH's address — see B1-Q7: Also NEW (ASTIL, AS82) in AppleSoft's alias file |
| 510 | `SCRATH` | `Statements::New` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | text after NEW: syntax error return via FindLine::Done; falls into EraseProgram |
| 511 | `SCRTCH` | `EraseProgram` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS], K4S79 [P4 P4R], HVK4 [P4 P4R] | no | stores a zero link at ProgramStart, sets VariablesStart to ProgramStart + 2; falls into ResetProgramState — startup in both vendors calls it |
| 512 | `RUNC` | `ResetProgramState` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | RewindTextPointer, then falls into CLEAR's reset of variables, DATA and stack — used by RUN, line editing, LOAD |
| 513 | `CLEAR_STATEMENT` | `ClearStatement` | macro | all |  | — | emits CLEAR's argument check (x1) |
| 514 | `returnEntry` | `KEEP` | parameter of CLEAR_STATEMENT | all |  | — | the rts for trailing text (STKRTS or CONTRT); already descriptive |
| 515 | `CLEAR` | `Statements::Clear` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS], AS82 [AS] | no | trailing text returns for a syntax error; falls into ClearVariables (BASIC 1: followed by jmp) |
| 516 | `NULL_STATEMENT` | `NullStatement` | macro | P1 P1R |  | — | emits NULL (x1, BASIC 1) |
| 517 | `incrementedLimit` | `KEEP` | parameter of NULL_STATEMENT | P1 P1R |  | — | first rejected count + 1; already descriptive |
| 518 | `NULL` | `Statements::Null` | routine | P1 P1R | M6502, HV1, HV1R | no | GETBYT; 0..limit-2 (and 255) stored in NULCNT, else ILLEGAL QUANTITY |
| 519 | `FCERR1` | `Statements::Null::ToIllegalQuantity` | local | P1 P1R | M6502, HV1, HV1R | no | jmp FCERR — target named as part B2 names FCERR |
| 520 | `CLEAR_STORAGE` | `ClearStorage` | macro | all |  | — | emits ClearVariables (x1) |
| 521 | `closeFiles` | `KEEP` | parameter of CLEAR_STORAGE | all |  | — | close files (CQCALL) on the PET; already descriptive |
| 522 | `clearDiskStatus` | `KEEP` | parameter of CLEAR_STORAGE | all |  | — | clear BASIC 4's disk-status descriptor; already descriptive |
| 523 | `CLEARC` | `ClearVariables` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | StringsBottom = MemoryTop, ArraysStart and ArraysEnd = VariablesStart, then RESTORE, falls into ResetStack |
| 524 | `FLOAD` | `ClearVariables::RestoreData` | local | all | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | no | jsr Statements::Restore; falls into ResetStack — kept unreferenced: documented |
| 525 | `EXECUTION_RESET` | `ExecutionReset` | macro | all |  | — | emits ResetStack and RewindTextPointer (x1) |
| 526 | `earlyStack` | `KEEP` | parameter of EXECUTION_RESET | all |  | — | BASIC 1's store-before-move return-address sequence; already descriptive |
| 527 | `paddedReturn` | `KEEP` | parameter of EXECUTION_RESET | all |  | — | BASIC 1's extra rts and byte; already descriptive |
| 528 | `stackTop` | `KEEP` | parameter of EXECUTION_RESET | all |  | — | the stack pointer set; already descriptive |
| 529 | `STKINI` | `ResetStack` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | frees the temporaries, resets the stack pointer keeping the return address, disables CONT (StoppedText high = 0), clears SubscriptsAllowed — bug documented: earlyStack has an interrupt window |
| 530 | `STKRTS` | `ResetStack::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts; LIST and CLEAR return through it for a syntax error — shared exit: see B1-Q1 |
| 531 | `STXTPT` | `RewindTextPointer` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R]; spelling only: AS82 [AS] | no | TextPointer = ProgramStart - 1 |

### MsBasic.ProgramTransfers

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 532 | `RESTORE_DATA` | `RestoreStatement` | macro | all |  | — | emits RESTORE (x1) |
| 533 | `RESTOR` | `Statements::Restore` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | DataPointer = ProgramStart - 1 |
| 534 | `RESFIN` | `Statements::Restore::SetDataPointer` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores A/Y in DataPointer; READ's finish enters here |
| 535 | `ISCRTS` | `Statements::Restore::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts; the statement dispatcher returns through it at end of statement — shared exit: see B1-Q1 |
| 536 | `STOP_AND_CONTINUE` | `StopAndContinue` | macro | all |  | — | emits STOP, END, their shared halt and CONT (x1) |
| 537 | `lineNumberDirect` | `KEEP` | parameter of STOP_AND_CONTINUE | all |  | — | direct mode by CurrentLine or the text page; already descriptive |
| 538 | `clearOutput` | `KEEP` | parameter of STOP_AND_CONTINUE | all |  | — | clear OutputSuppressed before BREAK; already descriptive |
| 539 | `STOP` | `Statements::Stop` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS], AS82 [AS], K4S79 [P4 P4R], HVK4 [P4 P4R]; other names here: BSTOP (HVK4) | aliases: BSTOP | carry set (CHRGET's non-digit, or ISCNTC's cmp #3 for Control-C) skips End's clc, so BREAK is printed; falls into End — Also: BSTOP (HVK4) in BASIC 4 if checked |
| 540 | `END` | `Statements::End` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS], AS82 [AS] | no | clears carry (no message), falls into StopOrEnd |
| 541 | `STOPC` | `Statements::StopOrEnd` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | trailing text returns; in a program saves StoppedText and StoppedLine; drops the return; BREAK (carry) or READY — own proc: Stop branches into it |
| 542 | `STPEND` | `Statements::StopOrEnd::SaveLine` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | saves CurrentLine in StoppedLine; the PET's INPUT stop paths enter here |
| 543 | `DIRIS` | `Statements::StopOrEnd::DiscardReturn` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | pla pla: drops the statement loop's return |
| 544 | `ENDCON` | `Statements::StopOrEnd::Finish` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | carry set: BREAK through ReportMessage; clear: READY; the dispatchers enter here at the end of the program |
| 545 | `GORDY` | `Statements::StopOrEnd::ToReady` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jmp READY |
| 546 | `CONT` | `Statements::Cont` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS], AS82 [AS], K4S79 [P4 P4R], HVK4 [P4 P4R] | no | StoppedText high = 0: CAN'T CONTINUE; else restores TextPointer and CurrentLine |
| 547 | `CONT1` | `Statements::Cont::Resume` | local | all | none found | — | copies StoppedText and StoppedLine back — SDK's own: no Also |
| 548 | `CONTRT` | `Statements::Cont::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts; STOP, NULL, BASIC 1's CLEAR and its dispatcher return through it — shared exit: see B1-Q1 |
| 549 | `RUN_STATEMENT` | `RunStatement` | macro | all |  | — | emits RUN (x1) |
| 550 | `runLabel` | `DROP` | parameter of RUN_STATEMENT | all |  | — | only defines RUN1, which nothing references or documents — see B1-Q7 |
| 551 | `RUN` | `Statements::Run` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS], AS82 [AS] | no | no line: ResetProgramState; else ClearVariables and the GOSUB transfer |
| 552 | `RUN1` | `DROP` | local | AS | none found | — | AppleSoft's label at jsr ClearVariables: unreferenced, no document |
| 553 | `GOSUB_AND_GOTO` | `GosubAndGoto` | macro | all |  | — | emits GOSUB and GOTO (x1) |
| 554 | `nextStatement` | `KEEP` | parameter of GOSUB_AND_GOTO | all |  | — | the statement loop's entry; already descriptive |
| 555 | `GOSUB` | `Statements::GoSub` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | CheckStack(3), pushes a GosubFrame (TextPointer, CurrentLine, TOKEN_GOSUB), then the transfer — see B1-Q2 (GosubFrame), B1-Q8 (spelling) |
| 556 | `RUNC2` | `Statements::GoSub::Transfer` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | GetCurrentCharacter, GoTo, jmp to the statement loop; RUN with a line enters here |
| 557 | `GOTO` | `Statements::GoTo` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | ReadLineNumber, FindLineEnd; searches from the next line when the target's high byte is above CurrentLine's, else from ProgramStart; TextPointer = line - 1 |
| 558 | `LUK4IT` | `Statements::GoTo::SearchFromStart` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | A/X = ProgramStart |
| 559 | `LUKALL` | `Statements::GoTo::Search` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | FindLine::FromAddress |
| 560 | `QFOUND` | `Statements::GoTo::CheckFound` | local | all | M6502 | no | not found: UNDEF'D STATEMENT — kept unreferenced: documented (M6502) |
| 561 | `GORTS` | `Statements::GoTo::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts; RETURN with trailing text returns through it — shared exit: see B1-Q1 |
| 562 | `RETURN_STATEMENT` | `ReturnStatement` | macro | all |  | — | emits RETURN with its search and POP choices (x1) |
| 563 | `searchLow` | `KEEP` | parameter of RETURN_STATEMENT | all |  | — | set AssignedVariable's low (BASIC 1, AppleSoft) or high byte; already descriptive |
| 564 | `popEntry` | `KEEP` | parameter of RETURN_STATEMENT | all |  | — | AppleSoft's POP test; already descriptive |
| 565 | `RETURN` | `Statements::Return` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS], AS82 [AS] | no | FindForFrame with an impossible variable skips FOR frames; GOSUB frame: restore; else RETURN WITHOUT GOSUB — bug documented: the low-byte variant can still match |
| 566 | `USERR` | `Statements::Return::UndefinedStatement` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | X = UNDEF'D STATEMENT (skipped by RETURN's BIT), jmp ERROR; GoTo enters here |
| 567 | `SNERR2` | `Statements::Return::ToSyntaxError` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jmp SNERR; ON enters here |
| 568 | `RETU1` | `Statements::Return::RestoreCaller` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | pops the frame into CurrentLine and TextPointer (POP: to PopFinish), falls into Data to skip the rest |

### MsBasic.RandomCore

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 569 | `RANDOM_ROUTINE` | `RandomRoutine` | macro | all |  | — | emits RandomMultiplier, RandomAddend and Functions::Rnd |
| 570 | `useTimers` | `KEEP` | parameter of RANDOM_ROUTINE | all |  | — | SDK's descriptive parameter: 1 seeds RND(0) from the PET timers |
| 571 | `RMULZC` | `Float::RandomMultiplier` | data | all | M6502 | no; alias RMULC in Commodore | four bytes of RND's packed multiplier; its fifth byte is RandomAddend's first — Commodore's RMULC alias, row 2279 |
| 572 | `RADDZC` | `Float::RandomAddend` | data | all | M6502 | no; alias RADDC in Commodore | four bytes of RND's packed addend; its fifth byte is Functions::Rnd's first opcode — Commodore's RADDC alias, row 2280 |
| 573 | `RND` | `Functions::Rnd` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | RND: negative seeds from Fac, positive steps RandomSeed (multiply, add), zero repeats it or reads the timers (by build) — see A-Q3 |
| 574 | `QSETNR` | `Functions::Rnd::NextValue` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | loads RandomSeed and multiplies by RandomMultiplier and adds RandomAddend (zero argument returns it, by build) |
| 575 | `RND1` | `Functions::Rnd::Scramble` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | swaps the top and bottom mantissa bytes (and the middle two, timer build) |
| 576 | `STRNEX` | `Functions::Rnd::NormalizeAndSave` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | makes the mantissa positive in [0,1) using the exponent as low bits, normalizes and stores it in RandomSeed |
| 577 | `GMOVMF` | `Functions::Rnd::ToStoreFac` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jumps on to Float::StoreFac — reached from Functions::Tan; To plus the target; see A-Q4 |

### MsBasic.Relational

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 578 | `RELATIONAL_OPERATORS` | `RelationalOperators` | macro | all |  | — | emits ApplyRelation |
| 579 | `trueByte` | `KEEP` | parameter of RELATIONAL_OPERATORS | all |  | — | SDK's descriptive parameter: the true value's byte ($01 or $FF) |
| 580 | `DOREL` | `ApplyRelation` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | compares Arg with Fac (numbers) or two strings, masks the order with RelationMask, and gives 0 or the true value in Fac — operator-table target for the relation operators; see A-Q9 |
| 581 | `STRCMP` | `ApplyRelation::CompareStrings` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | frees both temporary strings and compares bytes up to the shorter length, then the lengths |
| 582 | `STASGN` | `ApplyRelation::SetLengthOrder` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores the length order (0, 1, $FF) for equal prefixes |
| 583 | `NXTCMP` | `ApplyRelation::NextByte` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | counts down the shorter length; at its end uses the length order |
| 584 | `QCOMP` | `ApplyRelation::NumberResult` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | turns the order in X into the carry form ApplyMask expects |
| 585 | `GETCMP` | `ApplyRelation::CompareByte` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | compares one byte of each string |
| 586 | `DOCMP` | `ApplyRelation::ApplyMask` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | maps the order to a relation bit and masks it with RelationMask |
| 587 | `GOFLOT` | `ApplyRelation::ToConvertSignedByte` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jumps on to Float::ConvertSignedByte with the result — only jumps on: To plus the target |

### MsBasic.SimpleFunctions

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 588 | `SIMPLE_FUNCTIONS` | `SimpleFunctions` | macro | all |  | — | emits Functions::Fre, ReturnSignedWord, Functions::Pos and ReturnByte |
| 589 | `setCarry` | `KEEP` | parameter of SIMPLE_FUNCTIONS | all |  | — | SDK's descriptive parameter: 1 sets carry before ReturnByte's branch — the carry has no effect: ConvertSignedWord recomputes it; bytes only |
| 590 | `FRE` | `Functions::Fre` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | FRE: frees a string argument, collects garbage, returns StringsBottom - ArraysEnd as a signed word — falls into ReturnSignedWord; see A-Q3 |
| 591 | `NOFREF` | `Functions::Fre::Collect` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | collects garbage and subtracts |
| 592 | `GIVAYF` | `ReturnSignedWord` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | makes the signed word in A (high) and Y (low) the numeric value in Fac, setting ValueType numeric — ASTIL (GIVAYF); evaluator, PEEK, LEN, ASC and others call it; see A-Q9 |
| 593 | `POS` | `Functions::Pos` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS], K4S79 [P4 P4R], HVK4 [P4 P4R] | no | POS: loads TerminalPosition and falls into ReturnByte — see A-Q3 |
| 594 | `SNGFLT` | `ReturnByte` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | makes the unsigned byte in Y the numeric value in Fac — ASTIL (SNGFLT); Falls into ReturnSignedWord; see A-Q9 |

### MsBasic.StatementFlow

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 595 | `STATEMENT_SCAN` | `StatementScan` | macro | all |  | — | emits DATA, AdvanceTextPointer and the two end scanners (x1) |
| 596 | `quoteFirst` | `KEEP` | parameter of STATEMENT_SCAN | all |  | — | branch order of the quote test (BASIC 1); already descriptive |
| 597 | `popExit` | `KEEP` | parameter of STATEMENT_SCAN | all |  | — | AppleSoft's POP exit; already descriptive |
| 598 | `DATA` | `Statements::Data` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS], K4S79 [P4 P4R], HVK4 [P4 P4R] | no | FindStatementEnd, falls into AdvanceTextPointer — DEF calls it to skip its formula |
| 599 | `ADDON` | `AdvanceTextPointer` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | TextPointer += Y — used by REM, READ, AppleSoft commands |
| 600 | `REMRTS` | `AdvanceTextPointer::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts; FindLineEnd's terminator branches return through it — shared exit: see B1-Q1 |
| 601 | `DATAN` | `FindStatementEnd` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | X = ':' and BIT-skips FindLineEnd's ldx; Y = offset of an unquoted colon or zero |
| 602 | `REMN` | `FindLineEnd` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Delimiter = 0, EndDelimiter = 0; Y = offset of the zero byte, quotes toggling the delimiters |
| 603 | `EXCHQT` | `FindLineEnd::SwapDelimiters` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | exchanges Delimiter and EndDelimiter (on entry and at each quote) |
| 604 | `REMER` | `FindLineEnd::NextCharacter` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | zero or EndDelimiter ends; a quote swaps |
| 605 | `REMER1` | `Statements::PopFinish` | routine | AS | none found | — | AppleSoft: pulls the three GOSUB frame bytes left and returns, for POP — own proc: reached only from Return; SDK's own name |
| 606 | `CONDITIONAL_STATEMENTS` | `ConditionalStatements` | macro | all |  | — | emits IF, REM and IF's true path (x1) |
| 607 | `IF` | `Statements::If` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | evaluates, requires THEN or GOTO; false falls into Rem |
| 608 | `OKGOTO` | `Statements::If::Test` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | FacExponent nonzero: true |
| 609 | `REM` | `Statements::Rem` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | FindLineEnd, then (always) AdvanceTextPointer |
| 610 | `DOCOND` | `Statements::IfTrue` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | a digit after THEN/GOTO: GoTo; else the statement through GONE3 — own proc: If branches past Rem to it |
| 611 | `DOCO` | `Statements::IfTrue::ToExecuteStatement` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | jmp GONE3 — target named as part C names GONE3 |
| 612 | `ON_STATEMENT` | `OnStatement` | macro | all |  | — | emits ON (x1) |
| 613 | `ONGOTO` | `Statements::On` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | GETBYT selects; requires GOTO or GOSUB; skips n-1 line numbers, then dispatches the token through GONE2 — Also ON in AppleSoft (its own label, same address) |
| 614 | `SNERR3` | `Statements::On::RequireGoto` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | not GOTO: syntax error; ReadLineNumber's overflow branch also lands here — bug, see B1-Q6 |
| 615 | `ONGLOP` | `Statements::On::NextEntry` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | decrements the selector; zero: dispatches the GOTO/GOSUB |
| 616 | `ONGLP1` | `Statements::On::SkipEntry` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | reads a line number; a comma continues |
| 617 | `ONGRTS` | `Statements::On::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts; ReadLineNumber exits through it at a non-digit — shared exit: see B1-Q1 |

### MsBasic.StringConcatenation

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 618 | `STRING_CONCATENATION` | `StringConcatenation` | macro | all |  | — | Emits concatenation, the character movers and the release routines (CAT through FRETMS) |
| 619 | `linkedRelease` | `KEEP` | parameter of STRING_CONCATENATION | all |  | — | 1 assembles BASIC 4's release that marks linked strings as garbage — SDK's own name |
| 620 | `CAT` | `Strings::Concatenate` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Saves the first descriptor, evaluates the second operand (a string), allocates the sum, copies both, releases both and pushes the result; jumps to EvaluateExpression::NextOperator — STRING TOO LONG above 255; see B2-Q1 (Strings scope) |
| 621 | `SIZEOK` | `Strings::Concatenate::LengthOk` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Allocates the combined string and copies the two strings into it |
| 622 | `MOVINS` | `Strings::CopyString` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Copies the characters described by the descriptor at StringPointer to NewString; falls into CopyFrom — ASTIL entry |
| 623 | `MOVSTR` | `Strings::CopyFrom` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Copies A bytes from X:Y to NewString; falls into CopyBytes — ASTIL entry |
| 624 | `MOVDO` | `Strings::CopyBytes` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Copies A bytes from Pointer1 to NewString, last byte first, and advances NewString — Keeps X |
| 625 | `MOVLP` | `Strings::CopyBytes::Loop` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Copies one byte downward |
| 626 | `QMOVE` | `Strings::CopyBytes::CheckMore` | local | all | M6502 | no | Loops while bytes remain — Unreferenced but documented (M6502): kept |
| 627 | `MVDONE` | `Strings::CopyBytes::Advance` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Adds the length to NewString |
| 628 | `MVSTRT` | `Strings::CopyBytes::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The RTS |
| 629 | `FRESTR` | `Strings::ReleaseFacString` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R]; spelling only: AS82 [AS] | no | Requires FAC to be a string (TYPE MISMATCH) and falls into ReleaseFac — ASTIL entry |
| 630 | `FREFAC` | `Strings::ReleaseFac` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Releases the string whose descriptor FAC points to; falls into ReleaseDescriptor — ASTIL entry |
| 631 | `FRETMP` | `Strings::ReleaseDescriptor` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Removes the descriptor at A:Y if it is the latest temporary, reclaims its space when it is lowest (PET 4: marks its link as garbage), returns A = length, X/Y and Pointer1 = address — ASTIL entry |
| 632 | `RES00` | `Strings::ReleaseDescriptor::CheckBottom` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Stores the string's start and checks whether it is StringsBottom |
| 633 | `FRE01` | `Strings::ReleaseDescriptor::SkipLink` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Raises StringsBottom past the second link byte |
| 634 | `FREPLA` | `Strings::ReleaseDescriptor::RestoreLength` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Pulls the length back into A |
| 635 | `FRE02` | `Strings::ReleaseDescriptor::ReadDescriptor` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Loads the length into A and the address into Pointer1 and X/Y |
| 636 | `FRETRT` | `Strings::ReleaseDescriptor::StoreAddress` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | Stores the address in Pointer1 and returns |
| 637 | `FRETMS` | `Strings::ReleaseTemporary` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Pops the descriptor A:Y off the temporary stack if it is the latest one; zero set on a match — ASTIL entry; Keeps X |
| 638 | `FRERTS` | `Strings::ReleaseTemporary::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The RTS; (P4) ReleaseDescriptor branches here — Entered from ReleaseDescriptor in BASIC 4 |

### MsBasic.StringConversion

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 639 | `STRING_FROM_NUMBER` | `StringFromNumber` | macro | all |  | — | Emits STR$ and its buffer-to-string continuation |
| 640 | `STR` | `Functions::Str` | routine | all | M6502; spelling only: AS82 [AS] | no; alias STRD in Commodore | Requires a number, formats FAC with FOUTC at NumberBufferPrefix, drops the dispatcher's return and falls into Strings::FromNumberBuffer — Commodore's STRD alias |
| 641 | `TIMSTR` | `Strings::FromNumberBuffer` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Makes a temporary string of the text at NumberBufferPrefix (BEQ to FromText: the page is zero) — The PET's TI$ read calls it |

### MsBasic.StringFunctions

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 642 | `STRING_FUNCTIONS` | `StringFunctions` | macro | all |  | — | Emits CHR$, LEFT$, RIGHT$, MID$, LEN, ASC, the byte helpers and VAL |
| 643 | `rejectZeroSlices` | `KEEP` | parameter of STRING_FUNCTIONS | all |  | — | 1 makes SliceArguments reject a zero count (ILLEGAL QUANTITY); 0 rejects only MID$'s zero start — SDK's own name |
| 644 | `indirectReturn` | `KEEP` | parameter of STRING_FUNCTIONS | all |  | — | 1 makes SliceArguments return through FunctionJump's operand; 0 through the stack — SDK's own name |
| 645 | `sharedLenJump` | `KEEP` | parameter of STRING_FUNCTIONS | all |  | — | 1 makes ASC jump through LEN's float conversion — SDK's own name |
| 646 | `zeroTermViaY` | `KEEP` | parameter of STRING_FUNCTIONS | all |  | — | 1 writes VAL's terminator with TYA instead of LDA #0 — SDK's own name |
| 647 | `CHR` | `Functions::Chr` | routine | all | M6502; spelling only: AS82 [AS] | no; alias CHRD in Commodore | Converts the argument to a byte, allocates a one-byte string holding it and pushes it as a temporary — Commodore's CHRD alias |
| 648 | `RLZRET` | `Functions::Chr::ToPushTemporary` | local | all | M6502 | no | JMP PUTNEW — Unreferenced but documented (M6502): kept |
| 649 | `LEFT` | `Functions::Left` | routine | all | M6502; spelling only: AS82 [AS] | no; alias LEFTD in Commodore | Takes the leftmost count characters (all if the count is longer); falls into Functions::Slice — Commodore's LEFTD alias |
| 650 | `RLEFT` | `Functions::Slice` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Shared by LEFT$, RIGHT$ and MID$: allocates the slice, releases the source and copies from its start offset — Entered from Left (fall-through), Right (JMP) and Mid (branches to its entries) |
| 651 | `RLEFT1` | `Functions::Slice::PushStart` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Pushes the start offset |
| 652 | `RLEFT2` | `Functions::Slice::CountInX` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Takes the count from X; Mid branches here — Entered from Mid |
| 653 | `RLEFT3` | `Functions::Slice::CountInA` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Pushes the count in A, allocates it and releases the source descriptor; Mid branches here — Entered from Mid |
| 654 | `PULMOR` | `Functions::Slice::Copy` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Copies the characters and pushes the result |
| 655 | `RIGHT` | `Functions::Right` | routine | all | M6502; spelling only: AS82 [AS] | no; alias RIGHTD in Commodore | Computes the start offset of the rightmost count characters and jumps to Slice — Commodore's RIGHTD alias |
| 656 | `MID` | `Functions::Mid` | routine | all | M6502 | no; alias MIDD in Commodore | Reads the optional length (255 if absent), checks the start, and enters Slice with the shortened count — Commodore's MIDD alias |
| 657 | `MID2` | `Functions::Mid::HaveLength` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Gets the descriptor and start with SliceArguments |
| 658 | `PREAM` | `Functions::SliceArguments` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Requires ')', drops the dispatcher's return and pops the byte argument and the descriptor (DescriptorPointer) — P1's indirect return wraps within the page when the saved low byte is $FF (documented) |
| 659 | `LEN` | `Functions::Len` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Returns the length of the string argument as a number |
| 660 | `LENFLT` | `Functions::Len::ToFloat` | entry | P1 P1R | none found | — | (P1) JMP SNGFLT; ASC jumps here — To + SNGFLT's new name (part A); HV1's LD657 is an address name: no Also |
| 661 | `LEN1` | `Functions::ReleaseArgument` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Releases the string argument (ReleaseFacString), marks the result numeric and returns its length in A and Y — Called by LEN, ASC and VAL |
| 662 | `ASC` | `Functions::Asc` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Returns the first character's code; ILLEGAL QUANTITY for an empty string |
| 663 | `GOFUC` | `Functions::ToIllegalQuantityError` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | JMP FCERR, shared by the string functions, ConvertToByte and MemoryAccess — Reached from several routines and modules, so not a local; see B2-Q5 |
| 664 | `GTBYTC` | `SkipAndEvaluateByte` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Reads past the current character and falls into EvaluateByte — ASTIL entry |
| 665 | `GETBYT` | `EvaluateByte` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | no | Evaluates a numeric expression and falls into ConvertToByte — ASTIL entry |
| 666 | `CONINT` | `ConvertToByte` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Converts FAC to 0-255 in X (ILLEGAL QUANTITY otherwise) and rereads the current character — ASTIL entry |
| 667 | `CHRGO2` | `ConvertToByte::ToGetCurrentCharacter` | local | all | M6502 | no | JMP CHRGOT — Unreferenced but documented (M6502): kept |
| 668 | `VAL` | `Functions::Val` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Parses the string's numeric prefix with FIN, zeroing the byte after it meanwhile; an empty string gives zero — An error in FIN leaves that byte zeroed and TextPointer unrestored (documented, not fixed) |
| 669 | `VAL2` | `Functions::Val::SetEnd` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Saves the byte after the string, writes a terminator and parses the number |
| 670 | `ST2TXT` | `SetTextPointer` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS] | no | Loads TextPointer from SecondStringPointer — After FromText it moves past the scanned text; in VAL it restores the saved pointer |
| 671 | `VALRTS` | `SetTextPointer::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The RTS — Unreferenced but documented (M6502): kept |

### MsBasic.StringGarbageCollection

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 672 | `STRING_GARBAGE_COLLECTION` | `StringGarbageCollection` | macro | AS P1 P1R P2 |  | — | Emits the repeated-scan collector for unlinked strings (GARBA2 through GRBPAS) |
| 673 | `fullDescriptorPointer` | `KEEP` | parameter of STRING_GARBAGE_COLLECTION | AS P1 P1R P2 |  | — | 1 tests both bytes of CollectorPointer, so page-zero temporaries are collected too (P2) — SDK's own name |
| 674 | `patchedArrayStep` | `KEEP` | parameter of STRING_GARBAGE_COLLECTION | AS P1 P1R P2 |  | — | 1 calls the editor ROM's ARYINC for the array step (P1) — SDK's own name |
| 675 | `subtractDescriptorOffset` | `KEEP` | parameter of STRING_GARBAGE_COLLECTION | AS P1 P1R P2 |  | — | 1 forms the descriptor offset by subtracting 3 instead of masking with 4 — SDK's own name |
| 676 | `GARBA2` | `Strings::CollectGarbage` | routine | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | Repeatedly finds the highest live string below StringsBottom among temporaries, scalars and string arrays and moves it up under the strings already collected — P4's linked collector (part F) should take the same name; AS and P1 stop early at a page-zero temporary (documented); ASTIL's GARBAG ($E484) is this routine; GARBAG is also Microsoft's name for ReserveSpace::Collect (B2-Q8) |
| 677 | `FNDVAR` | `Strings::CollectGarbage::NextPass` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Sets StringsBottom to the top of the collected strings, clears the best candidate and starts at the temporaries |
| 678 | `TVAR` | `Strings::CollectGarbage::ScanTemporaries` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Considers each temporary descriptor up to NextTemporary — Not NextTemporary: that is a top-level name |
| 679 | `SVARS` | `Strings::CollectGarbage::StartScalars` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Sets the step to a scalar entry's size and starts at VariablesStart |
| 680 | `SVAR` | `Strings::CollectGarbage::ScanScalars` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Stops at ArraysStart |
| 681 | `SVARGO` | `Strings::CollectGarbage::CheckScalar` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Considers one scalar if it is a string variable |
| 682 | `ARYVAR` | `Strings::CollectGarbage::StartArrays` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Sets ArrayPointer to the arrays and the step to a descriptor's size |
| 683 | `ARYVA2` | `Strings::CollectGarbage::NextArray` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Loads the next array's address |
| 684 | `ARYVA3` | `Strings::CollectGarbage::CheckArraysEnd` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | At ArraysEnd the scan is over: moves the best string |
| 685 | `ARYVGO` | `Strings::CollectGarbage::ReadArray` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Advances ArrayPointer past this array and, for a string array, points Pointer1 at its first element |
| 686 | `ARYGET` | `Strings::CollectGarbage::ElementsReady` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | Loads Pointer1's high byte for the element loop |
| 687 | `ARYSTR` | `Strings::CollectGarbage::ScanElements` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Stops at the array's end (ArrayPointer) |
| 688 | `GOGO` | `Strings::CollectGarbage::CheckElement` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Considers one element's descriptor |
| 689 | `DVARS` | `Strings::CollectGarbage::ConsiderScalar` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Subroutine: skips a scalar that is not a string, then falls into ConsiderDescriptor |
| 690 | `DVAR` | `Strings::CollectGarbage::ConsiderDescriptor` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Subroutine: records a nonempty string below StringsBottom and above the best so far as the new best |
| 691 | `DVAR2` | `Strings::CollectGarbage::CheckBest` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | Compares the string's address with CollectorTop (the best so far) |
| 692 | `DVAR3` | `Strings::CollectGarbage::NewBest` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | Records the string's address in CollectorTop, the descriptor in CollectorPointer and the step in SIZE |
| 693 | `DVARTS` | `Strings::CollectGarbage::Advance` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: AS82 [AS] | no | Adds the step (CollectorStep) to Pointer1 |
| 694 | `GRBRTS` | `Strings::CollectGarbage::Return` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | Returns with X = Pointer1's high byte and Y = 0 (also the collector's exit when nothing is left to move) |
| 695 | `GRBPAS` | `Strings::CollectGarbage::MoveBest` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | Moves the best string up to StringsBottom with BLTUC, rewrites its descriptor's address and starts the next pass — SIZE is reused as the descriptor offset: needs a scoped alias, see glossary list |

### MsBasic.StringOutput

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 696 | `STROUT` | `PrintText` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Prints the text at A:Y up to a quote or zero (via a temporary string) and falls into PrintString — ASTIL entry |
| 697 | `STRPRT` | `PrintString` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Releases the string in FAC and prints its characters, following each carriage return with CRFIN — ASTIL entry; ends by branching to Print's PRTRTS |
| 698 | `STRPR2` | `PrintString::NextCharacter` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Prints the next character until the count runs out |

### MsBasic.StringStorage

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 711 | `STRING_STORAGE` | `StringStorage` | macro | all |  | — | Emits the allocation front ends, literal scanning and the temporary push (STRINI through PUTNEW) |
| 712 | `bufferPage` | `KEEP` | parameter of STRING_STORAGE | all |  | — | The page of InputBuffer, whose literals must be copied; 0 when it is in page zero — SDK's own name (also VariableInput's) |
| 713 | `clearFacOverflow` | `KEEP` | parameter of STRING_STORAGE | all |  | — | 1 clears FacExtension when a temporary is pushed — SDK's own name |
| 714 | `STRINI` | `Strings::AllocateForFac` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Saves FAC's descriptor pointer in DescriptorPointer and falls into Allocate — ASTIL entry |
| 715 | `STRSPA` | `Strings::Allocate` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Reserves A bytes and puts the length and address in NewDescriptor — ASTIL entry |
| 716 | `STRLIT` | `Strings::FromText` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Sets both delimiters to a quote and falls into FromTextUntil — ASTIL entry |
| 717 | `STRLT2` | `Strings::FromTextUntil` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Scans the text at A:Y to zero, Delimiter or EndDelimiter, copies it if it is in page zero or InputBuffer, and pushes the temporary — ASTIL entry; the terminator must be within 256 bytes |
| 718 | `STRGET` | `Strings::FromTextUntil::Scan` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Reads characters until a terminator |
| 719 | `STRFIN` | `Strings::FromTextUntil::AtDelimiter` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Sets carry to skip a closing quote |
| 720 | `STRFI1` | `Strings::FromTextUntil::AtZero` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Clears carry: the terminator is not skipped |
| 721 | `STRFI2` | `Strings::FromTextUntil::SetLength` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stores the length and the end position in SecondStringPointer |
| 722 | `STRST2` | `Strings::FromTextUntil::CheckPage` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Chooses copying by the text's page |
| 723 | `STRCP` | `Strings::FromTextUntil::CopyText` | local | all | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | no | Allocates and copies the text into string space — Falls into PushTemporary |
| 724 | `PUTNEW` | `Strings::PushTemporary` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Copies NewDescriptor to the next temporary descriptor, points FAC at it and marks a string; FORMULA TOO COMPLEX when full — ASTIL entry |
| 725 | `ERRGO2` | `Strings::PushTemporary::ToError` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | JMP ERROR; both allocators branch here with OUT OF MEMORY — To + ERROR's new name (another part) |
| 726 | `PUTNW1` | `Strings::PushTemporary::Store` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stores the descriptor and advances NextTemporary and LastTemporary |
| 727 | `STRING_ALLOCATION` | `StringAllocation` | macro | all |  | — | Emits GETSPA with the unlinked or linked body |
| 728 | `linkedStrings` | `KEEP` | parameter of STRING_ALLOCATION | all |  | — | 1 selects BASIC 4's linked allocator — SDK's own name |
| 729 | `GETSPA` | `Strings::ReserveSpace` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R]; spelling only: AS82 [AS] | no | Reserves A bytes below StringsBottom, collecting garbage once if needed; X/Y and NewString = the address — ASTIL entry; Commodore's disk commands call it |

### MsBasic.StringStorage.Classic

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 699 | `UNLINKED_STRING_ALLOCATION` | `UnlinkedStringAllocation` | macro | AS P1 P1R P2 |  | — | Emits the ordinary allocator's body after GETSPA |
| 700 | `TRYAG2` | `Strings::ReserveSpace::Try` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | Computes StringsBottom minus the length — Same job as the linked TRYAG2 |
| 701 | `TRYAG3` | `Strings::ReserveSpace::CheckRoom` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | Compares the new bottom with ArraysEnd (equality fits) — Linked builds' TRYAG3 is another step; their TRYAG4 is this one |
| 702 | `STRFRE` | `Strings::ReserveSpace::Take` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2 | no | Sets StringsBottom and NewString to the new bottom; returns X/Y = address, A = length |
| 703 | `GARBAG` | `Strings::ReserveSpace::Collect` | local | AS P1 P1R P2 | M6502, HV1, HV1R, HV2; spelling only: ASTIL [AS], AS82 [AS] | no | Collects once (OUT OF MEMORY if already collected) and retries a nonempty request — A zero-length failure falls out of the macro into CollectGarbage a second time (documented); Apple's GARBAG (Orchard) names CollectGarbage: see B2-Q8 |

### MsBasic.StringStorage.Linked

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 704 | `LINKED_STRING_ALLOCATION` | `LinkedStringAllocation` | macro | P4 P4R |  | — | Emits BASIC 4's allocator body, which adds a two-byte link after each string |
| 705 | `TRYAG2` | `Strings::ReserveSpace::Try` | local | P4 P4R | M6502, CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Returns at once for length 0, else computes the link address below StringsBottom |
| 706 | `TRYAG3` | `Strings::ReserveSpace::BelowLink` | local | P4 P4R | M6502, CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Saves the link address in Pointer1 and subtracts the length |
| 707 | `TRYAG4` | `Strings::ReserveSpace::CheckRoom` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Compares the new bottom with ArraysEnd |
| 708 | `STRFRE` | `Strings::ReserveSpace::Take` | local | P4 P4R | M6502, CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Writes the garbage link (length, $FF) and sets NewString and StringsBottom |
| 709 | `GETRTS` | `Strings::ReserveSpace::Done` | local | P4 P4R | M6502, CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) The RTS |
| 710 | `GARBAG` | `Strings::ReserveSpace::Collect` | local | P4 P4R | M6502, CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Collects once (OUT OF MEMORY if already collected) and retries |

### MsBasic.Switches

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 730 | `REALIO` | `KEEP` | switch | none |  | — | Microsoft's I/O target: 3 Commodore, 4 Apple — predefined by C# and tests: KEEP |
| 731 | `INTPRC` | `INTEGER_VARIABLES` | switch | all | M6502 | no | 1 includes integer variables and arrays (asserted 1) — Microsoft's INTPRC in Also |
| 732 | `ADDPRC` | `ADDITIONAL_PRECISION` | switch | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | 1 adds the fifth float byte; code uses it as that byte count (8+ADDPRC) — Microsoft's ADDPRC in Also |
| 733 | `LNGERR` | `LONG_ERRORS` | switch | all | M6502 | no | 1 uses full error messages (asserted 1) — Microsoft's LNGERR in Also |
| 734 | `TIME` | `KEEP` | switch | all | M6502; spelling only: K4S79 [P4 P4R], HVK4 [P4 P4R] | no | selects FormatFac's TI$ path and table — predefined by C# and tests: KEEP |
| 735 | `EXTIO` | `KEEP` | switch | all | M6502 | no | legacy external-I/O setting, asserted per build — predefined by C# and tests: KEEP |
| 736 | `DISKO` | `KEEP` | switch | all | M6502 | no | legacy disk-I/O setting, asserted per build — predefined by C# and tests: KEEP |

### MsBasic.TranscendentalCore

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 737 | `POWER_ROUTINES` | `PowerRoutines` | macro | all |  | — | emits Functions::Sqr, RaiseArg and Negate |
| 738 | `SQR` | `Functions::Sqr` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | SQR: copies Fac to Arg, loads Half into Fac and falls into Float::RaiseArg — Falls into Float::RaiseArg; see A-Q3 |
| 739 | `FPWRT` | `Float::RaiseArg` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Fac = Arg ^ Fac: zero power is EXP(0) = 1, zero base gives zero, a negative base needs a whole power (its parity sets the sign) — operator-table target for '^' |
| 740 | `FPWRT1` | `Float::RaiseArg::NonzeroBase` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | saves the power in FloatTemporary3; for a negative base checks the power is whole and takes its parity |
| 741 | `FPWR1` | `Float::RaiseArg::TakeLog` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Fac = Arg, then EXP(power * LOG(base)), negated for an odd power |
| 742 | `NEGOP` | `Float::Negate` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | flips FacSign unless Fac is zero — ASTIL (NEGOP); operator-table target for unary minus; ReadNumber and the functions call it |
| 743 | `NEGRTS` | `Float::Negate::Done` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the shared rts — reached from RaiseArg for an even power; see A-Q4 |
| 744 | `EXP_ROUTINE` | `ExponentialRoutine` | macro | all |  | — | emits Functions::Exp — EXP_ROUTINE in full words |
| 745 | `EXP` | `Functions::Exp` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | EXP: multiplies by LogBase2OfE, splits off the integer part to scale by a power of two and evaluates ExponentialPolynomial on the fraction — RaiseArg calls it; see A-Q3 |
| 746 | `STOLD` | `Functions::Exp::CheckRange` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | saves the rounding byte, copies Fac to Arg; exponent $88 or more is out of range |
| 747 | `GOMLDV` | `Functions::Exp::OutOfRange` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | ExponentOutOfRange: OVERFLOW for a large positive argument, zero for a large negative one |
| 748 | `EXP1` | `Functions::Exp::Reduce` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | takes the integer part (Functions::Int) for the power of two and keeps the fraction |
| 749 | `SWAPLP` | `Functions::Exp::SwapLoop` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | exchanges Fac and Arg byte by byte |
| 750 | `POLYNOMIAL_ROUTINES` | `PolynomialRoutines` | macro | all |  | — | emits EvaluateOddPolynomial and EvaluatePolynomial |
| 751 | `POLYX` | `Float::EvaluateOddPolynomial` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | evaluates x * P(x^2) for x in Fac, with the table at Y:A — LOG, SIN and ATN call it |
| 752 | `POLY` | `Float::EvaluatePolynomial` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores the table at Y:A in PolynomialPointer and falls into EvaluateStoredPolynomial — Functions::Exp calls it |
| 753 | `POLY1` | `Float::EvaluateStoredPolynomial` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | evaluates P(Fac) by Horner's rule from the table PolynomialPointer points to (degree, then packed coefficients) — EvaluateOddPolynomial calls it |
| 754 | `POLY3` | `Float::EvaluateStoredPolynomial::SetPointer` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | stores the first coefficient's address |
| 755 | `POLY2` | `Float::EvaluateStoredPolynomial::NextTerm` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | multiplies by x (FloatTemporary2) and steps to the next coefficient |
| 756 | `POLY4` | `Float::EvaluateStoredPolynomial::AddTerm` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | adds the coefficient; loops PolynomialDegree times |
| 757 | `RANDRT` | `Float::EvaluateStoredPolynomial::Done` | entry | all | M6502 | no | the shared rts — reached from Functions::Rnd; see A-Q4 |
| 758 | `TRIG_ROUTINES` | `TrigonometricRoutines` | macro | all |  | — | emits Functions::Cos, Functions::Sin and Functions::Tan — TRIG_ROUTINES in full words |
| 759 | `COS` | `Functions::Cos` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | COS: adds HalfPi and falls into Functions::Sin — see A-Q3 |
| 760 | `SIN` | `Functions::Sin` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | SIN: divides by TwoPi, keeps the fraction, folds the quadrant into [-1/4,1/4] and evaluates SinePolynomial — Functions::Tan calls it |
| 761 | `SIN1` | `Functions::Sin::Reflect` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | negates Fac (Float::Negate) — reached from Functions::Tan::Cosine; see A-Q4 |
| 762 | `SIN2` | `Functions::Sin::AddQuarter` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | adds Quarter; restores a negative quadrant's sign |
| 763 | `SIN3` | `Functions::Sin::Approximate` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | points Y:A at SinePolynomial |
| 764 | `GPOLYX` | `Functions::Sin::ToEvaluateOddPolynomial` | local | all | M6502 | no | jumps on to Float::EvaluateOddPolynomial — nothing references it (the code falls into it); M6502 names it, so kept |
| 765 | `TAN` | `Functions::Tan` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | TAN: saves x, computes the sine, then the cosine from x's magnitude and the quadrant sign, and divides — see A-Q3 |
| 766 | `GFDIV` | `Functions::Tan::ToDividePacked` | local | all | M6502 [PET] | yes: Commodore | jumps on to Float::DividePacked: sine / cosine — nothing references it; M6502 gives the name for PET builds only (vendor), see A-Q1 |
| 767 | `COSC` | `Functions::Tan::Cosine` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | pushes the quadrant sign and joins Functions::Sin::Reflect — called only by Tan; placed after its last jump |
| 768 | `ATN_ROUTINE` | `ArctangentRoutine` | macro | all |  | — | emits Functions::Atn — ATN_ROUTINE in full words |
| 769 | `ATN` | `Functions::Atn` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | ATN: takes the magnitude, uses its reciprocal above 1 (subtracting from HalfPi after), evaluates ArctangentPolynomial and restores the sign — see A-Q3 |
| 770 | `ATN1` | `Functions::Atn::Positive` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | pushes the exponent; above 1 takes the reciprocal (One / Fac) |
| 771 | `ATN2` | `Functions::Atn::Approximate` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | evaluates ArctangentPolynomial and subtracts from HalfPi if the reciprocal was taken |
| 772 | `ATN3` | `Functions::Atn::RestoreSign` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | negates for a negative argument |
| 773 | `ATN4` | `Functions::Atn::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | the rts |

### MsBasic.UserFunctions

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 774 | `USER_FUNCTIONS` | `UserFunctions` | macro | all |  | — | emits RejectDirectMode, DEF, ReadFunctionName, FN and PopToFunctionPointer (x1) |
| 775 | `earlyCheck` | `KEEP` | parameter of USER_FUNCTIONS | all |  | — | BASIC 1's undefined test on the low byte; already descriptive |
| 776 | `ERRDIR` | `RejectDirectMode` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | CurrentLine+1 = $FF: ILLEGAL DIRECT; else returns through DIMRTS — used by DEF, INPUT, GET |
| 777 | `ERRGUF` | `RejectDirectMode::UndefinedFunction` | entry | AS P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | no | X = UNDEF'D FUNCTION, skipped by ILLEGAL DIRECT's BIT; FN enters here |
| 778 | `ERRGO1` | `RejectDirectMode::ToError` | entry | all | M6502, HV1, HV1R | no | jmp ERROR; BASIC 1's FN enters here |
| 779 | `DEF` | `Statements::Def` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | ReadFunctionName, RejectDirectMode, (argument) =; pushes the argument pointer and text pointer, skips the formula, stores them |
| 780 | `GETFNM` | `ReadFunctionName` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | requires FN, sets the function bit, PTRGT2 finds or creates it; FunctionPointer = its value; must be numeric — shared by DEF and FN |
| 781 | `FNDOER` | `Functions::Fn` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | evaluates the argument, saves the variable's value and TextPointer, evaluates the formula with the argument, restores both — bug documented: the early check rejects an argument at a $xx00 address |
| 782 | `DEFSTF` | `Functions::Fn::SaveArgument` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | pushes the argument variable's five bytes |
| 783 | `DEFFIN` | `PopToFunctionPointer` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | pops five bytes into (FunctionPointer),0..4 — DEF jumps here; FN falls into it |
| 784 | `DEFRTS` | `PopToFunctionPointer::Done` | local | all | M6502 | no | the rts — kept unreferenced: documented (M6502) |

### MsBasic.VariableInput

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 785 | `VARIABLE_INPUT` | `VariableInput` | macro | all |  | — | Emits READ and the GET/INPUT/READ variable loop (READ through INPRTS) |
| 786 | `bufferPage` | `KEEP` | parameter of VARIABLE_INPUT | all |  | — | The page of InputBuffer; 0 when it is in page zero, which changes READ's flag trick — SDK's own name (also StringStorage's) |
| 787 | `maskGetBit7` | `KEEP` | parameter of VARIABLE_INPUT | all |  | — | 1 clears bit 7 of a GET character (AS) — SDK's own name |
| 788 | `getPointerYFirst` | `KEEP` | parameter of VARIABLE_INPUT | all |  | — | 1 loads the GET buffer pointer's high byte first (P1) — SDK's own name |
| 789 | `patchedGetString` | `KEEP` | parameter of VARIABLE_INPUT | all |  | — | 1 calls the editor ROM's GETSTR patch for a GET string (P1) — SDK's own name |
| 790 | `channelInput` | `KEEP` | parameter of VARIABLE_INPUT | all |  | — | 1 skips the prompt and the EXTRA IGNORED warning when an input channel is selected (PET) — SDK's own name |
| 791 | `blankNumericRetry` | `KEEP` | parameter of VARIABLE_INPUT | all |  | — | 1 retries an empty numeric INPUT instead of reading zero (AS) — SDK's own name |
| 792 | `READ` | `Statements::Read` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: ASTIL [AS], AS82 [AS], K4S79 [P4 P4R], HVK4 [P4 P4R] | no | Points X/Y at DataPointer and enters AssignVariableList with InputMode $98, skipping AssignInputList's flag load — Falls into AssignInputList (its first instruction skipped) |
| 793 | `INPCON` | `AssignInputList` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | INPUT's entry: A = 0 (the cursor's high byte for a page-zero buffer) and falls into AssignVariableList — Vendors' INPUT call it; see B2-Q10 (InputMode constants) |
| 794 | `INPCO1` | `AssignVariableList` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Assigns a GET character, an INPUT field or a DATA item to each variable in the list, then saves READ's position or warns of extra input — Vendors' GET call it with A = $40 |
| 795 | `INLOOP` | `AssignVariableList::NextVariable` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Finds the next variable, saves the list position and switches TextPointer to the input cursor |
| 796 | `QDATA` | `AssignVariableList::SourceEmpty` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The input is used up: READ searches for DATA; INPUT prompts (unless on a channel) and reads a line |
| 797 | `GETNTH` | `AssignVariableList::ReadAnotherLine` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Reads a line with QINLIN — Not ReadLine: QINLIN's new name (part C) may be that |
| 798 | `DATBK` | `AssignVariableList::SetCursor` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Sets TextPointer to X/Y |
| 799 | `DATBK1` | `AssignVariableList::NextValue` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Reads the next character and branches by the variable's type and the input mode |
| 800 | `SETQUT` | `AssignVariableList::SetDelimiters` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | A quote delimits a quoted string; otherwise colon and comma end it |
| 801 | `RESETC` | `AssignVariableList::StringAtCursor` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Clears carry so the string starts at the current character; P1's GETSTR patch jumps back here — Entered from the BASIC 1 editor patch |
| 802 | `NOWGET` | `AssignVariableList::MakeString` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Builds the string with FromTextUntil, moves TextPointer past it and assigns it with AssignString |
| 803 | `NOWGE1` | `AssignVariableList::HaveAddress` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Text address in A/Y: makes and assigns the string |
| 804 | `NOWGE2` | `AssignVariableList::CheckEmptyLine` | local | AS | none found | — | (AS) Numeric value: saves the character and checks for an empty input line |
| 805 | `NOWGE3` | `AssignVariableList::RestoreCharacter` | local | AS | none found | — | (AS) Pulls the saved character back |
| 806 | `NUMINS` | `AssignVariableList::ConvertNumber` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Parses the number with FIN and stores it with StoreNumber |
| 807 | `STRDN2` | `AssignVariableList::CheckTerminator` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Accepts end of statement or a comma after the value; otherwise jumps to the vendor's TRMNOK |
| 808 | `TRMOK` | `AssignVariableList::TerminatorOk` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Saves the input cursor, returns to the variable list and continues after a comma |
| 809 | `TRMOK1` | `AssignVariableList::EmptyNumber` | local | AS | none found | — | (AS) Empty line: READ and GET go on; INPUT jumps to SNERR6 to ask again |
| 810 | `DATLOP` | `AssignVariableList::SearchData` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Skips to the next statement with DATAN, noting each new line in DataLine; OUT OF DATA at the end of the program |
| 811 | `NOWLIN` | `AssignVariableList::CheckStatement` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Reads the statement's first token and loops until it is DATA |
| 812 | `VAREND` | `AssignVariableList::ListDone` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | READ saves its position with RESFIN; INPUT checks for unused input |
| 813 | `VARY0` | `AssignVariableList::CheckExtra` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Prints EXTRA IGNORED when input remains (not on a channel) |
| 814 | `INPRTS` | `AssignVariableList::Done` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | The RTS |
| 815 | `VARIABLE_INPUT_MESSAGES` | `VariableInputMessages` | macro | all |  | — | Emits the EXTRA IGNORED and retry messages after VariableInput |
| 816 | `shortRetry` | `KEEP` | parameter of VARIABLE_INPUT_MESSAGES | all |  | — | 1 for "?REENTER" (AS), 0 for "?REDO FROM START" — SDK's own name |
| 817 | `lineFeed` | `KEEP` | parameter of VARIABLE_INPUT_MESSAGES | all |  | — | 1 follows each carriage return with a line feed (P1, P2) — SDK's own name |
| 818 | `EXIGNT` | `ExtraIgnoredMessage` | message | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Zero-terminated "?EXTRA IGNORED" warning that AssignVariableList prints with PrintText |
| 819 | `TRYAGN` | `RetryMessage` | message | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Zero-terminated "?REDO FROM START" or "?REENTER" that the vendors' bad-input handlers print |

### MsBasic.VariableLookup

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 820 | `VARIABLE_NAME` | `VariableSearch` | macro | all |  | — | Emits FindVariable's name parser and scalar search (PTRGET through NOTIT) — Not VariableName: that is the glossary's location (VARNAM) |
| 821 | `fixedVectors` | `KEEP` | parameter of VARIABLE_NAME | all |  | — | 1 emits Apple's fixed jumps at $E000 inside FindVariable (AS) — SDK's own name |
| 822 | `vectorByte` | `KEEP` | parameter of VARIABLE_NAME | all |  | — | The model byte Apple keeps at $E006 — SDK's own name |
| 823 | `rejectAnyFlag` | `KEEP` | parameter of VARIABLE_NAME | all |  | — | 1 rejects '%' for any nonzero SubscriptsAllowed, 0 tests only bit 7 — SDK's own name |
| 824 | `existingArrays` | `KEEP` | parameter of VARIABLE_NAME | all |  | — | 1 assembles Apple's existing-array (STORE/RECALL) path — SDK's own name; same parameter name in ArrayLookup |
| 825 | `clearWithY` | `KEEP` | parameter of VARIABLE_NAME | all |  | — | 1 clears SubscriptsAllowed with LDY/STY — SDK's own name; same parameter name in ArrayLookup |
| 826 | `longFound` | `KEEP` | parameter of VARIABLE_NAME | all |  | — | 1 reaches ValueAddress with a JMP (P4, too far for a branch) — SDK's own name |
| 827 | `PTRGET` | `FindVariable` | routine | all | M6502, ASTIL [AS], CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: AS82 [AS] | no | Parses a variable name (two significant characters, '$' or '%' suffix), searches the simple variables and returns its value's address in A/Y; arrays and absent names go on elsewhere — ASTIL entry; branches to Variables::NotFound, Variables::ValueAddress or (JMP) Variables::FindArray |
| 828 | `PTRGT1` | `FindVariable::WithDimensionFlag` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Starts with A = the first character and X = Dimensioning; DIM enters here — Entered from Statements::Dim |
| 829 | `PTRGT2` | `FindVariable::KeepDimensionFlag` | entry | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Starts with A = the first character, keeping Dimensioning; DEF FN enters here — Entered from UserFunctions |
| 830 | `INTERR` | `FindVariable::ToSyntaxError` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | JMP SNERR for a bad first character or a forbidden '%' |
| 831 | `PTRGT3` | `FindVariable::ValidFirst` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Clears ValueType and IntegerType and reads the second character — AS: jumps over the fixed vectors here |
| 832 | `PTRGT4` | `FindVariable::AfterVectors` | local | AS | none found | — | (AS) The code after Apple's fixed jumps at $E000 (INIT, MAIN, the model byte) — See B2-Q11 ($E000 vectors inside FindVariable) |
| 833 | `ISSEC` | `FindVariable::SecondCharacter` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Keeps a letter or digit as the second name character |
| 834 | `EATEM` | `FindVariable::SkipRest` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Consumes further letters and digits |
| 835 | `NOSEC` | `FindVariable::CheckSuffix` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | '$' makes a string: sets ValueType and the second byte's bit 7 |
| 836 | `NOTSTR` | `FindVariable::CheckInteger` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | '%' makes an integer (SYNTAX where subscripts are not allowed) and sets both bytes' bit 7 |
| 837 | `TURNON` | `FindVariable::MarkSecond` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Sets bit 7 of the second name byte and consumes the suffix |
| 838 | `STRNAM` | `FindVariable::CheckSubscript` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stores the second byte and compares the next character, ORed with SubscriptsAllowed, with '(' |
| 839 | `STRNA1` | `FindVariable::ToChooseArrayLookup` | local | AS | none found | — | (AS) JMP QINTG1 |
| 840 | `STRNA2` | `FindVariable::NoParenthesis` | local | AS | none found | — | (AS) No '(': bit 7 of SubscriptsAllowed searches scalars, bit 6 goes to the existing-array lookup |
| 841 | `STRNA3` | `FindVariable::SearchScalars` | local | AS | none found | — | (AS) Same address as SCALAR_SEARCH — Merge with SCALAR_SEARCH: one label, branches to FindVariable::SearchScalars; STRNA3 has no document, so no Also |
| 842 | `SCALAR_SEARCH` | `FindVariable::SearchScalars` | local | all | none found | — | Clears SubscriptsAllowed and starts at VariablesStart — SDK's own label; renamed to the style |
| 843 | `STXFND` | `FindVariable::SetEntryHigh` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stores the entry pointer's high byte (start, and on a page crossing) |
| 844 | `LOPFND` | `FindVariable::CheckEnd` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stores the low byte; at ArraysStart the name is not found |
| 845 | `LOPFN` | `FindVariable::CompareName` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Compares both name bytes with VariableName |
| 846 | `NXTPTR` | `FindVariable::SecondMismatch` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Second byte differs: restores Y |
| 847 | `NOTIT` | `FindVariable::Advance` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Adds an entry's seven bytes and loops — Falls into ISLETC if the table wraps past $FFFF (unreachable; documented, not fixed) |
| 848 | `SIMPLE_VARIABLE_LOOKUP` | `SimpleVariableLookup` | macro | all |  | — | Emits absent-variable handling, scalar creation and the value and array-data address helpers (NOTFNS through JSRGM) |
| 849 | `checkCallerHigh` | `KEEP` | parameter of SIMPLE_VARIABLE_LOOKUP | all |  | — | 1 also compares the return address's high byte with ISVRET (AS) — SDK's own name |
| 850 | `inlineZero` | `KEEP` | parameter of SIMPLE_VARIABLE_LOOKUP | all |  | — | 1 emits the two zero bytes here (AS, P1) — SDK's own name |
| 851 | `useSimzer` | `KEEP` | parameter of SIMPLE_VARIABLE_LOOKUP | all |  | — | 1 names the zero SIMZER (AS), 0 ZERO — SDK's own name; after renaming it only chooses the Also: name, see B2-Q12 |
| 852 | `clockNames` | `KEEP` | parameter of SIMPLE_VARIABLE_LOOKUP | all |  | — | 1 rejects TI and reads TI$ as the zero (PET) — SDK's own name |
| 853 | `statusName` | `KEEP` | parameter of SIMPLE_VARIABLE_LOOKUP | all |  | — | 1 rejects ST (PET) — SDK's own name |
| 854 | `diskNames` | `KEEP` | parameter of SIMPLE_VARIABLE_LOOKUP | all |  | — | 1 rejects DS and DS$ (P4) — SDK's own name |
| 855 | `linkedArrays` | `KEEP` | parameter of SIMPLE_VARIABLE_LOOKUP | all |  | — | 1 adjusts BASIC 4's string back-links after moving the arrays (P4) — SDK's own name |
| 856 | `arrayEntryAlias` | `KEEP` | parameter of SIMPLE_VARIABLE_LOOKUP | all |  | — | 1 labels ElementsStart's entry with the count in A (AS) — SDK's own name |
| 857 | `NOTFNS` | `Variables::NotFound` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | A name not in the table: the expression evaluator's operand gets the zero (no entry made); others go on to CheckReservedName — PET compares only the return address's low byte (documented); falls into ReturnZero |
| 858 | `LDZR` | `Variables::ReturnZero` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Returns A/Y = the address of the zero bytes — Entered by fall-through and from CheckReservedName (TI$) |
| 859 | `SIMZER` | `ZeroVariable` | data | AS | none found | — | (AS) Two zero bytes an absent variable reads — AS also has ZERO (part A) elsewhere: a separate name is needed; see B2-Q12 |
| 860 | `ZERO` | `ZeroValue` | data | P1 P1R | M6502, HV1, HV1R | no | (P1) The zero bytes an absent variable reads; P1 has no ZERO in FHALF — Must match part A's name for ZERO (same job); see B2-Q12 |
| 861 | `NOTEVL` | `Variables::CheckReservedName` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | (PET) Rejects TI, ST and (P4) DS/DS$ with SYNTAX, returns the zero for TI$; falls into Create — In AS it is empty and shares Create's address |
| 862 | `GOBADV` | `Variables::CheckReservedName::ToSyntaxError` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | (PET) JMP SNERR for a reserved name |
| 863 | `QSTAVR` | `Variables::CheckReservedName::CheckStatus` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | (PET) Checks for ST |
| 864 | `QDSVAR` | `Variables::CheckReservedName::CheckDiskStatus` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Checks for DS and DS$ |
| 865 | `VAROK` | `Variables::Create` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Moves the arrays up seven bytes with BLTU, writes the name and five zero bytes and falls into ValueAddress — P4 also adjusts the moved arrays' string back-links |
| 866 | `NOTEVE` | `Variables::Create::SetNewEnd` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stores the arrays' new end and moves them |
| 867 | `ARYVA2` | `Variables::Create::NextArray` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Loads the next array's address — Same job and name as CollectGarbage::NextArray |
| 868 | `ARYVA3` | `Variables::Create::CheckArraysEnd` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Stops at ArraysEnd |
| 869 | `ARYVGO` | `Variables::Create::ReadArray` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Advances ArrayPointer past the array and, for a string array, points Pointer1 at its first element |
| 870 | `ARYGET` | `Variables::Create::ScanElements` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Stops at the array's end |
| 871 | `GOGO` | `Variables::Create::CheckElement` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Skips an empty string or one below StringsBottom |
| 872 | `GOGO1` | `Variables::Create::MoveLink` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Adds 7 to the back-link after the string's characters |
| 873 | `DVARTS` | `Variables::Create::Advance` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Steps Pointer1 to the next descriptor |
| 874 | `ARYDON` | `Variables::Create::WriteEntry` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | no | (P4) Back-links done: writes the new entry |
| 875 | `FINPTR` | `Variables::ValueAddress` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Returns the address two bytes into the entry at SourceStart in A/Y and VariablePointer — FindVariable branches (P4: jumps) here when found |
| 876 | `FINNOW` | `Variables::ValueAddress::Store` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stores VariablePointer and returns |
| 877 | `FMAPTR` | `Variables::ElementsStart` | routine | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Sets ArrayPointer to the first value after the header: SourceStart + 5 + 2 x the dimension count in Counter — Called by FindArray's paths and CreateArray |
| 878 | `FMAPT1` | `Variables::ElementsStart::FromCount` | entry | AS | none found | — | (AS) Same with the dimension count in A; STORE/RECALL call it — Entered from AppleSoft.PlatformHelpers |
| 879 | `JSRGM` | `Variables::ElementsStart::Store` | local | all | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | no | Stores ArrayPointer and returns |
| 880 | `EXISTING_ARRAY_ENTRY` | `ExistingArrayEntry` | macro | AS |  | — | Emits Apple's choice between subscripts and the existing-array lookup (QINTG1) |
| 881 | `QINTG1` | `Variables::ChooseArrayLookup` | routine | AS | none found | — | (AS) With SubscriptsAllowed nonzero skips subscripts to FindArray::Search; else falls into FindArray — Reached by FindVariable's JMP |

### AppleSoft

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1442 | `ENHNCD` | `KEEP` | switch | none |  | vendor | 1 builds the Enhanced IIe changes — KEEP: predefined by C# and tests |
| 1443 | `APLPLS` | `KEEP` | switch | IIeE |  | vendor | 1 builds the II Plus final byte (with ENHNCD = 0) — KEEP: predefined by C# and tests |

### AppleSoft.AppleCommands

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 882 | `CALL` | `Statements::Call` | routine | AS | spelling only: AS82 [AS] | vendor | CALL: evaluates an address into LineNumber and jumps through it; the called code's RTS returns to the statement loop. |
| 883 | `INNUM` | `Statements::InNumber` | routine | AS | spelling only: AS82 [AS] | vendor | IN#: reads a byte and selects that slot for input through the Monitor's SetInput. — named like DOS's Commands::PrNumber; see E-Q4 |
| 884 | `PRNUM` | `Statements::PrNumber` | routine | AS | none found | vendor | PR#: reads a byte and selects that slot for output through the Monitor's SetOutput. — same name as DOS's Commands::PrNumber (another scope) |
| 885 | `PLOTFN` | `ReadLowResCoordinates` | routine | AS | other names here: PLOTFNS (ASTIL) | vendor | Reads two comma-separated bytes below 48: the first into FIRST, the second into X, HorizontalLineEnd and VerticalLineEnd. — Also: PLOTFNS (ASTIL); top level because SCRN (QSTAT1, Expressions) calls it and the TIL documents it |
| 886 | `PLOTF1` | `ToIllegalQuantity` | routine | AS | none found | vendor | Only jumps on to FCERR (illegal quantity); the lo-res, cursor and hi-res argument checks branch here because FCERR is out of range. — its own proc: it follows ReadLowResCoordinates' rts and seven routines in two modules reach it; name follows FCERR's new name; see E-Q7 |
| 887 | `LINFNS` | `Statements::ReadLowResLine` | routine | AS | none found | vendor | Reads a lo-res line's two endpoints, ordering them (FIRST = lower, HorizontalLineEnd/VerticalLineEnd = higher), then AT and a third byte below 48 in X. — helper of HLin and VLin only, so in Statements |
| 888 | `LINFN1` | `Statements::ReadLowResLine::ReadAt` | local | AS | none found | vendor | Requires the AT token and reads the line's row or column below 48 into X. |
| 889 | `PLOT` | `Statements::Plot` | routine | AS | spelling only: AS82 [AS] | vendor | PLOT: reads the coordinates, checks the column is below 40, and plots through the Monitor's LowRes::Plot. |
| 890 | `HLIN` | `Statements::HLin` | routine | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | HLIN: reads the line, checks the right end is below 40, and draws it through the Monitor's LowRes::HorizontalLine. — ASTIL's HLIN is the hi-res line at $F53A (HighRes::Line), not this; see E-Q3 |
| 891 | `VLIN` | `Statements::VLin` | routine | AS | spelling only: AS82 [AS] | vendor | VLIN: reads the line, checks the AT column is below 40, and draws it through the Monitor's LowRes::VerticalLine. |
| 892 | `COLSTM` | `Statements::Color` | routine | AS | none found | vendor | COLOR=: reads a byte and passes it to the Monitor's LowRes::SetColor. |
| 893 | `VTAB` | `Statements::VTab` | routine | AS | spelling only: AS82 [AS] | vendor | VTAB: reads a row from 1 to 24 and moves the cursor there through the Monitor's VerticalTabTo. |
| 894 | `SPEED` | `Statements::Speed` | routine | AS | spelling only: AS82 [AS] | vendor | SPEED=: reads a byte and stores its negation (256 minus it) in SPEEDZ, the output delay. |
| 895 | `TRACE` | `Statements::Trace` | routine | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | TRACE: sets carry and skips NoTrace's CLC (a BCC opcode byte), so the ROR sets bit 7 of TRCFLG. — falls into NoTrace past its first byte |
| 896 | `NOTRAC` | `Statements::NoTrace` | routine | AS | none found | vendor | NOTRACE: clears carry and rotates it into bit 7 of TRCFLG, turning tracing off. |
| 897 | `NRMSTM` | `Statements::Normal` | routine | AS | none found | vendor | NORMAL: sets InverseMask to $FF and clears the flash mask through SetInverseMask. — also called by the cold start (Initialization) |
| 898 | `INVERS` | `Statements::Inverse` | routine | AS | none found | vendor | INVERSE: loads the inverse mask $3F and falls into SetInverseMask. — falls into Statements::SetInverseMask |
| 899 | `INVER1` | `Statements::SetInverseMask` | routine | AS | none found | vendor | Clears X (no flash) and falls into SetTextMasks, storing A as InverseMask. — its own proc: Normal branches to it and Inverse falls into it; falls into SetTextMasks; avoids the Monitor's top-level SetInverse |
| 900 | `INVER2` | `Statements::SetTextMasks` | routine | AS | none found | vendor | Stores A in InverseMask and X in FLASHB, the masks output applies to text. — its own proc: Flash branches to it |
| 901 | `FLASH` | `Statements::Flash` | routine | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | FLASH: sets InverseMask to $7F and FLASHB to $40 through SetTextMasks. |
| 902 | `HIMEM` | `Statements::HiMem` | routine | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | HIMEM: evaluates an address; if not below ArraysEnd, sets MemoryTop and StringsBottom to it, else out of memory. — strings already above the new top are abandoned, not moved (document, not fix) |
| 903 | `HIMEM1` | `Statements::HiMem::ToOutOfMemory` | entry | AS | none found | vendor | Only jumps on to OMERR (out of memory); LoMem branches here too. — reached from LoMem; Proc::Label entry per the Monitor's ReadCassette::Finish; see E-Q1 |
| 904 | `HIMEM2` | `Statements::HiMem::SetMemoryTop` | local | AS | none found | vendor | Stores LineNumber in MemoryTop and StringsBottom. |
| 905 | `LOMEM` | `Statements::LoMem` | routine | AS | spelling only: AS82 [AS] | vendor | LOMEM: evaluates an address; if below MemoryTop and not below VariablesStart, sets VariablesStart and clears variables (CLEARC), else out of memory. |
| 906 | `ONERR` | `Statements::OnErr` | routine | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | ONERR: requires GOTO, saves TextPointer in TXTPSV and CurrentLine in CURLSV, sets bit 7 of ERRFLG, then skips the rest of the statement. |
| 907 | `HANDLE` | `TrapError` | routine | AS | other names here: HANDLERR (ASTIL) | vendor | With X = the error code, saves it, REMSTK, CurrentLine and StoppedText for RESUME, restores the ONERR position and line, and runs its GOTO. — Also: HANDLERR (ASTIL); top level: the error, input and control-flow modules jump here |
| 908 | `RESUME` | `Statements::Resume` | routine | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | RESUME: restores CurrentLine, TextPointer and the stack pointer saved at the error, then continues at NXTCO1. — ASTIL lists RESUME at $F317, its dispatch value (address minus one); see E-Q3 |
| 909 | `RESUM1` | `Statements::ToSyntaxError` | routine | AS | none found | vendor | Only jumps on to SNERR; Del branches here when its argument does not start with a digit. — its own proc: it follows Resume's jmp; see E-Q7 |
| 910 | `DEL` | `Statements::Del` | routine | AS | spelling only: AS82 [AS] | vendor | DEL: finds the first line and the line after the second number, moves the rest of the program down over them, sets VariablesStart and relinks (FINI). — first restores VariablesStart from PRGEND; a reversed range deletes nothing |
| 911 | `DEL1` | `Statements::Del::FindEnd` | local | AS | none found | vendor | Finds the first line at or after the upper bound plus one, returning if it is before the first line's position. |
| 912 | `DEL11` | `Statements::Del::Move` | local | AS | none found | vendor | Starts the move with Y = 0. |
| 913 | `DEL111` | `Statements::Del::MoveByte` | local | AS | none found | vendor | Copies a byte from SourceStart to Pointer2 and advances SourceStart. |
| 914 | `DEL112` | `Statements::Del::StepDestination` | local | AS | none found | vendor | Advances Pointer2. |
| 915 | `DEL113` | `Statements::Del::TestEnd` | local | AS | none found | vendor | Loops while SourceStart has not passed VariablesStart. |
| 916 | `DEL114` | `Statements::Del::SetVariablesStart` | local | AS | none found | vendor | Sets VariablesStart to Pointer2 minus one and relinks the program. |
| 917 | `GR` | `Statements::Gr` | routine | AS | spelling only: AS82 [AS] | vendor | GR: reads HiResOff and MixedOn, then the Monitor's SetGraphics shows and clears the lo-res screen. |
| 918 | `TEXT` | `Statements::Text` | routine | AS | spelling only: AS82 [AS] | vendor | TEXT: reads Page2Off, then the Monitor's SetText selects full-screen text. |
| 919 | `STORE` | `Statements::Store` | routine | AS | spelling only: AS82 [AS] | vendor | STORE: finds the array, writes its length less one from LineNumber to cassette, then its data, both with the Monitor's WriteCassette. |
| 920 | `STORE1` | `Statements::Store::WriteLength` | local | AS | none found | vendor | Stores the length less one in LineNumber and writes the header. |
| 921 | `RECALL` | `Statements::Recall` | routine | AS | spelling only: AS82 [AS] | vendor | RECALL: finds the array, reads the length from cassette, fails out of memory if larger than the array, else reads the data with ReadCassette. |
| 922 | `RECAL1` | `Statements::Recall::ReadData` | local | AS | none found | vendor | Sets the cassette range to the array's data and reads it. |

### AppleSoft.ControlFlow

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 923 | `NXTCO1` | `NextStatementSavingStack` | routine | AS | none found | vendor | Saves the stack pointer in REMSTK (ONERR's resume level), then falls into NextStatement; the next-statement target of GOTO, NEXT, LIST and CRUNCH's run-only path. — AS's next-statement entry (PET callers use NextStatement); see C-Q4; ASTIL and AS82 give NEWSTT at $D7D2, this address; NEWSTT is row 924's name, so it goes in prose here |
| 924 | `NEWSTT` | `NextStatement` | routine | AS | M6502; spelling only: ASTIL [AS], AS82 [AS] | vendor | Checks for Control-C, saves TextPointer in StoppedText when running, then runs the next statement or steps to the next linked line. — C# BasicRom looks it up as NEWSTT; see C-Q1 |
| 925 | `DIRCON` | `NextStatement::TestSeparator` | local | AS | M6502 | vendor | Reads the byte at TextPointer: nonzero goes to the separator check, zero reads the next line's link and number. |
| 926 | `TRCLIN` | `NextStatement::TraceLine` | entry | AS | none found | vendor | Prints # and the line number when TRACE is on and running, then falls into ExecuteStatement; MAIN jumps here for a direct statement. — reached from CommandLoop and CheckStatementSeparator |
| 927 | `GONE` | `ExecuteStatement` | routine | AS | M6502 | vendor | Fetches the statement's first character, dispatches it through DispatchStatement, then continues at NextStatementSavingStack. — C# BasicRom looks it up as GONE |
| 928 | `GONE1` | `ExecuteStatement::ToEndOfProgram` | entry | AS | none found | vendor | Branch-range step: NextStatement's zero link goes on to ENDCON (end of program). — only NextStatement reaches it; it lies after ExecuteStatement's jump |
| 929 | `GONE3` | `DispatchStatement` | routine | AS | M6502 | vendor | Returns at the end of a statement; otherwise a statement token dispatches through StatementTable and anything else is LET. — called by ExecuteStatement and the shared IF/ON code |
| 930 | `GONE2` | `DispatchStatement::WithToken` | entry | AS | M6502 | vendor | Subtracts TOKEN_END from A (carry set) and dispatches; the shared ON/IF code enters here with a token. |
| 931 | `GLET` | `DispatchStatement::ToLet` | local | AS | M6502 | vendor | Jumps on to LET for a character below TOKEN_END. |
| 932 | `MORSTS` | `CheckStatementSeparator` | routine | AS | M6502 | vendor | NextStatement's nonzero-byte case: a colon goes back to trace and run the next statement; anything else is a syntax error. — sits after DispatchStatement; falls into its syntax-error step |
| 933 | `SNERR1` | `CheckStatementSeparator::ToSyntaxError` | entry | AS | M6502 | vendor | Jumps on to SNERR; DispatchStatement also branches here for a token beyond the statements. |
| 934 | `ISCNTC` | `CheckStop` | routine | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | Returns at once unless the keyboard holds Control-C ($83); then reads the key and falls into HandleBreak. — PET's ISCNTC is the kernal STOP check (D-workspace); same job, should share the name; see C-Q6 |
| 935 | `ISCCAP` | `CheckStop::ConsumeKey` | local | AS | M6502 | vendor | Consumes the Control-C key through InputCharacter. |
| 936 | `ISCCA1` | `HandleBreak` | routine | AS | none found | vendor | Gives error code $FF to an active ONERR handler, else compares A with Control-C and falls into the shared STOP code. — reached from CheckStop and Statements::Input |
| 937 | `ISCCA2` | `HandleBreak::NoHandler` | local | AS | none found | vendor | No ONERR active: sets the flags for the shared STOP path from A = 3. |
| 938 | `SAVE` | `Statements::Save` | routine | AS | M6502; spelling only: AS82 [AS] | vendor | Writes the two-byte program length and then the program to cassette through the Monitor. |
| 939 | `LOAD` | `Statements::Load` | routine | AS | M6502; spelling only: AS82 [AS] | vendor | Reads the length and program from cassette, sets VariablesStart, then clears (run-only) or clears and relinks. |
| 940 | `LOAD1` | `Statements::Load::ToClearAndRelink` | local | AS | none found | vendor | Jumps on to ClearAndRelink when LOCK is clear. |
| 941 | `VARTIO` | `SetCassetteLengthRange` | routine | AS | M6502; spelling only: AS82 [AS] | vendor | Points the Monitor's A1/A2 range at the two bytes of PokeAddress and clears LOCK. — also called from AppleSoft.PlatformHelpers |
| 942 | `PROGIO` | `SetCassetteProgramRange` | routine | AS | M6502; spelling only: AS82 [AS] | vendor | Points the Monitor's A1/A2 range from ProgramStart to VariablesStart. |
| 943 | `RUNSTM` | `Statements::PrepareRun` | routine | AS | none found | vendor | RUN's table entry: decrements CurrentLine's high byte keeping the flags, then falls into the shared RUN. — see C-Q7 |
| 944 | `POP` | `Statements::Pop` | routine | AS | spelling only: AS82 [AS] | vendor | Discards the innermost GOSUB frame (and the FOR frames above it) without transferring; RETURN's table entry too. — STMDSP sends both POP and RETURN here |
| 945 | `ON` | `Statements::On` | routine | AS | spelling only: AS82 [AS] | vendor | ON: evaluates the selector and takes the matching line of a GOTO or GOSUB list. |

### AppleSoft.DispatchTables

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 946 | `STMDSP` | `StatementTable` | table | AS | M6502 | vendor | Statement handler addresses minus one, for tokens $80-$BF, used for RTS dispatch. |
| 947 | `FUNDSP` | `FunctionTable` | table | AS | M6502 | vendor | Function entry addresses in token order from SGN to MID$. — SCRN('s entry is ReportError; CheckScrnFunction handles SCRN( first |
| 948 | `Q` | `DROP` | constant | AS | M6502; spelling only: ASTIL [AS], AS82 [AS] | vendor | Assembly-time counter of token values and message offsets; nothing reads it. — Microsoft's Q, mention in prose (assembly-time fill rule) |
| 949 | `RESLST` | `ReservedWords` | table | AS | M6502 | vendor | Keyword spellings in token order, bit 7 on each last character, ending in zero; Tokenize and LIST walk it. |
| 950 | `ENDTK` | `TOKEN_END` | token | AS | M6502 | vendor | Token of END, the first statement token. |
| 951 | `FORTK` | `TOKEN_FOR` | token | AS | M6502 | vendor | Token of FOR. |
| 952 | `DATATK` | `TOKEN_DATA` | token | AS | M6502 | vendor | Token of DATA. |
| 953 | `POPTK` | `TOKEN_POP` | token | AS | none found | vendor | Token of POP. — no document name: AppleSoft's own |
| 954 | `GOTOTK` | `TOKEN_GOTO` | token | AS | M6502 | vendor | Token of GOTO. |
| 955 | `GOSUTK` | `TOKEN_GOSUB` | token | AS | M6502 | vendor | Token of GOSUB. |
| 956 | `REMTK` | `TOKEN_REM` | token | AS | M6502 | vendor | Token of REM. |
| 957 | `PRINTK` | `TOKEN_PRINT` | token | AS | M6502 | vendor | Token of PRINT (Tokenize stores it for ?). |
| 958 | `SCRATK` | `TOKEN_NEW` | token | AS | M6502 | vendor | Token of NEW, the last statement token. |
| 959 | `TABTK` | `TOKEN_TAB` | token | AS | M6502 | vendor | Token of TAB(. |
| 960 | `TOTK` | `TOKEN_TO` | token | AS | M6502 | vendor | Token of TO. |
| 961 | `FNTK` | `TOKEN_FN` | token | AS | M6502 | vendor | Token of FN. |
| 962 | `SPCTK` | `TOKEN_SPC` | token | AS | M6502 | vendor | Token of SPC(. |
| 963 | `THENTK` | `TOKEN_THEN` | token | AS | M6502 | vendor | Token of THEN. |
| 964 | `ATTK` | `TOKEN_AT` | token | AS | none found | vendor | Token of AT; Tokenize refuses it before N or O. |
| 965 | `NOTTK` | `TOKEN_NOT` | token | AS | M6502 | vendor | Token of NOT. |
| 966 | `STEPTK` | `TOKEN_STEP` | token | AS | M6502 | vendor | Token of STEP. |
| 967 | `PLUSTK` | `TOKEN_PLUS` | token | AS | M6502 | vendor | Token of +. |
| 968 | `MINUTK` | `TOKEN_MINUS` | token | AS | M6502 | vendor | Token of -. |
| 969 | `GREATK` | `TOKEN_GREATER` | token | AS | M6502 | vendor | Token of >, the first relational token. |
| 970 | `EQULTK` | `TOKEN_EQUAL` | token | AS | M6502 | vendor | Token of =. |
| 971 | `LESSTK` | `TOKEN_LESS` | token | AS | M6502 | vendor | Token of <. |
| 972 | `ONEFUN` | `TOKEN_FIRST_FUNCTION` | token | AS | M6502 | vendor | Token of SGN, the first function; the evaluator and FunctionTable's index start here. — see C-Q5 |
| 973 | `SCRNTK` | `TOKEN_SCRN` | token | AS | none found | vendor | Token of SCRN(. |
| 974 | `LASNUM` | `TOKEN_LAST_SIMPLE_FUNCTION` | token | AS | M6502 | vendor | Token of CHR$, the last function taking one parenthesized argument; later ones are the string slicers. — see C-Q5 |
| 975 | `ERRTAB` | `ErrorMessages` | table | AS | M6502 | vendor | Error messages, each ending in a bit-7 character; ReportError indexes them by the ERROR_* offsets. |
| 976 | `ERRNF` | `ERROR_NEXT_WITHOUT_FOR` | error | AS | M6502 | vendor | Offset of NEXT WITHOUT FOR in ErrorMessages. |
| 977 | `ERRSN` | `ERROR_SYNTAX` | error | AS | M6502 | vendor | Offset of SYNTAX in ErrorMessages. |
| 978 | `ERRRG` | `ERROR_RETURN_WITHOUT_GOSUB` | error | AS | M6502 | vendor | Offset of RETURN WITHOUT GOSUB in ErrorMessages. |
| 979 | `ERROD` | `ERROR_OUT_OF_DATA` | error | AS | M6502 | vendor | Offset of OUT OF DATA in ErrorMessages. |
| 980 | `ERRFC` | `ERROR_ILLEGAL_QUANTITY` | error | AS | M6502 | vendor | Offset of ILLEGAL QUANTITY in ErrorMessages. |
| 981 | `ERROV` | `ERROR_OVERFLOW` | error | AS | M6502, ASTIL [AS] | vendor | Offset of OVERFLOW in ErrorMessages. |
| 982 | `ERROM` | `ERROR_OUT_OF_MEMORY` | error | AS | M6502 | vendor | Offset of OUT OF MEMORY in ErrorMessages. |
| 983 | `ERRUS` | `ERROR_UNDEFINED_STATEMENT` | error | AS | M6502 | vendor | Offset of UNDEF'D STATEMENT in ErrorMessages. |
| 984 | `ERRBS` | `ERROR_BAD_SUBSCRIPT` | error | AS | M6502 | vendor | Offset of BAD SUBSCRIPT in ErrorMessages. |
| 985 | `ERRDD` | `ERROR_REDIMENSIONED_ARRAY` | error | AS | M6502 | vendor | Offset of REDIM'D ARRAY in ErrorMessages. |
| 986 | `ERRDV0` | `ERROR_DIVISION_BY_ZERO` | error | AS | M6502 | vendor | Offset of DIVISION BY ZERO in ErrorMessages. |
| 987 | `ERRID` | `ERROR_ILLEGAL_DIRECT` | error | AS | M6502 | vendor | Offset of ILLEGAL DIRECT in ErrorMessages. |
| 988 | `ERRTM` | `ERROR_TYPE_MISMATCH` | error | AS | M6502 | vendor | Offset of TYPE MISMATCH in ErrorMessages. |
| 989 | `ERRLS` | `ERROR_STRING_TOO_LONG` | error | AS | M6502 | vendor | Offset of STRING TOO LONG in ErrorMessages. |
| 990 | `ERRST` | `ERROR_FORMULA_TOO_COMPLEX` | error | AS | M6502 | vendor | Offset of FORMULA TOO COMPLEX in ErrorMessages. |
| 991 | `ERRCN` | `ERROR_CANT_CONTINUE` | error | AS | M6502 | vendor | Offset of CAN'T CONTINUE in ErrorMessages. |
| 992 | `ERRUF` | `ERROR_UNDEFINED_FUNCTION` | error | AS | M6502 | vendor | Offset of UNDEF'D FUNCTION in ErrorMessages. |
| 993 | `ERR` | `ErrorSuffix` | message | AS | M6502; spelling only: AS82 [AS] | vendor | The text " ERROR", a bell and a zero, printed after an error message. |
| 994 | `INTXT` | `LineNumberPrefix` | message | AS | M6502 | vendor | The text " IN " printed before an error's or BREAK's line number. |
| 995 | `BRKTXT` | `BreakMessage` | message | AS | M6502 | vendor | A return, BREAK and a bell, printed when a program stops. |
| 996 | `REDDY` | `DROP` | constant | AS | M6502 | vendor | Microsoft's READY-message offset, set to 0; AppleSoft stores no READY text and nothing uses it. — mention REDDY in prose; see C-Q8 |
| 997 | `GOTK` | `DROP` | constant | AS | M6502 | vendor | Microsoft's GO token, set to $FF; AppleSoft has no GO keyword and nothing uses it. — mention GOTK in prose; see C-Q8 |
| 998 | `FORSIZ` | `FOR_FRAME_SIZE` | constant | AS | M6502 | vendor | Size in bytes of a FOR frame on the stack ($12). |

### AppleSoft.Equates

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 999 | `REALIO` | `REALIO` | switch | AS | M6502 | vendor | Microsoft's build target, 4 for the Apple — KEEP: predefined by C# and tests |
| 1000 | `NULCMD` | `NULL_COMMAND` | constant | AS | M6502 | vendor | 0: no NULL command — unused in AppleSoft (see D-Q4) |
| 1001 | `GETCMD` | `GET_COMMAND` | switch | AS | M6502 | vendor | Microsoft's switch for GET; nothing in this source reads it — unused: keep as a record of the configuration or DROP (see D-Q4) |
| 1002 | `RORSW` | `ROTATE_INSTRUCTION` | switch | AS | M6502 | vendor | Microsoft's switch for a CPU with ROR; nothing reads it — unused (see D-Q4) |
| 1003 | `ROMSW` | `ROM_RESIDENT` | switch | AS | M6502 | vendor | Microsoft's switch for ROM-resident BASIC; nothing reads it — unused (see D-Q4) |
| 1004 | `CLMWID` | `ZONE_WIDTH` | constant | AS | M6502 | vendor | print-zone width (14); AppleSoft's comma code uses its own NCMPOS — unused by code in AppleSoft (see D-Q4) |
| 1005 | `LONGI` | `LONG_INITIALIZATION` | switch | AS | M6502 | vendor | Microsoft's switch for the long initialization dialog; nothing reads it — unused (see D-Q4) |
| 1006 | `STKEND` | `STACK_END` | constant | AS | M6502 | vendor | the upper stack limit ($01FB) |
| 1007 | `BUFPAG` | `INPUT_BUFFER_PAGE` | constant | AS | M6502 | vendor | the input buffer's page (2) |
| 1008 | `LINLEN` | `LINE_LENGTH` | constant | AS | M6502 | vendor | the build's terminal line length (40) — unused by code in AppleSoft (see D-Q4) |
| 1009 | `BUFLEN` | `INPUT_BUFFER_LENGTH` | constant | AS | M6502 | vendor | the input buffer's length (240) — unused by code in AppleSoft (INLIN tests $EF itself); see D-Q4 |
| 1010 | `ROMLOC` | `ROM_ORIGIN` | constant | AS | M6502 | vendor | the ROM origin ($D000) |
| 1011 | `KIMROM` | `KIM_ROM` | switch | AS | M6502 | vendor | Microsoft's KIM ROM switch, 0; nothing reads it — unused (see D-Q4); KIM is the machine's name |
| 1012 | `RAMLOC` | `RAM_ORIGIN` | constant | AS | M6502 | vendor | the Microsoft build's RAM origin ($2A00) — unused in AppleSoft (see D-Q4) |
| 1013 | `CQINLN` | `GetLineAfterReturn` | alias | AS | M6502 | vendor | Microsoft's name for the Monitor's GETLNZ ($FD67); nothing in AppleSoft calls it — unused; Microsoft's CQINLN would go in an AppleSoft alias file or be dropped (see D-Q1) |
| 1014 | `CQPRMP` | `PromptCharacter` | alias | AS | M6502 | vendor | Microsoft's name for the Monitor's prompt byte $33; nothing reads it by this name — unused; IIeEquates PromptCharacter (see D-Q1) |
| 1015 | `CQINCH` | `ReadKey` | routine | AS | M6502 | vendor | jsr from AppleSoft's INCHR: the Monitor's RDKEY at $FD0C — Monitor name; Microsoft's CQINCH in an AppleSoft alias (see D-Q1) |
| 1016 | `CQCOUT` | `WriteCassette` | alias | AS | M6502 | vendor | Microsoft's name for the Monitor's WRITE ($FECD); unused — unused; same address as MWRITE (see D-Q1) |
| 1017 | `CQCSIN` | `ReadCassette` | alias | AS | M6502 | vendor | Microsoft's name for the Monitor's READ ($FEFD); unused — unused; same address as MREAD (see D-Q1) |
| 1018 | `BUF` | `InputBuffer` | location | AS | M6502, ASTIL [AS] | vendor | the line input and tokenizing buffer at $0200 — IIeEquates already defines InputBuffer = $0200 (IN); with that include, BUF joins its Also (see D-Q1) |
| 1019 | `OUTCH` | `CharacterOut` | routine | AS | M6502 | vendor | the Monitor's COUT ($FDED): OUTDO prints through it — Monitor name; same name as the PET kernal's $FFD2 vector (same job) |
| 1020 | `CZGETL` | `GetCharacter` | alias | AS | M6502 | vendor | shared GET code calls it; on the Apple it is the Monitor's RDKEY ($FD0C) — shared name so MsBasic.VariableInput reads one name in both vendors: GetCharacter = ReadKey here; see D-Q5 |
| 1021 | `NUMLEV` | `STACK_LEVELS` | constant | AS | M6502 | vendor | Microsoft's stack reserve (23 levels); AppleSoft's GETSTK uses its own — unused in AppleSoft (see D-Q4) |
| 1022 | `STRSIZ` | `DESCRIPTOR_SIZE` | constant | AS | M6502 | vendor | a string descriptor's size: length and two-byte address — could become StringDescriptor .sizeof (see D-Q9) |
| 1023 | `NUMTMP` | `TEMPORARY_COUNT` | constant | AS | M6502 | vendor | number of temporary string descriptors (3) |
| 1024 | `CONTW` | `SUPPRESS_OUTPUT_KEY` | constant | AS | M6502 | vendor | Control-O ($0F) — unused in AppleSoft (see D-Q4) |
| 1025 | `START` | `RestartJump` | location | AS | M6502, ASTIL [AS] | vendor | a JMP at $00: startup aims it at INIT, then at MAIN, and ends with JMP (START+1) — ASTIL documents START |
| 1026 | `RDYJSR` | `PrintStringJump` | location | AS | M6502, ASTIL [AS] | vendor | a JMP at $03 startup aims at STROUT; nothing in the ROM calls it — ASTIL documents RDYJSR; kept as documented workspace |
| 1027 | `ADRAYI` | `FloatToIntegerVector` | location | AS | M6502, ASTIL [AS] | vendor | two-byte vector at $06 for float-to-integer (ASTIL); nothing in the ROM sets or reads it — documented, unused by the ROM |
| 1028 | `ADRGAY` | `IntegerToFloatVector` | location | AS | M6502, ASTIL [AS] | vendor | two-byte vector at $08 for integer-to-float (ASTIL); nothing in the ROM sets or reads it — documented, unused by the ROM |
| 1029 | `USRPOK` | `UserVector` | location | AS | M6502, ASTIL [AS] | vendor | three-byte JMP that USR calls; startup points it at the illegal-quantity error |
| 1030 | `CHARAC` | `Delimiter` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | the delimiting character a scan stops at |
| 1031 | `INTEGR` | `SmallInteger` | alias | AS | M6502 | vendor | alias of Delimiter: the one-byte integer QINT leaves (EXP reads it) |
| 1032 | `ENDCHR` | `EndDelimiter` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | the other delimiting character of a scan |
| 1033 | `COUNT` | `Counter` | location | AS | M6502, ASTIL [AS] | vendor | general counter (tokenizer, line input, digits) |
| 1034 | `DIMFLG` | `Dimensioning` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | set while DIM is defining arrays |
| 1035 | `KIMY` | `DROP` | alias | AS | M6502 | vendor | alias of Dimensioning that nothing references — DROP: no code uses it; KIMY goes in Dimensioning's Also. The glossary's SavedOutputY clashes with IIeEquates SavedOutputY (YSAV1) in AppleSoft |
| 1036 | `VALTYP` | `ValueType` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | value type: $FF string, $00 numeric |
| 1037 | `INTFLG` | `IntegerType` | location | AS | M6502, ASTIL [AS] | vendor | integer type: $80 integer, $00 float |
| 1038 | `DORES` | `TokenizeState` | location | AS | M6502 | vendor | whether the tokenizer may crunch reserved words (cleared in DATA and quotes) |
| 1039 | `GARBFL` | `CollectionState` | alias | AS | M6502, ASTIL [AS] | vendor | alias of TokenizeState used by string allocation as the collected-once flag |
| 1040 | `SUBFLG` | `SubscriptMode` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | whether a subscripted or FN name is allowed here — PetDebugTarget looks it up by name (see D-Q8) |
| 1041 | `INPFLG` | `InputMode` | location | AS | M6502, ASTIL [AS] | vendor | INPUT ($00), GET ($40) or READ ($98) |
| 1042 | `TANSGN` | `TangentSign` | location | AS | M6502, ASTIL [AS] | vendor | sign flag of TAN/SIN quadrant work |
| 1043 | `CNTWFL` | `OutputSuppressed` | alias | AS | M6502 | vendor | alias of CollectorStep ($8F); the shared ProgramTransfers code clears it under clearOutput — in AppleSoft it shares CollectorStep's byte |
| 1044 | `TRMPOS` | `TerminalPosition` | alias | AS | M6502 | vendor | alias of the Monitor's CursorColumn ($24): shared print and list code reads the column here — on the Apple, TerminalPosition = CursorColumn |
| 1045 | `LINWID` | `DROP` | alias | AS | M6502 | vendor | points at CV ($25), the Monitor's cursor line; nothing references it — glossary LineWidth; in AppleSoft the address is not a width and the equate is unused |
| 1046 | `NCMWID` | `LastCommaColumn` | alias | AS | M6502 | vendor | its one use (READY) stores MEMSIZ+1 here: $70 is StringsBottom's high byte — code disagrees with the glossary: AppleSoft uses NCMWID as StringsBottom+1; recommend writing StringsBottom+1 there and dropping this equate (see D-Q3) |
| 1047 | `LINNUM` | `LineNumber` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | two-byte integer work area: line numbers, addresses |
| 1048 | `TEMPPT` | `NextTemporary` | location | AS | M6502; spelling only: ASTIL [AS], AS82 [AS] | vendor | offset of the next free temporary descriptor — PetDebugTarget looks it up by name (see D-Q8) |
| 1049 | `LASTPT` | `LastTemporary` | location | AS | M6502, ASTIL [AS] | vendor | two-byte pointer to the last-used temporary descriptor |
| 1050 | `TEMPST` | `TemporaryDescriptors` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | storage for the three temporary string descriptors — PetDebugTarget looks it up by name (see D-Q8) |
| 1051 | `INDEX1` | `Pointer1` | location | AS | M6502 | vendor | general two-byte pointer 1 — one definition with Also: INDEX1, INDEX |
| 1052 | `INDEX` | `Pointer1` | alias | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | the same definition as Pointer1 (Microsoft's second name) — no second line: INDEX goes in Pointer1's Also |
| 1053 | `INDEX2` | `Pointer2` | location | AS | M6502, ASTIL [AS] | vendor | general two-byte pointer 2 |
| 1054 | `RESHO` | `Result1` | location | AS | M6502; other names here: RESULT (AS82), RES (ASTIL) | vendor | multiply and divide result, most significant byte |
| 1055 | `RESMOH` | `Result2` | location | AS | M6502 | vendor | multiply and divide result, second byte |
| 1056 | `RESMO` | `Result3` | location | AS | M6502 | vendor | multiply and divide result, third byte |
| 1057 | `RESLO` | `Result4` | location | AS | M6502 | vendor | multiply and divide result, least significant byte |
| 1058 | `ADDEND` | `Addend` | alias | AS | M6502 | vendor | alias of Result3 used by the array-size multiplier |
| 1059 | `TXTTAB` | `ProgramStart` | location | AS | M6502; spelling only: AS82 [AS]; other names here: TEXTAB (ASTIL) | vendor | two-byte pointer to the first program line; LIST, RUN and the line search start here |
| 1060 | `VARTAB` | `VariablesStart` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | two-byte pointer to the simple variables, just past the program |
| 1061 | `ARYTAB` | `ArraysStart` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | two-byte pointer to the arrays, after the simple variables |
| 1062 | `STREND` | `ArraysEnd` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | two-byte end of the arrays: the bottom of free memory |
| 1063 | `FRETOP` | `StringsBottom` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | two-byte pointer to the lowest string; strings grow down from MemoryTop |
| 1064 | `FRESPC` | `NewString` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | two-byte pointer to the string just allocated |
| 1065 | `MEMSIZ` | `MemoryTop` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | two-byte highest address + 1 BASIC uses (HIMEM) |
| 1066 | `CURLIN` | `CurrentLine` | location | AS | M6502, ASTIL [AS], AS82 [AS] | vendor | two-byte line number executing; high byte $FF in direct mode — PetDebugTarget looks it up by name (see D-Q8) |
| 1067 | `OLDLIN` | `StoppedLine` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | two-byte line STOP or END left, for CONT |
| 1068 | `POKER` | `PokeAddress` | alias | AS | M6502 | vendor | alias of LineNumber: the address POKE, PEEK and WAIT use |
| 1069 | `OLDTXT` | `StoppedText` | location | AS | M6502, ASTIL [AS] | vendor | two-byte text pointer STOP or END left, for CONT — PetDebugTarget looks it up by name (see D-Q8) |
| 1070 | `DATLIN` | `DataLine` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | two-byte line number of the DATA being read, for error reports |
| 1071 | `DATPTR` | `DataPointer` | location | AS | M6502, ASTIL [AS], AS82 [AS] | vendor | two-byte position of READ in the DATA |
| 1072 | `INPPTR` | `InputPointer` | location | AS | M6502, ASTIL [AS] | vendor | two-byte pointer to the text INPUT or READ is reading |
| 1073 | `VARNAM` | `VariableName` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | the two-byte encoded name being looked up |
| 1074 | `VARPNT` | `VariablePointer` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | two-byte pointer to the value of the variable found |
| 1075 | `FDECPT` | `PowerTablePointer` | alias | AS | M6502 | vendor | alias of VariablePointer: FOUT's index into the powers of ten |
| 1076 | `FORPNT` | `AssignedVariable` | location | AS | M6502, ASTIL [AS], AS82 [AS] | vendor | two-byte pointer to the variable LET, FOR, INPUT or READ stores into |
| 1077 | `LSTPNT` | `ListOffset` | alias | AS | M6502 | vendor | alias of AssignedVariable: LIST saves its index into the line here (one byte, sty/ldy) — code disagrees with the glossary note: not a pointer to a keyword but LIST's saved Y; ListPosition fits better; see D-Q3 |
| 1078 | `ANDMSK` | `WaitAndMask` | alias | AS | M6502 | vendor | alias of AssignedVariable: WAIT's AND mask |
| 1079 | `EORMSK` | `WaitXorMask` | alias | AS | M6502 | vendor | alias of AssignedVariable+1: WAIT's EOR mask |
| 1080 | `OPPTR` | `OperatorPointer` | location | AS | M6502, ASTIL [AS]; other names here: LASTOP (AS82) | vendor | two-byte pointer to the current operator's OperatorTable entry |
| 1081 | `VARTXT` | `VariableListPointer` | alias | AS | M6502; other names here: LASTOP (AS82) | vendor | alias: READ/INPUT's pointer into the variable list |
| 1082 | `OPMASK` | `OperatorMask` | location | AS | M6502, ASTIL [AS] | vendor | relation mask of the operator being parsed |
| 1083 | `DOMASK` | `RelationMask` | alias | AS | M6502 | vendor | alias of TangentSign: the relation operators' result mask |
| 1084 | `DEFPNT` | `FunctionPointer` | location | AS | M6502, ASTIL [AS]; other names here: TEMP3 (ASTIL) | vendor | two-byte pointer to the DEF FN definition being used |
| 1085 | `GRBPNT` | `CollectorPointer` | alias | AS | M6502; other names here: TEMP3 (ASTIL) | vendor | alias of FunctionPointer: the collector's pointer to the best descriptor found |
| 1086 | `DSCPNT` | `DescriptorPointer` | location | AS | M6502, ASTIL [AS]; other names here: DSCPTR (AS82) | vendor | two-byte pointer to a string descriptor (assignment, string functions) |
| 1087 | `FOUR6` | `CollectorStep` | location | AS | M6502, ASTIL [AS] | vendor | the collector's step through descriptors: 3 for strings, 7 in a variable (set at startup to 3) |
| 1088 | `JMPER` | `FunctionJump` | location | AS | M6502, ASTIL [AS]; other names here: JMPADRS (AS82) | vendor | a JMP opcode; the function dispatcher stores its target into the next two bytes |
| 1089 | `SIZE` | `FunctionJumpTarget` | alias | AS | M6502 | vendor | alias of JMPER+1; the string collector keeps a descriptor offset here — code disagrees with the glossary note: no code reaches JMPER+1 by this name; its uses are the collector's offset scratch; see D-Q3 |
| 1090 | `OLDOV` | `FunctionJumpHigh` | alias | AS | M6502; other names here: EXTRASY (AS82) | vendor | alias of JMPER+2; FADD keeps the smaller operand's extension byte here, EXP its rounding — code disagrees with the glossary note: it is an extension (rounding) byte, not a jump address; see D-Q3 |
| 1091 | `TEMPF3` | `FloatTemporary3` | location | AS | M6502; spelling only: ASTIL [AS]; other names here: TEMP3 (ASTIL) | vendor | packed five-byte float temporary 3; shares FunctionPointer |
| 1092 | `TEMPF1` | `FloatTemporary1` | location | AS | M6502, ASTIL [AS]; other names here: TEMP1 (ASTIL) | vendor | packed five-byte float temporary 1 |
| 1093 | `HIGHDS` | `DestinationEnd` | location | AS | M6502, ASTIL [AS], AS82 [AS]; other names here: ARRYPT (ASTIL) | vendor | general two-byte pointer: a block move's high destination end |
| 1094 | `HIGHTR` | `SourceEnd` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | general two-byte pointer: a block move's high source end |
| 1095 | `TEMPF2` | `FloatTemporary2` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS]; other names here: TEMP2 (ASTIL) | vendor | packed five-byte float temporary 2 |
| 1096 | `LOWDS` | `DestinationStart` | location | AS | M6502, ASTIL [AS] | vendor | general two-byte pointer: a block move's low destination end — no code reads it by this name; it anchors the layout of DigitsBeforePoint and DecimalExponent |
| 1097 | `LOWTR` | `SourceStart` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | general two-byte pointer: a block move's low source end; FindLine's result |
| 1098 | `ARYPNT` | `ArrayPointer` | alias | AS | M6502; spelling only: AS82 [AS]; other names here: ARRYPT (ASTIL) | vendor | alias of DestinationEnd used while building an array |
| 1099 | `GRBTOP` | `CollectorTop` | alias | AS | M6502 | vendor | alias of SourceStart: the collector's highest string found so far |
| 1100 | `DECCNT` | `DigitCount` | location | AS | M6502 | vendor | digits after the point (FIN) or before it (FOUT); shares DestinationStart — FIN counts fractional digits here, so the before-the-point reading is FOUT's use only; name may want DigitCount (see D-Q3) |
| 1101 | `TENEXP` | `DecimalExponent` | location | AS | M6502 | vendor | FIN's decimal exponent, less the digits after the point; FOUT's exponent — code confirms the glossary |
| 1102 | `DPTFLG` | `DecimalPointSeen` | location | AS | M6502 | vendor | FIN: bit 7 set by the first decimal point; bit 6 set by a second ends the number — code confirms the glossary; Microsoft's comments on DPTFLG and TENEXP are swapped |
| 1103 | `EXPSGN` | `ExponentSign` | location | AS | M6502, AS82 [AS] | vendor | FIN's sign of the decimal exponent: rotated in on E-, tested to negate |
| 1104 | `FAC` | `Fac` | location | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | the floating-point accumulator, unpacked (exponent first) |
| 1105 | `FACEXP` | `FacExponent` | location | AS | M6502; spelling only: ASTIL [AS] | vendor | the FAC's exponent; the same byte as Fac |
| 1106 | `FACHO` | `FacMantissa1` | location | AS | M6502; spelling only: ASTIL [AS] | vendor | the FAC's mantissa, most significant byte |
| 1107 | `FACMOH` | `FacMantissa2` | location | AS | M6502 | vendor | the FAC's mantissa, second byte |
| 1108 | `FACMO` | `FacMantissa3` | location | AS | M6502; spelling only: ASTIL [AS] | vendor | the FAC's mantissa, third byte |
| 1109 | `FACLO` | `FacMantissa4` | location | AS | M6502; spelling only: ASTIL [AS] | vendor | the FAC's mantissa, least significant byte |
| 1110 | `FACSGN` | `FacSign` | location | AS | M6502, AS82 [AS] | vendor | the FAC's sign |
| 1111 | `SGNFLG` | `InputSign` | location | AS | M6502; other names here: SNGFLG (ASTIL) | vendor | FIN's mantissa sign: set by a leading minus, tested to negate at the end — code confirms the glossary |
| 1112 | `DEGREE` | `PolynomialDegree` | alias | AS | M6502; other names here: SNGFLG (ASTIL) | vendor | alias of InputSign: POLY's count of terms left |
| 1113 | `DSCTMP` | `NewDescriptor` | alias | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | alias of Fac where a temporary descriptor is built |
| 1114 | `INDICE` | `ArrayIndex` | alias | AS | M6502 | vendor | alias of FacMantissa3: QINT leaves the subscript here |
| 1115 | `BITS` | `ShiftFill` | location | AS | M6502, ASTIL [AS] | vendor | the fill byte for whole-byte right shifts (0 or $FF for sign); startup clears it — not in the glossary; same name in Commodore.Equates |
| 1116 | `ARGEXP` | `ArgExponent` | location | AS | M6502; other names here: ARG (ASTIL) | vendor | the argument register's exponent (ARG) |
| 1117 | `ARGHO` | `ArgMantissa1` | location | AS | M6502 | vendor | the argument's mantissa, most significant byte |
| 1118 | `ARGMOH` | `ArgMantissa2` | location | AS | M6502 | vendor | the argument's mantissa, second byte |
| 1119 | `ARGMO` | `ArgMantissa3` | location | AS | M6502 | vendor | the argument's mantissa, third byte |
| 1120 | `ARGLO` | `ArgMantissa4` | location | AS | M6502 | vendor | the argument's mantissa, least significant byte |
| 1121 | `ARGSGN` | `ArgSign` | location | AS | M6502; spelling only: AS82 [AS] | vendor | the argument's sign |
| 1122 | `ARISGN` | `ResultSign` | location | AS | M6502 | vendor | the sign of Fac's and Arg's product or sum (their signs compared) |
| 1123 | `FACOV` | `FacExtension` | location | AS | M6502 | vendor | the FAC's extension (rounding) byte |
| 1124 | `STRNG1` | `StringPointer` | alias | AS | M6502, ASTIL [AS] | vendor | two-byte pointer to a string or descriptor; shares ResultSign's byte |
| 1125 | `FBUFPT` | `NumberBufferPointer` | location | AS | M6502, ASTIL [AS] | vendor | two-byte pointer/index into NumberBuffer |
| 1126 | `BUFPTR` | `TokenizePointer` | alias | AS | M6502 | vendor | alias of NumberBufferPointer: the tokenizer's index into InputBuffer |
| 1127 | `STRNG2` | `SecondStringPointer` | alias | AS | M6502; spelling only: ASTIL [AS], AS82 [AS] | vendor | two-byte pointer to a second string or descriptor; shares NumberBufferPointer |
| 1128 | `POLYPT` | `PolynomialPointer` | alias | AS | M6502 | vendor | alias of NumberBufferPointer: POLY's pointer to the coefficients |
| 1129 | `CURTOL` | `LinearIndex` | alias | AS | M6502 | vendor | alias of NumberBufferPointer: an array element's linear index is formed here |
| 1130 | `CHRGET` | `GetNextCharacter` | routine | AS | M6502, ASTIL [AS], ASRM78; spelling only: AS82 [AS] | vendor | page-zero reader copied from the ROM template: advances TextPointer, then reads |
| 1131 | `CHRGOT` | `GetCurrentCharacter` | entry | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | entry into the page-zero reader that rereads the current character |
| 1132 | `TXTPTR` | `TextPointer` | location | AS | M6502; spelling only: ASTIL [AS], AS82 [AS] | vendor | the operand of the load in the page-zero reader: the text being read |
| 1133 | `QNUM` | `ClassifyCharacter` | local | AS | M6502 | vendor | an entry inside the page-zero reader, past its colon test: classifies A without reading — see B1-Q3 |
| 1134 | `CHRRTS` | `CharacterReaderReturn` | local | AS | M6502 | vendor | address inside the page-zero reader: its RTS — the page-zero reader's RTS; the PET debug host looks it up (PetDebugTarget.Basic.cs); see B1-Q3 |
| 1135 | `RNDX` | `RandomValue` | location | AS | M6502, ASTIL [AS] | vendor | RND's last value (five bytes; startup copies four from the template) — clashes in AppleSoft with IIeEquates RandomSeed (RNDL $4E); see D-Q2 |
| 1136 | `LOFBUF` | `NumberBufferPrefix` | location | AS | M6502 | vendor | the byte before NumberBuffer, where STR$'s result starts |
| 1137 | `FBUFFR` | `NumberBuffer` | location | AS | M6502, ASTIL [AS] | vendor | FOUT's output buffer at the bottom of page one |
| 1138 | `WNDLFT` | `WindowLeft` | location | AS | none found | vendor | the text window's left edge — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1139 | `WNDWDT` | `WindowWidth` | location | AS | none found | vendor | the text window's width; AppleSoft's HTAB/TAB wrap compares with it — IIeEquates name; Apple spells it WNDWDTH, AppleSoft WNDWDT: both in Also |
| 1140 | `WNDTOP` | `WindowTop` | location | AS | none found | vendor | the text window's top line — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1141 | `WNDBTM` | `WindowBottom` | location | AS | none found | vendor | the line below the text window — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1142 | `CH` | `CursorColumn` | location | AS | spelling only: AS82 [AS] | vendor | the Monitor's cursor column, also TerminalPosition — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1); TerminalPosition is its alias |
| 1143 | `CV` | `CV` | location | AS | spelling only: AS82 [AS] | vendor | the Monitor's cursor line ($25); AppleSoft names it only in comments — the converted Monitor keeps CV (Dos.md X7), so AppleSoft takes that definition (X10); D-Q7 proposed CursorLine |
| 1144 | `GBASL` | `LowResBase` | location | AS | other names here: HBAS (ASTIL) | vendor | the Monitor's graphics base; AppleSoft's hi-res code uses it as the hi-res byte address — IIeEquates name; ASTIL calls it HBAS here: a scoped alias HighResBase in the hi-res scope |
| 1145 | `GBASH` | `LowResBaseHigh` | location | AS | none found | vendor | high byte of LowResBase; hi-res code builds the row address here — IIeEquates name |
| 1146 | `BASL` | `TextBase` | location | AS | none found | vendor | the Monitor's text line base — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1147 | `BASH` | `TextBaseHigh` | location | AS | none found | vendor | high byte of TextBase — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1148 | `H2` | `HorizontalLineEnd` | location | AS | ASTIL [AS]; spelling only: AS82 [AS] | vendor | HLIN's right end, set by PLOTFN and LINFNS — IIeEquates name |
| 1149 | `V2` | `VerticalLineEnd` | location | AS | ASTIL [AS]; spelling only: AS82 [AS] | vendor | VLIN's bottom end, set by PLOTFN and LINFNS — IIeEquates name |
| 1150 | `MASK` | `PlotMask` | location | AS | none found | vendor | the Monitor's lo-res nibble mask — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1151 | `LENGTH` | `OperandLength` | location | AS | spelling only: AS82 [AS] | vendor | Monitor scratch — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1152 | `COLOR` | `PlotColor` | location | AS | spelling only: AS82 [AS] | vendor | the Monitor's lo-res color; AppleSoft's hi-res code keeps its pixel mask here — IIeEquates name; the hi-res scope may alias it (HighResMask) |
| 1153 | `MODE` | `CommandMode` | location | AS | none found | vendor | Monitor command scratch — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1154 | `INVFLG` | `InverseMask` | location | AS | AS82 [AS] | vendor | normal/inverse/flash text mask; INVERSE, NORMAL and FLASH store it — IIeEquates name |
| 1155 | `PROMPT` | `PromptCharacter` | location | AS | spelling only: AS82 [AS] | vendor | the prompt GETLN prints; INLIN stores it — IIeEquates name |
| 1156 | `YSAV` | `CommandPosition` | location | AS | none found | vendor | Monitor scratch — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1157 | `YSAV1` | `SavedOutputY` | location | AS | none found | vendor | Monitor scratch — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1); the glossary gives SavedOutputY to KIMY too (see D-Q3) |
| 1158 | `CSWL` | `OutputHook` | location | AS | none found | vendor | the Monitor's output vector — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1159 | `CSWH` | `OutputHookHigh` | location | AS | none found | vendor | high byte of OutputHook — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1160 | `KSWL` | `InputHook` | location | AS | none found | vendor | the Monitor's input vector — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1161 | `KSWH` | `InputHookHigh` | location | AS | none found | vendor | high byte of InputHook — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1162 | `PCL` | `ProgramCounter` | location | AS | none found | vendor | the Monitor's program counter — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1163 | `PCH` | `ProgramCounterHigh` | location | AS | none found | vendor | high byte of ProgramCounter — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1164 | `A1L` | `Address1` | location | AS | spelling only: AS82 [AS] | vendor | Monitor parameter A1: CALL/cassette range start set by AppleSoft — IIeEquates name |
| 1165 | `A1H` | `Address1High` | location | AS | none found | vendor | high byte of Address1 — IIeEquates name |
| 1166 | `A2L` | `Address2` | location | AS | none found | vendor | Monitor parameter A2: cassette range end set by AppleSoft — IIeEquates name |
| 1167 | `A2H` | `Address2High` | location | AS | none found | vendor | high byte of Address2 — IIeEquates name |
| 1168 | `A3L` | `Address3` | location | AS | none found | vendor | Monitor parameter A3 — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1169 | `A3H` | `Address3High` | location | AS | none found | vendor | high byte of Address3 — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1170 | `A4L` | `Address4` | location | AS | none found | vendor | Monitor parameter A4 — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1171 | `A4H` | `Address4High` | location | AS | none found | vendor | high byte of Address4 — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1172 | `A5L` | `Address5` | location | AS | none found | vendor | Monitor parameter A5 — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1173 | `A5H` | `Address5High` | location | AS | none found | vendor | high byte of Address5 — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1174 | `XREG` | `SavedX` | location | AS | none found | vendor | the Monitor's saved X — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1175 | `YREG` | `SavedY` | location | AS | none found | vendor | the Monitor's saved Y — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1176 | `STATUS` | `SavedStatus` | location | AS | none found | vendor | the Monitor's saved status — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1177 | `RNDL` | `RandomSeed` | location | AS | none found | vendor | the Monitor's keyboard-wait counter — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1); clashes with the glossary's RandomSeed for RNDX (see D-Q2) |
| 1178 | `RNDH` | `RandomSeedHigh` | location | AS | none found | vendor | high byte of RandomSeed — IIeEquates name; unused in AppleSoft: comes free with the include, else DROP (see D-Q1) |
| 1179 | `SHAPEL` | `ShapePointer` | location | AS | spelling only: AS82 [AS]; other names here: SHAPE (ASTIL) | vendor | two-byte pointer into the shape being drawn; HCLR/BKGND reuse it as the page fill pointer — ASTIL: SHAPE |
| 1180 | `SHAPEH` | `ShapePointerHigh` | location | AS | spelling only: AS82 [AS] | vendor | high byte of ShapePointer; BKGND loads HPAG into it |
| 1181 | `HCOLR2` | `HighResColorByte` | location | AS | other names here: HCOLOR1 (ASTIL) | vendor | the color byte for the current byte's phase; HPOSN copies HighResColor here, plotting XORs it in — ASTIL calls $1C HCOLOR1 |
| 1182 | `HCOUNT` | `HighResLineCount` | location | AS | spelling only: AS82 [AS]; other names here: COUNTH (ASTIL) | vendor | HLIN's remaining step count, counted up to zero — ASTIL: COUNTH |
| 1183 | `PRGEND` | `ProgramEnd` | location | AS | ASTIL [AS], AS82 [AS] | vendor | two-byte end of the program (NEW and LOAD set it, READY restores VariablesStart from it) — AS82 documents PRGEND |
| 1184 | `HGRDX` | `HighResDeltaX` | location | AS | other names here: DX (ASTIL) | vendor | two-byte X distance of the line being drawn — ASTIL: DX |
| 1185 | `HGRDY` | `HighResDeltaY` | location | AS | other names here: DY (ASTIL) | vendor | Y distance of the line; also the shape drawer's scratch — ASTIL: DY |
| 1186 | `HGRQUA` | `HighResQuadrant` | location | AS | other names here: QDRNT (ASTIL) | vendor | the line's direction bits (rotated in by HGLIN) — ASTIL: QDRNT |
| 1187 | `HGRE` | `HighResError` | location | AS | none found | vendor | two-byte error term of the line algorithm |
| 1188 | `LOCK` | `RunOnly` | location | AS | spelling only: AS82 [AS]; other names here: RNONLY (ASTIL) | vendor | bit 7 set: LIST and editing refused; LOAD also uses it to autorun — ASTIL: RNONLY |
| 1189 | `ERRFLG` | `OnErrorActive` | location | AS | ASTIL [AS], AS82 [AS] | vendor | bit 7 set by ONERR: errors go to HANDLE; RESUME and errors clear it |
| 1190 | `ERRLIN` | `ErrorLine` | location | AS | ASTIL [AS], AS82 [AS] | vendor | two-byte line of the trapped error, for RESUME — AS82 documents ERRLIN |
| 1191 | `ERRPOS` | `ErrorText` | location | AS | ASTIL [AS], AS82 [AS] | vendor | two-byte statement position of the trapped error, for RESUME |
| 1192 | `ERRNUM` | `ErrorCode` | location | AS | ASTIL [AS], AS82 [AS] | vendor | offset of the trapped error (PEEK(222)) |
| 1193 | `ERRSTK` | `ErrorStack` | location | AS | ASTIL [AS]; other names here: NXDIM (AS82) | vendor | stack pointer of the trapped statement, restored by RESUME |
| 1194 | `HGRX` | `HighResX` | location | AS | other names here: XO (ASTIL) | vendor | two-byte current hi-res X — ASTIL: XO |
| 1195 | `HGRY` | `HighResY` | location | AS | other names here: YO (ASTIL) | vendor | current hi-res Y — ASTIL: YO |
| 1196 | `HCOLR1` | `HighResColor` | location | AS | none found | vendor | the HCOLOR= value's color byte from COLTBL |
| 1197 | `HNDX` | `HighResByteIndex` | location | AS | ASTIL [AS]; spelling only: AS82 [AS] | vendor | the byte offset in the row of the current point — ASTIL documents HNDX |
| 1198 | `HPAG` | `HighResPage` | location | AS | ASTIL [AS] | vendor | high byte of the page being drawn ($20 or $40) — ASTIL documents HPAG |
| 1199 | `HSCALE` | `ShapeScale` | location | AS | none found | vendor | SCALE= value used by DRAW and XDRAW |
| 1200 | `SHPTBL` | `ShapeTable` | location | AS | other names here: SHAPX (ASTIL) | vendor | two-byte address of the shape table — ASTIL: SHAPX; the firmware conversion left SHAPEPTR for this (Firmware.md F8) |
| 1201 | `COLCNT` | `CollisionCount` | location | AS | other names here: COLLSN (ASTIL) | vendor | incremented when a drawn point was already lit — ASTIL: COLLSN |
| 1202 | `FIRST` | `LowResFirst` | location | AS | ASTIL [AS]; spelling only: AS82 [AS] | vendor | PLOT's X, HLIN/VLIN's lower end (PLOTFN, LINFNS) — ASTIL documents FIRST |
| 1203 | `SPEEDZ` | `OutputDelay` | location | AS | spelling only: AS82 [AS]; other names here: SPDBYT (ASTIL) | vendor | 256 minus SPEED=; OUTDO waits this long per character — ASTIL: SPDBYT |
| 1204 | `TRCFLG` | `TraceMode` | location | AS | spelling only: AS82 [AS]; other names here: TRFLAG (ASTIL) | vendor | bit 7 set by TRACE; NEWSTT prints line numbers while set — ASTIL: TRFLAG |
| 1205 | `FLASHB` | `FlashMask` | location | AS | other names here: ORMASK (ASTIL) | vendor | ORed into each character printed; FLASH sets $40 — ASTIL: ORMASK |
| 1206 | `TXTPSV` | `OnErrorText` | location | AS | spelling only: AS82 [AS]; other names here: ERRTO (ASTIL) | vendor | two-byte text position of the ONERR GOTO, restored when an error is trapped — ASTIL: ERRTO |
| 1207 | `CURLSV` | `OnErrorLine` | location | AS | spelling only: AS82 [AS] | vendor | two-byte line of the ONERR GOTO, restored when an error is trapped |
| 1208 | `REMSTK` | `StatementStack` | location | AS | ASTIL [AS]; spelling only: AS82 [AS] | vendor | stack pointer saved before each statement; HANDLE copies it to ErrorStack — ASTIL documents REMSTK |
| 1209 | `HROT` | `ShapeRotation` | location | AS | other names here: ROTBYT (ASTIL) | vendor | ROT= value used by DRAW and XDRAW — ASTIL: ROTBYT |
| 1210 | `AMPERV` | `AmpersandJump` | location | AS | none found | vendor | the JMP at $3F5 the & statement goes to (dispatch entry AMPERV-1) — not in IIeEquates; DOS and Integer BASIC name $3F5 differently (OVLOC); see D-Q1 |
| 1211 | `OURCH` | `EightyColumns::CursorColumn` | alias | AS | none found | vendor | the 80-column firmware's cursor column ($57B), read for POS and TAB on 80 columns — FirmwareEquates.asm name; include it or define the scope (see D-Q1) |
| 1212 | `KBD` | `Keyboard` | location | AS | spelling only: AS82 [AS] | vendor | the keyboard data; ISCNTC reads it for Control-C — IIeEquates name |
| 1213 | `SETSLO` | `InternalCxRomOff` | location | AS | none found | vendor | slot ROMs at $C100-$CFFF; written after calling the firmware — IIeEquates name |
| 1214 | `SETINT` | `InternalCxRomOn` | location | AS | none found | vendor | internal ROM at $C100-$CFFF; written before calling AppleSoftCassette — IIeEquates name |
| 1215 | `RD80VI` | `Columns80State` | location | AS | none found | vendor | bit 7 set when 80 columns are displayed; POS and TAB test it — IIeEquates name |
| 1216 | `TXTCLR` | `TextOff` | location | AS | spelling only: AS82 [AS] | vendor | graphics display; HGR reads it — IIeEquates name |
| 1217 | `TXTSET` | `TextOn` | location | AS | none found | vendor | text display; nothing in AppleSoft reads it — IIeEquates name; unused in AppleSoft |
| 1218 | `MIXCLR` | `MixedOff` | location | AS | spelling only: AS82 [AS] | vendor | full-screen graphics; HGR2 reads it — IIeEquates name |
| 1219 | `MIXSET` | `MixedOn` | location | AS | spelling only: AS82 [AS] | vendor | mixed text and graphics; GR and HGR read it — IIeEquates name |
| 1220 | `LOWSCR` | `Page2Off` | location | AS | spelling only: AS82 [AS] | vendor | display page 1; GR and HGR read it — IIeEquates name |
| 1221 | `HISCR` | `Page2On` | location | AS | spelling only: AS82 [AS] | vendor | display page 2; HGR2 reads it — IIeEquates name |
| 1222 | `LORES` | `HiResOff` | location | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | lo-res graphics; GR reads it — IIeEquates name |
| 1223 | `HIRES` | `HiResOn` | location | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | hi-res graphics; HGR reads it — IIeEquates name |
| 1224 | `MPLOT` | `LowRes::Plot` | routine | AS | none found | vendor | the Monitor's routine: PLOT jumps here — Monitor name; scoped in the Monitor, so AppleSoft writes .scope LowRes (as MonitorEntries does for SetPcFromA1::Loop); see D-Q1 |
| 1225 | `HLINE` | `LowRes::HorizontalLine` | routine | AS | none found | vendor | the Monitor's routine: HLIN calls it — Monitor name; scoped in the Monitor, so AppleSoft writes .scope LowRes (as MonitorEntries does for SetPcFromA1::Loop); see D-Q1 |
| 1226 | `VLINE` | `LowRes::VerticalLine` | routine | AS | spelling only: AS82 [AS] | vendor | the Monitor's routine: VLIN calls it — Monitor name; scoped in the Monitor, so AppleSoft writes .scope LowRes (as MonitorEntries does for SetPcFromA1::Loop); see D-Q1 |
| 1227 | `SETCOL` | `LowRes::SetColor` | routine | AS | spelling only: AS82 [AS] | vendor | the Monitor's routine: COLOR= calls it — Monitor name; scoped in the Monitor, so AppleSoft writes .scope LowRes (as MonitorEntries does for SetPcFromA1::Loop); see D-Q1 |
| 1228 | `MSCRN` | `LowRes::ReadColor` | routine | AS | none found | vendor | the Monitor's routine: SCRN( calls it — Monitor name; scoped in the Monitor, so AppleSoft writes .scope LowRes (as MonitorEntries does for SetPcFromA1::Loop); see D-Q1 |
| 1229 | `PREAD` | `ReadPaddle` | routine | AS | spelling only: AS82 [AS] | vendor | the Monitor's routine: PDL( calls it — Monitor name |
| 1230 | `SETTXT` | `SetText` | routine | AS | spelling only: AS82 [AS] | vendor | the Monitor's routine: TEXT calls it — Monitor name |
| 1231 | `SETGR` | `SetGraphics` | routine | AS | spelling only: AS82 [AS] | vendor | the Monitor's routine: GR calls it — Monitor name |
| 1232 | `TABV` | `VerticalTabTo` | routine | AS | none found | vendor | the Monitor's routine: VTAB jumps here — Monitor name |
| 1233 | `HOME` | `Home` | routine | AS | spelling only: AS82 [AS] | vendor | the Monitor's routine: HOME's dispatch entry points straight at the Monitor's routine — Monitor name; the dispatch entry is the Monitor's, so there is no Statements::Home |
| 1234 | `MWAIT` | `Delay` | routine | AS | none found | vendor | the Monitor's routine: OUTDO calls it for SPEED= — Monitor name |
| 1235 | `RD2BIT` | `Cassette::ReadBit` | routine | AS | none found | vendor | the Monitor's routine: the cassette helper calls it to find the tape's edge — Monitor name; scoped in the Monitor, so AppleSoft writes .scope Cassette (as MonitorEntries does for SetPcFromA1::Loop); see D-Q1 |
| 1236 | `GETLN` | `GetLine` | routine | AS | spelling only: AS82 [AS] | vendor | the Monitor's routine: INLIN calls it to read a line — Monitor name |
| 1237 | `INPORT` | `SetInput` | routine | AS | spelling only: AS82 [AS] | vendor | the Monitor's routine: IN# calls it — Monitor name |
| 1238 | `OUTPOR` | `SetOutput` | routine | AS | none found | vendor | the Monitor's routine: PR# calls it — Monitor name; Apple spells it OUTPORT |
| 1239 | `MWRITE` | `WriteCassette` | routine | AS | none found | vendor | the Monitor's routine: SAVE/STORE/SHLOAD helpers call it — Monitor name |
| 1240 | `MREAD` | `ReadCassette` | routine | AS | none found | vendor | the Monitor's routine: LOAD/RECALL/SHLOAD call it — Monitor name |
| 1241 | `C5ROM` | `AppleSoftCassette` | routine | AS | none found | vendor | the Enhanced IIe firmware's cassette helper at $C500, called with the internal ROM on (IIeE) — Firmware.Enhanced name (BASTAPE UNKN) |

### AppleSoft.ErrorAndInput

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1242 | `OMERR` | `ReportOutOfMemory` | routine | AS | M6502 | vendor | Loads ERROR_OUT_OF_MEMORY into X and falls into ReportError. |
| 1243 | `ERROR` | `ReportError` | routine | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | Passes the error to an active ONERR handler, else prints ?, the message at X in ErrorMessages, ERROR and the line, and returns to the prompt. — C# BasicRom looks it up as ERROR |
| 1244 | `ERROR1` | `ReportError::PrintMessage` | local | AS | other names here: DOERRMSG (AS82) | vendor | No handler: starts a new line and prints the question mark. — same job as PET's ERRCRD |
| 1245 | `GETERR` | `ReportError::NextCharacter` | local | AS | M6502 | vendor | Prints message characters until the one with bit 7 set. |
| 1246 | `READY` | `ReadyForCommand` | entry | AS | M6502 | vendor | Where errors, END and STOP return: AppleSoft prints nothing and this is CommandLoop's own address. — second label on CommandLoop; PET prints READY. here; see C-Q2 |
| 1247 | `MAIN` | `CommandLoop` | routine | AS | M6502; spelling only: AS82 [AS] | vendor | Reads a line after a newline, runs a direct statement, or inserts, replaces or deletes a numbered line. — C# debug targets look it up as MAIN |
| 1248 | `READY1` | `CommandLoop::EditProgram` | local | AS | none found | vendor | A numbered line: resets VariablesStart from PRGEND, then deletes any old line of that number. |
| 1249 | `NODEL` | `CommandLoop::InsertLine` | local | AS | M6502 | vendor | After any deletion: an empty line relinks; otherwise opens space at the insertion point with BLTU. — the shared delete-line macro branches here |
| 1250 | `NODELC` | `CommandLoop::OpenGap` | local | AS | M6502 | vendor | Stores the high byte of the move's end and calls BLTU. |
| 1251 | `NODEL1` | `CommandLoop::CopyLine` | local | AS | none found | vendor | Copies the tokenized line from the input buffer into the program. — same job as PET's STOLOP |
| 1252 | `FINI` | `ClearAndRelink` | routine | AS | M6502 | vendor | Clears variables and execution state (RUNC), then falls into LinkProgram. — called by LOAD and AppleSoft.AppleCommands |
| 1253 | `LNKPRG` | `LinkProgram` | routine | AS | M6502 | vendor | Rebuilds every line's link from ProgramStart, records VariablesStart as PRGEND and enters CommandLoop. |
| 1254 | `CHEAD` | `LinkProgram::NextLine` | local | AS | M6502; other names here: NXLINK (AS82) | vendor | Tests a line's link high byte; zero ends the program. — the shared link macro branches back here |
| 1255 | `CHEAD1` | `LinkProgram::StoreLink` | local | AS | none found | vendor | Scans the line to its zero and stores the next line's address as its link. |
| 1256 | `INLIN` | `InputLine` | routine | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | Reads a line through the Monitor with no prompt character, zero-terminated and capped at 239, bit 7 cleared. |
| 1257 | `INLIN1` | `InputLine::WithPrompt` | entry | AS | other names here: INLIN+2 (ASTIL) | vendor | Same, with X as the Monitor's prompt character; CommandLoop enters here with ]. — ASTIL names it INLIN+2 (prose) |
| 1258 | `GDBUFS` | `InputLine::Terminate` | local | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | Stores the zero after the last character. |
| 1259 | `LOPBHT` | `InputLine::ClearHighBits` | local | AS | M6502 | vendor | Clears bit 7 of each input character. |
| 1260 | `NOCHR` | `InputLine::Finish` | local | AS | M6502 | vendor | Returns A = 0, X/Y = the address before InputBuffer. |
| 1261 | `INCHR` | `InputCharacter` | routine | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | Reads a key through the Monitor and clears its bit 7. |
| 1262 | `INCRTS` | `InputCharacter::Return` | local | AS | M6502 | vendor | Return. — unreferenced; kept for its M6502 name |
| 1263 | `BUFOFS` | `INPUT_BUFFER_BASE` | constant | AS | M6502 | vendor | The input buffer's page base for Tokenize's indexing, set to 0 then $0200; AppleSoft's code never uses it. — matches Commodore's BUFOFS in D-workspace; see C-Q9 |
| 1264 | `CRUNCH` | `Tokenize` | routine | AS | M6502 | vendor | Tokenizes InputBuffer in place: skips spaces, copies quotes, DATA and REM, folds case on IIeE; runs a run-only program instead. |
| 1265 | `CRUNC1` | `Tokenize::Advance` | local | AS | none found | vendor | Steps to the next input character. |
| 1266 | `KLOOP` | `Tokenize::NextCharacter` | local | AS | M6502 | vendor | Reads the next input character (folding case on IIeE) for tokenizing. — the shared token-store macro branches back here |
| 1267 | `CMPSPC` | `Tokenize::CheckSpace` | local | AS | M6502 | vendor | Skips a space outside DATA. — unreferenced; kept for its M6502 name |
| 1268 | `CMPSP1` | `Tokenize::CheckQuote` | local | AS | none found | vendor | Records the character as the end delimiter and starts a quoted copy at a quote. |
| 1269 | `KLOOP1` | `Tokenize::CheckDigit` | local | AS | M6502 | vendor | Copies digits and : ; unchanged. |
| 1270 | `MUSTCR` | `Tokenize::SearchWords` | local | AS | M6502 | vendor | Sets up the walk of ReservedWords from the current input position. |
| 1271 | `RESER` | `Tokenize::CharacterMatched` | local | AS | M6502 | vendor | A character matched: advances in the table (with page carry) and the input. |
| 1272 | `RESPUL` | `Tokenize::AdvanceInput` | local | AS | M6502 | vendor | Advances the input index, skipping spaces. |
| 1273 | `RESPU1` | `Tokenize::CompareCharacter` | local | AS | none found | vendor | Compares the input character with the table's. — same job as PET's RESCON |
| 1274 | `NTHIS` | `Tokenize::NextWord` | local | AS | M6502 | vendor | Mismatch: restores the input index, counts the word and skips to its end. |
| 1275 | `NTHIS2` | `Tokenize::SkipWord` | local | AS | none found | vendor | Reads table bytes until the word's last character. — same job as PET's NTHIS1 |
| 1276 | `NTHIS1` | `Tokenize::AdvanceTable` | local | AS | M6502 | vendor | Advances the table index. — unreferenced; kept for its M6502 name |
| 1277 | `NTHIS3` | `Tokenize::TestWordEnd` | local | AS | none found | vendor | Tests bit 7 of the table byte after any page carry. — same job as PET P4's NTHIS2 |
| 1278 | `CRDONE` | `Tokenize::Finish` | local | AS | M6502 | vendor | Stores the line's end and sets TextPointer to the byte before InputBuffer. — the shared token-store macro branches here |
| 1279 | `LISTRT` | `Tokenize::Return` | local | AS | M6502 | vendor | Return. — unreferenced; kept for its M6502 name |

### AppleSoft.Expressions

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1280 | `ISVAR` | `EvaluateVariable` | routine | AS | M6502 | vendor | Looks up the variable operand (PTRGET) and falls into LoadVariableValue. |
| 1281 | `ISVRET` | `LoadVariableValue` | routine | AS | M6502 | vendor | With A/Y = the variable's address: leaves a string's address in Fac, loads an integer or float into Fac. — the shared lookup compares its return address with this label - 1 |
| 1282 | `STRRTS` | `LoadVariableValue::Return` | local | AS | M6502 | vendor | Return with a string's descriptor address in FacMantissa3/4. — unreferenced in AS; kept for its M6502 name |
| 1283 | `QSTATV` | `LoadVariableValue::LoadFloat` | local | AS | M6502 | vendor | Moves the float variable into Fac (MOVFM). — same job as PET's GOMOVF; Microsoft's QSTATV place, where AS has no ST check |
| 1284 | `QSTAT1` | `Functions::Scrn` | routine | AS | none found | vendor | SCRN(: evaluates the coordinates and returns the Monitor's lo-res color as a number. |
| 1285 | `QSTAT2` | `CheckScrnFunction` | routine | AS | none found | vendor | The evaluator's function entry: SCRN( goes to Functions::Scrn, others fall into the shared function dispatch. |
| 1286 | `PDL` | `Functions::Pdl` | routine | AS | spelling only: AS82 [AS] | vendor | PDL: reads the numbered paddle through the Monitor and returns its value. |

### AppleSoft.FloatAliases

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1287 | `PRNTFAC` | `AppleSoft::PrintFac` | alias | AS | ASTIL [AS] | vendor | AppleSoft's equate naming the shared entry that prints Fac — becomes Also: PRNTFAC (ASTIL) on Float::PrintFac, in AppleSoft's alias file (D3); see A-Q1 |

### AppleSoft.HighResolution

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1288 | `HGR2` | `Statements::HGr2` | routine | AS | ASTIL [AS]; spelling only: AS82 [AS] | vendor | HGR2: shows page 2 full screen (Page2On, MixedOff) and selects drawing page $40 through HighRes::SelectPage. — Also: HGR2 (ASTIL); the TIL documents it as an entry, so it keeps its .assert |
| 1289 | `HGR` | `Statements::HGr` | routine | AS | ASTIL [AS]; spelling only: AS82 [AS] | vendor | HGR: shows page 1 mixed with text (Page2Off, MixedOn) and falls into HighRes::SelectPage with page $20. — Also: HGR (ASTIL); falls into HighRes::SelectPage |
| 1290 | `HGR1` | `HighRes::SelectPage` | routine | AS | spelling only: ASTIL [AS] | vendor | Stores A (the page's high byte) in HPAG, switches HiResOn and TextOff, and falls into Clear. — its own proc: HGr2 branches to it, HGr falls into it; falls into HighRes::Clear; HighRes: scope for the hi-res engine as the Monitor's LowRes, see E-Q2 |
| 1291 | `HCLR` | `HighRes::Clear` | routine | AS | ASTIL [AS] | vendor | Sets HCOLR2 to black and falls into Fill. — Also: HCLR (ASTIL); falls into HighRes::Fill |
| 1292 | `BKGND` | `HighRes::Fill` | routine | AS | ASTIL [AS] | vendor | Fills the page HPAG names with HCOLR2, flipping its colored patterns for each byte's phase (StepHorizontal::AdjustColor). — Also: BKGND (ASTIL) |
| 1293 | `BKGND1` | `HighRes::Fill::NextByte` | local | AS | none found | vendor | Stores the pattern, adjusts it for the next byte, and loops to the page's end. |
| 1294 | `HPOSN` | `HighRes::Position` | routine | AS | ASTIL [AS]; spelling only: AS82 [AS] | vendor | With A = row, Y:X = column, sets LowResBase/LowResBaseHigh to the row's address, HNDX to the byte, PlotColor to the pixel mask, and HCOLR2 for the phase. — Also: HPOSN (ASTIL); uses the Monitor's lo-res base and color bytes for its own purpose, see E-Q5 |
| 1295 | `HPOSN1` | `HighRes::Position::CountByte` | local | AS | none found | vendor | Counts one more byte in Y while dividing the column by seven. |
| 1296 | `HPOSN2` | `HighRes::Position::Divide` | local | AS | none found | vendor | Subtracts seven until it borrows; the remainder indexes PixelMasks. |
| 1297 | `HPLOT0` | `HighRes::Plot` | routine | AS | none found | vendor | Positions the cursor and sets the pixel to HCOLR2 under the PixelMask. — ASTIL calls this HPLOT ($F457); HPLOT is the statement's name, so prose, see E-Q3 |
| 1298 | `LFTRT` | `HighRes::StepHorizontal` | routine | AS | none found | vendor | Moves the pixel mask one pixel left (A minus) or right (A plus), changing HNDX and wrapping within the row at a byte edge. — Entries: AdjustColor; Plot steps, Line and Fill reach it |
| 1299 | `LFTRT1` | `HighRes::StepHorizontal::SetMask` | local | AS | none found | vendor | Stores the new mask in PlotColor and returns. |
| 1300 | `LFTRT2` | `HighRes::StepHorizontal::PreviousByte` | local | AS | none found | vendor | Steps HNDX back a byte, from 0 to 39. — wraps to the row's other end rather than stopping |
| 1301 | `LFTRT3` | `HighRes::StepHorizontal::LastPixel` | local | AS | none found | vendor | Loads the mask for the byte's last pixel ($C0). |
| 1302 | `LFTRT4` | `HighRes::StepHorizontal::NewByte` | local | AS | none found | vendor | Stores the mask and HNDX for the new byte and falls into AdjustColor with HCOLR2. |
| 1303 | `LFTRT5` | `HighRes::StepHorizontal::AdjustColor` | entry | AS | none found | vendor | Flips HCOLR2's color bits (EOR $7F) when the pattern alternates, so the color stays in phase in the next byte. — reached from Position (branch) and Fill (jsr); Proc::Label entry, see E-Q1 |
| 1304 | `LFTRT6` | `HighRes::StepHorizontal::Done` | local | AS | none found | vendor | Returns. |
| 1305 | `LFTRT7` | `HighRes::StepHorizontal::Right` | local | AS | none found | vendor | Moves the mask right; past the byte's last pixel, takes the next byte's first ($81), from 39 to 0. |
| 1306 | `DRWPNT` | `HighRes::XorStep` | routine | AS | spelling only: AS82 [AS] | vendor | XorDraw's step: if the vector's plot bit is set, toggles the pixel (counting it in COLCNT when it was clear), then moves along the direction. — Apple's DRWPNT serves XDRAW and XDRPNT serves DRAW: the old names are swapped |
| 1307 | `DRWPN1` | `HighRes::XorStep::Across` | entry | AS | none found | vendor | The same with carry set, so the move is a quarter turn from the vector. — XorDrawShape calls it |
| 1308 | `XDRPNT` | `HighRes::PlotStep` | routine | AS | none found | vendor | Draw's step: if the plot bit is set, sets the pixel to HCOLR2 (counting it in COLCNT when it already matched), then moves along the direction. — falls into HighRes::StepVertical or branches to StepHorizontal |
| 1309 | `XDRPN1` | `HighRes::PlotStep::Across` | entry | AS | none found | vendor | The same with carry set, so the move is a quarter turn from the vector. — DrawShape calls it |
| 1310 | `XDRPN2` | `HighRes::PlotStep::WritePixel` | entry | AS | none found | vendor | Writes the masked change into the screen byte. — XorStep branches here; Proc::Label entry, see E-Q1 |
| 1311 | `XDRPN3` | `HighRes::PlotStep::Move` | entry | AS | none found | vendor | Adds HGRQUA and carry to the vector's direction and steps horizontally or (falling through) vertically. — XorStep branches here; see E-Q1 |
| 1312 | `MASK03` | `HighRes::LowTwoBitsMask` | data | AS | none found | vendor | The operand byte 3 of Move's AND, which StepVertical's BIT also reads to test the high byte's bits 0-1. — equate at * + 1 on an instruction operand; see E-Q8 |
| 1313 | `UPDWN` | `HighRes::StepVertical` | routine | AS | none found | vendor | Moves the cursor's LowResBase/LowResBaseHigh one row up (A plus) or down (A minus) through the interleaved screen layout. — the 11 bytes after its last bcc ($F530: zero the cursor, fall into Line) are unreachable: carry is always clear after the ror; see E-Q9 |
| 1314 | `UPDWN1` | `HighRes::StepVertical::UpThird` | local | AS | none found | vendor | Moving up out of a third of the screen: adjusts the high byte and moves LowResBase back across the third. |
| 1315 | `UPDWN2` | `HighRes::StepVertical::UpThirdStore` | local | AS | none found | vendor | Stores the adjusted LowResBase. |
| 1316 | `UPDWN3` | `HighRes::StepVertical::UpGroup` | local | AS | none found | vendor | Moving up into the previous group of eight rows when the group bit was set. |
| 1317 | `UPDWN4` | `HighRes::StepVertical::UpRotate` | local | AS | none found | vendor | Rotates the group bit back into LowResBase. |
| 1318 | `UPDWN5` | `HighRes::StepVertical::UpRow` | local | AS | none found | vendor | Subtracts 4 from the high byte: the previous row in the group. |
| 1319 | `UPDWN6` | `HighRes::StepVertical::StoreHigh` | local | AS | none found | vendor | Stores the high byte and returns. |
| 1320 | `UPDWN7` | `HighRes::StepVertical::Down` | local | AS | none found | vendor | Moving down: adds 4 to the high byte, the next row in the group, crossing groups and thirds when it overflows. |
| 1321 | `MASK04` | `HighRes::BitTwoMask` | data | AS | none found | vendor | The operand byte 4 of Down's ADC, which its BIT also reads to test bit 2 of the high byte. — equate at * + 1 on an instruction operand; see E-Q8 |
| 1322 | `UPDWN8` | `HighRes::StepVertical::DownThirdStore` | local | AS | none found | vendor | Stores LowResBase for the next third (or the page's top) and reloads HPAG. |
| 1323 | `UPDWN9` | `HighRes::StepVertical::DownGroup` | local | AS | none found | vendor | Moving down into the next group when the group bit was clear. |
| 1324 | `UPDW10` | `HighRes::StepVertical::DownRotate` | local | AS | none found | vendor | Rotates the group bit back into LowResBase; then returns through StoreHigh. |
| 1325 | `HGLIN` | `HighRes::Line` | routine | AS | spelling only: AS82 [AS] | vendor | With A = column low, X = column high, Y = row, draws from the cursor to that point, stepping by the error term, and leaves the cursor there. — ASTIL calls this HLIN ($F53A); HLIN is the lo-res statement's name, so prose, see E-Q3 |
| 1326 | `HGLIN1` | `HighRes::Line::SetDeltaX` | local | AS | none found | vendor | Stores the column distance in HGRDX and the error term HGRE. |
| 1327 | `HGLIN2` | `HighRes::Line::SetDeltaY` | local | AS | none found | vendor | Stores the row distance (negative) in HGRDY, the new row, the directions in HGRQUA, and the step count. |
| 1328 | `HGLIN3` | `HighRes::Line::Horizontal` | local | AS | none found | vendor | Steps horizontally through StepHorizontal. |
| 1329 | `HGLIN4` | `HighRes::Line::AddDeltaY` | local | AS | none found | vendor | Adds HGRDY to the error term. |
| 1330 | `HGLIN5` | `HighRes::Line::PlotPoint` | local | AS | none found | vendor | Sets the pixel to HCOLR2 and counts the step, ending through FindCoordinates::Done. |
| 1331 | `HGLIN6` | `HighRes::Line::ChooseStep` | local | AS | none found | vendor | Steps horizontally on carry, else vertically, then adds HGRDX to the error term. |
| 1332 | `MSKTBL` | `HighRes::PixelMasks` | table | AS | none found | vendor | The seven pixel masks of a screen byte ($81-$C0), each with bit 7 set. — indexed from PixelMasks - $F9 |
| 1333 | `MASK1C` | `HighRes::RowInGroupMask` | data | AS | none found | vendor | The byte $1C StepVertical's BIT tests: the high byte's bits for the row within its group of eight. |
| 1334 | `COSTBL` | `HighRes::CosineTable` | table | AS | spelling only: AS82 [AS] | vendor | Seventeen fractions, cosine from 0 to 90 degrees, that scale a rotated shape vector along and across. — the last byte ($FF) is read as COSTBL+1,x for rotation 0 |
| 1335 | `HFIND` | `HighRes::FindCoordinates` | routine | AS | ASTIL [AS] | vendor | Rebuilds HGRX and HGRY from LowResBase/LowResBaseHigh, HNDX and the pixel mask in PlotColor. — Also: HFIND (ASTIL) |
| 1336 | `HFIND1` | `HighRes::FindCoordinates::CountPixel` | local | AS | none found | vendor | Counts pixels in the column until the mask shifts out. |
| 1337 | `HFIND2` | `HighRes::FindCoordinates::StoreColumn` | local | AS | none found | vendor | Stores the column's low byte in HGRX. |
| 1338 | `HFIND3` | `HighRes::FindCoordinates::Done` | entry | AS | none found | vendor | Returns. — Line branches here to return; Proc::Label entry, see E-Q1 |
| 1339 | `DRAW0` | `HighRes::Draw` | routine | AS | none found | vendor | With A = rotation and Y:X = the shape's address, stores the address in SHAPEL/SHAPEH and falls into DrawShape. — ASTIL calls this DRAW ($F601); DRAW is the statement's name, so prose, see E-Q3; falls into HighRes::DrawShape |
| 1340 | `DRAW1` | `HighRes::DrawShape` | routine | AS | none found | vendor | Draws the shape at SHAPEL/SHAPEH with rotation A, HSCALE steps per vector, through PlotStep; COLCNT counts pixels already in the color. — its own proc: Statements::Draw jumps to it; an HSCALE of 0 means 256 |
| 1341 | `DRAW11` | `HighRes::DrawShape::NextVector` | local | AS | none found | vendor | Takes the next three-bit vector and starts its error terms and scale count. |
| 1342 | `DRAW12` | `HighRes::DrawShape::AlongStep` | local | AS | none found | vendor | Adds the cosine to the first error term and steps along the vector on carry. |
| 1343 | `DRAW13` | `HighRes::DrawShape::AcrossStep` | local | AS | none found | vendor | Adds the sine to the second error term and steps across the vector on carry. |
| 1344 | `DRAW14` | `HighRes::DrawShape::CountScale` | local | AS | none found | vendor | Repeats for the scale, then shifts to the byte's next vector. |
| 1345 | `DRAW15` | `HighRes::DrawShape::NextByte` | local | AS | none found | vendor | Reads the next shape byte; zero ends the shape. |
| 1346 | `XDRAW0` | `HighRes::XorDraw` | routine | AS | none found | vendor | With A = rotation and Y:X = the shape's address, stores the address in SHAPEL/SHAPEH and falls into XorDrawShape. — ASTIL calls this XDRAW ($F65D); XDRAW is the statement's name, so prose, see E-Q3; falls into HighRes::XorDrawShape |
| 1347 | `XDRAW1` | `HighRes::XorDrawShape` | routine | AS | none found | vendor | Toggles the shape at SHAPEL/SHAPEH with rotation A through XorStep; COLCNT counts pixels that were clear. — its own proc: Statements::XDraw jumps to it |
| 1348 | `XDRAW2` | `HighRes::XorDrawShape::NextVector` | local | AS | spelling only: AS82 [AS] | vendor | Takes the next three-bit vector and starts its error terms and scale count. — AS82 (spelling only) spells XDRAW2 |
| 1349 | `XDRAW3` | `HighRes::XorDrawShape::AlongStep` | local | AS | none found | vendor | Adds the cosine to the first error term and steps along the vector on carry. |
| 1350 | `XDRAW4` | `HighRes::XorDrawShape::AcrossStep` | local | AS | spelling only: AS82 [AS] | vendor | Adds the sine to the second error term and steps across the vector on carry. — AS82 (spelling only) spells XDRAW4 |
| 1351 | `XDRAW5` | `HighRes::XorDrawShape::CountScale` | local | AS | none found | vendor | Repeats for the scale, then shifts to the byte's next vector. |
| 1352 | `XDRAW6` | `HighRes::XorDrawShape::NextByte` | local | AS | none found | vendor | Reads the next shape byte; zero ends the shape. |
| 1353 | `HFNS` | `ReadHighResCoordinates` | routine | AS | ASTIL [AS]; spelling only: AS82 [AS] | vendor | Reads a column up to 279 and, after a comma, a row up to 191, returning X = column low, Y = column high, A = row (FacExponent as scratch). — Also: HFNS (ASTIL); top level beside ReadLowResCoordinates, both TIL text routines; ASTIL's text says Y is the vertical's msb: it is the column's |
| 1354 | `HFNS1` | `ReadHighResCoordinates::ReadRow` | local | AS | none found | vendor | Saves the column, requires a comma and reads the row. |
| 1355 | `HFNS11` | `RejectHighResArgument` | routine | AS | none found | vendor | Only jumps on to ToIllegalQuantity, for out-of-range coordinates, colors and shape numbers. — its own proc: it follows ReadHighResCoordinates' rts and HColor and ReadShapeNumber branch to it; see E-Q7 |
| 1356 | `HCOLOR` | `Statements::HColor` | routine | AS | AS82 [AS]; spelling only: ASTIL [AS] | vendor | HCOLOR=: reads a color below 8 and stores its pattern from ColorPatterns in HCOLR1. — ASTIL's SETHCOL ($F6EC, X = color) is this routine after its GETBYT: no label today, see E-Q3 |
| 1357 | `HCOLO1` | `Statements::HColor::Done` | entry | AS | none found | vendor | Returns. — HPlot branches here to return; see E-Q1 |
| 1358 | `COLTBL` | `HighRes::ColorPatterns` | table | AS | none found | vendor | The byte patterns of the eight hi-res colors, by HCOLOR number. |
| 1359 | `HPLOT` | `Statements::HPlot` | routine | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | HPLOT: plots the first point unless the statement starts with TO, then draws a line to each TO point. — Also: HPLOT (AS82); ASTIL (spelling only) HPLOT is HighRes::Plot |
| 1360 | `HPLOT1` | `Statements::HPlot::NextTo` | local | AS | none found | vendor | Returns unless the next token is TO. |
| 1361 | `HPLOT2` | `Statements::HPlot::LineTo` | local | AS | none found | vendor | Skips TO, reads the point and draws HighRes::Line to it. |
| 1362 | `ROT` | `Statements::Rot` | routine | AS | AS82 [AS] | vendor | ROT=: reads a byte into HROT, the shapes' rotation. |
| 1363 | `SCALE` | `Statements::Scale` | routine | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | SCALE=: reads a byte into HSCALE, the shapes' scale. |
| 1364 | `SHNUM` | `Statements::ReadShapeNumber` | routine | AS | none found | vendor | Reads a shape number no larger than the table's count, points SHAPEL/SHAPEH at that shape, positions at an optional AT point, and returns A = HROT. — shape 0 is accepted and takes the table's count and unused byte as its offset (document, not fix) |
| 1365 | `SHNUM1` | `Statements::ReadShapeNumber::Index` | local | AS | none found | vendor | Doubles the number for the offset index, carrying into SHAPEH. |
| 1366 | `SHNUM2` | `Statements::ReadShapeNumber::AddOffset` | local | AS | none found | vendor | Adds the shape's offset to the table address, then positions at AT if present. |
| 1367 | `SHNUM3` | `Statements::ReadShapeNumber::Rotation` | local | AS | none found | vendor | Loads HROT and returns. |
| 1368 | `DRAW` | `Statements::Draw` | routine | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | DRAW: reads the shape number and draws it through HighRes::DrawShape. — Also: DRAW (AS82); ASTIL (spelling only) DRAW is HighRes::Draw |
| 1369 | `XDRAW` | `Statements::XDraw` | routine | AS | spelling only: ASTIL [AS], AS82 [AS] | vendor | XDRAW: reads the shape number and toggles it through HighRes::XorDrawShape. — Also: XDRAW (AS82); ASTIL (spelling only) XDRAW is HighRes::XorDraw |

### AppleSoft.Initialization

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1370 | `INIT` | `ColdStart` | routine | AS | M6502 | vendor | Installs the restart and USR vectors, copies the character reader, finds the memory top, sets up the program at $0800 and enters CommandLoop. — Monitor's INIT is InitDisplay, no clash |
| 1371 | `MOVCHG` | `ColdStart::CopyCharacterReader` | local | AS | M6502 | vendor | Copies INITAT's character reader and random seed to page zero. |
| 1372 | `LOOPMM` | `ColdStart::ProbeMemory` | local | AS | M6502 | vendor | Complements and restores a byte on each page until one fails. |
| 1373 | `USEDEC` | `ColdStart::FoundMemoryTop` | local | AS | M6502 | vendor | Rounds the failing page down to 4 KB and sets MemoryTop and StringsBottom. |
| 1374 | `QROOM` | `ColdStart::CheckRoom` | local | AS | M6502 | vendor | Checks room for ProgramStart (REASON), clears the program and points the restart vector at CommandLoop. |

### AppleSoft.InputOutput

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1375 | `TRMNOK` | `HandleBadInput` | routine | AS | M6502 | vendor | A value did not convert: retries INPUT, or reports SYNTAX with the DATA line for READ or as direct for GET. |
| 1376 | `GETDTL` | `HandleBadInput::UseDataLine` | local | AS | M6502 | vendor | READ: takes DataLine as the error line. |
| 1377 | `STCURL` | `HandleBadInput::SetLine` | local | AS | M6502 | vendor | Stores the error line in CurrentLine. |
| 1378 | `SNERR4` | `HandleBadInput::ToSyntaxError` | entry | AS | M6502 | vendor | Jumps on to SNERR; PrintTabOrSpace also branches here (IIeE). |
| 1379 | `SNERR6` | `DiscardAndRetryInput` | routine | AS | none found | vendor | Drops a stacked byte and falls into RetryInput; the shared INPUT code enters here. |
| 1380 | `TRMNO1` | `DROP` | local | AS | M6502 | vendor | Same address as DOAGIN and nothing uses it. — Microsoft's TRMNO1 goes in RetryInput's Also: |
| 1381 | `DOAGIN` | `RetryInput` | routine | AS | M6502 | vendor | Passes error $FE to an active ONERR handler, else prints the retry message and restores TextPointer to the statement. |
| 1382 | `TRMNO2` | `RetryInput::PrintRetry` | local | AS | none found | vendor | No handler: prints the retry message and restores TextPointer from StoppedText. |
| 1383 | `GET` | `Statements::Get` | routine | AS | M6502; spelling only: AS82 [AS] | vendor | GET: rejects direct mode, then reads one key per variable through the shared input code. |
| 1384 | `GETTTY` | `Statements::Get::ReadCharacters` | local | AS | M6502 | vendor | Sets up an empty buffer and enters the shared input code in GET mode. — unreferenced in AS; kept for its M6502 name |
| 1385 | `INPUT` | `Statements::Input` | routine | AS | M6502; spelling only: ASTIL [AS], AS82 [AS] | vendor | INPUT: prints a quoted prompt or ?, rejects direct mode and reads lines for the variable list. |
| 1386 | `INPUT1` | `Statements::Input::NoPrompt` | local | AS | none found | vendor | No quoted prompt: prints a question mark. |
| 1387 | `NOTQTI` | `Statements::Input::CheckDirect` | local | AS | M6502 | vendor | Rejects direct mode and puts a comma before the buffer. |
| 1388 | `GETAGN` | `Statements::Input::ReadLine` | local | AS | M6502 | vendor | Reads the line; a leading Control-C goes to HandleBreak. — unreferenced; kept for its M6502 name |
| 1389 | `QINLIN` | `PromptAndInputLine` | routine | AS | M6502 | vendor | Prints a question mark and reads an input line. — called by the shared INPUT code for extra values |
| 1390 | `GINLIN` | `PromptAndInputLine::ToInputLine` | local | AS | M6502 | vendor | Jumps on to InputLine. — unreferenced in AS; kept for its M6502 name |

### AppleSoft.InterpreterAliases

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1391 | `COMBYTE` | `AppleSoft::ReadCommaAndByte` | alias | AS | ASTIL [AS], AS82 [AS] | vendor | Apple TIL 76's COMBYTE for the comma-and-byte entry; stays in AppleSoft's alias file (D3), pointing at COMBYT's new name. — target named by B2 |

### AppleSoft.NumericConversion

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1392 | `WAIT` | `DROP` | alias | AS | spelling only: AS82 [AS] | vendor | AppleSoft's second label at WAIT's handler (FNWAIT, B1's), used by AppleSoft's dispatch table — use B1's name for FNWAIT (Statements::Wait); AS82 gives only by spelling WAIT: Also only if confirmed; see A-Q6 |

### AppleSoft.PlatformHelpers

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1393 | `SHLOAD` | `Statements::ShLoad` | routine | AS | ASTIL [AS]; spelling only: AS82 [AS] | vendor | SHLOAD: loads a shape table from cassette just below MemoryTop, lowering it and StringsBottom, and points SHPTBL at it; out of memory if it does not fit. — Also: SHLOAD (ASTIL); one proc per build (enhanced: set carry and skip into CallAppleSoftCassette past its CLC) |
| 1394 | `CALLC5` | `Statements::CallAppleSoftCassette` | routine | IIeE | none found | vendor | Switches InternalCxRomOn, calls the firmware's AppleSoftCassette ($C500), switches InternalCxRomOff, and reports out of memory on carry. — IIeE only; carry set selects SHLOAD, clear STORE/RECALL; named for the firmware routine |
| 1395 | `CALLC1` | `Statements::CallAppleSoftCassette::ToOutOfMemory` | local | IIeE | none found | vendor | Only jumps on to OMERR. |
| 1396 | `UPNXT` | `UppercaseNextCharacter` | routine | IIeE | none found | vendor | Reads InputBuffer+1,x for the tokenizer's AT check, uppercased; with bit 7 set it falls into UppercaseInput instead. — IIeE; falls into UppercaseInput; that path returns the current byte, not the next (input bytes have bit 7 clear, so likely unreachable) |
| 1397 | `UPCASE` | `UppercaseInput` | routine | IIeE | none found | vendor | Returns InputBuffer,x, uppercased unless the tokenizer is in REM (EndDelimiter 0), a quote, or DATA (TokenizeState). — IIeE; falls into UppercaseBufferCharacter; see E-Q6 |
| 1398 | `UPBUF` | `UppercaseBufferCharacter` | routine | IIeE | none found | vendor | Loads InputBuffer,x and falls into UppercaseCharacter. — IIeE; the tokenizer calls it; falls into UppercaseCharacter |
| 1399 | `UPBUF1` | `UppercaseCharacter` | routine | IIeE | none found | vendor | Clears bit 5 of A when it is $61 or above, keeping the flags of the load. — IIeE; also folds $7B-$7F to $5B-$5F (document, not fix) |
| 1400 | `UPBUF4` | `UppercaseCharacter::RestoreFlags` | local | IIeE | none found | vendor | Restores the flags and returns. |
| 1401 | `UPBUF5` | `ReadBufferCharacter` | routine | IIeE | none found | vendor | Loads InputBuffer,x unchanged and returns. — IIeE; its own proc: UppercaseInput branches to it |
| 1402 | `SPCLIN` | `PrintSpaceAndLineNumber` | routine | IIeE | none found | vendor | Prints a space, then the line number in A and X through LINPRT. — IIeE; the lister's LIST_LINES argument |
| 1403 | `SHLOD1` | `Statements::ShLoad::StoreEnd` | local | II+ IIe | none found | vendor | Stores the table's last address high byte in Address2High and checks the start's page is above ArraysEnd's. — II+ IIe; named like the firmware's AppleSoftCassette::StoreEnd (same code) |
| 1404 | `SHLOD2` | `Statements::ShLoad::ToOutOfMemory` | local | II+ IIe | none found | vendor | Only jumps on to OMERR. — II+ IIe; the firmware's copy returns carry (OutOfMemory) instead |
| 1405 | `SHLOD3` | `Statements::ShLoad::SetShapeTable` | local | II+ IIe | none found | vendor | Lowers MemoryTop and StringsBottom to the table's start, points SHPTBL and Address1 there, and reads the table with ReadCassette. — II+ IIe; named like the firmware's AppleSoftCassette::ShapeTable; enters ReadCassette + 5 with A = 3 after Cassette::ReadBit |
| 1406 | `CHKCOL` | `CompareCommaColumn` | routine | IIeE | none found | vendor | Compares the output column with the last comma column: TerminalPosition with 33, or with 80 columns (Columns80State) EightyColumns::CursorColumn with 73. — IIeE; Out: carry set at or past the limit; PRINT's comma calls it |
| 1407 | `CHKCO1` | `CompareCommaColumn::Done` | local | IIeE | none found | vendor | Returns. |
| 1408 | `SETA2` | `Statements::SetArrayBlock` | routine | II+ IIe | none found | vendor | Sets Address1 to the array's first element (FMAPT1 from SourceStart) and Address2 to SourceStart plus LineNumber, its last byte. — II+ IIe; same job as the firmware's AppleSoftCassette::ArrayBlock; see E-Q7 |
| 1409 | `TRMSET` | `DistanceToColumn` | routine | IIeE | none found | vendor | Returns A = X minus the output column (TerminalPosition, or EightyColumns::CursorColumn with 80 columns), carry clear on a borrow. — IIeE; PRINT's TAB and comma call it; Entries: SetPosition, Done |
| 1410 | `TRMSE1` | `DistanceToColumn::SetPosition` | entry | IIeE | none found | vendor | Stores A in TerminalPosition, then returns X minus it. — HTab calls it; see E-Q1 |
| 1411 | `TRMSE2` | `DistanceToColumn::Done` | entry | IIeE | none found | vendor | Returns. — HTab branches here; see E-Q1 |
| 1412 | `TRMSE3` | `DistanceToColumn::UseFirmwareColumn` | local | IIeE | none found | vendor | Subtracts EightyColumns::CursorColumn with the caller's carry. — not EightyColumns: that would shadow the firmware scope |
| 1413 | `GETARY` | `Statements::FindCassetteArray` | routine | AS | spelling only: AS82 [AS]; other names here: GETARYPT (ASTIL) | vendor | Finds the array named in the text (SubscriptsAllowed $40 during PTRGET) and sets the cassette range to the length header (VARTIO). — Also: GETARYPT (ASTIL); AS82 (spelling only) GETARY |
| 1414 | `HTAB` | `Statements::HTab` | routine | AS | spelling only: AS82 [AS] | vendor | HTAB: reads a one-based column and sets TerminalPosition, outputting a return for each line width it passes. — one proc per build: the enhanced IIe wraps at the wider of 40 and WindowWidth, others at 40 |
| 1415 | `HTAB1` | `Statements::HTab::NextLine` | local | IIeE | none found | vendor | Starts a line: picks the width, the wider of 40 and WindowWidth. — IIeE |
| 1416 | `HTAB12` | `Statements::HTab::CompareWidth` | local | IIeE | none found | vendor | Sets TerminalPosition to the column if it fits, else subtracts the width and outputs a return. — IIeE |
| 1417 | `HTAB11` | `Statements::HTab::NextLine` | local | II+ IIe | none found | vendor | Starts a line: subtracts 40 and outputs a return while the column is 40 or more. — II+ IIe; same job, same name as the enhanced IIe's |
| 1418 | `HTAB13` | `Statements::HTab::SetColumn` | local | II+ IIe | none found | vendor | Stores the column in TerminalPosition. — II+ IIe |
| 1419 | `LASTWR` | `InterpreterEnd` | location | AS | M6502 | vendor | The byte after the BASIC image ($F800); the 100 reserved bytes cover the Monitor's ROM up to $F864. — Also: LASTWR (M6502); named to match the Commodore part's LASTWR; this file's comment calls the bytes Monitor workspace, but they are Monitor code; see E-Q10 |

### AppleSoft.Print

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1420 | `NCMPOS` | `LAST_COMMA_COLUMN` | constant | AS | M6502 | vendor | Microsoft's last comma-zone column, ((40/14)-1)*14 = 14; AppleSoft's code compares with $18 inline and never uses it. — PET's NCMPOS is in D-workspace; same name proposed there; see C-Q9 |
| 1421 | `CRDO` | `PrintNewline` | routine | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | Prints a carriage return, then complements A for callers that test it. — not PrintReturn: the Monitor's CROUT has that name |
| 1422 | `CRFIN` | `PrintNewline::Finish` | entry | AS | M6502 | vendor | Complements A; the shared string printer enters here after printing a return from a string. |
| 1423 | `PRTRTS` | `PrintNewline::Return` | entry | AS | M6502 | vendor | Return; shared PRINT and the string printer branch here to end. |
| 1424 | `COMPRT` | `PrintComma` | routine | AS | M6502 | vendor | PRINT's comma: a new line past column $18, otherwise spaces to the next 16-column zone (IIeE via CHKCOL and TRMSET). |
| 1425 | `LINCHK` | `PrintComma::NextZone` [IIeE]; DROP [II+ IIe] | local | AS | M6502 | vendor | IIeE: rounds the column up to the next zone and goes on to set it. — II+/IIe: this label falls inside an instruction ($DB11) and nothing uses it there: DROP in those builds; their NextZone is COMPR1; see C-Q3 |
| 1426 | `COMPR1` | `PrintComma::NextZone` | local | II+ IIe | none found | vendor | II+/IIe: adds the zone width; the following bytes overlap the TAB entry. — same job as IIeE's LINCHK |
| 1427 | `TABER` | `PrintTabOrSpace` [IIeE]; DROP [II+ IIe] | routine | AS | M6502 | vendor | TAB( or SPC(: reads the byte argument and ), then prints spaces to the column (TAB) or the count (SPC); falls into PrintSpaces. — IIeE label; II+/IIe: this label falls inside JSR GTBYTC ($DB19), nothing uses it: DROP there, the routine is LINCH1; see C-Q3 |
| 1428 | `LINCH1` | `PrintTabOrSpace` | routine | II+ IIe | none found | vendor | II+/IIe: PRINT_CORE's TAB/SPC entry (PHP), the same routine as IIeE's TABER. — same job, same name as row 1427 |
| 1429 | `TABER1` | `PrintTabOrSpace::ClosedParenthesis` | local | AS | none found | vendor | After the ): SPC prints X spaces; TAB subtracts the column. |
| 1430 | `TABER2` | `PrintTabOrSpace::MoveToColumn` | entry | IIeE | none found | vendor | IIeE: computes the spaces to the target column through TRMSET; PrintComma enters here. |
| 1431 | `ASPAC` | `PrintSpaces` | routine | AS | M6502 | vendor | Prints A spaces. — unreferenced in AS; kept for its M6502 name |
| 1432 | `XSPAC` | `PrintSpaces::CountInX` | entry | AS | M6502 | vendor | Prints X spaces (zero prints none); PrintTabOrSpace's SPC enters here. |
| 1433 | `XSPAC2` | `PrintSpaces::Next` | local | AS | M6502 | vendor | Counts down; zero goes on to ContinuePrint. |
| 1434 | `NOTABR` | `ContinuePrint` | entry | AS | M6502 | vendor | Rereads the current character and continues PRINT at PRINTC without a newline. — inside PrintSpaces' loop; PRINT's ; and the comma and TAB paths branch here; see C-Q3 |
| 1435 | `XSPAC1` | `PrintSpaces::One` | local | AS | M6502 | vendor | Prints one space and loops. |
| 1436 | `OUTSPC` | `PrintSpace` | routine | AS | M6502, ASTIL [AS] | vendor | Loads a space and skips into PrintCharacter. — falls into PrintCharacter (over PrintQuestionMark's load) |
| 1437 | `OUTQST` | `PrintQuestionMark` | routine | AS | M6502, ASTIL [AS] | vendor | Loads ? and falls into PrintCharacter. |
| 1438 | `OUTDO` | `PrintCharacter` | routine | AS | M6502, ASTIL [AS]; spelling only: AS82 [AS] | vendor | Sends A with bit 7 set (and FLASHB for printable characters) through OUTCH, then waits SPEEDZ; returns A with bit 7 clear. — not CharacterOut: the Monitor's COUT has that name |
| 1439 | `TRYOUT` | `DROP` | local | AS | M6502 | vendor | Same address as OUTLOC and nothing uses it. — Microsoft's TRYOUT goes in PrintCharacter::Send's Also: |
| 1440 | `OUTLOC` | `PrintCharacter::Send` | local | AS | M6502 | vendor | Sends the character through OUTCH and applies the speed delay. |
| 1441 | `GETRTS` | `PrintCharacter::Return` | local | AS | M6502 | vendor | Return. — nothing in AS uses it (BASIC 4's linked strings define their own); kept for its M6502 name |

### Basic1

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1444 | `REVISD` | `KEEP` | switch | none |  | vendor | 1 builds the revised BASIC 1 chip — KEEP: predefined by C# and tests |
| 1445 | `BUFPAG` | `INPUT_BUFFER_PAGE` | switch | P1 P1R | M6502 | vendor | 0: BASIC 1's buffer is in page zero |
| 1446 | `BUFLEN` | `INPUT_BUFFER_LENGTH` | switch | P1 P1R | M6502, HV1, HV1R | vendor | 80-byte buffer |
| 1447 | `NULCMD` | `NULL_COMMAND` | switch | P1 P1R | M6502 | vendor | 1 reserves NullCount |
| 1448 | `TERMINAL_FIRST` | `KEEP` | switch | P1 P1R |  | vendor | 1 places terminal storage before general scratch — SDK name; fits the style |
| 1449 | `FULL_STACK_TOP` | `KEEP` | switch | P1 P1R |  | vendor | 1 uses the whole page-one stack — SDK name; fits the style |
| 1450 | `STACK_RESERVE_19` | `KEEP` | switch | P1 P1R |  | vendor | 1 reserves 19 stack levels — SDK name; fits the style |
| 1451 | `LOCAL_TRMPOS` | `LOCAL_TERMINAL_POSITION` | switch | P1 P1R |  | vendor | 1 keeps BASIC's own TerminalPosition — renamed for the Microsoft name it spells |
| 1452 | `VARTXT_IN_LINNUM` | `VARIABLE_LIST_IN_LINE_NUMBER` | switch | P1 P1R |  | vendor | 1 shares VariableListPointer with LineNumber — renamed for the Microsoft names it spells |
| 1453 | `CLOCK_IN_PAGE2` | `KEEP` | switch | P1 P1R |  | vendor | 1 puts the clock in page two — SDK name; fits the style |
| 1454 | `STATUS_IN_PAGE2` | `KEEP` | switch | P1 P1R |  | vendor | 1 puts the I/O status in page two — SDK name; fits the style |
| 1455 | `RND_TIMER_9044` | `KEEP` | switch | P1 P1R |  | vendor | 1 makes RND(0) read the early timer at $9044 — SDK name; fits the style |
| 1456 | `ERROR_PADDING5` | `KEEP` | switch | P1 P1R |  | vendor | 1 keeps five unused error-table bytes — SDK name; fits the style |
| 1457 | `GO_TOKEN` | `KEEP` | switch | P1 P1R |  | vendor | 1 adds the GO reserved word (COMMODORE_DISPATCH_TABLES) — SDK name; fits the style |
| 1458 | `BAD_DATA_ERROR` | `KEEP` | switch | P1 P1R |  | vendor | 1 spells the file-data error BAD DATA — SDK name; fits the style |
| 1459 | `COMMAND_TEST_CHARACTER` | `KEEP` | switch | P1 P1R |  | vendor | 1 tests A after the command loop fetches its first character — SDK name; fits the style |
| 1460 | `COMMAND_RESET_BEFORE_INSERT` | `KEEP` | switch | P1 P1R |  | vendor | 1 clears variables and relinks before inserting a line — SDK name; fits the style |
| 1461 | `LINK_RETURNS` | `KEEP` | switch | P1 P1R |  | vendor | 1 returns from relinking instead of entering the command loop — SDK name; fits the style |
| 1462 | `EARLY_LINE_EDIT` | `KEEP` | switch | P1 P1R |  | vendor | 1 keeps the early line-edit entries and unconditional newline — SDK name; fits the style |
| 1463 | `TOKENIZE_SKIP_SPACES` | `KEEP` | switch | P1 P1R |  | vendor | 1 skips spaces while matching reserved words — SDK name; fits the style |
| 1464 | `NEW_CLEAR_CARRY` | `KEEP` | switch | P1 P1R |  | vendor | 1 clears carry before NEW adds two to the program start — SDK name; fits the style |
| 1465 | `RUN_SET_ZERO` | `KEEP` | switch | P1 P1R |  | vendor | 1 loads zero after RUN positions the text pointer — SDK name; fits the style |
| 1466 | `RESET_STACK_EARLY` | `KEEP` | switch | P1 P1R |  | vendor | 1 stores the return address before moving the stack pointer (original chip) — SDK name; fits the style |
| 1467 | `RESET_STACK_PADDING` | `KEEP` | switch | P1 P1R |  | vendor | 1 keeps the revised reset's extra RTS and unused byte — SDK name; fits the style |
| 1468 | `LIST_GUARD_OFFSET` | `KEEP` | switch | P1 P1R |  | vendor | 1 stops LIST when a malformed line's offset wraps — SDK name; fits the style |
| 1469 | `STATEMENT_FETCH_NOP` | `KEEP` | switch | P1 P1R |  | vendor | 1 keeps the later NOP before the direct-mode branch — SDK name; fits the style |
| 1470 | `EARLY_SEPARATOR_CHECK` | `KEEP` | switch | P1 P1R |  | vendor | 1 checks the separator before reading the line link — SDK name; fits the style |
| 1471 | `SHORT_END_BRANCH` | `KEEP` | switch | P1 P1R |  | vendor | 1 branches straight to the end-of-program handler — SDK name; fits the style |
| 1472 | `EARLY_STATEMENT_DISPATCH` | `KEEP` | switch | P1 P1R |  | vendor | 1 uses the earlier dispatch carry and error paths — SDK name; fits the style |
| 1473 | `STOP_BY_LINE_NUMBER` | `KEEP` | switch | P1 P1R |  | vendor | 1 detects direct STOP from CurrentLine rather than the text page — SDK name; fits the style |
| 1474 | `NULL_INCREMENT_LIMIT` | `KEEP` | switch | P1 P1R |  | vendor | first rejected NULL count (10) — SDK name; fits the style |
| 1475 | `RETURN_LOW_FOR_POINTER` | `KEEP` | switch | P1 P1R |  | vendor | 1 makes RETURN's FOR search set the low pointer byte — SDK name; fits the style |
| 1476 | `QUOTE_BRANCH_FIRST` | `KEEP` | switch | P1 P1R |  | vendor | 1 tests quotes first while scanning DATA and REM — SDK name; fits the style |
| 1477 | `TIME_LONG_ERROR` | `KEEP` | switch | P1 P1R |  | vendor | 1 uses the long jump for a bad TI$ length — SDK name; fits the style |
| 1478 | `PRINT_CLEAR_SPC_CARRY` | `KEEP` | switch | P1 P1R |  | vendor | 1 clears carry before dispatching SPC — SDK name; fits the style |
| 1479 | `PRINT_NULL_PADDING` | `KEEP` | switch | P1 P1R |  | vendor | 1 prints NullCount nulls after a newline — SDK name; fits the style |
| 1480 | `PRINT_TOKEN_SPACING` | `KEEP` | switch | P1 P1R |  | vendor | 1 tells TAB from SPC by token and uses the early space loop — SDK name; fits the style |
| 1481 | `ALWAYS_SKIP_CHARACTER` | `KEEP` | switch | P1 P1R |  | vendor | 1 sends cursor-right as a space on every channel — SDK name; fits the style |
| 1482 | `INPUT_ERROR_EDITOR_PATCH` | `KEEP` | switch | P1 P1R |  | vendor | 1 calls the editor ROM's GET/READ error-line helper — SDK name; fits the style |
| 1483 | `INPUT_STOP_EDITOR_PATCH` | `KEEP` | switch | P1 P1R |  | vendor | 1 calls the editor ROM's stop helper for a blank INPUT — SDK name; fits the style |
| 1484 | `GET_POINTER_Y_FIRST` | `KEEP` | switch | P1 P1R |  | vendor | 1 loads GET's buffer pointer high byte first — SDK name; fits the style |
| 1485 | `GET_STRING_EDITOR_PATCH` | `KEEP` | switch | P1 P1R |  | vendor | 1 calls the editor ROM's GET string helper — SDK name; fits the style |
| 1486 | `NEXT_COUNTED_STACK` | `KEEP` | switch | P1 P1R |  | vendor | 1 counts through the FOR frame instead of computing offsets — SDK name; fits the style |
| 1487 | `CLOCK_EDITOR_PATCH` | `KEEP` | switch | P1 P1R |  | vendor | 1 uses the editor ROM's TI and TI$ checks — SDK name; fits the style |
| 1488 | `INTIDX_USE_FRMNUM` | `SUBSCRIPT_CHECKS_NUMERIC` | switch | P1 P1R |  | vendor | 1 evaluates subscripts with FRMNUM (type checked), 0 with FRMEVL — renamed: spells two routine names; asserted 0 or 1 |
| 1489 | `POSINT_CHECK_TYPE` | `POSITIVE_INTEGER_CHECKS_TYPE` | switch | P1 P1R |  | vendor | 1 makes POSINT check the numeric type — renamed for the routine name it spells; follow part B2's name for POSINT |
| 1490 | `ARRAY_SAVE_OFFSET_HIGH` | `KEEP` | switch | P1 P1R |  | vendor | 1 saves the element offset's high byte (fixes the early array bug) — SDK name; fits the style |
| 1491 | `USER_FN_LOW_CHECK` | `KEEP` | switch | P1 P1R |  | vendor | 1 tests only the low byte for an undefined FN — SDK name; fits the style |
| 1492 | `STRING_CLEAR_FACOV` | `STRING_CLEARS_FAC_EXTENSION` | switch | P1 P1R |  | vendor | 1 clears FacExtension when making a temporary string — renamed for FACOV (FacExtension) |
| 1493 | `GC_FULL_POINTER` | `COLLECTOR_FULL_POINTER` | switch | P1 P1R |  | vendor | 1 makes the collector test both bytes of the chosen descriptor pointer — GC is an abbreviation; COLLECTOR matches CollectorStep/CollectorPointer |
| 1494 | `GC_PATCH_ARRAY_STEP` | `COLLECTOR_PATCH_ARRAY_STEP` | switch | P1 P1R |  | vendor | 1 makes the collector call the editor ROM's array-descriptor step |
| 1495 | `GC_SUBTRACT_OFFSET` | `COLLECTOR_SUBTRACT_OFFSET` | switch | P1 P1R |  | vendor | 1 subtracts three for the descriptor offset instead of masking (GRBPAS) |
| 1496 | `REJECT_ZERO_SLICES` | `KEEP` | switch | P1 P1R |  | vendor | 1 rejects zero LEFT$/RIGHT$ counts and a zero MID$ start — SDK name; fits the style |
| 1497 | `PREAM_INDIRECT_RETURN` | `STRING_PREAMBLE_INDIRECT_RETURN` | switch | P1 P1R |  | vendor | 1 returns from PREAM through the writable jump — renamed for PREAM; follow part B2's name for PREAM |
| 1498 | `ASC_SHARED_LEN_JUMP` | `KEEP` | switch | P1 P1R |  | vendor | 1 sends ASC through LEN's numeric-conversion jump — SDK name; fits the style |
| 1499 | `PEEK_PRESERVE_ADDRESS` | `KEEP` | switch | P1 P1R |  | vendor | 1 restores the previous PokeAddress after PEEK — SDK name; fits the style |
| 1500 | `PEEK_GUARD_ROM` | `KEEP` | switch | P1 P1R |  | vendor | 1 returns zero for the ROM pages from ROM_ORIGIN to InterpreterEnd — SDK name; fits the style |
| 1501 | `PEEK_PAD_GUARD` | `KEEP` | switch | P1 P1R |  | vendor | 1 emits eight padding bytes in PEEK — SDK name; fits the style |
| 1502 | `SHORT_FMUL_ZERO` | `SHORT_MULTIPLY_ZERO` | switch | P1 P1R |  | vendor | 1 uses BASIC 1's short multiply-by-zero branch in FMULTT — renamed for FMUL |
| 1503 | `EARLY_FIN_LIMIT` | `EARLY_INPUT_EXPONENT_LIMIT` | switch | P1 P1R |  | vendor | 1 keeps BASIC 1's exponent-12 test in FIN's exponent digits — renamed for FIN |
| 1504 | `PRECISE_FOUT_LIMIT` | `PRECISE_OUTPUT_LIMIT` | switch | P1 P1R |  | vendor | 1 uses BASIC 1's 999,999,999.5 output threshold — renamed for FOUT |
| 1505 | `ZERO_AT_FHALF` | `ZERO_IN_HALF_CONSTANT` | switch | P1 P1R |  | vendor | 1 defines ZERO inside the 0.5 constant (BASIC 2 and 4) — renamed for FHALF |
| 1506 | `WAIT_EASTER_EGG` | `KEEP` | switch | P1 P1R |  | vendor | 1 builds BASIC 2's hidden WAIT message and omitted-mask handler — SDK name; fits the style |
| 1507 | `RANDOM_SEED_TAIL` | `KEEP` | switch | P1 P1R |  | vendor | last byte of the reader template's seed ($59 BASIC 1, $58 later) — SDK name; fits the style |
| 1508 | `INIT_MARK_DIRECT` | `KEEP` | switch | P1 P1R |  | vendor | 1 marks CurrentLine direct during initialization — SDK name; fits the style |
| 1509 | `INIT_LINE_WIDTH` | `KEEP` | switch | P1 P1R |  | vendor | 1 initializes LineWidth and LastCommaColumn — SDK name; fits the style |
| 1510 | `INIT_DELAY_SIZE` | `KEEP` | switch | P1 P1R |  | vendor | 1 sets CollectorStep after clearing the flags — SDK name; fits the style |
| 1511 | `INIT_EARLY_BUFFER_SETUP` | `KEEP` | switch | P1 P1R |  | vendor | 1 restores the page-zero buffer's comma and prints a newline — SDK name; fits the style |
| 1512 | `PROBE_LOAD_ZERO` | `KEEP` | switch | P1 P1R |  | vendor | 1 loads zero before setting the first RAM address — SDK name; fits the style |
| 1513 | `PROBE_LOAD_INDEX_ZERO` | `KEEP` | switch | P1 P1R |  | vendor | 1 loads Y with zero instead of copying A — SDK name; fits the style |
| 1514 | `PROBE_SAVE_START` | `KEEP` | switch | P1 P1R |  | vendor | 1 saves the program start before probing RAM — SDK name; fits the style |
| 1515 | `PROBE_STOP_AT_SCREEN` | `KEEP` | switch | P1 P1R |  | vendor | 1 stops the probe at the early screen boundary — SDK name; fits the style |
| 1516 | `PROBE_TEST_BYTE` | `KEEP` | switch | P1 P1R |  | vendor | first byte written when testing RAM ($92 BASIC 1, $55 later) — SDK name; fits the style |
| 1517 | `START_CARRY_PROGRAM_START` | `KEEP` | switch | P1 P1R |  | vendor | 1 carries the program-start increment into its high byte — SDK name; fits the style |
| 1518 | `START_BANNER_AFTER_FREE` | `KEEP` | switch | P1 P1R |  | vendor | 1 prints the early sign-on after the free-memory count — SDK name; fits the style |
| 1519 | `ROMLOC` | `ROM_ORIGIN` | constant | P1 P1R | M6502, HV1, HV1R | vendor | start of the BASIC ROM; PEEK's ROM guard starts here |
| 1520 | `BASIC4_OUTPUT_PADDING` | `KEEP` | switch | P1 P1R |  | vendor | 1 builds BASIC 4's checksum byte and patch space before INPRT — SDK name; fits the style |
| 1521 | `RESET_STACK_POINTER` | `KEEP` | switch | P1 P1R |  | vendor | low byte of STACK_END - $101 - 2*RESET_STACK_EARLY: the reset stack pointer — SDK name; fits the style |

### Basic2

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1522 | `ROMLOC` | `ROM_ORIGIN` | constant | P2 | M6502, HV2 | vendor | start of the BASIC 2 ROM ($C000) |
| 1523 | `SHORT_FMUL_ZERO` | `SHORT_MULTIPLY_ZERO` | switch | P2 |  | vendor | 1 uses BASIC 1's short multiply-by-zero branch in FMULTT — renamed for FMUL |
| 1524 | `EARLY_FIN_LIMIT` | `EARLY_INPUT_EXPONENT_LIMIT` | switch | P2 |  | vendor | 1 keeps BASIC 1's exponent-12 test in FIN's exponent digits — renamed for FIN |
| 1525 | `PRECISE_FOUT_LIMIT` | `PRECISE_OUTPUT_LIMIT` | switch | P2 |  | vendor | 1 uses BASIC 1's 999,999,999.5 output threshold — renamed for FOUT |
| 1526 | `ZERO_AT_FHALF` | `ZERO_IN_HALF_CONSTANT` | switch | P2 |  | vendor | 1 defines ZERO inside the 0.5 constant (BASIC 2 and 4) — renamed for FHALF |
| 1527 | `WAIT_EASTER_EGG` | `KEEP` | switch | P2 |  | vendor | 1 builds BASIC 2's hidden WAIT message and omitted-mask handler — SDK name; fits the style |
| 1528 | `BASIC4_OUTPUT_PADDING` | `KEEP` | switch | P2 |  | vendor | 1 builds BASIC 4's checksum byte and patch space before INPRT — SDK name; fits the style |
| 1529 | `LASTWR` | `InterpreterEnd` | entry | P2 | M6502, HV2 | vendor | label after the interpreter's last byte; PEEK's ROM guard ends at its page — Commodore.Basic1Patches defines BASIC 1's (other part): same name; BASIC 4's extension follows it |

### Basic4

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1530 | `REVISD` | `KEEP` | switch | none |  | vendor | 1 builds the revised $B000 BASIC 4 chip — KEEP: predefined by C# and tests |
| 1531 | `DISK_STATUS_STRING` | `KEEP` | switch | P4 P4R |  | vendor | 1: BASIC 4 reserves the DS$ descriptor — SDK name; fits the style |
| 1532 | `LINE_WIDTH_STORAGE` | `KEEP` | switch | P4 P4R |  | vendor | 0: BASIC 4 omits LineWidth and LastCommaColumn — SDK name; fits the style |
| 1533 | `EXTENDED_DISK_VECTORS` | `KEEP` | switch | P4 P4R |  | vendor | 1: BASIC 4 defines the disk-command jump table — SDK name; fits the style |
| 1534 | `ROMLOC` | `ROM_ORIGIN` | constant | P4 P4R | M6502, HV4, HV4R; spelling only: CBM4S79 [P4 P4R] | vendor | start of the BASIC 4 ROM ($B000) |
| 1535 | `SHORT_FMUL_ZERO` | `SHORT_MULTIPLY_ZERO` | switch | P4 P4R |  | vendor | 1 uses BASIC 1's short multiply-by-zero branch in FMULTT — renamed for FMUL |
| 1536 | `EARLY_FIN_LIMIT` | `EARLY_INPUT_EXPONENT_LIMIT` | switch | P4 P4R |  | vendor | 1 keeps BASIC 1's exponent-12 test in FIN's exponent digits — renamed for FIN |
| 1537 | `PRECISE_FOUT_LIMIT` | `PRECISE_OUTPUT_LIMIT` | switch | P4 P4R |  | vendor | 1 uses BASIC 1's 999,999,999.5 output threshold — renamed for FOUT |
| 1538 | `ZERO_AT_FHALF` | `ZERO_IN_HALF_CONSTANT` | switch | P4 P4R |  | vendor | 1 defines ZERO inside the 0.5 constant (BASIC 2 and 4) — renamed for FHALF |
| 1539 | `WAIT_EASTER_EGG` | `KEEP` | switch | P4 P4R |  | vendor | 1 builds BASIC 2's hidden WAIT message and omitted-mask handler — SDK name; fits the style |
| 1540 | `BASIC4_OUTPUT_PADDING` | `KEEP` | switch | P4 P4R |  | vendor | 1 builds BASIC 4's checksum byte and patch space before INPRT — SDK name; fits the style |
| 1541 | `LASTWR` | `InterpreterEnd` | entry | P4 P4R | M6502, K4S79 [P4 P4R], HV4, HV4R, HVK4 [P4 P4R] | vendor | label after the interpreter, where BASIC 4's extension begins ($D472); PEEK's guard ends here — same name as BASIC 2's and BASIC 1's |

### Commodore.Basic1Patches

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1542 | `COMMODORE_BASIC1_EDITOR_PATCHES` | `CommodoreBasic1EditorPatches` | macro | P1 P1R |  | vendor | Emits BASIC 1's patch routines placed after the sign-on code in the editor ROM's spill area — D2: macro stays, renamed to PascalCase |
| 1543 | `INPSTP` | `StopEmptyInput` | routine | P1 P1R | other names here: PATCH1 (HV1, HV1R) | vendor | Clears carry and jumps to STPEND, ending a blank terminal INPUT without BREAK — Same job as the INPSTP label ChannelInput defines in other builds (part C): same name; HV1 PATCH1 in Also |
| 1544 | `TISTR` | `CheckClockString` | routine | P1 P1R | other names here: PATCH2 (HV1, HV1R) | vendor | Entered by jmp from ISVAR: a reserved-area string variable named T goes to TISTR1, else its rts ends the evaluation — HV1 PATCH2 in Also; the rts returns from the caller's evaluation, not to ISVAR |
| 1545 | `TISTR2` | `CheckClockString::NotClock` | local | P1 P1R | none found | vendor | rts reached when the string variable is not TI$ — HV1 LE1AA in Also |
| 1546 | `TINUM` | `RouteNumericVariable` | routine | P1 P1R | other names here: PATCH3 (HV1, HV1R) | vendor | Entered by jmp: ordinary variables go to GOMOVF, reserved ones to TINUM1 (T) or QSTATV (others) — HV1 PATCH3 in Also |
| 1547 | `TINUM2` | `RouteNumericVariable::Reserved` | local | P1 P1R | none found | vendor | Reserved-area variable (FACLO negative): tests for T |
| 1548 | `TINUM3` | `RouteNumericVariable::ToClockNumber` | local | P1 P1R | none found | vendor | Only jumps on to TINUM1, the TI handler — To + part C's name for TINUM1; see F-Q11 |
| 1549 | `GETSTR` | `BeginGetString` | routine | P1 P1R | other names here: PATCH4 (HV1, HV1R) | vendor | Stores the GET delimiter in CHARAC, advances X past the buffer pointer and jumps to GETST1 — HV1 PATCH4 in Also |
| 1550 | `GETDTL` | `GetDataLine` | routine | P1 P1R | spelling only: HV1, HV1R; other names here: PATCH5 (HV1, HV1R) | vendor | Returns DATLIN in A/Y when INPFLG is negative (READ), else Y = $FF (direct line), for the error's line number — Same job as GETDTL in ChannelInput/AppleSoft (part C): same name; HV1 PATCH5 in Also |
| 1551 | `GETDT1` | `GetDataLine::NotRead` | local | P1 P1R | none found | vendor | GET case: loads Y = $FF and returns — HV1 LE1C9 in Also |
| 1552 | `INCTRM` | `AdvanceTerminalPosition` | routine | P1 P1R | other names here: PATCH6 (HV1, HV1R) | vendor | Increments TRMPOS when zero is set (screen channel); a wrap to 0 restarts from the editor's CQPNTR — HV1 PATCH6 in Also |
| 1553 | `INCTR1` | `AdvanceTerminalPosition::Increment` | local | P1 P1R | none found | vendor | Increments TRMPOS, retried after reloading it from CQPNTR on wrap — HV1 LE1CE in Also |
| 1554 | `INCTR2` | `AdvanceTerminalPosition::Done` | local | P1 P1R | none found | vendor | Shared rts — HV1 LE1D8 in Also |
| 1555 | `GETST1` | `ResumeGetString` | routine | P1 P1R | other names here: PATCH7 (HV1, HV1R) | vendor | Stores X in TXTPTR, discards BeginGetString's return address, A = Y and jumps to RESETC — HV1 PATCH7 in Also; reached by jmp from BeginGetString across INCTRM |
| 1556 | `LASTWR` | `InterpreterEnd` | location | P1 P1R | M6502, HV1, HV1R | vendor | Marks the byte after BASIC 1's last ROM patch; MEMORY_ACCESS compares against its high byte — Must match part D's LASTWR (Basic2/Basic4) and part E's; see F-Q12 |
| 1557 | `COMMODORE_BASIC1_ARRAY_PATCH` | `CommodoreBasic1ArrayPatch` | macro | P1 P1R |  | vendor | Emits the six-byte array-header step at $E7F3 in the editor ROM |
| 1558 | `ARYINC` | `ArrayHeaderSize` | routine | P1 P1R | none found | vendor | Returns A = dimensions * 2 + 5 (plus the shift's carry) and Y = 0, for the collector's array walk — Called from MsBasic.StringGarbageCollection under patchedArrayStep |

### Commodore.Basic4DiskCommands

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1559 | `XFN1` | `INSERT_FIRST_NAME` | constant | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Template code $F1: BuildCommand appends the first filename (and copies it to the second) — Codes are prefixed constants (DOS X2); see F-Q5 |
| 1560 | `XFN2` | `INSERT_SECOND_NAME` | constant | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Template code $F2: appends the second filename, or drops the preceding separator when empty |
| 1561 | `XID` | `INSERT_DISK_ID` | constant | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Template code $D0: appends the two DISKID bytes |
| 1562 | `XREC` | `INSERT_RECORD_LENGTH` | constant | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Template code $E0: inserts LRECL (record length, or W after INSERT_FILE_TYPE chose S); skipped when 0 |
| 1563 | `XWRT` | `INSERT_FILE_TYPE` | constant | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Template code $E1: inserts L when LRECL is set, else S (and stores W in LRECL) |
| 1564 | `XD1` | `INSERT_FIRST_DRIVE` | constant | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Template code $D1: inserts DRIVE1 as an ASCII digit |
| 1565 | `XD2` | `INSERT_SECOND_DRIVE` | constant | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Template code $D2: inserts DRIVE2 as an ASCII digit |
| 1566 | `COMMODORE_BASIC4_DISK_COMMANDS` | `CommodoreBasic4DiskCommands` | macro | P4 P4R |  | vendor | Emits the disk statements, status handling and command builder |
| 1567 | `TABLD` | `Disk::CommandTemplates` | table | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Command templates indexed by Y offsets in each handler: catalog, open, append, header, collect, backup, copy, concat, rename, scratch — Offsets are bare numbers in the code; see F-Q5 |
| 1568 | `CATLOG` | `Statements::Catalog` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | CATALOG and DIRECTORY: saves LA in WSW, parses, then lists the directory to the chosen channel with STOP and pause — Reached through the kernal's CQDCAT; see F-Q1 |
| 1569 | `CATALG` | `Statements::Catalog::SelectTemplate` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Template length 1, or 2 when a drive was given — Unreferenced, kept for its K4S79 name |
| 1570 | `CATBLD` | `Statements::Catalog::Open` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Builds the $ command and opens file 14 on secondary $60 |
| 1571 | `WG220` | `Statements::Catalog::ReadPairs` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads Y byte pairs (3 for the first line, then 2), leaving the block count in TMP2 |
| 1572 | `SKIPB` | `Statements::Catalog::PrintSeparator` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints the space after the block count — Unreferenced, kept for its K4S79 name |
| 1573 | `WG250` | `Statements::Catalog::NextCharacter` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads and prints one name-line character; checks STOP and the space-bar pause |
| 1574 | `WG255` | `Statements::Catalog::Paused` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Waits for any key after a space paused the listing |
| 1575 | `WG240` | `Statements::Catalog::EndOfLine` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints carriage return at a line's zero byte and reads the next line's two pairs |
| 1576 | `WG235` | `Statements::Catalog::DropAndClose` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Pulls a stacked byte before closing — Unreferenced (nothing pushes for it), kept for its K4S79 name |
| 1577 | `WG230` | `Statements::Catalog::Close` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Restores channels and closes file 14 |
| 1578 | `SUBA` | `Statements::Catalog::OutputCharacter` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Selects the catalog output, prints A and restores the default channels — Nested routine only Catalog calls |
| 1579 | `SUBB` | `Statements::Catalog::SelectOutput` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Selects the saved channel (WSW) unless the saved device (CNTDN) is the screen |
| 1580 | `SUBBR` | `Statements::Catalog::SelectOutput::Done` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | rts |
| 1581 | `ENTRY0` | `Disk::FindSecondaryAddress` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Finds the first secondary address from $62 not in SAT; stores it in SA (also Y) |
| 1582 | `ENTRY1` | `Disk::FindSecondaryAddress::NextAddress` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tries the next secondary address |
| 1583 | `ENTRY2` | `Disk::FindSecondaryAddress::NextFile` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Compares against the next open file's secondary address |
| 1584 | `RFOUND` | `Disk::FindSecondaryAddress::Found` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Stores the unused address in SA |
| 1585 | `DOPEN` | `Statements::DOpen` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | DOPEN: needs a name and file number, rejects a second name or drive, opens with ,type,length when given and @ when replacing — K4S79 DOPEN; the $FF96 entry's DOPEN goes in prose; see F-Q1 |
| 1586 | `DOPEN2` | `Statements::DOpen::Open` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Chooses a secondary address and template length 3 |
| 1587 | `RECLCK` | `Statements::DOpen::TypedOpen` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Template length 7, adding the file type and record length — Unreferenced, kept for its K4S79 name |
| 1588 | `LEAV` | `Statements::DOpen::CheckReplace` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prefixes @ in TBUFF when the name began with @ |
| 1589 | `LEAV1` | `Statements::DOpen::NoReplace` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Builds the command from position 0 and opens |
| 1590 | `APPEND` | `Statements::Append` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | APPEND: needs a name and file number, rejects other options, opens with ,A — K4S79 APPEND; jump-table APPEND in prose |
| 1591 | `DAPPEN` | `Statements::Append::Open` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Chooses a secondary address and sends the append template |
| 1592 | `ERRCHL` | `Disk::ReadStatus` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads the error channel into DS$, allocating its buffer first when DSDESC is 0 — Falls into AllocateStatus; branches to ReadErrorChannel |
| 1593 | `GETDS` | `Disk::AllocateStatus` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Gets 40 bytes of string space for DS$, links it back to DSDESC ($0D, 0) and clears ST — Kernal's CQRDDS target; falls into ReadErrorChannel. The link's low byte is the literal $0D, DSDESC's address |
| 1594 | `ECHKS` | `Disk::ReadErrorChannel` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Defaults FA to 8, reads channel 15 into the DS$ buffer up to carriage return or zero, terminates it with 0 — No bound on the length: a reply over 40 characters overruns into the link |
| 1595 | `EREAD` | `Disk::ReadErrorChannel::SendTalk` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Commands the device to talk on secondary $6F |
| 1596 | `LOOP1` | `Disk::ReadErrorChannel::NextCharacter` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Stores the next received character |
| 1597 | `ERREND` | `Disk::ReadErrorChannel::Terminate` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Writes the zero terminator and untalks |
| 1598 | `FORMAT` | `Statements::Header` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | HEADER: needs a name and drive, closes the unit's files, confirms in direct mode, formats (with ID when given), reports a bad disk — K4S79 FORMAT; jump-table FORMAT in prose |
| 1599 | `FERRO` | `Statements::Header::Reject` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | jmp SNERR for missing name or drive — Unreferenced (reached by fall-through), kept for its K4S79 name; Reject, not ToSyntaxError, to avoid shadowing Statements::ToSyntaxError |
| 1600 | `DFORMA` | `Statements::Header::Confirm` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Closes the unit's files then asks; returns when declined — Files are closed even when declined |
| 1601 | `FBUILD` | `Statements::Header::Build` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Template length 4, or 6 with the disk ID |
| 1602 | `FCONT` | `Statements::Header::Send` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Sends the N command |
| 1603 | `FERRS` | `Statements::Header::CheckResult` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads the status; a first digit of 2 or more means a bad disk — Unreferenced, kept for its K4S79 name |
| 1604 | `FERRP` | `Statements::Header::ToBadDisk` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to BADDIS |
| 1605 | `DCLOSE` | `Statements::DClose` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | DCLOSE: accepts only a file number and unit; closes that file, or all the unit's files — K4S79 DCLOSE; jump-table DCLOSE in prose |
| 1606 | `DCLSE` | `Statements::DClose::Close` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Forgets DS$, then closes LA through the kernal or branches to CloseDeviceFiles |
| 1607 | `DCLALL` | `Disk::CloseDeviceFiles` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Closes every logical file whose device is FA, rescanning the table after each close — DClose branches into it; HEADER, COLLECT and BACKUP call it |
| 1608 | `DCLLP` | `Disk::CloseDeviceFiles::NextFile` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Steps down the open-file table |
| 1609 | `DCLBYE` | `Disk::CloseDeviceFiles::Done` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | rts when no file of the device remains |
| 1610 | `BOBREC` | `Disk::PositionRecord` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Gives FILE NOT OPEN unless LA is open, else sends P, secondary, record (POKER) and position (RECPOS) — Reached by jmp from Record; FNLEN2 is RECPOS's shared byte |
| 1611 | `DRECG` | `Disk::PositionRecord::FileOpen` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Gets the file's table entry and forgets DS$ |
| 1612 | `DREBLD` | `Disk::PositionRecord::Build` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Writes the five command bytes in TBUFF — Unreferenced, kept for its K4S79 name |
| 1613 | `COLECT` | `Statements::Collect` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | COLLECT: accepts only drive and unit, closes the unit's files, sends V with the drive — K4S79 COLECT; jump-table COLLECT in prose |
| 1614 | `DCOLLE` | `Statements::Collect::CloseFiles` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Closes the unit's files — Unreferenced, kept for its K4S79 name |
| 1615 | `DCOLL0` | `Statements::Collect::Send` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Sends the template (length 1 or 2) |
| 1616 | `BACKUP` | `Statements::Backup` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | BACKUP: needs both drives and nothing else but the unit; closes the unit's files and sends D — K4S79 BACKUP; falls into Disk::SendCommand |
| 1617 | `BERRO` | `Statements::Backup::Reject` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | jmp SNERR |
| 1618 | `BBACK` | `Statements::Backup::CheckOthers` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Rejects names, file number, record and replace options |
| 1619 | `DBACKU` | `Statements::Backup::CloseFiles` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Closes the unit's files and selects the D template — Unreferenced, kept for its K4S79 name |
| 1620 | `TRANS` | `Disk::SendCommand` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Builds the command from the template (A = length, Y = offset) then falls into OpenCommandChannel |
| 1621 | `TRANS1` | `Disk::OpenCommandChannel` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Opens the built command on secondary 15 ($6F) through LISTN and OPENIB — PositionRecord jumps here, so its own proc |
| 1622 | `DCOPY` | `Statements::Copy` | routine | P4 P4R | spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | COPY: a whole-drive copy with both drives alone, else two names checked; sends the C template — Undocumented spelling DCOPY (the overlay's, to avoid m6502's COPY); see F-Q3 |
| 1623 | `COPY2` | `Statements::Copy::CheckFiles` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Checks a file copy's parameters |
| 1624 | `COPCON` | `Statements::Copy::LoadFlags` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reloads PRSCHK — Unreferenced, kept for its K4S79 name |
| 1625 | `COPY3` | `Statements::Copy::Send` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Sends the copy template — The whole-drive and file forms use one template; empty names drop their colons |
| 1626 | `CONCAT` | `Statements::Concat` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | CONCAT: checks two names and sends the concatenate template — K4S79 CONCAT |
| 1627 | `RSFN` | `Disk::AppendFirstName` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Copies the first filename's pointer and length into the second's and falls into AppendSecondName — So a template must insert the second name before the first; all do |
| 1628 | `RDFN` | `Disk::AppendSecondName` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Copies the second filename into TBUFF at X, or backs X over the separator when it is empty — Out: A = Y = saved Y, carry set |
| 1629 | `RDMOV` | `Disk::AppendSecondName::NextCharacter` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Copies one character |
| 1630 | `RDRT0` | `Disk::AppendSecondName::Empty` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Removes the separator before an empty name |
| 1631 | `RDRT1` | `Disk::AppendSecondName::Done` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Restores Y and sets carry |
| 1632 | `RID` | `Disk::AppendDiskId` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Appends the two DISKID bytes to TBUFF; returns A = X |
| 1633 | `DSAVE` | `Statements::DSave` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | DSAVE: needs a name, accepts drive and unit and @; saves through SV3 — K4S79 DSAVE |
| 1634 | `DSAVE2` | `Statements::DSave::Save` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Chooses the open template |
| 1635 | `SAVLD0` | `Statements::DSave::Replace` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prefixes @ and builds from position 1 — Unreferenced, kept for its K4S79 name |
| 1636 | `SAVLD1` | `Statements::DSave::NoReplace` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Builds from position 0 |
| 1637 | `DLOAD` | `Statements::DLoad` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | DLOAD: needs a name, accepts drive and unit; clears VERCK and loads through LOADNP — K4S79 DLOAD |
| 1638 | `DLOERR` | `Statements::DLoad::Reject` | entry | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | jmp SNERR, also the target of Rename's bne — Rename branches here; see F-Q4 |
| 1639 | `DLOAD2` | `Statements::DLoad::Load` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Builds the name and loads |
| 1640 | `RENAME` | `Statements::Rename` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | RENAME: needs two names, accepts drive and unit; sends R — K4S79 RENAME |
| 1641 | `DREN` | `Statements::Rename::Send` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Sends the rename template — Unreferenced, kept for its K4S79 name |
| 1642 | `DSCRTC` | `Statements::Scratch` | routine | P4 P4R | none found | vendor | SCRATCH: needs a name; confirms in direct mode, sends S and prints the drive's reply in direct mode — Undocumented spelling DSCRTC (the overlay's); see F-Q3 |
| 1643 | `DSCRAT` | `Statements::Scratch::Confirm` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Asks; returns when declined — Unreferenced, kept for its K4S79 name |
| 1644 | `NUMSCR` | `Statements::Scratch::ShowResult` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | In direct mode reads DS$ and prints it between carriage returns — Unreferenced, kept for its K4S79 name |
| 1645 | `NUMLP` | `Statements::Scratch::NextCharacter` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints the next DS$ character |
| 1646 | `NUMPRT` | `Statements::Scratch::EndLine` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints the closing carriage return |
| 1647 | `NUMBYE` | `Statements::Scratch::Done` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | rts |
| 1648 | `DDIREC` | `Disk::TestDirect` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Sets zero when TXTPTR's high byte is 2 (the input buffer's page): direct mode |
| 1649 | `DXCR0` | `Disk::TestDirect::Done` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | rts — Unreferenced, kept for its K4S79 name |
| 1650 | `RUSURE` | `Disk::Confirm` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | In direct mode prints ARE YOU SURE and accepts Y or YES then return; carry set when declined — A zero byte while draining a rejected answer ends with carry clear (accepted) |
| 1651 | `RUSUR1` | `Disk::Confirm::Ask` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints the question and restores the default channels — Unreferenced, kept for its K4S79 name |
| 1652 | `RUSUR2` | `Disk::Confirm::ReadAnswer` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads and matches the answer — Unreferenced, kept for its K4S79 name |
| 1653 | `ANSNO` | `Disk::Confirm::Rejected` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Drains input to carriage return with carry set |
| 1654 | `ANSYES` | `Disk::Confirm::Accepted` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Clears carry |
| 1655 | `ANSBYE` | `Disk::Return` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Shared rts, ending Confirm and BadDisk outside direct mode — Scope-level label: BadDisk branches into Confirm here |
| 1656 | `BADDIS` | `Disk::BadDisk` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints the BAD DISK message in direct mode |
| 1657 | `OLDCLR` | `ForgetDiskStatus` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Marks DS$'s buffer as garbage (length 40, $FF) and zeroes its length and ST; keeps Y — Kernal4's TALK and LISTEN call it, so top level; see F-Q2 |
| 1658 | `OLDCL1` | `ForgetDiskStatus::Clear` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Zeroes ST and DSDESC |
| 1659 | `SENDP` | `Disk::BuildCommand` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Starts the command at TBUFF+0 and falls into BuildCommandAt |
| 1660 | `SENDP1` | `Disk::BuildCommandAt` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Forgets DS$, expands A template bytes from Y+1 into TBUFF at X, then names it the kernal filename — DOpen and DSave enter here after @; falls into SetCommandName |
| 1661 | `SENDP2` | `Disk::BuildCommandAt::NextByte` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Counts down KCOUNT and fetches the next template byte |
| 1662 | `RXFN1` | `Disk::BuildCommandAt::FirstName` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tests for INSERT_FIRST_NAME — Unreferenced, kept for its K4S79 name |
| 1663 | `RXFN2` | `Disk::BuildCommandAt::SecondName` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tests for INSERT_SECOND_NAME |
| 1664 | `RXREC` | `Disk::BuildCommandAt::PutRecordLength` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tests for INSERT_RECORD_LENGTH |
| 1665 | `RXID` | `Disk::BuildCommandAt::PutDiskId` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tests for INSERT_DISK_ID |
| 1666 | `RXWRT` | `Disk::BuildCommandAt::FileType` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tests for INSERT_FILE_TYPE |
| 1667 | `RXD1` | `Disk::BuildCommandAt::PutFirstDrive` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tests for INSERT_FIRST_DRIVE |
| 1668 | `RXD2` | `Disk::BuildCommandAt::PutSecondDrive` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tests for INSERT_SECOND_DRIVE; other codes are dropped |
| 1669 | `RXDD` | `Disk::BuildCommandAt::DriveDigit` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Converts the drive number to ASCII |
| 1670 | `RPLCE` | `Disk::BuildCommandAt::StoreByte` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Stores A in TBUFF and continues |
| 1671 | `TRANR` | `Disk::SetCommandName` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Sets FNLEN = X and FNADR = TBUFF |
| 1672 | `RWRT` | `Disk::ChooseFileType` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Returns L for a relative file, else S after storing W in LRECL |
| 1673 | `RWRT1` | `Disk::ChooseFileType::Sequential` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Sequential write: S, with W for the record field |
| 1674 | `RWRTS` | `Disk::ChooseFileType::Done` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | rts |

### Commodore.Basic4DiskParser

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1675 | `COMMODORE_BASIC4_DISK_PARSER` | `CommodoreBasic4DiskParser` | macro | P4 P4R |  | vendor | Emits the disk parameter parser and its helpers |
| 1676 | `DOSPAR` | `Disk::ParseParameters` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Clears the disk workspace (FA = 8) and parses #, W, L, R, D, ON U, U, I, names and TO into PRSCHK and the kernal fields — Out: A = PRSCHK; bit constants, see F-Q6 |
| 1677 | `PARSEL` | `Disk::ParseParameters::NextParameter` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Dispatches on a first-part parameter letter |
| 1678 | `PARNXT` | `Disk::ParseParameters::CheckDrive` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tests D, ON, U and I — R is skipped without effect |
| 1679 | `NEXT7` | `Disk::ParseParameters::CheckName` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tests for a quoted or parenthesized name |
| 1680 | `SNER1` | `Disk::ParseParameters::Reject` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | jmp SNERR for a bad or repeated first-part parameter |
| 1681 | `LOGADR` | `Disk::ParseParameters::ReadLogicalFile` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads # file number (not 0) into LA |
| 1682 | `RECLEN` | `Disk::ParseParameters::ReadRecordLength` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | W sets the write flag; L reads a length (not 0 or 255) into LRECL |
| 1683 | `RECOO` | `Disk::ParseParameters::ReadLength` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads L's length |
| 1684 | `RECON` | `Disk::ParseParameters::RecordSeen` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Sets the record/write bit |
| 1685 | `DONE1` | `Disk::ParseParameters::ToDone` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to Done |
| 1686 | `NAME11` | `Disk::ParseParameters::ToFirstName` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to FirstName |
| 1687 | `ON1` | `Disk::ParseParameters::OnUnit` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Parses ON U then continues |
| 1688 | `UNIT1` | `Disk::ParseParameters::Unit` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Parses U then continues |
| 1689 | `DRV1` | `Disk::ParseParameters::ReadFirstDrive` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads D (0 or 1) into DRIVE1 and DRIVE2 |
| 1690 | `QTYER2` | `Disk::ParseParameters::ToQuantityError` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to QuantityError |
| 1691 | `IDENT` | `Disk::ParseParameters::ReadDiskId` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | I: rejects a second ID, copies the next two text bytes to DISKID — DIDCHK shares LRECL's byte, which Parse clears |
| 1692 | `IDCON` | `Disk::ParseParameters::CopyId` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Starts the two-byte copy |
| 1693 | `NEXT3` | `Disk::ParseParameters::NextIdByte` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Advances TXTPTR |
| 1694 | `NEXT4` | `Disk::ParseParameters::StoreIdByte` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Stores an ID byte |
| 1695 | `NAME1` | `Disk::ParseParameters::FirstName` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Evaluates the first name into TBUF2, dropping a leading @ from FNADR/FNLEN |
| 1696 | `LOOP6` | `Disk::ParseParameters::CopyName` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Copies one name character |
| 1697 | `NAMCON` | `Disk::ParseParameters::StoreNameByte` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Stores it in TBUF2 |
| 1698 | `DELIM1` | `Disk::ParseParameters::FirstDelimiter` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | After a first-part parameter: end, comma, ON or TO |
| 1699 | `NXXX` | `Disk::ParseParameters::ExpectComma` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Comma continues the first part |
| 1700 | `NEXT6` | `Disk::ParseParameters::CheckOn` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | ON without a comma |
| 1701 | `NEXT6A` | `Disk::ParseParameters::CheckTo` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | TO starts the second part |
| 1702 | `SNER8` | `Disk::ParseParameters::RejectDelimiter` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | jmp SNERR for another character — Unreferenced (fall-through), kept for its K4S79 name |
| 1703 | `PARSE2` | `Disk::ParseParameters::SecondPart` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Dispatches a parameter after TO: D, ON, U or a name |
| 1704 | `SNER2` | `Disk::ParseParameters::RejectSecond` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | jmp SNERR |
| 1705 | `DRV2` | `Disk::ParseParameters::ReadSecondDrive` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads D (0 or 1) into DRIVE2 |
| 1706 | `ON2` | `Disk::ParseParameters::SecondOnUnit` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Parses ON U in the second part |
| 1707 | `UNIT2` | `Disk::ParseParameters::SecondUnit` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Parses U in the second part |
| 1708 | `NAME2` | `Disk::ParseParameters::SecondName` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Evaluates the second name into FNADR2/FNLEN2 |
| 1709 | `DELIM2` | `Disk::ParseParameters::SecondDelimiter` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | After a second-part parameter: end, comma, ON or U |
| 1710 | `SNER3` | `Disk::RejectParameter` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | jmp SNERR, shared by the parser, ParseOnUnit and EvaluateName — Scope-level label: three routines branch here |
| 1711 | `DONE` | `Disk::ParseParameters::Done` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Returns A = PRSCHK |
| 1712 | `QTYERR` | `Disk::QuantityError` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Gives ILLEGAL QUANTITY (ERRFC) — Called from the parser and Record |
| 1713 | `ON` | `Disk::ParseOnUnit` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Requires U after the ON token and falls into ParseUnit |
| 1714 | `UNIT` | `Disk::ParseUnit` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads a device number 3-31 into FA and sets the unit bit |
| 1715 | `NEWNAM` | `Disk::EvaluateName` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Evaluates a name of 1-16 characters (17 with a leading @, which sets the replace bit once); A = length, X/Y = address — In: zero set when the name is not yet given |
| 1716 | `LENCHK` | `Disk::EvaluateName::CheckLength` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Without @: at most 16 |
| 1717 | `ERRLEN` | `Disk::EvaluateName::TooLong` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Gives STRING TOO LONG (ERRLS) |
| 1718 | `NXXT5` | `Disk::EvaluateName::Replace` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Sets the replace bit |
| 1719 | `NEXT5` | `Disk::EvaluateName::LoadLength` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | A = length — Unreferenced, kept for its K4S79 name |
| 1720 | `NXX5` | `Disk::EvaluateName::LoadAddress` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | X/Y = the name's address from INDEX1 |
| 1721 | `GETVAL` | `Disk::ReadNextValue` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Advances with CHRGET and falls into ReadValue |
| 1722 | `GTVL2` | `Disk::ReadValue` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Evaluates a byte parameter into X: a number, or an expression in parentheses; SYNTAX ERROR at the end of the statement — Record calls it |
| 1723 | `GTVLCN` | `Disk::ReadValue::Present` | local | P4 P4R | none found | vendor | A non-digit must be (expression) — Undocumented (GTVLCN is the overlay's); not dropped since referenced |
| 1724 | `NUMERC` | `Disk::ReadValue::Number` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | A digit is read by GETBYT |

### Commodore.Basic4Extension

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1725 | `DISK_STATUS_STRING` | `KEEP` | switch | none |  | vendor | Default for opening the file alone: BASIC 4 has DS$'s descriptor — SDK build switch, already UPPER_SNAKE |
| 1726 | `LINE_WIDTH_STORAGE` | `KEEP` | switch | none |  | vendor | Default for opening the file alone: no line-width storage — SDK build switch, already UPPER_SNAKE |
| 1727 | `EXTENDED_DISK_VECTORS` | `KEEP` | switch | none |  | vendor | Default for opening the file alone: the disk-command vectors — SDK build switch, already UPPER_SNAKE |
| 1728 | `COMMODORE_BASIC4_EXTENSION` | `CommodoreBasic4Extension` | macro | P4 P4R |  | vendor | Emits the monitor, RECORD, disk commands, parser and ROM end from $D472 |
| 1729 | `revised` | `KEEP` | parameter of COMMODORE_BASIC4_EXTENSION | P4 P4R |  | vendor | 0 or 1 for the original or revised ROM; only asserted — KEEP (camelCase parameter) |

### Commodore.Basic4Monitor

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1730 | `COMMODORE_BASIC4_MONITOR` | `CommodoreBasic4Monitor` | macro | P4 P4R |  | vendor | Emits the machine-language monitor |
| 1731 | `CALLE` | `Monitor::EnterByCall` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Entered by jump (the kernal's reset with the diagnostic line low): marks C and joins SaveState — Monitor as a scope, see F-Q7; carry is not set up before SaveState's adc (BRKE clears it) |
| 1732 | `BRKE` | `Monitor::EnterByBreak` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | From BRK through the kernal: restores channels, marks B, pops Y, X, A and status into the save area — Falls into SaveState |
| 1733 | `B3` | `Monitor::SaveState` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Pops the return address less 1 into PCL/PCH, saves CINV and SP, enables interrupts, shows the registers — EnterByCall jumps here |
| 1734 | `B5` | `Monitor::SaveState::ShowEntry` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints carriage return, the entry letter and * then runs R — Unreferenced, kept for its K4S79 name |
| 1735 | `STRT` | `Monitor::Prompt` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints the . prompt, reads a command letter skipping periods and spaces — Falls into Dispatch |
| 1736 | `ST1` | `Monitor::Prompt::SkipSeparator` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads past . and space |
| 1737 | `S0` | `Monitor::Dispatch` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Finds A in CommandKeys, saves the index in SAVX and runs the command by rts, else jumps through USRCMD — SaveState branches here |
| 1738 | `S1` | `Monitor::Dispatch::Compare` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Compares with one command key |
| 1739 | `S2` | `Monitor::Dispatch::Next` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tries the previous key |
| 1740 | `PUTP` | `Monitor::SetProgramCounter` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Copies TMP0 to the saved PC |
| 1741 | `DM` | `Monitor::PrintBytes` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints A bytes (0 = 256) from TMP0, each after a space, advancing TMP0 |
| 1742 | `DM1` | `Monitor::PrintBytes::NextByte` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints one byte |
| 1743 | `BYTE` | `Monitor::AlterByte` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads a byte; when present stores and verifies it at TMP0 (failure abandons to ReportError); advances |
| 1744 | `BY3` | `Monitor::AlterByte::Advance` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Advances TMP0 and counts TMPC down |
| 1745 | `SETR` | `Monitor::SelectRegisters` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Points TMP0 at FLGS and returns A = 5 |
| 1746 | `SPAC2` | `Monitor::PrintTwoSpaces` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints a space and falls into PrintSpace |
| 1747 | `SPACE` | `Monitor::OutputSpace` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints a space (BIT skips PrintCarriageReturn's load) — Falls into PrintCarriageReturn |
| 1748 | `CRLF` | `Monitor::PrintCarriageReturn` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints carriage return |
| 1749 | `INCTMP` | `Monitor::NextAddress` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Increments TMP0, setting WRAP past $FFFF |
| 1750 | `SETWR` | `Monitor::NextAddress::Done` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | rts |
| 1751 | `CMDS` | `Monitor::CommandKeys` | table | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | The eight command characters : ; R M G X L S |
| 1752 | `ADRH` | `Monitor::CommandsHigh` | table | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | High bytes of each command's address less 1 — Two-byte values are Name and NameHigh: alternative CommandsLow/CommandsHigh kept as a pair |
| 1753 | `ADRL` | `Monitor::CommandsLow` | table | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Low bytes of each command's address less 1 |
| 1754 | `REGK` | `Monitor::RegisterHeading` | message | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Carriage return and the 28-character register heading — DisplayRegisters prints 29 bytes |
| 1755 | `ALTRIT` | `Monitor::StartLine` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints carriage return, . and the character in Y, then two spaces |
| 1756 | `DSPLYR` | `Monitor::DisplayRegisters` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | R: prints the heading, then PC, IRQ vector and the five register bytes |
| 1757 | `D2` | `Monitor::DisplayRegisters::PrintHeading` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints one heading character |
| 1758 | `DSPLYM` | `Monitor::DisplayMemory` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | M: reads two addresses, prints eight-byte rows until past the end, STOP or wrap |
| 1759 | `DSP1` | `Monitor::DisplayMemory::NextRow` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Checks STOP, wrap and the end address, prints a row |
| 1760 | `BEQS1` | `Monitor::ToPrompt` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to Prompt; several commands branch here — Scope-level label |
| 1761 | `ERRS1` | `Monitor::ToReportError` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to ReportError; several commands branch here — Scope-level label |
| 1762 | `ALTR` | `Monitor::AlterRegisters` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | ;: optionally sets PC and IRQ vector, then alters the five register bytes — Jumps into AlterBytes |
| 1763 | `AL2` | `Monitor::AlterRegisters::ReadVector` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads an optional IRQ vector |
| 1764 | `AL3` | `Monitor::AlterRegisters::AlterSaved` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Selects the register bytes and branches to AlterBytes |
| 1765 | `ALTM` | `Monitor::AlterMemory` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | :: reads an address and alters up to eight bytes — Falls into AlterBytes |
| 1766 | `A4` | `Monitor::AlterBytes` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Stores TMPC and alters bytes while present — AlterRegisters branches here, so its own proc |
| 1767 | `A5` | `Monitor::AlterBytes::NextByte` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Alters the next byte |
| 1768 | `A9` | `Monitor::AlterBytes::Done` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Branches to ToPrompt — Unreferenced, kept for its K4S79 name |
| 1769 | `MGO` | `Monitor::Go` | routine | P4 P4R | none found | vendor | G: optionally sets PC, restores SP, CINV and registers, resumes by RTI — Undocumented spelling MGO (the overlay's); see F-Q3 |
| 1770 | `G1` | `Monitor::Go::Resume` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Restores the saved state and returns into the program |
| 1771 | `EXIT` | `Monitor::Exit` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | X: restores the saved stack pointer and jumps to READY |
| 1772 | `ERRL` | `Monitor::LoadOrSave::Fail` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to ReportError — Not ToReportError, which would shadow the scope-level label |
| 1773 | `LD` | `Monitor::LoadOrSave` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | L and S: parses "name",device,start,end (device not 0 or 3), loads by LD15 or saves by SV5 |
| 1774 | `L1` | `Monitor::LoadOrSave::SkipSpaces` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Skips spaces before the name |
| 1775 | `L2` | `Monitor::LoadOrSave::ToFail` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Branch relay to Fail |
| 1776 | `L3` | `Monitor::LoadOrSave::NextNameCharacter` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Stores a name character in SAVNAM, at most 16 |
| 1777 | `L4` | `Monitor::LoadOrSave::CheckLength` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Fails at 16 characters, else continues; also a relay |
| 1778 | `L5` | `Monitor::LoadOrSave::Perform` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | With no more parameters: only L may proceed; loads and checks the status |
| 1779 | `L6` | `Monitor::LoadOrSave::RequireLoad` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Relay to ToFail when not a load |
| 1780 | `L7` | `Monitor::LoadOrSave::CheckLoadError` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Relay on a load error, else back to Prompt |
| 1781 | `L8` | `Monitor::LoadOrSave::AfterName` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Carriage return or a comma and device |
| 1782 | `L9` | `Monitor::LoadOrSave::RequireComma` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Branch relay |
| 1783 | `L10` | `Monitor::LoadOrSave::RejectKeyboard` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Device 0 fails |
| 1784 | `L11` | `Monitor::LoadOrSave::RejectScreen` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Device 3 fails — Unreferenced, kept for its K4S79 name |
| 1785 | `L12` | `Monitor::LoadOrSave::ReadStart` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads the start address into TMP2 |
| 1786 | `L13` | `Monitor::LoadOrSave::ReadEnd` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads the end address into EAL/EAH |
| 1787 | `L20` | `Monitor::LoadOrSave::SkipTrailingSpaces` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Skips spaces after the end address |
| 1788 | `L14` | `Monitor::LoadOrSave::RequireSave` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only S may give addresses; saves through SV5 |
| 1789 | `WROA` | `Monitor::PrintAddress` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints TMP0 as four hexadecimal digits — Falls into PrintByte |
| 1790 | `WROA1` | `Monitor::PrintAddress::PrintHigh` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints the high byte, leaving the low for PrintByte — Unreferenced, kept for its K4S79 name |
| 1791 | `WROB` | `Monitor::PrintByte` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints A as two hexadecimal digits — Falls into PrintPair |
| 1792 | `WRTWO` | `Monitor::PrintPair` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints the characters in X then A |
| 1793 | `ASCII` | `Monitor::HexDigit` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Converts a nibble to 0-9 or A-F |
| 1794 | `ASC1` | `Monitor::HexDigit::Digit` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Adds the ASCII base |
| 1795 | `T2T2` | `Monitor::SwapAddresses` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Exchanges TMP0 and TMP2 |
| 1796 | `T2T21` | `Monitor::SwapAddresses::NextByte` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Exchanges one byte |
| 1797 | `RDOA` | `Monitor::ReadAddress` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads up to two bytes into TMP0 high then low; carry from the second |
| 1798 | `RDOA2` | `Monitor::ReadAddress::LowByte` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads the low byte |
| 1799 | `RDEXIT` | `Monitor::ReadAddress::Done` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | rts |
| 1800 | `RDOB` | `Monitor::ReadByte` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Skips one space, reads two hex digits into A with carry set, or returns carry clear for two spaces |
| 1801 | `RDOB1` | `Monitor::ReadByte::CheckBlank` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Tests the first character for a space — Unreferenced, kept for its K4S79 name |
| 1802 | `RDOB2` | `Monitor::ReadByte::HighDigit` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads the high digit |
| 1803 | `RDOB3` | `Monitor::ReadByte::LowDigit` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads the low digit and combines |
| 1804 | `HEXIT` | `Monitor::HexValue` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Converts 0-9 or A-F to its value (no check) |
| 1805 | `HEX09` | `Monitor::Return` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | rts shared by HexValue and ReadCharacter — Scope-level label: ReadCharacter branches into HexValue's rts |
| 1806 | `RDOC` | `Monitor::ReadCharacter` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads a character; at carriage return abandons the command and returns to Prompt |
| 1807 | `ERROPR` | `Monitor::ShowError` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Prints ? and returns to Prompt — Kernal4 sets USRCMD to it |

### Commodore.Basic4Patches

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1808 | `COMMODORE_BASIC4_OPERAND_SPLIT` | `CommodoreBasic4OperandSplit` | macro | P4 P4R |  | vendor | Emits the $B000 chip's checksum byte, the ISVAR trampoline, the revised ROM's patches and patch space to $BF8C |
| 1809 | `revised` | `KEEP` | parameter of COMMODORE_BASIC4_OPERAND_SPLIT | P4 P4R |  | vendor | Selects the revised chip's checksum byte and patches — KEEP |
| 1810 | `ISVAR` | `EvaluateVariable` | entry | P4 P4R | M6502; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | Jumps to ISVAR1 past the patch area — Same job as ISVAR in VariableEvaluation (part C): same name; see F-Q11 |
| 1811 | `ADJDS` | `TestStatusString` | routine | P4R | other names here: PATCHG (HV4R) | vendor | Revised ROM: for FindStringLink, a string whose high byte matches a live DS$ goes to CompareStatusLow, else AddLength — HV4R PATCHG in Also; fixes the original's match on a released DS$ address (documented, not changed) |
| 1812 | `ADJDS2` | `TestStatusString::NoStatus` | local | P4R | other names here: PATH0 (HV4R) | vendor | DS$ empty: discards the saved byte — HV4R PATH0 in Also |
| 1813 | `ADJDS3` | `TestStatusString::ToAddLength` | local | P4R | other names here: PATH1 (HV4R) | vendor | Only jumps on to FindStringLink::AddLength — HV4R PATH1 in Also |
| 1814 | `GONEGT` | `FetchStatementCharacter` | routine | P4R | other names here: PATCHH (HV4R) | vendor | Revised ROM: gets the next character and gives SYNTAX ERROR for the PI token as a statement — HV4R PATCHH in Also |
| 1815 | `GONEG1` | `FetchStatementCharacter::ToGetCurrentCharacter` | local | P4R | none found | vendor | Only jumps on to CHRGOT |
| 1816 | `INPNUL` | `HandleBlankInput` | routine | P4R | other names here: PATCHI (HV4R) | vendor | Revised ROM: a blank INPUT line stops at the terminal, retries from a file, or continues at end of file — HV4R PATCHI in Also |
| 1817 | `INPNU1` | `HandleBlankInput::FromFile` | local | P4R | none found | vendor | Tests the end-of-file bit; otherwise jumps to GETAGN |
| 1818 | `INPNU2` | `HandleBlankInput::ToInputContinue` | local | P4R | none found | vendor | Only jumps on to INPCON — Name follows part B2's INPCON |

### Commodore.Basic4Record

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1819 | `COMMODORE_BASIC4_RECORD` | `CommodoreBasic4Record` | macro | P4 P4R |  | vendor | Emits RECORD and the disk parameter checks |
| 1820 | `SYNERR` | `Statements::ToSyntaxError` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to SNERR; Record branches back to it — Scope-level label before Record |
| 1821 | `RECORD` | `Statements::Record` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; spelling only: CBM4S79 [P4 P4R], HV4, HV4R | vendor | RECORD #file, record[, position]: record as a number or (expression), position 1-254 (default 1); then PositionRecord — K4S79 RECORD |
| 1822 | `NUMADR` | `Statements::Record::Number` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Evaluates a numeric record number |
| 1823 | `REXNEX` | `Statements::Record::Position` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Reads an optional position |
| 1824 | `DONER` | `Statements::Record::ToPositionRecord` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to Disk::PositionRecord |
| 1825 | `QTYER1` | `Statements::Record::ToQuantityError` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to Disk::QuantityError |
| 1826 | `CHK1` | `Disk::CheckSingleName` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | HEADER and SCRATCH: accepts only name, unit and drive, then requires the name — Jumps into RequireFirstName |
| 1827 | `CHKER1` | `Disk::ToSyntaxError` | local | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Only jumps on to SNERR; every check branches here — Scope-level label |
| 1828 | `CHK2` | `Disk::RequireFirstName` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Requires the first-name bit; returns A = PRSCHK |
| 1829 | `CHK3` | `Disk::CheckDriveOnly` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | COLLECT and CATALOG: rejects all but unit and first drive |
| 1830 | `CHK4` | `Disk::CheckTwoNames` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | COPY and CONCAT: rejects file number, record and replace — Falls into RequireTwoNames |
| 1831 | `CHK5` | `Disk::RequireTwoNames` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Requires both names; returns A = PRSCHK |
| 1832 | `CHK6` | `Disk::RequireNameAndFile` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | Requires a first name and file number; returns A = PRSCHK |

### Commodore.Basic4RomEnd

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1833 | `COMMODORE_BASIC4_ROM_END` | `CommodoreBasic4RomEnd` | macro | P4 P4R |  | vendor | Emits the $D000 chip's checksum byte, StoreStatusLink, the sign-on and patch fill |
| 1834 | `CKSUMD` | `ExtensionChecksum` | data | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | The $D000 chip's checksum-adjustment byte — Unreferenced, kept for its K4S79 name |
| 1835 | `DSLINK` | `Disk::StoreStatusLink` | routine | P4 P4R | other names here: PATCH5 (HVK4) | vendor | Stores A in ST and in DS$'s buffer at Y, then decrements Y — HVK4 PATCH5 in Also; scope Disk continued at the ROM end |
| 1836 | `SIGNON` | `Basic4SignOnMessage` | message | P4 P4R | HV4, HV4R, HVK4 [P4 P4R] | vendor | The BASIC 4 banner and two carriage returns |

### Commodore.Basic4SystemEquates

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1837 | `CINV` | `IrqVector` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | two-byte RAM IRQ vector; the monitor saves and restores it |
| 1838 | `SATUS` | `IoStatus` | alias | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's I/O status ST; the disk commands clear and test it — same byte as Commodore.Equates CQSTAT ($96 in BASIC 4): one definition with Also: CQSTAT, SATUS (see D-Q6) |
| 1839 | `VERCK` | `LoadVerifyFlag` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | 0 for LOAD, 1 for VERIFY; the monitor and DLOAD clear it |
| 1840 | `LDTND` | `OpenFileCount` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | number of entries in the kernal's file tables; DCLOSE scans them |
| 1841 | `DFLTO` | `DefaultOutputDevice` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's current output device; CATALOG saves it |
| 1842 | `WSW` | `CatalogOutputFile` | alias | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's cassette write flag, which CATALOG reuses for its output file — kernal name for the byte unknown here; a scoped alias in the catalog routine if a kernal name is kept (see D-Q10) |
| 1843 | `SAVX` | `MonitorCommandIndex` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; other names here: T1 (HVK4) | vendor | the monitor's index of the command it dispatched; LOAD/SAVE test it |
| 1844 | `TMPC` | `MonitorCount` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; other names here: RCNT (HVK4), T2 (HVK4) | vendor | the monitor's BRK marker character, then a byte count — HVK4 also calls it RCNT, T2 |
| 1845 | `CNTDN` | `CatalogOutputDevice` | alias | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's cassette countdown, which CATALOG reuses to save DefaultOutputDevice |
| 1846 | `EAL` | `EndAddress` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's load/save end address; the monitor's SAVE sets it |
| 1847 | `EAH` | `EndAddressHigh` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | high byte of EndAddress |
| 1848 | `FNLEN` | `FilenameLength` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's current filename length |
| 1849 | `LA` | `LogicalFile` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's current logical file number |
| 1850 | `SA` | `SecondaryAddress` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's current secondary address |
| 1851 | `FA` | `DeviceNumber` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's current device (primary address) |
| 1852 | `FNADR` | `FilenamePointer` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | two-byte pointer to the kernal's current filename |
| 1853 | `WRAP` | `MonitorAddressWrapped` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; other names here: FSBLK (HVK4) | vendor | set when the monitor's address passes $FFFF (INCTMP) — HVK4 calls it FSBLK |
| 1854 | `TMP0` | `MonitorAddress` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; other names here: STAL (HVK4) | vendor | two-byte address the monitor is working on — HVK4 calls it STAL |
| 1855 | `TMP2` | `MonitorEndAddress` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | two-byte second address of a monitor command (range end) |
| 1856 | `FNADR2` | `SecondFilenamePointer` | alias | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | second filename pointer for two-name disk commands; shares MonitorEndAddress |
| 1857 | `BAD` | `MonitorHexByte` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the monitor's hex-byte assembly scratch (RDOB) at $0100 — same address as NumberBuffer: an alias in BASIC 4 |
| 1858 | `PCH` | `ProgramCounterHigh` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the monitor's saved program counter, high byte (stored first) — matches IIeEquates' name for the Apple Monitor's same job; note high byte at the lower address |
| 1859 | `PCL` | `ProgramCounter` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the monitor's saved program counter, low byte — matches IIeEquates |
| 1860 | `FLGS` | `SavedStatus` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the monitor's saved processor status — matches IIeEquates |
| 1861 | `ACC` | `SavedA` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the monitor's saved accumulator — matches IIeEquates |
| 1862 | `XR` | `SavedX` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the monitor's saved X — matches IIeEquates |
| 1863 | `YR` | `SavedY` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the monitor's saved Y — matches IIeEquates |
| 1864 | `SP` | `SavedStackPointer` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the monitor's saved stack pointer — matches IIeEquates |
| 1865 | `INVH` | `SavedIrqVectorHigh` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | high byte of IrqVector as BRK found it |
| 1866 | `INVL` | `SavedIrqVector` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | low byte of IrqVector as BRK found it |
| 1867 | `SAVNAM` | `MonitorFilename` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; other names here: ZZZ1 (HVK4) | vendor | buffer for the monitor's LOAD/SAVE filename — HVK4 calls it ZZZ1 |
| 1868 | `LAT` | `LogicalFileTable` | table | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's table of open logical file numbers |
| 1869 | `FAT` | `DeviceTable` | table | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's table of the open files' devices |
| 1870 | `SAT` | `SecondaryAddressTable` | table | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's table of the open files' secondary addresses |
| 1871 | `FNLEN2` | `SecondFilenameLength` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; other names here: TAPE2 (HVK4) | vendor | length of a disk command's second filename — HVK4 calls it TAPE2 |
| 1872 | `RECPOS` | `RecordPosition` | alias | P4 P4R | other names here: TAPE2 (HVK4) | vendor | RECORD's byte position; shares SecondFilenameLength — no document; HVK4 calls the address TAPE2 |
| 1873 | `DRIVE1` | `FirstDrive` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the disk command's first drive number |
| 1874 | `DRIVE2` | `SecondDrive` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the disk command's second drive number |
| 1875 | `DIDCHK` | `DiskIdSeen` | alias | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | set when the parser has read a disk ID; shares RecordLength |
| 1876 | `LRECL` | `RecordLength` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | a relative file's record length (DOPEN L) |
| 1877 | `PRSCHK` | `ParsedParameters` | location | P4 P4R | none found | vendor | bits for the disk parameters the parser has read — no document gives this name |
| 1878 | `DISKID` | `DiskId` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | two-byte disk ID for HEADER |
| 1879 | `KCOUNT` | `TemplateCount` | location | P4 P4R | none found | vendor | bytes left in the disk-command template SENDP expands — no document gives this name |
| 1880 | `TBUF2` | `FirstFilename` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | storage for the disk command's first filename |
| 1881 | `TBUFF` | `DiskCommandBuffer` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | where SENDP builds the disk command sent to the drive |
| 1882 | `USRCMD` | `MonitorUserCommandVector` | location | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the monitor jumps through it for an unknown command |
| 1883 | `PRT` | `ScreenOut` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the screen editor's character output; NUMSCR prints the disk status through it — same job as the Apple Monitor's ScreenOut (COUT1) |
| 1884 | `MS1` | `KernalMessages` | table | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | base of the kernal's message table; offsets into it select a message |
| 1885 | `MSG1` | `KernalMessages` | alias | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the same base under a second kernal name — one definition with Also: MS1, MSG1 |
| 1886 | `MS3` | `FileNotOpenMessage` | message | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's FILE NOT OPEN message; RECORD reports it |
| 1887 | `MSG30` | `ConfirmMessage` | message | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's confirmation prompt; RUSURE prints it, then accepts only Y or YES |
| 1888 | `MSG31` | `BadDiskMessage` | message | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's bad-disk message; BADDIS prints it in direct mode |
| 1889 | `TALK` | `KernalTalk` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | addresses a device on the IEEE bus as talker |
| 1890 | `LISTN` | `KernalListen` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | addresses a device on the IEEE bus as listener |
| 1891 | `MSG` | `KernalPrintMessage` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | prints the kernal message at offset Y |
| 1892 | `SECND` | `KernalSendSecondary` | routine | P4 P4R | spelling only: K4S79 [P4 P4R], HVK4 [P4 P4R]; other names here: TKSA (HVK4) | vendor | sends a secondary address after Talk |
| 1893 | `UNTLK` | `KernalUntalk` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | sends UNTALK on the bus |
| 1894 | `UNLSN` | `KernalUnlisten` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | sends UNLISTEN on the bus |
| 1895 | `ACPTR` | `KernalReceiveByte` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | receives a byte from the bus talker |
| 1896 | `GETIN` | `KernalGetInput` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | gets a character without waiting (behind GetCharacter's vector) |
| 1897 | `BASIN` | `KernalInputCharacter` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | reads a character from the selected input (behind KernalCharacterIn) |
| 1898 | `BSOUT` | `KernalOutputCharacter` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | writes a character to the selected output (behind KernalCharacterOut) |
| 1899 | `CLRCH` | `KernalRestoreChannels` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | restores the default input and output |
| 1900 | `CLRCHN` | `KernalRestoreChannels` | alias | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the same entry under a second kernal name — one definition with Also: CLRCH, CLRCHN |
| 1901 | `JLTLK` | `KernalFindLogicalFile` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | looks up LogicalFile in the kernal's tables; zero set when found |
| 1902 | `JZ100` | `KernalLoadFileEntry` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | loads the found file's table entry into the current fields |
| 1903 | `CLOS5` | `KernalCloseLogicalFile` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | closes the selected logical file |
| 1904 | `FCLOSE` | `KernalCloseLogicalFile` | alias | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the same entry under a second kernal name — one definition with Also: CLOS5, FCLOSE |
| 1905 | `CLOS10` | `KernalCloseFileAt` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | closes the file at table position X (DCLOSE) |
| 1906 | `STOP1` | `KernalTestStopKey` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | tests the STOP key; zero set when pressed — distinct from the CheckStop vector |
| 1907 | `LD15` | `KernalMonitorLoad` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal load entry the monitor calls |
| 1908 | `LOADNP` | `KernalLoadWithoutName` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | loads without parsing a filename (DLOAD) |
| 1909 | `OPENIB` | `KernalSendOpen` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | sends an OPEN with the filename on the bus |
| 1910 | `OP94` | `KernalOpenPrepared` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | opens the filename a disk command prepared |
| 1911 | `FOPEN` | `KernalOpenCurrentFile` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | opens using the current kernal file fields (CATALOG) |
| 1912 | `ERMSG` | `KernalReportMessage` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | reports kernal message Y as an error |
| 1913 | `SV3` | `KernalBasicSave` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's BASIC save entry (DSAVE) |
| 1914 | `SV5` | `KernalMonitorSave` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | the kernal's save entry the monitor calls |
| 1915 | `CHKIN` | `KernalSetInputChannel` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | selects a logical file for input |
| 1916 | `CHKOUT` | `KernalSetOutputChannel` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; other names here: CKOUT (HVK4) | vendor | selects a logical file for output |
| 1917 | `TWAIT` | `KernalWaitForTape` | routine | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | waits for the tape operation to finish |
| 1918 | `SPERR` | `STATUS_LOAD_ERROR` | constant | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R]; other names here: CHANL (HVK4) | vendor | IoStatus bit ($10) for a load or verify error — HVK4 calls it CHANL |
| 1919 | `CR` | `CHARACTER_RETURN` | constant | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | carriage return ($0D), the monitor's line end — other PET parts may name CR; one definition (see D-Q6) |
| 1920 | `ONTK` | `TOKEN_ON` | token | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | BASIC's ON token; the disk parser reads ON as the unit keyword — should be the token table's TOKEN_ON (one definition) |
| 1921 | `NCMDS` | `MONITOR_COMMAND_COUNT` | constant | P4 P4R | K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | number of built-in monitor commands (8) — HVK4 calls it LBERR |

### Commodore.ChannelInput

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1922 | `COMMODORE_CHANNEL_INPUT` | `CommodoreChannelInput` | macro | PET |  | vendor | Emits GET, INPUT# and the channel release. — SDK name: case only, no Also: |
| 1923 | `bufferPage` | `KEEP` | parameter of COMMODORE_CHANNEL_INPUT | PET |  | vendor | Zero for a page-zero input buffer, else the buffer's page. |
| 1924 | `GET` | `Statements::Get` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | GET: rejects direct mode, selects channel # if given, then reads one character per variable. |
| 1925 | `GETTTY` | `Statements::Get::ReadCharacters` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Sets up an empty buffer, reads through the shared input code in GET mode, then releases a selected channel. |
| 1926 | `INPUTN` | `Statements::InputNumber` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | INPUT#: selects the input channel, runs INPUT from its direct-mode check, then falls into RestoreChannels. — keyword INPUT#, as DOS's PR# is Commands::PrNumber |
| 1927 | `IODONE` | `RestoreChannels` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Restores the default channels after channel input or output; falls into its release. — called from PRINT# and INPUT's file-error path |
| 1928 | `IORELE` | `RestoreChannels::Release` | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Calls CQCCHN and clears CHANNL; GET enters here after reading a channel. |
| 1929 | `COMMODORE_INPUT_STATEMENT` | `CommodoreInputStatement` | macro | PET |  | vendor | Emits INPUT through its line reader. — SDK name: case only |
| 1930 | `suppressWait` | `clearSuppression` | parameter of COMMODORE_INPUT_STATEMENT | PET |  | vendor | 1 to clear OutputSuppressed at INPUT's start (BASIC 1 and 2). — renamed: the old name and its doc say "wait", the code clears CNTWFL |
| 1931 | `statusMask` | `KEEP` | parameter of COMMODORE_INPUT_STATEMENT | PET |  | vendor | The channel status bits that end file INPUT (2 or 3). |
| 1932 | `revisedEof` | `KEEP` | parameter of COMMODORE_INPUT_STATEMENT | PET |  | vendor | 1 to send a blank line to the revised BASIC 4's patch (INPNUL). |
| 1933 | `editorPatch` | `KEEP` | parameter of COMMODORE_INPUT_STATEMENT | PET |  | vendor | 1 to stop through BASIC 1's editor-ROM helper. |
| 1934 | `localStopLabel` | `KEEP` | parameter of COMMODORE_INPUT_STATEMENT | PET |  | vendor | 1 to define the stop entry here (BASIC 4). |
| 1935 | `INPUT` | `Statements::Input` | routine | PET | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | INPUT: prints a quoted prompt, rejects direct mode, reads lines; a file error releases the channel and skips the statement, a blank terminal line stops. |
| 1936 | `NOTQTI` | `Statements::Input::CheckDirect` | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Rejects direct mode and puts a comma before the buffer; INPUT# enters here. |
| 1937 | `GETAGN` | `Statements::Input::ReadLine` | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Reads a line and checks the channel's status; the revised BASIC 4 patch re-enters here. |
| 1938 | `BUFFUL` | `Statements::Input::CheckEmpty` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | A nonempty line goes to the shared value parser; an empty one retries a channel or stops. |
| 1939 | `INPSTP` | `StopEmptyInput` | routine | P4 P4R | other names here: BUFFU1 (HV4R) | vendor | Stops the program (STPEND, carry clear) after a blank terminal INPUT line. — BASIC 1's INPSTP (F part) does the same job; same name; P4 falls into it |
| 1940 | `QINLIN` | `PromptAndInputLine` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Prints ? and a space on the keyboard only, then reads an input line. |
| 1941 | `GINLIN` | `PromptAndInputLine::ToInputLine` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Jumps on to InputLine. |
| 1942 | `COMMODORE_INPUT_ERROR` | `CommodoreInputError` | macro | PET |  | vendor | Emits the bad-input handling. — SDK name: case only |
| 1943 | `editorPatch` | `KEEP` | parameter of COMMODORE_INPUT_ERROR | PET |  | vendor | 1 to take the error line from BASIC 1's editor-ROM helper. |
| 1944 | `TRMNOK` | `HandleBadInput` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | A value did not convert: READ reports SYNTAX at the DATA line, GET as direct, file INPUT gives FILE DATA, terminal INPUT retries. |
| 1945 | `GETDTL` | `HandleBadInput::UseDataLine` | local | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | READ: takes DataLine as the error line. — BASIC 1 calls the editor ROM's GETDTL instead (F part) |
| 1946 | `STCURL` | `HandleBadInput::SetLine` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Stores the error line in CurrentLine. |
| 1947 | `SNERR4` | `HandleBadInput::ToSyntaxError` | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Jumps on to SNERR; PrintTabOrSpace also branches here. |
| 1948 | `TRMNO1` | `HandleBadInput::CheckChannel` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | INPUT: from a channel reports ERROR_FILE_DATA; from the keyboard retries. |
| 1949 | `DOAGIN` | `RetryInput` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Prints the retry message and restores TextPointer from StoppedText. — a separate .proc to match AS; only HandleBadInput reaches it here |

### Commodore.ChannelPrint

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1950 | `COMMODORE_PRINT_CHANNELS` | `CommodorePrintChannels` | macro | PET |  | vendor | Emits PRINT# and CMD. — SDK name: case only |
| 1951 | `PRINTN` | `Statements::PrintNumber` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | PRINT#: runs CMD, then restores the default channels. |
| 1952 | `CMD` | `Statements::Cmd` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | CMD: selects the output channel and prints any items; the channel stays selected. |
| 1953 | `SAVEIT` | `Statements::Cmd::SelectChannel` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Opens the channel for output (CQOOUT), records CHANNL and enters PRINT. |
| 1954 | `COMMODORE_CHARACTER_OUTPUT` | `CommodoreCharacterOutput` | macro | PET |  | vendor | Emits PrintSpace, PrintQuestionMark and PrintCharacter. — SDK name: case only |
| 1955 | `alwaysSkip` | `KEEP` | parameter of COMMODORE_CHARACTER_OUTPUT | PET |  | vendor | 1 to send cursor-right for every channel (BASIC 1). |
| 1956 | `localPosition` | `KEEP` | parameter of COMMODORE_CHARACTER_OUTPUT | PET |  | vendor | 1 to keep the screen column in BASIC (BASIC 1). |
| 1957 | `suppressOutput` | `honorSuppression` | parameter of COMMODORE_CHARACTER_OUTPUT | PET |  | vendor | 1 to skip output while OutputSuppressed is set. — renamed: suppressOutput reads as the opposite and means "clear" in CommodoreErrorReady |
| 1958 | `returnAlias` | `KEEP` | parameter of COMMODORE_CHARACTER_OUTPUT | PET |  | vendor | 1 to define PrintCharacter::Return at the RTS. |
| 1959 | `OUTSPC` | `PrintSpace` | routine | PET | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R; other names here: CRTSKP (HV1, HV1R) | vendor | Loads a space for a file or cursor-right for the screen (always cursor-right in BASIC 1), skipping into PrintCharacter. |
| 1960 | `CRTSKP` | `PrintSpace::CursorRight` | local | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | Loads the cursor-right code. |
| 1961 | `OUTQST` | `PrintQuestionMark` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Loads ? and falls into PrintCharacter. |
| 1962 | `OUTDO` | `PrintCharacter` | routine | PET | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Sends A to the selected channel (OUTCH) unless output is suppressed; BASIC 1 tracks the column; returns with zero set from A. |
| 1963 | `DECTRM` | `PrintCharacter::MoveLeft` | local | P1 P1R | none found | vendor | BASIC 1: cursor-left or delete moves the screen column back. |
| 1964 | `OUTDO2` | `PrintCharacter::CheckPrintable` | local | P1 P1R | none found | vendor | BASIC 1: only printable characters advance the column. |
| 1965 | `OUTDO1` | `PrintCharacter::Advance` | local | P1 P1R | M6502, HV1, HV1R | vendor | BASIC 1: advances the column through the editor ROM's INCTRM. |
| 1966 | `TRYOUT` | `PrintCharacter::RestoreCharacter` | local | P1 P1R | M6502, HV1, HV1R | vendor | BASIC 1: recovers the character before sending it. |
| 1967 | `OUTLOC` | `PrintCharacter::Send` | local | PET | M6502 | vendor | Sends the character through OUTCH. — unreferenced on PET; kept for its M6502 name |
| 1968 | `OUTRTS` | `PrintCharacter::SetFlags` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Sets zero from A and returns; suppressed output branches here. |
| 1969 | `GETRTS` | `PrintCharacter::Return` | local | P1 P1R P2 | M6502 | vendor | Return. — nothing in P1/P2 uses it; kept for its M6502 name |
| 1970 | `COMMODORE_LINE_END` | `CommodoreLineEnd` | macro | PET |  | vendor | Emits FinishInputLine and PrintNewline. — SDK name: case only |
| 1971 | `bufferPage` | `KEEP` | parameter of COMMODORE_LINE_END | PET |  | vendor | Zero for a page-zero input buffer, else the buffer's page. |
| 1972 | `localPosition` | `KEEP` | parameter of COMMODORE_LINE_END | PET |  | vendor | 1 to keep TerminalPosition in BASIC (BASIC 1). |
| 1973 | `channelLineFeed` | `KEEP` | parameter of COMMODORE_LINE_END | PET |  | vendor | 1 to send a line feed only to channels with bit 7 set (BASIC 4). |
| 1974 | `nullPadding` | `KEEP` | parameter of COMMODORE_LINE_END | PET |  | vendor | 1 to send the NULL count of zeros after a newline (BASIC 1). |
| 1975 | `FININL` | `FinishInputLine` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Zero-terminates the input line, returns X/Y = the address before InputBuffer; prints a newline only for keyboard input. — falls into PrintNewline |
| 1976 | `CRDO` | `PrintNewline` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Prints a return and, as configured, a line feed and NULL padding; BASIC 1 resets the screen column. |
| 1977 | `GOCR` | `PrintNewline::SendReturn` | local | PET | M6502 | vendor | Sends the carriage return. |
| 1978 | `CRFIN` | `PrintNewline::Finish` | entry | PET | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Finishes the newline (padding, column, or A complemented); the shared string printer enters here. |
| 1979 | `PRTNUL` | `PrintNewline::PadNulls` | local | P1 P1R | M6502, HV1, HV1R | vendor | BASIC 1: sends the NULL count of zero bytes. |
| 1980 | `CLRPOS` | `PrintNewline::ResetColumn` | local | P1 P1R | M6502, HV1, HV1R | vendor | BASIC 1: clears TerminalPosition and restores X. |
| 1981 | `PRTRTS` | `PrintNewline::Return` | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Return; FinishInputLine and shared PRINT branch here. |
| 1982 | `COMMODORE_PRINT_SPACING` | `CommodorePrintSpacing` | macro | PET |  | vendor | Emits PrintComma, PrintTabOrSpace and PrintSpaces. — SDK name: case only |
| 1983 | `tokenDispatch` | `KEEP` | parameter of COMMODORE_PRINT_SPACING | PET |  | vendor | 1 for BASIC 1's token-tested TAB/SPC and simple space loop. |
| 1984 | `COMPRT` | `PrintComma` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | PRINT's comma: prints spaces to the next ZONE_WIDTH zone from TerminalPosition. |
| 1985 | `MORCOM` | `PrintComma::Modulus` | local | PET | M6502 | vendor | Starts the zone modulus (SEC). — unreferenced; kept for its M6502 name |
| 1986 | `MORCO1` | `PrintComma::SubtractZone` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Subtracts ZONE_WIDTH until negative, then negates to the spaces needed. |
| 1987 | `TABER` | `PrintTabOrSpace` | routine | PET | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | TAB( or SPC(: reads the byte argument and ), then prints spaces to the column or the count. — BASIC 1 tests the saved token, later ones the carry; BASIC 1's SPC(0) prints 256 spaces (bug, document) |
| 1988 | `ASPAC` | `PrintSpaces` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Prints A spaces; PrintComma branches here and PrintTabOrSpace falls into it. — two definitions, one per variant of the macro (lines 213, 232) |
| 1989 | `XSPAC` | `PrintSpaces::CountInX` | entry | PET | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R; other names here: XSPAC1 (HV1, HV1R) | vendor | Prints X spaces. — BASIC 1: the loop itself |
| 1990 | `NOTABR` | `ContinuePrint` | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Rereads the current character and continues PRINT at PRINTC. |
| 1991 | `XSPAC2` | `PrintSpaces::Next` | local | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | Counts down; zero goes on to ContinuePrint. |
| 1992 | `XSPAC1` | `PrintSpaces::One` | local | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | Prints one space and loops. |

### Commodore.CommandInput

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1993 | `COMMODORE_ERROR_READY` | `CommodoreErrorReady` | macro | PET |  | vendor | Emits ReportError and ReadyForCommand. — SDK name: case only |
| 1994 | `suppressOutput` | `clearSuppression` | parameter of COMMODORE_ERROR_READY | PET |  | vendor | 1 to clear OutputSuppressed when reporting an error and at READY. — renamed: the same name means "honor" in CommodoreCharacterOutput |
| 1995 | `OMERR` | `ReportOutOfMemory` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Loads ERROR_OUT_OF_MEMORY into X and falls into ReportError. |
| 1996 | `ERROR` | `ReportError` | routine | PET | M6502, K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R], CBM4S79 [P4 P4R] | vendor | Closes a selected channel, prints ?, the message at X in ErrorMessages, ERROR and the line, and returns to the prompt. |
| 1997 | `ERRCRD` | `ReportError::ShowMessage` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Starts a new line and prints the question mark. |
| 1998 | `GETERR` | `ReportError::NextCharacter` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Prints message characters until the one with bit 7 set. |
| 1999 | `READY` | `ReadyForCommand` | routine | PET | M6502, K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R], CBM4S79 [P4 P4R] | vendor | Prints READY. and falls into CommandLoop. |
| 2000 | `COMMODORE_COMMAND_LOOP` | `CommodoreCommandLoop` | macro | PET |  | vendor | Emits CommandLoop, ClearAndRelink and LinkProgram. — SDK name: case only |
| 2001 | `testCharacter` | `KEEP` | parameter of COMMODORE_COMMAND_LOOP | PET |  | vendor | 1 to set zero from the first character (TAX). |
| 2002 | `resetBeforeInsert` | `KEEP` | parameter of COMMODORE_COMMAND_LOOP | PET |  | vendor | 1 to clear variables and relink before inserting a line. |
| 2003 | `linkReturns` | `KEEP` | parameter of COMMODORE_COMMAND_LOOP | PET |  | vendor | 1 for LinkProgram to return instead of entering CommandLoop. |
| 2004 | `addHighToY` | `KEEP` | parameter of COMMODORE_COMMAND_LOOP | PET |  | vendor | Passed to the shared link macro: 1 to add the high byte through Y. |
| 2005 | `MAIN` | `CommandLoop` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Reads a line, runs a direct statement, or inserts, replaces or deletes a numbered line. |
| 2006 | `NODEL` | `CommandLoop::InsertLine` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | After any deletion: an empty line relinks; otherwise opens space with BLTU. |
| 2007 | `NODELC` | `CommandLoop::OpenGap` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Stores the high byte of the move's end and calls BLTU. |
| 2008 | `STOLOP` | `CommandLoop::CopyLine` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Copies the tokenized line from the input buffer into the program. |
| 2009 | `FINI` | `ClearAndRelink` | routine | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | Clears variables (RUNC) and relinks the program, then enters CommandLoop (BASIC 1 falls into LinkProgram). |
| 2010 | `LNKPRG` | `LinkProgram` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Rebuilds every line's link from ProgramStart; returns, or in BASIC 1 enters CommandLoop. |
| 2011 | `CHEAD` | `LinkProgram::NextLine` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Tests a line's link high byte; zero ends the program. |
| 2012 | `LNKRTS` | `LinkProgram::Return` | local | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | Return at the end of the program. |
| 2013 | `COMMODORE_TERMINAL_INPUT` | `CommodoreTerminalInput` | macro | PET |  | vendor | Emits InputLine and InputCharacter. — SDK name: case only |
| 2014 | `earlyDelete` | `KEEP` | parameter of COMMODORE_TERMINAL_INPUT | PET |  | vendor | 1 for BASIC 1's erase and restart entries. |
| 2015 | `checkedInput` | `KEEP` | parameter of COMMODORE_TERMINAL_INPUT | PET |  | vendor | 1 to read through the kernal and stop at a full buffer with STRING TOO LONG. |
| 2016 | `LINLIN` | `EraseInputCharacter` | routine | P1 P1R | M6502, HV1, HV1R | vendor | BASIC 1: backs the input index up one; before the buffer, falls into RestartInputLine. — unreferenced; kept for its M6502 name; branches into InputLine |
| 2017 | `INLINN` | `RestartInputLine` | routine | P1 P1R | M6502, HV1, HV1R | vendor | BASIC 1: prints a newline and falls into InputLine. — unreferenced; kept for its M6502 name |
| 2018 | `INLIN` | `InputLine` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Reads characters into InputBuffer until a return, then finishes it through FinishInputLine. |
| 2019 | `INLINC` | `InputLine::NextCharacter` | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Reads and stores the next character; EraseInputCharacter enters here. |
| 2020 | `GOODCH` | `InputLine::StoreCharacter` | local | P1 P1R P2 | M6502 | vendor | Stores the character in the buffer. — unreferenced; kept for its M6502 name |
| 2021 | `FININ1` | `InputLine::ToFinishInputLine` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Jumps on to FinishInputLine. |
| 2022 | `INCHR` | `InputCharacter` | routine | P1 P1R P2 | M6502, HV1, HV1R, HV2 | vendor | Reads a character (CQINCH); Control-O from the keyboard toggles OutputSuppressed. |
| 2023 | `INCRTS` | `InputCharacter::Return` | local | P1 P1R P2 | M6502, HV1, HV1R, HV2 | vendor | Return. |
| 2024 | `COMMODORE_TOKENIZE` | `CommodoreTokenize` | macro | PET |  | vendor | Emits Tokenize. — SDK name: case only |
| 2025 | `indirectTable` | `KEEP` | parameter of COMMODORE_TOKENIZE | PET |  | vendor | 1 to walk a ReservedWords longer than 256 bytes through Pointer1 (BASIC 4). |
| 2026 | `skipKeywordSpaces` | `KEEP` | parameter of COMMODORE_TOKENIZE | PET |  | vendor | 1 to skip spaces inside keywords (BASIC 1). |
| 2027 | `CRUNCH` | `Tokenize` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Tokenizes the input buffer in place: keeps spaces, copies quotes, DATA and REM, drops other high-bit characters but PI. |
| 2028 | `KLOOP` | `Tokenize::NextCharacter` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Reads the next input character; a high-bit character other than PI is skipped. |
| 2029 | `CMPSPC` | `Tokenize::CheckSpace` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Copies a space; records the end delimiter and starts a quoted copy at a quote. |
| 2030 | `KLOOP1` | `Tokenize::CheckDigit` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Copies digits and : ; unchanged. |
| 2031 | `MUSTCR` | `Tokenize::SearchWords` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Sets up the walk of ReservedWords from the current input position. |
| 2032 | `RESER` | `Tokenize::CharacterMatched` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | A character matched: advances in the table and the input. |
| 2033 | `RESPUL` | `Tokenize::AdvanceInput` | local | P1 P1R P2 | M6502, HV1, HV1R | vendor | Advances the input index (BASIC 1 skips spaces here). |
| 2034 | `RESCON` | `Tokenize::CompareCharacter` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Compares the input character with the table's. |
| 2035 | `NTHIS` | `Tokenize::NextWord` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Mismatch: restores the input index, counts the word and skips to its end. |
| 2036 | `NTHIS1` | `Tokenize::SkipWord` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Reads table bytes until the word's last character. |
| 2037 | `NTHIS2` | `Tokenize::TestWordEnd` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | BASIC 4: tests bit 7 after the pointer's page carry. |
| 2038 | `CRDONE` | `Tokenize::Finish` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Stores the line's end and sets TextPointer to the byte before InputBuffer. |
| 2039 | `LISTRT` | `Tokenize::Return` | local | PET | M6502 | vendor | Return. — unreferenced; kept for its M6502 name |

### Commodore.DispatchTables

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2040 | `COMMODORE_DISPATCH_TABLES` | `CommodoreDispatchTables` | macro | PET |  | vendor | Emits the statement, function and operator tables, ReservedWords and the messages. — SDK name: case only |
| 2041 | `goToken` | `KEEP` | parameter of COMMODORE_DISPATCH_TABLES | PET |  | vendor | 1 to include the GO keyword (BASIC 2 and 4). |
| 2042 | `diskCommands` | `KEEP` | parameter of COMMODORE_DISPATCH_TABLES | PET |  | vendor | 1 to add BASIC 4's disk statements. — same name in CommodoreStatementDispatch |
| 2043 | `badData` | `KEEP` | parameter of COMMODORE_DISPATCH_TABLES | PET |  | vendor | 1 for BASIC 1's BAD DATA text, 0 for FILE DATA. |
| 2044 | `singleReturn` | `KEEP` | parameter of COMMODORE_DISPATCH_TABLES | PET |  | vendor | 1 for a lone return in READY. and BREAK (BASIC 4), 0 for return and line feed. |
| 2045 | `STMDSP` | `StatementTable` | table | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Statement handler addresses minus one from END on, for RTS dispatch; BASIC 4's disk statements follow GO. |
| 2046 | `FUNDSP` | `FunctionTable` | table | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Function entry addresses in token order from SGN to MID$. |
| 2047 | `USRLOC` | `FunctionTable::Usr` | data | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | USR's entry: the writable jump at UserVector. — unreferenced; kept for its M6502 name |
| 2048 | `COSFIX` | `FunctionTable::Cos` | data | PET | M6502 | vendor | COS's entry. — unreferenced; kept for its M6502 name (Microsoft's patch point) |
| 2049 | `SINFIX` | `FunctionTable::Sin` | data | PET | M6502 | vendor | SIN's entry. — as COSFIX |
| 2050 | `TANFIX` | `FunctionTable::Tan` | data | PET | M6502 | vendor | TAN's entry. — as COSFIX |
| 2051 | `ATNFIX` | `FunctionTable::Atn` | data | PET | M6502 | vendor | ATN's entry. — as COSFIX |
| 2052 | `RESLST` | `ReservedWords` | table | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Keyword spellings in token order, bit 7 on each last character, ending in zero; Tokenize and LIST walk it. |
| 2053 | `ENDTK` | `TOKEN_END` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of END, the first statement token. |
| 2054 | `FORTK` | `TOKEN_FOR` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of FOR. |
| 2055 | `DATATK` | `TOKEN_DATA` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of DATA. |
| 2056 | `GOTOTK` | `TOKEN_GOTO` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of GOTO. |
| 2057 | `GOSUTK` | `TOKEN_GOSUB` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of GOSUB. |
| 2058 | `REMTK` | `TOKEN_REM` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of REM. |
| 2059 | `PRINTK` | `TOKEN_PRINT` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of PRINT (Tokenize stores it for ?). |
| 2060 | `SCRATK` | `TOKEN_NEW` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of NEW, the last ordinary statement. |
| 2061 | `TABTK` | `TOKEN_TAB` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of TAB(. |
| 2062 | `TOTK` | `TOKEN_TO` | token | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | Token of TO. |
| 2063 | `FNTK` | `TOKEN_FN` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of FN. |
| 2064 | `SPCTK` | `TOKEN_SPC` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of SPC(. |
| 2065 | `THENTK` | `TOKEN_THEN` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of THEN. |
| 2066 | `NOTTK` | `TOKEN_NOT` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of NOT. |
| 2067 | `STEPTK` | `TOKEN_STEP` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of STEP. |
| 2068 | `GREATK` | `TOKEN_GREATER` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of >, the first relational token. |
| 2069 | `EQULTK` | `TOKEN_EQUAL` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of =. |
| 2070 | `LESSTK` | `TOKEN_LESS` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of <. |
| 2071 | `ONEFUN` | `TOKEN_FIRST_FUNCTION` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of SGN, the first function. — see C-Q5 |
| 2072 | `LASNUM` | `TOKEN_LAST_SIMPLE_FUNCTION` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Token of CHR$, the last one-argument function. — see C-Q5 |
| 2073 | `GOTK` | `TOKEN_GO` | token | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | Token of GO (BASIC 2 and 4). |
| 2074 | `ERRTAB` | `ErrorMessages` | table | PET | M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Error messages, each ending in a bit-7 character; ReportError indexes them by the ERROR_* offsets. |
| 2075 | `ERRNF` | `ERROR_NEXT_WITHOUT_FOR` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of NEXT WITHOUT FOR in ErrorMessages. |
| 2076 | `ERRSN` | `ERROR_SYNTAX` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of SYNTAX in ErrorMessages. |
| 2077 | `ERRRG` | `ERROR_RETURN_WITHOUT_GOSUB` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of RETURN WITHOUT GOSUB in ErrorMessages. |
| 2078 | `ERROD` | `ERROR_OUT_OF_DATA` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of OUT OF DATA in ErrorMessages. |
| 2079 | `ERRFC` | `ERROR_ILLEGAL_QUANTITY` | error | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | Offset of ILLEGAL QUANTITY in ErrorMessages. |
| 2080 | `ERROM` | `ERROR_OUT_OF_MEMORY` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of OUT OF MEMORY in ErrorMessages. — ERROV and ERRDV0 are workspace equates asserted here (D-workspace) |
| 2081 | `ERRUS` | `ERROR_UNDEFINED_STATEMENT` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of UNDEF'D STATEMENT in ErrorMessages. |
| 2082 | `ERRBS` | `ERROR_BAD_SUBSCRIPT` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of BAD SUBSCRIPT in ErrorMessages. |
| 2083 | `ERRDD` | `ERROR_REDIMENSIONED_ARRAY` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of REDIM'D ARRAY in ErrorMessages. |
| 2084 | `ERRID` | `ERROR_ILLEGAL_DIRECT` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of ILLEGAL DIRECT in ErrorMessages. |
| 2085 | `ERRTM` | `ERROR_TYPE_MISMATCH` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of TYPE MISMATCH in ErrorMessages. |
| 2086 | `ERRLS` | `ERROR_STRING_TOO_LONG` | error | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | Offset of STRING TOO LONG in ErrorMessages. |
| 2087 | `ERRBD` | `ERROR_FILE_DATA` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of the file-data message: BAD DATA in BASIC 1, FILE DATA later; file INPUT reports it. — see C-Q5 |
| 2088 | `ERRST` | `ERROR_FORMULA_TOO_COMPLEX` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of FORMULA TOO COMPLEX in ErrorMessages. |
| 2089 | `ERRCN` | `ERROR_CANT_CONTINUE` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of CAN'T CONTINUE in ErrorMessages. |
| 2090 | `ERRUF` | `ERROR_UNDEFINED_FUNCTION` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Offset of UNDEF'D FUNCTION in ErrorMessages. |
| 2091 | `ERR` | `ErrorSuffix` | message | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | The text " ERROR" and a zero, printed after an error message. |
| 2092 | `INTXT` | `LineNumberPrefix` | message | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | The text " IN " printed before an error's or BREAK's line number. |
| 2093 | `REDDY` | `ReadyMessage` | message | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | READY. between newlines, printed by ReadyForCommand. |
| 2094 | `BRKTXT` | `BreakMessage` | message | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | A newline and BREAK, printed when a program stops. |
| 2095 | `FORSIZ` | `FOR_FRAME_SIZE` | constant | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Size in bytes of a FOR frame on the stack (2 * ADDPRC + 16). |

### Commodore.Equates

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2096 | `REALIO` | `REALIO` | switch | PET | M6502 | vendor | Microsoft's build target, 3 for Commodore — KEEP: predefined by C# and tests |
| 2097 | `BUFPAG` | `INPUT_BUFFER_PAGE` | switch | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | input buffer page: 0 page zero (BASIC 1) or 2 — asserted 0 or 2 |
| 2098 | `BUFLEN` | `INPUT_BUFFER_LENGTH` | switch | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | input buffer length (81; 80 in BASIC 1) |
| 2099 | `NULCMD` | `NULL_COMMAND` | switch | P2 P4 P4R | M6502 | vendor | 1 reserves NullCount (BASIC 1 has the code but no token) |
| 2100 | `TERMINAL_FIRST` | `KEEP` | switch | P2 P4 P4R |  | vendor | 1 puts the terminal block (and BASIC 1's page-zero buffer) before the general scratch — SDK name; fits the style |
| 2101 | `FULL_STACK_TOP` | `KEEP` | switch | P2 P4 P4R |  | vendor | 1 lets the stack reach $01FF instead of $01FB — SDK name; fits the style |
| 2102 | `STACK_RESERVE_19` | `KEEP` | switch | P2 P4 P4R |  | vendor | 1 makes the stack check reserve 19 levels, not 23 — SDK name; fits the style |
| 2103 | `LOCAL_TRMPOS` | `LOCAL_TERMINAL_POSITION` | switch | P2 P4 P4R |  | vendor | 1 reserves BASIC's own TerminalPosition and names the early editor column — renamed only because it spells TRMPOS, which becomes TerminalPosition |
| 2104 | `LINE_WIDTH_STORAGE` | `KEEP` | switch | P1 P1R P2 |  | vendor | 1 reserves LineWidth and LastCommaColumn — SDK name; fits the style |
| 2105 | `DISK_STATUS_STRING` | `KEEP` | switch | P1 P1R P2 |  | vendor | 1 puts the DS$ descriptor where OutputSuppressed was — SDK name; fits the style |
| 2106 | `VARTXT_IN_LINNUM` | `VARIABLE_LIST_IN_LINE_NUMBER` | switch | P2 P4 P4R |  | vendor | 1 puts VariableListPointer on LineNumber's bytes (BASIC 1) — renamed only for the Microsoft names it spells |
| 2107 | `CLOCK_IN_PAGE2` | `KEEP` | switch | P2 P4 P4R |  | vendor | 1 puts the clock at $0200 (BASIC 1's kernal) — SDK name; fits the style |
| 2108 | `STATUS_IN_PAGE2` | `KEEP` | switch | P2 P4 P4R |  | vendor | 1 puts the I/O status at $020C (BASIC 1's kernal) — SDK name; fits the style |
| 2109 | `RND_TIMER_9044` | `KEEP` | switch | P2 P4 P4R |  | vendor | 1 makes RND(0) read $9044 instead of the VIA at $E844 — SDK name; fits the style |
| 2110 | `ERROR_PADDING5` | `KEEP` | switch | P2 P4 P4R |  | vendor | 1 keeps BASIC 1's five unused bytes in the error table (moves ERROR_OVERFLOW) — SDK name; fits the style |
| 2111 | `EXTENDED_DISK_VECTORS` | `KEEP` | switch | P1 P1R P2 |  | vendor | 1 defines BASIC 4's disk-command jump table below $FFC0 — SDK name; fits the style |
| 2112 | `NUMLEV` | `STACK_LEVELS` | switch | PET | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R; spelling only: HV1, HV1R | vendor | stack reserve in two-byte levels: 19 or 23 |
| 2113 | `STKEND` | `STACK_END` | switch | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | upper stack limit: $01FF or $01FB — PetDebugTarget looks up STKEND by name (see D-Q8) |
| 2114 | `STRSIZ` | `DESCRIPTOR_SIZE` | constant | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | a string descriptor's size: length and two-byte address — could become StringDescriptor .sizeof (see D-Q9) |
| 2115 | `NUMTMP` | `TEMPORARY_COUNT` | constant | PET | M6502 | vendor | number of temporary string descriptors (3) |
| 2116 | `LINLEN` | `LINE_LENGTH` | constant | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the build's terminal line length |
| 2117 | `CLMWID` | `ZONE_WIDTH` | constant | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | width of a comma's print zone |
| 2118 | `NCMPOS` | `LAST_COMMA_COLUMN` | constant | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | ((LINE_LENGTH / ZONE_WIDTH) - 1) * ZONE_WIDTH: the last zone's column; startup stores it in LastCommaColumn — AppleSoft.Print defines its own NCMPOS ($0E): same name there |
| 2119 | `CONTW` | `SUPPRESS_OUTPUT_KEY` | constant | PET | M6502 | vendor | the key that suppresses output (Control-O) |
| 2120 | `PI` | `TOKEN_PI` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the PET's one-character pi token ($FF); LIST stops quoting at it — should be the token table's TOKEN_PI (one definition) |
| 2121 | `RAMLOC` | `RAM_ORIGIN` | constant | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the Microsoft build's initial RAM origin ($0400) |
| 2122 | `USRPOK` | `UserVector` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | three-byte JMP at $00 that USR calls |
| 2123 | `CHANNL` | `CurrentChannel` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | logical file of CMD/INPUT#/PRINT#; 0 for the screen and keyboard — not in the glossary; shared code (VariableInput) reads it |
| 2124 | `NULCNT` | `NullCount` | location | P1 P1R | M6502, HV1, HV1R | vendor | NULL's count of nulls after each return (BASIC 1); CRDO prints them |
| 2125 | `TRMPOS` | `TerminalPosition` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | BASIC's own output column (BASIC 1) or the editor's column $C6 |
| 2126 | `CQPNTR` | `EditorCursorColumn` | location | P1 P1R | none found | vendor | the early editor's cursor column ($E2); BASIC 1's patch reads it when TerminalPosition wraps — Commodore's kernal name is PNTR |
| 2127 | `LINWID` | `LineWidth` | location | P1 P1R P2 | M6502, HV2 | vendor | terminal line width BASIC stores (BASIC 1 and 2) |
| 2128 | `NCMWID` | `LastCommaColumn` | location | P1 P1R P2 | M6502; other names here: NCMWFL (HV2) | vendor | column beyond which a comma starts a new line (BASIC 1 and 2) |
| 2129 | `LINNUM` | `LineNumber` | location | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | two-byte integer work area: line numbers, addresses |
| 2130 | `BUF` | `InputBuffer` | location | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | the line input and tokenizing buffer |
| 2131 | `BUFOFS` | `INPUT_BUFFER_BASE` | constant | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | page base for lda BUFOFS,x: 0 with the page-zero buffer, $0200 otherwise — AppleSoft redefines BUFOFS with .set in ErrorAndInput (other part): same name there |
| 2132 | `CHARAC` | `Delimiter` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the delimiting character a scan stops at |
| 2133 | `INTEGR` | `SmallInteger` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of Delimiter: the one-byte integer QINT leaves (EXP reads it) |
| 2134 | `ENDCHR` | `EndDelimiter` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the other delimiting character of a scan |
| 2135 | `COUNT` | `Counter` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R; spelling only: K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | general counter (tokenizer, line input, digits) |
| 2136 | `DIMFLG` | `Dimensioning` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | set while DIM is defining arrays |
| 2137 | `KIMY` | `DROP` | alias | PET | M6502 | vendor | alias of Dimensioning that nothing references — DROP: no code uses it; KIMY goes in Dimensioning's Also. The glossary's SavedOutputY clashes with IIeEquates SavedOutputY (YSAV1) in AppleSoft |
| 2138 | `VALTYP` | `ValueType` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | value type: $FF string, $00 numeric |
| 2139 | `INTFLG` | `IntegerType` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | integer type: $80 integer, $00 float |
| 2140 | `DORES` | `TokenizeState` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | whether the tokenizer may crunch reserved words (cleared in DATA and quotes) |
| 2141 | `GARBFL` | `CollectionState` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of TokenizeState used by string allocation as the collected-once flag |
| 2142 | `SUBFLG` | `SubscriptMode` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | whether a subscripted or FN name is allowed here — PetDebugTarget looks it up by name (see D-Q8) |
| 2143 | `INPFLG` | `InputMode` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | INPUT ($00), GET ($40) or READ ($98) |
| 2144 | `TANSGN` | `TangentSign` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | sign flag of TAN/SIN quadrant work |
| 2145 | `DSDESC` | `DiskStatusDescriptor` | location | P4 P4R | CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV4, HV4R, HVK4 [P4 P4R] | vendor | three-byte descriptor of DS$ (BASIC 4), in place of OutputSuppressed |
| 2146 | `CNTWFL` | `OutputSuppressed` | location | P1 P1R P2 | M6502, HV1, HV1R, HV2 | vendor | set to suppress output (Control-O); error, input and READY clear it (BASIC 1 and 2) |
| 2147 | `TEMPPT` | `NextTemporary` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | offset of the next free temporary descriptor — PetDebugTarget looks it up by name (see D-Q8) |
| 2148 | `LASTPT` | `LastTemporary` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to the last-used temporary descriptor |
| 2149 | `TEMPST` | `TemporaryDescriptors` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | storage for the three temporary string descriptors — PetDebugTarget looks it up by name (see D-Q8) |
| 2150 | `INDEX1` | `Pointer1` | location | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | general two-byte pointer 1 — one definition with Also: INDEX1, INDEX |
| 2151 | `INDEX` | `Pointer1` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the same definition as Pointer1 (Microsoft's second name) — no second line: INDEX goes in Pointer1's Also |
| 2152 | `INDEX2` | `Pointer2` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | general two-byte pointer 2 |
| 2153 | `RESHO` | `Result1` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | multiply and divide result, most significant byte |
| 2154 | `RESMOH` | `Result2` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | multiply and divide result, second byte |
| 2155 | `RESMO` | `Result3` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | multiply and divide result, third byte |
| 2156 | `RESLO` | `Result4` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | multiply and divide result, least significant byte |
| 2157 | `ADDEND` | `Addend` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of Result3 used by the array-size multiplier |
| 2158 | `TXTTAB` | `ProgramStart` | location | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | two-byte pointer to the first program line; LIST, RUN and the line search start here |
| 2159 | `VARTAB` | `VariablesStart` | location | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | two-byte pointer to the simple variables, just past the program |
| 2160 | `ARYTAB` | `ArraysStart` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to the arrays, after the simple variables |
| 2161 | `STREND` | `ArraysEnd` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte end of the arrays: the bottom of free memory |
| 2162 | `FRETOP` | `StringsBottom` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to the lowest string; strings grow down from MemoryTop |
| 2163 | `FRESPC` | `NewString` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to the string just allocated |
| 2164 | `MEMSIZ` | `MemoryTop` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte highest address + 1 BASIC uses (HIMEM) |
| 2165 | `CURLIN` | `CurrentLine` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte line number executing; high byte $FF in direct mode — PetDebugTarget looks it up by name (see D-Q8) |
| 2166 | `OLDLIN` | `StoppedLine` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte line STOP or END left, for CONT |
| 2167 | `POKER` | `PokeAddress` | alias | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | alias of LineNumber: the address POKE, PEEK and WAIT use |
| 2168 | `OLDTXT` | `StoppedText` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte text pointer STOP or END left, for CONT — PetDebugTarget looks it up by name (see D-Q8) |
| 2169 | `DATLIN` | `DataLine` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte line number of the DATA being read, for error reports |
| 2170 | `DATPTR` | `DataPointer` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte position of READ in the DATA |
| 2171 | `INPPTR` | `InputPointer` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to the text INPUT or READ is reading |
| 2172 | `VARNAM` | `VariableName` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the two-byte encoded name being looked up |
| 2173 | `VARPNT` | `VariablePointer` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to the value of the variable found |
| 2174 | `FDECPT` | `PowerTablePointer` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of VariablePointer: FOUT's index into the powers of ten |
| 2175 | `FORPNT` | `AssignedVariable` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to the variable LET, FOR, INPUT or READ stores into |
| 2176 | `LSTPNT` | `ListOffset` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of AssignedVariable: LIST saves its index into the line here (one byte, sty/ldy) — code disagrees with the glossary note: not a pointer to a keyword but LIST's saved Y; ListPosition fits better; see D-Q3 |
| 2177 | `ANDMSK` | `WaitAndMask` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of AssignedVariable: WAIT's AND mask |
| 2178 | `EORMSK` | `WaitXorMask` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of AssignedVariable+1: WAIT's EOR mask |
| 2179 | `OPPTR` | `OperatorPointer` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to the current operator's OperatorTable entry |
| 2180 | `VARTXT` | `VariableListPointer` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias: READ/INPUT's pointer into the variable list |
| 2181 | `OPMASK` | `OperatorMask` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | relation mask of the operator being parsed |
| 2182 | `DOMASK` | `RelationMask` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of TangentSign: the relation operators' result mask |
| 2183 | `DEFPNT` | `FunctionPointer` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to the DEF FN definition being used |
| 2184 | `GRBPNT` | `CollectorPointer` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of FunctionPointer: the collector's pointer to the best descriptor found |
| 2185 | `DSCPNT` | `DescriptorPointer` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to a string descriptor (assignment, string functions) |
| 2186 | `FOUR6` | `CollectorStep` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the collector's step through descriptors: 3 for strings, 7 in a variable (set at startup to 3) |
| 2187 | `JMPER` | `FunctionJump` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | a JMP opcode; the function dispatcher stores its target into the next two bytes |
| 2188 | `SIZE` | `FunctionJumpTarget` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of JMPER+1; the string collector keeps a descriptor offset here — code disagrees with the glossary note: no code reaches JMPER+1 by this name; its uses are the collector's offset scratch; see D-Q3 |
| 2189 | `OLDOV` | `FunctionJumpHigh` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of JMPER+2; FADD keeps the smaller operand's extension byte here, EXP its rounding — code disagrees with the glossary note: it is an extension (rounding) byte, not a jump address; see D-Q3 |
| 2190 | `TEMPF3` | `FloatTemporary3` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | packed five-byte float temporary 3; shares FunctionPointer |
| 2191 | `TEMPF1` | `FloatTemporary1` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | packed five-byte float temporary 1 |
| 2192 | `HIGHDS` | `DestinationEnd` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | general two-byte pointer: a block move's high destination end |
| 2193 | `HIGHTR` | `SourceEnd` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | general two-byte pointer: a block move's high source end |
| 2194 | `TEMPF2` | `FloatTemporary2` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | packed five-byte float temporary 2 |
| 2195 | `LOWDS` | `DestinationStart` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | general two-byte pointer: a block move's low destination end — no code reads it by this name; it anchors the layout of DigitsBeforePoint and DecimalExponent |
| 2196 | `LOWTR` | `SourceStart` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | general two-byte pointer: a block move's low source end; FindLine's result |
| 2197 | `ARYPNT` | `ArrayPointer` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of DestinationEnd used while building an array |
| 2198 | `GRBTOP` | `CollectorTop` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of SourceStart: the collector's highest string found so far |
| 2199 | `DECCNT` | `DigitCount` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | digits after the point (FIN) or before it (FOUT); shares DestinationStart — FIN counts fractional digits here, so the before-the-point reading is FOUT's use only; name may want DigitCount (see D-Q3) |
| 2200 | `TENEXP` | `DecimalExponent` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | FIN's decimal exponent, less the digits after the point; FOUT's exponent — code confirms the glossary |
| 2201 | `DPTFLG` | `DecimalPointSeen` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | FIN: bit 7 set by the first decimal point; bit 6 set by a second ends the number — code confirms the glossary; Microsoft's comments on DPTFLG and TENEXP are swapped |
| 2202 | `EXPSGN` | `ExponentSign` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | FIN's sign of the decimal exponent: rotated in on E-, tested to negate |
| 2203 | `FAC` | `Fac` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the floating-point accumulator, unpacked (exponent first) |
| 2204 | `FACEXP` | `FacExponent` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the FAC's exponent; the same byte as Fac |
| 2205 | `FACHO` | `FacMantissa1` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the FAC's mantissa, most significant byte |
| 2206 | `FACMOH` | `FacMantissa2` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the FAC's mantissa, second byte |
| 2207 | `FACMO` | `FacMantissa3` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the FAC's mantissa, third byte |
| 2208 | `FACLO` | `FacMantissa4` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the FAC's mantissa, least significant byte |
| 2209 | `FACSGN` | `FacSign` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the FAC's sign |
| 2210 | `SGNFLG` | `InputSign` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | FIN's mantissa sign: set by a leading minus, tested to negate at the end — code confirms the glossary |
| 2211 | `DEGREE` | `PolynomialDegree` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of InputSign: POLY's count of terms left |
| 2212 | `DSCTMP` | `NewDescriptor` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of Fac where a temporary descriptor is built |
| 2213 | `INDICE` | `ArrayIndex` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of FacMantissa3: QINT leaves the subscript here |
| 2214 | `BITS` | `ShiftFill` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | fill byte for whole-byte right shifts; startup clears it — same as AppleSoft |
| 2215 | `ARGEXP` | `ArgExponent` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the argument register's exponent (ARG) |
| 2216 | `ARGHO` | `ArgMantissa1` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the argument's mantissa, most significant byte |
| 2217 | `ARGMOH` | `ArgMantissa2` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the argument's mantissa, second byte |
| 2218 | `ARGMO` | `ArgMantissa3` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the argument's mantissa, third byte |
| 2219 | `ARGLO` | `ArgMantissa4` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the argument's mantissa, least significant byte |
| 2220 | `ARGSGN` | `ArgSign` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the argument's sign |
| 2221 | `ARISGN` | `ResultSign` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the sign of Fac's and Arg's product or sum (their signs compared) |
| 2222 | `FACOV` | `FacExtension` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the FAC's extension (rounding) byte |
| 2223 | `STRNG1` | `StringPointer` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to a string or descriptor; shares ResultSign's byte |
| 2224 | `FBUFPT` | `NumberBufferPointer` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer/index into NumberBuffer |
| 2225 | `BUFPTR` | `TokenizePointer` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of NumberBufferPointer: the tokenizer's index into InputBuffer |
| 2226 | `STRNG2` | `SecondStringPointer` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | two-byte pointer to a second string or descriptor; shares NumberBufferPointer |
| 2227 | `POLYPT` | `PolynomialPointer` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of NumberBufferPointer: POLY's pointer to the coefficients |
| 2228 | `CURTOL` | `LinearIndex` | alias | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | alias of NumberBufferPointer: an array element's linear index is formed here |
| 2229 | `CHRGET` | `GetNextCharacter` | routine | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | page-zero reader copied from the ROM template: advances TextPointer, then reads |
| 2230 | `CHRGOT` | `GetCurrentCharacter` | entry | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | entry into the page-zero reader that rereads the current character |
| 2231 | `TXTPTR` | `TextPointer` | location | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | the operand of the load in the page-zero reader: the text being read |
| 2232 | `QNUM` | `ClassifyCharacter` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | an entry inside the page-zero reader, past its colon test: classifies A without reading — Commodore.TimeAssignment calls it (jsr QNUM); see B1-Q3 |
| 2233 | `CHRRTS` | `CharacterReaderReturn` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | address inside the page-zero reader: its RTS — the page-zero reader's RTS; the PET debug host looks it up (PetDebugTarget.Basic.cs); see B1-Q3 |
| 2234 | `RNDX` | `RandomValue` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | RND's last value (five bytes; startup copies four from the template) — clashes in AppleSoft with IIeEquates RandomSeed (RNDL $4E); see D-Q2 |
| 2235 | `LOFBUF` | `NumberBufferPrefix` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the byte before NumberBuffer, where STR$'s result starts |
| 2236 | `FBUFFR` | `NumberBuffer` | location | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | FOUT's output buffer at the bottom of page one |
| 2237 | `CQTIMR` | `JiffyClock` | location | PET | M6502 | vendor | three-byte clock TI and TI$ read and set ($8D, or $0200 in BASIC 1) — jiffy is Commodore's own term |
| 2238 | `CQSTAT` | `IoStatus` | location | PET | M6502 | vendor | the kernal's I/O status byte ST ($96, or $020C in BASIC 1) — BASIC 4's system equates name the same byte SATUS: one definition (see D-Q6) |
| 2239 | `CQHTIM` | `RandomTimer` | location | PET | M6502; other names here: CHTIM (HV1, HV1R, HV2, HV4, HV4R), TIL (HVK4) | vendor | RND(0) reads offsets 0, 1, 4 and 5 here (VIA timers, or $9044 in BASIC 1) — HV calls it CHTIM |
| 2240 | `CQOPEN` | `KernalOpen` | routine | PET | M6502; other names here: COPEN (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: OPEN's dispatch entry: the kernal parses and opens — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column); a statement handler in the kernal, so not Statements:: (see D-Q5) |
| 2241 | `CQCLOS` | `KernalClose` | routine | PET | M6502; other names here: CCLOS (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: CLOSE's dispatch entry — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column); a statement handler in the kernal, so not Statements:: (see D-Q5) |
| 2242 | `CQOIN` | `KernalSelectInput` | routine | PET | M6502; other names here: COIN (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: INPUT#/GET# select the channel in X for input — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column) |
| 2243 | `CQOOUT` | `KernalSelectOutput` | routine | PET | M6502; other names here: COOUT (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: PRINT#/CMD select the channel in X for output — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column) |
| 2244 | `CQCCHN` | `KernalResetChannels` | routine | PET | M6502; other names here: CCCHN (HV1, HV1R, HV2, HV4, HV4R), CLSCHN (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: restores the screen and keyboard after channel I/O — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column) |
| 2245 | `CQINCH` | `KernalCharacterIn` | routine | PET | M6502; other names here: CINCH (HV1, HV1R, HV2, HV4, HV4R), INCHR (HV4, HV4R) | vendor | kernal jump-table entry: line input reads a character from the current input — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column) |
| 2246 | `OUTCH` | `KernalCharacterOut` | routine | PET | M6502, HV1, HV1R, HV2, HV4, HV4R; spelling only: CBM4S79 [P4 P4R] | vendor | kernal jump-table entry: writes a character to the current output (OUTDO) — Microsoft's CQ name; no Commodore name documented; only Commodore files call it, so it follows the Kernal names; AppleSoft's OUTCH is the Monitor's CharacterOut (see D-Q5) |
| 2247 | `CQLOAD` | `KernalLoad` | routine | PET | M6502; other names here: CLOAD (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: LOAD's dispatch entry — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column); a statement handler in the kernal, so not Statements:: (see D-Q5) |
| 2248 | `CQSAVE` | `KernalSave` | routine | PET | M6502; other names here: CSAVE (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: SAVE's dispatch entry — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column); a statement handler in the kernal, so not Statements:: (see D-Q5) |
| 2249 | `CQVERF` | `KernalVerify` | routine | PET | M6502; other names here: CVERF (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: VERIFY's dispatch entry — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column); a statement handler in the kernal, so not Statements:: (see D-Q5) |
| 2250 | `CQSYS` | `KernalSys` | routine | PET | M6502; other names here: CSYS (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: SYS's dispatch entry — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column); a statement handler in the kernal, so not Statements:: (see D-Q5) |
| 2251 | `ISCNTC` | `CheckStop` | routine | PET | M6502, HV1, HV1R, HV2, HV4, HV4R; spelling only: CBM4S79 [P4 P4R] | vendor | kernal jump-table entry: NEWSTT and LIST call it to test the STOP key — Microsoft's CQ name; no Commodore name documented; shared code calls it, so the name is vendor-neutral and matches AppleSoft's (AppleSoft's own ISCNTC routine, another part, must take the same name) |
| 2252 | `CZGETL` | `GetCharacter` | routine | PET | M6502; other names here: CGETL (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: GET reads one character without waiting — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column); shared code calls it, so the name is vendor-neutral and matches AppleSoft's |
| 2253 | `CQCALL` | `CloseAllFiles` | routine | PET | M6502; other names here: CCALL (HV1, HV1R, HV2, HV4, HV4R) | vendor | kernal jump-table entry: CLR and RUN close every file through it — Microsoft's CQ name; the HV reconstructions give the Commodore name (Documents column); shared code calls it, so the name is vendor-neutral and matches AppleSoft's |
| 2254 | `CQCONC` | `KernalConcat` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of CONCAT — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2255 | `CQDOPN` | `KernalDiskOpen` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of DOPEN — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2256 | `CQDCLS` | `KernalDiskClose` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of DCLOSE — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2257 | `CQRECD` | `KernalRecord` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of RECORD — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2258 | `CQFORM` | `KernalHeader` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of HEADER — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2259 | `CQCOLL` | `KernalCollect` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of COLLECT — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2260 | `CQBACK` | `KernalBackup` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of BACKUP — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2261 | `CQCOPY` | `KernalCopy` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of COPY — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2262 | `CQAPND` | `KernalAppend` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of APPEND — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2263 | `CQDSAV` | `KernalDiskSave` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of DSAVE — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2264 | `CQDLOD` | `KernalDiskLoad` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of DLOAD — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2265 | `CQDCAT` | `KernalDirectory` | routine | P4 P4R | other names here: DCAT (HV4, HV4R) | vendor | BASIC 4 disk jump-table entry: the dispatch entry of CATALOG and DIRECTORY — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2266 | `CQRENM` | `KernalRename` | routine | P4 P4R | none found | vendor | BASIC 4 disk jump-table entry: the dispatch entry of RENAME — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2267 | `CQSCRA` | `KernalScratch` | routine | P4 P4R | other names here: SCRATC (HV4, HV4R) | vendor | BASIC 4 disk jump-table entry: the dispatch entry of SCRATCH — named for the keyword; jumps into BASIC 4's own disk commands (see D-Q5) |
| 2268 | `CQRDDS` | `KernalReadDiskStatus` | routine | P4 P4R | other names here: READDS (HV4, HV4R) | vendor | BASIC 4 disk jump-table entry: reading DS or DS$ jumps here |
| 2269 | `PLUSTK` | `TOKEN_PLUS` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the + operator's token ($AA); FIN accepts it in an exponent — one definition with the token table's (see D-Q6) |
| 2270 | `MINUTK` | `TOKEN_MINUS` | token | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | the - operator's token; FIN accepts it in an exponent |
| 2271 | `ERROV` | `ERROR_OVERFLOW` | error | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | offset of OVERFLOW in ErrorTable, asserted against the table — AppleSoft.DispatchTables defines its own ($45): same name |
| 2272 | `ERRDV0` | `ERROR_DIVISION_BY_ZERO` | error | PET | M6502 | vendor | offset of DIVISION BY ZERO in ErrorTable, asserted against the table — AppleSoft.DispatchTables defines its own: same name |

### Commodore.FloatAliases

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2273 | `SQR05` | `Commodore::SquareRootOfHalf` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Commodore's name for SquareRootOfHalf — becomes Also: SQR05 (HV1, HV1R, HV2, HV4, HV4R) via Commodore's alias file; see A-Q1 |
| 2274 | `SQR20` | `Commodore::SquareRootOfTwo` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Commodore's name for SquareRootOfTwo — becomes Also: SQR20 (HV...) via Commodore's alias file; see A-Q1 |
| 2275 | `TENC` | `Commodore::Ten` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Commodore's name for Ten — becomes Also: TENC (HV...) via Commodore's alias file; see A-Q1 |
| 2276 | `N0999` | `Commodore::LowerOutputLimit` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Commodore's name for LowerOutputLimit — becomes Also: N0999 (HV...) via Commodore's alias file; see A-Q1 |
| 2277 | `N9999` | `Commodore::UpperOutputLimit` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Commodore's name for UpperOutputLimit — becomes Also: N9999 (HV...) via Commodore's alias file; see A-Q1 |
| 2278 | `NMIL` | `Commodore::Billion` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Commodore's name for Billion — becomes Also: NMIL (HV...) via Commodore's alias file; see A-Q1 |
| 2279 | `RMULC` | `Commodore::RandomMultiplier` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Commodore's name for RandomMultiplier — becomes Also: RMULC (HV...) via Commodore's alias file; see A-Q1 |
| 2280 | `RADDC` | `Commodore::RandomAddend` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | Commodore's name for RandomAddend — becomes Also: RADDC (HV...) via Commodore's alias file; see A-Q1 |

### Commodore.FloatingPoint

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2281 | `ZSTORD` | `WaitHiddenMessage` | routine | P2 | M6502; other names here: STORD1 (HV2) | vendor | WAIT without a second mask (BASIC 2): at address $1966 writes the hidden message to the screen the first mask's count of times; otherwise the plain wait — Also: ZSTORD (M6502), STORD1 (HV2); P2 only; outside Float though placed inside the package, see A-Q6 |
| 2282 | `MRCHKR` | `WaitHiddenMessage::Repeat` | local | P2 | M6502, HV2 | vendor | starts the ten-character message again |
| 2283 | `MRCHR` | `WaitHiddenMessage::NextCharacter` | local | P2 | M6502, HV2 | vendor | stores one character, masked to a screen code, and advances the screen address |
| 2284 | `PKINC` | `WaitHiddenMessage::Count` | local | P2 | M6502, HV2 | vendor | counts the characters, then the repetitions in WaitAndMask |
| 2285 | `BASIC4_OUTPUT_CHECKSUM` | `RomChecksumAdjustment` | data | P4 P4R | other names here: CHSUMC (HV4, HV4R) | vendor | the byte that adjusts BASIC 4's $C000 ROM checksum, before the patch space — Also: CHSUMC (HV4, HV4R); P4/P4R only |
| 2286 | `WAIT_SIGNATURE` | `HiddenMessageText` | data | P2 | none found | vendor | WaitHiddenMessage's ten bytes, stored reversed, each masked to a screen code (AND $3F) when written — P2 only; HV2's LE082 is an address name: no Also (Monitor log 6) |

### Commodore.Initialization

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2287 | `COMMODORE_INITIALIZE` | `CommodoreInitialize` | macro | PET |  | vendor | Emits ColdStart's vector and workspace setup. — SDK name: case only |
| 2288 | `markDirect` | `KEEP` | parameter of COMMODORE_INITIALIZE | PET |  | vendor | 1 to mark CurrentLine as direct (BASIC 1). |
| 2289 | `lineWidth` | `setLineWidth` | parameter of COMMODORE_INITIALIZE | PET |  | vendor | 1 to set LineWidth and LastCommaColumn (BASIC 1 and 2). — renamed: lineWidth differs from the location LineWidth only in case |
| 2290 | `delayedSize` | `KEEP` | parameter of COMMODORE_INITIALIZE | PET |  | vendor | 1 to set CollectorStep after clearing the flags (BASIC 1). |
| 2291 | `localPosition` | `KEEP` | parameter of COMMODORE_INITIALIZE | PET |  | vendor | 1 to clear TerminalPosition (BASIC 1). |
| 2292 | `bufferPage` | `KEEP` | parameter of COMMODORE_INITIALIZE | PET |  | vendor | Zero for a page-zero input buffer, else the buffer's page. |
| 2293 | `diskStatus` | `KEEP` | parameter of COMMODORE_INITIALIZE | PET |  | vendor | 1 to clear the disk-status descriptor instead of OutputSuppressed (BASIC 4). — same name in CommodoreVariableValue |
| 2294 | `earlyBufferSetup` | `KEEP` | parameter of COMMODORE_INITIALIZE | PET |  | vendor | 1 to set the page-zero buffer's comma and print a newline (BASIC 1). |
| 2295 | `INIT` | `ColdStart` | routine | PET | M6502, CBM4S79 [P4 P4R], K4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R, HVK4 [P4 P4R] | vendor | Sets the stack and USR vector, copies the character reader, clears the workspace, finds the memory top, prints the sign-on and free bytes and enters ReadyForCommand. |
| 2296 | `MOVCHG` | `ColdStart::CopyCharacterReader` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Copies INITAT's character reader and random seed to page zero. |
| 2297 | `COMMODORE_MEMORY_PROBE` | `CommodoreMemoryProbe` | macro | PET |  | vendor | Emits ColdStart's RAM probe. — SDK name: case only |
| 2298 | `explicitZero` | `KEEP` | parameter of COMMODORE_MEMORY_PROBE | PET |  | vendor | 1 to load zero before setting the probe address (BASIC 1). |
| 2299 | `explicitIndex` | `KEEP` | parameter of COMMODORE_MEMORY_PROBE | PET |  | vendor | 1 to load Y with zero rather than copy A (BASIC 1). |
| 2300 | `saveProgramStart` | `KEEP` | parameter of COMMODORE_MEMORY_PROBE | PET |  | vendor | 1 to set ProgramStart before probing. |
| 2301 | `diskFallback` | `KEEP` | parameter of COMMODORE_MEMORY_PROBE | PET |  | vendor | 1 to keep BASIC 4's unreachable ROM_ORIGIN fallback. |
| 2302 | `screenStop` | `KEEP` | parameter of COMMODORE_MEMORY_PROBE | PET |  | vendor | 1 to stop at the screen's $8000 page (BASIC 1). |
| 2303 | `probeByte` | `KEEP` | parameter of COMMODORE_MEMORY_PROBE | PET |  | vendor | The first value written to test each byte. |
| 2304 | `LOOPMM` | `ColdStart::ProbeMemory` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Steps to the next address, stopping at $8000. |
| 2305 | `LOOPM1` | `ColdStart::TestByte` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Writes and checks the probe byte and its shift; a mismatch ends the probe. |
| 2306 | `USEDEC` | `ColdStart::FoundMemoryTop` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Takes the failing address as the top of memory. |
| 2307 | `USEDEF` | `ColdStart::SetMemoryTop` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Sets MemoryTop and StringsBottom from A/Y. |
| 2308 | `COMMODORE_START_PROGRAM` | `CommodoreStartProgram` | macro | PET |  | vendor | Emits ColdStart's empty-program setup and sign-on. — SDK name: case only |
| 2309 | `reloadProgramStart` | `KEEP` | parameter of COMMODORE_START_PROGRAM | PET |  | vendor | 1 to load RAM_ORIGIN into ProgramStart again. |
| 2310 | `carryProgramStart` | `KEEP` | parameter of COMMODORE_START_PROGRAM | PET |  | vendor | 1 to carry ProgramStart's increment into its high byte. |
| 2311 | `checkRoom` | `KEEP` | parameter of COMMODORE_START_PROGRAM | PET |  | vendor | 1 to check room for the program (REASON). |
| 2312 | `carriageFirst` | `KEEP` | parameter of COMMODORE_START_PROGRAM | PET |  | vendor | 1 to print a newline instead of the banner (BASIC 1). |
| 2313 | `banner` | `KEEP` | parameter of COMMODORE_START_PROGRAM | PET |  | vendor | The sign-on message printed when carriageFirst is 0. |
| 2314 | `TTYW` | `ColdStart::StartProgram` | local | PET | M6502 | vendor | Puts the zero before the first line and advances ProgramStart past it. — unreferenced; kept for its M6502 name |
| 2315 | `ASKAGN` | `DROP` | local | PET | none found | vendor | Same address as TTYW; nothing uses it. — Microsoft's ASKAGN, no document gives it here; mention in prose |
| 2316 | `QROOM` | `ColdStart::CheckRoom` | local | P1 P1R P2 | M6502; other names here: INIT20 (HV1, HV1R) | vendor | Checks room for the program from ProgramStart (REASON). |
| 2317 | `COMMODORE_START_MESSAGES` | `CommodoreStartMessages` | macro | PET |  | vendor | Emits the free-bytes message and the sign-on. — SDK name: case only |
| 2318 | `earlyBanner` | `KEEP` | parameter of COMMODORE_START_MESSAGES | PET |  | vendor | 1 for BASIC 1's sign-on after the free-bytes text. |
| 2319 | `WORDS` | `BytesFreeMessage` | message | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | The text " BYTES FREE", then a newline (BASIC 1: its sign-on). |
| 2320 | `FREMES` | `SignOnMessage` | message | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | The ### COMMODORE BASIC ### sign-on printed before the free bytes (BASIC 2, or a BASIC 1 built with START_BANNER_AFTER_FREE = 0); BASIC 4 assembles it but prints its own SIGNON. |

### Commodore.InterpreterAliases

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2321 | `COPYC` | `Commodore::StoreDescriptor` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | CBM4S79's COPYC for the descriptor copy; stays in Commodore's alias file (D3), pointing at COPYZC's new name. — target named by B2 |
| 2322 | `STRD` | `Commodore::Str` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | CBM4S79's STRD for STR$; stays in the alias file, pointing at Functions::Str. — target named by B2 |
| 2323 | `CHRD` | `Commodore::Chr` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | CBM4S79's CHRD for CHR$; points at Functions::Chr. |
| 2324 | `LEFTD` | `Commodore::Left` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | CBM4S79's LEFTD for LEFT$; points at Functions::Left. |
| 2325 | `RIGHTD` | `Commodore::Right` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | CBM4S79's RIGHTD for RIGHT$; points at Functions::Right. |
| 2326 | `MIDD` | `Commodore::Mid` | alias | PET | HV1, HV1R, HV2, HV4, HV4R, CBM4S79 [P4 P4R] | vendor | CBM4S79's MIDD for MID$; points at Functions::Mid. |

### Commodore.StatementDispatch

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2327 | `COMMODORE_STATEMENT_FETCH` | `CommodoreStatementFetch` | macro | PET |  | vendor | Emits NextStatement and ExecuteStatement. — SDK name: case only |
| 2328 | `bufferPage` | `KEEP` | parameter of COMMODORE_STATEMENT_FETCH | PET |  | vendor | Zero for a page-zero buffer, else the page that marks direct mode. |
| 2329 | `spareByte` | `KEEP` | parameter of COMMODORE_STATEMENT_FETCH | PET |  | vendor | 1 to keep the NOP before the direct-mode branch. |
| 2330 | `earlySeparators` | `KEEP` | parameter of COMMODORE_STATEMENT_FETCH | PET |  | vendor | 1 to check the separator before the line link (BASIC 1). |
| 2331 | `shortEnd` | `KEEP` | parameter of COMMODORE_STATEMENT_FETCH | PET |  | vendor | 1 to branch straight to ENDCON (BASIC 1). |
| 2332 | `fetchToken` | `KEEP` | parameter of COMMODORE_STATEMENT_FETCH | PET |  | vendor | The routine that fetches the statement's first character (CHRGET, or the revised BASIC 4's PI check). |
| 2333 | `NEWSTT` | `NextStatement` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Checks STOP, saves TextPointer in StoppedText outside direct mode, then runs the next statement or steps to the next linked line. |
| 2334 | `DIRCON` | `NextStatement::TestSeparator` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Reads the byte at TextPointer: zero reads the next line, anything else is checked as a separator. — two definitions by bufferPage (lines 35, 39) |
| 2335 | `SNERR1` | `CheckStatementSeparator::ToSyntaxError` [P2 P4 P4R]; `NextStatement::ToSyntaxError` [P1 P1R] | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Jumps on to SNERR; DispatchStatement branches here too. — BASIC 1: inside NextStatement, written NextStatement::ToSyntaxError; see C-Q3 |
| 2336 | `NXTLIN` | `NextStatement::NextLine` | local | P1 P1R | other names here: CKEOL (HV1, HV1R) | vendor | BASIC 1: reads the next line's link and number. |
| 2337 | `GONE` | `ExecuteStatement` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Fetches the statement's first character, dispatches it through DispatchStatement, then continues at NextStatement. — CommandLoop jumps here for a direct statement |
| 2338 | `COMMODORE_STATEMENT_DISPATCH` | `CommodoreStatementDispatch` | macro | PET |  | vendor | Emits DispatchStatement and GO. — SDK name: case only |
| 2339 | `earlyDispatch` | `KEEP` | parameter of COMMODORE_STATEMENT_DISPATCH | PET |  | vendor | 1 for BASIC 1's carry and error paths. |
| 2340 | `diskCommands` | `KEEP` | parameter of COMMODORE_STATEMENT_DISPATCH | PET |  | vendor | 1 to map BASIC 4's disk tokens past the GO gap. |
| 2341 | `GONE3` | `DispatchStatement` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Returns at the end of a statement; otherwise dispatches a statement token through StatementTable, anything else is LET. |
| 2342 | `GONE2` | `DispatchStatement::WithToken` | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Subtracts TOKEN_END from A and dispatches; the shared ON code enters here. |
| 2343 | `GONE4` | `DispatchStatement::LookUp` | local | P1 P1R P4 P4R | HV4, HV4R, CBM4S79 [P4 P4R] | vendor | BASIC 1: checks the statement range; BASIC 4: dispatches after mapping a disk token; then indexes StatementTable. — two definitions (lines 104, 115) at different steps |
| 2344 | `GLET` | `DispatchStatement::ToLet` | local | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | Jumps on to LET. |
| 2345 | `MORSTS` | `CheckStatementSeparator` | routine | P2 P4 P4R | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | NextStatement's nonzero-byte case: a colon runs the next statement; anything else is a syntax error. |
| 2346 | `GO` | `Statements::Go` | routine | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R; spelling only: K4S79 [P4 P4R], HVK4 [P4 P4R] | vendor | GO: requires TO and continues as GOTO (BASIC 4's table entry). |
| 2347 | `SNERRX` | `CheckGoStatement` | routine | P2 | M6502, HV2 | vendor | BASIC 2: a token past the statements that is GO requires TO and continues as GOTO; anything else is a syntax error. — same job as BASIC 4's Statements::Go, reached from DispatchStatement instead of the table; see C-Q7 |

### Commodore.StringAssignment

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2348 | `STRING_STATUS_CHECK` | `StringStatusCheck` | macro | P4 P4R |  | vendor | Emits AssignString's test that forces a copy when the source is DS$'s buffer |
| 2349 | `NOTDS1` | `StoreString::RestoreOffset` | local | P4 P4R | other names here: DSKX1 (HV4, HV4R) | vendor | Not DS$: pulls the high byte and restores Y = 2 — HV4 DSKX1 in Also; qualifier follows part B2's GETSPT, see F-Q10 |
| 2350 | `NOTDS` | `StoreString::NotStatus` | local | P4 P4R | other names here: DSKX2 (HV4, HV4R) | vendor | Ordinary assignment continues — HV4 DSKX2 in Also |
| 2351 | `LINKED_STRING_STORE` | `LinkedStringStore` | macro | P4 P4R |  | vendor | Emits BASIC 4's descriptor store that relinks the new string and releases the old |
| 2352 | `COPYZC` | `StoreDescriptor` | entry | P4 P4R | M6502 | vendor | Frees a temporary, links its string to FORPNT, marks the destination's old string as garbage, copies the descriptor — Same entry as COPYZC in MsBasic.Assignment (part B2): same name |
| 2353 | `COPY00` | `StoreString::ReleaseOld` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Marks the destination's previous string as garbage (length, $FF) |
| 2354 | `COPY01` | `StoreString::CopyDescriptor` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Copies the three descriptor bytes |
| 2355 | `COPY02` | `StoreString::CopyByte` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Copies one byte |
| 2356 | `STRING_LINK_ADJUST` | `StringLinkAdjust` | macro | P4 P4R |  | vendor | Emits FindStringLink |
| 2357 | `patchedStatus` | `KEEP` | parameter of STRING_LINK_ADJUST | P4 P4R |  | vendor | 1 jumps to TestStatusString, 0 compares DS$'s high byte inline — KEEP |
| 2358 | `STRADJ` | `FindStringLink` | routine | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | For a nonempty string in string space that is not DS$: INDEX = its link, X = length, carry set; else carry clear — Called from AssignString and the concatenation's release |
| 2359 | `ADJ` | `FindStringLink::CheckStatus` | local | P4 P4R | HV4, HV4R; spelling only: CBM4S79 [P4 P4R] | vendor | Compares with DS$'s address (jump to TestStatusString in the revised ROM) |
| 2360 | `ADJDS1` | `FindStringLink::CompareStatusLow` | entry | P4 P4R | none found | vendor | Compares the low byte with DS$'s — TestStatusString jumps here; see F-Q9. HV4R LBA70 in Also |
| 2361 | `ADJ02` | `FindStringLink::AddLength` | entry | P4 P4R | none found | vendor | INDEX = string address + length — TestStatusString jumps here; HV4 LBA74 in Also |
| 2362 | `ADJ00` | `FindStringLink::Found` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Sets carry |
| 2363 | `ADJ01` | `FindStringLink::NoLink` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Discards the length and clears carry |

### Commodore.StringGarbageCollection

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2364 | `LINE_WIDTH_STORAGE` | `KEEP` | switch | none |  | vendor | Default for opening the file alone — SDK build switch, already UPPER_SNAKE |
| 2365 | `DISK_STATUS_STRING` | `KEEP` | switch | none |  | vendor | Default for opening the file alone — SDK build switch, already UPPER_SNAKE |
| 2366 | `LINKED_STRING_GARBAGE_COLLECTION` | `LinkedStringGarbageCollection` | macro | P4 P4R |  | vendor | Emits BASIC 4's one-pass linked collector |
| 2367 | `GARBA2` | `Strings::CollectGarbage` | routine | P4 P4R | M6502, CBM4S79 [P4 P4R], HV4, HV4R | vendor | Walks string space down from MEMSIZ by links, sliding live strings over garbage and updating their descriptors; sets FRETOP — Must match part B2's GARBA2; see F-Q8 |
| 2368 | `GLOOP` | `Strings::CollectGarbage::NextString` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Ends at FRETOP |
| 2369 | `COL00` | `Strings::CollectGarbage::Examine` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Lowers the destination past a link unless a gap is open |
| 2370 | `COL00B` | `Strings::CollectGarbage::ReadLink` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Lowers the source past the link and tests for garbage ($FF) |
| 2371 | `COL00A` | `Strings::CollectGarbage::SkipGarbage` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Lowers the source by the garbage length and opens a gap |
| 2372 | `COL01` | `Strings::CollectGarbage::LiveString` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Loads the descriptor address; moves the string only when a gap is open |
| 2373 | `COL02` | `Strings::CollectGarbage::MoveString` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Copies the link and the characters down and updates the descriptor |
| 2374 | `GLOP1` | `Strings::CollectGarbage::CopyByte` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Copies one character |
| 2375 | `COL02B` | `Strings::CollectGarbage::UpdateDescriptor` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Stores the new address in the descriptor |
| 2376 | `COL02A` | `Strings::CollectGarbage::NextMoved` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Next string while moving |
| 2377 | `GRBEND` | `Strings::CollectGarbage::ToFinish` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Only jumps on to Finish |
| 2378 | `COL03` | `Strings::CollectGarbage::KeepString` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Live string with no gap: lowers both pointers by its length |
| 2379 | `ENDGRB` | `Strings::CollectGarbage::Finish` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Sets FRETOP from FRESPC |
| 2380 | `SKIP2` | `Strings::CollectGarbage::SkipLinks` | routine | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Lowers the destination by 2 and falls into SkipSourceLink — Nested routines only the collector calls |
| 2381 | `SKIP2A` | `Strings::CollectGarbage::SkipSourceLink` | routine | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Loads 2 and falls into LowerSource |
| 2382 | `MOVPNT` | `Strings::CollectGarbage::LowerSource` | routine | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Subtracts A from GRBPNT |
| 2383 | `MOV00` | `Strings::CollectGarbage::LowerSource::Store` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Stores the result |
| 2384 | `MOVTOP` | `Strings::CollectGarbage::LowerDestination` | routine | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Subtracts A from GRBTOP |
| 2385 | `MOV01` | `Strings::CollectGarbage::LowerDestination::Store` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Stores the result |
| 2386 | `SETINX` | `Strings::CollectGarbage::LoadDescriptorAddress` | routine | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Copies the link at GRBPNT into INDEX; returns negative |
| 2387 | `SET00` | `Strings::CollectGarbage::LoadDescriptorAddress::NextByte` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | Copies one byte |

### Commodore.TimeAssignment

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2388 | `TIME_STRING_ASSIGNMENT` | `TimeStringAssignment` | macro | PET |  | vendor | Emits the TI$ assignment at the start of the string-assignment path |
| 2389 | `longLengthError` | `KEEP` | parameter of TIME_STRING_ASSIGNMENT | PET |  | vendor | 1 reaches FCERR by jmp for a wrong length, 0 by a branch to ToIllegalQuantity — KEEP |
| 2390 | `TIMELP` | `AssignString::NextPair` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Accumulates two digits, then scales by 6 unless zero — Qualifier follows part B2's INPCOM, see F-Q10 |
| 2391 | `NOML6` | `AssignString::SkipScale` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Counts to six digits; then multiplies by 10, converts and stores |
| 2392 | `TIMEST` | `AssignString::StoreClock` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Stores the three low bytes in CQTIMR with interrupts off |
| 2393 | `TIMNUM` | `AssignString::AddClockDigit` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Adds the digit at INDEX+Y to FAC; ILLEGAL QUANTITY for a non-digit — Nested routine |
| 2394 | `FCERR2` | `AssignString::ToIllegalQuantity` | local | PET | M6502, CBM4S79 [P4 P4R], HV2, HV4, HV4R | vendor | Only jumps on to FCERR; used by the length check and AddClockDigit |
| 2395 | `GOTNUM` | `AssignString::AddClockDigit::Digit` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Converts and adds by FINLOG |

### Commodore.VariableEvaluation

| # | Old | New | Kind | Builds | Documents (checked) | D3 | Reason |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 2396 | `COMMODORE_VARIABLE_VALUE` | `CommodoreVariableValue` | macro | PET |  | vendor | Emits LoadVariableValue with the PET's clock, status and disk-status variables. — SDK name: case only |
| 2397 | `splitEntry` | `KEEP` | parameter of COMMODORE_VARIABLE_VALUE | PET |  | vendor | 1 to enter at EvaluateVariableBody after BASIC 4's trampoline. |
| 2398 | `clockPatch` | `KEEP` | parameter of COMMODORE_VARIABLE_VALUE | PET |  | vendor | 1 to test TI and TI$ through BASIC 1's editor-ROM patches. |
| 2399 | `diskStatus` | `KEEP` | parameter of COMMODORE_VARIABLE_VALUE | PET |  | vendor | 1 to recognize BASIC 4's DS and DS$. |
| 2400 | `ISVAR1` | `EvaluateVariableBody` | routine | P4 P4R | none found | vendor | BASIC 4: the variable lookup (PTRGET) beyond the patch area, reached from the EvaluateVariable trampoline; falls into LoadVariableValue. — see C-Q4 |
| 2401 | `ISVAR` | `EvaluateVariable` | routine | P1 P1R P2 | M6502, HV1, HV1R, HV2 | vendor | Looks up the variable operand (PTRGET) and falls into LoadVariableValue. |
| 2402 | `ISVRET` | `LoadVariableValue` | routine | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | With A/Y = the variable's address: makes TI$ and DS$ strings, else leaves a string's address in Fac; numbers load as TI, ST, DS, integer or float. — the shared lookup compares its return address with this label - 1 |
| 2403 | `TISTR1` | `LoadVariableValue::MatchClockString` | entry | P1 P1R | none found | vendor | BASIC 1: the editor ROM's TISTR returns here to check the I of TI$. |
| 2404 | `ISVDS` | `LoadVariableValue::DiskStatusString` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | BASIC 4: DS$ returns the disk-status string, read if empty. |
| 2405 | `STRRTS` | `LoadVariableValue::Return` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Return with a string's descriptor address in FacMantissa3/4. |
| 2406 | `TINUM1` | `LoadVariableValue::MatchClockNumber` | entry | P1 P1R | none found | vendor | BASIC 1: the editor ROM's TINUM returns here to check the I of TI. |
| 2407 | `CHKDS` | `LoadVariableValue::EnsureDiskStatus` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | BASIC 4: reads the disk status (CQRDDS) only if its descriptor is empty. |
| 2408 | `GETTIM` | `LoadVariableValue::ReadClock` | local | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Copies the jiffy clock into Fac with interrupts off. |
| 2409 | `QSTATV` | `LoadVariableValue::MatchStatus` | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | ST returns the channel status as a number; BASIC 1's TINUM enters here. |
| 2410 | `QDSAV` | `LoadVariableValue::DiskStatusNumber` | local | P4 P4R | CBM4S79 [P4 P4R], HV4, HV4R | vendor | BASIC 4: DS returns the disk status's first two digits as a number. |
| 2411 | `GOMOVF` | `LoadVariableValue::LoadFloat` | entry | PET | M6502, CBM4S79 [P4 P4R], HV1, HV1R, HV2, HV4, HV4R | vendor | Moves the float variable into Fac (MOVFM); BASIC 1's TINUM enters here. |
