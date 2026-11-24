// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;

namespace Retrocore.Tests;

// Historical names of definitions in macro bodies: an Also: section there reaches the definition when the build
// expands it exactly once (docs/DocComments.md, section 2.4).
public sealed partial class HistoricalNameTests
{
    // A library macro whose body documents a routine with an old name, expanded once in a scope.
    private const string MacroLibrary = """
        .macro Library
        ;; Requires a comma and reads a byte.
        ;; Also: COMBYTE (TEST)
        COMBYT:
            rts
        .endmacro
        """;

    /// <summary>
    ///  An old name in a macro's body that the build expands once reaches the symbol the expansion defines, qualified
    ///  by the scope it is expanded in: in code before and after it, in conditionals after it, and in the assembly's
    ///  historical names.
    /// </summary>
    [TestMethod]
    public void OldNamesInAMacroExpandedOnceAssemble()
    {
        AssemblyResult result = Assemble($"""
            {MacroLibrary}
                jsr COMBYTE
            .scope Basic
                Library
            .endscope
            .ifdef COMBYTE
                jmp COMBYTE
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Symbols["Basic::COMBYT"].Should().Be(0x1003);
        result.Sections[0].Bytes.Span[..7].ToArray().Should().Equal(0x20, 0x03, 0x10, 0x60, 0x4C, 0x03, 0x10);
        result.HistoricalNames["COMBYTE"].Name.Should().Be("Basic::COMBYT");
    }

    /// <summary>
    ///  An old name in a macro's body that the build expands twice reaches neither definition: code using it is an
    ///  error, and a conditional after the second expansion doesn't see it.
    /// </summary>
    [TestMethod]
    public void OldNamesInAMacroExpandedTwiceReachNothing()
    {
        AssemblyResult result = Assemble($"""
            {MacroLibrary}
            .scope First
                Library
            .endscope
            .scope Second
                Library
            .endscope
            .ifdef COMBYTE
                .byte $FF
            .endif
                jsr COMBYTE
            """);

        string message = result.Diagnostics.Should().ContainSingle().Subject.Message;
        message.Should().Contain("COMBYTE").And.NotContain("historical name");
        result.HistoricalNames.Should().NotContainKey("COMBYTE");

        Assemble($"""
            {MacroLibrary}
            .scope First
                Library
            .endscope
            .scope Second
                Library
            .endscope
            .ifdef COMBYTE
                .byte $FF
            .endif
            """).Sections[0].Bytes.Span[..3].ToArray().Should().Equal(0x60, 0x60, 0x00);
    }

    /// <summary>
    ///  An old name in the body of a macro the build never expands reaches nothing.
    /// </summary>
    [TestMethod]
    public void OldNamesInAMacroNeverExpandedReachNothing()
    {
        AssemblyResult result = Assemble($"""
            {MacroLibrary}
                jsr COMBYTE
            """);

        result.Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("COMBYTE");

        // Nor does the lint check it, though its old name is also a definition: the build has no such definition.
        Check($"{MacroLibrary}\nCOMBYTE = 1\n").Should().BeEmpty();

        // Also beside a definition outside the macro that shares its topic, which the build assembles.
        Check($"{MacroLibrary}\nCOMBYT = 1\nCOMBYTE = 1\n").Should().BeEmpty();
    }

    /// <summary>
    ///  An expansion in a branch of conditional assembly the build leaves out doesn't count, so the one the build
    ///  takes has the old name.
    /// </summary>
    [TestMethod]
    public void OldNamesInAMacroExpandedUnderAConditionAssemble()
    {
        AssemblyResult result = Assemble($"""
            {MacroLibrary}
            ENHANCED = 1
            .if ENHANCED
                Library
            .else
                Library
            .endif
                jsr COMBYTE
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..4].ToArray().Should().Equal(0x60, 0x20, 0x00, 0x10);
    }

    /// <summary>
    ///  A macro expanded by another macro's body has the old names of its own body, once the build expands it once.
    /// </summary>
    [TestMethod]
    public void OldNamesInNestedMacrosAssemble()
    {
        AssemblyResult result = Assemble($"""
            {MacroLibrary}
            .macro Interpreter
                nop
                Library
            .endmacro
                Interpreter
                jsr COMBYTE
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..5].ToArray().Should().Equal(0xEA, 0x60, 0x20, 0x01, 0x10);
    }

    /// <summary>
    ///  A member of a type defined in a macro's body has its old name, qualified by the type, as anywhere else.
    /// </summary>
    [TestMethod]
    public void OldNamesOfMembersInAMacroAssemble()
    {
        AssemblyResult result = Assemble("""
            .macro Types
            ;; An I/O block.
            .struct Iob
                ;; The block's type.
                TYPE .byte
                ;; The command.
                ;; Also: IBCMD (TEST)
                COMMAND .byte
            .endstruct
            .endmacro
                Types
                lda #IBCMD
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA9, 0x01);
    }

    /// <summary>
    ///  A definition named by a macro's parameter, or local to each expansion, has no old name, even when the build
    ///  expands the macro once: each expansion names it differently.
    /// </summary>
    [TestMethod]
    public void OldNamesOfNamesThatVaryByExpansionReachNothing()
    {
        Assemble("""
            .macro Entry name
            ;; An entry.
            ;; Also: OLD (TEST)
            name:
                rts
            .endmacro
                Entry Start
                jsr OLD
            """).Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("OLD");

        Assemble("""
            .macro Delay
                .local again
            ;; Waits.
            ;; Also: OLD (TEST)
            again:
                dex
                bne again
            .endmacro
                Delay
                jsr OLD
            """).Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("OLD");

        Assemble("""
            .macro Scan
            ;; A loop.
            ;; Also: OLD (TEST)
            @loop:
                dex
                bne @loop
            .endmacro
                Scan
                jsr OLD
            """).Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("OLD");
    }

    /// <summary>
    ///  Links and <see cref="DocumentationSet.FindAlso"/> reach a definition in a macro's body by its old name when the
    ///  build expands it once, and its topic has the expansion's value; expanded twice or never, the old name finds
    ///  nothing.
    /// </summary>
    [TestMethod]
    public void LinksToOldNamesInAMacroResolve()
    {
        string once = $"""
            {MacroLibrary}

            ;; Reads through <COMBYTE>.
            Echo:
                rts
            .scope Basic
                Library
            .endscope
            """;

        DocumentationSet set = Set(once);
        DocumentationTopic topic = Required(set.Find("COMBYT"));
        topic.Value.Should().Be(0x1001);
        set.SymbolOf(topic).Should().Be("Basic::COMBYT");
        set.FindAlso("COMBYTE", thisBuild: true).Should().ContainSingle().Which.Name.Should().Be("COMBYT");
        DocumentationResolver resolver = new(set) { Bibliography = DocumentationBibliography.Parse(Bibliography) };
        resolver.Resolve(Required(set.Find("Echo")), "COMBYTE").Topic?.Name.Should().Be("COMBYT");
        resolver.Check().Should().BeEmpty();

        DocumentationSet twice = Set(once + "\n.scope Other\n    Library\n.endscope\n");
        twice.FindAlso("COMBYTE", thisBuild: true).Should().BeEmpty();
        twice.FindAlso("COMBYTE").Should().BeEmpty();
        twice.AlsoOf(Required(twice.Find("COMBYT"))).Should().BeEmpty();

        DocumentationSet never = Set($"{MacroLibrary}\n");
        never.FindAlso("COMBYTE").Should().BeEmpty();

        // A link by the old name reaches nothing either, and is reported; one by the current name still resolves.
        string linked = $"{MacroLibrary}\n;; Reads through <COMBYTE> and <COMBYT>.\nEcho:\n    rts\n";
        Check(linked).Should().ContainSingle().Which.Message.Should().Contain("'COMBYTE'");
    }

