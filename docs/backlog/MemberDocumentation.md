# Documented struct, union and enum members, with historical names

A specification for giving each member of a `.struct`, `.union` or `.enum` a `;;` block of its own, with every section a definition can have, `Also:` among them. Motivation: the DOS 3.3 conversion (decisions X1-X3) writes DOS's data layouts as structs (the file manager's parameter list, RWTS's IOB, the VTOC, the catalog and track/sector list) and needs each field to keep Apple's name (`Iob::COMMAND`, Also: IBCMD; `FileParameters::REQUEST`, Also: CCBREQ). Later sources (ProDOS, Pascal, SOS) have the same layouts.

## What works today

A probe (an assembly and `DocumentationSet.Create` over a strict file) shows the core already works. It ran on a branch whose `DocumentationParser.Definitions.cs` and `AssemblyPreprocessor.Ca65Types.cs` are identical to main's; make it the first test on main, to confirm:

```asm
; retrocore: style=strict
;; A probe.

.cpu Mos6502
.org $0300

;; An I/O block.
.struct Iob
    ;; The block's type.
    ;; Also: IBTYPE (TEST)
    TYPE .byte
    ;; The command.
    ;; Also: IBCMD (TEST)
    COMMAND .byte
.endstruct

;; The commands.
.enum Command
    ;; Seek only.
    ;; Also: IBCNUL (TEST)
    SEEK
    ;; Read.
    ;; Also: IBCRTS (TEST)
    READ
.endenum

;; Echoes <IBCMD> and <IBCRTS>.
Echo:
    lda #IBCMD
    ldy #IBCRTS
    rts
```

- **Assembler:** `lda #IBCMD` and `ldy #IBCRTS` assemble to 1 and 1. The preprocessor emits each member as a constant at the member's own source line (`AssemblyPreprocessor.Ca65Types.cs`), and `AssemblyAlsoNames.Apply` keys names by that line, so the member gets its historical names.
- **Documentation:** each member's block becomes a topic of kind `Member` named `Iob::COMMAND`, with its `Also:` (`DocumentationParser.Definitions.cs`, `Define`'s containers). Links `<IBCMD>` and `<IBCRTS>` resolve to `Iob::COMMAND` and `Command::READ`. A member reached through `.tag` (`WHERE .tag Pair`) works the same.

So this is mostly finishing and documenting what is there, not a new mechanism.

## What is missing

1. **Members inside an anonymous `.union` (or `.struct`) nested in a named one are named wrongly in the documentation.** In

   ```asm
   .struct Iob
       .union
           ;; Also: IBCMD (TEST)
           COMMAND .byte
           ;; Also: IBSTAT (TEST)
           STATUS .byte
       .endunion
   .endstruct
   ```

   the topics are `COMMAND` and `STATUS`, not `Iob::COMMAND` and `Iob::STATUS`; the assembler (correctly) defines `Iob::COMMAND`.
   - The cause: `DocumentationParser.Container` pushes `null` for the anonymous union, and `Define` qualifies by the innermost container only.
   - The fix: qualify by the innermost *named* container, as the assembler does (an anonymous union's members belong to the enclosing named type).
   - Check a named nested `.struct Inner` too. The assembler's name is `Outer::Inner::FIELD` when the inner type is named (follow `Ca65TypeLine`: a named nested type opens a `.scope`), so the documentation must produce the same name the assembler does in every case.
   - Add a test for each form: anonymous union, anonymous struct, named nested struct, `.tag`.

2. **The style lint's indentation inside types.** `DocumentationParser.Style.cs` expects every line between `.struct`/`.enum` and its end four columns in, so a nested `.union`'s members, written eight in, are reported. The rule should be:
   - a type's members are one level (four columns) in;
   - each nested `.struct`/`.union` body is one more level in, with the nested type's own `.union`/`.endunion` lines at its parent's member level;
   - `;;` blocks above a member sit at the member's indentation (the comment-indent rule already accepts that once the member's indentation is right).

