// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;

namespace Retrocore.Basic;

public sealed partial class BasicProgram
{
    private const int DefaultStep = 10;

    /// <summary>
    ///  Reads a program from its text form: numbered lines, as they would be typed, and lines without numbers that
    ///  labels name.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The dialect is the one a first-line pragma names, else the one the file's double extension names, else
    ///   <paramref name="dialect"/>. Blank lines are skipped. In a file of numbered lines only, lines out of order
    ///   are put in order, as BASIC would, with a warning; a line number used twice is an error.
    ///  </para>
    ///  <para>
    ///   A label is a line of its own, <c>name:</c> or <c>@name</c>, and names the line after it. A line without a
    ///   number gets the number after the line before it, in steps of 10, or of the step the pragma gives
    ///   (<c>REM retrocore applesoft step 5</c>), and its leading spaces are only in the source. A numbered line
    ///   pins its number, so numbers must rise through the file. Wherever BASIC takes a line number, after GOTO,
    ///   GOSUB, THEN, ELSE, ON, RUN, LIST, RESUME and the like, a label stands for the number of its line.
    ///  </para>
    /// </remarks>
    /// <param name="text">The text.</param>
    /// <param name="dialect">The dialect when the text and path do not name one.</param>
    /// <param name="path">The file the text came from, for its extension.</param>
    /// <returns>
    ///  The program, or what is wrong with the text; with each line's number and the labels either way.
    /// </returns>
    public static BasicParseResult Parse(string text, BasicDialect? dialect = null, string? path = null)
    {
        ArgumentNullException.ThrowIfNull(text);
        string[] lines = text.ReplaceLineEndings("\n").Split('\n');
        List<BasicDiagnostic> diagnostics = [];
        int first = Array.FindIndex(lines, line => !string.IsNullOrWhiteSpace(line));
        bool skipPragma = false;
        int step = DefaultStep;
        string? named = path is null ? null : BasicText.DialectOfPath(path);
        if (first >= 0 && BasicText.Pragma(lines[first], out bool numbered) is { } pragma)
        {
            named = pragma;
            skipPragma = !numbered;
            if (PragmaStep().Match(lines[first]) is { Success: true } given)
            {
                step = Math.Max(1, int.Parse(given.Groups["step"].Value, System.Globalization.CultureInfo.InvariantCulture));
            }

        }

        if (named is not null)
        {
            BasicDialect? found = BasicDialect.FromName(named);
            if (found is null)
            {
                diagnostics.Add(new(
                    Math.Max(first, 0),
                    BasicSeverity.Error,
                    $"'{named}' is not a BASIC dialect; use applesoft, integer, level2, business or colorbasic."));

                return Failed(diagnostics);
            }

            // The original IIe's AppleSoft is still AppleSoft.
            dialect = dialect?.Name == found.Name ? dialect : found;
        }

        if (dialect is null)
        {
            diagnostics.Add(new(
                0,
                BasicSeverity.Error,
                "No dialect: start the file with REM retrocore applesoft or ' retrocore level2."));

            return Failed(diagnostics);
        }

        (List<BasicTextLine> statements, List<BasicLabel> marks) = Classify(dialect, lines, skipPragma ? first : -1);
        bool labeled = statements.Any(line => !line.Numbered) || marks.Count > 0;
        statements = Number(dialect, statements, step, labeled, diagnostics);
        Dictionary<string, BasicLabel> labels = Name(statements, marks, diagnostics);

        SortedDictionary<int, (BasicLine Line, int Source)> program = [];
        int previous = -1;
        foreach (BasicTextLine line in statements.Where(line => line.Number >= 0))
        {
            string resolved = Resolve(dialect, line, labels, diagnostics);
            Store(dialect, line, resolved, diagnostics, program, ref previous);
        }

        bool failed = diagnostics.Any(diagnostic => diagnostic.Severity == BasicSeverity.Error);
        return new(
            failed ? null : new BasicProgram(dialect, program.Values.Select(entry => entry.Line)),
            dialect,
            [.. diagnostics.OrderBy(diagnostic => diagnostic.Line)],
            failed ? [] : [.. program.Values.Select(entry => entry.Source)])
        {
            Lines = statements,
            Labels = labels
        };
    }

    private static void Error(List<BasicDiagnostic> diagnostics, int line, string message, int start = 0, int end = -1) =>
        diagnostics.Add(new(line, BasicSeverity.Error, message, start, end));

    private static BasicParseResult Failed(List<BasicDiagnostic> diagnostics) =>
        new(Program: null, Dialect: null, diagnostics, SourceLines: []);