    /// <summary>
    ///  The lint reports an <c>Also:</c> in the body of a macro the build expands more than once, and one on a name
    ///  that varies by expansion, as errors; one in a macro the build doesn't expand isn't checked, as a definition
    ///  another build assembles isn't; one expanded once is checked as any other, its clashes among them.
    /// </summary>
    [TestMethod]
    public void AlsoSectionsInMacrosAreChecked()
    {
        DocumentationDiagnostic twice = Required(Check($"""
            {MacroLibrary}
            .scope First
                Library
            .endscope
            .scope Second
                Library
            .endscope
            """).Should().ContainSingle().Subject);

        twice.Rule.Should().Be(DocumentationRules.Also);
        twice.Severity.Should().Be(DocumentationSeverity.Error);
        twice.Line.Should().Be(2);
        twice.Message.Should().Be(
            "Also: COMBYT is defined 2 times, by expansions of the macro Library, so an old name can't reach any of "
                + "them; give the old name in prose.");

        Check("""
            .macro Entry name
            ;; An entry.
            ;; Also: OLD (TEST)
            name:
                rts
            .endmacro
                Entry Start
            """).Select(diagnostic => (diagnostic.Severity, diagnostic.Message)).Should().Equal((
            DocumentationSeverity.Error,
            "Also: name is named by a parameter of the macro Entry, so each expansion names it after its argument and "
                + "an old name can't reach it; give the old name in prose."));

        Check("""
            .macro Delay
                .local again
            ;; Waits.
            ;; Also: OLD (TEST)
            again:
                dex
                bne again
            .endmacro
                Delay
            """).Select(diagnostic => (diagnostic.Severity, diagnostic.Message)).Should().Equal((
            DocumentationSeverity.Error,
            "Also: again is local to each expansion of the macro Delay, so an old name can't reach it; give the old "
                + "name in prose."));

        Check("""
            .macro Scan
            ;; A loop.
            ;; Also: OLD (TEST)
            @loop:
                dex
                bne @loop
            .endmacro
                Scan
            """).Select(diagnostic => diagnostic.Message).Should().Equal(
            "Also: @loop is local to each expansion of the macro Scan, so an old name can't reach it; give the old "
                + "name in prose.");

        Check($"{MacroLibrary}\n").Should().BeEmpty();

        // A name expanded twice is no clash with another definition that gives it, which alone has it.
        Check($"""
            {MacroLibrary}
            .scope First
                Library
            .endscope
            .scope Second
                Library
            .endscope
            ;; Another reader.
            ;; Also: COMBYTE (TEST)
            Other:
                rts
            """).Should().ContainSingle().Which.Message.Should().StartWith("Also: COMBYT is defined 2 times");

        Check($"""
            {MacroLibrary}
                Library
            ;; Another reader.
            ;; Also: COMBYTE (TEST)
            Other:
                rts
            """).Select(diagnostic => diagnostic.Message).Should().BeEquivalentTo(
            "Also: COMBYT has the historical name COMBYTE too.",
            "Also: Other has the historical name COMBYTE too.");
    }

    /// <summary>
    ///  The debugger resolves an old name in a macro's body that the build expands once, and not one expanded twice.
    /// </summary>
    [TestMethod]
    public void OldNamesInAMacroResolveInTheDebugger()
    {
        SourceMapModule once = new(Assemble($"{MacroLibrary}\n.scope Basic\n    Library\n.endscope\n"), area: null);
        once.TryResolve("COMBYTE", out long value).Should().BeTrue();
        value.Should().Be(0x1000);

        SourceMapModule twice = new(
            Assemble($"{MacroLibrary}\n.scope A\n    Library\n.endscope\n.scope B\n    Library\n.endscope\n"),
            area: null);

        twice.TryResolve("COMBYTE", out _).Should().BeFalse();
    }

    /// <summary>
    ///  A definition outside a macro keeps its own old name when a macro's body defines one of the same name, which
    ///  shares its topic: whether the build expands the macro never, once in a scope, or twice, the old name reaches
    ///  the definition outside, the topic is that definition's, and the lint reports nothing about the macro.
    /// </summary>
    [TestMethod]
    public void OldNamesOutsideAMacroKeepWorkingBesideOne()
    {
        const string Source = """
            .macro Library
            ;; A macro reader.
            COMBYT:
                rts
            .endmacro
            ;; Top-level reader.
            ;; Also: COMBYTE (TEST)
            COMBYT:
                rts
            ;; Reads through <COMBYTE>.
            Echo:
                jsr COMBYTE
            """;

        foreach (string expansions in (string[])["", ".scope A\n    Library\n.endscope\n", ".scope A\n    Library\n.endscope\n.scope B\n    Library\n.endscope\n"])
        {
            string text = $"{Source}\n{expansions}";
            Assemble(text).HistoricalNames["COMBYTE"].Name.Should().Be("COMBYT");
            DocumentationSet set = Set(text);
            DocumentationTopic topic = set.FindAlso("COMBYTE", thisBuild: true).Should().ContainSingle().Subject;
            set.SymbolOf(topic).Should().Be("COMBYT");
            topic.Value.Should().Be(0x1000);
            set.AlsoOf(topic).Select(also => also.Name).Should().Equal("COMBYTE");
            Check(text).Should().BeEmpty();
        }
    }

    /// <summary>
    ///  A <c>.set</c> variable in a macro's body has no old name, as its versions differ by assignment: the assembler
    ///  and the documentation resolve nothing, and the lint reports it.
    /// </summary>
    [TestMethod]
    public void OldNamesOfVariablesInAMacroReachNothing()
    {
        const string Text = """
            .macro Bump
            ;; A counter.
            ;; Also: OLD (TEST)
            COUNT .set 1
            .endmacro
                Bump
                .byte OLD
            """;

        Assemble(Text).Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("OLD");
        Set(Text).FindAlso("OLD").Should().BeEmpty();

        // No build could give it, so the lint reports it though the macro is never expanded, beside an assignment
        // outside the macro or not.
        string unexpanded = Text.Replace("    Bump\n    .byte OLD", "Start:\n    rts", StringComparison.Ordinal);
        Check(unexpanded).Should().ContainSingle().Which.Severity.Should().Be(DocumentationSeverity.Error);
        Check("COUNT .set 0\n" + unexpanded).Should().ContainSingle().Which.Severity.Should().Be(DocumentationSeverity.Error);

        // Nor could one a parameter names, so it is reported unexpanded, and where expansions are not known.
        const string Parameter = """
            .macro Entry name
            ;; An entry.
            ;; Also: OLD (TEST)
            name:
                rts
            .endmacro
            Start:
                rts
            """;

        Check(Parameter).Should().ContainSingle().Which.Message.Should().Contain("named by a parameter");
        DocumentationSet unknown = DocumentationSet.Create(
            [DocumentationParser.Parse(Parameter, "test.asm")],
            new Dictionary<string, long> { ["Start"] = 0x1000 });

        DocumentationResolver resolver = new(unknown) { Bibliography = DocumentationBibliography.Parse(Bibliography) };
        resolver.Check().Should().ContainSingle().Which.Message.Should().Contain("named by a parameter");
        Check(Text).Select(diagnostic => (diagnostic.Severity, diagnostic.Message)).Should().Equal((
            DocumentationSeverity.Error,
            "Also: COUNT is a .set variable in the macro Bump, which each assignment gives a new version, so an old "
                + "name can't reach it; give the old name in prose."));
    }

