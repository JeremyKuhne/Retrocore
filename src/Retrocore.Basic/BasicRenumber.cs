// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Renumbers BASIC text: every line, and every GOTO, GOSUB, THEN, ELSE, ON, RUN, LIST, RESUME and the like that
///  names one, keeping everything else as written.
/// </summary>
public static class BasicRenumber
{
    /// <summary>
    ///  Renumbers BASIC text, in line number order.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="start">The first line's new number.</param>
    /// <param name="step">How much each line's number is above the one before.</param>
    /// <param name="dialect">The dialect when the text and path do not name one.</param>
    /// <param name="path">The file the text came from, for its extension.</param>
    /// <returns>
    ///  The renumbered text, or null when the text has errors or the numbers would pass the dialect's last; and
    ///  the problems, including references to lines that do not exist, which are left as they are.
    /// </returns>
    public static (string? Text, IReadOnlyList<BasicDiagnostic> Diagnostics) Renumber(
        string text,
        int start,
        int step,
        BasicDialect? dialect = null,
        string? path = null)
    {
        ArgumentNullException.ThrowIfNull(text);
        BasicSource source = BasicSource.Analyze(text, dialect, path);
        if (source.Parse.Program is not { } program || source.Dialect is not { } basic)
        {
            return (null, [.. source.Diagnostics.Where(diagnostic => diagnostic.Severity == BasicSeverity.Error)]);
        }

        if (start < 0 || step < 1) { return Failed("The start must be 0 or more, and the step 1 or more."); }
        long last = start + ((long)program.Lines.Count - 1) * step;
        if (last > basic.MaximumLineNumber)
        {
            return Failed($"The last line would be {last}, past {basic.DisplayName}'s last line number, {basic.MaximumLineNumber}.");
        }

        Dictionary<int, int> numbers = [];
        for (int index = 0; index < program.Lines.Count; index++)
        {
            numbers[program.Lines[index].Number] = start + index * step;
        }

        List<BasicDiagnostic> diagnostics = [];
        string[] lines = [.. source.Lines];
        foreach (IGrouping<int, BasicSite> line in source.Sites
            .Where(site => site.Kind is BasicSiteKind.LineNumber or BasicSiteKind.LineReference && IsNumber(site.Text))
            .GroupBy(site => site.Line))
        {
            string current = lines[line.Key];
            foreach (BasicSite site in line.OrderByDescending(site => site.Start))
            {
                if (numbers.TryGetValue(site.Number, out int renumbered))
                {
                    string number = renumbered.ToString(System.Globalization.CultureInfo.InvariantCulture);
                    current = $"{current[..site.Start]}{number}{current[site.End..]}";
                }
                else
                {
                    diagnostics.Add(new(
                        site.Line,
                        BasicSeverity.Warning,
                        $"There is no line {site.Number}, so it is left as it is.",
                        site.Start,
                        site.End));
                }
            }

            lines[line.Key] = current;
        }

        string newLine = text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        return (string.Join(newLine, lines), diagnostics);
    }

    // Whether a site is written as a number, rather than a label, which keeps naming its line.
    private static bool IsNumber(string text) => text.Length > 0 && text.All(character => char.IsAsciiDigit(character) || character == ' ');

    private static (string? Text, IReadOnlyList<BasicDiagnostic> Diagnostics) Failed(string message) =>
        (null, [new BasicDiagnostic(0, BasicSeverity.Error, message)]);
}
