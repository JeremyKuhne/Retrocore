# Backlog: language server SDK index speed

Status: **round in progress, started 2026-11-24.** The language server indexes every SDK ROM source when it starts,
for links to other modules and workspace search (`SdkIndex`, 69 roots). This page tracks where that time and memory
go, every change measured, and the candidates left, so a later round starts from evidence.

## How it is measured

- **Benchmark:** `SdkIndexBenchmarks` in `tests/Retrocore.Perf`. `Index` builds the index as `SdkIndex` does, every
  root or AppleSoft's alone; `Assemble` is the assembly and analysis without parsing the documentation. Its cleanup
  checks each root's success, bytes, symbol count and topic count against setup.

  ```powershell
  dotnet run -c Release --project tests/Retrocore.Perf -- --filter *SdkIndexBenchmarks* --affinity 80
  ```

- **Every row** is in [SdkIndexResults.csv](../../tests/Retrocore.Perf/SdkIndexResults.csv), one per step and case.
- **Where time goes:** ETW through filtrace's `Capture-BenchmarkTrace.ps1 -Profiler ETW`, with `--native-symbols` for
  the GC. **Where allocations go:** `dotnet-trace` on the benchmark run `--inProcess`, with the runtime provider
  `0x4C14FCCBD` at level 5, ranked with `filtrace rank --metric alloc`.
- **Equivalence gate:** every change must leave the editor exactly as it was. A dump of all 181 ROM roots (repository
  and SDK) is compared with `main`'s: each root's assembled bytes' SHA-256, the editor's documentation diagnostics,
  the lint, every historical name's definition, every definition with its position and value, the CPU at every
  line, and scoped name lookups (133,007 lines). It has matched exactly after every step.
- Release, Ryzen 9 9950X3D, pinned to two physical cores (`--affinity 80`), BenchmarkDotNet's default job. These are
  steady-state numbers; a fresh process also pays JIT and first use, about 3.5 s in total before this round.

## Progress

Indexing every SDK root:

| Step | Commit | Change | Time | Allocated | Time vs baseline | Allocated vs baseline |
| --- | --- | --- | --- | --- | --- | --- |
| Baseline | 29a687c1 | `main` after #141 | 1,162 ms | 1,389 MB | | |
| 1 | be52d5dd | Each source path made full once | 1,054 ms | 1,388 MB | −9% | 0% |
| 2 | 0fe00cc8 | Each file read once per build | 1,017 ms | 1,313 MB | −12% | −5% |
| 3 | dcd63404 | One prefiltered pass for macros | 949 ms | 1,081 MB | −18% | −22% |
| 4 | 04904961 | Type directives told by their words | 942 ms | 1,039 MB | −19% | −25% |
| 5 | d255b05c | Each file split into lines once | 894 ms | 938 MB | −23% | −32% |
| 6 (`b1`) | f33ce65d | The parser reads each line in place | 874 ms | 834 MB | −25% | −40% |
| 7 (`b2`) | 83190f75 | The style checks read lines in place | 885 ms | 810 MB | −24% | −42% |
| 8 (`a1`) | e886a86e | Each source's `Also:` names read once | 847 ms | 737 MB | −27% | −47% |
| 9 (`m1`) | baf631e6 | Macro names looked up by their text | 819 ms | 705 MB | −30% | −49% |
| 10 (`u1`) | c578ae00 | Each path upper-cased once | 798 ms | 682 MB | −31% | −51% |
| 11 (`c1`) | fff4bbeb | Lines split without replacing CRLF first | 819 ms | 665 MB | −30% | −52% |
| 12 (`r1`) | ab9c208a | Assembled lines passed over before matching | 813 ms | 641 MB | −30% | −54% |
| 13 (`k1`) | 05910d6d | Less kept after the index is built | 815 ms | 641 MB | −30% | −54% |

AppleSoft's root alone: 50.1 ms and 67.7 MB at the baseline, 27.2 ms and 26.5 MB after step 13.

