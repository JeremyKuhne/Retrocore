# Retrocore overlay

Repository bindings for the performance-testing skill. Read this before the core pages; where they
differ, this page wins for Retrocore.

## Bindings

| Core placeholder | Retrocore |
| --- | --- |
| `<root>.perf` | `tests/Retrocore.Perf` (BenchmarkDotNet 0.16.0-preview.2, `BenchmarkSwitcher`) |
| `<tfm>` | `net11.0` only for tests and executable benchmark hosts. Runtime libraries also build for `net10.0`. |
| Trace analyzer | `filtrace` (global tool `klutzyninja.filtrace`); see [Profiling](#profiling) |
| Recorded results | `tests/Retrocore.Perf/*Results.csv` (one row per benchmark, with the report path) |
| Related skills | None vendored. Skip the core's framework-JIT and scratch-buffer links: Retrocore has no .NET Framework target. |

```powershell
dotnet run -c Release --project tests/Retrocore.Perf -- --filter *Z80Benchmarks*
```

Use the .NET 11 SDK and C# 15. Compare JIT, published ReadyToRun, and Native AOT separately; report startup,
warmup, and settled throughput. R2R normally permits tiered JIT replacement. Release AOT favors speed and
defaults to x86-64-v3 on x64; record explicit instruction-set overrides in every result.
BenchmarkDotNet 0.16.0-preview.2 is used because 0.15.8 cannot validate .NET 11 Native AOT jobs, even with an
explicit custom toolchain. Use the supported runtime token for a Native AOT benchmark:

```powershell
dotnet run -c Release --project tests/Retrocore.Perf -- --runtimes nativeaot11.0 --filter *ProcessorBenchmarks* --affinity 80
```

The CPU benchmarks are `ProcessorBenchmarks` and `ProcessorTraceBenchmarks` (6502, with `RamBus` and
`CpuWorkload`) and `Z80Benchmarks` (with `Z80RamBus`). Their workloads validate the end state in
`[GlobalCleanup]`; keep that when adding one.

## Emulator cores: the exactness gate

A core change that is faster but not exact is a regression. Before reporting any speedup in
`Retrocore.Cpu.*` or a machine's step loop, all of these must pass in Release:

| Core | Tests |
| --- | --- |
| Z80 | `Z80ConformanceTests` (SingleStepTests, every T-state's bus activity), `Z80FuseTests`, `Z80CoreTests`, `Z80ExerciserTests` (ZEXALL by test; ZEXDOC with `RETROCORE_ZEXDOC`) |
| 6502 | `ProcessorConformanceTests` (SingleStepTests per cycle), `ProcessorFunctionalTests` (Klaus Dormann), `ProcessorTests`, `ProcessorSignalTests` |
| Machines | The `Trs80*` classes (NewDOS boots included), the Level II tests in `BasicConformanceTests` and `BasicVariableTests`, `DebugCallStackTests`, and the IIe tests the change touches |

The SingleStepTests, Klaus and ZEXALL fixtures live outside the repo (`tools/Fetch-ProcessorTests.ps1`,
`tools/Fetch-Z80Tests.ps1`); without them those tests report Inconclusive, which is not a pass.

Verify the gate catches what you changed: break the new code on purpose once (skip a refresh, drop a
line change) and confirm a test fails, then restore it.

## Emulator cores: the stepping convention

Every core (`Processor<TBus>`, `Z80Processor<TBus>`) and machine (`IMachine`, `Apple2Machine`,
`Trs80Machine`) steps with `void StepCycle()`, and reports the bus activity only on request through
`LastCycle`, with a cheap `FetchedOpcode` on the cores for instruction stepping. Keep hot loops on that
shape: returning or storing a `ProcessorCycle` every cycle cost the Z80 about 30%. Tests that check
each cycle use the `NextCycle()` helpers in `ProcessorCycleExtensions`.

## Emulator cores: the metric

Report emulated cycles per second (T-states/s for the Z80), not microseconds per call, plus host
cycles per emulated cycle (host clock / rate). Use a fixed, real workload:

- **Z80:** ZEXDOC from the fixture cache, loaded at `$0100` under the minimal CP/M of
  `Z80ExerciserTests.Run`. A full run is 46,734,975,782 T-states (an independent published
  count matches), so a run of a few hundred million T-states is a stable sample.
- **Split misprediction from fixed cost:** also time a perfectly predictable program (memory of NOPs
  ending in HALT). If it is much faster than ZEXDOC, the cost is dispatch that mispredicts on the
  instruction mix; if not, it is per-step bookkeeping.

The current numbers, the headroom and every candidate tried, kept or rejected, are in
[docs/backlog/CoreOptimization.md](../../../docs/backlog/CoreOptimization.md). Add to it as the experiment ledger
when you try something, and quote the before number you measured yourself, on this machine, in the same harness.
For the 6502, use Klaus's `6502_functional_test.bin` below about 90 M cycles (it then sits in its success loop),
and for a machine loop, the IIe running an AppleSoft program.

## Measuring on this machine

The development machine is a Ryzen 9 9950X3D. Its two core complexes differ (one has the extra cache
and lower clocks), so an unpinned run varies by about 10% depending on where Windows places it.

- **Pin to two physical cores at normal priority:** `Process.GetCurrentProcess().ProcessorAffinity =
  (IntPtr)0x50`. Do **not** pin to one core at high priority: the background thread that recompiles
  hot methods to optimized tier-1 code starves, and you measure unoptimized code (25 M against
  280 M T-states/s in one run).
- **A/B by interleaving:** build each variant into its own folder, run them alternately three times,
  and compare medians. Treat a difference under about 3%, or ranges that overlap, as no difference.
- **Keep the machine quiet:** no test run or build alongside a measurement.
- **A build that failed did not replace the binaries.** Check for `0 Error(s)` before trusting a
  number; the analyzers fail builds on formatting.
- For fast throughput loops, a small console harness referencing the project is fine for
  screening. Confirm the chosen change with the BenchmarkDotNet benchmark before recording it.

The measurement and profile-refresh scripts pin to `0x50` only when both logical processors are in the
inherited affinity; otherwise they retain the inherited mask. Desktop benchmark output and numeric command
arguments use invariant culture. Run `.\tools\Test-IIePerformance.ps1` to check measurement parsing,
odd/even medians, and the affinity fallback without running benchmarks.

## Test-suite time

`dotnet test` without `-c` is Debug, which is unoptimized: CPU-heavy tests run about 5 times slower
(ZEXALL took 40 minutes in Debug and under 3 in Release, before it was split into one case per test). When someone asks why the suite is slow:

- Compare durations only at the same configuration, and say which.
- Get per-test durations with `--logger "trx;LogFileName=run.trx"` and rank the `UnitTestResult`
  durations; tests run in parallel by method (`GlobalUsings.cs`), so the suite takes as long as its
  longest test, not the sum.
- A test that runs alone takes less time than the same test in a full run, which competes for cores.

## Profiling

Capture with `dotnet-trace` (EventPipe) and analyze with `filtrace`:

```powershell
dotnet-trace collect -o run.nettrace -- dotnet path\to\harness.dll <args>
filtrace info run.nettrace            # first: sample count and symbol coverage
filtrace cpu run.nettrace             # self-time by method
filtrace tree run.nettrace            # the hot path, top down
filtrace lines run.nettrace           # hottest source lines of the scoped methods
```

- Check `info` before trusting a ranking: a few hundred samples from a run of several seconds means
  the capture is thin, so rank only large shares.
- Inlined methods vanish into their callers. When a large share lands on the benchmark loop itself,
  the inlined step path (for example `StepCycle` and `Tick`) is in it.
- For the generated code, use `DOTNET_JitDisasm="Tick"` (or `"*Bench*"` for a local function) with
  `DOTNET_JitStdOutFile`, and read the `Tier1` or `Tier1-OSR` listing, not the tier-0 ones.

A profile forms the hypothesis; only an interleaved A/B decides it. Several plausible explanations
for the Z80's cost (call overhead, store-forwarding stalls on the cycle record) measured smaller than
the profile suggested. Report the measured effect, and correct an earlier claim when the
measurement contradicts it.

## Native AOT PGO maintenance

Windows x64 Release Desktop publishing consumes
[`Apple2-win-x64-net11.mibc`](../../../src/Retrocore.Desktop/Profiles/Apple2-win-x64-net11.mibc).
The adjacent JSON is provenance, not compiler input. The project selects the profile through `MibcFile`;
other runtime identifiers do not implicitly consume this Windows profile.

### When to refresh

Assess a refresh when changes materially affect:

- Hot 6502 instruction dispatch, control flow, helpers, generic instantiations, or bus call targets.
- Apple II memory mapping, scanner, device/audio stepping, or Desktop/debug-host execution paths.
- Method/type identities used by those paths, which can stop old profile entries matching.
- The .NET SDK, runtime/ILCompiler version, AOT configuration, or target OS/architecture.
- The representative workload mix or a demonstrated profile-related performance regression.

An ordinary rebuild does not require retraining. Neither do documentation, formatting, or changes outside
the profiled paths unless they alter relevant generated code or workload behavior. Profiles are optimization
feedback, not an exact-binary cache; stale data can become unused or unrepresentative without changing
program semantics. Do not equate successful compilation with an effective profile.

### How to refresh

On Windows x64, from the repository root, build the converter if it is not already available:

```powershell
.\tools\Build-PgoTool.ps1
.\tools\Update-DesktopPgoCorpus.ps1 -PgoTool .\artifacts\pgo-tool\bin\dotnet-pgo.exe -OutputDirectory .\artifacts\pgo-training-new
```

Use a new output directory. The scripts use pinned official runtime sources, train JIT builds on equal-cycle
math/string, graphics, and active stereo Mockingboard workloads, and merge their profiles. Keep this corpus
representative rather than tuning it to one favorable benchmark. Do not hand-edit the binary or provenance;
retain both generated files together in `src/Retrocore.Desktop/Profiles`.

The instrumented trace needs `Microsoft-Windows-DotNETRuntime:0x1E000080018:5`: level 4 was insufficient
for JIT-start events in the validated .NET 11 workflow. A CPU-sampling trace alone is not instrumented PGO.
The generator must find nonzero edge/block counts before replacing the profile.

### Acceptance and handoff

1. Retain the previous profile/build and compare old/new profiles against the same changed source and settings.
   `-p:RetrocorePgoProfile=` explicitly disables application PGO for an additional control.
2. Verify the actual native compiler arguments include the intended `--mibc`, speed preference, and ISA.
   Do not accidentally apply the Windows profile or x64 baseline to ARM64/other-OS publishes.
3. Use uninstrumented, interleaved Release application runs for performance acceptance. Separate JIT, R2R,
   AOT, startup, and steady-state results; do not benchmark the trace collector's training run.
4. Run the relevant exactness gates above on .NET 11 and validate native execution, including graphics,
   disk, speaker/Mockingboard, and normal-speed input/audio behavior. Missing fixtures are not passes.
   Build both library TFMs; do not add a .NET 10 test run.
5. Accept only reproducible product gains without correctness/functionality or important workload regressions.
   Record retained/rejected evidence in the optimization ledger and state the profile refresh decision in
   the change summary. If tooling, fixtures, or a suitable machine are unavailable, preserve the profile
   and report what was not validated rather than claiming it is current.
