# Backlog: cheaper running memory events

Status: **measured 2026-11-22; not recommended as designed.** The running memory check costs under 1% of wall time
even with four editors that have each read all 64K. Dirty-page tracking would put a branch on every machine's write
path and need a profile assessment, which that gain does not justify. A smaller, host-only change ([sharing the
hash](#recommendation)) is worth doing if the cost of stepping with several editors becomes a complaint.

[PR #85](https://github.com/JeremyKuhne/Retrocore/pull/85) gave each memory editor its own tracked ranges. This plan
asks whether the check that turns those ranges into DAP `memory` events should cost in proportion to what
**changed** rather than what is **tracked**. It answers with measurements first, then the design it would take.

## What there is

- `Track` (`src/Retrocore.Debug/DebugSession.Memory.cs`) records each view's reads. A view is a memory reference plus
  an optional Retrocore Memory `subscriber`. Views without a subscriber are limited to 32 (least recently used);
  subscribed views last until `retro/memory/unsubscribe`.
- `MemoryView.Ranges` (`DebugSession.MemoryView.cs`) is a sorted, disjoint list of the offsets read. It only grows,
  because an editor caches pages it scrolled away from ([Memory.md](../Memory.md)).
- `NotifyMemory` hashes every view: FNV-1a over `MemoryByte(bank, address)`, which is `Target.Peek` or
  `bank.Peek`, a delegate, for every byte of every range. It then sends one `memory` event per reference whose hash
  changed, except the reference that just wrote (`except`).
- It runs from `NotifyRunningMemory` every 8th running frame, and directly after `writeMemory`, freezes, BASIC
  variable edits, BASIC's return to its prompt, resets, card changes and **every stop**, so every step.

The cost is the tracked bytes summed over all views. Four editors on `0x0000` hash the same 64K four times.

## Measurements

### How

- **Build.** This container has no .NET 11 SDK: the host that serves it is blocked, and apt has only 10.0.115. The
  measurement therefore ran on a scratch copy of `main` at 396179b. In that copy, `net11.0` was retargeted to
  `net10.0`, C# 15's collection-expression arguments (`[with(comparer)]`, 183 uses) were rewritten as the
  equivalent `new(comparer)` constructors, and the build used `-p:LangVersion=preview` with Release
  configuration. JIT, not Native AOT, on the .NET 10 runtime. None of that copy is in this branch.
- **Probe.** The copy wraps `NotifyMemory` in a `Stopwatch`, counts `MemoryByte` calls, and with
  `RETROCORE_MEMPROBE=1` writes one stderr line per check. A Node driver over `tools/DapClient.mjs` launches the
  machine stopped and opens *N* subscribed editors. Each one reads all 64K through `retro/memory/read` in 4K
  pieces, as scrolling the whole space does. The driver then continues for 10 s and pauses. The first check is
  dropped as warmup.
- **Machine.** A 4-vCPU Linux cloud container, unpinned, not the Ryzen development machine that
  [CoreOptimization.md](CoreOptimization.md) uses. Absolute speeds are lower here; the share of wall time is the
  number to compare.
- **Machines.** The TRS-80 Model I from the SDK's ROM sources, running `sample/trs80/hello.asm`. The enhanced IIe
  and the II Plus from the SDK's ROM sources: `RETROCORE_IIE_ROMS` is not set here, so the IIe was **not** measured
  on Apple's ROM dumps. Neither Apple II had a disk, so both sat in the firmware's boot loop.
- **Share of wall time** is the summed check time divided by the time between the first and last check. Checks came
  every 290-356 ms, which is 8 frames of at least 33 ms each plus the slice that overran.

### Running

Each entry gives the median microseconds per check. Max-speed entries list three runs; 1x entries list one.
`peeks` is the number of `MemoryByte` calls in one check.

| Machine | Editors | Speed | Peeks | µs per check (median) | Share of wall time |
| --- | --- | --- | --- | --- | --- |
| Model I | 0 | max | 0 | 11, 12, 13 | 0.01% |
| Model I | 1 | max | 65,536 | 390, 396, 511 | 0.16-0.19% |
| Model I | 4 | max | 262,144 | 985, 1149, 1282 | 0.51-0.57% |
| Model I | 4 | 1x | 262,144 | 1394 | 0.62% |
| IIe | 0 | max | 0 | 17, 17, 18 | 0.01% |
| IIe | 1 | max | 65,536 | 472, 537, 598 | 0.14-0.22% |
| IIe | 4 | max | 262,144 | 1320, 1470, 1578 | 0.54-0.68% |
| IIe | 4 | 1x | 262,144 | 1771 | 0.80% |
| IIe, 4 editors on `0x0000`, `main:`, `aux:`, `bank1:0xD000` | 4 | max | 208,896 | 1743, 2139 | 0.80-0.83% |
| II Plus | 0 | max | 0 | 19, 20, 21 | 0.01% |
| II Plus | 1 | max | 65,536 | 537, 617, 665 | 0.23-0.24% |
| II Plus | 4 | max | 262,144 | 1540, 1725, 1816 | 0.55-0.73% |
| II Plus | 4 | 1x | 262,144 | 1480 | 0.71% |

- A byte costs about 4-10 ns through `Target.Peek` and about 8-10 ns through a bank's `Peek` delegate. The
  bank-view row reads fewer bytes but takes longer.
- The worst check in a run took 6-16 ms with four editors, against 0.05-0.6 ms with none. That is one pause of the
  run loop, under its lock. It is most likely the check's code before tiering, since the slowest check in each run
  came early, but this probe does not prove that.
- Emulated speed at max varied by ±15% between runs with the same settings (the Model I with no editors: 26.9, 33.8
  and 35.4 MHz). That noise hides a difference under 1%, so speed is not used as evidence either way.

### Stepping

`NotifyMemory` runs at every stop, so stepping pays for it once per step. There were 200 instruction steps (`stepIn`)
after 20 warmup steps, timed from request to `stopped` event.

| Machine | Editors | Round trip per step | `NotifyMemory` (median) |
| --- | --- | --- | --- |
| Model I | 0 | 3.08 ms | 4 µs |
| Model I | 4 | 4.03 ms | 1412 µs |
| IIe | 0 | 9.65 ms | 5 µs |
| IIe | 4 | 12.09 ms | 3949 µs |

Here the check is about a third of the host's time per step. VS Code's own work per stop, which this harness does
not include, comes on top of both rows.

### What this says

- **Running:** under 1% of wall time in every case, and 0.8% at worst. That meets the plan's bar for not doing the
  work. It is not "well under" 1%, though, and it is linear: eight editors over all memory would be about 1.6%.
- **Stepping:** it adds 1-4 ms per step with four full editors. This is the more visible cost. It also has the
  simplest fix, because nothing changes between two hashes of the same byte within one check.
- **Overlap is the main waste.** In both workloads three of the four hashes per byte are repeats.

## Where memory changes

The reason hashing exists is that Peek's value changes in ways no single write hook sees. Every target's `Peek` is
its bus's `Peek`. Every CPU core writes through its bus's `Write` (`M6502/Processor.cs`, `Z80Processor.cs`,
`M6809Processor.cs`, `I8080Processor.cs`), so each machine has one CPU choke point. Nothing in the code keeps a
memory generation or dirty counter. The nearest precedent is the Apple II's `Bus.CardChanges`, which invalidates the
bank list.

| Machine | CPU write choke point | Mapping changes without a RAM write | Device or DMA writes | I/O whose Peek changes by itself | Writers that bypass `Write` |
| --- | --- | --- | --- | --- | --- |
| Apple-1 | `Apple1Bus.Write` | None | None | PIA $D010-$D01F (mirrored $D000-$DFFF); cassette $C000-$C1FF | None (`Load` uses `Write`) |
| Apple II, II Plus, IIe | `Apple2Bus.Write` | `AccessSwitch` on reads *or* writes of $C000-$C0FF: language card $C080-$C08F; 80STORE, RAMRD, RAMWRT, ALTZP, INTCXROM, SLOTC3ROM; PAGE2/HIRES; `_internalC8` set by reading $C3xx and cleared at $CFFF; firmware card; card install/remove; reset | SoftCard Z80, mouse card, 3.5 card and slot 7 block device, all through `Write` | $C000-$C01F (keyboard, VBL), $C061-$C067, floating bus on unassigned I/O and on RAM above `RamKilobytes`, slot I/O $C090-$C0FF, Mockingboard $C400-$C4FF | `SetRam` (debug `Load`, the Integer BASIC tokenizer); `PokeArea` (debug `Poke`, the banks' `Poke`) |
| Apple III | `Apple3Bus.Write` (with extended addressing) | VIA writes at $FFD0-$FFEF (`UpdateRegisters`: environment, zero page, bank, stack, I/O and ROM enable); `_extendedBank` latched as a side effect of zero-page reads | ProFile pseudo-DMA, which writes `_ram` directly on a read of $F8xx; SoftCard3 through `DmaWrite` (uses `Write`) | $C000-$C0FF when I/O is enabled; the VIAs | ProFile `Transfer`; debug `Poke`, `PokeFar` and every bank's `Poke` write `bus.Ram` |
| BBC Micro | `BbcBus.Write` (Model A repeats its 16K) | Sideways ROM select, $FE30-$FE3F | None (the 8271 interrupts the CPU) | SHEILA $FE00-$FEFF | `Load` (`CopyTo`) |
| PET | `PetBus.Write` (1K video repeated at $8000-$87FF) | None | None | $E800-$EFFF | `Load` |
| Color Computer 1, 2, 3 | `CocoBus.Write` / `WriteCoco3` | SAM $FFC0-$FFDF (address-only writes); CoCo 3 GIME $FF90 and MMU $FFA0-$FFAF | None | PIAs $FF00-$FF3F, disk $FF40-$FF5F, GIME $FF92-$FF93 | None after power-on |
| Altair | `AltairBus.Write` | None | Front panel `Deposit` (uses `Write`) | None (I/O is port-mapped) | None |
| Kaypro II | `KayproBus.Write` | `_romBanked` from OUT to ports $1C-$1F, `Reset`, `BankRomOut` | None | None memory-mapped | `PokeRam` (debug `Load`, `BasicPoke`, the ram bank) |
| TRS-80 Model I | `Trs80Bus.Write` | None | None | $37E0-$37FF (latches, FDC), keyboard $3800-$3BFF | None |
| TRS-80 Model III, 4, 4P | `Trs80Model3Bus.Write` | Port $84 (map, paging, video page); port $9C (4P boot ROM) | None | Keyboard $3800-$3BFF (or $F400-$F7FF), printer $37E8-$37E9 | None |
| TRS-80 Model II | `Trs80Model2Bus.Write` | Port $FF (bank, video at $F800); port $F9 (boot ROM); reset | Z80 DMA through `Write` | None memory-mapped | None |

Other effects of reads:

- `Peek` is documented as having no side effects, but several targets' `Peek` depends on time: the Apple II's
  floating bus, VBL and paddles.
- Some targets update input pins when peeked: the Apple-1 PIA, the BBC's system VIA and the PET.
- A mapping change can come from a **read**: Apple II soft switches, `_internalC8`, and the Apple III's
  extended-bank latch. A hook on writes alone cannot see these.

The debugger's own writers:

- `writeMemory` and the `retro/memory/*` edits (assemble, fill, paste, load).
- Freezes: `ApplyFreezes` before every run slice, and `FreezeCycle` per cycle for a few frozen bytes.
- BASIC variable edits through `BasicPoke`, and loaders.
- These go through `Target.Poke`, a bank's `Poke`, `BasicPoke` or a machine `Load`. Per machine those end in
  `Bus.Write`, `PokeArea`, `SetRam`, `PokeRam` or direct array writes.

## The design, if it is built

This section works the design through so that a later decision has it ready. The recommendation below is not to
build it now.

### Dirty pages per address space

- One `ulong[4]` per tracked space: 256-byte pages, 256 bits for 64K. One space is the CPU map, plus one per
  `DebugMemoryBank`.
- A write sets `bits[page >> 6] |= 1UL << page`.
- `NotifyMemory` hashes only the views whose ranges meet a dirty page, and only within those pages. It needs a
  per-view, per-page hash so that a clean page keeps its old contribution. It then clears the bits. With no dirty
  page and no volatile range, the check is O(1).

**Where the bit is set.** There are three candidates:

1. **In each bus's `Write`.** This sees device writes that use `Write`, such as the SoftCard, mouse, 3.5 card,
   slot 7 and Model II DMA. It costs the most:
   - It puts a store on the hottest path of eleven buses, including `Apple2Bus.Write`, which the Desktop's PGO
     profile covers.
   - It needs a way to reach the debugger from machine code. That would be a nullable `ulong[]` field the bus
     tests, a branch per store even with no debugger attached.
   - The direct writers (`SetRam`, `PokeArea`, `PokeRam`, the Apple III's array writes, `Load`) each need the same
     mark.
2. **In the debug host's `Execute`, from `cpu.LastCycle`.** This is how data watches already see stores
   (`DebugSession.cs`, `if (_watches.Count != 0) Watch(cpu.LastCycle, ...)`). It touches no machine code, so it
   does not change Desktop or its profile. When no editor is open it costs one count test per cycle, like the
   watches. With editors open it costs `LastCycle` each cycle, which the stepping convention keeps
   off the hot path for good reason: storing a cycle record each cycle cost the Z80 about 30%. It sees only CPU
   stores, plus the SoftCard's own and host cycles as the watches do, so device writes need the fallback below.
3. **Per physical array, not per CPU page.** On the Apple II one store to $0400 can land in `_main` or
   `_auxiliary`, and the CPU-mapped view and a bank view see the same byte through different references. So pages
   are best kept per backing array, and each view maps its ranges to the arrays that back them *at check time*. A
   CPU write dirties the bank behind that address now, through `WriteArea`. Mirrors such as the PET's video RAM,
   the BBC Model A and the TRS-80's video make one array page several CPU pages.

**What a write hook cannot see, and the signal for each:**

- **Mapping changes** such as soft switches, the language card, sideways ROMs, the SAM, the GIME, the Model 4's
  port $84 and the Kaypro's ROM bank.
  - Signal: a per-target *map generation* that the target increments wherever it changes its map state. A change
    of generation dirties every page of the CPU-mapped space, and only of that space, since a bank's own bytes do
    not move.
  - On the Apple II that would be every `AccessSwitch` that changes `Switches` or the language card state, plus
    `_internalC8`. A program toggling PAGE2 every frame would make the CPU space fully dirty at every check, which
    is today's cost, not worse.
  - Cheaper per target: compare a snapshot of the map state, such as the IIe's switch word and language card bits,
    at each check instead of hooking each change. That needs no machine change, but each target has to expose its
    map state.
- **Device and DMA writes that bypass `Write`**, such as the Apple III ProFile `Transfer` and machine `Load`s.
  - Signal: mark the dirty pages at each, or keep hashing for machines that have such writers until they are
    hooked.
- **I/O whose Peek changes by itself**, as in the table's I/O column.
  - Signal: each target declares its volatile ranges. The I/O pages are already in `IDebugTarget.Regions`. Views
    that cover them keep hashing just those pages at every check, as today. That is a few hundred bytes, not 64K.
  - The floating bus on an Apple II with less than 64K makes RAM above `RamKilobytes` volatile too.
- **Debugger writes:** mark in `Poke`, the banks' `Poke` wrappers in each target, `BasicPoke` and the loaders. Or
  more simply, dirty everything after any debugger write, since those are rare and are followed by a
  `NotifyMemory` call anyway.
  - Freezes are the exception, since they rewrite their bytes every slice. `ApplyFreezes` must mark a page only
    when it changed a byte, or every frozen page is dirty at every check.

**Behavior to keep:**

- `except` stays as it is. The writer's own view still updates its `Seen` hash and is skipped for the event.
- Unsubscribe removes the view. A view with no subscriber that the 32-view limit evicts simply stops being checked.
- An expression reference such as `HL` that resolves elsewhere starts its view over, as `Track` does now.
- The `memory` event's shape (`memoryReference`, `offset: 0`, `count: end`) does not change. VS Code and Retrocore
  Memory see the same events for the same changes, so the protocol impact is none.

### Rejected alternatives

| Alternative | Why not |
| --- | --- |
| Dirty bits in every bus's `Write` | It touches eleven machines' hottest paths and the Desktop profile, and it misses mapping changes, reads that switch banks and volatile I/O anyway. That buys at most 0.8% of wall time. |
| Dirty bits from `LastCycle` in `Execute` | It keeps machines untouched, but it pays for `LastCycle` on every cycle while any editor is open. That is likely more than the hashing it saves at a 330 ms interval, and it is unmeasured. |
| A shorter or adaptive interval | It changes when editors see a change, and it does nothing for stepping. |
| Hashing on a background thread | `Peek` reads machine state that the run loop changes. Copying memory under the lock costs about what hashing does. |

## Recommendation

1. **Do not build dirty-page tracking now.** The measured gain is under 1% of wall time while running. The cost is
   a hook in every machine, or a per-cycle cost in the host, with a correctness surface the table shows to be wide.
2. **If several-editor stepping becomes a complaint, share the hash per address space.** This is host-only, with no
   machine code, no hot path and no profile.
   - In `NotifyMemory`, group views by `(Bank, Address)`.
   - Hash each 256-byte page of the union of their ranges once.
   - Give each view its covered pages' hashes combined, comparing that with its `Seen`.
   - This turns four editors on one space into one hash of 64K, about 0.15-0.25% while running and about a quarter
     of the per-step cost measured above. The events stay the same.
   - Per-page hashes also make "which pages changed" available, if a later event wants a narrower `offset`/`count`.
     Today it does not: `offset` must stay 0 for VS Code 1.100.
3. **Revisit dirty tracking** if editors grow to 8 or more on one session, or if Native AOT or Desktop starts
   hosting memory views. That would need a new measurement.

## PGO and hot paths

- The recommendation touches only `DebugSession.Memory.cs` and runs every eighth frame and at stops. It is not in
  the profiled path, which is 6502 dispatch, the Apple II bus, video, audio and devices. It needs no profile refresh.
- The dirty-page design with a bus hook *would* change `Apple2Bus.Write`, which is profiled. Under
  [the checklist](../../.claude/skills/performance-testing/overlay.md#native-aot-pgo-maintenance), that would need:
  - an interleaved A/B with no debugger views, showing no regression;
  - the 6502 and machine exactness gates;
  - a Windows x64 profile refresh with `tools/Update-DesktopPgoCorpus.ps1`, validated against the old profile.
- The `LastCycle` variant changes `DebugSession.Execute`, which is a debug-host path the Desktop also runs through
  the debug host's targets. It would need the same A/B with and without editors.
- No profile was retrained for this plan, and none needs to be.

## Test plan

Most of this applies to the shared hash as well. Items marked *dirty* apply only to dirty tracking.

The tests extend `tools/Test-Memory.mjs`, which needs nothing external for the Model I, and the unit tests in
`tests/Retrocore.Tests`. Test-Memory's existing per-range, subscriber, least-recently-used and `except`
assertions must keep passing unchanged.

| Case | Where | Asserts |
| --- | --- | --- |
| CPU write in a tracked page | Test-Memory, Model I | One `memory` event for each reference covering it, while running and at a stop |
| CPU write outside every view's ranges | Test-Memory | No event |
| Debugger write (`writeMemory`, `retro/memory/fill`, BASIC variable edit) | Test-Memory | Events for every other reference covering it; none for the writer (`except`) |
| Freeze holding a byte the program keeps writing | Test-Memory | No repeated events once the freeze holds (*dirty*: the page is not dirty at each check) |
| Two editors with overlapping ranges, and two with disjoint ranges, on `0x0000` | Test-Memory | A write in the overlap reaches both; a write in one editor's range reaches only that editor's reference |
| A shared hash with views of different extents | Unit test on the grouping | Each view's hash changes exactly when a byte in its own ranges changes |
| Unsubscribe | Test-Memory | After `retro/memory/unsubscribe`, no event for that subscriber's ranges; the other editor still gets its events |
| Bank switch without a write (IIe: RAMRD/80STORE, language card read of $C080-$C08F) | Test-Memory IIe part, `RETROCORE_IIE_ROMS`; and a unit test on the SDK IIe | The CPU-mapped view gets an event; bank views do not |
| CPU write through a switched map (IIe RAMWRT set) | Same | The `aux:` view gets an event, the `main:` view does not, and the CPU view gets one only if RAMRD also reads aux |
| Device write (Apple III ProFile `Transfer`; IIe slot 7 block read; SoftCard Z80 store) | Unit tests with a fake card, or the existing ProFile tests | The covering views get events (*dirty*: through the device signal) |
| Volatile I/O (Model I $3800 keyboard; IIe $C000) | Test-Memory | A key press changes a view of the keyboard page with no write (*dirty*: through the volatile ranges) |
| Reset and card change | Test-Memory | Events as today |
| No views | Perf A/B, interleaved | No change in max speed beyond noise (*dirty*, bus hook: the PGO gate above) |

A regression test is shown to fail with its mark removed before it counts as covering that path.

## Reproducing the measurement

- Retarget a scratch copy to whatever SDK is available. On a machine with the .NET 11 SDK, no retargeting is needed.
- Add the probe to `NotifyMemory`: a `Stopwatch`, a count of `MemoryByte` calls, and a stderr line when
  `RETROCORE_MEMPROBE=1`.
- Drive it with a script over `tools/DapClient.mjs` that:
  - sets `RETROCORE_DAP_HOST` to the probe build;
  - launches with `stopOnEntry` and `speed`;
  - reads `0x0000` (or bank references) in 4K pieces with a `subscriber` per editor;
  - continues for 10 s and pauses.
- For stepping, issue `stepIn` with `granularity: "instruction"` in a loop and time each request to its `stopped`
  event.
- On the development machine, pin as the [overlay](../../.claude/skills/performance-testing/overlay.md) says and
  interleave runs. Report the IIe on Apple's ROM dumps as well as the SDK's.