What the index keeps alive once built, from a heap walk (see [What the index keeps](#what-the-index-keeps)): 184 MB
after step 12, 171 MB after step 13.

### 1. Each source path made full once

`Path.GetFullPath` was called for every statement, symbol and source-map entry (`SourceAnalysis`'s constructor and
`DocumentationSet.ReadCpus`), though a root names a few dozen files: 10.7% of the index's CPU. A dictionary for the
one analysis, and one for the one CPU map, make each path full once.

### 2. Each file read once per build

The assembly read every included file and the analysis read each again for its lines, and every SDK root read again
the files it shares with others, such as Microsoft's BASIC: about 6% of CPU in opening and reading. `SourceFileCache`
holds the text for one analysis, or one build of the index, and serves the resolver and the analysis. Later lookups
of other files still read the disk.

### 3. One prefiltered pass for macros

The documentation parser classified every line twice with `Define`, for the macros' names and for the macros whose
bodies start with data, to find the few lines that define a macro: 19% of all allocations, and 94% of `Define`'s CPU.
Only `.macro`, `.mac`, Merlin's `MAC` and MACRO-10's `DEFINE` define one, and each has `mac` or `define` in it, so one
pass classifies only those lines and both lists come from it.

### 4. Type directives told by their words

`TypeLine`, for every code line, read its words, trimmed and lower-cased, to find `.enum`, `.struct`, `.union` and
their ends: about 5% of allocations. A line without `enum`, `struct` or `union` is answered at once.

Steps 3 and 4 compare ignoring case where the parser lowers with `ToLowerInvariant`. Across UTF-16, the only
character outside ASCII that lowers to an ASCII letter is the Kelvin sign (to `k`), which none of those words has, so
the prefilters pass every line the full checks would accept.

### 5. Each file split into lines once

The analysis split every file it read; the editor's documentation parse joined those lines back together and split
them again; and the assembler's `Also:` pass split each documented file once more. Every root repeated this for the
files it shares. The preprocessor was never among them: it walks lines as slices of the text. Now
`DocumentationParser.Lines` is the one split, `Parse` takes lines, an `AssemblySource` carries its lines, and
`SourceFileCache` keeps each file's lines for the assembly, the analysis and the editor's parse of every root. The
arrays are shared, so nothing writes into them. Allocations fell by 101 MB.

### 6. The parser reads each line in place

After step 5 the documentation parser made 41.5% of all allocations, half in the assembler's `Also:` pass and half
in the editor's parse, and 28% of that in its main loop. Every line was copied by `TrimStart` for the `;;` test,
split into code and comment, and trimmed; then `IsConditional`, the type check and the scope tracker each copied its
first word and lowered the copy. Most lines document, open and close nothing. Now the loop finds where the comment
starts, reads the trimmed code and its first word as spans, and copies only a line that documents or changes
something. Words are compared by lowering one character at a time with `char.ToLowerInvariant`, which is exactly what
`ToLowerInvariant` does to a string; `OrdinalIgnoreCase` would not be, as it takes `ı` for `I` and `ſ` for `S`. The
scope tracker also reads a line's `.using` names without LINQ's `Concat`. Allocations fell by 104 MB.

### 7. The style checks read lines in place

The style checks, which run only in the editor's parse of a strict source, split and trimmed every line, looked for
characters outside ASCII with LINQ's `Any`, and for every comment line `CommentIndent` split and trimmed each line it
looked at and built a `HashSet` of columns. `DefinedName` copied the rest of every line of code. Now whitespace and the
comment's start are measured in place, a line's code is copied once when it has some, and a comment's columns are kept
on the stack. Comment bodies and sections tell indentation and blank lines without copies. Allocations fell by 24 MB;
the time, 11 ms more, is within the run's noise, as `Assemble`, which these checks barely touch, moved as much. The
SDK's sources are clean, so the dump has none of these warnings: `StyleLintTests` covers them.

### 8. Each source's `Also:` names read once

After step 7 the assembler's `Also:` pass made 20.6% of the allocations, in two equal halves: the preprocessor read
each source's `Also:` sections when it first processed it, so conditionals see historical names, and the compiler
read every source's again, each a full documentation parse. Every root repeated both for the files it shares. Now an
`AssemblySource` reads its names once and keeps them, `AssemblyAlsoNames.Collect` builds each assembly's names (and
its state for macro expansions) from them, and `SourceFileCache` gives every assembly in an index build the same
source for a path. This helps every assembly, not only the index. Allocations fell by 72 MB.

### 9. Macro names looked up by their text

After step 8 the preprocessor made 53% of the allocations, and macro expansion about 18%. `Substitute` copied every
macro and `.repeat` body line it read, as each is a slice of its file's text, then copied every identifier on it to
look it up among the parameters and locals, though most are neither. The main loop copied each line's operation to
look it up among the macros whenever a file defined any. Now names are looked up by their text with the
dictionaries' span lookup (`GetAlternateLookup<ReadOnlySpan<char>>`, .NET 9 and later), and a line is copied only
when a name in it is replaced. The source generator compiles this for netstandard2.0, where it still copies each name
to look it up. Allocations fell by 32 MB.

### 10. Each path upper-cased once

The analysis keys the `.using` order and the lines the assembler defined names on by the upper-cased full path, as
those compare paths without case, and upper-cased the path again for every statement, every symbol and every line it
checked for definitions in the text: about 3% of the allocations, in `ToUpperInvariant`. Each path is now upper-cased
once per analysis, as step 1 makes each full once. Allocations fell by 23 MB.

### 11. Lines split without replacing CRLF first

`DocumentationParser.Lines` replaced every CRLF with LF and then split at LF, so on a Windows checkout, where every
file has CRLF, each file was copied whole before it was split. It now splits at each LF and leaves out the one CR
before it, which gives the same lines; `LinesSplitAtLineFeedsLessOneCarriageReturn` pins it to the old expression for
lone CRs, CR CR LF, empty lines and terminators at the end. On Linux, where the files have LF, nothing was copied, so
CI's numbers would not show this. Allocations fell by 17 MB. The time, 21 ms more, is within the run's noise (24 ms
standard deviation); `Assemble` in the same run was 16 ms faster than at step 10.

### 12. Assembled lines passed over before matching

The analysis matched every line with a name in column 0 against `TextDefinition` (a generated regex), built the
match and read its groups, and only then passed over the line when the assembler had defined a name on it, as it had
on nearly every one: about 2% of the allocations, in `Match` and `GroupCollection`. It now passes over those lines
first, which the old order also did whatever the match found, so only lines in a branch the assembly did not take, or
in a source that does not assemble, are matched. The lines are kept by file, so passing over one is one integer
lookup: keyed by the path, as at first, every line hashed a long path and the run was slower.

Two runs after the change were noisy, at 879 and 851 ms, so the time was settled by alternating runs in this
worktree, each after a rebuild: 824 and 815 ms without the change, 813 and 812 ms with it. A first try at that from a
copy of the branch under the temporary folder was void, as reading the sources from there was far slower
(AppleSoft's root took 41 ms). The row is the first run with the change, which measured `Index` alone. Allocations
fell by 24 MB.

### 13. Less kept after the index is built

The GC's time follows what survives (see below), so this step cuts what the index keeps, not what it allocates.

- **The CPU map.** `DocumentationSet.ReadCpus` kept a (line, CPU) pair for every statement and for every line that
  expanded it: 689 arrays, 12.7 MB. It now keeps the first of each run of one CPU. `CpuAt`'s answer, the CPU of the
  last entry at or before a line, is the CPU of that entry's run, so it is the same.
- **The text function's closure.** C# gives the lambdas of one method one closure, so an analysis's text function
  shared the one that captures the build's `SourceFileCache`, and every analysis kept the whole cache. It now has
  its own. The heap walk shows this freed almost nothing yet: the same texts are also reached from the analysis's
  `Result`, whose share grew by what the function's lost.

Allocations and time did not change: ten alternating runs in this worktree, five each way, measured 809–852 ms
without the change and 805–995 ms with it, the first two with it noisy (standard deviation 73 and 112 ms) and the
last three 805, 844 and 815 ms. The row is the last of those.

## What the index keeps

A heap walk with ClrMD (`Microsoft.Diagnostics.Runtime`) after building the index as `SdkIndex` does and forcing full
collections. Each field's bytes count each object once, for the first field that reaches it.

| | After step 12 | After step 13 |
| --- | --- | --- |
| Live | 184 MB, 2.27 M objects | 171 MB, 2.27 M objects |
| On the large object heap | 15.8 MB | 8.4 MB |
| `Result` (the assembly's result) | 76 MB | 90 MB |
| `_documentation` | 53 MB | 40 MB |
| `_lines` | 23 MB | 23 MB |
| `_text` | 17 MB | 0 MB |
| `_definitions` | 11 MB | 11 MB |

By type after step 13: strings 68 MB; the source map's entries 26 MB, their operands 12 MB and locations 15 MB
(264,000 entries); documentation comments, topics, sections and entries about 16 MB; symbol sites about 8 MB.
Dropping the build's file cache frees nothing, as everything in it is also reached from the analyses.

## Where the time and memory go now

ETW traces of `Index` over every root, through filtrace's `Capture-BenchmarkTrace.ps1 -Profiler ETW` and
`filtrace classify --native-symbols`, at the baseline (run `20261124-183310-87def9d1`) and after step 12 (run
`20261125-041157-d3315fd5`). Profiling slows each run, so the times below are the profiled runs'; the progress table's
are not profiled. Allocations are BenchmarkDotNet's, exact either way.

| | Baseline | After step 12 |
| --- | --- | --- |
| Profiled time per index | 1,338 ms | 1,056 ms |
| The GC's share of CPU | 27.5% | 34.7% |
| **The GC's time per index** | **368 ms** | **366 ms** |
| **Everything else** | **970 ms** | **690 ms** (−29%) |
| Allocated | 1,389 MB | 641 MB |
| Collections per index: gen 0, gen 1 | 27, 19 | 12, 11 |

- **The GC costs what it did before the round.** Halving the allocations halved the collections, but nearly every
  collection is now a gen 1 one, and each costs twice as much: its time goes on what survives, not on what was
  allocated. In the GC, planning the compaction (`plan_phase`) is 28% of all CPU and moving the survivors
  (`relocate_phase`) 15%; marking is 8%, of which 6% is `mark_through_cards_for_uoh_objects`, large arrays on the
  large object heap that point at young objects.
- What survives is what the index keeps: every root's analysis, with its lines, statements and documentation, and
  during a build, the cache's texts and lines. Allocating less no longer cuts the GC's time; keeping less, or keeping
  it where the GC does not scan it again, would.
- **Our own work** fell 29% across the round. Of all CPU now, the preprocessor is 48% (macro expansion 24%, the ca65
  path 11%), the documentation 21%, the compiler 14%, the analysis's constructor 14% and reading the files 5%,
  each including its share of the GC.
- AppleSoft's root alone is 22.8% GC: one root keeps less.

## Candidates

- **What the analyses keep.** The source map is most of `Result`, about 55 MB, and the index's analyses read it
  for little after the build: hover's assembled bytes, the symbols and diagnostics. Trimming it needs a decision on
  what an SDK analysis must still answer. Strings, at 68 MB, may repeat across roots and could be shared.
- **Reading definitions** (B3, next): `Define` and `LabelKind`, for each documented definition.
- **A lighter `Also:` pass.** Now one parse per file per build, it still builds every comment whole (summary,
  remarks, every section and its entries, label kinds, usings) though it reads only six things and the `Also:`
  names. A reader for the assembler could skip the rest; about three quarters of the SDK's documented definitions
  have an `Also:` section, so skipping comments without one is not enough by itself.
- Spans have been enough so far, as the parser keeps only strings; Touki's `StringSegment` would pay where slices of a
  line are kept.
- **The documentation parsed twice.** The assembler's `Also:` pass parses without style checks and without the
  assembly's knowledge; the editor's with both. Sharing more than the lines needs care.
- **Growing lists and dictionaries** (next): statement lists and name maps grow by resizing.
- **The ca65 path's copies** (M2): `PrepareCa65` copies a line it expands, its operation and an upper-cased
  copy of that; `ExpandCa65Functions` copies every `.`-token.
- **The rest of macro expansion**: each invocation's argument list, parameter dictionary and a location for every
  body line, and `Emit`.
- **Shared files preprocessed per root.** AppleSoft and each PET BASIC root preprocess the shared BASIC sources again;
  the result depends on each root's definitions and branches.

Touki is already a dependency of the assembler. The source generator compiles the assembler's and documentation's
sources for netstandard2.0, so any Touki types they use are linked into it as sources.
