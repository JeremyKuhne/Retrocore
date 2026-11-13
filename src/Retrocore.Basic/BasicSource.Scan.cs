// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

public sealed partial class BasicSource
{
    private void Scan(BasicDialect dialect)
    {
        List<BasicSite> sites = [];
        List<BasicDiagnostic> diagnostics = [.. Parse.Diagnostics];
        List<BasicSourceLine> numbered = [];
        HashSet<string> foreign = ForeignWords(dialect);
        IReadOnlyDictionary<string, BasicLabel> labels = Parse.Labels;
        foreach (BasicLabel label in labels.Values)
        {
            string written = Lines[label.Line][label.Start..label.End];
            sites.Add(new(BasicSiteKind.Label, label.Line, label.Start, label.End, written) { Number = label.Number });
        }

        foreach (BasicTextLine text in Parse.Lines)
        {
            int index = text.Line;
            string line = Lines[index];
            int number = text.Number;
            int start = text.Numbered ? line.Length - line.TrimStart(' ').Length : text.Column;
            int end = start;
            while (text.Numbered && end < line.Length && char.IsAsciiDigit(line[end])) { end++; }
            if (text.Numbered)
            {
                sites.Add(new(BasicSiteKind.LineNumber, index, start, end, line[start..end]) { Number = number });
            }

            List<(int Start, int End)> skip = [];
            foreach ((int from, int to, string name, _, string word) in BasicProgram.LabelReferences(dialect, text.Statements, labels))
            {
                if (!labels.TryGetValue(name, out BasicLabel? label)) { continue; }
                int column = text.Column + from;
                skip.Add((column, text.Column + to));
                sites.Add(new(BasicSiteKind.LineReference, index, column, text.Column + to, line[column..(text.Column + to)])
                {
                    Number = label.Number,
                    Via = word
                });
            }

            ScanLine(dialect, index, line, text.Statements, sites, diagnostics, foreign, skip, out List<BasicStatement> starts);
            byte[] tokens = Stored(dialect, text, labels, starts);
            if (number < 0) { continue; }
            BasicSourceLine entry = new(index, number, start, end, tokens, starts);
            numbered.Add(entry);
            _numbered.TryAdd(number, entry);
            if (line.TrimEnd().Length > dialect.InputLimit)
            {
                diagnostics.Add(new(
                    index,
                    BasicSeverity.Warning,
                    $"The line is longer than the {dialect.InputLimit} characters {dialect.DisplayName} lets you type; it can be stored, but not typed or edited on the machine.",
                    dialect.InputLimit,
                    line.Length));
            }
        }

        foreach (BasicSite site in sites)
        {
            if (site.Kind == BasicSiteKind.LineReference && !_numbered.ContainsKey(site.Number))
            {
                diagnostics.Add(new(site.Line, BasicSeverity.Warning, $"There is no line {site.Number}.", site.Start, site.End));
            }
        }

        Sites = [.. sites.OrderBy(site => site.Line).ThenBy(site => site.Start)];
        NumberedLines = numbered;
        Diagnostics = [.. diagnostics.OrderBy(diagnostic => diagnostic.Line).ThenBy(diagnostic => diagnostic.Start)];
    }

    // Words other dialects reserve that this one does not, which this one reads as variable names. Integer BASIC's
    // and Business BASIC's names are any length, so a word such as LOC is an ordinary name there; Integer BASIC's
    // tokenizer refuses another BASIC's statements itself.
    private static HashSet<string> ForeignWords(BasicDialect dialect)
    {
        HashSet<string> foreign = new(StringComparer.Ordinal);
        if (dialect is IntegerBasicDialect || dialect == BasicDialect.BusinessBasic) { return foreign; }
        HashSet<string> own = [.. dialect.AllKeywords.Select(Letters)];
        foreach (BasicDialect other in (BasicDialect[])[BasicDialect.AppleSoft, BasicDialect.Level2])
        {
            foreach (string word in other.Keywords.Select(Letters))
            {
                if (word.Length >= 2 && !own.Contains(word)) { foreign.Add(word); }
            }
        }

        return foreign;

        static string Letters(string keyword) => new([.. keyword.Where(char.IsAsciiLetter)]);
    }

    // The line as BASIC stores it, its labels made numbers; its statements' offsets are in those bytes, which a label
    // longer or shorter than its number moves, while their columns stay the text's.
    private static byte[] Stored(
        BasicDialect dialect,
        BasicTextLine text,
        IReadOnlyDictionary<string, BasicLabel> labels,
        List<BasicStatement> starts)
    {
        string resolved = BasicProgram.Resolved(dialect, text, labels);
        if (dialect is IntegerBasicDialect)
        {
            // Integer BASIC's stored tokens are not the Microsoft form the scanner read, so its offsets are found in
            // the stored tokens themselves.
            byte[] stored;
            try
            {
                stored = dialect.Tokenize(resolved);
            }
            catch (FormatException)
            {
                return [];
            }

            List<int> storedOffsets = IntegerBasicDialect.StatementOffsets(stored);
            for (int index = 0; index < starts.Count && index < storedOffsets.Count; index++)
            {
                starts[index] = starts[index] with { Offset = storedOffsets[index] };
            }

            return stored;
        }

        CrunchOutput output;
        try
        {
            output = dialect.Crunch(BasicText.Parse(resolved, []));
        }
        catch (FormatException)
        {
            return [];
        }

        byte[] bytes = output.ToArray();
        if (resolved == text.Statements) { return bytes; }
        int[] columns = [.. Enumerable.Range(0, resolved.Length + 1)];
        BasicLineScanner scanner = new(dialect, text.Line, resolved, bytes, output.Positions, columns, []);
        List<BasicStatement> offsets = scanner.Statements();
        for (int index = 0; index < starts.Count && index < offsets.Count; index++)
        {
            starts[index] = starts[index] with { Offset = offsets[index].Offset };
        }

        return bytes;
    }

    private static byte[] ScanLine(
        BasicDialect dialect,
        int index,
        string line,
        string statements,
        List<BasicSite> sites,
        List<BasicDiagnostic> diagnostics,
        HashSet<string> foreign,
        List<(int Start, int End)> skip,
        out List<BasicStatement> starts)
    {
        int offset = line.Length - statements.Length;
        starts = [new(0, offset + (statements.Length - statements.TrimStart(' ').Length))];
        List<int> columns = [];
        CrunchOutput output;
        try
        {
            output = dialect.Crunch(BasicText.Parse(statements, columns));
        }
        catch (FormatException)
        {
            return [];
        }

        byte[] bytes = output.ToArray();
        IReadOnlyList<int> positions = output.Positions;
        int[] at = [.. columns.Select(column => column + offset)];
        BasicLineScanner scanner = new(dialect, index, line, bytes, positions, at, foreign, skip);
        scanner.Run(sites, diagnostics);
        starts = scanner.Statements();
        return bytes;
    }
}
