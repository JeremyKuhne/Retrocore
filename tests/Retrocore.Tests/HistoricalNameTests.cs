// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Historical names: a definition's <c>;; Also:</c> section, which the assembler, the documentation and the
///  language server all accept for the definition (docs/DocComments.md, section 2.4).
/// </summary>
[TestClass]
public sealed class HistoricalNameTests
{
    private const string Library = """
        ;; Prints a character.
        ;; In: A = the character
        ;; Also: COUT (TEST)
        CharacterOut = $FDED

        .scope Monitor
        ;; Reads a key.
        ;; Also: RDKEY (TEST), KEYIN (TEST)
        .proc ReadKey
            rts
        .endproc
        .endscope
        """;

    /// <summary>
    ///  Code written with a historical name assembles against the definition, inside scopes and before it.
    /// </summary>
    [TestMethod]
    public void OldNamesAssemble()
    {
        AssemblyResult result = Assemble($"""
                jsr COUT
                lda #<KEYIN
                jsr RDKEY
                rts
            {Library}
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..9].ToArray().Should().Equal(0x20, 0xED, 0xFD, 0xA9, 0x09, 0x20, 0x09, 0x10, 0x60);
        result.Symbols.Should().NotContainKey("COUT");
    }

    /// <summary>
    ///  A symbol of the same name wins over a historical name.
    /// </summary>
    [TestMethod]
    public void DefinitionsWinOverOldNames()
    {
        AssemblyResult result = Assemble("""
                jsr COUT
            COUT = $FDF0
            ;; Also: COUT (TEST)
            CharacterOut = $FDED
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..3].ToArray().Should().Equal(0x20, 0xF0, 0xFD);
    }

    /// <summary>
    ///  A historical name two definitions give is an error where code uses it, naming both.
    /// </summary>
    [TestMethod]
    public void SharedOldNamesAreAmbiguous()
    {
        AssemblyResult result = Assemble("""
                jsr COUT
            ;; Also: COUT
            First = $FDED
            ;; Also: COUT
            Second = $FDF0
            """);

        result.Diagnostics.Select(diagnostic => diagnostic.Message).Should().Contain(
            "'COUT' is a historical name of First and Second: use one of those.");
    }

    /// <summary>
    ///  An included file's historical names reach the code that includes it.
    /// </summary>
    [TestMethod]
    public void IncludedOldNamesAssemble()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-also").FullName;
        try
        {
            File.WriteAllText(Path.Join(folder, "Library.asm"), Library);
            string main = Path.Join(folder, "Main.asm");
            string text = """
                    jsr COUT
                    rts
                .include "Library.asm"
                """;

            File.WriteAllText(main, text);
            AssemblyResult result = new NativeAssembler().Assemble(
                new AssemblySource(text, main),
                new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 0x100)
                {
                    SourceResolver = new FileAssemblySourceResolver()
                });

            result.Diagnostics.Should().BeEmpty();
            result.Sections[0].Bytes.Span[..3].ToArray().Should().Equal(0x20, 0xED, 0xFD);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  An <c>Also:</c> item is a name and the keys of the documents that give it.
    /// </summary>
    [TestMethod]
    public void AlsoItemsParse()
    {
        DocumentationAlso.Parse("COUT (A2RM78, IIETR)").Should().BeEquivalentTo(
            new DocumentationAlso("COUT", ["A2RM78", "IIETR"]));

        DocumentationAlso.Parse("KEYIN").Should().BeEquivalentTo(new DocumentationAlso("KEYIN", []));
        DocumentationAlso.Parse("COUT (A2RM78").Should().BeNull("the key list is not closed");
        DocumentationAlso.Parse("COUT (A2RM78) in the manual").Should().BeNull("text follows the key list");
        DocumentationAlso.Parse("the old name").Should().BeNull();
    }

    /// <summary>
    ///  A link to a historical name reaches the definition that gives it.
    /// </summary>
    [TestMethod]
    public void LinksToOldNamesResolve()
    {
        string text = Library + """

            ;; Echoes a key with <RDKEY> and <COUT>.
            Echo:
                rts
            """;

        DocumentationSet set = Set(text);
        DocumentationResolver resolver = new(set);
        DocumentationTopic echo = Required(set.Find("Echo"));
        resolver.Resolve(echo, "COUT").Topic?.Name.Should().Be("CharacterOut");
        resolver.Resolve(echo, "RDKEY").Topic?.Name.Should().Be("Monitor::ReadKey");
        resolver.Check().Should().BeEmpty();
    }

