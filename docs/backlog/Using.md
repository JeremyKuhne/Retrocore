# `.using`: names from another scope without qualifying them

A specification for a native-dialect directive that makes a scope's names usable without their `Scope::` prefix,
for a stretch of source. Motivation: the IIe firmware's routines work on the 80-column firmware's state, which the
style guide puts in a scope (`EightyColumns::CursorColumn`, `EightyColumns::Mode` ...). Without `.using`, every use is
qualified; with it, the code reads `lda CursorColumn`.

## Syntax

```text
.using Scope[, Scope ...]
```

- Each operand is a scope or `.proc` name as code at that point would write it: plain (`EightyColumns`), qualified
  (`Firmware::EightyColumns`), or absolute (`::EightyColumns`). It names an existing scope, defined before or after
  the directive, resolved by the same rules as a qualified name's first part (NativeAssembly.md, "Scopes").
- Native dialect only. A `.using` line cannot carry a label.

## Extent

A `.using` applies from the line after it to the end of the scope or `.proc` that contains it, or to the end of the
file it is in for one at file level. It does not reach into included files, and an included file's `.using` does not
leak into the including file. There is no `.endusing`: a stretch that needs one is a scope.

A `.using` inside a continued scope's piece applies to that piece only.

## Resolution

A plain name `N` used where `.using A, B` applies resolves in this order:

1. The scopes that contain the use, innermost first, as now (a name defined in the current scope or an enclosing one
   wins, including later in the source).
2. The scopes named by the `.using` directives in effect, innermost directive first; within one directive, its scopes
   together. If two scopes at the same step define `N`, the use is an error that names both
   ("'N' is in both A and B; qualify it").
3. Historical names (`Also:`), as now.

So a `.using` never changes what an already-resolving name means; it only lets an otherwise unresolved name be found.
Qualified names (`A::N`, `::N`) are not affected. Cheap locals (`@x`) and unnamed labels are not affected.

A `.using` that names a scope with no names the code uses is not an error, but the editor reports it as unnecessary
(information, like an unused import). One that names no scope is an error: "No scope named 'X' for .using."

## Definitions are not affected

`.using` changes how names are looked up, not where they are defined: a label or constant defined after `.using A` is
defined in the current scope, not in `A`. Exports and `.global` are unchanged.

## Tools

- **Assembler:** `AssemblyNameResolver` records each `.using` with the scope it applies in and its extent, and
  `ResolveName` adds step 2. The preprocessor's mirror of the resolver's rules (`AssemblyPreprocessor.Scopes.cs`,
  for conditionals that test names) follows the same rule. A new `AssemblyStatementKind.Using` in `Assembler.cs`'s
  directive table; `DirectiveDocs.cs` documents it for hover.
- **Debug file:** unchanged (it records definitions, which `.using` doesn't move).
- **Documentation links:** a `;;` comment's plain links resolve as the code around it would: `DocumentationParser`
  records the `.using` scopes in effect at each comment, and `DocumentationResolver`'s scoped lookup (`Scoped` and
  `Lookup`, DocComments.md section 4.3) adds them after the enclosing scopes.
- **Editor:** hover, go to definition and find references on a plain name use the same order
  (`SourceAnalysis.Find`, `LanguageHost.SitesAt`); completion offers the used scopes' names unqualified, after the
  enclosing scopes' own. Outline is unchanged.
- **Grammar:** the VS Code extension's TextMate grammar highlights `.using` as a directive.
- **Style lint:** no new rule. (The guide may say: prefer `.using` over repeating a scope prefix in a routine that
  uses several of the scope's names.)

## Tests

- A name found through `.using`; the same name defined locally wins over it; a qualified name unaffected.
- Extent: ends with the enclosing `.proc`/`.scope`; at file level, ends with the file; not across `.include`.
- Two used scopes defining the same name: an error naming both, only where that name is used.
- `.using` of an unknown scope: error. Of a scope defined later in the source: works.
- Inside a continued scope's piece: applies to that piece only.
- Conditional assembly testing a name found through `.using`.
- Documentation: a `<CursorColumn>` link in a comment inside the extent resolves to `EightyColumns::CursorColumn`.
- Editor: hover and go to definition on a name found through `.using`.
- Bytes: a source rewritten from qualified names to `.using` assembles to the same bytes.

## Docs

`docs/NativeAssembly.md` ("Scopes": a `.using` subsection with an assembled example), `docs/DocComments.md`
(section 4.3: the resolution order), `docs/AssemblyStyle.md` (when to use it), and the directive index.

## Out of scope

`.using` in the ca65, Merlin and MACRO-10 dialects; aliasing a scope (`.using E = EightyColumns`); importing a single
name.
