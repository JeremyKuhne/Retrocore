# Backlog: static analysis of assembly sources

Status: **survey, with item 4's groundwork done for the 6502 family**. This note gathers what Retrocore already
checks, what other assemblers and tools check, and where the two differ, as the starting point for a design. The
[effects lines](#register-and-flag-effects) are decided; the analyses that would use them are not.

## What Retrocore has

### Flow analysis

`AnalysisEngine` (`src/Retrocore.Assembler/Assembler/AnalysisEngine.cs`) follows code from entry points and the
CPU's vectors, without recursion, and records which instruction owns each byte, so a target in the middle of an
operand is told apart from an instruction boundary. A caller can pin ranges as code or data
(`AnalysisRegionKind`), and mark calls that never return or that take inline bytes or a zero-terminated string
(`AnalysisCallKind`: `NoReturn`, `InlineBytes`, `InlineZeroTerminated`). It reports references by kind: call,
jump, branch, vector, indirect jump, read, write and read-write.

What it knows of each CPU comes from the instruction-set descriptions (`OpcodeTables.txt`, `Z80Isa.txt`,
`M6809Isa.txt`, `I8080Isa.txt`): the `flow` lines (`InstructionFlow`), the `access` lines (`MemoryAccess`), the
vectors, the flags by word, and quirks such as `indirect-page-wrap Mos6502`. The 6502 family's description also
says which registers and flags each instruction reads and writes (the [effects lines](#register-and-flag-effects));
the other CPUs' do not yet, and their hovers' "flags it changes" is still text, not data an analysis can use.

Two features use it:

- **The disassembler** (`retrocore-disassembly` skill), with a JSON hints file (`entries`, `data`, `names`,
  `comments`, `noReturn`, `inline`), a byte-identical reassembly check, and a report of the bytes no followed code
  reached.
- **Retrocore Memory's listing** (`DebugSession.MemoryAnalysis.cs`, [Memory.md](../Memory.md)), which guesses at
  code and data where no source describes the bytes ([MemoryViewer.md](MemoryViewer.md), step 4).

### The assembler

Every assembler diagnostic is an error, with one code (`RETROCOREASM001`, `AssemblyDiagnostic`). Out-of-range
operands, branches and displacements are errors. There is no warning tier and no categories; `.warning` and `.out`
are accepted and ignored. `.assert e[, "message"]` is checked once every address is known, and `.error` and
`.fatal` fail ([NativeAssembly.md](../NativeAssembly.md#exports-assertions-and-messages)).

### The lint

The language server checks documentation and style under 19 rule IDs (`DocumentationRules`,
[DocComments.md](../DocComments.md#5-checked-contracts)): `line-length`, `ascii`, `trailing-doc`, `label-alone`,
`address-name`, `column-zero`, `indent`, `comment-indent`, `unlinked-name`, `link`, `ambiguous-link`, `also`,
`sections`, `historical-name`, `deprecated`, `using-shadow`, `undocumented-export`, `placement` and `exclusion`.
Registers and flags in `In:`, `Out:`, `Keeps:` and `Uses:` are checked against the routine's CPU, and `Entry:`
labels must lie inside the routine. `; retrocore: ignore=` turns a rule off for a file, a line or a `;;` block, may
be narrowed to names, and is itself reported when it turns nothing off ([LintExclusions.md](LintExclusions.md)).
`SdkDocumentationTests.EveryRepositorySourceIsCleanInTheEditor` lints every source under `src` and `sample` in CI.

### Contracts, checked at run time

The debugger checks `Keeps:` when a call returns (`checkContracts`: `warn`, `stop` or `off`) and `Uses:` with
`checkUses` (`DebugContracts.cs`). Nothing checks them without running the code. The SDK's sources already state a
great deal: about 1,040 `Keeps:` lines, 1,780 `Uses:`, 3,700 `In:`, 3,000 `Out:` and 750 `Entry:`, and 234 of 473
assembly files are `style=strict`.

### What conversions found by hand

The conversion logs record problems a reader found that a checker could have:

- AppleSoft's 10 unreachable bytes at $F530: carry is always clear after the `ror` before the last `bcc`
  ([Basic.md](../conversions/Basic.md), E-Q9). Flag values would find it.
- The 3.5 disk firmware's media check reads `MediaKind` at a leftover Y ([Disk35.md](../conversions/Disk35.md)).
  Register liveness would find it.
- DOS 3.2's dead `CHKPOSITION` ([Dos.md](../conversions/Dos.md), P20). Unreferenced code.
- Routines that fall into the next one: `NMARY1` into BAD SUBSCRIPT, `NOTIT` into `ISLETC`, `UPNXT`
  ([BasicRenames.md](../conversions/BasicRenames.md)). Fall-through edges.

### Other plans that touch it

- [I8080.md](I8080.md) and [M6809-CoCo.md](M6809-CoCo.md): flow analysis for those CPUs (the restarts, the 8085's
  interrupts, the 6809's fields through the instruction-set description).
- [DocComments.md](../DocComments.md#6-open-questions): linking bare names automatically.
- The extension's README: rename, semantic tokens and inlay hints are not done yet.

## What other tools do

Read from each project's manual or source, where the manual's site could not be reached, from its repository.

### Assemblers

- **64tass** ([manual](https://tass64.sourceforge.net/)): `-Wall`, `-Werror=name`, `-Wno-error=name`. Off by
  default: `branch-page`, `long-branch`, `unused` (`-label`, `-const`, `-macro`, `-variable`), `shadow`,
  `case-symbol`, `immediate` (immediate mode probably meant), `optimize`, `align`. On by default: `jmp-bug`
  (`JMP ($xxFF)`), `pitfalls`, `wrap-addr`, `wrap-dpage`, `wrap-pc` and the other wraps, `page`. `.page`/`.endp`
  checks a block stays in one page; `.cwarn` and `.cerror` are conditional messages.
- **RGBDS** ([rgbasm(1)](https://raw.githubusercontent.com/gbdev/rgbds/master/man/rgbasm.1),
  [rgbasm(5)](https://raw.githubusercontent.com/gbdev/rgbds/master/man/rgbasm.5)): `-Wall`, `-Wextra`,
  `-Weverything`; leveled warnings such as `-Wtruncation=0..2`; `PUSHO`/`POPO` with `OPT -Wno-...` for a region of
  source. `ASSERT` may wait for the linker (`ASSERT BANK(A) == BANK(B)`); `STATIC_ASSERT` may not. Both take
  `WARN`, `FAIL` or `FATAL`.
- **sjasmplus** ([documentation](https://raw.githubusercontent.com/z00m128/sjasmplus/master/docs/documentation.xml)):
  warnings with IDs, such as `rdlow` (a read from 0-255), `fwdref`, `out0`, `orgpage`, `nexstack`. A line turns one
  off with a comment containing `id-ok` (`; rdlow-ok`), the only per-line form found besides ours. `OPT -Wno-id`
  in source, `--help=warnings` lists them. Warnings without an ID can't be turned off.
- **ca65 and ld65** ([ca65](https://raw.githubusercontent.com/cc65/cc65/master/doc/ca65.sgml),
  [ld65](https://raw.githubusercontent.com/cc65/cc65/master/doc/ld65.sgml)): `-W n` levels;
  `.assert e, warning|error|ldwarning|lderror, "message"` is checked by the assembler if it can and again by the
  linker after placement. Range checks wait for the linker when the value isn't known. `.smart` follows `REP`/`SEP`
  for 65816 sizes but "cannot trace the execution flow". `--warn-align-waste`.
- **ACME** ([errors](https://raw.githubusercontent.com/meonwax/acme/master/docs/Errors.txt)): warns of `JMP ($xxFF)`,
  unstable `ANE`/`LXA #nonzero`, a zero-page pointer wrapping at $FF, an oversized addressing mode, overlapping
  segments, and `SED` on a CPU with the decimal bug. `-Wtype-mismatch` turns on address/integer types.
- **BeebAsm** ([README](https://raw.githubusercontent.com/stardot/beebasm/master/README.md)): `GUARD addr` fails on
  code assembled over it; overwriting assembled code fails unless `CLEAR`ed; `SKIPTO` fails going backwards.
- **Asar** ([warnings](https://raw.githubusercontent.com/RPGHacker/asar/master/docs/manual/warnings-list.html)):
  named warnings, `warnings enable|disable|push|pull` in source, `check bankcross` for bank crossings.
- **Kick Assembler** ([manual](https://theweb.dk/KickAssembler/webhelp/content/cpt_QuickReference.html)): its
  `.assert` and `.asserterror` are unit tests, comparing a value or two blocks' bytes, or expecting an error, and
  counted at the end ([testing](https://theweb.dk/KickAssembler/webhelp/content/cpt_Testing.html)). The build's
  checks are memory blocks overlapping in a segment (an error unless `allowOverlap`, a warning with `-aom`) and a
  segment's `min=`/`max=` ([segments](https://theweb.dk/KickAssembler/webhelp/content/ch10s11.html)). `.errorif`
  fails on a condition; `-warningsoff` is the only warning switch; `-asminfo` gives editors errors and syntax.
- **Merlin 32** ([page](https://www.brutaldeluxe.fr/products/crossdevtools/merlin/)): duplicate labels and macros
  and unknown lines; follows the 65816's M and X widths from `MX`, `SEP` and `REP` line by line, and asks for an
  `MX` after `PLP`, where it can't know them. No warning categories.
- **lwasm** ([pragmas](https://www.lwtools.ca/manual/x681.html), [listings](https://www.lwtools.ca/manual/x861.html)):
  pragmas in source or on the command line, stackable. `operandsizewarning` warns of an addressing mode larger than
  needed, such as a long branch that could be short; pragma `6809` makes 6309 instructions errors. Listings show
  cycle counts (`opt c`, by mode with `opt cd`, running totals with `opt ct`, `+?` where they vary). `testmode`
  checks each line against expected bytes or errors in `;.` comments.
- **vasm** ([manual](https://raw.githubusercontent.com/StarWolf3000/vasm-mirror/master/doc/vasm_main.texi)):
  `-nowarn=n`, `-wfail`, `-x` for undefined symbols; **DASM**, **WLA-DX**, **z88dk z80asm** and **6502.Net** add
  little beyond strict modes, assertions and unused-symbol listings.

### Analyzers and editors

- **SourceGen** ([analysis](https://raw.githubusercontent.com/fadden/6502bench/master/docs/sgmanual/analysis.html)):
  traces from entry points and carries each flag's state (N, V, M, X, D, Z, I, C), merging where paths join. A
  known flag prunes a branch, which is shown as never taken. It follows the 65816's M, X and E and the data bank.
  It does not track the stack; `PLP` makes the flags unknown unless "smart PLP" finds the `PHP`. Tags mark code
  starts, stops and inline data; cycle counts show `+` where a page crossing can add one. (Its "NiftyList" is a
  source of IIgs symbol names, from Dave Lyons' utility, not an analysis.)
- **Regenerator 2000** ([analysis](https://raw.githubusercontent.com/ricardoquesada/regenerator2000/main/docs/analysis.md)):
  five passes that classify operands, find address tables (split low and high too), name labels by how they are
  reached (`s_` subroutine, `j_` jump, `b_` branch, zero-page `zpa_`, `zpp_` and so on), keep cross-references by
  kind (read, write, call, jump), and resolve `JMP (ind)` through known tables. The zero-page labels and
  cross-references amount to a zero-page usage map.
- **Ghidra** ([processors](https://github.com/NationalSecurityAgency/ghidra/tree/master/Ghidra/Processors),
  [auto analysis](https://raw.githubusercontent.com/NationalSecurityAgency/ghidra/master/Ghidra/Features/Base/src/main/help/help/topics/AutoAnalysisPlugin/AutoAnalysis.htm)):
  6502 and 65C02 (not the 65816), Z80, 8085 and 6809. Its generic analyzers apply: functions from calls, stack
  frames from stack references, data references and the decompiler's parameters. How well they serve the 6502 was
  not checked. **IDA** ([6502](https://docs.hex-rays.com/core/disassembler/disassembly-gallery/6502-and-65c02-disassembler))
  disassembles the 6502, 65C02, Z80 and 6809; which of its analyses apply to them was not found.
- **DeZog** ([reverse engineering](https://raw.githubusercontent.com/maziac/DeZog/main/documentation/ReverseEngineeringUsage.md)):
  disassembles from the PC, redoes it when memory there changes (`JP (HL)`, interrupts and self-modifying code
  are beyond it), draws call graphs and flowcharts, and takes `ASSERTION`, `WPMEM` and `LOGPOINT` comments.
- **go6asm** ([analyze.go](https://raw.githubusercontent.com/carledwards/go6asm/main/analyze/analyze.go)): the
  closest to a 6502 linter. Reachability from the vectors and exports, with A0001 reachable `BRK`, A0002 an
  illegal opcode, A0003 an indirect jump, A0004 a write to ROM, A0005 an unmapped access from a device map, A0006
  control leaving the image. Its rule: indirect jumps, jump tables and self-modifying code are reported as
  boundaries, never assumed safe. Planned: reset hygiene (`CLD`, `TXS`), `RTI` against `RTS` in handlers,
  register preservation by liveness, `ADC` with an unknown carry, a stack-depth estimate, Apple II soft-switch
  read-modify-write.
- **SixtyPical** ([README](https://raw.githubusercontent.com/catseye/SixtyPical/master/README.md)): a 6502-level
  language whose effect system finds a missing `CLC` before `ADC`, a callee changing a register its caller
  relied on, and out-of-bounds table indexes.
- **llvm-mos**: a static stack from the call graph, overlaying zero page for functions never active together
  (release notes only).
- **asm-lsp**, **beeb-vsc**, **Z80 Assembly meter**: editor diagnostics come from running an assembler, or from
  reimplementing its checks; the meter counts T-states for a selection.

### By category

| Category | Who has it | Retrocore |
| --- | --- | --- |
| Warning categories and switches | 64tass, RGBDS, sjasmplus, Asar, vasm | Lint only; the assembler has errors alone |
| Per-line and per-region suppression | sjasmplus (`id-ok`); RGBDS, Asar (push and pop) | `ignore=` for a file, a line, a `;;` block |
| Unused and shadowed symbols | 64tass, ca65 `-W2`, DASM | No |
| Larger addressing than needed | 64tass `optimize`, lwasm `operandsizewarning` | No |
| Range and truncation | All, as errors; RGBDS leveled | Errors |
| Page crossing and timing | 64tass `branch-page`, `.page`; SourceGen and lwasm cycle counts | Cycle counts in the debugger and hover |
| CPU bugs and wraps | 64tass, ACME | The ISA knows `indirect-page-wrap`; nothing warns |
| Memory map and overlap | BeebAsm, ACME, Asar, sjasmplus, go6asm, Kick Assembler (`min`/`max`, overlap) | No |
| Link-time assertions | ca65, RGBDS (Kick Assembler's `.assert` is a unit test) | `.assert` after layout |
| Reachability, code and data | SourceGen, DeZog, go6asm, Regenerator 2000, Ghidra | `AnalysisEngine`, for disassembly and memory |
| Flag and register dataflow | SourceGen (flags), SixtyPical; register widths in ca65 `.smart`, Merlin 32 | No |
| Stack balance | None | No |
| Calling contracts | SixtyPical | `Keeps:`/`Uses:` at run time |
| Call graph | DeZog, Ghidra | References from analysis, not shown as a graph |
| Zero-page usage | Regenerator 2000 (typed labels) | No |

No mainstream assembler checks register liveness, stack balance, self-modifying code or calling contracts. Those
exist only in SourceGen, SixtyPical, go6asm's plans and compilers.

## Where we differ

Retrocore is ahead in its lint: named rules that are a public contract, exclusions that must turn something off, a
CI gate over every source, and thousands of documented routine contracts. It is behind in the assembler's own
warnings, which most assemblers have.

### Gaps others have filled

1. **A warning tier in the assembler.** Named, ignorable assembler warnings, through the same rule IDs and
   `ignore=` as the lint. Everything below needs it; [LintExclusions.md](LintExclusions.md) left it out of scope.
2. **Unused and shadowed symbols:** labels, constants and macros nothing uses, in the editor, where
   [Using.md](Using.md)'s name resolution already knows each use.
3. **CPU pitfalls:** NMOS `JMP ($xxFF)`, a zero-page pointer at $FF, undocumented or unstable opcodes on a CPU
   that has them, and, opted into like `.page`, a branch that crosses a page in timed code.

### What no one does yet

4. **`Keeps:` and `Uses:` without running.** The instruction-set descriptions say what each instruction reads
   and writes, and a per-routine dataflow over `AnalysisEngine`'s flow would take each callee's documented
   contract at a `JSR` or `CALL`. It would find the leftover-Y kind of problem and contracts the documentation
   gets wrong. The first part is done for the 6502 family: see
   [Register and flag effects](#register-and-flag-effects). The dataflow is not.
5. **Flag values,** as SourceGen carries them, to report branches never taken and the code only they reach.
6. **Unreferenced code and fall-through:** what no entry point reaches, and a routine that runs into the next,
   for the conversions to document.
7. **Stack balance:** pushes and pulls on every path through a routine, with a pushed address and `RTS` reported
   as a boundary, not a fault.
8. **Memory-map checks from the machines:** writes to ROM, a read-modify-write of an Apple II soft switch, indexed
   accesses that touch I/O twice.

## Register and flag effects

The groundwork for items 4 and 5: each instruction's register and flag effects, as data in the instruction-set
description, checked against execution. Done for the 6502 family (`OpcodeTables.txt`): the NMOS 6502 with its
undocumented opcodes, the WDC and Rockwell 65C02s, and the 65SC02 subset.

### The format

`effects` lines go in `[isa]`, after the `registers` and `flags` lines, beside `flow` and `access`:

```text
effects ADC SBC                 reads A carry decimal   writes A negative overflow zero carry
effects BIT                     reads A                 writes negative=bit7 overflow=bit6 zero
effects BIT:Immediate           reads A                 writes zero
effects PHP                     reads P S               writes S                        push 1
effects CLC                                             writes carry=0
effects in Wdc65C02 BRK         reads P S               writes S interrupt=1 decimal=0  push 3
effects :AbsoluteIndexedX :ZeroPageIndexedX :ZeroPageIndexedIndirect :AbsoluteIndexedIndirect reads X
effects BRA JMP NOP STZ BBR BBS RMB SMB WAI STP JAM none
```

- A line names instructions, then any of `reads`, `writes`, `push n` and `pull n`, or `none` for an instruction
  that touches no register or flag.
- `reads` lists what the instruction reads; `writes` what it assigns on every path, so the old value is dead
  afterwards. What is not written keeps its value.
- Registers go by name and flags by the word documentation uses (`carry`, not `C`), so the Z80's C register and
  carry flag cannot be confused. A flag without a word, such as the Z80's undocumented X and Y, goes by its name.
  The flags register by name (`P`) means every flag, as `PHP` pushes them and `PLP` pulls them.
- In `writes`, `flag=0` and `flag=1` are constants, and `flag=bitN` is a copy of bit N of the memory operand.
- `push n` and `pull n` move n bytes through the stack S points to; the line also lists S as read and written.
- `Instruction:Form` replaces the instruction's own line, as `BIT:Immediate` changes only zero. A `:Form` line
  adds to every instruction in that form, as the index register an address is formed from, and the accumulator
  form's `reads A writes A` for the shifts, `INC` and `DEC`.
- `effects in Set` lines win over the description's in that set, the sets built on it (`[Rockwell65C02 :
  Wdc65C02]`) and its subsets (`65SC02`). Within a scope, `Instruction:Form` wins over `Instruction`.
- PC is left to the `flow` lines and the memory operand to the `access` lines.

Once a description has any `effects` line, every encoding of every set must resolve to one, and every line must
name a known set and an instruction or form some set has, so a gap or a misspelling fails the build at its line
(`IsaDescriptionGenerator`, RCGEN010).

### The API

`InstructionSet.Effects(encoding)` (and `DisassembledInstruction.Effects`) returns an `InstructionEffects`, a
small value read from an array built with the set, so a lookup allocates nothing. It holds the registers read and
written as bits by index in `IsaDescription.Registers`; the flags read, written, set and cleared as bits of the
flags register; the flags copied from the operand, with `OperandBit(flag)`; and the bytes pushed and pulled.
`InstructionSet.HasEffects` says whether the description has them; without, `IsKnown` is false.

### How it is checked

- `InstructionEffectsTests.M6502EffectsMatchExecution` runs every opcode of each CPU on the core from 64 random
  states each. What the data says is not written must keep its value; constants must take theirs; a copied flag
  must be the operand's bit; S must move by the bytes pushed and pulled, with a stack write per byte pushed. Then
  each of A, X, Y, S and the six flags is changed in turn: one the data says is not read must change nothing else,
  neither the result nor any bus cycle. The data is also checked the other way: every register and flag it says
  is read must make a difference, and every one it says is written must change, in some case. The data matches
  exactly, so it says no more than the core does, and no less.
- `InstructionEffectsTests.M6502EffectsMatchSingleStepVectors` (category `Conformance`) checks the same unchanged,
  constant, copied-bit and stack claims against all 7,660,000 SingleStepTests vectors, which the core is certified
  against. It needs the fixtures from `tools/Fetch-ProcessorTests.ps1` and is inconclusive without them.
- `InstructionFlagsTests.M6502AgreesWithTheEffects`: the memory inspector's hand-written flags for each
  documented encoding are those the data says are written, B aside, which exists only in the pushed byte.

### Follow-ups

- **The hover and inspector text.** The 6502 family's "Flags:" text (`InstructionDocs.cs`) could be derived from
  the data, replacing its special cases for `BIT #` and `BRK`; the test above shows the two agree.
- **The Z80.** The same form, with decisions the 6502 did not need: register pairs, which overlap their halves
  (writing HL writes H and L) and so want a register to name its parts; the undocumented IXH, IXL, IYH and IYL,
  which the registers line lacks; the X and Y flags; conditional calls and returns, whose pushes and pulls happen
  on one path only; block instructions that repeat; and `EX`, `EXX` and the shadow registers. `Z80Isa.txt` has
  about 1,400 opcode lines, and the oracle and FUSE tests would check it as the SingleStepTests check the 6502.
- **The 8080 and the 6809.** The 6809's `PSHU` and `PULU` move the U stack, so `push` and `pull` would need to
  name a stack register, and `PSHS`, `PULS`, `TFR` and `EXG` depend on their postbyte, which effects by form
  cannot express.

## Open questions

- Where analysis runs: the assembler, the language server alone, or both, and whether CI fails on warnings.
- How a source says what the hints file says for disassembly: entry points, calls that never return or take inline
  bytes, data. Perhaps `;;` sections, which documentation already uses for `Entry:`.
- How `.if` builds are analyzed: once per build, as the documentation lint resolves each build's topics.
- How the Z80, 8080 and 6809 descriptions take on effects (see the follow-ups under
  [Register and flag effects](#register-and-flag-effects)).
- Whether `writes` should also have a "may write" form, for an instruction that changes a register only on some
  paths, such as a conditional call's push; no 6502 instruction needs one.
