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

        result.Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("COMBYTE");
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
            """).Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0x60, 0x60);
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
            "Also: the macro Library is expanded 2 times, so COMBYT is defined 2 times and an old name can't reach "
                + "one of them; give the old name in prose.");

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

        Check($"{MacroLibrary}\n").Should().BeEmpty();

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
        Check(Text).Select(diagnostic => (diagnostic.Severity, diagnostic.Message)).Should().Equal((
            DocumentationSeverity.Error,
            "Also: COUNT is a .set variable in the macro Bump, which each assignment gives a new version, so an old "
                + "name can't reach it; give the old name in prose."));
    }

    private static List<DocumentationDiagnostic> Check(string text) =>
        new DocumentationResolver(Set(text)) { Bibliography = DocumentationBibliography.Parse(Bibliography) }.Check();
}
