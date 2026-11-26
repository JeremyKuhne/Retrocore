# Backlog: static analysis of assembly sources

Status: **survey, with item 4's groundwork done for the 6502 family, the Z80 and the MC6809**. This note gathers what Retrocore already
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
vectors, the flags by word, and quirks such as `indirect-page-wrap Mos6502`. The 6502 family's, the Z80's and
the 6809's descriptions also say which registers and flags each instruction reads and writes (the
[effects lines](#register-and-flag-effects)); the 8080's does not yet.

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
   gets wrong. The first part is done for the 6502 family, the Z80 and the 6809: see
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
description, checked against execution. Done for the 6502 family (`OpcodeTables.txt`: the NMOS 6502 with its
undocumented opcodes, the WDC and Rockwell 65C02s, and the 65SC02 subset), the Z80 (`Z80Isa.txt`) and the MC6809
(`M6809Isa.txt`), their undocumented opcodes included.

### The format

`effects` lines go in `[isa]`, after the `registers` and `flags` lines, beside `flow` and `access`:

```text
stack S
effects ADC SBC                 reads A carry decimal   writes A negative overflow zero carry
effects BIT                     reads A                 writes negative=bit7 overflow=bit6 zero
effects BIT:Immediate           reads A                 writes zero
effects PHP                     reads P S               writes S                        push 1
effects CLC                                             writes carry=0
effects in Wdc65C02 BRK         reads P S               writes S interrupt=1 decimal=0  push 3
effects :AbsoluteIndexedX :ZeroPageIndexedX :ZeroPageIndexedIndirect :AbsoluteIndexedIndirect reads X
effects BRA JMP NOP STZ BBR BBS RMB SMB WAI STP JAM none
```

and for the Z80:

```text
parts AF=A,F BC=B,C DE=D,E HL=H,L IX=IXH,IXL IY=IYH,IYL
stack SP
effects LD                      reads $2                writes $1
effects RL RR                   reads $1 carry          writes $1 $2 F half-carry=0 subtract=0
effects CALL:NZ,nn CALL:Z,nn    reads zero SP           may-write SP                    may-push 2
effects XOR:A writes A negative=0 zero=1 Y=0 half-carry=0 X=0 overflow=1 subtract=0 carry=0
```

and for the 6809, whose postbytes name registers:

```text
parts D=A,B
stack S
effects :Direct                 reads DP
effects TFR                     reads $1                writes $2
effects PULU                    reads U                 writes $1 U                     pull U $1
effects RTI                     reads S                 writes CC S     may-write A B DP X Y U  pull 3  may-pull 9
```

- A line names instructions, then any of `reads`, `writes`, `may-write`, `push`, `pull`, `may-push` and
  `may-pull`, or `none` for an instruction that touches no register or flag.
- `reads` lists what the instruction reads; `writes` what it assigns on every path, so the old value is dead
  afterwards; `may-write` what it changes on some paths only, as a conditional call's SP. What is in none of them
  keeps its value.
- Registers go by name and flags by the word documentation uses (`carry`, not `C`), so the Z80's C register and
  carry flag cannot be confused. A flag without a word, the Z80's undocumented X and Y, goes by its name. The
  flags register by name (`P`, `F`) means every flag, as `PHP` pushes them and `POP AF` pulls them.
- In `writes`, `flag=0` and `flag=1` are constants, and `flag=bitN` is a copy of bit N of the memory operand.
- `parts Pair=Part,Part` makes a register stand for its parts: writing HL writes H and L, and the masks hold only
  the parts. A part the registers line lacks, as the Z80's IXH, is added for effects alone, so the debugger's
  frame, which holds the registers line, does not grow.
- `stack S` names the register `push n` and `pull n` move n bytes through; `push U 2` names another, for the
  6809's user stack. A line that pushes or pulls must read and write (or may-write) that register.
- `$1` to `$8` are the operands of the encoding's form name, split at commas: in `LD A,[HL]`, `$1` is A and `$2`
  is `[HL]`. A register operand is that register; a bracketed one is memory, and reads its address register
  (HL, or IX for `[IX+d]`) wherever the line names it; anything else (`n`, `nn`, a bit number) is nothing.
- Where a form's field is a postbyte, the description's `PostbyteCodec` says what each postbyte names
  (`TryGetEffects`), and `$1` and `$2` take it: a 6809 stack list's registers, or TFR's and EXG's two registers;
  `push $1` and `pull $1` move the list's bytes. An indexed postbyte's address registers add to every instruction
  in an indexed form: the index register, an accumulator offset (`B,X` reads B), PC for `PCR`, and the index
  register written by auto-increment and auto-decrement. Such an encoding's effects are marked
  `DependsOnPostbyte`.
- `Instruction:Form` replaces the instruction's own line, as `BIT:Immediate` changes only zero and `JP:NZ,nn`
  reads zero. A `:Form` line adds to every instruction in that form, as the index register an address is formed
  from, and the accumulator form's `reads A writes A` for the shifts, `INC` and `DEC`.
- `effects in Set` lines win over the description's in that set, the sets built on it (`[Rockwell65C02 :
  Wdc65C02]`) and its subsets (`65SC02`). Within a scope, `Instruction:Form` wins over `Instruction`.
- PC is left to the `flow` lines and the memory operand to the `access` lines. On the Z80 so are R's refresh
  count and the state the registers line does not list: WZ, Q, IFF1 and IFF2, and the interrupt mode. `LD A,R`
  and `LD R,A` name R. On the 6809, NMI's arming and the flags an unprefixed store immediate takes from the
  instruction before it are left out.

Once a description has any `effects` line, every encoding of every set must resolve to one, and every line must
name a known set and be taken by some encoding, so a gap, a misspelling or a line every set overrides fails the
build at its line (`IsaDescriptionGenerator`, RCGEN010).

Where an instruction's result does not depend on a register it reads, the data says so, for liveness: `XOR A`,
`SUB A` and `SBC A,A` do not read A, and `SBC A,A` and `SBC HL,HL` keep the carry. The 6809's `SWI`, `CWAI` and
`X18` set or shift E before it is seen, so they do not read the old E, and `XADDD` and `XADDU` set the flags
without writing D or U.

### The API

`InstructionSet.Effects(encoding)` (and `DisassembledInstruction.Effects`) returns an `InstructionEffects` by
reference into an array built with the set, so a lookup neither allocates nor copies. It holds the registers read,
written and maybe written as bits by index in `IsaDescription.EffectRegisters`, which `RegisterMask(name)` gives
for a name (a pair's parts' bits); the flags read, written, maybe written, set and cleared as bits of the flags
register; the flags copied from the operand, with `OperandBit(flag)`; the bytes pushed and pulled, always and on
some paths; and the stack register. `ReadsAny(mask)` and `ChangesAny(mask)` test a register or pair.
`InstructionSet.HasEffects` says whether the description has them; without, `IsKnown` is false. Where
`DependsOnPostbyte` is set, `Effects(encoding)` leaves out what the postbyte names, and
`Effects(encoding, postbyte)` adds it from tables of every postbyte built with the set, so it too is an array
lookup that allocates nothing; `DisassembledInstruction.Effects` passes the postbyte.

What it costs, measured in Release: a lookup about 1.3 ns, with nothing allocated; the tables 36 bytes an encoding,
about 37 KB for the four 6502 family sets, 45 KB for the Z80's 1,255 encodings, and for the 6809 its encodings' and
about 20 KB of postbyte tables (four field kinds, 256 postbytes each); nothing for a set whose description has no
effects. Parsing a description, done once a process and only when first used, allocates 260 KB (6502) and 395 KB (Z80)
of short-lived memory more than without the lines, and takes roughly 0.5 to 1 ms more. The cores do not read the data,
and the generator that builds the 6502 cores skips `[isa]`, so execution is unchanged.

### How it is checked

- `InstructionEffectsTests.M6502EffectsMatchExecution`, `Z80EffectsTests.Z80EffectsMatchExecution` and
  `M6809EffectsTests.M6809EffectsMatchExecution` run every encoding on the core from random states, 64 each on the 6502
  and Z80 and 1,024 on the 6809 with a random valid postbyte each, some at the values where rare changes happen (BC at
  1, low halves at $FF and 0, A at a 16-bit immediate's high byte). What the data says is not written must keep its
  value; constants must take theirs; a copied flag must be the operand's bit; the stack must move by the bytes pushed
  and pulled. Then each register and flag is changed in turn: one the data says is not read must change nothing else,
  neither the result nor any bus or port access. The data is also checked the other way: every register and flag it says
  is read must make a difference, and every one it says is written must change, in some case. Writing a register with
  its own value, as `LD B,B` and `AND A` do, is allowed. For a 6809 postbyte, the claims of all its cases are checked
  together. The data matches exactly, so it says no more than the cores do, and no less; planted errors in each
  description, and in the 6809 codec, were caught.
- `M6502EffectsMatchSingleStepVectors` and `Z80EffectsMatchSingleStepVectors` (category `Conformance`) check the
  same unchanged, constant and stack claims against the SingleStepTests vectors the cores are certified against:
  7,660,000 for the 6502 family and the Z80's 1,604 files. They need the fixtures from
  `tools/Fetch-ProcessorTests.ps1` and `tools/Fetch-Z80Tests.ps1` and are inconclusive without them. The 6809
  has no such vectors; its core is checked by the functional, cycle and interrupt programs
  (`M6809ConformanceTests`, from `tools/Fetch-M6809Tests.ps1`) and `M6809UndocumentedTests`, so its effects are
  as good as the core.
- `InstructionFlagsTests.M6502HoverFlagsComeFromTheEffects`: the 6502 family's hover and inspector flags now come
  from the data, and match the strings the hover listed by hand before, kept as the test's expectations. B, only
  a bit of the byte `BRK` and `PHP` push, is no flag, so `BRK` shows I, and D I on the 65C02s.

### Decisions

Taken on the open questions this work raised:

- One-path changes get `may-write`, `may-push` and `may-pull`, rather than counting as written, which would make
  liveness wrong after a conditional call.
- Pairs declare their parts, and effects keep bits on the parts alone.
- The undocumented IXH, IXL, IYH and IYL are IX's and IY's parts, so an instruction says exactly which half it
  touches.
- The Z80's X and Y flags are tracked, by name.
- `stack` sets the description's stack register, and a push or pull may name another.
- The 6502 hover's flags come from the data.
- The 6809's `PSHS`, `PULS`, `TFR` and `EXG`, and its indexed modes, take their registers from its
  `PostbyteCodec`, with a lookup that takes the postbyte.

### Follow-ups

- **The 8080 and 8085,** in the Z80's form: `parts PSW=A,F BC=B,C DE=D,E HL=H,L`, and the 8085's `RIM` and `SIM`.
- **The Z80 and 6809 hovers.** Their "Flags:" text and the inspector's special cases (`InstructionDocs.Z80.cs`,
  `InstructionDocs.M6809.cs`, and `FlagsOf`'s for `EXG`, `PULS` and `TFR`) could come from the data as the
  6502's now do.

## Open questions

- Where analysis runs: the assembler, the language server alone, or both, and whether CI fails on warnings.
- How a source says what the hints file says for disassembly: entry points, calls that never return or take inline
  bytes, data. Perhaps `;;` sections, which documentation already uses for `Entry:`.
- How `.if` builds are analyzed: once per build, as the documentation lint resolves each build's topics.
