// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Historical names: a definition's <c>;; Also:</c> section, which the assembler, the documentation and the
///  language server all accept for the definition (docs/DocComments.md, section 2.4).
/// </summary>
[TestClass]
public sealed partial class HistoricalNameTests
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
    ///  The debugger resolves a historical name, in a watch or a breakpoint, to its definition.
    /// </summary>
    [TestMethod]
    public void OldNamesResolveInTheDebugger()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-also").FullName;
        try
        {
            string path = Path.Join(folder, "Library.asm");
            File.WriteAllText(path, Library);
            AssemblyResult result = new NativeAssembler().Assemble(
                new AssemblySource(Library, path),
                new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 0x100));

            DebugInfo debug = new();
            debug.Add(new SourceMapModule(result, area: null));
            debug.Resolve("CharacterOut").Should().Be(0xFDED);
            debug.Resolve("COUT").Should().Be(0xFDED);
            debug.Resolve("KEYIN").Should().Be(0x1000);
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
    ///  Two models may give one old name to different code: only the build's own definition counts, so a link
    ///  resolves to it, and the two are not reported as sharing the name.
    /// </summary>
    [TestMethod]
    public void OldNamesOfOtherBuildsDontCount()
    {
        DocumentationSet set = Set("""
            ENHANCED = 1
            .if ENHANCED
            ;; Selects the slot's ROM.
            ;; Also: SLOTRTS (TEST)
            SelectSlotRom:
                rts
            .else
            ;; Text that runs as code.
            ;; Also: SLOTRTS (TEST)
            UserText:
                rts
            .endif

            ;; Returns through <SLOTRTS>.
            Echo:
                rts
            """);

        DocumentationResolver resolver = new(set);
        Required(resolver.Resolve(Required(set.Find("Echo")), "SLOTRTS").Topic).Name.Should().Be("SelectSlotRom");
        resolver.Check().Should().BeEmpty();
    }

    /// <summary>
    ///  The same holds when the two builds' conditions are joined in one <c>.if</c>, which the opposite-branch rule
    ///  does not take apart.
    /// </summary>
    [TestMethod]
    public void OldNamesOfOtherBuildsUnderJoinedConditionsDontCount()
    {
        DocumentationSet set = Set("""
            MONITOR = 2
            ENHANCED = 0
            .if MONITOR = 2 && .not ENHANCED
            ;; Text that runs as code.
            ;; Also: SLOTRTS (TEST)
            UserText:
                rts
            .endif
            .if ENHANCED
            ;; Selects the slot's ROM.
            ;; Also: SLOTRTS (TEST)
            SelectSlotRom:
                rts
            .endif

            ;; Returns through <SLOTRTS>.
            Echo:
                rts
            """);

        DocumentationResolver resolver = new(set);
        Required(resolver.Resolve(Required(set.Find("Echo")), "SLOTRTS").Topic).Name.Should().Be("UserText");
        resolver.Check().Should().BeEmpty();
    }

    /// <summary>
    ///  A routine documented in both branches gives each build's old names in that branch's section: one the other
    ///  branch's section gives is not this build's, so it neither resolves to the routine nor counts as shared with
    ///  this build's definition of it.
    /// </summary>
    [TestMethod]
    public void AlsoSectionsOfOtherBuildsDontCount()
    {
        DocumentationSet set = Set("""
            ENHANCED = 1
            .if ENHANCED
            ;; Reads a key.
            ReadKey:
                rts
            ;; Waits for a key.
            ;; Also: OLDKEY (TEST)
            WaitKey:
                rts
            .else
            ;; Reads a key.
            ;; Also: OLDKEY (TEST)
            ReadKey:
                rts
            .endif

            ;; Echoes <OLDKEY>.
            Echo:
                rts
            """);

        DocumentationResolver resolver = new(set);
        Required(resolver.Resolve(Required(set.Find("Echo")), "OLDKEY").Topic).Name.Should().Be("WaitKey");
        resolver.Check().Should().BeEmpty();
    }

    /// <summary>
    ///  A macro defined only in a branch the build doesn't take, or after the <c>.ifdef</c> that tests it, is not
    ///  defined for that <c>.ifdef</c>, as the assembler sees it: the branch's old names are not this build's.
    /// </summary>
    [TestMethod]
    public void AlsoSectionsUnderMacrosTheAssemblerHasNotSeenDontCount()
    {
        DocumentationSet set = Set("""
            .if 0
            .macro FAST
            .endmacro
            .endif
            .ifdef FAST
            ;; Reads a key.
            ;; Also: OLDKEY (TEST)
            ReadKey:
                rts
            .else
            ;; Reads a key.
            ReadKey:
                rts
            ;; Waits for a key.
            ;; Also: OLDKEY (TEST)
            WaitKey:
                rts
            .endif
            .ifdef WIDE
            ;; Scrolls.
            ;; Also: OLDSCROLL (TEST)
            Scroll:
                rts
            .else
            ;; Scrolls.
            Scroll:
                rts
            ;; Scrolls slowly.
            ;; Also: OLDSCROLL (TEST)
            SlowScroll:
                rts
            .endif
            .ifdef WIDE
            ;; The line width.
            ;; Also: OLDWIDTH (TEST)
            WIDTH = 80
            .else
            ;; The line width.
            WIDTH = 40
            ;; The narrow line width.
            ;; Also: OLDWIDTH (TEST)
            NARROW_WIDTH = 40
            .endif
            .macro WIDE
            .endmacro

            ;; Echoes <OLDKEY>, <OLDSCROLL> and <OLDWIDTH>.
            Echo:
                rts
            """);

        DocumentationResolver resolver = new(set);
        DocumentationTopic echo = Required(set.Find("Echo"));
        Required(resolver.Resolve(echo, "OLDKEY").Topic).Name.Should().Be("WaitKey");
        Required(resolver.Resolve(echo, "OLDSCROLL").Topic).Name.Should().Be("SlowScroll");
        Required(resolver.Resolve(echo, "OLDWIDTH").Topic).Name.Should().Be("NARROW_WIDTH");
        resolver.Check().Should().BeEmpty();
    }

    /// <summary>
    ///  Topics that are no symbols (a structure, a scope, a macro) documented once per branch follow the branch the
    ///  assembly took, as labels do: an <c>.ifdef</c> of a macro defined after it is not taken, so its sections are
    ///  another build's, and an old name only they give is not this build's.
    /// </summary>
    [TestMethod]
    public void TopicsOfEveryKindFollowTheBranchTheAssemblyTook()
    {
        DocumentationSet set = Set("""
            .ifdef WIDE
            ;; A screen cell.
            ;; Keeps: X
            .struct Cell
            Left .byte
            Right .byte
            .endstruct
            ;; The screen.
            ;; Keeps: X
            .scope Screen
            .endscope
            ;; Prints a byte.
            ;; Also: PRBYTE (TEST)
            .macro PrintByte
            .endmacro
            .else
            ;; A screen cell.
            ;; Keeps: Y
            .struct Cell
            Only .byte
            .endstruct
            ;; The screen.
            ;; Keeps: Y
            .scope Screen
            .endscope
            ;; Prints a byte.
            .macro PrintByte
            .endmacro
            .endif
            .macro WIDE
            .endmacro

            ;; Prints a byte, the routine.
            ;; Also: PRBYTE (TEST)
            PrintByteRoutine:
                rts
            """);

        foreach (string name in (string[])["Cell", "Screen"])
        {
            DocumentationTopic topic = Required(set.Find(name));
            List<DocumentationSection> keeps = [.. topic.Sections.Where(section => section.Name == "Keeps")];
            keeps.Should().HaveCount(2, name);
            keeps.Single(section => set.InBuild(topic, section)).Text.Should().Be("Y", name);
        }

        set.FindAlso("PRBYTE", thisBuild: true).Should().ContainSingle().Which.Name.Should().Be("PrintByteRoutine");
    }

    /// <summary>
    ///  A definition documented once per branch of an <c>.if</c> inside a macro's body follows the branch its
    ///  expansions took, so an old name only the other branch gives is not this build's.
    /// </summary>
    [TestMethod]
    public void AlsoSectionsInMacroBodiesFollowTheExpansions()
    {
        DocumentationSet set = Set("""
            .macro Entry wide
            .if wide
            ;; Starts.
            ;; Also: OLDSTART (TEST)
            Start:
                rts
            .else
            ;; Starts.
            Start:
                rts
            .endif
            .endmacro
            Entry 0

            ;; Starts, the other way.
            ;; Also: OLDSTART (TEST)
            OtherStart:
                rts
            """);

        DocumentationTopic start = Required(set.Find("Start"));
        set.Gives(start, "OLDSTART", thisBuild: true).Should().BeFalse();
        set.FindAlso("OLDSTART", thisBuild: true).Should().ContainSingle().Which.Name.Should().Be("OtherStart");
    }

    /// <summary>
    ///  Another module is assembled for its default build, which says nothing about the build of the source that
    ///  links into it: an old name two of its builds give is ambiguous there, not its default build's.
    /// </summary>
    [TestMethod]
    public void OldNamesOfAnotherModulesBuildsAreAmbiguous()
    {
        string library = """
            ENHANCED = 1
            .if ENHANCED
            ;; Selects the slot's ROM.
            ;; Also: SLOTRTS (TEST)
            SelectSlotRom:
                rts
            .else
            ;; Text that runs as code.
            ;; Also: SLOTRTS (TEST)
            UserText:
                rts
            .endif
            """;

        DocumentationSet other = DocumentationSet.Create(
            [DocumentationParser.Parse(library, "Library.asm")], Assemble(library), "Library");

        DocumentationSet program = Set("""
            ;; Returns through <SLOTRTS>.
            Echo:
                rts
            """);

        DocumentationTarget target = new DocumentationResolver(program, [other]).Resolve(Required(program.Find("Echo")), "SLOTRTS");
        target.Kind.Should().Be(DocumentationTargetKind.Ambiguous);
    }

    /// <summary>
    ///  Only labels and equates can be left out of a build: a macro that gives an old name a label gives too still
    ///  counts, so the name is ambiguous rather than the label's.
    /// </summary>
    [TestMethod]
    public void OldNamesOfMacrosAlwaysCount()
    {
        DocumentationSet set = Set("""
            ;; Prints a byte.
            ;; Also: PRBYTE (TEST)
            .macro PrintByte
                rts
            .endmacro

            ;; Prints a byte, the routine.
            ;; Also: PRBYTE (TEST)
            PrintByteRoutine:
                rts

            ;; Prints through <PRBYTE>.
            Echo:
                rts
            """);

        DocumentationTarget target = new DocumentationResolver(set).Resolve(Required(set.Find("Echo")), "PRBYTE");
        target.Kind.Should().Be(DocumentationTargetKind.Ambiguous);
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
