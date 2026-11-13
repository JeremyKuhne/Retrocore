# Documentation comments

Status: **implemented** (2026-11-06); see section 7 for where.

This is the format for documenting assembly sources in this repository: the SDK's ROM sources, samples,
and any program assembled with Retrocore. It plays the role C#'s XML documentation comments play for .NET:

- The **language server** renders it in hover and completion.
- The **debugger** shows each frame's routine documentation in the Variables pane, and checks `Keeps:`
  contracts when routines return.
- The **source generator** copies summaries into the `/// <summary>` comments of exported C# members.

Exporting an HTML reference is a follow-up, planned in [the doc export backlog](backlog/DocExport.md). This
specification keeps the comment text compatible with [Natural Docs](https://www.naturaldocs.org) formatting
(headings, lists, code blocks, links) so that export can use it, but nothing here depends on it.

## 1. Where documentation comments go

### 1.1 The `;;` marker

`;;` is the documentation marker, as `///` is in C#. Only lines that start with `;;`, after any indentation,
or trailing comments that start with `;;`, are documentation. A plain `;` comment is always an ordinary
comment, whatever it contains and wherever it is.

```asm
;; Plots one lo-res block in the current color.
;; In:    A = row (0-47), Y = column (0-39), COLOR = the color in both nibbles
PLOT:
    lsr a                           ; $F800 ordinary comment
```

To every assembler and dialect we support, `;;` is still an ordinary comment, so documented sources stay
valid for ca65, Merlin 32 and MACRO-10. In MACRO-10, `;;` inside a macro definition traditionally means
the comment is not copied into expansions. Documentation never goes inside a macro body, so the two uses
don't meet.

### 1.2 What a comment documents

A **documentation comment** is a block of consecutive `;;` lines. It documents the definition on the line
directly below it. Conditional lines (`.if`, `.else`, `.endif` and the rest of the family) may come between
them, as in a routine whose label differs by model. A blank line or a plain `;` line between the block and
the definition is a lint error,
not a silent change of meaning. A `;;` block followed by an instruction or anything else that can't be
documented is also a lint error.

| Definition below the comment | Topic kind | Facts the tools add |
| --- | --- | --- |
| A label followed by an instruction | Routine | Address in each model, and the model if under `.if` |
| A label followed by data (`.byte`, `.word`, `.res`, a data macro, `.repeat`) | Table | Address and size |
| `NAME = value` or `.equ` | Constant | Value |
| `.set NAME, value` | Variable | First value |
| `.macro NAME params` | Macro | Parameter list |
| `.enum`, `.struct`, `.union` | Enum, Struct | Members and their values or offsets |
| `.scope`, `.proc` | Scope | Members |
| `.define NAME` | Definition | Parameter list |

Rules:

- **Several labels in a row** share the comment of the first one. The others are listed as entry points (see
  `Entry:` below), unless they have their own comment.
- **Trailing comments** document the definition on their own line when they start with `;;`: a constant in
  an equate list, or a member of an `.enum` or `.struct`. For example, `KEY_CR = $8D ;; Control-M, Return`.
  The SDK sources' trailing address comments (`; $F800`) stay ordinary comments.
- **Headings over a group** are plain `;` comments. A `;;` block above a definition that has its own trailing
  `;;` comment is a lint error, because it reads as the group's heading but would document only the first
  definition:

  ```text
  ; Ports.
  DATA_PORT = $10                     ;; the data
  STATUS_PORT = $11                   ;; the status
  ```
- **The file comment** is a `;;` block at the top of the file, after any `; retrocore:` pragma, followed by a
  blank line. It becomes the file's topic and is exempt from the blank-line error.
- **Explicit topics.** A `;;` block whose first line is a Natural Docs keyword line (`Section: Title`,
  `Group: Title`, `Topic: Title`) is a free-standing topic, kept as written, and is followed by a blank line.
  Use `Group:` to divide a long file in the reference's menu.
- **Conditional code.** A definition documented in more than one branch of an `.if` is one topic. Each
  branch's sections apply to the models that branch assembles for; the tools label them by model.
- **MACRO-10 sources** follow the same rules. Overlay markers (`;@REPLACE`, `;@END`) are plain comments and
  never part of a documentation comment. Microsoft's `m6502.asm` is pinned and can't gain `;;` lines, so its
  routines are documented from the overlay (an `;@INSERT BEFORE` block holding the `;;` comment) or with
  `Include:`.
- **Undocumented definitions** stay out of the reference, unless they are exported or listed in an `Entry:`
  section.

## 2. Structure of a comment

The compact form is the default. Each section takes one line, the layout the SDK sources already use:

```asm
;; Plots one lo-res block in the current color.
;; In:    A = row (0-47), Y = column (0-39), COLOR = the color in both nibbles
;; Uses:  A, GBASL, GBASH, MASK
;; Keeps: X, Y
;; See:   <SCRN>, <SETCOL>
PLOT:
```

When the entries are long, or need more than one line, a section can use the expanded form instead: the
heading on a line of its own, then one entry per line. Both forms mean the same thing and can be mixed in one
comment:

```asm
;; Reads a line of input into IN ($0200) after printing the prompt character in PROMPT.
;;
;; Backspace deletes a character, Control-X cancels the line, and the right arrow copies the
;; character under the cursor.
;;
;; Out:
;;   X       = the line's length
;;   IN,X    = a carriage return, ending the line
;; Uses:  A, Y
GETLN:
```

- **Summary:** the text before the first section or empty `;;` line, which should be one sentence. Hover,
  completion, the debugger's documentation scope and the generated C# `<summary>` use it.
- **Remarks:** further paragraphs, after an empty `;;` line, that come before the first section.
- **Sections:** a comment line that starts with a recognized section name and a colon (section 2.1) starts a
  section, with or without an empty `;;` line before it.
  - **Compact form:** the content follows on the same line. A section continues onto the next line when that
    line is indented by two or more spaces, which lets a long comma list wrap.
  - **Expanded form:** the heading stands alone, and the indented lines below it are its entries.
  - **Entries:** in `In:`, `Out:`, `Errors:`, `Entry:` and `Parameters:`, each entry is `name =
    meaning`. Compact entries are separated by commas, and a comma inside a meaning is fine, because an entry
    only starts at `, NAME =`. Natural Docs' `name - meaning` is accepted too. A compact section with no `=`
    is a bare list of names (`Out: BASL/BASH`), documenting what is set without saying more. In `Uses:`,
    `Keeps:` and `See:`, entries are a comma list, and an item may end with a note in parentheses:
    `BAS2L (scroll)`.
  - **Names** in entries and lists are the routine's own CPU's registers and flags (section 2.2), symbols,
    numbers, and combinations of them such as `A1L/A1H`, `IN,X`, `SOFTEV+1` and `IN..IN+$FF`. Apple's convention of a
    pair name such as `A1` for `A1L`/`A1H` is accepted when both halves exist. `none`, `nothing` and `all`
    are accepted in `Uses:` and `Keeps:`.
  - **Other headings:** any other line ending in a colon, after an empty `;;` line, is a plain heading, as
    in Natural Docs.

Both forms parse to the same sections, so every tool treats them alike.

### 2.1 Sections

| Section | XML equivalent | Content | Checked by the tools |
| --- | --- | --- | --- |
| `In:` | `<param>` | Entries: register, flag or memory name `=` its meaning | Names must be the CPU's registers or flag words, or symbols |
| `Out:` | `<returns>` | Entries for the results, flags included: `carry = set when the key was Return` | Same |
| `Errors:` | `<exception>` | How failure is reported: `carry = set on a checksum error`, or error codes | |
| `Uses:` | | A comma list of what the routine changes beyond `Out:` | Optionally checked by the debugger |
| `Keeps:` | | A comma list of registers, flags and memory the routine preserves | Checked by the debugger (section 5) |
| `Entry:` | | Other labels that enter this routine, each with how it differs: `PLOT1 = skips the address calculation` | Names must be labels inside the routine |
| `Calls:` | | Hooks or routines called indirectly, which the tools cannot see | |
| `Cycles:` | | Timing, as text or a formula: `17`, `26 + 27A + 5A^2, halved` | |
| `Stack:` | | Bytes of stack used, including calls | |
| `Model:` | | `Original`, `Enhanced`, or both (on IIe sources) | Generated from `.if` when omitted |
| `Parameters:` | `<param>`, `<typeparam>` | Macro and `.define` parameters | Names must match the signature |
| `Members:` | | Enum or struct members not documented with trailing comments | Names must be members |
| `Example:` | `<example>` | Text and code blocks | |
| `See:` (or `See also:`) | `<seealso>` | A comma list of links | Every link resolves |
| `Deprecated:` | `[Obsolete]` | Why, and what to use instead | Callers get a warning |
| `Inherit:` | `<inheritdoc>` | See section 3 | Target resolves; no cycles |
| `Include:` | `<include>` | See section 3 | File and topic exist |

There is no `Flags:` section: flags go in `In:` and `Out:` with the registers. The check reports one and says
so.

Memory names are symbols such as `GBASL`, or ranges such as `IN..IN+$FF`.

### 2.2 Registers and flags

Names follow the CPU the routine is assembled for, taken from the assembly, so a file that switches CPUs is
checked line by line:

- **Registers** are the CPU's own letters: `A X Y S P PC` on the 6502; `A F B C D E H L I R`, the pairs
  `AF BC DE HL IX IY SP PC` and the alternates `AF' BC' DE' HL'` on the Z80, where alternates may run
  together, as in `C'H'L'`.
- **Flags** are always words, the same on every CPU, so a flag never reads as a register: the Z80's `C` is
  the register and its carry is `carry`. An entry says what the flag means when set, or says set and clear:
  `Out: zero = found`, `Out: carry = clear on success`.

| Word | 6502 | Z80 | 6809 | Meaning |
| --- | --- | --- | --- | --- |
| `carry` | C | C | C | Carry out of the top bit, or no borrow (6502) or a borrow (Z80, 6809) from a subtract or compare |
| `zero` | Z | Z | Z | A zero result, or an equal compare |
| `negative` | N | S | N | Most significant bit of the result, a negative number in two's complement; Zilog calls it the sign |
| `overflow` | V | P/V | V | A signed result out of range |
| `parity` | | P/V | | An even number of 1 bits, after logical operations, rotates and IN |
| `half-carry` | | H | H | A carry out of or borrow into bit 3, for DAA |
| `subtract` | | N | | The last arithmetic was a subtract, for DAA |
| `decimal` | D | | | Binary-coded decimal arithmetic |
| `interrupt` | I | | I | IRQ masked |
| `fast-interrupt` | | | F | FIRQ masked |
| `entire` | | | E | Complete register state stacked for RTI |

A flag's letter is reported with its word (`name the C flag by its word, 'carry'`), as are branch conditions
such as `NZ`, which say the same as `zero` with its meaning turned around. The words come from the CPU's
instruction-set description (the `flag` lines of `OpcodeTables.txt` and `Z80Isa.txt`), with what each flag
means; hovering a flag's word in a `;;` comment shows its letter and meaning, as in **negative (N) flag**. A
new CPU names its flags with the same words, adding one only for a flag no CPU has had.

### 2.3 Text formatting

These follow Natural Docs:

- Paragraphs are separated by an empty `;;` line.
- Bullet lists: lines starting with `-`, `*` or `+`.
- Definition lists: `name - description`, aligned or not. Inside the sections of 2.1, `name = description`
  is the usual spelling.
- Code blocks: lines starting with `>`, or a block between `(start code)` and `(end)`.
- Emphasis: `*bold*` and `_underline_`.
- Links: see section 4.

Two additions:

- Inline code in backticks: `` `lda #$A0` ``.
- A **register or parameter reference** in braces, such as `{A}`, refers to an entry of the routine's own
  `In:`, `Out:` or `Parameters:` section. This is the equivalent of `<paramref>`. The tools check the name,
  and the reference renders in code style.

## 3. Inheriting and including documentation

### 3.1 `Inherit:`

The `<inheritdoc>` equivalent copies another topic's documentation.

```asm
;; Inherit: <GETLN>
;; Does not print the prompt first.
GETLN1:
```

- **Target.** It can be any link target (section 4). Without one, `Inherit:` alone means:
  - the same name in the other model's branch, for a topic under `.if`;
  - otherwise, the first label of the routine this label is an `Entry:` of.
- **Merging.** Like `<inheritdoc>`, the comment's own parts win, and each part is inherited whole:
  - The summary, the remarks, and each section are inherited unless the comment gives its own.
  - A section given locally replaces the inherited one completely.
  - Local text after `Inherit:` (on the following lines, before any section) is added after the inherited
    remarks.
- **Choosing sections.** `Inherit: <GETLN> In, Out` inherits only those sections, like `<inheritdoc path>`.
- **Chains** are followed. A cycle, or a target with no documentation, is an error.
- **When shown,** inherited text carries an "Inherited from GETLN" note.

Typical uses:
- alternate entry points;
- one model's version of a routine documented once for both;
- a wrapper that only switches ROM banks and calls the real routine, such as the Monitor's `HOME` and the
  firmware's routine for it.

### 3.2 `Include:`

The `<include>` equivalent takes documentation from a documentation file instead of a symbol:

```asm
;; Include: <docs/firmware/cx-functions.txt#Function $10>
```

The file is in Natural Docs text format. The part after `#` names a topic in it, and its documentation is
merged like `Inherit:`. Use it for documentation shared by several sources, or written outside the code,
such as a protocol both a ROM and a program follow. The path is relative to the source file, then to the
repository root.

## 4. Links

### 4.1 Syntax

| Form | Meaning |
| --- | --- |
| `<Target>` | Link to a target, shown as its name |
| `<text at Target>` | Link shown as `text` (Natural Docs' named-link syntax) |
| `https://...` | A bare URL is linked as is |
| `<text at https://...>` | Named external link |
| `<text at doc:path/file.md#anchor>` | Link to a documentation file in the repository |

### 4.2 Targets

| Target | Resolves to |
| --- | --- |
| `NAME` | A symbol, macro or definition (4.3) |
| `Scope::NAME`, `::NAME` | A qualified symbol, as the assembler resolves it |
| `Module:NAME` | A symbol in a named SDK module, from its root file's name: `Monitor:COUT`, `Firmware:B_FUNC`, `AppleSoft:CHRGET`, `Slot7:DriverEntry`, `Level2:READY` |
| `$F800` | The documented label at that address, in the topic's model and memory area |
| `NAME@Original`, `NAME@Enhanced` | That model's version of a name that differs between models |
| `NAME#Section` | A section of a topic: `<PLOT#Keeps>` |
| `.directive` | The assembler's documentation for a directive: `<.repeat>` |
| `LDA`, `lda` | The instruction's documentation, when no symbol has that name |
| `File.asm` | A file's topic |

### 4.3 Resolving a plain name

A plain `NAME` is looked up in this order. The first match wins.

1. The comment's own `{parameters}` and section entries, when written `{NAME}` (section 2.3).
2. The assembler's scope rules, from the scope the definition is in, outward to the file's root.
3. The rest of the current assembly: other files included or composed into it, such as `m6502.asm` under
   `applesoft.mac`.
4. The other SDK modules for the same machine (such as the Monitor, firmware, AppleSoft, Integer BASIC, DOS
   and slot ROMs on the Apple II, or the Model I's ROMs), using the build for the topic's model.
5. Macros and `.define`s, then directives and instructions.

If a step finds the name in more than one place, the link is **ambiguous**. Examples are a name defined in
both firmware sources, or in both branches of an `.if` with different meanings. The lint reports it, the
link renders to the first match, and the author qualifies it (`Monitor:`, `@Enhanced`).

An unresolved link is a warning in the editor. It renders as plain text, never as a
broken link.

### 4.4 Rendering

| Output | A code link becomes | An external or `doc:` link becomes |
| --- | --- | --- |
| Hover and completion | A Markdown link that opens the definition's file and line | A Markdown link |
| Generated C# docs | `<see cref="..."/>` when the target is an exported member, otherwise `<c>NAME</c>` | `<see href="..."/>` |

`$address` and `@model` links render as the resolved name, so a reader sees `COUT` even when the source says
`<$FDED>`.

## 5. Checked contracts

- **`Keeps:`.** When a call to a documented routine returns (the PC returns to the caller with the stack
  back at its depth, as for cycle counting), the debugger compares each listed register, flag (by its word) and
  memory location with its value at entry. A difference is reported with the routine, the item and both values. It
  is a debugger warning, optionally a stop, not an assembly error. `Keeps: none` documents that nothing is
  preserved. Sections that apply only to one model (from `.if`) are checked only on that model. The launch
  option `checkContracts` selects `warn` (the default: a Debug Console message), `stop` (also stops, with
  reason `exception`, at the instruction after the call) or `off`. With `warn`, ticking the **Routine broke
  its Keeps: promise** exception filter in VS Code's Breakpoints view also stops; its hover explains it. The
  filter is listed only when some loaded source has a `Keeps:` section and `checkContracts` is not `off`.
- **`Uses:`** is checked the same way when the launch option `checkUses` is true: a change to `A`, `X` or
  `Y` (on the 6502) or `A`, `B`, `C`, `D`, `E`, `H`, `L`, `IX` or `IY` (on the Z80) that the routine's
  `Uses:`, `Out:` and `Keeps:` sections don't mention is reported.
- **The lint** (language server) checks:
  - section names and entries against section 2.1, and registers and flags against the routine's CPU
    (section 2.2);
  - `{references}`, links and `Inherit:` targets;
  - that `Entry:` labels lie inside the routine;
  - that each `;;` block sits directly above a definition it can document (section 1.2);
  - uses of a definition with a `Deprecated:` section, at each use;
  - that every exported symbol is documented, by its own comment or as an `Entry:` (or stacked label) of a
    documented routine.

## 6. Open questions

- **Automatic linking.** Linking bare names that match symbols, without angle brackets, would suit the
  existing comments. It risks false links for short names such as `A1` or `CH`.

## 7. Implementation

| Part | Where |
| --- | --- |
| Parser and model (`;;` blocks, sections, links) | `src/Retrocore.Assembler/Documentation/DocumentationParser*.cs`, `DocumentationComment`, `DocumentationSection`, `DocumentationText` |
| Topics with assembly values, `.if` merging | `DocumentationSet`, `DocumentationTopic` |
| Links, `Inherit:`, `Include:`, the lint | `DocumentationResolver*.cs` |
| Hover, completion, editor diagnostics | `src/Retrocore.Debug/Language/DocumentationMarkdown.cs`, `LanguageWorkspace.Documentation.cs` |
| `Keeps:`/`Uses:` checks and the Variables scope | `src/Retrocore.Debug/DebugContracts.cs`, `DebugSession.cs` |
| C# summaries for exports | `src/Retrocore.Generators/ExportDocumentation.cs` |
| Highlighting | `extension/scripts/generate-grammar.mjs` (`comment.line.documentation.retrocore`) |

The SDK's ROM sources use the format, and `SdkDocumentationTests` keeps them free of lint problems.
