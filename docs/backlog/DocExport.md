# Backlog: exporting documentation

Status: **not started**. A follow-up to the [documentation comment format](../DocComments.md).

## Goal

Generate a cross-linked HTML reference for documented sources across the SDK: the Apple II family's Monitor,
internal firmware, AppleSoft (`applesoft.mac` over `m6502.asm`), Integer BASIC, Programmer's Aid #1, Disk II, DOS
and slot ROMs, and the Model I's Level II, Level I and character-generator sources. It plays the role Sandcastle or
DocFX plays for XML documentation comments.

## Approach

Use [Natural Docs](https://www.naturaldocs.org) to render the HTML, fed by our own generator, which reads the
sources through the assembler.

`tools/Build-Docs`:

1. Assembles each source with the same options as the debugger, once per model.
2. Collects the `;;` documentation comments, resolving `Inherit:`, `Include:` and links as the format
   specifies.
3. Writes one Natural Docs **Text File** input per source. Each topic gets:
   - its keyword and title (`Routine: PLOT`), taken from the definition the comment documents;
   - a generated code block with its address in each model, its value, or its parameters;
   - its sections, with compact sections expanded into definition lists;
   - links rewritten to the exact topic titles it emitted;
   - an "Inherited from" note on inherited text.
4. Runs a pinned Natural Docs, downloaded the way `tools/Fetch-M1Dependencies.ps1` fetches other tools.

Rendering of links in the HTML:

| Link | Becomes |
| --- | --- |
| A code link | Natural Docs' exact topic link |
| `$address`, `@model` | The resolved name |
| An external link | A Natural Docs `at` link |
| A `doc:` link | A URL relative to the reference |

## Findings from the spike (2026-11-06)

The spike ran Natural Docs 2.3.1 on converted copies of `Monitor.asm`, `Firmware.Enhanced.asm` and
`applesoft.mac`, plus an edge-case file. Its output, converted sources, configuration and converter script
are in `artifacts/naturaldocs-spike`, which git ignores. Serve `html/` over HTTP to view it; the pages load
through JavaScript.

What worked:

- **The output is good:** one page per file, a menu grouped by topic type, search, and definition-list
  sections. There were 145 topics in the Monitor and 146 in the Enhanced firmware.
- **Assembly is built in.** Extra extensions (`s`, `inc`, `mac`) and a custom `Table` topic type need only
  two small project config files.
- **Cross-file links work:** `<PLOT>`, `<COUT>` and `<SCRN>` resolved between files.
- **Macros with parameters and code examples render cleanly.**
- **Speed:** the whole run took a few seconds.

Limits, and how generating the input avoids them:

| Limit with sources fed directly | With generated input |
| --- | --- |
| Assembly has only basic support: every topic needs a `Keyword: Title` line, which repeats the label | The generator writes it |
| A topic must start its own comment block; a comment line directly above it (an overlay `;@REPLACE`, a banner) hides it | The generator emits clean blocks |
| It doesn't read code: no addresses, values, or check that a title matches the label | The generator adds them from the assembly |
| Only explicit `<Name>` links; qualified (`<Monitor.asm.SETCOL>`) and scoped (`<AM::IMP>`) names don't resolve | Links are resolved before export and rewritten to exact titles |
| A routine documented in both branches of an `.if` appears twice | One topic with model notes |

## Constraints

- **License.** Natural Docs is AGPLv3. The JavaScript and CSS it copies into the output keep that license; the
  documentation text stays ours. Download it at build time, never vendor it, and keep the export an optional
  step outside the normal build and tests.
- **Runtime.** Natural Docs 2.3.1 is a .NET Framework executable: built in on Windows, Mono on Linux and
  macOS. Version 2.4, in beta, has native binaries.

## Open items

- **Inline code.** Natural Docs has no inline-code style. Backticks may need to become a CSS class in the
  generated input.
- **Publishing.** Decide where the reference lives: a CI artifact, GitHub Pages, or packaged with the SDK.
- **Fallback.** If the AGPL dependency or the repeated-title model becomes a problem, the same generator could
  emit HTML directly, at the cost of maintaining search, menus and styling ourselves.