    // Sorts the text's lines into statement lines, with their numbers if they have them, and label lines.
    private static (List<BasicTextLine> Statements, List<BasicLabel> Labels) Classify(
        BasicDialect dialect,
        string[] lines,
        int pragma)
    {
        List<BasicTextLine> statements = [];
        List<BasicLabel> labels = [];
        for (int index = 0; index < lines.Length; index++)
        {
            string line = lines[index];
            if (string.IsNullOrWhiteSpace(line) || index == pragma) { continue; }
            string trimmed = line.Trim();
            int indent = line.Length - line.TrimStart().Length;
            if (LabelLine().Match(trimmed) is { Success: true } label
                && !(trimmed.EndsWith(':') && dialect.AllKeywords.Contains(label.Groups["name"].Value.ToUpperInvariant())))
            {
                string name = label.Groups["name"].Value;
                labels.Add(new(name.ToUpperInvariant(), index, indent, indent + trimmed.Length, -1));
                continue;
            }

            if (char.IsAsciiDigit(trimmed[0]))
            {
                string after = dialect.SplitLineNumber(line, out int number);
                statements.Add(new(index, number, Numbered: true, line.Length - after.Length, after));
            }
            else
            {
                statements.Add(new(index, -1, Numbered: false, indent, line.TrimStart()));
            }
        }

        return (statements, labels);
    }

    // Gives each line without a number the next number after the line before it, below the next pinned number.
    private static List<BasicTextLine> Number(
        BasicDialect dialect,
        List<BasicTextLine> lines,
        int step,
        bool labeled,
        List<BasicDiagnostic> diagnostics)
    {
        List<BasicTextLine> numbered = new(lines.Count);
        int last = -1;
        for (int index = 0; index < lines.Count; index++)
        {
            BasicTextLine line = lines[index];
            if (line.Numbered)
            {
                if (line.Number > dialect.MaximumLineNumber)
                {
                    string past = $"Line {line.Number} is past {dialect.DisplayName}'s last line number, {dialect.MaximumLineNumber}.";
                    Error(diagnostics, line.Line, past);
                    numbered.Add(line with { Number = -1 });
                    continue;
                }

                if (labeled && line.Number <= last)
                {
                    string order = $"Line {line.Number} must come after line {last}: numbered lines keep their order with labels.";
                    Error(diagnostics, line.Line, order);
                }

                numbered.Add(line);
                last = Math.Max(last, line.Number);
                continue;
            }

            int next = lines.Skip(index + 1).FirstOrDefault(later => later.Numbered && later.Number > last)?.Number
                ?? dialect.MaximumLineNumber + 1;

            int candidate = last < 0 ? step : last + step;
            if (candidate >= next) { candidate = last + 1; }
            if (candidate >= next || candidate > dialect.MaximumLineNumber)
            {
                Error(diagnostics, line.Line, $"There is no line number left for this line between {last} and {next}.");
                numbered.Add(line);
                continue;
            }

            numbered.Add(line with { Number = candidate });
            last = candidate;
        }

        return numbered;
    }

    // Gives each label the number of the line after it.
    private static Dictionary<string, BasicLabel> Name(
        List<BasicTextLine> lines,
        List<BasicLabel> marks,
        List<BasicDiagnostic> diagnostics)
    {
        Dictionary<string, BasicLabel> labels = new(StringComparer.Ordinal);
        foreach (BasicLabel mark in marks)
        {
            BasicTextLine? after = lines.FirstOrDefault(line => line.Line > mark.Line && line.Number >= 0);
            if (after is null)
            {
                Error(diagnostics, mark.Line, $"The label {mark.Name} has no line after it.", mark.Start, mark.End);
                continue;
            }

            if (labels.TryGetValue(mark.Name, out BasicLabel? existing))
            {
                Error(diagnostics, mark.Line, $"The label {mark.Name} is already on line {existing.Line + 1}.", mark.Start, mark.End);
                continue;
            }

            labels[mark.Name] = mark with { Number = after.Number };
        }

        return labels;
    }

    private static void Store(
        BasicDialect dialect,
        BasicTextLine line,
        string statements,
        List<BasicDiagnostic> diagnostics,
        SortedDictionary<int, (BasicLine Line, int Source)> program,
        ref int previous)
    {
        int number = line.Number;
        int index = line.Line;
        byte[] tokens;
        try
        {
            tokens = dialect.Tokenize(statements);
        }
        catch (BasicSyntaxException exception)
        {
            int at = line.Column + exception.Column;
            diagnostics.Add(new(index, BasicSeverity.Error, exception.Message, at, at + 1));
            return;
        }
        catch (FormatException exception)
        {
            diagnostics.Add(new(index, BasicSeverity.Error, exception.Message));
            return;
        }

        if (tokens.All(value => value == ' '))
        {
            diagnostics.Add(new(
                index,
                BasicSeverity.Warning,
                $"Line {number} has no statements, so BASIC would delete it; it is left out."));

            return;
        }

        if (program.TryGetValue(number, out (BasicLine Line, int Source) existing))
        {
            Error(diagnostics, index, $"Line {number} is already on line {existing.Source + 1}.");
            return;
        }

        if (number < previous)
        {
            diagnostics.Add(new(
                index,
                BasicSeverity.Warning,
                $"Line {number} comes after line {previous}; BASIC keeps lines in order."));
        }

        previous = Math.Max(previous, number);
        program[number] = (new BasicLine(number, tokens), index);
    }

    [GeneratedRegex(@"^(?:@(?<name>[A-Za-z_][A-Za-z0-9_]*)|(?<name>[A-Za-z_][A-Za-z0-9_]*):)$")]
    private static partial Regex LabelLine();

    [GeneratedRegex(@"\bstep\s+(?<step>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex PragmaStep();
}