    /// <summary>
    ///  A member of a type in a macro's body, and a macro expanded by another macro's body under a condition: the
    ///  documentation finds each old name, and links to it resolve, as in the assembler.
    /// </summary>
    [TestMethod]
    public void OldNamesInMacroVariantsAreDocumented()
    {
        DocumentationSet members = Set("""
            .macro Types
            ;; An I/O block.
            .struct Iob
                ;; The block's type.
                TYPE .byte
                ;; The command.
                ;; Also: IBCMD (TEST)
                COMMAND .byte
            .endstruct
            .endmacro
                Types
            ;; Uses <IBCMD>.
            Echo:
                rts
            """);

        members.FindAlso("IBCMD", thisBuild: true).Should().ContainSingle().Which.Name.Should().Be("Iob::COMMAND");
        new DocumentationResolver(members).Resolve(Required(members.Find("Echo")), "IBCMD").Topic?.Name
            .Should().Be("Iob::COMMAND");

        DocumentationSet nested = Set($"""
            {MacroLibrary}
            .macro Interpreter
                Library
            .endmacro
            ENHANCED = 0
            .if ENHANCED
                Interpreter
            .else
                Interpreter
            .endif
            """);

        nested.FindAlso("COMBYTE", thisBuild: true).Should().ContainSingle().Which.Name.Should().Be("COMBYT");
    }

    /// <summary>
    ///  A ca65 <c>.macro</c>'s body gives old names as a native one's does.
    /// </summary>
    [TestMethod]
    public void OldNamesInCa65MacrosAssemble()
    {
        string text = $"; retrocore: dialect=ca65\n{MacroLibrary}\n    Library\n    jsr COMBYTE\n";
        AssemblyResult result = Assemble(text);
        result.Diagnostics.Should().BeEmpty();
        result.HistoricalNames["COMBYTE"].Name.Should().Be("COMBYT");
        Set(text).FindAlso("COMBYTE").Should().ContainSingle();

        // The short forms open and close a macro too, so a definition after one is no macro's.
        string shorter = """
            ; retrocore: dialect=ca65
            .mac Library
            ;; Requires a comma and reads a byte.
            ;; Also: COMBYTE (TEST)
            COMBYT:
                rts
            .endmac
            ;; Top-level.
            ;; Also: OLD (TEST)
            NEW:
                rts
                Library
                jsr COMBYTE
                jsr OLD
            """;

        AssemblyResult abbreviated = Assemble(shorter);
        abbreviated.Diagnostics.Should().BeEmpty();
        abbreviated.HistoricalNames["COMBYTE"].Name.Should().Be("COMBYT");
        DocumentationSet set = Set(shorter);
        Required(set.Find("COMBYT")).Comments[0].Macro.Should().Be("Library");
        Required(set.Find("NEW")).Comments[0].Macro.Should().BeNull();
        set.FindAlso("OLD").Should().ContainSingle();
    }

    /// <summary>
    ///  Two macros' bodies that each define the same name, expanded once in different scopes, share a topic: each old
    ///  name reaches the symbol its own macro's expansion defined, in the documentation as in the assembler.
    /// </summary>
    [TestMethod]
    public void OldNamesOfTwoMacrosDefiningOneNameReachTheirOwn()
    {
        const string Text = """
            .macro First
            ;; One reader.
            ;; Also: OLDA (TEST)
            COMBYT:
                rts
            .endmacro
            .macro Second
            ;; Another reader.
            ;; Also: OLDB (TEST)
            COMBYT:
                rts
            .endmacro
            .scope A
                First
            .endscope
            .scope B
                Second
            .endscope
            """;

        AssemblyResult result = Assemble(Text);
        result.HistoricalNames["OLDA"].Name.Should().Be("A::COMBYT");
        result.HistoricalNames["OLDB"].Name.Should().Be("B::COMBYT");
        DocumentationSet set = Set(Text);
        set.SymbolOf(set.FindAlso("OLDA", thisBuild: true).Should().ContainSingle().Subject, "OLDA").Should().Be("A::COMBYT");
        set.SymbolOf(set.FindAlso("OLDB", thisBuild: true).Should().ContainSingle().Subject, "OLDB").Should().Be("B::COMBYT");
        DocumentationTopic shared = Required(set.FindSymbol("A::COMBYT"));
        set.FindSymbol("B::COMBYT").Should().BeSameAs(shared);
        set.AlsoOf(shared, "A::COMBYT").Select(also => also.Name).Should().Equal("OLDA");
        set.AlsoOf(shared, "B::COMBYT").Select(also => also.Name).Should().Equal("OLDB");

        // A link by an old name reaches its own symbol, with that symbol's value.
        DocumentationSet linked = Set(Text + "\n;; Reads through <OLDA> and <OLDB>.\nEcho:\n    rts\n");
        DocumentationResolver resolver = new(linked);
        DocumentationTopic echo = Required(linked.Find("Echo"));
        DocumentationTarget second = resolver.Resolve(echo, "OLDB");
        second.Name.Should().Be("B::COMBYT");
        second.Value.Should().Be(linked.Symbols["B::COMBYT"]);
        resolver.Resolve(echo, "OLDA").Name.Should().Be("A::COMBYT");
    }

    /// <summary>
    ///  Where a macro's body and a definition outside it share a topic, each symbol has only its own old names: the
    ///  ones completion and workspace symbols match it by.
    /// </summary>
    [TestMethod]
    public void OldNamesOfASharedTopicBelongToTheirOwnSymbol()
    {
        const string Text = """
            .macro Library
            ;; A macro reader.
            ;; Also: OLDM (TEST)
            COMBYT:
                rts
            .endmacro
            ;; Top-level reader.
            ;; Also: COMBYTE (TEST)
            COMBYT:
                rts
            .scope Basic
                Library
            .endscope
            """;

        DocumentationSet set = Set(Text);
        DocumentationTopic topic = Required(set.FindSymbol("Basic::COMBYT"));
        set.FindSymbol("COMBYT").Should().BeSameAs(topic);
        set.AlsoOf(topic, "Basic::COMBYT").Select(also => also.Name).Should().Equal("OLDM");
        set.AlsoOf(topic, "COMBYT").Select(also => also.Name).Should().Equal("COMBYTE");
        set.SymbolOf(topic, "OLDM").Should().Be("Basic::COMBYT");
        set.SymbolOf(topic, "COMBYTE").Should().Be("COMBYT");

        // Links reach each old name's own definition and value.
        DocumentationSet linked = Set(Text + "\n;; Reads through <OLDM> and <COMBYTE>.\nEcho:\n    rts\n");
        DocumentationResolver resolver = new(linked);
        DocumentationTopic echo = Required(linked.Find("Echo"));
        resolver.Resolve(echo, "OLDM").Value.Should().Be(linked.Symbols["Basic::COMBYT"]);
        resolver.Resolve(echo, "COMBYTE").Value.Should().Be(linked.Symbols["COMBYT"]);
    }

    /// <summary>
    ///  A line the build defines three times reaches nothing, in conditionals after any of the expansions, and the
    ///  lint counts all three.
    /// </summary>
    [TestMethod]
    public void OldNamesInAMacroExpandedThriceReachNothing()
    {
        string text = $"""
            {MacroLibrary}
            .scope A
                Library
            .endscope
            .scope B
                Library
            .endscope
            .scope C
                Library
            .endscope
            .ifdef COMBYTE
                .byte $FF
            .endif
            """;

        Assemble(text).Sections[0].Bytes.Span[..4].ToArray().Should().Equal(0x60, 0x60, 0x60, 0x00);
        Check(text).Should().ContainSingle().Which.Message.Should().StartWith("Also: COMBYT is defined 3 times");
    }

    /// <summary>
    ///  A Merlin macro's body gives its definitions no old names.
    /// </summary>
    [TestMethod]
    public void OldNamesInMerlinMacrosReachNothing()
    {
        Assemble("""
            ; retrocore: dialect=merlin
            Emit    MAC
            ;; A reader.
            ;; Also: OLD (TEST)
            Reader  RTS
                    EOM
                    PMC Emit
                    JSR OLD
            """).Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("OLD");
    }

