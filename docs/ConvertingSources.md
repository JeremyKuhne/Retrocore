# Converting sources to the maintained style

How Retrocore turns an old source (Apple's listing as typed in, a disassembly, an SDK source written before the
style guide) into one a developer of today can read, debug and change, without losing the way back to the
original documents. The rules a converted source follows are in [AssemblyStyle.md](AssemblyStyle.md); this guide is
why, and how the work is done. The decisions behind each converted source are logged in [conversions](conversions),
one log per source, which comes to main with that source.

## Why: the audience and what success looks like

Retrocore's goal is a modern development experience on retro computers. Its sources are being written for a developer
who is **not** experienced on the old platform: someone who knows programming and today's tools, and meets the
Apple II's Monitor, DOS or a ROM for the first time. So:

- **The current name says what a thing is or does**, in full words: `CharacterOut`, `CallFileManager`,
  `FileParameters::REQUEST`. A reader should not need to know that COUT meant "character out" or CCBREQ "CCB
  request".
- **The old names are a bridge, not the language.** Every name a manual, listing or book gave a definition stays
  attached to it (`;; Also: COUT (A2RM78)`), so a developer coming from a 1978 manual, a 1983 listing, a magazine
  article or an old program can type the old name and land on the definition: the assembler accepts it, links
  and the debugger resolve it, the editor offers the new name, and hover cites the document.
- **Comments explain the machine**, not only the code: what a soft switch does, why a routine waits, what a
  screen hole is, linking to the docs that explain the concepts (`docs/Dos.md`, `docs/DiskII.md`).
