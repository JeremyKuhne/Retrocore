// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Tests;

/// <summary>
///  Verifies BASIC text with labels: numbering, labels made numbers, the line map back to the text, and what the
///  language server finds in it.
/// </summary>
[TestClass]
public sealed class BasicLabelTests
{
    private const string Labeled = """
        REM retrocore applesoft step 5
            HOME
        loop:
            INPUT "AGAIN? "; A$
            IF A$ = "Y" THEN loop
            GOSUB @done
            END
        @done
            PRINT "BYE": RETURN
        100 REM pinned
            GOTO loop: PRINT
        """;

    /// <summary>
    ///  Integer BASIC files take labels too; as its GOTO and GOSUB take expressions, a name there that is no label
    ///  stays a variable.
    /// </summary>
    [TestMethod]
    public void IntegerBasicLabels()
    {
        BasicParseResult parsed = BasicProgram.Parse("""
            REM retrocore integer
                T=100
            loop:
                INPUT "AGAIN? ",A$
                IF A$="Y" THEN loop
                GOSUB @done: GOSUB T
                END
            @done
                PRINT "BYE": RETURN
            100 RETURN
            """);

        parsed.Diagnostics.Should().BeEmpty();
        parsed.Program?.ToText().Should().Be("""
            10 T=100
            20 INPUT "AGAIN? ",A$
            30 IF A$="Y" THEN 20
            40 GOSUB 60: GOSUB T
            50 END
            60 PRINT "BYE": RETURN
            100 RETURN

            """.ReplaceLineEndings("\n"));
    }

    /// <summary>
    ///  THEN GOTO and THEN GOSUB take a label: the word after THEN that is no label is read as the jump it is.
    /// </summary>
    /// <param name="dialect">The dialect.</param>
    /// <param name="listed">How the line lists.</param>
    [TestMethod]
    [DataRow("applesoft", "20 IF T<3 THEN GOTO 10")]
    [DataRow("business", "20 IF T<3 THEN GOTO 10")]
    public void ThenGotoTakesALabel(string dialect, string listed)
    {
        BasicParseResult parsed = BasicProgram.Parse($"REM retrocore {dialect}\nloop:\nT=T+1\nIF T<3 THEN GOTO loop\n");
        parsed.Diagnostics.Should().BeEmpty();
        parsed.Program?.ToText().Split('\n')[1].Should().Be(listed);
    }

    /// <summary>
    ///  Lines without numbers are numbered after the line before them, labels become their lines' numbers, and the
    ///  program maps back to its text lines.
    /// </summary>
    [TestMethod]
    public void LabelsCompileToNumbers()
    {
        BasicParseResult parsed = BasicProgram.Parse(Labeled);
        parsed.Diagnostics.Should().BeEmpty();
        parsed.Program?.ToText().Should().Be("""
            5 HOME
            10 INPUT "AGAIN? ";A$
            15 IF A$="Y" THEN 10
            20 GOSUB 30
            25 END
            30 PRINT "BYE": RETURN
            100 REM pinned
            105 GOTO 10: PRINT

            """.ReplaceLineEndings("\n"));

        parsed.SourceLines.Should().Equal(1, 3, 4, 5, 6, 8, 9, 10);
        parsed.Labels.Keys.Should().BeEquivalentTo("LOOP", "DONE");
        parsed.Labels["DONE"].Number.Should().Be(30);
    }

    /// <summary>
    ///  A name GOTO takes must be a label; numbers must rise through a labeled file and leave room for the lines
    ///  between them.
    /// </summary>
    [TestMethod]
    public void LabelProblemsAreReported()
    {
        Messages("REM retrocore applesoft\nGOTO nowhere\n").Should().Equal("There is no label NOWHERE.");
        string[] crowded = Messages("REM retrocore applesoft\n10 A=1\nB=2\n11 C=3\n");
        crowded.Should().Equal("There is no line number left for this line between 10 and 11.");
        Messages("REM retrocore applesoft\n20 A=1\nB=2\n10 C=3\n").Should().ContainMatch("Line 10 must come after line 30*");
        Messages("REM retrocore applesoft\nx:\nA=1\nx:\nB=2\n").Should().Equal("The label X is already on line 2.");
        Messages("REM retrocore applesoft\nA=1\nend:\n").Should().BeEmpty("END: is a statement, not a label");
        Messages("REM retrocore applesoft\nA=1\nTHEN A = 1\n").Should().BeEmpty("a name after THEN is a label only if one is defined");
    }

    /// <summary>
    ///  The analysis finds labels and their references, and its statement offsets are the stored line's, where a
    ///  label longer than its number would move them.
    /// </summary>
    [TestMethod]
    public void LabelsAreSitesWithStoredOffsets()
    {
        BasicSource source = BasicSource.Analyze(Labeled);
        source.Diagnostics.Should().BeEmpty();
        BasicSite label = source.Sites.Single(site => site.Kind == BasicSiteKind.Label && site.Text == "loop:");
        label.Number.Should().Be(10);
        string[] uses = [.. source.References(label).Select(site => $"{site.Kind}:{site.Line}")];
        uses.Should().Equal("Label:2", "LineReference:4", "LineReference:10");
        source.Sites.Should().Contain(site => site.Kind == BasicSiteKind.LineReference && site.Text == "@done" && site.Via == "GOSUB");
        source.Sites.Should().NotContain(site => site.Kind == BasicSiteKind.Variable && site.Line == 4 && site.Text != "A$");

        BasicSourceLine last = source.LineNumbered(105) ?? throw new AssertFailedException("105");
        last.Line.Should().Be(10);
        last.Statements[1].Offset.Should().Be(4, "GOTO 10: is four bytes");
        last.Statements[1].Column.Should().Be(source.Lines[10].IndexOf("PRINT", StringComparison.Ordinal));
        source.LineNumbered(5)?.Statements[0].Column.Should().Be(4);
    }

    private static string[] Messages(string text) => [.. BasicProgram.Parse(text).Diagnostics.Select(diagnostic => diagnostic.Message)];
}
