---
name: retrocore-media-lifecycle
description: Design or review media save, eject, replace, Undo, journal, recovery, and off-machine actions without losing data or applying stale confirmation to a different target.
license: MIT
compatibility: Requires repository context; run the focused .NET and DAP tests for the affected machine and media action.
metadata:
   portability: repository
   applicability: retrocore
   risk: local-write
   maturity: canary
   requires: none
   related: pre-pr-self-review
---

# Retrocore media lifecycle

Use when changing save, save-as, eject, insert, replace, record, revert, discard, Undo, crash recovery, kept media, confirmation, or actions on a stopped/off-machine session. Begin with the existing ownership flow in `src/Retrocore.Debug/MediaActions.Kept.cs` and its caller in `src/Retrocore.Debug/DebugSession.cs`; preserve that convention unless the design is deliberately changed.

## Identify the action and its owner

Before editing, trace the operation from the UI or DAP request through dispatch to the machine/device and storage layer. Write down:

- The machine/session identity, device, mounted medium, media revision or snapshot, and requested action.
- Whether the operation mutates the mounted medium in place, replaces it, or removes it.
- Which layer owns each side effect: save, machine action, retained-media/Undo registration, journal update, and notification.
- Which actions need confirmation, which can run while stopped, and which intentionally differ across machines.

Do not infer semantics from an action name. PET RECORD writes to the mounted tape in place; BBC cassette RECORD can replace the mounted tape. A replacement guard or Undo path must not silently change the in-place case.

## Preserve the callback and result contract

`MediaActions.Device` uses the machine callback to perform an eject/insert that releases changed media, and only records the outgoing medium for Undo after that machine action succeeds. If the callback is missing, it cannot establish that the action occurred. At the `DebugSession` call site, a `null` result delegates the machine action to the caller; a returned answer means the caller must not issue that same action again. For callback-mediated discard, the answer is returned only after the callback succeeds.

Keep the ordering explicit:

1. Validate the request and target.
2. Obtain any required user confirmation for the exact media/revision to be changed.
3. Perform the action through its owner.
4. Only after success, update retained-media/Undo or journal state.
5. Return the truthful outcome and notify the user of failures.

Never report success-shaped fallback data after a failed save, replacement, or recovery. On failure, leave the original medium and usable recovery state intact, and surface the error using the repository's established reporting path.

## Treat confirmation as a versioned authorization

A confirmation authorizes one operation on one target at one revision. Capture the identity needed to distinguish a replacement session or newer snapshot. Revalidate it:

- After each `await` that permits session, launch configuration, selection, or media state to change.
- Inside a serialized queue, after rereading the configuration and before sending a mutation request.
- Immediately before the storage mutation, not only after it.

The revision must remain stable across harmless request rebuilds, yet change when a different medium or newer session state replaces the confirmed one. A drive ID or image path alone is insufficient if the contents/revision can change at that path. If the target is stale, reject before mutation and explain why.

## Test failure and variant boundaries

Add focused tests for the affected path, preferably with deterministic barriers and injected I/O errors rather than sleeps:

- Dirty-media eject/replace, successful save, failed save, failed machine action, and Undo after success.
- A confirmation answered after media, revision, launch identity, or selected session changes; assert no target was mutated.
- An operation paused across an awaited read or queued request while another action changes its target.
- Journal recovery when the original source image is missing or unreadable, when that case is within scope.
- Each shared action on one replacement-style and one in-place machine.
- User-visible result, journal/Undo state, and persisted bytes, not just the helper's return value.

For crash or concurrent-process claims, use a fresh process and controlled ordering where practical. An atomic file replacement prevents torn writes but does not, by itself, prevent a stale writer from overwriting a concurrent edit. State any unsupported concurrency case explicitly.

Use the existing media/DAP test helpers and fixture policy. A test skipped because its disk image is unavailable is not evidence for that scenario. For a larger code change, use `pre-pr-self-review` to record the contract, variants, and validation gaps.
