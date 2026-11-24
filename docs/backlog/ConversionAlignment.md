# Aligning the two conversion branches

Status: in progress. The owner accepted decisions D1 to D8 as recommended on 2026-11-23, except D5, decided the
other way; the plan was revised after four independent reviews.

A plan for bringing two bodies of source work to one approach, so that every converted source reads, builds and
checks the same way:

- **The style conversion** (`claude/gallant-ride-uod18z`, 13 commits on `5fe1dcb`, one behind main): the Apple II
  Monitor, IIeEquates, the IIe firmware and DOS 3.3/3.2 converted to the style guide. The method is written down in
  [ConvertingSources.md](../ConvertingSources.md), and the decisions in `docs/conversions` on that branch.
- **The shared BASIC modules** (`agents/refactor-assembly-docs-structure`, 3 commits on `bd57e5c`, 22 commits behind
  main at `34eec8b`): AppleSoft and PET BASIC 1, 2 and 4 built from documented native modules. The code they share
  with Microsoft's 6502 BASIC is in `src/Retrocore.Basic/Roms/Microsoft6502Basic`, and every ROM is byte-identical:
  three AppleSoft builds (II Plus, IIe, enhanced IIe) and five PET builds (BASIC 1 original and revised, 2, 4 original
  and revised). The branch has no PR yet.

The two are not competing.

- **The BASIC branch** splits the sources into documented modules without changing a byte, and shares code across
  vendors. That is our step 4's first commit, taken further. It has no inventory or rename table, no checked
  citations, no structure and no strict lint. It also forked before #104 (`.using`), #106 (historical names, the
  style guide, the lint) and #108 to #116, so it has never met the lint.
- **The style conversion** does all of that, but checks less than the BASIC branch does: contracts only through a
  debugger run, and bytes only per whole build.

The plan takes the best of each.

## Where the two differ

| Topic | Style conversion | Shared BASIC modules | Common approach |
| --- | --- | --- | --- |
| Names | Full words (`CharacterOut`); old names in `Also:` | Microsoft's six-letter names stay current (`FNDLIN`, `LOWTR`) | Full words at the BASIC conversion (B6); until then, unchanged |
| Historical names | `;; Also: COUT (A2RM78)`: bibliography keys; assembler, links, debugger and editor resolve them | 17 prose `Also:` blocks naming vendor and source in words; the names don't resolve. Alias equates in `*.FloatAliases.asm` and `*.InterpreterAliases.asm` (`COMBYTE = COMBYT` in `AppleSoft.InterpreterAliases.asm`) | The standard form, with old names per build (D3); the alias equates become `Also:` |
| Structure | `.proc` per routine, scopes, structs | Top-level labels. 78 shared macros in 38 of 51 shared files, plus 33 vendor macros. Bodies end mid-routine and take label arguments | `.proc`, scopes, structs; the macro question is D2 |
| Builds that differ | Whole `.proc`s per build under `.if`, or `.if` inside a routine | Inline `.if` on macro parameters (more than 130 in shared code) | `.if` inside the routine (D5, decided) |
| Documentation in macros | DocComments 1.1 forbids it | Most shared documentation is inside macro bodies | The tools already read `;;` blocks in macro bodies. What they skip there is `Also:` (`AssemblyAlsoNames.cs`, `AssemblyPreprocessor.HistoricalNames.cs`) and scope and `.using` tracking (`DocumentationParser.ScopeTracker.cs`). See D2 |
| Lint | `; retrocore: style=strict` on every file | None; never run against main's lint | Strict on every file except the kept originals (`m6502.asm`, the `.mac` overlays) |
| Contracts | `Keeps:` worked out; checked by running DOS in the debugger | `In:`/`Out:` common, `Keeps:` rare (6 in shared code) | `Keeps:` worked out; checked by routine tests and the debugger |
| Byte check | The digest tests (`DosSourceTests`, `Apple2SourceTests`, `SystemSourceTests`) per whole build | Also each module against the MACRO-10 build's region, by Microsoft's names | Both, with the module check keyed by historical name (B4) |
| Build switches | Each root asserts its combinations in its source's PR: the Monitor's `MONITOR` and `ENHANCED`, the firmware's `ENHANCED`, DOS's `MASTER` and `YEAR` (A3). Before them, main checks only that `ENHANCED` goes with the IIe's `MONITOR` | Roots assert `TIME`, `EXTIO`, `DISKO` (the README says `EXTIO` and `DISKO` select no code, and `TIME` is only partly wired) | Every root asserts the combinations its digest tests check |
| Variant documentation | Spread over decisions and comments | A README table of every switch | A table per root or folder |
| Original sources | Cited in the bibliography | `m6502.asm` kept with tabs expanded, its license, and an LF-normalized SHA-256 in the `.mac` pragmas and tests | Both |

