# Lint exclusions: rule IDs and ignoring one rule where it doesn't fit

A specification for naming each documentation and style lint rule and for turning a rule off for a line, a
definition's comment, or a whole file. Motivation: the style guide's checks (`; retrocore: style=strict`,
docs/AssemblyStyle.md) are all or nothing per file today. When one rule doesn't fit one place, the only remedies are
to bend the source to the rule or to change the rule for everyone. Examples:

- a data table whose columns read best past 120 columns;
- a word that is also a documented name ("Pascal 1.1" beside a `Pascal` scope, before scopes were exempted);
- a historical listing's spelling quoted in a comment.

## Rule IDs

Every lint diagnostic gets a rule ID: those of `DocumentationParser` (the line rules, `DocumentationParser.Style.cs`,
and the comment rules in `DocumentationParser.cs`), of `DocumentationResolver.Check`, and the editor's own
(`LanguageWorkspace.Documentation.cs`: deprecated uses and historical names in code). An ID is a short lowercase
name with hyphens. The editor shows it as the diagnostic's code (LSP `Diagnostic.code`), and messages printed
outside the editor (the tests, a command-line lint) end with it in brackets:
`Line is over 120 columns. [line-length]`.

| ID | Messages |
| --- | --- |
| `line-length` | Line is over 120 columns. |
| `ascii` | Write plain ASCII ... |
| `trailing-doc` | Put ;; documentation above the definition, not after it. |
| `label-alone` | Put the label X on its own line. |
| `address-name` | Name X for what it is: a name that is only an address says nothing. |
| `column-zero` | Put definitions, labels and block directives at column 0. |
| `indent` | Indent instructions and data 4 columns. Indent this line of the macro N columns. |
| `comment-indent` | Indent this comment like the code it describes (N columns). |
| `unlinked-name` | Link X as \<X\>: it names a documented definition. |
| `link` | No definition, file or address named 'X'. |
| `ambiguous-link` | 'X' names definitions in more than one place; qualify it ... |
| `also` | Every `Also:` message (form, bibliography key, clashes). |
| `sections` | The section-form messages: `Entry:`, `Members:`, `Parameters:`, `Inherit:`, `Include:`, `Flags:`, register lists, `name = meaning` entries, `{name}` references. |
| `historical-name` | The editor's information on a use of an old name in code (the quick fix stays). |
| `deprecated` | A use of a definition with a `Deprecated:` section. |
| `undocumented-export` | Exported 'X' has no ;; documentation. |
| `placement` | The `;;` placement errors of `DocumentationParser.cs` (errors only, so never ignorable). |
| `exclusion` | Problems with an exclusion itself: unknown ID, misplaced, unused (never ignorable). |

The IDs are a public contract once released: a rule can be split (an old ID then still covers both), but not
renamed. `DocumentationDiagnostic` gains a `Rule` property, and each `warn`/`diagnostics.Add` call site passes its
ID. A test checks that every diagnostic the parser and resolver can produce has an ID from the table.

## Where an exclusion goes

All three forms use the `; retrocore:` pragma words. An exclusion is `ignore=` and a comma-separated list of rule
IDs; a rule may be narrowed to names with a colon and `|`: `ignore=unlinked-name:Pascal|Control`. Narrowing by name
applies to the rules that report a name (`unlinked-name`, `link`, `ambiguous-link`, `address-name`, `label-alone`,
`historical-name`, `deprecated`); for the others it is an error ("line-length takes no names").

Text after ` -- ` is the reason, which the tools ignore and reviewers read:
`; retrocore: ignore=line-length -- the table's columns line up with the listing's`.

### A file

On the first line, after the other pragma words:

```text
; retrocore: style=strict ignore=unlinked-name:Pascal
```

It applies to the whole file and not to files it includes.

### A line of code

As the line's own trailing plain comment (a `;`, not `;;`, comment, which the style guide allows on code):

```asm
    .byte $C1, $D0, $D0, $CC, $C5, $A0, $DD, $DB, $C1, $D0, $D0, $CC, $C5 ; retrocore: ignore=line-length
```

It applies to that line only.

### A comment block

On a plain comment line directly above a `;;` block:

```asm
; retrocore: ignore=unlinked-name:Run -- Run is the verb here
;; Run starts the test ...
.proc Start
```

It applies to every line of that `;;` block (the topic's comment), not to the code below it. A `;;` block must sit
directly above its definition (DocComments.md, section 1.2), so the exclusion goes above the block, never between
the block and the definition.

## Rules for exclusions

- Only warnings and information can be ignored. Assembler diagnostics and documentation errors cannot: an
  `ignore=` naming a rule that only produces errors is itself an error.
- An unknown rule ID is a warning ("No lint rule named 'X'."), with the known IDs as completion in the editor.
- An exclusion that suppresses nothing is information ("Nothing here breaks line-length; remove the exclusion."),
  so they don't outlive their reason. This one can't be ignored.
- A file-level exclusion does not need `style=strict`; it applies to the rules that run without it too.
- Exclusions change no bytes and nothing the debugger, hover or documentation export shows, except that the
  pragma comment line is not exported.

## Tools

- **Parser:** `DocumentationParser.IsStrict` becomes a small pragma reader that returns the strict flag and the
  file's exclusions; the line and block exclusions are read where the parser already reads lines and comment
  blocks. The assembler's own pragma reader (`AssemblyPreprocessor.cs`, `dialect=`) must ignore the new `ignore=`
  word rather than reject it.
- **Filtering:** one place, after `DocumentationResolver.Check` and the parser's diagnostics are gathered, drops
  what an exclusion covers and adds the unused-exclusion information. The editor
  (`LanguageWorkspace.Documentation.cs`, `DocumentationDiagnostics`) and `SdkDocumentationTests` both go through it.
- **Editor:** the rule ID as `Diagnostic.code`; a quick fix on each ignorable diagnostic, "Ignore <rule> on this
  line" (or "for this comment"), writing the pragma comment; completion of rule IDs after `ignore=`; hover on a rule
  ID describing the rule.
- **Grammar:** the VS Code extension's TextMate grammar highlights `; retrocore:` lines' words.

## Tests

- Every diagnostic has a rule ID from the table.
- Each form (file, line, comment block) suppresses its rule there and nowhere else; a block exclusion does not reach
  the code below the definition.
- Narrowing by name suppresses only those names; a name on a rule that takes none is an error.
- An unknown ID warns; an unused exclusion is information; an error can't be ignored.
- The assembler accepts a file with `ignore=` on its first line and assembles the same bytes.
- Editor: the diagnostic's code, the quick fix's edit, and completion after `ignore=`.

## Docs

`docs/AssemblyStyle.md` (a short section: the IDs, when an exclusion is right, and that a reason is expected),
`docs/DocComments.md` (section 5, the lint, with the table of IDs), and `docs/NativeAssembly.md` (the pragma's
words).

## Out of scope

Repository- or folder-wide settings files; ignoring assembler warnings; per-dialect rules.