- **Structure is visible**: routines as `.proc`s, families as scopes, data layouts as structs, values as named
  constants, so the tools (outline, hover, go to definition, the debugger's contracts) can show it.

Success is measured by what it enables:

- **Debugging** with modern tools: breakpoints and watches by either name, hover that explains, `Keeps:`
  contracts the debugger checks.
- **Writing new software**: completion and links that make the system's routines and layouts discoverable.
- **Disassembling legacy binaries** into code that is easy to follow: the disassembler names what a program uses
  of the ROMs and DOS by these sources' names (`jsr FileManagerJump`, not `jsr $03D6`), so every name fixed here
  improves every disassembly ([retrocore-disassembly](../.claude/skills/retrocore-disassembly/SKILL.md)).

When readability for a newcomer and fidelity to the original pull apart, readability wins in the name and the
structure, and fidelity is kept in `Also:`, in prose and in the bytes.

## The method

A conversion never changes a byte. It goes in five steps, each reviewed before the next.

### 1. Inventory

List every name the source defines (labels, constants, macros, `.set` names, struct and enum members), per file
and per build, by script, so coverage can be checked later. Note each build the source assembles (`.if` models,
years, variants) and every other source that includes it or uses its names (other ROMs, `Software/` programs,
C# that looks names up, tests).

### 2. Sources and citations

Find the documents that give the names: manuals, Apple's listings, published sources. For each, add a key to
[Bibliography.md](Bibliography.md) only once the document is in hand and checked.

- **Cite only what was checked.** A name cites a document (`(A2RM79)`) only when that document defines that name for
  the same thing, not just the same spelling. Check by script against the document's text where possible (a
  listing's labels at column 0, an OCR text allowing for its damage), and say how it was checked.
- **UNKN** ("unclear where this originated") is for a name no listed document gives but that may be someone's; a
  name that is obviously generated (a numbered local such as `CLREOP_2`) is dropped with no `Also:`, and a name the
  source says is its own (the SDK's) is not historical and gets no `Also:`.
- **The documents used for checking stay out of Retrocore.** From a listing or manual, only names and facts come
  into the repository; a listing kept for checking goes in a private place, never into the sources or docs. What
  vendor-derived code the sources themselves may carry is decision D8 of
  [the alignment plan](backlog/ConversionAlignment.md).

### 3. The rename table

Draft a table for the owner's review before converting anything: per name, the old name, the new name, its kind,
the documents that give the old name, the builds it exists in, and a one-line reason from the code. Put the
cross-cutting questions first (scopes, what is top level, layouts, constants), each with a recommendation and
alternatives, then the per-source ones. The owner settles them; record each decision with an ID and log it
([conversions](conversions)). A large source can be drafted in parallel, one part per person or agent, with one
brief; merge the parts, then settle where they disagree.

### 4. Convert

Convert a routine or two at a time, assembling and comparing every build after each change. To split the work:

- Split the source into subject files first, unchanged, and commit that alone: the bytes prove the split.
- Give each person or agent its own files in its own copy. A family spread over several people's files is written
  in each as `.scope X continued`; a shim in each copy opens every scope empty, and the integration turns each
  scope's first piece into its opening, with the scope's documentation.
- Each records the old names it renamed that other files use (`{"OLD": "Scope::New"}`), and references other files'
  definitions by their old names meanwhile (they resolve through `Also:` once converted).
- Integrate: apply the renames to the other files, **per build** where one old name means different things in two
  models, merge constants several people defined into one place, remove the shims, assemble, lint, test.

### 5. Verify

- **Bytes**: every build assembles to the same bytes as before (the digest tests, or a script comparing each
  build).
- **Lint**: `; retrocore: style=strict` on each converted file, and the editor's lint clean
  (`SdkDocumentationTests`).
- **Contracts**: run the machine in the debugger with contract checking on and exercise the code (each model),
  so a wrong `Keeps:` is caught; byte identity proves nothing about a comment. Routine tests cover what the run
  doesn't reach ([Checks that make a conversion safe](#checks-that-make-a-conversion-safe)).
- **Names and comments**: the module comparisons, the rename gate and the scripted checks, in the same section.
- **Everything else**: the full test suite, and every source that includes or names the converted one.

## Naming rules learned so far

These held across the Monitor, IIeEquates, the IIe firmware and DOS; the logs say where each was decided.

- **Rename everything to the style**, even an Apple name that already reads well (`HOME` becomes `Home`), so a
  source reads one way; the old name goes in `Also:`. Names a source defines for another source not yet converted
  (DOS's equates for the BASICs, the firmware's for AppleSoft's page zero) keep that source's names until it is
  converted.
- **Same job, same name** across models and versions (the original and Enhanced IIe, DOS 3.3 and 3.2); each
  definition carries its lineage's historical names (below), and the tools resolve an old name to the definition
  the build assembles.
- **Cite Apple's names as code would write them**: upper case, with underscores for dots (`B.FUNC` is `B_FUNC`).
- **Keep every documented name in `Also:`**, unless it would clash inside one assembly with another definition or
  old name; then it goes in prose ("Apple's listings call it SET80COL"), and the clash is noted. This, fill
  arithmetic written inline (below), and an equate the source never uses, left out and named in prose (DOS's
  MULT and ASLMEM), are the exceptions to [DocComments.md](DocComments.md)'s rule that a documented name is
  never dropped. Clashes with names in other modules, which assemble separately, are allowed.
- **Avoid names that shadow a top-level one** inside a scope (`Functions::GetKey`, not `Functions::ReadKey`
  beside the top-level `ReadKey`), since a plain name would silently change meaning.
- **Locations are PascalCase, values UPPER_SNAKE**: soft switches, variables and tables are locations
  (`Keyboard`, `TextOn`); keys, counts, masks, offsets, codes and struct fields are values (`KEY_RETURN`,
  `REQUEST_OPEN`, `Iob::COMMAND`). As the style guide's case rule says, an equate that names a location is
  PascalCase, like a label, even though it is written with `=`.
- **Switch pairs** are the feature plus `On`/`Off`/`State` (`TextOn`, `TextOff`, `TextState`); two-byte locations
  are `Name` and `NameHigh`.
- **Codes are prefixed constants**, not enums, where code uses them as operands or several sources share them
  (narrowing the style guide, which allows either), one prefix per set (`FIRMWARE_*`, `REQUEST_*`, `ERROR_*`,
  `RWTS_*`): short in operands, and each keeps its own `Also:`. A set private to one table, like the
  disassembler's addressing modes, may be an enum.
- **Data layouts are structs** with UPPER_SNAKE fields; where the source has its own copy of the layout, its bytes
  keep labels tied to the struct by `.assert`s (grouped after the data), and sizes are named `.sizeof` constants.
- **Shared bytes get scoped aliases** for each routine's purpose (`Checksum = LowResBaseHigh` inside the routine
  that uses it); only bytes several modules share stay top level.
- **The hardware's own short terms are fine** (`Aux`, `Rom`, `Irq`, `Store80`, `Page2`); no digit-led identifiers
  (`EightyColumns`, not `80Columns`).
- **Assembly-time arithmetic** is named only where the name explains something to the reader; pure fill
  computation is written inline, with the original's label in prose.
- **Locals that only jump on** (out of branch range) are `To` plus their target (`ToFirmware`).
- **Labels nothing references stay if a document names them**, as renamed locals with the documented name in
  `Also:`; undocumented ones are dropped.

## Structure techniques

- **Top level is for what everything reaches**: the widely called documented entry points, such as the I/O (each
  with its address in its `;;` comment and an `.assert * = $FDED, "..."`), vectors, and helpers every family uses.
  Everything else is in a family scope, even a routine programs call by address (`LowRes::Plot`).
- **A family spread through a ROM is one scope in pieces**: `.scope X`, then `.scope X continued` for each later
  piece, with a plain `;` comment saying which part.
- **Builds that differ mid-routine** keep one routine with `.if`s inside it, on a named switch (`ENHANCED`,
  `MONITOR = MONITOR_IIE`, a macro's `bitwiseNot`), so the source shows how each version changed the one before;
  repeating the unchanged lines in a `.proc` per build hides that. Where the switch alone doesn't say which builds
  take which branch, a comment names them. A routine that differs throughout is a `.proc` per build, each with its
  own contract: the Monitor's ClearLineFrom, DOS's `Rwts`. A mid-routine `.if` can't give each branch its own
  `Keeps:`, so **a contract holds in every build, or says which build differs** (the owner's D5, as narrowed on the
  Monitor's PR; [Basic.md](conversions/Basic.md), S11). `Operators::Not` in
  [MsBasic.OperandEvaluation.asm](../src/Retrocore.Basic/Roms/Microsoft6502Basic/MsBasic.OperandEvaluation.asm)
  does both:

  ```asm
      ;; Applies `NOT` to <Fac>.
      ;;
      ;; Where `bitwiseNot` is 1 (the PET), the result is the signed 16-bit complement of the integer; where it is 0
      ;; (AppleSoft), it is 1 for zero and 0 otherwise.
      ;; In: Fac = the operand
      ;; Out: Fac = numeric result
      ;; Errors: ILLEGAL QUANTITY where `bitwiseNot` is 1 and the operand is outside -32768 to 32767
      ;; Also: NOTOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
      .proc Not
      .if bitwiseNot
  ```

- **A label other routines enter in the middle of a routine** is an entry of the routine it sits in: a local,
  listed in the routine's `Entry:` section, with its old name in `Also:` (Basic.md, X2). Split off a separate
  `.proc` only where the code before the label is another routine, or a table needs the label's address. In
  [MsBasic.LineSearch.asm](../src/Retrocore.Basic/Roms/Microsoft6502Basic/MsBasic.LineSearch.asm), Microsoft's
  FLNRTS is `FindLine::Done`:

  ```asm
  ;; Entry:
  ;;   FromAddress = searches from the line at A (low) and X (high)
  ;;   Done = returns; <Statements::New> and List's range parsing branch here for a syntax error return
  ;; Also: FNDLIN (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
  .proc FindLine
  ```

  An `Entry:` item must exist in every build that assembles the routine, so a label only some builds define is
  described in the routine's prose instead (Basic.md, S1).
- **A routine that descends through the builds is one lineage**: each of its definitions cites, in `Also:`, every
  document whose listing names it, in any build, so a name from any version finds it in all of them (ClearLineFrom
  carries the Apple II's CLEOLZ and the IIe's CLREOLZ). A document whose builds lack the routine is not cited.
  The lineage stays within one vendor's builds; code several vendors share follows
  [Code several sources share](#code-several-sources-share).
- **A routine split over two files** (as Apple split RWTS for size) may be one `.proc` spanning the include.
- **Numbers shared between sources** (the firmware's function numbers, the mode bits) go in one shared file the
  sources include, with `.assert`s tying them to the tables that use them.
- **Fall-through** between routines is written as separate `.proc`s with a "Falls into X" comment; each keeps
  its own contract. **Where moving code would silently change behavior, an `.assert` goes beside the comment**, so
  the assembly fails instead: a fall-through into a routine in another file or macro, which a change in the order
  of the includes would separate, and a byte two routines share. Not on every fall-through: where the next
  routine is the next lines of the same file, the comment is enough. `Functions::Log` falls into a routine in
  another module
  ([MsBasic.Logarithm.asm](../src/Retrocore.Basic/Roms/Microsoft6502Basic/MsBasic.Logarithm.asm)):

  ```asm
      .assert * = Float::MultiplyPacked, "LOG must fall through to FMULT."
      ; Falls into Float::MultiplyPacked.
      .endproc
  ```

  and READ's mode is the operand that a skipped `lda #` takes from the next routine's first opcode
  ([MsBasic.VariableInput.asm](../src/Retrocore.Basic/Roms/Microsoft6502Basic/MsBasic.VariableInput.asm)):

  ```asm
          .assert INPUT_MODE_READ = $98, "READ's mode must be the TYA opcode its LDA immediate takes."
          .byte $A9                   ; LDA immediate takes AssignInputList's TYA opcode as INPUT_MODE_READ
  ```

## Code several sources share

Microsoft's 6502 BASIC is the first source whose code several vendors inherited: AppleSoft and PET BASIC 1, 2 and
4 are built from the shared modules in
[Microsoft6502Basic](../src/Retrocore.Basic/Roms/Microsoft6502Basic) and each vendor's own files. A source with a
common ancestor follows these rules (the alignment plan's D1 and D3).

- **One module for the ancestor's code**, each difference a named switch or macro parameter with a one-line reason
  (the shared folder's [README](../src/Retrocore.Basic/Roms/Microsoft6502Basic/README.md) lists them). The cost is
  coupling: a change made for one vendor can move another vendor's bytes, so every build's digest tests and module
  comparisons run on any change to a shared module.
- **A shared definition gives only the ancestor's names**, each citing every document that gives that name for it
  (`FindLine`'s FNDLIN cites Microsoft's source and the vendors' documents). A name only a vendor's
  documents give goes in the vendor's own historical-names file, as an alias that inherits the definition's
  documentation, so it resolves only in that vendor's builds
  ([Commodore.HistoricalNames.asm](../src/Retrocore.Machines.Commodore/Roms/Basic/Commodore.HistoricalNames.asm)):

  ```asm
  .scope Commodore

  ;; Inherit: <Float::SquareRootOfHalf>
  ;; Also: SQR05 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
  SquareRootOfHalf = Float::SquareRootOfHalf
  ```

  Tests hold both halves: `BasicAttribution.AssertSharedNamesAreMicrosofts`, and
  `VendorOldNamesResolveOnlyInTheirVendorsBuilds` in
  [BasicWorkspaceConversionTests](../tests/Retrocore.Tests/BasicWorkspaceConversionTests.cs).
- **On a definition only one vendor's builds assemble, the lineage stays within that vendor's line.** A routine
  every PET build has, even in two versions, cites the whole PET line, but not Apple's documents: BASIC 4's string
  allocator doesn't cite AppleSoft's ASTIL for GETSPA. Where a routine has two versions that are different code
  (BASIC's two string allocators and two collectors), the routine's own name still cites the whole line (GETSPA,
  GARBA2), but the labels inside each version cite only the documents of the builds that have it (Basic.md, E4 and
  E8a).
- **A name that exists in only some builds can't be named in a comment the other builds assemble too**: not as a
  link, an `Entry:` item or an `Inherit:` target. Write it in backticks or describe it ("BASIC 4's error-channel
  read"), or move the comment under the `.if` with its code. A shared comment that names a build describes it with
  its root's default switches, and should say "by default" where a switch could change it.

## Builds and their switches

- **Each root asserts the switch values its digest tests check**, so a build no test covers fails to assemble
  rather than giving bytes nobody checked. [Monitor.asm](../src/Retrocore.Machines.Apple2/Roms/System/Monitor.asm):

  ```asm
  ; Only the four builds the digest tests check (SystemSourceTests and Apple2SourceTests): the Apple II and Autostart
  ; Monitors, and the original and Enhanced IIe's.
  .assert MONITOR >= MONITOR_II && MONITOR <= MONITOR_IIE, "MONITOR is MONITOR_II, MONITOR_AUTOSTART or MONITOR_IIE."
  .assert ENHANCED = 0 || ENHANCED = 1, "ENHANCED is 1 for the Enhanced IIe or 0 for the original."
  ```

  The firmware roots assert their `ENHANCED`, `Dos33.asm` its `MASTER` and `YEAR`, and `Dos32.asm` its `MASTER`
  alone, since `YEAR` selects nothing in DOS 3.2. A switch that is renamed has its old name rejected, since an
  `.ifndef` default isn't reached through `Also:` and a stale predefinition would silently get the default
  ([Basic1.asm](../src/Retrocore.Machines.Commodore/Roms/Basic/Basic1.asm):
  `.assert .not .defined(BUFPAG), "Predefine INPUT_BUFFER_PAGE, not BUFPAG."`).
- **Each source has a table of its builds and switches**: per build, its root and switch values; per switch or
  macro parameter, what it selects. [Basic.md](conversions/Basic.md) opens with the eight BASIC builds, and the
  shared folder's README gives each module's choices.

## Comments

- **Check every claim against the code**, and fix the ones that are wrong; a misleading comment costs a newcomer
  more than a missing one.
- **Bugs in the original are documented, not fixed**: the bytes stay, and the comment says what happens.
- **Explain for a newcomer**, linking the concept docs; keep the original's insight, rewritten in plain words.
- **Contracts are worked out from the code and everything it calls**, never copied from an old comment.

## Checks that make a conversion safe

Byte identity proves the code is unchanged; it proves nothing about a name, a comment or a contract. These checks
cover the rest. Each began as something reviewers did by hand, and a kind of check made by hand twice becomes a
test.

### Routine tests

Load the assembled bytes, prepare memory and registers as the routine's `In:` says, run that one routine until it
returns or reaches an error exit, and assert its documented `Out:` and `Keeps:`, error exits included. Use them for
routines whose contract a boot doesn't exercise: a debugger run checks only the paths it takes. From
[BasicExpressionRoutineTests](../tests/Retrocore.Tests/BasicExpressionRoutineTests.cs), run in AppleSoft and PET
BASIC 4:

```csharp
BasicMathMachine machine = new(apple);
SetWord(machine, "LinearIndex", multiplicand);
machine.Memory[machine.Address("Addend")] = (byte)multiplier;
int error = machine.Address("Variables::ElementAddress::ToOutOfMemoryError");

int reached = machine.CallUntil("Variables::MultiplyUnsigned", [error], a: multiplier >> 8);
```

The test then expects the error exit for a product past 16 bits, and otherwise the product in X, A and Y and
`LinearIndex` zero, as its documentation says.

- **`Keeps:`**: pass distinctive values in (`$5A` in X, `$A5` in Y) and check them after, as
  [BasicStatementRoutineTests](../tests/Retrocore.Tests/BasicStatementRoutineTests.cs) does for `IsLetter`.
- **Every claim**, flags included: the character reader's carry for a digit and zero for a null or colon.
- **A documented quirk is pinned** by a test, so it isn't "fixed" later: `ReadLineNumberSendsAGotoTokenHighByteIntoOn`.
- **Names are looked up rename-proof** (below), so the test survives the next conversion step.

The BASIC routine tests are `Basic*RoutineTests`, on the machines in
[BasicMathMachine](../tests/Retrocore.Tests/BasicMathMachine.cs) and `PetRoutineMachine`. They don't replace the
debugger run of step 5; for that, add a false `Keeps:` as a control and see it reported, so a clean run means the
check was live.

### Per-module byte comparison against an independent oracle

The digest tests say that a build changed, not where. Where an independent second source of the same bytes
exists, compare each module against it. BASIC's MACRO-10 overlays (`applesoft.mac`, `Basic1.mac`, `Basic2.mac`,
`Basic4.mac`, on Microsoft's `m6502.asm`) build every BASIC a second way, and stay as that oracle (D6). Each
`Basic*ConversionTests` assembles both, and checks in every build that each old name the converted files give has
the overlay's value for that name, and that each definition the files make reaches the overlay by its name or an
old name ([BasicMathConversionTests](../tests/Retrocore.Tests/BasicMathConversionTests.cs)):

```csharp
AssemblyResult native = AssembleAppleSoft(model);
AssemblyResult legacy = SdkModules.AssembleAppleSoft(Path.Join(AppleFolder, "applesoft.mac"), model);
BasicWorkspaceConversionTests.CheckAgainstOverlay(
    native, legacy, [.. Shared, AppleNames], minimum: 240, Exempt(native, AppleNames), scoped: true);
```

The comparison is keyed by historical name (`BasicNames.TryGetCounterpart` finds a definition in the other build
by its name or any of its `Also:` names), so it survives the rename it checks. `minimum` keeps it from passing with
nothing compared, and the exemptions are the SDK's own names, which no overlay gives. The same tests check the
citations: each key is in the bibliography, and each vendor's names cite only its own documents, Microsoft's or
UNKN.

### Rename-proof lookups and the rename gate

A test that looks a label up by its old name breaks when the conversion renames it, so look names up as a
definition or as a historical name. The BASIC tests go through [BasicNames](../tests/Retrocore.Tests/BasicNames.cs)
(`result.Symbol("FNDLIN")` reaches `FindLine` through its `Also:`), and the debug hosts through
`AssemblyResult.SymbolsWithHistoricalNames`. [BasicRenameGateTests](../tests/Retrocore.Tests/BasicRenameGateTests.cs)
proves it: it renames labels in a copy of the sources, each keeping its old name in `Also:`, and runs the BASIC
test classes it lists against the copy, which must keep every ROM's bytes and pass unchanged. A new test class that assembles
BASIC joins its list, or the list of those it leaves out, with a reason. Before converting a source whose tests look
names up, move them to such a lookup first (the alignment plan's B4).

### The scripted checks

Before the first review, and after every fix, script what reviewers used to check by hand:

- **Historical names in prose**: scan the comments for any name that is a definition's `Also:` name, written as
  prose rather than the current name or a link; keep it only where it is history ("Apple's listing calls it
  SET80COL").
- **Each comment's build condition**: list every changed comment with the builds that assemble it (the `.if`
  branches around it), so each is read against those builds. A comment true of only one build is the finding
  reviews meet most.
- **Links per build**: a link in a comment must name a definition in every build that assembles the comment. A
  check that resolves a conditional source's links against all its builds at once can accept a definition some
  builds lack, so check each build; [BasicBuildLinkTests](../tests/Retrocore.Tests/BasicBuildLinkTests.cs) does
  for the eight BASIC builds.
- **Citations**: every key in the bibliography, every name in the document it cites, and each lineage complete
  (`FirmwareLineagesCiteBothListings` and `DosLineagesCiteBothVersions` in
  [ConvertedSourceTests](../tests/Retrocore.Tests/ConvertedSourceTests.cs), and the conversion tests above).
- **Old names left behind**: code in a converted file uses the current names (`ConvertedSourcesUseCurrentNames`, for
  the Apple II's sources), and nothing else still uses an old one: other sources, `Software/`, C#, docs and the
  rename table.

## Review

A conversion reaches main through the owner's self-review cycle, set out in
[the alignment plan's process](backlog/ConversionAlignment.md#order-and-ownership): the scripted checks; a first
pass by several models in parallel on the whole diff; a delta review of each fix; a closing pass by Opus alone,
split by area for a large diff; and the PR once a closing pass finds no must-fix or should-fix. What it has taught:

- The findings that recur are comments true of only one build, and stack and register contracts. Hand reviewers
  the list of comments with their build conditions, and ask them to check each comment against each build.
- Reviewers get the diff and the brief, not the author's conclusions. Each finding is verified before it is
  fixed, and the false ones counted; nits are fixed in passing and never cause another round.
- A check a reviewer made by hand twice is scripted: the per-build link test came from nine findings in the
  closing reviews of BASIC's interpreter files.
- The logs record decisions, not progress: what was decided and why, with an ID, and what was found in the code
  and documented. Review rounds, commands and their results go in the PR.

## For agents

- Read this guide, [AssemblyStyle.md](AssemblyStyle.md), [DocComments.md](DocComments.md) (section 2.4,
  `Also:`) and the [native-assembly skill](../.claude/skills/retrocore-native-assembly/SKILL.md) before converting.
- The logs in [conversions](conversions), one per source as each lands, are the precedents: follow a settled rule
  rather than re-deciding it, and bring a genuinely new question to the owner with a recommendation.
- Never change a byte; never edit files another agent owns; check every build after every change.
