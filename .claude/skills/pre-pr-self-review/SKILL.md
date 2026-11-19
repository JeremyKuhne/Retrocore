---
name: pre-pr-self-review
description: Before publishing the first reviewable version of a behavioral change, check its contracts, affected paths and variants, regression evidence, and validation gaps so likely defects are caught before external review.
license: MIT
compatibility: Follow the consuming repository's test, build, and specialized-skill instructions.
metadata:
   portability: repository
   applicability: retrocore
   risk: local-write
   maturity: canary
   requires: none
   related: performance-testing, retrocore-media-lifecycle, retrocore-conformance, retrocore-self-host, retrocore-native-assembly
---

# Pre-PR self-review

Use this skill for a behavior-changing feature or fix before moving a draft to ready, requesting external review, or otherwise publishing its first reviewable version. For a documentation-only or mechanical change, use only the applicable parts. Follow any more specific repository instruction; this skill complements specialized checks rather than replacing them.

## Review the contract before the diff

Write down, in a sentence or two:

- The user-visible behavior that must change, and what must remain unchanged.
- The state and ownership involved: machine, device, memory bank, source file, session, media, or revision.
- The expected result on success, failure, cancellation, and retry.
- Whether a compatibility change or weaker guarantee is intentional and accepted.

Do not treat a plausible implementation, green review banner, or resolved thread as evidence that the contract is met.

## Trace the full behavior

Follow the affected value or action across its real boundaries. Depending on the feature, inspect:

- UI entry points, commands, menus, accessibility and focus behavior.
- Protocol request registration, advertised capabilities, dispatch and response/notification paths.
- Host, debug target, machine implementation, device, storage and recovery ownership.
- Tokenization, parsing, evaluation, source mapping, generated grammar and rename/reference consumers.
- Serialization, file formats, integer conversions, allocations and error handling.
- Reset, stop, restart, replacement, cancellation, disposal and concurrent operations.

List affected implementations and deliberately different variants. Shared action names do not guarantee shared semantics; for example, distinguish a cassette RECORD action that replaces media from one that writes in place. Use `retrocore-media-lifecycle` or `retrocore-conformance` when those domains are involved.

For asynchronous code, mark every suspension point and identify the state that can change while suspended. Capture the intended identity, then validate it inside the queue and immediately before mutation; validating only before an `await` or only after a request may be too late.

## Choose discriminating checks

Prefer a small matrix of behavioral boundaries over a long list of nominal cases. Select only the dimensions the change can affect:

| Dimension | Examples |
| --- | --- |
| Input | Ordinary, empty, maximum valid, one beyond, malformed |
| State | Running/stopped, reset/not reset, mounted/ejected, mapped/unmapped |
| Outcome | Success, no-op, rejection, partial I/O failure, cancellation |
| Identity | Same target, replaced target, newer revision, another session |
| Variant | Machine, CPU, dialect, media format, OS, protocol client |

Add a focused test that fails before the change and asserts the externally observable result: for a fix, a regression test that reproduces the original defect; for a new feature, a test of the new behavior that fails without it. For data-changing behavior, check the data remains recoverable on failure. For shared code, include at least one sibling variant that must keep its old behavior. For parser or format logic, use independent input vectors where possible; a writer and reader that share assumptions are not an independent oracle.

Do not add every matrix combination. State omitted combinations and why. Use the existing test framework and helpers; favor controlled barriers and injected errors over timing sleeps. A test that would also pass before the change is not evidence that the defect or feature is covered.

## Validate and hand off

1. Read the relevant repository and domain skill instructions before editing or choosing a validation command.
2. Run the smallest existing command that covers the behavioral change, then widen only if results or integration boundaries warrant it.
3. Confirm that expected test cases actually executed. Missing ROMs, disks, editor executables, or other fixtures mean that scenario was not validated, not that it passed.
4. Inspect the final diff and rerun checks affected by changes made during review remediation.
5. Report exact commands and observed outcomes. Separate **passed**, **failed**, **skipped/unavailable**, and **not run**. Do not claim manual UI, real-device, or performance validation without performing it.
6. If the change makes or challenges a performance claim, follow `performance-testing`; record both semantic requirements and product-performance evidence. Apply the repository's Native AOT PGO policy when its triggers apply, including the refresh decision.
7. Leave intentional scope decisions and deferred cases explicit, with rationale and a follow-up when appropriate.

The PR description should carry a compact evidence summary, for example:

```text
Contract: Reject a stale save confirmation without changing either session's media.
Variants: Same session/revision; replaced revision; second session; failed write.
Regression: Stale confirmation is rejected before mutation; both journals remain readable.
Validation: `dotnet test ...` passed. VS Code confirmation flow not run (editor unavailable).
Deferred: Crash between journal write and replacement; tracked separately because ...
```

This is a checklist for finding and proving likely regressions, not a guarantee of defect-free code. When evidence contradicts an assumption, update the contract or implementation instead of preserving the assumption.
