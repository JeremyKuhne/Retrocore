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
    }

    private static List<DocumentationDiagnostic> Check(string text) =>
        new DocumentationResolver(Set(text)) { Bibliography = DocumentationBibliography.Parse(Bibliography) }.Check();
}
