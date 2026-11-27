# Backlog: tape and disk speed

Status: **first implementation: PET BASIC project cassette load.** The same controls and Fast fallback work
for other media before they acquire their own Skip paths. See [current support](../Devices.md#media-speed).

## What the choices mean

Replace the Fast Tape and Fast Disk toggles with two independent controls: **Tape speed** and **Disk speed**.
Whenever either control is shown, all three choices are available. Show both controls on a machine that has both
kinds of media; don't make Skip appear or disappear when a disk or tape is mounted.

| Choice | While the media operation runs | Guest and debugger contract |
| --- | --- | --- |
| **Normal** | Honor the selected machine speed, including `max`. | Run all guest cycles, with the usual devices and debugger behavior. |
| **Fast** | Unthrottle the whole machine while the medium is active; return to the selected speed afterward without waiting for wall time to catch up. | Run the same guest cycles as Normal. No change to device clocks, interrupt ordering, or observability. |
| **Skip** | Complete a supported media operation at its verified firmware or device boundary without replaying the intervening work. Otherwise run it in Fast. | Preserve the supported operation's result and working continuation. Elapsed guest time and the skipped interval's intermediate I/O, interrupts, memory writes, and debugger stops are not reproduced. |

Help text: **"Skip supported media operations. Other operations run at Fast speed. See the docs for supported machines
and formats."** Keep the requested value when falling back, and show what actually ran, for example
**"Fast (Skip not supported for this load)."** Project boots report a result once per launch, even without any
running-frame updates. Live fallback is sampled activity, not a per-operation log; report changes instead of repeating
the current status on every refresh. A reported Skip means an actual transition occurred, not merely a selection.

Fast is the existing unthrottling feature, not a sector shortcut or a higher guest clock. In particular, the
[DAP pacing loop](../../src/Retrocore.Debug/DebugSession.cs) already runs unthrottled at machine speed `max`,
and [synchronous project-image boot](../../src/Retrocore.Debug/DebugSession.ProjectImage.cs) does not use that pacing
loop. `ioMode` is separate and remains unchanged. On the PET it controls keyboard holds and gaps.

## Shared policy and compatibility

1. Use the same values (`normal`, `fast`, `skip`) for tape and disk in launch configuration, debugger requests and
   Desktop settings. Use one effective policy in the debug host and Desktop, not a separate implementation in each UI.
   The drive or firmware decides which operations qualify; the control only records the requested policy.
2. Keep existing defaults where the old switches apply. Map `fastCassette`/`fastDisk` false to Normal and true to
   Fast. Migrate the old Desktop `fastDrives` boolean to the two settings; a new explicit per-kind value wins over an
   old alias in the same configuration. Preserve legacy DAP requests and `--fast-drives on|off` as Normal/Fast aliases
   during migration. Do not silently turn any existing configuration into Skip. Keep global machine speed independent.
3. Replace the Desktop [display controls and status](../../src/Retrocore.Desktop/MachinePane.cs), Desktop
   [settings](../../src/Retrocore.Desktop/DesktopSettings.cs), the [VS Code display](../../extension/src/display.ts),
   and [launch schema](../../extension/package.json) together with the host surface. Respect keyboard focus and
   persistence across relaunch. If tape and disk are active together, either kind requesting Fast (including a Skip
   fallback) may unthrottle the shared machine; neither overrides the other kind's Skip eligibility. Resolve eligibility
   again for the next operation after a setting change. Don't try to undo a published Skip transition.
4. Cover both ordinary execution and project boot. Set the policy and read the selected machine speed before a
   project enters its media loop. In Normal, media activity obeys that speed; at 1x, a real-length tape may take minutes.
   Keep the DAP reader responsive to cancellation during the paced launch. Preserve request/response ordering.
   Do not change unrelated firmware boot delays just to implement media pacing. Existing cycle-accurate test launches
   that need to finish quickly can select Normal plus `speed: "max"`.
5. Document support by machine, ROM, controller, image and operation in the [device guide](../Devices.md),
   [debug adapter guide](../DebugAdapter.md) and relevant machine guides when support lands. Start with one common
   policy and a PET-specific hook. Don't invent a general system for rewriting firmware or restoring machine snapshots
   before a second use case proves what it needs to share.

## First implementation: PET cassette 1

**Scope:** the [adventure's `pet-basic` target](../../sample/adventure/retrocore.json) on a fresh PET 4032 using the
verified SDK BASIC 4 KERNAL/editor, a canonical project-generated tape and an unnamed direct-mode LOAD on cassette 1.
Keep generating and mounting the complete TAP in this milestone. The project's PRG is a useful independent byte
check, not authority to load bytes that aren't represented in the mounted tape. T64 support, arbitrary TAP/WAV
decoding, interactive LOAD, cassette 2, VERIFY and SAVE are not prerequisites.

The measured Release baseline at `b3f258642e91e7ad4b84798e61bf61a4bd477b44` reaches the adventure entry at about
196 million guest cycles. An exact stepping probe reduced the 194.06-million-cycle LOAD phase from **6.42 s** to
**4.12 s** without reducing guest work. The two data copies alone occupy **180.30 million cycles**,
about **92%** of the tape's playback interval. That is the work to remove, not the duplicate boot in the test runner.

Release measurement on the implementation, .NET 11 JIT on Windows x64, affinity `0x50`: three interleaved
fresh debugger launches per mode with machine speed `max`. The media phase's median was **6.665 s Normal versus
0.327 s Skip** (Skip range 0.305–0.663 s); whole launch was **8.055 s versus 1.745 s**. Phase work fell from
194,059,869 to 11,812,587 cycles. The complete payload, status, BASIC pointers, IRQ vector, screen and tape position
matched at entry. The separate adventure matrix verified both PET Skip hits and active disk fallback with exact
transcripts; the 4040 remained untested because its ROMs were unavailable.

1. **Capture the real transition first.** For Normal at `max`, probe just before the `LD100` program-data
   `jmp TRD` and at the instruction after the enclosing `LOAD`'s `jsr LD15` in the
   [BASIC 4 KERNAL](../../src/Retrocore.Machines.Commodore/Roms/Basic4/Kernal4.asm). Capture destination RAM,
   work/status bytes, registers/flags/stack, IRQ sources, vectors and latches, deck index/partial pulse/read
   level and motor state. Use more than one canonical payload and compare against an independently authored vector
   or ROM SAVE fixture. Determine which changes are required at the continuation, and which are solely effects of
   elapsed tape time.
2. **Intercept the call site, not all calls to the tape reader.** Let the ROM read and choose the real header, fill
   its buffer, set start/end and print its messages. At the specific program-data transfer boundary, preflight the
   ROM identity, caller and stack shape, read operation, selected drive and media generation/version, current head
   and phase, RAM bounds, and canonical framing, both copies and checksums. Check cancellation and the media identity
   at the point of transition. If support isn't proven, fall back before modifying guest or media state.
3. **Apply the block result and let firmware continue.** Put the bytes at the ROM-selected destination, establish
   status/work pointers and the proven deck/IRQ state, and resume with the real foreground return semantics.
   The data call is a tail jump; return to the existing `LOAD` caller, not to an IRQ epilogue or the game entry.
   Don't wind to EOF, discard an unrelated IRQ, fabricate 180 million elapsed cycles, or restore a whole-machine
   snapshot. Leave the ROM to finish LOAD, reset BASIC state, relink lines and accept `RUN`/`SYS`.
4. **Preserve the live path.** A breakpoint, watchpoint, trace or other observer requiring the skipped interval,
   other active timing-sensitive hardware, a different ROM/call context, dirty or changed media, or an unsupported
   operation keeps the real path. Malformed data and errors must not become successes; the ROM remains the oracle
   for second-copy recovery, checksums, short/long blocks and STOP. Report an internal transition failure rather
   than retrying from half-modified state.

### Acceptance and rollout

- **Compatibility first:** validate default/migrated settings and legacy clients, both controls on mixed-media
  machines, explicit `max`, fallback without preference changes, and use of the UI in both hosts. Make mode changes
  live without resetting, remounting or dirtying media. Add the supported cases to the help link; don't advertise
  timing-inexact writes or saves.
- **Keep a realistic timing canary:** in Normal at `max`, run a short independent cassette fixture through the real
  ROM. Assert representative read edges, PIA/VIA IRQ/timer ordering, no payload writes before the first complete
  data byte, and a pulse-derived lower bound for completion. Compare Fast with Normal for the same guest-cycle
  boundaries, bytes, status and device state; at a finite runtime speed also show that Fast unthrottles and then
  restores pacing. The [PET cassette tests](../../tests/Retrocore.Tests/PetTapeTests.cs) and
  [PET SYS-program tests](../../tests/Retrocore.Tests/PetSysProgramTests.cs) are existing starting points.
- **Prove Skip and fallback separately:** check the full loaded payload and RAM sentinels, `ST`, BASIC pointers,
  screen/continuation, tape position, restored IRQ/vector and a subsequent command. Assert that the accelerated
  block actually ran as Skip and used far fewer guest cycles; a passing transcript on fallback isn't a Skip pass.
  Exercise first-copy repair, both copies bad, truncated/EOF, wrong name, STOP/cancellation, changed mount,
  unsupported ROM and active observers. For failure cases compare to the realistic path, including partial work
  where applicable.
- **Measure one load before the full matrix:** in Release, gather interleaved fresh-state Normal-at-`max` and Skip
  runs with identical tape, ROM and launch settings. Separate header/transfer, build, boot, source metadata and
  whole launch. Target **0.50 s or less for the adventure LOAD phase** on the same measurement setup; a target is
  not a result. Then run [the adventure DAP matrix](../../tools/Test-AdventureDap.mjs) and require exact available
  transcripts, explicit Skip hits and explicit fixture skips. Assess the
  [Native AOT PGO profile](../../.claude/skills/performance-testing/overlay.md#native-aot-pgo-maintenance) if
  any shared stepping or Desktop hot path changes.

## Backlog for additional drives

All rows below start with Fast fallback in Skip mode. The candidates are separate follow-ups, not promises of Skip
support. Profile the existing exact path before committing to a shortcut.

| Priority | Drive or workload | Candidate and gate |
| --- | --- | --- |
| Next | **PET other tapes / port 2 / BASIC 1 and 2** | Expand the cassette path one ROM/port or format at a time. Port 2 uses VIA CB1, not PIA CA1. Prove matching cleanup and recovery with a ROM SAVE fixture and real recordings before enabling it. An interactive version also needs explicit observer/STOP policy. T64 is a separate file-container reader and transport decision; parsing it alone would not accelerate LOAD. |
| Next | **Apple II Disk II / DOS 3.3** | Profile the application data-read phase, then try a guarded standard-sector read at a verified RWTS boundary. Keep real boot initially. Preserve status, buffer, drive/head state, error/retry semantics and writes. Raw WOZ, nonstandard sectors, DOS 3.2 and custom loaders stay realistic until separately proven. Existing Disk II fixed-point and active-bit-cell work is already in the baseline. |
| Next | **BBC DFS / Intel 8271** | Try command-level seek/rotation shortening before considering a complete read shortcut. The controller is already byte-level. Keep command/result semantics and data request/NMI pacing, overrun and error behavior; don't bypass DFS with a host file copy. |
| Later | **Apple III built-in floppy / SOS** | Measure boot and file reads separately. Prove a read handoff at a supported SOS driver/operation, with banked buffers, errors, head/drive state and a correct return. SOS is not Apple II RWTS even though the controllers share code. |
| Later, fixtures first | **PET IEEE-488 4040/2040** | Obtain the matching drive ROMs and measure cold boot, file open and transfer separately; the adventure 4040 results were skipped, not measured. Investigate standard read transfers at the IEEE-488 boundary. Preserve addressing, channels, EOI, status/error channel and true-drive fallback; don't drop the drive CPUs for uploaded/custom code. |
| Later, measure first | **Apple block devices / ProFile / 3.5-inch controllers; Atari SIO disks** | High-level devices may already avoid most physical work; separate cosmetic activity decay from guest-visible waits. Try only a measured, supported read command, preserving status, data and handshake; for Atari keep the real 810 drive variant separate from the SIO-command model. |
| Later, measure first | **TRS-80 floppy family / CoCo / Kaypro / Altair disks** | Benchmark by controller, ROM and disk format. Keep DRQ/INTRQ and lost-data behavior, DMA on Model II, CoCo HALT/NMI signaling, real status/error paths, and raw track operations. A shared WD controller is not proof of a shared firmware contract. |
| Later, measure first | **VIC-20, Apple-1, BBC, TRS-80, CoCo, Altair and Atari tapes** | Use verified ROM/loader receive boundaries with known image types, not a change to common waveform clocks. Preserve addresses, framing/checksums and status, transport and continuation. Distinguish variants such as TRS-80 250/500/1500 baud; test a real timing or unsupported-loader case for each. |
| Depends on hardware work | **Commodore serial 1540/1541/1571** | Keep the [true-drive design](Commodore.md) for arbitrary drive programs. Consider Skip only for verified standard reads after real hardware emulation and baselines exist. Uploads and fast loaders continue to require the real drive path. |

Parent measurements across six SOS/DOS/DFS launches were **2.19 s** in combined disk boot and program load and
**2.02 s** in subsequent game-data reads, unpinned and already unthrottled. These are aggregate ceilings, not speedup
forecasts. Don't add them to the PET savings or infer that a faster motor setting would recover them.

For each follow-up, record the exact supported variants, oracle and entry/return boundary, unchanged state and intentional
timing losses, fallback cases, one realistic timing test, and a repeatable Release phase measurement before enabling
Skip. Update the support docs in the same change.
