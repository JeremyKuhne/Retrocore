# Agent instructions

## Assembly sources

Retrocore's sources are being converted for developers new to the old platforms: names say what things are, and
the names manuals and listings used are kept as historical names (`;; Also:`), so old documents and code still lead
to the right definitions. Before writing, converting or disassembling assembly, read
[ConvertingSources.md](docs/ConvertingSources.md) (the philosophy, the method and the rules learned so far), the
[style guide](docs/AssemblyStyle.md) and the [conversion logs](docs/conversions/README.md), and use the
[native-assembly](.claude/skills/retrocore-native-assembly/SKILL.md) and
[disassembly](.claude/skills/retrocore-disassembly/SKILL.md) skills.

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

To size and stack pull requests and take them through Copilot's review, use [copilot-review-loop](.claude/skills/copilot-review-loop/SKILL.md): read every thread and the newest review's summary, resolve only answered threads, and wait for Copilot's review of the head. Two of its gates are easy to skip, so they are repeated here:

- Before requesting Copilot's first review, have the whole diff reviewed independently, by a reviewer that is given the diff but not your conclusions.
- After three Copilot rounds on one PR, or once fixes start breaking other things, stop fixing finding by finding and run that independent full review again.

When woken by pull-request activity (reviews, comments, CI), follow [steward](.claude/skills/steward/SKILL.md), which leads into copilot-review-loop. Where these skills and generic pull-request guidance differ, these skills win. If a skill named in this file is not in your checkout, because the branch predates it, read it from the default branch (`git fetch origin main`, then `git show origin/main:.claude/skills/<name>/SKILL.md`) rather than proceeding without it.
