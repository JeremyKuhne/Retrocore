# Backlog: static analysis of assembly sources

Status: **survey only**. This note gathers what Retrocore already checks, what other assemblers and tools check, and
where the two differ, as the starting point for a design. Nothing here is decided.

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
vectors, the flags by word, and quirks such as `indirect-page-wrap Mos6502`. The descriptions do not say which
registers and flags each instruction reads and writes; the hover's "flags it changes" is text, not data an analysis
can use.

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

Read from each project's manual or source. Kick Assembler, Merlin 32, lwasm, Ghidra and IDA could not be checked
from a primary source and are left out.

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
- **vasm** ([manual](https://raw.githubusercontent.com/StarWolf3000/vasm-mirror/master/doc/vasm_main.texi)):
  `-nowarn=n`, `-wfail`, `-x` for undefined symbols; **DASM**, **WLA-DX**, **z88dk z80asm** and **6502.Net** add
  little beyond strict modes, assertions and unused-symbol listings.

### Analyzers and editors

- **SourceGen** ([analysis](https://raw.githubusercontent.com/fadden/6502bench/master/docs/sgmanual/analysis.html)):
  traces from entry points and carries each flag's state (N, V, M, X, D, Z, I, C), merging where paths join. A
  known flag prunes a branch, which is shown as never taken. It follows the 65816's M, X and E and the data bank.
  It does not track the stack; `PLP` makes the flags unknown unless "smart PLP" finds the `PHP`. Tags mark code
  starts, stops and inline data; cycle counts show `+` where a page crossing can add one.
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
| Range and truncation | All, as errors; RGBDS leveled | Errors |
| Page crossing and timing | 64tass `branch-page`, `.page`; SourceGen | Cycle counts in the debugger and hover |
| CPU bugs and wraps | 64tass, ACME | The ISA knows `indirect-page-wrap`; nothing warns |
| Memory map and overlap | BeebAsm, ACME, Asar, sjasmplus, go6asm | No |
| Link-time assertions | ca65, RGBDS | `.assert` after layout |
| Reachability, code and data | SourceGen, DeZog, go6asm | `AnalysisEngine`, for disassembly and memory |
| Flag and register dataflow | SourceGen (flags), SixtyPical | No |
| Stack balance | None | No |
| Calling contracts | SixtyPical | `Keeps:`/`Uses:` at run time |
| Call graph | DeZog | References from analysis, not shown as a graph |

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

4. **`Keeps:` and `Uses:` without running.** The instruction-set descriptions would say what each instruction
   reads and writes, and a per-routine dataflow over `AnalysisEngine`'s flow would take each callee's documented
   contract at a `JSR` or `CALL`. It would find the leftover-Y kind of problem and contracts the documentation
   gets wrong.
5. **Flag values,** as SourceGen carries them, to report branches never taken and the code only they reach.
6. **Unreferenced code and fall-through:** what no entry point reaches, and a routine that runs into the next,
   for the conversions to document.
7. **Stack balance:** pushes and pulls on every path through a routine, with a pushed address and `RTS` reported
   as a boundary, not a fault.
8. **Memory-map checks from the machines:** writes to ROM, a read-modify-write of an Apple II soft switch, indexed
   accesses that touch I/O twice.

## Open questions

- Where analysis runs: the assembler, the language server alone, or both, and whether CI fails on warnings.
- How a source says what the hints file says for disassembly: entry points, calls that never return or take inline
  bytes, data. Perhaps `;;` sections, which documentation already uses for `Entry:`.
- How `.if` builds are analyzed: once per build, as the documentation lint resolves each build's topics.
- How much the instruction-set descriptions take on: register and flag effects for the 6502 family, the Z80, the
  8080 and the 6809, kept as data the cores' tests can check against execution.
