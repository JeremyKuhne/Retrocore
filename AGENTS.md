# Agent instructions

## Native AOT PGO maintenance

Windows x64 Release Desktop publishing uses a bundled application PGO profile. Before changing 6502
execution, Apple II memory/video/audio/device stepping, Desktop/debug-host hot paths, the .NET
SDK/compiler or publish settings, or training workloads, read the
[PGO maintenance checklist](.claude/skills/performance-testing/overlay.md#native-aot-pgo-maintenance).

Assess whether the profile needs refreshing; do not silently assume an old profile remains effective.
Refresh the binary profile and its provenance together using the scripts, and validate correctness and
product performance before accepting them. Documentation-only and cosmetic changes do not require retraining.
State the refresh/validation decision in the change summary; if training is unavailable, report that limitation.

## Before external review

For behavioral changes, use [pre-pr-self-review](.claude/skills/pre-pr-self-review/SKILL.md) before publishing the first reviewable version. Route media save/eject/replace/recovery work through [retrocore-media-lifecycle](.claude/skills/retrocore-media-lifecycle/SKILL.md), and emulator, dialect, format, memory-map, or ROM-contract changes through [retrocore-conformance](.claude/skills/retrocore-conformance/SKILL.md). For extension changes involving actual editor interaction, follow the evidence guidance in [retrocore-self-host](.claude/skills/retrocore-self-host/SKILL.md).

Report commands and outcomes accurately: a skipped fixture is not a pass, and an external review's resolution state is not independent proof of a fix. Use the applicable existing specialized skill rather than duplicating its procedure.
