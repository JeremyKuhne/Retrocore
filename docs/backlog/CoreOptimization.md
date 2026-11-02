# Backlog: CPU core and machine loop speed

Status: **Z80 and 6502 rounds done** (2026-11-09). Both cores still match every per-cycle reference exactly. This
page tracks where the time goes, the headroom left, and every candidate measured, kept or rejected, so a later
round starts from evidence instead of repeating experiments.

How to measure, the exactness gate a change must pass, and the traps on this machine are in the
performance-testing skill's [Retrocore overlay](../../.claude/skills/performance-testing/overlay.md). Every number
here is Release, on the Ryzen 9 9950X3D, pinned to two physical cores, as the median of interleaved runs. A
difference under about 3% is noise.

## Where things stand

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

## Not measured yet

- The Model I's loop (`Trs80Machine.StepCycle`: the Z80 plus `Trs80Bus.Tick` per T-state).
- The Disk II sequencer with a disk in the drive: two sequencer steps per CPU cycle.
