# Pascal style

How the SDK's Pascal sources are written: Apple Pascal's and Apple III Pascal's system programs, decompiled and
named, each of which compiles with its own Compiler back to the same segments. This guide is the Pascal counterpart
of [AssemblyStyle.md](AssemblyStyle.md) and [DocComments.md](DocComments.md), and it is written for the same reader:
a developer new to the p-System. Names say what things are, and the names in the old listings and manuals stay
attached as historical names. [ConvertingSources.md](ConvertingSources.md) explains why. [Pascal.md](Pascal.md)
covers the tools, decompiling and compiling.

## Checking a source

The lint checks what can be checked without Apple's disks. In VS Code its problems appear as you type, in any
`retrocore-pascal` file (`.text`, `.pas`, `.pascal`). A test, `PascalSourceTests.SdkSourcesPassTheLint`, runs it over
every `.TEXT` file under `src/Retrocore.Pascal/Sdk`, each program read from its main file through its includes; until
the first source lands it reports itself inconclusive. It checks the following rules:

| Rule | What it checks |
| --- | --- |
| `line-length` | Lines of 80 columns at most, the Editor's screen |
| `tab` | No tabs: the Editor has none |
| `file-size` | Each file within the strictest Editor's size, measured as below |
| `file-name` | A `.TEXT` file's name in capitals, at most 15 characters with the suffix |
| `include` | Every `(*$I*)` file present beside the file that includes it |
| `comment` | No `{ }` comments |
| `case` | Reserved words, and standard identifiers the program doesn't declare again, in capitals |
| `name` | Defined names in PascalCase, without `_`, except the names the code file keeps |
| `name-8` | Names distinct in their first 8 letters from those in the same and enclosing scopes |
| `doc-placement` | Each `(** *)` comment documents a declaration |
| `doc-section` | Only the sections below; a heading near one, such as `Param:` or `Return:`, is reported |
| `also` | `Also:` items written `NAME (KEYS)`, keys in [Bibliography.md](Bibliography.md), each name given once |
| `link` | Every `<Name>` link names a declaration |

With the disks, the round trip checks the rest: the source compiles to the same segments (section 1).

## 1. Every source compiles back

Every SDK Pascal source compiles with its own Compiler to the same segments as Apple's code file:
`--pascal compare` says "The code files' segments are the same". There are no reading copies that don't compile;
fuller explanation goes in `docs/`. A source keeps the options it needs to compile so, such as `(*$S++*)`, or `(*$U-*)`
for a system program, with a comment saying why.

The Compiler keeps none of the following in the code file, so they can change: names (except those section 3 keeps),
comments, layout, and declarations that leave the p-code the same. Anything that changes the p-code cannot, and the
round trip decides which is which.

## 2. Files and layout

- **Includes.** A program is a main file and `(*$I NAME.TEXT*)` includes, each small enough for every version's
  Editor (below). A file holds whole procedures. A nested procedure goes with its parent unless that would make the
  file too big.
- **File names.** Apple's, in capitals as the disk keeps them (`BODYPART1.TEXT`), as `(*$I*)` names them: at most 15
  characters with `.TEXT`, so 10 before it.
- **Lines.** 80 columns at most, the Editor's screen; spaces, not tabs.
- **Indentation.** Two spaces a level, as the decompiler writes. `BEGIN` goes on its own line at the statement's
  level, the body two spaces in, and `END` under `BEGIN`. `THEN`, `DO` and `OF` end the line they belong to. One
  statement goes on a line.
- **Each file opens** with a `(** … *)` comment saying what it holds: the segment and its number, which file
  includes it and where, and the procedures it defines, in nesting order.

### The Editor's size

A file must open in every version's Editor, so the limit is the strictest Editor's: **16,348 bytes** of text as the
disk stores it, with leading blanks compressed and each page's padding left out. That is 1.1's and 1.2's Editor on a
64K Apple II. Apple's *Operating System Reference Manual* (A2POSRM) gives the Editor's largest file as about 18,400
bytes, 38 blocks. That holds for 1.0, but not for 1.1, whose Editor has less room.

