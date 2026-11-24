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

AppleSoft's root alone: 50.1 ms and 67.7 MB at the baseline, 37.4 ms and 48.5 MB after step 4.

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

## Where the time and memory go now

From the traces before steps 3 and 4 (ETW) and after step 3 (allocations):

- **The GC is 27.5% of CPU**, nearly all of it compacting: objects live long enough to survive the first
  generation. Every allocation removed saves its GC work too.
- **The documentation parser makes about half the allocations.** It runs twice for each file: once in the assembler,
  for the `Also:` names (`AssemblyAlsoNames.Collect`), and once for the editor (`DocumentationSet.Create`).
- **The preprocessor** makes about a third, and the compiler about a fifth.

## Candidates

- **Lines split up to four times.** The preprocessor, the assembler's `Also:` parse, `SourceText.Lines` for the
  analysis, and the editor's parse each split the same text into lines, the last after `SourceAnalysis` joins its
  lines back together to call it: about 15% of allocations. One split per file shared across them, perhaps as Touki
  `StringSegment`s over the text, would remove most of it.
- **Repeated `Split` of a line** in the parser's main loop, and substrings in `Define`, `ScopeTracker`, `Body`,
  `CommentIndent` and `Style`, which spans or `StringSegment`s could avoid.
- **The documentation parsed twice.** The assembler's `Also:` pass parses without style checks and without the
  assembly's knowledge; the editor's with both. Sharing more than the lines needs care.
- **The preprocessor's macro expansion and string building** (`StringBuilder.ToString`, `Substitute`, the ca65
  functions).
- **Shared files preprocessed per root.** AppleSoft and each PET BASIC root preprocess the shared BASIC sources again;
  the result depends on each root's definitions and branches.

Touki is already a dependency of the assembler. The source generator compiles the assembler's and documentation's
sources for netstandard2.0, so any Touki types they use are linked into it as sources.
