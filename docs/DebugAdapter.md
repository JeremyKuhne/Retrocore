# Debug adapter automation

Ordinary debugger launches still send frames, audio, and source-cycle updates. Set `textOnly: true` to suppress
those streams; this does not change guest execution or hide debugger events. Screen and text snapshots remain
available on request.

## Run and input

After `launch` and `configurationDone`, submit one `retro/runUntil` at a time. This example supplies a line and
stops at the next verified wait **after** admitting its bytes:

```json
{
  "policy": "scripted",
  "input": { "text": "LOOK\n", "backend": "guestDemand" },
  "stopOn": { "kind": "inputDemand" },
  "maxCycles": 1000000,
  "snapshot": { "surface": "visibleText" }
}
```

The response reserves a run and returns `launchId`, `runId`, `startCycle`, `maxCycles`, and the initial input
counts, if any. Correlate `retro/run/result` by both IDs; either the response or the event can arrive first. The
event includes an outcome, the observation cycle, input counts, input status, and the optional snapshot. Input
and snapshot are independently optional. No text is sent ahead of verified demand with `guestDemand` (the
default backend). The `physical` backend uses ordinary device input and paste pacing; it cannot report guest
acceptance, so it is suitable for custom guests with their own application readiness markers.

If a completion observation fails, the result still reports the run's outcome and IDs. `observationErrors`
names each failed observation and gives its error message; an unavailable `demand` or `snapshot`
is omitted. A failed final receipt leaves the delivered byte unconfirmed and does not prevent cancelling unsent
input.

| `stopOn.kind` | What it observes |
|---|---|
| `inputDemand` | A verified blocking keyboard operation, with no input remaining in this run's batch. |
| `instruction` | `address` (0–65535) at the owning machine CPU's instruction boundary. This is a CPU address, not a bank or a symbol; use a breakpoint when bank or source identity matters. |
| `screenContains` | Case-sensitive `contains` on newline-joined text rows (`surface` defaults to `visibleText`). `fresh: true` requires first observing a sample without that string. |
| `transcriptContains` | ASCII `contains` in new bytes from the configured console sink, beginning with this run. Draining the sink does not reset a pending match. |

`scripted` (the default) runs unthrottled and parks the whole guest, including its devices, on completion.
`live` uses the session's configured speed and observes without parking on a match or budget expiry. If a
machine was already running, the adapter attaches to that worker. The deadline is relative to the request's
starting cycle and defaults to 60 emulated seconds. The adapter checks the starting state and completes budget expiry
at the first instruction or interrupt-response boundary at or beyond the deadline, or while the CPU is idle between
instructions. A device holding the CPU mid-instruction can extend the run until the hold clears. If the device never
releases the CPU, cancel or pause the run.
Instruction, demand, and transcript observations win ties with the budget. Text is sampled initially, at about
30 Hz of guest time, and where the budget expires; it can miss text between samples. Breakpoints and other debugger
stops take precedence. No polling instructions, IRQs, or device cycles are skipped.

Pause, breakpoints, exceptions, cancellation, reset, replacement, and disconnect retire the run. `retro/run/cancel`
takes both IDs, parks the guest if it cancelled the active run, and returns `cancelled: false` for stale IDs.
An active run must be paused or cancelled before a manual continue or step. A scripted reset leaves the machine
stopped and emits a DAP `stopped` event; a live reset retains ordinary reset behavior. A physical interrupt
(`retro/key` code 3) cancels automation input and lets a running guest continue at its configured speed. The
result uses one of `inputDemand`, `matched`,
`cycleBudgetExceeded`, `inputNotAccepted`, `captureOverflow`, `stopped`, `exception`, `cancelled`, `interrupted`,
`reset`, `replaced`, or `disconnected`. `stopped` and `exception` have a corresponding DAP `stopped` event;
scripted matches and cycle exhaustion also emit that event so the standard debugger knows the guest parked.
The host gives the peer up to two seconds to drain queued output on disconnect or input EOF. If the peer
does not drain it, the host discards undelivered queued messages and exits with a nonzero status rather than
waiting for a blocked write. If the output pipe fails while the input is still open, execution stops; the client
closes its input pipe to finish the session.

`retro/input/status` returns the current cycle, whether the machine is running, and `waiting`, `unknown`, or
`unsupported`. `waiting` names the active profile and its verified input route. `unknown` is not a request for
a key: it covers running between reads, a busy device, unknown firmware, alternate vectors/devices, and custom
code. As with all snapshots, demand is an observation at a particular cycle, not a persistent lock on a live
guest. The adapter never infers it from an unchanged PC, empty latch, or a prompt on the display.
The ordinary `retro/type` response remains `{ "typed": ..., "skipped": ... }`; `retro/input/status` exposes
progress for the current or most recently submitted batch.

Input counts distinguish mapped, skipped, pending, delivered, acknowledged (if observed by a device profile),
accepted, rejected, in flight, unconfirmed, and cancelled bytes. Admission is not application consumption.
`physical` reports delivery to the emulated device, not acceptance. Finishing a run cancels its unissued bytes;
an already delivered key cannot be retracted and is reported as unconfirmed if its receipt was not observed.
Check the result's counts even on a successful match: an application marker can be reached with unused input.

