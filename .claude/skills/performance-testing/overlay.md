# Retrocore overlay

Repository bindings for the performance-testing skill. Read this before the core pages; where they
differ, this page wins for Retrocore.

## Bindings

| Core placeholder | Retrocore |
| --- | --- |
| `<root>.perf` | `tests/Retrocore.Perf` (BenchmarkDotNet 0.15.8, `BenchmarkSwitcher`) |
| `<tfm>` | `net10.0` only. Never pass a second target. |
| Trace analyzer | `filtrace` (global tool `klutzyninja.filtrace`); see [Profiling](#profiling) |
| Recorded results | `tests/Retrocore.Perf/*Results.csv` (one row per benchmark, with the report path) |
| Related skills | None vendored. Skip the core's framework-JIT and scratch-buffer links: Retrocore has no .NET Framework target. |

```powershell
dotnet run -c Release --project tests/Retrocore.Perf -- --filter *Z80Benchmarks*
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