    /// <summary>
    ///  A topic that a macro's body shares with a definition under conditional assembly still counts only the
    ///  branch the build takes, so another definition's old name isn't reported as shared with the other branch.
    /// </summary>
    [TestMethod]
    public void OldNamesOfOtherBuildsDontCountBesideAMacro()
    {
        const string Text = """
            MODEL = 1
            .macro Library
            ;; A macro reader.
            FOO:
                rts
            .endmacro
            .if MODEL = 1
            ;; One model's.
            ;; Also: OLDX (TEST)
            FOO = 1
            .else
            ;; The other's.
            ;; Also: OLDY (TEST)
            FOO = 2
            .endif
            ;; Another.
            ;; Also: OLDY (TEST)
            BAR = 3
            """;

        DocumentationSet set = Set(Text);
        set.FindAlso("OLDY", thisBuild: true).Should().ContainSingle().Which.Name.Should().Be("BAR");
        set.FindAlso("OLDX", thisBuild: true).Should().ContainSingle().Which.Name.Should().Be("FOO");
    }

    /// <summary>
    ///  A definition in a macro's body that the build expands in a scope, whose plain name is no symbol, is checked
    ///  by the lint as any assembled definition is.
    /// </summary>
    [TestMethod]
    public void DefinitionsInAMacroExpandedInAScopeAreChecked()
    {
        Check("""
            .macro Library
            ;; Reads through <Nowhere>.
            COMBYT:
                rts
            .endmacro
            .scope Basic
                Library
            .endscope
            """).Select(diagnostic => diagnostic.Rule).Should().Equal(DocumentationRules.Link);
    }

    /// <summary>
    ///  The documented gap: a conditional between a line's first expansion and its second sees the old name, as the
    ///  assembler learns of the second only there; the lint reports the line defined twice.
    /// </summary>
    [TestMethod]
    public void ConditionsBetweenTwoExpansionsSeeTheFirst()
    {
        string text = $"""
            {MacroLibrary}
            .scope A
                Library
            .endscope
            .ifdef COMBYTE
                .byte $FF
            .endif
            .scope B
                Library
            .endscope
            """;

        Assemble(text).Sections[0].Bytes.Span[..3].ToArray().Should().Equal(0x60, 0xFF, 0x60);
        Check(text).Should().ContainSingle().Which.Severity.Should().Be(DocumentationSeverity.Error);
    }

    /// <summary>
    ///  A name in a nested macro's body that an outer macro's parameter gives differs by the outer expansion, so it
    ///  has no old name, and the lint says why.
    /// </summary>
    [TestMethod]
    public void OldNamesOfNamesAnOuterParameterGivesReachNothing()
    {
        const string Text = """
            .macro Outer name
            .macro Inner
            ;; An entry.
            ;; Also: OLD (TEST)
            name:
                rts
            .endmacro
                Inner
            .endmacro
                Outer Start
            """;

        Assemble(Text + "\n    jsr OLD\n").Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("OLD");
        Check(Text).Select(diagnostic => diagnostic.Message).Should().Equal(
            "Also: name is named by a parameter of the macro Inner, so each expansion names it after its argument and "
                + "an old name can't reach it; give the old name in prose.");
    }

    /// <summary>
    ///  Two macros' bodies that define one name and give it the same old name share a topic; the lint reports the
    ///  old name both give, which the assembler can't choose between.
    /// </summary>
    [TestMethod]
    public void OldNamesTwoMacrosShareAreChecked()
    {
        const string Text = """
            .macro First
            ;; One reader.
            ;; Also: OLD (TEST)
            COMBYT:
                rts
            .endmacro
            .macro Second
            ;; Another reader.
            ;; Also: OLD (TEST)
            COMBYT:
                rts
            .endmacro
            .scope A
                First
            .endscope
            .scope B
                Second
            .endscope
            """;

        string ambiguous = "'OLD' is a historical name of A::COMBYT and B::COMBYT: use one of those.";
        Assemble(Text + "\n    jsr OLD\n").Diagnostics.Should().ContainSingle().Which.Message.Should().Be(ambiguous);

        string expected = "Also: OLD is given by two definitions of COMBYT, A::COMBYT and B::COMBYT, so code can't "
            + "tell which it means; give it to one of them.";

        Check(Text).Select(diagnostic => diagnostic.Message).Should().Equal(expected);
    }

    /// <summary>
    ///  A macro's body and a definition outside it that share a topic and give the same old name clash, as two topics
    ///  would; the assembler can't choose between them either.
    /// </summary>
    [TestMethod]
    public void OldNamesAMacroSharesWithADefinitionOutsideItAreChecked()
    {
        const string Text = """
            .macro Library
            ;; A macro reader.
            ;; Also: OLD (TEST)
            COMBYT:
                rts
            .endmacro
            ;; Top-level reader.
            ;; Also: OLD (TEST)
            COMBYT:
                rts
            .scope Basic
                Library
            .endscope
            """;

        Assemble(Text + "\n    jsr OLD\n").Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("historical name");
        Check(Text).Select(diagnostic => diagnostic.Message).Should().Equal(
            "Also: OLD is given by two definitions of COMBYT, Basic::COMBYT and COMBYT, so code can't tell which it "
                + "means; give it to one of them.");
    }

    /// <summary>
    ///  An outer macro's <c>.local</c> name in a nested macro's body differs by expansion, and a type in a macro's
    ///  body has no old name, in the documentation as in the assembler.
    /// </summary>
    [TestMethod]
    public void OldNamesOfOuterLocalsAndTypesInMacrosReachNothing()
    {
        Check("""
            .macro Outer
                .local again
            .macro Inner
            ;; Waits.
            ;; Also: OLD (TEST)
            again:
                rts
            .endmacro
                Inner
            .endmacro
                Outer
            """).Select(diagnostic => diagnostic.Message).Should().Equal(
            "Also: again is local to each expansion of the macro Inner, so an old name can't reach it; give the old "
                + "name in prose.");

        DocumentationSet types = Set("""
            .macro Types
            ;; A block.
            ;; Also: OLDT (TEST)
            .struct Block
                ;; Its type.
                TYPE .byte
            .endstruct
            .endmacro
                Types
            """);

        types.FindAlso("OLDT").Should().BeEmpty();
        types.AlsoOf(Required(types.Find("Block"))).Should().BeEmpty();
        Check("""
            .macro Types
            ;; A block.
            ;; Also: OLDT (TEST)
            .struct Block
                ;; Its type.
                TYPE .byte
            .endstruct
            .endmacro
                Types
            """).Select(diagnostic => diagnostic.Message).Should().Equal(
            "Also: Block is a scope or type, which an old name cannot reach; give old names to its members.");
    }

