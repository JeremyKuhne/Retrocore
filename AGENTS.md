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