## Decisions for the owner

All eight were accepted as recommended (2026-11-23), except D5, which the owner decided the other way. The session
for B5 logs them in `docs/conversions/Basic.md` on `claude/basic-rename-table`, which reaches main through
`claude/basic-rename-ready`.

- **D1. Shared code across vendors.** Accept one module for code several vendors inherited from a common ancestor,
  with each difference a named switch or parameter and a one-line reason. *Recommended.* The trade-off is
  coupling: a change made for one vendor can move another vendor's bytes. The digest tests for every build catch
  that, so they must all run on any change to a shared module.
- **D2. Macros in the shared modules.**
  - **The facts.** 111 macros in all. Bodies end at bare labels that the next macro continues
    (`ASSIGNMENT_START` ends at `INPCOM:`, and `Basic4.asm` invokes `TIME_STRING_ASSIGNMENT` between it and
    `STRING_ASSIGNMENT`). Parameters include branch targets (`LIST_LINES 1, 1, 0, LINPRT, 0, READY`,
    `INTEGER_CONVERSION FRMNUM, POSINT_CHECK_TYPE`) and are checked by `.assert`. A few macros are invoked twice in
    one build's sources, in `.if` arms that exclude each other: `INTEGER_CONVERSION` and `MEMORY_ACCESS_WAIT` in
    `Basic1.asm`, and `LIST_LINES` and `PRINT_CORE` in `AppleSoft.Lister.asm` and `AppleSoft.Print.asm`. So every
    macro that defines a label is expanded once per build, in ROM order; `FLOAT_ONE`, expanded three times, defines
    none.
  - **The real problem.** An `Also:` inside a macro body is ignored, and DocComments 1.1 forbids documentation
    there. Documentation itself works: the BASIC branch's `AppleSoftDocumentationIsCleanForEachModel` finds `FADD`,
    `SQR` and about 30 others through macros.
  - **Options:**
    - (a) *Recommended:* keep the macros, and change the tools and rule. Honour `Also:` in a macro body expanded
      exactly once per build, at that expansion (two guard sites in the assembler, plus the lint's macro check). An
      `Also:` in a macro expanded more than once stays an error, and the name goes in prose. Rewrite DocComments
      1.1 to allow documentation in a macro body. Keep `Parameters:` and the `.assert` checks.
    - (b) Split each module at its join points into included files, with the parameters as constants defined before
      each `.include`. That is about 110 fragments. Label-valued parameters become alias symbols, and the
      parameters' checks move to the roots.
    - (c) Document each expansion site instead of the body. That loses the shared documentation.
- **D3. Historical names in the standard form, per build.**
  - Write `;; Also: COMBYTE (KEY)`. Remove the prose form, including its DocComments paragraph.
  - Keys go in [Bibliography.md](../Bibliography.md), which the BASIC branch does not have yet. Each source gets a
    key once it is in hand and its names are checked (ConvertingSources step 2). The candidates: Microsoft's 6502
    BASIC 1.1 source, Apple's Technical Information Library articles, Commodore's 1979 BASIC 4 listing, the
    Hoffmann-Vetter reconstructions.
  - A vendor's old name on shared code must resolve only in that vendor's builds. Otherwise `COMBYTE` would
    resolve in every PET build and can clash there with a real name. Options:
    - put the vendor's names in the vendor's own file, as an alias with `Also:`;
    - put an `Also:` under `.if` on the vendor switch (DocComments 1.2 allows per-branch sections);
    - add a tool feature to scope an `Also:` entry to a build.

    *Recommended:* the first, since it needs no tool change.
  - Test that each build resolves only its own vendor's names.
- **D4. Names.** Rename to full words in the BASIC conversion, keeping Microsoft's and each vendor's names in
  `Also:`. *Recommended*, by ConvertingSources' first naming rule (rename everything to the style). Alternative:
  keep Microsoft's names for the shared modules permanently, as a new exception to that rule.
- **D5. Builds that differ mid-routine.** *Decided by the owner:* an `.if` inside the routine, in a source's own
  builds and in shared modules alike, on a named switch (`ENHANCED`, `MONITOR = MONITOR_IIE`), with a comment where
  the switch alone doesn't say which builds take which branch.
  Showing the difference between versions is part of what the sources teach, and an `.if` shows that history far
  better than repeating the unchanged lines in a `.proc` per build. A whole `.proc` per build is for routines that
  differ throughout.

  Contracts: a mid-routine `.if` can't give each variant its own `Keeps:`. A routine with `.if`s inside it states the
  contract that holds in every build, and its prose says what a build does differently. (The recommendation had been a whole `.proc`
  per build in a source's own builds, with a mid-routine `.if` only in shared modules.)
- **D6. The MACRO-10 overlays.** Keep them as the selectable second source (`BasicSourceKind.Macro10`). They are
  the per-module byte oracle, not optional. Run the module comparisons in CI on every change to a shared module.
  *Recommended.*
- **D7. Finding shared sources.**
  - On the BASIC branch, `SourceIncludes.Neighbors` searches other projects only when the folder is named
    `Microsoft6502Basic` in `Retrocore.Basic`. `SdkDocumentationTests`, `OverlayBaseResolver` and `PetSdkModules`
    hard-code the same folder name, and `MachineSymbols` ranks the shared modules by their `MsBasic.` prefix.
  - *Recommended:* replace the check with a general rule that keeps the three layouts `OverlayBaseResolver`
    serves: repository, SDK (`Sdk/Roms/Microsoft6502Basic`) and the shipped extension. For example, a source in
    another project's `Roms` is found through the `.include` paths of the roots that use it.
  - Reconcile it with main's `NeighborFolders` (#110, #113) and with #116 (include sites from `.include` lines, merged
    as `34eec8b`).
- **D8. Licensing.**
  - Microsoft's code is MIT: keep `LICENSE` beside it, ship it in the SDK, and keep the notice in
    `extension/ThirdPartyNotices.txt` for the renamed modules derived from it.
  - Apple- and Commodore-derived code: settle whether the native sources may carry it, as the ROM sources already
    do. Keep listings used for checking out of the repository, as ConvertingSources step 2 says.

  *Recommended:* confirm the existing practice, and add a test that the SDK ships the license.

## Phase A: land the style conversion

Phase A and the BASIC rebase (B1) are independent: a test merge of the BASIC branch onto the whole style branch
gives the same four conflicts as onto main. A goes first only because its PRs are ready and smaller to review.

- [x] **A1. The method**, as a docs PR: `ConvertingSources.md`, the conversions README without its rows, this plan,
  the `UNKN` key, the pointers in the README, `AGENTS.md`, the style guide and two skills, and two style-guide rules
  made explicit. Split them out of `e5ecea0` (and `UNKN` out of `cd7d6c2`, whose IIEROM82 and IIETRM85 keys land
  with the Monitor); this plan, the pointer to its process, the two rules and the skill's lines that match them are
  new. `e5ecea0` also carries the four conversion logs (three say "Converted", DOS's "Decided"), which land with
  their sources (A2), and the DOS31 and DOS33 bibliography lines, which land with DOS.
- [ ] **A2. One PR per source:** the Monitor, IIeEquates, the firmware, DOS, in that order. Each carries its
  conversion log and its README row, is byte-identical by the digest tests, lint-clean, and contract-checked in the
  debugger.
  - *Status:* stacked on A1 as `claude/convert-monitor`, `claude/convert-iieequates`, `claude/convert-firmware`
    and `claude/convert-dos`.
- [ ] **A3. Assert the DOS builds:** `Dos33.asm` asserts its supported `MASTER` and `YEAR`, and `Dos32.asm` its
  `MASTER` (`YEAR` selects nothing in DOS 3.2), in the DOS PR. The Monitor's root asserts `MONITOR` and
  `ENHANCED` in the Monitor PR, and the firmware roots their `ENHANCED` in the firmware PR.
  - *Status:* in `claude/convert-dos`.

Exit for each PR: `EveryRepositorySourceIsCleanInTheEditor`, `SdkDocumentationIsClean` and the digest tests pass.

## Phase B: bring the BASIC modules to the method

- [ ] **B1. Rebase onto main.** It can start now.
  - Conflicts in a test merge: `.claude/skills/retrocore-native-assembly/SKILL.md`, `extension/README.md`,
    `src/Retrocore.Debug/Language/SourceIncludes.cs`, `tests/Retrocore.Tests/Retrocore.Tests.csproj`.
  - Check these by hand, though they merge silently:
    - `docs/DocComments.md`: drop the prose `Also:` paragraph now.
    - `tests/Retrocore.Tests/DocumentationTests.cs`: it asserts that the prose `Also:` is an unknown section;
      it's a list section on main.
    - `src/Retrocore.Debug/MachineSymbols.cs`: keep main's `ModuleFile` and add the BASIC branch's ranking of
      `AppleSoft.*` and `MsBasic.*`.
    - `src/Retrocore.Debug/Retrocore.Debug.csproj`, `tests/Retrocore.Tests/SdkDocumentationTests.cs`,
      `extension/src/test/suite.ts`.
  - `SourceIncludes.cs`: keep main's `NeighborFolders` and port the BASIC branch's cross-project search into it
    (D7 replaces it later). Taking main's side silently drops the search.
  - Exit: every ROM byte-identical; the full suite passes.
  - *Status:* pushed on `claude/basic-modules`; being integrated with B2 and B4 as `claude/basic-rename-ready`.
- [ ] **B2. Meet main's lint, still unconverted.**
  - Apply D3's form to the 17 prose `Also:` blocks: each vendor's names move to the vendor's own file as aliases
    with `Also:`, citing a key once B5 has the document in hand and checked.
  - Make the D2 (a) tool change, with its own tests and doc change.
  - Triage the lint's other findings on the branch's 15,500 added lines of assembly, which #106 to #115 never
    checked (`placement`, `sections`, `Entry:`).
  - Exit: byte-identical; `EveryRepositorySourceIsCleanInTheEditor` passes; no `also` errors.
  - *Status:* pushed on `claude/basic-standard-also`, with D2 (a)'s tool change on `claude/also-in-macros`; being
    integrated as `claude/basic-rename-ready`.
- [ ] **B3. Merge the BASIC modules to main**, unconverted, as their own PR. The conversion then goes module by
  module on main, as phase A did, rather than on one long branch of 32,000 lines.
- [ ] **B4. Make the tests rename-proof.** This is a gate before any rename.
  - The BASIC tests add over 900 `Symbols[...]` lookups, most by Microsoft's names, and the module comparisons match
    the MACRO-10 build's labels to the native build's by name (`AssembleShared`, `CompareRegion`).
  - Add a shared helper that looks a name up as its definition or as a historical name
    (`AssemblyResult.HistoricalNames`), and maps the MACRO-10 build's names to the native build's the same way.
  - Move every test to it.
  - Exit: renaming one label without changing the tests leaves the suite green.
  - *Status:* pushed on `claude/basic-rename-proof-tests`; being integrated as `claude/basic-rename-ready`.
- [ ] **B5. Inventory, rename table and decisions** (ConvertingSources steps 1 to 3). It depends on nothing above,
  so it can start now.
  - Every name per module and per build (the three AppleSoft and five PET builds), and the documents that give
    each.
  - Cross-cutting questions first: the vendor-only files (`Commodore.*`, `AppleSoft.HighResolution` ...) on the
    same schedule as the shared modules or later; structs for the variable entry, array header, string descriptor
    and FOR frame.
  - The owner settles them, and they are logged in `docs/conversions/Basic.md`.
  - *Status:* pushed on `claude/basic-rename-table`, with X1 to X16 settled by the owner.
- [ ] **B6. Convert, one PR per module or family** (step 4): `.proc`s, scopes, structs, named constants,
  `; retrocore: style=strict`, `Keeps:` worked out from the code. Shared modules first, then each vendor's. The
  alias files become `Also:`.
  - *Status:* step 1, the workspace, converted.
- [ ] **B7. Update the dependents:**
  - DOS: `docs/conversions/Dos.md` (which lands with A2's DOS PR) says "BASIC names wait for the BASICs' conversion";
    decision P2 is the BASIC vector.
  - the disassembler's names;
  - `docs/Apple2.md`, `docs/Pet.md`, the extension README.

Exit for each B6 PR:

- strict lint on every file but the kept originals;
- the digest tests and the module comparisons pass for all eight builds;
- every documented name has its Microsoft and vendor names in `Also:`, resolving only in their own builds (D3);
- routine tests for the module's routines with non-trivial contracts;
- AppleSoft and one PET checked for contracts in the debugger.

## Phase C: bring the BASIC branch's techniques to the method

- [ ] **C1. Add to `ConvertingSources.md`**, once B3 has landed, so the examples exist on main:
  - Routine tests: load the assembled bytes, prepare memory and registers, run one routine, and assert its
    documented `Out:` and `Keeps:`, error exits included. Use them for routines whose contracts a boot doesn't
    exercise. (`BasicSharedLineSearchTests` is the starting point; it checks `Out:` only.)
  - Per-module byte comparison against an independent oracle, keyed by historical name (B4).
  - Roots assert the combinations their digest tests check, as the Monitor's, the firmware's and DOS's do after
    phase A.
  - An `.assert` beside a "Falls into" comment where moving code would silently change behavior: a fall-through
    into another routine, or a byte shared between two routines. Not on every fall-through.
  - A table of each source's build switches.
  - The shared-ancestor rules (D1, D5).
- [ ] **C2. Apply them to the converted sources**, with or after each source's PR:
  - the asserted layouts and the switch tables;
  - routine tests where the debugger's boot run leaves gaps: RWTS seek and read, the file manager's FindFile, the
    Monitor's GetLine and its arithmetic.

Exit: ConvertingSources describes each technique with an example on main. Each converted source has its switch
table, and routine tests for the routines listed.

## Phase D: one set of docs

Each item lands with the PR it documents.

- [ ] **D-1.** `DocComments.md`: the prose `Also:` paragraph removed (in B1). Sections 1.1 and 2.4 rewritten for
  macro bodies (in B2, for D2 (a)). Old names per build (D3).
- [ ] **D-2.** `AssemblyStyle.md`: the shared-ancestor rules (D1, D5).
- [ ] **D-3.** The native-assembly skill: both branches' edits. Keep the BASIC branch's list of sources, its PET
  digest filter and its Learnings: PET BASIC 1 and 2 spill into their editor ROMs, and BASIC 1 has a patch at
  `$E7F3`. Keep the style branch's pointers to ConvertingSources and the logs.
- [ ] **D-4.** `docs/conversions/Basic.md` and its row in the conversions README.

## Order and ownership

A box is ticked in the PR that lands its item on main; an item in flight has a status line naming its branch.

The owner settles the decisions. Work is done by sessions, one per item, each following this plan and
`ConvertingSources.md`, and a coordinating session that starts them, tracks the items and reports to the owner.
For this effort the owner replaces the copilot-review-loop skill, its stacking rule and Copilot rounds included, and
the steward skill that leads into it, with the following; `pre-pr-self-review` still applies to behavioral changes.
Each session takes its branches to main this way:

- **Self-review**, by the owner's cycle
  ([An effective self-review cycle](https://claude.ai/artifact/VvBGDajXJzLwBxP6VvEfxs)).
  Reviewers are given the diff, the files it touches and the brief below, not the author's conclusions, and they
  only read: the session runs the checks and hands them the results.
  1. *Scripted checks*, before any reviewer and after every fix: the build, the tests and the lint; CI's later steps
     (every `node tools/Test-*.mjs`, the extension's `check:grammar`, `compile` and `test:grammar`); and the
     mechanical checks (citations, lineage, old names left behind). A kind of check made by hand twice becomes a
     test. Between fixes the targeted tests run; the full suite and CI's steps run before the closing pass and
     before pushing.
  2. *First pass*, once: Haiku, Sonnet and Opus in parallel on the whole diff, each starting from its own area.
  3. *Delta review*, after each fix: Haiku alone on the fix's diff, with the findings it addresses. It checks that
     the fix is right and broke nothing nearby; what it finds goes back to the fix.
  4. *Closing pass*: Sonnet and Opus on the whole diff. A finding goes back to step 3, not step 2.

  **The brief.** What counts: a wrong value, address or contract; a comment false for the code in a build it is in;
  a lost or mis-keyed historical name; a broken build or test. What does not: a comment that leaves out a use,
  names or switches that could also be defined, and what the scripted checks cover. Each finding gives its
  evidence (file and line, and the code, listing line or output that proves it; a document lacking a name means
  the whole text was searched) and a severity: must-fix (wrong behaviour or value, a broken build or test),
  should-fix (a false comment, a lost name) or nit (wording). A round is clean with no must-fix or should-fix;
  nits are fixed in passing and never cause another round. Each finding is verified before it is fixed, and the
  false ones counted. Each step reports, per stage and model, the findings by severity and the false ones, the
  tokens and minutes, the closing passes to clean, and anything found later.
- **The PR.** Against main, following the repository's PR template if there is one. Its body gives the change, the
  evidence (commands and results, naming skipped tests) and the review rounds. No Copilot review is requested.
- **CI.** The session waits for CI, subscribed to the PR's activity rather than polling, and squash-merges as soon as
  it is green, with the PR's title as the commit's.
- **A failure.** If CI fails for any reason, a flaky test or the infrastructure included, the session neither
  reruns it, merges, nor pushes a fix. It reports the job, the step and the log to the coordinating session,
  which takes it to the owner.
- **Stacks.** One PR at a time from each stack of branches. Once a branch merges, the next is rebased onto main
  (`git rebase --onto origin/main <old base> <branch>`), built, tested and reviewed again on what changed, then
  pushed and opened.
- **Main moving.** If main moves under an open PR and it conflicts, the session rebases, reruns the tests and a
  review round on the resolution, and pushes.

1. **Now, in parallel:**
   - A1 and A2 land, one PR at a time;
   - B1, B2 and B4, already pushed, are being integrated as `claude/basic-rename-ready`;
   - B5 is pushed, and B6's first step has started.
2. **Then:** B3, from that integration.
3. **After B3:** C1.
4. **After B3, B4 and B5:** B6, module by module, with B7 alongside; C2 goes with or after each source's PR.

**Tool files.** These branches and PRs touch the same files: #113 and #116 (both merged) change `SourceIncludes`;
the BASIC branch changes `SourceIncludes`, `MachineSymbols`, `SdkModules`, `OverlayBaseResolver` and
`PetSdkModules`. The open #118 changes the editor's include paths (D7's area) and #119 `DocComments.md` (D-1).
Until B1 lands, a change to those files names the others in its PR.

**If it stalls.** Each phase ends on main in a working state. A stalled B6 leaves some modules converted and the
rest unconverted, all byte-identical and lint-clean. A stalled B2 leaves the BASIC branch unmerged, with main
unaffected.