    /// <summary>
    ///  A diagnostic about a macro's body is in the file of that body's comment, though another file's definition of
    ///  the name is first in the topic.
    /// </summary>
    [TestMethod]
    public void MacroDiagnosticsAreInTheMacrosFile()
    {
        string folder = Directory.CreateTempSubdirectory("retrocore-also").FullName;
        try
        {
            string first = Path.Join(folder, "First.inc");
            string second = Path.Join(folder, "Second.inc");
            string main = Path.Join(folder, "Main.asm");
            File.WriteAllText(first, ".macro MA\n;; One.\n;; Also: OLDA (TEST)\nX:\n    rts\n.endmacro\n");
            File.WriteAllText(second, "; Second.\n;\n;\n.macro MB\n;; Two.\n;; Also: OLDB (TEST)\nX:\n    rts\n.endmacro\n");
            string text = """
                .include "First.inc"
                .include "Second.inc"
                .scope S1
                    MA
                .endscope
                .scope S2
                    MB
                .endscope
                .scope S3
                    MB
                .endscope
                """;

            File.WriteAllText(main, text);
            AssemblyResult result = new Retrocore.Assembler.Assembler().Assemble(
                new AssemblySource(text, main),
                new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 0x100)
                {
                    SourceResolver = new FileAssemblySourceResolver()
                });

            result.Diagnostics.Should().BeEmpty();
            List<DocumentationFile> files = [];
            foreach (string path in (string[])[main, first, second])
            {
                files.Add(DocumentationParser.Parse(File.ReadAllText(path), path));
            }

            DocumentationSet set = DocumentationSet.Create(files, result);
            DocumentationResolver resolver = new(set) { Bibliography = DocumentationBibliography.Parse(Bibliography) };
            DocumentationDiagnostic diagnostic = resolver.Check().Should().ContainSingle().Subject;

            diagnostic.Path.Should().Be(second);
            diagnostic.Line.Should().Be(5);

            // So is a check of the second macro's own section, expanded once.
            File.WriteAllText(second, "; Second.\n;\n;\n.macro MB\n;; Two.\n;; Also: OLDB (NOSUCH)\nX:\n    rts\n.endmacro\n");
            string once = text[..text.IndexOf(".scope S3", StringComparison.Ordinal)];
            File.WriteAllText(main, once);
            AssemblyResult built = new Retrocore.Assembler.Assembler().Assemble(
                new AssemblySource(once, main),
                new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 0x100)
                {
                    SourceResolver = new FileAssemblySourceResolver()
                });

            built.Diagnostics.Should().BeEmpty();
            files = [.. ((string[])[main, first, second]).Select(path => DocumentationParser.Parse(File.ReadAllText(path), path))];
            DocumentationResolver cited = new(DocumentationSet.Create(files, built))
            {
                Bibliography = DocumentationBibliography.Parse(Bibliography)
            };

            DocumentationDiagnostic unknown = cited.Check().Should().ContainSingle().Subject;
            unknown.Message.Should().Contain("NOSUCH");
            unknown.Path.Should().Be(second);
            unknown.Line.Should().Be(5);