3. **The lint's documentation checks on members.** Confirm, with tests, that a member's block gets the same checks as any definition's:
   - the `Also:` form and keys in the bibliography;
   - "is already the definition's name" and "is also a definition";
   - "has the historical name X too", for two members or for a member and another definition;
   - links.

   Two types may have members of the same plain name (`Iob::VOLUME`, `FileParameters::VOLUME`): that is not a clash, but the same *old* name on both is, as for any two definitions.
   - A member that has its own `;;` block must not also be listed in the type's `Members:` section: report "X has its own documentation; remove it from Members:" (`DocumentationResolver.Check`, beside the existing `Members:` check).
   - A member with both a block above it and a trailing `;;` comment: the existing "cannot document a definition that has its own trailing documentation" error applies; confirm it does for members.

4. **The editor.** Confirm, with tests where the language server has them, that a member's old name works like any other. Fix what doesn't:
   - hover on `IBCMD` in code says it is a historical name of `Iob::COMMAND`;
   - completion's filter text finds `Iob::COMMAND` when typing `IBCMD`;
   - workspace symbols list the member with its old names;
   - the information hint and quick fix on a use of `IBCMD` write `Iob::COMMAND`;
   - go to definition lands on the member's line.

   The quick fix must write the qualified name (`Iob::COMMAND`), since a member's plain name does not resolve outside its type.

5. **The debugger.** A watch or expression `IBCMD` resolves to the member's value (`SourceMapModule.TryResolve` handles constants; confirm with a test).

6. **Conditionals.** `.ifdef IBCMD` and `.if IBCMD = 1` see a member's historical name, as they see other definitions' (`AssemblyPreprocessor.HistoricalNames.cs`); confirm with a test.

## Docs

- `docs/DocComments.md`:
  - the topic-kind table: add a `Member` row (a member of `.struct`, `.union` or `.enum`, with its offset or value);
  - the "Trailing comments" rule: a member may have a trailing `;;` comment or a `;;` block above it, not both;
  - the `Members:` row: "for members documented by neither a block nor a trailing comment";
  - section 2.4 (`Also:`): members take `Also:` like any definition, a member's old name reaches the qualified member (`Iob::COMMAND`), and the quick fix writes the qualified name. Remove any wording that says members can't.
- `docs/NativeAssembly.md`, "Structures and enumerations": an assembled example with documented members and an `Also:`, and the nesting rules for names (anonymous union, named nested struct, `.tag`).
- `docs/AssemblyStyle.md`:
  - structure and union fields and enum members are UPPER_SNAKE (they are offsets and values: constants);
  - members are indented one level, and nested types one more;
  - document a member with a `;;` block when it has more to say than a few words or has a historical name, and with a trailing `;;` comment otherwise. A type whose members are all plain may use `Members:`.
- The native-assembly skill (`.claude/skills/retrocore-native-assembly/SKILL.md`) gets the same points briefly.

## Tests

In the existing classes where they fit (`HistoricalNameTests`, `StyleLintTests`, `NativeAssemblyDocsTests` for the docs' examples, the language server's tests):

- members' old names assemble (struct field, union field, enum member, `.tag` field, nested named struct), and a definition of the same name wins over a member's old name;
- topics and their names for each nesting form match the assembler's symbols;
- links to members by old name and by qualified name;
- the lint's `Also:` checks on members, the new `Members:` duplicate check, and the trailing-and-block error;
- the style lint's indentation inside nested types, clean and wrong;
- editor hover, completion, quick fix (qualified) and go to definition; debugger resolve; `.ifdef`/`.if`.

## Out of scope

`.using` (a separate backlog item); per-member `Model:` or `.if` inside a type; documentation export.

Done means:
- the full test suite passes;
- `EveryRepositorySourceIsCleanInTheEditor` and `SdkDocumentationIsClean` stay clean;
- the docs above are written;
- a strict file like the probe above (with the union form) is clean and behaves as described in the editor.