The size was measured on the emulator by opening a file of a known size in each version's Editor. The table gives
the largest file that loaded; one more line gave `ERROR: BUFFER OVERFLOW`.

| Editor | Machine | Largest file |
| --- | --- | ---: |
| Apple Pascal 1.0 | Apple II Plus, 64K | 18,910 bytes |
| Apple Pascal 1.1 | Apple II Plus, 64K | 16,348 bytes |
| Apple Pascal 1.2 | Apple II Plus, 64K | 16,348 bytes |
| Apple Pascal 1.2 | Apple IIe, 128K | 17,385 bytes |
| Apple Pascal 1.3 | Apple IIe, 128K (it needs 128K) | 39,894 bytes |
| Apple III Pascal 1.0 | Apple III, 256K | at least 56,791 bytes¹ |
| Apple III Pascal 1.1 | Apple III, 256K | 32,208 bytes |
| Apple III Pascal 1.2 | Apple III, 256K | 32,208 bytes |

¹ A larger file never finished loading: no error was shown.

The Editor counts the text as the disk stores it. A file of indented lines held 29,421 characters, but only 16,345
bytes as stored. Lines of 61 bytes, unindented, stopped at 16,348.

A file at the limit leaves the Editor no room to insert text, so keep files well under it.

## 3. Names

- **Case.** Reserved words and Pascal's standard identifiers are in capitals (`IF`, `BEGIN`, `INTEGER`, `WRITELN`,
  `NIL`, `TRUE`, `UNITREAD`). Every name the source defines is in PascalCase, in full words (`CurrentSymbol`,
  `WriteLinkerInfo`).
- **Distinct within 8 letters.** The Compiler reads a name's first 8 letters, with case folded. Two names in the same
  scope, or in a scope and one around it, must differ there: `WriteLinkerInfo` and `WriteLine` are both `WRITELIN`.
- **No underscores.** UCSD Pascal leaves `_` out of names, so `Last_Unit` and `LastUnit` are the same name.
- **Kept as the code file has them.** Segment, program and unit names are stored in the code file. So is a unit's
  interface text, which the programs that `USES` the unit compile against, so its interface names stay too. A modern
  name for any of them goes in the doc comment's prose. `--pascal compare` leaves the interface text out, so the
  round trip doesn't check it; a check for it comes with the first unit's source.
- **Constants and enumeration values** are in PascalCase like every other name, since capitals are for the reserved
  words. A set of related constants gets a shared prefix only where a name would clash or be unclear
  (`CspReleaseSegment`), and never a type suffix.
- **Same thing, same name.** Every version's sources use 1.3's names where their code matches, with new names only
  for what differs.

## 4. Historical names

A definition's names from documents are kept three ways:

1. **In its doc comment**, as an `Also:` section like the assembly's: `Also: GENLDC (UCSD20)`, each name with the
   [bibliography](Bibliography.md) keys of the documents that give it. Cite only what was checked against the
   document's text.
2. **In the rename log**, `docs/conversions/<source>.md`: the new name, the old name, the citation and the decision.
3. **In the editor**: an old name used in the source, or linked, leads to its definition for hover and go to
   definition, as `Also:` does in the assembler.

A historical name that would clash with another definition, that is one of Pascal's reserved words or standard
identifiers (`EXIT`, `SCAN`), or that wasn't checked, goes in prose, as in the assembly sources. The decompiler's own generated names (`P12`, `L059A`) aren't historical.

## 5. Doc comments

- **Marker.** `(** … *)` documents a declaration; `(* … *)` is an ordinary comment; `(*$ … *)` is a compiler
  option. Every Compiler in scope reads `(**` as an ordinary comment: a program with `(** *)` comments and the same
  program with `(* *)` compile to the same segments on Apple Pascal 1.0, 1.2 and 1.3 and Apple III Pascal 1.0, 1.1 and
  1.2. `(**)` is an empty ordinary comment. `{ }` comments aren't used.
- **Placement.** A doc comment goes above the declaration it documents, at its indentation: a procedure, function,
  segment, constant, type, variable, field, enumeration value or parameter. A short one may follow a field, variable
  or constant on its line, and documents the names its statement declared. In a record's variant, a field's
  comment goes inside the parentheses, `1: (Radius: INTEGER (** … *))`; after the `)` it documents nothing. A
  file's first `(** *)`, after any ordinary comments, with a blank line after it, documents the file.