### Input profiles

| Guest path | Delivery and limits |
|---|---|
| Apple-1 SDK Woz Monitor and Apple-1 BASIC | Existing PIA keyboard; confirms the verified port-A read. A program's own PIA loop is not recognized. |
| Apple II/II Plus Monitor and original/enhanced IIe | Existing keyboard latch on the matched firmware and default input path. IIe slot-3 80-column reads are distinguished from other uses of the same low-level poll. |
| Apple Pascal 1.1 | Matched bank-2 console firmware and keyboard route; confirms a software ring store after strobe clear. Alternate console cards and other Pascal versions are not recognized. |
| Apple III SOS `.CONSOLE` 1.30/1.31 | Matching relocated driver and eligible blocking keyboard route; one hardware key, accepted when the IRQ commits it to the type-ahead ring. Does not recognize alternate drivers, attention-key or no-wait input. |
| PET SDK BASIC 1/2/4 screen editor | Publishes one mapped PETSCII byte to the empty editor buffer. Not a physical scan and not nonblocking `GETIN`. |
| BBC MOS 1.20 | Publishes one byte in the default keyboard ring during an untimed `OSRDCH` wait. The guest still does line editing. Not a physical scan, `INKEY`, redirected input, or soft-key expansion. |

`ioMode: "fast"` is separate from all of the above. It changes peripheral timing: Apple-1 terminal acknowledgement
and device typing delays on Apple-1, Apple II, Apple III, PET, and BBC. Other targets reject it. The default
`realistic` mode preserves the normal device timing and works with guest-demand input. Use it for timing tests.

## Snapshots and console capture

`retro/text` returns compact text; `retro/snapshot` accepts the same surfaces plus `screen`. Pass `{ "surface":
"visibleText" }`, or omit the surface for current visible text. Snapshots carry a launch ID, revision, cycle,
and support flag. Text snapshots also describe mode, model (when available), columns, display rows, the first
represented row and row count, decoding, and cursor when known. Text does not render pixels.

- `visibleText` represents the current mapping, not the scanline history. Apple IIe 80 columns interleave
  auxiliary/main memory; in mixed mode only rows 20–23 are visible. Unmapped glyphs such as MouseText are
  represented by `�`. Apple III 80 columns interleave its two system-bank pages in display order; blanking or
  graphics does not expose hidden rows as visible text. Apple III decodes the text code convention, not a custom
  character RAM bitmap. PET is 40 columns and uses its active charset. BBC teletext represents character codes
  (not control effects or mosaics); bitmap text is a lossy guess from the MOS font where a character is eight
  scanlines high.
- `textMemory` is the current mapped text page on Apple II and Apple III, even if hidden. On Apple III in
  graphics mode it is a 40-column page.
- `editor` explicitly reports unsupported; no Pascal logical 80-column workspace is inferred from video.
- `screen` returns RGBA pixels and the selected monitor. `scanned` represents the frame drawn by the beam,
  not a render as if current switches and RAM had applied throughout the scan. Terminals and the Model 100
  LCD use `displayBuffer` instead. Use `retro/video` on targets that offer a separate current-render option.

`textPolicy: "manual"` is the default. `onStop` emits `retro/text/update` after a debugger stop. `onInputWait`
emits the update on a verified input-demand result. `changes` sends a full snapshot on a sampled change while
running or at a stop, not every intermediate state. `textSurface` selects the text surface for these updates.

To keep console bytes separately, set `consoleCapture: { "sink": "apple1Terminal", "capacity": 65536 }` at
launch. `retro/console/read` drains up to `maxBytes` (default 4096) and returns base64 `data`, a byte `offset`,
`count`, time range (`firstCycle`/`lastCycle`), `remaining`, and `overflow`. This sink taps the seven bits the
Apple-1 terminal actually accepted, before screen normalization or scrolling. No generic console sink is claimed
on other machines. If a byte arrives while the buffer is full, the adapter parks and reports an explicit overflow
on the next execution boundary; the retained prefix is readable and the stream is no longer complete. Relaunch to
start a new stream.

## Media speed

`tapeSpeed` and `diskSpeed` launch arguments accept `normal`, `fast` or `skip`. They are independent of machine
`speed` and keyboard/peripheral `ioMode`. `retro/mediaSpeed` with `{ "kind": "tape", "mode": "skip" }` changes the
requested mode; omit both arguments to read the current settings. The response and launch body's `mediaSpeed`
have `tape` and `disk` values (`null` for a kind not installed).

A project-image launch returns `mediaSpeedResult` with `kind`, `device`, `requested`, `effective`, and `reason`,
plus `cycles` and `elapsedMilliseconds` for the boot media phase. `effective: "skip"` means a shortcut actually
ran. `requested: "skip"` with `effective: "fast"` and `reason: "unsupportedOperation"` means real guest cycles ran
unthrottled. During ordinary execution, `retro/mediaSpeed` reports fallback when a device is seen active in status
sampling. This is live telemetry, not a transfer log: short or adjacent operations may not produce separate events.
The requested setting does not change. A DAP `cancel` request naming a pending launch's `requestId`
can interrupt its project-image boot.

See [media speed support](Devices.md#media-speed) for the machines and operations that can Skip.
