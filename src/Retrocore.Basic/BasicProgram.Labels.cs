// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;

namespace Retrocore.Basic;

public sealed partial class BasicProgram
{
    // The words a line number follows, longest first where one starts another; and whether each takes a list
    // (ON X GOTO a,b) and must have a line (GOTO).
    private static readonly (string Word, bool List, bool Required)[] s_jumps =
    [
        ("GOSUB", true, true),
        ("GOTO", true, true),
        ("THEN", false, false),
        ("ELSE", false, false),
        ("RESUME", false, false),
        ("RESTORE", false, false),
        ("DELETE", false, false),
        ("LLIST", false, false),
        ("LIST", false, false),
        ("EDIT", false, false),
        ("DEL", false, false),
        ("RUN", false, false)
    ];

    /// <summary>
    ///  Finds where a statement line names a label in place of a line number.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A name after GOTO or GOSUB, and each in an ON list, is always a label, since BASIC takes only numbers there;
    ///   Integer BASIC takes expressions there, so for it a name is a label only when one of that name is defined.
    ///   After THEN, ELSE, RUN, LIST, RESUME and the like, a name is a label only when one of that name is defined
    ///   and nothing but the statement's end follows it, so <c>THEN A = 1</c> stays an assignment.
    ///  </para>
    /// </remarks>
    /// <param name="dialect">The dialect, for its remarks.</param>
    /// <param name="text">The statements.</param>
    /// <param name="labels">The labels defined.</param>
    /// <returns>
    ///  Each reference: where it is, the label's uppercase name, whether it must be a label, and the word it follows.
    /// </returns>
    public static List<(int Start, int End, string Name, bool Required, string Word)> LabelReferences(
        BasicDialect dialect,
        string text,
        IReadOnlyDictionary<string, BasicLabel> labels)
    {
        ArgumentNullException.ThrowIfNull(dialect);
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(labels);
        List<(int, int, string, bool, string)> references = [];
        bool inString = false;
        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            if (inString)
            {
                inString = character != '"';
                continue;
            }

            if (character == '"')
            {
                inString = true;
                continue;
            }

            if (character == '\'' && dialect == BasicDialect.Level2) { break; }
            if (StartsWord(text, index, "REM")) { break; }
            if (StartsWord(text, index, "DATA"))
            {
                index = SkipData(text, index);
                continue;
            }

            if (Jump(text, index, out int after) is not { } jump) { continue; }
            index = Targets(text, after, jump, labels, references) - 1;
        }

        // Integer BASIC's GOTO and GOSUB take any expression, such as GOSUB T, so a name is a label only when one of
        // that name is defined.
        if (dialect == BasicDialect.Integer)
        {
            references.RemoveAll(reference => !labels.ContainsKey(reference.Item3));
            for (int index = 0; index < references.Count; index++)
            {
                references[index] = references[index] with { Item4 = false };
            }
        }

        return references;
    }

    /// <summary>
    ///  Gets a line's statements with each label it names replaced by its line's number, as they are stored.
    /// </summary>
    /// <param name="dialect">The dialect.</param>
    /// <param name="line">The line.</param>
    /// <param name="labels">The labels.</param>
    /// <returns>The statements.</returns>
    internal static string Resolved(BasicDialect dialect, BasicTextLine line, IReadOnlyDictionary<string, BasicLabel> labels) =>
        Resolve(dialect, line, new Dictionary<string, BasicLabel>(labels), []);

    // Puts the numbers of the labels a line names in place of their names.
    private static string Resolve(
        BasicDialect dialect,
        BasicTextLine line,
        Dictionary<string, BasicLabel> labels,
        List<BasicDiagnostic> diagnostics)
    {
        string text = line.Statements;
        if (labels.Count == 0 && !text.Contains("GO", StringComparison.OrdinalIgnoreCase)) { return text; }
        List<(int Start, int End, string Name, bool Required, string Word)> references = LabelReferences(dialect, text, labels);
        for (int index = references.Count - 1; index >= 0; index--)
        {
            (int start, int end, string name, bool required, _) = references[index];
            if (labels.TryGetValue(name, out BasicLabel? label))
            {
                text = $"{text[..start]}{label.Number}{text[end..]}";
            }
            else if (required)
            {
                Error(diagnostics, line.Line, $"There is no label {name}.", line.Column + start, line.Column + end);
            }
        }

        return text;
    }

    // The jump word starting at an index, and where the text after it starts.
    private static (string Word, bool List, bool Required)? Jump(string text, int index, out int after)
    {
        after = index;
        if (index > 0 && char.IsAsciiLetterOrDigit(text[index - 1])) { return null; }
        if (GoTo().Match(text, index) is { Success: true } go && go.Index == index)
        {
            after = index + go.Length;
            return s_jumps[1];
        }

        foreach ((string word, bool list, bool required) jump in s_jumps)
        {
            if (string.Compare(text, index, jump.word, 0, jump.word.Length, StringComparison.OrdinalIgnoreCase) == 0)
            {
                after = index + jump.word.Length;
                return jump;
            }
        }

        return null;
    }

    // Reads the line numbers and labels after a jump word: one, or a list after GOTO and GOSUB.
    private static int Targets(
        string text,
        int at,
        (string Word, bool List, bool Required) jump,
        IReadOnlyDictionary<string, BasicLabel> labels,
        List<(int, int, string, bool, string)> references)
    {
        while (true)
        {
            at = SkipSpaces(text, at);
            if (Name().Match(text, at) is { Success: true } name && name.Index == at)
            {
                string label = name.Groups["name"].Value.ToUpperInvariant();
                int end = at + name.Length;
                int next = SkipSpaces(text, end);
                bool alone = next >= text.Length || text[next] == ':' || StartsWord(text, next, "ELSE");
                if (jump.Required || (labels.ContainsKey(label) && alone))
                {
                    references.Add((at, end, label, jump.Required, jump.Word));
                }

                at = end;
            }
            else
            {
                while (at < text.Length && char.IsAsciiDigit(text[at])) { at++; }
            }

            int separator = SkipSpaces(text, at);
            if (!jump.List || separator >= text.Length || text[separator] != ',') { return at; }
            at = separator + 1;
        }
    }

    private static int SkipSpaces(string text, int at)
    {
        while (at < text.Length && text[at] == ' ') { at++; }
        return at;
    }

    // Skips a DATA statement, which ends at a colon outside quotes.
    private static int SkipData(string text, int index)
    {
        bool inString = false;
        for (int at = index; at < text.Length; at++)
        {
            if (text[at] == '"') { inString = !inString; }
            if (text[at] == ':' && !inString) { return at; }
        }

        return text.Length;
    }

    private static bool StartsWord(string text, int index, string word) =>
        (index == 0 || !char.IsAsciiLetterOrDigit(text[index - 1]))
            && string.Compare(text, index, word, 0, word.Length, StringComparison.OrdinalIgnoreCase) == 0;

    [GeneratedRegex(@"GO\s+TO", RegexOptions.IgnoreCase)]
    private static partial Regex GoTo();

    [GeneratedRegex(@"@?(?<name>[A-Za-z_][A-Za-z0-9_]*)")]
    private static partial Regex Name();
}