- **Summary.** The first paragraph is the summary, which hover and the outline show. Further paragraphs are remarks.
- **Sections** go on lines of their own after the summary, each continuing onto lines indented two or more spaces:

  | Section | Content |
  | --- | --- |
  | `Parameters:` | Each parameter, `Name = what it is`; for a `VAR` one, what it gets back |
  | `Returns:` | A function's result |
  | `Uses:` | Globals the routine reads or changes that its parameters don't say |
  | `Errors:` | The Compiler's error numbers it reports, or the execution errors it can raise |
  | `See:` | Links |
  | `Also:` | Historical names (section 4) |

- **Links.** `<Name>`, `<Outer.Inner>` (a nested routine, a record's field) or `<text at Name>`, as in the
  assembly's. A link may name a historical name.

```pascal
(** Generates the p-code that loads an integer constant: SLDC for 0 to 127,
    else LDCI of its magnitude, then NGI if it is negative.

    Parameters: Value = the constant
    See: <GenerateByte>
    Also: GENLDC (UCSD20) *)
PROCEDURE GenerateLoadConstant(Value: INTEGER);
```

## 6. Readability beyond names

Named constants, enumerated types, and named record or array types may be added wherever the p-code stays the same,
which the round trip decides. Two examples change it:

- a `CONST` of -1 compiles to `LDCI 1, NGI`, where a literal `-1` compiles to `SLDC 1, NGI`;
- a subrange type checks assignments with `CHK` where range checking is on.

## 7. The system's globals

One include for each version declares the system's globals and procedures, named once: SYSCOM, the file and unit
tables, and the procedures programs call. It lives in `src/Retrocore.Pascal/Sdk/System/<machine>-<version>/`. The
compilers include it (compiled `(*$U-*)`), and SYSTEM.PASCAL's source defines it. The decompiler reads it to name the
words a system program uses, such as AIIFORMAT's `SYS630`, and to give `.PUBLIC` names to system programs' assembled
procedures. The compilers' conversion starts it with what they use, and SYSTEM.PASCAL's conversion completes it.

## 8. In the editor

The language server reads a Pascal file as part of its program: the file in its folder that starts `PROGRAM`, `UNIT`
or `SEPARATE UNIT` and includes it. It offers:

- **hover** on a declared or used name, or on a link in a doc comment. It shows what the name declares
  (`FUNCTION Outer.Inner`), its doc comment's summary, remarks and sections, and the documents an `Also:` item cites.
  Hover on a historical name says whose it is;
- **go to definition** and **find all references**, by a name, a historical name, or a link;
- **the outline**: the file's routines, constants, types and variables, with what each routine or record declares
  under it;
- **the lint's problems**, as you type.

## Decisions

The owner settled each of these as recommended.

- **PS1. The file size limit.** The strictest Editor's, for every version's sources, so that a file opens in any
  version's Editor. The manual's figure gave 18 pages. Measured, the limit is 16,348 bytes, from 1.1's and 1.2's
  Editor on a 64K Apple II (section 2).
- **PS2. File names.** Apple's own style, in capitals as on the disk (`BODYPART1.TEXT`), as the Compiler's listings
  and `(*$I*)` give them.
- **PS3. Underscores.** Never in a defined name, since UCSD Pascal leaves them out.
- **PS4. Units' interface names.** Kept as the code file has them, like segment names, with a modern name in the doc
  comment's prose, and checked against the unit's code file when the disks are there.
- **PS5. Constants and enumeration values.** PascalCase, with a prefix only where needed.
- **PS6. `{ }` comments.** Not used: only `(* *)` and `(** *)`, as the decompiler writes.
- **PS7. Doc-comment sections.** The six in section 5, named as the assembly's where they mean the same.
- **PS8. The system-globals include.** In `src/Retrocore.Pascal/Sdk/System/<machine>-<version>/`.
- **PS9. Editor support and the lint.** A Pascal document model in the language server, as BASIC's has. The lint
  gives its diagnostics, and a test runs it over every SDK Pascal source.
