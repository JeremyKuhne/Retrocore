# Backlog: CPU core and machine loop speed

Status: **Latest exact IIe optimization round completed 2026-11-16**; results follow the MAME comparison below.
Both cores still match every per-cycle reference exactly. This
page tracks where the time goes, the headroom left, and every candidate measured, kept or rejected, so a later
round starts from evidence instead of repeating experiments.

How to measure, the exactness gate a change must pass, and the traps on this machine are in the
performance-testing skill's [Retrocore overlay](../../.claude/skills/performance-testing/overlay.md). Unless noted
otherwise, timings are from Release builds on the Ryzen 9 9950X3D, pinned to two physical cores, and report
the median of interleaved runs. A difference under about 3% is noise.

## Original 2026-11-09 baseline snapshot

| Core or loop | Workload | Before | Now | Host cycles per cycle | Floor with this design |
| --- | --- | --- | --- | --- | --- |
| Z80 `StepCycle` | ZEXDOC | ≈150 M T-states/s | 372 M | ≈15 | 676 M on predictable code |
| 6502 `StepCycle`, NMOS | Klaus functional test | 148 M cycles/s | 163 M | ≈34 | ≈190 M on NOPs |
| 6502 `StepCycle`, Rockwell 65C02 | Klaus functional test | 152 M cycles/s | 161 M | ≈35 | |
| IIe `StepCycle` (Enhanced) | AppleSoft `FOR` loop with `SIN` and `STR$` | 23.2 M cycles/s | 37.6 M | ≈150 | |
| Model I `StepCycle` | not measured yet | | | | |

For scale: a real Model I runs at 1.774 MHz and a IIe at 1.02 MHz, so the Z80 is about 210 times real time and
the IIe loop about 37 times. The best published cycle-stepped Z80, floooh's chips `z80.h`, takes about 5 host
cycles per T-state; an instruction-stepped one about 2.

"Floor with this design" is the same core on code it predicts perfectly (NOPs, HALT refetches). The gap between
the floor and the real workload is dispatch the branch predictor misses; the floor itself is fixed per-cycle
work. The Z80 splits about evenly between the two. The 6502 is nearly all fixed cost: NOPs run barely faster
than Klaus.

## The stepping convention

Every core and machine steps with `void StepCycle()` and builds its `ProcessorCycle` record only when asked,
through `LastCycle`; `FetchedOpcode` answers the debugger's per-cycle question without the record. Returning
and storing a record every cycle cost the Z80 about 30%. Keep new cores and loops on this shape.

## Z80

### Kept

| Change | Effect |
| --- | --- |
| `StepCycle` returns nothing; one activity byte per T-state, `LastCycle` built on request | 210 → 278 M (+32%) |
| Sample the input lines only when they change | +8% |
| `Tick` as one switch on (machine cycle kind << 3 \| T), each case one T-state's work | 275 → 372 M (+35%) |
| Unprefixed decode through a 256-entry group table (`Z80Decoding`) and one switch | +2.6%; kept as simpler than the x/y/z tree |
| `Run` loops `StepCycle` | simpler; see the rejected fast path |

### Rejected

| Candidate | Measured | Why rejected |
| --- | --- | --- |
| `Run` runs a whole machine cycle per step | 2.8× while records were built per T-state; equal (≈370) once `Tick` was a switch, +7% on predictable code | Its 40 lines, five tables and mid-cycle suspend logic no longer paid for themselves. |
| `Tick` driven by per-kind lookup tables (access, refresh, length) | +8–12% over the nested switch, still building records | Superseded by the single switch. |
| Inline `Tick` and `Refresh` | +3.6% | Below the threshold on its own; the single switch inlines anyway. |
| Fold decode into `Execute`'s switch | 0% | |
| Build the record with two 8-byte writes (`Unsafe.BitCast`) | +5% | Depends on the struct's layout; moot once records went. |
| Struct bus instead of class bus | 0% (150 vs 148) | |

### Headroom

| Candidate | Exact? | Estimate | Cost |
| --- | --- | --- | --- |
| Step programs: each opcode a fixed sequence of per-T-state steps in one generated switch (the floooh model) | Yes | 2–3× on real code | Effectively a new core; the generator becomes the source. The per-cycle SingleStep, FUSE and ZEXALL tests are the safety net. |
| Merge `Execute`'s operation and step dispatch into one jump per machine cycle | Yes | 10–20% | A large mechanical rewrite of `Execute`. |
| Instruction at once, then replay its bus activity per T-state | **No**: reads land up to 20 T-states early, WAIT cannot stretch an access already made, RESET and NMI cannot land mid-instruction | Over 1 G T-states/s | Breaks the core's exactness promise and the per-cycle tests. Not recommended. |

## 8080/8085 machine-cycle dispatch (2026-11-27)

**Kept:** Dispatch on the machine-cycle kind and T-state together, as the Z80 does. This removes the separate
`Transfer` dispatch without batching states: T1 still drives the address, T2 still samples READY, T3 still moves
the byte, and M1 still decodes on T4. Signal sampling and instruction execution are unchanged.