            // And a section two definitions share, written first in the second file after a bare Inherit: in the first.
            File.WriteAllText(first, ".macro MA\n;; One.\n;; Inherit:\nX:\n    rts\n.endmacro\n");
            File.WriteAllText(second, "; Second.\n;\n;\n.macro MB\n;; Two.\n;; Include: nofile.txt\nX:\n    rts\n.endmacro\n.macro MC\n;; Three.\n;; Include: nofile.txt\nX:\n    rts\n.endmacro\n");
            string three = once + ".scope S3\n    MC\n.endscope\n";
            File.WriteAllText(main, three);
            AssemblyResult shared = new Retrocore.Assembler.Assembler().Assemble(
                new AssemblySource(three, main),
                new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 0x100)
                {
                    SourceResolver = new FileAssemblySourceResolver()
                });

            shared.Diagnostics.Should().BeEmpty();
            files = [.. ((string[])[main, first, second]).Select(path => DocumentationParser.Parse(File.ReadAllText(path), path))];
            List<DocumentationDiagnostic> included = new DocumentationResolver(DocumentationSet.Create(files, shared)).Check();
            DocumentationDiagnostic missing = included.Should().ContainSingle(item => item.Message.StartsWith("Include:")).Subject;
            missing.Path.Should().Be(second);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  Old names a macro's body shares with a definition outside it count only in the build's branch of conditional
    ///  assembly; a definition in a macro's body is judged by its expansion, not by the body's own conditions.
    /// </summary>
    [TestMethod]
    public void OldNamesBesideAMacroCountOnlyInTheBuild()
    {
        Check("""
            MODEL = 1
            .macro Library
            ;; A macro reader.
            ;; Also: OLD (TEST)
            FOO:
                rts
            .endmacro
            .if MODEL = 1
            ;; One model's.
            FOO = 1
            .else
            ;; The other's.
            ;; Also: OLD (TEST)
            FOO = 2
            .endif
            .scope Basic
                Library
            .endscope
            """).Should().BeEmpty();

        DocumentationSet set = Set("""
            flag = 0
            .macro Library flag
            .if flag
            ;; A reader.
            ;; Also: OLD (TEST)
            COMBYT:
                rts
            .endif
            .endmacro
            .scope Basic
                Library 1
            .endscope
            ;; Another, by the same old name.
            ;; Also: OLD (TEST)
            Other:
                rts
            """);

        set.FindAlso("OLD", thisBuild: true).Select(topic => topic.Name).Should().Equal("COMBYT", "Other");
    }

    /// <summary>
    ///  A definition in a scope a macro's parameter names differs by expansion too: no old name, and the lint says
    ///  why.
    /// </summary>
    [TestMethod]
    public void OldNamesInAScopeAParameterNamesReachNothing()
    {
        const string Text = """
            .macro Entry name
            .scope name
            ;; An entry.
            ;; Also: OLD (TEST)
            X:
                rts
            .endscope
            .endmacro
                Entry Foo
            """;

        Assemble(Text + "\n    jsr OLD\n").Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("OLD");
        Check(Text).Should().ContainSingle().Which.Message.Should().StartWith("Also: name::X is named by a parameter");
        Set(Text).FindAlso("OLD", thisBuild: true).Should().BeEmpty();

        // Nor does a scope a .local name names, whose name is made up for each expansion.
        const string Local = """
            .macro Entry
            .local S
            .scope S
            ;; An entry.
            ;; Also: OLD (TEST)
            X:
                rts
            .endscope
            .endmacro
                Entry
            """;

        Assemble(Local + "\n    jsr OLD\n").Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("OLD");
        Check(Local).Should().ContainSingle().Which.Message.Should().StartWith("Also: S::X is local to");
        Set(Local).FindAlso("OLD", thisBuild: true).Should().BeEmpty();

        // A scope around the macro's definition isn't the expansion's, though a parameter has its name.
        const string Around = """
            .scope Draw
            .macro Plot Draw
            ;; An entry.
            ;; Also: OLD (TEST)
            X:
                rts
            .endmacro
            .endscope
            .scope Basic
                Plot 1
            .endscope
            """;

        // So is one around an inner macro's definition in an outer macro's body.
        const string Nested = """
            .macro Outer
            .scope Draw
            .macro Plot Draw
            ;; An entry.
            ;; Also: OLD (TEST)
            X:
                rts
            .endmacro
            .endscope
            .endmacro
                Outer
            .scope Basic
                Plot 1
            .endscope
            """;

        // A scope a parameter names is reported once, as a scope, which no build gives an old name.
        const string NamedScope = """
            .macro Entry name
            ;; An entry.
            ;; Also: OLD (TEST)
            .scope name
            .endscope
            .endmacro
                Entry Foo
            """;

        Check(NamedScope).Should().ContainSingle().Which.Message.Should().Contain("is a scope or type");

        // So is one expanded twice: a scope has no old name in any build, however many times it's expanded.
        string twice = NamedScope.Replace("Entry name", "Entry", StringComparison.Ordinal)
            .Replace(".scope name", ".scope Block", StringComparison.Ordinal)
            .Replace("    Entry Foo", ".scope A\n    Entry\n.endscope\n.scope B\n    Entry\n.endscope", StringComparison.Ordinal);

        Assemble(twice).Diagnostics.Should().BeEmpty();
        Check(twice).Should().ContainSingle().Which.Message.Should().Contain("is a scope or type");

        // A .define's name isn't qualified by the scopes around it, so a parameter that names it is still found.
        const string Defined = """
            .macro Outer
            .scope S
            .macro Inner P
            ;; A count.
            ;; Also: OLD (TEST)
            .define P 5
            .endmacro
            .endscope
            .endmacro
            """;

        Check(Defined).Should().ContainSingle().Which.Message.Should().StartWith("Also: P is named by a parameter");

        foreach (string text in (string[])[Around, Nested])
        {
            Assemble(text + "\n    jsr OLD\n").Diagnostics.Should().BeEmpty();
            Check(text).Should().BeEmpty();
            DocumentationSet set = Set(text);
            DocumentationTopic topic = set.FindAlso("OLD", thisBuild: true).Should().ContainSingle().Which;
            set.SymbolOf(topic, "OLD").Should().Be("Basic::X");
        }
    }

    /// <summary>
    ///  Names that differ by expansion reach nothing in the documentation either, though the build expands the macro
    ///  once: no link, hint or definition by the old name.
    /// </summary>
    [TestMethod]
    public void OldNamesThatVaryByExpansionAreNotDocumented()
    {
        DocumentationSet parameter = Set("""
            .macro Entry name
            ;; An entry.
            ;; Also: OLD (TEST)
            name:
                rts
            .endmacro
                Entry Start
            """);

        parameter.FindAlso("OLD", thisBuild: true).Should().BeEmpty();

        DocumentationSet local = Set("""
            .macro Delay
                .local again
            ;; Waits.
            ;; Also: OLD (TEST)
            again:
                dex
                bne again
            .endmacro
                Delay
            """);

        local.FindAlso("OLD", thisBuild: true).Should().BeEmpty();
    }

    /// <summary>
    ///  Lines on opposite branches of an <c>.if</c> in a macro's body are no different builds: two expansions take one
    ///  each, so an old name both give clashes, as the assembler finds.
    /// </summary>
    [TestMethod]
    public void OldNamesOnBothBranchesOfAMacroClash()
    {
        const string Text = """
            .macro Library flag
            .if flag
            ;; One reader.
            ;; Also: OLD (TEST)
            COMBYT:
            .else
            ;; Another.
            ;; Also: OLD (TEST)
            COMBYT2:
            .endif
                rts
            .endmacro
                Library 1
                Library 0
            """;

        Assemble(Text + "\n    jsr OLD\n").Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("historical name");
        Check(Text).Select(diagnostic => diagnostic.Message).Should().BeEquivalentTo(
            "Also: COMBYT2 has the historical name OLD too.",
            "Also: COMBYT has the historical name OLD too.");
    }

    /// <summary>
    ///  A condition in a macro's body never puts a definition in another build, beside another macro's or one outside
    ///  any macro: an old name both give clashes, as the assembler finds.
    /// </summary>
    [TestMethod]
    public void OldNamesUnderConditionsInMacrosClashWithOthers()
    {
        const string TwoMacros = """
            .macro First flag
            .if flag
            ;; One reader.
            ;; Also: OLD (TEST)
            ONE:
            .endif
                rts
            .endmacro
            .macro Second flag
            .if flag
                nop
            .else
            ;; Another.
            ;; Also: OLD (TEST)
            TWO:
            .endif
                rts
            .endmacro
                First 1
                Second 0
            """;

        Assemble(TwoMacros + "\n    jsr OLD\n").Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("historical name");
        Check(TwoMacros).Select(diagnostic => diagnostic.Message).Should().BeEquivalentTo(
            "Also: TWO has the historical name OLD too.",
            "Also: ONE has the historical name OLD too.");

        const string Outside = """
            .macro First
            .ifdef MODEL
            ;; One reader.
            ;; Also: OLD (TEST)
            ONE:
            .endif
                rts
            .endmacro
            .ifndef MODEL
            ;; Another.
            ;; Also: OLD (TEST)
            TWO:
                rts
            .endif
            MODEL = 1
                First
            """;

        Assemble(Outside + "\n    jsr OLD\n").Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("historical name");
        Check(Outside).Select(diagnostic => diagnostic.Message).Should().BeEquivalentTo(
            "Also: TWO has the historical name OLD too.",
            "Also: ONE has the historical name OLD too.");
    }

    /// <summary>
    ///  Two expansions in one scope are a duplicate symbol, which fails the assembly: its definitions are not known, so
    ///  the documentation resolves the old name to neither, as the assembler doesn't.
    /// </summary>
    [TestMethod]
    public void OldNamesInAMacroExpandedTwiceInOneScopeReachNothing()
    {
        string text = $"{MacroLibrary}\n    Library\n    Library\n";
        Assemble(text).Diagnostics.Select(diagnostic => diagnostic.Message).Should().ContainSingle()
            .Which.Should().Contain("Duplicate symbol");

        DocumentationSet set = Set(text);
        set.FindAlso("COMBYTE", thisBuild: true).Should().BeEmpty();
        set.AlsoOf(Required(set.Find("COMBYT"))).Should().BeEmpty();
    }

    /// <summary>
    ///  A definition outside a macro that shares a macro body's topic is in the build only where the assembly took its
    ///  branch: an <c>.ifdef</c> on a macro defined after it is skipped, so its old name is no clash.
    /// </summary>
    [TestMethod]
    public void OldNamesBesideAMacroFollowTheSkippedLines()
    {
        const string Text = """
            .ifdef LATER
            ;; One.
            ;; Also: OLD (TEST)
            FOO = 1
            .endif
            .macro LATER
            .endmacro
            .macro Library
            ;; Two.
            ;; Also: OLD (TEST)
            FOO:
                rts
            .endmacro
            .scope Basic
                Library
            .endscope
            """;

        Check(Text).Should().BeEmpty();
        DocumentationSet set = Set(Text);
        set.SymbolOf(set.FindAlso("OLD", thisBuild: true).Should().ContainSingle().Subject, "OLD").Should().Be("Basic::FOO");
    }

    /// <summary>
    ///  A definition outside a macro whose other branch only inherits shares that branch's old name in every build, as
    ///  without the macro: a macro's body that defines the same name doesn't change it.
    /// </summary>
    [TestMethod]
    public void InheritedOldNamesBesideAMacroAreShared()
    {
        const string Outside = """
            .ifdef WIDE
            ;; One.
            ;; Also: OLD (TEST)
            FOO = 1
            .else
            ;; Inherit:
            FOO = 2
            .endif
            ;; Another.
            ;; Also: OLD (TEST)
            BAR = 3
            """;

        const string Macro = """
            .macro Library
            ;; A reader.
            FOO:
                rts
            .endmacro
            .scope Basic
                Library
            .endscope
            """;

        string[] without = [.. Set(Outside).FindAlso("OLD", thisBuild: true).Select(topic => topic.Name)];
        without.Should().Equal("FOO", "BAR");
        Set(Macro + "\n" + Outside).FindAlso("OLD", thisBuild: true).Select(topic => topic.Name).Should().Equal(without);

        // With no branch the build takes, the definition gives nothing, as without the macro: no clash with BAR.
        string skipped = Outside.Replace(".else\n;; Inherit:\nFOO = 2\n", "", StringComparison.Ordinal);
        skipped.Should().NotContain("Inherit:");
        Set(Macro + "\n" + skipped).FindAlso("OLD", thisBuild: true).Select(topic => topic.Name).Should().Equal("BAR");
        Check(Macro + "\n" + skipped).Should().BeEmpty();

        // Branches that cite different documents share nothing with the inheriting one, as without the macro.
        const string Cited = """
            X = 3
            .if X = 1
            ;; One.
            ;; Also: OLD (TEST)
            FOO = 1
            .elseif X = 2
            ;; Two.
            ;; Also: OLD (BOOK)
            FOO = 2
            .else
            ;; Inherit:
            FOO = 3
            .endif
            ;; Another.
            ;; Also: OLD (TEST)
            BAR = 3
            """;

        string[] apart = [.. Set(Cited).FindAlso("OLD", thisBuild: true).Select(topic => topic.Name)];
        apart.Should().Equal("BAR");
        Set(Macro + "\n" + Cited).FindAlso("OLD", thisBuild: true).Select(topic => topic.Name).Should().Equal(apart);

        // Nor does an inheriting branch the build skips share anything, when it takes no branch at all.
        const string Neither = """
            X = 3
            .if X = 1
            ;; One.
            ;; Also: OLD (TEST)
            FOO = 1
            .elseif X = 2
            ;; Inherit:
            FOO = 2
            .endif
            ;; Another.
            ;; Also: OLD (TEST)
            BAR = 3
            """;

        string[] none = [.. Set(Neither).FindAlso("OLD", thisBuild: true).Select(topic => topic.Name)];
        none.Should().Equal("BAR");
        Set(Macro + "\n" + Neither).FindAlso("OLD", thisBuild: true).Select(topic => topic.Name).Should().Equal(none);
    }

    /// <summary>
    ///  The lint checks a definition outside a macro whose branch only inherits as it would without the macro: the
    ///  shared section's documents and clashes are reported alike.
    /// </summary>
    [TestMethod]
    public void InheritedOldNamesBesideAMacroAreChecked()
    {
        const string Outside = """
            .ifdef WIDE
            ;; One.
            ;; Also: OLD (NOSUCH)
            FOO = 1
            .else
            ;; Inherit:
            FOO = 2
            .endif
            ;; Another.
            ;; Also: OLD (TEST)
            BAR = 3
            """;

        const string Macro = """
            .macro Library
            ;; A reader.
            FOO:
                rts
            .endmacro
            .scope Basic
                Library
            .endscope
            """;

        string[] without = [.. Check(Outside).Select(diagnostic => diagnostic.Message).Order(StringComparer.Ordinal)];
        without.Should().Contain("Also: no document 'NOSUCH' in the bibliography.");
        Check(Macro + "\n" + Outside).Select(diagnostic => diagnostic.Message).Order(StringComparer.Ordinal)
            .Should().Equal(without);
    }

    /// <summary>
    ///  A section a macro's body and every branch outside it write alike is listed once, whichever branches the build
    ///  takes.
    /// </summary>
    [TestMethod]
    public void SectionsAMacroSharesAreListedOnce()
    {
        DocumentationSet set = Set("""
            .macro Library
            ;; A reader.
            ;; Also: MOLD (TEST)
            FOO:
                rts
            .endmacro
            .scope Basic
                Library
            .endscope
            X = 3
            .if X = 1
            ;; One.
            ;; Also: MOLD (TEST)
            FOO = 1
            .elseif X = 2
            ;; Two.
            ;; Also: MOLD (TEST)
            FOO = 2
            .endif
            """);

        Required(set.Find("FOO")).Sections.Where(section => section.Name == "Also").Should().ContainSingle()
            .Which.Condition.Should().BeNull();

        // A macro the build doesn't expand leaves the branches outside it as they would be without it.
        DocumentationSet unexpanded = Set("""
            .macro Library
            ;; A reader.
            FOO:
                rts
            .endmacro
            X = 3
            .if X = 1
            ;; One.
            ;; Also: MOLD (TEST)
            FOO = 1
            .elseif X = 2
            ;; Two.
            ;; Also: MOLD (TEST)
            FOO = 2
            .endif
            """);

        Required(unexpanded.Find("FOO")).Sections.Where(section => section.Name == "Also").Should().ContainSingle()
            .Which.Condition.Should().BeNull();

        // Whichever comes first in the file.
        DocumentationSet outsideFirst = Set("""
            X = 3
            .if X = 1
            ;; One.
            ;; Also: MOLD (TEST)
            FOO = 1
            .elseif X = 2
            ;; Two.
            ;; Also: MOLD (TEST)
            FOO = 2
            .endif
            .macro Library
            ;; A reader.
            ;; Also: MOLD (TEST)
            FOO:
                rts
            .endmacro
            .scope Basic
                Library
            .endscope
            """);

        Required(outsideFirst.Find("FOO")).Sections.Where(section => section.Name == "Also").Should().ContainSingle()
            .Which.Condition.Should().BeNull();
    }

    /// <summary>
    ///  Sections a macro's body shares a topic with are checked as without the macro: each definition's own, whatever
    ///  their order, none of a branch the build leaves out, and a <c>.set</c> variable's assignments each their own.
    /// </summary>
    [TestMethod]
    public void SectionsBesideAMacroAreCheckedAsWithoutIt()
    {
        const string Macro = """
            .macro Library
            ;; A reader.
            ;; Uses: two words
            FOO:
                rts
            .endmacro
            .scope Basic
                Library
            .endscope
            """;

        const string Built = """
            X = 1
            .if X = 1
            ;; One.
            ;; Uses: two words
            FOO = 1
            .else
            ;; Two.
            FOO = 2
            .endif
            """;

        Check(Macro + "\n" + Built).Count(diagnostic => diagnostic.Rule == DocumentationRules.Sections).Should().Be(2);

        // With another branch in the build, the skipped branch's sections are checked, as without the macro; with no
        // branch outside the macro in the build, none are, as without the macro the topic isn't this build's.
        string skipped = "X = 2" + Built["X = 1".Length..];
        skipped.Should().Contain(".if X = 1");
        string plainMacro = Macro.Replace(";; Uses: two words\n", "", StringComparison.Ordinal);
        plainMacro.Should().NotContain("Uses");
        string[] alone = [.. Check(skipped).Select(diagnostic => diagnostic.Message)];
        alone.Should().ContainSingle();
        Check(plainMacro + "\n" + skipped).Select(diagnostic => diagnostic.Message).Should().Equal(alone);

        string none = skipped[..skipped.IndexOf(".else", StringComparison.Ordinal)] + ".endif\n";
        Check(plainMacro + "\n" + none).Should().BeEmpty();

        // Nor its links and references.
        Check(plainMacro + "\nTALL = 1\n.ifdef WIDE\n;; Reads <NOSUCH> and {x}.\nFOO = 1\n.endif\n").Should().BeEmpty();

        // Nor what it inherits or includes.
        foreach (string section in (string[])[";; Inherit: <NOSUCH>", ";; Inherit: <FOO>", ";; Include: nofile.txt"])
        {
            string outside = $"TALL = 1\n.ifdef WIDE\n;; One.\n{section}\nFOO = 1\n.endif\n";
            Check(outside.Replace("TALL", "WIDE", StringComparison.Ordinal)).Should().NotBeEmpty();
            Check(plainMacro + "\n" + outside).Should().BeEmpty();
        }

        Check("""
            ;; One.
            ;; Uses: two words
            Count .set 0
            ;; Two.
            ;; Uses: two words
            Count .set 1
            ;; Three.
            Count .set 2
            """).Count(diagnostic => diagnostic.Rule == DocumentationRules.Sections).Should().Be(2);
    }

    /// <summary>
    ///  Where the build's macro expansions aren't known, as in the editor while a file has errors, a definition outside
    ///  a macro keeps its own old name, and an exclusion in a branch the build skips isn't reported unused, both as
    ///  without the macro.
    /// </summary>
    [TestMethod]
    public void DefinitionsBesideAMacroKeepTheirNamesWhereExpansionsArentKnown()
    {
        const string Outside = """
            .ifdef WIDE
            ;; One.
            ;; Also: OLD (TEST)
            FOO = 1
            .endif
            ;; Another.
            ;; Also: OLD (TEST)
            BAR:
                jmp NOWHERE
            """;

        const string Macro = """
            .macro Library
            ;; A reader.
            FOO = 5
            .endmacro
            .scope S
                Library
            .endscope
            """;

        // As the editor creates a set for an assembly with errors: no definitions, so no expansions are known.
        static string[] Found(string text)
        {
            AssemblyResult result = Assemble(text);
            result.Success.Should().BeFalse();
            DocumentationSet set = DocumentationSet.Create(
                [DocumentationParser.Parse(text, "test.asm")],
                new Dictionary<string, long> { ["FOO"] = 1, ["BAR"] = 0x1000 },
                skippedLines: result.SkippedLines);

            return [.. set.FindAlso("OLD", thisBuild: true).Select(topic => topic.Name)];
        }

        string[] without = Found(Outside);
        without.Should().Equal("FOO", "BAR");
        Found(Outside + "\n" + Macro).Should().Equal(without);

        const string Excluded = """
            TALL = 1
            .ifdef WIDE
            ; retrocore: ignore=link
            ;; One, through <Nowhere>.
            FOO = 1
            .endif
            """;

        static List<DocumentationDiagnostic> Lint(string text)
        {
            DocumentationBibliography bibliography = DocumentationBibliography.Parse(Bibliography);
            return new DocumentationResolver(Set(text)) { Bibliography = bibliography }.Lint();
        }

        Lint(Excluded).Should().BeEmpty();
        Lint(Excluded + "\n" + Macro).Should().BeEmpty();

        // A macro's body's own Also: is still checked where its expansions aren't known, as any other.
        string cited = ".macro Library\n;; A reader.\n;; Also: COUT (NOSUCH)\nREADER:\n    rts\n.endmacro\n    Library\n";
        DocumentationSet unknown = DocumentationSet.Create(
            [DocumentationParser.Parse(cited, "test.asm")],
            new Dictionary<string, long> { ["READER"] = 0x1000 });

        DocumentationBibliography bibliography = DocumentationBibliography.Parse(Bibliography);
        DocumentationResolver resolver = new(unknown) { Bibliography = bibliography };
        List<DocumentationDiagnostic> found = resolver.Check();
        found.Select(diagnostic => diagnostic.Message).Should().Equal("Also: no document 'NOSUCH' in the bibliography.");

        // An assembly with errors may stop short of its expansions, so they aren't known from it either.
        string failing = cited + "    jmp NOWHERE\n";
        AssemblyResult failed = Assemble(failing);
        failed.Success.Should().BeFalse();
        DocumentationSet partial = DocumentationSet.Create([DocumentationParser.Parse(failing, "test.asm")], failed);
        DocumentationResolver checker = new(partial) { Bibliography = bibliography };
        checker.Check().Select(diagnostic => diagnostic.Message).Should()
            .Contain("Also: no document 'NOSUCH' in the bibliography.");
    }

    /// <summary>
    ///  An outside definition in a branch the build leaves out goes unchecked only beside a macro's body that documents
    ///  the same name: a topic without one is checked as before, the macro's own sections still are, and in a strict
    ///  file the skipped branch's prose isn't held to the build's names either.
    /// </summary>
    [TestMethod]
    public void OnlyOutsideBranchesBesideAMacroGoUnchecked()
    {
        // No macro: a type in a skipped branch is still the build's topic, and its links are checked.
        const string Plain = """
            TALL = 1
            .scope Shapes
            .ifdef WIDE
            ;; Reads <NOSUCH>.
            .struct Point
                x .byte
            .endstruct
            .endif
            .endscope
            """;

        Check(Plain).Should().Contain(diagnostic => diagnostic.Rule == DocumentationRules.Link);

        // The macro's own section, under a condition of its body, is checked beside a skipped outside branch.
        const string Conditioned = """
            .macro Library
            .if 1
            ;; A reader.
            ;; Also: OLD (NOSUCH)
            FOO:
                rts
            .endif
            .endmacro
            .scope S
                Library
            .endscope
            TALL = 1
            .ifdef WIDE
            ;; One.
            FOO = 1
            .endif
            """;

        Check(Conditioned).Select(diagnostic => diagnostic.Message).Should()
            .Contain("Also: no document 'NOSUCH' in the bibliography.");

        // In a strict file, the skipped branch's prose naming a documented definition isn't reported unlinked.
        const string Strict = """
            ; retrocore: style=strict
            ;; A probe.

            ;; Tall.
            TALL = 1

            ;; Emits the reader.
            .macro Library
                ;; A reader.
            FOO:
                rts
            .endmacro

            ;; The reader's scope.
            .scope S
                Library
            .endscope

            .ifdef WIDE
            ;; Reads TALL and sets it.
            FOO = 1
            .endif
            """;

        Check(Strict.Replace("Library\n.endscope", "\n.endscope", StringComparison.Ordinal)
            .Replace(".ifdef WIDE", ".ifdef TALL", StringComparison.Ordinal)).Should()
            .Contain(diagnostic => diagnostic.Rule == DocumentationRules.UnlinkedName);

        Check(Strict).Should().NotContain(diagnostic => diagnostic.Rule == DocumentationRules.UnlinkedName);
    }

    /// <summary>
    ///  An old name two definitions of one topic give, two macros' bodies or a body and a definition outside them, is
    ///  ambiguous in a link, as the assembler finds it in code; one only the outside definition gives still reaches it.
    /// </summary>
    [TestMethod]
    public void AnOldNameTwoDefinitionsOfATopicGiveIsAmbiguous()
    {
        const string TwoMacros = """
            .macro A
            ;; A reader.
            ;; Also: OLD (TEST)
            COMBYT:
                rts
            .endmacro
            .macro B
            ;; B reader.
            ;; Also: OLD (TEST)
            COMBYT:
                rts
            .endmacro
            .scope SA
                A
            .endscope
            .scope SB
                B
            .endscope
            ;; Uses <OLD>.
            Echo:
                rts
            """;

        Assemble(TwoMacros + "\n    jsr OLD\n").Diagnostics.Should().ContainSingle().Which.Message.Should()
            .Contain("SA::COMBYT and SB::COMBYT");

        Linked(TwoMacros, "OLD").Kind.Should().Be(DocumentationTargetKind.Ambiguous);

        const string Beside = """
            .macro Lib
            ;; A reader.
            ;; Also: MOLD (TEST)
            COMBYT:
                rts
            .endmacro
            .scope Basic
                Lib
            .endscope
            ;; The other reader.
            ;; Also: MOLD (TEST), OWN (TEST)
            COMBYT:
                rts
            ;; Uses <MOLD> and <OWN>.
            Echo:
                rts
            """;

        Assemble(Beside + "\n    jsr MOLD\n").Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("MOLD");
        Linked(Beside, "MOLD").Kind.Should().Be(DocumentationTargetKind.Ambiguous);
        DocumentationTarget own = Linked(Beside, "OWN");
        own.Kind.Should().NotBe(DocumentationTargetKind.Ambiguous);
        own.Name.Should().Be("COMBYT");

        static DocumentationTarget Linked(string text, string name)
        {
            DocumentationSet set = Set(text);
            return new DocumentationResolver(set).Resolve(set.Find("Echo") ?? throw new AssertFailedException("No Echo."), name);
        }
    }

    /// <summary>
    ///  A link by the name a macro's expansion defined, from inside its scope or qualified, reaches the body's topic
    ///  with the symbol's own value, as a link by its old name does.
    /// </summary>
    [TestMethod]
    public void LinksByAnExpansionsNameReachItsTopic()
    {
        string text = $$"""
            {{MacroLibrary}}
            .scope Basic
                Library
            ;; Reads through <COMBYT> and <Basic::COMBYT>.
            Echo:
                rts
            .endscope
            """;

        DocumentationSet set = Set(text);
        DocumentationTopic echo = set.Find("Basic::Echo") ?? throw new AssertFailedException("No Echo.");
        DocumentationResolver resolver = new(set);
        foreach (string name in (string[])["COMBYT", "Basic::COMBYT"])
        {
            DocumentationTarget target = resolver.Resolve(echo, name);
            (target.Topic?.Name).Should().Be("COMBYT");
            target.Name.Should().Be("Basic::COMBYT");
            target.Value.Should().Be(set.Symbols["Basic::COMBYT"]);
        }
    }

    private static List<DocumentationDiagnostic> Check(string text) =>
        new DocumentationResolver(Set(text)) { Bibliography = DocumentationBibliography.Parse(Bibliography) }.Check();
}
