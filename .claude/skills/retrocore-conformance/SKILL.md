---
name: retrocore-conformance
description: Check emulator, debugger, media-format, BASIC dialect, address-mapping, or ROM behavior against an explicit contract and representative independent evidence.
license: MIT
compatibility: Requires repository context; some comparisons need licensed ROM or disk fixtures supplied by the user or configured externally.
metadata:
   portability: repository
   applicability: retrocore
   risk: local-write
   maturity: canary
   requires: none
   related: pre-pr-self-review, retrocore-native-assembly, retrocore-disassembly, performance-testing
---

# Retrocore conformance

Use when behavior depends on a CPU or peripheral, machine revision, memory map, timing, media format, BASIC dialect, ROM routine contract, or conversion between representations. The goal is to state what is being emulated and how it was checked, not to assume that similar machines or software versions behave alike.

## Establish an oracle and scope

Before changing code, identify:

1. **The contract:** observable inputs, outputs, side effects, errors, timing/state boundaries, and supported variants.
2. **The source of truth:** repository implementation/docs, an authoritative manual or known format specification, an SDK-built ROM, a user-supplied licensed dump, or a separately authored test vector. Record disagreements and uncertainty.
3. **The path under test:** caller, parser/tokenizer, machine/device, memory mapping, persistence, debugger/protocol, and user-visible result as applicable.
4. **The limits:** missing fixtures, unverified hardware revision, inaccessible editor behavior, or intentionally normalized/lossy data.

Treat sources as independent only when they are. A round trip through the same writer and reader can preserve a shared bug; a comment or compiler acceptance does not prove runtime semantics.

## Select representative variants and boundaries

Choose variants where behavior actually differs. Depending on the change, consider machine/revision, CPU, ROM version, dialect, disk/tape layout, bank/read/write mapping, and host OS. Include the distinguishing sibling behavior if shared code changes.

Target boundaries, not only defaults:

- Minimum, maximum, just-over-limit, truncated, malformed, duplicate, and end-of-stream/track cases.
- Integer width, sign, precision, overflow, wraparound, zero, and non-finite numeric cases.
- First, middle, last, and sole record/sector; valid and invalid checksums; short and oversized data fields.
- Reset, interrupt, idle, instruction boundary, bank switch, alias, and multi-CPU handoff.
- Success, rejection, cancellation, missing input, and I/O failure.

Use a compact matrix tailored to the change; do not generate every combination when dimensions are independent. If the feature claims byte preservation, compare bytes and metadata. If it intentionally normalizes or loses data, name the exact rule and test it separately from rejection behavior.

## Apply domain-specific evidence

- **Emulation and timing:** test bus/observable state at the relevant cycle or instruction boundary, including reset/interrupt and mapping changes. Avoid replacing a fidelity guarantee with a later run-slice check for performance without explicitly changing and accepting the contract.
- **BASIC or other dialects:** cross-check tokenization, scanning, evaluation, rename/references, generated grammar, and runtime behavior with compact syntax and dialect-specific examples. Where feasible, execute the same example on the SDK ROM and compare values or text.
- **Memory and debugger:** distinguish read routing, write routing, protection, aliases, and the reported mapping. Test the debugger/protocol result as well as internal state.
- **Media and serialization:** use independent known vectors as well as round trips. Assert sector/record ordering, lengths, checksums, metadata, and exact error/normalization behavior.
- **ROM source and documentation:** byte-identical hashes prove assembled bytes, not that prose, register/flag contracts, or side effects are correct. For executable `In`, `Out`, `Uses`, and `Keeps` claims, exercise representative success/error/branch paths and check the actual CPU state. List untested paths.
- **Extension and protocol:** test request registration, capability advertisement, result/notification semantics, and at least one real VS Code interaction when focus, keyboard, accessibility, webview, or dialog behavior is in scope. Node/fake-DOM tests are not equivalent to a real editor run.

Use existing repository tests, SDK source, test harnesses, and skills first. Use `retrocore-native-assembly` and `retrocore-disassembly` for assembly-specific syntax and reconstruction. Use `performance-testing` for performance claims; keep semantic validity and performance acceptance as separate gates.

## Report evidence honestly

For every command or comparison, state what ran and what it establishes. Separate executed, skipped, unavailable, manual, and not-run checks. Give fixture and source provenance without redistributing licensed ROMs or disk images. Do not claim full hardware or dialect fidelity from a partial oracle.

When evidence conflicts with the current implementation or documentation, report the discrepancy and choose an explicit contract before changing behavior. For a broader change, use `pre-pr-self-review` to capture the matrix, regression test, and remaining gaps.