Release .NET 11.0.0 JIT on a Core Ultra 7 270K Plus, affinity `0x50`. Both arms used the same test DLL;
the control core was built from `c57ef9a9`. The child-only Kaypro `bootStart` rename unblocked both builds and is
not part of the optimization. Each row below is the median of three fresh-process interleaved runs per arm.

| Workload | States | Control | One dispatch | Elapsed reduction |
| --- | ---: | ---: | ---: | ---: |
| 8080EXM ALU register/memory excerpt | 1,073,741,824 | 4.030 s | 3.233 s | 19.8% |
| CPUTEST, complete | 255,655,936 (rounded) | 0.904 s | 0.749 s | 17.2% |
| 8080EXM `Exm8080TestPasses (2)`, complete | 20,156,960,768 (rounded) | 70.478 s | 54.205 s | 23.1% |

Full test throughput rose from 286.0 to 371.9 million states/s. All six full test runs reported CRC `cf762c86`,
`PASS!`, and `Tests complete`, with identical stdout. A separate run stepped the final chunk and found the first
HALT at exactly 20,156,960,148 states in both arms. Registers, RAM and console hashes matched there and in both
screening workloads.

Matched 1 ms ETW captures scoped to the exerciser recorded 74,149 → 55,987 CPU samples. `Transfer` accounted for
17.1% of control self-time; its opcode bus read and transfer bookkeeping dominated its source-line samples.
Tier 1 code showed that the test wrapper's apparent self-time included the inlined stepping loop. The new
loop jumps directly to the transfer work, with guarded bus inlining in both arms.

All 181 focused I8080 tests passed, including all 30 exerciser cases. The revised I/O trace test caught a
deliberate READY regression on both CPUs. Another 54 machine/debugger tests passed; 15 were inconclusive for
missing optional Altair and Model 100 fixtures. Both library TFMs built. The bundled Desktop PGO profile was
left unchanged: its Apple II workloads do not exercise this dispatch. JIT measurements do not establish
Native AOT performance.

## 6502

### Kept

| Change | Effect |
| --- | --- |
| `StepCycle` returns nothing, with `LastCycle` and `FetchedOpcode` | API only; the record is still built inside |
| Sample the input lines only when they change | +11% NMOS, +9% 65C02 |
| Resolve the variant's opcode table once, in the constructor | +10% on NOPs, +7% 65C02, flat on NMOS Klaus |

### Rejected

