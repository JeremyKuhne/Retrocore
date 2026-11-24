// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  <c>.using</c>, which makes scopes' names usable without their <c>Scope::</c> prefix to the end of the enclosing
///  scope or file (docs/NativeAssembly.md, "Using a scope's names").
/// </summary>
[TestClass]
public sealed class UsingTests
{
    private const string EightyColumns = """
        .scope EightyColumns
        CursorColumn = $57B
        Mode = $4FB
        .endscope

        """;

    /// <summary>
    ///  A name is found through <c>.using</c>; the same name defined in the enclosing scope wins; a qualified name is
    ///  not affected.
    /// </summary>
    [TestMethod]
    public void NamesResolveThroughUsing()
    {
        AssemblyResult result = Assemble(EightyColumns + """
            .proc Show
                .using EightyColumns
                lda CursorColumn
                lda Mode
                lda EightyColumns::Mode
                rts
            Mode = $10
            .endproc
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..9].ToArray().Should().Equal(0xAD, 0x7B, 0x05, 0xA5, 0x10, 0xAD, 0xFB, 0x04, 0x60);
    }

    /// <summary>
    ///  A source rewritten from qualified names to <c>.using</c> assembles to the same bytes.
    /// </summary>
    [TestMethod]
    public void UsingKeepsTheBytes()
    {
        AssemblyResult qualified = Assemble(EightyColumns + """
            .proc Show
                lda EightyColumns::CursorColumn
                sta EightyColumns::Mode
                rts
            .endproc
            """);

        AssemblyResult used = Assemble(EightyColumns + """
            .proc Show
                .using EightyColumns
                lda CursorColumn
                sta Mode
                rts
            .endproc
            """);

        qualified.Diagnostics.Should().BeEmpty();
        used.Diagnostics.Should().BeEmpty();
        used.Sections[0].Bytes.ToArray().Should().Equal(qualified.Sections[0].Bytes.ToArray());
        used.Symbols.Should().BeEquivalentTo(qualified.Symbols);
    }

    /// <summary>
    ///  A <c>.using</c> ends with the <c>.proc</c> or <c>.scope</c> that contains it, and does not apply before its
    ///  own line.
    /// </summary>
    [TestMethod]
    public void UsingEndsWithItsScope()
    {
        AssemblyResult result = Assemble(EightyColumns + """
            .proc Show
                .using EightyColumns
                lda Mode
            .endproc
                lda Mode
            """);

        Messages(result).Should().ContainSingle().Which.Should().Contain("Mode");

        result = Assemble(EightyColumns + """
            .proc Show
                lda Mode
                .using EightyColumns
            .endproc
            """);

        Messages(result).Should().ContainSingle().Which.Should().Contain("Mode");
    }

    /// <summary>
    ///  At file level, a <c>.using</c> applies to the end of the file, inside the scopes that follow it.
    /// </summary>
    [TestMethod]
    public void FileLevelUsingAppliesToTheFile()
    {
        AssemblyResult result = Assemble(EightyColumns + """
            .using EightyColumns
                lda Mode
            .proc Show
                lda CursorColumn
                rts
            .endproc
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..6].ToArray().Should().Equal(0xAD, 0xFB, 0x04, 0xAD, 0x7B, 0x05);
    }

    /// <summary>
    ///  A <c>.using</c> does not reach into an included file, and an included file's does not leak out of it.
    /// </summary>
    [TestMethod]
    public void UsingStaysInItsFile()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            File.WriteAllText(Path.Join(folder, "Columns.asm"), EightyColumns);
            File.WriteAllText(Path.Join(folder, "Uses.asm"), ".using EightyColumns\n    lda Mode\n");
            File.WriteAllText(Path.Join(folder, "Plain.asm"), "    lda Mode\n");

            // The included file's own .using works in it, and is gone after it.
            IncludeAssemble(folder, ".include \"Columns.asm\"\n.include \"Uses.asm\"\n    lda Mode\n").Should()
                .ContainSingle().Which.Location?.Path.Should().EndWith("Main.asm");

            // The including file's .using does not reach into the included file, but applies again after it.
            IncludeAssemble(folder, ".include \"Columns.asm\"\n.using EightyColumns\n.include \"Plain.asm\"\n    lda Mode\n").Should()
                .ContainSingle().Which.Location?.Path.Should().EndWith("Plain.asm");