    /// <summary>
    ///  The lint checks each <c>Also:</c> item's form, its documents and its name.
    /// </summary>
    [TestMethod]
    public void AlsoSectionsAreChecked()
    {
        DocumentationSet set = Set("""
            ;; Prints a character.
            ;; Also: COUT (NOPE), PRINT, the old one
            CharacterOut = $FDED

            ;; Reads a key.
            ;; Also: ReadKey (TEST), Other (TEST), PRINT (TEST)
            ReadKey = $FD0C

            ;; Something else.
            Other = 1
            """);

        DocumentationResolver resolver = new(set) { Bibliography = DocumentationBibliography.Parse(Bibliography) };
        resolver.Check().Select(diagnostic => diagnostic.Message).Should().BeEquivalentTo(
            "Also: no document 'NOPE' in the bibliography.",
            "Also: say which document PRINT comes from, as 'PRINT (A2RM)'.",
            "Also: write a historical name and the documents that give it, as 'COUT (A2RM)', not 'the old one'.",
            "Also: ReadKey is already the definition's name.",
            "Also: Other is also a definition, which code reaches instead of ReadKey.",
            "Also: ReadKey has the historical name PRINT too.",
            "Also: CharacterOut has the historical name PRINT too.");
    }

    /// <summary>
    ///  An included library's own <c>Bibliography.md</c> serves its <c>Also:</c> entries, as well as the root's.
    /// </summary>
    [TestMethod]
    public void IncludedFilesBibliographiesAreRead()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-also").FullName;
        try
        {
            string main = Path.Join(folder, "Main.asm");
            string library = Path.Join(folder, "lib", "Library.asm");
            Directory.CreateDirectory(Path.Join(folder, "lib"));
            File.WriteAllText(main, ".include \"lib/Library.asm\"\n");
            File.WriteAllText(library, "");
            File.WriteAllText(
                Path.Join(folder, "lib", "Bibliography.md"),
                "| Key | Title | Year | Publisher | Link |\n| --- | --- | --- | --- | --- |\n| LIBDOC | The Library | 1980 | Me | |\n");

            global::Retrocore.Debug.Language.SourceBibliography.For(main, [main, library]).Find("LIBDOC").Should().NotBeNull();
            global::Retrocore.Debug.Language.SourceBibliography.For(main).Find("LIBDOC").Should().BeNull();
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A bibliography is the table of a Markdown file; a later file replaces an earlier one's key.
    /// </summary>
    [TestMethod]
    public void BibliographiesParse()
    {
        DocumentationBibliography bibliography = DocumentationBibliography.Parse(
            Bibliography,
            "| Key | Title | Year | Publisher | Link |\n| --- | --- | --- | --- | --- |\n| TEST | Replaced | 1980 | Me | |\n");

        bibliography.Sources.Keys.Should().BeEquivalentTo("TEST", "BOOK");
        Required(bibliography.Find("TEST")).Description.Should().Be("Replaced, Me, 1980");
        Required(bibliography.Find("BOOK")).Link.Should().Be("https://example.com/book");
    }

    /// <summary>
    ///  The SDK's bibliography, docs/Bibliography.md, parses, with the documents its sources cite.
    /// </summary>
    [TestMethod]
    public void TheSdkBibliographyParses()
    {
        string? root = AppContext.BaseDirectory;
        while (root is not null && !File.Exists(Path.Join(root, "docs", "Bibliography.md")))
        {
            root = Path.GetDirectoryName(root);
        }

        string path = Path.Join(Required(root), "docs", "Bibliography.md");
        DocumentationBibliography bibliography = DocumentationBibliography.Parse(File.ReadAllText(path));
        Required(bibliography.Find("A2RM78")).Title.Should().Be("Apple II Reference Manual");
    }

    /// <summary>
    ///  Conditional assembly sees a historical name as code does, for a definition earlier in the source; an old name
    ///  two definitions give is an error where a condition tests it.
    /// </summary>
    [TestMethod]
    public void ConditionsSeeOldNames()
    {
        AssemblyResult result = Assemble("""
            ;; Prints a character.
            ;; Also: COUT (TEST)
            CharacterOut = $FDED
            .ifdef COUT
            .if COUT = $FDED
                nop
            .endif
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[0].Should().Be(0xEA);

        Assemble("""
            ;; One.
            ;; Also: COUT (TEST)
            First = 1
            ;; Two.
            ;; Also: COUT (TEST)
            Second = 2
            .ifdef COUT
                nop
            .endif
            """).Diagnostics.Select(diagnostic => diagnostic.Message).Should().Equal(
            "'COUT' is a historical name of First and Second: use one of those.");
    }

    /// <summary>
    ///  A <c>.set</c> variable's old name keeps the value documented, in conditionals as in code, after the variable
    ///  is set again.
    /// </summary>
    [TestMethod]
    public void OldNamesOfVariablesKeepTheirValue()
    {
        AssemblyResult result = Assemble("""
            ;; The first width.
            ;; Also: OLD (TEST)
            Width .set 1
            Width .set 2
            .if OLD = 1
                lda #OLD
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA9, 1);
    }

    /// <summary>
    ///  Definitions under conditions that could both hold are not different builds: sharing an old name is reported.
    /// </summary>
    [TestMethod]
    public void IndependentConditionsDoNotShareOldNames()
    {
        DocumentationSet set = Set("""
            FIRST = 1
            SECOND = 1
            .if FIRST
            ;; Prints a character.
            ;; Also: COUT (TEST)
            FirstOut = $FDED
            .endif
            .if SECOND
            ;; Prints a character.
            ;; Also: COUT (TEST)
            SecondOut = $FDF0
            .endif
            """);

        DocumentationResolver resolver = new(set) { Bibliography = DocumentationBibliography.Parse(Bibliography) };
        resolver.Check().Select(diagnostic => diagnostic.Message).Should().Contain(message => message.Contains("has the historical name COUT too"));
    }

    /// <summary>
    ///  Conditionals see a <c>.proc</c>'s old name, as code does.
    /// </summary>
    [TestMethod]
    public void ConditionsSeeOldNamesOfProcedures()
    {
        AssemblyResult result = Assemble("""
            ;; Reads a key.
            ;; Also: RDKEY (TEST)
            .proc ReadKey
                rts
            .endproc
            .ifdef RDKEY
                lda #1
            .else
                lda #2
            .endif
                jsr RDKEY
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..6].ToArray().Should().Equal(0x60, 0xA9, 1, 0x20, 0x00, 0x10);
    }

    /// <summary>
    ///  Conditionals see the old names an included source in another dialect gives, as code does.
    /// </summary>
    [TestMethod]
    public void ConditionsSeeOldNamesInOtherDialects()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-also").FullName;
        try
        {
            File.WriteAllText(
                Path.Join(folder, "Lib.s"),
                "; retrocore: dialect=ca65\n;; Prints a character.\n;; Also: COUT (TEST)\nCharacterOut = $FDED\n");

            string main = Path.Join(folder, "Main.asm");
            string text = ".include \"Lib.s\"\n.ifdef COUT\n    lda #1\n.else\n    lda #2\n.endif\n    jsr COUT\n";
            File.WriteAllText(main, text);
            AssemblyResult result = new NativeAssembler().Assemble(
                new AssemblySource(text, main),
                new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 0x100)
                {
                    SourceResolver = new FileAssemblySourceResolver()
                });

            result.Diagnostics.Should().BeEmpty();
            // The ca65 source brings its segments; the code is in CODE.
            result.Sections.Single(section => section.Name == "CODE").Bytes.Span[..5].ToArray().Should().Equal(0xA9, 1, 0x20, 0xED, 0xFD);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A label at the start of a <c>.proc</c> is inside it, not another name of the routine.
    /// </summary>
    [TestMethod]
    public void LabelsInProceduresAreNotTheirNames()
    {
        DocumentationSet set = Set("""
            ;; Counts down.
            ;; Keeps: Y
            .proc Foo
            Loop:
                dex
                bne Loop
                rts
            .endproc
            Loop:
                rts
            """);

        Required(set.Find("Foo")).EntryLabels.Should().BeEmpty();
        set.FindRoutine("Loop").Should().BeNull();
    }

    /// <summary>
    ///  An <c>Also:</c> on a <c>.scope</c> gives it no address: the old name stays unresolved.
    /// </summary>
    [TestMethod]
    public void ScopesHaveNoOldNames()
    {
        Assemble("""
            ;; The commands.
            ;; Also: OLD (TEST)
            .scope Commands
            Go:
                rts
            .endscope
                jmp OLD
            """).Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("OLD");
    }

    /// <summary>
    ///  Two definitions in different branches of conditional assembly may share an old name: each build has one.
    /// </summary>
    [TestMethod]
    public void BuildVariantsShareOldNames()
    {
        DocumentationSet set = Set("""
            .ifdef ENHANCED
            ;; Prints a character.
            ;; Also: COUT (TEST)
            FirstOut = $FDED
            .else
            ;; Prints a character.
            ;; Also: COUT (TEST)
            SecondOut = $FDF0
            .endif
            """);

        DocumentationResolver resolver = new(set) { Bibliography = DocumentationBibliography.Parse(Bibliography) };
        resolver.Check().Should().BeEmpty();
    }

    private const string Bibliography = """
        | Key | Title | Year | Publisher | Link |
        | --- | --- | --- | --- | --- |
        | TEST | A Test Manual | 1977 | Tester | |
        | BOOK | A Book | 1981 | Publisher | <https://example.com/book> |
        """;

    private static T Required<T>(T? value) where T : class =>
        value ?? throw new AssertFailedException($"Expected a {typeof(T).Name}.");

    private static AssemblyResult Assemble(string text) =>
        new NativeAssembler().Assemble(
            new AssemblySource(text, "test.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 0x100));

    private static DocumentationSet Set(string text) =>
        DocumentationSet.Create([DocumentationParser.Parse(text, "test.asm")], Assemble(text));
}
