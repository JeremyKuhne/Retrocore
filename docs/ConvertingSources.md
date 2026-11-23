# Converting sources to the maintained style

How Retrocore turns an old source (Apple's listing as typed in, a disassembly, an SDK source written before the
style guide) into one a developer of today can read, debug and change, without losing the way back to the
original documents. The rules a converted source follows are in [AssemblyStyle.md](AssemblyStyle.md); this guide is
why, and how the work is done. The decisions behind each converted source are logged in [conversions](conversions),
one log per source, which comes to main with that source.

The examples (`CharacterOut`, `CallFileManager`, `TextOn` ...) are names from the Monitor, IIeEquates, the IIe
firmware and DOS as converted. Those conversions come to main one source at a time, so until each lands, its
examples are not in main's sources.

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
  so a wrong `Keeps:` is caught; byte identity proves nothing about a comment.
- **Everything else**: the full test suite, and every source that includes or names the converted one.

## Naming rules learned so far

These were settled converting the Monitor, IIeEquates, the IIe firmware and DOS; each source's log, which comes
to main with the source, says where each was decided.

- **Rename everything to the style**, even an Apple name that already reads well (`HOME` becomes `Home`), so a
  source reads one way; the old name goes in `Also:`. Names a source defines for another source not yet converted
  (DOS's equates for the BASICs, the firmware's for AppleSoft's page zero) keep that source's names until it is
  converted.
- **Same job, same name** across models and versions (the original and Enhanced IIe, DOS 3.3 and 3.2); each build's
  definition carries that build's historical names, and the tools resolve an old name to the definition the build
  assembles.
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
- **Builds that differ mid-routine** keep one routine with `.if`s inside it, so the source shows how each version
  changed the one before; repeating the unchanged lines in a `.proc` per build hides that. A routine that differs
  throughout is a `.proc` per build. Its contract states what holds in every build
  ([the alignment plan](backlog/ConversionAlignment.md), D5).
- **A routine that descends through the builds is one lineage**: each of its definitions cites, in `Also:`, every
  document whose listing names it, in any build, so a name from any version finds it in all of them (ClearLineFrom
  carries the Apple II's CLEOLZ and the IIe's CLREOLZ). A document whose builds lack the routine is not cited.
- **A routine split over two files** (as Apple split RWTS for size) may be one `.proc` spanning the include.
- **Numbers shared between sources** (the firmware's function numbers, the mode bits) go in one shared file the
  sources include, with `.assert`s tying them to the tables that use them.
- **Fall-through** between routines is written as separate `.proc`s with a "Falls into X" comment; each keeps
  its own contract.

## Comments

- **Check every claim against the code**, and fix the ones that are wrong; a misleading comment costs a newcomer
  more than a missing one.
- **Bugs in the original are documented, not fixed**: the bytes stay, and the comment says what happens.
- **Explain for a newcomer**, linking the concept docs; keep the original's insight, rewritten in plain words.
- **Contracts are worked out from the code and everything it calls**, never copied from an old comment.

## For agents

- Read this guide, [AssemblyStyle.md](AssemblyStyle.md), [DocComments.md](DocComments.md) (section 2.4,
  `Also:`) and the [native-assembly skill](../.claude/skills/retrocore-native-assembly/SKILL.md) before converting.
- The logs in [conversions](conversions), one per source as each lands, are the precedents: follow a settled rule
  rather than re-deciding it, and bring a genuinely new question to the owner with a recommendation.
- Never change a byte; never edit files another agent owns; check every build after every change.