            IncludeAssemble(folder, ".include \"Columns.asm\"\n.include \"Uses.asm\"\n.using EightyColumns\n    lda Mode\n").Should()
                .BeEmpty();
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A file-level <c>.using</c> ends with its top-level source: the next source assembled with it does not see it.
    /// </summary>
    [TestMethod]
    public void UsingEndsWithItsTopLevelSource()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            [
                new AssemblySource(".cpu Mos6502\n.scope A\nV = 1\n.endscope\n.using A\n    lda #V\n", "first.asm"),
                new AssemblySource("    lda #V\n", "second.asm")
            ],
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1300, imageSize: 0x100));

        result.Diagnostics.Should().ContainSingle().Which.Location?.Path.Should().Be("second.asm");
    }

    /// <summary>
    ///  Files a macro includes, one call after another, are separate files: one's <c>.using</c> does not reach the
    ///  next.
    /// </summary>
    [TestMethod]
    public void MacroIncludesAreSeparateFiles()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            File.WriteAllText(Path.Join(folder, "Columns.asm"), EightyColumns);
            File.WriteAllText(Path.Join(folder, "Uses.asm"), ".using EightyColumns\n    lda Mode\n");
            File.WriteAllText(Path.Join(folder, "Plain.asm"), "    lda Mode\n");
            IncludeAssemble(folder, """
                .include "Columns.asm"
                .macro Include file
                .include file
                .endmacro
                Include "Uses.asm"
                Include "Plain.asm"

                """).Should().ContainSingle().Which.Location?.Path.Should().EndWith("Plain.asm");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A statement with no location, as a programmatic project may hold, keeps the file-level <c>.using</c> around it.
    /// </summary>
    [TestMethod]
    public void StatementsWithoutLocationsStayInTheirFile()
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0x1300, imageSize: 0x100);
        AssemblyParseResult parsed = NativeAssembler.Parse(
            [new AssemblySource(".cpu Mos6502\n" + EightyColumns + ".using EightyColumns\n    nop\n    lda Mode\n", "test.asm")],
            options);

        parsed.Project.Statements.Single(statement => statement.Operation == "nop").Location = null;
        new NativeAssembler().Assemble(parsed.Project, options).Diagnostics.Should().BeEmpty();
    }

    /// <summary>
    ///  A statement added to a parsed project does not move a file-level <c>.using</c> out of its file.
    /// </summary>
    [TestMethod]
    public void AddedStatementsKeepFileLevelUsings()
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0x1300, imageSize: 0x100);
        AssemblyParseResult parsed = NativeAssembler.Parse(
            [
                new AssemblySource(".scope A\nV = 1\n.endscope\n.using A\n    lda #V\n", "first.asm"),
                new AssemblySource("    nop\n", "second.asm")
            ],
            options);

        parsed.Project.Statements.Insert(1, new(AssemblyStatementKind.Instruction, "NOP", AssemblyOperand.Value(new(""))));
        new NativeAssembler().Assemble(parsed.Project, options).Diagnostics.Should().BeEmpty();
    }

    /// <summary>
    ///  A statement removed from a parsed project does not carry a file-level <c>.using</c> into the next file.
    /// </summary>
    [TestMethod]
    public void RemovedStatementsKeepFileLevelUsingsInTheirFile()
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0x1300, imageSize: 0x100);
        AssemblyParseResult parsed = NativeAssembler.Parse(
            [
                new AssemblySource(".scope A\nV = 1\n.endscope\n    nop\n.using A\n", "first.asm"),
                new AssemblySource("    lda #V\n", "second.asm")
            ],
            options);

        parsed.Project.Statements.Remove(parsed.Project.Statements.First(statement => statement.Operation == "nop"));
        new NativeAssembler().Assemble(parsed.Project, options).Diagnostics.Should().NotBeEmpty();
    }

    /// <summary>
    ///  A <c>.using</c> in a <c>.repeat</c> is used if any expansion used it, and is not reported as unnecessary.
    /// </summary>
    [TestMethod]
    public void RepeatedUsingsAreUsedOnce()
    {
        AssemblyResult result = Assemble(EightyColumns + ".repeat 2\n.using EightyColumns\n.endrepeat\n    lda Mode\n");
        result.Diagnostics.Should().BeEmpty();
        result.Information.Should().BeEmpty();
    }

    /// <summary>
    ///  <c>.sizeof</c> takes a scope's or <c>.proc</c>'s plain name through <c>.using</c>, as other references do.
    /// </summary>
    [TestMethod]
    public void SizeofFindsUsedProcedures()
    {
        AssemblyResult result = Assemble("""
            .scope Video
            .proc Clear
                nop
                rts
            .endproc
            .endscope
            .using Video
                lda #.sizeof(Clear)
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[2..4].ToArray().Should().Equal(0xA9, 2);
    }

    /// <summary>
    ///  Exports are unchanged: <c>.export</c> of a plain name does not reach into a used scope.
    /// </summary>
    [TestMethod]
    public void ExportsDoNotLookInUsedScopes()
    {
        Messages(Assemble(EightyColumns + ".using EightyColumns\n.export Mode\n    lda Mode\n")).Should()
            .ContainSingle().Which.Should().Contain("Mode");
    }

    /// <summary>
    ///  Two used scopes that define a name: an error naming both, only where that name is used.
    /// </summary>
    [TestMethod]
    public void AmbiguousNamesAreErrorsWhereUsed()
    {
        const string Scopes = """
            .scope First
            Shared = 1
            OnlyFirst = 2
            .endscope
            .scope Second
            Shared = 3
            .endscope

            """;

        Assemble(Scopes + ".using First, Second\n    lda #OnlyFirst\n").Diagnostics.Should().BeEmpty();
        Messages(Assemble(Scopes + ".using First, Second\n    lda #Shared\n")).Should().Equal(
            "'Shared' is in both First and Second; qualify it.");

        // Separate directives are separate steps: the later, innermost one wins.
        AssemblyResult result = Assemble(Scopes + ".using First\n.using Second\n    lda #Shared\n");
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA9, 3);
    }

    /// <summary>
    ///  A <c>.using</c> of an unknown scope is an error; of one defined later in the source, it works; qualified
    ///  and absolute scope names work.
    /// </summary>
    [TestMethod]
    public void UsingNamesScopes()
    {
        Messages(Assemble(".using Nowhere\n    rts\n")).Should().Equal("No scope named 'Nowhere' for .using.");

        AssemblyResult later = Assemble(".using EightyColumns\n    lda Mode\n" + EightyColumns);
        later.Diagnostics.Should().BeEmpty();
        later.Sections[0].Bytes.Span[..3].ToArray().Should().Equal(0xAD, 0xFB, 0x04);

        AssemblyResult nested = Assemble("""
            .scope Firmware
            .scope Columns
            Mode = $4FB
            .endscope
            .endscope
            .proc A
                .using Firmware::Columns
                lda Mode
            .endproc
            .proc B
                .using ::Firmware::Columns
                lda Mode
            .endproc
            """);

        nested.Diagnostics.Should().BeEmpty();
        nested.Sections[0].Bytes.Span[..6].ToArray().Should().Equal(0xAD, 0xFB, 0x04, 0xAD, 0xFB, 0x04);
    }

    /// <summary>
    ///  A <c>.using</c> line takes scope names and no label, and only in the native dialect.
    /// </summary>
    [TestMethod]
    public void MalformedUsingsAreErrors()
    {
        Messages(Assemble(EightyColumns + "Here: .using EightyColumns\n")).Should().Equal("A .using line cannot carry a label.");
        Messages(Assemble(".using\n")).Should().Equal(".using requires one or more scope names.");
        Messages(Assemble(EightyColumns + ".using EightyColumns + 1\n")).Should().Equal(
            ".using requires scope names; 'EightyColumns + 1' is not one.");

        AssemblyResult ca65 = new NativeAssembler().Assemble(
            new AssemblySource("; retrocore: dialect=ca65\n.scope A\nB = 1\n.endscope\n.using A\n", "test.s"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1300, imageSize: 0x100));

        ca65.Success.Should().BeFalse("ca65 has no .using");
    }

    /// <summary>
    ///  Definitions after a <c>.using</c> are in the current scope, not the used one.
    /// </summary>
    [TestMethod]
    public void DefinitionsStayInTheirScope()
    {
        AssemblyResult result = Assemble(EightyColumns + """
            .proc Show
                .using EightyColumns
            Width = 80
                lda #Width
                rts
            .endproc
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Symbols.Should().ContainKey("Show::Width").And.NotContainKey("EightyColumns::Width");
    }

    /// <summary>
    ///  Inside a continued scope's piece, a <c>.using</c> applies to that piece only.
    /// </summary>
    [TestMethod]
    public void UsingInAPieceAppliesToThePiece()
    {
        AssemblyResult result = Assemble(EightyColumns + """
            .scope Commands
            Go:
                rts
            .endscope
            .scope Commands continued
                .using EightyColumns
                lda Mode
            .endscope
            .scope Commands continued
                lda Mode
            .endscope
            """);

        Messages(result).Should().ContainSingle().Which.Should().Contain("Mode");
    }

    /// <summary>
    ///  Conditional assembly sees a name found through <c>.using</c>, as code does.
    /// </summary>
    [TestMethod]
    public void ConditionsSeeUsedNames()
    {
        AssemblyResult result = Assemble("""
            .scope Settings
            WIDE = 1
            .endscope
            .proc Show
                .using Settings
            .ifdef WIDE
            .if WIDE
                lda #80
            .endif
            .endif
            COLUMNS = WIDE + 1
                lda #COLUMNS
                rts
            .endproc
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..5].ToArray().Should().Equal(0xA9, 80, 0xA9, 2, 0x60);

        Messages(Assemble("""
            .scope First
            WIDE = 1
            .endscope
            .scope Second
            WIDE = 0
            .endscope
            .using First, Second
            .if WIDE
                nop
            .endif
            """)).Should().Equal("'WIDE' is in both First and Second; qualify it.");
    }

    /// <summary>
    ///  A <c>.using</c> whose scope gives the code no name is not an error, but is reported as unnecessary.
    /// </summary>
    [TestMethod]
    public void UnusedUsingsAreInformation()
    {
        AssemblyResult result = Assemble(EightyColumns + """
            .scope Other
            Thing = 1
            .endscope
            .using EightyColumns, Other
                lda Mode
                lda Other::Thing
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Information.Select(note => note.Message).Should().Equal(
            "Nothing uses a name from Other through this .using; it is unnecessary.");
    }

    /// <summary>
    ///  A <c>.using</c> whose name only a conditional tests is used, so it is not reported as unnecessary.
    /// </summary>
    [TestMethod]
    public void ConditionsUseUsings()
    {
        AssemblyResult result = Assemble("""
            .scope Settings
            WIDE = 1
            .endscope
            .using Settings
            .if WIDE
                nop
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Information.Should().BeEmpty();
    }

    /// <summary>
    ///  A constant made from a name two used scopes define has no value for conditionals, and the code's use is an
    ///  error.
    /// </summary>
    [TestMethod]
    public void AmbiguousConstantsHaveNoValue()
    {
        const string Scopes = """
            .scope First
            Shared = 1
            .endscope
            .scope Second
            Shared = 0
            .endscope
            .using First, Second
            Value = Shared + 1

            """;

        Messages(Assemble(Scopes + ".if Value\n    nop\n.endif\n")).Should().Equal(
            "Conditional requires a constant known at this point in source order.");

        Messages(Assemble(Scopes + "    lda #Value\n")).Should().Equal("'Shared' is in both First and Second; qualify it.");
    }

    /// <summary>
    ///  The strict lint's unlinked-name check also resolves a name by its own comment's <c>.using</c> directives.
    /// </summary>
    [TestMethod]
    public void UnlinkedNamesUseTheirOwnCommentsUsings()
    {
        string text = """
            ; retrocore: style=strict
            .cpu Mos6502
            .org $0300

            ;; The first values.
            .scope A

            ;; A value.
            FirstValue = 1

            .endscope

            ;; The second values.
            .scope B

            ;; Another value.
            SecondValue = 2

            .endscope

            ENHANCED = 1
            .using A
            .if ENHANCED

            ;; Uses <FirstValue>.
            .proc Thing
                rts
            .endproc

            .else
            .using B

            ;; Uses <FirstValue> and SecondValue.
            .proc Thing
                rts
            .endproc

            .endif
            """;

        DocumentationSet set = DocumentationSet.Create([DocumentationParser.Parse(text, "test.asm")], Assemble(text));
        new DocumentationResolver(set).Check().Select(diagnostic => diagnostic.Message).Should()
            .Contain("Link SecondValue as <SecondValue>: it names a documented definition.");
    }

    /// <summary>
    ///  The editor's note on an unnecessary <c>.using</c> carries LSP's Unnecessary tag (1), so the editor fades it.
    /// </summary>
    [TestMethod]
    public void UnnecessaryNotesCarryTheTag()
    {
        Diagnostic note = new Diagnostic
        {
            Range = new LspRange(0, 0, 0, 1),
            Severity = DiagnosticSeverity.Error,
            Message = "unused"
        }.Unnecessary();

        System.Text.Json.Nodes.JsonObject json = note.ToJson();
        json["tags"]?.ToJsonString().Should().Be("[1]");
        json["severity"]?.GetValue<int>().Should().Be((int)DiagnosticSeverity.Information);
    }

    /// <summary>
    ///  A documentation link in a comment inside a <c>.using</c>'s extent resolves as the code there would.
    /// </summary>
    [TestMethod]
    public void LinksResolveThroughUsing()
    {
        string text = """
            .scope EightyColumns
            ;; The cursor's column.
            CursorColumn = $57B
            .endscope

            .using EightyColumns

            ;; Moves to <CursorColumn>.
            Move:
                lda CursorColumn
                rts
            """;

        DocumentationSet set = DocumentationSet.Create([DocumentationParser.Parse(text, "test.asm")], Assemble(text));
        DocumentationResolver resolver = new(set);
        DocumentationTopic move = set.Find("Move") ?? throw new AssertFailedException("No Move topic.");
        resolver.Resolve(move, "CursorColumn").Topic?.Name.Should().Be("EightyColumns::CursorColumn");
        resolver.Check().Should().BeEmpty();
    }

    /// <summary>
    ///  A topic documented in two <c>.if</c> branches resolves each comment's links by the <c>.using</c> directives in
    ///  effect at that comment, not the first comment's.
    /// </summary>
    [TestMethod]
    public void LinksUseTheirOwnCommentsUsings()
    {
        string text = """
            .scope A
            ;; A value.
            X = 1
            .endscope

            .scope B
            ;; Another value.
            Y = 2
            .endscope

            ENHANCED = 1
            .using A
            .if ENHANCED
            ;; Uses <X>.
            Thing:
                rts
            .else
            .using B
            ;; Uses <Y>.
            Thing:
                rts
            .endif
            """;

        DocumentationSet set = DocumentationSet.Create([DocumentationParser.Parse(text, "test.asm")], Assemble(text));
        new DocumentationResolver(set).Check().Should().BeEmpty();
    }

    /// <summary>
    ///  The editor's scope-rule lookup, which decides whether a word is a historical name, finds a name a
    ///  <c>.using</c> supplies, so that use is not offered a historical name's quick fix.
    /// </summary>
    [TestMethod]
    public void UsedNamesAreNotHistoricalNames()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope Other
                COUT = 1
                .endscope
                .using Other
                    lda #COUT

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            (analysis.Bound("COUT", main, line: 4) ?? []).Select(site => site.Name).Should().Equal("Other::COUT");
            analysis.Bound("COUT", main, line: 0).Should().BeNull();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Hover, go to definition and find references find a name through <c>.using</c> where the code uses it.
    /// </summary>
    [TestMethod]
    public void TheEditorFindsUsedNames()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope EightyColumns
                CursorColumn = $57B
                .endscope
                .scope Other
                CursorColumn = $57C
                .endscope
                .proc Show
                    .using EightyColumns
                    lda CursorColumn
                    rts
                .endproc

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            SymbolSite site = analysis.Find("CursorColumn", main, line: 8).Should().ContainSingle().Subject;
            site.Name.Should().Be("EightyColumns::CursorColumn");
            site.Line.Should().Be(1);

            analysis.UsedNames(main, line: 8).Select(used => used.Name).Should().Equal("CursorColumn");
            analysis.UsedNames(main, line: 3).Should().BeEmpty();

            SymbolReferences.Find("CursorColumn", [site], [analysis], sdk: [], includeDeclaration: false)
                .Select(reference => reference.Line).Should().Equal(8);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  The editor applies the <c>.using</c> lines the assembler took: not one in an <c>.if</c> branch it skipped, nor
    ///  one in a macro's body where the macro is defined.
    /// </summary>
    [TestMethod]
    public void TheEditorUsesAssembledUsings()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope A
                N = 1
                .endscope
                .scope B
                N = 2
                .endscope
                .macro UseB
                .using B
                .endmacro
                ON = 1
                .if ON
                .using A
                .else
                .using B
                .endif
                    lda #N

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Find("N", main, line: 15).Should().ContainSingle().Which.Name.Should().Be("A::N");
            analysis.UsedNames(main, line: 10).Should().BeEmpty("the macro's .using is not in effect where it is defined");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Completion offers a used scope's name only where it binds to that definition: not one an enclosing scope's own
    ///  name shadows, nor one two used scopes define.
    /// </summary>
    [TestMethod]
    public void CompletionOffersOnlyBindingNames()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope A
                Shared = 1
                Mode = 2
                OnlyA = 3
                .endscope
                .scope B
                Shared = 4
                .endscope
                .proc Show
                Mode = 5
                    .using A, B
                    rts
                .endproc

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.UsedNames(main, line: 11).Select(used => used.Name).Should().Equal("OnlyA");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A file included inside a scope is in that scope, so the editor looks its names up there, as the assembler does.
    /// </summary>
    [TestMethod]
    public void IncludedFilesAreInTheirIncludersScope()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string part = Path.Join(directory, "part.asm");
            File.WriteAllText(part, "    lda Value\n");
            File.WriteAllText(main, """
                Value = 1
                .scope Outer
                Value = 2
                .include "part.asm"
                .endscope

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA5, 2);
            analysis.Find("Value", part, line: 0).Should().ContainSingle().Which.Name.Should().Be("Outer::Value");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A file included in two scopes is in each, so the editor finds a name there in both, as the assembler binds it.
    /// </summary>
    [TestMethod]
    public void FilesIncludedTwiceAreInBothScopes()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string part = Path.Join(directory, "part.asm");
            File.WriteAllText(part, "    lda Value\n");
            File.WriteAllText(main, """
                .scope A
                Value = 1
                .include "part.asm"
                .endscope
                .scope B
                Value = 2
                .include "part.asm"
                .endscope

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Find("Value", part, line: 0).Select(site => site.Name).Should().BeEquivalentTo("A::Value", "B::Value");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A <c>.struct</c> a used scope defines is a type by its plain name: <c>.sizeof</c>, <c>.tag</c> and a condition
    ///  on its size all find it.
    /// </summary>
    [TestMethod]
    public void UsedStructsAreTypes()
    {
        AssemblyResult result = Assemble("""
            .scope A
            .struct S
                a .byte
                b .word
            .endstruct
            .endscope
            .using A
                lda #.sizeof(S)
            .if .sizeof(S) = 3
                nop
            .endif
            Buffer: .tag S
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..3].ToArray().Should().Equal(0xA9, 3, 0xEA);
    }

    /// <summary>
    ///  In the editor, a cheap local binds to the one after the label before it, not to the first in its scope.
    /// </summary>
    [TestMethod]
    public void TheEditorFindsCheapLocalsByTheirLabel()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .proc P
                    ldx #0
                @loop: dex
                    bne @loop
                Inner:
                @loop: dey
                    bne @loop
                    rts
                .endproc

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Bound("@loop", main, line: 6).Should().BeNull();
            analysis.Find("@loop", main, line: 6, macro10: false).Select(site => site.Line).Should().Contain(5);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A function the preprocessor answers, such as <c>.defined</c> or <c>.sizeof</c>, of a name two used scopes
    ///  define is the ambiguity error, as the name is in code.
    /// </summary>
    /// <param name="use">The lines that use the name.</param>
    [TestMethod]
    [DataRow(".if .defined(N)\n    nop\n.endif\n")]
    [DataRow(".if .const(N)\n    nop\n.endif\n")]
    [DataRow("    .byte .defined(N)\n")]
    public void AmbiguousNamesInFunctionsAreErrors(string use)
    {
        AssemblyResult result = Assemble(".scope A\nN = 1\n.endscope\n.scope B\nN = 2\n.endscope\n.using A, B\n" + use);
        result.Diagnostics.Select(diagnostic => diagnostic.Message).Should().Equal("'N' is in both A and B; qualify it.");
    }

    /// <summary>
    ///  A type two used scopes define is the ambiguity error where <c>.tag</c> or <c>.sizeof</c> names it.
    /// </summary>
    /// <param name="use">The lines that use the type.</param>
    [TestMethod]
    [DataRow("Buf: .tag T\n")]
    [DataRow("    lda #.sizeof(T)\n")]
    [DataRow(".struct U\n    t .tag T\n.endstruct\n")]
    public void AmbiguousTypesAreErrors(string use)
    {
        AssemblyResult result = Assemble("""
            .scope A
            .struct T
                x .byte
            .endstruct
            .endscope
            .scope B
            .struct T
                x .byte
                y .byte
            .endstruct
            .endscope
            .using A, B

            """ + use);

        result.Diagnostics.Select(diagnostic => diagnostic.Message).Should().Equal("'T' is in both A and B; qualify it.");
    }

    /// <summary>
    ///  Two spellings of one scope in a <c>.using</c> name one type, so a condition on its size is not ambiguous.
    /// </summary>
    [TestMethod]
    public void OneScopeSpelledTwiceGivesOneType()
    {
        AssemblyResult result = Assemble("""
            .scope A
            .struct T
                X .byte
                Y .byte
            .endstruct
            .endscope
            .using A, ::A
            .if .sizeof(T) = 2
                nop
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..1].ToArray().Should().Equal(0xEA);
    }

    /// <summary>
    ///  The historical-name hint does not look in a type's body, whose names are the type's own members.
    /// </summary>
    [TestMethod]
    public void TypeMembersAreNotHistoricalNames()
    {
        string[] lines =
        [
            "Thing = 1",
            ".struct Point",
            "    Width .byte",
            ".endstruct",
            ".enum Color",
            "    Black",
            ".endenum",
            "    lda #Width"
        ];

        SourceText.CodeNames(lines).Should().Equal([(7, 4, "lda"), (7, 9, "Width")]);
    }

    /// <summary>
    ///  The historical-name hint does not take the name a <c>.scope</c> or <c>.proc</c> line declares, after a label
    ///  or before an address size as ca65 writes them, or a scope's name before <c>::</c>, as a use.
    /// </summary>
    [TestMethod]
    public void DeclaredScopeNamesAreNotHistoricalNames()
    {
        string[] lines =
        [
            ".scope KBD",
            ".endscope",
            ".scope KBD continued",
            ".proc CH",
            ".endproc",
            "    jsr KBD::Read",
            "Alias: .scope KBD",
            "    .proc KBD: far",
            "    lda CH"
        ];

        SourceText.CodeNames(lines).Where(use => use.Name is "KBD" or "CH").Should().Equal([(8, 8, "CH")]);
    }

    /// <summary>
    ///  In the editor, a root name only a skipped conditional branch defines does not hide the name a
    ///  <c>.using</c> brings in, as it does not in the assembler.
    /// </summary>
    [TestMethod]
    public void TheEditorIgnoresSkippedDefinitionsWhenBinding()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope A
                V = 5
                .endscope
                .if 0
                V = 9
                .endif
                .proc P
                    .using A
                    lda #V
                    rts
                .endproc

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            (analysis.Bound("V", main, line: 8) ?? []).Select(site => site.Name).Should().Equal("A::V");
            analysis.UsedNames(main, line: 8).Select(used => used.Name).Should().Contain("V");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  The editor binds a used name the same way when many requests reach a fresh analysis at once.
    /// </summary>
    [TestMethod]
    public void TheEditorBindsUsedNamesFromParallelRequests()
    {
        // Language requests run in parallel on one analysis, and the first ones fill its scope caches.
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            List<string> parts = [];
            for (int part = 0; part < 40; part++)
            {
                string path = Path.Join(directory, $"p{part}.asm");
                File.WriteAllText(path, $".proc P{part}\n.using E\n    lda Col\n.endproc\n");
                parts.Add(path);
            }

            File.WriteAllText(main, ".scope E\nCol = 1\n.endscope\n" + string.Concat(parts.Select(path => $".include \"{Path.GetFileName(path)}\"\n")));
            for (int round = 0; round < 20; round++)
            {
                SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
                analysis.Result.Diagnostics.Should().BeEmpty();
                string?[] bound = new string?[parts.Count * 2];
                Parallel.For(0, bound.Length, at =>
                {
                    IReadOnlyList<SymbolSite>? sites = analysis.Bound("Col", parts[at % parts.Count], line: 2);
                    bound[at] = sites is [{ } site] ? site.Name : null;
                });

                bound.Should().AllBe("E::Col");
            }
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  In the editor, a macro's <c>.using</c> lasts as long as it does in the assembler: past the invocation when
    ///  the scope it is in closes outside the macro, and not when the macro closes it, a continued piece included.
    /// </summary>
    [TestMethod]
    public void TheEditorFollowsMacroUsingExtents()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope A
                X = 1
                .endscope
                .scope S
                .endscope
                .macro Open
                .scope T
                .using A
                .endmacro
                .macro Piece
                .scope S continued
                .using A
                .endscope
                .endmacro
                    Open
                    .byte X
                .endscope
                    Piece
                    nop

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            (analysis.Bound("X", main, line: 15) ?? []).Select(site => site.Name).Should().Equal("A::X");
            analysis.Bound("X", main, line: 19).Should().BeNull("the piece's .using ended inside the macro");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A <c>.using</c> whose operand a <c>.define</c> gives names that scope in the editor and doc links, as in the
    ///  assembler.
    /// </summary>
    [TestMethod]
    public void DefinedOperandsNameTheirScope()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope A
                ;; The value.
                V = $10
                .endscope
                .define Short A
                .using Short

                ;; Uses <V>.
                Load:
                    lda V
                    rts

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            (analysis.Bound("V", main, line: 9) ?? []).Select(site => site.Name).Should().Equal("A::V");
            DocumentationTopic load = analysis.Documentation.Find("Load") ?? throw new AssertFailedException("No Load topic.");
            new DocumentationResolver(analysis.Documentation).Resolve(load, "V").Topic?.Name.Should().Be("A::V");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A build that goes through the linker keeps the <c>.using</c> file extents and the uses conditionals make.
    /// </summary>
    [TestMethod]
    public void LinkedBuildsKeepUsingExtents()
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0x1300, imageSize: 0x100)
        {
            LinkerConfiguration = new("MEMORY{RAM:start=$1300,size=$100;}SEGMENTS{CODE:load=RAM,type=ro;}", "link.cfg")
        };

        AssemblyResult roots = new NativeAssembler().Assemble(
            [
                new AssemblySource(".cpu Mos6502\n.scope A\nV = 1\n.endscope\n.using A\n    lda #V\n", "first.asm"),
                new AssemblySource("    lda #V\n", "second.asm")
            ],
            options);

        roots.Diagnostics.Should().ContainSingle().Which.Location?.Path.Should().Be("second.asm");

        AssemblyResult conditional = new NativeAssembler().Assemble(
            new AssemblySource(".cpu Mos6502\n.scope S\nW = 1\n.endscope\n.using S\n.if W\n    nop\n.endif\n", "test.asm"),
            options);

        conditional.Diagnostics.Should().BeEmpty();
        conditional.Information.Should().BeEmpty();
    }

    /// <summary>
    ///  An included file that closes the scope it was included in also ends that scope's <c>.using</c>.
    /// </summary>
    [TestMethod]
    public void IncludesThatCloseScopesEndTheirUsings()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            File.WriteAllText(Path.Join(folder, "Close.asm"), ".endproc\n");
            IncludeAssemble(folder, EightyColumns + ".proc P\n.using EightyColumns\n.include \"Close.asm\"\n    lda Mode\n")
                .Should().ContainSingle().Which.Message.Should().Contain("Mode");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  In the editor, a <c>.using</c> inside a scope a macro's expansion opens ends with that scope; one a
    ///  <c>.define</c> gives applies from its line; and used scopes whose names differ by case are both searched.
    /// </summary>
    [TestMethod]
    public void TheEditorFollowsExpandedUsings()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope A
                X = $10
                .endscope
                .scope a
                Y = $20
                .endscope
                .macro Define
                .proc Inner
                .using A
                    lda X
                .endproc
                .endmacro
                .define USE .using A, a
                .proc P
                    Define
                    rts
                .endproc
                .proc Q
                    USE
                    lda X
                    lda Y
                .endproc

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Bound("X", main, line: 15).Should().BeNull("the macro's .using ended with the scope it opened");
            (analysis.Bound("X", main, line: 19) ?? []).Select(site => site.Name).Should().Equal("A::X");
            (analysis.Bound("Y", main, line: 20) ?? []).Select(site => site.Name).Should().Equal("a::Y");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A member file whose <c>.using</c> the assembly never reached (all of it in a skipped <c>.if</c>) does not
    ///  lend that <c>.using</c> to its doc links.
    /// </summary>
    [TestMethod]
    public void UnreachedFilesLendNoUsings()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(Path.Join(directory, "part.asm"), """
                .if 0
                .scope A
                ;; The value.
                N = 1
                .endscope
                .proc P
                .using A

                ;; Uses <N>.
                Load:
                    rts
                .endproc
                .endif

                """);

            File.WriteAllText(main, ".include \"part.asm\"\n    rts\n");
            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            DocumentationTopic load = analysis.Documentation.Find("P::Load") ?? throw new AssertFailedException("No Load topic.");
            new DocumentationResolver(analysis.Documentation).Resolve(load, "N").Kind.Should().Be(DocumentationTargetKind.Unresolved);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Each <c>.repeat</c> iteration of an <c>.include</c> is its own file: one iteration's <c>.using</c> does not reach
    ///  the next.
    /// </summary>
    [TestMethod]
    public void RepeatedIncludesAreSeparateFiles()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            File.WriteAllText(Path.Join(folder, "Part.asm"), "    lda X\n.using S\n");
            IncludeAssemble(folder, ".scope S\nX = 1\n.endscope\n.repeat 2\n.include \"Part.asm\"\n.endrepeat\n")
                .Select(diagnostic => Path.GetFileName(diagnostic.Location?.Path)).Should().Equal("Part.asm", "Part.asm");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  Documentation parsed with the assembly follows the <c>.using</c> lines it took: not one in a skipped
    ///  <c>.if</c> branch, and one a macro invocation gives from that line. The debugger and the generator parse so.
    /// </summary>
    [TestMethod]
    public void DocumentationFollowsTheAssembly()
    {
        const string Scope = """
            .scope EightyColumns
            ;; The cursor's column.
            CursorColumn = $57B
            .endscope

            """;

        const string Skipped = "ON = 0\n.if ON\n.using EightyColumns\n.endif\n\n;; Moves to <CursorColumn>.\nMove:\n    rts\n";
        const string Invoked = ".macro UseColumns\n.using EightyColumns\n.endmacro\n    UseColumns\n\n;; Moves to <CursorColumn>.\nMove:\n    rts\n";
        Unresolved(Scope + Skipped).Should().ContainSingle();
        Unresolved(Scope + Invoked).Should().BeEmpty();

        static List<string> Unresolved(string text)
        {
            AssemblyResult result = Assemble(text);
            result.Diagnostics.Should().BeEmpty();
            DocumentationFile file = DocumentationParser.Parse(".cpu Mos6502\n" + text, "test.asm", DocumentationAssembled.From(result, "test.asm"));
            DocumentationSet set = DocumentationSet.Create([file], result);
            return [.. new DocumentationResolver(set).Check().Select(diagnostic => diagnostic.Message).Where(message => message.Contains("CursorColumn"))];
        }
    }

    /// <summary>
    ///  Conditionals bind a <c>.using</c> operand at the directive, as code does: to the scope opened before it, not a
    ///  same-named one opened after it.
    /// </summary>
    [TestMethod]
    public void ConditionsBindOperandsAtTheDirective()
    {
        AssemblyResult result = Assemble("""
            .scope T
            X = 1
            .endscope
            .scope S
            .using T
            .scope T
            X = 2
            .endscope
            .if X = 1
                lda #1
            .else
                lda #2
            .endif
                lda X
            .endscope
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..4].ToArray().Should().Equal(0xA9, 1, 0xA5, 1);
    }

    /// <summary>
    ///  <c>.sizeof</c> of a label the enclosing scopes define is that label's, not a used scope's of the same name; a
    ///  scope name two used scopes share is an error.
    /// </summary>
    [TestMethod]
    public void SizeofPrefersLocalLabelsAndReportsAmbiguity()
    {
        AssemblyResult local = Assemble("""
            .scope V
            .proc Name
                nop
                nop
                nop
                rts
            .endproc
            .endscope
            .proc P
                .using V
            Name: nop
                lda #.sizeof(Name)
            .endproc
            """);

        local.Diagnostics.Should().BeEmpty();
        local.Sections[0].Bytes.Span[5..7].ToArray().Should().Equal(0xA9, 1);

        Messages(Assemble("""
            .scope A
            .scope Inner
                nop
            .endscope
            .endscope
            .scope B
            .scope Inner
                nop
            .endscope
            .endscope
            .using A, B
                lda #.sizeof(Inner)
            """)).Should().Equal("'Inner' is in both A and B; qualify it.");
    }

    /// <summary>
    ///  The editor matches a native name's case, as the assembler does, before the used scopes.
    /// </summary>
    [TestMethod]
    public void TheEditorMatchesCase()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, ".scope E\nMode = 1\n.endscope\nmode = 2\n.proc P\n    .using E\n    lda #Mode\n    rts\n.endproc\n");
            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Find("Mode", main, line: 6).Select(site => site.Name).Should().Equal("E::Mode");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  An empty operand in a <c>.using</c> list is an error of its own, not a missing scope.
    /// </summary>
    [TestMethod]
    public void EmptyOperandsAreErrors()
    {
        Messages(Assemble(".scope A\n.endscope\n.scope B\n.endscope\n.using A,,B\n")).Should().Equal(
            "Empty or unbalanced directive operands.");
    }

    /// <summary>
    ///  The editor binds a <c>.using</c> operand as the assembler does: to a scope already opened before the
    ///  directive, not to a same-named scope opened later in the enclosing one.
    /// </summary>
    [TestMethod]
    public void TheEditorBindsOperandsToEarlierScopes()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope A
                N = 1
                .endscope
                .proc P
                    .using A
                    lda #N
                .scope A
                N = 2
                .endscope
                .endproc

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA9, 1);
            analysis.Find("N", main, line: 5).Select(site => site.Name).Should().Equal("A::N");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A <c>.using</c> a macro gives applies, in the editor as in the assembler, from the line that invokes it.
    /// </summary>
    [TestMethod]
    public void TheEditorFollowsUsingsFromMacros()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, """
                .scope A
                X = $10
                .endscope
                .scope B
                X = $20
                .endscope
                .macro UseA
                .using A
                .endmacro
                .proc P
                    UseA
                    lda X
                    rts
                .endproc

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Find("X", main, line: 11).Select(site => site.Name).Should().Equal("A::X");
            analysis.UsedNames(main, line: 11).Select(used => used.Name).Should().Contain("X");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  <c>.sizeof</c> takes a <c>.scope</c>'s plain name through <c>.using</c>, as well as a <c>.proc</c>'s.
    /// </summary>
    [TestMethod]
    public void SizeofFindsUsedScopes()
    {
        AssemblyResult result = Assemble("""
            .scope A
            .scope C
                nop
                nop
            .endscope
            .endscope
            .using A
                lda #.sizeof(C)
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[2..4].ToArray().Should().Equal(0xA9, 2);
    }

    /// <summary>
    ///  A name two used scopes define is reported once for a statement, however often the statement uses it.
    /// </summary>
    [TestMethod]
    public void AmbiguityIsReportedOncePerStatement()
    {
        Messages(Assemble("""
            .scope A
            N = 1
            .endscope
            .scope B
            N = 2
            .endscope
            .using A, B
                lda #N+N
            """)).Should().Equal("'N' is in both A and B; qualify it.");
    }

    /// <summary>
    ///  A file a macro includes is in the scope where the macro is invoked, as the assembler binds it.
    /// </summary>
    [TestMethod]
    public void FilesIncludedByMacrosAreInTheInvokersScope()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string part = Path.Join(directory, "part.asm");
            File.WriteAllText(part, "    lda Value\n");
            File.WriteAllText(main, """
                .macro IncludePart
                .include "part.asm"
                .endmacro
                Value = 1
                .scope Outer
                Value = 2
                    IncludePart
                .endscope

                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Find("Value", part, line: 0).Select(site => site.Name).Should().Equal("Outer::Value");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  The editor ignores a malformed <c>.using</c>, which the assembler rejects.
    /// </summary>
    [TestMethod]
    public void TheEditorIgnoresMalformedUsings()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, ".scope A\n.proc Show\n    rts\n.endproc\n.endscope\n.using A, 1 + 2\n    jsr Show\n");
            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Result.Success.Should().BeFalse();
            analysis.Find("A::Show").Should().NotBeEmpty();
            analysis.Bound("Show", main, line: 6).Should().BeNull();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A <c>.repeat</c> count made from a name two used scopes define is an error, not the first scope's value.
    /// </summary>
    [TestMethod]
    public void AmbiguousRepeatCountsAreErrors()
    {
        Messages(Assemble("""
            .scope First
            N = 1
            .endscope
            .scope Second
            N = 2
            .endscope
            .using First, Second
            .repeat N
                nop
            .endrepeat
            """)).Should().Contain("'N' is in both First and Second; qualify it.");
    }

    /// <summary>
    ///  The editor ignores a <c>.using</c> in another dialect, which the assembler rejects.
    /// </summary>
    [TestMethod]
    public void TheEditorIgnoresUsingsInOtherDialects()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-using").FullName;
        try
        {
            string main = Path.Join(directory, "main.s");
            File.WriteAllText(main, "; retrocore: dialect=ca65\n.scope A\n.proc Show\n    rts\n.endproc\n.endscope\n.using A\n    jsr Show\n");
            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            analysis.Find("A::Show").Should().NotBeEmpty();
            analysis.Bound("Show", main, line: 7).Should().BeNull();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  The doc parser records the <c>.using</c> directives in effect at each line, ending with their scope.
    /// </summary>
    [TestMethod]
    public void ScopesByLineFollowUsings()
    {
        IReadOnlyList<DocumentationScopes> scopes = DocumentationParser.ScopesByLine(
        [
            ".using A",
            ".proc P",
            "    .using B, C",
            "    nop",
            ".endproc",
            "    nop"
        ]);

        scopes[0].Usings.Should().BeEmpty();
        scopes[2].Scope.Should().Be("P");
        scopes[2].Usings.Select(item => string.Join(",", item.Names)).Should().Equal("A");
        scopes[3].Usings.Select(item => string.Join(",", item.Names)).Should().Equal("B,C", "A");
        scopes[3].Usings[0].Scope.Should().Be("P");
        scopes[5].Usings.Select(item => string.Join(",", item.Names)).Should().Equal("A");
    }

    private static List<string> Messages(AssemblyResult result) => [.. result.Diagnostics.Select(diagnostic => diagnostic.Message)];

    private static IReadOnlyList<AssemblyDiagnostic> IncludeAssemble(string folder, string text)
    {
        string main = Path.Join(folder, "Main.asm");
        File.WriteAllText(main, text);
        return new NativeAssembler().Assemble(
            new AssemblySource(".cpu Mos6502\n" + text, main),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1300, imageSize: 0x100)
            {
                SourceResolver = new FileAssemblySourceResolver()
            }).Diagnostics;
    }

    private static AssemblyResult Assemble(string text) =>
        new NativeAssembler().Assemble(
            new AssemblySource(".cpu Mos6502\n" + text, "test.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1300, imageSize: 0x100));
}