| Candidate | Measured | Why rejected |
| --- | --- | --- |
| Move RDY's whole-state `before` copy into a separate stall path | 0% | The JIT already avoided it. |
| Drop the per-cycle placeholder record (every running cycle reads or writes) | 0 to −5% | |
| Record bus activity as plain fields, build `LastCycle` on request (the Z80's +32%) | +1.5–3% | Below the threshold; the 6502 builds one record per access, not per call. |
| Tell `IOpcodeFetchBus` buses their fetches through a `static readonly` flag per bus type (2026-11-12, the Apple III) | −8% on a class bus in every read, −3.5% in the fetch alone | Class buses share one copy of the generic code, where the static is a lookup. Kept instead: an instance field holding the bus as `IOpcodeFetchBus`, checked only at the fetch, −0.6% (noise). |

### Headroom

The NOP floor is barely above Klaus, so dispatch misprediction is not the cost: each cycle runs about 34 host
cycles of fixed work through `StepCycle`, `Advance` (status, sequence and interrupt checks) and
`AdvanceInstruction` (mode and instruction tests to pick a handler).

| Candidate | Exact? | Estimate | Cost |
| --- | --- | --- | --- |
| Pick each instruction's handler once at the fetch, then one switch on (handler, phase) per cycle, as the Z80's `Tick` does | Yes | Uncertain; the Z80's equivalent gave +35% | A rewrite of `Advance`, `AdvanceInstruction` and `AdvanceMemory`. |
| Fold `StepCycle`, `Advance` and the instruction step into one method with the status and sequence checks hoisted | Yes | 10–20% | Medium; the per-cycle and Klaus tests cover it. |

## IIe machine loop

The machine's per-cycle devices cost far more than its 6502: at the start the loop ran at 23 M cycles/s while
the core alone ran at 150 M.

### Kept

| Change | Effect |
| --- | --- |
| Read the Mockingboard's AY levels only when an audio sink is attached and `MixMockingboard` is on | 22.8 → 30.8 M (+35%) |
| Work out the beam once per video scan, not twice | +5% |
| Synchronize the AYs with their VIAs only on a VIA access or reset, not every cycle (port B's control bits change only then) | +11.5% |

Sound in the debugger (the `sound` launch option) defaults to `speaker`: speaker-only mixing costs about 2%
(34.8 → 34.2 M), and `off` attaches no sink and costs nothing. Mixing the Mockingboard (`mockingboard`) costs
about 28% (24.9 M), almost all of it the two AYs' output worked out every cycle. Caching that output (below) is
the way to make Mockingboard sound cheaper.

### Rejected

| Candidate | Measured | Why rejected |
| --- | --- | --- |
| Run the 6502 over a struct wrapper of `Apple2Bus`, so the JIT specializes it | 0% | The shared generic code is not the cost; it would have changed a public type. |
| Count the beam's column and scanline incrementally instead of dividing `CycleCount` | 0% | Division by a constant is already a cheap multiply. |

### Headroom

The last profile: the inlined `Apple2Machine.Run` (device ticks, IRQ wiring) 57%, `Apple2Video.ScanCycle` 13%,
`Ay38910.Tick` 6%, the 6502 about 20%.

| Candidate | Exact? | Estimate | Cost |
| --- | --- | --- | --- |
| Lazy catch-up for the AYs and VIAs: advance them in bulk when read, written or due to interrupt | Yes, if each catch-up reproduces the per-cycle counters | Up to 7% | The VIA's IRQ line is polled every cycle, so it needs the time of its next interrupt. |
| Cache the AY output, recomputing it only when a tone, noise or envelope state or a register changes | Yes | Only with a sink attached (AppleSharp) | Small. |
| Video scan: skip the per-cycle capture in blanking, or batch a scanline | Yes, if the floating bus stays per cycle | Part of 13% | Medium. |

## Debug session at max speed

Measured 2026-11-09 with `speed: "max"` from the SDK ROM sources, reading the speed the frames report after a few
seconds, interleaved three times; Release, unpinned. The bare machines, stepping in a tight loop outside the
session, run the IIe at 32x its clock (32.7 M cycles/s) and the Model I at 35x (62.7 M cycles/s).

| Change | IIe at max | Model I at max | Notes |
| --- | --- | --- | --- |
| Before | 3.4-4.0x | 3.2-3.9x | |
| Sleep only when ahead of the clock | 5.0-5.9x | 4.7-5.7x | Each 10 ms slice slept `Task.Delay(1)`, which Windows rounds up to its 15.6 ms timer tick, so running idled about 60% of the time. |
| Count a line's cycles once per instruction, not per cycle | 12.2-14.4x | 18.9-21.2x | `Execute` hashed the line's path into `_lineCycles` twice a cycle. The same as an experiment with line counting removed. |
| Waiting requests end the slice | unchanged | unchanged | Without the sleep, running retook the lock before requests: a key went from 12 ms to 35 ms, pause from 6 ms to 20 ms. With requests counted and the slice ending for them, a key takes 0.4 ms and pause 3-6 ms. |

### Headroom

The session still runs the IIe at under half of the bare machine's speed. Per instruction it checks breakpoints,
BASIC stops and BRK (a set lookup by filter name), and observes the instruction: its source position, the call
stack, contracts. Per cycle it checks the beam breakpoints and data watches through the target interface. Profile
these before choosing.

| Candidate | Exact? | Estimate | Cost |
| --- | --- | --- | --- |
| Answer "is there a breakpoint here?" from a 64K-bit map (8 KB per address space), falling back to the set only on a hit | Yes | Unknown; likely more than any runtime upgrade | Small; the map must follow every breakpoint, BASIC stop and filter change. |

## .NET 11

Migration and initial measurements completed 2026-11-14. Runtime libraries target `net10.0;net11.0`;
executables and tests target only `net11.0`, using the .NET 11 SDK and C# 15. The build-only generator remains
`netstandard2.0`. Release AOT favors speed and requires x86-64-v3 on x64. The candidates below began as the
2026-11-12 investigation proposal; measured results follow.

### .NET 11 baseline, 2026-11-14

These are pre-emulator-optimization measurements on the 9950X3D, normal priority, affinity `0x50`.
Desktop uses its real host and visible window at Max; the AppleSoft program loops over `SIN` and `STR$`
and prints a progress dot after each 1,000 iterations. Sound and fast disk are off for this workload.

| Workload, millions of emulated cycles/s | JIT | ReadyToRun | Native AOT |
| --- | --- | --- | --- |
| Desktop host, idle BASIC, no window | 44.79 (44.17-45.13) | 43.87 (43.79-45.33) | 37.32 (36.84-37.41) |
| Desktop visible window, AppleSoft | 34.51 (34.39-34.69) | 36.87 (36.43-37.53) | 33.29 (31.92-33.56) |
| CPU only, original 76-cycle RAM mix, NMOS | 170.64 | 170.82 | 152.11 |
| CPU only, original 76-cycle RAM mix, WDC 65C02 | 165.28 | 166.05 | 151.01 |
| CPU only, original 76-cycle RAM mix, Rockwell 65C02 | 164.05 | 165.46 | 151.03 |

Values are medians of three samples, with observed min/max for Desktop. Each headless path runs
204,096,768 cycles after 500,000 settling cycles. Visible-window samples measure all cycles over the
actual settled interval (at least 15 seconds), rather than the old smoke runner's final one-second
speed snapshot. CPU samples execute 760,000,000 cycles, validating the exact end state outside timing.
JIT and R2R retain normal tiering/dynamic PGO; hot R2R methods may therefore be replaced by JIT code.
All publishes are self-contained win-x64. Startup is reported separately in the raw window logs.

`tools/Measure-IIePerformance.ps1` measures already-published builds without building alongside a timing.
Raw baseline results and isolated binaries are under `artifacts/iie-overnight`; the preserved .NET 10
reference is under its `baseline10` directory. The old .NET 10 visible-window figures were final-second
snapshots, so they are not interchangeable with these whole-interval measurements.

The migrated solution builds both library TFMs with no warnings. The .NET 11 tests initially pass
41 AppleSharp and 2,227 main-suite cases, with 187 optional/external cases skipped. Missing external
cases are not counted as correctness certification for changes to those subsystems.

### Overnight results, 2026-11-15

The final Windows x64 Desktop publish uses `OptimizationPreference=Speed`, x86-64-v3, and an instrumented
application profile collected from equal-cycle math/string, graphics, and active stereo Mockingboard
workloads. Its profile and provenance are in `src/Retrocore.Desktop/Profiles`. The profile converter is
built from pinned runtime v11.0.0 sources, not an unavailable NuGet tool. Reproduce with
`tools/Build-PgoTool.ps1` and `tools/Update-DesktopPgoCorpus.ps1`.

| Final emulated MHz, median of three processes | JIT | ReadyToRun | Native AOT |
| --- | --- | --- | --- |
| Desktop host, idle BASIC, no window | 50.46 (49.47-50.72) | 50.13 (49.79-50.53) | 51.63 (50.86-52.27) |
| Visible Desktop, AppleSoft math/string loop | 40.56 (38.77-40.72) | 40.76 (39.12-41.18) | 47.49 (45.71-47.76) |
| First visible frame, median milliseconds | 1,194 | 598 | 275 |

R2R retains normal tiering/dynamic PGO; hot methods can become JIT code. Its startup improvement is
clearer than its steady-state difference. The display's behavior changed during the session: early
callbacks were about 135 Hz; late callbacks were about 75-90 Hz with roughly 33 ms p99. The preserved
.NET 10 app shows the same late behavior. Do not attribute the entire early-to-late visible-window delta
to optimizations. Paired pilots below and matched headless work establish the individual wins.

Isolated headless controls, unchanged emulator algorithm, normal priority/affinity `0x50`:
.NET 10 original AOT 34.50 MHz; .NET 11 blended/base 35.53; .NET 11 speed/base 37.41
(one 34.70 outlier); .NET 11 speed/v3 37.36. Runtime migration alone is a small part of the final result.
Explicit host-native ISA gives no repeatable advantage over v3.

#### Kept

| Change | Evidence |
| --- | --- |
| Precompute immutable per-frame scan offsets, visible-cell indices, mixed-text regions | Three paired AOT product runs: 33.15/32.13/28.99 -> 36.75/36.16/35.65 MHz. No scan or floating-bus fetch skipped. Existing mixed-mode test rejects a deliberately wrong boundary. |
| Inline the 6502 public per-cycle wrapper | Paired actual Desktop gain about 5%. Full Native AOT BDN: 6.642 -> 5.784 ns NMOS, 6.652 -> 6.135 WDC, 6.649 -> 6.168 Rockwell; no allocation. BDN uses host-native ISA; shipping application pilots separately use v3. |
| Instrumented application PGO | Paired AOT product 37.29/38.13/37.26 -> 47.38/46.16/45.60 MHz. Graphics, speaker, and Mockingboard holdouts improve. Compiler input, nonempty edge/type data, and native execution verified. |
| Cache AY output, invalidate only on amplitude-relevant changes | Active stereo tone workload: about 17 -> 24 MHz, then about 23 -> 25 MHz after dependency-aware invalidation. Every counter/LFSR still advances at its original clock. 50 chip/audio tests, including long recordings, pass. New test rejects deliberately stale output. |
| Broaden PGO to graphics and active audio | No target regression; active audio improves further to about 26-27 MHz. Shipping profile generation uses the same reproducible corpus. |

#### Rejected

| Candidate | Why rejected |
| --- | --- |
| Cache the scanned flash phase by absolute clock block | -4.3%/-0.2% product results; reverted. |
| Cache exact rendered rows | -1.4%/+0.7%, no gain for about 0.5 MB extra state per machine; reverted. |
| Inline a separate already-captured-cycle guard | +2.2%/+1.4%/-0.7%, overlapping ranges; reverted. |
| Pack scan-position entries into uint | Consistently about 0.7% slower; keep named tuple mapping. |
| Outline complex Cxxx dispatch to inline RAM/ROM reads | Fresh-profile product +5.1%/+3.9%/-0.3%, below gate with overlap; reverted. |
| Cache opcode execution groups/store/modify flags | All vectors pass, but promising short results do not survive full BDN: NMOS about 3% slower, CMOS only 2-3% faster; product neutral/slightly worse. Reverted including private snapshot fields. |
| Value-type Apple II bus adapter | Fresh AOT+PGO product has no gain; reverted all public generic/API changes. |
| Ryzen-native ISA | -1.4%/+0.4%/-0.5%, no repeatable gain over v3. |

#### AppleWin: matched work, not the screenshot's score

An external, licensed AppleWin v1.32.0.0 harness uses its real CPU, paging, soft switches, and NTSC renderer.
It has no UI presentation or outer disk/audio scheduler. It remains under ignored artifacts, never copied
into MIT production sources.

For 256 finite pairs of genuine AppleSoft ROM expression evaluations (25,396,270 cycles), every implementation
produces the same completion count, result bytes, DONE marker, PC/registers, and full-memory hash. The CPU
status B bit is normalized because AppleWin synthesizes it as set. Six warm samples across three processes:

| Headless finite work | Emulated MHz |
| --- | --- |
| AppleWin CPU + NTSC | 49.70 |
| Retrocore JIT, complete IIe step/device path | 49.88 |
| Retrocore R2R, complete IIe step/device path | 50.82 |
| Retrocore AOT, complete IIe step/device path | 56.68 |

This is about a 14% AOT win for this workload, **not a blanket claim over AppleWin's stock UI or games**.
Our lookup/raster-history renderer and AppleWin's continuously generated composite NTSC pixels do different
video work. Existing Retrocore functionality and per-cycle observability are preserved.

The CPU-only synthetic program remains much faster in AppleWin: 1,300.78 MHz against Retrocore AOT 167.16,
JIT 161.96, R2R 160.88. Both run the same initial RAM and actual warmup/work cycles and end at the same state.
AppleWin dispatches complete instructions and adds their cycle costs; Retrocore executes each cycle, dummy
access, signal check, resumable phase, and observable bus record. Closing that gap requires a substantially
different exact core, not retargeting or dropping accuracy. This investigation explains the current gap;
it does not prove a future exact implementation cannot improve it.

Final validation: both library TFMs build with zero warnings; .NET 11 has 41 AppleSharp and 2,229 main tests
passed, 187 optional/external skips; all 7,660,000 6502 bus-vector cases and functional/signal gates pass.
Native validation across all cores/machines, 14 DAP scripts, extension compilation, and 111 extension tests
pass. Both old and new AOT keep 1.000x, type 42, and play idle speaker audio without underruns in a matched
late normal-speed check. ARM64's evaluated configuration has neither the x64 ISA nor the Windows profile;
other-OS runtime execution was not available locally.

### MAME follow-up, 2026-11-15 evening

Stock Windows x64 MAME 0.289 (`mame0289`), enhanced IIe (`apple2ee`, WDC W65C02), normal priority,
affinity `0x50`, no debugger, empty peripheral slots for the finite/synthetic tests, extended 80-column
auxiliary RAM. All four motherboard/keyboard/character ROM hashes match MAME's expected set. The same
preserved Retrocore and external AppleWin benchmark binaries above were rerun, not rebuilt or optimized.

| Same validated work, emulated MHz | MAME | Retrocore AOT | Retrocore R2R | Retrocore JIT | AppleWin CPU + NTSC |
| --- | --- | --- | --- | --- | --- |
| Finite AppleSoft, headless | 72.18 | 56.62 | 50.14 | 48.98 | 49.28 |
| Synthetic mix, complete machine path | 81.43 | 57.28 | 53.23 | 51.17 | 51.15 |

The finite input completes 256 pairs / 512 genuine ROM expression evaluations. MAME's fixed-duration
timer advances exactly 25,396,270 CPU cycles; its PC, A/X/Y/SP/P (normalizing only the status B convention)
and complete RAM/ROM-image hash match the prior reference. The synthetic input uses exactly 10,000,001
warmup and 1,000,000,001 measured cycles and also matches registers and RAM. The MAME driver uses WDC
rather than Retrocore's enhanced-IIe Rockwell variant; these workloads exercise their common instructions.

Five finite MAME processes were interleaved with five processes per Retrocore deployment mode (three
samples each) and five AppleWin samples. One initial MAME sample was 48.89 MHz; the other four were
71.95-73.61 MHz. Three separate confirmation runs were 70.21-71.79 MHz. The table retains the original
five-sample median, not a selectively trimmed result. Retrocore AOT's 15 samples range 53.05-57.83 MHz.
The synthetic MAME range is 81.31-81.68 MHz; AOT is 57.07-57.37 MHz. These are observed ranges, not
confidence intervals. MAME is about 25-27% faster on the finite program and 42% on the synthetic full-machine
path. No isolated MAME CPU-only result was measured; `-video none` is not a CPU-only core benchmark.

For MAME, a Lua driver installs the original image, resets CPU state outside timing, and uses the stock
`emu.osd_ticks` monotonic host clock. A completion-address tap discovers and validates finite completion
during an untimed warmup; it is removed before the retained fixed-cycle measurement. There are no Lua
per-instruction callbacks or debugger hooks in the timed work. The exact CPU counter is read only after
the timeslice ends, avoiding stale in-slice counters. Host-process startup and completion-loop tails are
not the performance denominator.

Headless MAME disables host presentation/audio, not emulated video: runtime render metadata confirms a
non-hidden target with one visible screen and no frameskipping, consistent with the tagged screen-update
source. Pixel-generation models still differ among the three emulators.

#### The actual DOS-booted Desktop scenario

The original SDK DOS disk and looping `SIN`/`STR$` program were also run unchanged. MAME settles for 15
emulated seconds, validates the title, then measures 600 emulated seconds and verifies progress dots.
Retrocore Desktop uses its full settled wall-clock measurement and the same disk, sound off and fast disk
off. Three runs were interleaved, with MAME's normal accelerated Windows D3D renderer, windowed 1120x768,
no vsync wait, and frameskip zero.

| Same running AppleSoft program | Median MHz | Observed range |
| --- | --- | --- |
| MAME, no host presentation | 76.79 | 76.25-76.83 |
| MAME, visible D3D window | 47.39 | 46.83-47.96 |
| Retrocore Desktop AOT, visible window | 47.87 | 47.68-48.02 |

The visible ranges overlap: **no demonstrated Desktop throughput winner**. The presentation policies are
not identical: MAME processes emulated screen frames while Retrocore publishes at the display's request
rate (about 120 callbacks/s here). A separate MAME GDI finite-work control reaches only 13.09 MHz; it is
not used as the primary UI comparison because it is not the normal accelerated renderer.

All commands, original Lua/PowerShell measurement drivers, binary/input identities, raw logs, expected
state exports, render checks, and aggregate JSON are retained under `artifacts/mame-performance`.
Third-party firmware and downloaded MAME source excerpts stay outside tracked source. No emulator code,
publish settings, or training workloads were changed, so the bundled PGO profile was not refreshed.

### Independent exact optimizations, 2026-11-15/16

These are original changes derived from Retrocore's existing implementations and tests. **No MAME
implementation, tables, templates, translations, or GPL dependencies were copied or introduced.** The stock
MAME executable was used again only as an external measurement subject.

The investigation retained four changes:

| Change | Mechanism and acceptance evidence |
| --- | --- |
| Direct 6502 continuations | Select a handler at opcode fetch and retain the next memory microstep in the CPU execution state, instead of repeatedly classifying the instruction and addressing phase. Branches, jumps, stack operations and data tails use their existing semantics. Full native CPU throughput improves 14-16%; snapshots, RDY, RESET, interrupts and every bus cycle remain observable. |
| Exact stopped Disk II fixed points | When two sequencer half clocks leave the complete sequencer state and latch unchanged, with the motor stopped, no pulse pending and no write-protection dependency, reuse that proven result. Controls, input changes, resets and half clocks invalidate it. Motor-off countdowns still advance every cycle. AOT Desktop pilot: 47.39 -> 53.96 MHz. |
| Deferred muted audio clock | With no sink, count discarded cycles modulo the CPU clock period. Reconcile the exact fractional sample phase before changing sinks; reset clears the debt. Both public tick overloads retain identical PCM after attachment. AOT Desktop pilot: 52.95 -> 58.14 MHz. |
| Small active-drive clock wrapper | Inline the fractional accumulator and enter the unchanged bit-cell loop only when at least one cell is due. Multiple cells per half clock, weak bits, writes, rotation and live media lookups remain unchanged. Active-disk Desktop pilot: 26.75 -> 28.84 MHz. |

No public API was removed or changed. There is no approximate mode, instruction-at-once bus replay,
skipped video scan or omitted device counter.

#### Final product measurements

Release, .NET 11.0.100, Windows x64, Ryzen 9 9950X3D, normal priority, affinity `0x50`.
Original and final executables are isolated and interleaved, with three processes per row. Original-source
controls are verified against the `cac72e8` Git blobs; original/final AOT each use freshly trained corpus PGO.
The visible math/string workload is the same DOS-booted AppleSoft program, Max speed, sound and fast drives
off. Each visible sample measures the complete settled interval, not a final-second snapshot.

| Emulated MHz, median (observed min-max) | Original | Final | Gain |
| --- | --- | --- | --- |
| Visible math/string, JIT | 39.17 (35.67-40.42) | 45.24 (44.06-48.61) | 15.5% |
| Visible math/string, R2R | 40.32 (36.50-40.65) | 49.70 (43.61-49.80) | 23.3% |
| Visible math/string, AOT | 45.26 (45.22-46.52) | 56.92 (56.88-57.64) | 25.7% |
| Visible graphics, AOT | 44.35 (42.92-44.64) | 55.03 (54.69-56.89) | 24.1% |
| Active stereo Mockingboard, AOT | 25.73 (25.56-25.93) | 29.40 (28.95-29.54) | 14.3% |
| Continuously rotating/read disk, AOT | 25.93 (25.88-26.08) | 29.53 (28.56-29.88) | 13.9% |
| Headless idle BASIC, JIT | 49.45 (49.30-50.36) | 50.78 (47.49-51.34) | inconclusive |
| Headless idle BASIC, R2R | 48.91 (48.64-50.18) | 50.76 (50.71-51.41) | 3.8% |
| Headless idle BASIC, AOT | 52.21 (51.87-52.36) | 55.26 (55.06-55.60) | 5.8% |

The active-disk scenario is a separate original AppleSoft program that continually enables the motor and
reads its latch; it cannot benefit from the stopped-controller shortcut. Graphics and Mockingboard are
broader product checks, not unseen training inputs. R2R retains normal tiering and dynamic PGO.

First-frame startup has no demonstrated improvement: JIT medians 1,314 -> 1,352 ms, R2R 628 -> 683 ms,
AOT 333 -> 341 ms. Ranges overlap substantially, including a 618 ms final AOT sample. These startup
measurements are separate from steady-state throughput and are not an optimization claim.

#### Core and exact-work controls

Full BenchmarkDotNet jobs, zero managed allocation per cycle:

| CPU variant | Original native ns/cycle | Final native ns/cycle | Original JIT ns/cycle | Final JIT ns/cycle |
| --- | --- | --- | --- | --- |
| NMOS 6502 | 5.757 | 4.966 | 4.934 | 4.213 |
| WDC 65C02 | 5.708 | 4.994 | 4.757 | 4.068 |
| Rockwell 65C02 | 5.681 | 4.991 | 4.777 | 4.141 |

The native core reaches about 200-201 million cycles/s instead of 174-176 million. At the reported
4.29 GHz nominal host clock, that is approximately 21.3-21.4 rather than 24.4-24.7 host cycles per
emulated cycle; actual turbo clock was not measured. BDN uses host-native x86-64-v4, while the shipping
Desktop remains x86-64-v3. These are separate measurements.

A mixed-toolchain BDN run encountered a concurrent assembly-weaver file lock; its incomplete rows are not
accepted. It also contained an original Rockwell native result of 9.129 ns that did not reproduce.
Complete serial jobs produced the table above. All initial and confirmation logs remain available.

The finite 512-expression AppleSoft image still executes exactly 25,396,270 cycles and produces the
same registers and complete memory hash
`3172094CE1F0539B318C99CE41806672AC3CE985A36F8E366F3C929853A5C50E`.
With application PGO explicitly wired to the native validation host, nine samples across three
interleaved processes improve from 56.51 to 59.91 MHz (ranges 55.05-57.49 and 57.63-60.89).
The ordinary validation host does not automatically consume Desktop PGO; its separate unprofiled
control improves 44.66 -> 48.39 MHz and must not be mixed with profiled figures.

An original ROM-resident bank-switch stress image also matches its complete 59,000,000-cycle budget,
PC/registers and memory hash. Final unprofiled throughput is 51.29 MHz against 47.02, avoiding the
page-cache regression described below.

#### Fresh visible MAME check

Three more paired processes use the same unchanged stock MAME 0.289 executable and original Lua
measurement driver, same disk, D3D window and presentation settings as the previous comparison.
MAME measures 613,080,000 actual CPU cycles per run after boot; Retrocore measures its full settled
15-second window interval. Both programs verify title and continued progress.

| Same DOS-booted math/string program | Median MHz | Observed range |
| --- | --- | --- |
| MAME, visible D3D | 53.76 | 53.63-53.88 |
| Final Retrocore Desktop AOT | 57.83 | 57.45-59.04 |

Retrocore is about 7.6% faster in this paired visible scenario. This is **not a blanket CPU, headless,
game or video-accuracy win**: rendering models and presentation policies still differ. The newly measured
MAME rate also differs from the earlier evening's 47.39 MHz, illustrating why fresh paired controls matter.
This round does not establish a headless win over MAME.

#### Rejected alternatives

| Experiment | Why not retained |
| --- | --- |
| Flatten only the existing addressing-mode/phase switch | All 98 original CPU gates pass, but only 1-3% core improvement. |
| Memory-only continuations and redundant-phase removal | Marginal product gain; superseded by complete direct handlers, not retained as parallel implementations. |
| Put fetch/system sequences through the continuation jump table too | All expanded CPU tests pass, but the core becomes 2-3% slower than the better continuation structure. |
| Combine opcode metadata and continuation into one tuple table | Correct, but native throughput regresses; retain separate arrays. |
| Cache every low-RAM page's read/write bank | Promising normal Desktop pilot, but rapid bank switching falls from about 47 to 11 MHz because each switch refreshes hundreds of references. Rejected despite the favorable primary workload. |
| Compact bank bitmaps or selectively updated bank references | Avoid the severe switch regression but add no repeatable >=5% product benefit; compact references finish only 2.2% ahead with overlapping ranges. Original bus restored. |
| Resolve video fetch bases/masks when switches change | Video/banking tests pass, but fresh-PGO Desktop drops roughly 47-49 -> 40-41 MHz. Reverted exactly. |
| Cache drive bit intervals, reuse track length and avoid common-case modulo/no-op write stores | Final five-pair active-disk gain is only 4.2%, with overlap. Reverted all arithmetic/state changes; only the separately validated small clock wrapper remains. |
| Resolve the immutable high-ROM view at card/switch changes | Banking tests and exact finite output pass; cheap native screen gains only about 1.3%. Reverted before expensive profiling or product confirmation. |

Stop here for this round: additional changes would revisit rejected mechanisms or need a larger
opcode-specific/generated-core or event-driven-device redesign. Those remain research directions,
not measured gains or claims that exact emulation has reached a fundamental limit.

#### Correctness, PGO and reproduction

The solution builds both library TFMs with zero warnings. .NET 11 has **2,313 main-suite plus 41 AppleSharp
tests passed**, with 187 optional/external cases skipped, not certified. All 7,660,000 processor bus vectors
and functional/signal gates pass. Native validation passes for all cores/machines supported by its host.
The expanded CPU/audio/controller gate has 154 passing cases and no skips. New tests reject deliberate
faults in RESET continuation clearing, unlatched write protection, muted sample phase and multi-cell
disk-clock handling.

Fourteen live DAP drivers complete; optional Altair BASIC images are absent. The Pascal driver has no
available disk fixture and is not certified. Normal-speed original/final speaker checks preserve typing
`PRINT 6*7`, approximately 1.000x clock rate and open audio. All three final runs have zero underruns;
two original checks report one startup underrun, so no universal zero-underrun baseline is claimed.

The shipping binary profile **and its generated provenance were refreshed together** with the existing
math/graphics/Mockingboard corpus scripts. Instrumented-method counts are 777/783/801. Actual compiler
arguments contain the shipping `--mibc`, `--Ot` and `--instruction-set:x86-64-v3`. The same final source
with old/new profiles measures 54.93 -> 59.15 MHz in three separate paired Desktop runs, supporting
the refresh rather than merely assuming the old data remains effective.

Raw logs, blob-verified original-source controls, isolated publishes, native compiler response files,
instrumented profiles, negative controls and machine-readable final measurements are under
`artifacts/independent-iie`. The temporary MSBuild control imports substitute preserved original
sources only when explicitly requested; ordinary builds use the final source tree. No shipping build
settings or training workloads were changed. No commits or pull requests were created in this round.

### Candidates

| Candidate | Exact? | Estimate | Cost |
| --- | --- | --- | --- |
| Retarget to `net11.0` (`TargetFramework` in `Directory.Build.props`, the SDK in `global.json`) and rerun every row of "Where things stand" | Yes | Unknown; the cores' big switches, sealed generic buses and lack of virtual calls are the shape each JIT release improves | One line each, plus CI's SDK. Measure net10.0 and net11.0 interleaved on the same build of the benchmarks. |
| AppleSharp under Native AOT: compare against the same loop under the JIT (tiered, with dynamic PGO) | Yes | If the JIT wins clearly, the gap is the PGO that AOT lacks | Measurement only. If it matters, try static PGO (a recorded `.mibc` profile) in the AOT build. |
| Native AOT `IlcInstructionSet` above the x64 baseline (for example `x86-x64-v3`), for AppleSharp and the native debug host | Yes | Small; flags and video are bit twiddling that BMI and LZCNT can shorten | One property; the binaries then refuse to start on older CPUs, so it needs a decision on supported hardware. |
| Video: write whole 32-bit pixels and look up the 16-colour palette with `Vector128.Shuffle` | Yes | Several times faster rendering, but rendering is once per displayed frame (about 107K pixels at 60 Hz), a rounding error today | Small. Worth it only if a frame is rendered per emulated frame (recording, fast-forward previews). |
| Disk: find sync marks and address fields in nibble tracks with `SearchValues` and `IndexOf` (already vectorized) | Yes | Unknown | Profile the Disk II path first (see "Not measured yet"). |

### Ruled out

| Candidate | Why |
| --- | --- |
| `System.Numerics.Tensors` (`Tensor<T>`, `TensorPrimitives`) | Both pay off only when one operation runs over many independent values. The cores and the machine loop are a chain of cycles, each depending on the last. Audio is built up per cycle through a recursive high-pass filter, leaving only the final conversion of a 512-sample buffer, which costs nothing. Video is covered by the hand-written SIMD row above. The package would also grow the AOT binaries for no gain. |

None of these replace the design changes under each core's Headroom (Z80 step programs, the 6502's per-fetch
handler, the IIe's lazy AY and VIA catch-up): those are where the large gains are, on any runtime.

## Not measured yet

- The Model I's loop (`Trs80Machine.StepCycle`: the Z80 plus `Trs80Bus.Tick` per T-state).
- The Disk II sequencer with a disk in the drive: two sequencer steps per CPU cycle.
