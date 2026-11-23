// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

public partial class AssemblyPreprocessorTests
{
    /// <summary>
    ///  The assembly reports the lines of branches it didn't take; the conditional directives' own lines are
    ///  assembled with the branch around them.
    /// </summary>
    [TestMethod]
    public void BranchesNotTakenAreSkipped()
    {
        AssemblyResult result = Assemble("""
            Value = 1
            .if Value = 1
            .byte 1
            .elseif Value = 2
            .byte 2
            .else
            .byte 3
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        AssemblySkippedLines skipped = Required(result.SkippedLines);
        skipped.IsComplete.Should().BeTrue();
        skipped.Skipped.Keys.Should().Equal(Path.GetFullPath("main.asm"));
        Runs(skipped, "main.asm").Should().Equal((4, 1), (6, 1));
        foreach (int line in (int[])[0, 1, 2, 3, 5, 7])
        {
            skipped.IsAssembled("main.asm", line).Should().BeTrue($"line {line} is assembled");
        }

        skipped.IsAssembled("main.asm", 8).Should().BeNull("the file has eight lines");
        skipped.IsAssembled("other.asm", 0).Should().BeNull("the assembly never opened the file");
    }

    /// <summary>
    ///  Inside a branch not taken, a nested conditional's directives and both its branches are skipped.
    /// </summary>
    [TestMethod]
    public void NestedConditionalsOfSkippedBranchesAreSkipped()
    {
        AssemblyResult result = Assemble("""
            .if 0
            .if 1
            .byte 1
            .else
            .byte 2
            .endif
            .endif
            .if 1
            .if 0
            .byte 3
            .endif
            .endif
            .byte 4
            """);

        result.Diagnostics.Should().BeEmpty();
        Runs(Required(result.SkippedLines), "main.asm").Should().Equal((1, 5), (9, 1));
    }

    /// <summary>
    ///  A file included twice is reported once: a line either inclusion assembled is assembled, and only a line
    ///  neither did is skipped.
    /// </summary>
    [TestMethod]
    public void AFileIncludedTwiceIsAssembledWhereEitherInclusionTookIt()
    {
        Resolver resolver = new();
        resolver.Add("part.inc", """
            .if Wide
            .byte 1
            .else
            .byte 2
            .endif
            .if 0
            .byte 3
            .endif
            """);

        AssemblyResult result = Assemble("""
            .set Wide, 1
            .include "part.inc"
            .set Wide, 0
            .include "part.inc"
            """, resolver);

        result.Diagnostics.Should().BeEmpty();
        AssemblySkippedLines skipped = Required(result.SkippedLines);
        skipped.IsComplete.Should().BeTrue();
        Runs(skipped, "part.inc").Should().Equal((6, 1));
        Runs(skipped, "main.asm").Should().BeEmpty();
    }

    /// <summary>
    ///  A file only a branch not taken includes is never opened, so the report has nothing for it: its include line is
    ///  skipped, and its own lines are neither assembled nor skipped.
    /// </summary>
    [TestMethod]
    public void AFileOnlyASkippedBranchIncludesHasNoLines()
    {
        Resolver resolver = new();
        resolver.Add("never.inc", ".byte 1\n");
        AssemblyResult result = Assemble("""
            .if 0
            .include "never.inc"
            .endif
            """, resolver);

        result.Diagnostics.Should().BeEmpty();
        AssemblySkippedLines skipped = Required(result.SkippedLines);
        skipped.Skipped.Keys.Should().Equal(Path.GetFullPath("main.asm"));
        skipped.IsAssembled("main.asm", 1).Should().BeFalse();
        skipped.IsAssembled("never.inc", 0).Should().BeNull();
    }

    /// <summary>
    ///  A macro's body is assembled with its definition, whatever an <c>.if</c> in it chooses in each expansion, and
    ///  skipped with a definition in a branch not taken.
    /// </summary>
    [TestMethod]
    public void MacroBodiesFollowTheirDefinitions()
    {
        AssemblyResult result = Assemble("""
            .macro Pick wide
            .if wide
            .byte 1
            .else
            .byte 2
            .endif
            .endmacro
            Pick 1
            .if 0
            .macro Never
            .byte 3
            .endmacro
            Pick 0
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[0].Should().Be(1);
        Runs(Required(result.SkippedLines), "main.asm").Should().Equal((9, 4));
    }

    /// <summary>
    ///  A <c>.repeat</c>'s body is assembled where some iteration took it: one repeated no times is skipped, as is a
    ///  branch in it no iteration took.
    /// </summary>
    [TestMethod]
    public void RepeatBodiesAreAssembledWhereAnIterationTookThem()
    {
        AssemblyResult result = Assemble("""
            .repeat 0
            .byte 1
            .endrepeat
            .repeat 2, I
            .if I = 5
            .byte 2
            .endif
            .if I = 1
            .byte 3
            .endif
            .endrepeat
            """);

        result.Diagnostics.Should().BeEmpty();
        Runs(Required(result.SkippedLines), "main.asm").Should().Equal((1, 1), (5, 1));
    }

    /// <summary>
    ///  An error in expansion leaves what was chosen before it trustworthy and everything from it on undecided; one
    ///  found once code is laid out, after every branch was chosen, leaves the report whole.
    /// </summary>
    [TestMethod]
    public void ErrorsLeaveLaterLinesUndecided()
    {
        AssemblyResult expansion = Assemble("""
            .ifdef Missing
            .byte 1
            .endif
            .bogus
            .if 0
            .byte 2
            .endif
            """);

        expansion.Success.Should().BeFalse();
        AssemblySkippedLines early = Required(expansion.SkippedLines);
        early.IsComplete.Should().BeFalse();
        early.IsAssembled("main.asm", 0).Should().BeTrue();
        early.IsAssembled("main.asm", 1).Should().BeFalse();
        early.IsAssembled("main.asm", 2).Should().BeTrue();
        early.Undecided[Path.GetFullPath("main.asm")].Should().Equal(new AssemblyLineRange(3, 4));
        early.IsAssembled("main.asm", 5).Should().BeNull();

        AssemblyResult layout = Assemble("""
            .if 0
            .byte 1
            .endif
            jmp Nowhere
            """);

        layout.Success.Should().BeFalse();
        AssemblySkippedLines whole = Required(layout.SkippedLines);
        whole.IsComplete.Should().BeTrue();
        whole.IsAssembled("main.asm", 1).Should().BeFalse();
        whole.IsAssembled("main.asm", 3).Should().BeTrue();

        // An unterminated conditional leaves everything from its opening on undecided.
        AssemblySkippedLines open = Required(Assemble(".byte 0\n.if 0\n.byte 1\n").SkippedLines);
        open.IsAssembled("main.asm", 0).Should().BeTrue();
        open.Undecided[Path.GetFullPath("main.asm")].Should().Equal(new AssemblyLineRange(1, 3));
    }

    /// <summary>
    ///  A source without preprocessing directives, parsed without the preprocessor, is assembled whole; the parse
    ///  reports the same as the assembly.
    /// </summary>
    [TestMethod]
    public void SourcesWithoutConditionalsAreAssembledWhole()
    {
        AssemblyParseResult parsed = NativeAssembler.Parse(new AssemblySource("nop\n; note\nnop", "main.asm"));
        AssemblySkippedLines skipped = Required(parsed.SkippedLines);
        skipped.IsComplete.Should().BeTrue();
        Runs(skipped, "main.asm").Should().BeEmpty();
        skipped.IsAssembled("main.asm", 2).Should().BeTrue();
        Required(Assemble("nop\nnop").SkippedLines).IsAssembled("main.asm", 1).Should().BeTrue();
    }

    /// <summary>
    ///  Merlin's <c>DO</c> and ca65's conditions are reported as native ones are.
    /// </summary>
    [TestMethod]
    public void OtherDialectsConditionalsAreReported()
    {
        AssemblyResult merlin = Assemble("""
            ; retrocore: dialect=merlin
                     DO 0
                     DFB 1
                     ELSE
                     DFB 2
                     FIN
            """);

        merlin.Diagnostics.Should().BeEmpty();
        Runs(Required(merlin.SkippedLines), "main.asm").Should().Equal((2, 1));

        AssemblyResult ca65 = new NativeAssembler().Assemble(
            new AssemblySource("; retrocore: dialect=ca65\n.ifdef Missing\n.byte 1\n.endif\n.byte 2\n", "main.s"),
            Options());

        ca65.Diagnostics.Should().BeEmpty();
        Runs(Required(ca65.SkippedLines), "main.s").Should().Equal((2, 1));
    }

    /// <summary>
    ///  MACRO-10 expands its conditionals with the rest of its text, so only the lines that made statements are known
    ///  to be assembled; the others are undecided rather than skipped.
    /// </summary>
    [TestMethod]
    public void Macro10LinesWithoutStatementsAreUndecided()
    {
        AssemblyParseResult parsed = NativeAssembler.Parse(new("; retrocore: dialect=macro10\n\tEXP\t1\n", "other.s"));
        parsed.Diagnostics.Should().BeEmpty();
        AssemblySkippedLines skipped = Required(parsed.SkippedLines);
        skipped.IsAssembled("other.s", 1).Should().BeTrue();
        skipped.IsAssembled("other.s", 0).Should().BeNull();
        Runs(skipped, "other.s").Should().BeEmpty();
    }

    /// <summary>
    ///  A project built by hand, not by parsing, has no report.
    /// </summary>
    [TestMethod]
    public void ProjectsBuiltByHandHaveNoReport()
    {
        AssemblyProject project = NativeAssembler.Parse(new AssemblySource("nop", "main.asm")).Project;
        AssemblyProject copy = new();
        foreach (AssemblyStatement statement in project.Statements) { copy.Statements.Add(statement); }
        new NativeAssembler().Assemble(copy, Options()).SkippedLines.Should().BeNull();
    }

    private static (int Start, int Count)[] Runs(AssemblySkippedLines skipped, string path) =>
        [.. skipped.Skipped[Path.GetFullPath(path)].Select(range => (range.Start, range.Count))];

    private static T Required<T>(T? value) where T : class =>
        value ?? throw new AssertFailedException("Expected a value.");
}
