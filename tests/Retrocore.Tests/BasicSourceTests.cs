// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Tests;

/// <summary>
///  Verifies what the language server reads from BASIC text: line references, variables as BASIC names them,
///  warnings, keyword help and renumbering.
/// </summary>
[TestClass]
public sealed class BasicSourceTests
{
    private const string AppleSoft = """
        REM retrocore applesoft
        10 REM SETUP
        20 SCORE = 0: GOSUB 100
        30 IF SCORE > 5 THEN 10
        40 ON X GOTO 10,20,99
        50 LIST 10-20: X = 1E+5
        60 PRINT A$(1); A$; FN F(2): ELSE = 1
        100 DEF FN F(X) = X * 2: RETURN
        """;

    private const string Level2 = """
        ' retrocore level2
        10 IF A THEN 20 ELSE 30
        20 ON ERROR GOTO 0 : RESUME 0
        30 A#=1 'GOTO 99
        40 G O T O 10
        """;

    /// <summary>
    ///  Line references follow GOTO, GOSUB, THEN, ON and LIST, with their columns; a missing line is a warning.
    /// </summary>
    [TestMethod]
    public void LineReferencesAreFound()
    {
        BasicSource source = BasicSource.Analyze(AppleSoft);
        source.Dialect.Should().Be(BasicDialect.AppleSoft);
        Lines(source).Should().Equal("2:100", "3:10", "4:10", "4:20", "4:99", "5:10", "5:20");
        BasicSite gosub = source.Sites.Single(site => site.Kind == BasicSiteKind.LineReference && site.Number == 100);
        source.Lines[2][gosub.Start..gosub.End].Should().Be("100");
        source.Diagnostics.Should().Contain(diagnostic => diagnostic.Message == "There is no line 99." && diagnostic.Line == 4);

        source.References(gosub).Select(site => $"{site.Kind}:{site.Line}").Should().Equal("LineReference:2", "LineNumber:7");
        source.SiteAt(2, gosub.Start + 1).Should().Be(gosub);

        BasicSource level2 = BasicSource.Analyze(Level2);
        Lines(level2).Should().Equal("1:20", "1:30", "4:10");
        level2.Sites.Should().Contain(site => site.Kind == BasicSiteKind.Keyword && site.Text == "'" && site.Line == 3);
        level2.Sites.Should().Contain(site => site.Kind == BasicSiteKind.Keyword && site.Text == "G O T O");
    }

    /// <summary>
    ///  Names are what BASIC makes of them: SCORE is SC, an array is not the variable of the same name, and the
    ///  type and two letters decide which names are one variable.
    /// </summary>
    [TestMethod]
    public void VariablesAreNamedAsBasicReadsThem()
    {
        BasicSource source = BasicSource.Analyze(AppleSoft);
        string[] keys = [.. source.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Select(site => site.Key).Distinct()];
        keys.Should().Equal("SC", "E", "X", "A$(", "A$", "EL");
        source.Sites.Single(site => site.Kind == BasicSiteKind.Function && site.Line == 7).Key.Should().Be("F");
        source.Sites.Where(site => site.Kind == BasicSiteKind.Variable && site.Key == "SC").Should().HaveCount(2);
        BasicSource.Describe(source.Sites.First(site => site.Key == "A$(")).Should().Be("string array");

        string[] messages = [.. source.Diagnostics.Select(diagnostic => diagnostic.Message)];
        messages.Should().Contain(message => message.StartsWith("BASIC reads SCORE as SC OR E", StringComparison.Ordinal));
        messages.Should().Contain(message => message.StartsWith("ELSE is not a reserved word in AppleSoft", StringComparison.Ordinal));
        source.Diagnostics.Where(diagnostic => diagnostic.Line == 5).Should().BeEmpty("1E+5 is a number");

        BasicSource.Analyze(Level2).Sites.Single(site => site.Kind == BasicSiteKind.Variable && site.Line == 3).Key.Should().Be("A#");
    }

    /// <summary>
    ///  Every reserved word of each dialect has help, and help has no words the dialects lack.
    /// </summary>
    /// <param name="name">The dialect.</param>
    [TestMethod]
    [DataRow("applesoft")]
    [DataRow("level2")]
    [DataRow("integer")]
    public void EveryKeywordHasHelp(string name)
    {
        BasicDialect dialect = BasicDialect.FromName(name) ?? throw new AssertFailedException(name);
        dialect.Keywords.Where(keyword => BasicKeywordHelp.Describe(dialect, keyword) is null).Should().BeEmpty();
        BasicKeywordHelp.Markdown(dialect, "PRINT").Should().Contain("PRINT");
    }

    /// <summary>
    ///  Renumbering changes each line and each reference to it, and leaves a reference to a missing line.
    /// </summary>
    [TestMethod]
    public void RenumberingFollowsReferences()
    {
        (string? text, IReadOnlyList<BasicDiagnostic> diagnostics) = BasicRenumber.Renumber(AppleSoft, start: 1000, step: 5);
        // Renumbering keeps the source's line endings, which depend on how this file was checked out.
        string[] lines = text?.ReplaceLineEndings("\n").Split('\n') ?? throw new AssertFailedException("The text did not renumber.");
        lines[2].Should().Be("1005 SCORE = 0: GOSUB 1030");
        lines[4].Should().Be("1015 ON X GOTO 1000,1005,99");
        lines[5].Should().Be("1020 LIST 1000-1005: X = 1E+5");
        lines[7].Should().StartWith("1030 DEF FN");
        diagnostics.Should().ContainSingle().Which.Message.Should().Contain("no line 99");

        string? level2 = BasicRenumber.Renumber(Level2, start: 10, step: 10).Text?.ReplaceLineEndings("\n");
        level2?.Split('\n')[1].Should().Be("10 IF A THEN 20 ELSE 30");
        BasicRenumber.Renumber(AppleSoft, start: 63990, step: 10).Text.Should().BeNull();
    }

    // Each line reference as text line:number.
    private static IEnumerable<string> Lines(BasicSource source) =>
        source.Sites.Where(site => site.Kind == BasicSiteKind.LineReference).Select(site => $"{site.Line}:{site.Number}");
}
